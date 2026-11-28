;;;============================================================================

;;; File: "deque.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; 128B-Padded Chase-Lev Work-Stealing Deque (Le et al. PPoPP 2013)
;;;
;;; Backing ring buffers are GC-traced Scheme vectors accessed via relaxed
;;; GC-barriered atomics so speculative stealers racing with ring wraparound
;;; are C23 DRF-0 clean, while `top` and `bottom` occupy distinct 128B cache
;;; lines to eliminate owner-vs-thief false sharing.

(##define-type work-stealing-deque
  id: 8B42D1A1-5C7E-4D1A-9F3B-3B2000000001
  type-exhibitor: macro-type-work-stealing-deque
  constructor: macro-make-work-stealing-deque
  implementer: implement-type-work-stealing-deque
  macros:
  prefix: macro-
  opaque:
  (top    read-only: unprintable:)
  (bottom read-only: unprintable:)
  (array  read-only: unprintable:))
(implement-type-work-stealing-deque)

(define (next-pow2 n)
  (let loop ((p 4))
    (if (##fx>= p n) p (loop (##fxarithmetic-shift-left p 1)))))

(define (make-work-stealing-deque #!optional (initial-capacity 64))
  (let ((cap (next-pow2 (if (and (##fixnum? initial-capacity)
                                 (##fx> initial-capacity 0))
                            initial-capacity
                            64))))
    (macro-make-work-stealing-deque
     (%make-padded-fxatom 0)
     (%make-padded-fxatom 0)
     (make-atomic-box (##make-vector cap #f)))))

(define (work-stealing-deque? obj)
  (macro-work-stealing-deque? obj))

(define (deque-size-approx q)
  (if (not (macro-work-stealing-deque? q))
      (error "deque-size-approx: expected work-stealing-deque" q))
  (let* ((t (%fxatom-load-acq (macro-work-stealing-deque-top q)))
         (b (%fxatom-load-acq (macro-work-stealing-deque-bottom q)))
         (d (##fx- b t)))
    (if (##fx> d 0) d 0)))

(define (deque-empty? q)
  (if (not (macro-work-stealing-deque? q))
      (error "deque-empty?: expected work-stealing-deque" q))
  (##fx= (deque-size-approx q) 0))

;;; Grow ring buffer by 2x, preserving every live slot i in [t, b) without collision.
(define (deque-grow-array! q old-a t b)
  (let* ((old-cap (##vector-length old-a))
         (old-mask (##fx- old-cap 1))
         (new-cap (##fxarithmetic-shift-left old-cap 1))
         (new-mask (##fx- new-cap 1))
         (new-a (##make-vector new-cap #f)))
    (let loop ((i t))
      (if (##fx< i b)
          (begin
            (##vector-set!
             new-a
             (##fxand i new-mask)
             (%vec-slot-load-rlx old-a (##fxand i old-mask)))
            (loop (##fx+ i 1)))))
    (atomic-box-set! (macro-work-stealing-deque-array q) new-a 'release)
    new-a))

;;; Owner-only LIFO push at bottom.
(define (deque-push-bottom! q item)
  (if (not (macro-work-stealing-deque? q))
      (error "deque-push-bottom!: expected work-stealing-deque" q))
  (let* ((bot-box (macro-work-stealing-deque-bottom q))
         (b (%fxatom-load-rlx bot-box))
         (t (%fxatom-load-acq (macro-work-stealing-deque-top q)))
         (a0 (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed))
         (a (if (##fx>= (##fx- b t) (##vector-length a0))
                (deque-grow-array! q a0 t b)
                a0))
         (mask (##fx- (##vector-length a) 1)))
    (%vec-slot-store-rlx! a (##fxand b mask) item)
    (%fxatom-store-rel! bot-box (##fx+ b 1))
    (##void)))

;;; Owner-only LIFO pop from bottom (Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-pop-bottom! q #!optional (empty #f))
  (if (not (macro-work-stealing-deque? q))
      (error "deque-pop-bottom!: expected work-stealing-deque" q))
  (let* ((bot-box (macro-work-stealing-deque-bottom q))
         (top-box (macro-work-stealing-deque-top q))
         (b (##fx- (%fxatom-load-rlx bot-box) 1))
         (a (atomic-box-ref (macro-work-stealing-deque-array q) 'relaxed)))
    (%fxatom-store-rlx! bot-box b)
    (%seq-cst-fence!)
    (let ((t (%fxatom-load-rlx top-box)))
      (if (##fx<= t b)
          (let* ((mask (##fx- (##vector-length a) 1))
                 (idx (##fxand b mask))
                 (x (%vec-slot-load-rlx a idx)))
            (if (##fx= t b)
                (let ((prev (%fxatom-cas-seq! top-box t (##fx+ t 1))))
                  (%fxatom-store-rlx! bot-box (##fx+ b 1))
                  (if (##fx= prev t) x empty))
                (begin
                  ;; Safe to clear slot when t < b (no thief can read b).
                  (%vec-slot-store-rlx! a idx #f)
                  x)))
          (begin
            (%fxatom-store-rlx! bot-box (##fx+ b 1))
            empty)))))

;;; Concurrent thief FIFO steal from top (Le et al. PPoPP 2013 seq_cst Dekker fence).
(define (deque-steal! q #!optional (empty #f) (abort #f))
  (if (not (macro-work-stealing-deque? q))
      (error "deque-steal!: expected work-stealing-deque" q))
  (let* ((top-box (macro-work-stealing-deque-top q))
         (bot-box (macro-work-stealing-deque-bottom q))
         (t (%fxatom-load-acq top-box)))
    (%seq-cst-fence!)
    (let ((b (%fxatom-load-acq bot-box)))
      (if (##fx< t b)
          (let* ((a (atomic-box-ref (macro-work-stealing-deque-array q) 'acquire))
                 (mask (##fx- (##vector-length a) 1))
                 (x (%vec-slot-load-rlx a (##fxand t mask)))
                 (prev (%fxatom-cas-seq! top-box t (##fx+ t 1))))
            (if (##fx= prev t) x abort))
          empty))))

;;;============================================================================
