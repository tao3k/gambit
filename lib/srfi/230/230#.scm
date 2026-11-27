;;;============================================================================

;;; File: "230#.scm"

;;; SRFI 230, Atomic Operations

(##namespace ("srfi/230#"

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
atomic-fence

))

(##define-syntax memory-order
  (lambda (src)
    (let ((forms (##source-code src)))
      (if (and (##pair? forms)
               (##pair? (##cdr forms))
               (##null? (##cddr forms)))
          (let ((sym (##source-code (##cadr forms))))
            (if (##memq sym '(relaxed acquire release acquire-release sequentially-consistent))
                (##list 'quote sym)
                (##raise-expression-parsing-exception
                 'ill-formed-special-form
                 src)))
          (##raise-expression-parsing-exception
           'ill-formed-special-form
           src)))))

;;;============================================================================
