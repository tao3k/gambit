;;; Scheduler continuation ownership: immediate decisions versus committed waits.
;;; One native Scheme fixture; no alternative scheduler or test runner.
(declare (standard-bindings) (extended-bindings))

(define (require value . context)
  (if (not value) (apply error "mutex suspension contract" context)))

(define (running-cont-empty?)
  (##declare (not interrupts-enabled))
  (##c-code "___RESULT = ___BOOLEAN(___CONTINUATION_FRAME_FIELD(___THREAD_CONT_FIELD(___CURRENTTHREAD)) == ___END_OF_CONT_MARKER);"))

(define (slow-lock mutex timeout owner)
  (##declare (not interrupts-enabled))
  ;; Only the SMP implementation has this three-argument private protocol.
  ;; The single-context build checks the same decisions through its public
  ;; interface; it does not qualify the SMP slow-path ownership change.
  (if (##c-code "
#ifdef ___SINGLE_THREADED_VMS
___RESULT = ___TRU;
#else
___RESULT = ___FAL;
#endif
")
      (mutex-lock! mutex timeout owner)
      (begin
        (##check-heap-limit)
        (##primitive-lock! mutex 1 9)
        (if owner (##primitive-lock! owner 1 9))
        (##mutex-lock-out-of-line! mutex timeout owner))))

(define (await-mutex thread mutex)
  (let loop ()
    (let ((state (thread-state thread)))
      (if (and (thread-state-waiting? state)
               (eq? (thread-state-waiting-for state) mutex))
          #t
          (begin (thread-yield!) (loop))))))

(define (fresh thunk) (thread-join! (thread-start! (make-thread thunk))))

(define (probe)
  (fresh
   (lambda ()
     (let* ((m (make-mutex))
            (before (running-cont-empty?))
            (answer (slow-lock m #f (current-thread)))
            (after (running-cont-empty?)))
       (mutex-unlock! m)
       (write (list 'MUTEX-SUSPENSION-PROBE before answer after)) (newline)
       (require (and before answer) 'probe-formed)))))

(define (immediate opcode)
  (fresh
   (lambda ()
     (let ((m (make-mutex)))
       (if (= opcode 2) (mutex-lock! m))
       (let* ((before (running-cont-empty?))
              (answer (slow-lock m (if (= opcode 2) 0 #f)
                                 (if (= opcode 1) #f (current-thread))))
              (after (running-cont-empty?)))
         (mutex-unlock! m)
         (##gc)
         (list before answer after))))))

(define (blocking)
  (let* ((m (make-mutex)) (count (vector 0)) (answer #f))
    (mutex-lock! m)
    (let ((target (thread-start!
                   (make-thread
                    (lambda ()
                      (set! answer (slow-lock m #f (current-thread)))
                      (mutex-unlock! m)
                      'completed)))))
      (await-mutex target m)
      (do ((n 0 (+ n 1))) ((= n 12))
        (require (= (thread-interrupt!
                     target
                     (lambda ()
                       (vector-set! count 0 (+ 1 (vector-ref count 0)))
                       (##gc)
                       (vector-ref count 0)))
                    (+ n 1)) 'interrupt-result n)
        (await-mutex target m))
      (mutex-unlock! m)
      (require (eq? (thread-join! target) 'completed) 'blocked-completion)
      (require (and answer (= (vector-ref count 0) 12)) 'blocked-result))))

(define (cost count)
  (let* ((m (make-mutex)) (counter (vector 0)) (senders 10))
    (mutex-lock! m)
    (let ((target (thread-start! (make-thread (lambda () (mutex-lock! m) (mutex-unlock! m))))))
      (await-mutex target m)
      (let* ((before (##process-statistics)) (start (real-time))
             (threads
              (map (lambda (i)
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (do ((n i (+ n senders))) ((>= n count))
                           (thread-interrupt!
                            target
                            (lambda () (##vector-inc! counter 0))))))))
                   '(0 1 2 3 4 5 6 7 8 9))))
        (for-each thread-join! threads)
        (let ((wall (- (real-time) start)) (after (##process-statistics)))
          (mutex-unlock! m)
          (thread-join! target)
          (require (= (vector-ref counter 0) count) 'cost-count)
          (write (list 'MUTEX-SUSPENSION-COST count wall before after)) (newline))))))

(define (signature actions)
  (let loop ((xs actions))
    (if (null? xs)
        #f
        (let* ((opcode (car xs)) (observation (immediate opcode)))
          (cond ((not (car observation)) 'entry-not-empty)
                ((not (eq? (cadr observation) (not (= opcode 2)))) 'result-mismatch)
                ((not (caddr observation)) 'unnecessary-saved-continuation)
                (else (loop (cdr xs))))))))

(define (remove-at xs index)
  (if (= index 0) (cdr xs) (cons (car xs) (remove-at (cdr xs) (- index 1)))))

(define (shrink actions reason)
  (let again ((xs actions) (index 0))
    (if (= index (length xs))
        xs
        (let ((candidate (remove-at xs index)))
          (if (eq? reason (signature candidate))
              (again candidate 0)
              (again xs (+ index 1)))))))

(define (pbt)
  (let ((seed 173) (actions 0) (failure #f))
    (define (draw)
      (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
      (modulo (quotient seed 65536) 3))
    (do ((case 0 (+ case 1))) ((= case 24))
      (let* ((history (let loop ((n 12) (xs '()))
                        (if (= n 0) xs (loop (- n 1) (cons (draw) xs)))))
             (reason (signature history)))
        (set! actions (+ actions 12))
        (if (and reason (not failure))
            (set! failure (list reason history)))))
    (if failure
        (let* ((reason (car failure)) (original (cadr failure))
               (minimal (shrink original reason)))
          (call-with-output-file "mutex-suspension-minimal.scm"
            (lambda (port) (write minimal port) (newline port)))
          (require (eq? reason (signature minimal)) 'replay)
          (do ((i 0 (+ i 1))) ((= i (length minimal)))
            (require (not (eq? reason (signature (remove-at minimal i)))) 'minimal))
          (write (list 'MUTEX-SUSPENSION-SHRINK reason (length original)
                       (length minimal) 'deletion-one-minimal #t 'replayed #t minimal))
          (newline)
          #f)
        (begin
          (write (list 'MUTEX-SUSPENSION-PBT-PASS 'seed 173 'cases 24 'actions actions))
          (newline)
          #t))))

(define args (cdr (command-line)))
(cond ((equal? args '("--probe")) (probe))
      ((equal? args '("--pbt")) (if (not (pbt)) (exit 70)))
      ((and (pair? args) (string=? (car args) "--replay"))
       (let ((history (call-with-input-file (cadr args) read)))
         (write (list 'MUTEX-SUSPENSION-REPLAY (signature history))) (newline)))
      ((and (pair? args) (string=? (car args) "--cost")) (cost (string->number (cadr args))))
      (else
       (require (pbt) 'pbt)
       (blocking)
       (display "MUTEX-SUSPENSION-PASS\n")))
