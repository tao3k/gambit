;;;============================================================================

;;; File: "state.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Core control-state types, prompt tags, metacontinuation frames, lock-free
;;; one-shot continuation cells, inline C23 atomic operations, and SATB-safe
;;; in-place stack continuation reclamation for `(srfi 226)`.

;;;----------------------------------------------------------------------------
;;; Atomic One-Shot Continuation States & Sentinels

(define %CONT-ONE-SHOT-LIVE     0)
(define %CONT-ONE-SHOT-CONSUMED 1)
(define %CONT-MULTISHOT-COW     2)

(define %ABSENT (list 'srfi-226-absent))
(define %DEFAULT-PROMPT-HANDLER (list 'srfi-226-default-handler))
(define %FROZEN-DEFAULT-PROMPT-HANDLER (list 'srfi-226-frozen-default-handler))

;;;----------------------------------------------------------------------------
;;; Prompt Tags

(define-type continuation-prompt-tag
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000001
  constructor: %make-prompt-tag
  predicate: continuation-prompt-tag?
  (name %prompt-tag-name))

(define (make-continuation-prompt-tag #!optional (name 'prompt))
  (%make-prompt-tag name))

(define %default-prompt-tag (%make-prompt-tag 'default))

(define (default-continuation-prompt-tag)
  %default-prompt-tag)

;;;----------------------------------------------------------------------------
;;; Metacontinuation Frames & Native Per-Thread Control State

(define-type %mc-frame
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000002
  constructor: %make-mc-frame-9
  predicate: %mc-frame?
  (kind        %mc-frame-kind)     ;; 'prompt or 'underflow
  (tag         %mc-frame-tag)      ;; prompt-tag (or #f for underflow)
  (handler     %mc-frame-handler     %mc-frame-handler-set!)
  (escape-k    %mc-frame-escape-k    %mc-frame-escape-k-set!)
  (marks       %mc-frame-marks)
  (barriers    %mc-frame-barriers)
  (handlers    %mc-frame-handlers)
  (eh-scope    %mc-frame-eh-scope    %mc-frame-eh-scope-set!)
  (unwind-hook %mc-frame-unwind-hook %mc-frame-unwind-hook-set!))

(define (%make-mc-frame kind tag handler escape-k marks barriers handlers
                        #!optional (eh-scope #f) (unwind-hook #f))
  (%make-mc-frame-9 kind tag handler escape-k marks barriers handlers eh-scope unwind-hook))

(define-type %tc-state
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000004
  constructor: %make-tc-state
  predicate: %tc-state?
  (mc            %tc-mc            %tc-mc-set!)
  (marks         %tc-marks         %tc-marks-set!)
  (barriers      %tc-barriers      %tc-barriers-set!)
  (handlers      %tc-handlers      %tc-handlers-set!)
  (rewind-escape %tc-rewind-escape %tc-rewind-escape-set!)
  (rewind-frame  %tc-rewind-frame  %tc-rewind-frame-set!)
  (eh-outer-denv %tc-eh-outer-denv %tc-eh-outer-denv-set!)
  (eh-outer-proc %tc-eh-outer-proc %tc-eh-outer-proc-set!)
  (eh-tramp-denv %tc-eh-tramp-denv %tc-eh-tramp-denv-set!)
  (eh-tramp-proc %tc-eh-tramp-proc %tc-eh-tramp-proc-set!))

(define (%st-mc st)                    (##unchecked-structure-ref st 1 #f #f))
(define (%st-mc-set! st v)             (##unchecked-structure-set! st v 1 #f #f))
(define (%st-marks st)                 (##unchecked-structure-ref st 2 #f #f))
(define (%st-marks-set! st v)          (##unchecked-structure-set! st v 2 #f #f))
(define (%st-barriers st)              (##unchecked-structure-ref st 3 #f #f))
(define (%st-barriers-set! st v)       (##unchecked-structure-set! st v 3 #f #f))
(define (%st-handlers st)              (##unchecked-structure-ref st 4 #f #f))
(define (%st-handlers-set! st v)       (##unchecked-structure-set! st v 4 #f #f))
(define (%st-eh-outer-denv st)         (##unchecked-structure-ref st 7 #f #f))
(define (%st-eh-outer-denv-set! st v)  (##unchecked-structure-set! st v 7 #f #f))
(define (%st-eh-outer-proc st)         (##unchecked-structure-ref st 8 #f #f))
(define (%st-eh-outer-proc-set! st v)  (##unchecked-structure-set! st v 8 #f #f))
(define (%st-eh-tramp-denv st)         (##unchecked-structure-ref st 9 #f #f))
(define (%st-eh-tramp-denv-set! st v)  (##unchecked-structure-set! st v 9 #f #f))
(define (%st-eh-tramp-proc st)         (##unchecked-structure-ref st 10 #f #f))
(define (%st-eh-tramp-proc-set! st v)  (##unchecked-structure-set! st v 10 #f #f))

(define (%pf-kind pf)                  (##unchecked-structure-ref pf 1 #f #f))
(define (%pf-tag pf)                   (##unchecked-structure-ref pf 2 #f #f))
(define (%pf-handler pf)               (##unchecked-structure-ref pf 3 #f #f))
(define (%pf-handler-set! pf v)        (##unchecked-structure-set! pf v 3 #f #f))
(define (%pf-escape-k pf)              (##unchecked-structure-ref pf 4 #f #f))
(define (%pf-escape-k-set! pf v)       (##unchecked-structure-set! pf v 4 #f #f))
(define (%pf-marks pf)                 (##unchecked-structure-ref pf 5 #f #f))
(define (%pf-barriers pf)              (##unchecked-structure-ref pf 6 #f #f))
(define (%pf-handlers pf)              (##unchecked-structure-ref pf 7 #f #f))
(define (%pf-eh-scope pf)              (##unchecked-structure-ref pf 8 #f #f))
(define (%pf-eh-scope-set! pf v)       (##unchecked-structure-set! pf v 8 #f #f))
(define (%pf-unwind-hook pf)           (##unchecked-structure-ref pf 9 #f #f))
(define (%pf-unwind-hook-set! pf v)    (##unchecked-structure-set! pf v 9 #f #f))

(define (%tc-current)
  (let ((st (macro-thread-control-state (macro-current-thread))))
    (if st
        st
        (let ((fresh (%make-tc-state '() '() '() '() #f #f #f #f #f #f)))
          (macro-thread-control-state-set! (macro-current-thread) fresh)
          fresh))))

(define (%mc-same-dynwind? cont)
  (eq? (macro-denv-dynwind (macro-thread-denv (macro-current-thread)))
       (macro-denv-dynwind (##continuation-denv cont))))

;;;----------------------------------------------------------------------------
;;; Continuation Mark Sets

(define-type continuation-mark-set
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000003
  constructor: %make-mark-set
  predicate: continuation-mark-set?
  (frames %mark-set-frames))

;;;----------------------------------------------------------------------------
;;; Lock-Free One-Shot & Multi-Shot Continuation Cell

(define-type %one-shot-cell
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000005
  constructor: %make-one-shot-cell
  predicate: %one-shot-cell?
  (state    %osc-state)     ;; slot 1: atomic fixnum 0=LIVE, 1=CONSUMED, 2=MULTISHOT_COW
  (kind     %osc-kind)      ;; slot 2: 'composable, 'noncomp, or 'raw
  (sub-k    %osc-sub-k)     ;; slot 3: native Gambit continuation
  (prefix   %osc-prefix)    ;; slot 4: captured mc prefix
  (marks    %osc-marks)     ;; slot 5: captured continuation marks
  (barriers %osc-barriers)  ;; slot 6: captured barriers
  (handlers %osc-handlers)  ;; slot 7: captured effect handlers
  (tag      %osc-tag))      ;; slot 8: target prompt tag (for 'noncomp)

(define (%osc-cas-state! cell expected desired)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, &___f[1]),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    cell expected desired)
   (let ((prev (##unchecked-structure-ref cell 1 #f #f)))
     (if (fx= prev expected)
         (##unchecked-structure-set! cell desired 1 #f #f))
     prev)))

(define (%osc-load-state cell)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___CAST(___SCMOBJ,
       __atomic_load_n(&___f[1], __ATOMIC_ACQUIRE));"
    cell)
   (##unchecked-structure-ref cell 1 #f #f)))

(define (%osc-kind-fast c)      (##unchecked-structure-ref c 2 #f #f))
(define (%osc-sub-k-fast c)     (##unchecked-structure-ref c 3 #f #f))
(define (%osc-sub-k-set! c v)   (##unchecked-structure-set! c v 3 #f #f))
(define (%osc-prefix-fast c)    (##unchecked-structure-ref c 4 #f #f))
(define (%osc-prefix-set! c v)  (##unchecked-structure-set! c v 4 #f #f))
(define (%osc-marks-fast c)     (##unchecked-structure-ref c 5 #f #f))
(define (%osc-marks-set! c v)   (##unchecked-structure-set! c v 5 #f #f))
(define (%osc-barriers-fast c)  (##unchecked-structure-ref c 6 #f #f))
(define (%osc-barriers-set! c v)(##unchecked-structure-set! c v 6 #f #f))
(define (%osc-handlers-fast c)  (##unchecked-structure-ref c 7 #f #f))
(define (%osc-handlers-set! c v)(##unchecked-structure-set! c v 7 #f #f))
(define (%osc-tag-fast c)       (##unchecked-structure-ref c 8 #f #f))

;; Clear all heap references from an exclusively consumed one-shot cell so
;; retaining the consumed closure cannot pin captured stack frames or marks.
(define (%osc-clear-consumed! c)
  (%osc-sub-k-set! c #f)
  (%osc-prefix-set! c '())
  (%osc-marks-set! c '())
  (%osc-barriers-set! c '())
  (%osc-handlers-set! c '()))

;;;----------------------------------------------------------------------------
;;; Metacontinuation Frame Freezing & SATB-Safe One-Shot Direct Return

(define (%freeze-mc-frame! f)
  (let ((h (%pf-handler f)))
    (cond
      ((not h)
       (%pf-handler-set! f #t))
      ((eq? h %DEFAULT-PROMPT-HANDLER)
       (%pf-handler-set! f %FROZEN-DEFAULT-PROMPT-HANDLER)))))

(define (%freeze-mc-prefix! prefix)
  (let loop ((fs prefix))
    (if (pair? fs)
        (begin
          (%freeze-mc-frame! (car fs))
          (loop (cdr fs)))))
  prefix)

(define (%mc-try-reclaim-return! pframe ek val)
  (##declare (not inline) (not interrupts-enabled))
  (macro-if-c-compiled
   (##c-code
    "___SCMOBJ ___pf = ___ARG1;
     ___SCMOBJ ___cont = ___ARG2;
     ___SCMOBJ ___val = ___ARG3;
     if (___TESTTYPE(___cont, ___tCONTINUATION)) {
       ___SCMOBJ ___thr    = ___CURRENTTHREAD;
       ___SCMOBJ ___cur_d  = ___THREAD_DENV_FIELD(___thr);
       ___SCMOBJ ___cont_d = ___CONTINUATION_DENV_FIELD(___cont);
       if (___cur_d == ___cont_d ||
           (___VECTORREF(___cur_d, ___FIX(1L)) == ___VECTORREF(___cont_d, ___FIX(1L)) &&
            ___VECTORREF(___cur_d, ___FIX(0L)) == ___VECTORREF(___cont_d, ___FIX(0L)) &&
            ___VECTORREF(___cur_d, ___FIX(2L)) == ___VECTORREF(___cont_d, ___FIX(2L)))) {
         ___WORD ___ra;
         ___WORD *___new_fp;
         if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___cont, &___ra, &___new_fp)) {
           if (___cur_d != ___cont_d) {
             ___GC_WRITE_BARRIER(___ps, ___thr, &___THREAD_DENV_FIELD(___thr), ___cont_d);
             ___WORD_STORE_RELAXED(&___THREAD_DENV_FIELD(___thr), ___cont_d);
           }
           ___BODY_AS(___pf, ___tSTRUCTURE)[4] = ___FAL;
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
     }
     ___RESULT = ___FAL;"
    pframe ek val)
   #f))

(define (%return-oneshot-same-dynwind! cont val)
  (##declare (not inline) (not interrupts-enabled))
  (macro-if-c-compiled
   (if (##c-code
        "___SCMOBJ ___cont = ___ARG1;
         ___SCMOBJ ___val  = ___ARG2;
         if (___TESTTYPE(___cont, ___tCONTINUATION)) {
           ___SCMOBJ ___thr    = ___CURRENTTHREAD;
           ___SCMOBJ ___cur_d  = ___THREAD_DENV_FIELD(___thr);
           ___SCMOBJ ___cont_d = ___CONTINUATION_DENV_FIELD(___cont);
           if (___cur_d == ___cont_d ||
               (___VECTORREF(___cur_d, ___FIX(1L)) == ___VECTORREF(___cont_d, ___FIX(1L)) &&
                ___VECTORREF(___cur_d, ___FIX(0L)) == ___VECTORREF(___cont_d, ___FIX(0L)) &&
                ___VECTORREF(___cur_d, ___FIX(2L)) == ___VECTORREF(___cont_d, ___FIX(2L)))) {
             ___WORD ___ra;
             ___WORD *___new_fp;
             if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___cont, &___ra, &___new_fp)) {
               if (___cur_d != ___cont_d) {
                 ___GC_WRITE_BARRIER(___ps, ___thr, &___THREAD_DENV_FIELD(___thr), ___cont_d);
                 ___WORD_STORE_RELAXED(&___THREAD_DENV_FIELD(___thr), ___cont_d);
               }
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
         }
         ___RESULT = ___FAL;"
        cont val)
       (##void)
       (##continuation-return cont val))
   (##continuation-return cont val)))

;;;============================================================================
