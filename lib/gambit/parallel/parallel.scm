;;;============================================================================

;;; File: "parallel.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Weak-Memory-Verified Chase-Lev Work-Stealing Deque (Le et al., PPoPP 2013)
;;; and Structured Fork-Join Parallel Stdlib built on (srfi 230).
;;;
;;; Formal Verification Anchors:
;;;   - Quint V2: slice3b2_srfi230_and_chase_lev_v2.qnt
;;;   - Lean 4:   Slice3B2AtomicsChaseLevRefinement.lean
;;;   - CBMC PSO: slice3b2_chase_lev_and_srfi230_pso.c

(##supply-module gambit/parallel)

(##namespace ("gambit/parallel#"))
(##include "~~lib/gambit/prim/prim#.scm")
(##include "~~lib/_gambit#.scm")
(##include "~~lib/srfi/230/230#.scm")
(##namespace (""
              make-mutex mutex-lock! mutex-unlock!
              make-condition-variable condition-variable-signal! condition-variable-broadcast!
              make-thread thread-start! thread-join! thread-yield!
              make-parameter parameterize with-exception-catcher raise))

(##include "parallel#.scm")

(declare (extended-bindings))
(declare (not safe))
(declare (block))

;;;============================================================================
;;; Part 1: Chase-Lev Work-Stealing Deque (Le et al. PPoPP 2013)
;;;
;;; Backing ring buffers are GC-traced Scheme vectors accessed via relaxed
;;; GC-barriered atomics (srfi/230#vector-atomic-ref / set!) so speculative
;;; stealers racing with ring wraparound are 100% C23 DRF-0 & TSan clean.
;;;============================================================================

(##define-type work-stealing-deque
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000001
  type-exhibitor: macro-type-work-stealing-deque
  constructor: macro-make-work-stealing-deque
  implementer: implement-type-work-stealing-deque
  macros:
  prefix: macro-
  opaque:
  (top    read-only: unprintable:)
  (bottom read-only: unprintable:)
  (array  read-only: unprintable:))
(implement-type-work-stealing-deque)

(define (next-pow2 n)
  (let loop ((p 4))
    (if (##fx>= p n) p (loop (##fxarithmetic-shift-left p 1)))))

(define (make-work-stealing-deque #!optional (initial-capacity 64))
  (let ((cap (next-pow2 (if (and (##fixnum? initial-capacity)
                                 (##fx> initial-capacity 0))
                            initial-capacity
                            64))))
    (macro-make-work-stealing-deque
     (make-atomic-fxbox 0)
     (make-atomic-fxbox 0)
     (make-atomic-box (##make-vector cap #f)))))

(define (work-stealing-deque? obj)
  (macro-work-stealing-deque? obj))

(define (deque-size-approx q)
  (let* ((t (atomic-fxbox-ref (macro-work-stealing-deque-top q) 'acquire))
         (b (atomic-fxbox-ref (macro-work-stealing-deque-bottom q) 'acquire))
         (d (##fx- b t)))
    (if (##fx> d 0) d 0)))

(define (deque-empty? q)
  (##fx= (deque-size-approx q) 0))

;;; Grow ring buffer by 2x, preserving every live slot i in [t, b) without
;;; collision (proven injective in Slice3B2AtomicsChaseLevRefinement.lean).
(define (deque-grow-array! q old-a t b)
  (let* ((old-cap (##vector-length old-a))
         (old-mask (##fx- old-cap 1))
         (new-cap (##fxarithmetic-shift-left old-cap 1))
         (new-mask (##fx- new-cap 1))
         (new-a (##make-vector new-cap #f)))
    (let loop ((i t))
      (if (##fx< i b)
          (begin
            (##vector-set!
             new-a
             (##fxand i new-mask)
             (vector-atomic-ref old-a (##fxand i old-mask) 'relaxed))
            (loop (##fx+ i 1)))))
    (atomic-box-set! (macro-work-stealing-deque-array q) new-a 'release)
    new-a))

;;; Owner-only LIFO push at bottom.
(define (deque-push-bottom! q item)
  (let* ((b (atomic-fxbox-ref (macro-work-stealing-deque-bottom q) 'relaxed))
         (t (atomic-fxbox-ref (macro-work-stealing-deque-top q) 'acquire))
         (a0 (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed))
         (a (if (##fx>= (##fx- b t) (##vector-length a0))
                (deque-grow-array! q a0 t b)
                a0))
         (mask (##fx- (##vector-length a) 1)))
    (vector-atomic-set! a (##fxand b mask) item 'relaxed)
    (atomic-fxbox-set! (macro-work-stealing-deque-bottom q) (##fx+ b 1) 'release)
    (##void)))

;;; Owner-only LIFO pop from bottom (with Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-pop-bottom! q #!optional (empty #f))
  (let* ((bot-box (macro-work-stealing-deque-bottom q))
         (top-box (macro-work-stealing-deque-top q))
         (b (##fx- (atomic-fxbox-ref bot-box 'relaxed) 1))
         (a (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed)))
    (atomic-fxbox-set! bot-box b 'relaxed)
    (atomic-fence 'sequentially-consistent)
    (let ((t (atomic-fxbox-ref top-box 'relaxed)))
      (if (##fx<= t b)
          (let* ((mask (##fx- (##vector-length a) 1))
                 (idx (##fxand b mask))
                 (x (vector-atomic-ref a idx 'relaxed)))
            (if (##fx= t b)
                (let ((prev (atomic-fxbox-compare-and-swap!
                             top-box t (##fx+ t 1) 'sequentially-consistent)))
                  (atomic-fxbox-set! bot-box (##fx+ b 1) 'relaxed)
                  (if (##fx= prev t) x empty))
                (begin
                  ;; Safe to clear slot when t < b (no thief can read b).
                  (vector-atomic-set! a idx #f 'relaxed)
                  x)))
          (begin
            (atomic-fxbox-set! bot-box (##fx+ b 1) 'relaxed)
            empty)))))

;;; Concurrent thief FIFO steal from top (with Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-steal! q #!optional (empty #f) (abort #f))
  (let* ((top-box (macro-work-stealing-deque-top q))
         (bot-box (macro-work-stealing-deque-bottom q))
         (t (atomic-fxbox-ref top-box 'acquire)))
    (atomic-fence 'sequentially-consistent)
    (let ((b (atomic-fxbox-ref bot-box 'acquire)))
      (if (##fx< t b)
          (let* ((a (atomic-box-ref (macro-work-stealing-deque-array q) 'acquire))
                 (mask (##fx- (##vector-length a) 1))
                 (x (vector-atomic-ref a (##fxand t mask) 'relaxed))
                 (prev (atomic-fxbox-compare-and-swap!
                        top-box t (##fx+ t 1) 'sequentially-consistent)))
            (if (##fx= prev t) x abort))
          empty))))

;;;============================================================================
;;; Part 2: Work-Stealing Fork-Join Pool (Dynamic Core Count, Zero Hardcodes)
;;;============================================================================

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
  (pending-count read-only: unprintable:)
  (shutdown-flag read-only: unprintable:))
(implement-type-work-stealing-pool)

;; Thread-local (pool . worker-id) binding for worker threads (sole deque owner).
(define current-worker-binding (make-parameter #f))

(define (pool-inject-push! pool task)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool))
        (cell (##cons task '())))
    (mutex-lock! mut)
    (let ((tail (macro-work-stealing-pool-inject-tail pool)))
      (if (##pair? tail)
          (##set-cdr! tail cell)
          (macro-work-stealing-pool-inject-head-set! pool cell))
      (macro-work-stealing-pool-inject-tail-set! pool cell))
    (atomic-fxbox-fetch-add! (macro-work-stealing-pool-pending-count pool) 1 'release)
    (condition-variable-signal! cv)
    (mutex-unlock! mut)))

(define (pool-inject-pop! pool)
  (let ((mut (macro-work-stealing-pool-inject-mut pool)))
    (mutex-lock! mut)
    (let ((head (macro-work-stealing-pool-inject-head pool)))
      (if (##pair? head)
          (let ((task (##car head))
                (next (##cdr head)))
            (macro-work-stealing-pool-inject-head-set! pool next)
            (if (##null? next)
                (macro-work-stealing-pool-inject-tail-set! pool '()))
            (mutex-unlock! mut)
            task)
          (begin
            (mutex-unlock! mut)
            empty-sentinel)))))

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
                               x2)))
                        (else x)))))))))

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

(define (pool-worker-loop pool wid)
  (parameterize
   ((current-worker-binding (##cons pool wid)))
   (let ((mut (macro-work-stealing-pool-inject-mut pool))
         (cv (macro-work-stealing-pool-inject-cv pool))
         (pending (macro-work-stealing-pool-pending-count pool))
         (shut (macro-work-stealing-pool-shutdown-flag pool))
         (n (macro-work-stealing-pool-nworkers pool)))
     (let loop ((cursor (##fxremainder (##fx+ wid 1) (if (##fx> n 0) n 1)))
                (idle-spins 0))
       (let ((task (pool-try-get-task pool wid cursor)))
         (cond
          ((##not (##eq? task empty-sentinel))
           (atomic-fxbox-fetch-sub! pending 1 'acquire-release)
           (task)
           (loop (##fxremainder (##fx+ cursor 1) n) 0))
          ((##not (##fx= (atomic-fxbox-ref shut 'acquire) 0))
           (##void))
          ((##fx< idle-spins 16)
           (thread-yield!)
           (loop (##fxremainder (##fx+ cursor 1) n) (##fx+ idle-spins 1)))
          (else
           (mutex-lock! mut)
           (if (and (##fx= (atomic-fxbox-ref shut 'acquire) 0)
                    (##fx<= (atomic-fxbox-ref pending 'acquire) 0)
                    (##null? (macro-work-stealing-pool-inject-head pool)))
               (mutex-unlock! mut cv)
               (mutex-unlock! mut))
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
                  (make-atomic-fxbox 0)
                  (make-atomic-fxbox 0)))
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
  (macro-work-stealing-pool-nworkers pool))

(define (work-stealing-pool-shutdown! pool)
  (atomic-fxbox-set! (macro-work-stealing-pool-shutdown-flag pool) 1 'release)
  (let ((mut (macro-work-stealing-pool-inject-mut pool))
        (cv (macro-work-stealing-pool-inject-cv pool)))
    (mutex-lock! mut)
    (condition-variable-broadcast! cv)
    (mutex-unlock! mut))
  (let* ((threads (macro-work-stealing-pool-threads pool))
         (n (##vector-length threads)))
    (let join ((i 0))
      (if (##fx< i n)
          (begin
            (thread-join! (##vector-ref threads i))
            (join (##fx+ i 1))))))
  (##void))

(define (pool-submit! pool task)
  (let ((wb (current-worker-binding)))
    (if (and (##pair? wb) (##eq? (##car wb) pool))
        (let ((wid (##cdr wb))
              (mut (macro-work-stealing-pool-inject-mut pool))
              (cv (macro-work-stealing-pool-inject-cv pool)))
          ;; Sole owner pushes directly onto its Chase-Lev deque (lock-free!).
          (deque-push-bottom!
           (##vector-ref (macro-work-stealing-pool-deques pool) wid)
           task)
          (let ((prev (atomic-fxbox-fetch-add!
                       (macro-work-stealing-pool-pending-count pool) 1 'release)))
            ;; Wake sleeping peers if pool may have idle workers.
            (if (##fx< prev (macro-work-stealing-pool-nworkers pool))
                (begin
                  (mutex-lock! mut)
                  (condition-variable-signal! cv)
                  (mutex-unlock! mut)))))
        (pool-inject-push! pool task))))

;; Lazy default pool (initialized safely on first use via atomic CAS / mutex).
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
;;; Part 3: Futures with Work-Stealing Helping & Exception Propagation
;;;============================================================================

(##define-type ws-future
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000003
  type-exhibitor: macro-type-ws-future
  constructor: macro-make-ws-future
  implementer: implement-type-ws-future
  macros:
  prefix: macro-
  opaque:
  (pool  read-only: unprintable:)
  (thunk read-only: unprintable:)
  (state read-only: unprintable:))
(implement-type-ws-future)

(define (future? obj)
  (macro-ws-future? obj))

(define (future-ready? f)
  (let ((st (atomic-box-ref (macro-ws-future-state f) 'acquire)))
    (##pair? st)))

(define (future-run-once! f)
  (let* ((st-box (macro-ws-future-state f))
         (prev (atomic-box-compare-and-swap!
                st-box pending-sentinel running-sentinel 'acquire-release)))
    (if (##eq? prev pending-sentinel)
        (let ((result
               (with-exception-catcher
                (lambda (exc) (##cons 'err exc))
                (lambda () (##cons 'ok ((macro-ws-future-thunk f)))))))
          (atomic-box-set! st-box result 'release)
          #t)
        #f)))

(define (make-future thunk #!optional (pool #f))
  (let* ((p (if (macro-work-stealing-pool? pool) pool (get-active-pool)))
         (f (macro-make-ws-future p thunk (make-atomic-box pending-sentinel))))
    (pool-submit! p (lambda () (future-run-once! f)))
    f))

(define (future-force f)
  (let ((st-box (macro-ws-future-state f))
        (pool (macro-ws-future-pool f)))
    ;; Fast path: already completed.
    (let ((st0 (atomic-box-ref st-box 'acquire)))
      (if (##pair? st0)
          (if (##eq? (##car st0) 'ok) (##cdr st0) (raise (##cdr st0)))
          (begin
            ;; Try claiming & running this future directly (zero-deadlock helping!).
            (future-run-once! f)
            ;; While another thread is running this future, help execute work!
            (let* ((wb (current-worker-binding))
                   (self-id (if (and (##pair? wb) (##eq? (##car wb) pool))
                                (##cdr wb)
                                #f))
                   (n (macro-work-stealing-pool-nworkers pool))
                   (pending (macro-work-stealing-pool-pending-count pool)))
              (let wait ((cursor 0))
                (let ((st (atomic-box-ref st-box 'acquire)))
                  (if (##pair? st)
                      (if (##eq? (##car st) 'ok) (##cdr st) (raise (##cdr st)))
                      (let ((task (pool-try-get-task pool self-id cursor)))
                        (if (##not (##eq? task empty-sentinel))
                            (begin
                              (atomic-fxbox-fetch-sub! pending 1 'acquire-release)
                              (task)
                              (wait (##fxremainder (##fx+ cursor 1) n)))
                            (begin
                              (thread-yield!)
                              (wait (##fxremainder (##fx+ cursor 1) n))))))))))))))

(define (force-future f)
  (future-force f))

;;;============================================================================
;;; Part 4: Structured Fork-Join Combinators
;;;============================================================================

(define (default-grain n workers)
  (let* ((chunks (##fx* workers 4))
         (g (if (##fx> chunks 0) (##fxquotient n chunks) n)))
    (if (##fx> g 1) g 1)))

(define (parallel-vector-map fn vec #!optional (grain #f))
  (let* ((n (##vector-length vec))
         (out (##make-vector n #f)))
    (if (##fx= n 0)
        out
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (if (or (##fx<= w 1) (##fx<= n g))
              (let seq ((i 0))
                (if (##fx< i n)
                    (begin
                      (##vector-set! out i (fn (##vector-ref vec i)))
                      (seq (##fx+ i 1)))
                    out))
              (letrec ((run-range
                        (lambda (lo hi)
                          (if (##fx<= (##fx- hi lo) g)
                              (let loop ((i lo))
                                (if (##fx< i hi)
                                    (begin
                                      (##vector-set! out i (fn (##vector-ref vec i)))
                                      (loop (##fx+ i 1)))))
                              (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                     (right (make-future (lambda () (run-range mid hi)) pool)))
                                (run-range lo mid)
                                (future-force right))))))
                (run-range 0 n)
                out))))))

(define (parallel-map fn lst #!optional (grain #f))
  (if (##null? lst)
      '()
      (##vector->list (parallel-vector-map fn (##list->vector lst) grain))))

(define (parallel-for-each fn lst #!optional (grain #f))
  (if (##null? lst)
      (##void)
      (let* ((vec (##list->vector lst))
             (n (##vector-length vec))
             (pool (get-active-pool))
             (w (macro-work-stealing-pool-nworkers pool))
             (g (if (and (##fixnum? grain) (##fx> grain 0))
                    grain
                    (default-grain n w))))
        (if (or (##fx<= w 1) (##fx<= n g))
            (let seq ((i 0))
              (if (##fx< i n)
                  (begin (fn (##vector-ref vec i)) (seq (##fx+ i 1)))
                  (##void)))
            (letrec ((run-range
                      (lambda (lo hi)
                        (if (##fx<= (##fx- hi lo) g)
                            (let loop ((i lo))
                              (if (##fx< i hi)
                                  (begin (fn (##vector-ref vec i)) (loop (##fx+ i 1)))))
                            (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                   (right (make-future (lambda () (run-range mid hi)) pool)))
                              (run-range lo mid)
                              (future-force right))))))
              (run-range 0 n)
              (##void))))))

(define (parallel-reduce combine identity seq-or-vec #!optional (grain #f))
  (let* ((vec (if (##vector? seq-or-vec) seq-or-vec (##list->vector seq-or-vec)))
         (n (##vector-length vec)))
    (if (##fx= n 0)
        identity
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (letrec ((reduce-range
                    (lambda (lo hi)
                      (if (or (##fx<= w 1) (##fx<= (##fx- hi lo) g))
                          (let loop ((i lo) (acc identity))
                            (if (##fx< i hi)
                                (loop (##fx+ i 1) (combine acc (##vector-ref vec i)))
                                acc))
                          (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                 (right (make-future (lambda () (reduce-range mid hi)) pool))
                                 (lv (reduce-range lo mid))
                                 (rv (future-force right)))
                            (combine lv rv))))))
            (reduce-range 0 n))))))

;;;============================================================================
