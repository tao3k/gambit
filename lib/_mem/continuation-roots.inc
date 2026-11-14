#line 4085 ___MEM_SOURCE_FILE
/* Resolve the old half and stack claim before loading any frame word. The
 * descriptor itself is trusted live module metadata, as in the ordinary
 * frame decoder. A captured suffix may have no independent logical end. */
___HIDDEN ___msection *resolve_source_half(___msections *sections,
                                           ___WORD *top,
                                           ___SIZE_TS source_offset,
                                           ___SIZE_TS *half_words)
{
  ___msection *section;
  ___UWORD address=___CAST(___UWORD,top),first,half_past;
  int i;
  if (!sections || (source_offset!=0 && source_offset!=(___MSECTION_SIZE>>1))) return 0;
  i=find_msection(sections,top);
  if (i<0 || i>=sections->nb_sections) return 0;
  section=sections->sections[i];
  first=___CAST(___UWORD,section->base+source_offset);
  half_past=first+___CAST(___UWORD,___MSECTION_SIZE>>1)*___WS;
  if ((first%___WS)!=0 || (address%___WS)!=0 || address<first || address>=half_past)
    return 0;
  *half_words=(half_past-address)/___WS;
  return section;
}

___HIDDEN ___BOOL source_claim_is_live(const section_claim *claim)
{
  return claim->stack_owner &&
    (claim->stack_state==STACK_ACTIVE || claim->stack_state==STACK_PARKED);
}

___HIDDEN ___msection *admit_source_stack_span(___collector_worker *work,
                                              ___WORD *top,
                                              ___SIZE_TS source_offset,
                                              ___WORD *logical_past,
                                              ___SIZE_TS *half_words)
{
  ___processor_state ___ps=work->carrier;
  ___msection *section=resolve_source_half(the_msections,top,source_offset,half_words);
  ___UWORD address=___CAST(___UWORD,top);
  if (!section || !source_claim_is_live(section_claim_at(section,source_offset))) return 0;
  if (logical_past) {
    ___UWORD logical=___CAST(___UWORD,logical_past);
    if ((logical%___WS)!=0 || logical<address || (logical-address)/___WS>*half_words) return 0;
  }
  return section;
}

___HIDDEN int decode_source_stack_frame(___WORD *top, ___SIZE_TS remaining,
                                       ___WORD *ra, int carry,
                                       ___frame_descriptor *frame)
{
  int internal;
  if (!remaining) return 0;
  if (!carry) *ra=___FP_STK(top,-___FRAME_STACK_RA);
  internal=*ra==___GSTATE->internal_return;
  if (internal && ___CAST(___SIZE_TS,-___RETI_RA)>=remaining) return 0;
  *frame=___decode_frame_descriptor(___LABEL_DESCR_GET(
    internal ? ___FP_STK(top,___RETI_RA) : *ra),internal);
  if (frame->fs<=0 || frame->link<0 || frame->link>=frame->fs ||
      ___CAST(___SIZE_TS,___FRAME_SPACE(frame->fs))>remaining) return 0;
  return 1;
}

/* Find the nearest marks in the owning half before reading any payload.
 * Between an END and the next START is a break or a capture-object gap. */
___HIDDEN ___WORD *raw_stack_span_end(const section_claim *claim, ___WORD *base,
                                     ___WORD *top)
{
  ___SIZE_TS index=top-base;
  ___SIZE_TS low=claim->raw_low-base, high=claim->raw_high-base;
  const unsigned char *marks=claim->raw_marks;
  ___SIZE_TS prev=index, next=index+1;

  while (prev>low && !raw_stack_mark_at(marks,prev))
    prev-=prev%4==3 && !marks[prev/4] && prev-low>=4 ? 4 : 1;
  if (raw_stack_mark_at(marks,prev)!=RAW_STACK_START) return 0;

  while (next<high && !raw_stack_mark_at(marks,next))
    next+=next%4==0 && !marks[next/4] && high-next>=4 ? 4 : 1;
  return raw_stack_mark_at(marks,next)==RAW_STACK_END ? base+next : 0;
}

___HIDDEN int read_admitted_stack_frame(const section_claim *claim,
                                        ___WORD *top, ___SIZE_TS half_words,
                                        ___WORD *logical_past,
                                        ___WORD *ra, int carry,
                                        ___frame_descriptor *frame,
                                        ___WORD **known_break_out)
{
  ___UWORD address=___CAST(___UWORD,top);
  if (!logical_past && claim->stack_state==STACK_PARKED && claim->parked_top &&
      address>=___CAST(___UWORD,claim->parked_top) &&
      address<=___CAST(___UWORD,claim->parked_break))
    logical_past=claim->parked_break;
  if (!logical_past && claim->raw_marks &&
      address>=___CAST(___UWORD,claim->raw_low) &&
      address<=___CAST(___UWORD,claim->raw_high))
    {
      ___WORD *base=top-((___MSECTION_SIZE>>1)-half_words);
      logical_past=raw_stack_span_end(claim,base,top);
      if (!logical_past) return 0;
    }
  if (!decode_source_stack_frame(top,logical_past ? logical_past-top : half_words,
                                 ra,carry,frame)) return 0;
  if (known_break_out) *known_break_out=logical_past;
  return 1;
}

___HIDDEN ___msection *read_source_stack_frame(___collector_worker *work,
                                              ___WORD *top,
                                              ___SIZE_TS source_offset,
                                              ___WORD *logical_past,
                                              ___WORD *ra, int carry,
                                              ___frame_descriptor *frame,
                                              ___SIZE_TS *half_words_out,
                                              ___WORD **known_break_out)
{
  ___SIZE_TS half_words;
  ___msection *section=admit_source_stack_span(work,top,source_offset,
                                               logical_past,&half_words);
  if (!section || !read_admitted_stack_frame(section_claim_at(section,source_offset),
        top,half_words,logical_past,ra,carry,frame,known_break_out)) return 0;
  if (half_words_out) *half_words_out=half_words;
  return section;
}

/* Once the producer supplies a logical end, an ordinary successor cannot
 * cross it. A copied suffix can already terminate via a forwarding link. */
___HIDDEN int source_break_agrees(___WORD *base, ___WORD *known_break, ___WORD link)
{
  if (___FIXNUMP(link)) return link!=___END_OF_CONT_MARKER;
  return !known_break || ((base==known_break)==(link==___GSTATE->handler_break));
}

/* Raw break links can be installed by a different carrier. The existing
 * raw-continuation publication keeps their frames resident. Resolve the
 * shared map under its allocation lock and keep the source section gate
 * across claim inspection, descriptor reads and link updates. Collection
 * cannot retire a half while this nonpolling mutator is running. */
___HIDDEN ___msection *lock_source_stack_frame
 (___processor_state ___ps, ___WORD *top, ___SIZE_TS *half_words,
  ___WORD *ra, ___frame_descriptor *frame, ___WORD **known_break)
{
  ___msection *section;
  const section_claim *claim;

  ALLOC_MEM_LOCK();
  section=resolve_source_half(the_msections,top,tospace_offset,half_words);
  if (section) ___gc_copy_acquire(&section->copy_gate);
  ALLOC_MEM_UNLOCK();
  if (!section) return 0;

  claim=section_claim_at(section,tospace_offset);
  if (!source_claim_is_live(claim) ||
      !read_admitted_stack_frame(claim,top,*half_words,0,ra,0,frame,known_break))
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }
  return section;
}

___WORD ___restore_stack_break_frame(___processor_state ___ps, ___WORD *top,
                                     ___WORD **stack_cursor)
{
  ___SIZE_TS half_words, words;
  ___msection *section;
  ___WORD *known_break, *base, *dest=*stack_cursor;
  ___WORD ra, next;
  ___frame_descriptor frame;
  int i;

  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&frame,&known_break);
  if (!section) goto refused;
  words=___FRAME_SPACE(frame.fs);
  base=top+words;
  next=___FP_STK(base,frame.link+1);
  if (___FIXNUMP(next) || !source_break_agrees(base,known_break,next) ||
      half_words-words <= (next==___GSTATE->handler_break ? ___BREAK_FRAME_NEXT : 0))
    goto release_and_refuse;

  if (ra==___GSTATE->internal_return) {
    ___COVER_BREAK_HANDLER_STACK_RETI;
  } else {
    ___COVER_BREAK_HANDLER_STACK_RETN;
  }
  for (i=frame.fs;i>0;i--)
    ___FP_SET_STK(dest,i,___FP_STK(base,i))
  if (next==___GSTATE->handler_break) {
    ___COVER_BREAK_HANDLER_STACK_FIRST_FRAME;
    ___FP_SET_STK(dest,-___BREAK_FRAME_NEXT,___FP_STK(base,-___BREAK_FRAME_NEXT))
  } else {
    ___COVER_BREAK_HANDLER_STACK_NOT_FIRST_FRAME;
    ___FP_SET_STK(base,-___FRAME_STACK_RA,next)
    ___FP_SET_STK(dest,-___BREAK_FRAME_NEXT,___CAST(___WORD,base))
    ___FP_SET_STK(dest,frame.link+1,___GSTATE->handler_break)
  }
  *stack_cursor=dest-words;
  ___gc_copy_release(&section->copy_gate);
  return ra;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Break restore source frame is outside its stack grant");
  return ___FAL;
}

/* Inspect or change one raw frame under the same gate as restore. A
 * debugger payload write must not alter the chain or saved descriptor. */
___SCMOBJ ___access_raw_continuation_frame
 (___processor_state ___ps, ___SCMOBJ raw, enum ___raw_frame_operation op,
  ___SCMOBJ index, ___SCMOBJ value)
{
  ___WORD *top, *base, *known_break, ra;
  ___SIZE_TS half_words, words;
  ___msection *section;
  ___frame_descriptor frame;
  ___SCMOBJ result;
  ___WORD slot=0;

  if (raw==___END_OF_CONT_MARKER || !___FIXNUMP(raw))
    {
      rc_contract_error("Reflective continuation cursor is not a raw stack frame");
      return ___FAL;
    }
  top=___CAST(___WORD*,raw);
  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&frame,&known_break);
  if (!section)
    {
      rc_contract_error("Reflective continuation frame is outside its stack section");
      return ___FAL;
    }

  if (op==___RAW_FRAME_LIVE || op==___RAW_FRAME_REF || op==___RAW_FRAME_SET)
    {
      if (___FIXNUMP(index)) slot=___INT(index);
      if (slot<=0 || slot>frame.fs)
        {
          if (op!=___RAW_FRAME_LIVE) goto release_and_refuse;
          ___gc_copy_release(&section->copy_gate);
          return ___FAL;
        }
    }

  words=___FRAME_SPACE(frame.fs);
  base=top+words;
  switch (op)
    {
    case ___RAW_FRAME_RET:
      result=ra==___GSTATE->internal_return ? ___FP_STK(top,___RETI_RA) : ra;
      break;
    case ___RAW_FRAME_FS:
      result=___FIX(frame.fs);
      break;
    case ___RAW_FRAME_LINK:
      result=___FIX(frame.link+1);
      break;
    case ___RAW_FRAME_LIVE:
      result=___BOOLEAN(___frame_slot_live(&frame,slot));
      break;
    case ___RAW_FRAME_REF:
      result=___FP_STK(base,slot);
      break;
    case ___RAW_FRAME_SET:
      if (slot==frame.link+1 ||
          (ra==___GSTATE->internal_return && slot==words+___RETI_RA))
        goto release_and_refuse;
      ___FP_SET_STK(base,slot,value)
      result=___VOID;
      break;
    default:
      goto release_and_refuse;
    }
  ___gc_copy_release(&section->copy_gate);
  return result;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Reflective continuation slot is outside its stack grant");
  return ___FAL;
}

/* The caller owns cont as a mutable cursor. Shared stack words are
 * serialized with other raw mutators by the same gate as break restore.
 * A raw NEXT at a break is copied as an edge, without reading its target. */
___WORD ___continuation_next_stack(___processor_state ___ps, ___SCMOBJ cont)
{
  enum { dynamic_env_slot = 2 };
  ___SCMOBJ raw=___CONTINUATION_FRAME_FIELD(cont);
  ___SCMOBJ denv, successor;
  ___WORD *top, *base, *known_break, ra, next;
  ___SIZE_TS half_words, words;
  ___msection *section;
  ___frame_descriptor frame;
  int at_break;

  if (raw==___END_OF_CONT_MARKER) return ___FAL;
  if (!___FIXNUMP(raw)) goto refused;
  top=___CAST(___WORD*,raw);
  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&frame,&known_break);
  if (!section) goto refused;

  words=___FRAME_SPACE(frame.fs);
  base=top+words;
  next=___FP_STK(base,frame.link+1);
  at_break=next==___GSTATE->handler_break;
  if (___FIXNUMP(next) || !source_break_agrees(base,known_break,next) ||
      half_words-words <= (at_break ? ___BREAK_FRAME_NEXT : 0))
    goto release_and_refuse;

  denv=___CONTINUATION_DENV_FIELD(cont);
  if (ra==___ps->dynamic_env_bind_return)
    {
      if (frame.fs<dynamic_env_slot) goto release_and_refuse;
      denv=___FP_STK(base,dynamic_env_slot);
    }
  if (at_break)
    successor=___FP_STK(base,-___BREAK_FRAME_NEXT);
  else
    {
      ___FP_SET_STK(base,-___FRAME_STACK_RA,next)
      successor=___CAST(___SCMOBJ,base);
    }
  if (successor==___END_OF_CONT_MARKER)
    cont=___FAL;
  else
    {
      ___CONTINUATION_FRAME_FIELD(cont)=successor;
      ___CONTINUATION_DENV_FIELD(cont)=denv;
    }
  ___gc_copy_release(&section->copy_gate);
  return cont;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Reflective continuation source frame is outside its stack grant");
  return ___FAL;
}

/* Caller owns frame access across the initial read, source-frame forwarding,
 * root repairs and every destination-link update. No collector waits for
 * frame access while still holding a FIFO gate. */
___HIDDEN void mark_captured_continuation_locked
   ___P((___collector_worker *work,
         ___WORD *orig_ptr),
        (work,
         orig_ptr)
___collector_worker *work;
___WORD *orig_ptr;)
{
  ___processor_state ___ps = work->carrier;
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

      ___WORD *alloc = work->arena.cursor;
      ___SIZE_TS source_offset=(___MSECTION_SIZE>>1)-
        ___COLLECTION(work->vm).destination_offset;
      ___SIZE_TS half_words;
      ___frame_descriptor frame;
      ___WORD *source, *known_break, *logical_past=0;
      ___msection *section;

      next_frame:

      source=___CAST(___WORD*,cf);
      section=read_source_stack_frame(work,source,source_offset,
                                      logical_past,&ra1,0,&frame,&half_words,&known_break);
      if (!section) {
        rc_contract_error("GC captured frame is outside its source stack grant");
        return;
      }
      fs=frame.fs;
      link=frame.link;
      fp=source+___FRAME_SPACE(fs);
      ra2=___FP_STK(fp,link+1);
      if (!source_break_agrees(fp,known_break,ra2)) {
        rc_contract_error("GC captured successor disagrees with its parked break");
        return;
      }
      if (ra2==___GSTATE->handler_break &&
          half_words-___FRAME_SPACE(fs)<=___BREAK_FRAME_NEXT) {
        rc_contract_error("GC captured break link is outside its source stack grant");
        return;
      }

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

      if (ra1 == ___GSTATE->internal_return) {
        ___COVER_MARK_CAPTURED_CONTINUATION_RETI;
      } else {
        ___COVER_MARK_CAPTURED_CONTINUATION_RETN;
      }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", fs, link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

      if (___FIXNUMP(ra2))
        {
          ___COVER_MARK_CAPTURED_CONTINUATION_ALREADY_COPIED;
          *ptr = ra2; /* already copied, replace by forwarding pointer */
          work->frame_links_++;
        }
      else
        {
          ___WORD forw;
          ___WORD *copy_header;
          ___SIZE_TS words;
          ___copy_reservation grant;

          ___COVER_MARK_CAPTURED_CONTINUATION_COPY;

          words = fs + ___FRAME_EXTRA_SLOTS;

          prepare_copy_request(work,section,source,___FRAME_SPACE(fs),words,0,1);
          grant = reserve_copy(work,alloc,words,0);
          alloc = grant.header;

          /*TODO: add allocation of handle if using handles*/

          copy_header = alloc;
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
              logical_past = 0;
            }
          else
            {
              /* not the first frame of that section */

              ___COVER_MARK_CAPTURED_CONTINUATION_NOT_FIRST_FRAME;

              ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
              cf = ___CAST(___WORD,fp);
              logical_past = known_break;
            }

          ___FP_SET_STK(alloc,link+1,cf)
          ___FP_SET_STK(fp,link+1,forw) /* leave a forwarding pointer */

          *ptr = forw;
          work->frame_links_++;

          publish_object_scan (work, copy_header);
          work->copied_words += words+___SUBTYPED_BODY;
          commit_copy(work,&grant);

          ptr = &___FP_STK(alloc,link+1);

          if (alloc >= alloc_heap_chunk_limit)
            {
              work->arena.cursor = alloc;
              end_heap_chunk (work);
              start_heap_chunk (work);
              alloc = work->arena.cursor;
            }

          if (___FIXNUMP(cf) && cf != ___END_OF_CONT_MARKER)
            goto next_frame;
        }

      *orig_ptr = ___TAG(___UNTAG_AS(*orig_ptr, ___tFIXNUM), ___tSUBTYPED);

      work->arena.cursor = alloc;

    }
  else
    mark_array (work, orig_ptr, 1);
}

___HIDDEN void mark_captured_continuation
   ___P((___collector_worker *work, ___WORD *orig_ptr), (work, orig_ptr)
___collector_worker *work;
___WORD *orig_ptr;)
{
  if(work->census!=0) { census_capture(work,orig_ptr);return; }
  acquire_frame_access(work);
  mark_captured_continuation_locked(work,orig_ptr);
  release_frame_access(work);
}


___HIDDEN void mark_frame
   ___P((___collector_worker *work,
         ___WORD *fp,
         const ___frame_descriptor *frame),
        (work,
         fp,
         frame)
___collector_worker *work;
___WORD *fp;
const ___frame_descriptor *frame;)
{
  ___frame_root_cursor cursor = ___frame_ordinary_root_begin (frame);
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
      mark_array (work, &___FP_STK(fp,past-1), past-first);
    }
}


___HIDDEN void mark_continuation
   ___P((___collector_worker *work, ___execution_context *context),
        (work, context)
___collector_worker *work;
___execution_context *context;)
{
  ___processor_state ___ps = work->carrier;
  ___frame_descriptor descriptor;
  ___WORD *fp;
  ___WORD ra1;
  ___WORD ra2;
  ___SIZE_TS half_words;
  ___msection *section;
  section_claim *claim;
  ___SIZE_TS source_offset=(___MSECTION_SIZE>>1)-
    ___COLLECTION(work->vm).destination_offset;

  acquire_frame_access(work);
#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_CONTINUATION;
#endif

  fp = context->fp;
  section=admit_source_stack_span(work,fp,source_offset,context->stack_break,&half_words);
  claim=section ? section_claim_at(section,source_offset) : 0;
  if (!context->stack_break || !claim || claim->stack_state!=STACK_ACTIVE ||
      claim->stack_owner->context!=context ||
      half_words-(context->stack_break-fp)<=___BREAK_FRAME_NEXT) {
    release_frame_access(work);
    rc_contract_error("GC active break link is outside its source stack grant");
    return;
  }

#ifdef SHOW_FRAMES
  ___printf ("mark_continuation fp=%p\n", fp);
#endif

  if (fp != context->stack_break)
    for (;;)
      {
        if (!decode_source_stack_frame(fp,context->stack_break-fp,&ra1,0,&descriptor)) {
          release_frame_access(work);
          rc_contract_error("GC active frame is outside its source stack grant");
          return;
        }

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

        if (ra1 == ___GSTATE->internal_return)
          {
            ___COVER_MARK_CONTINUATION_RETI;
          }
        else
          {
            ___COVER_MARK_CONTINUATION_RETN;
          }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", descriptor.fs, descriptor.link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

        fp+=___FRAME_SPACE(descriptor.fs);

        ra2 = ___FP_STK(fp,descriptor.link+1);

#ifdef SHOW_FRAMES
        if (fp == context->stack_break)
          ___printf ("  (first frame above break frame)\n");
#endif

        mark_frame (work, fp, &descriptor);

        if (fp == context->stack_break)
          break;

        ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
      }

  mark_captured_continuation_locked (work, &___FP_STK(fp,-___BREAK_FRAME_NEXT));
  release_frame_access(work);
}


/* End internal memory fragment. */

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
  if(___ps->collector==0 && source->fp==source->stack_break &&
     ___FP_STK(source->stack_break,-___BREAK_FRAME_NEXT)==___END_OF_CONT_MARKER) {
    task->state=___ROOT_SCANNED;return 1;
  }
  if(___ps->collector==0) rc_contract_error("Active frame scan requires a collector worker");
  mark_continuation (___ps->collector, source);
  task->state=___ROOT_SCANNED;
  return 1;
}


/* End internal memory fragment. */
