#line 4401 ___MEM_SOURCE_FILE
___HIDDEN ___SIZE_TS max_target_heap_space_in_recent_history
    ___P((___virtual_machine_state ___vms),
         (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  ___SIZE_TS max_target_heap_space = 0;

#if ___TARGET_HEAP_SPACE_HIST_LENGTH > 0

  int i;

  for (i=0; i<___TARGET_HEAP_SPACE_HIST_LENGTH; i++)
    if (target_heap_space_hist[i] > max_target_heap_space)
      max_target_heap_space = target_heap_space_hist[i];

#endif

  return max_target_heap_space;

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


___HIDDEN void add_to_target_heap_space_history
    ___P((___virtual_machine_state ___vms,
          ___SIZE_TS target_heap_space),
         (___vms,
          target_heap_space)
___virtual_machine_state ___vms;
___SIZE_TS target_heap_space;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

#if ___TARGET_HEAP_SPACE_HIST_LENGTH > 0

  target_heap_space_hist_last =
    (target_heap_space_hist_last+1) % ___TARGET_HEAP_SPACE_HIST_LENGTH;

  target_heap_space_hist[target_heap_space_hist_last] = target_heap_space;

#endif

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


___HIDDEN ___SIZE_TS adjust_heap
   ___P((___SIZE_TS live),
        (live)
___SIZE_TS live;)
{
  ___SIZE_TS target_heap_space = live;

  if (___GSTATE->setup_params.adjust_heap_hook != 0)
    target_heap_space = ___GSTATE->setup_params.adjust_heap_hook (live);
  else if (___GSTATE->setup_params.live_percent < 100)
    target_heap_space = live / ___GSTATE->setup_params.live_percent * 100;

  SET_MAX(target_heap_space,
          ___CAST(___SIZE_TS,(___GSTATE->setup_params.min_heap >> ___LWS)));

  return target_heap_space;
}


___HIDDEN void prepare_mem_pstate
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___SIZE_TS avail;
  ___SIZE_TS stack_avail;
  ___SIZE_TS stack_left_before_fudge;
  ___SIZE_TS heap_avail;
  ___SIZE_TS heap_left_before_fudge;

#ifdef ___CALL_GC_FREQUENTLY
  avail = 0;
  ___ps->mem.gc_calls_to_punt_ = 2000;
#else
  avail = compute_free_heap_space_approximately()/2;
  SET_MAX(avail,0);
#endif

  stack_avail = avail/2;
  stack_left_before_fudge = (alloc_stack_ptr - alloc_stack_limit)
                            - ___MSECTION_FUDGE;

  ___ps->context->fp = alloc_stack_ptr;
  ___ps->context->stack_limit = alloc_stack_ptr
                       - ((stack_avail < stack_left_before_fudge)
                          ? stack_avail
                          : stack_left_before_fudge);

  heap_avail = avail - stack_avail;
  heap_left_before_fudge = (alloc_heap_limit - alloc_heap_ptr)
                           - ___MSECTION_FUDGE;

  ___ps->context->hp = alloc_heap_ptr;
  ___ps->heap_limit = alloc_heap_ptr
                      + ((heap_avail < heap_left_before_fudge)
                         ? heap_avail
                         : heap_left_before_fudge);

  /* set stack overflow and interrupt detection limit */

  ___refresh_interrupts_pstate (___ps);

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
    {
      ___WORD *end = ___ps->context->stack_limit;
      ___WORD *start = end - ___MSECTION_FUDGE;
      if (end > alloc_stack_ptr)
        end = alloc_stack_ptr;
      zap_section (start, end);
      if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) == 3)
        {
          ___printf ("heap_size          = %d\n", heap_size);
          ___printf ("avail              = %d\n", avail);
          ___printf ("stack_avail        = %d\n", stack_avail);
          ___printf ("heap_avail         = %d\n", heap_avail);
          ___printf ("stack_msection     = %p\n", stack_msection);
          ___printf ("heap_msection      = %p\n", heap_msection);
          ___printf ("___ps->context->stack_start = %p\n", ___ps->context->stack_start);
          ___printf ("___ps->context->stack_break = %p\n", ___ps->context->stack_break);
          ___printf ("___ps->context->fp          = %p\n", ___ps->context->fp);
          ___printf ("alloc_stack_ptr    = %p\n", alloc_stack_ptr);
          ___printf ("___ps->context->stack_limit = %p\n", ___ps->context->stack_limit);
          ___printf ("alloc_stack_limit  = %p\n", alloc_stack_limit);
          ___printf ("alloc_heap_limit   = %p\n", alloc_heap_limit);
          ___printf ("___ps->heap_limit  = %p\n", ___ps->heap_limit);
          ___printf ("___ps->context->hp          = %p\n", ___ps->context->hp);
          ___printf ("alloc_heap_ptr     = %p\n", alloc_heap_ptr);
          ___printf ("alloc_heap_start   = %p\n", alloc_heap_start);
        }
    }
#endif
}


___SCMOBJ ___setup_mem_pstate
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___virtual_machine_state ___vms = ___VMSTATE_FROM_PSTATE(___ps);
  ___SCMOBJ err;

  /*
   * Setup processor's activity log.
   */

  if ((err = ___setup_actlog_pstate (___ps)) != ___FIX(___NO_ERR))
    return err;

  /*
   * Setup location of tospace.
   */

  tospace_offset = ___PSTATE_FROM_PROCESSOR_ID(0,___vms)->mem.tospace_offset_;

#ifndef ___SINGLE_THREADED_VMS
  ___SPINLOCK_INIT(heap_chunks_to_scan_lock);
#endif

  if (!setup_rc (___ps))
    return ___FIX(___HEAP_OVERFLOW_ERR);

  /*
   * Allocate processor's stack and heap.
   */

  msection_free_list = 0;

  words_prev_msections = 0;

  stack_msection = 0;
  alloc_stack_start = 0;
  alloc_stack_ptr = 0;

  heap_msection = 0;
  alloc_heap_start = 0;
  alloc_heap_ptr = 0;

  next_stack_msection (___ps); /* allocate one msection for stack */
  next_heap_msection (___ps);  /* allocate one msection for local heap */

  /* Setup list of still objects. */

  still_objs = 0;
  words_still_objs = 0;
  words_still_objs_deferred = 0;

  /* Keep track of bytes allocated */

  bytes_allocated_minus_occupied = 0.0;

  /*
   * Setup reference counted memory management.
   */



  /*
   * Create "first break frame" of initial top section.  This first
   * break frame has a null msection link because it is not created
   * due to a stack section overflow (this information is needed by
   * ___stack_overflow_undo_if_possible).
   */

  ___ps->context->stack_start = alloc_stack_start;
  alloc_stack_ptr = alloc_stack_start;

  ___FP_ADJFP(alloc_stack_ptr,___FIRST_BREAK_FRAME_SPACE)

  ___FP_SET_STK(alloc_stack_ptr,
                -___BREAK_FRAME_NEXT,
                ___END_OF_CONT_MARKER) /* no next frame */

  ___FP_SET_STK(alloc_stack_ptr,
                -___FIRST_BREAK_FRAME_STACK_MSECTION,
                ___CAST(___WORD,
                        ___CAST(___msection*,NULL))) /* not a stack section overflow */

  ___ps->context->stack_break = alloc_stack_ptr;

  /*
   * Setup will lists.
   */

  nonexecutable_wills = ___TAG(0,0); /* tagged empty list */
  executable_wills = ___TAG(0,___EXECUTABLE_WILL); /* tagged empty list */

#ifdef ___DEBUG_CTRL_FLOW_HISTORY

  {
    int i;
    ___ps->ctrl_flow_history_index = 0;
    for (i=___CTRL_FLOW_HISTORY_LENGTH-1; i>=0; i--)
      ___ps->ctrl_flow_history[i].line = 0;
  }

#endif

#ifdef ___DEBUG_STACK_LIMIT
  ___ps->poll_location.line = 0;
  ___ps->stack_limit_location.line = 0;
#endif

#ifdef ___DEBUG_HEAP_LIMIT
  ___ps->check_heap_location.line = 0;
  ___ps->heap_limit_location.line = 0;
#endif

#ifdef ___HEARTBEAT_USING_POLL_COUNTDOWN
  ___ps->heartbeat_interval = ___HEARTBEAT_USING_POLL_COUNTDOWN;
  ___ps->heartbeat_countdown = ___ps->heartbeat_interval;
#endif

  prepare_mem_pstate (___ps);

  return err;
}


___SCMOBJ ___setup_mem_vmstate
   ___P((___virtual_machine_state ___vms),
        (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  ___SIZE_TS init_heap_size;
  int init_nb_sections;
  int source;

  /* Fresh VM setup owns every fixed source slot before any PS publication. */
  for (source=0; source<___MAX_PROCESSORS; ++source)
    ___PSTATE_FROM_PROCESSOR_ID(source,___vms)->mem.rc_domain_ = 0;

#ifndef ___SINGLE_THREADED_VMS

  /*
   * Initialize spinlock for VM level memory allocation.
   */

  ___SPINLOCK_INIT(misc_mem_lock);
  ___SPINLOCK_INIT(alloc_mem_lock);

  /*
   * Initialize condition variable to determine end of scan at VM level.
   */

  ___MUTEX_INIT(scan_termination_mutex);
  ___CONDVAR_INIT(scan_termination_condvar);

#endif

#ifndef ___SINGLE_VM

  /*
   * Add to tail of virtual machine circular list.
   */

  ___MUTEX_LOCK(___GSTATE->vm_list_mut);

  {
    ___virtual_machine_state head = &___GSTATE->vmstate0;
    ___virtual_machine_state tail = head->prev;

    ___vms->prev = tail;
    ___vms->next = head;
    head->prev = ___vms;
    tail->next = ___vms;
  }

  ___MUTEX_UNLOCK(___GSTATE->vm_list_mut);

  /* TODO: implement expansion of glos array when number of globals grows beyond 20000 */

  { int n = 20000;
    ___vms->glos = ___CAST(___SCMOBJ*,___ALLOC_MEM(n * sizeof (___SCMOBJ)));
    while (--n>=0) { ___vms->glos[n] = ___UNB1; }
  }

#endif

  /*
   * It is important to initialize the_msections first so
   * that if the program terminates early the procedure
   * ___cleanup_mem_vmstate will not access dangling pointers.
   */

  the_msections = 0;

  /*
   * Setup location of tospace.
   */

  ___PSTATE_FROM_PROCESSOR_ID(0,___vms)->mem.tospace_offset_ = 0;

  /*
   * Set the overflow reserve so that there is 4 times the space for
   * the rest parameter handler to construct the rest parameter list
   * without having to call the garbage collector.
   */

  normal_overflow_reserve = ___DEFAULT_NORMAL_OVERFLOW_RESERVE;
  overflow_reserve = normal_overflow_reserve;

  /* Setup GC statistics */

  nb_gcs = 0.0;
  gc_user_time = 0.0;
  gc_sys_time = 0.0;
  gc_real_time = 0.0;

  latest_gc_real_time = 0.0;
  latest_gc_heap_size = ___CAST(___F64,heap_size) * ___WS;
  latest_gc_live = 0.0;
  latest_gc_movable = 0.0;
  latest_gc_still = 0.0;

  /* No custom msection allocator */

  custom_msection_alloc = 0;

  /* Allocate msections of VM */

  init_heap_size = ___GSTATE->setup_params.min_heap;

  if (___GSTATE->setup_params.max_heap > 0)
    SET_MIN(init_heap_size, ___GSTATE->setup_params.max_heap);

  init_nb_sections = compute_nb_msections_needed(init_heap_size >> ___LWS);

  SET_MAX(init_nb_sections,
          compute_nb_msections_min(___vms->processor_count));

  adjust_msections (&the_msections, init_nb_sections);

  if (the_msections == 0 ||
      the_msections->nb_sections != init_nb_sections)
    return ___FIX(___HEAP_OVERFLOW_ERR);

  occupied_words_movable = 0;
  occupied_words_still = 0;

  nb_msections_assigned = 0;
  nb_msections_stacks   = 0;

#if ___TARGET_HEAP_SPACE_HIST_LENGTH > 0

  {
    int i;

    for (i=0; i<___TARGET_HEAP_SPACE_HIST_LENGTH; i++)
      target_heap_space_hist[i] = 0;

    target_heap_space_hist_last = 0;
  }

#endif

  heap_size = compute_heap_size();

  return ___FIX(___NO_ERR);

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


___SCMOBJ ___setup_mem ___PVOID
{
  if (___GSTATE->setup_params.min_heap == 0)
    {
      /*
       * Choose a reasonable minimum heap size.
       *
       * A fraction of the last level data cache size is probably good.
       */

      ___GSTATE->setup_params.min_heap = ___cpu_cache_size (0, 0) / 2;
    }

  SET_MAX(___GSTATE->setup_params.min_heap, ___DEFAULT_MIN_HEAP);

  if (___GSTATE->setup_params.live_percent <= 0 ||
      ___GSTATE->setup_params.live_percent > 100)
    {
      /*
       * Choose a reasonable minimum live percent.
       */

      ___GSTATE->setup_params.live_percent = ___DEFAULT_LIVE_PERCENT;
    }

  /*
   * Setup psections.
   */

  ___GSTATE->mem.psections = 0;
  ___GSTATE->mem.palloc_ptr = 0;

  /*
   * Create empty global variable list, symbol table and keyword
   * table.
   */

  ___glo_list_setup ();

  {
    ___SCMOBJ t = alloc_symkey_table (___sSYMBOL, INIT_SYMBOL_TABLE_LENGTH);

    if (___FIXNUMP(t))
      return t;

    ___GSTATE->symbol_table = t;
  }

  {
    ___SCMOBJ t = alloc_symkey_table (___sKEYWORD, INIT_KEYWORD_TABLE_LENGTH);

    if (___FIXNUMP(t))
      return t;

    ___GSTATE->keyword_table = t;
  }

  return ___FIX(___NO_ERR);
}


void ___cleanup_mem_pstate
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  if (!___rc_prepare_cleanup (___ps))
    { rc_contract_error ("RC roots or borrows prevent memory cleanup"); return; }
  free_still_objs (___ps);
  cleanup_rc (___ps);
}


void ___cleanup_mem_vmstate
   ___P((___virtual_machine_state ___vms),
        (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

#ifndef ___SINGLE_THREADED_VMS

  /*
   * Destroy spinlock for VM level memory allocation.
   */

  ___SPINLOCK_DESTROY(misc_mem_lock);
  ___SPINLOCK_DESTROY(alloc_mem_lock);

  /*
   * Destroy condition variable to determine end of scan at VM level.
   */

  ___CONDVAR_DESTROY(scan_termination_condvar);
  ___MUTEX_DESTROY(scan_termination_mutex);

#endif

  ___cleanup_mem_pstate (___PSTATE_FROM_PROCESSOR_ID(0,___vms));/*TODO: other processors?*/

  free_msections (&the_msections);

#ifndef ___SINGLE_VM

  /*
   * Remove from virtual machine circular list.
   */

  /* It is assumed that ___GSTATE->vm_list_mut is currently locked */

  {
    ___virtual_machine_state prev = ___vms->prev;
    ___virtual_machine_state next = ___vms->next;

    next->prev = prev;
    prev->next = next;
  }

#endif

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


void ___cleanup_mem ___PVOID
{
  free_psections ();
}


/* End internal memory fragment. */
