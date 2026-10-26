#line 3950 ___MEM_SOURCE_FILE
___HIDDEN ___SIZE_TS scan
   ___P((___PSD
         ___WORD *body,
         ___WORD head),
        (___PSV
         body,
         head)
___PSDKR
___WORD *body;
___WORD head;)
{
  ___PSGET
  ___SIZE_TS words = ___HD_WORDS(head);
  int subtype = ___HD_SUBTYPE(head);

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
            mark_array (___PSP body+1, 2); /* scan action and testator */
          else
            {
              mark_array (___PSP body+2, 1); /* scan action only */

              /*
               * Remember that this will's testator object remains to
               * be marked by the process_wills function.
               */

              body[0] = body[0] | ___UNMARKED_TESTATOR_WILL;
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
                  mark_array (___PSP body+i, 1); /* repair this key in place */
                  if (body[i] != key)
                    body[___GCHASHTABLE_FLAGS] =
                      ___FIXIOR(body[___GCHASHTABLE_FLAGS],
                                ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED));
                }
            }

          if ((flags & ___GCHASHTABLE_FLAG_WEAK_VALS) == 0)
            {
              for (i=words-1; i>=___GCHASHTABLE_VAL0; i-=2)
                mark_array (___PSP body+i, 1); /* mark objects in value fields */
            }

          body[0] = reached_gc_hash_tables;
          reached_gc_hash_tables = ___CAST(___WORD,body);
        }
      break;

    case ___sSYMBOL:
    case ___sKEYWORD:
      mark_array (___PSP body, 1); /* only scan name of symbols & keywords */
      break;

    case ___sCONTINUATION:
      mark_captured_continuation (___PSP &body[___CONTINUATION_FRAME]);
      mark_array (___PSP body+1, words-1); /* skip the frame pointer */
      break;

    case ___sFRAME:
      {
        ___frame_descriptor descriptor;
        ___WORD *fp = body + ___FRAME_EXTRA_SLOTS;
        ___WORD ra = body[0];
        ___WORD frame;

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

        fp += descriptor.fs;

        frame = ___FP_STK(fp,descriptor.link+1);

        if (___FIXNUMP(frame) && frame != ___END_OF_CONT_MARKER)
          ___FP_SET_STK(fp,descriptor.link+1,___FAL)

        mark_frame (___PSP fp, &descriptor);

        if (___FIXNUMP(frame) && frame != ___END_OF_CONT_MARKER)
          ___FP_SET_STK(fp,descriptor.link+1,___TAG(___UNTAG_AS(frame, ___tFIXNUM), ___tSUBTYPED))

        mark_array (___PSP &body[0], 1);
      }
      break;

    case ___sPROCEDURE:

      /*
       * The object can only be a closure (nonclosures are permanent objects).
       */

#ifdef ___SUPPORT_LOWLEVEL_EXEC

      /* update the closure's lowlevel code trampoline */

      ___CLO_LOWLEVEL_TRAMPOLINE_SETUP(body,
                                       body[___LABEL_ENTRY_OR_DESCR]);

#endif

      /* only need to scan the free variables */

      mark_array (___PSP body+___CLO_FREEVARS, words-___CLO_FREEVARS);

      break;

    default:

      if (___HD_TYP(head) == ___MOVABLE0 && subtype <= ___sBOXVALUES)
        mark_array (___PSP body+1, words-1);
      else
        mark_array (___PSP body, words);

      break;
    }

  return words;
}


#define scan_no_fast_path(ptr, head) \
do { \
  ptr += scan (___PSP (ptr)+1, head) + 1; \
} while (0)


#ifdef ___USE_SCAN_NO_FAST_PATH

#define scan_and_advance(ptr, head) scan_no_fast_path(ptr, head)

#else

#define scan_and_advance(ptr, head) \
do { \
  if ((head) == ___MAKE_HD_WORDS(___PAIR_SIZE,___sPAIR)) \
    { \
      mark_array (___PSP (ptr)+2, ___PAIR_SIZE-1); \
      ptr += ___PAIR_SIZE+1; \
    } \
  else \
    scan_no_fast_path(ptr, head); \
} while (0)

#endif


___HIDDEN void setup_still_objs_to_scan
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *base = ___CAST(___WORD*,still_objs);
  ___WORD *to_scan = 0;

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
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *base;

  while ((base = ___CAST(___WORD*,still_objs_to_scan)) != 0)
    {
      ___WORD *body = base + ___STILL_BODY;
      still_objs_to_scan = base[___STILL_MARK];
      scan (___PSP body, body[-1]);
    }
}


___HIDDEN void scan_complete_heap_chunk
   ___P((___PSD
         ___WORD *start),
        (___PSV
         start)
___PSDKR
___WORD *start;)
{
  ___PSGET
  ___WORD *ptr = start;
  ___WORD head;

#ifdef ENABLE_GC_ACTLOG_SCAN_COMPLETE_HEAP_CHUNK
  ___ACTLOG_BEGIN_PS(scan_complete_heap_chunk,_);
#endif

  while (!___TESTTYPE(head = *ptr, ___FORW)) /* not end of complete chunk? */
    {
      scan_and_advance(ptr, head); /* note: this advances ptr */
    }

#ifdef ENABLE_GC_ACTLOG_SCAN_COMPLETE_HEAP_CHUNK
  ___ACTLOG_END_PS();
#endif
}


___HIDDEN void scan_movable_objs_to_scan
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

  /*

    SITUATION #1: scanning a complete chunk

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                 ^                                  ^
          scan_ptr                                  alloc_heap_ptr


    SITUATION #2: scanning the incomplete chunk

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                                         ^          ^
                                  scan_ptr          alloc_heap_ptr


    SITUATION #3: done scanning all movable objects

     chunk 1  chunk 2   chunk 3   incomplete chunk
    +-------+---------+---------+------------------+-----
    |L      |L        |L        |L                 |
    +-------+---------+---------+------------------+-----
                                                    ^
                                            scan_ptr alloc_heap_ptr

     L = link to next chunk tagged with ___FORW

   */

  ___WORD *ptr = scan_ptr;
  ___VOLATILE ___WORD *hcsh;

  while (ptr != alloc_heap_ptr) /* SITUATION #1 or #2 ? */
    {
      ___WORD head;
      while (!___TESTTYPE(head = *ptr, ___FORW)) /* not end of complete chunk? */
        {
          scan_and_advance(ptr, head); /* note: this advances ptr */
          if (ptr == alloc_heap_ptr) /* end of incomplete chunk? */
            {
              /* SITUATION #3, done scanning all movable objects */
              scan_ptr = ptr;
              return;
            }
        }

      scan_ptr = ptr; /* remember where scan ended */

      /*
       * SITUATION #1, at end of complete chunk.
       */

#ifndef ___SINGLE_THREADED_VMS
      ___SPINLOCK_LOCK(heap_chunks_to_scan_lock);
#endif

      while ((hcsh=heap_chunks_to_scan_head) != heap_chunks_to_scan_tail)
        {
          /*
           * Get the next complete heap chunk from heap chunk FIFO and
           * scan it.
           */

          ptr = ___UNTAG_AS(*hcsh, ___FORW);

          heap_chunks_to_scan_head = ptr;

          ___SHARED_MEMORY_BARRIER(); /* share heap_chunks_to_scan_head */

#ifndef ___SINGLE_THREADED_VMS
          ___SPINLOCK_UNLOCK(heap_chunks_to_scan_lock);
#endif

          scan_complete_heap_chunk (___PSP ptr+1);

#ifndef ___SINGLE_THREADED_VMS
          ___SPINLOCK_LOCK(heap_chunks_to_scan_lock);
#endif
        }

#ifndef ___SINGLE_THREADED_VMS
      ___SPINLOCK_UNLOCK(heap_chunks_to_scan_lock);
#endif

      /*
       * Scan the incomplete heap chunk currently being created.
       */

      ptr = alloc_heap_chunk_start;

      scan_ptr = ptr;
    }
}


/* End internal memory fragment. */
