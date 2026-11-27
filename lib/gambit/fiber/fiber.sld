;;;============================================================================

;;; File: "fiber.sld"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime

(define-library (gambit fiber)

  (import (gambit)
          (gambit effect)
          (gambit concurrent)
          (srfi 230))

  (export
    run-fibers
    with-nursery
    nursery?
    fiber-spawn
    fiber-yield
    fiber-worker-count

    make-fiber-channel
    fiber-channel?
    fiber-send!
    fiber-recv!)

  (include "fiber.scm"))

;;;============================================================================
