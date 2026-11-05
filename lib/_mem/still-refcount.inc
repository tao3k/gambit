#line 1440 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/*
 * '___still_obj_refcount_inc (obj)' increments the reference count of
 * the still object 'obj'.
 */

___EXP_FUNC(void,___still_obj_refcount_inc)
   ___P((___WORD obj),
        (obj)
___WORD obj;)
{
  ___BODY0(obj)[___STILL_REFCOUNT-___STILL_BODY]++;
}


/*
 * '___still_obj_refcount_dec (obj)' decrements the reference count of
 * the still object 'obj'.
 */

___EXP_FUNC(void,___still_obj_refcount_dec)
   ___P((___WORD obj),
        (obj)
___WORD obj;)
{
  ___BODY0(obj)[___STILL_REFCOUNT-___STILL_BODY]--;
}


/*
 * '___still_obj_refcount (obj)' returns the reference count of
 * the still object 'obj'.
 */

___EXP_FUNC(___WORD,___still_obj_refcount)
   ___P((___WORD obj),
        (obj)
___WORD obj;)
{
  return ___BODY0(obj)[___STILL_REFCOUNT-___STILL_BODY];
}


/* End internal memory fragment. */
