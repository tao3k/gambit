;; Library-style host ownership, following tests/client.c and test8's actual
;; -D___LIBRARY path. This checks a real successful global reclamation receipt.
(c-declare #<<c-end
#include <stdio.h>
#include <stdlib.h>
#include "lifecycle.h"
#include "test-entry.h"
extern void ___thread_set_pstate(___processor_state);
static int registry_pin,registry_effects;
static ___SCMOBJ retain_registry(void *payload) {
  if(!___lifecycle_registry_begin())return ___FIX(___UNKNOWN_ERR);
  registry_pin=1;registry_effects++;return ___FIX(___NO_ERR);
}
extern ___mod_or_lnk ___LNK_vm_2d_lifecycle_2d_host__(___global_state);
GAMBIT_TEST_MAIN {
  ___setup_params_struct p;
  ___virtual_machine_state vm;
  ___processor_state primary;
  ___SCMOBJ held;
  ___setup_params_reset(&p);p.version=___VERSION;
  p.parallelism_level=1;
  p.linker=___LNK_vm_2d_lifecycle_2d_host__;
  if (___setup(&p)!=___FIX(___NO_ERR)) return 1;
  primary=___GET_PSTATE();
  if (___setup(&p)==___FIX(___NO_ERR) || ___GSTATE->setup_state!=1) return 2;
#ifndef ___SINGLE_VM
  vm=calloc(1,sizeof(*vm));if (!vm) return 3;
  if (___setup_vmstate(vm)!=___FIX(___NO_ERR)) return 4;
  if (___cleanup() || ___GSTATE->setup_state!=1 || vm->lifecycle->phase!=___VM_LIVE) return 5;
  ___thread_set_pstate(___PSTATE_FROM_PROCESSOR_ID(0,vm));
  if (!___cleanup_vmstate(vm)) return 6;
  ___thread_set_pstate(primary);
  free(vm);
#endif
  if(!___lifecycle_registry_begin())return 11;
  if(___cleanup() || ___GSTATE->vmstate0.lifecycle->phase!=___VM_LIVE ||
     primary->mem.rc_domain_==0)return 12;
  ___lifecycle_registry_end();
  /* The real owner effect retains only a topology/control pin. VM data can
   * drain, but the final writer/global free must refuse until this pin ACK. */
  if(___POINTER_to_SCMOBJ(primary,&registry_pin,___FAL,retain_registry,&held,0)
      !=___FIX(___NO_ERR))return 9;
  if(___cleanup() || !registry_pin || registry_effects!=1 ||
     ___GSTATE->setup_state!=1 ||
     ___GSTATE->vmstate0.lifecycle->phase!=___VM_DRAINED ||
     primary->mem.rc_domain_!=0)return 10;
  ___lifecycle_registry_end();registry_pin=0;
  if (!___cleanup() || registry_effects!=1 || ___GSTATE->setup_state!=2 || ___GSTATE->vmstate0.lifecycle!=0) return 7;
  if (___cleanup()) return 8;
  printf("LIFECYCLE-LAYOUT max=%d vm=%lu control=%lu launch=%lu cleanup=%lu activation=%lu\n",
    ___MAX_PROCESSORS,(unsigned long)sizeof(*vm),(unsigned long)sizeof(___vm_lifecycle),
    (unsigned long)sizeof(___resize_launch),(unsigned long)sizeof(___owner_cleanup),
    (unsigned long)sizeof(___activation_record));
#ifdef ___SINGLE_VM
  puts("VM-GLOBAL-RECLAIM-SINGLE-PASS global-permit duplicate-refusal");
#else
  puts("VM-GLOBAL-RECLAIM-PASS secondary-ack drained-retry one-effect global-permit duplicate-refusal");
#endif
  return 0;
}
c-end
)
