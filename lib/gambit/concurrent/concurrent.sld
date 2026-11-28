;;;============================================================================

;;; File: "concurrent.sld"

;;; Lock-Free SMP Concurrent Data Structures built on (srfi 230)

(define-library (gambit concurrent)

  (import (gambit)
          (srfi 230))

  (export
    ;; Lock-free Treiber stack
    make-lf-stack
    lf-stack?
    lf-stack-push!
    lf-stack-try-pop!
    lf-stack-empty?

    ;; Lock-free Michael-Scott MPMC FIFO queue
    make-lf-queue
    lf-queue?
    lf-queue-enqueue!
    lf-queue-try-dequeue!
    lf-queue-try-dequeue-or!
    lf-queue-empty?

    ;; Lock-free Chase-Lev work-stealing deque
    make-ws-deque
    ws-deque?
    ws-deque-push!
    ws-deque-try-pop!
    ws-deque-try-pop-or!
    ws-deque-try-steal!
    ws-deque-try-steal-or!
    ws-deque-size

    ;; Wait-free-read / lock-free-write sharded concurrent hash table
    make-concurrent-table
    concurrent-table?
    concurrent-table-ref
    concurrent-table-set!
    concurrent-table-update!
    concurrent-table-delete!
    concurrent-table-size)

  (include "concurrent.scm"))

;;;============================================================================
