;;;============================================================================

;;; File: "test.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit parallel) unit tests: Chase-Lev deque, futures, fork-join combinators

(import (gambit parallel))
(import (_test))

;; Chase-Lev deque sequential LIFO/FIFO + dynamic resize wraparound
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

;; Pool + nested recursive futures + exception propagation + parallel combinators
(let ((pool (make-work-stealing-pool)))
  (test-assert (work-stealing-pool? pool))
  (parameterize ((current-work-stealing-pool pool))
    (let ((f1 (future (+ 20 22))))
      (test-assert (future? f1))
      (test-equal 42 (future-force f1))
      (test-assert (future-ready? f1)))

    ;; Nested recursive future (zero deadlock even on 1 core!)
    (letrec ((pfib (lambda (n)
                     (if (<= n 12)
                         (let seq ((k n))
                           (if (< k 2) k (+ (seq (- k 1)) (seq (- k 2)))))
                         (let ((r (future (pfib (- n 2)))))
                           (+ (pfib (- n 1)) (future-force r)))))))
      (test-equal 6765 (pfib 20)))

    ;; Exception propagation
    (let ((bad (future (error "boom-future" 77))))
      (test-error-tail error-exception? (future-force bad)))

    ;; parallel-map / parallel-vector-map / parallel-reduce
    (let* ((xs (let loop ((i 0) (acc '()))
                 (if (= i 200) (reverse acc) (loop (+ i 1) (cons i acc)))))
           (sq (parallel-map (lambda (x) (* x x)) xs 16)))
      (test-equal (map (lambda (x) (* x x)) xs) sq)
      (test-equal (apply + sq) (parallel-reduce + 0 sq 16))))
  (work-stealing-pool-shutdown! pool))

;;;============================================================================
