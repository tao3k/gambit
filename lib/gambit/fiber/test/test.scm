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
;;; 11. Adversarial Bounded Ring Channel (cap=3, cap=5) Strict FIFO + Direct
;;;     Handoff + Zero-Capture Nursery Abort with dynamic-wind After-Before-Join

;; 11a. Non-power-of-two cap=3 MPMC (8 producers x 8 consumers x 250 items)
(let ((sum3 (make-atomic-fxbox 0))
      (fifo-ok #t))
  (run-fibers
   (lambda ()
     (let ((ch3 (make-fiber-channel 3))
           (ch-fifo (make-fiber-channel 5)))
       (with-nursery
        (lambda (n)
          ;; Single-producer / single-consumer strict FIFO check across cap=5
          (fiber-spawn
           (lambda ()
             (let loop ((i 1))
               (if (fx<= i 1000)
                   (begin (fiber-send! ch-fifo i) (loop (fx+ i 1))))))
           n)
          (fiber-spawn
           (lambda ()
             (let loop ((expected 1))
               (if (fx<= expected 1000)
                   (let ((got (fiber-recv! ch-fifo)))
                     (if (not (fx= got expected)) (set! fifo-ok #f))
                     (loop (fx+ expected 1))))))
           n)
          ;; 8x8 MPMC hammer on non-power-of-two cap=3
          (let loop ((p 0))
            (if (fx< p 8)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 1))
                       (if (fx<= i 250)
                           (begin (fiber-send! ch3 i) (iloop (fx+ i 1))))))
                   n)
                  (fiber-spawn
                   (lambda ()
                     (let iloop ((i 0) (s 0))
                       (if (fx< i 250)
                           (iloop (fx+ i 1) (fx+ s (fiber-recv! ch3)))
                           (atomic-fxbox+/fetch! sum3 s))))
                   n)
                  (loop (fx+ p 1))))))))))
  ;; Expected: 8 * (250 * 251 / 2) = 8 * 31375 = 251000
  (test-equal #t fifo-ok)
  (test-equal 251000 (atomic-fxbox-ref sum3)))

;; 11b. Zero-capture ##with-exception-handler nursery child abort MUST execute
;;      dynamic-wind after thunk BEFORE with-nursery returns/raises to parent!
(let ((after-ran (make-atomic-fxbox 0))
      (caught #f))
  (with-exception-catcher
   (lambda (e) (set! caught e))
   (lambda ()
     (run-fibers
      (lambda ()
        (with-nursery
         (lambda (n)
           (fiber-spawn
            (lambda ()
              (dynamic-wind
                (lambda () #!void)
                (lambda ()
                  (fiber-yield)
                  (raise 'c8-child-boom))
                (lambda ()
                  (atomic-fxbox+/fetch! after-ran 1))))
            n)))))))
  (test-equal 'c8-child-boom caught)
  (test-equal 1 (atomic-fxbox-ref after-ran)))

;;;============================================================================
;;; 12. Adversarial Overflow (>4096-fiber burst) + Sticky Victim Stealing +
;;;     Mixed Non-Null / Null Control-State Isolation Under Cross-Core Migration

(let ((overflow-done (make-atomic-fxbox 0))
      (clean-tc-ok (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     ;; 12a. 5,000 fibers in a single nursery forces local 4096-slot deque to
     ;;      spill into global-q and tests global-pending hint + sticky stealing.
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i 5000)
              (begin
                (fiber-spawn
                 (lambda ()
                   (fiber-yield)
                   (atomic-fxbox+/fetch! overflow-done 1))
                 n)
                (loop (fx+ i 1)))))))
     ;; 12b. Interleave fibers WITH continuation marks (non-#f tc) and fibers
     ;;      WITHOUT marks (#f tc) to verify lazy #f write-barrier skip never leaks!
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i 200)
              (begin
                (if (fx= (fxand i 1) 0)
                    (fiber-spawn
                     (lambda ()
                       (with-continuation-mark 'leak-check i
                         (begin
                           (fiber-yield)
                           (if (equal? (continuation-mark-set-first #f 'leak-check #f) i)
                               (atomic-fxbox+/fetch! clean-tc-ok 1)))))
                     n)
                    (fiber-spawn
                     (lambda ()
                       (fiber-yield)
                       (if (eq? (continuation-mark-set-first #f 'leak-check #f) #f)
                           (atomic-fxbox+/fetch! clean-tc-ok 1)))
                     n))
                (loop (fx+ i 1)))))))))
  (test-equal 5000 (atomic-fxbox-ref overflow-done))
  (test-equal 200 (atomic-fxbox-ref clean-tc-ok)))

;;;============================================================================
;;; 13. Continuation-Safe Resource Cleanup (with-finally vs dynamic-wind across
;;;     fiber-yield, channel park/resume, algebraic effects, nursery abort)
;;;     + Heterogeneous Performance-Core Detection (fiber-performance-core-count)

(define-effect cleanup-step-eff)

;; 13a. with-finally across repeated fiber-yield + channel park/resume + multiple values
(let ((cleanup-count (make-atomic-fxbox 0))
      (mv-ok (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((ch (make-fiber-channel 4)))
       (with-nursery
        (lambda (n)
          (let loop ((i 0))
            (if (fx< i 100)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (call-with-values
                      (lambda ()
                        (with-finally
                         (lambda ()
                           (fiber-yield)
                           (fiber-send! ch i)
                           (fiber-yield)
                           (values i (fx+ i 1)))
                         (lambda ()
                           (atomic-fxbox+/fetch! cleanup-count 1))))
                      (lambda (a b)
                        (if (and (fx= a i) (fx= b (fx+ i 1)))
                            (atomic-fxbox+/fetch! mv-ok 1)))))
                   n)
                  (loop (fx+ i 1)))))
          (fiber-spawn
           (lambda ()
             (let rloop ((k 0))
               (if (fx< k 100)
                   (begin (fiber-recv! ch) (rloop (fx+ k 1))))))
           n))))))
  (test-equal 100 (atomic-fxbox-ref cleanup-count))
  (test-equal 100 (atomic-fxbox-ref mv-ok)))

;; 13b. with-finally across non-tail algebraic effect perform/resume + fiber-yield
;;      MUST fire cleanup strictly once (no double-release on delimited continuation capture!)
(let ((wf-runs (make-atomic-fxbox 0))
      (res #f))
  (set! res
    (run-fibers
     (lambda ()
       (with-handler
         ((cleanup-step-eff (k x)
            (fiber-yield)
            (resume k (fx+ x 10))))
         (with-finally
          (lambda ()
            (let* ((a (perform cleanup-step-eff 1))
                   (_ (fiber-yield))
                   (b (perform cleanup-step-eff a)))
              b))
          (lambda ()
            (atomic-fxbox+/fetch! wf-runs 1)))))))
  (test-equal 21 res)
  (test-equal 1 (atomic-fxbox-ref wf-runs)))

;; 13c. with-finally on exception raise inside nursery child MUST run cleanup
;;      strictly once BEFORE with-nursery propagates the exception
(let ((wf-abort (make-atomic-fxbox 0))
      (caught #f))
  (with-exception-catcher
   (lambda (e) (set! caught e))
   (lambda ()
     (run-fibers
      (lambda ()
        (with-nursery
         (lambda (n)
           (fiber-spawn
            (lambda ()
              (with-finally
               (lambda ()
                 (fiber-yield)
                 (fiber-yield)
                 (raise 'wf-boom))
               (lambda ()
                 (atomic-fxbox+/fetch! wf-abort 1))))
            n)))))))
  (test-equal 'wf-boom caught)
  (test-equal 1 (atomic-fxbox-ref wf-abort)))

;; 13d. dynamic-wind across fiber-yield and channel park/resume MUST run after
;;      strictly once (no-winding fiber scheduler never double-triggers after)
(let ((dw-after (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((c1 (make-fiber-channel 1))
           (c2 (make-fiber-channel 1)))
       (with-nursery
        (lambda (n)
          (fiber-spawn
           (lambda ()
             (dynamic-wind
               (lambda () #!void)
               (lambda ()
                 (let loop ((i 0))
                   (if (fx< i 20)
                       (begin
                         (fiber-yield)
                         (let ((v (fiber-recv! c1)))
                           (fiber-send! c2 (fx+ v 1)))
                         (loop (fx+ i 1))))))
               (lambda ()
                 (atomic-fxbox+/fetch! dw-after 1))))
           n)
          (fiber-spawn
           (lambda ()
             (let loop ((i 0))
               (if (fx< i 20)
                   (begin
                     (fiber-send! c1 i)
                     (fiber-recv! c2)
                     (loop (fx+ i 1))))))
           n))))))
  (test-equal 1 (atomic-fxbox-ref dw-after)))

;; 13e. fiber-performance-core-count returns a valid positive P-core count
(let ((pcores (fiber-performance-core-count)))
  (test-assert (and (fixnum? pcores)
                    (fx>= pcores 1)
                    (fx<= pcores (##current-vm-processor-count))))
  (test-equal pcores
    (run-fibers (lambda () (fiber-worker-count)) workers: pcores)))

;;;============================================================================
