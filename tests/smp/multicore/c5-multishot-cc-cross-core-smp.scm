;;; C5 (Gambit-unique multi-shot continuation × cross-core migration × dynamic-wind):
;;; Captures a deep-stack (multi-msection break-frame, depth 350) multi-shot
;;; continuation wrapped in dynamic-wind on one processor, broadcasts it to
;;; peer threads running across p2/p4 processors, and invokes it repeatedly
;;; (3+ shots per thread) while GC-Hammer & thread-interrupt! fire concurrently.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define (deep-capture depth acc-box captured-box dw-enters dw-exits dw-mtx)
  (if (= depth 0)
      (dynamic-wind
        (lambda ()
          (mutex-lock! dw-mtx)
          (vector-set! dw-enters 0 (+ (vector-ref dw-enters 0) 1))
          (mutex-unlock! dw-mtx))
        (lambda ()
          (call-with-current-continuation
           (lambda (k)
             (vector-set! captured-box 0 k)
             (cons 'initial (vector-ref acc-box 0)))))
        (lambda ()
          (mutex-lock! dw-mtx)
          (vector-set! dw-exits 0 (+ (vector-ref dw-exits 0) 1))
          (mutex-unlock! dw-mtx)))
      ;; Non-tail recursion with live heap objects in every frame so GC must
      ;; relocate live roots across multiple stack msection break frames!
      (let ((frame-tag (vector 'frm depth (* depth 3))))
        (let ((res (deep-capture (- depth 1) acc-box captured-box dw-enters dw-exits dw-mtx)))
          (mc-assert (and (vector? frame-tag)
                          (eq? (vector-ref frame-tag 0) 'frm)
                          (= (vector-ref frame-tag 1) depth)
                          (= (vector-ref frame-tag 2) (* depth 3)))
                     'c5-frame-root-corrupted depth frame-tag)
          (if (pair? res)
              (cons (car res) (+ (cdr res) 1))
              (mc-fail 'c5-unexpected-return res))))))

(define (run-c5)
  (let* ((captured (vector #f))
         (acc-box (vector 0))
         (dw-enters (vector 0))
         (dw-exits (vector 0))
         (dw-mtx (make-mutex 'c5-dw))
         (shot-results (make-vector 12 #f))
         (depth 350))
    ;; Capture deep multi-shot continuation on main thread; deliver cross-thread
    ;; shot returns via per-thread escape stored in thread-specific!
    (let ((init-res
           (let ((r (deep-capture depth acc-box captured dw-enters dw-exits dw-mtx)))
             (let ((esc (thread-specific (current-thread))))
               (if (procedure? esc)
                   (esc r)
                   r)))))
      (mc-assert (equal? init-res (cons 'initial depth)) 'c5-initial-capture-mismatch init-res))
    (let ((k (vector-ref captured 0)))
      (mc-assert (procedure? k) 'c5-not-a-continuation k)
      (let* ((gc0 (mc-gc-count))
             (res
              (with-gc-hammer
               0.002
               (lambda ()
                 ;; Spawn 4 threads across processors; each invokes k 3 times!
                 ;; Each shot jumps into deep-capture's 350-frame stack, unwinds
                 ;; through all 350 live frame-tag checks, and returns into the
                 ;; caller's own thread-specific escape continuation!
                 (let ((workers
                        (map
                         (lambda (wid)
                           (thread-start!
                            (make-thread
                             (lambda ()
                               (let shot ((s 0))
                                 (if (< s 3)
                                     (let* ((idx (+ (* wid 3) s))
                                            (payload (+ 1000 idx))
                                            (got
                                             (call-with-current-continuation
                                              (lambda (escape)
                                                (thread-specific-set! (current-thread) escape)
                                                (##gc)
                                                (k (cons 'shot payload))))))
                                       (thread-specific-set! (current-thread) #f)
                                       (mc-assert (equal? got (cons 'shot (+ payload depth)))
                                                  'c5-shot-result-mismatch wid s got)
                                       (vector-set! shot-results idx got)
                                       (shot (+ s 1))))))
                             (string-append "c5-w-" (number->string wid)))))
                         '(0 1 2 3))))
                   ;; Interrupt workers gently while shots execute
                   (let poke ((i 0))
                     (if (< i 20)
                         (begin
                           (for-each (lambda (t)
                                       (with-exception-catcher
                                        (lambda (e) #f)
                                        (lambda () (thread-interrupt! t (lambda () #t)))))
                                     workers)
                           (thread-sleep! 0.002)
                           (poke (+ i 1)))))
                   (for-each thread-join! workers)))))
             (pulses (cdr res))
             (gc-delta (- (mc-gc-count) gc0)))
        ;; Every single one of the 12 multi-shot invocations must have succeeded
        (let chk ((i 0))
          (if (< i 12)
              (begin
                (mc-assert (equal? (vector-ref shot-results i)
                                   (cons 'shot (+ 1000 i depth)))
                           'c5-shot-missing i (vector-ref shot-results i))
                (chk (+ i 1)))))
        ;; dynamic-wind enters and exits must be strictly balanced!
        ;; 1 initial capture + 12 shots = 13 enters and 13 exits
        (mc-assert (= (vector-ref dw-enters 0) (vector-ref dw-exits 0))
                   'c5-dynamic-wind-imbalance (vector-ref dw-enters 0) (vector-ref dw-exits 0))
        (mc-assert (= (vector-ref dw-enters 0) 13)
                   'c5-dynamic-wind-count (vector-ref dw-enters 0))
        (mc-assert (> gc-delta 0) 'c5-no-gc)
        (display (list 'C5-MULTISHOT-CC-CROSS-CORE-PASS
                       'procs (mc-processor-count)
                       'depth depth
                       'shots 12
                       'dw-balanced (vector-ref dw-enters 0)
                       'gc-pulses pulses
                       'gc-total gc-delta))
        (newline)
        (force-output)))))

(run-c5)
