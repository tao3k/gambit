;;;============================================================================

;;; File: "marks.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; True O(1) Tail-Call-Preserving Continuation Marks & Captured-Continuation
;;; Mark Inspection (`with-continuation-mark`, `current-continuation-marks`,
;;; `continuation-marks`, `continuation-mark-set->list*`,
;;; `call-with-immediate-continuation-mark`) for `(srfi 226)`.
;;;
;;; Each entry on `st.marks` is an immutable `(fid . alist)` pair where `fid`
;;; identifies the dynamic `with-continuation-mark` frame and is preserved
;;; across tail-position mark replacements. Exception unwinding pops by `fid`
;;; on the invoking thread's current control state so composable continuation
;;; replay (same-thread or cross-thread) preserves resumer marks and never
;;; mutates another thread's state.

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

;; O(1) dynamic mark-frame pop by frame identity (`fid`). Fast-paths the top
;; frame in a single pointer compare; unwinds any unpopped inner mark frames
;; above `fid`, and leaves `ms` untouched if `fid` is absent.
(define (%pop-mark-frame-by-id ms fid)
  (if (null? ms)
      ms
      (if (eq? (caar ms) fid)
          (cdr ms)
          (let loop ((cur (cdr ms)))
            (cond
              ((null? cur) ms)
              ((eq? (caar cur) fid) (cdr cur))
              (else (loop (cdr cur))))))))

(define (%mark-pop-frame res)
  (let* ((st (%tc-current))
         (ms (%st-marks st)))
    (if (pair? ms)
        (%st-marks-set! st (cdr ms)))
    res))

(define (%mark-push-and-run! st ms fid kv thunk)
  (##declare (not inline))
  (%st-marks-set! st (cons (cons fid (list kv)) ms))
  (%mark-pop-frame (thunk)))

(define (%mark-dispatch caller-r0 kv thunk)
  (let* ((st (%tc-current))
         (ms (%st-marks st))
         (key (car kv))
         (val (cdr kv)))
    (if (and %mark-pop-ra (eq? caller-r0 %mark-pop-ra) (pair? ms))
        (let ((top (car ms)))
          (%st-marks-set!
           st
           (cons (cons (car top) (%alist-replace (cdr top) key val))
                 (cdr ms)))
          (thunk))
        (let ((cur-eh (macro-current-exception-handler)))
          (if (%mc-eh-trampoline? cur-eh)
              (%mark-push-and-run! st ms kv kv thunk)
              (macro-dynamic-bind
               exception-handler
               (lambda (exc)
                 (let* ((cst (%tc-current))
                        (saved (%st-marks cst))
                        (rest (%pop-mark-frame-by-id saved kv)))
                   (%st-marks-set! cst rest)
                   (let ((res (macro-dynamic-bind
                               exception-handler
                               cur-eh
                               (lambda () (cur-eh exc)))))
                     (%st-marks-set! (%tc-current) saved)
                     res)))
               (lambda ()
                 (%mark-push-and-run! st ms kv kv thunk))))))))

(define (%call-with-continuation-mark key val thunk)
  (##tail-call-with-r0 %mark-dispatch (cons key val) thunk))

;; Capture the exact Gambit C return label of `(thunk)` inside `%mark-push-and-run!`
;; once at module load time so tail-recursive `with-continuation-mark` and
;; `call-with-immediate-continuation-mark` are O(1) and tail-exact.
(%call-with-continuation-mark
 '%srfi226-init
 #t
 (lambda ()
   (##tail-call-with-r0
    (lambda (r0 _ __) (set! %mark-pop-ra r0))
    #f
    #f)))

(define (%marks-tail-matches-prefix? xs stop)
  (let loop ((a xs) (b stop))
    (cond
      ((null? a) #t)
      ((null? b) #f)
      ((eq? (car a) (car b)) (loop (cdr a) (cdr b)))
      (else #f))))

;; Exact prompt-tag mark slicing on captured continuations (handles both raw
;; tail-shared mark lists and copied composable/non-composable mark prefixes,
;; including nested multi-shot self-replay with repeated frames).
(define (%marks-slice-until-stop marks stop)
  (if (null? stop)
      marks
      (let loop ((xs marks) (acc '()))
        (cond
          ((null? xs) marks)
          ((or (eq? xs stop) (%marks-tail-matches-prefix? xs stop))
           (reverse acc))
          (else
           (loop (cdr xs) (cons (car xs) acc)))))))

(define (current-continuation-marks #!optional (tag %default-prompt-tag))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "current-continuation-marks: expected continuation-prompt-tag" tag))
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
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "continuation-marks: expected continuation-prompt-tag" tag))
  (cond
    ((continuation-mark-set? cont) cont)
    ((%extract-any-cont-cell cont)
     => (lambda (cell)
          (let* ((marks (%osc-marks-fast cell))
                 (prefix (%osc-prefix-fast cell)))
            (if (or (null? marks) (null? prefix))
                (%make-mark-set marks)
                (let ((found (%mc-find-tail-slow prefix tag)))
                  (if found
                      (%make-mark-set
                       (%marks-slice-until-stop marks (%pf-marks (cadr found))))
                      (%make-mark-set marks)))))))
    ((or (not cont) (##continuation? cont))
     (current-continuation-marks tag))
    (else
     (error "continuation-marks: expected continuation or continuation-mark-set" cont))))

(define (continuation-mark-set->list mark-set key #!optional (tag %default-prompt-tag))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "continuation-mark-set->list: expected continuation-prompt-tag" tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (continuation-marks mark-set tag)))))
    (let loop ((fs frames) (acc '()))
      (if (null? fs)
          (reverse acc)
          (let ((entry (assq key (cdar fs))))
            (loop (cdr fs)
                  (if entry (cons (cdr entry) acc) acc)))))))

(define (continuation-mark-set->list* mark-set key-list
                                      #!optional
                                      (none-v #f)
                                      (tag %default-prompt-tag))
  (if (not (list? key-list))
      (error "continuation-mark-set->list*: expected proper list of keys" key-list))
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "continuation-mark-set->list*: expected continuation-prompt-tag" tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (continuation-marks mark-set tag))))
        (n (length key-list)))
    (let loop ((fs frames) (acc '()))
      (if (null? fs)
          (reverse acc)
          (let ((alist (cdar fs))
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
  (if (not (or (eq? tag %default-prompt-tag) (continuation-prompt-tag? tag)))
      (error "continuation-mark-set-first: expected continuation-prompt-tag" tag))
  (let ((frames (if (continuation-mark-set? mark-set)
                    (%mark-set-frames mark-set)
                    (%mark-set-frames (continuation-marks mark-set tag)))))
    (let loop ((fs frames))
      (if (null? fs)
          none-v
          (let ((entry (assq key (cdar fs))))
            (if entry
                (cdr entry)
                (loop (cdr fs))))))))

(define (%immediate-mark-dispatch-default-f caller-r0 key proc)
  (let* ((st (%tc-current))
         (ms (%st-marks st)))
    (if (and %mark-pop-ra (eq? caller-r0 %mark-pop-ra) (pair? ms))
        (let ((entry (assq key (cdar ms))))
          (proc (if entry (cdr entry) #f)))
        (proc #f))))

(define (%immediate-mark-dispatch caller-r0 kd proc)
  (let* ((st (%tc-current))
         (ms (%st-marks st))
         (key (car kd))
         (default (cdr kd)))
    (if (and %mark-pop-ra (eq? caller-r0 %mark-pop-ra) (pair? ms))
        (let ((entry (assq key (cdar ms))))
          (proc (if entry (cdr entry) default)))
        (proc default))))

(define (call-with-immediate-continuation-mark key proc #!optional (default #f))
  (if (not (procedure? proc))
      (error "call-with-immediate-continuation-mark: expected procedure" proc))
  (if (eq? default #f)
      (##tail-call-with-r0 %immediate-mark-dispatch-default-f key proc)
      (##tail-call-with-r0 %immediate-mark-dispatch (cons key default) proc)))

;;;============================================================================
