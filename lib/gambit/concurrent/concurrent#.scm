;;;============================================================================

;;; File: "concurrent#.scm"

;;; Lock-Free SMP Concurrent Data Structures built on (srfi 230)

(##namespace ("gambit/concurrent#"

make-lf-stack
lf-stack?
lf-stack-push!
lf-stack-try-pop!
lf-stack-empty?

make-lf-queue
lf-queue?
lf-queue-enqueue!
lf-queue-try-dequeue!
lf-queue-empty?

make-ws-deque
ws-deque?
ws-deque-push!
ws-deque-try-pop!
ws-deque-try-steal!
ws-deque-size

make-concurrent-table
concurrent-table?
concurrent-table-ref
concurrent-table-set!
concurrent-table-update!
concurrent-table-delete!
concurrent-table-size

))

;;;============================================================================
