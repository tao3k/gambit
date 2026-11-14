/* Narrow callout adapter for the actual c_intf.c translation unit. Mode0
 * delegates unchanged. Modes1/2 fail the bank/marker constructor; mode3
 * collects at the marker boundary after the generated raw-input prefix.
 * This adapter never supplies an alternative activation implementation. */
#include "gambit.h"
#include "rc.h"
#include "lifecycle.h"

int sfun_entry_fault, sfun_entry_banks, sfun_entry_markers;
int sfun_entry_custody, sfun_entry_moved;
___SIZE_T sfun_entry_nodes, sfun_entry_borrows;
void *sfun_entry_self_root;
void *sfun_test_closure_self(void) { return sfun_entry_self_root; }

void *sfun_test_allocate_root_bank(___processor_state ps, ___SIZE_T count)
{
  ++sfun_entry_banks;
  if (sfun_entry_fault==1) return 0;
  return ___alloc_rc_roots(ps,count);
}

___SCMOBJ sfun_test_make_vector(___processor_state ps, ___SIZE_TS length,
                               ___SCMOBJ init)
{
  ++sfun_entry_markers;
  if (sfun_entry_fault==2) return ___FIX(___HEAP_OVERFLOW_ERR);
  if (sfun_entry_fault==3) {
    ___rc_domain *d=ps->mem.rc_domain_;
    ___activation_record *record=___VMSTATE_FROM_PSTATE(ps)->lifecycle->activations[
      ___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps))];
    ___rc_header *h=record && record->roots ? ___CAST(___rc_header*,record->roots)-1 : 0;
    ___SCMOBJ first=h ? ___CAST(___SCMOBJ*,record->roots)[0] : record->marker;
    sfun_entry_custody=h ?
      h->root_count==3 && d->nodes==sfun_entry_nodes+1 &&
      d->borrows==sfun_entry_borrows+1 && h->root_borrows==1 :
      record->kind==___ACTIVATION_SFUN_PERMANENT &&
      ___TESTTYPE(first,___tSUBTYPED) && ___HD_TYP(___SUBTYPED_HEADER(first))==___PERM &&
      d->nodes==sfun_entry_nodes && d->borrows==sfun_entry_borrows;
    if (!sfun_entry_custody || ___garbage_collect(___PSA(ps) 0))
      return ___FIX(___HEAP_OVERFLOW_ERR);
    sfun_entry_moved=first!=(h ? ___CAST(___SCMOBJ*,record->roots)[0] : record->marker);
  }
  return ___make_vector(ps,length,init);
}
