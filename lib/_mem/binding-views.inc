/* Lifecycle admission owns binding authority. A generated host consumes this
 * same context without adding a per-host admission or module-switch cache.
 * Setup publishes executable module descriptors only after READY fixup; reads
 * acquire the existing directory so later module registration needs no view
 * invalidation. The VM store remains the sole cell and scan owner. */
void ___binding_context_close(___processor_state ps)
{
  if (!ps || !ps->context) return;
  /* Existing entry/collective synchronization orders this owner-only write. */
  ps->context->binding_view.vm=0;
}

___BOOL ___binding_context_admit(___processor_state ps)
{
  ___virtual_machine_state vm;
  ___rc_domain *domain;
  ___WORD entries;
  int id;
  if (!ps || !ps->context || !(domain=ps->mem.rc_domain_)) return 0;
  vm=___VMSTATE_FROM_PSTATE(ps); id=___PROCESSOR_ID(ps,vm);
  /* Entry has authenticated TLS/native ownership, or the stopped coordinator
   * restores the exact roster. A refresh never mints a lifecycle entry. */
  if (!vm->lifecycle || id<0 || id>=vm->processor_count ||
      ___WORD_LOAD_ACQUIRE(&vm->lifecycle->phase)!=___VM_LIVE) return 0;
  entries=___WORD_LOAD_ACQUIRE(&vm->lifecycle->entries[id]);
  if (entries<2 || (entries&1) || domain->owner!=ps ||
      domain->phase!=___RC_OPEN || domain->joined_round) return 0;
  ps->context->binding_view.vm=vm;
  return 1;
}
