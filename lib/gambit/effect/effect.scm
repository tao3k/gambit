;;;============================================================================

;;; File: "effect.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; (gambit effect) — Direct-Style Algebraic Effect Handlers (Phase C2 Native)
;;;
;;; Built directly on Gambit's native zero-copy continuation primitives
;;; (##continuation-capture, ##continuation-graft, ##continuation-return),
;;; O(1) per-thread control state (##thread-control-state), and (srfi 230)
;;; inline atomic-fxbox CAS:
;;;   1. Koka ICFP '21 Tail-Resumptive Fast Path (`tail:`): zero prompt, zero
;;;      capture, zero parameterize, O(1) direct thread-slot handler lookup,
;;;      and zero-rest-arg 0/1/2-arg dispatch.
;;;   2. OCaml-5-Style Single-Capture Suspending Effects: `perform` performs
;;;      1 ##continuation-capture + 1 ##continuation-graft (zero thunks, zero
;;;      `apply`, zero `parameterize`); `resume` performs 1 inline atomic CAS
;;;      (0->1) + 1 ##continuation-capture + 1 ##continuation-return.
;;;   3. Lazy Multi-Shot Promotion: `resume-multishot` atomically transitions
;;;      ONE_SHOT_LIVE (0) -> MULTISHOT_COW (2) prior to invocation.

(##supply-module gambit/effect)

(##namespace ("gambit/effect#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
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
  (block))

;;;----------------------------------------------------------------------------
;;; Constants & Effect Identity

(define %EC-ONE-SHOT-LIVE     0)
(define %EC-ONE-SHOT-CONSUMED 1)
(define %EC-MULTISHOT-COW     2)
(define %ABSENT (list 'gambit-effect-absent))

(define-type effect
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000001
  constructor: %make-effect
  predicate: effect?
  (name effect-name))

(define (make-effect #!optional (name 'effect))
  (%make-effect name))

;;;----------------------------------------------------------------------------
;;; Handler Evidence Entries, Frames & Continuations

(define-type %handler-entry
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000002
  constructor: %make-handler-entry
  predicate: %handler-entry?
  (effect %entry-effect)
  (kind   %entry-kind)   ;; 'tail or 'suspend
  (proc   %entry-proc))

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
  (state    %ec-state))                     ;; SRFI 230 atomic-fxbox (0=live, 1=consumed, 2=multishot)

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

(define (%call-with-handler-entries entries return-fn thunk)
  (if (%entries-all-tail? entries)
      ;; Koka ICFP '21 Tail-Resumptive Fast Path:
      ;; Zero prompt, zero continuation capture, zero parameterize!
      (let* ((frame (%make-handler-frame #f entries))
             (st (%tc-current))
             (old-handlers (%tc-handlers st)))
        (%tc-handlers-set! st (cons frame old-handlers))
        (with-exception-catcher
         (lambda (e)
           (%tc-handlers-set! (%tc-current) old-handlers)
           (raise e))
         (lambda ()
           (let ((res (thunk)))
             (%tc-handlers-set! (%tc-current) old-handlers)
             (if return-fn (return-fn res) res)))))
      ;; Native Single-Capture Deep Effect Handler on SRFI-226 metacontinuation
      (let* ((tag (make-continuation-prompt-tag 'effect-handler))
             (frame (%make-handler-frame tag entries)))
        (##continuation-capture
         (lambda (escape-k)
           (let* ((st (%tc-current))
                  (saved-mc (%tc-mc st))
                  (saved-marks (%tc-marks st))
                  (saved-barriers (%tc-barriers st))
                  (saved-handlers (%tc-handlers st))
                  (pframe (%make-mc-frame 'prompt
                                          tag
                                          #f
                                          escape-k
                                          saved-marks
                                          saved-barriers
                                          saved-handlers)))
             (%tc-mc-set! st (cons pframe saved-mc))
             (%tc-handlers-set! st (cons frame saved-handlers))
             (let ((res (if return-fn (return-fn (thunk)) (thunk))))
               (%mc-return1 res))))))))

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
;;; Perform (Specialized 0/1/2/N-arg Fast Path — Zero Rest-Arg Consing)

(define (perform eff
                 #!optional
                 (a1 %ABSENT)
                 (a2 %ABSENT)
                 #!rest
                 more)
  (let* ((st (%tc-current))
         (handlers (%tc-handlers st)))
    ;; Fast inline lookup in thread's handler chain
    (let loop ((fs handlers))
      (if (null? fs)
          (error "perform: unhandled effect" (effect-name eff))
          (let* ((frame (car fs))
                 (entry (%find-entry-in-frame eff (%frame-entries frame))))
            (if (not entry)
                (loop (cdr fs))
                (if (eq? (%entry-kind entry) 'tail)
                    ;; Koka Tail-Resumptive Fast Path: direct call, zero capture!
                    (let ((proc (%entry-proc entry)))
                      (cond
                        ((eq? a1 %ABSENT) (proc))
                        ((eq? a2 %ABSENT) (proc a1))
                        ((null? more)     (proc a1 a2))
                        (else             (apply proc a1 a2 more))))
                    ;; Suspending Effect: 1 ##continuation-capture + 1 ##continuation-graft!
                    (let ((tag (%frame-tag frame))
                          (proc (%entry-proc entry))
                          (mc (%tc-mc st)))
                      ;; Fast path: handler's prompt is at the very top of mc
                      (if (and (pair? mc)
                               (eq? (%mc-frame-kind (car mc)) 'prompt)
                               (eq? (%mc-frame-tag (car mc)) tag)
                               (not (%barrier-between? (%tc-barriers st)
                                                       (%mc-frame-barriers (car mc)))))
                          (let* ((pframe (car mc))
                                 (rest (cdr mc))
                                 (cap-marks (%list-prefix-until (%tc-marks st)
                                                                (%mc-frame-marks pframe)))
                                 (cap-handlers (%handlers-prefix-before handlers frame))
                                 (escape-k (%mc-frame-escape-k pframe)))
                            (##continuation-capture
                             (lambda (sub-k)
                               (let ((ek (%make-effect-continuation
                                          sub-k
                                          pframe
                                          '()
                                          cap-marks
                                          cap-handlers
                                          frame
                                          (make-atomic-fxbox %EC-ONE-SHOT-LIVE))))
                                 (%tc-mc-set! st rest)
                                 (%tc-marks-set! st (%mc-frame-marks pframe))
                                 (%tc-barriers-set! st (%mc-frame-barriers pframe))
                                 (%tc-handlers-set! st (%mc-frame-handlers pframe))
                                 (cond
                                   ((eq? a1 %ABSENT)
                                    (##continuation-graft escape-k proc ek))
                                   ((eq? a2 %ABSENT)
                                    (##continuation-graft escape-k proc ek a1))
                                   ((null? more)
                                    (##continuation-graft escape-k proc ek a1 a2))
                                   (else
                                    (##continuation-graft escape-k ##apply proc
                                                          (cons ek (cons a1 (cons a2 more))))))))))
                          ;; General nested-prompt path
                          (call-with-values
                            (lambda () (%mc-split-at-tag mc tag))
                            (lambda (prefix pframe rest)
                              (if (not pframe)
                                  (error "perform: handler prompt not active" (effect-name eff)))
                              (if (%barrier-between? (%tc-barriers st)
                                                     (%mc-frame-barriers pframe))
                                  (error "perform: cannot suspend across continuation barrier"
                                         (effect-name eff)))
                              (let ((cap-marks (%list-prefix-until (%tc-marks st)
                                                                   (%mc-frame-marks pframe)))
                                    (cap-handlers (%handlers-prefix-before handlers frame))
                                    (escape-k (%mc-frame-escape-k pframe)))
                                (##continuation-capture
                                 (lambda (sub-k)
                                   (let ((ek (%make-effect-continuation
                                              sub-k
                                              pframe
                                              prefix
                                              cap-marks
                                              cap-handlers
                                              frame
                                              (make-atomic-fxbox %EC-ONE-SHOT-LIVE))))
                                     (%tc-mc-set! st rest)
                                     (%tc-marks-set! st (%mc-frame-marks pframe))
                                     (%tc-barriers-set! st (%mc-frame-barriers pframe))
                                     (%tc-handlers-set! st (%mc-frame-handlers pframe))
                                     (cond
                                       ((eq? a1 %ABSENT)
                                        (##continuation-graft escape-k proc ek))
                                       ((eq? a2 %ABSENT)
                                        (##continuation-graft escape-k proc ek a1))
                                       ((null? more)
                                        (##continuation-graft escape-k proc ek a1 a2))
                                       (else
                                        (##continuation-graft escape-k ##apply proc
                                                              (cons ek (cons a1 (cons a2 more)))))))))))))))))))))

;;;----------------------------------------------------------------------------
;;; Resume & Resume-Multishot
;;;
;;; Phase C3 Fast Path: when a one-shot continuation is resumed in tail
;;; position of its handler with empty prefix/marks/handlers, clear all live
;;; references to the stack-allocated continuation and tail-call the C runtime
;;; `##continuation-try-rewind-oneshot!` to reclaim the captured stack span in
;;; O(1) with ZERO bytes of stack growth and ZERO frame copies. Non-tail
;;; resumes (e.g. generators, collectors) transparently enter the zero-closure
;;; fallback `%resume-non-tail-fallback`.

(define (%resume-non-tail-fallback sub-k val)
  (let* ((st (%tc-current))
         (frame (%tc-rewind-frame st))
         (saved-mc (cdr (%tc-mc st)))
         (saved-handlers (cdr (%tc-handlers st))))
    (%tc-rewind-frame-set! st #f)
    (%tc-mc-set! st saved-mc)
    (%tc-handlers-set! st saved-handlers)
    (##continuation-capture
     (lambda (caller-k)
       (let* ((cst (%tc-current))
              (cur-mc (%tc-mc cst))
              (cur-marks (%tc-marks cst))
              (cur-barriers (%tc-barriers cst))
              (cur-handlers (%tc-handlers cst))
              (pframe (%make-mc-frame 'prompt
                                      (%frame-tag frame)
                                      #f
                                      caller-k
                                      cur-marks
                                      cur-barriers
                                      cur-handlers)))
         (%tc-mc-set! cst (cons pframe cur-mc))
         (%tc-handlers-set! cst (cons frame cur-handlers))
         (##continuation-return sub-k val))))))

(define (%resume-checked ek v1 v2 more)
  (let ((sub-k (%ec-sub-k ek))
        (prefix (%ec-prefix ek))
        (cap-marks (%ec-marks ek))
        (cap-handlers (%ec-handlers ek))
        (frame (%ec-frame ek)))
    (##continuation-capture
     (lambda (caller-k)
       (let* ((st (%tc-current))
              (saved-mc (%tc-mc st))
              (saved-marks (%tc-marks st))
              (saved-barriers (%tc-barriers st))
              (saved-handlers (%tc-handlers st))
              (pframe (%make-mc-frame 'prompt
                                      (%frame-tag frame)
                                      #f
                                      caller-k
                                      saved-marks
                                      saved-barriers
                                      saved-handlers)))
         (%tc-mc-set! st
                      (if (null? prefix)
                          (cons pframe saved-mc)
                          (append prefix (cons pframe saved-mc))))
         (%tc-marks-set! st
                         (if (null? cap-marks)
                             saved-marks
                             (append cap-marks saved-marks)))
         (%tc-barriers-set! st saved-barriers)
         (%tc-handlers-set! st
                            (let ((base (cons frame saved-handlers)))
                              (if (null? cap-handlers)
                                  base
                                  (append cap-handlers base))))
         (cond
           ((eq? v1 %ABSENT) (##continuation-return sub-k))
           ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
           ((null? more)     (##continuation-return sub-k v1 v2))
           (else             (##apply ##continuation-return sub-k v1 v2 more))))))))

(define (resume ek
                #!optional
                (v1 %ABSENT)
                (v2 %ABSENT)
                #!rest
                more)
  (if (not (effect-continuation? ek))
      (error "resume: expected effect-continuation" ek))
  (let* ((state-box (%ec-state ek))
         (prev (atomic-fxbox-compare-and-swap! state-box
                                               %EC-ONE-SHOT-LIVE
                                               %EC-ONE-SHOT-CONSUMED)))
    (if (not (or (fx= prev %EC-ONE-SHOT-LIVE)
                 (fx= prev %EC-MULTISHOT-COW)))
        (error "one-shot continuation already consumed" ek))
    ;; Phase C3 tail-resume one-shot stack-rewind fast path (1-arg common case)
    (if (and (fx= prev %EC-ONE-SHOT-LIVE)
             (not (eq? v1 %ABSENT))
             (eq? v2 %ABSENT)
             (null? (%ec-prefix ek))
             (null? (%ec-marks ek))
             (null? (%ec-handlers ek)))
        (let* ((sub-k (%ec-sub-k ek))
               (pframe (%ec-pframe ek))
               (frame (%ec-frame ek))
               (st (%tc-current)))
          ;; Sever all heap references to the stack-allocated sub-k before rewind!
          (%ec-sub-k-set! ek #f)
          (%ec-pframe-set! ek #f)
          (%ec-frame-set! ek #f)
          ;; Speculatively reinstall pframe (reusing existing object, zero alloc)
          (%tc-mc-set! st (cons pframe (%tc-mc st)))
          (%tc-handlers-set! st (cons frame (%tc-handlers st)))
          (%tc-rewind-escape-set! st (%mc-frame-escape-k pframe))
          (%tc-rewind-frame-set! st frame)
          (##continuation-try-rewind-oneshot! sub-k v1 %resume-non-tail-fallback))
        (%resume-checked ek v1 v2 more))))

(define (resume-multishot ek
                          #!optional
                          (v1 %ABSENT)
                          (v2 %ABSENT)
                          #!rest
                          more)
  (if (not (effect-continuation? ek))
      (error "resume-multishot: expected effect-continuation" ek))
  (let* ((state-box (%ec-state ek))
         (prev (atomic-fxbox-compare-and-swap! state-box
                                               %EC-ONE-SHOT-LIVE
                                               %EC-MULTISHOT-COW)))
    (if (not (or (fx= prev %EC-ONE-SHOT-LIVE)
                 (fx= prev %EC-MULTISHOT-COW)))
        (error "cannot promote consumed one-shot continuation" ek))
    (%resume-checked ek v1 v2 more)))

;;;----------------------------------------------------------------------------
;;; Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles
;;;
;;; Eliminates dynamic handler-chain walking completely:
;;;   - Tail capabilities invoke the handler procedure directly in O(1)
;;;     (zero dynamic lookup, zero ##thread-control-state read, zero capture).
;;;   - Suspending capabilities jump directly to their bound prompt tag without
;;;     scanning %tc-handlers.

(define-type effect-capability
  id: 8B1F3A70-9C24-4D6B-A5E1-EFF000000005
  constructor: %make-capability
  predicate: effect-capability?
  (kind  %cap-kind)   ;; 'tail or 'suspend
  (proc  %cap-proc)   ;; handler procedure
  (frame %cap-frame)) ;; %handler-frame (for suspending capabilities) or #f

(define (call-with-tail-capability handler-proc body-proc)
  (body-proc (%make-capability 'tail handler-proc #f)))

(define (call-with-suspend-capability handler-proc body-proc)
  (let* ((eff (%make-effect 'capability))
         (tag (make-continuation-prompt-tag 'cap-handler))
         (entry (%make-handler-entry eff 'suspend handler-proc))
         (frame (%make-handler-frame tag (list entry)))
         (cap (%make-capability 'suspend handler-proc frame)))
    (##continuation-capture
     (lambda (escape-k)
       (let* ((st (%tc-current))
              (saved-mc (%tc-mc st))
              (saved-marks (%tc-marks st))
              (saved-barriers (%tc-barriers st))
              (saved-handlers (%tc-handlers st))
              (pframe (%make-mc-frame 'prompt
                                      tag
                                      #f
                                      escape-k
                                      saved-marks
                                      saved-barriers
                                      saved-handlers)))
         (%tc-mc-set! st (cons pframe saved-mc))
         (%tc-handlers-set! st (cons frame saved-handlers))
         (%mc-return1 (body-proc cap)))))))

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
      ;; Direct suspending capability dispatch
      (let* ((st (%tc-current))
             (frame (%cap-frame cap))
             (tag (%frame-tag frame))
             (proc (%cap-proc cap))
             (mc (%tc-mc st))
             (handlers (%tc-handlers st)))
        (if (and (pair? mc)
                 (eq? (%mc-frame-kind (car mc)) 'prompt)
                 (eq? (%mc-frame-tag (car mc)) tag)
                 (not (%barrier-between? (%tc-barriers st)
                                         (%mc-frame-barriers (car mc)))))
            (let* ((pframe (car mc))
                   (rest (cdr mc))
                   (cap-marks (%list-prefix-until (%tc-marks st)
                                                  (%mc-frame-marks pframe)))
                   (cap-handlers (%handlers-prefix-before handlers frame))
                   (escape-k (%mc-frame-escape-k pframe)))
              (##continuation-capture
               (lambda (sub-k)
                 (let ((ek (%make-effect-continuation
                            sub-k
                            pframe
                            '()
                            cap-marks
                            cap-handlers
                            frame
                            (make-atomic-fxbox %EC-ONE-SHOT-LIVE))))
                   (%tc-mc-set! st rest)
                   (%tc-marks-set! st (%mc-frame-marks pframe))
                   (%tc-barriers-set! st (%mc-frame-barriers pframe))
                   (%tc-handlers-set! st (%mc-frame-handlers pframe))
                   (cond
                     ((eq? a1 %ABSENT) (##continuation-graft escape-k proc ek))
                     ((eq? a2 %ABSENT) (##continuation-graft escape-k proc ek a1))
                     ((null? more)     (##continuation-graft escape-k proc ek a1 a2))
                     (else             (##continuation-graft escape-k ##apply proc
                                                             (cons ek (cons a1 (cons a2 more))))))))))
            (call-with-values
              (lambda () (%mc-split-at-tag mc tag))
              (lambda (prefix pframe rest)
                (if (not pframe)
                    (error "perform-cap: capability handler prompt not active" cap))
                (if (%barrier-between? (%tc-barriers st)
                                       (%mc-frame-barriers pframe))
                    (error "perform-cap: cannot suspend across continuation barrier" cap))
                (let ((cap-marks (%list-prefix-until (%tc-marks st)
                                                     (%mc-frame-marks pframe)))
                      (cap-handlers (%handlers-prefix-before handlers frame))
                      (escape-k (%mc-frame-escape-k pframe)))
                  (##continuation-capture
                   (lambda (sub-k)
                     (let ((ek (%make-effect-continuation
                                sub-k
                                pframe
                                prefix
                                cap-marks
                                cap-handlers
                                frame
                                (make-atomic-fxbox %EC-ONE-SHOT-LIVE))))
                       (%tc-mc-set! st rest)
                       (%tc-marks-set! st (%mc-frame-marks pframe))
                       (%tc-barriers-set! st (%mc-frame-barriers pframe))
                       (%tc-handlers-set! st (%mc-frame-handlers pframe))
                       (cond
                         ((eq? a1 %ABSENT) (##continuation-graft escape-k proc ek))
                         ((eq? a2 %ABSENT) (##continuation-graft escape-k proc ek a1))
                         ((null? more)     (##continuation-graft escape-k proc ek a1 a2))
                         (else             (##continuation-graft escape-k ##apply proc
                                                                 (cons ek (cons a1 (cons a2 more))))))))))))))))

;;;----------------------------------------------------------------------------
;;; Built-in Direct-Style Generator (yield / make-generator — Zero Per-Yield Closure)

(define yield (make-effect 'yield))

(define (make-generator thunk)
  (let ((state 'init))
    (lambda ()
      (cond
        ((eq? state 'done) #!eof)
        ((eq? state 'init)
         (set! state 'done)
         (with-handler
           ((yield (k val)
              (set! state k)
              val)
            (return: (r)
              (set! state 'done)
              #!eof))
           (thunk)))
        (else
         (let ((k state))
           (set! state 'done)
           (resume k #f)))))))

;;;============================================================================
