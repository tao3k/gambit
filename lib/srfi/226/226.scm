;;;============================================================================

;;; File: "226.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 226, Control Features (Native Runtime Fast Path)
;;;
;;; Modularized by subsystem namespace while compiled as a single `(block)`
;;; unit so cross-subsystem fast paths inline with zero dynamic-dispatch tax:
;;;   - state.scm  (srfi/226/state#)  prompt tags, mc/tc structs, C23 atomics, reclaim
;;;   - unwind.scm (srfi/226/unwind#) scope-bound exception unwind trampoline
;;;   - prompt.scm (srfi/226/prompt#) prompts, transactional abort, barriers
;;;   - cont.scm   (srfi/226/cont#)   composable, non-composable & one-shot conts
;;;   - marks.scm  (srfi/226/marks#)  O(1) tail-preserving marks & cont inspection

(##supply-module srfi/226)

(##namespace ("srfi/226#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  dynamic-wind
  error))
(##include "226#.scm")
(##include "_internal#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (block)
  (not safe)
  (inlining-limit 400))

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

(##include "state.scm")
(##include "unwind.scm")
(##include "prompt.scm")
(##include "cont.scm")
(##include "marks.scm")

;;;============================================================================
