;;;============================================================================

;;; File: "parallel.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Weak-Memory-Safe Chase-Lev Work-Stealing Deque (Le et al., PPoPP 2013)
;;; and Structured Fork-Join Parallel Stdlib.
;;;
;;; Features:
;;;   - 128-byte cache-line padded Chase-Lev top/bottom cursors with inline C23
;;;     atomics on the C target and portable (srfi 230) fallback on JS.
;;;   - Zero-mutex-poll inject queue check and Dekker-fenced sleeper parking
;;;     with steal-cascade and inject-cascade wakeup.
;;;   - Single-allocation futures with inline atomic CAS state transitions.
;;;   - Structured fork-join exception quiescence (right child always joined
;;;     before left exception unwinds).

(##supply-module gambit/parallel)

(##namespace ("gambit/parallel#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##namespace (""
              make-mutex mutex-lock! mutex-unlock!
              make-condition-variable condition-variable-signal! condition-variable-broadcast!
              make-thread thread-start! thread-join! thread-yield!
              make-parameter parameterize with-exception-catcher raise))

(##include "parallel#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (inlining-limit 400)
  (block))

;;;============================================================================
;;; Part 0: Inline C23 128B-Padded Atomics (Zero Cross-Module Overhead on C)
;;;
;;; Memory-order codes match Gambit runtime_protocols:
;;;   0=relaxed, 1=acquire, 2=release, 3=acq_rel, 4=seq_cst
;;;============================================================================

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

(define (%make-padded-fxatom init)
  (macro-if-c-compiled
   (##make-vector 16 init)
   (make-atomic-fxbox init)))

(define (%fxatom-load-rlx box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 0));"
    box)
   (atomic-fxbox-ref box 'relaxed)))

(define (%fxatom-load-acq box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 1));"
    box)
   (atomic-fxbox-ref box 'acquire)))

(define (%fxatom-store-rlx! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 0);
     ___RESULT = ___VOID;"
    box val)
   (atomic-fxbox-set! box val 'relaxed)))

(define (%fxatom-store-rel! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    box val)
   (atomic-fxbox-set! box val 'release)))

(define (%fxatom-cas-seq! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    box expected desired)
   (atomic-fxbox-compare-and-swap! box expected desired 'sequentially-consistent)))

(define (%fxatom-add-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_add(___CAST(___VOLATILE ___UWORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___UWORD, ___ARG2), 3));"
    box delta)
   (atomic-fxbox-fetch-add! box delta 'acquire-release)))

(define (%fxatom-sub-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___UWORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___UWORD, ___ARG2), 3));"
    box delta)
   (atomic-fxbox-fetch-sub! box delta 'acquire-release)))

(define (%seq-cst-fence!)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order(4); ___RESULT = ___VOID;")
   (atomic-fence 'sequentially-consistent)))

(define (%cpu-pause!)
  (macro-if-c-compiled
   (##c-code
    "#if defined(__aarch64__) || defined(_M_ARM64)
     __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
     __asm__ __volatile__(\"pause\");
#endif
     ___RESULT = ___VOID;")
   (##void)))

(define (%vec-slot-load-rlx vec idx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ, ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___s), 0));"
    vec idx)
   (vector-atomic-ref vec idx 'relaxed)))

(define (%vec-slot-store-rlx! vec idx val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___GC_WRITE_BARRIER(___ps, ___ARG1, ___s, ___ARG3);
     ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___ARG3), 0);
     ___RESULT = ___VOID;"
    vec idx val)
   (vector-atomic-set! vec idx val 'relaxed)))

;;;============================================================================
;;; Part 1: 128B-Padded Chase-Lev Work-Stealing Deque (Le et al. PPoPP 2013)
;;;
;;; Backing ring buffers are GC-traced Scheme vectors accessed via relaxed
;;; GC-barriered atomics so speculative stealers racing with ring wraparound
;;; are C23 DRF-0 clean, while `top` and `bottom` occupy distinct 128B cache
;;; lines to eliminate owner-vs-thief false sharing.
;;;============================================================================

(##define-type work-stealing-deque
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000001
  type-exhibitor: macro-type-work-stealing-deque
  constructor: macro-make-work-stealing-deque
  implementer: implement-type-work-stealing-deque
  macros:
  prefix: macro-
  opaque:
  (top    read-only: unprintable:)
  (bottom read-only: unprintable:)
  (array  read-only: unprintable:))
(implement-type-work-stealing-deque)

(define (next-pow2 n)
  (let loop ((p 4))
    (if (##fx>= p n) p (loop (##fxarithmetic-shift-left p 1)))))

(define (make-work-stealing-deque #!optional (initial-capacity 64))
  (let ((cap (next-pow2 (if (and (##fixnum? initial-capacity)
                                 (##fx> initial-capacity 0))
                            initial-capacity
                            64))))
    (macro-make-work-stealing-deque
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (make-atomic-box (##make-vector cap #f)))))

(define (work-stealing-deque? obj)
  (macro-work-stealing-deque? obj))

(define (deque-size-approx q)
  (let* ((t (%fxatom-load-acq (macro-work-stealing-deque-top q)))
         (b (%fxatom-load-acq (macro-work-stealing-deque-bottom q)))
         (d (##fx- b t)))
    (if (##fx> d 0) d 0)))

(define (deque-empty? q)
  (##fx= (deque-size-approx q) 0))

;;; Grow ring buffer by 2x, preserving every live slot i in [t, b) without collision.
(define (deque-grow-array! q old-a t b)
  (let* ((old-cap (##vector-length old-a))
         (old-mask (##fx- old-cap 1))
         (new-cap (##fxarithmetic-shift-left old-cap 1))
         (new-mask (##fx- new-cap 1))
         (new-a (##make-vector new-cap #f)))
    (let loop ((i t))
      (if (##fx< i b)
          (begin
            (##vector-set!
             new-a
             (##fxand i new-mask)
             (%vec-slot-load-rlx old-a (##fxand i old-mask)))
            (loop (##fx+ i 1)))))
    (atomic-box-set! (macro-work-stealing-deque-array q) new-a 'release)
    new-a))

;;; Owner-only LIFO push at bottom.
(define (deque-push-bottom! q item)
  (let* ((bot-box (macro-work-stealing-deque-bottom q))
         (b (%fxatom-load-rlx bot-box))
         (t (%fxatom-load-acq (macro-work-stealing-deque-top q)))
         (a0 (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed))
         (a (if (##fx>= (##fx- b t) (##vector-length a0))
                (deque-grow-array! q a0 t b)
                a0))
         (mask (##fx- (##vector-length a) 1)))
    (%vec-slot-store-rlx! a (##fxand b mask) item)
    (%fxatom-store-rel! bot-box (##fx+ b 1))
    (##void)))

;;; Owner-only LIFO pop from bottom (Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-pop-bottom! q #!optional (empty #f))
  (let* ((bot-box (macro-work-stealing-deque-bottom q))
         (top-box (macro-work-stealing-deque-top q))
         (b (##fx- (%fxatom-load-rlx bot-box) 1))
         (a (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed)))
    (%fxatom-store-rlx! bot-box b)
    (%seq-cst-fence!)
    (let ((t (%fxatom-load-rlx top-box)))
      (if (##fx<= t b)
          (let* ((mask (##fx- (##vector-length a) 1))
                 (idx (##fxand b mask))
                 (x (%vec-slot-load-rlx a idx)))
            (if (##fx= t b)
                (let ((prev (%fxatom-cas-seq! top-box t (##fx+ t 1))))
                  (%fxatom-store-rlx! bot-box (##fx+ b 1))
                  (if (##fx= prev t) x empty))
                (begin
                  ;; Safe to clear slot when t < b (no thief can read b).
                  (%vec-slot-store-rlx! a idx #f)
                  x)))
          (begin
            (%fxatom-store-rlx! bot-box (##fx+ b 1))
            empty)))))

;;; Concurrent thief FIFO steal from top (Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-steal! q #!optional (empty #f) (abort #f))
  (let* ((top-box (macro-work-stealing-deque-top q))
         (bot-box (macro-work-stealing-deque-bottom q))
         (t (%fxatom-load-acq top-box)))
    (%seq-cst-fence!)
    (let ((b (%fxatom-load-acq bot-box)))
      (if (##fx< t b)
          (let* ((a (atomic-box-ref (macro-work-stealing-deque-array q) 'acquire))
                 (mask (##fx- (##vector-length a) 1))
                 (x (%vec-slot-load-rlx a (##fxand t mask)))
                 (prev (%fxatom-cas-seq! top-box t (##fx+ t 1))))
            (if (##fx= prev t) x abort))
          empty))))

;;;============================================================================
;;; Part 2: Zero-Mutex-Poll Work-Stealing Fork-Join Pool
;;;============================================================================

(define empty-sentinel (##vector 'empty))
(define abort-sentinel (##vector 'abort))
(define pending-sentinel (##vector 'pending))
(define running-sentinel (##vector 'running))

(##define-type work-stealing-pool
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000002
  type-exhibitor: macro-type-work-stealing-pool
  constructor: macro-make-work-stealing-pool
  implementer: implement-type-work-stealing-pool
  macros:
  prefix: macro-
  opaque:
  (nworkers      read-only: unprintable:)
  (deques        read-only: unprintable:)
  (threads       unprintable:)
  (inject-mut    read-only: unprintable:)
  (inject-cv     read-only: unprintable:)
  (inject-head   unprintable:)
  (inject-tail   unprintable:)
  (inject-count  read-only: unprintable:)
  (sleepers      read-only: unprintable:)
  (shutdown-flag read-only: unprintable:))
(implement-type-work-stealing-pool)

;; Thread-local (pool . worker-id) binding for worker threads (sole deque owner).
(define current-worker-binding (make-parameter #f))

(define (pool-wake-one! pool)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool)))
    (mutex-lock! mut)
    (condition-variable-signal! cv)
    (mutex-unlock! mut)))

(define (pool-inject-push! pool task)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool))
        (icnt (macro-work-stealing-pool-inject-count pool))
        (cell (##cons task '())))
    (mutex-lock! mut)
    (let ((tail (macro-work-stealing-pool-inject-tail pool)))
      (if (##pair? tail)
          (##set-cdr! tail cell)
          (macro-work-stealing-pool-inject-head-set! pool cell))
      (macro-work-stealing-pool-inject-tail-set! pool cell))
    (%fxatom-add-acqrel! icnt 1)
    (condition-variable-signal! cv)
    (mutex-unlock! mut)))

(define (pool-inject-pop! pool)
  (let ((icnt (macro-work-stealing-pool-inject-count pool)))
    ;; Fast lock-free skip when inject queue is empty (0 mutex acquisitions!).
    (if (##fx<= (%fxatom-load-rlx icnt) 0)
        empty-sentinel
        (let ((mut (macro-work-stealing-pool-inject-mut pool)))
          (mutex-lock! mut)
          (let ((head (macro-work-stealing-pool-inject-head pool)))
            (if (##pair? head)
                (let ((task (##car head))
                      (next (##cdr head)))
                  (macro-work-stealing-pool-inject-head-set! pool next)
                  (if (##null? next)
                      (macro-work-stealing-pool-inject-tail-set! pool '()))
                  (%fxatom-sub-acqrel! icnt 1)
                  ;; Cascade wakeup if more injected tasks remain and sleepers exist.
                  (if (and (##pair? next)
                           (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0))
                      (condition-variable-signal! (macro-work-stealing-pool-inject-cv pool)))
                  (mutex-unlock! mut)
                  task)
                (begin
                  (mutex-unlock! mut)
                  empty-sentinel)))))))

(define (pool-any-deque-work? pool)
  (let* ((deques (macro-work-stealing-pool-deques pool))
         (n (##vector-length deques)))
    (let loop ((i 0))
      (if (##fx>= i n)
          #f
          (if (##fx> (deque-size-approx (##vector-ref deques i)) 0)
              #t
              (loop (##fx+ i 1)))))))

(define (pool-try-steal pool self-id start-idx)
  (let* ((deques (macro-work-stealing-pool-deques pool))
         (n (##vector-length deques)))
    (let loop ((k 0))
      (if (##fx>= k n)
          empty-sentinel
          (let ((victim (##fxremainder (##fx+ start-idx k) n)))
            (if (##eq? victim self-id)
                (loop (##fx+ k 1))
                (let ((x (deque-steal! (##vector-ref deques victim)
                                       empty-sentinel
                                       abort-sentinel)))
                  (cond ((##eq? x empty-sentinel)
                         (loop (##fx+ k 1)))
                        ((##eq? x abort-sentinel)
                         ;; Contended steal: retry victim once then move on.
                         (let ((x2 (deque-steal! (##vector-ref deques victim)
                                                 empty-sentinel
                                                 abort-sentinel)))
                           (if (or (##eq? x2 empty-sentinel) (##eq? x2 abort-sentinel))
                               (loop (##fx+ k 1))
                               (begin
                                 (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
                                     (pool-wake-one! pool))
                                 x2))))
                        (else
                         ;; Unconditional steal-cascade wakeup if any peer is sleeping.
                         (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
                             (pool-wake-one! pool))
                         x)))))))))

(define (pool-try-get-task pool self-id cursor)
  (let ((deques (macro-work-stealing-pool-deques pool)))
    (let ((local (if (##fixnum? self-id)
                     (deque-pop-bottom! (##vector-ref deques self-id) empty-sentinel)
                     empty-sentinel)))
      (if (##not (##eq? local empty-sentinel))
          local
          (let ((inj (pool-inject-pop! pool)))
            (if (##not (##eq? inj empty-sentinel))
                inj
                (pool-try-steal pool self-id cursor)))))))

(define (pool-run-task! task)
  (if (future? task)
      (future-run-once! task)
      (task)))

(define (pool-worker-loop pool wid)
  (parameterize
   ((current-worker-binding (##cons pool wid)))
   (let ((mut (macro-work-stealing-pool-inject-mut pool))
         (cv (macro-work-stealing-pool-inject-cv pool))
         (icnt (macro-work-stealing-pool-inject-count pool))
         (slp (macro-work-stealing-pool-sleepers pool))
         (shut (macro-work-stealing-pool-shutdown-flag pool))
         (n (macro-work-stealing-pool-nworkers pool)))
     (let loop ((cursor (##fxremainder (##fx+ wid 1) (if (##fx> n 0) n 1)))
                (idle-spins 0))
       (let ((task (pool-try-get-task pool wid cursor)))
         (cond
          ((##not (##eq? task empty-sentinel))
           (pool-run-task! task)
           (loop (##fxremainder (##fx+ cursor 1) n) 0))
          ((##not (##fx= (%fxatom-load-acq shut) 0))
           (##void))
          ((##fx< idle-spins 32)
           (%cpu-pause!)
           (loop (##fxremainder (##fx+ cursor 1) n) (##fx+ idle-spins 1)))
          ((##fx< idle-spins 40)
           (thread-yield!)
           (loop (##fxremainder (##fx+ cursor 1) n) (##fx+ idle-spins 1)))
          (else
           ;; Dekker-fenced park: publish sleepers += 1, seq_cst fence, then re-verify
           ;; shutdown, inject queue, and all peer deques before waiting on condvar.
           (%fxatom-add-acqrel! slp 1)
           (%seq-cst-fence!)
           (if (and (##fx= (%fxatom-load-acq shut) 0)
                    (##fx<= (%fxatom-load-acq icnt) 0)
                    (##not (pool-any-deque-work? pool)))
               (begin
                 (mutex-lock! mut)
                 (if (and (##fx= (%fxatom-load-acq shut) 0)
                          (##null? (macro-work-stealing-pool-inject-head pool))
                          (##not (pool-any-deque-work? pool)))
                     (mutex-unlock! mut cv)
                     (mutex-unlock! mut))))
           (%fxatom-sub-acqrel! slp 1)
           (loop (##fxremainder (##fx+ cursor 1) n) 0))))))))

(define (make-work-stealing-pool #!optional (worker-count #f))
  (let* ((hw (##current-vm-processor-count))
         (n (if (and (##fixnum? worker-count) (##fx> worker-count 0))
                worker-count
                (if (##fx> hw 0) hw 1)))
         (deques (##make-vector n #f)))
    (let init-d ((i 0))
      (if (##fx< i n)
          (begin
            (##vector-set! deques i (make-work-stealing-deque 64))
            (init-d (##fx+ i 1)))))
    (let* ((pool (macro-make-work-stealing-pool
                  n
                  deques
                  #f
                  (make-mutex 'work-stealing-pool)
                  (make-condition-variable 'work-stealing-pool-cv)
                  '()
                  '()
                  (%make-padded-fxatom 0)
                  (%make-padded-fxatom 0)
                  (%make-padded-fxatom 0)))
           (threads (##make-vector n #f)))
      (macro-work-stealing-pool-threads-set! pool threads)
      (let spawn ((i 0))
        (if (##fx< i n)
            (let ((th (make-thread
                       (lambda () (pool-worker-loop pool i))
                       (##list 'ws-worker i))))
              (##vector-set! threads i th)
              (thread-start! th)
              (spawn (##fx+ i 1)))))
      pool)))

(define (work-stealing-pool? obj)
  (macro-work-stealing-pool? obj))

(define (work-stealing-pool-worker-count pool)
  (macro-work-stealing-pool-nworkers pool))

(define (work-stealing-pool-shutdown! pool)
  (%fxatom-store-rel! (macro-work-stealing-pool-shutdown-flag pool) 1)
  (%seq-cst-fence!)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool)))
    (mutex-lock! mut)
    (condition-variable-broadcast! cv)
    (mutex-unlock! mut))
  (let* ((threads (macro-work-stealing-pool-threads pool))
         (n (##vector-length threads)))
    (let join ((i 0))
      (if (##fx< i n)
          (begin
            (thread-join! (##vector-ref threads i))
            (join (##fx+ i 1))))))
  (##void))

(define (pool-submit! pool task)
  (let ((wb (current-worker-binding)))
    (if (and (##pair? wb) (##eq? (##car wb) pool))
        (let ((wid (##cdr wb)))
          ;; Sole owner pushes directly onto its 128B-padded Chase-Lev deque
          ;; (zero global counter writes, zero mutex locks while peers are busy!).
          (deque-push-bottom!
           (##vector-ref (macro-work-stealing-pool-deques pool) wid)
           task)
          (%seq-cst-fence!)
          (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
              (pool-wake-one! pool)))
        (pool-inject-push! pool task))))

;; Lazy default pool (initialized safely on first use via atomic CAS / mutex).
(define default-pool-mut (make-mutex 'default-ws-pool))
(define default-pool-box (make-atomic-box #f))
(define current-work-stealing-pool (make-parameter #f))

(define (get-active-pool)
  (let ((p (current-work-stealing-pool)))
    (if (macro-work-stealing-pool? p)
        p
        (let ((d (atomic-box-ref default-pool-box 'acquire)))
          (if d
              d
              (begin
                (mutex-lock! default-pool-mut)
                (let ((d2 (atomic-box-ref default-pool-box 'acquire)))
                  (if d2
                      (begin (mutex-unlock! default-pool-mut) d2)
                      (let ((created (make-work-stealing-pool)))
                        (atomic-box-set! default-pool-box created 'release)
                        (mutex-unlock! default-pool-mut)
                        created)))))))))

;;;============================================================================
;;; Part 3: Single-Allocation Futures with Work-Stealing Helping & Exceptions
;;;============================================================================

(##define-type ws-future
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000003
  type-exhibitor: macro-type-ws-future
  constructor: macro-make-ws-future
  implementer: implement-type-ws-future
  macros:
  prefix: macro-
  opaque:
  (pool  read-only: unprintable:)
  (thunk read-only: unprintable:)
  (state unprintable:))
(implement-type-ws-future)

;; Inline C23 atomic state ops on field 3 of ws-future (eliminates atomic-box alloc)
(define (%future-state-load-acq f)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, &___f[3]), 1));"
    f)
   (atomic-box-ref (macro-ws-future-state f) 'acquire)))

(define (%future-state-cas-acqrel! f expected desired)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___GC_WRITE_BARRIER(___ps, ___ARG1, &___f[3], ___ARG3);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, &___f[3]),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 3));"
    f expected desired)
   (atomic-box-compare-and-swap! (macro-ws-future-state f) expected desired 'acquire-release)))

(define (%future-state-store-rel! f val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___GC_WRITE_BARRIER(___ps, ___ARG1, &___f[3], ___ARG2);
     ___atomic_word_store(___CAST(___VOLATILE ___WORD*, &___f[3]),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    f val)
   (atomic-box-set! (macro-ws-future-state f) val 'release)))

(define (%make-future-state)
  (macro-if-c-compiled
   pending-sentinel
   (make-atomic-box pending-sentinel)))

(define (future? obj)
  (macro-ws-future? obj))

(define (future-ready? f)
  (##pair? (%future-state-load-acq f)))

(define (future-run-once! f)
  (let ((prev (%future-state-cas-acqrel! f pending-sentinel running-sentinel)))
    (if (##eq? prev pending-sentinel)
        (let ((result
               (with-exception-catcher
                (lambda (exc) (##cons 'err exc))
                (lambda () (##cons 'ok ((macro-ws-future-thunk f)))))))
          (%future-state-store-rel! f result)
          #t)
        #f)))

(define (make-future thunk #!optional (pool #f))
  (let* ((p (if (macro-work-stealing-pool? pool) pool (get-active-pool)))
         (f (macro-make-ws-future p thunk (%make-future-state))))
    ;; Push future directly (zero wrapper closure allocation!).
    (pool-submit! p f)
    f))

(define (future-force f)
  (let ((pool (macro-ws-future-pool f)))
    ;; Fast path: already completed.
    (let ((st0 (%future-state-load-acq f)))
      (if (##pair? st0)
          (if (##eq? (##car st0) 'ok) (##cdr st0) (raise (##cdr st0)))
          (begin
            ;; Try claiming & running this future directly (zero-deadlock helping!).
            (future-run-once! f)
            ;; While another thread is running this future, help execute work!
            (let* ((wb (current-worker-binding))
                   (self-id (if (and (##pair? wb) (##eq? (##car wb) pool))
                                (##cdr wb)
                                #f))
                   (n (macro-work-stealing-pool-nworkers pool)))
              (let wait ((cursor 0) (spins 0))
                (let ((st (%future-state-load-acq f)))
                  (if (##pair? st)
                      (if (##eq? (##car st) 'ok) (##cdr st) (raise (##cdr st)))
                      (let ((task (pool-try-get-task pool self-id cursor)))
                        (if (##not (##eq? task empty-sentinel))
                            (begin
                              (pool-run-task! task)
                              (wait (##fxremainder (##fx+ cursor 1) n) 0))
                            (if (##fx< spins 16)
                                (begin
                                  (%cpu-pause!)
                                  (wait (##fxremainder (##fx+ cursor 1) n) (##fx+ spins 1)))
                                (begin
                                  (thread-yield!)
                                  (wait (##fxremainder (##fx+ cursor 1) n) 0))))))))))))))

(define (force-future f)
  (future-force f))

;;;============================================================================
;;; Part 4: Structured Fork-Join Combinators (Exception-Quiescent Join)
;;;============================================================================

(define (default-grain n workers)
  (let* ((chunks (##fx* workers 4))
         (g (if (##fx> chunks 0) (##fxquotient n chunks) n)))
    (if (##fx> g 1) g 1)))

(define (parallel-vector-map fn vec #!optional (grain #f))
  (let* ((n (##vector-length vec))
         (out (##make-vector n #f)))
    (if (##fx= n 0)
        out
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (if (or (##fx<= w 1) (##fx<= n g))
              (let seq ((i 0))
                (if (##fx< i n)
                    (begin
                      (##vector-set! out i (fn (##vector-ref vec i)))
                      (seq (##fx+ i 1)))
                    out))
              (letrec ((run-range
                        (lambda (lo hi)
                          (if (##fx<= (##fx- hi lo) g)
                              (let loop ((i lo))
                                (if (##fx< i hi)
                                    (begin
                                      (##vector-set! out i (fn (##vector-ref vec i)))
                                      (loop (##fx+ i 1)))))
                              (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                     (right (make-future (lambda () (run-range mid hi)) pool))
                                     (left-err #f)
                                     (has-err #f))
                                (with-exception-catcher
                                 (lambda (e) (set! left-err e) (set! has-err #t))
                                 (lambda () (run-range lo mid)))
                                (if has-err
                                    (begin
                                      (with-exception-catcher
                                       (lambda (_) #f)
                                       (lambda () (future-force right)))
                                      (raise left-err))
                                    (future-force right)))))))
                (run-range 0 n)
                out))))))

(define (parallel-map fn lst #!optional (grain #f))
  (if (##null? lst)
      '()
      (##vector->list (parallel-vector-map fn (##list->vector lst) grain))))

(define (parallel-for-each fn lst #!optional (grain #f))
  (if (##null? lst)
      (##void)
      (let* ((vec (##list->vector lst))
             (n (##vector-length vec))
             (pool (get-active-pool))
             (w (macro-work-stealing-pool-nworkers pool))
             (g (if (and (##fixnum? grain) (##fx> grain 0))
                    grain
                    (default-grain n w))))
        (if (or (##fx<= w 1) (##fx<= n g))
            (let seq ((i 0))
              (if (##fx< i n)
                  (begin (fn (##vector-ref vec i)) (seq (##fx+ i 1)))
                  (##void)))
            (letrec ((run-range
                      (lambda (lo hi)
                        (if (##fx<= (##fx- hi lo) g)
                            (let loop ((i lo))
                              (if (##fx< i hi)
                                  (begin (fn (##vector-ref vec i)) (loop (##fx+ i 1)))))
                            (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                   (right (make-future (lambda () (run-range mid hi)) pool))
                                   (left-err #f)
                                   (has-err #f))
                              (with-exception-catcher
                               (lambda (e) (set! left-err e) (set! has-err #t))
                               (lambda () (run-range lo mid)))
                              (if has-err
                                  (begin
                                    (with-exception-catcher
                                     (lambda (_) #f)
                                     (lambda () (future-force right)))
                                    (raise left-err))
                                  (future-force right)))))))
              (run-range 0 n)
              (##void))))))

(define (parallel-reduce combine identity seq-or-vec #!optional (grain #f))
  (let* ((vec (if (##vector? seq-or-vec) seq-or-vec (##list->vector seq-or-vec)))
         (n (##vector-length vec)))
    (if (##fx= n 0)
        identity
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (letrec ((reduce-range
                    (lambda (lo hi)
                      (if (or (##fx<= w 1) (##fx<= (##fx- hi lo) g))
                          (let loop ((i lo) (acc identity))
                            (if (##fx< i hi)
                                (loop (##fx+ i 1) (combine acc (##vector-ref vec i)))
                                acc))
                          (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                 (right (make-future (lambda () (reduce-range mid hi)) pool))
                                 (left-err #f)
                                 (has-err #f)
                                 (lv #f))
                            (with-exception-catcher
                             (lambda (e) (set! left-err e) (set! has-err #t))
                             (lambda () (set! lv (reduce-range lo mid))))
                            (if has-err
                                (begin
                                  (with-exception-catcher
                                   (lambda (_) #f)
                                   (lambda () (future-force right)))
                                  (raise left-err))
                                (combine lv (future-force right))))))))
            (reduce-range 0 n))))))

;;;============================================================================
