;;; Paired workload: identical file for old and new embedded GSI.
;;; Composed mode uses the already-present processor-placement helper.
;;; No imports or runtime headers; -f suppresses user initialization.
(define count 4096)
(define composed?
  (member "--composed" (cdr (command-line))))
(define caller (current-thread))
(define caller-processor (processor-id (current-processor)))
(define target-start-processor #f)
(define callbacks 0)
(define resumed 0)
(define crossed 0)
(define latencies (make-f64vector count 0.0))
(define (request-value i)
  (if composed?
      (let ((resume #f))
        (if (not (eq? (current-thread) target)) (error "request logical target" i))
        (set! callbacks (+ callbacks 1))
        (if (not (= caller-processor (processor-id (current-processor))))
            (set! crossed (+ crossed 1)))
        (let ((turn (call-with-current-continuation
                     (lambda (k) (set! resume k) 0))))
          (if (< turn 2)
              (begin (set! resumed (+ resumed 1)) (resume (+ turn 1)))
              (let ((payload (vector i (cons i i))))
                (thread-send caller payload)
                payload))))
      i))
(define gate (make-mutex))
(define changed (make-condition-variable))
(define ready #f)
(define finished #f)
(define target
  (thread-start!
   (make-thread
    (lambda ()
      (set! target-start-processor (processor-id (current-processor)))
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
                (let* ((start (time->seconds (current-time)))
                       (n (thread-interrupt! target (lambda () (request-value i)))))
                  (f64vector-set! latencies i (- (time->seconds (current-time)) start))
                  (if composed?
                      (begin
                        (if (= (modulo i 256) 0) (##gc))
                        (let ((message (thread-receive)))
                          (if (not (and (eq? message n) (= (vector-ref n 0) i)
                                        (= (car (vector-ref n 1)) i)))
                              (error "composed request/mailbox result" i n))))
                      (if (not (= i n)) (error "request cost result" i n)))
                  (loop (+ i 1)))))))))
(newline)
(mutex-lock! gate)
(set! finished #t)
(condition-variable-signal! changed)
(mutex-unlock! gate)
(if (eq? (thread-join! target 5 'timeout) 'timeout) (error "cost target not drained"))

(if composed?
    (begin
      ;; Logical target identity is the contract. Scheduler migration may move
      ;; a parked target to the caller's processor; physical affinity is not.
      (if (not (and (= callbacks count) (= resumed (* 2 count))
                    (<= 0 crossed count)))
          (error "composed delivery/placement counts" callbacks resumed crossed))
      (write (list 'REQUEST-SERVICE-TOPOLOGY caller-processor target-start-processor crossed callbacks resumed))
      (newline)
      (write (list 'REQUEST-SERVICE-LATENCIES latencies))
      (newline)
      (display "REQUEST-SERVICE-COMPOSED-PASS count=4096 resumes=8192 explicit-gc=16 mailbox-identity drained\n")))
