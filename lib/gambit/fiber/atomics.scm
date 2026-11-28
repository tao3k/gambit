;;;============================================================================

;;; File: "atomics.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Inline C23 Atomics, Hardware Topology, OS Futex/Ulock Parker & Spinlocks

(macro-if-c-compiled
 (c-declare
  "#include <stdlib.h>
#include <stdint.h>
#ifdef __APPLE__
#include <sys/sysctl.h>
#include <pthread/qos.h>
extern int __ulock_wait(uint32_t operation, void *addr, uint64_t value, uint32_t timeout);
extern int __ulock_wake(uint32_t operation, void *addr, uint64_t wake_value);
#define FIBER_UL_COMPARE_AND_WAIT 1u
#define FIBER_ULF_WAKE_ALL        0x00000100u
#define FIBER_ULF_NO_ERRNO        0x01000000u
#elif defined(__linux__)
#include <unistd.h>
#include <time.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#endif
#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#include <sched.h>
#endif

typedef struct {
  uint32_t seq;
  char pad1[124];
  uint32_t waiters;
  char pad2[124];
} fiber_os_parker_t;

static inline void fiber_parker_wake_one_ptr(fiber_os_parker_t *p, ___VOLATILE ___WORD *searching_p) {
  if (!p) return;
#ifdef __aarch64__
  /* ARMv8-A RCsc: prior STLR (dq.tail/global-pending) + LDAR (waiters) is seq-cst ordered */
  if (__atomic_load_n(&p->waiters, __ATOMIC_SEQ_CST) > 0u &&
      (!searching_p || ___INT(___atomic_word_load(searching_p, 0)) == 0)) {
#else
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  if (__atomic_load_n(&p->waiters, __ATOMIC_RELAXED) > 0u &&
      (!searching_p || ___INT(___atomic_word_load(searching_p, 0)) == 0)) {
#endif
    __atomic_fetch_add(&p->seq, 1u, __ATOMIC_SEQ_CST);
#ifdef __APPLE__
    (void)__ulock_wake(FIBER_UL_COMPARE_AND_WAIT | FIBER_ULF_NO_ERRNO, &p->seq, 0);
#elif defined(__linux__)
    (void)syscall(SYS_futex, &p->seq, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
#endif
  }
}

static inline void fiber_parker_wake_all_ptr(fiber_os_parker_t *p) {
  if (!p) return;
  __atomic_fetch_add(&p->seq, 1u, __ATOMIC_SEQ_CST);
#ifdef __APPLE__
  (void)__ulock_wake(FIBER_UL_COMPARE_AND_WAIT | FIBER_ULF_WAKE_ALL | FIBER_ULF_NO_ERRNO, &p->seq, 0);
#elif defined(__linux__)
  (void)syscall(SYS_futex, &p->seq, FUTEX_WAKE_PRIVATE, 0x7fffffff, NULL, NULL, 0);
#endif
}
")
 (begin))

(define %parker-finish-wait-ffi!
  (macro-if-c-compiled
   (c-lambda (unsigned-int64 unsigned-int32) void
     "fiber_os_parker_t *p = (fiber_os_parker_t *)(uintptr_t)___arg1;
      uint32_t seq = ___arg2;
      if (p) {
        ___BEGIN_BLOCKING_FFI;
#ifdef __APPLE__
        (void)__ulock_wait(FIBER_UL_COMPARE_AND_WAIT | FIBER_ULF_NO_ERRNO, &p->seq, seq, 2000u);
#elif defined(__linux__)
        struct timespec ts;
        ts.tv_sec = 0;
        ts.tv_nsec = 2000000;
        (void)syscall(SYS_futex, &p->seq, FUTEX_WAIT_PRIVATE, seq, &ts, NULL, 0);
#else
        sched_yield();
#endif
        ___END_BLOCKING_FFI;
        __atomic_fetch_sub(&p->waiters, 1u, __ATOMIC_RELAXED);
      }")
   (lambda (addr seq) (thread-yield!))))

(define (%make-parker)
  (macro-if-c-compiled
   (let ((v (make-u64vector 1 0)))
     (##c-code
      "fiber_os_parker_t *___p = (fiber_os_parker_t *)calloc(1, sizeof(fiber_os_parker_t));
       (___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR)))[0] = (___U64)(uintptr_t)___p;
       ___RESULT = ___VOID;"
      v)
     v)
   #f))

(define (%destroy-parker! parker)
  (macro-if-c-compiled
   (if parker
       (##c-code
        "___U64 *___vp = ___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR));
         fiber_os_parker_t *___p = (fiber_os_parker_t *)(uintptr_t)___vp[0];
         ___vp[0] = 0;
         if (___p) free(___p);
         ___RESULT = ___VOID;"
        parker))
   #!void))

(define (%parker-wake-one! sched)
  (macro-if-c-compiled
   (let ((parker (%sched-parker sched)))
     (if parker
         (##c-code
          "fiber_os_parker_t *___p = (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR)))[0];
           ___VOLATILE ___WORD *___sp = ___CAST(___VOLATILE ___WORD*, ___BODY_AS(___ARG2, ___tVECTOR));
           fiber_parker_wake_one_ptr(___p, ___sp);
           ___RESULT = ___VOID;"
          parker (%sched-searching sched))))
   #!void))

(define (%parker-wake-all! parker)
  (macro-if-c-compiled
   (if parker
       (##c-code
        "fiber_os_parker_t *___p = (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR)))[0];
         fiber_parker_wake_all_ptr(___p);
         ___RESULT = ___VOID;"
        parker))
   #!void))

(define (%parker-begin-wait! parker)
  (macro-if-c-compiled
   (##c-code
    "fiber_os_parker_t *___p = (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR)))[0];
     uint32_t ___s = 0;
     if (___p) {
       ___s = __atomic_load_n(&___p->seq, __ATOMIC_ACQUIRE);
       __atomic_fetch_add(&___p->waiters, 1u, __ATOMIC_SEQ_CST);
     }
     ___RESULT = ___FIX(___s);"
    parker)
   0))

(define (%parker-abort-wait! parker)
  (macro-if-c-compiled
   (##c-code
    "fiber_os_parker_t *___p = (fiber_os_parker_t *)(uintptr_t)(___CAST(___U64*, ___BODY_AS(___ARG1, ___tU64VECTOR)))[0];
     if (___p) __atomic_fetch_sub(&___p->waiters, 1u, __ATOMIC_RELAXED);
     ___RESULT = ___VOID;"
    parker)
   #!void))

(define (%parker-finish-wait! parker seq)
  (macro-if-c-compiled
   (%parker-finish-wait-ffi! (u64vector-ref parker 0) seq)
   (thread-yield!)))

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

(define (%os-sched-yield!)
  (macro-if-c-compiled
   (##c-code
    "#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
     sched_yield();
#endif
     ___RESULT = ___VOID;")
   (thread-yield!)))

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
