#line 3918 ___MEM_SOURCE_FILE
___HIDDEN void mark_rc
   ___P((___PSD ___rc_header *source),
        (___PSV source)
___PSDKR
___rc_header *source;)
{
  ___PSGET
  ___rc_header *h = source->next;

#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_RC;
#endif

  while (h != source)
    {
      ___rc_header *next = h->next;
      mark_array (___PSP &h->data, 1);
      h = next;
    }
}


#define UNMARKED_MOVABLE(obj) \
((unmarked_typ = ___HD_TYP((unmarked_body=___BODY0(obj))[-1])) == ___MOVABLE0)

#define UNMARKED_STILL(obj) \
(unmarked_typ == ___STILL && \
 unmarked_body[___STILL_MARK - ___STILL_BODY] == -1)

#define UNMARKED(obj) \
(UNMARKED_MOVABLE(obj) || UNMARKED_STILL(obj))


/* End internal memory fragment. */
