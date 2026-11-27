/* Phase A.2.3: Independent Processor-Local Young-Still Reclamation (Zero Global STW).
 *
 * Formally verified in:
 *   - dev/refactoring/modern-c/models/lean/LocalNurserySRFI230Refinement.lean
 *   - dev/refactoring/modern-c/models/lean/AdversarialGCHighOrderRefinement.lean
 *   - dev/refactoring/modern-c/models/quint/adversarial_gc_high_order.qnt
 *
 * When a processor's local young allocations have NOT escaped to mature space,
 * globals, SRFI-230 atomic boxes, wills, or sibling processors (local_young_escaped_ == 0),
 * and no concurrent major cycle is active, the processor can trace strictly its own
 * execution context (GVM registers, saved/type_cache, processor_scmobj, active stack
 * frames, and transitive children within its own current young heap_msection) and
 * reclaim unmarked dead young_still_objs locally into still_local_free_ without
 * invoking on_all_processors() or stalling any sibling core.
 *
 * Any overflow of the bounded local worklist/visited set or encounter with an
 * exotic subtype conservatively aborts, resets mark bits, and falls back to the
 * standard global collector.
 */

#ifndef ___LOCAL_NURSERY_INC
#define ___LOCAL_NURSERY_INC

#define ___LOCAL_GC_WORKLIST_CAP 256u
#define ___LOCAL_GC_VISITED_CAP  512u /* power of 2 */
#define ___LOCAL_GC_VISITED_MAX  384u

typedef struct ___local_still_tracer_struct
  {
    ___processor_state ps;
    ___WORD *heap_lo;
    ___WORD *heap_hi;
    ___SCMOBJ worklist[___LOCAL_GC_WORKLIST_CAP];
    unsigned int wl_count;
    ___UWORD visited[___LOCAL_GC_VISITED_CAP];
    unsigned int vis_count;
    int aborted;
  } ___local_still_tracer;

static inline int local_tracer_is_leaf_subtype(int subtype)
{
  return (subtype == ___sFOREIGN || subtype == ___sSTRING ||
          subtype == ___sS8VECTOR || subtype == ___sU8VECTOR ||
          subtype == ___sS16VECTOR || subtype == ___sU16VECTOR ||
          subtype == ___sS32VECTOR || subtype == ___sU32VECTOR ||
          subtype == ___sS64VECTOR || subtype == ___sU64VECTOR ||
          subtype == ___sF32VECTOR || subtype == ___sF64VECTOR ||
          subtype == ___sFLONUM || subtype == ___sBIGNUM);
}

static inline int local_tracer_visit_body(___local_still_tracer *tr, ___WORD *body)
{
  ___UWORD key = ___CAST(___UWORD, body);
  unsigned int mask = ___LOCAL_GC_VISITED_CAP - 1u;
  unsigned int slot = (unsigned int)(((key >> 4) ^ (key >> 11)) & mask);
  unsigned int probes;
  for (probes = 0u; probes < ___LOCAL_GC_VISITED_CAP; probes++)
    {
      ___UWORD cur = tr->visited[slot];
      if (cur == key)
        return 0; /* already visited */
      if (cur == 0u)
        {
          if (tr->vis_count >= ___LOCAL_GC_VISITED_MAX)
            {
              tr->aborted = 1;
              return 0;
            }
          tr->visited[slot] = key;
          tr->vis_count++;
          return 1;
        }
      slot = (slot + 1u) & mask;
    }
  tr->aborted = 1;
  return 0;
}

static inline void local_tracer_mark_obj(___local_still_tracer *tr, ___SCMOBJ obj)
{
  ___WORD head;
  int htyp;

  if (tr->aborted || !___MEM_ALLOCATED(obj))
    return;

  head = ___HEADER(obj);
  htyp = ___HD_TYP(head);

  if (htyp == ___STILL)
    {
#ifndef ___USE_HANDLES
      ___WORD *base = ___BODY0(obj) - ___STILL_BODY;
      if ((base[___STILL_DIRTY] & ___STILL_FLAG_YOUNG) == 0)
        return; /* mature still: cannot reference local young still when unescaped */
      if (base[___STILL_MARK] == -1)
        {
          int subtype = ___HD_SUBTYPE(head);
          base[___STILL_MARK] = 0;
          if (!local_tracer_is_leaf_subtype(subtype))
            {
              if (tr->wl_count >= ___LOCAL_GC_WORKLIST_CAP)
                {
                  tr->aborted = 1;
                  return;
                }
              tr->worklist[tr->wl_count++] = obj;
            }
        }
#endif
      return;
    }

  if (htyp == ___MOVABLE0)
    {
      ___WORD *body = ___BODY0(obj);
      if (body < tr->heap_lo || body >= tr->heap_hi)
        return; /* mature movable: cannot reference local young still when unescaped */
      if (local_tracer_visit_body(tr, body))
        {
          int subtype = ___HD_SUBTYPE(head);
          if (!local_tracer_is_leaf_subtype(subtype))
            {
              if (tr->wl_count >= ___LOCAL_GC_WORKLIST_CAP)
                {
                  tr->aborted = 1;
                  return;
                }
              tr->worklist[tr->wl_count++] = obj;
            }
        }
      return;
    }
}

static void local_tracer_drain(___local_still_tracer *tr)
{
  while (!tr->aborted && tr->wl_count > 0u)
    {
      ___SCMOBJ obj = tr->worklist[--tr->wl_count];
      ___WORD head = ___HEADER(obj);
      int subtype = ___HD_SUBTYPE(head);
      ___SIZE_TS words = ___HD_WORDS(head);
      ___WORD *body = ___BODY0(obj);
      ___SIZE_TS i;

      switch (subtype)
        {
        case ___sVECTOR:
        case ___sPAIR:
        case ___sBOXVALUES:
        case ___sSTRUCTURE:
        case ___sSYMBOL:
        case ___sKEYWORD:
        case ___sRATNUM:
        case ___sCPXNUM:
        case ___sMEROON:
        case ___sJAZZ:
          for (i = 0; i < words && !tr->aborted; i++)
            local_tracer_mark_obj(tr, body[i]);
          break;

        case ___sPROCEDURE:
          /* Closure: slot 0 is entry label; free variables start at slot 1. */
          for (i = 1; i < words && !tr->aborted; i++)
            local_tracer_mark_obj(tr, body[i]);
          break;

        default:
          /* Conservatively abort on continuations, frames, weak tables, wills, promises */
          tr->aborted = 1;
          break;
        }
    }
}

___HIDDEN ___BOOL try_local_young_still_gc
   (___processor_state ___ps,
    ___SIZE_TS requested_words_still)
{
#ifdef ___USE_HANDLES
  (void)___ps; (void)requested_words_still;
  return 0;
#else
  ___virtual_machine_state vm;
  ___execution_context *ctx;
  ___WORD *hp;
  ___WORD *heap_lo;
  ___local_still_tracer tr;
  ___WORD *fp;
  ___WORD ra = 0;
  int carry = 0;
  int i;

  if (___ps == 0 || ___ps != ___PSTATE || !___lifecycle_gc_admitted(___ps))
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0)
    return 0;

  /* Soundness gate: local minor GC runs only when no young pointer has escaped
   * to mature/shared space and no major cycle or selective evacuation is pending.
   * Require zero young escapes, idle major phase, no wills, and enough young
   * still objects to make local reclamation worthwhile. */
  if (___ps->mem.local_young_escaped_ != 0)
    return 0;
  if (___ps->mem.young_still_objs_ == 0 ||
      ___ps->mem.words_still_objs_young_ < requested_words_still + 2048)
    return 0;
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE ||
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_request_start_) != 0 ||
      vm->mem.major_evacuate_count_ >= 2)
    return 0;
  if (___UNTAG(___ps->mem.nonexecutable_wills_) != 0 ||
      ___UNTAG(___ps->mem.executable_wills_) != 0)
    return 0;

  ctx = ___ps->context;
  if (ctx == 0 || ctx->fp == 0 || ctx->stack_break == 0 ||
      ___ps->mem.heap_msection_ == 0)
    return 0;

  hp = ctx->hp;
  heap_lo = ___ps->mem.alloc_heap_start_;
  if (hp == 0 || heap_lo == 0 || hp < heap_lo || hp > ___ps->mem.alloc_heap_limit_)
    return 0;

  tr.ps = ___ps;
  tr.heap_lo = heap_lo;
  tr.heap_hi = hp;
  tr.wl_count = 0u;
  tr.vis_count = 0u;
  tr.aborted = 0;
  memset(tr.visited, 0, sizeof(tr.visited));

  /* 0. Reset STILL_MARK = -1 on all young_still_objs (alloc initializes STILL_MARK = 0).
   * Any young still object with non-zero refcount is pinned live and seeded as a root. */
  {
    ___WORD *base = ___CAST(___WORD*, ___ps->mem.young_still_objs_);
    while (base != 0)
      {
        if (base[___STILL_REFCOUNT] != 0)
          {
            ___WORD head = base[___STILL_BODY - 1];
            base[___STILL_MARK] = 0;
            if (!local_tracer_is_leaf_subtype(___HD_SUBTYPE(head)))
              {
                /* Conservatively abort if a pinned pointer-bearing young still exists */
                tr.aborted = 1;
                break;
              }
          }
        else
          {
            base[___STILL_MARK] = -1;
          }
        base = ___CAST(___WORD*, base[___STILL_LINK]);
      }
  }

  /* 1. Mark processor-private execution roots (registers, saved, type_cache, processor_scmobj) */
  for (i = 0; i < ___NB_GVM_REGS && !tr.aborted; i++)
    local_tracer_mark_obj(&tr, ctx->r[i]);
  for (i = 0; i < 3 && !tr.aborted; i++)
    local_tracer_mark_obj(&tr, ctx->saved[i]);
  for (i = 0; i < 2 && !tr.aborted; i++)
    local_tracer_mark_obj(&tr, ctx->type_cache[i]);
  for (i = 0; i < ___PROCESSOR_SIZE && !tr.aborted; i++)
    local_tracer_mark_obj(&tr, ctx->processor_scmobj[___SUBTYPED_BODY + i]);

  /* 2. Read-only walk of active Scheme continuation stack frames on this processor */
  fp = ctx->fp;
  if (fp > ctx->stack_break)
    tr.aborted = 1;
  while (!tr.aborted && fp != ctx->stack_break)
    {
      ___frame_descriptor descriptor;
      ___frame_root_cursor cursor;
      int first, past, k;
      ___WORD ra2;

      if (!decode_source_stack_frame(fp, ctx->stack_break - fp, &ra, carry, &descriptor))
        {
          tr.aborted = 1;
          break;
        }
      fp += ___FRAME_SPACE(descriptor.fs);
      if (fp > ctx->stack_break)
        {
          tr.aborted = 1;
          break;
        }
      ra2 = ___FP_STK(fp, descriptor.link + 1);
      cursor = ___frame_ordinary_root_begin(&descriptor);
      while (!tr.aborted && ___frame_root_next_run(&cursor, &first, &past))
        {
          for (k = first; k < past && !tr.aborted; k++)
            local_tracer_mark_obj(&tr, ___FP_STK(fp, k));
        }
      ra = ra2;
      carry = 1;
    }

  if (!tr.aborted)
    {
      /* Check captured continuation link at break frame */
      local_tracer_mark_obj(&tr, ___FP_STK(fp, -___BREAK_FRAME_NEXT));
    }

  /* 3. Drain transitive local worklist (cycle-safe via tr.visited & STILL_MARK) */
  if (!tr.aborted)
    local_tracer_drain(&tr);

  /* 4. On abort: restore all STILL_MARK = 0 and fall back cleanly to global GC */
  if (tr.aborted)
    {
      ___WORD *base = ___CAST(___WORD*, ___ps->mem.young_still_objs_);
      while (base != 0)
        {
          base[___STILL_MARK] = 0;
          base = ___CAST(___WORD*, base[___STILL_LINK]);
        }
      return 0;
    }

  /* 5. Sweep unmarked dead young_still_objs locally into still_local_free_ (ZERO STW!) */
  {
    ___WORD *prev = 0;
    ___WORD *base = ___CAST(___WORD*, ___ps->mem.young_still_objs_);
    ___SIZE_TS freed_words = 0;
    ___SIZE_T freed_malloc_words = 0;

    while (base != 0)
      {
        ___WORD *next = ___CAST(___WORD*, base[___STILL_LINK]);
        if (base[___STILL_MARK] == -1 &&
            base[___STILL_REFCOUNT] == 0 &&
            ___HD_SUBTYPE(base[___STILL_BODY - 1]) != ___sFOREIGN)
          {
            ___SIZE_TS len = base[___STILL_LENGTH];
            if (prev == 0)
              ___ps->mem.young_still_objs_ = ___CAST(___WORD, next);
            else
              prev[___STILL_LINK] = ___CAST(___WORD, next);
            if (!free_mem_aligned_heap_ps(___ps, base) && len > 0)
              freed_malloc_words += (___SIZE_T)len;
            freed_words += len;
          }
        else
          {
            base[___STILL_MARK] = 0;
            prev = base;
          }
        base = next;
      }

    if (freed_malloc_words > 0)
      gc_record_freed_malloc_still_words(freed_malloc_words);

    if (freed_words > 0)
      {
        if (___ps->mem.words_still_objs_young_ >= freed_words)
          ___ps->mem.words_still_objs_young_ -= freed_words;
        else
          ___ps->mem.words_still_objs_young_ = 0;
        if (___ps->mem.words_still_objs_ >= freed_words)
          ___ps->mem.words_still_objs_ -= freed_words;
        else
          ___ps->mem.words_still_objs_ = 0;

        ALLOC_MEM_LOCK();
        if (occupied_words_still >= freed_words)
          occupied_words_still -= freed_words;
        else
          occupied_words_still = 0;
        ALLOC_MEM_UNLOCK();
      }

    /* Reset write-barrier card cache so any future mature write sets local_young_escaped_ = 1 */
    ___ps->mem.wb_last_card_lo_ = 0;
    return freed_words >= requested_words_still;
  }
#endif
}

/*
 * Phase A.3: Independent Processor-Local Movable Nursery Collection (Zero Global STW).
 *
 * When a processor's private young heap_msection fills (___heap_limit) and:
 *   - local_young_escaped_ == 0 (no pointer escaped to mature/global/SRFI-230/sibling),
 *   - young_still_objs_ == 0, major_phase_ == IDLE, no wills, primlock_depth == 0,
 *   - live movable objects in [alloc_heap_start_, hp) fit in a bounded 32 KiB scratch,
 * this processor compacts those live objects in-place to the start of its OWN
 * heap_msection half (preserving exact section parity!) and resets hp with ZERO
 * global STW (on_all_processors), ZERO ALLOC_MEM_LOCK, and ZERO cross-core barriers.
 */
#define ___LOCAL_MOV_SCRATCH_WORDS 4096u
#define ___LOCAL_MOV_MAX_LIVE      200u

typedef struct ___local_mov_compactor_struct
  {
    ___WORD *heap_lo;
    ___WORD *heap_hi;
    ___SCMOBJ live_objs[___LOCAL_MOV_MAX_LIVE];
    ___WORD *old_body[___LOCAL_MOV_MAX_LIVE];
    ___SIZE_TS new_off[___LOCAL_MOV_MAX_LIVE];
    ___SIZE_TS obj_words[___LOCAL_MOV_MAX_LIVE];
    unsigned int live_count;
    ___SIZE_TS total_live_words;
    ___UWORD vis_keys[___LOCAL_GC_VISITED_CAP];
    int vis_idx[___LOCAL_GC_VISITED_CAP];
    int aborted;
  } ___local_mov_compactor;

static inline int local_mov_lookup(___local_mov_compactor *mc, ___WORD *body)
{
  ___UWORD key = ___CAST(___UWORD, body);
  unsigned int mask = ___LOCAL_GC_VISITED_CAP - 1u;
  unsigned int slot = (unsigned int)(((key >> 4) ^ (key >> 11)) & mask);
  unsigned int probes;
  for (probes = 0u; probes < ___LOCAL_GC_VISITED_CAP; probes++)
    {
      ___UWORD cur = mc->vis_keys[slot];
      if (cur == key)
        return mc->vis_idx[slot];
      if (cur == 0u)
        return -1;
      slot = (slot + 1u) & mask;
    }
  return -1;
}

static inline void local_mov_mark(___local_mov_compactor *mc, ___SCMOBJ obj)
{
  ___WORD head;
  int htyp;
  ___WORD *body;
  ___UWORD key;
  unsigned int mask, slot, probes;
  ___SIZE_TS words, total_w;
  int subtype;

  if (mc->aborted || !___MEM_ALLOCATED(obj))
    return;

  head = ___HEADER(obj);
  htyp = ___HD_TYP(head);
  if (htyp != ___MOVABLE0)
    return; /* mature/perm/still: cannot point into unescaped local movable nursery */

  body = ___BODY0(obj);
  if (body < mc->heap_lo || body >= mc->heap_hi)
    return; /* mature movable */

  key = ___CAST(___UWORD, body);
  mask = ___LOCAL_GC_VISITED_CAP - 1u;
  slot = (unsigned int)(((key >> 4) ^ (key >> 11)) & mask);
  for (probes = 0u; probes < ___LOCAL_GC_VISITED_CAP; probes++)
    {
      ___UWORD cur = mc->vis_keys[slot];
      if (cur == key)
        return; /* already discovered */
      if (cur == 0u)
        break;
      slot = (slot + 1u) & mask;
    }
  if (probes >= ___LOCAL_GC_VISITED_CAP)
    {
      mc->aborted = 1;
      return;
    }

  subtype = ___HD_SUBTYPE(head);
  if (!local_tracer_is_leaf_subtype(subtype) &&
      subtype != ___sVECTOR && subtype != ___sPAIR &&
      subtype != ___sBOXVALUES && subtype != ___sSTRUCTURE &&
      subtype != ___sSYMBOL && subtype != ___sKEYWORD &&
      subtype != ___sRATNUM && subtype != ___sCPXNUM &&
      subtype != ___sMEROON && subtype != ___sJAZZ &&
      subtype != ___sPROCEDURE)
    {
      mc->aborted = 1;
      return;
    }

  words = ___HD_WORDS(head);
  total_w = words + 1;
  if (mc->live_count >= ___LOCAL_MOV_MAX_LIVE ||
      mc->total_live_words + total_w > ___LOCAL_MOV_SCRATCH_WORDS)
    {
      mc->aborted = 1;
      return;
    }

  {
    unsigned int idx = mc->live_count++;
    mc->vis_keys[slot] = key;
    mc->vis_idx[slot] = (int)idx;
    mc->live_objs[idx] = obj;
    mc->old_body[idx] = body;
    mc->new_off[idx] = mc->total_live_words;
    mc->obj_words[idx] = total_w;
    mc->total_live_words += total_w;
  }
}

static inline ___SCMOBJ local_mov_remap(___local_mov_compactor *mc, ___SCMOBJ obj)
{
  ___WORD head;
  ___WORD *body;
  int idx;
  if (!___MEM_ALLOCATED(obj))
    return obj;
  head = ___HEADER(obj);
  if (___HD_TYP(head) != ___MOVABLE0)
    return obj;
  body = ___BODY0(obj);
  if (body < mc->heap_lo || body >= mc->heap_hi)
    return obj;
  idx = local_mov_lookup(mc, body);
  if (idx < 0)
    return obj;
  return ___TAG(mc->heap_lo + mc->new_off[idx] + 1 - ___REFERENCE_TO_BODY, ___TYP(obj));
}

___HIDDEN ___BOOL try_local_movable_nursery_gc (___processor_state ___ps)
{
#if defined(___USE_HANDLES) || defined(___GAMBIT_REST_OBSERVATION) || defined(___GAMBIT_DEV_RESTORE_PROBE) || (___WS != 8)
  (void)___ps;
  return 0;
#else
  ___virtual_machine_state vm;
  ___execution_context *ctx;
  ___WORD *hp;
  ___WORD *heap_lo;
  ___SIZE_TS used_words;
  ___local_mov_compactor mc;
  ___WORD *fp;
  ___WORD ra = 0;
  int carry = 0;
  int i;
  unsigned int scan_idx;

  if (___ps == 0 || ___ps != ___PSTATE || !___lifecycle_gc_admitted(___ps))
    return 0;
  if (___ps->primlock_depth != 0)
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0)
    return 0;

  if (___ps->mem.local_young_escaped_ != 0)
    return 0;
  if (___ps->mem.young_still_objs_ != 0)
    return 0;
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE ||
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_request_start_) != 0 ||
      vm->mem.major_evacuate_count_ >= 2)
    return 0;
  if (___UNTAG(___ps->mem.nonexecutable_wills_) != 0 ||
      ___UNTAG(___ps->mem.executable_wills_) != 0)
    return 0;

  ctx = ___ps->context;
  if (ctx == 0 || ctx->fp == 0 || ctx->stack_break == 0 ||
      ___ps->mem.heap_msection_ == 0)
    return 0;

  hp = ctx->hp;
  heap_lo = ___ps->mem.alloc_heap_start_;
  if (hp == 0 || heap_lo == 0 || hp < heap_lo || hp > ___ps->mem.alloc_heap_limit_)
    return 0;

  used_words = (___SIZE_TS)(hp - heap_lo);
  if (used_words < 16384)
    return 0;

  mc.heap_lo = heap_lo;
  mc.heap_hi = hp;
  mc.live_count = 0u;
  mc.total_live_words = 0;
  mc.aborted = 0;
  memset(mc.vis_keys, 0, sizeof(mc.vis_keys));

  /* Pass 1: Read-only transitive root trace over [heap_lo, hp) */
  for (i = 0; i < ___NB_GVM_REGS && !mc.aborted; i++)
    local_mov_mark(&mc, ctx->r[i]);
  for (i = 0; i < 3 && !mc.aborted; i++)
    local_mov_mark(&mc, ctx->saved[i]);
  for (i = 0; i < 2 && !mc.aborted; i++)
    local_mov_mark(&mc, ctx->type_cache[i]);
  for (i = 0; i < ___PROCESSOR_SIZE && !mc.aborted; i++)
    local_mov_mark(&mc, ctx->processor_scmobj[___SUBTYPED_BODY + i]);

  fp = ctx->fp;
  if (fp > ctx->stack_break)
    mc.aborted = 1;
  while (!mc.aborted && fp != ctx->stack_break)
    {
      ___frame_descriptor descriptor;
      ___frame_root_cursor cursor;
      int first, past, k;
      ___WORD ra2;

      if (!decode_source_stack_frame(fp, ctx->stack_break - fp, &ra, carry, &descriptor))
        {
          mc.aborted = 1;
          break;
        }
      fp += ___FRAME_SPACE(descriptor.fs);
      if (fp > ctx->stack_break)
        {
          mc.aborted = 1;
          break;
        }
      ra2 = ___FP_STK(fp, descriptor.link + 1);
      cursor = ___frame_ordinary_root_begin(&descriptor);
      while (!mc.aborted && ___frame_root_next_run(&cursor, &first, &past))
        {
          for (k = first; k < past && !mc.aborted; k++)
            local_mov_mark(&mc, ___FP_STK(fp, k));
        }
      ra = ra2;
      carry = 1;
    }

  if (!mc.aborted)
    local_mov_mark(&mc, ___FP_STK(fp, -___BREAK_FRAME_NEXT));

  /* BFS drain over discovered live objects (cycle-safe via mc.vis_keys) */
  for (scan_idx = 0u; !mc.aborted && scan_idx < mc.live_count; scan_idx++)
    {
      ___SCMOBJ obj = mc.live_objs[scan_idx];
      ___WORD head = ___HEADER(obj);
      int subtype = ___HD_SUBTYPE(head);
      ___SIZE_TS words = ___HD_WORDS(head);
      ___WORD *body = mc.old_body[scan_idx];
      ___SIZE_TS j;

      if (local_tracer_is_leaf_subtype(subtype))
        continue;
      if (subtype == ___sPROCEDURE)
        {
          for (j = 1; j < words && !mc.aborted; j++)
            local_mov_mark(&mc, body[j]);
        }
      else
        {
          for (j = 0; j < words && !mc.aborted; j++)
            local_mov_mark(&mc, body[j]);
        }
    }

  if (mc.aborted)
    return 0;

  /* Fast zero-live path: 0 live objects in local nursery -> O(1) instant reset! */
  if (mc.live_count == 0u)
    {
      ctx->hp = heap_lo;
      ___ps->mem.alloc_heap_ptr_ = heap_lo;
      ___ps->mem.bytes_allocated_minus_occupied_ += (___F64)used_words * ___WS;
      ___ps->mem.wb_last_card_lo_ = 0;
      return 1;
    }

  /* Pass 2: Copy live objects to stack scratch, remap internal & root pointers, copy back */
  {
    ___WORD scratch[___LOCAL_MOV_SCRATCH_WORDS];
    unsigned int k;

    for (k = 0u; k < mc.live_count; k++)
      {
        ___WORD *dst = &scratch[mc.new_off[k]];
        ___WORD *src = mc.old_body[k] - 1;
        ___SIZE_TS total_w = mc.obj_words[k];
        ___WORD head = src[0];
        int subtype = ___HD_SUBTYPE(head);
        ___SIZE_TS j;

        memcpy(dst, src, (___SIZE_T)total_w * sizeof(___WORD));
        if (!local_tracer_is_leaf_subtype(subtype))
          {
            ___SIZE_TS start_j = (subtype == ___sPROCEDURE) ? 2 : 1;
            for (j = start_j; j < total_w; j++)
              dst[j] = local_mov_remap(&mc, dst[j]);
          }
      }

    /* Remap all processor-private root slots */
    for (i = 0; i < ___NB_GVM_REGS; i++)
      ctx->r[i] = local_mov_remap(&mc, ctx->r[i]);
    for (i = 0; i < 3; i++)
      ctx->saved[i] = local_mov_remap(&mc, ctx->saved[i]);
    for (i = 0; i < 2; i++)
      ctx->type_cache[i] = local_mov_remap(&mc, ctx->type_cache[i]);
    for (i = 0; i < ___PROCESSOR_SIZE; i++)
      ctx->processor_scmobj[___SUBTYPED_BODY + i] =
        local_mov_remap(&mc, ctx->processor_scmobj[___SUBTYPED_BODY + i]);

    fp = ctx->fp;
    ra = 0;
    carry = 0;
    while (fp != ctx->stack_break)
      {
        ___frame_descriptor descriptor;
        ___frame_root_cursor cursor;
        int first, past, sidx;
        ___WORD ra2;

        decode_source_stack_frame(fp, ctx->stack_break - fp, &ra, carry, &descriptor);
        fp += ___FRAME_SPACE(descriptor.fs);
        ra2 = ___FP_STK(fp, descriptor.link + 1);
        cursor = ___frame_ordinary_root_begin(&descriptor);
        while (___frame_root_next_run(&cursor, &first, &past))
          {
            for (sidx = first; sidx < past; sidx++)
              ___FP_SET_STK(fp, sidx, local_mov_remap(&mc, ___FP_STK(fp, sidx)));
          }
        ra = ra2;
        carry = 1;
      }

    /* Copy compacted live objects back to start of same half (preserving parity!) */
    memcpy(heap_lo, scratch, (___SIZE_T)mc.total_live_words * sizeof(___WORD));
    ctx->hp = heap_lo + mc.total_live_words;
    ___ps->mem.alloc_heap_ptr_ = ctx->hp;
    ___ps->mem.bytes_allocated_minus_occupied_ +=
      (___F64)(used_words - mc.total_live_words) * ___WS;
    ___ps->mem.wb_last_card_lo_ = 0;
    return 1;
  }
#endif
}

#endif /* ___LOCAL_NURSERY_INC */
