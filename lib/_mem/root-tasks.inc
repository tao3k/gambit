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
  else if (d->phase == ___RC_OPEN && d->owner == executor &&
           d->task.scan_leases == 0 && previous == d->task.epoch &&
           previous != ~___CAST(___UWORD,0) &&
           (d->task.state == ___ROOT_EMPTY || d->task.state == ___ROOT_DONE))
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

/* The VM source is immutable while the existing GC collective is stopped.
 * Task state is coordinator-confined; it is neither queued nor shared. */
void ___root_task_init_vm(___root_task *task, ___UWORD previous)
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

___BOOL ___root_task_publish_vm(___root_task *task, ___virtual_machine_state source,
                               ___processor_state executor, ___UWORD previous,
                               ___UWORD *epoch)
{
  if (task == 0 || epoch == 0 || !root_vm_executor(executor) ||
      source != ___VMSTATE_FROM_PSTATE(executor)) return 0;
  if (task->origin.kind == ___ROOT_VM && task->origin.source.vm == source &&
      task->executor == executor && task->epoch != 0 &&
      previous == task->epoch-1 &&
      task->state >= ___ROOT_READY && task->state <= ___ROOT_DONE)
    { *epoch=task->epoch; return 1; }
  if (task->origin.kind != ___ROOT_NONE || task->state != ___ROOT_EMPTY ||
      task->scan_leases != 0 || previous != task->epoch ||
      previous == ~___CAST(___UWORD,0)) return 0;
  task->origin.kind=___ROOT_VM; task->origin.source.vm=source;
  task->executor=executor; task->epoch=previous+1;
  task->scan_leases=1; task->state=___ROOT_READY;
  *epoch=task->epoch;
  return 1;
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
