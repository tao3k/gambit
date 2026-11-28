;;; Baseline for asynchronous interruption of interpreted code. The handler
;;; accesses a lexical location created inside the target and triggers GC.
(declare (standard-bindings) (block))
(display "PROCESSORS:")
(display (##current-vm-processor-count))
(newline)

(define result
  (eval
   '(let ((gate (make-mutex)) (callback #f) (seen #f))
      (let ((target
             (make-thread
              (lambda ()
                (let ((x 41) (done #f))
                  (mutex-lock! gate)
                  (set! callback
                        (lambda ()
                          (let ((before x))
                            (##gc)
                            (set! x (+ x 1))
                            (set! seen (list before x))
                            (set! done #t))))
                  (mutex-unlock! gate)
                  (let loop ()
                    (if (not done)
                        (begin (thread-yield!) (loop))
                        x)))))))
        (thread-start! target)
        (let wait ()
          (mutex-lock! gate)
          (let ((handler callback))
            (mutex-unlock! gate)
            (if handler
                (thread-interrupt! target handler)
                (begin (thread-yield!) (wait)))))
        (list (thread-join! target) seen)))))

(if (not (equal? result '(42 (41 42))))
    (error "interpreter interrupt RTE mismatch" result))
(display "INTERPRETED-RTE-INTERRUPT-PASS\n")
