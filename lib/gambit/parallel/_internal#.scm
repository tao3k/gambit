;;;============================================================================

;;; File: "_internal#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Internal subsystem namespace map for the modular (gambit parallel) runtime.
;;; Included once by "parallel.scm" so every subsystem owns a dedicated Gambit
;;; namespace while compiling inside a single `(block)` unit with zero
;;; cross-module dispatch overhead.

(##namespace ("gambit/parallel/atomics#"
  %make-padded-fxatom
  %fxatom-load-rlx
  %fxatom-load-acq
  %fxatom-store-rlx!
  %fxatom-store-rel!
  %fxatom-cas-seq!
  %fxatom-add-acqrel!
  %fxatom-sub-acqrel!
  %seq-cst-fence!
  %cpu-pause!
  %vec-slot-load-rlx
  %vec-slot-store-rlx!
))

(##namespace ("gambit/parallel/deque#"
  next-pow2
  deque-grow-array!
))

(##namespace ("gambit/parallel/pool#"
  empty-sentinel
  abort-sentinel
  pending-sentinel
  running-sentinel
  current-worker-binding
  pool-wake-one!
  pool-inject-push!
  pool-inject-pop!
  pool-any-deque-work?
  pool-try-steal
  pool-try-get-task
  pool-run-task!
  pool-worker-loop
  pool-submit!
  default-pool-mut
  default-pool-box
  get-active-pool
))

(##namespace ("gambit/parallel/future#"
  %future-state-load-acq
  %future-state-cas-acqrel!
  %future-state-store-rel!
  %future-thunk-clear!
  %make-future-state
  %parallel-pop-guard!
  %future-aborted-error
  future-run-once!
))

(##namespace ("gambit/parallel/combinators#"
  default-grain
  %with-fork-join-guard
))

;;;============================================================================
