;;;============================================================================

;;; File: "fiber.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit fiber) — Direct-Style Work-Stealing Structured Concurrency Runtime
;;;
;;; Features:
;;;   - Inline 4096-slot 128B-padded Chase-Lev work-stealing deques with
;;;     private LIFO slot and sticky victim-locality stealing
;;;   - Zero-cross-module inline thread-local carrier and control-state access
;;;   - Sharded 128B-padded per-worker monotonic quiescence counters
;;;   - Structured concurrency nurseries with zero-capture child exception handling
;;;   - Lock-free bounded MPMC ring channels with linearizable direct handoff
;;;   - Per-carrier recycled continuation wrapper freelist

(##supply-module gambit/fiber)

(##namespace ("gambit/fiber#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  make-thread
  thread-start!
  thread-join!
  thread-yield!
  with-exception-catcher
  raise
  error))
(##include "~~lib/gambit/concurrent/concurrent#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "fiber#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (inlining-limit 400)
  (block))

;;;----------------------------------------------------------------------------
;;; Inline C23 Atomic Primitives (Zero Cross-Module Overhead on C Target)
;;;
;;; Memory-order codes match Gambit runtime_protocols:
;;;   0=relaxed, 1=acquire, 2=release, 3=acq_rel, 4=seq_cst

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

(macro-if-c-compiled
 (c-declare
  "#ifdef __APPLE__
#include <sys/sysctl.h>
#include <pthread/qos.h>
#endif
")
 (begin))

;; Query physical performance-core count on heterogeneous Apple Silicon (e.g. 8 on 8P+4E),
;; falling back to VM processor count on homogeneous systems and non-C targets.
(define (fiber-performance-core-count)
  (let ((vm-procs (##current-vm-processor-count)))
    (macro-if-c-compiled
     (let ((pcores
            (##c-code
             "#ifdef __APPLE__
              int ___n = 0;
              size_t ___sz = sizeof(___n);
              if (sysctlbyname(\"hw.perflevel0.physicalcpu\", &___n, &___sz, NULL, 0) == 0 && ___n > 0) {
                ___RESULT = ___FIX(___n);
              } else {
                ___RESULT = ___FIX(0);
              }
#else
              ___RESULT = ___FIX(0);
#endif")))
       (if (fx> pcores 0)
           (if (fx< pcores vm-procs) pcores vm-procs)
           vm-procs))
     vm-procs)))

;; Request high-priority interactive QoS on carrier threads so heterogeneous OS
;; schedulers keep fiber workers resident on performance cores.
(define (%set-carrier-qos!)
  (macro-if-c-compiled
   (##c-code
    "#ifdef __APPLE__
     pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
#endif
     ___RESULT = ___VOID;")
   #!void))

;; 1-word fixnum atomic box
(define (%make-fxatom init)
  (##vector init))

;; 128-byte (16-word) cache-line-padded fixnum atomic box (eliminates L2 false sharing).
(define (%make-padded-fxatom init)
  (let ((v (##make-vector 16 0)))
    (##vector-set! v 0 init)
    v))

(define (%fxatom-load-rlx box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 0));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-load-acq box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 1));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-load-seq box)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)), 4));"
    box)
   (##vector-cas! box 0 #!unbound #!unbound)))

(define (%fxatom-set-rlx! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 0);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-set-rel! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-set-seq! box val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2), 4);
     ___RESULT = ___VOID;"
    box val)
   (let loop ((old (##vector-cas! box 0 #!unbound #!unbound)))
     (let ((prev (##vector-cas! box 0 val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (%fxatom-cas-rlx! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 0));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-cas-acq! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 1));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-cas-seq! box expected desired)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    box expected desired)
   (##vector-cas! box 0 desired expected)))

(define (%fxatom-add-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___WORD, ___ARG2), 3));"
    box delta)
   (##vector-inc! box 0 delta)))

(define (%fxatom-sub-acqrel! box delta)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)),
                                 ___CAST(___WORD, ___ARG2), 3));"
    box delta)
   (##vector-inc! box 0 (##fx- 0 delta))))

;; Owner-only single-writer release increment (STLR on ARM64, zero LDADDAL RMW)
(define (%fxatom-inc-owner-rel! box)
  (%fxatom-set-rel! box (##fx+ (##vector-ref box 0) 1)))

;; Indexed fixnum-vector atomics for bounded MPMC ring sequence numbers
(define (%vec-fx-load-acq vec idx)
  (macro-if-c-compiled
   (##c-code
    "___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(
         ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)) + ___INT(___ARG2),
         1));"
    vec idx)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (%vec-fx-store-seq! vec idx val)
  (macro-if-c-compiled
   (##c-code
    "___atomic_word_store(
       ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR)) + ___INT(___ARG2),
       ___CAST(___WORD, ___ARG3),
       4);
     ___RESULT = ___VOID;"
    vec idx val)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let ((prev (##vector-cas! vec idx val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

;; GC/SATB-safe atomic object-slot load/store for inline Chase-Lev deque
(define (%dq-slot-load-acq vec idx)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_load(___s, 1);"
    vec idx)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (%dq-slot-store-rlx! vec idx val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___gc_atomic_slot_exchange(
       ___ps, ___ARG1, ___s, ___ARG3, 0,
       ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
     ___RESULT = ___VOID;"
    vec idx val)
   (##vector-set! vec idx val)))

(define (%seq-cst-fence!)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order(4); ___RESULT = ___VOID;")
   (atomic-fence (memory-order sequentially-consistent))))

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
  (tail %dq-bot)) ;; 128B-padded fxatom (owner-only push cursor)

(define (%make-local-dq)
  (%make-local-dq-raw (make-vector %DQ-CAP #f)
                      (%make-padded-fxatom 0)
                      (%make-padded-fxatom 0)))

;; Owner-only SPSC push (zero CAS, plain relaxed atomic slot store + release tail)
(define (%dq-push! dq item)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf = ___f[1];
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
     ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
     if (___t - ___h >= 4096) {
       ___RESULT = ___FAL;
     } else {
       ___WORD *___s = ___BODY_AS(___buf, ___tVECTOR) + (___t & 4095);
       ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___ARG2);
       ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___ARG2), 0);
       ___atomic_word_store(___tail_p, ___FIX(___t + 1), 2);
       ___RESULT = ___TRU;
     }"
    dq item)
   (let* ((tail-box (%dq-bot dq))
          (t (%fxatom-load-rlx tail-box))
          (h (%fxatom-load-acq (%dq-top dq))))
     (if (fx>= (fx- t h) %DQ-CAP)
         #f
         (begin
           (%dq-slot-store-rlx! (%dq-buf dq) (fxand t %DQ-MASK) item)
           (%fxatom-set-rel! tail-box (fx+ t 1))
           #t)))))

;; Owner-only FIFO pop via CAS(head, h -> h+1) (zero seq_cst fence!)
(define (%dq-pop! dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___buf = ___f[1];
     ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[2], ___tVECTOR));
     ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[3], ___tVECTOR));
     ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
     ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
     ___SCMOBJ ___res = ___FAL;
     int ___tries;
     for (___tries = 0; ___tries < 64; ___tries++) {
       ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
       if (___h >= ___t) {
         ___res = ___FAL;
         break;
       }
       ___WORD *___s = ___buf_p + (___h & 4095);
       ___SCMOBJ ___item = ___gc_atomic_slot_load(___s, 1);
       if (___atomic_word_cas(___head_p, ___FIX(___h), ___FIX(___h + 1), 3) == ___FIX(___h)) {
         ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___FAL);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___FAL), 0);
         ___res = ___item;
         break;
       }
     }
     ___RESULT = ___res;"
    dq)
   (let* ((head-box (%dq-top dq))
          (t (%fxatom-load-rlx (%dq-bot dq))))
     (let loop ()
       (let ((h (%fxatom-load-acq head-box)))
         (if (fx>= h t)
             #f
             (let ((item (%dq-slot-load-acq (%dq-buf dq) (fxand h %DQ-MASK))))
               (if (fx= (%fxatom-cas-seq! head-box h (fx+ h 1)) h)
                   item
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

;; Batch work-steal: claims up to min((avail+1)/2, 16) tasks from victim-dq in
;; ONE single CAS(victim.head, h -> h+n), pushes n-1 into local-dq, returns task 0.
(define (%dq-steal-batch! victim-dq local-dq)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___vf = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___vbuf = ___vf[1];
     ___VOLATILE ___WORD *___vhead_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___vf[2], ___tVECTOR));
     ___VOLATILE ___WORD *___vtail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___vf[3], ___tVECTOR));
     ___WORD *___lf = ___BODY_AS(___ARG2, ___tSTRUCTURE);
     ___SCMOBJ ___lbuf = ___lf[1];
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
         ___SCMOBJ ___batch[16];
         ___WORD *___vbuf_p = ___BODY_AS(___vbuf, ___tVECTOR);
         ___WORD ___k;
         for (___k = 0; ___k < ___n; ___k++) {
           ___batch[___k] = ___gc_atomic_slot_load(___vbuf_p + ((___vh + ___k) & 4095), 1);
         }
         if (___atomic_word_cas(___vhead_p, ___FIX(___vh), ___FIX(___vh + ___n), 3) == ___FIX(___vh)) {
           if (___n > 1) {
             ___WORD *___lbuf_p = ___BODY_AS(___lbuf, ___tVECTOR);
             for (___k = 1; ___k < ___n; ___k++) {
               ___WORD *___ls = ___lbuf_p + ((___lt + ___k - 1) & 4095);
               ___GC_WRITE_BARRIER(___ps, ___lbuf, ___ls, ___batch[___k]);
               ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___ls), ___CAST(___WORD, ___batch[___k]), 0);
             }
             ___atomic_word_store(___ltail_p, ___FIX(___lt + ___n - 1), 2);
           }
           ___RESULT = ___batch[0];
         } else {
           ___RESULT = ___FAL;
         }
       }
     }"
    victim-dq local-dq)
   (let* ((head-box (%dq-top victim-dq))
          (h (%fxatom-load-acq head-box))
          (t (%fxatom-load-acq (%dq-bot victim-dq))))
     (if (fx< h t)
         (let ((item (%dq-slot-load-acq (%dq-buf victim-dq) (fxand h %DQ-MASK))))
           (if (fx= (%fxatom-cas-seq! head-box h (fx+ h 1)) h)
               item
               #f))
         #f))))

;;;----------------------------------------------------------------------------
;;; Inline Thread-Local Carrier Context & Lazy #f Control-State Access

(define (%get-tc)
  (macro-thread-control-state (##current-thread)))

(define (%set-tc! val)
  (macro-thread-control-state-set! (##current-thread) val))

;;;----------------------------------------------------------------------------
;;; Scheduler, Worker Context & Per-Carrier Recycled %fiber-k Freelist

(define %MAX-LIFO-STREAK 8)
(define %MAX-FK-POOL 64)
(define %MAX-NURSERY-BATCH 16)

;; Unexported private sentinels (cannot collide with any user value)
(define %CH-EMPTY (cons 'ch-empty '()))
(define %CH-RETRY (cons 'ch-retry '()))

(define-type %fiber-k
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000006
  constructor: %make-fiber-k
  predicate: %fiber-k?
  (raw-k %fk-raw-k %fk-raw-k-set!)  ;; native Gambit continuation (cleared on recycle)
  (tc    %fk-tc    %fk-tc-set!)     ;; saved per-fiber thread control-state
  (val   %fk-val   %fk-val-set!)    ;; intrusive resume/send payload
  (next  %fk-next  %fk-next-set!))  ;; intrusive wait-queue / freelist link

(define-type %scheduler
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000001
  constructor: %make-scheduler
  predicate: %scheduler?
  (num-workers    %sched-num-workers)
  (deques         %sched-deques)         ;; vector of W %local-dq
  (global-q       %sched-global-q)       ;; lf-queue for external wakeups & overflow
  (global-pending %sched-global-pending) ;; 128B-padded pending count (>= global-q len)
  (spawned-vec    %sched-spawned-vec)    ;; vector of W 128B-padded monotonic counters
  (completed-vec  %sched-completed-vec)  ;; vector of W 128B-padded monotonic counters
  (root-done      %sched-root-done)      ;; fxatom (0 -> 1)
  (root-box       %sched-root-box))      ;; box holding (ok? . val-or-exc)

(define-type %worker-ctx
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000002
  constructor: %make-worker-ctx
  predicate: %worker-ctx?
  (sched        %wctx-sched)
  (wid          %wctx-wid)
  (dq           %wctx-dq)
  (spawned      %wctx-spawned)          ;; owner-only 128B-padded monotonic spawned
  (completed    %wctx-completed)        ;; owner-only 128B-padded monotonic completed
  (lifo         %wctx-lifo         %wctx-lifo-set!)         ;; private 1-slot LIFO (0 atomics!)
  (lifo-streak  %wctx-lifo-streak  %wctx-lifo-streak-set!)  ;; anti-starvation counter
  (ticks        %wctx-ticks        %wctx-ticks-set!)        ;; fairness poll counter
  (sched-k      %wctx-sched-k      %wctx-sched-k-set!)      ;; reusable trampoline continuation
  (fk-pool       %wctx-fk-pool       %wctx-fk-pool-set!)       ;; private %fiber-k freelist
  (fk-pool-len   %wctx-fk-pool-len   %wctx-fk-pool-len-set!)
  (steal-cursor  %wctx-steal-cursor  %wctx-steal-cursor-set!)  ;; sticky productive victim wid
  (nursery-cur   %wctx-nursery-cur   %wctx-nursery-cur-set!)   ;; batched completion target nursery
  (nursery-batch %wctx-nursery-batch %wctx-nursery-batch-set!)) ;; un-flushed completion count (0..16)

(define (%outside-run-fibers-error!)
  (error "fiber operation called outside run-fibers"))

(define (%current-wctx)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (%worker-ctx? ctx)
        ctx
        (%outside-run-fibers-error!))))

;; Unchecked carrier-thread worker-ctx load for internal scheduler callbacks
;; that are guaranteed to run exclusively on initialized carrier threads.
(define (%carrier-wctx)
  (macro-thread-specific (##current-thread)))

;; Zero-allocation per-carrier %fiber-k pop/recycle (0 atomics, 0 GC retention)
(define (%alloc-fk! ctx raw-k tc val)
  (let ((fk (%wctx-fk-pool ctx)))
    (if fk
        (begin
          (%wctx-fk-pool-set! ctx (%fk-next fk))
          (%wctx-fk-pool-len-set! ctx (fx- (%wctx-fk-pool-len ctx) 1))
          (%fk-raw-k-set! fk raw-k)
          (%fk-tc-set! fk tc)
          (%fk-val-set! fk val)
          (%fk-next-set! fk #f)
          fk)
        (%make-fiber-k raw-k tc val #f))))

;; Single-C-block inline %fiber-k recycle (clears GC-retained fields, zero GVM stack frame).
(define (%free-fk! ctx fk)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD *___fk_f  = ___BODY_AS(___ARG2, ___tSTRUCTURE);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[1], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[1], ___FAL);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[2], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[2], ___FAL);
     ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[3], ___FAL);
     ___WORD_STORE_RELAXED(&___fk_f[3], ___FAL);
     ___WORD ___len = ___INT(___ctx_f[11]);
     if (___len < 64) {
       ___SCMOBJ ___head = ___ctx_f[10];
       ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[4], ___head);
       ___WORD_STORE_RELAXED(&___fk_f[4], ___head);
       ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[10], ___ARG2);
       ___WORD_STORE_RELAXED(&___ctx_f[10], ___ARG2);
       ___ctx_f[11] = ___FIX(___len + 1);
     } else {
       ___GC_WRITE_BARRIER(___ps, ___ARG2, &___fk_f[4], ___FAL);
       ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
     }
     ___RESULT = ___VOID;"
    ctx fk)
   (begin
     (%fk-raw-k-set! fk #f)
     (%fk-tc-set! fk #f)
     (%fk-val-set! fk #f)
     (let ((len (%wctx-fk-pool-len ctx)))
       (if (fx< len %MAX-FK-POOL)
           (begin
             (%fk-next-set! fk (%wctx-fk-pool ctx))
             (%wctx-fk-pool-set! ctx fk)
             (%wctx-fk-pool-len-set! ctx (fx+ len 1)))
           (%fk-next-set! fk #f))))))

;; Global queue enqueue/dequeue maintaining global-pending >= global-q length.
(define (%sched-enqueue-global! sched task)
  (%fxatom-add-acqrel! (%sched-global-pending sched) 1)
  (lf-queue-enqueue! (%sched-global-q sched) task))

(define (%sched-try-dequeue-global! sched)
  (let ((gp (%sched-global-pending sched)))
    (if (fx= (%fxatom-load-acq gp) 0)
        #f
        (let ((t (lf-queue-try-dequeue-or! (%sched-global-q sched) #f)))
          (if t
              (begin
                (%fxatom-sub-acqrel! gp 1)
                t)
              #f)))))

;; Push to inline local Chase-Lev deque (spilling to global-q only if > 4096 queued).
(define (%sched-push-dq! ctx task)
  (if (not (%dq-push! (%wctx-dq ctx) task))
      (%sched-enqueue-global! (%wctx-sched ctx) task)))

;; Push to private LIFO slot, evicting any prior occupant to local Chase-Lev deque.
(define (%sched-push-lifo! ctx task)
  (let ((prev (%wctx-lifo ctx)))
    (%wctx-lifo-set! ctx task)
    (if prev
        (%sched-push-dq! ctx prev))))

;; Wake task onto current carrier's LIFO slot if inside this scheduler, else global-q.
(define (%sched-wake! sched task)
  (let ((ctx (macro-thread-specific (##current-thread))))
    (if (and (%worker-ctx? ctx) (eq? (%wctx-sched ctx) sched))
        (%sched-push-lifo! ctx task)
        (%sched-enqueue-global! sched task))))

;; Sharded quiescence check:
;; Fast-skip while root fiber has not yet finished (root-done == 0 guarantees completed < spawned).
;; Once root-done == 1, scan ALL completed[0..W-1] (acq), seq_cst fence, then ALL spawned[0..W-1] (acq).
(define (%sched-quiescent? sched)
  (if (fx= (%fxatom-load-acq (%sched-root-done sched)) 0)
      #f
      (let ((w (%sched-num-workers sched))
            (cvec (%sched-completed-vec sched))
            (svec (%sched-spawned-vec sched)))
        (let cloop ((i 0) (c 0))
          (if (fx< i w)
              (cloop (fx+ i 1)
                     (fx+ c (%fxatom-load-acq (##vector-ref cvec i))))
              (begin
                (%seq-cst-fence!)
                (let sloop ((j 0) (s 0))
                  (if (fx< j w)
                      (sloop (fx+ j 1)
                             (fx+ s (%fxatom-load-acq (##vector-ref svec j))))
                      (fx= c s)))))))))

;; Bounded CPU pause backoff for idle stealers to reduce cross-core coherence traffic.
(define (%idle-pause-c! spins)
  (macro-if-c-compiled
   (##c-code
    "___WORD ___s = ___INT(___ARG1);
     if (___s > 3) ___s = 3;
     int ___n = 4 << ___s;
     int ___i;
     for (___i = 0; ___i < ___n; ___i++) {
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     ___RESULT = ___VOID;"
    spins)
   #!void))

;;;----------------------------------------------------------------------------
;;; Inline C23 Non-Blocking Spinlock Helper (Bounded C Spin + Safepoint Yield)

(define (%spin-trylock-bounded! box)
  (macro-if-c-compiled
   (##c-code
    "___VOLATILE ___WORD *___p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG1, ___tVECTOR));
     int ___i;
     ___SCMOBJ ___ok = ___FAL;
     for (___i = 0; ___i < 64; ___i++) {
       if (___atomic_word_cas(___p, ___FIX(0), ___FIX(1), 1) == ___FIX(0)) {
         ___ok = ___TRU;
         break;
       }
#if defined(__aarch64__)
       __asm__ __volatile__(\"yield\");
#elif defined(__x86_64__) || defined(__i386__)
       __asm__ __volatile__(\"pause\");
#endif
     }
     ___RESULT = ___ok;"
    box)
   (fx= (%fxatom-cas-acq! box 0 1) 0)))

(define (%spin-lock! box)
  (if (not (%spin-trylock-bounded! box))
      (let loop ()
        (thread-yield!)
        (if (not (%spin-trylock-bounded! box))
            (loop)))))

(define (%spin-unlock! box)
  (%fxatom-set-rel! box 0))

;;;----------------------------------------------------------------------------
;;; Structured Concurrency Nursery
;;; (Zero-Capture Children via ##with-exception-handler + Unwind-Safe Abort)

(define-type nursery
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000003
  constructor: %make-nursery
  predicate: nursery?
  (sched       %nursery-sched)
  (active      %nursery-active)      ;; 128B-padded fxatom (isolated from lock/waiter-k)
  (lock        %nursery-lock)        ;; fxatom spinlock
  (waiter-k    %nursery-waiter-k     %nursery-waiter-k-set!)
  (first-err   %nursery-first-err    %nursery-first-err-set!)
  (has-err?    %nursery-has-err?     %nursery-has-err?-set!)
  (err-handler %nursery-err-handler  %nursery-err-handler-set!))

(define (%nursery-record-error! n exc)
  (%spin-lock! (%nursery-lock n))
  (if (not (%nursery-has-err? n))
      (begin
        (%nursery-has-err?-set! n #t)
        (%nursery-first-err-set! n exc)))
  (%spin-unlock! (%nursery-lock n)))

(define (%nursery-sub-active! n cnt)
  (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) cnt)))
    (if (fx= prev cnt)
        (let ((lock (%nursery-lock n))
              (wk #f))
          (%spin-lock! lock)
          (set! wk (%nursery-waiter-k n))
          (%nursery-waiter-k-set! n #f)
          (%spin-unlock! lock)
          (if wk
              (begin
                (%fk-val-set! wk #!void)
                (%sched-wake! (%nursery-sched n) wk)))))))

(define (%nursery-flush! ctx)
  (let ((cnt (%wctx-nursery-batch ctx)))
    (if (fx> cnt 0)
        (let ((n (%wctx-nursery-cur ctx)))
          (%wctx-nursery-batch-set! ctx 0)
          (%wctx-nursery-cur-set! ctx #f)
          (%nursery-sub-active! n cnt)))))

(define (%nursery-child-done-batched! ctx n)
  (let ((cur (%wctx-nursery-cur ctx)))
    (if (eq? cur n)
        (let ((cnt (fx+ (%wctx-nursery-batch ctx) 1)))
          (if (fx>= cnt %MAX-NURSERY-BATCH)
              (begin
                (%wctx-nursery-batch-set! ctx 0)
                (%wctx-nursery-cur-set! ctx #f)
                (%nursery-sub-active! n cnt))
              (%wctx-nursery-batch-set! ctx cnt)))
        (begin
          (if cur (%nursery-flush! ctx))
          (%wctx-nursery-cur-set! ctx n)
          (%wctx-nursery-batch-set! ctx 1)))))

;; Executed on the clean carrier trampoline AFTER ##continuation-graft has
;; completed all dynamic-wind after thunks of the aborting child fiber.
(define (%nursery-child-abort! n exc)
  (let ((cur-ctx (%current-wctx)))
    (%nursery-flush! cur-ctx)
    (%nursery-record-error! n exc)
    (%nursery-sub-active! n 1)
    (if (%get-tc) (%set-tc! #f))
    (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
    (%worker-dispatch cur-ctx 0)))

;; Zero-closure multi-arg continuation receiver for nursery join park
(define (%park-nursery-cont! raw-k n)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #!void))
         (lock (%nursery-lock n))
         (wake-now? #f))
    (%nursery-flush! ctx)
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (if (fx= (%fxatom-load-acq (%nursery-active n)) 0)
        (set! wake-now? #t)
        (%nursery-waiter-k-set! n fk))
    (%spin-unlock! lock)
    (if wake-now?
        (%sched-push-lifo! ctx fk))
    (%sched-switch-next! ctx)))

(define (with-nursery proc)
  (if (not (procedure? proc))
      (error "with-nursery: expected procedure" proc))
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (n (%make-nursery sched
                           (%make-padded-fxatom 1)
                           (%make-fxatom 0)
                           #f
                           #f
                           #f
                           #f))
         (child-eh (lambda (e)
                     (let ((cur-ctx (%current-wctx)))
                       (##continuation-graft (%wctx-sched-k cur-ctx)
                                             %nursery-child-abort! n e))))
         (parent-res #f))
    (%nursery-err-handler-set! n child-eh)
    (with-exception-catcher
     (lambda (e) (%nursery-record-error! n e))
     (lambda ()
       (set! parent-res (proc n))))
    (%nursery-flush! (%current-wctx))
    (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) 1)))
      (if (fx> prev 1)
          (##continuation-capture %park-nursery-cont! n)))
    (if (%nursery-has-err? n)
        (raise (%nursery-first-err n))
        parent-res)))

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
         /* Push fk onto local runqueue with release tail */
         ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
         ___WORD *___pslot = ___buf_p + (___t & 4095);
         ___GC_WRITE_BARRIER(___ps, ___buf, ___pslot, ___fk);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___pslot), ___CAST(___WORD, ___fk), 0);
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
             ___SCMOBJ ___lifo = ___ctx_f[6];
             ___WORD ___streak = ___INT(___ctx_f[7]);
             if (___lifo != ___FAL && ___STRUCTUREP(___lifo) && ___streak < 8) {
               ___ctx_f[8] = ___FIX(___ticks + 1);
               ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___FAL);
               ___WORD_STORE_RELAXED(&___ctx_f[6], ___FAL);
               ___ctx_f[7] = ___FIX(___streak + 1);
               ___RESULT = ___lifo;
             } else {
               ___WORD ___nt = ___t + 1;
               ___SCMOBJ ___picked = ___FIX(1);
               int ___tries;
               for (___tries = 0; ___tries < 16; ___tries++) {
                 ___WORD ___ch = ___INT(___atomic_word_load(___head_p, 1));
                 if (___ch >= ___nt) break;
                 ___WORD *___s = ___buf_p + (___ch & 4095);
                 ___SCMOBJ ___item = ___gc_atomic_slot_load(___s, 1);
                 if (___atomic_word_cas(___head_p, ___FIX(___ch), ___FIX(___ch + 1), 3) == ___FIX(___ch)) {
                   ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___FAL);
                   ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___FAL), 0);
                   ___ctx_f[8] = ___FIX(___ticks + 1);
                   ___ctx_f[7] = ___FIX(0);
                   ___picked = ___item;
                   break;
                 }
               }
               ___RESULT = ___picked;
             }
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
               (##continuation-return-no-winding nk nval)))
            ((fixnum? res)
             (if (fx= res 1)
                 (%sched-switch-next! ctx)
                 (%yield-slow! ctx raw-k #f)))
            (else
             (##continuation-graft-no-winding
              (%wctx-sched-k ctx) %worker-run-task ctx res)))))))

(define (fiber-yield)
  (##continuation-capture %yield-cont!))

;; Single-C-block fused fiber-spawn push:
;; Increments nursery.active (if n != #f) and owner ctx.spawned BEFORE publishing
;; task into private LIFO (evicting prior occupant to local runqueue with release tail).
;; Returns #f if pushed cleanly, or the evicted task if local runqueue was full (4096).
(define (%fiber-spawn-push-c! ctx task n)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     if (___ARG3 != ___FAL) {
       ___WORD *___n_f = ___BODY_AS(___ARG3, ___tSTRUCTURE);
       ___VOLATILE ___WORD *___act_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___n_f[2], ___tVECTOR));
       ___atomic_uword_fetch_add(___act_p, ___FIX(1), 3);
     }
     ___VOLATILE ___WORD *___sp_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ctx_f[4], ___tVECTOR));
     ___WORD ___cur_sp = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___sp_p)));
     ___atomic_word_store(___sp_p, ___FIX(___cur_sp + 1), 2);
     ___SCMOBJ ___prev = ___ctx_f[6];
     ___GC_WRITE_BARRIER(___ps, ___ARG1, &___ctx_f[6], ___ARG2);
     ___WORD_STORE_RELAXED(&___ctx_f[6], ___ARG2);
     if (___prev == ___FAL) {
       ___RESULT = ___FAL;
     } else {
       ___WORD *___dq_f = ___BODY_AS(___ctx_f[3], ___tSTRUCTURE);
       ___SCMOBJ ___buf = ___dq_f[1];
       ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[2], ___tVECTOR));
       ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___dq_f[3], ___tVECTOR));
       ___WORD ___t = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___h = ___INT(___atomic_word_load(___head_p, 1));
       if (___t - ___h >= 4096) {
         ___RESULT = ___prev;
       } else {
         ___WORD *___s = ___BODY_AS(___buf, ___tVECTOR) + (___t & 4095);
         ___GC_WRITE_BARRIER(___ps, ___buf, ___s, ___prev);
         ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s), ___CAST(___WORD, ___prev), 0);
         ___atomic_word_store(___tail_p, ___FIX(___t + 1), 2);
         ___RESULT = ___FAL;
       }
     }"
    ctx task n)
   (begin
     (if n (%fxatom-add-acqrel! (%nursery-active n) 1))
     (%fxatom-inc-owner-rel! (%wctx-spawned ctx))
     (let ((prev (%wctx-lifo ctx)))
       (%wctx-lifo-set! ctx task)
       (if (and prev (not (%dq-push! (%wctx-dq ctx) prev)))
           prev
           #f)))))

(define (%fiber-spawn-spill! ctx prev)
  (%sched-enqueue-global! (%wctx-sched ctx) prev)
  #!void)

(define (fiber-spawn thunk #!optional (n #f))
  (if (not (procedure? thunk))
      (error "fiber-spawn: expected thunk" thunk)
      (let ((ctx (macro-thread-specific (##current-thread))))
        (if (not (%worker-ctx? ctx))
            (%outside-run-fibers-error!)
            (if n
                (if (not (nursery? n))
                    (error "fiber-spawn: expected nursery" n)
                    (let ((spill (%fiber-spawn-push-c! ctx (cons thunk n) n)))
                      (if spill (%fiber-spawn-spill! ctx spill) #!void)))
                (let ((spill (%fiber-spawn-push-c! ctx thunk #f)))
                  (if spill (%fiber-spawn-spill! ctx spill) #!void)))))))

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
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (%make-fxatom 0)
     (%make-wait-q #f #f)
     (%make-wait-q #f #f))))

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
     ___VOLATILE ___WORD *___rxw_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
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
           ___res = (___INT(___atomic_word_load(___rxw_p, 4)) > 0) ? 1 : 0;
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

;; Slow-path wakeups (called only when waiter count > 0)
(define (%ch-wake-one-receiver! ch)
  (let ((lock (%ch-lock ch))
        (rwq (%ch-recv-waiters ch))
        (rxw (%ch-rx-waiters ch))
        (rk #f)
        (item %CH-EMPTY))
    (%spin-lock! lock)
    (if (not (%wq-empty? rwq))
        (begin
          (set! rk (%wq-pop! rwq))
          (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
          (set! item (%vyukov-try-pop-or! ch %CH-EMPTY))))
    (%spin-unlock! lock)
    (if rk
        (if (not (eq? item %CH-EMPTY))
            (begin
              (if (fx> (%fxatom-load-seq (%ch-tx-waiters ch)) 0)
                  (%ch-wake-one-sender! ch))
              (%fk-val-set! rk item)
              (%sched-push-lifo! (%current-wctx) rk))
            (begin
              (%fk-val-set! rk %CH-RETRY)
              (%sched-push-lifo! (%current-wctx) rk))))))

(define (%ch-wake-one-sender! ch)
  (let ((lock (%ch-lock ch))
        (swq (%ch-send-waiters ch))
        (txw (%ch-tx-waiters ch))
        (sk #f)
        (pushed? #f))
    (%spin-lock! lock)
    (if (not (%wq-empty? swq))
        (begin
          (set! sk (%wq-pop! swq))
          (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
          (set! pushed? (%vyukov-try-push! ch (%fk-val sk)))))
    (%spin-unlock! lock)
    (if sk
        (if pushed?
            (begin
              (if (fx> (%fxatom-load-seq (%ch-rx-waiters ch)) 0)
                  (%ch-wake-one-receiver! ch))
              (%fk-val-set! sk #t)
              (%sched-push-lifo! (%current-wctx) sk))
            (begin
              (%fk-val-set! sk %CH-RETRY)
              (%sched-push-lifo! (%current-wctx) sk))))))

;; Single-C-block fused Dekker park-send for full buffered channels.
;; Returns: #t if parked cleanly, #f if race (ring freed or receiver parked),
;; or retry-tag if lock spin budget exhausted.
(define (%ch-park-send-c! ch fk retry-tag)
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
       ___VOLATILE ___WORD *___txw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[8], ___tVECTOR));
       ___WORD ___cur_txw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___txw_p)));
       ___atomic_word_store(___txw_p, ___FIX(___cur_txw + 1), 4);
       ___WORD ___cap  = ___INT(___f[1]);
       ___WORD ___mask = ___INT(___f[2]);
       ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
       ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
       ___WORD ___pos = ___INT(___atomic_word_load(___tail_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
       ___SCMOBJ ___rwq = ___f[10];
       ___WORD *___rwq_f = ___BODY_AS(___rwq, ___tSTRUCTURE);
       if (___s - (___pos << 1) < 0 && ___rwq_f[1] == ___FAL) {
         ___SCMOBJ ___swq = ___f[11];
         ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
         ___SCMOBJ ___fk = ___ARG2;
         ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
         ___GC_WRITE_BARRIER(___ps, ___fk, &___fk_f[4], ___FAL);
         ___WORD_STORE_RELAXED(&___fk_f[4], ___FAL);
         ___SCMOBJ ___t = ___swq_f[2];
         if (___t == ___FAL) {
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[1], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[1], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[2], ___fk);
         } else {
           ___WORD *___t_f = ___BODY_AS(___t, ___tSTRUCTURE);
           ___GC_WRITE_BARRIER(___ps, ___t, &___t_f[4], ___fk);
           ___WORD_STORE_RELAXED(&___t_f[4], ___fk);
           ___GC_WRITE_BARRIER(___ps, ___swq, &___swq_f[2], ___fk);
           ___WORD_STORE_RELAXED(&___swq_f[2], ___fk);
         }
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___TRU;
       } else {
         ___atomic_word_store(___txw_p, ___FIX(___cur_txw), 4);
         ___atomic_word_store(___lock_p, ___FIX(0), 2);
         ___RESULT = ___FAL;
       }
     }"
    ch fk retry-tag)
   #f))

;; Zero-closure multi-arg park receivers for buffered channels (cap > 0)
(define (%park-send-buf-cont! raw-k ch val)
  (let* ((ctx (%carrier-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc val)))
    (if (fx> (%wctx-nursery-batch ctx) 0) (%nursery-flush! ctx))
    (if tc (%set-tc! #f))
    (let ((fast (%ch-park-send-c! ch fk %CH-RETRY)))
      (if (not (eq? fast #t))
          (let ((lock (%ch-lock ch))
                (rwq (%ch-recv-waiters ch))
                (swq (%ch-send-waiters ch))
                (rxw (%ch-rx-waiters ch))
                (txw (%ch-tx-waiters ch)))
            (if (eq? fast %CH-RETRY) (thread-yield!))
            (%spin-lock! lock)
            (%fxatom-set-seq! txw (fx+ (##vector-ref txw 0) 1))
            (%seq-cst-fence!)
            (cond
              ((and (not (%wq-empty? rwq))
                    (let* ((t (%fxatom-load-acq (%ch-tail ch)))
                           (h (%fxatom-load-acq (%ch-head ch))))
                      (fx= t h)))
               (let ((rk (%wq-pop! rwq)))
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                 (%spin-unlock! lock)
                 (%fk-val-set! rk val)
                 (%fk-val-set! fk #t)
                 (%sched-push-lifo! ctx fk)
                 (%sched-push-lifo! ctx rk)))
              ((%vyukov-try-push! ch val)
               (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
               (%spin-unlock! lock)
               (if (fx> (%fxatom-load-seq rxw) 0)
                   (%ch-wake-one-receiver! ch))
               (%fk-val-set! fk #t)
               (%sched-push-lifo! ctx fk))
              (else
               (%wq-push! swq fk)
               (%spin-unlock! lock))))))
    (%sched-switch-next! ctx)))

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
       ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 0));
       ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
       ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
       ___SCMOBJ ___swq = ___f[11];
       ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
       if (___s - ((___pos << 1) + 1) < 0 && ___swq_f[1] == ___FAL) {
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

;; Single-C-block fused freelist pop + Dekker park-recv + LIFO %fiber-k pop.
;; Returns:
;;   %fiber-k : parked cleanly and popped next runnable %fiber-k directly from ctx.lifo
;;   1        : parked cleanly, caller dispatches via %sched-switch-next!
;;   2        : race (item arrived or sender parked); fk-pool untouched
;;   3        : spinlock budget exhausted; fk-pool untouched
;;   4        : fk-pool empty; caller allocates %fiber-k in Scheme
(define (%ch-park-recv-and-pop-c! ctx ch raw-k)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___ctx_f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___SCMOBJ ___fk = ___ctx_f[10];
     if (___fk == ___FAL) {
       ___RESULT = ___FIX(4);
     } else {
       ___WORD *___f = ___BODY_AS(___ARG2, ___tSTRUCTURE);
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
         ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
         ___WORD ___cur_rxw = ___INT(___WORD_LOAD_RELAXED(___CAST(___WORD*, ___rxw_p)));
         ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw + 1), 4);
         ___WORD ___cap  = ___INT(___f[1]);
         ___WORD ___mask = ___INT(___f[2]);
         ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
         ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
         ___WORD ___pos = ___INT(___atomic_word_load(___head_p, 0));
         ___WORD ___idx = (___mask >= 0) ? (___pos & ___mask) : (___pos % ___cap);
         ___WORD ___s   = ___INT(___atomic_word_load(___seq_p + ___idx, 4));
         ___SCMOBJ ___swq = ___f[11];
         ___WORD *___swq_f = ___BODY_AS(___swq, ___tSTRUCTURE);
         if (___s - ((___pos << 1) + 1) < 0 && ___swq_f[1] == ___FAL) {
           /* Pop fk from private fk-pool and populate fields with GC write barriers */
           ___WORD *___fk_f = ___BODY_AS(___fk, ___tSTRUCTURE);
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
           /* Push fk onto channel recv-waiters FIFO queue */
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
           /* Fused LIFO direct-switch candidate check */
           ___SCMOBJ ___lifo = ___ctx_f[6];
           if (___lifo != ___FAL && ___STRUCTUREP(___lifo)) {
             ___WORD ___ticks = ___INT(___ctx_f[8]);
             int ___need_global = 0;
             if ((___ticks & 31) == 31) {
               ___WORD *___sch_f = ___BODY_AS(___ctx_f[1], ___tSTRUCTURE);
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
                 ___ctx_f[7] = ___FIX((___streak < 8) ? (___streak + 1) : 8);
                 ___RESULT = ___lifo;
               } else {
                 ___RESULT = ___FIX(1);
               }
             } else {
               ___RESULT = ___FIX(1);
             }
           } else {
             ___RESULT = ___FIX(1);
           }
         } else {
           ___atomic_word_store(___rxw_p, ___FIX(___cur_rxw), 4);
           ___atomic_word_store(___lock_p, ___FIX(0), 2);
           ___RESULT = ___FIX(2);
         }
       }
     }"
    ctx ch raw-k)
   4))

(define (%park-recv-buf-slow! ctx raw-k tc ch fast-code)
  (let ((fk (%alloc-fk! ctx raw-k tc #f)))
    (let ((fast (if (fx= fast-code 4)
                    (%ch-park-recv-c! ch fk %CH-RETRY)
                    (if (fx= fast-code 3) %CH-RETRY #f))))
      (if (not (eq? fast #t))
          (let ((lock (%ch-lock ch))
                (rwq (%ch-recv-waiters ch))
                (swq (%ch-send-waiters ch))
                (rxw (%ch-rx-waiters ch))
                (txw (%ch-tx-waiters ch)))
            (if (eq? fast %CH-RETRY) (thread-yield!))
            (%spin-lock! lock)
            (%fxatom-set-seq! rxw (fx+ (##vector-ref rxw 0) 1))
            (%seq-cst-fence!)
            (let ((item (%vyukov-try-pop-or! ch %CH-EMPTY)))
              (cond
                ((not (eq? item %CH-EMPTY))
                 (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                 (%spin-unlock! lock)
                 (if (fx> (%fxatom-load-seq txw) 0)
                     (%ch-wake-one-sender! ch))
                 (%fk-val-set! fk item)
                 (%sched-push-lifo! ctx fk))
                ((not (%wq-empty? swq))
                 (let* ((sk (%wq-pop! swq))
                        (sval (%fk-val sk)))
                   (%fxatom-set-seq! txw (fx- (##vector-ref txw 0) 1))
                   (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))
                   (%spin-unlock! lock)
                   (%fk-val-set! sk #t)
                   (%fk-val-set! fk sval)
                   (%sched-push-lifo! ctx sk)
                   (%sched-push-lifo! ctx fk)))
                (else
                 (%wq-push! rwq fk)
                 (%spin-unlock! lock)))))))
    (%sched-switch-next! ctx)))

(define (%park-recv-buf-cont! raw-k ch)
  (let ((ctx (%carrier-wctx))
        (tc (%get-tc)))
    (if (fx> (%wctx-nursery-batch ctx) 0) (%nursery-flush! ctx))
    (if tc (%set-tc! #f))
    (let ((res (if (not tc) (%ch-park-recv-and-pop-c! ctx ch raw-k) 4)))
      (cond
        ((%fiber-k? res)
         (let ((nk (%fk-raw-k res))
               (ntc (%fk-tc res))
               (nval (%fk-val res)))
           (%free-fk! ctx res)
           (if ntc (%set-tc! ntc))
           (##continuation-return-no-winding nk nval)))
        ((fx= res 1)
         (%sched-switch-next! ctx))
        (else
         (%park-recv-buf-slow! ctx raw-k tc ch res))))))

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
    (if (not (%wq-empty? rwq))
        (let ((rk (%wq-pop! rwq)))
          (%spin-unlock! lock)
          (%fk-val-set! rk val)
          (%fk-val-set! fk #t)
          (%sched-push-lifo! ctx fk)
          (%sched-push-lifo! ctx rk))
        (begin
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
    (if (not (%wq-empty? swq))
        (let* ((sk (%wq-pop! swq))
               (sval (%fk-val sk)))
          (%spin-unlock! lock)
          (%fk-val-set! sk #t)
          (%fk-val-set! fk sval)
          (%sched-push-lifo! ctx sk)
          (%sched-push-lifo! ctx fk))
        (begin
          (%wq-push! rwq fk)
          (%spin-unlock! lock)))
    (%sched-switch-next! ctx)))

;; Single-C-block fused buffered send (linearizable direct handoff + bounded-retry Vyukov push).
;; Returns:
;;   #t        : pushed into ring and rx-waiters == 0 (immediate return)
;;   %fiber-k  : handed off directly to parked receiver (caller pushes onto LIFO slot)
;;   1         : pushed into ring and rx-waiters > 0 (caller wakes one receiver)
;;   2         : ring full (caller parks)
;;   3         : Vyukov CAS retry budget exhausted (caller polls safepoint and retries)
;;   4         : unbuffered channel (cap == 0)
;;   5         : direct-handoff spinlock budget exhausted (caller yields and retries)
(define (%ch-send-fast-c! ch val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___WORD ___cap = ___INT(___f[1]);
     if (___cap <= 0) {
       ___RESULT = ___FIX(4);
     } else {
       ___VOLATILE ___WORD *___rxw_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[7], ___tVECTOR));
       ___SCMOBJ ___out = ___FAL;
       int ___done = 0;
       if (___INT(___atomic_word_load(___rxw_p, 0)) > 0) {
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
             ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
             ___VOLATILE ___WORD *___head_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[6], ___tVECTOR));
             ___WORD ___t = ___atomic_word_load(___tail_p, 1);
             ___WORD ___h = ___atomic_word_load(___head_p, 1);
             if (___t == ___h) {
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
               ___out = ___rk;
               ___done = 1;
             }
           }
           ___atomic_word_store(___lock_p, ___FIX(0), 2);
         }
       }
       if (!___done) {
         ___WORD ___mask = ___INT(___f[2]);
         ___SCMOBJ ___buf = ___f[3];
         ___VOLATILE ___WORD *___seq_p  = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[4], ___tVECTOR));
         ___VOLATILE ___WORD *___tail_p = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___f[5], ___tVECTOR));
         ___WORD *___buf_p = ___BODY_AS(___buf, ___tVECTOR);
         ___SCMOBJ ___val = ___ARG2;
         ___out = ___FIX(3);
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
               ___out = (___INT(___atomic_word_load(___rxw_p, 4)) > 0) ? ___FIX(1) : ___TRU;
               break;
             }
           } else if (___dif < 0) {
             ___out = ___FIX(2);
             break;
           }
         }
       }
       ___RESULT = ___out;
     }"
    ch val)
   (if (fx<= (%ch-cap ch) 0)
       4
       (let ((rxw (%ch-rx-waiters ch))
             (rk #f))
         (if (fx> (%fxatom-load-rlx rxw) 0)
             (let ((lock (%ch-lock ch))
                   (rwq (%ch-recv-waiters ch)))
               (%spin-lock! lock)
               (if (and (not (%wq-empty? rwq))
                        (let* ((t (%fxatom-load-acq (%ch-tail ch)))
                               (h (%fxatom-load-acq (%ch-head ch))))
                          (fx= t h)))
                   (begin
                     (set! rk (%wq-pop! rwq))
                     (%fk-val-set! rk val)
                     (%fxatom-set-seq! rxw (fx- (##vector-ref rxw 0) 1))))
               (%spin-unlock! lock)))
         (if rk
             rk
             (let ((st (%vyukov-try-push-c! ch val)))
               (if (fx= st 0) #t st)))))))

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

(define (%fiber-send-evict-and-true! ctx prev)
  (%sched-push-dq! ctx prev)
  #t)

(define (%fiber-send-slow! ch val st)
  (cond
    ((fx= st 1)
     (%ch-wake-one-receiver! ch)
     #t)
    ((fx= st 2)
     (let ((res (##continuation-capture %park-send-buf-cont! ch val)))
       (if (eq? res %CH-RETRY)
           (fiber-send! ch val)
           #t)))
    ((fx= st 3)
     (fiber-send! ch val))
    ((fx= st 5)
     (thread-yield!)
     (fiber-send! ch val))
    (else
     ;; Unbuffered rendezvous (cap == 0) with relaxed hint
     (let ((rwq (%ch-recv-waiters ch)))
       (if (not (%wq-head rwq))
           (##continuation-capture %park-send-unbuf-cont! ch val)
           (let ((lock (%ch-lock ch)))
             (%spin-lock! lock)
             (if (not (%wq-empty? rwq))
                 (let ((rk (%wq-pop! rwq)))
                   (%spin-unlock! lock)
                   (%fk-val-set! rk val)
                   (%sched-push-lifo! (%current-wctx) rk)
                   #t)
                 (begin
                   (%spin-unlock! lock)
                   (##continuation-capture %park-send-unbuf-cont! ch val)))))))))

(define (fiber-send! ch val)
  (if (not (fiber-channel? ch))
      (error "fiber-send!: expected fiber-channel" ch)
      (let ((st (%ch-send-fast-c! ch val)))
        (cond
          ((eq? st #t) #t)
          ((fixnum? st) (%fiber-send-slow! ch val st))
          (else
           (let* ((ctx (%carrier-wctx))
                  (prev (%wctx-lifo ctx)))
             (%wctx-lifo-set! ctx st)
             (if prev
                 (%fiber-send-evict-and-true! ctx prev)
                 #t)))))))

(define (%fiber-recv-wake-and-ret! ch item)
  (%ch-wake-one-sender! ch)
  item)

(define (%fiber-recv-park! ch)
  (let ((res (##continuation-capture %park-recv-buf-cont! ch)))
    (if (eq? res %CH-RETRY)
        (fiber-recv! ch)
        res)))

(define (%fiber-recv-slow! ch)
  (if (fx> (%ch-cap ch) 0)
      (fiber-recv! ch)
      ;; Unbuffered rendezvous (cap == 0) with relaxed hint
      (let ((swq (%ch-send-waiters ch)))
        (if (not (%wq-head swq))
            (##continuation-capture %park-recv-unbuf-cont! ch)
            (let ((lock (%ch-lock ch)))
              (%spin-lock! lock)
              (if (not (%wq-empty? swq))
                  (let* ((sk (%wq-pop! swq))
                         (sval (%fk-val sk)))
                    (%spin-unlock! lock)
                    (%fk-val-set! sk #t)
                    (%sched-push-lifo! (%current-wctx) sk)
                    sval)
                  (begin
                    (%spin-unlock! lock)
                    (##continuation-capture %park-recv-unbuf-cont! ch))))))))

(define (fiber-recv! ch)
  (if (not (fiber-channel? ch))
      (error "fiber-recv!: expected fiber-channel" ch)
      (let ((item (%ch-recv-fast-c! ch %CH-EMPTY %CH-RETRY)))
        (cond
          ((eq? item %CH-EMPTY) (%fiber-recv-park! ch))
          ((eq? item %CH-RETRY) (%fiber-recv-slow! ch))
          ((fx= (%fxatom-load-seq (%ch-tx-waiters ch)) 0) item)
          (else (%fiber-recv-wake-and-ret! ch item))))))

;;;----------------------------------------------------------------------------
;;; Multi-Core M:N Work-Stealing Direct-Switch Trampoline
;;; (Sticky Victim Locality + Inline Chase-Lev Deque + Recycled %fiber-k)

(define (%worker-try-steal ctx num-workers deques)
  (if (fx<= num-workers 1)
      #f
      (let ((wid (%wctx-wid ctx))
            (local-dq (%wctx-dq ctx))
            (start (%wctx-steal-cursor ctx)))
        (let loop ((tried 1) (victim start))
          (if (fx>= tried num-workers)
              #f
              (let ((v (if (fx= victim wid)
                           (let ((n (fx+ victim 1)))
                             (if (fx>= n num-workers) 0 n))
                           victim)))
                (let ((task (%dq-steal-batch! (##vector-ref deques v) local-dq)))
                  (if task
                      (begin
                        (%wctx-steal-cursor-set! ctx v)
                        task)
                      (let ((nxt (fx+ v 1)))
                        (loop (fx+ tried 1)
                              (if (fx>= nxt num-workers) 0 nxt)))))))))))

(define (%worker-poll-task ctx)
  (let* ((sched (%wctx-sched ctx))
         (ticks (%wctx-ticks ctx))
         (local-dq (%wctx-dq ctx))
         (task #f))
    (%wctx-ticks-set! ctx (fx+ ticks 1))
    ;; 0. Every 32 ticks poll global-q for fairness (skipped in 1 load if empty!)
    (if (fx= (fxand ticks 31) 31)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 1. Fastest path: private LIFO slot (0 atomics, 0 fences!) if streak < 8
    (if (and (not task)
             (%wctx-lifo ctx)
             (fx< (%wctx-lifo-streak ctx) %MAX-LIFO-STREAK))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx (fx+ (%wctx-lifo-streak ctx) 1))))
    ;; 2. Local inline Chase-Lev deque (zero cross-module calls)
    (if (not task)
        (let ((t (%dq-pop! local-dq)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 3. Fallback to LIFO slot if streak hit limit but local-dq was empty
    (if (and (not task) (%wctx-lifo ctx))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx 0)))
    ;; 4. Global lock-free wakeup/overflow queue (fast-skipped when pending == 0)
    (if (not task)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 5. Sticky victim-locality FIFO work-steal from peer inline deques
    (if (not task)
        (let ((stolen (%worker-try-steal ctx
                                         (%sched-num-workers sched)
                                         (%sched-deques sched))))
          (if stolen
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task stolen)))))
    task))

;; Direct symmetric coroutine handoff with %fiber-k freelist recycling,
;; global-pending-guarded 32-tick fairness skip, empty-deque LIFO-streak bypass,
;; direct %dq-pop! switch, and lazy #f control-state restore.
(define (%sched-switch-next! ctx)
  (let* ((ticks (%wctx-ticks ctx))
         (lifo (%wctx-lifo ctx))
         (streak (%wctx-lifo-streak ctx))
         (dq (%wctx-dq ctx))
         (need-global (and (fx= (fxand ticks 31) 31)
                           (fx> (%fxatom-load-rlx (%sched-global-pending (%wctx-sched ctx))) 0))))
    (if (and (fx= (fxand ticks 15) 15) (fx> (%wctx-nursery-batch ctx) 0))
        (%nursery-flush! ctx))
    (if (and lifo
             (%fiber-k? lifo)
             (not need-global)
             (or (fx< streak %MAX-LIFO-STREAK) (%dq-empty-rlx? dq)))
        (let ((raw-k (%fk-raw-k lifo))
              (tc (%fk-tc lifo))
              (val (%fk-val lifo)))
          (%wctx-ticks-set! ctx (fx+ ticks 1))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-streak-set! ctx
            (if (fx< streak %MAX-LIFO-STREAK) (fx+ streak 1) %MAX-LIFO-STREAK))
          (%free-fk! ctx lifo)
          (if tc (%set-tc! tc))
          (##continuation-return-no-winding raw-k val))
        (if (and (not need-global)
                 (not (%dq-empty-rlx? dq)))
            (let ((t (%dq-pop! dq)))
              (if t
                  (begin
                    (%wctx-ticks-set! ctx (fx+ ticks 1))
                    (%wctx-lifo-streak-set! ctx 0)
                    (if (%fiber-k? t)
                        (let ((raw-k (%fk-raw-k t))
                              (tc (%fk-tc t))
                              (val (%fk-val t)))
                          (%free-fk! ctx t)
                          (if tc (%set-tc! tc))
                          (##continuation-return-no-winding raw-k val))
                        (##continuation-graft-no-winding
                         (%wctx-sched-k ctx) %worker-run-task ctx t)))
                  (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0)))
            (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0)))))

(define (%worker-run-task ctx task)
  (cond
    ((%fiber-k? task)
     (let ((raw-k (%fk-raw-k task))
           (tc (%fk-tc task))
           (val (%fk-val task)))
       (%free-fk! ctx task)
       (if tc (%set-tc! tc))
       (##continuation-return-no-winding raw-k val)))
    ((pair? task)
     ;; Zero-capture, zero-closure nursery child: (thunk . nursery)
     (let ((fn (car task))
           (n (cdr task)))
       (##with-exception-handler (%nursery-err-handler n) fn)
       (let ((cur-ctx (%carrier-wctx)))
         (%nursery-child-done-batched! cur-ctx n)
         (if (%get-tc) (%set-tc! #f))
         (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
         (%sched-switch-next! cur-ctx))))
    (else
     ;; Detached fiber thunk
     (task)
     (let ((cur-ctx (%carrier-wctx)))
       (if (%get-tc) (%set-tc! #f))
       (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
       (%sched-switch-next! cur-ctx)))))

(define (%worker-dispatch ctx idle-spins)
  (let ((task (%worker-poll-task ctx)))
    (if task
        (%worker-run-task ctx task)
        (begin
          (if (fx> (%wctx-nursery-batch ctx) 0) (%nursery-flush! ctx))
          (if (%wctx-lifo ctx)
              (%worker-dispatch ctx 0)
              (if (%sched-quiescent? (%wctx-sched ctx))
                  #!void
                  (begin
                    (%idle-pause-c! idle-spins)
                    (if (fx>= idle-spins 8)
                        (begin (thread-yield!) (%worker-dispatch ctx 0))
                        (%worker-dispatch ctx (fx+ idle-spins 1))))))))))

(define (%worker-loop sched wid)
  (let* ((w (%sched-num-workers sched))
         (deques (%sched-deques sched))
         (local-dq (##vector-ref deques wid))
         (spawned (##vector-ref (%sched-spawned-vec sched) wid))
         (completed (##vector-ref (%sched-completed-vec sched) wid))
         (init-victim (if (fx> w 1)
                          (let ((n (fx+ wid 1))) (if (fx>= n w) 0 n))
                          0))
         (ctx (%make-worker-ctx sched wid local-dq spawned completed
                                #f 0 0 #f #f 0 init-victim #f 0)))
    (%set-carrier-qos!)
    (macro-thread-specific-set! (##current-thread) ctx)
    (if (%get-tc) (%set-tc! #f))
    ;; Capture the carrier's single reusable trampoline continuation once
    (##continuation-capture
     (lambda (base-k)
       (%wctx-sched-k-set! ctx base-k)
       (%worker-dispatch ctx 0)))))

(define (run-fibers thunk #!key (workers (fiber-performance-core-count)))
  (if (not (procedure? thunk))
      (error "run-fibers: expected thunk" thunk))
  (let* ((w (max 1 (if (fixnum? workers) workers 1)))
         (deques (let ((v (make-vector w #f)))
                   (let loop ((i 0))
                     (if (fx< i w)
                         (begin (##vector-set! v i (%make-local-dq))
                                (loop (fx+ i 1)))))
                   v))
         (spawned-vec (let ((v (make-vector w #f)))
                        (let loop ((i 0))
                          (if (fx< i w)
                              (begin (##vector-set! v i (%make-padded-fxatom (if (fx= i 0) 1 0)))
                                     (loop (fx+ i 1)))))
                        v))
         (completed-vec (let ((v (make-vector w #f)))
                          (let loop ((i 0))
                            (if (fx< i w)
                                (begin (##vector-set! v i (%make-padded-fxatom 0))
                                       (loop (fx+ i 1)))))
                          v))
         (global-q (make-lf-queue))
         (global-pending (%make-padded-fxatom 0))
         (root-done (%make-fxatom 0))
         (root-box (cons #f #f))
         (sched (%make-scheduler w deques global-q global-pending
                                 spawned-vec completed-vec root-done root-box)))
    (%sched-enqueue-global!
     sched
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (set-car! root-box #f)
          (set-cdr! root-box e)
          (%fxatom-set-rel! root-done 1))
        (lambda ()
          (let ((res (thunk)))
            (set-car! root-box #t)
            (set-cdr! root-box res)
            (%fxatom-set-rel! root-done 1))))))
    (let ((threads
           (let loop ((i 0) (acc '()))
             (if (fx= i w)
                 acc
                 (loop (fx+ i 1)
                       (cons (thread-start!
                              (make-thread
                               (lambda () (%worker-loop sched i))))
                             acc))))))
      (for-each thread-join! threads))
    (if (car root-box)
        (cdr root-box)
        (raise (cdr root-box)))))

;;;============================================================================
