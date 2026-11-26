;;; C8: Concurrent SMP OS I/O (close-port / half-close / thread-terminate! vs ___device_select)
;;;     + Concurrent POSIX child-process reaping (open-process / process-status)
;;;     under active GC-Hammer across p1/p2/p4/p6/p8.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (run-c8)
  (let* ((io-workers 4)
         (io-rounds 50)
         (proc-workers 4)
         (proc-rounds 35)
         (io-done (vector 0))
         (proc-done (vector 0))
         (mtx (make-mutex 'c8-cnt)))

    ;; TCP close-vs-select + half-close + thread-terminate! adversarial worker
    (define (make-io-worker wid)
      (thread-start!
       (make-thread
        (lambda ()
          (let loop ((n 0))
            (if (< n io-rounds)
                (let* ((srv (open-tcp-server 0))
                       (port (socket-info-port-number (tcp-server-socket-info srv)))
                       (cli (open-tcp-client (list server-address: "127.0.0.1" port-number: port)))
                       (acc (read srv))
                       (mode (modulo (+ n wid) 3))
                       (reader
                        (make-thread
                         (lambda ()
                           (with-exception-catcher
                            (lambda (e) 'closed-or-err)
                            (lambda () (read-u8 acc))))
                         'c8-reader))
                       (closer
                        (make-thread
                         (lambda ()
                           (thread-yield!)
                           (cond
                            ((= mode 0)
                             ;; Full close while peer is inside ___device_select
                             (with-exception-catcher (lambda (e) #f) (lambda () (close-port acc))))
                            ((= mode 1)
                             ;; Staged half-close (input then output)
                             (with-exception-catcher (lambda (e) #f) (lambda () (close-input-port acc)))
                             (thread-yield!)
                             (with-exception-catcher (lambda (e) #f) (lambda () (close-output-port acc))))
                            (else
                             ;; Concurrent close + terminate blocked reader
                             (with-exception-catcher (lambda (e) #f) (lambda () (close-port acc)))
                             (with-exception-catcher (lambda (e) #f) (lambda () (thread-terminate! reader))))))
                         'c8-closer)))
                  (thread-start! reader)
                  (thread-start! closer)
                  (with-exception-catcher (lambda (e) 'terminated) (lambda () (thread-join! reader)))
                  (thread-join! closer)
                  (with-exception-catcher (lambda (e) #f) (lambda () (close-port acc)))
                  (with-exception-catcher (lambda (e) #f) (lambda () (close-port cli)))
                  (with-exception-catcher (lambda (e) #f) (lambda () (close-port srv)))
                  (loop (+ n 1)))))
          (mutex-lock! mtx)
          (vector-set! io-done 0 (+ (vector-ref io-done 0) io-rounds))
          (mutex-unlock! mtx))
        (string-append "c8-io-" (number->string wid)))))

    ;; Concurrent open-process / process-status reaping worker
    (define (make-proc-worker wid)
      (thread-start!
       (make-thread
        (lambda ()
          (let loop ((n 0))
            (if (< n proc-rounds)
                (let* ((tag (string-append "w" (number->string wid) "-" (number->string n)))
                       (p (open-process
                           (list path: "/bin/echo"
                                 arguments: (list tag)
                                 stdin-redirection: #f
                                 stdout-redirection: #t
                                 stderr-redirection: #f)))
                       (line (read-line p))
                       (st (process-status p)))
                  (close-port p)
                  (mc-assert (equal? line tag) 'c8-proc-output wid n line tag)
                  (mc-assert (= st 0) 'c8-proc-status wid n st)
                  (loop (+ n 1)))))
          (mutex-lock! mtx)
          (vector-set! proc-done 0 (+ (vector-ref proc-done 0) proc-rounds))
          (mutex-unlock! mtx))
        (string-append "c8-proc-" (number->string wid)))))

    (let* ((gc0 (mc-gc-count))
           (res
            (with-gc-hammer
             0.005
             (lambda ()
               (let ((ws (append
                          (let loop ((i 0) (acc '()))
                            (if (= i io-workers) acc (loop (+ i 1) (cons (make-io-worker i) acc))))
                          (let loop ((i 0) (acc '()))
                            (if (= i proc-workers) acc (loop (+ i 1) (cons (make-proc-worker i) acc)))))))
                 (for-each thread-join! ws)))))
           (pulses (cdr res))
           (gc-delta (- (mc-gc-count) gc0)))
      (mc-assert (= (vector-ref io-done 0) (* io-workers io-rounds)) 'c8-io-count)
      (mc-assert (= (vector-ref proc-done 0) (* proc-workers proc-rounds)) 'c8-proc-count)
      (mc-assert (> gc-delta 0) 'c8-no-gc)
      (display (list 'C8-IO-CLOSE-SELECT-PROCESS-REAP-PASS
                     'procs (mc-processor-count)
                     'io-rounds (vector-ref io-done 0)
                     'proc-spawns (vector-ref proc-done 0)
                     'gc-pulses pulses
                     'gc-total gc-delta))
      (newline)
      (force-output))))

(run-c8)
