#line 4334 ___MEM_SOURCE_FILE
___HIDDEN void free_unmarked_still_objs
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *last = &still_objs;
  ___WORD *base = ___CAST(___WORD*,*last);
  ___SIZE_TS live_words_still = 0;

  while (base != 0)
    {
      ___WORD link = base[___STILL_LINK];
      if (base[___STILL_MARK] == -1)
        {
          ___WORD head = base[___STILL_BODY-1];
          if (___HD_SUBTYPE(head) == ___sFOREIGN)
            ___lifecycle_defer(___ps,base);
          else free_mem_aligned_heap(base);
        }
      else
        {
          live_words_still += base[___STILL_LENGTH];
          *last = ___CAST(___WORD,base);
          last = base + ___STILL_LINK;
        }
      base = ___CAST(___WORD*,link);
    }

  *last = 0;

  words_still_objs = live_words_still + ___lifecycle_deferred_words(___ps);
  words_still_objs_deferred = 0;

  /*
   * In principle the occupied_words_still could be updated here but
   * this would require acquiring a lock, so instead the
   * occupied_words_still will be recomputed from all of the
   * processor's words_still_objs when computing the space occupied by
   * live objects prior to resizing the heap.
   */
}


___HIDDEN void free_still_objs
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___WORD *base = ___CAST(___WORD*,still_objs);

  still_objs = 0;
  while (base != 0)
    {
      ___WORD link=base[___STILL_LINK];
      if (___HD_SUBTYPE(base[___STILL_BODY-1])==___sFOREIGN)
        ___lifecycle_defer(___ps,base);
      else free_mem_aligned_heap(base);
      base=___CAST(___WORD*,link);
    }
  words_still_objs=___lifecycle_deferred_words(___ps);
}


/* End internal memory fragment. */

void ___lifecycle_detach_foreign(___processor_state ps)
{free_still_objs(ps);}
void ___lifecycle_reclaim_foreign(___processor_state ps,___WORD *base)
{ps->mem.words_still_objs_-=base[___STILL_LENGTH];free_mem_aligned_heap(base);}

void ___lifecycle_defer(___processor_state ps,___WORD *base)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___owner_cleanup *q=&vm->lifecycle->cleanup[___PROCESSOR_ID(ps,vm)];
  base[___STILL_LINK]=___CAST(___WORD,q->pending);q->pending=base;
  q->words+=base[___STILL_LENGTH];
}
___SIZE_TS ___lifecycle_deferred_words(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  return vm->lifecycle?vm->lifecycle->cleanup[___PROCESSOR_ID(ps,vm)].words:0;
}
___SIZE_TS ___lifecycle_retained_words(___virtual_machine_state vm)
{
  ___SIZE_TS words=0;int i;
  if(vm->lifecycle)for(i=vm->processor_count;i<___MAX_PROCESSORS;++i)
    words+=vm->lifecycle->cleanup[i].words;
  return words;
}
___BOOL ___lifecycle_drain(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___owner_cleanup *q=&vm->lifecycle->cleanup[___PROCESSOR_ID(ps,vm)];
  ___SCMOBJ ___err;
  ___processor_state ___ps=ps;
  if(q->draining)return 1; /* nested GC retains the outer in-flight debt */
  if(q->uncertain)return 0;
  q->draining=1;
  while(q->pending) {
    ___WORD *base=q->pending;___SCMOBJ obj;
    q->pending=___CAST(___WORD*,base[___STILL_LINK]);q->inflight=base;
    obj=___TAG(base+___STILL_BODY-___REFERENCE_TO_BODY,___tSUBTYPED);
    q->release_fn=___CAST(___SCMOBJ(*)___P((void*),()),___FOREIGN_RELEASE_FN_FIELD(obj));
    q->payload=___CAST(void*,___FOREIGN_PTR_FIELD(obj));
    ___BEGIN_TRY
      ___err=___release_foreign(obj);
    ___END_TRY
    if(___err!=___FIX(___NO_ERR)) {
      q->uncertain=1;q->draining=0;return 0;
    }
    q->words-=base[___STILL_LENGTH];
    ___lifecycle_reclaim_foreign(ps,base);
    q->inflight=0;q->release_fn=0;q->payload=0;
  }
  q->draining=0;return 1;
}

enum ___handoff_status ___lifecycle_can_handoff(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  ___WORD *base=___CAST(___WORD*,ps->mem.still_objs_);
  int id=___PROCESSOR_ID(ps,vm);
  ___owner_cleanup *q=&vm->lifecycle->cleanup[id];
  ___activation_record *record=vm->lifecycle->activations[id];
  ___WORD entries=___LOAD_GLOBAL_WORD(&vm->lifecycle->entries[id]);
  /* A terminal startup owns its entire native stack. A nested host callback
   * owns a return to external C and cannot be abandoned by processor removal.
   * The marker and ___call each hold one entry; unrelated borrows refuse. */
  if(record) {
    if(!record->startup || record->next || entries!=4)return ___HANDOFF_BUSY;
  }else if(entries!=0)return ___HANDOFF_BUSY;
  if(q->uncertain || q->draining || q->inflight)return ___HANDOFF_BUSY;
  if(q->words)return ___HANDOFF_GC;
  while(base) {
    if(___HD_SUBTYPE(base[___STILL_BODY-1])==___sFOREIGN) {
      ___SCMOBJ obj=___TAG(base+___STILL_BODY-___REFERENCE_TO_BODY,___tSUBTYPED);
      if(___FOREIGN_RELEASE_FN_FIELD(obj)!=0)return ___HANDOFF_GC;
    }
    base=___CAST(___WORD*,base[___STILL_LINK]);
  }
  return ___HANDOFF_READY;
}
void ___lifecycle_handoff(___processor_state from,___processor_state to)
{
  ___WORD *base=___CAST(___WORD*,from->mem.still_objs_);
  if(base) {
    ___WORD *last=base;
    while(last[___STILL_LINK])last=___CAST(___WORD*,last[___STILL_LINK]);
    last[___STILL_LINK]=to->mem.still_objs_;to->mem.still_objs_=from->mem.still_objs_;
    to->mem.words_still_objs_+=from->mem.words_still_objs_;
    to->mem.words_still_objs_deferred_+=from->mem.words_still_objs_deferred_;
    from->mem.still_objs_=0;from->mem.words_still_objs_=0;from->mem.words_still_objs_deferred_=0;
  }
  to->mem.bytes_allocated_minus_occupied_+=from->mem.bytes_allocated_minus_occupied_;
  from->mem.bytes_allocated_minus_occupied_=0;
}
