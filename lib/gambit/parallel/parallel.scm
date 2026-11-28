;;;============================================================================

;;; File: "parallel.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit parallel) — Weak-Memory-Safe Chase-Lev Work-Stealing Deque &
;;; Structured Fork-Join Parallel Stdlib.
;;;
;;; Modularized by subsystem namespace while compiled as a single `(block)`
;;; unit so cross-subsystem fast paths inline with zero dynamic-dispatch tax:
;;;   - atomics.scm     (gambit/parallel/atomics#)     128B-padded atomics & slot ops
;;;   - deque.scm       (gambit/parallel/deque#)       Chase-Lev deque (PPoPP 2013)
;;;   - pool.scm        (gambit/parallel/pool#)        work-stealing pool & shutdown
;;;   - future.scm      (gambit/parallel/future#)      SATB-safe futures & helping
;;;   - combinators.scm (gambit/parallel/combinators#) parallel-map/for-each/reduce

(##supply-module gambit/parallel)

(##namespace ("gambit/parallel#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##include "~~lib/srfi/226/226#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##namespace (""
              make-mutex mutex-lock! mutex-unlock!
              make-condition-variable condition-variable-signal! condition-variable-broadcast!
              make-thread thread-start! thread-join! thread-yield!
              make-parameter parameterize dynamic-wind with-exception-catcher raise error))

(##include "parallel#.scm")
(##include "_internal#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (inlining-limit 400)
  (block))

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

(##include "atomics.scm")
(##include "deque.scm")
(##include "pool.scm")
(##include "future.scm")
(##include "combinators.scm")

;;;============================================================================
