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
    fiber-try-send!
    fiber-try-recv!
    fiber-channel-close!
    fiber-channel-closed?)

  (include "fiber.scm"))

;;;============================================================================
