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


/* Caller holds the VM allocation lock. Inspection does not claim a section. */
___HIDDEN ___msection *peek_fresh_msection(___processor_state ___ps)
{
  return nb_msections_assigned==0 ? the_msections->head : alloc_msection->next;
}

___HIDDEN void commit_fresh_msection(___processor_state ___ps, ___msection *ms)
{
  alloc_msection=ms;
  ++nb_msections_assigned;
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

  result = peek_fresh_msection(___ps);

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
    commit_fresh_msection(___ps, result);

  return result;
}


/* The carrier alone edits its stack claims and private reuse list. A
 * section used by a heap stays ineligible through the end of this parity,
 * including after the heap cursor has moved elsewhere. */
___HIDDEN ___msection *take_released_stack_section(___processor_state ___ps)
{
  ___msection *section=msection_free_list;
  if(section!=0)
    {
      section_claim *claim=section_claim_at(section,tospace_offset);
      if(claim->stack_owner!=___ps || claim->stack_state!=STACK_REUSABLE ||
         claim->heap_used)
        { rc_contract_error("Invalid stack section reuse claim"); return 0; }
      msection_free_list=claim->reuse_next;
      ___gc_copy_acquire(&section->copy_gate);
      *claim=(section_claim){0};
      ___gc_copy_release(&section->copy_gate);
    }
  return section;
}

enum raw_stack_mark { RAW_STACK_START=1, RAW_STACK_END=2 };

___HIDDEN int raw_stack_mark_at(const unsigned char *marks, ___SIZE_TS index)
{
  return (marks[index/4] >> (2*(index%4))) & 3;
}

___HIDDEN void raw_stack_set_mark(unsigned char *marks, ___SIZE_TS index,
                                 enum raw_stack_mark mark)
{
  marks[index/4] |= mark << (2*(index%4));
}

/* Called by the running stack owner before publishing a detached raw fp.
 * Once detached, a segment's bounds survive stack parking and undo. */
___EXP_FUNC(void,___publish_raw_stack_span)
 (___processor_state ___ps, ___WORD *top, ___WORD *brk)
{
  ___msection *section=stack_msection;
  section_claim *claim;
  ___WORD *base;
  ___SIZE_TS words;

  if (!section || (tospace_offset!=0 && tospace_offset!=(___MSECTION_SIZE>>1)))
    { rc_contract_error("Raw stack span lacks a current half"); return; }

  base=start_of_tospace(section);
  claim=section_claim_at(section,tospace_offset);
  ___gc_copy_acquire(&section->copy_gate);
  if (claim->stack_owner!=___ps || claim->stack_state!=STACK_ACTIVE ||
      brk!=___ps->context->stack_break || top==brk ||
      !___gc_stack_span_words(base,base+(___MSECTION_SIZE>>1),top,brk,
                              ___BREAK_FRAME_SPACE,&words) ||
      (claim->raw_marks && brk>=claim->raw_low))
    {
      ___gc_copy_release(&section->copy_gate);
      rc_contract_error("Invalid raw stack source span");
      return;
    }
  if (!claim->raw_marks)
    {
      claim->raw_marks=___CAST(unsigned char*,section_claim_at(section,0)+2)
        +(tospace_offset ? RAW_STACK_MAP_BYTES : 0);
      memset(claim->raw_marks,0,RAW_STACK_MAP_BYTES);
      claim->raw_high=brk;
    }
  raw_stack_set_mark(claim->raw_marks,top-base,RAW_STACK_START);
  raw_stack_set_mark(claim->raw_marks,brk-base,RAW_STACK_END);
  claim->raw_low=top;
  ___gc_copy_release(&section->copy_gate);
}

___HIDDEN void park_stack_section(___processor_state ___ps, ___msection *section,
                                  ___WORD *floor, ___WORD *top, ___WORD *brk)
{
  section_claim *claim=section_claim_at(section,tospace_offset);
  ___WORD *base=start_of_tospace(section);
  ___SIZE_TS words;
  ___UWORD low=___CAST(___UWORD,floor);
  if (claim->stack_owner!=___ps || claim->stack_state!=STACK_ACTIVE ||
      low<___CAST(___UWORD,base) || low>___CAST(___UWORD,top) || low%___WS ||
      top==brk || !___gc_stack_span_words(base,base+(___MSECTION_SIZE>>1),
                                          top,brk,___BREAK_FRAME_SPACE,&words)) {
    rc_contract_error("Invalid parked stack source span");
    return;
  }
  ___gc_copy_acquire(&section->copy_gate);
  claim->stack_floor=floor;
  claim->parked_top=top;
  claim->parked_break=brk;
  claim->stack_state=STACK_PARKED;
  ___gc_copy_release(&section->copy_gate);
}

___HIDDEN void release_stack_section(___processor_state ___ps, ___msection *section)
{
  section_claim *claim=section_claim_at(section,tospace_offset);
  if(claim->stack_owner!=___ps || claim->stack_state!=STACK_ACTIVE ||
     claim->heap_used ||
     __atomic_load_n(&claim->source_pins, __ATOMIC_ACQUIRE))
    { rc_contract_error("Stack section release lacks exclusive ownership"); return; }
  ___gc_copy_acquire(&section->copy_gate);
  claim->stack_state=STACK_REUSABLE;
  claim->reuse_next=msection_free_list;
  msection_free_list=section;
  ___gc_copy_release(&section->copy_gate);
}

___HIDDEN void set_stack_msection
   ___P((___processor_state ___ps,
         ___msection *ms),
        (___ps,
         ms)
___processor_state ___ps;
___msection *ms;)
{
  section_claim *claim=section_claim_at(ms,tospace_offset);
  ___gc_copy_acquire(&ms->copy_gate);
  claim->stack_owner=___ps;
  claim->stack_floor=claim->parked_top=claim->parked_break=0;
  claim->stack_state=STACK_ACTIVE;
  ___gc_copy_release(&ms->copy_gate);
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


/* A half can contain both regions. A parked stack retains its floor
 * after the carrier moves its active stack to another section. */
___HIDDEN ___BOOL current_heap_interval_matches(___processor_state ___ps,
                                                 ___WORD *cursor)
{
  const section_claim *claim;
  ___WORD *base, *past, *floor;
  if (!heap_msection ||
      (tospace_offset!=0 && tospace_offset!=(___MSECTION_SIZE>>1)))
    return 0;
  base=start_of_tospace(heap_msection);
  past=base+(___MSECTION_SIZE>>1);
  claim=section_claim_at(heap_msection,tospace_offset);
  if (claim->stack_state==STACK_ACTIVE || claim->stack_state==STACK_PARKED)
    {
      if (claim->stack_owner!=___ps) return 0;
      if (claim->stack_state==STACK_ACTIVE)
        {
          if (heap_msection!=stack_msection) return 0;
          floor=alloc_stack_limit;
        }
      else
        floor=claim->stack_floor;
      if (___CAST(___UWORD,floor)<___CAST(___UWORD,base) ||
          ___CAST(___UWORD,floor)>___CAST(___UWORD,past))
        return 0;
      past=floor;
    }
  {
    ___WORD *limit=alloc_heap_limit;
    if (limit && ___CAST(___UWORD,past)<___CAST(___UWORD,limit))
      limit=___CAST(___WORD*,past);
    return ___gc_resume_heap_interval_matches(base,past,alloc_heap_start,
                                              cursor,limit);
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
  section_claim_at(ms,tospace_offset)->heap_used=1;
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

/* Soft room of an unpublished section. Return zero if its split cannot
 * leave the existing guard or if it cannot supply a usable interval. */
static int rest_predicted_soft_room(___processor_state ___ps, ___msection *ms,
                                   ___WORD *fp, ___SIZE_TS *room)
{
  ___SIZE_TS hard;
  if (!ms || !room) return 0;
  if (ms==stack_msection)
    {
      ___SIZE_TS space, quarter;
      if (!fp || fp<alloc_stack_limit || fp>alloc_stack_start) return 0;
      space=fp-alloc_stack_limit;
      if (space<2*___MSECTION_FUDGE) return 0;
      quarter=(space-2*___MSECTION_FUDGE)>>2;
      hard=3*quarter+___MSECTION_FUDGE;
    }
  else
    hard=___MSECTION_SIZE>>1;
  if (hard<=___MSECTION_FUDGE) { *room=0; return 0; }
  *room=hard-___MSECTION_FUDGE;
  return 1;
}

___BOOL ___rest_physical_tail_short(___processor_state ps,
                                  ___WORD pending, ___WORD np)
{
  ___processor_state ___ps=ps;
  ___WORD words, pairs, payload, *hp;
  ___WORD pair_words=(___WORD)(___PAIR_SIZE+___PAIR_BODY);
  /* Short soft room with a sufficient owned tail never reaches the lock. */
  if (!ps || !ps->context || pending<0 || np<0) return 0;
  if (pending!=0 && pair_words>((___WORD)((~(___UWORD)0)>>1))/pending) return 0;
  pairs=pending*pair_words;
  if (pairs>((___WORD)((~(___UWORD)0)>>1))-np) return 0;
  payload=pairs+np;
  if (payload>((___WORD)((~(___UWORD)0)>>1))-(___WORD)___VECTOR_BODY) return 0;
  words=payload+(___WORD)___VECTOR_BODY;
  hp=ps->context->hp;
  if (!hp || !alloc_heap_limit || hp>alloc_heap_limit) return 0;
  if ((___SIZE_TS)(alloc_heap_limit-hp)>___MSECTION_FUDGE &&
      (___SIZE_TS)(alloc_heap_limit-hp)-___MSECTION_FUDGE>=(___SIZE_TS)words)
    return 0;
  return 1;
}

___BOOL ___rest_publish_owned_soft_edge(___processor_state ps,
                                       ___WORD pending, ___WORD np)
{
  ___processor_state ___ps=ps;
  ___WORD *hp, *edge;
  if (___rest_physical_tail_short(ps, pending, np)) return 0;
  if (!ps || !ps->context) return 0;
  hp=ps->context->hp;
  if (!hp || !alloc_heap_limit ||
      (___SIZE_TS)(alloc_heap_limit-hp)<=___MSECTION_FUDGE)
    return 0;
  edge=alloc_heap_limit-___MSECTION_FUDGE;
  if (edge<hp) return 0;
  /* Carrier-local soft edge of the section already owned. No claim. */
  if (!ps->heap_limit || ps->heap_limit<edge) ps->heap_limit=edge;
  return ps->heap_limit && hp<=ps->heap_limit;
}

#ifdef ___GAMBIT_REST_OBSERVATION
#include <sched.h>
#include <time.h>
/* The fixture arms one two-carrier contest. Both carriers publish a lock
 * request before either takes the allocation lock. Waiting services a
 * pending collection so the other carrier can leave its barrier. */
static struct {
  uintptr_t vm;
  uint64_t case_id, epoch;
  unsigned arrivals, reported;
  ___WORD words;
  int cap_bound;
  int claimed;
  ___SIZE_T cap;
} rest_section_contest;

/* Admission here is the generated two-argument check, including the contest cap. */
static ___BOOL rest_overlay_section_admitted(___processor_state ps, ___SIZE_T max_heap)
{
  return ___rest_new_section_admitted(ps, max_heap);
}

int ___rest_observation_arm_section_contest(___processor_state ___ps, ___WORD words)
{
  uint64_t id=rest_observation_current_case();
  if (!___ps || ___ps!=___PSTATE || !id || words<0) return 0;
  ALLOC_MEM_LOCK();
  if (words) {
    if (__atomic_load_n(&rest_section_contest.vm,__ATOMIC_ACQUIRE)) {
      ALLOC_MEM_UNLOCK();
      return 0;
    }
    rest_section_contest.case_id=id;
    rest_section_contest.words=words;
    rest_section_contest.epoch=0;
    rest_section_contest.cap_bound=0;
    rest_section_contest.claimed=0;
    rest_observation_set_case_hold(1);
    __atomic_store_n(&rest_section_contest.arrivals,0,__ATOMIC_RELAXED);
    __atomic_store_n(&rest_section_contest.reported,0,__ATOMIC_RELAXED);
    __atomic_store_n(&rest_section_contest.vm,
      (uintptr_t)___VMSTATE_FROM_PSTATE(___ps),__ATOMIC_RELEASE);
  } else if (__atomic_load_n(&rest_section_contest.vm,__ATOMIC_ACQUIRE)==
             (uintptr_t)___VMSTATE_FROM_PSTATE(___ps)) {
    __atomic_store_n(&rest_section_contest.vm,0,__ATOMIC_RELEASE);
    rest_observation_set_case_hold(0);
  }
  ALLOC_MEM_UNLOCK();
  return 1;
}

static int rest_section_contest_wait(___processor_state ___ps, volatile unsigned *mask)
{
  struct timespec start, now;
  (void)___ps;
  if (clock_gettime(CLOCK_MONOTONIC,&start)!=0) return 0;
  while (__atomic_load_n(mask,__ATOMIC_ACQUIRE)!=3) {
    sched_yield();
    if (clock_gettime(CLOCK_MONOTONIC,&now)!=0 ||
        (now.tv_sec-start.tv_sec)*1000000000LL+now.tv_nsec-start.tv_nsec>=2000000000LL)
      return 0;
  }
  return 1;
}

static int rest_section_contest_join(___processor_state ___ps, ___WORD words)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
  int processor=___PROCESSOR_ID(___ps,vm);
  if (__atomic_load_n(&rest_section_contest.vm,__ATOMIC_ACQUIRE)!=(uintptr_t)vm ||
      processor<0 || processor>1 ||
      rest_section_contest.case_id!=rest_observation_current_case() ||
      rest_section_contest.words!=words)
    return 0;
  if (__atomic_fetch_or(&rest_section_contest.arrivals,1u<<processor,__ATOMIC_ACQ_REL)&(1u<<processor))
    return __atomic_load_n(&rest_section_contest.arrivals,__ATOMIC_ACQUIRE)==3;
  return rest_section_contest_wait(___ps,&rest_section_contest.arrivals);
}

/* This cap is used by this rest admission and its receipt only. The
 * configured heap limit and the collector's recovery reserve are unchanged. */
static ___SIZE_T rest_section_contest_cap(___processor_state ___ps, ___SIZE_T configured)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
  uint64_t epoch=___COLLECTION(vm).epoch;
  ___SIZE_T cap, still, assigned;
  if (__atomic_load_n(&rest_section_contest.vm,__ATOMIC_ACQUIRE)!=(uintptr_t)vm ||
      rest_section_contest.case_id!=rest_observation_current_case())
    return configured;
  if (rest_section_contest.cap_bound) {
    /* A collection between the two claims must not turn the second into an
     * unlimited grant. The bound frozen by the first claim stays in force. */
    cap=rest_section_contest.cap;
  } else {
    const ___SIZE_T max_words=(~(___SIZE_T)0)>>___LWS;
    if (occupied_words_still<0 || nb_msections_assigned<0) return configured;
    still=(___SIZE_T)occupied_words_still;
    assigned=(___SIZE_T)nb_msections_assigned;
    if (still>max_words || assigned>=(max_words-still)/___MSECTION_SIZE) return configured;
    cap=(still+(assigned+1)*(___SIZE_T)___MSECTION_SIZE)<<___LWS;
    rest_section_contest.cap=cap;
    rest_section_contest.epoch=epoch;
    rest_section_contest.cap_bound=1;
  }
  return configured && configured<cap ? configured : cap;
}
#endif

___BOOL ___rest_extend_interval(___processor_state ps,
                               ___WORD pending, ___WORD np)
{
  ___processor_state ___ps=ps;
  ___WORD words, pairs, payload;
  ___WORD *hp, *fp;
  ___WORD pair_words=(___WORD)(___PAIR_SIZE+___PAIR_BODY);
  if (!___ps || ___ps!=___PSTATE || !___ps->context || pending<0 || np<0) return 0;
  if (pending!=0 && pair_words>((___WORD)((~(___UWORD)0)>>1))/pending) return 0;
  pairs=pending*pair_words;
  if (pairs>((___WORD)((~(___UWORD)0)>>1))-np) return 0;
  payload=pairs+np;
  if (payload>((___WORD)((~(___UWORD)0)>>1))-(___WORD)___VECTOR_BODY) return 0;
  words=payload+(___WORD)___VECTOR_BODY;
  hp=___ps->context->hp;
  fp=___ps->context->fp;
  if (!current_heap_interval_matches(___ps, hp)) return 0;
  if ((___SIZE_TS)(alloc_heap_limit-hp)>___MSECTION_FUDGE &&
      (___SIZE_TS)(alloc_heap_limit-hp)-___MSECTION_FUDGE>=(___SIZE_TS)words)
    return 1;
  /* A rejected candidate has no claim to refund. In particular, do not
   * restore a VM cursor observed before another processor took the lock. */
  {
    ___msection *fresh, *ms;
    ___SIZE_TS room=0;
    ___SIZE_T max_heap;
#ifdef ___GAMBIT_REST_OBSERVATION
    int contest, matched;
    contest=rest_section_contest_join(___ps,words);
    matched=contest || (__atomic_load_n(&rest_section_contest.vm,__ATOMIC_ACQUIRE)==
                        (uintptr_t)___VMSTATE_FROM_PSTATE(___ps) &&
                        rest_section_contest.case_id==rest_observation_current_case() &&
                        rest_section_contest.words==words);
    if (matched && ___ps->context) {
      hp=___ps->context->hp;
      fp=___ps->context->fp;
    }
    if (matched) {
      unsigned flags=(___rest_stack_slots_fit(___ps,fp,1) ? 2 : 0) |
                     (rest_observation_reloaded ? 4 : 0);
      REST_OBS(REST_SECTION_VIEW,___ps,rest_observation_attempt_record(___ps),
               rest_observation_attempt_id(___ps),
               ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
               heap_msection,tospace_offset,hp,___ps->heap_limit,alloc_heap_limit,
               fp,words,flags);
    }
#endif
    REST_OBS(REST_LOCK_REQUEST,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
             ___VMSTATE_FROM_PSTATE(___ps),___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps)),
             words,hp,alloc_heap_limit,___MSECTION_FUDGE,fp,0);
#ifdef ___GAMBIT_REST_OBSERVATION
    /* Both requests are published before either carrier locks. */
    if (matched) {
      int processor=___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps));
      if (processor>=0 && processor<=1)
        __atomic_fetch_or(&rest_section_contest.reported,1u<<processor,__ATOMIC_ACQ_REL);
      rest_section_contest_wait(___ps,&rest_section_contest.reported);
    }
#endif
    ALLOC_MEM_LOCK();
    max_heap=___GSTATE->setup_params.max_heap;
#ifdef ___GAMBIT_REST_OBSERVATION
    /* The first committed contest claim keeps the only slot. A later carrier
     * is refused even when a collection rebuilt the same numeric room. */
    if (matched)
      max_heap=rest_section_contest_cap(___ps,max_heap);
#endif
    /* Read the admission inputs and next candidate under the same lock as
     * the actual bound, ownership check and commit. The probe only peeks. */
    REST_OBS(REST_LOCK,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
             ___VMSTATE_FROM_PSTATE(___ps),alloc_msection,nb_msections_assigned,
             the_msections->nb_sections,max_heap,occupied_words_still,
             ___MSECTION_SIZE,nb_msections_assigned==0 || alloc_msection
                             ? peek_fresh_msection(___ps) : 0);
    if (custom_msection_alloc ||
        (matched && rest_section_contest.claimed) ||
        !rest_overlay_section_admitted(___ps,max_heap)) {
      REST_OBS(REST_REFUSE,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),
               alloc_msection,nb_msections_assigned,custom_msection_alloc ? 4 : 1,0,0,0,0);
      REST_OBS(REST_UNLOCK,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),0,0,0,0,0,0,0);
      ALLOC_MEM_UNLOCK();
      return 0;
    }
    fresh=peek_fresh_msection(___ps);
    /* A missing node, or a node that already has a stack or heap owner, is
     * not an eligible fresh section. Refusing leaves the owner's grant
     * unchanged. Publishing it would move that stack break outside its grant. */
    if (!fresh ||
        section_claim_at(fresh,tospace_offset)->stack_owner ||
        section_claim_at(fresh,tospace_offset)->stack_state ||
        section_claim_at(fresh,tospace_offset)->heap_used) {
      REST_OBS(REST_REFUSE,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),
               alloc_msection,nb_msections_assigned,fresh ? 3 : 2,0,0,0,0);
      REST_OBS(REST_UNLOCK,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),0,0,0,0,0,0,0);
      ALLOC_MEM_UNLOCK();
      return 0;
    }
    ms=fresh;
    REST_OBS(REST_CAPACITY,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),
             ms,words,fp,alloc_msection,nb_msections_assigned,ms->next,tospace_offset);
    if (!rest_predicted_soft_room(___ps, ms, fp, &room) || room<(___SIZE_TS)words) {
      REST_OBS(REST_REFUSE,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),
               alloc_msection,nb_msections_assigned,5,room,words,0,0);
      REST_OBS(REST_UNLOCK,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),0,0,0,0,0,0,0);
      ALLOC_MEM_UNLOCK();
      return 0;
    }
    if (fresh) commit_fresh_msection(___ps, fresh);
#ifdef ___GAMBIT_REST_OBSERVATION
    if (matched) rest_section_contest.claimed=1;
#endif
    REST_OBS(REST_CLAIM,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),
             ms,room,words,alloc_msection,nb_msections_assigned,start_of_tospace(ms),tospace_offset);
    words_prev_msections += hp - alloc_heap_start;
    /* Publication uses the section, base and room captured while this
     * processor still holds the claim. Shared cursors after unlock belong
     * to whoever next takes the lock. */
    {
      ___msection *claimed=ms;
      ___WORD *base=start_of_tospace(ms);
      ___SIZE_TS claimed_room=room;
      ___WORD *hard;
      REST_OBS(REST_UNLOCK,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,___VMSTATE_FROM_PSTATE(___ps),0,0,0,0,0,0,0);
      ALLOC_MEM_UNLOCK();
      alloc_stack_ptr=fp;
      set_heap_msection_possibly_sharing_with_stack(___ps, claimed);
      ___ps->context->hp=base;
      ___ps->heap_limit=base+claimed_room;
      hard=base+(___MSECTION_SIZE>>1);
      if (hard > base+___MSECTION_FUDGE &&
          ___ps->heap_limit > hard-___MSECTION_FUDGE)
        ___ps->heap_limit = hard-___MSECTION_FUDGE;
      REST_OBS(REST_SECTION_PUBLISHED,___ps,rest_observation_attempt_record(___ps),
               rest_observation_attempt_id(___ps),___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
               ___VMSTATE_FROM_PSTATE(___ps),heap_msection,tospace_offset,
               ___ps->context->hp,___ps->heap_limit,alloc_heap_limit,words,___MSECTION_FUDGE);
      return base && ___ps->heap_limit &&
        base<=___ps->heap_limit &&
        (___SIZE_TS)(___ps->heap_limit-base)>=(___SIZE_TS)words;
    }
  }
}

static ___msection *resolve_source_half(___msections *sections, ___WORD *top,
                                       ___SIZE_TS source_offset,
                                       ___SIZE_TS *half_words);
static ___BOOL source_claim_is_live(const section_claim *claim);
/* 1 wrong owner, 2 stale half, 3 invalid cursor. Zero means a frame load is allowed. */
static int rest_chain_frame_refused(___processor_state ps, const section_claim *claim,
                                    ___WORD *cursor, ___WORD *base, ___WORD *past)
{
  if (!ps || !claim || !source_claim_is_live(claim)) return 2;
  if (claim->stack_owner!=ps) return 1;
  if (!cursor || (___CAST(___UWORD,cursor)&(___WS-1)) ||
      (base && past && (cursor<base || cursor>past))) return 3;
  return 0;
}
static int read_admitted_stack_frame(const section_claim *claim,
                                    ___WORD *top, ___SIZE_TS half_words,
                                    ___WORD *logical_past,
                                    ___WORD *ra, int carry,
                                    ___frame_descriptor *frame,
                                    ___WORD **known_break_out);

___BOOL ___rest_caller_chain(___WORD *window, ___WORD na, ___WORD ra,
                            ___WORD *stack_limit, ___WORD *stack_past,
                            ___WORD internal_return)
{
  ___processor_state ___ps=___PSTATE;
  ___WORD *top;
  ___msection *held=0;
  ___WORD *held_base=0;
  ___WORD *held_past=0;
  ___SIZE_TS held_offset=0;
  ___msection *pinned=0;
  ___SIZE_TS pinned_offset=0;
  int guard=0;
  if (!___ps || !window || na<0 || !stack_limit || !stack_past || !ra) return 0;
  (void)internal_return;
  top=window+na;
  if (top<stack_limit || top>stack_past) return 0;
#define REST_CHAIN_UNPIN(flag) \
  do { \
    if (pinned) { \
      __atomic_fetch_sub(&section_claim_at(pinned,pinned_offset)->source_pins, \
                         1, __ATOMIC_ACQ_REL); \
      REST_OBS(REST_UNPIN,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps), \
               ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch, \
               pinned,pinned_offset,(flag),0,0,0,0,0); \
      __atomic_fetch_add(&___rest_chain_unpins, 1, __ATOMIC_RELAXED); \
      pinned=0; \
    } \
  } while (0)
  while (guard++<100000)
    {
      ___frame_descriptor fd;
      ___WORD *base, *known_break=0;
      ___SIZE_TS half_words=0;
      ___msection *section;
      ___SIZE_TS offset;
      ___WORD *logical;
      if (top==stack_past) {
        /* A validated parked break link is the successor. The pin taken
         * before the last old read stays until that successor is acquired.
         * An invalid break is refused before that link word is loaded. */
        ___WORD link;
        if (!stack_past || (___CAST(___UWORD,stack_past)&(___WS-1)) ||
            (held && rest_chain_frame_refused(___ps,section_claim_at(held,held_offset),
                                              stack_past,held_base,held_past))) {
          REST_CHAIN_UNPIN(1);
          break;
        }
        link=___FP_STK(stack_past,-___BREAK_FRAME_NEXT);
        ___WORD *next=___CAST(___WORD*,link);
        ___msection *next_section=0;
        ___SIZE_TS next_offset=0, next_half=0;
        section_claim *next_claim;
        if (!link || (___CAST(___UWORD,link)&(___WS-1))!=0) {
          REST_CHAIN_UNPIN(1);
          break;
        }
        /* A break inserted inside this half points at an older frame still
         * in the same section. The section-crossing link is the first break
         * at the high end, not this intermediate frame. */
        if (held_base && ___ps->context && next>stack_past && next<held_past) {
          ___WORD *section_break=___ps->context->stack_start-___FIRST_BREAK_FRAME_SPACE;
          if (next<section_break && section_break>=held_base &&
              section_break<=held_past) {
            top=next;
            stack_past=section_break;
            continue;
          }
        }
        if (pinned && pinned==held) {
          REST_OBS(REST_BREAK_LINK,___ps,rest_observation_attempt_record(___ps),
                   rest_observation_attempt_id(___ps),___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
                   pinned,pinned_offset,section_claim_at(pinned,pinned_offset)->stack_owner,
                   stack_past+___BREAK_FRAME_NEXT,next,stack_past,___BREAK_FRAME_NEXT,___WS);
        }
        ALLOC_MEM_LOCK();
        next_offset=tospace_offset;
        next_section=resolve_source_half(the_msections, next, next_offset, &next_half);
        if (!next_section) {
          next_offset=tospace_offset==0 ? (___MSECTION_SIZE>>1) : 0;
          next_section=resolve_source_half(the_msections, next, next_offset, &next_half);
        }
        next_claim=next_section ? section_claim_at(next_section,next_offset) : 0;
        if (!next_section || next_section==held || !source_claim_is_live(next_claim) ||
            next_claim->stack_state!=STACK_PARKED ||
            !next_claim->parked_top || !next_claim->parked_break ||
            next<next_claim->parked_top || next>next_claim->parked_break) {
          ALLOC_MEM_UNLOCK();
          REST_CHAIN_UNPIN(1);
          break;
        }
        ___gc_copy_acquire(&next_section->copy_gate);
        __atomic_fetch_add(&___rest_chain_gates, 1, __ATOMIC_RELAXED);
        __atomic_fetch_add(&___rest_chain_crossings, 1, __ATOMIC_RELAXED);
        REST_OBS(REST_SUCCESSOR,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,
                 next_section,next_offset,next_claim->stack_owner,next,pinned,pinned_offset,1,0);
        if (held && held!=next_section) ___gc_copy_release(&held->copy_gate);
        held=next_section;
        held_offset=next_offset;
        held_base=next_section->base+next_offset;
        held_past=held_base+(___MSECTION_SIZE>>1);
        stack_limit=next_claim->parked_top;
        stack_past=next_claim->parked_break;
        top=next;
        ALLOC_MEM_UNLOCK();
        REST_CHAIN_UNPIN(0);
        continue;
      }
      if (top<stack_limit || top>stack_past) goto refuse;
      /* Same section: keep the gate already held and do not reenter the
       * allocation lock. A different section keeps a source pin, drops the
       * gate, then takes ALLOC_MEM_LOCK before the successor gate. */
      if (held && held_base &&
          ___CAST(___UWORD,top)>=___CAST(___UWORD,held_base) &&
          ___CAST(___UWORD,top)<___CAST(___UWORD,held_past))
        {
          section=held;
          offset=held_offset;
          half_words=held_past-top;
        }
      else
        {
          if (held) {
            /* The pin already covers the last read when it was taken
             * before that read. Do not take a second one on the way out. */
            if (pinned!=held) {
              __atomic_fetch_add(&section_claim_at(held,held_offset)->source_pins,
                                 1, __ATOMIC_RELEASE);
              REST_OBS(REST_PIN,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,held,held_offset,
                       section_claim_at(held,held_offset)->stack_owner,top,held_base,held_past,0,0);
              __atomic_fetch_add(&___rest_chain_old_pins, 1, __ATOMIC_RELAXED);
              pinned=held;
              pinned_offset=held_offset;
            }
            ___gc_copy_release(&held->copy_gate);
            held=0;
          }
          ALLOC_MEM_LOCK();
          offset=tospace_offset;
          section=resolve_source_half(the_msections, top, offset, &half_words);
          if (!section) {
            offset=tospace_offset==0 ? (___MSECTION_SIZE>>1) : 0;
            section=resolve_source_half(the_msections, top, offset, &half_words);
          }
          if (section) {
            ___gc_copy_acquire(&section->copy_gate);
            __atomic_fetch_add(&___rest_chain_gates, 1, __ATOMIC_RELAXED);
            held=section;
            held_offset=offset;
            held_base=section->base+offset;
            held_past=held_base+(___MSECTION_SIZE>>1);
            REST_OBS(REST_SUCCESSOR,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,section,offset,
                     section_claim_at(section,offset)->stack_owner,top,pinned,pinned_offset,0,0);
          }
          ALLOC_MEM_UNLOCK();
          if (!section) {
            REST_CHAIN_UNPIN(1);
            goto refuse;
          }
          /* Successor authority is recorded. Drop the old pin before any
           * read of the new section; that read is not an old-source use. */
          if (pinned && pinned!=held) REST_CHAIN_UNPIN(0);
        }
      logical=stack_past;
      if (logical<top || (___SIZE_TS)(logical-top)>half_words)
        logical=top+half_words;
      /* Pin this section before its read, so the last read of an old
       * section is inside the pin rather than beside a later successor read. */
      if (held && pinned!=held) {
        ___WORD link=___FP_STK(stack_past,-___BREAK_FRAME_NEXT);
        if (link && (___CAST(___UWORD,link)&(___WS-1))==0) {
          __atomic_fetch_add(&section_claim_at(held,held_offset)->source_pins,
                             1, __ATOMIC_RELEASE);
          REST_OBS(REST_PIN,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,held,held_offset,
                   section_claim_at(held,held_offset)->stack_owner,top,held_base,held_past,0,0);
          __atomic_fetch_add(&___rest_chain_old_pins, 1, __ATOMIC_RELAXED);
          pinned=held;
          pinned_offset=held_offset;
        }
      }
      if (held) __atomic_fetch_add(&___rest_chain_reads, 1, __ATOMIC_RELAXED);
      else __atomic_fetch_add(&___rest_chain_ungated, 1, __ATOMIC_RELAXED);
      if (rest_chain_frame_refused(___ps,section_claim_at(section,offset),
                                   top,held_base,held_past))
        goto refuse;
      if (!read_admitted_stack_frame(section_claim_at(section, offset),
                                    top, half_words, logical, &ra, 1, &fd,
                                    &known_break))
        goto refuse;
      base=top+___FRAME_SPACE(fd.fs);
      if (known_break && base>known_break) goto refuse;
      ra=___FP_STK(base, fd.link+1);
      top=base;
      REST_OBS(REST_SOURCE_READ,___ps,rest_observation_attempt_record(___ps),rest_observation_attempt_id(___ps),
             ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch,section,offset,
               section_claim_at(section,offset)->stack_owner,base-(fd.link+1),0,0,known_break,0);
      if (pinned && section==pinned)
        __atomic_fetch_add(&___rest_chain_old_reads, 1, __ATOMIC_RELAXED);
    }
  REST_CHAIN_UNPIN(0);
  if (held) ___gc_copy_release(&held->copy_gate);
  return top==stack_past;
refuse:
  REST_CHAIN_UNPIN(1);
  if (held) ___gc_copy_release(&held->copy_gate);
  return 0;
}
#undef REST_CHAIN_UNPIN

/* The three custody controls, using the same predicate as the caller chain.
 * The load counter stays zero: a refusal does not load a frame word. */
int ___rest_chain_control_probe(___processor_state ps, int which, long *loads)
{
  section_claim sample;
  int code;
  if (loads) *loads=0;
  if (!ps || ps!=___PSTATE || which<1 || which>3) return 0;
  memset(&sample,0,sizeof sample);
  sample.stack_owner=which==1 ? (___processor_state)((uintptr_t)ps+___WS) : ps;
  sample.stack_state=which==2 ? STACK_REUSABLE : STACK_ACTIVE;
  code=rest_chain_frame_refused(ps,&sample,
                                which==3 ? (___WORD*)1 : (___WORD*)___WS,
                                (___WORD*)___WS,(___WORD*)(___WS*4));
  return code;
}

/* Install a VM-assigned destination interval. No context heap cursor is
 * read or written by copying, including its slow refill path. Two terminal
 * chunk-link words remain outside the usable copy limit. */
___HIDDEN void prepare_worker_msection
 (___collector_worker *work, ___msection *section,
  ___WORD *base, ___WORD *limit)
{
  section_claim_at(section,___COLLECTION(work->vm).destination_offset)->heap_used=1;
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


/* Old-space roots, work queues, restore readers and cleanup are drained.
 * The caller runs once, with all mutators still behind the GC barrier. */
___HIDDEN void retire_section_claims(___msections *sections, ___SIZE_TS offset)
{
  ___msection *section;
  for(section=sections->head; section; section=section->next)
    *section_claim_at(section,offset)=(section_claim){0};
}

/* The cleanup collective publishes each frozen member's completion.
 * Check the whole roster before clearing any claim or permitting resize. */
___HIDDEN ___BOOL retire_drained_source_claims(___root_round *round,
                                               ___msections *sections,
                                               ___UWORD epoch)
{
  ___SIZE_TS half=___MSECTION_SIZE>>1;
  ___SIZE_TS destination=round->collection.destination_offset;
  ___SIZE_TS source;
  ___msection *section;
  int i;
  if (round->state!=___ROOT_ROUND_DRAINING || round->epoch!=epoch ||
      round->collection.epoch!=epoch || (destination!=0 && destination!=half) ||
      round->participants<1 || round->participants>___MAX_PROCESSORS ||
      round->participants!=round->collection.participant_count)
    return 0;
  source=half-destination;
  for(section=sections->head; section; section=section->next)
    if (__atomic_load_n(&section_claim_at(section,source)->source_pins,
                        __ATOMIC_ACQUIRE))
      return 0;
  for (i=0;i<round->participants;i++) {
    const ___root_member *member=&round->members[i];
    const ___gc_resume_space *resume=&round->resume[i];
    if (!___gc_resume_owner_matches(resume,member->owner) ||
        resume->context!=member->context || resume->epoch!=epoch ||
        resume->source_half!=source || !resume->accepted ||
        !resume->restored || !resume->source_drained)
      return 0;
  }
  retire_section_claims(sections,source);
  return 1;
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
    ___gc_resume_space *granted=&___RESUME(___vms,i);
    ___WORD *half=granted->source_section?granted->source_section->base+granted->source_half:0;
    ___SIZE_TS length=0;
    if(!half || granted->source_section!=owner->mem.stack_msection_ ||
       section_claim_at(granted->source_section, granted->source_half)->stack_state!=STACK_ACTIVE ||
       section_claim_at(granted->source_section, granted->source_half)->stack_owner!=owner ||
       granted->owner!=owner || granted->context!=owner->context ||
       owner->context->fp!=granted->source_fp ||
       owner->context->stack_break!=granted->source_break ||
       !___gc_stack_span_words(half, half+(___MSECTION_SIZE>>1),
         granted->source_fp, granted->source_break, ___FIRST_BREAK_FRAME_SPACE, &length) ||
       length!=granted->source_words ||
       !___gc_stack_cell_inside(granted->source_fp, length,
         ___gc_stack_first_read_cell(granted->source_fp)) ||
       length>(___MSECTION_SIZE>>1) ||
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
      ___SIZE_TS length;
      ___SIZE_TS loan;
      if(r->stack_section!=alloc || r->context!=___ps->context ||
         r->owner!=___ps || r->epoch!=___COLLECTION(___vms).epoch ||
         ___ps->context->fp!=r->source_fp ||
         ___ps->context->stack_break!=r->source_break)
        rc_contract_error("Restoration grant changed after preflight");
      length = r->source_words;
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
      r->loan_used = r->accepted = r->restored = r->copy_admitted = r->source_drained = 0;
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
