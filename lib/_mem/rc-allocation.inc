#line 669 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation of reference counted blocks of memory. */

___HIDDEN void setup_rc
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  rc_head.prev = &rc_head;
  rc_head.next = &rc_head;
  rc_head.refcount = 1;
  rc_head.data = ___FAL;
}

___HIDDEN void cleanup_rc
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___rc_header *h = rc_head.next;

  rc_head.prev = &rc_head;
  rc_head.next = &rc_head;

  while (h != &rc_head)
    {
      ___rc_header *next = h->next;
      ___FREE_MEM(h);
      h = next;
    }
}


___EXP_FUNC(void*,___alloc_rc_no_register)
   ___P((___SIZE_T bytes),
        (bytes)
___SIZE_T bytes;)
{
  ___rc_header *h = ___CAST(___rc_header*,
                            ___ALLOC_MEM(bytes + sizeof (___rc_header)));

  if (h != 0)
    {
      h->refcount = 1;
      h->data = ___FAL;

      return ___CAST(void*,h+1);
    }

  return 0;
}


___EXP_FUNC(void,___register_rc)
   ___P((___PSD
         void *ptr),
        (___PSV
         ptr)
___PSDKR
void *ptr;)
{
  ___PSGET
  ___rc_header *h = ___CAST(___rc_header*, ptr) - 1;
  ___rc_header *head = &rc_head;
  ___rc_header *tail = head->prev;

  h->prev = tail;
  h->next = head;
  head->prev = h;
  tail->next = h;
}


___EXP_FUNC(void*,___alloc_rc)
   ___P((___PSD
         ___SIZE_T bytes),
        (___PSV
         bytes)
___PSDKR
___SIZE_T bytes;)
{
  ___PSGET
  void *ptr = ___alloc_rc_no_register (bytes);

  if (ptr != 0) ___register_rc (___PSP ptr);

  return ptr;
}


___EXP_FUNC(void,___release_rc)
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  if (ptr != 0)
    {
      ___rc_header *h = ___CAST(___rc_header*,ptr) - 1;

      if (--h->refcount == 0)
        {
          ___rc_header *prev = h->prev;
          ___rc_header *next = h->next;

          next->prev = prev;
          prev->next = next;

          ___FREE_MEM(h);
        }
    }
}


___EXP_FUNC(void,___addref_rc)
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  if (ptr != 0)
    {
      ___rc_header *h = ___CAST(___rc_header*,ptr) - 1;
      h->refcount++;
    }
}


___EXP_FUNC(int,___refcount_rc)
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  ___rc_header *h = ___CAST(___rc_header*,ptr) - 1;
  return h->refcount;
}


___EXP_FUNC(___SCMOBJ,___data_rc)
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  ___rc_header *h = ___CAST(___rc_header*,ptr) - 1;
  return h->data;
}


___EXP_FUNC(void,___set_data_rc)
   ___P((void *ptr,
         ___SCMOBJ val),
        (ptr,
         val)
void *ptr;
___SCMOBJ val;)
{
  ___rc_header *h = ___CAST(___rc_header*,ptr) - 1;
  h->data = val;
}


/* End internal memory fragment. */
