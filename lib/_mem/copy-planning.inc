/* Closed-source, read-only preflight. This is not a second Scheme object
 * scanner: scan()/mark_frame() provide the same typed edge visitor used by
 * relocation. Only the sink (census_array) and structural frame walk differ.
 * Destination scan bits and STILL_MARK are collector-private scratch; no
 * root, forwarding header, payload, table layout or will flag is written. */

___HIDDEN int census_checked_add(___SIZE_TS *sum, ___SIZE_TS value)
{
  if(value<0 || *sum>___CAST(___SIZE_TS,___MAX_FIX)-value) return 0;
  *sum+=value;return 1;
}

static inline int census_claim(___collector_worker *work, ___WORD *source,
                          ___SIZE_TS span, ___SIZE_TS request, int frame)
{
  ___processor_state ___ps=work->carrier;
  ___gc_census *c=work->census;
  ___SIZE_TS at,j,half=___MSECTION_SIZE>>1;
  ___msection *section;
  ___WORD *bits;
  if(__builtin_expect(c->failed, 0)) return 0;
  if(__builtin_expect(span<1 || request<1, 0)) goto invalid;
  /* Consecutive objects in one half share the section found last time;
   * cross-section pointers hit the worker-private 64-entry direct cache. */
  if(__builtin_expect(
       work->census_section_ && work->census_epoch_==___COLLECTION(work->vm).epoch &&
       source>=work->census_base_+work->census_offset_ &&
       source<work->census_base_+work->census_offset_+half, 1)) {
    section=work->census_section_;
  } else {
    section=___gc_find_msection_cached(work, the_msections, source);
    if(__builtin_expect(!section, 0)) goto invalid;
    if(___COLLECTION(work->vm).is_minor &&
       section->region_age==___GC_REGION_MATURE && !section->gc_evacuating)
      return 0;
    work->census_section_=section;
    work->census_base_=section->base;
    work->census_offset_=section->gc_src_offset;
    work->census_epoch_=___COLLECTION(work->vm).epoch;
  }
  { ___UWORD address=___CAST(___UWORD,source);
    ___UWORD base=___CAST(___UWORD,section->base+section->gc_src_offset);
    if(__builtin_expect(address<base || address-base>=half*___WS || (address-base)%___WS, 0)) goto invalid;
    at=(address-base)/___WS;
  }
  if(__builtin_expect(span>half-at || request>half-3, 0)) goto invalid;
  bits=section->base+___MSECTION_SIZE;
  {
    const ___SIZE_TS spw=___WORD_WIDTH/2;
    const ___UWORD ones=(~___CAST(___UWORD,0))/3;
    const ___UWORD head_val=___CAST(___UWORD,frame?2:3);
    ___SIZE_TS w=at/spw;
    unsigned int off=(unsigned int)(at&(spw-1));
    unsigned int shift=2*off;
    ___UWORD cur=___CAST(___UWORD,bits[w]);
    int old=(int)((cur>>shift)&3);
    ___SIZE_TS first_take=spw-off;
    ___UWORD first_mask;
    ___UWORD first_pat;
    if(old==(int)head_val) return 0;
    if(__builtin_expect(old!=0, 0)) goto invalid;
    if(first_take>span) first_take=span;
    first_mask=(first_take==spw)
      ? ~___CAST(___UWORD,0)
      : (((___CAST(___UWORD,1)<<(2*first_take))-1)<<shift);
    first_pat=((ones&first_mask)&~(___CAST(___UWORD,3)<<shift))|(head_val<<shift);
    /* Full source intervals, not only pointer keys, must be disjoint. This
     * detects a frame/header inside another object's extent before copying. */
    if(__builtin_expect(first_take==span, 1)) {
      if(__builtin_expect((cur&first_mask)!=0, 0)) goto invalid;
      bits[w]=___CAST(___WORD,cur|first_pat);
    } else {
      ___SIZE_TS rem=span-first_take;
      ___SIZE_TS full_words=rem/spw;
      ___SIZE_TS tail_take=rem&(spw-1);
      ___UWORD tail_mask=tail_take
        ? ((___CAST(___UWORD,1)<<(2*tail_take))-1)
        : 0;
      if(__builtin_expect((cur&first_mask)!=0, 0)) goto invalid;
      for(j=0;j<full_words;j++)
        if(bits[w+1+j]!=0) goto invalid;
      if(tail_take && (___CAST(___UWORD,bits[w+1+full_words])&tail_mask))
        goto invalid;
      bits[w]=___CAST(___WORD,cur|first_pat);
      for(j=0;j<full_words;j++)
        bits[w+1+j]=___CAST(___WORD,ones);
      if(tail_take)
        bits[w+1+full_words]|=___CAST(___WORD,ones&tail_mask);
    }
  }
  if(__builtin_expect(!census_checked_add(&c->source_words,span) ||
     !census_checked_add(&c->destination_words,request), 0)) goto invalid;
  if(request>c->largest_request)c->largest_request=request;
  if(__builtin_expect(request>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3, 0)) ++c->large_count;
  else {
    if(__builtin_expect(!census_checked_add(&c->small_words,request), 0)) goto invalid;
    if(request>c->small_max)c->small_max=request;
  }
  if(frame)++c->frames;else ++c->objects;
  return 1;
invalid:
  c->failed=1;return 0;
}

#if defined(__GNUC__) && !defined(CBMC)
static __attribute__((noinline, cold)) void census_enqueue_grow(___collector_worker *work, ___SCMOBJ value)
#else
___HIDDEN void census_enqueue_grow(___collector_worker *work, ___SCMOBJ value)
#endif
{
  ___gc_census *c=work->census;
  ___SIZE_T capacity=c->capacity?2*c->capacity:___WORD_WIDTH;
  if(capacity<c->capacity || capacity>~___CAST(___SIZE_T,0)/sizeof(*c->queue)) {
    c->failed=1;return;
  }
  /* Both superseded and replacement buffers have a VM-owned publication
   * slot. Interruption of malloc/copy/free is never an idempotent retry. */
  {
    ___SIZE_T old_cap = c->capacity;
    c->state=___GC_PLAN_ALLOCATING;
    c->replacement=census_queue_alloc(capacity);
    if(c->replacement==0) {c->state=___GC_PLAN_READING;c->failed=1;return;}
    if(c->count)memcpy(c->replacement,c->queue,c->count*sizeof(*c->queue));
    c->retired=c->queue;c->queue=c->replacement;c->replacement=0;
    if(c->retired)census_queue_free(c->retired, old_cap);
    c->retired=0;c->capacity=capacity;c->state=___GC_PLAN_READING;
  }
  if(capacity*sizeof(*c->queue)>c->peak_bytes)c->peak_bytes=capacity*sizeof(*c->queue);
  c->queue[c->count++]=value;
}

static inline void census_enqueue(___collector_worker *work, ___SCMOBJ value)
{
  ___gc_census *c=work->census;
  if(__builtin_expect(c->failed, 0))return;
  if(__builtin_expect(c->count<c->capacity, 1)) {
    c->queue[c->count++]=value;
    return;
  }
  census_enqueue_grow(work, value);
}

___HIDDEN void census_array(___collector_worker *work, ___WORD *start, ___WORD n)
{
  ___gc_census *c=work->census;
  while(n-->0 && !c->failed) {
    ___SCMOBJ value=*start++;
    ___WORD *body,head;
    ___SIZE_TS request;
    int type;
    if(!___MEM_ALLOCATED(value))continue;
    body=___BODY0(value);head=body[-1];type=___HD_TYP(head);
    if(type==___PERM)continue;
    if(type==___STILL) {
#ifndef ___USE_HANDLES
      if(___COLLECTION(work->vm).is_minor &&
         (body[___STILL_DIRTY-___STILL_BODY] & ___STILL_FLAG_YOUNG)==0)
        continue;
#else
      if(___COLLECTION(work->vm).is_minor) continue;
#endif
      ___WORD *mark=body+___STILL_MARK-___STILL_BODY;
      if(*mark)continue;
      *mark=1;++c->still;
      if(still_subtype_has_pointers(___HD_SUBTYPE(head)))
        census_enqueue(work,value);
      continue;
    }
    if(type!=___MOVABLE0) {c->failed=1;break;}
    request=___HD_WORDS(head)+1;
#if ___WS==4
    if(___HD_SUBTYPE(head)>=___sS64VECTOR)request++;
#endif
    if(census_claim(work,body-1,___HD_WORDS(head)+1,request,0))
      census_enqueue(work,value);
  }
}

___HIDDEN int census_frame_descriptor(___collector_worker *work, ___WORD *top,
                                     ___WORD ra, int carry,
                                     ___WORD *logical_past,
                                     ___frame_descriptor *d,
                                     ___SIZE_TS *half_words_out)
{
  ___gc_census *c=work->census;
  if (read_source_stack_frame(work,top,c->source_offset,logical_past,
                              &ra,carry,d,half_words_out,0)) return 1;
  c->failed=1;
  return 0;
}

___HIDDEN void census_capture(___collector_worker *work, ___WORD *cell)
{
  ___gc_census *c=work->census;
  ___WORD cf=*cell,ra=0;
  ___WORD *logical_past=0;
  int carry=0;
  /* Each recorded segment supplies its own bound. Reuse it only while
   * traversing that segment, and independently admit a raw break target. */
  while(___FIXNUMP(cf) && cf!=___END_OF_CONT_MARKER && !c->failed) {
    ___WORD *top=___CAST(___WORD*,cf),*base,*known_break,next;
    ___frame_descriptor d;
    ___SIZE_TS half_words=0,words;
    int at_break;
    if(!read_source_stack_frame(work,top,c->source_offset,logical_past,&ra,carry,&d,
                                &half_words,&known_break)) {c->failed=1;return;}
    words=___FRAME_SPACE(d.fs);
    base=top+words;next=___FP_STK(base,d.link+1);
    if(!source_break_agrees(base,known_break,next)) {c->failed=1;return;}
    if(___FIXNUMP(next)) {
      cf=___TAG(___UNTAG_AS(next,___tFIXNUM),___tSUBTYPED);break;
    }
    at_break=next==___GSTATE->handler_break;
    if(at_break && half_words-words<=___BREAK_FRAME_NEXT) {
      c->failed=1;return;
    }
    if(!census_claim(work,top,words,d.fs+___FRAME_EXTRA_SLOTS+1,1))return;
    mark_frame(work,base,&d);
    if(at_break) {
      cf=___FP_STK(base,-___BREAK_FRAME_NEXT);carry=0;logical_past=0;
    } else {cf=___CAST(___WORD,base);ra=next;carry=1;logical_past=known_break;}
  }
  if(cf!=___END_OF_CONT_MARKER && !c->failed)census_array(work,&cf,1);
}

/* Admit the frozen owner's stack_msection_ and its source-parity claim.
 * find_msection plus numeric containment is not ownership: another carrier's
 * active stack can contain the same addresses. Returns 0 when the grant is
 * stored, 1 when a valid shape is owned by someone else, 2 when the source
 * is malformed. Frame words are not loaded. */
___HIDDEN int capture_continuation_source
 (___root_member *member, ___SIZE_TS source_offset, ___gc_resume_space *resume)
{
  ___processor_state owner;
  ___execution_context *context;
  ___msection *section;
  section_claim *claim;
  ___WORD *fp, *brk, *half_base, *half_past, *cell=0, *scan=0;
  ___SIZE_TS length=0;
  int shape=0;
  if(member==0 || resume==0) return 2;
  owner=member->owner;
  context=member->context;
  if(owner==0 || context==0 || owner->context!=context) return 2;
  section=owner->mem.stack_msection_;
  fp=context->fp;
  brk=context->stack_break;
  if(section==0 || section->base==0) return 2;
  half_base=section->base+source_offset;
  half_past=half_base+(___MSECTION_SIZE>>1);
  /* Geometry, the first frame load and later copy share fp. A cursor
   * below the half is not admitted by checking the half base while
   * storing the raw pointer. */
  scan=fp;
  if(fp && ___gc_stack_span_words(half_base,half_past,fp,brk,
       ___FIRST_BREAK_FRAME_SPACE,&length)) {
    cell=___gc_stack_first_read_cell(fp);
    shape=___gc_stack_cell_inside(fp,length,cell);
  }
  claim=section_claim_at(section,source_offset);
  if(shape && claim->stack_state==STACK_ACTIVE &&
     claim->stack_owner!=0 && claim->stack_owner!=owner) return 1;
  if(!shape || claim->stack_state!=STACK_ACTIVE || claim->stack_owner!=owner)
    return 2;
  resume->context=context;
  resume->owner=owner;
  resume->source_section=section;
  resume->source_fp=fp;
  resume->source_break=brk;
  resume->source_half=source_offset;
  resume->source_words=length;
  resume->copy_admitted=0;
  return 0;
}

___HIDDEN void census_continuation(___collector_worker *work, ___root_member *member,
                                   ___gc_resume_space *resume, ___SIZE_TS source_offset)
{
  ___WORD *top,*logical_past,ra=0;
  int carry=0,gate;
  if(work==0 || member==0 || member->owner==0 || resume==0) {
    rc_contract_error("Continuation source stack is malformed at census entry");
    return;
  }
  gate=capture_continuation_source(member,source_offset,resume);
  if(gate!=0) {
    if(work->census) work->census->failed=1;
    rc_contract_error(gate==1
      ? "Continuation source stack is owned by another carrier"
      : "Continuation source stack is malformed at census entry");
    return;
  }
  /* Same coordinate capture_continuation_source stored. Exact end stops
   * on it; a frame that would pass it fails in the descriptor first. */
  logical_past=resume->source_break;
  top=resume->source_fp;
  while(top!=logical_past && !work->census->failed) {
    ___frame_descriptor d;___WORD *base,next;
    if(!census_frame_descriptor(work,top,ra,carry,logical_past,&d,0))return;
    base=top+___FRAME_SPACE(d.fs);next=___FP_STK(base,d.link+1);
    mark_frame(work,base,&d);
    top=base;ra=next;carry=1;
  }
  if(!work->census->failed)census_capture(work,&___FP_STK(top,-___BREAK_FRAME_NEXT));
}

___HIDDEN void census_drain(___collector_worker *work)
{
  ___gc_census *c=work->census;
  while(c->next<c->count && !c->failed) {
    ___WORD *body=___BODY0(c->queue[c->next++]);
    scan(work,body,body[-1]);
  }
}

___HIDDEN int plan_copy_round(___processor_state ps, ___SIZE_TS requested_words_still)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___root_round *round=___ROOT_UNION(vm);
  ___gc_round *g=&round->collection;
  ___gc_census *c=&g->census;
  ___collector_worker *work=&round->workers[0];
  ___processor_state ___ps=ps;
  ___msection *section;
  ___SIZE_TS capacity=(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3;
  int k;
  int i,n=round->participants,w=g->worker_count;
  /* A prior unknown allocation/free result remains retained. No initialization
   * below can erase the queue or a superseded pointer with unsettled custody. */
  if(c->state==___GC_PLAN_ALLOCATING || c->state==___GC_PLAN_RETAINED ||
     c->replacement || c->retired) {c->state=___GC_PLAN_RETAINED;return 3;}
  for(i=0;i<___MAX_PROCESSORS;i++) {
    ___collector_worker *old=&round->workers[i];
    if(old->copy_request.state || old->arena.pending || old->copy_begin_ || old->tail_cell_) {
      c->state=___GC_PLAN_RETAINED;return 3;
    }
  }
  for(i=0;i<n;i++)g->observed[i]=0;
  if(custom_msection_alloc || w<1 || w>n ||
     ___WORD_LOAD_ACQUIRE(&g->requested_workers)<0 ||
     ___WORD_LOAD_ACQUIRE(&g->requested_workers)>n)goto refuse;

  prepare_generational_round(ps, requested_words_still);

 retry_major:
  c->count=c->next=0;c->source_words=c->destination_words=0;
  c->objects=c->frames=c->still=0;c->small_words=c->small_max=0;
  c->largest_request=c->large_count=0;c->failed=0;
  c->source_offset=ps->mem.tospace_offset_;c->state=___GC_PLAN_READING;

  if (g->is_minor) {
    if (g->evac_selective && vm->mem.mature_tail_ != 0) {
      for(section=the_msections->head;section;section=section->next) {
        if (section->gc_evacuating)
          memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
        if (section==g->old_mature_tail) break;
      }
    }
    for(section=g->young_head;section;section=section->next) {
      memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
      if(section==alloc_msection) break;
    }
    if (g->has_young_still) {
      for(i=0;i<n;i++) {
        ___WORD *base=___CAST(___WORD*,round->members[i].owner->mem.young_still_objs_);
        while(base) {base[___STILL_MARK]=0;base=___CAST(___WORD*,base[___STILL_LINK]);}
      }
    }
  } else {
    for(section=the_msections->head;section;section=section->next)
      memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
    for(i=0;i<n;i++) {
      ___WORD *base=___CAST(___WORD*,round->members[i].owner->mem.still_objs_);
      while(base) {base[___STILL_MARK]=0;base=___CAST(___WORD*,base[___STILL_LINK]);}
      base=___CAST(___WORD*,round->members[i].owner->mem.young_still_objs_);
      while(base) {base[___STILL_MARK]=0;base=___CAST(___WORD*,base[___STILL_LINK]);}
    }
  }

  work->sec_cache_epoch_=0;work->sec_cache_nb_sections_=-1;
  work->census_section_=0;work->census_epoch_=0;
  work->census=c;ps->collector=work;work->traverse_weak_refs_=1;
  mark_vm_scmobj(work, vm);mark_symkey_tables(___PSP ___GSTATE);
  for(i=0;i<n && !c->failed;i++) {
    ___root_member *m=&round->members[i];___rc_header *h;___WORD *base;
    ___RC_LOCK(m->rc);
    for(h=m->rc->head.next;h!=&m->rc->head;h=h->next) {
      census_array(work,&h->data,1);
      census_array(work,___CAST(___SCMOBJ*,h+1),h->root_count);
    }
    ___RC_UNLOCK(m->rc);
    mark_global_variables(___PSP &m->globals);
    mark_registers(work, m->context);mark_saved(work, m->context);
    mark_type_cache(work, m->context);mark_processor_scmobj(work, m->context);
    census_continuation(work,m,&round->resume[i],c->source_offset);
    if (!g->is_minor) {
      base=___CAST(___WORD*,m->owner->mem.still_objs_);
      while(base) {
        if(base[___STILL_REFCOUNT]!=0) {___WORD value=___SUBTYPED_FROM_BODY(base+___STILL_BODY);census_array(work,&value,1);}
        base=___CAST(___WORD*,base[___STILL_LINK]);
      }
    }
    if (!g->is_minor || g->has_young_still) {
      base=___CAST(___WORD*,m->owner->mem.young_still_objs_);
      while(base) {
        if(base[___STILL_REFCOUNT]!=0) {___WORD value=___SUBTYPED_FROM_BODY(base+___STILL_BODY);census_array(work,&value,1);}
        base=___CAST(___WORD*,base[___STILL_LINK]);
      }
    }
    { ___WORD lists[2]={m->owner->mem.executable_wills_,m->owner->mem.nonexecutable_wills_};int j;
      for(j=0;j<2;j++) {___WORD list=lists[j];while(___UNTAG(list)!=0 && !c->failed) {
        ___WORD value=___SUBTYPED_FROM_START(___UNTAG(list));
        list=___BODY0(value)[___WILL_NEXT];census_array(work,&value,1);
      }}
    }
  }
  if (g->is_minor && !c->failed)
    scan_remembered_set(work);
  census_drain(work);work->census=0;ps->collector=0;
  if(c->failed)goto refuse;
  /* Threshold markers each charge at least MSECTION_CHUNK successful words.
   * Large requests are isolated events, not part of the small no-fit bound. */
  if(!___gc_copy_section_bound(w,c->small_words,c->small_max,c->large_count,
       capacity,___MSECTION_CHUNK,&k))goto refuse;

  /* Verify resume grants and stack extents before assigning destination roles. */
  for(i=0;i<n;i++) {
    ___gc_resume_space *r=&round->resume[i];
    ___root_member *m=&round->members[i];
    ___execution_context *context=m->context;
    ___WORD *fp, *brk, *half_base, *half_past, *cell;
    ___SIZE_TS length=0;
    section_claim *claim;
    if(m->owner==0 || !context || r->source_section==0 ||
       r->source_section!=m->owner->mem.stack_msection_ ||
       r->owner!=m->owner || r->context!=context ||
       r->source_half!=c->source_offset)goto refuse;
    fp=context->fp;brk=context->stack_break;
    if(r->source_fp!=fp || r->source_break!=brk)goto refuse;
    half_base=r->source_section->base+r->source_half;
    half_past=half_base+(___MSECTION_SIZE>>1);
    cell=___gc_stack_first_read_cell(fp);
    claim=section_claim_at(r->source_section,r->source_half);
    if(claim->stack_state!=STACK_ACTIVE || claim->stack_owner!=m->owner ||
       !___gc_stack_span_words(half_base,half_past,fp,brk,
          ___FIRST_BREAK_FRAME_SPACE,&length) ||
       length!=r->source_words ||
       !___gc_stack_cell_inside(fp,length,cell) ||
       length>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE ||
       (g->proc_worker[i]<0 && restore_loan_words(length)<___MSECTION_FUDGE+2))goto refuse;
  }

  /* Reserve sections according to round mode: Minor GC, segregated Major GC,
   * or classic non-segregated Major GC. */
  {
    int nm = g->is_minor ? vm->mem.nb_msections_mature_ : 0;
    int want_young_heaps = (g->is_minor || g->segregate_mature) ? n : 0;
    int compat = 0;
    int need_compat;
    int need;
    ___msection *old_tail;

    for (section = g->is_minor ? g->young_head : the_msections->head;
         section != 0;
         section = section->next)
      if (section->gc_src_offset == c->source_offset)
        compat++;

    if (n < 0 || k < 0 || nm < 0 || k > INT_MAX - nm - n - want_young_heaps)
      goto refuse;

    if (!g->is_minor && want_young_heaps > 0 && ___GSTATE->setup_params.max_heap > 0)
      {
        ___SIZE_TS cap_secs =
          (___GSTATE->setup_params.max_heap >> ___LWS) / ___MSECTION_SIZE;
        if (___CAST(___SIZE_TS, k + 2 * n + 2) > cap_secs)
          {
            if (the_msections != 0 && compat == the_msections->nb_sections)
              {
                g->segregate_mature = 0;
                want_young_heaps = 0;
              }
            else
              {
                int loans_ok = 1;
                for (i = 0; i < n; i++)
                  if (restore_loan_words(round->resume[i].source_words) < ___MSECTION_FUDGE + 2)
                    loans_ok = 0;
                if (loans_ok)
                  want_young_heaps = 0;
              }
          }
      }

    need_compat = n + want_young_heaps;
    need = nm + need_compat + k;
    if (compat < need_compat && the_msections != 0)
      {
        int extra = need_compat - compat;
        if (extra <= INT_MAX - the_msections->nb_sections &&
            the_msections->nb_sections + extra > need)
          need = the_msections->nb_sections + extra;
      }

    if (the_msections == 0 || the_msections->nb_sections < need || compat < need_compat)
      {
        ___SIZE_TS max_heap = ___GSTATE->setup_params.max_heap;
        old_tail = the_msections ? the_msections->tail : 0;
        if (need > 0 && max_heap == 0)
          adjust_msections(&the_msections, need);
        else if (need > 0)
          {
            ___SIZE_TS cap = max_heap >> ___LWS;
            ___SIZE_TS still = occupied_words_still;
            if (still >= 0 && still <= cap &&
                (___SIZE_TS)need <= (cap - still) / ___MSECTION_SIZE)
              adjust_msections(&the_msections, need);
          }
        if (the_msections != 0)
          {
            ___msection *s = old_tail ? old_tail->next : the_msections->head;
            while (s != 0)
              {
                s->gc_src_offset = c->source_offset;
                s->gc_dest_offset = 0;
                s->gc_dest_words = 0;
                s->gc_is_dest = 0;
                s->gc_role = 0;
                compat++;
                s = s->next;
              }
            if (g->young_head == 0)
              g->young_head = g->old_mature_tail ? g->old_mature_tail->next : the_msections->head;
          }
      }

    if (g->is_minor &&
        (the_msections == 0 || the_msections->nb_sections < need || compat < need_compat))
      {
        /* Tight max_heap prevented Minor GC; transparently retry as Major GC. */
        downgrade_minor_to_major(ps);
        goto retry_major;
      }

    if (!g->is_minor && want_young_heaps > 0 &&
        (the_msections == 0 || the_msections->nb_sections < need || compat < need_compat))
      {
        /* Tight max_heap in Major GC: drop dedicated young heap sections and
         * use stack-section loan fallback (or classic mode if no mature exists). */
        int loans_ok = 1;
        for (i = 0; i < n; i++)
          if (restore_loan_words(round->resume[i].source_words) < ___MSECTION_FUDGE + 2)
            loans_ok = 0;
        if (loans_ok)
          {
            want_young_heaps = 0;
            need_compat = n;
            need = n + k;
          }
        else if (vm->mem.nb_msections_mature_ == 0)
          {
            g->segregate_mature = 0;
            want_young_heaps = 0;
            need_compat = n;
            need = n + k;
          }
        if (the_msections == 0 || the_msections->nb_sections < need || compat < need_compat)
          {
            ___SIZE_TS max_heap = ___GSTATE->setup_params.max_heap;
            old_tail = the_msections ? the_msections->tail : 0;
            if (need > 0 && max_heap > 0)
              {
                ___SIZE_TS cap = max_heap >> ___LWS;
                ___SIZE_TS still = occupied_words_still;
                if (still >= 0 && still <= cap &&
                    (___SIZE_TS)need <= (cap - still) / ___MSECTION_SIZE)
                  adjust_msections(&the_msections, need);
              }
            if (the_msections != 0)
              {
                ___msection *s = old_tail ? old_tail->next : the_msections->head;
                while (s != 0)
                  {
                    s->gc_src_offset = c->source_offset;
                    s->gc_dest_offset = 0;
                    s->gc_dest_words = 0;
                    s->gc_is_dest = 0;
                    s->gc_role = 0;
                    compat++;
                    s = s->next;
                  }
              }
          }
        if (the_msections == 0 || the_msections->nb_sections < need || compat < need_compat)
          goto refuse;
      }
    else if (the_msections == 0 || !___gc_copy_plan_fits(n, k, the_msections->nb_sections))
      goto refuse;

    /* Assign stack sections (gc_role = 1) from compatible sections. */
    section = g->is_minor ? g->young_head : the_msections->head;
    for (i = 0; i < n; i++)
      {
        ___gc_resume_space *r = &round->resume[i];
        ___root_member *m = &round->members[i];
        while (section != 0 && (section->gc_role != 0 || section->gc_src_offset != c->source_offset))
          section = section->next;
        if (!section) goto refuse;
        section->gc_role = 1;
        r->stack_section = section;
        r->context = m->context;
        r->owner = m->owner;
        r->epoch = round->epoch;
        r->accepted = r->restored = r->loan_used = r->copy_admitted = 0;
        section = section->next;
      }

    /* Assign dedicated fresh young heap sections (gc_role = 2) when segregated. */
    for (i = 0; i < n; i++)
      g->young_heap_secs[i] = 0;
    if (want_young_heaps > 0)
      {
        for (i = 0; i < n; i++)
          {
            while (section != 0 && (section->gc_role != 0 || section->gc_src_offset != c->source_offset))
              section = section->next;
            if (!section) goto refuse;
            section->gc_role = 2;
            g->young_heap_secs[i] = section;
            section = section->next;
          }
      }

    /* Reserve k copy-destination sections (gc_role == 0). */
    section = next_copy_plan_section(g->is_minor ? g->young_head : the_msections->head);
    g->copy_first = section;
    g->copy_cursor = section;
    for (i = 0; i < k; i++)
      {
        if (!section) goto refuse;
        section = next_copy_plan_section(section->next);
      }
    g->copy_past = section;
  }

  g->planned_copy_sections=(int)k;
  g->issued_copy_sections=w - g->promo_tail_count;
  g->large_sections=0;
  g->source_words=c->source_words;g->source_sections=nb_msections_assigned;
  g->destination_offset=(___MSECTION_SIZE>>1)-c->source_offset;
  c->count=c->next=0;c->state=___GC_PLAN_ACCEPTED;
  if(c->queue && !c->replacement && !c->retired &&
     c->capacity > (___CENSUS_QUEUE_RETAIN_MAX_BYTES / sizeof(*c->queue))) {
    census_queue_free(c->queue, c->capacity);
    c->queue=0; c->capacity=0;
  }
  return 1;
 refuse:
  work->census=0;ps->collector=0;c->count=c->next=0;c->state=___GC_PLAN_REFUSED;
  if(c->queue && !c->replacement && !c->retired &&
     c->capacity > (___CENSUS_QUEUE_RETAIN_MAX_BYTES / sizeof(*c->queue))) {
    census_queue_free(c->queue, c->capacity);
    c->queue=0; c->capacity=0;
  }
  return 2;
}
