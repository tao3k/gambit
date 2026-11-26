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

#define ___GC_SCAN_STEAL_WORK_CYCLES 16

  if (np <= 1)
    return;

  for (;;)
    {
      /* Try stealing a queued chunk from another processor */

      int cycle;
      for (cycle = ___GC_SCAN_STEAL_WORK_CYCLES; cycle > 0; cycle--)
        {
          for (i = 1; i < np; i++)
            {
              ___collector_worker *victim = &___COLLECTORS(___vms)[(id + i) % np];
              ___WORD *ptr = take_heap_chunk(work,victim);

              if (ptr != 0)
                {
                  scan_complete_heap_chunk (work, ptr, 3);
                  goto continue_local_scan;
                }
            }
          ___CPU_RELAX();
        }

      /* Signal being idle and wait for more work or termination */

      ___MUTEX_LOCK(scan_termination_mutex);

      {
        ___WORD rem = ___WORD_LOAD_ACQUIRE(workers_count) - 1;
        ___WORD_STORE_RELEASE(workers_count, rem);

        if (rem == 0)
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

            rem = ___WORD_LOAD_ACQUIRE(workers_count);
            if (rem == 0)
              {
                ___MUTEX_UNLOCK(scan_termination_mutex);
                break;
              }

            ___WORD_STORE_RELEASE(workers_count, rem + 1);

            ___MUTEX_UNLOCK(scan_termination_mutex);
          }
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
      setup_still_objs_to_scan(work, source, ___COLLECTION(___vms).is_minor);
      source->mem.words_still_objs_deferred_=0;
      source->mem.still_words_budget_=0;
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

  if (___COLLECTION(___vms).is_minor)
    scan_remembered_set(work);

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
  int proc_id, worker_idx, active_worker;
  int coord_id = ___sync_coordinator_id(___vms);
  int is_coord;
  ___F64 user_time_start, sys_time_start, real_time_start;
  ___F64 user_time_end, sys_time_end, real_time_end;
  ___F64 user_time, sys_time, real_time;

  proc_id = ___PROCESSOR_ID(___ps, ___vms);
  is_coord = (proc_id == coord_id);

  if (!___lifecycle_gc_admitted(___ps)) {
    /* Native foreign release callbacks have no running Scheme activation and
     * must neither enter a collective nor mutate execution hp. */
    if (___vms->lifecycle && proc_id >= 0 && proc_id < ___vms->processor_count &&
        (___vms->lifecycle->cleanup[proc_id].draining ||
         ___vms->lifecycle->cleanup[proc_id].uncertain))
      return 1;
    /* Ordinary compilation is not a closed binding context. An unlimited
     * heap continues on a new section instead of raising heap overflow. */
    if (___GSTATE->setup_params.max_heap==0 &&
        ___heap_continue_on_free_section(___ps))
      return 0;
    return 1;
  }
  ___ACTLOG_BEGIN_PS(gc,red);

  /* Start measuring GC statistics */

  if (is_coord)
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
        if (proc_id == p)
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

  /* Coordinator proxies pointer recovery & allocation accounting for parked FFI processors. */
  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___sync_processor_active(___vms, k))
          {
            ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(k, ___vms);
            pps->mem.alloc_stack_ptr_ = pps->context->fp;
            pps->mem.alloc_heap_ptr_  = pps->context->hp;
            pps->mem.bytes_allocated_minus_occupied_ += bytes_occupied(pps);
          }
    }

  /* Every source view is complete before the coordinator captures the roster.
   * This collective is also the publication edge for context/frame writes. */
  BARRIER();
  if (is_coord && !___root_round_begin(___ps))
    rc_contract_error("Frozen root union admission refused");
  BARRIER();
  if (!___root_round_freeze(___ps,&rc_epoch))
    rc_contract_error("Frozen root member admission refused");
  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___sync_processor_active(___vms, k))
          {
            ___UWORD parked_epoch = 0;
            if (!___root_round_freeze_parked(___ps, ___PSTATE_FROM_PROCESSOR_ID(k, ___vms), &parked_epoch))
              rc_contract_error("Frozen root parked member admission refused");
          }
    }
  REST_OBS(REST_GC_BEGIN,___ps,0,0,rc_epoch,
           ___VMSTATE_FROM_PSTATE(___ps),___ps->context->fp,
           ___COLLECTION(___vms).epoch,0,0,0,0,0);
#ifdef ___GAMBIT_REST_OBSERVATION
  ___rest_observation_note_gc((uint64_t)___VMSTATE_FROM_PSTATE(___ps),
    (uint64_t)___ps->mem.rc_domain_,(uint64_t)rc_epoch);
#endif
#ifdef ___GAMBIT_REST_OBSERVATION
  rest_observation_emit_parent(1,___ps->context->fp,(uint64_t)rc_epoch,
    ___COLLECTION(___vms).epoch);
#endif
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_alloc_expire(___ps, rc_epoch);
#endif
  BARRIER();
  if (is_coord)
    {
      if (!___root_round_publish(___ps))
        rc_contract_error("Frozen root union publication refused");
#if defined(___GC_SLOT_TEST_FROZEN) != defined(___GC_SLOT_TEST_REPAIRED)
#error "GC slot observation requires both test cuts"
#endif
#ifdef ___GC_SLOT_TEST_FROZEN
      /* Only the coordinator can plan from here. The other members stay at
       * the decision barrier. No forwarding or parity flip has started. */
      ___GC_SLOT_TEST_FROZEN(___ps,rc_epoch);
#endif
      ___COLLECTION(___vms).decision=plan_copy_round(___ps, requested_words_still);
    }
  BARRIER(); /* acquire the one decision & published RootTask/worker assignment */
  ___COLLECTION(___vms).observed[proc_id]=1;
  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___COLLECTION(___vms).active[k])
          ___COLLECTION(___vms).observed[k] = 1;
    }
  BARRIER(); /* all R observed acceptance/refusal/retention */
  if(___COLLECTION(___vms).decision!=1) {
    if(___COLLECTION(___vms).decision==3)
      rc_contract_error("Unknown planning result retains frozen roots and native buffers");
    if(is_coord && !___root_round_refuse(___ps))
      rc_contract_error("Known refusal cannot retire an already started root task");
    BARRIER();
    /* A refused plan did not mark, so occupied sections stay. When the refusal
     * is not an invalid worker/configuration request and no byte cap is active,
     * grow the reserved pool and let the mutator retry. An invalid request must
     * remain an explicit refusal/overflow without mutating the section pool. */
    if(is_coord) {
      ___gc_round *g=&___COLLECTION(___vms);
      ___WORD req=___WORD_LOAD_ACQUIRE(&g->requested_workers);
      int n=___ROOT_UNION(___vms)->participants;
      int w=g->worker_count;
      int invalid_request=(custom_msection_alloc || w<1 || w>n || req<0 || req>n);
      if(!invalid_request && the_msections &&
         ___GSTATE->setup_params.max_heap==0) {
        int before=the_msections->nb_sections;
        int add=before/2;
        if(add<32) add=32;
        if(before>0 && add<=INT_MAX-before)
          adjust_msections(&the_msections, before+add);
        heap_size=compute_heap_size();
        /* The reserve can exceed two new sections, so the approximate free
         * space stays negative. Added sections are still usable. */
        g->overflow=the_msections->nb_sections>before?0:1;
      } else
        g->overflow=1;
    }
    BARRIER();
    bytes_allocated_minus_occupied-=bytes_occupied(___ps);
    if (is_coord)
      {
        int k;
        for (k = 0; k < ___vms->processor_count; k++)
          if (!___COLLECTION(___vms).active[k])
            {
              ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(k, ___vms);
              pps->mem.bytes_allocated_minus_occupied_ -= bytes_occupied(pps);
            }
      }
    ___ACTLOG_END_PS();
    {
      int shared_overflow = ___COLLECTION(___vms).overflow ? 1 : 0;
      int movable_resumed =
        ___GSTATE->setup_params.max_heap==0 && shared_overflow==0;
      int still_charged = 0;
      /* Plan refusal never enters resize_heap, so a positive still request
       * has no charge yet. Pool growth is not that reservation. */
      if (requested_words_still>0 && shared_overflow==0) {
        ALLOC_MEM_LOCK();
        occupied_words_still += requested_words_still;
        ALLOC_MEM_UNLOCK();
        still_charged = 1;
      }
      {
        int caller_overflow;
        if (requested_words_still>0)
          caller_overflow=___gc_caller_overflow(shared_overflow,movable_resumed,
                                                (unsigned long)requested_words_still,
                                                still_charged);
        else if (movable_resumed)
          caller_overflow=0;
        else
          caller_overflow=shared_overflow ||
            (compute_free_heap_space_approximately()<___MSECTION_SIZE);
        return caller_overflow;
      }
    }
  }
  if(is_coord) setup_stack_heap_vmstate(___vms);
  BARRIER();
  worker_idx=___COLLECTION(___vms).proc_worker[proc_id];
  active_worker=(worker_idx>=0);
  work=active_worker?&___COLLECTORS(___vms)[worker_idx]:0;
  ___ps->collector=work;
  if (!___COLLECTION(___vms).is_minor || ___COLLECTION(___vms).has_young_still)
    {
      if(active_worker) garbage_collect_setup_phase(work);
      BARRIER();
    }

  /* Mark the objects that are reachable strongly */

  if(active_worker) garbage_collect_mark_strong_phase(work,rc_epoch);

  BARRIER();


  if (is_coord &&
      !___root_round_finish_scan(___ps))
    rc_contract_error("Frozen root union still owns unfinished sources");

  /* Mark the objects that are reachable weakly (skipped in O(1) when no wills exist) */

  if (___COLLECTION(___vms).has_wills)
    {
      if(active_worker) garbage_collect_mark_weak_phase(work);
      BARRIER();
    }


#ifdef ___GC_SLOT_TEST_REPAIRED
  /* The strong and weak scans have drained. Keep every member out of
   * continuation restoration and reclamation until the observer returns.
   * The test callbacks may inspect held slots but must not call Scheme,
   * allocate managed objects or wait for a member at this barrier. */
  if (is_coord)
    ___GC_SLOT_TEST_REPAIRED(___ps,rc_epoch);
  BARRIER();
#endif

  /* Weak descendants have drained on all W; each physical owner receives
   * either one exclusive worker tail, a fresh segregated young heap, or its
   * own disjoint empty resume span. */
  if (!___gc_resume_owner_matches(&___RESUME(___vms,proc_id),___ps))
    rc_contract_error("Restoration grant no longer belongs to its processor context");
  if (___COLLECTION(___vms).is_minor || ___COLLECTION(___vms).segregate_mature)
    {
      ___gc_round *g = &___COLLECTION(___vms);
      if (active_worker)
        {
          if (work->local_scan_chunk_ != work->alloc_heap_chunk_start_ ||
              work->scan_ptr_ != work->arena.cursor ||
              work->heap_chunks_to_scan_head_ != work->heap_chunks_to_scan_tail_)
            rc_contract_error("Restoration cannot retire unfinished scan transport");
          require_chunk_transition(work, work->local_scan_chunk_, 2, 3);
          work->chunks_completed_++;
          work->local_scan_chunk_ = 0;
          if (work->arena.section != 0)
            {
              ___msection *asec = work->arena.section;
              ___WORD *hbase = asec->base + asec->gc_dest_offset;
              if (asec->gc_is_dest == 2)
                {
                  ___WORD *pstart = hbase + g->promo_tail_starts[work->id];
                  asec->gc_dest_words = (work->arena.cursor > pstart + 1)
                    ? (work->arena.cursor - hbase)
                    : asec->mature_words;
                }
              else
                {
                  asec->gc_dest_words = work->arena.cursor - hbase;
                }
            }
          work->arena.handed_off = 1;
        }
      if (g->young_heap_secs[proc_id] != 0)
        {
          set_heap_msection(___ps, g->young_heap_secs[proc_id]);
          alloc_stack_limit = ___RESUME(___vms, proc_id).stack_floor;
          ___RESUME(___vms, proc_id).accepted = 1;
        }
      else
        {
          ___RESUME(___vms, proc_id).source_worker = -1;
          if (!___gc_resume_without_arena(&___RESUME(___vms, proc_id), rc_epoch))
            rc_contract_error("Segregated context restoration lacks its physical grant");
        }
    }
  else
    {
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
        if(!___gc_arena_handoff(&work->arena,&___RESUME(___vms,proc_id),rc_epoch))
          rc_contract_error("Collector tail handoff lacks drained ownership");
      } else if(!___gc_resume_without_arena(&___RESUME(___vms,proc_id),rc_epoch))
        rc_contract_error("Context restoration lacks its physical grant");
    }
  if (!current_heap_interval_matches(___ps,alloc_heap_ptr))
    rc_contract_error("Restoration heap interval leaves its destination section");
  section_claim_at(heap_msection,tospace_offset)->heap_used=1;
  move_continuation(___PSPNC);
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_after_reader(___ps, rc_epoch);
#endif
  if (___RESUME(___vms,proc_id).copy_admitted)
    ___RESUME(___vms,proc_id).restored=1;
  else
    rc_contract_error("Restored publication requires an admitted continuation copy");
  if (is_coord)
    {
      int k;
      ___gc_round *g = &___COLLECTION(___vms);
      for (k = 0; k < ___vms->processor_count; k++)
        if (!g->active[k])
          {
            ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(k, ___vms);
            if (!___gc_resume_owner_matches(&___RESUME(___vms, k), pps))
              rc_contract_error("Restoration grant no longer belongs to its parked processor context");
            if ((g->is_minor || g->segregate_mature) && g->young_heap_secs[k] != 0)
              {
                set_heap_msection(pps, g->young_heap_secs[k]);
                pps->mem.alloc_stack_limit_ = ___RESUME(___vms, k).stack_floor;
                ___RESUME(___vms, k).accepted = 1;
              }
            else if (!___gc_resume_without_arena(&___RESUME(___vms, k), rc_epoch))
              rc_contract_error("Parked context restoration lacks its physical grant");
            if (!current_heap_interval_matches(pps, pps->mem.alloc_heap_ptr_))
              rc_contract_error("Parked restoration heap interval leaves its destination section");
            section_claim_at(pps->mem.heap_msection_, pps->mem.tospace_offset_)->heap_used = 1;
            move_continuation(___PSANC(pps));
            if (___RESUME(___vms, k).copy_admitted)
              ___RESUME(___vms, k).restored = 1;
            else
              rc_contract_error("Parked restored publication requires an admitted continuation copy");
          }
    }
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  if (!___dev_restore_before_barrier(___ps, rc_epoch))
#endif
  BARRIER();
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_after_barrier(___ps, rc_epoch);
#endif
  /* Process gc hash tables before any processor frees unreachable still objects
   * (prevents cross-worker UAF when a weak table holds a dead still object). */

  if(active_worker) garbage_collect_cleanup_phase(work);
  BARRIER();
  if (!___COLLECTION(___vms).is_minor)
    {
      free_unmarked_still_objs(___PSPNC);
      if (is_coord)
        {
          int k;
          for (k = 0; k < ___vms->processor_count; k++)
            if (!___COLLECTION(___vms).active[k])
              free_unmarked_still_objs(___PSANC(___PSTATE_FROM_PROCESSOR_ID(k, ___vms)));
        }
    }
  else if (___COLLECTION(___vms).has_young_still)
    {
      sweep_young_still_objs(___PSPNC);
      if (is_coord)
        {
          int k;
          for (k = 0; k < ___vms->processor_count; k++)
            if (!___COLLECTION(___vms).active[k])
              sweep_young_still_objs(___PSANC(___PSTATE_FROM_PROCESSOR_ID(k, ___vms)));
        }
    }
  ___ps->collector=0;
  ___RESUME(___vms,proc_id).source_drained=1;
  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___COLLECTION(___vms).active[k])
          {
            ___PSTATE_FROM_PROCESSOR_ID(k, ___vms)->collector = 0;
            ___RESUME(___vms, k).source_drained = 1;
          }
    }

  BARRIER();


  /* Restoration and still/weak cleanup are past their old-space reads.
   * Mutators stay stopped. Retire source claims, finalize mature/young
   * section partitions, and resize the heap. */
  if (is_coord &&
      !retire_drained_source_claims(___ROOT_UNION(___vms),the_msections,rc_epoch))
    rc_contract_error("Physical source retirement lacks a drained member");

  if (is_coord)
    finalize_gc_sections(___vms);

  /* Resize heap */

  if (is_coord)
    ___COLLECTION(___vms).overflow = resize_heap (___vms, requested_words_still);

  BARRIER();


  overflow=___COLLECTION(___vms).overflow;

  /* Guarantee heap fudge */

  if (!current_heap_interval_matches(___ps,alloc_heap_ptr))
    rc_contract_error("Restoration heap interval changed before refill");
  if (___gc_resume_heap_needs_refill(alloc_heap_ptr,alloc_heap_limit,___MSECTION_FUDGE))
    next_heap_msection (___ps);
  /* Refill must leave the same reserve prepare_mem_pstate subtracts. Six is
   * the witnessed thread-join closure, not a census of every first write. */
  if (!current_heap_interval_matches(___ps,alloc_heap_ptr) ||
      !___gc_published_reserve_fits(alloc_heap_ptr,alloc_heap_limit,___MSECTION_FUDGE,6))
    rc_contract_error("Restoration publication lacks the fudge reserve for a first closure");


  /* Keep track of bytes allocated by this processor */

  bytes_allocated_minus_occupied -= bytes_occupied(___ps);

  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___COLLECTION(___vms).active[k])
          {
            ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(k, ___vms);
            if (!current_heap_interval_matches(pps, pps->mem.alloc_heap_ptr_))
              rc_contract_error("Parked restoration heap interval changed before refill");
            if (___gc_resume_heap_needs_refill(pps->mem.alloc_heap_ptr_, pps->mem.alloc_heap_limit_, ___MSECTION_FUDGE))
              next_heap_msection(pps);
            if (!current_heap_interval_matches(pps, pps->mem.alloc_heap_ptr_) ||
                !___gc_published_reserve_fits(pps->mem.alloc_heap_ptr_, pps->mem.alloc_heap_limit_, ___MSECTION_FUDGE, 6))
              rc_contract_error("Parked restoration publication lacks the fudge reserve for a first closure");
            pps->mem.bytes_allocated_minus_occupied_ -= bytes_occupied(pps);
          }
    }


  /* Finalize measuring GC statistics */

  if (is_coord)
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

      if (___COLLECTION(___vms).is_minor)
        {
          int wi;
          ___SIZE_TS promoted = 0;
          for (wi = 0; wi < ___COLLECTION(___vms).worker_count; wi++)
            promoted += ___COLLECTORS(___vms)[wi].copied_words;
          ___vms->mem.nb_minor_gcs_ += 1.0;
          ___vms->mem.minor_gc_real_time_ += real_time;
          ___vms->mem.minor_promoted_words_ += promoted;
        }
      else
        {
          ___vms->mem.nb_major_gcs_ += 1.0;
          ___vms->mem.major_gc_real_time_ += real_time;
        }

      ___raise_interrupt_pstate (___ps, ___INTR_GC); /* raise gc interrupt */

#ifdef ENABLE_GC_TRACE_PHASES
      ___printf ("----------------------------------------- GC END #%d\n", ___CAST(int,nb_gcs));
#endif
    }

  /* Prepare to continue executing program */

  prepare_mem_pstate (___ps);
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_alloc_arm(___ps, rc_epoch);
#endif

  reopen_rc_roots (___ps, rc_epoch);
  if (is_coord)
    {
      int k;
      for (k = 0; k < ___vms->processor_count; k++)
        if (!___COLLECTION(___vms).active[k])
          {
            ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(k, ___vms);
            prepare_mem_pstate(pps);
            reopen_rc_roots(pps, rc_epoch);
          }
    }
  BARRIER();
  if (is_coord && !___root_round_end(___ps))
    rc_contract_error("Frozen root union cannot retire before member restoration");
  BARRIER();


  ___ACTLOG_END_PS();

  /* Movable resume and the still reservation are decoded separately.
   * resize_heap keeps a positive charge only when it returns success.
   * A later rearm cannot recreate a charge that resize already withdrew. */
  {
    int shared_overflow = overflow ? 1 : 0;
    int movable_resumed = 0;
    int still_charged = 0;
    if (___GSTATE->setup_params.max_heap==0 &&
        ___heap_rearm_after_collection(___ps))
      movable_resumed = 1;
    if (requested_words_still>0 && shared_overflow==0) {
      if (is_coord)
        still_charged = 1;
      else {
        ALLOC_MEM_LOCK();
        occupied_words_still += requested_words_still;
        ALLOC_MEM_UNLOCK();
        still_charged = 1;
      }
    }
    overflow = ___gc_caller_overflow(shared_overflow,movable_resumed,
                                     (unsigned long)requested_words_still,
                                     still_charged);
  }

  REST_OBS(REST_GC_END,___ps,0,0,rc_epoch,
           ___VMSTATE_FROM_PSTATE(___ps),___ps->context->fp,overflow,
           ___COLLECTION(___vms).epoch,0,0,0,0);
#ifdef ___GAMBIT_REST_OBSERVATION
  rest_observation_emit_parent(2,___ps->context->fp,(uint64_t)rc_epoch,
    ___COLLECTION(___vms).epoch);
#endif
  return overflow;
}


/* End internal memory fragment. */
