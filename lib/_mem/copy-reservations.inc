#line 3627 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* State transitions belong to an object identity, not to the worker/chunk
 * currently carrying it. A duplicate queue/frontier task transfers no new
 * authority to mutate fields. Its first scanner remains active until DONE.
 * READY excludes payload-initialization debt; first-field Tail remains owned
 * by the copying worker and is never executed by scan. */
#define GC_SCAN_UNPUBLISHED 0
#define GC_SCAN_READY       1
#define GC_SCAN_OWNED       2
#define GC_SCAN_DONE        3

___HIDDEN int change_object_scan_state
   ___P((___collector_worker *work, ___WORD *header, int from, int to),
        (work, header, from, to)
___collector_worker *work;
___WORD *header;
int from;
int to;)
{
  ___processor_state ___ps = work->carrier;
  int i = find_msection (the_msections, header);
  if (i >= 0 && i < the_msections->nb_sections)
    {
      ___PTRDIFF_T pos = header-the_msections->sections[i]->base-___COLLECTION(work->vm).destination_offset;
      if (pos >= 0 && pos < (___MSECTION_SIZE>>1))
        {
          int shift = 2*(pos % (___WORD_WIDTH/2));
          ___WORD mask = ___CAST(___WORD,___CAST(___UWORD,3) << shift);
          ___WORD *cell = the_msections->sections[i]->base + ___MSECTION_SIZE +
                         pos / (___WORD_WIDTH/2);
          ___WORD old = ___COMPARE_AND_SWAP_WORD(cell,0,0);
          for (;;)
            {
              int state = (___CAST(___UWORD,old) >> shift) & 3;
              ___WORD found;
              if (state != from)
                return state;
              found = ___COMPARE_AND_SWAP_WORD
                (cell,old,(old & ~mask) |
                 ___CAST(___WORD,___CAST(___UWORD,to) << shift));
              if (found == old)
                return from;
              old = found;
            }
        }
    }
  {
    static char *msgs[] = { "GC scan identity outside destination", NULL };
    ___fatal_error (msgs);
  }
  return -1;
}


___HIDDEN void publish_object_scan
   ___P((___collector_worker *work, ___WORD *header), (work, header)
___collector_worker *work;
___WORD *header;)
{
  if (change_object_scan_state(work,header,GC_SCAN_UNPUBLISHED,GC_SCAN_READY)
      != GC_SCAN_UNPUBLISHED)
    {
      static char *msgs[] = { "GC object initialized more than once", NULL };
      ___fatal_error (msgs);
    }
}


___HIDDEN ___msection *require_fromspace_copy_source
   ___P((___collector_worker *work, ___WORD *cell, ___WORD *body),
        (work, cell, body)
___collector_worker *work;
___WORD *cell;
___WORD *body;)
{
  ___processor_state ___ps = work->carrier;
  ___virtual_machine_state vms = work->vm;
  ___WORD *header = body-1;
  int i = find_msection (the_msections, header);
  if (i >= 0 && i < the_msections->nb_sections)
    {
      ___msection *section = the_msections->sections[i];
      ___UWORD address = ___CAST(___UWORD,header);
      ___UWORD base = ___CAST(___UWORD,section->base);
      if (address >= base && address-base < ___MSECTION_SIZE*___WS)
        {
          ___SIZE_TS pos = (address-base)/___WS;
          if (pos >= (___MSECTION_SIZE>>1)-___COLLECTION(vms).destination_offset &&
              pos < ___MSECTION_SIZE-___COLLECTION(vms).destination_offset)
            return section;
        }
    }
  /* Recopying tospace invalidates any source-size capacity bound. Do not
   * silently skip a repeated cell or enlarge the heap. Retain coordinates
   * at the ordinary fatal boundary. This per-attempt lookup is a deliberate
   * qualification cost, not a claimed fast-path optimization. */
  MISC_MEM_LOCK();
  if (___COLLECTION(vms).invalid_copy_worker < 0)
    {
      ___COLLECTION(vms).invalid_copy_cell = cell;
      ___COLLECTION(vms).invalid_copy_body = body;
      ___COLLECTION(vms).invalid_copy_worker = work->id;
    }
  MISC_MEM_UNLOCK();
  {
    static char *msgs[] = { "GC copy source is not in frozen fromspace", NULL };
    ___fatal_error (msgs);
  }
  return 0;
}


/* Frame roots, stack-to-heap construction and structural links share one
 * access domain. The queue gate is never held while entering this domain.
 * READY publishes raw payload, not permission to race a link constructor. */
___HIDDEN void acquire_frame_access
   ___P((___collector_worker *work), (work)
___collector_worker *work;)
{
#ifndef ___SINGLE_THREADED_VMS
  ___processor_state ___ps = work->carrier;
  ___virtual_machine_state vms = work->vm;
  while (___COMPARE_AND_SWAP_WORD(&___COLLECTION(vms).frame_gate,0,1) != 0)
    ___CPU_RELAX();
#endif
  work->frame_accesses_++;
}

___HIDDEN void release_frame_access
   ___P((___collector_worker *work), (work)
___collector_worker *work;)
{
#ifndef ___SINGLE_THREADED_VMS
  ___processor_state ___ps = work->carrier;
  ___virtual_machine_state vms = work->vm;
  ___FETCH_AND_CLEAR_WORD(&___COLLECTION(vms).frame_gate);
#endif
}

typedef struct ___copy_reservation_struct
  {
    ___WORD *begin;
    ___WORD *header;
    ___WORD *past;
    ___SIZE_TS words;
  } ___copy_reservation;

___HIDDEN void prepare_copy_request
  (___collector_worker *work, ___msection *section, ___WORD *source,
   ___SIZE_TS source_words, ___SIZE_TS body_words, int align8, int frame)
{
  ___gc_copy_request *r = &work->copy_request;
  ___UWORD first = ___CAST(___UWORD,source);
  ___UWORD base = ___CAST(___UWORD,section->base) +
    ((___MSECTION_SIZE>>1)-___COLLECTION(work->vm).destination_offset)*___WS;
  ___SIZE_TS half = ___MSECTION_SIZE>>1;
  ___SIZE_TS destination;
  if (body_words < 0 || body_words > half-4)
    {
      static char *msgs[] = { "GC copy body exceeds physical section", NULL };
      ___fatal_error(msgs);
    }
  destination = body_words+1;
#if ___WS == 4
  if (align8) destination++;
#else
  (void)align8;
#endif
  if (___WORD_LOAD_ACQUIRE(&r->state) != 0 || source_words <= 0 ||
      body_words < 0 || source_words > half || first < base ||
      first-base > (half-source_words)*___WS ||
      (first-base)%___WS != 0 || destination > source_words+(frame ? 0 : 1))
    {
      static char *msgs[] = { "GC copy request lacks bounded source interval", NULL };
      ___fatal_error(msgs);
    }
  r->source_section = section;
  r->source_begin = source;
  r->source_words = source_words;
  r->destination_words = destination;
  r->epoch = ___COLLECTION(work->vm).epoch;
  r->frame = frame;
  ___COMPARE_AND_SWAP_WORD(&r->state,0,1);
}

#ifndef ___GC_COPY_CONTROL
#define ___GC_COPY_CONTROL(work,body,head) ((void)0)
#endif
#ifndef ___GC_ROOT_CONTROL
#define ___GC_ROOT_CONTROL(work) ((void)0)
#endif

___HIDDEN ___WORD load_copy_source_header
   (___collector_worker *work, ___WORD *body)
{
#ifdef ___ORDERED_WORD_NATIVE
  return ___WORD_LOAD_ACQUIRE(&body[-1]);
#else
  /* Legacy load may be an RMW. Moving headers use their physical section's
   * gate; PERM/STILL headers outside the pool are immutable during admitted
   * tracing and may be read-only. Never issue an RMW on those headers. */
  ___processor_state ___ps = work->carrier;
  ___WORD *header = body-1;
  int i = find_msection(the_msections,header);
  if (i >= 0 && i < the_msections->nb_sections)
    {
      ___msection *section = the_msections->sections[i];
      ___UWORD address = ___CAST(___UWORD,header);
      ___UWORD base = ___CAST(___UWORD,section->base);
      if (address >= base && address-base < ___MSECTION_SIZE*___WS)
        {
          ___WORD head;
          ___gc_copy_acquire (&section->copy_gate);
          head = body[-1];
          ___gc_copy_release (&section->copy_gate);
          return head;
        }
    }
  return body[-1];
#endif
}

/* Obtain an actual contiguous destination interval before writing a header
 * or attempting forwarding. The interval is private until commit. A known
 * forwarding contender exits before reservation. A changed header while
 * holding source authority is unknown and retains the grant. */
___HIDDEN ___copy_reservation reserve_copy
   ___P((___collector_worker *work, ___WORD *alloc, ___SIZE_TS words, int align8),
        (work, alloc, words, align8)
___collector_worker *work;
___WORD *alloc;
___SIZE_TS words;
int align8;)
{
  ___processor_state ___ps = work->carrier;
  ___copy_reservation grant;
  ___SIZE_TS required;
  if (work->copy_begin_ != 0 || words > (___MSECTION_SIZE>>1)-4)
    {
      static char *msgs[] = { "GC invalid contiguous copy reservation", NULL };
      ___fatal_error(msgs);
    }
  required = words+1;
#if ___WS == 4
  if (align8) required++;
#else
  (void)align8;
#endif
  if (___WORD_LOAD_ACQUIRE(&work->copy_request.state) != 1 ||
      work->copy_request.epoch != ___COLLECTION(work->vm).epoch ||
      work->copy_request.destination_words != required)
    {
      static char *msgs[] = { "GC arena request lacks current source custody", NULL };
      ___fatal_error(msgs);
    }
  if (required > (___MSECTION_SIZE>>1)-3)
    fatal_heap_overflow(); /* no section can satisfy this request */
  while ((required>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3 && !work->arena.large) ||
         alloc > work->arena.limit || work->arena.limit-alloc < required)
    {
      work->arena.cursor = alloc;
      end_heap_chunk(work);
      refill_worker_arena(work);
      alloc = work->arena.cursor;
    }
  grant.begin = alloc;
  grant.header = alloc;
  grant.past = alloc+required;
  grant.words = words;
  if (work->arena.cursor != grant.begin ||
      !___gc_arena_reserve(&work->arena,required))
    {
      static char *msgs[] = { "GC arena lost private copy interval", NULL };
      ___fatal_error(msgs);
    }
#if ___WS == 4
  if (align8 && (___CAST(___WORD,alloc) & 7) == 0)
    grant.header++;
#endif
  work->copy_begin_ = grant.begin;
  work->copy_past_ = grant.past;
  work->copy_reserved_words_ += required;
  ___COMPARE_AND_SWAP_WORD(&work->copy_request.state,1,2);
  return grant;
}

___HIDDEN void commit_copy
   ___P((___collector_worker *work, const ___copy_reservation *grant),
        (work, grant)
___collector_worker *work;
const ___copy_reservation *grant;)
{
  if (work->copy_begin_ != grant->begin || work->copy_past_ != grant->past)
    {
      static char *msgs[] = { "GC commit lost private reservation", NULL };
      ___fatal_error(msgs);
    }
  /* Alignment objects become visible only after forwarding succeeds. */
  if (grant->header != grant->begin)
    {
      *grant->begin = ___MAKE_HD_WORDS(0,___sVECTOR);
      publish_object_scan(work,grant->begin);
    }
  work->copy_padding_words_ += (grant->past-grant->begin)-(grant->words+1);
  if (!___gc_arena_commit(&work->arena,grant->begin,grant->past))
    {
      static char *msgs[] = { "GC commit does not own arena interval", NULL };
      ___fatal_error(msgs);
    }
  work->copy_begin_ = 0;
  work->copy_past_ = 0;
  work->copied_source_words += work->copy_request.source_words;
  if(work->copy_reserved_words_ >
     ___COLLECTION(work->vm).census.destination_words)
    rc_contract_error("Unique copy charge exceeds the frozen census");
  ___FETCH_AND_CLEAR_WORD(&work->copy_request.state);
}

___HIDDEN void finish_tail
   ___P((___collector_worker *work), (work)
___collector_worker *work;)
{
  if (work->tail_cell_ != 0)
    {
      work->tail_completed_++;
      work->tail_cell_ = 0;
    }
}

#ifdef ENABLE_CONSISTENCY_CHECKS

#define mark_array(work,start,n) mark_array_debug (work,start,n,__LINE__)

___HIDDEN void mark_array_debug
   ___P((___collector_worker *work,
         ___WORD *start,
         ___WORD n,
         int line),
        (work,
         start,
         n,
         line)
___collector_worker *work;
___WORD *start;
___WORD n;
int line;)

#else

___HIDDEN void mark_array
   ___P((___collector_worker *work,
         ___WORD *start,
         ___WORD n),
        (work,
         start,
         n)
___collector_worker *work;
___WORD *start;
___WORD n;)

#endif
{
  if(work!=0 && work->census!=0) { census_array(work,start,n);return; }
  if(work==0) {
    ___WORD i;
    for(i=0;i<n;i++) if(___MEM_ALLOCATED(start[i])) {
      ___WORD head=___HEADER(start[i]);
      if(___HD_TYP(head)!=___PERM) {
        char *messages[]={"Moving root scan requires an active collector worker",0};
        ___fatal_error(messages);
      }
    }
    return; /* no relocation or source-retirement receipt is manufactured */
  }
  ___processor_state ___ps = work->carrier;
  ___WORD *alloc = work->arena.cursor;

#ifdef ENABLE_CONSISTENCY_CHECKS
  mark_array_call_line = line;
#endif

  while (n-- > 0)
    {
      ___WORD *cell = start++;

    again: /* looping back here is possible when tail marking */
      {
        ___WORD obj = *cell;

        if (___MEM_ALLOCATED(obj))
          {
            ___WORD *body;
            ___WORD head;
            int head_typ;
            int subtype;

#ifdef ENABLE_CONSISTENCY_CHECKS
            if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1)
              validate_old_obj (___PSP obj);
#endif

            body = ___BODY0(obj);
            /* Permanent headers may live in read-only module storage. Use a
             * load, never an RMW pretending to be one. The selected modern-C
             * backend supplies the existing acquire-load word service. */
            head = load_copy_source_header(work,body);
            /* A canonical root may already contain a destination reference
             * repaired by another source. Revisit supplies no initialization,
             * Tail or scan completion; those debts stay with the copy owner.
             * Valid managed values are assumed; arbitrary forged native words
             * are not admitted by the root union. */
            if (___HD_TYP(head)==___MOVABLE0) {
              int section_index=find_msection(the_msections,body-1);
              if(section_index>=0 && section_index<the_msections->nb_sections) {
                ___UWORD address=___CAST(___UWORD,body-1);
                ___UWORD first=___CAST(___UWORD,the_msections->sections[section_index]->base)+
                  ___COLLECTION(work->vm).destination_offset*___WS;
                if(address>=first && address-first<(___MSECTION_SIZE>>1)*___WS) {
                  work->destination_revisits++;
                  continue;
                }
              }
            }
            subtype = ___HD_SUBTYPE(head);
            head_typ = ___HD_TYP(head);

            if (head_typ == ___MOVABLE0)
              {
                ___SIZE_TS words = ___HD_WORDS(head);
                ___WORD *copy_header;
                ___copy_reservation grant;
                ___msection *source_section =
                  require_fromspace_copy_source (work, cell, body);
                ___VOLATILE ___WORD *copy_gate =
                  &source_section->copy_gate;

                /* The old path reserved/refilled before discovering another
                 * copier's forwarding. Refunding that private grant did not
                 * recover a section already closed by refill. Serialize only
                 * the claim/reservation/header publication, not payload copy.
                 * Re-read under authority: the earlier header is a hint. */
                ___gc_copy_acquire (copy_gate);
                if (___WORD_LOAD_ACQUIRE(&body[-1]) != head)
                  {
                    ___gc_copy_release (copy_gate);
                    goto again;
                  }
                prepare_copy_request(work,source_section,body-1,words+1,
                                     words,subtype >= ___sS64VECTOR,0);
                grant = reserve_copy
                  (work,alloc,words,subtype >= ___sS64VECTOR);
                alloc = grant.header;

                ___GC_COPY_CONTROL(work,body,head); /* test-only scheduling, no result injection */
                copy_header = alloc;
                *alloc++ = head;

#ifdef ___SINGLE_THREADED_VMS

                body[-1] = ___TAG(alloc - ___REFERENCE_TO_BODY, ___FORW);

#else

                {
                  ___WORD head_now =
                    ___COMPARE_AND_SWAP_WORD(&body[-1],
                                             head,
                                             ___TAG(alloc - ___REFERENCE_TO_BODY, ___FORW));

                  if (head_now != head)
                    {
                      /* Every admitted forwarding writer owns this gate.
                       * A changed header here is an unknown foreign write,
                       * never a known losing reservation eligible for refund. */
                      static char *msgs[] = { "GC unknown forwarding result retains reservation", NULL };
                      ___fatal_error (msgs);
                    }
                }

#endif

                ___gc_copy_release (copy_gate);
                work->copied_words += words+1;
                *cell = ___TAG(alloc - ___REFERENCE_TO_BODY, ___TYP(obj));
                finish_tail(work);

                if (words > 0 && subtype <= ___sBOXVALUES)
                  {
                    cell = alloc;
                    work->tail_cell_ = cell;
                    work->tail_started_++;
                  }
                else
                  cell = 0;

                while (words > 0)
                  {
                    *alloc++ = *body++;
                    words--;
                  }
                publish_object_scan (work, copy_header);
                if (alloc != grant.past)
                  {
                    *alloc = ___MAKE_HD_WORDS(0,___sVECTOR);
                    publish_object_scan(work,alloc++);
                  }
                commit_copy(work,&grant);
                if (alloc >= alloc_heap_chunk_limit)
                  {
                    work->arena.cursor = alloc;
                    end_heap_chunk (work);
                    start_heap_chunk (work);
                    alloc = work->arena.cursor;
                  }

                if (cell != 0) goto again;
              }
            else if (head_typ == ___STILL)
              {
#ifdef ___SINGLE_THREADED_VMS

                if (body[___STILL_MARK - ___STILL_BODY] == -1)
                  {
                    body[___STILL_MARK - ___STILL_BODY]
                      = ___CAST(___WORD,still_objs_to_scan);
                    still_objs_to_scan
                      = ___CAST(___WORD,body - ___STILL_BODY);
                  }

#else

                if (___COMPARE_AND_SWAP_WORD(&body[___STILL_MARK - ___STILL_BODY],
                                             -1,
                                             ___CAST(___WORD,still_objs_to_scan))
                    == -1)
                  {
                    still_objs_to_scan
                      = ___CAST(___WORD,body - ___STILL_BODY);
                  }
#endif
              }
            else if (___TESTTYPE(head_typ, ___FORW))
              {
                *cell = ___TAG(___UNTAG_AS(head, ___FORW), ___TYP(obj));
              }
#ifdef ENABLE_CONSISTENCY_CHECKS
            else if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1 &&
                     head_typ != ___PERM)
              bug (___PSP obj, 0, "was not ___PERM, ___STILL, ___MOVABLE0 or ___FORW");
#endif
          }
      }
      finish_tail(work);
    }

  work->arena.cursor = alloc;
}


/* End internal memory fragment. */
