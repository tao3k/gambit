#line 1484 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/*
 * '___alloc_scmobj (___ps, subtype, bytes)' allocates a permanent or
 * still Scheme object (depending on '___ps') of subtype 'subtype'
 * with a body containing 'bytes' bytes, and returns it as an encoded
 * Scheme object.  When '___ps' is NULL, a permanent object is
 * allocated, and when '___ps' is not NULL, a still object is
 * allocated in the heap of that processor's VM.  The initialization
 * of the object's body must be done by the caller.  In the case of
 * still objects this initialization must be done before the next
 * allocation is requested.  The 'refcount' field of still objects is
 * initially 1.  A fixnum error code is returned when there is an
 * error.
 */

___HIDDEN ___WORD alloc_scmobj_perm
   ___P((int subtype,
         ___SIZE_TS bytes),
        (subtype,
         bytes)
int subtype;
___SIZE_TS bytes;)
{
  void *ptr;
  ___WORD *base;
  ___WORD *body;
  ___SIZE_TS words = ___PERM_BODY + ___WORDS(bytes);

  /*
   * Some objects, such as ___sFOREIGN, ___sS64VECTOR, ___sU64VECTOR,
   * ___sF64VECTOR, ___sFLONUM and ___sBIGNUM, must have a body that
   * is aligned on a multiple of 8 on some machines.  Here, we force
   * alignment to a multiple of 8 even if not necessary in all cases
   * because it is typically more efficient due to a better
   * utilization of the cache.
   */

  ptr = alloc_mem_aligned_perm (words,
                                8>>___LWS,
                                (-___PERM_BODY)&((8>>___LWS)-1));

  if (ptr == 0)
    return ___FIX(___HEAP_OVERFLOW_ERR);

  base = ___CAST(___WORD*,ptr);
  body = base + ___PERM_BODY;

#ifdef ___USE_HANDLES
  base[___PERM_HANDLE] = ___CAST(___WORD,body);
#endif

  base[___PERM_HEADER] = ___MAKE_HD(bytes, subtype, ___PERM);

#if ___tPAIR != ___tSUBTYPED
  if (subtype == ___sPAIR) return ___PAIR_FROM_BODY(body);
#endif

#ifndef ___NAN_BOXING
#if  ___tFLONUM != ___tSUBTYPED
  if (subtype == ___sFLONUM) return ___FLONUM_FROM_BODY(body);
#endif
#endif

#if ___tVECTOR != ___tSUBTYPED
  if (subtype == ___sVECTOR) return ___VECTOR_FROM_BODY(body);
#endif

  return ___SUBTYPED_FROM_BODY(body);
}


___HIDDEN ___WORD alloc_scmobj_still
   ___P((___processor_state ___ps,
         int subtype,
         ___SIZE_TS bytes),
        (___ps,
         subtype,
         bytes)
___processor_state ___ps;
int subtype;
___SIZE_TS bytes;)
{
  void *ptr;
  ___WORD *base;
  ___WORD *body;
  ___SIZE_TS words = ___STILL_BODY + ___WORDS(bytes);
  ___SIZE_TS words_including_deferred = words + words_still_objs_deferred;

#ifdef CALL_GC_FREQUENTLY
  if (--___gc_calls_to_punt < 0) goto invoke_gc;
#endif

  if (words_including_deferred <= ___MAX_STILL_DEFERRED)
    {
      /*
       * Allocate the still object and defer its accounting at the VM
       * level.
       */

      /*
       * Some objects, such as ___sFOREIGN, ___sS64VECTOR,
       * ___sU64VECTOR, ___sF64VECTOR, ___sFLONUM and ___sBIGNUM, must
       * have a body that is aligned on a multiple of 8 on some
       * machines.  Here, we force alignment to a multiple of 8 even
       * if not necessary in all cases because it is typically more
       * efficient due to a better utilization of the cache.
       */

      if ((ptr = alloc_mem_aligned_heap (words,
                                         8>>___LWS,
                                         (-___STILL_BODY)&((8>>___LWS)-1)))
          == 0)
        {
          /*
           * Couldn't allocate the still object (probably the C heap is full).
           */

          return ___FIX(___HEAP_OVERFLOW_ERR);
        }

      words_still_objs_deferred = words_including_deferred;
    }
  else
    {
      /*
       * The space for the still object (and the deferred previous
       * ones) is considerable, so the availability of the space must
       * be checked at the VM level.  The VM's memory allocation lock
       * must be acquired to ensure correct bookkeeping.
       */

      ALLOC_MEM_LOCK();

      if (words_including_deferred <= compute_free_heap_space_approximately())
        {
          /*
           * There is sufficient free heap space, so no need to call GC.
           */

          occupied_words_still += words_including_deferred;

          ALLOC_MEM_UNLOCK();

          /*
           * Space accounting for previous still objects is now accounted
           * for at the VM level.
           */

          words_still_objs_deferred = 0;
        }
      else
        {
          /*
           * There is insufficient free heap space, so call GC.
           */

          ALLOC_MEM_UNLOCK();

#ifdef CALL_GC_FREQUENTLY
        invoke_gc:
#endif

          if (___garbage_collect (___PSP words))
            return ___FIX(___HEAP_OVERFLOW_ERR);
        }

      /*
       * Allocate the still object.  See comments above for other call
       * to alloc_mem_aligned_heap.
       */

      if ((ptr = alloc_mem_aligned_heap (words,
                                         8>>___LWS,
                                         (-___STILL_BODY)&((8>>___LWS)-1)))
          == 0)
        {
          /*
           * Couldn't allocate the still object (probably the C heap is full).
           * So undo its accounting at the VM level.
           */

          ALLOC_MEM_LOCK();

          occupied_words_still -= words;

          ALLOC_MEM_UNLOCK();

          return ___FIX(___HEAP_OVERFLOW_ERR);
        }
    }

  /* Initialize still object and add it to the still_objs list. */

  base = ___CAST(___WORD*,ptr);
  body = base + ___STILL_BODY;

  base[___STILL_LINK] = still_objs;
  still_objs = ___CAST(___WORD,base);
  base[___STILL_REFCOUNT] = 1;
  base[___STILL_LENGTH] = words;

#ifdef ___USE_HANDLES
  base[___STILL_HANDLE] = ___CAST(___WORD,body);
#endif

  base[___STILL_HEADER] = ___MAKE_HD(bytes, subtype, ___STILL);

  /* Return tagged reference to still object. */

#if ___tPAIR != ___tSUBTYPED
  if (subtype == ___sPAIR) return ___PAIR_FROM_BODY(body);
#endif

#ifndef ___NAN_BOXING
#if ___tFLONUM != ___tSUBTYPED
  if (subtype == ___sFLONUM) return ___FLONUM_FROM_BODY(body);
#endif
#endif

#if ___tVECTOR != ___tSUBTYPED
  if (subtype == ___sVECTOR) return ___VECTOR_FROM_BODY(body);
#endif

  return ___SUBTYPED_FROM_BODY(body);
}


___EXP_FUNC(___WORD,___alloc_scmobj)
   ___P((___processor_state ___ps,
         int subtype,
         ___SIZE_TS bytes),
        (___ps,
         subtype,
         bytes)
___processor_state ___ps;
int subtype;
___SIZE_TS bytes;)
{
  if (___ps == NULL)
    return alloc_scmobj_perm (subtype, bytes);
  else
    return alloc_scmobj_still (___ps, subtype, bytes);
}


___EXP_FUNC(___SCMOBJ,___release_scmobj)
   ___P((___SCMOBJ obj),
        (obj)
___SCMOBJ obj;)
{
  if (___MEM_ALLOCATED(obj) &&
      ___HD_TYP(___HEADER(obj)) == ___STILL)
    ___still_obj_refcount_dec (obj);
  return obj;
}


/*
 * '___make_pair (___ps, car, cdr)' creates a Scheme pair having the
 * values 'car' and 'cdr' in its CAR and CDR fields.  The 'car' and
 * 'cdr' arguments must not be movable objects and any still object
 * must be reachable some other way or have a nonzero refcount.  A
 * permanent or still object is allocated, depending on '___ps'.  When
 * '___ps' is NULL, a permanent object is allocated, and when '___ps'
 * is not NULL, a still object is allocated in the heap of that
 * processor.  The 'refcount' field of still objects is initially 1.
 * A fixnum error code is returned when there is an error.
 */

___EXP_FUNC(___WORD,___make_pair)
   ___P((___processor_state ___ps,
         ___WORD car,
         ___WORD cdr),
        (___ps,
         car,
         cdr)
___processor_state ___ps;
___WORD car;
___WORD cdr;)
{
  ___WORD obj = ___alloc_scmobj (___ps, ___sPAIR, ___PAIR_SIZE<<___LWS);

  if (!___FIXNUMP(obj))
    {
      ___CAR_FIELD(obj) = car;
      ___CDR_FIELD(obj) = cdr;
    }

  return obj;
}


/*
 * '___make_vector (___ps, length, init)' creates a Scheme vector of
 * length 'length' and initialized with the value 'init'.  The 'init'
 * argument must not be a movable object and if it is a still object
 * it must be reachable some other way or have a nonzero refcount.  A
 * permanent or still object is allocated, depending on '___ps'.  When
 * '___ps' is NULL, a permanent object is allocated, and when '___ps'
 * is not NULL, a still object is allocated in the heap of that
 * processor.  The 'refcount' field of still objects is initially 1.
 * A fixnum error code is returned when there is an error.
 */

___EXP_FUNC(___WORD,___make_vector)
   ___P((___processor_state ___ps,
         ___SIZE_TS length,
         ___WORD init),
        (___ps,
         length,
         init)
___processor_state ___ps;
___SIZE_TS length;
___WORD init;)
{
  if (length > ___CAST(___WORD,___LMASK >> (___LF+___LWS)))
    return ___FIX(___HEAP_OVERFLOW_ERR);
  else
    {
      ___WORD obj = ___alloc_scmobj (___ps, ___sVECTOR, length<<___LWS);

      if (!___FIXNUMP(obj))
        {
          int i;
          for (i=0; i<length; i++)
            ___VECTORELEM(obj, i) = init;
        }

      return obj;
    }
}


/* End internal memory fragment. */
