;; C16: Adversarial Full-Core / Oversubscribed Spinlock Convoy & Still-Budget PBT
;;
;; Challenges FIFO ticket-lock convoy livelock and pre-GC still-object budget
;; thrashing under full-core & oversubscribed concurrency (max(12, 2*P) threads)
;; with simultaneous still-object allocation (make-f64vector 256), contended
;; ##vector-cas!, and processor-heartbeat preemption.
(declare (standard-bindings) (extended-bindings) (block))

(define (c16-worker id iters cas-box)
  (let loop ((i 0) (acc 0.0))
    (if (= i iters)
        acc
        (let* ((v (make-f64vector 256 (exact->inexact (+ id (modulo i 17)))))
               (p (list (vector i id v) (cons i (number->string i))))
               (s (+ (f64vector-ref v 0) (f64vector-ref v 255))))
          ;; Interleave contended CAS every 32 iterations to amplify lock/cache traffic
          (if (= (modulo i 32) 0)
              (let retry ((old (##vector-cas! cas-box 0 0 0)))
                (let ((prev (##vector-cas! cas-box 0 (+ old 1) old)))
                  (if (not (eq? prev old))
                      (retry prev)))))
          (loop (+ i 1) (+ acc s (if (pair? p) 1.0 0.0)))))))

(define (run-c16)
  (let* ((n-procs (##current-vm-processor-count))
         (n-workers (max 12 (* 2 n-procs)))
         (iters 6000)
         (cas-box (vector 0))
         (s0 (##process-statistics))
         (t0 (f64vector-ref s0 2))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i n-workers)
                acc
                (loop (+ i 1)
                      (cons (thread-start!
                             (make-thread (lambda () (c16-worker i iters cas-box))))
                            acc)))))
         (vals (map thread-join! threads))
         (s1 (##process-statistics))
         (work-real (- (f64vector-ref s1 2) t0))
         (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
         (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5)))
         (non-gc (- work-real gc-real))
         (expected-cas (* n-workers (quotient (+ iters 31) 32))))
    (for-each (lambda (v)
                (if (not (and (flonum? v) (> v 0.0)))
                    (error "c16 worker mismatch" v)))
              vals)
    (if (not (= (vector-ref cas-box 0) expected-cas))
        (error "c16 cas mismatch" (vector-ref cas-box 0) expected-cas))
    ;; Anti-convoy wall-time guard: non-GC time must not explode into a multi-second
    ;; spinlock convoy (legacy p12 hit 5.8s-15.1s non-GC).
    (if (> non-gc 4.0)
        (error "c16 spinlock convoy detected: non_gc_real=" non-gc " work_real=" work-real))
    (println "C16-FULL-CORE-SPINLOCK-CONVOY-PASS procs=" n-procs
             " workers=" n-workers
             " cas=" (vector-ref cas-box 0)
             " work_real=" work-real
             " gc_real=" gc-real
             " non_gc=" non-gc
             " gcs=" gcs)))

(run-c16)
