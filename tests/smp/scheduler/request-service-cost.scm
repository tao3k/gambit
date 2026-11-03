;;; Public-only paired workload: identical file for old and new embedded GSI.
;;; No imports or runtime headers; -f suppresses user initialization.
(define count 4096)
(define gate (make-mutex))
(define changed (make-condition-variable))
(define ready #f)
(define finished #f)
(define target
  (thread-start!
   (make-thread
    (lambda ()
      (mutex-lock! gate)
      (set! ready #t)
      (condition-variable-signal! changed)
      (let wait ()
        (if (not finished)
            (begin (mutex-unlock! gate changed 5) (mutex-lock! gate) (wait))))
      (mutex-unlock! gate)))))
(mutex-lock! gate)
(let wait ()
  (if (not ready)
      (begin (mutex-unlock! gate changed 5) (mutex-lock! gate) (wait))))
(mutex-unlock! gate)
(write
 (cons 'REQUEST-SERVICE-COST
       (##exec-stats
        (lambda ()
          (let loop ((i 0))
            (if (= i count)
                i
                (let ((n (thread-interrupt! target (lambda () i))))
                  (if (not (= i n)) (error "request cost result" i n))
                  (loop (+ i 1)))))))))
(newline)
(mutex-lock! gate)
(set! finished #t)
(condition-variable-signal! changed)
(mutex-unlock! gate)
(if (eq? (thread-join! target 5 'timeout) 'timeout) (error "cost target not drained"))
