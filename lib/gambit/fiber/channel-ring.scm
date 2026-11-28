;;;============================================================================

;;; File: "channel-ring.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Intrusive FIFO Wait Queue, Vyukov Bounded MPMC Ring & Fast-Slot Claims

;;;----------------------------------------------------------------------------
;;; Intrusive Zero-Cons FIFO Wait Queue & Lock-Free Bounded MPMC Channel
;;; + Linearizable Direct Handoff + Zero-Closure Multi-Arg Park Continuations

(define-type %wait-q
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000004
  constructor: %make-wait-q
  predicate: %wait-q?
  (head %wq-head %wq-head-set!)
  (tail %wq-tail %wq-tail-set!))

(define (%wq-empty? q)
  (not (%wq-head q)))

(define (%wq-push! q fk)
  (%fk-next-set! fk #f)
  (let ((t (%wq-tail q)))
    (if (not t)
        (begin
          (%wq-head-set! q fk)
          (%wq-tail-set! q fk))
        (begin
          (%fk-next-set! t fk)
          (%wq-tail-set! q fk)))))

(define (%wq-pop! q)
  (let* ((h (%wq-head q))
         (nxt (%fk-next h)))
    (%fk-next-set! h #f)
    (%wq-head-set! q nxt)
    (if (not nxt)
        (%wq-tail-set! q #f))
    h))

(define-type fiber-channel
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000005
  constructor: %make-fiber-channel
  predicate: fiber-channel?
  (cap          %ch-cap)
  (mask         %ch-mask)        ;; cap-1 when power-of-2, else -1 (exact fxmodulo)
  (buf          %ch-buf)         ;; ring payload slots (GC write-barrier via ##vector-set!)
  (seq          %ch-seq)         ;; per-slot sequence fixnums
  (tail         %ch-tail)        ;; 128B-padded producer cursor
  (head         %ch-head)        ;; 128B-padded consumer cursor
  (rx-waiters   %ch-rx-waiters)  ;; 128B-padded count of parked receivers
  (tx-waiters   %ch-tx-waiters)  ;; 128B-padded count of parked senders
  (lock         %ch-lock)        ;; slow-path wait-lock (and cap==0 rendezvous lock)
  (recv-waiters %ch-recv-waiters)
  (send-waiters %ch-send-waiters))

(define (make-fiber-channel #!optional (capacity 16))
  (if (or (not (fixnum? capacity)) (fx< capacity 0))
      (error "make-fiber-channel: capacity must be a non-negative fixnum" capacity))
  (let* ((is-pow2 (and (fx> capacity 0)
                       (fx= (fxand capacity (fx- capacity 1)) 0)))
         (mask (if is-pow2 (fx- capacity 1) -1))
         (buf (if (fx> capacity 0) (make-vector capacity #f) '#()))
         (seq (if (fx> capacity 0)
                  (let ((v (make-vector capacity 0)))
                    (let loop ((i 0))
                      (if (fx< i capacity)
                          (begin (##vector-set! v i (fxarithmetic-shift-left i 1))
                                 (loop (fx+ i 1)))))
                    v)
                  '#())))
    (%make-fiber-channel
     capacity
     mask
     buf
     seq
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (let ((rxw (%make-padded-fxatom 0)))
       (##vector-set! rxw 1 #f)
       rxw)
     (let ((txw (%make-padded-fxatom 0)))
       (##vector-set! txw 1 #f)
       txw)
     (%make-fxatom 0)
     (%make-wait-q #f #f)
     (%make-wait-q #f #f))))

;; Check whether any receiver is parked in either lock-free rx-fast (word 1) or rwq (word 0).
(define (%ch-rx-any-waiters-seq? ch)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD *___rxw_base = ___BODY_AS(___f[7], ___tVECTOR);
     ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___rxw_base);
     ___RESULT = (___gc_atomic_slot_load(___rxw_base + 1, 4) != ___FAL ||
                  ___INT(___atomic_word_load(___rxw_p, 4)) > 0)
                 ? ___TRU : ___FAL;"
    ch)
   (fx> (%fxatom-load-seq (%ch-rx-waiters ch)) 0)))

;; Check whether any sender is parked in either lock-free tx-fast (word 1) or swq (word 0).
(define (%ch-tx-any-waiters-seq? ch)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD *___txw_base = ___BODY_AS(___f[8], ___tVECTOR);
     ___VOLATILE ___WORD *___txw_p = ___CAST(___VOLATILE ___WORD*, ___txw_base);
     ___RESULT = (___gc_atomic_slot_load(___txw_base + 1, 4) != ___FAL ||
                  ___INT(___atomic_word_load(___txw_p, 4)) > 0)
                 ? ___TRU : ___FAL;"
    ch)
   (fx> (%fxatom-load-seq (%ch-tx-waiters ch)) 0)))

;; Lock-free CAS pop of the single-waiter rx-fast slot (word 1 of rx-waiters).
(define (%ch-try-pop-rxfast-c! ch)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___rxw_vec = ___f[7];
     ___WORD *___rxf_p = ___BODY_AS(___rxw_vec, ___tVECTOR) + 1;
     ___SCMOBJ ___rk = ___gc_atomic_slot_load(___rxf_p, 1);
     if (___rk != ___FAL &&
         ___gc_atomic_slot_cas(___ps, ___rxw_vec, ___rxf_p, ___rk, ___FAL, 3,
                               ___EXT(___gc_write_barrier_slow),
                               ___EXT(___gc_satb_barrier_val)) == ___rk) {
       ___RESULT = ___rk;
     } else {
       ___RESULT = ___FAL;
     }"
    ch)
   #f))

;; Lock-free CAS pop of the single-waiter tx-fast slot (word 1 of tx-waiters).
(define (%ch-try-pop-txfast-c! ch)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___txw_vec = ___f[8];
     ___WORD *___txf_p = ___BODY_AS(___txw_vec, ___tVECTOR) + 1;
     ___SCMOBJ ___sk = ___gc_atomic_slot_load(___txf_p, 1);
     if (___sk != ___FAL &&
         ___gc_atomic_slot_cas(___ps, ___txw_vec, ___txf_p, ___sk, ___FAL, 3,
                               ___EXT(___gc_write_barrier_slow),
                               ___EXT(___gc_satb_barrier_val)) == ___sk) {
       ___RESULT = ___sk;
     } else {
       ___RESULT = ___FAL;
     }"
    ch)
   #f))

;; Single-C-block bounded-retry Vyukov ring push (2*pos / 2*pos+1 supports all cap >= 1).
;; Returns: 0=pushed & rxw==0, 1=pushed & rxw>0, 2=full, 3=retry after safepoint poll.
(define (%vyukov-try-push-c! ch val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap  = ___INT(___f[1]);
     ___WORD ___mask = ___INT(___f[2]);
     ___SCMOBJ ___buf = ___f[3];
     ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
     ___WORD *___rxw_base = ___BODY_AS(___f[7], ___tVECTOR);
     ___VOLATILE ___WORD *___rxw_p  = ___CAST(___VOLATILE ___WORD*, ___rxw_base);
     ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
     ___SCMOBJ ___val = ___ARG2;
     ___WORD ___res = 3;
     int ___tries;
     for (___tries = 0; ___tries < 64; ___tries++) {
       ___WORD ___pos = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 1));
       ___WORD ___exp = ___pos << 1;
       ___WORD ___dif = ___s - ___exp;
       if (___dif == 0) {
         if (___atomic_word_cas(___tail_p, ___FIX(___pos), ___FIX(___pos + 1), 0) == ___FIX(___pos)) {
           ___WORD *___slot = ___buf_p + ___idx;
           ___GC_WRITE_BARRIER(___ps, ___buf, ___slot, ___val);
           ___WORD_STORE_RELAXED(___slot, ___val);
           ___atomic_word_store(___seq_p + ___idx, ___FIX(___exp + 1), 4);
           ___res = (___gc_atomic_slot_load(___rxw_base + 1, 4) != ___FAL ||
                     ___INT(___atomic_word_load(___rxw_p, 4)) > 0) ? 1 : 0;
           break;
         }
       } else if (___dif < 0) {
         ___res = 2;
         break;
       }
     }
     ___RESULT = ___FIX(___res);"
    ch val)
   (let ((tail-box (%ch-tail ch))
         (seq (%ch-seq ch))
         (buf (%ch-buf ch))
         (cap (%ch-cap ch))
         (mask (%ch-mask ch)))
     (let loop ()
       (let* ((pos (%fxatom-load-rlx tail-box))
              (idx (if (fx>= mask 0) (fxand pos mask) (fxmodulo pos cap)))
              (s (%vec-fx-load-acq seq idx))
              (exp (fxarithmetic-shift-left pos 1))
              (dif (fx- s exp)))
         (cond
           ((fx= dif 0)
            (if (fx= (%fxatom-cas-rlx! tail-box pos (fx+ pos 1)) pos)
                (begin
                  (##vector-set! buf idx val)
                  (%vec-fx-store-seq! seq idx (fx+ exp 1))
                  (if (fx> (%fxatom-load-seq (%ch-rx-waiters ch)) 0) 1 0))
                (loop)))
           ((fx< dif 0) 2)
           (else (loop))))))))

(define (%vyukov-try-push! ch val)
  (let loop ()
    (let ((st (%vyukov-try-push-c! ch val)))
      (cond
        ((fx<= st 1) #t)
        ((fx= st 2) #f)
        (else (loop))))))

;; Single-C-block bounded-retry Vyukov ring pop (2*pos+1 / 2*(pos+cap) supports all cap >= 1).
;; Returns item directly, `default` if empty, or `retry-tag` if retry budget hit safepoint.
(define (%vyukov-try-pop-c! ch default retry-tag)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap  = ___INT(___f[1]);
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
     ___RESULT = ___res;"
    ch default retry-tag)
   (let ((head-box (%ch-head ch))
         (seq (%ch-seq ch))
         (buf (%ch-buf ch))
         (cap (%ch-cap ch))
         (mask (%ch-mask ch)))
     (let loop ()
       (let* ((pos (%fxatom-load-rlx head-box))
              (idx (if (fx>= mask 0) (fxand pos mask) (fxmodulo pos cap)))
              (s (%vec-fx-load-acq seq idx))
              (exp (fx+ (fxarithmetic-shift-left pos 1) 1))
              (dif (fx- s exp)))
         (cond
           ((fx= dif 0)
            (if (fx= (%fxatom-cas-rlx! head-box pos (fx+ pos 1)) pos)
                (let ((item (##vector-ref buf idx)))
                  (##vector-set! buf idx #f)
                  (%vec-fx-store-seq! seq idx (fxarithmetic-shift-left (fx+ pos cap) 1))
                  item)
                (loop)))
           ((fx< dif 0) default)
           (else (loop))))))))

(define (%vyukov-try-pop-or! ch default)
  (let loop ()
    (let ((res (%vyukov-try-pop-c! ch default %CH-RETRY)))
      (if (eq? res %CH-RETRY)
          (loop)
          res))))

;; Slow-path wakeups (called only when rx-fast/tx-fast occupied or waiter count > 0)
(define (%ch-wake-one-receiver! ch)
  (let ((rk (%ch-try-pop-rxfast-c! ch)))
    (if rk
        (let ((item (%vyukov-try-pop-or! ch %CH-EMPTY)))
          (if (not (eq? item %CH-EMPTY))
              (begin
                (if (%ch-tx-any-waiters-seq? ch)
                    (%ch-wake-one-sender! ch))
                (%fk-val-set! rk item)
                (%sched-push-lifo! (%carrier-wctx) rk))
              (begin
                (%fk-val-set! rk %CH-RETRY)
                (%sched-push-lifo! (%carrier-wctx) rk))))
        (let ((lock (%ch-lock ch))
              (rwq (%ch-recv-waiters ch))
              (rxw (%ch-rx-waiters ch))
              (rk2 #f)
              (item %CH-EMPTY))
          (%spin-lock! lock)
          (if (not (%wq-empty? rwq))
              (begin
                (set! rk2 (%wq-pop! rwq))
                (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                (set! item (%vyukov-try-pop-or! ch %CH-EMPTY))))
          (%spin-unlock! lock)
          (if rk2
              (if (not (eq? item %CH-EMPTY))
                  (begin
                    (if (%ch-tx-any-waiters-seq? ch)
                        (%ch-wake-one-sender! ch))
                    (%fk-val-set! rk2 item)
                    (%sched-push-lifo! (%carrier-wctx) rk2))
                  (begin
                    (%fk-val-set! rk2 %CH-RETRY)
                    (%sched-push-lifo! (%carrier-wctx) rk2))))))))

(define (%ch-wake-one-sender! ch)
  (let ((sk (%ch-try-pop-txfast-c! ch)))
    (if sk
        (if (%vyukov-try-push! ch (%fk-val sk))
            (begin
              (if (%ch-rx-any-waiters-seq? ch)
                  (%ch-wake-one-receiver! ch))
              (%fk-val-set! sk #t)
              (%sched-push-lifo! (%carrier-wctx) sk))
            (begin
              (%fk-val-set! sk %CH-RETRY)
              (%sched-push-lifo! (%carrier-wctx) sk)))
        (let ((lock (%ch-lock ch))
              (swq (%ch-send-waiters ch))
              (txw (%ch-tx-waiters ch))
              (sk2 #f)
              (pushed? #f))
          (%spin-lock! lock)
          (if (not (%wq-empty? swq))
              (begin
                (set! sk2 (%wq-pop! swq))
                (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                (set! pushed? (%vyukov-try-push! ch (%fk-val sk2)))))
          (%spin-unlock! lock)
          (if sk2
              (if pushed?
                  (begin
                    (if (%ch-rx-any-waiters-seq? ch)
                        (%ch-wake-one-receiver! ch))
                    (%fk-val-set! sk2 #t)
                    (%sched-push-lifo! (%carrier-wctx) sk2))
                  (begin
                    (%fk-val-set! sk2 %CH-RETRY)
                    (%sched-push-lifo! (%carrier-wctx) sk2))))))))
