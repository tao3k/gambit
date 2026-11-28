;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Modularized by subsystem namespace while compiled as a single `(block)`
;;; unit so cross-subsystem fast paths inline with zero dynamic-dispatch tax:
;;;   - atomics.scm      (gambit/fiber/atomics#)      C23 atomics, parker, spinlock
;;;   - deque.scm        (gambit/fiber/deque#)        128B-padded Chase-Lev deque
;;;   - context.scm      (gambit/fiber/context#)      scheduler, worker-ctx, carrier TLS
;;;   - nursery.scm      (gambit/fiber/nursery#)      structured concurrency nursery
;;;   - spawn.scm        (gambit/fiber/spawn#)        with-finally, spawn, fused yield
;;;   - channel-ring.scm (gambit/fiber/channel/ring#) waitq, Vyukov ring, fast slots
;;;   - channel-send.scm (gambit/fiber/channel/send#) fused & slow-path send parkers
;;;   - channel-recv.scm (gambit/fiber/channel/recv#) fused & slow-path recv parkers
;;;   - channel.scm      (gambit/fiber/channel#)      fast-path dispatch & channel API
;;;   - scheduler.scm    (gambit/fiber/scheduler#)    work-stealing trampoline & run-fibers

(##supply-module gambit/fiber)

(##namespace ("gambit/fiber#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  make-thread
  thread-start!
  thread-join!
  thread-yield!
  with-exception-catcher
  raise
  error))
(##include "~~lib/gambit/concurrent/concurrent#.scm")
(##include "~~lib/srfi/226/226#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "fiber#.scm")
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
(##include "context.scm")
(##include "nursery.scm")
(##include "spawn.scm")
(##include "channel-ring.scm")
(##include "channel-send.scm")
(##include "channel-recv.scm")
(##include "channel.scm")
(##include "scheduler.scm")

;;;============================================================================
