;;;============================================================================
;;; C16: SRFI-230 Barriered Atomics & Chase-Lev Parallel Stdlib Multicore PBT
;;;
;;; Verifies on real multicore hardware across p1..p12 (and under TSan):
;;;   S1: SRFI-230 atomic-box set!/swap!/cas! with Concurrent SATB Major GC
;;;       and Generational Minor GC (young -> mature card + SATB completeness).
;;;   S2: SRFI-230 atomic-fxbox lock-free linearizability (fetch-add/sub/and/
;;;       ior/xor + cas + swap) under parallel contention.
;;;   S3: SRFI-230 atomic-flag spinlock mutual exclusion + atomic-pair zero-tear
;;;       snapshot consistency under concurrent readers/writers.
;;;   S4: Chase-Lev work-stealing deque (Le et al. PPoPP 2013) exact-once task
;;;       delivery across dynamic ring resizes (4 -> 8 -> ... -> 4096) with
;;;       concurrent thieves and GC hammer (zero duplicates, zero lost tasks).
;;;   S5: (gambit parallel) nested recursive futures, parallel-map over GC-heavy
;;;       heap allocations, parallel-reduce, and clean exception propagation.
;;;============================================================================

(import (srfi 230))
(import (gambit parallel))

(define (assert-true ok label . info)
  (if (not ok)
      (apply error (string-append "C16-FAIL: " label) info)))

(define (proc-count) (##current-vm-processor-count))

;; ----------------------------------------------------------------------------
;; S1: SRFI-230 atomic-box + generational card + SATB Major GC stress
;; ----------------------------------------------------------------------------
(define (test-srfi230-atomic-box-gc)
  (let* ((procs (proc-count))
         (nworkers (max 4 (min 12 procs)))
         (rounds 600)
         (nboxes 32)
         ;; Promote boxes to mature space FIRST so every store of a freshly
         ;; allocated young vector tests the generational card barrier AND
         ;; every overwrite during concurrent marking tests Yuasa SATB!
         (boxes (make-vector nboxes #f)))
    (let init ((i 0))
      (if (< i nboxes)
          (begin
            (vector-set! boxes i (make-atomic-box (vector 'init i (* i 17))))
            (init (+ i 1)))))
    (##gc)
    (##gc)

    (let* ((done-box (make-atomic-fxbox 0))
           (gc-pulses (make-atomic-fxbox 0))
           (gc-thread
            (thread-start!
             (make-thread
              (lambda ()
                (let loop ()
                  (if (< (atomic-fxbox-ref done-box 'acquire) nworkers)
                      (begin
                        ;; Churn young nursery + occasional explicit GC
                        (let churn ((k 0))
                          (if (< k 400)
                              (begin (make-vector 64 k) (churn (+ k 1)))))
                        (if (= (modulo (atomic-fxbox-fetch-add! gc-pulses 1 'relaxed) 5) 0)
                            (##gc))
                        (thread-yield!)
                        (loop)))))))))
      (let ((workers
             (let spawn ((w 0) (acc '()))
               (if (= w nworkers)
                   acc
                   (spawn
                    (+ w 1)
                    (cons
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (let ((retained (make-vector 16 #f)))
                           (let loop ((r 0))
                             (if (< r rounds)
                                 (let* ((bi (modulo (+ (* w 7) r) nboxes))
                                        (bx (vector-ref boxes bi))
                                        (tag (+ (* w 100000) r))
                                        ;; Fresh young heap object stored into mature atomic-box!
                                        (fresh (vector 'payload tag (* tag 3) (cons 'k tag)))
                                        (op (modulo r 3)))
                                   (cond
                                    ((= op 0)
                                     (atomic-box-set! bx fresh 'release))
                                    ((= op 1)
                                     (let ((old (atomic-box-swap! bx fresh 'acquire-release)))
                                       (assert-true (vector? old) "s1-swap-vec" old)
                                       (assert-true (or (eq? (vector-ref old 0) 'init)
                                                        (eq? (vector-ref old 0) 'payload))
                                                    "s1-swap-tag" old)
                                       ;; Retain popped mature/young object across GCs!
                                       (vector-set! retained (modulo r 16) old)))
                                    (else
                                     (let* ((cur (atomic-box-ref bx 'acquire))
                                            (prev (atomic-box-compare-and-swap!
                                                   bx cur fresh 'sequentially-consistent)))
                                       (assert-true (vector? prev) "s1-cas-vec" prev)
                                       (if (eq? prev cur)
                                           (vector-set! retained (modulo r 16) prev)))))
                                   ;; Verify all retained objects stayed intact across GCs
                                   (let ((chk (vector-ref retained (modulo r 16))))
                                     (if chk
                                         (begin
                                           (assert-true (vector? chk) "s1-retained-vec" chk)
                                           (if (eq? (vector-ref chk 0) 'payload)
                                               (let ((tg (vector-ref chk 1)))
                                                 (assert-true (= (vector-ref chk 2) (* tg 3))
                                                              "s1-retained-mul" chk)
                                                 (assert-true (= (cdr (vector-ref chk 3)) tg)
                                                              "s1-retained-pair" chk))))))
                                   (loop (+ r 1)))))
                           (atomic-fxbox-fetch-add! done-box 1 'release)))))
                     acc))))))
        (for-each thread-join! workers)
        (thread-join! gc-thread)))

    ;; Final GC + full validation of every mature atomic-box
    (##gc)
    (let verify ((i 0))
      (if (< i nboxes)
          (let ((v (atomic-box-ref (vector-ref boxes i) 'sequentially-consistent)))
            (assert-true (vector? v) "s1-final-vec" i v)
            (if (eq? (vector-ref v 0) 'payload)
                (let ((tg (vector-ref v 1)))
                  (assert-true (= (vector-ref v 2) (* tg 3)) "s1-final-mul" i v)
                  (assert-true (= (cdr (vector-ref v 3)) tg) "s1-final-pair" i v)))
            (verify (+ i 1)))))
    (* nworkers rounds)))

;; ----------------------------------------------------------------------------
;; S2: SRFI-230 atomic-fxbox arithmetic & bitwise linearizability
;; ----------------------------------------------------------------------------
(define (test-srfi230-fxbox-linearizability)
  (let* ((nworkers (max 4 (min 12 (proc-count))))
         (iters 4000)
         (sum-box (make-atomic-fxbox 0))
         (xor-box (make-atomic-fxbox 0))
         (ior-box (make-atomic-fxbox 0))
         (and-box (make-atomic-fxbox #xffffff))
         (cas-box (make-atomic-fxbox 0)))
    (let ((workers
           (let spawn ((w 0) (acc '()))
             (if (= w nworkers)
                 acc
                 (spawn
                  (+ w 1)
                  (cons
                   (thread-start!
                    (make-thread
                     (lambda ()
                       (let ((bit (arithmetic-shift 1 (modulo w 20))))
                         (atomic-fxbox-fetch-ior! ior-box bit 'acquire-release)
                         (atomic-fxbox-fetch-and! and-box (bitwise-not bit) 'acquire-release))
                       (let loop ((i 0))
                         (if (< i iters)
                             (begin
                               (atomic-fxbox-fetch-add! sum-box 3 'relaxed)
                               (atomic-fxbox-fetch-sub! sum-box 1 'relaxed)
                               (atomic-fxbox-fetch-xor! xor-box #x5a5a 'relaxed)
                               ;; CAS increment loop
                               (let retry ((cur (atomic-fxbox-ref cas-box 'acquire)))
                                 (let ((prev (atomic-fxbox-compare-and-swap!
                                              cas-box cur (+ cur 1) 'acquire-release)))
                                   (if (not (= prev cur)) (retry prev))))
                               (loop (+ i 1))))))))
                   acc))))))
      (for-each thread-join! workers))

    (let ((expected-sum (* nworkers iters 2))
          (expected-cas (* nworkers iters))
          (expected-ior (- (arithmetic-shift 1 (min nworkers 20)) 1)))
      (assert-true (= (atomic-fxbox-ref sum-box) expected-sum)
                   "s2-sum" (atomic-fxbox-ref sum-box) expected-sum)
      (assert-true (= (atomic-fxbox-ref cas-box) expected-cas)
                   "s2-cas" (atomic-fxbox-ref cas-box) expected-cas)
      ;; Even number of XORs (iters=4000 is even) -> returns to 0!
      (assert-true (= (atomic-fxbox-ref xor-box) 0)
                   "s2-xor" (atomic-fxbox-ref xor-box))
      (assert-true (= (atomic-fxbox-ref ior-box) expected-ior)
                   "s2-ior" (atomic-fxbox-ref ior-box) expected-ior)
      (assert-true (= (atomic-fxbox-ref and-box) (bitwise-and #xffffff (bitwise-not expected-ior)))
                   "s2-and" (atomic-fxbox-ref and-box))
      expected-cas)))

;; ----------------------------------------------------------------------------
;; S3: SRFI-230 atomic-flag spinlock + atomic-pair zero-tear snapshots
;; ----------------------------------------------------------------------------
(define (test-srfi230-flag-and-pair)
  (let* ((nworkers (max 4 (min 12 (proc-count))))
         (iters 1000)
         (flag (make-atomic-flag))
         (protected-counter (vector 0))
         (apair (make-atomic-pair 0 0))
         (tear-errors (make-atomic-fxbox 0)))
    (let ((workers
           (let spawn ((w 0) (acc '()))
             (if (= w nworkers)
                 acc
                 (spawn
                  (+ w 1)
                  (cons
                   (thread-start!
                    (make-thread
                     (lambda ()
                       (let loop ((i 0))
                         (if (< i iters)
                             (begin
                               ;; Spinlock critical section via atomic-flag
                               (let acquire ()
                                 (if (atomic-flag-test-and-set! flag 'acquire)
                                     (begin (thread-yield!) (acquire))))
                               (vector-set! protected-counter 0
                                            (+ (vector-ref protected-counter 0) 1))
                               (atomic-flag-clear! flag 'release)

                               ;; Atomic pair concurrent (k, k) zero-tear publish & observe
                               (let ((k (+ (* w 10000) i 1)))
                                 (if (= (modulo i 2) 0)
                                     (atomic-pair-set! apair k k 'release)
                                     (call-with-values
                                      (lambda () (atomic-pair-swap! apair k k 'acquire-release))
                                      (lambda (a b)
                                        (if (not (= a b))
                                            (atomic-fxbox-fetch-add! tear-errors 1 'relaxed)))))
                                 (call-with-values
                                  (lambda () (atomic-pair-ref apair 'acquire))
                                  (lambda (a b)
                                    (if (not (= a b))
                                        (atomic-fxbox-fetch-add! tear-errors 1 'relaxed)))))
                               (loop (+ i 1))))))))
                   acc))))))
      (for-each thread-join! workers))

    (assert-true (= (vector-ref protected-counter 0) (* nworkers iters))
                 "s3-flag-mutex" (vector-ref protected-counter 0) (* nworkers iters))
    (assert-true (= (atomic-fxbox-ref tear-errors) 0)
                 "s3-pair-zero-tear" (atomic-fxbox-ref tear-errors))
    (* nworkers iters)))

;; ----------------------------------------------------------------------------
;; S4: Chase-Lev Work-Stealing Deque Exact-Once Linearizability + Resize + GC
;; ----------------------------------------------------------------------------
(define (test-chase-lev-exact-once)
  (let* ((ntasks 10000)
         (nthieves (max 3 (min 11 (max 3 (- (proc-count) 1)))))
         (q (make-work-stealing-deque 4)) ;; tiny initial cap forces 4->8->...->4096 resizes!
         (seen (make-vector ntasks 0))    ;; atomic per-task execution count (must be 1!)
         (done-push (make-atomic-fxbox 0))
         (stolen-total (make-atomic-fxbox 0))
         (popped-total (make-atomic-fxbox 0))
         (dup-errors (make-atomic-fxbox 0))
         (empty-tag (list 'empty))
         (abort-tag (list 'abort)))
    (define (record-task! x)
      (assert-true (and (pair? x) (fixnum? (car x)) (= (cdr x) (* (car x) 7)))
                   "s4-task-payload-intact" x)
      (let* ((id (car x))
             (prev (##vector-inc! seen id 1)))
        (if (not (= prev 0))
            (atomic-fxbox-fetch-add! dup-errors 1 'relaxed))))

    (let ((thieves
           (let spawn ((k 0) (acc '()))
             (if (= k nthieves)
                 acc
                 (spawn
                  (+ k 1)
                  (cons
                   (thread-start!
                    (make-thread
                     (lambda ()
                       (let loop ()
                         (let ((x (deque-steal! q empty-tag abort-tag)))
                           (cond
                            ((eq? x abort-tag)
                             (loop))
                            ((eq? x empty-tag)
                             (if (= (atomic-fxbox-ref done-push 'acquire) 0)
                                 (begin (thread-yield!) (loop))
                                 ;; Final drain check after owner signaled done
                                 (let ((x2 (deque-steal! q empty-tag abort-tag)))
                                   (cond
                                    ((eq? x2 abort-tag) (loop))
                                    ((eq? x2 empty-tag) #t)
                                    (else
                                     (record-task! x2)
                                     (atomic-fxbox-fetch-add! stolen-total 1 'relaxed)
                                     (loop))))))
                            (else
                             (record-task! x)
                             (atomic-fxbox-fetch-add! stolen-total 1 'relaxed)
                             (loop))))))))
                   acc))))))
      ;; Owner pushes in waves, interspersing LIFO pops and explicit GCs!
      (let push ((i 0))
        (if (< i ntasks)
            (begin
              (deque-push-bottom! q (cons i (* i 7)))
              ;; Pop every 3rd task from bottom so owner & thieves collide constantly!
              (if (= (modulo i 3) 2)
                  (let ((x (deque-pop-bottom! q empty-tag)))
                    (if (not (eq? x empty-tag))
                        (begin
                          (record-task! x)
                          (atomic-fxbox-fetch-add! popped-total 1 'relaxed)))))
              (if (= (modulo i 2500) 2499)
                  (##gc))
              (push (+ i 1)))))
      ;; Drain remaining local tasks on owner
      (let drain ()
        (let ((x (deque-pop-bottom! q empty-tag)))
          (if (not (eq? x empty-tag))
              (begin
                (record-task! x)
                (atomic-fxbox-fetch-add! popped-total 1 'relaxed)
                (drain)))))
      (atomic-fxbox-set! done-push 1 'release)
      (for-each thread-join! thieves))

    (assert-true (= (atomic-fxbox-ref dup-errors) 0)
                 "s4-zero-duplicates" (atomic-fxbox-ref dup-errors))
    (let verify ((i 0))
      (if (< i ntasks)
          (begin
            (assert-true (= (vector-ref seen i) 1) "s4-exact-once" i (vector-ref seen i))
            (verify (+ i 1)))))
    (list ntasks (atomic-fxbox-ref popped-total) (atomic-fxbox-ref stolen-total))))

;; ----------------------------------------------------------------------------
;; S5: (gambit parallel) Nested Futures + parallel-map + parallel-reduce + Exc
;; ----------------------------------------------------------------------------
(define (test-parallel-stdlib)
  (let ((pool (make-work-stealing-pool)))
    (parameterize ((current-work-stealing-pool pool))
      ;; 1. Deeply nested recursive parallel Fibonacci (tests work-stealing helping!)
      (letrec ((seq-fib (lambda (n)
                          (if (< n 2) n (+ (seq-fib (- n 1)) (seq-fib (- n 2))))))
               (par-fib (lambda (n)
                          (if (<= n 14)
                              (seq-fib n)
                              (let ((f (future (par-fib (- n 2)))))
                                (+ (par-fib (- n 1)) (future-force f)))))))
        (assert-true (= (par-fib 24) 46368) "s5-par-fib24"))

      ;; 2. GC-heavy parallel-map + parallel-reduce over 2,000 items
      (let* ((n 2000)
             (input (let loop ((i 0) (acc '()))
                      (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc)))))
             (mapped (parallel-map
                      (lambda (k)
                        (let ((tmp (make-vector 16 k)))
                          (+ (* (vector-ref tmp 0) 2) 1)))
                      input
                      32))
             (total (parallel-reduce + 0 mapped 32))
             ;; sum_{k=0}^{n-1} (2k + 1) = n^2
             (expected (* n n)))
        (assert-true (= (length mapped) n) "s5-map-len" (length mapped))
        (assert-true (= total expected) "s5-reduce-sum" total expected))

      ;; 3. Exception propagation without poisoning the worker pool
      (let ((bad (future (error "c16-expected-exception" 999)))
            (caught #f))
        (with-exception-catcher
         (lambda (e)
           (if (and (error-exception? e)
                    (equal? (error-exception-message e) "c16-expected-exception"))
               (set! caught #t)))
         (lambda () (future-force bad)))
        (assert-true caught "s5-future-exception-propagated"))

      ;; Pool still healthy after exception!
      (assert-true (= (future-force (future (+ 100 23))) 123) "s5-pool-healthy-after-exc"))
    (work-stealing-pool-shutdown! pool)
    #t))

(define (main)
  (let* ((s1 (test-srfi230-atomic-box-gc))
         (s2 (test-srfi230-fxbox-linearizability))
         (s3 (test-srfi230-flag-and-pair))
         (s4 (test-chase-lev-exact-once))
         (s5 (test-parallel-stdlib)))
    (write (list 'C16-SRFI230-ATOMICS-CHASE-LEV-PASS
                 'procs (proc-count)
                 'box-ops s1
                 'fxbox-cas s2
                 'flag-pair-ops s3
                 'chase-lev s4
                 'parallel-ok s5))
    (newline)))

(main)
