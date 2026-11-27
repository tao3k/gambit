;;;============================================================================

;;; File: "test.scm"

;;; (gambit fiber) — Unit & 12-Core Adversarial SMP Stress Tests
;;;
;;; Verifies:
;;;   1. Basic run-fibers, fiber-spawn, fiber-yield, return value & exceptions
;;;   2. Structured concurrency nursery (zero leaked fibers, nested nurseries,
;;;      child exception propagation)
;;;   3. Bounded & unbuffered (cap=0) fiber-channel ping-pong & MPMC conservation
;;;      (zero lost wakeups, exact message conservation under heavy contention)
;;;   4. 12-Core Adversarial Work-Stealing Stress: 20,000 fibers spawning,
;;;      yielding, and exchanging messages across all cores

(import (gambit fiber))
(import (gambit effect))
(import (srfi 226))
(import (srfi 230))
(import (_test))

;;;============================================================================
;;; 1. Basic Scheduler, Spawn, Yield & Return Value

(test-equal 42
  (run-fibers
   (lambda ()
     (fiber-yield)
     42)))

;; Uncaught root exception propagates cleanly
(test-equal 'caught-root
  (with-exception-catcher
   (lambda (e) e)
   (lambda ()
     (run-fibers (lambda () (raise 'caught-root))))))

;;;============================================================================
;;; 2. Structured Concurrency Nursery (Zero Orphaned Fibers & Exceptions)

(let ((done-count (make-atomic-fxbox 0)))
  (let ((res
         (run-fibers
          (lambda ()
            (with-nursery
             (lambda (n)
               (let loop ((i 0))
                 (if (fx< i 200)
                     (begin
                       (fiber-spawn
                        (lambda ()
                          (fiber-yield)
                          (atomic-fxbox+/fetch! done-count 1))
                        n)
                       (loop (fx+ i 1)))))
               'parent-ok))))))
    (test-equal 'parent-ok res)
    (test-equal 200 (atomic-fxbox-ref done-count))))

;; Nested nurseries
(let ((nested-sum (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (outer)
        (let oloop ((i 0))
          (if (fx< i 10)
              (begin
                (fiber-spawn
                 (lambda ()
                   (with-nursery
                    (lambda (inner)
                      (let iloop ((j 0))
                        (if (fx< j 20)
                            (begin
                              (fiber-spawn
                               (lambda ()
                                 (fiber-yield)
                                 (atomic-fxbox+/fetch! nested-sum 1))
                               inner)
                              (iloop (fx+ j 1))))))))
                 outer)
                (oloop (fx+ i 1)))))))))
  (test-equal 200 (atomic-fxbox-ref nested-sum)))

;; Child exception propagates out of with-nursery after all siblings finish
(let ((siblings-done (make-atomic-fxbox 0)))
  (let ((caught
         (with-exception-catcher
          (lambda (e) e)
          (lambda ()
            (run-fibers
             (lambda ()
               (with-nursery
                (lambda (n)
                  (fiber-spawn
                   (lambda ()
                     (fiber-yield)
                     (raise 'child-boom))
                   n)
                  (let loop ((i 0))
                    (if (fx< i 20)
                        (begin
                          (fiber-spawn
                           (lambda ()
                             (fiber-yield)
                             (fiber-yield)
                             (atomic-fxbox+/fetch! siblings-done 1))
                           n)
                          (loop (fx+ i 1)))))))))))))
    (test-equal 'child-boom caught)
    ;; Structured concurrency guarantee: all 20 siblings completed before exit!
    (test-equal 20 (atomic-fxbox-ref siblings-done))))

;;;============================================================================
;;; 3. Bounded & Unbuffered (cap=0) Channel Ping-Pong & Zero Lost Wakeup

(define (run-pingpong cap rounds)
  (run-fibers
   (lambda ()
     (let ((c1 (make-fiber-channel cap))
           (c2 (make-fiber-channel cap))
           (final 0))
       (with-nursery
        (lambda (n)
          (fiber-spawn
           (lambda ()
             (let loop ((i 0))
               (if (fx< i rounds)
                   (let ((v (fiber-recv! c1)))
                     (fiber-send! c2 (fx+ v 1))
                     (loop (fx+ i 1))))))
           n)
          (fiber-spawn
           (lambda ()
             (let loop ((i 0) (acc 0))
               (if (fx< i rounds)
                   (begin
                     (fiber-send! c1 i)
                     (loop (fx+ i 1) (fx+ acc (fiber-recv! c2))))
                   (set! final acc))))
           n)))
       final))))

;; Unbuffered rendezvous channel (cap = 0)
(test-equal 5050 (run-pingpong 0 100))
;; Single-slot bounded channel (cap = 1)
(test-equal 5050 (run-pingpong 1 100))
;; Buffered channel (cap = 16)
(test-equal 2001000 (run-pingpong 16 2000))

;;;============================================================================
;;; 4. Adversarial 12-Core MPMC Channel Conservation (Zero Lost Messages/Wakeups)

(let ((producers 12)
      (consumers 12)
      (per-prod 500)
      (total-sum (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((ch (make-fiber-channel 4))) ;; tight capacity forces constant park/wake races!
       (with-nursery
        (lambda (n)
          (let ploop ((p 0))
            (if (fx< p producers)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let loop ((i 1))
                       (if (fx<= i per-prod)
                           (begin
                             (fiber-send! ch i)
                             (loop (fx+ i 1))))))
                   n)
                  (ploop (fx+ p 1)))))
          (let cloop ((c 0))
            (if (fx< c consumers)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let loop ((i 0) (s 0))
                       (if (fx< i per-prod)
                           (loop (fx+ i 1) (fx+ s (fiber-recv! ch)))
                           (atomic-fxbox+/fetch! total-sum s))))
                   n)
                  (cloop (fx+ c 1))))))))))
  ;; Expected: 12 * (500 * 501 / 2) = 12 * 125250 = 1503000
  (test-equal 1503000 (atomic-fxbox-ref total-sum)))

;;;============================================================================
;;; 5. Adversarial 20,000-Fiber Work-Stealing Fanout Stress Test

(let ((n-fibers 20000)
      (completed (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        ;; 20 fanout parents x 1000 leaf fibers each
        (let ploop ((p 0))
          (if (fx< p 20)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let cloop ((c 0))
                     (if (fx< c 1000)
                         (begin
                           (fiber-spawn
                            (lambda ()
                              (fiber-yield)
                              (atomic-fxbox+/fetch! completed 1))
                            n)
                           (cloop (fx+ c 1))))))
                 n)
                (ploop (fx+ p 1)))))))))
  (test-equal n-fibers (atomic-fxbox-ref completed)))

;;;============================================================================
;;; 6. Adversarial Concurrent-SATB Major-GC x Fiber Fanout & Prompt Rewind Stress

(let ((stop (make-atomic-fxbox 0))
      (completed (make-atomic-fxbox 0)))
  (let ((gc-churner
         (thread-start!
          (make-thread
           (lambda ()
             (let loop ((acc '()) (i 0))
               (if (fx= (atomic-fxbox-ref stop (memory-order acquire)) 0)
                   (let ((chunk (make-vector 256 i)))
                     (loop (if (fx= (fxand i 63) 0) (list chunk) (cons chunk acc))
                           (fx+ i 1))))))))))
    (run-fibers
     (lambda ()
       (let nloop ((ni 0))
         (if (fx< ni 20)
             (begin
               (with-nursery
                (lambda (n)
                  (let floop ((fi 0))
                    (if (fx< fi 500)
                        (begin
                          (fiber-spawn
                           (lambda ()
                             (fiber-yield)
                             (atomic-fxbox+/fetch! completed 1))
                           n)
                          (floop (fx+ fi 1)))))))
               (nloop (fx+ ni 1)))))))
    (atomic-fxbox-set! stop 1 (memory-order release))
    (thread-join! gc-churner))
  (test-equal 10000 (atomic-fxbox-ref completed)))

;;;============================================================================
;;; 7. Adversarial Per-Fiber %tc-state Isolation (Effects + SRFI-226 Marks
;;;    Surviving Cross-Core Work-Stealing Migrations With Zero Leakage)

(define-effect fiber-tag-eff)

(let ((ok-count (make-atomic-fxbox 0))
      (num-fibers 200))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((fid 1))
          (if (fx<= fid num-fibers)
              (begin
                (fiber-spawn
                 (lambda ()
                   (with-continuation-mark 'fiber-id fid
                     (with-handler
                       ((tail: fiber-tag-eff () fid))
                       (let yloop ((k 0) (good #t))
                         (if (fx< k 10)
                             (begin
                               (fiber-yield)
                               (let ((e-val (perform fiber-tag-eff))
                                     (m-val (continuation-mark-set-first #f 'fiber-id #f)))
                                 (yloop (fx+ k 1)
                                        (and good
                                             (fx= e-val fid)
                                             (equal? m-val fid)))))
                             (if good
                                 (atomic-fxbox+/fetch! ok-count 1)))))))
                 n)
                (loop (fx+ fid 1)))))))))
  (test-equal num-fibers (atomic-fxbox-ref ok-count)))

;;;============================================================================
;;; 8. Adversarial LIFO Anti-Starvation: Tight Ping-Pong + 500 Sibling Fibers

(let ((siblings-done (make-atomic-fxbox 0))
      (pingpong-sum (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        ;; 4 tight ping-pong pairs hammering the LIFO slot
        (let ploop ((p 0))
          (if (fx< p 4)
              (let ((c1 (make-fiber-channel 1))
                    (c2 (make-fiber-channel 1)))
                (fiber-spawn
                 (lambda ()
                   (let r ((i 0))
                     (if (fx< i 500)
                         (begin (fiber-send! c2 (fx+ (fiber-recv! c1) 1))
                                (r (fx+ i 1))))))
                 n)
                (fiber-spawn
                 (lambda ()
                   (let s ((i 0) (acc 0))
                     (if (fx< i 500)
                         (begin (fiber-send! c1 i)
                                (s (fx+ i 1) (fx+ acc (fiber-recv! c2))))
                         (atomic-fxbox+/fetch! pingpong-sum acc))))
                 n)
                (ploop (fx+ p 1)))))
        ;; 500 background yielding siblings that MUST NOT starve
        (let sloop ((i 0))
          (if (fx< i 500)
              (begin
                (fiber-spawn
                 (lambda ()
                   (fiber-yield)
                   (fiber-yield)
                   (atomic-fxbox+/fetch! siblings-done 1))
                 n)
                (sloop (fx+ i 1)))))))))
  (test-equal 500 (atomic-fxbox-ref siblings-done))
  ;; 4 * sum(1..500) = 4 * 125250 = 501000
  (test-equal 501000 (atomic-fxbox-ref pingpong-sum)))

;;;============================================================================
;;; 9. Adversarial Sharded Quiescence Termination Stress (Zero False Premature Exit)
;;;    Alternates 1-fiber deep chains (11 idle cores scanning quiescence continuously)
;;;    with 500-fiber bursty work-stealing waves across all cores.

(let ((chain-done (make-atomic-fxbox 0))
      (burst-done (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     ;; 50 sequential 1-child recursive spawns (11 cores scanning quiescence!)
     (let cloop ((i 0))
       (if (fx< i 50)
           (begin
             (with-nursery
              (lambda (n)
                (fiber-spawn
                 (lambda ()
                   (fiber-yield)
                   (fiber-spawn
                    (lambda ()
                      (fiber-yield)
                      (atomic-fxbox+/fetch! chain-done 1))
                    n))
                 n)))
             (cloop (fx+ i 1)))))
     ;; 10 bursty waves x 500 fibers = 5,000 fibers
     (let wloop ((w 0))
       (if (fx< w 10)
           (begin
             (with-nursery
              (lambda (n)
                (let floop ((j 0))
                  (if (fx< j 500)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (fiber-yield)
                           (atomic-fxbox+/fetch! burst-done 1))
                         n)
                        (floop (fx+ j 1)))))))
             (wloop (fx+ w 1)))))))
  (test-equal 50 (atomic-fxbox-ref chain-done))
  (test-equal 5000 (atomic-fxbox-ref burst-done)))

;;;============================================================================
;;; 10. Adversarial Relaxed-Hint Channel Hammer (cap=0 & cap=1 across 12 cores)
;;;     Maximizes stale relaxed empty/full hints under extreme MPMC contention
;;;     to prove ZERO lost wakeups and exact sum conservation.

(let ((sum0 (make-atomic-fxbox 0))
      (sum1 (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((ch0 (make-fiber-channel 0))
           (ch1 (make-fiber-channel 1)))
       (with-nursery
        (lambda (n)
          ;; 8 producers x 200 items on unbuffered cap=0 + 8 producers x 200 items on cap=1
          (let loop ((p 0))
            (if (fx< p 8)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 1))
                       (if (fx<= i 200)
                           (begin (fiber-send! ch0 i) (iloop (fx+ i 1))))))
                   n)
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 0) (s 0))
                       (if (fx< i 200)
                           (iloop (fx+ i 1) (fx+ s (fiber-recv! ch0)))
                           (atomic-fxbox+/fetch! sum0 s))))
                   n)
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 1))
                       (if (fx<= i 200)
                           (begin (fiber-send! ch1 i) (iloop (fx+ i 1))))))
                   n)
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 0) (s 0))
                       (if (fx< i 200)
                           (iloop (fx+ i 1) (fx+ s (fiber-recv! ch1)))
                           (atomic-fxbox+/fetch! sum1 s))))
                   n)
                  (loop (fx+ p 1))))))))))
  ;; Expected: 8 * (200 * 201 / 2) = 8 * 20100 = 160800 each
  (test-equal 160800 (atomic-fxbox-ref sum0))
  (test-equal 160800 (atomic-fxbox-ref sum1)))

;;;============================================================================
