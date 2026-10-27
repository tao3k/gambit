/* Frozen RC domain is the source; ___ps remains the existing copy executor. */
___HIDDEN ___BOOL mark_rc
   ___P((___PSD ___rc_domain *source, ___UWORD epoch),
        (___PSV source, epoch)
___PSDKR
___rc_domain *source;
___UWORD epoch;)
{
  ___PSGET
  ___rc_header *h;
  ___RC_LOCK(source);
  if (source->phase != ___RC_FROZEN || source->task.scan_leases != 1 ||
      source->task.origin.source.rc != source ||
      !root_task_matches(&source->task,___ROOT_RC,___ps,epoch) || source->task.state != ___ROOT_CLAIMED)
    { ___RC_UNLOCK(source); return 0; }
  source->task.state=___ROOT_SCANNING;
#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_RC;
#endif
  h=source->head.next;
  while (h != &source->head)
    {
      ___rc_header *next=h->next;
      mark_array (___PSP &h->data, 1);
      h=next;
    }
  source->task.state=___ROOT_SCANNED;
  ___RC_UNLOCK(source);
  return 1;
}

___BOOL ___root_task_scan(___rc_domain *source, ___processor_state executor,
                         ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  if (source == 0 || executor == 0 || executor != ___PSTATE) return 0;
  return mark_rc (___PSP source,epoch);
}

#define UNMARKED_MOVABLE(obj) \
((unmarked_typ = ___HD_TYP((unmarked_body=___BODY0(obj))[-1])) == ___MOVABLE0)

#define UNMARKED_STILL(obj) \
(unmarked_typ == ___STILL && \
 unmarked_body[___STILL_MARK - ___STILL_BODY] == -1)

#define UNMARKED(obj) \
(UNMARKED_MOVABLE(obj) || UNMARKED_STILL(obj))


/* End internal memory fragment. */
