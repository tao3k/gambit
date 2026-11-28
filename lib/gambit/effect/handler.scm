;;;============================================================================

;;; File: "handler.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Dynamic effect handler installation, Koka tail-resumptive fast path,
;;; zero-closure suspending capture receivers, and `perform`.

(define (%entries-all-tail? entries)
  (let loop ((es entries))
    (cond
      ((null? es) #t)
      ((eq? (%entry-kind (car es)) 'tail) (loop (cdr es)))
      (else #f))))

(define (%find-entry-in-frame eff entries)
  (if (and (pair? entries) (eq? (%entry-effect (car entries)) eff))
      (car entries)
      (let loop ((es (if (pair? entries) (cdr entries) '())))
        (cond
          ((null? es) #f)
          ((eq? (%entry-effect (car es)) eff) (car es))
          (else (loop (cdr es)))))))

(define (%handlers-prefix-before handlers frame)
  (if (or (null? handlers) (eq? (car handlers) frame))
      '()
      (let loop ((cur handlers) (acc '()))
        (if (or (null? cur) (eq? (car cur) frame))
            (reverse acc)
            (loop (cdr cur) (cons (car cur) acc))))))

;; Zero-closure multi-arg capture receivers for suspending with-handler (<= 4 args)
(define (%install-handler-cont! escape-k frame return-fn thunk)
  (let* ((st (%tc-fast))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   tag
                                   #f
                                   escape-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers
                                   #f
                                   #f)))
    (%st-mc-set! st (cons pframe saved-mc))
    (%st-handlers-set! st (cons frame saved-handlers))
    (let ((res (if return-fn (return-fn (thunk)) (thunk))))
      (%mc-return1 res))))

(define (%install-handler-cont-scoped! escape-k frame return-fn thunk)
  (let* ((st (%tc-fast))
         (tramp (macro-current-exception-handler))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   tag
                                   #f
                                   escape-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers
                                   tramp
                                   #f)))
    (%st-mc-set! st (cons pframe saved-mc))
    (%st-handlers-set! st (cons frame saved-handlers))
    (let ((res (if return-fn (return-fn (thunk)) (thunk))))
      (%mc-return1 res))))

(define (%call-with-handler-entries entries return-fn thunk)
  (if (%entries-all-tail? entries)
      ;; Koka ICFP '21 Tail-Resumptive Fast Path:
      ;; Zero prompt, zero continuation capture, zero parameterize!
      (let* ((frame (%make-handler-frame #f entries))
             (st (%tc-fast))
             (old-handlers (%st-handlers st)))
        (%st-handlers-set! st (cons frame old-handlers))
        (with-exception-catcher
         (lambda (e)
           (%st-handlers-set! (%tc-fast) old-handlers)
           (raise e))
         (lambda ()
           (let ((res (thunk)))
             (%st-handlers-set! (%tc-fast) old-handlers)
             (if return-fn (return-fn res) res)))))
      ;; Native Single-Capture Deep Effect Handler on SRFI-226 metacontinuation
      ;; with scope-bound exception unwind trampoline outside ##continuation-capture
      ;; so escape-k and sub-k share identical denv.
      (let* ((tag (make-continuation-prompt-tag 'effect-handler))
             (frame (%make-handler-frame tag entries))
             (cur-eh (macro-current-exception-handler)))
        (if (%mc-eh-trampoline? cur-eh)
            (##continuation-capture %install-handler-cont! frame return-fn thunk)
            (let* ((st (%tc-fast))
                   (cur-denv (macro-thread-denv (macro-current-thread)))
                   (tdenv (%mc-ensure-tramp-denv st cur-denv cur-eh)))
              (##dynamic-env-bind
               tdenv
               (lambda ()
                 (##continuation-capture %install-handler-cont-scoped!
                                         frame return-fn thunk))))))))

;; Functional API:
;; (call-with-effect-handler '((tail: eff proc) (eff proc)) return-fn thunk)
(define (call-with-effect-handler specs return-fn thunk)
  (if (not (list? specs))
      (error "call-with-effect-handler: expected list of handler specs" specs))
  (if (and return-fn (not (procedure? return-fn)))
      (error "call-with-effect-handler: expected procedure or #f for return handler" return-fn))
  (if (not (procedure? thunk))
      (error "call-with-effect-handler: expected procedure" thunk))
  (let ((entries
         (map (lambda (spec)
                (if (not (and (pair? spec) (pair? (cdr spec))))
                    (error "call-with-effect-handler: malformed handler spec" spec))
                (if (eq? (car spec) 'tail:)
                    (if (not (and (pair? (cddr spec)) (effect? (cadr spec)) (procedure? (caddr spec))))
                        (error "call-with-effect-handler: malformed tail handler spec" spec)
                        (%make-handler-entry (cadr spec) 'tail (caddr spec)))
                    (if (not (and (effect? (car spec)) (procedure? (cadr spec))))
                        (error "call-with-effect-handler: malformed handler spec" spec)
                        (%make-handler-entry (car spec) 'suspend (cadr spec)))))
              specs)))
    (%call-with-handler-entries entries return-fn thunk)))

;;;----------------------------------------------------------------------------
;;; Zero-Closure Multi-Arg Perform Capture Receivers (all <= 4 args)

(define (%perform-fast-cap-0! sub-k frame proc)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
         (escape-k (%pf-escape-k pframe))
         (cur-marks (%st-marks st))
         (pf-marks (%pf-marks pframe))
         (cap-marks (if (eq? cur-marks pf-marks)
                        '()
                        (%list-prefix-until cur-marks pf-marks)))
         (handlers (%st-handlers st))
         (cap-handlers (if (eq? (car handlers) frame)
                           '()
                           (%handlers-prefix-before handlers frame)))
         (ek (%make-effect-continuation sub-k pframe '() cap-marks cap-handlers frame (%make-ec-state))))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv escape-k)))
        (begin
          (%st-mc-set! st rest)
          (%st-marks-set! st pf-marks)
          (%st-barriers-set! st (%pf-barriers pframe))
          (%st-handlers-set! st (%pf-handlers pframe))
          (##continuation-graft escape-k proc ek))
        (##continuation-graft
         escape-k
         (lambda ()
           (%st-mc-set! st rest)
           (%st-marks-set! st pf-marks)
           (%st-barriers-set! st (%pf-barriers pframe))
           (%st-handlers-set! st (%pf-handlers pframe))
           (proc ek))))))

(define (%perform-fast-cap-1! sub-k frame proc a1)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
         (escape-k (%pf-escape-k pframe))
         (cur-marks (%st-marks st))
         (pf-marks (%pf-marks pframe))
         (cap-marks (if (eq? cur-marks pf-marks)
                        '()
                        (%list-prefix-until cur-marks pf-marks)))
         (handlers (%st-handlers st))
         (cap-handlers (if (eq? (car handlers) frame)
                           '()
                           (%handlers-prefix-before handlers frame)))
         (ek (%make-effect-continuation sub-k pframe '() cap-marks cap-handlers frame (%make-ec-state))))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv escape-k)))
        (begin
          (%st-mc-set! st rest)
          (%st-marks-set! st pf-marks)
          (%st-barriers-set! st (%pf-barriers pframe))
          (%st-handlers-set! st (%pf-handlers pframe))
          (##continuation-graft escape-k proc ek a1))
        (##continuation-graft
         escape-k
         (lambda ()
           (%st-mc-set! st rest)
           (%st-marks-set! st pf-marks)
           (%st-barriers-set! st (%pf-barriers pframe))
           (%st-handlers-set! st (%pf-handlers pframe))
           (proc ek a1))))))

(define (%perform-fast-cap-n! sub-k frame proc args)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
         (escape-k (%pf-escape-k pframe))
         (cur-marks (%st-marks st))
         (pf-marks (%pf-marks pframe))
         (cap-marks (if (eq? cur-marks pf-marks)
                        '()
                        (%list-prefix-until cur-marks pf-marks)))
         (handlers (%st-handlers st))
         (cap-handlers (if (eq? (car handlers) frame)
                           '()
                           (%handlers-prefix-before handlers frame)))
         (ek (%make-effect-continuation sub-k pframe '() cap-marks cap-handlers frame (%make-ec-state))))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv escape-k)))
        (begin
          (%st-mc-set! st rest)
          (%st-marks-set! st pf-marks)
          (%st-barriers-set! st (%pf-barriers pframe))
          (%st-handlers-set! st (%pf-handlers pframe))
          (##continuation-graft escape-k ##apply proc (cons ek args)))
        (##continuation-graft
         escape-k
         (lambda ()
           (%st-mc-set! st rest)
           (%st-marks-set! st pf-marks)
           (%st-barriers-set! st (%pf-barriers pframe))
           (%st-handlers-set! st (%pf-handlers pframe))
           (##apply proc (cons ek args)))))))

(define (%perform-suspend-dispatch st handlers frame proc a1 a2 more)
  (let ((tag (%frame-tag frame))
        (mc (%st-mc st)))
    ;; Fast path: handler's prompt is at the very top of mc
    (if (and (pair? mc)
             (let ((pframe (car mc)))
               (and (eq? (%pf-kind pframe) 'prompt)
                    (eq? (%pf-tag pframe) tag)
                    (eq? (%st-barriers st) (%pf-barriers pframe)))))
        (cond
          ((eq? a1 %ABSENT)
           (##continuation-capture %perform-fast-cap-0! frame proc))
          ((eq? a2 %ABSENT)
           (##continuation-capture %perform-fast-cap-1! frame proc a1))
          (else
           (##continuation-capture %perform-fast-cap-n! frame proc
                                   (cons a1 (cons a2 more)))))
        ;; General nested-prompt path
        (call-with-values
          (lambda () (%mc-split-at-tag mc tag))
          (lambda (prefix pframe rest)
            (if (not pframe)
                (error "perform: handler prompt not active"))
            (if (not (eq? (%st-barriers st) (%pf-barriers pframe)))
                (error "perform: cannot suspend across continuation barrier"))
            (if (pair? prefix) (%freeze-mc-prefix! prefix))
            (let ((cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
                  (cap-handlers (%handlers-prefix-before handlers frame))
                  (escape-k (%pf-escape-k pframe)))
              (##continuation-capture
               (lambda (sub-k)
                 (let ((ek (%make-effect-continuation sub-k pframe prefix cap-marks cap-handlers frame (%make-ec-state))))
                   (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
                            (macro-denv-dynwind (##continuation-denv escape-k)))
                       (begin
                         (%st-mc-set! st rest)
                         (%st-marks-set! st (%pf-marks pframe))
                         (%st-barriers-set! st (%pf-barriers pframe))
                         (%st-handlers-set! st (%pf-handlers pframe))
                         (cond
                           ((eq? a1 %ABSENT) (##continuation-graft escape-k proc ek))
                           ((eq? a2 %ABSENT) (##continuation-graft escape-k proc ek a1))
                           ((null? more)     (##continuation-graft escape-k proc ek a1 a2))
                           (else             (##continuation-graft escape-k ##apply proc
                                                                   (cons ek (cons a1 (cons a2 more)))))))
                       (##continuation-graft
                        escape-k
                        (lambda ()
                          (%st-mc-set! st rest)
                          (%st-marks-set! st (%pf-marks pframe))
                          (%st-barriers-set! st (%pf-barriers pframe))
                          (%st-handlers-set! st (%pf-handlers pframe))
                          (cond
                            ((eq? a1 %ABSENT) (proc ek))
                            ((eq? a2 %ABSENT) (proc ek a1))
                            ((null? more)     (proc ek a1 a2))
                            (else             (##apply proc (cons ek (cons a1 (cons a2 more))))))))))))))))))

;;;----------------------------------------------------------------------------
;;; Perform (Specialized 0/1/2/N-arg Fast Path — Zero Rest-Arg Consing)

(define (perform eff
                 #!optional
                 (a1 %ABSENT)
                 (a2 %ABSENT)
                 #!rest
                 more)
  (if (not (effect? eff))
      (error "perform: expected effect" eff))
  (let* ((st (%tc-fast))
         (handlers (%st-handlers st)))
    (let loop ((fs handlers))
      (if (null? fs)
          (error "perform: unhandled effect" (effect-name eff))
          (let* ((frame (car fs))
                 (entry (%find-entry-in-frame eff (%frame-entries frame))))
            (if (not entry)
                (loop (cdr fs))
                (let ((kind (%entry-kind entry)))
                  (cond
                    ((eq? kind 'tail)
                     ;; Koka Tail-Resumptive Fast Path: direct call, zero capture!
                     (let ((proc (%entry-proc entry)))
                       (cond
                         ((eq? a1 %ABSENT) (proc))
                         ((eq? a2 %ABSENT) (proc a1))
                         ((null? more)     (proc a1 a2))
                         (else             (apply proc a1 a2 more)))))
                    ((eq? kind 'gen)
                     ;; Direct-Style Symmetric Generator Fast Path (0 alloc!)
                     (let* ((gen (%entry-proc entry))
                            (tag (%frame-tag frame))
                            (mc (%st-mc st)))
                       (if (and (not (eq? a1 %ABSENT))
                                (eq? a2 %ABSENT)
                                (pair? mc)
                                (eq? (car handlers) frame)
                                (let ((pf (car mc)))
                                  (and (eq? (%pf-kind pf) 'prompt)
                                       (eq? (%pf-tag pf) tag)
                                       (let ((h (%pf-handler pf)))
                                         (or (not h) (eq? h 'init)))
                                       (eq? (%st-barriers st) (%pf-barriers pf))
                                       (eq? (%st-marks st) (%pf-marks pf)))))
                           (##continuation-capture %gen-yield-swap-cont! gen a1)
                           (%perform-suspend-dispatch st handlers frame
                                                      (%gen-yield-slow-handler gen)
                                                      a1 a2 more))))
                    (else
                     (%perform-suspend-dispatch st handlers frame
                                                (%entry-proc entry)
                                                a1 a2 more))))))))))

;;;============================================================================
