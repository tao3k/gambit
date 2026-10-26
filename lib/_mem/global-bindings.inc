#line 1228 ___MEM_SOURCE_FILE
void ___glo_list_setup ___PVOID
{
  int i;

  ___GSTATE->mem.glo_list.count = 0;

  for (i=___GLO_SUBLIST_COUNT-1; i>=0; i--)
    {
      ___glo_sublist_struct *sl = &___GSTATE->mem.glo_list.sublist[i];
      sl->head = 0;
      sl->tail = 0;
    }
}


void ___glo_list_add
   ___P((___glo_struct *glo),
        (glo)
___glo_struct *glo;)
{
  int i = ___GSTATE->mem.glo_list.count++ % ___GLO_SUBLIST_COUNT;
  ___glo_sublist_struct *sl = &___GSTATE->mem.glo_list.sublist[i];

  glo->next = 0;

  if (sl->head == 0)
    sl->head = glo;
  else
    sl->tail->next = glo;

  sl->tail = glo;
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

  for (i=___GLO_SUBLIST_COUNT-1; i>=0; i--)
    {
      ___glo_sublist_struct *sl = &___GSTATE->mem.glo_list.sublist[i];
      ___glo_struct *probe = sl->head;
      int probe_depth = 0;

      if (prm)
        {
          while (probe != 0 && ___PRMCELL(probe->prm) != obj)
            {
              probe = probe->next;
              if (++probe_depth > glo_depth) break;
            }
        }
      else
        {
          while (probe != 0 && ___GLOCELL(probe->val) != obj)
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

  return glo;
}


___SCMOBJ ___glo_struct_to_global_var
   ___P((___glo_struct *glo),
        (glo)
___glo_struct *glo;)
{
  ___SCMOBJ result = ___FAL;

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
  if (___GLOBALVARSTRUCT(sym) == 0)
    {
      ___glo_struct *glo = ___CAST(___glo_struct*,
                                   alloc_mem_aligned_perm
                                     (___WORDS(sizeof (___glo_struct)),
                                      1,
                                      0));

      if (glo == 0)
        return ___FIX(___HEAP_OVERFLOW_ERR);

#ifdef ___SINGLE_VM
      glo->val = ___UNB1;
#else
      glo->val = ___GSTATE->mem.glo_list.count;
#endif

      ___glo_list_add (glo);

      ___PRMCELL(glo->prm) = ___FAL;

      ___SYMBOL_GLOBAL_FIELD(sym) = ___CAST(___SCMOBJ,glo);
    }

  return sym;
}


#ifdef ___USE_find_global_var_bound_to

___SCMOBJ ___find_global_var_bound_to
   ___P((___SCMOBJ val),
        (val)
___SCMOBJ val;)
{
  ___SCMOBJ sym = ___NUL;
  int i;

  for (i = ___INT(___VECTORLENGTH(___GSTATE->symbol_table)) - 1; i>0; i--)
    {
      sym = ___VECTORELEM(___GSTATE->symbol_table, i);

      while (sym != ___NUL)
       {
          ___glo_struct *g = ___GLOBALVARSTRUCT(sym);

          if (g != 0 &&
              (___PRMCELL(g->prm) == val || ___GLOCELL(g->val) == val))
            {
              i = 0;
              break;
            }

          sym = ___SYMKEY_NEXT_FIELD(sym);
        }
    }

  return sym;
}

#endif


/* End internal memory fragment. */
