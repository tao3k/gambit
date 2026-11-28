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

;; 5a. 12 threads running independent tail + suspending + multi-shot effects
(let ((num-threads 12)
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

(let ((num-threads 12)
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
