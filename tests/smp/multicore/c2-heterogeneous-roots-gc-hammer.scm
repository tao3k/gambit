;;; C2 (Chez mats/gc.ms + v10 thread_state.scm raw-f64 regression family):
;;; Orthogonal heterogeneous root torture under p2/p4 GC-Hammer:
;;;   - Worker 0: dense unboxed F64 arithmetic + timeout queue inserts/removals
;;;               (mutex-lock! / thread-sleep! timeouts -> ##toq-insert! raw-f64 spills)
;;;   - Worker 1: heavy bignum allocation (expt 11 10001) + integer-sqrt
;;;   - Worker 2: ##still-copy + u8vector / f64vector / closure / pair churn
;;;   - Worker 3: continuous thread-state / thread-interrupt! inspection + GC

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (run-c2)
  (let* ((stop (vector #f))
         (big-num (expt 11 6001))
         (locked-m1 (make-mutex 'c2-m1))
         (locked-m2 (make-mutex 'c2-m2))
         (f64-sum (vector 0.0))
         (still-ok (vector 0))
         (inspections (vector 0)))
    (mutex-lock! locked-m1)
    (mutex-lock! locked-m2)

    (let* ((w-f64
            ;; Worker 0: timeout queue + heavy unboxed flonum arithmetic
            (thread-start!
             (make-thread
              (lambda ()
                (let loop ((i 0) (acc 0.0))
                  (if (< i 250)
                      (let* ((now (time->seconds (current-time)))
                             (t1 (+ now 0.001 (* (exact->inexact (modulo i 5)) 0.0002)))
                             (t2 (+ now 1000.0 (* (exact->inexact i) 0.125)))
                             (to1 (seconds->time t1))
                             (to2 (seconds->time t2))
                             ;; Spawn short-lived waiter inserting future timeout into TOQ
                             (waiter
                              (thread-start!
                               (make-thread
                                (lambda ()
                                  (mutex-lock! locked-m1 to2))
                                'c2-toq-waiter))))
                        ;; Also timeout on locked-m2 with short absolute timeout
                        (let ((got (mutex-lock! locked-m2 to1)))
                          (mc-assert (not got) 'c2-locked-m2-unexpectedly-acquired))
                        (thread-terminate! waiter)
                        (with-exception-catcher
                         (lambda (e) (mc-assert (terminated-thread-exception? e) 'c2-waiter-exc e))
                         (lambda () (thread-join! waiter)))
                        (let ((x (+ acc (* (- t2 t1) 0.001))))
                          (loop (+ i 1) x)))
                      (vector-set! f64-sum 0 acc))))
              'c2-f64-toq)))
           (w-big
            ;; Worker 1: bignum stress forcing rapid msection transitions & GC
            (thread-start!
             (make-thread
              (lambda ()
                (let loop ((i 0))
                  (if (not (vector-ref stop 0))
                      (let ((r (integer-sqrt big-num)))
                        (mc-assert (> r 0) 'c2-bignum-corrupt)
                        (if (< i 40) (loop (+ i 1)))))))
              'c2-bignum)))
           (w-still
            ;; Worker 2: still objects + typed vectors + closures
            (thread-start!
             (make-thread
              (lambda ()
                (let loop ((i 0) (ring '()))
                  (if (not (vector-ref stop 0))
                      (let* ((s (##still-copy (u8vector (modulo i 251) 2 3 4 5 6 7 8)))
                             (fv (f64vector (exact->inexact i) (+ 1.5 (exact->inexact i)) 3.14159))
                             (fn (lambda (k) (+ (u8vector-ref s 0) (inexact->exact (floor (f64vector-ref fv 0))) k))))
                        (mc-assert (= (fn 10) (+ (modulo i 251) i 10)) 'c2-still-closure-corrupt i)
                        (vector-set! still-ok 0 (+ (vector-ref still-ok 0) 1))
                        (let ((next-ring (if (< (length ring) 16) (cons (cons s fv) ring) (list (cons s fv)))))
                          (if (= (modulo i 25) 0) (thread-yield!))
                          (loop (+ i 1) next-ring))))))
              'c2-still)))
           (w-inspect
            ;; Worker 3: inspects thread-state of all peers + interrupts w-still concurrently
            (thread-start!
             (make-thread
              (lambda ()
                (let loop ()
                  (if (not (vector-ref stop 0))
                      (begin
                        (for-each (lambda (t) (thread-state t)) (list w-f64 w-big w-still))
                        (with-exception-catcher
                         (lambda (e) #f)
                         (lambda () (thread-interrupt! w-still (lambda () 'ok))))
                        (vector-set! inspections 0 (+ (vector-ref inspections 0) 1))
                        (thread-sleep! 0.001)
                        (loop)))))
              'c2-inspector)))
           (gc0 (mc-gc-count))
           (res
            (with-gc-hammer
             0.001
             (lambda ()
               (thread-join! w-f64)
               (vector-set! stop 0 #t)
               (thread-join! w-big)
               (thread-join! w-still)
               (thread-join! w-inspect))))
           (pulses (cdr res))
           (gc-delta (- (mc-gc-count) gc0)))
      (mc-assert (> (vector-ref f64-sum 0) 0.0) 'c2-f64-sum-zero)
      (mc-assert (> (vector-ref still-ok 0) 0) 'c2-still-zero)
      (mc-assert (> gc-delta 0) 'c2-no-gc)
      (display (list 'C2-HETEROGENEOUS-ROOTS-PASS
                     'procs (mc-processor-count)
                     'still-checks (vector-ref still-ok 0)
                     'inspections (vector-ref inspections 0)
                     'gc-pulses pulses
                     'gc-total gc-delta))
      (newline)
      (force-output))))

(run-c2)
