;;; One source, domain properties and a separately selected matched cost population.
(declare (standard-bindings) (extended-bindings))
(cond-expand
 (sfun-entry-cost
  (begin
(c-declare "extern int sfun_cost_zero(void);\nextern int sfun_cost_one(___SCMOBJ);\nextern int sfun_cost_many(___SCMOBJ,___SCMOBJ,___SCMOBJ,___SCMOBJ,___SCMOBJ,___SCMOBJ,___SCMOBJ,___SCMOBJ);\n")
(c-define (cost-zero) () int "sfun_cost_zero" "" 1)
(c-define (cost-one a) (scheme-object) int "sfun_cost_one" ""
 (if (= (vector-ref a 0) 0) 1 0))
(c-define (cost-many a b c d e f g h)
 (scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object)
 int "sfun_cost_many" ""
 (if (= (+ (vector-ref a 0) (vector-ref b 0) (vector-ref c 0) (vector-ref d 0)
           (vector-ref e 0) (vector-ref f 0) (vector-ref g 0) (vector-ref h 0)) 28) 1 0))
(define cost-invoke
 (c-lambda (int scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object scheme-object) int
  "___result=___arg1==0 ? sfun_cost_zero() : (___arg1==1 ? sfun_cost_one(___arg2) : sfun_cost_many(___arg2,___arg3,___arg4,___arg5,___arg6,___arg7,___arg8,___arg9));"))
(let* ((args (cdr (command-line))) (arity (if (null? args) 0 (string->number (car args))))
       (a (vector 0)) (b (vector 1)) (c (vector 2)) (d (vector 3))
       (e (vector 4)) (f (vector 5)) (g (vector 6)) (h (vector 7)))
 (if (not (memv arity '(0 1 8))) (error "cost arity must be0/1/8"))
 (write (cons 'SFUN-ENTRY-COST
         (##exec-stats (lambda ()
           (let loop ((i 0))
             (if (= i 4096) i
                 (if (= 1 (cost-invoke arity a b c d e f g h))
                     (loop (+ i 1)) (error "SFUN cost result" i))))))))
 (newline) (write (list 'SFUN-ENTRY-COST-PASS 'arity arity 'calls 4096)) (newline))
))
 (else
  (begin
;;; Complete generated SFUN activation: actual roots, constructor failure,
;;; moving GC, nesting, exceptional return and the existing replay/shrinker.
(c-declare #<<c-end
#include "rc.h"
#include "lifecycle.h"
extern int sfun_entry_callback(___SCMOBJ,___SCMOBJ,int);
extern int sfun_entry_driver(___SCMOBJ,___SCMOBJ,int);
extern int sfun_entry_zero(void);
extern int sfun_entry_bad_result(___SCMOBJ);
extern void sfun_entry_void(___SCMOBJ);
extern ___SCMOBJ sfun_entry_object(___SCMOBJ);
extern int sfun_entry_fault,sfun_entry_banks,sfun_entry_markers;
extern int sfun_entry_custody,sfun_entry_moved;
extern ___SIZE_T sfun_entry_nodes,sfun_entry_borrows;
extern void *sfun_entry_self_root;
c-end
)
(define callback-body #f)
(define root-store-check
 (c-lambda (scheme-object) bool #<<c-end
{
  void *scope=0;
  ___SCMOBJ proc=___MLBL(___C_LBL_sfun_entry_zero);
  ___SCMOBJ status=___begin_sfun(___ps,2,proc,&scope);
  ___result=0;
  if(status==___FIX(___NO_ERR)) {
    ___activation_record *record=___CAST(___activation_record*,scope);
    void *bank=record->roots;
    ___rc_domain *d=___ps->mem.rc_domain_;
    const ___SCMOBJ *extra;
    int ok=___sfun_arg(___ps,scope,1,___arg1)==___FIX(___NO_ERR);
    ok=ok && ___try_set_data_rc(___ps,bank,proc) &&
       !___try_set_data_rc(___ps,bank,___FAL) &&
       !___store_rc_root(___ps,bank,3,___arg1) &&
       !___store_rc_root(0,bank,1,___arg1);
    extra=___borrow_rc_root(___ps,bank);
    ok=ok && extra && !___store_rc_root(___ps,bank,2,___arg1) &&
       ___sfun_arg(___ps,scope,2,___arg1)!=___FIX(___NO_ERR);
    if(extra)___return_rc_root(bank);
    /* A source pointer alone does not prove current source ownership. This
     * confined inconsistent-owner control neither polls nor allocates. */
    ___RC_LOCK(d);d->owner=0;___RC_UNLOCK(d);
    extra=___borrow_rc_root(___ps,bank);
    ok=ok && !extra && !___store_rc_root(___ps,bank,2,___arg1);
    ok=ok && !___EXT(___register_rc)(___PSP bank) &&
       ___sfun_arg(___ps,scope,2,___arg1)!=___FIX(___NO_ERR);
    if(extra)___return_rc_root(bank);
    ___RC_LOCK(d);d->owner=___ps;___RC_UNLOCK(d);
    /* Confined refusal control, not an independent GC phase. This registered
     * cooperative owner does not poll/allocate while the phase is restored. */
    ___RC_LOCK(d);d->phase=___RC_FROZEN;___RC_UNLOCK(d);
    ok=ok && !___store_rc_root(___ps,bank,2,___arg1) &&
       !___borrow_rc_root(___ps,bank) &&
       !___EXT(___register_rc)(___PSP bank) &&
       ___sfun_arg(___ps,scope,2,___arg1)!=___FIX(___NO_ERR);
    ___RC_LOCK(d);d->phase=___RC_OPEN;___RC_UNLOCK(d);
    ok=ok && !___store_rc_root(___ps,bank,2,___arg1) &&
       ___sfun_arg(___ps,scope,2,___arg1)==___FIX(___NO_ERR) &&
       ___CAST(___SCMOBJ*,bank)[0]==___arg1 &&
       ___CAST(___SCMOBJ*,bank)[1]==___arg1;
    ___end_sfun(___ps,scope);
    ___result=ok;
  }
}
c-end
))

(define conversion-failure? #f)
(define caught-conversion? #f)
(c-define (entry-zero) () int "sfun_entry_zero" "" (##gc) 1)
(c-define (entry-bad-result value) (scheme-object) int "sfun_entry_bad_result" ""
 (##gc) value)
(define invoke-bad (c-lambda (scheme-object) int "sfun_entry_bad_result"))
(define wind-balance 0)
(define void-seen #f)
(c-define (entry-void value) (scheme-object) void "sfun_entry_void" ""
 (##gc) (set! void-seen value))
(c-define (entry-object value) (scheme-object) scheme-object "sfun_entry_object" ""
 (##gc) value)
(define invoke-void (c-lambda (scheme-object) void "sfun_entry_void"))
(define invoke-object (c-lambda (scheme-object) scheme-object "sfun_entry_object"))
(c-define (entry-callback first second mode)
          (scheme-object scheme-object int) int "sfun_entry_callback" ""
  (callback-body first second mode))
(define invoke
 (c-lambda (scheme-object scheme-object int) int
  "___result=sfun_entry_callback(___arg1,___arg2,___arg3);"))
(define fixture-action
 (c-lambda (scheme-object scheme-object int) bool #<<c-end
{
  ___rc_domain *d=___ps->mem.rc_domain_;
  ___vm_lifecycle *life=___VMSTATE_FROM_PSTATE(___ps)->lifecycle;
  int id=___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps));
  ___WORD entries=___WORD_LOAD_ACQUIRE(&life->entries[id]);
  ___SCMOBJ ___err;
  int returned=0,value=0,mode=___arg3;
  ___RC_LOCK(d);sfun_entry_nodes=d->nodes;sfun_entry_borrows=d->borrows;___RC_UNLOCK(d);
  sfun_entry_banks=sfun_entry_markers=0;sfun_entry_custody=sfun_entry_moved=0;
  sfun_entry_fault=mode<4 ? mode : (mode==4 ? 2 : (mode==5 ? 3 : 1));
  ___BEGIN_TRY
    value=mode<4 ? sfun_entry_callback(___arg1,___arg2,0) : sfun_entry_zero();returned=1;
  ___END_TRY
  sfun_entry_fault=0;
  ___RC_LOCK(d);
  ___result=d->nodes==sfun_entry_nodes && d->borrows==sfun_entry_borrows &&
    ___WORD_LOAD_ACQUIRE(&life->entries[id])==entries &&
    (mode>=4 ?
      (sfun_entry_banks==0 && sfun_entry_markers==1 &&
       (mode==4 ? !returned && ___err==___FIX(___SFUN_HEAP_OVERFLOW_ERR) :
        returned && value==1 && ___err==___FIX(___NO_ERR) &&
        (mode!=5 || (sfun_entry_custody && !sfun_entry_moved)))) :
    (mode==1 || mode==2 ?
      (!returned && ___err==___FIX(___SFUN_HEAP_OVERFLOW_ERR) &&
       sfun_entry_banks==1 && sfun_entry_markers==(mode==2)) :
      (returned && value==1 && ___err==___FIX(___NO_ERR) &&
       sfun_entry_banks==1 && sfun_entry_markers==1 &&
       (mode!=3 || (sfun_entry_custody && sfun_entry_moved)))));
  ___RC_UNLOCK(d);
}
c-end
))
(define owner-state
 (c-lambda () scheme-object #<<c-end
___rc_domain *d=___ps->mem.rc_domain_;
___RC_LOCK(d);
___result=___FIX(___CAST(___WORD,d->borrows));
___RC_UNLOCK(d);
c-end
))
(define closure-source
 (c-lambda (scheme-object) bool #<<c-end
{
  ___rc_domain *d=___ps->mem.rc_domain_;
  ___SIZE_T nodes=d->nodes,borrows=d->borrows;
  void *source=___EXT(___alloc_rc)(___PSP 0),*scope=0;
  ___SCMOBJ marker=___FAL,err=___FIX(___UNKNOWN_ERR);
  ___result=0;
  if (source && ___try_set_data_rc(___ps,source,___arg1)) {
    sfun_entry_self_root=source;
    err=___EXT(___begin_sfun)(___ps,0,___FAL,&scope);
    sfun_entry_self_root=0;
    if (err==___FIX(___NO_ERR) && ___try_set_data_rc(___ps,source,___FAL)) {
      ___EXT(___release_rc)(source);source=0;
      if (!___EXT(___garbage_collect)(___PSA(___ps) 0)) {
        err=___EXT(___sfun_marker)(___ps,scope,&marker);
        if (err==___FIX(___NO_ERR)) err=___EXT(___call_sfun)(___ps,scope);
        ___result=err==___FIX(___NO_ERR) && ___PSR1==___FIX(2069);
      }
    }
    if (scope) ___EXT(___end_sfun)(___ps,scope);
  }
  if (source) {___try_set_data_rc(___ps,source,___FAL);___EXT(___release_rc)(source);}
  ___RC_LOCK(d);
  ___result=___result && d->nodes==nodes && d->borrows==borrows;
  ___RC_UNLOCK(d);
}
c-end
))
(define revoke-control
 (c-lambda (scheme-object) bool #<<c-end
{
  ___rc_domain *d=___ps->mem.rc_domain_;
  ___SIZE_T nodes,borrows,want_bank;
  ___vm_lifecycle *life=___VMSTATE_FROM_PSTATE(___ps)->lifecycle;
  int id=___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps));
  ___WORD entries=___WORD_LOAD_ACQUIRE(&life->entries[id]);
  ___SCMOBJ marker=___FAL;
  void *scope=0;
  int retained=0;
  ___result=0;
  ___RC_LOCK(d);nodes=d->nodes;borrows=d->borrows;___RC_UNLOCK(d);
  want_bank=!(___TESTTYPE(___arg1,___tSUBTYPED) &&
              ___HD_TYP(___SUBTYPED_HEADER(___arg1))==___PERM);
  if (___EXT(___begin_sfun)(___ps,want_bank ? 1 : 0,___arg1,&scope)==___FIX(___NO_ERR)) {
    if (want_bank && ___EXT(___sfun_arg)(___ps,scope,1,___arg1)!=___FIX(___NO_ERR)) _Exit(76);
    if (___lifecycle_can_handoff(___ps)!=___HANDOFF_BUSY) _Exit(73);
    if (___EXT(___sfun_marker)(___ps,scope,&marker)==___FIX(___NO_ERR)) {
      ___EXT(___kill_sfun_stack_marker)(marker);
      ___EXT(___kill_sfun_stack_marker)(marker);
      ___RC_LOCK(d);
      retained=d->nodes==nodes+want_bank && d->borrows==borrows+want_bank &&
        ___WORD_LOAD_ACQUIRE(&life->entries[id])==entries+2 &&
        ___lifecycle_can_handoff(___ps)==___HANDOFF_BUSY;
      ___RC_UNLOCK(d);
      /* The rejected implementation frees scope during marker kill. Never
       * dereference/finish it when the independent source counts prove loss. */
      if (retained) {
        ___SCMOBJ ignored=___FAL;
        if (___EXT(___sfun_marker)(___ps,scope,&ignored)==___FIX(___NO_ERR) ||
            ___EXT(___call_sfun)(___ps,scope)==___FIX(___NO_ERR)) _Exit(74);
        if (___EXT(___sfun_arg)(___ps,scope,1,___FAL)==___FIX(___NO_ERR)) _Exit(75);
        if (!___EXT(___garbage_collect)(___PSA(___ps) 0)) {
          ___EXT(___end_sfun)(___ps,scope);
          ___RC_LOCK(d);
          ___result=d->nodes==nodes && d->borrows==borrows &&
            ___WORD_LOAD_ACQUIRE(&life->entries[id])==entries;
          ___RC_UNLOCK(d);
        }
      }
    } else ___EXT(___end_sfun)(___ps,scope);
  }
}
c-end
))
;;; A Scheme handler can run while its inner C activation still owns roots.
;;; Returning through this outer marker supplies a real physical exit boundary.
(c-define (entry-driver first second depth)
          (scheme-object scheme-object int) int "sfun_entry_driver" ""
 (let ((before (owner-state)))
  (with-exception-catcher
   (lambda (e)
    (if conversion-failure? (set! caught-conversion? #t))
    (if (not (= (owner-state) (+ before 1)))
        (error "logical escape lost its physical activation root"))
    (##gc)
    (if (not (= (owner-state) (+ before 1)))
        (error "GC lost its escaped physical activation root"))
    1)
   (lambda () (if conversion-failure? (invoke-bad first) (invoke first second depth))))))
(define invoke-owned
 (c-lambda (scheme-object scheme-object int) int
  "___result=sfun_entry_driver(___arg1,___arg2,___arg3);"))
(set! callback-body
 (lambda (first second mode)
  (##gc)
  (if (and (= (car first) 2027) (= (vector-ref second 0) 2029)) 1 0)))
(define (constructors)
 (for-each
  (lambda (mode)
   (if (not (fixture-action (cons 2027 'first) (vector 2029) mode))
       (error "SFUN construction/root/exit contract" mode)))
  '(0 1 2 3 4 5 6)))

(define self (path-expand (car (command-line))))
(define (trace-tag) 'sfun-entry-trace)
(include "root-task-replay.scm")
(define (replay-entry commands fault)
 (let loop ((xs commands) (at 0))
  (if (null? xs)
      (begin (write (list 'root-task-result 'pass at (##current-processor-id)))
             (newline) (exit 0))
      (let* ((row (car xs)) (op (vector-ref row 0))
             (before (owner-state)) (ok #t))
       (set! conversion-failure? (= op 7))
       (set! caught-conversion? #f)
       (set! callback-body
        (lambda (first second depth)
         (dynamic-wind
          (lambda () (set! wind-balance (+ wind-balance 1)))
          (lambda ()
           (##gc)
           (cond ((= op 1) (error "SFUN injected Scheme exception"))
                 ((= op 6)
                  (let ((resume #f) (round 0))
                   (let ((values (map (lambda (x)
                                       (if (= x 2)
                                           (call/cc (lambda (k) (set! resume k) x)) x))
                                     '(1 2 3))))
                    (##gc)
                    (if (not (equal? values '(1 2 3))) (error "SFUN map continuation roots"))
                    (if (< round 2)
                        (begin (set! round (+ round 1)) (resume 2)) 1))))
                 ((and (= op 2) (> depth 0)) (invoke first second (- depth 1)))
                 (else (if (and (= (car first) 2027) (= (vector-ref second 0) 2029)) 1 0))))
          (lambda () (set! wind-balance (- wind-balance 1))))))
       (case op
        ((0 2 6 7) (set! ok (= (invoke-owned (cons 2027 'first) (vector 2029) (vector-ref row 1)) 1)))
        ((1) (set! ok (= (invoke-owned (cons 2027 'first) (vector 2029) 0) 1)))
        ((3) (##gc)))
       (case op
        ((4) (let ((payload (vector 2039)))
               (set! ok (eq? payload (invoke-object payload)))))
        ((5) (let ((payload (vector 2053)))
               (invoke-void payload) (set! ok (eq? payload void-seen)))))
       (if (= op 8)
           (let ((held (vector 2081)))
             (set! ok (revoke-control (lambda () held)))))
       (if (not (and ok (or (not (= op 7)) caught-conversion?) (= wind-balance 0) (= before (owner-state)) (not (and (= fault 1) (= op 3)))))
           (begin (write (list 'root-task-result 'mismatch at op 0)) (newline) (exit 71)))
       (loop (cdr xs) (+ at 1))))))
(define (suite check-constructors?)
 (if (not (root-store-check (vector 2071))) (error "RC writer/borrow authority"))
 (display "RC-WRITER-PASS primary span owner borrow frozen\n")
 (if check-constructors? (constructors))
 (let ((seed 2027) (actions 0))
  (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
  (do ((i 0 (+ i 1))) ((= i 12))
   (let ((commands (append '(#(0 0) #(1 0) #(2 2) #(3 0) #(4 0) #(5 0) #(6 0) #(7 0) #(8 0))
                    (let loop ((n 8))
                     (if (= n 0) '() (cons (vector (next 9) (next 3)) (loop (- n 1))))))))
    (set! actions (+ actions (length commands)))
    (let ((result (trial commands 0)))
     (if (signature result) (error "SFUN native history failed" result
                             (shrink commands 0 (signature result)))))))
  (let* ((commands (append (make-list 6 '#(0 0)) '(#(3 0)) (make-list 6 '#(0 0))))
         (failure (trial commands 1)) (wanted (signature failure))
         (minimal (shrink commands 1 wanted)))
   (if (not (and (equal? wanted '(3 0)) (= (length minimal) 1)
                 (one-minimal? minimal 1 wanted) (not (signature (trial minimal 0)))))
       (error "SFUN replay/shrink control failed" failure minimal))
   (for-each
    (lambda (pair)
     (with-output-to-file (string-append "sfun-entry-" (car pair) ".trace")
      (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
    '(("observation-control" . 1) ("production" . 0)))
   (if (not (and (equal? (signature (trial-file "sfun-entry-observation-control.trace")) wanted)
                 (not (signature (trial-file "sfun-entry-production.trace")))))
       (error "SFUN serialized replay failed")))
  (delete-file input-file)
  (write (list 'SFUN-ENTRY-PBT-PASS 'cases 12 'actions actions 'constructors (if check-constructors? 7 0)
               'shrink-from 13 'shrink-to 1 'control 'observation-mutation)) (newline)))
(let ((args (cdr (command-line))))
 (cond ((null? args) (suite #t))
       ((equal? args '("--properties")) (suite #f))
       ((equal? args '("--nonzero"))
        (if (< (##current-vm-processor-count) 2) (error "nonzero processor required"))
        (let ((worker (make-thread
                       (lambda ()
                        (if (not (= (##current-processor-id) 1)) (error "nonzero owner not acquired"))
                        (if (not (root-store-check (vector 2077))) (error "nonzero RC writer authority"))
                        (display "RC-WRITER-NONZERO-PASS\n")
                        (replay-entry '(#(0 0) #(1 0) #(2 2) #(3 0) #(4 0) #(5 0) #(6 0) #(7 0) #(8 0)) 0)))))
         (##thread-pin! worker (##processor 1))
         (thread-start! worker) (thread-join! worker)))
       ((equal? args '("--constructors")) (constructors) (display "SFUN-CONSTRUCTORS-PASS 7\n"))
       ((equal? args '("--revoke"))
        (let ((held (vector 2063)))
         (if (not (revoke-control (lambda () held)))
             (error "marker revocation lost physical bank ownership")))
        (if (not (revoke-control ((c-lambda () scheme-object
                         "___result=___MLBL(___C_LBL_sfun_entry_zero);"))))
            (error "permanent marker revocation lost physical entry ownership"))
        (display "SFUN-REVOKE-PASS rooted-and-permanent retained-gc-drained\n"))
       ((equal? args '("--closure-source"))
        (let ((held (vector 2069)))
         (if (not (closure-source (lambda () (##gc) (vector-ref held 0))))
             (error "C-closure source transfer lost canonical procedure root")))
        (display "SFUN-CLOSURE-SOURCE-PASS accessor-control transfer gc exit\n"))
       ((and (= (length args) 2) (equal? (car args) "--replay"))
        (let ((x (with-input-from-file (cadr args) read)))
         (if (not (and (list? x) (= (length x) 4) (eq? (car x) (trace-tag))
                       (= (cadr x) 1) (list? (caddr x)) (<= (length (caddr x)) 96)
                       (memv (cadddr x) '(0 1))
                       (let valid ((xs (caddr x)))
                        (or (null? xs)
                            (let ((v (car xs)))
                             (and (vector? v) (= (vector-length v) 2)
                                  (memv (vector-ref v 0) '(0 1 2 3 4 5 6 7 8))
                                  (memv (vector-ref v 1) '(0 1 2)) (valid (cdr xs))))))))
             (error "invalid SFUN trace"))
         (replay-entry (caddr x) (cadddr x))))
       (else (error "unknown SFUN test mode" args))))

)))
