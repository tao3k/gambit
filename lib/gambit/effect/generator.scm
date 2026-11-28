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
        ;; Winding path: defer st/SUSPENDED commit until dynamic-wind after-thunks finish
        (##continuation-graft
         ck
         (lambda ()
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
           (%gen-state-store-rel! gen %GEN-SUSPENDED)
           val)))))

;; Slow generator yield handler when nested prompts or frozen multi-shot frames exist
(define (%gen-yield-slow-handler gen)
  (lambda (ek val)
    (%gen-sub-k-set! gen ek)
    (%gen-state-store-rel! gen %GEN-SUSPENDED)
    val))

(define (%gen-install-pframe! st gen caller-k)
  (let* ((pf (%gen-pframe gen))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
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
  (let* ((st (%tc-fast))
         (mc (%st-mc st)))
    (if (pair? mc)
        (let* ((top (car mc))
               (rest (cdr mc))
               (ck (%pf-escape-k top))
               (unfrozen (not (%pf-handler top)))
               (mc-cell (%gen-mc-cell gen))
               (h-cell (%gen-h-cell gen)))
          (%st-mc-set! st rest)
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
              (##continuation-return ck #!eof)))
        (begin
          (%gen-sub-k-set! gen #f)
          (%gen-pframe-set! gen #f)
          (%gen-mc-cell-set! gen #f)
          (%gen-h-cell-set! gen #f)
          (%gen-thunk-set! gen #f)
          (%gen-unwind-fn-set! gen #f)
          (%gen-state-store-rel! gen %GEN-DONE)
          #!eof))))

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
  (%gen-install-pframe! (%tc-fast) gen caller-k)
  (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! sub-k #f)))

(define (make-generator thunk)
  (if (not (procedure? thunk))
      (error "make-generator: expected thunk" thunk))
  (let* ((tag (make-continuation-prompt-tag 'generator))
         (gen (%make-gen-raw (%make-gen-state) #f #f #f #f #f thunk #f))
         (unwind-fn
          (lambda (phase)
            (if (eq? phase 'unwind)
                (let ((pf (%gen-pframe gen))
                      (mc-cell (%gen-mc-cell gen))
                      (h-cell (%gen-h-cell gen)))
                  (%gen-sub-k-set! gen #f)
                  (if (and pf (not (%pf-handler pf)))
                      (begin
                        (if (pair? mc-cell) (set-cdr! mc-cell '()))
                        (if (pair? h-cell) (set-cdr! h-cell '()))))
                  (%gen-state-store-rel! gen %GEN-DONE))
                (%gen-cas-state! gen %GEN-DONE %GEN-RUNNING))))
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
                 (resume sk #f)
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
