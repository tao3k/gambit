;;;============================================================================

;;; File: "concurrent.scm"

;;; Lock-Free SMP Concurrent Data Structures built directly on C23 atomic
;;; operations and Gambit SMP GC write barriers, with pure-Scheme fallback
;;; when interpreted without precompiled C modules.

(##supply-module gambit/concurrent)

(##namespace ("gambit/concurrent#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "concurrent#.scm")

(declare (extended-bindings))
(declare (not safe))
(declare (block))

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

;; 128-byte padded fixnum atomic counter (eliminates false sharing on Apple Silicon / x86)
(define (%make-padded-ctr init)
  (let ((v (##make-vector 16 0)))
    (##vector-set! v 0 init)
    v))

(##define-macro (%ctr-load-acq c)
  `(macro-if-c-compiled
    (##c-code
     "___RESULT = ___CAST(___SCMOBJ,
        ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 1));"
     ,c)
    (##vector-cas! ,c 0 #!unbound #!unbound)))

(##define-macro (%ctr-add-rlx! c delta)
  `(macro-if-c-compiled
    (##c-code
     "___RESULT = ___CAST(___SCMOBJ,
        ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                  ___CAST(___WORD, ___ARG2), 0));"
     ,c ,delta)
    (##vector-inc! ,c 0 ,delta)))

(##define-macro (%ctr-sub-rlx! c delta)
  `(macro-if-c-compiled
    (##c-code
     "___RESULT = ___CAST(___SCMOBJ,
        ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                  ___CAST(___WORD, ___ARG2), 0));"
     ,c ,delta)
    (let ((cv ,c) (d ,delta))
      (let loop ((old (##vector-cas! cv 0 #!unbound #!unbound)))
        (let ((prev (##vector-cas! cv 0 (##fx- old d) old)))
          (if (##eq? prev old) old (loop prev)))))))

(##define-macro (%slot-load-acq vec idx)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
      ___RESULT = ___gc_atomic_slot_load(___s, 1);"
     ,vec ,idx)
    (##vector-cas! ,vec ,idx #!unbound #!unbound)))

(##define-macro (%slot-cas-acqrel! vec idx expected desired)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
      ___RESULT = ___gc_atomic_slot_cas(
        ___ps, ___ARG1, ___s, ___ARG3, ___ARG4, 3,
        ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));"
     ,vec ,idx ,expected ,desired)
    (##vector-cas! ,vec ,idx ,desired ,expected)))

(define (%raise-bad-type type-id proc x)
  (##raise-type-exception 1 type-id proc (##list x)))

;;;============================================================================
;;; 1. Lock-Free Treiber Stack (GC-managed nodes -> immune to ABA)

(##define-type lf-stack
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000001
  type-exhibitor: macro-type-lf-stack
  constructor: macro-make-lf-stack
  implementer: implement-type-lf-stack
  macros:
  prefix: macro-
  opaque:
  (head unprintable: read-only:))
(implement-type-lf-stack)

(define (make-lf-stack)
  (macro-make-lf-stack (##make-vector 16 '())))

(define (lf-stack? obj)
  (macro-lf-stack? obj))

(define (lf-stack-empty? st)
  (if (##not (macro-lf-stack? st))
      (%raise-bad-type (macro-type-lf-stack) lf-stack-empty? st))
  (##null? (%slot-load-acq (macro-lf-stack-head st) 0)))

(define (lf-stack-push! st val)
  (if (##not (macro-lf-stack? st))
      (%raise-bad-type (macro-type-lf-stack) lf-stack-push! st))
  (let ((head (macro-lf-stack-head st)))
    (let loop ()
      (let* ((cur (%slot-load-acq head 0))
             (nxt (##cons val cur))
             (prev (%slot-cas-acqrel! head 0 cur nxt)))
        (if (##eq? prev cur)
            #t
            (loop))))))

;; Returns (values #t val) on success, or (values #f #f) when empty.
(define (lf-stack-try-pop! st)
  (if (##not (macro-lf-stack? st))
      (%raise-bad-type (macro-type-lf-stack) lf-stack-try-pop! st))
  (let ((head (macro-lf-stack-head st)))
    (let loop ()
      (let ((cur (%slot-load-acq head 0)))
        (if (##null? cur)
            (##values #f #f)
            (let ((prev (%slot-cas-acqrel! head 0 cur (##cdr cur))))
              (if (##eq? prev cur)
                  (##values #t (##car cur))
                  (loop))))))))

;;;============================================================================
;;; 2. Lock-Free Unbounded Segmented MPMC FIFO Queue (128-slot movable segments)
;;;
;;; Each segment is a 4-element vector: #(base slots states next)
;;;   [0] base   : immutable fixnum start ticket (k * 128)
;;;   [1] slots  : 128-element movable payload vector (cleared to #f upon dequeue)
;;;   [2] states : 128-element movable atomic fixnum state vector (0=EMPTY, 1=READY)
;;;   [3] next   : #f or lazily CAS-linked next segment
;;; (128 words stays strictly below Gambit's still-object threshold so every
;;;  segment allocates via fast movable bump-pointer nursery allocation.)
;;;
;;; Queue holds two 128-byte padded control vectors:
;;;   head-ctr : #(head_ticket head_seg 0 ... 0)
;;;   tail-ctr : #(tail_ticket tail_seg 0 ... 0)

(##define-type lf-queue
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000003
  type-exhibitor: macro-type-lf-queue
  constructor: macro-make-lf-queue
  implementer: implement-type-lf-queue
  macros:
  prefix: macro-
  opaque:
  (head unprintable: read-only:)
  (tail unprintable: read-only:))
(implement-type-lf-queue)

(define %lfq-empty (##cons 'lfq-empty 'lfq-empty))
(define %lfq-retry (##cons 'lfq-retry 'lfq-retry))

(define (%make-lf-qseg base)
  (##vector base
            (##make-vector 128 #f)
            (##make-vector 128 0)
            #f))

(define (make-lf-queue)
  (let* ((seg0 (%make-lf-qseg 0))
         (hc (##make-vector 16 0))
         (tc (##make-vector 16 0)))
    (##vector-set! hc 1 seg0)
    (##vector-set! tc 1 seg0)
    (macro-make-lf-queue hc tc)))

(define (lf-queue? obj)
  (macro-lf-queue? obj))

(define (lf-queue-empty? q)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-empty? q))
  (let ((h (%ctr-load-acq (macro-lf-queue-head q)))
        (t (%ctr-load-acq (macro-lf-queue-tail q))))
    (##fx>= h t)))

;; Returns #t if enqueued, #f to yield/retry, or `seg` needing seg[3] allocation.
(##define-macro (%lfq-enq-fast! tc val)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ tc = ___ARG1;
      ___SCMOBJ val = ___ARG2;
      ___WORD *tvec = ___BODY_AS(tc, ___tVECTOR);
      ___VOLATILE ___WORD *tt_p = ___CAST(___VOLATILE ___WORD*, &tvec[0]);
      ___WORD *tseg_p = &tvec[1];
      int spins = 0;
      for (;;) {
        ___SCMOBJ seg = ___gc_atomic_slot_load(tseg_p, 1);
        ___WORD *svec = ___BODY_AS(seg, ___tVECTOR);
        ___WORD base = ___INT(svec[0]);
        ___WORD t_fix = ___atomic_word_load(tt_p, 1);
        ___WORD t = ___INT(t_fix);
        ___WORD off = t - base;
        if (off < 0) {
          if (++spins >= 64) { ___RESULT = ___FAL; break; }
          ___CPU_RELAX();
          continue;
        }
        if (off >= 128) {
          ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[3], 1);
          if (nxt == ___FAL) {
            ___RESULT = seg;
            break;
          }
          (void)___gc_atomic_slot_cas(
            ___ps, tc, tseg_p, seg, nxt, 2,
            ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
          if (++spins >= 64) { ___RESULT = ___FAL; break; }
          continue;
        }
        if (___atomic_word_cas(tt_p, t_fix, ___FIX(t + 1), 3) == t_fix) {
          ___SCMOBJ slots = svec[1];
          ___SCMOBJ states = svec[2];
          ___WORD *slot_ptr = ___BODY_AS(slots, ___tVECTOR) + off;
          ___VOLATILE ___WORD *st_ptr =
            ___CAST(___VOLATILE ___WORD*, ___BODY_AS(states, ___tVECTOR) + off);
          ___GC_WRITE_BARRIER(___ps, slots, slot_ptr, val);
          ___atomic_word_store(___CAST(___VOLATILE ___WORD*, slot_ptr), ___CAST(___WORD, val), 0);
          ___atomic_word_store(st_ptr, ___FIX(1), 2);
          if (off == 127) {
            ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[3], 1);
            if (nxt != ___FAL) {
              (void)___gc_atomic_slot_cas(
                ___ps, tc, tseg_p, seg, nxt, 2,
                ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
            }
          }
          ___RESULT = ___TRU;
          break;
        }
        if (++spins >= 64) { ___RESULT = ___FAL; break; }
        ___CPU_RELAX();
      }"
     ,tc ,val)
    ;; Interpreted fallback
    (let* ((seg (%slot-load-acq ,tc 1))
           (base (##vector-ref seg 0))
           (t (%ctr-load-acq ,tc))
           (off (##fx- t base)))
      (cond
        ((##fx< off 0) #f)
        ((##fx>= off 128)
         (let ((nxt (%slot-load-acq seg 3)))
           (if nxt
               (begin (%slot-cas-acqrel! ,tc 1 seg nxt) #f)
               seg)))
        (else
         (let ((prev (##vector-cas! ,tc 0 (##fx+ t 1) t)))
           (if (##fx= prev t)
               (let ((slots (##vector-ref seg 1))
                     (states (##vector-ref seg 2)))
                 (##vector-set! slots off ,val)
                 (##vector-cas! states off 1 0)
                 #t)
               #f)))))))

(define (lf-queue-enqueue! q val)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-enqueue! q))
  (let ((tc (macro-lf-queue-tail q)))
    (let loop ()
      (let ((r (%lfq-enq-fast! tc val)))
        (cond
          ((##eq? r #t) #t)
          ((##eq? r #f) (loop))
          (else
           ;; `r` is the tail segment needing a lazily linked successor
           (let* ((next-base (##fx+ (##vector-ref r 0) 128))
                  (new-seg (%make-lf-qseg next-base))
                  (prev (%slot-cas-acqrel! r 3 #f new-seg))
                  (winner (if (##not prev) new-seg prev)))
             (%slot-cas-acqrel! tc 1 r winner)
             (loop))))))))

;; Returns dequeued item, `empty-sent` if empty, or `retry-sent` to retry in Scheme.
(##define-macro (%lfq-deq-fast! hc tc empty-sent retry-sent)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ hc = ___ARG1;
      ___SCMOBJ tc = ___ARG2;
      ___SCMOBJ empty_sent = ___ARG3;
      ___SCMOBJ retry_sent = ___ARG4;
      ___WORD *hvec = ___BODY_AS(hc, ___tVECTOR);
      ___WORD *tvec = ___BODY_AS(tc, ___tVECTOR);
      ___VOLATILE ___WORD *ht_p = ___CAST(___VOLATILE ___WORD*, &hvec[0]);
      ___WORD *hseg_p = &hvec[1];
      ___VOLATILE ___WORD *tt_p = ___CAST(___VOLATILE ___WORD*, &tvec[0]);
      int spins = 0;
      for (;;) {
        ___SCMOBJ seg = ___gc_atomic_slot_load(hseg_p, 1);
        ___WORD *svec = ___BODY_AS(seg, ___tVECTOR);
        ___WORD base = ___INT(svec[0]);
        ___WORD h_fix = ___atomic_word_load(ht_p, 1);
        ___WORD h = ___INT(h_fix);
        ___WORD t = ___INT(___atomic_word_load(tt_p, 1));
        if (h >= t) {
          ___RESULT = empty_sent;
          break;
        }
        ___WORD off = h - base;
        if (off < 0) {
          if (++spins >= 64) { ___RESULT = retry_sent; break; }
          ___CPU_RELAX();
          continue;
        }
        if (off >= 128) {
          ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[3], 1);
          if (nxt == ___FAL) {
            ___RESULT = retry_sent;
            break;
          }
          (void)___gc_atomic_slot_cas(
            ___ps, hc, hseg_p, seg, nxt, 2,
            ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
          if (++spins >= 64) { ___RESULT = retry_sent; break; }
          continue;
        }
        /* Verify producer has already release-published states[off] == 1 BEFORE
         * claiming ticket h so a preempted producer can never trap a consumer. */
        {
          ___SCMOBJ states = svec[2];
          ___VOLATILE ___WORD *st_ptr =
            ___CAST(___VOLATILE ___WORD*, ___BODY_AS(states, ___tVECTOR) + off);
          if (___atomic_word_load(st_ptr, 1) == ___FIX(0)) {
            if (++spins >= 32) { ___RESULT = retry_sent; break; }
            ___CPU_RELAX();
            continue;
          }
        }
        if (___atomic_word_cas(ht_p, h_fix, ___FIX(h + 1), 3) == h_fix) {
          ___SCMOBJ slots = svec[1];
          ___WORD *slot_ptr = ___BODY_AS(slots, ___tVECTOR) + off;
          ___SCMOBJ val =
            ___CAST(___SCMOBJ, ___atomic_word_load(___CAST(___VOLATILE ___WORD*, slot_ptr), 0));
          ___GC_WRITE_BARRIER(___ps, slots, slot_ptr, ___FAL);
          ___atomic_word_store(___CAST(___VOLATILE ___WORD*, slot_ptr), ___CAST(___WORD, ___FAL), 0);
          if (off == 127) {
            ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[3], 1);
            if (nxt != ___FAL) {
              (void)___gc_atomic_slot_cas(
                ___ps, hc, hseg_p, seg, nxt, 2,
                ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
            }
          }
          ___RESULT = val;
          break;
        }
        if (++spins >= 64) { ___RESULT = retry_sent; break; }
        ___CPU_RELAX();
      }"
     ,hc ,tc ,empty-sent ,retry-sent)
    ;; Interpreted fallback
    (let* ((seg (%slot-load-acq ,hc 1))
           (base (##vector-ref seg 0))
           (h (%ctr-load-acq ,hc))
           (t (%ctr-load-acq ,tc)))
      (if (##fx>= h t)
          ,empty-sent
          (let ((off (##fx- h base)))
            (cond
              ((##fx< off 0) ,retry-sent)
              ((##fx>= off 128)
               (let ((nxt (%slot-load-acq seg 3)))
                 (if nxt (%slot-cas-acqrel! ,hc 1 seg nxt))
                 ,retry-sent))
              (else
               (let ((states (##vector-ref seg 2)))
                 (if (##fx= (%slot-load-acq states off) 0)
                     ,retry-sent
                     (let ((prev (##vector-cas! ,hc 0 (##fx+ h 1) h)))
                       (if (##fx= prev h)
                           (let* ((slots (##vector-ref seg 1))
                                  (val (##vector-ref slots off)))
                             (##vector-set! slots off #f)
                             val)
                           ,retry-sent)))))))))))

;; Returns (values #t val) on success, or (values #f #f) when empty.
(define (lf-queue-try-dequeue! q)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-try-dequeue! q))
  (let ((hc (macro-lf-queue-head q))
        (tc (macro-lf-queue-tail q)))
    (let loop ()
      (let ((r (%lfq-deq-fast! hc tc %lfq-empty %lfq-retry)))
        (cond
          ((##eq? r %lfq-empty) (##values #f #f))
          ((##eq? r %lfq-retry) (loop))
          (else (##values #t r)))))))

;; Zero-closure single-value variant: returns dequeued value or `default` when empty.
(define (lf-queue-try-dequeue-or! q default)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-try-dequeue-or! q))
  (let ((hc (macro-lf-queue-head q))
        (tc (macro-lf-queue-tail q)))
    (let loop ()
      (let ((r (%lfq-deq-fast! hc tc %lfq-empty %lfq-retry)))
        (cond
          ((##eq? r %lfq-empty) default)
          ((##eq? r %lfq-retry) (loop))
          (else r))))))

;;;============================================================================
;;; 3. Lock-Free Bounded Chase-Lev Work-Stealing Deque (Single-Block C23 Fast Path)

(##define-type ws-deque
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000004
  type-exhibitor: macro-type-ws-deque
  constructor: macro-make-ws-deque
  implementer: implement-type-ws-deque
  macros:
  prefix: macro-
  opaque:
  (mask   unprintable: read-only:)
  (cap    unprintable: read-only:)
  (slots  unprintable: read-only:)
  (top    unprintable: read-only:)
  (bottom unprintable: read-only:))
(implement-type-ws-deque)

(define %ws-empty (##cons 'ws-empty 'ws-empty))

(define (%next-pow2 n)
  (let loop ((p 16))
    (if (##fx>= p n) p (loop (##fx* p 2)))))

(define (make-ws-deque #!optional (min-cap 256))
  (let* ((cap (%next-pow2 (if (and (##fixnum? min-cap) (##fx> min-cap 0)) min-cap 256)))
         (slots (##make-vector cap #f)))
    (macro-make-ws-deque (##fx- cap 1) cap slots
                         (%make-padded-ctr 0)
                         (%make-padded-ctr 0))))

(define (ws-deque? obj)
  (macro-ws-deque? obj))

(define (ws-deque-size dq)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-size dq))
  (let ((b (%ctr-load-acq (macro-ws-deque-bottom dq)))
        (t (%ctr-load-acq (macro-ws-deque-top dq))))
    (let ((d (##fx- b t)))
      (if (##fx> d 0) d 0))))

;; Owner-only push at bottom. Returns #t on success, #f if bounded ring is full.
(define (ws-deque-push! dq val)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-push! dq))
  (macro-if-c-compiled
   (##c-code
    "___WORD *bvec = ___BODY_AS(___ARG1, ___tVECTOR);
     ___WORD *tvec = ___BODY_AS(___ARG2, ___tVECTOR);
     ___SCMOBJ slots = ___ARG3;
     ___WORD mask = ___INT(___ARG4);
     ___WORD cap = ___INT(___ARG5);
     ___SCMOBJ val = ___ARG6;
     ___VOLATILE ___WORD *bp = ___CAST(___VOLATILE ___WORD*, &bvec[0]);
     ___VOLATILE ___WORD *tp = ___CAST(___VOLATILE ___WORD*, &tvec[0]);
     ___WORD b = ___INT(___atomic_word_load(bp, 0));
     ___WORD t = ___INT(___atomic_word_load(tp, 1));
     if (b - t >= cap) {
       ___RESULT = ___FAL;
     } else {
       ___WORD *sp = ___BODY_AS(slots, ___tVECTOR) + (b & mask);
       ___GC_WRITE_BARRIER(___ps, slots, sp, val);
       ___atomic_word_store(___CAST(___VOLATILE ___WORD*, sp), ___CAST(___WORD, val), 0);
       ___atomic_word_store(bp, ___FIX(b + 1), 2);
       ___RESULT = ___TRU;
     }"
    (macro-ws-deque-bottom dq) (macro-ws-deque-top dq) (macro-ws-deque-slots dq)
    (macro-ws-deque-mask dq) (macro-ws-deque-cap dq) val)
   (let* ((bot-box (macro-ws-deque-bottom dq))
          (b (%ctr-load-acq bot-box))
          (t (%ctr-load-acq (macro-ws-deque-top dq)))
          (cap (macro-ws-deque-cap dq)))
     (if (##fx>= (##fx- b t) cap)
         #f
         (begin
           (srfi/230#vector-atomic-set! (macro-ws-deque-slots dq) (##fxand b (macro-ws-deque-mask dq)) val (memory-order relaxed))
           (let loop ((old (##vector-cas! bot-box 0 #!unbound #!unbound)))
             (let ((prev (##vector-cas! bot-box 0 (##fx+ b 1) old)))
               (if (##eq? prev old) #t (loop prev)))))))))

(##define-macro (%ws-pop-raw! dq empty-sent)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *bvec = ___BODY_AS(___ARG1, ___tVECTOR);
      ___WORD *tvec = ___BODY_AS(___ARG2, ___tVECTOR);
      ___SCMOBJ slots = ___ARG3;
      ___WORD mask = ___INT(___ARG4);
      ___SCMOBJ empty_sent = ___ARG5;
      ___VOLATILE ___WORD *bp = ___CAST(___VOLATILE ___WORD*, &bvec[0]);
      ___VOLATILE ___WORD *tp = ___CAST(___VOLATILE ___WORD*, &tvec[0]);
      ___WORD b = ___INT(___atomic_word_load(bp, 0)) - 1;
      ___atomic_word_store(bp, ___FIX(b), 0);
      ___atomic_fence_order(4);
      ___WORD t = ___INT(___atomic_word_load(tp, 0));
      if (t <= b) {
        ___WORD *sp = ___BODY_AS(slots, ___tVECTOR) + (b & mask);
        ___SCMOBJ val = ___gc_atomic_slot_load(sp, 1);
        if (t == b) {
          if (___atomic_word_cas(tp, ___FIX(t), ___FIX(t + 1), 4) != ___FIX(t)) {
            val = empty_sent;
          }
          ___atomic_word_store(bp, ___FIX(b + 1), 0);
        }
        ___RESULT = val;
      } else {
        ___atomic_word_store(bp, ___FIX(b + 1), 0);
        ___RESULT = empty_sent;
      }"
     (macro-ws-deque-bottom ,dq) (macro-ws-deque-top ,dq) (macro-ws-deque-slots ,dq)
     (macro-ws-deque-mask ,dq) ,empty-sent)
    (let* ((bot-box (macro-ws-deque-bottom ,dq))
           (b (##fx- (%ctr-load-acq bot-box) 1))
           (top-box (macro-ws-deque-top ,dq))
           (slots (macro-ws-deque-slots ,dq))
           (idx (##fxand b (macro-ws-deque-mask ,dq))))
      (let loop ((old (##vector-cas! bot-box 0 #!unbound #!unbound)))
        (let ((prev (##vector-cas! bot-box 0 b old)))
          (if (##not (##eq? prev old)) (loop prev))))
      (let ((t (%ctr-load-acq top-box)))
        (cond
          ((##fx< t b)
           (%slot-load-acq slots idx))
          ((##fx= t b)
           (let* ((val (%slot-load-acq slots idx))
                  (prev (##vector-cas! top-box 0 (##fx+ t 1) t)))
             (let loop ((old (##vector-cas! bot-box 0 #!unbound #!unbound)))
               (let ((prev2 (##vector-cas! bot-box 0 (##fx+ b 1) old)))
                 (if (##not (##eq? prev2 old)) (loop prev2))))
             (if (##fx= prev t) val ,empty-sent)))
          (else
           (let loop ((old (##vector-cas! bot-box 0 #!unbound #!unbound)))
             (let ((prev2 (##vector-cas! bot-box 0 (##fx+ b 1) old)))
               (if (##not (##eq? prev2 old)) (loop prev2))))
           ,empty-sent))))))

(##define-macro (%ws-steal-raw! dq empty-sent)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *tvec = ___BODY_AS(___ARG1, ___tVECTOR);
      ___WORD *bvec = ___BODY_AS(___ARG2, ___tVECTOR);
      ___SCMOBJ slots = ___ARG3;
      ___WORD mask = ___INT(___ARG4);
      ___SCMOBJ empty_sent = ___ARG5;
      ___VOLATILE ___WORD *tp = ___CAST(___VOLATILE ___WORD*, &tvec[0]);
      ___VOLATILE ___WORD *bp = ___CAST(___VOLATILE ___WORD*, &bvec[0]);
      ___WORD t = ___INT(___atomic_word_load(tp, 1));
      ___WORD b_peek = ___INT(___atomic_word_load(bp, 0));
      if (t >= b_peek) {
        ___RESULT = empty_sent;
      } else {
        ___atomic_fence_order(4);
        ___WORD b = ___INT(___atomic_word_load(bp, 1));
        if (t < b) {
          ___WORD *sp = ___BODY_AS(slots, ___tVECTOR) + (t & mask);
          ___SCMOBJ val = ___gc_atomic_slot_load(sp, 1);
          if (___atomic_word_cas(tp, ___FIX(t), ___FIX(t + 1), 4) == ___FIX(t)) {
            ___RESULT = val;
          } else {
            ___RESULT = empty_sent;
          }
        } else {
          ___RESULT = empty_sent;
        }
      }"
     (macro-ws-deque-top ,dq) (macro-ws-deque-bottom ,dq) (macro-ws-deque-slots ,dq)
     (macro-ws-deque-mask ,dq) ,empty-sent)
    (let* ((top-box (macro-ws-deque-top ,dq))
           (bot-box (macro-ws-deque-bottom ,dq))
           (t (%ctr-load-acq top-box))
           (b (%ctr-load-acq bot-box)))
      (if (##fx< t b)
          (let* ((val (%slot-load-acq (macro-ws-deque-slots ,dq) (##fxand t (macro-ws-deque-mask ,dq))))
                 (prev (##vector-cas! top-box 0 (##fx+ t 1) t)))
            (if (##fx= prev t) val ,empty-sent))
          ,empty-sent))))

;; Owner-only LIFO pop from bottom. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-pop! dq)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-try-pop! dq))
  (let ((r (%ws-pop-raw! dq %ws-empty)))
    (if (##eq? r %ws-empty)
        (##values #f #f)
        (##values #t r))))

;; Concurrent thief FIFO steal from top. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-steal! dq)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-try-steal! dq))
  (let ((r (%ws-steal-raw! dq %ws-empty)))
    (if (##eq? r %ws-empty)
        (##values #f #f)
        (##values #t r))))

;; Zero-closure owner-only LIFO pop: returns popped item or `default` when empty.
(define (ws-deque-try-pop-or! dq default)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-try-pop-or! dq))
  (let ((r (%ws-pop-raw! dq %ws-empty)))
    (if (##eq? r %ws-empty) default r)))

;; Zero-closure concurrent thief FIFO steal: returns stolen item or `default` when empty.
(define (ws-deque-try-steal-or! dq default)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-try-steal-or! dq))
  (let ((r (%ws-steal-raw! dq %ws-empty)))
    (if (##eq? r %ws-empty) default r)))

;;;============================================================================
;;; 4. Wait-Free-Read / Lock-Free-Write Sharded Concurrent Hash Table

(##define-type concurrent-table
  id: 8B4E21C0-5F39-4E1A-A001-C04C00000005
  type-exhibitor: macro-type-concurrent-table
  constructor: macro-make-concurrent-table
  implementer: implement-type-concurrent-table
  macros:
  prefix: macro-
  opaque:
  (mask      unprintable: read-only:)
  (buckets   unprintable: read-only:)
  (eq-fn     unprintable: read-only:)
  (hash-fn   unprintable: read-only:)
  (count     unprintable: read-only:)
  (fast-mode unprintable: read-only:))
(implement-type-concurrent-table)

(define (make-concurrent-table #!optional (min-buckets 64) (eq-fn equal?) (hash-fn equal?-hash))
  (let* ((nb (%next-pow2 (if (and (##fixnum? min-buckets) (##fx> min-buckets 0)) min-buckets 64)))
         (buckets (##make-vector nb '()))
         (fast? (or (and (##eq? eq-fn equal?) (##eq? hash-fn equal?-hash))
                    (and (##eq? eq-fn eq?) (##eq? hash-fn eq?-hash)))))
    (macro-make-concurrent-table (##fx- nb 1) buckets eq-fn hash-fn (%make-padded-ctr 0) fast?)))

(define (concurrent-table? obj)
  (macro-concurrent-table? obj))

(##define-macro (%ct-fixnum-hash key mask)
  `(macro-if-c-compiled
    (##c-code
     "___U64 h = ___CAST(___U64, ___CAST(___UWORD, ___ARG1)) * ___CAST(___U64, 11400714819323198485ULL);
      ___RESULT = ___FIX((___WORD)((h >> 32) & ___CAST(___U64, ___INT(___ARG2))));"
     ,key ,mask)
    (##fxand (equal?-hash ,key) ,mask)))

(##define-macro (%ct-fast-fixnum-ref buckets mask key default)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ bvec = ___ARG1;
      ___WORD mask = ___INT(___ARG2);
      ___SCMOBJ key = ___ARG3;
      ___SCMOBJ res = ___ARG4;
      ___U64 h = ___CAST(___U64, ___CAST(___UWORD, key)) * ___CAST(___U64, 11400714819323198485ULL);
      ___WORD idx = (___WORD)((h >> 32) & ___CAST(___U64, mask));
      ___WORD *slot = ___BODY_AS(bvec, ___tVECTOR) + idx;
      ___SCMOBJ xs = ___gc_atomic_slot_load(slot, 1);
      while (___PAIRP(xs)) {
        ___SCMOBJ entry = ___CAR(xs);
        if (___EQP(___CAR(entry), key)) {
          res = ___CDR(entry);
          break;
        }
        xs = ___CDR(xs);
      }
      ___RESULT = res;"
     ,buckets ,mask ,key ,default)
    (let* ((alist (%slot-load-acq ,buckets (##fxand (equal?-hash ,key) ,mask))))
      (let loop ((xs alist))
        (cond
          ((##null? xs) ,default)
          ((##eq? (##caar xs) ,key) (##cdar xs))
          (else (loop (##cdr xs))))))))

(define (%ct-bucket-idx ct key)
  (let ((mask (macro-concurrent-table-mask ct)))
    (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
        (%ct-fixnum-hash key mask)
        (##fxand ((macro-concurrent-table-hash-fn ct) key) mask))))

(define (%alist-find alist key eq-fn)
  (let loop ((xs alist))
    (cond
      ((##null? xs) #f)
      ((eq-fn (##caar xs) key) (##car xs))
      (else (loop (##cdr xs))))))

(define (%alist-find-eq alist key)
  (let loop ((xs alist))
    (cond
      ((##null? xs) #f)
      ((##eq? (##caar xs) key) (##car xs))
      (else (loop (##cdr xs))))))

;; Zero-closure replace: `(eq? (cdr result) alist)` is #t iff key did NOT exist.
(define (%alist-replace alist key val eq-fn)
  (let loop ((xs alist) (prefix '()))
    (cond
      ((##null? xs)
       (##cons (##cons key val) alist))
      ((eq-fn (##caar xs) key)
       (let rebuild ((p prefix) (res (##cons (##cons key val) (##cdr xs))))
         (if (##null? p)
             res
             (rebuild (##cdr p) (##cons (##car p) res)))))
      (else
       (loop (##cdr xs) (##cons (##car xs) prefix))))))

(define (%alist-replace-eq alist key val)
  (let loop ((xs alist) (prefix '()))
    (cond
      ((##null? xs)
       (##cons (##cons key val) alist))
      ((##eq? (##caar xs) key)
       (let rebuild ((p prefix) (res (##cons (##cons key val) (##cdr xs))))
         (if (##null? p)
             res
             (rebuild (##cdr p) (##cons (##car p) res)))))
      (else
       (loop (##cdr xs) (##cons (##car xs) prefix))))))

;; Zero-closure delete: `(eq? result alist)` is #t iff key was NOT found.
(define (%alist-delete alist key eq-fn)
  (let loop ((xs alist) (prefix '()))
    (cond
      ((##null? xs)
       alist)
      ((eq-fn (##caar xs) key)
       (let rebuild ((p prefix) (res (##cdr xs)))
         (if (##null? p)
             res
             (rebuild (##cdr p) (##cons (##car p) res)))))
      (else
       (loop (##cdr xs) (##cons (##car xs) prefix))))))

(define (concurrent-table-size ct)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-size ct))
  (%ctr-load-acq (macro-concurrent-table-count ct)))

;; Wait-free read: single acquire load + immutable bucket scan.
(define (concurrent-table-ref ct key #!optional (default #f))
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-ref ct))
  (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
      (%ct-fast-fixnum-ref (macro-concurrent-table-buckets ct) (macro-concurrent-table-mask ct) key default)
      (let* ((alist (%slot-load-acq (macro-concurrent-table-buckets ct) (%ct-bucket-idx ct key)))
             (entry (%alist-find alist key (macro-concurrent-table-eq-fn ct))))
        (if entry (##cdr entry) default))))

(define (concurrent-table-set! ct key val)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-set! ct))
  (let ((buckets (macro-concurrent-table-buckets ct))
        (cnt (macro-concurrent-table-count ct)))
    (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
        (let ((idx (%ct-fixnum-hash key (macro-concurrent-table-mask ct))))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (nxt (%alist-replace-eq cur key val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##eq? (##cdr nxt) cur)
                        (%ctr-add-rlx! cnt 1))
                    val)
                  (loop)))))
        (let ((idx (%ct-bucket-idx ct key))
              (eq-fn (macro-concurrent-table-eq-fn ct)))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (nxt (%alist-replace cur key val eq-fn))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##eq? (##cdr nxt) cur)
                        (%ctr-add-rlx! cnt 1))
                    val)
                  (loop))))))))

;; Atomic functional update: (updater found? old-val) -> new-val.
(define (concurrent-table-update! ct key updater)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-update! ct))
  (let ((buckets (macro-concurrent-table-buckets ct))
        (cnt (macro-concurrent-table-count ct)))
    (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
        (let ((idx (%ct-fixnum-hash key (macro-concurrent-table-mask ct))))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (entry (%alist-find-eq cur key))
                   (new-val (if entry (updater #t (##cdr entry)) (updater #f #f)))
                   (nxt (%alist-replace-eq cur key new-val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##eq? (##cdr nxt) cur)
                        (%ctr-add-rlx! cnt 1))
                    new-val)
                  (loop)))))
        (let ((idx (%ct-bucket-idx ct key))
              (eq-fn (macro-concurrent-table-eq-fn ct)))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (entry (%alist-find cur key eq-fn))
                   (new-val (if entry (updater #t (##cdr entry)) (updater #f #f)))
                   (nxt (%alist-replace cur key new-val eq-fn))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##eq? (##cdr nxt) cur)
                        (%ctr-add-rlx! cnt 1))
                    new-val)
                  (loop))))))))

(define (concurrent-table-delete! ct key)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-delete! ct))
  (let ((buckets (macro-concurrent-table-buckets ct))
        (idx (%ct-bucket-idx ct key))
        (eq-fn (macro-concurrent-table-eq-fn ct))
        (cnt (macro-concurrent-table-count ct)))
    (let loop ()
      (let* ((cur (%slot-load-acq buckets idx))
             (nxt (%alist-delete cur key eq-fn)))
        (if (##eq? nxt cur)
            #f
            (let ((prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (%ctr-sub-rlx! cnt 1)
                    #t)
                  (loop))))))))

;;;============================================================================
