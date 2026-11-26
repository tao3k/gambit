/* File: "mem.c" */

/* Copyright (c) 1994-2026 by Marc Feeley, All Rights Reserved.  */

#define ___INCLUDED_FROM_MEM
#define ___VERSION 409008
#include "gambit.h"

#include "os_setup.h"
#include "os_base.h"
#include "os_thread.h"
#include "os_time.h"
#include "setup.h"
#include "mem.h"
#include "rc.h"
#include "lifecycle.h"
#include "c_intf.h"
#include "actlog.h"

/* The following includes are needed for debugging. */

#include <stdlib.h>
#include <string.h>
#include "rest-observation.h"


/* Internal source organization; inclusion order is part of the contract.
 * Preserve original logical diagnostic coordinates across fragments. */
#if defined(__BASE_FILE__)
#define ___MEM_SOURCE_FILE __BASE_FILE__
#else
#define ___MEM_SOURCE_FILE "mem.c"
#endif
#include "_mem/rest-observation.inc"

#ifdef ___GAMBIT_DEV_RESTORE_PROBE
#include "../tests/smp/gc/restore-collective-probe.h"
#endif

#include "_mem/configuration.inc"
#include "_mem/aligned-allocation.inc"
#include "_mem/rc-allocation.inc"
#include "_mem/global-storage.inc"
#include "_mem/binding-views.inc"
#include "_mem/root-tasks.inc"
#include "_mem/movable-sections.inc"

/* Worker-owned direct-mapped msection cache scoped strictly to work->vm
 * (no _Thread_local storage, eliminating cross-VM pointer ABA reuse). */
static inline ___msection *___gc_find_msection_cached
   (___collector_worker *work, ___msections *ms, ___WORD *ptr)
{
  ___UWORD addr = ___CAST(___UWORD, ptr);
  ___SIZE_TS epoch = ___COLLECTION(work->vm).epoch;
  int ns = ms->nb_sections;
  ___UWORD slot = (addr / (___CAST(___UWORD, ___MSECTION_SIZE) * ___WS)) & ___GC_SEC_CACHE_MASK;
  if (__builtin_expect(work->sec_cache_epoch_ == epoch &&
                       work->sec_cache_nb_sections_ == ns, 1))
    {
      ___msection *s = work->sec_cache_[slot];
      if (__builtin_expect(s != 0 &&
                           addr - ___CAST(___UWORD, s->base) < ___MSECTION_SIZE * ___WS, 1))
        return s;
    }
  else
    {
      memset(work->sec_cache_, 0, sizeof(work->sec_cache_));
      work->sec_cache_epoch_ = epoch;
      work->sec_cache_nb_sections_ = ns;
    }
  {
    int i = find_msection(ms, ptr);
    if (i >= 0 && i < ns)
      {
        ___msection *s = ms->sections[i];
        if (addr - ___CAST(___UWORD, s->base) < ___MSECTION_SIZE * ___WS)
          {
            work->sec_cache_[slot] = s;
            return s;
          }
      }
  }
  return 0;
}
#include "_mem/permanent-allocation.inc"
#include "_mem/global-bindings.inc"
#include "_mem/still-refcount.inc"
#include "_mem/object-allocation.inc"
#include "_mem/symbols.inc"
#include "_mem/diagnostics.inc"
___HIDDEN void publish_fast_span ___P((___processor_state ___ps),());
___HIDDEN void clear_fast_span ___P((___processor_state ___ps),());
#include "_mem/heap-sections.inc"
#include "_mem/startup-reservation.inc"
___HIDDEN void major_shade_mature_movable(___virtual_machine_state vm, ___msection *sec, ___WORD *header, ___WORD head);
___HIDDEN void major_shade_mature_still(___virtual_machine_state vm, ___WORD *base, ___WORD head);
___HIDDEN void major_register_weak_table(___virtual_machine_state vm, ___SCMOBJ ht);
___HIDDEN int major_has_pending_mark_work(___virtual_machine_state vm);
___HIDDEN void major_initial_mark_begin(___virtual_machine_state vm);
___HIDDEN void major_minor_gc_drain_satb(___virtual_machine_state vm);
___HIDDEN void major_remark_phase_a_prepare(___virtual_machine_state vm);
___HIDDEN void major_remark_phase_a_parallel(___virtual_machine_state vm, int w_id, int w_cnt);
___HIDDEN void major_remark_phase_b_coord(___virtual_machine_state vm);
___HIDDEN void major_remark_phase_c_parallel(___virtual_machine_state vm, int w_id, int w_cnt);
___HIDDEN void major_remark_phase_d_coord(___virtual_machine_state vm);
___HIDDEN void major_abort_for_full_compacting_gc(___virtual_machine_state vm);
#include "_mem/copy-reservations.inc"
#include "_mem/continuation-roots.inc"
#include "_mem/rc-roots.inc"
#include "_mem/object-scanning.inc"
#include "_mem/generational.inc"
#include "_mem/still-sweep.inc"
#include "_mem/concurrent-major.inc"
#include "_mem/memory-lifecycle.inc"
#include "_mem/wills.inc"
#include "_mem/weak-tables.inc"
#include "_mem/hash-table-api.inc"
#include "_mem/capacity-resize.inc"
#include "_mem/root-origins.inc"
#include "_mem/copy-planning.inc"
#include "_mem/collection-round.inc"
#include "_mem/allocation-limits.inc"
#include "_mem/allocation-statistics.inc"

#undef ___MEM_SOURCE_FILE
