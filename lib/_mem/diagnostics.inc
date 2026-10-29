#line 2204 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

#ifdef ___DEBUG_GARBAGE_COLLECT


#define ZAP_USING_INVALID_HEAD_TAG_not
#define ZAP_PATTERN ___CAST(___WORD,0xcafebabe)
#define INVALID_HEAD_TAG 4


char *subtype_to_string
   ___P((int subtype),
        (subtype)
int subtype;)
{
  switch (subtype)
    {
    case ___sVECTOR:       return "vector";
    case ___sPAIR:         return "pair";
    case ___sRATNUM:       return "ratnum";
    case ___sCPXNUM:       return "cpxnum";
    case ___sSTRUCTURE:    return "structure";
    case ___sBOXVALUES:    return "boxvalues";
    case ___sMEROON:       return "meroon";
    case ___sJAZZ:         return "jazz";
    case ___sSYMBOL:       return "symbol";
    case ___sKEYWORD:      return "keyword";
    case ___sFRAME:        return "frame";
    case ___sCONTINUATION: return "continuation";
    case ___sPROMISE:      return "promise";
    case ___sWEAK:         return "weak";
    case ___sPROCEDURE:    return "procedure";
    case ___sRETURN:       return "return";
    case ___sFOREIGN:      return "foreign";
    case ___sSTRING:       return "string";
    case ___sS8VECTOR:     return "s8vector";
    case ___sU8VECTOR:     return "u8vector";
    case ___sS16VECTOR:    return "s16vector";
    case ___sU16VECTOR:    return "u16vector";
    case ___sS32VECTOR:    return "s32vector";
    case ___sU32VECTOR:    return "u32vector";
    case ___sF32VECTOR:    return "f32vector";
    case ___sS64VECTOR:    return "s64vector";
    case ___sU64VECTOR:    return "u64vector";
    case ___sF64VECTOR:    return "f64vector";
    case ___sFLONUM:       return "flonum";
    case ___sBIGNUM:       return "bignum";
    default:               return "UNKNOWN SUBTYPE";
    }
}

void print_value
   ___P((___SCMOBJ val),
        (val)
___SCMOBJ val;)
{
  ___SCMOBJ ___temp;
  if (___MEM_ALLOCATED(val))
    {
      ___WORD* body = ___BODY0(val);
      ___WORD head = body[-1];
      int subtype;
      int shift = 0;

      if (___TESTTYPE(head, ___FORW))
        {
          /* indirect forwarding pointer */
          body = ___BODY0(head);
          head = body[-1];
        }

      if (head == ZAP_PATTERN)
        ___printf ("[WARNING: HEAD=ZAP_PATTERN] ");
      else if (___HD_TYP(head) == INVALID_HEAD_TAG)
        {
          ___printf ("[WARNING: HEAD HAS INVALID TAG] ");
          shift = ___HTB;
        }

      head >>= shift;
      subtype = ___HD_SUBTYPE(head);

      if (subtype == ___sPAIR)
        {
          ___printf ("0x%" ___PRIxWORD " (... . ...)", val);
        }
      else
        {
          ___SCMOBJ sym;
          if (subtype == ___sPROCEDURE || subtype == ___sRETURN)
            {
              ___printf ("0x%" ___PRIxWORD " ", val);
              if (subtype == ___sPROCEDURE)
                ___printf ("#<procedure ");
              else
                ___printf ("#<return ");
              if ((sym = ___find_global_var_bound_to (val)) != ___NUL)
                print_value (___SYMKEY_NAME_FIELD(sym));
              else
                {
                  if (___HD_TYP(head) == ___PERM)
                    {
                      ___SCMOBJ *start = &body[-1];
                      ___SCMOBJ *ptr = start;
                      while (!___TESTHEADERTAG(*ptr,___sVECTOR))
                        ptr -= ___LABEL_SIZE;
                      ptr += ___LABEL_SIZE;
                      if (ptr == start)
                        ___printf ("???");
                      else
                        {
                          ___printf ("%d in ", (start-ptr)/___LABEL_SIZE);
                          print_value (___TAG(ptr,___tSUBTYPED));
                        }
                    }
                  else
                    ___printf ("???");
                }
              ___printf (">");
            }
          else if (subtype == ___sSTRING)
            {
              int i;
              ___SCMOBJ str = ___SUBTYPED_FROM_BODY(body);
              ___printf ("\"");
              for (i=0; i<___INT(___STRINGLENGTH(str)); i++)
                ___printf ("%c", ___ORD(___STRINGREF(str,___FIX(i))));
              ___printf ("\"");
            }
          else if (subtype == ___sSYMBOL)
            {
              ___printf ("#<symbol ");
              print_value (body[___SYMKEY_NAME]>>shift);
              ___printf (">");
            }
          else
            {
              ___printf ("#<%s>", subtype_to_string (subtype));
            }
        }
    }
  else if (___FIXNUMP(val))
    ___printf ("%d", ___INT(val));
  else if (___CHARP(val))
    ___printf ("#\\x%x", ___ORD(val));
  else if (val == ___FAL)
    ___printf ("#f");
  else if (val == ___TRU)
    ___printf ("#t");
  else if (val == ___NUL)
    ___printf ("()");
  else if (val == ___EOF)
    ___printf ("#!eof");
  else if (val == ___VOID)
    ___printf ("#!void");
  else if (val == ___ABSENT)
    ___printf ("#absent");
  else if (val == ___UNB1)
    ___printf ("#!unbound");
  else if (val == ___UNB2)
    ___printf ("#!unbound2");
  else if (val == ___OPTIONAL)
    ___printf ("#!optional");
  else if (val == ___KEYOBJ)
    ___printf ("#!key");
  else if (val == ___REST)
    ___printf ("#!rest");
  else if (val == ___UNUSED)
    ___printf ("#unused");
  else if (val == ___DELETED)
    ___printf ("#deleted");
  else
    ___printf ("#unknown(0x" ___PRIxWORD ")", val);
}

void print_stack
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___WORD *stack_limit = ___ps->context->stack_limit;
  ___WORD *fp = ___ps->context->fp;
  ___WORD *stack_break = ___ps->context->stack_break;
  ___WORD *stack_start = ___ps->context->stack_start;
  ___msection *stack_ms = ___ps->mem.stack_msection_;
  ___WORD *probe;

  ___printf ("------------------ current stack\n");

  ___printf ("stack_msection = %p\n", stack_ms);
  ___printf ("stack_msection->index = %d\n", stack_ms->index);
  ___printf ("stack_msection->pos   = %d\n", stack_ms->pos);
  ___printf ("stack_msection->next  = %p\n", stack_ms->next);
  ___printf ("stack_msection->prev  = %p\n", stack_ms->prev);
  ___printf ("fp = %p\n", fp);
  ___printf ("stack_break = %p\n", stack_break);
  ___printf ("stack_start = %p\n", stack_start);

  probe = stack_limit - 3;

  while (probe < stack_start)
    {
      int span = 0;
      int skip = 99999999;

#define SET_DIST_LO_HI(ctx_lo, ctx_hi, ptr) \
do { \
  int dist = probe - ptr; \
  if (dist < ctx_lo) \
    SET_MIN(skip, ctx_lo - dist); \
  else if (dist <= ctx_hi) \
    SET_MAX(span, ctx_hi - dist + 1); \
} while (0)

      SET_DIST_LO_HI( -3,  3, stack_limit);
      SET_DIST_LO_HI(-10, 10, fp);
      SET_DIST_LO_HI(-10, 10, stack_break);
      SET_DIST_LO_HI(-15,  0, stack_start);

      if (span > 0)
        {
          while (span > 0)
            {
              int i;
              if (probe < stack_start)
                ___printf ("%p %p", probe, *probe);
              else
                ___printf ("%p", probe);
              if (probe == stack_limit) ___printf (" <--stack_limit");
              if (probe == fp)          ___printf (" <--fp");
              if (probe == stack_break) ___printf (" <--stack_break");
              if (probe == stack_start) ___printf (" <--stack_start");
              i = probe - stack_break;
              if (i == ___BREAK_FRAME_NEXT)
                ___printf (" [BREAK_FRAME_NEXT]");
              else
                {
                  i = probe - (stack_start - ___FIRST_BREAK_FRAME_SPACE);
                  switch (i)
                    {
                    case ___BREAK_FRAME_NEXT:
                      ___printf (" [BREAK_FRAME_NEXT]");
                      break;
                    case ___FIRST_BREAK_FRAME_STACK_MSECTION:
                      ___printf (" [FIRST_BREAK_FRAME_STACK_MSECTION]");
                      break;
                    case ___FIRST_BREAK_FRAME_STACK_BREAK:
                      ___printf (" [FIRST_BREAK_FRAME_STACK_BREAK]");
                      break;
                    }
                }
              ___printf ("\n");
              probe++;
              span--;
            }
        }
      else
        {
           ___printf ("...\n");
           probe += skip;
        }
    }
}

#endif


#ifdef ENABLE_CONSISTENCY_CHECKS

#define IN_OBJECT           0
#define IN_REGISTER         1
#define IN_SAVED            2
#define IN_TYPE_CACHE       3
#define IN_PROCESSOR_SCMOBJ 4
#define IN_VM_SCMOBJ        5
#define IN_SYMKEY_TABLE     6
#define IN_GLOBAL_VAR       7
#define IN_WILL_LIST        8
#define IN_CONTINUATION     9
#define IN_RC               10


___HIDDEN void print_prefix
   ___P((char *prefix,
         int indent),
        (prefix,
         indent)
char *prefix;
int indent;)
{
  int i;

  ___printf ("%s", prefix);

  for (i=0; i<indent; i++)
    ___printf (" ");
}


___HIDDEN void print_object
   ___P((___WORD obj,
         int max_depth,
         char *prefix,
         int indent),
        (obj,
         max_depth,
         prefix,
         indent)
___WORD obj;
int max_depth;
char *prefix;
int indent;)
{
  print_prefix (prefix, indent);

  if (___FIXNUMP(obj))
    ___printf ("%d\n", ___INT(obj));
  else if (___TESTTYPE(obj, ___tSPECIAL))
    {
      if (obj >= 0)
        ___printf ("#\\%c\n", ___ORD(obj));
      else if (obj == ___FAL)
        ___printf ("#f\n");
      else if (obj == ___TRU)
        ___printf ("#t\n");
      else if (obj == ___NUL)
        ___printf ("()\n");
      else if (obj == ___EOF)
        ___printf ("#!eof\n");
      else if (obj == ___VOID)
        ___printf ("#!void\n");
      else if (obj == ___ABSENT)
        ___printf ("#<absent>\n");
      else if (obj == ___UNB1)
        ___printf ("#<unbound1>\n");
      else if (obj == ___UNB2)
        ___printf ("#<unbound2>\n");
      else if (obj == ___OPTIONAL)
        ___printf ("#!optional\n");
      else if (obj == ___KEYOBJ)
        ___printf ("#!key\n");
      else if (obj == ___REST)
        ___printf ("#!rest\n");
      else if (obj == ___UNUSED)
        ___printf ("#<unused>\n");
      else if (obj == ___DELETED)
        ___printf ("#<deleted>\n");
      else
        ___printf ("#<unknown 0x%" ___PRIxWORD ">\n", obj);
    }
  else
    {
      ___WORD* body = ___BODY0(obj);
      ___WORD head = body[-1];
      int subtype;
      int shift = 0;

      if (___TESTTYPE(head, ___FORW))
        {
          /* indirect forwarding pointer */
          body = ___BODY0(head);
          head = body[-1];
        }

      if (___HD_TYP(head) == INVALID_HEAD_TAG)
        shift = ___HTB;

      head >>= shift;
      subtype = ___HD_SUBTYPE(head);

      switch (subtype)
        {
        case ___sVECTOR:
          if (max_depth > 0)
            {
              int i;
              ___printf ("#(\n");
              for (i=0; i<___CAST(int,___HD_WORDS(head)); i++)
                print_object (___VECTORELEM(obj,i)>>shift, max_depth-1, prefix, indent+2);
              print_prefix (prefix, indent);
              ___printf (")\n");
            }
          else
            ___printf ("#(...)\n");
          break;
        case ___sPAIR:
          if (max_depth > 0)
            {
              ___printf ("(\n");
              print_object (___CAR(obj)>>shift, max_depth-1, prefix, indent+1);
              print_prefix (prefix, indent);
              ___printf (" .\n");
              print_object (___CDR(obj)>>shift, max_depth-1, prefix, indent+1);
              print_prefix (prefix, indent);
              ___printf (")\n");
            }
          else
            ___printf ("(...)\n");
          break;
        case ___sRATNUM:
          ___printf ("RATNUM\n");
          break;
        case ___sCPXNUM:
          ___printf ("CPXNUM\n");
          break;
        case ___sSTRUCTURE:
          ___printf ("STRUCTURE\n");
          break;
        case ___sBOXVALUES:
          ___printf ("BOXVALUES\n");
          break;
        case ___sMEROON:
          ___printf ("MEROON\n");
          break;
        case ___sSYMBOL:
          ___printf ("SYMBOL ");
          print_object (___SYMKEY_NAME_FIELD(obj)>>shift, max_depth-1, "", 0);
          break;
        case ___sKEYWORD:
          ___printf ("KEYWORD ");
          print_object (___SYMKEY_NAME_FIELD(obj)>>shift, max_depth-1, "", 0);
          break;
        case ___sFRAME:
          ___printf ("FRAME\n");
          break;
        case ___sCONTINUATION:
          ___printf ("CONTINUATION\n");
          break;
        case ___sPROMISE:
          ___printf ("PROMISE\n");
          break;
        case ___sWEAK:
          ___printf ("WEAK\n");
          break;
        case ___sPROCEDURE:
          ___printf ("PROCEDURE\n");
          break;
        case ___sRETURN:
          ___printf ("RETURN\n");
          break;
        case ___sFOREIGN:
          ___printf ("FOREIGN\n");
          break;
        case ___sSTRING:
          {
            int i;
            int len = ___HD_BYTES(head)>>___LCS;
            ___printf ("STRING ");
            for (i=0; i<len; i++)
              ___printf ("%c", ___ORD(___STRINGREF(obj,___FIX(i))));
            ___printf ("\n");
          }
          break;
        case ___sS8VECTOR:
          ___printf ("S8VECTOR\n");
          break;
        case ___sU8VECTOR:
          ___printf ("U8VECTOR\n");
          break;
        case ___sS16VECTOR:
          ___printf ("S16VECTOR\n");
          break;
        case ___sU16VECTOR:
          ___printf ("U16VECTOR\n");
          break;
        case ___sS32VECTOR:
          ___printf ("S32VECTOR\n");
          break;
        case ___sU32VECTOR:
          ___printf ("U32VECTOR\n");
          break;
        case ___sF32VECTOR:
          ___printf ("F32VECTOR\n");
          break;
        case ___sS64VECTOR:
          ___printf ("S64VECTOR\n");
          break;
        case ___sU64VECTOR:
          ___printf ("U64VECTOR\n");
          break;
        case ___sF64VECTOR:
          ___printf ("F64VECTOR\n");
          break;
        case ___sFLONUM:
          ___printf ("FLONUM\n");
          break;
        case ___sBIGNUM:
          ___printf ("BIGNUM\n");
          break;
        default:
          ___printf ("UNKNOWN\n");
          break;
        }
    }
}


___HIDDEN void print_global_var_name
   ___P((___glo_struct *glo),
        (glo)
___glo_struct *glo;)
{
  ___SCMOBJ sym = ___NUL;
  int i;

  for (i = ___INT(___VECTORLENGTH(___GSTATE->symbol_table)) - 1; i>0; i--)
    {
      sym = ___VECTORELEM(___GSTATE->symbol_table,i);

      while (sym != ___NUL)
        {
          ___SCMOBJ g = ___SYMBOL_GLOBAL_FIELD(sym);

          if (g != ___FIX(0))
            {
              ___glo_struct *p = ___CAST(___glo_struct*,g);

              if (p == glo)
                {
                  ___SCMOBJ name = ___SYMKEY_NAME_FIELD(sym);
                  for (i=0; i<___INT(___STRINGLENGTH(name)); i++)
                    ___printf ("%c", ___ORD(___STRINGREF(name,___FIX(i))));
                  i = 0;
                  break;
                }
            }

          sym = ___SYMKEY_NEXT_FIELD(sym);
        }
    }
}


___HIDDEN void dump_memory_map
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  int ns = the_msections->nb_sections;
  ___msection **sections = the_msections->sections;
  int i;

  ___printf (">>> Memory map:\n");

  for (i=0; i<ns; i++)
    ___printf (">>>  msection %2d:  %p .. %p .. %p\n",
               i,
               sections[i]->base,
               sections[i]->base + (___MSECTION_SIZE>>1),
               sections[i]->base + ___MSECTION_SIZE);

  ___printf (">>>  alloc_msection       = %p\n", alloc_msection);
  ___printf (">>>  stack_msection       = %p\n", stack_msection);
  ___printf (">>>  heap_msection        = %p\n", heap_msection);
  ___printf (">>>  alloc_stack_ptr      = %p\n", alloc_stack_ptr);
  ___printf (">>>  alloc_stack_limit    = %p\n", alloc_stack_limit);
  ___printf (">>>  alloc_heap_limit     = %p\n", alloc_heap_limit);
  ___printf (">>>  alloc_heap_ptr       = %p\n", alloc_heap_ptr);
  ___printf (">>>  scan_ptr             = %p\n", scan_ptr);
}

___HIDDEN void explain_problem
   ___P((___PSD
         ___WORD obj,
         int shift,
         char *msg),
        (___PSV
         obj,
         shift,
         msg)
___PSDKR
___WORD obj;
int shift;
char *msg;)
{
  ___PSGET

  dump_memory_map (___PSPNC);

  ___printf (">>> The object 0x%" ___PRIxWORD " %s\n", obj, msg);

  {
    int j;
    ___WORD head = ___BODY0(obj)[-1]>>shift;
    ___SIZE_TS words = ___HD_WORDS(head);
    if (words > 10)
      words = 10;
    for (j=-1; j<words; j++)
      {
        ___printf (">>>  body[%2d] = 0x%" ___PRIxWORD "\n", j, ___BODY0(obj)[j]>>shift);
        print_object (___BODY0(obj)[j]>>shift, 1, ">>>             ", 0);
      }
  }

  switch (reference_location)
    {
    case IN_OBJECT:
      {
        ___WORD container;
        ___WORD head = container_body[-1];
        ___SIZE_TS words = ___HD_WORDS(head);
        int subtype = ___HD_SUBTYPE(head);
        int i;

        if (subtype == ___sPAIR)
          container = ___PAIR_FROM_BODY(container_body);
        else
          container = ___SUBTYPED_FROM_BODY(container_body);

        ___printf (">>> The reference was found in ");
        if (___HD_TYP(head) == ___PERM)
          ___printf ("___PERM ");
        else if (___HD_TYP(head) == ___STILL)
          ___printf ("___STILL ");
        else if (___HD_TYP(head) == ___MOVABLE0)
          ___printf ("___MOVABLE0 ");
        else if (___TESTTYPE(head, ___FORW))
          ___printf ("___FORW ");
        else
          ___printf ("UNKNOWN ");
        ___printf ("object with body at %p:\n", container_body);

        ___printf (">>>  subtype = %d\n", subtype);
        ___printf (">>>  length  = %ld words\n", words);
        if (words <= 100)
          {
            for (i=-1; i<words; i++)
              ___printf (">>>  body[%2d] = 0x%" ___PRIxWORD "\n", i, container_body[i]);
          }
        else
          {
            for (i=0; i<50; i++)
              ___printf (">>>  body[%2d] = 0x%" ___PRIxWORD "\n", i, container_body[i]);
            ___printf ("...\n");
            for (i=words-50; i<words; i++)
              ___printf (">>>  body[%2d] = 0x%" ___PRIxWORD "\n", i, container_body[i]);
          }
        ___printf (">>> container =\n");
        print_object (container, 4, ">>>   ", 0);
        break;
      }

    case IN_REGISTER:
      ___printf (">>> The reference was found in a register\n");
      break;

    case IN_SAVED:
      ___printf (">>> The reference was found in the saved objects\n");
      break;

    case IN_TYPE_CACHE:
      ___printf (">>> The reference was found in a type cache\n");
      break;

    case IN_PROCESSOR_SCMOBJ:
      ___printf (">>> The reference was found in the processor object\n");
      break;

    case IN_VM_SCMOBJ:
      ___printf (">>> The reference was found in the VM object\n");
      break;

    case IN_SYMKEY_TABLE:
      ___printf (">>> The reference was found in the symbol or keyword table\n");
      break;

    case IN_GLOBAL_VAR:
      ___printf (">>> The reference was found in a global variable\n");
      break;

    case IN_WILL_LIST:
      ___printf (">>> The reference was found in a will list\n");
      break;

    case IN_CONTINUATION:
      ___printf (">>> The reference was found in a continuation\n");
      break;

    case IN_RC:
      ___printf (">>> The reference was found in a reference counted object\n");
      break;
    }
}


___HIDDEN void bug
   ___P((___PSD
         ___WORD obj,
         int shift,
         char *msg),
        (___PSV
         obj,
         shift,
         msg)
___PSDKR
___WORD obj;
int shift;
char *msg;)
{
  ___PSGET
  char *msgs[2];

  ___printf (">>> P%d: the GC has detected the following inconsistency\n",
             ___PROCESSOR_ID(___ps,___VMSTATE_FROM_PSTATE(___ps)));
  ___printf (">>> during call of mark_array on line %d of mem.c:\n",
             mark_array_call_line);
  explain_problem (___PSP obj, shift, msg);
  msgs[0] = "GC inconsistency detected";
  msgs[1] = 0;
  ___fatal_error (msgs);
}


___HIDDEN void validate_old_obj
   ___P((___PSD
         ___WORD obj),
        (___PSV
         obj)
___PSDKR
___WORD obj;)
{
  ___PSGET
  ___WORD *hd_ptr = ___BODY0(obj)-1;
  ___WORD head;
  int i = find_msection (the_msections, hd_ptr);
  if (i >= 0 && i < the_msections->nb_sections)
    {
      ___PTRDIFF_T pos = hd_ptr - the_msections->sections[i]->base;
      if (pos >= 0 && pos < ___MSECTION_SIZE)
        {
          head = *hd_ptr;
          if (___TESTTYPE(head, ___FORW))
            {
              ___WORD *hd_ptr2 = ___BODY0(head)-1;
              int i2 = find_msection (the_msections, hd_ptr2);
              if (i2 >= 0 && i2 < the_msections->nb_sections)
                {
                  ___PTRDIFF_T pos2 = hd_ptr2 -
                                      (the_msections->sections[i2]->base +
                                       tospace_offset);
                  if (pos2 < 0 || pos2 >= ___MSECTION_SIZE>>1)
                    bug (___PSP obj, 0, "was copied outside of tospace");
                  else if (___HD_TYP((*hd_ptr2)) != ___MOVABLE0)
                    bug (___PSP obj, 0, "was copied and copy is not ___MOVABLE0");
                }
              else
                bug (___PSP obj, 0, "was copied outside of tospace");
            }
          else if (___HD_TYP(head) != ___MOVABLE0)
            bug (___PSP obj, ___HTB, "should be ___MOVABLE0");
          else
            {
              pos -= tospace_offset;
              if (pos >= 0 && pos < ___MSECTION_SIZE>>1)
                bug (___PSP obj, 0, "is in tospace");
            }
          return;
        }
    }
  head = *hd_ptr; /* this dereference will likely bomb if there is a bug */
  if (___HD_TYP(head) != ___PERM && ___HD_TYP(head) != ___STILL)
    bug (___PSP obj, 0, "is not ___PERM or ___STILL");
}


___HIDDEN void zap_section
   ___P((___WORD *start,
         ___WORD *end),
        (start,
         end)
___WORD *start;
___WORD *end;)
{
  while (start < end)
    {
#ifdef ZAP_USING_INVALID_HEAD_TAG
      *start = (*start << ___HTB) | INVALID_HEAD_TAG;
#else
      *start = ZAP_PATTERN;
#endif
      start++;
    }
}


___HIDDEN int unzapped_words
   ___P((___WORD *start,
         int words),
        (start,
         words)
___WORD *start;
int words;)
{
  ___WORD *ptr = start;

  while (words > 0 && *ptr++ == ZAP_PATTERN)
    words--;

  return words;
}


___HIDDEN void check_fudge_used
   ___P((___PSDNC),
        (___PSVNC)
___PSDKR)
{
  ___PSGET
  int s;
  int h;

  s = unzapped_words (___ps->context->stack_limit - ___MSECTION_FUDGE,
                      ___MSECTION_FUDGE);

  if (s > stack_fudge_used)
    stack_fudge_used = s;

  h = ___ps->context->hp - ___ps->heap_limit;

  if (h > heap_fudge_used)
    heap_fudge_used = h;

#ifdef ___DEBUG_GARBAGE_COLLECT
  ___printf ("********* used fudge: stack = %d  heap = %d\n", s, h);
#endif
}


#endif


/* End internal memory fragment. */
