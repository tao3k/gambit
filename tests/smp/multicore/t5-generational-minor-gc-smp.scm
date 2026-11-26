;;; Adversarial SMP PBT for Tier 3.1 Phase 2 — Bounded Generational Minor GC:
;;; 1. Write-barrier completeness across ALL heap container types (pairs,
;;;    vectors, vector-cas!, boxes, structures, closures, subvector-move!,
;;;    multi-card movable vectors, still vectors, and gc-hash-tables) across
;;;    many automatic Minor GCs without manual (##gc).
;;; 2. Per-processor card hint-log overflow fallback (> 64 distinct dirty cards
;;;    in one epoch) verifying overflow_fallbacks > 0 and zero lost edges.
;;; 3. Wills (young & mature testators) and weak tables across interleaved
;;;    Minor GCs and explicit Major (##gc).
;;; 4. Multi-shot call/cc mature continuations & parameterize across Minor GCs.
;;; 5. Concurrent multicore write-barrier + promotion + CAS torture.

(declare (standard-bindings) (extended-bindings) (block))

(c-declare "#include \"gambit.h\"")

(define gc-gen-stats
  (c-lambda () scheme-object
    "___SCMOBJ v = ___EXT(___alloc_scmobj)(___PSTATE, ___sF64VECTOR, 8 * sizeof(double));
     if (!___FIXNUMP(v)) {
       double *p = ___CAST(double*, ___BODY_AS(v, ___tSUBTYPED));
       ___EXT(___gc_generational_stats)(___PSTATE, p);
       ___EXT(___release_scmobj)(v);
     }
     ___return(v);"))

(define (assert-true ok label . info)
  (if (not ok)
      (apply error (string-append "T5-FAIL: " label) info)))

(define (proc-count) (##current-vm-processor-count))

(define (stat-minor s) (inexact->exact (round (f64vector-ref s 0))))
(define (stat-major s) (inexact->exact (round (f64vector-ref s 1))))
(define (stat-mature-secs s) (inexact->exact (round (f64vector-ref s 4))))
(define (stat-dirty-cards s) (inexact->exact (round (f64vector-ref s 6))))
(define (stat-overflows s) (inexact->exact (round (f64vector-ref s 7))))

(define-type gen-node
  id: 8b23c6c0-5a7f-4a40-9b34-1c5e9d33e101
  a b c)

(define (make-young-payload tag)
  (let ((s (string-append "y-" (number->string tag))))
    (cons (vector tag (+ tag 1) s)
          (box (list tag (* tag 3) s)))))

(define (check-payload p tag label)
  (assert-true (pair? p) label 'not-pair tag)
  (let ((v (car p))
        (bx (cdr p)))
    (assert-true (vector? v) label 'not-vec tag)
    (assert-true (box? bx) label 'not-box tag)
    (assert-true (= (vector-ref v 0) tag) label 'v0 tag (vector-ref v 0))
    (assert-true (= (vector-ref v 1) (+ tag 1)) label 'v1 tag (vector-ref v 1))
    (let ((xs (unbox bx)))
      (assert-true (and (pair? xs) (= (car xs) tag) (= (cadr xs) (* tag 3)))
                   label 'box-list tag xs)
      (assert-true (string=? (vector-ref v 2) (caddr xs))
                   label 'str-eq tag))))

(define (churn-young! rounds)
  ;; Allocate transient young garbage to trigger automatic Minor GCs.
  (let loop ((i 0) (acc 0))
    (if (= i rounds)
        acc
        (let ((v (make-vector 128 i))
              (p (cons i (cons (+ i 1) (+ i 2)))))
          (loop (+ i 1) (+ acc (vector-ref v 0) (car p)))))))

;; ---------------------------------------------------------------------------
;; Scenario 1: All container types + subvector-move! + still vector across Minor GCs
;; ---------------------------------------------------------------------------
(define (test-all-container-barriers)
  ;; Build a multi-section mature base (~4 MiB) so mature_sections_ is rich.
  (let* ((anchor (make-vector 2048 #f))
         (m-pair (cons 'init-car 'init-cdr))
         (m-vec (make-vector 32 #f))
         (m-cas-vec (make-vector 8 #f))
         (m-box (box #f))
         (m-struct (make-gen-node #f #f #f))
         (m-big-movable (make-vector 4000 #f)) ;; spans > 60 cards in movable mature
         (m-still-vec (make-vector 65536 #f))  ;; allocated as ___STILL (> MSECTION)
         (m-table (make-table test: eq?))
         (m-clo-val #f)
         (m-clo-set! (lambda (v) (set! m-clo-val v)))
         (m-clo-get  (lambda () m-clo-val)))
    (let init ((i 0))
      (if (< i 2048)
          (begin
            (vector-set! anchor i (make-vector 250 i))
            (init (+ i 1)))))
    ;; Promote all containers to MATURE via one Major GC.
    (##gc)
    (let* ((s0 (gc-gen-stats))
           (m0 (stat-minor s0)))
      (assert-true (> (stat-mature-secs s0) 0) "mature-sections-established" (stat-mature-secs s0))
      ;; Run waves: mutate every mature container with fresh young payloads,
      ;; churn young garbage to force automatic Minor GCs, and verify integrity.
      (let wave ((w 1))
        (if (<= w 12)
            (let ((base (* w 1000)))
              (set-car! m-pair (make-young-payload (+ base 1)))
              (set-cdr! m-pair (make-young-payload (+ base 2)))
              (vector-set! m-vec 0 (make-young-payload (+ base 3)))
              (vector-set! m-vec 31 (make-young-payload (+ base 4)))
              (let ((old (vector-ref m-cas-vec 3)))
                (assert-true
                 (eq? (##vector-cas! m-cas-vec 3 (make-young-payload (+ base 5)) old) old)
                 "vector-cas-write"))
              (set-box! m-box (make-young-payload (+ base 6)))
              (gen-node-a-set! m-struct (make-young-payload (+ base 7)))
              (gen-node-b-set! m-struct (make-young-payload (+ base 8)))
              (gen-node-c-set! m-struct (make-young-payload (+ base 9)))
              (m-clo-set! (make-young-payload (+ base 10)))
              ;; Sparse mutations across distinct cards of multi-card mature movable vector
              (vector-set! m-big-movable 17 (make-young-payload (+ base 11)))
              (vector-set! m-big-movable 1999 (make-young-payload (+ base 12)))
              (vector-set! m-big-movable 3980 (make-young-payload (+ base 13)))
              ;; Bulk subvector-move! across card boundary into m-big-movable
              (let ((src (make-vector 140 #f)))
                (let fill ((j 0))
                  (if (< j 140)
                      (begin
                        (vector-set! src j (make-young-payload (+ base 200 j)))
                        (fill (+ j 1)))))
                (subvector-move! src 0 140 m-big-movable 500))
              ;; Still vector mutation
              (vector-set! m-still-vec 12345 (make-young-payload (+ base 14)))
              (vector-set! m-still-vec 60000 (make-young-payload (+ base 15)))
              ;; Mature eq? hash table mutation with young key & young value
              (let ((yk (cons 'key (+ base 16)))
                    (yv (make-young-payload (+ base 17))))
                (table-set! m-table yk yv)
                ;; Trigger at least one automatic GC per wave regardless of host
                ;; CPU L3-cache-derived default min_heap (stopping if either a
                ;; Minor GC or a tight-max_heap Major fallback fires).
                (let* ((sw0 (gc-gen-stats))
                       (g0 (+ (stat-minor sw0) (stat-major sw0))))
                  (let churn-wave ((tries 0))
                    (let ((sw (gc-gen-stats)))
                      (if (and (< tries 40)
                               (= (+ (stat-minor sw) (stat-major sw)) g0))
                          (begin
                            (churn-young! 12000)
                            (churn-wave (+ tries 1)))))))
                ;; Verify EVERY single young reference survived intact
                (check-payload (car m-pair) (+ base 1) "pair-car")
                (check-payload (cdr m-pair) (+ base 2) "pair-cdr")
                (check-payload (vector-ref m-vec 0) (+ base 3) "vec-0")
                (check-payload (vector-ref m-vec 31) (+ base 4) "vec-31")
                (check-payload (vector-ref m-cas-vec 3) (+ base 5) "vec-cas")
                (check-payload (unbox m-box) (+ base 6) "box")
                (check-payload (gen-node-a m-struct) (+ base 7) "struct-a")
                (check-payload (gen-node-b m-struct) (+ base 8) "struct-b")
                (check-payload (gen-node-c m-struct) (+ base 9) "struct-c")
                (check-payload (m-clo-get) (+ base 10) "closure")
                (check-payload (vector-ref m-big-movable 17) (+ base 11) "big-17")
                (check-payload (vector-ref m-big-movable 1999) (+ base 12) "big-1999")
                (check-payload (vector-ref m-big-movable 3980) (+ base 13) "big-3980")
                (check-payload (vector-ref m-big-movable 500) (+ base 200) "subvec-0")
                (check-payload (vector-ref m-big-movable 564) (+ base 264) "subvec-64")
                (check-payload (vector-ref m-big-movable 639) (+ base 339) "subvec-139")
                (check-payload (vector-ref m-still-vec 12345) (+ base 14) "still-12345")
                (check-payload (vector-ref m-still-vec 60000) (+ base 15) "still-60000")
                (check-payload (table-ref m-table yk #f) (+ base 17) "table-val"))
              (wave (+ w 1)))))
      ;; Ensure anchor wasn't optimized away and verify Minor GCs actually fired
      (assert-true (= (vector-ref (vector-ref anchor 2047) 0) 2047) "anchor-live")
      (let* ((s1 (gc-gen-stats))
             (d-minor (- (stat-minor s1) m0))
             (d-cards (- (stat-dirty-cards s1) (stat-dirty-cards s0))))
        (assert-true (>= d-minor 4) "minor-gcs-triggered" d-minor (stat-major s1))
        (assert-true (> d-cards 0) "dirty-cards-scanned" d-cards)
        (list d-minor d-cards)))))

;; ---------------------------------------------------------------------------
;; Scenario 2: Card hint-log overflow fallback (> 64 distinct cards in 1 epoch)
;; ---------------------------------------------------------------------------
(define (test-hint-log-overflow)
  ;; 256 vectors of 64 elements = 16384 words (~256 distinct cards in mature)
  (let ((arr (make-vector 256 #f)))
    (let init ((i 0))
      (if (< i 256)
          (begin
            (vector-set! arr i (make-vector 64 i))
            (init (+ i 1)))))
    (##gc)
    (let* ((s0 (gc-gen-stats))
           (ov0 (stat-overflows s0))
           (m0 (stat-minor s0)))
      ;; Dirty > 128 distinct mature cards inside ONE mutator epoch (pre-GC)
      (let dirty ((i 0))
        (if (< i 256)
            (begin
              (vector-set! (vector-ref arr i) 5 (cons 'ov-tag (+ 70000 i)))
              (dirty (+ i 1)))))
      ;; Force Minor GC via young allocation churn
      (let churn-until ((tries 0))
        (if (and (< tries 20) (= (stat-minor (gc-gen-stats)) m0))
            (begin
              (churn-young! 10000)
              (churn-until (+ tries 1)))))
      ;; Verify EVERY SINGLE one of the 256 young pairs survived the overflow scan
      (let chk ((i 0))
        (if (< i 256)
            (let ((p (vector-ref (vector-ref arr i) 5)))
              (assert-true (and (pair? p)
                                (eq? (car p) 'ov-tag)
                                (= (cdr p) (+ 70000 i)))
                           "overflow-entry-intact" i p)
              (chk (+ i 1)))))
      (let* ((s1 (gc-gen-stats))
             (d-ov (- (stat-overflows s1) ov0)))
        (assert-true (> d-ov 0) "hint-log-overflow-exercised" d-ov)
        d-ov))))

;; ---------------------------------------------------------------------------
;; Scenario 3: Wills & Weak tables across Minor and Major GC
;; ---------------------------------------------------------------------------
(define (test-wills-and-weak-tables)
  (let* ((live-mature-key (cons 'mature-live 1))
         (dead-mature-holder (box (cons 'mature-dead 2)))
         (fired-live-mature 0)
         (fired-dead-mature 0)
         (fired-dead-young 0)
         (wt (make-table test: eq? weak-keys: #t))
         (w1 (make-will live-mature-key (lambda (o) (set! fired-live-mature (+ fired-live-mature 1)))))
         (w2 (make-will (unbox dead-mature-holder) (lambda (o) (set! fired-dead-mature (+ fired-dead-mature 1))))))
    (table-set! wt live-mature-key 'keep-me)
    (table-set! wt (unbox dead-mature-holder) 'drop-on-major)
    ;; Promote everything to mature
    (##gc)
    ;; Drop strong ref to dead-mature-holder's object, create dead young testator & weak key
    (set-box! dead-mature-holder #f)
    (let ((w3 (make-will (cons 'young-dead 3)
                         (lambda (o) (set! fired-dead-young (+ fired-dead-young 1)))))
          (live-young-key (cons 'young-live 4)))
      (table-set! wt (cons 'weak-young-dead 5) 'drop-on-minor)
      (table-set! wt live-young-key 'keep-young)
      ;; Trigger Minor GCs via young churn
      (let ((m0 (stat-minor (gc-gen-stats))))
        (let churn-until ((tries 0))
          (if (and (< tries 20) (< (- (stat-minor (gc-gen-stats)) m0) 2))
              (begin
                (churn-young! 12000)
                (churn-until (+ tries 1))))))
      (thread-yield!)
      (assert-true (= fired-live-mature 0) "live-mature-will-not-fired" fired-live-mature)
      (assert-true (eq? (table-ref wt live-mature-key #f) 'keep-me) "weak-table-live-mature")
      (assert-true (eq? (table-ref wt live-young-key #f) 'keep-young) "weak-table-live-young")
      ;; Explicit Major GC must reclaim dead mature testator and fire w2
      (##gc)
      (let drain ((k 0))
        (if (and (< k 40) (or (< fired-dead-mature 1) (< fired-dead-young 1)))
            (begin (thread-sleep! 0.005) (drain (+ k 1)))))
      (assert-true (= fired-live-mature 0) "live-mature-still-alive" fired-live-mature)
      (assert-true (= fired-dead-mature 1) "dead-mature-will-fired-on-major" fired-dead-mature)
      (assert-true (= fired-dead-young 1) "dead-young-will-fired" fired-dead-young)
      (assert-true (eq? (table-ref wt live-mature-key #f) 'keep-me) "weak-table-post-major")
      ;; Keep w1, w2, w3 live until check finishes
      (list (will? w1) (will? w2) (will? w3) fired-dead-mature fired-dead-young))))

;; ---------------------------------------------------------------------------
;; Scenario 4: Multi-shot call/cc mature continuations across Minor GCs
;; ---------------------------------------------------------------------------
(define (test-mature-continuations)
  (let* ((saved-k #f)
         (p (make-parameter 'init))
         (results '()))
    (let ((val
           (parameterize ((p (cons 'denv-tag 42)))
             (call/cc
              (lambda (k)
                (set! saved-k k)
                'first)))))
      (set! results (cons (cons val (p)) results)))
    ;; Promote saved-k and its captured frames to MATURE
    (##gc)
    ;; Churn young memory to trigger Minor GCs while saved-k is mature
    (churn-young! 25000)
    ;; Re-invoke mature continuation with fresh young arguments across Minor GCs
    (if (= (length results) 1)
        (saved-k (make-young-payload 9001)))
    (if (= (length results) 2)
        (begin
          (churn-young! 20000)
          (saved-k (make-young-payload 9002))))
    (assert-true (= (length results) 3) "multishot-invocations" (length results))
    (check-payload (caar results) 9002 "multishot-2")
    (check-payload (caadr results) 9001 "multishot-1")
    (assert-true (eq? (caaddr results) 'first) "multishot-0")
    (length results)))

;; ---------------------------------------------------------------------------
;; Scenario 5: Multicore concurrent write-barrier & Minor GC torture
;; ---------------------------------------------------------------------------
(define (test-multicore-wb-torture)
  (let* ((np (proc-count))
         (nw (max 4 (* 2 np)))
         (shared (make-vector (* nw 64) #f))
         (cas-slots (make-vector nw (cons 'init 0))))
    ;; Promote shared arrays to MATURE
    (##gc)
    (let* ((s0 (gc-gen-stats))
           (m0 (stat-minor s0))
           (threads
            (let spawn ((w 0) (acc '()))
              (if (= w nw)
                  acc
                  (spawn
                   (+ w 1)
                   (cons
                    (thread-start!
                     (make-thread
                      (lambda ()
                        (let ((my-mature (make-vector 32 #f))
                              (base (* w 64)))
                          (let round ((r 0))
                            (if (< r 40)
                                (begin
                                  ;; Write fresh young objects into both shared mature
                                  ;; and per-thread slots (across cards)
                                  (let fill ((j 0))
                                    (if (< j 64)
                                        (let ((tag (+ (* w 100000) (* r 1000) j)))
                                          (vector-set! shared (+ base j)
                                                       (make-young-payload tag))
                                          (fill (+ j 1)))))
                                  ;; Concurrent CAS into mature cas-slots
                                  (let ((old (vector-ref cas-slots w))
                                        (nxt (make-young-payload (+ (* w 100000) r))))
                                    (assert-true (eq? (##vector-cas! cas-slots w nxt old) old)
                                                 "mc-cas-slot" w r))
                                  (vector-set! my-mature (modulo r 32)
                                               (make-young-payload (+ (* w 50000) r)))
                                  ;; Young garbage churn
                                  (churn-young! 1200)
                                  ;; Occasional Major GC from worker 0
                                  (if (and (= w 0) (= (modulo r 15) 7))
                                      (##gc))
                                  ;; Verify our slice of shared mature vector & CAS slot
                                  (check-payload (vector-ref shared (+ base 0))
                                                 (+ (* w 100000) (* r 1000) 0) "mc-shared-0")
                                  (check-payload (vector-ref shared (+ base 63))
                                                 (+ (* w 100000) (* r 1000) 63) "mc-shared-63")
                                  (check-payload (vector-ref cas-slots w)
                                                 (+ (* w 100000) r) "mc-cas-verify")
                                  (check-payload (vector-ref my-mature (modulo r 32))
                                                 (+ (* w 50000) r) "mc-local-verify")
                                  (round (+ r 1)))))
                          'ok))))
                    acc))))))
      (for-each
       (lambda (th)
         (assert-true (eq? (thread-join! th 60 'timeout) 'ok) "mc-worker-ok"))
       threads)
      (let ((s1 (gc-gen-stats)))
        (list nw (- (stat-minor s1) m0))))))

(define r1 (test-all-container-barriers))
(define r2 (test-hint-log-overflow))
(define r3 (test-wills-and-weak-tables))
(define r4 (test-mature-continuations))
(define r5 (test-multicore-wb-torture))
(define sf (gc-gen-stats))

(write
 (list 'T5-GENERATIONAL-MINOR-GC-PASS
       'procs (proc-count)
       's1-minor (car r1)
       's1-dirty-cards (cadr r1)
       's2-overflows r2
       's3-wills (cdddr r3)
       's4-multishot r4
       's5-workers (car r5)
       's5-minor (cadr r5)
       'total-minor (stat-minor sf)
       'total-major (stat-major sf)))
(newline)
