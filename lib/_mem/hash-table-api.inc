#line 5679 ___MEM_SOURCE_FILE
___SCMOBJ ___gc_hash_table_ref
   ___P((___SCMOBJ ht,
         ___SCMOBJ key),
        (ht,
         key)
___SCMOBJ ht;
___SCMOBJ key;)
{
  int size2;
  int probe2;
  int step2;
  ___SCMOBJ obj;

#ifdef ___GC_HASH_TABLE_REHASH_LAZILY

  if (!___FIXZEROP(___FIXAND(___GCHASHTABLE_FLAGS_FIELD(ht),
                             ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED))))
    gc_hash_table_rehash_in_situ (ht);

#endif

  size2 = ___INT(___GCHASHTABLELENGTH(ht)) - ___GCHASHTABLE_KEY0;
  ___GCHASHTABLE_HASH_STEP(probe2, step2, key, size2>>1);
  probe2 <<= 1;
  step2 <<= 1;
  obj = ___FIELD(WEAK,ht, probe2+___GCHASHTABLE_KEY0);

  if (___EQP(obj,key))
    return ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_VAL0);
  else if (!___EQP(obj,___UNUSED))
    {
      for (;;)
        {
          probe2 -= step2;
          if (probe2 < 0)
            probe2 += size2;
          obj = ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0);

          if (___EQP(obj,key))
            return ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_VAL0);
          else if (___EQP(obj,___UNUSED))
            break;
        }
    }

  return ___UNUSED; /* key was not found */
}


___SCMOBJ ___gc_hash_table_set
   ___P((___SCMOBJ ht,
         ___SCMOBJ key,
         ___SCMOBJ val),
        (ht,
         key,
         val)
___SCMOBJ ht;
___SCMOBJ key;
___SCMOBJ val;)
{
  int size2;
  int probe2;
  int step2;
  ___SCMOBJ obj;

#ifdef ___GC_HASH_TABLE_REHASH_LAZILY

  if (!___FIXZEROP(___FIXAND(___GCHASHTABLE_FLAGS_FIELD(ht),
                             ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED))))
    gc_hash_table_rehash_in_situ (ht);

#endif

  size2 = ___INT(___GCHASHTABLELENGTH(ht)) - ___GCHASHTABLE_KEY0;
  ___GCHASHTABLE_HASH_STEP(probe2, step2, key, size2>>1);
  probe2 <<= 1;
  step2 <<= 1;
  obj = ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0);

  if (!___EQP(val,___ABSENT))
    {
      /* trying to add or replace an entry */

      if (___EQP(obj,key))
        {
        replace_entry:
          ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_VAL0) = val;
        }
      else if (___EQP(obj,___UNUSED))
        {
        add_entry:
          ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0) = key;
          ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_VAL0) = val;
          ___GCHASHTABLE_COUNT_FIELD(ht) =
            ___FIXADD(___GCHASHTABLE_COUNT_FIELD(ht), ___FIX(1));
          if (___FIXNEGATIVEP(___GCHASHTABLE_FREE_FIELD(ht) =
                                ___FIXSUB(___GCHASHTABLE_FREE_FIELD(ht),
                                          ___FIX(1))))
            return ___TRU;
        }
      else
        {
          int deleted2 = -1;

          for (;;)
            {
              if (deleted2 < 0 && ___EQP(obj,___DELETED))
                deleted2 = probe2;

              probe2 -= step2;
              if (probe2 < 0)
                probe2 += size2;
              obj = ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0);

              if (___EQP(obj,key))
                goto replace_entry;

              if (___EQP(obj,___UNUSED))
                {
                  if (deleted2 < 0)
                    goto add_entry;

                  ___FIELD(WEAK, ht, deleted2+___GCHASHTABLE_KEY0) = key;
                  ___FIELD(WEAK, ht, deleted2+___GCHASHTABLE_VAL0) = val;
                  ___GCHASHTABLE_COUNT_FIELD(ht) =
                    ___FIXADD(___GCHASHTABLE_COUNT_FIELD(ht), ___FIX(1));

                  break;
                }
            }
        }
    }
  else
    {
      /* trying to delete an entry */

      if (___EQP(obj,key))
        {
        delete_entry:
          ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0) = ___DELETED;
          ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_VAL0) = ___UNUSED;
          ___GCHASHTABLE_COUNT_FIELD(ht) =
            ___FIXSUB(___GCHASHTABLE_COUNT_FIELD(ht),
                      ___FIX(1));
          if (___FIXLT(___GCHASHTABLE_COUNT_FIELD(ht),
                       ___GCHASHTABLE_MIN_COUNT_FIELD(ht)))
            return ___TRU;
        }
      else if (!___EQP(obj,___UNUSED))
        {
          for (;;)
            {
              probe2 -= step2;
              if (probe2 < 0)
                probe2 += size2;
              obj = ___FIELD(WEAK, ht, probe2+___GCHASHTABLE_KEY0);

              if (___EQP(obj,key))
                goto delete_entry;

              if (___EQP(obj,___UNUSED))
                break;
            }
        }
    }

 /*
  * Hash table does not need to be resized.
  */

  return ___FAL;
}


#define FIND_COMPRESS_KEY(key,key_probe2,key_step2,obj,k,k_probe2,k_prev2,k_step2,o,k_p2) \
do {                                                                          \
  ___GCHASHTABLE_HASH_STEP(key_probe2,key_step2,key,size2>>1);                \
  key_probe2 <<= 1;                                                           \
  key_step2 <<= 1;                                                            \
  obj = ___FIELD(WEAK, ht, key_probe2+___GCHASHTABLE_KEY0);                   \
                                                                              \
  while (!(___EQP(obj,key) || ___EQP(obj,___UNUSED)))                         \
    {                                                                         \
      key_probe2 -= key_step2;                                                \
      if (key_probe2 < 0)                                                     \
        key_probe2 += size2;                                                  \
      obj = ___FIELD(WEAK, ht, key_probe2+___GCHASHTABLE_KEY0);               \
    }                                                                         \
                                                                              \
  if (___EQP(obj,key))                                                        \
    {                                                                         \
      /*                                                                      \
       * key was found, compress its path.                                    \
       */                                                                     \
                                                                              \
      k = ___FIELD(WEAK, ht, key_probe2+___GCHASHTABLE_VAL0);                 \
                                                                              \
      if (___SPECIALP(k))                                                     \
        {                                                                     \
          k_probe2 = key_probe2;                                              \
        }                                                                     \
      else                                                                    \
        {                                                                     \
          ___SCMOBJ k_prev2 = key_probe2;                                     \
                                                                              \
          for (;;)                                                            \
            {                                                                 \
              if (___FIXNUMP(k))                                              \
                {                                                             \
                  k_probe2 = ___INT(k);                                       \
                }                                                             \
              else                                                            \
                {                                                             \
                  ___SCMOBJ o;                                                \
                  ___SCMOBJ k_step2;                                          \
                  ___GCHASHTABLE_HASH_STEP(k_probe2,k_step2,k,size2>>1);      \
                  k_probe2 <<= 1;                                             \
                  k_step2 <<= 1;                                              \
                  o = ___FIELD(WEAK, ht, k_probe2+___GCHASHTABLE_KEY0);       \
                                                                              \
                  while (!___EQP(o,k))                                        \
                    {                                                         \
                      k_probe2 -= k_step2;                                    \
                      if (k_probe2 < 0)                                       \
                        k_probe2 += size2;                                    \
                      o = ___FIELD(WEAK, ht, k_probe2+___GCHASHTABLE_KEY0);   \
                    }                                                         \
                }                                                             \
                                                                              \
              k = ___FIELD(WEAK, ht, k_probe2+___GCHASHTABLE_VAL0);           \
                                                                              \
              if (___SPECIALP(k))                                             \
                break;                                                        \
                                                                              \
              ___FIELD(WEAK, ht, k_probe2+___GCHASHTABLE_VAL0) = ___FIX(k_prev2); \
              k_prev2 = k_probe2;                                             \
            }                                                                 \
                                                                              \
          for (;;)                                                            \
            {                                                                 \
              ___SCMOBJ k_p2 = ___INT(___FIELD(WEAK, ht, k_prev2+___GCHASHTABLE_VAL0)); \
              ___FIELD(WEAK, ht, k_prev2+___GCHASHTABLE_VAL0) = ___FIX(k_probe2); \
              if (k_prev2 == key_probe2)                                      \
                break;                                                        \
              k_prev2 = k_p2;                                                 \
            }                                                                 \
        }                                                                     \
    }                                                                         \
 } while (0)


___SCMOBJ ___gc_hash_table_union_find
   ___P((___SCMOBJ ht,
         ___SCMOBJ key1,
         ___SCMOBJ key2,
         ___BOOL find),
        (ht,
         key1,
         key2,
         find)
___SCMOBJ ht;
___SCMOBJ key1;
___SCMOBJ key2;
___BOOL find;)
{
  /*
   * This function takes a GC hash table "ht", which must have its
   * ___GCHASHTABLE_FLAG_UNION_FIND flag set, and two memory allocated
   * objects "key1" and "key2", and determines if these objects are
   * part of the same equivalence class.  If "find" is false, the hash
   * table is modified to force these objects to be in the same
   * equivalence class (union operation).  The returned value
   * indicates which keys were found in the table, if they are part of
   * the same equivalence class and if the GC hash table needs to
   * grow.  The possible return values are:
   *
   *    0       key1 and key2 found in ht, and in same equiv class
   *    1       key1 and key2 found in ht, but not in same equiv class
   *    2 or 3  only one of key1 and key2 found in ht (2 = need to grow ht)
   *    4 or 5  neither key1 or key2 found in ht (4 = need to grow ht)
   */

  int size2;
  ___SCMOBJ key1_probe2;
  ___SCMOBJ key1_step2;
  ___SCMOBJ key2_probe2;
  ___SCMOBJ key2_step2;
  ___SCMOBJ allocated;
  ___SCMOBJ obj1;
  ___SCMOBJ obj2;
  ___SCMOBJ k1 = ___FIX(0);
  ___SCMOBJ k1_probe2 = ___FIX(0);
  ___SCMOBJ k2 = ___FIX(0);
  ___SCMOBJ k2_probe2 = ___FIX(0);

#ifdef ___GC_HASH_TABLE_REHASH_LAZILY

  if (!___FIXZEROP(___FIXAND(___GCHASHTABLE_FLAGS_FIELD(ht),
                             ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED))))
    gc_hash_table_rehash_in_situ (ht);

#endif

  size2 = ___INT(___GCHASHTABLELENGTH(ht)) - ___GCHASHTABLE_KEY0;

  /* Search for key1 */

  FIND_COMPRESS_KEY(key1,
                    key1_probe2,
                    key1_step2,
                    obj1,
                    k1,
                    k1_probe2,
                    k1_prev2,
                    k1_step2,
                    o1,
                    k1_p2);

  /* Search for key2 */

  FIND_COMPRESS_KEY(key2,
                    key2_probe2,
                    key2_step2,
                    obj2,
                    k2,
                    k2_probe2,
                    k2_prev2,
                    k2_step2,
                    o2,
                    k2_p2);

  /* What needs to be done depends on which keys were found */

  if (___EQP(obj1,key1))
    {
      if (___EQP(obj2,key2))
        {
          /* both key1 and key2 were found in the table */

          if (k1_probe2 == k2_probe2)
            return ___FIX(0); /* keys are in the same equiv class */

          if (find)
            return ___FIX(1); /* keys are not in the same equiv class */

          k1 = ___INT(k1);
          k2 = ___INT(k2);

          if (k1 > k2) /* choose biggest equivalence class */
            {
              ___FIELD(WEAK, ht, k1_probe2+___GCHASHTABLE_VAL0) =
                ___SPECIAL(k1+k2);
              ___FIELD(WEAK, ht, k2_probe2+___GCHASHTABLE_VAL0) =
                ___FIX(k1_probe2);
            }
          else
            {
              ___FIELD(WEAK, ht, k2_probe2+___GCHASHTABLE_VAL0) =
                ___SPECIAL(k1+k2);
              ___FIELD(WEAK, ht, k1_probe2+___GCHASHTABLE_VAL0) =
                ___FIX(k2_probe2);
            }

          return ___FIX(1);
        }
      else
        {
          /* key1 was found in the table, but key2 was not found */

          if (find)
            return ___FIX(3); /* keys are not in the same equiv class */

          k1 = ___INT(k1);

          ___FIELD(WEAK, ht, k1_probe2+___GCHASHTABLE_VAL0) = ___SPECIAL(k1+1);
          ___FIELD(WEAK, ht, key2_probe2+___GCHASHTABLE_KEY0) = key2;
          ___FIELD(WEAK, ht, key2_probe2+___GCHASHTABLE_VAL0) = ___FIX(k1_probe2);
          allocated = 1;
        }
    }
  else
    {
      /* key1 was not found */

      if (___EQP(obj2,key2))
        {
          /* key2 was found in the table, but key1 was not found */

          if (find)
            return ___FIX(3); /* keys are not in the same equiv class */

          k2 = ___INT(k2);

          ___FIELD(WEAK, ht, k2_probe2+___GCHASHTABLE_VAL0) = ___SPECIAL(k2+1);
          ___FIELD(WEAK, ht, key1_probe2+___GCHASHTABLE_KEY0) = key1;
          ___FIELD(WEAK, ht, key1_probe2+___GCHASHTABLE_VAL0) = ___FIX(k2_probe2);
          allocated = 1;
        }
      else
        {
          /* key1 and key2 were not found in the table */

          if (find)
            return ___FIX(5); /* keys are not in the same equiv class */

          ___FIELD(WEAK, ht, key1_probe2+___GCHASHTABLE_KEY0) = key1;
          ___FIELD(WEAK, ht, key1_probe2+___GCHASHTABLE_VAL0) = ___SPECIAL(2);

          if (key1_probe2 == key2_probe2)
            {
              /*
               * Both keys hash to the same entry so search for other
               * free entry.  This will succeed because GC hash tables
               * are guaranteed to have 2 free entries.
               */
              do
                {
                  key2_probe2 -= key2_step2;
                  if (key2_probe2 < 0)
                    key2_probe2 += size2;
                } while (!___EQP(___FIELD(WEAK, ht, key2_probe2+___GCHASHTABLE_KEY0),
                                 ___UNUSED));
            }

          ___FIELD(WEAK, ht, key2_probe2+___GCHASHTABLE_KEY0) = key2;
          ___FIELD(WEAK, ht, key2_probe2+___GCHASHTABLE_VAL0) = ___FIX(key1_probe2);
          allocated = 2;
        }
    }

  ___GCHASHTABLE_COUNT_FIELD(ht) =
    ___FIXADD(___GCHASHTABLE_COUNT_FIELD(ht), ___FIX(allocated));

  if (___FIXNEGATIVEP(___GCHASHTABLE_FREE_FIELD(ht) =
                      ___FIXSUB(___GCHASHTABLE_FREE_FIELD(ht),
                                ___FIX(allocated))))
    return ___FIX(allocated*2); /* signal that table needs to grow */
  else
    return ___FIX(allocated*2+1); /* signal that table doesn't need to grow */
}


___SCMOBJ ___gc_hash_table_rehash
   ___P((___SCMOBJ ht_src,
         ___SCMOBJ ht_dst),
        (ht_src,
         ht_dst)
___SCMOBJ ht_src;
___SCMOBJ ht_dst;)
{
  ___SCMOBJ* body_src = ___BODY_AS(ht_src,___tSUBTYPED);
  ___SIZE_TS words = ___HD_WORDS(body_src[-1]);
  int size2 = words - ___GCHASHTABLE_KEY0;
  int i;

  if (___FIXZEROP(___FIXAND(body_src[___GCHASHTABLE_FLAGS],
                            ___FIX(___GCHASHTABLE_FLAG_UNION_FIND))))
    {
      for (i=size2-2; i>=0; i-=2)
        {
          ___SCMOBJ key = body_src[i+___GCHASHTABLE_KEY0];

          if (key != ___UNUSED &&
              key != ___DELETED)
            {
              ___SCMOBJ val = body_src[i+___GCHASHTABLE_VAL0];
              ___gc_hash_table_set (ht_dst, key, val);
            }
        }
    }
  else
    {
      for (i=size2-2; i>=0; i-=2)
        {
          ___SCMOBJ key = body_src[i+___GCHASHTABLE_KEY0];

          if (key != ___UNUSED)
            {
              ___SCMOBJ val = body_src[i+___GCHASHTABLE_VAL0];
              if (___FIXNUMP(val)) {
                val = body_src[___INT(val)+___GCHASHTABLE_KEY0];
              }
              ___gc_hash_table_set (ht_dst, key, val);
            }
        }
    }

  return ht_dst;
}


/* End internal memory fragment. */
