#line 5070 ___MEM_SOURCE_FILE
___HIDDEN void gc_hash_table_rehash_in_situ
   ___P((___SCMOBJ ht),
        (ht)
___SCMOBJ ht;)
{
  ___WORD* body = ___BODY_AS(ht,___tSUBTYPED);
  ___SIZE_TS words = ___HD_WORDS(body[-1]);
  int size2 = words - ___GCHASHTABLE_KEY0;
  int i;

  body[___GCHASHTABLE_FLAGS] =
    ___FIXAND(body[___GCHASHTABLE_FLAGS],
              ___FIXNOT(___FIX(___GCHASHTABLE_FLAG_KEY_MOVED)));

  if (!___FIXZEROP(___FIXAND(body[___GCHASHTABLE_FLAGS],
                             ___FIX(___GCHASHTABLE_FLAG_UNION_FIND))))
    {
#if 0

      /*
       * Compress paths.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___SCMOBJ val = body[i+___GCHASHTABLE_VAL0];
          if (___FIXNUMP(val)) /* parent links are encoded as fixnums */
            {
              if (!___FIXODDP(val)) { /* not compressed yet */
                int probe2 = ___INT(val);
                int prev2 = i;
                ___SCMOBJ x;
                for (;;) {
                  ___SCMOBJ v = body[probe2+___GCHASHTABLE_VAL0];
                  if (___FIXNUMP(v)) { /* link to parent? */
                    if (___FIXODDP(v)) { /* compressed path? */
                      x = v;
                      break;
                    }
                    body[probe2+___GCHASHTABLE_VAL0] = prev2;
                    prev2 = probe2;
                    probe2 = ___INT(v);
                  } else { /* reached root of class */
                    x = ___FIX(probe2+1);
                    break;
                  }
                }
                while (prev2 != i) {
                  probe2 = body[prev2+___GCHASHTABLE_VAL0];
                  body[prev2+___GCHASHTABLE_VAL0] = x;
                  prev2 = probe2;
                }
                body[i+___GCHASHTABLE_VAL0] = x;
              }
            }
        }

      for (i=size2-2; i>=0; i-=2)
        {
          ___SCMOBJ val = body[i+___GCHASHTABLE_VAL0];
          if (___FIXNUMP(val))
            body[i+___GCHASHTABLE_VAL0] = ___FIX(___INT(val)&~1);
        }

#endif

      /*
       * Replace entry values that are parent links by the key of
       * their parent.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___SCMOBJ val = body[i+___GCHASHTABLE_VAL0];
          if (___FIXNUMP(val)) /* parent links are encoded as fixnums */
            body[i+___GCHASHTABLE_VAL0] = body[___INT(val)+___GCHASHTABLE_KEY0];
        }
    }

  if (___FIXZEROP(___FIXAND(body[___GCHASHTABLE_FLAGS],
                            ___FIX(___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS))))
    {
      /*
       * Free deleted entries and mark key field of all active
       * entries.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___WORD key = body[i+___GCHASHTABLE_KEY0];
          if (key == ___DELETED)
            {
              body[i+___GCHASHTABLE_KEY0] = ___UNUSED;
              body[___GCHASHTABLE_FREE] =
                ___FIXADD(body[___GCHASHTABLE_FREE], ___FIX(1));
            }
          else if (key != ___UNUSED)
            body[i+___GCHASHTABLE_KEY0] = ___MEM_ALLOCATED_SET(key);
        }

      /*
       * Move the active entries.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___WORD key = body[i+___GCHASHTABLE_KEY0];

          if (___MEM_ALLOCATED(key))
            {
              /* this is an active entry that has not been moved yet */

              ___SCMOBJ val = body[i+___GCHASHTABLE_VAL0];
              ___SCMOBJ obj;
              int probe2;
              int step2;

              body[i+___GCHASHTABLE_KEY0] = ___UNUSED;
              body[i+___GCHASHTABLE_VAL0] = ___UNUSED;

            chain_non_mem_alloc:
              key = ___MEM_ALLOCATED_CLEAR(key); /* recover true encoding */
              ___GCHASHTABLE_HASH_STEP(probe2, step2, key, size2>>1);
              probe2 <<= 1;
              step2 <<= 1;

            next_non_mem_alloc:
              obj = body[probe2+___GCHASHTABLE_KEY0];

              if (obj == ___UNUSED)
                {
                  /* storing into an unused entry */

                  body[probe2+___GCHASHTABLE_KEY0] = key;
                  body[probe2+___GCHASHTABLE_VAL0] = val;
                }
              else if (___MEM_ALLOCATED(obj))
                {
                  /* storing into an active entry */

                  body[probe2+___GCHASHTABLE_KEY0] = key;
                  key = obj;
                  obj = body[probe2+___GCHASHTABLE_VAL0];
                  body[probe2+___GCHASHTABLE_VAL0] = val;
                  val = obj;
                  goto chain_non_mem_alloc; /* now move overwritten entry */
                }
              else
                {
                  /* an entry has been moved here, so keep looking */

                  probe2 -= step2;
                  if (probe2 < 0)
                    probe2 += size2;
                  goto next_non_mem_alloc;
                }
            }
        }
    }
  else
    {
      /*
       * Free deleted entries and mark key field of all active
       * entries.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___WORD key = body[i+___GCHASHTABLE_KEY0];
          if (key == ___DELETED)
            {
              body[i+___GCHASHTABLE_KEY0] = ___UNUSED;
              body[___GCHASHTABLE_FREE] =
                ___FIXADD(body[___GCHASHTABLE_FREE], ___FIX(1));
            }
          else if (key != ___UNUSED)
            body[i+___GCHASHTABLE_KEY0] = ___MEM_ALLOCATED_CLEAR(key);
        }

      /*
       * Move the active entries.
       */

      for (i=size2-2; i>=0; i-=2)
        {
          ___WORD key = body[i+___GCHASHTABLE_KEY0];

          if (key != ___UNUSED && !___MEM_ALLOCATED(key))
            {
              /* this is an active entry that has not been moved yet */

              ___SCMOBJ val = body[i+___GCHASHTABLE_VAL0];
              ___SCMOBJ obj;
              int probe2;
              int step2;

              body[i+___GCHASHTABLE_KEY0] = ___UNUSED;
              body[i+___GCHASHTABLE_VAL0] = ___UNUSED;

            chain_mem_alloc:
              key = ___MEM_ALLOCATED_SET(key); /* recover true encoding */
              ___GCHASHTABLE_HASH_STEP(probe2, step2, key, size2>>1);
              probe2 <<= 1;
              step2 <<= 1;

            next_mem_alloc:
              obj = body[probe2+___GCHASHTABLE_KEY0];

              if (obj == ___UNUSED)
                {
                  /* storing into an unused entry */

                  body[probe2+___GCHASHTABLE_KEY0] = key;
                  body[probe2+___GCHASHTABLE_VAL0] = val;
                }
              else if (!___MEM_ALLOCATED(obj))
                {
                  /* storing into an active entry */

                  body[probe2+___GCHASHTABLE_KEY0] = key;
                  key = obj;
                  obj = body[probe2+___GCHASHTABLE_VAL0];
                  body[probe2+___GCHASHTABLE_VAL0] = val;
                  val = obj;
                  goto chain_mem_alloc; /* now move overwritten entry */
                }
              else
                {
                  /* an entry has been moved here, so keep looking */

                  probe2 -= step2;
                  if (probe2 < 0)
                    probe2 += size2;
                  goto next_mem_alloc;
                }
            }
        }
    }
}


___HIDDEN void process_gc_hash_tables
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  ___WORD curr = reached_gc_hash_tables;

  while (curr != ___TAG(0,0))
    {
      ___WORD* body = ___CAST(___WORD*,curr);
      ___SIZE_TS words = ___HD_WORDS(body[-1]);
      int flags = ___INT(body[___GCHASHTABLE_FLAGS]);
      int i;

      curr = body[___GCHASHTABLE_NEXT];

      body[___GCHASHTABLE_NEXT] = ___FIX(0);

      if (((___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS)
           & flags) ==
          (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS))
        {
          if (flags & ___GCHASHTABLE_FLAG_WEAK_VALS)
            {
              /*
               * GC hash table is weak on keys and on values.
               */

              /*
               * Eliminate GC hash table entries with an unmarked key
               * or an unmarked value.
               */

              for (i=words-2; i>=___GCHASHTABLE_KEY0; i-=2)
                {
                  ___WORD *unmarked_body; /* used by the UNMARKED macro */
                  int unmarked_typ;

                  ___WORD key = body[i];
                  ___WORD val = body[i+1];

                  if (___MEM_ALLOCATED(key))
                    {
                      ___WORD key_head = ___BODY0(key)[-1];

                      if (___TESTTYPE(key_head, ___FORW))
                        {
                          /*
                           * The key is movable and has been
                           * forwarded.
                           */

                          if (___MEM_ALLOCATED(val))
                            {
                              ___WORD val_head = ___BODY0(val)[-1];

                              if (___TESTTYPE(val_head, ___FORW))
                                {
                                  /*
                                   * The key is movable and has been
                                   * forwarded and the value is
                                   * movable and has been forwarded,
                                   * so update key field and value
                                   * field and remember to rehash next
                                   * time the GC hash table is
                                   * accessed.
                                   */

                                  body[i] =
                                    ___TAG(___UNTAG_AS(key_head, ___FORW),
                                           ___TYP(key));
                                  body[i+1] =
                                    ___TAG(___UNTAG_AS(val_head, ___FORW),
                                           ___TYP(val));
                                  flags |= ___GCHASHTABLE_FLAG_KEY_MOVED;
                                }
                              else if (UNMARKED(val))
                                {
                                  /*
                                   * Change the entry to indicate it
                                   * has been deleted.
                                   */

                                  body[i] = ___DELETED;
                                  body[i+1] = ___UNUSED;
                                  body[___GCHASHTABLE_COUNT] =
                                    ___FIXSUB(body[___GCHASHTABLE_COUNT],
                                              ___FIX(1));
                                  flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                                }
                              else
                                {
                                  /*
                                   * The key is movable and has been
                                   * forwarded and the value is not
                                   * movable and is reachable, so
                                   * update key field and remember to
                                   * rehash next time the GC hash
                                   * table is accessed.
                                   */

                                  body[i] =
                                    ___TAG(___UNTAG_AS(key_head, ___FORW),
                                           ___TYP(key));
                                  flags |= ___GCHASHTABLE_FLAG_KEY_MOVED;
                                }
                            }
                          else
                            {
                              /*
                               * The key is movable and has been
                               * forwarded, and the value is not
                               * memory allocated, so update key field
                               * and remember to rehash next time the
                               * GC hash table is accessed.
                               */

                              body[i] =
                                ___TAG(___UNTAG_AS(key_head, ___FORW),
                                       ___TYP(key));
                              flags |= ___GCHASHTABLE_FLAG_KEY_MOVED;
                            }
                        }
                      else if (UNMARKED(key))
                        {
                          /*
                           * Change the entry to indicate it has been
                           * deleted.
                           */

                          body[i] = ___DELETED;
                          body[i+1] = ___UNUSED;
                          body[___GCHASHTABLE_COUNT] =
                            ___FIXSUB(body[___GCHASHTABLE_COUNT],___FIX(1));
                          flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                        }
                      else
                        {
                          /*
                           * The key is not movable and is reachable.
                           */

                          if (___MEM_ALLOCATED(val))
                            {
                              ___WORD val_head = ___BODY0(val)[-1];

                              if (___TESTTYPE(val_head, ___FORW))
                                {
                                  /*
                                   * The key is not movable and is
                                   * reachable and the value is
                                   * movable and has been forwarded,
                                   * so update value field.
                                   */

                                  body[i+1] =
                                    ___TAG(___UNTAG_AS(val_head, ___FORW),
                                           ___TYP(val));
                                }
                              else if (UNMARKED(val))
                                {
                                  /*
                                   * Change the entry to indicate it
                                   * has been deleted.
                                   */

                                  body[i] = ___DELETED;
                                  body[i+1] = ___UNUSED;
                                  body[___GCHASHTABLE_COUNT] =
                                    ___FIXSUB(body[___GCHASHTABLE_COUNT],
                                              ___FIX(1));
                                  flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                                }
                              else
                                {
                                  /*
                                   * The key is not movable and is
                                   * reachable and the value is not
                                   * movable and is reachable, so
                                   * leave fields untouched.
                                   */
                                }
                            }
                          else
                            {
                              /*
                               * The key is not movable and is
                               * reachable and the value is not memory
                               * allocated, so leave fields untouched.
                               */
                            }
                        }
                    }
                  else
                    {
                      /*
                       * The key is not memory allocated.
                       */

                      if (___MEM_ALLOCATED(val))
                        {
                          ___WORD val_head = ___BODY0(val)[-1];

                          if (___TESTTYPE(val_head, ___FORW))
                            {
                              /*
                               * The key is not memory allocated and
                               * the value is movable and has been
                               * forwarded, so update value field.
                               */

                              body[i+1] =
                                ___TAG(___UNTAG_AS(val_head, ___FORW),
                                       ___TYP(val));
                            }
                          else if (UNMARKED(val))
                            {
                              /*
                               * Change the entry to indicate it
                               * has been deleted.
                               */

                              body[i] = ___DELETED;
                              body[i+1] = ___UNUSED;
                              body[___GCHASHTABLE_COUNT] =
                                ___FIXSUB(body[___GCHASHTABLE_COUNT],
                                          ___FIX(1));
                              flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                            }
                          else
                            {
                              /*
                               * The key is not memory allocated and
                               * the value is not movable and is
                               * reachable, so leave fields untouched.
                               */
                            }
                        }
                      else
                        {
                          /*
                           * The key is not memory allocated and the
                           * value is not memory allocated, so leave
                           * fields untouched.
                           */
                        }
                    }
                }
            }
          else
            {
              /*
               * GC hash table is weak on keys only.
               */

              /*
               * Eliminate GC hash table entries with an unmarked key.
               */

              for (i=words-2; i>=___GCHASHTABLE_KEY0; i-=2)
                {
                  ___WORD *unmarked_body; /* used by the UNMARKED macro */
                  int unmarked_typ;

                  ___WORD key = body[i];

                  if (___MEM_ALLOCATED(key))
                    {
                      ___WORD head = ___BODY0(key)[-1];

                      if (___TESTTYPE(head, ___FORW))
                        {
                          /*
                           * The key is movable and has been
                           * forwarded, so update key field and
                           * remember to rehash next time the
                           * GC hash table is accessed.
                           */

                          body[i] = ___TAG(___UNTAG_AS(head, ___FORW),
                                           ___TYP(key));
                          flags |= ___GCHASHTABLE_FLAG_KEY_MOVED;
                        }
                      else if (UNMARKED(key))
                        {
                          /*
                           * Change the entry to indicate it has been
                           * deleted.
                           */

                          body[i] = ___DELETED;
                          body[i+1] = ___UNUSED;
                          body[___GCHASHTABLE_COUNT] =
                            ___FIXSUB(body[___GCHASHTABLE_COUNT],___FIX(1));
                          flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                        }
                    }
                }
            }
        }
      else
        {
          if (flags & ___GCHASHTABLE_FLAG_WEAK_VALS)
            {
              /*
               * GC hash table is weak on values only.
               */

              /*
               * Eliminate GC hash table entries with an unmarked value.
               */

              for (i=words-2; i>=___GCHASHTABLE_KEY0; i-=2)
                {
                  ___WORD *unmarked_body; /* used by the UNMARKED macro */
                  int unmarked_typ;

                  ___WORD val = body[i+1];

                  if (___MEM_ALLOCATED(val))
                    {
                      ___WORD head = ___BODY0(val)[-1];

                      if (___TESTTYPE(head, ___FORW))
                        {
                          /*
                           * The value is movable and has been
                           * forwarded, so update value field.
                           */

                          body[i+1] = ___TAG(___UNTAG_AS(head, ___FORW),
                                             ___TYP(val));
                        }
                      else if (UNMARKED(val))
                        {
                          /*
                           * Change the entry to indicate it has been
                           * deleted.
                           */

                          body[i] = ___DELETED;
                          body[i+1] = ___UNUSED;
                          body[___GCHASHTABLE_COUNT] =
                            ___FIXSUB(body[___GCHASHTABLE_COUNT],___FIX(1));
                          flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                        }
                    }
                }
            }

          if (flags & ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS)
            flags |= ___GCHASHTABLE_FLAG_KEY_MOVED; /* assume worst case */
        }

      /* A Scheme hash is stable for an unchanged key across GC. Repairing
       * references does not authorize C address-hash slot permutation.
       * Preserve separate NEED_REHASH debt from reconstruction. */
      if (flags & ___GCHASHTABLE_FLAG_SCHEME_INDEX)
        flags &= ~___GCHASHTABLE_FLAG_KEY_MOVED;

      body[___GCHASHTABLE_FLAGS] = ___FIX(flags);

#ifndef ___GC_HASH_TABLE_REHASH_LAZILY

      if (!___FIXZEROP(___FIXAND(___FIX(flags),
                                 ___FIX(___GCHASHTABLE_FLAG_KEY_MOVED))))
        gc_hash_table_rehash_in_situ (___SUBTYPED_FROM_BODY(body));

#endif
    }
}


/* End internal memory fragment. */
