/* Opt-in diagnostic declarations. Production builds leave
 * ___GAMBIT_DEV_RESTORE_PROBE undefined and do not include this header.
 * The translation unit is not in the production link. */
#ifndef ___RESTORE_COLLECTIVE_PROBE_H
#define ___RESTORE_COLLECTIVE_PROBE_H

void ___dev_restore_before_final_read(___processor_state ___ps, ___UWORD epoch);
void ___dev_restore_after_reader(___processor_state ___ps, ___UWORD epoch);
int ___dev_restore_before_barrier(___processor_state ___ps, ___UWORD epoch);
void ___dev_restore_inside_barrier(___processor_state ___ps);
void ___dev_restore_after_barrier(___processor_state ___ps, ___UWORD epoch);
void ___dev_restore_alloc_expire(___processor_state ___ps, ___UWORD epoch);
void ___dev_restore_alloc_arm(___processor_state ___ps, ___UWORD epoch);
void ___dev_restore_census_native(const char *kind);

/* Closure and other-allocation hooks are declared in header_end.h.in and
 * defined in restore-collective-probe.c. The positive marker is printed
 * only after the bound closure's label, trampoline setup and four free
 * fields have been stored. Direct ___hp updates and native allocation
 * attempts at the covered sites exit before the write or allocator call when
 * they are the first hooked entry. Production builds do not define
 * ___GAMBIT_DEV_RESTORE_PROBE. */

#endif
