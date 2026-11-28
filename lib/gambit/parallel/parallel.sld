;;;============================================================================

;;; File: "parallel.sld"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Weak-Memory-Verified Chase-Lev Work-Stealing Deque & Parallel Stdlib

(define-library (gambit parallel)
  (export
   ;; Chase-Lev Work-Stealing Deque (Le et al. PPoPP 2013)
   make-work-stealing-deque
   work-stealing-deque?
   deque-push-bottom!
   deque-pop-bottom!
   deque-steal!
   deque-empty?
   deque-size-approx

   ;; Work-Stealing Pool
   make-work-stealing-pool
   work-stealing-pool?
   work-stealing-pool-worker-count
   work-stealing-pool-shutdown!
   current-work-stealing-pool

   ;; Futures (with work-stealing helping & exception propagation)
   future
   make-future
   future?
   future-ready?
   future-force
   force-future

   ;; Structured Fork-Join Combinators
   parallel-map
   parallel-for-each
   parallel-vector-map
   parallel-reduce)

  (import (srfi 226)
          (srfi 230))
  (begin
    (##define-syntax future
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms) (##pair? (##cdr forms)))
              (##list 'gambit/parallel#make-future
                      (##cons 'lambda (##cons '() (##cdr forms))))
              (##raise-expression-parsing-exception 'ill-formed-special-form src))))))
  (include "parallel.scm"))

;;;============================================================================
