;;;============================================================================

;;; File: "226.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 226, Control Features (Native Runtime Fast Path)
;;;
;;; Built directly on Gambit's O(1) zero-copy native continuation primitives
;;; (##continuation-capture, ##continuation-graft, ##continuation-return) and
;;; inline per-thread control-state slot (macro-thread-control-state), with
;;; lock-free unforgeable closure-code identity and inline C23 seq_cst CAS for
;;; linearizable SMP one-shot continuations and SATB-safe in-place stack
;;; continuation reclamation.

(##supply-module srfi/226)

(##namespace ("srfi/226#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace (""
  dynamic-wind
  error))
(##include "226#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (block)
  (not safe)
  (inlining-limit 400))

(##define-macro (macro-if-c-compiled then-expr else-expr)
  (let ((co (##global-var-ref (##make-global-var '##compilation-options))))
    (if (and (##not (##unbound? co))
             (let ((t (##assq 'target co)))
               (or (##not t) (##eq? (##cadr t) 'C))))
        then-expr
        else-expr)))

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
;;;
;;; Stored directly in Gambit's GC-traced green-thread `control-state` slot
;;; (macro-thread-control-state): O(1) single load, zero locks, zero hashing,
;;; zero memory leaks, and safe across SMP carrier thread migrations.

(define-type %mc-frame
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000002
  constructor: %make-mc-frame-9
  predicate: %mc-frame?
  (kind        %mc-frame-kind)     ;; 'prompt, 'underflow, or 'replay
  (tag         %mc-frame-tag)      ;; prompt-tag (or #f for underflow)
  (handler     %mc-frame-handler     %mc-frame-handler-set!)
  ;; handler values:
  ;;   #f                              = rewindable effect/underflow frame
  ;;   #t                              = frozen/shared effect/underflow frame
  ;;   'init                           = generator initial anchor frame (unreclaimable)
  ;;   %DEFAULT-PROMPT-HANDLER         = rewindable default prompt handler
  ;;   %FROZEN-DEFAULT-PROMPT-HANDLER  = frozen/shared default prompt handler
  ;;   procedure                       = custom abort handler
  (escape-k    %mc-frame-escape-k    %mc-frame-escape-k-set!) ;; native Gambit continuation object
  (marks       %mc-frame-marks)    ;; saved marks outside this frame
  (barriers    %mc-frame-barriers) ;; saved barriers outside this frame
  (handlers    %mc-frame-handlers) ;; saved effect handlers outside this frame
  (eh-scope    %mc-frame-eh-scope    %mc-frame-eh-scope-set!) ;; #f, trampoline closure, or caller-eh
  (unwind-hook %mc-frame-unwind-hook %mc-frame-unwind-hook-set!)) ;; #f or (lambda (phase) ...)

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

;; Inline unchecked accessors for %tc-state and %mc-frame (1-instruction load/store)
(define-macro (%tc-slot)
  '(macro-thread-control-state (macro-current-thread)))
(define-macro (%tc-slot-set! v)
  `(macro-thread-control-state-set! (macro-current-thread) ,v))

(define-macro (%st-mc st) `(##unchecked-structure-ref ,st 1 #f #f))
(define-macro (%st-mc-set! st v) `(##unchecked-structure-set! ,st ,v 1 #f #f))
(define-macro (%st-marks st) `(##unchecked-structure-ref ,st 2 #f #f))
(define-macro (%st-marks-set! st v) `(##unchecked-structure-set! ,st ,v 2 #f #f))
(define-macro (%st-barriers st) `(##unchecked-structure-ref ,st 3 #f #f))
(define-macro (%st-barriers-set! st v) `(##unchecked-structure-set! ,st ,v 3 #f #f))
(define-macro (%st-handlers st) `(##unchecked-structure-ref ,st 4 #f #f))
(define-macro (%st-handlers-set! st v) `(##unchecked-structure-set! ,st ,v 4 #f #f))
(define-macro (%st-eh-outer-denv st) `(##unchecked-structure-ref ,st 7 #f #f))
(define-macro (%st-eh-outer-denv-set! st v) `(##unchecked-structure-set! ,st ,v 7 #f #f))
(define-macro (%st-eh-outer-proc st) `(##unchecked-structure-ref ,st 8 #f #f))
(define-macro (%st-eh-outer-proc-set! st v) `(##unchecked-structure-set! ,st ,v 8 #f #f))
(define-macro (%st-eh-tramp-denv st) `(##unchecked-structure-ref ,st 9 #f #f))
(define-macro (%st-eh-tramp-denv-set! st v) `(##unchecked-structure-set! ,st ,v 9 #f #f))
(define-macro (%st-eh-tramp-proc st) `(##unchecked-structure-ref ,st 10 #f #f))
(define-macro (%st-eh-tramp-proc-set! st v) `(##unchecked-structure-set! ,st ,v 10 #f #f))

(define-macro (%pf-kind pf) `(##unchecked-structure-ref ,pf 1 #f #f))
(define-macro (%pf-tag pf) `(##unchecked-structure-ref ,pf 2 #f #f))
(define-macro (%pf-handler pf) `(##unchecked-structure-ref ,pf 3 #f #f))
(define-macro (%pf-handler-set! pf v) `(##unchecked-structure-set! ,pf ,v 3 #f #f))
(define-macro (%pf-escape-k pf) `(##unchecked-structure-ref ,pf 4 #f #f))
(define-macro (%pf-escape-k-set! pf v) `(##unchecked-structure-set! ,pf ,v 4 #f #f))
(define-macro (%pf-marks pf) `(##unchecked-structure-ref ,pf 5 #f #f))
(define-macro (%pf-barriers pf) `(##unchecked-structure-ref ,pf 6 #f #f))
(define-macro (%pf-handlers pf) `(##unchecked-structure-ref ,pf 7 #f #f))
(define-macro (%pf-eh-scope pf) `(##unchecked-structure-ref ,pf 8 #f #f))
(define-macro (%pf-eh-scope-set! pf v) `(##unchecked-structure-set! ,pf ,v 8 #f #f))
(define-macro (%pf-unwind-hook pf) `(##unchecked-structure-ref ,pf 9 #f #f))
(define-macro (%pf-unwind-hook-set! pf v) `(##unchecked-structure-set! ,pf ,v 9 #f #f))

(define (%tc-current)
  (let ((st (%tc-slot)))
    (if st
        st
        (let ((fresh (%make-tc-state '() '() '() '() #f #f #f #f #f #f)))
          (%tc-slot-set! fresh)
          fresh))))

;;;----------------------------------------------------------------------------
;;; Scope-Bound Exception Unwind Trampoline (Zero-Cost When Nested)
;;;
;;; Keeps `st.mc`, `st.marks`, `st.barriers`, `st.handlers`, and generator
;;; unwind hooks coherent whenever an uncaught exception escapes through an
;;; enclosing `with-exception-catcher` or `with-exception-handler`.
;;; Bound outside `##continuation-capture` once per outer exception-handler
;;; scope so `escape-k` and captured `sub-k` share identical `denv` (preserving
;;; 100% of one-shot stack rewinds) and nested prompts incur only a single `eq?`.

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

;;;----------------------------------------------------------------------------
;;; Continuation Mark Sets

(define-type continuation-mark-set
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000003
  constructor: %make-mark-set
  predicate: continuation-mark-set?
  (frames %mark-set-frames))  ;; list of alists from innermost to outermost

;;;----------------------------------------------------------------------------
;;; Lock-Free Closure-Code One-Shot Continuation Representation
;;;
;;; Eliminates all mutex locks, weak hash tables, eq?-hash serial allocation,
;;; and per-capture atomic-fxbox heap objects:
;;;   - `%one-shot-cell` stores the atomic fixnum state in field 1 and all
;;;     captured continuation metadata in fields 2..8.
;;;   - `%make-one-shot-closure` closes over ONLY `cell`, yielding a standard
;;;     Scheme procedure (`procedure?` = #t) whose `##closure-code` equals the
;;;     module-private sentinel `%one-shot-closure-code` and whose slot 1 is
;;;     `cell`.
;;;   - `one-shot-continuation?`, `one-shot-continuation-consumed?`, and
;;;     `promote-one-shot-continuation!` execute in O(1) with zero locks.

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

(define-macro (%osc-cas-state! cell expected desired)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
      ___RESULT = ___CAST(___SCMOBJ,
        ___atomic_word_cas(___CAST(___VOLATILE ___WORD*, &___f[1]),
                           ___CAST(___WORD, ___ARG2),
                           ___CAST(___WORD, ___ARG3), 4));"
     ,cell ,expected ,desired)
    (let* ((c ,cell)
           (prev (##unchecked-structure-ref c 1 #f #f)))
      (if (fx= prev ,expected)
          (##unchecked-structure-set! c ,desired 1 #f #f))
      prev)))

(define-macro (%osc-load-state cell)
  `(macro-if-c-compiled
    (##c-code
     "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
      ___RESULT = ___CAST(___SCMOBJ,
        __atomic_load_n(&___f[1], __ATOMIC_ACQUIRE));"
     ,cell)
    (##unchecked-structure-ref ,cell 1 #f #f)))

(define-macro (%osc-kind-fast c) `(##unchecked-structure-ref ,c 2 #f #f))
(define-macro (%osc-sub-k-fast c) `(##unchecked-structure-ref ,c 3 #f #f))
(define-macro (%osc-prefix-fast c) `(##unchecked-structure-ref ,c 4 #f #f))
(define-macro (%osc-marks-fast c) `(##unchecked-structure-ref ,c 5 #f #f))
(define-macro (%osc-barriers-fast c) `(##unchecked-structure-ref ,c 6 #f #f))
(define-macro (%osc-handlers-fast c) `(##unchecked-structure-ref ,c 7 #f #f))
(define-macro (%osc-tag-fast c) `(##unchecked-structure-ref ,c 8 #f #f))

;;;----------------------------------------------------------------------------
;;; Internal Metacontinuation Helpers & SATB-Safe In-Place Prompt Reclaim

(define (%default-prompt-handler tag)
  (lambda (thunk)
    (call-with-continuation-prompt thunk tag)))

;; Freeze a single metacontinuation frame so `%mc-return1` / `%mc-return-vals`
;; never reclaims its `escape-k` in-place while any captured continuation may
;; reference it via `next_break_link` or shared prefix replay.
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

;; SATB-watermark-safe in-place stack continuation return for unfrozen frames.
;; Clears `pframe->escape-k` ONLY after `___try_return_oneshot_fiber_cont`
;; confirms the reclaim succeeded and `denv` matches. Must be called through
;; a non-inlined boundary `(let () (declare (inlining-limit 0)) ...)` so any
;; active Gambit write-group is committed before `___JUMPEXTPRM`.
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

;; Fast single-value return through topmost metacontinuation frame (zero thunk,
;; zero rest-list; SATB-safe in-place stack reclaim for unfrozen frames).
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
;; Exported internal contract: returns (values prefix pframe rest) or (values #f #f #f).
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

;; Zero-MV-closure helper: finds matching prompt frame; returns pair `(prefix . tail)`
;; where `(car tail)` is `pframe` and `(cdr tail)` is `rest`, or `#f` if not found.
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

(define (continuation-prompt-available? tag)
  (let loop ((cur (%st-mc (%tc-current))))
    (cond
      ((null? cur) #f)
      ((and (eq? (%pf-kind (car cur)) 'prompt)
            (eq? (%pf-tag (car cur)) tag))
       #t)
      (else (loop (cdr cur))))))

(define (%abort-to-pframe! st pframe rest tag a1 a2 a3 more)
  (let ((escape-k (%pf-escape-k pframe))
        (handler (%pf-handler pframe)))
    (%st-mc-set! st rest)
    (%st-marks-set! st (%pf-marks pframe))
    (%st-barriers-set! st (%pf-barriers pframe))
    (%st-handlers-set! st (%pf-handlers pframe))
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
                                 (cons a1 (cons a2 (cons a3 more)))))))))

(define (abort-current-continuation tag
                                    #!optional
                                    (a1 %ABSENT)
                                    (a2 %ABSENT)
                                    (a3 %ABSENT)
                                    #!rest
                                    more)
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (%abort-to-pframe! st (car mc) (cdr mc) tag a1 a2 a3 more)
        (let ((found (%mc-find-tail-slow mc tag)))
          (if (not found)
              (error "abort-current-continuation: no prompt found for tag" tag)
              (let ((tail (cdr found)))
                (%abort-to-pframe! st (car tail) (cdr tail) tag a1 a2 a3 more)))))))

(define (call-with-continuation-barrier thunk)
  (let* ((st (%tc-current))
         (barrier-token (list 'continuation-barrier))
         (saved-barriers (%st-barriers st))
         (new-barriers (cons barrier-token saved-barriers)))
    (dynamic-wind
      (lambda () (%st-barriers-set! (%tc-current) new-barriers))
      thunk
      (lambda () (%st-barriers-set! (%tc-current) saved-barriers)))))

;;;----------------------------------------------------------------------------
;;; Composable & Non-Composable Delimited Continuations (Zero-Copy Native)

;; Zero-closure <=4-arg capture receiver for 1-value / 0-value composable replay
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
        (##continuation-return sub-k v1))))

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
             (else (##apply ##continuation-return sub-k v1 v2 v3 more))))))))

(define (%invoke-noncomp-cell cell v1 v2 v3 more)
  (let* ((cst (%tc-current))
         (cap-barriers (%osc-barriers-fast cell)))
    (if (%entering-barrier? cap-barriers (%st-barriers cst))
        (error "continuation invocation blocked by continuation barrier"))
    (let* ((tag (%osc-tag-fast cell))
           (mc (%st-mc cst))
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
      (let ((prefix (%osc-prefix-fast cell))
            (cap-marks (%osc-marks-fast cell))
            (cap-handlers (%osc-handlers-fast cell))
            (sub-k (%osc-sub-k-fast cell)))
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
          (else (##apply ##continuation-return sub-k v1 v2 v3 more)))))))

(define (%invoke-raw-cell cell v1 v2 v3 more)
  (if (%entering-barrier? (%osc-barriers-fast cell) (%st-barriers (%tc-current)))
      (error "continuation invocation blocked by continuation barrier"))
  (let ((sub-k (%osc-sub-k-fast cell)))
    (cond
      ((eq? v1 %ABSENT) (##continuation-return sub-k))
      ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
      ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
      ((null? more) (##continuation-return sub-k v1 v2 v3))
      (else (##apply ##continuation-return sub-k v1 v2 v3 more)))))

;; Multi-shot composable closure (single free variable `cell`, zero outer allocs)
(define (%make-composable-closure cell)
  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
    (%invoke-composable-cell cell v1 v2 v3 more)))

;; Multi-shot non-composable closure
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
    (proc (%make-composable-closure cell))))

(define (%capture-composable-fast! sub-k proc)
  (let ((cell (%make-one-shot-cell %CONT-MULTISHOT-COW 'composable sub-k '() '() '() '() #f)))
    (proc (%make-composable-closure cell))))

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
    (proc (%make-noncomp-closure cell))))

(define (call-with-composable-continuation proc
                                           #!optional
                                           (tag %default-prompt-tag))
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
    ;; Freeze both prefix AND delimiting pframe so `%mc-return1` never reclaims
    ;; `pframe->escape-k` while `sub-k` is live.
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
;;; Lock-Free Atomic One-Shot Continuations (call/1cc & composable one-shot)

(define (%invoke-one-shot-cell cell v1 v2 v3 more)
  (let ((prev (%osc-cas-state! cell %CONT-ONE-SHOT-LIVE %CONT-ONE-SHOT-CONSUMED)))
    (if (or (fx= prev %CONT-ONE-SHOT-LIVE)
            (fx= prev %CONT-MULTISHOT-COW))
        (let ((kind (%osc-kind-fast cell)))
          (cond
            ((eq? kind 'composable)
             (%invoke-composable-cell cell v1 v2 v3 more))
            ((eq? kind 'noncomp)
             (%invoke-noncomp-cell cell v1 v2 v3 more))
            (else
             (%invoke-raw-cell cell v1 v2 v3 more))))
        (error "one-shot continuation already consumed"))))

;; Single-free-variable closure factory: `##closure-code` is unforgeable and
;; `(##closure-ref k 1)` is unconditionally `cell`.
(define (%make-one-shot-closure cell)
  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
    (%invoke-one-shot-cell cell v1 v2 v3 more)))

;; Capture the module-private entry code label once at load time using a
;; non-inlined boundary and a fresh heap-allocated cell.
(define (%init-one-shot-closure-code)
  (let ()
    (declare (inlining-limit 0))
    (##closure-code
     (%make-one-shot-closure
      (%make-one-shot-cell 0 'raw #f '() '() '() '() #f)))))

(define %one-shot-closure-code (%init-one-shot-closure-code))

(define (%extract-one-shot-cell obj)
  (if (and (##closure? obj)
           (##eq? (##closure-code obj) %one-shot-closure-code))
      (let ((c (##closure-ref obj 1)))
        (if (%one-shot-cell? c) c #f))
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
(define (%capture-1cc-raw! sub-k proc cap-barriers)
  (let ((cell (%make-one-shot-cell %CONT-ONE-SHOT-LIVE 'raw sub-k '() '() cap-barriers '() #f)))
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
              (##continuation-capture %capture-1cc-raw! proc (%st-barriers st)))))))

(define (call-with-one-shot-composable-continuation proc
                                                    #!optional
                                                    (tag %default-prompt-tag))
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

;;;----------------------------------------------------------------------------
;;; Continuation Marks (Racket CS ICFP '20 True O(1) Tail-Call-Preserving Marks)
;;;
;;; Uses ##tail-call-with-r0 to inspect the caller's exact return address without
;;; allocating a stack frame. When caller-r0 == %mark-pop-ra (tail position of an
;;; enclosing marked frame), replaces/merges key -> val in the top mark frame in
;;; O(1) stack space and tail-calls thunk directly.

(define %mark-pop-ra #f)

(define (%alist-replace alist key val)
  (if (and (pair? alist) (eq? (caar alist) key))
      (cons (cons key val) (cdr alist))
      (let loop ((xs alist) (acc '()))
        (cond
          ((null? xs) (cons (cons key val) (reverse acc)))
          ((eq? (caar xs) key)
           (append (reverse acc) (cons (cons key val) (cdr xs))))
          (else
           (loop (cdr xs) (cons (car xs) acc)))))))

(define (%mark-pop-frame res)
  (let* ((st (%tc-current))
         (ms (%st-marks st)))
    (if (pair? ms)
        (%st-marks-set! st (cdr ms)))
    res))

(define (%mark-push-and-run! st ms kv thunk)
  (##declare (not inline))
  (%st-marks-set! st (cons (list kv) ms))
  (%mark-pop-frame (thunk)))

(define (%mark-dispatch caller-r0 kv thunk)
  (let* ((st (%tc-current))
         (ms (%st-marks st))
         (key (car kv))
         (val (cdr kv)))
    (if (and %mark-pop-ra (eq? caller-r0 %mark-pop-ra) (pair? ms))
        (begin
          (%st-marks-set! st (cons (%alist-replace (car ms) key val) (cdr ms)))
          (thunk))
        (let ((cur-eh (macro-current-exception-handler)))
          (if (%mc-eh-trampoline? cur-eh)
              (%mark-push-and-run! st ms kv thunk)
              (macro-dynamic-bind
               exception-handler
               (lambda (exc)
                 (let ((saved (%st-marks st)))
                   (%st-marks-set! st ms)
                   (let ((res (macro-dynamic-bind
                               exception-handler
                               cur-eh
                               (lambda () (cur-eh exc)))))
                     (%st-marks-set! st saved)
                     res)))
               (lambda ()
                 (%mark-push-and-run! st ms kv thunk))))))))

(define (%call-with-continuation-mark key val thunk)
  (##tail-call-with-r0 %mark-dispatch (cons key val) thunk))

;; Capture the exact Gambit C return label of `(thunk)` inside `%mark-dispatch`
;; once at module load time so tail-recursive `with-continuation-mark` is O(1).
(%call-with-continuation-mark
 '%srfi226-init
 #t
 (lambda ()
   (##tail-call-with-r0
    (lambda (r0 _ __) (set! %mark-pop-ra r0))
    #f
    #f)))

(define (current-continuation-marks #!optional (tag %default-prompt-tag))
  (let* ((st (%tc-current))
         (mc (%st-mc st)))
    (if (and (pair? mc)
             (eq? (%pf-kind (car mc)) 'prompt)
             (eq? (%pf-tag (car mc)) tag))
        (%make-mark-set (%list-prefix-until (%st-marks st) (%pf-marks (car mc))))
        (let ((found (%mc-find-tail-slow mc tag)))
          (if found
              (%make-mark-set (%list-prefix-until (%st-marks st) (%pf-marks (cadr found))))
              (%make-mark-set (%st-marks st)))))))

(define (continuation-marks cont #!optional (tag %default-prompt-tag))
  (if (continuation-mark-set? cont)
      cont
      (current-continuation-marks tag)))

(define (continuation-mark-set->list mark-set key #!optional (tag %default-prompt-tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (current-continuation-marks tag)))))
    (let loop ((fs frames) (acc '()))
      (if (null? fs)
          (reverse acc)
          (let ((entry (assq key (car fs))))
            (loop (cdr fs)
                  (if entry (cons (cdr entry) acc) acc)))))))

(define (continuation-mark-set->list* mark-set key-list
                                      #!optional
                                      (none-v #f)
                                      (tag %default-prompt-tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (current-continuation-marks tag))))
        (n (length key-list)))
    (let loop ((fs frames) (acc '()))
      (if (null? fs)
          (reverse acc)
          (let ((alist (car fs))
                (vec (make-vector n none-v))
                (found? #f))
            (let kloop ((ks key-list) (i 0))
              (if (pair? ks)
                  (let ((entry (assq (car ks) alist)))
                    (if entry
                        (begin
                          (vector-set! vec i (cdr entry))
                          (set! found? #t)))
                    (kloop (cdr ks) (fx+ i 1)))))
            (loop (cdr fs)
                  (if found? (cons vec acc) acc)))))))

(define (continuation-mark-set-first mark-set key
                                     #!optional
                                     (none-v #f)
                                     (tag %default-prompt-tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (current-continuation-marks tag)))))
    (let loop ((fs frames))
      (if (null? fs)
          none-v
          (let ((entry (assq key (car fs))))
            (if entry
                (cdr entry)
                (loop (cdr fs))))))))

(define (call-with-immediate-continuation-mark key proc #!optional (default #f))
  (let ((ms (%st-marks (%tc-current))))
    (if (null? ms)
        (proc default)
        (let ((entry (assq key (car ms))))
          (proc (if entry (cdr entry) default))))))

;;;============================================================================
