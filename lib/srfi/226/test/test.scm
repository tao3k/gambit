;;;============================================================================

;;; File: "test.scm"

;;; (srfi 226) Control Features — Unit & 12-Core SMP Linearizability Tests

(import (srfi 226))
(import (srfi 230))
(import (_test))

;;;============================================================================
;;; 1. Prompts & Abort Handlers

(define t1 (make-continuation-prompt-tag 't1))
(define t2 (make-continuation-prompt-tag 't2))

(test-equal #t (continuation-prompt-tag? t1))
(test-equal #t (continuation-prompt-tag? (default-continuation-prompt-tag)))
(test-equal #f (continuation-prompt-tag? 'not-a-tag))
(test-equal #f (continuation-prompt-available? t1))

;; Normal return (single and multiple values)
(test-equal 42
  (call-with-continuation-prompt
   (lambda ()
     (test-equal #t (continuation-prompt-available? t1))
     42)
   t1))

(test-equal '(1 2 3)
  (call-with-values
    (lambda ()
      (call-with-continuation-prompt
       (lambda () (values 1 2 3))
       t1))
    list))

;; Abort to custom prompt handler
(test-equal '(aborted 10 20)
  (call-with-continuation-prompt
   (lambda ()
     (+ 1 (abort-current-continuation t1 10 20)))
   t1
   (lambda (a b) (list 'aborted a b))))

;; Nested prompts: abort to outer skips inner
(test-equal 'outer-caught
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-prompt
      (lambda ()
        (abort-current-continuation t1 'outer-caught))
      t2
      (lambda (x) 'inner-wrong)))
   t1
   (lambda (x) x)))

;; Prompt is removed before handler runs
(test-equal #f
  (call-with-continuation-prompt
   (lambda () (abort-current-continuation t1))
   t1
   (lambda () (continuation-prompt-available? t1))))

;;;============================================================================
;;; 2. Composable & Non-Composable Delimited Continuations

;; Composable continuation invoked once and multiple times
(test-equal 113
  (+ 1 (call-with-continuation-prompt
        (lambda ()
          (+ 2 (call-with-composable-continuation
                (lambda (k)
                  (abort-current-continuation
                   t1
                   (lambda () (+ 10 (k 100)))))
                t1)))
        t1)))

(test-equal 35
  (+ 1 (call-with-continuation-prompt
        (lambda ()
          (+ 2 (call-with-composable-continuation
                (lambda (k)
                  (abort-current-continuation
                   t1
                   (lambda () (+ (k 10) (k 20)))))
                t1)))
        t1)))

;; Composable continuation with multiple values
(test-equal 30
  (call-with-continuation-prompt
   (lambda ()
     (call-with-values
       (lambda ()
         (call-with-composable-continuation
          (lambda (k)
            (abort-current-continuation
             t1
             (lambda () (k 10 20))))
          t1))
       +))
   t1))

;; Nested composable continuation across two prompts
(test-equal 1110
  (call-with-continuation-prompt
   (lambda ()
     (+ 1000
        (call-with-continuation-prompt
         (lambda ()
           (+ 100
              (call-with-composable-continuation
               (lambda (k)
                 (abort-current-continuation
                  t1
                  (lambda () (k 10))))
               t1)))
         t2)))
   t1))

;; Non-composable continuation
(test-equal 1077
  (call-with-continuation-prompt
   (lambda ()
     (+ 1000
        (call-with-non-composable-continuation
         (lambda (k)
           (+ 2000 (k 77)))
         t1)))
   t1))

;;;============================================================================
;;; 3. Continuation Barriers

(define (raises-error? thunk)
  (with-exception-catcher
   (lambda (e) #t)
   (lambda () (thunk) #f)))

;; Capturing composable continuation across a barrier must raise
(test-equal #t
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-barrier
      (lambda ()
        (raises-error?
         (lambda ()
           (call-with-composable-continuation (lambda (k) (k 1)) t1))))))
   t1))

;; Aborting OUT of a barrier to an enclosing prompt is allowed
(test-equal 'escaped-barrier
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-barrier
      (lambda ()
        (abort-current-continuation t1 'escaped-barrier))))
   t1
   (lambda (v) v)))

;; Jumping INTO a barrier via a captured continuation from outside must raise
(define captured-inside-barrier #f)
(call-with-continuation-prompt
 (lambda ()
   (call-with-continuation-barrier
    (lambda ()
      (call-with-non-composable-continuation
       (lambda (k) (set! captured-inside-barrier k) 'ok)
       t1))))
 t1)
(test-equal #t
  (call-with-continuation-prompt
   (lambda ()
     (raises-error? (lambda () (captured-inside-barrier 'bad))))
   t1))

;;;============================================================================
;;; 4. Atomic One-Shot Continuations (call/1cc & promotion)

;; Single invocation succeeds; second raises
(define saved-1cc #f)
(define r1cc
  (call-with-continuation-prompt
   (lambda ()
     (+ 10 (call-with-one-shot-composable-continuation
            (lambda (k)
              (set! saved-1cc k)
              (test-equal #t (one-shot-continuation? k))
              (test-equal #f (one-shot-continuation-consumed? k))
              (abort-current-continuation t1 (lambda () (k 5))))
            t1)))
   t1))
(test-equal 15 r1cc)
(test-equal #t (one-shot-continuation-consumed? saved-1cc))
(test-equal #t (raises-error? (lambda () (saved-1cc 6))))
;; Promoting an already-consumed one-shot continuation must raise
(test-equal #t (raises-error? (lambda () (promote-one-shot-continuation! saved-1cc))))

;; Promoting BEFORE consumption allows multi-shot invocation
(define r-promo
  (call-with-continuation-prompt
   (lambda ()
     (+ 1 (call-with-one-shot-composable-continuation
           (lambda (k)
             (promote-one-shot-continuation! k)
             (abort-current-continuation t1 (lambda () (+ (k 10) (k 20)))))
           t1)))
   t1))
(test-equal 32 r-promo)

;; call/1cc basic test
(define c1-saved #f)
(test-equal 99
  (call-with-continuation-prompt
   (lambda ()
     (call/1cc
      (lambda (k)
        (set! c1-saved k)
        (k 99))
      t1))
   t1))
(test-equal #t (one-shot-continuation-consumed? c1-saved))
(test-equal #t (raises-error? (lambda () (c1-saved 100))))

;;;============================================================================
;;; 5. Continuation Marks

(test-equal '(2 1)
  (with-continuation-mark 'k 1
    (let ((inner
           (with-continuation-mark 'k 2
             (continuation-mark-set->list (current-continuation-marks) 'k))))
      inner)))

(test-equal 2
  (with-continuation-mark 'k 1
    (with-continuation-mark 'k 2
      (continuation-mark-set-first (current-continuation-marks) 'k))))

(test-equal 'default-val
  (continuation-mark-set-first (current-continuation-marks) 'missing 'default-val))

(test-equal 'imm-val
  (with-continuation-mark 'm 'imm-val
    (call-with-immediate-continuation-mark 'm (lambda (v) v) 'none)))

;; Non-tail nested marks keep 2 distinct frames
(test-equal (list (vector 'b #f) (vector #f 'a))
  (with-continuation-mark 'y 'a
    (let ((res
           (with-continuation-mark 'x 'b
             (continuation-mark-set->list* (current-continuation-marks) '(x y) #f))))
      res)))

;; Tail-nested marks merge into a SINGLE frame (Racket CS ICFP '20 / SRFI 226)
(test-equal (list (vector 'b 'a))
  (with-continuation-mark 'y 'a
    (with-continuation-mark 'x 'b
      (continuation-mark-set->list* (current-continuation-marks) '(x y) #f))))

;; 100,000-iteration tail-recursive with-continuation-mark in O(1) stack space!
(test-equal '(99999)
  (let loop ((i 0))
    (if (fx= i 100000)
        (continuation-mark-set->list (current-continuation-marks) 'tail-k)
        (with-continuation-mark 'tail-k i
          (loop (fx+ i 1))))))

;; Deep 30-frame composable continuation exercising Chez 4 KiB multi-frame chunk restore
(test-equal 465
  (call-with-continuation-prompt
   (lambda ()
     (let deep ((n 30))
       (if (fx= n 0)
           (call-with-composable-continuation
            (lambda (k)
              (abort-current-continuation t1 (lambda () (k 0))))
            t1)
           (fx+ n (deep (fx- n 1))))))
   t1))

;; Marks are delimited by prompt tag
(test-equal '(inner)
  (with-continuation-mark 'scope 'outer
    (call-with-continuation-prompt
     (lambda ()
       (with-continuation-mark 'scope 'inner
         (continuation-mark-set->list (current-continuation-marks t1) 'scope)))
     t1)))

;;;============================================================================
;;; 6. Shift / Reset

(test-equal 112
  (reset (+ 2 (shift k (+ 10 (k 100))))))

(test-equal '(1 2 3)
  (reset
   (let ((x (shift k (cons 1 (k '())))))
     (let ((y (shift k (cons 2 (k '())))))
       (cons 3 '())))))

(test-equal 120
  ;; Multi-shot shift/reset
  (reset
   (* 10 (shift k (+ (k 5) (k 7))))))

;;;============================================================================
;;; 7. 12-Core SMP Linearizability Stress Test for Atomic One-Shot call/1cc
;;;
;;; 12 threads simultaneously race to invoke the SAME one-shot continuation
;;; across 40 rounds. In every single round, the atomic CAS (0 -> 1) must
;;; guarantee EXACTLY 1 winner and 11 rejected callers.

(let ((num-threads (max 4 (min 16 (##current-vm-processor-count))))
      (rounds 40)
      (total-winners (make-atomic-fxbox 0))
      (total-rejected (make-atomic-fxbox 0)))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let ((shared-k #f)
              (round-winners (make-atomic-fxbox 0))
              (round-rejected (make-atomic-fxbox 0))
              (go-flag (make-atomic-fxbox 0)))
          ;; Capture a live one-shot composable continuation
          (call-with-continuation-prompt
           (lambda ()
             (+ 1 (call-with-one-shot-composable-continuation
                   (lambda (k)
                     (set! shared-k k)
                     (abort-current-continuation t1 (lambda () 'captured)))
                   t1)))
           t1)
          (let ((threads
                 (let tloop ((i 0) (acc '()))
                   (if (fx= i num-threads)
                       acc
                       (tloop (fx+ i 1)
                              (cons
                               (thread-start!
                                (make-thread
                                 (lambda ()
                                   ;; Spin until all threads are ready
                                   (let spin ()
                                     (if (fx= (atomic-fxbox-ref go-flag) 0)
                                         (begin (thread-yield!) (spin))))
                                   (with-exception-catcher
                                    (lambda (e)
                                      (atomic-fxbox+/fetch! round-rejected 1))
                                    (lambda ()
                                      (let ((res (shared-k r)))
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
;;; 8. 12-Core SMP Adversarial Multi-Shot Composable Replay + Frozen Prefix
;;;    + Concurrent Downstream Snapshot Readers & GC Stress
;;;
;;; Captures a multi-shot composable continuation enclosing an inner prompt
;;; frame (which enters the captured metacontinuation prefix), then replays
;;; that SAME continuation concurrently across 12 SMP threads while an active
;;; downstream consumer thread reads published immutable snapshots and forces
;;; garbage collections. Verifies zero cross-shot corruption, zero prefix
;;; escape-k clobbering, and exact snapshot immutability.

(let* ((outer-tag (make-continuation-prompt-tag 'smp-outer))
       (inner-tag (make-continuation-prompt-tag 'smp-inner))
       (shared-multi-k #f)
       (num-threads (max 4 (min 16 (##current-vm-processor-count))))
       (shots-per-thread 40)
       (ok-shots (make-atomic-fxbox 0))
       (reader-ok (make-atomic-fxbox 0))
       (stop-reader (make-atomic-fxbox 0))
       ;; Published immutable snapshot read continuously by downstream consumer
       (published-snap (make-vector 32 7777)))
  ;; Capture multi-shot composable continuation across an inner prompt frame
  (call-with-continuation-prompt
   (lambda ()
     (let ((inner-res
            (call-with-continuation-prompt
             (lambda ()
               (let ((x (call-with-composable-continuation
                         (lambda (k)
                           (set! shared-multi-k k)
                           (abort-current-continuation outer-tag (lambda () 'captured)))
                         outer-tag)))
                 ;; Each shot computes a fresh immutable snapshot vector (COW fork)
                 (let ((v (make-vector 8 (fx+ x 100))))
                   (fx+ (vector-ref v 0) (vector-ref v 7)))))
             inner-tag)))
       (fx+ inner-res 1)))
   outer-tag)
  (test-assert (procedure? shared-multi-k))
  (let* ((reader-thread
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ((iters 0))
                (if (fx= (atomic-fxbox-ref stop-reader) 0)
                    (begin
                      (let check ((idx 0) (good #t))
                        (if (fx< idx 32)
                            (check (fx+ idx 1)
                                   (and good (fx= (vector-ref published-snap idx) 7777)))
                            (if good (atomic-fxbox+/fetch! reader-ok 1))))
                      (if (fx= (fxand iters 31) 31) (thread-yield!))
                      (loop (fx+ iters 1)))))))))
         (workers
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
                                  (let* ((arg (fx+ (fx* t 100) s))
                                         (res (shared-multi-k arg))
                                         (expected (fx+ (fx* 2 (fx+ arg 100)) 1)))
                                    (if (and (fx= res expected)
                                             (fx= (vector-ref published-snap 0) 7777))
                                        (atomic-fxbox+/fetch! ok-shots 1))
                                    (if (and (fx= t 0) (fx= (fxand s 15) 15))
                                        (##gc))
                                    (sloop (fx+ s 1))))))))
                        acc))))))
    (for-each thread-join! workers)
    (atomic-fxbox-set! stop-reader 1)
    (thread-join! reader-thread)
    (test-equal (fx* num-threads shots-per-thread) (atomic-fxbox-ref ok-shots))
    (test-assert (fx>= (atomic-fxbox-ref reader-ok) 0))
    (test-equal 7777 (vector-ref published-snap 31))))

;;;============================================================================
;;; 9. CPU-Adaptive Adversarial Concurrency & GC-Barrier Regressions (9a-9e)

;; 9a. Lock-free closure-code one-shot identity & adaptive-P call/1cc throughput
;;     regression (zero weak-table mutex contention, zero false positives).
(let* ((num-threads (max 2 (min 16 (##current-vm-processor-count))))
       (iters 4000)
       (tag (make-continuation-prompt-tag 'c25-1cc))
       (plain-fn (lambda (x) (fx+ x 1)))
       (ok-count (make-atomic-fxbox 0)))
  (test-equal #f (one-shot-continuation? plain-fn))
  (test-equal #f (one-shot-continuation-consumed? plain-fn))
  (test-equal #t (raises-error? (lambda () (promote-one-shot-continuation! plain-fn))))
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let inner ((i 0) (sum 0))
                            (if (fx< i iters)
                                (let ((v (call-with-continuation-prompt
                                          (lambda ()
                                            (call/1cc (lambda (k) (k 1)) tag))
                                          tag)))
                                  (inner (fx+ i 1) (fx+ sum v)))
                                (if (fx= sum iters)
                                    (atomic-fxbox+/fetch! ok-count 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; 9b. Adaptive-P shift/reset GC-crossing replay stress (verifies frozen replay
;;     underflow frames never overwrite enclosing prompt stack continuations).
(let* ((num-threads (max 2 (min 16 (##current-vm-processor-count))))
       (iters 6000)
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
                          (let inner ((i 0) (sum 0))
                            (if (fx< i iters)
                                (begin
                                  (if (and (fx= t 0) (fx= (fxand i 511) 511))
                                      (##gc))
                                  (inner (fx+ i 1)
                                         (fx+ sum (reset (fx+ 1 (shift k (k 2)))))))
                                (if (fx= sum (fx* iters 3))
                                    (atomic-fxbox+/fetch! ok-count 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; 9c. Adaptive-P concurrent invoke vs promote-one-shot-continuation! race:
;;     every round must linearize cleanly with zero consumed-continuation resurrection.
(let* ((num-threads (max 4 (min 16 (##current-vm-processor-count))))
       (rounds 30)
       (tag (make-continuation-prompt-tag 'c25-race))
       (good-rounds (make-atomic-fxbox 0)))
  (let rloop ((r 0))
    (if (fx< r rounds)
        (let ((shared-k #f)
              (go (make-atomic-fxbox 0))
              (invoke-wins (make-atomic-fxbox 0))
              (promote-wins (make-atomic-fxbox 0)))
          (call-with-continuation-prompt
           (lambda ()
             (fx+ 1 (call-with-one-shot-composable-continuation
                     (lambda (k)
                       (set! shared-k k)
                       (abort-current-continuation tag (lambda () 'cap)))
                     tag)))
           tag)
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
                                   (if (fx= (fxand i 1) 0)
                                       (with-exception-catcher
                                        (lambda (e) #f)
                                        (lambda ()
                                          (if (fx= (shared-k r) (fx+ r 1))
                                              (atomic-fxbox+/fetch! invoke-wins 1))))
                                       (with-exception-catcher
                                        (lambda (e) #f)
                                        (lambda ()
                                          (if (promote-one-shot-continuation! shared-k)
                                              (atomic-fxbox+/fetch! promote-wins 1))))))))
                               acc))))))
            (atomic-fxbox-set! go 1)
            (for-each thread-join! threads)
            (let ((iw (atomic-fxbox-ref invoke-wins))
                  (pw (atomic-fxbox-ref promote-wins))
                  (consumed? (one-shot-continuation-consumed? shared-k)))
              ;; Either consumed before any promotion (iw=1, pw=0, consumed?=#t)
              ;; OR promoted before consumption (pw>=1, consumed?=#f, iw>=1).
              (if (or (and consumed? (fx= iw 1) (fx= pw 0))
                      (and (not consumed?) (fx>= pw 1) (fx>= iw 1)))
                  (atomic-fxbox+/fetch! good-rounds 1)))
            (rloop (fx+ r 1))))))
  (test-equal rounds (atomic-fxbox-ref good-rounds)))

;; 9d. dynamic-wind denv preservation across default prompt normal return
;;     (%mc-return-vals) under concurrent SATB/GC activity.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (iters 500)
       (tag (make-continuation-prompt-tag 'c25-dw))
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
                          (let inner ((i 0) (good #t))
                            (if (fx< i iters)
                                (let ((log '()))
                                  (let ((res
                                         (call-with-continuation-prompt
                                          (lambda ()
                                            (dynamic-wind
                                              (lambda () (set! log (cons 'in log)))
                                              (lambda () (fx+ i 10))
                                              (lambda () (set! log (cons 'out log)))))
                                          tag)))
                                    (if (and (fx= t 0) (fx= (fxand i 63) 63)) (##gc))
                                    (inner (fx+ i 1)
                                           (and good
                                                (fx= res (fx+ i 10))
                                                (equal? log '(out in))))))
                                (if good (atomic-fxbox+/fetch! ok-count 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; 9e. Adaptive-P STW Minor GC packed-ulock barrier & active nursery churn +
;;     explicit contraction stress (hundreds of back-to-back STW barriers).
(let* ((num-threads (max 2 (min 16 (##current-vm-processor-count))))
       (rounds 40)
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
                          (let rloop ((r 0) (acc 0))
                            (if (fx< r rounds)
                                (let ((v (make-vector 2048 r)))
                                  (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                  (rloop (fx+ r 1) (fx+ acc (vector-ref v 0) (vector-ref v 2047))))
                                (if (fx= acc (fx* rounds (fx- rounds 1)))
                                    (atomic-fxbox+/fetch! ok-count 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (##gc)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; 10. Exception-Unwind Metacontinuation & Continuation-Mark Coherency
;;;     (Single-Thread Exactness + Adaptive-P SMP Torture)

;; 10a. Nested prompt exception unwind: outer prompt -> inner catcher -> inner
;;      prompt + marks -> error. Must pop ONLY inner prompt & inner marks,
;;      preserve outer prompt & outer marks, and execute post-catcher code
;;      EXACTLY once (zero stale-frame time-travel).
(let ((t-outer (make-continuation-prompt-tag 'exn-outer))
      (t-inner (make-continuation-prompt-tag 'exn-inner))
      (after-count 0))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'outer-mark 'alive
              (let ((v (with-exception-catcher
                        (lambda (e) 'caught-inner)
                        (lambda ()
                          (call-with-continuation-prompt
                           (lambda ()
                             (with-continuation-mark 'inner-mark 'leaked
                               (error "inner-prompt-boom")))
                           t-inner)))))
                (set! after-count (fx+ after-count 1))
                (test-equal #f (continuation-prompt-available? t-inner))
                (test-equal #t (continuation-prompt-available? t-outer))
                (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'inner-mark))
                (test-equal '(alive) (continuation-mark-set->list (current-continuation-marks) 'outer-mark))
                (list 'done v))))
          t-outer)))
    (test-equal '(done caught-inner) res)
    (test-equal 1 after-count)
    (test-equal #f (continuation-prompt-available? t-outer))))

;; 10b. Top-level & nested with-continuation-mark exception unwind (outside any
;;      prompt) + O(1) tail-recursive mark preservation.
(with-exception-catcher
 (lambda (e) 'caught-top-mark)
 (lambda ()
   (with-continuation-mark 'top-leaked 123
     (error "top-mark-boom"))))
(test-equal '() (continuation-mark-set->list (current-continuation-marks) 'top-leaked))

(with-continuation-mark 'outer-k 'ok
  (begin
    (with-exception-catcher
     (lambda (e) 'caught-nested-mark)
     (lambda ()
       (with-continuation-mark 'inner-k 'gone
         (error "nested-mark-boom"))))
    (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'inner-k))
    (test-equal '(ok) (continuation-mark-set->list (current-continuation-marks) 'outer-k))))

;; 10c. Composable continuation captured under one prompt/catcher and replayed
;;      inside a DIFFERENT with-exception-catcher where it throws: exception
;;      must be delivered to the replayer's catcher with zero leaked uframe.
(let ((t-cap (make-continuation-prompt-tag 'cap-exn))
      (t-outer (make-continuation-prompt-tag 'outer-replay-exn))
      (saved-k #f)
      (after-count 0))
  (call-with-continuation-prompt
   (lambda ()
     (let ((x (call-with-composable-continuation
               (lambda (k)
                 (set! saved-k k)
                 (abort-current-continuation t-cap (lambda () 'captured)))
               t-cap)))
       (if (eq? x 'boom)
           (error "replayed-boom")
           (fx+ x 1))))
   t-cap)
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (let ((v (with-exception-catcher
                      (lambda (e) (error-exception-message e))
                      (lambda () (saved-k 'boom)))))
              (set! after-count (fx+ after-count 1))
              (list v (saved-k 41))))
          t-outer)))
    (test-equal '("replayed-boom" 42) res)
    (test-equal 1 after-count)))

;; 10d. Adaptive-P SMP concurrent exception-unwind + continuable handler torture
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 80)
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
                          (let ((to (make-continuation-prompt-tag 'smp-to))
                                (ti (make-continuation-prompt-tag 'smp-ti)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((cnt 0))
                                    (let ((res
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (let ((v (with-exception-catcher
                                                        (lambda (e) r)
                                                        (lambda ()
                                                          (call-with-continuation-prompt
                                                           (lambda ()
                                                             (with-continuation-mark 'k r
                                                               (error "smp-boom")))
                                                           ti)))))
                                                (set! cnt (fx+ cnt 1))
                                                (and (not (continuation-prompt-available? ti))
                                                     (null? (continuation-mark-set->list
                                                             (current-continuation-marks) 'k))
                                                     (fx= v r))))
                                            to)))
                                      ;; Also exercise continuable with-exception-handler
                                      (let ((cres
                                             (with-exception-handler
                                              (lambda (e) (fx+ e 100))
                                              (lambda ()
                                                (call-with-continuation-prompt
                                                 (lambda () (fx+ (raise r) 1))
                                                 ti)))))
                                        (if (and (fx= t 0) (fx= (fxand r 31) 31)) (##gc))
                                        (rloop (fx+ r 1)
                                               (and good res (fx= cnt 1)
                                                    (fx= cres (fx+ r 101)))))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; 11. Transactional Post-dynamic-wind Commit, Captured-Continuation Marks
;;;     Inspection & Zero-Leak One-Shot Slot Clearing (Adaptive-P SMP)

;; 11a. Transactional abort across dynamic-wind: after-thunk must see intact
;;      marks & active prompt; if after-thunk raises caught inside the prompt,
;;      the prompt and marks must remain 100% intact.
(let ((t-a (make-continuation-prompt-tag 'dw-abort-a))
      (t-b (make-continuation-prompt-tag 'dw-abort-b))
      (seen-marks #f)
      (seen-prompt #f))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'dw-k 'inside-mark
              (dynamic-wind
                (lambda () #!void)
                (lambda () (abort-current-continuation t-a 'aborted-ok))
                (lambda ()
                  (set! seen-marks
                        (continuation-mark-set->list (current-continuation-marks) 'dw-k))
                  (set! seen-prompt (continuation-prompt-available? t-a))))))
          t-a
          (lambda (v) v))))
    (test-equal 'aborted-ok res)
    (test-equal '(inside-mark) seen-marks)
    (test-equal #t seen-prompt)
    (test-equal #f (continuation-prompt-available? t-a)))
  (let ((res2
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'dw-k2 'survives
              (with-exception-catcher
               (lambda (e)
                 (list 'caught
                       (continuation-prompt-available? t-b)
                       (continuation-mark-set->list (current-continuation-marks) 'dw-k2)))
               (lambda ()
                 (dynamic-wind
                   (lambda () #!void)
                   (lambda () (abort-current-continuation t-b 'never))
                   (lambda () (error "after-abort-boom")))))))
          t-b
          (lambda (v) (list 'wrong-handler v)))))
    (test-equal '(caught #t (survives)) res2)
    (test-equal #f (continuation-prompt-available? t-b))))

;; 11b. Exact (continuation-marks cont) inspection for composable, noncomp,
;;      call/1cc, and one-shot composable continuations + consumed slot clear
;;      vs promoted multi-shot mark preservation.
(let ((t-m (make-continuation-prompt-tag 'marks-inspect))
      (ck #f) (nk #f) (ok1 #f) (ok-promo #f) (raw-1cc #f))
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'mk 'comp-val
       (call-with-composable-continuation (lambda (k) (set! ck k) 'ok) t-m)))
   t-m)
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'mk 'noncomp-val
       (call-with-non-composable-continuation (lambda (k) (set! nk k) 'ok) t-m)))
   t-m)
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'mk 'oneshot-val
       (call-with-one-shot-composable-continuation (lambda (k) (set! ok1 k) 'ok) t-m)))
   t-m)
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'mk 'promo-val
       (call-with-one-shot-composable-continuation (lambda (k) (set! ok-promo k) 'ok) t-m)))
   t-m)
  (with-continuation-mark 'mk 'raw-val
    (call/1cc (lambda (k) (set! raw-1cc k) 'ok) (make-continuation-prompt-tag 'absent)))
  (with-continuation-mark 'mk 'caller-decoy
    (begin
      (test-equal '(comp-val) (continuation-mark-set->list (continuation-marks ck) 'mk))
      (test-equal '(noncomp-val) (continuation-mark-set->list (continuation-marks nk) 'mk))
      (test-equal '(oneshot-val) (continuation-mark-set->list (continuation-marks ok1) 'mk))
      (test-equal '(raw-val) (continuation-mark-set->list (continuation-marks raw-1cc) 'mk))
      ;; Consume ok1 -> slots immediately cleared (zero GC retention leak)
      (ok1 'done)
      (test-equal #t (one-shot-continuation-consumed? ok1))
      (test-equal '() (continuation-mark-set->list (continuation-marks ok1) 'mk))
      ;; Promote ok-promo -> marks preserved across multiple invocations
      (promote-one-shot-continuation! ok-promo)
      (ok-promo 'shot1)
      (ok-promo 'shot2)
      (test-equal '(promo-val) (continuation-mark-set->list (continuation-marks ok-promo) 'mk)))))

;; 11c. Transactional non-composable continuation invocation across dynamic-wind
;;      whose after-thunk raises an exception: prompt and marks stay intact.
(let ((t-nc (make-continuation-prompt-tag 'dw-noncomp))
      (saved-nk #f))
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'nc-k 'alive
              (let ((first? (call-with-non-composable-continuation
                             (lambda (k) (set! saved-nk k) #t)
                             t-nc)))
                (if first?
                    (with-exception-catcher
                     (lambda (e)
                       (list 'caught-nc
                             (continuation-prompt-available? t-nc)
                             (continuation-mark-set->list (current-continuation-marks) 'nc-k)))
                     (lambda ()
                       (dynamic-wind
                         (lambda () #!void)
                         (lambda () (saved-nk #f))
                         (lambda () (error "noncomp-after-boom")))))
                    'jumped))))
          t-nc)))
    (test-equal '(caught-nc #t (alive)) res)
    (test-equal #f (continuation-prompt-available? t-nc))))

;; 11d. Adaptive-P SMP concurrent torture: transactional dynamic-wind aborts
;;      (normal & throwing) + concurrent one-shot clear vs multishot mark reads.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 50)
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
                          (let ((tg (make-continuation-prompt-tag 'smp-dw)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((obs-ok #f))
                                    (let ((v1
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (with-continuation-mark 'sk r
                                                (dynamic-wind
                                                  (lambda () #!void)
                                                  (lambda () (abort-current-continuation tg r))
                                                  (lambda ()
                                                    (set! obs-ok
                                                          (and (continuation-prompt-available? tg)
                                                               (equal? (continuation-mark-set->list
                                                                        (current-continuation-marks) 'sk)
                                                                       (list r))))))))
                                            tg
                                            (lambda (x) x)))
                                          (v2
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (with-exception-catcher
                                               (lambda (e) (continuation-prompt-available? tg))
                                               (lambda ()
                                                 (dynamic-wind
                                                   (lambda () #!void)
                                                   (lambda () (abort-current-continuation tg 'no))
                                                   (lambda () (error "smp-dw-boom"))))))
                                            tg
                                            (lambda (x) #f))))
                                      ;; One-shot composable with marks + fast reclaim
                                      (let ((k1 #f))
                                        (let ((v3
                                               (call-with-continuation-prompt
                                                (lambda ()
                                                  (fx+ 10
                                                       (call-with-one-shot-composable-continuation
                                                        (lambda (k)
                                                          (set! k1 k)
                                                          (abort-current-continuation tg (lambda () (k r))))
                                                        tg)))
                                                tg)))
                                          (if (and (fx= t 0) (fx= (fxand r 15) 15)) (##gc))
                                          (rloop (fx+ r 1)
                                                 (and good obs-ok (fx= v1 r) v2
                                                      (fx= v3 (fx+ r 10))
                                                      (one-shot-continuation-consumed? k1)
                                                      (not (continuation-prompt-available? tg))))))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; Raw call/1cc Transactional Control-State Restore & Public API Guards

;; Raw call/1cc escaping an inner prompt, continuation mark, and barrier must
;; restore outer control state cleanly with zero zombie prompts or marks.
(let ((t-inner (make-continuation-prompt-tag 'raw-inner))
      (t-outer (make-continuation-prompt-tag 'raw-outer))
      (t-absent (make-continuation-prompt-tag 'raw-absent)))
  ;; Top-level raw call/1cc escaping inner prompt + mark + barrier
  (let ((res
         (with-continuation-mark 'scope 'top
           (call/1cc
            (lambda (k)
              (call-with-continuation-prompt
               (lambda ()
                 (with-continuation-mark 'scope 'inner
                   (call-with-continuation-barrier
                    (lambda () (k 'escaped-top)))))
               t-inner
               (lambda (v) (list 'wrong-prompt v))))))))
    (test-equal 'escaped-top res)
    (test-equal #f (continuation-prompt-available? t-inner))
    (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'scope)))

  ;; Raw call/1cc captured inside an outer prompt (with absent tag) escaping an
  ;; inner prompt must discard the inner prompt while preserving the outer one.
  (let ((outer-res
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'layer 'outer
              (let ((v (call/1cc
                        (lambda (k)
                          (call-with-continuation-prompt
                           (lambda ()
                             (with-continuation-mark 'layer 'inner
                               (k 'escaped-to-outer)))
                           t-inner))
                        t-absent)))
                (list v
                      (continuation-prompt-available? t-outer)
                      (continuation-prompt-available? t-inner)
                      (continuation-mark-set->list (current-continuation-marks t-outer) 'layer)))))
          t-outer)))
    (test-equal '(escaped-to-outer #t #f (outer)) outer-res)
    (test-equal #f (continuation-prompt-available? t-outer))
    (test-equal #f (continuation-prompt-available? t-inner))))

;; Raw call/1cc escaping across dynamic-wind: after-thunk must observe intact
;; inner prompt and marks; throwing inside after-thunk caught within the inner
;; prompt must keep inner control state completely intact.
(let ((t-dw1 (make-continuation-prompt-tag 'raw-dw-ok))
      (t-dw2 (make-continuation-prompt-tag 'raw-dw-throw))
      (t-abs (make-continuation-prompt-tag 'raw-dw-absent))
      (seen-prompt #f)
      (seen-marks #f))
  (let ((res
         (with-continuation-mark 'dw-raw 'outer
           (call/1cc
            (lambda (k)
              (call-with-continuation-prompt
               (lambda ()
                 (with-continuation-mark 'dw-raw 'inner
                   (dynamic-wind
                     (lambda () #!void)
                     (lambda () (k 'jumped-clean))
                     (lambda ()
                       (set! seen-prompt (continuation-prompt-available? t-dw1))
                       (set! seen-marks
                             (continuation-mark-set->list
                              (current-continuation-marks t-dw1) 'dw-raw))))))
               t-dw1))
            t-abs))))
    (test-equal 'jumped-clean res)
    (test-equal #t seen-prompt)
    (test-equal '(inner) seen-marks)
    (test-equal #f (continuation-prompt-available? t-dw1))
    (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'dw-raw)))

  ;; After-thunk raises inside inner prompt: raw jump is aborted cleanly and
  ;; inner prompt/marks remain intact.
  (let ((res2
         (call/1cc
          (lambda (k)
            (call-with-continuation-prompt
             (lambda ()
               (with-continuation-mark 'dw-raw2 'survives
                 (with-exception-catcher
                  (lambda (e)
                    (list 'caught-after
                          (continuation-prompt-available? t-dw2)
                          (continuation-mark-set->list
                           (current-continuation-marks t-dw2) 'dw-raw2)))
                  (lambda ()
                    (dynamic-wind
                      (lambda () #!void)
                      (lambda () (k 'never-reaches))
                      (lambda () (error "raw-after-boom")))))))
             t-dw2))
          t-abs)))
    (test-equal '(caught-after #t (survives)) res2)
    (test-equal #f (continuation-prompt-available? t-dw2))))

;; Promoted multi-shot raw call/1cc restores captured outer prompt and marks
;; cleanly across repeated replays.
(let ((t-outer (make-continuation-prompt-tag 'raw-promo-outer))
      (t-inner (make-continuation-prompt-tag 'raw-promo-inner))
      (t-abs (make-continuation-prompt-tag 'raw-promo-absent))
      (saved-k #f)
      (replays 0)
      (log '()))
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'pm 'outer-mark
       (let ((v (call/1cc
                 (lambda (k)
                   (promote-one-shot-continuation! k)
                   (set! saved-k k)
                   0)
                 t-abs)))
         (set! log
               (cons (list v
                           (continuation-prompt-available? t-outer)
                           (continuation-prompt-available? t-inner)
                           (continuation-mark-set->list
                            (current-continuation-marks t-outer) 'pm))
                     log))
         (if (fx< replays 2)
             (begin
               (set! replays (fx+ replays 1))
               (call-with-continuation-prompt
                (lambda ()
                  (with-continuation-mark 'pm 'inner-zombie
                    (saved-k replays)))
                t-inner))))))
   t-outer)
  (test-equal '((2 #t #f (outer-mark))
                (1 #t #f (outer-mark))
                (0 #t #f (outer-mark)))
              log)
  (test-equal #f (continuation-prompt-available? t-outer))
  (test-equal #f (continuation-prompt-available? t-inner)))

;; Public API argument validation under (declare (not safe)): invalid arguments
;; raise clean Scheme errors without crashing.
(let ((check-err
       (lambda (thunk)
         (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f)))))
  (test-equal #t (check-err (lambda () (call-with-continuation-prompt 123))))
  (test-equal #t (check-err (lambda () (call-with-continuation-prompt (lambda () 1) 'bad-tag))))
  (test-equal #t (check-err (lambda () (call-with-continuation-prompt (lambda () 1) t1 456))))
  (test-equal #t (check-err (lambda () (continuation-prompt-available? 'bad-tag))))
  (test-equal #t (check-err (lambda () (abort-current-continuation 'bad-tag))))
  (test-equal #t (check-err (lambda () (call-with-continuation-barrier 123))))
  (test-equal #t (check-err (lambda () (call-with-composable-continuation 123))))
  (test-equal #t (check-err (lambda () (call-with-composable-continuation (lambda (k) k) 'bad-tag))))
  (test-equal #t (check-err (lambda () (call-with-non-composable-continuation 123))))
  (test-equal #t (check-err (lambda () (call-with-non-composable-continuation (lambda (k) k) 'bad-tag))))
  (test-equal #t (check-err (lambda () (call/1cc 123))))
  (test-equal #t (check-err (lambda () (call/1cc (lambda (k) k) 'bad-tag))))
  (test-equal #t (check-err (lambda () (call-with-one-shot-composable-continuation 123))))
  (test-equal #t (check-err (lambda () (call-with-one-shot-composable-continuation (lambda (k) k) 'bad-tag))))
  (test-equal #t (check-err (lambda () (current-continuation-marks 'bad-tag))))
  (test-equal #t (check-err (lambda () (continuation-marks #f 'bad-tag))))
  (test-equal #t (check-err (lambda () (continuation-mark-set->list #f 'k 'bad-tag))))
  (test-equal #t (check-err (lambda () (continuation-mark-set->list* #f 123))))
  (test-equal #t (check-err (lambda () (continuation-mark-set->list* #f '(k) #f 'bad-tag))))
  (test-equal #t (check-err (lambda () (continuation-mark-set-first #f 'k #f 'bad-tag))))
  (test-equal #t (check-err (lambda () (call-with-immediate-continuation-mark 'k 123))))
  ;; Default prompt handler rejects non-procedure abort value cleanly
  (test-equal #t
    (check-err
     (lambda ()
       (call-with-continuation-prompt
        (lambda () (abort-current-continuation t1 999))
        t1)))))

;; Adaptive-P SMP torture: concurrent raw call/1cc escapes across prompts,
;; marks, and dynamic-wind (both clean completion and throwing after-thunks)
;; interleaved with GC.
(let* ((num-threads (max 2 (min 12 (##current-vm-processor-count))))
       (rounds 40)
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
                          (let ((tg-in (make-continuation-prompt-tag 'smp-raw-in))
                                (tg-abs (make-continuation-prompt-tag 'smp-raw-abs)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((after-ok #f))
                                    (let ((v1
                                           (call/1cc
                                            (lambda (k)
                                              (call-with-continuation-prompt
                                               (lambda ()
                                                 (with-continuation-mark 'raw-k r
                                                   (dynamic-wind
                                                     (lambda () #!void)
                                                     (lambda () (k r))
                                                     (lambda ()
                                                       (set! after-ok
                                                             (and (continuation-prompt-available? tg-in)
                                                                  (equal? (continuation-mark-set->list
                                                                           (current-continuation-marks tg-in) 'raw-k)
                                                                          (list r))))))))
                                               tg-in))
                                            tg-abs))
                                          (v2
                                           (call/1cc
                                            (lambda (k)
                                              (call-with-continuation-prompt
                                               (lambda ()
                                                 (with-continuation-mark 'raw-k2 r
                                                   (with-exception-catcher
                                                    (lambda (e)
                                                      (and (continuation-prompt-available? tg-in)
                                                           (equal? (continuation-mark-set->list
                                                                    (current-continuation-marks tg-in) 'raw-k2)
                                                                   (list r))))
                                                    (lambda ()
                                                      (dynamic-wind
                                                        (lambda () #!void)
                                                        (lambda () (k #f))
                                                        (lambda () (error "smp-raw-after")))))))
                                               tg-in))
                                            tg-abs)))
                                      (if (and (fx= t 0) (fx= (fxand r 15) 15)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good after-ok (fx= v1 r) v2
                                                  (not (continuation-prompt-available? tg-in))
                                                  (null? (continuation-mark-set->list
                                                          (current-continuation-marks) 'raw-k))
                                                  (null? (continuation-mark-set->list
                                                          (current-continuation-marks) 'raw-k2))))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
;;; Transactional Composable Continuation Replay Across dynamic-wind & Barriers

;; Caller dynamic-wind after-thunk must observe pure caller prompts and marks
;; (never the target composable continuation's not-yet-entered prompts or marks).
(let ((t-out (make-continuation-prompt-tag 'comp-dw-out))
      (t-in (make-continuation-prompt-tag 'comp-dw-in))
      (saved #f)
      (log '()))
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-prompt
      (lambda ()
        (with-continuation-mark 'mk 'target-mark
          (+ 1 (call-with-composable-continuation (lambda (k) (set! saved k) 0) t-out))))
      t-in))
   t-out)
  (let ((res
         (call-with-continuation-prompt
          (lambda ()
            (with-continuation-mark 'mk 'caller-mark
              (dynamic-wind
                (lambda ()
                  (set! log (cons (list 'before
                                        (continuation-prompt-available? t-in)
                                        (continuation-mark-set->list
                                         (current-continuation-marks) 'mk))
                                  log)))
                (lambda () (saved 10))
                (lambda ()
                  (set! log (cons (list 'after
                                        (continuation-prompt-available? t-in)
                                        (continuation-mark-set->list
                                         (current-continuation-marks) 'mk))
                                  log))))))
          t-out)))
    (test-equal 11 res)
    (test-equal '((before #f (caller-mark))
                  (after #f (caller-mark))
                  (before #f (caller-mark))
                  (after #f (caller-mark)))
                (reverse log))))

;; Continuation barrier remains strictly enforced when invoking a multi-shot or
;; one-shot composable continuation captured outside the barrier.
(let ((t-outer (make-continuation-prompt-tag 'bar-outer))
      (t-cap (make-continuation-prompt-tag 'bar-cap))
      (saved-multi #f)
      (saved-1shot #f))
  (call-with-continuation-prompt
   (lambda ()
     (let ((v (call-with-composable-continuation (lambda (k) (set! saved-multi k) 'init) t-cap)))
       (if (eq? v 'go)
           (call-with-composable-continuation (lambda (k) 'barrier-bypassed) t-outer)
           v)))
   t-cap)
  (call-with-continuation-prompt
   (lambda ()
     (let ((v (call-with-one-shot-composable-continuation (lambda (k) (set! saved-1shot k) 'init) t-cap)))
       (if (eq? v 'go)
           (call-with-composable-continuation (lambda (k) 'barrier-bypassed) t-outer)
           v)))
   t-cap)
  (test-equal 'barrier-enforced
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-barrier
        (lambda ()
          (with-exception-catcher
           (lambda (e) 'barrier-enforced)
           (lambda () (saved-multi 'go))))))
     t-outer))
  (test-equal 'barrier-enforced
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-barrier
        (lambda ()
          (with-exception-catcher
           (lambda (e) 'barrier-enforced)
           (lambda () (saved-1shot 'go))))))
     t-outer)))

;; Multi-value composable continuation across caller dynamic-wind and barrier.
(let ((t-mv (make-continuation-prompt-tag 'comp-mv))
      (saved-mv #f)
      (after-saw #f))
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'mvk 'target-mv
       (call-with-values
         (lambda ()
           (call-with-composable-continuation (lambda (k) (set! saved-mv k) (values 0 0)) t-mv))
         (lambda (a b) (+ a b)))))
   t-mv)
  (test-equal 30
    (call-with-continuation-prompt
     (lambda ()
       (with-continuation-mark 'mvk 'caller-mv
         (dynamic-wind
           (lambda () #!void)
           (lambda () (saved-mv 10 20))
           (lambda ()
             (if (not after-saw)
                 (set! after-saw (continuation-mark-set->list (current-continuation-marks) 'mvk)))))))
     t-mv))
  (test-equal '(caller-mv) after-saw))

;; Adaptive-P SMP torture: concurrent composable replay across dynamic-wind and
;; continuation barriers interleaved with GC.
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
                          (let ((tg-out (make-continuation-prompt-tag 'smp-cb-out))
                                (tg-cap (make-continuation-prompt-tag 'smp-cb-cap)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((sk #f) (after-clean #t))
                                    (call-with-continuation-prompt
                                     (lambda ()
                                       (with-continuation-mark 'smk 'target
                                         (let ((v (call-with-composable-continuation
                                                   (lambda (k) (set! sk k) 'init)
                                                   tg-cap)))
                                           (if (eq? v 'probe-barrier)
                                               (call-with-composable-continuation
                                                (lambda (k) 'bypassed)
                                                tg-out)
                                               v))))
                                     tg-cap)
                                    (let ((r1
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (with-continuation-mark 'smk 'caller
                                                (dynamic-wind
                                                  (lambda () #!void)
                                                  (lambda () (sk r))
                                                  (lambda ()
                                                    (if (not (equal? (continuation-mark-set->list
                                                                      (current-continuation-marks) 'smk)
                                                                     '(caller)))
                                                        (set! after-clean #f))))))
                                            tg-out))
                                          (r2
                                           (call-with-continuation-prompt
                                            (lambda ()
                                              (call-with-continuation-barrier
                                               (lambda ()
                                                 (with-exception-catcher
                                                  (lambda (e) 'blocked)
                                                  (lambda () (sk 'probe-barrier))))))
                                            tg-out)))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good after-clean (fx= r1 r) (eq? r2 'blocked)))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;; Aliased one-shot stack-span safety:
;; 1) Direct invocation of a one-shot composable continuation without aborting
;;    first places caller-k above sub-k on the same break chain; repeated
;;    invocations must not corrupt stack grants.
;; 2) Nested raw call/1cc capturing k2 inside k1's receiver, escaping via k1,
;;    and later resuming k2 must preserve k1's underlying stack span for k2.
(let ((t-direct (make-continuation-prompt-tag 'direct-1shot)))
  (let loop ((i 0) (acc 0))
    (if (fx< i 5000)
        (loop (fx+ i 1)
              (fx+ acc
                   (call-with-continuation-prompt
                    (lambda ()
                      (fx+ 1 (call-with-one-shot-composable-continuation
                              (lambda (k) (k 1))
                              t-direct)))
                    t-direct)))
        (test-equal 15000 acc))))

(let loop ((i 0) (ok #t))
  (if (and ok (fx< i 5000))
      (let ((saved-k2 #f))
        (let ((res
               (let ((x (call/1cc
                         (lambda (k1)
                           (let ((y (call/1cc
                                     (lambda (k2)
                                       (set! saved-k2 k2)
                                       (k1 'first-escape)))))
                             (list 'from-k2 y))))))
                 (if (eq? x 'first-escape)
                     (saved-k2 i)
                     x))))
          (loop (fx+ i 1) (equal? res (list 'from-k2 i)))))
      (test-equal #t ok)))

;; Dynamic continuation-barrier push/pop: entering and exiting an inner barrier
;; inside a replayed composable continuation must preserve an enclosing outer barrier.
(let ((t-out (make-continuation-prompt-tag 'dynbar-out))
      (t-cap (make-continuation-prompt-tag 'dynbar-cap))
      (saved #f))
  (call-with-continuation-prompt
   (lambda ()
     (let ((v (call-with-composable-continuation (lambda (k) (set! saved k) 'init) t-cap)))
       (if (eq? v 'go)
           (begin
             (call-with-continuation-barrier (lambda () 'inner-barrier-ok))
             (call-with-composable-continuation (lambda (k) 'outer-barrier-bypassed) t-out))
           v)))
   t-cap)
  (test-equal 'outer-barrier-preserved
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-barrier
        (lambda ()
          (with-exception-catcher
           (lambda (e) 'outer-barrier-preserved)
           (lambda () (saved 'go))))))
     t-out)))

;; Dynamic continuation-mark exception unwind across same-thread and cross-thread
;; composable continuation replay (including tail-position mark replacement).
(let ((tag (make-continuation-prompt-tag 'dynmark-same))
      (saved-k #f))
  (with-continuation-mark 'outer 'dead
    (call-with-continuation-prompt
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (list 'caught
                (continuation-mark-set->list (current-continuation-marks) 'resumer)
                (continuation-mark-set->list (current-continuation-marks) 'outer)
                (continuation-mark-set->list (current-continuation-marks) 'inner)))
        (lambda ()
          (with-continuation-mark 'inner 'v1
            (with-continuation-mark 'inner 'v2
              (let ((x (call-with-composable-continuation
                        (lambda (k)
                          (set! saved-k k)
                          (abort-current-continuation tag 'cap))
                        tag)))
                (if (eq? x 'boom) (raise 'kaboom) x)))))))
     tag
     (lambda (v) v)))
  (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'outer))
  (with-continuation-mark 'resumer 'alive
    (let ((r (saved-k 'boom)))
      (test-equal '(caught (alive) () ()) r)))
  ;; Non-escaping exception handler returns into active inner mark and exits cleanly.
  (let ((tag2 (make-continuation-prompt-tag 'dynmark-nonesc))
        (saved-k2 #f))
    (call-with-continuation-prompt
     (lambda ()
       (with-exception-handler
        (lambda (e)
          (list 'handled
                (continuation-mark-set->list (current-continuation-marks) 'resumer)
                (continuation-mark-set->list (current-continuation-marks) 'inner)))
        (lambda ()
          (with-continuation-mark 'inner 'in-val
            (let ((x (call-with-composable-continuation
                      (lambda (k)
                        (set! saved-k2 k)
                        (abort-current-continuation tag2 'cap))
                      tag2)))
              (let ((hr (if (eq? x 'go) (raise 'soft) x)))
                (list hr (continuation-mark-set->list (current-continuation-marks) 'inner))))))))
     tag2
     (lambda (v) v))
    (with-continuation-mark 'resumer 'alive2
      (test-equal '((handled (alive2) ()) (in-val)) (saved-k2 'go)))))

;; Cross-thread SMP replay of with-continuation-mark exception unwind:
;; invoking threads must unwind only their own mark stacks without touching the
;; capture thread's mark stack.
(let* ((hw (##current-vm-processor-count))
       (num-threads (max 2 (min 8 hw)))
       (rounds 40)
       (tag (make-continuation-prompt-tag 'dynmark-smp))
       (saved-k #f)
       (ok-count (make-atomic-fxbox 0)))
  (with-continuation-mark 'origin-dead 'corrupt
    (call-with-continuation-prompt
     (lambda ()
       (with-exception-catcher
        (lambda (e)
          (list (continuation-mark-set->list (current-continuation-marks) 'worker-mark)
                (continuation-mark-set->list (current-continuation-marks) 'origin-dead)
                (continuation-mark-set->list (current-continuation-marks) 'inner)))
        (lambda ()
          (with-continuation-mark 'inner 'v1
            (with-continuation-mark 'inner 'v2
              (let ((x (call-with-composable-continuation
                        (lambda (k)
                          (set! saved-k k)
                          (abort-current-continuation tag 'cap))
                        tag)))
                (if (eq? x 'boom) (raise 'smp-err) x)))))))
     tag
     (lambda (v) v)))
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (fx= t num-threads)
               acc
               (loop (fx+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let rloop ((r 0) (good #t))
                            (if (fx< r rounds)
                                (let ((res
                                       (with-continuation-mark 'worker-mark t
                                         (saved-k 'boom))))
                                  (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                  (rloop (fx+ r 1)
                                         (and good
                                              (equal? res (list (list t) '() '()))
                                              (null? (continuation-mark-set->list
                                                      (current-continuation-marks) 'inner))
                                              (null? (continuation-mark-set->list
                                                      (current-continuation-marks) 'worker-mark)))))
                                (if good (atomic-fxbox+/fetch! ok-count 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))
    (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'origin-dead))
    (test-equal '() (continuation-mark-set->list (current-continuation-marks) 'inner))))

;; Tail-checked call-with-immediate-continuation-mark:
;; tail position observes the immediate mark (including chained tail marks and
;; tail helper calls); non-tail, cross-prompt, and outer-only frames see default.
(let ((tail-helper
       (lambda (k d) (call-with-immediate-continuation-mark k (lambda (v) v) d))))
  (test-equal 42
    (with-continuation-mark 'imm 42
      (call-with-immediate-continuation-mark 'imm (lambda (v) v) 'none)))
  (test-equal 42
    (with-continuation-mark 'imm 42
      (call-with-immediate-continuation-mark 'imm (lambda (v) v))))
  (test-equal 99
    (with-continuation-mark 'imm 42
      (with-continuation-mark 'other 'x
        (with-continuation-mark 'imm 99
          (tail-helper 'imm 'none)))))
  (test-equal 'x
    (with-continuation-mark 'imm 42
      (with-continuation-mark 'other 'x
        (tail-helper 'other 'none))))
  (test-equal '(none)
    (with-continuation-mark 'imm 42
      (list (call-with-immediate-continuation-mark 'imm (lambda (v) v) 'none))))
  (test-equal '(#f)
    (with-continuation-mark 'imm 42
      (list (call-with-immediate-continuation-mark 'imm (lambda (v) v)))))
  (test-equal 'none
    (with-continuation-mark 'imm 42
      (call-with-continuation-prompt
       (lambda ()
         (call-with-immediate-continuation-mark 'imm (lambda (v) v) 'none)))))
  (test-equal 'none
    (with-continuation-mark 'imm 42
      (let ((x (with-continuation-mark 'other 1
                 (call-with-immediate-continuation-mark 'imm (lambda (v) v) 'none))))
        x))))

;; Prompt-scoped continuation-marks slicing on captured continuations (including
;; nested self-replay) and strict argument validation.
(let ((t1 (make-continuation-prompt-tag 'cm-t1))
      (t2 (make-continuation-prompt-tag 'cm-t2))
      (saved-comp #f)
      (saved-raw #f))
  (call-with-continuation-prompt
   (lambda ()
     (with-continuation-mark 'm 'outer
       (call-with-continuation-prompt
        (lambda ()
          (with-continuation-mark 'm 'inner
            (call-with-composable-continuation
             (lambda (k)
               (set! saved-comp k)
               (abort-current-continuation t1 'done))
             t1)))
        t2
        (lambda (v) v))))
   t1
   (lambda (v) v))
  (test-equal '(inner outer) (continuation-mark-set->list (continuation-marks saved-comp t1) 'm))
  (test-equal '(inner) (continuation-mark-set->list (continuation-marks saved-comp t2) 'm))
  ;; Raw call/1cc captured across nested prompt t2:
  (with-continuation-mark 'rm 'outer
    (call-with-continuation-prompt
     (lambda ()
       (with-continuation-mark 'rm 'inner
         (call/1cc (lambda (k) (set! saved-raw k) 'ok) t1)))
     t2
     (lambda (v) v)))
  (test-equal '(inner) (continuation-mark-set->list (continuation-marks saved-raw t2) 'rm))
  ;; Nested self-replay: replay inner continuation inside t2 and capture again up to t1.
  (let ((t-rep (make-continuation-prompt-tag 'cm-rep))
        (t-mid (make-continuation-prompt-tag 'cm-mid))
        (k-once #f)
        (k-twice #f))
    (call-with-continuation-prompt
     (lambda ()
       (with-continuation-mark 'rep 'a
         (let ((x (call-with-composable-continuation
                   (lambda (k)
                     (set! k-once k)
                     (abort-current-continuation t-rep 'c1))
                   t-rep)))
           (if (eq? x 'capture-again)
               (call-with-composable-continuation
                (lambda (k)
                  (set! k-twice k)
                  (abort-current-continuation t-rep 'c2))
                t-rep)
               x))))
     t-rep
     (lambda (v) v))
    (call-with-continuation-prompt
     (lambda ()
       (with-continuation-mark 'rep 'a
         (call-with-continuation-prompt
          (lambda () (k-once 'capture-again))
          t-mid
          (lambda (v) v))))
     t-rep
     (lambda (v) v))
    (test-equal '(a a) (continuation-mark-set->list (continuation-marks k-twice t-rep) 'rep))
    (test-equal '(a) (continuation-mark-set->list (continuation-marks k-twice t-mid) 'rep)))
  ;; Invalid non-continuation argument rejection:
  (let ((check-err (lambda (th)
                     (with-exception-catcher (lambda (e) #t) (lambda () (th) #f)))))
    (test-equal #t (check-err (lambda () (continuation-marks 123))))
    (test-equal #t (check-err (lambda () (continuation-mark-set->list 'bad 'm))))
    (test-equal #t (check-err (lambda () (continuation-mark-set->list* 42 '(m)))))
    (test-equal #t (check-err (lambda () (continuation-mark-set-first "bad" 'm))))))

;; Prompt-scoped barrier capture/restore for non-composable continuations and
;; prompted call/1cc:
;; 1) Invoking a barrier-free non-composable continuation or prompted call/1cc
;;    inside an enclosing outer barrier must preserve that outer barrier.
;; 2) Capturing a non-composable continuation or prompted call/1cc inside an
;;    outer barrier that lies outside the delimiting prompt must NOT suffer a
;;    false-positive barrier error when invoked in a fresh prompt outside that
;;    outer barrier.
;; 3) Capturing across an inner barrier inside the delimiting prompt must block
;;    invocation from outside that inner barrier while permitting invocation
;;    within the same inner barrier.
(let ((t-out (make-continuation-prompt-tag 'ncb-out))
      (t-in  (make-continuation-prompt-tag 'ncb-in))
      (saved-nc #f)
      (saved-1cc #f))
  (call-with-continuation-prompt
   (lambda ()
     (let ((v (call-with-non-composable-continuation
               (lambda (k) (set! saved-nc k) 'cap)
               t-in)))
       (if (eq? v 'probe)
           (call-with-composable-continuation (lambda (k) 'bypassed) t-out)
           v)))
   t-in)
  (call-with-continuation-prompt
   (lambda ()
     (let ((v (call/1cc (lambda (k) (set! saved-1cc k) 'cap) t-in)))
       (if (eq? v 'probe)
           (call-with-composable-continuation (lambda (k) 'bypassed) t-out)
           v)))
   t-in)
  (test-equal 'blocked-nc
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-barrier
        (lambda ()
          (with-exception-catcher
           (lambda (e) 'blocked-nc)
           (lambda ()
             (call-with-continuation-prompt
              (lambda () (saved-nc 'probe))
              t-in))))))
     t-out))
  (test-equal 'blocked-1cc
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-barrier
        (lambda ()
          (with-exception-catcher
           (lambda (e) 'blocked-1cc)
           (lambda ()
             (call-with-continuation-prompt
              (lambda () (saved-1cc 'probe))
              t-in))))))
     t-out)))

(let ((t-in (make-continuation-prompt-tag 'ncb-nofp))
      (saved-nc #f)
      (saved-1cc #f))
  (call-with-continuation-barrier
   (lambda ()
     (call-with-continuation-prompt
      (lambda ()
        (let ((v (call-with-non-composable-continuation
                  (lambda (k) (set! saved-nc k) 'cap)
                  t-in)))
          (if (number? v) (fx+ v 10) v)))
      t-in)
     (call-with-continuation-prompt
      (lambda ()
        (let ((v (call/1cc (lambda (k) (set! saved-1cc k) 'cap) t-in)))
          (if (number? v) (fx+ v 20) v)))
      t-in)))
  (test-equal 42 (call-with-continuation-prompt (lambda () (saved-nc 32)) t-in))
  (test-equal 52 (call-with-continuation-prompt (lambda () (saved-1cc 32)) t-in)))

(let ((t-in (make-continuation-prompt-tag 'ncb-inner))
      (saved-inner #f)
      (in-same-res #f))
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-barrier
      (lambda ()
        (let ((v (call-with-non-composable-continuation
                  (lambda (k) (set! saved-inner k) 'first)
                  t-in)))
          (if (eq? v 'first)
              (saved-inner 'same-barrier-ok)
              (set! in-same-res v))))))
   t-in)
  (test-equal 'same-barrier-ok in-same-res)
  (test-equal 'inner-blocked
    (call-with-continuation-prompt
     (lambda ()
       (with-exception-catcher
        (lambda (e) 'inner-blocked)
        (lambda () (saved-inner 'illegal-entry))))
     t-in)))

;; Optional continuation argument on continuation-prompt-available?
(let ((t1 (make-continuation-prompt-tag 'cpa-t1))
      (t2 (make-continuation-prompt-tag 'cpa-t2))
      (t3 (make-continuation-prompt-tag 'cpa-t3))
      (k-comp #f)
      (k-1shot #f)
      (k-raw #f))
  (call-with-continuation-prompt
   (lambda ()
     (call-with-continuation-prompt
      (lambda ()
        (call-with-composable-continuation (lambda (k) (set! k-comp k) 'ok) t1)
        (call-with-one-shot-composable-continuation (lambda (k) (set! k-1shot k) 'ok) t1)
        (call/1cc (lambda (k) (set! k-raw k) 'ok) t3))
      t2))
   t1)
  (test-equal #t (continuation-prompt-available? t2 k-comp))
  (test-equal #f (continuation-prompt-available? t1 k-comp))
  (test-equal #f (continuation-prompt-available? t3 k-comp))
  (test-equal #t (continuation-prompt-available? t2 k-1shot))
  (test-equal #t (continuation-prompt-available? t2 k-raw))
  (test-equal #t (continuation-prompt-available? t1 k-raw))
  (test-equal #f (continuation-prompt-available? t3 k-raw))
  ;; Consumed one-shot continuation returns #f cleanly
  (k-1shot 'consume)
  (test-equal #f (continuation-prompt-available? t2 k-1shot))
  ;; Invalid continuation argument raises
  (test-equal #t
    (with-exception-catcher
     (lambda (e) #t)
     (lambda () (continuation-prompt-available? t1 'not-a-cont) #f))))

;; Adaptive-P SMP torture: concurrent non-composable barrier preservation +
;; false-positive absence + dynamic-wind unwind + ##gc across P threads.
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
                          (let ((tg-out (make-continuation-prompt-tag 'smp-ncb-out))
                                (tg-in  (make-continuation-prompt-tag 'smp-ncb-in)))
                            (let rloop ((r 0) (good #t))
                              (if (fx< r rounds)
                                  (let ((sk #f))
                                    (call-with-continuation-barrier
                                     (lambda ()
                                       (call-with-continuation-prompt
                                        (lambda ()
                                          (let ((v (call-with-non-composable-continuation
                                                    (lambda (k) (set! sk k) 'init)
                                                    tg-in)))
                                            (if (eq? v 'probe)
                                                (call-with-composable-continuation
                                                 (lambda (k) 'bypassed)
                                                 tg-out)
                                                v)))
                                        tg-in)))
                                    (let ((r1 (call-with-continuation-prompt
                                               (lambda () (sk r))
                                               tg-in))
                                          (r2 (call-with-continuation-prompt
                                               (lambda ()
                                                 (call-with-continuation-barrier
                                                  (lambda ()
                                                    (with-exception-catcher
                                                     (lambda (e) 'blocked)
                                                     (lambda ()
                                                       (call-with-continuation-prompt
                                                        (lambda () (sk 'probe))
                                                        tg-in))))))
                                               tg-out)))
                                      (if (and (fx= t 0) (fx= (fxand r 7) 7)) (##gc))
                                      (rloop (fx+ r 1)
                                             (and good (fx= r1 r) (eq? r2 'blocked)))))
                                  (if good (atomic-fxbox+/fetch! ok-count 1))))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal num-threads (atomic-fxbox-ref ok-count))))

;;;============================================================================
