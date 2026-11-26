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

static inline int change_object_scan_state_at
   (___collector_worker *work, ___WORD *cell, int shift, ___WORD mask,
    int from, int to)
{
  ___WORD old, updated;
  int state;
  if (___COLLECTION(work->vm).worker_count<=1)
    {
      old=*cell;
      state=(___CAST(___UWORD,old) >> shift) & 3;
      if (state!=from) return state;
      *cell=(old & ~mask) |
        ___CAST(___WORD,___CAST(___UWORD,to) << shift);
      return from;
    }
  old = ___WORD_LOAD_ACQUIRE(cell);
  for (;;)
    {
      ___WORD found;
      state = (___CAST(___UWORD,old) >> shift) & 3;
      if (state != from)
        return state;
      updated=(old & ~mask) |
        ___CAST(___WORD,___CAST(___UWORD,to) << shift);
      found = ___COMPARE_AND_SWAP_WORD(cell,old,updated);
      if (found == old)
        return from;
      old = found;
    }
}

static inline ___WORD *locate_object_scan_cell
   (___collector_worker *work, ___WORD *header, int *shift_out, ___WORD *mask_out)
{
  ___processor_state ___ps = work->carrier;
  ___msection *section;
  ___PTRDIFF_T pos;
  ___SIZE_TS epoch = ___COLLECTION(work->vm).epoch;
  if (__builtin_expect(
        work->scan_state_section_ && work->scan_state_epoch_==epoch &&
        header>=work->scan_state_base_+work->scan_state_offset_ &&
        header<work->scan_state_base_+work->scan_state_offset_+(___MSECTION_SIZE>>1), 1))
    {
      section=work->scan_state_section_;
      pos=header-(work->scan_state_base_+work->scan_state_offset_);
    }
  else
    {
      ___SIZE_TS sdest;
      section = ___gc_find_msection_cached(work, the_msections, header);
      if (!section || !section->gc_is_dest) goto outside;
      sdest = section->gc_dest_offset;
      pos=header-section->base-sdest;
      if (pos < 0 || pos >= (___MSECTION_SIZE>>1)) goto outside;
      work->scan_state_section_=section;
      work->scan_state_base_=section->base;
      work->scan_state_offset_=sdest;
      work->scan_state_epoch_=epoch;
    }
  {
    int shift = 2*(int)(pos & ((___WORD_WIDTH/2)-1));
    *shift_out = shift;
    *mask_out = ___CAST(___WORD,___CAST(___UWORD,3) << shift);
    return section->base + ___MSECTION_SIZE + (pos / (___WORD_WIDTH/2));
  }
 outside:
  {
    static char *msgs[] = { "GC scan identity outside destination", NULL };
    ___fatal_error (msgs);
  }
  return 0;
}

static inline int change_object_scan_state
   (___collector_worker *work, ___WORD *header, int from, int to)
{
  int shift;
  ___WORD mask;
  ___WORD *cell = locate_object_scan_cell(work, header, &shift, &mask);
  return change_object_scan_state_at(work, cell, shift, mask, from, to);
}


static inline void publish_object_scan
   (___collector_worker *work, ___WORD *header)
{
  if (__builtin_expect(
        change_object_scan_state(work,header,GC_SCAN_UNPUBLISHED,GC_SCAN_READY)
        != GC_SCAN_UNPUBLISHED, 0))
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
  ___SIZE_TS epoch = ___COLLECTION(vms).epoch;
  if (__builtin_expect(
        work->census_section_ && work->census_epoch_ == epoch, 1))
    {
      ___UWORD address = ___CAST(___UWORD, header);
      ___UWORD sbase = ___CAST(___UWORD, work->census_base_ + work->census_offset_);
      if (__builtin_expect(address >= sbase && address - sbase < (___MSECTION_SIZE>>1) * ___WS, 1))
        return work->census_section_;
    }
  {
    ___msection *section = ___gc_find_msection_cached(work, the_msections, header);
    if (section != 0 &&
        (!___COLLECTION(vms).is_minor || section->region_age != ___GC_REGION_MATURE))
      {
        ___SIZE_TS source_off = section->gc_src_offset;
        ___UWORD address = ___CAST(___UWORD,header);
        ___UWORD base = ___CAST(___UWORD,section->base);
        ___SIZE_TS pos = (address-base)/___WS;
        if (pos >= source_off && pos < source_off + (___MSECTION_SIZE>>1))
          {
            work->census_section_ = section;
            work->census_base_ = section->base;
            work->census_offset_ = source_off;
            work->census_epoch_ = epoch;
            return section;
          }
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
static inline void acquire_frame_access
   (___collector_worker *work)
{
#ifndef ___SINGLE_THREADED_VMS
  ___virtual_machine_state vms = work->vm;
  if (___COLLECTION(vms).worker_count > 1)
    while (___COMPARE_AND_SWAP_WORD(&___COLLECTION(vms).frame_gate,0,1) != 0)
      ___CPU_RELAX();
#endif
  work->frame_accesses_++;
}

static inline void release_frame_access
   (___collector_worker *work)
{
#ifndef ___SINGLE_THREADED_VMS
  ___virtual_machine_state vms = work->vm;
  if (___COLLECTION(vms).worker_count > 1)
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

static inline void prepare_copy_request
  (___collector_worker *work, ___msection *section, ___WORD *source,
   ___SIZE_TS source_words, ___SIZE_TS body_words, int align8, int frame)
{
  ___gc_copy_request *r = &work->copy_request;
  ___UWORD first = ___CAST(___UWORD,source);
  ___UWORD base = ___CAST(___UWORD,section->base + section->gc_src_offset);
  ___SIZE_TS half = ___MSECTION_SIZE>>1;
  ___SIZE_TS destination;
  if (__builtin_expect(body_words < 0 || body_words > half-4, 0))
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
  /* copy_request belongs exclusively to this worker during collection. */
  if (__builtin_expect(r->state != 0 || source_words <= 0 ||
      body_words < 0 || source_words > half || first < base ||
      first-base > (half-source_words)*___WS ||
      (first-base)%___WS != 0 || destination > source_words+(frame ? 0 : 1), 0))
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
  r->state = 1;
}

#ifdef ___GC_COPY_CONTROL
#define ___GC_COPY_CONTROL_ACTIVE 1
#else
#define ___GC_COPY_CONTROL(work,body,head) ((void)0)
#endif
#ifndef ___GC_ROOT_CONTROL
#define ___GC_ROOT_CONTROL(work) ((void)0)
#endif

static inline ___WORD load_copy_source_header
   (___collector_worker *work, ___WORD *body)
{
  if (___COLLECTION(work->vm).worker_count <= 1)
    return body[-1];
  return ___WORD_LOAD_ACQUIRE(&body[-1]);
}

/* Obtain an actual contiguous destination interval before writing a header
 * or attempting forwarding. The interval is private until commit. A known
 * forwarding contender exits before reservation. A changed header while
 * holding source authority is unknown and retains the grant. */
static inline ___copy_reservation reserve_copy
   (___collector_worker *work, ___WORD *alloc, ___SIZE_TS words, int align8)
{
  ___copy_reservation grant;
  ___SIZE_TS required;
  if (__builtin_expect(work->copy_begin_ != 0 || words > (___MSECTION_SIZE>>1)-4, 0))
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
  if (__builtin_expect(work->copy_request.state != 1 ||
      work->copy_request.epoch != ___COLLECTION(work->vm).epoch ||
      work->copy_request.destination_words != required, 0))
    {
      static char *msgs[] = { "GC arena request lacks current source custody", NULL };
      ___fatal_error(msgs);
    }
  if (__builtin_expect(required > (___MSECTION_SIZE>>1)-3, 0))
    fatal_heap_overflow(); /* no section can satisfy this request */
  while (__builtin_expect(
         (required>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3 && !work->arena.large) ||
         alloc > work->arena.limit || work->arena.limit-alloc < required, 0))
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
  if (__builtin_expect(work->arena.cursor != grant.begin ||
      !___gc_arena_reserve(&work->arena,required), 0))
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
  work->copy_request.state = 2;
  return grant;
}

static inline void commit_copy
   (___collector_worker *work, const ___copy_reservation *grant)
{
  if (__builtin_expect(work->copy_begin_ != grant->begin || work->copy_past_ != grant->past, 0))
    {
      static char *msgs[] = { "GC commit lost private reservation", NULL };
      ___fatal_error(msgs);
    }
  /* Alignment objects become visible only after forwarding succeeds. */
  if (__builtin_expect(grant->header != grant->begin, 0))
    {
      *grant->begin = ___MAKE_HD_WORDS(0,___sVECTOR);
      record_mature_obj_start(work->arena.section, grant->begin);
      publish_object_scan(work,grant->begin);
    }
  work->copy_padding_words_ += (grant->past-grant->begin)-(grant->words+1);
  if (__builtin_expect(!___gc_arena_commit(&work->arena,grant->begin,grant->past), 0))
    {
      static char *msgs[] = { "GC commit does not own arena interval", NULL };
      ___fatal_error(msgs);
    }
  work->copy_begin_ = 0;
  work->copy_past_ = 0;
  work->copied_source_words += work->copy_request.source_words;
  if (__builtin_expect(work->copy_reserved_words_ >
      ___COLLECTION(work->vm).census.destination_words, 0))
    rc_contract_error("Unique copy charge exceeds the frozen census");
  work->copy_request.state = 0;
}

static inline void finish_tail
   (___collector_worker *work)
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
  const int single_worker = (___COLLECTION(work->vm).worker_count <= 1);
  const int is_minor = ___COLLECTION(work->vm).is_minor;
  const ___SIZE_TS half_bytes = (___MSECTION_SIZE>>1) * ___WS;
  const ___SIZE_TS epoch = ___COLLECTION(work->vm).epoch;

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
              validate_old_obj (work, obj);
#endif

            body = ___BODY0(obj);
            /* Permanent headers may live in read-only module storage. Use a
             * load, never an RMW pretending to be one. The selected modern-C
             * backend supplies the existing acquire-load word service. */
            head = load_copy_source_header(work,body);
            head_typ = ___HD_TYP(head);

            if (head_typ == ___MOVABLE0)
              {
                ___WORD *header = body - 1;
                ___UWORD addr = ___CAST(___UWORD, header);
                ___msection *source_section = 0;

                /* Single cached lookup distinguishes frozen fromspace source
                 * from mature/destination revisit without two find_msection calls. */
                if (__builtin_expect(
                      work->census_section_ && work->census_epoch_ == epoch &&
                      addr - ___CAST(___UWORD, work->census_base_ + work->census_offset_) < half_bytes, 1))
                  {
                    source_section = work->census_section_;
                  }
                else
                  {
                    ___msection *sec = ___gc_find_msection_cached(work, the_msections, header);
                    if (__builtin_expect(sec != 0, 1))
                      {
                        if (is_minor && sec->region_age == ___GC_REGION_MATURE)
                          {
                            finish_tail(work);
                            continue;
                          }
                        {
                          ___SIZE_TS s_off = sec->gc_src_offset;
                          ___UWORD sbase = ___CAST(___UWORD, sec->base + s_off);
                          if (addr - sbase < half_bytes)
                            {
                              work->census_section_ = sec;
                              work->census_base_ = sec->base;
                              work->census_offset_ = s_off;
                              work->census_epoch_ = epoch;
                              source_section = sec;
                            }
                          else if (sec->gc_is_dest &&
                                   addr - ___CAST(___UWORD, sec->base + sec->gc_dest_offset) < half_bytes)
                            {
                              work->destination_revisits++;
                              finish_tail(work);
                              continue;
                            }
                        }
                      }
                    if (__builtin_expect(source_section == 0, 0))
                      source_section = require_fromspace_copy_source (work, cell, body);
                  }

                {
                  ___SIZE_TS words = ___HD_WORDS(head);
                  ___WORD *copy_header;
                  ___copy_reservation grant;

                  subtype = ___HD_SUBTYPE(head);
                  if (single_worker)
                    {
                      prepare_copy_request(work,source_section,header,words+1,
                                           words,subtype >= ___sS64VECTOR,0);
                      grant = reserve_copy
                        (work,alloc,words,subtype >= ___sS64VECTOR);
                      alloc = grant.header;

                      ___GC_COPY_CONTROL(work,body,head);
                      copy_header = alloc;
                      *alloc++ = head;
                      body[-1] = ___TAG(alloc - ___REFERENCE_TO_BODY, ___FORW);
                    }
                  else
                    {
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
                      prepare_copy_request(work,source_section,header,words+1,
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

                        if (__builtin_expect(head_now != head, 0))
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
                    }

                  work->copied_words += words+1;
                  *cell = ___TAG(alloc - ___REFERENCE_TO_BODY, ___TYP(obj));
                  REST_OBS_REPAIR(___ps,cell,obj,*cell,work->arena.epoch);
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
                  record_mature_obj_start(work->arena.section, copy_header);
                  publish_object_scan (work, copy_header);
                  if (__builtin_expect(alloc != grant.past, 0))
                    {
                      *alloc = ___MAKE_HD_WORDS(0,___sVECTOR);
                      record_mature_obj_start(work->arena.section, alloc);
                      publish_object_scan(work,alloc++);
                    }
                  commit_copy(work,&grant);
                  if (__builtin_expect(alloc >= alloc_heap_chunk_limit, 0))
                    {
                      work->arena.cursor = alloc;
                      end_heap_chunk (work);
                      start_heap_chunk (work);
                      alloc = work->arena.cursor;
                    }

                  if (cell != 0) goto again;
                }
              }
            else if (head_typ == ___STILL)
              {
#ifndef ___USE_HANDLES
                if (is_minor &&
                    (body[___STILL_DIRTY - ___STILL_BODY] & ___STILL_FLAG_YOUNG) == 0)
                  {
                    finish_tail(work);
                    continue;
                  }
#else
                if (is_minor)
                  {
                    finish_tail(work);
                    continue;
                  }
#endif
                if (!still_subtype_has_pointers(___HD_SUBTYPE(head)))
                  {
                    if (single_worker)
                      {
                        if (body[___STILL_MARK - ___STILL_BODY] == -1)
                          body[___STILL_MARK - ___STILL_BODY] = 0;
                      }
                    else
                      {
#ifdef ___SINGLE_THREADED_VMS
                        if (body[___STILL_MARK - ___STILL_BODY] == -1)
                          body[___STILL_MARK - ___STILL_BODY] = 0;
#else
                        if (___WORD_LOAD_RELAXED(&body[___STILL_MARK - ___STILL_BODY]) == -1)
                          ___COMPARE_AND_SWAP_WORD(&body[___STILL_MARK - ___STILL_BODY], -1, 0);
#endif
                      }
                  }
                else if (single_worker)
                  {
                    if (body[___STILL_MARK - ___STILL_BODY] == -1)
                      {
                        body[___STILL_MARK - ___STILL_BODY]
                          = ___CAST(___WORD,still_objs_to_scan);
                        still_objs_to_scan
                          = ___CAST(___WORD,body - ___STILL_BODY);
                      }
                  }
                else
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
                    if (___WORD_LOAD_RELAXED(&body[___STILL_MARK - ___STILL_BODY]) == -1 &&
                        ___COMPARE_AND_SWAP_WORD(&body[___STILL_MARK - ___STILL_BODY],
                                                 -1,
                                                 ___CAST(___WORD,still_objs_to_scan))
                        == -1)
                      {
                        still_objs_to_scan
                          = ___CAST(___WORD,body - ___STILL_BODY);
                      }
#endif
                  }
              }
            else if (___TESTTYPE(head_typ, ___FORW))
              {
                *cell = ___TAG(___UNTAG_AS(head, ___FORW), ___TYP(obj));
                REST_OBS_REPAIR(___ps,cell,obj,*cell,work->arena.epoch);
              }
#ifdef ENABLE_CONSISTENCY_CHECKS
            else if (___DEBUG_SETTINGS_LEVEL(___GSTATE->setup_params.debug_settings) >= 1 &&
                     head_typ != ___PERM)
              bug (work, obj, 0, "was not ___PERM, ___STILL, ___MOVABLE0 or ___FORW");
#endif
          }
      }
      finish_tail(work);
    }

  work->arena.cursor = alloc;
}


/* End internal memory fragment. */
