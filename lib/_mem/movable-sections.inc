#line 829 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation of movable objects.  */

/*
 * 'find_msection (ms, ptr)' finds the position in the 'ms->sections'
 * array of the msection that contains the pointer 'ptr'.  More
 * precisely, if ___ALLOC_MEM_UP is defined, it returns the integer
 * 'i' (-1<=i<=n-1) such that 'ptr' is between the start of section i
 * and section i+1.  -1 is returned if 'ptr' is lower than the lowest
 * section and 'n' is returned if 'ptr' is not lower than the highest
 * section.  If ___ALLOC_MEM_UP is not defined, it returns the integer
 * 'i' (0<=i<=n) such that 'ptr' is between the start of section i and
 * section i-1.  n is returned if 'ptr' is lower than the lowest
 * section and 0 is returned if 'ptr' is not lower than the highest
 * section.
 */

___HIDDEN int find_msection
   ___P((___msections *ms,
         void *ptr),
        (ms,
         ptr)
___msections *ms;
void *ptr;)
{
  int ns = ms->nb_sections;
  ___msection **sections = ms->sections;
  int lo, hi;

#ifdef ___ALLOC_MEM_UP
  if (ns == 0 ||
      ptr < ___CAST(void*,sections[0]))
    return -1;
#else
  if (ns == 0 ||
      ptr < ___CAST(void*,sections[ns-1]))
    return ns;
#endif

  /* binary search */

  lo = 0;
  hi = ns-1;

  /* loop invariant: lo <= find_msection (ms, ptr) <= hi */

  while (lo < hi)
    {
      int mid = (lo+hi) / 2; /* lo <= mid < hi */
#ifdef ___ALLOC_MEM_UP
      if (ptr < ___CAST(void*,sections[mid+1])) hi = mid; else lo = mid+1;
#else
      if (ptr < ___CAST(void*,sections[mid])) lo = mid+1; else hi = mid;
#endif
    }

  return lo;
}


/*
 * 'adjust_msections (msp, n)' contracts or expands the msections
 * pointed to by 'msp' so that it contains 'n' sections.  When the
 * msections is contracted, the last sections allocated (i.e. those at
 * the end of the doubly-linked list of sections) will be reclaimed.
 * When expanding the msections there may not be enough memory to
 * allocate new sections so the operation may fail.  However
 * 'adjust_msections' will always leave the msections in a consistent
 * state and there will be at least as many sections as when the
 * expansion was started.  Failure can be detected by checking the
 * 'nb_sections' field.
 */

___HIDDEN void adjust_msections
   ___P((___msections **msp,
         int n),
        (msp,
         n)
___msections **msp;
int n;)
{
  int max_ns, ns;
  ___msections *ms = *msp;
  ___msection *hd;
  ___msection *tl;

  if (ms == 0)
    {
      max_ns = 0;
      ns = 0;
      hd = 0;
      tl = 0;
    }
  else
    {
      max_ns = ms->max_nb_sections;
      ns = ms->nb_sections;
      hd = ms->head;
      tl = ms->tail;
    }

  if (ms == 0 || n > max_ns)
    {
      /* must allocate a new msections structure */

      ___msections *new_ms;
      int i;

      while (n > max_ns) /* grow max_nb_sections until big enough */
        max_ns = 2*max_ns + 1;

      new_ms = ___CAST(___msections*,
                       alloc_mem_aligned
                         (___WORDS(___sizeof_msections(max_ns)),
                          1,
                          0));

      if (new_ms == 0)
        return;

      new_ms->max_nb_sections = max_ns;
      new_ms->nb_sections = ns;
      new_ms->head = hd;
      new_ms->tail = tl;

      for (i=ns-1; i>=0; i--)
        new_ms->sections[i] = ms->sections[i];

      if (ms != 0)
        free_mem_aligned (ms);

      ms = new_ms;

      *msp = ms;
    }

  if (n < ns)
    {
      /* contraction of the msections */

      int j;

      while (ns > n)
        {
          ___msection *s = tl;

          tl = tl->prev;

          if (tl == 0)
            hd = 0;
          else
            tl->next = 0;

          for (j=s->pos; j<ns-1; j++)
            {
              ms->sections[j] = ms->sections[j+1];
              ms->sections[j]->pos = j;
            }

          free_mem_aligned_heap (s);

          ns--;
        }

      ms->nb_sections = ns;
      ms->head = hd;
      ms->tail = tl;

      /*
       * Contraction of the msections structure is not performed
       * because there is typically very little memory to be
       * reclaimed.
       */
    }
  else
    {
      /* expansion of the msections */

      int i, j;

      while (ns < n)
        {
          ___msection *s = ___CAST(___msection*,
                                   alloc_mem_aligned_heap
                                     (___WORDS(___sizeof_msection(___MSECTION_SIZE)),
                                      1,
                                      0));

          if (s == 0)
            return;

          i = find_msection (ms, ___CAST(void*,s));

#ifdef ___ALLOC_MEM_UP
          i++;
#endif

          for (j=ns; j>i; j--)
            {
              ms->sections[j] = ms->sections[j-1];
              ms->sections[j]->pos = j;
            }

          ms->sections[i] = s;

          if (tl == 0)
            {
              hd = s;
              s->index = 0;
            }
          else
            {
              tl->next = s;
              s->index = tl->index + 1;
            }

          s->copy_gate=0;
          s->pos = i;
          s->prev = tl;
          s->next = 0;

          tl = s;

          ms->nb_sections = ++ns;
          ms->head = hd;
          ms->tail = tl;
        }
    }
}


/*
 * 'free_msections (msp)' releases all memory associated with the
 * msections pointed to by 'msp'.
 */

___HIDDEN void free_msections
   ___P((___msections **msp),
        (msp)
___msections **msp;)
{
  ___msections *ms = *msp;

  if (ms != 0)
    {
      int i;

      for (i=ms->nb_sections-1; i>=0; i--)
        free_mem_aligned_heap (ms->sections[i]);

      free_mem_aligned (ms);

      *msp = 0;
    }
}


/* End internal memory fragment. */
