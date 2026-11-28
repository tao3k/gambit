;;;============================================================================

;;; File: "combinators.scm"

;;; Copyright (c) 2026 by Gambit Contributors, All Rights Reserved.

;;;============================================================================

;;; Structured Fork-Join Combinators (Exception-Quiescent Join)

(define (default-grain n workers)
  (let* ((chunks (##fx* workers 4))
         (g (if (##fx> chunks 0) (##fxquotient n chunks) n)))
    (if (##fx> g 1) g 1)))

(define (parallel-vector-map fn vec #!optional (grain #f))
  (if (not (##procedure? fn))
      (error "parallel-vector-map: expected procedure" fn))
  (if (not (##vector? vec))
      (error "parallel-vector-map: expected vector" vec))
  (let* ((n (##vector-length vec))
         (out (##make-vector n #f)))
    (if (##fx= n 0)
        out
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (if (or (##fx<= w 1) (##fx<= n g))
              (let seq ((i 0))
                (if (##fx< i n)
                    (begin
                      (##vector-set! out i (fn (##vector-ref vec i)))
                      (seq (##fx+ i 1)))
                    out))
              (letrec ((run-range
                        (lambda (lo hi)
                          (if (##fx<= (##fx- hi lo) g)
                              (let loop ((i lo))
                                (if (##fx< i hi)
                                    (begin
                                      (##vector-set! out i (fn (##vector-ref vec i)))
                                      (loop (##fx+ i 1)))))
                              (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                     (right (make-future (lambda () (run-range mid hi)) pool))
                                     (left-err #f)
                                     (has-err #f))
                                (with-exception-catcher
                                 (lambda (e) (set! left-err e) (set! has-err #t))
                                 (lambda () (run-range lo mid)))
                                (if has-err
                                    (begin
                                      (with-exception-catcher
                                       (lambda (_) #f)
                                       (lambda () (future-force right)))
                                      (raise left-err))
                                    (future-force right)))))))
                (run-range 0 n)
                out))))))

(define (parallel-map fn lst #!optional (grain #f))
  (if (not (##procedure? fn))
      (error "parallel-map: expected procedure" fn))
  (if (##null? lst)
      '()
      (if (not (##pair? lst))
          (error "parallel-map: expected list" lst)
          (##vector->list (parallel-vector-map fn (##list->vector lst) grain)))))

(define (parallel-for-each fn lst #!optional (grain #f))
  (if (not (##procedure? fn))
      (error "parallel-for-each: expected procedure" fn))
  (if (##null? lst)
      (##void)
      (if (not (##pair? lst))
          (error "parallel-for-each: expected list" lst)
          (let* ((vec (##list->vector lst))
                 (n (##vector-length vec))
                 (pool (get-active-pool))
                 (w (macro-work-stealing-pool-nworkers pool))
                 (g (if (and (##fixnum? grain) (##fx> grain 0))
                        grain
                        (default-grain n w))))
            (if (or (##fx<= w 1) (##fx<= n g))
                (let seq ((i 0))
                  (if (##fx< i n)
                      (begin (fn (##vector-ref vec i)) (seq (##fx+ i 1)))
                      (##void)))
                (letrec ((run-range
                          (lambda (lo hi)
                            (if (##fx<= (##fx- hi lo) g)
                                (let loop ((i lo))
                                  (if (##fx< i hi)
                                      (begin (fn (##vector-ref vec i)) (loop (##fx+ i 1)))))
                                (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                       (right (make-future (lambda () (run-range mid hi)) pool))
                                       (left-err #f)
                                       (has-err #f))
                                  (with-exception-catcher
                                   (lambda (e) (set! left-err e) (set! has-err #t))
                                   (lambda () (run-range lo mid)))
                                  (if has-err
                                      (begin
                                        (with-exception-catcher
                                         (lambda (_) #f)
                                         (lambda () (future-force right)))
                                        (raise left-err))
                                      (future-force right)))))))
                  (run-range 0 n)
                  (##void)))))))

(define (parallel-reduce combine identity seq-or-vec #!optional (grain #f))
  (if (not (##procedure? combine))
      (error "parallel-reduce: expected procedure" combine))
  (if (not (or (##vector? seq-or-vec) (##null? seq-or-vec) (##pair? seq-or-vec)))
      (error "parallel-reduce: expected vector or list" seq-or-vec))
  (let* ((vec (if (##vector? seq-or-vec) seq-or-vec (##list->vector seq-or-vec)))
         (n (##vector-length vec)))
    (if (##fx= n 0)
        identity
        (let* ((pool (get-active-pool))
               (w (macro-work-stealing-pool-nworkers pool))
               (g (if (and (##fixnum? grain) (##fx> grain 0))
                      grain
                      (default-grain n w))))
          (letrec ((reduce-range
                    (lambda (lo hi)
                      (if (or (##fx<= w 1) (##fx<= (##fx- hi lo) g))
                          (let loop ((i lo) (acc identity))
                            (if (##fx< i hi)
                                (loop (##fx+ i 1) (combine acc (##vector-ref vec i)))
                                acc))
                          (let* ((mid (##fx+ lo (##fxarithmetic-shift-right (##fx- hi lo) 1)))
                                 (right (make-future (lambda () (reduce-range mid hi)) pool))
                                 (left-err #f)
                                 (has-err #f)
                                 (lv #f))
                            (with-exception-catcher
                             (lambda (e) (set! left-err e) (set! has-err #t))
                             (lambda () (set! lv (reduce-range lo mid))))
                            (if has-err
                                (begin
                                  (with-exception-catcher
                                   (lambda (_) #f)
                                   (lambda () (future-force right)))
                                  (raise left-err))
                                (combine lv (future-force right))))))))
            (reduce-range 0 n))))))

;;;============================================================================
