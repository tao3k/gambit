#line 4334 ___MEM_SOURCE_FILE
___HIDDEN void free_unmarked_still_objs
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *last = &still_objs;
  ___WORD *base = ___CAST(___WORD*,*last);
  ___SIZE_TS live_words_still = 0;

  while (base != 0)
    {
      ___WORD link = base[___STILL_LINK];
      if (base[___STILL_MARK] == -1)
        {
          ___WORD head = base[___STILL_BODY-1];
          if (___HD_SUBTYPE(head) == ___sFOREIGN)
            ___release_foreign
              (___TAG(base + ___STILL_BODY - ___REFERENCE_TO_BODY, ___tSUBTYPED));
          free_mem_aligned_heap (base);
        }
      else
        {
          live_words_still += base[___STILL_LENGTH];
          *last = ___CAST(___WORD,base);
          last = base + ___STILL_LINK;
        }
      base = ___CAST(___WORD*,link);
    }

  *last = 0;

  words_still_objs = live_words_still;
  words_still_objs_deferred = 0;

  /*
   * In principle the occupied_words_still could be updated here but
   * this would require acquiring a lock, so instead the
   * occupied_words_still will be recomputed from all of the
   * processor's words_still_objs when computing the space occupied by
   * live objects prior to resizing the heap.
   */
}


___HIDDEN void free_still_objs
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___WORD *base = ___CAST(___WORD*,still_objs);

  still_objs = 0;

  while (base != 0)
    {
      ___WORD link = base[___STILL_LINK];
      ___WORD head = base[___STILL_BODY-1];
      if (___HD_SUBTYPE(head) == ___sFOREIGN)
        ___release_foreign
          (___TAG(base + ___STILL_BODY - ___REFERENCE_TO_BODY, ___tSUBTYPED));
      free_mem_aligned_heap (base);
      base = ___CAST(___WORD*,link);
    }
}


/* End internal memory fragment. */
