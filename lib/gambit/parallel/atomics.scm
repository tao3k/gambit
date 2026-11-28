;;;============================================================================

;;; File: "atomics.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Inline C23 128B-Padded Atomics & GC-Barriered Slot Primitives
;;;
;;; Memory-order codes match Gambit runtime_protocols:
;;;   0=relaxed, 1=acquire, 2=release, 3=acq_rel, 4=seq_cst

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
     ___RESULT = ___gc_atomic_slot_load(___s, 0);"
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
