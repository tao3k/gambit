;;; C4 (Chez concurrent load/intern + Gambit Family 8 P0-2 binding-read stress):
;;; Concurrent dynamic .o1 loading (if C4_O1_LIST env is supplied) + concurrent
;;; string->symbol / string->keyword interning + concurrent global binding
;;; reads/updates across p2/p4 under active GC-Hammer.

(declare (standard-bindings) (extended-bindings))
(include "gc-hammer.scm")

(define c4-shared-counter 0)
(define (c4-target-fn x) (+ x 1))

(define (split-colon str)
  (if (or (not str) (= (string-length str) 0))
      '()
      (let ((n (string-length str)))
        (let loop ((i 0) (start 0) (acc '()))
          (cond
           ((= i n)
            (reverse (if (> i start) (cons (substring str start i) acc) acc)))
           ((char=? (string-ref str i) #\:)
            (loop (+ i 1) (+ i 1)
                  (if (> i start) (cons (substring str start i) acc) acc)))
           (else (loop (+ i 1) start acc)))))))

(define (run-c4)
  (let* ((o1-paths (split-colon (getenv "C4_O1_LIST" "")))
         (load-mtx (make-mutex 'c4-load))
         (loaded-count (vector 0))
         (sym-count (vector 0))
         (bind-reads (vector 0))
         (stop (vector #f)))
    ;; Worker 0 & 1: heavy concurrent symbol + keyword interning (stresses symbol_table/keyword_table!)
    (define (make-intern-worker wid)
      (thread-start!
       (make-thread
        (lambda ()
          (let loop ((i 0))
            (if (< i 2500)
                (let* ((s1 (string->symbol (string-append "c4-sym-" (number->string wid) "-" (number->string i))))
                       (s2 (string->symbol (string-append "c4-shared-" (number->string (modulo i 200)))))
                       (k1 (string->keyword (string-append "c4-kw-" (number->string wid) "-" (number->string i)))))
                  (mc-assert (eq? s1 (string->symbol (symbol->string s1))) 'c4-sym-intern-identity wid i)
                  (mc-assert (eq? s2 (string->symbol (symbol->string s2))) 'c4-shared-sym-identity wid i)
                  (mc-assert (eq? k1 (string->keyword (keyword->string k1))) 'c4-kw-intern-identity wid i)
                  (loop (+ i 1)))))
          (mutex-lock! load-mtx)
          (vector-set! sym-count 0 (+ (vector-ref sym-count 0) 2500))
          (mutex-unlock! load-mtx))
        (string-append "c4-intern-" (number->string wid)))))

    ;; Worker 2: concurrent global binding mutations & dynamic .o1 loading
    (define w-mutator
      (thread-start!
       (make-thread
        (lambda ()
          ;; Load precompiled .o1 modules if provided by runner
          (for-each
           (lambda (p)
             (load p)
             (mutex-lock! load-mtx)
             (vector-set! loaded-count 0 (+ (vector-ref loaded-count 0) 1))
             (mutex-unlock! load-mtx)
             (##gc))
           o1-paths)
          ;; Mutate global function binding repeatedly while readers call it!
          (let loop ((i 0))
            (if (< i 1500)
                (let ((delta (+ 1 (modulo i 7))))
                  (set! c4-shared-counter i)
                  (set! c4-target-fn (lambda (x) (+ x delta)))
                  (if (= (modulo i 40) 0) (thread-yield!))
                  (loop (+ i 1))))))
        'c4-mutator)))

    ;; Worker 3: high-rate global primitive & variable reader (exercises P0-2 binding_view!)
    (define w-reader
      (thread-start!
       (make-thread
        (lambda ()
          (let loop ((i 0) (acc 0))
            (if (not (vector-ref stop 0))
                (let* ((fn c4-target-fn)
                       (v (fn 10))
                       (c c4-shared-counter))
                  (mc-assert (and (>= v 11) (<= v 17)) 'c4-binding-torn-fn v)
                  (mc-assert (and (fixnum? c) (>= c 0)) 'c4-binding-torn-counter c)
                  (if (= (modulo i 500) 0) (thread-yield!))
                  (loop (+ i 1) (+ acc 1)))
                (vector-set! bind-reads 0 acc))))
        'c4-reader)))

    (let* ((gc0 (mc-gc-count))
           (res
            (with-gc-hammer
             0.002
             (lambda ()
               (let ((w0 (make-intern-worker 0))
                     (w1 (make-intern-worker 1)))
                 (thread-join! w0)
                 (thread-join! w1)
                 (thread-join! w-mutator)
                 (vector-set! stop 0 #t)
                 (thread-join! w-reader)))))
           (pulses (cdr res))
           (gc-delta (- (mc-gc-count) gc0)))
      (mc-assert (= (vector-ref sym-count 0) 5000) 'c4-sym-count)
      (mc-assert (> (vector-ref bind-reads 0) 0) 'c4-zero-reads)
      (mc-assert (> gc-delta 0) 'c4-no-gc)
      (display (list 'C4-DYNAMIC-O1-BINDING-SYMKEY-PASS
                     'procs (mc-processor-count)
                     'o1-loaded (vector-ref loaded-count 0)
                     'symbols-interned (vector-ref sym-count 0)
                     'binding-reads (vector-ref bind-reads 0)
                     'gc-pulses pulses
                     'gc-total gc-delta))
      (newline)
      (force-output))))

(run-c4)
