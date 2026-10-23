;;; Compiler-side frame contract and producer fixtures for frame-contract.c.
;;; Run with GSC (the constructor is part of the compiler, not the interpreter).
(define checks 0)
(define fixtures 0)
(define fixture-path (getenv "FRAME_SPEC_FIXTURES"))
(define fixture-port (and fixture-path (open-output-file fixture-path)))
(define (check p)
  (set! checks (+ checks 1))
  (if (not p) (error "frame-spec check" checks)))
(define old-regs c#targ-nb-gvm-regs)
(define old-error c#compiler-internal-error)
(define (rejected? kind fs link roots)
  (with-exception-catcher
   (lambda (e) #t)
   (lambda () (c#targ-make-frame-spec kind fs link roots) #f)))

(dynamic-wind
 (lambda ()
   ;; Only the diagnostic sink is substituted; production validation is used.
   (set! c#compiler-internal-error (lambda args (error "invalid frame" args))))
 (lambda ()
   (if fixture-port
       (display "static const struct frame_case cases[] = {\n" fixture-port))
   (for-each
    (lambda (regs)
      (set! c#targ-nb-gvm-regs (lambda () regs))
      (for-each
       (lambda (kind)
         (for-each
          (lambda (fs)
            ;; Independent integer arithmetic; do not call target layout helpers.
            (let ((actual (if (eq? kind 'internal)
                              (+ (* 4 (quotient (+ fs 3) 4))
                                 (- (* 4 (quotient (+ regs 7) 4)) 3))
                              fs)))
              (if (> actual 0)
                  (for-each
                   (lambda (pattern)
                     (let* ((roots (case pattern
                                     ((0) 0)
                                     ((1) (if (= actual 1) 1
                                              (+ 1 (expt 2 (- actual 1)))))
                                     (else (- (expt 2 actual) 1))))
                            (link (- actual 1))
                            (spec (c#targ-make-frame-spec kind fs link roots))
                            (ofd? (> actual 20))
                            (chunks (c#targ-frame-spec-chunks spec)))
                       (check (= (c#targ-frame-spec-actual-fs spec) actual))
                       (check (= (c#targ-frame-spec-stored-fs spec) fs))
                       (check (= (c#targ-frame-spec-link spec) link))
                       (check (= (c#targ-frame-spec-gc-map spec) roots))
                       (check (eq? (c#targ-frame-spec-kind spec) kind))
                       (check (eq? (c#targ-frame-spec-out-of-line? spec) ofd?))
                       (check (= (length chunks) (if ofd? (quotient (+ actual 31) 32) 0)))
                       (if ofd?
                           (check (= roots
                                     (let loop ((xs (reverse chunks)) (acc 0))
                                       (if (null? xs) acc
                                           (loop (cdr xs) (+ (* acc 4294967296) (car xs))))))))
                       (if fixture-port
                           (begin
                             (display "{" fixture-port)
                             (for-each
                              (lambda (x) (write x fixture-port) (display "," fixture-port))
                              (list regs (case kind ((normal) 1) ((internal) 2) (else 3))
                                    fs link actual pattern (if ofd? 1 0)))
                             (display "{" fixture-port)
                             (let loop ((xs (if ofd? chunks (list roots))))
                               (if (pair? xs)
                                   (begin (display (number->string (car xs)) fixture-port)
                                          (display "U," fixture-port) (loop (cdr xs)))))
                             (display "}},\n" fixture-port)
                             (set! fixtures (+ fixtures 1))))))
                   '(0 1 2)))))
          '(0 1 8 20 21 31 32 33 63 64 65 127)))
       '(normal task internal)))
    '(3 5 25))
   (for-each (lambda (args) (check (apply rejected? args)))
             '((other 8 0 0) (normal -1 0 0) (normal 8 -1 0)
               (normal 8 8 0) (normal 8 0 256) (normal 16384 0 0)
               (normal 8 0 -1) (normal 1.5 0 0) (normal 8 0 1.5)
               (normal 8 1.5 0) (normal 0 0 0)))
   (if fixture-port (display "};\n" fixture-port)))
 (lambda ()
   (set! c#targ-nb-gvm-regs old-regs)
   (set! c#compiler-internal-error old-error)
   (if fixture-port (close-output-port fixture-port))))
(display "FRAME-SPEC-PASS ") (write checks)
(display " checks; ") (write fixtures) (display " fixtures\n")
