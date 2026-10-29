/* Entries and RC/root leases close before destruction. Native effects execute
 * on their owner after the whole GC round reopens; no collector holds them. */
static int lifecycle_close_context(___processor_state ps,int terminal)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___vm_lifecycle *life=vm->lifecycle;int id=___PROCESSOR_ID(ps,vm);
  ___WORD old=___LOAD_GLOBAL_WORD(&life->entries[id]);
  if(old!=0 && !lifecycle_owner(life,id))return 0;
  if(terminal) {
    ___activation_record *record=life->activations[id];
    while(record) {
      ___activation_record *next=record->next;
      if(record->marker!=___FAL) {
        ___VECTORELEM(record->marker,0)=___FAL;___still_obj_refcount_dec(record->marker);
      }
      ___FREE_MEM(record);record=next;
    }
    life->activations[id]=0;
  }
  if(old&1)return 1;
  if(old!=0 && !terminal)return 0;
  return ___lifecycle_cas(&life->entries[id],old,old|1)==old;
}
___BOOL ___lifecycle_cleanup_pstate(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  int id=___PROCESSOR_ID(ps,vm);
  /* A retiring native owner cannot resume this C stack: its caller exits the
   * thread. An unpublished aborted child has never acquired any entry. */
  if(!lifecycle_close_context(ps,ps==___PSTATE && id>=vm->processor_count))return 0;
  if(!___rc_prepare_cleanup(ps))return 0;
  ___lifecycle_detach_foreign(ps);
  if(!___lifecycle_drain(ps))return 0;
  cleanup_interrupts_pstate(ps);cleanup_os_and_mem_pstate(ps);return 1;
}
static int lifecycle_resize_quiet(___virtual_machine_state vm)
{
#ifndef ___SINGLE_THREADED_VMS
  int i;___vm_lifecycle *life=vm->lifecycle;
  if(life->resize_phase!=___RESIZE_IDLE && life->resize_phase!=___RESIZE_RUN)return 0;
  for(i=0;i<___MAX_PROCESSORS;i++)
    if(___LOAD_GLOBAL_WORD(&life->launches[i].uncertain))return 0;
#endif
  return 1;
}
static ___BOOL cleanup_vm_owned(___virtual_machine_state vm,int terminal)
{
  ___processor_state ps=___PSTATE_FROM_PROCESSOR_ID(0,vm);
  ___vm_lifecycle *life=vm->lifecycle;___WORD phase;
  if(!life || ps!=___PSTATE || !lifecycle_owner(life,0))return 0;
  phase=___LOAD_GLOBAL_WORD(&life->phase);
  if(phase==___VM_DRAINED)return 1;
  if(phase!=___VM_LIVE || vm->processor_count!=1 || !lifecycle_resize_quiet(vm))return 0;
  if(!lifecycle_close_context(ps,terminal))return 0;
  if(!___rc_prepare_cleanup(ps)) {
    ___WORD old=___LOAD_GLOBAL_WORD(&life->entries[0]);
    ___PUBLISH_GLOBAL_WORD(&life->entries[0],old&~___CAST(___WORD,1));return 0;
  }
  ___PUBLISH_GLOBAL_WORD(&life->phase,___VM_CLOSING);
  if(!___lifecycle_members_close(vm)) {
    ___rc_cancel_cleanup(ps);
    ___PUBLISH_GLOBAL_WORD(&life->phase,___VM_LIVE);
    ___PUBLISH_GLOBAL_WORD(&life->entries[0],0);return 0;
  }
  if(!___lifecycle_cleanup_pstate(ps)) {
    ___PUBLISH_GLOBAL_WORD(&life->phase,___VM_RETAINED);return 0;
  }
  life->setup_stages&=~___VM_SETUP_PROCESSOR;
  cleanup_os_and_mem_vmstate(vm);life->setup_stages&=~___VM_SETUP_MEMORY;
  ___cleanup_actlog_vmstate(vm);life->setup_stages=0;
  ___PUBLISH_GLOBAL_WORD(&life->phase,___VM_DRAINED);return 1;
}
static void lifecycle_dispose(___virtual_machine_state vm)
{
  ___vm_lifecycle *life=vm->lifecycle;
#ifndef ___SINGLE_THREADED_VMS
  ___CONDVAR_DESTROY(life->changed);___MUTEX_DESTROY(life->gate);
#endif
  vm_registry_remove(vm);vm->lifecycle=0;___FREE_MEM(life);
}
/* Known constructor failure has never published an executable VM. Reclaim
 * only completed stages, in reverse order; no owner/user callback can exist. */
static void abort_vm_setup(___virtual_machine_state vm)
{
  ___vm_lifecycle *life=vm->lifecycle;
  if(!life)return;
  if(life->setup_stages & ___VM_SETUP_PROCESSOR) {
    cleanup_interrupts_pstate(___PSTATE_FROM_PROCESSOR_ID(0,vm));
    cleanup_os_and_mem_pstate(___PSTATE_FROM_PROCESSOR_ID(0,vm));
  }
  if(life->setup_stages & ___VM_SETUP_MEMORY)cleanup_os_and_mem_vmstate(vm);
  if(life->setup_stages & ___VM_SETUP_ACTLOG)___cleanup_actlog_vmstate(vm);
#ifndef ___SINGLE_THREADED_VMS
  ___CONDVAR_DESTROY(life->changed);___MUTEX_DESTROY(life->gate);
#endif
  vm->lifecycle=0;___FREE_MEM(life);
}
___EXP_FUNC(___SCMOBJ,___setup_vmstate)
 ___P((___virtual_machine_state vm),(vm)
 ___virtual_machine_state vm;)
{
  ___SCMOBJ result;
  if(!vm || !vm_registry_try_write())return ___FIX(___UNKNOWN_ERR);
  if(___GSTATE->setup_state!=1 || vm_shutdown || !___GSTATE->vmstate0.lifecycle ||
     ___LOAD_GLOBAL_WORD(&___GSTATE->vmstate0.lifecycle->phase)!=___VM_LIVE || vm_registry_contains(vm)) {
    vm_registry_open();return ___FIX(___UNKNOWN_ERR);
  }
#ifdef ___SINGLE_VM
  vm_registry_open();return ___FIX(___UNKNOWN_ERR);
#else
  result=setup_vmstate_owned(vm);
  if(result==___FIX(___NO_ERR)) {
    ___PUBLISH_GLOBAL_WORD(&vm->lifecycle->phase,___VM_LIVE);vm_registry_publish(vm);
  }else abort_vm_setup(vm);
  vm_registry_open();return result;
#endif
}
___EXP_FUNC(___BOOL,___cleanup_vmstate)
 ___P((___virtual_machine_state vm),(vm)
 ___virtual_machine_state vm;)
{
  if(!vm || !___lifecycle_registry_begin())return 0;
  if(vm==&___GSTATE->vmstate0 || !vm_registry_contains(vm)) {___lifecycle_registry_end();return 0;}
  /* A successful context close excludes other cleanup callers. No registry
   * writer is held while an arbitrary foreign callback executes. */
  if(!vm->lifecycle || ___LOAD_GLOBAL_WORD(&vm->lifecycle->phase)==___VM_CLOSING ||
     ___LOAD_GLOBAL_WORD(&vm->lifecycle->phase)==___VM_RETAINED) {___lifecycle_registry_end();return 0;}
  ___lifecycle_registry_end();
  if(!cleanup_vm_owned(vm,0))return 0;
  if(!vm_registry_try_write())return 0; /* known DRAINED; retry only unlink */
  lifecycle_dispose(vm);vm_registry_open();return 1;
}
static ___BOOL cleanup_runtime(int terminal)
{
  ___virtual_machine_state vm=&___GSTATE->vmstate0;
  ___processor_state ___ps=___PSTATE;
  if(!vm_registry_try_write())return 0;
  if(___GSTATE->setup_state!=1 || ___ps!=___PSTATE_FROM_PROCESSOR_ID(0,vm) ||
     !vm->lifecycle || !lifecycle_owner(vm->lifecycle,0)) {
    vm_registry_open();return 0;
  }
#ifndef ___SINGLE_VM
  if(vm->next!=vm || vm->prev!=vm) {vm_registry_open();return 0;}
#endif
  if(!lifecycle_resize_quiet(vm)) {vm_registry_open();return 0;}
  ___PUBLISH_GLOBAL_WORD(&vm_shutdown,1);
  /* A refused final registry writer leaves a DRAINED VM in custody. Retry
   * only the unlink/global permit, never resize an already-freed root domain. */
  if(___LOAD_GLOBAL_WORD(&vm->lifecycle->phase)!=___VM_DRAINED) {
  vm_registry_open();
#ifndef ___SINGLE_THREADED_VMS
  if(___current_vm_resize(___PSP ___FAL,1)!=___FIX(___NO_ERR)) {
    ___PUBLISH_GLOBAL_WORD(&vm_shutdown,0);return 0;
  }
#endif
  if(!cleanup_vm_owned(vm,terminal)) {
    if(vm->lifecycle && ___LOAD_GLOBAL_WORD(&vm->lifecycle->phase)==___VM_LIVE)
      ___PUBLISH_GLOBAL_WORD(&vm_shutdown,0);
    return 0;
  }
  if(!vm_registry_try_write())return 0;
  }
  /* No published extra VM can appear after primordial entry closure, but a
   * concurrent setup may have won the gate; do not sweep its resources. */
#ifndef ___SINGLE_VM
  if(vm->next!=vm || vm->prev!=vm) {vm_registry_open();return 0;}
#endif
  ___cleanup_all_interrupt_handling();lifecycle_dispose(vm);
#ifndef ___SINGLE_VM

#endif
  cleanup_os_and_mem();___GSTATE->setup_state=2;
  ___PUBLISH_GLOBAL_WORD(&vm_registry_gate,VM_REGISTRY_CLOSED);return 1;
}
___EXP_FUNC(___BOOL,___cleanup) ___PVOID
{return cleanup_runtime(0);}
