;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;; (Phase C6: Sharded Quiescence Counters, Zero-Closure Nursery Tasks,
;;;  Zero-Closure Sentinel Deques & SATB-Safe In-Place Fiber Rewind)
;;;
;;; Formally verified in:
;;;   - dev/refactoring/modern-c/models/quint/fiber_scheduler_nursery_smp.qnt
;;;   - dev/refactoring/modern-c/models/lean/FiberNurseryRefinement.lean
;;;   - tests/contracts/modern-c/gc-ffi/fiber-nursery-smp/harness.c
;;;   - dev/refactoring/modern-c/models/quint/fiber_direct_switch_lifo_smp.qnt
;;;   - dev/refactoring/modern-c/models/lean/FiberDirectSwitchLifoRefinement.lean
;;;   - tests/contracts/modern-c/gc-ffi/fiber-direct-switch-lifo/harness.c
;;;   - dev/refactoring/modern-c/models/quint/sharded_quiescence_and_oneshot_fiber_rewind_smp.qnt
;;;   - dev/refactoring/modern-c/models/lean/ShardedQuiescenceRefinement.lean
;;;   - tests/contracts/modern-c/gc-ffi/sharded-quiescence-smp/harness.c

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
  (block))

;;;----------------------------------------------------------------------------
;;; Scheduler, Worker Context & Lightweight Intrusive Fiber Continuation

(define %MAX-LIFO-STREAK 8)

(define-type %fiber-k
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000006
  constructor: %make-fiber-k
  predicate: %fiber-k?
  (raw-k %fk-raw-k %fk-raw-k-set!)  ;; native Gambit continuation (cleared on resume)
  (tc    %fk-tc    %fk-tc-set!)     ;; saved per-fiber (##thread-control-state)
  (val   %fk-val   %fk-val-set!)    ;; intrusive resume/send payload
  (next  %fk-next  %fk-next-set!))  ;; intrusive FIFO wait-queue link

(define-type %scheduler
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000001
  constructor: %make-scheduler
  predicate: %scheduler?
  (num-workers   %sched-num-workers)
  (deques        %sched-deques)        ;; vector of W ws-deque
  (global-q      %sched-global-q)      ;; lf-queue for wakeups & overflow
  (spawned-vec   %sched-spawned-vec)   ;; vector of W per-worker monotonic atomic-fxbox
  (completed-vec %sched-completed-vec) ;; vector of W per-worker monotonic atomic-fxbox
  (root-done     %sched-root-done)     ;; atomic-fxbox (0 -> 1)
  (root-box      %sched-root-box))     ;; box holding (ok? . val-or-exc)

(define-type %worker-ctx
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000002
  constructor: %make-worker-ctx
  predicate: %worker-ctx?
  (sched       %wctx-sched)
  (wid         %wctx-wid)
  (dq          %wctx-dq)
  (spawned     %wctx-spawned)          ;; owner-only monotonic spawned atomic-fxbox
  (completed   %wctx-completed)        ;; owner-only monotonic completed atomic-fxbox
  (lifo        %wctx-lifo        %wctx-lifo-set!)        ;; private 1-slot LIFO (0 atomics!)
  (lifo-streak %wctx-lifo-streak %wctx-lifo-streak-set!) ;; anti-starvation counter
  (ticks       %wctx-ticks       %wctx-ticks-set!)       ;; fairness poll counter
  (sched-k     %wctx-sched-k     %wctx-sched-k-set!))    ;; reusable trampoline continuation

(define (%current-wctx)
  (let ((ctx (thread-specific (current-thread))))
    (if (%worker-ctx? ctx)
        ctx
        (error "fiber operation called outside run-fibers"))))

;; Push to local Chase-Lev deque (spilling to unbounded lock-free global-q if full).
(define (%sched-push-dq! ctx task)
  (if (not (ws-deque-push! (%wctx-dq ctx) task))
      (lf-queue-enqueue! (%sched-global-q (%wctx-sched ctx)) task)))

;; Push to private LIFO slot, evicting any prior occupant to Chase-Lev deque
;; (strictly conserves tasks and allows idle peer cores to steal evicted work).
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

;; Formally proven sharded quiescence check (Quint + Lean 4 + CBMC --mm pso):
;; MUST read ALL completed[0..W-1] FIRST, execute seq_cst fence, then read
;; ALL spawned[0..W-1]. Because every fiber's spawned[ws]++ happens-before its
;; completed[wc]++, C == S guarantees ZERO live or queued fibers remain!
(define (%sched-quiescent? sched)
  (let ((w (%sched-num-workers sched))
        (cvec (%sched-completed-vec sched))
        (svec (%sched-spawned-vec sched)))
    (let cloop ((i 0) (c 0))
      (if (fx< i w)
          (cloop (fx+ i 1)
                 (fx+ c (atomic-fxbox-ref (vector-ref cvec i) (memory-order acquire))))
          (begin
            (atomic-fence (memory-order sequentially-consistent))
            (let sloop ((j 0) (s 0))
              (if (fx< j w)
                  (sloop (fx+ j 1)
                         (fx+ s (atomic-fxbox-ref (vector-ref svec j) (memory-order acquire))))
                  (fx= c s))))))))

;;;----------------------------------------------------------------------------
;;; Tiny Lock-Free Spinlock Helper (for channel & nursery critical sections)

(define (%spin-lock! box)
  (let loop ((spins 0))
    (if (fx= (atomic-fxbox-compare-and-swap! box 0 1 (memory-order acquire)) 0)
        #t
        (begin
          (if (fx>= spins 64)
              (begin (thread-yield!) (loop 0))
              (loop (fx+ spins 1)))))))

(define (%spin-unlock! box)
  (atomic-fxbox-set! box 0 (memory-order release)))

;;;----------------------------------------------------------------------------
;;; Structured Concurrency Nursery (Zero Orphaned Fibers, Zero Per-Spawn Closure)

(define-type nursery
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000003
  constructor: %make-nursery
  predicate: nursery?
  (sched       %nursery-sched)
  (active      %nursery-active)      ;; atomic-fxbox (starts at 1 for parent scope)
  (lock        %nursery-lock)        ;; atomic-fxbox spinlock
  (waiter-k    %nursery-waiter-k     %nursery-waiter-k-set!)
  (first-err   %nursery-first-err    %nursery-first-err-set!)
  (has-err?    %nursery-has-err?     %nursery-has-err?-set!)
  (err-handler %nursery-err-handler  %nursery-err-handler-set!)) ;; pre-allocated once!

(define (%nursery-record-error! n exc)
  (%spin-lock! (%nursery-lock n))
  (if (not (%nursery-has-err? n))
      (begin
        (%nursery-has-err?-set! n #t)
        (%nursery-first-err-set! n exc)))
  (%spin-unlock! (%nursery-lock n)))

(define (%nursery-child-done! n)
  ;; atomic-fxbox-/fetch! returns the PREVIOUS value before subtraction.
  (let ((prev (atomic-fxbox-/fetch! (%nursery-active n) 1 (memory-order acquire-release))))
    (if (fx= prev 1)
        ;; We were the last active entity; wake parked parent if present
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

(define (%park-nursery! n)
  (##continuation-capture
   (lambda (raw-k)
     (let* ((ctx (%current-wctx))
            (tc (##thread-control-state))
            (fk (%make-fiber-k raw-k tc #!void #f))
            (lock (%nursery-lock n))
            (wake-now? #f))
       (##thread-control-state-set! #f)
       (%spin-lock! lock)
       (if (fx= (atomic-fxbox-ref (%nursery-active n) (memory-order acquire)) 0)
           (set! wake-now? #t)
           (%nursery-waiter-k-set! n fk))
       (%spin-unlock! lock)
       (if wake-now?
           (%sched-push-lifo! ctx fk))
       (%sched-switch-next! ctx)))))

(define (with-nursery proc)
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (n (%make-nursery sched
                           (make-atomic-fxbox 1)
                           (make-atomic-fxbox 0)
                           #f
                           #f
                           #f
                           #f))
         (eh (lambda (e) (%nursery-record-error! n e)))
         (parent-res #f))
    (%nursery-err-handler-set! n eh)
    (with-exception-catcher
     eh
     (lambda ()
       (set! parent-res (proc n))))
    ;; Parent scope finished: decrement our own count (1) and park if children remain
    (let ((prev (atomic-fxbox-/fetch! (%nursery-active n) 1 (memory-order acquire-release))))
      (if (fx> prev 1)
          (%park-nursery! n)))
    (if (%nursery-has-err? n)
        (raise (%nursery-first-err n))
        parent-res)))

;;;----------------------------------------------------------------------------
;;; Direct O(1) Fiber Spawn (Zero Closures, Zero Global Atomic Contention)

(define (fiber-worker-count)
  (%sched-num-workers (%wctx-sched (%current-wctx))))

;; Cooperative yield: push to local Chase-Lev deque (NOT lifo-slot) so ready
;; peers run first and idle cores can steal cleanly.
(define (fiber-yield)
  (##continuation-capture
   (lambda (raw-k)
     (let* ((ctx (%current-wctx))
            (tc (##thread-control-state))
            (fk (%make-fiber-k raw-k tc #!void #f)))
       (##thread-control-state-set! #f)
       (%sched-push-dq! ctx fk)
       (%sched-switch-next! ctx)))))

;; Direct O(1) fiber spawn:
;;   - Increments ONLY this worker's private monotonic `spawned` counter with
;;     release ordering BEFORE publishing the task (zero cross-core contention!).
;;   - Nursery tasks enqueue a single pair `(cons thunk n)` (0 closures!).
(define (fiber-spawn thunk #!optional (n #f))
  (let ((ctx (%current-wctx)))
    (if n
        (begin
          (if (not (nursery? n))
              (error "fiber-spawn: expected nursery" n))
          (atomic-fxbox+/fetch! (%nursery-active n) 1 (memory-order acquire-release))
          (atomic-fxbox+/fetch! (%wctx-spawned ctx) 1 (memory-order release))
          (%sched-push-lifo! ctx (cons thunk n))
          #!void)
        (begin
          (atomic-fxbox+/fetch! (%wctx-spawned ctx) 1 (memory-order release))
          (%sched-push-lifo! ctx thunk)
          #!void))))

;;;----------------------------------------------------------------------------
;;; Intrusive Zero-Cons FIFO Wait Queue & Direct-Handoff Fiber Channel

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
  (lock         %ch-lock)
  (cap          %ch-cap)
  (buf          %ch-buf)
  (head         %ch-head  %ch-head-set!)
  (tail         %ch-tail  %ch-tail-set!)
  (count        %ch-count %ch-count-set!)
  (recv-waiters %ch-recv-waiters)
  (send-waiters %ch-send-waiters))

(define (make-fiber-channel #!optional (capacity 16))
  (if (or (not (fixnum? capacity)) (fx< capacity 0))
      (error "make-fiber-channel: capacity must be a non-negative fixnum" capacity))
  (%make-fiber-channel
   (make-atomic-fxbox 0)
   capacity
   (if (fx> capacity 0) (make-vector capacity #f) '#())
   0
   0
   0
   (%make-wait-q #f #f)
   (%make-wait-q #f #f)))

(define (%park-send! ch val)
  (##continuation-capture
   (lambda (raw-k)
     (let* ((ctx (%current-wctx))
            (tc (##thread-control-state))
            (fk (%make-fiber-k raw-k tc val #f))
            (lock (%ch-lock ch))
            (cap (%ch-cap ch))
            (rwq (%ch-recv-waiters ch))
            (swq (%ch-send-waiters ch)))
       (##thread-control-state-set! #f)
       (%spin-lock! lock)
       (cond
         ((not (%wq-empty? rwq))
          (let ((rk (%wq-pop! rwq)))
            (%spin-unlock! lock)
            (%fk-val-set! rk val)
            (%fk-val-set! fk #t)
            (%sched-push-lifo! ctx fk)
            (%sched-push-lifo! ctx rk)))
         ((fx< (%ch-count ch) cap)
          (let ((t (%ch-tail ch)))
            (vector-set! (%ch-buf ch) t val)
            (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
            (%ch-count-set! ch (fx+ (%ch-count ch) 1))
            (%spin-unlock! lock)
            (%fk-val-set! fk #t)
            (%sched-push-lifo! ctx fk)))
         (else
          (%wq-push! swq fk)
          (%spin-unlock! lock)))
       (%sched-switch-next! ctx)))))

(define (fiber-send! ch val)
  (let* ((ctx (%current-wctx))
         (lock (%ch-lock ch))
         (cap (%ch-cap ch))
         (rwq (%ch-recv-waiters ch)))
    (%spin-lock! lock)
    (cond
      ;; Case 1: Direct zero-alloc rendezvous handoff to a parked receiver
      ((not (%wq-empty? rwq))
       (let ((rk (%wq-pop! rwq)))
         (%spin-unlock! lock)
         (%fk-val-set! rk val)
         (%sched-push-lifo! ctx rk)
         #t))
      ;; Case 2: Ring buffer has free space
      ((fx< (%ch-count ch) cap)
       (let ((t (%ch-tail ch)))
         (vector-set! (%ch-buf ch) t val)
         (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
         (%ch-count-set! ch (fx+ (%ch-count ch) 1))
         (%spin-unlock! lock)
         #t))
      ;; Case 3: Full -> park directly via native continuation capture
      (else
       (%spin-unlock! lock)
       (%park-send! ch val)))))

(define (%park-recv! ch)
  (##continuation-capture
   (lambda (raw-k)
     (let* ((ctx (%current-wctx))
            (tc (##thread-control-state))
            (fk (%make-fiber-k raw-k tc #f #f))
            (lock (%ch-lock ch))
            (cap (%ch-cap ch))
            (rwq (%ch-recv-waiters ch))
            (swq (%ch-send-waiters ch)))
       (##thread-control-state-set! #f)
       (%spin-lock! lock)
       (cond
         ((fx> (%ch-count ch) 0)
          (let* ((h (%ch-head ch))
                 (buf (%ch-buf ch))
                 (item (vector-ref buf h))
                 (nh (let ((x (fx+ h 1))) (if (fx= x cap) 0 x))))
            (vector-set! buf h #f)
            (%ch-head-set! ch nh)
            (if (not (%wq-empty? swq))
                (let* ((sk (%wq-pop! swq))
                       (sval (%fk-val sk))
                       (t (%ch-tail ch)))
                  (vector-set! buf t sval)
                  (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
                  (%spin-unlock! lock)
                  (%fk-val-set! sk #t)
                  (%fk-val-set! fk item)
                  (%sched-push-lifo! ctx sk)
                  (%sched-push-lifo! ctx fk))
                (begin
                  (%ch-count-set! ch (fx- (%ch-count ch) 1))
                  (%spin-unlock! lock)
                  (%fk-val-set! fk item)
                  (%sched-push-lifo! ctx fk)))))
         ((not (%wq-empty? swq))
          (let* ((sk (%wq-pop! swq))
                 (sval (%fk-val sk)))
            (%spin-unlock! lock)
            (%fk-val-set! sk #t)
            (%fk-val-set! fk sval)
            (%sched-push-lifo! ctx sk)
            (%sched-push-lifo! ctx fk)))
         (else
          (%wq-push! rwq fk)
          (%spin-unlock! lock)))
       (%sched-switch-next! ctx)))))

(define (fiber-recv! ch)
  (let* ((ctx (%current-wctx))
         (lock (%ch-lock ch))
         (cap (%ch-cap ch))
         (swq (%ch-send-waiters ch)))
    (%spin-lock! lock)
    (cond
      ;; Case 1: Buffered item available
      ((fx> (%ch-count ch) 0)
       (let* ((h (%ch-head ch))
              (buf (%ch-buf ch))
              (item (vector-ref buf h))
              (nh (let ((x (fx+ h 1))) (if (fx= x cap) 0 x))))
         (vector-set! buf h #f)
         (%ch-head-set! ch nh)
         (if (not (%wq-empty? swq))
             ;; Refill slot from oldest parked sender & wake it (zero cons!)
             (let* ((sk (%wq-pop! swq))
                    (sval (%fk-val sk))
                    (t (%ch-tail ch)))
               (vector-set! buf t sval)
               (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
               (%spin-unlock! lock)
               (%fk-val-set! sk #t)
               (%sched-push-lifo! ctx sk)
               item)
             (begin
               (%ch-count-set! ch (fx- (%ch-count ch) 1))
               (%spin-unlock! lock)
               item))))
      ;; Case 2: Unbuffered rendezvous (cap == 0) with a parked sender
      ((not (%wq-empty? swq))
       (let* ((sk (%wq-pop! swq))
              (sval (%fk-val sk)))
         (%spin-unlock! lock)
         (%fk-val-set! sk #t)
         (%sched-push-lifo! ctx sk)
         sval))
      ;; Case 3: Empty -> park directly via native continuation capture
      (else
       (%spin-unlock! lock)
       (%park-recv! ch)))))

;;;----------------------------------------------------------------------------
;;; Multi-Core M:N Work-Stealing Direct-Switch Trampoline (Zero-Closure Poll)

(define (%worker-try-steal wid num-workers deques)
  (if (fx<= num-workers 1)
      #f
      (let loop ((offset 1))
        (if (fx= offset num-workers)
            #f
            (let* ((victim (let ((v (fx+ wid offset)))
                             (if (fx>= v num-workers) (fx- v num-workers) v)))
                   (task (ws-deque-try-steal-or! (vector-ref deques victim) #f)))
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
    ;; 4. Global lock-free wakeup/overflow queue (zero-closure sentinel pop)
    (if (not task)
        (let ((t (lf-queue-try-dequeue-or! global-q #f)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 5. Work-steal FIFO from peer worker deques (zero-closure sentinel steal)
    (if (not task)
        (let ((stolen (%worker-try-steal (%wctx-wid ctx)
                                         (%sched-num-workers sched)
                                         (%sched-deques sched))))
          (if stolen
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task stolen)))))
    task))

;; Direct symmetric coroutine handoff with SATB-safe in-place one-shot rewind!
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
          (%fk-raw-k-set! lifo #f)
          (%fk-tc-set! lifo #f)
          (%fk-val-set! lifo #f)
          (##thread-control-state-set! tc)
          (##continuation-try-rewind-prompt! #f raw-k val))
        (##continuation-graft (%wctx-sched-k ctx) %worker-dispatch ctx 0))))

(define (%worker-dispatch ctx idle-spins)
  (let ((task (%worker-poll-task ctx)))
    (if task
        (cond
          ((%fiber-k? task)
           ;; ZERO-CAPTURE DIRECT RESUME + SATB-SAFE IN-PLACE STACK REWIND!
           (let ((raw-k (%fk-raw-k task))
                 (tc (%fk-tc task))
                 (val (%fk-val task)))
             (%fk-raw-k-set! task #f)
             (%fk-tc-set! task #f)
             (%fk-val-set! task #f)
             (##thread-control-state-set! tc)
             (##continuation-try-rewind-prompt! #f raw-k val)))
          ((pair? task)
           ;; ZERO-CLOSURE NURSERY CHILD: (thunk . nursery)
           (let ((fn (car task))
                 (n (cdr task)))
             (##thread-control-state-set! #f)
             (with-exception-catcher (%nursery-err-handler n) fn)
             (%nursery-child-done! n)
             (let ((cur-ctx (%current-wctx)))
               (##thread-control-state-set! #f)
               (atomic-fxbox+/fetch! (%wctx-completed cur-ctx) 1 (memory-order release))
               (%sched-switch-next! cur-ctx))))
          (else
           ;; Detached fiber thunk
           (##thread-control-state-set! #f)
           (task)
           (let ((cur-ctx (%current-wctx)))
             (##thread-control-state-set! #f)
             (atomic-fxbox+/fetch! (%wctx-completed cur-ctx) 1 (memory-order release))
             (%sched-switch-next! cur-ctx))))
        (if (%sched-quiescent? (%wctx-sched ctx))
            #!void
            (begin
              (if (fx>= idle-spins 16)
                  (begin (thread-yield!) (%worker-dispatch ctx 0))
                  (%worker-dispatch ctx (fx+ idle-spins 1))))))))

(define (%worker-loop sched wid)
  (let* ((deques (%sched-deques sched))
         (local-dq (vector-ref deques wid))
         (spawned (vector-ref (%sched-spawned-vec sched) wid))
         (completed (vector-ref (%sched-completed-vec sched) wid))
         (ctx (%make-worker-ctx sched wid local-dq spawned completed #f 0 0 #f)))
    (thread-specific-set! (current-thread) ctx)
    ;; Capture the carrier's SINGLE reusable trampoline continuation ONCE!
    (##continuation-capture
     (lambda (base-k)
       (%wctx-sched-k-set! ctx base-k)
       (%worker-dispatch ctx 0)))))

(define (run-fibers thunk #!key (workers (##current-vm-processor-count)))
  (let* ((w (max 1 (if (fixnum? workers) workers 1)))
         (deques (let ((v (make-vector w #f)))
                   (let loop ((i 0))
                     (if (fx< i w)
                         (begin (vector-set! v i (make-ws-deque 512))
                                (loop (fx+ i 1)))))
                   v))
         (spawned-vec (let ((v (make-vector w #f)))
                        (let loop ((i 0))
                          (if (fx< i w)
                              (begin (vector-set! v i (make-atomic-fxbox (if (fx= i 0) 1 0)))
                                     (loop (fx+ i 1)))))
                        v))
         (completed-vec (let ((v (make-vector w #f)))
                          (let loop ((i 0))
                            (if (fx< i w)
                                (begin (vector-set! v i (make-atomic-fxbox 0))
                                       (loop (fx+ i 1)))))
                          v))
         (global-q (make-lf-queue))
         (root-done (make-atomic-fxbox 0))
         (root-box (cons #f #f))
         (sched (%make-scheduler w deques global-q spawned-vec completed-vec root-done root-box)))
    ;; Seed root fiber onto global queue (pre-accounted as spawned[0] = 1)
    (lf-queue-enqueue!
     global-q
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (set-car! root-box #f)
          (set-cdr! root-box e)
          (atomic-fxbox-set! root-done 1 (memory-order release)))
        (lambda ()
          (let ((res (thunk)))
            (set-car! root-box #t)
            (set-cdr! root-box res)
            (atomic-fxbox-set! root-done 1 (memory-order release)))))))
    ;; Launch W carrier worker threads
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
