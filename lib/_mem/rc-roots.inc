/* Frozen RC domain is the source; ___ps remains the existing copy executor. */
___HIDDEN void mark_rc
   ___P((___PSD ___rc_domain *source),
        (___PSV source)
___PSDKR
___rc_domain *source;)
{
  ___PSGET
  ___rc_header *h;
  ___RC_LOCK(source);
  if (source->phase != ___RC_FROZEN)
    { ___RC_UNLOCK(source); rc_contract_error("RC scan requires a frozen source"); return; }
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
  ___RC_UNLOCK(source);
}

#define UNMARKED_MOVABLE(obj) \
((unmarked_typ = ___HD_TYP((unmarked_body=___BODY0(obj))[-1])) == ___MOVABLE0)

#define UNMARKED_STILL(obj) \
(unmarked_typ == ___STILL && \
 unmarked_body[___STILL_MARK - ___STILL_BODY] == -1)

#define UNMARKED(obj) \
(UNMARKED_MOVABLE(obj) || UNMARKED_STILL(obj))


/* End internal memory fragment. */
