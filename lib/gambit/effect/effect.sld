;;;============================================================================

;;; File: "effect.sld"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit effect) — Direct-Style Algebraic Effect Handlers

(define-library (gambit effect)

  (import (gambit)
          (srfi 226)
          (srfi 230))

  (export
    make-effect
    effect?
    effect-name
    define-effect

    with-handler
    call-with-effect-handler
    perform
    resume
    resume-multishot
    effect-continuation?

    yield
    make-generator)

  (begin
    (##define-syntax define-effect
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms)
                   (##pair? (##cdr forms))
                   (##null? (##cddr forms)))
              (let ((name (##cadr forms)))
                (##list 'define
                        name
                        (##list 'gambit/effect#make-effect
                                (##list 'quote (##desourcify name)))))
              (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

    (##define-syntax with-handler
      (lambda (src)
        (let ((forms (##source-code src)))
          (if (and (##pair? forms)
                   (##pair? (##cdr forms))
                   (##pair? (##cddr forms)))
              (let ((clauses (##source-code (##cadr forms)))
                    (body (##cddr forms)))
                (let loop ((cs clauses) (entries '()) (ret-fn #f))
                  (if (##null? cs)
                      (##list 'gambit/effect#%call-with-handler-entries
                              (##cons 'list (##reverse entries))
                              ret-fn
                              (##cons 'lambda (##cons '() body)))
                      (let ((c (##source-code (##car cs))))
                        (cond
                          ((and (##pair? c)
                                (##eq? (##desourcify (##car c)) 'return:)
                                (##pair? (##cdr c))
                                (##pair? (##cddr c)))
                           (let ((params (##cadr c))
                                 (rbody (##cddr c)))
                             (loop (##cdr cs)
                                   entries
                                   (##cons 'lambda (##cons params rbody)))))
                          ((and (##pair? c)
                                (##eq? (##desourcify (##car c)) 'tail:)
                                (##pair? (##cdr c))
                                (##pair? (##cddr c))
                                (##pair? (##cdddr c)))
                           (let ((eff (##cadr c))
                                 (params (##caddr c))
                                 (ebody (##cdddr c)))
                             (loop (##cdr cs)
                                   (##cons (##list 'gambit/effect#%make-handler-entry
                                                   eff
                                                   ''tail
                                                   (##cons 'lambda (##cons params ebody)))
                                           entries)
                                   ret-fn)))
                          ((and (##pair? c)
                                (##pair? (##cdr c))
                                (##pair? (##cddr c)))
                           (let ((eff (##car c))
                                 (params (##cadr c))
                                 (ebody (##cddr c)))
                             (loop (##cdr cs)
                                   (##cons (##list 'gambit/effect#%make-handler-entry
                                                   eff
                                                   ''suspend
                                                   (##cons 'lambda (##cons params ebody)))
                                           entries)
                                   ret-fn)))
                          (else
                           (##raise-expression-parsing-exception 'ill-formed-special-form src)))))))
              (##raise-expression-parsing-exception 'ill-formed-special-form src))))))

  (include "effect.scm"))

;;;============================================================================
