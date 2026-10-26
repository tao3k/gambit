#line 3468 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

#ifdef ENABLE_CONSISTENCY_CHECKS

#define mark_array(start,n) mark_array_debug (start,n,__LINE__)

___HIDDEN void mark_array_debug
   ___P((___PSD
         ___WORD *start,
         ___WORD n,
         int line),
        (___PSV
         start,
         n,
         line)
___PSDKR
___WORD *start;
___WORD n;
int line;)

#else

___HIDDEN void mark_array
   ___P((___PSD
         ___WORD *start,
         ___WORD n),
        (___PSV
         start,
         n)
___PSDKR
___WORD *start;
___WORD n;)

#endif
{
  ___PSGET
  ___WORD *alloc = alloc_heap_ptr;
  ___WORD *limit = alloc_heap_limit;

#ifdef ENABLE_CONSISTENCY_CHECKS
  mark_array_call_line = line;
#endif

  while (n-- > 0)
    {
      ___WORD *cell = start++;

    again: /* looping back here is possible when tail marking */
      {
        ___WORD obj = *cell;

        if (___MEM_ALLOCATED(obj))
          {
            ___WORD *body;
            ___WORD head;
            int head_typ;
            int subtype;

#ifdef ENABLE_CONSISTENCY_CHECKS
            if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
              validate_old_obj (___PSP obj);
#endif

            body = ___BODY0(obj);
            head = body[-1];
            subtype = ___HD_SUBTYPE(head);
            head_typ = ___HD_TYP(head);

            if (head_typ == ___MOVABLE0)
              {
                ___SIZE_TS words = ___HD_WORDS(head);

                /*TODO: add allocation of handle if using handles*/
#if ___WS == 4
                ___BOOL pad = 0;
                while (alloc + words + (subtype >= ___sS64VECTOR ? 2 : 1) >
                       limit)
#else
                while (alloc + words + 1 > limit)
#endif
                  {
                    alloc_heap_ptr = alloc;
                    end_heap_chunk (___ps);
                    next_heap_msection (___ps);
                    prepare_heap_msection (___ps);
                    alloc = alloc_heap_ptr;
                    limit = alloc_heap_limit;
                  }
#if ___WS != 8
                /*
                 * ___sS64VECTOR, ___sU64VECTOR, ___sF64VECTOR,
                 * ___sFLONUM and ___sBIGNUM need to be aligned on a
                 * multiple of 8.
                 */
                if (subtype >= ___sS64VECTOR)
                  {
                    if ((___CAST(___WORD,alloc) & (8-1)) == 0)
                      *alloc++ = ___MAKE_HD_WORDS(0, ___sVECTOR);
                    else
                      pad = 1;
                  }
#endif
                *alloc++ = head;

#ifdef ___SINGLE_THREADED_VMS

                body[-1] = ___TAG(alloc - ___REFERENCE_TO_BODY, ___FORW);

#else

                {
                  ___WORD head_now =
                    ___COMPARE_AND_SWAP_WORD(&body[-1],
                                             head,
                                             ___TAG(alloc - ___REFERENCE_TO_BODY, ___FORW));

                  if (head_now != head)
                    {
                      /*
                       * Other processor forwarded the object first so
                       * the allocation must be undone and head_now is
                       * the correct forwarding pointer.
                       */

                      alloc--;
                      *cell = ___TAG(___UNTAG_AS(head_now, ___FORW), ___TYP(obj));
                      continue;
                    }
                }

#endif

                *cell = ___TAG(alloc - ___REFERENCE_TO_BODY, ___TYP(obj));

                if (words > 0 && subtype <= ___sBOXVALUES)
                  cell = alloc;
                else
                  cell = 0;

                while (words > 0)
                  {
                    *alloc++ = *body++;
                    words--;
                  }
#if ___WS == 4
                if (pad)
                  *alloc++ = ___MAKE_HD_WORDS(0, ___sVECTOR);
#endif
                if (alloc >= alloc_heap_chunk_limit)
                  {
                    alloc_heap_ptr = alloc;
                    end_heap_chunk (___ps);
                    start_heap_chunk (___ps);
                    alloc = alloc_heap_ptr;
                  }

                if (cell != 0) goto again;
              }
            else if (head_typ == ___STILL)
              {
#ifdef ___SINGLE_THREADED_VMS

                if (body[___STILL_MARK - ___STILL_BODY] == -1)
                  {
                    body[___STILL_MARK - ___STILL_BODY]
                      = ___CAST(___WORD,still_objs_to_scan);
                    still_objs_to_scan
                      = ___CAST(___WORD,body - ___STILL_BODY);
                  }

#else

                if (___COMPARE_AND_SWAP_WORD(&body[___STILL_MARK - ___STILL_BODY],
                                             -1,
                                             ___CAST(___WORD,still_objs_to_scan))
                    == -1)
                  {
                    still_objs_to_scan
                      = ___CAST(___WORD,body - ___STILL_BODY);
                  }
#endif
              }
            else if (___TESTTYPE(head_typ, ___FORW))
              {
                *cell = ___TAG(___UNTAG_AS(head, ___FORW), ___TYP(obj));
              }
#ifdef ENABLE_CONSISTENCY_CHECKS
            else if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1 &&
                     head_typ != ___PERM)
              bug (___PSP obj, 0, "was not ___PERM, ___STILL, ___MOVABLE0 or ___FORW");
#endif
          }
      }
    }

  alloc_heap_ptr = alloc;
}


/* End internal memory fragment. */
