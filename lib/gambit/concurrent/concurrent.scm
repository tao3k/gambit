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

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

;; 128-byte padded fixnum atomic box (eliminates Chase-Lev top/bottom false sharing)
(define (%make-ws-ctr init)
  (let ((v (##make-vector 16 0)))
    (##vector-set! v 0 init)
    v))

(define (%ws-load-rlx c)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 0));"
    c)
   (##vector-cas! c 0 #!unbound #!unbound)))

(define (%ws-load-acq c)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 1));"
    c)
   (##vector-cas! c 0 #!unbound #!unbound)))

(define (%ws-store-rlx! c val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 0);
     ___RESULT = ___VOID;"
    c val)
   (let loop ((old (##vector-cas! c 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! c 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%ws-store-rel! c val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    c val)
   (let loop ((old (##vector-cas! c 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! c 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%ws-cas-seq! c expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    c expected desired)
   (##vector-cas! c 0 desired expected)))

(define (%ws-fence-seq!)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order(4); ___RESULT = ___VOID;")
   (atomic-fence (memory-order sequentially-consistent))))

(define (%ws-slot-load-acq slots idx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_load(___s, 1);"
    slots idx)
   (srfi/230#vector-atomic-ref slots idx (memory-order acquire))))

(define (%ws-slot-store-rlx! slots idx val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___gc_atomic_slot_exchange(
       ___ps, ___ARG1, ___s, ___ARG3, 0,
       ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
     ___RESULT = ___VOID;"
    slots idx val)
   (srfi/230#vector-atomic-set! slots idx val (memory-order relaxed))))

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

;; Zero-closure single-value variant: returns dequeued value or `default` when empty.
(define (lf-queue-try-dequeue-or! q default)
  (let ((head-box (lf-queue-head q))
        (tail-box (lf-queue-tail q)))
    (let loop ()
      (let* ((head (atomic-box-ref head-box (memory-order acquire)))
             (tail (atomic-box-ref tail-box (memory-order acquire)))
             (next (atomic-box-ref (lf-qnode-next head) (memory-order acquire))))
        (if (eq? head (atomic-box-ref head-box (memory-order acquire)))
            (if (eq? head tail)
                (if (not next)
                    default
                    (begin
                      (atomic-box-compare-and-swap! tail-box tail next (memory-order release))
                      (loop)))
                (let ((val (lf-qnode-val next)))
                  (let ((prev (atomic-box-compare-and-swap! head-box head next (memory-order acquire-release))))
                    (if (eq? prev head)
                        (begin
                          (lf-qnode-val-set! next #f)
                          val)
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
                    (%make-ws-ctr 0)
                    (%make-ws-ctr 0))))

(define (ws-deque-size dq)
  (let ((b (%ws-load-acq (ws-deque-bottom dq)))
        (t (%ws-load-acq (ws-deque-top dq))))
    (let ((d (fx- b t)))
      (if (> d 0) d 0))))

;; Owner-only push at bottom. Returns #t on success, #f if bounded ring is full.
(define (ws-deque-push! dq val)
  (let* ((bot-box (ws-deque-bottom dq))
         (b (%ws-load-rlx bot-box))
         (t (%ws-load-acq (ws-deque-top dq)))
         (cap (ws-deque-cap dq)))
    (if (fx>= (fx- b t) cap)
        #f
        (begin
          (%ws-slot-store-rlx! (ws-deque-slots dq) (fxand b (ws-deque-mask dq)) val)
          (%ws-store-rel! bot-box (fx+ b 1))
          #t))))

;; Owner-only LIFO pop from bottom. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-pop! dq)
  (let* ((bot-box (ws-deque-bottom dq))
         (b (fx- (%ws-load-rlx bot-box) 1))
         (top-box (ws-deque-top dq))
         (slots (ws-deque-slots dq))
         (idx (fxand b (ws-deque-mask dq))))
    (%ws-store-rlx! bot-box b)
    (%ws-fence-seq!)
    (let ((t (%ws-load-rlx top-box)))
      (cond
        ((fx< t b)
         (values #t (%ws-slot-load-acq slots idx)))
        ((fx= t b)
         (let* ((val (%ws-slot-load-acq slots idx))
                (prev (%ws-cas-seq! top-box t (fx+ t 1))))
           (%ws-store-rlx! bot-box (fx+ b 1))
           (if (fx= prev t)
               (values #t val)
               (values #f #f))))
        (else
         (%ws-store-rlx! bot-box (fx+ b 1))
         (values #f #f))))))

;; Concurrent thief FIFO steal from top. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-steal! dq)
  (let ((top-box (ws-deque-top dq))
        (bot-box (ws-deque-bottom dq)))
    (let ((t (%ws-load-acq top-box)))
      (%ws-fence-seq!)
      (let ((b (%ws-load-acq bot-box)))
        (if (fx< t b)
            (let* ((val (%ws-slot-load-acq (ws-deque-slots dq) (fxand t (ws-deque-mask dq))))
                   (prev (%ws-cas-seq! top-box t (fx+ t 1))))
              (if (fx= prev t)
                  (values #t val)
                  (values #f #f)))
            (values #f #f))))))

;; Zero-closure owner-only LIFO pop: returns popped item or `default` when empty.
(define (ws-deque-try-pop-or! dq default)
  (let* ((bot-box (ws-deque-bottom dq))
         (b (fx- (%ws-load-rlx bot-box) 1))
         (top-box (ws-deque-top dq))
         (slots (ws-deque-slots dq))
         (idx (fxand b (ws-deque-mask dq))))
    (%ws-store-rlx! bot-box b)
    (%ws-fence-seq!)
    (let ((t (%ws-load-rlx top-box)))
      (cond
        ((fx< t b)
         (%ws-slot-load-acq slots idx))
        ((fx= t b)
         (let* ((val (%ws-slot-load-acq slots idx))
                (prev (%ws-cas-seq! top-box t (fx+ t 1))))
           (%ws-store-rlx! bot-box (fx+ b 1))
           (if (fx= prev t) val default)))
        (else
         (%ws-store-rlx! bot-box (fx+ b 1))
         default)))))

;; Zero-closure concurrent thief FIFO steal: returns stolen item or `default` when empty.
(define (ws-deque-try-steal-or! dq default)
  (let ((top-box (ws-deque-top dq))
        (bot-box (ws-deque-bottom dq)))
    (let ((t (%ws-load-acq top-box)))
      (%ws-fence-seq!)
      (let ((b (%ws-load-acq bot-box)))
        (if (fx< t b)
            (let* ((val (%ws-slot-load-acq (ws-deque-slots dq) (fxand t (ws-deque-mask dq))))
                   (prev (%ws-cas-seq! top-box t (fx+ t 1))))
              (if (fx= prev t) val default))
            default)))))

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
