#line 4334 ___MEM_SOURCE_FILE
static ___VOLATILE ___SIZE_T gc_freed_malloc_still_words_ = 0;

___HIDDEN void gc_record_freed_malloc_still_words(___SIZE_T words)
{
  if (words == 0)
    return;
#if defined(__ATOMIC_RELAXED)
  (void)__atomic_fetch_add(&gc_freed_malloc_still_words_, words, __ATOMIC_RELAXED);
#else
  gc_freed_malloc_still_words_ += words;
#endif
}

___HIDDEN ___SIZE_T gc_take_freed_malloc_still_words ___PVOID
{
#if defined(__ATOMIC_ACQ_REL)
  return __atomic_exchange_n(&gc_freed_malloc_still_words_, (___SIZE_T)0, __ATOMIC_ACQ_REL);
#else
  ___SIZE_T w = gc_freed_malloc_still_words_;
  gc_freed_malloc_still_words_ = 0;
  return w;
#endif
}

___HIDDEN void sweep_young_still_objs
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *base = ___CAST(___WORD*, young_still_objs);
  ___SIZE_TS promoted_words = 0;
  ___SIZE_T freed_malloc_words = 0;

  young_still_objs = 0;
  words_still_objs_young = 0;

  while (base != 0)
    {
      ___WORD link = base[___STILL_LINK];
      if (base[___STILL_MARK] == -1)
        {
          ___WORD head = base[___STILL_BODY-1];
          if (___HD_SUBTYPE(head) == ___sFOREIGN)
            ___lifecycle_defer(___ps, base);
          else
            {
              ___SIZE_TS len = base[___STILL_LENGTH];
              if (!free_mem_aligned_heap_ex(base) && len > 0)
                freed_malloc_words += (___SIZE_T)len;
            }
        }
      else
        {
#ifndef ___USE_HANDLES
          {
            ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
            if (___WORD_LOAD_RELAXED(&vm->mem.major_phase_) == ___GC_MAJOR_MARKING)
              base[___STILL_DIRTY] = ___STILL_MAJOR_MARK_BIT(vm->mem.major_epoch_);
            else
              base[___STILL_DIRTY] = 0;
          }
#endif
          promoted_words += base[___STILL_LENGTH];
          base[___STILL_LINK] = still_objs;
          still_objs = ___CAST(___WORD, base);
        }
      base = ___CAST(___WORD*, link);
    }

  gc_record_freed_malloc_still_words(freed_malloc_words);

  words_still_objs_mature += promoted_words;
  words_still_objs = words_still_objs_mature + ___lifecycle_deferred_words(___ps);
  words_still_objs_deferred = 0;
  still_words_budget = 0;
}


___HIDDEN void free_unmarked_still_objs
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD *last = &still_objs;
  ___WORD *base = ___CAST(___WORD*,*last);
  ___WORD *young = ___CAST(___WORD*,young_still_objs);
  ___SIZE_TS live_words_still = 0;
  ___SIZE_T freed_malloc_words = 0;

  young_still_objs = 0;
  words_still_objs_young = 0;

  while (base != 0)
    {
      ___WORD link = base[___STILL_LINK];
      if (base[___STILL_MARK] == -1)
        {
          ___WORD head = base[___STILL_BODY-1];
          if (___HD_SUBTYPE(head) == ___sFOREIGN)
            ___lifecycle_defer(___ps,base);
          else
            {
              ___SIZE_TS len = base[___STILL_LENGTH];
              if (!free_mem_aligned_heap_ex(base) && len > 0)
                freed_malloc_words += (___SIZE_T)len;
            }
        }
      else
        {
#ifndef ___USE_HANDLES
          base[___STILL_DIRTY] = 0;
#endif
          live_words_still += base[___STILL_LENGTH];
          *last = ___CAST(___WORD,base);
          last = base + ___STILL_LINK;
        }
      base = ___CAST(___WORD*,link);
    }

  while (young != 0)
    {
      ___WORD link = young[___STILL_LINK];
      if (young[___STILL_MARK] == -1)
        {
          ___WORD head = young[___STILL_BODY-1];
          if (___HD_SUBTYPE(head) == ___sFOREIGN)
            ___lifecycle_defer(___ps,young);
          else
            {
              ___SIZE_TS len = young[___STILL_LENGTH];
              if (!free_mem_aligned_heap_ex(young) && len > 0)
                freed_malloc_words += (___SIZE_T)len;
            }
        }
      else
        {
#ifndef ___USE_HANDLES
          young[___STILL_DIRTY] = 0;
#endif
          live_words_still += young[___STILL_LENGTH];
          *last = ___CAST(___WORD,young);
          last = young + ___STILL_LINK;
        }
      young = ___CAST(___WORD*,link);
    }

  *last = 0;

  gc_record_freed_malloc_still_words(freed_malloc_words);

  words_still_objs_mature = live_words_still;
  words_still_objs = live_words_still + ___lifecycle_deferred_words(___ps);
  words_still_objs_deferred = 0;
  still_words_budget = 0;

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
  ___WORD *young = ___CAST(___WORD*,young_still_objs);

  still_objs = 0;
  young_still_objs = 0;
  words_still_objs_mature = 0;
  words_still_objs_young = 0;
  while (base != 0)
    {
      ___WORD link=base[___STILL_LINK];
      if (___HD_SUBTYPE(base[___STILL_BODY-1])==___sFOREIGN)
        ___lifecycle_defer(___ps,base);
      else free_mem_aligned_heap(base);
      base=___CAST(___WORD*,link);
    }
  while (young != 0)
    {
      ___WORD link=young[___STILL_LINK];
      if (___HD_SUBTYPE(young[___STILL_BODY-1])==___sFOREIGN)
        ___lifecycle_defer(___ps,young);
      else free_mem_aligned_heap(young);
      young=___CAST(___WORD*,link);
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
  ___WORD entries=___WORD_LOAD_ACQUIRE(&vm->lifecycle->entries[id]);
  /* A terminal startup owns its entire native stack. A nested host callback
   * owns a return to external C and cannot be abandoned by processor removal.
   * The marker and ___call each hold one entry; unrelated borrows refuse. */
  if(record) {
    if(record->kind!=___ACTIVATION_STARTUP || record->next || entries!=4)return ___HANDOFF_BUSY;
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
  base=___CAST(___WORD*,ps->mem.young_still_objs_);
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
    from->mem.still_objs_=0;
  }
  base=___CAST(___WORD*,from->mem.young_still_objs_);
  if(base) {
    ___WORD *last=base;
    while(last[___STILL_LINK])last=___CAST(___WORD*,last[___STILL_LINK]);
    last[___STILL_LINK]=to->mem.young_still_objs_;to->mem.young_still_objs_=from->mem.young_still_objs_;
    from->mem.young_still_objs_=0;
  }
  to->mem.words_still_objs_+=from->mem.words_still_objs_;
  to->mem.words_still_objs_mature_+=from->mem.words_still_objs_mature_;
  to->mem.words_still_objs_young_+=from->mem.words_still_objs_young_;
  to->mem.words_still_objs_deferred_+=from->mem.words_still_objs_deferred_;
  from->mem.words_still_objs_=0;from->mem.words_still_objs_mature_=0;
  from->mem.words_still_objs_young_=0;from->mem.words_still_objs_deferred_=0;
  to->mem.still_words_budget_+=from->mem.still_words_budget_;
  from->mem.still_words_budget_=0;
  to->mem.bytes_allocated_minus_occupied_+=from->mem.bytes_allocated_minus_occupied_;
  from->mem.bytes_allocated_minus_occupied_=0;
}
