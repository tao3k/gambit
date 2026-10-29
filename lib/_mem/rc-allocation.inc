/* RC list membership, payload access, scan and retirement share one source gate.
 * A domain outlives its carrier while byte-only native owners remain. */
___HIDDEN void rc_contract_error(char *message)
{
  char *messages[] = {message, 0};
  ___fatal_error(messages);
}

/* One cooperative owner predicate for all managed mutable root stores.
 * RC list/payload callers additionally hold their source mutex. No caller may
 * allocate, poll or reenter between this predicate and its final root store. */
___HIDDEN ___BOOL root_writer_open(___processor_state ps)
{
  ___rc_domain *d;
  if (ps == 0 || ps != ___PSTATE || (d=ps->mem.rc_domain_) == 0) return 0;
  return d->owner == ps && d->phase == ___RC_OPEN && d->joined_round == 0;
}

___HIDDEN ___BOOL setup_rc(___processor_state ps)
{
  ___rc_domain *d = ___CAST(___rc_domain*, ___ALLOC_MEM(sizeof(*d)));
  if (d == 0) return 0;
  if (!___RC_INIT(d)) { ___FREE_MEM(d); return 0; }
  d->round=0; d->joined_round=0;
  if (___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps)) == 0)
    {
      d->round=___CAST(___root_round*,___ALLOC_MEM(sizeof(*d->round)));
      if (d->round == 0) { ___RC_DESTROY(d); ___FREE_MEM(d); return 0; }
      memset(d->round,0,sizeof(*d->round));
      d->round->vm=___VMSTATE_FROM_PSTATE(ps);
      { int i; for(i=0;i<___MAX_PROCESSORS;i++) {
          d->round->workers[i].vm=d->round->vm;
          d->round->workers[i].id=i;
          d->round->workers[i].carrier=___PSTATE_FROM_PROCESSOR_ID(i,d->round->vm);
        } }

      d->round->epoch=0; d->round->participants=0;
      d->round->state=___ROOT_ROUND_IDLE;
    }
  d->head.prev = d->head.next = &d->head;
  d->head.refcount = 1; d->head.data = ___FAL;
  d->head.domain = d; d->head.root_borrows = 0;
  d->owner = ps; d->nodes = d->borrows = 0; d->phase = ___RC_OPEN;
  d->task.origin.kind=___ROOT_RC; d->task.origin.source.rc=d; d->task.executor=0; d->task.epoch=0;
  d->task.state=___ROOT_EMPTY; d->task.scan_leases=0;
  ps->mem.rc_domain_ = d;
  return 1;
}

___HIDDEN ___BOOL rc_can_close(___rc_domain *d)
{
  ___rc_header *h;
  if (d->joined_round != 0) return 0;
  if (d->round != 0 && (d->round->state != ___ROOT_ROUND_IDLE ||
      d->round->collection.census.state==___GC_PLAN_ALLOCATING ||
      d->round->collection.census.state==___GC_PLAN_RETAINED ||
      d->round->collection.census.replacement || d->round->collection.census.retired)) return 0;
  if (d->borrows != 0 || d->task.scan_leases != 0 || d->phase == ___RC_FROZEN) return 0;
  for (h=d->head.next; h!=&d->head; h=h->next)
    if (h->data != ___FAL) return 0;
  return 1;
}

___BOOL ___rc_prepare_cleanup(___processor_state ps)
{
  ___rc_domain *d = ps->mem.rc_domain_;
  ___BOOL ready;
  if (d == 0) return 1;
  ___RC_LOCK(d);
  ready = (d->phase == ___RC_OPEN || d->phase == ___RC_CLOSING) && rc_can_close(d);
  if (ready) d->phase = ___RC_CLOSING;
  ___RC_UNLOCK(d);
  return ready;
}

void ___rc_cancel_cleanup(___processor_state ps)
{
  ___rc_domain *d = ps->mem.rc_domain_;
  if (d == 0) return;
  ___RC_LOCK(d);
  if (d->phase == ___RC_CLOSING) d->phase = ___RC_OPEN;
  ___RC_UNLOCK(d);
}

___HIDDEN void cleanup_rc(___processor_state ps)
{
  ___rc_domain *d = ps->mem.rc_domain_;
  ___BOOL destroy;
  if (d == 0) return;
  ___RC_LOCK(d);
  if (d->phase != ___RC_CLOSING || !rc_can_close(d))
    { ___RC_UNLOCK(d); rc_contract_error("RC cleanup without closed root ownership"); return; }
  /* Native byte owners retain both their allocation and this gate. No PS/VM
   * address remains in the detached domain; last native release reclaims it. */
  if (d->round != 0) {
    if (d->round->collection.census.queue != 0)
      ___FREE_MEM(d->round->collection.census.queue);
    ___FREE_MEM(d->round); d->round=0;
  }
  d->owner = 0; d->task.executor = 0; d->phase = ___RC_DETACHED;
  destroy = d->nodes == 0;
  ps->mem.rc_domain_ = 0;
  ___RC_UNLOCK(d);
  if (destroy) { ___RC_DESTROY(d); ___FREE_MEM(d); }
}

___HIDDEN void reopen_rc_roots(___processor_state ps, ___UWORD epoch)
{
  ___rc_domain *d = ps->mem.rc_domain_;
  ___root_round *round;
  ___BOOL completion_owner;
  int id;
  ___RC_LOCK(d);
  round=d->joined_round;
  /* The current native owner reopens its source after physical restoration.
   * The scan executor may be a different W worker; its completion alone is
   * insufficient to authorize the source's return to mutation. */
  completion_owner=d->owner==ps && ps==___PSTATE;
  if (round != 0) {
    id=___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps));
    completion_owner=completion_owner && round->vm==___VMSTATE_FROM_PSTATE(ps) &&
      round->state==___ROOT_ROUND_DRAINING && round->epoch==epoch &&
      id>=0 && id<round->participants && round->collection.worker_count>0 &&
      round->members[id].rc==d && round->members[id].context==ps->context &&
      d->task.executor==round->members[id%round->collection.worker_count].owner &&
      round->resume[id].epoch==epoch && round->resume[id].accepted &&
      round->resume[id].restored;
  } else completion_owner=completion_owner && d->task.executor==ps;
  if (!completion_owner || d->phase != ___RC_FROZEN || d->task.origin.kind != ___ROOT_RC ||
      d->task.origin.source.rc != d || d->task.epoch != epoch ||
      d->task.state != ___ROOT_DONE || d->task.scan_leases != 0)
    { ___RC_UNLOCK(d); rc_contract_error("RC source cannot resume before task completion"); return; }
  d->phase = ___RC_OPEN;
  ___RC_UNLOCK(d);
}

___EXP_FUNC(void*,___alloc_rc_no_register)
   ___P((___SIZE_T bytes),(bytes) ___SIZE_T bytes;)
{
  ___rc_header *h;
  if (bytes > ~___CAST(___SIZE_T,0)-sizeof(*h)) return 0;
  h=___CAST(___rc_header*,___ALLOC_MEM(bytes+sizeof(*h)));
  if (h == 0) return 0;
  h->prev=h->next=h; h->refcount=1; h->data=___FAL;
  h->domain=0; h->root_borrows=0;
  return ___CAST(void*,h+1);
}

___EXP_FUNC(void*,___register_rc)
   ___P((___PSD void *ptr),(___PSV ptr) ___PSDKR void *ptr;)
{
  ___PSGET
  ___rc_header *h;
  ___rc_domain *d;
  if (ptr == 0 || ___ps == 0 || ___ps != ___PSTATE) return 0;
  h=___CAST(___rc_header*,ptr)-1; d=___ps->mem.rc_domain_;
  /* First registration requires exclusive ownership of a private block.
   * A registered block cannot be moved by re-registering it with another PS. */
  if (h->domain != 0) return h->domain == d ? ptr : 0;
  if (d == 0) return 0;
  ___RC_LOCK(d);
  if (d->joined_round != 0 || d->phase != ___RC_OPEN || d->nodes == ~___CAST(___SIZE_T,0))
    { ___RC_UNLOCK(d); return 0; }
  h->prev=d->head.prev; h->next=&d->head;
  d->head.prev->next=h; d->head.prev=h;
  h->domain=d; ++d->nodes;
  ___RC_UNLOCK(d);
  return ptr;
}

___EXP_FUNC(void*,___alloc_rc)
   ___P((___PSD ___SIZE_T bytes),(___PSV bytes) ___PSDKR ___SIZE_T bytes;)
{
  ___PSGET
  void *ptr=___alloc_rc_no_register(bytes);
  if (ptr != 0 && ___register_rc(___PSP ptr) == 0)
    { ___FREE_MEM(___CAST(___rc_header*,ptr)-1); return 0; }
  return ptr;
}

___HIDDEN ___BOOL rc_unlink_if_dead(___rc_domain *d, ___rc_header *h)
{
  if (h->refcount != 0 || h->root_borrows != 0) return 0;
  h->next->prev=h->prev; h->prev->next=h->next;
  --d->nodes;
  return 1;
}

___EXP_FUNC(void,___release_rc)
   ___P((void *ptr),(ptr) void *ptr;)
{
  ___rc_header *h;
  ___rc_domain *d;
  ___BOOL dead, destroy;
  if (ptr == 0) return;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d == 0) { if (--h->refcount == 0) ___FREE_MEM(h); return; }
  ___RC_LOCK(d);
  if (h->refcount <= 0)
    { ___RC_UNLOCK(d); rc_contract_error("RC owner released twice"); return; }
  --h->refcount;
  dead=rc_unlink_if_dead(d,h);
  destroy=d->phase == ___RC_DETACHED && d->nodes == 0;
  ___RC_UNLOCK(d);
  if (dead) ___FREE_MEM(h);
  if (destroy) { ___RC_DESTROY(d); ___FREE_MEM(d); }
}

___EXP_FUNC(void,___addref_rc)
   ___P((void *ptr),(ptr) void *ptr;)
{
  ___rc_header *h;
  ___rc_domain *d;
  if (ptr == 0) return;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d != 0) ___RC_LOCK(d);
  if (h->refcount <= 0 || h->refcount == ___MAX_FIX)
    { if (d != 0) ___RC_UNLOCK(d); rc_contract_error("RC owner count exhausted or closed"); return; }
  ++h->refcount;
  if (d != 0) ___RC_UNLOCK(d);
}

___EXP_FUNC(___WORD,___refcount_rc)
   ___P((void *ptr),(ptr) void *ptr;)
{
  ___rc_header *h=___CAST(___rc_header*,ptr)-1;
  ___rc_domain *d=h->domain;
  ___WORD count;
  if (d != 0) ___RC_LOCK(d);
  count=h->refcount;
  if (d != 0) ___RC_UNLOCK(d);
  return count;
}

___EXP_FUNC(___SCMOBJ,___data_rc)
   ___P((void *ptr),(ptr) void *ptr;)
{
  ___rc_header *h=___CAST(___rc_header*,ptr)-1;
  ___rc_domain *d=h->domain;
  ___SCMOBJ value;
  if (d != 0) ___RC_LOCK(d);
  value=h->data;
  if (d != 0) ___RC_UNLOCK(d);
  return value; /* Snapshot only: a stable root borrow must span allocating calls. */
}

___BOOL ___try_set_data_rc(___processor_state ps, void *ptr, ___SCMOBJ value)
{
  ___rc_header *h;
  ___rc_domain *d;
  if (ptr == 0 || ps == 0 || ps != ___PSTATE) return 0;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d == 0 || d != ps->mem.rc_domain_) return 0;
  ___RC_LOCK(d);
  if (d->owner != ps || d->joined_round != 0 || d->phase != ___RC_OPEN || h->refcount <= 0 ||
      (h->root_borrows != 0 && h->data != value))
    { ___RC_UNLOCK(d); return 0; }
  /* A borrowed cell may be relocated by the collector, not rebound by a
   * mutator. An idempotent admission performs no racing same-value store. */
  if (h->data != value) h->data=value;
  ___RC_UNLOCK(d);
  return 1;
}

___EXP_FUNC(void,___set_data_rc)
   ___P((void *ptr, ___SCMOBJ value),(ptr,value) void *ptr; ___SCMOBJ value;)
{
  if (!___try_set_data_rc(___PSTATE,ptr,value))
    rc_contract_error("RC payload write outside source ownership");
}

const ___SCMOBJ *___borrow_rc_root(___processor_state ps, void *ptr)
{
  ___rc_header *h;
  ___rc_domain *d;
  if (ptr == 0 || ps == 0 || ps != ___PSTATE) return 0;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d == 0 || d != ps->mem.rc_domain_) return 0;
  ___RC_LOCK(d);
  if (d->joined_round != 0 || d->phase != ___RC_OPEN || h->refcount <= 0 ||
      d->borrows == ~___CAST(___SIZE_T,0) || h->root_borrows == ___MAX_FIX)
    { ___RC_UNLOCK(d); return 0; }
  ++h->root_borrows; ++d->borrows;
  ___RC_UNLOCK(d);
  return &h->data;
}

void ___return_rc_root(void *ptr)
{
  ___rc_header *h=___CAST(___rc_header*,ptr)-1;
  ___rc_domain *d=h->domain;
  ___BOOL dead;
  ___RC_LOCK(d);
  if (h->root_borrows <= 0 || d->borrows == 0)
    { ___RC_UNLOCK(d); rc_contract_error("RC borrow returned without custody"); return; }
  --h->root_borrows; --d->borrows;
  dead=rc_unlink_if_dead(d,h);
  ___RC_UNLOCK(d);
  if (dead) ___FREE_MEM(h);
}
