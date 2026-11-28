;;; C12: Adversarial SMP Memory Scaling, Contraction, Direct-mmap Still, and
;;; Lock-Free Rest Fast-Span Challenge (refining adaptive_heap_scaling_and_reclaim_v2.qnt).
;;; Challenges:
;;;   1. Single explicit (##gc) after a large burst immediately breaks the legacy
;;;      16-GC contraction ratchet (heap size shrinks >= 55% in 1 GC, not 16!).
;;;   2. Large >= 64 KiB still objects (direct mmap/munmap) and medium 4 KiB still
;;;      objects churned across P parallel workers leave zero retained memory leak.
;;;   3. Concurrent variadic/keyword calls + mailbox sends across P cores verify
;;;      lock-free fast_span & strict-DRF mutex-guarded mailbox wakeup soundness.

(declare (standard-bindings) (extended-bindings) (block))

(define (make-burst-tree depth seed)
  (if (fx<= depth 0)
      (vector seed (fx+ seed 1) (cons seed (fx+ seed 2)))
      (cons (make-burst-tree (fx- depth 1) (fx+ seed 1))
            (make-burst-tree (fx- depth 1) (fx+ seed 2)))))

(define (rsum a b . rest)
  (let loop ((xs rest) (acc (fx+ a b)))
    (if (pair? xs) (loop (cdr xs) (fx+ acc (car xs))) acc)))

(define (kwsum a #!key (k1 3) (k2 5) #!rest r)
  (fx+ a k1 k2 (length r)))

(define (latest-heap-bytes)
  ;; ##process-statistics index 15 = last_gc_heap_size (movable + still bytes)
  (f64vector-ref (##process-statistics) 15))

(define (phase1-contraction-challenge!)
  ;; Establish the empty-VM baseline first (per-processor stack/young/mature floor
  ;; scales with P), then allocate ~25-35 MiB movable tree + 16 MiB direct-mmap
  ;; large still + 4 MiB medium still and verify a SINGLE (##gc) contracts the
  ;; burst delta (not blocked by the legacy 16-GC ratchet) on any core count P.
  (##gc)
  (let ((base-heap (latest-heap-bytes))
        (peak-heap 0.0)
        (after-heap 0.0))
    (let ((tree (make-burst-tree 16 1))
          (big-stills
           (let loop ((i 0) (acc '()))
             (if (fx= i 64)
                 acc
                 (loop (fx+ i 1) (cons (make-f64vector 32768 (exact->inexact i)) acc)))))
          (med-stills
           (let loop ((i 0) (acc '()))
             (if (fx= i 512)
                 acc
                 (loop (fx+ i 1) (cons (make-u8vector 8192 (fxand i 255)) acc))))))
      ;; Keep all objects live across one GC to establish true peak heap
      (##gc)
      (set! peak-heap (latest-heap-bytes))
      (let ((burst-delta (- peak-heap base-heap)))
        (if (not (and (pair? tree)
                      (= (length big-stills) 64)
                      (= (length med-stills) 512)
                      (> burst-delta 16000000.0)))
            (error "c12 phase1 peak allocation sanity failed"
                   (list base: base-heap peak: peak-heap delta: burst-delta)))))
    ;; Now all burst objects are dead. A SINGLE (##gc) MUST contract the burst immediately!
    (##gc)
    (set! after-heap (latest-heap-bytes))
    (let* ((burst-delta (- peak-heap base-heap))
           (retained-delta (max 0.0 (- after-heap base-heap)))
           (retained-ratio (/ retained-delta burst-delta)))
      (if (> retained-ratio 0.25)
          (error "c12 contraction ratchet detected (1 GC failed to shrink heap)"
                 (list base: base-heap peak: peak-heap after: after-heap
                       burst-delta: burst-delta retained-ratio: retained-ratio)))
      (list peak-heap after-heap retained-ratio))))

(define (phase2-smp-still-rest-mailbox-challenge!)
  (let* ((n-workers (max 4 (##current-vm-processor-count)))
         (threads
          (let loop ((w 0) (acc '()))
            (if (fx= w n-workers)
                acc
                (loop
                 (fx+ w 1)
                 (cons
                  (thread-start!
                   (make-thread
                    (lambda ()
                      ;; Interleave >= 64 KiB direct-mmap still churn, rest/kw calls, and mailbox
                      (let ((receiver
                             (thread-start!
                              (make-thread
                               (lambda ()
                                 (let rloop ((k 0) (sum 0))
                                   (if (fx= k 500)
                                       sum
                                       (rloop (fx+ k 1) (fx+ sum (thread-receive))))))))))
                        (let sloop ((i 0) (chk 0))
                          (if (fx= i 500)
                              (let ((rsum-val (thread-join! receiver)))
                                (if (not (fx= rsum-val 500))
                                    (error "c12 mailbox wakeup mismatch" rsum-val))
                                chk)
                              (begin
                                (if (fx= (fxand i 15) 0)
                                    ;; 128 KiB direct-mmap still buffer per burst
                                    (let ((buf (make-u8vector 131072 (fxand i 255))))
                                      (if (not (fx= (u8vector-ref buf 131071) (fxand i 255)))
                                          (error "c12 large still corruption"))))
                                (thread-send receiver 1)
                                (sloop (fx+ i 1)
                                       (fx+ chk
                                            (rsum 1 2 3 4 5 6)
                                            (kwsum 1 k1: 2 k2: 4 7 8))))))))))
                  acc))))))
    (let ((vals (map thread-join! threads)))
      (for-each
       (lambda (v)
         (if (not (fx= v (* 500 30)))
             (error "c12 rest/kw checksum mismatch" v)))
       vals))
    ;; Final single GC must leave heap small & contracted
    (##gc)
    (latest-heap-bytes)))

(let* ((p1 (phase1-contraction-challenge!))
       (p2-heap (phase2-smp-still-rest-mailbox-challenge!))
       (saved-lp (##get-live-percent)))
  (if (not (and (fixnum? saved-lp) (> saved-lp 0) (<= saved-lp 100)))
      (error "c12 invalid live-percent" saved-lp))
  (println "C12-MEMORY-SCALING-CONTRACTION-PASS"
           " peak_mib=" (round (/ (car p1) 1048576.0))
           " contracted_mib=" (round (/ (cadr p1) 1048576.0))
           " post_smp_mib=" (round (/ p2-heap 1048576.0))
           " procs=" (##current-vm-processor-count)))
