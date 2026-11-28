;;;============================================================================

;;; File: "_internal#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Internal subsystem namespace bindings for `(srfi 226)`.
;;; Included once in `226.scm` so every subsystem submodule shares a single
;;; `(block)` compilation unit while retaining explicit namespace ownership.

(##namespace ("srfi/226/state#"
  %CONT-ONE-SHOT-LIVE
  %CONT-ONE-SHOT-CONSUMED
  %CONT-MULTISHOT-COW
  %ABSENT
  %DEFAULT-PROMPT-HANDLER
  %FROZEN-DEFAULT-PROMPT-HANDLER
  %make-prompt-tag
  %prompt-tag-name
  %default-prompt-tag
  %mc-frame
  %mc-frame?
  %tc-state
  %make-tc-state
  %tc-state?
  %tc-eh-outer-denv
  %tc-eh-outer-denv-set!
  %tc-eh-outer-proc
  %tc-eh-outer-proc-set!
  %tc-eh-tramp-denv
  %tc-eh-tramp-denv-set!
  %tc-eh-tramp-proc
  %tc-eh-tramp-proc-set!
  %st-mc
  %st-mc-set!
  %st-marks
  %st-marks-set!
  %st-barriers
  %st-barriers-set!
  %st-handlers
  %st-handlers-set!
  %st-eh-outer-denv
  %st-eh-outer-denv-set!
  %st-eh-outer-proc
  %st-eh-outer-proc-set!
  %st-eh-tramp-denv
  %st-eh-tramp-denv-set!
  %st-eh-tramp-proc
  %st-eh-tramp-proc-set!
  %pf-kind
  %pf-tag
  %pf-handler
  %pf-handler-set!
  %pf-escape-k
  %pf-escape-k-set!
  %pf-marks
  %pf-barriers
  %pf-handlers
  %pf-eh-scope
  %pf-eh-scope-set!
  %pf-unwind-hook
  %pf-unwind-hook-set!
  %make-mark-set
  %mark-set-frames
  %one-shot-cell
  %make-one-shot-cell
  %one-shot-cell?
  %osc-state
  %osc-kind
  %osc-sub-k
  %osc-prefix
  %osc-marks
  %osc-barriers
  %osc-handlers
  %osc-tag
  %osc-cas-state!
  %osc-load-state
  %osc-kind-fast
  %osc-sub-k-fast
  %osc-sub-k-set!
  %osc-prefix-fast
  %osc-prefix-set!
  %osc-marks-fast
  %osc-marks-set!
  %osc-barriers-fast
  %osc-barriers-set!
  %osc-handlers-fast
  %osc-handlers-set!
  %osc-tag-fast
  %osc-clear-consumed!
  %freeze-mc-frame!
  %mc-try-reclaim-return!
  %return-oneshot-same-dynwind!))

(##namespace ("srfi/226/unwind#"
  %make-mc-eh-trampoline
  %mc-eh-trampoline-code
  %mc-eh-trampoline-prev
  %mc-unwind-and-raise!))

(##namespace ("srfi/226/prompt#"
  %default-prompt-handler
  %mc-return-vals
  %mc-find-tail-slow
  %entering-barrier?
  %prompt-cont!
  %prompt-cont-scoped!
  %invoke-abort-handler
  %abort-to-pframe!))

(##namespace ("srfi/226/cont#"
  %composable-replay-1!
  %composable-oneshot-replay-1!
  %invoke-composable-parts
  %invoke-composable-cell
  %commit-noncomp-and-return!
  %invoke-noncomp-parts
  %invoke-noncomp-cell
  %invoke-raw-parts
  %invoke-raw-cell
  %make-composable-closure
  %make-noncomp-closure
  %capture-composable-cont!
  %capture-composable-fast!
  %capture-noncomp-cont!
  %invoke-one-shot-cell
  %make-one-shot-closure
  %init-one-shot-closure-code
  %init-composable-closure-code
  %init-noncomp-closure-code
  %one-shot-closure-code
  %composable-closure-code
  %noncomp-closure-code
  %extract-one-shot-cell
  %extract-any-cont-cell
  %capture-1cc-raw!
  %capture-1cc-noncomp!
  %capture-1cc-noncomp-fast!
  %capture-1shot-comp-fast!
  %capture-1shot-comp!))

(##namespace ("srfi/226/marks#"
  %mark-pop-ra
  %alist-replace
  %mark-pop-frame
  %mark-push-and-run!
  %mark-dispatch))

;;;============================================================================
