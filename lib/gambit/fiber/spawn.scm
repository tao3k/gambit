;;;============================================================================

;;; File: "spawn.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Resource Cleanup, Direct O(1) Fiber Spawn, Fused Yield & One-Shot Return

;;;----------------------------------------------------------------------------
;;; Continuation-Safe Resource Cleanup, Direct O(1) Fiber Spawn & Fused Yield

;; Continuation-safe resource cleanup: guarantees finally-thunk runs strictly
;; once on normal return (including multiple values) or exception/nursery abort,
;; and never fires during fiber-yield, channel park/resume, or algebraic effect
;; perform/resume suspension (preventing dynamic-wind double-release).
(define (with-finally thunk finally-thunk)
  (if (not (procedure? thunk))
      (error "with-finally: expected thunk" thunk))
  (if (not (procedure? finally-thunk))
      (error "with-finally: expected finally-thunk" finally-thunk))
  (let ((done? #f))
    (define (run-once!)
      (if (not done?)
          (begin
            (set! done? #t)
            (finally-thunk))))
    (with-exception-catcher
     (lambda (e)
       (run-once!)
       (raise e))
     (lambda ()
       (call-with-values
        thunk
        (lambda vals
          (run-once!)
          (apply values vals)))))))

(define (fiber-worker-count)
  (%sched-num-workers (%wctx-sched (%current-wctx))))

;; Single-C-block fused yield: pop %fiber-k from private freelist, push to local
;; runqueue with release tail, and immediately claim next runnable task from
;; LIFO or CAS(dq.head).
;; Returns:
;;   %fiber-k / task : next runnable task already popped
;;   1               : yielded fk pushed; caller dispatches via %sched-switch-next!
;;   2               : fk-pool empty or dq full; caller uses slow path
(define (%yield-push-and-pop-c! ctx raw-k)
  (##declare (not interrupts-enabled))
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___fk = ___ctx_f[10];
     if (___fk == ___FAL) {
       ___RESULT = ___FIX(2);
     } else {
       ___WORD *___dq_f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
       ___SCMOBJ ___buf = ___dq_f[1];
       ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[2], ___tVECTOR));
       ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[3], ___tVECTOR));
       ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
       if (___t - ___h >= 4096) {
         ___RESULT = ___FIX(2);
       } else {
         /* Pop fk from private freelist and populate */
         ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___SCMOBJ ___fk_type = ___fk_f[0];
         ___SCMOBJ ___pool_nxt = ___fk_f[4];
         ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___pool_nxt);
         ___WORD_STORE_RELAXED(&___ctx_f[10], ___pool_nxt);
         ___ctx_f[11] = ___FIX(___INT(___ctx_f[11]) - 1);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[1], ___ARG2);
         ___WORD_STORE_RELAXED(&___fk_f[1], ___ARG2);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[2], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[2], ___FAL);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[3], ___VOID);
         ___WORD_STORE_RELAXED(&___fk_f[3], ___VOID);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
         /* Push fk onto local runqueue (with nbuf = #f) and release tail */
         ___SCMOBJ ___nbuf = ___dq_f[4];
         ___WORD *___buf_p  = ___BODY_AS(___buf, ___tVECTOR);
         ___WORD *___nbuf_p = ___BODY_AS(___nbuf, ___tVECTOR);
         ___WORD ___pidx = ___t & 4095;
         ___WORD *___pslot  = ___buf_p + ___pidx;
         ___WORD *___pnslot = ___nbuf_p + ___pidx;
         ___GC_WRITE_BARRIER(___ps, ___buf, ___pslot, ___fk);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___pslot), ___CAST(___WORD, ___fk), 0);
         ___GC_WRITE_BARRIER(___ps, ___nbuf, ___pnslot, ___FAL);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___pnslot), ___CAST(___WORD, ___FAL), 0);
         ___atomic_word_store(___tail_p, ___FIX(___t + 1), 2);
         /* Check tick boundaries (nursery flush every 16 ticks, global poll every 32 ticks) */
         ___WORD ___ticks = ___INT(___ctx_f[8]);
         if (((___ticks & 15) == 15 && ___INT(___ctx_f[14]) > 0)) {
           ___RESULT = ___FIX(1);
         } else {
           int ___need_global = 0;
           if ((___ticks & 31) == 31) {
             ___WORD *___sch_f = ___BODY_AS(___ctx_f[1], ___tSTRUCTURE);
             ___VOLATILE ___WORD *___gp_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___sch_f[4], ___tVECTOR));
             if (___INT(___atomic_word_load(___gp_p, 0)) > 0) ___need_global = 1;
           }
           if (___need_global) {
             ___RESULT = ___FIX(1);
           } else {
             ___SCMOBJ ___next_task = ___FIX(1);
             ___SCMOBJ ___lifo = ___ctx_f[6];
             ___WORD ___streak = ___INT(___ctx_f[7]);
             if (___lifo != ___FAL && ___streak < 8) {
               ___SCMOBJ ___lifo_n = ___ctx_f[15];
               ___ctx_f[8] = ___FIX(___ticks + 1);
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___FAL);
               ___WORD_STORE_RELAXED(&___ctx_f[6], ___FAL);
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[15], ___FAL);
               ___WORD_STORE_RELAXED(&___ctx_f[15], ___FAL);
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[16], ___lifo_n);
               ___WORD_STORE_RELAXED(&___ctx_f[16], ___lifo_n);
               ___ctx_f[7] = ___FIX(___streak + 1);
               ___next_task = ___lifo;
             } else {
               ___WORD ___nt = ___t + 1;
               ___SCMOBJ ___picked_n = ___FAL;
               int ___tries;
               for (___tries = 0; ___tries < 16; ___tries++) {
                 ___WORD ___ch = ___INT(___atomic_word_load(___head_p, 1));
                 if (___ch >= ___nt) break;
                 ___WORD ___cidx = ___ch & 4095;
                 ___WORD *___s  = ___buf_p + ___cidx;
                 ___WORD *___ns = ___nbuf_p + ___cidx;
                 ___SCMOBJ ___item = ___gc_atomic_slot_load(___s, 1);
                 ___SCMOBJ ___item_n = ___gc_atomic_slot_load(___ns, 1);
                 if (___atomic_word_cas(___head_p, ___FIX(___ch), ___FIX(___ch + 1), 3) == ___FIX(___ch)) {
                   ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___FAL);
                   ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___FAL), 0);
                   ___GC_WRITE_BARRIER(___ps, ___nbuf, ___ns, ___FAL);
                   ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ns), ___CAST(___WORD, ___FAL), 0);
                   ___ctx_f[8] = ___FIX(___ticks + 1);
                   ___ctx_f[7] = ___FIX(0);
                   ___next_task = ___item;
                   ___picked_n = ___item_n;
                   break;
                 }
               }
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[16], ___picked_n);
               ___WORD_STORE_RELAXED(&___ctx_f[16], ___picked_n);
             }
             /* Direct zero-hop switch when next_task is a %fiber-k with tc == #f */
             if (___STRUCTUREP(___next_task)) {
               ___WORD *___nf = ___BODY_AS(___next_task, ___tSTRUCTURE);
               if (___nf[0] == ___fk_type && ___nf[2] == ___FAL) {
                 ___SCMOBJ ___nk = ___nf[1];
                 ___SCMOBJ ___nval = ___nf[3];
                 ___SCMOBJ ___phead = ___ctx_f[10];
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[1], ___FAL);
                 ___WORD_STORE_RELAXED(&___nf[1], ___FAL);
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[3], ___FAL);
                 ___WORD_STORE_RELAXED(&___nf[3], ___FAL);
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[4], ___phead);
                 ___WORD_STORE_RELAXED(&___nf[4], ___phead);
                 ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___next_task);
                 ___WORD_STORE_RELAXED(&___ctx_f[10], ___next_task);
                 ___ctx_f[11] = ___FIX(___INT(___ctx_f[11]) + 1);
                 {
                   ___WORD ___ra;
                   ___WORD *___new_fp;
                   if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___nk, &___ra, &___new_fp)) {
                     ___SET_FP(___new_fp)
                     ___SET_R1(___nval)
#if ___NB_GVM_REGS > 2
                     ___SET_R2(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 3
                     ___SET_R3(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 4
                     ___SET_R4(___FIX(0L))
#endif
                     ___JUMPEXTPRM(___NOTHING, ___ra)
                   }
                 }
                 ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___phead);
                 ___WORD_STORE_RELAXED(&___ctx_f[10], ___phead);
                 ___ctx_f[11] = ___FIX(___INT(___ctx_f[11]) - 1);
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[1], ___nk);
                 ___WORD_STORE_RELAXED(&___nf[1], ___nk);
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[3], ___nval);
                 ___WORD_STORE_RELAXED(&___nf[3], ___nval);
                 ___GC_WRITE_BARRIER(___ps, ___next_task, &___nf[4], ___FAL);
                 ___WORD_STORE_RELAXED(&___nf[4], ___FAL);
               }
             }
             ___RESULT = ___next_task;
           }
         }
       }
     }"
    ctx raw-k)
   2))

(define (%yield-slow! ctx raw-k tc)
  (let ((fk (%alloc-fk! ctx raw-k tc #!void)))
    (%sched-push-dq! ctx fk)
    (%sched-switch-next! ctx)))

;; Direct linear one-shot fiber continuation return with zero-copy in-place
;; rewind or full-span reclamation. Falls back to ##continuation-return-no-winding
;; whenever concurrent SATB marking is active, denv changed, or the span is
;; aliased / heap-promoted / > 4 KiB.
(define (%return-oneshot! cont val)
  (##declare (not interrupts-enabled))
  (macro-if-c-compiled
   (if (##c-code
        "___SCMOBJ ___cont = ___ARG1;
         ___SCMOBJ ___val = ___ARG2;
         ___WORD ___ra;
         ___WORD *___new_fp;
         if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___cont, &___ra, &___new_fp)) {
           ___SET_FP(___new_fp)
           ___SET_R1(___val)
#if ___NB_GVM_REGS > 2
           ___SET_R2(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 3
           ___SET_R3(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 4
           ___SET_R4(___FIX(0L))
#endif
           ___JUMPEXTPRM(___NOTHING, ___ra)
         }
         ___RESULT = ___FAL;"
        cont val)
       (##void)
       (##continuation-return-no-winding cont val))
   (##continuation-return-no-winding cont val)))

;; Zero-closure multi-arg continuation receiver for fiber-yield.
(define (%yield-cont! raw-k)
  (let ((ctx (%carrier-wctx))
        (tc (%get-tc)))
    (if tc
        (begin
          (%set-tc! #f)
          (%yield-slow! ctx raw-k tc))
        (let ((res (%yield-push-and-pop-c! ctx raw-k)))
          (cond
            ((%fiber-k? res)
             (let ((nk (%fk-raw-k res))
                   (ntc (%fk-tc res))
                   (nval (%fk-val res)))
               (%free-fk! ctx res)
               (if ntc (%set-tc! ntc))
               (%return-oneshot! nk nval)))
            ((fixnum? res)
             (if (fx= res 1)
                 (%sched-switch-next! ctx)
                 (%yield-slow! ctx raw-k #f)))
            (else
             (##continuation-graft-no-winding
              (%wctx-sched-k ctx) %worker-run-task ctx res (%wctx-picked-n ctx))))))))

(define (fiber-yield)
  (if (not (%worker-ctx? (%carrier-wctx)))
      (%outside-run-fibers-error!)
      (##continuation-capture %yield-cont!)))

;; Single-C-block fused zero-cons fiber-spawn with pre-reserved +32 nursery credits:
;; - Consumes 1 pre-reserved credit (0 atomics!) when ctx.nursery-cur == n && credit >= 1.
;; - Otherwise refills +32 in ONE fetch_add_acqrel (or returns 1 if switching away from
;;   a different nursery with un-flushed credit so Scheme flushes it first).
;; - Publishes (thunk, n) into private (lifo, lifo-n) and evicts any prior occupant
;;   to the flat dual-array (buf, nbuf) runqueue with release tail (0 heap pairs!).
;; Returns:
;;   #f       : pushed cleanly
;;   1        : must flush different ctx.nursery-cur credit before spawning into n
;;   prev-obj : local 4096-slot runqueue full; caller spills (prev-obj, ctx.picked-n) to global-q
(define (%fiber-spawn-push-c! ctx thunk n)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     int ___need_flush = 0;
     if (___ARG3 != ___FAL) {
       ___SCMOBJ ___cur_n = ___ctx_f[13];
       ___WORD ___cred = ___INT(___ctx_f[14]);
       if (___cur_n == ___ARG3 && ___cred >= 1) {
         ___ctx_f[14] = ___FIX(___cred - 1);
       } else if (___cur_n != ___FAL && ___cur_n != ___ARG3 && ___cred > 0) {
         ___need_flush = 1;
       } else {
         ___WORD *___n_f = ___BODY_AS(___ARG3, ___tSTRUCTURE);
         ___VOLATILE ___WORD *___act_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___n_f[2], ___tVECTOR));
         ___atomic_uword_fetch_add(___act_p, ___FIX(32), 3);
         ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[13], ___ARG3);
         ___WORD_STORE_RELAXED(&___ctx_f[13], ___ARG3);
         ___ctx_f[14] = ___FIX(31);
       }
     }
     if (___need_flush) {
       ___RESULT = ___FIX(1);
     } else {
       ___VOLATILE ___WORD *___sp_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ctx_f[4], ___tVECTOR));
       ___WORD ___cur_sp = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___sp_p)));
       ___atomic_word_store(___sp_p, ___FIX(___cur_sp + 1), 2);
       ___SCMOBJ ___prev   = ___ctx_f[6];
       ___SCMOBJ ___prev_n = ___ctx_f[15];
       ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___ARG2);
       ___WORD_STORE_RELAXED(&___ctx_f[6], ___ARG2);
       ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[15], ___ARG3);
       ___WORD_STORE_RELAXED(&___ctx_f[15], ___ARG3);
       if (___prev == ___FAL) {
         ___RESULT = ___FAL;
       } else {
         ___WORD *___dq_f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
         ___SCMOBJ ___buf  = ___dq_f[1];
         ___SCMOBJ ___nbuf = ___dq_f[4];
         ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[2], ___tVECTOR));
         ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[3], ___tVECTOR));
         ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
         ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
         if (___t - ___h >= 4096) {
           ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[16], ___prev_n);
           ___WORD_STORE_RELAXED(&___ctx_f[16], ___prev_n);
           ___RESULT = ___prev;
         } else {
           ___WORD ___idx = ___t & 4095;
           ___WORD *___s  = ___BODY_AS(___buf, ___tVECTOR) + ___idx;
           ___WORD *___ns = ___BODY_AS(___nbuf, ___tVECTOR) + ___idx;
           ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___prev);
           ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___prev), 0);
           ___GC_WRITE_BARRIER(___ps, ___nbuf, ___ns, ___prev_n);
           ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ns), ___CAST(___WORD, ___prev_n), 0);
           ___atomic_word_store(___tail_p, ___FIX(___t + 1), 2);
           {
             ___WORD *___sch_f = ___BODY_AS(___ctx_f[1], ___tSTRUCTURE);
             ___SCMOBJ ___pk = ___sch_f[11];
             if (___pk != ___FAL) {
               fiber_os_parker_t *___pp = (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___pk, ___tU64VECTOR)))[0];
               ___VOLATILE ___WORD *___srch_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___sch_f[9], ___tVECTOR));
               fiber_parker_wake_one_ptr(___pp, ___srch_p);
             }
           }
           ___RESULT = ___FAL;
         }
       }
     }"
    ctx thunk n)
   (begin
     (if n (%fxatom-add-acqrel! (%nursery-active n) 1))
     (%fxatom-inc-owner-rel! (%wctx-spawned ctx))
     (let ((prev (%wctx-lifo ctx))
           (prev-n (%wctx-lifo-n ctx)))
       (%wctx-lifo-set! ctx thunk)
       (%wctx-lifo-n-set! ctx n)
       (if (and prev (not (%dq-push-pair! (%wctx-dq ctx) prev prev-n)))
           (begin (%wctx-picked-n-set! ctx prev-n) prev)
           #f)))))

(define (%fiber-spawn-slow! ctx thunk n res)
  (if (eq? res 1)
      (begin
        (%nursery-flush! ctx)
        (let ((spill (%fiber-spawn-push-c! ctx thunk n)))
          (if spill
              (%fiber-spawn-slow! ctx thunk n spill)
              #!void)))
      (let ((prev-n (%wctx-picked-n ctx)))
        (%sched-enqueue-global! (%wctx-sched ctx) (if prev-n (cons res prev-n) res))
        #!void)))

(define (fiber-spawn thunk #!optional (n #f))
  (if (not (procedure? thunk))
      (error "fiber-spawn: expected thunk" thunk)
      (let ((ctx (macro-thread-specific (##current-thread))))
        (if (not (%worker-ctx? ctx))
            (%outside-run-fibers-error!)
            (if n
                (if (not (nursery? n))
                    (error "fiber-spawn: expected nursery" n)
                    (if (not (eq? (%nursery-sched n) (%wctx-sched ctx)))
                        (error "fiber-spawn: nursery belongs to a different scheduler" n)
                        (let ((res (%fiber-spawn-push-c! ctx thunk n)))
                          (if res (%fiber-spawn-slow! ctx thunk n res) #!void))))
                (let ((res (%fiber-spawn-push-c! ctx thunk #f)))
                  (if res (%fiber-spawn-slow! ctx thunk #f res) #!void)))))))
