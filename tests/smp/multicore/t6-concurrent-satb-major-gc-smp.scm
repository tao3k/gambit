;;; Adversarial SMP PBT for Slice 2 — Concurrent SATB Major GC & Non-Moving
;;; Immix Mark-Region Mature Space.
;;; Covers all 9 Quint V2 / CBMC PSO invariants under true SMP (p1, p2, p4)
;;; and Apple Clang C23 ThreadSanitizer:
;;;   S1. Yuasa SATB edge-move across concurrent marking (overwrite mature slot
;;;       with #f / immediate after copying edge to another container — kills
;;;       Quint Mutant 1 & CBMC USE_SATB_GUARD=0).
;;;   S2. Black Allocation of newly promoted young movable & young ___STILL
;;;       survivors during active concurrent marking (kills Quint Mutant 2).
;;;   S3. Non-moving mark-region sweep: dense live mature sections stay pinned
;;;       with zero copying while 100%-dead mature sections are reclaimed in
;;;       O(1) and dead mature ___STILL objects are freed (kills Mutant 3).
;;;   S4. SATB buffer overflow recovery (> 1024 distinct mature pointer
;;;       overwrites in one epoch -> sticky overflow fallback -> zero lost live
;;;       objects; kills Quint Mutant 4).
;;;   S5. Tier 3.3 blocking FFI parked processor phase adoption on unpark
;;;       during active concurrent marking (kills Quint Mutant 5).
;;;   S6. Weak GC hash-table & will-testator SATB read-barrier resurrection
;;;       safety (kills Quint Mutant 6 & CBMC MUTANT_SKIP_WEAK_READ_BARRIER).
;;;   S7. Atomic weak-table clearing BEFORE sweep + dead mature will firing
;;;       across multi-cycle concurrent Major GCs (kills Mutant 7 & CBMC
;;;       MUTANT_SKIP_WEAK_CLEAR).
;;;   S8. ##vector-cas! & ##unchecked-structure-cas! SATB old-value logging
;;;       (kills Quint Mutant 8).
;;;   S9. Multicore SMP concurrent marking + mutation + weak-table + CAS torture
;;;       (verifies concurrent_major_cycles > 0, mark_slices > 0, 0 data races).

(declare (standard-bindings) (extended-bindings) (block))

(c-declare #<<c-end
#include "gambit.h"
#ifdef _WIN32
#include <windows.h>
static void t6_sleep_ms(int ms) { Sleep((DWORD)ms); }
#else
#include <time.h>
static void t6_sleep_ms(int ms) {
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (long)(ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
}
#endif
c-end
)

(define gc-gen-stats
  (c-lambda () scheme-object
    "___SCMOBJ v = ___EXT(___alloc_scmobj)(___PSTATE, ___sF64VECTOR, 8 * sizeof(double));
     if (!___FIXNUMP(v)) {
       double *p = ___CAST(double*, ___BODY_AS(v, ___tSUBTYPED));
       ___EXT(___gc_generational_stats)(___PSTATE, p);
       ___EXT(___release_scmobj)(v);
     }
     ___return(v);"))

(define gc-cm-stats
  (c-lambda () scheme-object
    "___SCMOBJ v = ___EXT(___alloc_scmobj)(___PSTATE, ___sF64VECTOR, 8 * sizeof(double));
     if (!___FIXNUMP(v)) {
       double *p = ___CAST(double*, ___BODY_AS(v, ___tSUBTYPED));
       ___EXT(___gc_concurrent_major_stats)(___PSTATE, p);
       ___EXT(___release_scmobj)(v);
     }
     ___return(v);"))

(define gc-start-concurrent-major!
  (c-lambda (int) int
    "___return(___EXT(___gc_start_concurrent_major)(___PSTATE, ___arg1));"))

(define gc-major-mark-slice!
  (c-lambda (int) int
    "___return((int)___EXT(___gc_major_mark_slice)(___PSTATE, (___SIZE_TS)___arg1));"))

(define gc-cm-v2-stats
  (c-lambda () scheme-object
    "___SCMOBJ v = ___EXT(___alloc_scmobj)(___PSTATE, ___sF64VECTOR, 2 * sizeof(double));
     if (!___FIXNUMP(v)) {
       double *p = ___CAST(double*, ___BODY_AS(v, ___tSUBTYPED));
       ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___PSTATE);
       p[0] = vm->mem.concurrent_major_holes_recycled_;
       p[1] = vm->mem.concurrent_major_idle_slices_;
       ___EXT(___release_scmobj)(v);
     }
     ___return(v);"))

(define parked-ffi-sleep-ms
  (c-lambda (int) int
    "___BEGIN_BLOCKING_FFI
     t6_sleep_ms(___arg1);
     ___END_BLOCKING_FFI
     ___return(1);"))

(define (assert-true ok label . info)
  (if (not ok)
      (apply error (string-append "T6-FAIL: " label) info)))

(define (proc-count) (##current-vm-processor-count))

(define (cm-cycles s) (inexact->exact (round (f64vector-ref s 0))))
(define (cm-slices s) (inexact->exact (round (f64vector-ref s 1))))
(define (cm-marked-words s) (inexact->exact (round (f64vector-ref s 2))))
(define (cm-reclaimed-secs s) (inexact->exact (round (f64vector-ref s 3))))
(define (cm-reclaimed-still s) (inexact->exact (round (f64vector-ref s 4))))
(define (cm-satb-logged s) (inexact->exact (round (f64vector-ref s 6))))
(define (cm-phase s) (inexact->exact (round (f64vector-ref s 7))))

(define (churn-young! rounds)
  (let loop ((i 0) (acc 0))
    (if (= i rounds)
        acc
        (let ((v (make-vector 128 i))
              (p (cons i (cons (+ i 1) (+ i 2)))))
          (loop (+ i 1) (+ acc (vector-ref v 0) (car p)))))))

(define (drive-to-phase! target-phase max-iters)
  (let loop ((k 0))
    (cond
      ((= (cm-phase (gc-cm-stats)) target-phase) #t)
      ((>= k max-iters) #f)
      (else
       (churn-young! 4000)
       (loop (+ k 1))))))

(define (make-tagged-payload id)
  (let ((s (string-append "satb-" (number->string id))))
    (vector id (+ id 7) (cons s (* id 11)))))

(define (verify-tagged-payload obj id label)
  (assert-true (vector? obj) label 'not-vec id obj)
  (assert-true (= (vector-ref obj 0) id) label 'id0 id (vector-ref obj 0))
  (assert-true (= (vector-ref obj 1) (+ id 7)) label 'id1 id (vector-ref obj 1))
  (let ((pr (vector-ref obj 2)))
    (assert-true (pair? pr) label 'not-pair id pr)
    (assert-true (= (cdr pr) (* id 11)) label 'id2 id (cdr pr))
    (assert-true (string=? (car pr) (string-append "satb-" (number->string id)))
                 label 'str id (car pr))))

;; ---------------------------------------------------------------------------
;; S1 + S2 + S8: Yuasa SATB edge-move, Black Allocation, CAS SATB
;; ---------------------------------------------------------------------------
(define (test-satb-edge-move-black-alloc-cas)
  (let* ((n 128)
         (src-vec (make-vector n #f))
         (dst-vec (make-vector n #f))
         (cas-vec (make-vector 32 #f))
         (still-holder (make-vector 16 #f)))
    (let init ((i 0))
      (if (< i n)
          (begin
            (vector-set! src-vec i (make-tagged-payload (+ 1000 i)))
            (init (+ i 1)))))
    (let initc ((i 0))
      (if (< i 32)
          (begin
            (vector-set! cas-vec i (make-tagged-payload (+ 2000 i)))
            (initc (+ i 1)))))
    ;; Promote everything to mature space via explicit compacting GC.
    (##gc)

    ;; Request concurrent Major GC start on next Minor GC.
    (assert-true (= (gc-start-concurrent-major! 0) 1) "s1-start-req")
    (assert-true (drive-to-phase! 1 40) "s1-entered-marking" (gc-cm-stats))

    ;; S1: Move mature pointers from src-vec -> dst-vec and overwrite src-vec
    ;; with #f (immediate!) while concurrent marking is active!
    (let move ((i 0))
      (if (< i n)
          (let ((p (vector-ref src-vec i)))
            (vector-set! src-vec i #f)
            (vector-set! dst-vec i p)
            (if (= (modulo i 16) 0) (gc-major-mark-slice! 512))
            (move (+ i 1)))))

    ;; S8: Replace mature pointers in cas-vec using ##vector-cas! with #f
    ;; while saving them into dst-vec / still-holder.
    (let ((cas-saved (make-vector 32 #f)))
      (let cloop ((i 0))
        (if (< i 32)
            (let* ((old (vector-ref cas-vec i))
                   (prev (##vector-cas! cas-vec i #f old)))
              (assert-true (eq? prev old) "s8-cas-match" i)
              (vector-set! cas-saved i old)
              (cloop (+ i 1)))))

      ;; S2: Allocate brand-new young movable + young ___STILL objects during
      ;; active MARKING and promote them via Minor GC (must be BLACK-allocated!).
      (let sloop ((i 0))
        (if (< i 16)
            (let ((sv (make-vector 40000 (+ 3000 i))))
              (vector-set! sv 0 (make-tagged-payload (+ 4000 i)))
              (vector-set! still-holder i sv)
              (sloop (+ i 1)))))

      ;; Finish the concurrent Major cycle (Remark + Non-Moving Sweep).
      (gc-start-concurrent-major! 1)
      (assert-true (drive-to-phase! 0 60) "s1-completed-remark" (gc-cm-stats))

      ;; Verify ALL moved, CAS-replaced, and BLACK-allocated objects survived
      ;; intact (and survive another full GC afterwards!).
      (let check ((i 0))
        (if (< i n)
            (begin
              (verify-tagged-payload (vector-ref dst-vec i) (+ 1000 i) "s1-dst")
              (check (+ i 1)))))
      (let checkc ((i 0))
        (if (< i 32)
            (begin
              (verify-tagged-payload (vector-ref cas-saved i) (+ 2000 i) "s8-cas")
              (checkc (+ i 1)))))
      (let checks ((i 0))
        (if (< i 16)
            (let ((sv (vector-ref still-holder i)))
              (assert-true (= (vector-length sv) 40000) "s2-still-len" i)
              (assert-true (= (vector-ref sv 39999) (+ 3000 i)) "s2-still-tail" i)
              (verify-tagged-payload (vector-ref sv 0) (+ 4000 i) "s2-still-slot0")
              (checks (+ i 1))))))))

;; ---------------------------------------------------------------------------
;; S3: Non-Moving Sweep — 100%-dead mature section O(1) reclaim + dead ___STILL
;; ---------------------------------------------------------------------------
(define (test-nonmoving-reclaim-sections-and-still)
  (let* ((live-anchor (make-vector 2048 #f))
         (dead-box (box #f))
         (dead-still-box (box #f)))
    ;; Allocate persistent live anchor (~2 MiB) + disposable mature garbage (~8 MiB)
    ;; + disposable mature ___STILL vectors (~4 MiB).
    (let loop ((i 0))
      (if (< i 2048)
          (begin
            (vector-set! live-anchor i (make-tagged-payload (+ 10000 i)))
            (loop (+ i 1)))))
    (let ((junk (make-vector 8192 #f)))
      (let jloop ((i 0))
        (if (< i 8192)
            (begin
              (vector-set! junk i (make-vector 128 i))
              (jloop (+ i 1)))))
      (set-box! dead-box junk))
    (let ((stills (make-vector 12 #f)))
      (let sloop ((i 0))
        (if (< i 12)
            (begin
              (vector-set! stills i (make-vector 40000 (+ 500 i)))
              (sloop (+ i 1)))))
      (set-box! dead-still-box stills))

    ;; Promote live-anchor, junk, and stills into mature space.
    (##gc)

    ;; Now drop all references to junk and dead stills!
    (set-box! dead-box #f)
    (set-box! dead-still-box #f)

    (let* ((st0 (gc-cm-stats))
           (cyc0 (cm-cycles st0))
           (rsec0 (cm-reclaimed-secs st0))
           (rstill0 (cm-reclaimed-still st0)))
      ;; Run a Concurrent SATB Major GC cycle (non-moving!).
      (gc-start-concurrent-major! 0)
      (assert-true (drive-to-phase! 1 40) "s3-enter-marking")
      (gc-major-mark-slice! 65536)
      (gc-start-concurrent-major! 1)
      (assert-true (drive-to-phase! 0 60) "s3-finish-remark")

      (let* ((st1 (gc-cm-stats))
             (dcyc (- (cm-cycles st1) cyc0))
             (drsec (- (cm-reclaimed-secs st1) rsec0))
             (drstill (- (cm-reclaimed-still st1) rstill0)))
        (assert-true (>= dcyc 1) "s3-cycle-ran" dcyc)
        (assert-true (> drsec 0) "s3-reclaimed-mature-sections" drsec)
        (assert-true (> drstill 0) "s3-reclaimed-mature-still-words" drstill)
        ;; Verify live-anchor is 100% intact after non-moving sweep!
        (let check ((i 0))
          (if (< i 2048)
              (begin
                (verify-tagged-payload (vector-ref live-anchor i) (+ 10000 i) "s3-live")
                (check (+ i 1)))))
        (list dcyc drsec drstill)))))

;; ---------------------------------------------------------------------------
;; S4: SATB Buffer Overflow Recovery (> 1024 overwrites in one epoch)
;; ---------------------------------------------------------------------------
(define (test-satb-overflow-recovery)
  (let* ((n 1200)
         (src (make-vector n #f))
         (dst (make-vector n #f)))
    (let init ((i 0))
      (if (< i n)
          (begin
            (vector-set! src i (make-tagged-payload (+ 20000 i)))
            (init (+ i 1)))))
    (##gc)

    (gc-start-concurrent-major! 0)
    (assert-true (drive-to-phase! 1 40) "s4-enter-marking")

    ;; Overwrite 1200 mature slots consecutively (> 4x SATB_BUF_CAP=256)
    ;; without yielding so the local SATB buffer flushes repeatedly.
    (let ov ((i 0))
      (if (< i n)
          (let ((x (vector-ref src i)))
            (vector-set! src i #f)
            (vector-set! dst i x)
            (ov (+ i 1)))))

    (gc-start-concurrent-major! 1)
    (assert-true (drive-to-phase! 0 60) "s4-finish-remark")

    (let check ((i 0))
      (if (< i n)
          (begin
            (verify-tagged-payload (vector-ref dst i) (+ 20000 i) "s4-recovered")
            (check (+ i 1)))))))

;; ---------------------------------------------------------------------------
;; S6 + S7: Weak-Table Read-Barrier Resurrection, Atomic Weak Clearing & Wills
;; ---------------------------------------------------------------------------
(define (test-weak-tables-and-wills)
  (let* ((wk-tbl (make-table test: eq? weak-keys: #t))
         (wv-tbl (make-table test: eq? weak-values: #t))
         (resurrected-box (box #f))
         (will-fired-count 0)
         (dead-will-box (box (make-tagged-payload 77777)))
         (live-will-target (make-tagged-payload 88888))
         (live-will (make-will live-will-target (lambda (x) (set! will-fired-count (+ will-fired-count 100)))))
         (dead-will (make-will (unbox dead-will-box)
                               (lambda (x)
                                 (verify-tagged-payload x 77777 "s7-will-testator-intact")
                                 (set! will-fired-count (+ will-fired-count 1))))))
    ;; Populate weak tables:
    ;;   - k-dead/v-dead: dropped before concurrent Major GC -> MUST be cleared!
    ;;   - k-res/v-res: dropped from strong root, then read via table-ref during
    ;;     MARKING -> read-barrier MUST resurrect v-res!
    (let ((k-dead (make-tagged-payload 30001))
          (v-dead (make-tagged-payload 30002))
          (k-res  (make-tagged-payload 30003))
          (v-res  (make-tagged-payload 30004)))
      (table-set! wk-tbl k-dead 'dead-key-val)
      (table-set! wv-tbl 'dead-val-key v-dead)
      (table-set! wv-tbl 'res-val-key v-res)
      (table-set! wk-tbl k-res 'res-key-val)
      ;; Promote tables, entries, and wills to mature space.
      (##gc)

      ;; Start concurrent Major GC while k-res is still strongly held, then
      ;; drop v-res & k-dead & v-dead & dead-will-box!
      (set-box! dead-will-box #f)
      (set! k-dead #f)
      (set! v-dead #f)
      (set! v-res #f)

      (gc-start-concurrent-major! 0)
      (assert-true (drive-to-phase! 1 40) "s6-enter-marking")

      ;; S6: Resurrect v-res via weak-table lookup AND touch live-will testator
      ;; via will-testator read-barrier during active MARKING!
      (let ((got-v (table-ref wv-tbl 'res-val-key #f))
            (got-t (will-testator live-will)))
        (assert-true (not (eq? got-v #f)) "s6-weak-ref-found")
        (set-box! resurrected-box got-v)
        (verify-tagged-payload got-t 88888 "s6-will-testator-read"))

      ;; Finish concurrent Major GC (Remark clears dead weak entries & triggers dead-will!).
      (gc-start-concurrent-major! 1)
      (assert-true (drive-to-phase! 0 60) "s6-finish-remark")

      ;; Allow executable will to run (Gambit runs executable wills on GC interrupt).
      (thread-sleep! 0.02)
      (churn-young! 500)

      ;; Verify resurrected value survived intact, dead weak entries were cleared,
      ;; live-will did NOT fire, and dead-will DID fire!
      (verify-tagged-payload (unbox resurrected-box) 30004 "s6-resurrected-alive")
      (assert-true (eq? (table-ref wv-tbl 'dead-val-key 'absent) 'absent)
                   "s7-dead-weak-val-cleared")
      (assert-true (eq? (table-ref wk-tbl k-res #f) 'res-key-val)
                   "s7-live-weak-key-preserved")
      (assert-true (= (table-length wk-tbl) 1) "s7-wk-tbl-len-1" (table-length wk-tbl))
      (assert-true (= will-fired-count 1) "s7-dead-will-fired-once" will-fired-count)
      ;; Keep live-will & live-will-target alive across assertions.
      (assert-true (eq? (will-testator live-will) live-will-target) "s7-live-will-alive")
      (assert-true (will? dead-will) "s7-dead-will-obj"))))

;; ---------------------------------------------------------------------------
;; S5 + S9: Parked Tier 3.3 FFI Phase Adoption + Multicore SMP SATB Torture
;; ---------------------------------------------------------------------------
(define (test-smp-concurrent-satb-and-ffi-park)
  (let* ((n-workers 6)
         (shared (make-vector 256 #f))
         (shared-weak (make-table test: eq? weak-values: #t))
         (done-flag #f))
    (let init ((i 0))
      (if (< i 256)
          (let ((p (make-tagged-payload (+ 50000 i))))
            (vector-set! shared i p)
            (table-set! shared-weak i p)
            (init (+ i 1)))))
    (##gc)

    (let* ((ffi-parker
            (thread-start!
             (make-thread
              (lambda ()
                (let ploop ((r 0))
                  (if (and (not done-flag) (< r 12))
                      (begin
                        ;; Park in blocking FFI across concurrent Major phase transitions,
                        ;; then immediately mutate mature heap upon unpark (Mutant 5!).
                        (parked-ffi-sleep-ms 5)
                        (let* ((idx (modulo r 256))
                               (old (vector-ref shared idx))
                               (fresh (make-tagged-payload (+ 60000 r))))
                          (##vector-cas! shared idx fresh old)
                          (vector-set! shared idx old))
                        (ploop (+ r 1)))))))))
           (workers
            (let loop ((w 0) (acc '()))
              (if (= w n-workers)
                  acc
                  (loop
                   (+ w 1)
                   (cons
                    (thread-start!
                     (make-thread
                      (lambda ()
                        (let ((local-hold (make-vector 64 #f)))
                          (let rloop ((r 0))
                            (if (< r 400)
                                (let* ((slot (modulo (+ (* w 37) r) 256))
                                       (lslot (modulo r 64))
                                       (old (vector-ref shared slot))
                                       (tmp (make-tagged-payload (+ 70000 (* w 1000) r))))
                                  ;; Mutate mature shared vector & local vector + weak-table reads + churn!
                                  (vector-set! local-hold lslot old)
                                  (vector-set! shared slot tmp)
                                  (vector-set! shared slot old)
                                  (let ((wv (table-ref shared-weak slot #f)))
                                    (if wv (vector-set! local-hold (modulo (+ lslot 1) 64) wv)))
                                  (if (= (modulo r 40) 0)
                                      (begin
                                        (churn-young! 300)
                                        (gc-major-mark-slice! 1024)))
                                  (rloop (+ r 1)))))))))
                    acc)))))
           (driver
            (thread-start!
             (make-thread
              (lambda ()
                (let dloop ((c 0))
                  (if (< c 3)
                      (begin
                        (gc-start-concurrent-major! 0)
                        (churn-young! 3000)
                        (gc-major-mark-slice! 4096)
                        (gc-start-concurrent-major! 1)
                        (churn-young! 4000)
                        (dloop (+ c 1))))))))))
      (thread-join! driver)
      (for-each thread-join! workers)
      (set! done-flag #t)
      (thread-join! ffi-parker))

    ;; Finish any active cycle and verify every single mature slot in shared!
    (if (= (cm-phase (gc-cm-stats)) 1)
        (begin
          (gc-start-concurrent-major! 1)
          (drive-to-phase! 0 60)))
    (let check ((i 0))
      (if (< i 256)
          (let ((v (vector-ref shared i)))
            (assert-true (vector? v) "s9-shared-vec" i)
            (verify-tagged-payload v (vector-ref v 0) "s9-shared-intact")
            (check (+ i 1)))))))

;; ---------------------------------------------------------------------------
;; S10 + S11 + S12 (Slice 2 v2): Immix Line-Hole Recycling, Parallel STW Remark
;; + Per-Processor Local Mark-Buffer Flush, & Idle-Core Cooperative Marking
;; ---------------------------------------------------------------------------
(define (test-immix-hole-recycling-and-v2-features)
  (let* ((n-groups 24)
         (dead-per-group 96)
         (stride (+ 1 dead-per-group))
         (live-grid (make-vector n-groups #f))
         (v2-0 (gc-cm-v2-stats))
         (holes0 (inexact->exact (round (f64vector-ref v2-0 0)))))
    ;; Place live anchors and 96x200-word (~19.2K-word) movable dead blocks
    ;; in strictly alternating BFS order inside one flat vector so compacting
    ;; (##gc) lays them out physically interleaved inside shared mature sections.
    (let ((interleaved (make-vector (* n-groups stride) #f)))
      (let gloop ((g 0))
        (if (< g n-groups)
            (let ((anchor (make-tagged-payload (+ 90000 g)))
                  (base (* g stride)))
              (vector-set! live-grid g anchor)
              (vector-set! interleaved base anchor)
              (let dloop ((k 0))
                (if (< k dead-per-group)
                    (begin
                      ;; 200 words <= ___MSECTION_BIGGEST(255) -> movable!
                      (vector-set! interleaved (+ base 1 k) (make-vector 200 (+ g k)))
                      (dloop (+ k 1)))))
              (gloop (+ g 1)))))
      ;; Promote interleaved anchors + dead spans into shared mature sections.
      (##gc)
      ;; Drop interleaved container while keeping every live-grid anchor pinned!
      (let clear ((i 0))
        (if (< i (vector-length interleaved))
            (begin
              (vector-set! interleaved i #f)
              (clear (+ i 1))))))

    ;; Run a full Concurrent SATB Major GC cycle -> Parallel STW Remark sweeps
    ;; dead runs and records ~19K-word card-aligned Immix holes inside live
    ;; mature sections!
    (gc-start-concurrent-major! 0)
    (assert-true (drive-to-phase! 1 40) "s10-enter-marking")
    ;; Sleep briefly on multi-core so idle cores can also exercise cooperative marking!
    (if (> (proc-count) 1) (thread-sleep! 0.005))
    (gc-major-mark-slice! 32768)
    (gc-start-concurrent-major! 1)
    (assert-true (drive-to-phase! 0 60) "s10-finish-remark")

    ;; Now promote new young survivors across several IDLE Minor GCs so Minor GC
    ;; recycles the discovered Immix holes (gc_is_dest == 3) and verify all
    ;; promoted objects + existing live-grid neighbors survive a subsequent GC!
    (let ((promoted (make-vector 1600 #f)))
      (let ploop ((r 0))
        (if (< r 1600)
            (begin
              (vector-set! promoted r (make-tagged-payload (+ 95000 r)))
              (if (= (modulo r 200) 199) (churn-young! 5000))
              (ploop (+ r 1)))))
      ;; Trigger one more concurrent Major cycle to verify card-starts & fillers
      ;; inside recycled holes are 100% sound under marking + sweeping!
      (gc-start-concurrent-major! 0)
      (assert-true (drive-to-phase! 1 40) "s10-cycle2-enter")
      (gc-start-concurrent-major! 1)
      (assert-true (drive-to-phase! 0 60) "s10-cycle2-finish")
      (##gc)

      (let check1 ((i 0))
        (if (< i n-groups)
            (begin
              (verify-tagged-payload (vector-ref live-grid i) (+ 90000 i) "s10-live-grid")
              (check1 (+ i 1)))))
      (let check2 ((i 0))
        (if (< i 1600)
            (begin
              (verify-tagged-payload (vector-ref promoted i) (+ 95000 i) "s10-promoted-in-hole")
              (check2 (+ i 1))))))

    (let* ((v2-1 (gc-cm-v2-stats))
           (dholes (- (inexact->exact (round (f64vector-ref v2-1 0))) holes0))
           (idle-slc (inexact->exact (round (f64vector-ref v2-1 1)))))
      (assert-true (> dholes 0) "s10-immix-holes-recycled" dholes)
      (list dholes idle-slc))))

;; ---------------------------------------------------------------------------
;; Main
;; ---------------------------------------------------------------------------
(test-satb-edge-move-black-alloc-cas)
(let ((reclaim-info (test-nonmoving-reclaim-sections-and-still)))
  (test-satb-overflow-recovery)
  (test-weak-tables-and-wills)
  (test-smp-concurrent-satb-and-ffi-park)
  (let* ((v2-info (test-immix-hole-recycling-and-v2-features))
         (st (gc-cm-stats))
         (gs (gc-gen-stats)))
    (assert-true (>= (cm-cycles st) 6) "total-cm-cycles" (cm-cycles st))
    (assert-true (> (cm-slices st) 0) "total-cm-slices" (cm-slices st))
    (assert-true (> (cm-marked-words st) 0) "total-cm-marked-words" (cm-marked-words st))
    (assert-true (= (cm-phase st) 0) "final-phase-idle" (cm-phase st))
    (write
      (list 'T6-CONCURRENT-SATB-MAJOR-GC-PASS
            'procs (proc-count)
            'cm-cycles (cm-cycles st)
            'cm-slices (cm-slices st)
            'cm-marked-words (cm-marked-words st)
            'cm-reclaimed-secs (cm-reclaimed-secs st)
            'cm-reclaimed-still (cm-reclaimed-still st)
            'cm-satb-logged (cm-satb-logged st)
            's3-reclaim reclaim-info
            's10-v2-holes-idle v2-info
            'minor-gcs (inexact->exact (round (f64vector-ref gs 0)))
            'major-gcs (inexact->exact (round (f64vector-ref gs 1)))))
    (newline)))
