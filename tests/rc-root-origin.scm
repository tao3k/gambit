;;; ROOT-SOURCE regression: b77ad85c fails on the nonzero-origin RC payload.
;;; This test does not implement/admit root dispatch or arbitrary FFI writers.
;;; Execute with -:p2. A single-thread configuration exercises origin0 only;
;;; its PASS marker is distinct and never counts as nonzero SMP evidence.
;;; Two slots correspond to the two real processor origins in this control.
;;; Never dereference a possibly stale RC payload: compare tagged words only.
(c-declare #<<c-end
#include "mem.h"
#if defined(__APPLE__)
#include <dlfcn.h>
#endif
static void *rc_origin_slot[2];
static ___SCMOBJ rc_origin_before[2];
/* Internal root protocol under test; no new public FFI entrypoint. */
extern ___SCMOBJ *___borrow_rc_root(___processor_state, void *);
extern void ___return_rc_root(void *);
static void *rc_borrow_slot;
static ___SCMOBJ *rc_borrow_cell;
static ___SCMOBJ rc_borrow_before;
extern int rc_origin_callback(int);
static int rc_marker_gc_status;
static int rc_join_fault(int armed) {
#if defined(__APPLE__)
  void (*arm)(int,int,int)=dlsym(RTLD_DEFAULT,"resize_test_arm");
  if(!arm) return 0;
  arm(0,armed?1:0,0);return 1;
#else
  return 0;
#endif
}
static int rc_join_fault_calls(void) {
#if defined(__APPLE__)
  int (*count)(int)=dlsym(RTLD_DEFAULT,"resize_test_count");
  return count?count(1):-1;
#else
  return -1;
#endif
}
static ___SIZE_TS rc_free_words(___virtual_machine_state vm) {
  return vm->mem.heap_size_ -
    ___CAST(___SIZE_TS,vm->mem.nb_msections_assigned_)*___MSECTION_SIZE -
    vm->mem.occupied_words_still_ - vm->mem.overflow_reserve_;
}
c-end
)
(define register-root
  (c-lambda (int scheme-object) int #<<c-end
int owner = ___PROCESSOR_ID(___PSTATE, ___VMSTATE_FROM_PSTATE(___PSTATE));
if (owner != ___arg1 || owner < 0 || owner >= 2) {
  ___result = -1;
} else {
  void *p = ___EXT(___alloc_rc)(___PSA(___PSTATE) 0);
  if (!p) ___result = -2;
  else {
    rc_origin_slot[owner] = p;
    rc_origin_before[owner] = ___arg2;
    ___EXT(___set_data_rc)(p, ___arg2);
    ___result = owner;
  }
}
c-end
))
(define compare-and-release
  (c-lambda (int scheme-object) int #<<c-end
void *p = rc_origin_slot[___arg1];
int moved = rc_origin_before[___arg1] != ___arg2;
int updated = ___EXT(___data_rc)(p) == ___arg2;
___EXT(___release_rc)(p);
rc_origin_slot[___arg1] = 0;
___result = (moved ? 2 : 0) | (updated ? 1 : 0);
c-end
))
(define (observe owner)
  (let ((t (make-thread
            (lambda ()
              (let* ((root (cons (##current-processor-id) (make-vector 7 owner)))
                     (registered (register-root owner root)))
                (if (not (= owner registered))
                    (error "RC origin registration failed" owner registered))
                (write (list 'RC-SOURCE-STAGE 'registered owner)) (newline) (force-output)
                (##gc)
                (let ((bits (compare-and-release owner root)))
                  ;; Keep the ordinary Scheme root live; inspect only this root.
                  (if (not (= owner (car root))) (error "ordinary root damaged"))
                  (list owner registered bits)))))))
    (##thread-pin! t (##processor owner))
    (thread-start! t)
    (thread-join! t)))
;; The control caller must survive the requested membership. Pinning its
;; logical thread is not a replacement for the native self-removal refusal.
(##thread-pin! (current-thread) (##processor 0))
(thread-yield!)
(if (not (= (##current-processor-id) 0)) (error "control caller not on source0"))
(for-each
 (lambda (owner)
   (let ((row (observe owner)))
     (write (cons 'RC-ROOT-ORIGIN row)) (newline) (force-output)
     (if (< (caddr row) 2) (error "control requires actual moving collection"))
     (if (not (= (caddr row) 3))
         (error "RC moving-root coverage incomplete" row))))
 (if (> (##current-vm-processor-count) 1) '(0 1) '(0)))
(display (if (> (##current-vm-processor-count) 1)
             "RC-ROOT-ORIGIN-PASS" "RC-ROOT-ORIGIN-SINGLE-PASS")) (newline) (force-output)

;;; A borrowed cell is a stable root address, not a saved Scheme value. A
;;; final public release must leave it linked until the borrow is returned.
(define borrow-and-drop-reference
  (c-lambda (scheme-object) bool #<<c-end
void *p=___EXT(___alloc_rc)(___PSA(___PSTATE) 0);
if(p==0) ___result=0;
else {
  ___EXT(___set_data_rc)(p,___arg1);
  rc_borrow_cell=___borrow_rc_root(___PSTATE,p);
  if(rc_borrow_cell==0) { ___EXT(___release_rc)(p); ___result=0; }
  else {
    rc_borrow_slot=p; rc_borrow_before=___arg1;
    ___EXT(___release_rc)(p);
    ___result=1;
  }
}
c-end
))
(define reload-and-return-borrow
  (c-lambda (scheme-object) int #<<c-end
int moved=rc_borrow_before!=___arg1;
int updated=*rc_borrow_cell==___arg1;
int zero=___EXT(___refcount_rc)(rc_borrow_slot)==0;
___return_rc_root(rc_borrow_slot);
rc_borrow_slot=0; rc_borrow_cell=0;
___result=(moved?4:0)|(updated?2:0)|(zero?1:0);
c-end
))
(let ((root (cons 131 (make-vector 7 139))))
  (if (not (borrow-and-drop-reference root)) (error "root borrow refused"))
  (##gc)
  (if (not (= (reload-and-return-borrow root) 7))
      (error "zero-reference borrow did not retain/reload the moving root"))
  (if (not (= (car root) 131)) (error "borrowed ordinary root damaged")))
(##gc)
(display "RC-BORROW-RELOAD-PASS\n") (force-output)

;;; Escape from Scheme through a generated SFUN and its native caller. A
;;; subsequent callback must see a valid activation chain, not a stale marker.
(define rc-origin-action (lambda () 0))
(c-define (rc-origin-callback action) (int) int "rc_origin_callback" "extern"
  (if (= action 0) (begin (##gc) 37) (rc-origin-action)))
(define invoke-root-callback
  (c-lambda (int) int "___result=rc_origin_callback(___arg1);"))
(let ((answer (call-with-current-continuation
               (lambda (escape)
                 (set! rc-origin-action (lambda () (##gc) (escape 41)))
                 (invoke-root-callback 1)
                 0))))
  (set! rc-origin-action (lambda () 0))
  (if (not (= answer 41)) (error "callback escape lost its result")))
(if (not (= (invoke-root-callback 0) 37))
    (error "callback activation did not recover after escape"))
(display "RC-CALLBACK-ESCAPE-PASS\n") (force-output)

;;; Reach the real marker allocation slow path using valid still allocations.
;;; Single-member admission makes these allocator snapshots stable. No private
;;; counter is written, no heap parameter changes, and a GC before the marker
;;; is a failed precondition, never evidence of constructor-root protection.
(define marker-under-allocation-gc
  (c-lambda (scheme-object) scheme-object #<<c-end
___processor_state ps=___PSTATE;
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
___SCMOBJ filler,marker=___FAL,before=___arg1,err;
___SIZE_TS free_words,words,overhead,prior_deferred;
___F64 collections=vm->mem.nb_gcs_;
rc_marker_gc_status=-1; ___result=___FAL;
if(vm->processor_count==1) {
  /* Derive overhead from real allocator accounting, not copied layout
   * constants. This zero-length vector is fully initialized and released. */
  prior_deferred=ps->mem.words_still_objs_deferred_;
  filler=___EXT(___make_vector)(ps,0,___FAL);
  if(!___FIXNUMP(filler)) {
  ___EXT(___release_scmobj)(filler);
  overhead=ps->mem.words_still_objs_deferred_-prior_deferred;
  free_words=rc_free_words(vm);
  words=free_words-ps->mem.words_still_objs_deferred_-1;
  if(overhead>0 && vm->mem.nb_gcs_==collections &&
     words>___MAX_STILL_DEFERRED+overhead) {
    filler=___EXT(___make_vector)(ps,words-overhead,___FAL);
    if(!___FIXNUMP(filler)) {
      ___EXT(___release_scmobj)(filler);
      words=___MAX_STILL_DEFERRED-ps->mem.words_still_objs_deferred_;
      if(words>=overhead) {
        filler=___EXT(___make_vector)(ps,words-overhead,___FAL);
        if(!___FIXNUMP(filler)) {
          ___EXT(___release_scmobj)(filler);
          if(vm->mem.nb_gcs_==collections && rc_free_words(vm)==1 &&
             ps->mem.words_still_objs_deferred_==___MAX_STILL_DEFERRED) {
            rc_marker_gc_status=-2;
            err=___EXT(___make_sfun_stack_marker)(ps,&marker,before);
            if(err==___FIX(___NO_ERR)) {
              ___result=___VECTORELEM(marker,0);
              rc_marker_gc_status=(vm->mem.nb_gcs_>collections?2:0)|
                                  (___result!=before?1:0);
              ___EXT(___kill_sfun_stack_marker)(marker);
            }
          }
        }
      }
    }
  }
  }
}
c-end
))
(define marker-gc-status
  (c-lambda () int "___result=rc_marker_gc_status;"))
(let ((members (##current-vm-processor-count)))
  (if (> members 1)
      (if (not (equal? (##cvmr 1) 0)) (error "marker test source stop refused")))
  (##gc)
  (let* ((payload (make-vector 7 149))
         (proc (lambda () (vector-ref payload 3)))
         (reloaded (marker-under-allocation-gc proc)))
    (if (not (and (= (marker-gc-status) 3) (procedure? reloaded)
                  (= (reloaded) 149)))
        (error "marker allocation did not protect and reload its closure"
               (marker-gc-status))))
  (if (> members 1)
      (if (not (equal? (##cvmr members) 0)) (error "marker test source restore refused"))))
(display "RC-MARKER-ALLOCATION-GC-PASS\n") (force-output)

;;; A real nonzero source stops while its RC-only still payload stays live.
;;; This distinguishes domain lifetime from carrier lifetime. The optional
;;; calibrated join-error run never treats an unknown result as a stop witness.
(define retain-still-root
  (c-lambda () int #<<c-end
int owner=___PROCESSOR_ID(___PSTATE,___VMSTATE_FROM_PSTATE(___PSTATE));
void *p=0;
if(owner!=1 || rc_origin_slot[1]!=0) ___result=-1;
else if((p=___EXT(___alloc_rc)(___PSA(___PSTATE) 0))==0) ___result=-2;
else {
  ___SCMOBJ root=___EXT(___make_vector)(___PSTATE,7,___FIX(113));
  if(___FIXNUMP(root)) { ___EXT(___release_rc)(p); ___result=-3; }
  else {
    ___EXT(___set_data_rc)(p,root);
    ___EXT(___release_scmobj)(root);
    rc_origin_slot[1]=p;
    ___result=1;
  }
}
c-end
))
(define retained-still-root
  (c-lambda () scheme-object "___result=___EXT(___data_rc)(rc_origin_slot[1]);"))
(define release-still-root
  (c-lambda () void
    "___EXT(___release_rc)(rc_origin_slot[1]); rc_origin_slot[1]=0;"))
(define unknown-join-control? (member "unknown-join" (command-line)))
(define arm-join-fault (c-lambda (bool) int "rc_join_fault"))
(define join-fault-calls (c-lambda () int "rc_join_fault_calls"))
(define quarantined-source?
  (c-lambda () bool
    "___result=!___root_slot_available(___VMSTATE_FROM_PSTATE(___PSTATE),1);"))
(define recover-actual-join
  (c-lambda () bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___PSTATE);
___SCMOBJ error=___thread_join(&___PSTATE_FROM_PROCESSOR_ID(1,vm)->os_thread);
/* This control supplies a fresh actual platform result, not a fabricated
 * success flag or a protocol for a possibly executing/unknown owner. */
if(error==___FIX(___NO_ERR)) ___root_note_join(vm,1,1);
___result=error==___FIX(___NO_ERR);
c-end
))
(if (> (##current-vm-processor-count) 1)
    (begin
      (let ((t (make-thread
                (lambda ()
                  (let ((result (##cvmr 1)))
                    (list result (##current-vm-processor-count) (##current-processor-id)))))))
        (##thread-pin! t (##processor 1))
        (thread-start! t)
        (let ((row (thread-join! t)))
          (if (not (and (not (equal? (car row) 0)) (= (cadr row) 2) (= (caddr row) 1)))
              (error "self-removal must retain the calling source" row)))
        (display "RC-SOURCE-SELF-REMOVAL-REFUSED\n") (force-output))
      (let ((t (make-thread retain-still-root)))
        (##thread-pin! t (##processor 1))
        (thread-start! t)
        (if (not (= (thread-join! t) 1)) (error "still source registration failed")))
      (write (list 'RC-SOURCE-STAGE 'before-stop (##current-processor-id)))
      (newline) (force-output)
      (if unknown-join-control?
          (if (not (= (arm-join-fault #t) 1)) (error "join adapter unavailable")))
      (let ((result (##cvmr 1)))
        (if unknown-join-control?
            (if (or (equal? result 0) (not (= (join-fault-calls) 1))
                    (not (quarantined-source?)))
                (error "actual join error did not retain source custody" result))
            (if (not (equal? result 0)) (error "source stop refused" result))))
      (if (not (= (##current-vm-processor-count) 1)) (error "source still active"))
      (display "RC-SOURCE-STAGE stopped\n") (force-output)
      (##gc)
      (display "RC-SOURCE-STAGE retained-scan\n") (force-output)
      (let ((root (retained-still-root)))
        (if (not (equal? root (make-vector 7 113)))
            (error "retained source payload damaged")))
      (release-still-root)
      (##gc)
      (if unknown-join-control?
          (begin
            ;; A real platform join error leaves the old source outside the
            ;; surviving GC roster. Roots above must still have been scanned.
            (if (or (equal? (##cvmr 2) 0)
                    (not (= (##current-vm-processor-count) 1))
                    (not (quarantined-source?)))
                (error "unknown join admitted source reuse"))
            (display "RC-UNKNOWN-JOIN-GC-PASS\n") (force-output)
            (if (not (= (arm-join-fault #f) 1)) (error "join adapter reset failed"))
            (if (not (recover-actual-join)) (error "actual recovery join failed"))
            (if (quarantined-source?) (error "successful recovery join not acknowledged"))))
      ;; Reuse is permitted only after the real successful native join.
      (let ((result (##cvmr 2)))
        (if (not (equal? result 0)) (error "confirmed source reuse refused" result)))
      (display "RC-SOURCE-STAGE reused\n") (force-output)
      (let ((row (observe 1)))
        (if (not (= (caddr row) 3)) (error "reused source lost RC root" row)))
      (display "RC-ROOT-RETIRE-REUSE-PASS") (newline) (force-output)))
