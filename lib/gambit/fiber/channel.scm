;;;============================================================================

;;; File: "channel.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Fast-Path Channel Send/Recv Dispatch & Public Channel API

;; Single-C-block fused buffered send (linearizable direct handoff + fused
;; empty-LIFO wakeup placement + bounded-retry Vyukov push).
;; Returns:
;;   #t        : pushed into ring (rx-waiters == 0) OR handed off directly into empty ctx.lifo
;;   %fiber-k  : handed off directly to parked receiver while ctx.lifo occupied (caller evicts)
;;   1         : pushed into ring and rx-waiters > 0 (caller wakes one receiver)
;;   2         : ring full (caller parks)
;;   3         : Vyukov CAS retry budget exhausted (caller polls safepoint and retries)
;;   4         : unbuffered channel (cap == 0)
;;   5         : direct-handoff spinlock budget exhausted (caller yields and retries)
;;   6         : channel closed (caller raises)
(define (%ch-send-fast-c! ch val ctx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
     if (___INT(___atomic_word_load(___tail_p, 1)) & 1) {
       ___RESULT = ___FIX(6);
     } else {
       ___WORD ___cap = ___INT(___f[1]);
       if (___cap <= 0) {
         ___RESULT = ___FIX(4);
       } else {
         ___SCMOBJ ___rxw_vec = ___f[7];
         ___WORD *___rxw_base = ___BODY_AS(___rxw_vec, ___tVECTOR);
         ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___rxw_base);
         ___WORD *___rxf_p = ___rxw_base + 1;
         ___SCMOBJ ___out = ___FAL;
         ___SCMOBJ ___woke = ___FAL;
         int ___done = 0;
         /* Fast path A1: Lock-free single-waiter rx-fast direct handoff (0 spinlocks!) */
         ___SCMOBJ ___rxf = ___gc_atomic_slot_load(___rxf_p, 0);
         if (___rxf != ___FAL) {
           ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
           ___WORD ___raw_t = ___INT(___atomic_word_load(___tail_p, 1));
           if ((___raw_t & 1) == 0 && (___raw_t >> 1) == ___INT(___atomic_word_load(___head_p, 1))) {
             if (___gc_atomic_slot_cas(___ps, ___rxw_vec, ___rxf_p, ___rxf, ___FAL, 3,
                                       ___EXT(___gc_write_barrier_slow),
                                       ___EXT(___gc_satb_barrier_val)) == ___rxf) {
               ___WORD *___rk_f = ___BODY_AS(___rxf, ___tSTRUCTURE);
               ___GC_WRITE_BARRIER(___ps, ___rxf, &___rk_f[3], ___ARG2);
               ___WORD_STORE_RELAXED(&___rk_f[3], ___ARG2);
               ___woke = ___rxf;
               ___done = 1;
             }
           }
         }
         /* Fast path A2: Fallback rwq direct handoff when >=2 concurrent receivers parked */
         if (!___done && ___INT(___atomic_word_load(___rxw_p, 0)) > 0) {
           ___VOLATILE ___WORD *___lock_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[9], ___tVECTOR));
           int ___got_lock = 0;
           int ___i;
           for (___i = 0; ___i < 64; ___i++) {
             if (___atomic_word_cas(___lock_p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
               ___got_lock = 1;
               break;
             }
#if defined(__aarch64__)
             __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
             __asm__ __volatile__(\"pause\");
#endif
           }
           if (!___got_lock) {
             ___out = ___FIX(5);
             ___done = 1;
           } else {
             ___SCMOBJ ___rwq = ___f[10];
             ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
             ___SCMOBJ ___rk = ___rwq_f[1];
             if (___rk != ___FAL) {
               ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
               ___WORD ___raw_t = ___INT(___atomic_word_load(___tail_p, 1));
               ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
               if ((___raw_t & 1) == 0 && (___raw_t >> 1) == ___h) {
                 ___WORD *___rk_f = ___BODY_AS(___rk, ___tSTRUCTURE);
                 ___SCMOBJ ___nxt = ___rk_f[4];
                 ___GC_WRITE_BARRIER(___ps, ___rk, &___rk_f[4], ___FAL);
                 ___WORD_STORE_RELAXED(&___rk_f[4], ___FAL);
                 ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[1], ___nxt);
                 ___WORD_STORE_RELAXED(&___rwq_f[1], ___nxt);
                 if (___nxt == ___FAL) {
                   ___GC_WRITE_BARRIER(___ps, ___rwq, &___rwq_f[2], ___FAL);
                   ___WORD_STORE_RELAXED(&___rwq_f[2], ___FAL);
                 }
                 ___GC_WRITE_BARRIER(___ps, ___rk, &___rk_f[3], ___ARG2);
                 ___WORD_STORE_RELAXED(&___rk_f[3], ___ARG2);
                 ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
                 ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw - 1), 4);
                 ___woke = ___rk;
                 ___done = 1;
               }
             }
             ___atomic_word_store(___lock_p, ___FIX(0), 2);
           }
         }
         if (___woke != ___FAL) {
           ___SCMOBJ ___ctx = ___ARG3;
           if (___ctx != ___FAL) {
             ___WORD *___ctx_f = ___BODY_AS(___ctx, ___tSTRUCTURE);
             ___WORD *___wf = ___BODY_AS(___woke, ___tSTRUCTURE);
             if (___ctx_f[1] == ___wf[5] && ___ctx_f[6] == ___FAL) {
               ___GC_WRITE_BARRIER(___ps, ___ctx, &___ctx_f[6], ___woke);
               ___WORD_STORE_RELAXED(&___ctx_f[6], ___woke);
               if (___ctx_f[15] != ___FAL) {
                 ___GC_WRITE_BARRIER(___ps, ___ctx, &___ctx_f[15], ___FAL);
                 ___WORD_STORE_RELAXED(&___ctx_f[15], ___FAL);
               }
               ___out = ___TRU;
             } else {
               ___out = ___woke;
             }
           } else {
             ___out = ___woke;
           }
         }
         if (!___done) {
           ___WORD ___mask = ___INT(___f[2]);
           ___SCMOBJ ___buf = ___f[3];
           ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
           ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
           ___SCMOBJ ___val = ___ARG2;
           ___out = ___FIX(3);
           int ___tries;
           for (___tries = 0; ___tries < 64; ___tries++) {
             ___WORD ___raw_t = ___INT(___atomic_word_load(___tail_p, 0));
             if (___raw_t & 1) {
               ___out = ___FIX(6);
               break;
             }
             ___WORD ___pos = ___raw_t >> 1;
             ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
             ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 1));
             ___WORD ___exp = ___pos << 1;
             ___WORD ___dif = ___s - ___exp;
             if (___dif == 0) {
               if (___atomic_word_cas(___tail_p, ___FIX(___raw_t), ___FIX((___pos + 1) << 1), 0) == ___FIX(___raw_t)) {
                 ___WORD *___slot = ___buf_p + ___idx;
                 ___GC_WRITE_BARRIER(___ps, ___buf, ___slot, ___val);
                 ___WORD_STORE_RELAXED(___slot, ___val);
                 ___atomic_word_store(___seq_p + ___idx, ___FIX(___exp + 1), 4);
                 ___out = (___gc_atomic_slot_load(___rxf_p, 4) != ___FAL ||
                           ___INT(___atomic_word_load(___rxw_p, 4)) > 0) ? ___FIX(1) : ___TRU;
                 break;
               }
             } else if (___dif < 0) {
               ___out = ___FIX(2);
               break;
             }
           }
         }
         ___RESULT = ___out;
       }
     }"
    ch val ctx)
   (if (%ch-closed-seq? ch)
       6
       (if (fx<= (%ch-cap ch) 0)
           4
           (let ((rxw (%ch-rx-waiters ch))
                 (rk #f))
             (if (fx> (%fxatom-load-rlx rxw) 0)
                 (let ((lock (%ch-lock ch))
                       (rwq (%ch-recv-waiters ch)))
                   (%spin-lock! lock)
                   (if (and (not (%wq-empty? rwq))
                            (let* ((raw-t (%fxatom-load-acq (%ch-tail ch)))
                                   (h (%fxatom-load-acq (%ch-head ch))))
                              (and (fx= (fxand raw-t 1) 0)
                                   (fx= (fxarithmetic-shift-right raw-t 1) h))))
                       (begin
                         (set! rk (%wq-pop! rwq))
                         (%fk-val-set! rk val)
                         (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))))
                   (%spin-unlock! lock)))
             (if rk
                 rk
                 (let ((st (%vyukov-try-push-c! ch val)))
                   (if (fx= st 0) #t st))))))))

;; Single-C-block fused buffered receive (bounded-retry Vyukov pop).
;; Returns item directly, `empty-tag` if ring empty, or `retry-tag` if cap == 0 or retry budget hit.
(define (%ch-recv-fast-c! ch empty-tag retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap = ___INT(___f[1]);
     if (___cap <= 0) {
       ___RESULT = ___ARG3;
     } else {
       ___WORD ___mask = ___INT(___f[2]);
       ___SCMOBJ ___buf = ___f[3];
       ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
       ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
       ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
       ___SCMOBJ ___res = ___ARG3;
       int ___tries;
       for (___tries = 0; ___tries < 64; ___tries++) {
         ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 0));
         ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
         ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 1));
         ___WORD ___exp = (___pos << 1) + 1;
         ___WORD ___dif = ___s - ___exp;
         if (___dif == 0) {
           if (___atomic_word_cas(___head_p, ___FIX(___pos), ___FIX(___pos + 1), 0) == ___FIX(___pos)) {
             ___WORD *___slot = ___buf_p + ___idx;
             ___SCMOBJ ___item = ___WORD_LOAD_RELAXED(___slot);
             ___GC_WRITE_BARRIER(___ps, ___buf, ___slot, ___FAL);
             ___WORD_STORE_RELAXED(___slot, ___FAL);
             ___atomic_word_store(___seq_p + ___idx, ___FIX((___pos + ___cap) << 1), 4);
             ___res = ___item;
             break;
           }
         } else if (___dif < 0) {
           ___res = ___ARG2;
           break;
         }
       }
       ___RESULT = ___res;
     }"
    ch empty-tag retry-tag)
   (if (fx<= (%ch-cap ch) 0)
       retry-tag
       (%vyukov-try-pop-c! ch empty-tag retry-tag))))

(define (%fiber-send-evict-and-true! ctx prev prev-n)
  (%sched-push-dq-pair! ctx prev prev-n)
  #t)

(define (%fiber-send-slow! ch val st)
  (cond
    ((fx= st 6)
     (error "fiber-send!: channel closed" ch))
    ((fx= st 1)
     (%ch-wake-one-receiver! ch)
     #t)
    ((fx= st 2)
     (if (%worker-ctx? (%carrier-wctx))
         (let ((res (##continuation-capture %park-send-buf-cont! ch val)))
           (if (eq? res %CH-RETRY)
               (fiber-send! ch val)
               #t))
         (begin
           (thread-yield!)
           (fiber-send! ch val))))
    ((fx= st 3)
     (fiber-send! ch val))
    ((fx= st 5)
     (thread-yield!)
     (fiber-send! ch val))
    (else
     ;; Unbuffered rendezvous (cap == 0) with acquire hint
     (let ((rwq (%ch-recv-waiters ch))
           (in-fiber? (%worker-ctx? (%carrier-wctx))))
       (if (%ch-closed-seq? ch)
           (error "fiber-send!: channel closed" ch)
           (if (not (%wq-head-acq rwq))
               (if in-fiber?
                   (let ((res (##continuation-capture %park-send-unbuf-cont! ch val)))
                     (if (eq? res %CH-RETRY) (fiber-send! ch val) #t))
                   (begin
                     (thread-yield!)
                     (fiber-send! ch val)))
               (let ((lock (%ch-lock ch)))
                 (%spin-lock! lock)
                 (cond
                   ((%ch-closed-seq? ch)
                    (%spin-unlock! lock)
                    (error "fiber-send!: channel closed" ch))
                   ((not (%wq-empty? rwq))
                    (let ((rk (%wq-pop! rwq)))
                      (%spin-unlock! lock)
                      (%fk-val-set! rk val)
                      (%wake-fk! rk)
                      #t))
                   (else
                    (%spin-unlock! lock)
                    (if in-fiber?
                        (let ((res (##continuation-capture %park-send-unbuf-cont! ch val)))
                          (if (eq? res %CH-RETRY) (fiber-send! ch val) #t))
                        (begin
                          (thread-yield!)
                          (fiber-send! ch val))))))))))))

(define (fiber-send! ch val)
  (if (not (fiber-channel? ch))
      (error "fiber-send!: expected fiber-channel" ch)
      (let* ((ctx (%carrier-wctx))
             (st (%ch-send-fast-c! ch val (if (%worker-ctx? ctx) ctx #f))))
        (cond
          ((eq? st #t) #t)
          ((fixnum? st) (%fiber-send-slow! ch val st))
          (else
           (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) (%fk-sched st)))
               (let ((prev (%wctx-lifo ctx))
                     (prev-n (%wctx-lifo-n ctx)))
                 (%wctx-lifo-set! ctx st)
                 (%wctx-lifo-n-set! ctx #f)
                 (if prev
                     (%fiber-send-evict-and-true! ctx prev prev-n)
                     #t))
               (begin
                 (%sched-enqueue-global! (%fk-sched st) st)
                 #t)))))))

(define (fiber-try-send! ch val)
  (if (not (fiber-channel? ch))
      (error "fiber-try-send!: expected fiber-channel" ch)
      (let loop ()
        (let* ((ctx (%carrier-wctx))
               (st (%ch-send-fast-c! ch val (if (%worker-ctx? ctx) ctx #f))))
          (cond
            ((eq? st #t) #t)
            ((fixnum? st)
             (cond
               ((fx= st 6) (error "fiber-try-send!: channel closed" ch))
               ((fx= st 1) (%ch-wake-one-receiver! ch) #t)
               ((fx= st 2) #f)
               ((fx= st 3) (loop))
               ((fx= st 5) (thread-yield!) (loop))
               (else
                ;; Unbuffered channel: succeed only if a receiver is already parked
                (let ((rwq (%ch-recv-waiters ch))
                      (lock (%ch-lock ch)))
                  (%spin-lock! lock)
                  (cond
                    ((%ch-closed-seq? ch)
                     (%spin-unlock! lock)
                     (error "fiber-try-send!: channel closed" ch))
                    ((not (%wq-empty? rwq))
                     (let ((rk (%wq-pop! rwq)))
                       (%spin-unlock! lock)
                       (%fk-val-set! rk val)
                       (%wake-fk! rk)
                       #t))
                    (else
                     (%spin-unlock! lock)
                     #f))))))
            (else
             (%wake-fk! st)
             #t))))))

(define (%fiber-recv-wake-and-ret! ch item)
  (%ch-wake-one-sender! ch)
  item)

(define (%fiber-recv-park! ch)
  (if (%ch-closed-seq? ch)
      (%ch-drain-closed-or-eof! ch)
      (if (%worker-ctx? (%carrier-wctx))
          (let ((res (##continuation-capture %park-recv-buf-cont! ch)))
            (if (eq? res %CH-RETRY)
                (fiber-recv! ch)
                res))
          (begin
            (thread-yield!)
            (fiber-recv! ch)))))

(define (%fiber-recv-slow! ch)
  (if (fx> (%ch-cap ch) 0)
      (fiber-recv! ch)
      ;; Unbuffered rendezvous (cap == 0) with acquire hint
      (let ((swq (%ch-send-waiters ch))
            (in-fiber? (%worker-ctx? (%carrier-wctx))))
        (if (and (not (%wq-head-acq swq)) (not (%ch-closed-seq? ch)))
            (if in-fiber?
                (let ((res (##continuation-capture %park-recv-unbuf-cont! ch)))
                  (if (eq? res %CH-RETRY) (fiber-recv! ch) res))
                (begin
                  (thread-yield!)
                  (fiber-recv! ch)))
            (let ((lock (%ch-lock ch)))
              (%spin-lock! lock)
              (cond
                ((not (%wq-empty? swq))
                 (let* ((sk (%wq-pop! swq))
                        (sval (%fk-val sk)))
                   (%spin-unlock! lock)
                   (%fk-val-set! sk #t)
                   (%wake-fk! sk)
                   sval))
                ((%ch-closed-seq? ch)
                 (%spin-unlock! lock)
                 #!eof)
                (else
                 (%spin-unlock! lock)
                 (if in-fiber?
                     (let ((res (##continuation-capture %park-recv-unbuf-cont! ch)))
                       (if (eq? res %CH-RETRY) (fiber-recv! ch) res))
                     (begin
                       (thread-yield!)
                       (fiber-recv! ch))))))))))

(define (fiber-recv! ch)
  (if (not (fiber-channel? ch))
      (error "fiber-recv!: expected fiber-channel" ch)
      (let ((item (%ch-recv-fast-c! ch %CH-EMPTY %CH-RETRY)))
        (cond
          ((eq? item %CH-EMPTY) (%fiber-recv-park! ch))
          ((eq? item %CH-RETRY) (%fiber-recv-slow! ch))
          ((not (%ch-tx-any-waiters-seq? ch)) item)
          (else (%fiber-recv-wake-and-ret! ch item))))))

(define (fiber-try-recv! ch #!optional (default #f))
  (if (not (fiber-channel? ch))
      (error "fiber-try-recv!: expected fiber-channel" ch)
      (let loop ()
        (let ((item (%ch-recv-fast-c! ch %CH-EMPTY %CH-RETRY)))
          (cond
            ((eq? item %CH-EMPTY)
             (if (%ch-closed-seq? ch)
                 (%ch-drain-closed-or-eof! ch)
                 default))
            ((eq? item %CH-RETRY)
             (if (fx> (%ch-cap ch) 0)
                 (loop)
                 ;; Unbuffered channel: succeed only if a sender is already parked
                 (let ((swq (%ch-send-waiters ch))
                       (lock (%ch-lock ch)))
                   (%spin-lock! lock)
                   (cond
                     ((not (%wq-empty? swq))
                      (let* ((sk (%wq-pop! swq))
                             (sval (%fk-val sk)))
                        (%spin-unlock! lock)
                        (%fk-val-set! sk #t)
                        (%wake-fk! sk)
                        sval))
                     ((%ch-closed-seq? ch)
                      (%spin-unlock! lock)
                      #!eof)
                     (else
                      (%spin-unlock! lock)
                      default)))))
            ((not (%ch-tx-any-waiters-seq? ch)) item)
            (else (%fiber-recv-wake-and-ret! ch item)))))))

(define (fiber-channel-closed? ch)
  (if (not (fiber-channel? ch))
      (error "fiber-channel-closed?: expected fiber-channel" ch)
      (%ch-closed-seq? ch)))

;; Linearizable idempotent channel close:
;;   1. Atomically seal bit 0 of ch.tail = (final_tail << 1) | 1 with seq_cst
;;   2. Drain lock-free rx-fast & tx-fast slots + all rwq & swq waiters under ch.lock
;;   3. Re-drain rx-fast & tx-fast once more after lock release
;;   4. Wake every drained waiter via %wake-fk! with %CH-RETRY (receivers drain
;;      all pre-close buffered items up to final_tail then return #!eof; senders
;;      observe closed & raise).
(define (fiber-channel-close! ch)
  (if (not (fiber-channel? ch))
      (error "fiber-channel-close!: expected fiber-channel" ch))
  (%ch-seal-tail-seq! ch)
  (let ((woken '())
        (lock (%ch-lock ch))
        (rwq (%ch-recv-waiters ch))
        (swq (%ch-send-waiters ch))
        (rxw (%ch-rx-waiters ch))
        (txw (%ch-tx-waiters ch)))
    (let ((rk (%ch-try-pop-rxfast-c! ch)))
      (if rk (set! woken (cons rk woken))))
    (let ((sk (%ch-try-pop-txfast-c! ch)))
      (if sk (set! woken (cons sk woken))))
    (%spin-lock! lock)
    (let rloop ()
      (if (not (%wq-empty? rwq))
          (begin
            (set! woken (cons (%wq-pop! rwq) woken))
            (rloop))))
    (%fxatom-set-seq! rxw 0)
    (let sloop ()
      (if (not (%wq-empty? swq))
          (begin
            (set! woken (cons (%wq-pop! swq) woken))
            (sloop))))
    (%fxatom-set-seq! txw 0)
    (%spin-unlock! lock)
    (let ((rk2 (%ch-try-pop-rxfast-c! ch)))
      (if rk2 (set! woken (cons rk2 woken))))
    (let ((sk2 (%ch-try-pop-txfast-c! ch)))
      (if sk2 (set! woken (cons sk2 woken))))
    (let wloop ((ws woken))
      (if (pair? ws)
          (let ((fk (car ws)))
            (%fk-val-set! fk %CH-RETRY)
            (%wake-fk! fk)
            (wloop (cdr ws)))))
    #!void))
