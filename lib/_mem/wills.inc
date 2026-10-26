#line 4944 ___MEM_SOURCE_FILE
___HIDDEN void determine_will_executability
   ___P((___WORD list),
        (list)
___WORD list;)
{
  while (___UNTAG(list) != 0)
    {
      ___WORD* will_body = ___UNTAG(list) + ___SUBTYPED_BODY;
      ___WORD will_head = will_body[-1];
      ___WORD testator;

      ___WORD *unmarked_body; /* used by the UNMARKED macro */
      int unmarked_typ;

      if (___TESTTYPE(will_head, ___FORW)) /* was will forwarded? */
        will_body = ___BODY0_AS(will_head,___FORW);

      list = will_body[___WILL_NEXT];

      testator = will_body[___WILL_TESTATOR];

      if (___MEM_ALLOCATED(testator) &&
          UNMARKED(testator)) /* testator was not marked? */
        {
          /*
           * All paths to testator object from roots pass through
           * weak references, so mark will as executable.
           */

          will_body[___WILL_NEXT] = list | ___EXECUTABLE_WILL;
        }
    }
}


___HIDDEN void process_wills
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD* tail_exec;
  ___WORD* tail_nonexec;
  ___WORD curr;

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_WILL_LIST;
#endif

  determine_will_executability (nonexecutable_wills);

  /*
   * Finish scanning the wills whose testator object remains to be
   * marked.
   *
   * The wills that have become executable are also transferred from
   * the nonexecutable wills list to the executable wills list.
   */

  tail_exec = &executable_wills;
  curr = *tail_exec;

  while (___UNTAG(curr) != 0)
    {
      ___WORD will = ___SUBTYPED_FROM_START(___UNTAG(curr));

      mark_array (___PSP &will, 1);

      *tail_exec = ___TAG(___SUBTYPED_TO_START(will),___EXECUTABLE_WILL);
      tail_exec = &___BODY0_AS(will,___tSUBTYPED)[___WILL_NEXT];
      curr = *tail_exec;
      if (curr & ___UNMARKED_TESTATOR_WILL)
        mark_array (___PSP tail_exec+___WILL_TESTATOR, 1); /* mark testator object */
    }

  tail_nonexec = &nonexecutable_wills;
  curr = *tail_nonexec;

  while (___UNTAG(curr) != 0)
    {
      ___WORD will = ___SUBTYPED_FROM_START(___UNTAG(curr));

      mark_array (___PSP &will, 1);

      if (___BODY0_AS(will,___tSUBTYPED)[___WILL_NEXT] & ___EXECUTABLE_WILL)
        {
          /* move will to executable will list */

          *tail_exec = ___TAG(___SUBTYPED_TO_START(will),___EXECUTABLE_WILL);
          tail_exec = &___BODY0_AS(will,___tSUBTYPED)[___WILL_NEXT];
          curr = *tail_exec;
          if (curr & ___UNMARKED_TESTATOR_WILL)
            mark_array (___PSP tail_exec+___WILL_TESTATOR, 1); /* mark testator object */
        }
      else
        {
          /* leave will in nonexecutable will list */

          *tail_nonexec = ___TAG(___SUBTYPED_TO_START(will),0);
          tail_nonexec = &___BODY0_AS(will,___tSUBTYPED)[___WILL_NEXT];
          curr = *tail_nonexec;
          if (curr & ___UNMARKED_TESTATOR_WILL)
            mark_array (___PSP tail_nonexec+___WILL_TESTATOR, 1); /* mark testator object */
        }
    }

  *tail_exec = ___TAG(0,___EXECUTABLE_WILL);
  *tail_nonexec = ___TAG(0,0);
}


/* Hash-table layout ownership is independent of collector population.
 * Reads preserve slots; native writes settle address-index debt. */

/* End internal memory fragment. */
