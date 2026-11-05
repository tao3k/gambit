#line 4389 ___MEM_SOURCE_FILE
___HIDDEN ___SIZE_TS scan
   ___P((___collector_worker *work,
         ___WORD *body,
         ___WORD head),
        (work,
         body,
         head)
___collector_worker *work;
___WORD *body;
___WORD head;)
{
  ___processor_state ___ps = work->carrier;
  ___SIZE_TS words = ___HD_WORDS(head);
  int subtype = ___HD_SUBTYPE(head);
  ___BOOL movable = ___HD_TYP(head) == ___MOVABLE0;

  if (movable && work->census==0)
    {
      int state = change_object_scan_state
        (work,body-1,GC_SCAN_READY,GC_SCAN_OWNED);
      if (state == GC_SCAN_OWNED || state == GC_SCAN_DONE)
        {
          work->duplicate_scans++;
          return words; /* no field mutation; the first owner carries debt */
        }
      if (state != GC_SCAN_READY)
        {
          static char *msgs[] = { "GC scan before object initialization", NULL };
          ___fatal_error (msgs);
        }
    }

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_OBJECT;
  container_body = body;
#endif

  switch (subtype)
    {
    case ___sFOREIGN:
    case ___sSTRING:
    case ___sS8VECTOR:
    case ___sU8VECTOR:
    case ___sS16VECTOR:
    case ___sU16VECTOR:
    case ___sS32VECTOR:
    case ___sU32VECTOR:
    case ___sS64VECTOR:
    case ___sU64VECTOR:
    case ___sF32VECTOR:
    case ___sF64VECTOR:
    case ___sFLONUM:
    case ___sBIGNUM:
      break;

    case ___sWEAK:
      if (words == ___WILL_SIZE)
        {
          /* Object is a will */

          /*
           * The will contains a weak reference to its testator object
           * and a strong reference to the action procedure.
           * Consequently, the action procedure must be marked and,
           * only if traverse_weak_refs is true, the testator object
           * is also marked.  The link field is never scanned.
           */

          if (traverse_weak_refs)
            mark_array (work, body+1, 2); /* scan action and testator */
          else
            {
              mark_array (work, body+2, 1); /* scan action only */

              /*
               * Remember that this will's testator object remains to
               * be marked by the process_wills function.
               */

              if(work->census==0) body[0] = body[0] | ___UNMARKED_TESTATOR_WILL;
            }
        }
      else
        {
          /* Object is a GC hash table */

          int flags = ___INT(body[___GCHASHTABLE_FLAGS]);
          int i;

          if ((flags & ___GCHASHTABLE_FLAG_WEAK_KEYS) == 0 &&
              (flags & ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS))
            {
              for (i=words-2; i>=___GCHASHTABLE_KEY0; i-=2)
                {
                  ___SCMOBJ key = body[i];
                  mark_array (work, body+i, 1); /* repair this key in place */
                  if (body[i] != key)
                    body[___GCHASHTABLE_FLAGS] =
                      ___FIXIOR(body[___GCHASHTABLE_FLAGS],
                                ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED));
                }
            }

          if ((flags & ___GCHASHTABLE_FLAG_WEAK_VALS) == 0)
            {
              for (i=words-1; i>=___GCHASHTABLE_VAL0; i-=2)
                mark_array (work, body+i, 1); /* mark objects in value fields */
            }

          if(work->census==0) { body[0] = reached_gc_hash_tables;
            reached_gc_hash_tables = ___CAST(___WORD,body); }
        }
      break;

    case ___sSYMBOL:
    case ___sKEYWORD:
      mark_array (work, body, 1); /* only scan name of symbols & keywords */
      break;

    case ___sCONTINUATION:
      mark_captured_continuation (work, &body[___CONTINUATION_FRAME]);
      mark_array (work, body+1, words-1); /* skip the frame pointer */
      break;

    case ___sFRAME:
      {
        ___frame_descriptor descriptor;
        ___WORD *fp = body + ___FRAME_EXTRA_SLOTS;
        ___WORD ra = body[0];
        ___WORD frame;

        acquire_frame_access(work);

#ifdef SHOW_FRAMES
        ___printf ("___sFRAME object\n");
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra);
#endif

        if (ra == ___GSTATE->internal_return)
          {
            ___WORD actual_ra = body[___FRAME_RETI_RA];
            descriptor = ___decode_frame_descriptor (___LABEL_DESCR_GET(actual_ra), 1);
            ___COVER_SCAN_FRAME_RETI;
          }
        else
          {
            descriptor = ___decode_frame_descriptor (___LABEL_DESCR_GET(ra), 0);
            ___COVER_SCAN_FRAME_RETN;
          }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", descriptor.fs, descriptor.link, fp);
        print_value (ra);
        ___printf ("\n");
#endif

        if (descriptor.fs <= 0 || descriptor.link < 0 ||
            descriptor.link >= descriptor.fs ||
            words != descriptor.fs+___FRAME_EXTRA_SLOTS)
          {
            static char *msgs[] = { "GC frame payload/descriptor mismatch", NULL };
            ___fatal_error(msgs);
          }

        fp += descriptor.fs;

        frame = ___FP_STK(fp,descriptor.link+1);

        mark_frame (work, fp, &descriptor);

        if (work->census!=0)
          census_capture(work,&___FP_STK(fp,descriptor.link+1));
        else if (___FIXNUMP(frame) && frame != ___END_OF_CONT_MARKER)
          ___FP_SET_STK(fp,descriptor.link+1,___TAG(___UNTAG_AS(frame, ___tFIXNUM), ___tSUBTYPED))
        else
          mark_array(work,&___FP_STK(fp,descriptor.link+1),1);

        mark_array (work, &body[0], 1);
        release_frame_access(work);
      }
      break;

    case ___sPROCEDURE:

      /*
       * The object can only be a closure (nonclosures are permanent objects).
       */

#ifdef ___SUPPORT_LOWLEVEL_EXEC

      /* update the closure's lowlevel code trampoline */

      if(work->census==0) ___CLO_LOWLEVEL_TRAMPOLINE_SETUP(body,
                                       body[___LABEL_ENTRY_OR_DESCR]);

#endif

      /* only need to scan the free variables */

      mark_array (work, body+___CLO_FREEVARS, words-___CLO_FREEVARS);

      break;

    default:

      if (work->census==0 && ___HD_TYP(head) == ___MOVABLE0 && subtype <= ___sBOXVALUES)
        mark_array (work, body+1, words-1);
      else
        mark_array (work, body, words);

      break;
    }

  if (work->census==0 && movable &&
      change_object_scan_state(work,body-1,GC_SCAN_OWNED,GC_SCAN_DONE)
      != GC_SCAN_OWNED)
    {
      static char *msgs[] = { "GC scan owner lost before completion", NULL };
      ___fatal_error (msgs);
    }
  return words;
}


#define scan_no_fast_path(ptr, head) \
do { \
  work->active_scan_object_ = (ptr)+1; \
  ptr += scan (work, (ptr)+1, head) + 1; \
  work->active_scan_object_ = 0; \
} while (0)


/* Pair and general scanning consume the same object authority. The previous
 * pair macro mutated a field without going through the scan owner. */
#define scan_and_advance(ptr, head) scan_no_fast_path(ptr, head)


___HIDDEN void setup_still_objs_to_scan
   ___P((___collector_worker *work, ___processor_state source),
        (work, source)
___collector_worker *work;
___processor_state source;)
{
  ___processor_state ___ps = work->carrier;
  ___WORD *base = ___CAST(___WORD*,source->mem.still_objs_);
  ___WORD *to_scan = ___CAST(___WORD*,still_objs_to_scan);

  while (base != 0)
    {
      if (base[___STILL_REFCOUNT] == 0)
        base[___STILL_MARK] = -1;
      else
        {
          base[___STILL_MARK] = ___CAST(___WORD,to_scan);
          to_scan = base;
        }
      base = ___CAST(___WORD*,base[___STILL_LINK]);
    }

  still_objs_to_scan = ___CAST(___WORD,to_scan);
}


___HIDDEN void scan_still_objs_to_scan
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps = work->carrier;
  ___WORD *base;

  while ((base = ___CAST(___WORD*,still_objs_to_scan)) != 0)
    {
      ___WORD *body = base + ___STILL_BODY;
      still_objs_to_scan = base[___STILL_MARK];
      scan (work, body, body[-1]);
    }
}


___HIDDEN void scan_complete_heap_chunk
   ___P((___collector_worker *work,
         ___WORD *start,
         int origin),
        (work,
         start,
         origin)
___collector_worker *work;
___WORD *start;
int origin;)
{
  ___processor_state ___ps = work->carrier;
  ___WORD *ptr = start;
  ___WORD head;

  work->active_scan_chunk_ = start;
  work->scan_origin_ = origin;

#ifdef ENABLE_GC_ACTLOG_SCAN_COMPLETE_HEAP_CHUNK
  ___ACTLOG_BEGIN_PS(scan_complete_heap_chunk,_);
#endif

  while (!___TESTTYPE(head = *ptr, ___FORW)) /* not end of complete chunk? */
    {
      scan_and_advance(ptr, head); /* note: this advances ptr */
    }

  require_chunk_transition(work,start,2,3);
  work->chunks_completed_++;
  work->active_scan_chunk_ = 0;
  work->scan_origin_ = 0;

#ifdef ENABLE_GC_ACTLOG_SCAN_COMPLETE_HEAP_CHUNK
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void scan_movable_objs_to_scan
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps = work->carrier;

  /*

    SITUATION #1: scanning a complete chunk

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                 ^                                  ^
          scan_ptr                                  work->arena.cursor


    SITUATION #2: scanning the incomplete chunk

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                                         ^          ^
                                  scan_ptr          work->arena.cursor


    SITUATION #3: done scanning all movable objects

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                                                    ^
                                            scan_ptr work->arena.cursor

     L = link to next chunk tagged with ___FORW

   */

  ___WORD *ptr = scan_ptr;

  while (ptr != work->arena.cursor) /* SITUATION #1 or #2 ? */
    {
      ___WORD head;
      work->active_scan_chunk_ = work->local_scan_chunk_;
      work->scan_origin_ = 1;
      while (!___TESTTYPE(head = *ptr, ___FORW)) /* not end of complete chunk? */
        {
          scan_and_advance(ptr, head); /* note: this advances ptr */
          if (ptr == work->arena.cursor) /* end of incomplete chunk? */
            {
              /* SITUATION #3, done scanning all movable objects */
              scan_ptr = ptr;
              work->active_scan_chunk_ = 0;
              work->scan_origin_ = 0;
              return;
            }
        }

      scan_ptr = ptr; /* remember where scan ended */
      require_chunk_transition(work,work->local_scan_chunk_,2,3);
      work->chunks_completed_++;
      work->local_scan_chunk_ = 0;
      work->active_scan_chunk_ = 0;
      work->scan_origin_ = 0;

      /*
       * SITUATION #1, at end of complete chunk.
       */

      while ((ptr=take_heap_chunk(work,work)) != 0)
        {
          /*
           * Get the next complete heap chunk from heap chunk FIFO and
           * scan it.
           */

          scan_complete_heap_chunk (work, ptr, 2);
        }

      /*
       * Scan the incomplete heap chunk currently being created.
       */

      ptr = alloc_heap_chunk_start;

      require_chunk_transition(work,ptr,0,2);
      work->local_scan_chunk_ = ptr;

      scan_ptr = ptr;
    }
}


/* End internal memory fragment. */
