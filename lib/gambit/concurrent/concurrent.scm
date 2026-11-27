;;;============================================================================

;;; File: "concurrent.scm"

;;; Lock-Free SMP Concurrent Data Structures built directly on (srfi 230)
;;; C23 atomic operations and Gambit SMP GC write barriers.

(##supply-module gambit/concurrent)

(##namespace ("gambit/concurrent#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "concurrent#.scm")

(declare (extended-bindings))
(declare (block))

;;;============================================================================
;;; 1. Lock-Free Treiber Stack (GC-managed nodes -> immune to ABA)

(##define-type lf-stack
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000001
  constructor: %make-lf-stack
  predicate: lf-stack?
  opaque:
  (head unprintable: read-only:))

(define (make-lf-stack)
  (%make-lf-stack (make-atomic-box '())))

(define (lf-stack-empty? st)
  (null? (atomic-box-ref (lf-stack-head st) (memory-order acquire))))

(define (lf-stack-push! st val)
  (let ((head (lf-stack-head st)))
    (let loop ()
      (let* ((cur (atomic-box-ref head (memory-order acquire)))
             (nxt (cons val cur))
             (prev (atomic-box-compare-and-swap! head cur nxt (memory-order acquire-release))))
        (if (eq? prev cur)
            #t
            (loop))))))

;; Returns (values #t val) on success, or (values #f #f) when empty.
(define (lf-stack-try-pop! st)
  (let ((head (lf-stack-head st)))
    (let loop ()
      (let ((cur (atomic-box-ref head (memory-order acquire))))
        (if (null? cur)
            (values #f #f)
            (let ((prev (atomic-box-compare-and-swap! head cur (cdr cur) (memory-order acquire-release))))
              (if (eq? prev cur)
                  (values #t (car cur))
                  (loop))))))))

;;;============================================================================
;;; 2. Lock-Free Michael-Scott MPMC FIFO Queue

(##define-type lf-qnode
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000002
  constructor: %make-lf-qnode
  predicate: lf-qnode?
  opaque:
  (val  unprintable:)
  (next unprintable: read-only:))

(##define-type lf-queue
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000003
  constructor: %make-lf-queue
  predicate: lf-queue?
  opaque:
  (head unprintable: read-only:)
  (tail unprintable: read-only:))

(define (make-lf-queue)
  (let ((dummy (%make-lf-qnode #f (make-atomic-box #f))))
    (%make-lf-queue (make-atomic-box dummy)
                    (make-atomic-box dummy))))

(define (lf-queue-empty? q)
  (let* ((h (atomic-box-ref (lf-queue-head q) (memory-order acquire)))
         (nxt (atomic-box-ref (lf-qnode-next h) (memory-order acquire))))
    (not nxt)))

(define (lf-queue-enqueue! q val)
  (let ((node (%make-lf-qnode val (make-atomic-box #f)))
        (tail-box (lf-queue-tail q)))
    (let loop ()
      (let* ((tail (atomic-box-ref tail-box (memory-order acquire)))
             (next-box (lf-qnode-next tail))
             (next (atomic-box-ref next-box (memory-order acquire))))
        (if (eq? tail (atomic-box-ref tail-box (memory-order acquire)))
            (if (not next)
                (let ((prev (atomic-box-compare-and-swap! next-box #f node (memory-order acquire-release))))
                  (if (not prev)
                      (begin
                        ;; Best-effort tail swing (concurrent enqueuers help if this races).
                        (atomic-box-compare-and-swap! tail-box tail node (memory-order release))
                        #t)
                      (loop)))
                (begin
                  ;; Help advance lagging tail pointer.
                  (atomic-box-compare-and-swap! tail-box tail next (memory-order release))
                  (loop)))
            (loop))))))

;; Returns (values #t val) on success, or (values #f #f) when empty.
(define (lf-queue-try-dequeue! q)
  (let ((head-box (lf-queue-head q))
        (tail-box (lf-queue-tail q)))
    (let loop ()
      (let* ((head (atomic-box-ref head-box (memory-order acquire)))
             (tail (atomic-box-ref tail-box (memory-order acquire)))
             (next (atomic-box-ref (lf-qnode-next head) (memory-order acquire))))
        (if (eq? head (atomic-box-ref head-box (memory-order acquire)))
            (if (eq? head tail)
                (if (not next)
                    (values #f #f)
                    (begin
                      ;; Tail is lagging behind; help advance it.
                      (atomic-box-compare-and-swap! tail-box tail next (memory-order release))
                      (loop)))
                (let ((val (lf-qnode-val next)))
                  (let ((prev (atomic-box-compare-and-swap! head-box head next (memory-order acquire-release))))
                    (if (eq? prev head)
                        (begin
                          ;; Clear payload from new dummy node so GC can reclaim promptly.
                          (lf-qnode-val-set! next #f)
                          (values #t val))
                        (loop)))))
            (loop))))))

;;;============================================================================
;;; 3. Lock-Free Bounded Chase-Lev Work-Stealing Deque

(##define-type ws-deque
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000004
  constructor: %make-ws-deque
  predicate: ws-deque?
  opaque:
  (mask   unprintable: read-only:)
  (cap    unprintable: read-only:)
  (slots  unprintable: read-only:)
  (top    unprintable: read-only:)
  (bottom unprintable: read-only:))

(define (%next-pow2 n)
  (let loop ((p 16))
    (if (>= p n) p (loop (fx* p 2)))))

(define (make-ws-deque #!optional (min-cap 256))
  (let* ((cap (%next-pow2 (if (and (fixnum? min-cap) (> min-cap 0)) min-cap 256)))
         (slots (make-vector cap #f)))
    (%make-ws-deque (fx- cap 1) cap slots
                    (make-atomic-fxbox 0)
                    (make-atomic-fxbox 0))))

(define (ws-deque-size dq)
  (let ((b (atomic-fxbox-ref (ws-deque-bottom dq) (memory-order acquire)))
        (t (atomic-fxbox-ref (ws-deque-top dq) (memory-order acquire))))
    (let ((d (fx- b t)))
      (if (> d 0) d 0))))

;; Owner-only push at bottom. Returns #t on success, #f if bounded ring is full.
(define (ws-deque-push! dq val)
  (let* ((b (atomic-fxbox-ref (ws-deque-bottom dq) (memory-order relaxed)))
         (t (atomic-fxbox-ref (ws-deque-top dq) (memory-order acquire)))
         (cap (ws-deque-cap dq)))
    (if (>= (fx- b t) cap)
        #f
        (begin
          (srfi/230#vector-atomic-set!
           (ws-deque-slots dq) (fxand b (ws-deque-mask dq)) val (memory-order relaxed))
          (atomic-fxbox-set! (ws-deque-bottom dq) (fx+ b 1) (memory-order release))
          #t))))

;; Owner-only LIFO pop from bottom. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-pop! dq)
  (let* ((b (fx- (atomic-fxbox-ref (ws-deque-bottom dq) (memory-order relaxed)) 1))
         (top-box (ws-deque-top dq))
         (bot-box (ws-deque-bottom dq))
         (slots (ws-deque-slots dq))
         (idx (fxand b (ws-deque-mask dq))))
    (atomic-fxbox-set! bot-box b (memory-order relaxed))
    (atomic-fence (memory-order sequentially-consistent))
    (let ((t (atomic-fxbox-ref top-box (memory-order relaxed))))
      (cond
        ((< t b)
         (let ((val (srfi/230#vector-atomic-ref slots idx (memory-order acquire))))
           (values #t val)))
        ((= t b)
         (let* ((val (srfi/230#vector-atomic-ref slots idx (memory-order acquire)))
                (prev (atomic-fxbox-compare-and-swap! top-box t (fx+ t 1) (memory-order sequentially-consistent))))
           (atomic-fxbox-set! bot-box (fx+ b 1) (memory-order relaxed))
           (if (= prev t)
               (values #t val)
               (values #f #f))))
        (else
         (atomic-fxbox-set! bot-box (fx+ b 1) (memory-order relaxed))
         (values #f #f))))))

;; Concurrent thief FIFO steal from top. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-steal! dq)
  (let ((top-box (ws-deque-top dq))
        (bot-box (ws-deque-bottom dq)))
    (let ((t (atomic-fxbox-ref top-box (memory-order acquire))))
      (atomic-fence (memory-order sequentially-consistent))
      (let ((b (atomic-fxbox-ref bot-box (memory-order acquire))))
        (if (< t b)
            (let* ((val (srfi/230#vector-atomic-ref
                         (ws-deque-slots dq) (fxand t (ws-deque-mask dq)) (memory-order acquire)))
                   (prev (atomic-fxbox-compare-and-swap! top-box t (fx+ t 1) (memory-order sequentially-consistent))))
              (if (= prev t)
                  (values #t val)
                  (values #f #f)))
            (values #f #f))))))

;;;============================================================================
;;; 4. Wait-Free-Read / Lock-Free-Write Sharded Concurrent Hash Table

(##define-type concurrent-table
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000005
  constructor: %make-concurrent-table
  predicate: concurrent-table?
  opaque:
  (mask    unprintable: read-only:)
  (buckets unprintable: read-only:)
  (eq-fn   unprintable: read-only:)
  (hash-fn unprintable: read-only:)
  (count   unprintable: read-only:))

(define (make-concurrent-table #!optional (min-buckets 64) (eq-fn equal?) (hash-fn equal?-hash))
  (let* ((nb (%next-pow2 (if (and (fixnum? min-buckets) (> min-buckets 0)) min-buckets 64)))
         (buckets (make-vector nb '())))
    (%make-concurrent-table (fx- nb 1) buckets eq-fn hash-fn (make-atomic-fxbox 0))))

(define (%ct-bucket-idx ct key)
  (fxand ((concurrent-table-hash-fn ct) key) (concurrent-table-mask ct)))

(define (%alist-find alist key eq-fn)
  (let loop ((xs alist))
    (cond
      ((null? xs) #f)
      ((eq-fn (caar xs) key) (car xs))
      (else (loop (cdr xs))))))

;; Share untouched suffix after matched key to avoid O(n) reverse allocation.
(define (%alist-replace alist key val eq-fn)
  (let loop ((xs alist) (prefix '()))
    (cond
      ((null? xs)
       (values (cons (cons key val) alist) #f))
      ((eq-fn (caar xs) key)
       (let rebuild ((p prefix) (res (cons (cons key val) (cdr xs))))
         (if (null? p)
             (values res #t)
             (rebuild (cdr p) (cons (car p) res)))))
      (else
       (loop (cdr xs) (cons (car xs) prefix))))))

(define (%alist-delete alist key eq-fn)
  (let loop ((xs alist) (prefix '()))
    (cond
      ((null? xs)
       (values alist #f))
      ((eq-fn (caar xs) key)
       (let rebuild ((p prefix) (res (cdr xs)))
         (if (null? p)
             (values res #t)
             (rebuild (cdr p) (cons (car p) res)))))
      (else
       (loop (cdr xs) (cons (car xs) prefix))))))

(define (concurrent-table-size ct)
  (atomic-fxbox-ref (concurrent-table-count ct) (memory-order acquire)))

;; Wait-free read: single acquire load + immutable bucket scan.
(define (concurrent-table-ref ct key #!optional (default #f))
  (let* ((alist (srfi/230#vector-atomic-ref
                 (concurrent-table-buckets ct) (%ct-bucket-idx ct key) (memory-order acquire)))
         (entry (%alist-find alist key (concurrent-table-eq-fn ct))))
    (if entry (cdr entry) default)))

(define (concurrent-table-set! ct key val)
  (let ((buckets (concurrent-table-buckets ct))
        (idx (%ct-bucket-idx ct key))
        (eq-fn (concurrent-table-eq-fn ct))
        (cnt (concurrent-table-count ct)))
    (let loop ()
      (let ((cur (srfi/230#vector-atomic-ref buckets idx (memory-order acquire))))
        (call-with-values
          (lambda () (%alist-replace cur key val eq-fn))
          (lambda (nxt existed)
            (let ((prev (srfi/230#vector-atomic-cas! buckets idx cur nxt (memory-order acquire-release))))
              (if (eq? prev cur)
                  (begin
                    (unless existed
                      (atomic-fxbox+/fetch! cnt 1 (memory-order relaxed)))
                    val)
                  (loop)))))))))

;; Atomic functional update: (updater found? old-val) -> new-val.
(define (concurrent-table-update! ct key updater)
  (let ((buckets (concurrent-table-buckets ct))
        (idx (%ct-bucket-idx ct key))
        (eq-fn (concurrent-table-eq-fn ct))
        (cnt (concurrent-table-count ct)))
    (let loop ()
      (let* ((cur (srfi/230#vector-atomic-ref buckets idx (memory-order acquire)))
             (entry (%alist-find cur key eq-fn))
             (new-val (if entry (updater #t (cdr entry)) (updater #f #f))))
        (call-with-values
          (lambda () (%alist-replace cur key new-val eq-fn))
          (lambda (nxt existed)
            (let ((prev (srfi/230#vector-atomic-cas! buckets idx cur nxt (memory-order acquire-release))))
              (if (eq? prev cur)
                  (begin
                    (unless existed
                      (atomic-fxbox+/fetch! cnt 1 (memory-order relaxed)))
                    new-val)
                  (loop)))))))))

(define (concurrent-table-delete! ct key)
  (let ((buckets (concurrent-table-buckets ct))
        (idx (%ct-bucket-idx ct key))
        (eq-fn (concurrent-table-eq-fn ct))
        (cnt (concurrent-table-count ct)))
    (let loop ()
      (let ((cur (srfi/230#vector-atomic-ref buckets idx (memory-order acquire))))
        (call-with-values
          (lambda () (%alist-delete cur key eq-fn))
          (lambda (nxt found)
            (if (not found)
                #f
                (let ((prev (srfi/230#vector-atomic-cas! buckets idx cur nxt (memory-order acquire-release))))
                  (if (eq? prev cur)
                      (begin
                        (atomic-fxbox-/fetch! cnt 1 (memory-order relaxed))
                        #t)
                      (loop))))))))))

;;;============================================================================
