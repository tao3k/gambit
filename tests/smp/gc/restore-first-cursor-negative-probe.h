/* Diagnostic-only instrumentation for a separately built image. The marker
 * requires a real post-GC publication, generated host reload and closure entry
 * with no cursor advance. It does not cover other generated allocation sites. */
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  ___processor_state owner;
  ___WORD *published, *base, *limit;
  ___WORD epoch;
  int armed, reloaded;
} dev_alloc_state;

static _Thread_local dev_alloc_state dev_alloc_tls;
static atomic_int dev_alloc_done;

static int dev_alloc_mode(void)
{
  const char *mode=getenv("GAMBIT_DEV_FIRST_ALLOC_PROBE");
  if (!mode || atomic_load(&dev_alloc_done)) return 0;
  if (strcmp(mode,"positive")==0) return 1;
  if (strcmp(mode,"negative")==0) return 2;
  _Exit(77);
}

static dev_alloc_state *dev_alloc_for(___processor_state ps)
{
  (void)ps;
  return &dev_alloc_tls;
}

static void dev_alloc_arm(___processor_state ps, ___WORD epoch)
{
  dev_alloc_state *s;
  if (!dev_alloc_mode() || !ps || !ps->context) return;
  s=dev_alloc_for(ps);
  s->owner=ps;
  s->published=ps->context->hp;
  s->base=ps->mem.alloc_heap_start_;
  s->limit=ps->mem.alloc_heap_limit_;
  s->epoch=epoch;
  s->reloaded=0;
  s->armed=1;
}

void dev_alloc_reload(___processor_state ps, ___WORD *hp)
{
  dev_alloc_state *s;
  if (!dev_alloc_mode()) return;
  s=dev_alloc_for(ps);
  if (s->armed && s->owner==ps && ps->context && hp==s->published && ps->context->hp==s->published)
    s->reloaded=1;
}

static int dev_alloc_valid(___processor_state ps, dev_alloc_state *s,
                           ___WORD *hp, ___SIZE_TS words, ___WORD epoch)
{
  uintptr_t p=(uintptr_t)hp, base=(uintptr_t)s->base, end=(uintptr_t)s->limit;
  return s->armed && s->reloaded && s->owner==ps && ps->context && epoch==s->epoch && hp==s->published &&
    ps->context->hp==s->published && ps->mem.alloc_heap_start_==s->base &&
    ps->mem.alloc_heap_limit_==s->limit && p>=base && p<=end && words>0 &&
    (uintptr_t)words <= (end-p)/sizeof(___WORD);
}

___WORD *dev_alloc_poison_cursor(___processor_state ps, ___WORD *hp, ___SIZE_TS words)
{
  dev_alloc_state *s = dev_alloc_for(ps);
  if (dev_alloc_mode()==2 && dev_alloc_valid(ps,s,hp,words,s->epoch))
    return s->limit;
  return hp;
}

void dev_alloc_closure(___processor_state ps, ___WORD *hp, ___SIZE_TS words)
{
  dev_alloc_state *s = dev_alloc_for(ps);
  int mode = dev_alloc_mode();
  if (!mode || !s->armed || !s->reloaded || s->owner != ps) return;
  if (mode==2 && hp==s->limit && !dev_alloc_valid(ps,s,hp,words,s->epoch)) {
    fprintf(stderr,"DEV-FIRST-CURSOR-NEGATIVE rejected-before-write words=%ld\n",(long)words);
    fflush(NULL);
    _Exit(0);
  }
  if (!dev_alloc_valid(ps,s,hp,words,s->epoch)) return;
  fprintf(stderr,"DEV-FIRST-CURSOR-POSITIVE words=%ld\n",(long)words);
  fflush(stderr);
  atomic_store(&dev_alloc_done,1);
}
