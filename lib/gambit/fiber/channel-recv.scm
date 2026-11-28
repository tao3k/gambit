;;;============================================================================

;;; File: "channel-recv.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Fused Direct-Handoff Recv-Park, Slow-Path FIFO Recv & Unbuffered Rendezvous

;; Single-C-block fused Dekker park-recv for empty buffered channels.
;; Returns: #t if parked cleanly, #f if race (item arrived or sender parked),
;; or retry-tag if lock spin budget exhausted.
(define (%ch-park-recv-c! ch fk retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
     int ___got = 0;
     int ___i;
     for (___i = 0; ___i < 64; ___i++) {
       if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
         ___got = 1;
         break;
       }
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     if (!___got) {
       ___RESULT = ___ARG3;
     } else {
       ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
       ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
       ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw + 1), 4);
       ___WORD ___cap  = ___INT(___f[1]);
       ___WORD ___mask = ___INT(___f[2]);
       ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
       ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
       ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 4));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
       ___SCMOBJ ___swq = ___f[11];
       ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
       ___WORD *___txf_p = ___BODY_AS(___f[8], ___tVECTOR) + 1;
       ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
       if (___s - ((___pos << 1) + 1) < 0 && ___swq_f[1] == ___FAL &&
           ___gc_atomic_slot_load(___txf_p, 4) == ___FAL &&
           (___INT(___atomic_word_load(___tail_p, 4)) & 1) == 0) {
         ___SCMOBJ ___rwq = ___f[10];
         ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
         ___SCMOBJ ___fk = ___ARG2;
         ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
         ___SCMOBJ ___t = ___rwq_f[2];
         if (___t == ___FAL) {
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[1], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[1], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
         } else {
           ___WORD *___t_f = ___BODY_AS(___t, ___tSTRUCTURE);
           ___GC_WRITE_BARRIER(___ps, ___t, &___t_f[4], ___fk);
           ___WORD_STORE_RELAXED(&___t_f[4], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
         }
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___TRU;
       } else {
         ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw), 4);
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___FAL;
       }
     }"
    ch fk retry-tag)
   #f))

;; Single-C-block fused freelist pop + lock-free rx-fast Dekker park-recv
;; (with fallback to ch.lock + rwq when rx-fast occupied) + LIFO %fiber-k pop.
;; Returns:
;;   %fiber-k : parked cleanly and popped next runnable %fiber-k directly from ctx.lifo
;;   1        : parked cleanly, caller dispatches via %sched-switch-next!
;;   2        : race on rwq path (item arrived or sender parked); fk-pool untouched
;;   3        : spinlock budget exhausted; fk-pool untouched
;;   4        : fk-pool empty; caller allocates %fiber-k in Scheme
;;   5        : pending nursery batch > 0; caller flushes in slow path
;;   6        : race on rx-fast canceled via exchange; caller wakes ctx.picked-n with %CH-RETRY
(define (%ch-park-recv-and-pop-c! ctx ch raw-k)
  (##declare (not interrupts-enabled))
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     if (___INT(___ctx_f[14]) > 0) {
       ___RESULT = ___FIX(5);
     } else {
       ___SCMOBJ ___fk = ___ctx_f[10];
       if (___fk == ___FAL) {
         ___RESULT = ___FIX(4);
       } else {
         ___WORD *___fk_head_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___SCMOBJ ___fk_type = ___fk_head_f[0];
         ___WORD *___f = ___BODY_AS(___ARG2, ___tSTRUCTURE);
         ___SCMOBJ ___rxw_vec = ___f[7];
         ___WORD *___rxw_base = ___BODY_AS(___rxw_vec, ___tVECTOR);
         ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___rxw_base);
         ___WORD *___rxf_p = ___rxw_base + 1;
         ___WORD *___txw_base = ___BODY_AS(___f[8], ___tVECTOR);
         ___VOLATILE ___WORD *___txw_p = ___CAST(___VOLATILE ___WORD*, ___txw_base);
         ___WORD *___txf_p = ___txw_base + 1;
         ___WORD ___cap  = ___INT(___f[1]);
         ___WORD ___mask = ___INT(___f[2]);
         ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
         ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
         int ___parked = 0;
         int ___canceled = 0;
         /* Fast path: lock-free single-waiter rx-fast slot (0 spinlocks!) */
         if (___INT(___atomic_word_load(___txw_p, 0)) == 0 &&
             ___gc_atomic_slot_load(___txf_p, 0) == ___FAL &&
             ___gc_atomic_slot_load(___rxf_p, 0) == ___FAL) {
           ___WORD *___fk_f = ___fk_head_f;
           ___SCMOBJ ___pool_nxt = ___fk_f[4];
           ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[1], ___ARG3);
           ___WORD_STORE_RELAXED(&___fk_f[1], ___ARG3);
           ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[2], ___FAL);
           ___WORD_STORE_RELAXED(&___fk_f[2], ___FAL);
           ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[3], ___FAL);
           ___WORD_STORE_RELAXED(&___fk_f[3], ___FAL);
           ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
           ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
           if (___gc_atomic_slot_cas(___ps, ___rxw_vec, ___rxf_p, ___FAL, ___fk, 4,
                                     ___EXT(___gc_write_barrier_slow),
                                     ___EXT(___gc_satb_barrier_val)) == ___FAL) {
             /* Commit private freelist pop */
             ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___pool_nxt);
             ___WORD_STORE_RELAXED(&___ctx_f[10], ___pool_nxt);
             ___ctx_f[11] = ___FIX(___INT(___ctx_f[11]) - 1);
             /* Dekker seq_cst re-check against ring arrival, parked senders & channel close */
             ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 4));
             ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
             ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
             ___WORD ___txw2 = ___INT(___atomic_word_load(___txw_p, 4));
             ___SCMOBJ ___txf2 = ___gc_atomic_slot_load(___txf_p, 4);
             ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
             if (___s - ((___pos << 1) + 1) < 0 && ___txw2 == 0 && ___txf2 == ___FAL &&
                 (___INT(___atomic_word_load(___tail_p, 4)) & 1) == 0) {
               ___parked = 1;
             } else {
               /* Race: ABA-free exchange cancel (never recycle or clear raw_k on prev!) */
               ___SCMOBJ ___prev = ___gc_atomic_slot_exchange(
                 ___ps, ___rxw_vec, ___rxf_p, ___FAL, 4,
                 ___EXT(___gc_write_barrier_slow),
                 ___EXT(___gc_satb_barrier_val));
               if (___prev != ___FAL) {
                 ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[16], ___prev);
                 ___WORD_STORE_RELAXED(&___ctx_f[16], ___prev);
                 ___canceled = 1;
               } else {
                 /* Sender already claimed fk and will resume it */
                 ___parked = 1;
               }
             }
           } else {
             /* Initial CAS lost (another receiver occupies rx-fast): restore fk in pool */
             ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[1], ___FAL);
             ___WORD_STORE_RELAXED(&___fk_f[1], ___FAL);
             ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___pool_nxt);
             ___WORD_STORE_RELAXED(&___fk_f[4], ___pool_nxt);
           }
         }
         if (___canceled) {
           ___RESULT = ___FIX(6);
         } else if (!___parked) {
           /* Fallback path: ch.lock + rwq for >=2 concurrent parked receivers */
           ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
           int ___got = 0;
           int ___i;
           for (___i = 0; ___i < 64; ___i++) {
             if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
               ___got = 1;
               break;
             }
#if defined(__aarch64__)
             __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
             __asm__ __volatile__(\"pause\");
#endif
           }
           if (!___got) {
             ___RESULT = ___FIX(3);
           } else {
             ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
             ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw + 1), 4);
             ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 4));
             ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
             ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
             ___SCMOBJ ___swq = ___f[11];
             ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
             ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
             if (___s - ((___pos << 1) + 1) < 0 && ___swq_f[1] == ___FAL &&
                 ___gc_atomic_slot_load(___txf_p, 4) == ___FAL &&
                 (___INT(___atomic_word_load(___tail_p, 4)) & 1) == 0) {
               ___WORD *___fk_f = ___fk_head_f;
               ___SCMOBJ ___pool_nxt = ___fk_f[4];
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___pool_nxt);
               ___WORD_STORE_RELAXED(&___ctx_f[10], ___pool_nxt);
               ___ctx_f[11] = ___FIX(___INT(___ctx_f[11]) - 1);
               ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[1], ___ARG3);
               ___WORD_STORE_RELAXED(&___fk_f[1], ___ARG3);
               ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[2], ___FAL);
               ___WORD_STORE_RELAXED(&___fk_f[2], ___FAL);
               ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[3], ___FAL);
               ___WORD_STORE_RELAXED(&___fk_f[3], ___FAL);
               ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
               ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
               ___SCMOBJ ___rwq = ___f[10];
               ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
               ___SCMOBJ ___t = ___rwq_f[2];
               if (___t == ___FAL) {
                 ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[1], ___fk);
                 ___WORD_STORE_RELAXED(&___rwq_f[1], ___fk);
                 ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
                 ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
               } else {
                 ___WORD *___t_f = ___BODY_AS(___t, ___tSTRUCTURE);
                 ___GC_WRITE_BARRIER(___ps, ___t, &___t_f[4], ___fk);
                 ___WORD_STORE_RELAXED(&___t_f[4], ___fk);
                 ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___fk);
                 ___WORD_STORE_RELAXED(&___rwq_f[2], ___fk);
               }
               ___atomic_word_store(___lock_p, ___FIX(0), 2);
               ___parked = 1;
             } else {
               ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw), 4);
               ___atomic_word_store(___lock_p, ___FIX(0), 2);
               ___RESULT = ___FIX(2);
             }
           }
         }
         if (___parked) {
           /* Fused LIFO direct-switch candidate check + straggler spill + zero-hop jump */
           ___SCMOBJ ___lifo = ___ctx_f[6];
           if (___lifo != ___FAL && ___STRUCTUREP(___lifo)) {
             ___WORD ___ticks = ___INT(___ctx_f[8]);
             ___WORD *___sch_f = ___BODY_AS(___ctx_f[1], ___tSTRUCTURE);
             /* Idle-searcher-aware E-core straggler spill: expose private LIFO to idle P-cores */
             if ((___ticks & 63) == 63 && ___INT(___ctx_f[2]) >= ___INT(___sch_f[12])) {
               ___VOLATILE ___WORD *___srch_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___sch_f[9], ___tVECTOR));
               ___SCMOBJ ___pk = ___sch_f[11];
               fiber_os_parker_t *___pp = (___pk != ___FAL) ? (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___pk, ___tU64VECTOR)))[0] : 0;
               int ___idle_peer = (___INT(___atomic_word_load(___srch_p, 0)) > 0 ||
                                   (___pp != 0 && __atomic_load_n(&___pp->waiters, __ATOMIC_RELAXED) > 0u));
               if (___idle_peer) {
                 ___WORD *___dq_f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
                 ___VOLATILE ___WORD *___dh_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[2], ___tVECTOR));
                 ___VOLATILE ___WORD *___dt_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[3], ___tVECTOR));
                 ___WORD ___dt = ___INT(___atomic_word_load(___dt_p, 0));
                 ___WORD ___dh = ___INT(___atomic_word_load(___dh_p, 1));
                 if (___dt - ___dh < 4096) {
                   ___SCMOBJ ___lbuf = ___dq_f[1];
                   ___SCMOBJ ___lnbuf = ___dq_f[4];
                   ___WORD ___didx = ___dt & 4095;
                   ___WORD *___ds = ___BODY_AS(___lbuf, ___tVECTOR) + ___didx;
                   ___WORD *___dns = ___BODY_AS(___lnbuf, ___tVECTOR) + ___didx;
                   ___GC_WRITE_BARRIER(___ps, ___lbuf, ___ds, ___lifo);
                   ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ds), ___CAST(___WORD, ___lifo), 0);
                   ___GC_WRITE_BARRIER(___ps, ___lnbuf, ___dns, ___FAL);
                   ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___dns), ___CAST(___WORD, ___FAL), 0);
                   ___atomic_word_store(___dt_p, ___FIX(___dt + 1), 2);
                   fiber_parker_wake_one_ptr(___pp, ___srch_p);
                   ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___FAL);
                   ___WORD_STORE_RELAXED(&___ctx_f[6], ___FAL);
                   ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[15], ___FAL);
                   ___WORD_STORE_RELAXED(&___ctx_f[15], ___FAL);
                   ___ctx_f[8] = ___FIX(___ticks + 1);
                   ___ctx_f[7] = ___FIX(0);
                   ___RESULT = ___FIX(7);
                   ___parked = 0;
                 }
               }
             }
             if (___parked) {
               int ___need_global = 0;
               if ((___ticks & 31) == 31) {
                 ___VOLATILE ___WORD *___gp_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___sch_f[4], ___tVECTOR));
                 if (___INT(___atomic_word_load(___gp_p, 0)) > 0) ___need_global = 1;
               }
               if (!___need_global) {
                 ___WORD ___streak = ___INT(___ctx_f[7]);
                 int ___ok_lifo = (___streak < 8);
                 if (!___ok_lifo) {
                   ___WORD *___dq_f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
                   ___VOLATILE ___WORD *___dh_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[2], ___tVECTOR));
                   ___VOLATILE ___WORD *___dt_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[3], ___tVECTOR));
                   if (___atomic_word_load(___dh_p, 0) == ___atomic_word_load(___dt_p, 0)) ___ok_lifo = 1;
                 }
                 if (___ok_lifo) {
                   ___ctx_f[8] = ___FIX(___ticks + 1);
                   ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___FAL);
                   ___WORD_STORE_RELAXED(&___ctx_f[6], ___FAL);
                   ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[15], ___FAL);
                   ___WORD_STORE_RELAXED(&___ctx_f[15], ___FAL);
                   ___ctx_f[7] = ___FIX((___streak < 8) ? (___streak + 1) : 8);
                   ___WORD *___lf = ___BODY_AS(___lifo, ___tSTRUCTURE);
                   if (___lf[0] == ___fk_type && ___lf[2] == ___FAL) {
                     ___SCMOBJ ___nk = ___lf[1];
                     ___SCMOBJ ___nval = ___lf[3];
                     ___SCMOBJ ___phead = ___ctx_f[10];
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[1], ___FAL);
                     ___WORD_STORE_RELAXED(&___lf[1], ___FAL);
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[3], ___FAL);
                     ___WORD_STORE_RELAXED(&___lf[3], ___FAL);
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[4], ___phead);
                     ___WORD_STORE_RELAXED(&___lf[4], ___phead);
                     ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___lifo);
                     ___WORD_STORE_RELAXED(&___ctx_f[10], ___lifo);
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
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[1], ___nk);
                     ___WORD_STORE_RELAXED(&___lf[1], ___nk);
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[3], ___nval);
                     ___WORD_STORE_RELAXED(&___lf[3], ___nval);
                     ___GC_WRITE_BARRIER(___ps, ___lifo, &___lf[4], ___FAL);
                     ___WORD_STORE_RELAXED(&___lf[4], ___FAL);
                   }
                   ___RESULT = ___lifo;
                 } else {
                   ___RESULT = ___FIX(1);
                 }
               } else {
                 ___RESULT = ___FIX(1);
               }
             }
           } else {
             ___RESULT = ___FIX(1);
           }
         }
       }
     }"
    ctx ch raw-k)
   4))

(define (%park-recv-buf-slow! ctx raw-k tc ch fast-code)
  (if (fx> (%wctx-nursery-batch ctx) 0) (%nursery-flush! ctx))
  (let ((fk (%alloc-fk! ctx raw-k tc #f)))
    (let ((fast (if (or (fx= fast-code 4) (fx= fast-code 5))
                    (%ch-park-recv-c! ch fk %CH-RETRY)
                    (if (fx= fast-code 3) %CH-RETRY #f))))
      (if (not (eq? fast #t))
          (let ((lock (%ch-lock ch))
                (rwq (%ch-recv-waiters ch))
                (swq (%ch-send-waiters ch))
                (rxw (%ch-rx-waiters ch))
                (txw (%ch-tx-waiters ch)))
            (if (eq? fast %CH-RETRY) (%os-sched-yield!))
            (%spin-lock! lock)
            (%fxatom-set-seq! rxw (fx+ (##vector-ref rxw 0) 1))
            (%seq-cst-fence!)
            (let ((item (%vyukov-try-pop-or! ch %CH-EMPTY)))
              (cond
                ((not (eq? item %CH-EMPTY))
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%spin-unlock! lock)
                 (if (%ch-tx-any-waiters-seq? ch)
                     (%ch-wake-one-sender! ch))
                 (%fk-val-set! fk item)
                 (%sched-push-lifo! ctx fk))
                ((%ch-closed-seq? ch)
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%spin-unlock! lock)
                 (%fk-val-set! fk %CH-RETRY)
                 (%sched-push-lifo! ctx fk))
                ((let ((sk-fast (%ch-try-pop-txfast-c! ch)))
                   (if sk-fast
                       (begin
                         (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                         (%spin-unlock! lock)
                         (%fk-val-set! sk-fast %CH-RETRY)
                         (%fk-val-set! fk %CH-RETRY)
                         (%wake-fk! sk-fast)
                         (%sched-push-lifo! ctx fk)
                         #t)
                       #f))
                 #!void)
                ((not (%wq-empty? swq))
                 (let ((sk (%wq-pop! swq)))
                   (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                   (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                   (%spin-unlock! lock)
                   (%fk-val-set! sk %CH-RETRY)
                   (%fk-val-set! fk %CH-RETRY)
                   (%wake-fk! sk)
                   (%sched-push-lifo! ctx fk)))
                (else
                 (%wq-push! rwq fk)
                 (%spin-unlock! lock)))))))
    (%sched-switch-next! ctx)))

(define (%park-recv-buf-cont! raw-k ch)
  (let ((ctx (%carrier-wctx))
        (tc (%get-tc)))
    (if tc
        (begin
          (%set-tc! #f)
          (%park-recv-buf-slow! ctx raw-k tc ch 4))
        (let ((res (%ch-park-recv-and-pop-c! ctx ch raw-k)))
          (cond
            ((%fiber-k? res)
             (let ((nk (%fk-raw-k res))
                   (ntc (%fk-tc res))
                   (nval (%fk-val res)))
               (%free-fk! ctx res)
               (if ntc (%set-tc! ntc))
               (%return-oneshot! nk nval)))
            ((fx= res 1)
             (%sched-switch-next! ctx))
            ((fx= res 6)
             (let ((w (%wctx-picked-n ctx)))
               (%wctx-picked-n-set! ctx #f)
               (%fk-val-set! w %CH-RETRY)
               (%wake-fk! w)
               (%sched-switch-next! ctx)))
            ((fx= res 7)
             (%os-sched-yield!)
             (%sched-switch-next! ctx))
            (else
             (%park-recv-buf-slow! ctx raw-k #f ch res)))))))

;; Zero-closure multi-arg park receivers for unbuffered rendezvous (cap == 0)
(define (%park-send-unbuf-cont! raw-k ch val)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc val))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (%nursery-flush! ctx)
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (cond
      ((%ch-closed-seq? ch)
       (%spin-unlock! lock)
       (%fk-val-set! fk %CH-RETRY)
       (%sched-push-lifo! ctx fk))
      ((not (%wq-empty? rwq))
       (let ((rk (%wq-pop! rwq)))
         (%spin-unlock! lock)
         (%fk-val-set! rk val)
         (%fk-val-set! fk #t)
         (%sched-push-lifo! ctx fk)
         (%wake-fk! rk)))
      (else
       (%wq-push! swq fk)
       (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))

(define (%park-recv-unbuf-cont! raw-k ch)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #f))
         (lock (%ch-lock ch))
         (rwq (%ch-recv-waiters ch))
         (swq (%ch-send-waiters ch)))
    (%nursery-flush! ctx)
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (cond
      ((not (%wq-empty? swq))
       (let* ((sk (%wq-pop! swq))
              (sval (%fk-val sk)))
         (%spin-unlock! lock)
         (%fk-val-set! sk #t)
         (%fk-val-set! fk sval)
         (%wake-fk! sk)
         (%sched-push-lifo! ctx fk)))
      ((%ch-closed-seq? ch)
       (%spin-unlock! lock)
       (%fk-val-set! fk %CH-RETRY)
       (%sched-push-lifo! ctx fk))
      (else
       (%wq-push! rwq fk)
       (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))
