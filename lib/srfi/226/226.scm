;;;============================================================================

;;; File: "226.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SRFI 226, Control Features (Phase C2 Native Runtime Fast Path)
;;;
;;; Built directly on Gambit's O(1) zero-copy native continuation primitives
;;; (##continuation-capture, ##continuation-graft, ##continuation-return) and
;;; dedicated per-thread control-state slot (##thread-control-state), with
;;; (srfi 230) atomic-fxbox CAS for linearizable SMP one-shot continuations.

(##supply-module srfi/226)

(##namespace ("srfi/226#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##namespace (""
  dynamic-wind
  make-table
  table-ref
  table-set!
  make-mutex
  mutex-lock!
  mutex-unlock!
  eq?-hash
  error))
(##include "~~lib/srfi/230/230#.scm")
(##include "226#.scm")

(declare
  (standard-bindings)
  (extended-bindings)
  (block))

;;;----------------------------------------------------------------------------
;;; Atomic One-Shot Continuation States (matches formal Quint/Lean/CBMC model)

(define %CONT-ONE-SHOT-LIVE     0)
(define %CONT-ONE-SHOT-CONSUMED 1)
(define %CONT-MULTISHOT-COW     2)

(define %ABSENT (list 'srfi-226-absent))

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
;;; (##thread-control-state / ##thread-control-state-set!): O(1) single load,
;;; zero locks, zero hashing, zero memory leaks, and safe across SMP carrier
;;; thread migrations.

(define-type %mc-frame
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000002
  constructor: %make-mc-frame
  predicate: %mc-frame?
  (kind     %mc-frame-kind)     ;; 'prompt or 'underflow
  (tag      %mc-frame-tag)      ;; prompt-tag (or #f for underflow)
  (handler  %mc-frame-handler)  ;; abort handler proc (or #f)
  (escape-k %mc-frame-escape-k) ;; native Gambit continuation object
  (marks    %mc-frame-marks)    ;; saved marks outside this frame
  (barriers %mc-frame-barriers) ;; saved barriers outside this frame
  (handlers %mc-frame-handlers) ;; saved effect handlers outside this frame
  )

(define-type %tc-state
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000004
  constructor: %make-tc-state
  predicate: %tc-state?
  (mc            %tc-mc            %tc-mc-set!)
  (marks         %tc-marks         %tc-marks-set!)
  (barriers      %tc-barriers      %tc-barriers-set!)
  (handlers      %tc-handlers      %tc-handlers-set!)
  (rewind-escape %tc-rewind-escape %tc-rewind-escape-set!)
  (rewind-frame  %tc-rewind-frame  %tc-rewind-frame-set!))

(define (%tc-current)
  (let ((st (##thread-control-state)))
    (if st
        st
        (let ((fresh (%make-tc-state '() '() '() '() #f #f)))
          (##thread-control-state-set! fresh)
          fresh))))

;;;----------------------------------------------------------------------------
;;; Continuation Mark Sets

(define-type continuation-mark-set
  id: 8B1F3A70-9C24-4D6B-A5E1-226000000003
  constructor: %make-mark-set
  predicate: continuation-mark-set?
  (frames %mark-set-frames))  ;; list of alists from innermost to outermost

;;;----------------------------------------------------------------------------
;;; Sharded Weak Table for SRFI-226 call/1cc Ownership Inspection/Promotion

(define %ONE-SHOT-SHARDS 64)
(define %one-shot-tables
  (let ((v (make-vector %ONE-SHOT-SHARDS #f)))
    (let loop ((i 0))
      (if (fx< i %ONE-SHOT-SHARDS)
          (begin
            (vector-set! v i (make-table test: eq? weak-keys: #t))
            (loop (fx+ i 1)))))
    v))
(define %one-shot-mutexes
  (let ((v (make-vector %ONE-SHOT-SHARDS #f)))
    (let loop ((i 0))
      (if (fx< i %ONE-SHOT-SHARDS)
          (begin
            (vector-set! v i (make-mutex 'srfi-226-one-shot))
            (loop (fx+ i 1)))))
    v))

(define (%register-one-shot! proc state-box)
  (let* ((slot (fxand (eq?-hash proc) (fx- %ONE-SHOT-SHARDS 1)))
         (mtx (vector-ref %one-shot-mutexes slot))
         (tbl (vector-ref %one-shot-tables slot)))
    (mutex-lock! mtx)
    (table-set! tbl proc state-box)
    (mutex-unlock! mtx)
    proc))

(define (%lookup-one-shot-box proc)
  (let* ((slot (fxand (eq?-hash proc) (fx- %ONE-SHOT-SHARDS 1)))
         (mtx (vector-ref %one-shot-mutexes slot))
         (tbl (vector-ref %one-shot-tables slot)))
    (mutex-lock! mtx)
    (let ((box (table-ref tbl proc #f)))
      (mutex-unlock! mtx)
      box)))

(define (one-shot-continuation? obj)
  (and (procedure? obj)
       (if (%lookup-one-shot-box obj) #t #f)))

(define (one-shot-continuation-consumed? obj)
  (let ((box (%lookup-one-shot-box obj)))
    (if box
        (fx= (atomic-fxbox-ref box) %CONT-ONE-SHOT-CONSUMED)
        #f)))

(define (promote-one-shot-continuation! obj)
  (let ((box (%lookup-one-shot-box obj)))
    (if (not box)
        (error "promote-one-shot-continuation!: not a one-shot continuation" obj)
        (let ((prev (atomic-fxbox-compare-and-swap! box
                                                    %CONT-ONE-SHOT-LIVE
                                                    %CONT-MULTISHOT-COW)))
          (cond
            ((fx= prev %CONT-ONE-SHOT-LIVE) #t)
            ((fx= prev %CONT-MULTISHOT-COW) #t)
            (else
             (error "cannot promote consumed one-shot continuation" obj)))))))

;;;----------------------------------------------------------------------------
;;; Internal Metacontinuation Helpers

(define (%default-prompt-handler tag)
  (lambda (thunk)
    (call-with-continuation-prompt thunk tag)))

;; Fast single-value return through topmost metacontinuation frame (zero thunk,
;; zero rest-list, direct ##continuation-return).
(define (%mc-return1 val)
  (let* ((st (%tc-current))
         (mc (%tc-mc st)))
    (if (null? mc)
        val
        (let ((top (car mc))
              (rest (cdr mc)))
          (%tc-mc-set! st rest)
          (%tc-marks-set! st (%mc-frame-marks top))
          (%tc-barriers-set! st (%mc-frame-barriers top))
          (%tc-handlers-set! st (%mc-frame-handlers top))
          (##continuation-return (%mc-frame-escape-k top) val)))))

;; Multi-value return through topmost metacontinuation frame (0/1/2/3/N).
(define (%mc-return-vals #!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
  (let* ((st (%tc-current))
         (mc (%tc-mc st)))
    (if (null? mc)
        (cond
          ((eq? v1 %ABSENT) (values))
          ((eq? v2 %ABSENT) v1)
          ((eq? v3 %ABSENT) (values v1 v2))
          ((null? more) (values v1 v2 v3))
          (else (apply values v1 v2 v3 more)))
        (let ((top (car mc))
              (rest (cdr mc)))
          (%tc-mc-set! st rest)
          (%tc-marks-set! st (%mc-frame-marks top))
          (%tc-barriers-set! st (%mc-frame-barriers top))
          (%tc-handlers-set! st (%mc-frame-handlers top))
          (let ((k (%mc-frame-escape-k top)))
            (cond
              ((eq? v1 %ABSENT) (##continuation-return k))
              ((eq? v2 %ABSENT) (##continuation-return k v1))
              ((eq? v3 %ABSENT) (##continuation-return k v1 v2))
              ((null? more) (##continuation-return k v1 v2 v3))
              (else (##apply ##continuation-return k v1 v2 v3 more))))))))

;; Split mc at the first prompt frame matching tag.
;; Returns (values prefix pframe rest) or (values #f #f #f).
(define (%mc-split-at-tag mc tag)
  (if (and (pair? mc)
           (eq? (%mc-frame-kind (car mc)) 'prompt)
           (eq? (%mc-frame-tag (car mc)) tag))
      (values '() (car mc) (cdr mc))
      (let loop ((cur mc) (rev-prefix '()))
        (cond
          ((null? cur)
           (values #f #f #f))
          ((and (eq? (%mc-frame-kind (car cur)) 'prompt)
                (eq? (%mc-frame-tag (car cur)) tag))
           (values (reverse rev-prefix) (car cur) (cdr cur)))
          (else
           (loop (cdr cur) (cons (car cur) rev-prefix)))))))

(define (%list-prefix-until xs stop-tail)
  (if (eq? xs stop-tail)
      '()
      (let loop ((cur xs) (acc '()))
        (if (or (eq? cur stop-tail) (null? cur))
            (reverse acc)
            (loop (cdr cur) (cons (car cur) acc))))))

(define (%entering-barrier? captured-barriers current-barriers)
  (let loop ((bs captured-barriers))
    (cond
      ((null? bs) #f)
      ((memq (car bs) current-barriers) (loop (cdr bs)))
      (else #t))))

(define (%barrier-between? current-barriers pframe-barriers)
  (not (eq? current-barriers pframe-barriers)))

;;;----------------------------------------------------------------------------
;;; Prompts & Barriers

(define (call-with-continuation-prompt proc
                                       #!optional
                                       (tag %default-prompt-tag)
                                       (handler (%default-prompt-handler tag)))
  (##continuation-capture
   (lambda (escape-k)
     (let* ((st (%tc-current))
            (saved-mc (%tc-mc st))
            (saved-marks (%tc-marks st))
            (saved-barriers (%tc-barriers st))
            (saved-handlers (%tc-handlers st))
            (frame (%make-mc-frame 'prompt
                                   tag
                                   handler
                                   escape-k
                                   saved-marks
                                   saved-barriers
                                   saved-handlers)))
       (%tc-mc-set! st (cons frame saved-mc))
       (call-with-values proc %mc-return-vals)))))

(define (continuation-prompt-available? tag)
  (let loop ((cur (%tc-mc (%tc-current))))
    (cond
      ((null? cur) #f)
      ((and (eq? (%mc-frame-kind (car cur)) 'prompt)
            (eq? (%mc-frame-tag (car cur)) tag))
       #t)
      (else (loop (cdr cur))))))

(define (abort-current-continuation tag
                                    #!optional
                                    (a1 %ABSENT)
                                    (a2 %ABSENT)
                                    (a3 %ABSENT)
                                    #!rest
                                    more)
  (let ((st (%tc-current)))
    (call-with-values
      (lambda () (%mc-split-at-tag (%tc-mc st) tag))
      (lambda (prefix pframe rest)
        (if (not pframe)
            (error "abort-current-continuation: no prompt found for tag" tag)
            (let ((escape-k (%mc-frame-escape-k pframe))
                  (handler (%mc-frame-handler pframe)))
              (%tc-mc-set! st rest)
              (%tc-marks-set! st (%mc-frame-marks pframe))
              (%tc-barriers-set! st (%mc-frame-barriers pframe))
              (%tc-handlers-set! st (%mc-frame-handlers pframe))
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
                                       (cons a1 (cons a2 (cons a3 more))))))))))))

(define (call-with-continuation-barrier thunk)
  (let* ((st (%tc-current))
         (barrier-token (list 'continuation-barrier))
         (saved-barriers (%tc-barriers st))
         (new-barriers (cons barrier-token saved-barriers)))
    (dynamic-wind
      (lambda () (%tc-barriers-set! (%tc-current) new-barriers))
      thunk
      (lambda () (%tc-barriers-set! (%tc-current) saved-barriers)))))

;;;----------------------------------------------------------------------------
;;; Composable & Non-Composable Delimited Continuations (Zero-Copy Native)

(define (call-with-composable-continuation proc
                                           #!optional
                                           (tag %default-prompt-tag))
  (let ((st (%tc-current)))
    (call-with-values
      (lambda () (%mc-split-at-tag (%tc-mc st) tag))
      (lambda (prefix pframe rest)
        (if (not pframe)
            (error "call-with-composable-continuation: no prompt found for tag" tag))
        (if (%barrier-between? (%tc-barriers st) (%mc-frame-barriers pframe))
            (error "call-with-composable-continuation: cannot capture across continuation barrier" tag))
        (let ((captured-marks (%list-prefix-until (%tc-marks st) (%mc-frame-marks pframe)))
              (captured-handlers (%list-prefix-until (%tc-handlers st) (%mc-frame-handlers pframe))))
          (##continuation-capture
           (lambda (sub-k)
             (let ((composable-k
                    (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
                      (##continuation-capture
                       (lambda (caller-k)
                         (let* ((cst (%tc-current))
                                (caller-mc (%tc-mc cst))
                                (caller-marks (%tc-marks cst))
                                (caller-barriers (%tc-barriers cst))
                                (caller-handlers (%tc-handlers cst))
                                (uframe (%make-mc-frame 'underflow
                                                        #f
                                                        #f
                                                        caller-k
                                                        caller-marks
                                                        caller-barriers
                                                        caller-handlers)))
                           (%tc-mc-set! cst
                                        (if (null? prefix)
                                            (cons uframe caller-mc)
                                            (append prefix (cons uframe caller-mc))))
                           (%tc-marks-set! cst
                                           (if (null? captured-marks)
                                               caller-marks
                                               (append captured-marks caller-marks)))
                           (%tc-barriers-set! cst caller-barriers)
                           (%tc-handlers-set! cst
                                              (if (null? captured-handlers)
                                                  caller-handlers
                                                  (append captured-handlers caller-handlers)))
                           (cond
                             ((eq? v1 %ABSENT) (##continuation-return sub-k))
                             ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
                             ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
                             ((null? more) (##continuation-return sub-k v1 v2 v3))
                             (else (##apply ##continuation-return sub-k v1 v2 v3 more)))))))))
               (proc composable-k)))))))))

(define (call-with-non-composable-continuation proc
                                               #!optional
                                               (tag %default-prompt-tag))
  (let ((st (%tc-current)))
    (call-with-values
      (lambda () (%mc-split-at-tag (%tc-mc st) tag))
      (lambda (prefix pframe rest)
        (if (not pframe)
            (error "call-with-non-composable-continuation: no prompt found for tag" tag))
        (let ((captured-marks (%list-prefix-until (%tc-marks st) (%mc-frame-marks pframe)))
              (captured-barriers (%tc-barriers st))
              (captured-handlers (%list-prefix-until (%tc-handlers st) (%mc-frame-handlers pframe))))
          (##continuation-capture
           (lambda (sub-k)
             (let ((noncomp-k
                    (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
                      (let ((cst (%tc-current)))
                        (if (%entering-barrier? captured-barriers (%tc-barriers cst))
                            (error "continuation invocation blocked by continuation barrier"))
                        (call-with-values
                          (lambda () (%mc-split-at-tag (%tc-mc cst) tag))
                          (lambda (cur-prefix cur-pframe cur-rest)
                            (if (not cur-pframe)
                                (error "non-composable continuation: target prompt not active" tag))
                            (%tc-mc-set! cst
                                         (if (null? prefix)
                                             (cons cur-pframe cur-rest)
                                             (append prefix (cons cur-pframe cur-rest))))
                            (%tc-marks-set! cst
                                            (if (null? captured-marks)
                                                (%mc-frame-marks cur-pframe)
                                                (append captured-marks (%mc-frame-marks cur-pframe))))
                            (%tc-barriers-set! cst captured-barriers)
                            (%tc-handlers-set! cst
                                               (if (null? captured-handlers)
                                                   (%mc-frame-handlers cur-pframe)
                                                   (append captured-handlers (%mc-frame-handlers cur-pframe))))
                            (cond
                              ((eq? v1 %ABSENT) (##continuation-return sub-k))
                              ((eq? v2 %ABSENT) (##continuation-return sub-k v1))
                              ((eq? v3 %ABSENT) (##continuation-return sub-k v1 v2))
                              ((null? more) (##continuation-return sub-k v1 v2 v3))
                              (else (##apply ##continuation-return sub-k v1 v2 v3 more)))))))))
               (proc noncomp-k)))))))))

;;;----------------------------------------------------------------------------
;;; Atomic One-Shot Continuations (call/1cc & composable one-shot)

(define (%wrap-one-shot raw-k)
  (let ((state-box (make-atomic-fxbox %CONT-ONE-SHOT-LIVE)))
    (let ((guarded-k
           (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
             (let ((prev (atomic-fxbox-compare-and-swap! state-box
                                                         %CONT-ONE-SHOT-LIVE
                                                         %CONT-ONE-SHOT-CONSUMED)))
               (if (or (fx= prev %CONT-ONE-SHOT-LIVE)
                       (fx= prev %CONT-MULTISHOT-COW))
                   (cond
                     ((eq? v1 %ABSENT) (raw-k))
                     ((eq? v2 %ABSENT) (raw-k v1))
                     ((eq? v3 %ABSENT) (raw-k v1 v2))
                     ((null? more) (raw-k v1 v2 v3))
                     (else (apply raw-k v1 v2 v3 more)))
                   (error "one-shot continuation already consumed"))))))
      (%register-one-shot! guarded-k state-box))))

(define (call/1cc proc #!optional (tag %default-prompt-tag))
  (if (continuation-prompt-available? tag)
      (call-with-non-composable-continuation
       (lambda (raw-k)
         (proc (%wrap-one-shot raw-k)))
       tag)
      (let ((captured-barriers (%tc-barriers (%tc-current))))
        (##continuation-capture
         (lambda (raw-k)
           (proc (%wrap-one-shot
                  (lambda (#!optional (v1 %ABSENT) (v2 %ABSENT) (v3 %ABSENT) #!rest more)
                    (if (%entering-barrier? captured-barriers (%tc-barriers (%tc-current)))
                        (error "continuation invocation blocked by continuation barrier"))
                    (cond
                      ((eq? v1 %ABSENT) (##continuation-return raw-k))
                      ((eq? v2 %ABSENT) (##continuation-return raw-k v1))
                      ((eq? v3 %ABSENT) (##continuation-return raw-k v1 v2))
                      ((null? more) (##continuation-return raw-k v1 v2 v3))
                      (else (##apply ##continuation-return raw-k v1 v2 v3 more)))))))))))

(define (call-with-one-shot-composable-continuation proc
                                                    #!optional
                                                    (tag %default-prompt-tag))
  (call-with-composable-continuation
   (lambda (raw-k)
     (proc (%wrap-one-shot raw-k)))
   tag))

;;;----------------------------------------------------------------------------
;;; Continuation Marks

(define (%call-with-continuation-mark key val thunk)
  (let* ((st (%tc-current))
         (old-marks (%tc-marks st))
         (new-marks (cons (list (cons key val)) old-marks)))
    (dynamic-wind
      (lambda () (%tc-marks-set! (%tc-current) new-marks))
      thunk
      (lambda () (%tc-marks-set! (%tc-current) old-marks)))))

(define (current-continuation-marks #!optional (tag %default-prompt-tag))
  (let ((st (%tc-current)))
    (call-with-values
      (lambda () (%mc-split-at-tag (%tc-mc st) tag))
      (lambda (prefix pframe rest)
        (if pframe
            (%make-mark-set (%list-prefix-until (%tc-marks st) (%mc-frame-marks pframe)))
            (%make-mark-set (%tc-marks st)))))))

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
  (let ((ms (%tc-marks (%tc-current))))
    (if (null? ms)
        (proc default)
        (let ((entry (assq key (car ms))))
          (proc (if entry (cdr entry) default))))))

;;;============================================================================
