;;; C1 (Chez mats/gc.ms + OCaml 5 parallel ephemeron/finaliser inspired):
;;; Concurrent weak-keys & weak-values tables + thousands of wills executing
;;; secondary allocations & table mutations under active p2/p4 GC-Hammer.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (run-c1)
  (let* ((wt-keys (make-table test: eq? weak-keys: #t))
         (wt-vals (make-table test: eqv? weak-values: #t))
         (tbl-mtx (make-mutex 'c1-tbl))
         ;; Direct SRFI-18 mutex inside make-will action! This deterministically
         ;; self-deadlocked before the non-reentrant ##gc-finalize! fix (Bug #2A).
         (will-mtx (make-mutex 'c1-will))
         (will-fired (vector 0))
         (will-alloc-sum (vector 0))
         (strong-keep (make-vector 200 #f))
         (n-workers 4)
         (iters 1500))
    (define (make-worker wid)
      (thread-start!
       (make-thread
        (lambda ()
          (let loop ((i 0))
            (if (< i iters)
                (let ((ephemeral-key (list 'eph wid i))
                      (ephemeral-val (make-vector 6 (+ wid i))))
                  ;; Register will whose action allocates AND locks a non-reentrant
                  ;; SRFI-18 mutex directly inside ___INTR_GC!
                  (make-will
                   ephemeral-key
                   (lambda (obj)
                     (let ((extra (vector 'will-payload (car obj) (cadr obj))))
                       (mutex-lock! will-mtx)
                       (vector-set! will-fired 0 (+ (vector-ref will-fired 0) 1))
                       (vector-set! will-alloc-sum 0
                                    (+ (vector-ref will-alloc-sum 0)
                                       (vector-length extra)))
                       (mutex-unlock! will-mtx))))
                  ;; Also exercise concurrent lock-free ##final-will-registry mutations
                  (if (= (modulo i 50) 0)
                      (##make-final-will (cons 'fin wid) (lambda (x) #f)))
                  ;; Mutate weak-keys & weak-values tables concurrently (under mutex for table API)
                  (mutex-lock! tbl-mtx)
                  (table-set! wt-keys ephemeral-key ephemeral-val)
                  (table-set! wt-vals (+ 10000 (* wid iters) i) ephemeral-val)
                  ;; Periodically probe pinned entries and snapshot copy
                  (if (= (modulo i 50) 0)
                      (let* ((idx (modulo (+ wid i) 200))
                             (pair (vector-ref strong-keep idx))
                             (got-k (table-ref wt-keys (car pair) #f))
                             (got-v (table-ref wt-vals idx #f)))
                        (mc-assert (eq? got-k (cdr pair)) 'c1-pinned-weak-key-lost wid i idx)
                        (mc-assert (eq? got-v (cdr pair)) 'c1-pinned-weak-val-lost wid i idx)))
                  (if (= (modulo i 300) 0)
                      (let ((snap (table-copy wt-keys)))
                        (mc-assert (>= (table-length snap) 200) 'c1-copy-shrunk wid i (table-length snap))))
                  (mutex-unlock! tbl-mtx)
                  (if (= (modulo i 75) 0) (thread-yield!))
                  (loop (+ i 1))))))
        (string-append "c1-w-" (number->string wid)))))
    ;; Install 200 strongly-held keys/values that MUST survive all GCs.
    (let init ((i 0))
      (if (< i 200)
          (let ((k (cons 'pinned-key i))
                (v (vector 'pinned-val i (* i 7))))
            (vector-set! strong-keep i (cons k v))
            (table-set! wt-keys k v)
            (table-set! wt-vals i v)
            (init (+ i 1)))))

    (let* ((gc0 (mc-gc-count))
           (res
            (with-gc-hammer
             0.002
             (lambda ()
               (let ((ws (map make-worker '(0 1 2 3))))
                 (for-each thread-join! ws))
               ;; Force GC rounds + brief yields until ALL 6000 in-flight wills drain across all cores!
               (let drain ((k 0))
                 (if (and (< k 60) (< (vector-ref will-fired 0) (* n-workers iters)))
                     (begin (##gc) (thread-sleep! 0.005) (drain (+ k 1))))))))
           (pulses (cdr res))
           (gc-delta (- (mc-gc-count) gc0)))
      ;; Verify all 200 strongly-held entries are intact after full storm
      (let check ((i 0))
        (if (< i 200)
            (let* ((pair (vector-ref strong-keep i))
                   (k (car pair))
                   (v (cdr pair)))
              (mc-assert (eq? (table-ref wt-keys k #f) v) 'c1-final-weak-key-corrupt i)
              (mc-assert (eq? (table-ref wt-vals i #f) v) 'c1-final-weak-val-corrupt i)
              (mc-assert (= (vector-ref v 2) (* i 7)) 'c1-final-payload-corrupt i)
              (check (+ i 1)))))
      (let* ((fired (vector-ref will-fired 0))
             (total (* n-workers iters))
             ;; With VM-wide ##gc-pop-executable-will!, ZERO executable wills are
             ;; stranded on idle processors (pre-fix p4 stranded ~3000/6000).
             ;; At most 1 nonexecutable will per idle processor can remain live
             ;; via a parked processor's last GVM register snapshot.
             (min-expected (- total (mc-processor-count))))
        (mc-assert (>= fired min-expected) 'c1-wills-stranded fired total)
        (mc-assert (= (vector-ref will-alloc-sum 0) (* fired 3)) 'c1-will-accounting-mismatch fired)
        (display (list 'C1-WEAK-WILL-TABLE-PASS
                       'procs (mc-processor-count)
                       'wills-fired fired
                       'gc-pulses pulses
                       'gc-total gc-delta))
        (newline)
        (force-output)))))

(run-c1)
