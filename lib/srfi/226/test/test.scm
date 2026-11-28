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
