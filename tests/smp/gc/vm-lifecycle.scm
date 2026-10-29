(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#vm_lifecycle#" check result quit host-code))
(c-declare #<<c-end
#include "lifecycle.h"
#include "rc.h"
#include <stdlib.h>
#include <stdio.h>
extern void ___thread_set_pstate(___processor_state);
static int releases, rejected_reentries;
static ___SCMOBJ release_ok(void *p) {
  ___processor_state ps=___GET_PSTATE();
  if (___run(___PSA(ps) ___FAL)==___FIX(___UNKNOWN_ERR)) rejected_reentries++;
  releases++;
  return ___FIX(___NO_ERR);
}
static ___SCMOBJ release_unknown(void *p) { releases++; return ___FIX(___UNKNOWN_ERR); }
static int lifecycle_check(___processor_state primary,___SCMOBJ host_code) {
#ifdef ___SINGLE_VM
  if(___cleanup() || !___lifecycle_gc_admitted(primary))return 1;
  return 0;
#else
  ___processor_state ___ps=primary;
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(primary);
  ___virtual_machine_state extra=calloc(1,sizeof(*extra));
  ___virtual_machine_state rejected=calloc(1,sizeof(*rejected));
  ___virtual_machine_state retained=calloc(1,sizeof(*retained));
  ___processor_state secondary;
  ___SCMOBJ obj, symbols=___GSTATE->symbol_table;
  void *rc=NULL;
  int code=0;
#define REQUIRE(x,n) do { if (!(x)) {code=n;goto done;} } while(0)
  REQUIRE(extra && rejected && retained,1);
  REQUIRE(___setup_vmstate(extra)==___FIX(___NO_ERR),2);
  secondary=___PSTATE_FROM_PROCESSOR_ID(0,extra);
  {
    ___WORD incarnation=extra->lifecycle->incarnation;
    REQUIRE(___setup_vmstate(extra)!=___FIX(___NO_ERR),3);
    REQUIRE(extra->lifecycle->incarnation==incarnation,4);
  }
  REQUIRE(!___cleanup() && ___GSTATE->setup_state==1 && ___GSTATE->symbol_table==symbols,5);
  /* Membership readers prevent close. Notifications remain in the VM queue
   * until the same publication gate reopens; no direct private gate writes. */
  REQUIRE(___lifecycle_members_begin(vm),6);
  REQUIRE(!___lifecycle_members_close(vm),7);
  ___lifecycle_members_end(vm);
  REQUIRE(___lifecycle_members_close(vm),8);
  ___raise_interrupt_vmstate(vm,___INTR_HEARTBEAT);
  REQUIRE(vm->lifecycle->pending_interrupts & (1<<___INTR_HEARTBEAT),9);
  ___lifecycle_members_open(vm);
  REQUIRE(!vm->lifecycle->pending_interrupts,10);
  ___thread_set_pstate(secondary);
  ___ps=secondary;
  /* A real host marker owns an external return, so neither retirement nor
   * cleanup may abandon it. Killing the exact marker releases the debt. */
  REQUIRE(___make_sfun_stack_marker(secondary,&obj,host_code)==___FIX(___NO_ERR),11);
  REQUIRE(___lifecycle_can_handoff(secondary)==___HANDOFF_BUSY,12);
  REQUIRE(!___cleanup_vmstate(extra),13);
  ___kill_sfun_stack_marker(obj);
  REQUIRE(___lifecycle_can_handoff(secondary)==___HANDOFF_READY,30);
  rc=___alloc_rc(___PSP 0);
  REQUIRE(rc && ___borrow_rc_root(secondary,rc),14);
  REQUIRE(!___cleanup_vmstate(extra) && extra->lifecycle->phase==___VM_LIVE,15);
  ___return_rc_root(rc); ___release_rc(rc); rc=NULL;
  REQUIRE(___POINTER_to_SCMOBJ(secondary,extra,___FAL,release_ok,&obj,0)==___FIX(___NO_ERR),16);
  REQUIRE(___cleanup_vmstate(extra),17);
  REQUIRE(extra->lifecycle==0 && releases==1 && rejected_reentries==1,18);
  REQUIRE(!___cleanup_vmstate(extra),19);
  REQUIRE(___run(___PSP ___FAL)==___FIX(___UNKNOWN_ERR),20);
  ___thread_set_pstate(primary); ___ps=primary;
  free(extra); extra=NULL;
  REQUIRE(___setup_vmstate(retained)==___FIX(___NO_ERR),21);
  ___thread_set_pstate(___PSTATE_FROM_PROCESSOR_ID(0,retained));
  ___ps=___PSTATE_FROM_PROCESSOR_ID(0,retained);
  REQUIRE(___POINTER_to_SCMOBJ(___ps,retained,___FAL,release_unknown,&obj,0)==___FIX(___NO_ERR),22);
  REQUIRE(!___cleanup_vmstate(retained),23);
  REQUIRE(retained->lifecycle->phase==___VM_RETAINED && releases==2,24);
  REQUIRE(retained->lifecycle->cleanup[0].inflight &&
          retained->lifecycle->cleanup[0].payload==retained,25);
  REQUIRE(!___cleanup_vmstate(retained) && releases==2,26);
  ___thread_set_pstate(primary); ___ps=primary;
  REQUIRE(!___cleanup() && ___GSTATE->setup_state==1 && ___GSTATE->symbol_table==symbols,27);
  REQUIRE(___setup_vmstate(rejected)==___FIX(___NO_ERR),28);
  ___thread_set_pstate(___PSTATE_FROM_PROCESSOR_ID(0,rejected));
  REQUIRE(___cleanup_vmstate(rejected),29);
  ___thread_set_pstate(primary);
  free(rejected); rejected=NULL;
done:
  ___thread_set_pstate(primary);

  if (code) fprintf(stderr,"VM-LIFECYCLE-FAIL step=%d\n",code);
  return code;
#undef REQUIRE
#endif
}
c-end
)
(define (host-code) #f)
(define check (c-lambda (scheme-object) int "___return(lifecycle_check(___ps,___arg1));"))
(define quit (c-lambda (int) void "_Exit(___arg1);"))
(define result (check host-code))
(if (not (= result 0)) (quit result))
;; This is the initialized native VM lifecycle contract. No Scheme execution or
;; collection inside the secondary VM is claimed by this fixture.
(##gc)
(display
 (if ((c-lambda () bool "\n#ifdef ___SINGLE_VM\n___result=0;\n#else\n___result=1;\n#endif\n"))
     "VM-LIFECYCLE-PASS registry owner roots retained-release no-replay healthy-gc\n"
     "VM-LIFECYCLE-SINGLE-PASS active-entry guarded-gc\n"))
(force-output)
(quit 0)
