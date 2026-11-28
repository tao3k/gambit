;;;============================================================================

;;; File: "test.scm"

;;; (gambit effect) — Unit & 12-Core SMP Algebraic Effect Handler Tests

(import (gambit effect))
(import (srfi 226))
(import (srfi 230))
(import (_test))

(define (raises-error? thunk)
  (with-exception-catcher
   (lambda (e) #t)
   (lambda () (thunk) #f)))

;;;============================================================================
;;; 1. Effect Identity & Koka Tail-Resumptive Fast Path

(define-effect ask)
(define-effect get-state)
(define-effect put-state)
(define-effect emit)
(define-effect fail)
(define-effect choose)

(test-equal #t (effect? ask))
(test-equal 'ask (effect-name ask))
(test-equal #f (effect? 'ask))

;; Pure tail-resumptive Reader effect (zero continuation capture)
(test-equal 142
  (with-handler
    ((tail: ask () 42))
    (+ 100 (perform ask))))

;; Nested tail-resumptive shadowing
(test-equal '(10 20 10)
  (with-handler
    ((tail: ask () 10))
    (let ((a (perform ask))
          (b (with-handler
               ((tail: ask () 20))
               (perform ask)))
          (c (perform ask)))
      (list a b c))))

;; Tail-resumptive mutable State + return transform
(test-equal '(55 . 10)
  (let ((s 0))
    (with-handler
      ((tail: get-state () s)
       (tail: put-state (v) (set! s v))
       (return: (r) (cons r s)))
      (let loop ((i 1) (acc 0))
        (if (fx> i 10)
            acc
            (begin
              (perform put-state i)
              (loop (fx+ i 1) (fx+ acc (perform get-state)))))))))

;;;============================================================================
;;; 2. Suspending One-Shot Effects & Non-Resuming Abort

;; Deep handler collecting emitted values via one-shot resume
(test-equal '(1 2 3 4)
  (with-handler
    ((emit (k v) (cons v (resume k #f)))
     (return: (r) '()))
    (perform emit 1)
    (perform emit 2)
    (perform emit 3)
    (perform emit 4)))

;; Abort effect (handler discards k and returns immediately)
(test-equal '(failed division-by-zero)
  (with-handler
    ((fail (k reason) (list 'failed reason)))
    (+ 1 (perform fail 'division-by-zero) 999)))

;; Nested composition of tail-resumptive + suspending handlers
(test-equal '(10 20 30)
  (with-handler
    ((tail: ask () 10))
    (with-handler
      ((emit (k v) (cons v (resume k #f)))
       (return: (r) '()))
      (perform emit (* 1 (perform ask)))
      (perform emit (* 2 (perform ask)))
      (perform emit (* 3 (perform ask))))))

;; One-shot safety: calling `resume` twice without `resume-multishot` raises
(test-equal #t
  (with-handler
    ((emit (k v)
       (let ((first (resume k #f)))
         (raises-error? (lambda () (resume k #f))))))
    (perform emit 'once)
    'done))

;;;============================================================================
;;; 3. Lazy Multi-Shot Promotion (resume-multishot)

;; Cartesian product via multi-shot backtracking
(test-equal '((#t . #t) (#t . #f) (#f . #t) (#f . #f))
  (with-handler
    ((choose (k)
       (append (resume-multishot k #t)
               (resume-multishot k #f)))
     (return: (x) (list x)))
    (let ((a (perform choose))
          (b (perform choose)))
      (cons a b))))

;; Multi-shot search: sum-to-5 pairs from {1,2,3,4}
(define-effect pick)
(test-equal '((1 . 4) (2 . 3) (3 . 2) (4 . 1))
  (with-handler
    ((pick (k xs)
       (let loop ((rem xs) (acc '()))
         (if (null? rem)
             acc
             (loop (cdr rem)
                   (append acc (resume-multishot k (car rem)))))))
     (return: (v) (if v (list v) '())))
    (let ((a (perform pick '(1 2 3 4)))
          (b (perform pick '(1 2 3 4))))
      (if (fx= (fx+ a b) 5) (cons a b) #f))))

;;;============================================================================
;;; 4. Direct-Style Generators (make-generator / yield)

;; Finite generator
(let ((g (make-generator
          (lambda ()
            (perform yield 'a)
            (perform yield 'b)
            (perform yield 'c)))))
  (test-equal 'a (g))
  (test-equal 'b (g))
  (test-equal 'c (g))
  (test-equal #!eof (g))
  (test-equal #!eof (g)))

;; Infinite Fibonacci generator
(let ((fib (make-generator
            (lambda ()
              (let loop ((a 0) (b 1))
                (perform yield a)
                (loop b (+ a b)))))))
  (test-equal '(0 1 1 2 3 5 8 13)
    (list (fib) (fib) (fib) (fib) (fib) (fib) (fib) (fib))))

;;;============================================================================
;;; 5. 12-Core SMP Concurrency & One-Shot Resume Linearizability

;; 5a. Adaptive-P threads running independent tail + suspending + multi-shot effects
(let ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
      (ok-count (make-atomic-fxbox 0)))
  (let ((threads
         (let loop ((i 0) (acc '()))
           (if (fx= i num-threads)
               acc
               (loop (fx+ i 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          ;; Tail-resumptive loop
                          (let ((tail-sum
                                 (with-handler
                                   ((tail: ask () i))
                                   (let s ((n 0) (tot 0))
                                     (if (fx= n 200)
                                         tot
                                         (s (fx+ n 1) (fx+ tot (perform ask))))))))
                            ;; Generator
                            (let ((g (make-generator
                                      (lambda ()
                                        (let k ((j 0))
                                          (if (fx< j 20)
                                              (begin (perform yield (fx+ i j))
                                                     (k (fx+ j 1)))))))))
                              (let gloop ((gsum 0))
                                (let ((v (g)))
                                  (if (eof-object? v)
                                      (if (and (fx= tail-sum (fx* 200 i))
                                               (fx= gsum (fx+ (fx* 20 i) 190)))
                                          (atomic-fxbox+/fetch! ok-count 1))
                                      (gloop (fx+ gsum v))))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; 5b. 12 threads racing to `resume` the SAME one-shot effect-continuation
(let ((num-threads (max 4 (min 16 (##current-vm-processor-count))))
      (rounds 30)
      (total-winners (make-atomic-fxbox 0))
      (total-rejected (make-atomic-fxbox 0)))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let ((shared-ek #f)
              (round-winners (make-atomic-fxbox 0))
              (round-rejected (make-atomic-fxbox 0))
              (go-flag (make-atomic-fxbox 0)))
          (with-handler
            ((emit (k v)
               (set! shared-ek k)
               'suspended))
            (+ 1 (perform emit r)))
          (let ((threads
                 (let tloop ((i 0) (acc '()))
                   (if (fx= i num-threads)
                       acc
                       (tloop (fx+ i 1)
                              (cons
                               (thread-start!
                                (make-thread
                                 (lambda ()
                                   (let spin ()
                                     (if (fx= (atomic-fxbox-ref go-flag) 0)
                                         (begin (thread-yield!) (spin))))
                                   (with-exception-catcher
                                    (lambda (e)
                                      (atomic-fxbox+/fetch! round-rejected 1))
                                    (lambda ()
                                      (let ((res (resume shared-ek r)))
                                        (if (fx= res (fx+ r 1))
                                            (atomic-fxbox+/fetch! round-winners 1))))))))
                               acc))))))
            (atomic-fxbox-set! go-flag 1)
            (for-each thread-join! threads)
            (test-equal 1 (atomic-fxbox-ref round-winners))
            (test-equal (fx- num-threads 1) (atomic-fxbox-ref round-rejected))
            (atomic-fxbox+/fetch! total-winners (atomic-fxbox-ref round-winners))
            (atomic-fxbox+/fetch! total-rejected (atomic-fxbox-ref round-rejected))
            (rloop (fx+ r 1))))))
  (test-equal rounds (atomic-fxbox-ref total-winners))
  (test-equal (fx* rounds (fx- num-threads 1)) (atomic-fxbox-ref total-rejected)))

;;;============================================================================
;;; 6. ZGC-Style Stack Watermark × SATB Concurrent Major GC Stress Test
;;;
;;; Verifies that returning across handler_break during concurrent SATB major
;;; marking preserves all live objects across 12 cores and exercises the
;;; stack watermark return barrier.

(test-equal #t (fixnum? (##gc-stack-watermark-shaded-frames)))
(test-equal #t (fx>= (##gc-stack-watermark-shaded-frames) 0))

(let ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
      (ok (make-atomic-fxbox 0)))
  (let ((threads
         (let loop ((i 0) (acc '()))
           (if (fx= i num-threads)
               acc
               (loop (fx+ i 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          ;; Deep suspending effect + heap allocation to trigger
                          ;; concurrent SATB major marking across break frames
                          (let ((res
                                 (with-handler
                                   ((emit (k v)
                                      (let ((box (vector v (make-vector 64 v))))
                                        (let ((tail (resume k (vector-ref box 0))))
                                          (fx+ (vector-ref (vector-ref box 1) 0) tail))))
                                    (return: (r) r))
                                   (let iloop ((j 0) (s 0))
                                     (if (fx= j 250)
                                         s
                                         (iloop (fx+ j 1)
                                                (fx+ s (perform emit j))))))))
                            (if (fx= res 62250)
                                (atomic-fxbox+/fetch! ok 1))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok))))

;;;============================================================================
;;; 7. One-Shot Stack-Rewind Verification & Escaped-Handle GC Safety
;;;
;;; Verifies that tail-resuming one-shot handlers trigger the C-runtime
;;; in-place stack-rewind fast path and that holding a consumed `ek` handle
;;; across a full GC after stack rewind is 100% memory-safe.

;; Finish any pending concurrent SATB major GC started by Test #6 so
;; satb_active_ == 0 (in-place stack rewind intentionally refuses while
;; SATB marking is active to prevent dangling stack-continuation pointers).
(##gc)

(let ((rw-before (##gc-oneshot-continuation-rewinds))
      (escaped-eks '()))
  (let ((res
         (with-handler
           ((emit (k v)
              (set! escaped-eks (cons k escaped-eks))
              (resume k (fx+ v 1))))
           (let loop ((i 0) (acc 0))
             (if (fx< i 200)
                 (loop (fx+ i 1) (perform emit acc))
                 acc)))))
    (test-equal 200 res)
    (test-equal #t (fx>= (fx- (##gc-oneshot-continuation-rewinds) rw-before) 180))
    ;; Force GC while retaining all 200 consumed effect-continuation handles
    (##gc)
    (test-equal 200 (length escaped-eks))
    ;; Every retained handle must still report consumed and reject re-invocation
    (test-equal #t (raises-error? (lambda () (resume (car escaped-eks) 0))))
    (test-equal #t (raises-error? (lambda () (resume-multishot (car escaped-eks) 0))))))

;;;============================================================================
;;; 8. Lexa OOPSLA '24 / Effekt OOPSLA '23 O(1) Lexical Capability Handles

;; Tail capability: O(1) direct dispatch (zero handler-chain walk)
(test-equal 55
  (with-capability-handler add-cap
    (tail: (x y) (fx+ x y))
    (test-equal #t (effect-capability? add-cap))
    (let loop ((i 1) (acc 0))
      (if (fx> i 10)
          acc
          (loop (fx+ i 1) (perform-cap add-cap acc i))))))

;; Suspending capability: direct prompt jump + one-shot rewind
(test-equal 100
  (with-capability-handler step-cap
    ((k x) (resume k (fx+ x 1)))
    (let loop ((i 0) (acc 0))
      (if (fx< i 100)
          (loop (fx+ i 1) (perform-cap step-cap acc))
          acc))))

;; Deeply nested capability handles: outer capability remains O(1) without
;; scanning inner handlers
(test-equal '(outer-10 inner-20)
  (with-capability-handler outer-cap
    (tail: (x) (list 'outer-10 x))
    (with-capability-handler inner-cap
      (tail: (x) (list 'inner-20 x))
      (list (car (perform-cap outer-cap 1))
            (car (perform-cap inner-cap 2))))))

;;;============================================================================
;;; 9. 12-Core SMP Adversarial Linear One-Shot Race & Multi-Shot Nested-Handler
;;;    Concurrent Replay + Downstream Snapshot Verification

;; 9a. 12 threads simultaneously race to consume the SAME linear one-shot
;;     effect continuation via `resume` (and competing `resume-multishot`).
;;     For a linear effect, strictly 1 caller succeeds when `resume` wins;
;;     consumed continuations never re-execute.
(let ((num-threads (max 4 (min 16 (##current-vm-processor-count))))
      (rounds 30)
      (linear-eff (make-effect 'smp-linear-race))
      (total-winners (make-atomic-fxbox 0))
      (total-rejected (make-atomic-fxbox 0)))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let ((shared-ek #f)
              (round-winners (make-atomic-fxbox 0))
              (round-rejected (make-atomic-fxbox 0))
              (side-effect-count (make-atomic-fxbox 0))
              (go-flag (make-atomic-fxbox 0)))
          (with-handler
            ((linear-eff (k x)
               (set! shared-ek k)
               'suspended))
            (let ((v (perform linear-eff r)))
              (atomic-fxbox+/fetch! side-effect-count 1)
              (fx+ v 1000)))
          (let ((threads
                 (let tloop ((i 0) (acc '()))
                   (if (fx= i num-threads)
                       acc
                       (tloop (fx+ i 1)
                              (cons
                               (thread-start!
                                (make-thread
                                 (lambda ()
                                   (let spin ()
                                     (if (fx= (atomic-fxbox-ref go-flag) 0)
                                         (begin (thread-yield!) (spin))))
                                   (with-exception-catcher
                                    (lambda (e)
                                      (atomic-fxbox+/fetch! round-rejected 1))
                                    (lambda ()
                                      (let ((res (resume shared-ek r)))
                                        (if (fx= res (fx+ r 1000))
                                            (atomic-fxbox+/fetch! round-winners 1))))))))
                               acc))))))
            (atomic-fxbox-set! go-flag 1)
            (for-each thread-join! threads)
            (test-equal 1 (atomic-fxbox-ref side-effect-count))
            (test-equal 1 (atomic-fxbox-ref round-winners))
            (test-equal (fx- num-threads 1) (atomic-fxbox-ref round-rejected))
            (atomic-fxbox+/fetch! total-winners (atomic-fxbox-ref round-winners))
            (atomic-fxbox+/fetch! total-rejected (atomic-fxbox-ref round-rejected))
            (rloop (fx+ r 1))))))
  (test-equal rounds (atomic-fxbox-ref total-winners))
  (test-equal (fx* rounds (fx- num-threads 1)) (atomic-fxbox-ref total-rejected)))

;; 9b. Multi-shot effect continuation capturing an inner nested effect handler
;;     frame in its prefix: concurrently replayed across 12 SMP threads while
;;     each shot exits through the shared inner prompt frame (verifies frozen
;;     prefix frames never clear escape-k in-place under concurrent readers).
(let ((outer-eff (make-effect 'smp-outer-multi))
      (inner-eff (make-effect 'smp-inner-multi))
      (shared-ek #f)
      (num-threads (max 4 (min 16 (##current-vm-processor-count))))
      (shots-per-thread 30)
      (ok-shots (make-atomic-fxbox 0)))
  (with-handler
    ((outer-eff (k seed)
       (set! shared-ek k)
       'captured))
    (with-handler
      ((inner-eff (k v)
         (resume k (fx+ v 10)))
       (return: (r) (fx* r 2)))
      (let* ((a (perform outer-eff 0))
             (b (perform inner-eff a)))
        (fx+ b 5))))
  (test-equal #t (effect-continuation? shared-ek))
  ;; Promote once to MULTISHOT_COW before concurrent multi-core replay
  (test-equal 30 (resume-multishot shared-ek 0))
  (let ((threads
         (let tloop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (tloop (fx+ t 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let sloop ((s 0))
                             (if (fx< s shots-per-thread)
                                 (let* ((arg (fx+ (fx* t 50) s))
                                        (res (resume-multishot shared-ek arg))
                                        (expected (fx* (fx+ (fx+ arg 10) 5) 2)))
                                   (if (fx= res expected)
                                       (atomic-fxbox+/fetch! ok-shots 1))
                                   (if (and (fx= t 0) (fx= (fxand s 15) 15))
                                       (##gc))
                                   (sloop (fx+ s 1))))))))
                       acc))))))
    (for-each thread-join! threads)
    (test-equal (fx* num-threads shots-per-thread) (atomic-fxbox-ref ok-shots))))

;;;============================================================================
;;; 10. Adversarial Generator Safety (dynamic-wind, Nested Multi-Shot, SMP
;;;     Concurrent Race, SATB Torture & Work-Stealing Fiber Migration)

;; 10a. Generator with dynamic-wind inside body: denv guard MUST decline
;;      no-winding fast return and fire before/after thunks on every yield/resume.
(let ((log '()))
  (let ((g (make-generator
            (lambda ()
              (dynamic-wind
                (lambda () (set! log (cons 'in log)))
                (lambda ()
                  (perform yield 1)
                  (perform yield 2))
                (lambda () (set! log (cons 'out log))))))))
    (test-equal 1 (g))
    (test-equal 2 (g))
    (test-equal #!eof (g))
    (test-equal '(in out in out in out) (reverse log))))

;; 10b. Nested multi-shot handler inside a generator: frozen pframe COW safety
(let ((g (make-generator
          (lambda ()
            (let ((res
                   (with-handler
                     ((choose (k)
                        (append (resume-multishot k 10)
                                (resume-multishot k 20)))
                      (return: (x) (list x)))
                     (let ((a (perform choose)))
                       (perform yield a)
                       (fx+ a 1)))))
              (perform yield res))))))
  (test-equal 10 (g))
  (test-equal 20 (g))
  (test-equal '(11 21) (g))
  (test-equal #!eof (g)))

;; 10c. SMP concurrent race on the SAME generator (adaptive P threads):
;;      exactly 1 thread wins each step; losers observe RUNNING or DONE cleanly
;;      with zero double-resume corruption.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (steps 40)
       (g (make-generator
           (lambda ()
             (let loop ((i 0))
               (if (fx< i steps)
                   (begin
                     (perform yield i)
                     (loop (fx+ i 1))))))))
       (seen (make-vector steps 0))
       (dup-err (make-atomic-fxbox 0))
       (val-sum (make-atomic-fxbox 0)))
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let gloop ()
                            (let ((v (with-exception-catcher
                                      (lambda (e) 'busy)
                                      (lambda () (g)))))
                              (cond
                                ((eof-object? v) #!void)
                                ((eq? v 'busy) (thread-yield!) (gloop))
                                (else
                                 (let ((prev (##vector-inc! seen v 1)))
                                   (if (not (fx= prev 0))
                                       (atomic-fxbox+/fetch! dup-err 1)))
                                 (atomic-fxbox+/fetch! val-sum v)
                                 (gloop))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal 0 (atomic-fxbox-ref dup-err))
    (test-equal (fxquotient (fx* steps (fx- steps 1)) 2) (atomic-fxbox-ref val-sum))))

;; 10d. Heavy SATB-active concurrent one-shot suspend + generator torture across
;;      adaptive P cores: verifies one-shot rewinds succeed even during concurrent
;;      SATB major GC and mature anchors remain 100% intact.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (anchors (make-vector 100 #f))
       (ok (make-atomic-fxbox 0)))
  (let aloop ((i 0))
    (if (fx< i 100)
        (begin (vector-set! anchors i (make-vector 512 i))
               (aloop (fx+ i 1)))))
  (##gc)
  (let ((rw-before (##gc-oneshot-continuation-rewinds))
        (threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let ((s1
                                 (with-handler
                                   ((emit (k v)
                                      (let ((trash (make-vector 32 v)))
                                        (resume k (fx+ (vector-ref trash 0) 1)))))
                                   (let iloop ((j 0) (a 0))
                                     (if (fx< j 400)
                                         (iloop (fx+ j 1) (perform emit a))
                                         a))))
                                (g (make-generator
                                    (lambda ()
                                      (let gloop ((j 0))
                                        (if (fx< j 400)
                                            (let ((trash (make-vector 32 j)))
                                              (perform yield (vector-ref trash 0))
                                              (gloop (fx+ j 1)))))))))
                            (let sumloop ((s2 0))
                              (let ((v (g)))
                                (if (eof-object? v)
                                    (if (and (fx= s1 400) (fx= s2 79800))
                                        (atomic-fxbox+/fetch! ok 1))
                                    (sumloop (fx+ s2 v)))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok))
    (test-equal #t (fx> (##gc-oneshot-continuation-rewinds) rw-before)))
  (let chk ((i 0))
    (if (fx< i 100)
        (let ((v (vector-ref anchors i)))
          (test-equal i (vector-ref v 0))
          (test-equal i (vector-ref v 511))
          (chk (fx+ i 1))))))

;; 10e. Sequential multi-generator Yield #1 base-anchor preservation stress
;;      across adaptive P threads: verifies Yield #1 keeps caller-k alive as
;;      sub-k's next_break_link anchor (zero break-chain cycle or stack-overflow)
;;      while Yields #2..N reclaim caller-k in O(1).
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (gens-per-thread 60)
       (yields-per-gen 60)
       (expected-gen-sum (fxquotient (fx* yields-per-gen (fx- yields-per-gen 1)) 2))
       (ok (make-atomic-fxbox 0)))
  (let ((threads
         (let tloop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (tloop (fx+ t 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let gloop ((gi 0) (all-good #t))
                             (if (fx< gi gens-per-thread)
                                 (let ((g (make-generator
                                           (lambda ()
                                             (let yloop ((k 0))
                                               (if (fx< k yields-per-gen)
                                                   (begin
                                                     (perform yield k)
                                                     (yloop (fx+ k 1)))))))))
                                   (let sloop ((sum 0))
                                     (let ((v (g)))
                                       (if (eof-object? v)
                                           (begin
                                             (if (and (fx= t 0) (fx= (fxand gi 31) 31))
                                                 (##gc))
                                             (gloop (fx+ gi 1)
                                                    (and all-good (fx= sum expected-gen-sum))))
                                           (sloop (fx+ sum v))))))
                                 (if all-good
                                     (atomic-fxbox+/fetch! ok 1)))))))
                       acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok))))

;;;============================================================================
;;; 11. Exception-Unwind Coherency, Generator Cross-Call Fault Propagation,
;;;     Non-Tail Frozen Anchor Safety & Concurrent resume vs resume-multishot

;; 11a. Suspending `with-handler` & `with-capability-handler` exception unwind:
;;      both body-throws and handler-clause-throws inside an inner catcher
;;      enclosed by an outer prompt must unwind cleanly with after-count == 1
;;      and zero leaked handlers.
(let ((t-outer (make-continuation-prompt-tag 'eff-exn-outer))
      (leaked-eff (make-effect 'eff-exn-leaked))
      (after-count 0))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (let ((v1 (with-exception-catcher
                       (lambda (e) (error-exception-message e))
                       (lambda ()
                         (with-handler ((leaked-eff (k x) (resume k x)))
                           (error "body-boom")))))
                  (v2 (with-exception-catcher
                       (lambda (e) (error-exception-message e))
                       (lambda ()
                         (with-handler ((leaked-eff (k x) (error "clause-boom")))
                           (perform leaked-eff 1)))))
                  (v3 (with-exception-catcher
                       (lambda (e) (error-exception-message e))
                       (lambda ()
                         (with-capability-handler cap ((k x) (resume k x))
                           (error "cap-boom"))))))
              (set! after-count (fx+ after-count 1))
              (test-equal #t (raises-error? (lambda () (perform leaked-eff 99))))
              (list v1 v2 v3)))
          t-outer)))
    (test-equal '("body-boom" "clause-boom" "cap-boom") res)
    (test-equal 1 after-count)))

;; 11b. Generator Call #1 and Call #2 (post-yield) fault propagation inside
;;      caller's with-exception-catcher + dynamic-wind cleanup + DONE state.
(let ((t-outer (make-continuation-prompt-tag 'gen-exn-outer))
      (after-count 0)
      (dw-log '()))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (let ((g1 (make-generator (lambda () (error "gen-call1-boom"))))
                  (g2 (make-generator
                       (lambda ()
                         (dynamic-wind
                           (lambda () (set! dw-log (cons 'in dw-log)))
                           (lambda ()
                             (perform yield 10)
                             (error "gen-call2-boom"))
                           (lambda () (set! dw-log (cons 'out dw-log))))))))
              (let* ((m1 (with-exception-catcher
                          (lambda (e) (list (error-exception-message e) (g1)))
                          (lambda () (g1))))
                     (y1 (g2))
                     (m2 (with-exception-catcher
                          (lambda (e) (list (error-exception-message e) (g2)))
                          (lambda () (g2)))))
                (set! after-count (fx+ after-count 1))
                (list m1 y1 m2 (g1) (g2)))))
          t-outer)))
    (test-equal (list (list "gen-call1-boom" #!eof)
                      10
                      (list "gen-call2-boom" #!eof)
                      #!eof
                      #!eof)
                res)
    (test-equal 1 after-count)
    (test-equal '(in out in out) (reverse dw-log))))

;; 11c. Cross-thread generator fault propagation: Thread A runs Call #1 (yields),
;;      Thread B runs Call #2 inside Thread B's with-exception-catcher where the
;;      generator throws; Thread B's catcher must catch it cleanly and mark DONE.
(let* ((g (make-generator
           (lambda ()
             (perform yield 'from-thread-a)
             (error "fault-on-thread-b"))))
       (t1 (thread-start! (make-thread (lambda () (g)))))
       (v1 (thread-join! t1))
       (t2 (thread-start!
            (make-thread
             (lambda ()
               (with-exception-catcher
                (lambda (e) (list 'caught-on-b (error-exception-message e) (g)))
                (lambda () (g)))))))
       (v2 (thread-join! t2)))
  (test-equal 'from-thread-a v1)
  (test-equal (list 'caught-on-b "fault-on-thread-b" #!eof) v2)
  (test-equal #!eof (g)))

;; 11d. Non-tail one-shot resume under denv mismatch (with-exception-catcher +
;;      dynamic-wind) + nested perform + GC: verifies frozen non-tail replay
;;      pframe never corrupts caller-k's break-chain anchor.
(let ((outer-e (make-effect 'nontail-outer))
      (inner-e (make-effect 'nontail-inner)))
  (let loop ((i 0) (acc 0))
    (if (fx< i 80)
        (let ((r
               (with-handler
                 ((outer-e (k v)
                    ;; Non-tail resume inside a fresh dynamic-wind / catcher (denv mismatch!)
                    (let ((res
                           (with-exception-catcher
                            (lambda (e) -999)
                            (lambda ()
                              (dynamic-wind
                                (lambda () #!void)
                                (lambda () (resume k (fx+ v 1)))
                                (lambda () #!void))))))
                      (fx+ res 10))))
                 (with-handler
                   ((inner-e (k2 x)
                      (fx+ 100 (resume k2 (fx+ x 2)))))
                   (let* ((a (perform outer-e i))
                          (b (perform inner-e a)))
                     (if (fx= (fxand i 15) 15) (##gc))
                     b)))))
          (loop (fx+ i 1) (fx+ acc r)))
        (test-equal (fx+ (fxquotient (fx* 80 79) 2) (fx* 80 113)) acc))))

;; 11e. Adaptive-P SMP race directly pitting `resume` vs `resume-multishot` on
;;      the SAME `ONE_SHOT_LIVE` effect-continuation with nested handler prefix
;;      and concurrent GC: either strictly 1 one-shot winner + 0 promotes, OR
;;      promoted `MULTISHOT_COW` with every racer freezing idempotently before
;;      entering `%resume-checked` and producing exact results.
(let* ((num-threads (max 4 (min 12 (##current-vm-processor-count))))
       (rounds 40)
       (race-outer (make-effect 'race-outer-11e))
       (race-inner (make-effect 'race-inner-11e))
       (good-rounds (make-atomic-fxbox 0)))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let ((shared-ek #f)
              (resume-wins (make-atomic-fxbox 0))
              (promote-wins (make-atomic-fxbox 0))
              (bad-result (make-atomic-fxbox 0))
              (go (make-atomic-fxbox 0)))
          (with-handler
            ((race-outer (k seed)
               (set! shared-ek k)
               'captured))
            (with-handler
              ((race-inner (k2 v)
                 (resume k2 (fx+ v 5)))
               (return: (x) (fx* x 2)))
              (let* ((a (perform race-outer 0))
                     (b (perform race-inner a)))
                (fx+ b 1))))
          (let ((threads
                 (let tloop ((i 0) (acc '()))
                   (if (fx= i num-threads)
                       acc
                       (tloop (fx+ i 1)
                              (cons
                               (thread-start!
                                (make-thread
                                 (lambda ()
                                   (let spin ()
                                     (if (fx= (atomic-fxbox-ref go) 0)
                                         (begin (thread-yield!) (spin))))
                                   (let ((arg (fx+ r i))
                                         (exp (fx* (fx+ (fx+ (fx+ r i) 5) 1) 2)))
                                     (if (fx= (fxand i 1) 0)
                                         (with-exception-catcher
                                          (lambda (e) #f)
                                          (lambda ()
                                            (let ((res (resume shared-ek arg)))
                                              (if (fx= res exp)
                                                  (atomic-fxbox+/fetch! resume-wins 1)
                                                  (atomic-fxbox+/fetch! bad-result 1)))))
                                         (with-exception-catcher
                                          (lambda (e) #f)
                                          (lambda ()
                                            (let ((res (resume-multishot shared-ek arg)))
                                              (if (fx= res exp)
                                                  (atomic-fxbox+/fetch! promote-wins 1)
                                                  (atomic-fxbox+/fetch! bad-result 1))))))))))
                               acc))))))
            (atomic-fxbox-set! go 1)
            (for-each thread-join! threads)
            (if (fx= (fxand r 15) 15) (##gc))
            (let ((rw (atomic-fxbox-ref resume-wins))
                  (pw (atomic-fxbox-ref promote-wins))
                  (br (atomic-fxbox-ref bad-result)))
              (if (and (fx= br 0)
                       (or (and (fx= rw 1) (fx= pw 0))
                           (and (fx>= pw 1) (fx>= (fx+ rw pw) 2))))
                  (atomic-fxbox+/fetch! good-rounds 1)))
            (rloop (fx+ r 1)))))
  (test-equal rounds (atomic-fxbox-ref good-rounds))))

;; 11f. Adaptive-P SMP concurrent generator fault + nested handler throw torture
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (iters 60)
       (ok-count (make-atomic-fxbox 0)))
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let ((to (make-continuation-prompt-tag 'smp-eff-to))
                                (ef (make-effect 'smp-eff-f)))
                            (let iloop ((i 0) (good #t))
                              (if (fx< i iters)
                                  (let ((cnt 0))
                                    (let ((res
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (let ((g (make-generator
                                                        (lambda ()
                                                          (perform yield i)
                                                          (error "smp-gen-fault")))))
                                                (let* ((v1 (g))
                                                       (v2 (with-exception-catcher
                                                            (lambda (e) 'caught-g)
                                                            (lambda () (g))))
                                                       (v3 (g))
                                                       (v4 (with-exception-catcher
                                                            (lambda (e) 'caught-h)
                                                            (lambda ()
                                                              (with-handler ((ef (k x) (resume k x)))
                                                                (error "smp-h-fault"))))))
                                                  (set! cnt (fx+ cnt 1))
                                                  (and (fx= v1 i)
                                                       (eq? v2 'caught-g)
                                                       (eof-object? v3)
                                                       (eq? v4 'caught-h)))))
                                            to)))
                                      (if (and (fx= t 0) (fx= (fxand i 31) 31)) (##gc))
                                      (iloop (fx+ i 1) (and good res (fx= cnt 1)))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; 12. Transactional Post-dynamic-wind Perform & Generator Yield Safety
;;;     (Single-Thread Exactness + Adaptive-P SMP Torture)

;; 12a. Transactional `perform` across dynamic-wind: after-thunk sees intact
;;      inner handlers & marks; if after-thunk throws caught inside with-handler,
;;      the outer effect handler remains 100% live and uncorrupted.
(let ((outer-eff (make-effect 'dw-perf-outer))
      (inner-eff (make-effect 'dw-perf-inner))
      (after-saw #f))
  (let ((r1
         (with-handler ((outer-eff (k v) (list 'handled v)))
           (with-handler ((tail: inner-eff () 'inner-alive))
             (dynamic-wind
               (lambda () #!void)
               (lambda () (perform outer-eff 42))
               (lambda () (set! after-saw (perform inner-eff)))))))
        (r2
         (with-handler ((outer-eff (k v) (list 'still-live v)))
           (with-exception-catcher
            (lambda (e) (perform outer-eff 7))
            (lambda ()
              (dynamic-wind
                (lambda () #!void)
                (lambda () (perform outer-eff 99))
                (lambda () (error "perform-after-boom"))))))))
    (test-equal '(handled 42) r1)
    (test-equal 'inner-alive after-saw)
    (test-equal '(still-live 7) r2)))

;; 12b. Generator `yield` inside dynamic-wind whose after-thunk throws:
;;      exception delivers cleanly to caller's catcher, generator transitions
;;      atomically to DONE (#!eof), and enclosing prompts return once.
(let ((t-outer (make-continuation-prompt-tag 'gen-dw-after-outer))
      (after-count 0))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (let ((g (make-generator
                      (lambda ()
                        (dynamic-wind
                          (lambda () #!void)
                          (lambda () (perform yield 1))
                          (lambda () (error "gen-dw-after-boom")))))))
              (let ((c (with-exception-catcher
                        (lambda (e) (error-exception-message e))
                        (lambda () (g)))))
                (set! after-count (fx+ after-count 1))
                (list c (g)))))
          t-outer)))
    (test-equal (list "gen-dw-after-boom" #!eof) res)
    (test-equal 1 after-count)))

;; 12c. Adaptive-P SMP concurrent torture mixing transactional dynamic-wind
;;      perform & generator yield faults with concurrent GC.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (iters 60)
       (ok-count (make-atomic-fxbox 0)))
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let ((eo (make-effect 'smp-dw-eo))
                                (ei (make-effect 'smp-dw-ei)))
                            (let iloop ((i 0) (good #t))
                              (if (fx< i iters)
                                  (let ((saw #f))
                                    (let ((r1
                                           (with-handler ((eo (k v) (fx+ v 1)))
                                             (with-handler ((tail: ei () i))
                                               (dynamic-wind
                                                 (lambda () #!void)
                                                 (lambda () (perform eo i))
                                                 (lambda () (set! saw (perform ei)))))))
                                          (r2
                                           (with-handler ((eo (k v) (fx+ v 10)))
                                             (with-exception-catcher
                                              (lambda (e) (perform eo i))
                                              (lambda ()
                                                (dynamic-wind
                                                  (lambda () #!void)
                                                  (lambda () (perform eo 999))
                                                  (lambda () (error "smp-perf-dw")))))))
                                          (g (make-generator
                                              (lambda ()
                                                (dynamic-wind
                                                  (lambda () #!void)
                                                  (lambda () (perform yield i))
                                                  (lambda () (error "smp-gen-dw")))))))
                                      (let ((c (with-exception-catcher (lambda (e) 'ok) (lambda () (g)))))
                                        (if (and (fx= t 0) (fx= (fxand i 15) 15)) (##gc))
                                        (iloop (fx+ i 1)
                                               (and good
                                                    (fx= r1 (fx+ i 1))
                                                    (fx= saw i)
                                                    (fx= r2 (fx+ i 10))
                                                    (eq? c 'ok)
                                                    (eof-object? (g)))))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
