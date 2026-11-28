;;;============================================================================

;;; File: "_internal#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Internal subsystem namespace map for the modular (gambit fiber) runtime.
;;; Included once by "fiber.scm" so every subsystem owns a dedicated Gambit
;;; namespace while compiling inside a single `(block)` unit with zero
;;; cross-module dispatch overhead.

(##namespace ("gambit/fiber/atomics#"
  %parker-finish-wait-ffi!
  %make-parker
  %destroy-parker!
  %parker-wake-one!
  %parker-wake-all!
  %parker-begin-wait!
  %parker-abort-wait!
  %parker-finish-wait!
  %set-carrier-qos!
  %os-sched-yield!
  %make-fxatom
  %make-padded-fxatom
  %fxatom-load-rlx
  %fxatom-load-acq
  %fxatom-load-seq
  %fxatom-set-rlx!
  %fxatom-set-rel!
  %fxatom-set-seq!
  %fxatom-cas-rlx!
  %fxatom-cas-acq!
  %fxatom-cas-seq!
  %fxatom-add-acqrel!
  %fxatom-sub-acqrel!
  %fxatom-inc-owner-rel!
  %vec-fx-load-acq
  %vec-fx-store-seq!
  %dq-slot-load-acq
  %dq-slot-store-rlx!
  %seq-cst-fence!
  %idle-pause-c!
  %spin-trylock-bounded!
  %spin-lock!
  %spin-unlock!
))

(##namespace ("gambit/fiber/deque#"
  %DQ-CAP
  %DQ-MASK
  %MAX-STEAL-BATCH
  %make-local-dq
  %dq-push-pair!
  %dq-pop!
  %dq-empty-rlx?
  %dq-steal-batch!
  %make-local-dq-raw
  %local-dq?
  %dq-buf
  %dq-top
  %dq-bot
  %local-dq
))

(##namespace ("gambit/fiber/context#"
  %get-tc
  %set-tc!
  %MAX-LIFO-STREAK
  %MAX-FK-POOL
  %MAX-NURSERY-BATCH
  %CH-EMPTY
  %CH-RETRY
  %outside-run-fibers-error!
  %current-wctx
  %carrier-wctx
  %alloc-fk!
  %free-fk!
  %sched-enqueue-global!
  %sched-try-dequeue-global!
  %sched-push-dq-pair!
  %sched-push-dq!
  %sched-push-lifo!
  %sched-wake!
  %wake-fk!
  %sched-quiescent?
  %sched-try-acquire-search!
  %sched-release-search!
  %make-fiber-k
  %fiber-k?
  %fk-raw-k
  %fk-raw-k-set!
  %fk-tc
  %fk-tc-set!
  %fk-val
  %fk-val-set!
  %fk-sched
  %fiber-k
  %make-scheduler
  %scheduler?
  %sched-num-workers
  %sched-deques
  %sched-global-q
  %sched-global-pending
  %sched-spawned-vec
  %sched-completed-vec
  %sched-root-done
  %sched-root-box
  %sched-searching
  %sched-max-searching
  %sched-parker
  %scheduler
  %make-worker-ctx
  %worker-ctx?
  %wctx-sched
  %wctx-wid
  %wctx-dq
  %wctx-spawned
  %wctx-completed
  %wctx-lifo
  %wctx-lifo-set!
  %wctx-lifo-streak
  %wctx-lifo-streak-set!
  %wctx-ticks
  %wctx-ticks-set!
  %wctx-sched-k
  %wctx-sched-k-set!
  %wctx-fk-pool
  %wctx-fk-pool-set!
  %wctx-fk-pool-len
  %wctx-fk-pool-len-set!
  %wctx-steal-cursor
  %wctx-steal-cursor-set!
  %wctx-nursery-cur
  %wctx-nursery-cur-set!
  %wctx-nursery-batch
  %wctx-nursery-batch-set!
  %wctx-lifo-n
  %wctx-lifo-n-set!
  %wctx-picked-n
  %wctx-picked-n-set!
  %worker-ctx
))

(##namespace ("gambit/fiber/nursery#"
  %nursery-record-error!
  %nursery-sub-active!
  %nursery-flush!
  %nursery-child-done-batched!
  %nursery-child-abort!
  %park-nursery-cont!
  %make-nursery
  %nursery-sched
  %nursery-active
  %nursery-lock
  %nursery-waiter-k
  %nursery-waiter-k-set!
  %nursery-first-err
  %nursery-first-err-set!
  %nursery-has-err?
  %nursery-has-err?-set!
  %nursery-err-handler
  %nursery-err-handler-set!
  %nursery-cancelled
  nursery
))

(##namespace ("gambit/fiber/spawn#"
  %yield-push-and-pop-c!
  %yield-slow!
  %return-oneshot!
  %yield-cont!
  %fiber-spawn-push-c!
  %fiber-spawn-slow!
))

(##namespace ("gambit/fiber/channel/ring#"
  %wq-empty?
  %wq-push!
  %wq-pop!
  %ch-rx-any-waiters-seq?
  %ch-tx-any-waiters-seq?
  %ch-closed-rlx?
  %ch-closed-seq?
  %ch-seal-tail-seq!
  %ch-drain-closed-or-eof!
  %ch-try-pop-rxfast-c!
  %ch-try-pop-txfast-c!
  %vyukov-try-push-c!
  %vyukov-try-push!
  %vyukov-try-pop-c!
  %vyukov-try-pop-or!
  %ch-wake-one-receiver!
  %ch-wake-one-sender!
  %make-wait-q
  %wait-q?
  %wq-head
  %wq-head-set!
  %wait-q
  %make-fiber-channel
  %ch-cap
  %ch-mask
  %ch-buf
  %ch-seq
  %ch-tail
  %ch-head
  %ch-rx-waiters
  %ch-tx-waiters
  %ch-lock
  %ch-recv-waiters
  %ch-send-waiters
  fiber-channel
))

(##namespace ("gambit/fiber/channel/send#"
  %ch-park-send-c!
  %ch-park-send-and-pop-c!
  %park-send-buf-slow!
  %park-send-buf-cont!
))

(##namespace ("gambit/fiber/channel/recv#"
  %ch-park-recv-c!
  %ch-park-recv-and-pop-c!
  %park-recv-buf-slow!
  %park-recv-buf-cont!
  %park-send-unbuf-cont!
  %park-recv-unbuf-cont!
))

(##namespace ("gambit/fiber/channel#"
  %ch-send-fast-c!
  %ch-recv-fast-c!
  %fiber-send-evict-and-true!
  %fiber-send-slow!
  %fiber-recv-wake-and-ret!
  %fiber-recv-park!
  %fiber-recv-slow!
))

(##namespace ("gambit/fiber/scheduler#"
  %worker-try-steal
  %worker-poll-task
  %sched-switch-next!
  %worker-run-task
  %sched-any-work-visible?
  %worker-dispatch
  %worker-loop
))

;;;============================================================================
