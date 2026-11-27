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

(define (order->code order proc)
  (cond ((##eq? order 'sequentially-consistent) 4)
        ((##eq? order 'acquire) 1)
        ((##eq? order 'release) 2)
        ((##eq? order 'acquire-release) 3)
        ((##eq? order 'relaxed) 0)
        (else (##raise-type-exception 1 'memory-order proc (##list order)))))

;;;============================================================================
;;; Low-Level GC-Barriered Vector-Slot Atomic Operations
;;;============================================================================

(define fence-scratch (##vector 0))

(define (raw-fence! code)
  (macro-if-c-compiled
   (##c-code "___atomic_fence_order((int)___INT(___ARG1)); ___RESULT = ___VOID;"
             code)
   (begin
     (##vector-cas! fence-scratch 0 0 0)
     (##void))))

(define (raw-slot-load vec idx code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_load(___s, (int)___INT(___ARG3));"
    vec idx code)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (raw-slot-exchange! vec idx newval code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_exchange(
       ___ps, ___ARG1, ___s, ___ARG3, (int)___INT(___ARG4),
       ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));"
    vec idx newval code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let ((prev (##vector-cas! vec idx newval old)))
       (if (##eq? prev old)
           old
           (loop prev))))))

(define (raw-slot-cas! vec idx expected desired code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___gc_atomic_slot_cas(
       ___ps, ___ARG1, ___s, ___ARG3, ___ARG4, (int)___INT(___ARG5),
       ___EXT(___gc_write_barrier_slow), ___EXT(___gc_satb_barrier_val));"
    vec idx expected desired code)
   (##vector-cas! vec idx desired expected)))

(define (raw-fx-load vec idx code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_load(___CAST(___VOLATILE ___WORD*, ___s), (int)___INT(___ARG3)));"
    vec idx code)
   (##vector-cas! vec idx #!unbound #!unbound)))

(define (raw-fx-store! vec idx val code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___atomic_word_store(___CAST(___VOLATILE ___WORD*, ___s),
                          ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4));
     ___RESULT = ___VOID;"
    vec idx val code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let ((prev (##vector-cas! vec idx val old)))
       (if (##eq? prev old) (##void) (loop prev))))))

(define (raw-fx-exchange! vec idx val code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_exchange(___CAST(___VOLATILE ___WORD*, ___s),
                               ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx val code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let ((prev (##vector-cas! vec idx val old)))
       (if (##eq? prev old) old (loop prev))))))

(define (raw-fx-cas! vec idx expected desired code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, ___s),
                          ___CAST(___WORD, ___ARG3),
                          ___CAST(___WORD, ___ARG4), (int)___INT(___ARG5)));"
    vec idx expected desired code)
   (##vector-cas! vec idx desired expected)))

(define (raw-fx-fetch-add! vec idx delta code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_add(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx delta code)
   (##vector-inc! vec idx delta)))

(define (raw-fx-fetch-sub! vec idx delta code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_sub(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx delta code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let* ((next (##fxwrap- old delta))
            (prev (##vector-cas! vec idx next old)))
       (if (##eq? prev old) old (loop prev))))))

(define (raw-fx-fetch-and! vec idx mask code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_and(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx mask code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let* ((next (##fxand old mask))
            (prev (##vector-cas! vec idx next old)))
       (if (##eq? prev old) old (loop prev))))))

(define (raw-fx-fetch-ior! vec idx mask code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_ior(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx mask code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let* ((next (##fxior old mask))
            (prev (##vector-cas! vec idx next old)))
       (if (##eq? prev old) old (loop prev))))))

(define (raw-fx-fetch-xor! vec idx mask code)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___s = ___FXINDX_WORD(___BODY_AS(___ARG1, ___tVECTOR), ___ARG2);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_uword_fetch_xor(___CAST(___VOLATILE ___WORD*, ___s),
                                 ___CAST(___WORD, ___ARG3), (int)___INT(___ARG4)));"
    vec idx mask code)
   (let loop ((old (##vector-cas! vec idx #!unbound #!unbound)))
     (let* ((next (##fxxor old mask))
            (prev (##vector-cas! vec idx next old)))
       (if (##eq? prev old) old (loop prev))))))

;;; Exported internal helpers for (gambit parallel) Chase-Lev ring buffer
;;; (prevents C23/TSan speculative stealer data races on wrapped ring slots).
(define (vector-atomic-ref vec idx #!optional (order 'sequentially-consistent))
  (raw-slot-load vec idx (order->code order vector-atomic-ref)))

(define (vector-atomic-set! vec idx val #!optional (order 'sequentially-consistent))
  (raw-slot-exchange! vec idx val (order->code order vector-atomic-set!))
  (##void))

(define (vector-atomic-swap! vec idx val #!optional (order 'sequentially-consistent))
  (raw-slot-exchange! vec idx val (order->code order vector-atomic-swap!)))

(define (vector-atomic-cas! vec idx expected desired #!optional (order 'sequentially-consistent))
  (raw-slot-cas! vec idx expected desired (order->code order vector-atomic-cas!)))

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
;;; Type Checks
;;;============================================================================

(define (check-flag x proc)
  (if (##not (macro-atomic-flag? x))
      (##raise-type-exception 1 (macro-type-atomic-flag) proc (##list x))))

(define (check-box x proc)
  (if (##not (macro-atomic-box? x))
      (##raise-type-exception 1 (macro-type-atomic-box) proc (##list x))))

(define (check-fxbox x proc)
  (if (##not (macro-atomic-fxbox? x))
      (##raise-type-exception 1 (macro-type-atomic-fxbox) proc (##list x))))

(define (check-pair x proc)
  (if (##not (macro-atomic-pair? x))
      (##raise-type-exception 1 (macro-type-atomic-pair) proc (##list x))))

(define (check-fixnum x arg-id proc)
  (if (##not (##fixnum? x))
      (##raise-type-exception arg-id 'fixnum proc (##list x))))

;;;============================================================================
;;; Atomic Flags
;;;============================================================================

(define (make-atomic-flag)
  (macro-make-atomic-flag (##vector 0)))

(define (atomic-flag? obj)
  (macro-atomic-flag? obj))

(define (atomic-flag-test-and-set! flag #!optional (order 'sequentially-consistent))
  (check-flag flag atomic-flag-test-and-set!)
  (let ((code (order->code order atomic-flag-test-and-set!)))
    (##not (##fx= (raw-fx-exchange! (macro-atomic-flag-cell flag) 0 1 code) 0))))

(define (atomic-flag-clear! flag #!optional (order 'sequentially-consistent))
  (check-flag flag atomic-flag-clear!)
  (let ((code (order->code order atomic-flag-clear!)))
    (raw-fx-store! (macro-atomic-flag-cell flag) 0 0 code)
    (##void)))

;;;============================================================================
;;; Atomic Boxes (GC-Barriered: Generational Card + Yuasa SATB via Exchange/CAS)
;;;============================================================================

(define (make-atomic-box obj)
  (macro-make-atomic-box (##vector obj)))

(define (atomic-box? obj)
  (macro-atomic-box? obj))

(define (atomic-box-ref box #!optional (order 'sequentially-consistent))
  (check-box box atomic-box-ref)
  (raw-slot-load (macro-atomic-box-cell box)
                 0
                 (order->code order atomic-box-ref)))

(define (atomic-box-set! box obj #!optional (order 'sequentially-consistent))
  (check-box box atomic-box-set!)
  ;; Uses atomic_exchange (never load+shade+store) so concurrent writers can
  ;; never lose an overwritten mature pointer during Concurrent SATB Major GC.
  (raw-slot-exchange! (macro-atomic-box-cell box)
                      0
                      obj
                      (order->code order atomic-box-set!))
  (##void))

(define (atomic-box-swap! box obj #!optional (order 'sequentially-consistent))
  (check-box box atomic-box-swap!)
  (raw-slot-exchange! (macro-atomic-box-cell box)
                      0
                      obj
                      (order->code order atomic-box-swap!)))

(define (atomic-box-compare-and-swap! box expected desired
                                      #!optional (order 'sequentially-consistent))
  (check-box box atomic-box-compare-and-swap!)
  (raw-slot-cas! (macro-atomic-box-cell box)
                 0
                 expected
                 desired
                 (order->code order atomic-box-compare-and-swap!)))

;;;============================================================================
;;; Atomic Fixnum Boxes (Zero-Barrier Hardware Atomic RMW, 00-Tag Preserving)
;;;============================================================================

(define (make-atomic-fxbox fx)
  (check-fixnum fx 1 make-atomic-fxbox)
  (macro-make-atomic-fxbox (##vector fx)))

(define (atomic-fxbox? obj)
  (macro-atomic-fxbox? obj))

(define (atomic-fxbox-ref fxbox #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-ref)
  (raw-fx-load (macro-atomic-fxbox-cell fxbox)
               0
               (order->code order atomic-fxbox-ref)))

(define (atomic-fxbox-set! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-set!)
  (check-fixnum fx 2 atomic-fxbox-set!)
  (raw-fx-store! (macro-atomic-fxbox-cell fxbox)
                 0
                 fx
                 (order->code order atomic-fxbox-set!))
  (##void))

(define (atomic-fxbox-swap! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-swap!)
  (check-fixnum fx 2 atomic-fxbox-swap!)
  (raw-fx-exchange! (macro-atomic-fxbox-cell fxbox)
                    0
                    fx
                    (order->code order atomic-fxbox-swap!)))

(define (atomic-fxbox-compare-and-swap! fxbox expected desired
                                        #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-compare-and-swap!)
  (check-fixnum expected 2 atomic-fxbox-compare-and-swap!)
  (check-fixnum desired 3 atomic-fxbox-compare-and-swap!)
  (raw-fx-cas! (macro-atomic-fxbox-cell fxbox)
               0
               expected
               desired
               (order->code order atomic-fxbox-compare-and-swap!)))

(define (atomic-fxbox-fetch-add! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-fetch-add!)
  (check-fixnum fx 2 atomic-fxbox-fetch-add!)
  (raw-fx-fetch-add! (macro-atomic-fxbox-cell fxbox)
                     0
                     fx
                     (order->code order atomic-fxbox-fetch-add!)))

(define (atomic-fxbox-fetch-sub! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-fetch-sub!)
  (check-fixnum fx 2 atomic-fxbox-fetch-sub!)
  (raw-fx-fetch-sub! (macro-atomic-fxbox-cell fxbox)
                     0
                     fx
                     (order->code order atomic-fxbox-fetch-sub!)))

(define (atomic-fxbox-fetch-and! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-fetch-and!)
  (check-fixnum fx 2 atomic-fxbox-fetch-and!)
  (raw-fx-fetch-and! (macro-atomic-fxbox-cell fxbox)
                     0
                     fx
                     (order->code order atomic-fxbox-fetch-and!)))

(define (atomic-fxbox-fetch-ior! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-fetch-ior!)
  (check-fixnum fx 2 atomic-fxbox-fetch-ior!)
  (raw-fx-fetch-ior! (macro-atomic-fxbox-cell fxbox)
                     0
                     fx
                     (order->code order atomic-fxbox-fetch-ior!)))

(define (atomic-fxbox-fetch-xor! fxbox fx #!optional (order 'sequentially-consistent))
  (check-fxbox fxbox atomic-fxbox-fetch-xor!)
  (check-fixnum fx 2 atomic-fxbox-fetch-xor!)
  (raw-fx-fetch-xor! (macro-atomic-fxbox-cell fxbox)
                     0
                     fx
                     (order->code order atomic-fxbox-fetch-xor!)))

;;;============================================================================
;;; Atomic Pairs (Lock-Free Immutable Cons-Cell Replacement: Zero Tear!)
;;;============================================================================

(define (make-atomic-pair car-val cdr-val)
  (macro-make-atomic-pair (##vector (##cons car-val cdr-val))))

(define (atomic-pair? obj)
  (macro-atomic-pair? obj))

(define (atomic-pair-ref apair #!optional (order 'sequentially-consistent))
  (check-pair apair atomic-pair-ref)
  (let ((p (raw-slot-load (macro-atomic-pair-cell apair)
                          0
                          (order->code order atomic-pair-ref))))
    (##values (##car p) (##cdr p))))

(define (atomic-pair-set! apair car-val cdr-val
                          #!optional (order 'sequentially-consistent))
  (check-pair apair atomic-pair-set!)
  (raw-slot-exchange! (macro-atomic-pair-cell apair)
                      0
                      (##cons car-val cdr-val)
                      (order->code order atomic-pair-set!))
  (##void))

(define (atomic-pair-swap! apair car-val cdr-val
                           #!optional (order 'sequentially-consistent))
  (check-pair apair atomic-pair-swap!)
  (let ((old (raw-slot-exchange! (macro-atomic-pair-cell apair)
                                 0
                                 (##cons car-val cdr-val)
                                 (order->code order atomic-pair-swap!))))
    (##values (##car old) (##cdr old))))

(define (atomic-pair-compare-and-swap! apair exp-car exp-cdr des-car des-cdr
                                       #!optional (order 'sequentially-consistent))
  (check-pair apair atomic-pair-compare-and-swap!)
  (let ((cell (macro-atomic-pair-cell apair))
        (code (order->code order atomic-pair-compare-and-swap!))
        (desired (##cons des-car des-cdr)))
    (let loop ((cur (raw-slot-load cell 0 code)))
      (let ((c-car (##car cur))
            (c-cdr (##cdr cur)))
        (if (and (##eq? c-car exp-car) (##eq? c-cdr exp-cdr))
            (let ((prev (raw-slot-cas! cell 0 cur desired code)))
              (if (##eq? prev cur)
                  (##values c-car c-cdr)
                  (loop prev)))
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
  (raw-fence! (order->code order atomic-fence)))

;;;============================================================================
