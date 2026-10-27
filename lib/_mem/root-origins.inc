#line 4689 ___MEM_SOURCE_FILE
___HIDDEN void mark_registers
   ___P((___PSD ___execution_context *source),
        (___PSV source)
___PSDKR
___execution_context *source;)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_REGISTER;
#endif

  mark_array (___PSP source->r, sizeof(source->r)/sizeof(*source->r));
}


___HIDDEN void mark_saved
   ___P((___PSD ___execution_context *source),
        (___PSV source)
___PSDKR
___execution_context *source;)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_SAVED;
#endif

  mark_array (___PSP source->saved, sizeof(source->saved)/sizeof(*source->saved));
}


___HIDDEN void mark_type_cache
   ___P((___PSD ___execution_context *source),
        (___PSV source)
___PSDKR
___execution_context *source;)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_TYPE_CACHE;
#endif

  mark_array (___PSP source->type_cache, sizeof(source->type_cache)/sizeof(*source->type_cache));
}


#line 6503 ___MEM_SOURCE_FILE
___HIDDEN void mark_processor_scmobj
   ___P((___PSD ___execution_context *source),
        (___PSV source)
___PSDKR
___execution_context *source;)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_PROCESSOR_SCMOBJ;
#endif

  mark_array (___PSP
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
  source=task->origin.source.bank;
  task->state=___ROOT_SCANNING;
  mark_registers (___PSP source);
  mark_saved (___PSP source);
  mark_type_cache (___PSP source);
  mark_processor_scmobj (___PSP source);
  task->state=___ROOT_SCANNED;
  return 1;
}


___HIDDEN void mark_vm_scmobj
   ___P((___PSD ___virtual_machine_state source),
        (___PSV source)
___PSDKR
___virtual_machine_state source;)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_VM_SCMOBJ;
#endif

  mark_array (___PSP
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
  mark_vm_scmobj (___PSP task->origin.source.vm);
  task->state=___ROOT_SCANNED;
  return 1;
}


___HIDDEN void mark_global_variables
   ___P((___PSD const ___global_root_source *source),
        (___PSV source)
___PSDKR
const ___global_root_source *source;)
{
  ___PSGET
#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_GLOBAL_VAR;
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
            mark_array (___PSP &glo->val, 1);
            glo = glo->next;
          }
        lo++;
      }
  }
#else
  mark_array (___PSP source->vm->glos+source->lo,source->hi-source->lo);
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

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_SYMKEY_TABLE;
#endif

  mark_array (___PSP &source->symbol_table, 1);
  mark_array (___PSP &source->keyword_table, 1);
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
