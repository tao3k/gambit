;;; Stable identity, VM storage growth and moving-root coverage.
(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#global_storage#"
  count roots check i symbol value pages identity-count page-count))
(define count 21000) ; Cross the historical 20000 identity ceiling unchanged.
(define roots (make-vector count))
(define (check value) (if (not value) (error "global storage contract failed")))
(define identity-count
  (c-lambda () unsigned-long "___result=___GSTATE->mem.glo_list.count;"))
(define page-count
  (c-lambda () unsigned-long
    #<<c-end
#ifdef ___SINGLE_VM
___result=0;
#else
___result=___VMSTATE_FROM_PSTATE(___PSTATE)->glos->count;
#endif
c-end
))
(let loop ((i 0))
  (if (< i count)
      (let ((symbol (string->symbol (string-append "global-storage/" (number->string i)))))
        (##make-global-var symbol)
        (vector-set! roots i symbol)
        (##global-var-set! symbol (vector i (cons i 'root)))
        (if (= (modulo i 101) 0)
            (##global-var-primitive-set! symbol (vector 'override i)))
        (if (= (modulo i 997) 0) (##gc))
        (loop (+ i 1)))))
(##gc)
(let loop ((i 0))
  (if (< i count)
      (let* ((symbol (vector-ref roots i)) (value (##global-var-ref symbol)))
        (check (= (vector-ref value 0) i))
        (check (= (car (vector-ref value 1)) i))
        (loop (+ i 1)))))
(check (> (identity-count) 20000))
(write (list 'global-storage-pass 'identities (identity-count) 'scan-pages (page-count)))
(newline)
