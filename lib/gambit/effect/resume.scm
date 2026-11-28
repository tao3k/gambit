;;;============================================================================

;;; File: "resume.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; One-shot and multi-shot effect continuation resumption (`resume`,
;;; `resume-multishot`) with idempotent COW freezing, frozen non-tail replay
;;; anchors, and exception-unwind scope preservation.

(define (%freeze-ec! ek)
  (let ((pf (%ec-pframe ek)))
    (if (and pf (not (%pf-handler pf)))
        (%pf-handler-set! pf #t)))
  (let ((pr (%ec-prefix ek)))
    (if (pair? pr) (%freeze-mc-prefix! pr))))

(define (%clear-consumed-ec! ek)
  (%ec-sub-k-set! ek #f)
  (%ec-pframe-set! ek #f)
  (%ec-prefix-set! ek '())
  (%ec-marks-set! ek '())
  (%ec-handlers-set! ek '())
  (%ec-frame-set! ek #f))

;; Non-tail one-shot replay receiver (<= 4 args).
;; Creates a frozen prompt frame (`handler = #t`) so caller-k is never reclaimed
;; in-place if `%return-oneshot-same-denv!` falls back to `##continuation-return`
;; and splices `sub-k` onto caller-k's break chain; still reclaims `sub-k` in O(1)
;; when `denv` matches. When crossing `dynamic-wind` frames (including
;; `call-with-continuation-barrier`), defers control-state commit to a
;; post-unwind landing thunk via `##continuation-graft`.
(define (%resume-nontail-oneshot-cont! caller-k sub-k frame val)
  (let* ((st (%tc-fast))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   (%frame-tag frame)
                                   #t
                                   caller-k
                                   cur-marks
                                   cur-barriers
                                   cur-handlers
                                   eh-scope
                                   'replay)))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv sub-k)))
        (begin
          (%st-mc-set! st (cons pframe cur-mc))
          (%st-handlers-set! st (cons frame cur-handlers))
          (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! sub-k val)))
        (##continuation-graft
         sub-k
         (lambda ()
           (let ((st2 (%tc-fast)))
             (%st-mc-set! st2 (cons pframe cur-mc))
             (%st-marks-set! st2 cur-marks)
             (%st-barriers-set! st2 cur-barriers)
             (%st-handlers-set! st2 (cons frame cur-handlers)))
           val)))))

(define (%resume-nontail-oneshot! sub-k val)
  (let* ((st (%tc-fast))
         (frame (%st-rewind-frame st))
         (saved-mc (cdr (%st-mc st)))
         (saved-handlers (cdr (%st-handlers st))))
    (%st-rewind-frame-set! st #f)
    (%st-mc-set! st saved-mc)
    (%st-handlers-set! st saved-handlers)
    (##continuation-capture %resume-nontail-oneshot-cont! sub-k frame val)))

;; Zero-frame tail-called leaf: attempts SATB-safe in-place rewind / full-span
;; reclaim when in exact handler tail position and `denv` matches.
(define (%tail-resume-dispatch! sub-k escape-k val)
  (##declare (not inline) (not interrupts-enabled))
  (macro-if-c-compiled
   (if (##c-code
        "___SCMOBJ ___sub_k = ___ARG1;
         ___SCMOBJ ___esc_k = ___ARG2;
         ___SCMOBJ ___val   = ___ARG3;
         if (___fp == ___ps->context->stack_break &&
             ___R0 == ___ps->handler_break &&
             ___TESTTYPE(___esc_k, ___tCONTINUATION) &&
             ___FP_STK(___fp, -___BREAK_FRAME_NEXT) == ___CONTINUATION_FRAME_FIELD(___esc_k) &&
             ___TESTTYPE(___sub_k, ___tCONTINUATION) &&
             ___THREAD_DENV_FIELD(___CURRENTTHREAD) == ___CONTINUATION_DENV_FIELD(___sub_k)) {
           ___WORD ___ra;
           ___WORD *___new_fp;
           if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___sub_k, &___ra, &___new_fp)) {
             ___SET_FP(___new_fp)
             ___SET_R1(___val)
#if ___NB_GVM_REGS > 2
             ___SET_R2(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 3
             ___SET_R3(___FIX(0L))
#endif
#if ___NB_GVM_REGS > 4
             ___SET_R4(___FIX(0L))
#endif
             ___JUMPEXTPRM(___NOTHING, ___ra)
           }
         }
         ___RESULT = ___FAL;"
        sub-k escape-k val)
       (##void)
       (%resume-nontail-oneshot! sub-k val))
   (%resume-nontail-oneshot! sub-k val)))

;; Zero-closure multi-arg capture receivers for general / multi-shot resume (<= 4 args).
;; Transactionally defers control-state commit to a post-unwind landing thunk
;; via `##continuation-graft` when crossing `dynamic-wind` frames.
(define (%resume-checked-1! caller-k ek v1 clear?)
  (let* ((st (%tc-fast))
         (cur-eh (macro-current-exception-handler))
         (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
         (sub-k (%ec-sub-k ek))
         (prefix (%ec-prefix ek))
         (cap-marks (%ec-marks ek))
         (cap-handlers (%ec-handlers ek))
         (frame (%ec-frame ek))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   (%frame-tag frame)
                                   #t
                                   caller-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers
                                   eh-scope
                                   'replay)))
    (if clear? (%clear-consumed-ec! ek))
    (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
             (macro-denv-dynwind (##continuation-denv sub-k)))
        (begin
          (%st-mc-set! st
                       (if (null? prefix)
                           (cons pframe saved-mc)
                           (append prefix (cons pframe saved-mc))))
          (%st-marks-set! st
                          (if (null? cap-marks)
                              saved-marks
                              (append cap-marks saved-marks)))
          (%st-barriers-set! st saved-barriers)
          (%st-handlers-set! st
                             (let ((base (cons frame saved-handlers)))
                               (if (null? cap-handlers)
                                   base
                                   (append cap-handlers base))))
          (if (eq? v1 %ABSENT)
              (##continuation-return sub-k)
              (##continuation-return sub-k v1)))
        (##continuation-graft
         sub-k
         (lambda ()
           (let ((st2 (%tc-fast)))
             (%st-mc-set! st2
                          (if (null? prefix)
                              (cons pframe saved-mc)
                              (append prefix (cons pframe saved-mc))))
             (%st-marks-set! st2
                             (if (null? cap-marks)
                                 saved-marks
                                 (append cap-marks saved-marks)))
             (%st-barriers-set! st2 saved-barriers)
             (%st-handlers-set! st2
                                (let ((base (cons frame saved-handlers)))
                                  (if (null? cap-handlers)
                                      base
                                      (append cap-handlers base)))))
           (if (eq? v1 %ABSENT) (values) v1))))))

(define (%resume-checked ek v1 v2 more clear?)
  (if (eq? v2 %ABSENT)
      (##continuation-capture %resume-checked-1! ek v1 clear?)
      (##continuation-capture
       (lambda (caller-k)
         (let* ((st (%tc-fast))
                (cur-eh (macro-current-exception-handler))
                (eh-scope (if (%mc-eh-trampoline? cur-eh) #f cur-eh))
                (sub-k (%ec-sub-k ek))
                (prefix (%ec-prefix ek))
                (cap-marks (%ec-marks ek))
                (cap-handlers (%ec-handlers ek))
                (frame (%ec-frame ek))
                (saved-mc (%st-mc st))
                (saved-marks (%st-marks st))
                (saved-barriers (%st-barriers st))
                (saved-handlers (%st-handlers st))
                (pframe (%make-mc-frame-9 'prompt
                                          (%frame-tag frame)
                                          #t
                                          caller-k
                                          saved-marks
                                          saved-barriers
                                          saved-handlers
                                          eh-scope
                                          'replay)))
           (if clear? (%clear-consumed-ec! ek))
           (if (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
                    (macro-denv-dynwind (##continuation-denv sub-k)))
               (begin
                 (%st-mc-set! st
                              (if (null? prefix)
                                  (cons pframe saved-mc)
                                  (append prefix (cons pframe saved-mc))))
                 (%st-marks-set! st
                                 (if (null? cap-marks)
                                     saved-marks
                                     (append cap-marks saved-marks)))
                 (%st-barriers-set! st saved-barriers)
                 (%st-handlers-set! st
                                    (let ((base (cons frame saved-handlers)))
                                      (if (null? cap-handlers)
                                          base
                                          (append cap-handlers base))))
                 (if (null? more)
                     (##continuation-return sub-k v1 v2)
                     (##apply ##continuation-return sub-k v1 v2 more)))
               (##continuation-graft
                sub-k
                (lambda ()
                  (let ((st2 (%tc-fast)))
                    (%st-mc-set! st2
                                 (if (null? prefix)
                                     (cons pframe saved-mc)
                                     (append prefix (cons pframe saved-mc))))
                    (%st-marks-set! st2
                                    (if (null? cap-marks)
                                        saved-marks
                                        (append cap-marks saved-marks)))
                    (%st-barriers-set! st2 saved-barriers)
                    (%st-handlers-set! st2
                                       (let ((base (cons frame saved-handlers)))
                                         (if (null? cap-handlers)
                                             base
                                             (append cap-handlers base)))))
                  (if (null? more)
                      (values v1 v2)
                      (apply values v1 v2 more))))))))))

(define (resume ek
                #!optional
                (v1 %ABSENT)
                (v2 %ABSENT)
                #!rest
                more)
  (if (not (effect-continuation? ek))
      (error "resume: expected effect-continuation" ek))
  (let ((prev (%ec-cas-state! ek %EC-ONE-SHOT-LIVE %EC-ONE-SHOT-CONSUMED)))
    (if (not (or (fx= prev %EC-ONE-SHOT-LIVE)
                 (fx= prev %EC-MULTISHOT-COW)))
        (error "one-shot continuation already consumed" ek))
    ;; One-shot fast path (1-arg common case, empty prefix/marks/handlers)
    (if (and (fx= prev %EC-ONE-SHOT-LIVE)
             (not (eq? v1 %ABSENT))
             (eq? v2 %ABSENT)
             (null? (%ec-prefix ek))
             (null? (%ec-marks ek))
             (null? (%ec-handlers ek)))
        (let* ((sub-k (%ec-sub-k ek))
               (pframe (%ec-pframe ek))
               (frame (%ec-frame ek))
               (st (%tc-fast)))
          ;; Sever all heap references to the stack-allocated sub-k before reclaim
          (%ec-sub-k-set! ek #f)
          (%ec-pframe-set! ek #f)
          (%ec-frame-set! ek #f)
          ;; Speculatively reinstall pframe (reusing existing object, zero alloc)
          (%st-mc-set! st (cons pframe (%st-mc st)))
          (%st-handlers-set! st (cons frame (%st-handlers st)))
          (%st-rewind-frame-set! st frame)
          (let () (declare (inlining-limit 0)) (%tail-resume-dispatch! sub-k (%pf-escape-k pframe) v1)))
        (begin
          ;; If racing with concurrent `resume-multishot`, idempotently freeze
          ;; pframe/prefix before entering `%resume-checked`.
          (if (fx= prev %EC-MULTISHOT-COW)
              (%freeze-ec! ek))
          (%resume-checked ek v1 v2 more (fx= prev %EC-ONE-SHOT-LIVE))))))

(define (resume-multishot ek
                          #!optional
                          (v1 %ABSENT)
                          (v2 %ABSENT)
                          #!rest
                          more)
  (if (not (effect-continuation? ek))
      (error "resume-multishot: expected effect-continuation" ek))
  (let ((prev (%ec-cas-state! ek %EC-ONE-SHOT-LIVE %EC-MULTISHOT-COW)))
    (if (not (or (fx= prev %EC-ONE-SHOT-LIVE)
                 (fx= prev %EC-MULTISHOT-COW)))
        (error "cannot promote consumed one-shot continuation" ek))
    (%freeze-ec! ek)
    (%resume-checked ek v1 v2 more #f)))

;;;============================================================================
