;;; Directly exercise the interpreter code-node interface with a mutable
;;; internal procedure binding. The caller supplies a private node graph.
(declare (not standard-bindings))
(display "PROCESSORS:")
(display (##current-vm-processor-count))
(newline)

(define handlers (make-vector 9 #f))
(define (second a b) b)
(define (operator-code code rte) second)
(define (first-code code rte) 0)
(define (replacement-code code rte) 123)
(define operator-node (vector #f operator-code #f #f handlers))
(define first-node (vector #f first-code #f #f handlers))
(define second-node (vector #f replacement-code #f #f handlers 41))
(define application (vector #f ##cprc-app2-sub #f #f handlers
                            operator-node first-node second-node))
(define saved ##cprc-cst)
(define (run-probe)
  (dynamic-wind
    (lambda () (set! ##cprc-cst replacement-code))
    (lambda () (##cprc-app2-sub application #f))
    (lambda () (set! ##cprc-cst saved))))
(display "NODE-IDENTITY-RESULT:")
(write (run-probe))
(newline)
(display "NODE-IDENTITY-DONE\n")
