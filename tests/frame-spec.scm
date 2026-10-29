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

;;; The CPU backend and C consumers must describe the same physical fields.
;;; Reuse the existing fixture channel: C compiles these against real offsetof,
;;; independently of the Scheme target's word-coordinate calculation.
(if fixture-path
    (let ((out (open-output-file (list path: fixture-path append: #t)))
          (serial 0))
      (define (offset-check type member expected . element-index)
        (set! serial (+ serial 1))
        (display "typedef char execution_layout_" out) (write serial out)
        (display "[(offsetof(" out) (display type out) (display "," out)
        (display member out) (display ")" out)
        ;; MSVC C does not accept an array-element offsetof as an integer
        ;; constant expression. Use the array member's offset and its actual
        ;; element size; keep the independently computed expected coordinate.
        (if (pair? element-index)
            (begin
              (display "+" out) (write (car element-index) out)
              (display "*sizeof(((" out) (display type out)
              (display "*)0)->" out) (display member out)
              (display "[0])" out)))
        (display "==" out) (write expected out)
        (display ")?1:-1];\n" out))
      (display "#include <stddef.h>\n" out)
      (for-each
       (lambda (target-maker)
         (let* ((target (target-maker))
                (cgc (_codegen#make-codegen-context)))
           (_codegen#codegen-context-target-set! cgc target)
           (let* ((width (c#get-word-width cgc))
                  (bias (if (memq (c#get-arch-name cgc) '(arm RV32I RV64I))
                            width 0)))
             (display "#if ___WS == " out) (write width out) (newline out)
             (for-each
              (lambda (field)
                (let* ((root? (eq? (cadr field) 'context))
                       (loc (if root?
                                (c#get-execution-context-field cgc (car field))
                                (c#get-processor-state-field cgc (car field))))
                       (opnd (car loc)))
                  (check (= (cdr loc) (* 8 width)))
                  (if (eq? (cadr field) 'context)
                      (begin
                        (offset-check "___processor_state_struct" "context"
                                      (- (c#mem-opnd-offset
                                          (car (c#get-processor-state-field cgc 'context))) bias))
                        (apply offset-check "___execution_context"
                               (caddr field) opnd (cdddr field)))
                      (offset-check "___processor_state_struct" (caddr field)
                                    (- (c#mem-opnd-offset opnd) bias)))))
              '((stack-trip carrier "stack_trip")
                (stack-limit context "stack_limit") (frame-pointer context "fp")
                (stack-start context "stack_start") (stack-break context "stack_break")
                (heap-limit carrier "heap_limit") (heap-pointer context "hp")
                (gvm-reg0 context "r" 0) (gvm-reg1 context "r" 1)
                (gvm-reg2 context "r" 2) (gvm-reg3 context "r" 3)
                (gvm-reg4 context "r" 4) (program-counter context "pc")
                (nargs carrier "na") (saved-obj0 context "saved" 0)
                (saved-obj1 context "saved" 1) (saved-obj2 context "saved" 2)
                (type-cache0 context "type_cache" 0) (type-cache1 context "type_cache" 1)
                (handler_sfun_conv_error carrier "handler_sfun_conv_error")
                (handler_cfun_conv_error carrier "handler_cfun_conv_error")
                (handler_stack_limit carrier "handler_stack_limit")
                (handler_heap_limit carrier "handler_heap_limit")
                (handler_not_proc carrier "handler_not_proc")
                (handler_not_proc_glo carrier "handler_not_proc_glo")
                (handler_wrong_nargs carrier "handler_wrong_nargs")
                (handler_get_rest carrier "handler_get_rest")
                (handler_get_key carrier "handler_get_key")
                (handler_get_key_rest carrier "handler_get_key_rest")
                (handler_force carrier "handler_force")
                (handler_return_to_c carrier "handler_return_to_c")
                (handler_break carrier "handler_break")
                (internal_return carrier "internal_return")
                (dynamic_env_bind_return carrier "dynamic_env_bind_return")
                (temp1 carrier "temp1") (temp2 carrier "temp2")
                (temp3 carrier "temp3") (temp4 carrier "temp4")))
             (display "#ifdef ___SUPPORT_LOWLEVEL_EXEC\n" out)
             (for-each
              (lambda (field)
                (let* ((loc (car (c#get-processor-state-field cgc (car field))))
                       (expected (- (c#mem-opnd-offset loc) bias)))
                  (set! serial (+ serial 1))
                  (display "typedef char execution_layout_" out) (write serial out)
                  (display "[((ptrdiff_t)offsetof(___aligned_processor_state_struct,aligned_llpstate.llpstate." out)
                  (display (cadr field) out)
                  (display ")-(ptrdiff_t)offsetof(___aligned_processor_state_struct,pstate)==" out)
                  (write expected out) (display ")?1:-1];\n" out)))
              '((entry-pc "entry_pc") (saved-r1 "saved_r1")
                (return-stack-pointer "return_sp") (return-handler "return_handler")))
             (display "#endif\n#endif\n" out))))
       (list c#x86-32-target c#x86-64-target c#arm-target
             c#riscv-32-target c#riscv-64-target))
      (close-output-port out)
      (display "EXECUTION-LAYOUT-FIXTURES ") (write serial) (newline)))
