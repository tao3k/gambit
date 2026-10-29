/* RC publication and source freezing share one mutex/linearization point.
 * Completion releases a scan lease, never the enclosing round's authority. */
/* These state transitions require source-specific exclusion: the RC gate or
 * the current VM coordinator's nonallocating, nonreentrant C invocation. */
___HIDDEN ___BOOL root_task_matches(___root_task *task,
                                  enum ___root_origin_kind kind,
                                  ___processor_state executor, ___UWORD epoch)
{
  return task->origin.kind == kind && task->executor == executor &&
         task->epoch == epoch;
}

___HIDDEN ___BOOL root_task_claim_state(___root_task *task,
                                       enum ___root_origin_kind kind,
                                       ___processor_state executor, ___UWORD epoch)
{
  if (!root_task_matches(task,kind,executor,epoch) ||
      task->scan_leases != 1 || task->state != ___ROOT_READY) return 0;
  task->state=___ROOT_CLAIMED;
  return 1;
}

___HIDDEN ___BOOL root_task_finish_state(___root_task *task,
                                        enum ___root_origin_kind kind,
                                        ___processor_state executor, ___UWORD epoch)
{
  if (!root_task_matches(task,kind,executor,epoch)) return 0;
  if (task->state == ___ROOT_SCANNED && task->scan_leases == 1)
    { task->state=___ROOT_DONE; task->scan_leases=0; return 1; }
  return task->state == ___ROOT_DONE && task->scan_leases == 0;
}

___BOOL ___root_task_publish(___rc_domain *d, ___processor_state executor,
                            ___UWORD previous, ___UWORD *epoch)
{
  ___BOOL accepted=0;
  if (d == 0 || executor == 0 || executor != ___PSTATE || epoch == 0) return 0;
  ___RC_LOCK(d);
  /* A retry may recover this publication; it cannot create another lease. */
  if (d->phase == ___RC_FROZEN && d->task.origin.kind == ___ROOT_RC &&
      d->task.origin.source.rc == d && d->task.epoch != 0 &&
      previous == d->task.epoch-1 && d->task.executor == executor &&
      d->task.state >= ___ROOT_READY && d->task.state <= ___ROOT_DONE)
    accepted=1;
  else if (d->phase == ___RC_OPEN && d->joined_round == 0 && d->owner == executor &&
           d->task.scan_leases == 0 && previous == d->task.epoch &&
           previous != ~___CAST(___UWORD,0) &&
           (d->task.state == ___ROOT_EMPTY || d->task.state == ___ROOT_DONE || d->task.state == ___ROOT_REFUSED))
    {
      d->task.origin.kind=___ROOT_RC; d->task.origin.source.rc=d; d->task.executor=executor;
      d->task.epoch=previous+1; d->task.state=___ROOT_READY;
      d->task.scan_leases=1;
      d->phase=___RC_FROZEN;
      accepted=1;
    }
  if (accepted) *epoch=d->task.epoch;
  ___RC_UNLOCK(d);
  return accepted;
}

___BOOL ___root_task_claim(___rc_domain *d, ___processor_state executor,
                          ___UWORD epoch)
{
  ___BOOL accepted=0;
  if (d == 0 || executor == 0 || executor != ___PSTATE) return 0;
  ___RC_LOCK(d);
  if (d->phase == ___RC_FROZEN && d->task.origin.source.rc == d)
    accepted=root_task_claim_state(&d->task,___ROOT_RC,executor,epoch);
  ___RC_UNLOCK(d);
  return accepted;
}

___BOOL ___root_task_finish(___rc_domain *d, ___processor_state executor,
                           ___UWORD epoch)
{
  ___BOOL accepted=0;
  if (d == 0 || executor == 0 || executor != ___PSTATE) return 0;
  ___RC_LOCK(d);
  if (d->phase == ___RC_FROZEN && d->task.origin.source.rc == d)
    accepted=root_task_finish_state(&d->task,___ROOT_RC,executor,epoch);
  ___RC_UNLOCK(d);
  return accepted;
}

___BOOL ___root_task_completed(___rc_domain *d, ___processor_state executor,
                              ___UWORD epoch)
{
  ___BOOL done;
  if (d == 0 || executor == 0 || executor != ___PSTATE) return 0;
  ___RC_LOCK(d);
  done=d->task.origin.source.rc == d && root_task_matches(&d->task,___ROOT_RC,executor,epoch) &&
       d->task.state == ___ROOT_DONE && d->task.scan_leases == 0;
  ___RC_UNLOCK(d);
  return done;
}

/* Fresh confined task state. Source-specific wrappers supply the stopped
 * source/current executor; no record is queued, reinitialized or migrated. */
void ___root_task_init(___root_task *task, ___UWORD previous)
{
  task->origin.kind=___ROOT_NONE; task->origin.source.vm=0;
  task->executor=0; task->epoch=previous; task->scan_leases=0;
  task->state=___ROOT_EMPTY;
}

___HIDDEN ___BOOL root_vm_executor(___processor_state executor)
{
  return executor != 0 && executor == ___PSTATE &&
         ___PROCESSOR_ID(executor,___VMSTATE_FROM_PSTATE(executor)) == 0;
}

/* Shared fresh-record eligibility; descriptor initialization must not reset
 * or overwrite an exposed/unknown task when publication is refused. */
___HIDDEN ___BOOL root_task_fresh(___root_task *task, ___UWORD previous)
{
  return task->origin.kind == ___ROOT_NONE && task->state == ___ROOT_EMPTY &&
         task->scan_leases == 0 && previous == task->epoch &&
         previous != ~___CAST(___UWORD,0);
}

/* VM, bank, stack, symkey and globals publication share one confined state transition. The
 * wrapper checks source identity before reading any source payload. */
___HIDDEN ___BOOL root_task_publish_confined(___root_task *task,
                                            ___root_origin origin,
                                            ___processor_state executor,
                                            ___UWORD previous, ___UWORD *epoch)
{
  ___BOOL same_source=0;
  if (task->origin.kind == origin.kind)
    {
      if (origin.kind == ___ROOT_VM)
        same_source=task->origin.source.vm == origin.source.vm;
      else if (origin.kind == ___ROOT_BANK)
        same_source=task->origin.source.bank == origin.source.bank;
      else if (origin.kind == ___ROOT_STACK)
        same_source=task->origin.source.stack == origin.source.stack;
      else if (origin.kind == ___ROOT_SYMKEY)
        same_source=task->origin.source.symkey == origin.source.symkey;
      else if (origin.kind == ___ROOT_GLOBALS)
        same_source=task->origin.source.globals == origin.source.globals;
    }
  if (same_source && task->executor == executor && task->epoch != 0 &&
      previous == task->epoch-1 &&
      task->state >= ___ROOT_READY && task->state <= ___ROOT_DONE)
    { *epoch=task->epoch; return 1; }
  if (!root_task_fresh(task,previous)) return 0;
  task->origin=origin; task->executor=executor; task->epoch=previous+1;
  task->scan_leases=1; task->state=___ROOT_READY;
  *epoch=task->epoch;
  return 1;
}

___BOOL ___root_task_publish_vm(___root_task *task, ___virtual_machine_state source,
                               ___processor_state executor, ___UWORD previous,
                               ___UWORD *epoch)
{
  ___root_origin origin;
  if (task == 0 || epoch == 0 || !root_vm_executor(executor) ||
      source != ___VMSTATE_FROM_PSTATE(executor)) return 0;
  origin.kind=___ROOT_VM; origin.source.vm=source;
  return root_task_publish_confined(task,origin,executor,previous,epoch);
}

___HIDDEN ___BOOL root_vm_task(___root_task *task, ___processor_state executor)
{
  return task != 0 && root_vm_executor(executor) &&
         task->origin.kind == ___ROOT_VM &&
         task->origin.source.vm == ___VMSTATE_FROM_PSTATE(executor);
}

___BOOL ___root_task_claim_vm(___root_task *task, ___processor_state executor,
                             ___UWORD epoch)
{
  return root_vm_task(task,executor) &&
         root_task_claim_state(task,___ROOT_VM,executor,epoch);
}

___BOOL ___root_task_finish_vm(___root_task *task, ___processor_state executor,
                              ___UWORD epoch)
{
  return root_vm_task(task,executor) &&
         root_task_finish_state(task,___ROOT_VM,executor,epoch);
}

___BOOL ___root_task_completed_vm(___root_task *task, ___processor_state executor,
                                 ___UWORD epoch)
{
  return root_vm_task(task,executor) &&
         root_task_matches(task,___ROOT_VM,executor,epoch) &&
         task->state == ___ROOT_DONE && task->scan_leases == 0;
}

/* A context source is a VM-owned slot, not arbitrary carrier storage. Keep the
 * existing synchronous binding; no context migration is admitted here. */
___HIDDEN ___BOOL root_context_executor(___execution_context *source,
                                   ___processor_state executor)
{
  ___virtual_machine_state vm;
  int id;
  if (executor == 0 || executor != ___PSTATE || source == 0) return 0;
  vm=___VMSTATE_FROM_PSTATE(executor);
  id=___PROCESSOR_ID(executor,vm);
  if(id<0 || id>=vm->processor_count || id>=___MAX_PROCESSORS) return 0;
  if(source==executor->context && source==&vm->execution_contexts[id]) return 1;
  if(executor->collector != 0) {
    ___root_round *round=___ROOT_UNION(vm); int i;
    if(round->state!=___ROOT_ROUND_FROZEN || id>=round->collection.worker_count) return 0;
    for(i=id;i<round->participants;i+=round->collection.worker_count)
      if(round->members[i].context==source && round->members[i].rc->joined_round==round) return 1;
  }
  return 0;
}

___BOOL ___root_task_publish_bank(___root_task *task, ___execution_context *source,
                                 ___processor_state executor, ___UWORD previous,
                                 ___UWORD *epoch)
{
  ___root_origin origin;
  if (task == 0 || epoch == 0 || !root_context_executor(source,executor)) return 0;
  origin.kind=___ROOT_BANK; origin.source.bank=source;
  return root_task_publish_confined(task,origin,executor,previous,epoch);
}

___HIDDEN ___BOOL root_bank_task(___root_task *task, ___processor_state executor)
{
  return task != 0 && task->origin.kind == ___ROOT_BANK &&
         root_context_executor(task->origin.source.bank,executor);
}

___BOOL ___root_task_claim_bank(___root_task *task, ___processor_state executor,
                               ___UWORD epoch)
{
  return root_bank_task(task,executor) &&
         root_task_claim_state(task,___ROOT_BANK,executor,epoch);
}

___BOOL ___root_task_finish_bank(___root_task *task, ___processor_state executor,
                                ___UWORD epoch)
{
  return root_bank_task(task,executor) &&
         root_task_finish_state(task,___ROOT_BANK,executor,epoch);
}

___BOOL ___root_task_completed_bank(___root_task *task, ___processor_state executor,
                                   ___UWORD epoch)
{
  return root_bank_task(task,executor) &&
         root_task_matches(task,___ROOT_BANK,executor,epoch) &&
         task->state == ___ROOT_DONE && task->scan_leases == 0;
}

___BOOL ___root_task_publish_stack(___root_task *task, ___execution_context *source,
                                  ___processor_state executor, ___UWORD previous,
                                  ___UWORD *epoch)
{
  ___root_origin origin;
  if (task == 0 || epoch == 0 || !root_context_executor(source,executor)) return 0;
  origin.kind=___ROOT_STACK; origin.source.stack=source;
  return root_task_publish_confined(task,origin,executor,previous,epoch);
}

___HIDDEN ___BOOL root_stack_task(___root_task *task, ___processor_state executor)
{
  return task != 0 && task->origin.kind == ___ROOT_STACK &&
         root_context_executor(task->origin.source.stack,executor);
}

___BOOL ___root_task_claim_stack(___root_task *task, ___processor_state executor,
                                ___UWORD epoch)
{
  return root_stack_task(task,executor) &&
         root_task_claim_state(task,___ROOT_STACK,executor,epoch);
}

___BOOL ___root_task_finish_stack(___root_task *task, ___processor_state executor,
                                 ___UWORD epoch)
{
  return root_stack_task(task,executor) &&
         root_task_finish_state(task,___ROOT_STACK,executor,epoch);
}

___BOOL ___root_task_completed_stack(___root_task *task, ___processor_state executor,
                                    ___UWORD epoch)
{
  return root_stack_task(task,executor) &&
         root_task_matches(task,___ROOT_STACK,executor,epoch) &&
         task->state == ___ROOT_DONE && task->scan_leases == 0;
}

___BOOL ___root_task_publish_symkey(___root_task *task, ___global_state source,
                                   ___processor_state executor, ___UWORD previous,
                                   ___UWORD *epoch)
{
  ___root_origin origin;
  if (task == 0 || epoch == 0 || !root_vm_executor(executor) ||
      source != ___GSTATE) return 0;
  origin.kind=___ROOT_SYMKEY; origin.source.symkey=source;
  return root_task_publish_confined(task,origin,executor,previous,epoch);
}

___HIDDEN ___BOOL root_symkey_task(___root_task *task, ___processor_state executor)
{
  return task != 0 && root_vm_executor(executor) &&
         task->origin.kind == ___ROOT_SYMKEY &&
         task->origin.source.symkey == ___GSTATE;
}

___BOOL ___root_task_claim_symkey(___root_task *task, ___processor_state executor,
                                 ___UWORD epoch)
{
  return root_symkey_task(task,executor) &&
         root_task_claim_state(task,___ROOT_SYMKEY,executor,epoch);
}

___BOOL ___root_task_finish_symkey(___root_task *task, ___processor_state executor,
                                  ___UWORD epoch)
{
  return root_symkey_task(task,executor) &&
         root_task_finish_state(task,___ROOT_SYMKEY,executor,epoch);
}

___BOOL ___root_task_completed_symkey(___root_task *task, ___processor_state executor,
                                     ___UWORD epoch)
{
  return root_symkey_task(task,executor) &&
         root_task_matches(task,___ROOT_SYMKEY,executor,epoch) &&
         task->state == ___ROOT_DONE && task->scan_leases == 0;
}

/* Half-open floor partitions, including empty shards. Reject arithmetic that
 * cannot represent the old mathematical product rather than wrap its bound. */
___BOOL ___root_globals_partition(int extent, int participant, int participants,
                                 int *lo, int *hi)
{
  ___UWORD n;
  if (lo == 0 || hi == 0 || extent < 0 || participants <= 0 ||
      participant < 0 || participant >= participants) return 0;
  n=___CAST(___UWORD,extent);
  if (n != 0 && ___CAST(___UWORD,participants) >
      ~___CAST(___UWORD,0)/n) return 0;
  *lo=___CAST(int,(___CAST(___UWORD,participant)*n)/participants);
  *hi=___CAST(int,(___CAST(___UWORD,participant+1)*n)/participants);
  return 1;
}

___BOOL ___root_globals_begin(___global_root_snapshot *snapshot,
                                ___processor_state coordinator, ___UWORD epoch)
{
  ___virtual_machine_state vm;
  int i, ok=1;
  if (snapshot==0 || coordinator==0 || coordinator!=___PSTATE || epoch==0)
    return 0;
  vm=___VMSTATE_FROM_PSTATE(coordinator);
  if (___PROCESSOR_ID(coordinator,vm)!=0 || vm->processor_count<1 ||
      vm->processor_count>___MAX_PROCESSORS) return 0;
  /* The caller owns the closed roster, after all root sources froze at the
   * existing collective. Do not turn a mere count read into writer exclusion. */
  for (i=0;i<vm->processor_count;i++) {
    ___rc_domain *domain=___PSTATE_FROM_PROCESSOR_ID(i,vm)->mem.rc_domain_;
    if (domain==0) return 0;
    ___RC_LOCK(domain);
    ok=domain->phase==___RC_FROZEN && domain->task.epoch==epoch;
    ___RC_UNLOCK(domain);
    if (!ok) return 0;
  }
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (vm->mem.globals_snapshot_!=0 || ___GSTATE->mem.global_bootstrap ||
      ___GSTATE->mem.glo_list.count>___CAST(___UWORD,INT_MAX) ||
      ___GSTATE->mem.global_snapshots==~___CAST(___SIZE_T,0)) ok=0;
#ifndef ___SINGLE_VM
  if (vm->glos==0 || ___GSTATE->mem.glo_list.count>___GLOBALS_CAPACITY) ok=0;
#endif
  if (ok) {
    snapshot->vm=vm; snapshot->epoch=epoch;
    snapshot->count=___CAST(int,___GSTATE->mem.glo_list.count);
    snapshot->participants=vm->processor_count;
    for (i=0;i<snapshot->participants;i++) snapshot->shards[i]=0;
    ++___GSTATE->mem.global_snapshots;
    vm->mem.globals_snapshot_=snapshot;
  }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return ok;
}

___BOOL ___root_globals_end(___global_root_snapshot *snapshot,
                              ___processor_state coordinator)
{
  int i,ok=1;
  ___virtual_machine_state vm;
  if (snapshot==0 || coordinator==0 || coordinator!=___PSTATE) return 0;
  vm=___VMSTATE_FROM_PSTATE(coordinator);
  if (___PROCESSOR_ID(coordinator,vm)!=0) return 0;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (vm->mem.globals_snapshot_!=snapshot || snapshot->vm!=vm ||
      snapshot->participants!=vm->processor_count ||
      ___GSTATE->mem.global_snapshots==0) ok=0;
  if (ok) for (i=0;i<snapshot->participants;i++)
    if (snapshot->shards[i]!=2) { ok=0; break; }
  if (ok) {
    vm->mem.globals_snapshot_=0;
    --___GSTATE->mem.global_snapshots;
  }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return ok;
}

___HIDDEN ___BOOL root_globals_view(___global_root_source *view,
                                   ___virtual_machine_state vm,
                                   ___processor_state executor)
{
  int extent;
  const ___global_root_snapshot *snapshot;
  if (executor == 0 || executor != ___PSTATE ||
      vm != ___VMSTATE_FROM_PSTATE(executor)) return 0;
  snapshot=vm->mem.globals_snapshot_;
  if (snapshot==0 || snapshot->vm!=vm || snapshot->epoch==0 ||
      snapshot->participants!=vm->processor_count) return 0;
  view->global=___GSTATE; view->vm=vm;
  view->snapshot=snapshot; view->snapshot_epoch=snapshot->epoch;
  view->count=snapshot->count;
  view->participants=snapshot->participants;
  view->participant=___PROCESSOR_ID(executor,vm);
  if (view->count < 0 || view->participants <= 0 ||
      view->participants > ___MAX_PROCESSORS) return 0;
#ifdef ___SINGLE_VM
  extent=___GLO_SUBLIST_COUNT;
#else
  if (view->count > ___GLOBALS_CAPACITY || vm->glos == 0) return 0;
  extent=view->count;
#endif
  return ___root_globals_partition(extent,view->participant,view->participants,
                                   &view->lo,&view->hi);
}

___HIDDEN ___BOOL root_globals_equal(const ___global_root_source *a,
                                    const ___global_root_source *b)
{
  return a->global == b->global && a->vm == b->vm && a->count == b->count &&
         a->participants == b->participants && a->participant == b->participant &&
         a->lo == b->lo && a->hi == b->hi &&
         a->snapshot == b->snapshot && a->snapshot_epoch == b->snapshot_epoch;
}

___BOOL ___root_task_publish_globals(___root_task *task,
                                    ___global_root_source *storage,
                                    ___virtual_machine_state vm,
                                    ___processor_state executor,
                                    ___UWORD previous, ___UWORD *epoch)
{
  ___global_root_source view;
  ___root_origin origin;
  if (task == 0 || storage == 0 || epoch == 0 ||
      !root_globals_view(&view,vm,executor)) return 0;
  if (task->origin.kind == ___ROOT_GLOBALS)
    {
      if (task->origin.source.globals != storage ||
          !root_globals_equal(storage,&view)) return 0;
    }
  else
    {
      if (!root_task_fresh(task,previous)) return 0;
      *storage=view; /* Initialize descriptor before READY, only once. */
    }
  origin.kind=___ROOT_GLOBALS; origin.source.globals=storage;
  {
    ___global_root_snapshot *snapshot=vm->mem.globals_snapshot_;
    ___BOOL fresh=task->origin.kind!=___ROOT_GLOBALS, ok;
    ___MUTEX_LOCK(___GSTATE->mem.global_gate);
    ok=(!fresh || snapshot->shards[view.participant]==0) &&
       root_task_publish_confined(task,origin,executor,previous,epoch);
    if (ok && fresh) snapshot->shards[view.participant]=1;
    ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
    return ok;
  }
}

___HIDDEN ___BOOL root_globals_task(___root_task *task,
                                   ___processor_state executor)
{
  ___global_root_source expected;
  if(executor!=0 && executor==___PSTATE && executor->collector!=0 && task!=0 &&
     task->origin.kind==___ROOT_GLOBALS) {
    ___root_round *round=___ROOT_UNION(___VMSTATE_FROM_PSTATE(executor));
    int i,worker=executor->collector->id;
    if(round->state!=___ROOT_ROUND_FROZEN || round->collection.worker_count<1) return 0;
    for(i=worker;i<round->participants;i+=round->collection.worker_count)
      if(task==&round->members[i].global_task &&
         task->origin.source.globals==&round->members[i].globals &&
         round->members[i].globals.snapshot==&round->globals) return 1;
    return 0;
  }
  return executor != 0 && executor == ___PSTATE && task != 0 &&
         task->origin.kind == ___ROOT_GLOBALS && task->origin.source.globals != 0 &&
         root_globals_view(&expected,___VMSTATE_FROM_PSTATE(executor),executor) &&
         root_globals_equal(task->origin.source.globals,&expected);
}

___BOOL ___root_task_claim_globals(___root_task *task, ___processor_state executor,
                                  ___UWORD epoch)
{
  return executor != 0 && executor == ___PSTATE && root_globals_task(task,executor) &&
         root_task_claim_state(task,___ROOT_GLOBALS,executor,epoch);
}

___BOOL ___root_task_finish_globals(___root_task *task, ___processor_state executor,
                                   ___UWORD epoch)
{
  ___BOOL ok;
  const ___global_root_source *source;
  if (!root_globals_task(task,executor)) return 0;
  source=task->origin.source.globals;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  ok=root_task_finish_state(task,___ROOT_GLOBALS,executor,epoch);
  if (ok) source->vm->mem.globals_snapshot_->shards[source->participant]=2;
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return ok;
}

___BOOL ___root_task_completed_globals(___root_task *task, ___processor_state executor,
                                      ___UWORD epoch)
{
  return executor != 0 && executor == ___PSTATE && root_globals_task(task,executor) &&
         root_task_matches(task,___ROOT_GLOBALS,executor,epoch) &&
         task->state == ___ROOT_DONE && task->scan_leases == 0;
}

___HIDDEN ___root_round *root_round_for(___processor_state ps)
{
  ___rc_domain *coordinator;
  if (ps == 0 || ps != ___PSTATE) return 0;
  coordinator=___PSTATE_FROM_PROCESSOR_ID(0,___VMSTATE_FROM_PSTATE(ps))->mem.rc_domain_;
  return coordinator == 0 ? 0 : coordinator->round;
}

/* All participants have saved their full root views and reached the first
 * collective. A changing roster or retained scan refuses the entire union.
 * In particular a newly started RC domain must not invent its own GC epoch. */
___BOOL ___root_round_begin(___processor_state ps)
{
  ___root_round *round=root_round_for(ps);
  ___UWORD previous;
  int i;
  if (!root_vm_executor(ps) || round == 0 ||
      round->state != ___ROOT_ROUND_IDLE || round->vm->processor_count < 1 ||
      round->vm->processor_count > ___MAX_PROCESSORS) return 0;
  previous=round->epoch;
  for (i=0;i<round->vm->processor_count;i++)
    {
      ___processor_state owner=___PSTATE_FROM_PROCESSOR_ID(i,round->vm);
      ___rc_domain *domain=owner->mem.rc_domain_;
      ___BOOL ok;
      if (domain == 0 || owner->context == 0) return 0;
      ___RC_LOCK(domain);
      ok=domain->owner == owner && domain->joined_round == 0 && domain->phase == ___RC_OPEN &&
         domain->task.scan_leases == 0 &&
         (domain->task.state == ___ROOT_EMPTY || domain->task.state == ___ROOT_DONE || domain->task.state == ___ROOT_REFUSED);
      if (previous < domain->task.epoch) previous=domain->task.epoch;
      ___RC_UNLOCK(domain);
      if (!ok) return 0;
    }
  if (previous == ~___CAST(___UWORD,0)) return 0;
  round->participants=round->vm->processor_count;
  round->epoch=previous+1;
  for (i=0;i<round->participants;i++)
    {
      ___root_member *member=&round->members[i];
      member->owner=___PSTATE_FROM_PROCESSOR_ID(i,round->vm);
      member->rc=member->owner->mem.rc_domain_;
      member->context=member->owner->context;
      ___RC_LOCK(member->rc);
      member->rc->joined_round=round;
      ___RC_UNLOCK(member->rc);
      ___root_task_init(&member->global_task,previous);
      ___root_task_init(&member->stack_task,previous);
      ___root_task_init(&member->bank_task,previous);
    }
  ___root_task_init(&round->vm_task,previous);
  ___root_task_init(&round->symkey_task,previous);
  ___RC_LOCK(ps->mem.rc_domain_);
  round->state=___ROOT_ROUND_CLOSING;
  ___RC_UNLOCK(ps->mem.rc_domain_);
  return 1;
}

___BOOL ___root_round_freeze(___processor_state ps, ___UWORD *epoch)
{
  ___root_round *round=root_round_for(ps);
  ___root_member *member;
  ___rc_domain *domain;
  ___BOOL ok;
  int id;
  if (round == 0 || epoch == 0 || round->state != ___ROOT_ROUND_CLOSING ||
      round->participants != round->vm->processor_count) return 0;
  id=___PROCESSOR_ID(ps,round->vm);
  if (id < 0 || id >= round->participants) return 0;
  member=&round->members[id]; domain=ps->mem.rc_domain_;
  if (member->owner != ps || member->rc != domain || member->context != ps->context)
    return 0;
  ___RC_LOCK(domain);
  ok=domain->owner == ps && domain->joined_round == round && domain->phase == ___RC_OPEN &&
     domain->task.scan_leases == 0 && domain->task.epoch < round->epoch &&
     (domain->task.state == ___ROOT_EMPTY || domain->task.state == ___ROOT_DONE || domain->task.state == ___ROOT_REFUSED);
  if (ok)
    {
      domain->task.origin.kind=___ROOT_RC; domain->task.origin.source.rc=domain;
      domain->task.executor=ps; domain->task.epoch=round->epoch;
      domain->task.state=___ROOT_READY; domain->task.scan_leases=1;
      domain->phase=___RC_FROZEN; *epoch=round->epoch;
    }
  ___RC_UNLOCK(domain);
  return ok;
}

___BOOL ___root_round_publish(___processor_state ps)
{
  ___root_round *round=root_round_for(ps);
  if (!root_vm_executor(ps) || round == 0 ||
      round->state != ___ROOT_ROUND_CLOSING ||
      !___root_globals_begin(&round->globals,ps,round->epoch)) return 0;
  { int i; ___WORD requested=___LOAD_GLOBAL_WORD(&round->collection.requested_workers);
    int count=(requested>0 && requested<round->participants)?(int)requested:round->participants;
    round->collection.decision=0;
    for(i=0;i<round->participants;i++)round->collection.observed[i]=0;
    round->collection.epoch=round->epoch;
    round->collection.participant_count=round->participants;
    round->collection.worker_count=count;
    round->collection.frame_gate=0;
    for(i=0;i<round->participants;i++) {
      ___root_member *member=&round->members[i];
      ___processor_state executor=round->members[i%count].owner;
      ___root_task *tasks[3]={&member->global_task,&member->stack_task,&member->bank_task};
      int j;
      member->globals.global=___GSTATE; member->globals.vm=round->vm;
      member->globals.count=round->globals.count; member->globals.participants=round->participants;
      member->globals.participant=i; member->globals.snapshot=&round->globals;
      member->globals.snapshot_epoch=round->epoch;
#ifdef ___SINGLE_VM
      if(!___root_globals_partition(___GLO_SUBLIST_COUNT,i,round->participants,&member->globals.lo,&member->globals.hi)) return 0;
#else
      if(!___root_globals_partition(round->globals.count,i,round->participants,&member->globals.lo,&member->globals.hi)) return 0;
#endif
      member->global_task.origin.kind=___ROOT_GLOBALS;
      member->global_task.origin.source.globals=&member->globals;
      member->stack_task.origin.kind=___ROOT_STACK; member->stack_task.origin.source.stack=member->context;
      member->bank_task.origin.kind=___ROOT_BANK; member->bank_task.origin.source.bank=member->context;
      for(j=0;j<3;j++) { tasks[j]->executor=executor;tasks[j]->epoch=round->epoch;
        tasks[j]->scan_leases=1;tasks[j]->state=___ROOT_READY; }
      round->globals.shards[i]=1;
      ___RC_LOCK(member->rc);member->rc->task.executor=executor;___RC_UNLOCK(member->rc);
    }
  }
  ___RC_LOCK(ps->mem.rc_domain_);
  round->state=___ROOT_ROUND_FROZEN;
  ___RC_UNLOCK(ps->mem.rc_domain_);
  return 1;
}

/* Each record already belongs to the union before it becomes READY. The
 * source-specific adapter enforces canonical source identity and writes only
 * its own member slot. A partial/unknown scan cannot be reinitialized/requeued.
 * Preserve VM/symkey, RC, globals, stack, bank order and in-place frame repair. */
___BOOL ___root_round_scan(___processor_state ps, ___UWORD epoch)
{
  ___root_round *round=root_round_for(ps);
  ___root_member *member;
  ___UWORD receipt;
  int id;
  if (round == 0 || round->state != ___ROOT_ROUND_FROZEN || round->epoch != epoch ||
      (ps->collector!=0 && round->collection.decision!=1))
    return 0;
  id=___PROCESSOR_ID(ps,round->vm);
  if (id < 0 || id >= round->participants) return 0;
  if (id == 0)
    {
      if (!___root_task_publish_vm(&round->vm_task,round->vm,ps,epoch-1,&receipt) ||
          receipt != epoch || !___root_task_claim_vm(&round->vm_task,ps,epoch) ||
          !___root_task_scan_vm(&round->vm_task,ps,epoch) ||
          !___root_task_finish_vm(&round->vm_task,ps,epoch)) return 0;
      if (!___root_task_publish_symkey(&round->symkey_task,___GSTATE,ps,epoch-1,&receipt) ||
          receipt != epoch || !___root_task_claim_symkey(&round->symkey_task,ps,epoch) ||
          !___root_task_scan_symkey(&round->symkey_task,ps,epoch) ||
          !___root_task_finish_symkey(&round->symkey_task,ps,epoch)) return 0;
    }
  for(id=___PROCESSOR_ID(ps,round->vm);id<round->participants;id+=round->collection.worker_count) {
    member=&round->members[id];
  if (!___root_task_claim(member->rc,ps,epoch) ||
      !___root_task_scan(member->rc,ps,epoch) ||
      !___root_task_finish(member->rc,ps,epoch)) return 0;
  if (!___root_task_claim_globals(&member->global_task,ps,epoch) ||
      !___root_task_scan_globals(&member->global_task,ps,epoch) ||
      !___root_task_finish_globals(&member->global_task,ps,epoch)) return 0;
  if (!___root_task_claim_stack(&member->stack_task,ps,epoch) ||
      !___root_task_scan_stack(&member->stack_task,ps,epoch) ||
      !___root_task_finish_stack(&member->stack_task,ps,epoch)) return 0;
  if (!___root_task_claim_bank(&member->bank_task,ps,epoch) ||
      !___root_task_scan_bank(&member->bank_task,ps,epoch) ||
      !___root_task_finish_bank(&member->bank_task,ps,epoch)) return 0;
  }
  return 1;
}

/* The strong-phase collective joins every task, including empty global
 * shards. Local DONE never grants source/domain/VM retirement permission. */
___BOOL ___root_round_finish_scan(___processor_state ps)
{
  ___root_round *round=root_round_for(ps);
  int i;
  if (!root_vm_executor(ps) || round == 0 || round->state != ___ROOT_ROUND_FROZEN ||
      round->participants != round->vm->processor_count ||
      round->vm_task.state != ___ROOT_DONE || round->vm_task.scan_leases != 0 ||
      round->symkey_task.state != ___ROOT_DONE || round->symkey_task.scan_leases != 0)
    return 0;
  for (i=0;i<round->participants;i++)
    {
      ___root_member *member=&round->members[i];
      ___BOOL done;
      ___RC_LOCK(member->rc);
      done=member->rc->owner == member->owner && member->rc->phase == ___RC_FROZEN &&
           member->rc->task.epoch == round->epoch &&
           member->rc->task.state == ___ROOT_DONE && member->rc->task.scan_leases == 0;
      ___RC_UNLOCK(member->rc);
      if (!done || member->global_task.state != ___ROOT_DONE || member->global_task.scan_leases != 0 ||
          member->stack_task.state != ___ROOT_DONE || member->stack_task.scan_leases != 0 ||
          member->bank_task.state != ___ROOT_DONE || member->bank_task.scan_leases != 0) return 0;
    }
  if (!___root_globals_end(&round->globals,ps)) return 0;
  ___RC_LOCK(ps->mem.rc_domain_);
  round->state=___ROOT_ROUND_DRAINING;
  ___RC_UNLOCK(ps->mem.rc_domain_);
  return 1;
}

___BOOL ___root_round_end(___processor_state ps)
{
  ___root_round *round=root_round_for(ps);
  int i;
  if (!root_vm_executor(ps) || round == 0 || round->state != ___ROOT_ROUND_DRAINING ||
      round->participants != round->vm->processor_count) return 0;
  for (i=0;i<round->participants;i++)
    {
      ___root_member *member=&round->members[i];
      ___BOOL restored;
      ___RC_LOCK(member->rc);
      restored=member->owner->mem.rc_domain_ == member->rc &&
               member->owner->context == member->context &&
               member->rc->phase == ___RC_OPEN && member->rc->task.epoch == round->epoch &&
               member->rc->joined_round == round;
      ___RC_UNLOCK(member->rc);
      if (!restored) return 0;
    }
  /* Only the restored collective can drop source/exit leases. Retained audit
   * descriptors cease to be dereference/retirement authority after this cut. */
  for (i=0;i<round->participants;i++)
    {
      ___RC_LOCK(round->members[i].rc);
      round->members[i].rc->joined_round=0;
      ___RC_UNLOCK(round->members[i].rc);
    }
  ___RC_LOCK(ps->mem.rc_domain_);
  round->state=___ROOT_ROUND_IDLE;
  ___RC_UNLOCK(ps->mem.rc_domain_);
  return 1;
}

/* All R observed a known pre-copy refusal. No root task has been claimed,
 * no parity flipped and no source forwarding/payload write began. */
___BOOL ___root_round_refuse(___processor_state ps)
{
  ___root_round *round=root_round_for(ps);
  int i,j;
  if(!root_vm_executor(ps) || !round || round->state!=___ROOT_ROUND_FROZEN ||
     round->collection.decision!=2 || round->collection.census.state!=___GC_PLAN_REFUSED ||
     round->vm_task.state!=___ROOT_EMPTY || round->symkey_task.state!=___ROOT_EMPTY)return 0;
  for(i=0;i<round->participants;i++) {
    ___root_member *m=&round->members[i];
    ___root_task *tasks[4]={&m->rc->task,&m->global_task,&m->stack_task,&m->bank_task};
    if(!round->collection.observed[i] || m->rc->phase!=___RC_FROZEN ||
       m->rc->joined_round!=round || round->globals.shards[i]!=1)return 0;
    for(j=0;j<4;j++)if(tasks[j]->epoch!=round->epoch ||
       tasks[j]->state!=___ROOT_READY || tasks[j]->scan_leases!=1)return 0;
  }
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if(round->vm->mem.globals_snapshot_!=&round->globals ||
     !___GSTATE->mem.global_snapshots) {
    ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);return 0;
  }
  round->vm->mem.globals_snapshot_=0;--___GSTATE->mem.global_snapshots;
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  for(i=0;i<round->participants;i++) {
    ___root_member *m=&round->members[i];
    ___root_task *tasks[4]={&m->rc->task,&m->global_task,&m->stack_task,&m->bank_task};
    ___RC_LOCK(m->rc);
    for(j=0;j<4;j++) {tasks[j]->state=___ROOT_REFUSED;tasks[j]->scan_leases=0;}
    m->rc->joined_round=0;m->rc->phase=___RC_OPEN;
    round->globals.shards[i]=0;___RC_UNLOCK(m->rc);
  }
  ___RC_LOCK(ps->mem.rc_domain_);round->state=___ROOT_ROUND_IDLE;___RC_UNLOCK(ps->mem.rc_domain_);
  return 1;
}
