;;; Exercise the actual interpreter call-step callback, including changed
;;; arguments and multiple invocations.  The handler selects only public -.
(declare (standard-bindings) (block))
(display "PROCESSORS:")
(display (##current-vm-processor-count))
(newline)

(define seen '())
(define target -)
(define handlers (make-vector 7 #f))
(define stepper (vector handlers #f #f #f #f #f #f #f handlers))
(vector-set!
 stepper 1
 (lambda (leap code rte execute proc . args)
   (if (and (eq? proc target) (= (length args) 2))
       (let ((a (execute code rte proc 9 4))
             (b (execute code rte proc 20 3)))
         (set! seen (list a b))
         b)
       (apply execute code rte proc args))))

(define answer
  (parameterize ((##current-stepper stepper))
    (eval '(- 10 3))))
(if (not (and (= answer 17) (equal? seen '(5 17))))
    (error "step callback mismatch" answer seen))
(display "INTERPRETER-STEP-CALLBACK-PASS\n")
