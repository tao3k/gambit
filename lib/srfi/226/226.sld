;;;============================================================================

;;; File: "226.sld"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 226, Control Features

(define-library (srfi 226)

  (import (gambit)
          (srfi 230))

  (export
    ;; Continuation prompt tags & prompts
    make-continuation-prompt-tag
    continuation-prompt-tag?
    default-continuation-prompt-tag
    call-with-continuation-prompt
    abort-current-continuation
    continuation-prompt-available?

    ;; Continuation barriers
    call-with-continuation-barrier

    ;; Delimited & atomic one-shot continuations
    call-with-composable-continuation
    call-with-non-composable-continuation
    call/1cc
    call-with-one-shot-composable-continuation
    one-shot-continuation?
    one-shot-continuation-consumed?
    promote-one-shot-continuation!

    ;; Continuation marks
    with-continuation-mark
    current-continuation-marks
    continuation-marks
    continuation-mark-set?
    continuation-mark-set->list
    continuation-mark-set->list*
    continuation-mark-set-first
    call-with-immediate-continuation-mark

    ;; Shift / Reset
    reset
    shift)

  (begin
    (##define-syntax with-continuation-mark
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms)
                   (##pair? (##cdr forms))
                   (##pair? (##cddr forms))
                   (##pair? (##cdddr forms))
                   (##null? (##cddddr forms)))
              (let ((key (##cadr forms))
                    (val (##caddr forms))
                    (expr (##cadddr forms)))
                (##list 'srfi/226#%call-with-continuation-mark
                        key
                        val
                        (##list 'lambda '() expr)))
              (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

    (##define-syntax reset
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms) (##pair? (##cdr forms)))
              (##list 'srfi/226#call-with-continuation-prompt
                      (##cons 'lambda (##cons '() (##cdr forms))))
              (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

    (##define-syntax shift
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms)
                   (##pair? (##cdr forms))
                   (##pair? (##cddr forms)))
              (let ((k (##cadr forms))
                    (body (##cddr forms)))
                (##list 'srfi/226#call-with-composable-continuation
                        (##list 'lambda
                                '(%srfi226-raw-k)
                                (##list 'srfi/226#abort-current-continuation
                                        (##list 'srfi/226#default-continuation-prompt-tag)
                                        (##list 'lambda
                                                '()
                                                (##cons 'let
                                                        (##cons (##list
                                                                 (##list k
                                                                         '(lambda %srfi226-args
                                                                            (srfi/226#call-with-continuation-prompt
                                                                             (lambda ()
                                                                               (apply %srfi226-raw-k %srfi226-args))))))
                                                                body)))))))
              (##raise-expression-parsing-exception 'ill-formed-special-form src))))))

  (include "226.scm"))

;;;============================================================================
