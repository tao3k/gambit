/* Actual header kernel, not a second implementation of its transitions.
 * Physical root stop, task-slot grace and a whole-round seal are external
 * prerequisites; these controls do not grant them to arbitrary native callers. */
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include "gambit.h"

/* The same component controls also run from Make against the runtime library.
 * This bound kernel compiles the actual implementation, not a model copy. */
#include "write_authority.c"
#define ___TEST_WRITE_AUTHORITY_EMBEDDED
#include "write-authority.c"
#undef ___TEST_WRITE_AUTHORITY_EMBEDDED
#undef CHECK

/* Independent ABI consumer: declaration and exported function-table contract
 * must agree in both implicit-TLS and explicit-PSTATE configurations. */
typedef ___SCMOBJ (*native_run_signature)(___PSD ___SCMOBJ thunk);
_Static_assert(_Generic(&___run,native_run_signature:1,default:0),
               "public run declaration does not match PSTATE ABI");
_Static_assert(_Generic(___GSTATE->___run,native_run_signature:1,default:0),
               "run function table does not match public ABI");
typedef void *(*rc_register_signature)(___PSD void *);
typedef ___BOOL (*rc_store_signature)(void *,___SCMOBJ);
typedef ___WORD (*rc_count_signature)(void *);
_Static_assert(_Generic(&___register_rc,rc_register_signature:1,default:0),"RC registration ABI");
_Static_assert(_Generic(___GSTATE->___register_rc,rc_register_signature:1,default:0),"RC registration table ABI");
_Static_assert(_Generic(&___set_data_rc,rc_store_signature:1,default:0),"RC store status ABI");
_Static_assert(_Generic(___GSTATE->___set_data_rc,rc_store_signature:1,default:0),"RC store table ABI");
_Static_assert(_Generic(&___refcount_rc,rc_count_signature:1,default:0),"RC count ABI");

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"gc-root-task:%d: %s\n",__LINE__,#x); return 1; } } while (0)

static ___gc_root_origin origin;
static ___gc_root_task task;
static ___execution_context context;
static ___processor_state_struct resume_owner;
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int ready, go;

struct contender { ___WORD owner; int won; };
static ___msection copy_sources[2];
static ___WORD copy_headers[2];
struct copy_contender_state { ___msection *source; ___WORD *header; };
static int copy_visits;
static void *copy_contender(void *arg)
{
  struct copy_contender_state *state = arg;
  ___WORD *header = state->header;
  ___VOLATILE ___WORD *copy_gate = &state->source->copy_gate;
  pthread_mutex_lock(&gate);
  ready++;
  pthread_cond_broadcast(&changed);
  while (!go) pthread_cond_wait(&changed,&gate);
  pthread_mutex_unlock(&gate);
  /* Two distinct source identities share their physical source owner. The
   * gate serializes reservation only; it never deduplicates the objects. */
  for (int i=0; i<10000; i++)
    {
      ___gc_copy_acquire(copy_gate);
      copy_visits++;
      (*header)++;
      ___gc_copy_release(copy_gate);
    }
  return 0;
}

static void *claim(void *arg)
{
  struct contender *c = arg;
  pthread_mutex_lock(&gate);
  ready++;
  pthread_cond_broadcast(&changed);
  while (!go) pthread_cond_wait(&changed,&gate);
  pthread_mutex_unlock(&gate);
  c->won = ___gc_root_task_claim(&task,1,___GC_ROOT_PREPARE,c->owner);
  return 0;
}

int main(void)
{
  pthread_t a, b;
  struct contender ca = {4,0}, cb = {5,0};
  struct copy_contender_state copies[2] = {
    {copy_sources,copy_headers}, {copy_sources,copy_headers+1}
  };
  ___WORD words[32];
  ___gc_worker_arena arena;
  ___WORD *begin, *past;
  memset(&origin,0,sizeof(origin));
  memset(&task,0,sizeof(task));
  memset(&context,0,sizeof(context));
  origin.incarnation = 1;
  context.saved[0] = ___FIX(37);
  CHECK(!___gc_root_task_publish(&task,&origin,1));
  CHECK(___gc_origin_freeze(&origin,&context,1));
  CHECK(!___gc_origin_freeze(&origin,&context,2));
  CHECK(___gc_root_task_publish(&task,&origin,1));
  CHECK(!___gc_root_task_claim(&task,2,___GC_ROOT_PREPARE,4));
  CHECK(!___gc_root_task_claim(&task,1,___GC_ROOT_STRONG,4));
  CHECK(!___gc_origin_thaw(&task,1));
  CHECK(task.origin->context->saved[0] == ___FIX(37));
  puts("PUBLICATION-PASS");

  CHECK(pthread_create(&a,0,claim,&ca) == 0);
  CHECK(pthread_create(&b,0,claim,&cb) == 0);
  pthread_mutex_lock(&gate);
  while (ready != 2) pthread_cond_wait(&changed,&gate);
  go = 1;
  pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&gate);
  CHECK(pthread_join(a,0) == 0);
  CHECK(pthread_join(b,0) == 0);
  CHECK(ca.won+cb.won == 1);
  CHECK(!___gc_root_task_finish(&task,1,___GC_ROOT_PREPARE,ca.won ? cb.owner : ca.owner));
  CHECK(!___gc_origin_thaw(&task,1)); /* retained winner, not idle */
  CHECK(___gc_root_task_finish(&task,1,___GC_ROOT_PREPARE,ca.won ? ca.owner : cb.owner));
  CHECK(!___gc_root_task_finish(&task,1,___GC_ROOT_PREPARE,ca.won ? ca.owner : cb.owner));
  CHECK(!___gc_origin_thaw(&task,1)); /* prepare is not whole-round completion */
  for (int phase=___GC_ROOT_PREPARE; phase<___GC_ROOT_CLEANUP; phase++)
    {
      CHECK(!___gc_root_task_advance(&task,2,(___gc_root_phase)phase));
      CHECK(___gc_root_task_advance(&task,1,(___gc_root_phase)phase));
      CHECK(!___gc_root_task_advance(&task,1,(___gc_root_phase)phase));
      CHECK(!___gc_root_task_claim(&task,1,(___gc_root_phase)phase,4));
      CHECK(___gc_root_task_claim(&task,1,(___gc_root_phase)(phase+1),4));
      CHECK(!___gc_root_task_advance(&task,1,(___gc_root_phase)(phase+1)));
      CHECK(!___gc_root_task_finish(&task,1,(___gc_root_phase)phase,4));
      CHECK(___gc_root_task_finish(&task,1,(___gc_root_phase)(phase+1),4));
      if (phase+1 < ___GC_ROOT_CLEANUP) CHECK(!___gc_origin_thaw(&task,1));
    }
  CHECK(!___gc_root_task_advance(&task,1,___GC_ROOT_CLEANUP));
  CHECK(___gc_origin_thaw(&task,1));
  CHECK(!___gc_origin_freeze(&origin,&context,1));
  CHECK(___gc_origin_freeze(&origin,&context,___MAX_FIX));
  CHECK(!___gc_origin_freeze(&origin,&context,1));
  puts("CLAIM-RACE-PASS");

  CHECK(copies[0].source == copies[1].source);
  ___gc_copy_acquire(&copy_sources[0].copy_gate);
  /* A different physical source remains independently acquirable. */
  CHECK(___COMPARE_AND_SWAP_WORD(
    &copy_sources[1].copy_gate,0,1) == 0);
  ___gc_copy_release(&copy_sources[1].copy_gate);
  ___gc_copy_release(&copy_sources[0].copy_gate);
  /* Start both contenders at the existing condition-variable cut. */
  ready = go = 0;
  CHECK(pthread_create(&a,0,copy_contender,&copies[0]) == 0);
  CHECK(pthread_create(&b,0,copy_contender,&copies[1]) == 0);
  pthread_mutex_lock(&gate);
  while (ready != 2) pthread_cond_wait(&changed,&gate);
  go = 1;
  pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&gate);
  CHECK(pthread_join(a,0) == 0);
  CHECK(pthread_join(b,0) == 0);
  CHECK(copy_visits == 20000);
  CHECK(copy_headers[0] == 10000 && copy_headers[1] == 10000);
  puts("COPY-AUTHORITY-PASS");

  memset(&arena,0,sizeof(arena));
  arena.base = arena.cursor = words;
  arena.limit = words+32;
  CHECK(!___gc_arena_reserve(&arena,33));
  CHECK(___gc_arena_reserve(&arena,8));
  begin = arena.pending; past = arena.pending_past;
  CHECK(!___gc_arena_reserve(&arena,1));
  CHECK(!___gc_arena_commit(&arena,begin+1,past));
  CHECK(arena.cursor == words+8);
  CHECK(___gc_arena_commit(&arena,begin,past));
  CHECK(arena.cursor == words+8);
  CHECK(!___gc_arena_commit(&arena,begin,past));
  CHECK(___gc_arena_reserve(&arena,24));
  CHECK(___gc_arena_commit(&arena,words+8,words+32));
  CHECK(arena.cursor == arena.limit);
  CHECK(!___gc_arena_reserve(&arena,1));
  puts("ARENA-PASS");
  {
    ___gc_resume_space resume;
    memset(&resume,0,sizeof(resume));
    resume.context = &context;
    resume.owner = &resume_owner;
    resume_owner.context = &context;
    resume.epoch = arena.epoch = 7;
    resume.stack_floor = words+30;
    arena.section = (___msection *)words; /* opaque, never dereferenced */
    arena.physical_limit = words+32;
    arena.retired_words = 11;
    resume_owner.mem.words_prev_msections_ = 5;
    CHECK(!___gc_arena_handoff(&arena,&resume,8));
    arena.cursor = words;
    CHECK(___gc_arena_reserve(&arena,3));
    CHECK(!___gc_arena_handoff(&arena,&resume,7));
    CHECK(!resume.accepted && resume_owner.mem.words_prev_msections_ == 5);
    CHECK(___gc_arena_commit(&arena,words,words+3));
    CHECK(___gc_arena_handoff(&arena,&resume,7));
    CHECK(resume_owner.mem.alloc_heap_ptr_ == words+3);
    CHECK(resume_owner.mem.alloc_heap_start_ == words);
    CHECK(resume_owner.mem.alloc_heap_limit_ == words+32);
    CHECK(resume_owner.mem.words_prev_msections_ == 16);
    CHECK(resume_owner.mem.alloc_stack_limit_ == words+30);
    CHECK(!___gc_arena_handoff(&arena,&resume,7));
    CHECK(!___gc_arena_reserve(&arena,1));
    CHECK(resume_owner.mem.words_prev_msections_ == 16);
  }
  {
    ___gc_resume_space r;
    memset(&r,0,sizeof(r)); r.context=&context; r.owner=&resume_owner; r.epoch=9;
    r.stack_section=(___msection *)words; r.loan_base=words;
    r.loan_limit=words+24; r.source_worker=-1;
    CHECK(!___gc_resume_without_arena(&r,8));
    r.loan_used=1; CHECK(!___gc_resume_without_arena(&r,9)); r.loan_used=0;
    CHECK(___gc_resume_without_arena(&r,9));
    CHECK(resume_owner.mem.alloc_heap_start_==words && resume_owner.mem.alloc_heap_ptr_==words);
    CHECK(resume_owner.mem.alloc_heap_limit_==words+22 && resume_owner.mem.alloc_stack_limit_==words+24);
    CHECK(!___gc_resume_without_arena(&r,9));
    CHECK(resume_owner.mem.words_prev_msections_==16);
  }
  puts("ARENA-HANDOFF-PASS");
  puts("ROOT-DOMAIN-RESUME-PASS");
  puts("NATIVE-RUN-ABI-PASS");
  CHECK(check_write_authority () == 0);
  return 0;
}
