;;;============================================================================

;;; File: "effect.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit effect) — Direct-Style Algebraic Effect Handlers
;;;
;;; Built directly on Gambit's native zero-copy continuation primitives
;;; (##continuation-capture, ##continuation-graft, ##continuation-return,
;;; ___try_return_oneshot_fiber_cont), inline per-thread control-state access
;;; (macro-thread-control-state), and inline C23 atomic word CAS:
;;;   1. Koka ICFP '21 Tail-Resumptive Fast Path (`tail:`): zero prompt, zero
;;;      capture, zero cross-module lookup, inline thread-slot handler dispatch,
;;;      and zero-rest-arg 0/1/2-arg specialization.
;;;   2. Zero-Closure Inline-CAS Suspending Effects: `perform` / `perform-cap`
;;;      use zero-closure multi-arg ##continuation-capture and an inline atomic
;;;      state word inside `effect-continuation` (zero atomic-fxbox allocation).
;;;      Both tail and non-tail one-shot `resume` consume the captured span via
;;;      SATB-watermark-safe `___try_return_oneshot_fiber_cont` when `denv`
;;;      matches, falling back to full winding `##continuation-return` otherwise.
;;;   3. Lazy Multi-Shot Promotion: `resume-multishot` atomically transitions
;;;      ONE_SHOT_LIVE (0) -> MULTISHOT_COW (2) and freezes captured prompt
;;;      frames prior to invocation.
;;;   4. Zero-Allocation Symmetric 4-State Direct-Style Generators (`make-generator`
;;;      / `yield`): atomic INIT/RUNNING/SUSPENDED/DONE transitions with reusable
;;;      unfrozen prompt frame and symmetric one-shot continuation swaps.

(##supply-module gambit/effect)

(##namespace ("gambit/effect#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  with-exception-catcher
  raise
  error))
(##include "~~lib/srfi/226/226#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##include "effect#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (inlining-limit 400)
  (block))

;;;----------------------------------------------------------------------------
;;; Target Helper & Inline Cross-Module Control-State / Prompt-Frame Accessors

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

;; Zero-cross-module fast access to the current thread's SRFI-226 %tc-state.
;; Field layout matches srfi/226/226.scm:
;;   %tc-state: 1=mc, 2=marks, 3=barriers, 4=handlers, 5=rewind-escape, 6=rewind-frame
;;   %mc-frame: 1=kind, 2=tag, 3=handler, 4=escape-k, 5=marks, 6=barriers, 7=handlers
(define (%tc-fast)
  (let ((st (macro-thread-control-state (##current-thread))))
    (if st st (%tc-current))))

(define (%st-mc st)               (##unchecked-structure-ref st 1 #f #f))
(define (%st-mc-set! st v)        (##unchecked-structure-set! st v 1 #f #f))
(define (%st-marks st)            (##unchecked-structure-ref st 2 #f #f))
(define (%st-marks-set! st v)     (##unchecked-structure-set! st v 2 #f #f))
(define (%st-barriers st)         (##unchecked-structure-ref st 3 #f #f))
(define (%st-barriers-set! st v)  (##unchecked-structure-set! st v 3 #f #f))
(define (%st-handlers st)         (##unchecked-structure-ref st 4 #f #f))
(define (%st-handlers-set! st v)  (##unchecked-structure-set! st v 4 #f #f))
(define (%st-rewind-frame st)     (##unchecked-structure-ref st 6 #f #f))
(define (%st-rewind-frame-set! st v) (##unchecked-structure-set! st v 6 #f #f))

(define (%pf-kind pf)             (##unchecked-structure-ref pf 1 #f #f))
(define (%pf-tag pf)              (##unchecked-structure-ref pf 2 #f #f))
(define (%pf-handler pf)          (##unchecked-structure-ref pf 3 #f #f))
(define (%pf-handler-set! pf v)   (##unchecked-structure-set! pf v 3 #f #f))
(define (%pf-escape-k pf)         (##unchecked-structure-ref pf 4 #f #f))
(define (%pf-escape-k-set! pf v)  (##unchecked-structure-set! pf v 4 #f #f))
(define (%pf-marks pf)            (##unchecked-structure-ref pf 5 #f #f))
(define (%pf-marks-set! pf v)     (##unchecked-structure-set! pf v 5 #f #f))
(define (%pf-barriers pf)         (##unchecked-structure-ref pf 6 #f #f))
(define (%pf-barriers-set! pf v)  (##unchecked-structure-set! pf v 6 #f #f))
(define (%pf-handlers pf)         (##unchecked-structure-ref pf 7 #f #f))
(define (%pf-handlers-set! pf v)  (##unchecked-structure-set! pf v 7 #f #f))

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
  (name effect-name))

(define (make-effect #!optional (name 'effect))
  (%make-effect name))

;;;----------------------------------------------------------------------------
;;; Handler Evidence Entries, Frames, Continuations & Direct Generators

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
  (prefix   %ec-prefix)                     ;; metacontinuation prefix frames (usually '())
  (marks    %ec-marks)                      ;; captured continuation marks (usually '())
  (handlers %ec-handlers)                   ;; captured inner effect handlers (usually '())
  (frame    %ec-frame    %ec-frame-set!)    ;; deep handler frame to reinstall on resume
  (state    %ec-state))                     ;; C: inline atomic fixnum (0/1/2); non-C: atomic-fxbox

(define-type %generator
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000006
  constructor: %make-gen-raw
  predicate: %generator?
  (state    %gen-state    %gen-state-set!)    ;; C: inline atomic fixnum (0..3); non-C: atomic-fxbox
  (sub-k    %gen-sub-k    %gen-sub-k-set!)    ;; suspended continuation (raw k or effect-continuation)
  (pframe   %gen-pframe   %gen-pframe-set!)   ;; reusable %mc-frame (reallocated if frozen)
  (frame    %gen-frame)                       ;; %handler-frame for yield
  (mc-cell  %gen-mc-cell  %gen-mc-cell-set!)  ;; reusable cons cell for st.mc when pframe unfrozen
  (h-cell   %gen-h-cell   %gen-h-cell-set!)   ;; reusable cons cell for st.handlers when pframe unfrozen
  (thunk    %gen-thunk    %gen-thunk-set!))   ;; initial generator body (cleared on start)

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
;;;
;;; Reclaims the linearly-owned one-shot continuation span in O(1) via
;;; ___try_return_oneshot_fiber_cont (with ZGC Stack Watermark shading when
;;; SATB is active) whenever `cur_denv == cont_denv`, and falls back to full
;;; winding ##continuation-return whenever dynamic-wind / parameterize changed
;;; `denv` or the span exceeds 4 KiB / is aliased.

(define (%return-oneshot-same-denv! cont val)
  (##declare (not inline) (not interrupts-enabled))
  (macro-if-c-compiled
   (if (##c-code
        "___SCMOBJ ___cont = ___ARG1;
         ___SCMOBJ ___val  = ___ARG2;
         if (___TESTTYPE(___cont, ___tCONTINUATION) &&
             ___THREAD_DENV_FIELD(___CURRENTTHREAD) == ___CONTINUATION_DENV_FIELD(___cont)) {
           ___WORD ___ra;
           ___WORD *___new_fp;
           if (___EXT(___try_return_oneshot_fiber_cont)(___ps, ___cont, &___ra, &___new_fp)) {
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
        cont val)
       (##void)
       (##continuation-return cont val))
   (##continuation-return cont val)))

;;;----------------------------------------------------------------------------
;;; Handler Lookup & Installation

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

;; Zero-closure multi-arg capture receiver for suspending with-handler (<= 4 args)
(define (%install-handler-cont! escape-k frame return-fn thunk)
  (let* ((st (%tc-fast))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame 'prompt
                                 tag
                                 #f
                                 escape-k
                                 saved-marks
                                 saved-barriers
                                 saved-handlers)))
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
      (let* ((tag (make-continuation-prompt-tag 'effect-handler))
             (frame (%make-handler-frame tag entries)))
        (##continuation-capture %install-handler-cont! frame return-fn thunk))))

;; Functional API:
;; (call-with-effect-handler '((tail: eff proc) (eff proc)) return-fn thunk)
(define (call-with-effect-handler specs return-fn thunk)
  (let ((entries
         (map (lambda (spec)
                (if (eq? (car spec) 'tail:)
                    (%make-handler-entry (cadr spec) 'tail (caddr spec))
                    (%make-handler-entry (car spec) 'suspend (cadr spec))))
              specs)))
    (%call-with-handler-entries entries return-fn thunk)))

;;;----------------------------------------------------------------------------
;;; Zero-Closure Multi-Arg Perform Capture Receivers (all <= 4 args for inline)

(define (%perform-fast-cap-0! sub-k frame proc)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
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
    (%st-mc-set! st rest)
    (%st-marks-set! st pf-marks)
    (%st-barriers-set! st (%pf-barriers pframe))
    (%st-handlers-set! st (%pf-handlers pframe))
    (##continuation-graft (%pf-escape-k pframe) proc ek)))

(define (%perform-fast-cap-1! sub-k frame proc a1)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
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
    (%st-mc-set! st rest)
    (%st-marks-set! st pf-marks)
    (%st-barriers-set! st (%pf-barriers pframe))
    (%st-handlers-set! st (%pf-handlers pframe))
    (##continuation-graft (%pf-escape-k pframe) proc ek a1)))

(define (%perform-fast-cap-n! sub-k frame proc args)
  (let* ((st (%tc-fast))
         (mc (%st-mc st))
         (pframe (car mc))
         (rest (cdr mc))
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
    (%st-mc-set! st rest)
    (%st-marks-set! st pf-marks)
    (%st-barriers-set! st (%pf-barriers pframe))
    (%st-handlers-set! st (%pf-handlers pframe))
    (##continuation-graft (%pf-escape-k pframe) ##apply proc (cons ek args))))

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
         (is-init (eq? (%pf-handler pframe) 'init)))
    (if (not is-init) (%pf-escape-k-set! pframe #f))
    (%st-mc-set! st rest)
    (%st-marks-set! st (%pf-marks pframe))
    (%st-barriers-set! st (%pf-barriers pframe))
    (%st-handlers-set! st (%pf-handlers pframe))
    (%gen-sub-k-set! gen sub-k)
    ;; Release-store SUSPENDED strictly AFTER all pframe/st updates complete
    (%gen-state-store-rel! gen %GEN-SUSPENDED)
    (if is-init
        (##continuation-return ck val)
        (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! ck val)))))

;; Slow generator yield handler when nested prompts or frozen multi-shot frames exist
(define (%gen-yield-slow-handler gen)
  (lambda (ek val)
    (%gen-sub-k-set! gen ek)
    (%gen-state-store-rel! gen %GEN-SUSPENDED)
    val))

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
                   (%st-mc-set! st rest)
                   (%st-marks-set! st (%pf-marks pframe))
                   (%st-barriers-set! st (%pf-barriers pframe))
                   (%st-handlers-set! st (%pf-handlers pframe))
                   (cond
                     ((eq? a1 %ABSENT) (##continuation-graft escape-k proc ek))
                     ((eq? a2 %ABSENT) (##continuation-graft escape-k proc ek a1))
                     ((null? more)     (##continuation-graft escape-k proc ek a1 a2))
                     (else             (##continuation-graft escape-k ##apply proc
                                                             (cons ek (cons a1 (cons a2 more)))))))))))))))

;;;----------------------------------------------------------------------------
;;; Perform (Specialized 0/1/2/N-arg Fast Path — Zero Rest-Arg Consing)

(define (perform eff
                 #!optional
                 (a1 %ABSENT)
                 (a2 %ABSENT)
                 #!rest
                 more)
  (let* ((st (%tc-fast))
         (handlers (%st-handlers st)))
    ;; Fast inline lookup in thread's handler chain (0 cross-module calls)
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

;;;----------------------------------------------------------------------------
;;; Resume & Resume-Multishot
;;;
;;; Fast Path:
;;;   - Inline seq_cst CAS on effect-continuation.state (0 -> 1) claims linear
;;;     ownership with zero atomic-fxbox allocation.
;;;   - In tail position of the handler (`___FP == stack_break && ___R0 == handler_break
;;;     && break_next == escape_k.frame`) with matching `denv`, reclaims the span via
;;;     SATB-watermark-safe `___try_return_oneshot_fiber_cont` + `___JUMPEXTPRM`.
;;;   - In non-tail one-shot position, captures `caller-k` via zero-closure multi-arg
;;;     `##continuation-capture` and still returns to `sub-k` via `___try_return_oneshot_fiber_cont`
;;;     (zero dead-frame stack ratcheting, SATB-safe).

(define (%resume-nontail-oneshot-cont! caller-k sub-k frame val)
  (let* ((st (%tc-fast))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st))
         (pframe (%make-mc-frame 'prompt
                                 (%frame-tag frame)
                                 #f
                                 caller-k
                                 cur-marks
                                 cur-barriers
                                 cur-handlers)))
    (%st-mc-set! st (cons pframe cur-mc))
    (%st-handlers-set! st (cons frame cur-handlers))
    (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! sub-k val))))

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

;; Zero-closure multi-arg capture receivers for general / multi-shot resume (<= 4 args)
(define (%resume-checked-1! caller-k ek v1)
  (let* ((st (%tc-fast))
         (sub-k (%ec-sub-k ek))
         (prefix (%ec-prefix ek))
         (cap-marks (%ec-marks ek))
         (cap-handlers (%ec-handlers ek))
         (frame (%ec-frame ek))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame 'prompt
                                 (%frame-tag frame)
                                 #t
                                 caller-k
                                 saved-marks
                                 saved-barriers
                                 saved-handlers)))
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
        (##continuation-return sub-k v1))))

(define (%resume-checked ek v1 v2 more)
  (if (eq? v2 %ABSENT)
      (##continuation-capture %resume-checked-1! ek v1)
      (##continuation-capture
       (lambda (caller-k)
         (let* ((st (%tc-fast))
                (sub-k (%ec-sub-k ek))
                (prefix (%ec-prefix ek))
                (cap-marks (%ec-marks ek))
                (cap-handlers (%ec-handlers ek))
                (frame (%ec-frame ek))
                (saved-mc (%st-mc st))
                (saved-marks (%st-marks st))
                (saved-barriers (%st-barriers st))
                (saved-handlers (%st-handlers st))
                (pframe (%make-mc-frame 'prompt
                                        (%frame-tag frame)
                                        #t
                                        caller-k
                                        saved-marks
                                        saved-barriers
                                        saved-handlers)))
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
               (##apply ##continuation-return sub-k v1 v2 more)))))))

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
        (%resume-checked ek v1 v2 more))))

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
    (let ((pf (%ec-pframe ek)))
      (if (and pf (not (%pf-handler pf)))
          (%pf-handler-set! pf #t)))
    (let ((pr (%ec-prefix ek)))
      (if (pair? pr) (%freeze-mc-prefix! pr)))
    (%resume-checked ek v1 v2 more)))

;;;----------------------------------------------------------------------------
;;; Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles

(define-type effect-capability
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000005
  constructor: %make-capability
  predicate: effect-capability?
  (kind  %cap-kind)   ;; 'tail or 'suspend
  (proc  %cap-proc)   ;; handler procedure
  (frame %cap-frame)) ;; %handler-frame (for suspending capabilities) or #f

(define (call-with-tail-capability handler-proc body-proc)
  (body-proc (%make-capability 'tail handler-proc #f)))

(define (%install-cap-cont! escape-k cap body-proc)
  (let* ((st (%tc-fast))
         (frame (%cap-frame cap))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame 'prompt
                                 tag
                                 #f
                                 escape-k
                                 saved-marks
                                 saved-barriers
                                 saved-handlers)))
    (%st-mc-set! st (cons pframe saved-mc))
    (%st-handlers-set! st (cons frame saved-handlers))
    (%mc-return1 (body-proc cap))))

(define (call-with-suspend-capability handler-proc body-proc)
  (let* ((eff (%make-effect 'capability))
         (tag (make-continuation-prompt-tag 'cap-handler))
         (entry (%make-handler-entry eff 'suspend handler-proc))
         (frame (%make-handler-frame tag (list entry)))
         (cap (%make-capability 'suspend handler-proc frame)))
    (##continuation-capture %install-cap-cont! cap body-proc)))

(define (perform-cap cap
                     #!optional
                     (a1 %ABSENT)
                     (a2 %ABSENT)
                     #!rest
                     more)
  (if (eq? (%cap-kind cap) 'tail)
      ;; O(1) direct dispatch — zero handler-chain walk, zero capture!
      (let ((proc (%cap-proc cap)))
        (cond
          ((eq? a1 %ABSENT) (proc))
          ((eq? a2 %ABSENT) (proc a1))
          ((null? more)     (proc a1 a2))
          (else             (apply proc a1 a2 more))))
      ;; Direct suspending capability dispatch (zero-closure capture)
      (let* ((st (%tc-fast))
             (frame (%cap-frame cap))
             (handlers (%st-handlers st)))
        (%perform-suspend-dispatch st handlers frame (%cap-proc cap) a1 a2 more))))

;;;----------------------------------------------------------------------------
;;; Built-in Zero-Allocation Symmetric 4-State Direct-Style Generator

(define yield (make-effect 'yield))

(define (%gen-install-pframe! st gen caller-k)
  (let* ((pf (%gen-pframe gen))
         (cur-mc (%st-mc st))
         (cur-marks (%st-marks st))
         (cur-barriers (%st-barriers st))
         (cur-handlers (%st-handlers st))
         (frame (%gen-frame gen)))
    (if (and pf (not (%pf-handler pf)))
        ;; Reuse unfrozen pframe + cons cells in-place (zero heap allocation!)
        (let ((mc-cell (%gen-mc-cell gen))
              (h-cell (%gen-h-cell gen)))
          (%pf-escape-k-set! pf caller-k)
          (%pf-marks-set! pf cur-marks)
          (%pf-barriers-set! pf cur-barriers)
          (%pf-handlers-set! pf cur-handlers)
          (set-car! mc-cell pf)
          (set-cdr! mc-cell cur-mc)
          (set-car! h-cell frame)
          (set-cdr! h-cell cur-handlers)
          (%st-mc-set! st mc-cell)
          (%st-handlers-set! st h-cell))
        ;; Multi-shot froze previous pframe: allocate fresh COW frame + cells
        (let* ((fresh-pf (%make-mc-frame 'prompt
                                         (%frame-tag frame)
                                         #f
                                         caller-k
                                         cur-marks
                                         cur-barriers
                                         cur-handlers))
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
               (unfrozen (not (%pf-handler top))))
          (%st-mc-set! st rest)
          (%st-marks-set! st (%pf-marks top))
          (%st-barriers-set! st (%pf-barriers top))
          (%st-handlers-set! st (%pf-handlers top))
          (if unfrozen (%pf-escape-k-set! top #f))
          (%gen-state-store-rel! gen %GEN-DONE)
          (if unfrozen
              (let () (declare (inlining-limit 0)) (%return-oneshot-same-denv! ck #!eof))
              (##continuation-return ck #!eof)))
        (begin
          (%gen-state-store-rel! gen %GEN-DONE)
          #!eof))))

(define (%gen-start-cont! caller-k gen thunk)
  (let* ((st (%tc-fast))
         (frame (%gen-frame gen))
         (init-pf (%make-mc-frame 'prompt
                                  (%frame-tag frame)
                                  'init
                                  caller-k
                                  (%st-marks st)
                                  (%st-barriers st)
                                  (%st-handlers st))))
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
         (gen (%make-gen-raw (%make-gen-state) #f #f #f #f #f thunk))
         (entry (%make-handler-entry yield 'gen gen))
         (frame (%make-handler-frame tag (list entry)))
         (pf (%make-mc-frame 'prompt tag #f #f '() '() '()))
         (mc-cell (cons pf '()))
         (h-cell (cons frame '())))
    (##unchecked-structure-set! gen frame 4 #f #f)
    (%gen-pframe-set! gen pf)
    (%gen-mc-cell-set! gen mc-cell)
    (%gen-h-cell-set! gen h-cell)
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
               (let ((fn (%gen-thunk gen)))
                 (%gen-thunk-set! gen #f)
                 (##continuation-capture %gen-start-cont! gen fn))
               (error "generator already running")))
          (else
           (error "generator already running")))))))

;;;============================================================================
