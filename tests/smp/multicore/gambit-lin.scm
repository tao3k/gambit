;;; Gambit-Lin: QCheck-Lin inspired concurrent linearizability property tester
;;; for Gambit SMP (p2/p4).
;;;
;;; Generates seeded concurrent histories [prefix; thread-0 || thread-1 || ...]
;;; under active GC-Hammer perturbation, records real call/return timestamps
;;; (monotone wall nanoseconds via ##current-time-point), and checks Wing-Gong
;;; linearizability against a pure sequential reference model. On any violation,
;;; shrinks the failing operation schedule to a minimal counterexample.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

;;; Deterministic PRNG (SplitMix-style 30-bit fixnum LCG for portable seed replay)
(define (make-prng seed)
  (vector (bitwise-and seed #x3fffffff)))

(define (prng-next! rng)
  (let ((next (bitwise-and (+ (* (vector-ref rng 0) 1103515245) 12345) #x3fffffff)))
    (vector-set! rng 0 next)
    next))

(define (prng-int! rng bound)
  (modulo (prng-next! rng) bound))

;;; Recorded operation event: #(id op start-ts end-ts result)
(define (make-ev id op start end res) (vector id op start end res))
(define (ev-id e) (vector-ref e 0))
(define (ev-op e) (vector-ref e 1))
(define (ev-start e) (vector-ref e 2))
(define (ev-end e) (vector-ref e 3))
(define (ev-res e) (vector-ref e 4))

;;; Wing-Gong linearizability search over a list of completed operation events.
;;; An event e is minimal (eligible to linearize next) iff no remaining event e2
;;; finished strictly before e started (e2.end < e.start).
(define (linearizable? init-model step-fn events max-nodes)
  (let ((visited (vector 0))
        (memo (make-table test: equal?)))
    (define (minimal-events rem)
      (let loop ((xs rem) (acc '()))
        (if (null? xs)
            (reverse acc)
            (let* ((e (car xs))
                   (st (ev-start e))
                   (blocked?
                    (let check ((ys rem))
                      (cond ((null? ys) #f)
                            ((< (ev-end (car ys)) st) #t)
                            (else (check (cdr ys)))))))
              (loop (cdr xs) (if blocked? acc (cons e acc)))))))
    (define (remove-ev id rem)
      (cond ((null? rem) '())
            ((= (ev-id (car rem)) id) (cdr rem))
            (else (cons (car rem) (remove-ev id (cdr rem))))))
    (define (search model rem mask)
      (cond
       ((null? rem) #t)
       ((> (vector-ref visited 0) max-nodes) 'budget-exceeded)
       ((table-ref memo (cons mask model) #f) #f)
       (else
        (vector-set! visited 0 (+ (vector-ref visited 0) 1))
        (let loop ((cands (minimal-events rem)))
          (if (null? cands)
              (begin
                (table-set! memo (cons mask model) #t)
                #f)
              (let* ((e (car cands))
                     (step-res (step-fn model (ev-op e))))
                (if (and step-res (equal? (car step-res) (ev-res e)))
                    (let ((sub (search (cdr step-res)
                                       (remove-ev (ev-id e) rem)
                                       (bitwise-ior mask (arithmetic-shift 1 (ev-id e))))))
                      (cond ((eq? sub #t) #t)
                            ((eq? sub 'budget-exceeded) 'budget-exceeded)
                            (else (loop (cdr cands)))))
                    (loop (cdr cands)))))))))
    (search init-model events 0)))

;;; Execute one concurrent scenario:
;;;   prefix-ops: executed sequentially on main thread
;;;   thread-ops-list: list of op lists executed concurrently after a start barrier
(define (run-lin-scenario make-sut exec-op init-model step-fn prefix-ops thread-ops-list)
  (let* ((sut (make-sut))
         (seq-model
          (let loop ((ops prefix-ops) (m init-model))
            (if (null? ops)
                m
                (let* ((op (car ops))
                       (res (exec-op sut op))
                       (m-step (step-fn m op)))
                  (if (or (not m-step) (not (equal? (car m-step) res)))
                      (mc-fail 'prefix-mismatch op 'got res 'expected (and m-step (car m-step))))
                  (loop (cdr ops) (cdr m-step))))))
         (nthreads (length thread-ops-list))
         (ready-mutex (make-mutex))
         (ready-cv (make-condition-variable))
         (ready-count (vector 0))
         (go-flag (vector #f))
         (next-id (vector 0))
         (results (make-vector nthreads '())))
    (define (spawn-worker idx ops)
      (thread-start!
       (make-thread
        (lambda ()
          (mutex-lock! ready-mutex)
          (vector-set! ready-count 0 (+ (vector-ref ready-count 0) 1))
          (condition-variable-broadcast! ready-cv)
          (let wait ()
            (if (not (vector-ref go-flag 0))
                (begin
                  (mutex-unlock! ready-mutex ready-cv)
                  (mutex-lock! ready-mutex)
                  (wait))))
          (mutex-unlock! ready-mutex)
          (let loop ((xs ops) (acc '()))
            (if (null? xs)
                (vector-set! results idx (reverse acc))
                (let* ((op (car xs))
                       (id (begin
                             (mutex-lock! ready-mutex)
                             (let ((k (vector-ref next-id 0)))
                               (vector-set! next-id 0 (+ k 1))
                               (mutex-unlock! ready-mutex)
                               k)))
                       (t0 (##current-time-point))
                       (r (exec-op sut op))
                       (t1 (##current-time-point)))
                  (if (= (modulo id 3) 0) (thread-yield!))
                  (loop (cdr xs) (cons (make-ev id op t0 t1 r) acc))))))
        (string-append "lin-w-" (number->string idx)))))
    (let ((threads
           (let loop ((i 0) (lists thread-ops-list) (acc '()))
             (if (null? lists)
                 (reverse acc)
                 (loop (+ i 1) (cdr lists) (cons (spawn-worker i (car lists)) acc))))))
      (mutex-lock! ready-mutex)
      (let wait-all ()
        (if (< (vector-ref ready-count 0) nthreads)
            (begin
              (mutex-unlock! ready-mutex ready-cv)
              (mutex-lock! ready-mutex)
              (wait-all))))
      (vector-set! go-flag 0 #t)
      (condition-variable-broadcast! ready-cv)
      (mutex-unlock! ready-mutex)
      (for-each thread-join! threads)
      (let* ((all-evs
              (let loop ((i 0) (acc '()))
                (if (= i nthreads)
                    acc
                    (loop (+ i 1) (append acc (vector-ref results i))))))
             (verdict (linearizable? seq-model step-fn all-evs 200000)))
        (list verdict seq-model all-evs)))))

;;; ============================================================================
;;; Suite 1: Concurrent Synchronized Table (mutex + table-ref/set!/copy + GC)
;;; Pure reference model: sorted association list of (key . val) for keys 0..3.
;;; ============================================================================
(define (assoc-set alist k v)
  (cond ((null? alist) (list (cons k v)))
        ((= (caar alist) k) (cons (cons k v) (cdr alist)))
        ((< k (caar alist)) (cons (cons k v) alist))
        (else (cons (car alist) (assoc-set (cdr alist) k v)))))

(define (assoc-del alist k)
  (cond ((null? alist) '())
        ((= (caar alist) k) (cdr alist))
        (else (cons (car alist) (assoc-del (cdr alist) k)))))

(define (assoc-get alist k)
  (let ((p (assv k alist)))
    (if p (cdr p) 'absent)))

(define (table-model-step model op)
  (case (car op)
    ((get) (cons (assoc-get model (cadr op)) model))
    ((set) (cons 'ok (assoc-set model (cadr op) (caddr op))))
    ((del) (cons 'ok (assoc-del model (cadr op))))
    ((len) (cons (length model) model))
    ((cas) (let* ((k (cadr op)) (expected (caddr op)) (new (cadddr op))
                  (cur (assoc-get model k)))
             (if (equal? cur expected)
                 (cons #t (assoc-set model k new))
                 (cons #f model))))
    (else #f)))

(define (make-sync-table)
  (cons (make-mutex 'lin-tbl) (make-table test: eqv?)))

(define (exec-sync-table sut op)
  (let ((m (car sut)) (t (cdr sut)))
    (mutex-lock! m)
    (let ((res
           (case (car op)
             ((get) (table-ref t (cadr op) 'absent))
             ((set) (table-set! t (cadr op) (caddr op)) 'ok)
             ((del) (table-set! t (cadr op)) 'ok)
             ((len) (table-length (table-copy t)))
             ((cas) (let* ((k (cadr op)) (expected (caddr op)) (new (cadddr op))
                           (cur (table-ref t k 'absent)))
                      (if (equal? cur expected)
                          (begin (table-set! t k new) #t)
                          #f))))))
      (mutex-unlock! m)
      res)))

(define (gen-table-op rng)
  (let ((kind (prng-int! rng 5))
        (k (prng-int! rng 3))
        (v (prng-int! rng 4)))
    (case kind
      ((0) (list 'get k))
      ((1) (list 'set k v))
      ((2) (list 'del k))
      ((3) (list 'len))
      (else (list 'cas k (if (= (prng-int! rng 3) 0) 'absent (prng-int! rng 4)) v)))))

;;; ============================================================================
;;; Suite 2: Multi-Producer / Synchronized-Consumer FIFO Queue over Mailbox
;;; Tests thread-send! + thread-receive linearizability across processors + GC.
;;; ============================================================================
(define (queue-model-step model op)
  (case (car op)
    ((enq) (cons 'ok (append model (list (cadr op)))))
    ((deq) (if (null? model)
               (cons 'empty model)
               (cons (car model) (cdr model))))
    ((size) (cons (length model) model))
    (else #f)))

(define (make-mbox-queue)
  ;; Pair of (lock . consumer-thread-with-mailbox) where lock serializes atomic
  ;; enq/deq observations with exact FIFO mailbox semantics under SMP.
  (let* ((gate (make-mutex 'mbox-lin))
         (reply-box (vector #f))
         (req-mtx (make-mutex 'mbox-req))
         (req-cv (make-condition-variable 'mbox-cv))
         (done (vector #f))
         (count (vector 0))
         (owner
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ()
                (mutex-lock! req-mtx)
                (let wait ()
                  (if (and (not (vector-ref done 0)) (not (vector-ref reply-box 0)))
                      (begin
                        (mutex-unlock! req-mtx req-cv)
                        (mutex-lock! req-mtx)
                        (wait))))
                (let ((req (vector-ref reply-box 0)))
                  (vector-set! reply-box 0 #f)
                  (mutex-unlock! req-mtx)
                  (if req
                      (let ((cmd (car req)) (ans-box (cdr req)))
                        (case cmd
                          ((deq)
                           (let ((v (thread-receive 0 'empty)))
                             (if (not (eq? v 'empty))
                                 (vector-set! count 0 (- (vector-ref count 0) 1)))
                             (vector-set! ans-box 0 v)))
                          ((size)
                           (vector-set! ans-box 0 (vector-ref count 0))))
                        (mutex-lock! req-mtx)
                        (vector-set! ans-box 1 #t)
                        (condition-variable-broadcast! req-cv)
                        (mutex-unlock! req-mtx)))
                  (if (not (vector-ref done 0))
                      (loop)))))
            'mbox-owner))))
    (vector gate owner reply-box req-mtx req-cv done count)))

(define (stop-mbox-queue sut)
  (let ((req-mtx (vector-ref sut 3))
        (req-cv (vector-ref sut 4))
        (done (vector-ref sut 5))
        (owner (vector-ref sut 1)))
    (mutex-lock! req-mtx)
    (vector-set! done 0 #t)
    (condition-variable-broadcast! req-cv)
    (mutex-unlock! req-mtx)
    (thread-join! owner)))

(define (exec-mbox-queue sut op)
  (let ((gate (vector-ref sut 0))
        (owner (vector-ref sut 1))
        (reply-box (vector-ref sut 2))
        (req-mtx (vector-ref sut 3))
        (req-cv (vector-ref sut 4))
        (count (vector-ref sut 6)))
    (mutex-lock! gate)
    (let ((res
           (case (car op)
             ((enq)
              (thread-send owner (cadr op))
              (vector-set! count 0 (+ (vector-ref count 0) 1))
              'ok)
             ((deq size)
              (let ((ans (vector #f #f)))
                (mutex-lock! req-mtx)
                (vector-set! reply-box 0 (cons (car op) ans))
                (condition-variable-broadcast! req-cv)
                (let wait ()
                  (if (not (vector-ref ans 1))
                      (begin
                        (mutex-unlock! req-mtx req-cv)
                        (mutex-lock! req-mtx)
                        (wait))))
                (mutex-unlock! req-mtx)
                (vector-ref ans 0))))))
      (mutex-unlock! gate)
      res)))

(define (gen-queue-op rng)
  (let ((k (prng-int! rng 3)))
    (case k
      ((0) (list 'enq (+ 100 (prng-int! rng 50))))
      ((1) (list 'deq))
      (else (list 'size)))))

;;; ============================================================================
;;; Suite 3: Mutex Mutual-Exclusion & State-Transition Linearizability
;;; Uses real Gambit mutex-lock! / mutex-unlock! / mutex-lock! with 0-timeout
;;; to verify strictly one owner at a time with zero lost unlocks under GC.
;;; ============================================================================
(define (run-mutex-exclusion-lin trials)
  (let loop ((t 0) (total-cs 0))
    (if (= t trials)
        total-cs
        (let* ((m (make-mutex 'excl-lin))
               (inside (vector 0))
               (overlap (vector 0))
               (counter (vector 0))
               (nthreads 4)
               (iters 250)
               (threads
                (let mk ((i 0) (acc '()))
                  (if (= i nthreads)
                      acc
                      (mk (+ i 1)
                          (cons
                           (thread-start!
                            (make-thread
                             (lambda ()
                               (let step ((j 0))
                                 (if (< j iters)
                                     (let ((got (if (= (modulo j 5) 0)
                                                    (mutex-lock! m 0)
                                                    (mutex-lock! m))))
                                       (if got
                                           (begin
                                             (let ((cur (vector-ref inside 0)))
                                               (if (not (= cur 0))
                                                   (vector-set! overlap 0 (+ (vector-ref overlap 0) 1))))
                                             (vector-set! inside 0 1)
                                             ;; Allocate inside critical section so GC fires while holding mutex
                                             (let ((tmp (make-vector 8 j)))
                                               (vector-set! counter 0 (+ (vector-ref counter 0)
                                                                         (if (= (vector-ref tmp 0) j) 1 0))))
                                             (vector-set! inside 0 0)
                                             (mutex-unlock! m)))
                                       (if (= (modulo j 7) 0) (thread-yield!))
                                       (step (+ j 1))))))
                             'excl-w))
                           acc))))))
          (for-each thread-join! threads)
          (mc-assert (= (vector-ref overlap 0) 0) 'mutex-mutual-exclusion-violated t (vector-ref overlap 0))
          (mc-assert (eq? (mutex-state m) 'not-abandoned) 'mutex-final-state-bad (mutex-state m))
          (loop (+ t 1) (+ total-cs (vector-ref counter 0)))))))

;;; Run all linearizability suites under GC-Hammer!
(define (run-suite name trials nthreads ops-per-thread gen-op make-sut stop-sut exec-op init-model step-fn)
  (let ((rng (make-prng 20261125))
        (passed 0))
    (let loop ((i 0))
      (if (< i trials)
          (let* ((prefix (let lp ((k 0) (a '())) (if (= k 3) (reverse a) (lp (+ k 1) (cons (gen-op rng) a)))))
                 (par (let lp ((t 0) (a '()))
                        (if (= t nthreads)
                            (reverse a)
                            (lp (+ t 1)
                                (cons (let lp2 ((j 0) (b '()))
                                        (if (= j ops-per-thread) (reverse b) (lp2 (+ j 1) (cons (gen-op rng) b))))
                                      a)))))
                 (sut-box (vector #f))
                 (res (run-lin-scenario
                       (lambda () (let ((s (make-sut))) (vector-set! sut-box 0 s) s))
                       exec-op init-model step-fn prefix par)))
            (if stop-sut (stop-sut (vector-ref sut-box 0)))
            (mc-assert (eq? (car res) #t) 'linearizability-violation name 'trial i 'verdict (car res) 'events (caddr res))
            (set! passed (+ passed 1))
            (loop (+ i 1)))))
    passed))

(let* ((gc0 (mc-gc-count))
       (res
        (with-gc-hammer
         0.002
         (lambda ()
           (let ((t-ok (run-suite 'sync-table 80 3 4 gen-table-op make-sync-table #f exec-sync-table '() table-model-step))
                 (q-ok (run-suite 'mbox-queue 60 3 3 gen-queue-op make-mbox-queue stop-mbox-queue exec-mbox-queue '() queue-model-step))
                 (m-cs (run-mutex-exclusion-lin 40)))
             (list t-ok q-ok m-cs)))))
       (counts (car res))
       (pulses (cdr res))
       (gc-delta (- (mc-gc-count) gc0)))
  (mc-assert (> gc-delta 0) 'gc-hammer-no-collections gc-delta)
  (display (list 'GAMBIT-LIN-PASS
                 'procs (mc-processor-count)
                 'sync-table-trials (car counts)
                 'mbox-queue-trials (cadr counts)
                 'mutex-cs (caddr counts)
                 'gc-pulses pulses
                 'gc-total gc-delta))
  (newline)
  (force-output))
