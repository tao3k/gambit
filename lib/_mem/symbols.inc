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
  ___SCMOBJ tbl = ___make_vector (NULL, length+1, ___NUL);

  if (!___FIXNUMP(tbl))
    ___VECTORELEM(tbl, 0) = ___FIX(0);

  return tbl;
}


void ___intern_symkey
   ___P((___SCMOBJ symkey),
        (symkey)
___SCMOBJ symkey;)
{
  unsigned int subtype = ___INT(___SUBTYPE(symkey));
  ___SCMOBJ tbl = symkey_table (subtype);
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

  if (___INT(___VECTORELEM(tbl, 0)) > ___INT(___VECTORLENGTH(tbl)) * 4)
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


___SCMOBJ ___new_symkey
   ___P((___SCMOBJ name, /* name must be a permanent object */
         unsigned int subtype),
        (name,
         subtype)
___SCMOBJ name;
unsigned int subtype;)
{
  ___SCMOBJ obj;
  ___SCMOBJ tbl;

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

  ___intern_symkey (obj);

  return obj;
}


___SCMOBJ ___find_symkey_from_UTF_8_string
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


___SCMOBJ ___find_symkey_from_scheme_string
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


___SCMOBJ ___make_symkey_from_UTF_8_string
   ___P((___UTF_8STRING str,
         unsigned int subtype),
        (str,
         subtype)
___UTF_8STRING str;
unsigned int subtype;)
{
  ___SCMOBJ obj = ___find_symkey_from_UTF_8_string (str, subtype);

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

      obj = ___new_symkey (name, subtype);
    }

  return obj;
}


___SCMOBJ ___make_symkey_from_scheme_string
   ___P((___SCMOBJ str,
         unsigned int subtype),
        (str,
         subtype)
___SCMOBJ str;
unsigned int subtype;)
{
  ___SCMOBJ obj = ___find_symkey_from_scheme_string (str, subtype);

  if (obj == ___FAL)
    {
      ___SIZE_T n = ___INT(___STRINGLENGTH(str));
      ___SCMOBJ name = ___alloc_scmobj (NULL, ___sSTRING, n<<___LCS);

      if (___FIXNUMP(name))
        return name;

      memmove (___BODY_AS(name,___tSUBTYPED),
               ___BODY_AS(str,___tSUBTYPED),
               n<<___LCS);

      obj = ___new_symkey (name, subtype);
    }

  return obj;
}


void ___for_each_symkey
   ___P((unsigned int subtype,
         void (*visit) (___SCMOBJ symkey, void *data),
         void *data),
        (subtype,
         visit,
         data)
unsigned int subtype;
void (*visit) ();
void *data;)
{
  ___SCMOBJ tbl = symkey_table (subtype);
  int i;

  for (i=___INT(___VECTORLENGTH(tbl))-1; i>0; i--)
    {
      ___SCMOBJ probe = ___VECTORELEM(tbl, i);

      while (probe != ___NUL)
        {
          visit (probe, data);
          probe = ___SYMKEY_NEXT_FIELD(probe);
        }
    }
}


/*---------------------------------------------------------------------------*/


#define fromspace_offset ((___MSECTION_SIZE>>1) - tospace_offset)

#define start_of_fromspace(ms) ms->base + fromspace_offset

#define start_of_tospace(ms) ms->base + tospace_offset

#define SET_MAX(var,val) do { if ((var) < (val)) var = val; } while (0)
#define SET_MIN(var,val) do { if ((var) > (val)) var = val; } while (0)


/* End internal memory fragment. */
