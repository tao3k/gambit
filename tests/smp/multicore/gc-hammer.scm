;;; Reusable GC-Hammer perturbation harness for true multicore Gambit SMP tests.
;;; Inspired by OCaml 5 Gc.Memprof / aggressive-GC forcing to expose narrow
;;; STW safepoint, frame-root, and weak-reference race windows.

(declare (standard-bindings) (extended-bindings))

(define (mc-processor-count)
  (##current-vm-processor-count))

(define (mc-stats-snapshot)
  (let ((s (##process-statistics)))
    (list (cons 'user (f64vector-ref s 0))
          (cons 'sys (f64vector-ref s 1))
          (cons 'real (f64vector-ref s 2))
          (cons 'gc-user (f64vector-ref s 3))
          (cons 'gc-count (inexact->exact (round (f64vector-ref s 6))))
          (cons 'bytes (inexact->exact (round (f64vector-ref s 7)))))))

(define (mc-gc-count)
  (inexact->exact (round (f64vector-ref (##process-statistics) 6))))

(define (mc-fail tag . details)
  (display "MC-FAIL ")
  (display tag)
  (for-each (lambda (x) (display " ") (write x)) details)
  (newline)
  (force-output)
  (exit 1))

(define (mc-assert cond tag . details)
  (if (not cond)
      (apply mc-fail tag details)))

;; Spawn a dedicated background GC-Hammer thread pulsing (##gc) every interval-sec
;; while thunk runs, returning (values thunk-result gc-pulses).
(define (with-gc-hammer interval-sec thunk)
  (let* ((stop-box (vector #f))
         (pulses (vector 0))
         (hammer
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ()
                (if (not (vector-ref stop-box 0))
                    (begin
                      (##gc)
                      (vector-set! pulses 0 (+ (vector-ref pulses 0) 1))
                      (if (> interval-sec 0)
                          (thread-sleep! interval-sec)
                          (thread-yield!))
                      (loop)))))
            'gc-hammer))))
    (let ((result
           (with-exception-catcher
            (lambda (exc)
              (vector-set! stop-box 0 #t)
              (thread-join! hammer)
              (raise exc))
            thunk)))
      (vector-set! stop-box 0 #t)
      (thread-join! hammer)
      (cons result (vector-ref pulses 0)))))
