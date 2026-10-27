;;; gambit.smp.gc.root-task: native replay, independent oracle and shrinking.
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
  (c-lambda (scheme-object scheme-object int) void #<<c-end
___processor_state ps=___PSTATE;
___rc_domain *d=ps->mem.rc_domain_;
___UWORD base, receipt;
int i,n=___INT(___VECTORLENGTH(___arg1));
___RC_LOCK(d);
base=d->task.epoch;
if(d->phase!=___RC_OPEN || d->task.state!=___ROOT_DONE || d->scan_leases!=0) {
  ___RC_UNLOCK(d); printf("(root-task-result precondition 0)\n"); fflush(stdout); _Exit(72);
}
{
  ___rc_header *h;
  for(h=d->head.next;h!=&d->head;h=h->next) if(h->data!=___FAL) {
    ___RC_UNLOCK(d); printf("(root-task-result precondition 1)\n"); fflush(stdout); _Exit(72);
  }
}
___RC_UNLOCK(d);
for(i=0;i<n;i++) {
  ___SCMOBJ row=___VECTORELEM(___arg1,i), expected=___VECTORELEM(___arg2,i);
  int op=___INT(___VECTORELEM(row,0)), delta=___INT(___VECTORELEM(row,1));
  ___processor_state actor=___INT(___VECTORELEM(row,2))==0?ps:0;
  ___UWORD key=base+delta;
  long observed[5];
  int accepted=0,j;
  /* Calibrated adapter mutation: production finish must reject the stale key.
   * The oracle remains unchanged; this is not a production runtime defect. */
  if(___arg3==1 && op==3 && delta==1 && actor==ps) --key;
  switch(op) {
  case 0: accepted=___root_task_publish(d,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim(d,actor,key); break;
  case 2: accepted=___root_task_scan(d,actor,key); break;
  case 3: accepted=___root_task_finish(d,actor,key); break;
  case 4: accepted=___rc_prepare_cleanup(ps); if(accepted) ___rc_cancel_cleanup(ps); break;
  case 5: accepted=___root_task_completed(d,actor,key); break;
  }
  ___RC_LOCK(d);
  observed[0]=accepted; observed[1]=d->task.state; observed[2]=d->phase;
  observed[3]=d->scan_leases; observed[4]=d->task.epoch-base;
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
(define (oracle commands)
  (let ((state 5) (phase 0) (lease 0) (epoch 0))
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
            ((4) (set! accepted (= phase 0)))
            ((5) (set! accepted (and current (= state 5) (= lease 0)))))
          (vector (if accepted 1 0) state phase lease epoch)))
      commands))))

(define (trace? x)
  (and (list? x) (= (length x) 4) (eq? (car x) 'root-task-trace)
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
  (if (not (prepare-source)) (error "root-task source allocation failed"))
  (do ((i 0 (+ i 1))) ((= i (cadr trace))) (##gc))
  (let ((commands (caddr trace)))
    (replay-native (list->vector commands) (oracle commands) (cadddr trace))))

(define self (car (command-line)))
(define input-file "root-task-input.dat")
(define trials 0)
(define (trial commands fault)
  (set! trials (+ trials 1))
  (with-output-to-file input-file
    (lambda () (write (list 'root-task-trace 1 commands fault)) (newline)))
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
              (with-output-to-file "root-task-failure.trace"
                (lambda () (write (list 'root-task-trace 1 minimal 0)) (newline)))
              (error "real root-task implementation property failed" result minimal)))))
    (write (list 'ROOT-TASK-PBT-PASS 'seed 173 'cases 24 'actions actions)) (newline)
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
        (with-output-to-file "root-task-minimal.trace"
          (lambda () (write (list 'root-task-trace 1 minimal 1)) (newline)))
        (write (list 'ROOT-TASK-SHRINK-PASS 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'trials trials))
        (newline)))
    (delete-file input-file)
    (display "ROOT-TASK-REPLAY-PASS\n") (force-output)))

(let ((args (cdr (command-line))))
  (cond ((and (= (length args) 2) (string=? (car args) "--replay"))
         (replay (call-with-input-file (cadr args) read)))
        ((null? args) (suite))
        (else (error "usage: root-task [--replay TRACE]"))))
