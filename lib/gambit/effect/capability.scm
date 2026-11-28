;;;============================================================================

;;; File: "capability.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles
;;; with scope-bound exception-unwind coherency.

(define (%cap-pop-guard! guard-frame)
  (let* ((st (%tc-fast))
         (mc (%st-mc st)))
    (if (pair? mc)
        (if (eq? (car mc) guard-frame)
            (%st-mc-set! st (cdr mc))
            (let loop ((cur mc) (acc '()))
              (cond
                ((null? cur) #!void)
                ((eq? (car cur) guard-frame)
                 (%st-mc-set! st (append (reverse acc) (cdr cur))))
                (else
                 (loop (cdr cur) (cons (car cur) acc)))))))))

;; Split `cur-h` at the creation-site `outer-handlers` boundary.
;; Returns `(values prefix target-h)` where `target-h` is the handler stack
;; active during the capability body and `prefix` is the paused inner handler
;; prefix to splice back on return (or `#f` if `outer-handlers` is not present
;; in `cur-h`).
(define (%cap-split-handlers cur-h outer-handlers)
  (if (null? outer-handlers)
      (values cur-h '())
      (let ((top-frame (car outer-handlers)))
        (let loop ((p cur-h) (acc '()))
          (cond
            ((null? p)
             (values #f outer-handlers))
            ((eq? (car p) top-frame)
             (values (reverse acc) p))
            (else
             (loop (cdr p) (cons (car p) acc))))))))

(define (call-with-tail-capability handler-proc body-proc)
  (if (not (procedure? handler-proc))
      (error "call-with-tail-capability: expected procedure" handler-proc))
  (if (not (procedure? body-proc))
      (error "call-with-tail-capability: expected procedure" body-proc))
  (let* ((st (macro-thread-control-state (##current-thread)))
         (outer-handlers (if st (%st-handlers st) '()))
         (live-box (cons #t outer-handlers))
         (cap (%make-capability 'tail handler-proc live-box))
         (cur-eh (macro-current-exception-handler))
         (guard-frame
          (if (and st (pair? (%st-mc st)))
              (let ((gf (%make-mc-frame-9
                         'unwind-guard
                         #f
                         #t
                         #f
                         (%st-marks st)
                         (%st-barriers st)
                         (%st-handlers st)
                         #f
                         (lambda (phase)
                           (set-car! live-box (eq? phase 'restore))))))
                (%st-mc-set! st (cons gf (%st-mc st)))
                gf)
              #f)))
    (if (and guard-frame (%mc-eh-trampoline? cur-eh))
        (let ((r (body-proc cap)))
          (%cap-pop-guard! guard-frame)
          (set-car! live-box #f)
          r)
        (macro-dynamic-bind
         exception-handler
         (lambda (exc)
           (let ((prev (car live-box))
                 (saved-mc #f))
             (set-car! live-box #f)
             (if guard-frame
                 (let ((cst (%tc-fast)))
                   (set! saved-mc (%st-mc cst))
                   (%cap-pop-guard! guard-frame)))
             (let ((r (macro-dynamic-bind
                       exception-handler
                       cur-eh
                       (lambda () (cur-eh exc)))))
               (if guard-frame
                   (%st-mc-set! (%tc-fast) saved-mc))
               (set-car! live-box prev)
               r)))
         (lambda ()
           (let ((r (body-proc cap)))
             (if guard-frame (%cap-pop-guard! guard-frame))
             (set-car! live-box #f)
             r))))))

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
      ;; O(1) direct dispatch with lexical scope liveness guard and creation-site
      ;; dynamic handler scope isolation: zero mutation/allocation when no inner
      ;; handlers intervene; otherwise temporarily shifts `st.handlers` to the
      ;; creation-site scope and splices any paused inner prefix back on return.
      (let ((live-box (%cap-frame cap)))
        (if (not (car live-box))
            (error "perform-cap: capability handler no longer active" cap))
        (let* ((proc (%cap-proc cap))
               (outer-handlers (cdr live-box))
               (st (macro-thread-control-state (##current-thread)))
               (cur-h (if st (%st-handlers st) '())))
          (if (eq? cur-h outer-handlers)
              (cond
                ((eq? a1 %ABSENT) (proc))
                ((eq? a2 %ABSENT) (proc a1))
                ((null? more)     (proc a1 a2))
                (else             (apply proc a1 a2 more)))
              (call-with-values
                (lambda () (%cap-split-handlers cur-h outer-handlers))
                (lambda (prefix target-h)
                  (if (eq? target-h cur-h)
                      (cond
                        ((eq? a1 %ABSENT) (proc))
                        ((eq? a2 %ABSENT) (proc a1))
                        ((null? more)     (proc a1 a2))
                        (else             (apply proc a1 a2 more)))
                      (let ((st2 (or st (%tc-fast)))
                            (cur-eh (macro-current-exception-handler)))
                        (%st-handlers-set! st2 target-h)
                        (let ((res
                               (if (%mc-eh-trampoline? cur-eh)
                                   (cond
                                     ((eq? a1 %ABSENT) (proc))
                                     ((eq? a2 %ABSENT) (proc a1))
                                     ((null? more)     (proc a1 a2))
                                     (else             (apply proc a1 a2 more)))
                                   (macro-dynamic-bind
                                    exception-handler
                                    (lambda (exc)
                                      (let* ((cst (%tc-fast))
                                             (saved-h (%st-handlers cst)))
                                        (%st-handlers-set!
                                         cst
                                         (if (eq? saved-h target-h)
                                             cur-h
                                             (if prefix
                                                 (append prefix saved-h)
                                                 saved-h)))
                                        (let ((r (macro-dynamic-bind
                                                  exception-handler
                                                  cur-eh
                                                  (lambda () (cur-eh exc)))))
                                          (%st-handlers-set! (%tc-fast) saved-h)
                                          r)))
                                    (lambda ()
                                      (cond
                                        ((eq? a1 %ABSENT) (proc))
                                        ((eq? a2 %ABSENT) (proc a1))
                                        ((null? more)     (proc a1 a2))
                                        (else             (apply proc a1 a2 more))))))))
                          (let* ((cst (%tc-fast))
                                 (after-h (%st-handlers cst)))
                            (%st-handlers-set!
                             cst
                             (if (eq? after-h target-h)
                                 cur-h
                                 (if prefix
                                     (append prefix after-h)
                                     after-h))))
                          res))))))))
      ;; Direct suspending capability dispatch (zero-closure capture)
      (let* ((st (%tc-fast))
             (frame (%cap-frame cap))
             (handlers (%st-handlers st)))
        (%perform-suspend-dispatch st handlers frame (%cap-proc cap) a1 a2 more))))

;;;============================================================================
