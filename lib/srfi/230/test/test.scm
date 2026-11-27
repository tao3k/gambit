;;;============================================================================

;;; File: "test.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 230, Atomic Operations conformance tests

(import (srfi 230))
(import (_test))

;;; Memory orders

(test-assert (memory-order? (memory-order relaxed)))
(test-assert (memory-order? (memory-order acquire)))
(test-assert (memory-order? (memory-order release)))
(test-assert (memory-order? (memory-order acquire-release)))
(test-assert (memory-order? (memory-order sequentially-consistent)))
(test-assert (not (memory-order? 'invalid)))
(test-assert (not (memory-order? 42)))

(atomic-fence (memory-order relaxed))
(atomic-fence (memory-order acquire))
(atomic-fence (memory-order release))
(atomic-fence (memory-order acquire-release))
(atomic-fence (memory-order sequentially-consistent))

;;; Disjointness & atomic-flag

(let ((fl (make-atomic-flag))
      (bx (make-atomic-box 'a))
      (fx (make-atomic-fxbox 10))
      (pr (make-atomic-pair 'x 'y)))
  (test-assert (atomic-flag? fl))
  (test-assert (not (atomic-box? fl)))
  (test-assert (not (atomic-fxbox? fl)))
  (test-assert (not (atomic-pair? fl)))

  (test-assert (atomic-box? bx))
  (test-assert (not (atomic-flag? bx)))
  (test-assert (not (atomic-fxbox? bx)))
  (test-assert (not (atomic-pair? bx)))

  (test-assert (atomic-fxbox? fx))
  (test-assert (not (atomic-flag? fx)))
  (test-assert (not (atomic-box? fx)))
  (test-assert (not (atomic-pair? fx)))

  (test-assert (atomic-pair? pr))
  (test-assert (not (atomic-flag? pr)))
  (test-assert (not (atomic-box? pr)))
  (test-assert (not (atomic-fxbox? pr)))

  ;; atomic-flag ops
  (test-equal #f (atomic-flag-test-and-set! fl))
  (test-equal #t (atomic-flag-test-and-set! fl (memory-order acquire-release)))
  (atomic-flag-clear! fl (memory-order release))
  (test-equal #f (atomic-flag-test-and-set! fl))

  ;; atomic-box ops
  (test-equal 'a (atomic-box-ref bx))
  (atomic-box-set! bx 'b (memory-order release))
  (test-equal 'b (atomic-box-ref bx (memory-order acquire)))
  (test-equal 'b (atomic-box-swap! bx 'c))
  (test-equal 'c (atomic-box-compare-and-swap! bx 'wrong 'd))
  (test-equal 'c (atomic-box-ref bx))
  (test-equal 'c (atomic-box-compare-and-swap! bx 'c 'd))
  (test-equal 'd (atomic-box-ref bx))

  ;; atomic-fxbox ops
  (test-equal 10 (atomic-fxbox-ref fx))
  (atomic-fxbox-set! fx 20 (memory-order relaxed))
  (test-equal 20 (atomic-fxbox-swap! fx 30))
  (test-equal 30 (atomic-fxbox-compare-and-swap! fx 99 40))
  (test-equal 30 (atomic-fxbox-compare-and-swap! fx 30 40))
  (test-equal 40 (atomic-fxbox-fetch-add! fx 5))
  (test-equal 45 (atomic-fxbox-fetch-sub! fx 15))
  (test-equal 30 (atomic-fxbox-ref fx))
  (test-equal 30 (atomic-fxbox-fetch-and! fx #b10110))
  (test-equal 22 (atomic-fxbox-fetch-ior! fx #b01001))
  (test-equal 31 (atomic-fxbox-fetch-xor! fx #b11111))
  (test-equal 0 (atomic-fxbox-ref fx))

  ;; atomic-pair ops
  (call-with-values (lambda () (atomic-pair-ref pr))
    (lambda (a b) (test-equal 'x a) (test-equal 'y b)))
  (atomic-pair-set! pr 'p 'q)
  (call-with-values (lambda () (atomic-pair-swap! pr 'r 's))
    (lambda (a b) (test-equal 'p a) (test-equal 'q b)))
  (call-with-values (lambda () (atomic-pair-compare-and-swap! pr 'r 'wrong 'u 'v))
    (lambda (a b) (test-equal 'r a) (test-equal 's b)))
  (call-with-values (lambda () (atomic-pair-compare-and-swap! pr 'r 's 'u 'v))
    (lambda (a b) (test-equal 'r a) (test-equal 's b)))
  (call-with-values (lambda () (atomic-pair-ref pr))
    (lambda (a b) (test-equal 'u a) (test-equal 'v b))))

;;;============================================================================
