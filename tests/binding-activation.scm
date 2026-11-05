;;; Real binding address/GC/callback properties; reuse root-task replay support.
(declare (standard-bindings) (extended-bindings))
(define self (path-expand (car (command-line))))
(define family 'binding)
(define (trace-tag) 'binding-activation-trace)
(define (trace-file suffix) (string-append "binding-activation-" suffix ".trace"))
(include "root-task-replay.scm")
;;; Binding activation uses the existing root-task trial/replay/shrink driver.
;;; No shadow runtime or independent PBT framework is introduced.
(define binding-payload (vector -1 (cons -1 'binding)))
(define binding-primitive (vector -1))
(define binding-symbol (##make-global-var 'binding-payload))
(c-declare "#include \"mem.h\"\n#include \"rc.h\"\n")
(define binding-observe
 (c-lambda (scheme-object scheme-object scheme-object) bool #<<c-end
___binding_view *view=&___ps->context->binding_view;
___rc_domain *domain=___ps->mem.rc_domain_;
___glo_struct *global=___GLOBALVARSTRUCT(___arg3);
___result=view && view->vm==___VMSTATE_FROM_PSTATE(___ps) &&
 domain && domain->phase==___RC_OPEN && !domain->joined_round &&
 ___WORD_LOAD_ACQUIRE(___binding_global(view->vm,global))==___arg1 &&
 ___binding_primitive(view->vm,global)==(___arg2==___FAL ? ___PRMCELL(global->prm) : ___arg2);
#ifndef ___SINGLE_VM
if (___result) {
  ___glo_struct absent={0};
  absent.val=-1; absent.prm=___FIX(17);
  ___result=___binding_primitive(view->vm,&absent)==___FIX(17);
}
#endif

c-end
))
(define binding-clear
 (c-lambda (scheme-object) void
  "___glo_struct *g=___GLOBALVARSTRUCT(___arg1); ___EXT(___bind_primitive)(___ps,g,___PRMCELL(g->prm));"))
(c-declare "extern int binding_callback_native(int);")
(c-define (binding-callback n) (int) int "binding_callback_native" ""
 (set! binding-payload (vector n (cons n 'binding)))
 (##gc)
 (if (< n 0) (error "binding callback unwind" n) n))
(define binding-call (c-lambda (int) int "___result=binding_callback_native(___arg1);"))
(define (replay-binding commands fault)
 (set! binding-payload (vector -1 (cons -1 'binding)))
 (set! binding-primitive (vector -1))
 (##global-var-primitive-set! binding-symbol binding-primitive)
 (let loop ((xs commands) (at 0) (expected -1))
  (if (null? xs)
   (begin (write (list 'root-task-result 'pass at (##current-processor-id))) (newline) (exit 0))
   (let* ((row (car xs)) (op (vector-ref row 0)) (n (vector-ref row 1))
          (next expected) (callback-ok #t))
    (case op
     ((0) (set! binding-payload (vector n (cons n 'binding))) (set! next n))
     ((1) (##gc))
     ((2) (set! next (abs n)) (set! callback-ok (= (binding-call next) next)))
     ((3) (set! next (- (+ (abs n) 1)))
          (set! callback-ok
           (with-exception-catcher (lambda (e) #t)
            (lambda () (binding-call next) #f))))
     ((4) (if (= (vector-ref row 2) 0)
               (begin (set! binding-primitive (vector n))
                      (##global-var-primitive-set! binding-symbol binding-primitive))
               (begin (binding-clear binding-symbol) (set! binding-primitive #f)))))
    (if (not (and callback-ok (= (vector-ref binding-payload 0) next)
                  (= (car (vector-ref binding-payload 1)) next)
                  (binding-observe binding-payload binding-primitive binding-symbol)
                  (not (and (= fault 1) (= op 1)))))
     (begin (write (list 'root-task-result 'mismatch at op 0)) (newline) (exit 71)))
    (loop (cdr xs) (+ at 1) next)))))
(define (binding-suite)
 (set! family 'binding) (set! trials 0)
 (let ((seed 1993) (actions 0))
  (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
  (define (noise n) (if (= n 0) '() (cons (vector (next 6) (- (next 4) 1) (next 2)) (noise (- n 1)))))
  (define chain '(#(0 2 0) #(4 1 0) #(1 0 0) #(2 2 0) #(3 1 0) #(4 0 1) #(1 0 0) #(5 0 0)))
  (do ((i 0 (+ i 1))) ((= i 12))
   (let* ((commands (append (noise 6) chain (noise 6))) (result (trial commands 0)))
    (set! actions (+ actions (length commands)))
    (if (signature result) (error "binding activation history failed" result (shrink commands 0 (signature result))))))
  (let* ((commands (append (make-list 6 '#(5 0 0)) '(#(1 0 0)) (make-list 6 '#(5 0 0))))
         (failure (trial commands 1)) (wanted (signature failure)) (minimal (shrink commands 1 wanted)))
   (if (not (and (equal? wanted '(1 0)) (= (length minimal) 1)
                 (one-minimal? minimal 1 wanted) (not (signature (trial minimal 0)))))
    (error "binding control did not shrink" failure minimal))
   (for-each (lambda (pair)
    (with-output-to-file (trace-file (car pair))
     (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
    '(("observation-control" . 1) ("production" . 0)))
   (if (not (and (equal? (signature (trial-file (trace-file "observation-control"))) wanted)
                 (not (signature (trial-file (trace-file "production"))))))
    (error "binding serialized replay failed"))
   (write (list 'BINDING-ACTIVATION-PBT-PASS 'cases 12 'actions actions 'shrink-from 13 'shrink-to 1
                'control 'observation-mutation 'callback 'normal-and-unwind)) (newline))
  (delete-file input-file)))

(define (binding-trace? x)
 (and (list? x) (= (length x) 4) (eq? (car x) 'binding-activation-trace)
      (integer? (cadr x)) (<= 1 (cadr x) 3) (list? (caddr x))
      (<= (length (caddr x)) 96) (memv (cadddr x) '(0 1))
      (let loop ((xs (caddr x)))
       (or (null? xs)
           (let ((row (car xs)))
            (and (vector? row) (= (vector-length row) 3)
                 (integer? (vector-ref row 0)) (<= 0 (vector-ref row 0) 5)
                 (memv (vector-ref row 1) '(-1 0 1 2))
                 (memv (vector-ref row 2) '(0 1)) (loop (cdr xs))))))))
(let ((args (cdr (command-line))))
 (cond ((or (null? args) (equal? args '("--binding-activation"))) (binding-suite))
       ((equal? args '("--nonzero"))
        (if (< (##current-vm-processor-count) 2) (error "nonzero processor required"))
        (let ((worker (make-thread
                       (lambda ()
                        (if (not (= (##current-processor-id) 1))
                         (error "nonzero owner was not acquired"))
                        (replay-binding '(#(0 2 0) #(4 1 0) #(1 0 0) #(2 2 0) #(3 1 0) #(4 0 1) #(1 0 0) #(5 0 0)) 0)))))
         (##thread-pin! worker (##processor 1))
         (thread-start! worker)
         (thread-join! worker)))
       ((and (= (length args) 2) (equal? (car args) "--replay"))
        (let ((trace (call-with-input-file (cadr args) read)))
         (if (not (binding-trace? trace)) (error "invalid binding trace"))
         (do ((i 0 (+ i 1))) ((= i (cadr trace))) (##gc))
         (replay-binding (caddr trace) (cadddr trace))))
       (else (error "usage: binding-activation [--replay TRACE]"))))
