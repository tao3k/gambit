/* Darwin qualification adapter only. Never linked into the runtime/profile. */
/* Bind this control to the configured native word ABI. No Gambit runtime
 * function is invoked by the independent interposition calibration. */
#include "gambit.h"
static_assert(sizeof(___WORD) == sizeof(void *), "native control word ABI");
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <errno.h>
#include <dlfcn.h>
#include <malloc/malloc.h>
#include <sched.h>
static _Atomic int create_at, join_at, allocation_at;
static _Atomic int creates, joins, allocations, hold_start, held_starts;
struct held_entry { void *(*fn)(void *); void *arg; };
void resize_test_hold_start(int hold) { atomic_store(&hold_start,hold); }
static void *held_entry(void *p) {
  struct held_entry *e=p;
  atomic_fetch_add(&held_starts,1);
  while(atomic_load(&hold_start)) sched_yield();
  void *result=e->fn(e->arg);
  atomic_fetch_sub(&held_starts,1);
  free(e);
  return result;
}

void resize_test_arm(int c, int j, int a) {
  atomic_store(&creates,0);atomic_store(&joins,0);atomic_store(&allocations,0);
  atomic_store(&create_at,c);atomic_store(&join_at,j);atomic_store(&allocation_at,a);
}
int resize_test_count(int kind) {
  return kind==3 ? atomic_load(&held_starts) : kind==0 ? atomic_load(&creates) : kind==1 ? atomic_load(&joins) : atomic_load(&allocations);
}
static int create_thread(pthread_t *id,const pthread_attr_t *attr,
                         void *(*fn)(void *),void *arg) {
  int at=atomic_load(&create_at);
  if(at && atomic_fetch_add(&creates,1)+1==at) {errno=0;return EAGAIN;}
  /* dyld excludes the interposer image from its own replacement tuples. */
  if(atomic_load(&hold_start)) {
    struct held_entry *e=malloc_zone_malloc(malloc_default_zone(),sizeof(*e));
    if(!e) return ENOMEM;
    e->fn=fn;e->arg=arg;
    int error=pthread_create(id,attr,held_entry,e);
    if(error) free(e);
    return error;
  }
  return pthread_create(id,attr,fn,arg);

}
static int join_thread(pthread_t id,void **result) {
  int at=atomic_load(&join_at);
  if(at && atomic_fetch_add(&joins,1)+1==at) {errno=0;return ESRCH;}
  return pthread_join(id,result);
}
static void *allocate(size_t bytes) {
  int at=atomic_load(&allocation_at);
  if(at && bytes>=1048576 && bytes<1052672 &&
     atomic_fetch_add(&allocations,1)+1==at) {errno=ENOMEM;return NULL;}
  return malloc_zone_malloc(malloc_default_zone(),bytes);
}
#define INTERPOSE(replacement,original) \
  __attribute__((used)) static struct {const void *r,*o;} map_##original \
  __attribute__((section("__DATA,__interpose")))={(const void *)&replacement,(const void *)&original}
INTERPOSE(create_thread,pthread_create);
INTERPOSE(join_thread,pthread_join);
INTERPOSE(allocate,malloc);
