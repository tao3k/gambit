;;;============================================================================

;;; File: "test.scm"

;;; SRFI 230, Atomic Operations — Conformance & SMP Multicore Stress Tests

(import (srfi 230))
(import (_test))

;;;============================================================================
;;; 1. Memory orders

(test-equal #t (memory-order? (memory-order relaxed)))
(test-equal #t (memory-order? (memory-order acquire)))
(test-equal #t (memory-order? (memory-order release)))
(test-equal #t (memory-order? (memory-order acquire-release)))
(test-equal #t (memory-order? (memory-order sequentially-consistent)))
(test-equal #f (memory-order? 'invalid))
(test-equal #f (memory-order? 0))
(test-equal #f (memory-order? #f))

;;;============================================================================
;;; 2. Disjoint type predicates

(define flg (make-atomic-flag))
(define bx  (make-atomic-box 'init))
(define fxb (make-atomic-fxbox 42))
(define pr  (make-atomic-pair 'a 'b))

(test-equal #t (atomic-flag? flg))
(test-equal #f (atomic-flag? bx))
(test-equal #f (atomic-flag? fxb))
(test-equal #f (atomic-flag? pr))
(test-equal #f (atomic-flag? (box #f)))

(test-equal #t (atomic-box? bx))
(test-equal #f (atomic-box? flg))
(test-equal #f (atomic-box? fxb))
(test-equal #f (atomic-box? pr))
(test-equal #f (atomic-box? (box 1)))

(test-equal #t (atomic-fxbox? fxb))
(test-equal #f (atomic-fxbox? flg))
(test-equal #f (atomic-fxbox? bx))
(test-equal #f (atomic-fxbox? pr))

(test-equal #t (atomic-pair? pr))
(test-equal #f (atomic-pair? flg))
(test-equal #f (atomic-pair? bx))
(test-equal #f (atomic-pair? fxb))
(test-equal #f (atomic-pair? '(a . b)))

;;;============================================================================
;;; 3. Atomic flags

(test-equal #f (atomic-flag-test-and-set! flg))
(test-equal #t (atomic-flag-test-and-set! flg (memory-order acquire-release)))
(atomic-flag-clear! flg (memory-order release))
(test-equal #f (atomic-flag-test-and-set! flg (memory-order acquire)))
(atomic-flag-clear! flg)
(test-equal #f (atomic-flag-test-and-set! flg (memory-order relaxed)))
(atomic-flag-clear! flg (memory-order relaxed))

;;;============================================================================
;;; 4. Atomic boxes

(test-equal 'init (atomic-box-ref bx))
(test-equal 'init (atomic-box-ref bx (memory-order acquire)))
(atomic-box-set! bx 'next (memory-order release))
(test-equal 'next (atomic-box-ref bx (memory-order relaxed)))
(test-equal 'next (atomic-box-swap! bx 'swapped (memory-order acquire-release)))
(test-equal 'swapped (atomic-box-ref bx))
;; Failed CAS returns actual current contents
(test-equal 'swapped (atomic-box-compare-and-swap! bx 'wrong 'nope))
(test-equal 'swapped (atomic-box-ref bx))
;; Successful CAS returns previous contents and stores desired
(test-equal 'swapped (atomic-box-compare-and-swap! bx 'swapped 'final (memory-order sequentially-consistent)))
(test-equal 'final (atomic-box-ref bx))

;;;============================================================================
;;; 5. Atomic fixnum boxes (+, -, and, ior, xor, swap, cas)

(test-equal 42 (atomic-fxbox-ref fxb))
(atomic-fxbox-set! fxb 10 (memory-order release))
(test-equal 10 (atomic-fxbox-ref fxb (memory-order acquire)))
(test-equal 10 (atomic-fxbox-swap! fxb 20))
(test-equal 20 (atomic-fxbox-compare-and-swap! fxb 99 30))
(test-equal 20 (atomic-fxbox-compare-and-swap! fxb 20 30))
(test-equal 30 (atomic-fxbox+/fetch! fxb 5 (memory-order acquire-release)))
(test-equal 35 (atomic-fxbox-/fetch! fxb 15 (memory-order relaxed)))
(test-equal 20 (atomic-fxbox-ref fxb))
(test-equal 20 (atomic-fxbox-ior/fetch! fxb 3))
(test-equal 23 (atomic-fxbox-and/fetch! fxb 15))
(test-equal 7 (atomic-fxbox-xor/fetch! fxb 12))
(test-equal 11 (atomic-fxbox-ref fxb))

;;;============================================================================
;;; 6. Atomic pairs (2-value returns + lock-free CAS)

(call-with-values (lambda () (atomic-pair-ref pr))
  (lambda (a b)
    (test-equal 'a a)
    (test-equal 'b b)))

(atomic-pair-set! pr 'x 'y (memory-order release))
(call-with-values (lambda () (atomic-pair-swap! pr 'p 'q (memory-order acquire-release)))
  (lambda (a b)
    (test-equal 'x a)
    (test-equal 'y b)))

;; Failed pair CAS (car mismatch)
(call-with-values (lambda () (atomic-pair-compare-and-swap! pr 'wrong 'q 'u 'v))
  (lambda (a b)
    (test-equal 'p a)
    (test-equal 'q b)))
;; Failed pair CAS (cdr mismatch)
(call-with-values (lambda () (atomic-pair-compare-and-swap! pr 'p 'wrong 'u 'v))
  (lambda (a b)
    (test-equal 'p a)
    (test-equal 'q b)))
;; Successful pair CAS
(call-with-values (lambda () (atomic-pair-compare-and-swap! pr 'p 'q 'u 'v (memory-order sequentially-consistent)))
  (lambda (a b)
    (test-equal 'p a)
    (test-equal 'q b)))
(call-with-values (lambda () (atomic-pair-ref pr (memory-order acquire)))
  (lambda (a b)
    (test-equal 'u a)
    (test-equal 'v b)))

;;;============================================================================
;;; 7. Memory fences

(atomic-fence (memory-order relaxed))
(atomic-fence (memory-order acquire))
(atomic-fence (memory-order release))
(atomic-fence (memory-order acquire-release))
(atomic-fence (memory-order sequentially-consistent))

;;;============================================================================
;;; 8. True SMP Multicore Linearizability & GC Publication Stress Test

(let* ((nprocs (##current-vm-processor-count))
       (nworkers (max 4 (* 2 nprocs)))
       (iters 2000)
       (sum-fx (make-atomic-fxbox 0))
       (sub-fx (make-atomic-fxbox (* nworkers iters)))
       (xor-fx (make-atomic-fxbox 0))
       (spin-flag (make-atomic-flag))
       (lock-counter (box 0))
       (pub-box (make-atomic-box #f))
       (pub-pair (make-atomic-pair 0 0))
       (threads
        (let loop ((w 0) (acc '()))
          (if (= w nworkers)
              acc
              (loop (+ w 1)
                    (cons
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (let wloop ((i 0))
                           (when (< i iters)
                             ;; Contended fxbox + / - / xor
                             (atomic-fxbox+/fetch! sum-fx 1 (memory-order relaxed))
                             (atomic-fxbox-/fetch! sub-fx 1 (memory-order relaxed))
                             (atomic-fxbox-xor/fetch! xor-fx #x5a5a (memory-order relaxed))
                             ;; Publish fresh heap graph via atomic-box & atomic-pair
                             (let ((v (vector w i (cons w i))))
                               (atomic-box-set! pub-box v (memory-order release))
                               (let ((obs (atomic-box-ref pub-box (memory-order acquire))))
                                 (when (vector? obs)
                                   (let ((p (vector-ref obs 2)))
                                     (unless (and (pair? p)
                                                  (= (car p) (vector-ref obs 0))
                                                  (= (cdr p) (vector-ref obs 1)))
                                       (error "SRFI-230 torn box publication" obs))))))
                             (atomic-pair-set! pub-pair w i (memory-order release))
                             (call-with-values
                               (lambda () (atomic-pair-ref pub-pair (memory-order acquire)))
                               (lambda (a b)
                                 (unless (and (fixnum? a) (fixnum? b) (>= a 0) (>= b 0))
                                   (error "SRFI-230 torn pair publication" a b))))
                             ;; Spinlock mutual exclusion via atomic-flag
                             (when (= (modulo i 20) 0)
                               (let acquire ()
                                 (when (atomic-flag-test-and-set! spin-flag (memory-order acquire))
                                   (acquire)))
                               (set-box! lock-counter (+ (unbox lock-counter) 1))
                               (atomic-flag-clear! spin-flag (memory-order release)))
                             (wloop (+ i 1)))))))
                     acc))))))
  (for-each thread-join! threads)
  (test-equal (* nworkers iters) (atomic-fxbox-ref sum-fx))
  (test-equal 0 (atomic-fxbox-ref sub-fx))
  ;; Even number of workers * even iters => xor cancels to 0
  (test-equal 0 (atomic-fxbox-ref xor-fx))
  (test-equal (* nworkers (/ iters 20)) (unbox lock-counter)))

;;;============================================================================
;;; Memory-Order Load/Store Validation, Bounds Safety & Fixnum Wraparound

(define (raises-exc? thunk)
  (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f)))

;; Load operations reject release and acquire-release
(test-equal #t (raises-exc? (lambda () (atomic-box-ref bx (memory-order release)))))
(test-equal #t (raises-exc? (lambda () (atomic-box-ref bx (memory-order acquire-release)))))
(test-equal #t (raises-exc? (lambda () (atomic-fxbox-ref fxb (memory-order release)))))
(test-equal #t (raises-exc? (lambda () (atomic-fxbox-ref fxb (memory-order acquire-release)))))
(test-equal #t (raises-exc? (lambda () (atomic-pair-ref pr (memory-order release)))))
(test-equal #t (raises-exc? (lambda () (atomic-pair-ref pr (memory-order acquire-release)))))

;; Store operations reject acquire and acquire-release
(test-equal #t (raises-exc? (lambda () (atomic-flag-clear! flg (memory-order acquire)))))
(test-equal #t (raises-exc? (lambda () (atomic-flag-clear! flg (memory-order acquire-release)))))
(test-equal #t (raises-exc? (lambda () (atomic-box-set! bx 1 (memory-order acquire)))))
(test-equal #t (raises-exc? (lambda () (atomic-box-set! bx 1 (memory-order acquire-release)))))
(test-equal #t (raises-exc? (lambda () (atomic-fxbox-set! fxb 1 (memory-order acquire)))))
(test-equal #t (raises-exc? (lambda () (atomic-fxbox-set! fxb 1 (memory-order acquire-release)))))
(test-equal #t (raises-exc? (lambda () (atomic-pair-set! pr 1 2 (memory-order acquire)))))
(test-equal #t (raises-exc? (lambda () (atomic-pair-set! pr 1 2 (memory-order acquire-release)))))

;; Internal vector-atomic-* helpers reject non-vectors, out-of-bounds indices, and invalid orders
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-ref 123 0))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-ref (vector 1 2) -1))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-ref (vector 1 2) 2))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-set! (vector 1 2) 5 'x))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-swap! (vector 1 2) -1 'x))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-cas! (vector 1 2) 2 1 2))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-ref (vector 1 2) 0 (memory-order release)))))
(test-equal #t (raises-exc? (lambda () (srfi/230#vector-atomic-set! (vector 1 2) 0 'x (memory-order acquire)))))

;; Modular 2's-complement fixnum wraparound on atomic-fxbox+/fetch! and -/fetch!
(let* ((max-fx (- (expt 2 (- (##fixnum-width) 1)) 1))
       (min-fx (- (- max-fx) 1))
       (wb (make-atomic-fxbox max-fx)))
  (test-equal max-fx (atomic-fxbox+/fetch! wb 1))
  (test-equal min-fx (atomic-fxbox-ref wb))
  (test-equal min-fx (atomic-fxbox-/fetch! wb 1))
  (test-equal max-fx (atomic-fxbox-ref wb)))

;; atomic-pair-compare-and-swap! works across all 5 memory orders (including release & acq_rel)
(let ((ap (make-atomic-pair 0 0)))
  (for-each
   (lambda (ord)
     (call-with-values (lambda () (atomic-pair-ref ap))
       (lambda (v s)
         ;; Mismatch returns current pair unchanged
         (call-with-values (lambda () (atomic-pair-compare-and-swap! ap -1 s 99 99 ord))
           (lambda (rv rs)
             (test-equal v rv)
             (test-equal s rs)))
         ;; Match transitions atomically
         (call-with-values (lambda () (atomic-pair-compare-and-swap! ap v s (+ v 10) (+ s 1) ord))
           (lambda (rv rs)
             (test-equal v rv)
             (test-equal s rs))))))
   (list (memory-order relaxed)
         (memory-order acquire)
         (memory-order release)
         (memory-order acquire-release)
         (memory-order sequentially-consistent)))
  (call-with-values (lambda () (atomic-pair-ref ap))
    (lambda (v s)
      (test-equal 50 v)
      (test-equal 5 s))))

;;;============================================================================
;;; Adaptive-P SMP Lock-Free CAS Conservation (Treiber Stack + Stamped Pair + GC)

(let* ((p (##current-vm-processor-count))
       (w (max 4 (min 12 p)))
       (iters 400)
       (stack (make-atomic-box '()))
       (stamped (make-atomic-pair 0 0))
       (bits (make-atomic-fxbox 0))
       (pushed-sum (make-atomic-fxbox 0))
       (popped-sum (make-atomic-fxbox 0))
       (popped-cnt (make-atomic-fxbox 0))
       (threads
        (let loop ((tid 0) (acc '()))
          (if (= tid w)
              acc
              (loop (+ tid 1)
                    (cons
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (let iloop ((i 0))
                           (when (< i iters)
                             (let ((val (+ (* tid iters) i 1)))
                               ;; Push onto lock-free Treiber stack via atomic-box-compare-and-swap!
                               (let push ()
                                 (let* ((head (atomic-box-ref stack (memory-order acquire)))
                                        (node (cons val head)))
                                   (unless (eq? (atomic-box-compare-and-swap! stack head node (memory-order acquire-release))
                                                head)
                                     (push))))
                               (atomic-fxbox+/fetch! pushed-sum val)
                               ;; Increment stamped (val, stamp) pair via atomic-pair-compare-and-swap!
                               (let bump ()
                                 (call-with-values (lambda () (atomic-pair-ref stamped (memory-order acquire)))
                                   (lambda (cv cs)
                                     (call-with-values
                                       (lambda ()
                                         (atomic-pair-compare-and-swap!
                                          stamped cv cs (+ cv 1) (+ cs 1) (memory-order acquire-release)))
                                       (lambda (rv rs)
                                         (unless (and (eq? rv cv) (eq? rs cs))
                                           (bump)))))))
                               ;; Set per-thread bit via atomic-fxbox-ior/fetch!
                               (atomic-fxbox-ior/fetch! bits (arithmetic-shift 1 tid))
                               ;; Interleave pop & concurrent SATB GC
                               (when (= (modulo i 2) 1)
                                 (let pop ()
                                   (let ((head (atomic-box-ref stack (memory-order acquire))))
                                     (when (pair? head)
                                       (if (eq? (atomic-box-compare-and-swap! stack head (cdr head) (memory-order acquire-release))
                                                head)
                                           (begin
                                             (atomic-fxbox+/fetch! popped-sum (car head))
                                             (atomic-fxbox+/fetch! popped-cnt 1))
                                           (pop))))))
                               (when (and (= tid 0) (= (modulo i 128) 127))
                                 (##gc)))
                             (iloop (+ i 1)))))))
                     acc))))))
  (for-each thread-join! threads)
  ;; Drain remaining Treiber stack nodes
  (let drain ()
    (let ((head (atomic-box-ref stack)))
      (when (pair? head)
        (if (eq? (atomic-box-compare-and-swap! stack head (cdr head)) head)
            (begin
              (atomic-fxbox+/fetch! popped-sum (car head))
              (atomic-fxbox+/fetch! popped-cnt 1)))
        (drain))))
  (test-equal (* w iters) (atomic-fxbox-ref popped-cnt))
  (test-equal (atomic-fxbox-ref pushed-sum) (atomic-fxbox-ref popped-sum))
  (test-equal (- (arithmetic-shift 1 w) 1) (atomic-fxbox-ref bits))
  (call-with-values (lambda () (atomic-pair-ref stamped))
    (lambda (cv cs)
      (test-equal (* w iters) cv)
      (test-equal (* w iters) cs))))

;;;============================================================================
