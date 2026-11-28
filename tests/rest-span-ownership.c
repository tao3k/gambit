/* Production rest-span ownership. This TU includes the RC writer and the
 * lifecycle prepare/abort used by the runtime. It does not enter handler 7
 * or handler 9, does not collect, and does not change ___REST_PARAM_RESERVE.
 * Exit 0 is the span contract below. It is not a P1 admission. */
#define HAVE_CONFIG_H
#define ___VERSION 409008
#include "gambit.h"
#include "mem.h"
#include "rc.h"
#include "lifecycle.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(___REST_PARAM_RESERVE == 9220, "P0 short reserve stays 9220");
_Static_assert(___MSECTION_FUDGE == ___REST_PARAM_RESERVE, "fudge still follows the short reserve");

static int block_alloc;
static int allocs;
static int refused_allocs;
static int fatal_hits;
static int interrupt_hits;
static void *test_tls;

#ifdef ___THREAD_LOCAL_STORAGE_CLASS
___THREAD_LOCAL_STORAGE_CLASS void *___tls_ptr;
#endif

void *___alloc_mem ___P((___SIZE_T bytes),(bytes) ___SIZE_T bytes;)
{
  if (block_alloc) { ++refused_allocs; return 0; }
  ++allocs;
  return calloc(1, bytes ? bytes : 1);
}

void ___free_mem ___P((void *ptr),(ptr) void *ptr;)
{ free(ptr); }

void ___fatal_error ___P((char **msgs),())
{
  ++fatal_hits;
  if (msgs && msgs[0]) fprintf(stderr, "rest-span fatal: %s\n", msgs[0]);
}

void ___raise_interrupt_vmstate(___virtual_machine_state vm, int code)
{ (void)vm; (void)code; ++interrupt_hits; }

___SCMOBJ ___thread_init_from_self ___P((___thread *thread),(thread) ___thread *thread;)
{
#ifdef ___USE_POSIX_THREAD_SYSTEM
  thread->thread_id = pthread_self();
#endif
  return ___FIX(___NO_ERR);
}

void ___still_obj_refcount_dec ___P((___WORD obj),(obj) ___WORD obj;)
{ (void)obj; ++fatal_hits; }

#ifdef ___DEFINE_THREAD_LOCAL_STORAGE_GETTER_SETTER
void *___get_tls_ptr ___PVOID
{
#ifdef ___THREAD_LOCAL_STORAGE_CLASS
  return ___tls_ptr;
#else
  return test_tls;
#endif
}
void ___set_tls_ptr ___P((void *ptr),(ptr) void *ptr;)
{
#ifdef ___THREAD_LOCAL_STORAGE_CLASS
  ___tls_ptr = ptr;
#else
  test_tls = ptr;
#endif
}
#endif

#ifndef ___MEM_SOURCE_FILE
#define ___MEM_SOURCE_FILE "rest-span-ownership.c"
#endif
#include "_mem/configuration.inc"
#include "_mem/binding-views.inc"
#include "_mem/rc-allocation.inc"
#include "_setup/vm-registry.inc"

#if defined(__GNUC__)
___global_state_struct ___gstate0 __attribute__((aligned(65536)));
#else
___global_state_struct ___gstate0;
#endif

static int failures;

void ___group_demand_retire(___processor_state ps)
{ (void)ps; }

static void fail(int line, const char *what)
{
  fprintf(stderr, "rest-span-ownership:%d: %s\n", line, what);
  ++failures;
}
#define CHECK(x) do { if(!(x)) fail(__LINE__, #x); } while (0)

static int file_has(const char *path, const char *needle)
{
  FILE *f = fopen(path, "rb");
  long n;
  char *buf;
  int ok = 0;
  if (!f) return 0;
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 0; }
  n = ftell(f);
  if (n < 0) { fclose(f); return 0; }
  rewind(f);
  buf = malloc((size_t)n + 1);
  if (!buf) { fclose(f); return 0; }
  ok = fread(buf, 1, (size_t)n, f) == (size_t)n;
  fclose(f);
  if (!ok) { free(buf); return 0; }
  buf[n] = 0;
  ok = strstr(buf, needle) != 0;
  free(buf);
  return ok;
}

static const char *thread_source(void)
{
  if (file_has("lib/_thread.c", "___H__23__23_thread_2d_join_2d_wait_21_"))
    return "lib/_thread.c";
  if (file_has("vendor/gambit/lib/_thread.c", "___H__23__23_thread_2d_join_2d_wait_21_"))
    return "vendor/gambit/lib/_thread.c";
  return 0;
}

static ___rest_span_request request_of(int keyword, ___WORD attempt,
                                       ___WORD np, ___WORD nb_req_opt,
                                       ___WORD nb_key, ___WORD j, ___WORD i,
                                       ___WORD n, ___SCMOBJ label,
                                       ___SCMOBJ rest_list,
                                       const ___SCMOBJ *window,
                                       const ___SCMOBJ *key_vals)
{
  ___rest_span_request request;
  memset(&request, 0, sizeof request);
  request.attempt=attempt;
  request.keyword=keyword;
  request.np=np;
  request.nb_req_opt=nb_req_opt;
  request.nb_key=nb_key;
  request.j=j;
  request.i=i;
  request.n=n;
  request.label=label;
  request.rest_list=rest_list;
  request.window=window;
  request.key_vals=key_vals;
  return request;
}

static ___processor_state boot(void)
{
  ___virtual_machine_state vm;
  ___processor_state ps;
  ___vm_lifecycle *life;
  static ___vm_lifecycle storage;
  static ___execution_context context;
  if (___GSTATE != &___gstate0) {
    fprintf(stderr, "rest-span-ownership: gstate is not the aligned object\n");
    return 0;
  }
  memset(___GSTATE, 0, sizeof *___GSTATE);
  memset(&storage, 0, sizeof storage);
  memset(&context, 0, sizeof context);
  vm=&___GSTATE->vmstate0;
  life=&storage;
  vm->lifecycle=life;
  vm->processor_count=1;
#ifndef ___SINGLE_VM
  vm->next=vm;
  vm->prev=vm;
#endif
  life->phase=___VM_LIVE;
#ifdef ___USE_POSIX_THREAD_SYSTEM
  life->owners[0].thread_id=pthread_self();
#endif
  ps=___PSTATE_FROM_PROCESSOR_ID(0, vm);
#ifndef ___SINGLE_THREADED_VMS
  ps->vmstate=vm;
#endif
  ps->context=&context;
  ___SET_REAL_PSTATE(ps);
  if (___PSTATE != ps) {
    fprintf(stderr, "rest-span-ownership: current processor was not installed\n");
    return 0;
  }
  vm_registry_open();
  if (!setup_rc(ps)) {
    fprintf(stderr, "rest-span-ownership: RC domain was not created\n");
    return 0;
  }
  return ps;
}

static int span_ok(___processor_state ps, ___activation_record *record,
                   ___WORD attempt, ___WORD epoch, ___SCMOBJ label,
                   ___SCMOBJ rest_list, const ___SCMOBJ *window, ___WORD n,
                   const ___SCMOBJ *keys, ___WORD nb_key, ___WORD root_count)
{
  ___rc_header *h;
  ___SCMOBJ *slot;
  ___SCMOBJ got_label=___FIX(0), got_rest=___FIX(0), got_result=___FIX(0);
  ___SCMOBJ loaded_window[8], loaded_keys[8];
  ___WORD u;
  if (!record || !record->roots) return 0;
  h=___CAST(___rc_header*,record->roots)-1;
  slot=___CAST(___SCMOBJ*,record->roots);
  if (h->root_count!=(___SIZE_T)root_count || h->root_borrows!=1) return 0;
  if (h->data!=label || slot[0]!=rest_list || slot[root_count-1]!=___FAL)
    return 0;
  for (u=0; u<n; u++) if (slot[1+u]!=window[u]) return 0;
  for (u=0; u<nb_key; u++) if (slot[n+1+u]!=keys[u]) return 0;
  if (record->roots==(void *)window || record->rest_context==(void *)window)
    return 0;
  if (record->rest_context!=ps->context || record->rest_phase!=___REST_INSTALLED)
    return 0;
  if (___rest_span_query(ps, record, attempt, epoch, &got_label, &got_rest,
                         &got_result)!=___REST_OK || got_label!=label ||
      got_rest!=rest_list || got_result!=___FAL) return 0;
  for (u=0; u<8; u++) { loaded_window[u]=___FIX(99); loaded_keys[u]=___FIX(99); }
  if (___rest_span_reload(ps, record, attempt, epoch, loaded_window, n-1,
                          loaded_keys, nb_key)!=___REST_REFUSED ||
      loaded_window[0]!=___FIX(99)) return 0;
  if (___rest_span_reload(ps, record, attempt, epoch, loaded_window, n,
                          loaded_keys, nb_key)!=___REST_OK) return 0;
  for (u=0; u<n; u++) if (loaded_window[u]!=window[u]) return 0;
  for (u=0; u<nb_key; u++) if (loaded_keys[u]!=keys[u]) return 0;
  return ps->mem.rc_domain_->nodes==1 && ps->mem.rc_domain_->borrows==1;
}

int main(void)
{
  ___WORD unused=___FIX(7);
  ___WORD word_max=(___WORD)((~(___UWORD)0)>>1);
  ___SCMOBJ ordinary_window[4];
  ___SCMOBJ ordinary_saved[4];
  ___SCMOBJ keyword_window[4];
  ___SCMOBJ keyword_saved[4];
  ___SCMOBJ keyword_keys[2];
  ___SCMOBJ dsssl_window[3];
  ___SCMOBJ dsssl_keys[1];
  ___SCMOBJ label, rest_list, result, poisoned;
  ___activation_record *record;
  ___activation_record *legacy;
  ___processor_state ps;
  ___rest_span_request request;
  ___rc_header *header;
  ___WORD epoch=0, epoch1=0, epoch5=0, epoch_reused=0;
  void *kept_roots;
  static ___execution_context other_context;
  int ordinary=0, keyword=0, layout=0, overflow=0, alloc_refused=0;
  int duplicate=0, lost=0, clear=0, unchanged=0, sfun_rejected=0;
  int stale=0, freed=0, reserve_same;

  overflow=!___rest_signed_sum(word_max, 1, &unused) && unused==___FIX(7);
  CHECK(overflow);
  CHECK(___rest_signed_sum(3, 4, &unused) && unused==7);
  request=request_of(1, ___FIX(1), 1, word_max, 0, 1, 0, 0,
                     ___FIX(1), ___FIX(1), 0, 0);
  CHECK(___rest_activation_open(0, &request)==0);
  CHECK(allocs==0 && fatal_hits==0 && refused_allocs==0);
  overflow=overflow && allocs==0;

  ps=boot();
  if (!ps || fatal_hits || interrupt_hits) return 1;

  {
    const char *thread = thread_source();
    CHECK(thread);
    CHECK(file_has(thread, "___JUMP_CONTINUATION_CAPTURE3(___JUMPNOTSAFE)"));
    CHECK(file_has(thread, "___CHECK_HEAP(2,4096)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_join_2d_wait_21_,___IFD(___RETI,1,4,0x3f1L),3)"));
    CHECK(file_has(thread, "___JUMP_THREAD_PARK5(___JUMPNOTSAFE)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_join_2d_register_21_,___IFD(___RETN,9,1,0x3fL),2)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_intr_21_,___IFD(___RETN,5,0,0xbL),6)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_intr_2d_service_21_,___IFD(___RETN,5,1,0x7L),2)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_end_2d_locked_21_,___IFD(___RETN,5,0,0x7L),3)"));
    CHECK(file_has(thread, "___DEF_LBL_RET_AT(___H__23__23_thread_2d_execute_2d_and_2d_end_21_,___IFD(___RETN,1,0,0x1L),2)"));
  }

  {
    ___WORD heap[64];
    ___msection *section;
    section_claim *claim;
    ___WORD *hp;
    ___WORD *fp;
    ___WORD *half;
    ___WORD words;
    ___WORD pair_words=(___WORD)(___PAIR_SIZE+___PAIR_BODY);
    int saved_fatals;
    words=2*pair_words+2+(___WORD)___VECTOR_BODY;
    section=calloc(1, ___sizeof_msection(___MSECTION_SIZE)+2*sizeof *claim);
    CHECK(section);
    half=section->base;
    claim=((void *)(half+___MSECTION_SIZE+___msection_scan_words(___MSECTION_SIZE)));
    claim->stack_owner=ps;
    claim->stack_state=STACK_ACTIVE;
    ps->mem.stack_msection_=section;
    ps->mem.tospace_offset_=0;
    ps->mem.alloc_stack_limit_=half;
    ps->mem.alloc_stack_start_=half+(___MSECTION_SIZE>>1);
    hp=heap+8;
    fp=ps->mem.alloc_stack_start_-4;
    ps->context->hp=hp;
    ps->context->fp=fp;
    ps->mem.alloc_heap_start_=heap;
    ps->mem.alloc_heap_limit_=hp+words;
    ps->heap_limit=hp+words;
    CHECK(___rest_grant_fits(ps, hp, fp, 2, 2, 1));
    ps->mem.alloc_heap_limit_=hp+words-1;
    ps->heap_limit=hp+words-1;
    CHECK(!___rest_grant_fits(ps, hp, fp, 2, 2, 1) && fatal_hits==0);
    saved_fatals=fatal_hits;
    ps->context->fp=half+(___MSECTION_SIZE>>1)+8;
    CHECK(!___rest_grant_fits(ps, hp, ps->context->fp, 2, 2, 1) &&
          fatal_hits==saved_fatals+1);
    fatal_hits=saved_fatals;
    ps->context->fp=fp;
    CHECK(___rest_fallback_pair_writes==0 && ___rest_fallback_pops==0 &&
          ___rest_fallback_vector_writes==0);
    heap[8]=0x1111;
    ___rest_mark_attempt_cut(ps, hp, fp, 1, 4000);
    CHECK(___rest_attempt_cut_kind==1 && ___rest_attempt_cut_cursor==4000);
    CHECK(___rest_attempt_cut_sentinel==0x52455354 &&
          ___rest_attempt_sentinel==0x52455354);
    CHECK(___rest_attempt_cut_word==0x1111 &&
          ___rest_attempt_cut_word!=___rest_attempt_cut_sentinel);
    CHECK(___rest_fallback_pair_writes==0 && ___rest_fallback_pops==0);
    ps->mem.alloc_heap_limit_=hp+words;
    ps->heap_limit=hp+words;
    ps->context->hp=hp+1;
    CHECK(!___rest_grant_fits(ps, hp, fp, 2, 2, 1));
    ps->context->hp=hp;
    fp=ps->mem.alloc_stack_limit_;
    ps->context->fp=fp;
    CHECK(!___rest_grant_fits(ps, hp, fp, 2, 2, 1) && fatal_hits==0);
    saved_fatals=fatal_hits;
    fp=half+(___MSECTION_SIZE>>1)+8;
    ps->context->fp=fp;
    CHECK(!___rest_grant_fits(ps, hp, fp, 2, 2, 1) && fatal_hits==saved_fatals+1);
    fatal_hits=saved_fatals;
    ps->mem.alloc_stack_limit_=half+(___MSECTION_SIZE>>1);
    ps->mem.alloc_stack_start_=half+___MSECTION_SIZE;
    claim=((void *)(half+___MSECTION_SIZE+___msection_scan_words(___MSECTION_SIZE)))+1;
    claim->stack_owner=ps;
    claim->stack_state=STACK_ACTIVE;
    ps->mem.tospace_offset_=___MSECTION_SIZE>>1;
    fp=half+4;
    ps->context->fp=fp;
    saved_fatals=fatal_hits;
    CHECK(!___rest_grant_fits(ps, hp, fp, 2, 2, 1) && fatal_hits==saved_fatals+1);
    fatal_hits=saved_fatals;
    ps->mem.stack_msection_=0;
    ps->mem.tospace_offset_=0;
    ps->context->hp=0;
    ps->mem.alloc_heap_start_=0;
    ps->mem.alloc_heap_limit_=0;
    ps->heap_limit=0;
    ps->mem.alloc_stack_limit_=0;
    ps->mem.alloc_stack_start_=0;
    free(section);
  }

  {
    ___SCMOBJ retry_window[2];
    ___WORD list_slot, window_slot, window_n, key_slot, key_n, result_slot;
    ___WORD *old_hp=(___WORD*)1;
    ___WORD *new_hp=0;
    ___SCMOBJ entered=___FAL;
    ___WORD entries;
    ___rc_header *span;
    retry_window[0]=___FIX(4);
    retry_window[1]=___FIX(5);
    request=request_of(0, ___FIX(1), 1, 0, 0, 0, 2, 2,
                       ___FAL, ___NUL, retry_window, 0);
    record=___rest_activation_open(ps, &request);
    epoch=record ? record->rest_epoch : 0;
    CHECK(record && ___rest_span_publish(ps, record, &request, epoch)==___REST_OK);
    ___rest_retry_map(record, &list_slot, &window_slot, &window_n,
                      &key_slot, &key_n, &result_slot);
    span=___CAST(___rc_header*,record->roots)-1;
    CHECK(list_slot==0 && window_slot==1 && window_n==2 && key_n==0 &&
          result_slot==3 && span->root_count==(___SIZE_T)(result_slot+1) &&
          ___CAST(___SCMOBJ*,record->roots)[result_slot]==___FAL);
    CHECK(___rest_claim_ready(ps, record, ___FIX(1), epoch, ___FIX(50))==___REST_OK);
    entries=___rest_internal_entries;
    ps->context->hp=(___WORD*)4;
    CHECK(___rest_resume_delivery(ps, record, epoch, ___FIX(1), &old_hp, &new_hp,
                                  &entered)==___REST_OK);
    CHECK(entered==___FIX(50) && new_hp==ps->context->hp &&
          ___rest_internal_entries==entries+1);
    CHECK(___rest_resume_delivery(ps, record, epoch, ___FIX(1), &old_hp, &new_hp,
                                  &entered)==___REST_DUPLICATE);
    CHECK(___rest_internal_entries==entries+1);
    CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), epoch)==___REST_OK);
    ps->context->hp=0;
  }

  legacy=___lifecycle_marker_prepare(ps);
  request=request_of(0, ___FIX(1), 2, 1, 0, 0, 1, 2,
                     ___FIX(1), ___FIX(2), ordinary_window, 0);
  ordinary_window[0]=___FIX(10);
  ordinary_window[1]=___FIX(11);
  /* This address already carries the epoch-1 terminal receipt from the
   * retry above. A late publish must not treat that as a new rest record. */
  CHECK(legacy && ___rest_span_publish(ps, legacy, &request, 1)==___REST_DUPLICATE);
  ___lifecycle_marker_abort(legacy);
  CHECK(ps->mem.rc_domain_->nodes==0 && fatal_hits==0);

  ordinary_window[0]=___FIX(10);
  ordinary_window[1]=___FIX(11);
  ordinary_window[2]=___FIX(12);
  ordinary_window[3]=___FIX(13);
  memcpy(ordinary_saved, ordinary_window, sizeof ordinary_window);
  request=request_of(0, ___FIX(1), 3, 2, 0, 0, 2, 4,
                     ___FIX(3), ___FIX(9), ordinary_window, 0);
  record=___rest_activation_open(ps, &request);
  epoch=record ? record->rest_epoch : 0;
  CHECK(record && epoch>0 &&
        ___rest_span_query(ps, record, ___FIX(1), epoch, &label, &rest_list,
                           &result)==___REST_LOST);
  lost=fatal_hits==0 && refused_allocs==0;
  CHECK(record && ___rest_span_publish(ps, record, &request, epoch)==___REST_OK);
  unchanged=memcmp(ordinary_window, ordinary_saved, sizeof ordinary_window)==0;
  CHECK(record && span_ok(ps, record, ___FIX(1), epoch, ___FIX(3), ___FIX(9),
                          ordinary_saved, 4, 0, 0, 6));
  ordinary_window[0]=___FIX(70);
  CHECK(record && ___rest_span_reload(ps, record, ___FIX(1), epoch,
                                      ordinary_window, 4, 0, 0)==___REST_OK &&
        ordinary_window[0]==___FIX(10));
  CHECK(!___store_rc_root(ps, record->roots, 1, ___FIX(80)));
  header=___CAST(___rc_header*,record->roots)-1;
  sfun_rejected=___CAST(___SCMOBJ*,record->roots)[0]==___FIX(9) &&
    header->data==___FIX(3);
  request.label=___FIX(4);
  CHECK(___rest_span_publish(ps, record, &request, epoch)==___REST_DUPLICATE);
  CHECK(header->data==___FIX(3));
  CHECK(___rest_claim_ready(ps, record, ___FIX(9), epoch, ___FIX(50))==___REST_LOST);
  CHECK(___CAST(___SCMOBJ*,record->roots)[5]==___FAL);
  CHECK(___rest_claim_ready(ps, record, ___FIX(1), epoch, ___FIX(50))==___REST_OK);
  CHECK(___rest_claim_ready(ps, record, ___FIX(1), epoch, ___FIX(51))==___REST_DUPLICATE);
  CHECK(___rest_span_query(ps, record, ___FIX(1), epoch, &label, &rest_list, &result)
        ==___REST_OK && result==___FIX(50) && label==___FIX(3));
  duplicate=result==___FIX(50) && record->rest_phase==___REST_READY;
  epoch1=epoch;
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), epoch1)==___REST_OK);
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), epoch1)==___REST_DUPLICATE);
  clear=ps->mem.rc_domain_->idle_activation &&
    ___rest_control_clear(ps->mem.rc_domain_->idle_activation) &&
    ps->mem.rc_domain_->nodes==0 && ps->mem.rc_domain_->borrows==0;
  ordinary=clear && unchanged && sfun_rejected && duplicate && lost;

  /* The idle record is reused. A delayed cleanup of attempt 1 must present
   * attempt 1's epoch. The same address and a later reused fixnum are not
   * proof, and neither call may drop attempt 5's borrow. */
  legacy=record;
  request=request_of(0, ___FIX(5), 2, 1, 0, 0, 1, 2,
                     ___FIX(1), ___FIX(2), ordinary_saved, 0);
  record=___rest_activation_open(ps, &request);
  epoch5=record ? record->rest_epoch : 0;
  CHECK(record && record==legacy && epoch5>epoch1);
  CHECK(record && ___rest_span_publish(ps, record, &request, epoch5)==___REST_OK);
  kept_roots=record ? record->roots : 0;
  CHECK(___rest_activation_cleanup(ps, legacy, ___FIX(1), epoch1)==___REST_DUPLICATE);
  CHECK(___rest_span_query(ps, legacy, ___FIX(1), epoch1, &label, &rest_list,
                           &result)==___REST_DUPLICATE);
  CHECK(___rest_claim_ready(ps, legacy, ___FIX(1), epoch1, ___FIX(80))==___REST_DUPLICATE);
  CHECK(record->kind==___ACTIVATION_REST && record->roots==kept_roots &&
        record->rest_attempt==___FIX(5) && record->rest_epoch==epoch5);
  memset(&other_context, 0, sizeof other_context);
  ps->context=&other_context;
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(5), epoch5)==___REST_LOST);
  CHECK(___rest_span_publish(ps, record, &request, epoch5)==___REST_LOST);
  ps->context=___CAST(___execution_context*,legacy->rest_context);
  CHECK(record->roots==kept_roots && record->rest_context==ps->context);
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), epoch5)==___REST_LOST);
  CHECK(record->roots==kept_roots && fatal_hits==0);
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(5), epoch5)==___REST_OK);
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(5), epoch5)==___REST_DUPLICATE);
  request=request_of(0, ___FIX(1), 2, 1, 0, 0, 1, 2,
                     ___FIX(1), ___FIX(2), ordinary_saved, 0);
  record=___rest_activation_open(ps, &request);
  epoch_reused=record ? record->rest_epoch : 0;
  CHECK(record && record==legacy && epoch_reused>epoch5 &&
        record->rest_attempt==___FIX(1));
  CHECK(record && ___rest_span_publish(ps, record, &request, epoch_reused)==___REST_OK);
  kept_roots=record ? record->roots : 0;
  CHECK(___rest_activation_cleanup(ps, legacy, ___FIX(1), epoch1)==___REST_LOST);
  CHECK(___rest_activation_cleanup(ps, legacy, ___FIX(5), epoch5)==___REST_DUPLICATE);
  CHECK(record->kind==___ACTIVATION_REST && record->roots==kept_roots &&
        ___CAST(___SCMOBJ*,record->roots)[0]==___FIX(2));
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), epoch_reused)==___REST_OK);
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(1), 99)==___REST_UNKNOWN);
  stale=record->kind!=___ACTIVATION_REST &&
    ps->mem.rc_domain_->idle_activation &&
    ___rest_control_clear(ps->mem.rc_domain_->idle_activation) &&
    ps->mem.rc_domain_->nodes==0 && ps->mem.rc_domain_->borrows==0 &&
    fatal_hits==0;

  keyword_window[0]=___FIX(21);
  keyword_window[1]=___FIX(22);
  keyword_window[2]=___FIX(23);
  keyword_window[3]=___FIX(24);
  memcpy(keyword_saved, keyword_window, sizeof keyword_window);
  keyword_keys[0]=___FIX(31);
  keyword_keys[1]=___FIX(32);
  request=request_of(1, ___FIX(2), 4, 1, 2, 2, 1, 4,
                     ___FIX(8), ___FIX(11), keyword_window, keyword_keys);
  record=___rest_activation_open(ps, &request);
  epoch=record ? record->rest_epoch : 0;
  CHECK(record && epoch>epoch_reused && record->rest_j==2 &&
        record->rest_nb_key==2 && record->rest_i==1 &&
        record->rest_context==ps->context);
  CHECK(___rest_span_publish(ps, record, &request, epoch)==___REST_OK);
  CHECK(span_ok(ps, record, ___FIX(2), epoch, ___FIX(8), ___FIX(11),
                keyword_saved, 4, keyword_keys, 2, 8));
  keyword_window[0]=___FIX(90);
  CHECK(___rest_span_reload(ps, record, ___FIX(2), epoch, keyword_window, 4,
                            keyword_keys, 2)==___REST_OK &&
        keyword_window[0]==___FIX(21) && keyword_keys[1]==___FIX(32));
  keyword=1;
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(2), epoch)==___REST_OK);

  dsssl_window[0]=___FIX(41);
  dsssl_window[1]=___FIX(42);
  dsssl_window[2]=___FIX(43);
  dsssl_keys[0]=___FIX(44);
  request=request_of(1, ___FIX(3), 3, 1, 1, 0, 2, 3,
                     ___FIX(8), ___FIX(12), dsssl_window, dsssl_keys);
  record=___rest_activation_open(ps, &request);
  epoch=record ? record->rest_epoch : 0;
  CHECK(record && ___rest_span_publish(ps, record, &request, epoch)==___REST_OK);
  CHECK(span_ok(ps, record, ___FIX(3), epoch, ___FIX(8), ___FIX(12),
                dsssl_window, 3, dsssl_keys, 1, 6));
  layout=record->rest_n==3 && record->rest_j==0 && record->rest_nb_key==1;
  CHECK(___rest_activation_cleanup(ps, record, ___FIX(3), epoch)==___REST_OK);
  CHECK(___rest_control_clear(ps->mem.rc_domain_->idle_activation));

  /* Two live records, one idle slot. The first cleanup occupies the slot.
   * The second frees its storage. A later query and cleanup of that address
   * must resolve the directory receipt and must not load the freed record. */
  {
    ___activation_record *first, *second;
    ___WORD first_epoch, second_epoch, loads;
    ___SCMOBJ late_window[2];
    late_window[0]=___FIX(1);
    late_window[1]=___FIX(2);
    request=request_of(0, ___FIX(11), 2, 1, 0, 0, 1, 2,
                       ___FIX(11), ___FIX(11), late_window, 0);
    first=___rest_activation_open(ps, &request);
    first_epoch=first ? first->rest_epoch : 0;
    CHECK(first && ___rest_span_publish(ps, first, &request, first_epoch)==___REST_OK);
    request=request_of(0, ___FIX(12), 2, 1, 0, 0, 1, 2,
                       ___FIX(12), ___FIX(12), late_window, 0);
    second=___rest_activation_open(ps, &request);
    second_epoch=second ? second->rest_epoch : 0;
    CHECK(second && second!=first &&
          ___rest_span_publish(ps, second, &request, second_epoch)==___REST_OK);
    CHECK(___rest_activation_cleanup(ps, first, ___FIX(11), first_epoch)==___REST_OK);
    CHECK(ps->mem.rc_domain_->idle_activation==first);
    CHECK(___rest_activation_cleanup(ps, second, ___FIX(12), second_epoch)==___REST_OK);
    CHECK(ps->mem.rc_domain_->idle_activation==first);
    loads=___rest_record_field_loads;
    CHECK(___rest_span_query(ps, second, ___FIX(12), second_epoch, &label,
                             &rest_list, &result)==___REST_DUPLICATE);
    CHECK(___rest_activation_cleanup(ps, second, ___FIX(12), second_epoch)==___REST_DUPLICATE);
    freed=___rest_record_field_loads==loads &&
      ps->mem.rc_domain_->idle_activation==first && fatal_hits==0;
  }

  request=request_of(0, ___FIX(4), 2, 1, 0, 0, 1, 2,
                     ___FIX(1), ___FIX(2), ordinary_saved, 0);
  record=___rest_activation_open(ps, &request);
  epoch=record ? record->rest_epoch : 0;
  block_alloc=1;
  CHECK(record && ___rest_span_publish(ps, record, &request, epoch)==___REST_REFUSED);
  block_alloc=0;
  alloc_refused=record && record->roots==0 &&
    record->rest_phase==___REST_PUBLISHING &&
    ps->mem.rc_domain_->nodes==0 && fatal_hits==0 && refused_allocs>0 &&
    ordinary_saved[0]==___FIX(10) && ordinary_saved[3]==___FIX(13);
  if (record) CHECK(___rest_activation_cleanup(ps, record, ___FIX(4), epoch)==___REST_OK);
  CHECK(___rest_control_clear(ps->mem.rc_domain_->idle_activation));
  ___VMSTATE_FROM_PSTATE(ps)->lifecycle->rest_epoch_next=
    (___WORD)((~(___UWORD)0)>>1);
  CHECK(___rest_activation_open(ps, &request)==0 && fatal_hits==0 &&
        ___rest_control_clear(ps->mem.rc_domain_->idle_activation));
  (void)poisoned;

  reserve_same=___REST_PARAM_RESERVE==9220 &&
    ___MSECTION_FUDGE==___REST_PARAM_RESERVE;
  if (failures || !ordinary || !keyword || !layout || !overflow ||
      !alloc_refused || !duplicate || !lost || !clear || !unchanged ||
      !sfun_rejected || !stale || !freed || fatal_hits || interrupt_hits || !reserve_same)
    return 2;
  printf("REST-SPAN-OWNERSHIP ordinary=%d keyword=%d layout=%d overflow=%d alloc=%d duplicate=%d lost=%d clear=%d unchanged=%d sfun=%d stale=%d freed=%d fatal=%d reserve=%d cut=%ld sentinel=%lx\n",
         ordinary, keyword, layout, overflow, alloc_refused, duplicate, lost,
         clear, unchanged, sfun_rejected, stale, freed, fatal_hits,
         (int)___REST_PARAM_RESERVE,
         (long)___rest_attempt_cut_cursor, (unsigned long)___rest_attempt_cut_sentinel);
  return 0;
}
