(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#unknown_join_worker_domains#" arm fault-count note-entry entries hold-start phase capacity assigned base-capacity base-assigned retained-root? retained-phase? retained-reinit-rejected? isolated? collections end-control require-test await-entry request))
(c-declare #<<c-end
#include <dlfcn.h>
#include <stdlib.h>
#include <stdatomic.h>
static _Atomic int entry_count;
static int resize_test_arm_fn(int c,int j,int a) {
  void (*fn)(int,int,int)=dlsym(RTLD_DEFAULT,"resize_test_arm");
  if(!fn) return 0;fn(c,j,a);return 1;
}
static int resize_test_counter(int kind) {
  int (*fn)(int)=dlsym(RTLD_DEFAULT,"resize_test_count");
  return fn ? fn(kind) : -1;
}
c-end
)
(define arm (c-lambda (int int int) int "resize_test_arm_fn"))
(define fault-count (c-lambda (int) int "resize_test_counter"))
(define note-entry (c-lambda () void "atomic_fetch_add(&entry_count,1);"))
(define entries (c-lambda () int "___return(atomic_load(&entry_count));"))
(define hold-start (c-lambda (int) void "((void (*)(int))dlsym(RTLD_DEFAULT,\"resize_test_hold_start\"))(___arg1);"))
(define phase (c-lambda () int "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.phase);"))
(define capacity (c-lambda () int "___return(___VMSTATE_FROM_PSTATE(___ps)->mem.the_msections_->nb_sections);"))
(define assigned (c-lambda () int "___return(___VMSTATE_FROM_PSTATE(___ps)->mem.nb_msections_assigned_);"))
(define base-capacity (c-lambda () int "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.base_capacity);"))
(define base-assigned (c-lambda () int "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.base_assigned);"))
(define retained-root? (c-lambda () bool "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.thunk!=___FAL);"))
(define retained-phase? (c-lambda () bool "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.phase==___RESIZE_RETAINED);"))
(define retained-reinit-rejected? (c-lambda () bool #<<c-end
___virtual_machine_state vms = ___VMSTATE_FROM_PSTATE(___ps);
___SCMOBJ root = vms->resize.thunk;
___WORD generation = vms->resize.generation;
int before=___GSTATE->setup_state;
if (___cleanup() || ___GSTATE->setup_state != before) { ___return(0); }
___SCMOBJ err = ___setup(&___GSTATE->setup_params);
___return(err != ___FIX(___NO_ERR) && ___GSTATE->setup_state == before &&
          vms->resize.phase == ___RESIZE_RETAINED &&
          vms->resize.thunk == root && vms->resize.generation == generation);
c-end
))
(define isolated? (c-lambda () bool "___return(___VMSTATE_FROM_PSTATE(___ps)->resize.abort_isolated);"))
(define collections (c-lambda () double "___return(___VMSTATE_FROM_PSTATE(___ps)->mem.nb_gcs_);"))
(define end-control (c-lambda () void "_Exit(0);"))
(define (require-test p label) (if (not p) (error label)))
(define (await-entry n)
  (require-test (= (entries) n) "managed completion lost Scheme entry"))
(define (request n)
  ;; Fresh closure and payload must survive the pre-grant collection, entry
  ;; synchronization and marker allocation. Each child records actual entry.
  (let ((payload (vector 314159)))
    (##current-vm-resize-ready
      (lambda ()
        (declare (not interrupts-enabled))
        (if (not (= (vector-ref payload 0) 314159)) (error "startup closure root"))
        (note-entry)
        (##startup-processor!))
      n)))
((c-lambda () void "___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps); ___WORD old=___gc_atomic_load(&vm->gc_round.requested_workers); while(___gc_cas(&vm->gc_round.requested_workers,old,1)!=old) old=___gc_atomic_load(&vm->gc_round.requested_workers);"))
(require-test (= (##current-vm-processor-count) 1) "initial population")
(require-test (= (request 3) 0) "healthy cohort setup")
(await-entry 2)
(require-test (= (arm 2 1 0) 1) "fault adapter")
(hold-start 1)
(require-test (not (= (request 5) 0)) "partial growth accepted")
(require-test (= (##current-vm-processor-count) 3) "healthy cohort changed")
(require-test (= (entries) 2) "aborted child entered Scheme")
(require-test (isolated?) "empty abort domain not isolated")
(require-test (= (assigned) (base-assigned)) "empty grant still charged")
(let loop () (if (= (fault-count 3) 0) (begin (thread-yield!) (loop))))
(let ((before (collections)))
  (##gc) (##gc) (##gc)
  (require-test (>= (- (collections) before) 3) "healthy cohort GC blocked"))
(require-test ((c-lambda () bool "___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps); ___return(vm->gc_round.participant_count==3 && vm->gc_round.worker_count==1 && vm->gc_participants[0].resume.restored && vm->gc_participants[1].resume.restored && vm->gc_participants[2].resume.restored);")) "unequal worker/root round not observed")
(require-test (= (fault-count 3) 1) "held native actor not in flight")
(require-test (retained-root?) "VM root lost")
(hold-start 0)
(let loop () (if (not (= (fault-count 3) 0)) (begin (thread-yield!) (loop))))
(require-test (not (= (request 5) 0)) "quarantined slot reused")
(display "RESIZE-UNKNOWN-MULTI-GC-PASS\n")
(force-output)
(end-control)
