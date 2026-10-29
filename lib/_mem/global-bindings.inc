#line 1228 ___MEM_SOURCE_FILE
___HIDDEN ___BOOL global_bootstrap_owner(void);

/* Immutable image code and VM-local mutable overrides are different sources.
 * Slot/bit addresses are stable through the owning VM lifetime. Presence
 * publication is serialized with module rebinding; readers need no mutex. */
___HIDDEN ___SCMOBJ *primitive_cell(___virtual_machine_state vm, ___glo_struct *g)
{
#ifdef ___SINGLE_VM
  return &g->primitive_value;
#else
  if (vm == 0 || vm->glos == 0 || g->val < 0 || g->val >= ___GLOBALS_CAPACITY) return 0;
  return vm->glos+___GLOBALS_CAPACITY+g->val;
#endif
}
___HIDDEN ___WORD *primitive_flag(___virtual_machine_state vm, ___glo_struct *g)
{
#ifdef ___SINGLE_VM
  return &g->primitive_set;
#else
  return vm->glos+2*___GLOBALS_CAPACITY+g->val/___WORD_WIDTH;
#endif
}
___HIDDEN ___UWORD primitive_mask(___glo_struct *g)
{
#ifdef ___SINGLE_VM
  return 1;
#else
  return ___CAST(___UWORD,1) << (g->val % ___WORD_WIDTH);
#endif
}
___HIDDEN ___SCMOBJ primitive_value(___virtual_machine_state vm, ___glo_struct *g)
{
  ___SCMOBJ *cell=primitive_cell(vm,g);
  if (cell != 0 && (___LOAD_GLOBAL_WORD(primitive_flag(vm,g)) & primitive_mask(g)))
    return ___LOAD_GLOBAL_WORD(cell);
  return ___PRMCELL(g->prm);
}
___EXP_FUNC(___SCMOBJ,___primitive_ref)
   ___P((___processor_state ps, ___glo_struct *g), (ps,g)
___processor_state ps; ___glo_struct *g;)
{
  if (g == 0 || !root_writer_open(ps))
    { rc_contract_error("Primitive read outside current root ownership"); return ___FAL; }
  return primitive_value(___VMSTATE_FROM_PSTATE(ps),g);
}
___EXP_FUNC(void,___store_primitive)
   ___P((___processor_state ps, ___glo_struct *g, ___SCMOBJ value), (ps,g,value)
___processor_state ps; ___glo_struct *g; ___SCMOBJ value;)
{
  ___virtual_machine_state vm;
  ___SCMOBJ *cell;
  ___WORD *flag;
  if (g == 0 || !root_writer_open(ps))
    { rc_contract_error("Primitive store outside open root ownership"); return; }
  vm=___VMSTATE_FROM_PSTATE(ps); cell=primitive_cell(vm,g);
  if (cell == 0) { rc_contract_error("Primitive storage is not initialized"); return; }
  flag=primitive_flag(vm,g);
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  ___PUBLISH_GLOBAL_WORD(cell,value);
  ___PUBLISH_GLOBAL_WORD(flag,___LOAD_GLOBAL_WORD(flag) | primitive_mask(g));
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
}
/* Only generated module code publishes this image template. A runtime module
 * rebind resets overrides in the loading VM, not in unrelated VM instances.
 * Clear presence only: a concurrent reader that saw the old bit must still
 * see a valid old value. The next owning GC removes that inactive root. */
___EXP_FUNC(void,___bind_primitive)
   ___P((___processor_state ps, ___glo_struct *g, ___SCMOBJ code), (ps,g,code)
___processor_state ps; ___glo_struct *g; ___SCMOBJ code;)
{
  ___BOOL bootstrap;
  if (g == 0 || (___MEM_ALLOCATED(code) &&
      ___HD_TYP(___HEADER(code)) != ___PERM))
    { rc_contract_error("Module primitive template must be immutable image code"); return; }
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  bootstrap=___GSTATE->mem.global_bootstrap;
  if (!(bootstrap ? global_bootstrap_owner() : root_writer_open(ps)))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
      rc_contract_error("Module primitive publication outside root ownership"); return; }
  ___PUBLISH_GLOBAL_WORD(&g->prm,code);
  if (!bootstrap)
    {
      ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
      ___WORD *flag=primitive_flag(vm,g);
      ___PUBLISH_GLOBAL_WORD(flag,___LOAD_GLOBAL_WORD(flag) & ~primitive_mask(g));
    }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
}

/* Ordinary global stores are confined to the actual current processor. No
 * allocation, callback, poll or safepoint occurs between this check and store.
 * The owner cannot simultaneously store and acknowledge the GC collective;
 * its complete root view precedes root_round_begin. The collective supplies
 * the publication edge, not a per-store mutex or an unsynchronized count read.
 * Domain/VM lifetime and exclusive current-processor binding preexist lookup.
 * Cross-thread native stores must use an owner entry, never borrow this fast
 * path by supplying someone else's processor pointer. */
___BOOL ___try_store_global(___processor_state ps, ___glo_struct *global,
                             ___SCMOBJ value)
{
  if (global == 0 || !root_writer_open(ps)) return 0;
  ___PUBLISH_GLOBAL_WORD(&___GLOCELL_IN_VM((___VMSTATE_FROM_PSTATE(ps)),global->val),value);
  return 1;
}

___EXP_FUNC(void,___store_global)
   ___P((___processor_state ps, ___glo_struct *global, ___SCMOBJ value),
        (ps,global,value)
___processor_state ps;
___glo_struct *global;
___SCMOBJ value;)
{
  if (!___try_store_global(ps,global,value))
    rc_contract_error("Ordinary global store outside open root ownership");
}

/* Lock order: current RC source -> global_gate -> permanent_gate.
 * No Scheme allocation, callback, collector barrier or native join under them. */
___HIDDEN ___BOOL global_bootstrap_owner(void)
{
#ifdef ___USE_POSIX_THREAD_SYSTEM
  return pthread_equal(___GSTATE->mem.global_bootstrap_owner.thread_id,pthread_self());
#else
#ifdef ___USE_WIN32_THREAD_SYSTEM
  return ___GSTATE->mem.global_bootstrap_owner.thread_id==GetCurrentThreadId();
#else
  return 1;
#endif
#endif
}

___SCMOBJ ___glo_list_setup ___PVOID
{
  int i;
#ifdef ___USE_POSIX_THREAD_SYSTEM
  if (!___MUTEX_INIT(___GSTATE->mem.global_gate)) return ___FIX(___UNKNOWN_ERR);
  if (!___MUTEX_INIT(___GSTATE->mem.permanent_gate)) {
    ___MUTEX_DESTROY(___GSTATE->mem.global_gate); return ___FIX(___UNKNOWN_ERR);
  }
#else
  ___MUTEX_INIT(___GSTATE->mem.global_gate);
  ___MUTEX_INIT(___GSTATE->mem.permanent_gate);
#endif
  ___GSTATE->mem.global_bootstrap=1;
  ___GSTATE->mem.global_snapshots=0;
  ___thread_init_from_self(&___GSTATE->mem.global_bootstrap_owner);
  ___GSTATE->mem.glo_list.count=0;
  for (i=0;i<___GLO_SUBLIST_COUNT;i++) {
    ___GSTATE->mem.glo_list.sublist[i].head=0;
    ___GSTATE->mem.glo_list.sublist[i].tail=0;
  }
  return ___FIX(___NO_ERR);
}

void ___glo_list_open ___PVOID
{
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  ___GSTATE->mem.global_bootstrap=0;
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
}

___HIDDEN ___BOOL global_room(void)
{
#ifdef ___SINGLE_VM
  return ___GSTATE->mem.glo_list.count < INT_MAX;
#else
  return ___GSTATE->mem.glo_list.count < ___GLOBALS_CAPACITY;
#endif
}

___HIDDEN void global_append(___glo_struct *glo)
{
  ___SIZE_T index=___GSTATE->mem.glo_list.count;
  ___glo_sublist_struct *sl=&___GSTATE->mem.glo_list.sublist[index%___GLO_SUBLIST_COUNT];
#ifndef ___SINGLE_VM
  glo->val=index;
#endif
  glo->next=0;
  if (sl->head==0) sl->head=glo; else sl->tail->next=glo;
  sl->tail=glo;
  ___GSTATE->mem.glo_list.count=index+1;
}

___SCMOBJ ___glo_list_add(___glo_struct *glo)
{
  ___SCMOBJ result=___FIX(___IMPL_LIMIT_ERR);
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (___GSTATE->mem.global_bootstrap && global_bootstrap_owner() && global_room()) {
    global_append(glo); result=___FIX(___NO_ERR);
  }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}


___glo_struct *___glo_list_search_obj
   ___P((___PSD
         ___SCMOBJ obj,
         ___BOOL prm),
        (___PSV
         obj,
         prm)
___PSDKR
___SCMOBJ obj;
___BOOL prm;)
{
  ___PSGET

  ___glo_struct *glo = 0;
  int glo_depth = 999999999;
  int i;

  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  for (i=___GLO_SUBLIST_COUNT-1; i>=0; i--)
    {
      ___glo_sublist_struct *sl = &___GSTATE->mem.glo_list.sublist[i];
      ___glo_struct *probe = sl->head;
      int probe_depth = 0;

      if (prm)
        {
          while (probe != 0 && primitive_value(___VMSTATE_FROM_PSTATE(___ps),probe) != obj)
            {
              probe = probe->next;
              if (++probe_depth > glo_depth) break;
            }
        }
      else
        {
          while (probe != 0 && ___LOAD_GLOBAL_WORD(&___GLOCELL(probe->val)) != obj)
            {
              probe = probe->next;
              if (++probe_depth > glo_depth) break;
            }
        }

      if (probe != 0)
        {
          if (glo == 0 || probe_depth <= glo_depth)
            {
              glo = probe;
              glo_depth = probe_depth;
            }
        }
    }

  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return glo;
}


___SCMOBJ ___glo_struct_to_global_var
   ___P((___glo_struct *glo),
        (glo)
___glo_struct *glo;)
{
  ___SCMOBJ result = ___FAL;

  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (glo != 0)
    {
      int len = ___INT(___VECTORLENGTH(___GSTATE->symbol_table));
      int i;

      for (i=1; i<len; i++)
        {
          ___SCMOBJ probe = ___VECTORELEM(___GSTATE->symbol_table, i);

          while (probe != ___NUL)
            {
              if (___GLOBALVARSTRUCT(probe) == glo)
                {
                  result = probe;
                  goto end_search;
                }
              probe = ___SYMKEY_NEXT_FIELD(probe);
            }
        }
    end_search:;
    }

  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}


___SCMOBJ ___obj_to_global_var
   ___P((___PSD
         ___SCMOBJ obj,
         ___BOOL prm),
        (___PSV
         obj,
         prm)
___PSDKR
___SCMOBJ obj;
___BOOL prm;)
{
  ___PSGET

  /*
   * Find the global variable that is bound to the object obj.
   * If prm is true then the prm field of the global variable
   * is checked, otherwise the val field is checked.
   */

  return ___glo_struct_to_global_var (___glo_list_search_obj (___PSP obj, prm));
}


___SCMOBJ ___make_global_var
   ___P((___SCMOBJ sym),
        (sym)
___SCMOBJ sym;)
{
  ___processor_state ps=___GET_REAL_PSTATE();
  ___rc_domain *domain;
  ___SCMOBJ result=sym;
#ifdef ___SUPPORT_PSTATE_BIND
  if (ps!=0) ps=ps->pstate_binding;
#endif
  domain=ps==0?0:ps->mem.rc_domain_;
  if (domain!=0) ___RC_LOCK(domain);
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (___GLOBALVARSTRUCT(sym)==0) {
    if (!(domain!=0 ? domain->owner==ps && domain->joined_round==0 && domain->phase==___RC_OPEN :
          ___GSTATE->mem.global_bootstrap && global_bootstrap_owner()) ||
        !global_room()) result=___FIX(___IMPL_LIMIT_ERR);
    else {
      ___glo_struct *glo=___CAST(___glo_struct*,alloc_mem_aligned_perm(
        ___WORDS(sizeof(___glo_struct)),1,0));
      if (glo==0) result=___FIX(___HEAP_OVERFLOW_ERR);
      else {
#ifdef ___SINGLE_VM
        glo->val=___UNB1;
#endif
        glo->prm=___FAL; /* unpublished shared code template */
#ifdef ___SINGLE_VM
        glo->primitive_value=___FAL; glo->primitive_set=0;
#endif
        global_append(glo);
        ___PUBLISH_GLOBAL_WORD(&___SYMBOL_GLOBAL_FIELD(sym),___CAST(___SCMOBJ,glo));
      }
    }
  }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  if (domain!=0) ___RC_UNLOCK(domain);
  return result;
}


#ifdef ___USE_find_global_var_bound_to

___SCMOBJ ___find_global_var_bound_to
   ___P((___SCMOBJ val),
        (val)
___SCMOBJ val;)
{
  ___SCMOBJ sym = ___NUL;
  int i;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);

  for (i = ___INT(___VECTORLENGTH(___GSTATE->symbol_table)) - 1; i>0; i--)
    {
      sym = ___VECTORELEM(___GSTATE->symbol_table, i);

      while (sym != ___NUL)
       {
          ___glo_struct *g = ___GLOBALVARSTRUCT(sym);

          if (g != 0 &&
              (primitive_value(___VMSTATE_FROM_PSTATE(___ps),g) == val || ___LOAD_GLOBAL_WORD(&___GLOCELL(g->val)) == val))
            {
              i = 0;
              break;
            }

          sym = ___SYMKEY_NEXT_FIELD(sym);
        }
    }

  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return sym;
}

#endif


/* End internal memory fragment. */
