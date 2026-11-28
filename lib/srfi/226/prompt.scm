;;;============================================================================

;;; File: "prompt.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Continuation Prompts, Transactional Post-dynamic-wind Abort, Metacontinuation
;;; Returns & Continuation Barriers for `(srfi 226)`.

(define (%default-prompt-handler tag)
  (lambda (thunk)
    (call-with-continuation-prompt thunk tag)))

;; Fast single-value return through topmost metacontinuation frame.
(define (%mc-return1 val)
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (null? mc)
        val
        (let* ((top (car mc))
               (rest (cdr mc))
               (ek (%pf-escape-k top))
               (h (%pf-handler top)))
          (%st-mc-set! st rest)
          (%st-marks-set! st (%pf-marks top))
          (%st-barriers-set! st (%pf-barriers top))
          (%st-handlers-set! st (%pf-handlers top))
          (if (or (not h) (eq? h %DEFAULT-PROMPT-HANDLER))
              (begin
                (let () (declare (inlining-limit 0)) (%mc-try-reclaim-return! top ek val))
                (##continuation-return ek val))
              (##continuation-return ek val))))))

;; Multi-value return through topmost metacontinuation frame (0/1/2/3/N).
(define (%mc-return-vals #!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (null? mc)
        (cond
          ((eq? v1 %ABSENT) (values))
          ((eq? v2 %ABSENT) v1)
          ((eq? v3 %ABSENT) (values v1 v2))
          ((null? more) (values v1 v2 v3))
          (else (apply values v1 v2 v3 more)))
        (let* ((top (car mc))
               (rest (cdr mc))
               (k (%pf-escape-k top))
               (h (%pf-handler top)))
          (%st-mc-set! st rest)
          (%st-marks-set! st (%pf-marks top))
          (%st-barriers-set! st (%pf-barriers top))
          (%st-handlers-set! st (%pf-handlers top))
          (cond
            ((eq? v1 %ABSENT) (##continuation-return k))
            ((eq? v2 %ABSENT)
             (if (not h)
                 (begin
                   (let () (declare (inlining-limit 0)) (%mc-try-reclaim-return! top k v1))
                   (##continuation-return k v1))
                 (##continuation-return k v1)))
            ((eq? v3 %ABSENT) (##continuation-return k v1 v2))
            ((null? more) (##continuation-return k v1 v2 v3))
            (else (##apply ##continuation-return k v1 v2 v3 more)))))))

;; Split mc at the first prompt frame matching tag.
(define (%mc-split-at-tag mc tag)
  (if (and (pair? mc)
           (eq? (%pf-kind (car mc)) 'prompt)
           (eq? (%pf-tag (car mc)) tag))
      (values '() (car mc) (cdr mc))
      (let loop ((cur mc) (rev-prefix '()))
        (cond
          ((null? cur)
           (values #f #f #f))
          ((and (eq? (%pf-kind (car cur)) 'prompt)
                (eq? (%pf-tag (car cur)) tag))
           (values (reverse rev-prefix) (car cur) (cdr cur)))
          (else
           (loop (cdr cur) (cons (car cur) rev-prefix)))))))

(define (%mc-find-tail-slow mc tag)
  (let loop ((cur mc) (rev-prefix '()))
    (cond
      ((null? cur) #f)
      ((and (eq? (%pf-kind (car cur)) 'prompt)
            (eq? (%pf-tag (car cur)) tag))
       (cons (reverse rev-prefix) cur))
      (else
       (loop (cdr cur) (cons (car cur) rev-prefix))))))

(define (%list-prefix-until xs stop-tail)
  (if (eq? xs stop-tail)
      '()
      (let loop ((cur xs) (acc '()))
        (if (or (eq? cur stop-tail) (null? cur))
            (reverse acc)
            (loop (cdr cur) (cons (car cur) acc))))))

(define (%entering-barrier? captured-barriers current-barriers)
  (if (eq? captured-barriers current-barriers)
      #f
      (let loop ((bs captured-barriers))
        (cond
          ((null? bs) #f)
          ((memq (car bs) current-barriers) (loop (cdr bs)))
          (else #t)))))

(define (%barrier-between? current-barriers pframe-barriers)
  (not (eq? current-barriers pframe-barriers)))

;;;----------------------------------------------------------------------------
;;; Prompts & Barriers (Zero-Closure <=4-Arg Capture)

(define (%prompt-cont! escape-k proc tag handler)
  (let* ((st (%tc-current))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (frame (%make-mc-frame-9 'prompt
                                  tag
                                  handler
                                  escape-k
                                  saved-marks
                                  saved-barriers
                                  saved-handlers
                                  #f
                                  #f)))
    (%st-mc-set! st (cons frame saved-mc))
    (call-with-values proc %mc-return-vals)))

(define (%prompt-cont-scoped! escape-k proc tag handler)
  (let* ((st (%tc-current))
         (tramp (macro-current-exception-handler))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (frame (%make-mc-frame-9 'prompt
                                  tag
                                  handler
                                  escape-k
                                  saved-marks
                                  saved-barriers
                                  saved-handlers
                                  tramp
                                  #f)))
    (%st-mc-set! st (cons frame saved-mc))
    (call-with-values proc %mc-return-vals)))

(define (call-with-continuation-prompt proc
                                       #!optional
                                       (tag %default-prompt-tag)
                                       (handler %DEFAULT-PROMPT-HANDLER))
  (if (not (procedure? proc))
      (error "call-with-continuation-prompt: expected procedure" proc))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "call-with-continuation-prompt: expected continuation-prompt-tag" tag))
  (if (not (or (eq? handler %DEFAULT-PROMPT-HANDLER) (procedure? handler)))
      (error "call-with-continuation-prompt: expected handler procedure" handler))
  (let ((cur-eh (macro-current-exception-handler)))
    (if (%mc-eh-trampoline? cur-eh)
        (##continuation-capture %prompt-cont! proc tag handler)
        (let* ((st (%tc-current))
               (cur-denv (macro-thread-denv (macro-current-thread)))
               (tdenv (%mc-ensure-tramp-denv st cur-denv cur-eh)))
          (##dynamic-env-bind
           tdenv
           (lambda ()
             (##continuation-capture %prompt-cont-scoped! proc tag handler)))))))

(define (continuation-prompt-available? tag #!optional (cont %ABSENT))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "continuation-prompt-available?: expected continuation-prompt-tag" tag))
  (let ((frames
         (if (eq? cont %ABSENT)
             (%st-mc (%tc-current))
             (let ((cell (%extract-any-cont-cell cont)))
               (if cell
                   (%osc-prefix-fast cell)
                   (error "continuation-prompt-available?: expected continuation" cont))))))
    (let loop ((cur frames))
      (cond
        ((null? cur) #f)
        ((and (eq? (%pf-kind (car cur)) 'prompt)
              (eq? (%pf-tag (car cur)) tag))
         #t)
        (else (loop (cdr cur)))))))

(define (%invoke-abort-handler handler tag a1 a2 a3 more)
  (if (or (eq? handler %DEFAULT-PROMPT-HANDLER)
          (eq? handler %FROZEN-DEFAULT-PROMPT-HANDLER))
      (if (and (not (eq? a1 %ABSENT)) (eq? a2 %ABSENT))
          (call-with-continuation-prompt a1 tag)
          (let ((h (%default-prompt-handler tag)))
            (cond
              ((eq? a1 %ABSENT) (h))
              ((eq? a3 %ABSENT) (h a1 a2))
              ((null? more) (h a1 a2 a3))
              (else (apply h a1 a2 a3 more)))))
      (cond
        ((eq? a1 %ABSENT) (handler))
        ((eq? a2 %ABSENT) (handler a1))
        ((eq? a3 %ABSENT) (handler a1 a2))
        ((null? more) (handler a1 a2 a3))
        (else (apply handler a1 a2 a3 more)))))

;; Transactional abort: when no dynamic-wind frames separate the current
;; point from `escape-k` (common fast path), commit `st` directly with zero
;; extra allocation; otherwise defer `st` commit to the post-unwind landing
;; thunk so `dynamic-wind` after-thunks observe intact prompts/marks/handlers
;; and raising inside an after-thunk never corrupts `st`.
(define (%abort-to-pframe! st prefix pframe rest tag a1 a2 a3 more)
  (let ((escape-k (%pf-escape-k pframe))
        (handler (%pf-handler pframe)))
    (if (%mc-same-dynwind? escape-k)
        (begin
          (%st-mc-set! st rest)
          (%st-marks-set! st (%pf-marks pframe))
          (%st-barriers-set! st (%pf-barriers pframe))
          (%st-handlers-set! st (%pf-handlers pframe))
          (if (pair? prefix) (%mc-run-unwind-hooks! prefix 'unwind))
          (let ((uh (%pf-unwind-hook pframe)))
            (if (procedure? uh) (uh 'unwind)))
          (if (or (eq? handler %DEFAULT-PROMPT-HANDLER)
                  (eq? handler %FROZEN-DEFAULT-PROMPT-HANDLER))
              (if (and (not (eq? a1 %ABSENT)) (eq? a2 %ABSENT))
                  (##continuation-graft escape-k call-with-continuation-prompt a1 tag)
                  (let ((h (%default-prompt-handler tag)))
                    (cond
                      ((eq? a1 %ABSENT) (##continuation-graft escape-k h))
                      ((eq? a3 %ABSENT) (##continuation-graft escape-k h a1 a2))
                      ((null? more) (##continuation-graft escape-k h a1 a2 a3))
                      (else (##continuation-graft escape-k ##apply h
                                                  (cons a1 (cons a2 (cons a3 more))))))))
              (cond
                ((eq? a1 %ABSENT)
                 (##continuation-graft escape-k handler))
                ((eq? a2 %ABSENT)
                 (##continuation-graft escape-k handler a1))
                ((eq? a3 %ABSENT)
                 (##continuation-graft escape-k handler a1 a2))
                ((null? more)
                 (##continuation-graft escape-k handler a1 a2 a3))
                (else
                 (##continuation-graft escape-k ##apply handler
                                       (cons a1 (cons a2 (cons a3 more))))))))
        (##continuation-graft
         escape-k
         (lambda ()
           (let ((st2 (%tc-current)))
             (%st-mc-set! st2 rest)
             (%st-marks-set! st2 (%pf-marks pframe))
             (%st-barriers-set! st2 (%pf-barriers pframe))
             (%st-handlers-set! st2 (%pf-handlers pframe)))
           (if (pair? prefix) (%mc-run-unwind-hooks! prefix 'unwind))
           (let ((uh (%pf-unwind-hook pframe)))
             (if (procedure? uh) (uh 'unwind)))
           (%invoke-abort-handler handler tag a1 a2 a3 more))))))

(define (abort-current-continuation tag
                                    #!optional
                                    (a1 %ABSENT)
                                    (a2 %ABSENT)
                                    (a3 %ABSENT)
                                    #!rest
                                    more)
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "abort-current-continuation: expected continuation-prompt-tag" tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (%abort-to-pframe! st '() (car mc) (cdr mc) tag a1 a2 a3 more)
        (let ((found (%mc-find-tail-slow mc tag)))
          (if (not found)
              (error "abort-current-continuation: no prompt found for tag" tag)
              (let ((tail (cdr found)))
                (%abort-to-pframe! st (car found) (car tail) (cdr tail) tag a1 a2 a3 more)))))))

(define (%pop-barrier-token! st token)
  (let ((bs (%st-barriers st)))
    (if (and (pair? bs) (eq? (car bs) token))
        (%st-barriers-set! st (cdr bs))
        (let loop ((cur bs))
          (cond
            ((null? cur) #!void)
            ((eq? (car cur) token)
             (%st-barriers-set! st (cdr cur)))
            (else (loop (cdr cur))))))))

(define (call-with-continuation-barrier thunk)
  (if (not (procedure? thunk))
      (error "call-with-continuation-barrier: expected procedure" thunk))
  (let ((barrier-token (list 'continuation-barrier)))
    (dynamic-wind
      (lambda ()
        (let ((st (%tc-current)))
          (%st-barriers-set! st (cons barrier-token (%st-barriers st)))))
      thunk
      (lambda ()
        (%pop-barrier-token! (%tc-current) barrier-token)))))

;;;============================================================================
