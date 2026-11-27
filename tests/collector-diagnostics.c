/* Actual private diagnostic consumers, isolated from the production archive:
 * DEBUG changes C layouts. Only output and fatal-delivery sinks are controlled;
 * allocation/scanning/diagnostic decisions are the real mem.c definitions.
 * This does not qualify the whole debug VM or native fatal cleanup. */
#include <stdarg.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#ifdef __APPLE__
#include <pthread.h>
#include <stdatomic.h>
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
#include <sys/mman.h>
#include <sys/wait.h>
#endif
static void before_final_restore_read(void);
#define ___GC_TEST_BEFORE_FINAL_RESTORE_READ(slot) before_final_restore_read()
#endif
#include "mem.c"

#ifndef ___GAMBIT_DEV_RESTORE_PROBE
___global_state_struct ___gstate0;
___THREAD_LOCAL_STORAGE_CLASS void *___tls_ptr;
#endif

/* Census entry negatives must reject before reaching the allocation path.
 * Keep the isolated diagnostic linkable and fail on any such call. */
#ifndef ___DEBUG_ALLOC_MEM
void *___alloc_mem(___SIZE_T bytes)
#else
void *___alloc_mem(___SIZE_T bytes, int line, char *file)
#endif
{
  fputs("unexpected allocation in collector diagnostic\n",stderr);
  abort();
}

#ifndef ___DEBUG_ALLOC_MEM
void ___free_mem(void *ptr)
#else
void ___free_mem(void *ptr, int line, char *file)
#endif
{
  fputs("unexpected free in collector diagnostic\n",stderr);
  abort();
}

#ifndef ___DEBUG_ALLOC_MEM
void *___alloc_mem_heap(___SIZE_T bytes)
#else
void *___alloc_mem_heap(___SIZE_T bytes, int line, char *file)
#endif
{
  fputs("unexpected heap allocation in collector diagnostic\n",stderr);
  abort();
}

#ifndef ___DEBUG_ALLOC_MEM
void ___free_mem_heap(void *ptr)
#else
void ___free_mem_heap(void *ptr, int line, char *file)
#endif
{
  fputs("unexpected heap free in collector diagnostic\n",stderr);
  abort();
}

static char report[32768];
static size_t used;
static int expect_fatal;
static const char *expect_contract;
static jmp_buf contract_env;
static int contract_armed;

int ___printf(const char *format, ...)
{
  va_list ap;
  int n;
  va_start(ap,format);
  n=vsnprintf(report+used,sizeof(report)-used,format,ap);
  va_end(ap);
  if(n<0 || (size_t)n>=sizeof(report)-used) exit(80);
  used+=(size_t)n;
  return n;
}

void ___fatal_error(char **messages)
{
  if(contract_armed && expect_contract && messages && messages[0] &&
     strcmp(messages[0], expect_contract)==0) {
    contract_armed=0;
    longjmp(contract_env, 1);
  }
  if(expect_fatal && messages && messages[0] &&
     strstr(report,"W7 (carrier P0)") && strstr(report,"line 123") &&
     strstr(report,"reference counted object") && !strstr(report,"line 999")) {
    puts("COLLECTOR-DIAGNOSTIC-FATAL-PASS selected-worker");
    exit(73);
  }
  fputs(report,stderr);
  if(messages && messages[0]) fprintf(stderr,"fatal: %s\n", messages[0]);
  exit(81);
}

/* The isolated test has no asynchronous interrupt producer. Keep the
 * real prepare_mem_pstate and its cursor calculations. */
#ifndef ___GAMBIT_DEV_RESTORE_PROBE
void ___refresh_interrupts_pstate(___processor_state ps)
{
  (void)ps;
}
#else
/* The real barrier's processor-count branch links the interrupt path.
 * This control never resizes or enters the I/O wait machinery. */
void ___device_select_abort(___processor_state ps)
{
  (void)ps;
  abort();
}
#endif

#define CHECK(x) do { if(!(x)) {fprintf(stderr,"collector-diagnostics:%d: %s\n%s",__LINE__,#x,report);return 1;} } while(0)

/* setjmp stays in the rejecting function. A helper that returned first would
 * make the longjmp target undefined. */
#define REJECT(msg, invoke) do { \
  expect_contract=(msg); contract_armed=1; \
  if(setjmp(contract_env)==0) { \
    invoke; \
    fprintf(stderr,"collector-diagnostics:%d: missing rejection %s\n",__LINE__,msg); \
    return 1; \
  } \
  expect_contract=0; \
} while(0)

/* Allocate backing slot arrays via calloc so the ___alloc_mem trap stays armed. */
static int diag_bind_round_storage(___root_round *round, int cap)
{
  ___gc_round *g;
  ___SIZE_T total = 0, off = 0, ucap, hcap;
  unsigned char *buf;
  if (!round || cap < 1) return 0;
  if (round->slot_storage != 0) return 1;
  ucap = ___CAST(___SIZE_T, cap);
  hcap = ucap * ___CAST(___SIZE_T, ___GC_CARD_HINT_CAPACITY);
  g = &round->collection;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->members))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->workers))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->resume))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->globals.shards))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->worker_proc))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->proc_worker))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->active))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->active_procs))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->observed))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tails))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_starts))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_ends))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_is_hole))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->major_reclaimed_still))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->major_live_still))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->young_heap_secs))) return 0;
  if (!___vm_slot_add_slice(&total, hcap, sizeof(*g->hints))) return 0;
  buf = (unsigned char*)calloc(1, total);
  if (!buf) return 0;
  round->slot_capacity = cap;
  round->slot_storage = buf;
  g->slot_capacity = cap;
  g->hint_capacity = cap * ___GC_CARD_HINT_CAPACITY;
  round->members = (___root_member*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->members));
  round->workers = (___collector_worker*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->workers));
  round->resume = (___gc_resume_space*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->resume));
  round->globals.shards = (unsigned char*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->globals.shards));
  round->globals.shard_capacity = cap;
  g->worker_proc = (int*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->worker_proc));
  g->proc_worker = (int*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->proc_worker));
  g->active = (unsigned char*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->active));
  g->active_procs = (int*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->active_procs));
  g->observed = (int*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->observed));
  g->promo_tails = (___msection**)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tails));
  g->promo_tail_starts = (___SIZE_TS*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_starts));
  g->promo_tail_ends = (___SIZE_TS*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_ends));
  g->promo_tail_is_hole = (unsigned char*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_is_hole));
  g->major_reclaimed_still = (___SIZE_TS*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->major_reclaimed_still));
  g->major_live_still = (___SIZE_TS*)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->major_live_still));
  g->young_heap_secs = (___msection**)___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->young_heap_secs));
  g->hints = (___gc_card_hint*)___vm_slot_carve_slice(buf, &off, hcap, sizeof(*g->hints));
  return 1;
}

/* Install the preflight span move_continuation now requires. The floor is
 * the destination lower bound; source_half is the half that still holds fp. */
static int admit_span(___processor_state ps, ___msection *source,
                      ___SIZE_TS source_half, ___msection *destination,
                      ___WORD *floor, ___WORD epoch)
{
  ___virtual_machine_state vm;
  ___processor_state root;
  ___gc_resume_space *r;
  ___SIZE_TS words=0;
  ___WORD *half;
  int id;
  static ___rc_domain fallback_domain;
  static ___root_round fallback_round;
#ifndef ___SINGLE_THREADED_VMS
  if(ps->vmstate==0) return 0;
#endif
  vm=___VMSTATE_FROM_PSTATE(ps);
  root=___PSTATE_FROM_PROCESSOR_ID(0,vm);
  if(root->mem.rc_domain_==0) {
    memset(&fallback_domain,0,sizeof fallback_domain);
    CHECK(diag_bind_round_storage(&fallback_round,___MAX_PROCESSORS));
    root->mem.rc_domain_=&fallback_domain;
    fallback_domain.round=&fallback_round;
  } else if(root->mem.rc_domain_->round==0) {
    CHECK(diag_bind_round_storage(&fallback_round,___MAX_PROCESSORS));
    root->mem.rc_domain_->round=&fallback_round;
  } else if(root->mem.rc_domain_->round->slot_storage==0) {
    CHECK(diag_bind_round_storage(root->mem.rc_domain_->round,___MAX_PROCESSORS));
  }
  id=___PROCESSOR_ID(ps,vm);
  r=&___RESUME(vm,id);
  memset(r,0,sizeof *r);
  r->context=ps->context;
  r->owner=ps;
  r->epoch=epoch;
  ___COLLECTION(vm).epoch=epoch;
  if(___COLLECTION(vm).worker_count<1) ___COLLECTION(vm).worker_count=1;
  if(___COLLECTION(vm).participant_count<id+1)
    ___COLLECTION(vm).participant_count=id+1;
  r->source_worker=id<___COLLECTION(vm).worker_count?id:-1;
  r->stack_section=destination;
  r->source_section=source;
  r->source_fp=ps->context->fp;
  r->source_break=ps->context->stack_break;
  r->source_half=source_half;
  section_claim_at(source,source_half)->stack_owner=ps;
  section_claim_at(source,source_half)->stack_state=STACK_ACTIVE;
  r->stack_floor=floor;
  ps->mem.stack_msection_=destination;
  ps->mem.alloc_stack_limit_=floor;
  half=source->base+source_half;
  if(!___gc_stack_span_words(half,half+(___MSECTION_SIZE>>1),
       r->source_fp,r->source_break,___FIRST_BREAK_FRAME_SPACE,&words))
    return 0;
  r->source_words=words;
  return 1;
}

/* Only the dedicated threaded control enables this cut. The reader stops
 * immediately before the real final old-space load in move_continuation. */
#ifdef ___GC_TEST_BEFORE_FINAL_RESTORE_READ
#ifdef SECTION_BYTES
static atomic_int restore_cut;
static pthread_mutex_t restore_mutex=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t restore_cv=PTHREAD_COND_INITIALIZER;
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
static int collective_control;
#endif

#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
static ___msection *shared_closure_section;

/* include/gambit.h is the configured aggregate and has no probe expansions.
 * These are the branches already present in the .in templates. They apply
 * only to statements compiled later in this file. Production units keep
 * the aggregate header, and configure is not run. */
#undef ___DEV_RESTORE_HOST_TEXT_
#undef ___DEV_RESTORE_HOST_TEXT
#define ___DEV_RESTORE_HOST_TEXT_(host) #host
#define ___DEV_RESTORE_HOST_TEXT(host) ___DEV_RESTORE_HOST_TEXT_(host)
#undef ___R_HEAP_EXPR
#define ___R_HEAP_EXPR (___hp=___dev_restore_alloc_reload(___ps,___PSHEAP))
#undef ___ALLOC
#define ___ALLOC(n) (___hp += ___dev_restore_census_bump(___ps,___hp,(___SIZE_TS)(n)))
#undef ___BEGIN_ALLOC_SUBTYPED
#define ___BEGIN_ALLOC_SUBTYPED(hd)(___dev_restore_census_other(___ps,___hp,"subtyped-header"),___hp[0] = (hd))
#undef ___ALLOC_CLO
#define ___ALLOC_CLO(n)(___dev_restore_alloc_before(___ps,&___hp,(___SIZE_TS)(n),(___SIZE_TS)((n)+___CLO_FREEVARS+___SUBTYPED_BODY),___DEV_RESTORE_HOST_TEXT(___PH_PROC)),___BEGIN_ALLOC_SUBTYPED(___MAKE_HD_WORDS(n+___CLO_FREEVARS,___sPROCEDURE)),___END_ALLOC_SUBTYPED(n+___CLO_FREEVARS),___dev_restore_alloc_after(___ps,___hp),___GET_SUBTYPED(n+___CLO_FREEVARS))
#undef ___BEGIN_SETUP_CLO
#define ___BEGIN_SETUP_CLO(n,clo,lbl) \
{___WORD *___ptr=___BODY0_AS(clo,___tSUBTYPED); \
___WORD ___dev_label=___LBL(lbl); \
___ptr[___LABEL_ENTRY_OR_DESCR]=___dev_label; \
___CLO_LOWLEVEL_TRAMPOLINE_SETUP(___ptr,___dev_label); \
___dev_restore_clo_label(___ps,___ptr,___dev_label,lbl);
#undef ___ADD_CLO_ELEM
#define ___ADD_CLO_ELEM(i,val) do{___WORD ___dev_v=(val);___SIZE_TS ___dev_i=(___SIZE_TS)(i);___ptr[___dev_i+___CLO_FREEVARS]=___dev_v;___dev_restore_clo_field(___ps,___ptr,___dev_i,___dev_v);}while(0);

/* The include contains the allocator statements from the current
 * join-wait receiver. This control supplies input registers and label
 * storage; it never enters the scheduler thunk. */
static int generated_join_allocation(___processor_state ___ps)
{
  static ___msection other_section;
  ___WORD labels[4*___LABEL_SIZE]={0};
  ___WORD ___start=(___WORD)(uintptr_t)labels;
  ___WORD *begin=___ps->mem.alloc_heap_ptr_;
  ___SIZE_TS words=4+___CLO_FREEVARS+___SUBTYPED_BODY;
  ___D_HEAP
  ___D_FP
  ___D_R1
  ___D_R2
  ___D_R3
  prepare_mem_pstate(___ps);
  ___dev_restore_alloc_arm(___ps,4);
  ___ps->context->r[1]=___FIX(41);
  ___ps->context->r[2]=___FIX(42);
  ___ps->context->r[3]=___FIX(43);
  ___R_FP
  ___R_R1
  ___R_R2
  ___R_R3
  if (collective_control==3) {
    ___ps->context->hp=begin+1;
    ___R_HEAP
    ___ps->context->hp=begin;
  }
  ___R_HEAP
  if (collective_control==4)
    ___ps->mem.heap_msection_=&other_section;
  if (collective_control==5)
    ___ps->mem.tospace_offset_=0;
#include "generated-join-alloc.inc"
  CHECK(___hp==begin+words);
  CHECK(begin[0]==___MAKE_HD_WORDS(4+___CLO_FREEVARS,___sPROCEDURE));
  CHECK(___CLO(___STK(1),1)==___STK(1));
  CHECK(___CLO(___STK(1),2)==___FIX(42));
  CHECK(___CLO(___STK(1),3)==___FIX(43));
  CHECK(___CLO(___STK(1),4)==___FIX(41));
  CHECK(begin[words]==___FIX(71));
  return 0;
}
#endif

static void before_final_restore_read(void)
{
  if (atomic_load(&restore_cut)!=1)
    return;
  pthread_mutex_lock(&restore_mutex);
  atomic_store(&restore_cut,2);
  pthread_cond_signal(&restore_cv);
  while (atomic_load(&restore_cut)==2)
    pthread_cond_wait(&restore_cv,&restore_mutex);
  pthread_mutex_unlock(&restore_mutex);
}

static void *restore_reader(void *arg)
{
  ___processor_state ___ps=arg;
  move_continuation(___PSPNC);
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  if (collective_control) {
    if (*___ps->mem.alloc_stack_ptr_!=___FIX(42)) _Exit(82);
    ___dev_restore_after_reader(___ps,4);
    barrier_sync_noop(___PSPNC);
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
    if (collective_control>=2) {
      barrier_sync_noop(___PSPNC);
      if (generated_join_allocation(___ps)!=0) _Exit(83);
    }
#endif
  }
#endif
  return 0;
}
#else
static void before_final_restore_read(void) {}
#endif
#endif

static int delayed_restore_reader(int early, int collective)
{
  static ___virtual_machine_state_struct vm;
  int guarded=early==2;
  ___processor_state ps=___PSTATE_FROM_PROCESSOR_ID(collective!=0 || guarded,&vm);
  ___execution_context context={0};
  ___execution_context coordinator_context={0};
  ___root_round *round=0;
  ___msections sections={0};
  ___msection *section=0;
  ___SIZE_TS half=___MSECTION_SIZE>>1;
  pthread_t reader;
  int held;
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
  section=shared_closure_section;
#endif
  if (!section) section=calloc(1,SECTION_BYTES);
  CHECK(section);
  sections.head=section;
  ps->context=&context;
#ifndef ___SINGLE_THREADED_VMS
  ps->vmstate=&vm;
#endif
  /* Source half stays 0 while the destination cursor lives in the other half.
   * The paused reader still retires only the source claim. */
  ps->mem.tospace_offset_=half;
  context.fp=section->base;
  context.stack_break=section->base+1;
  section->base[0]=___FIX(42);
  CHECK(admit_span(ps, section, 0, section, section->base+half, 4));
  ps->mem.alloc_stack_start_=section->base+half+64;
  ps->mem.alloc_stack_ptr_=ps->mem.alloc_stack_start_;
  section_claim_at(section,0)->heap_used=1;
  section_claim_at(section,half)->heap_used=1;
  if (guarded) {
    ___processor_state coordinator=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
    coordinator->context=&coordinator_context;
    round=___ROOT_UNION(&vm);
    round->state=___ROOT_ROUND_DRAINING;
    round->epoch=4;
    round->participants=2;
    round->collection.destination_offset=half;
    round->members[0].owner=coordinator;
    round->members[0].context=&coordinator_context;
    round->members[1].owner=ps;
    round->members[1].context=&context;
    round->resume[0]=(___gc_resume_space){
      .owner=coordinator, .context=&coordinator_context, .epoch=4,
      .accepted=1, .restored=1, .source_drained=1
    };
    round->resume[1].accepted=1;
  }

#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  if (collective) {
    ___processor_state parent=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
    CHECK(pthread_mutex_init(&parent->sync_mut,0)==0);
    CHECK(pthread_cond_init(&parent->sync_cv,0)==0);
    CHECK(pthread_mutex_init(&ps->sync_mut,0)==0);
    CHECK(pthread_cond_init(&ps->sync_cv,0)==0);
    parent->vmstate=&vm;
    parent->sync_id0=parent->sync_id1=parent->sync_id2=-1;
    ps->sync_id0=ps->sync_id1=ps->sync_id2=-1;
    vm.processor_count=2;
    collective_control=collective;
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
    if (collective>=2) {
      vm.mem.heap_size_=___MSECTION_SIZE;
      ps->mem.alloc_stack_start_=section->base+half+___MSECTION_FUDGE+64;
      ps->mem.alloc_stack_ptr_=ps->mem.alloc_stack_start_;
      ps->mem.heap_msection_=section;
      ps->mem.alloc_heap_start_=section->base+half+___MSECTION_FUDGE+128;
      ps->mem.alloc_heap_ptr_=ps->mem.alloc_heap_start_;
      ps->mem.alloc_heap_limit_=section->base+___MSECTION_SIZE;
      ps->mem.alloc_heap_ptr_[4+___CLO_FREEVARS+___SUBTYPED_BODY]=___FIX(71);
    }
#endif
    CHECK(pthread_create(&reader,0,restore_reader,ps)==0);
    if (!___dev_restore_before_barrier(parent,4))
      barrier_sync_noop(parent);
    ___dev_restore_after_barrier(parent,4);
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
    if (collective>=2) {
      CHECK(section_claim_at(section,0)->heap_used);
      retire_section_claims(&sections,0,0);
      barrier_sync_noop(parent);
    }
#endif
    CHECK(pthread_join(reader,0)==0);
    if (collective==1) {
      CHECK(section_claim_at(section,0)->heap_used);
      retire_section_claims(&sections,0,0);
    }
    CHECK(!section_claim_at(section,0)->heap_used);
    CHECK(section_claim_at(section,half)->heap_used);
    if (collective==1) puts("PRODUCTION-RESTORE-EDGE-PASS");
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
    if (collective>=2) puts("GENERATED-RESTORE-CLOSURE-PAYLOAD-PASS");
    if (section!=shared_closure_section)
#endif
      free(section);
    return 0;
  }
#endif
  atomic_store(&restore_cut,1);
  CHECK(pthread_create(&reader,0,restore_reader,ps)==0);
  pthread_mutex_lock(&restore_mutex);
  while (atomic_load(&restore_cut)!=2)
    pthread_cond_wait(&restore_cv,&restore_mutex);
  /* Mutate only claim metadata in the negative arm. Never free or reuse
   * storage while a native reader can still dereference it. */
  if (guarded) {
    CHECK(!retire_drained_source_claims(round,&sections,4));
    CHECK(section_claim_at(section,0)->heap_used);
    puts("DRAINED-RETIRE-HELD-READER-REFUSED");
  } else if (early)
    retire_section_claims(&sections,0,0);
  held=section_claim_at(section,0)->heap_used;
  atomic_store(&restore_cut,3);
  pthread_cond_signal(&restore_cv);
  pthread_mutex_unlock(&restore_mutex);
  CHECK(pthread_join(reader,0)==0);
  CHECK(held==(guarded || !early));
  CHECK(*ps->mem.alloc_stack_ptr_==___FIX(42));
  if (guarded) {
    CHECK(round->resume[1].copy_admitted);
    round->resume[1].restored=1;
    CHECK(!retire_drained_source_claims(round,&sections,4));
    CHECK(section_claim_at(section,0)->heap_used);
    puts("DRAINED-RETIRE-RESTORED-WITH-CLEANUP-PENDING-REFUSED");
    round->resume[1].source_drained=1;
    round->resume[1].epoch=3;
    CHECK(!retire_drained_source_claims(round,&sections,4));
    round->resume[1].epoch=4;
    round->resume[1].source_half=half;
    CHECK(!retire_drained_source_claims(round,&sections,4));
    CHECK(section_claim_at(section,0)->heap_used);
    puts("DRAINED-RETIRE-WRONG-EPOCH-OR-HALF-REFUSED");
    round->resume[1].source_half=0;
    CHECK(retire_drained_source_claims(round,&sections,4));
  } else if (!early)
    retire_section_claims(&sections,0,0);
  CHECK(!section_claim_at(section,0)->heap_used);
  CHECK(section_claim_at(section,half)->heap_used);
  free(section);
  puts(guarded ? "DRAINED-RETIRE-SOURCE-ONLY-PASS" :
       early ? "DELAYED-RESTORE-READER-EARLY-RETIRE-DETECTED"
             : "DELAYED-RESTORE-READER-DRAIN-PASS");
  return 0;
}

#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
static int generated_closure_refusal(int control)
{
  ___WORD *boundary;
  ___SIZE_TS words=4+___CLO_FREEVARS+___SUBTYPED_BODY;
  ___SIZE_TS checked_words=control==2 ? words-1 : words;
  pid_t child;
  int status;
  shared_closure_section=mmap(0,SECTION_BYTES,PROT_READ|PROT_WRITE,
                              MAP_ANON|MAP_SHARED,-1,0);
  CHECK(shared_closure_section!=MAP_FAILED);
  boundary=control==2 ? shared_closure_section->base+___MSECTION_SIZE-(words-1)
                      : shared_closure_section->base+(___MSECTION_SIZE>>1)+___MSECTION_FUDGE+128;
  for (___SIZE_TS i=0;i<checked_words;i++) boundary[i]=___FIX(72);
  child=fork();
  CHECK(child>=0);
  if (child==0) _Exit(delayed_restore_reader(0,control)==0 ? 84 : 85);
  CHECK(waitpid(child,&status,0)==child);
  CHECK(WIFEXITED(status) && WEXITSTATUS(status)==(control==2?0:79));
  for (___SIZE_TS i=0;i<checked_words;i++) CHECK(boundary[i]==___FIX(72));
  CHECK(munmap(shared_closure_section,SECTION_BYTES)==0);
  switch (control) {
  case 2: puts("GENERATED-RESTORE-SHORT-SPAN-NO-WRITE"); break;
  case 3: puts("GENERATED-RESTORE-STALE-RELOAD-NO-WRITE"); break;
  case 4: puts("GENERATED-RESTORE-SECTION-DRIFT-NO-WRITE"); break;
  case 5: puts("GENERATED-RESTORE-PARITY-DRIFT-NO-WRITE"); break;
  }
  return 0;
}
#endif

/* Exercise the actual GC restoration consumer, not a copy of its algorithm.
 * The first break and active top coincide only for the empty segment. */
static int restoration_overflow_ownership(___processor_state ___ps)
{
  ___execution_context context, *previous_context=___ps->context;
  ___WORD *previous_start=___ps->mem.alloc_stack_start_;
  ___WORD *previous_ptr=___ps->mem.alloc_stack_ptr_;
  ___WORD *previous_limit=___ps->mem.alloc_stack_limit_;
  ___msection *previous_stack=___ps->mem.stack_msection_;
  ___SIZE_TS previous_half=___ps->mem.tospace_offset_;
  ___msection *source_ms=calloc(1,SECTION_BYTES);
  ___msection *dest_ms=calloc(1,SECTION_BYTES);
  int active;
  CHECK(source_ms && dest_ms);
#ifndef ___SINGLE_THREADED_VMS
  if(___ps->vmstate==0) {
    fprintf(stderr,"collector-diagnostics: restoration carrier has no vm\n");
    return 1;
  }
#endif
  memset(&context,0,sizeof context);
  ___ps->context=&context;
  ___ps->mem.tospace_offset_=0;
  for(active=0;active<=16;active+=8) {
    int length=active+___FIRST_BREAK_FRAME_SPACE;
    ___WORD *source_top=source_ms->base+16;
    ___WORD *destination_high=dest_ms->base+96;
    ___WORD *destination_top=destination_high-length;
    ___WORD *destination_break=destination_high-___FIRST_BREAK_FRAME_SPACE;
    ___WORD expected[128];
    int i;
    ___virtual_machine_state vm;
    for(i=0;i<128;i++) {
      source_ms->base[i]=___FIX(100+i);
      dest_ms->base[i]=___FIX(-100-i);
    }
    context.fp=source_top;
    context.stack_break=source_top+active;
    ___FP_SET_STK(context.stack_break,-___FIRST_BREAK_FRAME_STACK_MSECTION,
                 ___CAST(___WORD,source_ms->base+120))
    ___ps->mem.alloc_stack_start_=destination_high;
    ___ps->mem.alloc_stack_ptr_=destination_high;
    ___ps->mem.alloc_stack_limit_=dest_ms->base;
    ___ps->mem.stack_msection_=dest_ms;
    CHECK(admit_span(___ps, source_ms, 0, dest_ms, dest_ms->base, 1));
    memcpy(expected,dest_ms->base,sizeof expected);
    memcpy(expected+(destination_top-dest_ms->base),source_top,length*sizeof(___WORD));
    ___FP_SET_STK((expected+(destination_break-dest_ms->base)),
                 -___FIRST_BREAK_FRAME_STACK_MSECTION,0)
    CHECK(move_continuation(___PSPNC));
    vm=___VMSTATE_FROM_PSTATE(___ps);
    CHECK(___RESUME(vm,___PROCESSOR_ID(___ps,vm)).copy_admitted);
    CHECK(___ps->mem.alloc_stack_ptr_==destination_top);
    CHECK(context.stack_break==destination_break);
    CHECK(memcmp(dest_ms->base,expected,sizeof expected)==0);
  }
  ___ps->context=previous_context;
  ___ps->mem.alloc_stack_start_=previous_start;
  ___ps->mem.alloc_stack_ptr_=previous_ptr;
  ___ps->mem.alloc_stack_limit_=previous_limit;
  ___ps->mem.stack_msection_=previous_stack;
  ___ps->mem.tospace_offset_=previous_half;
  free(source_ms);
  free(dest_ms);
  return 0;
}

/* Seed the exact pre-undo state produced by stack growth out of a
 * stack/heap loan. Use the real undo, with a recognizable outgoing word
 * and a saved floor that is deliberately different from the section base. */
static int stack_section_ownership(void)
{
  static ___virtual_machine_state_struct vm;
  ___processor_state ___ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___execution_context context={0};
  ___msections sections={0};
#ifdef SECTION_BYTES
  size_t bytes=SECTION_BYTES;
#else
  size_t bytes=___sizeof_msection(___MSECTION_SIZE);
#endif
  ___msection *shared=calloc(1,bytes);
  ___msection *outgoing=calloc(1,bytes);
  ___WORD *floor, *parked_break, *first;
  ___WORD ra=___FIX(42), marker=___FIX(99);
  CHECK(shared && outgoing);
#ifndef ___SINGLE_THREADED_VMS
  ___ps->vmstate=&vm;
#endif
  ___ps->context=&context;
  ___ps->mem.tospace_offset_=0;
  set_stack_msection(___ps,shared);
  set_heap_msection_possibly_sharing_with_stack(___ps,shared);
  floor=___ps->mem.alloc_stack_limit_;
  CHECK(floor>shared->base);
  parked_break=___ps->mem.alloc_stack_start_-___FIRST_BREAK_FRAME_SPACE;
  ___FP_SET_STK((parked_break-8),-___FRAME_STACK_RA,ra)
  ___ps->mem.words_prev_msections_=___FIRST_BREAK_FRAME_SPACE+8;
#ifdef SECTION_BYTES
  park_stack_section(___ps,shared,floor,parked_break-8,parked_break);
#endif
  set_stack_msection(___ps,outgoing);
  first=___ps->mem.alloc_stack_start_-___FIRST_BREAK_FRAME_SPACE;
  context.stack_start=___ps->mem.alloc_stack_start_;
  context.stack_break=context.fp=first;
  ___FP_SET_STK(first,-___FIRST_BREAK_FRAME_STACK_MSECTION,___CAST(___WORD,shared))
  ___FP_SET_STK(first,-___FIRST_BREAK_FRAME_STACK_BREAK,___CAST(___WORD,parked_break))
  ___FP_SET_STK(first,-___BREAK_FRAME_NEXT,___CAST(___WORD,parked_break-8))
  outgoing->base[0]=marker;
#ifdef SECTION_BYTES
  ___FP_SET_STK(first,-___BREAK_FRAME_NEXT,___CAST(___WORD,parked_break-9))
  REJECT("Stack undo does not match the parked source span",
         ___stack_overflow_undo_if_possible(___PSPNC));
  CHECK(context.fp==first && context.stack_break==first);
  CHECK(section_claim_at(shared,0)->stack_state==STACK_PARKED);
  CHECK(___FP_STK(first,-___FIRST_BREAK_FRAME_STACK_MSECTION)==___CAST(___WORD,shared));
  ___FP_SET_STK(first,-___BREAK_FRAME_NEXT,___CAST(___WORD,parked_break-8))
  puts("PARKED-UNDO-WRONG-TOP-REFUSED");
#endif
  CHECK(___stack_overflow_undo_if_possible(___PSPNC)==ra);
  CHECK(context.fp==parked_break-8 && context.stack_break==parked_break);
  CHECK(___ps->mem.alloc_stack_limit_==floor);
  CHECK(___ps->mem.alloc_heap_limit_<=floor);
  CHECK(outgoing->base[0]==marker);
  CHECK(___ps->mem.words_prev_msections_==0);
#ifdef SECTION_BYTES
  CHECK(!section_claim_at(shared,0)->parked_top && !section_claim_at(shared,0)->parked_break);
  CHECK(take_released_stack_section(___ps)==outgoing);
  CHECK(take_released_stack_section(___ps)==0);
  CHECK(section_claim_at(outgoing,0)->stack_state==STACK_UNCLAIMED);
  /* The old half and its protected heap claim coexist with the new half
   * until the collector's explicit retire cut. */
  section_claim_at(shared,___MSECTION_SIZE>>1)->stack_owner=___ps;
  section_claim_at(shared,___MSECTION_SIZE>>1)->stack_state=STACK_ACTIVE;
  CHECK(section_claim_at(shared,0)->heap_used);
  sections.head=shared;
  shared->next=outgoing;
  retire_section_claims(&sections,0,0);
  CHECK(!section_claim_at(shared,0)->heap_used);
  CHECK(section_claim_at(shared,0)->stack_state==STACK_UNCLAIMED);
  CHECK(section_claim_at(shared,___MSECTION_SIZE>>1)->stack_owner==___ps);
  CHECK(section_claim_at(shared,___MSECTION_SIZE>>1)->stack_state==STACK_ACTIVE);
#endif
  free(outgoing);
  free(shared);
  puts("STACK-SECTION-OWNERSHIP-PASS parked-floor payload two-parities");
  return 0;
}

/* Legal reusable section, wrong-section old cursor. Rejection must leave the
 * reuse list, the 42-word account, and the published heap section alone.
 * The following call accounts the 10-word gap once and unlinks only R. */
static int heap_cursor_controls(void)
{
  static ___virtual_machine_state_struct vm;
  ___processor_state ___ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___execution_context context={0};
  ___msection *stack=calloc(1,SECTION_BYTES);
  ___msection *heap=calloc(1,SECTION_BYTES);
  ___msection *reusable=calloc(1,SECTION_BYTES);
  ___msection *sentinel=calloc(1,SECTION_BYTES);
  ___msection *foreign_heap=calloc(1,SECTION_BYTES);
  ___WORD *kept, *stack_top;
  CHECK(stack && heap && reusable && sentinel && foreign_heap);
#ifndef ___SINGLE_THREADED_VMS
  ___ps->vmstate=&vm;
#endif
  ___ps->context=&context;
  ___ps->mem.tospace_offset_=0;
  set_stack_msection(___ps, stack);
  stack_top=___ps->mem.alloc_stack_ptr_;
  context.fp=stack_top;
  set_heap_msection(___ps, heap);
  ___ps->mem.words_prev_msections_=42;
  ___ps->mem.alloc_heap_ptr_=___ps->mem.alloc_heap_start_+10;
  kept=___ps->mem.alloc_heap_ptr_;
  /* Another carrier's published heap has a legal cursor and heap_used claim.
   * It must not unlink this carrier's list or change the word account, and
   * the unadmitted fp must not be stored. */
  section_claim_at(foreign_heap,0)->heap_used=1;
  context.fp=stack_top-4;
  context.hp=foreign_heap->base+10;
  REJECT("Heap limit old cursor leaves its owned active half",
         ___heap_limit(___PSPNC));
  CHECK(___ps->mem.alloc_stack_ptr_==stack_top);
  CHECK(___ps->mem.alloc_heap_ptr_==kept);
  CHECK(___ps->mem.words_prev_msections_==42);
  CHECK(___ps->mem.msection_free_list_==0);
  CHECK(___ps->mem.heap_msection_==heap);
  context.fp=stack_top;
  puts("HEAP-CURSOR-FOREIGN-CARRIER-UNCHANGED");
  section_claim_at(reusable,0)->stack_owner=___ps;
  section_claim_at(reusable,0)->stack_state=STACK_REUSABLE;
  section_claim_at(reusable,0)->heap_used=0;
  section_claim_at(reusable,0)->reuse_next=sentinel;
  section_claim_at(sentinel,0)->stack_owner=___ps;
  section_claim_at(sentinel,0)->stack_state=STACK_REUSABLE;
  section_claim_at(sentinel,0)->heap_used=0;
  section_claim_at(sentinel,0)->reuse_next=0;
  ___ps->mem.msection_free_list_=reusable;
  context.hp=reusable->base+10;
  REJECT("Heap limit old cursor leaves its owned active half",
         ___heap_limit(___PSPNC));
  CHECK(___ps->mem.msection_free_list_==reusable);
  CHECK(section_claim_at(reusable,0)->reuse_next==sentinel);
  CHECK(section_claim_at(reusable,0)->stack_state==STACK_REUSABLE);
  CHECK(section_claim_at(sentinel,0)->stack_state==STACK_REUSABLE);
  CHECK(!section_claim_at(reusable,0)->heap_used);
  CHECK(!section_claim_at(sentinel,0)->heap_used);
  CHECK(section_claim_at(reusable,0)->stack_owner==___ps);
  CHECK(section_claim_at(sentinel,0)->stack_owner==___ps);
  CHECK(___ps->mem.words_prev_msections_==42);
  CHECK(___ps->mem.heap_msection_==heap);
  CHECK(___ps->mem.alloc_heap_ptr_==kept);
  CHECK(section_claim_at(heap,0)->heap_used);
  context.hp=kept;
  CHECK(___heap_limit(___PSPNC)==0);
  CHECK(___ps->mem.words_prev_msections_==52);
  CHECK(___ps->mem.msection_free_list_==sentinel);
  CHECK(section_claim_at(sentinel,0)->reuse_next==0);
  CHECK(section_claim_at(sentinel,0)->stack_state==STACK_REUSABLE);
  CHECK(!section_claim_at(sentinel,0)->heap_used);
  CHECK(___ps->mem.heap_msection_==reusable);
  CHECK(section_claim_at(reusable,0)->heap_used);
  /* Physical half membership alone would accept a heap limit in the
   * reserved stack interval. The ordinary heap-limit path must refuse
   * before changing either cursor or consuming its reusable section. */
  set_stack_msection(___ps,heap);
  set_heap_msection_possibly_sharing_with_stack(___ps,heap);
  {
    ___WORD *floor=___ps->mem.alloc_stack_limit_;
    ___WORD *top=___ps->mem.alloc_stack_start_-___FIRST_BREAK_FRAME_SPACE-___FRAME_SPACE(1);
    ___WORD *brk=top+___FRAME_SPACE(1);
    ___WORD *cursor=___ps->mem.alloc_heap_ptr_;
    ___ps->mem.alloc_heap_limit_=floor;
    CHECK(current_heap_interval_matches(___ps,cursor));
    CHECK(___heap_alloc_fits(___ps,floor-1,1));
    CHECK(!___heap_alloc_fits(___ps,floor-1,2));
    CHECK(!___heap_alloc_fits(___ps,floor,1));
    ___ps->mem.alloc_heap_limit_=floor+1;
    CHECK(!___heap_alloc_fits(___ps,floor,1));
    context.hp=floor+1;
    context.fp=top;
    REJECT("Heap limit old cursor leaves its owned active half",
           ___heap_limit(___PSPNC));
    CHECK(___ps->mem.alloc_heap_ptr_==cursor);
    CHECK(___ps->mem.alloc_stack_ptr_==___ps->mem.alloc_stack_start_);
    CHECK(___ps->mem.msection_free_list_==sentinel);
    puts("HEAP-SHARED-ACTIVE-STACK-OVERLAP-REFUSED");

    park_stack_section(___ps,heap,floor,top,brk);
    set_stack_msection(___ps,stack);
    CHECK(!current_heap_interval_matches(___ps,floor+1));
    ___ps->mem.alloc_heap_limit_=floor;
    CHECK(current_heap_interval_matches(___ps,cursor));
    CHECK(___heap_alloc_fits(___ps,floor-1,1));
    CHECK(!___heap_alloc_fits(___ps,floor,1));
    CHECK(!___heap_alloc_fits(___ps,foreign_heap->base,1));
    section_claim_at(heap,0)->heap_used=0;
    CHECK(!___heap_alloc_fits(___ps,floor-1,1));
    section_claim_at(heap,0)->heap_used=1;
    puts("HEAP-PARKED-STACK-FLOOR-EXACT-FIT");
  }
  free(stack); free(heap); free(reusable); free(sentinel); free(foreign_heap);
  puts("HEAP-CURSOR-REJECT-BEFORE-UNLINK");
  puts("HEAP-CURSOR-ACCOUNT-UNLINK-ONCE");
  return 0;
}

/* Exact fit copies the admitted span and clears its overflow slot.
 * One word short, a moved source endpoint, the wrong context, and a stale
 * epoch all return before any destination or context write. */
static int continuation_extent_controls(void)
{
  static ___virtual_machine_state_struct vm;
  static ___rc_domain domain;
  static ___root_round round;
  ___processor_state ___ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___execution_context context={0}, other={0};
  ___msection *source=calloc(1,SECTION_BYTES);
  ___msection *dest=calloc(1,SECTION_BYTES);
  ___WORD *sfp, *floor, *short_ptr, *exact_ptr;
  ___WORD *saved_break;
  ___WORD image[32];
  ___gc_resume_space *r;
  int active=8, span, i, slot;
  CHECK(source && dest);
#ifndef ___SINGLE_THREADED_VMS
  ___ps->vmstate=&vm;
#endif
  ___ps->mem.rc_domain_=&domain;
  if(round.slot_storage==0) CHECK(diag_bind_round_storage(&round,___MAX_PROCESSORS));
  domain.round=&round;
  ___ps->context=&context;
  ___ps->mem.tospace_offset_=0;
  sfp=source->base+32;
  floor=dest->base+16;
  context.fp=sfp;
  context.stack_break=sfp+active;
  span=active+___FIRST_BREAK_FRAME_SPACE;
  CHECK(span+2<=(int)(sizeof image/sizeof image[0]));
  for(i=0;i<span;i++) sfp[i]=___FIX(100+i);
  ___FP_SET_STK(context.stack_break,-___FIRST_BREAK_FRAME_STACK_MSECTION,___FIX(77))
  CHECK(admit_span(___ps, source, 0, dest, floor, 1));
  r=&___RESUME(___VMSTATE_FROM_PSTATE(___ps),
               ___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps)));
  CHECK(r->source_words==(___SIZE_TS)span);
  CHECK(r->context==&context && r->owner==___ps && r->epoch==1);
  for(i=0;i<span+2;i++) (floor-1)[i]=___FIX(-50-i);
  short_ptr=floor+(span-1);
  exact_ptr=floor+span;
  ___ps->mem.alloc_stack_ptr_=short_ptr;
  ___ps->mem.alloc_stack_start_=short_ptr;
  saved_break=context.stack_break;
  memcpy(image,floor-1,(span+2)*sizeof(___WORD));
  REJECT("Continuation copy extent does not fit its destination",
         move_continuation(___PSPNC));
  CHECK(memcmp(floor-1,image,(span+2)*sizeof(___WORD))==0);
  CHECK(context.fp==sfp && context.stack_break==saved_break);
  CHECK(!r->copy_admitted && !r->restored);
  CHECK(___ps->mem.alloc_stack_ptr_==short_ptr);
  context.fp=sfp+___FRAME_ALIGN;
  REJECT("Continuation source extent changed after preflight",
         move_continuation(___PSPNC));
  CHECK(context.fp==sfp+___FRAME_ALIGN);
  CHECK(memcmp(floor-1,image,(span+2)*sizeof(___WORD))==0);
  CHECK(!r->copy_admitted);
  context.fp=sfp;
  r->context=&other;
  REJECT("Continuation restore has the wrong context",
         move_continuation(___PSPNC));
  CHECK(r->context==&other);
  CHECK(context.fp==sfp && context.stack_break==saved_break);
  CHECK(memcmp(floor-1,image,(span+2)*sizeof(___WORD))==0);
  CHECK(!r->copy_admitted);
  r->context=&context;
  r->epoch=2;
  REJECT("Continuation restore has a stale epoch",
         move_continuation(___PSPNC));
  CHECK(r->epoch==2 && ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch==1);
  CHECK(memcmp(floor-1,image,(span+2)*sizeof(___WORD))==0);
  CHECK(!r->copy_admitted && !r->restored);
  r->epoch=1;
  {
    static ___processor_state_struct foreign_owner;
    section_claim *claim=section_claim_at(source,0);
    ___processor_state saved_owner=claim->stack_owner;
    claim->stack_owner=&foreign_owner;
    REJECT("Continuation source stack is owned by another carrier",
           move_continuation(___PSPNC));
    CHECK(memcmp(floor-1,image,(span+2)*sizeof(___WORD))==0);
    CHECK(context.fp==sfp && context.stack_break==saved_break);
    CHECK(!r->copy_admitted && !r->restored);
    claim->stack_owner=saved_owner;
    CHECK(claim->stack_state==STACK_ACTIVE);
    puts("CONTINUATION-FOREIGN-SOURCE-OWNER");
  }
  ___ps->mem.alloc_stack_ptr_=exact_ptr;
  ___ps->mem.alloc_stack_start_=exact_ptr;
  CHECK(move_continuation(___PSPNC));
  CHECK(r->copy_admitted && !r->restored);
  CHECK(___ps->mem.alloc_stack_ptr_==floor);
  CHECK(context.stack_break==floor+active);
  CHECK(context.stack_start==exact_ptr);
  CHECK((floor-1)[0]==image[0]);
  CHECK(floor[span]==image[span+1]);
  slot=active+___FIRST_BREAK_FRAME_STACK_MSECTION;
  for(i=0;i<span;i++) {
    ___WORD want=(i==slot)?0:sfp[i];
    CHECK(floor[i]==want);
  }
  CHECK(sfp[0]==___FIX(100));
  puts("CONTINUATION-EXACT-FIT");
  puts("CONTINUATION-ONE-WORD-SHORT");
  puts("CONTINUATION-CHANGED-EXTENT");
  puts("CONTINUATION-WRONG-CONTEXT");
  puts("CONTINUATION-STALE-EPOCH");

#if ___MAX_PROCESSORS >= 3 && !defined(___SINGLE_THREADED_VMS)
  {
    ___processor_state p0=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
    ___processor_state carrier=___PSTATE_FROM_PROCESSOR_ID(2,&vm);
    ___execution_context independent={0};
    ___msection *nsource=calloc(1,SECTION_BYTES);
    ___msection *ndest=calloc(1,SECTION_BYTES);
    ___gc_resume_space *nr;
    ___WORD *nfp;
    ___WORD poison;
    ___SIZE_TS words, n;
    CHECK(nsource && ndest);
    CHECK(___PROCESSOR_ID(carrier,&vm)==2);
    p0->mem.rc_domain_=&domain;
    domain.round=&round;
    carrier->vmstate=&vm;
    carrier->context=&independent;
    carrier->mem.tospace_offset_=0;
    set_stack_msection(carrier, ndest);
    nfp=nsource->base+16;
    independent.fp=nfp;
    independent.stack_break=nfp+active;
    for(i=0;i<span;i++) nfp[i]=___FIX(100+i);
    ___FP_SET_STK(independent.stack_break,-___FIRST_BREAK_FRAME_STACK_MSECTION,
                 ___FIX(77))
    ___COLLECTION(&vm).worker_count=2;
    ___COLLECTION(&vm).participant_count=3;
    ___COLLECTION(&vm).epoch=1;
    CHECK(admit_span(carrier, nsource, 0, ndest, carrier->mem.alloc_stack_limit_, 1));
    nr=&___RESUME(&vm,2);
    CHECK(nr->source_worker==-1);
    CHECK(nr->source_words==(___SIZE_TS)span);
    nr->loan_base=carrier->mem.alloc_stack_limit_;
    nr->loan_limit=nr->loan_base+restore_loan_words(nr->source_words);
    nr->stack_floor=carrier->mem.alloc_stack_limit_;
    CHECK(___gc_resume_without_arena(nr, 1));
    CHECK(nr->stack_floor==nr->loan_limit);
    CHECK(carrier->mem.alloc_stack_limit_==nr->stack_floor);
    poison=___FIX(99);
    nr->stack_floor[-1]=poison;
    {
      ___processor_state ___ps=carrier;
      CHECK(move_continuation(___PSPNC));
      words=nr->source_words;
      CHECK(nr->copy_admitted && !nr->restored);
      CHECK(nr->stack_floor[-1]==poison);
      CHECK(___ps->mem.alloc_stack_ptr_+words<=___ps->mem.alloc_stack_start_);
      CHECK(___ps->mem.alloc_stack_ptr_>=nr->stack_floor);
      for(n=0;n<words;n++) {
        ___WORD want=(n==(unsigned)slot)?0:nfp[n];
        CHECK(___ps->mem.alloc_stack_ptr_[n]==want);
      }
    }
    free(nsource);
    free(ndest);
    puts("NON-WORKER-R3-W2-PASS");
  }
#else
  puts("NON-WORKER-R3-W2-BLOCKED ___MAX_PROCESSORS<3 or single-threaded profile");
#endif
  free(source);
  free(dest);
  return 0;
}

/* Foreign and malformed census entries must reject before the first frame
 * load. The foreign section is registered in the section map so a
 * find_msection result alone would otherwise admit it. */
static int source_census_controls(void)
{
  static ___virtual_machine_state_struct vm;
  static ___processor_state_struct foreign;
  static ___msections map;
  static ___rc_domain domain;
  static ___root_round round;
  ___processor_state ___ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___execution_context context={0};
  ___root_member member;
  ___gc_resume_space resume;
  ___gc_census census;
  ___collector_worker work;
  ___msection *section=calloc(1,SECTION_BYTES);
  ___WORD *fp;
  int span=8+___FIRST_BREAK_FRAME_SPACE;
  int i;
  CHECK(section);
#ifndef ___SINGLE_THREADED_VMS
  ___ps->vmstate=&vm;
#endif
  memset(&member,0,sizeof member);
  memset(&work,0,sizeof work);
  memset(&census,0,sizeof census);
  memset(&map,0,sizeof map);
  memset(&foreign,0,sizeof foreign);
  map.max_nb_sections=map.nb_sections=1;
  map.head=map.tail=map.sections[0]=section;
  vm.mem.the_msections_=&map;
#ifndef ___SINGLE_THREADED_VMS
  ___SPINLOCK_INIT(vm.mem.alloc_mem_lock_);
#endif
  ___ps->mem.rc_domain_=&domain;
  if(round.slot_storage==0) CHECK(diag_bind_round_storage(&round,___MAX_PROCESSORS));
  domain.round=&round;
  round.collection.destination_offset=___MSECTION_SIZE>>1;
  ___ps->context=&context;
  ___ps->mem.tospace_offset_=0;
  ___ps->mem.stack_msection_=section;
  member.owner=___ps;
  member.context=&context;
  work.census=&census;
  work.carrier=___ps;
  work.vm=&vm;
  fp=section->base+32;
  for(i=0;i<span;i++) fp[i]=___FIX(100+i);
  context.fp=0;
  context.stack_break=0;
  section_claim_at(section,0)->stack_owner=___ps;
  section_claim_at(section,0)->stack_state=STACK_ACTIVE;
  memset(&resume,0,sizeof resume);
  REJECT("Continuation source stack is malformed at census entry",
         census_continuation(&work,&member,&resume,0));
  CHECK(census.failed==1);
  CHECK(resume.source_section==0);
  puts("SOURCE-CENSUS-MALFORMED-NULL");

  context.fp=fp;
  context.stack_break=fp+8;
  section_claim_at(section,0)->stack_state=STACK_UNCLAIMED;
  section_claim_at(section,0)->stack_owner=___ps;
  memset(&resume,0,sizeof resume);
  census.failed=0;
  census.frames=0;
  REJECT("Continuation source stack is malformed at census entry",
         census_continuation(&work,&member,&resume,0));
  CHECK(census.failed==1);
  CHECK(resume.source_section==0);
  CHECK(census.frames==0);
  CHECK(fp[0]==___FIX(100));
  puts("SOURCE-CENSUS-MALFORMED-INACTIVE");

  section_claim_at(section,0)->stack_state=STACK_ACTIVE;
  section_claim_at(section,0)->stack_owner=&foreign;
  memset(&resume,0,sizeof resume);
  census.failed=0;
  census.frames=0;
  REJECT("Continuation source stack is owned by another carrier",
         census_continuation(&work,&member,&resume,0));
  CHECK(census.failed==1);
  CHECK(resume.source_section==0);
  CHECK(census.frames==0);
  CHECK(fp[0]==___FIX(100));
  CHECK(section_claim_at(section,0)->stack_owner==&foreign);
  CHECK(section_claim_at(section,0)->stack_state==STACK_ACTIVE);
  puts("SOURCE-CENSUS-FOREIGN-OWNER");

  /* The admitted logical end is earlier than the physical half's end.
   * Use real inline label descriptors so this exercises the frame walker. */
  {
    ___label_struct exact={0}, crossing={0}, interrupted={0};
    ___frame_descriptor decoded={0};
    ___SCMOBJ exact_ra=___SUBTYPED_FROM_BODY(&exact.entry_or_descr);
    ___SCMOBJ crossing_ra=___SUBTYPED_FROM_BODY(&crossing.entry_or_descr);
    ___SCMOBJ prior_internal=___GSTATE->internal_return;
    ___SCMOBJ queue[1];
    ___WORD still[___STILL_BODY+1]={0};
    ___WORD *past=fp+___FRAME_SPACE(1);
    ___WORD *crossing_base=fp+___FRAME_SPACE(5);
    int rejected_before_decode;

    exact.header=___MAKE_HD(0,___sRETURN,___PERM);
    crossing.header=___MAKE_HD(0,___sRETURN,___PERM);
    interrupted.header=___MAKE_HD(0,___sRETURN,___PERM);
    exact.entry_or_descr=___IFD(___RETN,1,0,0x1L);
    crossing.entry_or_descr=___IFD(___RETN,5,0,0x3L);
    interrupted.entry_or_descr=___IFD(___RETI,1,4,0x3f1L);
    section_claim_at(section,0)->stack_owner=___ps;
    context.stack_break=past;
    ___FP_STK(past,-___BREAK_FRAME_NEXT)=___END_OF_CONT_MARKER;
    ___FP_STK(fp,-___FRAME_STACK_RA)=exact_ra;
    ___FP_STK(past,1)=exact_ra;
    census.failed=0;
    census_continuation(&work,&member,&resume,0);
    CHECK(!census.failed && resume.source_break==past);
    puts("SOURCE-CENSUS-EXACT-BREAK");

    CHECK(crossing_base>past && crossing_base<section->base+(___MSECTION_SIZE>>1));
    ___FP_STK(fp,-___FRAME_STACK_RA)=crossing_ra;
    ___FP_STK(crossing_base,1)=exact_ra;
    /* A premature root scan would mark and enqueue this otherwise valid
     * object. Its root slot lies beyond the logical break. */
    still[___STILL_HEADER]=___MAKE_HD(___WS,___sVECTOR,___STILL);
    still[___STILL_BODY]=___FAL;
    ___FP_STK(crossing_base,2)=___SUBTYPED_FROM_BODY(still+___STILL_BODY);
    census.queue=queue;
    census.capacity=1;
    census.failed=0;
    census_continuation(&work,&member,&resume,0);
    CHECK(census.failed && !resume.copy_admitted);
    CHECK(still[___STILL_MARK]==0 && census.count==0);
    CHECK(___FP_STK(crossing_base,1)==exact_ra);
    puts("SOURCE-CENSUS-LOGICAL-BREAK-SKIP");
    REJECT("GC active frame is outside its source stack grant",
           mark_continuation(&work,&context));
    CHECK(still[___STILL_MARK]==0 && ___FP_STK(crossing_base,1)==exact_ra);
    CHECK(round.collection.frame_gate==0);
    puts("SOURCE-COPY-ACTIVE-BREAK-SKIP");
    context.fp=context.stack_break=section->base+(___MSECTION_SIZE>>1)-1;
    REJECT("GC active break link is outside its source stack grant",
           mark_continuation(&work,&context));
    CHECK(round.collection.frame_gate==0);
    context.fp=fp;
    context.stack_break=past;
    puts("SOURCE-COPY-EMPTY-ACTIVE-BREAK-REFUSED");
    section_claim_at(section,0)->stack_owner=&foreign;
    REJECT("GC active break link is outside its source stack grant",
           mark_continuation(&work,&context));
    CHECK(section_claim_at(section,0)->stack_owner==&foreign);
    CHECK(round.collection.frame_gate==0);
    section_claim_at(section,0)->stack_owner=___ps;
    puts("SOURCE-COPY-ACTIVE-FOREIGN-OWNER-REFUSED");

    /* A saved internal-return label at the logical end or beyond must
     * not be loaded even though its slot is in the same physical half. */
    CHECK(fp-___RETI_RA>=past);
    ___GSTATE->internal_return=___FIX(111);
    ___FP_STK(fp,-___FRAME_STACK_RA)=___GSTATE->internal_return;
    ___FP_STK(fp,___RETI_RA)=___SUBTYPED_FROM_BODY(&interrupted.entry_or_descr);
    census.failed=0;
    rejected_before_decode=
      !census_frame_descriptor(&work,fp,___GSTATE->internal_return,1,past,&decoded,0)
      && census.failed && decoded.fs==0;
    census.failed=0;
    census_continuation(&work,&member,&resume,0);
    ___GSTATE->internal_return=prior_internal;
    CHECK(rejected_before_decode && census.failed && !resume.copy_admitted);
    CHECK(section_claim_at(section,0)->stack_owner==___ps);
    CHECK(section_claim_at(section,0)->stack_state==STACK_ACTIVE);
    CHECK(___ps->mem.tospace_offset_==0);
    puts("SOURCE-CENSUS-RETI-OUTSIDE-BREAK");

  }

  /* A raw captured coordinate is admitted from its own claim, not from the
   * scanner's carrier or stack_break. Logical end is not known: the short
   * overflow records only NEXT, the undo marker can be cleared, and a suffix
   * can sit above a later nested break. stack_floor is only a floor. */
  {
    ___label_struct parked_label={0}, handler_label={0};
    ___SCMOBJ parked_ra=___SUBTYPED_FROM_BODY(&parked_label.entry_or_descr);
    ___WORD handler=___SUBTYPED_FROM_BODY(&handler_label.entry_or_descr);
    ___WORD prior_handler=___GSTATE->handler_break;
    ___WORD *saved_break=context.stack_break;
    ___WORD *raw=fp+24;
    ___WORD *parked_top=fp+40;
    ___WORD *parked_base;
    ___WORD *half_end=section->base+(___MSECTION_SIZE>>1);
    ___WORD *edge=half_end-___FRAME_SPACE(1);
    ___WORD poison=___FIX(91);
    ___WORD cell;
    ___WORD *floor=section->base;
    ___SCMOBJ cap_queue[1];
    parked_label.header=___MAKE_HD(0,___sRETURN,___PERM);
    handler_label.header=___MAKE_HD(0,___sRETURN,___PERM);
    parked_label.entry_or_descr=___IFD(___RETN,1,0,0);
    handler_label.entry_or_descr=___IFD(___RETN,1,0,0);
    census.queue=cap_queue;
    census.capacity=1;
    census.count=0;
    census.frames=0;
    census.failed=0;
    cell=___FIX(0);
    census_capture(&work,&cell);
    CHECK(census.failed && census.frames==0 && cell==___FIX(0));
    puts("SOURCE-CENSUS-CAPTURE-UNMAPPED");
    REJECT("GC captured frame is outside its source stack grant",
           mark_captured_continuation_locked(&work,&cell));
    CHECK(cell==___FIX(0) && !work.copy_request.state);
    puts("SOURCE-COPY-CAPTURE-UNMAPPED");

    ___GSTATE->handler_break=handler;
    ___FP_STK(edge,-___FRAME_STACK_RA)=parked_ra;
    ___FP_STK(half_end,1)=handler;
    cell=___CAST(___WORD,edge);
    section_claim_at(section,0)->stack_state=STACK_PARKED;
    census.failed=0;
    census_capture(&work,&cell);
    CHECK(census.failed && census.frames==0 && cell==___CAST(___WORD,edge));
    puts("SOURCE-CENSUS-CAPTURE-BREAK-OUTSIDE-HALF");
    REJECT("GC captured break link is outside its source stack grant",
           mark_captured_continuation_locked(&work,&cell));
    CHECK(cell==___CAST(___WORD,edge) && !work.copy_request.state);
    CHECK(___FP_STK(half_end,1)==handler);
    puts("SOURCE-COPY-CAPTURE-BREAK-OUTSIDE-HALF");
    {
      ___WORD *reti_top=half_end-1;
      ___SCMOBJ prior_internal=___GSTATE->internal_return;
      ___GSTATE->internal_return=___FIX(111);
      ___FP_STK(reti_top,-___FRAME_STACK_RA)=___GSTATE->internal_return;
      cell=___CAST(___WORD,reti_top);
      REJECT("GC captured frame is outside its source stack grant",
             mark_captured_continuation_locked(&work,&cell));
      ___GSTATE->internal_return=prior_internal;
      CHECK(cell==___CAST(___WORD,reti_top) && !work.copy_request.state);
      puts("SOURCE-COPY-CAPTURE-RETI-OUTSIDE-HALF");
    }

    census.failed=0;
    section_claim_at(section,0)->stack_owner=___ps;
    section_claim_at(section,0)->stack_state=STACK_REUSABLE;
    section_claim_at(section,0)->stack_floor=floor;
    ___FP_STK(raw,-___FRAME_STACK_RA)=poison;
    cell=___CAST(___WORD,raw);
    context.stack_break=(___WORD*)1;
    census_capture(&work,&cell);
    context.stack_break=saved_break;
    CHECK(census.failed && census.frames==0 && census.count==0);
    CHECK(___FP_STK(raw,-___FRAME_STACK_RA)==poison);
    CHECK(___ps->mem.tospace_offset_==0);
    puts("SOURCE-CENSUS-CAPTURE-RAW-REJECTED");
    REJECT("GC captured frame is outside its source stack grant",
           mark_captured_continuation_locked(&work,&cell));
    CHECK(___FP_STK(raw,-___FRAME_STACK_RA)==poison && !work.copy_request.state);
    puts("SOURCE-COPY-CAPTURE-REUSABLE-REFUSED");

    parked_base=parked_top+___FRAME_SPACE(1);
    ___GSTATE->handler_break=handler;
    ___FP_STK(parked_top,-___FRAME_STACK_RA)=parked_ra;
    ___FP_STK(parked_base,1)=handler;
    ___FP_STK(parked_base,-___BREAK_FRAME_NEXT)=___END_OF_CONT_MARKER;
    section_claim_at(section,0)->stack_owner=&foreign;
    section_claim_at(section,0)->stack_state=STACK_PARKED;
    section_claim_at(section,0)->stack_floor=floor;
    cell=___CAST(___WORD,parked_top);
    census.failed=0;
    census.frames=0;
    census.count=0;
    context.stack_break=(___WORD*)1;
    census_capture(&work,&cell);
    context.stack_break=saved_break;
    ___GSTATE->handler_break=prior_handler;
    CHECK(!census.failed && census.frames==1 && census.count==0);
    CHECK(section_claim_at(section,0)->stack_owner==&foreign);
    CHECK(section_claim_at(section,0)->stack_state==STACK_PARKED);
    CHECK(section_claim_at(section,0)->stack_floor==floor);
    CHECK(context.fp==fp && ___ps->mem.tospace_offset_==0);
    CHECK(___FP_STK(parked_base,-___BREAK_FRAME_NEXT)==___END_OF_CONT_MARKER);
    puts("SOURCE-CENSUS-CAPTURE-PARKED");
    {
      ___WORD *body=half_end+32;
      ___WORD forwarded=___TAG(body-___REFERENCE_TO_BODY,___tFIXNUM);
      body[-1]=___MAKE_HD_WORDS(1+___FRAME_EXTRA_SLOTS,___sFRAME);
      ___FP_STK(parked_base,1)=forwarded;
      cell=___CAST(___WORD,parked_top);
      mark_captured_continuation_locked(&work,&cell);
      CHECK(cell==___TAG(___UNTAG_AS(forwarded,___tFIXNUM),___tSUBTYPED));
      CHECK(___FP_STK(parked_base,1)==forwarded && work.frame_links_==1);
      CHECK(!work.copy_request.state);
      puts("SOURCE-COPY-CAPTURE-FORWARDED");
    }
    {
      ___label_struct crossing={0};
      ___WORD crossing_ra=___SUBTYPED_FROM_BODY(&crossing.entry_or_descr);
      ___WORD *older=parked_base+___BREAK_FRAME_SPACE+8;
      ___WORD *older_base=older+___FRAME_SPACE(1);
      crossing.header=___MAKE_HD(0,___sRETURN,___PERM);
      crossing.entry_or_descr=___IFD(___RETN,5,0,0);
      section_claim_at(section,0)->stack_owner=___ps;
      section_claim_at(section,0)->stack_state=STACK_ACTIVE;
      park_stack_section(___ps,section,floor,parked_top,parked_base);
      ___GSTATE->handler_break=handler;
      ___FP_STK(parked_top,-___FRAME_STACK_RA)=crossing_ra;
      cell=___CAST(___WORD,parked_top);
      census.failed=0;
      census_capture(&work,&cell);
      CHECK(census.failed);
      REJECT("GC captured frame is outside its source stack grant",
             mark_captured_continuation_locked(&work,&cell));
      CHECK(cell==___CAST(___WORD,parked_top) && !work.copy_request.state);
      puts("PARKED-LOGICAL-BREAK-SKIP-REFUSED");

      ___FP_STK(parked_top,-___FRAME_STACK_RA)=parked_ra;
      ___FP_STK(parked_base,1)=parked_ra;
      census.failed=0;
      census_capture(&work,&cell);
      CHECK(census.failed);
      REJECT("GC captured successor disagrees with its parked break",
             mark_captured_continuation_locked(&work,&cell));
      CHECK(___FP_STK(parked_base,1)==parked_ra && !work.copy_request.state);
      puts("PARKED-BREAK-SUCCESSOR-REFUSED");

      memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
      ___FP_STK(parked_base,1)=handler;
      ___FP_STK(parked_base,-___BREAK_FRAME_NEXT)=___CAST(___WORD,older);
      ___FP_STK(older,-___FRAME_STACK_RA)=parked_ra;
      ___FP_STK(older_base,1)=handler;
      ___FP_STK(older_base,-___BREAK_FRAME_NEXT)=___END_OF_CONT_MARKER;
      census.frames=0;
      census.failed=0;
      census_capture(&work,&cell);
      CHECK(!census.failed && census.frames==2);
      CHECK(section_claim_at(section,0)->parked_break==parked_base);
      {
        ___WORD destination[32];
        ___WORD *const dest=destination+16;
        ___WORD *cursor=dest;
        ___WORD internal=___GSTATE->internal_return;
        for (i=0;i<32;i++) destination[i]=poison;
        section_claim_at(section,0)->stack_owner=&foreign;
        ___FP_STK(parked_top,-___FRAME_STACK_RA)=crossing_ra;
        REJECT("Break restore source frame is outside its stack grant",
               ___restore_stack_break_frame(___ps,parked_top,&cursor));
        CHECK(cursor==dest && section->copy_gate==0);
        for (i=0;i<32;i++) CHECK(destination[i]==poison);
        puts("BREAK-RESTORE-PARKED-OVERRUN-REFUSED");
        ___GSTATE->internal_return=___FIX(112);
        ___FP_STK(parked_top,-___FRAME_STACK_RA)=___GSTATE->internal_return;
        CHECK(parked_top-___RETI_RA>=parked_base);
        REJECT("Break restore source frame is outside its stack grant",
               ___restore_stack_break_frame(___ps,parked_top,&cursor));
        ___GSTATE->internal_return=internal;
        CHECK(cursor==dest && section->copy_gate==0);
        for (i=0;i<32;i++) CHECK(destination[i]==poison);
        puts("BREAK-RESTORE-RETI-OUTSIDE-PARKED-REFUSED");
        ___FP_STK(parked_top,-___FRAME_STACK_RA)=parked_ra;
        CHECK(___restore_stack_break_frame(___ps,parked_top,&cursor)==parked_ra);
        CHECK(cursor==dest-___FRAME_SPACE(1) && section->copy_gate==0);
        CHECK(___FP_STK(dest,1)==handler);
        CHECK(___FP_STK(dest,-___BREAK_FRAME_NEXT)==___CAST(___WORD,older));
        puts("BREAK-RESTORE-FOREIGN-PARKED-EXACT-PASS");
        cursor=dest;
        CHECK(___restore_stack_break_frame(___ps,older,&cursor)==parked_ra);
        CHECK(cursor==dest-___FRAME_SPACE(1) && section->copy_gate==0);
        CHECK(___FP_STK(dest,-___BREAK_FRAME_NEXT)==___END_OF_CONT_MARKER);
        puts("BREAK-RESTORE-OLDER-PHYSICAL-PASS");
      }
      ___GSTATE->handler_break=prior_handler;
      puts("PARKED-KNOWN-BREAK-OLDER-SUFFIX-PASS");
    }
  }
  free(section);
  return 0;
}

int main(int argc,char **argv)
{
  static ___virtual_machine_state_struct vm;
  static ___rc_domain domain;
  static ___root_round round;
  static ___collector_worker selected,decoy;
  static ___msections map;
  ___processor_state ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___msection *section=calloc(1,___sizeof_msection(___MSECTION_SIZE));
  ___SCMOBJ obj;
  char needle[128];
#if defined(SECTION_BYTES) && defined(___GC_TEST_BEFORE_FINAL_RESTORE_READ)
  if(argc==2 && (strcmp(argv[1],"--delayed-reader")==0 ||
                 strcmp(argv[1],"--early-retire")==0)) {
    free(section);
    return delayed_restore_reader(strcmp(argv[1],"--early-retire")==0,0);
  }
  if(argc==2 && strcmp(argv[1],"--drained-source-retirement")==0) {
    free(section);
    return delayed_restore_reader(2,0);
  }
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  if(argc==2 && strcmp(argv[1],"--production-restore-edge")==0) {
    const char *mode=getenv("GAMBIT_DEV_RESTORE_COLLECTIVE");
    CHECK(mode && (strcmp(mode,"positive")==0 || strcmp(mode,"negative")==0));
    free(section);
    return delayed_restore_reader(0,1);
  }
#ifdef ___GAMBIT_DEV_RESTORE_GENERATED_CONTROL
  if(argc==2 && strcmp(argv[1],"--generated-restore-closure")==0) {
    const char *mode=getenv("GAMBIT_DEV_RESTORE_COLLECTIVE");
    CHECK(mode && (strcmp(mode,"positive")==0 || strcmp(mode,"closure-negative")==0));
    free(section);
    return strcmp(mode,"positive")==0 ? delayed_restore_reader(0,2)
                                      : generated_closure_refusal(2);
  }
  if(argc==2 && strcmp(argv[1],"--generated-restore-stale")==0) {
    const char *mode=getenv("GAMBIT_DEV_RESTORE_COLLECTIVE");
    CHECK(mode && strcmp(mode,"positive")==0);
    free(section);
    return generated_closure_refusal(3);
  }
  if(argc==2 && (strcmp(argv[1],"--generated-restore-section-drift")==0 ||
                 strcmp(argv[1],"--generated-restore-parity-drift")==0)) {
    const char *mode=getenv("GAMBIT_DEV_RESTORE_COLLECTIVE");
    CHECK(mode && strcmp(mode,"positive")==0);
    free(section);
    return generated_closure_refusal(strcmp(argv[1],"--generated-restore-section-drift")==0 ? 4 : 5);
  }
#endif
#endif
#endif
  if(argc==2 && strcmp(argv[1],"--stack-section")==0) {
    free(section);
    return stack_section_ownership();
  }
  CHECK(section!=0);
  map.max_nb_sections=map.nb_sections=1;
  map.head=map.tail=map.sections[0]=section;
  vm.mem.the_msections_=&map;
#ifndef ___SINGLE_VM
  ps->vmstate=&vm;
#endif
  ps->mem.rc_domain_=&domain;
  if(round.slot_storage==0) CHECK(diag_bind_round_storage(&round,___MAX_PROCESSORS));
  domain.round=&round;
  selected.vm=&vm;selected.carrier=ps;selected.id=7;
  selected.reference_location_=IN_RC;selected.mark_array_call_line_=123;
  selected.scan_ptr_=section->base+7;
  selected.arena.cursor=section->base+9;selected.arena.limit=section->base+20;
  decoy.vm=&vm;decoy.carrier=ps;decoy.id=99;
  decoy.reference_location_=IN_REGISTER;decoy.mark_array_call_line_=999;
  decoy.scan_ptr_=section->base+3;
  ps->collector=&decoy; /* May not override the actual scanning worker. */
  ps->mem.tospace_offset_=0; /* Deliberately stale carrier projection. */
  round.collection.destination_offset=___MSECTION_SIZE>>1;
  section->base[0]=___MAKE_HD_WORDS(1,___sVECTOR);
  section->base[1]=___FIX(0);
  obj=___TAG(section->base+1,___tSUBTYPED);
  validate_old_obj(&selected,obj); /* Round says source, carrier says tospace. */
  dump_memory_map(&selected);
  snprintf(needle,sizeof(needle),"scan_ptr             = %p",selected.scan_ptr_);
  CHECK(strstr(report,needle)!=0);
  CHECK(strstr(report,"Memory map for worker 7")!=0);
  CHECK(strstr(report,"worker_arena_cursor")!=0);
  CHECK(selected.scan_ptr_==section->base+7 && ps->collector==&decoy);
  CHECK(restoration_overflow_ownership(ps)==0);
  if(argc==2 && strcmp(argv[1],"--invalid")==0) {
    ___WORD *dest=section->base+round.collection.destination_offset;
    dest[0]=___MAKE_HD_WORDS(1,___sVECTOR);dest[1]=___FIX(0);
    expect_fatal=1;
    validate_old_obj(&selected,___TAG(dest+1,___tSUBTYPED));
    CHECK(0); /* The real diagnostic must reach its controlled fatal sink. */
  }
  free(section);
  CHECK(stack_section_ownership()==0);
  CHECK(heap_cursor_controls()==0);
  CHECK(continuation_extent_controls()==0);
  CHECK(source_census_controls()==0);
  puts("COLLECTOR-DIAGNOSTICS-PASS worker carrier-decoy round-offset arena");
  return 0;
}
