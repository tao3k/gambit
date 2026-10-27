;;; gambit.smp.gc.root-task: native replay, independent oracle and shrinking.
;;; RC, VM, bank and stack origins share this generator, oracle, replay and shrink driver.
;;; Each replay is a fresh process. No Scheme allocation while a source is frozen.
(c-declare #<<c-end
#include "rc.h"
#include <stdio.h>
#include <stdlib.h>
static void *root_task_bytes;
c-end
)
(define prepare-source
  (c-lambda () bool "root_task_bytes=___EXT(___alloc_rc)(___PSA(___PSTATE) 1); ___result=root_task_bytes!=0;"))
(define replay-native
  (c-lambda (scheme-object scheme-object int int) void #<<c-end
___processor_state ps=___PSTATE;
___rc_domain *d=ps->mem.rc_domain_;
___UWORD base, receipt;
___root_task local_task, *task;
___execution_context *bank=ps->context;
___SCMOBJ commands=___arg1, expected_rows=___arg2;
int mutation=___arg3;
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
___WORD alien_source=0;
int family=___arg4;
int i,n=___INT(___VECTORLENGTH(commands));
___RC_LOCK(d);
base=d->task.epoch;
if(d->phase!=___RC_OPEN || d->task.state!=___ROOT_DONE || d->task.scan_leases!=0) {
  ___RC_UNLOCK(d); printf("(root-task-result precondition 0)\n"); fflush(stdout); _Exit(72);
}
{
  ___rc_header *h;
  for(h=d->head.next;h!=&d->head;h=h->next) if(h->data!=___FAL) {
    ___RC_UNLOCK(d); printf("(root-task-result precondition 1)\n"); fflush(stdout); _Exit(72);
  }
}
___RC_UNLOCK(d);
if(family) {
  if(vm->processor_count!=1) { printf("(root-task-result precondition 2)\n"); fflush(stdout); _Exit(72); }
  /* Snapshot C arguments before touching the register bank. No Scheme
   * allocation/callback/return follows; each trial destroys its child image. */
  if(family==1) {
    ___SCMOBJ *cells=___BODY0_AS(___VM_SCMOBJ(vm),___tSUBTYPED);
    for(i=0;i<___VM_SIZE;i++) cells[i]=___FAL;
  } else if(family==2) {
    ___SCMOBJ *cells=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank->processor_scmobj,___WS)),___tSUBTYPED);
    for(i=0;i<sizeof(bank->r)/sizeof(*bank->r);i++) bank->r[i]=___FAL;
    for(i=0;i<sizeof(bank->saved)/sizeof(*bank->saved);i++) bank->saved[i]=___FAL;
    for(i=0;i<sizeof(bank->type_cache)/sizeof(*bank->type_cache);i++) bank->type_cache[i]=___FAL;
    for(i=0;i<___PROCESSOR_SIZE;i++) cells[i]=___FAL;
  } else {
    /* Control replay uses an empty break anchor, not fabricated frame bodies.
     * Full active/captured frames are exercised by the Scheme histories below.
     * No Scheme allocation, callback or return may follow this reset. */
    bank->fp=bank->stack_break;
    ___FP_STK(bank->stack_break,-___BREAK_FRAME_NEXT)=___END_OF_CONT_MARKER;
  }
  ___root_task_init(&local_task,base);
}
task=family?&local_task:&d->task;
for(i=0;i<n;i++) {
  ___SCMOBJ row=___VECTORELEM(commands,i), expected=___VECTORELEM(expected_rows,i);
  int op=___INT(___VECTORELEM(row,0)), delta=___INT(___VECTORELEM(row,1));
  ___processor_state actor=___INT(___VECTORELEM(row,2))==0?ps:0;
  ___UWORD key=base+delta;
  long observed[5];
  int accepted=0,j;
  /* Calibrated adapter mutation: production finish must reject the stale key.
   * The oracle remains unchanged; this is not a production runtime defect. */
  if(mutation==1 && op==3 && delta==1 && actor==ps) --key;
  if(family==1) switch(op) {
  case 0: accepted=___root_task_publish_vm(task,vm,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_vm(task,actor,key); break;
  case 2: accepted=___root_task_scan_vm(task,actor,key); break;
  case 3: accepted=___root_task_finish_vm(task,actor,key); break;
  case 4: accepted=___root_task_publish_vm(task,___CAST(___virtual_machine_state,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_vm(task,actor,key); break;
  } else if(family==2) switch(op) {
  case 0: accepted=___root_task_publish_bank(task,bank,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_bank(task,actor,key); break;
  case 2: accepted=___root_task_scan_bank(task,actor,key); break;
  case 3: accepted=___root_task_finish_bank(task,actor,key); break;
  case 4: accepted=___root_task_publish_bank(task,___CAST(___execution_context*,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_bank(task,actor,key); break;
  } else if(family==3) switch(op) {
  case 0: accepted=___root_task_publish_stack(task,bank,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_stack(task,actor,key); break;
  case 2: accepted=___root_task_scan_stack(task,actor,key); break;
  case 3: accepted=___root_task_finish_stack(task,actor,key); break;
  case 4: accepted=___root_task_publish_stack(task,___CAST(___execution_context*,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_stack(task,actor,key); break;
  } else switch(op) {
  case 0: accepted=___root_task_publish(d,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim(d,actor,key); break;
  case 2: accepted=___root_task_scan(d,actor,key); break;
  case 3: accepted=___root_task_finish(d,actor,key); break;
  case 4: accepted=___rc_prepare_cleanup(ps); if(accepted) ___rc_cancel_cleanup(ps); break;
  case 5: accepted=___root_task_completed(d,actor,key); break;
  }
  ___RC_LOCK(d);
  observed[0]=accepted; observed[1]=task->state;
  observed[2]=family?(task->origin.kind!=___ROOT_NONE):d->phase;
  observed[3]=task->scan_leases; observed[4]=task->epoch-base;
  ___RC_UNLOCK(d);
  for(j=0;j<5;j++) if(observed[j]!=___INT(___VECTORELEM(expected,j))) {
    printf("(root-task-result mismatch %d %d %d %ld %ld (%ld %ld %ld %ld %ld))\n",i,op,j,
      (long)___INT(___VECTORELEM(expected,j)),observed[j],observed[0],observed[1],observed[2],observed[3],observed[4]);
    fflush(stdout); _Exit(71);
  }
}
printf("(root-task-result pass %d)\n",n); fflush(stdout);
/* Prefixes may intentionally retain a claim/lease. Never reset that state in
 * process merely to shrink another trial. The OS reclaims this child image. */
_Exit(0);
c-end
))

;;; The oracle describes externally observable requests. SCANNED is the native
;;; refinement cut after the real scanner, before root_dispatch.finish.
(define family 'rc)
(define (trace-tag)
  (case family ((vm) 'vm-root-task-trace) ((bank) 'bank-root-task-trace) ((stack) 'stack-root-task-trace)
    ((continuation) 'continuation-history)
    (else 'root-task-trace)))
(define (trace-file suffix)
  (string-append (case family ((vm) "vm-root-task-")
                  ((bank) "bank-root-task-") ((stack) "stack-root-task-")
                  ((continuation) "continuation-history-") (else "root-task-")) suffix ".trace"))
(define (oracle commands)
  (let ((state (if (eq? family 'rc) 5 0)) (phase 0) (lease 0) (epoch 0))
    (list->vector
     (map
      (lambda (row)
        (let* ((op (vector-ref row 0)) (key (vector-ref row 1))
               (owner (= (vector-ref row 2) 0))
               (current (and owner (= key epoch))) (accepted #f))
          (case op
            ((0)
             (cond ((and owner (= phase 0) (= key epoch))
                    (set! epoch (+ epoch 1)) (set! phase 1)
                    (set! lease 1) (set! state 1) (set! accepted #t))
                   ((and owner (= phase 1) (= key (- epoch 1)))
                    (set! accepted #t))))
            ((1) (if (and current (= phase 1) (= state 1))
                     (begin (set! state 2) (set! accepted #t))))
            ((2) (if (and current (= phase 1) (= state 2))
                     (begin (set! state 4) (set! accepted #t))))
            ((3) (if (and current (= phase 1) (or (= state 4) (= state 5)))
                     (begin (set! state 5) (set! lease 0) (set! accepted #t))))
            ((4) (set! accepted (and (eq? family 'rc) (= phase 0))))
            ((5) (set! accepted (and current (= state 5) (= lease 0)))))
          (vector (if accepted 1 0) state phase lease epoch)))
      commands))))

(define (trace? x)
  (and (list? x) (= (length x) 4) (memq (car x) '(root-task-trace vm-root-task-trace bank-root-task-trace stack-root-task-trace continuation-history))
       (integer? (cadr x)) (<= 1 (cadr x) 3) (list? (caddr x))
       (<= (length (caddr x)) 96) (memv (cadddr x) '(0 1))
       (let loop ((xs (caddr x)))
         (or (null? xs)
             (let ((r (car xs)))
               (and (vector? r) (= (vector-length r) 3)
                    (integer? (vector-ref r 0)) (<= 0 (vector-ref r 0) 5)
                    (memv (vector-ref r 1) '(-1 0 1 2))
                    (memv (vector-ref r 2) '(0 1)) (loop (cdr xs))))))))
(define (replay trace)
  (if (not (trace? trace)) (error "invalid structured root-task trace"))
  (set! family (case (car trace) ((vm-root-task-trace) 'vm)
                 ((bank-root-task-trace) 'bank) ((stack-root-task-trace) 'stack)
                 ((continuation-history) 'continuation) (else 'rc)))
  (if (not (prepare-source)) (error "root-task source allocation failed"))
  (do ((i 0 (+ i 1))) ((= i (cadr trace))) (##gc))
  (let ((commands (caddr trace)))
    (if (eq? family 'continuation)
        (replay-continuation commands (cadddr trace))
        (replay-native (list->vector commands) (oracle commands) (cadddr trace)
                       (case family ((vm) 1) ((bank) 2) ((stack) 3) (else 0))))))

(define self (car (command-line)))
(define input-file "root-task-input.dat")
(define trials 0)
(define (trial commands fault)
  (set! trials (+ trials 1))
  (with-output-to-file input-file
    (lambda () (write (list (trace-tag) 1 commands fault)) (newline)))
  (let* ((port (open-input-process
                (list path: self arguments: (list "-:p1" "--replay" input-file)
                      stderr-redirection: #t)))
         (result (with-exception-catcher (lambda (e) '(root-task-result runtime-error))
                   (lambda () (read port))))
         (status (process-status port)))
    (close-input-port port)
    (cond ((and (list? result) (>= (length result) 3)
                (eq? (car result) 'root-task-result))
           (cond ((and (eq? (cadr result) 'pass) (= status 0)) result)
                 ((and (eq? (cadr result) 'mismatch) (= status (arithmetic-shift 71 8))) result)
                 (else (error "native replay failed outside property oracle" status result))))
          (else (error "malformed native replay outcome" status result)))))
(define (signature result)
  (and (eq? (cadr result) 'mismatch) (list (list-ref result 3) (list-ref result 4))))
(define (take xs n) (if (= n 0) '() (cons (car xs) (take (cdr xs) (- n 1)))))
(define (drop xs n) (if (= n 0) xs (drop (cdr xs) (- n 1))))
(define (remove-range xs from n) (append (take xs from) (drop xs (+ from n))))
(define (shrink commands fault wanted)
  ;; Chunk deletion followed by a deletion-1-minimality check. Expected results
  ;; are recomputed after each deletion, preserving meaningful preconditions.
  (let size-loop ((xs commands) (size (max 1 (quotient (length commands) 2))))
    (let try ((at 0))
      (cond ((> (+ at size) (length xs))
             (if (= size 1) xs (size-loop xs (max 1 (quotient size 2)))))
            (else
             (let ((candidate (remove-range xs at size)))
               (if (equal? (signature (trial candidate fault)) wanted)
                   (size-loop candidate (min size (max 1 (length candidate))))
                   (try (+ at 1)))))))))
(define (one-minimal? commands fault wanted)
  (let loop ((i 0))
    (or (= i (length commands))
        (and (not (equal? (signature (trial (remove-range commands i 1) fault)) wanted))
             (loop (+ i 1))))))

(define (suite)
  (set! trials 0)
  (let ((state 173) (actions 0))
    (define (next n)
      (set! state (modulo (+ (* state 48271) 17) 2147483647)) (modulo state n))
    (define (noise n)
      (if (= n 0) '()
          (cons (vector (next 6) (list-ref '(-1 0 1 2) (next 4)) (next 2))
                (noise (- n 1)))))
    (define chain (list (vector 0 0 0) (vector 1 1 0) (vector 2 1 0) (vector 3 1 0)))
    (do ((sample 0 (+ sample 1))) ((= sample 24))
      (let* ((commands (append (noise 16) chain (noise 16)))
             (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "real root-task implementation property failed" result minimal)))))
    (write (list 'ROOT-TASK-PBT-PASS 'family family 'seed 173 'cases 24 'actions actions)) (newline)
    ;; A known stale-finish invocation mutation must be detected and reduced
    ;; against the same real C implementation, never a copied simulator.
    (let* ((noisy (append (make-list 12 (vector 5 0 0)) chain
                          (make-list 8 (vector 4 0 0))))
           (failure (trial noisy 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(3 0))) (error "stale-finish negative control missed" failure))
      (let* ((minimal (shrink noisy 1 wanted))
             (replayed (trial minimal 1))
             (minimal? (one-minimal? minimal 1 wanted)))
        (if (not (and (= (length minimal) 4) minimal?
                      (equal? (signature replayed) wanted)
                      (equal? (list-ref replayed 7) '(0 4 1 1 1))))
            (error "native shrink/replay certificate failed" minimal replayed))
        (with-output-to-file (trace-file "minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (write (list 'ROOT-TASK-SHRINK-PASS 'family family 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'trials trials))
        (newline)))
    (delete-file input-file)
    (display "ROOT-TASK-REPLAY-PASS\n") (force-output)))

;;; A semantic history uses the same typed trace, fresh-process replay and
;;; deletion shrinker. Its oracle observes dynamic-wind entry/exit and result
;;; graph identity, never a copy of the runtime's frame or GC algorithm.
(define (replay-continuation commands fault)
  (let ((saved #f) (deliver #f) (generation 0) (seed 0)
        (before 0) (after 0) (last -3) (resumes 0) (gc-since-resume #f)
        (eg 0) (eb 0) (ea 0) (el -3) (er 0) (have #f))
    (define (capture value)
      (set! generation (+ generation 1)) (set! seed value)
      (set! last -3) (set! resumes 0) (set! gc-since-resume #f)
      (call/cc
       (lambda (exit)
         (set! deliver exit)
         (let* ((payload (vector generation seed))
                (result
                 (dynamic-wind
                  (lambda () (set! before (+ before 1)))
                  (lambda ()
                    (map (lambda (x)
                           (if (= x 1)
                               (continuation-capture (lambda (k) (set! saved k) (deliver 'captured)))
                               payload)) '(0 1 2)))
                  (lambda () (set! after (+ after 1))))))
           ;; Latest dispatcher is intentional: multi-shot restore must return
           ;; to the current action, not restart the old history driver.
           (deliver result)))))
    (define (resume value)
      (let* ((actual (if (and (= fault 1) (> resumes 0) gc-since-resume)
                         (+ value 1) value))
             (result (call/cc (lambda (exit) (set! deliver exit) (continuation-return saved actual)))))
        (set! resumes (+ resumes 1)) (set! gc-since-resume #f)
        (set! last (cadr result))
        (and (= (length result) 3) (eq? (car result) (caddr result))
             (vector? (car result))
             (= (vector-ref (car result) 0) generation)
             (= (vector-ref (car result) 1) seed))))
    (let loop ((xs commands) (at 0))
      (if (null? xs)
          (begin (write (list 'root-task-result 'pass at)) (newline) (exit 0))
          (let* ((row (car xs)) (op (vector-ref row 0))
                 (value (vector-ref row 1)) (owner (= (vector-ref row 2) 0))
                 (accepted 0) (expected-accepted 0) (graph #t))
            (case op
              ((0) (if owner
                       (begin (set! eg (+ eg 1)) (set! eb (+ eb 1)) (set! ea (+ ea 1))
                              (set! el -3) (set! er 0) (set! have #t)
                              (set! expected-accepted 1)
                              (capture value) (set! accepted 1))))
              ((1) (if (and owner have)
                       (begin (set! eb (+ eb 1)) (set! ea (+ ea 1))
                              (set! er (+ er 1)) (set! el value)
                              (set! expected-accepted 1)
                              (set! graph (resume value)) (set! accepted 1))))
              ((2) (##gc) (set! gc-since-resume #t)
                   (set! expected-accepted 1) (set! accepted 1))
              ((3) (if (and owner have)
                       (begin (set! expected-accepted 1) (set! accepted 1)
                              (set! graph (and (##continuation? saved)
                                               (>= (##continuation-fs saved) 0))))))
              ((5) (set! expected-accepted (if (and owner have) 1 0))
                   (set! accepted (if (and owner saved) 1 0))))
            (let ((expected (vector expected-accepted eg eb ea el er 1))
                  (observed (vector accepted generation before after last resumes (if graph 1 0))))
              (let compare ((j 0))
                (if (< j 7)
                    (if (= (vector-ref expected j) (vector-ref observed j))
                        (compare (+ j 1))
                        (begin
                          (write (list 'root-task-result 'mismatch at op j
                                       (vector-ref expected j) (vector-ref observed j)
                                       (vector->list observed)))
                          (newline) (exit 71))))))
            (loop (cdr xs) (+ at 1)))))))

(define (continuation-suite)
  (set! family 'continuation) (set! trials 0)
  (let ((state 173) (actions 0))
    (define (next n)
      (set! state (modulo (+ (* state 48271) 17) 2147483647)) (modulo state n))
    (define (noise n)
      (if (= n 0) '()
          (cons (vector (next 6) (list-ref '(-1 0 1 2) (next 4)) (next 2)) (noise (- n 1)))))
    (define chain (list (vector 0 0 0) (vector 1 1 0) (vector 2 0 0) (vector 1 2 0)))
    (do ((sample 0 (+ sample 1))) ((= sample 24))
      (let* ((commands (append (noise 16) chain (noise 16))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "real continuation history failed" result minimal)))))
    (write (list 'CONTINUATION-HISTORY-PBT-PASS 'seed 173 'cases 24 'actions actions)) (newline)
    (let* ((noisy (append (make-list 12 (vector 5 0 0)) chain (make-list 8 (vector 4 0 0))))
           (failure (trial noisy 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(1 4))) (error "continuation invocation negative control missed" failure))
      (let* ((minimal (shrink noisy 1 wanted)) (replayed (trial minimal 1))
             (minimal? (one-minimal? minimal 1 wanted)))
        (if (not (and (= (length minimal) 4) minimal? (equal? (signature replayed) wanted)))
            (error "continuation shrink/replay certificate failed" minimal replayed))
        (with-output-to-file (trace-file "minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (write (list 'CONTINUATION-HISTORY-SHRINK-PASS 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'trials trials)) (newline)))
    (delete-file input-file)
    (display "CONTINUATION-HISTORY-REPLAY-PASS\n") (force-output)))

(c-declare "static ___SCMOBJ vm_root_before; static int vm_root_owned;")
(define vm-install
  (c-lambda (scheme-object) bool #<<c-end
___SCMOBJ *cells=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED);
/* Field2 is unused-field2 in both real _thread#.scm VM definitions. */
___result=cells[2]==___FAL;
if(___result) { cells[2]=___arg1; vm_root_before=___arg1; vm_root_owned=1; }
c-end
))
(define vm-value
  (c-lambda () scheme-object "___result=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2];"))
(define vm-moved?
  (c-lambda () bool "___result=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2]!=vm_root_before;"))
(define vm-clear
  (c-lambda () void "if(vm_root_owned) { ___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2]=___FAL; vm_root_before=___FAL; vm_root_owned=0; }"))
(define (vm-moving-roots)
  (dynamic-wind
   (lambda () #f)
   (lambda ()
     (thread-join!
      (thread-start!
       (make-thread
        (lambda ()
          (if (not (vm-install (cons (+ 987 (##current-processor-id)) (make-vector 7 731))))
              (error "VM fixture unused-field2 unavailable"))
          #t))))
     (##gc)
     (if (not (vm-moved?)) (error "VM source payload did not move"))
     (##gc)
     (let ((value (vm-value)))
       (if (not (and (pair? value) (= (car value) 987)
                     (equal? (cdr value) (make-vector 7 731))))
           (error "VM root payload lost after moving GC")))
     (display "VM-ROOT-MOVING-PASS\n"))
   vm-clear))

(c-declare "static ___SCMOBJ bank_root_before; static ___execution_context *bank_root_context; static int bank_root_owned;")
(define bank-install
  (c-lambda (scheme-object) bool #<<c-end
___execution_context *source=___PSTATE->context;
___SCMOBJ *cells=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(source->processor_scmobj,___WS)),___tSUBTYPED);
/* unused-field15 in the real processor definition, _thread#.scm. */
___result=cells[15]==___FAL && !bank_root_owned;
if(___result) { cells[15]=___arg1; bank_root_before=___arg1; bank_root_context=source; bank_root_owned=1; }
c-end
))
(define bank-value
  (c-lambda () scheme-object "___result=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(___PSTATE->context->processor_scmobj,___WS)),___tSUBTYPED)[15];"))
(define bank-moved?
  (c-lambda () bool "___result=bank_root_owned && bank_root_context==___PSTATE->context && ___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank_root_context->processor_scmobj,___WS)),___tSUBTYPED)[15]!=bank_root_before;"))
(define bank-clear
  (c-lambda () void "if(bank_root_owned && bank_root_context==___PSTATE->context) { ___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank_root_context->processor_scmobj,___WS)),___tSUBTYPED)[15]=___FAL; bank_root_before=___FAL; bank_root_context=0; bank_root_owned=0; }"))
(define (bank-moving-roots)
  (for-each
   (lambda (owner)
     (let ((thread
            (make-thread
             (lambda ()
               (dynamic-wind
                (lambda () #f)
                (lambda ()
                  (if (not (= (##current-processor-id) owner)) (error "bank fixture wrong owner"))
                  (if (not (bank-install (cons (+ 997 owner) (make-vector 7 739))))
                      (error "processor fixture unused-field15 unavailable"))
                  (##gc)
                  (if (not (bank-moved?)) (error "bank root cell not updated" owner))
                  (##gc)
                  (let ((value (bank-value)))
                    (if (not (and (pair? value) (= (car value) (+ 997 owner))
                                  (equal? (cdr value) (make-vector 7 739))))
                        (error "bank moving root lost" owner)))
                  (write (list 'BANK-ROOT-MOVING-PASS 'owner owner)) (newline))
                bank-clear)))))
       (##thread-pin! thread (##processor owner))
       (thread-start! thread) (thread-join! thread)))
   (if (> (##current-vm-processor-count) 1) '(0 1) '(0))))

(let ((args (cdr (command-line))))
  (cond ((and (= (length args) 2) (string=? (car args) "--replay"))
         (replay (call-with-input-file (cadr args) read)))
        ((and (= (length args) 1) (string=? (car args) "--moving-bank")) (bank-moving-roots))
        ((null? args) (vm-moving-roots) (for-each (lambda (kind) (set! family kind) (suite)) '(rc vm bank stack))
         (continuation-suite))
        (else (error "usage: root-task [--replay TRACE | --moving-bank]"))))
