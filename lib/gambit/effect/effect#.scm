;;;============================================================================

;;; File: "effect#.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit effect) — Direct-Style Algebraic Effect Handlers
;;;
;;; Features:
;;;   - Koka ICFP '21 tail-resumptive zero-capture direct handler fast path
;;;   - Lexa OOPSLA '24 / evidence-passing O(1) dynamic handler dispatch
;;;   - Atomic one-shot delimited resume + lazy MULTISHOT_COW promotion
;;;   - Direct-style generators (make-generator / yield)

(##namespace ("gambit/effect#"

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

;; Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles
effect-capability?
call-with-tail-capability
call-with-suspend-capability
with-capability-handler
perform-cap

;; Built-in direct-style generator combinator
yield
make-generator

;; Internal helpers used by syntax expansions
%make-handler-entry
%call-with-handler-entries

))

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
                      ;; (return: (v) body ...)
                      ((and (##pair? c)
                            (##eq? (##desourcify (##car c)) 'return:)
                            (##pair? (##cdr c))
                            (##pair? (##cddr c)))
                       (if ret-fn
                           (##raise-expression-parsing-exception 'ill-formed-special-form src)
                           (let ((params (##cadr c))
                                 (rbody (##cddr c)))
                             (loop (##cdr cs)
                                   entries
                                   (##cons 'lambda (##cons params rbody))))))
                      ;; (tail: eff (args ...) body ...)
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
                      ;; (eff (k args ...) body ...)
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
          (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

;; (with-capability-handler cap (tail: (args ...) hbody ...) body ...)
;; (with-capability-handler cap ((k args ...) hbody ...) body ...)
(##define-syntax with-capability-handler
  (lambda (src)
    (let ((forms (##source-code src)))
      (if (and (##pair? forms)
               (##pair? (##cdr forms))
               (##pair? (##cddr forms))
               (##pair? (##cdddr forms)))
          (let ((cap-var (##cadr forms))
                (clause (##source-code (##caddr forms)))
                (body (##cdddr forms)))
            (cond
              ((and (##pair? clause)
                    (##eq? (##desourcify (##car clause)) 'tail:)
                    (##pair? (##cdr clause))
                    (##pair? (##cddr clause)))
               (##list 'gambit/effect#call-with-tail-capability
                       (##cons 'lambda (##cons (##cadr clause) (##cddr clause)))
                       (##cons 'lambda (##cons (##list cap-var) body))))
              ((and (##pair? clause)
                    (##pair? (##cdr clause)))
               (##list 'gambit/effect#call-with-suspend-capability
                       (##cons 'lambda (##cons (##car clause) (##cdr clause)))
                       (##cons 'lambda (##cons (##list cap-var) body))))
              (else
               (##raise-expression-parsing-exception 'ill-formed-special-form src))))
          (##raise-expression-parsing-exception 'ill-formed-special-form src)))))

;;;============================================================================
