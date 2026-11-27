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
