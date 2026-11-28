;;;============================================================================

;;; File: "future.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; SATB-Safe Single-Allocation Futures with Eager Thunk Clearing & Helping

(##define-type ws-future
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000003
  type-exhibitor: macro-type-ws-future
  constructor: macro-make-ws-future
  implementer: implement-type-ws-future
  macros:
  prefix: macro-
  opaque:
  (pool  read-only: unprintable:)
  (thunk unprintable:)
  (state unprintable:))
(implement-type-ws-future)

;; Inline C23 GC-barriered atomic slot ops on ws-future fields (zero wrapper alloc,
;; exact SATB pre-write shading on overwritten heap values).
(define (%future-state-load-acq f)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___gc_atomic_slot_load(&___f[3], 1);"
    f)
   (atomic-box-ref (macro-ws-future-state f) 'acquire)))

(define (%future-state-cas-acqrel! f expected desired)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     ___RESULT = ___gc_atomic_slot_cas(
       ___ps, ___ARG1, &___f[3], ___ARG2, ___ARG3, 3,
       ___EXT(___gc_write_barrier_slow),
       ___EXT(___gc_satb_barrier_val));"
    f expected desired)
   (atomic-box-compare-and-swap! (macro-ws-future-state f) expected desired 'acquire-release)))

(define (%future-state-store-rel! f val)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     (void)___gc_atomic_slot_exchange(
       ___ps, ___ARG1, &___f[3], ___ARG2, 2,
       ___EXT(___gc_write_barrier_slow),
       ___EXT(___gc_satb_barrier_val));
     ___RESULT = ___VOID;"
    f val)
   (atomic-box-set! (macro-ws-future-state f) val 'release)))

(define (%future-thunk-clear! f)
  (macro-if-c-compiled
   (##c-code
    "___WORD *___f = ___BODY_AS(___ARG1, ___tSTRUCTURE);
     (void)___gc_atomic_slot_exchange(
       ___ps, ___ARG1, &___f[2], ___FAL, 2,
       ___EXT(___gc_write_barrier_slow),
       ___EXT(___gc_satb_barrier_val));
     ___RESULT = ___VOID;"
    f)
   (macro-ws-future-thunk-set! f #f)))

(define (%make-future-state)
  (macro-if-c-compiled
   pending-sentinel
   (make-atomic-box pending-sentinel)))

(define (future? obj)
  (macro-ws-future? obj))

(define (future-ready? f)
  (if (not (macro-ws-future? f))
      (error "future-ready?: expected future" f))
  (##pair? (%future-state-load-acq f)))

(define %future-aborted-error
  (with-exception-catcher
   (lambda (e) e)
   (lambda () (error "future aborted by non-local control escape"))))

;; O(1) dynamic guard removal from the current thread's metacontinuation stack.
(define (%parallel-pop-guard! guard-frame)
  (let ((tc (macro-thread-control-state (##current-thread))))
    (if tc
        (let ((mc (%tc-mc tc)))
          (if (##pair? mc)
              (if (##eq? (##car mc) guard-frame)
                  (%tc-mc-set! tc (##cdr mc))
                  (let loop ((cur mc) (acc '()))
                    (cond
                      ((##null? cur) #!void)
                      ((##eq? (##car cur) guard-frame)
                       (%tc-mc-set! tc (append (reverse acc) (##cdr cur))))
                      (else
                       (loop (##cdr cur) (##cons (##car cur) acc)))))))))))

(define (future-run-once! f)
  (let* ((self (##current-thread))
         (prev (%future-state-cas-acqrel! f pending-sentinel self)))
    (if (##eq? prev pending-sentinel)
        (let* ((th (macro-ws-future-thunk f))
               (done-box (##cons #f #f))
               (tc (macro-thread-control-state self))
               (guard-frame
                (if (and tc (##pair? (%tc-mc tc)))
                    (let ((gf (%make-mc-frame-9
                               'unwind-guard
                               #f
                               #t
                               #f
                               (%tc-marks tc)
                               (%tc-barriers tc)
                               (%tc-handlers tc)
                               #f
                               (lambda (phase)
                                 (if (and (##eq? phase 'unwind)
                                          (not (##car done-box)))
                                     (begin
                                       (##set-car! done-box #t)
                                       (%future-state-store-rel!
                                        f (##cons 'err %future-aborted-error))))))))
                      (%tc-mc-set! tc (##cons gf (%tc-mc tc)))
                      gf)
                    #f)))
          ;; Eagerly drop thunk reference with SATB shade so captured closure
          ;; data can be collected while or immediately after thunk executes.
          (%future-thunk-clear! f)
          (let ((result
                 (with-exception-catcher
                  (lambda (exc) (##cons 'err exc))
                  (lambda () (##cons 'ok (th))))))
            (if guard-frame (%parallel-pop-guard! guard-frame))
            (if (not (##car done-box))
                (begin
                  (##set-car! done-box #t)
                  (%future-state-store-rel! f result)))
            #t))
        #f)))

(define (make-future thunk #!optional (pool #f))
  (if (not (##procedure? thunk))
      (error "make-future: expected procedure" thunk))
  (if (and pool (not (macro-work-stealing-pool? pool)))
      (error "make-future: expected work-stealing-pool or #f" pool))
  (let* ((p (if (macro-work-stealing-pool? pool) pool (get-active-pool)))
         (f (macro-make-ws-future p thunk (%make-future-state))))
    ;; Push future directly (zero wrapper closure allocation!).
    (pool-submit! p f)
    f))

(define (future-force f)
  (if (not (macro-ws-future? f))
      (error "future-force: expected future" f))
  (let ((pool (macro-ws-future-pool f))
        (self (##current-thread)))
    ;; Fast path: already completed or self-reentrant cycle.
    (let ((st0 (%future-state-load-acq f)))
      (cond
        ((##pair? st0)
         (if (##eq? (##car st0) 'ok) (##cdr st0) (raise (##cdr st0))))
        ((##eq? st0 self)
         (error "future-force: reentrant cycle detected" f))
        (else
         ;; Try claiming & running this future directly (zero-deadlock helping!).
         (future-run-once! f)
         ;; While another thread is running this future, help execute work!
         (let* ((wb (current-worker-binding))
                (self-id (if (and (##pair? wb) (##eq? (##car wb) pool))
                             (##cdr wb)
                             #f))
                (n (macro-work-stealing-pool-nworkers pool)))
           (let wait ((cursor 0) (spins 0))
             (let ((st (%future-state-load-acq f)))
               (cond
                 ((##pair? st)
                  (if (##eq? (##car st) 'ok) (##cdr st) (raise (##cdr st))))
                 ((##eq? st self)
                  (error "future-force: reentrant cycle detected" f))
                 (else
                  (let ((task (pool-try-get-task pool self-id cursor)))
                    (if (##not (##eq? task empty-sentinel))
                        (begin
                          (pool-run-task! task)
                          (wait (##fxremainder (##fx+ cursor 1) n) 0))
                        (if (##fx< spins 16)
                            (begin
                              (%cpu-pause!)
                              (wait (##fxremainder (##fx+ cursor 1) n) (##fx+ spins 1)))
                            (begin
                              (thread-yield!)
                              (wait (##fxremainder (##fx+ cursor 1) n) 0)))))))))))))))

(define (force-future f)
  (future-force f))

;;;============================================================================
