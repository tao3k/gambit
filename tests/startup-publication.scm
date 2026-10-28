;;; gambit.smp.startup.publication: actual resize, custody, replay and shrinking.
;;; Fault mode links one renamed setup consumer; production has no test branch.
(declare (standard-bindings) (extended-bindings))
(c-declare #<<c-end
#include "rc.h"
#include "vm-resize.h"
#include "c_intf.h"
#include "setup.h"
#include <stdatomic.h>
#include <stdlib.h>
static int startup_mode, startup_creates, startup_joins, startup_roots;
static int startup_faults, startup_calibrate, startup_bad_refund;
static ___SIZE_T startup_base_nodes, startup_base_borrows;
static _Atomic int startup_entries, startup_bad_payload, startup_marker_gcs;
static void startup_arm(int mode) {
  startup_mode=mode; startup_creates=0; startup_joins=0;
  startup_roots=0; startup_faults=0;
  { ___rc_domain *d=___PSTATE->mem.rc_domain_;
    ___RC_LOCK(d); startup_base_nodes=d->nodes; startup_base_borrows=d->borrows;
    ___RC_UNLOCK(d); }
}
___SCMOBJ test_startup_create(___thread *thread) {
  ++startup_creates;
  if ((startup_mode==3 || startup_mode==4) && startup_creates==2) {
    ++startup_faults; return ___FIX(___UNKNOWN_ERR);
  }
  return ___thread_create(thread);
}
___SCMOBJ test_startup_join(___thread *thread) {
  ++startup_joins;
  if (startup_mode==4 && startup_joins==1) {
    ++startup_faults; return ___FIX(___UNKNOWN_ERR);
  }
  return ___thread_join(thread);
}
___SCMOBJ test_startup_reserve(___processor_state ps, ___resize_state *r) {
  if (startup_mode==1) { ++startup_faults; return ___FIX(___HEAP_OVERFLOW_ERR); }
  return ___reserve_resize(ps,r);
}
void *test_startup_alloc(___PSD ___SIZE_T bytes) {
  ___PSGET
  ++startup_roots;
  if (startup_mode==2 && startup_roots==3) { ++startup_faults; return 0; }
  return ___alloc_rc(___PSP bytes);
}
void test_startup_refund(___processor_state ps, ___resize_state *r) {
  ___refund_resize(ps,r);
  if (startup_calibrate) {
    /* Calibrated adapter mutation of the real refunded ledger; observation
     * restores it before the next trial. Never enabled in production. */
    ++___VMSTATE_FROM_PSTATE(ps)->mem.nb_msections_assigned_;
    startup_bad_refund=1;
  }
}
___SCMOBJ test_startup_marker(___processor_state ps, ___SCMOBJ *marker,
                             const ___SCMOBJ *cell) {
  if (startup_mode==6) {
    ___processor_state ___ps=ps;
    atomic_fetch_add(&startup_marker_gcs,1);
    /* Exercise removal while the rooted C activation has not constructed
     * its marker. Participate normally; never substitute a sleep/timeout. */
    for (;;) service_sync_op(___PSPNC);
  }
  /* New native actor participates in the actual collective, before the
   * allocating marker constructor; its source RC cell is the only C root. */
  if (startup_mode==5) {
    ___garbage_collect(___PSA(ps) 0);
    atomic_fetch_add(&startup_marker_gcs,1);
  }
  return ___make_sfun_stack_marker_root(ps,marker,cell);
}
static int startup_rolled_back(___processor_state ps) {
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___resize_state *r=vm->resize_state;
  int i, ok=r && r->phase==___RESIZE_IDLE && vm->processor_count==1;
  if (r && startup_mode!=1)
    ok=ok && vm->mem.nb_msections_assigned_==r->saved_assigned;
  if (r) for(i=r->first;i<r->target;++i)
    ok=ok && r->slots[i].root==0 && r->slots[i].cell==0;
  if (startup_bad_refund) {
    --vm->mem.nb_msections_assigned_; startup_bad_refund=0;
  }
  { ___rc_domain *d=ps->mem.rc_domain_; ___RC_LOCK(d);
    ok=ok && d->nodes==startup_base_nodes && d->borrows==startup_base_borrows;
    ___RC_UNLOCK(d); }
  return ok && atomic_load(&startup_entries)==0 && startup_faults==1;
}
c-end
)
(define arm (c-lambda (int) void "startup_arm"))
(define rolled-back? (c-lambda () bool "___return(startup_rolled_back(___ps));"))
(define entries (c-lambda () int "___return(atomic_load(&startup_entries));"))
(define marker-gcs (c-lambda () int "___return(atomic_load(&startup_marker_gcs));"))
(define note-entry
  (c-lambda (bool) void "if (!___arg1) atomic_store(&startup_bad_payload,1); atomic_fetch_add(&startup_entries,1);"))
(define clean-payload? (c-lambda () bool "___return(!atomic_load(&startup_bad_payload));"))
(define processor-id (c-lambda () int "___return(___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps)));"))
(define (require value . context) (if (not value) (apply error "startup publication" context)))
(define (request count)
  (declare (not interrupts-enabled))
  (let ((payload (vector 314159 271828)))
    (##current-vm-resize
     (lambda ()
       (declare (not interrupts-enabled))
       (note-entry (and (= (vector-ref payload 0) 314159)
                        (= (vector-ref payload 1) 271828)))
       (##startup-processor!)) count)))
(define (signature actions)
  (let loop ((xs actions))
    (if (null? xs) #f
        (begin
          (arm (car xs))
          (let ((result (request 3)))
            (cond ((= result 0) 'accepted-failure)
                  ((not (rolled-back?)) 'refund-or-custody)
                  (else (##gc) (loop (cdr xs)))))))))
(define (remove-at xs index)
  (if (= index 0) (cdr xs) (cons (car xs) (remove-at (cdr xs) (- index 1)))))
(define (shrink actions reason)
  (let loop ((xs actions) (i 0))
    (if (= i (length xs)) xs
        (let ((candidate (remove-at xs i)))
          (if (eq? reason (signature candidate))
              (loop candidate 0) (loop xs (+ i 1)))))))
(define (pbt)
  (let ((seed 271) (failure #f))
    (define (draw)
      (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
      (+ 1 (modulo (quotient seed 65536) 3)))
    (do ((trial 0 (+ trial 1))) ((= trial 12))
      (let* ((history (let loop ((n 6) (xs '()))
                        (if (= n 0) xs (loop (- n 1) (cons (draw) xs)))))
             (reason (signature history)))
        (if (and reason (not failure)) (set! failure (list reason history)))))
    (if failure
        (let* ((reason (car failure)) (original (cadr failure))
               (minimal (shrink original reason)))
          (call-with-output-file "startup-publication-minimal.scm"
            (lambda (p) (write minimal p) (newline p)))
          (require (eq? reason (signature minimal)) 'replay)
          (do ((i 0 (+ i 1))) ((= i (length minimal)))
            (require (not (eq? reason (signature (remove-at minimal i)))) 'minimal))
          (write (list 'STARTUP-PUBLICATION-SHRINK reason (length original)
                       (length minimal) 'replayed #t 'deletion-one-minimal #t minimal))
          (newline) #f)
        (begin (display "STARTUP-PUBLICATION-PBT-PASS seed 271 cases 12 actions 72\n") #t))))
(define (positive)
  (arm 5)
  (require (= (request 3) 0) 'growth)
  (let loop () (if (< (entries) 2) (begin (thread-yield!) (loop))))
  (require (and (= (##current-vm-processor-count) 3) (clean-payload?)) 'entry-roots)
  (##gc)
  (display "STARTUP-PUBLICATION-POSITIVE-PASS\n"))
(define (nonzero)
  (positive)
  (let ((answer
         (thread-join!
          (thread-start!
           (make-thread
            (lambda ()
              (declare (not interrupts-enabled))
              ;; Migration enqueues runnable work; work stealing may resume it
              ;; on a different carrier. Obtain an actual nonzero origin,
              ;; without treating the requested destination as a pin receipt.
              (let retry ()
                (##thread-migrate-to! 1)
                (if (= (processor-id) 0) (retry) (request 4)))))))))
    (require (= answer 0) 'nonzero-request))
  (let loop () (if (< (entries) 3) (begin (thread-yield!) (loop))))
  (##gc)
  (require (clean-payload?) 'nonzero-roots)
  (display "STARTUP-PUBLICATION-NONZERO-PASS\n"))
(define (unknown)
  (arm 4)
  (require (not (= (request 3) 0)) 'unknown-refused)
  (require ((c-lambda () bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
___resize_state *r=vm->resize_state;
___return(r && r->phase==___RESIZE_RETAINED && vm->processor_count==1 &&
          vm->mem.nb_msections_assigned_==r->saved_assigned+4 &&
          r->slots[1].root!=0 && r->slots[2].root!=0 &&
          startup_faults==2 && atomic_load(&startup_entries)==0);
c-end
)) 'unknown-custody)
  (require (not (= (request 3) 0)) 'retained-reuse-refused)
  (require ((c-lambda () bool "___return(___EXT(___garbage_collect)(___PSP 0));")) 'retained-gc-refused)
  (display "STARTUP-PUBLICATION-UNKNOWN-PASS\n") (force-output)
  ;; Deliberate process end: no fake successful join or teardown permission.
  ((c-lambda () void "_Exit(0);")))
(define (early-retire)
  (arm 6)
  (require (= (request 3) 0) 'early-grow)
  (let loop () (if (< (marker-gcs) 2) (begin (thread-yield!) (loop))))
  (require (= (##current-vm-resize #f 1) 0) 'early-retire)
  (require ((c-lambda () bool #<<c-end
___rc_domain *d=___ps->mem.rc_domain_;
int ok;
___RC_LOCK(d);
printf("STARTUP-EARLY-RETIRE nodes=%lu borrows=%lu base-nodes=%lu base-borrows=%lu\n",
 (unsigned long)d->nodes,(unsigned long)d->borrows,
 (unsigned long)startup_base_nodes,(unsigned long)startup_base_borrows);
ok=d->nodes==startup_base_nodes && d->borrows==startup_base_borrows;
___RC_UNLOCK(d);
___return(ok);
c-end
)) 'early-custody-drained)
  (##gc)
  (display "STARTUP-PUBLICATION-EARLY-RETIRE-PASS\n"))
(define args (cdr (command-line)))
(require (= (##current-vm-processor-count) 1) 'initial-owner)
(cond ((equal? args '("--positive")) (positive))
      ((equal? args '("--nonzero")) (nonzero))
      ((equal? args '("--marker-gc"))
       (positive) (require (= (marker-gcs) 2) 'actual-marker-gc-count)
       (display "STARTUP-PUBLICATION-MARKER-GC-PASS\n"))
      ((equal? args '("--unknown")) (unknown))
      ((equal? args '("--early-retire")) (early-retire))
      ((equal? args '("--calibrate"))
       ((c-lambda () void "startup_calibrate=1;")) (if (not (pbt)) (exit 70)))
      ((equal? args '("--calibration"))
       ((c-lambda () void "startup_calibrate=1;"))
       (require (not (pbt)) 'negative-not-detected)
       ((c-lambda () void "startup_calibrate=0;"))
       (require (not (signature (call-with-input-file "startup-publication-minimal.scm" read))) 'candidate-replay)
       (display "STARTUP-PUBLICATION-CALIBRATION-PASS\n"))
      ((and (pair? args) (equal? (car args) "--replay"))
       (require (not (signature (call-with-input-file (cadr args) read))) 'replay)
       (display "STARTUP-PUBLICATION-REPLAY-PASS\n"))
      (else (require (pbt) 'pbt)))
