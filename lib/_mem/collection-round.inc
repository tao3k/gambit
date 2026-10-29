#line 6614 ___MEM_SOURCE_FILE
___HIDDEN void mark_reachable_from_marked
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

#ifndef ___SINGLE_THREADED_VMS

  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);
  ___VOLATILE ___WORD *workers_count = &scan_workers_count[traverse_weak_refs];
  int np = ___vms->processor_count;
  int id = ___PROCESSOR_ID(___ps,___vms); /* id of this processor */
  int i;

 continue_local_scan:

#endif

  do
    {
      scan_still_objs_to_scan (___PSPNC);
      scan_movable_objs_to_scan (___PSPNC);
    } while (___CAST(___WORD*,still_objs_to_scan) != 0);

#ifndef ___SINGLE_THREADED_VMS

#define ___GC_SCAN_STEAL_WORK_CYCLES 1000

  for (;;)
    {
      /* Try stealing a queued chunk from another processor */

      for (i = (np-1) * ___GC_SCAN_STEAL_WORK_CYCLES - 1; i>=0; i--)
        {
          ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID((i + i%(np-1) + 1) % np,___vms);
          ___VOLATILE ___WORD *hcsh;

          if (ps->mem.heap_chunks_to_scan_head_ !=
              ps->mem.heap_chunks_to_scan_tail_)
            {
              /* only try stealing when chunk FIFO is non-empty */

              ___SPINLOCK_LOCK(ps->mem.heap_chunks_to_scan_lock_);

              if ((hcsh=ps->mem.heap_chunks_to_scan_head_) !=
                  ps->mem.heap_chunks_to_scan_tail_)
                {
                  /* chunk FIFO is really non-empty */

                  ___WORD *ptr = ___UNTAG_AS(*hcsh, ___FORW);

                  ps->mem.heap_chunks_to_scan_head_ = ptr;

                  ___SHARED_MEMORY_BARRIER(); /* share heap_chunks_to_scan_head */

                  ___SPINLOCK_UNLOCK(ps->mem.heap_chunks_to_scan_lock_);

                  scan_complete_heap_chunk (___PSP ptr+1);

                  goto continue_local_scan;
                }
              else
                {
                  ___SPINLOCK_UNLOCK(ps->mem.heap_chunks_to_scan_lock_);
                }
            }
        }

      /* Signal being idle and wait for more work or termination */

      ___MUTEX_LOCK(scan_termination_mutex);

      if (--(*workers_count) == 0)
        {
          /* Scan has terminated */

          for (i=np-1; i>=0; i--)
            ___CONDVAR_SIGNAL(scan_termination_condvar);

          ___MUTEX_UNLOCK(scan_termination_mutex);

          break;
        }
      else
        {
          /* Other processors are still actively scanning chunks */

          ___ACTLOG_BEGIN_PS(gc_wait,lightgray);
          ___CONDVAR_WAIT(scan_termination_condvar,scan_termination_mutex);
          ___ACTLOG_END_PS();

          if (*workers_count == 0)
            {
              ___MUTEX_UNLOCK(scan_termination_mutex);
              break;
            }

          (*workers_count)++;

          ___MUTEX_UNLOCK(scan_termination_mutex);
        }
    }

#endif
}


___HIDDEN void garbage_collect_setup_phase
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(setup_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_setup_phase\n");
  BARRIER();
#endif

  /* Assign initial stack and heap msections to each processor */

  if (___PROCESSOR_ID(___ps,___vms) == 0)
    setup_stack_heap_vmstate (___vms);

  /* Create list of externally referenced still objects to trace */

  setup_still_objs_to_scan (___PSPNC);

  /* Account for deferred accounting of still object allocation */

  words_still_objs += words_still_objs_deferred;
  words_still_objs_deferred = 0;

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_mark_strong_phase
   ___P((___PSD ___UWORD rc_epoch),
        (___PSV rc_epoch)
___PSDKR
___UWORD rc_epoch;)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(mark_strong_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_mark_strong_phase\n");
  BARRIER();
#endif

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
    {
      stack_fudge_used = 0;
      heap_fudge_used = 0;
    }
#endif

  /* maintain list of GC hash tables reached by GC */

  reached_gc_hash_tables = 0;

  traverse_weak_refs = 0; /* don't traverse weak references in this phase */

  /* The VM round owns all six source kinds and their complete lifetimes.
   * Source adapters preserve the established scan order and frame rewrites. */
  if (!___root_round_scan(___ps,rc_epoch))
    rc_contract_error("Frozen root union did not complete");

  mark_reachable_from_marked (___PSPNC);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_mark_weak_phase
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

  /*
   * At this point all of the objects accessible from the roots
   * without having to traverse a weak reference have been scanned
   * by the GC.
   */

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(mark_weak_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_mark_weak_phase\n");
  BARRIER();
#endif

  traverse_weak_refs = 1; /* traverse weak references in this phase */

  process_wills (___PSPNC);

  mark_reachable_from_marked (___PSPNC);

  move_continuation (___PSPNC);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_cleanup_phase
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(cleanup_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_cleanup_phase\n");
  BARRIER();
#endif

  process_gc_hash_tables (___PSPNC);

  free_unmarked_still_objs (___PSPNC);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___BOOL ___garbage_collect_pstate
   ___P((___processor_state ___ps,
         ___SIZE_TS requested_words_still),
        (___ps,
         requested_words_still)
___processor_state ___ps;
___SIZE_TS requested_words_still;)
{
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);
  ___BOOL overflow = 0;
  ___UWORD rc_epoch;
  ___F64 user_time_start, sys_time_start, real_time_start;
  ___F64 user_time_end, sys_time_end, real_time_end;
  ___F64 user_time, sys_time, real_time;

#ifndef ___SINGLE_THREADED_VMS
  if (resize_retained(___vms)) return 1; /* VM-local refusal, not a global GC gate */
#endif
  ___ACTLOG_BEGIN_PS(gc,red);

  /* Start measuring GC statistics */

  if (___PROCESSOR_ID(___ps,___vms) == 0)
    {
#ifdef ENABLE_GC_TRACE_PHASES
      ___printf ("----------------------------------------- GC START #%d\n", ___CAST(int,nb_gcs)+1);
#endif
      ___process_times (&user_time_start, &sys_time_start, &real_time_start);
    }

  /* Print debugging info */

#ifdef ___DEBUG_GARBAGE_COLLECT

  {
    int p;
    int np = ___vms->processor_count;
    for (p=0; p<np; p++)
      {
        if (___PROCESSOR_ID(___ps,___vms) == p)
          {
            ___printf ("processor #%d\n", p);
            ___printf ("heap_size          = %d\n", heap_size);
            ___printf ("tospace_offset     = %d\n", ___ps->mem.tospace_offset_);
            ___printf ("___ps->context->stack_start = %p\n", ___ps->context->stack_start);
            ___printf ("___ps->context->stack_break = %p\n", ___ps->context->stack_break);
            ___printf ("___ps->context->fp          = %p\n", ___ps->context->fp);
            ___printf ("___ps->context->stack_limit = %p\n", ___ps->context->stack_limit);
            ___printf ("___ps->heap_limit  = %p\n", ___ps->heap_limit);
            ___printf ("___ps->context->hp          = %p\n", ___ps->context->hp);
          }
        BARRIER();
      }
  }

#endif


  /* Recover processor's stack and heap pointers */

  alloc_stack_ptr = ___ps->context->fp;
  alloc_heap_ptr  = ___ps->context->hp;


  /* Keep track of bytes allocated by this processor */

  bytes_allocated_minus_occupied += bytes_occupied(___ps);

  /* Every source view is complete before the coordinator captures the roster.
   * This collective is also the publication edge for context/frame writes. */
  BARRIER();
  if (___PROCESSOR_ID(___ps,___vms)==0 && !___root_round_begin(___ps))
    rc_contract_error("Frozen root union admission refused");
  BARRIER();
  if (!___root_round_freeze(___ps,&rc_epoch))
    rc_contract_error("Frozen root member admission refused");
  BARRIER();
  if (___PROCESSOR_ID(___ps,___vms)==0 && !___root_round_publish(___ps))
    rc_contract_error("Frozen root union publication refused");

  /* Setup the stacks and heaps of all the processors */

  garbage_collect_setup_phase (___PSPNC);

  BARRIER();


  /* Mark the objects that are reachable strongly */

  garbage_collect_mark_strong_phase (___PSP rc_epoch);

  BARRIER();


  if (___PROCESSOR_ID(___ps,___vms)==0 &&
      !___root_round_finish_scan(___ps))
    rc_contract_error("Frozen root union still owns unfinished sources");

  /* Mark the objects that are reachable weakly */

  garbage_collect_mark_weak_phase (___PSPNC);

  BARRIER();


  /* Process gc hash tables and free unreachable still objects */

  garbage_collect_cleanup_phase (___PSPNC);

  BARRIER();


  /* Resize heap */

  if (___PROCESSOR_ID(___ps,___vms) == 0)
    overflow = resize_heap (___vms, requested_words_still);

  BARRIER();


  /* Guarantee heap fudge */

  if (alloc_heap_ptr > alloc_heap_limit - ___MSECTION_FUDGE)
    next_heap_msection (___ps);


  /* Keep track of bytes allocated by this processor */

  bytes_allocated_minus_occupied -= bytes_occupied(___ps);


  /* Finalize measuring GC statistics */

  if (___PROCESSOR_ID(___ps,___vms) == 0)
    {
      ___process_times (&user_time_end, &sys_time_end, &real_time_end);

      user_time = user_time_end - user_time_start;
      sys_time = sys_time_end - sys_time_start;
      real_time = real_time_end - real_time_start;

      nb_gcs = nb_gcs + 1.0;
      gc_user_time += user_time;
      gc_sys_time += sys_time;
      gc_real_time += real_time;

      latest_gc_user_time = user_time;
      latest_gc_sys_time = sys_time;
      latest_gc_real_time = real_time;

      ___raise_interrupt_pstate (___ps, ___INTR_GC); /* raise gc interrupt */

#ifdef ENABLE_GC_TRACE_PHASES
      ___printf ("----------------------------------------- GC END #%d\n", ___CAST(int,nb_gcs));
#endif
    }

  /* Prepare to continue executing program */

  prepare_mem_pstate (___ps);

  reopen_rc_roots (___ps, rc_epoch);
  BARRIER();
  if (___PROCESSOR_ID(___ps,___vms)==0 && !___root_round_end(___ps))
    rc_contract_error("Frozen root union cannot retire before member restoration");
  BARRIER();


  ___ACTLOG_END_PS();

  return overflow;
}


/* End internal memory fragment. */
