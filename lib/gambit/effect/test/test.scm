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

;; Public API argument validation: invalid effects, capabilities, and handlers
;; must raise clean Scheme errors rather than crashing under (not safe).
(let ((raises? (lambda (thunk)
                 (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f)))))
  (test-equal #t (raises? (lambda () (effect-name 123))))
  (test-equal #t (raises? (lambda () (perform 123))))
  (test-equal #t (raises? (lambda () (perform 'not-an-effect))))
  (test-equal #t (raises? (lambda () (perform-cap 123))))
  (test-equal #t (raises? (lambda () (call-with-tail-capability 123 (lambda (c) c)))))
  (test-equal #t (raises? (lambda () (call-with-tail-capability (lambda () 1) 123))))
  (test-equal #t (raises? (lambda () (call-with-suspend-capability 123 (lambda (c) c)))))
  (test-equal #t (raises? (lambda () (call-with-suspend-capability (lambda (k) k) 123))))
  (test-equal #t (raises? (lambda () (call-with-effect-handler 123 #f (lambda () 1)))))
  (test-equal #t (raises? (lambda () (call-with-effect-handler '() 123 (lambda () 1)))))
  (test-equal #t (raises? (lambda () (call-with-effect-handler '() #f 123))))
  (test-equal #t (raises? (lambda () (call-with-effect-handler '((123 456)) #f (lambda () 1))))))

;; Zero-leak consumed one-shot effect-continuation slot clearing across slow paths
;; (0-arg, multi-arg, and nested prompt/mark captures) while preserving multishot slots.
(let ((e0 (make-effect 'zero-leak-e0))
      (e-inner (make-effect 'zero-leak-inner))
      (saved-0 #f)
      (saved-2 #f)
      (saved-nested #f)
      (saved-multi #f))
  ;; 0-arg one-shot resume clears all 6 captured slots
  (test-equal 'ok-0
    (with-handler ((e0 (k) (set! saved-0 k) (resume k)))
      (call-with-values (lambda () (perform e0)) (lambda () 'ok-0))))
  (test-equal #f (##structure-ref saved-0 1 (##structure-type saved-0) #f))
  (test-equal #f (##structure-ref saved-0 2 (##structure-type saved-0) #f))
  (test-equal '() (##structure-ref saved-0 3 (##structure-type saved-0) #f))
  (test-equal '() (##structure-ref saved-0 4 (##structure-type saved-0) #f))
  (test-equal '() (##structure-ref saved-0 5 (##structure-type saved-0) #f))
  (test-equal #f (##structure-ref saved-0 6 (##structure-type saved-0) #f))
  ;; 2-arg one-shot resume clears all 6 captured slots
  (test-equal 30
    (with-handler ((e0 (k) (set! saved-2 k) (resume k 10 20)))
      (call-with-values (lambda () (perform e0)) (lambda (a b) (fx+ a b)))))
  (test-equal #f (##structure-ref saved-2 1 (##structure-type saved-2) #f))
  (test-equal #f (##structure-ref saved-2 6 (##structure-type saved-2) #f))
  ;; Nested-prompt + continuation-mark one-shot resume clears all 6 slots
  (test-equal '(42 mark-v)
    (with-handler ((e0 (k) (set! saved-nested k) (resume k 42)))
      (with-handler ((e-inner (k v) (resume k v)))
        (with-continuation-mark 'k 'mark-v
          (let ((x (perform e0)))
            (call-with-immediate-continuation-mark 'k (lambda (v) (list x v))))))))
  (test-equal #f (##structure-ref saved-nested 1 (##structure-type saved-nested) #f))
  (test-equal '() (##structure-ref saved-nested 3 (##structure-type saved-nested) #f))
  (test-equal '() (##structure-ref saved-nested 4 (##structure-type saved-nested) #f))
  (test-equal '() (##structure-ref saved-nested 5 (##structure-type saved-nested) #f))
  ;; Multishot promoted continuation preserves slots across multiple replays
  (test-equal '(10 20)
    (with-handler ((e0 (k)
                     (set! saved-multi k)
                     (list (resume-multishot k 10) (resume k 20))))
      (perform e0)))
  (test-assert (not (eq? #f (##structure-ref saved-multi 1 (##structure-type saved-multi) #f)))))

;; Generator caller metacontinuation/handler-chain detachment on yield and completion:
;; suspended generator detaches caller mc-cell/h-cell cdr between yields, and finished
;; generator clears all reusable cells.
(let ((g (make-generator
          (lambda ()
            (perform yield 'y1)
            (perform yield 'y2)
            (perform yield 'y3)))))
  (let ((gen (##closure-ref g 1)))
    (call-with-continuation-prompt
     (lambda ()
       (test-equal 'y1 (g))
       (test-equal 'y2 (g))
       ;; While suspended after Yield #2, caller mc-cell/h-cell cdr MUST be detached
       (test-equal '() (cdr (##structure-ref gen 5 (##structure-type gen) #f)))
       (test-equal '() (cdr (##structure-ref gen 6 (##structure-type gen) #f)))
       (test-equal 'y3 (g))
       (test-equal #!eof (g))))
    ;; After completion (DONE), all reusable cells on %generator MUST be cleared
    (test-equal #f (##structure-ref gen 2 (##structure-type gen) #f))
    (test-equal #f (##structure-ref gen 3 (##structure-type gen) #f))
    (test-equal #f (##structure-ref gen 5 (##structure-type gen) #f))
    (test-equal #f (##structure-ref gen 6 (##structure-type gen) #f))
    (test-equal #!eof (g))))

;;;============================================================================
;;; Transactional Effect Resume & Generator Resumption Across dynamic-wind & Barriers

;; Resuming an effect continuation across caller dynamic-wind must not pollute
;; the caller's after-thunk with the suspended body's marks or effect handlers.
(let ((inner-eff (make-effect 'dw-inner-eff))
      (outer-eff (make-effect 'dw-outer-eff))
      (log '()))
  (let ((res
         (with-handler ((outer-eff (k v)
                          (dynamic-wind
                            (lambda () #!void)
                            (lambda () (resume k v))
                            (lambda ()
                              (set! log
                                    (cons (list
                                           (continuation-mark-set->list
                                            (current-continuation-marks) 'ek)
                                           (with-exception-catcher
                                            (lambda (e) 'no-inner-handler)
                                            (lambda () (perform inner-eff 77))))
                                          log))))))
           (with-handler ((inner-eff (k v) (list 'zombie-inner-handler v)))
             (with-continuation-mark 'ek 'from-suspended-body
               (perform outer-eff 42))))))
    (test-equal 42 res)
    (test-equal '((() no-inner-handler) (() no-inner-handler)) (reverse log))))

;; Resuming an effect continuation across caller dynamic-wind whose after-thunk
;; throws rolls back cleanly without leaking suspended marks or handlers.
(let ((e1 (make-effect 'dw-throw-e1))
      (e2 (make-effect 'dw-throw-e2)))
  (let ((res
         (with-handler ((e1 (k v)
                          (with-exception-catcher
                           (lambda (e)
                             (list 'caught-after
                                   (continuation-mark-set->list
                                    (current-continuation-marks) 'ek)
                                   (with-exception-catcher
                                    (lambda (e) 'no-e2)
                                    (lambda () (perform e2 1)))))
                           (lambda ()
                             (dynamic-wind
                               (lambda () #!void)
                               (lambda () (resume k v))
                               (lambda () (error "resume-after-boom")))))))
           (with-handler ((e2 (k v) (list 'zombie-e2 v)))
             (with-continuation-mark 'ek 'suspended-mark
               (perform e1 10))))))
    (test-equal '(caught-after () no-e2) res)))

;; Continuation barrier remains strictly enforced across one-shot resume,
;; multi-shot resume, and generator resumption.
(let ((e-outer (make-effect 'bar-e-outer))
      (e-inner (make-effect 'bar-e-inner)))
  ;; One-shot resume inside barrier cannot suspend past barrier
  (test-equal 'barrier-enforced
    (with-handler ((e-outer (k v) 'barrier-bypassed))
      (with-handler ((e-inner (k v)
                       (call-with-continuation-barrier
                        (lambda ()
                          (with-exception-catcher
                           (lambda (e) 'barrier-enforced)
                           (lambda () (resume k v)))))))
        (perform e-inner 1)
        (perform e-outer 2))))

  ;; Multi-shot resume inside barrier cannot suspend past barrier on any replay
  (test-equal '(barrier-enforced barrier-enforced)
    (with-handler ((e-outer (k v) 'barrier-bypassed))
      (with-handler ((e-inner (k v)
                       (list
                        (call-with-continuation-barrier
                         (lambda ()
                           (with-exception-catcher
                            (lambda (e) 'barrier-enforced)
                            (lambda () (resume-multishot k v)))))
                        (call-with-continuation-barrier
                         (lambda ()
                           (with-exception-catcher
                            (lambda (e) 'barrier-enforced)
                            (lambda () (resume-multishot k v))))))))
        (perform e-inner 1)
        (perform e-outer 2))))

  ;; Generator resumed inside a barrier cannot suspend to an outer handler past the barrier
  (let ((g (make-generator
            (lambda ()
              (perform yield 'first)
              (perform e-outer 'try-escape)))))
    (test-equal 'first (g))
    (test-equal 'gen-barrier-enforced
      (with-handler ((e-outer (k v) 'gen-barrier-bypassed))
        (call-with-continuation-barrier
         (lambda ()
           (with-exception-catcher
            (lambda (e) 'gen-barrier-enforced)
            (lambda () (g)))))))))

;; Adaptive-P SMP torture: concurrent effect resume & generator resumption
;; across continuation barriers and dynamic-wind interleaved with GC.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 30)
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
                          (let ((eo (make-effect 'smp-eo))
                                (ei (make-effect 'smp-ei)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((after-clean #t))
                                    (let ((v1
                                           (with-handler ((eo (k v)
                                                            (dynamic-wind
                                                              (lambda () #!void)
                                                              (lambda () (resume k v))
                                                              (lambda ()
                                                                (with-exception-catcher
                                                                 (lambda (e) #!void)
                                                                 (lambda ()
                                                                   (perform ei 0)
                                                                   (set! after-clean #f)))))))
                                             (with-handler ((ei (k v) 'hijacked))
                                               (perform eo r))))
                                          (v2
                                           (with-handler ((eo (k v) 'bypassed))
                                             (with-handler ((ei (k v)
                                                              (call-with-continuation-barrier
                                                               (lambda ()
                                                                 (with-exception-catcher
                                                                  (lambda (e) 'blocked)
                                                                  (lambda () (resume k v)))))))
                                               (perform ei 1)
                                               (perform eo 2)))))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good after-clean (fx= v1 r) (eq? v2 'blocked)))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; Tail-Resumptive Handler Dynamic Frame Popping Across Continuation Replay

;; Exiting a tail-resumptive handler inside a resumed composable or effect
;; continuation (both normally, inside return clauses, and via exception unwind)
;; must dynamically pop only its own frame, preserving resumer-installed outer
;; handlers and never resurrecting dead capture-site handlers.
(let ((e-tail (make-effect 'dynpop-tail))
      (e-outer (make-effect 'dynpop-outer))
      (e-res-a (make-effect 'dynpop-res-a))
      (e-res-b (make-effect 'dynpop-res-b))
      (e-zombie (make-effect 'dynpop-zombie))
      (tag (make-continuation-prompt-tag 'dynpop-tag))
      (saved-k #f))
  ;; 1. Composable continuation captured inside tail handler under capture-site e-zombie
  (with-handler ((tail: e-zombie (x) (list 'zombie x)))
    (call-with-continuation-prompt
     (lambda ()
       (let ((a (with-handler ((tail: e-tail (x) (+ x 1))
                               (return: (v)
                                 (list v
                                       (with-exception-catcher
                                        (lambda (e) 'no-res-in-ret)
                                        (lambda () (perform e-res-a v))))))
                  (let ((v (call-with-composable-continuation
                            (lambda (k) (set! saved-k k) 0)
                            tag)))
                    (+ v (perform e-tail 10))))))
         (list a
               (with-exception-catcher (lambda (e) 'no-res-after) (lambda () (perform e-res-a 99)))
               (with-exception-catcher (lambda (e) 'no-zombie) (lambda () (perform e-zombie 77))))))
     tag))
  (test-equal '((16 (res-a 16)) (res-a 99) no-zombie)
    (with-handler ((tail: e-res-a (x) (list 'res-a x)))
      (saved-k 5)))

  ;; 2. Pure (gambit effect) multi-shot resume under distinct resumer handlers
  (test-equal '((16 (res-a 88)) (21 (res-b 88)))
    (with-handler ((e-outer (k v)
                     (list
                      (with-handler ((tail: e-res-a (x) (list 'res-a x)))
                        (resume-multishot k v))
                      (with-handler ((tail: e-res-b (x) (list 'res-b x)))
                        (resume-multishot k (+ v 5))))))
      (let ((a (with-handler ((tail: e-tail (x) (+ x 1)))
                 (+ (perform e-outer 5) (perform e-tail 10)))))
        (list a
              (with-exception-catcher
               (lambda (e)
                 (with-exception-catcher
                  (lambda (e2) 'neither)
                  (lambda () (perform e-res-b 88))))
               (lambda () (perform e-res-a 88)))))))

  ;; 3. Exception unwind out of tail-resumptive handler after resume preserves resumer handler
  (test-equal '(res-a 55)
    (with-handler ((e-outer (k v)
                     (with-handler ((tail: e-res-a (x) (list 'res-a x)))
                       (resume k v))))
      (with-exception-catcher
       (lambda (e) (perform e-res-a 55))
       (lambda ()
         (with-handler ((tail: e-tail (x) (+ x 1)))
           (perform e-outer 5)
           (error "tail-unwind-after-resume")))))))

;; Adaptive-P SMP torture: concurrent multi-shot tail-handler replay under
;; distinct resumer handlers + exception unwind + GC.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 30)
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
                          (let ((et (make-effect 'smp-dt))
                                (eo (make-effect 'smp-do))
                                (er (make-effect 'smp-dr))
                                (ez (make-effect 'smp-dz)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((res
                                         (with-handler ((eo (k v)
                                                          (with-handler ((tail: er (x) (fx+ x r)))
                                                            (resume k v))))
                                           (let ((a (with-handler ((tail: et (x) (fx+ x 1)))
                                                      (fx+ (perform eo 10) (perform et 5)))))
                                             (fx+ a (perform er 100)))))
                                        (res2
                                         (with-handler ((eo (k v)
                                                          (with-handler ((tail: er (x) (fx+ x 1)))
                                                            (resume k v))))
                                           (with-exception-catcher
                                            (lambda (e) (perform er r))
                                            (lambda ()
                                              (with-handler ((tail: et (x) x))
                                                (perform eo 0)
                                                (error "smp-tail-boom")))))))
                                    (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                    (rloop (fx+ r 1)
                                           (and good
                                                (fx= res (fx+ 116 r))
                                                (fx= res2 (fx+ r 1)))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; Generator Lifecycle Coherency Across Non-Local Control Escapes

;; Escaping a running generator via abort-current-continuation, raw/prompted
;; call/1cc, or an outer suspending effect must transition the generator
;; cleanly to DONE (#!eof on subsequent calls) rather than leaving it stuck in
;; RUNNING, while resuming an outer suspending effect restores RUNNING cleanly.
(let ((tag (make-continuation-prompt-tag 'gen-esc-tag))
      (outer-eff (make-effect 'gen-outer-eff)))
  ;; 1. abort-current-continuation escape -> clean #!eof + detached mc-cell/h-cell
  (let* ((g1 (make-generator
              (lambda ()
                (perform yield 'y1)
                (abort-current-continuation tag 'aborted-out))))
         (gen1 (##closure-ref g1 1)))
    (test-equal 'y1 (g1))
    (test-equal 'aborted-out
      (call-with-continuation-prompt (lambda () (g1)) tag (lambda (v) v)))
    (test-equal #!eof (g1))
    (test-equal '() (cdr (##structure-ref gen1 5 (##structure-type gen1) #f)))
    (test-equal '() (cdr (##structure-ref gen1 6 (##structure-type gen1) #f))))

  ;; 2. abort-current-continuation across throwing dynamic-wind after-thunk:
  ;;    rollback keeps generator alive and yielding subsequent values!
  (let ((g-rb (make-generator
               (lambda ()
                 (perform yield 'before-rb)
                 (with-exception-catcher
                  (lambda (e) 'rolled-back)
                  (lambda ()
                    (dynamic-wind
                      (lambda () #!void)
                      (lambda () (abort-current-continuation tag 'never))
                      (lambda () (error "gen-after-boom")))))
                 (perform yield 'after-rb)))))
    (test-equal 'before-rb (g-rb))
    (test-equal 'after-rb
      (call-with-continuation-prompt (lambda () (g-rb)) tag (lambda (v) 'wrong)))
    (test-equal #!eof (g-rb)))

  ;; 3. Raw call/1cc escape -> clean #!eof
  (let ((g-raw #f))
    (test-equal 'raw-escaped
      (call/1cc
       (lambda (k)
         (set! g-raw (make-generator
                      (lambda ()
                        (perform yield 'a)
                        (k 'raw-escaped))))
         (test-equal 'a (g-raw))
         (g-raw))))
    (test-equal #!eof (g-raw)))

  ;; 4. Prompted non-composable call/1cc escape -> clean #!eof
  (let ((g-nc #f))
    (test-equal 'nc-escaped
      (call-with-continuation-prompt
       (lambda ()
         (call/1cc
          (lambda (k)
            (set! g-nc (make-generator
                        (lambda ()
                          (perform yield 'b)
                          (k 'nc-escaped))))
            (test-equal 'b (g-nc))
            (g-nc))
          tag))
       tag))
    (test-equal #!eof (g-nc)))

  ;; 5. Outer suspending effect: abandoned (non-resuming) -> clean #!eof
  (let ((g-ab (make-generator
               (lambda ()
                 (perform yield 'first)
                 (perform outer-eff 'bye)))))
    (test-equal 'first (g-ab))
    (test-equal '(handled bye)
      (with-handler ((outer-eff (k v) (list 'handled v)))
        (g-ab)))
    (test-equal #!eof (g-ab)))

  ;; 6. Outer suspending effect: resumed -> restores RUNNING, yields next item, finishes to #!eof
  (let ((g-res (make-generator
                (lambda ()
                  (perform yield 'start)
                  (let ((x (perform outer-eff 10)))
                    (perform yield (+ x 5)))))))
    (test-equal 'start (g-res))
    (test-equal 25
      (with-handler ((outer-eff (k v)
                       ;; While suspended at outer-eff, calling (g-res) returns #!eof (not stuck!)
                       (test-equal #!eof (g-res))
                       (resume k (* v 2))))
        (g-res)))
    (test-equal #!eof (g-res))))

;; Adaptive-P SMP torture: concurrent generator non-local escapes (abort,
;; raw call/1cc, outer effect abandon & resume) interleaved with GC.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 30)
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
                          (let ((tg (make-continuation-prompt-tag 'smp-ge))
                                (eo (make-effect 'smp-ge-eff)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let* ((g1 (make-generator
                                              (lambda ()
                                                (perform yield r)
                                                (abort-current-continuation tg 'esc))))
                                         (v1a (g1))
                                         (v1b (call-with-continuation-prompt
                                               (lambda () (g1)) tg (lambda (v) v)))
                                         (v1c (g1))
                                         (g2 (make-generator
                                              (lambda ()
                                                (perform yield r)
                                                (perform yield (fx+ (perform eo r) 1)))))
                                         (v2a (g2))
                                         (v2b (with-handler ((eo (k v) (resume k (fx+ v 10))))
                                                (g2)))
                                         (v2c (g2)))
                                    (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                    (rloop (fx+ r 1)
                                           (and good
                                                (fx= v1a r) (eq? v1b 'esc) (eof-object? v1c)
                                                (fx= v2a r) (fx= v2b (fx+ r 11)) (eof-object? v2c))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; Out-of-scope tail-position return: clause execution & full 0/1/N multiple-value
;; return: dispatch for both suspending and tail-resumptive handlers.
(let ((e-ret (make-effect 'ret-scope))
      (e-ch  (make-effect 'ret-choose)))
  ;; Performing the same effect inside a suspending handler's return: clause
  ;; must dispatch to the enclosing outer handler (never hijacked by inner),
  ;; matching tail-resumptive handler semantics identically.
  (test-equal '(outer 40)
    (with-handler
      ((e-ret (k x) (list 'outer x)))
      (with-handler
        ((e-ret (k x) (resume k (fx+ x 1)))
         (return: (v) (perform e-ret (fx* v 10))))
        (perform e-ret 3))))
  (test-equal '(outer 40)
    (with-handler
      ((e-ret (k x) (list 'outer x)))
      (with-handler
        ((tail: e-ret (x) (fx+ x 1))
         (return: (v) (perform e-ret (fx* v 10))))
        (perform e-ret 3))))
  ;; Multi-shot resume-multishot runs return: once per branch outside inner handler
  (test-equal '(10 20)
    (with-handler
      ((e-ret (k x) (resume k (fx* x 10))))
      (with-handler
        ((e-ch (k) (append (resume-multishot k 1) (resume-multishot k 2)))
         (e-ret (k x) (resume k (fx+ x 999)))
         (return: (x) (list (perform e-ret x))))
        (perform e-ch))))
  ;; 0-value, 2-value, and 3-value return: clauses (both suspending and tail)
  (test-equal 'susp-zero
    (with-handler
      ((e-ret (k x) (resume k x))
       (return: () 'susp-zero))
      (perform e-ret 1)
      (values)))
  (test-equal 'tail-zero
    (with-handler
      ((tail: e-ret (x) x)
       (return: () 'tail-zero))
      (perform e-ret 1)
      (values)))
  (test-equal '(susp-2 11 22)
    (with-handler
      ((e-ret (k x) (resume k (fx+ x 1)))
       (return: (a b) (list 'susp-2 a b)))
      (values (perform e-ret 10) (perform e-ret 21))))
  (test-equal '(tail-2 11 22)
    (with-handler
      ((tail: e-ret (x) (fx+ x 1))
       (return: (a b) (list 'tail-2 a b)))
      (values (perform e-ret 10) (perform e-ret 21))))
  (test-equal 60
    (with-handler
      ((e-ret (k x) (resume k x))
       (return: (a b c) (fx+ a b c)))
      (values (perform e-ret 10) (perform e-ret 20) (perform e-ret 30))))
  ;; Exception raised inside return: observes clean outer stack (inner popped)
  (test-equal '(caught-ret-exc outer-alive)
    (with-handler
      ((tail: e-ret (x) 'outer-alive))
      (with-exception-catcher
       (lambda (ex) (list ex (perform e-ret 0)))
       (lambda ()
         (with-handler
           ((e-ret (k x) (resume k 'inner-zombie))
            (return: (v) (raise 'caught-ret-exc)))
           (perform e-ret 1))))))
  (test-equal '(caught-tail-ret-exc outer-alive)
    (with-handler
      ((tail: e-ret (x) 'outer-alive))
      (with-exception-catcher
       (lambda (ex) (list ex (perform e-ret 0)))
       (lambda ()
         (with-handler
           ((tail: e-ret (x) 'inner-zombie)
            (return: (v) (raise 'caught-tail-ret-exc)))
           (perform e-ret 1))))))
  ;; Adaptive-P SMP torture combining out-of-scope return: + multival + ##gc
  (let* ((hw (##current-vm-processor-count))
         (num-threads (max 2 (min 8 hw)))
         (rounds 30)
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
                            (let ((e1 (make-effect 'smp-ret1))
                                  (e2 (make-effect 'smp-ret2)))
                              (let rloop ((r 0) (good #t))
                                (if (fx< r rounds)
                                    (let ((r1
                                           (with-handler
                                             ((e1 (k x) (fx+ x 100)))
                                             (with-handler
                                               ((e1 (k x) (resume k (fx+ x 1)))
                                                (return: (a b) (perform e1 (fx+ a b))))
                                               (values (perform e1 r) (perform e1 1)))))
                                          (r2
                                           (with-handler
                                             ((tail: e2 (x) (fx* x 2)))
                                             (with-handler
                                               ((tail: e2 (x) (fx+ x 1))
                                                (return: (a b) (perform e2 (fx+ a b))))
                                               (values (perform e2 r) (perform e2 1))))))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good
                                                  (fx= r1 (fx+ r 103))
                                                  (fx= r2 (fx* (fx+ r 3) 2)))))
                                    (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal num-threads (atomic-fxbox-ref ok-count)))))

;;;============================================================================
;;; Generator Slow-Path Unwind-Hook Coherency, Multi-Value Yield, and
;;; Winding-Transition Fault Safety

(let ()
  ;; Slow-path yield (inside continuation mark) followed by exception transitions
  ;; the generator cleanly to DONE (#!eof) rather than wedging in RUNNING.
  (let ((g (make-generator
            (lambda ()
              (with-continuation-mark 'gen-mk 'v1
                (perform yield 10))
              (raise 'slow-gen-boom)))))
    (test-equal 10 (g))
    (test-equal 'slow-gen-boom
      (with-exception-catcher (lambda (e) e) (lambda () (g))))
    (test-equal #!eof (g))
    (test-equal #!eof (g)))

  ;; Slow-path yield followed by outer prompt abort transitions to DONE (#!eof).
  (let* ((pt (make-continuation-prompt-tag 'slow-gen-abort))
         (g (make-generator
             (lambda ()
               (with-continuation-mark 'gen-mk 'v1
                 (perform yield 11))
               (abort-current-continuation pt 'aborted-out)))))
    (test-equal 11 (g))
    (test-equal 'aborted-out
      (call-with-continuation-prompt (lambda () (g)) pt (lambda (x) x)))
    (test-equal #!eof (g)))

  ;; Slow-path yield followed by subsequent yield outside mark, then exception.
  (let ((g (make-generator
            (lambda ()
              (with-continuation-mark 'gen-mk 'v1
                (perform yield 21))
              (perform yield 22)
              (raise 'second-stage-boom)))))
    (test-equal 21 (g))
    (test-equal 22 (g))
    (test-equal 'second-stage-boom
      (with-exception-catcher (lambda (e) e) (lambda () (g))))
    (test-equal #!eof (g)))

  ;; Slow-path yield inside inner suspending handler, then outer effect abort.
  (let ((e-inner (make-effect 'slow-gen-inner))
        (e-outer (make-effect 'slow-gen-outer)))
    (let ((g (make-generator
              (lambda ()
                (with-handler ((e-inner (k v) (resume k (fx* v 10))))
                  (perform yield (perform e-inner 3))
                  (perform e-outer 99)
                  (perform yield 40))))))
      (test-equal 30 (g))
      (test-equal '(intercepted 99)
        (with-handler ((e-outer (k v) (list 'intercepted v)))
          (g)))
      (test-equal #!eof (g))))

  ;; Nested generators where inner yields via slow path then raises.
  (let* ((inner (make-generator
                 (lambda ()
                   (with-continuation-mark 'k 1 (perform yield 10))
                   (raise 'inner-slow-boom))))
         (outer (make-generator
                 (lambda ()
                   (perform yield (inner))
                   (perform yield (inner))))))
    (test-equal 10 (outer))
    (test-equal 'inner-slow-boom
      (with-exception-catcher (lambda (e) e) (lambda () (outer))))
    (test-equal #!eof (outer))
    (test-equal #!eof (inner)))

  ;; Multi-value and 0-value yields (0 / 1 / 2 / 3 values) stay live and finish cleanly.
  (let ((g (make-generator
            (lambda ()
              (perform yield)
              (perform yield 'single)
              (perform yield 'a 'b)
              (perform yield 10 20 30)))))
    (test-equal '() (call-with-values g list))
    (test-equal '(single) (call-with-values g list))
    (test-equal '(a b) (call-with-values g list))
    (test-equal '(10 20 30) (call-with-values g list))
    (test-equal #!eof (g)))

  ;; Generator dynamic-wind before-thunk raising on re-entry (both fast & slow paths)
  ;; is delivered to the caller's exception catcher and transitions generator to DONE.
  (let* ((n 0)
         (g (make-generator
             (lambda ()
               (dynamic-wind
                 (lambda ()
                   (set! n (fx+ n 1))
                   (if (fx= n 2) (raise 'fast-before-boom)))
                 (lambda ()
                   (perform yield 1)
                   (perform yield 2))
                 (lambda () #!void))))))
    (test-equal 1 (g))
    (test-equal 'fast-before-boom
      (with-exception-catcher (lambda (e) e) (lambda () (g))))
    (test-equal #!eof (g)))

  (let* ((n 0)
         (g (make-generator
             (lambda ()
               (dynamic-wind
                 (lambda ()
                   (set! n (fx+ n 1))
                   (if (fx= n 2) (raise 'slow-before-boom)))
                 (lambda ()
                   (with-continuation-mark 'k 1 (perform yield 1))
                   (perform yield 2))
                 (lambda () #!void))))))
    (test-equal 1 (g))
    (test-equal 'slow-before-boom
      (with-exception-catcher (lambda (e) e) (lambda () (g))))
    (test-equal #!eof (g)))

  ;; Trampolined caller dynamic-wind after-thunk raising during generator resume
  ;; leaves caller marks unpolluted and transitions generator cleanly to DONE.
  (let* ((pt (make-continuation-prompt-tag 'gen-tramp-after))
         (saw-marks #f)
         (g (make-generator
             (lambda ()
               (with-continuation-mark 'gen-only 'leak
                 (perform yield 1))
               (perform yield 2)))))
    (test-equal 1 (g))
    (test-equal 'tramp-after-boom
      (with-exception-catcher
       (lambda (e) e)
       (lambda ()
         (call-with-continuation-prompt
          (lambda ()
            (dynamic-wind
              (lambda () #!void)
              (lambda () (g))
              (lambda ()
                (set! saw-marks
                      (continuation-mark-set->list (current-continuation-marks) 'gen-only))
                (raise 'tramp-after-boom))))
          pt))))
    (test-equal '() saw-marks)
    (test-equal #!eof (g)))

  ;; Untramped bare caller dynamic-wind after-thunk raising inside an enclosing
  ;; prompt must NEVER leak a stale unwind-guard frame onto the metacontinuation.
  (let* ((pt (make-continuation-prompt-tag 'gen-untramp-after))
         (saw-marks #f)
         (g (make-generator
             (lambda ()
               (with-continuation-mark 'gen-only 'leak
                 (perform yield 1))
               (perform yield 2)))))
    (test-equal 1 (g))
    (test-equal 'untramp-after-boom
      (call-with-continuation-prompt
       (lambda ()
         (with-exception-catcher
          (lambda (e) e)
          (lambda ()
            (dynamic-wind
              (lambda () #!void)
              (lambda () (g))
              (lambda ()
                (set! saw-marks
                      (continuation-mark-set->list (current-continuation-marks) 'gen-only))
                (raise 'untramp-after-boom))))))
       pt))
    (test-equal '() saw-marks))

  ;; Cross-thread generator migration after slow-path yield and fault.
  (let ((g (make-generator
            (lambda ()
              (with-continuation-mark 'mk 'x (perform yield 101))
              (raise 'migrated-boom)))))
    (test-equal 101 (g))
    (let ((th (thread-start!
               (make-thread
                (lambda ()
                  (let ((c (with-exception-catcher (lambda (e) e) (lambda () (g)))))
                    (list c (g))))))))
      (test-equal (list 'migrated-boom #!eof) (thread-join! th))))

  ;; Adaptive-P SMP torture combining slow-path yields, 0/2/3-value yields,
  ;; outer aborts, and winding before-thunk faults with concurrent ##gc.
  (let* ((hw (##current-vm-processor-count))
         (num-threads (max 2 (min 8 hw)))
         (rounds 30)
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
                            (let ((pt (make-continuation-prompt-tag 'smp-gen-pt)))
                              (let rloop ((r 0) (good #t))
                                (if (fx< r rounds)
                                    (let* ((g1 (make-generator
                                                (lambda ()
                                                  (with-continuation-mark 'mk r
                                                    (perform yield r (fx+ r 1)))
                                                  (raise 'smp-slow-err))))
                                           (v1 (call-with-values g1 list))
                                           (e1 (with-exception-catcher (lambda (e) e) (lambda () (g1))))
                                           (d1 (g1))
                                           (g2 (make-generator
                                                (lambda ()
                                                  (with-continuation-mark 'mk r
                                                    (perform yield))
                                                  (abort-current-continuation pt 'smp-ab))))
                                           (v2 (call-with-values g2 list))
                                           (a2 (call-with-continuation-prompt
                                                (lambda () (g2)) pt (lambda (x) x)))
                                           (d2 (g2))
                                           (cnt 0)
                                           (g3 (make-generator
                                                (lambda ()
                                                  (dynamic-wind
                                                    (lambda ()
                                                      (set! cnt (fx+ cnt 1))
                                                      (if (fx= cnt 2) (raise 'smp-dw-err)))
                                                    (lambda () (perform yield r) (perform yield 0))
                                                    (lambda () #!void)))))
                                           (v3 (g3))
                                           (e3 (with-exception-catcher (lambda (e) e) (lambda () (g3))))
                                           (d3 (g3)))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good
                                                  (equal? v1 (list r (fx+ r 1)))
                                                  (eq? e1 'smp-slow-err)
                                                  (eof-object? d1)
                                                  (null? v2)
                                                  (eq? a2 'smp-ab)
                                                  (eof-object? d2)
                                                  (fx= v3 r)
                                                  (eq? e3 'smp-dw-err)
                                                  (eof-object? d3))))
                                    (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal num-threads (atomic-fxbox-ref ok-count)))))

;; 12d. Adaptive-P SMP ABBA deadlock regression: concurrent deep-stack
;;      cross-thread / cross-section continuation restore (lock_source_stack_frame:
;;      ALLOC_MEM_LOCK -> copy_gate) racing against variadic #!rest heap
;;      overflows traversing parked stack-section breaks (___rest_caller_chain).
(let* ((num-threads (max 4 (min 12 (##current-vm-processor-count))))
       (iters 80)
       (ok-count (make-atomic-fxbox 0))
       (eff-hop (make-effect 'smp-rest-hop))
       (var-sum (lambda (a b . rest)
                  (let loop ((xs rest) (acc (fx+ a b)))
                    (if (null? xs) acc (loop (cdr xs) (fx+ acc (car xs))))))))
  (define (deep-rest depth i)
    (if (fx= depth 0)
        (let ((v (make-vector 32 i)))
          (fx+ (vector-ref v 0) (var-sum 1 2 3 4 5 6 7 8)))
        (let ((a (fx+ depth 1))
              (b (fx+ depth 2))
              (c (fx+ depth 3))
              (d (fx+ depth 4)))
          (let ((r (deep-rest (fx- depth 1) i)))
            (fx+ r (fxand (fx+ a b c d) 3))))))
  (define (deep-cont depth i)
    (if (fx= depth 0)
        (fx+ (perform eff-hop i) (var-sum 1 2 3 4 5 6))
        (let ((a (fx+ depth 1))
              (b (fx+ depth 2))
              (c (fx+ depth 3))
              (d (fx+ depth 4)))
          (let ((r (deep-cont (fx- depth 1) i)))
            (fx+ r (fxand (fx+ a b c d) 1))))))
  (let* ((resumer-mbox (make-thread
                        (lambda ()
                          (let loop ()
                            (let ((msg (thread-receive)))
                              (if (pair? msg)
                                  (let ((k (car msg))
                                        (v (cadr msg))
                                        (reply-thr (cddr msg)))
                                    (thread-send reply-thr (resume k (fx+ v 1)))
                                    (loop))))))))
         (_ (thread-start! resumer-mbox))
         (threads
          (let loop ((t 0) (acc '()))
            (if (fx= t num-threads)
                acc
                (let ((tid t))
                  (loop (fx+ t 1)
                        (cons
                         (thread-start!
                          (make-thread
                           (lambda ()
                             (let ((self (current-thread)))
                               (let iloop ((i 0) (good #t))
                                 (if (fx< i iters)
                                     (let* ((r1 (deep-rest 240 i))
                                            (r2 (with-handler
                                                  ((eff-hop (k v)
                                                     (if (fx= (fxand i 3) 0)
                                                         (begin
                                                           (thread-send resumer-mbox (cons k (cons v self)))
                                                           (thread-receive))
                                                         (fx+ (resume k (fx+ v 1)) 0))))
                                                  (deep-cont 200 i))))
                                       (if (and (fx= tid 0) (fx= (fxand i 15) 15)) (##gc))
                                       (iloop (fx+ i 1)
                                              (and good
                                                   (fixnum? r1)
                                                   (fx>= r1 i)
                                                   (fixnum? r2)
                                                   (fx>= r2 (fx+ i 22)))))
                                     (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                         acc)))))))
    (for-each thread-join! threads)
    (thread-send resumer-mbox 'stop)
    (thread-join! resumer-mbox)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; 12e. SMP tgroup enumeration vs concurrent thread termination & subgroup creation:
;;      Regression for unlocked ##tgroup->thread-vector / ##tgroup->tgroup-vector /
;;      macro-make-tgroup racing against ##thread-end! self-looping deque nodes.
(let* ((rounds 25)
       (ok 0))
  (let rloop ((r 0))
    (when (fx< r rounds)
      (let* ((tg (make-thread-group (list 'smp-tg r) (thread-thread-group (current-thread))))
             (spawners
              (let loop ((i 0) (acc '()))
                (if (fx= i 24)
                    acc
                    (loop (fx+ i 1)
                          (cons (thread-start!
                                 (make-thread
                                  (lambda ()
                                    (if (fx= (fxand i 3) 0)
                                        (let ((sub (make-thread-group (list 'sub i) tg)))
                                          (thread-sleep! 0.05))
                                        (thread-sleep! 0.05)))
                                  (list 'tg-w i)
                                  tg))
                                acc))))))
        ;; Concurrently enumerate threads & subgroups while terminating siblings across cores
        (let ((enumerator
               (thread-start!
                (make-thread
                 (lambda ()
                   (let eloop ((k 0))
                     (when (fx< k 150)
                       (thread-group->thread-list tg)
                       (thread-group->thread-group-list tg)
                       (eloop (fx+ k 1)))))))))
          (for-each (lambda (t) (with-exception-catcher (lambda (_) #f) (lambda () (thread-terminate! t))))
                    spawners)
          (for-each (lambda (t) (with-exception-catcher (lambda (_) #f) (lambda () (thread-join! t))))
                    spawners)
          (thread-join! enumerator)
          (set! ok (fx+ ok 1))))
      (rloop (fx+ r 1))))
  (test-equal rounds ok))


;;;============================================================================
;;; Zero-Capture Tail-Resumptive Continuable-Exception Parity, Lexical Tail-
;;; Capability Scope Safety, and Raw call/1cc Cross-Prompt Restore Hooks

(let ()
  (define (raises-err? thunk)
    (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f)))

  ;; 1. Tail-resumptive with-handler preserves continuable exceptions (with-exception-handler),
  ;;    hiding the inner handler during outer eh execution and restoring it upon return.
  (let ((e (make-effect 'tail-cont-exc))
        (saw-in-outer #f))
    (test-equal 143
      (with-exception-handler
       (lambda (ex) (fx+ ex 100))
       (lambda ()
         (with-handler ((tail: e (v) v))
           (fx+ 1 (raise 42))))))
    (test-equal 240
      (with-handler ((tail: e (v) (list 'outer v)))
        (with-exception-handler
         (lambda (ex)
           (set! saw-in-outer (perform e ex))
           (fx+ ex 100))
         (lambda ()
           (with-handler ((tail: e (v) (fx* v 2)))
             (let ((r (raise 20)))
               (perform e r)))))))
    (test-equal '(outer 20) saw-in-outer)
    ;; Also inside an enclosing SRFI-226 prompt trampoline (zero-overhead path)
    (let ((pt (make-continuation-prompt-tag 'tail-tramp-cont)))
      (test-equal 240
        (with-exception-handler
         (lambda (ex) (fx+ ex 100))
         (lambda ()
           (call-with-continuation-prompt
            (lambda ()
              (with-handler ((tail: e (v) (fx* v 2)))
                (let ((r (raise 20)))
                  (perform e r))))
            pt))))
      ;; Escaping exception inside prompt leaves handler stack clean
      (test-equal 'caught-esc
        (with-exception-catcher
         (lambda (ex) ex)
         (lambda ()
           (call-with-continuation-prompt
            (lambda ()
              (with-handler ((tail: e (v) 'leaked))
                (raise 'caught-esc)))
            pt))))
      (test-equal #t (raises-err? (lambda () (perform e 1))))))

  ;; 2. Lexical tail-capability scope safety across normal exit, exceptions,
  ;;    continuable exceptions, non-local aborts, and multi-shot replay.
  (let ((escaped #f)
        (escaped-exc #f)
        (escaped-ab #f)
        (pt (make-continuation-prompt-tag 'cap-ab-pt))
        (e-out (make-effect 'cap-out-susp)))
    ;; Normal exit invalidates escaped tail capability
    (test-equal 15
      (call-with-tail-capability
       (lambda (x) (fx+ x 5))
       (lambda (cap)
         (set! escaped cap)
         (perform-cap cap 10))))
    (test-equal #t (raises-err? (lambda () (perform-cap escaped 10))))

    ;; Escaping exception invalidates escaped tail capability
    (test-equal 'cap-boom
      (with-exception-catcher
       (lambda (ex) ex)
       (lambda ()
         (call-with-tail-capability
          (lambda (x) x)
          (lambda (cap)
            (set! escaped-exc cap)
            (raise 'cap-boom))))))
    (test-equal #t (raises-err? (lambda () (perform-cap escaped-exc 1))))

    ;; Continuable exception disables cap during outer eh and re-enables on return
    (let ((outer-blocked #f))
      (test-equal 220
        (with-exception-handler
         (lambda (ex)
           (set! outer-blocked (raises-err? (lambda () (perform-cap (cdr ex) 1))))
           (fx+ (car ex) 100))
         (lambda ()
           (call-with-tail-capability
            (lambda (x) (fx* x 2))
            (lambda (cap)
              (let ((v (raise (cons 10 cap))))
                (perform-cap cap v)))))))
      (test-equal #t outer-blocked))

    ;; Non-local abort invalidates escaped tail capability
    (test-equal 'aborted-cap
      (call-with-continuation-prompt
       (lambda ()
         (call-with-tail-capability
          (lambda (x) x)
          (lambda (cap)
            (set! escaped-ab cap)
            (abort-current-continuation pt 'aborted-cap))))
       pt
       (lambda (v) v)))
    (test-equal #t (raises-err? (lambda () (perform-cap escaped-ab 1))))

    ;; Outer suspending perform disables cap during handler ('suspend) and
    ;; re-enables across multi-shot resume-multishot ('restore)!
    (let ((handler-blocked #f)
          (escaped-ms #f))
      (test-equal '(110 120)
        (with-handler ((e-out (k cap)
                         (set! handler-blocked (raises-err? (lambda () (perform-cap cap 1))))
                         (list (resume-multishot k 10)
                               (resume-multishot k 20))))
          (call-with-tail-capability
           (lambda (x) (fx+ x 100))
           (lambda (cap)
             (set! escaped-ms cap)
             (let ((v (perform e-out cap)))
               (perform-cap cap v))))))
      (test-equal #t handler-blocked)
      (test-equal #t (raises-err? (lambda () (perform-cap escaped-ms 1))))))

  ;; 3. Promoted raw call/1cc divergent jump restores re-entered tail-capability
  ;;    guard cleanly via exact LCA diff.
  (let ((absent (make-continuation-prompt-tag 'raw-cap-absent))
        (pt-a (make-continuation-prompt-tag 'raw-cap-a))
        (pt-b (make-continuation-prompt-tag 'raw-cap-b))
        (saved-k #f)
        (shot 0)
        (out '()))
    (call-with-continuation-prompt
     (lambda ()
       (call-with-tail-capability
        (lambda (x) (fx+ x 1000))
        (lambda (cap)
          (let ((v (call/1cc (lambda (k)
                               (promote-one-shot-continuation! k)
                               (set! saved-k k)
                               1)
                             absent)))
            (set! out (cons (perform-cap cap v) out))))))
     pt-a)
    (if (fx= shot 0)
        (begin
          (set! shot 1)
          (call-with-continuation-prompt
           (lambda () (saved-k 2))
           pt-b)))
    (test-equal '(1002 1001) out))

  ;; 4. Adaptive-P SMP torture combining tail-resumptive continuable exceptions,
  ;;    lexical tail-capability scope checks across aborts & multi-shot replay + ##gc.
  (let* ((hw (##current-vm-processor-count))
         (num-threads (max 2 (min 8 hw)))
         (rounds 30)
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
                            (let ((e1 (make-effect 'smp-c-e1))
                                  (e2 (make-effect 'smp-c-e2)))
                              (let rloop ((r 0) (good #t))
                                (if (fx< r rounds)
                                    (let* ((r1 (with-exception-handler
                                                (lambda (ex) (fx+ ex 10))
                                                (lambda ()
                                                  (with-handler ((tail: e1 (x) (fx* x 2)))
                                                    (perform e1 (raise r))))))
                                           (esc #f)
                                           (r2 (with-handler ((e2 (k cap)
                                                                (list (resume-multishot k r)
                                                                      (resume-multishot k (fx+ r 1)))))
                                                 (call-with-tail-capability
                                                  (lambda (x) (fx+ x 5))
                                                  (lambda (cap)
                                                    (set! esc cap)
                                                    (perform-cap cap (perform e2 cap))))))
                                           (dead? (raises-err? (lambda () (perform-cap esc 0)))))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good
                                                  (fx= r1 (fx* (fx+ r 10) 2))
                                                  (equal? r2 (list (fx+ r 5) (fx+ r 6)))
                                                  dead?)))
                                    (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal num-threads (atomic-fxbox-ref ok-count))))

  ;; 7. Tail capability inside prompt + non-trampoline with-exception-catcher or
  ;;    with-exception-handler MUST pop its unwind-guard before delegating to the
  ;;    catcher (zero stale guard leak on prompt return) and restore it on
  ;;    continuable return.
  (let ((leaked-cap #f)
        (mid-dead #f)
        (pt (make-continuation-prompt-tag 'cap-catcher-pt)))
    (test-equal 'caught-cap
      (call-with-continuation-prompt
       (lambda ()
         (with-exception-catcher
          (lambda (e) e)
          (lambda ()
            (call-with-tail-capability
             (lambda (x) (fx+ x 1))
             (lambda (cap)
               (set! leaked-cap cap)
               (raise 'caught-cap))))))
       pt))
    (test-equal #t (raises-err? (lambda () (perform-cap leaked-cap 1))))

    ;; With return: clause inside suspending with-handler as well
    (let ((e-ret (make-effect 'cap-ret-eff)))
      (test-equal '(wrapped caught-ret)
        (with-handler ((e-ret (k) (resume k #f))
                       (return: (v) (list 'wrapped v)))
          (with-exception-catcher
           (lambda (e) e)
           (lambda ()
             (call-with-tail-capability
              (lambda (x) x)
              (lambda (cap) (raise 'caught-ret))))))))

    ;; Continuable exception inside prompt + inner with-exception-handler restores
    ;; guard-frame so a subsequent abort still deactivates the capability!
    (let ((c2 #f))
      (test-equal 'aborted-after-cont
        (call-with-continuation-prompt
         (lambda ()
           (with-exception-handler
            (lambda (e)
              (set! mid-dead (raises-err? (lambda () (perform-cap c2 0))))
              (fx+ e 10))
            (lambda ()
              (call-with-tail-capability
               (lambda (x) (fx* x 2))
               (lambda (cap)
                 (set! c2 cap)
                 (let ((v (perform-cap cap (raise 5))))
                   (test-equal 30 v)
                   (abort-current-continuation pt 'aborted-after-cont)))))))
         pt
         (lambda (v) v)))
      (test-equal #t mid-dead)
      (test-equal #t (raises-err? (lambda () (perform-cap c2 0)))))))

;;;============================================================================
;;; Tail-Resumptive Deep-Handler Delegation, Dynamic Scope Isolation &
;;; Cross-Extent Suspend/Resume Splicing

(let ()
  (define ask (make-effect 'tail-del-ask))
  (define e1 (make-effect 'tail-del-e1))
  (define e2 (make-effect 'tail-del-e2))
  (define e3 (make-effect 'tail-del-e3))

  ;; 1. Tail-resumptive handler delegating same effect to outer handler (zero self-recursion!)
  (test-equal 11
    (with-handler ((tail: ask () 10))
      (with-handler ((tail: ask () (fx+ 1 (perform ask))))
        (perform ask))))

  ;; 3-level tail delegation chain
  (test-equal 111
    (with-handler ((tail: ask () 100))
      (with-handler ((tail: ask () (fx+ 10 (perform ask))))
        (with-handler ((tail: ask () (fx+ 1 (perform ask))))
          (perform ask)))))

  ;; 2. Outer tail handler dynamic scope isolation: inner e2 handler MUST NOT hijack
  ;;    outer tail e1 handler when e1 performs e2!
  (test-equal '(outer-e2 inner-e2)
    (with-handler ((tail: e2 () 'outer-e2))
      (with-handler ((tail: e1 () (perform e2)))
        (with-handler ((tail: e2 () 'inner-e2))
          (list (perform e1) (perform e2))))))

  ;; 3. Mixed handler block (tail: e1 + suspend e2): tail e1 delegates cleanly to outer e1!
  (test-equal 21
    (with-handler ((tail: e1 () 20))
      (with-handler ((tail: e1 () (fx+ 1 (perform e1)))
                     (e2 (k) (resume k 0)))
        (perform e1))))

  ;; 4. Outer tail handler performing a SUSPENDING outer effect resumed in a DIFFERENT
  ;;    dynamic extent with an extra resumer handler e3: preserves BOTH inner e2 AND e3!
  (let ((saved-k #f))
    (test-equal '(from-outer-e2 from-inner-e2 from-resumer-e3)
      (let ((first
             (with-handler ((e2 (k) (set! saved-k k) 'suspended))
               (with-handler ((tail: e1 () (perform e2)))
                 (with-handler ((tail: e2 () 'from-inner-e2))
                   (let ((a (perform e1))
                         (b (perform e2))
                         (c (perform e3)))
                     (list a b c)))))))
        (test-equal 'suspended first)
        (with-handler ((tail: e3 () 'from-resumer-e3))
          (resume saved-k 'from-outer-e2)))))

  ;; 5. Tail handler delegation + continuable exception preserves outer scope & value!
  (test-equal 106
    (with-exception-handler
     (lambda (e) (fx+ e 100))
     (lambda ()
       (with-handler ((tail: ask () (raise 5)))
         (with-handler ((tail: ask () (fx+ 1 (perform ask))))
           (perform ask))))))

  ;; 6. Tail handler raising an escaping exception caught by an INNER catcher
  ;;    preserves the outer tail handler while popping inner handlers!
  (test-equal '(boom outer-ok from-e2-still-live)
    (let ((flag #f))
      (with-handler ((tail: e1 () 'outer-ok))
        (with-handler ((tail: e2 ()
                         (if flag 'from-e2-still-live (raise 'boom))))
          (with-exception-catcher
           (lambda (e)
             (set! flag #t)
             (list e (perform e1) (perform e2)))
           (lambda ()
             (with-handler ((tail: e1 () 'inner-bad))
               (perform e2))))))))

  ;; 7. Adaptive-P SMP torture: concurrent delegated tail handlers + suspending
  ;;    outer resume + continuable exceptions with ##gc.
  (let* ((num-threads (max 2 (min 8 (##current-vm-processor-count))))
         (rounds 30)
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
                            (let ((ea (make-effect 'smp-td-a))
                                  (eb (make-effect 'smp-td-b)))
                              (let rloop ((r 0) (good #t))
                                (if (fx< r rounds)
                                    (let* ((r1 (with-handler ((tail: ea (x) (fx+ x 10)))
                                                 (with-handler ((tail: ea (x) (fx+ 1 (perform ea x))))
                                                   (perform ea r))))
                                           (r2 (with-handler ((eb (k) (resume k 'outer)))
                                                 (with-handler ((tail: ea () (perform eb)))
                                                   (with-handler ((tail: eb () 'inner))
                                                     (list (perform ea) (perform eb))))))
                                           (r3 (with-exception-handler
                                                (lambda (ex) (fx+ ex 100))
                                                (lambda ()
                                                  (with-handler ((tail: ea () (raise r)))
                                                    (with-handler ((tail: ea () (fx+ 1 (perform ea))))
                                                      (perform ea)))))))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good
                                                  (fx= r1 (fx+ r 11))
                                                  (equal? r2 '(outer inner))
                                                  (fx= r3 (fx+ r 101)))))
                                    (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal num-threads (atomic-fxbox-ref ok-count)))))

;;;============================================================================
;;; Lexical Tail-Capability Creation-Site Dynamic Scope Isolation,
;;; Cross-Extent Splicing & Exception/Continuable Coherency

(let ()
  (define e2 (make-effect 'tail-cap-iso-e2))
  (define e3 (make-effect 'tail-cap-iso-e3))
  (define (raises-unhandled? thunk)
    (with-exception-catcher (lambda (_) #t) (lambda () (thunk) #f)))

  ;; 1. Outer tail capability MUST execute in its creation-site handler stack,
  ;;    never hijacked by an inner with-handler for the same effect.
  (test-equal '(outer-e2 inner-e2)
    (with-handler ((tail: e2 () 'outer-e2))
      (call-with-tail-capability
       (lambda () (perform e2))
       (lambda (cap)
         (with-handler ((tail: e2 () 'inner-e2))
           (list (perform-cap cap) (perform e2)))))))

  ;; 2. Top-level tail capability (empty creation-site handler stack) MUST NOT
  ;;    be hijacked by an inner handler installed inside its body.
  (test-equal #t
    (call-with-tail-capability
     (lambda () (perform e2))
     (lambda (cap)
       (with-handler ((tail: e2 () 'inner-e2))
         (raises-unhandled? (lambda () (perform-cap cap)))))))

  ;; 3. Tail capability performing an outer SUSPENDING effect resumed under an
  ;;    extra resumer handler preserves BOTH the inner handler AND resumer handler.
  (let ((saved-k #f))
    (test-equal '(from-outer-e2 from-inner-e2 from-resumer-e3)
      (let ((first
             (with-handler ((e2 (k) (set! saved-k k) 'suspended))
               (call-with-tail-capability
                (lambda () (perform e2))
                (lambda (cap)
                  (with-handler ((tail: e2 () 'from-inner-e2))
                    (let ((a (perform-cap cap))
                          (b (perform e2))
                          (c (perform e3)))
                      (list a b c))))))))
        (test-equal 'suspended first)
        (with-handler ((tail: e3 () 'from-resumer-e3))
          (resume saved-k 'from-outer-e2)))))

  ;; 4. Tail capability whose own body was suspended and resumed under an extra
  ;;    resumer handler sees the resumer handler while staying isolated from
  ;;    inner handlers installed after resume.
  (let ((e-susp (make-effect 'tail-cap-iso-susp))
        (saved-k #f))
    (test-equal '((outer-e2 from-resumer-e3) inner-e2)
      (let ((first
             (with-handler ((e-susp (k) (set! saved-k k) 'suspended))
               (with-handler ((tail: e2 () 'outer-e2))
                 (call-with-tail-capability
                  (lambda () (list (perform e2) (perform e3)))
                  (lambda (cap)
                    (let ((_ (perform e-susp)))
                      (with-handler ((tail: e2 () 'inner-e2))
                        (list (perform-cap cap) (perform e2))))))))))
        (test-equal 'suspended first)
        (with-handler ((tail: e3 () 'from-resumer-e3))
          (resume saved-k 'go)))))

  ;; 5. Escaping exception raised inside isolated tail-cap caught by an inner
  ;;    catcher pops the inner handler while keeping the capability live and
  ;;    outer handler intact.
  (test-equal '(cap-boom outer-e2 cap-still-live)
    (let ((flag #f))
      (with-handler ((tail: e2 () 'outer-e2))
        (call-with-tail-capability
         (lambda () (if flag 'cap-still-live (raise 'cap-boom)))
         (lambda (cap)
           (with-exception-catcher
            (lambda (ex)
              (set! flag #t)
              (list ex (perform e2) (perform-cap cap)))
            (lambda ()
              (with-handler ((tail: e2 () 'inner-bad))
                (perform-cap cap)))))))))

  ;; 6. Continuable exception raised inside isolated tail-cap preserves creation-site
  ;;    scope after recovery AND restores inner handler on return.
  (test-equal '((105 outer-e2) inner-e2)
    (with-exception-handler
     (lambda (ex) (fx+ ex 100))
     (lambda ()
       (with-handler ((tail: e2 () 'outer-e2))
         (call-with-tail-capability
          (lambda ()
            (let ((v (raise 5)))
              (list v (perform e2))))
          (lambda (cap)
            (with-handler ((tail: e2 () 'inner-e2))
              (list (perform-cap cap) (perform e2)))))))))

  ;; 7. Multiple values returned through isolated tail-cap are preserved intact.
  (test-equal '((outer-e2 10 20) inner-e2)
    (with-handler ((tail: e2 () 'outer-e2))
      (call-with-tail-capability
       (lambda (x y) (values (perform e2) x y))
       (lambda (cap)
         (with-handler ((tail: e2 () 'inner-e2))
           (let ((mv (call-with-values (lambda () (perform-cap cap 10 20)) list)))
             (list mv (perform e2))))))))

  ;; 8. Adaptive-P SMP torture: concurrent isolated tail-capabilities with
  ;;    cross-extent resume, continuable exceptions, and ##gc.
  (let* ((num-threads (max 2 (min 8 (##current-vm-processor-count))))
         (rounds 30)
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
                            (let ((ea (make-effect 'smp-tc-a))
                                  (eb (make-effect 'smp-tc-b)))
                              (let rloop ((r 0) (good #t))
                                (if (fx< r rounds)
                                    (let* ((r1 (with-handler ((tail: ea () 'outer))
                                                 (call-with-tail-capability
                                                  (lambda () (perform ea))
                                                  (lambda (cap)
                                                    (with-handler ((tail: ea () 'inner))
                                                      (list (perform-cap cap) (perform ea)))))))
                                           (r2 (with-handler ((ea (k) (resume k (fx+ r 10))))
                                                 (call-with-tail-capability
                                                  (lambda () (perform ea))
                                                  (lambda (cap)
                                                    (with-handler ((tail: ea () 'inner))
                                                      (list (perform-cap cap) (perform ea)))))))
                                           (r3 (with-exception-handler
                                                (lambda (ex) (fx+ ex 100))
                                                (lambda ()
                                                  (with-handler ((tail: eb () 'outer-b))
                                                    (call-with-tail-capability
                                                     (lambda () (list (raise r) (perform eb)))
                                                     (lambda (cap)
                                                       (with-handler ((tail: eb () 'inner-b))
                                                         (list (perform-cap cap) (perform eb))))))))))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good
                                                  (equal? r1 '(outer inner))
                                                  (equal? r2 (list (fx+ r 10) 'inner))
                                                  (equal? r3 (list (list (fx+ r 100) 'outer-b) 'inner-b)))))
                                    (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                        acc))))))
      (for-each thread-join! threads)
      (test-equal num-threads (atomic-fxbox-ref ok-count)))))

;;;============================================================================
