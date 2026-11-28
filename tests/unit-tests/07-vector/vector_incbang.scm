(include "#.scm")

(define vect1 (vector 11 22 33))
(define vect2 (vector 11 22 33))

(test-equal 11 (##vector-inc! vect1 0 1))
(test-equal 12 (##vector-ref vect1 0))

(test-equal 22 (##vector-inc! vect1 1 10))
(test-equal 32 (##vector-ref vect1 1))

(test-equal 33 (##vector-inc! vect1 2 -5))
(test-equal 28 (##vector-ref vect1 2))

(test-equal 11 (vector-inc! vect2 0))
(test-equal 12 (vector-ref vect2 0))

(test-equal 22 (vector-inc! vect2 1 10))
(test-equal 32 (vector-ref vect2 1))

(test-equal 33 (vector-inc! vect2 2 -5))
(test-equal 28 (vector-ref vect2 2))

(test-error-tail type-exception? (vector-inc! #f 0))
(test-error-tail type-exception? (vector-inc! vect1 #f))
(test-error-tail type-exception? (vector-inc! vect1 0 #f))

(test-error-tail wrong-number-of-arguments-exception? (vector-inc!))
(test-error-tail wrong-number-of-arguments-exception? (vector-inc! vect1))
(test-error-tail wrong-number-of-arguments-exception? (vector-inc! vect1 0 0 0))

;; The callable primitive must accept the compiler's two-argument form too.
;; Apply also exercises first-class calls, without primitive-call expansion.
(define (call-primitive-inc . args)
  (declare (not inline) (not inline-primitives ##vector-inc!))
  (apply ##vector-inc! args))

(define vect3 (vector 11))
(test-equal 11 (##vector-inc! vect3 0))
(test-equal 12 (##vector-ref vect3 0))
(test-equal 12 (call-primitive-inc vect3 0))
(test-equal 13 (##vector-ref vect3 0))
(test-equal 13 (call-primitive-inc vect3 0 7))
(test-equal 20 (##vector-ref vect3 0))
(test-error-tail wrong-number-of-arguments-exception?
                 (call-primitive-inc vect3))
(test-error-tail wrong-number-of-arguments-exception?
                 (call-primitive-inc vect3 0 1 2))
