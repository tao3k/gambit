;;; The operator enables reference stepping before its argument is evaluated.
;;; A fused application must observe the current handler at the reference.
(declare (standard-bindings) (block))
(display "PROCESSORS:")
(display (##current-vm-processor-count))
(newline)

(define handlers (make-vector 7 #f))
(define stepper (vector handlers #f #f #f #f #f #f #f handlers))
(define changed 0)
(define (enable-reference-step!)
  (vector-set! stepper 6
    (lambda (leap code rte execute)
      (let ((result (execute code rte)))
        (if (eqv? result 11)
            (begin (set! changed (+ changed 1)) 42)
            result)))))

(define result
  (parameterize ((##current-stepper stepper))
    (eval '(let ((x 11))
             ((begin (enable-reference-step!) (lambda (v) v)) x)))))
(if (not (and (= result 42) (> changed 0)))
    (error "dynamic reference stepper mismatch" result changed))
(display "INTERPRETER-DYNAMIC-STEPPER-PASS\n")
