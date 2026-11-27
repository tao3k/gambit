;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Features:
;;;   - M:N work-stealing scheduler with private LIFO slot and Chase-Lev deques
;;;   - Sharded 128B-padded per-worker monotonic quiescence counters
;;;   - Structured concurrency nurseries with zero-capture child exception handling
;;;   - Lock-free bounded MPMC ring channels with linearizable direct handoff
;;;   - Per-carrier recycled continuation wrapper freelist

(##supply-module gambit/fiber)

(##namespace ("gambit/fiber#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##namespace (""
  make-thread
  thread-start!
  thread-join!
  thread-yield!
  current-thread
  thread-specific
  thread-specific-set!
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
  (block))

;;;----------------------------------------------------------------------------
;;; Inline C23 Atomic Primitives (Zero Cross-Module SRFI-230 Overhead on C Target)
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

;; 128-byte (16-word) cache-line-padded fixnum atomic box for Apple Silicon
;; per-worker / producer-consumer counters (0% L2 false sharing across 12 cores).
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

;; Indexed fixnum-vector atomics for Vyukov MPMC ring sequence numbers
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

(define (%seq-cst-fence!)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order(4); ___RESULT = ___VOID;")
   (atomic-fence (memory-order sequentially-consistent))))

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
  (tc    %fk-tc    %fk-tc-set!)     ;; saved per-fiber (##thread-control-state)
  (val   %fk-val   %fk-val-set!)    ;; intrusive resume/send payload
  (next  %fk-next  %fk-next-set!))  ;; intrusive wait-queue / freelist link

(define-type %scheduler
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000001
  constructor: %make-scheduler
  predicate: %scheduler?
  (num-workers   %sched-num-workers)
  (deques        %sched-deques)        ;; vector of W ws-deque
  (global-q      %sched-global-q)      ;; lf-queue for wakeups & overflow
  (spawned-vec   %sched-spawned-vec)   ;; vector of W 128B-padded monotonic counters
  (completed-vec %sched-completed-vec) ;; vector of W 128B-padded monotonic counters
  (root-done     %sched-root-done)     ;; fxatom (0 -> 1)
  (root-box      %sched-root-box))     ;; box holding (ok? . val-or-exc)

(define-type %worker-ctx
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000002
  constructor: %make-worker-ctx
  predicate: %worker-ctx?
  (sched       %wctx-sched)
  (wid         %wctx-wid)
  (dq          %wctx-dq)
  (spawned     %wctx-spawned)          ;; owner-only 128B-padded monotonic spawned
  (completed   %wctx-completed)        ;; owner-only 128B-padded monotonic completed
  (lifo        %wctx-lifo        %wctx-lifo-set!)        ;; private 1-slot LIFO (0 atomics!)
  (lifo-streak %wctx-lifo-streak %wctx-lifo-streak-set!) ;; anti-starvation counter
  (ticks       %wctx-ticks       %wctx-ticks-set!)       ;; fairness poll counter
  (sched-k     %wctx-sched-k     %wctx-sched-k-set!)     ;; reusable trampoline continuation
  (fk-pool     %wctx-fk-pool     %wctx-fk-pool-set!)     ;; private zero-atomic %fiber-k freelist
  (fk-pool-len %wctx-fk-pool-len %wctx-fk-pool-len-set!))

(define (%current-wctx)
  (let ((ctx (thread-specific (current-thread))))
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

;; Push to local Chase-Lev deque (spilling to unbounded lock-free global-q if full).
(define (%sched-push-dq! ctx task)
  (if (not (ws-deque-push! (%wctx-dq ctx) task))
      (lf-queue-enqueue! (%sched-global-q (%wctx-sched ctx)) task)))

;; Push to private LIFO slot, evicting any prior occupant to Chase-Lev deque.
(define (%sched-push-lifo! ctx task)
  (let ((prev (%wctx-lifo ctx)))
    (%wctx-lifo-set! ctx task)
    (if prev
        (%sched-push-dq! ctx prev))))

;; Wake task onto current carrier's LIFO slot if inside this scheduler, else global-q.
(define (%sched-wake! sched task)
  (let ((ctx (thread-specific (current-thread))))
    (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) sched))
        (%sched-push-lifo! ctx task)
        (lf-queue-enqueue! (%sched-global-q sched) task))))

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
;;; Inline C23 Non-Blocking Spinlock Helper (Slow-Path Waiters & Unbuffered)

(define (%spin-lock! box)
  (if (not (fx= (%fxatom-cas-acq! box 0 1) 0))
      (let loop ((spins 1))
        (if (not (fx= (%fxatom-cas-acq! box 0 1) 0))
            (if (fx>= spins 64)
                (begin (thread-yield!) (loop 0))
                (loop (fx+ spins 1)))))))

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
;; completed all dynamic-wind after thunks of the aborting child fiber!
(define (%nursery-child-abort! n exc)
  (%nursery-record-error! n exc)
  (%nursery-child-done! n)
  (let ((cur-ctx (%current-wctx)))
    (##thread-control-state-set! #f)
    (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
    (%worker-dispatch cur-ctx 0)))

;; Zero-closure multi-arg continuation receiver for nursery join park
(define (%park-nursery-cont! raw-k n)
  (let* ((ctx (%current-wctx))
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc #!void))
         (lock (%nursery-lock n))
         (wake-now? #f))
    (##thread-control-state-set! #f)
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
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc #!void)))
    (##thread-control-state-set! #f)
    (%sched-push-dq! ctx fk)
    (%sched-switch-next! ctx)))

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
;;; Intrusive Zero-Cons FIFO Wait Queue & Lock-Free Vyukov Bounded MPMC Channel
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
  (seq          %ch-seq)         ;; Vyukov per-slot sequence fixnums
  (tail         %ch-tail)        ;; 128B-padded producer cursor
  (head         %ch-head)        ;; 128B-padded consumer cursor
  (rx-waiters   %ch-rx-waiters)  ;; 128B-padded count of parked receivers (wait-lock protected writes)
  (tx-waiters   %ch-tx-waiters)  ;; 128B-padded count of parked senders (wait-lock protected writes)
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

;; Lock-free Vyukov bounded MPMC ring push (2*pos / 2*pos+1 encoding supports all cap >= 1!)
(define (%vyukov-try-push! ch val)
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
                 #t)
               (loop)))
          ((fx< dif 0)
           #f)
          (else
           (loop)))))))

;; Lock-free Vyukov bounded MPMC ring pop (2*pos+1 / 2*(pos+cap) encoding supports all cap >= 1!)
(define (%vyukov-try-pop-or! ch default)
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
          ((fx< dif 0)
           default)
          (else
           (loop)))))))

;; Slow-path wakeups (called ONLY when Dekker seq_cst counter > 0)
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

;; Zero-closure multi-arg park receivers for buffered channels (cap > 0)
(define (%park-send-buf-cont! raw-k ch val)
  (let* ((ctx (%current-wctx))
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc val))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch))
         (rxw (%ch-rx-waiters ch))
         (txw (%ch-tx-waiters ch)))
    (##thread-control-state-set! #f)
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
       (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))

(define (%park-recv-buf-cont! raw-k ch)
  (let* ((ctx (%current-wctx))
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc #f))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch))
         (rxw (%ch-rx-waiters ch))
         (txw (%ch-tx-waiters ch)))
    (##thread-control-state-set! #f)
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
         (%spin-unlock! lock))))
    (%sched-switch-next! ctx)))

;; Zero-closure multi-arg park receivers for unbuffered rendezvous (cap == 0)
(define (%park-send-unbuf-cont! raw-k ch val)
  (let* ((ctx (%current-wctx))
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc val))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (##thread-control-state-set! #f)
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
         (tc (##thread-control-state))
         (fk (%alloc-fk! ctx raw-k tc #f))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (##thread-control-state-set! #f)
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

(define (%fiber-send-buf! ch val)
  (let ((rxw (%ch-rx-waiters ch)))
    ;; Fast path A (Ping-Pong): Linearizable direct handoff ONLY when
    ;; rx-waiters > 0 AND load_acq(tail) == load_acq(head) under wait-lock!
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
                (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))))
          (%spin-unlock! lock)
          (if rk
              (begin
                (%fk-val-set! rk val)
                (%sched-push-lifo! (%current-wctx) rk)
                #t)
              (%fiber-send-buf-ring! ch val rxw)))
        (%fiber-send-buf-ring! ch val rxw))))

(define (%fiber-send-buf-ring! ch val rxw)
  ;; Fast path B (Streaming): Lock-Free Vyukov Ring Push (0 spinlocks!)
  (if (%vyukov-try-push! ch val)
      (begin
        (if (fx> (%fxatom-load-seq rxw) 0)
            (%ch-wake-one-receiver! ch))
        #t)
      (let ((res (##continuation-capture %park-send-buf-cont! ch val)))
        (if (eq? res %CH-RETRY)
            (%fiber-send-buf! ch val)
            #t))))

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
  ;; Fast path (Streaming): Lock-Free Vyukov Ring Pop (0 spinlocks!)
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
;;; Multi-Core M:N Work-Stealing Direct-Switch Trampoline (Recycled %fiber-k)

(define (%worker-try-steal wid num-workers deques)
  (if (fx<= num-workers 1)
      #f
      (let loop ((offset 1))
        (if (fx= offset num-workers)
            #f
            (let* ((victim (let ((v (fx+ wid offset)))
                             (if (fx>= v num-workers) (fx- v num-workers) v)))
                   (task (ws-deque-try-steal-or! (##vector-ref deques victim) #f)))
              (if task
                  task
                  (loop (fx+ offset 1))))))))

(define (%worker-poll-task ctx)
  (let* ((sched (%wctx-sched ctx))
         (ticks (%wctx-ticks ctx))
         (local-dq (%wctx-dq ctx))
         (global-q (%sched-global-q sched))
         (task #f))
    (%wctx-ticks-set! ctx (fx+ ticks 1))
    ;; 0. Every 32 ticks poll global-q for fairness
    (if (fx= (fxand ticks 31) 31)
        (let ((t (lf-queue-try-dequeue-or! global-q #f)))
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
    ;; 2. Local Chase-Lev deque (zero-closure sentinel pop)
    (if (not task)
        (let ((t (ws-deque-try-pop-or! local-dq #f)))
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
    ;; 4. Global lock-free wakeup/overflow queue
    (if (not task)
        (let ((t (lf-queue-try-dequeue-or! global-q #f)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 5. Work-steal FIFO from peer worker deques
    (if (not task)
        (let ((stolen (%worker-try-steal (%wctx-wid ctx)
                                         (%sched-num-workers sched)
                                         (%sched-deques sched))))
          (if stolen
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task stolen)))))
    task))

;; Direct symmetric coroutine handoff with %fiber-k freelist recycling!
;; Uses no-winding continuation switches so fiber suspension/resumption never
;; triggers spurious dynamic-wind before/after thrashing (only genuine exits
;; or exception aborts wind/unwind).
(define (%sched-switch-next! ctx)
  (let ((ticks (%wctx-ticks ctx))
        (lifo (%wctx-lifo ctx))
        (streak (%wctx-lifo-streak ctx)))
    (if (and lifo
             (%fiber-k? lifo)
             (fx< streak %MAX-LIFO-STREAK)
             (not (fx= (fxand ticks 31) 31)))
        (let ((raw-k (%fk-raw-k lifo))
              (tc (%fk-tc lifo))
              (val (%fk-val lifo)))
          (%wctx-ticks-set! ctx (fx+ ticks 1))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx (fx+ streak 1))
          (%free-fk! ctx lifo)
          (##thread-control-state-set! tc)
          (##continuation-return-no-winding raw-k val))
        (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0))))

(define (%worker-dispatch ctx idle-spins)
  (let ((task (%worker-poll-task ctx)))
    (if task
        (cond
          ((%fiber-k? task)
           (let ((raw-k (%fk-raw-k task))
                 (tc (%fk-tc task))
                 (val (%fk-val task)))
             (%free-fk! ctx task)
             (##thread-control-state-set! tc)
             (##continuation-return-no-winding raw-k val)))
          ((pair? task)
           ;; ZERO-CAPTURE, ZERO-CLOSURE NURSERY CHILD: (thunk . nursery)
           (let ((fn (car task))
                 (n (cdr task)))
             (##thread-control-state-set! #f)
             (##with-exception-handler (%nursery-err-handler n) fn)
             (%nursery-child-done! n)
             (let ((cur-ctx (%current-wctx)))
               (##thread-control-state-set! #f)
               (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
               (%sched-switch-next! cur-ctx))))
          (else
           ;; Detached fiber thunk
           (##thread-control-state-set! #f)
           (task)
           (let ((cur-ctx (%current-wctx)))
             (##thread-control-state-set! #f)
             (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
             (%sched-switch-next! cur-ctx))))
        (if (%sched-quiescent? (%wctx-sched ctx))
            #!void
            (begin
              (if (fx>= idle-spins 16)
                  (begin (thread-yield!) (%worker-dispatch ctx 0))
                  (%worker-dispatch ctx (fx+ idle-spins 1))))))))

(define (%worker-loop sched wid)
  (let* ((deques (%sched-deques sched))
         (local-dq (##vector-ref deques wid))
         (spawned (##vector-ref (%sched-spawned-vec sched) wid))
         (completed (##vector-ref (%sched-completed-vec sched) wid))
         (ctx (%make-worker-ctx sched wid local-dq spawned completed #f 0 0 #f #f 0)))
    (thread-specific-set! (current-thread) ctx)
    ;; Capture the carrier's SINGLE reusable trampoline continuation ONCE!
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
                         (begin (##vector-set! v i (make-ws-deque 512))
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
         (root-done (%make-fxatom 0))
         (root-box (cons #f #f))
         (sched (%make-scheduler w deques global-q spawned-vec completed-vec root-done root-box)))
    (lf-queue-enqueue!
     global-q
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
