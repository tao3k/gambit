;;;============================================================================

;;; File: "230.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 230, Atomic Operations
;;;
;;; Lowered to native C23 atomics + generational card + Yuasa SATB barriers
;;; (___gc_atomic_slot_* & ___atomic_uword_fetch_*) when compiled for C target,
;;; with a 100% atomic GC-barriered ##vector-cas!/##vector-inc! fallback when
;;; interpreted directly by gsi without precompiled .o1 modules.

(##supply-module srfi/230)

(##namespace ("srfi/230#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")

(##include "230#.scm")

(declare (extended-bindings))
(declare (not safe))
(declare (block))

;;;============================================================================
;;; Compile-time target detection: C-compiled (gsc) vs interpreted (gsi)
;;;============================================================================

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

;;;============================================================================
;;; Memory Order Encoding
;;;   0 = relaxed
;;;   1 = acquire
;;;   2 = release
;;;   3 = acquire-release
;;;   4 = sequentially-consistent
;;;============================================================================

(define (memory-order? obj)
  (or (##eq? obj 'relaxed)
      (##eq? obj 'acquire)
      (##eq? obj 'release)
      (##eq? obj 'acquire-release)
      (##eq? obj 'sequentially-consistent)))

(define (bad-memory-order order proc)
  (##raise-type-exception 1 'memory-order proc (##list order)))

(##define-macro (macro-order->code order proc)
  `(cond ((##eq? ,order 'acquire) 1)
         ((##eq? ,order 'relaxed) 0)
         ((##eq? ,order 'release) 2)
         ((##eq? ,order 'sequentially-consistent) 4)
         ((##eq? ,order 'acquire-release) 3)
         (else (bad-memory-order ,order ,proc))))

(##define-macro (macro-load-order->code order proc)
  `(cond ((##eq? ,order 'acquire) 1)
         ((##eq? ,order 'relaxed) 0)
         ((##eq? ,order 'sequentially-consistent) 4)
         (else (bad-memory-order ,order ,proc))))

(##define-macro (macro-store-order->code order proc)
  `(cond ((##eq? ,order 'release) 2)
         ((##eq? ,order 'relaxed) 0)
         ((##eq? ,order 'sequentially-consistent) 4)
         (else (bad-memory-order ,order ,proc))))

(##define-macro (macro-dispatch-load-order order proc op . args)
  `(cond ((##eq? ,order 'acquire) (,op ,@args 1))
         ((##eq? ,order 'relaxed) (,op ,@args 0))
         ((##eq? ,order 'sequentially-consistent) (,op ,@args 4))
         (else (bad-memory-order ,order ,proc))))

(##define-macro (macro-dispatch-store-order order proc op . args)
  `(cond ((##eq? ,order 'release) (,op ,@args 2))
         ((##eq? ,order 'relaxed) (,op ,@args 0))
         ((##eq? ,order 'sequentially-consistent) (,op ,@args 4))
         (else (bad-memory-order ,order ,proc))))

(##define-macro (macro-dispatch-rmw-order order proc op . args)
  `(cond ((##eq? ,order 'acquire) (,op ,@args 1))
         ((##eq? ,order 'relaxed) (,op ,@args 0))
         ((##eq? ,order 'release) (,op ,@args 2))
         ((##eq? ,order 'sequentially-consistent) (,op ,@args 4))
         ((##eq? ,order 'acquire-release) (,op ,@args 3))
         (else (bad-memory-order ,order ,proc))))

;;;============================================================================
;;; Low-Level Inline GC-Barriered Vector-Slot Atomic Macros
;;;============================================================================

(define fence-scratch (##vector 0))

(##define-macro (macro-raw-fence! code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append "___atomic_fence_order(" (number->string code) "); ___RESULT = ___VOID;"))
         `(##c-code "___atomic_fence_order((int)___INT(___ARG1)); ___RESULT = ___VOID;"
                    ,code))
    (begin
      (##vector-cas! fence-scratch 0 0 0)
      (##void))))

(##define-macro (macro-raw-slot-load vec idx code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___gc_atomic_slot_load(___s, " (number->string code) ");")
           ,vec ,idx)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___gc_atomic_slot_load(___s, (int)___INT(___ARG3));"
           ,vec ,idx ,code))
    (##vector-cas! ,vec ,idx #!unbound #!unbound)))

(##define-macro (macro-raw-slot-exchange! vec idx newval code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___gc_atomic_slot_exchange(
                ___ps, ___ARG1, ___s, ___ARG3, " (number->string code) ",
                ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));")
           ,vec ,idx ,newval)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___gc_atomic_slot_exchange(
              ___ps, ___ARG1, ___s, ___ARG3, (int)___INT(___ARG4),
              ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));"
           ,vec ,idx ,newval ,code))
    (let ((v ,vec) (i ,idx) (nv ,newval))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let ((prev (##vector-cas! v i nv old)))
          (if (##eq? prev old)
              old
              (loop prev)))))))

(##define-macro (macro-raw-slot-store-void! vec idx newval code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___gc_atomic_slot_exchange(
                ___ps, ___ARG1, ___s, ___ARG3, " (number->string code) ",
                ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
              ___RESULT = ___VOID;")
           ,vec ,idx ,newval)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___gc_atomic_slot_exchange(
              ___ps, ___ARG1, ___s, ___ARG3, (int)___INT(___ARG4),
              ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));
            ___RESULT = ___VOID;"
           ,vec ,idx ,newval ,code))
    (begin
      (macro-raw-slot-exchange! ,vec ,idx ,newval ,code)
      (##void))))

(##define-macro (macro-raw-slot-cas! vec idx expected desired code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___gc_atomic_slot_cas(
                ___ps, ___ARG1, ___s, ___ARG3, ___ARG4, " (number->string code) ",
                ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));")
           ,vec ,idx ,expected ,desired)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___gc_atomic_slot_cas(
              ___ps, ___ARG1, ___s, ___ARG3, ___ARG4, (int)___INT(___ARG5),
              ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));"
           ,vec ,idx ,expected ,desired ,code))
    (##vector-cas! ,vec ,idx ,desired ,expected)))

(##define-macro (macro-raw-fx-load vec idx code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___s), " (number->string code) "));")
           ,vec ,idx)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___s), (int)___INT(___ARG3)));"
           ,vec ,idx ,code))
    (##vector-cas! ,vec ,idx #!unbound #!unbound)))

(##define-macro (macro-raw-fx-store! vec idx val code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s),
                                   ___CAST(___WORD, ___ARG3), " (number->string code) ");
              ___RESULT = ___VOID;")
           ,vec ,idx ,val)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4));
            ___RESULT = ___VOID;"
           ,vec ,idx ,val ,code))
    (let ((v ,vec) (i ,idx) (nv ,val))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let ((prev (##vector-cas! v i nv old)))
          (if (##eq? prev old) (##void) (loop prev)))))))

(##define-macro (macro-raw-fx-exchange! vec idx val code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_word_exchange(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,val)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_word_exchange(___CAST(___VOLATILE ___WORD*, ___s),
                                      ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,val ,code))
    (let ((v ,vec) (i ,idx) (nv ,val))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let ((prev (##vector-cas! v i nv old)))
          (if (##eq? prev old) old (loop prev)))))))

(##define-macro (macro-raw-flag-tas! vec idx code)
  `(##not (##fx= (macro-raw-fx-exchange! ,vec ,idx 1 ,code) 0)))

(##define-macro (macro-raw-fx-cas! vec idx expected desired code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___s),
                                   ___CAST(___WORD, ___ARG3),
                                   ___CAST(___WORD, ___ARG4), " (number->string code) "));")
           ,vec ,idx ,expected ,desired)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3),
                                 ___CAST(___WORD, ___ARG4), (int)___INT(___ARG5)));"
           ,vec ,idx ,expected ,desired ,code))
    (##vector-cas! ,vec ,idx ,desired ,expected)))

(##define-macro (macro-raw-fx-fetch-add! vec idx delta code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___s),
                                          ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,delta)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,delta ,code))
    (##vector-inc! ,vec ,idx ,delta)))

(##define-macro (macro-raw-fx-fetch-sub! vec idx delta code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___s),
                                          ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,delta)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,delta ,code))
    (let ((v ,vec) (i ,idx) (d ,delta))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let* ((next (##fxwrap- old d))
               (prev (##vector-cas! v i next old)))
          (if (##eq? prev old) old (loop prev)))))))

(##define-macro (macro-raw-fx-fetch-and! vec idx mask code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_uword_fetch_and(___CAST(___VOLATILE ___WORD*, ___s),
                                          ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,mask)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_uword_fetch_and(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,mask ,code))
    (let ((v ,vec) (i ,idx) (m ,mask))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let* ((next (##fxand old m))
               (prev (##vector-cas! v i next old)))
          (if (##eq? prev old) old (loop prev)))))))

(##define-macro (macro-raw-fx-fetch-ior! vec idx mask code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_uword_fetch_ior(___CAST(___VOLATILE ___WORD*, ___s),
                                          ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,mask)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_uword_fetch_ior(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,mask ,code))
    (let ((v ,vec) (i ,idx) (m ,mask))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let* ((next (##fxior old m))
               (prev (##vector-cas! v i next old)))
          (if (##eq? prev old) old (loop prev)))))))

(##define-macro (macro-raw-fx-fetch-xor! vec idx mask code)
  `(macro-if-c-compiled
    ,(if (##fixnum? code)
         `(##c-code
           ,(string-append
             "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
              ___RESULT = ___CAST(___SCMOBJ,
                ___atomic_uword_fetch_xor(___CAST(___VOLATILE ___WORD*, ___s),
                                          ___CAST(___WORD, ___ARG3), " (number->string code) "));")
           ,vec ,idx ,mask)
         `(##c-code
           "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
            ___RESULT = ___CAST(___SCMOBJ,
              ___atomic_uword_fetch_xor(___CAST(___VOLATILE ___WORD*, ___s),
                                        ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
           ,vec ,idx ,mask ,code))
    (let ((v ,vec) (i ,idx) (m ,mask))
      (let loop ((old (##vector-cas! v i #!unbound #!unbound)))
        (let* ((next (##fxxor old m))
               (prev (##vector-cas! v i next old)))
          (if (##eq? prev old) old (loop prev)))))))

;;; Exported internal helpers for (gambit parallel) Chase-Lev ring buffer
;;; (prevents C23/TSan speculative stealer data races on wrapped ring slots).
(##define-macro (macro-with-vector-index vec idx proc body)
  `(if (##vector? ,vec)
       (if (##fixnum? ,idx)
           (if (and (##fx>= ,idx 0) (##fx< ,idx (##vector-length ,vec)))
               ,body
               (##raise-range-exception 2 ,proc ,vec ,idx))
           (##raise-type-exception 2 'fixnum ,proc (##list ,vec ,idx)))
       (##raise-type-exception 1 'vector ,proc (##list ,vec ,idx))))

(define (vector-atomic-ref vec idx #!optional (order 'sequentially-consistent))
  (macro-with-vector-index vec idx vector-atomic-ref
    (macro-dispatch-load-order order vector-atomic-ref macro-raw-slot-load vec idx)))

(define (vector-atomic-set! vec idx val #!optional (order 'sequentially-consistent))
  (macro-with-vector-index vec idx vector-atomic-set!
    (macro-dispatch-store-order order vector-atomic-set! macro-raw-slot-store-void! vec idx val)))

(define (vector-atomic-swap! vec idx val #!optional (order 'sequentially-consistent))
  (macro-with-vector-index vec idx vector-atomic-swap!
    (macro-dispatch-rmw-order order vector-atomic-swap! macro-raw-slot-exchange! vec idx val)))

(define (vector-atomic-cas! vec idx expected desired #!optional (order 'sequentially-consistent))
  (macro-with-vector-index vec idx vector-atomic-cas!
    (macro-dispatch-rmw-order order vector-atomic-cas! macro-raw-slot-cas! vec idx expected desired)))

;;;============================================================================
;;; Disjoint SRFI-230 Atomic Types
;;;============================================================================

(##define-type atomic-flag
  id: 8B42D1A1-5C7E-4D1A-9F3B-230000000001
  type-exhibitor: macro-type-atomic-flag
  constructor: macro-make-atomic-flag
  implementer: implement-type-atomic-flag
  macros:
  prefix: macro-
  opaque:
  (cell read-only: unprintable:))
(implement-type-atomic-flag)

(##define-type atomic-box
  id: 8B42D1A1-5C7E-4D1A-9F3B-230000000002
  type-exhibitor: macro-type-atomic-box
  constructor: macro-make-atomic-box
  implementer: implement-type-atomic-box
  macros:
  prefix: macro-
  opaque:
  (cell read-only: unprintable:))
(implement-type-atomic-box)

(##define-type atomic-fxbox
  id: 8B42D1A1-5C7E-4D1A-9F3B-230000000003
  type-exhibitor: macro-type-atomic-fxbox
  constructor: macro-make-atomic-fxbox
  implementer: implement-type-atomic-fxbox
  macros:
  prefix: macro-
  opaque:
  (cell read-only: unprintable:))
(implement-type-atomic-fxbox)

(##define-type atomic-pair
  id: 8B42D1A1-5C7E-4D1A-9F3B-230000000004
  type-exhibitor: macro-type-atomic-pair
  constructor: macro-make-atomic-pair
  implementer: implement-type-atomic-pair
  macros:
  prefix: macro-
  opaque:
  (cell read-only: unprintable:))
(implement-type-atomic-pair)

;;;============================================================================
;;; Inline Type Checks (outlined cold exception helper)
;;;============================================================================

(define (raise-bad-type arg-id type-id proc x)
  (##raise-type-exception arg-id type-id proc (##list x)))

(##define-macro (macro-check-flag x proc)
  `(if (##not (macro-atomic-flag? ,x))
       (raise-bad-type 1 (macro-type-atomic-flag) ,proc ,x)))

(##define-macro (macro-check-box x proc)
  `(if (##not (macro-atomic-box? ,x))
       (raise-bad-type 1 (macro-type-atomic-box) ,proc ,x)))

(##define-macro (macro-check-fxbox x proc)
  `(if (##not (macro-atomic-fxbox? ,x))
       (raise-bad-type 1 (macro-type-atomic-fxbox) ,proc ,x)))

(##define-macro (macro-check-pair x proc)
  `(if (##not (macro-atomic-pair? ,x))
       (raise-bad-type 1 (macro-type-atomic-pair) ,proc ,x)))

(##define-macro (macro-check-fixnum x arg-id proc)
  `(if (##not (##fixnum? ,x))
       (raise-bad-type ,arg-id 'fixnum ,proc ,x)))

;;;============================================================================
;;; Atomic Flags
;;;============================================================================

(define (make-atomic-flag)
  (macro-make-atomic-flag (##make-vector 16 0)))

(define (atomic-flag? obj)
  (macro-atomic-flag? obj))

(define (atomic-flag-test-and-set! flag #!optional (order 'sequentially-consistent))
  (if (macro-atomic-flag? flag)
      (macro-dispatch-rmw-order order atomic-flag-test-and-set!
                                macro-raw-flag-tas! (macro-atomic-flag-cell flag) 0)
      (raise-bad-type 1 (macro-type-atomic-flag) atomic-flag-test-and-set! flag)))

(define (atomic-flag-clear! flag #!optional (order 'sequentially-consistent))
  (if (macro-atomic-flag? flag)
      (macro-dispatch-store-order order atomic-flag-clear!
                                  macro-raw-fx-store! (macro-atomic-flag-cell flag) 0 0)
      (raise-bad-type 1 (macro-type-atomic-flag) atomic-flag-clear! flag)))

;;;============================================================================
;;; Atomic Boxes (GC-Barriered: Generational Card + Yuasa SATB via Exchange/CAS)
;;;============================================================================

(define (make-atomic-box obj)
  (let ((cell (##make-vector 16 #f)))
    (##vector-set! cell 0 obj)
    (macro-make-atomic-box cell)))

(define (atomic-box? obj)
  (macro-atomic-box? obj))

(define (atomic-box-ref box #!optional (order 'sequentially-consistent))
  (if (macro-atomic-box? box)
      (macro-dispatch-load-order order atomic-box-ref
                                 macro-raw-slot-load (macro-atomic-box-cell box) 0)
      (raise-bad-type 1 (macro-type-atomic-box) atomic-box-ref box)))

(define (atomic-box-set! box obj #!optional (order 'sequentially-consistent))
  ;; Uses atomic_exchange (never load+shade+store) so concurrent writers can
  ;; never lose an overwritten mature pointer during Concurrent SATB Major GC.
  (if (macro-atomic-box? box)
      (macro-dispatch-store-order order atomic-box-set!
                                  macro-raw-slot-store-void! (macro-atomic-box-cell box) 0 obj)
      (raise-bad-type 1 (macro-type-atomic-box) atomic-box-set! box)))

(define (atomic-box-swap! box obj #!optional (order 'sequentially-consistent))
  (if (macro-atomic-box? box)
      (macro-dispatch-rmw-order order atomic-box-swap!
                                macro-raw-slot-exchange! (macro-atomic-box-cell box) 0 obj)
      (raise-bad-type 1 (macro-type-atomic-box) atomic-box-swap! box)))

(define (atomic-box-compare-and-swap! box expected desired
                                      #!optional (order 'sequentially-consistent))
  (if (macro-atomic-box? box)
      (macro-dispatch-rmw-order order atomic-box-compare-and-swap!
                                macro-raw-slot-cas! (macro-atomic-box-cell box) 0 expected desired)
      (raise-bad-type 1 (macro-type-atomic-box) atomic-box-compare-and-swap! box)))

;;;============================================================================
;;; Atomic Fixnum Boxes (Zero-Barrier Hardware Atomic RMW, 00-Tag Preserving)
;;;============================================================================

(define (make-atomic-fxbox fx)
  (macro-check-fixnum fx 1 make-atomic-fxbox)
  (let ((cell (##make-vector 16 0)))
    (##vector-set! cell 0 fx)
    (macro-make-atomic-fxbox cell)))

(define (atomic-fxbox? obj)
  (macro-atomic-fxbox? obj))

(define (atomic-fxbox-ref fxbox #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (macro-dispatch-load-order order atomic-fxbox-ref
                                 macro-raw-fx-load (macro-atomic-fxbox-cell fxbox) 0)
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-ref fxbox)))

(define (atomic-fxbox-set! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-store-order order atomic-fxbox-set!
                                      macro-raw-fx-store! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-set! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-set! fxbox)))

(define (atomic-fxbox-swap! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-swap!
                                    macro-raw-fx-exchange! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-swap! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-swap! fxbox)))

(define (atomic-fxbox-compare-and-swap! fxbox expected desired
                                        #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? expected)
          (if (##fixnum? desired)
              (macro-dispatch-rmw-order order atomic-fxbox-compare-and-swap!
                                        macro-raw-fx-cas! (macro-atomic-fxbox-cell fxbox) 0 expected desired)
              (raise-bad-type 3 'fixnum atomic-fxbox-compare-and-swap! desired))
          (raise-bad-type 2 'fixnum atomic-fxbox-compare-and-swap! expected))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-compare-and-swap! fxbox)))

(define (atomic-fxbox-fetch-add! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-fetch-add!
                                    macro-raw-fx-fetch-add! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-fetch-add! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-fetch-add! fxbox)))

(define (atomic-fxbox-fetch-sub! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-fetch-sub!
                                    macro-raw-fx-fetch-sub! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-fetch-sub! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-fetch-sub! fxbox)))

(define (atomic-fxbox-fetch-and! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-fetch-and!
                                    macro-raw-fx-fetch-and! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-fetch-and! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-fetch-and! fxbox)))

(define (atomic-fxbox-fetch-ior! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-fetch-ior!
                                    macro-raw-fx-fetch-ior! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-fetch-ior! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-fetch-ior! fxbox)))

(define (atomic-fxbox-fetch-xor! fxbox fx #!optional (order 'sequentially-consistent))
  (if (macro-atomic-fxbox? fxbox)
      (if (##fixnum? fx)
          (macro-dispatch-rmw-order order atomic-fxbox-fetch-xor!
                                    macro-raw-fx-fetch-xor! (macro-atomic-fxbox-cell fxbox) 0 fx)
          (raise-bad-type 2 'fixnum atomic-fxbox-fetch-xor! fx))
      (raise-bad-type 1 (macro-type-atomic-fxbox) atomic-fxbox-fetch-xor! fxbox)))

;;;============================================================================
;;; Atomic Pairs (Lock-Free Immutable Cons-Cell Replacement: Zero Tear!)
;;;============================================================================

(define (make-atomic-pair car-val cdr-val)
  (let ((cell (##make-vector 16 #f)))
    (##vector-set! cell 0 (##cons car-val cdr-val))
    (macro-make-atomic-pair cell)))

(define (atomic-pair? obj)
  (macro-atomic-pair? obj))

(define (atomic-pair-ref apair #!optional (order 'sequentially-consistent))
  (macro-check-pair apair atomic-pair-ref)
  (let ((p (macro-raw-slot-load (macro-atomic-pair-cell apair)
                                0
                                (macro-load-order->code order atomic-pair-ref))))
    (##values (##car p) (##cdr p))))

(define (atomic-pair-set! apair car-val cdr-val
                          #!optional (order 'sequentially-consistent))
  (macro-check-pair apair atomic-pair-set!)
  (macro-raw-slot-exchange! (macro-atomic-pair-cell apair)
                            0
                            (##cons car-val cdr-val)
                            (macro-store-order->code order atomic-pair-set!))
  (##void))

(define (atomic-pair-swap! apair car-val cdr-val
                           #!optional (order 'sequentially-consistent))
  (macro-check-pair apair atomic-pair-swap!)
  (let ((old (macro-raw-slot-exchange! (macro-atomic-pair-cell apair)
                                       0
                                       (##cons car-val cdr-val)
                                       (macro-order->code order atomic-pair-swap!))))
    (##values (##car old) (##cdr old))))

(define (atomic-pair-compare-and-swap! apair exp-car exp-cdr des-car des-cdr
                                       #!optional (order 'sequentially-consistent))
  (macro-check-pair apair atomic-pair-compare-and-swap!)
  (let* ((cell (macro-atomic-pair-cell apair))
         (code (macro-order->code order atomic-pair-compare-and-swap!))
         ;; Map RMW release/acq_rel orders to valid load orders (relaxed/acquire)
         ;; for the speculative read before CAS.
         (load-code (if (##fx= code 2) 0 (if (##fx= code 3) 1 code))))
    (let loop ((cur (macro-raw-slot-load cell 0 load-code))
               (desired #f))
      (let ((c-car (##car cur))
            (c-cdr (##cdr cur)))
        (if (and (##eq? c-car exp-car) (##eq? c-cdr exp-cdr))
            (let* ((des (or desired (##cons des-car des-cdr)))
                   (prev (macro-raw-slot-cas! cell 0 cur des code)))
              (if (##eq? prev cur)
                  (##values c-car c-cdr)
                  (loop prev des)))
            (##values c-car c-cdr))))))

(define atomic-fxbox+/fetch! atomic-fxbox-fetch-add!)
(define atomic-fxbox-/fetch! atomic-fxbox-fetch-sub!)
(define atomic-fxbox-and/fetch! atomic-fxbox-fetch-and!)
(define atomic-fxbox-ior/fetch! atomic-fxbox-fetch-ior!)
(define atomic-fxbox-xor/fetch! atomic-fxbox-fetch-xor!)

;;;============================================================================
;;; Memory Synchronization Fence
;;;============================================================================

(define (atomic-fence #!optional (order 'sequentially-consistent))
  (macro-dispatch-rmw-order order atomic-fence macro-raw-fence!))

;;;============================================================================
