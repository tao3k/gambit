;;;============================================================================

;;; File: "fiber#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Built on (gambit effect) + (gambit concurrent) Chase-Lev work-stealing
;;; deques + (srfi 230) atomics.

(##namespace ("gambit/fiber#"

run-fibers
with-nursery
with-finally
nursery?
fiber-spawn
fiber-yield
fiber-worker-count
fiber-performance-core-count
fiber-carrier-wid
fiber-carrier-tls
fiber-carrier-tls-set!

make-fiber-channel
fiber-channel?
fiber-send!
fiber-recv!

))

;;;============================================================================
