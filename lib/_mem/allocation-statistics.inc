#line 7453 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/


___F64 ___bytes_allocated
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET

  /* Recover processor's stack and heap pointers */

  alloc_stack_ptr = ___ps->context->fp;
  alloc_heap_ptr  = ___ps->context->hp;

  return bytes_allocated_minus_occupied + bytes_occupied(___ps) +
         ___CAST(___F64,occupied_words_still) * ___WS;
}


/*---------------------------------------------------------------------------*/
/* End internal memory fragment. */
