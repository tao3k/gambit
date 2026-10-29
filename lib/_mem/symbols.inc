#line 1818 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/*
 * Routines to manage symbol table, keyword table and global variable
 * table.
 */

/*
 * The hashing functions '___hash_UTF_8_string (str)' and
 * '___hash_scheme_string (str)' must compute the same value as the
 * function 'targ-hash' in the file gsc/_t-c-3.scm.  A fixnum error
 * code is returned when there is an error.
 *
 * These functions implement an adaptation of the FNV1a hash algorithm
 * (see https://tools.ietf.org/html/draft-eastlake-fnv-12).  Instead
 * of iterating over bytes, an iteration over Unicode code points is
 * used.  This will give the same result if the string contains only
 * ISO-8859-1 characters.  However, only the lower 29 bits of the
 * standard 32 bit FNV1a algorithm are returned so the result fits in
 * a fixnum on a 32 bit word architecture.
 */

#define FN1a_prime        0x01000193
#define FN1a_offset_basis 0x011C9DC5

#define HASH_STEP(h,c) (((h)^(c)) * FN1a_prime) & ___MAX_FIX32

/* Both the Scheme count cell and the existing C index operations must fit. */
#define SYMKEY_COUNT_LIMIT ((___MAX_FIX < INT_MAX) ? ___MAX_FIX : INT_MAX)

___SCMOBJ ___hash_UTF_8_string
   ___P((___UTF_8STRING str),
        (str)
___UTF_8STRING str;)
{
  ___UM32 h = FN1a_offset_basis;
  ___UTF_8STRING p = str;
  ___UCS_4 c;

  for (;;)
    {
      ___UTF_8STRING start = p;
      ___UTF_8_get_var (&p, c);
      if (p == start || c > ___MAX_CHR)
        return ___FIX(___CTOS_UTF_8STRING_ERR);
      if (c == 0)
        break;
      h = HASH_STEP(h,c);
    }

  return ___FIX(h);
}


___SCMOBJ ___hash_scheme_string
   ___P((___SCMOBJ str),
        (str)
___SCMOBJ str;)
{
  ___SIZE_T i, n = ___INT(___STRINGLENGTH(str));
  ___UM32 h = FN1a_offset_basis;

  for (i=0; i<n; i++)
    h = HASH_STEP(h,___ORD(___STRINGREF(str,___FIX(i))));

  return ___FIX(h);
}


___HIDDEN ___SCMOBJ symkey_table
   ___P((unsigned int subtype),
        (subtype)
unsigned int subtype;)
{
  switch (subtype)
    {
    case ___sKEYWORD:
      return ___GSTATE->keyword_table;
    default: /* assume ___sSYMBOL */
      return ___GSTATE->symbol_table;
    }
}


___HIDDEN ___BOOL symkey_table_permanent(___SCMOBJ tbl)
{
  return ___MEM_ALLOCATED(tbl) && ___HD_TYP(___HEADER(tbl))==___PERM &&
         ___HD_SUBTYPE(___HEADER(tbl))==___sVECTOR &&
         ___INT(___VECTORLENGTH(tbl))>1;
}

___HIDDEN void symkey_table_set
   ___P((unsigned int subtype,
         ___SCMOBJ new_table),
        (subtype,
         new_table)
unsigned int subtype;
___SCMOBJ new_table;)
{
  switch (subtype)
    {
    case ___sKEYWORD:
      ___GSTATE->keyword_table = new_table;
      break;
    default: /* assume ___sSYMBOL */
      ___GSTATE->symbol_table = new_table;
      break;
    }
}


___HIDDEN ___SCMOBJ alloc_symkey_table
   ___P((unsigned int subtype,
         ___SIZE_TS length),
        (subtype,
         length)
unsigned int subtype;
___SIZE_TS length;)
{
  ___SCMOBJ tbl;
  if (length<1 || length>=SYMKEY_COUNT_LIMIT) return ___FIX(___HEAP_OVERFLOW_ERR);
  tbl=___make_vector (NULL, length+1, ___NUL);

  if (!___FIXNUMP(tbl))
    ___VECTORELEM(tbl, 0) = ___FIX(0);

  return tbl;
}


___HIDDEN void symkey_intern
   ___P((___SCMOBJ symkey),
        (symkey)
___SCMOBJ symkey;)
{
  unsigned int subtype = ___INT(___SUBTYPE(symkey));
  ___SCMOBJ tbl = symkey_table (subtype);
  if (!symkey_table_permanent(tbl) || !___FIXNUMP(___VECTORELEM(tbl,0)) ||
      ___INT(___VECTORELEM(tbl,0))<0 ||
      ___VECTORELEM(tbl,0)>=___FIX(SYMKEY_COUNT_LIMIT))
    rc_contract_error("symkey insertion outside native permanent table bound");
  int i = ___INT(___SYMKEY_HASH_FIELD(symkey))
          % (___INT(___VECTORLENGTH(tbl)) - 1)
          + 1;

  /*
   * Add symbol/keyword to the appropriate list.
   */

  ___SYMKEY_NEXT_FIELD(symkey) = ___VECTORELEM(tbl, i);
  ___VECTORELEM(tbl, i) = symkey;

  ___VECTORELEM(tbl, 0) = ___FIXADD(___VECTORELEM(tbl, 0), ___FIX(1));

  /*
   * Grow and rehash the table when it is too loaded (above an average
   * list length of 4).
   */

  if ((___INT(___VECTORELEM(tbl,0))-1)/4 >= ___INT(___VECTORLENGTH(tbl)) &&
      ___INT(___VECTORLENGTH(tbl))-1 <= (INT_MAX-1)/2)
    {
      int new_len = (___INT(___VECTORLENGTH(tbl))-1) * 2;
      ___SCMOBJ newtbl = alloc_symkey_table (subtype, new_len);

      if (!___FIXNUMP(newtbl))
        {
          for (i=___INT(___VECTORLENGTH(tbl))-1; i>0; i--)
            {
              ___SCMOBJ probe = ___VECTORELEM(tbl, i);

              while (probe != ___NUL)
                {
                  ___SCMOBJ symkey = probe;
                  int j = ___INT(___SYMKEY_HASH_FIELD(symkey))%new_len + 1;

                  probe = ___SYMKEY_NEXT_FIELD(symkey);
                  ___SYMKEY_NEXT_FIELD(symkey) = ___VECTORELEM(newtbl, j);
                  ___VECTORELEM(newtbl,j) = symkey;
                }
            }

          ___VECTORELEM(newtbl, 0) = ___VECTORELEM(tbl, 0);

          symkey_table_set (subtype, newtbl);
        }
    }
}


___HIDDEN ___SCMOBJ symkey_new
   ___P((___SCMOBJ name, /* name must be a permanent object */
         unsigned int subtype),
        (name,
         subtype)
___SCMOBJ name;
unsigned int subtype;)
{
  ___SCMOBJ obj;
  ___SCMOBJ tbl;

  tbl=symkey_table(subtype);
  if (!symkey_table_permanent(tbl) ||
      !___MEM_ALLOCATED(name) || ___HD_TYP(___HEADER(name))!=___PERM ||
      ___VECTORELEM(tbl,0)>=___FIX(SYMKEY_COUNT_LIMIT))
    return ___FIX(___HEAP_OVERFLOW_ERR);

  switch (subtype)
    {
    case ___sKEYWORD:
      obj = ___alloc_scmobj (NULL, ___sKEYWORD, ___KEYWORD_SIZE<<___LWS);
      break;
    default: /* assume ___sSYMBOL */
      obj = ___alloc_scmobj (NULL, ___sSYMBOL, ___SYMBOL_SIZE<<___LWS);
      break;
    }

  if (___FIXNUMP(obj))
    return obj;

  tbl = symkey_table (subtype);

  /* object layout is same for ___sSYMBOL and ___sKEYWORD */

  ___SYMKEY_NAME_FIELD(obj) = name;
  ___SYMKEY_HASH_FIELD(obj) = ___hash_scheme_string (name);

  if (subtype == ___sSYMBOL)
    ___SYMBOL_GLOBAL_FIELD(obj) = ___CAST(___SCMOBJ,___CAST(___glo_struct*,0));

  symkey_intern (obj);

  return obj;
}


___HIDDEN ___SCMOBJ symkey_find_utf8
   ___P((char *str,
         unsigned int subtype),
        (str,
         subtype)
char *str;
unsigned int subtype;)
{
  ___SCMOBJ tbl;
  ___SCMOBJ probe;
  ___SCMOBJ h = ___hash_UTF_8_string (str);

  if (h < ___FIX(0))
    return h;

  tbl = symkey_table (subtype);
  if (!symkey_table_permanent(tbl)) return ___FIX(___HEAP_OVERFLOW_ERR);
  probe = ___VECTORELEM(tbl, ___INT(h) % (___INT(___VECTORLENGTH(tbl))-1) + 1);

  while (probe != ___NUL)
    {
      ___SCMOBJ name = ___SYMKEY_NAME_FIELD(probe);
      ___SIZE_T i;
      ___SIZE_T n = ___INT(___STRINGLENGTH(name));
      ___UTF_8STRING p = str;
      ___UCS_4 c;
      for (i=0; i<n; i++)
        if (___UTF_8_get_var (&p, c) !=
            ___CAST(___UCS_4,___ORD(___STRINGREF(name,___FIX(i)))))
          goto next;
      if (___UTF_8_get_var (&p, c) == 0)
        return probe;
    next:
      probe = ___SYMKEY_NEXT_FIELD(probe);
    }

  return ___FAL;
}


___HIDDEN ___SCMOBJ symkey_find_string
   ___P((___SCMOBJ str,
         unsigned int subtype),
        (str,
         subtype)
___SCMOBJ str;
unsigned int subtype;)
{
  ___SCMOBJ tbl;
  ___SCMOBJ probe;
  ___SCMOBJ h = ___hash_scheme_string (str);

  tbl = symkey_table (subtype);
  if (!symkey_table_permanent(tbl)) return ___FIX(___HEAP_OVERFLOW_ERR);
  probe = ___VECTORELEM(tbl, ___INT(h) % (___INT(___VECTORLENGTH(tbl))-1) + 1);

  while (probe != ___NUL)
    {
      ___SCMOBJ name = ___SYMKEY_NAME_FIELD(probe);
      ___SIZE_TS i = 0;
      ___SIZE_TS n = ___INT(___STRINGLENGTH(name));
      if (___INT(___STRINGLENGTH(str)) == n)
        {
          for (i=0; i<n; i++)
            if (___STRINGREF(str,___FIX(i)) != ___STRINGREF(name,___FIX(i)))
              goto next;
          return probe;
        }
    next:
      probe = ___SYMKEY_NEXT_FIELD(probe);
    }

  return ___FAL;
}


___HIDDEN ___SCMOBJ symkey_make_utf8
   ___P((___UTF_8STRING str,
         unsigned int subtype),
        (str,
         subtype)
___UTF_8STRING str;
unsigned int subtype;)
{
  ___SCMOBJ obj = symkey_find_utf8 (str, subtype);

  if (obj == ___FAL)
    {
      ___SCMOBJ name;
      ___SCMOBJ err;

      if ((err = ___NONNULLUTF_8STRING_to_SCMOBJ
                   (NULL, /* allocate as permanent object */
                    str,
                    &name,
                    -1))
          != ___FIX(___NO_ERR))
        return err;

      obj = symkey_new (name, subtype);
    }

  return obj;
}


___HIDDEN ___SCMOBJ symkey_make_string
   ___P((___SCMOBJ str,
         unsigned int subtype),
        (str,
         subtype)
___SCMOBJ str;
unsigned int subtype;)
{
  ___SCMOBJ obj = symkey_find_string (str, subtype);

  if (obj == ___FAL)
    {
      ___SIZE_T n = ___INT(___STRINGLENGTH(str));
      ___SCMOBJ name = ___alloc_scmobj (NULL, ___sSTRING, n<<___LCS);

      if (___FIXNUMP(name))
        return name;

      memmove (___BODY_AS(name,___tSUBTYPED),
               ___BODY_AS(str,___tSUBTYPED),
               n<<___LCS);

      obj = symkey_new (name, subtype);
    }

  return obj;
}


/* Registry -> permanent allocator; no Scheme allocation, GC, callback or
 * safepoint in a lookup/create transaction. Names/objects/tables are permanent.
 * Caller owns the source string against concurrent character mutation. */
___SCMOBJ ___find_symkey_from_UTF_8_string(char *str,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  result=symkey_find_utf8(str,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

___SCMOBJ ___find_symkey_from_scheme_string(___SCMOBJ str,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  result=symkey_find_string(str,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

___SCMOBJ ___make_symkey_from_UTF_8_string(___UTF_8STRING str,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  result=symkey_make_utf8(str,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

___SCMOBJ ___make_symkey_from_scheme_string(___SCMOBJ str,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  result=symkey_make_string(str,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

___SCMOBJ ___new_symkey(___SCMOBJ name,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  result=symkey_find_string(name,subtype);
  if (result==___FAL) result=symkey_new(name,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

void ___intern_symkey(___SCMOBJ symkey)
{
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (!___GSTATE->mem.global_bootstrap || !global_bootstrap_owner())
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
      rc_contract_error("direct symkey insertion requires exclusive bootstrap"); }
  symkey_intern(symkey);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
}

/* One checked identity-copy contract serves Scheme views and native callbacks.
 * Caller holds global_gate. No allocation, callback or Scheme/GC occurs here.
 * A size mismatch writes no destination cells; copied identities are permanent. */
___HIDDEN ___SCMOBJ symkey_table_copy(___SCMOBJ *items,
                                    ___SIZE_TS length,unsigned int subtype)
{
  ___SCMOBJ table=symkey_table(subtype),result,probe;
  int count,used=0,i;
  if (!symkey_table_permanent(table) ||
      !___FIXNUMP(___VECTORELEM(table,0)) ||
      ___INT(___VECTORELEM(table,0))<0 ||
      ___VECTORELEM(table,0)>___FIX(SYMKEY_COUNT_LIMIT))
    return ___FIX(___HEAP_OVERFLOW_ERR);
  result=___VECTORELEM(table,0);
  count=___INT(result);
  if (items==0 || length!=count) return result;
  for (i=___INT(___VECTORLENGTH(table))-1;i>0;i--)
    for (probe=___VECTORELEM(table,i);probe!=___NUL;
         probe=___SYMKEY_NEXT_FIELD(probe))
      {
        if (used>=count || !___MEM_ALLOCATED(probe) ||
            ___HD_TYP(___HEADER(probe))!=___PERM ||
            ___INT(___SUBTYPE(probe))!=subtype)
          return ___FIX(___HEAP_OVERFLOW_ERR);
        items[used++]=probe;
      }
  return used==count ? result : ___FIX(___HEAP_OVERFLOW_ERR);
}

/* The Scheme caller allocates/roots its vector outside the registry gate. */
___SCMOBJ ___symkey_table_view(___SCMOBJ view,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (view==___FAL)
    result=symkey_table_copy(0,0,subtype);
  else if (!___MEM_ALLOCATED(view) ||
           ___HD_SUBTYPE(___HEADER(view))!=___sVECTOR)
    result=___FIX(___HEAP_OVERFLOW_ERR);
  else
    result=symkey_table_copy(___BODY_AS(view,___tVECTOR),
                            ___INT(___VECTORLENGTH(view)),subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

/* Native callbacks borrow a private identity array, never buckets or NEXT.
 * A live global-state owner and normally returning callbacks are required.
 * The native allocator cannot enter Scheme/GC. Keeping query/allocation/copy
 * in one gate avoids treating ordinary concurrent growth as caller failure.
 * No registry lock or movable address survives the callback boundary.
 * Permanent identities need no extra RC roots and do not extend VM lifetime. */
___BOOL ___for_each_symkey
   ___P((unsigned int subtype,
         void (*visit) (___SCMOBJ symkey, void *data),
         void *data),
        (subtype,visit,data)
unsigned int subtype;
void (*visit) ();
void *data;)
{
  ___SCMOBJ count,result,*items=0;
  ___SIZE_T length,i;
  if (visit==0) return 0;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  count=symkey_table_copy(0,0,subtype);
  if (count<___FIX(0))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  length=___INT(count);
  if (length==0)
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 1; }
  if (length>~___CAST(___SIZE_T,0)/sizeof(*items))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  items=___CAST(___SCMOBJ*,___ALLOC_MEM(length*sizeof(*items)));
  if (items==0)
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  result=symkey_table_copy(items,length,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  if (result!=count)
    { ___FREE_MEM(items); return 0; }
  for (i=0;i<length;i++) visit(items[i],data);
  ___FREE_MEM(items);
  return 1;
}

/*---------------------------------------------------------------------------*/


#define fromspace_offset ((___MSECTION_SIZE>>1) - tospace_offset)

#define start_of_fromspace(ms) ms->base + fromspace_offset

#define start_of_tospace(ms) ms->base + tospace_offset

#define SET_MAX(var,val) do { if ((var) < (val)) var = val; } while (0)
#define SET_MIN(var,val) do { if ((var) > (val)) var = val; } while (0)


/* End internal memory fragment. */
