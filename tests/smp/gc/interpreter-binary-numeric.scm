;;; Compare the original and exact-binary numeric implementations under eval.
(declare (standard-bindings) (block))

(define (check actual expected name)
  (if (not (equal? actual expected))
      (error "interpreted binary numeric mismatch" name actual expected)))

(define (check-failure expr predicate name)
  (check (with-exception-catcher
          predicate
          (lambda () (eval expr) #f))
         #t
         name))

(println "PROCESSORS:" (##current-vm-processor-count))

(check (eval '(list (> 41 40) (> 41 41) (> -3 2)
                    (- 42 1) (- 41 41) (- -3 -5)))
       '(#t #f #f 41 0 2)
       'binary-fixnums)
(check (eval '(list (> 1.5 1) (> 1 3/2) (- 3/2 1) (- 1.5 1)
                    (> 5 4 3) (> 5 2 3) (- 7 3 1) (- 7)))
       '(#t #f 1/2 0.5 #t #f 3 -7)
       'numeric-fallback)
(let ((max (##greatest-fixnum)) (min (##least-fixnum)))
  (check (eval `(list (- ,max -1) (- ,min 1)))
         (list (+ max 1) (- min 1))
         'fixnum-overflow))
(check (eval '((lambda (> -) (list (> 42 0) (- 42 1)))
               (lambda (a b) 'other-comparison)
               (lambda (a b) 'other-subtraction)))
       '(other-comparison other-subtraction)
       'rebound-operator)
(check-failure '(-) wrong-number-of-arguments-exception? 'wrong-arity)
(check-failure '(- 'invalid 1) type-exception? 'invalid-subtraction)
(check-failure '(> 1 'invalid) type-exception? 'invalid-comparison)

;;; Interruption is asynchronous. Only a captured return label for one of
;;; the binary numeric polls is a targeted observation. Any other successful
;;; interrupt still checks the enclosing interpreter's final numeric state.
(define (poll-owner cont)
  (let loop ((frame cont) (fuel 64))
    (and frame (> fuel 0)
         (let* ((ret (##continuation-ret frame))
                (parent (##subprocedure-parent ret))
                (id (##subprocedure-id ret)))
           (cond ((and (eq? parent >) (eqv? id 3)) 'greater)
                 ((and (eq? parent -) (eqv? id 5)) 'subtract)
                 (else (loop (##continuation-next frame) (- fuel 1))))))))

;; Publish the receiver before targeting its thread. The callback writes
;; only the target's lexical state and returns the identities it observed.
(define gate (make-mutex))
(define callback #f)

;; Use an interpreted closure to publish the target-owned interrupt action.
(define publish-target
  (eval
   '(lambda (gate publish)
      (let ((done #f) (cycles 0) (seen '()))
        (mutex-lock! gate)
        (publish (lambda (stop? capture)
                   (if stop?
                       (set! done #t)
                       (let ((owner (capture)))
                         (if (and owner (not (memq owner seen)))
                             (begin (##gc) (set! seen (cons owner seen))))))
                   seen))
        (mutex-unlock! gate)
        (let loop ((n 6000) (steps 0))
          (cond (done (list n cycles seen steps))
                ((> n 0) (loop (- n 1) (+ steps 1)))
                (else (set! cycles (+ cycles 1)) (loop 6000 (+ steps 1)))))))))

(define target
  (make-thread
   (lambda () (publish-target gate (lambda (value) (set! callback value))))))
(thread-start! target)
(define action
  (let wait ()
    (mutex-lock! gate)
    (let ((value callback))
      (mutex-unlock! gate)
      (or value (begin (thread-yield!) (wait))))))
(define seen
  (let sample ((left 64) (observed '()))
    (if (or (= left 0) (and (memq 'greater observed) (memq 'subtract observed)))
        observed
        (sample (- left 1)
                (thread-interrupt! target
                 (lambda ()
                   (action #f (lambda () (##continuation-capture poll-owner)))))))))
(thread-interrupt! target (lambda () (action #t #f)))
(let ((result (thread-join! target)))
  (check (and (fixnum? (car result)) (<= 0 (car result) 6000)) #t 'resumed-counter)
  (check (caddr result) seen 'captured-state)
  (check (cadddr result) (+ (* (cadr result) 6001) (- 6000 (car result)))
         'resumed-progress))
(println "BINARY-NUMERIC-POLL greater=" (if (memq 'greater seen) 1 0)
         " subtract=" (if (memq 'subtract seen) 1 0))
(display "INTERPRETED-BINARY-NUMERIC-PASS\n")
