;;;============================================================================

;;; File: "generator.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Built-in Zero-Allocation Symmetric 4-State Direct-Style Generator
;;; (`make-generator` / `yield`) with cross-call exception propagation and
;;; atomic fault-to-DONE unwinding.

(define yield (make-effect 'yield))

;; Zero-allocation symmetric one-shot generator yield swap receiver (3 total args).
;; When pframe.handler == 'init (Yield #1), caller-k is the base break-frame anchor
;; referenced by sub-k's next_break_link, so it returns via ##continuation-return
;; without reclaiming caller-k; Yields #2..N reclaim caller-k safely in O(1).
(define (%gen-yield-swap-cont! sub-k gen val)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
         (ck (%pf-escape-k pframe))
         (pf-h (%pf-handler pframe))
         (is-init (eq? pf-h 'init))
         (unfrozen (not pf-h)))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv ck)))
        (begin
          (%st-mc-set! st rest)
          (%st-marks-set! st (%pf-marks pframe))
          (%st-barriers-set! st (%pf-barriers pframe))
          (%st-handlers-set! st (%pf-handlers pframe))
          (if unfrozen
              (begin
                (%pf-escape-k-set! pframe #f)
                (%pf-eh-scope-set! pframe #f)
                (%pf-marks-set! pframe '())
                (%pf-barriers-set! pframe '())
                (%pf-handlers-set! pframe '())
                (let ((mc-cell (%gen-mc-cell gen))
                      (h-cell (%gen-h-cell gen)))
                  (if (pair? mc-cell) (set-cdr! mc-cell '()))
                  (if (pair? h-cell) (set-cdr! h-cell '())))))
          (%gen-sub-k-set! gen sub-k)
          ;; Release-store SUSPENDED strictly AFTER all pframe/st/cell updates complete
          (%gen-state-store-rel! gen %GEN-SUSPENDED)
          (if is-init
              (##continuation-return ck val)
              (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! ck val))))
        ;; Winding path: defer st/SUSPENDED commit until dynamic-wind after-thunks finish,
        ;; marking rewind-escape as 'suspending so dynamic-wind guards distinguish yield
        ;; from permanent escape.
        (let ((prev-re (%tc-rewind-escape st)))
          (%tc-rewind-escape-set! st 'suspending)
          (##continuation-graft
           ck
           (lambda ()
             (let ((st2 (%tc-fast)))
               (%tc-rewind-escape-set! st2 prev-re)
               (%st-mc-set! st2 rest)
               (%st-marks-set! st2 (%pf-marks pframe))
               (%st-barriers-set! st2 (%pf-barriers pframe))
               (%st-handlers-set! st2 (%pf-handlers pframe)))
             (if unfrozen
                 (begin
                   (%pf-escape-k-set! pframe #f)
                   (%pf-eh-scope-set! pframe #f)
                   (%pf-marks-set! pframe '())
                   (%pf-barriers-set! pframe '())
                   (%pf-handlers-set! pframe '())
                   (let ((mc-cell (%gen-mc-cell gen))
                         (h-cell (%gen-h-cell gen)))
                     (if (pair? mc-cell) (set-cdr! mc-cell '()))
                     (if (pair? h-cell) (set-cdr! h-cell '())))))
             (%gen-sub-k-set! gen sub-k)
             (%gen-state-store-rel! gen %GEN-SUSPENDED)
             val))))))

;; Slow generator yield handler when nested prompts, continuation marks,
;; frozen multi-shot frames, or 0/multi-value yields are active.
(define (%gen-yield-slow-handler gen)
  (lambda (ek #!optional (v1 %ABSENT) (v2 %ABSENT) #!rest more)
    (%gen-sub-k-set! gen ek)
    (%gen-state-store-rel! gen %GEN-SUSPENDED)
    (cond
      ((eq? v1 %ABSENT) (values))
      ((eq? v2 %ABSENT) v1)
      ((null? more)     (values v1 v2))
      (else             (apply values v1 v2 more)))))

;; Return #t iff every caller dynamic-wind frame that will be unwound when
;; jumping from `cur-dw` to `sub-dw` executes its after-thunk under an active
;; `%mc-eh-trampoline?` (including when zero caller frames are unwound).
(define (%gen-winding-guard-safe? cur-dw sub-dw)
  (let ((cur-lvl (macro-dynwind-level cur-dw)))
    (if (fx= cur-lvl 0)
        #t
        (let align ((sub sub-dw) (sub-lvl (macro-dynwind-level sub-dw)))
          (if (fx> sub-lvl cur-lvl)
              (let ((next-sub (macro-denv-dynwind
                               (##continuation-denv (macro-dynwind-cont sub)))))
                (align next-sub (macro-dynwind-level next-sub)))
              (let walk ((c cur-dw) (cl cur-lvl) (s sub) (sl sub-lvl))
                (cond
                  ((eq? c s) #t)
                  ((fx= cl 0) #t)
                  (else
                   (let* ((cdenv (##continuation-denv (macro-dynwind-cont c)))
                          (eh-cell (macro-denv-exception-handler cdenv)))
                     (if (not (and (pair? eh-cell) (%mc-eh-trampoline? (cdr eh-cell))))
                         #f
                         (let* ((nc (macro-denv-dynwind cdenv))
                                (ncl (macro-dynwind-level nc)))
                           (if (fx= cl sl)
                               (let ((ns (macro-denv-dynwind
                                          (##continuation-denv (macro-dynwind-cont s)))))
                                 (walk nc ncl ns (macro-dynwind-level ns)))
                               (walk nc ncl s sl)))))))))))))

(define (%gen-install-pframe! st gen caller-k eh-scope)
  (let* ((pf (%gen-pframe gen))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st))
         (frame (%gen-frame gen))
         (unwind-fn (%gen-unwind-fn gen)))
    (if (and pf (not (%pf-handler pf)))
        ;; Reuse unfrozen pframe + cons cells in-place (zero heap allocation!)
        (let ((mc-cell (%gen-mc-cell gen))
              (h-cell (%gen-h-cell gen)))
          (%pf-escape-k-set! pf caller-k)
          (%pf-marks-set! pf cur-marks)
          (%pf-barriers-set! pf cur-barriers)
          (%pf-handlers-set! pf cur-handlers)
          (%pf-eh-scope-set! pf eh-scope)
          (%pf-unwind-hook-set! pf unwind-fn)
          (set-car! mc-cell pf)
          (set-cdr! mc-cell cur-mc)
          (set-car! h-cell frame)
          (set-cdr! h-cell cur-handlers)
          (%st-mc-set! st mc-cell)
          (%st-handlers-set! st h-cell))
        ;; Multi-shot froze previous pframe: allocate fresh COW frame + cells
        (let* ((fresh-pf (%make-mc-frame-9 'prompt
                                           (%frame-tag frame)
                                           #f
                                           caller-k
                                           cur-marks
                                           cur-barriers
                                           cur-handlers
                                           eh-scope
                                           unwind-fn))
               (mc-cell (cons fresh-pf cur-mc))
               (h-cell (cons frame cur-handlers)))
          (%gen-pframe-set! gen fresh-pf)
          (%gen-mc-cell-set! gen mc-cell)
          (%gen-h-cell-set! gen h-cell)
          (%st-mc-set! st mc-cell)
          (%st-handlers-set! st h-cell)))))

(define (%gen-finish! gen)
  (let loop ()
    (let* ((st (%tc-fast))
           (mc (%st-mc st)))
      (if (pair? mc)
          (let* ((top (car mc))
                 (rest (cdr mc))
                 (ck (%pf-escape-k top)))
            (%st-mc-set! st rest)
            (if (not ck)
                (let ((uh (%pf-unwind-hook top)))
                  (if (procedure? uh) (uh 'unwind))
                  (loop))
                (let ((unfrozen (not (%pf-handler top)))
                      (mc-cell (%gen-mc-cell gen))
                      (h-cell (%gen-h-cell gen)))
                  (%st-marks-set! st (%pf-marks top))
                  (%st-barriers-set! st (%pf-barriers top))
                  (%st-handlers-set! st (%pf-handlers top))
                  (if unfrozen
                      (begin
                        (%pf-escape-k-set! top #f)
                        (%pf-eh-scope-set! top #f)
                        (%pf-marks-set! top '())
                        (%pf-barriers-set! top '())
                        (%pf-handlers-set! top '())
                        (%pf-unwind-hook-set! top #f)
                        (if (pair? mc-cell) (set-cdr! mc-cell '()))
                        (if (pair? h-cell) (set-cdr! h-cell '()))))
                  (%gen-sub-k-set! gen #f)
                  (%gen-pframe-set! gen #f)
                  (%gen-mc-cell-set! gen #f)
                  (%gen-h-cell-set! gen #f)
                  (%gen-thunk-set! gen #f)
                  (%gen-unwind-fn-set! gen #f)
                  (%gen-state-store-rel! gen %GEN-DONE)
                  (if unfrozen
                      (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! ck #!eof))
                      (##continuation-return ck #!eof)))))
          (begin
            (%gen-sub-k-set! gen #f)
            (%gen-pframe-set! gen #f)
            (%gen-mc-cell-set! gen #f)
            (%gen-h-cell-set! gen #f)
            (%gen-thunk-set! gen #f)
            (%gen-unwind-fn-set! gen #f)
            (%gen-state-store-rel! gen %GEN-DONE)
            #!eof)))))

(define (%gen-start-cont! caller-k gen thunk)
  (let* ((st (%tc-fast))
         (frame (%gen-frame gen))
         (init-pf (%make-mc-frame-9 'prompt
                                    (%frame-tag frame)
                                    'init
                                    caller-k
                                    (%st-marks st)
                                    (%st-barriers st)
                                    (%st-handlers st)
                                    #f
                                    (%gen-unwind-fn gen))))
    (%st-mc-set! st (cons init-pf (%st-mc st)))
    (%st-handlers-set! st (cons frame (%st-handlers st)))
    (thunk)
    (%gen-finish! gen)))

(define (%gen-start-cont-scoped! caller-k gen thunk)
  (let* ((st (%tc-fast))
         (tramp (macro-current-exception-handler))
         (frame (%gen-frame gen))
         (init-pf (%make-mc-frame-9 'prompt
                                    (%frame-tag frame)
                                    'init
                                    caller-k
                                    (%st-marks st)
                                    (%st-barriers st)
                                    (%st-handlers st)
                                    tramp
                                    (%gen-unwind-fn gen))))
    (%st-mc-set! st (cons init-pf (%st-mc st)))
    (%st-handlers-set! st (cons frame (%st-handlers st)))
    (thunk)
    (%gen-finish! gen)))

(define (%gen-resume-swap-cont! caller-k gen sub-k)
  (let* ((st (%tc-fast))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (cur-dw (macro-denv-dynwind (macro-thread-denv (macro-current-thread))))
         (sub-dw (macro-denv-dynwind (##continuation-denv sub-k))))
    (if (eq? cur-dw sub-dw)
        (begin
          (%gen-install-pframe! st gen caller-k eh-scope)
          (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! sub-k #f)))
        (let* ((cur-mc (%st-mc st))
               (cur-marks (%st-marks st))
               (cur-barriers (%st-barriers st))
               (cur-handlers (%st-handlers st))
               (gframe (if (%gen-winding-guard-safe? cur-dw sub-dw)
                           (%make-mc-frame-9 'unwind-guard
                                             #f
                                             #t
                                             #f
                                             cur-marks
                                             cur-barriers
                                             cur-handlers
                                             eh-scope
                                             (%gen-unwind-fn gen))
                           #f)))
          (if gframe
              (%st-mc-set! st (cons gframe cur-mc)))
          (##continuation-graft
           sub-k
           (lambda ()
             (let* ((st2 (%tc-fast))
                    (mc2 (%st-mc st2))
                    (base-mc (if (and gframe (pair? mc2) (eq? (car mc2) gframe))
                                 (cdr mc2)
                                 cur-mc)))
               (%st-mc-set! st2 base-mc)
               (%st-marks-set! st2 cur-marks)
               (%st-barriers-set! st2 cur-barriers)
               (%st-handlers-set! st2 cur-handlers)
               (%gen-install-pframe! st2 gen caller-k eh-scope))
             #f))))))

;; Dedicated zero-closure slow-path generator resumption receiver (<= 4 args).
;; Preserves the generator's unwind hook on the replayed prompt frame so
;; exceptions and outer prompt aborts transition the generator cleanly to DONE,
;; and installs a temporary `'unwind-guard` frame during winding whenever every
;; caller after-thunk runs under an active exception trampoline.
(define (%gen-resume-ec-cont! caller-k gen sk clear?)
  (let* ((st (%tc-fast))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (sub-k (%ec-sub-k sk))
         (prefix (%ec-prefix sk))
         (cap-marks (%ec-marks sk))
         (cap-handlers (%ec-handlers sk))
         (frame (%ec-frame sk))
         (unwind-fn (%gen-unwind-fn gen))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st))
         (cur-dw (macro-denv-dynwind (macro-thread-denv (macro-current-thread))))
         (sub-dw (macro-denv-dynwind (##continuation-denv sub-k)))
         (pframe (%make-mc-frame-9 'prompt
                                   (%frame-tag frame)
                                   #t
                                   caller-k
                                   cur-marks
                                   cur-barriers
                                   cur-handlers
                                   eh-scope
                                   unwind-fn)))
    (if clear? (%clear-consumed-ec! sk))
    (let* ((new-marks (if (null? cap-marks) cur-marks (append cap-marks cur-marks)))
           (base-handlers (cons frame cur-handlers))
           (new-handlers (if (null? cap-handlers) base-handlers (append cap-handlers base-handlers)))
           (rprefix (%mc-rebase-prefix prefix
                                       cap-marks new-marks cur-marks
                                       '() cur-barriers cur-barriers
                                       cap-handlers new-handlers base-handlers)))
      (if (eq? cur-dw sub-dw)
          (begin
            (%st-mc-set! st
                         (if (null? rprefix)
                             (cons pframe cur-mc)
                             (append rprefix (cons pframe cur-mc))))
            (%st-marks-set! st new-marks)
            (%st-barriers-set! st cur-barriers)
            (%st-handlers-set! st new-handlers)
            (if (pair? rprefix) (%mc-run-unwind-hooks! rprefix 'restore))
            (##continuation-return sub-k #f))
          (let ((gframe (if (%gen-winding-guard-safe? cur-dw sub-dw)
                            (%make-mc-frame-9 'unwind-guard
                                              #f
                                              #t
                                              #f
                                              cur-marks
                                              cur-barriers
                                              cur-handlers
                                              eh-scope
                                              unwind-fn)
                            #f)))
            (if gframe
                (%st-mc-set! st (cons gframe cur-mc)))
            (##continuation-graft
             sub-k
             (lambda ()
               (let* ((st2 (%tc-fast))
                      (mc2 (%st-mc st2))
                      (base-mc (if (and gframe (pair? mc2) (eq? (car mc2) gframe))
                                   (cdr mc2)
                                   cur-mc)))
                 (%st-mc-set! st2
                              (if (null? rprefix)
                                  (cons pframe base-mc)
                                  (append rprefix (cons pframe base-mc))))
                 (%st-marks-set! st2 new-marks)
                 (%st-barriers-set! st2 cur-barriers)
                 (%st-handlers-set! st2 new-handlers)
                 (if (pair? rprefix) (%mc-run-unwind-hooks! rprefix 'restore)))
               #f)))))))

(define (%gen-resume-ec! gen sk)
  (let ((prev (%ec-cas-state! sk %EC-ONE-SHOT-LIVE %EC-ONE-SHOT-CONSUMED)))
    (if (not (or (fx= prev %EC-ONE-SHOT-LIVE)
                 (fx= prev %EC-MULTISHOT-COW)))
        (begin
          (%gen-state-store-rel! gen %GEN-DONE)
          (error "one-shot continuation already consumed" sk)))
    (if (fx= prev %EC-MULTISHOT-COW)
        (%freeze-ec! sk))
    (##continuation-capture %gen-resume-ec-cont! gen sk (fx= prev %EC-ONE-SHOT-LIVE))))

(define (make-generator thunk)
  (if (not (procedure? thunk))
      (error "make-generator: expected thunk" thunk))
  (let* ((tag (make-continuation-prompt-tag 'generator))
         (gen (%make-gen-raw (%make-gen-state) #f #f #f #f #f thunk #f))
         (unwind-fn
          (lambda (phase)
            (if (eq? phase 'restore)
                (%gen-cas-state! gen %GEN-DONE %GEN-RUNNING)
                (let ((pf (%gen-pframe gen))
                      (mc-cell (%gen-mc-cell gen))
                      (h-cell (%gen-h-cell gen)))
                  (%gen-sub-k-set! gen #f)
                  (if (and pf (not (%pf-handler pf)))
                      (begin
                        (if (pair? mc-cell) (set-cdr! mc-cell '()))
                        (if (pair? h-cell) (set-cdr! h-cell '()))))
                  (%gen-state-store-rel! gen %GEN-DONE)))))
         (entry (%make-handler-entry yield 'gen gen))
         (frame (%make-handler-frame tag (list entry)))
         (pf (%make-mc-frame-9 'prompt tag #f #f '() '() '() #f unwind-fn))
         (mc-cell (cons pf '()))
         (h-cell (cons frame '())))
    (##unchecked-structure-set! gen frame 4 #f #f)
    (%gen-pframe-set! gen pf)
    (%gen-mc-cell-set! gen mc-cell)
    (%gen-h-cell-set! gen h-cell)
    (%gen-unwind-fn-set! gen unwind-fn)
    (lambda ()
      (let ((prev (%gen-cas-state! gen %GEN-SUSPENDED %GEN-RUNNING)))
        (cond
          ((fx= prev %GEN-SUSPENDED)
           (let ((sk (%gen-sub-k gen)))
             (%gen-sub-k-set! gen #f)
             (if (effect-continuation? sk)
                 (%gen-resume-ec! gen sk)
                 (##continuation-capture %gen-resume-swap-cont! gen sk))))
          ((fx= prev %GEN-DONE)
           #!eof)
          ((fx= prev %GEN-INIT)
           (if (fx= (%gen-cas-state! gen %GEN-INIT %GEN-RUNNING) %GEN-INIT)
               (let ((fn (%gen-thunk gen))
                     (cur-eh (macro-current-exception-handler)))
                 (%gen-thunk-set! gen #f)
                 (if (%mc-eh-trampoline? cur-eh)
                     (##continuation-capture %gen-start-cont! gen fn)
                     (let* ((st (%tc-fast))
                            (cur-denv (macro-thread-denv (macro-current-thread)))
                            (tdenv (%mc-ensure-tramp-denv st cur-denv cur-eh)))
                       (##dynamic-env-bind
                        tdenv
                        (lambda ()
                          (##continuation-capture %gen-start-cont-scoped! gen fn))))))
               (error "generator already running")))
          (else
           (error "generator already running")))))))

;;;============================================================================
