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
} ___resize_launch;

typedef struct ___resize_slot_struct {
  ___msection *stack, *heap;
  void *root;
  const ___SCMOBJ *cell;
  enum ___resize_slot_phase phase;
} ___resize_slot;

typedef struct ___activation_record_struct {
  struct ___activation_record_struct *next;
  ___processor_state owner;
  ___SCMOBJ marker;
  int startup; /* Only run_startup_root grants terminal ownership. */
} ___activation_record;

typedef struct ___vm_lifecycle_struct {
  ___VOLATILE ___WORD phase;
  ___WORD incarnation;
  ___VOLATILE ___WORD member_gate, pending_interrupts;
  ___VOLATILE ___WORD requests[___MAX_PROCESSORS];
  unsigned int setup_stages;
  ___VOLATILE ___WORD entries[___MAX_PROCESSORS]; /* bit0 closed, +2 per borrow */
  ___owner_cleanup cleanup[___MAX_PROCESSORS];
  ___activation_record *activations[___MAX_PROCESSORS];
  ___thread owners[___MAX_PROCESSORS];
#ifndef ___SINGLE_THREADED_VMS
  ___MUTEX_DECL(gate)
  ___CONDVAR_DECL(changed)
  enum ___resize_phase resize_phase;
  int first, target, saved_assigned, saved_stacks, refusal;
  ___msection *saved_cursor;
  ___SCMOBJ result;
  ___WORD generation;
  ___resize_slot slots[___MAX_PROCESSORS];
  ___resize_launch launches[___MAX_PROCESSORS];
#endif
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
  if (___LOAD_GLOBAL_WORD(&r->phase)==___VM_RETAINED) return 1;
  for(i=0;i<___MAX_PROCESSORS;++i)
    if (___LOAD_GLOBAL_WORD(&r->launches[i].uncertain) &&
        ___LOAD_GLOBAL_WORD(&r->launches[i].entry)==___LAUNCH_RUN &&
        !___LOAD_GLOBAL_WORD(&r->launches[i].data_closed)) return 1;
  return r->resize_phase==___RESIZE_RETAINED;
}
#endif
#endif
