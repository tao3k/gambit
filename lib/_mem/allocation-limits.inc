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

  if (alloc_stack_ptr < alloc_stack_limit + ___MSECTION_FUDGE)
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
                  (___ps->context->stack_start - ___ps->context->stack_limit)*2/3)
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
      return 1;
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

static int group_demand_same(___group_demand *d, ___processor_state ps,
                             ___WORD group_point, ___WORD attempt)
{
  return d && ps && attempt!=0 && d->attempt==attempt &&
    d->context==ps->context &&
    d->activation==group_demand_activation(ps) &&
    d->group_point==group_point;
}

static int group_footprint_fits(___processor_state ps, ___group_demand *d,
                                ___WORD *hp, ___WORD *fp)
{
  if (!ps || !d || !hp || !fp) return 0;
  if (d->heap_words>0 && !___heap_alloc_fits(ps, hp, d->heap_words)) return 0;
  if (d->stack_words>0 && !cursor_has_stack_room(ps, fp, d->stack_words)) return 0;
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

/* Issue the next attempt for this VM. The counter never wraps; exhaustion
 * returns zero and the caller must fail the grant. */
static ___WORD group_demand_issue(___vm_lifecycle *life)
{
  for (;;) {
    ___WORD old=___WORD_LOAD_ACQUIRE(&life->group_demand_attempt_next);
    ___WORD next;
    if (old==0 || old>=___MAX_FIX) return 0;
    next=old+1;
    if (next==0 || next>=___MAX_FIX) return 0;
    if (___lifecycle_cas(&life->group_demand_attempt_next, old, next)==old)
      return old;
  }
}

___EXP_FUNC(int,___handler_spill_backed)
(___processor_state ps, ___WORD *fp)
{
  ___WORD *cursor=fp ? fp : (ps && ps->context ? ps->context->fp : 0);
  if (!ps || !cursor) {
    rc_contract_error("Handler internal return frame has no backing");
    return 0;
  }
  if (cursor_has_stack_room(ps, cursor, handler_spill_words())) {
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
  if (d->phase==1 && d->resume_query &&
      d->context==ps->context &&
      d->activation==group_demand_activation(ps) &&
      d->group_point==group_point && d->attempt!=0) {
    d->resume_query=0;
    if (!group_footprint_fits(ps, d, hp, fp)) {
      d->phase=3;
      return 0;
    }
    group_demand_publish_view(d, ps, hp, fp);
    d->phase=2;
    if (attempt_out) *attempt_out=d->attempt;
    return 0;
  }
  if (d->phase==1 || d->phase==2 || d->phase==3 || d->phase==4) return 1;
  life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  attempt=group_demand_issue(life);
  if (!attempt) {
    d->phase=3;
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
      rc_contract_error("Stack cursor is outside the owned interval");
      return 0;
    }
  }
  if (!cursor_has_stack_room(ps, fp, handler_spill_words())) {
    d->phase=3;
    return 0;
  }
  d->phase=group_footprint_fits(ps, d, hp, fp) ? 2 : 1;
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
  if (attempt==0) return;
  d=group_demand_slot(ps);
  if (!group_demand_same(d, ps, group_point, attempt) || d->phase!=2) return;
  d->phase=0;
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
  /* Diagnostic only. The 84138e91 demand struct has no saved_fp slot.
   * Do not store one while this object is linked with that layout. */
  (void)fp;
  (void)hp;
  if (overflow) {
    d->phase=3;
    d->resume_query=0;
    return;
  }
  /* Phase 2 is issued by the unframed retry. Keep the attempt and demand. */
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

/* Preserve the emitted protocol order in one runtime service. This uses
 * only C locals: no Scheme allocation, safepoint, spill or new attempt store.
 * A false result requires the caller's existing mapped limit-service jump. */
#undef ___group_demand_enter
___EXP_FUNC(int,___group_demand_enter)
(___processor_state ps, ___WORD **hp, ___WORD **fp,
 ___SIZE_TS stack_words, ___SIZE_TS heap_words,
 ___WORD group_point, ___WORD *attempt_out)
{
  /* Heap grants keep the full attempt protocol. A stack adjustment that
   * already fits the current half-section allocates nothing and does not
   * need a new attempt. */
  if (heap_words==0 && ps && ps->context && hp && *hp && fp && *fp &&
      ps->context->hp==*hp && ps->context->fp==*fp &&
      (stack_words<=0 || ___stack_adjust_fits(ps, *fp, stack_words))) {
    if (attempt_out) *attempt_out=0;
    return 1;
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
      if (noted) REST_OBS(REST_GRANT,ps,noted->activation,noted->attempt,noted->epoch,
               *hp,*fp,noted->stack_words,noted->heap_words,group_point,
               noted->phase,owned?lo:0,owned?hi:0);
    }
#endif
    return granted;
  }
}

___EXP_FUNC(void,___group_demand_note_return_fp)
(___processor_state ps, ___WORD *fp)
{
  ___group_demand *d=group_demand_slot(ps);
  if (!d || !ps) return;
  (void)fp;
  REST_OBS(REST_RETURN_FP,ps,d->activation,d->attempt,0,fp,d->phase,0,0,0,0,0,0);
}

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

  return 0;
}


/* End internal memory fragment. */
