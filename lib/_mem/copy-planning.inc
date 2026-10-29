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

___HIDDEN int census_claim(___collector_worker *work, ___WORD *source,
                          ___SIZE_TS span, ___SIZE_TS request, int frame)
{
  ___processor_state ___ps=work->carrier;
  ___gc_census *c=work->census;
  int i=find_msection(the_msections,source);
  ___SIZE_TS at,j,half=___MSECTION_SIZE>>1;
  ___msection *section;
  ___WORD *bits;
  if(c->failed) return 0;
  if(i<0 || i>=the_msections->nb_sections || span<1 || request<1) goto invalid;
  section=the_msections->sections[i];
  { ___UWORD address=___CAST(___UWORD,source);
    ___UWORD base=___CAST(___UWORD,section->base+c->source_offset);
    if(address<base || address-base>=half*___WS || (address-base)%___WS) goto invalid;
    at=(address-base)/___WS;
  }
  if(span>half-at || request>half-3) goto invalid;
  bits=section->base+___MSECTION_SIZE;
  { int shift=2*(at%(___WORD_WIDTH/2));
    int old=(___CAST(___UWORD,bits[at/(___WORD_WIDTH/2)])>>shift)&3;
    if(old==(frame?2:3)) return 0;
    if(old) goto invalid;
  }
  /* Full source intervals, not only pointer keys, must be disjoint. This
   * detects a frame/header inside another object's extent before copying. */
  for(j=at;j<at+span;j++) {
    int shift=2*(j%(___WORD_WIDTH/2));
    if((___CAST(___UWORD,bits[j/(___WORD_WIDTH/2)])>>shift)&3) goto invalid;
  }
  for(j=at;j<at+span;j++) {
    int shift=2*(j%(___WORD_WIDTH/2));
    bits[j/(___WORD_WIDTH/2)]|=___CAST(___WORD,___CAST(___UWORD,j==at?(frame?2:3):1)<<shift);
  }
  if(!census_checked_add(&c->source_words,span) ||
     !census_checked_add(&c->destination_words,request)) goto invalid;
  if(request>c->largest_request)c->largest_request=request;
  if(request>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE-3) ++c->large_count;
  else {
    if(!census_checked_add(&c->small_words,request)) goto invalid;
    if(request>c->small_max)c->small_max=request;
  }
  if(frame)++c->frames;else ++c->objects;
  return 1;
invalid:
  c->failed=1;return 0;
}

___HIDDEN void census_enqueue(___collector_worker *work, ___SCMOBJ value)
{
  ___gc_census *c=work->census;
  if(c->failed)return;
  if(c->count==c->capacity) {
    ___SIZE_T capacity=c->capacity?2*c->capacity:___WORD_WIDTH;
    if(capacity<c->capacity || capacity>~___CAST(___SIZE_T,0)/sizeof(*c->queue)) {
      c->failed=1;return;
    }
    /* Both superseded and replacement buffers have a VM-owned publication
     * slot. Interruption of malloc/copy/free is never an idempotent retry. */
    c->state=___GC_PLAN_ALLOCATING;
    c->replacement=___CAST(___SCMOBJ*,___ALLOC_MEM(capacity*sizeof(*c->queue)));
    if(c->replacement==0) {c->state=___GC_PLAN_READING;c->failed=1;return;}
    if(c->count)memcpy(c->replacement,c->queue,c->count*sizeof(*c->queue));
    c->retired=c->queue;c->queue=c->replacement;c->replacement=0;
    if(c->retired)___FREE_MEM(c->retired);
    c->retired=0;c->capacity=capacity;c->state=___GC_PLAN_READING;
    if(capacity*sizeof(*c->queue)>c->peak_bytes)c->peak_bytes=capacity*sizeof(*c->queue);
  }
  c->queue[c->count++]=value;
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
      ___WORD *mark=body+___STILL_MARK-___STILL_BODY;
      if(*mark)continue;
      *mark=1;++c->still;census_enqueue(work,value);continue;
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
                                     ___WORD ra, ___frame_descriptor *d)
{
  ___processor_state ___ps=work->carrier;
  ___gc_census *c=work->census;
  ___msection *section;
  ___UWORD address=___CAST(___UWORD,top),first;
  int i=find_msection(the_msections,top);
  if(i<0 || i>=the_msections->nb_sections)goto invalid;
  section=the_msections->sections[i];first=___CAST(___UWORD,section->base+c->source_offset);
  if(address<first || address-first>=(___MSECTION_SIZE>>1)*___WS)goto invalid;
  *d=___decode_frame_descriptor(___LABEL_DESCR_GET(ra==___GSTATE->internal_return?
      ___FP_STK(top,___RETI_RA):ra),ra==___GSTATE->internal_return);
  if(d->fs<=0 || d->link<0 || d->link>=d->fs ||
     ___FRAME_SPACE(d->fs)>(___MSECTION_SIZE>>1)-(address-first)/___WS)goto invalid;
  return 1;
invalid:c->failed=1;return 0;
}

___HIDDEN void census_capture(___collector_worker *work, ___WORD *cell)
{
  ___gc_census *c=work->census;
  ___WORD cf=*cell,ra=0;
  int carry=0;
  while(___FIXNUMP(cf) && cf!=___END_OF_CONT_MARKER && !c->failed) {
    ___WORD *top=___CAST(___WORD*,cf),*base,next;
    ___frame_descriptor d;
    if(!carry)ra=___FP_STK(top,-___FRAME_STACK_RA);
    if(!census_frame_descriptor(work,top,ra,&d))return;
    base=top+___FRAME_SPACE(d.fs);next=___FP_STK(base,d.link+1);
    if(___FIXNUMP(next)) {
      if(next==___END_OF_CONT_MARKER) {c->failed=1;return;}
      cf=___TAG(___UNTAG_AS(next,___tFIXNUM),___tSUBTYPED);break;
    }
    if(!census_claim(work,top,___FRAME_SPACE(d.fs),d.fs+___FRAME_EXTRA_SLOTS+1,1))return;
    mark_frame(work,base,&d);
    if(next==___GSTATE->handler_break) {
      cf=___FP_STK(base,-___BREAK_FRAME_NEXT);carry=0;
    } else {cf=___CAST(___WORD,base);ra=next;carry=1;}
  }
  if(cf!=___END_OF_CONT_MARKER && !c->failed)census_array(work,&cf,1);
}

___HIDDEN void census_continuation(___collector_worker *work, ___execution_context *context)
{
  ___WORD *top=context->fp,ra=0;
  int carry=0;
  while(top!=context->stack_break && !work->census->failed) {
    ___frame_descriptor d;___WORD *base,next;
    if(!carry)ra=___FP_STK(top,-___FRAME_STACK_RA);
    if(!census_frame_descriptor(work,top,ra,&d))return;
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

___HIDDEN int plan_copy_round(___processor_state ps)
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
  c->count=c->next=0;c->source_words=c->destination_words=0;
  c->objects=c->frames=c->still=0;c->small_words=c->small_max=0;
  c->largest_request=c->large_count=0;c->failed=0;
  c->source_offset=ps->mem.tospace_offset_;c->state=___GC_PLAN_READING;
  for(i=0;i<n;i++)g->observed[i]=0;
  if(custom_msection_alloc || w<1 || w>n ||
     ___LOAD_GLOBAL_WORD(&g->requested_workers)<0 ||
     ___LOAD_GLOBAL_WORD(&g->requested_workers)>n)goto refuse;
  for(section=the_msections->head;section;section=section->next)
    memset(section->base+___MSECTION_SIZE,0,___msection_scan_words(___MSECTION_SIZE)*___WS);
  for(i=0;i<n;i++) {
    ___WORD *base=___CAST(___WORD*,round->members[i].owner->mem.still_objs_);
    while(base) {base[___STILL_MARK]=0;base=___CAST(___WORD*,base[___STILL_LINK]);}
  }
  work->census=c;ps->collector=work;work->traverse_weak_refs_=1;
  mark_vm_scmobj(___PSP vm);mark_symkey_tables(___PSP ___GSTATE);
  for(i=0;i<n && !c->failed;i++) {
    ___root_member *m=&round->members[i];___rc_header *h;___WORD *base;
    ___RC_LOCK(m->rc);
    for(h=m->rc->head.next;h!=&m->rc->head;h=h->next)census_array(work,&h->data,1);
    ___RC_UNLOCK(m->rc);
    mark_global_variables(___PSP &m->globals);
    mark_registers(___PSP m->context);mark_saved(___PSP m->context);
    mark_type_cache(___PSP m->context);mark_processor_scmobj(___PSP m->context);
    census_continuation(work,m->context);
    base=___CAST(___WORD*,m->owner->mem.still_objs_);
    while(base) {
      if(base[___STILL_REFCOUNT]!=0) {___WORD value=___SUBTYPED_FROM_BODY(base+___STILL_BODY);census_array(work,&value,1);}
      base=___CAST(___WORD*,base[___STILL_LINK]);
    }
    { ___WORD lists[2]={m->owner->mem.executable_wills_,m->owner->mem.nonexecutable_wills_};int j;
      for(j=0;j<2;j++) {___WORD list=lists[j];while(___UNTAG(list)!=0 && !c->failed) {
        ___WORD value=___SUBTYPED_FROM_START(___UNTAG(list));
        list=___BODY0(value)[___WILL_NEXT];census_array(work,&value,1);
      }}
    }
  }
  census_drain(work);work->census=0;ps->collector=0;
  if(c->failed)goto refuse;
  /* Threshold markers each charge at least MSECTION_CHUNK successful words.
   * Large requests are isolated events, not part of the small no-fit bound. */
  if(!___gc_copy_section_bound(w,c->small_words,c->small_max,c->large_count,
       capacity,___MSECTION_CHUNK,&k) ||
     !___gc_copy_plan_fits(n,k,the_msections->nb_sections))goto refuse;
  section=the_msections->head;
  for(i=0;i<n;i++) {
    ___gc_resume_space *r=&round->resume[i];___execution_context *context=round->members[i].context;
    ___SIZE_TS length=context->stack_break+___FIRST_BREAK_FRAME_SPACE-context->fp;
    if(!section || length<0 || length>(___MSECTION_SIZE>>1)-___MSECTION_FUDGE ||
       (i>=w && restore_loan_words(length)<___MSECTION_FUDGE+2))goto refuse;
    r->stack_section=section;r->context=context;r->owner=round->members[i].owner;
    r->epoch=round->epoch;r->accepted=r->restored=r->loan_used=0;
    section=section->next;
  }
  g->copy_first=section;
  for(i=0;i<k;i++) {if(!section)goto refuse;section=section->next;}
  g->copy_past=section;g->planned_copy_sections=(int)k;
  g->issued_copy_sections=w;g->large_sections=0;
  g->source_words=c->source_words;g->source_sections=nb_msections_assigned;
  g->destination_offset=(___MSECTION_SIZE>>1)-c->source_offset;
  c->count=c->next=0;c->state=___GC_PLAN_ACCEPTED;return 1;
refuse:
  work->census=0;ps->collector=0;c->count=c->next=0;c->state=___GC_PLAN_REFUSED;return 2;
}
