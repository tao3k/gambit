/* VM ownership, launch descriptors and owner-affine release. The descriptor
 * outlives an uncertain native join; it never borrows a retired PSTATE. */
#ifndef ___LIFECYCLE_H
#define ___LIFECYCLE_H
#include "gambit.h"
#include <limits.h>
static inline ___WORD ___lifecycle_cas(___VOLATILE ___WORD *p,___WORD old,___WORD value)
{
#ifdef ___USE_sequential_sync
  ___WORD found=*p;if(found==old)*p=value;return found;
#else
  return ___COMPARE_AND_SWAP_WORD(p,old,value);
#endif
}

enum ___vm_phase { ___VM_BUILDING, ___VM_LIVE, ___VM_CLOSING,
                  ___VM_RETAINED, ___VM_DRAINED, ___VM_CLOSED };
enum ___resize_phase { ___RESIZE_IDLE, ___RESIZE_PREPARING,
                      ___RESIZE_RUN, ___RESIZE_ABORT, ___RESIZE_RETAINED };
enum ___resize_slot_phase { ___RESIZE_EMPTY, ___RESIZE_RESERVED,
                           ___RESIZE_INITIALIZED, ___RESIZE_CREATED };
enum ___launch_entry { ___LAUNCH_PARKED, ___LAUNCH_RUN, ___LAUNCH_ABORT };
enum ___startup_phase { ___STARTUP_PENDING, ___STARTUP_READY, ___STARTUP_RETURNED };

typedef struct ___owner_cleanup_struct {
  ___WORD *pending, *inflight;
  ___SIZE_TS words;
  ___SCMOBJ (*release_fn) ___P((void*),());
  void *payload;
  int draining, uncertain;
} ___owner_cleanup;

typedef struct ___resize_launch_struct {
  ___thread thread;
  ___virtual_machine_state vm;
  ___WORD generation;
  int id;
  ___VOLATILE ___WORD entry, native_live, joined, data_closed, uncertain;
  int managed_startup;
  enum ___startup_phase startup_phase; /* Protected by the VM gate. */
} ___resize_launch;

typedef struct ___resize_slot_struct {
  ___msection *stack, *heap;
  void *root;
  const ___SCMOBJ *cell;
  enum ___resize_slot_phase phase;
} ___resize_slot;

enum ___activation_kind {
  ___ACTIVATION_LEGACY, ___ACTIVATION_STARTUP,
  ___ACTIVATION_SFUN_ROOTED, ___ACTIVATION_SFUN_PERMANENT,
  ___ACTIVATION_SFUN_ACTIVE, ___ACTIVATION_SFUN_REVOKED,
  ___ACTIVATION_REST, ___ACTIVATION_IDLE
};
/* Counts, phase and the attempt stay off the scanned RC slots. The context
 * pointer is the stable VM execution identity, never a stack address. */
enum ___rest_phase {
  ___REST_NONE, ___REST_PUBLISHING, ___REST_INSTALLED, ___REST_READY
};
enum ___rest_status {
  ___REST_OK, ___REST_REFUSED, ___REST_LOST, ___REST_DUPLICATE,
  ___REST_UNKNOWN, /* proof missed; no release and no reuse of that outcome */
  ___REST_RETRY /* one reader already holds the pin; no record field was loaded */
};
/* Directory phase word: one pin at bit 2, phase in bits 0-1.
 * Generation is a separate slot field. A full ___WORD shifted by eight does
 * not fit in this word, so the phase word never carries it. A lookup may
 * read the phase word, the generation field and the directory pointer. It
 * must not load an activation-record field until the pin CAS has succeeded.
 * FREE is stored only after the terminal receipt and the last metadata write. */
#define ___REST_DIRECTORY_SLOTS 4
#define ___REST_PHASE_FREE 0
#define ___REST_PHASE_PUBLISHING 1
#define ___REST_PHASE_OPEN 2
#define ___REST_PHASE_CLOSED 3
#define ___REST_ST_PHASE(state) ((state) & 3)
#define ___REST_ST_PIN(state) (((state) >> 2) & 1)
#define ___REST_ST_MAKE(pin, phase) (((pin) << 2) | (phase))
/* Build the configured internal-return frame at the current fp. The saved
 * label supplies the descriptor and return address. Call this only after the
 * caller argument window is no longer the scanned top of stack. */
#define ___REST_PUBLISH_RETRY_FRAME(return_label) \
do { \
  int ___rest_cfs; \
  ___SCMOBJ ___rest_ra=(return_label); \
  ___RETI_GET_CFS(___rest_ra,___rest_cfs); \
  ___ADJFP(___ROUND_TO_MULT(___rest_cfs,___FRAME_ALIGN)-___rest_cfs); \
  ___PUSH_REGS \
  ___PUSH(___rest_ra) \
  ___ADJFP(-___RETI_RA) \
  ___SET_R0(___ps->internal_return) \
  ___FRAME_STORE_RA(___R0) \
} while (0);
/* Return fp to the frame that was current before ___REST_PUBLISH_RETRY_FRAME. */
#define ___REST_RETRACT_RETRY_FRAME() \
do { \
  ___WORD ___rest_saved=___FP_STK(___fp,___RETI_RA); \
  int ___rest_fs,___rest_link; \
  ___RETI_GET_FS_LINK(___rest_saved,___rest_fs,___rest_link); \
  ___ADJFP(-___FRAME_SPACE(___rest_fs)); \
} while (0);
typedef struct ___rest_span_request_struct {
  ___WORD attempt; /* non-pointer fixnum token; raw zero is unused */
  ___WORD n;
  ___WORD nb_key;
  ___WORD j;
  ___WORD i;
  ___WORD np;
  ___WORD nb_req_opt;
  int keyword; /* 0 ordinary rest, 1 either keyword-rest spelling */
  ___SCMOBJ label;
  ___SCMOBJ rest_list;
  const ___SCMOBJ *window; /* n words copied in; not retained */
  const ___SCMOBJ *key_vals; /* nb_key words copied in; not retained */
} ___rest_span_request;
typedef struct ___activation_record_struct {
  struct ___activation_record_struct *next;
  ___processor_state owner;
  ___SCMOBJ marker; /* PERMANENT preparation holds an immovable proc instead */
  void *roots; /* one registered SFUN bank, retained through physical C exit */
  ___WORD startup_generation; /* Used only by the rooted startup activation. */
  enum ___activation_kind kind;
  ___WORD rest_attempt;
  ___WORD rest_n;
  ___WORD rest_nb_key;
  ___WORD rest_j;
  ___WORD rest_i;
  ___WORD rest_np;
  ___WORD rest_nb_req_opt;
  int rest_keyword;
  int rest_delivered; /* one internal entry has consumed this READY result */
  enum ___rest_phase rest_phase;
  void *rest_context;
  ___WORD rest_epoch; /* live generation issued by the VM; 0 is unused */
  ___WORD rest_retired_epoch; /* last generation settled on this storage */
} ___activation_record;

static int ___activation_marker_live(___activation_record *record)
{
  return record->marker!=___FAL &&
    (record->kind==___ACTIVATION_LEGACY || record->kind==___ACTIVATION_STARTUP ||
     record->kind==___ACTIVATION_SFUN_ACTIVE);
}

static inline void ___rest_control_reset(___activation_record *record)
{
  record->rest_attempt=0;
  record->rest_n=0;
  record->rest_nb_key=0;
  record->rest_j=0;
  record->rest_i=0;
  record->rest_np=0;
  record->rest_nb_req_opt=0;
  record->rest_keyword=0;
  record->rest_delivered=0;
  record->rest_phase=___REST_NONE;
  record->rest_context=0;
  record->rest_epoch=0;
  /* rest_retired_epoch stays. It is the only proof a later occupant is new. */
}

static inline int ___rest_control_clear(___activation_record *record)
{
  return record->rest_attempt==0 && record->rest_n==0 &&
    record->rest_nb_key==0 && record->rest_j==0 && record->rest_i==0 &&
    record->rest_np==0 && record->rest_nb_req_opt==0 &&
    record->rest_keyword==0 && record->rest_delivered==0 &&
    record->rest_phase==___REST_NONE &&
    record->rest_context==0 && record->rest_epoch==0;
}

/* Publication copies the caller arrays under the RC gate and does not collect.
 * A refused, lost or unknown attempt leaves the caller arrays unchanged.
 * READY is stored once in the result cell. Cleanup drops the borrow only
 * when the caller proves this storage's live attempt, VM epoch and context.
 * The epoch is never reissued. A stale address or a reused attempt value
 * does not match it, so late cleanup cannot release a newer occupant. */
extern ___BOOL ___rest_signed_sum(___WORD a, ___WORD b, ___WORD *sum);
extern ___activation_record *___rest_activation_open(___processor_state ps,
                                                    const ___rest_span_request *request);
extern enum ___rest_status ___rest_span_publish(___processor_state ps,
                                               ___activation_record *record,
                                               const ___rest_span_request *request,
                                               ___WORD epoch);
extern enum ___rest_status ___rest_span_query(___processor_state ps,
                                             ___activation_record *record,
                                             ___WORD attempt, ___WORD epoch,
                                             ___SCMOBJ *label,
                                             ___SCMOBJ *rest_list,
                                             ___SCMOBJ *result);
extern enum ___rest_status ___rest_span_reload(___processor_state ps,
                                              ___activation_record *record,
                                              ___WORD attempt, ___WORD epoch,
                                              ___SCMOBJ *window, ___WORD window_n,
                                              ___SCMOBJ *key_vals, ___WORD key_n);
extern enum ___rest_status ___rest_claim_ready(___processor_state ps,
                                              ___activation_record *record,
                                              ___WORD attempt, ___WORD epoch,
                                              ___SCMOBJ vector);
extern enum ___rest_status ___rest_activation_cleanup(___processor_state ps,
                                                     ___activation_record *record,
                                                     ___WORD attempt,
                                                     ___WORD epoch);
/* Admission uses the complete demand: emitted pairs, np, and one vector
 * word. A true result still constructs only the pairs; that vector word is
 * not written here and is not debited again. False writes nothing. The
 * caller may recover and must repeat this complete-demand decision. */
extern ___BOOL ___rest_fast_grant_fits(___processor_state ps, ___WORD *hp,
                                      ___WORD *fp, ___WORD pending, ___WORD np,
                                      ___WORD stack_slots);
/* A new movable section fits the live still-word and assigned-section
 * bound. This is not the cumulative allocator counter. */
extern ___BOOL ___rest_new_section_admitted(___processor_state ps, ___SIZE_T max_heap);
/* Arms one activation. A ceiling still collects and reloads, then refuses
 * before a pair write or a pop. The cut kind is 1 after that reload,
 * 2 when a new section is refused, 3 when the root window is refused,
 * and 4 when collection itself overflows. */
extern void ___rest_arm_attempt(___WORD words, ___WORD floor);
extern void ___rest_arm_force_slow(void);
extern ___WORD ___rest_ready_claims;
extern ___WORD ___rest_resume_reloads;
extern ___WORD ___rest_resume_collections;
extern void ___rest_disarm_attempt(void);
extern int ___rest_attempt_blocked(void);
extern ___BOOL ___rest_one_word_short(___processor_state ps, ___WORD *hp, ___WORD *fp,
                                ___WORD pending, ___WORD np, ___WORD stack_slots);
extern void ___rest_note_attempt_entry(___processor_state ps,
                                     ___WORD *hp, ___WORD *fp);
extern void ___rest_note_attempt_acquired(___processor_state ps,
                                        ___WORD *hp, ___WORD *fp);
extern ___WORD ___rest_attempt_acquired_heap;
extern ___WORD ___rest_attempt_acquired_frame;
extern ___WORD ___rest_attempt_acquired_word;
extern void ___rest_capture_attempt_cut(___processor_state ps,
                                       ___WORD *hp, ___WORD *fp);
extern ___WORD ___rest_attempt_entry_heap;
extern ___WORD ___rest_attempt_entry_frame;
extern ___WORD ___rest_attempt_entry_word;
extern ___WORD ___rest_attempt_cut_heap;
extern ___WORD ___rest_attempt_cut_frame;
extern ___WORD ___rest_attempt_cut_word;
extern ___WORD ___rest_attempt_cut_kind;
extern ___WORD ___rest_attempt_seen_words;
extern ___WORD ___rest_attempt_cut_cursor;
extern ___WORD ___rest_attempt_cut_sentinel;
extern ___WORD ___rest_attempt_sentinel;
extern void ___rest_mark_attempt_cut(___processor_state ps,
                                    ___WORD *hp, ___WORD *fp, int kind,
                                    ___WORD cursor);
extern void ___rest_note_attempt_view(___processor_state ps,
                                    ___activation_record *record,
                                    ___WORD epoch, ___WORD *fp);
extern ___WORD ___rest_attempt_view_open;
extern ___WORD ___rest_attempt_view_mapped;
extern ___WORD ___rest_attempt_view_frame;
extern ___WORD ___rest_heap_cursor(___processor_state ps);
extern ___WORD ___rest_frame_cursor(___processor_state ps);
/* Retained for a single external attempt. Production grant checks do not
 * read it, so it cannot change a later rest decision. */
extern void ___rest_set_grant_cap(___WORD words, ___WORD floor);
/* Wrong-generation pin and release against one live rest record.
 * The field-load counter must stay put, and the live pin must remain. */
extern void ___rest_stale_probe(___processor_state ps);
extern void ___rest_reuse_probe(___processor_state ps);
extern ___WORD ___rest_reuse_status;
extern ___WORD ___rest_reuse_pin;
extern ___WORD ___rest_reuse_loads;
extern ___WORD ___rest_close_status;
extern ___WORD ___rest_close_pin;
extern ___WORD ___rest_close_loads;
extern ___WORD ___rest_stale_pin_status;
extern ___WORD ___rest_stale_load_delta;
extern ___WORD ___rest_stale_still_pinned;
extern ___WORD ___rest_stale_incarnation_status;
extern ___WORD ___rest_stale_incarnation_loads;
/* One READY result, then the same attempt again. The second status is the
 * duplicate refusal and the internal entry count moves only on the first. */
extern void ___rest_once_probe(___processor_state ps);
extern ___WORD ___rest_once_first;
extern ___WORD ___rest_once_second;
extern ___WORD ___rest_once_delta;
extern ___WORD ___rest_once_result;
extern ___WORD ___rest_preflight_required;
extern ___WORD ___rest_preflight_effective;
extern ___WORD ___rest_preflight_uncapped;
extern ___WORD ___rest_preflight_cap;
extern ___WORD ___rest_refusal_writes;
extern ___WORD ___rest_refusal_pops;
/* The published heap cursor stays put. If its interval cannot hold the
 * retry footprint, take a heap section that is not the stack section. */
extern ___BOOL ___rest_extend_interval(___processor_state ps,
                                      ___WORD pending, ___WORD np);
/* The argument window ends at the caller frame. ra is that frame's return
 * label, stored by the caller before collection. The chain must land on
 * stack_past without reading an incomplete descriptor. */
extern ___BOOL ___rest_caller_chain(___WORD *window, ___WORD na, ___WORD ra,
                                   ___WORD *stack_limit, ___WORD *stack_past,
                                   ___WORD internal_return);
extern ___BOOL ___rest_stack_slots_fit(___processor_state ps, ___WORD *fp,
                                     ___WORD stack_slots);
extern ___BOOL ___rest_physical_tail_short(___processor_state ps,
                                         ___WORD pending, ___WORD np);
extern ___BOOL ___rest_publish_owned_soft_edge(___processor_state ps,
                                             ___WORD pending, ___WORD np);
extern ___BOOL ___rest_grant_fits(___processor_state ps, ___WORD *hp, ___WORD *fp,
                                 ___WORD pending, ___WORD np, ___WORD stack_slots);
/* Copy the complete physical window fp[0..n) and the resolved keys. The
 * procedure label is stored in the RC header, not in the array. Failure
 * leaves the caller arrays and stack unchanged. */
extern ___BOOL ___rest_root_window(___processor_state ps, ___WORD *fp,
                                  ___SCMOBJ label, ___WORD n, ___WORD nb_key,
                                  ___SCMOBJ *key_vals, ___WORD nb_req_opt,
                                  ___WORD j, ___WORD i, ___WORD np, int keyword,
                                  ___activation_record **record_out,
                                  ___WORD *epoch_out);
extern ___BOOL ___rest_reload_window(___processor_state ps, ___WORD *fp,
                                    ___activation_record *record, ___WORD epoch,
                                    ___WORD n, ___WORD nb_key,
                                    ___SCMOBJ *key_vals, ___SCMOBJ *label_out);
extern void ___rest_retry_map(___activation_record *record,
                             ___WORD *list_slot, ___WORD *window_slot,
                             ___WORD *window_n, ___WORD *key_slot,
                             ___WORD *key_n, ___WORD *result_slot);
extern ___SCMOBJ ___rest_finish_refusal(___processor_state ps,
                                       ___activation_record *record,
                                       ___WORD epoch, ___SCMOBJ result,
                                       ___WORD **old_hp);
extern void ___rest_observation_note_store(___processor_state ps,
                                          ___activation_record *record,
                                          ___WORD epoch, ___WORD *fp,
                                          ___WORD *address);
extern void ___rest_observation_note_adjust(___processor_state ps, ___WORD *fp,
                                           long words);
extern void ___rest_observation_note_saved_fp(___processor_state ps,
                                            ___activation_record *record,
                                            ___WORD epoch, ___WORD *saved,
                                            ___WORD *parent);
extern void ___rest_observation_note_return_fp(___processor_state ps,
                                             ___activation_record *record,
                                             ___WORD epoch, ___WORD *fp);
extern void ___rest_observation_note_body(___processor_state ps);
/* Fallible pin, view, domain and phase checks. Does not store a result
 * and does not construct a pair. Call it before the first pair write. */
extern enum ___rest_status ___rest_ready_preflight(___processor_state ps,
                                                 ___activation_record *record,
                                                 ___WORD attempt,
                                                 ___WORD epoch);
extern enum ___rest_status ___rest_token_pin(___processor_state ps,
                                            ___activation_record *record,
                                            ___WORD generation);
extern enum ___rest_status ___rest_token_release(___processor_state ps,
                                                ___activation_record *record,
                                                ___WORD generation);
extern enum ___rest_status ___rest_token_close(___processor_state ps,
                                              ___activation_record *record,
                                              ___WORD generation);
extern enum ___rest_status ___rest_resume_delivery(___processor_state ps,
                                                  ___activation_record *record,
                                                  ___WORD generation,
                                                  ___WORD attempt,
                                                  ___WORD **old_hp,
                                                  ___WORD **new_hp,
                                                  ___SCMOBJ *entered);
extern int ___rest_user_continuation_restore(___WORD continuation_identity);
extern ___WORD ___rest_record_field_loads;
extern ___WORD ___rest_fallback_pops;
extern ___WORD ___rest_fallback_pair_writes;
extern ___WORD ___rest_before_collect_pops;
extern ___WORD ___rest_before_collect_writes;
extern void ___rest_note_before_collect(void);
extern ___WORD ___rest_fallback_vector_writes;
extern ___WORD ___rest_fallback_keyword_adjusts;
extern ___WORD ___rest_fallback_keyword_pushes;
extern ___WORD ___rest_internal_entries;
extern ___WORD ___rest_user_restores;

/* One write-group grant. root_fp/hp/fp/epoch are the attempt's current
 * view and are replaced after a moving collection; they are not a
 * permanent address identity. */
typedef struct ___group_demand_struct {
  ___execution_context *context;
  ___activation_record *activation;
  ___WORD group_point;
  ___WORD attempt;
  ___WORD *root_fp;
  ___WORD epoch;
  ___WORD *hp;
  ___WORD *fp;
  ___SIZE_TS stack_words;
  ___SIZE_TS heap_words;
  int phase; /* 0 empty, 1 pending, 2 granted, 3 exhausted, 4 diagnostic */
  int resume_query; /* one handler return may re-query this attempt */
} ___group_demand;

typedef struct ___vm_lifecycle_struct {
  ___VOLATILE ___WORD phase;
  ___WORD incarnation;
  ___VOLATILE ___WORD member_gate, pending_interrupts;
  ___VOLATILE ___WORD requests[___MAX_PROCESSORS];
  unsigned int setup_stages;
  ___VOLATILE ___WORD entries[___MAX_PROCESSORS]; /* bit0 closed, +2 per borrow */
  ___VOLATILE ___WORD rest_epoch_next; /* next rest generation; 0 means unstarted; never wraps */
  struct ___rest_directory_slot_struct {
    ___VOLATILE ___WORD state; /* pin and phase only */
    ___WORD incarnation;
    ___VOLATILE ___WORD generation; /* live generation; 0 while unsettled or free */
    ___WORD retired_generation; /* last generation drained; not an activation field */
    ___activation_record *record; /* directory cell; not an activation field */
  } rest_directory[___REST_DIRECTORY_SLOTS];
  ___owner_cleanup cleanup[___MAX_PROCESSORS];
  ___activation_record *activations[___MAX_PROCESSORS];
  ___thread owners[___MAX_PROCESSORS];
#ifndef ___SINGLE_THREADED_VMS
  /* Slot resources belong to this VM, not to a carrier incarnation. Bit 0
   * owns the mutex, bit 1 owns the condition variable. Constructor rollback
   * visits only acquired resources; processor retirement destroys neither. */
  unsigned char sync_constructed[___MAX_PROCESSORS];
  ___MUTEX_DECL(gate)
  ___CONDVAR_DECL(changed)
  enum ___resize_phase resize_phase;
  int first, target, saved_assigned, saved_stacks, refusal;
  ___msection *saved_cursor;
  ___SCMOBJ result;
  ___WORD generation;
  ___WORD membership_epoch; /* Every successful topology change, including shrink. */
  ___resize_slot slots[___MAX_PROCESSORS];
  ___resize_launch launches[___MAX_PROCESSORS];
#endif
  /* Demand slots are VM storage. A processor number only selects a slot
   * inside this lifecycle; it is not an identity across VMs. */
  ___group_demand group_demand[___MAX_PROCESSORS];
  ___VOLATILE ___WORD group_demand_attempt_next;
} ___vm_lifecycle;

#define ___VM_SETUP_ACTLOG 1u
#define ___VM_SETUP_MEMORY 2u
#define ___VM_SETUP_PROCESSOR 4u

/* Topology/control pin only; PSTATE/root access needs its own entry/member
 * lease. The pin remains releasable after a VM reaches DRAINED. */
extern ___BOOL ___lifecycle_registry_begin(void);
extern void ___lifecycle_registry_end(void);
extern ___BOOL ___lifecycle_enter(___processor_state);
extern int ___lifecycle_members_begin(___virtual_machine_state);
extern void ___lifecycle_members_end(___virtual_machine_state);
extern int ___lifecycle_members_close(___virtual_machine_state);
extern void ___lifecycle_members_open(___virtual_machine_state);
extern void ___lifecycle_interrupt_pending(___virtual_machine_state,int);
extern ___activation_record *___lifecycle_marker_prepare(___processor_state);
extern void ___lifecycle_marker_abort(___activation_record*);
extern void ___lifecycle_marker_kill(___processor_state,___SCMOBJ);
extern void ___lifecycle_leave(___processor_state);
extern ___BOOL ___lifecycle_gc_admitted(___processor_state);
extern void ___lifecycle_defer(___processor_state,___WORD*);
extern ___BOOL ___lifecycle_drain(___processor_state);
extern ___SIZE_TS ___lifecycle_deferred_words(___processor_state);
extern ___SIZE_TS ___lifecycle_retained_words(___virtual_machine_state);
extern void ___lifecycle_detach_foreign(___processor_state);
extern void ___lifecycle_reclaim_foreign(___processor_state,___WORD*);
enum ___handoff_status { ___HANDOFF_READY, ___HANDOFF_GC, ___HANDOFF_BUSY };
extern enum ___handoff_status ___lifecycle_can_handoff(___processor_state);
extern void ___lifecycle_handoff(___processor_state,___processor_state);
extern ___BOOL ___lifecycle_cleanup_pstate(___processor_state);
#ifndef ___SINGLE_THREADED_VMS
extern ___SCMOBJ ___reserve_resize(___processor_state, ___vm_lifecycle*);
extern void ___refund_resize(___processor_state, ___vm_lifecycle*);
extern int ___resume_msections(___virtual_machine_state);
extern int ___restore_msections(___virtual_machine_state);
static ___BOOL resize_retained(___virtual_machine_state vm)
{
  int i;
  ___vm_lifecycle *r=vm->lifecycle;
  if (!r) return 0;
  if (___WORD_LOAD_ACQUIRE(&r->phase)==___VM_RETAINED) return 1;
  for(i=0;i<___MAX_PROCESSORS;++i)
    if (___WORD_LOAD_ACQUIRE(&r->launches[i].uncertain) &&
        ___WORD_LOAD_ACQUIRE(&r->launches[i].entry)==___LAUNCH_RUN &&
        !___WORD_LOAD_ACQUIRE(&r->launches[i].data_closed)) return 1;
  return r->resize_phase==___RESIZE_RETAINED;
}
#endif
#endif
