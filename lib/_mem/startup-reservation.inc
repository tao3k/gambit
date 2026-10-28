/* Physical grants are charged before setup, under the stopped old cohort.
 * These are startup intervals, not a pre-copy bound for the whole collector. */
#ifndef ___SINGLE_THREADED_VMS
int ___resume_msections(___virtual_machine_state vm)
{
  ___SIZE_T reserve=vm->mem.normal_overflow_reserve_;
  ___SIZE_T fudge=4*___CAST(___SIZE_T,___MSECTION_FUDGE);
  ___SIZE_T words;
  if (reserve > ~___CAST(___SIZE_T,0)-fudge-(___MSECTION_SIZE-1)) return INT_MAX;
  words=(reserve+fudge+___MSECTION_SIZE-1)/___MSECTION_SIZE;
  return words > INT_MAX ? INT_MAX : ___CAST(int,words);
}

int ___restore_msections(___virtual_machine_state vm)
{
  int p, count=0;
  for (p=0;p<vm->processor_count;++p)
    {
      ___processor_state ps=___PSTATE_FROM_PROCESSOR_ID(p,vm);
      if (ps->mem.alloc_heap_ptr_ > ps->mem.alloc_heap_limit_-___MSECTION_FUDGE)
        ++count;
    }
  return count;
}

___SCMOBJ ___reserve_resize(___processor_state ___ps, ___resize_state *r)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
  int n=r->target-r->first, resume=___resume_msections(vm), need, i;
  ___msection *cursor;
  if (n<0 || n>___MAX_PROCESSORS || resume==INT_MAX ||
      nb_msections_assigned > INT_MAX-2*n-resume)
    return ___FIX(___HEAP_OVERFLOW_ERR);
  need=nb_msections_assigned+2*n+resume;
  if (___GSTATE->setup_params.max_heap>0)
    {
      ___SIZE_T cap=___GSTATE->setup_params.max_heap>>___LWS;
      if (occupied_words_still<0 || cap<___CAST(___SIZE_T,occupied_words_still) ||
          (cap-occupied_words_still)/___MSECTION_SIZE<___CAST(___SIZE_T,need))
        return ___FIX(___HEAP_OVERFLOW_ERR);
    }
  if (the_msections->nb_sections<need) adjust_msections(&the_msections,need);
  heap_size=compute_heap_size();
  if (the_msections->nb_sections<need) return ___FIX(___HEAP_OVERFLOW_ERR);
  r->saved_assigned=nb_msections_assigned;
  r->saved_stacks=nb_msections_stacks;
  r->saved_cursor=alloc_msection;
  cursor=nb_msections_assigned==0 ? the_msections->head : alloc_msection->next;
  /* Validate the entire linked suffix before publishing any slot grant. */
  for (i=0;i<2*n;++i)
    { if (cursor==0) return ___FIX(___UNKNOWN_ERR); cursor=cursor->next; }
  cursor=nb_msections_assigned==0 ? the_msections->head : alloc_msection->next;
  for (i=r->first;i<r->target;++i)
    {
      ___resize_slot *slot=&r->slots[i];
      slot->stack=cursor; slot->heap=cursor->next;
      cursor=slot->heap->next;
      slot->phase=___RESIZE_RESERVED;
    }
  if (n>0) alloc_msection=r->slots[r->target-1].heap;
  nb_msections_assigned+=2*n;
  nb_msections_stacks+=n;
  return ___FIX(___NO_ERR);
}

void ___refund_resize(___processor_state ___ps, ___resize_state *r)
{
  int i;
  nb_msections_assigned=r->saved_assigned;
  nb_msections_stacks=r->saved_stacks;
  alloc_msection=r->saved_cursor;
  for (i=r->first;i<r->target;++i)
    { r->slots[i].stack=0; r->slots[i].heap=0; r->slots[i].phase=___RESIZE_EMPTY; }
  /* Newly allocated free sections remain available, not charged to a context. */
  heap_size=compute_heap_size();
}
#endif
