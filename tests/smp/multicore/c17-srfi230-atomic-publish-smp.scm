;; C17: Phase A.1 SRFI-230 Atomic Publication & GC Barrier Adversarial SMP PBT
;; Verifies across p1..p12 under simultaneous minor/major/SATB GC pressure:
;;   1. Release/acquire publication of freshly allocated young cyclic & multi-node
;;      graphs through ___SRFI230_BOX_STORE / ___SRFI230_BOX_CAS / ___SRFI230_BOX_SWAP.
;;   2. Zero torn reads, zero dangling pointers, and full SATB reachability preservation.
;;   3. Exact linearizable contended arithmetic via ___SRFI230_FXBOX_ADD.

(declare (standard-bindings) (extended-bindings) (block))

(c-declare "#include \"gambit.h\"")

(define atomic-box-ref-acq
  (c-lambda (scheme-object) scheme-object
    "___return(___SRFI230_BOX_LOAD(___arg1, ___SRFI230_ORDER_ACQUIRE));"))

(define atomic-box-set-rel!
  (c-lambda (scheme-object scheme-object) void
    "___SRFI230_BOX_STORE(___ps, ___arg1, ___arg2, ___SRFI230_ORDER_RELEASE);"))

(define atomic-box-swap-acqrel!
  (c-lambda (scheme-object scheme-object) scheme-object
    "___return(___SRFI230_BOX_SWAP(___ps, ___arg1, ___arg2, ___SRFI230_ORDER_ACQ_REL));"))

(define atomic-box-cas-acqrel!
  (c-lambda (scheme-object scheme-object scheme-object) scheme-object
    "___return(___SRFI230_BOX_CAS(___ps, ___arg1, ___arg2, ___arg3, ___SRFI230_ORDER_ACQ_REL));"))

(define atomic-fxbox-add-seqcst!
  (c-lambda (scheme-object scheme-object) scheme-object
    "___return(___SRFI230_FXBOX_ADD(___arg1, ___arg2, ___SRFI230_ORDER_SEQ_CST));"))

(define atomic-fence-seqcst!
  (c-lambda () void
    "___SRFI230_FENCE(___SRFI230_ORDER_SEQ_CST);"))

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
         (shared-box (box #f))
         (swap-box (box #f))
         (cas-box (box #f))
         (fx-counter (box 0))
         (done-box (box 0))
         (s0 (##process-statistics))
         (gc-thread
          (thread-start!
           (make-thread
            (lambda ()
              (let loop ((n 0))
                (if (= (atomic-box-ref-acq done-box) 1)
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
                                   (atomic-box-set-rel! shared-box pl)
                                   (let ((old-sw (atomic-box-swap-acqrel! swap-box pl)))
                                     (verify-payload! old-sw))
                                   (let* ((cur (atomic-box-ref-acq cas-box))
                                          (prev (atomic-box-cas-acqrel! cas-box cur pl)))
                                     (verify-payload! prev))
                                   (let ((obs (atomic-box-ref-acq shared-box)))
                                     (verify-payload! obs))
                                   (atomic-fxbox-add-seqcst! fx-counter 1)
                                   (when (= (modulo i 500) 0)
                                     (atomic-fence-seqcst!))
                                   (wloop (+ i 1) (+ reads 1))))))))
                       acc)))))
         (total-reads (apply + (map thread-join! worker-threads))))
    (atomic-box-set-rel! done-box 1)
    (let* ((gc-pulses (thread-join! gc-thread))
           (final-fx (atomic-box-ref-acq fx-counter))
           (expected-fx (* workers iters))
           (s1 (##process-statistics))
           (gc-total (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6))))))
      (verify-payload! (atomic-box-ref-acq shared-box))
      (verify-payload! (atomic-box-ref-acq swap-box))
      (verify-payload! (atomic-box-ref-acq cas-box))
      (unless (= final-fx expected-fx)
        (error "C17 fxbox linearizability mismatch" final-fx expected-fx))
      (write (list 'C17-SRFI230-ATOMIC-PUBLISH-PASS
                   'procs nprocs
                   'workers workers
                   'reads total-reads
                   'fx-sum final-fx
                   'gc-pulses gc-pulses
                   'gc-total gc-total))
      (newline))))

(run-c17)
