/* Private process registry. Readers pin list/control storage; no user effect
 * runs under its writer gate. Failed admission never waits for another owner. */
#define VM_REGISTRY_CLOSED 0
#define VM_REGISTRY_OPEN 1
#define VM_REGISTRY_WRITER 2
#define VM_REGISTRY_READER 4
static ___VOLATILE ___WORD vm_registry_gate;
static ___VOLATILE ___WORD vm_pending_interrupts;
static ___WORD vm_incarnation;
static ___VOLATILE ___WORD vm_shutdown;
static void vm_registry_flush(void);
extern void ___raise_interrupt_vmstate(___virtual_machine_state,int);
static int vm_registry_try_write(void)
{return ___lifecycle_cas(&vm_registry_gate,VM_REGISTRY_OPEN,VM_REGISTRY_WRITER)==VM_REGISTRY_OPEN;}
static int vm_registry_begin_setup(void)
{if(___GSTATE->setup_state==1 || ___GSTATE->setup_state==3)return 0;
 vm_shutdown=0;return ___lifecycle_cas(&vm_registry_gate,VM_REGISTRY_CLOSED,VM_REGISTRY_WRITER)==VM_REGISTRY_CLOSED;}
___BOOL ___lifecycle_registry_begin(void)
{
  ___WORD old=___LOAD_GLOBAL_WORD(&vm_registry_gate),found;
  while((old & 3)==VM_REGISTRY_OPEN && old<=___MAX_FIX-VM_REGISTRY_READER) {
    found=___lifecycle_cas(&vm_registry_gate,old,old+VM_REGISTRY_READER);
    if(found==old)return 1;old=found;
  }
  return 0;
}
void ___lifecycle_registry_end(void)
{
  ___WORD old=___LOAD_GLOBAL_WORD(&vm_registry_gate);
  while(___lifecycle_cas(&vm_registry_gate,old,old-VM_REGISTRY_READER)!=old)
    old=___LOAD_GLOBAL_WORD(&vm_registry_gate);
}
static void vm_registry_open(void)
{___PUBLISH_GLOBAL_WORD(&vm_registry_gate,VM_REGISTRY_OPEN);vm_registry_flush();}
static int vm_registry_contains(___virtual_machine_state vm)
{
  ___virtual_machine_state head=&___GSTATE->vmstate0,cursor=head;
  do {
    if(cursor==vm)return cursor->lifecycle!=0;
#ifndef ___SINGLE_VM
    cursor=cursor->next;
#else
    break;
#endif
  }while(cursor && cursor!=head);
  return 0;
}
static void vm_registry_publish(___virtual_machine_state vm)
{
#ifndef ___SINGLE_VM
  ___virtual_machine_state head=&___GSTATE->vmstate0;
  if(vm!=head) {vm->prev=head->prev;vm->next=head;head->prev->next=vm;head->prev=vm;}
#endif
}
static void vm_registry_remove(___virtual_machine_state vm)
{
#ifndef ___SINGLE_VM
  vm->next->prev=vm->prev;vm->prev->next=vm->next;vm->next=vm->prev=vm;
#endif
}
static void vm_registry_flush(void)
{
  ___WORD bits,old;int code;
  ___virtual_machine_state vm=&___GSTATE->vmstate0,cursor=vm;
  if(!___lifecycle_registry_begin())return;
  old=___LOAD_GLOBAL_WORD(&vm_pending_interrupts);
  while(___lifecycle_cas(&vm_pending_interrupts,old,0)!=old)old=___LOAD_GLOBAL_WORD(&vm_pending_interrupts);
  bits=old;
  for(code=0;code<___NB_INTRS;++code)if(bits & (___CAST(___WORD,1)<<code)) {
    cursor=vm;
    do {
      if(cursor->lifecycle && ___LOAD_GLOBAL_WORD(&cursor->lifecycle->phase)==___VM_LIVE)
        ___raise_interrupt_vmstate(cursor,code);
#ifndef ___SINGLE_VM
      cursor=cursor->next;
#else
      break;
#endif
    }while(cursor && cursor!=vm);
  }
  ___lifecycle_registry_end();
}
static void vm_registry_interrupt(int code)
{
  ___WORD old,next;
  if(code<0 || code>=___NB_INTRS)return;
  old=___LOAD_GLOBAL_WORD(&vm_pending_interrupts);
  do {next=old|(___CAST(___WORD,1)<<code);
    if(___lifecycle_cas(&vm_pending_interrupts,old,next)==old)break;
    old=___LOAD_GLOBAL_WORD(&vm_pending_interrupts);
  }while(1);
  vm_registry_flush();
}
static ___vm_lifecycle *vm_lifecycle_create(___virtual_machine_state vm)
{
  ___vm_lifecycle *life;
  if(vm_incarnation==___MAX_FIX)return 0;
  life=___CAST(___vm_lifecycle*,___ALLOC_MEM(sizeof(*life)));
  if(!life)return 0;
  memset(life,0,sizeof(*life));life->incarnation=++vm_incarnation;
#ifndef ___SINGLE_THREADED_VMS
#ifdef ___USE_POSIX_THREAD_SYSTEM
  if(!___MUTEX_INIT(life->gate)){___FREE_MEM(life);return 0;}
  if(!___CONDVAR_INIT(life->changed)){___MUTEX_DESTROY(life->gate);___FREE_MEM(life);return 0;}
#else
  ___MUTEX_INIT(life->gate);___CONDVAR_INIT(life->changed);
#endif
  life->resize_phase=___RESIZE_IDLE;
#endif
  ___thread_init_from_self(&life->owners[0]);
  vm->lifecycle=life;return life;
}
static int lifecycle_owner(___vm_lifecycle *life,int id)
{
#ifdef ___USE_POSIX_THREAD_SYSTEM
  return pthread_equal(life->owners[id].thread_id,pthread_self());
#elif defined(___USE_WIN32_THREAD_SYSTEM)
  return life->owners[id].thread_id==GetCurrentThreadId();
#else
  return 1;
#endif
}
___BOOL ___lifecycle_enter(___processor_state ps)
{
  ___virtual_machine_state vm;
  ___vm_lifecycle *life;
  ___WORD old,found;int id,ok=0;
  if(ps==0 || ps!=___PSTATE || !___lifecycle_registry_begin())return 0;
  vm=___VMSTATE_FROM_PSTATE(ps);
  if(!vm_registry_contains(vm))goto done;
  life=vm->lifecycle;id=___PROCESSOR_ID(ps,vm);
  if(___LOAD_GLOBAL_WORD(&life->phase)!=___VM_LIVE || id<0 || id>=vm->processor_count || !lifecycle_owner(life,id))goto done;
  old=___LOAD_GLOBAL_WORD(&life->entries[id]);
  while(!(old&1) && old<=___MAX_FIX-2) {
    found=___lifecycle_cas(&life->entries[id],old,old+2);
    if(found==old){ok=1;break;}old=found;
  }
done:___lifecycle_registry_end();return ok;
}
void ___lifecycle_leave(___processor_state ps)
{
  ___vm_lifecycle *life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  int id=___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps));
  ___WORD old=___LOAD_GLOBAL_WORD(&life->entries[id]);
  while(old>=2) {
    if(___lifecycle_cas(&life->entries[id],old,old-2)==old)return;
    old=___LOAD_GLOBAL_WORD(&life->entries[id]);
  }
}
___BOOL ___lifecycle_gc_admitted(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  int id=___PROCESSOR_ID(ps,vm);
#ifndef ___SINGLE_THREADED_VMS
  if(resize_retained(vm))return 0;
#endif
  return vm->lifecycle && ___LOAD_GLOBAL_WORD(&vm->lifecycle->phase)==___VM_LIVE &&
    id>=0 && id<vm->processor_count && !(___LOAD_GLOBAL_WORD(&vm->lifecycle->entries[id])&1);
}

___activation_record *___lifecycle_marker_prepare(___processor_state ps)
{
  ___vm_lifecycle *life;___activation_record *record;int id;
  if(!___lifecycle_enter(ps))return 0;
  record=___CAST(___activation_record*,___ALLOC_MEM(sizeof(*record)));
  if(!record){___lifecycle_leave(ps);return 0;}
  life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;id=___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps));
  record->owner=ps;record->marker=___FAL;record->startup=0;
  record->next=life->activations[id];life->activations[id]=record;return record;
}
void ___lifecycle_marker_abort(___activation_record *record)
{
  ___processor_state ps=record->owner;___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___activation_record **link=&vm->lifecycle->activations[___PROCESSOR_ID(ps,vm)];
  while(*link && *link!=record)link=&(*link)->next;
  if(*link==record){*link=record->next;___FREE_MEM(record);___lifecycle_leave(ps);}
}
void ___lifecycle_marker_kill(___processor_state ps,___SCMOBJ marker)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);int id=___PROCESSOR_ID(ps,vm);
  ___activation_record *record;
  if(!vm->lifecycle || !lifecycle_owner(vm->lifecycle,id))return;
  record=vm->lifecycle->activations[id];
  while(record && record->marker!=marker)record=record->next;
  if(!record)return; /* never discharge an unowned or already retired marker */
  ___VECTORELEM(marker,0)=___FAL;___still_obj_refcount_dec(marker);
  ___lifecycle_marker_abort(record);
}

int ___lifecycle_members_begin(___virtual_machine_state vm)
{
  ___WORD old,found;___vm_lifecycle *life=vm->lifecycle;
  if(!life)return 0;
  old=___LOAD_GLOBAL_WORD(&life->member_gate);
  while(!(old&1) && old<=___MAX_FIX-2) {
    found=___lifecycle_cas(&life->member_gate,old,old+2);
    if(found==old)return 1;old=found;
  }
  return 0;
}
void ___lifecycle_members_end(___virtual_machine_state vm)
{
  ___WORD old=___LOAD_GLOBAL_WORD(&vm->lifecycle->member_gate);
  while(___lifecycle_cas(&vm->lifecycle->member_gate,old,old-2)!=old)
    old=___LOAD_GLOBAL_WORD(&vm->lifecycle->member_gate);
}
int ___lifecycle_members_close(___virtual_machine_state vm)
{return ___lifecycle_cas(&vm->lifecycle->member_gate,0,1)==0;}
static void lifecycle_members_flush(___virtual_machine_state vm)
{
  ___WORD bits,old;int code;
  if(!___lifecycle_members_begin(vm))return;
  old=___LOAD_GLOBAL_WORD(&vm->lifecycle->pending_interrupts);
  while(___lifecycle_cas(&vm->lifecycle->pending_interrupts,old,0)!=old)
    old=___LOAD_GLOBAL_WORD(&vm->lifecycle->pending_interrupts);
  bits=old;
  for(code=0;code<___NB_INTRS;code++)if(bits & (___CAST(___WORD,1)<<code))
    ___raise_interrupt_vmstate(vm,code);
  ___lifecycle_members_end(vm);
}
void ___lifecycle_interrupt_pending(___virtual_machine_state vm,int code)
{
  ___WORD old=___LOAD_GLOBAL_WORD(&vm->lifecycle->pending_interrupts),next;
  do {
    next=old|(___CAST(___WORD,1)<<code);
    if(___lifecycle_cas(&vm->lifecycle->pending_interrupts,old,next)==old)break;
    old=___LOAD_GLOBAL_WORD(&vm->lifecycle->pending_interrupts);
  }while(1);
  /* The producer also tries delivery: opening between the producer's failed
   * borrow and this bit publication cannot strand the notification. */
  lifecycle_members_flush(vm);
}
void ___lifecycle_members_open(___virtual_machine_state vm)
{
  ___PUBLISH_GLOBAL_WORD(&vm->lifecycle->member_gate,0);
  lifecycle_members_flush(vm);
}
