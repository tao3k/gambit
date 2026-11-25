;;; The forms under test are evaluated by the interpreter, including nested
;;; escaped closures and multiple invocations of one captured continuation.
(declare (standard-bindings) (block))
(display "PROCESSORS:")
(display (##current-vm-processor-count))
(newline)

(define (check value expected label)
  (if (not (equal? value expected))
      (error "interpreter RTE identity mismatch" label value expected)))

(check
 (eval
  '(let ((read-location #f) (write-location #f))
     (let ((x 10))
       (set! read-location (lambda () x))
       (set! write-location (lambda (v) (set! x v))))
     (##gc)
     (write-location 41)
     (##gc)
     (read-location)))
 41 'escaped-mutable-location)

(check
 (eval
  '(let ((saved #f) (round 0) (seen '()))
     (let ((x 10))
       (call-with-current-continuation (lambda (k) (set! saved k) #f))
       (set! seen (cons x seen))
       (set! x (+ x 1))
       (cond ((= round 0) (set! round 1) (##gc) (saved #f))
             ((= round 1) (set! round 2) (##gc) (saved #f))
             (else (reverse seen))))))
 '(10 11 12) 'multishot-mutable-location)

(check
 (eval '(with-exception-catcher (lambda (x) (if (eq? x #f) 'false-value 'wrong))
          (lambda () (raise #f))))
 'false-value 'false-exception)

(display "INTERPRETED-RTE-IDENTITY-PASS\n")
