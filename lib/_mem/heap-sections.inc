#line 3046 ___MEM_SOURCE_FILE
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
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps = work->carrier;
  alloc_heap_chunk_start = work->arena.cursor;
  alloc_heap_chunk_limit = work->arena.cursor + ___MSECTION_CHUNK;
}


#define NULL_CHUNK_LINK ___TAG(0, ___FORW)

/* Chunk links occupy non-object word positions in the existing scan map.
 * 0 private, 1 queued, 2 exclusively held, 3 drained. A local frontier owns
 * its chunk before any copying can close it. Allocation position is never
 * evidence of that ownership. */
___HIDDEN int change_object_scan_state
   ___P((___collector_worker *work, ___WORD *header, int from, int to),
        (work, header, from, to)
___collector_worker *work;
___WORD *header;
int from;
int to;);

___HIDDEN void require_chunk_transition
   ___P((___collector_worker *work, ___WORD *start, int from, int to),
        (work, start, from, to)
___collector_worker *work;
___WORD *start;
int from;
int to;)
{
  if (change_object_scan_state(work,start-1,from,to) != from)
    {
      static char *msgs[] = { "GC chunk authority lost", NULL };
      ___fatal_error (msgs);
    }
}

/* Full-barrier atomic adapters are already provided by Gambit's portable
 * native layer. In contrast to a grant polled with a volatile load, the
 * successful CAS itself acquires preceding queue writes. Every head/tail
 * access is inside this gate. A failed steal has no queue observation. */
___HIDDEN void lock_chunk_fifo
   ___P((___collector_worker *owner), (owner)
___collector_worker *owner;)
{
#ifndef ___SINGLE_THREADED_VMS
  while (___COMPARE_AND_SWAP_WORD(&owner->chunk_gate_,0,1) != 0)
    ___CPU_RELAX();
#endif
}

___HIDDEN void unlock_chunk_fifo
   ___P((___collector_worker *owner), (owner)
___collector_worker *owner;)
{
#ifndef ___SINGLE_THREADED_VMS
  ___FETCH_AND_CLEAR_WORD(&owner->chunk_gate_);
#endif
}

___HIDDEN ___WORD *take_heap_chunk
   ___P((___collector_worker *work, ___collector_worker *owner),
        (work, owner)
___collector_worker *work;
___collector_worker *owner;)
{
  ___WORD *node;
#ifndef ___SINGLE_THREADED_VMS
  if (___COMPARE_AND_SWAP_WORD(&owner->chunk_gate_,0,1) != 0)
    return 0;
#endif
  if (owner->heap_chunks_to_scan_head_ == owner->heap_chunks_to_scan_tail_)
    {
      unlock_chunk_fifo(owner);
      return 0;
    }
  node = ___UNTAG_AS(*owner->heap_chunks_to_scan_head_, ___FORW);
  require_chunk_transition(work,node+1,1,2);
  owner->heap_chunks_to_scan_head_ = node;
  work->chunks_claimed_++;
  unlock_chunk_fifo(owner);
  return node+1;
}


___HIDDEN void end_heap_chunk
   ___P((___collector_worker *work),
        (work)
___collector_worker *work;)
{
  ___processor_state ___ps = work->carrier;
  /*
   * Add the end of chunk marker.
   *
   * This is done even when the chunk is empty, in case the chunk is
   * currently being scanned.
   */

  *work->arena.cursor++ = NULL_CHUNK_LINK; /* leave space for next chunk's link */

  if (alloc_heap_chunk_start != work->local_scan_chunk_)
    {
      /*
       * The chunk being ended is not empty and it isn't currently
       * being scanned, so add it to the heap chunk FIFO and wake any
       * idle processor.
       */

      ___WORD *new_tail = alloc_heap_chunk_start-1;

      require_chunk_transition(work,alloc_heap_chunk_start,0,1);
      work->chunks_published_++;

      lock_chunk_fifo(work);

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

      unlock_chunk_fifo(work);
#ifndef ___SINGLE_THREADED_VMS
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


/* Install a VM-assigned destination interval. No context heap cursor is
 * read or written by copying, including its slow refill path. Two terminal
 * chunk-link words remain outside the usable copy limit. */
___HIDDEN void prepare_worker_msection
 (___collector_worker *work, ___msection *section,
  ___WORD *base, ___WORD *limit)
{
  work->arena.section = section;
  work->arena.base = work->arena.cursor = base;
  work->arena.physical_limit=limit-1;
  work->arena.large=work->copy_request.state!=0 &&
    work->copy_request.destination_words>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3;
  work->arena.limit=limit-2-(work->arena.large?0:___MSECTION_FUDGE);
  work->arena.pending = work->arena.pending_past = 0;
  *work->arena.cursor++ = NULL_CHUNK_LINK;
  start_heap_chunk(work);
}

/* The VM allocator serializes section ownership. Exhaustion may consume the
 * worker's pre-issued restoration-space loan once, never an implicit current
 * PSTATE stack/heap fallback. The stack footprint was reserved before flip. */
___HIDDEN void refill_worker_arena (___collector_worker *work)
{
  ___processor_state ___ps = work->carrier;
  ___msection *ms;
  ___WORD *base, *limit;
  ___gc_resume_space *r = work->reserve;
  if (work->arena.pending || work->arena.handed_off)
    fatal_heap_overflow();
  work->arena.retired_words += work->arena.cursor-work->arena.base;
  ALLOC_MEM_LOCK();
  ms=alloc_msection->next;
  if(___COLLECTION(work->vm).decision!=1 ||
     ___COLLECTION(work->vm).issued_copy_sections>=___COLLECTION(work->vm).planned_copy_sections ||
     ms==___COLLECTION(work->vm).copy_past || ms==0) {
    ALLOC_MEM_UNLOCK();rc_contract_error("Admitted copy layout exhausted: census/packing refinement violation");return;
  }
  alloc_msection=ms;nb_msections_assigned++;
  ++___COLLECTION(work->vm).issued_copy_sections;
  ALLOC_MEM_UNLOCK();
  if (ms != 0)
    {
      base = ms->base + ___COLLECTION(work->vm).destination_offset;
      limit = base + (___MSECTION_SIZE>>1);
    }
  else
    {
      rc_contract_error("Copying cannot borrow a context restoration interval");return;
    }
  work->arena.refills++;
  prepare_worker_msection(work,ms,base,limit);
}


/* Private partition policy, shared by pre-flip admission and actual grants. */
___HIDDEN ___SIZE_TS restore_loan_words (___SIZE_TS length)
{
  ___SIZE_TS space = ___MSECTION_SIZE>>1;
  ___SIZE_TS loan = 3*((space-2*___MSECTION_FUDGE)>>2)+___MSECTION_FUDGE;
  if (loan > space-length-___MSECTION_FUDGE)
    loan = space-length-___MSECTION_FUDGE;
  return loan;
}


___HIDDEN void setup_stack_heap_vmstate
   ___P((___virtual_machine_state ___vms),
        (___vms)
___virtual_machine_state ___vms;)
{
#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___vms->mem.var

  ___msection *alloc = the_msections->head;
  int np = ___COLLECTION(___vms).participant_count;
  int nw=___COLLECTION(___vms).worker_count;
  int i;
  /* All source and restoration admission precedes the first space flip. The
   * next planner must supply the complete copy envelope, not local headroom. */
  if(___COLLECTION(___vms).decision!=1 ||
     ___COLLECTION(___vms).census.state!=___GC_PLAN_ACCEPTED ||
     np<1 || nw<1 || nw>np || np+___COLLECTION(___vms).planned_copy_sections>the_msections->nb_sections)
    rc_contract_error("Physical setup requires the all-participant accepted plan");
  ___COLLECTION(___vms).destination_offset=(___MSECTION_SIZE>>1)-
    ___PSTATE_FROM_PROCESSOR_ID(0,___vms)->mem.tospace_offset_;
  for(i=0;i<np;i++) {
    ___processor_state owner=___PSTATE_FROM_PROCESSOR_ID(i,___vms);
    ___SIZE_TS length=owner->context->stack_break+___FIRST_BREAK_FRAME_SPACE-owner->context->fp;
    if(length<0 || length>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE ||
       owner->mem.tospace_offset_==___COLLECTION(___vms).destination_offset ||
       (i>=nw && restore_loan_words(length)<___MSECTION_FUDGE+2)) fatal_heap_overflow();
  }
  { ___msection *section=the_msections->head;
    while(section) { section->copy_gate=0;
      memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
      section=section->next; } }
  /* Context restoration and worker destinations are separate physical grants.
   * RC/still chains and other root-domain state stay in the existing context. */
  for (i=0; i<np; i++)
    {
      ___processor_state ___ps = ___PSTATE_FROM_PROCESSOR_ID(i,___vms);
      ___gc_resume_space *r = &___RESUME(___vms,i);
      ___SIZE_TS length = (___ps->context->stack_break +
                          ___FIRST_BREAK_FRAME_SPACE) - ___ps->context->fp;
      ___SIZE_TS loan;
      if(r->stack_section!=alloc || r->context!=___ps->context || r->epoch!=___COLLECTION(___vms).epoch)
        rc_contract_error("Restoration grant changed after preflight");
      tospace_offset = ___COLLECTION(___vms).destination_offset;
      msection_free_list = 0;
      words_prev_msections = 0;
      heap_msection = 0;
      set_stack_msection(___ps,alloc);
      r->context = ___ps->context;
      r->owner = ___ps;
      r->epoch = ___COLLECTION(___vms).epoch;
      r->stack_section = alloc;
      r->loan_base = alloc_stack_limit;
      /* Keep the old 3/4 fallback ceiling, capped by the actual restoration
       * footprint plus stack fudge. This does not enlarge the copy grant. */
      loan = restore_loan_words(length);
      r->loan_limit = r->loan_base+loan;
      r->stack_floor = alloc_stack_limit;
      r->loan_used = r->accepted = r->restored = 0;
      r->source_worker = i<nw ? i : -1;
      alloc = alloc->next;
    }

  for (i=0; i<nw; i++)
    {
      ___collector_worker *work = &___COLLECTORS(___vms)[i];
      ___processor_state ___ps = work->carrier;

      work->census=0;
      work->destination_revisits=0;
      work->copied_words = 0;
      work->copied_source_words = 0;
      work->copy_request.state = 0; /* preceding round physically drained */
      work->duplicate_scans = 0;
      work->copy_begin_ = 0;
      work->copy_past_ = 0;
      work->tail_cell_ = 0;
      work->copy_reserved_words_ = 0;
      work->copy_padding_words_ = 0;
      work->tail_started_ = 0;
      work->tail_completed_ = 0;
      work->frame_accesses_ = 0;
      work->frame_links_ = 0;
      work->local_scan_chunk_ = 0;
      work->active_scan_chunk_ = 0;
      work->active_scan_object_ = 0;
      work->scan_origin_ = 0;
      work->chunks_published_ = 0;
      work->chunks_claimed_ = 0;
      work->chunks_completed_ = 0;
      work->reserve = &___RESUME(___vms,
        ___PROCESSOR_ID(___ps,___vms));
      work->arena.epoch = ___COLLECTION(___vms).epoch;
      work->arena.retired_words = work->arena.refills = 0;
      work->arena.handed_off = 0;
      prepare_worker_msection(work,alloc,
        alloc->base+___COLLECTION(___vms).destination_offset,
        alloc->base+___COLLECTION(___vms).destination_offset+(___MSECTION_SIZE>>1));
      alloc_msection = alloc;
      alloc = alloc->next;
      scan_ptr = alloc_heap_chunk_start;
      require_chunk_transition(work,alloc_heap_chunk_start,0,2);
      work->local_scan_chunk_ = alloc_heap_chunk_start;

      heap_chunks_to_scan = NULL_CHUNK_LINK;
      heap_chunks_to_scan_head = &heap_chunks_to_scan;
      heap_chunks_to_scan_tail = &heap_chunks_to_scan;
      still_objs_to_scan = 0;
    }

  nb_msections_assigned = np+nw;
  nb_msections_stacks   = np;

#ifndef ___SINGLE_THREADED_VMS

  /* Initialize the active scanning workers count */

  scan_workers_count[0] = nw;
  scan_workers_count[1] = nw;

#endif

#undef ___VMSTATE_MEM
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var
}


/* End internal memory fragment. */

___HIDDEN void prepare_heap_msection(___processor_state ps)
{
  *ps->mem.alloc_heap_ptr_++=NULL_CHUNK_LINK;
  ps->mem.alloc_heap_chunk_start_=ps->mem.alloc_heap_ptr_;
  ps->mem.alloc_heap_chunk_limit_=ps->mem.alloc_heap_ptr_+___MSECTION_CHUNK;
}
