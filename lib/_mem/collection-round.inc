#line 6614 ___MEM_SOURCE_FILE
___HIDDEN void mark_reachable_from_marked
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps = work->carrier;

#ifndef ___SINGLE_THREADED_VMS

  ___virtual_machine_state ___vms = work->vm;
  ___VOLATILE ___WORD *workers_count = &scan_workers_count[traverse_weak_refs];
  int np = ___COLLECTION(___vms).worker_count;
  int id = work->id; /* id of this processor */
  int i;

 continue_local_scan:

#endif

  do
    {
      scan_still_objs_to_scan (work);
      scan_movable_objs_to_scan (work);
    } while (___CAST(___WORD*,still_objs_to_scan) != 0);

#ifndef ___SINGLE_THREADED_VMS

#define ___GC_SCAN_STEAL_WORK_CYCLES 1000

  for (;;)
    {
      /* Try stealing a queued chunk from another processor */

      for (i = (np-1) * ___GC_SCAN_STEAL_WORK_CYCLES - 1; i>=0; i--)
        {
          ___collector_worker *victim = &___COLLECTORS(___vms)[(id + 1 + i%(np-1)) % np];
          ___WORD *ptr = take_heap_chunk(work,victim);

          if (ptr != 0)
            {
              scan_complete_heap_chunk (work, ptr, 3);
              goto continue_local_scan;
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
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps=work->carrier;
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(setup_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_setup_phase\n");
  /* Physical phase collectives remain in the all-R caller. */
#endif

  /* Physical grants have already been installed and published to all R. */
  { int i; for(i=work->id;i<___COLLECTION(___vms).participant_count;i+=___COLLECTION(___vms).worker_count) {
      ___processor_state source=___PSTATE_FROM_PROCESSOR_ID(i,___vms);
      setup_still_objs_to_scan(work,source);
      source->mem.words_still_objs_+=source->mem.words_still_objs_deferred_;
      source->mem.words_still_objs_deferred_=0;
  } }
#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_mark_strong_phase
   ___P((___collector_worker *work, ___UWORD rc_epoch),
        (work,rc_epoch)
___collector_worker *work;
___UWORD rc_epoch;)
{
  ___processor_state ___ps=work->carrier;
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(mark_strong_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_mark_strong_phase\n");
  /* Physical phase collectives remain in the all-R caller. */
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

  mark_reachable_from_marked (work);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_mark_weak_phase
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps=work->carrier;
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
  /* Physical phase collectives remain in the all-R caller. */
#endif

  traverse_weak_refs = 1; /* traverse weak references in this phase */

  { int i; for(i=work->id;i<___COLLECTION(___vms).participant_count;i+=___COLLECTION(___vms).worker_count)
      process_wills(work,___PSTATE_FROM_PROCESSOR_ID(i,___vms)); }

  mark_reachable_from_marked (work);



#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void garbage_collect_cleanup_phase
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps=work->carrier;
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);

#ifdef ENABLE_GC_ACTLOG_PHASES
  ___ACTLOG_BEGIN_PS(cleanup_phase,_);
#endif

#ifdef ENABLE_GC_TRACE_PHASES
  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___printf ("garbage_collect_cleanup_phase\n");
  /* Physical phase collectives remain in the all-R caller. */
#endif

  process_gc_hash_tables (work);



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
  ___collector_worker *work;
  int worker_id,active_worker;
  ___F64 user_time_start, sys_time_start, real_time_start;
  ___F64 user_time_end, sys_time_end, real_time_end;
  ___F64 user_time, sys_time, real_time;

  if (!___lifecycle_gc_admitted(___ps)) return 1;
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

  BARRIER(); /* publishes the one RootTask/worker assignment */
  if(___PROCESSOR_ID(___ps,___vms)==0)
    ___COLLECTION(___vms).decision=plan_copy_round(___ps);
  BARRIER(); /* acquire the one decision; no parity changed */
  ___COLLECTION(___vms).observed[___PROCESSOR_ID(___ps,___vms)]=1;
  BARRIER(); /* all R observed acceptance/refusal/retention */
  if(___COLLECTION(___vms).decision!=1) {
    if(___COLLECTION(___vms).decision==3)
      rc_contract_error("Unknown planning result retains frozen roots and native buffers");
    if(___PROCESSOR_ID(___ps,___vms)==0 && !___root_round_refuse(___ps))
      rc_contract_error("Known refusal cannot retire an already started root task");
    BARRIER();
    bytes_allocated_minus_occupied-=bytes_occupied(___ps);
    ___ACTLOG_END_PS();return 1;
  }
  if(___PROCESSOR_ID(___ps,___vms)==0) setup_stack_heap_vmstate(___vms);
  BARRIER();
  worker_id=___PROCESSOR_ID(___ps,___vms);
  active_worker=worker_id<___COLLECTION(___vms).worker_count;
  work=&___COLLECTORS(___vms)[worker_id];
  ___ps->collector=active_worker?work:0;
  if(active_worker) garbage_collect_setup_phase(work);
  BARRIER();

  /* Mark the objects that are reachable strongly */

  if(active_worker) garbage_collect_mark_strong_phase(work,rc_epoch);

  BARRIER();


  if (___PROCESSOR_ID(___ps,___vms)==0 &&
      !___root_round_finish_scan(___ps))
    rc_contract_error("Frozen root union still owns unfinished sources");

  /* Mark the objects that are reachable weakly */

  if(active_worker) garbage_collect_mark_weak_phase(work);

  BARRIER();


  /* Weak descendants have drained on all W; each physical owner receives
   * either one exclusive worker tail or its own disjoint empty resume span. */
  if(active_worker) {
    /* A final large-object section has no execution fudge. A counted fresh
     * small grant restores that reserve before physical owner handoff. */
    if(work->arena.large) {
      if(work->local_scan_chunk_!=work->alloc_heap_chunk_start_ ||
         work->scan_ptr_!=work->arena.cursor)
        rc_contract_error("Large tail handoff retains unfinished local scan work");
      *work->arena.cursor++=NULL_CHUNK_LINK;
      require_chunk_transition(work,work->local_scan_chunk_,2,3);
      work->chunks_completed_++;work->local_scan_chunk_=0;
      refill_worker_arena(work);
      require_chunk_transition(work,work->alloc_heap_chunk_start_,0,2);
      work->local_scan_chunk_=work->alloc_heap_chunk_start_;
      work->scan_ptr_=work->arena.cursor;
    }
    if(work->local_scan_chunk_!=work->alloc_heap_chunk_start_ ||
       work->scan_ptr_!=work->arena.cursor || work->heap_chunks_to_scan_head_!=work->heap_chunks_to_scan_tail_)
      rc_contract_error("Restoration cannot retire unfinished scan transport");
    require_chunk_transition(work,work->local_scan_chunk_,2,3);
    work->chunks_completed_++;work->local_scan_chunk_=0;
    if(!___gc_arena_handoff(&work->arena,&___RESUME(___vms,worker_id),rc_epoch))
      rc_contract_error("Collector tail handoff lacks drained ownership");
  } else if(!___gc_resume_without_arena(&___RESUME(___vms,worker_id),rc_epoch))
    rc_contract_error("Context restoration lacks its physical grant");
  move_continuation(___PSPNC);
  ___RESUME(___vms,worker_id).restored=1;
  BARRIER();
  /* Process gc hash tables and free unreachable still objects */

  if(active_worker) garbage_collect_cleanup_phase(work);
  free_unmarked_still_objs(___PSPNC);
  BARRIER();
  ___ps->collector=0;

  BARRIER();


  /* Resize heap */

  if (___PROCESSOR_ID(___ps,___vms) == 0)
    ___COLLECTION(___vms).overflow = resize_heap (___vms, requested_words_still);

  BARRIER();


  overflow=___COLLECTION(___vms).overflow;

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
