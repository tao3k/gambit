/* Private startup transaction. Existing VM slots, roots and Make entrypoints. */
#ifndef ___VM_RESIZE_H
#define ___VM_RESIZE_H
#include <limits.h>
#ifndef ___SINGLE_THREADED_VMS

enum ___resize_phase { ___RESIZE_IDLE, ___RESIZE_PREPARING,
                      ___RESIZE_RUN, ___RESIZE_ABORT, ___RESIZE_RETAINED };
enum ___resize_slot_phase { ___RESIZE_EMPTY, ___RESIZE_RESERVED,
                           ___RESIZE_INITIALIZED, ___RESIZE_CREATED };
typedef struct ___resize_slot_struct {
  ___msection *stack, *heap;
  void *root;
  const ___SCMOBJ *cell;
  enum ___resize_slot_phase phase;
} ___resize_slot;
typedef struct ___resize_state_struct {
  ___MUTEX_DECL(gate)
  ___CONDVAR_DECL(changed)
  enum ___resize_phase phase;
  int first, target, saved_assigned, saved_stacks;
  ___msection *saved_cursor;
  ___SCMOBJ result;
  ___resize_slot slots[___MAX_PROCESSORS];
} ___resize_state;

extern ___SCMOBJ ___reserve_resize(___processor_state, ___resize_state*);
extern void ___refund_resize(___processor_state, ___resize_state*);
extern int ___resume_msections(___virtual_machine_state);
extern int ___restore_msections(___virtual_machine_state);

/* A retained pre-publication cohort has no new Scheme member. Its native
 * outcomes must be reconciled before the owning VM may reclaim its grants. */
static ___BOOL resize_retained(___virtual_machine_state vm)
{
  ___resize_state *r=vm->resize_state;
  ___BOOL retained;
  if (r == 0) return 0;
  ___MUTEX_LOCK(r->gate);
  retained=r->phase == ___RESIZE_RETAINED;
  ___MUTEX_UNLOCK(r->gate);
  return retained;
}
#endif
#endif
