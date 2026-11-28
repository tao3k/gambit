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

;; Immutable pre-allocated empty multiple-values sentinel (zero heap allocation
;; on empty non-blocking pop/dequeue/steal polls).
(define %empty-values-2 (##values #f #f))

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
            %empty-values-2
            (let ((prev (%slot-cas-acqrel! head 0 cur (##cdr cur))))
              (if (##eq? prev cur)
                  (##values #t (##car cur))
                  (loop))))))))

;;;============================================================================
;;; 2. Lock-Free Unbounded Per-Segment FAA MPMC FIFO Queue
;;;    (256-slot cache-line-permuted 2-sentinel LCRQ segments)
;;;
;;; Each segment is a 3-element vector: #(slots ctrl next)
;;;   [0] slots : 256-element movable payload vector initialized to an internal
;;;               empty sentinel (___UNB2 in C-compiled mode; private pair when
;;;               interpreted). Logical ticket idx in [0..255] maps to physical
;;;               slot ((idx & 15) << 4) | (idx >> 4) so 16 consecutive tickets
;;;               land on 16 disjoint 128-byte cache lines (zero false sharing).
;;;               Consumed or stalled-cancelled slots transition to ___DELETED.
;;;   [1] ctrl  : 32-element movable vector holding per-segment head_ctr at [0]
;;;               and tail_ctr at [16] (128 bytes apart on separate cache lines).
;;;               Tickets >= 256 permanently close the segment with zero loss.
;;;   [2] next  : #f or lazily CAS-linked successor segment.
;;;
;;; Queue holds two 128-byte padded segment-pointer vectors:
;;;   head : #(head_seg 0 ... 0)
;;;   tail : #(tail_seg 0 ... 0)

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
(define %lfq-slot-empty (##cons 'lfq-slot-empty 'lfq-slot-empty))
(define %lfq-slot-cancelled (##cons 'lfq-slot-cancelled 'lfq-slot-cancelled))

(define (%make-lf-qseg)
  (let ((slots (##make-vector 256 #f))
        (ctrl (##make-vector 32 0)))
    (macro-if-c-compiled
     (##c-code
      "___WORD *sp = ___BODY_AS(___ARG1, ___tVECTOR);
       ___WORD i;
       for (i = 0; i < 256; i++)
         ___WORD_STORE_RELAXED(&sp[i], ___CAST(___WORD, ___UNB2));
       ___RESULT = ___ARG1;"
      slots)
     (let loop ((i 0))
       (if (##fx< i 256)
           (begin
             (##vector-set! slots i %lfq-slot-empty)
             (loop (##fx+ i 1)))
           slots)))
    (##vector slots ctrl #f)))

(define (make-lf-queue)
  (let* ((seg0 (%make-lf-qseg))
         (hc (##make-vector 16 0))
         (tc (##make-vector 16 0)))
    (##vector-set! hc 0 seg0)
    (##vector-set! tc 0 seg0)
    (macro-make-lf-queue hc tc)))

(define (lf-queue? obj)
  (macro-lf-queue? obj))

(define (lf-queue-empty? q)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-empty? q))
  (let loop ((seg (%slot-load-acq (macro-lf-queue-head q) 0)))
    (let* ((ctrl (##vector-ref seg 1))
           (h (%slot-load-acq ctrl 0))
           (t (%slot-load-acq ctrl 16)))
      (cond
        ((##fx>= h 256)
         (let ((nxt (%slot-load-acq seg 2)))
           (if nxt (loop nxt) #t)))
        ((##fx< h t) #f)
        (else
         (let ((nxt (%slot-load-acq seg 2)))
           (if nxt (loop nxt) #t)))))))

;; Returns #t if enqueued, #f to retry, or `seg` needing seg[2] allocation.
;; Relaxed FAA claims an exclusive ticket in one instruction; CAS_ACQREL
;; publishes the payload into the 16-way cache-line-permuted slot.
(##define-macro (%lfq-enq-fast! tc val)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ tc = ___ARG1;
      ___SCMOBJ val = ___ARG2;
      ___WORD *tseg_p = ___BODY_AS(tc, ___tVECTOR);
      int tries = 0;
      for (;;) {
        ___SCMOBJ seg = ___gc_atomic_slot_load(tseg_p, 1);
        ___WORD *svec = ___BODY_AS(seg, ___tVECTOR);
        ___SCMOBJ slots = svec[0];
        ___SCMOBJ ctrl = svec[1];
        ___WORD *cvec = ___BODY_AS(ctrl, ___tVECTOR);
        ___VOLATILE ___WORD *tt_p = ___CAST(___VOLATILE ___WORD*, &cvec[16]);
        ___WORD t = ___INT(___atomic_uword_fetch_add(tt_p, ___FIX(1), 0));
        if (t < 256) {
          ___WORD phys = ((t & 15) << 4) | (t >> 4);
          ___WORD *slot_ptr = ___BODY_AS(slots, ___tVECTOR) + phys;
          ___SCMOBJ prev = ___gc_atomic_slot_cas(
            ___ps, slots, slot_ptr, ___UNB2, val, 3,
            ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
          if (prev == ___UNB2) {
            if (t == 255) {
              ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
              if (nxt != ___FAL) {
                (void)___gc_atomic_slot_cas(
                  ___ps, tc, tseg_p, seg, nxt, 2,
                  ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
              }
            }
            ___RESULT = ___TRU;
            break;
          }
          /* Slot was cancelled by a consumer while this producer was delayed. */
          if (++tries >= 64) { ___RESULT = ___FAL; break; }
          continue;
        }
        /* Segment is closed (t >= 256): advance to successor or ask Scheme to link one. */
        {
          ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
          if (nxt == ___FAL) {
            ___RESULT = seg;
            break;
          }
          (void)___gc_atomic_slot_cas(
            ___ps, tc, tseg_p, seg, nxt, 2,
            ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
          if (++tries >= 64) { ___RESULT = ___FAL; break; }
        }
      }"
     ,tc ,val)
    ;; Interpreted fallback
    (let* ((seg (%slot-load-acq ,tc 0))
           (slots (##vector-ref seg 0))
           (ctrl (##vector-ref seg 1))
           (t (##vector-inc! ctrl 16 1)))
      (if (##fx< t 256)
          (let* ((phys (##fxior (##fxarithmetic-shift-left (##fxand t 15) 4)
                                (##fxarithmetic-shift-right t 4)))
                 (prev (##vector-cas! slots phys ,val %lfq-slot-empty)))
            (##eq? prev %lfq-slot-empty))
          (let ((nxt (%slot-load-acq seg 2)))
            (if nxt
                (begin (%slot-cas-acqrel! ,tc 0 seg nxt) #f)
                seg))))))

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
           ;; `r` is the closed tail segment needing a lazily linked successor
           (let* ((new-seg (%make-lf-qseg))
                  (prev (%slot-cas-acqrel! r 2 #f new-seg))
                  (winner (if (##not prev) new-seg prev)))
             (%slot-cas-acqrel! tc 0 r winner)
             (loop))))))))

;; Returns dequeued item, `empty-sent` if empty, or `retry-sent` to retry in Scheme.
;; Zero-write empty peek avoids FAA overshoot; steady-state consumers claim
;; disjoint tickets via relaxed FAA on per-segment head_ctr with zero CAS retries.
(##define-macro (%lfq-deq-fast! hc empty-sent retry-sent)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ hc = ___ARG1;
      ___SCMOBJ empty_sent = ___ARG2;
      ___SCMOBJ retry_sent = ___ARG3;
      ___WORD *hseg_p = ___BODY_AS(hc, ___tVECTOR);
      int tries = 0;
      for (;;) {
        ___SCMOBJ seg = ___gc_atomic_slot_load(hseg_p, 1);
        ___WORD *svec = ___BODY_AS(seg, ___tVECTOR);
        ___SCMOBJ slots = svec[0];
        ___SCMOBJ ctrl = svec[1];
        ___WORD *cvec = ___BODY_AS(ctrl, ___tVECTOR);
        ___VOLATILE ___WORD *ht_p = ___CAST(___VOLATILE ___WORD*, &cvec[0]);
        ___VOLATILE ___WORD *tt_p = ___CAST(___VOLATILE ___WORD*, &cvec[16]);
        ___WORD h0 = ___INT(___atomic_word_load(ht_p, 1));
        if (h0 >= 256) {
          ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
          if (nxt == ___FAL) {
            ___WORD t0 = ___INT(___atomic_word_load(tt_p, 1));
            if (t0 <= 256) {
              ___CPU_RELAX();
              ___RESULT = empty_sent;
              break;
            }
            if (++tries >= 32) { ___RESULT = retry_sent; break; }
            ___CPU_RELAX();
            continue;
          }
          (void)___gc_atomic_slot_cas(
            ___ps, hc, hseg_p, seg, nxt, 2,
            ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
          if (++tries >= 64) { ___RESULT = retry_sent; break; }
          continue;
        }
        /* Zero-write empty peek: avoid FAA when segment is currently empty. */
        {
          ___WORD phys0 = ((h0 & 15) << 4) | (h0 >> 4);
          ___WORD *sp0 = ___BODY_AS(slots, ___tVECTOR) + phys0;
          ___SCMOBJ v0 = ___gc_atomic_slot_load(sp0, 1);
          if (v0 == ___UNB2) {
            ___WORD t0 = ___INT(___atomic_word_load(tt_p, 1));
            if (h0 >= t0) {
              ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
              if (nxt == ___FAL) {
                ___CPU_RELAX();
                ___RESULT = empty_sent;
                break;
              }
            }
          }
        }
        {
          ___WORD h = ___INT(___atomic_uword_fetch_add(ht_p, ___FIX(1), 0));
          if (h >= 256) {
            ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
            if (nxt == ___FAL) {
              ___WORD t_now = ___INT(___atomic_word_load(tt_p, 1));
              if (t_now <= 256) {
                ___CPU_RELAX();
                ___RESULT = empty_sent;
                break;
              }
              if (++tries >= 32) { ___RESULT = retry_sent; break; }
              ___CPU_RELAX();
              continue;
            }
            (void)___gc_atomic_slot_cas(
              ___ps, hc, hseg_p, seg, nxt, 2,
              ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
            if (++tries >= 64) { ___RESULT = retry_sent; break; }
            continue;
          }
          {
            ___WORD phys = ((h & 15) << 4) | (h >> 4);
            ___WORD *slot_ptr = ___BODY_AS(slots, ___tVECTOR) + phys;
            ___SCMOBJ val = ___gc_atomic_slot_load(slot_ptr, 1);
            int wspins = 0;
            while (val == ___UNB2 && wspins < 64) {
              ___CPU_RELAX();
              val = ___gc_atomic_slot_load(slot_ptr, 1);
              wspins++;
            }
            if (val != ___UNB2 && val != ___DELETED) {
              if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0) && ___MEM_ALLOCATED(val))
                ___EXT(___gc_satb_barrier_val)(___ps, val);
              ___atomic_word_store(___CAST(___VOLATILE ___WORD*, slot_ptr), ___CAST(___WORD, ___DELETED), 0);
              if (h == 255) {
                ___SCMOBJ nxt = ___gc_atomic_slot_load(&svec[2], 1);
                if (nxt != ___FAL) {
                  (void)___gc_atomic_slot_cas(
                    ___ps, hc, hseg_p, seg, nxt, 2,
                    ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
                }
              }
              ___RESULT = val;
              break;
            }
            if (val == ___UNB2) {
              ___SCMOBJ prev = ___CAST(___SCMOBJ,
                ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, slot_ptr),
                                   ___CAST(___WORD, ___UNB2),
                                   ___CAST(___WORD, ___DELETED), 3));
              if (prev != ___UNB2 && prev != ___DELETED) {
                if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0) && ___MEM_ALLOCATED(prev))
                  ___EXT(___gc_satb_barrier_val)(___ps, prev);
                ___atomic_word_store(___CAST(___VOLATILE ___WORD*, slot_ptr), ___CAST(___WORD, ___DELETED), 0);
                ___RESULT = prev;
                break;
              }
            }
            /* Slot cancelled cleanly: return empty if queue has no further tickets. */
            {
              ___WORD t_now = ___INT(___atomic_word_load(tt_p, 1));
              if (h + 1 >= t_now && ___gc_atomic_slot_load(&svec[2], 1) == ___FAL) {
                ___RESULT = empty_sent;
                break;
              }
            }
          }
        }
        if (++tries >= 64) { ___RESULT = retry_sent; break; }
      }"
     ,hc ,empty-sent ,retry-sent)
    ;; Interpreted fallback
    (let* ((seg (%slot-load-acq ,hc 0))
           (slots (##vector-ref seg 0))
           (ctrl (##vector-ref seg 1))
           (h0 (%slot-load-acq ctrl 0)))
      (cond
        ((##fx>= h0 256)
         (let ((nxt (%slot-load-acq seg 2)))
           (if nxt
               (begin (%slot-cas-acqrel! ,hc 0 seg nxt) ,retry-sent)
               ,empty-sent)))
        ((##fx>= h0 (%slot-load-acq ctrl 16))
         (let ((nxt (%slot-load-acq seg 2)))
           (if nxt
               (begin (%slot-cas-acqrel! ,hc 0 seg nxt) ,retry-sent)
               ,empty-sent)))
        (else
         (let ((h (##vector-inc! ctrl 0 1)))
           (if (##fx>= h 256)
               (let ((nxt (%slot-load-acq seg 2)))
                 (if nxt
                     (begin (%slot-cas-acqrel! ,hc 0 seg nxt) ,retry-sent)
                     ,empty-sent))
               (let* ((phys (##fxior (##fxarithmetic-shift-left (##fxand h 15) 4)
                                     (##fxarithmetic-shift-right h 4)))
                      (v (%slot-load-acq slots phys)))
                 (if (and (##not (##eq? v %lfq-slot-empty))
                          (##not (##eq? v %lfq-slot-cancelled)))
                     (begin
                       (##vector-set! slots phys %lfq-slot-cancelled)
                       v)
                     (let ((prev (##vector-cas! slots phys %lfq-slot-cancelled %lfq-slot-empty)))
                       (if (and (##not (##eq? prev %lfq-slot-empty))
                                (##not (##eq? prev %lfq-slot-cancelled)))
                           (begin
                             (##vector-set! slots phys %lfq-slot-cancelled)
                             prev)
                           (if (and (##fx>= (##fx+ h 1) (%slot-load-acq ctrl 16))
                                    (##not (%slot-load-acq seg 2)))
                               ,empty-sent
                               ,retry-sent))))))))))))

;; Returns (values #t val) on success, or (values #f #f) when empty.
(define (lf-queue-try-dequeue! q)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-try-dequeue! q))
  (let ((hc (macro-lf-queue-head q)))
    (let loop ()
      (let ((r (%lfq-deq-fast! hc %lfq-empty %lfq-retry)))
        (cond
          ((##eq? r %lfq-empty) %empty-values-2)
          ((##eq? r %lfq-retry) (loop))
          (else (##values #t r)))))))

;; Zero-closure single-value variant: returns dequeued value or `default` when empty.
(define (lf-queue-try-dequeue-or! q default)
  (if (##not (macro-lf-queue? q))
      (%raise-bad-type (macro-type-lf-queue) lf-queue-try-dequeue-or! q))
  (let ((hc (macro-lf-queue-head q)))
    (let loop ()
      (let ((r (%lfq-deq-fast! hc %lfq-empty %lfq-retry)))
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

;; Owner-only push at bottom. Caches a private lower bound on top in bvec[1]
;; so steady-state pushes avoid reading the thief-contended top cache line.
;; Returns #t on success, #f if bounded ring is full.
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
     ___WORD cached_t = ___INT(bvec[1]);
     if (___EXPECT_FALSE(b - cached_t >= cap)) {
       cached_t = ___INT(___atomic_word_load(tp, 1));
       bvec[1] = ___FIX(cached_t);
     }
     if (___EXPECT_FALSE(b - cached_t >= cap)) {
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
      ___SCMOBJ res = empty_sent;
      ___WORD t_peek = ___INT(___atomic_word_load(tp, 0));
      ___WORD b_peek = ___INT(___atomic_word_load(bp, 0));
      if (t_peek < b_peek) {
        int attempt;
        int jitter = ___PROCESSOR_ID(___ps, ___VMSTATE_FROM_PSTATE(___ps)) & 3;
        for (attempt = 0; attempt < 2; attempt++) {
          ___WORD t = ___INT(___atomic_word_load(tp, 1));
          ___atomic_fence_order(4);
          ___WORD b = ___INT(___atomic_word_load(bp, 1));
          if (t >= b) {
            break;
          }
          {
            ___WORD *sp = ___BODY_AS(slots, ___tVECTOR) + (t & mask);
            ___SCMOBJ val = ___gc_atomic_slot_load(sp, 0);
            if (___atomic_word_cas(tp, ___FIX(t), ___FIX(t + 1), 4) == ___FIX(t)) {
              res = val;
              break;
            }
          }
          {
            int bk = (2 << attempt) + jitter;
            while (bk-- > 0) ___CPU_RELAX();
          }
        }
      } else {
        ___CPU_RELAX();
        ___CPU_RELAX();
      }
      ___RESULT = res;"
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
        %empty-values-2
        (##values #t r))))

;; Concurrent thief FIFO steal from top. Returns (values #t val) or (values #f #f).
(define (ws-deque-try-steal! dq)
  (if (##not (macro-ws-deque? dq))
      (%raise-bad-type (macro-type-ws-deque) ws-deque-try-steal! dq))
  (let ((r (%ws-steal-raw! dq %ws-empty)))
    (if (##eq? r %ws-empty)
        %empty-values-2
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

;; Shared immutable empty flat bucket vector: #(k0 v0 k1 v1 ...)
(define %ct-empty-bucket (##vector))

(define (make-concurrent-table #!optional (min-buckets 64) (eq-fn equal?) (hash-fn equal?-hash))
  (let* ((nb (%next-pow2 (if (and (##fixnum? min-buckets) (##fx> min-buckets 0)) min-buckets 64)))
         (buckets (##make-vector nb %ct-empty-bucket))
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
      ___SCMOBJ bv = ___gc_atomic_slot_load(slot, 1);
      ___WORD *elems = ___BODY_AS(bv, ___tVECTOR);
      ___SIZE_TS len = ___INT(___VECTORLENGTH(bv));
      ___SIZE_TS i;
      for (i = 0; i < len; i += 2) {
        if (___EQP(___CAST(___SCMOBJ, ___WORD_LOAD_RELAXED(&elems[i])), key)) {
          res = ___CAST(___SCMOBJ, ___WORD_LOAD_RELAXED(&elems[i + 1]));
          break;
        }
      }
      ___RESULT = res;"
     ,buckets ,mask ,key ,default)
    (let* ((bv (%slot-load-acq ,buckets (##fxand (equal?-hash ,key) ,mask)))
           (len (##vector-length bv)))
      (let loop ((i 0))
        (cond
          ((##fx>= i len) ,default)
          ((##eq? (##vector-ref bv i) ,key) (##vector-ref bv (##fx+ i 1)))
          (else (loop (##fx+ i 2))))))))

(##define-macro (%ct-vec-find-eq bv key)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ bv = ___ARG1;
      ___SCMOBJ key = ___ARG2;
      ___WORD *elems = ___BODY_AS(bv, ___tVECTOR);
      ___SIZE_TS len = ___INT(___VECTORLENGTH(bv));
      ___SIZE_TS i;
      ___SCMOBJ res = ___FAL;
      for (i = 0; i < len; i += 2) {
        if (___EQP(___CAST(___SCMOBJ, ___WORD_LOAD_RELAXED(&elems[i])), key)) {
          res = ___FIX(i);
          break;
        }
      }
      ___RESULT = res;"
     ,bv ,key)
    (let ((len (##vector-length ,bv)))
      (let loop ((i 0))
        (cond
          ((##fx>= i len) #f)
          ((##eq? (##vector-ref ,bv i) ,key) i)
          (else (loop (##fx+ i 2))))))))

(##define-macro (%ct-vec-copy-range! dst doff src soff n)
  `(macro-if-c-compiled
    (##c-code
     "___SCMOBJ dst = ___ARG1;
      ___WORD doff = ___INT(___ARG2);
      ___SCMOBJ src = ___ARG3;
      ___WORD soff = ___INT(___ARG4);
      ___WORD n = ___INT(___ARG5);
      ___WORD *dp = ___BODY_AS(dst, ___tVECTOR) + doff;
      ___WORD *sp = ___BODY_AS(src, ___tVECTOR) + soff;
      ___WORD i;
      for (i = 0; i < n; i++) {
        ___SCMOBJ v = ___CAST(___SCMOBJ, ___WORD_LOAD_RELAXED(&sp[i]));
        ___GC_WRITE_BARRIER(___ps, dst, &dp[i], v);
        ___WORD_STORE_RELAXED(&dp[i], ___CAST(___WORD, v));
      }
      ___RESULT = dst;"
     ,dst ,doff ,src ,soff ,n)
    (let loop ((i 0))
      (if (##fx< i ,n)
          (begin
            (##vector-set! ,dst (##fx+ ,doff i) (##vector-ref ,src (##fx+ ,soff i)))
            (loop (##fx+ i 1)))
          ,dst))))

(define (%ct-bucket-idx ct key)
  (let ((mask (macro-concurrent-table-mask ct)))
    (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
        (%ct-fixnum-hash key mask)
        (##fxand ((macro-concurrent-table-hash-fn ct) key) mask))))

(define (%ct-vec-find bv key eq-fn)
  (let ((len (##vector-length bv)))
    (let loop ((i 0))
      (cond
        ((##fx>= i len) #f)
        ((eq-fn (##vector-ref bv i) key) i)
        (else (loop (##fx+ i 2)))))))

;; Copy-on-write immutable flat bucket vector replace.
;; (> (vector-length nxt) (vector-length cur)) is #t iff key did NOT exist.
(define (%ct-vec-replace-at cur pos key val)
  (let ((len (##vector-length cur)))
    (if pos
        (let ((nxt (##make-vector len #f)))
          (%ct-vec-copy-range! nxt 0 cur 0 len)
          (##vector-set! nxt (##fx+ pos 1) val)
          nxt)
        (let ((nxt (##make-vector (##fx+ len 2) #f)))
          (%ct-vec-copy-range! nxt 0 cur 0 len)
          (##vector-set! nxt len key)
          (##vector-set! nxt (##fx+ len 1) val)
          nxt))))

;; Copy-on-write immutable flat bucket vector delete.
;; (eq? nxt cur) is #t iff key was NOT found.
(define (%ct-vec-delete cur key eq-fn)
  (let ((pos (%ct-vec-find cur key eq-fn)))
    (if (##not pos)
        cur
        (let ((len (##vector-length cur)))
          (if (##fx= len 2)
              %ct-empty-bucket
              (let ((nxt (##make-vector (##fx- len 2) #f)))
                (%ct-vec-copy-range! nxt 0 cur 0 pos)
                (%ct-vec-copy-range! nxt pos cur (##fx+ pos 2) (##fx- len (##fx+ pos 2)))
                nxt))))))

(define (concurrent-table-size ct)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-size ct))
  (%ctr-load-acq (macro-concurrent-table-count ct)))

;; Wait-free read: single acquire load + contiguous immutable flat bucket scan.
(define (concurrent-table-ref ct key #!optional (default #f))
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-ref ct))
  (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
      (%ct-fast-fixnum-ref (macro-concurrent-table-buckets ct) (macro-concurrent-table-mask ct) key default)
      (let* ((bv (%slot-load-acq (macro-concurrent-table-buckets ct) (%ct-bucket-idx ct key)))
             (pos (%ct-vec-find bv key (macro-concurrent-table-eq-fn ct))))
        (if pos (##vector-ref bv (##fx+ pos 1)) default))))

(define (concurrent-table-set! ct key val)
  (if (##not (macro-concurrent-table? ct))
      (%raise-bad-type (macro-type-concurrent-table) concurrent-table-set! ct))
  (let ((buckets (macro-concurrent-table-buckets ct))
        (cnt (macro-concurrent-table-count ct)))
    (if (and (macro-concurrent-table-fast-mode ct) (##fixnum? key))
        (let ((idx (%ct-fixnum-hash key (macro-concurrent-table-mask ct))))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (pos (%ct-vec-find-eq cur key))
                   (nxt (%ct-vec-replace-at cur pos key val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##not pos)
                        (%ctr-add-rlx! cnt 1))
                    val)
                  (loop)))))
        (let ((idx (%ct-bucket-idx ct key))
              (eq-fn (macro-concurrent-table-eq-fn ct)))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (pos (%ct-vec-find cur key eq-fn))
                   (nxt (%ct-vec-replace-at cur pos key val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##not pos)
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
                   (pos (%ct-vec-find-eq cur key))
                   (new-val (if pos (updater #t (##vector-ref cur (##fx+ pos 1))) (updater #f #f)))
                   (nxt (%ct-vec-replace-at cur pos key new-val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##not pos)
                        (%ctr-add-rlx! cnt 1))
                    new-val)
                  (loop)))))
        (let ((idx (%ct-bucket-idx ct key))
              (eq-fn (macro-concurrent-table-eq-fn ct)))
          (let loop ()
            (let* ((cur (%slot-load-acq buckets idx))
                   (pos (%ct-vec-find cur key eq-fn))
                   (new-val (if pos (updater #t (##vector-ref cur (##fx+ pos 1))) (updater #f #f)))
                   (nxt (%ct-vec-replace-at cur pos key new-val))
                   (prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (if (##not pos)
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
             (nxt (%ct-vec-delete cur key eq-fn)))
        (if (##eq? nxt cur)
            #f
            (let ((prev (%slot-cas-acqrel! buckets idx cur nxt)))
              (if (##eq? prev cur)
                  (begin
                    (%ctr-sub-rlx! cnt 1)
                    #t)
                  (loop))))))))

;;;============================================================================
