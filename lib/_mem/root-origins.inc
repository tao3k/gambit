#line 4689 ___MEM_SOURCE_FILE
___HIDDEN void mark_registers(___collector_worker *work, ___execution_context *source)
{

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_REGISTER;
#endif

  mark_array (work, source->r, sizeof(source->r)/sizeof(*source->r));
}


___HIDDEN void mark_saved(___collector_worker *work, ___execution_context *source)
{

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_SAVED;
#endif

  mark_array (work, source->saved, sizeof(source->saved)/sizeof(*source->saved));
}


___HIDDEN void mark_type_cache(___collector_worker *work, ___execution_context *source)
{

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_TYPE_CACHE;
#endif

  mark_array (work, source->type_cache, sizeof(source->type_cache)/sizeof(*source->type_cache));
}


#line 6503 ___MEM_SOURCE_FILE
___HIDDEN void mark_processor_scmobj(___collector_worker *work, ___execution_context *source)
{

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_PROCESSOR_SCMOBJ;
#endif

  mark_array (work,
              ___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(source->processor_scmobj,___WS)),___tSUBTYPED),
              ___PROCESSOR_SIZE);
}


/* One bank task covers the existing disjoint register/saved/cache/processor
 * ranges. Never treat pc, fp/hp or padding as Scheme root words. */
___BOOL ___root_task_scan_bank(___root_task *task, ___processor_state executor,
                              ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  ___execution_context *source;
  if (!root_bank_task(task,executor) ||
      !root_task_matches(task,___ROOT_BANK,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  ___collector_worker *work=executor->collector;
  source=task->origin.source.bank;
  task->state=___ROOT_SCANNING;
  mark_registers (work, source);
  mark_saved (work, source);
  mark_type_cache (work, source);
  mark_processor_scmobj (work, source);
  task->state=___ROOT_SCANNED;
  return 1;
}


___HIDDEN void mark_vm_scmobj(___collector_worker *work, ___virtual_machine_state source)
{

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_VM_SCMOBJ;
#endif

  mark_array (work,
              ___BODY0_AS(___VM_SCMOBJ(source),___tSUBTYPED),
              ___VM_SIZE);
}


/* No callback or Scheme allocation is allowed between scan entry and return.
 * A failed/unknown scan cannot be acknowledged or reset as unstarted. */
___BOOL ___root_task_scan_vm(___root_task *task, ___processor_state executor,
                            ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  if (!root_vm_task(task,executor) ||
      !root_task_matches(task,___ROOT_VM,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  task->state=___ROOT_SCANNING;
  mark_vm_scmobj (executor->collector, task->origin.source.vm);
  task->state=___ROOT_SCANNED;
  return 1;
}


/* Publish relocation to the actual canonical slot. The source is stopped,
 * but metadata readers use atomic words too; do not mix atomic reads with
 * racing plain collector writes. The local word never becomes a second task. */
___HIDDEN void mark_global_cell(___collector_worker *work, ___SCMOBJ *cell)
{
  ___SCMOBJ value=___WORD_LOAD_ACQUIRE(cell);
  mark_array(work, &value,1);
  if(work==0 || work->census==0) ___WORD_STORE_RELEASE(cell,value);
}

___HIDDEN void mark_global_variables
   ___P((___PSD const ___global_root_source *source),
        (___PSV source)
___PSDKR
const ___global_root_source *source;)
{
  ___PSGET
  ___collector_worker *work = ___ps->collector;
#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_GLOBAL_VAR;
#endif
#ifdef ___SINGLE_VM
  {
    int lo=source->lo;
    while (lo < source->hi)
      {
        ___glo_sublist_struct *sl = &source->global->mem.glo_list.sublist[lo];
        ___glo_struct *glo = sl->head;
        while (glo != 0)
          {
#ifdef ___DEBUG_GARBAGE_COLLECT_globals
            print_global_var_name (glo);
            ___printf ("\n");
#endif
            mark_global_cell(work, &glo->val);
            if (___WORD_LOAD_ACQUIRE(&glo->primitive_set))
              mark_global_cell(work, &glo->primitive_value);
            else if(work==0 || work->census==0)
              ___WORD_STORE_RELEASE(&glo->primitive_value,___FAL);
            glo = glo->next;
          }
        lo++;
      }
  }
#else
  {
    int i, slot;
    ___global_slot_page *page=source->pages;
    for (i=source->lo;i<source->hi;i++,page=page->next)
      {
        ___WORD flags=___WORD_LOAD_ACQUIRE(&page->primitive_set);
        for (slot=0;slot<___WORD_WIDTH;slot++) {
          mark_global_cell(work, &page->ordinary[slot]);
          if (flags & (___CAST(___UWORD,1)<<slot))
            mark_global_cell(work, &page->primitive[slot]);
          else if (work==0 || work->census==0)
            ___WORD_STORE_RELEASE(&page->primitive[slot],___FAL);
        }
      }
  }
#endif
}

___BOOL ___root_task_scan_globals(___root_task *task, ___processor_state executor,
                                 ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  if (!root_globals_task(task,executor) ||
      !root_task_matches(task,___ROOT_GLOBALS,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  task->state=___ROOT_SCANNING;
  mark_global_variables (___PSP task->origin.source.globals);
  task->state=___ROOT_SCANNED;
  return 1;
}


___HIDDEN void mark_symkey_tables
   ___P((___PSD ___global_state source),
        (___PSV source)
___PSDKR
___global_state source;)
{
  ___PSGET
  ___collector_worker *work = ___ps->collector;

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (work != 0) reference_location = IN_SYMKEY_TABLE;
#endif

  {
    ___SCMOBJ before[2], cells[2];
    ___MUTEX_LOCK(source->mem.global_gate);
    before[0]=cells[0]=source->symbol_table;
    before[1]=cells[1]=source->keyword_table;
    ___MUTEX_UNLOCK(source->mem.global_gate);
    mark_array (work, cells, 2);
    ___MUTEX_LOCK(source->mem.global_gate);
    if (cells[0]!=before[0] && source->symbol_table==before[0])
      source->symbol_table=cells[0];
    if (cells[1]!=before[1] && source->keyword_table==before[1])
      source->keyword_table=cells[1];
    ___MUTEX_UNLOCK(source->mem.global_gate);
  }
}


/* Scan the two actual anchor cells in place. Bucket traversal/weak handling
 * remains with the existing heap algorithm, not this root-entry lease. */
___BOOL ___root_task_scan_symkey(___root_task *task, ___processor_state executor,
                                ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  if (!root_symkey_task(task,executor) ||
      !root_task_matches(task,___ROOT_SYMKEY,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  task->state=___ROOT_SCANNING;
  mark_symkey_tables (___PSP task->origin.source.symkey);
  task->state=___ROOT_SCANNED;
  return 1;
}


/* End internal memory fragment. */
