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
      ___WORD *prev_alloc_stack_start = alloc_stack_start;
      ___WORD *prev_alloc_stack_ptr = alloc_stack_ptr;
      ___WORD *prev_stack_break = ___ps->context->stack_break;
      ___WORD *fp;
      int frame_count;
      int words;

      /*
       * Get a new stack msection.
       */

      ___msection *ms = msection_free_list;

      if (stack_msection != heap_msection &&
          ms != NULL)
        {
          /* we can reuse an existing one */

          msection_free_list = ___CAST(___msection*,ms->base[0]);

          set_stack_msection (___ps, ms);
        }
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

                  ___FP_ADJFP(alloc_stack_ptr,___BREAK_FRAME_SPACE)
                  ___FP_SET_STK(alloc_stack_ptr,
                                -___BREAK_FRAME_NEXT,
                                ___CAST(___WORD,prev_alloc_stack_ptr))
                  ___ps->context->stack_break = alloc_stack_ptr;
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

              fp = alloc_stack_ptr;

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

      stack_msection_stop_using (___ps, prev_alloc_stack_start, fp);
    }

  prepare_mem_pstate (___ps);

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

  if (stack_msection != heap_msection &&
      ___ps->context->stack_start == &___STK(-___FIRST_BREAK_FRAME_SPACE) &&
      (ms = ___CAST(___msection*,___STK(-___FIRST_BREAK_FRAME_STACK_MSECTION)))
      != NULL)
    {
      /*
       * The current stack msection is not shared with the heap and
       * the break frame is at the start of the stack msection and it
       * was created due to a stack section overflow, so the stack can
       * be moved to the previous stack msection.
       */

      stack_msection->base[0] = ___CAST(___WORD,msection_free_list);
      msection_free_list = stack_msection;

      set_stack_msection (___ps, ms);

      ___ps->context->stack_break =
        ___CAST(___WORD*,___STK(-___FIRST_BREAK_FRAME_STACK_BREAK));

      alloc_stack_ptr =
        ___CAST(___WORD*,___STK(-___BREAK_FRAME_NEXT));

      ___ps->context->stack_start = alloc_stack_start;

      stack_msection_resume_using (___ps, alloc_stack_start, alloc_stack_ptr);

      prepare_mem_pstate (___ps);

      ___SET_FP(alloc_stack_ptr)

      return ___FRAME_FETCH_RA;
    }

  return ___FAL;
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

  /* Recover processor's stack and heap pointers */

  alloc_stack_ptr = ___ps->context->fp;
  alloc_heap_ptr  = ___ps->context->hp;

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

    ___msection *ms = msection_free_list;

    if (stack_msection != heap_msection &&
        ms != NULL)
      {
        /* we can reuse an existing one */

        msection_free_list = ___CAST(___msection*,ms->base[0]);

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
            if (alloc_heap_ptr > alloc_heap_limit - ___MSECTION_FUDGE)
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

  prepare_mem_pstate (___ps);

  return 0;
}


/* End internal memory fragment. */
