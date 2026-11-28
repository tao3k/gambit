;;;============================================================================

;;; File: "context.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Scheduler State, Per-Carrier Worker Context, Lock-Free Carrier TLS & Freelist

;;;----------------------------------------------------------------------------
;;; Inline Thread-Local Carrier Context & Lazy #f Control-State Access

(define (%get-tc)
  (macro-thread-control-state (##current-thread)))

(define (%set-tc! val)
  (macro-thread-control-state-set! (##current-thread) val))

;;;----------------------------------------------------------------------------
;;; Scheduler, Worker Context & Per-Carrier Recycled %fiber-k Freelist

(define %MAX-LIFO-STREAK 8)
(define %MAX-FK-POOL 64)
(define %MAX-NURSERY-BATCH 32)

;; Unexported private sentinels (cannot collide with any user value)
(define %CH-EMPTY (cons 'ch-empty '()))
(define %CH-RETRY (cons 'ch-retry '()))

(define-type %fiber-k
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000006
  constructor: %make-fiber-k
  predicate: %fiber-k?
  (raw-k %fk-raw-k %fk-raw-k-set!)  ;; native Gambit continuation (cleared on recycle)
  (tc    %fk-tc    %fk-tc-set!)     ;; saved per-fiber thread control-state
  (val   %fk-val   %fk-val-set!)    ;; intrusive resume/send payload
  (next  %fk-next  %fk-next-set!))  ;; intrusive wait-queue / freelist link

(define-type %scheduler
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000001
  constructor: %make-scheduler
  predicate: %scheduler?
  (num-workers    %sched-num-workers)
  (deques         %sched-deques)         ;; vector of W %local-dq
  (global-q       %sched-global-q)       ;; lf-queue for external wakeups & overflow
  (global-pending %sched-global-pending) ;; 128B-padded pending count (>= global-q len)
  (spawned-vec    %sched-spawned-vec)    ;; vector of W 128B-padded monotonic counters
  (completed-vec  %sched-completed-vec)  ;; vector of W 128B-padded monotonic counters
  (root-done      %sched-root-done)      ;; fxatom (0 -> 1)
  (root-box       %sched-root-box)       ;; box holding (ok? . val-or-exc)
  (searching      %sched-searching)      ;; 128B-padded count of active steal-searchers
  (max-searching  %sched-max-searching)  ;; cap = max(1, W/2) preventing steal herds
  (parker         %sched-parker)         ;; off-heap OS futex/ulock parker handle
  (pcores         %sched-pcores))        ;; performance-core count for heterogeneous tiers

(define-type %worker-ctx
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000002
  constructor: %make-worker-ctx
  predicate: %worker-ctx?
  (sched        %wctx-sched)
  (wid          %wctx-wid)
  (dq           %wctx-dq)
  (spawned      %wctx-spawned)          ;; owner-only 128B-padded monotonic spawned
  (completed    %wctx-completed)        ;; owner-only 128B-padded monotonic completed
  (lifo         %wctx-lifo         %wctx-lifo-set!)         ;; private 1-slot LIFO (0 atomics!)
  (lifo-streak  %wctx-lifo-streak  %wctx-lifo-streak-set!)  ;; anti-starvation counter
  (ticks        %wctx-ticks        %wctx-ticks-set!)        ;; fairness poll counter
  (sched-k      %wctx-sched-k      %wctx-sched-k-set!)      ;; reusable trampoline continuation
  (fk-pool       %wctx-fk-pool       %wctx-fk-pool-set!)       ;; private %fiber-k freelist
  (fk-pool-len   %wctx-fk-pool-len   %wctx-fk-pool-len-set!)
  (steal-cursor  %wctx-steal-cursor  %wctx-steal-cursor-set!)  ;; sticky productive victim wid
  (nursery-cur   %wctx-nursery-cur   %wctx-nursery-cur-set!)   ;; target nursery for unified credit
  (nursery-batch %wctx-nursery-batch %wctx-nursery-batch-set!) ;; unified non-negative credit (0..32)
  (lifo-n        %wctx-lifo-n        %wctx-lifo-n-set!)        ;; nursery associated with lifo slot
  (picked-n      %wctx-picked-n      %wctx-picked-n-set!)      ;; nursery of last popped/stolen task
  (carrier-tls   %wctx-carrier-tls   %wctx-carrier-tls-set!))  ;; lock-free per-carrier user/actor TLS

(define (%outside-run-fibers-error!)
  (error "fiber operation called outside run-fibers"))

(define (fiber-carrier-wid)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        (%wctx-wid ctx)
        #f)))

(define (fiber-carrier-tls)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        (%wctx-carrier-tls ctx)
        #f)))

(define (fiber-carrier-tls-set! val)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        (%wctx-carrier-tls-set! ctx val)
        (%outside-run-fibers-error!))))

(define (%current-wctx)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        ctx
        (%outside-run-fibers-error!))))

;; Unchecked carrier-thread worker-ctx load for internal scheduler callbacks
;; that are guaranteed to run exclusively on initialized carrier threads.
(define (%carrier-wctx)
  (macro-thread-specific (##current-thread)))

;; Zero-allocation per-carrier %fiber-k pop/recycle (0 atomics, 0 GC retention)
(define (%alloc-fk! ctx raw-k tc val)
  (let ((fk (%wctx-fk-pool ctx)))
    (if fk
        (begin
          (%wctx-fk-pool-set! ctx (%fk-next fk))
          (%wctx-fk-pool-len-set! ctx (fx- (%wctx-fk-pool-len ctx) 1))
          (%fk-raw-k-set! fk raw-k)
          (%fk-tc-set! fk tc)
          (%fk-val-set! fk val)
          (%fk-next-set! fk #f)
          fk)
        (%make-fiber-k raw-k tc val #f))))

;; Single-C-block inline %fiber-k recycle (clears GC-retained fields, zero GVM stack frame).
(define (%free-fk! ctx fk)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD *___fk_f  = ___BODY_AS(___ARG2, ___tSTRUCTURE);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[1], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[1], ___FAL);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[2], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[2], ___FAL);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[3], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[3], ___FAL);
     ___WORD ___len = ___INT(___ctx_f[11]);
     if (___len < 64) {
       ___SCMOBJ ___head = ___ctx_f[10];
       ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[4], ___head);
       ___WORD_STORE_RELAXED(&___fk_f[4], ___head);
       ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___ARG2);
       ___WORD_STORE_RELAXED(&___ctx_f[10], ___ARG2);
       ___ctx_f[11] = ___FIX(___len + 1);
     } else {
       ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[4], ___FAL);
       ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
     }
     ___RESULT = ___VOID;"
    ctx fk)
   (begin
     (%fk-raw-k-set! fk #f)
     (%fk-tc-set! fk #f)
     (%fk-val-set! fk #f)
     (let ((len (%wctx-fk-pool-len ctx)))
       (if (fx< len %MAX-FK-POOL)
           (begin
             (%fk-next-set! fk (%wctx-fk-pool ctx))
             (%wctx-fk-pool-set! ctx fk)
             (%wctx-fk-pool-len-set! ctx (fx+ len 1)))
           (%fk-next-set! fk #f))))))

;; Global queue enqueue/dequeue maintaining global-pending >= global-q length.
(define (%sched-enqueue-global! sched task)
  (%fxatom-add-acqrel! (%sched-global-pending sched) 1)
  (lf-queue-enqueue! (%sched-global-q sched) task)
  (%parker-wake-one! sched))

(define (%sched-try-dequeue-global! sched)
  (let ((gp (%sched-global-pending sched)))
    (if (fx= (%fxatom-load-acq gp) 0)
        #f
        (let ((t (lf-queue-try-dequeue-or! (%sched-global-q sched) #f)))
          (if t
              (begin
                (%fxatom-sub-acqrel! gp 1)
                t)
              #f)))))

;; Push (task, nursery) pair to inline local deque (packing pair ONLY on 4096-overflow to global-q).
(define (%sched-push-dq-pair! ctx task n)
  (let ((sched (%wctx-sched ctx)))
    (if (%dq-push-pair! (%wctx-dq ctx) task n)
        (%parker-wake-one! sched)
        (%sched-enqueue-global! sched (if n (cons task n) task)))))

(define (%sched-push-dq! ctx task)
  (%sched-push-dq-pair! ctx task #f))

;; Push to private LIFO slot, evicting any prior (task, nursery) occupant to local deque.
(define (%sched-push-lifo! ctx task)
  (let ((prev (%wctx-lifo ctx))
        (prev-n (%wctx-lifo-n ctx)))
    (%wctx-lifo-set! ctx task)
    (%wctx-lifo-n-set! ctx #f)
    (if prev
        (%sched-push-dq-pair! ctx prev prev-n))))

;; Wake task onto current carrier's LIFO slot if inside this scheduler, else global-q.
(define (%sched-wake! sched task)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) sched))
        (%sched-push-lifo! ctx task)
        (%sched-enqueue-global! sched task))))

;; Sharded quiescence check:
;; Fast-skip while root fiber has not yet finished (root-done == 0 guarantees completed < spawned).
;; Once root-done == 1, scan ALL completed[0..W-1] (acq), seq_cst fence, then ALL spawned[0..W-1] (acq).
(define (%sched-quiescent? sched)
  (if (fx= (%fxatom-load-acq (%sched-root-done sched)) 0)
      #f
      (let ((w (%sched-num-workers sched))
            (cvec (%sched-completed-vec sched))
            (svec (%sched-spawned-vec sched)))
        (let cloop ((i 0) (c 0))
          (if (fx< i w)
              (cloop (fx+ i 1)
                     (fx+ c (%fxatom-load-acq (##vector-ref cvec i))))
              (begin
                (%seq-cst-fence!)
                (let sloop ((j 0) (s 0))
                  (if (fx< j w)
                      (sloop (fx+ j 1)
                             (fx+ s (%fxatom-load-acq (##vector-ref svec j))))
                      (fx= c s)))))))))

;; Bounded searching-worker permit (caps concurrent steal scanners to max(1, W/2)).
(define (%sched-try-acquire-search! sched)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___sp = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
     ___WORD ___cap = ___INT(___f[10]);
     ___SCMOBJ ___ok = ___FAL;
     int ___i;
     for (___i = 0; ___i < 4; ___i++) {
       ___WORD ___cur = ___INT(___atomic_word_load(___sp, 1));
       if (___cur >= ___cap) break;
       if (___atomic_word_cas(___sp, ___FIX(___cur), ___FIX(___cur + 1), 3) == ___FIX(___cur)) {
         ___ok = ___TRU;
         break;
       }
     }
     ___RESULT = ___ok;"
    sched)
   (let ((box (%sched-searching sched))
         (cap (%sched-max-searching sched)))
     (let ((cur (%fxatom-load-acq box)))
       (and (fx< cur cap)
            (fx= (%fxatom-cas-acq! box cur (fx+ cur 1)) cur))))))

(define (%sched-release-search! sched)
  (%fxatom-sub-acqrel! (%sched-searching sched) 1))
