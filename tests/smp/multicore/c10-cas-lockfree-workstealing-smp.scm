;;; C10: High-contention lock-free ##vector-cas! Treiber stack conservation +
;;;      contended mutex/condvar MPMC bounded queue + 8-thread mailbox ring storm
;;;      under active GC-Hammer across p1/p2/p4/p6/p8.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

;; Lock-free Treiber stack backed by (vector head-pair) and ##vector-cas!
(define (make-lf-stack) (vector '()))

(define (lf-push! st val)
  (let loop ()
    (let* ((old (vector-ref st 0))
           (node (cons val old)))
      (if (not (eq? (##vector-cas! st 0 node old) old))
          (loop)))))

(define (lf-pop! st)
  (let loop ()
    (let ((old (vector-ref st 0)))
      (if (null? old)
          #f
          (let ((nxt (cdr old)))
            (if (eq? (##vector-cas! st 0 nxt old) old)
                (car old)
                (loop)))))))

;; Contended mutex + condition-variable bounded MPMC queue
(define (make-mpmc cap)
  (vector (make-mutex 'c10-q)
          (make-condition-variable 'c10-not-empty)
          (make-condition-variable 'c10-not-full)
          (make-vector cap #f)
          0 0 0 cap)) ; head tail count cap

(define (mpmc-put! q val)
  (let ((mtx (vector-ref q 0))
        (cv-ne (vector-ref q 1))
        (cv-nf (vector-ref q 2))
        (buf (vector-ref q 3))
        (cap (vector-ref q 7)))
    (mutex-lock! mtx)
    (let loop ()
      (if (= (vector-ref q 6) cap)
          (begin
            (mutex-unlock! mtx cv-nf)
            (mutex-lock! mtx)
            (loop))))
    (let ((tail (vector-ref q 5)))
      (vector-set! buf tail val)
      (vector-set! q 5 (modulo (+ tail 1) cap))
      (vector-set! q 6 (+ (vector-ref q 6) 1)))
    (condition-variable-signal! cv-ne)
    (mutex-unlock! mtx)))

(define (mpmc-get! q)
  (let ((mtx (vector-ref q 0))
        (cv-ne (vector-ref q 1))
        (cv-nf (vector-ref q 2))
        (buf (vector-ref q 3))
        (cap (vector-ref q 7)))
    (mutex-lock! mtx)
    (let loop ()
      (if (= (vector-ref q 6) 0)
          (begin
            (mutex-unlock! mtx cv-ne)
            (mutex-lock! mtx)
            (loop))))
    (let* ((head (vector-ref q 4))
           (val (vector-ref buf head)))
      (vector-set! buf head #f)
      (vector-set! q 4 (modulo (+ head 1) cap))
      (vector-set! q 6 (- (vector-ref q 6) 1))
      (condition-variable-signal! cv-nf)
      (mutex-unlock! mtx)
      val)))

(define (run-c10)
  (let* ((gc0 (mc-gc-count))
         (res
          (with-gc-hammer
           0.004
           (lambda ()
             ;; Part 1: 4 pushers + 4 poppers on lock-free Treiber stack (16,000 items)
             (let* ((st (make-lf-stack))
                    (n-prod 4)
                    (per-prod 4000)
                    (total-items (* n-prod per-prod))
                    (seen (make-u8vector total-items 0))
                    (popped (vector 0))
                    (pop-sum (vector 0))
                    (check-mtx (make-mutex 'c10-chk))
                    (pushers
                     (let loop ((p 0) (acc '()))
                       (if (= p n-prod)
                           acc
                           (loop (+ p 1)
                                 (cons (thread-start!
                                        (make-thread
                                         (lambda ()
                                           (let ((base (* p per-prod)))
                                             (let i-loop ((i 0))
                                               (if (< i per-prod)
                                                   (begin
                                                     (lf-push! st (+ base i 1))
                                                     (if (= (modulo i 250) 0) (thread-yield!))
                                                     (i-loop (+ i 1)))))))
                                         'c10-lf-push))
                                       acc)))))
                    (poppers
                     (let loop ((c 0) (acc '()))
                       (if (= c n-prod)
                           acc
                           (loop (+ c 1)
                                 (cons (thread-start!
                                        (make-thread
                                         (lambda ()
                                           (let p-loop ((local-cnt 0) (local-sum 0) (local-ids '()))
                                             (let ((v (lf-pop! st)))
                                               (cond
                                                (v
                                                 (p-loop (+ local-cnt 1) (+ local-sum v) (cons v local-ids)))
                                                (else
                                                 (mutex-lock! check-mtx)
                                                 (let ((cur (+ (vector-ref popped 0) local-cnt)))
                                                   (vector-set! popped 0 cur)
                                                   (vector-set! pop-sum 0 (+ (vector-ref pop-sum 0) local-sum))
                                                   (for-each
                                                    (lambda (id)
                                                      (let ((idx (- id 1)))
                                                        (mc-assert (= (u8vector-ref seen idx) 0) 'c10-lf-dup id)
                                                        (u8vector-set! seen idx 1)))
                                                    local-ids)
                                                   (mutex-unlock! check-mtx)
                                                   (if (< cur total-items)
                                                       (begin
                                                         (thread-yield!)
                                                         (p-loop 0 0 '())))))))))
                                         'c10-lf-pop))
                                       acc))))))
               (for-each thread-join! pushers)
               (for-each thread-join! poppers)
               (let ((expected-sum (quotient (* total-items (+ total-items 1)) 2)))
                 (mc-assert (= (vector-ref popped 0) total-items) 'c10-lf-count (vector-ref popped 0))
                 (mc-assert (= (vector-ref pop-sum 0) expected-sum) 'c10-lf-sum (vector-ref pop-sum 0) expected-sum)
                 (mc-assert (null? (vector-ref st 0)) 'c10-lf-nonempty))

               ;; Part 2: Contended MPMC bounded queue (4 producers + 4 consumers, 8,000 items)
               (let* ((q (make-mpmc 32))
                      (per-q 2000)
                      (q-total (* 4 per-q))
                      (q-prods
                       (let loop ((p 0) (acc '()))
                         (if (= p 4)
                             acc
                             (loop (+ p 1)
                                   (cons (thread-start!
                                          (make-thread
                                           (lambda ()
                                             (let ((base (* p per-q)))
                                               (let i-loop ((i 0))
                                                 (if (< i per-q)
                                                     (begin
                                                       (mpmc-put! q (+ base i 1))
                                                       (i-loop (+ i 1)))))))
                                           'c10-q-prod))
                                         acc)))))
                      (q-cons
                       (let loop ((c 0) (acc '()))
                         (if (= c 4)
                             acc
                             (loop (+ c 1)
                                   (cons (thread-start!
                                          (make-thread
                                           (lambda ()
                                             (let i-loop ((i 0) (s 0))
                                               (if (= i per-q)
                                                   s
                                                   (i-loop (+ i 1) (+ s (mpmc-get! q))))))
                                           'c10-q-cons))
                                         acc))))))
                 (for-each thread-join! q-prods)
                 (let ((got-sum (apply + (map thread-join! q-cons)))
                       (exp-sum (quotient (* q-total (+ q-total 1)) 2)))
                   (mc-assert (= got-sum exp-sum) 'c10-mpmc-sum got-sum exp-sum)))

               ;; Part 3: 8-thread mailbox ring storm (500 laps = 4,000 cross-core hops)
               (let* ((n-ring 8)
                      (laps 500)
                      (ring (make-vector n-ring #f)))
                 (let loop ((i 0))
                   (if (< i n-ring)
                       (begin
                         (vector-set!
                          ring i
                          (make-thread
                           (lambda ()
                             (let ((nxt (vector-ref ring (modulo (+ i 1) n-ring))))
                               (let r-loop ((k 0))
                                 (if (< k laps)
                                     (let ((tok (thread-receive)))
                                       (if (not (and (= i (- n-ring 1)) (= k (- laps 1))))
                                           (thread-send nxt (+ tok 1))
                                           tok)
                                       (r-loop (+ k 1)))
                                     'ok))))
                           (string-append "c10-ring-" (number->string i))))
                         (loop (+ i 1)))))
                 (let loop ((i 0))
                   (if (< i n-ring)
                       (begin (thread-start! (vector-ref ring i)) (loop (+ i 1)))))
                 (thread-send (vector-ref ring 0) 0)
                 (let loop ((i 0))
                   (if (< i n-ring)
                       (begin (thread-join! (vector-ref ring i)) (loop (+ i 1))))))))))
         (pulses (cdr res))
         (gc-delta (- (mc-gc-count) gc0)))
    (mc-assert (> gc-delta 0) 'c10-no-gc)
    (display (list 'C10-CAS-LOCKFREE-WORKSTEALING-PASS
                   'procs (mc-processor-count)
                   'lf-items 16000
                   'mpmc-items 8000
                   'ring-hops 4000
                   'gc-pulses pulses
                   'gc-total gc-delta))
    (newline)
    (force-output)))

(run-c10)
