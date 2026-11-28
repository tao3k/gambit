#line 1086 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation of permanent objects.  */

/*
 * 'alloc_mem_aligned_psection (words, multiplier, modulus)' allocates
 * an aligned block of memory inside a new psection.  'words' is the
 * size of the block in words and 'multiplier' and 'modulus' specify
 * its alignment in words.  'multiplier' must be a power of two and
 * 0<=modulus<multiplier.  The pointer returned corresponds to an
 * address that is equal to (i*multiplier+modulus)*sizeof (___WORD) for
 * some 'i'.
 */

___HIDDEN void *alloc_mem_aligned_psection
   ___P((___SIZE_TS words,
         unsigned int multiplier,
         unsigned int modulus),
        (words,
         multiplier,
         modulus)
___SIZE_TS words;
unsigned int multiplier;
unsigned int modulus;)
{
  void *container;

  /* Make sure alignment is sufficient for pointers */

  if (multiplier < sizeof (void*) / ___WS)
    multiplier = sizeof (void*) / ___WS;

  /* Make space for psection link and modulus */

  if (modulus < (sizeof (void*) + ___WS - 1) / ___WS)
    modulus += ((sizeof (void*) + multiplier * ___WS - 1) / ___WS) &
               -multiplier;

  /* Allocate container */

  container = alloc_mem_aligned_heap (words+modulus, multiplier, 0);

  if (container == 0)
    return 0;

  *___CAST(void**,container) = ___GSTATE->mem.psections;
  ___GSTATE->mem.psections = container;
  return ___CAST(void*,___CAST(___WORD*,container) + modulus);
}


/*
 * 'alloc_mem_aligned_perm (words, multiplier, modulus)' allocates an
 * aligned block of memory inside a psection.  If there is enough free
 * space in a previously allocated psection that psection is used,
 * otherwise a new psection is allocated.  'words' is the size of the
 * block in words and 'multiplier' and 'modulus' specify its alignment
 * in words.  'multiplier' must be a power of two and
 * 0<=modulus<multiplier.  The pointer returned corresponds to an
 * address that is equal to (i*multiplier+modulus)*sizeof (___WORD) for
 * some 'i'.
 */

___HIDDEN void *alloc_mem_aligned_perm_locked
   ___P((___SIZE_TS words,
         int multiplier,
         int modulus),
        (words,
         multiplier,
         modulus)
___SIZE_TS words;
int multiplier;
int modulus;)
{
  ___SIZE_TS waste;
  ___WORD *base;

  /*
   * Try to satisfy request in current psection.
   */

  if (___GSTATE->mem.palloc_ptr != 0)
    {
      ___WORD *new_palloc_ptr;

      base = ___CAST(___WORD*,
                     ___CAST(___WORD,___GSTATE->mem.palloc_ptr+multiplier-1-modulus) &
                     (multiplier * -___WS)) +
             modulus;

      new_palloc_ptr = base + words;

      if (new_palloc_ptr <= ___GSTATE->mem.palloc_limit) /* did it fit in the psection? */
        {
          ___GSTATE->mem.palloc_ptr = new_palloc_ptr;
          return base;
        }

      waste = ___GSTATE->mem.palloc_limit - ___GSTATE->mem.palloc_ptr;
    }
  else
    waste = 0;

  /*
   * Request can't be satisfied in current psection so we must
   * allocate a new psection.
   */

  if (waste > ___PSECTION_WASTE || words > ___PSECTION_SIZE)
    return alloc_mem_aligned_psection (words, multiplier, modulus);

  base = ___CAST(___WORD*,
                 alloc_mem_aligned_psection
                   (___PSECTION_SIZE,
                    multiplier,
                    modulus));

  if (base != 0)
    {
      ___GSTATE->mem.palloc_ptr = base + words;
      ___GSTATE->mem.palloc_limit = base + ___PSECTION_SIZE;
    }

  return base;
}


___HIDDEN void *alloc_mem_aligned_perm(___SIZE_TS words, int multiplier, int modulus)
{
  void *result;
  ___MUTEX_LOCK(___GSTATE->mem.permanent_gate);
  result=alloc_mem_aligned_perm_locked(words,multiplier,modulus);
  ___MUTEX_UNLOCK(___GSTATE->mem.permanent_gate);
  return result;
}

___HIDDEN void free_psections ___PVOID
{
  void *base = ___GSTATE->mem.psections;

  ___GSTATE->mem.psections = 0;

  while (base != 0)
    {
      void *link = *___CAST(void**,base);
      free_mem_aligned_heap (base);
      base = link;
    }
}


/* End internal memory fragment. */
