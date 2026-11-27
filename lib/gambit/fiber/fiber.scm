;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Formally verified in:
;;;   - dev/refactoring/modern-c/models/quint/fiber_scheduler_nursery_smp.qnt
;;;   - dev/refactoring/modern-c/models/lean/FiberNurseryRefinement.lean
;;;   - tests/contracts/modern-c/gc-ffi/fiber-nursery-smp/harness.c
;;;
;;; Architecture:
;;;   - M:N work-stealing scheduler with per-worker lock-free Chase-Lev deques
;;;     (ws-deque) + lock-free Michael-Scott global/wakeup queue (lf-queue).
;;;   - One-shot effect continuations from (gambit effect) for cooperative
;;;     yield, channel parking/waking, and structured nursery join.
;;;   - Carrier-thread-local worker context stored in internal carrier
;;;     thread-specific so stolen fibers always push to the currently executing
;;;     carrier's private Chase-Lev deque (strict single-producer invariant).

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
(##include "~~lib/gambit/effect/effect#.scm")
(##include "~~lib/gambit/concurrent/concurrent#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "fiber#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (block))

;;;----------------------------------------------------------------------------
;;; Internal Effects & Scheduler Structures

(define %eff-spawn (make-effect 'fiber-spawn))
(define %eff-yield (make-effect 'fiber-yield))
(define %eff-park  (make-effect 'fiber-park))

(define-type %scheduler
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000001
  constructor: %make-scheduler
  predicate: %scheduler?
  (num-workers   %sched-num-workers)
  (deques        %sched-deques)        ;; vector of W ws-deque
  (global-q      %sched-global-q)      ;; lf-queue for wakeups & overflow
  (active-fibers %sched-active-fibers) ;; atomic-fxbox of non-completed fibers
  (root-done     %sched-root-done)     ;; atomic-fxbox (0 -> 1)
  (root-box      %sched-root-box)      ;; box holding (ok? . val-or-exc)
  )

(define-type %worker-ctx
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000002
  constructor: %make-worker-ctx
  predicate: %worker-ctx?
  (sched %wctx-sched)
  (wid   %wctx-wid)
  (dq    %wctx-dq))

(define (%current-wctx)
  (let ((ctx (thread-specific (current-thread))))
    (if (%worker-ctx? ctx)
        ctx
        (error "fiber operation called outside run-fibers"))))

(define (%sched-enqueue-local! task)
  (let ((ctx (%current-wctx)))
    (if (not (ws-deque-push! (%wctx-dq ctx) task))
        (lf-queue-enqueue! (%sched-global-q (%wctx-sched ctx)) task))))

(define (%sched-enqueue-global! sched task)
  (lf-queue-enqueue! (%sched-global-q sched) task))

;; Enqueue to current worker's local deque if inside a fiber worker, else global-q
(define (%sched-wake! sched task)
  (let ((ctx (thread-specific (current-thread))))
    (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) sched))
        (if (not (ws-deque-push! (%wctx-dq ctx) task))
            (lf-queue-enqueue! (%sched-global-q sched) task))
        (lf-queue-enqueue! (%sched-global-q sched) task))))

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
;;; Structured Concurrency Nursery (Zero Orphaned Fibers)

(define-type nursery
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000003
  constructor: %make-nursery
  predicate: nursery?
  (sched     %nursery-sched)
  (active    %nursery-active)    ;; atomic-fxbox (starts at 1 for parent scope)
  (lock      %nursery-lock)      ;; atomic-fxbox spinlock
  (waiter-k  %nursery-waiter-k   %nursery-waiter-k-set!)
  (first-err %nursery-first-err  %nursery-first-err-set!)
  (has-err?  %nursery-has-err?   %nursery-has-err?-set!))

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
              (%sched-wake! (%nursery-sched n) wk))))))

(define (with-nursery proc)
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (n (%make-nursery sched
                           (make-atomic-fxbox 1)
                           (make-atomic-fxbox 0)
                           #f
                           #f
                           #f))
         (parent-res #f))
    (with-exception-catcher
     (lambda (e)
       (%nursery-record-error! n e))
     (lambda ()
       (set! parent-res (proc n))))
    ;; Parent scope finished: decrement our own count (1) and wait if children remain
    (let ((prev (atomic-fxbox-/fetch! (%nursery-active n) 1 (memory-order acquire-release))))
      (if (fx> prev 1)
          (perform %eff-park
                   (lambda (k)
                     (let ((lock (%nursery-lock n))
                           (wake-now? #f))
                       (%spin-lock! lock)
                       (if (fx= (atomic-fxbox-ref (%nursery-active n) (memory-order acquire)) 0)
                           (set! wake-now? #t)
                           (%nursery-waiter-k-set! n k))
                       (%spin-unlock! lock)
                       (if wake-now?
                           (%sched-wake! sched k)))))))
    (if (%nursery-has-err? n)
        (raise (%nursery-first-err n))
        parent-res)))

;;;----------------------------------------------------------------------------
;;; Fiber Spawn, Yield, and Worker Count

(define (fiber-worker-count)
  (%sched-num-workers (%wctx-sched (%current-wctx))))

(define (fiber-yield)
  (perform %eff-yield))

(define (fiber-spawn thunk #!optional (n #f))
  (if n
      (begin
        (if (not (nursery? n))
            (error "fiber-spawn: expected nursery" n))
        (atomic-fxbox+/fetch! (%nursery-active n) 1 (memory-order acquire-release))
        (perform %eff-spawn
                 (lambda ()
                   (with-exception-catcher
                    (lambda (e)
                      (%nursery-record-error! n e)
                      (%nursery-child-done! n))
                    (lambda ()
                      (thunk)
                      (%nursery-child-done! n))))))
      (perform %eff-spawn thunk)))

;;;----------------------------------------------------------------------------
;;; Direct-Style Bounded & Unbuffered Fiber Channel (Zero Lost Wakeup)
;;;
;;; Uses FIFO waiter queues (head/tail pairs) protected by a tiny non-blocking
;;; spinlock + re-check inside %eff-park callback (matches Quint/Lean/CBMC).

(define-type %wait-q
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000004
  constructor: %make-wait-q
  predicate: %wait-q?
  (head %wq-head %wq-head-set!)
  (tail %wq-tail %wq-tail-set!))

(define (%wq-empty? q)
  (null? (%wq-head q)))

(define (%wq-push! q item)
  (let ((cell (cons item '())))
    (if (null? (%wq-head q))
        (begin
          (%wq-head-set! q cell)
          (%wq-tail-set! q cell))
        (begin
          (set-cdr! (%wq-tail q) cell)
          (%wq-tail-set! q cell)))))

(define (%wq-pop! q)
  (let* ((h (%wq-head q))
         (nxt (cdr h)))
    (%wq-head-set! q nxt)
    (if (null? nxt)
        (%wq-tail-set! q '()))
    (car h)))

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
   (%make-wait-q '() '())
   (%make-wait-q '() '())))

(define (fiber-send! ch val)
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (lock (%ch-lock ch))
         (cap (%ch-cap ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (%spin-lock! lock)
    (cond
      ;; Case 1: Direct rendezvous handoff to a parked receiver
      ((not (%wq-empty? rwq))
       (let ((rk (%wq-pop! rwq)))
         (%spin-unlock! lock)
         (%sched-wake! sched (cons rk val))
         #t))
      ;; Case 2: Ring buffer has free space
      ((fx< (%ch-count ch) cap)
       (let ((t (%ch-tail ch)))
         (vector-set! (%ch-buf ch) t val)
         (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
         (%ch-count-set! ch (fx+ (%ch-count ch) 1))
         (%spin-unlock! lock)
         #t))
      ;; Case 3: Full -> park via one-shot continuation with locked re-check
      (else
       (%spin-unlock! lock)
       (perform %eff-park
                (lambda (k)
                  (%spin-lock! lock)
                  (cond
                    ((not (%wq-empty? rwq))
                     (let ((rk (%wq-pop! rwq)))
                       (%spin-unlock! lock)
                       (%sched-wake! sched (cons rk val))
                       (%sched-wake! sched (cons k #t))))
                    ((fx< (%ch-count ch) cap)
                     (let ((t (%ch-tail ch)))
                       (vector-set! (%ch-buf ch) t val)
                       (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
                       (%ch-count-set! ch (fx+ (%ch-count ch) 1))
                       (%spin-unlock! lock)
                       (%sched-wake! sched (cons k #t))))
                    (else
                     (%wq-push! swq (cons k val))
                     (%spin-unlock! lock)))))))))

(define (fiber-recv! ch)
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (lock (%ch-lock ch))
         (cap (%ch-cap ch))
         (rwq (%ch-recv-waiters ch))
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
             ;; Immediately refill slot from oldest parked sender & wake it
             (let* ((sw (%wq-pop! swq))
                    (sk (car sw))
                    (sval (cdr sw))
                    (t (%ch-tail ch)))
               (vector-set! buf t sval)
               (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
               (%spin-unlock! lock)
               (%sched-wake! sched (cons sk #t))
               item)
             (begin
               (%ch-count-set! ch (fx- (%ch-count ch) 1))
               (%spin-unlock! lock)
               item))))
      ;; Case 2: Unbuffered rendezvous (cap == 0) with a parked sender
      ((not (%wq-empty? swq))
       (let* ((sw (%wq-pop! swq))
              (sk (car sw))
              (sval (cdr sw)))
         (%spin-unlock! lock)
         (%sched-wake! sched (cons sk #t))
         sval))
      ;; Case 3: Empty -> park via one-shot continuation with locked re-check
      (else
       (%spin-unlock! lock)
       (perform %eff-park
                (lambda (k)
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
                           (let* ((sw (%wq-pop! swq))
                                  (sk (car sw))
                                  (sval (cdr sw))
                                  (t (%ch-tail ch)))
                             (vector-set! buf t sval)
                             (%ch-tail-set! ch (let ((nt (fx+ t 1))) (if (fx= nt cap) 0 nt)))
                             (%spin-unlock! lock)
                             (%sched-wake! sched (cons sk #t))
                             (%sched-wake! sched (cons k item)))
                           (begin
                             (%ch-count-set! ch (fx- (%ch-count ch) 1))
                             (%spin-unlock! lock)
                             (%sched-wake! sched (cons k item))))))
                    ((not (%wq-empty? swq))
                     (let* ((sw (%wq-pop! swq))
                            (sk (car sw))
                            (sval (cdr sw)))
                       (%spin-unlock! lock)
                       (%sched-wake! sched (cons sk #t))
                       (%sched-wake! sched (cons k sval))))
                    (else
                     (%wq-push! rwq k)
                     (%spin-unlock! lock)))))))))

;;;----------------------------------------------------------------------------
;;; Multi-Core M:N Work-Stealing Scheduler Loop

(define (%run-fiber-thunk sched thunk)
  (with-handler
    ((tail: %eff-spawn (child-thunk)
       (atomic-fxbox+/fetch! (%sched-active-fibers sched) 1 (memory-order acquire-release))
       (%sched-enqueue-local! child-thunk)
       #!void)
     (%eff-yield (k)
       (%sched-enqueue-local! k)
       #!void)
     (%eff-park (k register-fn)
       (register-fn k)
       #!void)
     (return: (r)
       (atomic-fxbox-/fetch! (%sched-active-fibers sched) 1 (memory-order acquire-release))
       #!void))
    (thunk)))

(define (%worker-try-steal sched wid num-workers deques)
  (if (fx<= num-workers 1)
      (values #f #f)
      (let loop ((offset 1))
        (if (fx= offset num-workers)
            (values #f #f)
            (let* ((victim (let ((v (fx+ wid offset)))
                             (if (fx>= v num-workers) (fx- v num-workers) v)))
                   (vdq (vector-ref deques victim)))
              (call-with-values
                (lambda () (ws-deque-try-steal! vdq))
                (lambda (ok task)
                  (if ok
                      (values #t task)
                      (loop (fx+ offset 1))))))))))

(define (%worker-loop sched wid)
  (let* ((num-workers (%sched-num-workers sched))
         (deques (%sched-deques sched))
         (local-dq (vector-ref deques wid))
         (global-q (%sched-global-q sched))
         (active (%sched-active-fibers sched))
         (ctx (%make-worker-ctx sched wid local-dq)))
    (thread-specific-set! (current-thread) ctx)
    (let loop ((ticks 0) (idle-spins 0))
      (let ((got-task? #f)
            (task #f))
        ;; Periodically poll global-q every 32 local ticks for fairness
        (if (fx= (fxand ticks 31) 31)
            (call-with-values
              (lambda () (lf-queue-try-dequeue! global-q))
              (lambda (ok t)
                (if ok (begin (set! got-task? #t) (set! task t))))))
        ;; 1. Fast path: LIFO pop from own Chase-Lev deque
        (if (not got-task?)
            (call-with-values
              (lambda () (ws-deque-try-pop! local-dq))
              (lambda (ok t)
                (if ok (begin (set! got-task? #t) (set! task t))))))
        ;; 2. Global wakeup queue
        (if (not got-task?)
            (call-with-values
              (lambda () (lf-queue-try-dequeue! global-q))
              (lambda (ok t)
                (if ok (begin (set! got-task? #t) (set! task t))))))
        ;; 3. Work-steal from peer worker deques
        (if (not got-task?)
            (call-with-values
              (lambda () (%worker-try-steal sched wid num-workers deques))
              (lambda (ok t)
                (if ok (begin (set! got-task? #t) (set! task t))))))
        (if got-task?
            (begin
              (cond
                ((procedure? task)
                 (%run-fiber-thunk sched task))
                ((effect-continuation? task)
                 (resume task #f))
                (else
                 (resume (car task) (cdr task))))
              (loop (fx+ ticks 1) 0))
            (if (fx<= (atomic-fxbox-ref active (memory-order acquire)) 0)
                #!void
                (begin
                  (if (fx>= idle-spins 16)
                      (begin (thread-yield!) (loop ticks 0))
                      (loop ticks (fx+ idle-spins 1))))))))))

(define (run-fibers thunk #!key (workers (##current-vm-processor-count)))
  (let* ((w (max 1 (if (fixnum? workers) workers 1)))
         (deques (let ((v (make-vector w #f)))
                   (let loop ((i 0))
                     (if (fx< i w)
                         (begin (vector-set! v i (make-ws-deque 4096))
                                (loop (fx+ i 1)))))
                   v))
         (global-q (make-lf-queue))
         (active (make-atomic-fxbox 1))
         (root-done (make-atomic-fxbox 0))
         (root-box (cons #f #f))
         (sched (%make-scheduler w deques global-q active root-done root-box)))
    ;; Seed root fiber onto global queue
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
    ;; Launch W carrier worker threads (run worker 0 on a dedicated thread so
    ;; caller's own thread-specific is never touched)
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
