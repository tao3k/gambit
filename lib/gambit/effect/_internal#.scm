;;;============================================================================

;;; File: "_internal#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Internal subsystem namespace bindings for `(gambit effect)`.
;;; Included once in `effect.scm` so every subsystem submodule shares a single
;;; `(block)` compilation unit while retaining explicit namespace ownership.

(##namespace ("gambit/effect/types#"
  %tc-fast
  %st-mc
  %st-mc-set!
  %st-marks
  %st-marks-set!
  %st-barriers
  %st-barriers-set!
  %st-handlers
  %st-handlers-set!
  %st-rewind-frame
  %st-rewind-frame-set!
  %pf-kind
  %pf-tag
  %pf-handler
  %pf-handler-set!
  %pf-escape-k
  %pf-escape-k-set!
  %pf-marks
  %pf-marks-set!
  %pf-barriers
  %pf-barriers-set!
  %pf-handlers
  %pf-handlers-set!
  %pf-eh-scope
  %pf-eh-scope-set!
  %pf-unwind-hook
  %pf-unwind-hook-set!
  %EC-ONE-SHOT-LIVE
  %EC-ONE-SHOT-CONSUMED
  %EC-MULTISHOT-COW
  %GEN-INIT
  %GEN-RUNNING
  %GEN-SUSPENDED
  %GEN-DONE
  %ABSENT
  %make-effect
  %handler-entry
  %handler-entry?
  %entry-effect
  %entry-kind
  %entry-proc
  %handler-frame
  %make-handler-frame
  %handler-frame?
  %frame-tag
  %frame-entries
  %make-effect-continuation
  %ec-sub-k
  %ec-sub-k-set!
  %ec-pframe
  %ec-pframe-set!
  %ec-prefix
  %ec-marks
  %ec-handlers
  %ec-frame
  %ec-frame-set!
  %ec-state
  %generator
  %make-gen-raw
  %generator?
  %gen-state
  %gen-state-set!
  %gen-sub-k
  %gen-sub-k-set!
  %gen-pframe
  %gen-pframe-set!
  %gen-frame
  %gen-mc-cell
  %gen-mc-cell-set!
  %gen-h-cell
  %gen-h-cell-set!
  %gen-thunk
  %gen-thunk-set!
  %gen-unwind-fn
  %gen-unwind-fn-set!
  %make-capability
  %cap-kind
  %cap-proc
  %cap-frame
  %make-ec-state
  %ec-cas-state!
  %make-gen-state
  %gen-cas-state!
  %gen-state-store-rel!
  %return-oneshot-same-denv!))

(##namespace ("gambit/effect/handler#"
  %entries-all-tail?
  %find-entry-in-frame
  %handlers-prefix-before
  %install-handler-cont!
  %install-handler-cont-scoped!
  %perform-fast-cap-0!
  %perform-fast-cap-1!
  %perform-fast-cap-n!
  %perform-suspend-dispatch))

(##namespace ("gambit/effect/resume#"
  %freeze-ec!
  %resume-nontail-oneshot-cont!
  %resume-nontail-oneshot!
  %tail-resume-dispatch!
  %resume-checked-1!
  %resume-checked))

(##namespace ("gambit/effect/capability#"
  %install-cap-cont!
  %install-cap-cont-scoped!))

(##namespace ("gambit/effect/generator#"
  %gen-yield-swap-cont!
  %gen-yield-slow-handler
  %gen-install-pframe!
  %gen-finish!
  %gen-start-cont!
  %gen-start-cont-scoped!
  %gen-resume-swap-cont!))

;;;============================================================================
