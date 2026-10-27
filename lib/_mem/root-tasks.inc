/* RC publication and source freezing share one mutex/linearization point.
 * Completion releases a scan lease, never the enclosing round's authority. */
___HIDDEN ___BOOL root_task_matches(___rc_domain *d,
                                  ___processor_state executor, ___UWORD epoch)
{
  return d->task.source == d && d->task.executor == executor &&
         d->task.epoch == epoch;
}

___BOOL ___root_task_publish(___rc_domain *d, ___processor_state executor,
                            ___UWORD previous, ___UWORD *epoch)
{
  ___BOOL accepted=0;
  if (d == 0 || executor == 0 || executor != ___PSTATE || epoch == 0) return 0;
  ___RC_LOCK(d);
  /* A retry may recover this publication; it cannot create another lease. */
  if (d->phase == ___RC_FROZEN && d->task.epoch != 0 &&
      previous == d->task.epoch-1 && d->task.executor == executor &&
      d->task.state >= ___ROOT_READY && d->task.state <= ___ROOT_DONE)
    accepted=1;
  else if (d->phase == ___RC_OPEN && d->owner == executor &&
           d->scan_leases == 0 && previous == d->task.epoch &&
           previous != ~___CAST(___UWORD,0) &&
           (d->task.state == ___ROOT_EMPTY || d->task.state == ___ROOT_DONE))
    {
      d->task.source=d; d->task.executor=executor;
      d->task.epoch=previous+1; d->task.state=___ROOT_READY;
      d->scan_leases=1;
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
  if (d->phase == ___RC_FROZEN && d->scan_leases == 1 &&
      root_task_matches(d,executor,epoch) && d->task.state == ___ROOT_READY)
    { d->task.state=___ROOT_CLAIMED; accepted=1; }
  ___RC_UNLOCK(d);
  return accepted;
}

___BOOL ___root_task_finish(___rc_domain *d, ___processor_state executor,
                           ___UWORD epoch)
{
  ___BOOL accepted=0;
  if (d == 0 || executor == 0 || executor != ___PSTATE) return 0;
  ___RC_LOCK(d);
  if (d->phase == ___RC_FROZEN && root_task_matches(d,executor,epoch))
    {
      if (d->task.state == ___ROOT_SCANNED && d->scan_leases == 1)
        { d->task.state=___ROOT_DONE; d->scan_leases=0; accepted=1; }
      else if (d->task.state == ___ROOT_DONE && d->scan_leases == 0)
        accepted=1; /* Known completion reply; no repeated decrement. */
    }
  ___RC_UNLOCK(d);
  return accepted;
}

___BOOL ___root_task_completed(___rc_domain *d, ___processor_state executor,
                              ___UWORD epoch)
{
  ___BOOL done;
  if (d == 0 || executor == 0 || executor != ___PSTATE) return 0;
  ___RC_LOCK(d);
  done=root_task_matches(d,executor,epoch) &&
       d->task.state == ___ROOT_DONE && d->scan_leases == 0;
  ___RC_UNLOCK(d);
  return done;
}
