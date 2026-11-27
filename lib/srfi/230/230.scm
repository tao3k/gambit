;;;============================================================================

;;; File: "230.scm"

;;; SRFI 230, Atomic Operations
;;; Backed directly by Gambit SMP C23 <stdatomic.h> + SATB/Generational GC
;;; write barriers (include/_gambit/runtime_protocols.h.in).

(##supply-module srfi/230)

(##namespace ("srfi/230#"))               ;; in srfi/230#
(##include "~~lib/gambit/prim/prim#.scm") ;; map fx+ to ##fx+, etc
(##include "~~lib/_gambit#.scm")          ;; for macro-absent-obj, etc

(##include "230#.scm")

(declare (extended-bindings))
(declare (block))

;;;============================================================================
;;; Low-level C23 SRFI-230 primitives (GC-barrier integrated)

(define %srfi230-box-load
  (c-lambda (scheme-object int) scheme-object
    "___return(___SRFI230_BOX_LOAD(___arg1, ___arg2));"))

(define %srfi230-box-store!
  (c-lambda (scheme-object scheme-object int) void
    "___SRFI230_BOX_STORE(___ps, ___arg1, ___arg2, ___arg3);"))

(define %srfi230-box-swap!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_BOX_SWAP(___ps, ___arg1, ___arg2, ___arg3));"))

(define %srfi230-box-cas!
  (c-lambda (scheme-object scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_BOX_CAS(___ps, ___arg1, ___arg2, ___arg3, ___arg4));"))

(define %srfi230-fxbox-add!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_FXBOX_ADD(___arg1, ___arg2, ___arg3));"))

(define %srfi230-fxbox-sub!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_FXBOX_SUB(___arg1, ___arg2, ___arg3));"))

(define %srfi230-fxbox-and!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_FXBOX_AND(___arg1, ___arg2, ___arg3));"))

(define %srfi230-fxbox-ior!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_FXBOX_IOR(___arg1, ___arg2, ___arg3));"))

(define %srfi230-fxbox-xor!
  (c-lambda (scheme-object scheme-object int) scheme-object
    "___return(___SRFI230_FXBOX_XOR(___arg1, ___arg2, ___arg3));"))

(define %srfi230-fence!
  (c-lambda (int) void
    "___SRFI230_FENCE(___arg1);"))

;;;============================================================================
;;; Memory orders

(define (memory-order? obj)
  (or (eq? obj 'relaxed)
      (eq? obj 'acquire)
      (eq? obj 'release)
      (eq? obj 'acquire-release)
      (eq? obj 'sequentially-consistent)))

(define (%order->int order)
  (cond
    ((eq? order 'sequentially-consistent) 4)
    ((eq? order 'acquire-release)         3)
    ((eq? order 'release)                 2)
    ((eq? order 'acquire)                 1)
    ((eq? order 'relaxed)                 0)
    (else (error "SRFI-230: invalid memory-order" order))))

(define (%opt-order args)
  (cond
    ((null? args) 4)
    ((null? (cdr args)) (%order->int (car args)))
    (else (error "SRFI-230: too many arguments" args))))

;;;============================================================================
;;; Disjoint opaque record types

(##define-type atomic-flag
  id: 6D9F3C4E-8E21-4B8F-9A41-230F1A600001
  constructor: %make-atomic-flag
  predicate: atomic-flag?
  opaque:
  (cell unprintable: read-only:))

(##define-type atomic-box
  id: 6D9F3C4E-8E21-4B8F-9A41-230B0A600002
  constructor: %make-atomic-box
  predicate: atomic-box?
  opaque:
  (cell unprintable: read-only:))

(##define-type atomic-fxbox
  id: 6D9F3C4E-8E21-4B8F-9A41-230F7A600003
  constructor: %make-atomic-fxbox
  predicate: atomic-fxbox?
  opaque:
  (cell unprintable: read-only:))

(##define-type atomic-pair
  id: 6D9F3C4E-8E21-4B8F-9A41-230A1A600004
  constructor: %make-atomic-pair
  predicate: atomic-pair?
  opaque:
  (cell unprintable: read-only:))

(define (%check-flag obj)
  (if (atomic-flag? obj)
      (atomic-flag-cell obj)
      (error "SRFI-230: expected atomic-flag" obj)))

(define (%check-box obj)
  (if (atomic-box? obj)
      (atomic-box-cell obj)
      (error "SRFI-230: expected atomic-box" obj)))

(define (%check-fxbox obj)
  (if (atomic-fxbox? obj)
      (atomic-fxbox-cell obj)
      (error "SRFI-230: expected atomic-fxbox" obj)))

(define (%check-pair obj)
  (if (atomic-pair? obj)
      (atomic-pair-cell obj)
      (error "SRFI-230: expected atomic-pair" obj)))

(define (%check-fixnum obj)
  (if (fixnum? obj)
      obj
      (error "SRFI-230: expected fixnum" obj)))

;;;============================================================================
;;; Atomic flags

(define (make-atomic-flag)
  (%make-atomic-flag (box #f)))

(define (atomic-flag-test-and-set! flag . rest)
  (let ((cell (%check-flag flag))
        (mo (%opt-order rest)))
    (%srfi230-box-swap! cell #t mo)))

(define (atomic-flag-clear! flag . rest)
  (let ((cell (%check-flag flag))
        (mo (%opt-order rest)))
    (%srfi230-box-store! cell #f mo)))

;;;============================================================================
;;; Atomic boxes

(define (make-atomic-box obj)
  (%make-atomic-box (box obj)))

(define (atomic-box-ref abox . rest)
  (let ((cell (%check-box abox))
        (mo (%opt-order rest)))
    (%srfi230-box-load cell mo)))

(define (atomic-box-set! abox obj . rest)
  (let ((cell (%check-box abox))
        (mo (%opt-order rest)))
    (%srfi230-box-store! cell obj mo)))

(define (atomic-box-swap! abox obj . rest)
  (let ((cell (%check-box abox))
        (mo (%opt-order rest)))
    (%srfi230-box-swap! cell obj mo)))

(define (atomic-box-compare-and-swap! abox expected desired . rest)
  (let ((cell (%check-box abox))
        (mo (%opt-order rest)))
    (%srfi230-box-cas! cell expected desired mo)))

;;;============================================================================
;;; Atomic fixnum boxes

(define (make-atomic-fxbox fx)
  (%make-atomic-fxbox (box (%check-fixnum fx))))

(define (atomic-fxbox-ref fxbox . rest)
  (let ((cell (%check-fxbox fxbox))
        (mo (%opt-order rest)))
    (%srfi230-box-load cell mo)))

(define (atomic-fxbox-set! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-box-store! cell v mo)))

(define (atomic-fxbox-swap! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-box-swap! cell v mo)))

(define (atomic-fxbox-compare-and-swap! fxbox expected desired . rest)
  (let ((cell (%check-fxbox fxbox))
        (e (%check-fixnum expected))
        (d (%check-fixnum desired))
        (mo (%opt-order rest)))
    (%srfi230-box-cas! cell e d mo)))

(define (atomic-fxbox+/fetch! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-fxbox-add! cell v mo)))

(define (atomic-fxbox-/fetch! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-fxbox-sub! cell v mo)))

(define (atomic-fxbox-and/fetch! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-fxbox-and! cell v mo)))

(define (atomic-fxbox-ior/fetch! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-fxbox-ior! cell v mo)))

(define (atomic-fxbox-xor/fetch! fxbox fx . rest)
  (let ((cell (%check-fxbox fxbox))
        (v (%check-fixnum fx))
        (mo (%opt-order rest)))
    (%srfi230-fxbox-xor! cell v mo)))

;;;============================================================================
;;; Atomic pairs (lock-free, tear-free via immutable pair + atomic box)

(define (make-atomic-pair a b)
  (%make-atomic-pair (box (cons a b))))

(define (atomic-pair-ref apair . rest)
  (let* ((cell (%check-pair apair))
         (mo (%opt-order rest))
         (p (%srfi230-box-load cell mo)))
    (values (car p) (cdr p))))

(define (atomic-pair-set! apair a b . rest)
  (let ((cell (%check-pair apair))
        (mo (%opt-order rest)))
    (%srfi230-box-store! cell (cons a b) mo)))

(define (atomic-pair-swap! apair a b . rest)
  (let* ((cell (%check-pair apair))
         (mo (%opt-order rest))
         (old (%srfi230-box-swap! cell (cons a b) mo)))
    (values (car old) (cdr old))))

(define (atomic-pair-compare-and-swap! apair expected-a expected-b desired-a desired-b . rest)
  (let ((cell (%check-pair apair))
        (mo (%opt-order rest))
        (desired (cons desired-a desired-b)))
    (let loop ()
      (let ((cur (%srfi230-box-load cell mo)))
        (if (and (eq? (car cur) expected-a)
                 (eq? (cdr cur) expected-b))
            (let ((prev (%srfi230-box-cas! cell cur desired mo)))
              (if (eq? prev cur)
                  (values (car cur) (cdr cur))
                  (loop)))
            (values (car cur) (cdr cur)))))))

;;;============================================================================
;;; Memory fence

(define (atomic-fence order)
  (%srfi230-fence! (%order->int order)))

;;;============================================================================
