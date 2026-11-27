;;;============================================================================

;;; File: "230.sld"

;;; SRFI 230, Atomic Operations (backed by Gambit SMP C23 + GC barriers)

(define-library (srfi 230)

  (export
    memory-order
    memory-order?
    make-atomic-flag
    atomic-flag?
    atomic-flag-test-and-set!
    atomic-flag-clear!
    make-atomic-box
    atomic-box?
    atomic-box-ref
    atomic-box-set!
    atomic-box-swap!
    atomic-box-compare-and-swap!
    make-atomic-fxbox
    atomic-fxbox?
    atomic-fxbox-ref
    atomic-fxbox-set!
    atomic-fxbox-swap!
    atomic-fxbox-compare-and-swap!
    atomic-fxbox+/fetch!
    atomic-fxbox-/fetch!
    atomic-fxbox-and/fetch!
    atomic-fxbox-ior/fetch!
    atomic-fxbox-xor/fetch!
    make-atomic-pair
    atomic-pair?
    atomic-pair-ref
    atomic-pair-set!
    atomic-pair-swap!
    atomic-pair-compare-and-swap!
    atomic-fence)

  (include "230#.scm")
  (include "230.scm"))

;;;============================================================================
