#line 3036 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

#ifdef ___DEBUG_GARBAGE_COLLECT

#define fatal_heap_overflow() fatal_heap_overflow_debug (__LINE__)

___HIDDEN void fatal_heap_overflow_debug
   ___P((int line),
        (line)
int line;)

#else

___HIDDEN void fatal_heap_overflow ___PVOID

#endif
{
  char *msgs[2];

#ifdef ___DEBUG_GARBAGE_COLLECT
  ___printf ("fatal_heap_overflow called at mem.c:%d\n", line);
#endif

  msgs[0] = "Heap overflow";
  msgs[1] = 0;

  ___fatal_error (msgs);
}


___HIDDEN ___msection *next_msection_without_locking
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  ___msection *result;

  /*
   * This function allocates an msection from the list of free
   * msections.  This is done when a processor has used up all of the
   * space in its current reserved msection (either heap_msection for
   * a heap allocation or stack_msection for a stack allocation).
   * This operation must be done in a critical section because
   * multiple processors may exhaust their space concurrently, either
   * when doing a GC or when ___stack_limit or ___heap_limit are
   * called.  However, this mutual exclusion is the responsibility of
   * the caller of next_msection_without_locking.
   *
   * A spinlock is appropriate for this critical section because the
   * critical section takes very little time and the requests for new
   * msections happen relatively much less frequently.  An experiment
   * on a 2.6 GHz Intel Core i7 using a tight allocation loop of pairs
   * and ___MSECTION_SIZE=131072, indicates that the critical section
   * lasts 0.2 microseconds and next_msection_without_locking
   * is called every 300 microseconds.
   */

  if (custom_msection_alloc != 0)
    return custom_msection_alloc ();

  if (nb_msections_assigned == 0)
    result = the_msections->head; /* start at head of free msections */
  else
    result = alloc_msection->next; /* move to next free msection */

  if (result == 0)
    {
      /*
       * If there are no free msections to allocate the next heap or
       * stack msection, it is possible to use ms for both the heap
       * allocations and stack allocations.  But if it is currently
       * the case that both use the same msection, then it is an error
       * because the garbage collector should have been called to free
       * some space.
       */

      if (stack_msection == heap_msection)
        fatal_heap_overflow ();

      result = ms;
    }
  else
    {
      alloc_msection = result;
      nb_msections_assigned++;
    }

  return result;
}


___HIDDEN void set_stack_msection
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  stack_msection = ms;

  alloc_stack_limit = start_of_tospace(ms);
  alloc_stack_start = alloc_stack_limit + (___MSECTION_SIZE>>1);
  alloc_stack_ptr = alloc_stack_start;
}


___HIDDEN void set_stack_msection_possibly_sharing_with_heap
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  set_stack_msection (___ps, ms);

  if (ms == heap_msection)
    {
      /*
       * The same msection will be used for the stack and the heap, so
       * adjust the heap and stack limits accordingly.  3/4 of the
       * remaining usable space is assigned to the stack.
       */

      ___SIZE_TS space = alloc_heap_limit - alloc_heap_ptr;

      if (space < 2*___MSECTION_FUDGE)
        fatal_heap_overflow ();

      space = (space - 2*___MSECTION_FUDGE) >> 2; /* 1/4 of usable space */

      alloc_heap_limit = alloc_heap_ptr + (space + ___MSECTION_FUDGE);
      alloc_stack_limit = alloc_stack_ptr - (3*space + ___MSECTION_FUDGE);
    }

#ifdef ENABLE_CONSISTENCY_CHECKS
  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
    zap_section (alloc_stack_limit, alloc_stack_ptr);
#endif
}


___HIDDEN void stack_msection_stop_using
   ___P((___processor_state ___ps,
         ___WORD *stack_start,
         ___WORD *stack_ptr),
        (___ps,
         stack_start,
         stack_ptr)
___processor_state ___ps;
___WORD *stack_start;
___WORD *stack_ptr;)
{
  words_prev_msections += stack_start - stack_ptr;
}


___HIDDEN void stack_msection_resume_using
   ___P((___processor_state ___ps,
         ___WORD *stack_start,
         ___WORD *stack_ptr),
        (___ps,
         stack_start,
         stack_ptr)
___processor_state ___ps;
___WORD *stack_start;
___WORD *stack_ptr;)
{
  words_prev_msections -= stack_start - stack_ptr;
}


___HIDDEN void next_stack_msection_without_locking
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___msection *ms;
  ms = next_msection_without_locking (___ps, heap_msection);
  nb_msections_stacks++; /* one more msection assigned to stacks */
  set_stack_msection_possibly_sharing_with_heap (___ps, ms);
}


___HIDDEN void next_stack_msection
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___msection *ms;
  ALLOC_MEM_LOCK();
  ms = next_msection_without_locking (___ps, heap_msection);
  nb_msections_stacks++; /* one more msection assigned to stacks */
  ALLOC_MEM_UNLOCK();
  set_stack_msection_possibly_sharing_with_heap (___ps, ms);
}


___HIDDEN void start_heap_chunk
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  alloc_heap_chunk_start = alloc_heap_ptr;
  alloc_heap_chunk_limit = alloc_heap_ptr + ___MSECTION_CHUNK;
}


#define NULL_CHUNK_LINK ___TAG(0, ___FORW)


___HIDDEN void end_heap_chunk
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  /*
   * Add the end of chunk marker.
   *
   * This is done even when the chunk is empty, in case the chunk is
   * currently being scanned.
   */

  *alloc_heap_ptr++ = NULL_CHUNK_LINK; /* leave space for next chunk's link */

  if (alloc_heap_ptr != alloc_heap_chunk_start &&
      !(scan_ptr >= alloc_heap_chunk_start && scan_ptr < alloc_heap_ptr))
    {
      /*
       * The chunk being ended is not empty and it isn't currently
       * being scanned, so add it to the heap chunk FIFO and wake any
       * idle processor.
       */

      ___WORD *new_tail = alloc_heap_chunk_start-1;

#ifndef ___SINGLE_THREADED_VMS
      ___SPINLOCK_LOCK(heap_chunks_to_scan_lock);
#endif

      *heap_chunks_to_scan_tail = ___TAG(new_tail, ___FORW);

      /*
       * A memory barrier is needed to ensure that the content of the
       * chunk, including the end of chunk and the link to the chunk,
       * is visible to other processors.
       */

      ___SHARED_MEMORY_BARRIER();

      heap_chunks_to_scan_tail = new_tail;

      /*
       * A memory barrier is needed to ensure that the new tail of the
       * heap chunk FIFO are visible to other processors.  This can't
       * be combined with the previous memory barrier because the
       * ordering is important (as soon as the modification of
       * heap_chunks_to_scan_tail is observed by another processor, it
       * may attempt to read the content of the chunk).
       */

      ___SHARED_MEMORY_BARRIER();

#ifndef ___SINGLE_THREADED_VMS
      ___SPINLOCK_UNLOCK(heap_chunks_to_scan_lock);
      ___CONDVAR_SIGNAL(scan_termination_condvar);
#endif
    }
}


___HIDDEN void set_heap_msection
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  heap_msection = ms;

  alloc_heap_start = start_of_tospace(ms);
  alloc_heap_limit = alloc_heap_start + (___MSECTION_SIZE>>1);
  alloc_heap_ptr = alloc_heap_start;
}


___HIDDEN void set_heap_msection_possibly_sharing_with_stack
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  set_heap_msection (___ps, ms);

  if (ms == stack_msection)
    {
      /*
       * The same msection will be used for the stack and the heap, so
       * adjust the heap and stack limits accordingly.  3/4 of the
       * remaining usable space is assigned to the heap.
       */

      ___SIZE_TS space = alloc_stack_ptr - alloc_stack_limit;

      if (space < 2*___MSECTION_FUDGE)
        fatal_heap_overflow ();

      space = (space - 2*___MSECTION_FUDGE) >> 2; /* 1/4 of usable space */

      alloc_stack_limit = alloc_stack_ptr - (space + ___MSECTION_FUDGE);
      alloc_heap_limit = alloc_heap_ptr + (3*space + ___MSECTION_FUDGE);
    }

#ifdef ENABLE_CONSISTENCY_CHECKS
  //  if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
  //    zap_section (alloc_heap_ptr, alloc_heap_limit);
#endif
}


___HIDDEN void next_heap_msection_without_locking
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___msection *ms;
  words_prev_msections += alloc_heap_ptr - alloc_heap_start;
  ms = next_msection_without_locking (___ps, stack_msection);
  set_heap_msection_possibly_sharing_with_stack (___ps, ms);
}


___HIDDEN void next_heap_msection
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___msection *ms;
  words_prev_msections += alloc_heap_ptr - alloc_heap_start;
  ALLOC_MEM_LOCK();
  ms = next_msection_without_locking (___ps, stack_msection);
  ALLOC_MEM_UNLOCK();
  set_heap_msection_possibly_sharing_with_stack (___ps, ms);
}


___HIDDEN void prepare_heap_msection
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  /*
   * Heap chunks are non-empty, except possibly for the last chunk in
   * the msection.  Consequently, an msection may end with 2
   * consecutive end of chunk markers.  One for the last non-empty
   * chunk and one for an empty chunk.  The heap allocation limit must
   * be adjusted to handle this case.
   */

  alloc_heap_limit -= 2; /* leave space for 2 end of chunk markers */

  *alloc_heap_ptr++ = NULL_CHUNK_LINK; /* link of msection's first chunk */

  start_heap_chunk (___ps);
}


___HIDDEN void setup_stack_heap_vmstate
   ___P((___virtual_machine_state ___vms),
        (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  ___msection *alloc = the_msections->head;
  int np = ___vms->processor_count;
  int i;

  for (i=0; i<np; i++)
    {
      ___processor_state ___ps = ___PSTATE_FROM_PROCESSOR_ID(i,___vms);

      tospace_offset = fromspace_offset;  /* Flip fromspace and tospace */

      msection_free_list = 0;

      words_prev_msections = 0;

      stack_msection = 0;
      heap_msection = 0;

      set_stack_msection (___ps, alloc);
      alloc = alloc->next;

      alloc_msection = alloc;

      set_heap_msection (___ps, alloc);
      alloc = alloc->next;

      prepare_heap_msection (___ps);
      scan_ptr = alloc_heap_chunk_start;

      heap_chunks_to_scan = NULL_CHUNK_LINK;
      heap_chunks_to_scan_head = &heap_chunks_to_scan;
      heap_chunks_to_scan_tail = &heap_chunks_to_scan;
    }

  nb_msections_assigned = np*2;
  nb_msections_stacks   = np;

#ifndef ___SINGLE_THREADED_VMS

  /* Initialize the active scanning workers count */

  scan_workers_count[0] = np;
  scan_workers_count[1] = np;

#endif

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


/* End internal memory fragment. */
