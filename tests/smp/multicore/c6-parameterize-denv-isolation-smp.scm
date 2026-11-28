;;; C6 (Chez thread-parameter + Gambit denv / exception isolation under SMP):
;;; Verifies strict per-thread dynamic-environment (parameterize) isolation
;;; across p2/p4 processors with nested parameterize, call/cc capture/restore,
;;; async thread-interrupt! raising exceptions, and continuous GC-Hammer.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define p-worker (make-parameter 'root-worker))
(define p-depth  (make-parameter 0))
(define p-token  (make-parameter #f))

(define (run-c6)
  (let* ((n-workers 6)
         (iters 200)
         (done-mtx (make-mutex 'c6-done))
         (total-checks (vector 0))
         (intr-caught (vector 0)))
    (define (worker-loop wid)
      (parameterize ((p-worker wid)
                     (p-depth 1)
                     (p-token (vector 'tok wid 0)))
        (let loop ((i 0))
          (if (< i iters)
              (let ((expected-tok (vector 'tok wid (+ i 1))))
                (mc-assert (eqv? (p-worker) wid) 'c6-outer-worker-leak wid (p-worker))
                (mc-assert (= (p-depth) 1) 'c6-outer-depth-leak wid (p-depth))
                (with-exception-catcher
                 (lambda (e)
                   (mc-assert (eq? e 'c6-async-ping) 'c6-unexpected-exc wid e)
                   (mutex-lock! done-mtx)
                   (vector-set! intr-caught 0 (+ (vector-ref intr-caught 0) 1))
                   (mutex-unlock! done-mtx))
                 (lambda ()
                   (parameterize ((p-depth 2)
                                  (p-token expected-tok))
                     (let ((res
                            (call-with-current-continuation
                             (lambda (k)
                               (parameterize ((p-depth 3))
                                 (mc-assert (eqv? (p-worker) wid) 'c6-inner-worker-leak wid)
                                 (mc-assert (= (p-depth) 3) 'c6-inner-depth-leak wid)
                                 (mc-assert (eq? (p-token) expected-tok) 'c6-inner-tok-leak wid)
                                 (if (= (modulo i 20) 0) (thread-yield!))
                                 (k (vector 'ok wid (p-depth))))))))
                       (mc-assert (equal? res (vector 'ok wid 3)) 'c6-cc-return-bad res)
                       (mc-assert (= (p-depth) 2) 'c6-post-cc-depth-bad (p-depth))
                       (mc-assert (eq? (p-token) expected-tok) 'c6-post-cc-tok-bad)))))
                ;; After unwind/exit, outer parameter bindings MUST be intact!
                (mc-assert (eqv? (p-worker) wid) 'c6-post-worker-corrupt wid (p-worker))
                (mc-assert (= (p-depth) 1) 'c6-post-depth-corrupt wid (p-depth))
                (loop (+ i 1))))))
      (mutex-lock! done-mtx)
      (vector-set! total-checks 0 (+ (vector-ref total-checks 0) iters))
      (mutex-unlock! done-mtx))

    (let* ((gc0 (mc-gc-count))
           (res
            (with-gc-hammer
             0.002
             (lambda ()
               (let ((ws (map (lambda (wid)
                                (thread-start!
                                 (make-thread (lambda () (worker-loop wid))
                                              (string-append "c6-w-" (number->string wid)))))
                              '(0 1 2 3 4 5))))
                 ;; Pepper running workers with async interrupts that raise inside parameterize!
                 (let poke ((k 0))
                   (if (< k 40)
                       (begin
                         (for-each
                          (lambda (t)
                            (with-exception-catcher
                             (lambda (e) #f)
                             (lambda ()
                               (thread-interrupt!
                                t
                                (lambda ()
                                  ;; Interrupt executes inside target thread's denv!
                                  ;; Only raise when inside the guarded inner parameterize (depth >= 2).
                                  (if (>= (p-depth) 2)
                                      (raise 'c6-async-ping)))))))
                          ws)
                         (thread-sleep! 0.001)
                         (poke (+ k 1)))))
                 (for-each thread-join! ws)))))
           (pulses (cdr res))
           (gc-delta (- (mc-gc-count) gc0)))
      ;; Root thread parameters must never have been mutated!
      (mc-assert (eq? (p-worker) 'root-worker) 'c6-root-mutated (p-worker))
      (mc-assert (= (p-depth) 0) 'c6-root-depth-mutated (p-depth))
      (mc-assert (eq? (p-token) #f) 'c6-root-tok-mutated (p-token))
      (mc-assert (= (vector-ref total-checks 0) (* n-workers iters)) 'c6-incomplete)
      (mc-assert (> gc-delta 0) 'c6-no-gc)
      (display (list 'C6-PARAMETERIZE-DENV-ISOLATION-PASS
                     'procs (mc-processor-count)
                     'checks (vector-ref total-checks 0)
                     'async-unwinds (vector-ref intr-caught 0)
                     'gc-pulses pulses
                     'gc-total gc-delta))
      (newline)
      (force-output))))

(run-c6)
