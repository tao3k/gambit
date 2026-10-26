#line 6503 ___MEM_SOURCE_FILE
___HIDDEN void mark_processor_scmobj
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_PROCESSOR_SCMOBJ;
#endif

  mark_array (___PSP
              ___BODY0_AS(___PROCESSOR_SCMOBJ(___ps),___tSUBTYPED),
              ___PROCESSOR_SIZE);
}


___HIDDEN void mark_vm_scmobj
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_VM_SCMOBJ;
#endif

  mark_array (___PSP
              ___BODY0_AS(___VM_SCMOBJ(___vms),___tSUBTYPED),
              ___VM_SIZE);
}


___HIDDEN void mark_global_variables
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);
  int id = ___PROCESSOR_ID(___ps,___vms); /* id of this processor */

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_GLOBAL_VAR;
#endif

  /*
   * Mark a portion of the global variables.
   */

#ifdef ___SINGLE_VM

  {
    int np = ___vms->processor_count;
    int lo = (id * ___GLO_SUBLIST_COUNT) / np;
    int hi = ((id+1) * ___GLO_SUBLIST_COUNT) / np;

    while (lo < hi)
      {
        ___glo_sublist_struct *sl = &___GSTATE->mem.glo_list.sublist[lo];
        ___glo_struct *glo = sl->head;

        while (glo != 0)
          {
#ifdef ___DEBUG_GARBAGE_COLLECT_globals
            print_global_var_name (glo);
            ___printf ("\n");
#endif
            mark_array (___PSP &___GLOCELL(glo->val), 1);
            glo = glo->next;
          }

        lo++;
      }
  }

#else

  {
    int n = ___GSTATE->mem.glo_list.count;
    int np = ___vms->processor_count;
    int lo = (id * n) / np;
    int hi = ((id+1) * n) / np;

    mark_array (___PSP
                ___VMSTATE_FROM_PSTATE(___ps)->glos+lo,
                hi-lo);
  }

#endif
}


___HIDDEN void mark_symkey_tables
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_SYMKEY_TABLE;
#endif

  mark_array (___PSP &___GSTATE->symbol_table, 1);
  mark_array (___PSP &___GSTATE->keyword_table, 1);
}


/* End internal memory fragment. */
