;;; Safe specialization must validate every operand before the atomic write.
(##namespace ("gambit#tests#vector-increment#" rejects? v))

(define (rejects? thunk)
  (with-exception-catcher type-exception?
    (lambda () (thunk) #f)))

(define v (vector 12))
(if (not (rejects? (lambda () (vector-inc! v 0 #f))))
    (error "invalid delta reached the atomic operation"))
(if (not (= (vector-ref v 0) 12))
    (error "rejected delta changed the vector"))
(vector-set! v 0 'not-a-fixnum)
(if (not (rejects? (lambda () (vector-inc! v 0))))
    (error "invalid old element reached the atomic operation"))
(if (not (eq? (vector-ref v 0) 'not-a-fixnum))
    (error "rejected old element changed the vector"))
(vector-set! v 0 12)
(if (not (and (= (vector-inc! v 0) 12) (= (vector-ref v 0) 13)))
    (error "default delta or returned old value changed"))
(if (not (and (= (vector-inc! v 0 -3) 13) (= (vector-ref v 0) 10)))
    (error "explicit delta or returned old value changed"))
(display "VECTOR-INCREMENT-CONTRACT-PASS\n")
