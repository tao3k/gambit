#line 6170 ___MEM_SOURCE_FILE
___HIDDEN ___BOOL move_continuation
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);
  int id = ___PROCESSOR_ID(___ps,___vms);
  ___gc_resume_space *r = &___RESUME(___vms,id);
  ___WORD *source_base, *source_past, *dest_base, *dest_past;
  ___SIZE_TS length = 0;
  ___WORD *start;
  ___WORD *p1;
  ___WORD *p2;

  r->copy_admitted = 0;
  if (!___gc_resume_owner_matches(r,___ps) || r->context != ___ps->context)
    { rc_contract_error("Continuation restore has the wrong context"); return 0; }
  if (r->epoch != ___COLLECTION(___vms).epoch)
    { rc_contract_error("Continuation restore has a stale epoch"); return 0; }
  if (___ps->context->fp != r->source_fp ||
      ___ps->context->stack_break != r->source_break)
    { rc_contract_error("Continuation source extent changed after preflight"); return 0; }
  if (!r->source_section || !r->stack_section || stack_msection != r->stack_section)
    { rc_contract_error("Continuation restore lacks its source or destination section"); return 0; }
  source_base = r->source_section->base + r->source_half;
  source_past = source_base + (___MSECTION_SIZE>>1);
  if (!___gc_stack_span_words(source_base, source_past, r->source_fp, r->source_break,
        ___FIRST_BREAK_FRAME_SPACE, &length) || length != r->source_words)
    { rc_contract_error("Continuation source extent leaves its section"); return 0; }
  {
    /* Source identity was captured from the owner's stack_msection_. The
     * carrier's current stack_msection_ is the destination section. */
    section_claim *claim=section_claim_at(r->source_section, r->source_half);
    ___WORD *cell=___gc_stack_first_read_cell(r->source_fp);
    if (claim->stack_state==STACK_ACTIVE && claim->stack_owner!=r->owner)
      { rc_contract_error("Continuation source stack is owned by another carrier"); return 0; }
    if (claim->stack_state!=STACK_ACTIVE || claim->stack_owner!=___ps ||
        r->owner!=___ps || !___gc_stack_cell_inside(r->source_fp, length, cell))
      { rc_contract_error("Continuation source identity does not match its captured stack"); return 0; }
  }
  dest_base = start_of_tospace(r->stack_section);
  dest_past = dest_base + (___MSECTION_SIZE>>1);
  /* The admitted stack floor is the destination lower bound. Exact fit
   * copies every word of that room; one word short copies nothing. */
  if (r->stack_floor == 0 || r->stack_floor != alloc_stack_limit ||
      !___gc_stack_span_fits(dest_base, dest_past, r->stack_floor,
        alloc_stack_ptr, length))
    { rc_contract_error("Continuation copy extent does not fit its destination"); return 0; }

  start = r->source_fp;
  p1 = start + length;
  p2 = alloc_stack_ptr;

  ___ps->context->stack_start = alloc_stack_start;
  ___ps->context->stack_break = p2 - ___FIRST_BREAK_FRAME_SPACE;

  while (p1 != start)
    {
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
      if (p1 == start + 1)
        ___dev_restore_before_final_read(___ps, r->epoch);
#endif
#ifdef ___GC_TEST_BEFORE_FINAL_RESTORE_READ
      if (p1 == start + 1)
        ___GC_TEST_BEFORE_FINAL_RESTORE_READ (p1 - 1);
#endif
      *--p2 = *--p1;
    }

  alloc_stack_ptr = p2;

  /* The copied overflow link belongs to the first break, not the active
   * frame at alloc_stack_ptr.  Restoration replaces its physical ownership
   * just as capture does; use the same canonical first-break projection. */
  ___INVALIDATE_STACK_OVERFLOW_UNDO
  r->copy_admitted = 1;
  return 1;
}


___HIDDEN void determine_occupied_words
   ___P((___virtual_machine_state ___vms),
        (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  /*
   * Compute space occupied by live objects.
   */

  int p;
  int np = ___vms->processor_count;
  ___SIZE_TS movable = 0;
  ___SIZE_TS still = 0;
  ___F64 bytes_allocated = 0.0;

  for (p=0; p<np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p,___vms);

      movable += words_movable_objs(ps);

      still += ps->mem.words_still_objs_;

      /*
       * Note that at this point bytes_allocated_minus_occupied is
       * actually the number of bytes allocated by the processor.
       */

      bytes_allocated += ps->mem.bytes_allocated_minus_occupied_;
    }

  occupied_words_movable = movable;
  occupied_words_still = still + ___lifecycle_retained_words(___vms);

  latest_gc_alloc = bytes_allocated;

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


___HIDDEN ___BOOL resize_heap
   ___P((___virtual_machine_state ___vms,
         ___SIZE_TS requested_words_still),
        (___vms,
         requested_words_still)
___virtual_machine_state ___vms;
___SIZE_TS requested_words_still;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  ___BOOL overflow = 0;
  ___SIZE_TS target_heap_space;
  ___SIZE_TS ths;
  ___SIZE_TS target_movable_space;
  int target_nb_sections;
  int recent_history;
  int lower_bound_nb_sections;
  int upper_bound_nb_sections;
  ___SIZE_TS live;
  ___SIZE_TS free_space;

  /*
   * Compute the space occupied by live objects.
   */

  determine_occupied_words (___vms);

  /*
   * Determine the strict minimum number of msections required after
   * the GC.  The code reserves ___MIN_NB_MSECTIONS_PER_PROCESSOR per
   * processor taking the target number of processors into account in
   * case the GC was called as part of the resizing of the VM.
   */

  lower_bound_nb_sections = compute_nb_msections_min(___vms->processor_count);
#ifndef ___SINGLE_THREADED_VMS
  /* GC owns its current closed cohort; future startup pairs are reserved
   * independently. Never contract away assigned or imminent restore ranges. */
  SET_MAX(lower_bound_nb_sections, nb_msections_assigned+
          ___restore_msections(___vms)+___resume_msections(___vms));
#endif

  SET_MAX(lower_bound_nb_sections,
          (compute_nb_msections_needed(occupied_words_movable) +
           nb_msections_stacks));

  /*
   * Use the recent target heap space history to avoid shrinking the
   * heap size abruptly.
   */

  recent_history = max_target_heap_space_in_recent_history (___vms);

  /*
   * Determine how to resize the heap assuming the requested space is
   * live and no heap overflow happens, but if this would cause a heap
   * overflow then try again after setting requested_words_still to
   * zero and lowering the overflow reserve to make some free space
   * available to handle the heap overflow.
   */

  while (1)
    {
      /*
       * At most 2 iterations are executed. From the first to second
       * iteration, the following variables will change values:
       *
       *   overflow will be 0 at first iteration and 1 at second iteration
       *   overflow_reserve will be lower at second iteration
       *   requested_words_still will be 0 at second iteration
       */

      /* Pretend requested space is live */
      occupied_words_still += requested_words_still;

      live = occupied_words_movable + occupied_words_still;

      /*
       * Determine the size to grow/shrink the heap at the end of the
       * GC, taking into account the resizing policy (live ratio and
       * min/max heap size).
       */

      target_heap_space = adjust_heap (live) + normal_overflow_reserve;

      ths = target_heap_space; /* remember target_heap_space for history */

      SET_MAX(ths, recent_history);

      target_movable_space = ths - occupied_words_still;

      /*
       * Compute the number of msections required after the GC.
       */

      target_nb_sections = compute_nb_msections_needed(target_movable_space) +
                           nb_msections_stacks;

      SET_MAX(target_nb_sections, lower_bound_nb_sections);
      upper_bound_nb_sections = target_nb_sections;

      if (___GSTATE->setup_params.max_heap > 0)
        {
          upper_bound_nb_sections =
            ((___GSTATE->setup_params.max_heap >> ___LWS) -
             occupied_words_still) / ___MSECTION_SIZE;

          SET_MAX(target_nb_sections, lower_bound_nb_sections);
          SET_MIN(target_nb_sections, upper_bound_nb_sections);
#ifndef ___SINGLE_THREADED_VMS
          SET_MAX(target_nb_sections, nb_msections_assigned+___restore_msections(___vms));
#endif
        }

      /*
       * Check if there was a heap overflow.
       */

      if (overflow) break;

      free_space = compute_free_heap_space_in_msections(target_nb_sections);

      if (target_nb_sections > upper_bound_nb_sections || free_space < overflow_reserve)
        {
          /*
           * Trigger a recoverable heap overflow.
           */

          overflow = 1;

          /*
           * Get space from overflow reserve to handle heap overflow.
           */

          overflow_reserve >>= 1; /* make 50% of reserve usable */

          if (overflow_reserve < (normal_overflow_reserve>>2))
            fatal_heap_overflow ();

          /*
           * Stop pretending requested space is live.
           */

          occupied_words_still -= requested_words_still;
          requested_words_still = 0;
        }
      else
        break;
    }

  adjust_msections (&the_msections, target_nb_sections);

  /*
   * Detect heap overflows caused by failure to allocate msections
   * from the C heap. These heap overflows can happen even when a
   * maximum heap size was not set in the runtime options, for example
   * if the virtual memory is exhausted.
   */

  if (the_msections->nb_sections < target_nb_sections)
    {
      /*
       * Trigger a recoverable heap overflow.
       */

      overflow = 1;

      /*
       * Get space from overflow reserve to handle heap overflow.
       */

      overflow_reserve >>= 1; /* make 50% of reserve usable */

      if (overflow_reserve < (normal_overflow_reserve>>2))
        fatal_heap_overflow ();

      /*
       * Stop pretending requested space is live.
       */

      occupied_words_still -= requested_words_still;
      requested_words_still = 0;
    }

  if (!overflow)
    {
      add_to_target_heap_space_history (___vms, target_heap_space);

      free_space = compute_free_heap_space_in_msections(the_msections->nb_sections);

      if (free_space > normal_overflow_reserve)
        {
          /*
           * Now that there is enough free space, reset the overflow
           * reserve to its normal value.
           */

          overflow_reserve = normal_overflow_reserve;
        }
    }

  heap_size = compute_heap_size();

  /*
   * Maintain GC statistics.
   */

  latest_gc_heap_size = ___CAST(___F64,heap_size) * ___WS;

  latest_gc_live = ___CAST(___F64,live) * ___WS;
  latest_gc_movable = ___CAST(___F64,occupied_words_movable) * ___WS;
  latest_gc_still = ___CAST(___F64,occupied_words_still) * ___WS;

  return overflow;

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


/* End internal memory fragment. */
