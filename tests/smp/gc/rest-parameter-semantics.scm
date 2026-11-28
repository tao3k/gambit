;;; DEV semantic oracle for ordinary and both keyword/rest calling forms.
;;; Explicit GC here runs after argument binding. Native cut probes must
;;; establish separately that a short grant reaches GC before binding.
(define (ensure condition label)
  (if (not condition) (error "stress-gsi rest semantic mismatch" label)))

(define entries 0)
(define default-flag (vector 'default))

(define (observe label flag tail)
  (set! entries (+ entries 1))
  (##gc)
  (vector label flag tail))

(define (ordinary label . tail)
  (observe label #f tail))

(define (keyword-rest label #!key (flag default-flag) . tail)
  (observe label flag tail))

(define (rest-keyword label #!rest tail #!key (flag default-flag))
  (observe label flag tail))

(define (expect-result label flag tail invoke)
  (let* ((before entries)
         (result (invoke)))
    (ensure (= entries (+ before 1)) 'single-body-entry)
    (ensure (eq? (vector-ref result 0) label) 'label)
    (ensure (eq? (vector-ref result 1) flag) 'keyword-value)
    (let loop ((expected tail) (actual (vector-ref result 2)))
      (cond ((null? expected)
             (ensure (null? actual) 'rest-length))
            (else
             (ensure (pair? actual) 'rest-shape)
             (ensure (eqv? (car expected) (car actual)) 'rest-order-or-alias)
             (loop (cdr expected) (cdr actual)))))))

(define (expect-rejection predicate invoke)
  (let* ((before entries)
         (caught (with-exception-catcher predicate
                   (lambda () (invoke) #f))))
    (ensure caught 'exception-class)
    (ensure (= entries before) 'rejected-before-body)))

(let* ((label (vector 'procedure-label))
       (selected (vector 'selected))
       (shadowed (vector 'shadowed))
       (keyword-args (list flag: selected flag: shadowed))
       (tail (let loop ((i 3999) (out (list selected)))
               (if (< i 0) out (loop (- i 1) (cons i out))))))
  (expect-result label #f '() (lambda () (ordinary label)))
  (expect-result label #f (list selected)
    (lambda () (ordinary label selected)))
  (expect-result label #f tail
    (lambda () (apply ordinary label tail)))
  (expect-result label default-flag '()
    (lambda () (keyword-rest label)))
  (expect-result label selected (list selected)
    (lambda () (keyword-rest label flag: selected selected)))
  (expect-result label selected tail
    (lambda () (apply keyword-rest label (append keyword-args tail))))
  (expect-result label selected keyword-args
    (lambda () (apply rest-keyword label keyword-args)))
  (expect-rejection wrong-number-of-arguments-exception?
    (lambda () (apply ordinary '())))
  (expect-rejection unknown-keyword-argument-exception?
    (lambda () (keyword-rest label unknown: selected))))

(ensure (= entries 7) 'total-entries)
(println "DEV-STRESS-GSI-REST-SEMANTICS-PASS entries=" entries)
