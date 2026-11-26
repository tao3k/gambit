;;; C9: High-core variadic rest-parameter & keyword-rest nursery TLAB contention
;;;     under tight heap bounds (m65536). Verifies exact checksum conservation,
;;;     bounded GC count (proving zero-growth budgeted nursery refill eliminates
;;;     500x+ per-section STW GC amplification), and safety across STW half-flips.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (c9-sum-rest a b . rest)
  (let loop ((xs rest) (acc (+ a b)))
    (if (pair? xs)
        (loop (cdr xs) (+ acc (car xs)))
        acc)))

(define (c9-sum-kw a #!key (k1 10) (k2 20) #!rest r)
  (let loop ((xs r) (acc (+ a k1 k2)))
    (if (pair? xs)
        (loop (cdr xs) (+ acc (if (fixnum? (car xs)) (car xs) 1)))
        acc)))

(define (run-c9)
  (let* ((n-workers 8)
         (iters 25000)
         (gc0 (mc-gc-count))
         (threads
          (let loop ((w 0) (acc '()))
            (if (= w n-workers)
                acc
                (loop
                 (+ w 1)
                 (cons
                  (thread-start!
                   (make-thread
                    (lambda ()
                      (let inner ((i 0) (tot 0))
                        (if (= i iters)
                            tot
                            (let* ((v1 (c9-sum-rest 1 2 3 4 5 6 7 8))
                                   (v2 (c9-sum-kw 5 k1: 7 k2: 9 11 13))
                                   (v3 (apply c9-sum-rest (list 2 4 6 8 10))))
                              ;; v1 = 36, v2 = 5+7+9+(11+13)=45, v3 = 30 -> 111
                              (mc-assert (= v1 36) 'c9-rest-bad v1)
                              (mc-assert (= v2 45) 'c9-kw-bad v2)
                              (mc-assert (= v3 30) 'c9-apply-bad v3)
                              (inner (+ i 1) (+ tot v1 v2 v3))))))
                    (string-append "c9-w-" (number->string w))))
                  acc)))))
         (vals (map thread-join! threads))
         (gc1 (mc-gc-count))
         (gc-delta (- gc1 gc0))
         (expected (* iters 111)))
    (for-each (lambda (v) (mc-assert (= v expected) 'c9-worker-sum v expected)) vals)
    ;; Without v16 budgeted nursery refill, 200k rest calls triggered hundreds of STW GCs;
    ;; with budgeted nursery refill under m65536, gc-delta stays sharply bounded.
    (mc-assert (<= gc-delta 40) 'c9-gc-amplification-regression gc-delta)
    (display (list 'C9-REST-KEYWORD-NURSERY-CONTENTION-PASS
                   'procs (mc-processor-count)
                   'workers n-workers
                   'calls (* n-workers iters 3)
                   'gc-total gc-delta))
    (newline)
    (force-output)))

(run-c9)
