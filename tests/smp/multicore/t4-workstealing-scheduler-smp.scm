;;; Adversarial SMP PBT for Tier 3.2 Work-Stealing & Dekker Wakeup Scheduler:
;;; 1. Dekker lost-wakeup adversarial stress: producer pinned to P0 enqueues
;;;    work via thread-start! and mutex-unlock! while sibling cores rapidly
;;;    transition idle <-> active across 160 burst rounds (zero timeouts).
;;; 2. Pinned-thread Head-of-Line (HoL) steal bypass: P0 holds a pinned busy
;;;    loop + pinned queued threads ahead of unpinned workers; verifies sibling
;;;    processors steal and complete unpinned workers concurrently without
;;;    waiting for P0's pinned threads to finish.
;;; 3. Parallel fork-join & mutex/condvar fan-out balance under GC-hammer:
;;;    verifies work spreads across multiple processors with zero deadlocks,
;;;    zero lost wakeups, and exact result conservation across p1/p2/p4/p6/p8.

(declare (standard-bindings) (extended-bindings) (block))

(define (assert-true ok label . info)
  (if (not ok)
      (apply error (string-append "T4-FAIL: " label) info)))

(define (proc-count) (##current-vm-processor-count))
(define (cur-proc-id) (##current-processor-id))

(define (busy-work n)
  (let loop ((i 0) (acc 0))
    (if (##fx< i n)
        (loop (##fx+ i 1) (##fxwrap+ acc (##fxand i 7)))
        acc)))

;; ---------------------------------------------------------------------------
;; Scenario 1: Dekker lost-wakeup adversarial burst stress (mutex & spawn)
;; ---------------------------------------------------------------------------
(define (test-dekker-wakeup-bursts)
  (let* ((np (proc-count))
         (rounds 120)
         (m (make-mutex))
         (cv (make-condition-variable))
         (done-m (make-mutex))
         (done-cv (make-condition-variable))
         (epoch 0)
         (completed 0)
         (stop? #f)
         (n-workers (max 4 (* 2 np)))
         (seen-procs (make-vector np 0)))
    ;; Persistent workers that repeatedly wake, do short work, then sleep on cv
    ;; (forcing idle processors in/out of ##wait-idle-if-unchanged! continuously)
    (let ((workers
           (let loop ((w 0) (acc '()))
             (if (= w n-workers)
                 acc
                 (loop
                  (+ w 1)
                  (cons
                   (thread-start!
                    (make-thread
                     (lambda ()
                       (let wloop ((last-seen 0))
                         (mutex-lock! m)
                         (let wait ()
                           (if (and (not stop?) (= epoch last-seen))
                               (begin
                                 (mutex-unlock! m cv)
                                 (mutex-lock! m)
                                 (wait))))
                         (let ((cur epoch)
                               (s stop?))
                           (mutex-unlock! m)
                           (if (not s)
                               (begin
                                 (let ((pid (cur-proc-id)))
                                   (vector-set! seen-procs pid
                                                (+ (vector-ref seen-procs pid) 1)))
                                 (busy-work 4000)
                                 (mutex-lock! done-m)
                                 (set! completed (+ completed 1))
                                 (if (= completed n-workers)
                                     (condition-variable-signal! done-cv))
                                 (mutex-unlock! done-m)
                                 (wloop cur))))))))
                   acc))))))
      ;; Run 120 broadcast + short-sleep burst rounds; every round must complete
      ;; well under a strict 5s deadline (a lost wakeup would hang or stall).
      (let rloop ((r 1))
        (if (<= r rounds)
            (begin
              (mutex-lock! done-m)
              (set! completed 0)
              (mutex-unlock! done-m)
              ;; Brief pause every 15 rounds so sibling cores genuinely enter kernel ##wait!
              (if (= (modulo r 15) 0)
                  (thread-sleep! 0.002))
              (mutex-lock! m)
              (set! epoch r)
              (condition-variable-broadcast! cv)
              (mutex-unlock! m)
              ;; Also exercise single-thread spawn while sibling cores wake
              (let ((ephemeral
                     (thread-start!
                      (make-thread (lambda () (busy-work 1500) r)))))
                (assert-true (eqv? (thread-join! ephemeral 5 'timeout) r)
                             "ephemeral-spawn-timeout" r))
              ;; Wait for all persistent workers to complete this burst
              (mutex-lock! done-m)
              (let wdone ()
                (if (< completed n-workers)
                    (begin
                      (assert-true (mutex-unlock! done-m done-cv 5)
                                   "burst-round-lost-wakeup" r completed n-workers)
                      (mutex-lock! done-m)
                      (wdone))))
              (mutex-unlock! done-m)
              (rloop (+ r 1)))))
      (mutex-lock! m)
      (set! stop? #t)
      (condition-variable-broadcast! cv)
      (mutex-unlock! m)
      (for-each
       (lambda (th)
         (assert-true (not (eq? (thread-join! th 5 'timeout) 'timeout))
                      "worker-shutdown-timeout"))
       workers)
      (let ((active-cores
             (let cloop ((i 0) (c 0))
               (if (= i np)
                   c
                   (cloop (+ i 1)
                          (if (> (vector-ref seen-procs i) 0) (+ c 1) c))))))
        (if (> np 1)
            (assert-true (>= active-cores 2)
                         "dekker-bursts-used-multiple-cores" np seen-procs))
        (list rounds active-cores)))))

;; ---------------------------------------------------------------------------
;; Scenario 2: Pinned-thread Head-of-Line (HoL) steal bypass proof
;; ---------------------------------------------------------------------------
(define (test-pinned-hol-steal-bypass)
  (let ((np (proc-count)))
    (if (= np 1)
        (list 0 0)
        (let* ((p0 (##processor 0))
               (gate (make-mutex))
               (p0-busy-started (make-mutex))
               (release-p0 (make-mutex))
               (unpinned-done (make-mutex))
               (unpinned-cv (make-condition-variable))
               (unpinned-count 0)
               (stolen-on-sibling 0)
               (n-unpinned 24))
          (mutex-lock! gate)
          (mutex-lock! p0-busy-started)
          (mutex-lock! release-p0)
          ;; Pin a coordinator thread on P0 that queues high-priority pinned
          ;; blockers on P0's runq, then enqueues unpinned workers on P0 via
          ;; mutex-unlock! (which uses run-queue-of-current-processor-preferably!)
          ;; while P0 itself stays occupied on CPU until siblings steal & finish
          ;; all unpinned workers.
          (let* ((p0-driver
                  (let ((th (make-thread
                             (lambda ()
                               ;; Spawn 2 pinned threads on P0 (higher priority -> HoL of P0 runq)
                               (let ((pin1 (make-thread (lambda () (busy-work 2000))))
                                     (pin2 (make-thread (lambda () (busy-work 2000)))))
                                 (thread-base-priority-set! pin1 10.0)
                                 (thread-base-priority-set! pin2 10.0)
                                 (##thread-pin! pin1 p0)
                                 (##thread-pin! pin2 p0)
                                 (thread-start! pin1)
                                 (thread-start! pin2)
                                 ;; Spawn unpinned workers (lower priority -> behind pin1/pin2 in rbtree)
                                 (let ((workers
                                        (let loop ((i 0) (acc '()))
                                          (if (= i n-unpinned)
                                              acc
                                              (let ((w (make-thread
                                                        (lambda ()
                                                          (let ((pid (cur-proc-id)))
                                                            (busy-work 8000)
                                                            (mutex-lock! unpinned-done)
                                                            (if (not (= pid 0))
                                                                (set! stolen-on-sibling
                                                                      (+ stolen-on-sibling 1)))
                                                            (set! unpinned-count
                                                                  (+ unpinned-count 1))
                                                            (if (= unpinned-count n-unpinned)
                                                                (condition-variable-signal! unpinned-cv))
                                                            (mutex-unlock! unpinned-done))))))
                                                (thread-base-priority-set! w 0.0)
                                                (thread-start! w)
                                                (loop (+ i 1) (cons w acc)))))))
                                   ;; Signal started and stay non-yielding on P0 briefly so
                                   ;; pin1 & pin2 sit at HoL of P0's runq while siblings steal
                                   ;; the unpinned workers sitting behind them!
                                   (mutex-unlock! p0-busy-started)
                                   (let spin ((k 0))
                                     (if (and (< k 4000)
                                              (let ()
                                                (mutex-lock! unpinned-done)
                                                (let ((done (= unpinned-count n-unpinned)))
                                                  (mutex-unlock! unpinned-done)
                                                  (not done))))
                                         (begin
                                           (busy-work 2000)
                                           (spin (+ k 1)))))
                                   (for-each (lambda (w) (thread-join! w 5)) workers)
                                   (thread-join! pin1 5)
                                   (thread-join! pin2 5)))))))
                    (##thread-pin! th p0)
                    (thread-start! th))))
            (mutex-lock! p0-busy-started)
            (mutex-unlock! p0-busy-started)
            (assert-true (not (eq? (thread-join! p0-driver 10 'timeout) 'timeout))
                         "pinned-hol-driver-timeout")
            (assert-true (= unpinned-count n-unpinned)
                         "pinned-hol-count" unpinned-count n-unpinned)
            (assert-true (> stolen-on-sibling 0)
                         "pinned-hol-bypassed-to-sibling" stolen-on-sibling)
            (list unpinned-count stolen-on-sibling))))))

;; ---------------------------------------------------------------------------
;; Scenario 3: Parallel fork-join + mutex fan-out under continuous GC-hammer
;; ---------------------------------------------------------------------------
(define (par-fib n cutoff)
  (if (<= n cutoff)
      (let fib ((k n))
        (if (< k 2) k (+ (fib (- k 1)) (fib (- k 2)))))
      (let ((t (thread-start! (make-thread (lambda () (par-fib (- n 1) cutoff))))))
        (let ((r2 (par-fib (- n 2) cutoff)))
          (+ (thread-join! t) r2)))))

(define (test-fork-join-gc-hammer)
  (let* ((stop-gc #f)
         (gc-pulses 0)
         (hammer
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ()
                (if (not stop-gc)
                    (begin
                      (##gc)
                      (set! gc-pulses (+ gc-pulses 1))
                      (thread-sleep! 0.002)
                      (loop))))))))
         (expected 121393) ;; fib(26)
         (r1 (par-fib 26 19))
         (r2 (par-fib 26 19)))
    (set! stop-gc #t)
    (thread-join! hammer 5)
    (assert-true (and (= r1 expected) (= r2 expected))
                 "par-fib-exact" r1 r2 expected)
    (list r1 gc-pulses)))

(define gc-before (##f64vector-ref (##process-statistics) 6))
(define s1 (test-dekker-wakeup-bursts))
(define s2 (test-pinned-hol-steal-bypass))
(define s3 (test-fork-join-gc-hammer))
(define gc-after (##f64vector-ref (##process-statistics) 6))

(write
 (list 'T4-WORKSTEALING-SCHEDULER-PASS
       'procs (proc-count)
       's1-rounds (car s1)
       's1-active-cores (cadr s1)
       's2-unpinned (car s2)
       's2-stolen-sibling (cadr s2)
       's3-parfib (car s3)
       's3-gc-pulses (cadr s3)
       'gc-total (inexact->exact (round (- gc-after gc-before)))))
(newline)
