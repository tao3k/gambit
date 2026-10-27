#line 6170 ___MEM_SOURCE_FILE
___HIDDEN void move_continuation
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

  ___WORD *start;
  ___SIZE_TS length;
  ___WORD *p1;
  ___WORD *p2;

  start = ___ps->context->fp;
  length = (___ps->context->stack_break + ___FIRST_BREAK_FRAME_SPACE) - start;

  p1 = start + length;
  p2 = alloc_stack_ptr;

  ___ps->context->stack_start = alloc_stack_start;
  ___ps->context->stack_break = p2 - ___FIRST_BREAK_FRAME_SPACE;

  while (p1 != start)
    *--p2 = *--p1;

  alloc_stack_ptr = p2;

  ___FP_SET_STK(alloc_stack_ptr,
                -___FIRST_BREAK_FRAME_STACK_MSECTION,
                ___CAST(___WORD,
                        ___CAST(___msection*,NULL))) /* not a stack section overflow */
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
  occupied_words_still = still;

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

  lower_bound_nb_sections = compute_nb_msections_min(target_processor_count);

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

      upper_bound_nb_sections = target_nb_sections;

      if (___GSTATE->setup_params.max_heap > 0)
        {
          upper_bound_nb_sections =
            ((___GSTATE->setup_params.max_heap >> ___LWS) -
             occupied_words_still) / ___MSECTION_SIZE;

          SET_MAX(target_nb_sections, lower_bound_nb_sections);
          SET_MIN(target_nb_sections, upper_bound_nb_sections);
        }

      /*
       * Check if there was a heap overflow.
       */

      if (overflow) break;

      free_space = compute_free_heap_space_in_msections(target_nb_sections);

      if (free_space <  overflow_reserve)
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
