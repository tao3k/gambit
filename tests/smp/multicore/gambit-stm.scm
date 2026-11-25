;;; Gambit-STM: QCheck-STM inspired thread-lifecycle & interrupt state-machine
;;; property-based test for Gambit SMP (p1/p2/p4) under active GC-Hammer.
;;;
;;; Exercises randomized interleavings of:
;;;   make-thread, thread-start!, thread-interrupt! (normal / raise / call/cc),
;;;   thread-join! (0-timeout / future-timeout / unbounded), thread-terminate!,
;;;   thread-state inspection, and concurrent (##gc).
;;; Verifies:
;;;   1. Legal monotonic thread state transitions (never regresses from terminal)
;;;   2. At-most-once execution of every interrupt action
;;;   3. Exact terminal result / exception class agreement between thread-state and thread-join!
;;;   4. Zero deadlocks / zero crashes across hundreds of randomized schedules.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (make-prng seed) (vector (bitwise-and seed #x3fffffff)))
(define (prng-int! rng bound)
  (let ((n (bitwise-and (+ (* (vector-ref rng 0) 1103515245) 12345) #x3fffffff)))
    (vector-set! rng 0 n)
    (modulo n bound)))

(define (classify-state st)
  (cond ((thread-state-uninitialized? st) 'uninitialized)
        ((thread-state-initialized? st) 'initialized)
        ((thread-state-running? st) 'running)
        ((thread-state-waiting? st) 'waiting)
        ((thread-state-normally-terminated? st) 'normally-terminated)
        ((thread-state-abnormally-terminated? st) 'abnormally-terminated)
        (else (mc-fail 'unknown-thread-state st))))

(define (terminal-kind? k)
  (or (eq? k 'normally-terminated) (eq? k 'abnormally-terminated)))

;; Legal state transition relation: once terminal, kind and payload must never change.
(define (legal-transition? prev next)
  (cond
   ((eq? prev 'none) #t)
   ((terminal-kind? prev) (eq? prev next))
   ((eq? prev 'initialized) (not (eq? next 'uninitialized)))
   (else (not (or (eq? next 'uninitialized) (eq? next 'initialized))))))

(define (run-stm-trial rng trial-id)
  (let* ((worker-mode (prng-int! rng 4))
         (gate (make-mutex 'stm-gate))
         (escape-k (vector #f))
         (intr-hits (vector 0))
         (intr-mtx (make-mutex 'stm-intr))
         (target-res (+ 1000 trial-id))
         (target
          (make-thread
           (lambda ()
             (case worker-mode
               ;; Mode 0: sleep with timeout (exercises ##toq-insert! F64 paths!)
               ((0) (thread-sleep! 0.015) target-res)
               ;; Mode 1: block on mutex with future timeout (exercises btq + toq!)
               ((1) (let ((to (seconds->time (+ 5 (time->seconds (current-time))))))
                      (if (mutex-lock! gate to)
                          (begin (mutex-unlock! gate) target-res)
                          'timed-out)))
               ;; Mode 2: busy allocate + yield (exercises running-on-other-processor interrupts!)
               ((2) (let loop ((i 0) (acc 0))
                      (if (< i 200)
                          (let ((v (vector i (+ i 1) (+ i 2))))
                            (if (= (modulo i 20) 0) (thread-yield!))
                            (loop (+ i 1) (+ acc (vector-ref v 1))))
                          target-res)))
               ;; Mode 3: supports call/cc escape inside interrupt
               (else
                (call-with-current-continuation
                 (lambda (k)
                   (vector-set! escape-k 0 k)
                   (thread-sleep! 0.02)
                   target-res)))))
           (string-append "stm-t-" (number->string trial-id)))))
    (if (= worker-mode 1) (mutex-lock! gate))
    (let ((last-state (vector (classify-state (thread-state target))))
          (started (vector #f))
          (expected-hits (vector 0)))
      (define (observe-state!)
        (let* ((st (thread-state target))
               (k (classify-state st)))
          (mc-assert (legal-transition? (vector-ref last-state 0) k)
                     'illegal-state-transition trial-id (vector-ref last-state 0) '-> k)
          (vector-set! last-state 0 k)
          st))
      (mc-assert (eq? (vector-ref last-state 0) 'initialized) 'stm-initial-state (vector-ref last-state 0))
      ;; Drive 8 randomized operations across main + helper thread
      (let loop ((step 0))
        (if (< step 8)
            (let ((op (prng-int! rng 6)))
              (case op
                ;; Start
                ((0)
                 (if (not (vector-ref started 0))
                     (begin
                       (thread-start! target)
                       (vector-set! started 0 #t))))
                ;; Synchronous interrupt with exact-once counter
                ((1)
                 (if (vector-ref started 0)
                     (let ((ran (vector 0)))
                       (with-exception-catcher
                        (lambda (e)
                          (mc-assert (or (inactive-thread-exception? e)
                                         (abandoned-mutex-exception? e))
                                     'unexpected-intr-exc trial-id e))
                        (lambda ()
                          (let ((r (thread-interrupt!
                                    target
                                    (lambda ()
                                      (vector-set! ran 0 (+ (vector-ref ran 0) 1))
                                      (mutex-lock! intr-mtx)
                                      (vector-set! intr-hits 0 (+ (vector-ref intr-hits 0) 1))
                                      (mutex-unlock! intr-mtx)
                                      (+ 42 step)))))
                            (mc-assert (= r (+ 42 step)) 'stm-intr-return-mismatch r (+ 42 step))
                            (mc-assert (= (vector-ref ran 0) 1) 'stm-intr-ran-not-once (vector-ref ran 0)))))
                       (mc-assert (<= (vector-ref ran 0) 1) 'stm-intr-duplicate-exec (vector-ref ran 0)))))
                ;; Interrupt that raises or escapes via call/cc
                ((2)
                 (if (vector-ref started 0)
                     (with-exception-catcher
                      (lambda (e)
                        (mc-assert (or (inactive-thread-exception? e)
                                       (abandoned-mutex-exception? e))
                                   'unexpected-intr-exc2 trial-id e))
                      (lambda ()
                        (thread-interrupt!
                         target
                         (lambda ()
                           (if (and (= worker-mode 3) (vector-ref escape-k 0))
                               ((vector-ref escape-k 0) 'escaped-ok)
                               (raise 'stm-injected-error))))))))
                ;; Non-blocking join (0 timeout)
                ((3)
                 (if (vector-ref started 0)
                     (with-exception-catcher
                      (lambda (e)
                        (mc-assert (or (uncaught-exception? e)
                                       (terminated-thread-exception? e))
                                   'unexpected-join0-exc trial-id e))
                      (lambda ()
                        (thread-join! target 0 'still-running)))))
                ;; Terminate or release gate
                ((4)
                 (if (= (prng-int! rng 2) 0)
                     (thread-terminate! target)
                     (if (and (= worker-mode 1) (eq? (mutex-state gate) (current-thread)))
                         (mutex-unlock! gate))))
                ;; State probe + GC
                (else
                 (observe-state!)
                 (if (= (modulo step 3) 0) (##gc))))
              (observe-state!)
              (loop (+ step 1)))))
      ;; Ensure target finishes cleanly and verify thread-join! agrees 100% with thread-state!
      (if (not (vector-ref started 0))
          (thread-start! target))
      (if (and (= worker-mode 1) (eq? (mutex-state gate) (current-thread)))
          (mutex-unlock! gate))
      (let* ((join-outcome
              (with-exception-catcher
               (lambda (e)
                 (cond ((terminated-thread-exception? e) (cons 'terminated #f))
                       ((uncaught-exception? e) (cons 'uncaught (uncaught-exception-reason e)))
                       (else (mc-fail 'unexpected-final-join-exc trial-id e))))
               (lambda ()
                 (cons 'normal (thread-join! target)))))
             (final-st (observe-state!))
             (final-kind (classify-state final-st)))
        (case (car join-outcome)
          ((normal)
           (mc-assert (eq? final-kind 'normally-terminated) 'state-join-normal-mismatch trial-id final-kind)
           (mc-assert (equal? (thread-state-normally-terminated-result final-st) (cdr join-outcome))
                      'state-join-val-mismatch trial-id))
          ((terminated)
           (mc-assert (eq? final-kind 'abnormally-terminated) 'state-join-term-mismatch trial-id final-kind)
           (mc-assert (terminated-thread-exception? (thread-state-abnormally-terminated-reason final-st))
                      'state-join-term-reason-mismatch trial-id))
          ((uncaught)
           (mc-assert (eq? final-kind 'abnormally-terminated) 'state-join-uncaught-mismatch trial-id final-kind)
           (mc-assert (equal? (thread-state-abnormally-terminated-reason final-st) (cdr join-outcome))
                      'state-join-uncaught-reason-mismatch trial-id)))))))

(let* ((rng (make-prng 987654321))
       (trials 120)
       (gc0 (mc-gc-count))
       (res
        (with-gc-hammer
         0.002
         (lambda ()
           ;; Run trials concurrently in batches of 4 across processors!
           (let loop ((b 0))
             (if (< b (/ trials 4))
                 (let ((ts (map (lambda (k)
                                  (let ((sub-rng (make-prng (+ 17 (* (+ (* b 4) k) 7919)))))
                                    (thread-start!
                                     (make-thread
                                      (lambda () (run-stm-trial sub-rng (+ (* b 4) k)))))))
                                '(0 1 2 3))))
                   (for-each thread-join! ts)
                   (loop (+ b 1))))))))
       (pulses (cdr res))
       (gc-delta (- (mc-gc-count) gc0)))
  (mc-assert (> gc-delta 0) 'stm-no-gc gc-delta)
  (display (list 'GAMBIT-STM-PASS
                 'procs (mc-processor-count)
                 'trials trials
                 'gc-pulses pulses
                 'gc-total gc-delta))
  (newline)
  (force-output))
