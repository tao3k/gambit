;;;============================================================================

;;; File: "nursery.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Structured Concurrency Nursery & Batched Completion Credit

;;;----------------------------------------------------------------------------
;;; Structured Concurrency Nursery
;;; (Zero-Capture Children via ##with-exception-handler + Unwind-Safe Abort)

(define-type nursery
  id: 8B1F3A70-9C24-4D6B-A5E1-F1B000000003
  constructor: %make-nursery
  predicate: nursery?
  (sched       %nursery-sched)
  (active      %nursery-active)      ;; 128B-padded fxatom (isolated from lock/waiter-k)
  (lock        %nursery-lock)        ;; fxatom spinlock
  (waiter-k    %nursery-waiter-k     %nursery-waiter-k-set!)
  (first-err   %nursery-first-err    %nursery-first-err-set!)
  (has-err?    %nursery-has-err?     %nursery-has-err?-set!)
  (err-handler %nursery-err-handler  %nursery-err-handler-set!))

(define (%nursery-record-error! n exc)
  (%spin-lock! (%nursery-lock n))
  (if (not (%nursery-has-err? n))
      (begin
        (%nursery-has-err?-set! n #t)
        (%nursery-first-err-set! n exc)))
  (%spin-unlock! (%nursery-lock n)))

(define (%nursery-sub-active! n cnt)
  (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) cnt)))
    (if (fx= prev cnt)
        (let ((lock (%nursery-lock n))
              (wk #f))
          (%spin-lock! lock)
          (set! wk (%nursery-waiter-k n))
          (%nursery-waiter-k-set! n #f)
          (%spin-unlock! lock)
          (if wk
              (begin
                (%fk-val-set! wk #!void)
                (%sched-wake! (%nursery-sched n) wk)))))))

(define (%nursery-flush! ctx)
  (let ((cnt (%wctx-nursery-batch ctx)))
    (if (fx> cnt 0)
        (let ((n (%wctx-nursery-cur ctx)))
          (%wctx-nursery-batch-set! ctx 0)
          (%wctx-nursery-cur-set! ctx #f)
          (%nursery-sub-active! n cnt)))))

(define (%nursery-child-done-batched! ctx n)
  (let ((cur (%wctx-nursery-cur ctx)))
    (if (eq? cur n)
        (let ((cnt (fx+ (%wctx-nursery-batch ctx) 1)))
          (if (fx>= cnt %MAX-NURSERY-BATCH)
              (begin
                (%wctx-nursery-batch-set! ctx 0)
                (%wctx-nursery-cur-set! ctx #f)
                (%nursery-sub-active! n cnt))
              (%wctx-nursery-batch-set! ctx cnt)))
        (begin
          (if cur (%nursery-flush! ctx))
          (%wctx-nursery-cur-set! ctx n)
          (%wctx-nursery-batch-set! ctx 1)))))

;; Executed on the clean carrier trampoline AFTER ##continuation-graft has
;; completed all dynamic-wind after thunks of the aborting child fiber.
(define (%nursery-child-abort! n exc)
  (let ((cur-ctx (%current-wctx)))
    (%nursery-flush! cur-ctx)
    (%nursery-record-error! n exc)
    (%nursery-sub-active! n 1)
    (if (%get-tc) (%set-tc! #f))
    (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
    (%worker-dispatch cur-ctx 0)))

;; Zero-closure multi-arg continuation receiver for nursery join park
(define (%park-nursery-cont! raw-k n)
  (let* ((ctx (%current-wctx))
         (tc (%get-tc))
         (fk (%alloc-fk! ctx raw-k tc #!void))
         (lock (%nursery-lock n))
         (wake-now? #f))
    (%nursery-flush! ctx)
    (if tc (%set-tc! #f))
    (%spin-lock! lock)
    (if (fx= (%fxatom-load-acq (%nursery-active n)) 0)
        (set! wake-now? #t)
        (%nursery-waiter-k-set! n fk))
    (%spin-unlock! lock)
    (if wake-now?
        (%sched-push-lifo! ctx fk))
    (%sched-switch-next! ctx)))

(define (with-nursery proc)
  (if (not (procedure? proc))
      (error "with-nursery: expected procedure" proc))
  (let* ((ctx (%current-wctx))
         (sched (%wctx-sched ctx))
         (n (%make-nursery sched
                           (%make-padded-fxatom 1)
                           (%make-fxatom 0)
                           #f
                           #f
                           #f
                           #f))
         (child-eh (lambda (e)
                     (let ((cur-ctx (%current-wctx)))
                       (##continuation-graft (%wctx-sched-k cur-ctx)
                                             %nursery-child-abort! n e))))
         (parent-res #f))
    (%nursery-err-handler-set! n child-eh)
    (with-exception-catcher
     (lambda (e) (%nursery-record-error! n e))
     (lambda ()
       (set! parent-res (proc n))))
    (let ((cur-ctx (%carrier-wctx)))
      (if (eq? (%wctx-nursery-cur cur-ctx) n)
          (let* ((drop (fx+ (%wctx-nursery-batch cur-ctx) 1)))
            (%wctx-nursery-batch-set! cur-ctx 0)
            (%wctx-nursery-cur-set! cur-ctx #f)
            (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) drop)))
              (if (fx> prev drop)
                  (##continuation-capture %park-nursery-cont! n))))
          (begin
            (%nursery-flush! cur-ctx)
            (let ((prev (%fxatom-sub-acqrel! (%nursery-active n) 1)))
              (if (fx> prev 1)
                  (##continuation-capture %park-nursery-cont! n))))))
    (if (%nursery-has-err? n)
        (raise (%nursery-first-err n))
        parent-res)))
