;;;============================================================================

;;; File: "capability.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles
;;; with scope-bound exception-unwind coherency.

(define (call-with-tail-capability handler-proc body-proc)
  (if (not (procedure? handler-proc))
      (error "call-with-tail-capability: expected procedure" handler-proc))
  (if (not (procedure? body-proc))
      (error "call-with-tail-capability: expected procedure" body-proc))
  (body-proc (%make-capability 'tail handler-proc #f)))

(define (%install-cap-cont! escape-k cap body-proc)
  (let* ((st (%tc-fast))
         (frame (%cap-frame cap))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   tag
                                   #f
                                   escape-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers
                                   #f
                                   #f)))
    (%st-mc-set! st (cons pframe saved-mc))
    (%st-handlers-set! st (cons frame saved-handlers))
    (%mc-return1 (body-proc cap))))

(define (%install-cap-cont-scoped! escape-k cap body-proc)
  (let* ((st (%tc-fast))
         (tramp (macro-current-exception-handler))
         (frame (%cap-frame cap))
         (tag (%frame-tag frame))
         (saved-mc (%st-mc st))
         (saved-marks (%st-marks st))
         (saved-barriers (%st-barriers st))
         (saved-handlers (%st-handlers st))
         (pframe (%make-mc-frame-9 'prompt
                                   tag
                                   #f
                                   escape-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers
                                   tramp
                                   #f)))
    (%st-mc-set! st (cons pframe saved-mc))
    (%st-handlers-set! st (cons frame saved-handlers))
    (%mc-return1 (body-proc cap))))

(define (call-with-suspend-capability handler-proc body-proc)
  (if (not (procedure? handler-proc))
      (error "call-with-suspend-capability: expected procedure" handler-proc))
  (if (not (procedure? body-proc))
      (error "call-with-suspend-capability: expected procedure" body-proc))
  (let* ((eff (%make-effect 'capability))
         (tag (make-continuation-prompt-tag 'cap-handler))
         (entry (%make-handler-entry eff 'suspend handler-proc))
         (frame (%make-handler-frame tag (list entry)))
         (cap (%make-capability 'suspend handler-proc frame))
         (cur-eh (macro-current-exception-handler)))
    (if (%mc-eh-trampoline? cur-eh)
        (##continuation-capture %install-cap-cont! cap body-proc)
        (let* ((st (%tc-fast))
               (cur-denv (macro-thread-denv (macro-current-thread)))
               (tdenv (%mc-ensure-tramp-denv st cur-denv cur-eh)))
          (##dynamic-env-bind
           tdenv
           (lambda ()
             (##continuation-capture %install-cap-cont-scoped! cap body-proc)))))))

(define (perform-cap cap
                     #!optional
                     (a1 %ABSENT)
                     (a2 %ABSENT)
                     #!rest
                     more)
  (if (not (effect-capability? cap))
      (error "perform-cap: expected effect-capability" cap))
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

;;;============================================================================
