;;;============================================================================

;;; File: "test.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit parallel) Unit & CPU-Adaptive Adversarial Concurrency Tests:
;;;   1. Sequential Chase-Lev deque LIFO/FIFO + dynamic resize wraparound
;;;   2. Adaptive-P concurrent Chase-Lev push/pop/steal + dynamic grow linearizability
;;;   3. Post-idle Dekker park -> steal-cascade wakeup regression
;;;   4. Adaptive-P concurrent future-force race (single-run & exception broadcast)
;;;   5. Structured fork-join exception quiescence (map, for-each, reduce)
;;;   6. Adaptive-P heavy fork-join + concurrent GC + repeated pool lifecycle

(import (gambit parallel))
(import (srfi 226))
(import (srfi 230))
(import (gambit effect))
(import (_test))

(define (raises-error? thunk)
  (with-exception-catcher
   (lambda (e) #t)
   (lambda () (thunk) #f)))

;;;============================================================================
;;; 1. Chase-Lev Deque Sequential LIFO/FIFO + Dynamic Resize Wraparound

(let ((q (make-work-stealing-deque 4)))
  (test-assert (work-stealing-deque? q))
  (test-assert (deque-empty? q))
  (test-equal 'empty (deque-pop-bottom! q 'empty))
  (test-equal 'empty (deque-steal! q 'empty 'abort))

  ;; Push 3, steal 1 (top=1, bot=3), then push 20 more forcing resizes 4->8->16->32!
  (deque-push-bottom! q 10)
  (deque-push-bottom! q 20)
  (deque-push-bottom! q 30)
  (test-equal 10 (deque-steal! q 'empty 'abort))
  (let push ((i 0))
    (if (< i 20)
        (begin (deque-push-bottom! q (+ 100 i)) (push (+ i 1)))))
  (test-equal 119 (deque-pop-bottom! q 'empty))
  (test-equal 20 (deque-steal! q 'empty 'abort))
  (test-equal 30 (deque-steal! q 'empty 'abort))
  (let drain ((expect 100))
    (if (< expect 119)
        (begin
          (test-equal expect (deque-steal! q 'empty 'abort))
          (drain (+ expect 1)))))
  (test-assert (deque-empty? q))
  (test-equal 'empty (deque-pop-bottom! q 'empty)))

;;;============================================================================
;;; 2. Adaptive-P Concurrent Chase-Lev Owner Push/Pop vs. Thieves + Dynamic Grow

(let* ((p (##current-vm-processor-count))
       (n-thieves (max 2 (min 11 p)))
       (total-items 12000)
       (q (make-work-stealing-deque 4))
       (owner-done (make-atomic-fxbox 0))
       (stolen-count (make-atomic-fxbox 0))
       (stolen-sum (make-atomic-fxbox 0))
       (owner-count 0)
       (owner-sum 0)
       (expected-sum (quotient (* total-items (+ total-items 1)) 2))
       (thieves
        (let loop ((t 0) (acc '()))
          (if (= t n-thieves)
              acc
              (loop (+ t 1)
                    (cons
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (let sloop ((cnt 0) (s 0))
                           (let ((v (deque-steal! q 'empty 'abort)))
                             (cond
                               ((fixnum? v)
                                (sloop (+ cnt 1) (+ s v)))
                               ((eq? v 'abort)
                                (sloop cnt s))
                               ((and (= (atomic-fxbox-ref owner-done 'acquire) 1)
                                     (deque-empty? q))
                                (atomic-fxbox-fetch-add! stolen-count cnt)
                                (atomic-fxbox-fetch-add! stolen-sum s))
                               (else
                                (thread-yield!)
                                (sloop cnt s))))))))
                     acc))))))
  ;; Sole owner pushes 1..total-items (triggering resizes 4->8->...->4096)
  ;; while interleaving owner LIFO pops and periodic GC.
  (let ploop ((i 1))
    (if (<= i total-items)
        (begin
          (deque-push-bottom! q i)
          (if (= (bitwise-and i 3) 0)
              (let ((v (deque-pop-bottom! q 'empty)))
                (if (fixnum? v)
                    (begin
                      (set! owner-count (+ owner-count 1))
                      (set! owner-sum (+ owner-sum v))))))
          (if (= (bitwise-and i 2047) 2047) (##gc))
          (ploop (+ i 1)))))
  ;; Drain any remaining items from owner side
  (let dloop ()
    (let ((v (deque-pop-bottom! q 'empty)))
      (if (fixnum? v)
          (begin
            (set! owner-count (+ owner-count 1))
            (set! owner-sum (+ owner-sum v))
            (dloop)))))
  (atomic-fxbox-set! owner-done 1 'release)
  (for-each thread-join! thieves)
  (test-equal total-items (+ owner-count (atomic-fxbox-ref stolen-count)))
  (test-equal expected-sum (+ owner-sum (atomic-fxbox-ref stolen-sum))))

;;;============================================================================
;;; 3. Pool Basics, Nested Futures, Exceptions & Post-Idle Steal-Cascade Wakeup

(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (pool (make-work-stealing-pool w)))
  (test-assert (work-stealing-pool? pool))
  (test-equal w (work-stealing-pool-worker-count pool))
  (parameterize ((current-work-stealing-pool pool))
    (let ((f1 (future (+ 20 22))))
      (test-assert (future? f1))
      (test-equal 42 (future-force f1))
      (test-assert (future-ready? f1)))

    ;; Let all workers genuinely park via Dekker condvar wait, then burst a
    ;; nested fork-join tree to verify zero lost wakeups & steal cascade.
    (thread-sleep! 0.03)
    (letrec ((pfib (lambda (n)
                     (if (<= n 12)
                         (let seq ((k n))
                           (if (< k 2) k (+ (seq (- k 1)) (seq (- k 2)))))
                         (let ((r (future (pfib (- n 2)))))
                           (+ (pfib (- n 1)) (future-force r)))))))
      (test-equal 46368 (pfib 24)))

    ;; Exception propagation
    (let ((bad (future (error "boom-future" 77))))
      (test-error-tail error-exception? (future-force bad)))

    ;; parallel-map / parallel-vector-map / parallel-reduce / parallel-for-each
    (let* ((xs (let loop ((i 0) (acc '()))
                 (if (= i 200) (reverse acc) (loop (+ i 1) (cons i acc)))))
           (sq (parallel-map (lambda (x) (* x x)) xs 16))
           (fe-sum (make-atomic-fxbox 0)))
      (test-equal (map (lambda (x) (* x x)) xs) sq)
      (test-equal (apply + sq) (parallel-reduce + 0 sq 16))
      (parallel-for-each (lambda (x) (atomic-fxbox-fetch-add! fe-sum x)) sq 16)
      (test-equal (apply + sq) (atomic-fxbox-ref fe-sum))))
  (work-stealing-pool-shutdown! pool))

;;;============================================================================
;;; 4. Adaptive-P Concurrent future-force Race (Single-Run & Exception Broadcast)

(let* ((p (##current-vm-processor-count))
       (n-threads (max 4 (min 12 p)))
       (pool (make-work-stealing-pool n-threads)))
  (parameterize ((current-work-stealing-pool pool))
    ;; 4a. Normal future forced concurrently by n-threads across 25 rounds:
    ;;     thunk MUST execute strictly once and every waiter observes exact value.
    (let rloop ((r 0))
      (if (< r 25)
          (let* ((runs (make-atomic-fxbox 0))
                 (go (make-atomic-fxbox 0))
                 (ok (make-atomic-fxbox 0))
                 (f (future
                     (begin
                       (atomic-fxbox-fetch-add! runs 1)
                       (let spin ((i 0) (a r))
                         (if (< i 2000) (spin (+ i 1) (+ a 1)) a)))))
                 (ts (let tloop ((i 0) (acc '()))
                       (if (= i n-threads)
                           acc
                           (tloop (+ i 1)
                                  (cons
                                   (thread-start!
                                    (make-thread
                                     (lambda ()
                                       (let w ()
                                         (if (= (atomic-fxbox-ref go 'acquire) 0)
                                             (begin (thread-yield!) (w))))
                                       (if (= (future-force f) (+ r 2000))
                                           (atomic-fxbox-fetch-add! ok 1)))))
                                   acc))))))
            (atomic-fxbox-set! go 1 'release)
            (for-each thread-join! ts)
            (test-equal 1 (atomic-fxbox-ref runs))
            (test-equal n-threads (atomic-fxbox-ref ok))
            (rloop (+ r 1)))))

    ;; 4b. Failing future forced concurrently by n-threads across 15 rounds:
    ;;     thunk MUST execute strictly once and ALL waiters receive the exception.
    (let rloop ((r 0))
      (if (< r 15)
          (let* ((runs (make-atomic-fxbox 0))
                 (go (make-atomic-fxbox 0))
                 (caught (make-atomic-fxbox 0))
                 (f (future
                     (begin
                       (atomic-fxbox-fetch-add! runs 1)
                       (error "concurrent-future-boom" r))))
                 (ts (let tloop ((i 0) (acc '()))
                       (if (= i n-threads)
                           acc
                           (tloop (+ i 1)
                                  (cons
                                   (thread-start!
                                    (make-thread
                                     (lambda ()
                                       (let w ()
                                         (if (= (atomic-fxbox-ref go 'acquire) 0)
                                             (begin (thread-yield!) (w))))
                                       (if (raises-error? (lambda () (future-force f)))
                                           (atomic-fxbox-fetch-add! caught 1)))))
                                   acc))))))
            (atomic-fxbox-set! go 1 'release)
            (for-each thread-join! ts)
            (test-equal 1 (atomic-fxbox-ref runs))
            (test-equal n-threads (atomic-fxbox-ref caught))
            (rloop (+ r 1))))))
  (work-stealing-pool-shutdown! pool))

;;;============================================================================
;;; 5. Structured Fork-Join Exception Quiescence (Zero Orphaned Right Tasks)

(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (pool (make-work-stealing-pool w)))
  (parameterize ((current-work-stealing-pool pool))
    (let ((vec (let ((v (make-vector 64 0)))
                 (let loop ((i 0))
                   (if (< i 64) (begin (vector-set! v i i) (loop (+ i 1)))))
                 v)))
      ;; 5a. parallel-vector-map: left throws at idx=0 while right runs delay loop
      (let ((right-done (make-atomic-fxbox 0)))
        (test-equal #t
          (raises-error?
           (lambda ()
             (parallel-vector-map
              (lambda (x)
                (if (= x 0)
                    (error "left-vmap-boom")
                    (begin
                      (if (= x 63)
                          (begin
                            (let spin ((k 0) (a 0))
                              (if (< k 50000) (spin (+ k 1) (+ a 1))))
                            (atomic-fxbox-set! right-done 1 'release)))
                      x)))
              vec 16))))
        ;; Right child MUST already be finished before caller catches left's error!
        (test-equal 1 (atomic-fxbox-ref right-done 'acquire)))

      ;; 5b. parallel-for-each: left throws while right runs delay loop
      (let ((right-done (make-atomic-fxbox 0))
            (lst (vector->list vec)))
        (test-equal #t
          (raises-error?
           (lambda ()
             (parallel-for-each
              (lambda (x)
                (if (= x 0)
                    (error "left-fe-boom")
                    (if (= x 63)
                        (begin
                          (let spin ((k 0) (a 0))
                            (if (< k 50000) (spin (+ k 1) (+ a 1))))
                          (atomic-fxbox-set! right-done 1 'release)))))
              lst 16))))
        (test-equal 1 (atomic-fxbox-ref right-done 'acquire)))

      ;; 5c. parallel-reduce: left throws while right runs delay loop
      (let ((right-done (make-atomic-fxbox 0)))
        (test-equal #t
          (raises-error?
           (lambda ()
             (parallel-reduce
              (lambda (acc x)
                (if (= x 0)
                    (error "left-red-boom")
                    (begin
                      (if (= x 63)
                          (begin
                            (let spin ((k 0) (a 0))
                              (if (< k 50000) (spin (+ k 1) (+ a 1))))
                            (atomic-fxbox-set! right-done 1 'release)))
                      (+ acc x))))
              0 vec 16))))
        (test-equal 1 (atomic-fxbox-ref right-done 'acquire)))))
  (work-stealing-pool-shutdown! pool))

;;;============================================================================
;;; 6. Adaptive-P Heavy Fork-Join + Concurrent GC + Repeated Pool Lifecycle

(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p))))
  (let cycle ((c 0))
    (if (< c 4)
        (let ((pool (make-work-stealing-pool w)))
          (parameterize ((current-work-stealing-pool pool))
            (let* ((n (* w 512))
                   (vec (let ((v (make-vector n 0)))
                          (let loop ((i 0))
                            (if (< i n) (begin (vector-set! v i i) (loop (+ i 1)))))
                          v))
                   (mapped (parallel-vector-map
                            (lambda (x)
                              (if (= (bitwise-and x 255) 255) (##gc))
                              (+ (* x 2) 1))
                            vec 32))
                   (sum (parallel-reduce + 0 mapped 32))
                   (expected (* n n)))
              (test-equal expected sum)))
          (work-stealing-pool-shutdown! pool)
          (cycle (+ c 1))))))

;;;============================================================================
;;; Public API Argument Validation (Safe Error Reporting Without Crashes)

(test-equal #t (raises-error? (lambda () (deque-size-approx 123))))
(test-equal #t (raises-error? (lambda () (deque-empty? 123))))
(test-equal #t (raises-error? (lambda () (deque-push-bottom! 123 'x))))
(test-equal #t (raises-error? (lambda () (deque-pop-bottom! 123))))
(test-equal #t (raises-error? (lambda () (deque-steal! 123))))
(test-equal #t (raises-error? (lambda () (work-stealing-pool-worker-count 123))))
(test-equal #t (raises-error? (lambda () (work-stealing-pool-shutdown! 123))))
(test-equal #t (raises-error? (lambda () (make-future 123))))
(test-equal #t (raises-error? (lambda () (make-future (lambda () 1) 123))))
(test-equal #t (raises-error? (lambda () (future-ready? 123))))
(test-equal #t (raises-error? (lambda () (future-force 123))))
(test-equal #t (raises-error? (lambda () (parallel-vector-map 123 '#(1 2)))))
(test-equal #t (raises-error? (lambda () (parallel-vector-map (lambda (x) x) 123))))
(test-equal #t (raises-error? (lambda () (parallel-map 123 '(1 2)))))
(test-equal #t (raises-error? (lambda () (parallel-map (lambda (x) x) 123))))
(test-equal #t (raises-error? (lambda () (parallel-for-each 123 '(1 2)))))
(test-equal #t (raises-error? (lambda () (parallel-for-each (lambda (x) x) 123))))
(test-equal #t (raises-error? (lambda () (parallel-reduce 123 0 '#(1 2)))))
(test-equal #t (raises-error? (lambda () (parallel-reduce + 0 123))))

;;;============================================================================
;;; Zero-Leak Eager Thunk Clearing & SATB GC Stress on Futures

(let* ((p (##current-vm-processor-count))
       (w (max 2 (min 12 p)))
       (pool (make-work-stealing-pool w)))
  (parameterize ((current-work-stealing-pool pool))
    ;; Normal future must clear its thunk slot once forced
    (let* ((payload (make-vector 1024 7))
           (f (make-future (lambda () (vector-ref payload 512)) pool)))
      (test-equal 7 (future-force f))
      (test-equal #t (future-ready? f))
      (test-equal #f (##structure-ref f 2 (##structure-type f) #f)))
    ;; Failing future must also clear its thunk slot once forced
    (let* ((payload (make-vector 1024 9))
           (f (make-future (lambda () (error "thunk-clear-boom" (vector-ref payload 0))) pool)))
      (test-equal #t (raises-error? (lambda () (future-force f))))
      (test-equal #t (future-ready? f))
      (test-equal #f (##structure-ref f 2 (##structure-type f) #f)))
    ;; Concurrent future-force + SATB GC storm: every completed future clears thunk
    (let* ((n-futs (* w 40))
           (futs (make-vector n-futs #f))
           (bad-thunk (make-atomic-fxbox 0)))
      (let init ((i 0))
        (if (< i n-futs)
            (let ((buf (make-vector 64 i)))
              (vector-set! futs i (make-future (lambda () (vector-ref buf 32)) pool))
              (init (+ i 1)))))
      (let ((racers
             (let rloop ((t 0) (acc '()))
               (if (= t w)
                   acc
                   (rloop (+ t 1)
                          (cons
                           (thread-start!
                            (make-thread
                             (lambda ()
                               (let flp ((i 0))
                                 (if (< i n-futs)
                                     (let* ((f (vector-ref futs i))
                                            (v (future-force f)))
                                       (if (or (not (= v i))
                                               (not (eq? #f (##structure-ref f 2 (##structure-type f) #f))))
                                           (atomic-fxbox-fetch-add! bad-thunk 1))
                                       (if (and (= t 0) (= (bitwise-and i 31) 31))
                                           (##gc))
                                       (flp (+ i 1))))))))
                           acc))))))
        (for-each thread-join! racers))
      (test-equal 0 (atomic-fxbox-ref bad-thunk))))
  (work-stealing-pool-shutdown! pool))

;;;============================================================================
;;; Concurrent Idempotent Pool Shutdown & Post-Shutdown Future Safety

(let* ((p (##current-vm-processor-count))
       (n-callers (max 4 (min 12 p)))
       (rounds 8)
       (ok-rounds 0))
  (let rloop ((r 0))
    (if (< r rounds)
        (let* ((pool (make-work-stealing-pool (max 2 (min 8 p))))
               (go (make-atomic-fxbox 0))
               (done (make-atomic-fxbox 0)))
          ;; Submit active work right before concurrent multi-thread shutdown
          (let ((f-pre (make-future (lambda () (+ 100 r)) pool)))
            (let ((callers
                   (let cloop ((i 0) (acc '()))
                     (if (= i n-callers)
                         acc
                         (cloop (+ i 1)
                                (cons
                                 (thread-start!
                                  (make-thread
                                   (lambda ()
                                     (let w ()
                                       (if (= (atomic-fxbox-ref go 'acquire) 0)
                                           (begin (thread-yield!) (w))))
                                     (work-stealing-pool-shutdown! pool)
                                     (atomic-fxbox-fetch-add! done 1))))
                                 acc))))))
              (atomic-fxbox-set! go 1 'release)
              (for-each thread-join! callers))
            ;; Repeat shutdown after completion is also idempotent
            (work-stealing-pool-shutdown! pool)
            ;; Both pre-shutdown and post-shutdown futures still force cleanly
            (let ((f-post (make-future (lambda () (+ 200 r)) pool)))
              (if (and (= (atomic-fxbox-ref done) n-callers)
                       (= (future-force f-pre) (+ 100 r))
                       (= (future-force f-post) (+ 200 r)))
                  (set! ok-rounds (+ ok-rounds 1)))))
          (rloop (+ r 1)))))
  (test-equal rounds ok-rounds))

;;;============================================================================
;;; Proper-List Validation & Overflow-Safe Deque Capacity Guard

(let ((check-err
       (lambda (thunk)
         (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f)))))
  (test-equal #t (check-err (lambda () (parallel-map (lambda (x) x) '(1 . 2)))))
  (test-equal #t (check-err (lambda () (parallel-map (lambda (x) x) '(1 2 . 3)))))
  (test-equal #t (check-err (lambda () (parallel-for-each (lambda (x) x) '(1 . 2)))))
  (test-equal #t (check-err (lambda () (parallel-for-each (lambda (x) x) '(1 2 . 3)))))
  (test-equal #t (check-err (lambda () (parallel-reduce + 0 '(1 . 2)))))
  (test-equal #t (check-err (lambda () (parallel-reduce + 0 '(1 2 . 3)))))
  (let ((max-pow2
         (let lp ((x 1))
           (let ((y (##fxarithmetic-shift-left x 1)))
             (if (##fx<= y x) x (lp y))))))
    (test-equal #t (check-err (lambda () (make-work-stealing-deque (##fx+ max-pow2 1)))))))

;;;============================================================================
;;; Deadlock-Free Future Cycle Detection, Non-Local Escape Quiescence,
;;; Self-Shutdown Guard & Zero-Retention Last-Item Deque Pop

(let ()
  ;; 1. Direct & indirect self-reentrant future-force cycles raise immediately
  ;;    instead of spinning forever.
  (let* ((pool (make-work-stealing-pool 1)))
    (work-stealing-pool-shutdown! pool)
    ;; Direct cycle: f forces f
    (let ((f #f))
      (set! f (make-future (lambda () (future-force f)) pool))
      (test-equal #t (raises-error? (lambda () (future-force f))))
      (test-equal #t (future-ready? f)))
    ;; Indirect cycle: f1 forces f2 which forces f1
    (let ((f1 #f) (f2 #f))
      (set! f1 (make-future (lambda () (future-force f2)) pool))
      (set! f2 (make-future (lambda () (future-force f1)) pool))
      (test-equal #t (raises-error? (lambda () (future-force f1))))
      (test-equal #t (future-ready? f1))
      (test-equal #t (future-ready? f2))))

  ;; 2. Future body escaping via abort-current-continuation or call/1cc transitions
  ;;    the future cleanly to a ready error state so subsequent/peer forces never wedge.
  (let* ((pt (make-continuation-prompt-tag 'fut-abort-pt))
         (pool (make-work-stealing-pool 1)))
    (work-stealing-pool-shutdown! pool)
    (let ((f1 (make-future (lambda () (abort-current-continuation pt 'aborted-fut)) pool)))
      (test-equal 'aborted-fut
        (call-with-continuation-prompt (lambda () (future-force f1)) pt (lambda (v) v)))
      (test-equal #t (future-ready? f1))
      (test-equal #t (raises-error? (lambda () (future-force f1)))))
    (let ((f2 (make-future (lambda () (abort-current-continuation pt 'via-abort)) pool)))
      (test-equal 'via-1cc
        (call-with-continuation-prompt
         (lambda ()
           (call/1cc
            (lambda (exit)
              (let ((f3 (make-future (lambda () (exit 'via-1cc)) pool)))
                (future-force f3)))
            pt))
         pt))
      (test-equal 'via-abort
        (call-with-continuation-prompt (lambda () (future-force f2)) pt (lambda (v) v)))
      (test-equal #t (future-ready? f2)))
    ;; Outer suspending algebraic effect perform/resume inside a future completes cleanly.
    (let ((e-ask (make-effect 'fut-ask)))
      (let ((f4 (make-future (lambda () (+ 10 (perform e-ask 32))) pool)))
        (test-equal 42
          (with-handler ((e-ask (k v) (resume k v)))
            (future-force f4)))
        (test-equal #t (future-ready? f4))
        (test-equal 42 (future-force f4)))))

  ;; 3. Structured fork-join non-local escape quiescence: aborting out of the left
  ;;    branch of parallel-vector-map, parallel-for-each, and parallel-reduce joins
  ;;    the right future BEFORE the outer prompt handler runs (zero orphaned work).
  (let* ((p (##current-vm-processor-count))
         (w (max 2 (min 8 p)))
         (pool (make-work-stealing-pool w))
         (pt (make-continuation-prompt-tag 'fj-abort-pt))
         (vec (vector 0 1 2 3 4 5 6 7)))
    (parameterize ((current-work-stealing-pool pool))
      ;; parallel-vector-map
      (let ((right-done (make-atomic-fxbox 0))
            (saw-done #f))
        (test-equal 'vmap-ab
          (call-with-continuation-prompt
           (lambda ()
             (parallel-vector-map
              (lambda (x)
                (if (= x 0)
                    (abort-current-continuation pt 'vmap-ab)
                    (begin
                      (if (= x 7)
                          (begin
                            (let spin ((k 0) (a 0)) (if (< k 40000) (spin (+ k 1) (+ a 1))))
                            (atomic-fxbox-set! right-done 1 'release)))
                      x)))
              vec 2))
           pt
           (lambda (v)
             (set! saw-done (= (atomic-fxbox-ref right-done 'acquire) 1))
             v)))
        (test-equal #t saw-done))
      ;; parallel-for-each
      (let ((right-done (make-atomic-fxbox 0))
            (saw-done #f))
        (test-equal 'fe-ab
          (call-with-continuation-prompt
           (lambda ()
             (parallel-for-each
              (lambda (x)
                (if (= x 0)
                    (abort-current-continuation pt 'fe-ab)
                    (if (= x 7)
                        (begin
                          (let spin ((k 0) (a 0)) (if (< k 40000) (spin (+ k 1) (+ a 1))))
                          (atomic-fxbox-set! right-done 1 'release)))))
              (vector->list vec) 2))
           pt
           (lambda (v)
             (set! saw-done (= (atomic-fxbox-ref right-done 'acquire) 1))
             v)))
        (test-equal #t saw-done))
      ;; parallel-reduce
      (let ((right-done (make-atomic-fxbox 0))
            (saw-done #f))
        (test-equal 'red-ab
          (call-with-continuation-prompt
           (lambda ()
             (parallel-reduce
              (lambda (acc x)
                (if (= x 0)
                    (abort-current-continuation pt 'red-ab)
                    (begin
                      (if (= x 7)
                          (begin
                            (let spin ((k 0) (a 0)) (if (< k 40000) (spin (+ k 1) (+ a 1))))
                            (atomic-fxbox-set! right-done 1 'release)))
                      (+ acc x))))
              0 vec 2))
           pt
           (lambda (v)
             (set! saw-done (= (atomic-fxbox-ref right-done 'acquire) 1))
             v)))
        (test-equal #t saw-done)))
    (work-stealing-pool-shutdown! pool))

  ;; 4. Worker thread calling work-stealing-pool-shutdown! on its own pool raises
  ;;    a clean error instead of self-join deadlocking, leaving the pool healthy.
  (let* ((pool (make-work-stealing-pool 2))
         (f-self (make-future (lambda () (work-stealing-pool-shutdown! pool)) pool)))
    ;; Let a pool worker thread claim and execute f-self (even at p=1) before forcing.
    (let wait ()
      (if (not (future-ready? f-self))
          (begin (thread-yield!) (wait))))
    (test-equal #t (raises-error? (lambda () (future-force f-self))))
    ;; Pool remains completely usable after rejecting worker self-shutdown
    (test-equal 99 (future-force (make-future (lambda () 99) pool)))
    (work-stealing-pool-shutdown! pool))

  ;; 5. Zero-retention last-item Chase-Lev pop: popping the sole item (t == b)
  ;;    clears the backing vector slot to #f so large closures are never pinned.
  (let* ((q (make-work-stealing-deque 4))
         (sentinel (list 'zero-retention-sentinel)))
    (deque-push-bottom! q sentinel)
    (test-equal sentinel (deque-pop-bottom! q 'empty))
    (let* ((arr-box (##structure-ref q 3 (##structure-type q) #f))
           (vec (atomic-box-ref arr-box 'acquire)))
      (test-equal #f (vector-ref vec 0))))

  ;; 6. Adaptive-P SMP torture combining concurrent future aborts, fork-join aborts,
  ;;    self-cycle detection, and last-item deque pops with ##gc.
  (let* ((p (##current-vm-processor-count))
         (w (max 2 (min 8 p)))
         (pool (make-work-stealing-pool w))
         (ok (make-atomic-fxbox 0)))
    (let ((threads
           (let loop ((t 0) (acc '()))
             (if (= t w)
                 acc
                 (loop (+ t 1)
                       (cons
                        (thread-start!
                         (make-thread
                          (lambda ()
                            (parameterize ((current-work-stealing-pool pool))
                              (let ((pt (make-continuation-prompt-tag 'smp-fj-pt))
                                    (vec (vector 0 1 2 3 4 5 6 7)))
                                (let rloop ((r 0) (good #t))
                                  (if (< r 15)
                                      (let* ((rd (make-atomic-fxbox 0))
                                             (seen-rd #f)
                                             (v (call-with-continuation-prompt
                                                 (lambda ()
                                                   (parallel-vector-map
                                                    (lambda (x)
                                                      (if (= x 0)
                                                          (abort-current-continuation pt r)
                                                          (begin
                                                            (if (= x 7) (atomic-fxbox-set! rd 1 'release))
                                                            x)))
                                                    vec 2))
                                                 pt
                                                 (lambda (x)
                                                   (set! seen-rd (= (atomic-fxbox-ref rd 'acquire) 1))
                                                   x)))
                                             (q (make-work-stealing-deque 4))
                                             (s (cons r t)))
                                        (deque-push-bottom! q s)
                                        (let* ((popped (deque-pop-bottom! q 'empty))
                                               (ab (##structure-ref q 3 (##structure-type q) #f))
                                               (arr (atomic-box-ref ab 'acquire)))
                                          (if (and (= t 0) (= (bitwise-and r 3) 3)) (##gc))
                                          (rloop (+ r 1)
                                                 (and good
                                                      (= v r)
                                                      seen-rd
                                                      (eq? popped s)
                                                      (eq? (vector-ref arr 0) #f)))))
                                      (if good (atomic-fxbox-fetch-add! ok 1)))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal w (atomic-fxbox-ref ok)))
    (work-stealing-pool-shutdown! pool)))

;;;============================================================================
