/* Included once by mem.c; also compiled verbatim by the transport regression.
 * Lifecycle calls occur outside runtime locks and after worker quiescence.
 * A crash leaves a committed prefix in the supervisor-owned shared mapping. */
#ifdef ___GAMBIT_REST_OBSERVATION
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if !defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "rest observation wire format requires little-endian uint64_t"
#endif
_Static_assert(sizeof(uintptr_t)==8, "rest observation requires 64-bit pointers");
_Static_assert(__atomic_always_lock_free(8,0), "observation atomics must be lock free");

static uint64_t *rest_observation_map;
static uint64_t rest_observation_case_id;
static int rest_observation_auto_watch; /* 1 one word short, 2 exact fit */
static int rest_observation_auto_watch_claimed;
static _Thread_local unsigned rest_observation_handler_form;
static _Thread_local uint64_t rest_observation_gc_domain;
static _Thread_local uint64_t rest_observation_gc_vm;
static _Thread_local uint64_t rest_observation_gc_rc_epoch;
static _Thread_local uintptr_t rest_observation_chain_record;
static _Thread_local uint64_t rest_observation_chain_attempt;
static _Thread_local uint64_t rest_observation_protocol_attempt;
static _Thread_local uint64_t rest_observation_form;
static _Thread_local void *rest_observation_restored_fp;
static _Thread_local int rest_observation_reloaded;
static _Thread_local uint64_t rest_observation_ready_result;
static _Thread_local uint64_t rest_observation_ready_label;

static void rest_observation_chain_bind(const void *record, uint64_t attempt)
{
  rest_observation_chain_record=(uintptr_t)record;
  rest_observation_chain_attempt=attempt;
  if (!attempt) rest_observation_protocol_attempt=0;
  if (!attempt) rest_observation_form=0;
  if (!attempt) rest_observation_reloaded=0;
}
static _Thread_local uint64_t rest_observation_argument_words;
static _Thread_local uint64_t rest_observation_watch_case;
static _Thread_local unsigned rest_observation_watch_state;
static _Thread_local uintptr_t rest_observation_bases[3];
static _Thread_local uint64_t rest_observation_lengths[3];
static _Thread_local uint64_t rest_observation_delivery[4];
static _Thread_local uint64_t rest_observation_delivery_case;
static _Thread_local uintptr_t rest_observation_scan_base;
static _Thread_local uint64_t rest_observation_scan_words;
/* Workers copy roots on other threads. The mutator publishes the one
 * activation root span; tail cells outside it stay unrecorded. */
static uintptr_t rest_observation_root_base;
static uint64_t rest_observation_root_words;


static inline uintptr_t rest_observation_attempt_record(const void *actor)
{ (void)actor; return rest_observation_chain_record; }
static inline uint64_t rest_observation_attempt_id(const void *actor)
{ (void)actor; return rest_observation_protocol_attempt; }
static uint64_t rest_observation_current_case(void)
{
  return __atomic_load_n(&rest_observation_case_id,__ATOMIC_ACQUIRE);
}
/* One case is shared by every processor. A refusing carrier must not close
 * it while another carrier is still recording the same attempt. */
static int rest_observation_case_holders;
static _Thread_local int rest_observation_case_held;
/* A two-carrier section contest keeps the case until both have locked.
 * One carrier's body must not close it while the other is still arriving. */
static int rest_observation_case_hold;
static void rest_observation_set_case_hold(int hold)
{
  rest_observation_case_hold=hold ? 1 : 0;
}
static void rest_observation_case_enter(void)
{
  if (!rest_observation_current_case() || rest_observation_case_held) return;
  rest_observation_case_held=1;
  __atomic_fetch_add(&rest_observation_case_holders,1,__ATOMIC_ACQ_REL);
}
static void rest_observation_case_leave(void)
{
  int remaining;
  if (!rest_observation_case_held) return;
  rest_observation_case_held=0;
  remaining=__atomic_fetch_sub(&rest_observation_case_holders,1,__ATOMIC_ACQ_REL);
  if (remaining==1 && !rest_observation_case_hold && rest_observation_current_case() &&
      rest_observation_delivery_case!=rest_observation_current_case())
    ___rest_observation_case_end();
}

void ___rest_observation_delivered(void *actor, void *record, uint64_t attempt, uint64_t epoch)
{
  rest_observation_delivery[0]=(uintptr_t)actor;
  rest_observation_delivery[1]=(uintptr_t)record;
  rest_observation_delivery[2]=attempt; rest_observation_delivery[3]=epoch;
  rest_observation_delivery_case=__atomic_load_n(&rest_observation_case_id,__ATOMIC_ACQUIRE);
  REST_OBS(REST_DELIVER,actor,record,attempt,epoch,rest_observation_ready_result,0,0,0,0,0,0,0);
}

int ___rest_observation_body(void *actor)
{
  if (!rest_observation_map || !rest_observation_current_case() ||
      __atomic_load_n(rest_observation_map+5,__ATOMIC_ACQUIRE) ||
      rest_observation_delivery_case!=rest_observation_current_case() ||
      rest_observation_delivery[0]!=(uintptr_t)actor || !rest_observation_delivery[1]) return 0;
  ___rest_observation_emit(REST_BODY,rest_observation_delivery[0],rest_observation_delivery[1],
    rest_observation_delivery[2],rest_observation_delivery[3],0,0,0,0,0,0,0,0);
  return 1;
}

int ___rest_observation_watch(uint64_t argument_words)
{
  uint64_t id=rest_observation_current_case();
  if (rest_observation_watch_case!=id) rest_observation_watch_state=0;
  if (!rest_observation_map || !id || argument_words>1000000 ||
      __atomic_load_n(rest_observation_map+5,__ATOMIC_ACQUIRE) ||
      rest_observation_watch_state) return 0;
  rest_observation_watch_case=id;
  rest_observation_argument_words=argument_words;
  rest_observation_watch_state=1;
  return 1;
}

int ___rest_observation_open(const char *path)
{
  int fd;
  struct stat st;
  uint64_t *map;
  if (rest_observation_map) return 1;
  if (!path) path=getenv("GAMBIT_REST_OBSERVATION");
  if (!path || !*path) return 0;
  fd=open(path,O_RDWR|O_NOFOLLOW);
  if (fd<0) return 0;
  if (fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_size<64) {
    close(fd); return 0;
  }
  map=mmap(0,(size_t)st.st_size,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
  close(fd);
  if (map==MAP_FAILED) return 0;
  if (map[0]!=UINT64_C(0x3130545345523646) || map[1]!=1 || map[2]<1 ||
      map[2]>1000000 || (uint64_t)st.st_size!=64+128*map[2] ||
      map[3] || map[4] || map[5] || map[6]!=16 || map[7]) {
    munmap(map,(size_t)st.st_size); return 0;
  }
  rest_observation_map=map;
  {
    const char *watch=getenv("GAMBIT_REST_OBSERVATION_WATCH");
    rest_observation_auto_watch=0;
    if (watch && !strcmp(watch,"physical-one-short")) rest_observation_auto_watch=1;
    else if (watch && !strcmp(watch,"physical-exact")) rest_observation_auto_watch=2;
  }
  return 1;
}

void ___rest_observation_emit(uint64_t kind, uint64_t actor, uint64_t record,
  uint64_t attempt, uint64_t epoch, uint64_t a, uint64_t b, uint64_t c,
  uint64_t d, uint64_t e, uint64_t f, uint64_t g, uint64_t h)
{
  uint64_t *map=rest_observation_map, *out, n, id;
  if (!map || __atomic_load_n(map+5,__ATOMIC_ACQUIRE)) return;
  id=__atomic_load_n(&rest_observation_case_id,__ATOMIC_ACQUIRE);
  if (!id) return;
  n=__atomic_load_n(map+3,__ATOMIC_RELAXED);
  do {
    if (n>=map[2]) {
      uint64_t lost=__atomic_load_n(map+4,__ATOMIC_RELAXED);
      while (lost!=UINT64_MAX && !__atomic_compare_exchange_n(map+4,&lost,lost+1,0,
              __ATOMIC_RELAXED,__ATOMIC_RELAXED)) {}
      return;
    }
  } while (!__atomic_compare_exchange_n(map+3,&n,n+1,0,__ATOMIC_RELAXED,__ATOMIC_RELAXED));
  out=map+8+16*n;
  out[1]=kind; out[2]=id; out[3]=actor; out[4]=record;
  out[5]=attempt; out[6]=epoch;
  out[7]=a; out[8]=b; out[9]=c; out[10]=d;
  out[11]=e; out[12]=f; out[13]=g; out[14]=h; out[15]=0;
  __atomic_store_n(out,n+1,__ATOMIC_RELEASE);
}

int ___rest_observation_case(uint64_t id)
{
  uint64_t expected=0;
  if (!rest_observation_map || !id ||
      __atomic_load_n(rest_observation_map+5,__ATOMIC_ACQUIRE)) return 0;
  if (__atomic_load_n(&rest_observation_case_id,__ATOMIC_ACQUIRE)==id) return 1;
  if (!__atomic_compare_exchange_n(&rest_observation_case_id,&expected,id,0,
                                  __ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE)) return 0;
  ___rest_observation_emit(REST_CASE_BEGIN,0,0,0,0,0,0,0,0,0,0,0,0);
  return 1;
}

int ___rest_observation_case_end(void)
{
  if (!rest_observation_map || !rest_observation_current_case()) return 0;
  ___rest_observation_emit(REST_CASE_END,0,0,0,0,0,0,0,0,0,0,0,0);
  __atomic_store_n(&rest_observation_case_id,0,__ATOMIC_RELEASE);
  rest_observation_watch_state=0;
  memset(rest_observation_delivery,0,sizeof(rest_observation_delivery));
  return 1;
}

int ___rest_observation_close(void)
{
  uint64_t *map=rest_observation_map;
  if (!map || rest_observation_current_case()) return 0;
  /* Keep the mapping alive until process exit. A late observer must never
   * dereference unmapped storage, even when a fixture violates quiescence. */
  return __atomic_exchange_n(map+5,1,__ATOMIC_ACQ_REL)==0;
}

static void rest_observation_finish(void)
{
  if (!rest_observation_map) return;
  if (rest_observation_current_case()) ___rest_observation_case_end();
  ___rest_observation_close();
}

void ___rest_observation_snapshot(uint64_t actor, uint64_t region, uint64_t phase,
                                const void *base, uint64_t words)
{
  uint64_t i, value;
  if (!rest_observation_map || !base || words>1000000) return;
  /* Copy as bytes: unwritten allocated words need not hold a C value. */
  for (i=0;i<words;i++) {
    memcpy(&value,(const unsigned char*)base+8*i,8);
    ___rest_observation_emit(REST_SNAPSHOT,actor,0,0,0,region,phase,
      (uintptr_t)base+8*i,value,(uintptr_t)base,words,0,0);
  }
}

void ___rest_observation_store(void *actor, void *fp, void *address)
{
  REST_OBS(REST_STORE,actor,0,0,0,fp,address,0,0,0,0,0,0);
}

void ___rest_observation_adjust(void *actor, void *fp, intptr_t words)
{
  REST_OBS(REST_FP_ADJUST,actor,0,0,0,fp,
           (uintptr_t)fp-(uintptr_t)words*8,words,0,0,0,0,0);
}

void ___rest_observation_pop(void *actor, void *fp)
{
  REST_OBS(REST_POP,actor,0,0,0,fp,0,0,0,0,0,0,0);
}

static int rest_observation_in_span(uintptr_t address, uintptr_t base, uint64_t words)
{
  return base && address>=base && !((address-base)%8) && (address-base)/8<words;
}

void ___rest_observation_watch_roots(void *base, uint64_t words)
{
  __atomic_store_n(&rest_observation_root_words, words, __ATOMIC_RELAXED);
  __atomic_store_n(&rest_observation_root_base, (uintptr_t)base, __ATOMIC_RELEASE);
}

void ___rest_observation_clear_roots(void)
{
  __atomic_store_n(&rest_observation_root_base, 0, __ATOMIC_RELEASE);
}

void ___rest_observation_repair(void *actor, void *cell, uint64_t old_value,
                               uint64_t new_value, uint64_t round)
{
  uintptr_t address=(uintptr_t)cell;
  uintptr_t shared=__atomic_load_n(&rest_observation_root_base, __ATOMIC_ACQUIRE);
  uint64_t shared_words=__atomic_load_n(&rest_observation_root_words, __ATOMIC_RELAXED);
  /* RC root cells and their header label only. Tail marking may visit other
   * heap cells; those writes are not evidence of a root-window repair. */
  if (!rest_observation_in_span(address, rest_observation_scan_base,
                                rest_observation_scan_words) &&
      !rest_observation_in_span(address, shared, shared_words)) return;
  REST_OBS(REST_ROOT_REPAIRED,actor,0,0,round,cell,old_value,new_value,
           rest_observation_gc_domain,rest_observation_gc_vm,
           rest_observation_gc_rc_epoch,0,0);
}

void ___rest_observation_note_gc(uint64_t vm, uint64_t domain, uint64_t rc_epoch)
{
  rest_observation_gc_vm=vm;
  rest_observation_gc_domain=domain;
  rest_observation_gc_rc_epoch=rc_epoch;
}

static int rest_observation_join_need;
static int rest_observation_join_seen;

/* Both handlers emit their requests before either takes the allocation lock.
 * The count is the number of handlers the probe has already committed to the
 * same contest. A zero count leaves the lock path unchanged. */
void ___rest_observation_arm_extend_join(int need)
{
  if (need<2) need=0;
  __atomic_store_n(&rest_observation_join_seen,0,__ATOMIC_RELAXED);
  __atomic_store_n(&rest_observation_join_need,need,__ATOMIC_RELEASE);
}

void ___rest_observation_extend_join(void)
{
  int need=__atomic_load_n(&rest_observation_join_need,__ATOMIC_ACQUIRE);
  struct timespec start, now;
  if (need<2) return;
  __atomic_add_fetch(&rest_observation_join_seen,1,__ATOMIC_ACQ_REL);
  if (clock_gettime(CLOCK_MONOTONIC,&start)!=0) return;
  while (__atomic_load_n(&rest_observation_join_seen,__ATOMIC_ACQUIRE)<need) {
    if (clock_gettime(CLOCK_MONOTONIC,&now)!=0) return;
    if (now.tv_sec-start.tv_sec>=2) return;
  }
}

/* Remaining admissions to install as the process heap cap at the next
 * locked check. Zero leaves the configured max heap unchanged. The
 * collector has already applied its recovery floor before this runs. */
int ___rest_observation_admission_sections;

void ___rest_observation_arm_admission_sections(int remaining)
{
  if (remaining<1) remaining=0;
  __atomic_store_n(&___rest_observation_admission_sections,remaining,__ATOMIC_RELEASE);
}
#endif
