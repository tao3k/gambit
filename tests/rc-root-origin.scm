;;; Stateful RC implementation properties. Model protocol duties stay in Quint.
;;; Legal operations carry slot identities, not raw generated addresses.
;;; A failure prints the deterministic seed and complete replayable history.
(c-declare #<<c-end
#include "rc.h"
static void *rc_slots[4];
static const ___SCMOBJ *rc_cells[4];
static void *rc_departing;
#ifdef ___USE_POSIX_THREAD_SYSTEM
static pthread_t rc_native_thread;
static void *rc_native_bytes;
static void *rc_reference_worker(void *unused) {
  int i;
  for(i=0;i<2000;i++) {
    ___EXT(___addref_rc)(rc_native_bytes);
    ___EXT(___release_rc)(rc_native_bytes);
  }
  ___EXT(___release_rc)(rc_native_bytes);
  return 0;
}
#endif
c-end
)
(define rc-act
  (c-lambda (int int scheme-object) int #<<c-end
int op=___arg1, i=___arg2;
void *p;
___result=0;
if(i>=0 && i<4) {
  p=rc_slots[i];
  switch(op) {
  case 0:
    if(!p) { rc_slots[i]=___EXT(___alloc_rc)(___PSA(___PSTATE) 0); ___result=rc_slots[i]!=0; }
    break;
  case 1: if(p) ___result=___try_set_data_rc(___PSTATE,p,___arg3); break;
  case 2: if(p) { ___EXT(___addref_rc)(p); ___result=1; } break;
  case 3:
    if(p) {
      int last=___EXT(___refcount_rc)(p)==1 && !rc_cells[i];
      ___EXT(___release_rc)(p); if(last) rc_slots[i]=0; ___result=1;
    }
    break;
  case 4:
    if(p && !rc_cells[i]) { rc_cells[i]=___borrow_rc_root(___PSTATE,p); ___result=rc_cells[i]!=0; }
    break;
  case 5:
    if(p && rc_cells[i]) {
      int last=___EXT(___refcount_rc)(p)==0;
      ___return_rc_root(p); rc_cells[i]=0; if(last) rc_slots[i]=0; ___result=1;
    }
    break;
  case 6:
    /* A live payload/borrow must refuse teardown without changing admission. */
    if(p && !___rc_prepare_cleanup(___PSTATE))
      ___result=___try_set_data_rc(___PSTATE,p,___arg3);
    else ___rc_cancel_cleanup(___PSTATE);
    break;
  }
}
c-end
))
(define rc-inspect
  (c-lambda (int int scheme-object bool) bool #<<c-end
int i=___arg1;
void *p=rc_slots[i];
___result=p && ___EXT(___refcount_rc)(p)==___arg2 &&
  ___EXT(___data_rc)(p)==___arg3 &&
  (!___arg4 || (rc_cells[i] && *rc_cells[i]==___arg3));
c-end
))
(define (exercise owner seed steps)
  (let ((refs (make-vector 4 0)) (borrows (make-vector 4 #f))
        (values (make-vector 4 #f)) (history '()) (state seed) (actions 0))
    (define (next n)
      (set! state (modulo (+ (* state 48271) 17) 2147483647))
      (modulo state n))
    (define (fail why)
      (write (list 'RC-PROPERTY-FAIL owner seed why (reverse history)))
      (newline) (force-output) (error "RC implementation property violated" why))
    (define (check-all)
      (do ((i 0 (+ i 1))) ((= i 4))
        (if (or (> (vector-ref refs i) 0) (vector-ref borrows i))
            (if (not (rc-inspect i (vector-ref refs i) (vector-ref values i)
                                 (vector-ref borrows i)))
                (fail (list 'inspect i))))))
    (define (record action)
      (set! actions (+ actions 1)) (set! history (cons action history)))
    (do ((step 0 (+ step 1))) ((= step steps))
      (let* ((i (next 4)) (op (next 8)) (n (vector-ref refs i))
             (b (vector-ref borrows i)) (live (or (> n 0) b))
             (value (cons owner (make-vector (+ 1 (next 9)) step))))
        (cond
         ((and (= op 0) (not live))
          (record (list 'register i))
          (if (not (= (rc-act 0 i #f) 1)) (fail 'register))
          (vector-set! refs i 1) (vector-set! values i #f))
         ((and (= op 1) (> n 0))
          (record (list 'write i step))
          (if (not (= (rc-act 1 i value) (if b 0 1))) (fail 'write-admission))
          (if (not b) (vector-set! values i value)))
         ((and (= op 2) (> n 0) (< n 8))
          (record (list 'addref i))
          (rc-act 2 i #f) (vector-set! refs i (+ n 1)))
         ((and (= op 3) (> n 0))
          (record (list 'release i))
          (rc-act 3 i #f) (vector-set! refs i (- n 1)))
         ((and (= op 4) (> n 0) (not b))
          (record (list 'borrow i))
          (if (not (= (rc-act 4 i #f) 1)) (fail 'borrow))
          (vector-set! borrows i #t))
         ((and (= op 5) b)
          (record (list 'return i))
          (rc-act 5 i #f) (vector-set! borrows i #f))
         ((and (= op 6) (> n 0) (vector-ref values i))
          (record (list 'close-refused i step))
          (if (not (= (rc-act 6 i value) (if b 0 1))) (fail 'close-refusal))
          (if (not b) (vector-set! values i value)))
         ((= op 7)
          (record '(gc)) (##gc)))
        (check-all)))
    (do ((i 0 (+ i 1))) ((= i 4))
      (if (vector-ref borrows i) (rc-act 5 i #f))
      (do ((n (vector-ref refs i) (- n 1))) ((= n 0)) (rc-act 3 i #f)))
    (##gc)
    (write (list 'RC-STATEFUL-PASS owner seed 'draws steps 'actions actions))
    (newline) (force-output)))

(define (on-owner owner thunk)
  (let ((thread (make-thread thunk)))
    (##thread-pin! thread (##processor owner))
    (thread-start! thread) (thread-join! thread)))
(##thread-pin! (current-thread) (##processor 0))
(thread-yield!)
(define rc-initial-members (##current-vm-processor-count))
(for-each
 (lambda (owner)
   (for-each (lambda (seed) (on-owner owner (lambda () (exercise owner seed 240))))
             '(173 947 2027)))
 (if (> (##current-vm-processor-count) 1) '(0 1) '(0)))

(define rc-registration-refusal
  (c-lambda () bool #<<c-end
void *p=___EXT(___alloc_rc_no_register)(3);
___result=0;
if(p && ___EXT(___alloc_rc_no_register)(~(___SIZE_T)0)==0) {
  ___rc_header *h=(___rc_header*)p-1;
  if(___rc_prepare_cleanup(___PSTATE)) {
    int private_kept=___EXT(___setup_pstate)(___PSTATE,___VMSTATE_FROM_PSTATE(___PSTATE))==___FIX(___UNKNOWN_ERR) &&
      ___EXT(___register_rc)(___PSA(___PSTATE) p)==0 &&
      h->domain==0 && h->refcount==1 && h->next==h && h->prev==h;
    ___rc_cancel_cleanup(___PSTATE);
    ___result=private_kept && ___EXT(___register_rc)(___PSA(___PSTATE) p)==p &&
      ___EXT(___register_rc)(___PSA(___PSTATE) p)==p && h->domain->nodes==1;
  }
}
___EXT(___release_rc)(p);
c-end
))
(if (not (rc-registration-refusal)) (error "registration refusal lost private ownership"))
(display "RC-REGISTRATION-REFUSAL-PASS\n")

;;; Guaranteed borrow-last history, independent of random action coverage.
(let ((value (cons 817 (make-vector 5 919))))
  (rc-act 0 0 #f) (rc-act 1 0 value) (rc-act 4 0 #f) (rc-act 3 0 #f)
  (##gc)
  (if (not (rc-inspect 0 0 value #t)) (error "borrow-last root lost"))
  (rc-act 5 0 #f))
(display "RC-BORROW-LAST-PASS\n")

;;; An independent native reference holder can count/release while the Scheme
;;; owner participates in moving GC. No raw foreign payload writer is admitted.
(define rc-start-native
  (c-lambda () int #<<c-end
___result=0;
#ifdef ___USE_POSIX_THREAD_SYSTEM
___result=-1;
rc_native_bytes=___EXT(___alloc_rc)(___PSA(___PSTATE) 7);
if(rc_native_bytes) {
  ___EXT(___addref_rc)(rc_native_bytes);
  if(pthread_create(&rc_native_thread,0,rc_reference_worker,0)==0) ___result=1;
  else {
    ___EXT(___release_rc)(rc_native_bytes);
    ___EXT(___release_rc)(rc_native_bytes); rc_native_bytes=0;
    ___result=-1;
  }
}
#endif
c-end
))
(define rc-join-native
  (c-lambda () bool #<<c-end
___result=0;
#ifdef ___USE_POSIX_THREAD_SYSTEM
if(pthread_join(rc_native_thread,0)==0) {
  ___result=___EXT(___refcount_rc)(rc_native_bytes)==1;
  ___EXT(___release_rc)(rc_native_bytes); rc_native_bytes=0;
}
#endif
c-end
))
(let ((started (rc-start-native)))
  (if (< started 0) (error "native reference thread creation failed"))
  (if (= started 1)
      (begin
        (do ((i 0 (+ i 1))) ((= i 20)) (##gc))
        (if (not (rc-join-native)) (error "native reference handoff failed"))
        (display "RC-NATIVE-REFERENCE-PASS\n"))
      (display "RC-NATIVE-REFERENCE-SKIP unsupported-thread-backend\n")))

;;; Real resize must reject a source containing a Scheme payload before the
;;; roster is changed, then permit retirement after its actual owner releases.
(if (> (##current-vm-processor-count) 1)
    (let ((value (cons 971 (make-vector 3 977))))
      (on-owner 1 (lambda () (rc-act 0 0 #f) (rc-act 1 0 value)))
      (if (= (##current-vm-resize #f 1) 0) (error "live RC root did not refuse resize"))
      (if (not (= (##current-vm-processor-count) 2)) (error "refused resize changed roster"))
      (##gc)
      (if (not (rc-inspect 0 1 value #f)) (error "refused source lost moving root"))
      (on-owner 1 (lambda () (rc-act 3 0 #f)))
      (display "RC-RETIRE-REFUSAL-PASS\n")))

;;; A byte handle's lifetime crosses successful owner retirement. It is
;;; released from the surviving owner after the real shrink/join completes.
(define rc-retain-byte
  (c-lambda () bool #<<c-end
rc_departing=___EXT(___alloc_rc)(___PSA(___PSTATE) 13);
___result=rc_departing!=0;
c-end
))
(define rc-release-byte
  (c-lambda () bool #<<c-end
___rc_header *h=(___rc_header*)rc_departing-1;
___rc_domain *d=h->domain;
___result=d && d->phase==___RC_DETACHED && d->owner==0 && d->task.executor==0 &&
  d->task.scan_leases==0 && d->nodes==1;
___EXT(___release_rc)(rc_departing); rc_departing=0;
c-end
))
(if (> (##current-vm-processor-count) 1)
    (begin
      (if (not (on-owner 1 rc-retain-byte)) (error "byte handle allocation failed"))
      (if (not (= (##current-vm-resize #f 1) 0)) (error "RC-clean shrink refused"))
      (if (not (rc-release-byte)) (error "byte owner not detached"))
      (display "RC-DETACHED-BYTE-PASS\n")))
(display (if (> rc-initial-members 1) "RC-OWNERSHIP-PASS\n"
             "RC-OWNERSHIP-SINGLE-PASS\n")) (force-output)
