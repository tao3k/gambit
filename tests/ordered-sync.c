/* Exercise actual word/ticket/fence operations, including the real POSIX
 * emulated C translation unit. Collective-message ownership is separate.
 * Finite observations do not prove all weak-memory executions. */
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
#include "gambit.h"
#ifdef ___USE_emulated_sync
#include "os_thread.h"
#endif
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"ordered-sync:%d: %s\n",__LINE__,#x); return 1; } } while (0)
#define ROUNDS 4096
static ___TICKETLOCK lock = ___TICKETLOCK_INIT_STATIC;
static ___WORD count, complement;
static _Atomic int bad;
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int ready, go;
static void *locker(void *unused)
{
  int i;
  pthread_mutex_lock(&gate);
  ready++;
  pthread_cond_broadcast(&changed);
  while (!go) pthread_cond_wait(&changed,&gate);
  pthread_mutex_unlock(&gate);
  for (i=0;i<ROUNDS;i++)
    {
      ___TICKETLOCK_LOCK(lock);
      if (complement != ~count) bad = 1;
      count++;
      complement = ~count;
      ___TICKETLOCK_UNLOCK(lock);
    }
  return 0;
}
static _Atomic int litmus[2];
static int phase, completed, observed[2];
static void *fenced_worker(void *identity)
{
  int id=___CAST(___SIZE_T,identity), round;
  for (round=1; round<=ROUNDS; round++) {
    pthread_mutex_lock(&gate);
    while(phase<round) pthread_cond_wait(&changed,&gate);
    pthread_mutex_unlock(&gate);
    atomic_store_explicit(&litmus[id],1,memory_order_relaxed);
    ___SHARED_MEMORY_BARRIER();
    observed[id]=atomic_load_explicit(&litmus[id^1],memory_order_relaxed);
    pthread_mutex_lock(&gate);
    completed++;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
  }
  return 0;
}
int main(void)
{
  pthread_t workers[4], producer, reader;
  ___WORD ___temp;
  int i;
#ifdef ___USE_emulated_sync
  CHECK(___setup_thread_module()==___FIX(___NO_ERR));
#endif
  /* Signed boundary and all-bit-pattern wrap are word-service contracts,
   * not a dependence on the production compiler -fwrapv option. */
  {
    ___VOLATILE ___WORD word=___CAST(___WORD,(~___CAST(___UWORD,0))>>1);
    ___WORD before=word;
    CHECK(___FETCH_AND_ADD_WORD(&word,1)==before);
    CHECK(___CAST(___UWORD,word)==___CAST(___UWORD,before)+1);
    before=word;
    CHECK(___COMPARE_AND_SWAP_WORD(&word,before,___CAST(___WORD,-1))==before && word==-1);
    CHECK(___FETCH_AND_ADD_WORD(&word,1)==-1 && word==0);
    word=___FIX(7);
    CHECK(___FETCH_AND_CLEAR_WORD(&word)==___FIX(7) && word==0);
  }
  complement = ~count;
  for (i=0;i<4;i++) CHECK(pthread_create(&workers[i],0,locker,0)==0);
  pthread_mutex_lock(&gate);
  while (ready!=4) pthread_cond_wait(&changed,&gate);
  go=1;
  pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&gate);
  for (i=0;i<4;i++) CHECK(pthread_join(workers[i],0)==0);
  CHECK(!bad && count==4*ROUNDS && complement==~count);
  ___TICKETLOCK_LOCK(lock);
  CHECK(!___TICKETLOCK_TRYLOCK2(lock.next_ticket,lock.current_ticket,___temp));
  ___TICKETLOCK_UNLOCK(lock);
  CHECK(___TICKETLOCK_TRYLOCK2(lock.next_ticket,lock.current_ticket,___temp));
  ___TICKETLOCK_UNLOCK(lock);
  /* Last encoded ticket wraps modulo the word, retaining the tag bits. */
  lock.current_ticket=lock.next_ticket=___CAST(___WORD,~___CAST(___UWORD,___FIX(1)-1));
  ___TICKETLOCK_LOCK(lock);
  ___TICKETLOCK_UNLOCK(lock);
  CHECK(___WORD_LOAD_ACQUIRE(&lock.current_ticket)==0 && ___WORD_LOAD_ACQUIRE(&lock.next_ticket)==0);
  CHECK(pthread_create(&producer,0,fenced_worker,___CAST(void*,0))==0);
  CHECK(pthread_create(&reader,0,fenced_worker,___CAST(void*,1))==0);
  for(i=1;i<=ROUNDS;i++) {
    pthread_mutex_lock(&gate);
    atomic_store_explicit(&litmus[0],0,memory_order_relaxed);
    atomic_store_explicit(&litmus[1],0,memory_order_relaxed);
    completed=0;phase=i;
    pthread_cond_broadcast(&changed);
    while(completed<2) pthread_cond_wait(&changed,&gate);
    CHECK(observed[0] || observed[1]);
    pthread_mutex_unlock(&gate);
  }
  CHECK(pthread_join(producer,0)==0 && pthread_join(reader,0)==0);
#ifdef ___USE_emulated_sync
  ___emulated_shared_memory_barrier();
  ___cleanup_thread_module();
  CHECK(___thread_mod.refcount==0);
  puts("ORDERED-SYNC-BACKEND emulated lifecycle-drained");
#else
  puts("ORDERED-SYNC-BACKEND native");
#endif
  puts("ORDERED-SYNC-PASS locks=16384 fences=4096 trylock=2 wrap=2 rmw=4");
  printf("ORDERED-SYNC-LAYOUT word=%d\n",___WORD_WIDTH);
  return 0;
}
