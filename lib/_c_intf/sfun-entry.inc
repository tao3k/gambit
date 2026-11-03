/* Generated C-to-Scheme activation. The existing lifecycle record owns one
 * RC span, its scan borrow and marker until this physical C extent exits.
 * No per-argument allocation or independently registered identity table. */
___EXP_FUNC(___SCMOBJ,___begin_sfun)
   ___P((___processor_state ps, ___WORD nargs, ___SCMOBJ proc, void **scope), ())
{
  ___activation_record *record;
  const ___SCMOBJ *source=0;
  void *self=0;
  if (nargs<0) return ___FIX(___UNKNOWN_ERR);
  *scope=0;
  record=___lifecycle_marker_prepare(ps);
  if (!record) return ___FIX(___UNKNOWN_ERR);
  record->kind=___ACTIVATION_SFUN_ROOTED;
  /* Reuse Gambit's existing pre-marker PERM predicate. With no arguments
   * there is no moving payload to register; the admitted code/VM lifetime
   * retains this immovable procedure. Kind distinguishes it from a marker. */
  if (nargs==0 && proc!=___FAL && ___TESTTYPE(proc,___tSUBTYPED) &&
      ___HD_TYP(___SUBTYPED_HEADER(proc))==___PERM) {
    record->marker=proc;
    record->kind=___ACTIVATION_SFUN_PERMANENT;
    *scope=record;
    return ___FIX(___NO_ERR);
  }
  if (proc==___FAL) {
    self=___c_closure_self();
    source=___borrow_rc_root(ps,self);
    if (!source) {___lifecycle_marker_abort(record);return ___FIX(___UNKNOWN_ERR);}
  }
  record->roots=___alloc_rc_roots(ps,___CAST(___SIZE_T,nargs));
  if (record->roots && ___try_set_data_rc(ps,record->roots,source ? *source : proc) &&
      ___borrow_rc_root(ps,record->roots)) {
    if (source) ___return_rc_root(self);
    *scope=record;
    return ___FIX(___NO_ERR);
  }
  if (source) ___return_rc_root(self);
  /* No bank borrow was accepted on failure. Abort must not return one. */
  if (record->roots) {___release_rc(record->roots);record->roots=0;}
  ___lifecycle_marker_abort(record);
  return ___FIX(___SFUN_HEAP_OVERFLOW_ERR);
}

___EXP_FUNC(___SCMOBJ,___sfun_arg)
   ___P((___processor_state ps, void *scope, ___WORD index,
         ___SCMOBJ value), ())
{
  ___activation_record *record=___CAST(___activation_record*,scope);
  if (!record || record->owner!=ps || !record->roots || index<1)
    return ___FIX(___UNKNOWN_ERR);
  return ___FIX(___store_rc_root(ps,record->roots,___CAST(___SIZE_T,index),value)
               ? ___NO_ERR : ___UNKNOWN_ERR);
}

___EXP_FUNC(___SCMOBJ,___sfun_marker)
   ___P((___processor_state ps, void *scope, ___SCMOBJ *marker), ())
{
  ___activation_record *record=___CAST(___activation_record*,scope);
  ___SCMOBJ result;
  ___rc_header *h;
  if (!record || record->owner!=ps || ps!=___PSTATE)
    return ___FIX(___UNKNOWN_ERR);
  if (record->kind==___ACTIVATION_SFUN_PERMANENT)
    result=make_sfun_stack_marker(ps,marker,record->marker,0);
  else if (record->kind==___ACTIVATION_SFUN_ROOTED && record->roots) {
    h=___CAST(___rc_header*,record->roots)-1;
    result=make_sfun_stack_marker(ps,marker,___TRU,&h->data);
  } else return ___FIX(___UNKNOWN_ERR);
  if (result==___FIX(___NO_ERR)) {
    record->marker=*marker;
    record->kind=___ACTIVATION_SFUN_ACTIVE;
  }
  return result;
}

___EXP_FUNC(___SCMOBJ,___call_sfun)
   ___P((___processor_state ps, void *scope), ())
{
  ___processor_state ___ps=ps;
  ___activation_record *record=___CAST(___activation_record*,scope);
  ___rc_header *h;
  ___rc_domain *d;
  ___SIZE_T i;
  if (!record || record->owner!=ps || ps!=___PSTATE ||
      record->kind!=___ACTIVATION_SFUN_ACTIVE) return ___FIX(___UNKNOWN_ERR);
  if (!record->roots)
    return ___call(___PSA(ps) 0,___VECTORELEM(record->marker,0),record->marker);
  h=___CAST(___rc_header*,record->roots)-1;d=h->domain;
  ___RC_LOCK(d);
  if (d!=ps->mem.rc_domain_ || d->owner!=ps || d->phase!=___RC_OPEN ||
      d->joined_round || h->root_borrows!=1) {
    ___RC_UNLOCK(d);return ___FIX(___UNKNOWN_ERR);
  }
  /* Same existing call-frame reserve and arity contract as ___call. No GC,
   * conversion, callback or poll can observe the partial argument prefix. */
  for (i=0;i<h->root_count;i++)
    ___PSSTK(___FRAME_SPACE(2)+i+1)=___CAST(___SCMOBJ*,record->roots)[i];
  ___RC_UNLOCK(d);
  return ___call(___PSA(ps) h->root_count,
                ___VECTORELEM(record->marker,0),record->marker);
}

___EXP_FUNC(void,___end_sfun)
   ___P((___processor_state ps, void *scope), ())
{
  ___activation_record *record=___CAST(___activation_record*,scope);
  if (!record || record->owner!=ps || ps!=___PSTATE) return;
  if (___activation_marker_live(record)) {
    ___VECTORELEM(record->marker,0)=___FAL;
    ___still_obj_refcount_dec(record->marker);
    record->marker=___FAL;
  }
  ___lifecycle_marker_abort(record);
}
