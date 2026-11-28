(##namespace ("gambit#tests#smp#gc#scheme_index_gc#" keys table missing before after))
;; Run with the declared producer's GSI and default heap, from its source root.
;; GC may repair references; it must preserve this Scheme-owned hash index.
(define keys
  (let loop ((i 0) (xs '()))
    (if (= i 32)
        xs
        (loop (+ i 1)
              (cons (string-append "scheme-index-key-" (number->string i)) xs)))))
(define table (make-table))
(for-each (lambda (key) (table-set! table key (string-length key))) keys)
(define (missing)
  (let loop ((xs keys) (n 0))
    (if (null? xs)
        n
        (loop (cdr xs)
              (+ n (if (equal? (table-ref table (string-append (car xs) "") #f)
                               (string-length (car xs)))
                       0
                       1))))))
(define before (missing))
(write (list 'before-gc 'missing before)) (newline)
(if (not (= before 0)) (exit 2))
(##gc)
(define after (missing))
(write (list 'after-gc 'missing after)) (newline)
(if (not (= after 0)) (exit 1))
(display "gambit.smp.gc.hash-index.scheme-owner PASS\n")
