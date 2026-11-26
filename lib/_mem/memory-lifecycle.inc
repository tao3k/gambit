#line 4401 ___MEM_SOURCE_FILE
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


#ifndef ___GC_ADAPTIVE_SIZING
#define ___GC_ADAPTIVE_SIZING 1
#endif

/* CBMC-verified hardware-adaptive large-heap live_percent damping
 * (dev/refactoring/modern-c/models/cbmc/adaptive_heap_scaling_pso.c):
 * honors explicit -:l<N> / ___set_live_percent verbatim; otherwise keeps
 * 50% on small/medium heaps (<= soft_budget/8) and smoothly ramps up to 80%
 * as live heap approaches soft_budget/2 (soft_budget = RAM / max(2, CPUs),
 * clamped by max_heap). */
___HIDDEN int gc_adaptive_live_percent
   (___SIZE_TS live_words,
    int explicit_flag,
    int configured_pct,
    ___SIZE_T max_heap_bytes)
{
#if ___GC_ADAPTIVE_SIZING && defined(___USE_MMAP_MSECTIONS)
  uint64_t phys_mem_bytes, cpu_count, live_bytes, ram_mib, cap_mib;
  uint32_t eff_cpus, soft_mib, live_mib, lo, hi, span, delta, extra;
  if (explicit_flag || configured_pct != ___DEFAULT_LIVE_PERCENT || live_words <= 0)
    return configured_pct;
  phys_mem_bytes = (uint64_t)msection_os_phys_memory_bytes();
  cpu_count = (uint64_t)msection_os_cpu_count();
  if (phys_mem_bytes == 0u && max_heap_bytes == 0u)
    return configured_pct;
  eff_cpus = (cpu_count >= 2u) ? (uint32_t)((cpu_count > 1024u) ? 1024u : cpu_count) : 2u;
  ram_mib = phys_mem_bytes >> 20;
  cap_mib = ((uint64_t)max_heap_bytes) >> 20;
  if (ram_mib > (uint64_t)0xffffffffu) ram_mib = (uint64_t)0xffffffffu;
  if (cap_mib > (uint64_t)0xffffffffu) cap_mib = (uint64_t)0xffffffffu;
  soft_mib = (ram_mib > 0u) ? ((uint32_t)ram_mib / eff_cpus) : (uint32_t)cap_mib;
  if (cap_mib > 0u && (uint32_t)cap_mib < soft_mib)
    soft_mib = (uint32_t)cap_mib;
  live_bytes = ((uint64_t)live_words) << ___LWS;
  live_mib = ((live_bytes >> 20) > (uint64_t)0xffffffffu)
               ? (uint32_t)0xffffffffu
               : (uint32_t)(live_bytes >> 20);
  lo = soft_mib >> 3;
  hi = soft_mib >> 1;
  if (hi <= lo || live_mib <= lo)
    return 50;
  if (live_mib >= hi)
    return 80;
  span = hi - lo;
  delta = live_mib - lo;
  extra = (delta <= (0xffffffffu / 30u)) ? ((delta * 30u) / span) : ((delta / span) * 30u);
  if (extra > 30u) extra = 30u;
  return 50 + (int)extra;
#else
  (void)live_words;
  (void)explicit_flag;
  (void)max_heap_bytes;
  return configured_pct;
#endif
}

___HIDDEN ___SIZE_TS adjust_heap
   ___P((___SIZE_TS live),
        (live)
___SIZE_TS live;)
{
  ___SIZE_TS target_heap_space = live;

  if (___GSTATE->setup_params.adjust_heap_hook != 0)
    target_heap_space = ___GSTATE->setup_params.adjust_heap_hook (live);
  else
    {
      int eff_pct = gc_adaptive_live_percent
        (live,
         ___live_percent_is_explicit(),
         ___GSTATE->setup_params.live_percent,
         ___GSTATE->setup_params.max_heap);
      if (eff_pct > 0 && eff_pct < 100)
        target_heap_space = live / eff_pct * 100;
    }

  SET_MAX(target_heap_space,
          ___CAST(___SIZE_TS,(___GSTATE->setup_params.min_heap >> ___LWS)));

  return target_heap_space;
}


___HIDDEN void clear_fast_span
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  if (!___ps) return;
  ___ps->stack_fast_floor_b = 0;
  ___ps->stack_fast_limit_b = 0;
  ___ps->heap_fast_lo_b = 0;
  ___ps->heap_fast_bytes = 0;
}

___HIDDEN void publish_fast_span
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___WORD *lo = 0, *hi = 0;
  if (!___ps) return;
  if (___ps->group_demand_active)
    {
      clear_fast_span(___ps);
      return;
    }
  if (___owned_stack_span(___ps, &lo, &hi) && lo != 0 &&
      (___SIZE_TS)(hi - lo) > (___SIZE_TS)___MSECTION_FUDGE &&
      ___CAST(___UWORD, hi) < ~(___UWORD)0)
    {
      ___WORD *floor = lo + ___MSECTION_FUDGE;
      ___ps->stack_fast_floor_b = ___CAST(___UWORD, floor);
      ___ps->stack_fast_limit_b = ___CAST(___UWORD, hi) - ___CAST(___UWORD, floor) + 1;
    }
  else
    {
      ___ps->stack_fast_floor_b = 0;
      ___ps->stack_fast_limit_b = 0;
    }
  ___ps->heap_fast_lo_b = 0;
  ___ps->heap_fast_bytes = 0;
  if (heap_msection &&
      section_claim_at(heap_msection, tospace_offset)->heap_used &&
      alloc_heap_start && alloc_heap_limit && ___ps->heap_limit &&
      ___ps->heap_limit > alloc_heap_start &&
      ___CAST(___UWORD, ___ps->heap_limit) < ~(___UWORD)0)
    {
      ___WORD *end = alloc_heap_limit;
      int shared_ok = 1;
      if (heap_msection == stack_msection)
        {
          if (alloc_stack_limit && alloc_stack_limit < end)
            end = alloc_stack_limit;
          if (___ps->stack_fast_limit_b == 0 ||
              ___CAST(___UWORD, ___ps->heap_limit) > ___ps->stack_fast_floor_b)
            shared_ok = 0;
        }
      if (shared_ok && ___ps->heap_limit <= end)
        {
          ___ps->heap_fast_lo_b = ___CAST(___UWORD, alloc_heap_start);
          ___ps->heap_fast_bytes = ___CAST(___UWORD, ___ps->heap_limit) - ___CAST(___UWORD, alloc_heap_start);
        }
    }
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
  {
    ___SIZE_TS free_approx = compute_free_heap_space_approximately();
    int np = ___VMSTATE_FROM_PSTATE(___ps)->processor_count;
    int div = (np <= 1) ? 2 : (np + 1);
    if (div > 8) div = 8;
    avail = (free_approx > 0) ? (free_approx / div) : 0;
  }
  SET_MAX(avail,0);
#endif

  stack_avail = avail/2;
  {
    ___PTRDIFF_T room = alloc_stack_ptr - alloc_stack_limit;
    stack_left_before_fudge =
      room > (___PTRDIFF_T)___MSECTION_FUDGE
      ? (___SIZE_TS)(room - (___PTRDIFF_T)___MSECTION_FUDGE)
      : 0;
  }

  ___ps->context->fp = alloc_stack_ptr;
  ___ps->context->stack_limit = alloc_stack_ptr
                       - ((stack_avail < stack_left_before_fudge)
                          ? stack_avail
                          : stack_left_before_fudge);
  if (alloc_stack_limit &&
      ___ps->context->stack_limit < alloc_stack_limit+___MSECTION_FUDGE)
    ___ps->context->stack_limit = alloc_stack_limit+___MSECTION_FUDGE;

  heap_avail = avail - stack_avail;
  /* A slice shorter than one fudge cannot authorize another full burst.
   * Replace it once, and only with a section that is not the live stack. */
  if (heap_msection && stack_msection != heap_msection &&
      alloc_heap_ptr && alloc_heap_limit &&
      alloc_heap_ptr >= alloc_heap_start &&
      alloc_heap_ptr <= alloc_heap_limit &&
      (___SIZE_TS)(alloc_heap_limit - alloc_heap_ptr) <= (___SIZE_TS)___MSECTION_FUDGE &&
      compute_free_heap_space_approximately() >= ___MSECTION_SIZE)
    {
      ALLOC_MEM_LOCK();
      next_heap_msection_without_locking (___ps);
      ALLOC_MEM_UNLOCK();
    }
  {
    ___PTRDIFF_T room = alloc_heap_limit - alloc_heap_ptr;
    heap_left_before_fudge =
      room > (___PTRDIFF_T)___MSECTION_FUDGE
      ? (___SIZE_TS)(room - (___PTRDIFF_T)___MSECTION_FUDGE)
      : 0;
  }

  ___ps->context->hp = alloc_heap_ptr;
  ___ps->heap_limit = alloc_heap_ptr
                      + ((heap_avail < heap_left_before_fudge)
                         ? heap_avail
                         : heap_left_before_fudge);
  /* The unchecked burst is exactly one fudge. Keep that burst at or
   * before the hard end. A shorter slice must not publish the cursor
   * itself as the soft limit. */
  if (alloc_heap_limit &&
      alloc_heap_limit > alloc_heap_start+___MSECTION_FUDGE)
    {
      ___WORD *soft = alloc_heap_limit-___MSECTION_FUDGE;
      if (___ps->heap_limit > soft)
        ___ps->heap_limit = soft;
    }
  else if (alloc_heap_ptr && alloc_heap_ptr > alloc_heap_start)
    ___ps->heap_limit = alloc_heap_ptr-1;
  /* set stack overflow and interrupt detection limit */

  publish_fast_span (___ps);

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
  /* Collector FIFO gates belong to VM-owned workers, not PSTATE. */
#endif

  ___ps->collector=0;
  if (!setup_rc (___ps))
    { ___cleanup_actlog_pstate(___ps); return ___FIX(___HEAP_OVERFLOW_ERR); }

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

  ___ps->mem.src_stack_cache_sec_[0] = 0;
  ___ps->mem.src_stack_cache_sec_[1] = 0;
  ___ps->mem.src_stack_cache_sec_[2] = 0;
  ___ps->mem.src_stack_cache_sec_[3] = 0;
  ___ps->mem.src_stack_cache_base_[0] = 0;
  ___ps->mem.src_stack_cache_base_[1] = 0;
  ___ps->mem.src_stack_cache_base_[2] = 0;
  ___ps->mem.src_stack_cache_base_[3] = 0;
  ___ps->mem.src_stack_cache_epoch_ = ~___CAST(___UWORD,0);
  ___ps->mem.src_stack_cache_offset_ = 0;
  ___ps->mem.src_stack_cache_next_ = 0;
  ___ps->mem.wb_last_sec_ = 0;
  ___ps->mem.wb_last_epoch_ = 0;
  ___ps->mem.wb_last_card_lo_ = 0;
  memset(&___ps->mem.card_hints_, 0, sizeof(___ps->mem.card_hints_));
  ___ps->mem.satb_active_ = 0;
  ___ps->mem.satb_count_ = 0;
  ___ps->mem.satb_overflow_ = 0;
  ___ps->mem.satb_buf_ =
    ___CAST(___SCMOBJ*, ___ALLOC_MEM(___GC_SATB_BUF_CAP * sizeof(___SCMOBJ)));
  ___ps->mem.major_mark_local_count_ = 0;
  ___ps->mem.major_mark_local_buf_ =
    ___CAST(___SCMOBJ*, ___ALLOC_MEM(___GC_MAJOR_LOCAL_MARK_CAP * sizeof(___SCMOBJ)));
  if (___ps->mem.satb_buf_ == 0 || ___ps->mem.major_mark_local_buf_ == 0)
    {
      if (___ps->mem.satb_buf_ != 0)
        { ___FREE_MEM(___ps->mem.satb_buf_); ___ps->mem.satb_buf_ = 0; }
      if (___ps->mem.major_mark_local_buf_ != 0)
        { ___FREE_MEM(___ps->mem.major_mark_local_buf_); ___ps->mem.major_mark_local_buf_ = 0; }
      cleanup_rc (___ps);
      ___cleanup_actlog_pstate (___ps);
      return ___FIX(___HEAP_OVERFLOW_ERR);
    }

#ifndef ___SINGLE_THREADED_VMS
  if (___PROCESSOR_ID(___ps,___vms)>0 && ___vms->lifecycle != 0 &&
      ___vms->lifecycle->resize_phase==___RESIZE_PREPARING)
    {
      ___resize_slot *slot=&___vms->lifecycle->slots[___PROCESSOR_ID(___ps,___vms)];
      if (slot->phase!=___RESIZE_RESERVED || slot->stack==0 || slot->heap==0 || slot->stack==slot->heap)
        {
          if (___ps->mem.satb_buf_ != 0)
            { ___FREE_MEM(___ps->mem.satb_buf_); ___ps->mem.satb_buf_ = 0; }
          if (___ps->mem.major_mark_local_buf_ != 0)
            { ___FREE_MEM(___ps->mem.major_mark_local_buf_); ___ps->mem.major_mark_local_buf_ = 0; }
          ___rc_prepare_cleanup(___ps); cleanup_rc(___ps); ___cleanup_actlog_pstate(___ps);
          return ___FIX(___UNKNOWN_ERR);
        }
      set_stack_msection(___ps,slot->stack);
      set_heap_msection(___ps,slot->heap);
    }
  else
#endif
    {
      next_stack_msection (___ps); /* primary context only */
      next_heap_msection (___ps);
    }

  /* Setup list of still objects. */

  still_objs = 0;
  young_still_objs = 0;
  words_still_objs = 0;
  words_still_objs_mature = 0;
  words_still_objs_young = 0;
  words_still_objs_deferred = 0;
  still_words_budget = 0;

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

  ___vms->mem.globals_snapshot_=0;
  the_msections=0;
#ifndef ___SINGLE_VM
  ___vms->glos=0;
#endif

  /* Fresh VM setup owns every fixed source slot before any PS publication. */
  for (source=0; source<___MAX_PROCESSORS; ++source)
    {
      ___PSTATE_FROM_PROCESSOR_ID(source,___vms)->mem.rc_domain_ = 0;
      ___PSTATE_FROM_PROCESSOR_ID(source,___vms)->mem.satb_buf_ = 0;
      ___PSTATE_FROM_PROCESSOR_ID(source,___vms)->mem.major_mark_local_buf_ = 0;
    }

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

  {
    ___SIZE_T identity, count;
    ___vms->glos=___CAST(___global_slot_store*,___ALLOC_MEM(sizeof(*___vms->glos)));
    if (___vms->glos==0) return ___FIX(___HEAP_OVERFLOW_ERR);
    ___vms->glos->directory=0; ___vms->glos->pages=0;
    ___vms->glos->count=0; ___vms->glos->unbound=___UNB1;
    /* The initial image is this VM's bootstrap binding inventory. Later
     * identities registered by another VM do not reserve cells in this VM. */
    ___MUTEX_LOCK(___GSTATE->mem.global_gate);
    count=___GSTATE->mem.glo_list.count;
    for (identity=0;identity<count;identity++)
      if (!global_prepare_locked(___vms,identity)) break;
    ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
    if (identity<count) {
      global_storage_cleanup(___vms); return ___FIX(___HEAP_OVERFLOW_ERR);
    }
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
  reserved_words_still = 0;

  nb_msections_assigned = 0;
  nb_msections_stacks   = 0;

  ___vms->mem.nb_msections_mature_ = 0;
  ___vms->mem.mature_tail_ = 0;
  ___vms->mem.mature_sections_ = 0;
  ___vms->mem.mature_sections_cap_ = 0;
  ___vms->mem.mature_addr_lo_ = 0;
  ___vms->mem.mature_addr_span_ = 0;
  ___vms->mem.mature_snapshot_epoch_ = 1;
  ___vms->mem.occupied_words_mature_ = 0;
  ___vms->mem.major_trigger_sections_ = 8;
  ___vms->mem.minor_gcs_since_major_ = 0;
  ___vms->mem.mature_still_words_ = 0;
  ___vms->mem.major_trigger_still_words_ = 4 * ___MSECTION_SIZE;
  ___vms->mem.promo_cand_count_ = 0;
  ___vms->mem.still_dirty_any_ = 0;
  ___vms->mem.card_overflow_any_ = 0;
  ___vms->mem.force_major_gc_ = 0;
  {
    const char *gen_env = getenv("GAMBIT_GEN_GC");
    ___vms->mem.gen_gc_enabled_ = (gen_env != 0 && gen_env[0] == '0' && gen_env[1] == '\0') ? 0 : 1;
  }
  ___vms->mem.nb_minor_gcs_ = 0.0;
  ___vms->mem.nb_major_gcs_ = 0.0;
  ___vms->mem.minor_gc_real_time_ = 0.0;
  ___vms->mem.major_gc_real_time_ = 0.0;
  ___vms->mem.minor_promoted_words_ = 0;
  ___vms->mem.minor_dirty_cards_scanned_ = 0;
  ___vms->mem.minor_overflow_fallbacks_ = 0;

  ___vms->mem.major_phase_ = ___GC_MAJOR_IDLE;
  ___vms->mem.major_epoch_ = 0;
  ___vms->mem.satb_overflow_ = 0;
  ___vms->mem.major_mark_lock_ = 0;
  ___vms->mem.major_request_start_ = 0;
  ___vms->mem.major_remark_working_ = 0;
  ___vms->mem.major_mark_stack_ = 0;
  ___vms->mem.major_mark_stack_count_ = 0;
  ___vms->mem.major_mark_stack_cap_ = 0;
  ___vms->mem.major_weak_tables_ = 0;
  ___vms->mem.major_weak_tables_count_ = 0;
  ___vms->mem.major_weak_tables_cap_ = 0;
  ___vms->mem.major_still_bases_ = 0;
  ___vms->mem.major_still_bases_count_ = 0;
  ___vms->mem.major_still_bases_cap_ = 0;
  ___vms->mem.major_still_lo_ = 0;
  ___vms->mem.major_still_span_ = 0;
  ___vms->mem.major_evacuate_count_ = 0;
  ___vms->mem.major_last_reclaimed_sections_ = 0;
#ifdef ___USE_HANDLES
  ___vms->mem.concurrent_major_enabled_ = 0;
#else
  {
    const char *cm_env = getenv("GAMBIT_CONCURRENT_MAJOR");
    ___vms->mem.concurrent_major_enabled_ =
      (cm_env != 0 && cm_env[0] == '0' && cm_env[1] == '\0') ? 0 : 1;
  }
#endif
  ___vms->mem.nb_concurrent_major_cycles_ = 0.0;
  ___vms->mem.concurrent_major_mark_slices_ = 0.0;
  ___vms->mem.concurrent_major_marked_words_ = 0.0;
  ___vms->mem.concurrent_major_reclaimed_sections_ = 0.0;
  ___vms->mem.concurrent_major_reclaimed_still_words_ = 0.0;
  ___vms->mem.concurrent_major_remark_real_time_ = 0.0;
  ___vms->mem.concurrent_major_satb_logged_ = 0.0;
  ___vms->mem.concurrent_major_holes_recycled_ = 0.0;
  ___vms->mem.concurrent_major_idle_slices_ = 0.0;

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
#ifdef ___GAMBIT_REST_OBSERVATION
  const char *procedure=getenv("GAMBIT_GATE2_PROCEDURE");
  const char *label=getenv("GAMBIT_GATE2_LABEL");
  const char *case_id=getenv("GAMBIT_GATE2_CASE");
  if (!gate2_procedure && procedure && label && case_id && ___rest_observation_open(0)) {
    const uint64_t selected_case=strtoull(case_id,0,10);
    const uint64_t selected_label=strtoull(label,0,10);
    if (selected_label && selected_case && ___rest_observation_case(selected_case)) {
      gate2_procedure=procedure;
      gate2_label=selected_label;
      rest_observation_case_hold=1;
    }
  }
#endif
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
       * Choose a reasonable minimum live percent (adaptive large-heap enabled).
       */

      ___set_live_percent_explicit (0);
      ___GSTATE->setup_params.live_percent = ___DEFAULT_LIVE_PERCENT;
    }
  else
    {
      ___set_live_percent_explicit (1);
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

  {
    ___SCMOBJ result=___glo_list_setup();
    if (result!=___FIX(___NO_ERR)) return result;
  }

  {
    ___SCMOBJ t = alloc_symkey_table (___sSYMBOL, INIT_SYMBOL_TABLE_LENGTH);

    if (___FIXNUMP(t))
      { ___cleanup_mem(); return t; }

    ___GSTATE->symbol_table = t;
  }

  {
    ___SCMOBJ t = alloc_symkey_table (___sKEYWORD, INIT_KEYWORD_TABLE_LENGTH);

    if (___FIXNUMP(t))
      { ___cleanup_mem(); return t; }

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
  if (still_words_budget > 0)
    {
      ALLOC_MEM_LOCK();
      if (reserved_words_still >= still_words_budget)
        reserved_words_still -= still_words_budget;
      else
        reserved_words_still = 0;
      still_words_budget = 0;
      ALLOC_MEM_UNLOCK();
    }
  clear_fast_span (___ps);
  if (___ps->mem.satb_buf_ != 0)
    {
      ___FREE_MEM(___ps->mem.satb_buf_);
      ___ps->mem.satb_buf_ = 0;
      ___ps->mem.satb_count_ = 0;
    }
  if (___ps->mem.major_mark_local_buf_ != 0)
    {
      ___FREE_MEM(___ps->mem.major_mark_local_buf_);
      ___ps->mem.major_mark_local_buf_ = 0;
      ___ps->mem.major_mark_local_count_ = 0;
    }
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

  /* An already cleaned or unconstructed processor owns no still/RC state.
   * Failure rollback must not run its cleanup twice or inspect stale fields. */
  if (___PSTATE_FROM_PROCESSOR_ID(0,___vms)->mem.rc_domain_ != 0)
    ___cleanup_mem_pstate (___PSTATE_FROM_PROCESSOR_ID(0,___vms));

  free_msections (&the_msections);
  if (___vms->mem.mature_sections_ != 0)
    {
      ___FREE_MEM(___vms->mem.mature_sections_);
      ___vms->mem.mature_sections_ = 0;
      ___vms->mem.mature_sections_cap_ = 0;
    }
  if (___vms->mem.major_mark_stack_ != 0)
    {
      ___FREE_MEM(___vms->mem.major_mark_stack_);
      ___vms->mem.major_mark_stack_ = 0;
      ___vms->mem.major_mark_stack_cap_ = 0;
    }
  if (___vms->mem.major_weak_tables_ != 0)
    {
      ___FREE_MEM(___vms->mem.major_weak_tables_);
      ___vms->mem.major_weak_tables_ = 0;
      ___vms->mem.major_weak_tables_cap_ = 0;
    }
  if (___vms->mem.major_still_bases_ != 0)
    {
      ___FREE_MEM(___vms->mem.major_still_bases_);
      ___vms->mem.major_still_bases_ = 0;
      ___vms->mem.major_still_bases_cap_ = 0;
    }

#ifndef ___SINGLE_VM
  /* One VM-owned block covers ordinary/primitive slots and presence bits.
   * All source leases and native borrowers have drained before this cut. */
  global_storage_cleanup(___vms);



#endif

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


void ___cleanup_mem ___PVOID
{
#ifdef ___GAMBIT_REST_OBSERVATION
  rest_observation_finish();
#endif
  if (___GSTATE->mem.global_snapshots!=0)
    rc_contract_error("global snapshot retained at runtime cleanup");
  free_psections ();
  ___MUTEX_DESTROY(___GSTATE->mem.permanent_gate);
  ___MUTEX_DESTROY(___GSTATE->mem.global_gate);
}


/* End internal memory fragment. */
