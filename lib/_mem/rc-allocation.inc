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
  ___virtual_machine_state vm;
  int id;
  if (ps == 0 || ps != ___PSTATE || (d=ps->mem.rc_domain_) == 0) return 0;
  vm = ___VMSTATE_FROM_PSTATE(ps);
  id = ___PROCESSOR_ID(ps, vm);
  if (vm->lifecycle && id >= 0 && id < vm->lifecycle->slot_capacity &&
      (vm->lifecycle->cleanup[id].draining || vm->lifecycle->cleanup[id].uncertain))
    return 0;
  return d->owner == ps && d->phase == ___RC_OPEN && d->joined_round == 0;
}

___BOOL ___root_round_init_storage(___root_round *round, int cap)
{
  ___gc_round *g;
  ___SIZE_T total = 0, off = 0, ucap, hcap;
  unsigned char *buf;
  if (!round || cap < 1) return 0;
  if (cap > INT_MAX / ___GC_CARD_HINT_CAPACITY) return 0;
  ucap = ___CAST(___SIZE_T, cap);
  hcap = ucap * ___CAST(___SIZE_T, ___GC_CARD_HINT_CAPACITY);
  g = &round->collection;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->members))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->workers))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->resume))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*round->globals.shards))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->worker_proc))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->proc_worker))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->active))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->active_procs))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->observed))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tails))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_starts))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_ends))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->promo_tail_is_hole))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->major_reclaimed_still))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->major_live_still))) return 0;
  if (!___vm_slot_add_slice(&total, ucap, sizeof(*g->young_heap_secs))) return 0;
  if (!___vm_slot_add_slice(&total, hcap, sizeof(*g->hints))) return 0;
  if (total == 0) return 0;
  buf = ___CAST(unsigned char*, ___ALLOC_MEM(total));
  if (!buf) return 0;
  memset(buf, 0, total);
  round->slot_capacity = cap;
  round->slot_storage = buf;
  g->slot_capacity = cap;
  g->hint_capacity = cap * ___GC_CARD_HINT_CAPACITY;
  round->members = ___CAST(___root_member*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->members)));
  round->workers = ___CAST(___collector_worker*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->workers)));
  round->resume = ___CAST(___gc_resume_space*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->resume)));
  round->globals.shards = ___CAST(unsigned char*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*round->globals.shards)));
  round->globals.shards_heap = 0;
  round->globals.shard_capacity = cap;
  g->worker_proc = ___CAST(int*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->worker_proc)));
  g->proc_worker = ___CAST(int*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->proc_worker)));
  g->active = ___CAST(unsigned char*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->active)));
  g->active_procs = ___CAST(int*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->active_procs)));
  g->observed = ___CAST(int*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->observed)));
  g->promo_tails = ___CAST(___msection**, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tails)));
  g->promo_tail_starts = ___CAST(___SIZE_TS*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_starts)));
  g->promo_tail_ends = ___CAST(___SIZE_TS*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_ends)));
  g->promo_tail_is_hole = ___CAST(unsigned char*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->promo_tail_is_hole)));
  g->major_reclaimed_still = ___CAST(___SIZE_TS*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->major_reclaimed_still)));
  g->major_live_still = ___CAST(___SIZE_TS*, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->major_live_still)));
  g->young_heap_secs = ___CAST(___msection**, ___vm_slot_carve_slice(buf, &off, ucap, sizeof(*g->young_heap_secs)));
  g->hints = ___CAST(___gc_card_hint*, ___vm_slot_carve_slice(buf, &off, hcap, sizeof(*g->hints)));
  return 1;
}

void ___root_round_free_storage(___root_round *round)
{
  if (!round) return;
  if (round->globals.shards_heap != 0) {
    ___FREE_MEM(round->globals.shards_heap);
    round->globals.shards_heap = 0;
    round->globals.shards = 0;
    round->globals.shard_capacity = 0;
  }
  if (round->slot_storage != 0) {
    ___FREE_MEM(round->slot_storage);
    round->slot_storage = 0;
  }
  round->slot_capacity = 0;
  round->collection.slot_capacity = 0;
  round->collection.hint_capacity = 0;
}

___HIDDEN ___BOOL setup_rc(___processor_state ps)
{
  ___rc_domain *d = ___CAST(___rc_domain*, ___ALLOC_MEM(sizeof(*d)));
  if (d == 0) return 0;
  if (!___RC_INIT(d)) { ___FREE_MEM(d); return 0; }
  d->round=0; d->joined_round=0; d->idle_activation=0;
  d->rest_chunks=0; d->rest_total_slots=0; d->rest_evict_cursor=0;
  if (___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps)) == 0)
    {
      ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(ps);
      int cap = (vm->lifecycle && vm->lifecycle->slot_capacity > 0)
                ? vm->lifecycle->slot_capacity : ___MAX_PROCESSORS;
      d->round=___CAST(___root_round*,___ALLOC_MEM(sizeof(*d->round)));
      if (d->round == 0) { ___RC_DESTROY(d); ___FREE_MEM(d); return 0; }
      memset(d->round,0,sizeof(*d->round));
      if (!___root_round_init_storage(d->round, cap))
        { ___FREE_MEM(d->round); ___RC_DESTROY(d); ___FREE_MEM(d); return 0; }
      d->round->vm=vm;
      { int i; for(i=0;i<d->round->slot_capacity;i++) {
          d->round->workers[i].vm=d->round->vm;
          d->round->workers[i].id=i;
          d->round->workers[i].carrier=___PSTATE_FROM_PROCESSOR_ID(i,d->round->vm);
        } }

      d->round->epoch=0; d->round->participants=0;
      d->round->state=___ROOT_ROUND_IDLE;
    }
  d->head.prev = d->head.next = &d->head;
  d->head.refcount = 1; d->head.data = ___FAL;
  d->head.domain = d; d->head.root_borrows = 0; d->head.root_count = 0;
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
  if (d->idle_activation != 0 &&
      (d->idle_activation->kind != ___ACTIVATION_IDLE ||
       d->idle_activation->owner != 0 || d->idle_activation->roots != 0 ||
       d->idle_activation->marker != ___FAL || d->idle_activation->next != 0 ||
       !___rest_control_clear(d->idle_activation)))
    return 0;
  if (d->round != 0 && (d->round->state != ___ROOT_ROUND_IDLE ||
      d->round->collection.census.state==___GC_PLAN_ALLOCATING ||
      d->round->collection.census.state==___GC_PLAN_RETAINED ||
      d->round->collection.census.replacement || d->round->collection.census.retired)) return 0;
  if (d->borrows != 0 || d->task.scan_leases != 0 || d->phase == ___RC_FROZEN) return 0;
  for (h=d->head.next; h!=&d->head; h=h->next) {
    ___SIZE_T i;
    if (h->data != ___FAL) return 0;
    for (i=0; i<h->root_count; i++)
      if (___CAST(___SCMOBJ*,h+1)[i] != ___FAL) return 0;
  }
  return 1;
}

___BOOL ___rc_prepare_cleanup(___processor_state ps)
{
  ___rc_domain *d = ps->mem.rc_domain_;
  ___BOOL ready;
  if (d == 0) return 1;
  ___RC_LOCK(d);
  ready = (d->phase == ___RC_OPEN || d->phase == ___RC_CLOSING) && rc_can_close(d);
  if (ready) { ___binding_context_close(ps); d->phase = ___RC_CLOSING; }
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
  ___binding_context_admit(ps);
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
      census_queue_free(d->round->collection.census.queue, d->round->collection.census.capacity);
    ___root_round_free_storage(d->round);
    ___FREE_MEM(d->round); d->round=0;
  }
  /* Lifecycle closure has excluded the cooperative activation owner. Only
   * a clean, physically retired record can occupy this byte-only slot. */
  if (d->idle_activation != 0) {
    ___FREE_MEM(d->idle_activation); d->idle_activation=0;
  }
  {
    ___rest_directory_chunk *chunk = d->rest_chunks;
    d->rest_chunks = 0;
    d->rest_total_slots = 0;
    d->rest_evict_cursor = 0;
    while (chunk != 0) {
      ___rest_directory_chunk *next = chunk->next;
      ___FREE_MEM(chunk);
      chunk = next;
    }
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
  /* The current native owner (or active coordinator proxying a parked blocking-FFI
   * member under sync_part_mut exclusion) reopens this RC source after physical
   * restoration. Scan completion alone is insufficient to authorize mutation. */
  if (round != 0) {
    ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(ps);
    id=___PROCESSOR_ID(ps,vm);
    completion_owner=d->owner==ps && round->vm==vm &&
      round->state==___ROOT_ROUND_DRAINING && round->epoch==epoch &&
      id>=0 && id<round->participants && round->collection.worker_count>0 &&
      (round->collection.active[id]
       ? (ps==___PSTATE)
       : (___PSTATE==___PSTATE_FROM_PROCESSOR_ID(round->collection.coordinator_id,vm))) &&
      round->members[id].rc==d && round->members[id].context==ps->context &&
      d->task.executor==___PSTATE_FROM_PROCESSOR_ID(
        round->collection.worker_proc[id%round->collection.worker_count],vm) &&
      round->resume[id].epoch==epoch && round->resume[id].accepted &&
      round->resume[id].restored;
  } else completion_owner=d->owner==ps && ps==___PSTATE && d->task.executor==ps;
  if (!completion_owner || d->phase != ___RC_FROZEN || d->task.origin.kind != ___ROOT_RC ||
      d->task.origin.source.rc != d || d->task.epoch != epoch ||
      d->task.state != ___ROOT_DONE || d->task.scan_leases != 0)
    { ___RC_UNLOCK(d); rc_contract_error("RC source cannot resume before task completion"); return; }
  d->phase = ___RC_OPEN;
  ___RC_UNLOCK(d);
  if (round == 0) ___binding_context_admit(ps);
}

___EXP_FUNC(void*,___alloc_rc_no_register)
   ___P((___SIZE_T bytes),(bytes) ___SIZE_T bytes;)
{
  ___rc_header *h;
  if (bytes > ~___CAST(___SIZE_T,0)-sizeof(*h)) return 0;
#ifdef ___GAMBIT_DEV_RESTORE_PROBE
  ___dev_restore_census_native("rc");
#endif
  h=___CAST(___rc_header*,___ALLOC_MEM(bytes+sizeof(*h)));
  if (h == 0) return 0;
  h->prev=h->next=h; h->refcount=1; h->data=___FAL;
  h->domain=0; h->root_borrows=0; h->root_count=0;
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
  if (d == 0 || (h->domain != 0 && h->domain != d)) return 0;
  ___RC_LOCK(d);
  if (!root_writer_open(___ps) || h->refcount <= 0)
    { ___RC_UNLOCK(d); return 0; }
  if (h->domain == d) { ___RC_UNLOCK(d); return ptr; }
  if (d->nodes == ~___CAST(___SIZE_T,0))
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

/* Publish only a completely initialized span. Native metadata allocation and
 * registration do not collect or call Scheme. The ordinary RC source gate and
 * scan lease own both the procedure cell and every argument cell. */
void *___alloc_rc_roots(___processor_state ps, ___SIZE_T count)
{
  void *ptr;
  ___rc_header *h;
  ___SIZE_T i;
  if (count > (~___CAST(___SIZE_T,0)-sizeof(*h))/sizeof(___SCMOBJ)) return 0;
  ptr=___alloc_rc_no_register(count*sizeof(___SCMOBJ));
  if (!ptr) return 0;
  h=___CAST(___rc_header*,ptr)-1;
  h->root_count=count;
  for (i=0; i<count; i++) ___CAST(___SCMOBJ*,ptr)[i]=___FAL;
  if (!___register_rc(___PSA(ps) ptr)) { ___FREE_MEM(h); return 0; }
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

/* One source gate owns mutator writes to the primary cell and typed payload.
 * Primary borrows preserve logical identity. A generated argument span has
 * one activation borrow, whose owner fills its cells between safe points. */
static ___BOOL store_rc_root(___processor_state ps, void *ptr,
                            ___SIZE_T index, ___SCMOBJ value,
                            ___activation_record *record)
{
  ___rc_header *h;
  ___rc_domain *d;
  ___SCMOBJ *cell;
  if (ptr == 0 || ps == 0 || ps != ___PSTATE) return 0;
  if (index != 0 && (!record || record->owner != ps || record->roots != ptr ||
      (record->kind != ___ACTIVATION_SFUN_ROOTED &&
       record->kind != ___ACTIVATION_SFUN_ACTIVE))) return 0;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d == 0 || d != ps->mem.rc_domain_) return 0;
  ___RC_LOCK(d);
  if (!root_writer_open(ps) || h->refcount <= 0 || index > h->root_count ||
      (index == 0 ? (h->root_borrows != 0 && h->data != value)
                  : h->root_borrows != 1))
    { ___RC_UNLOCK(d); return 0; }
  /* A borrowed cell may be relocated by the collector, not rebound by a
   * mutator. An idempotent admission performs no racing same-value store. */
  cell=index==0 ? &h->data : ___CAST(___SCMOBJ*,ptr)+index-1;
  if (*cell != value) *cell=value;
  ___RC_UNLOCK(d);
  return 1;
}

/* Raw root access cannot infer an activation from a borrow count. Only the
 * generated SFUN entry supplies its live record for a positive span index.
 * Colocation keeps one policy and avoids an inter-unit forwarding call. */
___BOOL ___store_rc_root(___processor_state ps, void *ptr,
                        ___SIZE_T index, ___SCMOBJ value)
{
  return store_rc_root(ps,ptr,index,value,0);
}

___EXP_FUNC(___SCMOBJ,___sfun_arg)
   ___P((___processor_state ps, void *scope, ___WORD index,
         ___SCMOBJ value), ())
{
  ___activation_record *record=___CAST(___activation_record*,scope);
  if (!record || index<1) return ___FIX(___UNKNOWN_ERR);
  return ___FIX(store_rc_root(ps,record->roots,___CAST(___SIZE_T,index),value,record)
               ? ___NO_ERR : ___UNKNOWN_ERR);
}

___BOOL ___try_set_data_rc(___processor_state ps, void *ptr, ___SCMOBJ value)
{
  return ___store_rc_root(ps,ptr,0,value);
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
  if (!root_writer_open(ps) || h->refcount <= 0 ||
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

/* Both operands are non-negative and the sum fits in a signed ___WORD.
 * The comparison is against the signed maximum, not (___UWORD)-1. Failure
 * writes nothing. */
___BOOL ___rest_signed_sum(___WORD a, ___WORD b, ___WORD *sum)
{
  ___WORD word_max=(___WORD)((~(___UWORD)0)>>1);
  if (sum==0 || a<0 || b<0 || a>word_max-b) return 0;
  *sum=a+b;
  return 1;
}

/* Ordinary rest is the same formula with nb_key=0 and j=0:
 * np = nb_req_opt+nb_key+1, n = nb_req_opt+j+i, root_count = n+nb_key+2.
 * Every addition goes through ___rest_signed_sum before a pointer is formed. */
static ___BOOL rest_counts(___WORD np, ___WORD nb_req_opt, ___WORD nb_key,
                           ___WORD j, ___WORD i, ___WORD n, ___WORD *root_count)
{
  ___WORD formals, with_rest, staged, expected, keyed, count;
  if (np<0 || nb_req_opt<0 || nb_key<0 || j<0 || i<0 || n<0) return 0;
  if (!___rest_signed_sum(nb_req_opt, nb_key, &formals)) return 0;
  if (!___rest_signed_sum(formals, 1, &with_rest) || with_rest!=np) return 0;
  if (!___rest_signed_sum(nb_req_opt, j, &staged)) return 0;
  if (!___rest_signed_sum(staged, i, &expected) || expected!=n) return 0;
  if (!___rest_signed_sum(n, nb_key, &keyed)) return 0;
  if (!___rest_signed_sum(keyed, 2, &count)) return 0;
  *root_count=count;
  return 1;
}

static ___BOOL rest_request_ok(const ___rest_span_request *request,
                               ___WORD *root_count)
{
  if (!request || !root_count || !___FIXNUMP(request->attempt)) return 0;
  if (request->keyword!=0 && request->keyword!=1) return 0;
  if (request->keyword==0 && (request->nb_key!=0 || request->j!=0)) return 0;
  if (request->n>0 && request->window==0) return 0;
  if (request->nb_key>0 && request->key_vals==0) return 0;
  return rest_counts(request->np, request->nb_req_opt, request->nb_key,
                     request->j, request->i, request->n, root_count);
}

static ___BOOL rest_same_request(___activation_record *record,
                                 const ___rest_span_request *request)
{
  return record->rest_attempt==request->attempt &&
    record->rest_n==request->n && record->rest_nb_key==request->nb_key &&
    record->rest_j==request->j && record->rest_i==request->i &&
    record->rest_np==request->np &&
    record->rest_nb_req_opt==request->nb_req_opt &&
    record->rest_keyword==request->keyword;
}

static int rest_slot_watch;
___WORD ___rest_slot_n;
___WORD ___rest_slot_fill0;
___WORD ___rest_slot_fill1;
___WORD ___rest_slot_fill2;
___WORD ___rest_slot_fill3;
___WORD ___rest_slot_load0;
___WORD ___rest_slot_load1;
___WORD ___rest_slot_load2;
___WORD ___rest_slot_load3;

void ___rest_arm_slot_watch(void)
{
  rest_slot_watch=1;
}

static void rest_fill_span(___SCMOBJ *slot, const ___rest_span_request *request)
{
  ___WORD u, k;
  slot[0]=request->rest_list;
  for (u=0; u<request->n; u++) slot[1+u]=request->window[u];
  for (k=0; k<request->nb_key; k++) slot[request->n+1+k]=request->key_vals[k];
  slot[request->n+request->nb_key+1]=___FAL;
  if (rest_slot_watch && request->n>0) {
    ___rest_slot_n=request->n;
    ___rest_slot_fill0=request->n>0?slot[1]:0;
    ___rest_slot_fill1=request->n>1?slot[2]:0;
    ___rest_slot_fill2=request->n>2?slot[3]:0;
    ___rest_slot_fill3=request->n>3?slot[4]:0;
  }
}

/* Issue one positive generation. 0 stays unused and the counter never wraps,
 * so a recycled activation address cannot present an old epoch again. */
static ___WORD rest_issue_epoch(___processor_state ps)
{
  ___vm_lifecycle *life;
  ___WORD word_max=(___WORD)((~(___UWORD)0)>>1);
  ___WORD old, next, found;
  if (ps==0) return 0;
  life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  if (!life) return 0;
  for (;;) {
    old=___WORD_LOAD_ACQUIRE(&life->rest_epoch_next);
    if (old<0 || old>=word_max) return 0;
    next=old==0 ? 1 : old;
    found=___lifecycle_cas(&life->rest_epoch_next, old, next+1);
    if (found==old) return next;
  }
}

___WORD ___rest_record_field_loads;
___WORD ___rest_fallback_pops;
___WORD ___rest_fallback_pair_writes;
___WORD ___rest_before_collect_pops = -1;
___WORD ___rest_before_collect_writes = -1;
___WORD ___rest_chain_gates;
___WORD ___rest_chain_reads;
___WORD ___rest_chain_ungated;
___WORD ___rest_chain_crossings;
___WORD ___rest_chain_old_pins;
___WORD ___rest_chain_old_reads;
___WORD ___rest_chain_unpins;

#ifdef ___GAMBIT_REST_OBSERVATION
static void rest_observation_emit_parent(unsigned phase, ___WORD *fp,
                                        uint64_t detail, uint64_t round);
#endif

void ___rest_note_before_collect(void)
{
  ___rest_before_collect_pops=___rest_fallback_pops;
  ___rest_before_collect_writes=___rest_fallback_pair_writes;
#ifdef ___GAMBIT_REST_OBSERVATION
  /* The handler has already published the parent fp. Record that entry
   * before this collection moves it. */
  if (___PSTATE && ___PSTATE->context)
    rest_observation_emit_parent(0,___PSTATE->context->fp,rest_observation_form,
      ___COLLECTION(___VMSTATE_FROM_PSTATE(___PSTATE)).epoch);
#endif
}
___WORD ___rest_fallback_vector_writes;
___WORD ___rest_fallback_keyword_adjusts;
___WORD ___rest_fallback_keyword_pushes;
___WORD ___rest_internal_entries;
___WORD ___rest_user_restores;

/* A user continuation may be restored more than once. That count is not a
 * second READY claim and does not change the delivered entry. */
int ___rest_user_continuation_restore(___WORD continuation_identity)
{
  ___WORD word_max=(___WORD)((~(___UWORD)0)>>1);
  if (!continuation_identity || ___rest_user_restores>=word_max) return 0;
  ___rest_user_restores++;
  return 1;
}

static ___BOOL rest_batch_words(___WORD pending, ___WORD np, ___WORD *words)
{
  ___WORD pair_words=(___WORD)(___PAIR_SIZE+___PAIR_BODY);
  ___WORD pairs, payload;
  if (!words || pending<0 || np<0) return 0;
  if (pending!=0 && pair_words>((___WORD)((~(___UWORD)0)>>1))/pending) return 0;
  pairs=pending*pair_words;
  if (!___rest_signed_sum(pairs, np, &payload)) return 0;
  return ___rest_signed_sum(payload, (___WORD)___VECTOR_BODY, words);
}

___WORD ___rest_observation_room(___processor_state ps)
{
  ___WORD *hp, *hard, hard_room;
  if (!ps || !ps->context || !ps->context->hp) return -1;
  hp=ps->context->hp;
  hard=ps->mem.alloc_heap_limit_;
  if (!hard || hp>hard) return -1;
  hard_room=(___WORD)(hard-hp)-(___WORD)___MSECTION_FUDGE;
  if (hard_room<0) return -1;
  return hard_room;
}

___WORD ___rest_observation_settled(___processor_state ps)
{
  ___WORD *hp, *hard, *soft, soft_room, hard_room;
  hard_room=___rest_observation_room(ps);
  if (hard_room<0 || !ps->context) return -1;
  hp=ps->context->hp;
  hard=ps->mem.alloc_heap_limit_;
  soft=ps->heap_limit?ps->heap_limit:hard;
  if (!soft || hp>soft) return -1;
  soft_room=(___WORD)(soft-hp);
  return soft_room==hard_room ? hard_room : -1;
}

___WORD ___rest_observation_demand(___WORD pending, ___WORD np)
{
  ___WORD words;
  if (!rest_batch_words(pending, np, &words)) return -1;
  return words;
}

static ___WORD rest_observation_last_pending;
static ___WORD rest_observation_last_parameters;
static ___WORD rest_observation_last_words;
static ___WORD rest_observation_last_entry_room = -1;
static int rest_observation_last_one_word;
static int rest_observation_last_physical;
static ___VOLATILE ___WORD rest_observation_admission_captured;

___WORD ___rest_observation_last_demand(___WORD *pending, ___WORD *parameters)
{
  if (pending) *pending=rest_observation_last_pending;
  if (parameters) *parameters=rest_observation_last_parameters;
  return rest_observation_last_words;
}

___WORD ___rest_observation_last_entry_room(void)
{
  return rest_observation_last_entry_room;
}

___WORD ___rest_observation_last_decision(void)
{
  return (rest_observation_last_one_word<<1)|rest_observation_last_physical;
}

void ___rest_observation_reset_admission(void)
{
  ___WORD_STORE_RELEASE(&rest_observation_admission_captured, 0);
}

static ___activation_record *rest_slot_record(___rest_directory_slot *slot)
{
  return ___CAST(___activation_record*, ___WORD_LOAD_ACQUIRE(&slot->record));
}

static void rest_slot_set_record(___rest_directory_slot *slot,
                                 ___activation_record *record)
{
  ___WORD_STORE_RELEASE(&slot->record, ___CAST(___WORD, record));
}

static ___WORD rest_slot_incarnation(___rest_directory_slot *slot)
{
  return ___WORD_LOAD_ACQUIRE(&slot->incarnation);
}

static void rest_slot_set_incarnation(___rest_directory_slot *slot,
                                      ___WORD incarnation)
{
  ___WORD_STORE_RELEASE(&slot->incarnation, incarnation);
}

static ___WORD rest_slot_retired(___rest_directory_slot *slot)
{
  return ___WORD_LOAD_ACQUIRE(&slot->retired_generation);
}

static void rest_slot_set_retired(___rest_directory_slot *slot,
                                  ___WORD generation)
{
  ___WORD_STORE_RELEASE(&slot->retired_generation, generation);
}

static ___WORD rest_slot_generation(___rest_directory_slot *slot)
{
  return ___WORD_LOAD_ACQUIRE(&slot->generation);
}

static void rest_slot_set_generation(___rest_directory_slot *slot,
                                     ___WORD generation)
{
  ___WORD_STORE_RELEASE(&slot->generation, generation);
}

/* One settler. A lost CAS leaves the live generation in place. */
static int rest_slot_take_generation(___rest_directory_slot *slot,
                                     ___WORD generation)
{
  return ___lifecycle_cas(&slot->generation, generation, 0) == generation;
}

/* Compare per-domain directory cells only. The activation record is never
 * dereferenced here. Steady-state idle_activation hits chunk 0 slot 0 in O(1). */
static ___rest_directory_slot *rest_directory_find(___rc_domain *d,
                                                   ___activation_record *record)
{
  ___rest_directory_chunk *chunk;
  if (!d || !record) return 0;
  for (chunk = d->rest_chunks; chunk != 0; chunk = chunk->next) {
    ___SIZE_T i;
    for (i = 0; i < chunk->capacity; i++)
      if (rest_slot_record(&chunk->slots[i]) == record)
        return &chunk->slots[i];
  }
  return 0;
}

/* Geometrically grow the per-domain chunked slab (4 -> 8 -> 16 -> ...).
 * Appending a new chunk keeps all existing slot pointers address-stable and
 * leaves chunk 0 first in the list for O(1) hot-path lookups. */
static ___rest_directory_chunk *rest_directory_grow(___rc_domain *d)
{
  ___SIZE_T cap, slots_bytes, total_bytes;
  ___rest_directory_chunk *chunk;
  ___rest_directory_chunk **tail = &d->rest_chunks;
  ___SIZE_T last_cap = 0;
  while (*tail != 0) {
    last_cap = (*tail)->capacity;
    tail = &(*tail)->next;
  }
  if (last_cap == 0)
    cap = 4;
  else if (last_cap <= ((~___CAST(___SIZE_T, 0)) >> 1))
    cap = last_cap << 1;
  else
    return 0;
  if (cap > (((~___CAST(___SIZE_T, 0)) - sizeof(___rest_directory_chunk)) /
             sizeof(___rest_directory_slot)) + 1)
    return 0;
  slots_bytes = (cap - 1) * sizeof(___rest_directory_slot);
  total_bytes = sizeof(___rest_directory_chunk) + slots_bytes;
  chunk = ___CAST(___rest_directory_chunk*, ___ALLOC_MEM(total_bytes));
  if (!chunk) return 0;
  memset(chunk, 0, total_bytes);
  chunk->capacity = cap;
  chunk->next = 0;
  *tail = chunk;
  d->rest_total_slots += cap;
  return chunk;
}

static ___rest_directory_slot *rest_directory_claim(___processor_state ps,
                                                    ___activation_record *record,
                                                    ___WORD generation)
{
  ___virtual_machine_state vm;
  ___vm_lifecycle *life;
  ___rc_domain *d;
  ___rest_directory_slot *slot;
  ___rest_directory_chunk *chunk;
  if (!ps || ps != ___PSTATE || !record || generation <= 0) return 0;
  d = ps->mem.rc_domain_;
  vm = ___VMSTATE_FROM_PSTATE(ps);
  life = vm ? vm->lifecycle : 0;
  if (!d || !life) return 0;

  /* 1. Reuse existing FREE slot already keyed by this record (O(1) hit for
   *    idle_activation; preserves retired_generation receipt for same key). */
  slot = rest_directory_find(d, record);
  if (slot != 0) {
    ___WORD state = ___WORD_LOAD_ACQUIRE(&slot->state);
    if (___REST_ST_PHASE(state) != ___REST_PHASE_FREE) return 0;
    if (___lifecycle_cas(&slot->state, state,
                         ___REST_ST_MAKE(0, ___REST_PHASE_PUBLISHING)) != state)
      return 0;
    rest_slot_set_incarnation(slot, life->incarnation);
    rest_slot_set_generation(slot, generation);
    return slot;
  }

  /* 2. Prefer a never-used FREE slot (record == 0) so recently retired
   *    address receipts remain intact without eviction. */
  for (chunk = d->rest_chunks; chunk != 0; chunk = chunk->next) {
    ___SIZE_T i;
    for (i = 0; i < chunk->capacity; i++) {
      ___WORD state;
      slot = &chunk->slots[i];
      if (rest_slot_record(slot) != 0) continue;
      state = ___WORD_LOAD_ACQUIRE(&slot->state);
      if (___REST_ST_PHASE(state) == ___REST_PHASE_FREE &&
          ___lifecycle_cas(&slot->state, state,
                           ___REST_ST_MAKE(0, ___REST_PHASE_PUBLISHING)) == state) {
        rest_slot_set_record(slot, record);
        rest_slot_set_incarnation(slot, life->incarnation);
        rest_slot_set_retired(slot, 0);
        rest_slot_set_generation(slot, generation);
        return slot;
      }
    }
  }

  /* 3. Reuse a drained FREE slot via round-robin cursor if available
   *    (bounds slab size across sequential allocations with distinct malloc
   *    addresses while preserving the most recent retired receipts). */
  if (d->rest_total_slots > 0) {
    ___SIZE_T total = d->rest_total_slots;
    ___SIZE_T start = d->rest_evict_cursor % total;
    ___SIZE_T step;
    for (step = 0; step < total; step++) {
      ___SIZE_T target = (start + step) % total;
      ___SIZE_T offset = target;
      slot = 0;
      for (chunk = d->rest_chunks; chunk != 0; chunk = chunk->next) {
        if (offset < chunk->capacity) {
          slot = &chunk->slots[offset];
          break;
        }
        offset -= chunk->capacity;
      }
      if (slot != 0) {
        ___WORD state = ___WORD_LOAD_ACQUIRE(&slot->state);
        if (___REST_ST_PHASE(state) == ___REST_PHASE_FREE &&
            ___lifecycle_cas(&slot->state, state,
                             ___REST_ST_MAKE(0, ___REST_PHASE_PUBLISHING)) == state) {
          d->rest_evict_cursor = (target + 1) % total;
          rest_slot_set_record(slot, record);
          rest_slot_set_incarnation(slot, life->incarnation);
          rest_slot_set_retired(slot, 0);
          rest_slot_set_generation(slot, generation);
          return slot;
        }
      }
    }
  }

  /* 4. All existing slots are live (or first activation on this domain):
   *    grow the per-domain slab dynamically with zero compile-time cap. */
  chunk = rest_directory_grow(d);
  if (!chunk) return 0;
  slot = &chunk->slots[0];
  if (___lifecycle_cas(&slot->state, ___REST_ST_MAKE(0, ___REST_PHASE_FREE),
                       ___REST_ST_MAKE(0, ___REST_PHASE_PUBLISHING)) !=
      ___REST_ST_MAKE(0, ___REST_PHASE_FREE))
    return 0;
  rest_slot_set_record(slot, record);
  rest_slot_set_incarnation(slot, life->incarnation);
  rest_slot_set_retired(slot, 0);
  rest_slot_set_generation(slot, generation);
  return slot;
}

static void rest_directory_retire(___processor_state ps,
                                  ___rest_directory_slot *slot,
                                  ___WORD generation)
{
  ___activation_record *record;
  ___WORD state;
  (void)ps;
  if (!slot) return;
  state = ___WORD_LOAD_ACQUIRE(&slot->state);
  if (rest_slot_generation(slot) != generation) return;
  if (___REST_ST_PIN(state) || ___REST_ST_PHASE(state) != ___REST_PHASE_CLOSED)
    return;
  /* Own the generation before any metadata write. FREE is the last store. */
  if (!rest_slot_take_generation(slot, generation)) return;
  record = rest_slot_record(slot);
  rest_slot_set_retired(slot, generation);
  if (record) {
    record->kind = ___ACTIVATION_LEGACY;
    ___lifecycle_marker_abort(record);
  }
  /* Keep the address as an equality key. Do not load it after abort. */
  rest_slot_set_record(slot, record);
  if (___lifecycle_cas(&slot->state, state,
                       ___REST_ST_MAKE(0, ___REST_PHASE_FREE)) != state)
    return;
}

static void rest_directory_cancel(___processor_state ps,
                                  ___rest_directory_slot *slot,
                                  ___WORD generation)
{
  ___WORD state, swapped;
  (void)ps;
  if (!slot) return;
  state = ___WORD_LOAD_ACQUIRE(&slot->state);
  if (rest_slot_generation(slot) != generation || ___REST_ST_PIN(state) ||
      ___REST_ST_PHASE(state) != ___REST_PHASE_PUBLISHING) return;
  if (!rest_slot_take_generation(slot, generation)) return;
  rest_slot_set_retired(slot, generation);
  for (;;) {
    state = ___WORD_LOAD_ACQUIRE(&slot->state);
    if (___REST_ST_PHASE(state) == ___REST_PHASE_FREE) return;
    if (___REST_ST_PIN(state) ||
        ___REST_ST_PHASE(state) != ___REST_PHASE_PUBLISHING) return;
    swapped = ___lifecycle_cas(&slot->state, state,
                               ___REST_ST_MAKE(0, ___REST_PHASE_FREE));
    if (swapped == state) return;
  }
}

/* Claim a stable per-domain slot, then publish OPEN. Callers may load the
 * record only after this returns a non-null slot. */
static ___rest_directory_slot *rest_directory_open_slot(___processor_state ps,
                                                        ___activation_record *record,
                                                        ___WORD generation)
{
  ___rest_directory_slot *slot;
  ___WORD state, swapped;
  slot = rest_directory_claim(ps, record, generation);
  if (!slot) return 0;
  state = ___WORD_LOAD_ACQUIRE(&slot->state);
  if (rest_slot_generation(slot) == generation && !___REST_ST_PIN(state) &&
      ___REST_ST_PHASE(state) == ___REST_PHASE_PUBLISHING) {
    swapped = ___lifecycle_cas(&slot->state, state,
                               ___REST_ST_MAKE(0, ___REST_PHASE_OPEN));
    if (swapped == state) return slot;
  }
  /* Leave PUBLISHING in place. The caller settles the record, then cancels. */
  return 0;
}

/* Pin CAS first. Mismatched generation, close, and a second reader return
 * without loading an activation field. */
static int rest_reuse_before_cas;
static int rest_close_while_pinned;
static int rest_force_slow;
___WORD ___rest_ready_claims;
___WORD ___rest_resume_reloads;
___WORD ___rest_resume_collections;

static enum ___rest_status rest_admit(___processor_state ps,
                                      ___activation_record *record,
                                      ___WORD generation,
                                      ___rest_directory_slot **slot_out)
{
  ___vm_lifecycle *life;
  ___rc_domain *d;
  ___rest_directory_slot *found;
  ___WORD state, swapped;
  if (slot_out) *slot_out = 0;
  if (!ps || ps != ___PSTATE || !record || generation <= 0) return ___REST_REFUSED;
  d = ps->mem.rc_domain_;
  life = ___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  if (!d || !life) return ___REST_REFUSED;
  found = rest_directory_find(d, record);
  if (!found || rest_slot_incarnation(found) != life->incarnation)
    return ___REST_REFUSED;
  for (;;) {
    state = ___WORD_LOAD_ACQUIRE(&found->state);
    if (rest_slot_generation(found) != generation) {
      if (generation == rest_slot_retired(found))
        return ___REST_DUPLICATE;
      if (___REST_ST_PHASE(state) == ___REST_PHASE_OPEN) return ___REST_LOST;
      return ___REST_UNKNOWN;
    }
    if (___REST_ST_PHASE(state) == ___REST_PHASE_PUBLISHING) return ___REST_LOST;
    if (___REST_ST_PHASE(state) == ___REST_PHASE_CLOSED) return ___REST_REFUSED;
    if (___REST_ST_PHASE(state) != ___REST_PHASE_OPEN) return ___REST_UNKNOWN;
    if (___REST_ST_PIN(state)) return ___REST_RETRY;
    /* Test-only pause. A publisher reuses the slot, still unpinned OPEN,
     * before this CAS. Production leaves the flag clear. */
    if (rest_reuse_before_cas) {
      rest_reuse_before_cas = 0;
      rest_slot_set_generation(found, generation + 1);
    }
    swapped = ___lifecycle_cas(&found->state, state,
                               ___REST_ST_MAKE(1, ___REST_PHASE_OPEN));
    if (swapped == state) {
      /* Close can move OPEN+pin to CLOSED+pin before this re-read.
       * Either a new generation or a phase that is no longer OPEN drops
       * the pin. The activation record is not loaded. */
      if (rest_close_while_pinned) {
        rest_close_while_pinned = 0;
        ___lifecycle_cas(&found->state,
                         ___REST_ST_MAKE(1, ___REST_PHASE_OPEN),
                         ___REST_ST_MAKE(1, ___REST_PHASE_CLOSED));
      }
      if (rest_slot_generation(found) != generation ||
          ___REST_ST_PHASE(___WORD_LOAD_ACQUIRE(&found->state)) != ___REST_PHASE_OPEN) {
        for (;;) {
          ___WORD pinned = ___WORD_LOAD_ACQUIRE(&found->state);
          ___WORD now = rest_slot_generation(found);
          if (!___REST_ST_PIN(pinned)) break;
          if (___lifecycle_cas(&found->state, pinned,
                               ___REST_ST_MAKE(0, ___REST_ST_PHASE(pinned))) == pinned) {
            /* Close may have moved OPEN+pin to CLOSED+pin. Dropping the
             * last pin retires that generation; an OPEN occupant stays. */
            if (___REST_ST_PHASE(pinned) == ___REST_PHASE_CLOSED)
              rest_directory_retire(ps, found, now);
            break;
          }
        }
        return ___REST_LOST;
      }
      break;
    }
  }
  if (slot_out) *slot_out = found;
  return ___REST_OK;
}

static void rest_unpin(___processor_state ps,
                       ___rest_directory_slot *slot,
                       ___WORD generation)
{
  ___WORD state, swapped;
  if (!ps || !slot) return;
  for (;;) {
    state = ___WORD_LOAD_ACQUIRE(&slot->state);
    if (rest_slot_generation(slot) != generation || !___REST_ST_PIN(state)) return;
    swapped = ___lifecycle_cas(&slot->state, state,
                               ___REST_ST_MAKE(0, ___REST_ST_PHASE(state)));
    if (swapped == state) {
      if (___REST_ST_PHASE(state) == ___REST_PHASE_CLOSED)
        rest_directory_retire(ps, slot, generation);
      return;
    }
  }
}

enum ___rest_status ___rest_token_pin(___processor_state ps,
                                      ___activation_record *record,
                                      ___WORD generation)
{
  ___rest_directory_slot *dir_slot = 0;
  enum ___rest_status status = rest_admit(ps, record, generation, &dir_slot);
  if (status != ___REST_OK) return status;
  return ___REST_OK;
}

enum ___rest_status ___rest_token_release(___processor_state ps,
                                          ___activation_record *record,
                                          ___WORD generation)
{
  ___rest_directory_slot *dir_slot;
  if (!ps || ps != ___PSTATE || !ps->mem.rc_domain_) return ___REST_REFUSED;
  dir_slot = rest_directory_find(ps->mem.rc_domain_, record);
  if (!dir_slot) return ___REST_REFUSED;
  rest_unpin(ps, dir_slot, generation);
  return ___REST_OK;
}

enum ___rest_status ___rest_token_close(___processor_state ps,
                                        ___activation_record *record,
                                        ___WORD generation)
{
  ___vm_lifecycle *life;
  ___rest_directory_slot *dir_slot;
  ___WORD state, swapped;
  if (!ps || ps != ___PSTATE || !ps->mem.rc_domain_ || !record || generation <= 0)
    return ___REST_REFUSED;
  life = ___VMSTATE_FROM_PSTATE(ps)->lifecycle;
  dir_slot = rest_directory_find(ps->mem.rc_domain_, record);
  if (!dir_slot || !life || rest_slot_incarnation(dir_slot) != life->incarnation)
    return ___REST_REFUSED;
  for (;;) {
    state = ___WORD_LOAD_ACQUIRE(&dir_slot->state);
    if (rest_slot_generation(dir_slot) != generation ||
        ___REST_ST_PHASE(state) != ___REST_PHASE_OPEN) return ___REST_REFUSED;
    swapped = ___lifecycle_cas(&dir_slot->state, state,
                               ___REST_ST_MAKE(___REST_ST_PIN(state),
                                               ___REST_PHASE_CLOSED));
    if (swapped == state) break;
  }
  if (!___REST_ST_PIN(___WORD_LOAD_ACQUIRE(&dir_slot->state)))
    rest_directory_retire(ps, dir_slot, generation);
  return ___REST_OK;
}

/* The address is not the attempt. Callers must already hold the pin.
 * The first statement counts the field load so a refused lookup can prove
 * it never got here. */
static enum ___rest_status rest_prove(___processor_state ps,
                                      ___activation_record *record,
                                      ___WORD attempt, ___WORD epoch)
{
  ___rest_record_field_loads++;
  if (!record || ps==0 || ps!=___PSTATE || epoch<=0 || !___FIXNUMP(attempt))
    return ___REST_REFUSED;
  if (record->rest_retired_epoch==epoch && record->rest_epoch!=epoch)
    return ___REST_DUPLICATE;
  if (record->owner!=ps || record->kind!=___ACTIVATION_REST)
    return (record->kind==___ACTIVATION_IDLE || record->owner==0)
      ? ___REST_UNKNOWN : ___REST_REFUSED;
  if (record->rest_context!=ps->context ||
      record->rest_attempt!=attempt || record->rest_epoch!=epoch)
    return ___REST_LOST;
  return ___REST_OK;
}

static enum ___rest_status rest_with_pin(___processor_state ps,
                                         ___activation_record *record,
                                         ___WORD attempt, ___WORD epoch,
                                         ___rest_directory_slot **slot_out)
{
  enum ___rest_status status = rest_admit(ps, record, epoch, slot_out);
  if (status != ___REST_OK) return status;
  status = rest_prove(ps, record, attempt, epoch);
  if (status != ___REST_OK) rest_unpin(ps, *slot_out, epoch);
  return status;
}

___activation_record *___rest_activation_open(___processor_state ps,
                                             const ___rest_span_request *request)
{
  ___WORD root_count, epoch;
  ___activation_record *record;
  if (!rest_request_ok(request, &root_count) || ps==0 || ps!=___PSTATE ||
      ps->context==0) return 0;
  record=___lifecycle_marker_prepare(ps);
  if (!record) return 0;
  epoch=rest_issue_epoch(ps);
  if (epoch==0) { ___lifecycle_marker_abort(record); return 0; }
  record->kind=___ACTIVATION_REST;
  record->marker=___FAL;
  record->roots=0;
  record->rest_attempt=request->attempt;
  record->rest_n=request->n;
  record->rest_nb_key=request->nb_key;
  record->rest_j=request->j;
  record->rest_i=request->i;
  record->rest_np=request->np;
  record->rest_nb_req_opt=request->nb_req_opt;
  record->rest_keyword=request->keyword;
  record->rest_phase=___REST_PUBLISHING;
  record->rest_context=ps->context;
  record->rest_epoch=epoch;
  (void)root_count;
  if (!rest_directory_open_slot(ps, record, epoch)) {
    ___rest_directory_slot *dir_slot =
      ps->mem.rc_domain_ ? rest_directory_find(ps->mem.rc_domain_, record) : 0;
    ___lifecycle_marker_abort(record);
    if (dir_slot) rest_directory_cancel(ps, dir_slot, epoch);
    return 0;
  }
  return record;
}

enum ___rest_status ___rest_span_publish(___processor_state ps,
                                        ___activation_record *record,
                                        const ___rest_span_request *request,
                                        ___WORD epoch)
{
  ___WORD root_count;
  void *ptr;
  ___rc_header *h;
  ___rc_domain *d;
  enum ___rest_status proof;
  ___rest_directory_slot *dir_slot=0;
  if (!request) return ___REST_REFUSED;
  proof=rest_with_pin(ps, record, request->attempt, epoch, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (record->rest_context!=ps->context ||
      !rest_request_ok(request, &root_count) ||
      !rest_same_request(record, request) ||
      record->rest_epoch!=epoch) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_REFUSED;
  }
  if (record->rest_phase==___REST_INSTALLED ||
      record->rest_phase==___REST_READY) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_DUPLICATE;
  }
  if (record->rest_phase!=___REST_PUBLISHING || record->roots!=0) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  /* Native metadata only. A short or failed allocation does not collect and
   * does not call fatal_heap_overflow. The caller arrays stay in place. */
  ptr=___alloc_rc_roots(ps, ___CAST(___SIZE_T, root_count));
  if (!ptr) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_REFUSED;
  }
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  ___RC_LOCK(d);
  if (!root_writer_open(ps) || d!=ps->mem.rc_domain_ || h->refcount<=0 ||
      h->root_borrows!=0 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_phase!=___REST_PUBLISHING || record->roots!=0 ||
      record->rest_attempt!=request->attempt ||
      record->rest_epoch!=epoch ||
      d->borrows==~___CAST(___SIZE_T,0)) {
    ___RC_UNLOCK(d);
    ___release_rc(ptr);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  h->data=request->label;
  rest_fill_span(___CAST(___SCMOBJ*,ptr), request);
  ++h->root_borrows; ++d->borrows;
  record->roots=ptr;
  record->rest_phase=___REST_INSTALLED;
  REST_OBS(REST_ROOTS,ps,record,request->attempt,epoch,
           ptr,root_count,request->n,request->nb_key,h->data,&h->data,
           ps->mem.rc_domain_,ps->context);
#ifdef ___GAMBIT_REST_OBSERVATION
  ___rest_observation_watch_roots(ptr, (uint64_t)root_count);
  {
    ___WORD observed_root;
    for (observed_root=0;observed_root<root_count;observed_root++)
      REST_OBS(REST_ROOT_VALUE,ps,record,request->attempt,epoch,
        observed_root,___CAST(___SCMOBJ*,ptr)[observed_root],0,0,0,0,0,0);
  }
#endif
  ___RC_UNLOCK(d);
  rest_unpin(ps, dir_slot, epoch);
  return ___REST_OK;
}

static ___BOOL rest_view_open(___processor_state ps, ___activation_record *record,
                              ___WORD attempt, ___WORD epoch, ___WORD *root_count)
{
  /* Caller holds the directory pin. This load is not an admission. */
  if (rest_prove(ps, record, attempt, epoch)!=___REST_OK) return 0;
  if (record->rest_attempt!=attempt || record->rest_epoch!=epoch ||
      record->rest_context!=ps->context) return 0;
  if ((record->rest_phase!=___REST_INSTALLED &&
       record->rest_phase!=___REST_READY) || record->roots==0) return 0;
  return rest_counts(record->rest_np, record->rest_nb_req_opt,
                     record->rest_nb_key, record->rest_j, record->rest_i,
                     record->rest_n, root_count);
}

enum ___rest_status ___rest_span_query(___processor_state ps,
                                       ___activation_record *record,
                                       ___WORD attempt, ___WORD epoch,
                                       ___SCMOBJ *label, ___SCMOBJ *rest_list,
                                       ___SCMOBJ *result)
{
  ___WORD root_count;
  ___rc_header *h;
  ___rc_domain *d;
  ___SCMOBJ *slot;
  ___rest_directory_slot *dir_slot=0;
  enum ___rest_status proof=rest_with_pin(ps, record, attempt, epoch, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (record->rest_phase!=___REST_INSTALLED &&
      record->rest_phase!=___REST_READY) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  if (!rest_view_open(ps, record, attempt, epoch, &root_count)) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  h=___CAST(___rc_header*,record->roots)-1; d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || !root_writer_open(ps) || h->refcount<=0 ||
      h->root_borrows!=1 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_epoch!=epoch ||
      (record->rest_phase!=___REST_INSTALLED &&
       record->rest_phase!=___REST_READY)) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  slot=___CAST(___SCMOBJ*,record->roots);
  if (label) *label=h->data;
  if (rest_list) *rest_list=slot[0];
  if (result) *result=slot[root_count-1];
  ___RC_UNLOCK(d);
  rest_unpin(ps, dir_slot, epoch);
  return ___REST_OK;
}

enum ___rest_status ___rest_span_reload(___processor_state ps,
                                        ___activation_record *record,
                                        ___WORD attempt, ___WORD epoch,
                                        ___SCMOBJ *window, ___WORD window_n,
                                        ___SCMOBJ *key_vals, ___WORD key_n)
{
  ___WORD root_count, u, k;
  ___rc_header *h;
  ___rc_domain *d;
  ___SCMOBJ *slot;
  ___rest_directory_slot *dir_slot=0;
  enum ___rest_status proof=rest_with_pin(ps, record, attempt, epoch, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (window_n!=record->rest_n || key_n!=record->rest_nb_key) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_REFUSED;
  }
  if ((window_n>0 && window==0) || (key_n>0 && key_vals==0)) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_REFUSED;
  }
  if (!rest_view_open(ps, record, attempt, epoch, &root_count)) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  h=___CAST(___rc_header*,record->roots)-1; d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || !root_writer_open(ps) || h->refcount<=0 ||
      h->root_borrows!=1 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_epoch!=epoch ||
      (record->rest_phase!=___REST_INSTALLED &&
       record->rest_phase!=___REST_READY)) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  slot=___CAST(___SCMOBJ*,record->roots);
  if (rest_slot_watch && record->rest_n>0) {
    ___rest_slot_n=record->rest_n;
    ___rest_slot_load0=record->rest_n>0?slot[1]:0;
    ___rest_slot_load1=record->rest_n>1?slot[2]:0;
    ___rest_slot_load2=record->rest_n>2?slot[3]:0;
    ___rest_slot_load3=record->rest_n>3?slot[4]:0;
    rest_slot_watch=0;
  }
  for (u=0; u<record->rest_n; u++) window[u]=slot[1+u];
  for (k=0; k<record->rest_nb_key; k++) key_vals[k]=slot[record->rest_n+1+k];
  REST_OBS(REST_RELOAD,ps,record,attempt,epoch,
           window,window_n,key_vals,key_n,root_count,h->data,0,0);
#ifdef ___GAMBIT_REST_OBSERVATION
  for (u=0;u<root_count;u++)
    REST_OBS(REST_ROOT_VALUE,ps,record,attempt,epoch,
             u,slot[u],1,0,0,0,0,0);
#endif
  ___RC_UNLOCK(d);
  rest_unpin(ps, dir_slot, epoch);
  return ___REST_OK;
}

enum ___rest_status ___rest_claim_ready(___processor_state ps,
                                        ___activation_record *record,
                                        ___WORD attempt, ___WORD epoch,
                                        ___SCMOBJ vector)
{
  ___WORD root_count;
  ___rc_header *h;
  ___rc_domain *d;
  ___rest_directory_slot *dir_slot=0;
  enum ___rest_status proof=rest_with_pin(ps, record, attempt, epoch, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (!rest_view_open(ps, record, attempt, epoch, &root_count)) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  h=___CAST(___rc_header*,record->roots)-1; d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || !root_writer_open(ps) || h->refcount<=0 ||
      h->root_borrows!=1 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_epoch!=epoch) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  if (record->rest_phase==___REST_READY) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_DUPLICATE;
  }
  if (record->rest_phase!=___REST_INSTALLED) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  ___CAST(___SCMOBJ*,record->roots)[root_count-1]=vector;
  record->rest_phase=___REST_READY;
  ___rest_ready_claims++;
  REST_OBS(REST_READY,ps,record,attempt,epoch,vector,0,0,0,0,0,0,0);
#ifdef ___GAMBIT_REST_OBSERVATION
  rest_observation_ready_result=(uint64_t)vector;
  rest_observation_ready_label=(uint64_t)h->data;
#endif
  ___RC_UNLOCK(d);
  rest_unpin(ps, dir_slot, epoch);
  return ___REST_OK;
}

enum ___rest_status ___rest_activation_cleanup(___processor_state ps,
                                              ___activation_record *record,
                                              ___WORD attempt, ___WORD epoch)
{
  ___rest_directory_slot *dir_slot=0;
  enum ___rest_status proof=rest_with_pin(ps, record, attempt, epoch, &dir_slot);
  enum ___rest_status closed;
  /* Settled, unknown and lost proofs must not reach marker abort. Abort
   * runs from directory retirement, after the generation has advanced and
   * only when this pin is the last one. */
  if (proof!=___REST_OK) return proof;
  record->rest_retired_epoch=epoch;
  closed=___rest_token_close(ps, record, epoch);
  rest_unpin(ps, dir_slot, epoch);
  return closed==___REST_OK ? ___REST_OK : closed;
}

static ___BOOL rest_fast_words(___WORD pending, ___WORD *words)
{
  ___WORD pair_words=(___WORD)(___PAIR_SIZE+___PAIR_BODY);
  if (!words || pending<0) return 0;
  if (pending!=0 && pair_words>((___WORD)((~(___UWORD)0)>>1))/pending) return 0;
  *words=pending*pair_words;
  return 1;
}

#include "_mem/section-claim.inc"
#include "collector.h"

___HIDDEN int ___owned_stack_span(___processor_state ps, ___WORD **lo, ___WORD **hi)
{
  ___msection *ms;
  section_claim *claim;
  ___WORD *limit, *start, *half, *half_past;
  ___SIZE_TS off;
  int owned;
  if (!ps || !lo || !hi) return 0;
  ms=ps->mem.stack_msection_;
  if (!ms) return 0;
  off=ps->mem.tospace_offset_;
  if (off!=0 && off!=(___MSECTION_SIZE>>1)) return 0;
  claim=section_claim_at(ms, off);
  /* Same gate set_stack_msection holds while it publishes the owner. */
  ___gc_copy_acquire(&ms->copy_gate);
  owned=claim->stack_owner==ps && claim->stack_state==STACK_ACTIVE;
  limit=ps->mem.alloc_stack_limit_;
  start=ps->mem.alloc_stack_start_;
  ___gc_copy_release(&ms->copy_gate);
  if (!owned) return 0;
  half=ms->base+off;
  half_past=half+(___MSECTION_SIZE>>1);
  if (!limit || !start || limit<half || start>half_past || start<=limit)
    return 0;
  *lo=limit;
  *hi=start;
  return 1;
}

#ifdef ___GAMBIT_REST_OBSERVATION
static void rest_observation_emit_parent(unsigned phase, ___WORD *fp,
                                        uint64_t detail, uint64_t round)
{
  ___processor_state ps=___PSTATE;
  ___WORD *lo, *hi;
  int owned;
  if (!rest_observation_chain_attempt || !rest_observation_chain_record ||
      !ps || !ps->context || !fp) return;
  owned=___owned_stack_span(ps,&lo,&hi) && fp>=lo && fp<=hi;
  REST_OBS(REST_PARENT,ps,rest_observation_chain_record,rest_observation_protocol_attempt,
           rest_observation_chain_attempt,
           phase,ps->context,fp,ps->mem.stack_msection_,owned?ps:0,
           ps->mem.tospace_offset_,detail,round);
  if (phase==2) rest_observation_restored_fp=fp;
}

static void rest_observation_native_cut(___processor_state ps, ___WORD *hp,
                                       ___WORD *fp, unsigned phase,
                                       unsigned kind, ___WORD cursor)
{
  ___WORD *lo, *hi, *heap_lo, *heap_hi;
  uintptr_t bases[3];
  uint64_t lengths[3];
  int i;
  if (!rest_observation_map || !rest_observation_current_case() ||
      rest_observation_watch_case!=rest_observation_current_case() ||
      rest_observation_watch_state!=phase+1 || ps!=___PSTATE ||
      !___owned_stack_span(ps,&lo,&hi) || !fp || fp<lo || fp>hi ||
      rest_observation_argument_words>(uint64_t)(hi-fp)) return;
  heap_lo=ps->mem.alloc_heap_start_; heap_hi=ps->mem.alloc_heap_limit_;
  if (!heap_lo || !heap_hi || heap_lo>heap_hi || !hp || hp<heap_lo || hp>heap_hi) return;
  bases[0]=(uintptr_t)heap_lo; bases[1]=(uintptr_t)lo; bases[2]=(uintptr_t)fp;
  lengths[0]=(uint64_t)(heap_hi-heap_lo); lengths[1]=(uint64_t)(hi-lo);
  lengths[2]=rest_observation_argument_words;
  if (phase) {
    /* A relocated or released interval cannot be dereferenced to obtain an
     * after-image of an old address. Keep that premise missing instead. */
    for (i=0;i<2;i++) if (bases[i]!=rest_observation_bases[i] ||
                         lengths[i]!=rest_observation_lengths[i]) return;
    bases[2]=rest_observation_bases[2]; lengths[2]=rest_observation_lengths[2];
  }
  REST_OBS(phase?REST_NATIVE_CUT:REST_NATIVE_BEGIN,ps,0,0,0,
           hp,fp,kind,cursor,rest_observation_handler_form,0,0,0);
  REST_OBS(REST_HEAP_SPAN,ps,0,0,0,heap_lo,ps->heap_limit?ps->heap_limit:heap_hi,hp,heap_hi,phase,0,0,0);
  REST_OBS(REST_STACK_SPAN,ps,0,0,0,lo,hi,fp,ps->mem.stack_msection_,phase,0,0,0);
  REST_OBS(REST_ARGUMENT_SPAN,ps,0,0,0,bases[2],bases[2]+8*lengths[2],fp,phase,0,0,0,0);
  for (i=0;i<3;i++) {
    if (!phase) { rest_observation_bases[i]=bases[i]; rest_observation_lengths[i]=lengths[i]; }
    ___rest_observation_snapshot((uintptr_t)ps,(uint64_t)i+1,phase,(void*)bases[i],lengths[i]);
  }
  rest_observation_watch_state=phase?0:2;
}

void ___rest_observation_form(unsigned form)
{
  if (__builtin_expect(!__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE), 1))
    return;
  rest_observation_handler_form=form;
  rest_observation_form=form;
}

void ___rest_observation_exact_granted(___processor_state ps, ___WORD *hp, ___WORD *fp)
{
  /* The pair stores sit between the opening snapshot and this cut. */
  if (rest_observation_auto_watch==2 &&
      rest_observation_watch_state==2 &&
      rest_observation_watch_case==rest_observation_current_case())
    rest_observation_native_cut(ps,hp,fp,1,0,0);
}
#endif

static ___BOOL rest_interval_fits(___processor_state ps, ___WORD *hp, ___WORD *fp,
                                 ___WORD words, ___WORD stack_slots)
{
  ___WORD *start, *end, *lo, *hi;
  if (!ps || ps!=___PSTATE || !ps->context || !hp || !fp || ps->context->hp!=hp)
    return 0;
  if (words<0 || stack_slots<0) return 0;
  /* Invalid ownership is not a heap shortage. A heap-short return would
   * send the caller into the rest root-window copy. Refuse first. */
  if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) {
    REST_OBS(REST_PREFLIGHT,ps,0,0,0,words,stack_slots,0,2,hp,fp,0,0);
    rc_contract_error("Stack cursor is outside the owned interval");
    return 0;
  }
  REST_OBS(REST_STACK_SPAN,ps,0,0,0,lo,hi,fp,ps->mem.stack_msection_,0,0,0,0);
  if (stack_slots!=0 && (___SIZE_TS)(fp-lo)<(___SIZE_TS)stack_slots) {
    REST_OBS(REST_PREFLIGHT,ps,0,0,0,words,stack_slots,0,1,hp,fp,0,0);
    return 0;
  }
  start=ps->mem.alloc_heap_start_;
  /* Soft limit. CHECK_HEAP collects once the cursor passes it. The hard
   * alloc limit is one fudge past that, so a grant against the hard limit
   * writes in the fudge and the next check collects with no rest window. */
  end=ps->heap_limit?ps->heap_limit:ps->mem.alloc_heap_limit_;
  REST_OBS(REST_HEAP_SPAN,ps,0,0,0,start,end,hp,ps->mem.alloc_heap_limit_,0,0,0,0);
  if (!start || !end || hp<start || hp>end) {
    REST_OBS(REST_PREFLIGHT,ps,0,0,0,words,stack_slots,0,2,hp,fp,0,0);
    return 0;
  }
  if ((___SIZE_TS)(end-hp)<(___SIZE_TS)words) {
    REST_OBS(REST_PREFLIGHT,ps,0,0,0,words,stack_slots,0,1,hp,fp,0,0);
    return 0;
  }
  REST_OBS(REST_PREFLIGHT,ps,0,0,0,words,stack_slots,1,0,hp,fp,0,0);
  return 1;
}

___WORD ___rest_grant_cap_words;
___WORD ___rest_grant_cap_floor;
___WORD ___rest_preflight_required;
___WORD ___rest_preflight_effective;
___WORD ___rest_preflight_uncapped;
___WORD ___rest_preflight_cap;
___WORD ___rest_refusal_writes;
___WORD ___rest_refusal_pops;

void ___rest_set_grant_cap(___WORD words, ___WORD floor)
{
  ___rest_grant_cap_words = words > 0 ? words : 0;
  ___rest_grant_cap_floor = floor > 0 ? floor : 0;
}

___WORD ___rest_stale_pin_status;
___WORD ___rest_stale_load_delta;
___WORD ___rest_stale_still_pinned;
___WORD ___rest_stale_incarnation_status;
___WORD ___rest_stale_incarnation_loads;

void ___rest_stale_probe(___processor_state ps)
{
  ___rest_span_request request;
  ___activation_record *record;
  ___WORD epoch, loads;
  enum ___rest_status stale, held, again;
  ___rest_stale_pin_status=-1;
  ___rest_stale_load_delta=-1;
  ___rest_stale_still_pinned=0;
  if (!ps || ps!=___PSTATE || !ps->context) return;
  memset(&request, 0, sizeof request);
  request.attempt=___FIX(1);
  request.np=1;
  request.label=___FAL;
  request.rest_list=___NUL;
  record=___rest_activation_open(ps, &request);
  if (!record) { ___rest_stale_pin_status=-2; return; }
  epoch=record->rest_epoch;
  if (___rest_span_publish(ps, record, &request, epoch)!=___REST_OK) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    ___rest_stale_pin_status=-3;
    return;
  }
  loads=___rest_record_field_loads;
  stale=___rest_token_pin(ps, record, epoch+1);
  ___rest_stale_pin_status=(___WORD)stale;
  ___rest_stale_load_delta=___rest_record_field_loads-loads;
  held=___rest_token_pin(ps, record, epoch);
  if (held==___REST_OK) {
    ___rest_token_release(ps, record, epoch+1);
    again=___rest_token_pin(ps, record, epoch);
    ___rest_stale_still_pinned=again==___REST_RETRY;
    if (again==___REST_OK) ___rest_token_release(ps, record, epoch);
    ___rest_token_release(ps, record, epoch);
  }
  {
    ___vm_lifecycle *life=___VMSTATE_FROM_PSTATE(ps)->lifecycle;
    ___WORD saved=life->incarnation;
    enum ___rest_status wrong;
    ___WORD mark;
    life->incarnation=saved+1;
    mark=___rest_record_field_loads;
    wrong=___rest_token_pin(ps, record, epoch);
    ___rest_stale_incarnation_status=(___WORD)wrong;
    ___rest_stale_incarnation_loads=___rest_record_field_loads-mark;
    life->incarnation=saved;
  }
  ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
}

___WORD ___rest_reuse_status;
___WORD ___rest_reuse_pin;
___WORD ___rest_reuse_loads;
___WORD ___rest_close_status;
___WORD ___rest_close_pin;
___WORD ___rest_close_loads;

static int rest_directory_pin_bit(___processor_state ps, ___activation_record *record)
{
  ___rest_directory_slot *dir_slot;
  ___WORD state;
  if (!ps || !ps->mem.rc_domain_ || !record) return -1;
  dir_slot = rest_directory_find(ps->mem.rc_domain_, record);
  if (!dir_slot) return -1;
  state = ___WORD_LOAD_ACQUIRE(&dir_slot->state);
  return ___REST_ST_PIN(state) ? 1 : 0;
}

void ___rest_reuse_probe(___processor_state ps)
{
  ___rest_span_request request;
  ___activation_record *record;
  ___WORD epoch, loads;
  enum ___rest_status status;
  ___rest_directory_slot *dir_slot;
  ___rest_reuse_status=-1;
  ___rest_reuse_pin=-1;
  ___rest_reuse_loads=-1;
  ___rest_close_status=-1;
  ___rest_close_pin=-1;
  ___rest_close_loads=-1;
  if (!ps || ps!=___PSTATE || !ps->context) return;
  memset(&request, 0, sizeof request);
  request.attempt=___FIX(1);
  request.np=1;
  request.label=___FAL;
  request.rest_list=___NUL;
  record=___rest_activation_open(ps, &request);
  if (!record) return;
  epoch=record->rest_epoch;
  if (___rest_span_publish(ps, record, &request, epoch)!=___REST_OK) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    return;
  }
  loads=___rest_record_field_loads;
  rest_reuse_before_cas=1;
  status=___rest_token_pin(ps, record, epoch);
  ___rest_reuse_status=(___WORD)status;
  ___rest_reuse_pin=rest_directory_pin_bit(ps, record);
  ___rest_reuse_loads=___rest_record_field_loads-loads;
  dir_slot = ps->mem.rc_domain_ ? rest_directory_find(ps->mem.rc_domain_, record) : 0;
  if (dir_slot && rest_slot_generation(dir_slot) == epoch + 1)
    rest_slot_set_generation(dir_slot, epoch);
  ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);

  record=___rest_activation_open(ps, &request);
  if (!record) return;
  epoch=record->rest_epoch;
  if (___rest_span_publish(ps, record, &request, epoch)!=___REST_OK) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    return;
  }
  loads=___rest_record_field_loads;
  rest_close_while_pinned=1;
  status=___rest_token_pin(ps, record, epoch);
  ___rest_close_status=(___WORD)status;
  ___rest_close_pin=rest_directory_pin_bit(ps, record);
  ___rest_close_loads=___rest_record_field_loads-loads;
  ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
}

___WORD ___rest_once_first;
___WORD ___rest_once_second;
___WORD ___rest_once_delta;
___WORD ___rest_once_result;

void ___rest_once_probe(___processor_state ps)
{
  ___rest_span_request request;
  ___activation_record *record;
  ___WORD epoch, before;
  ___WORD *old_hp=0, *new_hp=0;
  ___SCMOBJ entered=___FAL, first_result=___FAL;
  enum ___rest_status ready, first, second;
  ___rest_once_first=-1;
  ___rest_once_second=-1;
  ___rest_once_delta=-1;
  ___rest_once_result=0;
  if (!ps || ps!=___PSTATE || !ps->context) return;
  memset(&request, 0, sizeof request);
  request.attempt=___FIX(1);
  request.np=1;
  request.label=___FAL;
  request.rest_list=___NUL;
  record=___rest_activation_open(ps, &request);
  if (!record) { ___rest_once_first=-2; return; }
  epoch=record->rest_epoch;
  if (___rest_span_publish(ps, record, &request, epoch)!=___REST_OK) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    ___rest_once_first=-3;
    return;
  }
  ready=___rest_claim_ready(ps, record, ___FIX(1), epoch, ___FIX(7));
  if (ready!=___REST_OK) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    ___rest_once_first=-4;
    return;
  }
  before=___rest_internal_entries;
  first=___rest_resume_delivery(ps, record, epoch, ___FIX(1), &old_hp, &new_hp,
                                &entered);
  first_result=entered;
  second=___rest_resume_delivery(ps, record, epoch, ___FIX(1), &old_hp, &new_hp,
                                 &entered);
  ___rest_once_first=(___WORD)first;
  ___rest_once_second=(___WORD)second;
  ___rest_once_delta=___rest_internal_entries-before;
  ___rest_once_result=first_result==___FIX(7);
  ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
}

___BOOL ___rest_new_section_admitted(___processor_state ps, ___SIZE_T max_heap)
{
  ___processor_state ___ps=ps;
  ___SIZE_T cap, live, room, need;
  /* Same bound as resize reservation: live still words and assigned
   * sections, not the cumulative allocator counter. The caller passes the
   * contest ceiling when one is armed; otherwise this is the configured cap. */
  if (!___ps || ___ps!=___PSTATE) return 0;
  if (max_heap==0) return 1;
  if (occupied_words_still<0 || nb_msections_assigned<0) return 0;
  cap=max_heap>>___LWS;
  live=___CAST(___SIZE_T,occupied_words_still);
  if (cap<live) return 0;
  room=(cap-live)/___MSECTION_SIZE;
  need=___CAST(___SIZE_T,nb_msections_assigned)+1;
  return room>=need;
}

/* Ask the next collection for one section beyond the two-per-processor
 * assignment, and refuse any larger growth. The extra node is the unassigned
 * tail. An existing longer list is left unchanged so this does not reclaim
 * a section the mutators already own. */
___WORD ___rest_observation_one_fresh_section(___processor_state ps)
{
  ___processor_state ___ps=ps;
  int np;
  if (!___ps || ___ps!=___PSTATE || occupied_words_still<0 || the_msections==0)
    return -1;
  np=___VMSTATE_FROM_PSTATE(___ps)->processor_count;
  if (np<1 || np>___MAX_PROCESSORS/2) return -1;
  /* The measured startup list is already longer than one fresh tail:
   * 8 sections, 4 assigned, resume reserve 2. The next collection's
   * lower bound is at least 6, and setup then assigns 4, so at least
   * two sections stay unassigned. Report the length and do not shrink. */
  return ___CAST(___WORD,the_msections->nb_sections);
}

/* One test attempt. Production grants ignore this while it is zero.
 * The handler disarms it before returning, so the next activation
 * does not inherit the ceiling. */
___WORD ___rest_attempt_words;
___WORD ___rest_attempt_floor;
___WORD ___rest_attempt_entry_heap;
___WORD ___rest_attempt_entry_frame;
___WORD ___rest_attempt_entry_word;
___WORD ___rest_attempt_entry_arg;
___WORD ___rest_attempt_cut_arg;
___WORD ___rest_attempt_acquired_heap;
___WORD ___rest_attempt_acquired_frame;
___WORD ___rest_attempt_acquired_word;
___WORD ___rest_attempt_cut_heap;
___WORD ___rest_attempt_cut_frame;
___WORD ___rest_attempt_cut_word;
___WORD ___rest_attempt_cut_kind;
___WORD ___rest_attempt_cut_cursor;
___WORD ___rest_attempt_cut_sentinel;
/* Copied from the allocation cursor. Grant helpers do not store it.
 * A test that wants this value plants it on an interval the grant has
 * already authorized. */
___WORD ___rest_attempt_sentinel = 0x52455354;
___WORD ___rest_attempt_seen_words;
static int rest_attempt_blocked_flag;
static int rest_attempt_entry_noted;
static ___processor_state rest_attempt_owner;
static ___VOLATILE ___WORD rest_attempt_active_flag;

static int rest_attempt_here(___processor_state ps)
{
  return rest_attempt_owner && ps==rest_attempt_owner && ps==___PSTATE;
}

static int rest_attempt_refuses(___WORD words)
{
  int refuse;
  if (___rest_attempt_words>0) ___rest_attempt_seen_words=words;
  refuse=___rest_attempt_words>0 && words>=___rest_attempt_floor &&
    (___SIZE_TS)___rest_attempt_words<(___SIZE_TS)words;
  if (refuse) rest_attempt_blocked_flag=1;
  return refuse;
}

int ___rest_attempt_blocked(void)
{
  return rest_attempt_blocked_flag;
}

int ___rest_planted_short(void)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (rest_observation_auto_watch==1) return 1;
#endif
  return rest_attempt_owner && ___rest_attempt_words>0 && rest_attempt_here(___PSTATE);
}

___BOOL ___rest_one_word_short(___processor_state ps, ___WORD *hp, ___WORD *fp,
                              ___WORD pending, ___WORD np, ___WORD stack_slots)
{
  ___WORD words, *start, *end, *lo, *hi;
  ___SIZE_TS room;
  /* Exactly one word under the complete demand. The fast pair budget is
   * not this comparison. */
  if (!ps || ps!=___PSTATE || !ps->context || !hp || !fp || ps->context->hp!=hp)
    return 0;
  if (np<0 || stack_slots<0 || !rest_batch_words(pending, np, &words) || words<1)
    return 0;
  if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) return 0;
  if (stack_slots!=0 && (___SIZE_TS)(fp-lo)<(___SIZE_TS)stack_slots) return 0;
  start=ps->mem.alloc_heap_start_;
  end=ps->heap_limit?ps->heap_limit:ps->mem.alloc_heap_limit_;
  if (!start || !end || hp<start || hp>end) return 0;
  room=(___SIZE_TS)(end-hp);
  return room+1==(___SIZE_TS)words;
}

void ___rest_note_attempt_entry(___processor_state ps, ___WORD *hp, ___WORD *fp)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  /* Probe GAMBIT_REST_OBSERVATION at most once per process to avoid contending
   * on Darwin's global environ lock across SMP cores, and skip _Thread_local
   * observation state entirely when no observation mapping is open. */
  if (!__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE) &&
      !__atomic_load_n(&rest_observation_env_probed,__ATOMIC_ACQUIRE))
    ___rest_observation_open(0);
  if (__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE)) {
    if (!rest_observation_current_case()) {
      static uint64_t rest_observation_next_case=1;
      if (rest_observation_next_case)
        ___rest_observation_case(rest_observation_next_case++);
    }
    rest_observation_chain_bind(0,0);
    rest_observation_native_cut(ps,hp,fp,0,0,0);
    rest_observation_case_enter();
  }
#endif
  if (___rest_attempt_words<=0 || !rest_attempt_here(ps) || rest_attempt_entry_noted)
    return;
  rest_attempt_entry_noted=1;
  ___rest_attempt_entry_heap=hp ? ___CAST(___WORD,hp) : 0;
  ___rest_attempt_entry_frame=fp ? ___CAST(___WORD,fp) : 0;
  ___rest_attempt_entry_word=hp ? *hp : 0;
  ___rest_attempt_entry_arg=fp ? *fp : 0;
}

void ___rest_note_attempt_acquired(___processor_state ps, ___WORD *hp, ___WORD *fp)
{
  if (___rest_attempt_words<=0 || !rest_attempt_here(ps)) return;
  ___rest_attempt_acquired_heap=hp ? ___CAST(___WORD,hp) : 0;
  ___rest_attempt_acquired_frame=fp ? ___CAST(___WORD,fp) : 0;
  ___rest_attempt_acquired_word=hp ? *hp : 0;
}

void ___rest_capture_attempt_cut(___processor_state ps, ___WORD *hp, ___WORD *fp)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE))
    rest_observation_native_cut(ps,hp,fp,1,0,0);
#endif
  if (!rest_attempt_here(ps)) return;
  ___rest_attempt_cut_heap=hp ? ___CAST(___WORD,hp) : 0;
  ___rest_attempt_cut_frame=fp ? ___CAST(___WORD,fp) : 0;
  ___rest_attempt_cut_word=hp ? *hp : 0;
}

void ___rest_mark_attempt_cut(___processor_state ps, ___WORD *hp, ___WORD *fp,
                             int kind, ___WORD cursor)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  /* Record the cut before the attempt-owner check. A normal call does not
   * arm the older refusal injection, and that check must not drop cut 9. */
  if (__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE))
    rest_observation_native_cut(ps,hp,fp,1,(unsigned)kind,cursor);
#endif
  if (!rest_attempt_here(ps)) return;
  ___rest_capture_attempt_cut(ps, hp, fp);
  ___rest_attempt_cut_kind=kind;
  /* Remaining unpopped arguments, before ADJFP and exception cleanup. */
  ___rest_attempt_cut_cursor=cursor;
  ___rest_attempt_cut_sentinel=___rest_attempt_sentinel;
  ___rest_attempt_cut_arg=fp ? *fp : 0;
}

___WORD ___rest_attempt_view_open;
___WORD ___rest_attempt_view_mapped;
___WORD ___rest_attempt_view_frame;

void ___rest_note_attempt_view(___processor_state ps,
                              ___activation_record *record, ___WORD epoch,
                              ___WORD *fp)
{
  ___WORD root_count=0;
  ___WORD list_slot, window_slot, window_n, key_slot, key_n, result_slot;
  ___rc_header *h;
  ___UWORD frame, low, high;
  if (!rest_attempt_here(ps) || !record || !fp || !ps->context) return;
  ___rest_attempt_view_open=0;
  ___rest_attempt_view_mapped=0;
  ___rest_attempt_view_frame=0;
  if (record->rest_epoch!=epoch || !record->roots) return;
  if (record->rest_phase!=___REST_INSTALLED &&
      record->rest_phase!=___REST_READY) return;
  if (!rest_counts(record->rest_np, record->rest_nb_req_opt, record->rest_nb_key,
                   record->rest_j, record->rest_i, record->rest_n, &root_count))
    return;
  h=___CAST(___rc_header*,record->roots)-1;
  if (h->refcount<=0 || h->root_borrows!=1 ||
      h->root_count!=___CAST(___SIZE_T, root_count)) return;
  ___rest_attempt_view_open=1;
  ___rest_retry_map(record, &list_slot, &window_slot, &window_n,
                    &key_slot, &key_n, &result_slot);
  if (window_n==record->rest_n && result_slot+1==root_count)
    ___rest_attempt_view_mapped=1;
  frame=___CAST(___UWORD, fp);
  low=___CAST(___UWORD, ps->context->stack_limit);
  high=___CAST(___UWORD, ps->context->stack_break);
  if (low!=0 && frame>=low && frame<=high)
    ___rest_attempt_view_frame=1;
}

void ___rest_arm_force_slow(void)
{
  rest_attempt_owner=___PSTATE;
  rest_force_slow=1;
  ___WORD_STORE_RELEASE(&rest_attempt_active_flag, 1);
}

void ___rest_arm_attempt(___WORD words, ___WORD floor)
{
  rest_attempt_owner=___PSTATE;
  ___rest_attempt_words=words>0?words:0;
  ___rest_attempt_floor=floor>0?floor:0;
  rest_attempt_blocked_flag=0;
  rest_attempt_entry_noted=0;
  ___WORD_STORE_RELEASE(&rest_attempt_active_flag, 1);
  ___rest_attempt_entry_heap=0;
  ___rest_attempt_entry_frame=0;
  ___rest_attempt_entry_word=0;
  ___rest_attempt_entry_arg=0;
  ___rest_attempt_cut_arg=0;
  ___rest_before_collect_pops=-1;
  ___rest_before_collect_writes=-1;
  ___rest_chain_gates=0;
  ___rest_chain_reads=0;
  ___rest_chain_ungated=0;
  ___rest_attempt_acquired_heap=0;
  ___rest_attempt_acquired_frame=0;
  ___rest_attempt_acquired_word=0;
  ___rest_attempt_cut_heap=0;
  ___rest_attempt_cut_frame=0;
  ___rest_attempt_cut_word=0;
  ___rest_attempt_cut_kind=0;
  ___rest_attempt_cut_cursor=0;
  ___rest_attempt_cut_sentinel=0;
  ___rest_attempt_view_open=0;
  ___rest_attempt_view_mapped=0;
  ___rest_attempt_view_frame=0;
  ___rest_attempt_seen_words=0;
}

void ___rest_observation_note_adjust(___processor_state ps, ___WORD *fp,
                                     long words)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (fp) ___rest_observation_adjust(ps, fp, (intptr_t)words);
#else
  (void)ps; (void)fp; (void)words;
#endif
}

void ___rest_observation_note_store(___processor_state ps,
                                    ___activation_record *record,
                                    ___WORD epoch, ___WORD *fp,
                                    ___WORD *address)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (address)
    ___rest_observation_emit(REST_STORE,(uintptr_t)ps,(uintptr_t)record,
      record?(uint64_t)record->rest_attempt:0,(uint64_t)epoch,
      0,(uintptr_t)address,0,0,0,0,0,0);
#else
  (void)ps; (void)record; (void)epoch; (void)fp; (void)address;
#endif
}

void ___rest_observation_note_saved_fp(___processor_state ps,
                                      ___activation_record *record,
                                      ___WORD epoch, ___WORD *saved,
                                      ___WORD *parent)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  ___rest_observation_emit(REST_SAVED_FP,(uintptr_t)ps,(uintptr_t)record,
    record?(uint64_t)record->rest_attempt:0,(uint64_t)epoch,
    (uintptr_t)saved,(uintptr_t)parent,0,0,0,0,0,0);
#else
  (void)ps; (void)record; (void)epoch; (void)saved; (void)parent;
#endif
}

void ___rest_observation_note_return_fp(___processor_state ps,
                                       ___activation_record *record,
                                       ___WORD epoch, ___WORD *fp)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  ___rest_observation_emit(REST_RETURN_FP,(uintptr_t)ps,(uintptr_t)record,
    record?(uint64_t)record->rest_attempt:0,(uint64_t)epoch,
    (uintptr_t)fp,0,0,0,0,0,0,0);
  {
    uint64_t slots=0;
    if (rest_observation_restored_fp && fp &&
        (___WORD*)rest_observation_restored_fp>fp)
      slots=(uint64_t)((___WORD*)rest_observation_restored_fp-fp);
    rest_observation_emit_parent(3,fp,slots,
      ___COLLECTION(___VMSTATE_FROM_PSTATE(ps)).epoch);
    rest_observation_reloaded=1;
  }
#else
  (void)ps; (void)record; (void)epoch; (void)fp;
#endif
}

void ___rest_observation_note_body(___processor_state ps)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (__builtin_expect(!__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE), 1))
    return;
  ___rest_observation_clear_roots();
  if (ps && rest_observation_ready_label)
    REST_OBS(REST_TAIL,ps,rest_observation_chain_record,
             rest_observation_protocol_attempt,rest_observation_chain_attempt,
             rest_observation_ready_label,rest_observation_ready_result,0,0,0,0,0,0);
  /* Delivery stays in this case until the handler transfers to the body. */
  if (ps) ___rest_observation_body(ps);
  if (!rest_observation_case_hold && rest_observation_current_case())
    ___rest_observation_case_end();
#else
  (void)ps;
#endif
}

void ___rest_disarm_attempt(void)
{
#ifdef ___GAMBIT_REST_OBSERVATION
  if (__builtin_expect(__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE)!=0, 0)) {
    ___rest_observation_clear_roots();
    /* A recorded delivery stays open so the body event can follow it.
     * Any other exit closes the case here. */
    rest_observation_case_leave();
  }
#endif
  if (__builtin_expect(___WORD_LOAD_RELAXED(&rest_attempt_active_flag) == 0, 1))
    return;
  ___rest_attempt_words=0;
  ___rest_attempt_floor=0;
  rest_attempt_blocked_flag=0;
  rest_attempt_owner=0;
  rest_force_slow=0;
  ___WORD_STORE_RELEASE(&rest_attempt_active_flag, 0);
}

___WORD ___rest_heap_cursor(___processor_state ps)
{
  if (!ps || ps!=___PSTATE || !ps->context || !ps->context->hp) return 0;
  return ___CAST(___WORD,ps->context->hp);
}

___WORD ___rest_frame_cursor(___processor_state ps)
{
  if (!ps || ps!=___PSTATE || !ps->context || !ps->context->fp) return 0;
  return ___CAST(___WORD,ps->context->fp);
}

___BOOL ___rest_fast_grant_fits(___processor_state ps, ___WORD *hp, ___WORD *fp,
                               ___WORD pending, ___WORD np, ___WORD stack_slots)
{
  ___WORD words;
  /* Lock-free processor-owned fast_span leaf bypass: mirrors ___group_demand_enter
   * (zero copy_gate lock, zero ___PSTATE TLS, zero shared writes) when no attempt
   * injection or observation trace is active. */
  {
    int obs_idle = 1;
#ifdef ___GAMBIT_REST_OBSERVATION
    obs_idle = (__atomic_load_n(&rest_observation_map, __ATOMIC_ACQUIRE) == 0);
#endif
    if (__builtin_expect(
          obs_idle &&
          ___WORD_LOAD_RELAXED(&rest_attempt_active_flag) == 0 &&
          ___WORD_LOAD_ACQUIRE(&rest_observation_admission_captured) != 0 &&
          ps != 0 && ps->context != 0 && hp != 0 && fp != 0 &&
          ps->context->hp == hp && np >= 0 && stack_slots >= 0 &&
          rest_batch_words(pending, np, &words),
          1))
      {
        ___UWORD sd = ___CAST(___UWORD, fp) - ps->stack_fast_floor_b;
        ___UWORD hd = ___CAST(___UWORD, hp) - ps->heap_fast_lo_b;
        if (__builtin_expect(
              sd < ps->stack_fast_limit_b &&
              (sd / sizeof(___WORD)) >= (___UWORD)stack_slots &&
              hd < ps->heap_fast_bytes &&
              ((ps->heap_fast_bytes - hd) / sizeof(___WORD)) >= (___UWORD)words,
              1))
          return 1;
      }
  }

  if (__builtin_expect(___WORD_LOAD_ACQUIRE(&rest_attempt_active_flag) != 0, 0) &&
      rest_force_slow && rest_attempt_here(ps)) {
    rest_force_slow=0;
    return 0;
  }
  /* Ten-word envelope for the ordinary case. The following pair loop still
   * emits only pending*3 words. */
  if (np<0 || !rest_batch_words(pending, np, &words)) return 0;
  if (__builtin_expect(___WORD_LOAD_ACQUIRE(&rest_observation_admission_captured) == 0, 0)) {
    rest_observation_last_pending=pending;
    rest_observation_last_parameters=np;
    rest_observation_last_words=words;
    rest_observation_last_entry_room=___rest_observation_room(ps);
    rest_observation_last_one_word=
      ___rest_one_word_short(ps, hp, fp, pending, np, stack_slots) ? 1 : 0;
    rest_observation_last_physical=
      ___rest_physical_tail_short(ps, pending, np) ? 1 : 0;
    ___WORD_STORE_RELEASE(&rest_observation_admission_captured, 1);
  }
#ifdef ___GAMBIT_REST_OBSERVATION
  if (__builtin_expect(__atomic_load_n(&rest_observation_map,__ATOMIC_ACQUIRE)!=0, 0)) {
    /* Sample the settled boundary the handler is about to judge. Short is one
     * word under the complete demand. Exact is that demand. */
    if (rest_observation_auto_watch && ps && ps==___PSTATE && ps->context &&
        ps->na>=0 && hp && fp && words>0 && ps->mem.alloc_heap_limit_ &&
        (uintptr_t)hp<=(uintptr_t)ps->mem.alloc_heap_limit_) {
      ___WORD boundary=words-(rest_observation_auto_watch==1);
      if (___rest_observation_settled(ps)==boundary &&
          !__atomic_exchange_n(&rest_observation_auto_watch_claimed,1,__ATOMIC_RELAXED) &&
          ___rest_observation_watch((uint64_t)ps->na))
        rest_observation_native_cut(ps,hp,fp,0,0,0);
    }
    if (rest_observation_watch_state==2 &&
        rest_observation_watch_case==rest_observation_current_case())
      REST_OBS(REST_WATCHED_DEMAND,ps,0,0,0,hp,fp,words,pending,np,
               ___MSECTION_FUDGE,___PAIR_SIZE+___PAIR_BODY,___VECTOR_BODY);
  }
#endif
  {
    ___BOOL fits=rest_interval_fits(ps, hp, fp, words, stack_slots);
    return fits;
  }
}

___BOOL ___rest_stack_slots_fit(___processor_state ps, ___WORD *fp,
                               ___WORD stack_slots)
{
  ___WORD *lo, *hi;
  /* A short stack is not a destination-heap shortage. The handler must
   * refuse it before asking for another section. */
  if (!ps || ps!=___PSTATE || !ps->context || !fp || stack_slots<0) return 0;
  if (!___owned_stack_span(ps, &lo, &hi) || fp<lo || fp>hi) return 0;
  if (stack_slots!=0 && (___SIZE_TS)(fp-lo)<(___SIZE_TS)stack_slots) return 0;
  return 1;
}

___BOOL ___rest_grant_fits(___processor_state ps, ___WORD *hp, ___WORD *fp,
                           ___WORD pending, ___WORD np, ___WORD stack_slots)
{
  ___WORD words;
  ___BOOL fits;
  if (np<0 || !rest_batch_words(pending, np, &words)) return 0;
  fits=rest_interval_fits(ps, hp, fp, words, stack_slots);
#ifdef ___GAMBIT_REST_OBSERVATION
  if (rest_observation_chain_record && rest_observation_protocol_attempt && ps==___PSTATE) {
    ___processor_state ___ps=ps;
    ___WORD *lo, *hi;
    uint64_t round=___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch;
    unsigned flags=(fits ? 1 : 0) |
      (___rest_stack_slots_fit(ps,fp,stack_slots) ? 2 : 0) |
      (rest_observation_reloaded ? 4 : 0);
    REST_OBS(REST_SECTION_VIEW,ps,rest_observation_chain_record,
             rest_observation_protocol_attempt,round,
             heap_msection,tospace_offset,hp,ps->heap_limit,ps->mem.alloc_heap_limit_,
             fp,words,flags);
    if (fits && rest_observation_reloaded && ___owned_stack_span(ps,&lo,&hi))
      REST_OBS(REST_RETRY_GRANT,ps,rest_observation_chain_record,
               rest_observation_protocol_attempt,rest_observation_chain_attempt,
               round,hp,ps->heap_limit?ps->heap_limit:ps->mem.alloc_heap_limit_,
               fp,lo,hi,words,stack_slots);
  }
#endif
  return fits;
}

___BOOL ___rest_root_window(___processor_state ps, ___WORD *fp, ___SCMOBJ label,
                            ___WORD n, ___WORD nb_key, ___SCMOBJ *key_vals,
                            ___WORD nb_req_opt, ___WORD j, ___WORD i, ___WORD np,
                            int keyword, ___activation_record **record_out,
                            ___WORD *epoch_out)
{
  ___SCMOBJ *window=0;
  ___rest_span_request request;
  ___activation_record *record;
  ___WORD u;
  if (record_out) *record_out=0;
  if (epoch_out) *epoch_out=0;
  if (!ps || ps!=___PSTATE || !fp || n<0 || nb_key<0 || keyword<0 || keyword>1)
    return 0;
  if (nb_key>0 && !key_vals) return 0;
  if (n>0) {
    window=___CAST(___SCMOBJ*,___ALLOC_MEM((___SIZE_T)n*sizeof(___SCMOBJ)));
    if (!window) return 0;
    for (u=0; u<n; u++) window[u]=fp[u];
  }
  memset(&request, 0, sizeof request);
  request.attempt=___FIX(1);
  request.keyword=keyword;
  request.n=n;
  request.nb_key=nb_key;
  request.j=j;
  request.i=i;
  request.np=np;
  request.nb_req_opt=nb_req_opt;
  request.label=label?label:___FAL;
  request.rest_list=___NUL;
  request.window=window;
  request.key_vals=key_vals;
  record=___rest_activation_open(ps, &request);
  if (!record ||
      ___rest_span_publish(ps, record, &request, record->rest_epoch)!=___REST_OK) {
    if (record) ___rest_activation_cleanup(ps, record, ___FIX(1), record->rest_epoch);
    if (window) ___FREE_MEM(window);
    return 0;
  }
  if (window) ___FREE_MEM(window);
  if (record_out) *record_out=record;
  if (epoch_out) *epoch_out=record->rest_epoch;
#ifdef ___GAMBIT_REST_OBSERVATION
  /* The caller-chain walk follows this window. Bind its record before the
   * first source read so the pin, break link and successor share one attempt. */
  if (record->rest_epoch) {
    rest_observation_chain_bind(record,(uint64_t)record->rest_epoch);
    rest_observation_protocol_attempt=(uint64_t)record->rest_attempt;
  }
  /* The handler named its form before entry. Entry clears the parent
   * detail, so publish that same form with this window. */
  if (rest_observation_handler_form)
    rest_observation_form=rest_observation_handler_form;
  else if (!keyword)
    rest_observation_form=1;
#endif
  return 1;
}

___BOOL ___rest_reload_window(___processor_state ps, ___WORD *fp,
                              ___activation_record *record, ___WORD epoch,
                              ___WORD n, ___WORD nb_key, ___SCMOBJ *key_vals,
                              ___SCMOBJ *label_out)
{
  ___SCMOBJ *window=0;
  ___SCMOBJ label=___FAL, list=___NUL, result=___FAL;
  ___WORD u;
  enum ___rest_status status;
  if (!ps || !fp || n<0 || nb_key<0) return 0;
  if (n>0) window=___CAST(___SCMOBJ*,fp);
  status=___rest_span_reload(ps, record, ___FIX(1), epoch, window, n,
                             key_vals, nb_key);
#ifdef ___GAMBIT_REST_OBSERVATION
  if (status!=___REST_OK)
    REST_OBS(REST_RELOAD,ps,record,0,epoch,(uint64_t)status,n,0,0,0,0,0,0);
#endif
  if (status==___REST_OK &&
      ___rest_span_query(ps, record, ___FIX(1), epoch, &label, &list,
                         &result)!=___REST_OK)
    status=___REST_LOST;
  if (status==___REST_OK && window) {
    for (u=0; u<n; u++) fp[u]=window[u];
    ___rest_resume_reloads++;
  }
  if (status==___REST_OK && label_out) *label_out=label;
#ifdef ___GAMBIT_REST_OBSERVATION
  if (status==___REST_OK) {
    ___WORD index;
    uint64_t round=___COLLECTION(___VMSTATE_FROM_PSTATE(ps)).epoch;
    REST_OBS(REST_ROOT_VALUE,ps,record,record->rest_attempt,epoch,0,list,2,0,0,0,0,0);
    for (index=0; index<n; index++)
      REST_OBS(REST_ROOT_VALUE,ps,record,record->rest_attempt,epoch,
               index+1,window?window[index]:___FAL,2,0,0,0,0,0);
    for (index=0; index<nb_key; index++)
      REST_OBS(REST_ROOT_VALUE,ps,record,record->rest_attempt,epoch,
               n+1+index,key_vals[index],2,0,0,0,0,0);
    REST_OBS(REST_ROOT_VALUE,ps,record,record->rest_attempt,epoch,
             n+nb_key+1,result,2,0,0,0,0,0);
    REST_OBS(REST_RELOAD_INSTALLED,ps,record,record->rest_attempt,epoch,
             fp,n,key_vals,nb_key,label,list,result,round);
  }
#endif
  return status==___REST_OK;
}

void ___rest_retry_map(___activation_record *record,
                       ___WORD *list_slot, ___WORD *window_slot,
                       ___WORD *window_n, ___WORD *key_slot,
                       ___WORD *key_n, ___WORD *result_slot)
{
  ___WORD n, k;
  if (!record) return;
  n=record->rest_n;
  k=record->rest_nb_key;
  if (list_slot) *list_slot=0;
  if (window_slot) *window_slot=1;
  if (window_n) *window_n=n;
  if (key_slot) *key_slot=1+n;
  if (key_n) *key_n=k;
  if (result_slot) *result_slot=1+n+k;
}

enum ___rest_status ___rest_resume_delivery(___processor_state ps,
                                            ___activation_record *record,
                                            ___WORD generation,
                                            ___WORD attempt,
                                            ___WORD **old_hp,
                                            ___WORD **new_hp,
                                            ___SCMOBJ *entered)
{
  ___rest_directory_slot *dir_slot=0;
  ___WORD root_count;
  ___SCMOBJ result=___FAL;
  ___rc_header *h;
  ___rc_domain *d;
  enum ___rest_status proof=rest_with_pin(ps, record, attempt, generation, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (record->rest_delivered) {
    rest_unpin(ps, dir_slot, generation);
    if (entered) *entered=___FAL;
    return ___REST_DUPLICATE;
  }
  if (record->rest_phase!=___REST_READY ||
      !rest_view_open(ps, record, attempt, generation, &root_count)) {
    rest_unpin(ps, dir_slot, generation);
    return ___REST_LOST;
  }
  h=___CAST(___rc_header*,record->roots)-1; d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || !root_writer_open(ps) || h->refcount<=0 ||
      h->root_borrows!=1 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_epoch!=generation || record->rest_phase!=___REST_READY ||
      record->rest_delivered) {
    {
      int delivered=record->rest_delivered;
      ___RC_UNLOCK(d);
      rest_unpin(ps, dir_slot, generation);
      /* The last pin drop can retire the record. Do not load it again. */
      return delivered ? ___REST_DUPLICATE : ___REST_LOST;
    }
  }
  result=___CAST(___SCMOBJ*,record->roots)[root_count-1];
  record->rest_delivered=1;
  ___rest_internal_entries++;
#ifdef ___GAMBIT_REST_OBSERVATION
  ___rest_observation_delivered(ps,record,attempt,generation);
#endif
  ___RC_UNLOCK(d);
  if (entered) *entered=result;
  if (new_hp) *new_hp=ps->context->hp;
  if (old_hp && *old_hp!=ps->context->hp) {
    /* The cached cursor is not a grant. Delivery did not store through it. */
  }
  rest_unpin(ps, dir_slot, generation);
  return ___REST_OK;
}

enum ___rest_status ___rest_ready_preflight(___processor_state ps,
                                        ___activation_record *record,
                                        ___WORD attempt, ___WORD epoch)
{
  ___WORD root_count;
  ___rc_header *h;
  ___rc_domain *d;
  ___rest_directory_slot *dir_slot=0;
  enum ___rest_status proof;
  if (!ps || !record) return ___REST_LOST;
  proof=rest_with_pin(ps, record, attempt, epoch, &dir_slot);
  if (proof!=___REST_OK) return proof;
  if (!rest_view_open(ps, record, attempt, epoch, &root_count)) {
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  h=___CAST(___rc_header*,record->roots)-1; d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || !root_writer_open(ps) || h->refcount<=0 ||
      h->root_borrows!=1 || h->root_count!=___CAST(___SIZE_T, root_count) ||
      record->rest_epoch!=epoch ||
      (record->rest_phase!=___REST_READY &&
       record->rest_phase!=___REST_INSTALLED)) {
    ___RC_UNLOCK(d);
    rest_unpin(ps, dir_slot, epoch);
    return ___REST_LOST;
  }
  proof=record->rest_phase==___REST_READY ? ___REST_DUPLICATE : ___REST_OK;
  ___RC_UNLOCK(d);
  rest_unpin(ps, dir_slot, epoch);
  return proof;
}

___SCMOBJ ___rest_finish_refusal(___processor_state ps,
                                 ___activation_record *record,
                                 ___WORD epoch, ___SCMOBJ result,
                                 ___WORD **old_hp)
{
  ___WORD *new_hp=0;
  ___SCMOBJ entered=___FAL;
  enum ___rest_status ready, once;
  if (!ps || !record) return 0;
  ready=___rest_claim_ready(ps, record, ___FIX(1), epoch, result);
  if (ready!=___REST_OK && ready!=___REST_DUPLICATE) {
    ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
    return 0;
  }
  once=___rest_resume_delivery(ps, record, epoch, ___FIX(1), old_hp, &new_hp,
                               &entered);
  ___rest_activation_cleanup(ps, record, ___FIX(1), epoch);
  if (once!=___REST_OK) return 0;
  return entered==0 ? ___FAL : entered;
}
