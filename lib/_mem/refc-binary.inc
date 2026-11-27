/* Off-Heap Immutable Reference-Counted Binaries and External Phantom-Byte
 * Accounting.
 *
 * Implements:
 *   - Racket-on-Chez style external phantom-byte accounting coupled directly
 *     into GC triggers and global concurrent major work pacing, bounding total
 *     managed + native RSS without polling.
 *   - Erlang ProcBin / Rust Arc style off-heap binaries requiring the
 *     ___REFC_BIN_FLAG_IMMUTABLE tag bit before cross-core zero-copy sharing,
 *     with release-order refcount decrement and an acquire fence prior to final
 *     deallocation when the observed previous count equals 1. */

#ifndef ___REFC_BINARY_INC
#define ___REFC_BINARY_INC

#include <stddef.h>

#define ___GC_PHANTOM_MIN_TRIGGER_DEFAULT (___CAST(___WORD, 16) * 1024 * 1024)
#define ___GC_PHANTOM_MIN_TRIGGER_FLOOR   (___CAST(___WORD, 2) * 1024 * 1024)

___HIDDEN ___WORD gc_phantom_min_trigger_bytes(void)
{
  ___WORD min_trig = ___GC_PHANTOM_MIN_TRIGGER_DEFAULT;
  if (___GSTATE != 0 && ___GSTATE->setup_params.max_heap > 0)
    {
      ___WORD half_max = ___CAST(___WORD, ___GSTATE->setup_params.max_heap >> 1);
      if (half_max < min_trig)
        min_trig = half_max;
      if (min_trig < ___GC_PHANTOM_MIN_TRIGGER_FLOOR)
        min_trig = ___GC_PHANTOM_MIN_TRIGGER_FLOOR;
    }
  return min_trig;
}

static inline void gc_phantom_update_peak(___virtual_machine_state vm, ___WORD cur)
{
  ___WORD peak = ___WORD_LOAD_RELAXED(&vm->mem.phantom_bytes_peak_);
  while (cur > peak)
    {
      if (___WORD_CAS_ACQUIRE(&vm->mem.phantom_bytes_peak_, peak, cur))
        break;
      peak = ___WORD_LOAD_RELAXED(&vm->mem.phantom_bytes_peak_);
    }
}

static inline ___WORD gc_sub_phantom_bytes_vm
   (___virtual_machine_state vm,
    ___SIZE_T bytes)
{
  ___WORD cur, next, trig, min_trig;
  if (vm == 0 || bytes == 0)
    return vm ? ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_) : 0;

  cur = ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_);
  for (;;)
    {
      next = (cur > ___CAST(___WORD, bytes)) ? (cur - ___CAST(___WORD, bytes)) : 0;
      if (___WORD_CAS_ACQUIRE(&vm->mem.phantom_bytes_live_, cur, next))
        break;
      cur = ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_);
    }

  /* Prevent trigger ratcheting after deferred foreign cleanup releases large
   * off-heap buffers: when live phantom bytes drop below half of the active
   * trigger, tighten the trigger back toward the working set + minimum headroom. */
  min_trig = gc_phantom_min_trigger_bytes();
  trig = ___WORD_LOAD_ACQUIRE(&vm->mem.major_trigger_phantom_bytes_);
  if (trig > min_trig && next < (trig >> 1))
    {
      ___WORD tightened = next + min_trig;
      if (tightened < min_trig)
        tightened = min_trig;
      if (tightened < trig)
        ___WORD_STORE_RELEASE(&vm->mem.major_trigger_phantom_bytes_, tightened);
    }
  return next;
}

/* Lock-free, strictly non-moving external native-memory pressure registration.
 * Positive deltas charge global concurrent major work pacing and arm GC/major
 * triggers once phantom_bytes_live_ reaches major_trigger_phantom_bytes_.
 * Negative deltas release external pressure with underflow clamping at zero. */
___EXP_FUNC(___SIZE_TS,___gc_register_phantom_bytes)
   ___P((___processor_state ___ps,
         ___SIZE_TS delta_bytes),
        (___ps,
         delta_bytes)
___processor_state ___ps;
___SIZE_TS delta_bytes;)
{
  ___virtual_machine_state vm;
  ___WORD new_live;

  if (___ps == 0)
    return 0;
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0)
    return 0;

  if (delta_bytes == 0)
    return ___CAST(___SIZE_TS, ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_));

  if (delta_bytes < 0)
    return ___CAST(___SIZE_TS,
                   gc_sub_phantom_bytes_vm(vm, ___CAST(___SIZE_T, -delta_bytes)));

  new_live =
    ___WORD_FETCH_ADD_RELEASE(&vm->mem.phantom_bytes_live_, ___CAST(___WORD, delta_bytes)) +
    ___CAST(___WORD, delta_bytes);
  gc_phantom_update_peak(vm, new_live);

#ifndef ___DISABLE_GENERATIONAL_GC
  {
    ___WORD trig = ___WORD_LOAD_ACQUIRE(&vm->mem.major_trigger_phantom_bytes_);
    ___WORD phase = ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_);
    ___SIZE_TS delta_words = (delta_bytes + ___WS - 1) >> ___LWS;

    if (phase == ___GC_MAJOR_MARKING)
      gc_major_pace_alloc_words(___ps, delta_words);

    if (trig > 0 && new_live >= trig)
      {
        if (phase == ___GC_MAJOR_IDLE)
          {
            ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, 1);
            ___WORD_STORE_RELEASE(&vm->mem.phantom_gc_needed_, 1);
          }
        else if (phase == ___GC_MAJOR_MARKING)
          {
            if (___ps->primlock_depth == 0)
              ___gc_major_mark_slice(___ps, 262144);
            if ((___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) == 0 &&
                 ___ps->mem.major_mark_local_count_ == 0 &&
                 ___ps->mem.satb_count_ == 0) ||
                new_live >= trig + (trig >> 1))
              {
                ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, 2);
                ___WORD_STORE_RELEASE(&vm->mem.phantom_gc_needed_, 1);
              }
          }
      }
  }
#endif

  return ___CAST(___SIZE_TS, new_live);
}

___HIDDEN ___SCMOBJ gc_refc_bin_foreign_release
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  ___gc_refc_bin_release(___CAST(___refc_bin*, ptr));
  return ___FIX(___NO_ERR);
}

/* Reclaim a built-in lock-free ___refc_bin foreign wrapper directly during
 * sweep on any core (thread-agnostic, non-throwing, avoids parked-owner
 * cleanup queues pinning large dead off-heap buffers). Returns 1 if handled. */
___HIDDEN int gc_try_reclaim_refc_foreign(___WORD *base)
{
  ___SCMOBJ obj = ___TAG(base + ___STILL_BODY - ___REFERENCE_TO_BODY, ___tSUBTYPED);
  if (___FOREIGN_RELEASE_FN_FIELD(obj) == ___CAST(___SCMOBJ, gc_refc_bin_foreign_release))
    {
      ___refc_bin *bin = ___CAST(___refc_bin*, ___FOREIGN_PTR_FIELD(obj));
      ___FOREIGN_RELEASE_FN_FIELD(obj) = 0;
      ___FOREIGN_PTR_FIELD(obj) = 0;
      ___gc_refc_bin_release(bin);
      return 1;
    }
  return 0;
}

___EXP_FUNC(___refc_bin*,___gc_refc_bin_create)
   ___P((___processor_state ___ps,
         const void *src,
         ___SIZE_T byte_len,
         int immutable),
        (___ps,
         src,
         byte_len,
         immutable)
___processor_state ___ps;
const void *src;
___SIZE_T byte_len;
int immutable;)
{
  ___SIZE_T hdr_size = ___CAST(___SIZE_T, offsetof(___refc_bin, data));
  ___SIZE_T payload_alloc = (byte_len > 0) ? byte_len : 1;
  ___virtual_machine_state vm = (___ps != 0) ? ___VMSTATE_FROM_PSTATE(___ps) : 0;
  ___refc_bin *bin;

  if (payload_alloc > (~___CAST(___SIZE_T, 0)) - hdr_size)
    return 0;

  bin = ___CAST(___refc_bin*, ___ALLOC_MEM(hdr_size + payload_alloc));
  if (bin == 0)
    return 0;

  ___WORD_STORE_RELEASE(&bin->refcount, 1);
  bin->flags = immutable ? ___REFC_BIN_FLAG_IMMUTABLE : 0u;
  bin->reserved = 0u;
  bin->byte_len = byte_len;
  bin->owner_vm = vm;
  if (byte_len > 0)
    {
      if (src != 0)
        memcpy(bin->data, src, byte_len);
      else
        memset(bin->data, 0, byte_len);
    }

  if (vm != 0)
    {
      ___WORD_FETCH_ADD_RELAXED(&vm->mem.refc_bins_created_, 1);
      if (byte_len > 0)
        ___gc_register_phantom_bytes(___ps, ___CAST(___SIZE_TS, byte_len));
    }

  return bin;
}

/* Zero-copy retain/share across SMP cores. Strictly requires the
 * ___REFC_BIN_FLAG_IMMUTABLE tag bit to rule out shared-mutation data races. */
___EXP_FUNC(___refc_bin*,___gc_refc_bin_share)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  if (bin == 0 || (bin->flags & ___REFC_BIN_FLAG_IMMUTABLE) == 0u)
    return 0;
  ___WORD_FETCH_ADD_RELAXED(&bin->refcount, 1);
  if (bin->owner_vm != 0)
    ___WORD_FETCH_ADD_RELAXED(&bin->owner_vm->mem.refc_bins_shared_, 1);
  return bin;
}

/* Freeze a uniquely owned mutable off-heap binary (refcount == 1) so it may
 * subsequently be shared zero-copy across SMP cores. */
___EXP_FUNC(int,___gc_refc_bin_freeze)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  if (bin == 0)
    return 0;
  if ((bin->flags & ___REFC_BIN_FLAG_IMMUTABLE) != 0u)
    return 1;
  if (___WORD_LOAD_ACQUIRE(&bin->refcount) != 1)
    return 0;
#if defined(__ATOMIC_RELEASE)
  __atomic_thread_fence(__ATOMIC_RELEASE);
#else
  ___WORD_STORE_RELEASE(&bin->refcount, 1);
#endif
  bin->flags |= ___REFC_BIN_FLAG_IMMUTABLE;
  return 1;
}

/* Release one reference to an off-heap binary. Uses release-order decrement so
 * every prior payload read/write happens-before deallocation, and issues an
 * acquire fence before freeing when the observed previous count equals 1. */
___EXP_FUNC(int,___gc_refc_bin_release)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  ___WORD prev;
  if (bin == 0)
    return 0;

  prev = ___WORD_FETCH_ADD_RELEASE(&bin->refcount, -1);
  if (prev == 1)
    {
      ___virtual_machine_state vm = bin->owner_vm;
      ___SIZE_T len = bin->byte_len;
#if defined(__ATOMIC_ACQUIRE)
      __atomic_thread_fence(__ATOMIC_ACQUIRE);
#else
      (void)___WORD_LOAD_ACQUIRE(&bin->refcount);
#endif
      if (vm != 0)
        {
          if (len > 0)
            gc_sub_phantom_bytes_vm(vm, len);
          ___WORD_FETCH_ADD_RELAXED(&vm->mem.refc_bins_freed_, 1);
        }
      ___FREE_MEM(bin);
      return 1;
    }
  return 0;
}

/* Wrap an off-heap RefC binary in a lightweight Gambit ___sFOREIGN handle
 * with automatic GC finalization via ___lifecycle_drain(). When take_ref != 0,
 * retains a shared reference (requiring ___REFC_BIN_FLAG_IMMUTABLE). Returns a
 * still ___sFOREIGN object with initial still refcount 1 (release via
 * ___release_scmobj() before handing ownership to Scheme), ___FAL on invalid
 * mutable share, or a fixnum error code on allocation failure. */
___EXP_FUNC(___SCMOBJ,___gc_refc_bin_wrap)
   ___P((___processor_state ___ps,
         ___refc_bin *bin,
         int take_ref),
        (___ps,
         bin,
         take_ref)
___processor_state ___ps;
___refc_bin *bin;
int take_ref;)
{
  ___SCMOBJ r;
  if (___ps == 0 || bin == 0)
    return ___FAL;
  if (take_ref != 0)
    {
      if (___gc_refc_bin_share(bin) == 0)
        return ___FAL;
    }
  r = ___alloc_scmobj(___ps, ___sFOREIGN, ___FOREIGN_SIZE << ___LWS);
  if (___FIXNUMP(r))
    {
      if (take_ref != 0)
        ___gc_refc_bin_release(bin);
      return r;
    }
  ___FOREIGN_TAGS_FIELD(r) = ___FAL;
  ___FOREIGN_RELEASE_FN_FIELD(r) = ___CAST(___SCMOBJ, gc_refc_bin_foreign_release);
  ___FOREIGN_PTR_FIELD(r) = ___CAST(___SCMOBJ, bin);
  return r;
}

___EXP_FUNC(___refc_bin*,___gc_refc_bin_unwrap)
   ___P((___SCMOBJ obj),
        (obj)
___SCMOBJ obj;)
{
  ___SCMOBJ ___temp;
  if (!___MEM_ALLOCATED(obj) || !___TESTSUBTYPE(obj, ___sFOREIGN))
    return 0;
  if (___FOREIGN_RELEASE_FN_FIELD(obj) != ___CAST(___SCMOBJ, gc_refc_bin_foreign_release))
    return 0;
  return ___CAST(___refc_bin*, ___FOREIGN_PTR_FIELD(obj));
}

___EXP_FUNC(void*,___gc_refc_bin_data)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  return (bin != 0) ? ___CAST(void*, bin->data) : 0;
}

___EXP_FUNC(___SIZE_T,___gc_refc_bin_length)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  return (bin != 0) ? bin->byte_len : 0;
}

___EXP_FUNC(int,___gc_refc_bin_is_immutable)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  return (bin != 0 && (bin->flags & ___REFC_BIN_FLAG_IMMUTABLE) != 0u) ? 1 : 0;
}

___EXP_FUNC(___WORD,___gc_refc_bin_refcount)
   ___P((___refc_bin *bin),
        (bin)
___refc_bin *bin;)
{
  return (bin != 0) ? ___WORD_LOAD_ACQUIRE(&bin->refcount) : 0;
}

#endif
