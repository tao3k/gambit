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
(import (srfi 230))
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
