;;;============================================================================

;;; File: "scheduler.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Multi-Core M:N Work-Stealing Trampoline, Cascade Wakeup & run-fibers

;;;----------------------------------------------------------------------------
;;; Multi-Core M:N Work-Stealing Direct-Switch Trampoline
;;; (Sticky Victim Locality + Inline Chase-Lev Deque + Recycled %fiber-k)

(define (%worker-try-steal ctx sched num-workers deques)
  (if (or (fx<= num-workers 1)
          (not (%sched-try-acquire-search! sched)))
      #f
      (let ((wid (%wctx-wid ctx))
            (start (%wctx-steal-cursor ctx)))
        (let loop ((tried 1) (victim start))
          (if (fx>= tried num-workers)
              (begin
                ;; Advance cursor pseudorandomly on full miss to desynchronize thieves
                (%wctx-steal-cursor-set!
                 ctx (fxmodulo (fx+ (fx* start 5) 1) num-workers))
                (%sched-release-search! sched)
                #f)
              (let ((v (if (fx= victim wid)
                           (let ((n (fx+ victim 1)))
                             (if (fx>= n num-workers) 0 n))
                           victim)))
                (let ((task (%dq-steal-batch! (##vector-ref deques v) ctx)))
                  (if task
                      (begin
                        (%wctx-steal-cursor-set! ctx v)
                        (%sched-release-search! sched)
                        ;; Unconditional steal-cascade wakeup when last searcher transitions 1 -> 0
                        (%parker-wake-one! sched)
                        task)
                      (let ((nxt (fx+ v 1)))
                        (loop (fx+ tried 1)
                              (if (fx>= nxt num-workers) 0 nxt)))))))))))

(define (%worker-poll-task ctx)
  (let* ((sched (%wctx-sched ctx))
         (ticks (%wctx-ticks ctx))
         (task #f))
    (%wctx-ticks-set! ctx (fx+ ticks 1))
    (%wctx-picked-n-set! ctx #f)
    ;; 0. Every 32 ticks poll global-q for fairness (skipped in 1 load if empty!)
    (if (fx= (fxand ticks 31) 31)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (if (fx> (%fxatom-load-rlx (%sched-global-pending sched)) 0)
                    (%parker-wake-one! sched))
                (set! task t)))))
    ;; 1. Fastest path: private LIFO slot (0 atomics, 0 fences!) if streak < 8
    (if (and (not task)
             (%wctx-lifo ctx)
             (fx< (%wctx-lifo-streak ctx) %MAX-LIFO-STREAK))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-picked-n-set! ctx (%wctx-lifo-n ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-n-set! ctx #f)
          (%wctx-lifo-streak-set! ctx (fx+ (%wctx-lifo-streak ctx) 1))))
    ;; 2. Local inline work-stealing deque (populates ctx.picked-n)
    (if (not task)
        (let ((t (%dq-pop! ctx)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task t)))))
    ;; 3. Fallback to LIFO slot if streak hit limit but local-dq was empty
    (if (and (not task) (%wctx-lifo ctx))
        (begin
          (set! task (%wctx-lifo ctx))
          (%wctx-picked-n-set! ctx (%wctx-lifo-n ctx))
          (%wctx-lifo-set! ctx #f)
          (%wctx-lifo-n-set! ctx #f)
          (%wctx-lifo-streak-set! ctx 0)))
    ;; 4. Global lock-free wakeup/overflow queue (fast-skipped when pending == 0)
    (if (not task)
        (let ((t (%sched-try-dequeue-global! sched)))
          (if t
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (%wctx-picked-n-set! ctx #f)
                ;; Cascade wakeup when additional global tasks remain for parked peers
                (if (fx> (%fxatom-load-rlx (%sched-global-pending sched)) 0)
                    (%parker-wake-one! sched))
                (set! task t)))))
    ;; 5. Sticky victim-locality FIFO batch work-steal (throttled to max(1, W/2) searchers)
    (if (not task)
        (let ((stolen (%worker-try-steal ctx
                                         sched
                                         (%sched-num-workers sched)
                                         (%sched-deques sched))))
          (if stolen
              (begin
                (%wctx-lifo-streak-set! ctx 0)
                (set! task stolen)))))
    task))

;; Direct symmetric coroutine handoff with %fiber-k freelist recycling,
;; global-pending-guarded 32-tick fairness skip, empty-deque LIFO-streak bypass,
;; direct %dq-pop! switch, and lazy #f control-state restore.
(define (%sched-switch-next! ctx)
  (let ((ticks (%wctx-ticks ctx)))
    (if (and (fx= (fxand ticks 15) 15) (fx> (%wctx-nursery-batch ctx) 0))
        (%nursery-flush! ctx))
    (let* ((lifo (%wctx-lifo ctx))
           (streak (%wctx-lifo-streak ctx))
           (dq (%wctx-dq ctx))
           (need-global (and (fx= (fxand ticks 31) 31)
                             (fx> (%fxatom-load-rlx (%sched-global-pending (%wctx-sched ctx))) 0))))
      (if (and lifo
               (not need-global)
               (or (fx< streak %MAX-LIFO-STREAK) (%dq-empty-rlx? dq)))
          (let ((lifo-n (%wctx-lifo-n ctx)))
            (%wctx-ticks-set! ctx (fx+ ticks 1))
            (%wctx-lifo-set! ctx #f)
            (%wctx-lifo-n-set! ctx #f)
            (%wctx-lifo-streak-set! ctx
              (if (fx< streak %MAX-LIFO-STREAK) (fx+ streak 1) %MAX-LIFO-STREAK))
            (if (%fiber-k? lifo)
                (let ((raw-k (%fk-raw-k lifo))
                      (tc (%fk-tc lifo))
                      (val (%fk-val lifo)))
                  (%free-fk! ctx lifo)
                  (if tc (%set-tc! tc))
                  (%return-oneshot! raw-k val))
                (##continuation-graft-no-winding
                 (%wctx-sched-k ctx) %worker-run-task ctx lifo lifo-n)))
          (if (and (not need-global)
                   (not (%dq-empty-rlx? dq)))
              (let ((t (%dq-pop! ctx)))
                (if t
                    (begin
                      (%wctx-ticks-set! ctx (fx+ ticks 1))
                      (%wctx-lifo-streak-set! ctx 0)
                      (if (%fiber-k? t)
                          (let ((raw-k (%fk-raw-k t))
                                (tc (%fk-tc t))
                                (val (%fk-val t)))
                            (%free-fk! ctx t)
                            (if tc (%set-tc! tc))
                            (%return-oneshot! raw-k val))
                          (##continuation-graft-no-winding
                           (%wctx-sched-k ctx) %worker-run-task ctx t (%wctx-picked-n ctx))))
                    (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0)))
              (##continuation-graft-no-winding (%wctx-sched-k ctx) %worker-dispatch ctx 0))))))

;; Executed on the clean carrier trampoline AFTER ##continuation-graft has
;; completed all dynamic-wind after-thunks of a faulting detached fiber so
;; the carrier OS worker survives, control state stays isolated, and
;; quiescence (completed == spawned) always converges.
(define (%detached-fiber-abort! exc)
  (let ((cur-ctx (%current-wctx)))
    (%nursery-flush! cur-ctx)
    (if (%get-tc) (%set-tc! #f))
    (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
    (%worker-dispatch cur-ctx 0)))

(define (%detached-err-handler exc)
  (let ((cur-ctx (%current-wctx)))
    (##continuation-graft (%wctx-sched-k cur-ctx)
                          %detached-fiber-abort! exc)))

(define (%worker-run-task ctx task n)
  (cond
    ((%fiber-k? task)
     (let ((raw-k (%fk-raw-k task))
           (tc (%fk-tc task))
           (val (%fk-val task)))
       (%free-fk! ctx task)
       (if tc (%set-tc! tc))
       (%return-oneshot! raw-k val)))
    (n
     ;; Zero-cons, zero-closure nursery child (thunk + nursery from flat dual-array dq)
     (##with-exception-handler (%nursery-err-handler n) task)
     (let ((cur-ctx (%carrier-wctx)))
       (%nursery-child-done-batched! cur-ctx n)
       (if (%get-tc) (%set-tc! #f))
       (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
       (%sched-switch-next! cur-ctx)))
    ((pair? task)
     ;; Overflow-queue nursery child: (thunk . nursery)
     (let ((fn (car task))
           (pn (cdr task)))
       (##with-exception-handler (%nursery-err-handler pn) fn)
       (let ((cur-ctx (%carrier-wctx)))
         (%nursery-child-done-batched! cur-ctx pn)
         (if (%get-tc) (%set-tc! #f))
         (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
         (%sched-switch-next! cur-ctx))))
    (else
     ;; Detached fiber thunk: isolate uncaught exceptions so carrier OS workers
     ;; stay alive, cleanups run, and scheduler quiescence always converges.
     (##with-exception-handler %detached-err-handler task)
     (let ((cur-ctx (%carrier-wctx)))
       (if (%get-tc) (%set-tc! #f))
       (%fxatom-inc-owner-rel! (%wctx-completed cur-ctx))
       (%sched-switch-next! cur-ctx)))))

(define (%sched-any-work-visible? sched)
  (if (fx> (%fxatom-load-acq (%sched-global-pending sched)) 0)
      #t
      (let ((w (%sched-num-workers sched))
            (deques (%sched-deques sched)))
        (let loop ((i 0))
          (if (fx< i w)
              (if (not (%dq-empty-rlx? (##vector-ref deques i)))
                  #t
                  (loop (fx+ i 1)))
              #f)))))

(define (%worker-dispatch ctx idle-spins)
  (let ((task (%worker-poll-task ctx)))
    (if task
        (%worker-run-task ctx task (%wctx-picked-n ctx))
        (let ((sched (%wctx-sched ctx)))
          (if (fx> (%wctx-nursery-batch ctx) 0) (%nursery-flush! ctx))
          (if (%wctx-lifo ctx)
              (%worker-dispatch ctx 0)
              (if (%sched-quiescent? sched)
                  (begin
                    (%parker-wake-all! (%sched-parker sched))
                    #!void)
                  (let* ((parker (%sched-parker sched))
                         (is-ecore (fx>= (%wctx-wid ctx) (%sched-pcores sched)))
                         (pause-limit (if is-ecore 8 48)))
                    (if (and parker (fx>= idle-spins pause-limit))
                        (begin
                          (thread-yield!)
                          (let ((seq (%parker-begin-wait! parker)))
                            (cond
                              ((%sched-quiescent? sched)
                               (%parker-abort-wait! parker)
                               (%parker-wake-all! parker)
                               #!void)
                              ((%sched-any-work-visible? sched)
                               (%parker-abort-wait! parker)
                               (%worker-dispatch ctx 0))
                              (else
                               (%parker-finish-wait! parker seq)
                               (%worker-dispatch ctx 0)))))
                        (if (fx< idle-spins pause-limit)
                            (begin
                              (%idle-pause-c! idle-spins)
                              (%worker-dispatch ctx (fx+ idle-spins 1)))
                            (begin
                              (thread-yield!)
                              (%worker-dispatch ctx 0)))))))))))

(define (%worker-loop sched wid)
  (let* ((w (%sched-num-workers sched))
         (deques (%sched-deques sched))
         (local-dq (##vector-ref deques wid))
         (spawned (##vector-ref (%sched-spawned-vec sched) wid))
         (completed (##vector-ref (%sched-completed-vec sched) wid))
         (init-victim (if (fx> w 1)
                          (let ((n (fx+ wid 1))) (if (fx>= n w) 0 n))
                          0))
         (ctx (%make-worker-ctx sched wid local-dq spawned completed
                                #f 0 0 #f #f 0 init-victim #f 0 #f #f #f)))
    (%set-carrier-qos!)
    (macro-thread-specific-set! (##current-thread) ctx)
    (if (%get-tc) (%set-tc! #f))
    ;; Capture the carrier's single reusable trampoline continuation once
    (##continuation-capture
     (lambda (base-k)
       (%wctx-sched-k-set! ctx base-k)
       (%worker-dispatch ctx 0)))))

(define (run-fibers thunk #!key (workers (fiber-performance-core-count)))
  (if (not (procedure? thunk))
      (error "run-fibers: expected thunk" thunk))
  (let* ((w (max 1 (if (fixnum? workers) workers 1)))
         (pcores (fiber-performance-core-count))
         (deques (let ((v (make-vector w #f)))
                   (let loop ((i 0))
                     (if (fx< i w)
                         (begin (##vector-set! v i (%make-local-dq))
                                (loop (fx+ i 1)))))
                   v))
         (spawned-vec (let ((v (make-vector w #f)))
                        (let loop ((i 0))
                          (if (fx< i w)
                              (begin (##vector-set! v i (%make-padded-fxatom (if (fx= i 0) 1 0)))
                                     (loop (fx+ i 1)))))
                        v))
         (completed-vec (let ((v (make-vector w #f)))
                          (let loop ((i 0))
                            (if (fx< i w)
                                (begin (##vector-set! v i (%make-padded-fxatom 0))
                                       (loop (fx+ i 1)))))
                          v))
         (global-q (make-lf-queue))
         (global-pending (%make-padded-fxatom 0))
         (root-done (%make-fxatom 0))
         (root-box (cons #f #f))
         (searching (%make-padded-fxatom 0))
         (max-searching (max 1 (fxarithmetic-shift-right w 1)))
         (parker (%make-parker))
         (sched (%make-scheduler w deques global-q global-pending
                                 spawned-vec completed-vec root-done root-box
                                 searching max-searching parker pcores)))
    (%sched-enqueue-global!
     sched
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (set-car! root-box #f)
          (set-cdr! root-box e)
          (%fxatom-set-rel! root-done 1)
          (%parker-wake-all! parker))
        (lambda ()
          (let ((res (thunk)))
            (set-car! root-box #t)
            (set-cdr! root-box res)
            (%fxatom-set-rel! root-done 1)
            (%parker-wake-all! parker))))))
    (let ((threads
           (let loop ((i 0) (acc '()))
             (if (fx= i w)
                 acc
                 (loop (fx+ i 1)
                       (cons (thread-start!
                              (make-thread
                               (lambda () (%worker-loop sched i))))
                             acc))))))
      (with-exception-catcher
       (lambda (e)
         (%destroy-parker! parker)
         (raise e))
       (lambda ()
         (for-each thread-join! threads))))
    (%destroy-parker! parker)
    (if (car root-box)
        (cdr root-box)
        (raise (cdr root-box)))))

;;;============================================================================
