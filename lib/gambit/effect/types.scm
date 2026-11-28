;;;============================================================================

;;; File: "types.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Core types, inline per-thread control-state accessors, inline C23 atomic
;;; word operations, and SATB-watermark-safe one-shot direct return primitive
;;; for `(gambit effect)`.

;; Zero-cross-module fast access to the current thread's SRFI-226 %tc-state.
;; Field layout matches srfi/226/226.scm:
;;   %tc-state: 1=mc, 2=marks, 3=barriers, 4=handlers, 5=rewind-escape, 6=rewind-frame
;;   %mc-frame: 1=kind, 2=tag, 3=handler, 4=escape-k, 5=marks, 6=barriers,
;;              7=handlers, 8=eh-scope, 9=unwind-hook
(define (%tc-fast)
  (let ((st (macro-thread-control-state (##current-thread))))
    (if st st (%tc-current))))

(define (%st-mc st)                   (##unchecked-structure-ref st 1 #f #f))
(define (%st-mc-set! st v)            (##unchecked-structure-set! st v 1 #f #f))
(define (%st-marks st)                (##unchecked-structure-ref st 2 #f #f))
(define (%st-marks-set! st v)         (##unchecked-structure-set! st v 2 #f #f))
(define (%st-barriers st)             (##unchecked-structure-ref st 3 #f #f))
(define (%st-barriers-set! st v)      (##unchecked-structure-set! st v 3 #f #f))
(define (%st-handlers st)             (##unchecked-structure-ref st 4 #f #f))
(define (%st-handlers-set! st v)      (##unchecked-structure-set! st v 4 #f #f))
(define (%st-rewind-frame st)         (##unchecked-structure-ref st 6 #f #f))
(define (%st-rewind-frame-set! st v)  (##unchecked-structure-set! st v 6 #f #f))

(define (%pf-kind pf)                 (##unchecked-structure-ref pf 1 #f #f))
(define (%pf-tag pf)                  (##unchecked-structure-ref pf 2 #f #f))
(define (%pf-handler pf)              (##unchecked-structure-ref pf 3 #f #f))
(define (%pf-handler-set! pf v)       (##unchecked-structure-set! pf v 3 #f #f))
(define (%pf-escape-k pf)             (##unchecked-structure-ref pf 4 #f #f))
(define (%pf-escape-k-set! pf v)      (##unchecked-structure-set! pf v 4 #f #f))
(define (%pf-marks pf)                (##unchecked-structure-ref pf 5 #f #f))
(define (%pf-marks-set! pf v)         (##unchecked-structure-set! pf v 5 #f #f))
(define (%pf-barriers pf)             (##unchecked-structure-ref pf 6 #f #f))
(define (%pf-barriers-set! pf v)      (##unchecked-structure-set! pf v 6 #f #f))
(define (%pf-handlers pf)             (##unchecked-structure-ref pf 7 #f #f))
(define (%pf-handlers-set! pf v)      (##unchecked-structure-set! pf v 7 #f #f))
(define (%pf-eh-scope pf)             (##unchecked-structure-ref pf 8 #f #f))
(define (%pf-eh-scope-set! pf v)      (##unchecked-structure-set! pf v 8 #f #f))
(define (%pf-unwind-hook pf)          (##unchecked-structure-ref pf 9 #f #f))
(define (%pf-unwind-hook-set! pf v)   (##unchecked-structure-set! pf v 9 #f #f))

;;;----------------------------------------------------------------------------
;;; Constants & Effect Identity

(define %EC-ONE-SHOT-LIVE     0)
(define %EC-ONE-SHOT-CONSUMED 1)
(define %EC-MULTISHOT-COW     2)

(define %GEN-INIT      0)
(define %GEN-RUNNING   1)
(define %GEN-SUSPENDED 2)
(define %GEN-DONE      3)

(define %ABSENT (list 'gambit-effect-absent))

(define-type effect
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000001
  constructor: %make-effect
  predicate: effect?
  (name %effect-name))

(define (make-effect #!optional (name 'effect))
  (%make-effect name))

(define (effect-name eff)
  (if (not (effect? eff))
      (error "effect-name: expected effect" eff)
      (%effect-name eff)))

;;;----------------------------------------------------------------------------
;;; Handler Evidence Entries, Frames, Continuations, Capabilities & Generators

(define-type %handler-entry
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000002
  constructor: %make-handler-entry
  predicate: %handler-entry?
  (effect %entry-effect)
  (kind   %entry-kind)   ;; 'tail, 'suspend, or 'gen
  (proc   %entry-proc))  ;; handler procedure (or %generator when kind == 'gen)

(define-type %handler-frame
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000003
  constructor: %make-handler-frame
  predicate: %handler-frame?
  (tag     %frame-tag)     ;; SRFI 226 prompt tag (or #f for pure tail-resumptive)
  (entries %frame-entries)) ;; list of %handler-entry

(define-type effect-continuation
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000004
  constructor: %make-effect-continuation
  predicate: effect-continuation?
  (sub-k    %ec-sub-k    %ec-sub-k-set!)    ;; native Gambit continuation object
  (pframe   %ec-pframe   %ec-pframe-set!)   ;; saved prompt frame for zero-alloc tail-resume
  (prefix   %ec-prefix   %ec-prefix-set!)   ;; metacontinuation prefix frames (usually '())
  (marks    %ec-marks    %ec-marks-set!)    ;; captured continuation marks (usually '())
  (handlers %ec-handlers %ec-handlers-set!) ;; captured inner effect handlers (usually '())
  (frame    %ec-frame    %ec-frame-set!)    ;; deep handler frame to reinstall on resume
  (state    %ec-state))                     ;; C: inline atomic fixnum (0/1/2); non-C: atomic-fxbox

(define-type effect-capability
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000005
  constructor: %make-capability
  predicate: effect-capability?
  (kind  %cap-kind)   ;; 'tail or 'suspend
  (proc  %cap-proc)   ;; handler procedure
  (frame %cap-frame)) ;; %handler-frame (for suspending capabilities) or #f

(define-type %generator
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000006
  constructor: %make-gen-raw
  predicate: %generator?
  (state     %gen-state     %gen-state-set!)     ;; C: inline atomic fixnum (0..3); non-C: atomic-fxbox
  (sub-k     %gen-sub-k     %gen-sub-k-set!)     ;; suspended continuation (raw k or effect-continuation)
  (pframe    %gen-pframe    %gen-pframe-set!)    ;; reusable %mc-frame (reallocated if frozen)
  (frame     %gen-frame)                         ;; %handler-frame for yield
  (mc-cell   %gen-mc-cell   %gen-mc-cell-set!)   ;; reusable cons cell for st.mc when pframe unfrozen
  (h-cell    %gen-h-cell    %gen-h-cell-set!)    ;; reusable cons cell for st.handlers when pframe unfrozen
  (thunk     %gen-thunk     %gen-thunk-set!)     ;; initial generator body (cleared on start)
  (unwind-fn %gen-unwind-fn %gen-unwind-fn-set!)) ;; cached exception-unwind hook (allocated once)

;; Inline C23 seq_cst CAS on structure field 7 of effect-continuation (zero atomic-fxbox alloc)
(define (%make-ec-state)
  (macro-if-c-compiled
   %EC-ONE-SHOT-LIVE
   (make-atomic-fxbox %EC-ONE-SHOT-LIVE)))

(define (%ec-cas-state! ek expected desired)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, &___f[7]),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    ek expected desired)
   (atomic-fxbox-compare-and-swap! (%ec-state ek) expected desired)))

;; Inline C23 atomic state ops on structure field 1 of %generator
(define (%make-gen-state)
  (macro-if-c-compiled
   %GEN-INIT
   (make-atomic-fxbox %GEN-INIT)))

(define (%gen-cas-state! gen expected desired)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___CAST(___SCMOBJ,
       ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, &___f[1]),
                          ___CAST(___WORD, ___ARG2),
                          ___CAST(___WORD, ___ARG3), 4));"
    gen expected desired)
   (atomic-fxbox-compare-and-swap! (%gen-state gen) expected desired)))

(define (%gen-state-store-rel! gen val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___atomic_word_store(___CAST(___VOLATILE ___WORD*, &___f[1]),
                          ___CAST(___WORD, ___ARG2), 2);
     ___RESULT = ___VOID;"
    gen val)
   (atomic-fxbox-set! (%gen-state gen) val)))

;;;----------------------------------------------------------------------------
;;; Same-Denv SATB-Safe One-Shot Direct Continuation Return

(define (%return-oneshot-same-denv! cont val)
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
