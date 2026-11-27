;;;============================================================================

;;; File: "parallel#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Weak-Memory-Verified Chase-Lev Work-Stealing Deque & Parallel Stdlib

(##namespace ("gambit/parallel#"

make-work-stealing-deque
work-stealing-deque?
deque-push-bottom!
deque-pop-bottom!
deque-steal!
deque-empty?
deque-size-approx

make-work-stealing-pool
work-stealing-pool?
work-stealing-pool-worker-count
work-stealing-pool-shutdown!
current-work-stealing-pool

future
make-future
future?
future-ready?
future-force
force-future

parallel-map
parallel-for-each
parallel-vector-map
parallel-reduce

))

(##define-syntax future
  (lambda (src)
    (let ((forms (##source-code src)))
      (if (and (##pair? forms) (##pair? (##cdr forms)))
          (##list 'gambit/parallel#make-future
                  (##cons 'lambda (##cons '() (##cdr forms))))
          (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

;;;============================================================================
