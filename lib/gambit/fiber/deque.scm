;;;============================================================================

;;; File: "deque.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Inline 4096-Slot 128B-Padded Chase-Lev Work-Stealing Runqueue

;;;----------------------------------------------------------------------------
;;; Inline 4096-Slot 128B-Padded Work-Stealing Runqueue (SPSC Push, MPMC FIFO
;;; CAS(head) Pop & Tokio/Go-Style Half-Deque Batch Work-Stealing)

(define %DQ-CAP 4096)
(define %DQ-MASK 4095)
(define %MAX-STEAL-BATCH 16)

(define-type %local-dq
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000007
  constructor: %make-local-dq-raw
  predicate: %local-dq?
  (buf  %dq-buf)
  (head %dq-top)  ;; 128B-padded fxatom (shared CAS claim cursor for pop & steal)
  (tail %dq-bot)  ;; 128B-padded fxatom (owner-only push cursor)
  (nbuf %dq-nbuf)) ;; parallel nursery vector (eliminates heap pair allocation on spawn)

(define (%make-local-dq)
  (%make-local-dq-raw (make-vector %DQ-CAP #f)
                      (%make-padded-fxatom 0)
                      (%make-padded-fxatom 0)
                      (make-vector %DQ-CAP #f)))

;; Owner-only SPSC push of (item, nursery) pair (zero CAS, release tail publishes both slots)
(define (%dq-push-pair! dq item n)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf  = ___f[1];
     ___SCMOBJ ___nbuf = ___f[4];
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
     ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
     if (___t - ___h >= 4096) {
       ___RESULT = ___FAL;
     } else {
       ___WORD ___idx = ___t & 4095;
       ___WORD *___s  = ___BODY_AS(___buf, ___tVECTOR) + ___idx;
       ___WORD *___ns = ___BODY_AS(___nbuf, ___tVECTOR) + ___idx;
       ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___ARG2);
       ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___ARG2), 0);
       ___GC_WRITE_BARRIER(___ps, ___nbuf, ___ns, ___ARG3);
       ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ns), ___CAST(___WORD, ___ARG3), 0);
       ___atomic_word_store(___tail_p, ___FIX(___t + 1), 2);
       ___RESULT = ___TRU;
     }"
    dq item n)
   (let* ((tail-box (%dq-bot dq))
          (t (%fxatom-load-rlx tail-box))
          (h (%fxatom-load-acq (%dq-top dq))))
     (if (fx>= (fx- t h) %DQ-CAP)
         #f
         (let ((idx (fxand t %DQ-MASK)))
           (%dq-slot-store-rlx! (%dq-buf dq) idx item)
           (%dq-slot-store-rlx! (%dq-nbuf dq) idx n)
           (%fxatom-set-rel! tail-box (fx+ t 1))
           #t)))))

;; Owner-only FIFO pop via CAS(head, h -> h+1) (writes popped nursery into ctx.picked-n)
(define (%dq-pop! ctx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD *___f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
     ___SCMOBJ ___buf  = ___f[1];
     ___SCMOBJ ___nbuf = ___f[4];
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD *___buf_p  = ___BODY_AS(___buf, ___tVECTOR);
     ___WORD *___nbuf_p = ___BODY_AS(___nbuf, ___tVECTOR);
     ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
     ___SCMOBJ ___res = ___FAL;
     ___SCMOBJ ___res_n = ___FAL;
     int ___tries;
     for (___tries = 0; ___tries < 64; ___tries++) {
       ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
       if (___h >= ___t) {
         ___res = ___FAL;
         break;
       }
       ___WORD ___idx = ___h & 4095;
       ___WORD *___s  = ___buf_p + ___idx;
       ___WORD *___ns = ___nbuf_p + ___idx;
       ___SCMOBJ ___item = ___gc_atomic_slot_load(___s, 1);
       ___SCMOBJ ___n    = ___gc_atomic_slot_load(___ns, 1);
       if (___atomic_word_cas(___head_p, ___FIX(___h), ___FIX(___h + 1), 3) == ___FIX(___h)) {
         ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___FAL);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___FAL), 0);
         ___GC_WRITE_BARRIER(___ps, ___nbuf, ___ns, ___FAL);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ns), ___CAST(___WORD, ___FAL), 0);
         ___res = ___item;
         ___res_n = ___n;
         break;
       }
     }
     ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[16], ___res_n);
     ___WORD_STORE_RELAXED(&___ctx_f[16], ___res_n);
     ___RESULT = ___res;"
    ctx)
   (let* ((dq (%wctx-dq ctx))
          (head-box (%dq-top dq))
          (t (%fxatom-load-rlx (%dq-bot dq))))
     (let loop ()
       (let ((h (%fxatom-load-acq head-box)))
         (if (fx>= h t)
             (begin (%wctx-picked-n-set! ctx #f) #f)
             (let* ((idx (fxand h %DQ-MASK))
                    (item (%dq-slot-load-acq (%dq-buf dq) idx))
                    (n (%dq-slot-load-acq (%dq-nbuf dq) idx)))
               (if (fx= (%fxatom-cas-seq! head-box h (fx+ h 1)) h)
                   (begin (%wctx-picked-n-set! ctx n) item)
                   (loop)))))))))

(define (%dq-empty-rlx? dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___RESULT = (___INT(___atomic_word_load(___tail_p, 0)) <= ___INT(___atomic_word_load(___head_p, 0))) ? ___TRU : ___FAL;"
    dq)
   (fx<= (%fxatom-load-rlx (%dq-bot dq)) (%fxatom-load-rlx (%dq-top dq)))))

;; Batch work-steal: claims up to min((avail+1)/2, 16) (task, nursery) pairs from
;; victim-dq in ONE single CAS(victim.head, h -> h+n), pushes n-1 pairs into
;; ctx.dq, stores batch_n[0] in ctx.picked-n, and returns batch_t[0].
(define (%dq-steal-batch! victim-dq ctx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___vf = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___vbuf  = ___vf[1];
     ___SCMOBJ ___vnbuf = ___vf[4];
     ___VOLATILE ___WORD *___vhead_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___vf[2], ___tVECTOR));
     ___VOLATILE ___WORD *___vtail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___vf[3], ___tVECTOR));
     ___WORD *___ctx_f = ___BODY_AS(___ARG2, ___tSTRUCTURE);
     ___WORD *___lf = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
     ___SCMOBJ ___lbuf  = ___lf[1];
     ___SCMOBJ ___lnbuf = ___lf[4];
     ___VOLATILE ___WORD *___lhead_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___lf[2], ___tVECTOR));
     ___VOLATILE ___WORD *___ltail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___lf[3], ___tVECTOR));
     ___WORD ___vh = ___INT(___atomic_word_load(___vhead_p, 1));
     ___WORD ___vt = ___INT(___atomic_word_load(___vtail_p, 1));
     ___WORD ___avail = ___vt - ___vh;
     if (___avail <= 0) {
       ___RESULT = ___FAL;
     } else {
       ___WORD ___n = (___avail == 1) ? 1 : ((___avail + 1) >> 1);
       if (___n > 16) ___n = 16;
       ___WORD ___lt = ___INT(___atomic_word_load(___ltail_p, 0));
       ___WORD ___lh = ___INT(___atomic_word_load(___lhead_p, 1));
       ___WORD ___lroom = 4096 - (___lt - ___lh);
       if (___n > ___lroom + 1) ___n = ___lroom + 1;
       if (___n <= 0) {
         ___RESULT = ___FAL;
       } else {
         ___SCMOBJ ___batch_t[16];
         ___SCMOBJ ___batch_n[16];
         ___WORD *___vbuf_p  = ___BODY_AS(___vbuf, ___tVECTOR);
         ___WORD *___vnbuf_p = ___BODY_AS(___vnbuf, ___tVECTOR);
         ___WORD ___k;
         for (___k = 0; ___k < ___n; ___k++) {
           ___WORD ___vi = (___vh + ___k) & 4095;
           ___batch_t[___k] = ___gc_atomic_slot_load(___vbuf_p + ___vi, 1);
           ___batch_n[___k] = ___gc_atomic_slot_load(___vnbuf_p + ___vi, 1);
         }
         if (___atomic_word_cas(___vhead_p, ___FIX(___vh), ___FIX(___vh + ___n), 3) == ___FIX(___vh)) {
           if (___n > 1) {
             ___WORD *___lbuf_p  = ___BODY_AS(___lbuf, ___tVECTOR);
             ___WORD *___lnbuf_p = ___BODY_AS(___lnbuf, ___tVECTOR);
             for (___k = 1; ___k < ___n; ___k++) {
               ___WORD ___li = (___lt + ___k - 1) & 4095;
               ___WORD *___ls  = ___lbuf_p + ___li;
               ___WORD *___lns = ___lnbuf_p + ___li;
               ___GC_WRITE_BARRIER(___ps, ___lbuf, ___ls, ___batch_t[___k]);
               ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ls), ___CAST(___WORD, ___batch_t[___k]), 0);
               ___GC_WRITE_BARRIER(___ps, ___lnbuf, ___lns, ___batch_n[___k]);
               ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___lns), ___CAST(___WORD, ___batch_n[___k]), 0);
             }
             ___atomic_word_store(___ltail_p, ___FIX(___lt + ___n - 1), 2);
           }
           ___GC_WRITE_BARRIER(___ps, ___ARG2, &___ctx_f[16], ___batch_n[0]);
           ___WORD_STORE_RELAXED(&___ctx_f[16], ___batch_n[0]);
           ___RESULT = ___batch_t[0];
         } else {
           ___RESULT = ___FAL;
         }
       }
     }"
    victim-dq ctx)
   (let* ((head-box (%dq-top victim-dq))
          (h (%fxatom-load-acq head-box))
          (t (%fxatom-load-acq (%dq-bot victim-dq))))
     (if (fx< h t)
         (let* ((idx (fxand h %DQ-MASK))
                (item (%dq-slot-load-acq (%dq-buf victim-dq) idx))
                (n (%dq-slot-load-acq (%dq-nbuf victim-dq) idx)))
           (if (fx= (%fxatom-cas-seq! head-box h (fx+ h 1)) h)
               (begin (%wctx-picked-n-set! ctx n) item)
               #f))
         #f))))
