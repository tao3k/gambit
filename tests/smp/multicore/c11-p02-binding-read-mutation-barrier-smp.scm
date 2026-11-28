;;; C11: High-core P0-2 binding-read fast path (___GLOBALVARPRIMREF / ___binding_vm)
;;;      vs concurrent global mutations & continuous STW GC binding_view freeze/restore
;;;      across p1/p2/p4/p6/p8.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define c11-epoch 0)
(define c11-pair (cons 0 1))
(define c11-vec (vector 1 2 3 4))
(define (c11-dispatch x) (+ x 1))

(define (run-c11)
  (let* ((n-readers 6)
         (reads-per-reader 200000)
         (stop (vector #f))
         (gc0 (mc-gc-count))
         (res
          (with-gc-hammer
           0.002
           (lambda ()
             ;; Mutator 0: monotonically updates global scalar/pair/vector bindings
             (define m0
               (thread-start!
                (make-thread
                 (lambda ()
                   (let loop ((i 1))
                     (if (not (vector-ref stop 0))
                         (begin
                           (set! c11-epoch i)
                           (set! c11-pair (cons i (+ i 1)))
                           (set! c11-vec (vector i (+ i 1) (+ i 2) (+ i 3)))
                           (if (= (modulo i 200) 0) (thread-yield!))
                           (loop (+ i 1))))))
                 'c11-mut0)))
             ;; Mutator 1: rotates global closure binding
             (define m1
               (thread-start!
                (make-thread
                 (lambda ()
                   (let loop ((i 0))
                     (if (not (vector-ref stop 0))
                         (let ((d (+ 1 (modulo i 16))))
                           (set! c11-dispatch (lambda (x) (+ x d)))
                           (if (= (modulo i 100) 0) (thread-yield!))
                           (loop (+ i 1))))))
                 'c11-mut1)))
             ;; 6 compiled readers hammering P0-2 primitive & mutable global reads
             (define readers
               (let loop ((r 0) (acc '()))
                 (if (= r n-readers)
                     acc
                     (loop
                      (+ r 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let r-loop ((i 0) (prev-ep 0) (acc-v 0))
                             (if (= i reads-per-reader)
                                 acc-v
                                 (let* ((ep c11-epoch)
                                        (pr c11-pair)
                                        (vc c11-vec)
                                        (fn c11-dispatch)
                                        (rv (fn 100))
                                        (p0 (car pr))
                                        (p1 (cdr pr))
                                        (v0 (vector-ref vc 0))
                                        (v3 (vector-ref vc 3)))
                                   (mc-assert (and (fixnum? ep) (>= ep prev-ep))
                                              'c11-non-monotone-epoch ep prev-ep)
                                   (mc-assert (= p1 (+ p0 1)) 'c11-torn-pair p0 p1)
                                   (mc-assert (= v3 (+ v0 3)) 'c11-torn-vec v0 v3)
                                   (mc-assert (and (>= rv 101) (<= rv 116)) 'c11-torn-fn rv)
                                   (r-loop (+ i 1) ep (+ acc-v (bitwise-and rv 7)))))))
                         (string-append "c11-reader-" (number->string r))))
                       acc)))))
             (let ((sums (map thread-join! readers)))
               (vector-set! stop 0 #t)
               (thread-join! m0)
               (thread-join! m1)
               sums))))
         (sums (car res))
         (pulses (cdr res))
         (gc-delta (- (mc-gc-count) gc0)))
    (for-each (lambda (s) (mc-assert (> s 0) 'c11-zero-acc s)) sums)
    (mc-assert (> gc-delta 0) 'c11-no-gc)
    (display (list 'C11-P02-BINDING-READ-BARRIER-PASS
                   'procs (mc-processor-count)
                   'readers n-readers
                   'total-reads (* n-readers reads-per-reader)
                   'final-epoch c11-epoch
                   'gc-pulses pulses
                   'gc-total gc-delta))
    (newline)
    (force-output)))

(run-c11)
