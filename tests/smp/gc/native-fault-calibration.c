/* Independent qualification of the Darwin injection adapter; no Gambit code. */
/* Bind this control to the configured native word ABI. No Gambit runtime
 * function is invoked by the independent interposition calibration. */
#include "gambit.h"
static_assert(sizeof(___WORD) == sizeof(void *), "native control word ABI");
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sched.h>
#include <stdatomic.h>
static _Atomic int invoked; static void *entry(void *p) {atomic_fetch_add(&invoked,1);return p;}
int main(void) {
  void (*arm)(int,int,int)=dlsym(RTLD_DEFAULT,"resize_test_arm");
  int (*count)(int)=dlsym(RTLD_DEFAULT,"resize_test_count");
  if (!arm || !count) return 2;
  pthread_t first,second;arm(2,1,0);
  int a=pthread_create(&first,0,entry,0),b=pthread_create(&second,0,entry,0);
  int c=a==0?pthread_join(first,0):-1;
  int creates=count(0),joins=count(1);
  printf("create_first=%d create_second=%d join_first=%d creates=%d joins=%d\n",a,b,c,creates,joins);
  arm(0,0,0);if(a==0&&c!=0)pthread_join(first,0);if(b==0)pthread_join(second,0);
  if(!(a==0&&b==EAGAIN&&c==ESRCH&&creates==2&&joins==1)) return 1;
  void (*hold)(int)=dlsym(RTLD_DEFAULT,"resize_test_hold_start");
  if(!hold) return 3;
  atomic_store(&invoked,0);hold(1);
  if(pthread_create(&first,0,entry,0)) return 4;
  while(count(3)!=1) sched_yield();
  int before=atomic_load(&invoked);
  hold(0);if(pthread_join(first,0)) return 5;
  int after=atomic_load(&invoked),pending=count(3);
  printf("held_invocations=%d released_invocations=%d held_remaining=%d\n",before,after,pending);
  return before==0&&after==1&&pending==0?0:6;

}
