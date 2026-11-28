;;;============================================================================

;;; File: "cont.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Composable, Non-Composable & Lock-Free Atomic One-Shot Continuations
;;; (`call-with-composable-continuation`, `call-with-non-composable-continuation`,
;;; `call/1cc`, `call-with-one-shot-composable-continuation`,
;;; `promote-one-shot-continuation!`) with O(1) closure-code identity,
;;; zero-leak consumed-slot clearing, and transactional dynamic-wind commit.

;; Zero-closure <=4-arg capture receiver for 1-value / 0-value composable replay.
;; Transactionally defers control-state commit to a post-unwind landing thunk
;; via `##continuation-graft` when crossing `dynamic-wind` frames (including
;; `call-with-continuation-barrier`) so caller after-thunks observe pure caller
;; state and active continuation barriers remain enforced inside `sub-k`.
(define (%composable-replay-1! caller-k cell v1)
  (let* ((cst (%tc-current))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (caller-mc (%st-mc cst))
         (caller-marks (%st-marks cst))
         (caller-barriers (%st-barriers cst))
         (caller-handlers (%st-handlers cst))
         (prefix (%osc-prefix-fast cell))
         (cap-marks (%osc-marks-fast cell))
         (cap-handlers (%osc-handlers-fast cell))
         (sub-k (%osc-sub-k-fast cell))
         (uframe (%make-mc-frame-9 'underflow
                                   #f
                                   #t
                                   caller-k
                                   caller-marks
                                   caller-barriers
                                   caller-handlers
                                   eh-scope
                                   #f)))
    (if (%mc-same-dynwind? sub-k)
        (begin
          (%st-mc-set! cst
                       (if (null? prefix)
                           (cons uframe caller-mc)
                           (append prefix (cons uframe caller-mc))))
          (%st-marks-set! cst
                          (if (null? cap-marks)
                              caller-marks
                              (append cap-marks caller-marks)))
          (%st-barriers-set! cst caller-barriers)
          (%st-handlers-set! cst
                             (if (null? cap-handlers)
                                 caller-handlers
                                 (append cap-handlers caller-handlers)))
          (if (eq? v1 %ABSENT)
              (##continuation-return sub-k)
              (##continuation-return sub-k v1)))
        (##continuation-graft
         sub-k
         (lambda ()
           (let ((st (%tc-current)))
             (%st-mc-set! st
                          (if (null? prefix)
                              (cons uframe caller-mc)
                              (append prefix (cons uframe caller-mc))))
             (%st-marks-set! st
                             (if (null? cap-marks)
                                 caller-marks
                                 (append cap-marks caller-marks)))
             (%st-barriers-set! st caller-barriers)
             (%st-handlers-set! st
                                (if (null? cap-handlers)
                                    caller-handlers
                                    (append cap-handlers caller-handlers))))
           (if (eq? v1 %ABSENT) (values) v1))))))

;; Zero-closure <=4-arg fast receiver for exclusively consumed one-shot
;; composable continuation with empty prefix/marks/handlers.
;; Uses non-destructive `##continuation-return` because `caller-k` (saved in
;; `uframe`) may sit directly above `sub-k` when invoked without aborting first,
;; so its break chain can reference `sub-k`'s stack span. Defers control-state
;; commit to a post-unwind landing thunk when crossing `dynamic-wind`.
(define (%composable-oneshot-replay-1! caller-k sub-k v1)
  (let* ((cst (%tc-current))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (caller-mc (%st-mc cst))
         (caller-marks (%st-marks cst))
         (caller-barriers (%st-barriers cst))
         (caller-handlers (%st-handlers cst))
         (uframe (%make-mc-frame-9 'underflow
                                   #f
                                   #t
                                   caller-k
                                   caller-marks
                                   caller-barriers
                                   caller-handlers
                                   eh-scope
                                   #f)))
    (if (%mc-same-dynwind? sub-k)
        (begin
          (%st-mc-set! cst (cons uframe caller-mc))
          (##continuation-return sub-k v1))
        (##continuation-graft
         sub-k
         (lambda ()
           (let ((st (%tc-current)))
             (%st-mc-set! st (cons uframe caller-mc))
             (%st-marks-set! st caller-marks)
             (%st-barriers-set! st caller-barriers)
             (%st-handlers-set! st caller-handlers))
           v1)))))

(define (%invoke-composable-parts sub-k prefix cap-marks cap-handlers v1 v2 v3 more)
  (if (and (null? prefix) (null? cap-marks) (null? cap-handlers)
           (not (eq? v1 %ABSENT)) (eq? v2 %ABSENT))
      (##continuation-capture %composable-oneshot-replay-1! sub-k v1)
      (##continuation-capture
       (lambda (caller-k)
         (let* ((cst (%tc-current))
                (cur-eh (macro-current-exception-handler))
                (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
                (caller-mc (%st-mc cst))
                (caller-marks (%st-marks cst))
                (caller-barriers (%st-barriers cst))
                (caller-handlers (%st-handlers cst))
                (uframe (%make-mc-frame-9 'underflow
                                          #f
                                          #t
                                          caller-k
                                          caller-marks
                                          caller-barriers
                                          caller-handlers
                                          eh-scope
                                          #f)))
           (if (%mc-same-dynwind? sub-k)
               (begin
                 (%st-mc-set! cst
                              (if (null? prefix)
                                  (cons uframe caller-mc)
                                  (append prefix (cons uframe caller-mc))))
                 (%st-marks-set! cst
                                 (if (null? cap-marks)
                                     caller-marks
                                     (append cap-marks caller-marks)))
                 (%st-barriers-set! cst caller-barriers)
                 (%st-handlers-set! cst
                                    (if (null? cap-handlers)
                                        caller-handlers
                                        (append cap-handlers caller-handlers)))
                 (cond
                   ((eq? v1 %ABSENT) (##continuation-return sub-k))
                   ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
                   ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
                   ((null? more) (##continuation-return sub-k v1 v2 v3))
                   (else (##apply ##continuation-return sub-k v1 v2 v3 more))))
               (##continuation-graft
                sub-k
                (lambda ()
                  (let ((st (%tc-current)))
                    (%st-mc-set! st
                                 (if (null? prefix)
                                     (cons uframe caller-mc)
                                     (append prefix (cons uframe caller-mc))))
                    (%st-marks-set! st
                                    (if (null? cap-marks)
                                        caller-marks
                                        (append cap-marks caller-marks)))
                    (%st-barriers-set! st caller-barriers)
                    (%st-handlers-set! st
                                       (if (null? cap-handlers)
                                           caller-handlers
                                           (append cap-handlers caller-handlers))))
                  (cond
                    ((eq? v1 %ABSENT) (values))
                    ((eq? v2 %ABSENT) v1)
                    ((eq? v3 %ABSENT) (values v1 v2))
                    ((null? more) (values v1 v2 v3))
                    (else (apply values v1 v2 v3 more)))))))))))

(define (%invoke-composable-cell cell v1 v2 v3 more)
  (if (eq? v2 %ABSENT)
      (##continuation-capture %composable-replay-1! cell v1)
      (##continuation-capture
       (lambda (caller-k)
         (let* ((cst (%tc-current))
                (cur-eh (macro-current-exception-handler))
                (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
                (caller-mc (%st-mc cst))
                (caller-marks (%st-marks cst))
                (caller-barriers (%st-barriers cst))
                (caller-handlers (%st-handlers cst))
                (prefix (%osc-prefix-fast cell))
                (cap-marks (%osc-marks-fast cell))
                (cap-handlers (%osc-handlers-fast cell))
                (sub-k (%osc-sub-k-fast cell))
                (uframe (%make-mc-frame-9 'underflow
                                          #f
                                          #t
                                          caller-k
                                          caller-marks
                                          caller-barriers
                                          caller-handlers
                                          eh-scope
                                          #f)))
           (if (%mc-same-dynwind? sub-k)
               (begin
                 (%st-mc-set! cst
                              (if (null? prefix)
                                  (cons uframe caller-mc)
                                  (append prefix (cons uframe caller-mc))))
                 (%st-marks-set! cst
                                 (if (null? cap-marks)
                                     caller-marks
                                     (append cap-marks caller-marks)))
                 (%st-barriers-set! cst caller-barriers)
                 (%st-handlers-set! cst
                                    (if (null? cap-handlers)
                                        caller-handlers
                                        (append cap-handlers caller-handlers)))
                 (cond
                   ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
                   ((null? more) (##continuation-return sub-k v1 v2 v3))
                   (else (##apply ##continuation-return sub-k v1 v2 v3 more))))
               (##continuation-graft
                sub-k
                (lambda ()
                  (let ((st (%tc-current)))
                    (%st-mc-set! st
                                 (if (null? prefix)
                                     (cons uframe caller-mc)
                                     (append prefix (cons uframe caller-mc))))
                    (%st-marks-set! st
                                    (if (null? cap-marks)
                                        caller-marks
                                        (append cap-marks caller-marks)))
                    (%st-barriers-set! st caller-barriers)
                    (%st-handlers-set! st
                                       (if (null? cap-handlers)
                                           caller-handlers
                                           (append cap-handlers caller-handlers))))
                  (cond
                    ((eq? v3 %ABSENT) (values v1 v2))
                    ((null? more) (values v1 v2 v3))
                    (else (apply values v1 v2 v3 more)))))))))))

(define (%commit-noncomp-and-return! cst cur-pframe cur-rest sub-k prefix
                                     cap-marks cap-barriers cap-handlers
                                     v1 v2 v3 more)
  (if (%mc-same-dynwind? sub-k)
      (begin
        (%st-mc-set! cst
                     (if (null? prefix)
                         (cons cur-pframe cur-rest)
                         (append prefix (cons cur-pframe cur-rest))))
        (%st-marks-set! cst
                        (if (null? cap-marks)
                            (%pf-marks cur-pframe)
                            (append cap-marks (%pf-marks cur-pframe))))
        (%st-barriers-set! cst cap-barriers)
        (%st-handlers-set! cst
                           (if (null? cap-handlers)
                               (%pf-handlers cur-pframe)
                               (append cap-handlers (%pf-handlers cur-pframe))))
        (cond
          ((eq? v1 %ABSENT) (##continuation-return sub-k))
          ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
          ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
          ((null? more) (##continuation-return sub-k v1 v2 v3))
          (else (##apply ##continuation-return sub-k v1 v2 v3 more))))
      (##continuation-graft
       sub-k
       (lambda ()
         (%st-mc-set! cst
                      (if (null? prefix)
                          (cons cur-pframe cur-rest)
                          (append prefix (cons cur-pframe cur-rest))))
         (%st-marks-set! cst
                         (if (null? cap-marks)
                             (%pf-marks cur-pframe)
                             (append cap-marks (%pf-marks cur-pframe))))
         (%st-barriers-set! cst cap-barriers)
         (%st-handlers-set! cst
                            (if (null? cap-handlers)
                                (%pf-handlers cur-pframe)
                                (append cap-handlers (%pf-handlers cur-pframe))))
         (cond
           ((eq? v1 %ABSENT) (values))
           ((eq? v2 %ABSENT) v1)
           ((eq? v3 %ABSENT) (values v1 v2))
           ((null? more) (values v1 v2 v3))
           (else (apply values v1 v2 v3 more)))))))

(define (%invoke-noncomp-parts sub-k prefix cap-marks cap-barriers cap-handlers tag
                               v1 v2 v3 more)
  (let ((cst (%tc-current)))
    (if (%entering-barrier? cap-barriers (%st-barriers cst))
        (error "continuation invocation blocked by continuation barrier"))
    (let* ((mc (%st-mc cst))
           (cur-pframe #f)
           (cur-rest #f))
      (if (and (pair? mc)
               (eq? (%pf-kind (car mc)) 'prompt)
               (eq? (%pf-tag (car mc)) tag))
          (begin
            (set! cur-pframe (car mc))
            (set! cur-rest (cdr mc)))
          (let ((found (%mc-find-tail-slow mc tag)))
            (if (not found)
                (error "non-composable continuation: target prompt not active" tag)
                (let ((tail (cdr found)))
                  (set! cur-pframe (car tail))
                  (set! cur-rest (cdr tail))))))
      (%commit-noncomp-and-return! cst cur-pframe cur-rest sub-k prefix
                                   cap-marks cap-barriers cap-handlers
                                   v1 v2 v3 more))))

(define (%invoke-noncomp-cell cell v1 v2 v3 more)
  (%invoke-noncomp-parts (%osc-sub-k-fast cell)
                         (%osc-prefix-fast cell)
                         (%osc-marks-fast cell)
                         (%osc-barriers-fast cell)
                         (%osc-handlers-fast cell)
                         (%osc-tag-fast cell)
                         v1 v2 v3 more))

;; Transactional raw continuation invocation: restore captured control state
;; (metacontinuation, marks, barriers, handlers) directly on the fast path
;; when no dynamic-wind frames separate caller and target, or inside a
;; post-unwind landing thunk via `##continuation-graft` when winding so
;; after-thunks observe intact inner control state and raising inside an
;; after-thunk never corrupts thread control state.
(define (%invoke-raw-parts sub-k cap-mc cap-marks cap-barriers cap-handlers
                           oneshot? v1 v2 v3 more)
  (let ((cst (%tc-current)))
    (if (%entering-barrier? cap-barriers (%st-barriers cst))
        (error "continuation invocation blocked by continuation barrier"))
    (if (%mc-same-dynwind? sub-k)
        (begin
          (%st-mc-set! cst cap-mc)
          (%st-marks-set! cst cap-marks)
          (%st-barriers-set! cst cap-barriers)
          (%st-handlers-set! cst cap-handlers)
          (cond
            ((eq? v1 %ABSENT) (##continuation-return sub-k))
            ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
            ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
            ((null? more) (##continuation-return sub-k v1 v2 v3))
            (else (##apply ##continuation-return sub-k v1 v2 v3 more))))
        (##continuation-graft
         sub-k
         (lambda ()
           (let ((st (%tc-current)))
             (%st-mc-set! st cap-mc)
             (%st-marks-set! st cap-marks)
             (%st-barriers-set! st cap-barriers)
             (%st-handlers-set! st cap-handlers))
           (cond
             ((eq? v1 %ABSENT) (values))
             ((eq? v2 %ABSENT) v1)
             ((eq? v3 %ABSENT) (values v1 v2))
             ((null? more) (values v1 v2 v3))
             (else (apply values v1 v2 v3 more))))))))

(define (%invoke-raw-cell cell v1 v2 v3 more)
  (%invoke-raw-parts (%osc-sub-k-fast cell)
                     (%osc-prefix-fast cell)
                     (%osc-marks-fast cell)
                     (%osc-barriers-fast cell)
                     (%osc-handlers-fast cell)
                     #f v1 v2 v3 more))

;; Multi-shot composable & non-composable closures (sole free variable: `cell`)
(define (%make-composable-closure cell)
  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
    (%invoke-composable-cell cell v1 v2 v3 more)))

(define (%make-noncomp-closure cell)
  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
    (%invoke-noncomp-cell cell v1 v2 v3 more)))

;; Zero-closure <=4-arg capture receivers for composable / non-composable capture
(define (%capture-composable-cont! sub-k proc cell-template)
  (let ((cell (%make-one-shot-cell
               %CONT-MULTISHOT-COW
               'composable
               sub-k
               (%osc-prefix-fast cell-template)
               (%osc-marks-fast cell-template)
               '()
               (%osc-handlers-fast cell-template)
               #f)))
    (proc (let () (declare (inlining-limit 0)) (%make-composable-closure cell)))))

(define (%capture-composable-fast! sub-k proc)
  (let ((cell (%make-one-shot-cell %CONT-MULTISHOT-COW 'composable sub-k '() '() '() '() #f)))
    (proc (let () (declare (inlining-limit 0)) (%make-composable-closure cell)))))

(define (%capture-noncomp-cont! sub-k proc cell-template)
  (let ((cell (%make-one-shot-cell
               %CONT-MULTISHOT-COW
               'noncomp
               sub-k
               (%osc-prefix-fast cell-template)
               (%osc-marks-fast cell-template)
               (%osc-barriers-fast cell-template)
               (%osc-handlers-fast cell-template)
               (%osc-tag-fast cell-template))))
    (proc (let () (declare (inlining-limit 0)) (%make-noncomp-closure cell)))))

(define (call-with-composable-continuation proc
                                           #!optional
                                           (tag %default-prompt-tag))
  (if (not (procedure? proc))
      (error "call-with-composable-continuation: expected procedure" proc))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "call-with-composable-continuation: expected continuation-prompt-tag" tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st))
         (prefix '())
         (pframe #f))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (set! pframe (car mc))
        (let ((found (%mc-find-tail-slow mc tag)))
          (if (not found)
              (error "call-with-composable-continuation: no prompt found for tag" tag))
          (set! prefix (car found))
          (set! pframe (cadr found))))
    (if (%barrier-between? (%st-barriers st) (%pf-barriers pframe))
        (error "call-with-composable-continuation: cannot capture across continuation barrier" tag))
    (%freeze-mc-frame! pframe)
    (if (pair? prefix) (%freeze-mc-prefix! prefix))
    (let ((cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
          (cap-handlers (%list-prefix-until (%st-handlers st) (%pf-handlers pframe))))
      (if (and (null? prefix) (null? cap-marks) (null? cap-handlers))
          (##continuation-capture %capture-composable-fast! proc)
          (let ((tmpl (%make-one-shot-cell %CONT-MULTISHOT-COW 'composable #f
                                           prefix cap-marks '() cap-handlers #f)))
            (##continuation-capture %capture-composable-cont! proc tmpl))))))

(define (call-with-non-composable-continuation proc
                                               #!optional
                                               (tag %default-prompt-tag))
  (if (not (procedure? proc))
      (error "call-with-non-composable-continuation: expected procedure" proc))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "call-with-non-composable-continuation: expected continuation-prompt-tag" tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st))
         (prefix '())
         (pframe #f))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (set! pframe (car mc))
        (let ((found (%mc-find-tail-slow mc tag)))
          (if (not found)
              (error "call-with-non-composable-continuation: no prompt found for tag" tag))
          (set! prefix (car found))
          (set! pframe (cadr found))))
    (%freeze-mc-frame! pframe)
    (if (pair? prefix) (%freeze-mc-prefix! prefix))
    (let* ((cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
           (cap-barriers (%st-barriers st))
           (cap-handlers (%list-prefix-until (%st-handlers st) (%pf-handlers pframe)))
           (tmpl (%make-one-shot-cell %CONT-MULTISHOT-COW 'noncomp #f
                                      prefix cap-marks cap-barriers cap-handlers tag)))
      (##continuation-capture %capture-noncomp-cont! proc tmpl))))

;;;----------------------------------------------------------------------------
;;; Lock-Free Atomic One-Shot Continuations & Unforgeable Closure-Code Identity

(define (%invoke-one-shot-cell cell v1 v2 v3 more)
  (let ((prev (%osc-cas-state! cell %CONT-ONE-SHOT-LIVE %CONT-ONE-SHOT-CONSUMED)))
    (cond
      ((fx= prev %CONT-ONE-SHOT-LIVE)
       ;; Exclusive one-shot winner: extract locals and immediately clear cell
       ;; slots so retaining the consumed closure leaks zero stack frames/marks.
       (let ((kind (%osc-kind-fast cell))
             (sub-k (%osc-sub-k-fast cell))
             (prefix (%osc-prefix-fast cell))
             (marks (%osc-marks-fast cell))
             (barriers (%osc-barriers-fast cell))
             (handlers (%osc-handlers-fast cell))
             (tag (%osc-tag-fast cell)))
         (%osc-clear-consumed! cell)
         (cond
           ((eq? kind 'composable)
            (%invoke-composable-parts sub-k prefix marks handlers v1 v2 v3 more))
           ((eq? kind 'noncomp)
            (%invoke-noncomp-parts sub-k prefix marks barriers handlers tag v1 v2 v3 more))
           (else
            (%invoke-raw-parts sub-k prefix marks barriers handlers #t v1 v2 v3 more)))))
      ((fx= prev %CONT-MULTISHOT-COW)
       ;; Promoted multi-shot continuation: never clear shared cell slots!
       (let ((kind (%osc-kind-fast cell)))
         (cond
           ((eq? kind 'composable)
            (%invoke-composable-cell cell v1 v2 v3 more))
           ((eq? kind 'noncomp)
            (%invoke-noncomp-cell cell v1 v2 v3 more))
           (else
            (%invoke-raw-cell cell v1 v2 v3 more)))))
      (else
       (error "one-shot continuation already consumed")))))

(define (%make-one-shot-closure cell)
  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
    (%invoke-one-shot-cell cell v1 v2 v3 more)))

(define (%init-one-shot-closure-code)
  (let ()
    (declare (inlining-limit 0))
    (##closure-code
     (%make-one-shot-closure
      (%make-one-shot-cell 0 'raw #f '() '() '() '() #f)))))

(define (%init-composable-closure-code)
  (let ()
    (declare (inlining-limit 0))
    (##closure-code
     (%make-composable-closure
      (%make-one-shot-cell 2 'composable #f '() '() '() '() #f)))))

(define (%init-noncomp-closure-code)
  (let ()
    (declare (inlining-limit 0))
    (##closure-code
     (%make-noncomp-closure
      (%make-one-shot-cell 2 'noncomp #f '() '() '() '() #f)))))

(define %one-shot-closure-code   (%init-one-shot-closure-code))
(define %composable-closure-code (%init-composable-closure-code))
(define %noncomp-closure-code    (%init-noncomp-closure-code))

(define (%extract-one-shot-cell obj)
  (if (and (##closure? obj)
           (##eq? (##closure-code obj) %one-shot-closure-code))
      (let ((c (##closure-ref obj 1)))
        (if (%one-shot-cell? c) c #f))
      #f))

;; O(1) lock-free cell extraction for ANY SRFI-226 continuation closure
;; (one-shot, composable, or non-composable) used by `continuation-marks`.
(define (%extract-any-cont-cell obj)
  (if (##closure? obj)
      (let ((code (##closure-code obj)))
        (if (or (##eq? code %one-shot-closure-code)
                (##eq? code %composable-closure-code)
                (##eq? code %noncomp-closure-code))
            (let ((c (##closure-ref obj 1)))
              (if (%one-shot-cell? c) c #f))
            #f))
      #f))

(define (one-shot-continuation? obj)
  (if (%extract-one-shot-cell obj) #t #f))

(define (one-shot-continuation-consumed? obj)
  (let ((c (%extract-one-shot-cell obj)))
    (if c
        (fx= (%osc-load-state c) %CONT-ONE-SHOT-CONSUMED)
        #f)))

(define (promote-one-shot-continuation! obj)
  (let ((c (%extract-one-shot-cell obj)))
    (if (not c)
        (error "promote-one-shot-continuation!: not a one-shot continuation" obj)
        (let ((prev (%osc-cas-state! c %CONT-ONE-SHOT-LIVE %CONT-MULTISHOT-COW)))
          (cond
            ((fx= prev %CONT-ONE-SHOT-LIVE) #t)
            ((fx= prev %CONT-MULTISHOT-COW) #t)
            (else
             (error "cannot promote consumed one-shot continuation" obj)))))))

;; Zero-closure <=4-arg capture receivers for one-shot continuations
(define (%capture-1cc-raw! sub-k proc cell-template)
  (let ((cell (%make-one-shot-cell
               %CONT-ONE-SHOT-LIVE
               'raw
               sub-k
               (%osc-prefix-fast cell-template)
               (%osc-marks-fast cell-template)
               (%osc-barriers-fast cell-template)
               (%osc-handlers-fast cell-template)
               #f)))
    (proc (let () (declare (inlining-limit 0)) (%make-one-shot-closure cell)))))

(define (%capture-1cc-noncomp! sub-k proc cell-template)
  (let ((cell (%make-one-shot-cell
               %CONT-ONE-SHOT-LIVE
               'noncomp
               sub-k
               (%osc-prefix-fast cell-template)
               (%osc-marks-fast cell-template)
               (%osc-barriers-fast cell-template)
               (%osc-handlers-fast cell-template)
               (%osc-tag-fast cell-template))))
    (proc (let () (declare (inlining-limit 0)) (%make-one-shot-closure cell)))))

(define (%capture-1cc-noncomp-fast! sub-k proc tag)
  (let ((cell (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'noncomp sub-k '() '() '() '() tag)))
    (proc (let () (declare (inlining-limit 0)) (%make-one-shot-closure cell)))))

(define (%capture-1shot-comp-fast! sub-k proc)
  (let ((cell (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'composable sub-k '() '() '() '() #f)))
    (proc (let () (declare (inlining-limit 0)) (%make-one-shot-closure cell)))))

(define (%capture-1shot-comp! sub-k proc cell-template)
  (let ((cell (%make-one-shot-cell
               %CONT-ONE-SHOT-LIVE
               'composable
               sub-k
               (%osc-prefix-fast cell-template)
               (%osc-marks-fast cell-template)
               '()
               (%osc-handlers-fast cell-template)
               #f)))
    (proc (let () (declare (inlining-limit 0)) (%make-one-shot-closure cell)))))

(define (call/1cc proc #!optional (tag %default-prompt-tag))
  (if (not (procedure? proc))
      (error "call/1cc: expected procedure" proc))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "call/1cc: expected continuation-prompt-tag" tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (let* ((pframe (car mc))
               (cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
               (cap-barriers (%st-barriers st))
               (cap-handlers (%list-prefix-until (%st-handlers st) (%pf-handlers pframe))))
          (%freeze-mc-frame! pframe)
          (if (and (null? cap-marks) (null? cap-barriers) (null? cap-handlers))
              (##continuation-capture %capture-1cc-noncomp-fast! proc tag)
              (let ((tmpl (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'noncomp #f
                                               '() cap-marks cap-barriers cap-handlers tag)))
                (##continuation-capture %capture-1cc-noncomp! proc tmpl))))
        (let ((found (%mc-find-tail-slow mc tag)))
          (if found
              (let* ((prefix (car found))
                     (pframe (cadr found)))
                (%freeze-mc-frame! pframe)
                (if (pair? prefix) (%freeze-mc-prefix! prefix))
                (let* ((cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
                       (cap-barriers (%st-barriers st))
                       (cap-handlers (%list-prefix-until (%st-handlers st) (%pf-handlers pframe)))
                       (tmpl (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'noncomp #f
                                                  prefix cap-marks cap-barriers cap-handlers tag)))
                  (##continuation-capture %capture-1cc-noncomp! proc tmpl)))
              (begin
                (if (pair? mc) (%freeze-mc-prefix! mc))
                (let ((tmpl (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'raw #f
                                                 mc (%st-marks st) (%st-barriers st)
                                                 (%st-handlers st) #f)))
                  (##continuation-capture %capture-1cc-raw! proc tmpl))))))))

(define (call-with-one-shot-composable-continuation proc
                                                    #!optional
                                                    (tag %default-prompt-tag))
  (if (not (procedure? proc))
      (error "call-with-one-shot-composable-continuation: expected procedure" proc))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "call-with-one-shot-composable-continuation: expected continuation-prompt-tag" tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st))
         (prefix '())
         (pframe #f))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (set! pframe (car mc))
        (let ((found (%mc-find-tail-slow mc tag)))
          (if (not found)
              (error "call-with-one-shot-composable-continuation: no prompt found for tag" tag))
          (set! prefix (car found))
          (set! pframe (cadr found))))
    (if (%barrier-between? (%st-barriers st) (%pf-barriers pframe))
        (error "call-with-one-shot-composable-continuation: cannot capture across continuation barrier" tag))
    (%freeze-mc-frame! pframe)
    (if (pair? prefix) (%freeze-mc-prefix! prefix))
    (let ((cap-marks (%list-prefix-until (%st-marks st) (%pf-marks pframe)))
          (cap-handlers (%list-prefix-until (%st-handlers st) (%pf-handlers pframe))))
      (if (and (null? prefix) (null? cap-marks) (null? cap-handlers))
          (##continuation-capture %capture-1shot-comp-fast! proc)
          (let ((tmpl (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'composable #f
                                           prefix cap-marks '() cap-handlers #f)))
            (##continuation-capture %capture-1shot-comp! proc tmpl))))))

;;;============================================================================
