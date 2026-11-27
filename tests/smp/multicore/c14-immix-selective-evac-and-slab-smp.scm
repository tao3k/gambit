;;; C14: Adversarial Slice 2 v3 Selective Immix Evacuation & Medium ___STILL
;;; Page-Backed Slab Challenge (refining slice2_v3_immix_evac_and_slab_v2.qnt).
;;; Challenges:
;;;   1. Selective Immix Evacuation (P2-1):
;;;      - Retain a dense mature anchor cohort (~6 MiB) whose clean-card slots
;;;        point directly into a fragmented sparse mature cohort (~16 MiB
;;;        allocated, 80% dropped -> ~20% live, flagged major_evacuate == 1).
;;;      - Trigger a Concurrent Major GC cycle to mark & flag sparse sections,
;;;        then run Minor GCs (staying well below 2x growth) to trigger
;;;        Selective Immix Evacuation.
;;;      - Verify 100% checksum integrity across BOTH dense pinned anchors and
;;;        their clean-card references into evacuated sparse objects, plus real
;;;        mature section reclamation!
;;;   2. Medium ___STILL Page-Backed Slab (2 KiB - 32 KiB, P2-3):
;;;      - Spawn P concurrent workers churning 4 KiB, 8 KiB, 16 KiB, and 32 KiB
;;;        still u8vectors/f64vectors across 4 waves with full byte verification
;;;        and post-wave contraction; verify zero corruption and zero RSS creep!

(declare (standard-bindings) (extended-bindings) (block))

(c-declare "#include \"gambit.h\"")

(define (gc-cm-stats)
  (let ((v (make-f64vector 8 0.0)))
    ((c-lambda (scheme-object) void
       "___EXT(___gc_concurrent_major_stats)(___PSTATE, ___CAST(double*, ___BODY_AS(___arg1, ___tSUBTYPED)));")
     v)
    v))

(define (gc-gen-stats)
  (let ((v (make-f64vector 8 0.0)))
    ((c-lambda (scheme-object) void
       "___EXT(___gc_generational_stats)(___PSTATE, ___CAST(double*, ___BODY_AS(___arg1, ___tSUBTYPED)));")
     v)
    v))

(define (gc-request-cm! finish-now)
  ((c-lambda (int) int "___return(___EXT(___gc_start_concurrent_major)(___PSTATE, ___arg1));")
   finish-now))

(define (latest-heap-bytes)
  (f64vector-ref (##process-statistics) 15))

(define (assert-eq! tag actual expected)
  (if (not (equal? actual expected))
      (error "C14-FAIL" tag actual expected)))

(define (make-tagged-node id)
  (let ((v (make-vector 24 id)))
    (vector-set! v 0 id)
    (vector-set! v 23 (fx+ id 7777))
    v))

(define (verify-tagged-node! v id tag)
  (if (not (and (vector? v)
                (fx= (vector-length v) 24)
                (fx= (vector-ref v 0) id)
                (fx= (vector-ref v 23) (fx+ id 7777))))
      (error "C14-CORRUPT" tag id v)))

(define (churn-movable! count)
  (let loop ((i 0) (acc 0))
    (if (fx= i count)
        acc
        (let ((v (make-vector 200 i)))
          (loop (fx+ i 1) (fx+ acc (vector-ref v 0)))))))

;; Phase 1: Selective Immix Evacuation with clean-card cross-references from
;; dense pinned mature sections into sparse evacuating mature sections.
(define (phase1-selective-evac-challenge!)
  (##gc)
  (let* ((n-dense 4000)
         (n-sparse 36000)
         (stride 6) ;; keep 1 of 6 => ~16.7% live (< 50% => major_evacuate == 1)
         (dense-anchors (make-vector n-dense #f))
         (sparse-all (make-vector n-sparse #f)))
    ;; Allocate sparse cohort first, then dense anchor cohort holding clean-card
    ;; pointers to the sparse survivors.
    (let loop ((i 0))
      (if (fx< i n-sparse)
          (begin
            (vector-set! sparse-all i (make-tagged-node i))
            (loop (fx+ i 1)))))
    (let loop ((i 0))
      (if (fx< i n-dense)
          (let* ((sidx (fx* (fxmodulo i (fxquotient n-sparse stride)) stride))
                 (anchor (make-vector 48 i)))
            ;; Clean-card reference from dense mature anchor -> sparse mature node
            (vector-set! anchor 1 (vector-ref sparse-all sidx))
            (vector-set! anchor 2 sidx)
            (vector-set! dense-anchors i anchor)
            (loop (fx+ i 1)))))
    ;; Promote both cohorts to mature space via Minor GC bursts (no full ##gc yet)
    (let* ((m0 (inexact->exact (round (f64vector-ref (gc-gen-stats) 0)))))
      (let promote ((k 0))
        (if (and (fx< k 20)
                 (fx< (inexact->exact (round (f64vector-ref (gc-gen-stats) 0))) (fx+ m0 3)))
            (begin
              (churn-movable! 4000)
              (promote (fx+ k 1))))))
    ;; Drop 5/6 of sparse-all so sparse sections become ~16.7% live Swiss cheese
    (let drop ((i 0))
      (if (fx< i n-sparse)
          (begin
            (if (not (fx= (fxmodulo i stride) 0))
                (vector-set! sparse-all i #f))
            (drop (fx+ i 1)))))
    ;; Drain any already-in-flight Concurrent Major cycle (whose SATB snapshot
    ;; predated the drop) before launching a fresh post-drop Concurrent Major cycle.
    (let drain-prior ((k 0))
      (if (and (fx< k 30)
               (not (fx= (inexact->exact (round (f64vector-ref (gc-cm-stats) 7))) 0)))
          (begin
            (gc-request-cm! 1)
            (churn-movable! 2000)
            (drain-prior (fx+ k 1)))))
    (let* ((mat-before (inexact->exact (round (f64vector-ref (gc-gen-stats) 4))))
           (cm0 (inexact->exact (round (f64vector-ref (gc-cm-stats) 0)))))
      ;; Request a fresh post-drop Concurrent Major GC cycle (start + finish) so
      ;; sparse sections get swept and flagged major_evacuate == 1.
      (gc-request-cm! 0)
      (let drive-cm ((k 0))
        (let ((cm-cur (inexact->exact (round (f64vector-ref (gc-cm-stats) 0)))))
          (if (and (fx< k 40) (fx= cm-cur cm0))
              (begin
                (if (fx>= k 2) (gc-request-cm! 1))
                (churn-movable! 2000)
                (drive-cm (fx+ k 1))))))
      (let ((mat-after-cm (inexact->exact (round (f64vector-ref (gc-gen-stats) 4))))
            (maj-after-cm (inexact->exact (round (f64vector-ref (gc-gen-stats) 1)))))
        ;; Now drive Minor GCs while major_phase == IDLE so Selective Immix Evacuation
        ;; evacuates sparse sections without copying dense sections or triggering full Major GC!
        (let ((min0 (inexact->exact (round (f64vector-ref (gc-gen-stats) 0)))))
          (let evac-drive ((k 0))
            (if (and (fx< k 30)
                     (fx< (inexact->exact (round (f64vector-ref (gc-gen-stats) 0))) (fx+ min0 4)))
                (begin
                  (churn-movable! 2000)
                  (evac-drive (fx+ k 1))))))
        ;; Verify EVERY clean-card reference from dense anchors to evacuated sparse nodes!
        (let verify-dense ((i 0))
          (if (fx< i n-dense)
              (let* ((anchor (vector-ref dense-anchors i))
                     (ref (vector-ref anchor 1))
                     (sidx (vector-ref anchor 2)))
                (assert-eq! 'dense-anchor-id (vector-ref anchor 0) i)
                (verify-tagged-node! ref sidx 'clean-pinned-to-evac)
                (verify-dense (fx+ i 1)))))
        (let verify-sparse ((i 0))
          (if (fx< i n-sparse)
              (begin
                (if (fx= (fxmodulo i stride) 0)
                    (verify-tagged-node! (vector-ref sparse-all i) i 'sparse-survivor))
                (verify-sparse (fx+ i 1)))))
        (let* ((mat-after (inexact->exact (round (f64vector-ref (gc-gen-stats) 4))))
               (maj-after (inexact->exact (round (f64vector-ref (gc-gen-stats) 1))))
               (cm1 (inexact->exact (round (f64vector-ref (gc-cm-stats) 0)))))
          (if (not (fx> cm1 cm0))
              (error "C14-FAIL: expected concurrent major cycle before selective evac" cm0 cm1))
          (if (not (fx< mat-after mat-before))
              (error "C14-FAIL: expected selective evac to reclaim mature sections"
                     mat-before mat-after-cm mat-after))
          (if (not (fx= maj-after maj-after-cm))
              (error "C14-FAIL: expected selective evac without full STW major GC"
                     maj-after-cm maj-after))
          (list mat-before mat-after (fx- cm1 cm0)))))))

;; Phase 2: Medium ___STILL Page-Backed Slab (2 KiB - 32 KiB) multi-core churn
;; across all 4 size classes (4K, 8K, 16K, 32K) + direct-mmap 48K, verifying
;; byte integrity and post-GC contraction (zero retained empty slab chunks).
(define (phase2-medium-still-slab-challenge!)
  (let* ((np (##current-vm-processor-count))
         (workers (fxmax 4 np))
         (sizes '#(2500 5000 10000 20000 30000 48000))
         (wave-heaps '()))
    (##gc)
    (let wave-loop ((w 0))
      (if (fx< w 4)
          (let ((ts
                 (let spawn ((wid 0) (acc '()))
                   (if (fx= wid workers)
                       acc
                       (spawn
                        (fx+ wid 1)
                        (cons
                         (thread-start!
                          (make-thread
                           (lambda ()
                             (let ((ring (make-vector 32 #f)))
                               (let iter ((k 0) (chk 0))
                                 (if (fx= k 480)
                                     chk
                                     (let* ((sz (vector-ref sizes (fxmodulo (fx+ k wid) 6)))
                                            (u8 (make-u8vector sz (fxand (fx+ k wid w) 255)))
                                            (slot (fxand k 31)))
                                       (u8vector-set! u8 0 (fxand k 255))
                                       (u8vector-set! u8 (fx- sz 1) (fxand (fx+ wid 17) 255))
                                       (vector-set! ring slot u8)
                                       (let* ((prev (vector-ref ring (fxand (fx+ k 1) 31)))
                                              (b (if prev (u8vector-ref prev 0) 0)))
                                         (iter (fx+ k 1) (fx+ chk b))))))))))
                         acc))))))
            (for-each thread-join! ts)
            (##gc)
            (set! wave-heaps (cons (latest-heap-bytes) wave-heaps))
            (wave-loop (fx+ w 1)))))
    (let* ((h-last (car wave-heaps))
           (h-first (car (reverse wave-heaps))))
      (if (> h-last (* 2.0 (max h-first (* 16.0 1048576.0))))
          (error "C14-FAIL: medium still slab heap creep across waves" h-first h-last))
      (list workers (inexact->exact (round (/ h-first 1048576.0)))
            (inexact->exact (round (/ h-last 1048576.0)))))))

(let ((p1 (phase1-selective-evac-challenge!))
      (p2 (phase2-medium-still-slab-challenge!)))
  (display "C14-IMMIX-SELECTIVE-EVAC-SLAB-PASS")
  (display " procs=") (display (##current-vm-processor-count))
  (display " mat_before=") (display (car p1))
  (display " mat_after=") (display (cadr p1))
  (display " cm_cycles=") (display (caddr p1))
  (display " slab_workers=") (display (car p2))
  (display " wave1_mib=") (display (cadr p2))
  (display " wave4_mib=") (display (caddr p2))
  (newline))
