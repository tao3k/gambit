#line 538 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation and reclamation of aligned blocks of memory.  */


/*
 * 'alloc_mem_aligned_aux (words, multiplier, modulus, heap)'
 * allocates an aligned block of memory (using '___alloc_mem' when
 * heap is false, and '___alloc_mem_heap' when heap is true).  'words'
 * is the size of the block in words and 'multiplier' and 'modulus'
 * specify its alignment in words.  'multiplier' must be a power of
 * two and 0<=modulus<multiplier.  The pointer returned corresponds to
 * an address that is equal to (i*multiplier+modulus)*sizeof (___WORD)
 * for some 'i'.
 */

___HIDDEN void *alloc_mem_aligned_aux
   ___P((___SIZE_TS words,
         unsigned int multiplier,
         unsigned int modulus,
         ___BOOL heap),
        (words,
         multiplier,
         modulus,
         heap)
___SIZE_TS words;
unsigned int multiplier;
unsigned int modulus;
___BOOL heap;)
{
  void *container; /* pointer to block returned by ___alloc_mem{_heap} */
  unsigned int extra; /* space for alignment to multiplier */

  /* Make sure alignment is sufficient for pointers */

  if (multiplier < sizeof (void*) / ___WS)
    multiplier = sizeof (void*) / ___WS;

  /* How many extra bytes are needed for padding */

  extra = (multiplier * ___WS) - 1;
  if (modulus < sizeof (void*) / ___WS)
    extra += sizeof (void*);

  if (heap)
    container = ___ALLOC_MEM_HEAP(extra + (words+modulus) * ___WS);
  else
    container = ___ALLOC_MEM(extra + (words+modulus) * ___WS);

  if (container == 0)
    return 0;
  else
    {
      void *ptr = ___CAST(void*,
                          (((___CAST(___WORD,container) + extra) &
                            -___CAST(___WORD,multiplier * ___WS)) +
                           modulus * ___WS));
      void **cptr = ___CAST(void**,
                            (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                            -___CAST(___WORD,sizeof (void*)));

      *cptr = container;
      return ptr;
    }
}


___HIDDEN void *alloc_mem_aligned
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
  return alloc_mem_aligned_aux (words, multiplier, modulus, 0);
}


___HIDDEN void *alloc_mem_aligned_heap
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
  return alloc_mem_aligned_aux (words, multiplier, modulus, 1);
}


/*
 * 'free_mem_aligned (ptr)' reclaims the aligned block of memory 'ptr'
 * that was allocated using 'alloc_mem_aligned'.
 */

___HIDDEN void free_mem_aligned
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  void **cptr = ___CAST(void**,
                        (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                        -___CAST(___WORD,sizeof (void*)));
  ___FREE_MEM(*cptr);
}


/*
 * 'free_mem_aligned_heap (ptr)' reclaims the aligned block of memory
 * 'ptr' that was allocated using 'alloc_mem_aligned_heap'.
 */

___HIDDEN void free_mem_aligned_heap
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  void **cptr = ___CAST(void**,
                        (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                        -___CAST(___WORD,sizeof (void*)));
  ___FREE_MEM_HEAP(*cptr);
}


/* End internal memory fragment. */
