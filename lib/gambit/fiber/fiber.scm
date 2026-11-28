;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Features:
;;;   - Inline 4096-slot 128B-padded Chase-Lev work-stealing deques with
;;;     private LIFO slot and sticky victim-locality stealing
;;;   - Zero-cross-module inline thread-local carrier and control-state access
;;;   - Sharded 128B-padded per-worker monotonic quiescence counters
;;;   - Structured concurrency nurseries with zero-capture child exception handling
;;;   - Lock-free bounded MPMC ring channels with linearizable direct handoff
;;;   - Per-carrier recycled continuation wrapper freelist

(##supply-module gambit/fiber)

(##namespace ("gambit/fiber#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  make-thread
  thread-start!
  thread-join!
  thread-yield!
  with-exception-catcher
  raise
  error))
(##include "~~lib/gambit/concurrent/concurrent#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "fiber#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (inlining-limit 400)
  (block))

;;;----------------------------------------------------------------------------
;;; Inline C23 Atomic Primitives (Zero Cross-Module Overhead on C Target)
;;;
;;; Memory-order codes match Gambit runtime_protocols:
;;;   0=relaxed, 1=acquire, 2=release, 3=acq_rel, 4=seq_cst

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

;; 1-word fixnum atomic box
(define (%make-fxatom init)
  (##vector init))

;; 128-byte (16-word) cache-line-padded fixnum atomic box (eliminates L2 false sharing).
(define (%make-padded-fxatom init)
  (let ((v (##make-vector 16 0)))
    (##vector-set! v 0 init)
    v))

(define (%fxatom-load-rlx box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 0));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-load-acq box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 1));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-load-seq box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 4));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-set-rlx! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 0);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-set-rel! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-set-seq! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 4);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-cas-rlx! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 0));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-cas-acq! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 1));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-cas-seq! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-add-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___WORD, ___ARG2), 3));"
    box delta)
   (##vector-inc! box 0 delta)))

(define (%fxatom-sub-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___WORD, ___ARG2), 3));"
    box delta)
   (##vector-inc! box 0 (##fx- 0 delta))))

;; Owner-only single-writer release increment (STLR on ARM64, zero LDADDAL RMW)
(define (%fxatom-inc-owner-rel! box)
  (%fxatom-set-rel! box (##fx+ (##vector-ref box 0) 1)))

;; Indexed fixnum-vector atomics for bounded MPMC ring sequence numbers
(define (%vec-fx-load-acq vec idx)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(
         ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)) + ___INT(___ARG2),
         1));"
    vec idx)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (%vec-fx-store-seq! vec idx val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(
       ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)) + ___INT(___ARG2),
       ___CAST(___WORD, ___ARG3),
       4);
     ___RESULT = ___VOID;"
    vec idx val)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let ((prev (##vector-cas! vec idx val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

;; GC/SATB-safe atomic object-slot load/store for inline Chase-Lev deque
(define (%dq-slot-load-acq vec idx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_load(___s, 1);"
    vec idx)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (%dq-slot-store-rlx! vec idx val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___gc_atomic_slot_exchange(
       ___ps, ___ARG1, ___s, ___ARG3, 0,
       ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
     ___RESULT = ___VOID;"
    vec idx val)
   (##vector-set! vec idx val)))

(define (%seq-cst-fence!)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order(4); ___RESULT = ___VOID;")
   (atomic-fence (memory-order sequentially-consistent))))

;;;----------------------------------------------------------------------------
;;; Inline 4096-Slot 128B-Padded Chase-Lev Work-Stealing Deque
;;; (Eliminates cross-module calls and global-queue spills for large nurseries)

(define %DQ-CAP 4096)
(define %DQ-MASK 4095)

(define-type %local-dq
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000007
  constructor: %make-local-dq-raw
  predicate: %local-dq?
  (buf %dq-buf)
  (top %dq-top)  ;; 128B-padded fxatom
  (bot %dq-bot)) ;; 128B-padded fxatom

(define (%make-local-dq)
  (%make-local-dq-raw (make-vector %DQ-CAP #f)
                      (%make-padded-fxatom 0)
                      (%make-padded-fxatom 0)))

(define (%dq-push! dq item)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf = ___f[1];
     ___VOLATILE ___WORD *___top_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___bot_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD ___b = ___INT(___atomic_word_load(___bot_p, 0));
     ___WORD ___t = ___INT(___atomic_word_load(___top_p, 1));
     if (___b - ___t >= 4096) {
       ___RESULT = ___FAL;
     } else {
       ___WORD *___s = ___BODY_AS(___buf, ___tVECTOR) + (___b & 4095);
       ___gc_atomic_slot_exchange(
         ___ps, ___buf, ___s, ___ARG2, 0,
         ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
       ___atomic_word_store(___bot_p, ___FIX(___b + 1), 2);
       ___RESULT = ___TRU;
     }"
    dq item)
   (let* ((bot-box (%dq-bot dq))
          (b (%fxatom-load-rlx bot-box))
          (t (%fxatom-load-acq (%dq-top dq))))
     (if (fx>= (fx- b t) %DQ-CAP)
         #f
         (begin
           (%dq-slot-store-rlx! (%dq-buf dq) (fxand b %DQ-MASK) item)
           (%fxatom-set-rel! bot-box (fx+ b 1))
           #t)))))

(define (%dq-pop! dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf = ___f[1];
     ___VOLATILE ___WORD *___top_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___bot_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD ___b = ___INT(___atomic_word_load(___bot_p, 0)) - 1;
     ___atomic_word_store(___bot_p, ___FIX(___b), 0);
     ___atomic_fence_order(4);
     ___WORD ___t = ___INT(___atomic_word_load(___top_p, 0));
     if (___t <= ___b) {
       ___SCMOBJ ___item = ___gc_atomic_slot_load(___BODY_AS(___buf, ___tVECTOR) + (___b & 4095), 1);
       if (___t == ___b) {
         ___WORD ___won = (___atomic_word_cas(___top_p, ___FIX(___t), ___FIX(___t + 1), 4) == ___FIX(___t));
         ___atomic_word_store(___bot_p, ___FIX(___t + 1), 0);
         ___RESULT = ___won ? ___item : ___FAL;
       } else {
         ___RESULT = ___item;
       }
     } else {
       ___atomic_word_store(___bot_p, ___FIX(___t), 0);
       ___RESULT = ___FAL;
     }"
    dq)
   (let* ((bot-box (%dq-bot dq))
          (top-box (%dq-top dq))
          (b (fx- (%fxatom-load-rlx bot-box) 1)))
     (%fxatom-set-rlx! bot-box b)
     (%seq-cst-fence!)
     (let ((t (%fxatom-load-rlx top-box)))
       (if (fx<= t b)
           (let ((item (%dq-slot-load-acq (%dq-buf dq) (fxand b %DQ-MASK))))
             (if (fx= t b)
                 (let ((won? (fx= (%fxatom-cas-seq! top-box t (fx+ t 1)) t)))
                   (%fxatom-set-rlx! bot-box (fx+ t 1))
                   (if won? item #f))
                 item))
           (begin
             (%fxatom-set-rlx! bot-box t)
             #f))))))

(define (%dq-empty-rlx? dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___top_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___bot_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___RESULT = (___INT(___atomic_word_load(___bot_p, 0)) <= ___INT(___atomic_word_load(___top_p, 0))) ? ___TRU : ___FAL;"
    dq)
   (fx<= (%fxatom-load-rlx (%dq-bot dq)) (%fxatom-load-rlx (%dq-top dq)))))

(define (%dq-steal! dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf = ___f[1];
     ___VOLATILE ___WORD *___top_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___bot_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD ___t = ___INT(___atomic_word_load(___top_p, 1));
     ___atomic_fence_order(4);
     ___WORD ___b = ___INT(___atomic_word_load(___bot_p, 1));
     if (___t < ___b) {
       ___SCMOBJ ___item = ___gc_atomic_slot_load(___BODY_AS(___buf, ___tVECTOR) + (___t & 4095), 1);
       if (___atomic_word_cas(___top_p, ___FIX(___t), ___FIX(___t + 1), 4) == ___FIX(___t)) {
         ___RESULT = ___item;
       } else {
         ___RESULT = ___FAL;
       }
     } else {
       ___RESULT = ___FAL;
     }"
    dq)
   (let* ((top-box (%dq-top dq))
          (t (%fxatom-load-acq top-box)))
     (%seq-cst-fence!)
     (let ((b (%fxatom-load-acq (%dq-bot dq))))
       (if (fx< t b)
           (let ((item (%dq-slot-load-acq (%dq-buf dq) (fxand t %DQ-MASK))))
             (if (fx= (%fxatom-cas-seq! top-box t (fx+ t 1)) t)
                 item
                 #f))
           #f)))))

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
  (root-box       %sched-root-box))      ;; box holding (ok? . val-or-exc)

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
  (fk-pool      %wctx-fk-pool      %wctx-fk-pool-set!)      ;; private %fiber-k freelist
  (fk-pool-len  %wctx-fk-pool-len  %wctx-fk-pool-len-set!)
  (steal-cursor %wctx-steal-cursor %wctx-steal-cursor-set!)) ;; sticky productive victim wid

(define (%current-wctx)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        ctx
        (error "fiber operation called outside run-fibers"))))

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

(define (%free-fk! ctx fk)
  (%fk-raw-k-set! fk #f)
  (%fk-tc-set! fk #f)
  (%fk-val-set! fk #f)
  (let ((len (%wctx-fk-pool-len ctx)))
    (if (fx< len %MAX-FK-POOL)
        (begin
          (%fk-next-set! fk (%wctx-fk-pool ctx))
          (%wctx-fk-pool-set! ctx fk)
          (%wctx-fk-pool-len-set! ctx (fx+ len 1)))
        (%fk-next-set! fk #f))))

;; Global queue enqueue/dequeue maintaining global-pending >= global-q length.
(define (%sched-enqueue-global! sched task)
  (%fxatom-add-acqrel! (%sched-global-pending sched) 1)
  (lf-queue-enqueue! (%sched-global-q sched) task))

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

;; Push to inline local Chase-Lev deque (spilling to global-q only if > 4096 queued).
(define (%sched-push-dq! ctx task)
  (if (not (%dq-push! (%wctx-dq ctx) task))
      (%sched-enqueue-global! (%wctx-sched ctx) task)))

;; Push to private LIFO slot, evicting any prior occupant to local Chase-Lev deque.
(define (%sched-push-lifo! ctx task)
  (let ((prev (%wctx-lifo ctx)))
    (%wctx-lifo-set! ctx task)
    (if prev
        (%sched-push-dq! ctx prev))))

;; Wake task onto current carrier's LIFO slot if inside this scheduler, else global-q.
(define (%sched-wake! sched task)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) sched))
        (%sched-push-lifo! ctx task)
        (%sched-enqueue-global! sched task))))

;; Sharded quiescence check:
;; Scan ALL completed[0..W-1] (acq), seq_cst fence, then scan ALL spawned[0..W-1] (acq).
(define (%sched-quiescent? sched)
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
                  (fx= c s))))))))

;;;----------------------------------------------------------------------------
;;; Inline C23 Non-Blocking Spinlock Helper (Bounded C Spin + Safepoint Yield)

(define (%spin-trylock-bounded! box)
  (macro-if-c-compiled
   (##c-code
    "___VOLATILE ___WORD *___p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR));
     int ___i;
     ___SCMOBJ ___ok = ___FAL;
     for (___i = 0; ___i < 64; ___i++) {
       if (___atomic_word_cas(___p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
         ___ok = ___TRU;
         break;
       }
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     ___RESULT = ___ok;"
    box)
   (fx= (%fxatom-cas-acq! box 0 1) 0)))

(define (%spin-lock! box)
  (if (not (%spin-trylock-bounded! box))
      (let loop ()
        (thread-yield!)
        (if (not (%spin-trylock-bounded! box))
            (loop)))))

(define (%spin-unlock! box)
  (%fxatom-set-rel! box 0))

;;;----------------------------------------------------------------------------
;;; Structured Concurrency Nursery
;;; (Zero-Capture Children via ##with-exception-handler + Unwind-Safe Abort)

(define-type nursery
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000003
  constructor: %make-nursery
  predicate: nursery?
  (sched       %nursery-sched)
  (active      %nursery-active)      ;; 128B-padded fxatom (isolated from lock/waiter-k)
  (lock        %nursery-lock)        ;; fxatom spinlock
  (waiter-k    %nursery-waiter-k     %nursery-waiter-k-set!)
  (first-err   %nursery-first-err    %nursery-first-err-set!)
  (has-err?    %nursery-has-err?     %nursery-has-err?-set!)
  (err-handler %nursery-err-handler  %nursery-err-handler-set!))

(define (%nursery-record-error! n exc)
  (%spin-lock! (%nursery-lock n))
  (if (not (%nursery-has-err? n))
      (begin
        (%nursery-has-err?-set! n #t)
        (%nursery-first-err-set! n exc)))
  (%spin-unlock! (%nursery-lock n)))

(define (%nursery-child-done! n)
  (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) 1)))
    (if (fx= prev 1)
        (let ((lock (%nursery-lock n))
              (wk #f))
          (%spin-lock! lock)
          (set! wk (%nursery-waiter-k n))
          (%nursery-waiter-k-set! n #f)
          (%spin-unlock! lock)
          (if wk
              (begin
                (%fk-val-set! wk #!void)
                (%sched-wake! (%nursery-sched n) wk)))))))

;; Executed on the clean carrier trampoline AFTER ##continuation-graft has
;; completed all dynamic-wind after thunks of the aborting child fiber.
(define (%nursery-child-abort! n exc)
  (%nursery-record-error! n exc)
  (%nursery-child-done! n)
  (let ((cur-ctx (%current-wctx)))
    (if (%get-tc) (%set-tc! #f))
    (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
    (%worker-dispatch cur-ctx 0)))

;; Zero-closure multi-arg continuation receiver for nursery join park
(define (%park-nursery-cont! raw-k n)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #!void))
         (lock (%nursery-lock n))
         (wake-now? #f))
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (if (fx= (%fxatom-load-acq (%nursery-active n)) 0)
        (set! wake-now? #t)
        (%nursery-waiter-k-set! n fk))
    (%spin-unlock! lock)
    (if wake-now?
        (%sched-push-lifo! ctx fk))
    (%sched-switch-next! ctx)))

(define (with-nursery proc)
  (if (not (procedure? proc))
      (error "with-nursery: expected procedure" proc))
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (n (%make-nursery sched
                           (%make-padded-fxatom 1)
                           (%make-fxatom 0)
                           #f
                           #f
                           #f
                           #f))
         (child-eh (lambda (e)
                     (let ((cur-ctx (%current-wctx)))
                       (##continuation-graft (%wctx-sched-k cur-ctx)
                                             %nursery-child-abort! n e))))
         (parent-res #f))
    (%nursery-err-handler-set! n child-eh)
    (with-exception-catcher
     (lambda (e) (%nursery-record-error! n e))
     (lambda ()
       (set! parent-res (proc n))))
    (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) 1)))
      (if (fx> prev 1)
          (##continuation-capture %park-nursery-cont! n)))
    (if (%nursery-has-err? n)
        (raise (%nursery-first-err n))
        parent-res)))

;;;----------------------------------------------------------------------------
;;; Direct O(1) Fiber Spawn & Zero-Closure Yield

(define (fiber-worker-count)
  (%sched-num-workers (%wctx-sched (%current-wctx))))

;; Zero-closure multi-arg continuation receiver for fiber-yield
(define (%yield-cont! raw-k)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #!void)))
    (if tc (%set-tc! #f))
    (%sched-push-dq! ctx fk)
    (if (%wctx-lifo ctx)
        (%sched-switch-next! ctx)
        (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0))))

(define (fiber-yield)
  (##continuation-capture %yield-cont!))

(define (fiber-spawn thunk #!optional (n #f))
  (if (not (procedure? thunk))
      (error "fiber-spawn: expected thunk" thunk))
  (let ((ctx (%current-wctx)))
    (if n
        (begin
          (if (not (nursery? n))
              (error "fiber-spawn: expected nursery" n))
          (%fxatom-add-acqrel! (%nursery-active n) 1)
          (%fxatom-inc-owner-rel! (%wctx-spawned ctx))
          (%sched-push-lifo! ctx (cons thunk n))
          #!void)
        (begin
          (%fxatom-inc-owner-rel! (%wctx-spawned ctx))
          (%sched-push-lifo! ctx thunk)
          #!void))))

;;;----------------------------------------------------------------------------
;;; Intrusive Zero-Cons FIFO Wait Queue & Lock-Free Bounded MPMC Channel
;;; + Linearizable Direct Handoff + Zero-Closure Multi-Arg Park Continuations

(define-type %wait-q
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000004
  constructor: %make-wait-q
  predicate: %wait-q?
  (head %wq-head %wq-head-set!)
  (tail %wq-tail %wq-tail-set!))

(define (%wq-empty? q)
  (not (%wq-head q)))

(define (%wq-push! q fk)
  (%fk-next-set! fk #f)
  (let ((t (%wq-tail q)))
    (if (not t)
        (begin
          (%wq-head-set! q fk)
          (%wq-tail-set! q fk))
        (begin
          (%fk-next-set! t fk)
          (%wq-tail-set! q fk)))))

(define (%wq-pop! q)
  (let* ((h (%wq-head q))
         (nxt (%fk-next h)))
    (%fk-next-set! h #f)
    (%wq-head-set! q nxt)
    (if (not nxt)
        (%wq-tail-set! q #f))
    h))

(define-type fiber-channel
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000005
  constructor: %make-fiber-channel
  predicate: fiber-channel?
  (cap          %ch-cap)
  (mask         %ch-mask)        ;; cap-1 when power-of-2, else -1 (exact fxmodulo)
  (buf          %ch-buf)         ;; ring payload slots (GC write-barrier via ##vector-set!)
  (seq          %ch-seq)         ;; per-slot sequence fixnums
  (tail         %ch-tail)        ;; 128B-padded producer cursor
  (head         %ch-head)        ;; 128B-padded consumer cursor
  (rx-waiters   %ch-rx-waiters)  ;; 128B-padded count of parked receivers
  (tx-waiters   %ch-tx-waiters)  ;; 128B-padded count of parked senders
  (lock         %ch-lock)        ;; slow-path wait-lock (and cap==0 rendezvous lock)
  (recv-waiters %ch-recv-waiters)
  (send-waiters %ch-send-waiters))

(define (make-fiber-channel #!optional (capacity 16))
  (if (or (not (fixnum? capacity)) (fx< capacity 0))
      (error "make-fiber-channel: capacity must be a non-negative fixnum" capacity))
  (let* ((is-pow2 (and (fx> capacity 0)
                       (fx= (fxand capacity (fx- capacity 1)) 0)))
         (mask (if is-pow2 (fx- capacity 1) -1))
         (buf (if (fx> capacity 0) (make-vector capacity #f) '#()))
         (seq (if (fx> capacity 0)
                  (let ((v (make-vector capacity 0)))
                    (let loop ((i 0))
                      (if (fx< i capacity)
                          (begin (##vector-set! v i (fxarithmetic-shift-left i 1))
                                 (loop (fx+ i 1)))))
                    v)
                  '#())))
    (%make-fiber-channel
     capacity
     mask
     buf
     seq
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (%make-fxatom 0)
     (%make-wait-q #f #f)
     (%make-wait-q #f #f))))

;; Single-C-block bounded-retry Vyukov ring push (2*pos / 2*pos+1 supports all cap >= 1).
;; Returns: 0=pushed & rxw==0, 1=pushed & rxw>0, 2=full, 3=retry after safepoint poll.
(define (%vyukov-try-push-c! ch val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap  = ___INT(___f[1]);
     ___WORD ___mask = ___INT(___f[2]);
     ___SCMOBJ ___buf = ___f[3];
     ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
     ___VOLATILE ___WORD *___rxw_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
     ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
     ___SCMOBJ ___val = ___ARG2;
     ___WORD ___res = 3;
     int ___tries;
     for (___tries = 0; ___tries < 64; ___tries++) {
       ___WORD ___pos = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 1));
       ___WORD ___exp = ___pos << 1;
       ___WORD ___dif = ___s - ___exp;
       if (___dif == 0) {
         if (___atomic_word_cas(___tail_p, ___FIX(___pos), ___FIX(___pos + 1), 0) == ___FIX(___pos)) {
           ___WORD *___slot = ___buf_p + ___idx;
           ___GC_WRITE_BARRIER(___ps, ___buf, ___slot, ___val);
           ___WORD_STORE_RELAXED(___slot, ___val);
           ___atomic_word_store(___seq_p + ___idx, ___FIX(___exp + 1), 4);
           ___res = (___INT(___atomic_word_load(___rxw_p, 4)) > 0) ? 1 : 0;
           break;
         }
       } else if (___dif < 0) {
         ___res = 2;
         break;
       }
     }
     ___RESULT = ___FIX(___res);"
    ch val)
   (let ((tail-box (%ch-tail ch))
         (seq (%ch-seq ch))
         (buf (%ch-buf ch))
         (cap (%ch-cap ch))
         (mask (%ch-mask ch)))
     (let loop ()
       (let* ((pos (%fxatom-load-rlx tail-box))
              (idx (if (fx>= mask 0) (fxand pos mask) (fxmodulo pos cap)))
              (s (%vec-fx-load-acq seq idx))
              (exp (fxarithmetic-shift-left pos 1))
              (dif (fx- s exp)))
         (cond
           ((fx= dif 0)
            (if (fx= (%fxatom-cas-rlx! tail-box pos (fx+ pos 1)) pos)
                (begin
                  (##vector-set! buf idx val)
                  (%vec-fx-store-seq! seq idx (fx+ exp 1))
                  (if (fx> (%fxatom-load-seq (%ch-rx-waiters ch)) 0) 1 0))
                (loop)))
           ((fx< dif 0) 2)
           (else (loop))))))))

(define (%vyukov-try-push! ch val)
  (let loop ()
    (let ((st (%vyukov-try-push-c! ch val)))
      (cond
        ((fx<= st 1) #t)
        ((fx= st 2) #f)
        (else (loop))))))

;; Single-C-block bounded-retry Vyukov ring pop (2*pos+1 / 2*(pos+cap) supports all cap >= 1).
;; Returns item directly, `default` if empty, or `retry-tag` if retry budget hit safepoint.
(define (%vyukov-try-pop-c! ch default retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap  = ___INT(___f[1]);
     ___WORD ___mask = ___INT(___f[2]);
     ___SCMOBJ ___buf = ___f[3];
     ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
     ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
     ___SCMOBJ ___res = ___ARG3;
     int ___tries;
     for (___tries = 0; ___tries < 64; ___tries++) {
       ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 1));
       ___WORD ___exp = (___pos << 1) + 1;
       ___WORD ___dif = ___s - ___exp;
       if (___dif == 0) {
         if (___atomic_word_cas(___head_p, ___FIX(___pos), ___FIX(___pos + 1), 0) == ___FIX(___pos)) {
           ___WORD *___slot = ___buf_p + ___idx;
           ___SCMOBJ ___item = ___WORD_LOAD_RELAXED(___slot);
           ___GC_WRITE_BARRIER(___ps, ___buf, ___slot, ___FAL);
           ___WORD_STORE_RELAXED(___slot, ___FAL);
           ___atomic_word_store(___seq_p + ___idx, ___FIX((___pos + ___cap) << 1), 4);
           ___res = ___item;
           break;
         }
       } else if (___dif < 0) {
         ___res = ___ARG2;
         break;
       }
     }
     ___RESULT = ___res;"
    ch default retry-tag)
   (let ((head-box (%ch-head ch))
         (seq (%ch-seq ch))
         (buf (%ch-buf ch))
         (cap (%ch-cap ch))
         (mask (%ch-mask ch)))
     (let loop ()
       (let* ((pos (%fxatom-load-rlx head-box))
              (idx (if (fx>= mask 0) (fxand pos mask) (fxmodulo pos cap)))
              (s (%vec-fx-load-acq seq idx))
              (exp (fx+ (fxarithmetic-shift-left pos 1) 1))
              (dif (fx- s exp)))
         (cond
           ((fx= dif 0)
            (if (fx= (%fxatom-cas-rlx! head-box pos (fx+ pos 1)) pos)
                (let ((item (##vector-ref buf idx)))
                  (##vector-set! buf idx #f)
                  (%vec-fx-store-seq! seq idx (fxarithmetic-shift-left (fx+ pos cap) 1))
                  item)
                (loop)))
           ((fx< dif 0) default)
           (else (loop))))))))

(define (%vyukov-try-pop-or! ch default)
  (let loop ()
    (let ((res (%vyukov-try-pop-c! ch default %CH-RETRY)))
      (if (eq? res %CH-RETRY)
          (loop)
          res))))

;; Slow-path wakeups (called only when waiter count > 0)
(define (%ch-wake-one-receiver! ch)
  (let ((lock (%ch-lock ch))
        (rwq (%ch-recv-waiters ch))
        (rxw (%ch-rx-waiters ch))
        (rk #f)
        (item %CH-EMPTY))
    (%spin-lock! lock)
    (if (not (%wq-empty? rwq))
        (begin
          (set! rk (%wq-pop! rwq))
          (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
          (set! item (%vyukov-try-pop-or! ch %CH-EMPTY))))
    (%spin-unlock! lock)
    (if rk
        (if (not (eq? item %CH-EMPTY))
            (begin
              (if (fx> (%fxatom-load-seq (%ch-tx-waiters ch)) 0)
                  (%ch-wake-one-sender! ch))
              (%fk-val-set! rk item)
              (%sched-push-lifo! (%current-wctx) rk))
            (begin
              (%fk-val-set! rk %CH-RETRY)
              (%sched-push-lifo! (%current-wctx) rk))))))

(define (%ch-wake-one-sender! ch)
  (let ((lock (%ch-lock ch))
        (swq (%ch-send-waiters ch))
        (txw (%ch-tx-waiters ch))
        (sk #f)
        (pushed? #f))
    (%spin-lock! lock)
    (if (not (%wq-empty? swq))
        (begin
          (set! sk (%wq-pop! swq))
          (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
          (set! pushed? (%vyukov-try-push! ch (%fk-val sk)))))
    (%spin-unlock! lock)
    (if sk
        (if pushed?
            (begin
              (if (fx> (%fxatom-load-seq (%ch-rx-waiters ch)) 0)
                  (%ch-wake-one-receiver! ch))
              (%fk-val-set! sk #t)
              (%sched-push-lifo! (%current-wctx) sk))
            (begin
              (%fk-val-set! sk %CH-RETRY)
              (%sched-push-lifo! (%current-wctx) sk))))))

;; Single-C-block fused Dekker park-send for full buffered channels.
;; Returns: #t if parked cleanly, #f if race (ring freed or receiver parked),
;; or retry-tag if lock spin budget exhausted.
(define (%ch-park-send-c! ch fk retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
     int ___got = 0;
     int ___i;
     for (___i = 0; ___i < 64; ___i++) {
       if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
         ___got = 1;
         break;
       }
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     if (!___got) {
       ___RESULT = ___ARG3;
     } else {
       ___VOLATILE ___WORD *___txw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[8], ___tVECTOR));
       ___WORD ___cur_txw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___txw_p)));
       ___atomic_word_store(___txw_p, ___FIX(___cur_txw + 1), 4);
       ___WORD ___cap  = ___INT(___f[1]);
       ___WORD ___mask = ___INT(___f[2]);
       ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
       ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
       ___WORD ___pos = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
       ___SCMOBJ ___rwq = ___f[10];
       ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
       if (___s - (___pos << 1) < 0 && ___rwq_f[1] == ___FAL) {
         ___SCMOBJ ___swq = ___f[11];
         ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
         ___SCMOBJ ___fk = ___ARG2;
         ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
         ___SCMOBJ ___t = ___swq_f[2];
         if (___t == ___FAL) {
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[1], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[1], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[2], ___fk);
         } else {
           ___WORD *___t_f = ___BODY_AS(___t, ___tSTRUCTURE);
           ___GC_WRITE_BARRIER(___ps, ___t, &___t_f[4], ___fk);
           ___WORD_STORE_RELAXED(&___t_f[4], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[2], ___fk);
         }
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___TRU;
       } else {
         ___atomic_word_store(___txw_p, ___FIX(___cur_txw), 4);
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___FAL;
       }
     }"
    ch fk retry-tag)
   #f))

;; Zero-closure multi-arg park receivers for buffered channels (cap > 0)
(define (%park-send-buf-cont! raw-k ch val)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc val)))
    (if tc (%set-tc! #f))
    (let ((fast (%ch-park-send-c! ch fk %CH-RETRY)))
      (if (not (eq? fast #t))
          (let ((lock (%ch-lock ch))
                (rwq (%ch-recv-waiters ch))
                (swq (%ch-send-waiters ch))
                (rxw (%ch-rx-waiters ch))
                (txw (%ch-tx-waiters ch)))
            (if (eq? fast %CH-RETRY) (thread-yield!))
            (%spin-lock! lock)
            (%fxatom-set-seq! txw (fx+ (##vector-ref txw 0) 1))
            (%seq-cst-fence!)
            (cond
              ((and (not (%wq-empty? rwq))
                    (let* ((t (%fxatom-load-acq (%ch-tail ch)))
                           (h (%fxatom-load-acq (%ch-head ch))))
                      (fx= t h)))
               (let ((rk (%wq-pop! rwq)))
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                 (%spin-unlock! lock)
                 (%fk-val-set! rk val)
                 (%fk-val-set! fk #t)
                 (%sched-push-lifo! ctx fk)
                 (%sched-push-lifo! ctx rk)))
              ((%vyukov-try-push! ch val)
               (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
               (%spin-unlock! lock)
               (if (fx> (%fxatom-load-seq rxw) 0)
                   (%ch-wake-one-receiver! ch))
               (%fk-val-set! fk #t)
               (%sched-push-lifo! ctx fk))
              (else
               (%wq-push! swq fk)
               (%spin-unlock! lock))))))
    (%sched-switch-next! ctx)))

;; Single-C-block fused Dekker park-recv for empty buffered channels.
;; Returns: #t if parked cleanly, #f if race (item arrived or sender parked),
;; or retry-tag if lock spin budget exhausted.
(define (%ch-park-recv-c! ch fk retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
     int ___got = 0;
     int ___i;
     for (___i = 0; ___i < 64; ___i++) {
       if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
         ___got = 1;
         break;
       }
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     if (!___got) {
       ___RESULT = ___ARG3;
     } else {
       ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
       ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
       ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw + 1), 4);
       ___WORD ___cap  = ___INT(___f[1]);
       ___WORD ___mask = ___INT(___f[2]);
       ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
       ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
       ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
       ___SCMOBJ ___swq = ___f[11];
       ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
       if (___s - ((___pos << 1) + 1) < 0 && ___swq_f[1] == ___FAL) {
         ___SCMOBJ ___rwq = ___f[10];
         ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
         ___SCMOBJ ___fk = ___ARG2;
         ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
         ___SCMOBJ ___t = ___rwq_f[2];
         if (___t == ___FAL) {
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[1], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[1], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
         } else {
           ___WORD *___t_f = ___BODY_AS(___t, ___tSTRUCTURE);
           ___GC_WRITE_BARRIER(___ps, ___t, &___t_f[4], ___fk);
           ___WORD_STORE_RELAXED(&___t_f[4], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
         }
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___TRU;
       } else {
         ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw), 4);
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___FAL;
       }
     }"
    ch fk retry-tag)
   #f))

(define (%park-recv-buf-cont! raw-k ch)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #f)))
    (if tc (%set-tc! #f))
    (let ((fast (%ch-park-recv-c! ch fk %CH-RETRY)))
      (if (not (eq? fast #t))
          (let ((lock (%ch-lock ch))
                (rwq (%ch-recv-waiters ch))
                (swq (%ch-send-waiters ch))
                (rxw (%ch-rx-waiters ch))
                (txw (%ch-tx-waiters ch)))
            (if (eq? fast %CH-RETRY) (thread-yield!))
            (%spin-lock! lock)
            (%fxatom-set-seq! rxw (fx+ (##vector-ref rxw 0) 1))
            (%seq-cst-fence!)
            (let ((item (%vyukov-try-pop-or! ch %CH-EMPTY)))
              (cond
                ((not (eq? item %CH-EMPTY))
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%spin-unlock! lock)
                 (if (fx> (%fxatom-load-seq txw) 0)
                     (%ch-wake-one-sender! ch))
                 (%fk-val-set! fk item)
                 (%sched-push-lifo! ctx fk))
                ((not (%wq-empty? swq))
                 (let* ((sk (%wq-pop! swq))
                        (sval (%fk-val sk)))
                   (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                   (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                   (%spin-unlock! lock)
                   (%fk-val-set! sk #t)
                   (%fk-val-set! fk sval)
                   (%sched-push-lifo! ctx sk)
                   (%sched-push-lifo! ctx fk)))
                (else
                 (%wq-push! rwq fk)
                 (%spin-unlock! lock)))))))
    (%sched-switch-next! ctx)))

;; Zero-closure multi-arg park receivers for unbuffered rendezvous (cap == 0)
(define (%park-send-unbuf-cont! raw-k ch val)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc val))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (if (not (%wq-empty? rwq))
        (let ((rk (%wq-pop! rwq)))
          (%spin-unlock! lock)
          (%fk-val-set! rk val)
          (%fk-val-set! fk #t)
          (%sched-push-lifo! ctx fk)
          (%sched-push-lifo! ctx rk))
        (begin
          (%wq-push! swq fk)
          (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))

(define (%park-recv-unbuf-cont! raw-k ch)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #f))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (if (not (%wq-empty? swq))
        (let* ((sk (%wq-pop! swq))
               (sval (%fk-val sk)))
          (%spin-unlock! lock)
          (%fk-val-set! sk #t)
          (%fk-val-set! fk sval)
          (%sched-push-lifo! ctx sk)
          (%sched-push-lifo! ctx fk))
        (begin
          (%wq-push! rwq fk)
          (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))

;; Single-C-block linearizable direct handoff for buffered channels.
;; Sets rk.val = val with SATB/generational write barrier before unlocking.
;; Returns: parked %fiber-k if handed off, #f if no eligible waiter, or retry-tag.
(define (%ch-try-direct-handoff-c! ch val retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
     if (___INT(___atomic_word_load(___rxw_p, 0)) == 0) {
       ___RESULT = ___FAL;
     } else {
       ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
       int ___got_lock = 0;
       int ___i;
       for (___i = 0; ___i < 64; ___i++) {
         if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
           ___got_lock = 1;
           break;
         }
#if defined(__aarch64__)
         __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
         __asm__ __volatile__(\"pause\");
#endif
       }
       if (!___got_lock) {
         ___RESULT = ___ARG3;
       } else {
         ___SCMOBJ ___rwq = ___f[10];
         ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
         ___SCMOBJ ___rk = ___rwq_f[1];
         ___SCMOBJ ___out = ___FAL;
         if (___rk != ___FAL) {
           ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
           ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
           ___WORD ___t = ___atomic_word_load(___tail_p, 1);
           ___WORD ___h = ___atomic_word_load(___head_p, 1);
           if (___t == ___h) {
             ___WORD *___rk_f = ___BODY_AS(___rk, ___tSTRUCTURE);
             ___SCMOBJ ___nxt = ___rk_f[4];
             ___GC_WRITE_BARRIER(___ps, ___rk, &___rk_f[4], ___FAL);
             ___WORD_STORE_RELAXED(&___rk_f[4], ___FAL);
             ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[1], ___nxt);
             ___WORD_STORE_RELAXED(&___rwq_f[1], ___nxt);
             if (___nxt == ___FAL) {
               ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___FAL);
               ___WORD_STORE_RELAXED(&___rwq_f[2], ___FAL);
             }
             ___GC_WRITE_BARRIER(___ps, ___rk, &___rk_f[3], ___ARG2);
             ___WORD_STORE_RELAXED(&___rk_f[3], ___ARG2);
             ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
             ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw - 1), 4);
             ___out = ___rk;
           }
         }
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___out;
       }
     }"
    ch val retry-tag)
   (let ((rxw (%ch-rx-waiters ch)))
     (if (fx> (%fxatom-load-rlx rxw) 0)
         (let ((lock (%ch-lock ch))
               (rwq (%ch-recv-waiters ch))
               (rk #f))
           (%spin-lock! lock)
           (if (and (not (%wq-empty? rwq))
                    (let* ((t (%fxatom-load-acq (%ch-tail ch)))
                           (h (%fxatom-load-acq (%ch-head ch))))
                      (fx= t h)))
               (begin
                 (set! rk (%wq-pop! rwq))
                 (%fk-val-set! rk val)
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))))
           (%spin-unlock! lock)
           rk)
         #f))))

(define (%fiber-send-buf! ch val)
  ;; Fast path A: Single-C-block linearizable direct handoff (1 instruction skip if rxw==0)
  (let loop ()
    (let ((rk (%ch-try-direct-handoff-c! ch val %CH-RETRY)))
      (cond
        ((not rk)
         (%fiber-send-buf-ring! ch val (%ch-rx-waiters ch)))
        ((eq? rk %CH-RETRY)
         (thread-yield!)
         (loop))
        (else
         (%sched-push-lifo! (%current-wctx) rk)
         #t)))))

(define (%fiber-send-buf-ring! ch val rxw)
  ;; Fast path B: Single-C-block lock-free bounded MPMC ring push (zero spinlocks)
  (let loop ()
    (let ((st (%vyukov-try-push-c! ch val)))
      (cond
        ((fx= st 0) #t)
        ((fx= st 1) (%ch-wake-one-receiver! ch) #t)
        ((fx= st 2)
         (let ((res (##continuation-capture %park-send-buf-cont! ch val)))
           (if (eq? res %CH-RETRY)
               (%fiber-send-buf! ch val)
               #t)))
        (else (loop))))))

(define (fiber-send! ch val)
  (if (not (fiber-channel? ch))
      (error "fiber-send!: expected fiber-channel" ch))
  (if (fx> (%ch-cap ch) 0)
      (%fiber-send-buf! ch val)
      ;; Unbuffered rendezvous (cap == 0) with relaxed hint
      (let ((rwq (%ch-recv-waiters ch)))
        (if (not (%wq-head rwq))
            (##continuation-capture %park-send-unbuf-cont! ch val)
            (let ((lock (%ch-lock ch)))
              (%spin-lock! lock)
              (if (not (%wq-empty? rwq))
                  (let ((rk (%wq-pop! rwq)))
                    (%spin-unlock! lock)
                    (%fk-val-set! rk val)
                    (%sched-push-lifo! (%current-wctx) rk)
                    #t)
                  (begin
                    (%spin-unlock! lock)
                    (##continuation-capture %park-send-unbuf-cont! ch val))))))))

(define (%fiber-recv-buf! ch)
  ;; Fast path: Lock-free bounded MPMC ring pop (zero spinlocks)
  (let ((item (%vyukov-try-pop-or! ch %CH-EMPTY)))
    (if (not (eq? item %CH-EMPTY))
        (begin
          (if (fx> (%fxatom-load-seq (%ch-tx-waiters ch)) 0)
              (%ch-wake-one-sender! ch))
          item)
        (let ((res (##continuation-capture %park-recv-buf-cont! ch)))
          (if (eq? res %CH-RETRY)
              (%fiber-recv-buf! ch)
              res)))))

(define (fiber-recv! ch)
  (if (not (fiber-channel? ch))
      (error "fiber-recv!: expected fiber-channel" ch))
  (if (fx> (%ch-cap ch) 0)
      (%fiber-recv-buf! ch)
      ;; Unbuffered rendezvous (cap == 0) with relaxed hint
      (let ((swq (%ch-send-waiters ch)))
        (if (not (%wq-head swq))
            (##continuation-capture %park-recv-unbuf-cont! ch)
            (let ((lock (%ch-lock ch)))
              (%spin-lock! lock)
              (if (not (%wq-empty? swq))
                  (let* ((sk (%wq-pop! swq))
                         (sval (%fk-val sk)))
                    (%spin-unlock! lock)
                    (%fk-val-set! sk #t)
                    (%sched-push-lifo! (%current-wctx) sk)
                    sval)
                  (begin
                    (%spin-unlock! lock)
                    (##continuation-capture %park-recv-unbuf-cont! ch))))))))

;;;----------------------------------------------------------------------------
;;; Multi-Core M:N Work-Stealing Direct-Switch Trampoline
;;; (Sticky Victim Locality + Inline Chase-Lev Deque + Recycled %fiber-k)

(define (%worker-try-steal ctx num-workers deques)
  (if (fx<= num-workers 1)
      #f
      (let ((wid (%wctx-wid ctx))
            (start (%wctx-steal-cursor ctx)))
        (let loop ((tried 1) (victim start))
          (if (fx>= tried num-workers)
              #f
              (let ((v (if (fx= victim wid)
                           (let ((n (fx+ victim 1)))
                             (if (fx>= n num-workers) 0 n))
                           victim)))
                (let ((task (%dq-steal! (##vector-ref deques v))))
                  (if task
                      (begin
                        (%wctx-steal-cursor-set! ctx v)
                        task)
                      (let ((nxt (fx+ v 1)))
                        (loop (fx+ tried 1)
                              (if (fx>= nxt num-workers) 0 nxt)))))))))))

(define (%worker-poll-task ctx)
  (let* ((sched (%wctx-sched ctx))
         (ticks (%wctx-ticks ctx))
         (local-dq (%wctx-dq ctx))
         (task #f))
    (%wctx-ticks-set! ctx (fx+ ticks 1))
    ;; 0. Every 32 ticks poll global-q for fairness (skipped in 1 load if empty!)
    (if (fx= (fxand ticks 31) 31)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 1. Fastest path: private LIFO slot (0 atomics, 0 fences!) if streak < 8
    (if (and (not task)
             (%wctx-lifo ctx)
             (fx< (%wctx-lifo-streak ctx) %MAX-LIFO-STREAK))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx (fx+ (%wctx-lifo-streak ctx) 1))))
    ;; 2. Local inline Chase-Lev deque (zero cross-module calls)
    (if (not task)
        (let ((t (%dq-pop! local-dq)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 3. Fallback to LIFO slot if streak hit limit but local-dq was empty
    (if (and (not task) (%wctx-lifo ctx))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx 0)))
    ;; 4. Global lock-free wakeup/overflow queue (fast-skipped when pending == 0)
    (if (not task)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 5. Sticky victim-locality FIFO work-steal from peer inline deques
    (if (not task)
        (let ((stolen (%worker-try-steal ctx
                                         (%sched-num-workers sched)
                                         (%sched-deques sched))))
          (if stolen
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task stolen)))))
    task))

;; Direct symmetric coroutine handoff with %fiber-k freelist recycling,
;; empty-deque LIFO-streak bypass (zero wasted grafts when no siblings wait),
;; direct %dq-pop! switch, and lazy #f control-state restore.
(define (%sched-switch-next! ctx)
  (let ((ticks (%wctx-ticks ctx))
        (lifo (%wctx-lifo ctx))
        (streak (%wctx-lifo-streak ctx))
        (dq (%wctx-dq ctx)))
    (if (and lifo
             (%fiber-k? lifo)
             (not (fx= (fxand ticks 31) 31))
             (or (fx< streak %MAX-LIFO-STREAK) (%dq-empty-rlx? dq)))
        (let ((raw-k (%fk-raw-k lifo))
              (tc (%fk-tc lifo))
              (val (%fk-val lifo)))
          (%wctx-ticks-set! ctx (fx+ ticks 1))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx
            (if (fx< streak %MAX-LIFO-STREAK) (fx+ streak 1) %MAX-LIFO-STREAK))
          (%free-fk! ctx lifo)
          (if tc (%set-tc! tc))
          (##continuation-return-no-winding raw-k val))
        (if (and (not (fx= (fxand ticks 31) 31))
                 (not (%dq-empty-rlx? dq)))
            (let ((t (%dq-pop! dq)))
              (if t
                  (begin
                    (%wctx-ticks-set! ctx (fx+ ticks 1))
                    (%wctx-lifo-streak-set! ctx 0)
                    (if (%fiber-k? t)
                        (let ((raw-k (%fk-raw-k t))
                              (tc (%fk-tc t))
                              (val (%fk-val t)))
                          (%free-fk! ctx t)
                          (if tc (%set-tc! tc))
                          (##continuation-return-no-winding raw-k val))
                        (##continuation-graft-no-winding
                         (%wctx-sched-k ctx) %worker-run-task ctx t)))
                  (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0)))
            (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0)))))

(define (%worker-run-task ctx task)
  (cond
    ((%fiber-k? task)
     (let ((raw-k (%fk-raw-k task))
           (tc (%fk-tc task))
           (val (%fk-val task)))
       (%free-fk! ctx task)
       (if tc (%set-tc! tc))
       (##continuation-return-no-winding raw-k val)))
    ((pair? task)
     ;; Zero-capture, zero-closure nursery child: (thunk . nursery)
     (let ((fn (car task))
           (n (cdr task)))
       (##with-exception-handler (%nursery-err-handler n) fn)
       (%nursery-child-done! n)
       (let ((cur-ctx (%current-wctx)))
         (if (%get-tc) (%set-tc! #f))
         (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
         (%sched-switch-next! cur-ctx))))
    (else
     ;; Detached fiber thunk
     (task)
     (let ((cur-ctx (%current-wctx)))
       (if (%get-tc) (%set-tc! #f))
       (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
       (%sched-switch-next! cur-ctx)))))

(define (%worker-dispatch ctx idle-spins)
  (let ((task (%worker-poll-task ctx)))
    (if task
        (%worker-run-task ctx task)
        (if (%sched-quiescent? (%wctx-sched ctx))
            #!void
            (begin
              (if (fx>= idle-spins 16)
                  (begin (thread-yield!) (%worker-dispatch ctx 0))
                  (%worker-dispatch ctx (fx+ idle-spins 1))))))))

(define (%worker-loop sched wid)
  (let* ((w (%sched-num-workers sched))
         (deques (%sched-deques sched))
         (local-dq (##vector-ref deques wid))
         (spawned (##vector-ref (%sched-spawned-vec sched) wid))
         (completed (##vector-ref (%sched-completed-vec sched) wid))
         (init-victim (if (fx> w 1)
                          (let ((n (fx+ wid 1))) (if (fx>= n w) 0 n))
                          0))
         (ctx (%make-worker-ctx sched wid local-dq spawned completed
                                #f 0 0 #f #f 0 init-victim)))
    (macro-thread-specific-set! (##current-thread) ctx)
    (if (%get-tc) (%set-tc! #f))
    ;; Capture the carrier's single reusable trampoline continuation once
    (##continuation-capture
     (lambda (base-k)
       (%wctx-sched-k-set! ctx base-k)
       (%worker-dispatch ctx 0)))))

(define (run-fibers thunk #!key (workers (##current-vm-processor-count)))
  (if (not (procedure? thunk))
      (error "run-fibers: expected thunk" thunk))
  (let* ((w (max 1 (if (fixnum? workers) workers 1)))
         (deques (let ((v (make-vector w #f)))
                   (let loop ((i 0))
                     (if (fx< i w)
                         (begin (##vector-set! v i (%make-local-dq))
                                (loop (fx+ i 1)))))
                   v))
         (spawned-vec (let ((v (make-vector w #f)))
                        (let loop ((i 0))
                          (if (fx< i w)
                              (begin (##vector-set! v i (%make-padded-fxatom (if (fx= i 0) 1 0)))
                                     (loop (fx+ i 1)))))
                        v))
         (completed-vec (let ((v (make-vector w #f)))
                          (let loop ((i 0))
                            (if (fx< i w)
                                (begin (##vector-set! v i (%make-padded-fxatom 0))
                                       (loop (fx+ i 1)))))
                          v))
         (global-q (make-lf-queue))
         (global-pending (%make-padded-fxatom 0))
         (root-done (%make-fxatom 0))
         (root-box (cons #f #f))
         (sched (%make-scheduler w deques global-q global-pending
                                 spawned-vec completed-vec root-done root-box)))
    (%sched-enqueue-global!
     sched
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (set-car! root-box #f)
          (set-cdr! root-box e)
          (%fxatom-set-rel! root-done 1))
        (lambda ()
          (let ((res (thunk)))
            (set-car! root-box #t)
            (set-cdr! root-box res)
            (%fxatom-set-rel! root-done 1))))))
    (let ((threads
           (let loop ((i 0) (acc '()))
             (if (fx= i w)
                 acc
                 (loop (fx+ i 1)
                       (cons (thread-start!
                              (make-thread
                               (lambda () (%worker-loop sched i))))
                             acc))))))
      (for-each thread-join! threads))
    (if (car root-box)
        (cdr root-box)
        (raise (cdr root-box)))))

;;;============================================================================
