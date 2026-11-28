;;;============================================================================

;;; File: "pool.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Zero-Mutex-Poll Work-Stealing Fork-Join Pool & Idempotent Shutdown

(define empty-sentinel (##vector 'empty))
(define abort-sentinel (##vector 'abort))
(define pending-sentinel (##vector 'pending))
(define running-sentinel (##vector 'running))

(##define-type work-stealing-pool
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000002
  type-exhibitor: macro-type-work-stealing-pool
  constructor: macro-make-work-stealing-pool
  implementer: implement-type-work-stealing-pool
  macros:
  prefix: macro-
  opaque:
  (nworkers      read-only: unprintable:)
  (deques        read-only: unprintable:)
  (threads       unprintable:)
  (inject-mut    read-only: unprintable:)
  (inject-cv     read-only: unprintable:)
  (inject-head   unprintable:)
  (inject-tail   unprintable:)
  (inject-count  read-only: unprintable:)
  (sleepers      read-only: unprintable:)
  (shutdown-flag read-only: unprintable:)) ;; 0=running, 1=shutting-down, 2=shutdown-done
(implement-type-work-stealing-pool)

;; Thread-local (pool . worker-id) binding for worker threads (sole deque owner).
(define current-worker-binding (make-parameter #f))

(define (pool-wake-one! pool)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool)))
    (mutex-lock! mut)
    (condition-variable-signal! cv)
    (mutex-unlock! mut)))

(define (pool-inject-push! pool task)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool))
        (icnt (macro-work-stealing-pool-inject-count pool))
        (cell (##cons task '())))
    (mutex-lock! mut)
    (let ((tail (macro-work-stealing-pool-inject-tail pool)))
      (if (##pair? tail)
          (##set-cdr! tail cell)
          (macro-work-stealing-pool-inject-head-set! pool cell))
      (macro-work-stealing-pool-inject-tail-set! pool cell))
    (%fxatom-add-acqrel! icnt 1)
    (condition-variable-signal! cv)
    (mutex-unlock! mut)))

(define (pool-inject-pop! pool)
  (let ((icnt (macro-work-stealing-pool-inject-count pool)))
    ;; Fast lock-free skip when inject queue is empty (0 mutex acquisitions!).
    (if (##fx<= (%fxatom-load-rlx icnt) 0)
        empty-sentinel
        (let ((mut (macro-work-stealing-pool-inject-mut pool)))
          (mutex-lock! mut)
          (let ((head (macro-work-stealing-pool-inject-head pool)))
            (if (##pair? head)
                (let ((task (##car head))
                      (next (##cdr head)))
                  (macro-work-stealing-pool-inject-head-set! pool next)
                  (if (##null? next)
                      (macro-work-stealing-pool-inject-tail-set! pool '()))
                  (%fxatom-sub-acqrel! icnt 1)
                  ;; Cascade wakeup if more injected tasks remain and sleepers exist.
                  (if (and (##pair? next)
                           (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0))
                      (condition-variable-signal! (macro-work-stealing-pool-inject-cv pool)))
                  (mutex-unlock! mut)
                  task)
                (begin
                  (mutex-unlock! mut)
                  empty-sentinel)))))))

(define (pool-any-deque-work? pool)
  (let* ((deques (macro-work-stealing-pool-deques pool))
         (n (##vector-length deques)))
    (let loop ((i 0))
      (if (##fx>= i n)
          #f
          (if (##fx> (deque-size-approx (##vector-ref deques i)) 0)
              #t
              (loop (##fx+ i 1)))))))

(define (pool-try-steal pool self-id start-idx)
  (let* ((deques (macro-work-stealing-pool-deques pool))
         (n (##vector-length deques)))
    (let loop ((k 0))
      (if (##fx>= k n)
          empty-sentinel
          (let ((victim (##fxremainder (##fx+ start-idx k) n)))
            (if (##eq? victim self-id)
                (loop (##fx+ k 1))
                (let ((x (deque-steal! (##vector-ref deques victim)
                                       empty-sentinel
                                       abort-sentinel)))
                  (cond ((##eq? x empty-sentinel)
                         (loop (##fx+ k 1)))
                        ((##eq? x abort-sentinel)
                         ;; Contended steal: retry victim once then move on.
                         (let ((x2 (deque-steal! (##vector-ref deques victim)
                                                 empty-sentinel
                                                 abort-sentinel)))
                           (if (or (##eq? x2 empty-sentinel) (##eq? x2 abort-sentinel))
                               (loop (##fx+ k 1))
                               (begin
                                 (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
                                     (pool-wake-one! pool))
                                 x2))))
                        (else
                         ;; Unconditional steal-cascade wakeup if any peer is sleeping.
                         (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
                             (pool-wake-one! pool))
                         x)))))))))

(define (pool-try-get-task pool self-id cursor)
  (let ((deques (macro-work-stealing-pool-deques pool)))
    (let ((local (if (##fixnum? self-id)
                     (deque-pop-bottom! (##vector-ref deques self-id) empty-sentinel)
                     empty-sentinel)))
      (if (##not (##eq? local empty-sentinel))
          local
          (let ((inj (pool-inject-pop! pool)))
            (if (##not (##eq? inj empty-sentinel))
                inj
                (pool-try-steal pool self-id cursor)))))))

(define (pool-run-task! task)
  (if (future? task)
      (future-run-once! task)
      (with-exception-catcher
       (lambda (_) #f)
       task)))

(define (pool-worker-loop pool wid)
  (parameterize
   ((current-worker-binding (##cons pool wid)))
   (let ((mut (macro-work-stealing-pool-inject-mut pool))
         (cv (macro-work-stealing-pool-inject-cv pool))
         (icnt (macro-work-stealing-pool-inject-count pool))
         (slp (macro-work-stealing-pool-sleepers pool))
         (shut (macro-work-stealing-pool-shutdown-flag pool))
         (n (macro-work-stealing-pool-nworkers pool)))
     (let loop ((cursor (##fxremainder (##fx+ wid 1) (if (##fx> n 0) n 1)))
                (idle-spins 0))
       (let ((task (pool-try-get-task pool wid cursor)))
         (cond
          ((##not (##eq? task empty-sentinel))
           (pool-run-task! task)
           (loop (##fxremainder (##fx+ cursor 1) n) 0))
          ((##not (##fx= (%fxatom-load-acq shut) 0))
           (##void))
          ((##fx< idle-spins 32)
           (%cpu-pause!)
           (loop (##fxremainder (##fx+ cursor 1) n) (##fx+ idle-spins 1)))
          ((##fx< idle-spins 40)
           (thread-yield!)
           (loop (##fxremainder (##fx+ cursor 1) n) (##fx+ idle-spins 1)))
          (else
           ;; Dekker-fenced park: publish sleepers += 1, seq_cst fence, then re-verify
           ;; shutdown, inject queue, and all peer deques before waiting on condvar.
           (%fxatom-add-acqrel! slp 1)
           (%seq-cst-fence!)
           (if (and (##fx= (%fxatom-load-acq shut) 0)
                    (##fx<= (%fxatom-load-acq icnt) 0)
                    (##not (pool-any-deque-work? pool)))
               (begin
                 (mutex-lock! mut)
                 (if (and (##fx= (%fxatom-load-acq shut) 0)
                          (##null? (macro-work-stealing-pool-inject-head pool))
                          (##not (pool-any-deque-work? pool)))
                     (mutex-unlock! mut cv)
                     (mutex-unlock! mut))))
           (%fxatom-sub-acqrel! slp 1)
           (loop (##fxremainder (##fx+ cursor 1) n) 0))))))))

(define (make-work-stealing-pool #!optional (worker-count #f))
  (let* ((hw (##current-vm-processor-count))
         (n (if (and (##fixnum? worker-count) (##fx> worker-count 0))
                worker-count
                (if (##fx> hw 0) hw 1)))
         (deques (##make-vector n #f)))
    (let init-d ((i 0))
      (if (##fx< i n)
          (begin
            (##vector-set! deques i (make-work-stealing-deque 64))
            (init-d (##fx+ i 1)))))
    (let* ((pool (macro-make-work-stealing-pool
                  n
                  deques
                  #f
                  (make-mutex 'work-stealing-pool)
                  (make-condition-variable 'work-stealing-pool-cv)
                  '()
                  '()
                  (%make-padded-fxatom 0)
                  (%make-padded-fxatom 0)
                  (%make-padded-fxatom 0)))
           (threads (##make-vector n #f)))
      (macro-work-stealing-pool-threads-set! pool threads)
      (let spawn ((i 0))
        (if (##fx< i n)
            (let ((th (make-thread
                       (lambda () (pool-worker-loop pool i))
                       (##list 'ws-worker i))))
              (##vector-set! threads i th)
              (thread-start! th)
              (spawn (##fx+ i 1)))))
      pool)))

(define (work-stealing-pool? obj)
  (macro-work-stealing-pool? obj))

(define (work-stealing-pool-worker-count pool)
  (if (not (macro-work-stealing-pool? pool))
      (error "work-stealing-pool-worker-count: expected work-stealing-pool" pool))
  (macro-work-stealing-pool-nworkers pool))

;; Atomic idempotent pool shutdown:
;;   0 (running) -> 1 (shutting-down) -> 2 (shutdown-done).
;; Strictly one caller broadcasts and joins worker threads; concurrent or
;; repeat callers wait until state reaches 2 so no caller returns before all
;; workers have quiesced.
(define (work-stealing-pool-shutdown! pool)
  (if (not (macro-work-stealing-pool? pool))
      (error "work-stealing-pool-shutdown!: expected work-stealing-pool" pool))
  (let ((wb (current-worker-binding)))
    (if (and (##pair? wb) (##eq? (##car wb) pool))
        (error "work-stealing-pool-shutdown!: cannot shut down pool from its own worker thread" pool)))
  (let ((shut (macro-work-stealing-pool-shutdown-flag pool))
        (mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool)))
    (if (##fx= (%fxatom-cas-seq! shut 0 1) 0)
        (begin
          (mutex-lock! mut)
          (condition-variable-broadcast! cv)
          (mutex-unlock! mut)
          (let* ((threads (macro-work-stealing-pool-threads pool))
                 (n (##vector-length threads)))
            (let join ((i 0))
              (if (##fx< i n)
                  (begin
                    (thread-join! (##vector-ref threads i))
                    (join (##fx+ i 1))))))
          (%fxatom-store-rel! shut 2)
          (mutex-lock! mut)
          (condition-variable-broadcast! cv)
          (mutex-unlock! mut))
        (if (##fx< (%fxatom-load-acq shut) 2)
            (begin
              (mutex-lock! mut)
              (let wait ()
                (if (##fx< (%fxatom-load-acq shut) 2)
                    (begin
                      (mutex-unlock! mut cv)
                      (mutex-lock! mut)
                      (wait))
                    (mutex-unlock! mut)))))))
  (##void))

(define (pool-submit! pool task)
  (let ((wb (current-worker-binding)))
    (if (and (##pair? wb) (##eq? (##car wb) pool))
        (let ((wid (##cdr wb)))
          ;; Sole owner pushes directly onto its 128B-padded Chase-Lev deque
          ;; (zero global counter writes, zero mutex locks while peers are busy!).
          (deque-push-bottom!
           (##vector-ref (macro-work-stealing-pool-deques pool) wid)
           task)
          (%seq-cst-fence!)
          (if (##fx> (%fxatom-load-rlx (macro-work-stealing-pool-sleepers pool)) 0)
              (pool-wake-one! pool)))
        ;; Skip pushing into inject-queue once pool shutdown has started;
        ;; futures forced post-shutdown execute locally via future-run-once!.
        (if (##fx= (%fxatom-load-acq (macro-work-stealing-pool-shutdown-flag pool)) 0)
            (pool-inject-push! pool task)))))

;; Lazy default pool (initialized safely on first use via atomic box + mutex).
(define default-pool-mut (make-mutex 'default-ws-pool))
(define default-pool-box (make-atomic-box #f))
(define current-work-stealing-pool (make-parameter #f))

(define (get-active-pool)
  (let ((p (current-work-stealing-pool)))
    (if (macro-work-stealing-pool? p)
        p
        (let ((d (atomic-box-ref default-pool-box 'acquire)))
          (if d
              d
              (begin
                (mutex-lock! default-pool-mut)
                (let ((d2 (atomic-box-ref default-pool-box 'acquire)))
                  (if d2
                      (begin (mutex-unlock! default-pool-mut) d2)
                      (let ((created (make-work-stealing-pool)))
                        (atomic-box-set! default-pool-box created 'release)
                        (mutex-unlock! default-pool-mut)
                        created)))))))))

;;;============================================================================
