/* Slice 2 (v2 Production System): Concurrent SATB Major GC and Non-Moving
 * Immix Mark-Region Mature Space with:
 *   - Per-processor lock-free local mark-stack buffers (128 entries, batch
 *     spill/steal under major_mark_lock_),
 *   - 4-barrier parallel STW Remark (parallel SATB/local-buffer/mark-stack
 *     drain with atomic worker quiescence + atomic weak-table dead-entry
 *     clearing BEFORE SWEEPING + parallel non-moving Immix section sweep
 *     & coalesced card-aligned dead-hole discovery + parallel mature still
 *     sweep),
 *   - Immix 64-word card-aligned dead-line hole recycling during IDLE Minor
 *     GCs and immediate post-Remark heap contraction,
 *   - Idle-core cooperative concurrent marking before scheduler sleep. */

#ifndef ___CONCURRENT_MAJOR_INC
#define ___CONCURRENT_MAJOR_INC

#define ___GC_MAJOR_ACTION_NONE       0
#define ___GC_MAJOR_ACTION_START      1
#define ___GC_MAJOR_ACTION_DRAIN_SATB 2
#define ___GC_MAJOR_ACTION_REMARK     3
#define ___GC_MAJOR_ACTION_ABORT      4

#define ___GC_IMMIX_MIN_HOLE_WORDS    512

typedef struct major_local_queue_struct
  {
    ___SCMOBJ *buf;
    unsigned int *count;
    unsigned int cap;
  } major_local_queue;

static inline void major_mark_lock(___virtual_machine_state vm)
{
#ifndef ___SINGLE_THREADED_VMS
  for (;;)
    {
      ___WORD expected = 0;
      if (___WORD_CAS_ACQUIRE(&vm->mem.major_mark_lock_, expected, 1))
        break;
      ___CPU_RELAX();
    }
#else
  (void)vm;
#endif
}

static inline int major_mark_trylock(___virtual_machine_state vm)
{
#ifndef ___SINGLE_THREADED_VMS
  ___WORD expected = 0;
  return ___WORD_CAS_ACQUIRE(&vm->mem.major_mark_lock_, expected, 1) ? 1 : 0;
#else
  (void)vm;
  return 1;
#endif
}

static inline void major_mark_unlock(___virtual_machine_state vm)
{
#ifndef ___SINGLE_THREADED_VMS
  ___WORD_STORE_RELEASE(&vm->mem.major_mark_lock_, 0);
#else
  (void)vm;
#endif
}

static inline ___SCMOBJ major_make_scmobj_from_body(___WORD *body, int subtype)
{
#if ___tPAIR != ___tSUBTYPED
  if (subtype == ___sPAIR)
    return ___PAIR_FROM_BODY(body);
#endif
#ifndef ___NAN_BOXING
#if ___tFLONUM != ___tSUBTYPED
  if (subtype == ___sFLONUM)
    return ___FLONUM_FROM_BODY(body);
#endif
#endif
#if ___tVECTOR != ___tSUBTYPED
  if (subtype == ___sVECTOR)
    return ___VECTOR_FROM_BODY(body);
#endif
  return ___SUBTYPED_FROM_BODY(body);
}

static inline ___msection *major_find_mature_section_ro
   (___virtual_machine_state vm,
    ___UWORD addr)
{
  int nm = vm->mem.nb_msections_mature_;
  ___UWORD half_bytes = ___CAST(___UWORD, ___MSECTION_SIZE >> 1) * ___WS;
  ___msection **arr;
  int lo, hi;
  ___msection *sec;

  if (nm <= 0)
    return 0;
  if (addr - vm->mem.mature_addr_lo_ >= vm->mem.mature_addr_span_)
    return 0;

  arr = vm->mem.mature_sections_;
  lo = 0;
  hi = nm - 1;
  while (lo < hi)
    {
      int mid = (lo + hi + 1) >> 1;
      if (___CAST(___UWORD, arr[mid]->base) <= addr)
        lo = mid;
      else
        hi = mid - 1;
    }
  sec = arr[lo];
  if (addr - ___CAST(___UWORD, sec->base + sec->active_offset) < half_bytes)
    return sec;
  return 0;
}

static inline ___WORD *major_find_mature_still_base_ro
   (___virtual_machine_state vm,
    ___WORD *cand_base)
{
  ___SIZE_TS n = vm->mem.major_still_bases_count_;
  ___UWORD addr = ___CAST(___UWORD, cand_base);
  ___WORD **arr;
  ___SIZE_TS lo, hi;

  if (n <= 0 || vm->mem.major_still_span_ == 0)
    return 0;
  if (addr - vm->mem.major_still_lo_ >= vm->mem.major_still_span_)
    return 0;

  arr = vm->mem.major_still_bases_;
  lo = 0;
  hi = n;
  while (lo < hi)
    {
      ___SIZE_TS mid = lo + ((hi - lo) >> 1);
      ___UWORD maddr = ___CAST(___UWORD, arr[mid]);
      if (maddr == addr)
        return arr[mid];
      if (maddr < addr)
        lo = mid + 1;
      else
        hi = mid;
    }
  return 0;
}

static inline int major_is_marked_word(___msection *sec, ___SIZE_TS off)
{
  ___VOLATILE ___WORD *mbits;
  ___SIZE_TS w;
  ___UWORD bit;

  if (off >= sec->major_snapshot_words)
    return 1;
  mbits = section_major_mark_bits(sec);
  w = off / ___WORD_WIDTH;
  bit = ___CAST(___UWORD, 1) << (off & (___WORD_WIDTH - 1));
  return (___CAST(___UWORD, ___WORD_LOAD_ACQUIRE(&mbits[w])) & bit) != 0;
}

/* Check whether any global or per-processor local mark-stack work remains.
 * Called only during STW (prepare_generational_round). */
___HIDDEN int major_has_pending_mark_work(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) > 0)
    return 1;
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      if (ps->mem.major_mark_local_count_ > 0 || ps->mem.satb_count_ > 0)
        return 1;
    }
  return 0;
}

/* Batch push onto global major mark stack under ONE lock acquisition.
 * When allow_alloc == 0 (inside mutator write barriers), never allocate; mark
 * sticky satb_overflow_ if full so STW Remark runs complete overflow recovery. */
___HIDDEN void major_mark_stack_push_batch_ex
   (___virtual_machine_state vm,
    const ___SCMOBJ *items,
    unsigned int n,
    int allow_alloc)
{
  ___SIZE_TS cur;
  if (n == 0)
    return;
  major_mark_lock(vm);
  cur = ___CAST(___SIZE_TS, ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_));
  if (cur + ___CAST(___SIZE_TS, n) > vm->mem.major_mark_stack_cap_)
    {
      if (!allow_alloc)
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
          major_mark_unlock(vm);
          return;
        }
      {
        ___SIZE_TS need = cur + ___CAST(___SIZE_TS, n);
        ___SIZE_TS ncap = vm->mem.major_mark_stack_cap_
                            ? (vm->mem.major_mark_stack_cap_ * 2)
                            : 4096;
        ___SCMOBJ *nbuf;
        while (ncap < need)
          ncap *= 2;
        nbuf = ___CAST(___SCMOBJ*, ___ALLOC_MEM(ncap * sizeof(___SCMOBJ)));
        if (nbuf == 0)
          {
            ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
            major_mark_unlock(vm);
            return;
          }
        if (cur > 0 && vm->mem.major_mark_stack_ != 0)
          memcpy(nbuf, vm->mem.major_mark_stack_, cur * sizeof(___SCMOBJ));
        if (vm->mem.major_mark_stack_ != 0)
          ___FREE_MEM(vm->mem.major_mark_stack_);
        vm->mem.major_mark_stack_ = nbuf;
        vm->mem.major_mark_stack_cap_ = ncap;
      }
    }
  memcpy(&vm->mem.major_mark_stack_[cur], items, n * sizeof(___SCMOBJ));
  ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, ___CAST(___WORD, cur + n));
  major_mark_unlock(vm);
}

___HIDDEN void major_mark_stack_push_ex
   (___virtual_machine_state vm,
    ___SCMOBJ obj,
    int allow_alloc)
{
  major_mark_stack_push_batch_ex(vm, &obj, 1, allow_alloc);
}

static inline void major_mark_push_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___SCMOBJ obj,
    int allow_alloc)
{
  if (q != 0)
    {
      unsigned int cnt = *q->count;
      if (cnt >= q->cap)
        {
          unsigned int half = q->cap >> 1;
          major_mark_stack_push_batch_ex(vm, &q->buf[half], cnt - half, allow_alloc);
          cnt = half;
        }
      q->buf[cnt++] = obj;
      *q->count = cnt;
      return;
    }
  major_mark_stack_push_ex(vm, obj, allow_alloc);
}

___HIDDEN void major_register_weak_table
   (___virtual_machine_state vm,
    ___SCMOBJ ht)
{
  major_mark_lock(vm);
  if (vm->mem.major_weak_tables_count_ >= vm->mem.major_weak_tables_cap_)
    {
      ___SIZE_TS ncap = vm->mem.major_weak_tables_cap_
                          ? (vm->mem.major_weak_tables_cap_ * 2)
                          : 128;
      ___SCMOBJ *nbuf = ___CAST(___SCMOBJ*, ___ALLOC_MEM(ncap * sizeof(___SCMOBJ)));
      if (nbuf == 0)
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
          major_mark_unlock(vm);
          return;
        }
      if (vm->mem.major_weak_tables_count_ > 0 && vm->mem.major_weak_tables_ != 0)
        memcpy(nbuf, vm->mem.major_weak_tables_,
               vm->mem.major_weak_tables_count_ * sizeof(___SCMOBJ));
      if (vm->mem.major_weak_tables_ != 0)
        ___FREE_MEM(vm->mem.major_weak_tables_);
      vm->mem.major_weak_tables_ = nbuf;
      vm->mem.major_weak_tables_cap_ = ncap;
    }
  vm->mem.major_weak_tables_[vm->mem.major_weak_tables_count_++] = ht;
  major_mark_unlock(vm);
}

___HIDDEN void major_shade_mature_movable_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___msection *sec,
    ___WORD *header,
    ___WORD head,
    int allow_alloc)
{
  ___WORD *half_base = sec->base + sec->active_offset;
  ___SIZE_TS off;
  ___VOLATILE ___WORD *mbits;
  ___SIZE_TS w;
  ___UWORD bit, prev;
  ___SIZE_TS words;
  int subtype;

  if (sec->major_mark_epoch != vm->mem.major_epoch_)
    return;
  off = ___CAST(___SIZE_TS, header - half_base);
  if (off < 0 || off >= sec->major_snapshot_words)
    return;

  mbits = section_major_mark_bits(sec);
  w = off / ___WORD_WIDTH;
  bit = ___CAST(___UWORD, 1) << (off & (___WORD_WIDTH - 1));
  if ((___CAST(___UWORD, ___WORD_LOAD_RELAXED(&mbits[w])) & bit) != 0)
    return;
  prev = ___CAST(___UWORD, ___WORD_FETCH_OR_RELEASE(&mbits[w], ___CAST(___WORD, bit)));
  if ((prev & bit) != 0)
    return;

  words = ___HD_WORDS(head);
  subtype = ___HD_SUBTYPE(head);
  ___WORD_FETCH_ADD_RELEASE(&sec->major_live_words, ___CAST(___WORD, words + 1));

  /* Record 128-word Immix line occupancy. */
  {
    ___SIZE_TS max_lines = 8 * ___WORD_WIDTH;
    ___SIZE_TS line_lo = off >> 7;
    ___SIZE_TS line_hi = (off + words) >> 7;
    ___SIZE_TS ln;
    if (line_hi >= max_lines)
      line_hi = max_lines - 1;
    for (ln = line_lo; ln <= line_hi; ln++)
      {
        ___VOLATILE ___WORD *lw =
          ___CAST(___VOLATILE ___WORD*, &sec->major_line_live[ln / ___WORD_WIDTH]);
        ___UWORD lbit = ___CAST(___UWORD, 1) << (ln & (___WORD_WIDTH - 1));
        if ((___CAST(___UWORD, ___WORD_LOAD_RELAXED(lw)) & lbit) == 0)
          ___WORD_FETCH_OR_RELEASE(lw, ___CAST(___WORD, lbit));
      }
  }

  /* Leaf objects are immediately BLACK without mark-stack traffic. */
  if (!still_subtype_has_pointers(subtype))
    return;

  major_mark_push_q(vm, q, major_make_scmobj_from_body(header + 1, subtype), allow_alloc);
}

___HIDDEN void major_shade_mature_movable
   (___virtual_machine_state vm,
    ___msection *sec,
    ___WORD *header,
    ___WORD head)
{
  major_shade_mature_movable_q(vm, 0, sec, header, head, 1);
}

___HIDDEN void major_shade_mature_still_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___WORD *base,
    ___WORD head,
    int allow_alloc)
{
#ifndef ___USE_HANDLES
  ___WORD mbit = ___STILL_MAJOR_MARK_BIT(vm->mem.major_epoch_);
  ___VOLATILE ___WORD *dptr = &base[___STILL_DIRTY];
  ___WORD flags = ___WORD_LOAD_RELAXED(dptr);

  if ((flags & (___STILL_FLAG_YOUNG | mbit)) != 0)
    return;
  if ((___WORD_FETCH_OR_RELEASE(dptr, mbit) & mbit) != 0)
    return;

  if (still_subtype_has_pointers(___HD_SUBTYPE(head)))
    major_mark_push_q(
      vm, q,
      major_make_scmobj_from_body(base + ___STILL_BODY, ___HD_SUBTYPE(head)),
      allow_alloc);
#else
  (void)vm;
  (void)q;
  (void)base;
  (void)head;
  (void)allow_alloc;
#endif
}

___HIDDEN void major_shade_mature_still
   (___virtual_machine_state vm,
    ___WORD *base,
    ___WORD head)
{
  major_shade_mature_still_q(vm, 0, base, head, 1);
}

/* Address-only classification: never dereferences young movable, young still,
 * newly promoted BLACK objects, or permanent objects. Completely data-race
 * free under C23/PSO/TSan when called concurrently with mutators. */
___HIDDEN void major_shade_obj_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___SCMOBJ val,
    int allow_alloc)
{
  ___WORD *body;
  ___WORD *hdr;
  ___msection *sec;

  if (!___MEM_ALLOCATED(val))
    return;

  body = ___BODY0(val);
  hdr = body - 1;
  sec = major_find_mature_section_ro(vm, ___CAST(___UWORD, hdr));
  if (sec != 0)
    {
      ___SIZE_TS off = ___CAST(___SIZE_TS, hdr - (sec->base + sec->active_offset));
      if (off < sec->major_snapshot_words)
        {
          ___WORD head = ___WORD_LOAD_RELAXED(hdr);
          if (___HD_TYP(head) == ___MOVABLE0)
            major_shade_mature_movable_q(vm, q, sec, hdr, head, allow_alloc);
        }
      return;
    }

  if (vm->mem.major_still_bases_count_ > 0)
    {
      ___WORD *base = major_find_mature_still_base_ro(vm, body - ___STILL_BODY);
      if (base != 0)
        {
          ___WORD head = ___WORD_LOAD_RELAXED(&base[___STILL_HEADER]);
          if (___HD_TYP(head) == ___STILL)
            major_shade_mature_still_q(vm, q, base, head, allow_alloc);
        }
    }
}

___HIDDEN void major_shade_obj_ex
   (___virtual_machine_state vm,
    ___SCMOBJ val,
    int allow_alloc)
{
  major_shade_obj_q(vm, 0, val, allow_alloc);
}

/* Non-allocating, non-collecting SATB pre-store and weak-read barriers. */
___EXP_FUNC(void,___gc_satb_barrier_val)
   ___P((___processor_state ___ps,
         ___SCMOBJ old_val),
        (___ps,
         old_val)
___processor_state ___ps;
___SCMOBJ old_val;)
{
  ___virtual_machine_state vm;
  unsigned int i;

  if (___ps == 0 || !___MEM_ALLOCATED(old_val))
    return;

  if (___ps->mem.satb_buf_ != 0 && ___ps->mem.satb_count_ < ___GC_SATB_BUF_CAP)
    {
      ___ps->mem.satb_buf_[___ps->mem.satb_count_++] = old_val;
      return;
    }

  /* Local SATB buffer full: flush into lock-free local mark buffer (spilling
   * to global without allocating). Sticky satb_overflow_ triggers full Remark
   * recovery if global stack capacity is exceeded (Quint Mutant 7). */
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    {
      ___ps->mem.satb_count_ = 0;
      return;
    }

  if (___ps->mem.major_mark_local_buf_ != 0)
    {
      major_local_queue lq;
      lq.buf = ___ps->mem.major_mark_local_buf_;
      lq.count = &___ps->mem.major_mark_local_count_;
      lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;
      if (___ps->mem.satb_buf_ != 0)
        {
          for (i = 0; i < ___ps->mem.satb_count_; i++)
            major_shade_obj_q(vm, &lq, ___ps->mem.satb_buf_[i], 0);
        }
      ___ps->mem.satb_count_ = 0;
      major_shade_obj_q(vm, &lq, old_val, 0);
    }
  else
    {
      if (___ps->mem.satb_buf_ != 0)
        {
          for (i = 0; i < ___ps->mem.satb_count_; i++)
            major_shade_obj_q(vm, 0, ___ps->mem.satb_buf_[i], 0);
        }
      ___ps->mem.satb_count_ = 0;
      major_shade_obj_q(vm, 0, old_val, 0);
    }
}

___EXP_FUNC(void,___gc_satb_barrier_slot)
   ___P((___processor_state ___ps,
         ___WORD *slot_ptr),
        (___ps,
         slot_ptr)
___processor_state ___ps;
___WORD *slot_ptr;)
{
  ___SCMOBJ old_val;
  if (___ps == 0 || slot_ptr == 0)
    return;
  old_val = ___WORD_LOAD_RELAXED(slot_ptr);
  if (___MEM_ALLOCATED(old_val))
    ___gc_satb_barrier_val(___ps, old_val);
}

___EXP_FUNC(void,___gc_satb_barrier_range)
   ___P((___processor_state ___ps,
         ___WORD *start_ptr,
         ___SIZE_TS words),
        (___ps,
         start_ptr,
         words)
___processor_state ___ps;
___WORD *start_ptr;
___SIZE_TS words;)
{
  ___SIZE_TS i;
  if (___ps == 0 || start_ptr == 0 || words <= 0)
    return;
  for (i = 0; i < words; i++)
    {
      ___SCMOBJ old_val = ___WORD_LOAD_RELAXED(&start_ptr[i]);
      if (___MEM_ALLOCATED(old_val))
        ___gc_satb_barrier_val(___ps, old_val);
    }
}

/* Scan one popped mature object (concurrent when is_stw == 0, STW Remark when
 * is_stw == 1). Returns words scanned, or -1 if concurrent weak-table scan hit
 * an active in-situ rehash and requeued obj. */
___HIDDEN ___SIZE_TS major_scan_object_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___SCMOBJ obj,
    int is_stw)
{
  ___WORD *body = ___BODY0(obj);
  ___WORD head = ___WORD_LOAD_RELAXED(body - 1);
  ___SIZE_TS words = ___HD_WORDS(head);
  int subtype = ___HD_SUBTYPE(head);
  ___SIZE_TS i;

  switch (subtype)
    {
    case ___sFOREIGN:
    case ___sSTRING:
    case ___sS8VECTOR:
    case ___sU8VECTOR:
    case ___sS16VECTOR:
    case ___sU16VECTOR:
    case ___sS32VECTOR:
    case ___sU32VECTOR:
    case ___sS64VECTOR:
    case ___sU64VECTOR:
    case ___sF32VECTOR:
    case ___sF64VECTOR:
    case ___sFLONUM:
    case ___sBIGNUM:
      break;

    case ___sWEAK:
      if (words == ___WILL_SIZE)
        {
          ___WORD wnext = ___WORD_LOAD_RELAXED(&body[___WILL_NEXT]);
          major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[___WILL_ACTION]), 1);
          if (wnext & ___EXECUTABLE_WILL)
            major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[___WILL_TESTATOR]), 1);
        }
      else
        {
          ___VOLATILE ___WORD *flags_ptr =
            ___CAST(___VOLATILE ___WORD*, &body[___GCHASHTABLE_FLAGS]);
          int flags;
          int pinned = 0;

          if (!is_stw)
            {
              ___WORD fword = ___WORD_LOAD_ACQUIRE(flags_ptr);
              if (!___FIXZEROP(___FIXAND(fword, ___FIX(___GCHASHTABLE_FLAG_REHASHING))))
                {
                  major_mark_stack_push_ex(vm, obj, 1);
                  return -1;
                }
              {
                ___WORD want = ___FIXADD(fword, ___FIX(___GCHASHTABLE_CURSOR_UNIT));
                if (!___WORD_CAS_ACQUIRE(flags_ptr, fword, want))
                  {
                    major_mark_stack_push_ex(vm, obj, 1);
                    return -1;
                  }
                pinned = 1;
                flags = ___INT(fword);
              }
            }
          else
            {
              flags = ___INT(___WORD_LOAD_RELAXED(flags_ptr));
            }

          if ((flags & ___GCHASHTABLE_FLAG_WEAK_KEYS) == 0 &&
              (flags & ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS))
            {
              for (i = words - 2; i >= ___GCHASHTABLE_KEY0; i -= 2)
                major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[i]), 1);
            }

          if ((flags & ___GCHASHTABLE_FLAG_WEAK_VALS) == 0)
            {
              for (i = words - 1; i >= ___GCHASHTABLE_VAL0; i -= 2)
                major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[i]), 1);
            }

          if ((flags & (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_WEAK_VALS)) != 0)
            major_register_weak_table(vm, obj);

          if (pinned)
            ___WORD_FETCH_ADD_RELEASE(flags_ptr, -___FIX(___GCHASHTABLE_CURSOR_UNIT));
        }
      break;

    case ___sSYMBOL:
    case ___sKEYWORD:
      major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[0]), 1);
      break;

    case ___sCONTINUATION:
      major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[___CONTINUATION_FRAME]), 1);
      for (i = 1; i < words; i++)
        major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[i]), 1);
      break;

    case ___sFRAME:
      {
        ___frame_descriptor descriptor;
        if (___decode_heap_frame_descriptor(body, ___GSTATE->internal_return, &descriptor) &&
            words == ___CAST(___SIZE_TS, descriptor.fs + ___FRAME_EXTRA_SLOTS))
          {
            ___WORD *fp = body + ___FRAME_EXTRA_SLOTS + descriptor.fs;
            ___frame_root_cursor cursor = ___frame_ordinary_root_begin(&descriptor);
            int first, past;
            while (___frame_root_next_run(&cursor, &first, &past))
              {
                ___WORD *run = &___FP_STK(fp, past - 1);
                int cnt = past - first;
                int k;
                for (k = 0; k < cnt; k++)
                  major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&run[k]), 1);
              }
            {
              ___WORD *link_slot = ___frame_heap_link_ptr(body, &descriptor);
              ___WORD frame = ___WORD_LOAD_RELAXED(link_slot);
              if (___MEM_ALLOCATED(frame))
                major_shade_obj_q(vm, q, frame, 1);
            }
            major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[0]), 1);
          }
      }
      break;

    case ___sPROCEDURE:
      for (i = ___CLO_FREEVARS; i < words; i++)
        major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[i]), 1);
      break;

    default:
      for (i = 0; i < words; i++)
        major_shade_obj_q(vm, q, ___WORD_LOAD_RELAXED(&body[i]), 1);
      break;
    }

  return words + 1;
}

/* Cooperative concurrent marking slice invoked by mutators at allocation
 * boundaries (with primlock_depth == 0), idle cores before sleeping, or
 * explicitly from tests. Uses per-processor lock-free local mark buffer with
 * batch steal/spill to minimize spinlock contention on SMP. */
___EXP_FUNC(___SIZE_TS,___gc_major_mark_slice)
   ___P((___processor_state ___ps,
         ___SIZE_TS budget_words),
        (___ps,
         budget_words)
___processor_state ___ps;
___SIZE_TS budget_words;)
{
  ___virtual_machine_state vm;
  ___SIZE_TS scanned = 0;
  major_local_queue lq;
  unsigned int i;

  if (___ps == 0 || budget_words <= 0)
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    return 0;
  if (___ps->mem.major_mark_local_buf_ == 0)
    return 0;

  lq.buf = ___ps->mem.major_mark_local_buf_;
  lq.count = &___ps->mem.major_mark_local_count_;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;

  /* Drain this processor's local SATB buffer directly into local mark buffer. */
  if (___ps->mem.satb_buf_ != 0 && ___ps->mem.satb_count_ > 0)
    {
      unsigned int n = ___ps->mem.satb_count_;
      ___SCMOBJ local_copy[___GC_SATB_BUF_CAP];
      memcpy(local_copy, ___ps->mem.satb_buf_, n * sizeof(___SCMOBJ));
      ___ps->mem.satb_count_ = 0;
      for (i = 0; i < n; i++)
        major_shade_obj_q(vm, &lq, local_copy[i], 1);
      major_mark_lock(vm);
      vm->mem.concurrent_major_satb_logged_ += ___CAST(___F64, n);
      major_mark_unlock(vm);
    }

  while (scanned < budget_words)
    {
      if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
        break;

      if (*lq.count == 0)
        {
          ___WORD avail;
          unsigned int take = 0;
          if (!major_mark_trylock(vm))
            break;
          avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
          if (avail > 0)
            {
              take = (avail > 64) ? 64u : ___CAST(unsigned int, avail);
              avail -= ___CAST(___WORD, take);
              memcpy(lq.buf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
              ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
              *lq.count = take;
            }
          major_mark_unlock(vm);
          if (take == 0)
            break;
        }

      {
        ___SCMOBJ obj = lq.buf[--(*lq.count)];
        ___SIZE_TS w = major_scan_object_q(vm, &lq, obj, 0);
        if (w < 0)
          break;
        scanned += w;
      }
    }

  /* Share excess local work back to global stack so other/idle cores can steal. */
  if (*lq.count > 32 &&
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) == ___GC_MAJOR_MARKING)
    {
      unsigned int spill = *lq.count - 32;
      major_mark_stack_push_batch_ex(vm, &lq.buf[32], spill, 1);
      *lq.count = 32;
    }

  if (scanned > 0)
    {
      major_mark_lock(vm);
      vm->mem.concurrent_major_mark_slices_ += 1.0;
      vm->mem.concurrent_major_marked_words_ += ___CAST(___F64, scanned);
      major_mark_unlock(vm);
    }
  return scanned;
}

/* Idle-core cooperative marking hook invoked from SMP scheduler right before
 * sleeping in ##wait-idle-if-unchanged!. Fast 1-load exit when idle. */
___EXP_FUNC(int,___gc_major_mark_idle_slice)
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
  ___virtual_machine_state vm;
  ___SIZE_TS w;

  if (___ps == 0 || ___ps->primlock_depth != 0)
    return 0;
  if (___EXPECT_TRUE(___WORD_LOAD_RELAXED(&___ps->mem.satb_active_) == 0))
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    return 0;
  if (___ps->mem.major_mark_local_count_ == 0 &&
      ___ps->mem.satb_count_ == 0 &&
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) == 0)
    return 0;

  w = ___gc_major_mark_slice(___ps, 32768);
  if (w > 0)
    {
      major_mark_lock(vm);
      vm->mem.concurrent_major_idle_slices_ += 1.0;
      major_mark_unlock(vm);
      return 1;
    }
  return 0;
}

/* Heapsort helper for mature still base address snapshot (zero libc qsort
 * callback indirection, strictly O(S log S) worst-case). */
___HIDDEN void major_sort_still_bases(___WORD **arr, ___SIZE_TS n)
{
  ___SIZE_TS i;
  if (n < 2)
    return;
  for (i = n / 2; i > 0; i--)
    {
      ___SIZE_TS root = i - 1;
      for (;;)
        {
          ___SIZE_TS child = root * 2 + 1;
          if (child >= n)
            break;
          if (child + 1 < n &&
              ___CAST(___UWORD, arr[child]) < ___CAST(___UWORD, arr[child + 1]))
            child++;
          if (___CAST(___UWORD, arr[root]) < ___CAST(___UWORD, arr[child]))
            {
              ___WORD *tmp = arr[root];
              arr[root] = arr[child];
              arr[child] = tmp;
              root = child;
            }
          else
            break;
        }
    }
  for (i = n - 1; i > 0; i--)
    {
      ___WORD *tmp = arr[0];
      ___SIZE_TS root = 0;
      arr[0] = arr[i];
      arr[i] = tmp;
      for (;;)
        {
          ___SIZE_TS child = root * 2 + 1;
          if (child >= i)
            break;
          if (child + 1 < i &&
              ___CAST(___UWORD, arr[child]) < ___CAST(___UWORD, arr[child + 1]))
            child++;
          if (___CAST(___UWORD, arr[root]) < ___CAST(___UWORD, arr[child]))
            {
              ___WORD *t2 = arr[root];
              arr[root] = arr[child];
              arr[child] = t2;
              root = child;
            }
          else
            break;
        }
    }
}

/* STW Initial-Mark piggybacked onto a Minor GC (before mark_strong_phase). */
___HIDDEN void major_initial_mark_begin(___virtual_machine_state vm)
{
  ___msections *ms = vm->mem.the_msections_;
  ___msection *sec;
  int np = vm->processor_count;
  int p;
  ___UWORD epoch;
  ___SIZE_TS still_count = 0;

  vm->mem.major_epoch_++;
  if (vm->mem.major_epoch_ == 0)
    vm->mem.major_epoch_ = 1;
  epoch = vm->mem.major_epoch_;

  ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, 0);
  vm->mem.major_weak_tables_count_ = 0;
  vm->mem.major_still_bases_count_ = 0;
  vm->mem.major_still_lo_ = 0;
  vm->mem.major_still_span_ = 0;
  ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, 0);

  /* Ensure generous initial mark stack so mutator write barriers rarely overflow. */
  if (vm->mem.major_mark_stack_cap_ < 8192)
    {
      ___SCMOBJ *nbuf = ___CAST(___SCMOBJ*, ___ALLOC_MEM(8192 * sizeof(___SCMOBJ)));
      if (nbuf != 0)
        {
          if (vm->mem.major_mark_stack_ != 0)
            ___FREE_MEM(vm->mem.major_mark_stack_);
          vm->mem.major_mark_stack_ = nbuf;
          vm->mem.major_mark_stack_cap_ = 8192;
        }
    }

  /* Snapshot all existing mature sections and clear their mark bitmaps.
   * Clear Immix hole markers until this cycle's Remark sweeps fresh dead runs. */
  if (ms != 0)
    {
      for (sec = ms->head; sec != 0; sec = sec->next)
        {
          if (sec->region_age != ___GC_REGION_MATURE)
            break;
          sec->major_mark_epoch = epoch;
          sec->major_snapshot_words = sec->mature_words;
          sec->major_live_words = 0;
          sec->major_evacuate = 0;
          sec->major_hole_start = 0;
          sec->major_hole_end = 0;
          memset(sec->major_line_live, 0, sizeof(sec->major_line_live));
          memset(___CAST(void*, section_major_mark_bits(sec)), 0, SECTION_MAJOR_MARK_BYTES);
          if (sec == vm->mem.mature_tail_)
            break;
        }
    }

  /* Snapshot all existing mature still object bases (read-only during MARKING)
   * and shade C-pinned (refcount > 0) mature still roots. */
  for (p = 0; p < np; p++)
    {
      ___WORD *base = ___CAST(___WORD*, ___PSTATE_FROM_PROCESSOR_ID(p, vm)->mem.still_objs_);
      while (base != 0)
        {
          still_count++;
          base = ___CAST(___WORD*, base[___STILL_LINK]);
        }
    }
  if (still_count > 0)
    {
      if (still_count > vm->mem.major_still_bases_cap_)
        {
          ___SIZE_TS ncap = vm->mem.major_still_bases_cap_ ? vm->mem.major_still_bases_cap_ : 256;
          ___WORD **nbuf;
          while (ncap < still_count)
            ncap *= 2;
          nbuf = ___CAST(___WORD**, ___ALLOC_MEM(ncap * sizeof(___WORD*)));
          if (nbuf != 0)
            {
              if (vm->mem.major_still_bases_ != 0)
                ___FREE_MEM(vm->mem.major_still_bases_);
              vm->mem.major_still_bases_ = nbuf;
              vm->mem.major_still_bases_cap_ = ncap;
            }
        }
      if (vm->mem.major_still_bases_ != 0 &&
          still_count <= vm->mem.major_still_bases_cap_)
        {
          ___SIZE_TS idx = 0;
          for (p = 0; p < np; p++)
            {
              ___WORD *base = ___CAST(___WORD*, ___PSTATE_FROM_PROCESSOR_ID(p, vm)->mem.still_objs_);
              while (base != 0)
                {
                  vm->mem.major_still_bases_[idx++] = base;
#ifndef ___USE_HANDLES
                  if ((base[___STILL_DIRTY] & (___STILL_FLAG_MAJOR_MARK0 | ___STILL_FLAG_MAJOR_MARK1)) != 0)
                    ___WORD_FETCH_AND_RELEASE(
                      &base[___STILL_DIRTY],
                      ~___CAST(___WORD, ___STILL_FLAG_MAJOR_MARK0 | ___STILL_FLAG_MAJOR_MARK1));
#endif
                  base = ___CAST(___WORD*, base[___STILL_LINK]);
                }
            }
          major_sort_still_bases(vm->mem.major_still_bases_, idx);
          vm->mem.major_still_bases_count_ = idx;
          vm->mem.major_still_lo_ = ___CAST(___UWORD, vm->mem.major_still_bases_[0]);
          vm->mem.major_still_span_ =
            (___CAST(___UWORD, vm->mem.major_still_bases_[idx - 1]) - vm->mem.major_still_lo_) + 1;

          for (idx = 0; idx < vm->mem.major_still_bases_count_; idx++)
            {
              ___WORD *base = vm->mem.major_still_bases_[idx];
              if (base[___STILL_REFCOUNT] != 0)
                major_shade_mature_still_q(vm, 0, base, base[___STILL_HEADER], 1);
            }
        }
      else
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
        }
    }

  /* Shade existing mature wills: executable wills keep testator+action live;
   * nonexecutable wills keep will+action live without resurrecting testator. */
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD curr = ps->mem.executable_wills_;
      while (___UNTAG(curr) != 0)
        {
          ___SCMOBJ will = ___SUBTYPED_FROM_START(___UNTAG(curr));
          ___WORD *wbody = ___BODY0_AS(will, ___tSUBTYPED);
          major_shade_obj_ex(vm, will, 1);
          major_shade_obj_ex(vm, wbody[___WILL_TESTATOR], 1);
          major_shade_obj_ex(vm, wbody[___WILL_ACTION], 1);
          curr = wbody[___WILL_NEXT];
        }
      curr = ps->mem.nonexecutable_wills_;
      while (___UNTAG(curr) != 0)
        {
          ___SCMOBJ will = ___SUBTYPED_FROM_START(___UNTAG(curr));
          ___WORD *wbody = ___BODY0_AS(will, ___tSUBTYPED);
          major_shade_obj_ex(vm, will, 1);
          major_shade_obj_ex(vm, wbody[___WILL_ACTION], 1);
          curr = wbody[___WILL_NEXT];
        }
    }

  /* Publish MARKING phase and arm SATB barrier across ALL processors (active
   * and parked FFI processors alike; ___leave_blocking_ffi also adopts it). */
  vm->mem.minor_gcs_since_major_ = 0;
  ___WORD_STORE_RELEASE(&vm->mem.major_phase_, ___GC_MAJOR_MARKING);
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
      ___WORD_STORE_RELEASE(&ps->mem.satb_active_, 1);
    }
}

/* Drain all processors' SATB & local mark buffers into the Major mark stack during STW. */
___HIDDEN void major_minor_gc_drain_satb(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      unsigned int i;
      if (ps->mem.major_mark_local_count_ > 0)
        {
          major_mark_stack_push_batch_ex(
            vm, ps->mem.major_mark_local_buf_, ps->mem.major_mark_local_count_, 1);
          ps->mem.major_mark_local_count_ = 0;
        }
      if (ps->mem.satb_overflow_ != 0)
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
          ps->mem.satb_overflow_ = 0;
        }
      for (i = 0; i < ps->mem.satb_count_; i++)
        major_shade_obj_ex(vm, ps->mem.satb_buf_[i], 1);
      vm->mem.concurrent_major_satb_logged_ += ___CAST(___F64, ps->mem.satb_count_);
      ps->mem.satb_count_ = 0;
    }
}

/* Single-threaded STW mark-stack drain (used after overflow recovery & wills). */
___HIDDEN void major_drain_mark_stack_stw(___virtual_machine_state vm)
{
  ___SCMOBJ lbuf[___GC_MAJOR_LOCAL_MARK_CAP];
  unsigned int lcnt = 0;
  major_local_queue lq;
  ___SIZE_TS scanned = 0;

  lq.buf = lbuf;
  lq.count = &lcnt;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;

  for (;;)
    {
      while (lcnt > 0)
        {
          ___SCMOBJ obj = lbuf[--lcnt];
          ___SIZE_TS w = major_scan_object_q(vm, &lq, obj, 1);
          if (w > 0)
            scanned += w;
        }
      {
        ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
        if (avail <= 0)
          break;
        {
          unsigned int take = (avail > 64) ? 64u : ___CAST(unsigned int, avail);
          avail -= ___CAST(___WORD, take);
          memcpy(lbuf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
          ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
          lcnt = take;
        }
      }
    }
  vm->mem.concurrent_major_marked_words_ += ___CAST(___F64, scanned);
}

/* Check whether a heap object is a dead WHITE mature object at STW Remark.
 * Young / newly promoted BLACK / permanent objects return 0 (live). */
___HIDDEN int major_is_dead_white_mature(___virtual_machine_state vm, ___SCMOBJ obj)
{
  ___WORD *body;
  ___WORD *hdr;
  ___msection *sec;

  if (!___MEM_ALLOCATED(obj))
    return 0;

  body = ___BODY0(obj);
  hdr = body - 1;
  sec = major_find_mature_section_ro(vm, ___CAST(___UWORD, hdr));
  if (sec != 0)
    {
      ___SIZE_TS off;
      if (sec->major_mark_epoch != vm->mem.major_epoch_)
        return 0;
      off = ___CAST(___SIZE_TS, hdr - (sec->base + sec->active_offset));
      if (off < 0 || off >= sec->major_snapshot_words)
        return 0;
      return !major_is_marked_word(sec, off);
    }

  if (vm->mem.major_still_bases_count_ > 0)
    {
      ___WORD *base = major_find_mature_still_base_ro(vm, body - ___STILL_BODY);
      if (base != 0)
        {
#ifndef ___USE_HANDLES
          ___WORD mbit = ___STILL_MAJOR_MARK_BIT(vm->mem.major_epoch_);
          if (base[___STILL_REFCOUNT] == 0 &&
              (base[___STILL_DIRTY] & (___STILL_FLAG_YOUNG | mbit)) == 0)
            return 1;
#endif
          return 0;
        }
    }

  return 0;
}

/* Complete SATB overflow recovery at STW Remark: re-scan every already-marked
 * mature object, every newly promoted BLACK suffix [snapshot..mature_words),
 * every newly promoted BLACK mature section, and every live mature still
 * object so zero edges dropped on SATB buffer overflow can be missed. */
___HIDDEN void major_overflow_recovery_scan_stw(___virtual_machine_state vm)
{
  ___msections *ms = vm->mem.the_msections_;
  ___msection *sec;
  int np = vm->processor_count;
  int p;
#ifndef ___USE_HANDLES
  ___WORD mbit = ___STILL_MAJOR_MARK_BIT(vm->mem.major_epoch_);
#endif

  if (ms != 0)
    {
      for (sec = ms->head; sec != 0; sec = sec->next)
        {
          ___WORD *base;
          ___WORD *end;
          ___WORD *ptr;
          if (sec->region_age != ___GC_REGION_MATURE)
            break;
          base = sec->base + sec->active_offset;
          end = base + sec->mature_words;
          ptr = base;
          while (ptr < end)
            {
              ___WORD head = *ptr;
              if (___TESTTYPE(head, ___FORW))
                {
                  ptr += 1;
                  continue;
                }
              {
                ___SIZE_TS words = ___HD_WORDS(head);
                ___SIZE_TS off = ___CAST(___SIZE_TS, ptr - base);
                int is_live = (sec->major_mark_epoch != vm->mem.major_epoch_) ||
                              (off >= sec->major_snapshot_words) ||
                              major_is_marked_word(sec, off);
                if (is_live && still_subtype_has_pointers(___HD_SUBTYPE(head)))
                  major_scan_object_q(
                    vm, 0, major_make_scmobj_from_body(ptr + 1, ___HD_SUBTYPE(head)), 1);
                ptr += words + 1;
              }
            }
          if (sec == vm->mem.mature_tail_)
            break;
        }
    }

  for (p = 0; p < np; p++)
    {
      ___WORD *base = ___CAST(___WORD*, ___PSTATE_FROM_PROCESSOR_ID(p, vm)->mem.still_objs_);
      while (base != 0)
        {
          ___WORD head = base[___STILL_HEADER];
#ifndef ___USE_HANDLES
          int is_live = (base[___STILL_REFCOUNT] != 0) ||
                        ((base[___STILL_DIRTY] & mbit) != 0);
#else
          int is_live = 1;
#endif
          if (is_live && still_subtype_has_pointers(___HD_SUBTYPE(head)))
            major_scan_object_q(
              vm, 0,
              major_make_scmobj_from_body(base + ___STILL_BODY, ___HD_SUBTYPE(head)),
              1);
          base = ___CAST(___WORD*, base[___STILL_LINK]);
        }
    }

  major_drain_mark_stack_stw(vm);
}

/* ==========================================================================
 * 4-Barrier Parallel STW Remark & Parallel Non-Moving Immix Sweep (Slice 2 v2)
 * ========================================================================== */

/* Coordinator setup before Phase R-A BARRIER. */
___HIDDEN void major_remark_phase_a_prepare(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  ___F64 u0, s0, r0;
  int i;

  ___process_times(&u0, &s0, &r0);
  g->major_remark_r0 = r0;
  ___WORD_STORE_RELEASE(&vm->mem.major_remark_working_, ___CAST(___WORD, g->worker_count));
  for (i = 0; i < g->worker_count; i++)
    {
      g->major_reclaimed_still[i] = 0;
      g->major_live_still[i] = 0;
    }
}

/* Phase R-A (Parallel across all w_cnt workers):
 *   1. Flush per-processor SATB + local mark buffers for p % w_cnt == w_id.
 *   2. Parallel work-stealing drain of global mark stack using stack-local
 *      lbuf[128] and exact atomic active-worker quiescence counter
 *      (major_remark_working_ == 0 && major_mark_stack_count_ == 0). */
___HIDDEN void major_remark_phase_a_parallel
   (___virtual_machine_state vm,
    int w_id,
    int w_cnt)
{
  int np = vm->processor_count;
  int p;
  ___SCMOBJ lbuf[___GC_MAJOR_LOCAL_MARK_CAP];
  unsigned int lcnt = 0;
  major_local_queue lq;
  ___SIZE_TS scanned = 0;
  ___SIZE_TS satb_n = 0;

  lq.buf = lbuf;
  lq.count = &lcnt;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;

  for (p = w_id; p < np; p += w_cnt)
    {
      ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      unsigned int i;
      if (pps->mem.major_mark_local_count_ > 0)
        {
          major_mark_stack_push_batch_ex(
            vm, pps->mem.major_mark_local_buf_, pps->mem.major_mark_local_count_, 1);
          pps->mem.major_mark_local_count_ = 0;
        }
      if (pps->mem.satb_overflow_ != 0)
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
          pps->mem.satb_overflow_ = 0;
        }
      for (i = 0; i < pps->mem.satb_count_; i++)
        major_shade_obj_q(vm, &lq, pps->mem.satb_buf_[i], 1);
      satb_n += pps->mem.satb_count_;
      pps->mem.satb_count_ = 0;
    }

  for (;;)
    {
      while (lcnt > 0)
        {
          ___SCMOBJ obj = lbuf[--lcnt];
          ___SIZE_TS w = major_scan_object_q(vm, &lq, obj, 1);
          if (w > 0)
            scanned += w;
        }

      major_mark_lock(vm);
      {
        ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
        if (avail > 0)
          {
            unsigned int take = (avail > 32) ? 32u : ___CAST(unsigned int, avail);
            avail -= ___CAST(___WORD, take);
            memcpy(lbuf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
            ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
            lcnt = take;
            major_mark_unlock(vm);
            continue;
          }
        ___WORD_FETCH_ADD_RELEASE(&vm->mem.major_remark_working_, -1);
      }
      major_mark_unlock(vm);

      if (w_cnt <= 1)
        break;

      while (___WORD_LOAD_ACQUIRE(&vm->mem.major_remark_working_) > 0)
        {
          if (___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) > 0)
            {
              major_mark_lock(vm);
              {
                ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
                if (avail > 0)
                  {
                    unsigned int take = (avail > 32) ? 32u : ___CAST(unsigned int, avail);
                    avail -= ___CAST(___WORD, take);
                    memcpy(lbuf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
                    ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
                    ___WORD_FETCH_ADD_RELEASE(&vm->mem.major_remark_working_, 1);
                    lcnt = take;
                    major_mark_unlock(vm);
                    break;
                  }
              }
              major_mark_unlock(vm);
            }
          ___CPU_RELAX();
        }
      if (lcnt == 0)
        break;
    }

  if (scanned > 0 || satb_n > 0)
    {
      major_mark_lock(vm);
      vm->mem.concurrent_major_marked_words_ += ___CAST(___F64, scanned);
      vm->mem.concurrent_major_satb_logged_ += ___CAST(___F64, satb_n);
      major_mark_unlock(vm);
    }
}

/* Phase R-B (Coordinator after Phase R-A BARRIER):
 *   1. Overflow recovery if satb_overflow_ != 0.
 *   2. Resolve mature wills and drain any shaded testator subgraph.
 *   3. Atomically clear dead WHITE weak-table entries BEFORE SWEEPING.
 *   4. Transition phase -> SWEEPING, disarm SATB, freeze mature_sections count. */
___HIDDEN void major_remark_phase_b_coord(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  int np = vm->processor_count;
  int p;

  if (___WORD_LOAD_ACQUIRE(&vm->mem.satb_overflow_) != 0)
    major_overflow_recovery_scan_stw(vm);

  /* Resolve mature wills. */
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD *tail_exec = &ps->mem.executable_wills_;
      ___WORD *tail_nonexec = &ps->mem.nonexecutable_wills_;
      ___WORD curr;

      while (___UNTAG(*tail_exec) != 0)
        {
          ___SCMOBJ ew = ___SUBTYPED_FROM_START(___UNTAG(*tail_exec));
          tail_exec = &___BODY0_AS(ew, ___tSUBTYPED)[___WILL_NEXT];
        }

      curr = *tail_nonexec;
      while (___UNTAG(curr) != 0)
        {
          ___SCMOBJ will = ___SUBTYPED_FROM_START(___UNTAG(curr));
          ___WORD *wbody = ___BODY0_AS(will, ___tSUBTYPED);
          ___WORD next = wbody[___WILL_NEXT];
          ___SCMOBJ testator = wbody[___WILL_TESTATOR];

          if ((next & ___EXECUTABLE_WILL) || major_is_dead_white_mature(vm, testator))
            {
              *tail_exec = ___TAG(___SUBTYPED_TO_START(will), ___EXECUTABLE_WILL);
              tail_exec = &wbody[___WILL_NEXT];
              *tail_exec = ___TAG(0, ___EXECUTABLE_WILL);
              major_shade_obj_ex(vm, testator, 1);
            }
          else
            {
              *tail_nonexec = ___TAG(___SUBTYPED_TO_START(will), 0);
              tail_nonexec = &wbody[___WILL_NEXT];
            }
          curr = next;
        }
      *tail_nonexec = ___TAG(0, 0);
    }
  major_drain_mark_stack_stw(vm);

  /* Atomically clear dead WHITE mature entries in all live weak GC hash
   * tables BEFORE transitioning to SWEEPING (Quint V2 Mutant 9 invariant). */
  {
    ___SIZE_TS ti;
    for (ti = 0; ti < vm->mem.major_weak_tables_count_; ti++)
      {
        ___SCMOBJ ht = vm->mem.major_weak_tables_[ti];
        ___WORD *body;
        ___SIZE_TS words;
        int flags;
        ___SIZE_TS i;

        if (!___MEM_ALLOCATED(ht) || major_is_dead_white_mature(vm, ht))
          continue;

        body = ___BODY0(ht);
        words = ___HD_WORDS(body[-1]);
        flags = ___INT(body[___GCHASHTABLE_FLAGS]);

        if (((flags & (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS)) ==
             (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS)) ||
            (flags & ___GCHASHTABLE_FLAG_WEAK_VALS))
          {
            int weak_keys = ((flags & (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS)) ==
                             (___GCHASHTABLE_FLAG_WEAK_KEYS | ___GCHASHTABLE_FLAG_MEM_ALLOC_KEYS));
            int weak_vals = ((flags & ___GCHASHTABLE_FLAG_WEAK_VALS) != 0);

            for (i = words - 2; i >= ___GCHASHTABLE_KEY0; i -= 2)
              {
                ___SCMOBJ key = body[i];
                ___SCMOBJ val = body[i + 1];
                int dead = 0;
                if (key == ___UNUSED || key == ___DELETED)
                  continue;
                if (weak_keys && major_is_dead_white_mature(vm, key))
                  dead = 1;
                if (!dead && weak_vals && major_is_dead_white_mature(vm, val))
                  dead = 1;
                if (dead)
                  {
                    body[i] = ___DELETED;
                    body[i + 1] = ___UNUSED;
                    body[___GCHASHTABLE_COUNT] =
                      ___FIXSUB(body[___GCHASHTABLE_COUNT], ___FIX(1));
                    flags |= ___GCHASHTABLE_FLAG_ENTRY_DELETED;
                  }
              }
            body[___GCHASHTABLE_FLAGS] = ___FIX(flags);
          }
      }
  }

  ___WORD_STORE_RELEASE(&vm->mem.major_phase_, ___GC_MAJOR_SWEEPING);
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD_STORE_RELEASE(&ps->mem.satb_active_, 0);
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
    }

  g->major_sweep_nm = vm->mem.nb_msections_mature_;
}

/* Close one contiguous dead WHITE run [run_lo, run_hi) strictly inside full
 * cards [0 .. full_card_words) by emitting card-aligned leaf ___sU8VECTOR
 * fillers, recording exact card starts, and tracking the largest Immix hole. */
static inline void major_close_dead_run
   (___msection *sec,
    ___WORD *base,
    ___SIZE_TS run_lo,
    ___SIZE_TS run_hi,
    ___SIZE_TS *best_lo,
    ___SIZE_TS *best_hi)
{
  ___SIZE_TS h_lo, h_hi;
  if (run_hi <= run_lo)
    return;
  h_lo = (run_lo + ___GC_CARD_WORDS - 1) & ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
  h_hi = run_hi & ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
  if (h_hi > h_lo)
    {
      if (h_lo > run_lo)
        {
          base[run_lo] = ___MAKE_HD_WORDS(h_lo - run_lo - 1, ___sU8VECTOR);
          record_mature_obj_start(sec, base + run_lo);
        }
      base[h_lo] = ___MAKE_HD_WORDS(h_hi - h_lo - 1, ___sU8VECTOR);
      record_mature_obj_start(sec, base + h_lo);
      if (run_hi > h_hi)
        {
          base[h_hi] = ___MAKE_HD_WORDS(run_hi - h_hi - 1, ___sU8VECTOR);
          record_mature_obj_start(sec, base + h_hi);
        }
      if ((h_hi - h_lo) > (*best_hi - *best_lo))
        {
          *best_lo = h_lo;
          *best_hi = h_hi;
        }
    }
  else
    {
      base[run_lo] = ___MAKE_HD_WORDS(run_hi - run_lo - 1, ___sU8VECTOR);
      record_mature_obj_start(sec, base + run_lo);
    }
}

/* Phase R-C (Parallel across all w_cnt workers):
 *   1. Parallel dead mature ___STILL sweep (p % w_cnt == w_id).
 *   2. Parallel non-moving Immix section sweep (i % w_cnt == w_id) with
 *      coalesced dead-run fillers, exact card-start rebuild, largest Immix
 *      hole discovery, and 100%-dead tagging (major_evacuate = 2). */
___HIDDEN void major_remark_phase_c_parallel
   (___virtual_machine_state vm,
    int w_id,
    int w_cnt)
{
  ___gc_round *g = &___COLLECTION(vm);
  int np = vm->processor_count;
  int nm = g->major_sweep_nm;
  ___UWORD epoch = vm->mem.major_epoch_;
  ___SIZE_TS my_reclaimed_still = 0;
  ___SIZE_TS my_live_still = 0;
  int p, si;
#ifndef ___USE_HANDLES
  ___WORD mbit = ___STILL_MAJOR_MARK_BIT(epoch);
#endif

  /* 1. Parallel mature ___STILL sweep on disjoint processor lists. */
  for (p = w_id; p < np; p += w_cnt)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD *last = &ps->mem.still_objs_;
      ___WORD *base = ___CAST(___WORD*, *last);
      ___SIZE_TS live_words = 0;

      while (base != 0)
        {
          ___WORD link = base[___STILL_LINK];
#ifndef ___USE_HANDLES
          int dead = (base[___STILL_REFCOUNT] == 0) &&
                     ((base[___STILL_DIRTY] & (___STILL_FLAG_YOUNG | mbit)) == 0);
#else
          int dead = 0;
#endif
          if (dead)
            {
              ___WORD head = base[___STILL_HEADER];
              my_reclaimed_still += base[___STILL_LENGTH];
              if (___HD_SUBTYPE(head) == ___sFOREIGN)
                ___lifecycle_defer(ps, base);
              else
                free_mem_aligned_heap(base);
            }
          else
            {
#ifndef ___USE_HANDLES
              if ((base[___STILL_DIRTY] & (___STILL_FLAG_MAJOR_MARK0 | ___STILL_FLAG_MAJOR_MARK1)) != 0)
                ___WORD_FETCH_AND_RELEASE(
                  &base[___STILL_DIRTY],
                  ~___CAST(___WORD, ___STILL_FLAG_MAJOR_MARK0 | ___STILL_FLAG_MAJOR_MARK1));
#endif
              live_words += base[___STILL_LENGTH];
              *last = ___CAST(___WORD, base);
              last = base + ___STILL_LINK;
            }
          base = ___CAST(___WORD*, link);
        }
      *last = 0;
      ps->mem.words_still_objs_mature_ = live_words;
      ps->mem.words_still_objs_ = live_words + ___lifecycle_deferred_words(ps);
      my_live_still += live_words;
    }

  g->major_reclaimed_still[w_id] = my_reclaimed_still;
  g->major_live_still[w_id] = my_live_still;

  /* 2. Parallel non-moving Immix sweep across disjoint mature sections. */
  for (si = w_id; si < nm; si += w_cnt)
    {
      ___msection *sec = vm->mem.mature_sections_[si];
      if (sec == 0 || sec->region_age != ___GC_REGION_MATURE)
        continue;

      if (sec->major_mark_epoch == epoch &&
          sec->major_live_words == 0 &&
          sec->mature_words == sec->major_snapshot_words)
        {
          /* Tag 100%-dead section for O(1) coordinator unlink in Phase R-D. */
          sec->major_evacuate = 2;
          sec->major_hole_start = 0;
          sec->major_hole_end = 0;
          continue;
        }

      {
        ___SIZE_TS best_lo = 0, best_hi = 0;
        ___SIZE_TS effective_live;

        if (sec->major_mark_epoch == epoch && sec->major_snapshot_words > 0)
          {
            ___WORD *base = sec->base + sec->active_offset;
            ___SIZE_TS snap_words = sec->major_snapshot_words;
            ___WORD *snap_end = base + snap_words;
            ___SIZE_TS full_card_words = snap_words & ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
            unsigned int half_card_lo =
              ___CAST(unsigned int, sec->active_offset >> ___GC_CARD_SHIFT_WORDS);
            unsigned int full_card_cnt =
              ___CAST(unsigned int, full_card_words >> ___GC_CARD_SHIFT_WORDS);
            unsigned char *starts = section_card_starts(sec);
            ___WORD *ptr = base;
            int in_dead = 0;
            ___SIZE_TS run_lo = 0, run_hi = 0;

            if (full_card_cnt > 0)
              memset(starts + half_card_lo, ___GC_CARD_NO_OBJ_START, full_card_cnt);

            while (ptr < snap_end)
              {
                ___SIZE_TS off = ___CAST(___SIZE_TS, ptr - base);
                ___WORD head = *ptr;
                if (___TESTTYPE(head, ___FORW))
                  {
                    if (off < full_card_words)
                      {
                        if (!in_dead)
                          {
                            in_dead = 1;
                            run_lo = off;
                          }
                        run_hi = off + 1;
                      }
                    ptr += 1;
                    continue;
                  }
                {
                  ___SIZE_TS words = ___HD_WORDS(head);
                  ___SIZE_TS next_off = off + words + 1;
                  if (off < full_card_words)
                    {
                      if (!major_is_marked_word(sec, off))
                        {
                          if (next_off <= full_card_words)
                            {
                              if (!in_dead)
                                {
                                  in_dead = 1;
                                  run_lo = off;
                                }
                              run_hi = next_off;
                            }
                          else
                            {
                              /* Dead object crosses full_card_words into boundary card:
                               * flush prior run and overwrite this header in place. */
                              if (in_dead)
                                {
                                  major_close_dead_run(sec, base, run_lo, run_hi, &best_lo, &best_hi);
                                  in_dead = 0;
                                }
                              *ptr = ___MAKE_HD_WORDS(words, ___sU8VECTOR);
                              record_mature_obj_start(sec, ptr);
                            }
                        }
                      else
                        {
                          if (in_dead)
                            {
                              major_close_dead_run(sec, base, run_lo, run_hi, &best_lo, &best_hi);
                              in_dead = 0;
                            }
                          record_mature_obj_start(sec, ptr);
                        }
                    }
                  else
                    {
                      /* Inside boundary card [full_card_words .. snap_words):
                       * close any open run and overwrite dead objects in place
                       * without altering starts[boundary_card]. */
                      if (in_dead)
                        {
                          major_close_dead_run(sec, base, run_lo, run_hi, &best_lo, &best_hi);
                          in_dead = 0;
                        }
                      if (!major_is_marked_word(sec, off))
                        *ptr = ___MAKE_HD_WORDS(words, ___sU8VECTOR);
                    }
                  ptr += words + 1;
                }
              }
            if (in_dead)
              major_close_dead_run(sec, base, run_lo, run_hi, &best_lo, &best_hi);
          }

        if (best_hi > best_lo && (best_hi - best_lo) >= ___GC_IMMIX_MIN_HOLE_WORDS)
          {
            sec->major_hole_start = best_lo;
            sec->major_hole_end = best_hi;
          }
        else
          {
            sec->major_hole_start = 0;
            sec->major_hole_end = 0;
          }

        if (sec->major_mark_epoch == epoch)
          {
            ___SIZE_TS post_snap = (sec->mature_words > sec->major_snapshot_words)
                                     ? (sec->mature_words - sec->major_snapshot_words)
                                     : 0;
            effective_live = ___CAST(___SIZE_TS, sec->major_live_words) + post_snap;
          }
        else
          effective_live = sec->mature_words;

        if (sec->mature_words >= (___MSECTION_SIZE >> 3) &&
            effective_live * 2 < sec->mature_words)
          sec->major_evacuate = 1;
        else
          sec->major_evacuate = 0;
      }
    }
}

/* Phase R-D (Coordinator after Phase R-C BARRIER):
 *   1. Aggregate parallel mature still stats.
 *   2. O(M) unlink of 100%-dead mature sections (major_evacuate == 2) to FREE
 *      YOUNG tail, rebuild promo_cands_[] (tail room + Immix holes), and
 *      update mature snapshot.
 *   3. Transition major_phase_ -> IDLE and advance adaptive 1.5x triggers. */
___HIDDEN void major_remark_phase_d_coord(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  ___msections *ms = vm->mem.the_msections_;
  ___SIZE_TS reclaimed_sections = 0;
  ___SIZE_TS reclaimed_still_words = 0;
  ___SIZE_TS total_mature_still = 0;
  int evac_count = 0;
  int wi;
  ___F64 u1, s1, r1;

  for (wi = 0; wi < g->worker_count; wi++)
    {
      reclaimed_still_words += g->major_reclaimed_still[wi];
      total_mature_still += g->major_live_still[wi];
    }
  vm->mem.mature_still_words_ = total_mature_still;

  if (ms != 0 && vm->mem.mature_tail_ != 0)
    {
      ___msection *sec = ms->head;
      ___msection *stop_after = vm->mem.mature_tail_;
      ___msection *new_mat_tail = 0;
      ___SIZE_TS new_mature_words = 0;
      int new_mature_count = 0;

      vm->mem.promo_cand_count_ = 0;

      while (sec != 0)
        {
          ___msection *nxt = sec->next;
          int is_last = (sec == stop_after);

          if (sec->region_age != ___GC_REGION_MATURE)
            break;

          if (sec->major_evacuate == 2)
            {
              /* 100%-dead mature section: O(1) reclamation to FREE YOUNG tail. */
              if (sec->prev != 0)
                sec->prev->next = sec->next;
              else
                ms->head = sec->next;
              if (sec->next != 0)
                sec->next->prev = sec->prev;
              else
                ms->tail = sec->prev;
              if (vm->mem.alloc_msection_ == sec)
                vm->mem.alloc_msection_ = new_mat_tail;

              sec->region_age = ___GC_REGION_YOUNG;
              sec->active_offset = 0;
              sec->mature_words = 0;
              sec->scan_end_words = 0;
              sec->gc_src_offset = 0;
              sec->gc_dest_offset = 0;
              sec->gc_dest_words = 0;
              sec->gc_is_dest = 0;
              sec->gc_role = 0;
              sec->card_dirty_any = 0;
              sec->major_mark_epoch = 0;
              sec->major_snapshot_words = 0;
              sec->major_live_words = 0;
              sec->major_evacuate = 0;
              sec->major_hole_start = 0;
              sec->major_hole_end = 0;
              memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
              memset(___CAST(void*, section_card_starts(sec)), ___GC_CARD_NO_OBJ_START, SECTION_CARD_COUNT);
              *section_claim_at(sec, 0) = (section_claim){0};
              *section_claim_at(sec, ___MSECTION_SIZE >> 1) = (section_claim){0};
              sec->region_generation++;

              sec->next = 0;
              sec->prev = ms->tail;
              if (ms->tail != 0)
                ms->tail->next = sec;
              else
                ms->head = sec;
              ms->tail = sec;

              reclaimed_sections++;
            }
          else
            {
              if (sec->major_evacuate == 1)
                evac_count++;
              new_mature_count++;
              new_mature_words += sec->mature_words;
              new_mat_tail = sec;
              promo_cand_add(vm, sec);
            }

          if (is_last)
            break;
          sec = nxt;
        }

      vm->mem.nb_msections_mature_ = new_mature_count;
      vm->mem.mature_tail_ = new_mat_tail;
      vm->mem.occupied_words_mature_ = new_mature_words;
      if (reclaimed_sections > 0)
        {
          int idx = 0;
          ___msection *s;
          if (vm->mem.nb_msections_assigned_ >= ___CAST(int, reclaimed_sections))
            vm->mem.nb_msections_assigned_ -= ___CAST(int, reclaimed_sections);
          for (s = ms->head; s != 0; s = s->next)
            s->index = idx++;
          rebuild_mature_snapshot(vm);
        }
    }

  vm->mem.major_evacuate_count_ = evac_count;
  vm->mem.major_last_reclaimed_sections_ = reclaimed_sections;
  ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, 0);
  vm->mem.major_weak_tables_count_ = 0;
  vm->mem.major_still_bases_count_ = 0;
  vm->mem.major_still_lo_ = 0;
  vm->mem.major_still_span_ = 0;
  ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_phase_, ___GC_MAJOR_IDLE);

  /* Balanced Go-style 2.0x movable section trigger prevents premature rsec=0
   * cycles while 1.5x still trigger keeps large mature still RSS bounded. */
  {
    int mcnt = vm->mem.nb_msections_mature_;
    int trig = mcnt * 2;
    ___SIZE_TS mstill = vm->mem.mature_still_words_;
    ___SIZE_TS still_trig = mstill + (mstill >> 1);
    if (trig < mcnt + 8)
      trig = mcnt + 8;
    if (still_trig < 2 * ___MSECTION_SIZE)
      still_trig = 2 * ___MSECTION_SIZE;
    vm->mem.major_trigger_sections_ = trig;
    vm->mem.major_trigger_still_words_ = still_trig;
    vm->mem.minor_gcs_since_major_ = 0;
  }

  ___process_times(&u1, &s1, &r1);
  vm->mem.nb_concurrent_major_cycles_ += 1.0;
  vm->mem.concurrent_major_reclaimed_sections_ += ___CAST(___F64, reclaimed_sections);
  vm->mem.concurrent_major_reclaimed_still_words_ += ___CAST(___F64, reclaimed_still_words);
  vm->mem.concurrent_major_remark_real_time_ += (r1 - g->major_remark_r0);
}

/* Abort an in-progress concurrent Major cycle cleanly when an explicit (##gc),
 * tight max_heap, or Immix defragmentation triggers a full STW compacting GC. */
___HIDDEN void major_abort_for_full_compacting_gc(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;

  ___WORD_STORE_RELEASE(&vm->mem.major_phase_, ___GC_MAJOR_IDLE);
  ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, 0);
  vm->mem.major_weak_tables_count_ = 0;
  vm->mem.major_still_bases_count_ = 0;
  vm->mem.major_still_lo_ = 0;
  vm->mem.major_still_span_ = 0;
  vm->mem.major_evacuate_count_ = 0;

  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD_STORE_RELEASE(&ps->mem.satb_active_, 0);
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
    }
}

/* Public runtime control & telemetry APIs for tests and diagnostics. */
___EXP_FUNC(void,___gc_concurrent_major_stats)
   ___P((___processor_state ___ps,
         double *out_stats),
        (___ps,
         out_stats)
___processor_state ___ps;
double *out_stats;)
{
  ___virtual_machine_state vm;
  if (___ps == 0 || out_stats == 0)
    return;
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  major_mark_lock(vm);
  out_stats[0] = vm->mem.nb_concurrent_major_cycles_;
  out_stats[1] = vm->mem.concurrent_major_mark_slices_;
  out_stats[2] = vm->mem.concurrent_major_marked_words_;
  out_stats[3] = vm->mem.concurrent_major_reclaimed_sections_;
  out_stats[4] = vm->mem.concurrent_major_reclaimed_still_words_;
  out_stats[5] = vm->mem.concurrent_major_remark_real_time_;
  out_stats[6] = vm->mem.concurrent_major_satb_logged_;
  out_stats[7] = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_));
  major_mark_unlock(vm);
}

___EXP_FUNC(int,___gc_set_concurrent_major_enabled)
   ___P((___processor_state ___ps,
         int enabled),
        (___ps,
         enabled)
___processor_state ___ps;
int enabled;)
{
  ___virtual_machine_state vm;
  int prev;
  if (___ps == 0)
    return 0;
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  prev = vm->mem.concurrent_major_enabled_;
  if (enabled >= 0)
    {
#ifdef ___USE_HANDLES
      vm->mem.concurrent_major_enabled_ = 0;
#else
      vm->mem.concurrent_major_enabled_ = enabled ? 1 : 0;
#endif
    }
  return prev;
}

___EXP_FUNC(int,___gc_start_concurrent_major)
   ___P((___processor_state ___ps,
         int finish_now),
        (___ps,
         finish_now)
___processor_state ___ps;
int finish_now;)
{
  ___virtual_machine_state vm;
  if (___ps == 0)
    return 0;
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (!vm->mem.concurrent_major_enabled_ || !vm->mem.gen_gc_enabled_)
    return 0;
  ___WORD_STORE_RELEASE(&vm->mem.major_request_start_, finish_now ? 2 : 1);
  return 1;
}

#endif
