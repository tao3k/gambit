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
;;; 14. Adversarial SMP One-Shot Stack Rewind, Parked-Section Recycling,
;;;     Mixed Multi-Shot call/cc, Deep > 4 KiB Stacks & COW-Fork Replay DAG

;; 14a. High-volume ping-pong + concurrent GC hammering across all carriers:
;;      verifies one-shot stack rewind & parked-section recycling remain 100%
;;      memory-safe under concurrent minor/major GC and cross-core stealing.
(##gc)
(let* ((num-pairs (max 2 (min 8 (##current-vm-processor-count))))
       (ok-pairs (make-atomic-fxbox 0))
       (rw-before (##gc-oneshot-continuation-rewinds)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let ploop ((p 0))
          (if (fx< p num-pairs)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let ((c1 (make-fiber-channel 16))
                         (c2 (make-fiber-channel 16)))
                     (with-nursery
                      (lambda (pn)
                        (fiber-spawn
                         (lambda ()
                           (let rloop ((i 0))
                             (if (fx< i 1500)
                                 (let ((v (fiber-recv! c1)))
                                   (fiber-send! c2 (fx+ v 1))
                                   (rloop (fx+ i 1))))))
                         pn)
                        (fiber-spawn
                         (lambda ()
                           (let iloop ((i 0) (acc 0))
                             (if (fx< i 1500)
                                 (begin
                                   (if (and (fx= p 0) (fx= (fxand i 511) 511))
                                       (##gc))
                                   (fiber-send! c1 i)
                                   (iloop (fx+ i 1) (fx+ acc (fiber-recv! c2))))
                                 (if (fx= acc 1125750)
                                     (atomic-fxbox+/fetch! ok-pairs 1)))))
                         pn)))))
                 n)
                (ploop (fx+ p 1)))))))))
  (test-equal num-pairs (atomic-fxbox-ref ok-pairs))
  (test-assert (fx> (fx- (##gc-oneshot-continuation-rewinds) rw-before) 0)))

;; 14b. Mixed multi-shot call/cc inside fibers + one-shot fiber park/yield:
;;      proves non-aliasing guard never reclaims or corrupts a live multi-shot
;;      call/cc span when a fiber yields/parks and migrates across carriers.
(let ((ok-count (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i 16)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let ((saved-k #f)
                         (visits 0)
                         (sum 0))
                     (let ((v (call-with-current-continuation
                               (lambda (k)
                                 (set! saved-k k)
                                 (fiber-yield)
                                 10))))
                       (set! visits (fx+ visits 1))
                       (set! sum (fx+ sum v))
                       (fiber-yield)
                       (if (fx< visits 3)
                           (saved-k (fx+ v 10))))
                     (if (and (fx= visits 3) (fx= sum 60))
                         (atomic-fxbox+/fetch! ok-count 1))))
                 n)
                (loop (fx+ i 1)))))))))
  (test-equal 16 (atomic-fxbox-ref ok-count)))

;; 14c. Deep (> 4 KiB / > 64 frames) recursive fiber stacks across channel
;;      park/resume & work-stealing: verifies partial-chunk restores never
;;      prematurely clear their underlying stack span.
(let ((deep-ok (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i 8)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let ((ch (make-fiber-channel 1)))
                     (let ((res
                            (let recur ((d 140))
                              (if (fx= d 0)
                                  (begin
                                    (fiber-yield)
                                    (fiber-spawn (lambda () (fiber-send! ch 42)))
                                    (fiber-recv! ch))
                                  (let ((x (fx+ d 1)))
                                    (fx+ 1 (recur (fx- d 1)) (fx- x d)))))))
                       (if (fx= res (fx+ 42 (fx* 140 2)))
                           (atomic-fxbox+/fetch! deep-ok 1)))))
                 n)
                (loop (fx+ i 1)))))))))
  (test-equal 8 (atomic-fxbox-ref deep-ok)))

;; 14d. Multi-shot replay + concurrent downstream snapshot reader fiber DAG:
;;      producer publishes immutable snapshots and replays via fresh COW vectors
;;      while concurrent downstream consumer fibers verify snapshot immutability
;;      and linear side-effecting tasks execute strictly once.
(let ((linear-runs (make-atomic-fxbox 0))
      (reader-ok (make-atomic-fxbox 0))
      (replay-ok (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((snap-ch (make-fiber-channel 32))
           (done-ch (make-fiber-channel 16)))
       (with-nursery
        (lambda (n)
          ;; Linear side-effecting upstream task (executes strictly once)
          (fiber-spawn
           (lambda ()
             (atomic-fxbox+/fetch! linear-runs 1)
             (fiber-send! done-ch 'linear-done))
           n)
          ;; Pure multi-shot producer publishing immutable COW snapshots
          (fiber-spawn
           (lambda ()
             (let loop ((shot 0))
               (if (fx< shot 64)
                   (let ((cow-buf (make-vector 16 (fx+ 1000 shot))))
                     (fiber-send! snap-ch (cons shot cow-buf))
                     (fiber-yield)
                     (atomic-fxbox+/fetch! replay-ok 1)
                     (loop (fx+ shot 1))))))
           n)
          ;; 4 concurrent downstream consumer fibers verifying every snapshot
          (let cloop ((c 0))
            (if (fx< c 4)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let rloop ((k 0))
                       (if (fx< k 16)
                           (let* ((msg (fiber-recv! snap-ch))
                                  (shot (car msg))
                                  (buf (cdr msg))
                                  (exp (fx+ 1000 shot)))
                             (fiber-yield)
                             (let chk ((j 0) (good #t))
                               (if (fx< j 16)
                                   (chk (fx+ j 1) (and good (fx= (vector-ref buf j) exp)))
                                   (if good (atomic-fxbox+/fetch! reader-ok 1))))
                             (rloop (fx+ k 1))))))
                   n)
                  (cloop (fx+ c 1)))))
          (fiber-recv! done-ch))))))
  (test-equal 1 (atomic-fxbox-ref linear-runs))
  (test-equal 64 (atomic-fxbox-ref replay-ok))
  (test-equal 64 (atomic-fxbox-ref reader-ok)))

;; 14e. Property-based randomized MPMC linearizability & exact per-producer FIFO
;;      model check on fiber-channel (adaptive to VM processor count) across
;;      cap in {0, 1, 2, 4, 8, 16} with interleaved fiber-yield and concurrent
;;      GC: verifies zero drops, zero duplicates, exact item set conservation,
;;      and strict per-producer FIFO order across all cores.
(let* ((p (max 2 (min 8 (##current-vm-processor-count))))
       (rounds 12)
       (items-per-prod 50)
       (all-ok #t))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let* ((cap (vector-ref '#(0 1 2 4 8 16) (fxmodulo r 6)))
               (ch (make-fiber-channel cap))
               (total (fx* p items-per-prod))
               (seen (let ((v (make-vector total #f)))
                       (let sloop ((i 0))
                         (if (fx< i total)
                             (begin (vector-set! v i (make-atomic-fxbox 0))
                                    (sloop (fx+ i 1)))))
                       v))
               (order-bad (make-atomic-fxbox 0))
               (dup-bad (make-atomic-fxbox 0))
               (cons-done (make-atomic-fxbox 0)))
          (run-fibers
           (lambda ()
             (with-nursery
              (lambda (n)
                ;; P concurrent producers encoding (prod-id * items-per-prod + seq)
                (let ploop ((pid 0))
                  (if (fx< pid p)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (let iloop ((seq 0))
                             (if (fx< seq items-per-prod)
                                 (let ((tok (fx+ (fx* pid items-per-prod) seq)))
                                   (fiber-send! ch tok)
                                   (if (fx= (fxand (fx+ pid seq r) 7) 7) (fiber-yield))
                                   (iloop (fx+ seq 1))))))
                         n)
                        (ploop (fx+ pid 1)))))
                ;; P concurrent consumers verifying lock-free uniqueness & exact conservation
                (let cloop ((cid 0))
                  (if (fx< cid p)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (let iloop ((k 0))
                             (if (fx< k items-per-prod)
                                 (let* ((v (fiber-recv! ch))
                                        (prev (atomic-fxbox+/fetch! (vector-ref seen v) 1)))
                                   (if (not (fx= prev 0))
                                       (atomic-fxbox+/fetch! dup-bad 1))
                                   (atomic-fxbox+/fetch! cons-done 1)
                                   (if (and (fx= cid 0) (fx= (fxand k 31) 31))
                                       (##gc))
                                   (iloop (fx+ k 1))))))
                         n)
                        (cloop (fx+ cid 1))))))))
           workers: p)
          ;; Single-consumer exact per-producer FIFO check on the same channel
          (let ((ch-fifo (make-fiber-channel cap))
                (fifo-last (make-vector p -1)))
            (run-fibers
             (lambda ()
               (with-nursery
                (lambda (n)
                  (let ploop ((pid 0))
                    (if (fx< pid p)
                        (begin
                          (fiber-spawn
                           (lambda ()
                             (let iloop ((seq 0))
                               (if (fx< seq 25)
                                   (begin
                                     (fiber-send! ch-fifo (fx+ (fx* pid 25) seq))
                                     (if (fx= (fxand seq 7) 7) (fiber-yield))
                                     (iloop (fx+ seq 1))))))
                           n)
                          (ploop (fx+ pid 1)))))
                  (fiber-spawn
                   (lambda ()
                     (let cloop ((k 0))
                       (if (fx< k (fx* p 25))
                           (let* ((v (fiber-recv! ch-fifo))
                                  (pid (fxquotient v 25))
                                  (seq (fxmodulo v 25)))
                             (if (not (fx= seq (fx+ (vector-ref fifo-last pid) 1)))
                                 (atomic-fxbox+/fetch! order-bad 1))
                             (vector-set! fifo-last pid seq)
                             (cloop (fx+ k 1))))))
                   n))))
             workers: p))
          ;; Verify every single item [0 .. total) was delivered strictly once
          (let vloop ((i 0))
            (if (fx< i total)
                (begin
                  (if (not (fx= (atomic-fxbox-ref (vector-ref seen i)) 1))
                      (set! all-ok #f))
                  (vloop (fx+ i 1)))))
          (if (or (not (fx= (atomic-fxbox-ref cons-done) total))
                  (not (fx= (atomic-fxbox-ref dup-bad) 0))
                  (not (fx= (atomic-fxbox-ref order-bad) 0)))
              (set! all-ok #f))
          (rloop (fx+ r 1)))))
  (test-assert all-ok))

;; 14f. Adversarial cap=1/cap=2 tx-fast/rx-fast cancel pointer-ABA & slow-path
;;      non-empty-ring FIFO torture across adaptive P cores: hammers rapid
;;      full-ring + parked-sender / empty-ring + parked-receiver transitions
;;      while recycling %fiber-k heavily.
(let* ((p (max 2 (min 12 (##current-vm-processor-count))))
       (items-per-prod 80)
       (ok-all #t))
  (let cloop ((caps '(1 2)))
    (if (pair? caps)
        (let* ((cap (car caps))
               (ch (make-fiber-channel cap))
               (last-seq (make-vector p -1))
               (order-bad (make-atomic-fxbox 0))
               (total (fx* p items-per-prod)))
          (run-fibers
           (lambda ()
             (with-nursery
              (lambda (n)
                (let ploop ((pid 0))
                  (if (fx< pid p)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (let sloop ((seq 0))
                             (if (fx< seq items-per-prod)
                                 (begin
                                   (fiber-send! ch (fx+ (fx* pid items-per-prod) seq))
                                   (sloop (fx+ seq 1))))))
                         n)
                        (ploop (fx+ pid 1)))))
                (fiber-spawn
                 (lambda ()
                   (let rloop ((k 0))
                     (if (fx< k total)
                         (let* ((v (fiber-recv! ch))
                                (pid (fxquotient v items-per-prod))
                                (seq (fxmodulo v items-per-prod)))
                           (if (not (fx= seq (fx+ (vector-ref last-seq pid) 1)))
                               (atomic-fxbox+/fetch! order-bad 1))
                           (vector-set! last-seq pid seq)
                           (if (fx= (fxand k 15) 15) (fiber-yield))
                           (rloop (fx+ k 1))))))
                 n))))
           workers: p)
          (if (not (fx= (atomic-fxbox-ref order-bad) 0))
              (set! ok-all #f))
          (cloop (cdr caps)))))
  (test-assert ok-all))

;; 14g. Rapid nested nursery flush vs stolen-LIFO regression (catches stale
;;      ctx.lifo cached across %nursery-flush! in %sched-switch-next!):
;;      forces (ticks & 15) == 15 batched nursery completion wakes while
;;      ctx.lifo holds a woken %fiber-k and peer workers steal from ctx.dq.
(let* ((p (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 40)
       (done-count (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let rloop ((r 0))
       (if (fx< r rounds)
           (let ((ch (make-fiber-channel 1))
                 (children (fx+ 20 (fxmodulo r 24))))
             (with-nursery
              (lambda (outer)
                (fiber-spawn
                 (lambda ()
                   (with-nursery
                    (lambda (inner)
                      (let cloop ((i 0))
                        (if (fx< i children)
                            (begin
                              (fiber-spawn
                               (lambda ()
                                 (fiber-yield)
                                 (atomic-fxbox+/fetch! done-count 1))
                               inner)
                              (cloop (fx+ i 1)))))))
                   (fiber-send! ch r))
                 outer)
                (fiber-spawn
                 (lambda ()
                   (fiber-recv! ch)
                   (fiber-yield))
                 outer)))
             (rloop (fx+ r 1))))))
   workers: p)
  (let ((expected (let loop ((r 0) (s 0))
                    (if (fx< r rounds)
                        (loop (fx+ r 1) (fx+ s (fx+ 20 (fxmodulo r 24))))
                        s))))
    (test-equal expected (atomic-fxbox-ref done-count))))

;; 14h. Oversubscribed W = 3 * P deadlock-freedom regression: verifies
;;      cooperative pre-park (thread-yield!) prevents carrier starvation on
;;      small/CI machines when workers exceed VM processor count.
(let* ((p (max 1 (min 4 (##current-vm-processor-count))))
       (w (fx* 3 p))
       (done (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let rloop ((r 0))
       (if (fx< r 12)
           (let ((ch (make-fiber-channel 4)))
             (with-nursery
              (lambda (n)
                (let iloop ((i 0))
                  (if (fx< i 80)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (fiber-yield)
                           (fiber-send! ch i)
                           (atomic-fxbox+/fetch! done 1))
                         n)
                        (fiber-spawn
                         (lambda ()
                           (fiber-recv! ch))
                         n)
                        (iloop (fx+ i 1)))))))
             (rloop (fx+ r 1))))))
   workers: w)
  (test-equal (fx* 12 80) (atomic-fxbox-ref done)))

;; 14i. Parallel STW Remark Phase R-A Chez remote-inbox quiescence regression:
;;      spawns (3000 * P) simultaneously live suspended fibers referencing a
;;      cross-core mature-anchor graph and triggers explicit STW Major GC
;;      Remark ((##gc)) to guard against split-counter Remark livelock.
(let* ((p (max 2 (min 12 (##current-vm-processor-count))))
       (n-fibers (fx* 3000 p))
       (started (make-atomic-fxbox 0))
       (done (make-atomic-fxbox 0))
       (anchors (make-vector 512 #f)))
  (let aloop ((i 0))
    (if (fx< i 512)
        (begin (vector-set! anchors i (make-vector 64 i))
               (aloop (fx+ i 1)))))
  (##gc)
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i n-fibers)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let ((local-obj (cons (vector-ref anchors (fxand i 511))
                                          (make-vector 4 i))))
                     (atomic-fxbox+/fetch! started 1)
                     (fiber-yield)
                     (fiber-yield)
                     (if (fx= (vector-ref (cdr local-obj) 0) i)
                         (atomic-fxbox+/fetch! done 1))))
                 n)
                (loop (fx+ i 1)))))
        (##gc)
        (##gc))))
   workers: p)
  (test-equal n-fibers (atomic-fxbox-ref started))
  (test-equal n-fibers (atomic-fxbox-ref done)))

;; 14j. Cross-module (gambit effect) + (gambit fiber) work-stealing carrier
;;      migration: fibers run suspending with-handler, direct-style generators,
;;      and multi-shot effects while parking on channels and migrating across
;;      all P carrier threads.
(let* ((p (max 2 (min 12 (##current-vm-processor-count))))
       (n-fibers (fx* 8 p))
       (eff-step (make-effect 'fiber-mig-step))
       (eff-choose (make-effect 'fiber-mig-choose))
       (ok (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((ch (make-fiber-channel 4)))
       (with-nursery
        (lambda (n)
          (let loop ((i 0))
            (if (fx< i n-fibers)
                (begin
                  (fiber-spawn
                   (lambda ()
                     ;; Suspending handler + generator + channel park across carriers
                     (let ((s1
                            (with-handler
                              ((eff-step (k v) (resume k (fx+ v 1))))
                              (let iloop ((j 0) (a 0))
                                (if (fx< j 16)
                                    (begin
                                      (if (fx= (fxand j 3) 3)
                                          (begin (fiber-send! ch j)
                                                 (fiber-recv! ch)))
                                      (iloop (fx+ j 1) (perform eff-step a)))
                                    a))))
                           (g (make-generator
                               (lambda ()
                                 (let gloop ((j 0))
                                   (if (fx< j 16)
                                       (begin
                                         (if (fx= (fxand j 3) 3) (fiber-yield))
                                         (perform yield j)
                                         (gloop (fx+ j 1))))))))
                           (ms (with-handler
                                 ((eff-choose (k)
                                    (append (resume-multishot k 1)
                                            (resume-multishot k 2)))
                                  (return: (x) (list x)))
                                 (let ((a (perform eff-choose)))
                                   (fiber-yield)
                                   (fx+ a (perform eff-choose))))))
                       (let sumloop ((s2 0))
                         (let ((v (g)))
                           (if (eof-object? v)
                               (if (and (fx= s1 16)
                                        (fx= s2 120)
                                        (equal? ms '(2 3 3 4)))
                                   (atomic-fxbox+/fetch! ok 1))
                               (sumloop (fx+ s2 v)))))))
                   n)
                  (loop (fx+ i 1)))))))))
   workers: p)
  (test-equal n-fibers (atomic-fxbox-ref ok)))

;; 14k. Post-serial-phase steal-cascade wakeup regression:
;;      All W-1 peer carriers genuinely park in OS futex/ulock during a 30ms
;;      serial pause, then 1 worker bursts W*8 CPU-bound tasks into its local
;;      deque. Verifies steal-cascade wakes peers instead of stalling at 2/W.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (n-tasks (fx* w 8))
       (seen (let ((v (make-vector w #f)))
               (let loop ((i 0))
                 (if (fx< i w)
                     (begin (vector-set! v i (make-atomic-fxbox 0))
                            (loop (fx+ i 1)))))
               v))
       (done (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     ;; Let peer carriers spin out and park in OS futex/ulock
     (thread-sleep! 0.03)
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i n-tasks)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let ((wid (fiber-carrier-wid)))
                     (if (and wid (fx>= wid 0) (fx< wid w))
                         (atomic-fxbox-set! (vector-ref seen wid) 1)))
                   ;; Brief CPU burn so steals fan out across all woken carriers
                   (let spin ((k 0) (acc 0))
                     (if (fx< k 60000)
                         (spin (fx+ k 1) (fx+ acc (fxand k 7)))
                         (if (fx>= acc 0)
                             (atomic-fxbox+/fetch! done 1)))))
                 n)
                (loop (fx+ i 1))))))))
   workers: w)
  (test-equal n-tasks (atomic-fxbox-ref done))
  (let ((awake-wids
         (let loop ((i 0) (c 0))
           (if (fx< i w)
               (loop (fx+ i 1)
                     (fx+ c (atomic-fxbox-ref (vector-ref seen i))))
               c))))
    ;; On p>=4, steal cascade MUST wake >2 carriers (proving no 2/W stall!)
    (if (fx>= p 4)
        (test-assert (fx>= awake-wids (min w 3)))
        (test-assert (fx>= awake-wids 1)))))

;; 14l. Global-queue overflow cascade wakeup regression after serial park:
;;      Channel-woken burst lands in global-q while peers are parked; verifies
;;      global-pop cascade wakes parked peers and completes 100% of tasks.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (n-waiters (fx* w 6))
       (done (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (let ((ch (make-fiber-channel n-waiters)))
       (with-nursery
        (lambda (n)
          (let loop ((i 0))
            (if (fx< i n-waiters)
                (begin
                  (fiber-spawn
                   (lambda ()
                     (let ((v (fiber-recv! ch)))
                       (let spin ((k 0) (acc v))
                         (if (fx< k 15000)
                             (spin (fx+ k 1) (fx+ acc 1))
                             (if (fx>= acc 0)
                                 (atomic-fxbox+/fetch! done 1))))))
                   n)
                  (loop (fx+ i 1)))))
          ;; Wait for all waiters to block and peer carriers to park
          (thread-sleep! 0.03)
          ;; Unblock all waiters in one burst (queues wakeups into global/local)
          (let sloop ((i 0))
            (if (fx< i n-waiters)
                (begin (fiber-send! ch i) (sloop (fx+ i 1)))))))))
   workers: w)
  (test-equal n-waiters (atomic-fxbox-ref done)))

;; 14m. Lock-free per-carrier TLS (fiber-carrier-tls / fiber-carrier-tls-set!):
;;      Verifies #f outside run-fibers, strict per-carrier ownership isolation
;;      across thousands of cross-carrier fiber yields, and 0 cross-carrier clobber.
(test-equal #f (fiber-carrier-tls))
(test-equal #f (fiber-carrier-wid))
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (n-fibers (fx* w 32))
       (ok-reads (make-atomic-fxbox 0))
       (bad-reads (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i n-fibers)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let step ((j 0))
                     (if (fx< j 40)
                         (let* ((wid (fiber-carrier-wid))
                                (cur (fiber-carrier-tls)))
                           (if (not cur)
                               (let ((slot (cons wid (make-vector 4 wid))))
                                 (fiber-carrier-tls-set! slot)
                                 (set! cur slot)))
                           (if (and (pair? cur)
                                    (fx= (car cur) wid)
                                    (fx= (vector-ref (cdr cur) 3) wid))
                               (atomic-fxbox+/fetch! ok-reads 1)
                               (atomic-fxbox+/fetch! bad-reads 1))
                           (fiber-yield)
                           (step (fx+ j 1))))))
                 n)
                (loop (fx+ i 1))))))))
   workers: w)
  (test-equal (fx* n-fibers 40) (atomic-fxbox-ref ok-reads))
  (test-equal 0 (atomic-fxbox-ref bad-reads))
  (test-equal #f (fiber-carrier-tls)))

;; 14n. Adaptive-P multi-fiber allocation churn + explicit GC packed-ulock
;;      STW barrier & active young-nursery contraction regression.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (n-fibers (fx* w 16))
       (done (make-atomic-fxbox 0)))
  (run-fibers
   (lambda ()
     (with-nursery
      (lambda (n)
        (let loop ((i 0))
          (if (fx< i n-fibers)
              (begin
                (fiber-spawn
                 (lambda ()
                   (let iter ((k 0) (acc 0))
                     (if (fx< k 120)
                         (let ((v (make-vector 256 k)))
                           (if (and (fx= i 0) (fx= (fxand k 15) 15)) (##gc))
                           (if (fx= (fxand k 7) 7) (fiber-yield))
                           (iter (fx+ k 1) (fx+ acc (vector-ref v 0) (vector-ref v 255))))
                         (if (fx= acc (fx* 120 119))
                             (atomic-fxbox+/fetch! done 1)))))
                 n)
                (loop (fx+ i 1))))))))
   workers: w)
  (##gc)
  (test-equal n-fibers (atomic-fxbox-ref done)))

;; External OS-thread <-> fiber-scheduler bidirectional channel bridge
;; (buffered cap=4 and unbuffered cap=0): verifies %fk-sched wakeup routing
;; from non-carrier OS threads with zero crashes and exact conservation.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 8 p)))
       (n-msgs 200)
       (expected-sum (fxquotient (fx* n-msgs (fx- n-msgs 1)) 2)))
  (for-each
   (lambda (cap)
     (let ((to-fiber (make-fiber-channel cap))
           (to-os (make-fiber-channel cap)))
       (let ((os-sender
              (thread-start!
               (make-thread
                (lambda ()
                  (thread-sleep! 0.01)
                  (let loop ((i 0))
                    (if (fx< i n-msgs)
                        (begin
                          (fiber-send! to-fiber i)
                          (loop (fx+ i 1)))))
                  (fiber-channel-close! to-fiber)))))
             (os-receiver
              (thread-start!
               (make-thread
                (lambda ()
                  (let loop ((acc 0))
                    (let ((v (fiber-recv! to-os)))
                      (if (eof-object? v)
                          acc
                          (loop (fx+ acc v))))))))))
         (run-fibers
          (lambda ()
            (with-nursery
             (lambda (n)
               (let cloop ((k 0))
                 (if (fx< k 2)
                     (begin
                       (fiber-spawn
                        (lambda ()
                          (let rloop ()
                            (let ((v (fiber-recv! to-fiber)))
                              (if (not (eof-object? v))
                                  (begin
                                    (fiber-send! to-os v)
                                    (rloop))))))
                        n)
                       (cloop (fx+ k 1))))))))
          workers: w)
         (fiber-channel-close! to-os)
         (thread-join! os-sender)
         (test-equal expected-sum (thread-join! os-receiver)))))
   '(4 0)))

;; Cross-scheduler (sched-A <-> sched-B) channel bridge: two independent
;; run-fibers pools communicating across buffered & unbuffered channels
;; must route wakeups to each fiber's owning %fk-sched without corrupting
;; either scheduler's quiescence counters.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 6 (fxmax 2 (fxquotient p 2)))))
       (n-req 250)
       (expected-sum (fx* 2 (fxquotient (fx* n-req (fx- n-req 1)) 2))))
  (for-each
   (lambda (cap)
     (let ((req (make-fiber-channel cap))
           (rep (make-fiber-channel cap)))
       (let ((tA (thread-start!
                  (make-thread
                   (lambda ()
                     (run-fibers
                      (lambda ()
                        (let loop ((i 0) (s 0))
                          (if (fx< i n-req)
                              (begin
                                (fiber-send! req i)
                                (loop (fx+ i 1) (fx+ s (fiber-recv! rep))))
                              (begin
                                (fiber-channel-close! req)
                                s))))
                      workers: w)))))
             (tB (thread-start!
                  (make-thread
                   (lambda ()
                     (run-fibers
                      (lambda ()
                        (let loop ((cnt 0))
                          (let ((v (fiber-recv! req)))
                            (if (eof-object? v)
                                cnt
                                (begin
                                  (fiber-send! rep (fx* v 2))
                                  (loop (fx+ cnt 1)))))))
                      workers: w))))))
         (test-equal expected-sum (thread-join! tA))
         (test-equal n-req (thread-join! tB)))))
   '(4 0)))

;; Non-blocking fiber-try-send! / fiber-try-recv! + fiber-channel-close!
;; drain ordering, idempotence, and post-close send rejection.
(let ((ch (make-fiber-channel 2)))
  (test-equal #f (fiber-channel-closed? ch))
  (test-equal 'empty (fiber-try-recv! ch 'empty))
  (test-equal #t (fiber-try-send! ch 'a))
  (test-equal #t (fiber-try-send! ch 'b))
  (test-equal #f (fiber-try-send! ch 'c))
  (fiber-channel-close! ch)
  (fiber-channel-close! ch) ;; idempotent close
  (test-equal #t (fiber-channel-closed? ch))
  (test-equal #t (with-exception-catcher (lambda (e) #t) (lambda () (fiber-send! ch 'x) #f)))
  (test-equal #t (with-exception-catcher (lambda (e) #t) (lambda () (fiber-try-send! ch 'x) #f)))
  (test-equal 'a (fiber-try-recv! ch 'empty))
  (test-equal 'b (fiber-try-recv! ch 'empty))
  (test-equal #!eof (fiber-try-recv! ch 'empty))
  (test-equal #!eof (fiber-recv! ch)))

;; Concurrent channel close linearizability and waiter wakeup stress:
;; N receivers + N senders racing against concurrent fiber-channel-close!
;; across cap in {0, 1, 2, 4, 8} with GC; verifies zero lost wakeups,
;; exact item conservation for all successful sends, and clean termination.
(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (n-peers (max 4 (min 12 p)))
       (rounds 20)
       (ok-rounds 0))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let* ((cap (vector-ref '#(0 1 2 4 8) (fxmodulo r 5)))
               (ch (make-fiber-channel cap))
               (sent-cnt (make-atomic-fxbox 0))
               (recv-cnt (make-atomic-fxbox 0))
               (err-cnt (make-atomic-fxbox 0))
               (rx-done (make-atomic-fxbox 0))
               (tx-done (make-atomic-fxbox 0)))
          (run-fibers
           (lambda ()
             (with-nursery
              (lambda (n)
                ;; Receivers loop until #!eof
                (let cloop ((i 0))
                  (if (fx< i n-peers)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (let lp ()
                             (let ((v (fiber-recv! ch)))
                               (if (eof-object? v)
                                   (atomic-fxbox+/fetch! rx-done 1)
                                   (begin
                                     (atomic-fxbox+/fetch! recv-cnt 1)
                                     (lp))))))
                         n)
                        (cloop (fx+ i 1)))))
                ;; Senders push until closed exception
                (let sloop ((i 0))
                  (if (fx< i n-peers)
                      (begin
                        (fiber-spawn
                         (lambda ()
                           (with-exception-catcher
                            (lambda (e)
                              (atomic-fxbox+/fetch! err-cnt 1)
                              (atomic-fxbox+/fetch! tx-done 1))
                            (lambda ()
                              (let lp ((k 0))
                                (if (fx< k 80)
                                    (begin
                                      (fiber-send! ch k)
                                      (atomic-fxbox+/fetch! sent-cnt 1)
                                      (if (fx= (fxand k 15) 15) (fiber-yield))
                                      (lp (fx+ k 1)))
                                    (atomic-fxbox+/fetch! tx-done 1))))))
                         n)
                        (sloop (fx+ i 1)))))
                ;; Closer races concurrently after brief yield
                (fiber-spawn
                 (lambda ()
                   (let y ((k 0))
                     (if (fx< k (fx+ 2 (fxmodulo r 5)))
                         (begin (fiber-yield) (y (fx+ k 1)))))
                   (if (fx= (fxand r 7) 7) (##gc))
                   (fiber-channel-close! ch))
                 n))))
           workers: w)
          (if (and (fx= (atomic-fxbox-ref rx-done) n-peers)
                   (fx= (atomic-fxbox-ref tx-done) n-peers)
                   (fx= (atomic-fxbox-ref sent-cnt) (atomic-fxbox-ref recv-cnt)))
              (set! ok-rounds (fx+ ok-rounds 1)))
          (rloop (fx+ r 1)))))
  (test-equal rounds ok-rounds))

;;;============================================================================
