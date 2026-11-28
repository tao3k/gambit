;;;============================================================================

;;; File: "effect.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit effect) — Direct-Style Algebraic Effect Handlers
;;;
;;; Modularized by subsystem namespace while compiled as a single `(block)`
;;; unit so cross-subsystem fast paths inline with zero dynamic-dispatch tax:
;;;   - types.scm      (gambit/effect/types#)      types, C23 atomics, direct return
;;;   - handler.scm    (gambit/effect/handler#)    tail & suspending handlers, perform
;;;   - resume.scm     (gambit/effect/resume#)     one-shot & multi-shot resumption
;;;   - capability.scm (gambit/effect/capability#) O(1) lexical capability handles
;;;   - generator.scm  (gambit/effect/generator#)  symmetric 4-state generators

(##supply-module gambit/effect)

(##namespace ("gambit/effect#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  with-exception-catcher
  raise
  error))
(##include "~~lib/srfi/226/226#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "effect#.scm")
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

(##include "types.scm")
(##include "handler.scm")
(##include "resume.scm")
(##include "capability.scm")
(##include "generator.scm")

;;;============================================================================
