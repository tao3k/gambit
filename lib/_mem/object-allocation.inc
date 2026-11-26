#line 1491 ___MEM_SOURCE_FILE
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

#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_census_native("permanent-scmobj");
#endif
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
  ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
  void *ptr;
  ___WORD *base;
  ___WORD *body;
  ___SIZE_TS words = ___STILL_BODY + ___WORDS(bytes);

#ifdef CALL_GC_FREQUENTLY
  if (--___gc_calls_to_punt < 0) goto invoke_gc;
#endif

  if (words <= still_words_budget)
    {
      /*
       * Fast path: consume from this processor's pre-reserved still-object
       * budget without acquiring ALLOC_MEM_LOCK(). The budget is already
       * accounted in reserved_words_still, preserving exact heap bounds.
       */

#ifdef ___GAMBIT_DEV_RESTORE_PROBE
      ___dev_restore_census_native("still-scmobj");
#endif
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

      still_words_budget -= words;
      words_still_objs_deferred += words;
    }
  else
    {
      /*
       * Settle this processor's prior still-object reservation and reserve
       * space for this allocation plus a bounded prefetch chunk to amortize
       * ALLOC_MEM_LOCK() contention across high core counts.
       */
      ___SIZE_TS prev_reserved;
      ___SIZE_TS avail;

      ALLOC_MEM_LOCK();

      prev_reserved = words_still_objs_deferred + still_words_budget;
      if (reserved_words_still >= prev_reserved)
        reserved_words_still -= prev_reserved;
      else
        reserved_words_still = 0;
      occupied_words_still += words_still_objs_deferred;
      words_still_objs_deferred = 0;
      still_words_budget = 0;

      avail = compute_free_heap_space_approximately();

      if (words <= avail)
        {
          /*
           * There is sufficient free heap space, so no need to call GC.
           */
          ___SIZE_TS rem = avail - words;
          ___SIZE_TS extra = 0;
          if (rem > 0)
            {
              ___SIZE_TS cap = rem / (2 * vm->processor_count + 2);
              ___SIZE_TS chunk = (___MSECTION_SIZE >> 2);
              extra = cap < chunk ? cap : chunk;
            }

          occupied_words_still += words;
          reserved_words_still += extra;
          still_words_budget = extra;

          ALLOC_MEM_UNLOCK();
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

          /* Native release callbacks have an owner service, not a running
           * Scheme activation. No nested collective can wait on this round.
           * Return allocation failure before losing any initialization debt. */
          if (___ps != ___PSTATE || !___lifecycle_gc_admitted(___ps)
              || vm->lifecycle->cleanup[___PROCESSOR_ID(___ps,vm)].draining)
            return ___FIX(___HEAP_OVERFLOW_ERR);
          if (___garbage_collect (___PSP words))
            return ___FIX(___HEAP_OVERFLOW_ERR);
        }

      /*
       * Allocate the still object.  See comments above for other call
       * to alloc_mem_aligned_heap.
       */

#ifdef ___GAMBIT_DEV_RESTORE_PROBE
      ___dev_restore_census_native("still-scmobj");
#endif
      if ((ptr = alloc_mem_aligned_heap (words,
                                         8>>___LWS,
                                         (-___STILL_BODY)&((8>>___LWS)-1)))
          == 0)
        {
          /*
           * Couldn't allocate the still object (probably the C heap is full).
           * Refund this request once. A reservation resize_heap already
           * withdrew is not refunded here, because that path returns before
           * this allocation.
           */

          {
            int refunded = 0;
            long occupied = (long)occupied_words_still;

            ALLOC_MEM_LOCK();
            if (___still_refund_once(&refunded,&occupied,(long)words))
              occupied_words_still = (___SIZE_TS)occupied;
            ALLOC_MEM_UNLOCK();
          }

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
#else
  base[___STILL_DIRTY] = 1;
  ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 1);
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
