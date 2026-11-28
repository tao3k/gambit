;;;============================================================================

;;; File: "unwind.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Scope-Bound Exception Unwind Trampoline for `(srfi 226)` & `(gambit effect)`.
;;;
;;; Keeps `st.mc`, `st.marks`, `st.barriers`, `st.handlers`, and generator
;;; unwind hooks coherent whenever an uncaught exception escapes through an
;;; enclosing `with-exception-catcher` or `with-exception-handler`.

(define (%make-mc-eh-trampoline prev-eh)
  (let ((box (cons prev-eh #f)))
    (let ((fn (lambda (exc)
                (%mc-unwind-and-raise! exc box))))
      (set-cdr! box fn)
      fn)))

(define %mc-eh-trampoline-code
  (let ()
    (declare (inlining-limit 0))
    (##closure-code (%make-mc-eh-trampoline #f))))

(define (%mc-eh-trampoline? proc)
  (and (##closure? proc)
       (##eq? (##closure-code proc) %mc-eh-trampoline-code)))

(define (%mc-eh-trampoline-prev proc)
  (car (##closure-ref proc 1)))

(define (%mc-ensure-tramp-denv st cur-denv cur-eh)
  (if (and (eq? cur-denv (%st-eh-outer-denv st))
           (eq? cur-eh (%st-eh-outer-proc st)))
      (%st-eh-tramp-denv st)
      (let* ((tramp (let () (declare (inlining-limit 0)) (%make-mc-eh-trampoline cur-eh)))
             (tdenv (macro-denv-set cur-denv exception-handler tramp)))
        (%st-eh-outer-denv-set! st cur-denv)
        (%st-eh-outer-proc-set! st cur-eh)
        (%st-eh-tramp-denv-set! st tdenv)
        (%st-eh-tramp-proc-set! st tramp)
        tdenv)))

(define (%mc-unwind-and-raise! exc box)
  (let* ((fallback-eh (car box))
         (self-tramp (cdr box))
         (st (%tc-current))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st)))
    (let loop ((cur cur-mc) (hooks '()) (crossed-replay? #f))
      (if (null? cur)
          (macro-dynamic-bind
           exception-handler
           fallback-eh
           (lambda () (fallback-eh exc)))
          (let* ((f (car cur))
                 (rest (cdr cur))
                 (kind (%pf-kind f))
                 (hook (%pf-unwind-hook f))
                 (next-hooks (if (procedure? hook) (cons hook hooks) hooks))
                 (next-crossed? (or crossed-replay?
                                    hook
                                    (eq? kind 'underflow)))
                 (scope (%pf-eh-scope f)))
            (if scope
                (let ((scope-is-tramp (%mc-eh-trampoline? scope)))
                  (if (or (eq? scope self-tramp)
                          (not scope-is-tramp)
                          crossed-replay?)
                      (let ((target-eh
                             (if scope-is-tramp
                                 (%mc-eh-trampoline-prev scope)
                                 scope)))
                        (%st-mc-set! st rest)
                        (%st-marks-set! st (%pf-marks f))
                        (%st-barriers-set! st (%pf-barriers f))
                        (%st-handlers-set! st (%pf-handlers f))
                        (let hloop ((hs next-hooks))
                          (if (pair? hs)
                              (begin
                                ((car hs) 'unwind)
                                (hloop (cdr hs)))))
                        (let ((res
                               (macro-dynamic-bind
                                exception-handler
                                target-eh
                                (lambda () (target-eh exc)))))
                          (%st-mc-set! st cur-mc)
                          (%st-marks-set! st cur-marks)
                          (%st-barriers-set! st cur-barriers)
                          (%st-handlers-set! st cur-handlers)
                          (let rloop ((hs next-hooks))
                            (if (pair? hs)
                                (begin
                                  ((car hs) 'restore)
                                  (rloop (cdr hs)))))
                          res))
                      ;; Foreign outer trampoline with no intervening replay/generator:
                      ;; our own prompt was already popped; delegate without popping outer mc.
                      (macro-dynamic-bind
                       exception-handler
                       fallback-eh
                       (lambda () (fallback-eh exc)))))
                (loop rest next-hooks next-crossed?)))))))

;;;============================================================================
