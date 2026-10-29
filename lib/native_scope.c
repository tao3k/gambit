/* Bounded native write-authority records; no allocation, callbacks or GC. */
#define ___INCLUDED_FROM_NATIVE_SCOPE
#define ___VERSION 409008
#include "gambit.h"
#include "native_scope.h"

#if ___WORD_WIDTH < 32
#error "native scopes require at least a 32-bit word"
#endif
typedef char scope_one_word[(sizeof (___native_scope) == sizeof (___WORD)) ? 1 : -1];

/* Sequential sync macros use PSTATE scratch space.  Keep this service free of
 * PSTATE: use ordinary accesses only in that explicitly single-thread backend.
 * Other backends use Gambit's existing full-barrier RMW/CAS operations.  The
 * emulated backend is not asynchronous lock-owner-death recovery.
 */
static ___WORD scope_read (___native_scope *scope)
{
#ifdef ___USE_sequential_sync
  return scope->gate;
#else
  return ___FETCH_AND_ADD_WORD(&scope->gate,0);
#endif
}

static ___WORD scope_cas (___native_scope *scope, ___WORD old, ___WORD next)
{
#ifdef ___USE_sequential_sync
  ___WORD found = scope->gate;
  if (found == old)
    scope->gate = next;
  return found;
#else
  return ___COMPARE_AND_SWAP_WORD(&scope->gate,old,next);
#endif
}

static int scope_valid_tag (___WORD tag)
{
  if (tag < 0 || (tag & ~___NATIVE_SCOPE_TAG_MASK) != 0)
    return 0;
  if (tag == 0)
    return 1;
  return (tag >> ___NATIVE_SCOPE_GENERATION_SHIFT) != 0 &&
         ((tag >> ___NATIVE_SCOPE_ACTOR_SHIFT) & 255) != 0;
}

void ___native_scope_init (___native_scope *scope)
{
  scope->gate = ___NATIVE_SCOPE_CLOSED;
}

void ___native_scope_init_vmstate (___virtual_machine_state vms)
{
  unsigned int i;
  for (i=0; i<___NATIVE_SCOPE_CAPACITY; i++)
    ___native_scope_init (&vms->native_scopes[i]);
}

___WORD ___native_scope_snapshot (___native_scope *scope)
{
  return scope_read (scope);
}

int ___native_scope_prepare
  (___WORD previous, unsigned int actor, ___WORD *candidate)
{
  ___UWORD generation;
  if (!scope_valid_tag (previous) || actor == 0 || actor > 255)
    return ___NATIVE_SCOPE_INVALID;
  generation = ___CAST(___UWORD,previous) >> ___NATIVE_SCOPE_GENERATION_SHIFT;
  if (generation == ___NATIVE_SCOPE_MAX_GENERATION)
    return ___NATIVE_SCOPE_EXHAUSTED;
  *candidate = ___CAST(___WORD,((generation+1) << ___NATIVE_SCOPE_GENERATION_SHIFT) |
                         (___CAST(___UWORD,actor) << ___NATIVE_SCOPE_ACTOR_SHIFT));
  return ___NATIVE_SCOPE_OK;
}

int ___native_scope_try_handoff
  (___native_scope *scope, ___WORD previous, ___WORD candidate)
{
  ___WORD old, next, expected;
  unsigned int actor;
  int status;
  if (!scope_valid_tag (candidate) || candidate == 0)
    return ___NATIVE_SCOPE_INVALID;
  actor = ___CAST(unsigned int,(candidate >> ___NATIVE_SCOPE_ACTOR_SHIFT) & 255);
  status = ___native_scope_prepare (previous, actor, &expected);
  if (status != ___NATIVE_SCOPE_OK)
    return status;
  if (candidate != expected)
    return ___NATIVE_SCOPE_INVALID;
  old = scope_read (scope);
  for (;;)
    {
      if ((old & ___NATIVE_SCOPE_TAG_MASK) == candidate)
        return ___NATIVE_SCOPE_REPLAY;
      if ((old & ___NATIVE_SCOPE_TAG_MASK) != previous)
        return ___NATIVE_SCOPE_STALE;
      if (!(old & ___NATIVE_SCOPE_CLOSED) || (old & ___NATIVE_SCOPE_LIVE_MASK))
        return ___NATIVE_SCOPE_BUSY;
      /* The new owner starts with BOTH class permits.  There is no open,
       * unaccounted writer window before a possibly lost acquisition reply.
       */
      next = candidate |
             (___CAST(___WORD,17)<<___NATIVE_SCOPE_LIVE_SHIFT) |
             (___CAST(___WORD,17)<<___NATIVE_SCOPE_USED_SHIFT);
      expected = scope_cas (scope, old, next);
      if (expected == old)
        return ___NATIVE_SCOPE_OK;
      old = expected;
    }
}

int ___native_scope_try_acquire
  (___native_scope *scope, ___WORD tag, unsigned int role)
{
  ___WORD old, found, used, live;
  if (!scope_valid_tag (tag) || tag == 0 || role >= ___NATIVE_SCOPE_ROLES)
    return ___NATIVE_SCOPE_INVALID;
  used = ___CAST(___WORD,1) << (___NATIVE_SCOPE_USED_SHIFT+role);
  live = ___CAST(___WORD,1) << (___NATIVE_SCOPE_LIVE_SHIFT+role);
  old = scope_read (scope);
  for (;;)
    {
      if ((old & ___NATIVE_SCOPE_TAG_MASK) != tag)
        return ___NATIVE_SCOPE_STALE;
      if (old & ___NATIVE_SCOPE_CLOSED)
        return ___NATIVE_SCOPE_BUSY;
      if (old & used)
        return ___NATIVE_SCOPE_USED;
      found = scope_cas (scope, old, old | used | live);
      if (found == old)
        return ___NATIVE_SCOPE_OK;
      old = found;
    }
}

int ___native_scope_close (___native_scope *scope, ___WORD tag)
{
  ___WORD old, found;
  if (!scope_valid_tag (tag) || tag == 0)
    return ___NATIVE_SCOPE_INVALID;
  old = scope_read (scope);
  for (;;)
    {
      if ((old & ___NATIVE_SCOPE_TAG_MASK) != tag)
        return ___NATIVE_SCOPE_STALE;
      if (old & ___NATIVE_SCOPE_CLOSED)
        return ___NATIVE_SCOPE_REPLAY;
      found = scope_cas (scope, old, old | ___NATIVE_SCOPE_CLOSED);
      if (found == old)
        return ___NATIVE_SCOPE_OK;
      old = found;
    }
}

int ___native_scope_release
  (___native_scope *scope, ___WORD tag, unsigned int role)
{
  ___WORD old, found, used, live;
  if (!scope_valid_tag (tag) || tag == 0 || role >= ___NATIVE_SCOPE_ROLES)
    return ___NATIVE_SCOPE_INVALID;
  used = ___CAST(___WORD,1) << (___NATIVE_SCOPE_USED_SHIFT+role);
  live = ___CAST(___WORD,1) << (___NATIVE_SCOPE_LIVE_SHIFT+role);
  old = scope_read (scope);
  for (;;)
    {
      if ((old & ___NATIVE_SCOPE_TAG_MASK) != tag)
        return ___NATIVE_SCOPE_STALE;
      if (!(old & used))
        return ___NATIVE_SCOPE_INVALID;
      if (!(old & live))
        return ___NATIVE_SCOPE_REPLAY;
      /* Only the producer, AFTER its last actual write/borrow, may release.
       * Catcher observation/failed join does not authorize clearing this bit.
       */
      found = scope_cas (scope, old, old & ~live);
      if (found == old)
        return ___NATIVE_SCOPE_OK;
      old = found;
    }
}

int ___native_scope_class_quiescent
  (___native_scope *scope, ___WORD tag, unsigned int first_role)
{
  ___WORD old, mask;
  if (!scope_valid_tag (tag) || tag == 0 ||
      (first_role != ___NATIVE_SCOPE_CONTROL &&
       first_role != ___NATIVE_SCOPE_DATA))
    return ___NATIVE_SCOPE_INVALID;
  old = scope_read (scope);
  if ((old & ___NATIVE_SCOPE_TAG_MASK) != tag)
    return ___NATIVE_SCOPE_STALE;
  mask = ___CAST(___WORD,15) << (___NATIVE_SCOPE_LIVE_SHIFT+first_role);
  if (!(old & ___NATIVE_SCOPE_CLOSED) || (old & mask))
    return ___NATIVE_SCOPE_BUSY;
  return ___NATIVE_SCOPE_OK;
}

int ___native_scope_quiescent (
___native_scope *scope, ___WORD tag)
{
  ___WORD old;
  if (!scope_valid_tag (tag) || tag == 0)
    return ___NATIVE_SCOPE_INVALID;
  old = scope_read (scope);
  if ((old & ___NATIVE_SCOPE_TAG_MASK) != tag)
    return ___NATIVE_SCOPE_STALE;
  if (!(old & ___NATIVE_SCOPE_CLOSED) || (old & ___NATIVE_SCOPE_LIVE_MASK))
    return ___NATIVE_SCOPE_BUSY;
  /* Covers registered permits ONLY.  Not a physical stop/root/VM-free seal.
   * Another qualified actor can already have advanced after this snapshot.
   */
  return ___NATIVE_SCOPE_OK;
}
