static ___group_demand *group_demand_slot(___processor_state ps);
int ___heap_alloc_fits(___processor_state ___ps, ___WORD *hp, ___SIZE_TS n);

#line 7036 ___MEM_SOURCE_FILE
#ifdef ___DEBUG_STACK_LIMIT

___BOOL ___stack_limit_debug
   ___P((___PSD
         int line,
         char *file),
        (___PSV
         line,
         file)
___PSDKR
int line;
char *file;)

#else

___BOOL ___stack_limit
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)

#endif
{
  ___PSGET

  /*
   * In a multithreaded VM, the function ___stack_limit can be called
   * concurrently by multiple processors. The VM level memory allocation
   * lock is used to implement a critical section.
   */

  /* Recover processor's stack and heap pointers */

  alloc_stack_ptr = ___ps->context->fp;
  alloc_heap_ptr  = ___ps->context->hp;

#ifdef ___DEBUG_STACK_LIMIT
  ___ps->stack_limit_line = line;
  ___ps->stack_limit_file = file;
  ___printf ("___POLL caused ___stack_limit call at %s:%d\n",
             ___ps->poll_file,
             ___ps->poll_line);
#endif

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
    check_fudge_used (___PSPNC);
#endif

  {
    ___group_demand *pending_stack = group_demand_slot(___ps);
    ___SIZE_TS stack_reserve = ___MSECTION_FUDGE;
    if (pending_stack && pending_stack->context == ___ps->context &&
        pending_stack->phase == 1 && pending_stack->stack_words > 0)
      stack_reserve += pending_stack->stack_words;
    if (alloc_stack_ptr < alloc_stack_limit + stack_reserve)
    {
      /*
       * There isn't enough free space in the current stack msection.
       */

      ___msection *prev_stack_msection = stack_msection;
      ___WORD *prev_alloc_stack_limit = alloc_stack_limit;
      ___WORD *prev_alloc_stack_start = alloc_stack_start;
      ___WORD *prev_alloc_stack_ptr = alloc_stack_ptr;
      ___WORD *prev_stack_break = ___ps->context->stack_break;
      ___WORD *fp;
      int frame_count;
      int words;

      /*
       * Get a new stack msection.
       */

      ___msection *ms = stack_msection != heap_msection
        ? take_released_stack_section(___ps) : 0;

      if (ms != 0)
        set_stack_msection (___ps, ms);
      else
        {
          /* we need to allocate a new msection */

          ALLOC_MEM_LOCK();

          if (
#ifdef CALL_GC_FREQUENTLY
              --___gc_calls_to_punt < 0 ||
#endif
              compute_free_heap_space_approximately() < ___MSECTION_SIZE)
            {
              if (___ps->primlock_depth > 0 && the_msections &&
                  the_msections->nb_sections > 0 &&
                  the_msections->nb_sections < INT_MAX &&
                  ___rest_new_section_admitted (___ps, ___GSTATE->setup_params.max_heap))
                {
                  /* Never enter stop-the-world GC barrier while holding a raw spinlock,
                   * while still enforcing any configured max_heap bound. */
                  int before_n = the_msections->nb_sections;
                  adjust_msections (&the_msections, before_n + 1);
                  if (the_msections->nb_sections > before_n)
                    {
                      heap_size = compute_heap_size ();
                      next_stack_msection_without_locking (___ps);
                      ALLOC_MEM_UNLOCK();
                      goto stack_msection_ready;
                    }
                }
              ALLOC_MEM_UNLOCK();

              /*
               * Because the GC preserves the topmost contiguous
               * frames in the stack msection (the frames between the
               * stack pointer and the latest break frame), the
               * occupation of the stack msection would increase
               * gradually with subsequent calls to ___stack_limit and
               * this would eventually cause an uncontrolled overflow
               * of the stack msection.
               *
               * To avoid this, a break frame is added at the top of
               * the stack when the topmost contiguous frames in the
               * stack msection take too much space.  This will cause
               * the GC to move all the frames to the heap.
               */

              if ((___ps->context->stack_break - alloc_stack_ptr) >
                  (___ps->context->stack_start - ___ps->context->stack_limit)*2/3 ||
                  (pending_stack && pending_stack->context == ___ps->context &&
                   pending_stack->phase == 1 &&
                   prev_alloc_stack_ptr != prev_stack_break &&
                   (___ps->context->stack_break - alloc_stack_ptr) + stack_reserve >
                     (___ps->context->stack_start - alloc_stack_limit)))
                {
                  /*
                   * At the top of the current stack msection there are
                   * contiguous frames that occupy more than 2/3 of the
                   * available space.
                   */

                  /*
                   * Add a break frame.
                   */

                  ___publish_raw_stack_span(___ps,prev_alloc_stack_ptr,prev_stack_break);
                  /* The break frame has to stay inside the half. Pushing
                   * it from the hard base leaves the cursor census rejects. */
                  if (alloc_stack_ptr >= alloc_stack_limit + ___BREAK_FRAME_SPACE)
                    {
                      ___FP_ADJFP(alloc_stack_ptr,___BREAK_FRAME_SPACE)
                      ___FP_SET_STK(alloc_stack_ptr,
                                    -___BREAK_FRAME_NEXT,
                                    ___CAST(___WORD,prev_alloc_stack_ptr))
                      ___ps->context->stack_break = alloc_stack_ptr;
                    }
                }

              prepare_mem_pstate (___ps);

              return 1; /* trigger GC */
            }

          next_stack_msection_without_locking (___ps);

          ALLOC_MEM_UNLOCK();
        }

    stack_msection_ready:
      /*
       * Move to the new stack msection.
       */

      ___ps->context->stack_start = alloc_stack_start;
      alloc_stack_ptr = alloc_stack_start;

      /*
       * Create a "break frame" in the new stack msection.  The break
       * frame is used by the break handler (see _kernel.scm).
       */

      ___FP_ADJFP(alloc_stack_ptr,___FIRST_BREAK_FRAME_SPACE)
      ___FP_SET_STK(alloc_stack_ptr,-___FIRST_BREAK_FRAME_STACK_MSECTION,0)

      /*
       * Because ___stack_limit is only called by the stack-limit
       * handler in _kernel.scm and it has pushed an internal
       * return frame to the top of the stack, the frame pointer
       * can't be pointing to a break frame,
       * i.e. prev_alloc_stack_ptr != prev_stack_break.
       *
       * If the topmost frame were to be left on the stack, when
       * ___stack_overflow_undo_if_possible would return to it, an
       * uncontrolled overflow of the stack would be possible (because
       * the generated code assumes that after returning from a call
       * to ___stack_limit it is OK to perform a function call without
       * checking the stack limit).
       *
       * For this reason, is is necessary for correctness to transfer
       * the topmost frame to the new stack msection.  However, only
       * transferring the topmost frame may cause the stack limit
       * handler to be called frequently if there are many shallow
       * function calls in a row (calls to ___stack_limit followed by
       * ___stack_overflow_undo_if_possible in a tight loop).  To
       * avoid this performance issue, it is best to transfer a
       * certain number of frames, but no more than up to the break
       * frame.
       */

      fp = prev_alloc_stack_ptr;
      frame_count = 0; /* count of frames to transfer */

      for (;;)
        {
          int fs, link;
          ___WORD ra1 = ___FP_STK(fp,-___FRAME_STACK_RA);
          ___WORD ra2;

          frame_count++;

          if (ra1 == ___GSTATE->internal_return)
            {
              ___WORD actual_ra = ___FP_STK(fp,___RETI_RA);
              ___RETI_GET_FS_LINK(actual_ra,fs,link)
            }
          else
            {
              ___RETN_GET_FS_LINK(ra1,fs,link)
            }

          ___FP_ADJFP(fp,-___FRAME_SPACE(fs)) /* get base of frame */

          ra2 = ___FP_STK(fp,link+1);

          words = fp - prev_alloc_stack_ptr;

          if (fp == prev_stack_break)
            {
              /* reached the break frame */

              /* best to not transfer any frames to new stack msection */

              /*
               * Add a break frame.
               */

              ___FP_ADJFP(alloc_stack_ptr,___BREAK_FRAME_SPACE)
              ___FP_SET_STK(alloc_stack_ptr,
                            -___BREAK_FRAME_NEXT,
                            ___CAST(___WORD,prev_alloc_stack_ptr))
              ___ps->context->stack_break = alloc_stack_ptr;

              fp = prev_alloc_stack_ptr;

              break;
            }

          ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)

          words = fp - prev_alloc_stack_ptr;

          if (frame_count >= 5 || words >= 100)
            {
              /* reached max frame count or max volume */

              /*
               * Save state of previous stack msection in the
               * first break frame of new stack msection to allow
               * returning to the previous stack msection when
               * ___stack_overflow_undo_if_possible is called.
               */

              ___FP_SET_STK(alloc_stack_ptr,
                            -___FIRST_BREAK_FRAME_STACK_MSECTION,
                            ___CAST(___WORD,prev_stack_msection))

              ___FP_SET_STK(alloc_stack_ptr,
                            -___FIRST_BREAK_FRAME_STACK_BREAK,
                            ___CAST(___WORD,prev_stack_break))

              ___FP_SET_STK(alloc_stack_ptr,
                            -___BREAK_FRAME_NEXT,
                            ___CAST(___WORD,fp))

              ___ps->context->stack_break = alloc_stack_ptr;

              memmove (alloc_stack_ptr - words,
                       prev_alloc_stack_ptr,
                       words << ___LWS);

              ___FP_SET_STK(alloc_stack_ptr,
                            link+1,
                            ___GSTATE->handler_break)

              ___FP_ADJFP(alloc_stack_ptr, words)

              break;
            }
        }

      park_stack_section(___ps,prev_stack_msection,prev_alloc_stack_limit,
                         fp,prev_stack_break);
      stack_msection_stop_using (___ps, prev_alloc_stack_start, fp);
    }
  }

  /* A stack return reloads the heap cursor. The following allocation is
   * unchecked up to the fudge, so a nearly full half has to be replaced
   * before that reload. */
  if (heap_msection && alloc_heap_ptr && alloc_heap_limit &&
      alloc_heap_ptr>=alloc_heap_start &&
      alloc_heap_ptr<=alloc_heap_limit &&
      (___SIZE_TS)(alloc_heap_limit-alloc_heap_ptr)<=(___SIZE_TS)___MSECTION_FUDGE)
    {
      ___msection *heap_ms = stack_msection != heap_msection
        ? take_released_stack_section(___ps) : 0;
      if (heap_ms != 0)
        {
          words_prev_msections += alloc_heap_ptr-alloc_heap_start;
          set_heap_msection (___ps, heap_ms);
        }
      else if (compute_free_heap_space_approximately() >= ___MSECTION_SIZE)
        {
          ALLOC_MEM_LOCK();
          next_heap_msection_without_locking (___ps);
          ALLOC_MEM_UNLOCK();
        }
    }

  prepare_mem_pstate (___ps);
  {
    ___WORD *hp=___ps->context ? ___ps->context->hp : 0;
    ___group_demand *pending=group_demand_slot(___ps);
    if (pending && hp && pending->context==___ps->context &&
        pending->phase==1 && pending->heap_words>0 &&
        !___heap_alloc_fits(___ps, hp, pending->heap_words))
      {
        if (___ps->primlock_depth > 0 && the_msections &&
            the_msections->nb_sections > 0 &&
            the_msections->nb_sections < INT_MAX)
          {
            int before_n;
            ALLOC_MEM_LOCK();
            if (___rest_new_section_admitted (___ps, ___GSTATE->setup_params.max_heap))
              {
                before_n = the_msections->nb_sections;
                adjust_msections (&the_msections, before_n + 1);
                if (the_msections->nb_sections > before_n)
                  {
                    heap_size = compute_heap_size ();
                    next_heap_msection_without_locking (___ps);
                  }
              }
            ALLOC_MEM_UNLOCK();
            prepare_mem_pstate (___ps);
            hp = ___ps->context ? ___ps->context->hp : 0;
            if (hp && ___heap_alloc_fits(___ps, hp, pending->heap_words))
              return 0;
          }
        /* Return 2 (truthy) to distinguish a pure heap-group shortage from a
         * stack shortage so handler_stack_limit raises heap-overflow-exception
         * rather than stack-overflow-exception when GC overflows max_heap. */
        return 2;
      }
  }

  return 0;
}


___WORD ___stack_overflow_undo_if_possible
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___D_FP
  ___R_FP

  ___msection *ms;

  if (___ps->context->stack_start == &___STK(-___FIRST_BREAK_FRAME_SPACE) &&
      (ms = ___CAST(___msection*,___STK(-___FIRST_BREAK_FRAME_STACK_MSECTION)))
      != NULL)
    {
      ___msection *outgoing=stack_msection;
      section_claim *active=section_claim_at(outgoing,tospace_offset);
      section_claim *parked=section_claim_at(ms,tospace_offset);
      ___WORD *break_frame;
      ___WORD *next_frame;
      ___WORD *floor;
      if(active->heap_used)
        return ___FAL; /* The logical break-handler copy remains available. */
      if(active->stack_owner!=___ps || active->stack_state!=STACK_ACTIVE ||
         parked->stack_owner!=___ps || parked->stack_state!=STACK_PARKED ||
         !parked->stack_floor)
        { rc_contract_error("Invalid stack section undo claim"); return ___FAL; }
      break_frame=___CAST(___WORD*,___STK(-___FIRST_BREAK_FRAME_STACK_BREAK));
      next_frame=___CAST(___WORD*,___STK(-___BREAK_FRAME_NEXT));
      if (break_frame!=parked->parked_break || next_frame!=parked->parked_top) {
        rc_contract_error("Stack undo does not match the parked source span");
        return ___FAL;
      }
      floor=parked->stack_floor;
      ___SET_STK(-___FIRST_BREAK_FRAME_STACK_MSECTION,0)

      set_stack_msection (___ps, ms);
      alloc_stack_limit=floor;
      ___ps->context->stack_break=break_frame;
      alloc_stack_ptr=next_frame;
      ___ps->context->stack_start = alloc_stack_start;

      stack_msection_resume_using (___ps, alloc_stack_start, alloc_stack_ptr);
      release_stack_section(___ps,outgoing);

      prepare_mem_pstate (___ps);

      ___SET_FP(alloc_stack_ptr)

      return ___FRAME_FETCH_RA;
    }

  return ___FAL;
}

int ___heap_alloc_fits(___processor_state ___ps, ___WORD *hp, ___SIZE_TS n)
{
  ___UWORD current, end;
  if (!___ps || !___ps->context || !hp || n<0 ||
      !current_heap_interval_matches(___ps,hp) ||
      !section_claim_at(heap_msection,tospace_offset)->heap_used)
    return 0;
  current=___CAST(___UWORD,hp);
  end=___CAST(___UWORD,alloc_heap_limit);
  if (heap_msection==stack_msection && alloc_stack_limit &&
      ___CAST(___UWORD,alloc_stack_limit)<end)
    end=___CAST(___UWORD,alloc_stack_limit);
  if (current>end) return 0;
  return ___CAST(___UWORD,n)<=(end-current)/___WS;
}

int ___stack_adjust_fits(___processor_state ps, ___WORD *fp, ___SIZE_TS delta)
{
  ___WORD *lo, *hi, *next;
  if (delta<=0) return 1;
  if (!___owned_stack_span(ps, &lo, &hi) || !fp || fp<lo || fp>hi) return 0;
  /* Distance before subtraction. A delta wider than the owned prefix
   * must not form a wrapped cursor. */
  if ((___SIZE_TS)(fp-lo)<delta) return 0;
  next=fp-delta;
  return next<=hi;
}

/* Room is distance inside the span ___owned_stack_span published.
 * A cursor in the other half does not select that half. */
static int cursor_has_stack_room(___processor_state ps, ___WORD *fp,
                                 ___SIZE_TS words)
{
  return ___stack_adjust_fits(ps, fp, words);
}

/* Demand lives on the VM lifecycle. The processor number only routes
 * inside that VM. Phase 4 is a diagnostic hold with no waiter. */

static ___SIZE_TS handler_spill_words(void)
{
  return (___SIZE_TS)((___FRAME_ALIGN-1)+___FRAME_SPACE(___NB_GVM_REGS+1));
}

static ___group_demand *group_demand_slot(___processor_state ps)
{
  ___virtual_machine_state vm;
  ___vm_lifecycle *life;
  ptrdiff_t id;
  if (!ps || !ps->context) return 0;
  vm=___VMSTATE_FROM_PSTATE(ps);
  if (!vm || !vm->lifecycle) return 0;
  life=vm->lifecycle;
  id=___PROCESSOR_ID(ps, vm);
  if (id<0 || id>=___MAX_PROCESSORS) return 0;
  return &life->group_demand[id];
}

static ___activation_record *group_demand_activation(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ptrdiff_t id;
  if (!vm || !vm->lifecycle) return 0;
  id=___PROCESSOR_ID(ps, vm);
  if (id<0 || id>=___MAX_PROCESSORS) return 0;
  return vm->lifecycle->activations[id];
}

static ___WORD group_demand_gc_epoch(___processor_state ps)
{
  return (___WORD)___VMSTATE_FROM_PSTATE(ps)->mem.nb_gcs_;
}

#ifdef ___GAMBIT_REST_OBSERVATION
static int gate2_here(___processor_state ps)
{
  return gate2_view.phase && gate2_view.actor==ps &&
    gate2_view.context==(uintptr_t)ps->context &&
    gate2_view.activation==(uintptr_t)group_demand_activation(ps);
}

static int gate2_actor_current(void *actor)
{
  return actor && gate2_here((___processor_state)actor);
}

static void gate2_retire(___processor_state ps)
{
  if (gate2_here(ps)) {
    gate2_event(REST_GROUP_RETIRED,gate2_view.attempt,0,0,0,0,0);
    gate2_view.phase=GATE2_IDLE;
  }
}

___EXP_FUNC(void,___gate2_group_site)
(___processor_state ps, const char *procedure, int label, ___WORD point,
 ___WORD *fp, int opening)
{
  ___WORD *lo=0,*hi=0;
  if (__builtin_expect(!___rest_observation_active,1) || !gate2_procedure) return;
  if (opening && point!=gate2_view.point && gate2_view.phase==GATE2_SETTLED)
    gate2_retire(ps);
  if (strcmp(gate2_procedure,procedure) || (uint64_t)label!=gate2_label) return;
  if (opening) {
    if (gate2_here(ps)) {
      gate2_event(REST_GROUP_OPEN,(uintptr_t)fp,0,0,0,label,gate2_view.phase);
      return;
    }
    gate2_view.actor=ps;
    gate2_view.point=point;
    gate2_view.context=(uintptr_t)ps->context;
    gate2_view.activation=(uintptr_t)group_demand_activation(ps);
    gate2_view.invocation++;
    gate2_view.attempt=0;
    gate2_view.epoch=group_demand_gc_epoch(ps);
    gate2_view.phase=GATE2_OLD_FRAME;
  } else if (!gate2_here(ps) || gate2_view.point!=point) return;
  ___owned_stack_span(ps,&lo,&hi);
  gate2_event(opening?REST_GROUP_OPEN:REST_GROUP_ENTER,(uintptr_t)fp,
              (uintptr_t)lo,(uintptr_t)hi,(uintptr_t)ps->context->stack_limit,
              label,gate2_view.phase);
  if (!opening && gate2_view.phase!=GATE2_SETTLED) gate2_view.phase=GATE2_PENDING;
}

___EXP_FUNC(void,___gate2_fast_done)
(___processor_state ps, ___WORD point)
{
  if (gate2_procedure && gate2_here(ps) && gate2_view.point==point && gate2_view.phase==GATE2_PENDING)
    gate2_view.phase=GATE2_IDLE;
}

#endif

static int group_demand_same(___group_demand *d, ___processor_state ps,
                             ___WORD group_point, ___WORD attempt)
{
  ___vm_lifecycle *life;
  if (!d || !ps || !ps->context || attempt==0 || d->attempt!=attempt) return 0;
  if (d->context!=ps->context) return 0;
  if (d->activation!=group_demand_activation(ps)) return 0;
  if (d->group_point!=group_point) return 0;
  life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  return life && d->service_incarnation==life->incarnation;
}

static int stack_span_adjust_fits(___WORD *lo, ___WORD *hi, ___WORD *fp,
                                  ___SIZE_TS delta)
{
  ___WORD *floor, *next;
  if (delta<=0) return 1;
  if (!fp || fp<lo || fp>hi) return 0;
  if ((___SIZE_TS)(hi-lo)<=___MSECTION_FUDGE) return 0;
  floor=lo+___MSECTION_FUDGE;
  if (fp<floor || (___SIZE_TS)(fp-floor)<delta) return 0;
  next=fp-delta;
  return next<=hi;
}

static int mutator_stack_adjust_fits(___processor_state ps, ___WORD *fp,
                                     ___SIZE_TS delta)
{
  ___WORD *lo, *hi;
  if (delta<=0) return 1;
  if (!___owned_stack_span(ps, &lo, &hi)) return 0;
  return stack_span_adjust_fits(lo, hi, fp, delta);
}

static int group_footprint_fits(___processor_state ps, ___group_demand *d,
                                ___WORD *hp, ___WORD *fp)
{
  if (!ps || !d || !hp || !fp) return 0;
  if (d->heap_words>0 && !___heap_alloc_fits(ps, hp, d->heap_words)) return 0;
  if (d->stack_words>0 && !mutator_stack_adjust_fits(ps, fp, d->stack_words)) return 0;
  return 1;
}

static void group_demand_publish_view(___group_demand *d, ___processor_state ps,
                                      ___WORD *hp, ___WORD *fp)
{
  d->hp=hp;
  d->fp=fp;
  d->root_fp=fp;
  d->epoch=group_demand_gc_epoch(ps);
}

/* Next shortage number for this processor slot. Fitting groups do not
 * call this. The counter stays on the slot for this VM incarnation and
 * never wraps; exhaustion returns zero and the caller fails the grant. */
static ___WORD group_demand_issue(___group_demand *d, ___vm_lifecycle *life)
{
  ___WORD n;
  if (!d || !life) return 0;
  n=d->service_next;
  if (n==0) n=1;
  if (n>=___MAX_FIX) return 0;
  if (n+1==0 || n+1>=___MAX_FIX) return 0;
  d->service_next=n+1;
  d->service_incarnation=life->incarnation;
  return n;
}

static int group_demand_local_room
   (___processor_state ps, ___WORD *hp, ___WORD *fp,
    ___SIZE_TS stack_words, ___SIZE_TS heap_words)
{
  ___WORD *lo, *hi;
  if (!ps || !ps->context || !hp || !fp) return 0;
  if (ps->context->hp!=hp || ps->context->fp!=fp) return 0;
  /* Check pure pointer-local heap limits before acquiring copy_gate via
   * ___owned_stack_span, and reuse the single (lo, hi) lease snapshot for
   * both cursor containment and mutator stack-fudge adjustment. */
  if (heap_words>0) {
    ___WORD *limit=ps->heap_limit;
    if (!limit || hp>=limit || (___SIZE_TS)(limit-hp)<heap_words) return 0;
    if (!___heap_alloc_fits(ps, hp, heap_words)) return 0;
  }
  if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) return 0;
  if (stack_words>0 && !stack_span_adjust_fits(lo, hi, fp, stack_words)) return 0;
  return 1;
}

/* Capacity already covers this group. Authorize the caller's current
 * cursors and leave the slow slot untouched. No shared counter, poll,
 * safepoint or reentry. */
int ___group_demand_local_admit
   (___processor_state ps, ___WORD *hp, ___WORD *fp,
    ___SIZE_TS stack_words, ___SIZE_TS heap_words)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d || d->phase!=0) return 0;
  return group_demand_local_room(ps, hp, fp, stack_words, heap_words);
}

___EXP_FUNC(int,___handler_spill_backed)
(___processor_state ps, ___WORD *fp)
{
  ___WORD *cursor=fp ? fp : (ps && ps->context ? ps->context->fp : 0);
  if (!ps || !cursor) {
    rc_contract_error("Handler internal return frame has no backing");
    return 0;
  }
  int fits=cursor_has_stack_room(ps, cursor, handler_spill_words());
#ifdef ___GAMBIT_REST_OBSERVATION
  if (gate2_procedure && gate2_here(ps) && ps->temp1==gate2_view.point) {
    ___WORD *lo=0,*hi=0;
    int raw_map_complete=1;
    ___UWORD live=0;
    ___frame_descriptor frame=___decode_frame_descriptor(___LABEL_DESCR_GET(ps->temp1),1);
    int slot;
    ___owned_stack_span(ps,&lo,&hi);
    if (frame.stored_fs<0 || frame.stored_fs>64) raw_map_complete=0;
    if (raw_map_complete)
      for (slot=1; slot<=frame.stored_fs; ++slot)
        if (___frame_slot_live(&frame, slot))
          live|=(___UWORD)1<<(slot-1);
    gate2_event(REST_GROUP_BACKING,(uintptr_t)cursor,(uintptr_t)lo,(uintptr_t)hi,
                handler_spill_words(),fits && raw_map_complete ? frame.stored_fs+1 : 0,live);
  }
#endif
  if (fits) {
    REST_OBS(REST_BACKING,ps,0,0,0,cursor,handler_spill_words(),1,0,0,0,0,0);
    return 1;
  }
  REST_OBS(REST_BACKING,ps,0,0,0,cursor,handler_spill_words(),0,0,0,0,0,0);
  rc_contract_error("Handler internal return frame has no backing");
  return 0;
}

___EXP_FUNC(int,___group_demand_resume_view)
(___processor_state ps, ___WORD group_point,
                               ___WORD **hp, ___WORD **fp)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d || !ps || !ps->context || !hp || !fp || !d->resume_query) return 0;
  /* The handler cursor is diagnostic. The unframed retry must keep the
   * fp/hp it actually holds; writing the saved handler frame back would
   * make the later equality check agree with the wrong coordinate. */
  if (d->phase==1) return 0;
  if (d->context!=ps->context ||
      d->activation!=group_demand_activation(ps) ||
      d->group_point!=group_point || d->attempt==0 || !d->hp || !d->fp)
    return 0;
  if (d->epoch!=group_demand_gc_epoch(ps)) {
    rc_contract_error("Write-group retry view is not the repaired epoch");
    return 0;
  }
  ps->context->hp=d->hp;
  ps->context->fp=d->fp;
  *hp=d->hp;
  *fp=d->fp;
  return 1;
}

___EXP_FUNC(int,___group_demand_arm)
(___processor_state ps, ___WORD *hp, ___WORD *fp,
                       ___SIZE_TS stack_words, ___SIZE_TS heap_words,
                       ___WORD group_point, ___WORD *attempt_out)
{
  ___group_demand *d=group_demand_slot(ps);
  ___vm_lifecycle *life;
  ___WORD attempt;
  if (attempt_out) *attempt_out=0;
  if (!d || !ps || !ps->context || !hp || !fp) return 1;
  /* The caller publishes the live locals first. A context cursor that
   * still names an older position cannot authorize this write. */
  if (ps->context->hp!=hp || ps->context->fp!=fp) return 1;
  /* One return from the handler. Issue phase 2 only after unframe, using
   * the cursors this entry actually holds, and consume the retry once.
   * A second miss is a native failure so the generated jump cannot spin. */
  /* The handler already proved this footprint and published the repaired
   * cursors. Accept that view once; do not issue another shortage. */
  if (d->phase==2 && d->resume_query &&
      d->context==ps->context &&
      d->activation==group_demand_activation(ps) &&
      d->group_point==group_point && d->attempt!=0 &&
      d->hp==hp && d->fp==fp &&
      d->epoch==group_demand_gc_epoch(ps) &&
      ___VMSTATE_FROM_PSTATE(ps)->lifecycle &&
      d->service_incarnation==___VMSTATE_FROM_PSTATE(ps)->lifecycle->incarnation) {
    d->resume_query=0;
    if (attempt_out) *attempt_out=d->attempt;
    return 0;
  }
  if (d->phase==1 && d->resume_query &&
      d->context==ps->context &&
      d->activation==group_demand_activation(ps) &&
      d->group_point==group_point && d->attempt!=0 &&
      ___VMSTATE_FROM_PSTATE(ps)->lifecycle &&
      d->service_incarnation==___VMSTATE_FROM_PSTATE(ps)->lifecycle->incarnation) {
    d->resume_query=0;
    if (group_footprint_fits(ps, d, hp, fp)) {
      group_demand_publish_view(d, ps, hp, fp);
      d->phase=2;
      ps->group_demand_active=1; clear_fast_span(ps);
      if (attempt_out) *attempt_out=d->attempt;
      return 0;
    }
    if (d->epoch==group_demand_gc_epoch(ps)) {
      d->phase=3;
      ps->group_demand_active=1; clear_fast_span(ps);
      return 0;
    }
  }
  if (d->phase==2 || (d->phase==1 && !d->resume_query) ||
      ((d->phase==3 || d->phase==4) &&
       d->context==ps->context &&
       d->activation==group_demand_activation(ps)))
    return 1;
  /* Shortage only. A group that already fits is admitted by the caller
   * with attempt zero and never reaches this issuance. */
  life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  attempt=group_demand_issue(d, life);
  if (!attempt) {
    d->phase=3;
    ps->group_demand_active=1; clear_fast_span(ps);
    return 0;
  }
  d->context=ps->context;
  d->activation=group_demand_activation(ps);
  d->group_point=group_point;
  d->attempt=attempt;
  d->stack_words=stack_words;
  d->heap_words=heap_words;
  d->resume_query=0;
  group_demand_publish_view(d, ps, hp, fp);
  if (attempt_out) *attempt_out=attempt;
  {
    ___WORD *lo, *hi;
    if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) {
      d->phase=3;
      ps->group_demand_active=1; clear_fast_span(ps);
      rc_contract_error("Stack cursor is outside the owned interval");
      return 0;
    }
  }
  if (!cursor_has_stack_room(ps, fp, handler_spill_words())) {
    d->phase=3;
    ps->group_demand_active=1; clear_fast_span(ps);
    return 0;
  }
  d->phase=group_footprint_fits(ps, d, hp, fp) ? 2 : 1;
  ps->group_demand_active=1; clear_fast_span(ps);
  return 0;
}

___EXP_FUNC(int,___group_demand_granted)
(___processor_state ps, ___WORD group_point,
                            ___WORD attempt, ___WORD *hp, ___WORD *fp)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!group_demand_same(d, ps, group_point, attempt) || d->phase!=2)
    return 0;
  if (!hp || !fp || hp!=d->hp || fp!=d->fp) return 0;
  if (d->epoch!=group_demand_gc_epoch(ps)) return 0;
  return 1;
}

#undef ___group_demand_commit
___EXP_FUNC(void,___group_demand_commit)
(___processor_state ps, ___WORD group_point,
                            ___WORD attempt)
{
  ___group_demand *d;
  /* A fitting stack-only enter publishes attempt 0 and must not clear
   * an earlier heap grant. */
  if (__builtin_expect(attempt==0, 1)) {
#ifdef ___GAMBIT_REST_OBSERVATION
    if (__builtin_expect(___rest_observation_active, 0))
      ___gate2_fast_done(ps, group_point);
#endif
    return;
  }
  d=group_demand_slot(ps);
  if (!group_demand_same(d, ps, group_point, attempt) || d->phase!=2) return;
#ifdef ___GAMBIT_REST_OBSERVATION
  if (gate2_procedure && gate2_here(ps) && gate2_view.point==group_point && gate2_view.attempt==attempt) {
    gate2_event(REST_GROUP_COMMIT,attempt,0,0,0,0,0);
    gate2_view.phase=GATE2_SETTLED;
  }
#endif
  d->phase=0;
  if (ps) { ps->group_demand_active=0; publish_fast_span(ps); }
  d->context=0;
  d->activation=0;
  d->group_point=0;
  d->attempt=0;
  d->root_fp=0;
  d->hp=0;
  d->fp=0;
  d->stack_words=0;
  d->heap_words=0;
  d->epoch=0;
  d->resume_query=0;
}

___EXP_FUNC(int,___group_demand_before)
(___processor_state ps, ___WORD *fp)
{
  ___group_demand *d=group_demand_slot(ps);
  ___WORD *lo, *hi;
  if (!d || !ps || !fp || d->context!=ps->context || d->attempt==0) return 0;
  if (d->activation!=group_demand_activation(ps)) return 0;
  /* The demand is only visible while this cursor is still inside the
   * owned span and on the old side of the stack limit. */
  if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) return 0;
  if (ps->context->stack_limit && ___FP_AFTER(fp, ps->context->stack_limit))
    return 0;
  REST_OBS(REST_DEMAND,ps,d->activation,d->attempt,d->epoch,
           fp,lo,hi,ps->context->stack_limit,d->phase,d->stack_words,d->heap_words,0);
#ifdef ___GAMBIT_REST_OBSERVATION
  if (gate2_procedure && gate2_here(ps) && d->group_point==gate2_view.point && d->phase==1)
    gate2_event(REST_GROUP_DEMAND,(uintptr_t)fp,(uintptr_t)ps->context->stack_limit,
                d->phase,d->attempt,d->stack_words,d->heap_words);
#endif
  if (d->phase==1) return 1;
  if (d->phase==3 || d->phase==4) return 2;
  return 0;
}

___EXP_FUNC(void,___group_demand_after)
(___processor_state ps, int overflow)
{
  ___group_demand *d=group_demand_slot(ps);
  ___WORD *hp;
  ___WORD *fp;
  if (!d || !ps || !ps->context || d->context!=ps->context || d->phase!=1)
    return;
  if (d->activation!=group_demand_activation(ps) || d->attempt==0) return;
  hp=ps->context->hp;
  fp=ps->context->fp;
#ifdef ___GAMBIT_REST_OBSERVATION
  if (gate2_procedure && gate2_here(ps) && d->group_point==gate2_view.point && d->attempt==gate2_view.attempt)
    gate2_event(REST_GROUP_SAVED,(uintptr_t)fp,d->attempt,overflow,group_demand_gc_epoch(ps),0,0);
#endif
  /* A collection is not room. Publish the repaired cursors only when they
   * hold the footprint, so the unframed retry writes at the post-recovery
   * hp instead of the cursor that just filled the section. */
  if (overflow || !group_footprint_fits(ps, d, hp, fp)) {
    d->phase=overflow ? 3 : 4;
    ps->group_demand_active=1; clear_fast_span(ps);
    d->resume_query=0;
    return;
  }
  d->epoch=group_demand_gc_epoch(ps);
  d->resume_query=1;
}

___EXP_FUNC(int,___group_demand_blocked)
(___processor_state ps)
{
  ___group_demand *d=group_demand_slot(ps);
  return d && ps && d->context==ps->context &&
    d->activation==group_demand_activation(ps) &&
    (d->phase==3 || d->phase==4);
}

___EXP_FUNC(int,___group_demand_will_retry)
(___processor_state ps)
{
  ___group_demand *d=group_demand_slot(ps);
  return d && ps && d->context==ps->context &&
    d->activation==group_demand_activation(ps) &&
    d->resume_query && (d->phase==1 || d->phase==2);
}

___EXP_FUNC(int,___group_demand_stalled)
(___processor_state ps)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d || !ps || d->context!=ps->context || d->attempt==0) return 0;
  if (d->activation!=group_demand_activation(ps)) return 0;
  if (d->phase!=1 && d->phase!=2) return 0;
  return !___group_demand_will_retry(ps);
}

___EXP_FUNC(void,___group_demand_retire)
(___processor_state ps)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d) return;
  d->phase=0;
  if (ps) { ps->group_demand_active=0; publish_fast_span(ps); }
  d->context=0;
  d->activation=0;
  d->group_point=0;
  d->attempt=0;
  d->root_fp=0;
  d->hp=0;
  d->fp=0;
  d->stack_words=0;
  d->heap_words=0;
  d->epoch=0;
  d->resume_query=0;
}

___EXP_FUNC(void,___group_demand_fail)
(___processor_state ps)
{
  (void)ps;
  rc_contract_error("Stack or heap group demand was not granted");
}

/* Publish the soft heap limit for a freshly selected section. The stack
 * cursor stays where the mutator left it. */
static void publish_bumped_heap_limit(___processor_state ___ps)
{
  ___PTRDIFF_T room;
  ___SIZE_TS left;
  ___WORD *soft;
  if (!___ps) return;
  room=alloc_heap_limit-alloc_heap_ptr;
  left=room>(___PTRDIFF_T)___MSECTION_FUDGE
    ? (___SIZE_TS)(room-(___PTRDIFF_T)___MSECTION_FUDGE) : 0;
  ___ps->context->hp=alloc_heap_ptr;
  ___ps->heap_limit=alloc_heap_ptr+left;
  if (alloc_heap_limit &&
      alloc_heap_limit>alloc_heap_start+___MSECTION_FUDGE) {
    soft=alloc_heap_limit-___MSECTION_FUDGE;
    if (___ps->heap_limit>soft) ___ps->heap_limit=soft;
  }
  publish_fast_span(___ps);
}

/* The current section cannot hold this heap group. Keep the bytes already
 * consumed, then continue on a new section. Returns after the mutator heap
 * cursor has moved. */
static int bump_heap_section_for_demand(___processor_state ___ps, ___WORD *hp,
                                        ___SIZE_TS heap_words)
{
  if (!___ps || !___ps->context || !hp || !heap_msection) return 0;
  /* A cursor past the hard edge still belongs to this section. Snap it
   * back so the next free section can be published. */
  if (hp>alloc_heap_limit) hp=alloc_heap_limit;
  if (hp<alloc_heap_start) return 0;
  if (compute_free_heap_space_approximately()<___MSECTION_SIZE) return 0;
  if (heap_words>0 && ___heap_alloc_fits(___ps, hp, heap_words) &&
      alloc_heap_limit && hp<=alloc_heap_limit &&
      (___SIZE_TS)(alloc_heap_limit-hp)>(___SIZE_TS)___MSECTION_FUDGE) {
    if ((___SIZE_TS)(alloc_heap_limit-hp)-(___SIZE_TS)___MSECTION_FUDGE>=heap_words) {
      alloc_heap_ptr=hp;
      publish_bumped_heap_limit(___ps);
      return ___ps->context->hp==alloc_heap_ptr;
    }
    return 0;
  }
  alloc_heap_ptr=hp;
  next_heap_msection(___ps);
  publish_bumped_heap_limit(___ps);
  return ___ps->context->hp==alloc_heap_ptr;
}

/* The soft heap limit ended a section that still has a free successor.
 * Continuing there avoids a whole-heap census. */
int ___stack_extend_soft_limit(___processor_state ___ps)
{
  ___WORD *floor;
  if (!___ps || !___ps->context || !___ps->context->fp || !alloc_stack_limit)
    return 0;
  if (!___FP_AFTER(___ps->context->fp, ___ps->context->stack_limit)) return 0;
  floor=alloc_stack_limit+___MSECTION_FUDGE;
  if (___ps->context->fp<=floor) return 0;
  ___ps->context->stack_limit=floor;
  return 1;
}

int ___heap_rearm_after_collection(___processor_state ___ps)
{
  ___processor_state ps=___ps;
  int n, add;
  if (!ps || !ps->context) return 0;
  if (ps->heap_limit && ps->context->hp && ps->context->hp<=ps->heap_limit)
    return 1;
  if (___GSTATE->setup_params.max_heap!=0) return 0;
  if (!the_msections || !the_msections->head) return 0;
  if (!heap_msection)
    set_heap_msection(ps, the_msections->head);
  ALLOC_MEM_LOCK();
  n=the_msections->nb_sections;
  add=n/2;
  if (add<32) add=32;
  if (compute_free_heap_space_approximately()<___MSECTION_SIZE &&
      n>0 && add<=INT_MAX-n) {
    adjust_msections(&the_msections, n+add);
    heap_size=compute_heap_size();
  }
  ALLOC_MEM_UNLOCK();
  next_heap_msection(ps);
  publish_bumped_heap_limit(ps);
  return ps->heap_limit && ps->context->hp && ps->context->hp<=ps->heap_limit;
}

int ___heap_continue_on_free_section(___processor_state ___ps)
{
  ___WORD *hp;
  if (!___ps || !___ps->context) return 0;
  hp=___ps->context->hp;
  if (!___ps->heap_limit || hp<=___ps->heap_limit) return 0;
  /* Assigned sections are not a heap limit. With no byte cap, reserve more
   * before a census. The next bump publishes one of those sections. */
  if (compute_free_heap_space_approximately()<___MSECTION_SIZE &&
      ___GSTATE->setup_params.max_heap==0 && the_msections) {
    int n, add, grown;
    ALLOC_MEM_LOCK();
    n=the_msections->nb_sections;
    add=n/2;
    if (add<8) add=8;
    grown=n>0 && add<=INT_MAX-n ? n+add : n;
    if (grown>n) adjust_msections(&the_msections, grown);
    heap_size=compute_heap_size();
    ALLOC_MEM_UNLOCK();
  }
  return bump_heap_section_for_demand(___ps, hp, 0);
}

/* Preserve the emitted protocol order in one runtime service. This uses
 * only C locals: no Scheme allocation, safepoint, spill or new attempt store.
 * A false result requires the caller's existing mapped limit-service jump. */
#undef ___group_demand_enter
___EXP_FUNC(int,___group_demand_enter)
(___processor_state ps, ___WORD **hp, ___WORD **fp,
 ___SIZE_TS stack_words, ___SIZE_TS heap_words,
 ___WORD group_point, ___WORD *attempt_out);

#if defined(__GNUC__) && !defined(CBMC)
static __attribute__((noinline, cold)) int group_demand_enter_slow
#else
static int group_demand_enter_slow
#endif
(___processor_state ps, ___WORD **hp, ___WORD **fp,
 ___SIZE_TS stack_words, ___SIZE_TS heap_words,
 ___WORD group_point, ___WORD *attempt_out)
{
  ___group_demand *slot;
  /* A fitting group, including a positive heap demand, uses the caller's
   * current cursors and does not take a service number. Shortage falls
   * through to the mapped attempt. */
  slot=ps ? group_demand_slot(ps) : 0;
  {
    int same_pending=slot && slot->phase!=0 && ps && slot->context==ps->context &&
      slot->activation==group_demand_activation(ps) && slot->group_point==group_point;
    int blocked_here=slot && (slot->phase==3 || slot->phase==4) && ps &&
      slot->context==ps->context && slot->activation==group_demand_activation(ps);
    /* Sync live generated cursors once on fast-path entry before acquiring
     * the section copy_gate snapshot inside group_demand_local_room, cutting
     * fast-path copy_gate acquisitions from up to 4 down to at most 1. */
    if (!same_pending && !blocked_here && hp && *hp && fp && *fp && ps && ps->context &&
        (!slot || slot->phase!=2)) {
      ps->context->hp=*hp;
      ps->context->fp=*fp;
      if (group_demand_local_room(ps, *hp, *fp, stack_words, heap_words)) {
        if ((!slot || slot->phase==0) && !ps->group_demand_active &&
            (!ps->stack_fast_limit_b || (heap_words>0 && !ps->heap_fast_bytes)))
          publish_fast_span(ps);
        if (attempt_out) *attempt_out=0;
        return 1;
      }
      if (heap_words>0 && bump_heap_section_for_demand(ps, *hp, heap_words)) {
        *hp=ps->context->hp;
        if (group_demand_local_room(ps, *hp, *fp, stack_words, heap_words)) {
          if (attempt_out) *attempt_out=0;
          return 1;
        }
      }
    }
  }
  if (!___group_demand_resume_view(ps, group_point, hp, fp)) {
    ps->context->hp=*hp;
    ps->context->fp=*fp;
  }
  if (___group_demand_arm(ps, *hp, *fp, stack_words, heap_words,
                         group_point, attempt_out)) {
    rc_contract_error("Write-group arm was not accepted");
    return 0;
  }
#ifdef ___GAMBIT_REST_OBSERVATION
  if (gate2_procedure && gate2_here(ps) && gate2_view.point==group_point && attempt_out)
    gate2_view.attempt=*attempt_out;
#endif
  if (___group_demand_blocked(ps)) {
    rc_contract_error("Write-group entered while a refusal was pending");
    return 0;
  }
  {
    int granted=___group_demand_granted(ps, group_point, *attempt_out, *hp, *fp);
    (void)granted;
#ifdef ___GAMBIT_REST_OBSERVATION
    if (granted) {
      ___group_demand *noted=group_demand_slot(ps);
      ___WORD *lo=0,*hi=0;
      int owned=___owned_stack_span(ps,&lo,&hi);
      if (gate2_procedure && noted && gate2_here(ps) && gate2_view.point==group_point &&
          gate2_view.attempt==noted->attempt) {
        gate2_view.epoch=noted->epoch;
        gate2_event(REST_GROUP_GRANT,(uintptr_t)*fp,(uintptr_t)lo,(uintptr_t)hi,
                    noted->stack_words,noted->attempt,___WS);
        gate2_event(REST_GROUP_HEAP_GRANT,(uintptr_t)*hp,noted->heap_words,noted->attempt,0,0,0);
        gate2_view.phase=GATE2_GRANTED;
      }
      if (noted) REST_OBS(REST_GRANT,ps,noted->activation,noted->attempt,noted->epoch,
               *hp,*fp,noted->stack_words,noted->heap_words,group_point,
               noted->phase,owned?lo:0,owned?hi:0);
    }
#endif
    return granted;
  }
}

___EXP_FUNC(int,___group_demand_enter)
(___processor_state ps, ___WORD **hp, ___WORD **fp,
 ___SIZE_TS stack_words, ___SIZE_TS heap_words,
 ___WORD group_point, ___WORD *attempt_out)
{
  /* Processor-owned byte-range leaf fast-span check when group_demand_active == 0:
   * avoids callee-saved spills, copy_gate atomic acquisition, and lifecycle slot
   * lookup while keeping ___group_demand_enter strictly out-of-line. */
  if (__builtin_expect(ps!=0 && ps->context!=0 && hp!=0 && fp!=0 && attempt_out!=0, 1)) {
    ___WORD *f=*fp;
    ___WORD *h=*hp;
    if (__builtin_expect(f!=0 && h!=0 && stack_words>=0 && heap_words>=0, 1)) {
      ___UWORD sd=___CAST(___UWORD,f)-ps->stack_fast_floor_b;
      if (__builtin_expect(
            sd<ps->stack_fast_limit_b &&
            (sd/sizeof(___WORD))>=(___UWORD)stack_words &&
            (heap_words==0 ||
             ((___CAST(___UWORD,h)-ps->heap_fast_lo_b)<ps->heap_fast_bytes &&
              ((ps->heap_fast_bytes-(___CAST(___UWORD,h)-ps->heap_fast_lo_b))/sizeof(___WORD))>=(___UWORD)heap_words)),
            1)) {
        ps->context->hp=h;
        ps->context->fp=f;
        *attempt_out=0;
        return 1;
      }
    }
  }
  return group_demand_enter_slow(ps, hp, fp, stack_words, heap_words,
                                 group_point, attempt_out);
}

___EXP_FUNC(void,___group_demand_note_return_fp)
(___processor_state ps, ___WORD *fp)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d || !ps) return;
  (void)fp;
  REST_OBS(REST_RETURN_FP,ps,d->activation,d->attempt,0,fp,d->phase,0,0,0,0,0,0);
}

#ifdef ___GAMBIT_REST_OBSERVATION
___EXP_FUNC(void,___gate2_unwound)
(___processor_state ps, ___WORD *handler_fp, ___WORD *caller_fp, int cfs)
{
  ___group_demand *d=group_demand_slot(ps);
  if (gate2_procedure && d && gate2_here(ps) && d->phase==1 && d->resume_query &&
      d->group_point==gate2_view.point && d->attempt==gate2_view.attempt) {
    gate2_view.epoch=group_demand_gc_epoch(ps);
    gate2_event(REST_GROUP_UNWOUND,(uintptr_t)handler_fp,(uintptr_t)caller_fp,cfs,
                ___FRAME_ALIGN,___FRAME_SPACE(___NB_GVM_REGS+1),d->attempt);
  }
}
#endif

#ifdef ___DEBUG_HEAP_LIMIT

___BOOL ___heap_limit_debug
   ___P((___PSD
         int line,
         char *file),
        (___PSV
         line,
         file)
___PSDKR
int line;
char *file;)

#else

___BOOL ___heap_limit
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)

#endif
{
  ___PSGET

  /*
   * In a multithreaded VM, the function ___heap_limit can be called
   * concurrently by multiple processors. The VM level memory allocation
   * lock is used to implement a critical section.
   */

  /* Recover processor's stack and heap pointers.
   * heap_msection is published exclusively by the selection below. hp from
   * another carrier, and fp, stay in these locals until this carrier's own
   * active half admits the old cursor. Rejection returns before the reuse
   * list, words_prev_msections, or either allocation cursor is updated. */
  {
    ___WORD *old_fp = ___ps->context->fp;
    ___WORD *old_hp = ___ps->context->hp;
    /* A cursor past alloc_heap_limit may already be a CONS stored into a
     * live register. Do not publish a rewound hp. Collection has to see
     * the cursor the processor actually published. */
    {
      ___UWORD current=___CAST(___UWORD,old_hp);
      ___UWORD end=___CAST(___UWORD,alloc_heap_limit);
      ___WORD *base;
      ___WORD *past;
      if (heap_msection && end!=0 && current>end &&
          ((current|end)%___WS)==0 &&
          (current-end)/___WS<=___CAST(___UWORD,___MSECTION_FUDGE))
        {
          base=start_of_tospace(heap_msection);
          past=base+(___MSECTION_SIZE>>1);
          if (___CAST(___UWORD,old_hp)<=___CAST(___UWORD,past))
            return 1;
        }
    }
    if (!current_heap_interval_matches(___ps,old_hp) ||
        !section_claim_at(heap_msection,tospace_offset)->heap_used)
      {
        if (!heap_msection ||
            !section_claim_at(heap_msection,tospace_offset)->heap_used)
          rc_contract_error("Heap limit section is not an active heap");
        else
          rc_contract_error("Heap limit old cursor leaves its owned active half");
        return 1;
      }
    alloc_stack_ptr = old_fp;
    alloc_heap_ptr = old_hp;
  }

#ifdef ___DEBUG_HEAP_LIMIT
  ___ps->heap_limit_line = line;
  ___ps->heap_limit_file = file;
#endif

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
    check_fudge_used (___PSPNC);
#endif

  {
    /*
     * Get a new heap msection.
     */

    /* The admitted cursor belongs to the current heap_msection. Selecting a
     * reusable stack section publishes that section alone; the previous
     * heap_msection is not a second live allocation cursor. */
    ___msection *ms = stack_msection != heap_msection
      ? take_released_stack_section(___ps) : 0;

    if (ms != 0)
      {
        words_prev_msections += alloc_heap_ptr-alloc_heap_start;
        set_heap_msection (___ps, ms);
      }
    else
      {
        /* we need to allocate a new msection */

        ALLOC_MEM_LOCK();

        if (
#ifdef CALL_GC_FREQUENTLY
            --___gc_calls_to_punt >= 0 &&
#endif
            compute_free_heap_space_approximately() >= ___MSECTION_SIZE)
          {
            if (!current_heap_interval_matches(___ps,alloc_heap_ptr))
              {
                ALLOC_MEM_UNLOCK();
                rc_contract_error("Heap limit interval leaves its destination section");
                return 1;
              }
            if (___gc_resume_heap_needs_refill(alloc_heap_ptr,alloc_heap_limit,___MSECTION_FUDGE))
              next_heap_msection_without_locking (___ps);

            ALLOC_MEM_UNLOCK();
          }
        else if (___ps->primlock_depth > 0 && the_msections &&
                 the_msections->nb_sections > 0 &&
                 the_msections->nb_sections < INT_MAX &&
                 ___rest_new_section_admitted (___ps, ___GSTATE->setup_params.max_heap))
          {
            int before_n = the_msections->nb_sections;
            adjust_msections (&the_msections, before_n + 1);
            if (the_msections->nb_sections > before_n)
              {
                heap_size = compute_heap_size ();
                if (___gc_resume_heap_needs_refill(alloc_heap_ptr,alloc_heap_limit,___MSECTION_FUDGE))
                  next_heap_msection_without_locking (___ps);
                ALLOC_MEM_UNLOCK();
              }
            else
              {
                ALLOC_MEM_UNLOCK();
                return 1;
              }
          }
        else
          {
            ALLOC_MEM_UNLOCK();

            return 1; /* trigger GC */
          }
      }
  }

  if (!current_heap_interval_matches(___ps,alloc_heap_ptr) ||
      !___gc_published_reserve_fits(alloc_heap_ptr,alloc_heap_limit,___MSECTION_FUDGE,6))
    {
      rc_contract_error("Heap publication lacks the fudge reserve for a first closure");
      return 1;
    }

  prepare_mem_pstate (___ps);

#ifndef ___DISABLE_GENERATIONAL_GC
  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0 && ___ps->primlock_depth == 0))
    {
      ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
      ___SIZE_TS budget =
        (___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) > 4096) ? 49152 : 32768;
      ___gc_major_mark_slice(___ps, budget);
    }
#endif

  return 0;
}


/* End internal memory fragment. */
