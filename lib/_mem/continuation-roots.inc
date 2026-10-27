#line 3667 ___MEM_SOURCE_FILE
___HIDDEN void mark_captured_continuation
   ___P((___PSD
         ___WORD *orig_ptr),
        (___PSV
         orig_ptr)
___PSDKR
___WORD *orig_ptr;)
{
  ___PSGET
  ___WORD *ptr = orig_ptr;
  int fs, link, i;
  ___WORD *fp;
  ___WORD ra1;
  ___WORD ra2;
  ___WORD cf;

  cf = *ptr;

#ifdef SHOW_FRAMES
  ___printf ("mark_captured_continuation cf=%p\n", ___CAST(void*,cf));
#endif

  if (___FIXNUMP(cf) && cf != ___END_OF_CONT_MARKER)
    {
      /* continuation frame is in the stack */

      ___WORD *alloc = alloc_heap_ptr;
      ___WORD *limit = alloc_heap_limit;

      MISC_MEM_LOCK();

      next_frame:

      fp = ___CAST(___WORD*,cf);

      ra1 = ___FP_STK(fp,-___FRAME_STACK_RA);

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

      if (ra1 == ___GSTATE->internal_return)
        {
          ___WORD actual_ra = ___FP_STK(fp,___RETI_RA);
          ___RETI_GET_FS_LINK(actual_ra,fs,link)
          ___COVER_MARK_CAPTURED_CONTINUATION_RETI;
        }
      else
        {
          ___RETN_GET_FS_LINK(ra1,fs,link)
          ___COVER_MARK_CAPTURED_CONTINUATION_RETN;
        }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", fs, link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

      ___FP_ADJFP(fp,-___FRAME_SPACE(fs)) /* get base of frame */

      ra2 = ___FP_STK(fp,link+1);

      if (___FIXNUMP(ra2))
        {
          ___COVER_MARK_CAPTURED_CONTINUATION_ALREADY_COPIED;
          *ptr = ra2; /* already copied, replace by forwarding pointer */
        }
      else
        {
          ___WORD forw;
          ___SIZE_TS words;

          ___COVER_MARK_CAPTURED_CONTINUATION_COPY;

          words = fs + ___FRAME_EXTRA_SLOTS;

          while (alloc + words + ___SUBTYPED_BODY > limit)
            {
              alloc_heap_ptr = alloc;
              end_heap_chunk (___ps);
              next_heap_msection (___ps);
              prepare_heap_msection (___ps);
              alloc = alloc_heap_ptr;
              limit = alloc_heap_limit;
            }

          /*TODO: add allocation of handle if using handles*/

          *alloc++ = ___MAKE_HD_WORDS(words, ___sFRAME);
#if ___SUBTYPED_BODY != 1
          #error "___SUBTYPED_BODY != 1"
#endif
          forw = ___TAG(alloc - ___REFERENCE_TO_BODY, ___tFIXNUM);
          *alloc++ = ra1;
#if ___FRAME_EXTRA_SLOTS != 1
          #error "___FRAME_EXTRA_SLOTS != 1"
#endif

          for (i=fs; i>0; i--)
            *alloc++ = ___FP_STK(fp,i);

          if (ra2 == ___GSTATE->handler_break)
            {
              /* first frame of that section */

              ___COVER_MARK_CAPTURED_CONTINUATION_FIRST_FRAME;

              cf = ___FP_STK(fp,-___BREAK_FRAME_NEXT);
            }
          else
            {
              /* not the first frame of that section */

              ___COVER_MARK_CAPTURED_CONTINUATION_NOT_FIRST_FRAME;

              ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
              cf = ___CAST(___WORD,fp);
            }

          ___FP_SET_STK(alloc,link+1,cf)
          ___FP_SET_STK(fp,link+1,forw) /* leave a forwarding pointer */

          *ptr = forw;

          ptr = &___FP_STK(alloc,link+1);

          if (alloc_heap_ptr >= alloc_heap_chunk_limit)
            {
              alloc_heap_ptr = alloc;
              end_heap_chunk (___ps);
              start_heap_chunk (___ps);
              alloc = alloc_heap_ptr;
            }

          if (___FIXNUMP(cf) && cf != ___END_OF_CONT_MARKER)
            goto next_frame;
        }

      *orig_ptr = ___TAG(___UNTAG_AS(*orig_ptr, ___tFIXNUM), ___tSUBTYPED);

      alloc_heap_ptr = alloc;

      MISC_MEM_UNLOCK();
    }
  else
    mark_array (___PSP orig_ptr, 1);
}


___HIDDEN void mark_frame
   ___P((___PSD
         ___WORD *fp,
         const ___frame_descriptor *frame),
        (___PSV
         fp,
         frame)
___PSDKR
___WORD *fp;
const ___frame_descriptor *frame;)
{
  ___frame_root_cursor cursor = ___frame_root_begin (frame);
  int first, past;

  while (___frame_root_next_run (&cursor, &first, &past))
    {
#ifdef SHOW_FRAMES
      int k = first;
      while (k < past)
        {
          ___WORD obj = ___FP_STK(fp,k);
          ___printf ("  %2d: ", k);
          print_value (obj);
          ___printf ("\n");
          k++;
        }
#endif
      mark_array (___PSP &___FP_STK(fp,past-1), past-first);
    }
}


___HIDDEN void mark_continuation
   ___P((___PSD ___WORD *fp, ___WORD *stack_break),
        (___PSV fp, stack_break)
___PSDKR
___WORD *fp;
___WORD *stack_break;)
{
  ___PSGET
  ___frame_descriptor descriptor;
  ___WORD ra1;
  ___WORD ra2;

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_CONTINUATION;
#endif

#ifdef SHOW_FRAMES
  ___printf ("mark_continuation fp=%p\n", fp);
#endif

  if (fp != stack_break)
    for (;;)
      {
        ra1 = ___FP_STK(fp,-___FRAME_STACK_RA);

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

        if (ra1 == ___GSTATE->internal_return)
          {
            ___WORD actual_ra = ___FP_STK(fp,___RETI_RA);
            descriptor = ___decode_frame_descriptor (___LABEL_DESCR_GET(actual_ra), 1);
            ___COVER_MARK_CONTINUATION_RETI;
          }
        else
          {
            descriptor = ___decode_frame_descriptor (___LABEL_DESCR_GET(ra1), 0);
            ___COVER_MARK_CONTINUATION_RETN;
          }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", descriptor.fs, descriptor.link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

        ___FP_ADJFP(fp,-___FRAME_SPACE(descriptor.fs)) /* get base of frame */

        ra2 = ___FP_STK(fp,descriptor.link+1);

#ifdef SHOW_FRAMES
        if (fp == stack_break)
          ___printf ("  (first frame above break frame)\n");
#endif

        mark_frame (___PSP fp, &descriptor);

        if (fp == stack_break)
          break;

        ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
      }

  mark_captured_continuation (___PSP &___FP_STK(fp,-___BREAK_FRAME_NEXT));
}


/* Preserve the original active-frame/captured-tail algorithm. Source and
 * frame storage are held by the enclosing stopped GC invocation. */
___BOOL ___root_task_scan_stack(___root_task *task, ___processor_state executor,
                               ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  ___execution_context *source;
  if (!root_stack_task(task,executor) ||
      !root_task_matches(task,___ROOT_STACK,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  source=task->origin.source.stack;
  task->state=___ROOT_SCANNING;
  mark_continuation (___PSP source->fp,source->stack_break);
  task->state=___ROOT_SCANNED;
  return 1;
}


/* End internal memory fragment. */
