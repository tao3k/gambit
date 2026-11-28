;; C17: SRFI-230 Standard Library Atomic Publication & GC Barrier Adversarial SMP PBT
;; Uses the standard (import (srfi 230)) library directly across p1..p12 under
;; simultaneous minor/major/SATB GC pressure to verify:
;;   1. Release/acquire publication of freshly allocated young cyclic & multi-node
;;      graphs through atomic-box-set!, atomic-box-swap!, atomic-box-compare-and-swap!,
;;      and atomic-pair-set!/compare-and-swap!.
;;   2. Zero torn reads, zero dangling pointers, and full SATB reachability preservation.
;;   3. Exact linearizable contended arithmetic via atomic-fxbox+/fetch!, -/fetch!, xor/fetch!,
;;      and spinlock mutual exclusion via atomic-flag-test-and-set!/clear!.

(import (srfi 230))

(declare (standard-bindings) (extended-bindings) (block))

(define (make-cyclic-payload id seq)
  (let* ((v (make-vector 6 0))
         (fv (make-f64vector 64 (exact->inexact (+ id seq))))
         (p (cons id seq)))
    (vector-set! v 0 id)
    (vector-set! v 1 seq)
    (vector-set! v 2 p)
    (vector-set! v 3 fv)
    (vector-set! v 4 v) ;; intentional self-cycle
    (vector-set! v 5 (+ (* id 100000) seq))
    v))

(define (verify-payload! v)
  (when (vector? v)
    (let* ((id (vector-ref v 0))
           (seq (vector-ref v 1))
           (p (vector-ref v 2))
           (fv (vector-ref v 3))
           (self (vector-ref v 4))
           (chk (vector-ref v 5)))
      (unless (and (fixnum? id)
                   (fixnum? seq)
                   (pair? p)
                   (= (car p) id)
                   (= (cdr p) seq)
                   (f64vector? fv)
                   (= (f64vector-length fv) 64)
                   (= (f64vector-ref fv 0) (exact->inexact (+ id seq)))
                   (eq? self v)
                   (= chk (+ (* id 100000) seq)))
        (error "C17 torn or corrupted SRFI-230 payload" id seq chk)))))

(define (run-c17)
  (let* ((nprocs (##current-vm-processor-count))
         (workers (max 4 (* 2 nprocs)))
         (iters 4000)
         (shared-box (make-atomic-box #f))
         (swap-box (make-atomic-box #f))
         (cas-box (make-atomic-box #f))
         (shared-pair (make-atomic-pair #f 0))
         (fx-add (make-atomic-fxbox 0))
         (fx-sub (make-atomic-fxbox (* workers iters)))
         (fx-xor (make-atomic-fxbox 0))
         (spin-flag (make-atomic-flag))
         (spin-count (box 0))
         (done-box (make-atomic-fxbox 0))
         (s0 (##process-statistics))
         (gc-thread
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ((n 0))
                (if (= (atomic-fxbox-ref done-box (memory-order acquire)) 1)
                    n
                    (begin
                      (let ((junk (make-f64vector 512 1.0)))
                        (f64vector-set! junk 0 (exact->inexact n)))
                      (when (= (modulo n 40) 0) (##gc))
                      (thread-yield!)
                      (loop (+ n 1)))))))))
         (worker-threads
          (let loop ((w 0) (acc '()))
            (if (= w workers)
                acc
                (loop (+ w 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let wloop ((i 0) (reads 0))
                             (if (= i iters)
                                 reads
                                 (let ((pl (make-cyclic-payload w i)))
                                   (atomic-box-set! shared-box pl (memory-order release))
                                   (let ((old-sw (atomic-box-swap! swap-box pl (memory-order acquire-release))))
                                     (verify-payload! old-sw))
                                   (let* ((cur (atomic-box-ref cas-box (memory-order acquire)))
                                          (prev (atomic-box-compare-and-swap! cas-box cur pl (memory-order acquire-release))))
                                     (verify-payload! prev))
                                   (let ((obs (atomic-box-ref shared-box (memory-order acquire))))
                                     (verify-payload! obs))
                                   (atomic-pair-set! shared-pair pl i (memory-order release))
                                   (call-with-values
                                     (lambda () (atomic-pair-ref shared-pair (memory-order acquire)))
                                     (lambda (p-obj p-seq)
                                       (verify-payload! p-obj)
                                       (unless (fixnum? p-seq)
                                         (error "C17 torn SRFI-230 atomic-pair" p-seq))))
                                   (atomic-fxbox+/fetch! fx-add 1 (memory-order sequentially-consistent))
                                   (atomic-fxbox-/fetch! fx-sub 1 (memory-order relaxed))
                                   (atomic-fxbox-xor/fetch! fx-xor #x3c3c (memory-order relaxed))
                                   (when (= (modulo i 50) 0)
                                     (let acq ()
                                       (when (atomic-flag-test-and-set! spin-flag (memory-order acquire))
                                         (acq)))
                                     (set-box! spin-count (+ (unbox spin-count) 1))
                                     (atomic-flag-clear! spin-flag (memory-order release)))
                                   (when (= (modulo i 500) 0)
                                     (atomic-fence (memory-order sequentially-consistent)))
                                   (wloop (+ i 1) (+ reads 1))))))))
                       acc)))))
         (total-reads (apply + (map thread-join! worker-threads))))
    (atomic-fxbox-set! done-box 1 (memory-order release))
    (let* ((gc-pulses (thread-join! gc-thread))
           (final-add (atomic-fxbox-ref fx-add (memory-order acquire)))
           (final-sub (atomic-fxbox-ref fx-sub (memory-order acquire)))
           (final-xor (atomic-fxbox-ref fx-xor (memory-order acquire)))
           (expected-fx (* workers iters))
           (expected-spin (* workers (/ iters 50)))
           (s1 (##process-statistics))
           (gc-total (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6))))))
      (verify-payload! (atomic-box-ref shared-box (memory-order acquire)))
      (verify-payload! (atomic-box-ref swap-box (memory-order acquire)))
      (verify-payload! (atomic-box-ref cas-box (memory-order acquire)))
      (unless (and (= final-add expected-fx)
                   (= final-sub 0)
                   (= final-xor 0)
                   (= (unbox spin-count) expected-spin))
        (error "C17 SRFI-230 linearizability mismatch"
               final-add final-sub final-xor (unbox spin-count)))
      (write (list 'C17-SRFI230-ATOMIC-PUBLISH-PASS
                   'procs nprocs
                   'workers workers
                   'reads total-reads
                   'fx-sum final-add
                   'spin-locks (unbox spin-count)
                   'gc-pulses gc-pulses
                   'gc-total gc-total))
      (newline))))

(run-c17)
