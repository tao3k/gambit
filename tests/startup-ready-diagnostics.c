/* Focused control for the real topology publisher and startup receipt
 * consumers. Native creation and Scheme execution are exercised separately. */
#include "setup.c"
#include <stdio.h>
#include <stdlib.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"startup-ready:%d: %s\n", \
                                           __LINE__,#x); return 1; } } while (0)

/* The topology publisher's interrupt path links this I/O entry. The
 * control deliberately publishes no I/O interrupt. */
void ___device_select_abort(___processor_state ps)
{
  (void)ps;
  abort();
}

int main(void)
{
#ifdef ___SINGLE_THREADED_VMS
  CHECK(___startup_ready_status(___FIX(0))==___FIX(___NO_ERR));
  CHECK(___startup_ready_status(___FIX(1))==___FIX(___UNKNOWN_ERR));
  CHECK(___startup_ready()==___FAL);
#else
  static ___virtual_machine_state_struct vm;
  static ___vm_lifecycle life;
  static ___activation_record activation;
  ___processor_state p0=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___processor_state p1=___PSTATE_FROM_PROCESSOR_ID(1,&vm);
  ___resize_launch *launch=&life.launches[1];
  ___sync_op_struct publish={OP_SET_PROCESSOR_COUNT,{2,0}};
  CHECK(pthread_mutex_init(&life.gate,0)==0);
  CHECK(pthread_cond_init(&life.changed,0)==0);
  vm.lifecycle=&life;
  vm.processor_count=1;
  p0->vmstate=p1->vmstate=&vm;
  life.resize_phase=___RESIZE_PREPARING;
  life.membership_epoch=18;
  life.first=1;
  life.target=2;
  launch->vm=&vm;
  launch->id=1;
  launch->generation=9;
  launch->native_live=1;
  launch->managed_startup=1;
  launch->entry=___LAUNCH_PARKED;
  launch->startup_phase=___STARTUP_PENDING;
  CHECK(barrier_sync_op(p0,&publish)==0);
  CHECK(vm.processor_count==2 && life.membership_epoch==19);
  CHECK(___startup_ready_status(p0,___FIX(18))==___FIX(___UNKNOWN_ERR));
  CHECK(___startup_ready_status(p0,___FIX(19))==___FAL);

  CHECK(___startup_ready(p1)==___FAL);
  activation.owner=p1;
  activation.marker=___FIX(99);
  activation.kind=___ACTIVATION_STARTUP;
  activation.startup_generation=8;
  life.activations[1]=&activation;
  CHECK(___startup_ready(p1)==___FAL);
  activation.startup_generation=9;
  CHECK(___startup_ready(p1)==___TRU);
  CHECK(___startup_ready(p1)==___FAL);
  CHECK(___startup_ready_status(p0,___FIX(19))==___FIX(___NO_ERR));

  launch->startup_phase=___STARTUP_RETURNED;
  CHECK(___startup_ready_status(p0,___FIX(19))==___FIX(___UNKNOWN_ERR));
  launch->startup_phase=___STARTUP_PENDING;
  launch->managed_startup=0;
  CHECK(___startup_ready_status(p0,___FIX(19))==___FIX(___UNKNOWN_ERR));
  launch->managed_startup=1;
  launch->uncertain=1;
  CHECK(___startup_ready_status(p0,___FIX(19))==___FIX(___UNKNOWN_ERR));
  CHECK(___startup_ready(p1)==___FAL && launch->native_live && !launch->joined);
  CHECK(pthread_cond_destroy(&life.changed)==0);
  CHECK(pthread_mutex_destroy(&life.gate)==0);
#endif
  puts("STARTUP-READY-DIAGNOSTICS-PASS");
  return 0;
}
