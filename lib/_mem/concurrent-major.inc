/* Concurrent SATB Major GC and Non-Moving Immix Mark-Region Mature Space:
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

#define ___GC_IMMIX_MIN_HOLE_WORDS    256

#define ___GC_MAJOR_REMOTE_BATCH      32
#define ___GC_MAJOR_MAX_STATIC_WORKERS 64
#define ___GC_MAJOR_PREFETCH_CAP       64u
#define ___GC_MAJOR_PREFETCH_MASK      (___GC_MAJOR_PREFETCH_CAP - 1u)
#define ___GC_MAJOR_PREFETCH_MIN       24u
#define ___GC_MAJOR_MARK_STACK_MAX_CAP 4194304

typedef struct major_prefetch_entry_struct
  {
    ___msection *sec;
    ___WORD *hdr;
    ___SIZE_TS off;
  } major_prefetch_entry;

typedef struct major_prefetch_ring_struct
  {
    major_prefetch_entry entries[___GC_MAJOR_PREFETCH_CAP];
    unsigned int head;
    unsigned int tail;
  } major_prefetch_ring;

typedef struct major_remote_inbox_struct
  {
    ___VOLATILE ___WORD lock;
    ___SCMOBJ *buf;
    ___SIZE_TS count;
    ___SIZE_TS cap;
    char pad[64 - (sizeof(___WORD) + sizeof(___SCMOBJ*) + 2 * sizeof(___SIZE_TS))];
  } major_remote_inbox;

typedef struct major_local_queue_struct
  {
    ___SCMOBJ *buf;
    unsigned int *count;
    unsigned int cap;
    ___msection *last_sec;
    major_prefetch_ring *ring;
    int owner_w_id;
    int owner_w_cnt;
    major_remote_inbox *inboxes;
    ___SCMOBJ (*out_buf)[___GC_MAJOR_REMOTE_BATCH];
    unsigned int *out_cnt;
    ___VOLATILE ___WORD *remote_pending;
    ___VOLATILE ___WORD *inflight_counter;
    int track_nonstatic;
    int saw_nonstatic;
  } major_local_queue;

static inline ___WORD major_inflight_add
   (___VOLATILE ___WORD *p,
    ___WORD delta)
{
#if defined(__GNUC__) || defined(__clang__)
  return __atomic_fetch_add(p, delta, __ATOMIC_ACQ_REL);
#else
  return ___WORD_FETCH_ADD_RELEASE(p, delta);
#endif
}

static inline void major_inbox_lock(major_remote_inbox *ib)
{
  for (;;)
    {
      ___WORD expected = 0;
      if (___WORD_CAS_ACQUIRE(&ib->lock, expected, 1))
        break;
      ___CPU_RELAX();
    }
}

static inline void major_inbox_unlock(major_remote_inbox *ib)
{
  ___WORD_STORE_RELEASE(&ib->lock, 0);
}

___HIDDEN void major_remote_flush_one
   (___virtual_machine_state vm,
    major_local_queue *q,
    int dst)
{
  unsigned int n = q->out_cnt[dst];
  major_remote_inbox *ib;

  if (n == 0)
    return;
  ib = &q->inboxes[dst];
  major_inbox_lock(ib);
  if (ib->count + ___CAST(___SIZE_TS, n) > ib->cap)
    {
      ___SIZE_TS need = ib->count + ___CAST(___SIZE_TS, n);
      ___SIZE_TS ncap = ib->cap ? (ib->cap * 2) : 512;
      ___SCMOBJ *nbuf;
      while (ncap < need)
        ncap *= 2;
      nbuf = ___CAST(___SCMOBJ*, ___ALLOC_MEM(ncap * sizeof(___SCMOBJ)));
      if (nbuf == 0)
        {
          ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
          major_inbox_unlock(ib);
          q->out_cnt[dst] = 0;
          return;
        }
      if (ib->count > 0 && ib->buf != 0)
        memcpy(nbuf, ib->buf, ib->count * sizeof(___SCMOBJ));
      if (ib->buf != 0)
        ___FREE_MEM(ib->buf);
      ib->buf = nbuf;
      ib->cap = ncap;
    }
  memcpy(&ib->buf[ib->count], q->out_buf[dst], n * sizeof(___SCMOBJ));
  ib->count += ___CAST(___SIZE_TS, n);
  if (q->inflight_counter != 0)
    major_inflight_add(q->inflight_counter, ___CAST(___WORD, n));
  major_inbox_unlock(ib);
  q->out_cnt[dst] = 0;
}

static inline void major_remote_route
   (___virtual_machine_state vm,
    major_local_queue *q,
    int dst,
    ___SCMOBJ obj)
{
  unsigned int c = q->out_cnt[dst];
  q->out_buf[dst][c++] = obj;
  q->out_cnt[dst] = c;
  if (c >= ___GC_MAJOR_REMOTE_BATCH)
    major_remote_flush_one(vm, q, dst);
}

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
  return mature_radix_lookup_ro(vm, addr);
}

static inline ___msection *major_find_mature_section_cached
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___UWORD addr)
{
  ___msection *sec;
  if (q != 0 && q->last_sec != 0)
    {
      ___msection *ls = q->last_sec;
      ___UWORD half_bytes = ___CAST(___UWORD, ___MSECTION_SIZE >> 1) * ___WS;
      if (addr - ___CAST(___UWORD, ls->base + ls->active_offset) < half_bytes)
        return ls;
    }
  sec = major_find_mature_section_ro(vm, addr);
  if (q != 0 && sec != 0)
    q->last_sec = sec;
  return sec;
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
 * When inflight_counter != 0 (parallel STW Remark), atomically accounts for the
 * newly queued items in the single-word quiescence counter while holding
 * major_mark_lock so queued items are never invisible to quiescence checks. */
___HIDDEN void major_mark_stack_push_batch_inflight
   (___virtual_machine_state vm,
    const ___SCMOBJ *items,
    unsigned int n,
    int allow_alloc,
    ___VOLATILE ___WORD *inflight_counter)
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
        if (ncap > ___GC_MAJOR_MARK_STACK_MAX_CAP)
          {
            ___WORD_STORE_RELEASE(&vm->mem.satb_overflow_, 1);
            major_mark_unlock(vm);
            return;
          }
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
  if (inflight_counter != 0)
    major_inflight_add(inflight_counter, ___CAST(___WORD, n));
  major_mark_unlock(vm);
}

___HIDDEN void major_mark_stack_push_batch_ex
   (___virtual_machine_state vm,
    const ___SCMOBJ *items,
    unsigned int n,
    int allow_alloc)
{
  major_mark_stack_push_batch_inflight(vm, items, n, allow_alloc, 0);
}

___HIDDEN void major_mark_stack_push_ex
   (___virtual_machine_state vm,
    ___SCMOBJ obj,
    int allow_alloc)
{
  major_mark_stack_push_batch_inflight(vm, &obj, 1, allow_alloc, 0);
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
          major_mark_stack_push_batch_inflight(
            vm, &q->buf[half], cnt - half, allow_alloc, q->inflight_counter);
          cnt = half;
        }
      else if (allow_alloc && q->inboxes == 0 && cnt >= 32 &&
               ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_) == 0)
        {
          /* Fast work publication when global stack is empty so peer cores start stealing immediately. */
          unsigned int keep = 16;
          major_mark_stack_push_batch_inflight(
            vm, &q->buf[keep], cnt - keep, allow_alloc, q->inflight_counter);
          cnt = keep;
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

static inline void major_shade_mature_movable_core
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___msection *sec,
    ___WORD *header,
    ___WORD head,
    int allow_alloc,
    ___SCMOBJ *scan_now_out)
{
  ___WORD *half_base = sec->base + sec->active_offset;
  ___SIZE_TS off;
  ___VOLATILE ___WORD *mbits;
  ___SIZE_TS w;
  ___UWORD bit, prev;
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

  /* Chez Creator-Owned Segment Routing during parallel Remark (Phase R-A):
   *   - Owned section (sec->index % w_cnt == w_id): non-atomic mark, zero RMW!
   *   - Remote section: route object to owner's remote inbox (zero cross-core
   *     mark-bitmap cache-line bouncing). */
  if (q != 0 && q->owner_w_cnt > 1 && q->inboxes != 0)
    {
      int owner = ___CAST(int, ___CAST(unsigned int, sec->index) %
                               ___CAST(unsigned int, q->owner_w_cnt));
      if (owner != q->owner_w_id)
        {
          subtype = ___HD_SUBTYPE(head);
          major_remote_route(vm, q, owner, major_make_scmobj_from_body(header + 1, subtype));
          return;
        }
      mbits[w] = ___CAST(___WORD, ___CAST(___UWORD, mbits[w]) | bit);
      if (sec->major_live_words == 0)
        sec->major_live_words = 1;
    }
  else
    {
      prev = ___CAST(___UWORD, ___WORD_FETCH_OR_RELEASE(&mbits[w], ___CAST(___WORD, bit)));
      if ((prev & bit) != 0)
        return;
      /* Zero-contention monotonic 0->1 any_marked flag; exact live_words &
       * Immix free-line bitmaps are computed locally in parallel Phase R-C. */
      if (___WORD_LOAD_RELAXED(&sec->major_live_words) == 0)
        ___WORD_STORE_RELEASE(&sec->major_live_words, 1);
    }

  subtype = ___HD_SUBTYPE(head);

  /* Leaf objects are immediately BLACK without mark-stack traffic. */
  if (!still_subtype_has_pointers(subtype))
    return;

  {
    ___SCMOBJ obj = major_make_scmobj_from_body(header + 1, subtype);
    if (scan_now_out != 0)
      *scan_now_out = obj;
    else
      major_mark_push_q(vm, q, obj, allow_alloc);
  }
}

___HIDDEN void major_shade_mature_movable_q
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___msection *sec,
    ___WORD *header,
    ___WORD head,
    int allow_alloc)
{
  major_shade_mature_movable_core(vm, q, sec, header, head, allow_alloc, 0);
}

static inline void major_prefetch_ring_process_one
   (___virtual_machine_state vm,
    major_local_queue *q,
    major_prefetch_entry e,
    int allow_alloc,
    ___SCMOBJ *scan_now_out)
{
  ___msection *sec = e.sec;
  ___WORD *header = e.hdr;
  ___SIZE_TS off = e.off;
  ___VOLATILE ___WORD *mbits = section_major_mark_bits(sec);
  ___SIZE_TS w = off / ___WORD_WIDTH;
  ___UWORD bit = ___CAST(___UWORD, 1) << (off & (___WORD_WIDTH - 1));
  ___WORD head;
  int subtype;

  if ((___CAST(___UWORD, ___WORD_LOAD_RELAXED(&mbits[w])) & bit) != 0)
    return;

  head = ___WORD_LOAD_RELAXED(header);
  if (___HD_TYP(head) != ___MOVABLE0)
    return;

  if (q != 0 && q->owner_w_cnt > 1 && q->inboxes != 0)
    {
      int owner = ___CAST(int, ___CAST(unsigned int, sec->index) %
                               ___CAST(unsigned int, q->owner_w_cnt));
      if (owner != q->owner_w_id)
        {
          subtype = ___HD_SUBTYPE(head);
          major_remote_route(vm, q, owner, major_make_scmobj_from_body(header + 1, subtype));
          return;
        }
      mbits[w] = ___CAST(___WORD, ___CAST(___UWORD, mbits[w]) | bit);
      if (sec->major_live_words == 0)
        sec->major_live_words = 1;
    }
  else
    {
      ___UWORD prev = ___CAST(___UWORD, ___WORD_FETCH_OR_RELEASE(&mbits[w], ___CAST(___WORD, bit)));
      if ((prev & bit) != 0)
        return;
      if (___WORD_LOAD_RELAXED(&sec->major_live_words) == 0)
        ___WORD_STORE_RELEASE(&sec->major_live_words, 1);
    }

  subtype = ___HD_SUBTYPE(head);
  if (!still_subtype_has_pointers(subtype))
    return;

  {
    ___SCMOBJ obj = major_make_scmobj_from_body(header + 1, subtype);
    if (scan_now_out != 0)
      *scan_now_out = obj;
    else
      major_mark_push_q(vm, q, obj, allow_alloc);
  }
}

static inline void major_prefetch_ring_drain_to_queue
   (___virtual_machine_state vm,
    major_local_queue *q,
    int allow_alloc)
{
  major_prefetch_ring *ring = (q != 0) ? q->ring : 0;
  if (ring == 0)
    return;
  while (ring->head != ring->tail)
    {
      major_prefetch_entry e = ring->entries[ring->head & ___GC_MAJOR_PREFETCH_MASK];
      ring->head++;
      major_prefetch_ring_process_one(vm, q, e, allow_alloc, 0);
    }
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
  sec = major_find_mature_section_cached(vm, q, ___CAST(___UWORD, hdr));
  if (sec != 0)
    {
      ___SIZE_TS off;
      if (sec->major_static_gen != 0)
        return;
      if (q != 0 && q->track_nonstatic)
        q->saw_nonstatic = 1;
      off = ___CAST(___SIZE_TS, hdr - (sec->base + sec->active_offset));
      if (off >= 0 && off < sec->major_snapshot_words)
        {
          ___VOLATILE ___WORD *mbits;
          ___SIZE_TS w;
          ___UWORD bit;

          if (sec->major_mark_epoch != vm->mem.major_epoch_)
            return;

          /* Bitmap-first filter (L2-hot ~8 KiB/section): reject 67-90% of duplicate
           * pointers WITHOUT touching cold DRAM *hdr or polluting the prefetch ring! */
          mbits = section_major_mark_bits(sec);
          w = off / ___WORD_WIDTH;
          bit = ___CAST(___UWORD, 1) << (off & (___WORD_WIDTH - 1));
          if ((___CAST(___UWORD, ___WORD_LOAD_RELAXED(&mbits[w])) & bit) != 0)
            return;

          if (q != 0 && q->ring != 0 && allow_alloc != 0)
            {
              major_prefetch_ring *ring = q->ring;
              unsigned int rlen = ring->tail - ring->head;
              if (rlen >= ___GC_MAJOR_PREFETCH_CAP ||
                  (q->inboxes == 0 && rlen >= ___GC_MAJOR_PREFETCH_MIN &&
                   ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_) == 0))
                {
                  major_prefetch_entry old = ring->entries[ring->head & ___GC_MAJOR_PREFETCH_MASK];
                  ring->head++;
                  major_prefetch_ring_process_one(vm, q, old, allow_alloc, 0);
                }
#if defined(__GNUC__) || defined(__clang__)
              /* Read-only prefetch of cold DRAM object header + first 56B payload.
               * Never issue write-intent (RFO) prefetch on shared mark bitmaps. */
              __builtin_prefetch(hdr, 0, 1);
#endif
              {
                unsigned int slot = ring->tail & ___GC_MAJOR_PREFETCH_MASK;
                ring->entries[slot].sec = sec;
                ring->entries[slot].hdr = hdr;
                ring->entries[slot].off = off;
                ring->tail++;
              }
              return;
            }
          {
            ___WORD head = ___WORD_LOAD_RELAXED(hdr);
            if (___HD_TYP(head) == ___MOVABLE0)
              major_shade_mature_movable_q(vm, q, sec, hdr, head, allow_alloc);
          }
        }
      return;
    }

  if (q != 0 && q->track_nonstatic)
    {
      ___WORD vhead = ___WORD_LOAD_RELAXED(hdr);
      if (___HD_TYP(vhead) != ___PERM)
        q->saw_nonstatic = 1;
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
   * recovery if global stack capacity is exceeded. */
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0 || ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    {
      ___ps->mem.satb_count_ = 0;
      return;
    }

  if (___ps->mem.major_mark_local_buf_ != 0)
    {
      major_local_queue lq = {0};
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
  ___WORD head = ___WORD_LOAD_ACQUIRE(body - 1);
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
        {
          ___SCMOBJ v = ___WORD_LOAD_RELAXED(&body[i]);
          if (___MEM_ALLOCATED(v))
            major_shade_obj_q(vm, q, v, 1);
        }
      break;

    default:
      for (i = 0; i < words; i++)
        {
          ___SCMOBJ v = ___WORD_LOAD_RELAXED(&body[i]);
          if (___MEM_ALLOCATED(v))
            major_shade_obj_q(vm, q, v, 1);
        }
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
  major_local_queue lq = {0};
  major_prefetch_ring ring;
  unsigned int i;

  if (___ps == 0 || budget_words <= 0)
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    return 0;
  if (___ps->mem.major_mark_local_buf_ == 0)
    return 0;

  ring.head = 0u;
  ring.tail = 0u;
  lq.buf = ___ps->mem.major_mark_local_buf_;
  lq.count = &___ps->mem.major_mark_local_count_;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;
  lq.ring = &ring;

  /* Drain this processor's local SATB buffer directly into prefetch ring / local buffer. */
  if (___ps->mem.satb_buf_ != 0 && ___ps->mem.satb_count_ > 0)
    {
      unsigned int n = ___ps->mem.satb_count_;
      ___SCMOBJ local_copy[___GC_SATB_BUF_CAP];
      memcpy(local_copy, ___ps->mem.satb_buf_, n * sizeof(___SCMOBJ));
      ___ps->mem.satb_count_ = 0;
      for (i = 0; i < n; i++)
        major_shade_obj_q(vm, &lq, local_copy[i], 1);
      ___WORD_STORE_RELEASE(
        &___ps->mem.major_satb_logged_local_,
        ___ps->mem.major_satb_logged_local_ + ___CAST(___WORD, n));
    }

  while (scanned < budget_words)
    {
      if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
        break;

      if ((ring.tail - ring.head) < ___GC_MAJOR_PREFETCH_MIN && *lq.count > 0)
        {
          ___SCMOBJ obj = lq.buf[--(*lq.count)];
          ___SIZE_TS w;
#if defined(__GNUC__) || defined(__clang__)
          if (*lq.count >= 4)
            __builtin_prefetch(___BODY0(lq.buf[*lq.count - 4]) - 1, 0, 1);
#endif
          w = major_scan_object_q(vm, &lq, obj, 0);
          if (w < 0)
            break;
          scanned += w;
          continue;
        }

      if (ring.tail != ring.head)
        {
          major_prefetch_entry e = ring.entries[ring.head & ___GC_MAJOR_PREFETCH_MASK];
          ___SCMOBJ scan_obj = 0;
          ring.head++;
          major_prefetch_ring_process_one(vm, &lq, e, 1, &scan_obj);
          if (scan_obj != 0)
            {
              ___SIZE_TS w = major_scan_object_q(vm, &lq, scan_obj, 0);
              if (w < 0)
                break;
              scanned += w;
            }
          continue;
        }

      /* Local buffer and prefetch ring both empty: steal batch from global mark stack. */
      {
        ___WORD avail;
        unsigned int take = 0;
        int retries = 32;
        if (___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) <= 0)
          break;
        while (!major_mark_trylock(vm))
          {
            if (--retries <= 0 ||
                ___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) <= 0 ||
                ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
              goto done_slice_loop;
            ___CPU_RELAX();
          }
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
    }

 done_slice_loop:
  /* Conserve 100% of remaining prefetched entries into local mark buffer before exit. */
  major_prefetch_ring_drain_to_queue(vm, &lq, 1);

  /* Share excess local work back to global stack so stealing cores never starve
   * while avoiding unnecessary spinlock traffic when global stack is already deep. */
  if (*lq.count > 32 &&
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) < 256 &&
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) == ___GC_MAJOR_MARKING)
    {
      unsigned int spill = *lq.count - 32;
      major_mark_stack_push_batch_ex(vm, &lq.buf[32], spill, 1);
      *lq.count = 32;
    }

  if (scanned > 0)
    {
      ___WORD_STORE_RELEASE(
        &___ps->mem.major_mark_slices_local_,
        ___ps->mem.major_mark_slices_local_ + 1);
      ___WORD_STORE_RELEASE(
        &___ps->mem.major_marked_words_local_,
        ___ps->mem.major_marked_words_local_ + ___CAST(___WORD, scanned));
      ___WORD_FETCH_ADD_RELEASE(
        &vm->mem.major_work_done_words_,
        ___CAST(___WORD, scanned));
    }
  return scanned;
}

/* Global atomic work pacer (OCaml-5 alloc_counter / work_counter model):
 * credits managed + phantom allocation words into vm->mem.major_alloc_words_
 * and performs a proportional concurrent mark slice whenever completed work
 * trails ceil(W * alloc / E), guaranteeing marking finishes before 2x headroom. */
___HIDDEN ___SIZE_TS gc_major_pace_alloc_words
   (___processor_state ___ps,
    ___SIZE_TS alloc_words)
{
  ___virtual_machine_state vm;
  ___WORD total_alloc, done;
  ___SIZE_TS headroom, target_total, target_work, budget;
  double target_d;

  if (___ps == 0 || alloc_words <= 0 || ___ps->primlock_depth != 0)
    return 0;
  if (___EXPECT_TRUE(___WORD_LOAD_RELAXED(&___ps->mem.satb_active_) == 0))
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0 || ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    return 0;

  total_alloc =
    ___WORD_FETCH_ADD_RELEASE(&vm->mem.major_alloc_words_, ___CAST(___WORD, alloc_words)) +
    ___CAST(___WORD, alloc_words);

  headroom = vm->mem.pacing_headroom_words_;
  if (headroom < 2 * ___MSECTION_SIZE)
    headroom = 2 * ___MSECTION_SIZE;
  target_total = vm->mem.pacing_work_target_words_;
  if (target_total < 2 * ___MSECTION_SIZE)
    target_total = 2 * ___MSECTION_SIZE;

  target_d = (___CAST(double, target_total) * ___CAST(double, total_alloc)) /
             ___CAST(double, headroom);
  if (target_d >= ___CAST(double, target_total))
    target_work = target_total;
  else
    target_work = ___CAST(___SIZE_TS, target_d) + 1;

  done = ___WORD_LOAD_ACQUIRE(&vm->mem.major_work_done_words_);
  if (target_work > ___CAST(___SIZE_TS, done))
    {
      int np = (vm->processor_count > 0) ? vm->processor_count : 1;
      ___SIZE_TS deficit = target_work - ___CAST(___SIZE_TS, done);
      double fair_d = (___CAST(double, target_total) * ___CAST(double, alloc_words)) /
                      ___CAST(double, headroom);
      ___SIZE_TS fair_slice = ___CAST(___SIZE_TS, fair_d) + 1;
      ___SIZE_TS share = (deficit + np - 1) / np;
      if (target_d >= ___CAST(double, target_total))
        {
          /* Past 75% of remaining headroom: drain remaining mark work
           * aggressively before concurrent allocation hits the 2x limit. */
          budget = (deficit > 262144) ? 262144 : deficit;
          if (budget < 16384)
            budget = 16384;
        }
      else
        {
          budget = (fair_slice > share) ? fair_slice : share;
          if (budget > deficit)
            budget = deficit;
          if (budget < 16384)
            budget = 16384;
          if (budget > 131072)
            budget = 131072;
        }
    }
  else if (___CAST(___SIZE_TS, total_alloc) >= headroom &&
           (___ps->mem.major_mark_local_count_ > 0 ||
            ___ps->mem.satb_count_ > 0 ||
            ___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) > 0))
    {
      budget = 65536;
    }
  else if (___ps->mem.satb_count_ >= (___GC_SATB_BUF_CAP >> 1))
    {
      budget = 8192;
    }
  else
    {
      return 0;
    }

  return ___gc_major_mark_slice(___ps, budget);
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
      ___WORD_STORE_RELEASE(
        &___ps->mem.major_idle_slices_local_,
        ___ps->mem.major_idle_slices_local_ + 1);
      return 1;
    }
  return 0;
}

/* Amp-2 Cut 2B: Opportunistic STW entry spin-wait concurrent marking slice.
 * Invoked strictly during STW ENTERING (before upward barrier arrival publish,
 * never during FLIPPING/REMARK/SWEEPING). Strictly bounded to 2048 words (~3us)
 * and exits in 1 relaxed load when major marking is inactive. */
int ___gc_major_mark_stw_spin_slice
   ___P((___processor_state ___ps),
        (___ps)
___processor_state ___ps;)
{
#ifdef ___USE_HANDLES
  (void)___ps;
  return 0;
#else
  ___virtual_machine_state vm;
  ___SIZE_TS w;

  if (___ps == 0 || ___ps->primlock_depth != 0)
    return 0;
  if (___EXPECT_TRUE(___WORD_LOAD_RELAXED(&___ps->mem.satb_active_) == 0))
    return 0;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  if (vm == 0 || ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_MARKING)
    return 0;
  if (___ps->mem.major_mark_local_count_ == 0 &&
      ___ps->mem.satb_count_ == 0 &&
      ___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) == 0)
    return 0;

  w = ___gc_major_mark_slice(___ps, 1024);
  if (w > 0)
    {
      ___WORD_STORE_RELEASE(
        &___ps->mem.major_spin_slices_local_,
        ___ps->mem.major_spin_slices_local_ + 1);
      return 1;
    }
  return 0;
#endif
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

  /* Record mature section count for parallel Initial-Mark bitmap clear
   * (major_initial_mark_clear_parallel runs across all w_cnt workers). */
  ___COLLECTION(vm).major_sweep_nm = vm->mem.nb_msections_mature_;
  (void)ms;
  (void)sec;
  (void)epoch;

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

  /* Publish MARKING phase and arm SATB barrier across ALL processors (active
   * and parked FFI processors alike; ___leave_blocking_ffi also adopts it). */
  {
    ___F64 u0, s0, r0;
    ___SIZE_TS half_sec = ___MSECTION_SIZE >> 1;
    ___SIZE_TS lim_sec = ___CAST(___SIZE_TS, vm->mem.major_trigger_sections_) * 2;
    ___SIZE_TS cur_sec = ___CAST(___SIZE_TS, vm->mem.nb_msections_mature_);
    ___SIZE_TS e_sec = (lim_sec > cur_sec + 4) ? ((lim_sec - cur_sec) * half_sec) : (4 * half_sec);
    ___SIZE_TS lim_still = vm->mem.major_trigger_still_words_ * 2;
    ___SIZE_TS cur_still = vm->mem.mature_still_words_;
    ___SIZE_TS e_still = (lim_still > cur_still + 2 * ___MSECTION_SIZE)
                           ? (lim_still - cur_still)
                           : (2 * ___MSECTION_SIZE);
    ___SIZE_TS e = (e_sec < e_still) ? e_sec : e_still;
    ___SIZE_TS e_minor = ___CAST(___SIZE_TS, (np > 0 ? np : 1)) * half_sec * 6;
    ___SIZE_TS w = vm->mem.occupied_words_mature_ + vm->mem.mature_still_words_;
    ___WORD ph_trig = ___WORD_LOAD_ACQUIRE(&vm->mem.major_trigger_phantom_bytes_);
    ___WORD ph_live = ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_);

    gc_pacing_sample_mutator(vm);
    ___process_times(&u0, &s0, &r0);
    vm->mem.pacing_major_start_real_ = r0;

    if (e_minor < e)
      e = e_minor;
    if (ph_trig > 0 && ph_live >= (ph_trig >> 1))
      {
        ___WORD ph_rem = (ph_trig * 2 > ph_live) ? (ph_trig * 2 - ph_live) : (ph_trig >> 1);
        ___SIZE_TS e_ph = ___CAST(___SIZE_TS, ph_rem >> ___LWS);
        if (e_ph < e)
          e = e_ph;
      }
    /* Target concurrent mark completion at 75% of remaining headroom so
     * mutator pacing drains the mark graph well before 2x emergency Remark. */
    e = (e * 3) >> 2;
    if (e < 2 * ___MSECTION_SIZE)
      e = 2 * ___MSECTION_SIZE;
    if (w < 4 * ___MSECTION_SIZE)
      w = 4 * ___MSECTION_SIZE;

    vm->mem.pacing_headroom_words_ = e;
    vm->mem.pacing_work_target_words_ = w;
    ___WORD_STORE_RELEASE(&vm->mem.major_alloc_words_, 0);
    ___WORD_STORE_RELEASE(&vm->mem.major_work_done_words_, 0);
    ___WORD_STORE_RELEASE(&vm->mem.phantom_gc_needed_, 0);
  }
  vm->mem.minor_gcs_since_major_ = 0;
  ___WORD_STORE_RELEASE(&vm->mem.major_phase_, ___GC_MAJOR_MARKING);
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
      ps->mem.stack_watermark_epoch_ = vm->mem.major_epoch_;
      ___WORD_STORE_RELEASE(&ps->mem.satb_active_, 1);
    }
}

/* Shade existing mature wills AFTER parallel section epoch/bitmap clear. */
___HIDDEN void major_initial_mark_seed_wills(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;
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
}

/* Parallel Initial-Mark mature section snapshot & mark-bitmap clear across all
 * w_cnt workers using strided partitioning (si % w_cnt == w_id). */
___HIDDEN void major_initial_mark_clear_parallel
   (___virtual_machine_state vm,
    int w_id,
    int w_cnt)
{
  int nm = ___COLLECTION(vm).major_sweep_nm;
  ___UWORD epoch = vm->mem.major_epoch_;
  int si;

  for (si = w_id; si < nm; si += w_cnt)
    {
      ___msection *sec = vm->mem.mature_sections_[si];
      if (sec == 0 || sec->region_age != ___GC_REGION_MATURE ||
          sec->major_static_gen != 0)
        continue;
      sec->major_mark_epoch = epoch;
      sec->major_snapshot_words = sec->mature_words;
      sec->major_live_words = 0;
      sec->major_evacuate = 0;
      sec->major_hole_start = 0;
      sec->major_hole_end = 0;
      memset(sec->major_line_live, 0, sizeof(sec->major_line_live));
      memset(___CAST(void*, section_major_mark_bits(sec)), 0, SECTION_MAJOR_MARK_BYTES);
    }
}

/* Scan a dirty static mature section during STW (Initial-Mark or Remark).
 * When clear_if_closed != 0, clear static_major_dirty to 0 only if zero
 * outgoing edges to non-static objects were observed (inductive closure). */
___HIDDEN ___SIZE_TS major_scan_dirty_static_section
   (___virtual_machine_state vm,
    major_local_queue *q,
    ___msection *sec,
    int clear_if_closed)
{
  ___WORD *base = sec->base + sec->active_offset;
  ___WORD *end = base + sec->mature_words;
  ___WORD *ptr = base;
  ___SIZE_TS scanned = 0;

  if (q != 0)
    {
      q->track_nonstatic = clear_if_closed ? 1 : 0;
      q->saw_nonstatic = 0;
    }

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
        int subtype = ___HD_SUBTYPE(head);
        if (still_subtype_has_pointers(subtype))
          {
            ___SIZE_TS w = major_scan_object_q(
              vm, q, major_make_scmobj_from_body(ptr + 1, subtype), 1);
            if (w > 0)
              scanned += w;
          }
        ptr += words + 1;
      }
    }

  if (q != 0)
    {
      q->track_nonstatic = 0;
      if (clear_if_closed && q->saw_nonstatic == 0)
        ___WORD_STORE_RELEASE(&sec->static_major_dirty, 0);
    }
  return scanned;
}

/* Parallel Initial-Mark seeding of dirty static sections after bitmap clear. */
___HIDDEN void major_initial_mark_seed_static_dirty_parallel
   (___virtual_machine_state vm,
    int w_id,
    int w_cnt)
{
  int nm = ___COLLECTION(vm).major_sweep_nm;
  int si;
  ___SCMOBJ lbuf[___GC_MAJOR_LOCAL_MARK_CAP];
  unsigned int lcnt = 0;
  major_prefetch_ring ring;
  major_local_queue lq = {0};

  if (vm->mem.nb_msections_static_ <= 0)
    return;

  ring.head = 0u;
  ring.tail = 0u;
  lq.buf = lbuf;
  lq.count = &lcnt;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;
  lq.ring = &ring;

  for (si = w_id; si < nm; si += w_cnt)
    {
      ___msection *sec = vm->mem.mature_sections_[si];
      if (sec == 0 || sec->region_age != ___GC_REGION_MATURE ||
          sec->major_static_gen == 0 ||
          ___WORD_LOAD_ACQUIRE(&sec->static_major_dirty) == 0)
        continue;
      major_scan_dirty_static_section(vm, &lq, sec, 0);
    }

  major_prefetch_ring_drain_to_queue(vm, &lq, 1);
  if (lcnt > 0)
    major_mark_stack_push_batch_ex(vm, lbuf, lcnt, 1);
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

/* Single-threaded STW mark-stack drain (used after overflow recovery & wills)
 * with Amp-2 256-entry software prefetch ring. */
___HIDDEN void major_drain_mark_stack_stw(___virtual_machine_state vm)
{
  ___SCMOBJ lbuf[___GC_MAJOR_LOCAL_MARK_CAP];
  unsigned int lcnt = 0;
  major_prefetch_ring ring;
  major_local_queue lq = {0};
  ___SIZE_TS scanned = 0;

  ring.head = 0u;
  ring.tail = 0u;
  lq.buf = lbuf;
  lq.count = &lcnt;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;
  lq.ring = &ring;

  for (;;)
    {
      while (lcnt > 0 || ring.tail != ring.head)
        {
          if ((ring.tail - ring.head) < ___GC_MAJOR_PREFETCH_MIN && lcnt > 0)
            {
              ___SCMOBJ obj = lbuf[--lcnt];
              ___SIZE_TS w = major_scan_object_q(vm, &lq, obj, 1);
              if (w > 0)
                scanned += w;
            }
          else
            {
              major_prefetch_entry e = ring.entries[ring.head & ___GC_MAJOR_PREFETCH_MASK];
              ___SCMOBJ scan_obj = 0;
              ring.head++;
              major_prefetch_ring_process_one(vm, &lq, e, 1, &scan_obj);
              if (scan_obj != 0)
                {
                  ___SIZE_TS w = major_scan_object_q(vm, &lq, scan_obj, 1);
                  if (w > 0)
                    scanned += w;
                }
            }
        }
      {
        ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
        if (avail <= 0)
          break;
        {
          unsigned int take = (avail > 128) ? 128u : ___CAST(unsigned int, avail);
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
      if (sec->major_static_gen != 0 || sec->major_mark_epoch != vm->mem.major_epoch_)
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
          if (sec->major_static_gen != 0 &&
              ___WORD_LOAD_ACQUIRE(&sec->static_major_dirty) == 0)
            {
              if (sec == vm->mem.mature_tail_)
                break;
              continue;
            }
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
 * 4-Barrier Parallel STW Remark & Parallel Non-Moving Immix Sweep
 * ========================================================================== */

/* Coordinator setup before Phase R-A BARRIER. */
___HIDDEN void major_remark_phase_a_prepare(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  ___F64 u0, s0, r0;
  int i;

  ___process_times(&u0, &s0, &r0);
  g->major_remark_r0 = r0;
  {
    /* Single-word atomic quiescence counter:
     *   inflight = working_workers + sum(inboxes[d].count) + major_mark_stack_count_
     * Stored in vm->mem.major_remark_working_ so termination is a single
     * monotonic zero-latch atomic load with zero split-counter races. */
    ___WORD init_stack = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
    ___WORD_STORE_RELEASE(
      &vm->mem.major_remark_working_,
      ___CAST(___WORD, g->worker_count) + init_stack);
  }
  ___WORD_STORE_RELEASE(&g->major_remote_pending, 0);
  g->major_remote_inboxes = 0;
  if (g->worker_count > 1 && g->worker_count <= ___GC_MAJOR_MAX_STATIC_WORKERS)
    {
      major_remote_inbox *ibs = ___CAST(major_remote_inbox*,
        ___ALLOC_MEM(___CAST(___SIZE_TS, g->worker_count) * sizeof(major_remote_inbox)));
      if (ibs != 0)
        {
          memset(ibs, 0, ___CAST(___SIZE_TS, g->worker_count) * sizeof(major_remote_inbox));
          g->major_remote_inboxes = ibs;
        }
    }
  for (i = 0; i < g->worker_count; i++)
    {
      g->major_reclaimed_still[i] = 0;
      g->major_live_still[i] = 0;
    }
}

/* Phase R-A (Parallel across all w_cnt workers):
 *   1. Flush per-processor SATB + local mark buffers for p % w_cnt == w_id.
 *   2. Chez Creator-Owned Segment Routing: each worker owns sections where
 *      (sec->index % w_cnt == w_id) with ZERO atomic RMWs on owned mark bitmaps;
 *      remote pointers are batched into per-owner inboxes, eliminating global
 *      major_mark_lock_ contention and cross-core bitmap cache-line bouncing.
 *   3. Exact atomic quiescence: working == 0 && remote_pending == 0 && stack == 0. */
___HIDDEN void major_remark_phase_a_parallel
   (___virtual_machine_state vm,
    int w_id,
    int w_cnt)
{
  ___gc_round *g = &___COLLECTION(vm);
  int np = vm->processor_count;
  int p, dst;
  ___SCMOBJ lbuf[___GC_MAJOR_LOCAL_MARK_CAP];
  unsigned int lcnt = 0;
  ___SCMOBJ out_buf[___GC_MAJOR_MAX_STATIC_WORKERS][___GC_MAJOR_REMOTE_BATCH];
  unsigned int out_cnt[___GC_MAJOR_MAX_STATIC_WORKERS];
  major_remote_inbox *inboxes = ___CAST(major_remote_inbox*, g->major_remote_inboxes);
  major_prefetch_ring ring;
  major_local_queue lq = {0};
  ___SIZE_TS scanned = 0;
  ___SIZE_TS satb_n = 0;
  ___VOLATILE ___WORD *inflight = &vm->mem.major_remark_working_;
  int use_chez = (w_cnt > 1 && w_cnt <= ___GC_MAJOR_MAX_STATIC_WORKERS && inboxes != 0);

  ring.head = 0u;
  ring.tail = 0u;
  lq.buf = lbuf;
  lq.count = &lcnt;
  lq.cap = ___GC_MAJOR_LOCAL_MARK_CAP;
  lq.ring = &ring;
  lq.inflight_counter = inflight;
  if (use_chez)
    {
      memset(out_cnt, 0, ___CAST(___SIZE_TS, w_cnt) * sizeof(unsigned int));
      lq.owner_w_id = w_id;
      lq.owner_w_cnt = w_cnt;
      lq.inboxes = inboxes;
      lq.out_buf = out_buf;
      lq.out_cnt = out_cnt;
      lq.remote_pending = inflight;
    }

  for (p = w_id; p < np; p += w_cnt)
    {
      ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      unsigned int i;
      if (pps->mem.major_mark_local_count_ > 0)
        {
          major_mark_stack_push_batch_inflight(
            vm, pps->mem.major_mark_local_buf_, pps->mem.major_mark_local_count_, 1, inflight);
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

  if (vm->mem.nb_msections_static_ > 0)
    {
      int nm = vm->mem.nb_msections_mature_;
      int si;
      for (si = w_id; si < nm; si += w_cnt)
        {
          ___msection *sec = vm->mem.mature_sections_[si];
          if (sec == 0 || sec->region_age != ___GC_REGION_MATURE ||
              sec->major_static_gen == 0 ||
              ___WORD_LOAD_ACQUIRE(&sec->static_major_dirty) == 0)
            continue;
          scanned += major_scan_dirty_static_section(vm, &lq, sec, 1);
        }
    }

  for (;;)
    {
      while (lcnt > 0 || ring.tail != ring.head)
        {
          if ((ring.tail - ring.head) < ___GC_MAJOR_PREFETCH_MIN && lcnt > 0)
            {
              ___SCMOBJ obj = lbuf[--lcnt];
              ___SIZE_TS w;
#if defined(__GNUC__) || defined(__clang__)
              if (lcnt >= 4)
                __builtin_prefetch(___BODY0(lbuf[lcnt - 4]) - 1, 0, 1);
#endif
              w = major_scan_object_q(vm, &lq, obj, 1);
              if (w > 0)
                scanned += w;
            }
          else
            {
              major_prefetch_entry e = ring.entries[ring.head & ___GC_MAJOR_PREFETCH_MASK];
              ___SCMOBJ scan_obj = 0;
              ring.head++;
              major_prefetch_ring_process_one(vm, &lq, e, 1, &scan_obj);
              if (scan_obj != 0)
                {
                  ___SIZE_TS w = major_scan_object_q(vm, &lq, scan_obj, 1);
                  if (w > 0)
                    scanned += w;
                }
            }
        }

      /* Chez remote flush & inbox drain (lock-free of global major_mark_lock_). */
      if (use_chez)
        {
          for (dst = 0; dst < w_cnt; dst++)
            {
              if (out_cnt[dst] > 0)
                major_remote_flush_one(vm, &lq, dst);
            }
          if (___WORD_LOAD_ACQUIRE(&inboxes[w_id].count) > 0)
            {
              major_remote_inbox *my_ib = &inboxes[w_id];
              ___SCMOBJ rbatch[___GC_MAJOR_LOCAL_MARK_CAP];
              unsigned int take = 0;
              unsigned int ri;
              major_inbox_lock(my_ib);
              if (my_ib->count > 0)
                {
                  take = (my_ib->count > ___GC_MAJOR_LOCAL_MARK_CAP)
                           ? ___GC_MAJOR_LOCAL_MARK_CAP
                           : ___CAST(unsigned int, my_ib->count);
                  my_ib->count -= ___CAST(___SIZE_TS, take);
                  memcpy(rbatch, &my_ib->buf[my_ib->count], take * sizeof(___SCMOBJ));
                  major_inflight_add(inflight, -___CAST(___WORD, take));
                }
              major_inbox_unlock(my_ib);
              if (take > 0)
                {
                  for (ri = 0; ri < take; ri++)
                    major_shade_obj_q(vm, &lq, rbatch[ri], 1);
                  continue;
                }
            }
        }

      major_mark_lock(vm);
      {
        ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
        if (avail > 0)
          {
            unsigned int take = (avail > 64) ? 64u : ___CAST(unsigned int, avail);
            avail -= ___CAST(___WORD, take);
            memcpy(lbuf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
            ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
            major_inflight_add(inflight, -___CAST(___WORD, take));
            lcnt = take;
            major_mark_unlock(vm);
            continue;
          }
        major_inflight_add(inflight, -1);
      }
      major_mark_unlock(vm);

      if (w_cnt <= 1)
        break;

      {
        unsigned int idle_spins = 0;
        while (___WORD_LOAD_ACQUIRE(inflight) > 0)
          {
            if (use_chez && ___WORD_LOAD_ACQUIRE(&inboxes[w_id].count) > 0)
              {
                major_remote_inbox *my_ib = &inboxes[w_id];
                ___SCMOBJ rbatch[___GC_MAJOR_LOCAL_MARK_CAP];
                unsigned int take = 0;
                unsigned int ri;
                major_inbox_lock(my_ib);
                if (my_ib->count > 0)
                  {
                    take = (my_ib->count > ___GC_MAJOR_LOCAL_MARK_CAP)
                             ? ___GC_MAJOR_LOCAL_MARK_CAP
                             : ___CAST(unsigned int, my_ib->count);
                    my_ib->count -= ___CAST(___SIZE_TS, take);
                    memcpy(rbatch, &my_ib->buf[my_ib->count], take * sizeof(___SCMOBJ));
                    /* Single atomic RMW exchanges `take` queued inbox units for 1
                     * working credit so inflight never visits 0 while work exists. */
                    major_inflight_add(inflight, 1 - ___CAST(___WORD, take));
                  }
                major_inbox_unlock(my_ib);
                if (take > 0)
                  {
                    for (ri = 0; ri < take; ri++)
                      major_shade_obj_q(vm, &lq, rbatch[ri], 1);
                    break;
                  }
              }
            if (___WORD_LOAD_ACQUIRE(&vm->mem.major_mark_stack_count_) > 0)
              {
                major_mark_lock(vm);
                {
                  ___WORD avail = ___WORD_LOAD_RELAXED(&vm->mem.major_mark_stack_count_);
                  if (avail > 0)
                    {
                      unsigned int take = (avail > 64) ? 64u : ___CAST(unsigned int, avail);
                      avail -= ___CAST(___WORD, take);
                      memcpy(lbuf, &vm->mem.major_mark_stack_[avail], take * sizeof(___SCMOBJ));
                      ___WORD_STORE_RELEASE(&vm->mem.major_mark_stack_count_, avail);
                      major_inflight_add(inflight, 1 - ___CAST(___WORD, take));
                      lcnt = take;
                      major_mark_unlock(vm);
                      break;
                    }
                }
                major_mark_unlock(vm);
              }
            if (idle_spins < 1024u)
              {
                ___CPU_RELAX();
                idle_spins++;
              }
            else if (idle_spins < 4096u)
              {
                int ri;
                for (ri = 0; ri < 8; ri++)
                  ___CPU_RELAX();
                idle_spins++;
              }
            else
              {
#if defined(___USE_POSIX_THREAD_SYSTEM) && !defined(_WIN32)
                struct timespec ts;
                ts.tv_sec = 0;
                ts.tv_nsec = 5000;
                nanosleep(&ts, 0);
#else
                ___CPU_RELAX();
#endif
              }
          }
      }
      if (lcnt == 0 &&
          ring.tail == ring.head &&
          ___WORD_LOAD_ACQUIRE(inflight) == 0)
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
 *   1. Free Chez remote inboxes.
 *   2. Overflow recovery if satb_overflow_ != 0.
 *   3. Resolve mature wills and drain any shaded testator subgraph.
 *   4. Atomically clear dead WHITE weak-table entries BEFORE SWEEPING.
 *   5. Transition phase -> SWEEPING, disarm SATB, freeze mature_sections count. */
___HIDDEN void major_remark_phase_b_coord(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  int np = vm->processor_count;
  int p;

  if (g->major_remote_inboxes != 0)
    {
      major_remote_inbox *ibs = ___CAST(major_remote_inbox*, g->major_remote_inboxes);
      int wi;
      for (wi = 0; wi < g->worker_count; wi++)
        {
          if (ibs[wi].buf != 0)
            ___FREE_MEM(ibs[wi].buf);
        }
      ___FREE_MEM(ibs);
      g->major_remote_inboxes = 0;
    }

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
   * tables BEFORE transitioning to SWEEPING. */
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
      ps->mem.stack_watermark_epoch_ = 0;
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
    }

  g->major_sweep_nm = vm->mem.nb_msections_mature_;
  if (vm->mem.the_msections_ != 0)
    lxr_drc_ensure(vm, vm->mem.the_msections_->nb_sections);
}

/* Close one contiguous dead WHITE run [run_lo, run_hi) strictly inside full
 * cards [0 .. full_card_words) by emitting card-aligned leaf ___sU8VECTOR
 * fillers, recording exact card starts, and recording ALL >=512-word 128-word
 * aligned Immix free line runs in sec->major_line_live[] for multi-hole reuse. */
static inline void major_close_dead_run
   (___msection *sec,
    ___WORD *base,
    ___SIZE_TS run_lo,
    ___SIZE_TS run_hi)
{
  ___SIZE_TS l_lo, l_hi;
  if (run_hi <= run_lo)
    return;
  l_lo = (run_lo + 127) & ~___CAST(___SIZE_TS, 127);
  l_hi = run_hi & ~___CAST(___SIZE_TS, 127);
  if (l_hi > l_lo && (l_hi - l_lo) >= ___GC_IMMIX_MIN_HOLE_WORDS)
    {
      const ___SIZE_TS max_lines = 8 * ___WORD_WIDTH;
      ___SIZE_TS ln_lo = l_lo >> 7;
      ___SIZE_TS ln_hi = l_hi >> 7;
      ___SIZE_TS ln;
      if (l_lo > run_lo)
        {
          base[run_lo] = ___MAKE_HD_WORDS(l_lo - run_lo - 1, ___sU8VECTOR);
          record_mature_obj_start(sec, base + run_lo);
        }
      base[l_lo] = ___MAKE_HD_WORDS(l_hi - l_lo - 1, ___sU8VECTOR);
      record_mature_obj_start(sec, base + l_lo);
      if (run_hi > l_hi)
        {
          base[l_hi] = ___MAKE_HD_WORDS(run_hi - l_hi - 1, ___sU8VECTOR);
          record_mature_obj_start(sec, base + l_hi);
        }
      if (ln_hi > max_lines)
        ln_hi = max_lines;
      for (ln = ln_lo; ln < ln_hi; ln++)
        sec->major_line_live[ln / ___WORD_WIDTH] |=
          (___CAST(___UWORD, 1) << (ln & (___WORD_WIDTH - 1)));
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
              ___SIZE_TS len = base[___STILL_LENGTH];
              my_reclaimed_still += len;
              if (___HD_SUBTYPE(head) == ___sFOREIGN && !gc_try_reclaim_refc_foreign(base))
                ___lifecycle_defer(ps, base);
              else if (!free_mem_aligned_heap_ex(base) && len > 0)
                gc_record_freed_malloc_still_words((___SIZE_T)len);
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
      if (sec->major_static_gen != 0)
        {
          sec->major_evacuate = 0;
          continue;
        }

      if (sec->major_mark_epoch == epoch &&
          sec->major_live_words == 0 &&
          sec->mature_words == sec->major_snapshot_words)
        {
          /* Tag 100%-dead section for O(1) coordinator unlink in Phase R-D. */
          sec->major_evacuate = 2;
          sec->major_hole_start = 0;
          sec->major_hole_end = 0;
          memset(sec->major_line_live, 0, sizeof(sec->major_line_live));
          continue;
        }

      {
        ___SIZE_TS local_live_words = 0;
        ___SIZE_TS effective_live;
        int has_weak = 0;

        memset(sec->major_line_live, 0, sizeof(sec->major_line_live));

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
                    else
                      {
                        /* Replace chunk-link ___FORW inside the boundary card with a
                         * 1-word leaf filler so starts[boundary_card] becomes 0 and
                         * dirty-card walks never backtrack across full_card_words into
                         * a recycled Immix hole. */
                        *ptr = ___MAKE_HD_WORDS(0, ___sU8VECTOR);
                        record_mature_obj_start(sec, ptr);
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
                                  major_close_dead_run(sec, base, run_lo, run_hi);
                                  in_dead = 0;
                                }
                              *ptr = ___MAKE_HD_WORDS(words, ___sU8VECTOR);
                              record_mature_obj_start(sec, ptr);
                            }
                        }
                      else
                        {
                          if (___HD_SUBTYPE(head) == ___sWEAK)
                            has_weak = 1;
                          local_live_words += (words + 1);
                          if (in_dead)
                            {
                              major_close_dead_run(sec, base, run_lo, run_hi);
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
                          major_close_dead_run(sec, base, run_lo, run_hi);
                          in_dead = 0;
                        }
                      if (!major_is_marked_word(sec, off))
                        *ptr = ___MAKE_HD_WORDS(words, ___sU8VECTOR);
                      else
                        {
                          if (___HD_SUBTYPE(head) == ___sWEAK)
                            has_weak = 1;
                          local_live_words += (words + 1);
                        }
                    }
                  ptr += words + 1;
                }
              }
            if (in_dead)
              major_close_dead_run(sec, base, run_lo, run_hi);
            /* If post-snapshot promotions appended a chunk-link ___FORW right at
             * a card-aligned snap_words boundary, replace it with a 1-word leaf
             * filler so starts[snap_card] == 0 blocks dirty-card backtracking. */
            if (sec->mature_words > snap_words &&
                (snap_words & (___GC_CARD_WORDS - 1)) == 0 &&
                ___TESTTYPE(base[snap_words], ___FORW))
              {
                base[snap_words] = ___MAKE_HD_WORDS(0, ___sU8VECTOR);
                record_mature_obj_start(sec, base + snap_words);
              }
            sec->major_live_words = ___CAST(___WORD, local_live_words);
          }

        /* Sync 2-bit deferred-RC side-table from exact SATB sweep liveness,
         * then claim the first/largest dead hole from major_line_live[]. */
        lxr_drc_sync_section_after_sweep(vm, sec);
        section_advance_next_immix_hole(sec);

        if (sec->major_mark_epoch == epoch)
          {
            ___SIZE_TS post_snap = (sec->mature_words > sec->major_snapshot_words)
                                     ? (sec->mature_words - sec->major_snapshot_words)
                                     : 0;
            effective_live = local_live_words + post_snap;
          }
        else
          effective_live = sec->mature_words;

        if (sec->mature_words >= (___MSECTION_SIZE >> 3) &&
            effective_live * 2 < sec->mature_words)
          sec->major_evacuate = 1;
        else
          sec->major_evacuate = 0;

        if (!has_weak &&
            sec->major_mark_epoch == epoch &&
            sec->major_evacuate == 0 &&
            sec->mature_words == sec->major_snapshot_words &&
            sec->major_hole_end <= sec->major_hole_start &&
            sec->mature_words >= ((___MSECTION_SIZE >> 1) * 3) / 4 &&
            local_live_words * 100 >= sec->mature_words * 85)
          {
            if (sec->major_survive_count < 255)
              sec->major_survive_count++;
            if (sec->major_survive_count >= 2)
              {
                sec->major_static_gen = 1;
                ___WORD_STORE_RELEASE(&sec->static_major_dirty, 1);
              }
          }
        else
          {
            sec->major_survive_count = 0;
          }
      }
    }
}

/* Fold per-processor lock-free major marking counters into VM totals during STW. */
___HIDDEN void major_fold_local_stats_stw(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD sl = ___WORD_LOAD_ACQUIRE(&ps->mem.major_mark_slices_local_);
      ___WORD mw = ___WORD_LOAD_ACQUIRE(&ps->mem.major_marked_words_local_);
      ___WORD sb = ___WORD_LOAD_ACQUIRE(&ps->mem.major_satb_logged_local_);
      ___WORD id = ___WORD_LOAD_ACQUIRE(&ps->mem.major_idle_slices_local_);
      ___WORD sp = ___WORD_LOAD_ACQUIRE(&ps->mem.major_spin_slices_local_);
      if (sl != 0)
        {
          vm->mem.concurrent_major_mark_slices_ += ___CAST(___F64, sl);
          ps->mem.major_mark_slices_local_ = 0;
        }
      if (mw != 0)
        {
          vm->mem.concurrent_major_marked_words_ += ___CAST(___F64, mw);
          ps->mem.major_marked_words_local_ = 0;
        }
      if (sb != 0)
        {
          vm->mem.concurrent_major_satb_logged_ += ___CAST(___F64, sb);
          ps->mem.major_satb_logged_local_ = 0;
        }
      if (id != 0)
        {
          vm->mem.concurrent_major_idle_slices_ += ___CAST(___F64, id);
          ps->mem.major_idle_slices_local_ = 0;
        }
      if (sp != 0)
        {
          vm->mem.concurrent_major_spin_slices_ += ___CAST(___F64, sp);
          ps->mem.major_spin_slices_local_ = 0;
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
      int new_static_count = 0;
      ___SIZE_TS skipped_static = 0;

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
              sec->major_static_gen = 0;
              sec->major_survive_count = 0;
              sec->static_major_dirty = 0;
              sec->major_hole_start = 0;
              sec->major_hole_end = 0;
              memset(sec->major_line_live, 0, sizeof(sec->major_line_live));
              memset(___CAST(void*, section_lxr_drc_bits(sec)), 0x55, SECTION_LXR_DRC_BYTES);
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
              if (sec->major_static_gen != 0)
                {
                  new_static_count++;
                  if (sec->major_mark_epoch != vm->mem.major_epoch_)
                    skipped_static++;
                }
              else
                {
                  if (sec->major_evacuate == 1)
                    evac_count++;
                  promo_cand_add(vm, sec);
                }
              new_mature_count++;
              new_mature_words += sec->mature_words;
              new_mat_tail = sec;
            }

          if (is_last)
            break;
          sec = nxt;
        }

      vm->mem.nb_msections_mature_ = new_mature_count;
      vm->mem.nb_msections_static_ = new_static_count;
      vm->mem.major_static_skipped_sections_ += ___CAST(___F64, skipped_static);
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

  major_fold_local_stats_stw(vm);
  lxr_drc_sync_vm_stats(vm);

  ___process_times(&u1, &s1, &r1);
  {
    ___F64 remark_sec = r1 - g->major_remark_r0;
    ___F64 conc_done = ___CAST(___F64, ___WORD_LOAD_ACQUIRE(&vm->mem.major_work_done_words_));
    ___F64 reclaimed_words =
      ___CAST(___F64, reclaimed_sections) * ___CAST(___F64, ___MSECTION_SIZE >> 1) +
      ___CAST(___F64, reclaimed_still_words);
    ___F64 gc_words = reclaimed_words + conc_done;
    ___F64 est_gc_sec = (remark_sec > 0.0 ? remark_sec : 0.0) + (conc_done / 4.0e7);
    if (gc_words < ___CAST(___F64, ___MSECTION_SIZE))
      gc_words = ___CAST(___F64, ___MSECTION_SIZE);
    if (est_gc_sec < 1.0e-5)
      est_gc_sec = 1.0e-5;
    gc_pacing_sample_mutator(vm);
    gc_pacing_on_major_gc(vm, gc_words, est_gc_sec);
  }
  gc_update_major_triggers(vm);

  vm->mem.nb_concurrent_major_cycles_ += 1.0;
  vm->mem.concurrent_major_reclaimed_sections_ += ___CAST(___F64, reclaimed_sections);
  vm->mem.concurrent_major_reclaimed_still_words_ += ___CAST(___F64, reclaimed_still_words);
  vm->mem.concurrent_major_remark_real_time_ += (r1 - g->major_remark_r0);
}

/* Portable Newton-Raphson double square root (zero libm dependency). */
static inline double gc_sqrt_f64(double x)
{
  double g;
  int i;
  if (x <= 0.0)
    return 0.0;
  g = (x >= 1.0) ? x * 0.5 : 1.0;
  for (i = 0; i < 24; i++)
    {
      double next = 0.5 * (g + x / g);
      if (next == g)
        break;
      g = next;
    }
  return g;
}

/* Sum VM-wide cumulative allocated bytes at an STW cut without mutator overhead. */
static inline ___F64 gc_vm_total_alloc_bytes_stw(___virtual_machine_state vm)
{
  int np = vm->processor_count;
  int p;
  ___F64 total = ___CAST(___F64, vm->mem.occupied_words_still_) * ___WS +
                 ___CAST(___F64, ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_));
  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      total += ps->mem.bytes_allocated_minus_occupied_;
      if (ps->mem.alloc_heap_ptr_ != 0 && ps->mem.alloc_heap_start_ != 0 &&
          ps->mem.alloc_heap_ptr_ > ps->mem.alloc_heap_start_)
        total += ___CAST(___F64, ps->mem.alloc_heap_ptr_ - ps->mem.alloc_heap_start_) * ___WS;
    }
  return total;
}

/* MemBalancer mutator allocation-rate EMA update (alpha_g = 0.95). */
___HIDDEN void gc_pacing_sample_mutator(___virtual_machine_state vm)
{
  ___F64 u1, s1, r1;
  ___F64 alloc_now, d_bytes, dt;
  if (vm == 0)
    return;
  ___process_times(&u1, &s1, &r1);
  alloc_now = gc_vm_total_alloc_bytes_stw(vm);
  if (vm->mem.pacing_last_real_time_ > 0.0 && r1 > vm->mem.pacing_last_real_time_)
    {
      dt = r1 - vm->mem.pacing_last_real_time_;
      d_bytes = alloc_now - vm->mem.pacing_last_alloc_bytes_;
      if (d_bytes > 0.0 && dt > 1.0e-6)
        {
          ___F64 d_words = d_bytes / ___CAST(___F64, ___WS);
          if (vm->mem.pacing_ema_alloc_sec_ <= 0.0)
            {
              vm->mem.pacing_ema_alloc_words_ = d_words;
              vm->mem.pacing_ema_alloc_sec_ = dt;
            }
          else
            {
              vm->mem.pacing_ema_alloc_words_ =
                0.95 * vm->mem.pacing_ema_alloc_words_ + 0.05 * d_words;
              vm->mem.pacing_ema_alloc_sec_ =
                0.95 * vm->mem.pacing_ema_alloc_sec_ + 0.05 * dt;
            }
        }
    }
  vm->mem.pacing_last_real_time_ = r1;
  vm->mem.pacing_last_alloc_bytes_ = alloc_now;
}

/* MemBalancer GC scan/reclaim-rate EMA update (alpha_s = 0.5). */
___HIDDEN void gc_pacing_on_major_gc
   (___virtual_machine_state vm,
    ___F64 collected_words,
    ___F64 gc_sec)
{
  if (vm == 0 || collected_words <= 0.0 || gc_sec <= 1.0e-7)
    return;
  if (vm->mem.pacing_ema_gc_sec_ <= 0.0)
    {
      vm->mem.pacing_ema_gc_words_ = collected_words;
      vm->mem.pacing_ema_gc_sec_ = gc_sec;
    }
  else
    {
      vm->mem.pacing_ema_gc_words_ =
        0.5 * vm->mem.pacing_ema_gc_words_ + 0.5 * collected_words;
      vm->mem.pacing_ema_gc_sec_ =
        0.5 * vm->mem.pacing_ema_gc_sec_ + 0.5 * gc_sec;
    }
}

/* MemBalancer sqrt(L * g / (c * s)) adaptive Major GC trigger pacing coupled
 * with hardware soft-budget damping and Racket-style external phantom bytes.
 * Honors explicit -:l<N> verbatim; otherwise adapts headroom sub-linearly
 * across live heap sizes while enforcing an E_min burst-OOM floor. */
___HIDDEN void gc_update_major_triggers(___virtual_machine_state vm)
{
  int mcnt = vm->mem.nb_msections_mature_;
  ___SIZE_TS mstill = vm->mem.mature_still_words_;
  ___WORD ph_live = ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_);
  ___SIZE_TS ph_words = (ph_live > 0) ? ___CAST(___SIZE_TS, ph_live >> ___LWS) : 0;
  ___SIZE_TS mature_live_words = vm->mem.occupied_words_mature_ + mstill + ph_words;
  int explicit_pct = ___live_percent_is_explicit();
  int cfg_pct = ___GSTATE->setup_params.live_percent;
  int eff_pct = gc_adaptive_live_percent
    (mature_live_words,
     explicit_pct,
     cfg_pct,
     ___GSTATE->setup_params.max_heap);
  int still_pct;
  int use_mb = (!explicit_pct && cfg_pct == ___DEFAULT_LIVE_PERCENT &&
                vm->mem.pacing_ema_gc_sec_ > 1.0e-6 &&
                vm->mem.pacing_ema_alloc_sec_ > 1.0e-6 &&
                mature_live_words > 0);
  double mb_extra_total = 0.0;
  ___SIZE_TS trig64;
  ___SIZE_TS still_trig;
  ___WORD min_ph = gc_phantom_min_trigger_bytes();
  ___WORD ph_trig;
  int trig;

  if (eff_pct < 10) eff_pct = 10;
  if (eff_pct > 90) eff_pct = 90;
  still_pct = (eff_pct > 67) ? eff_pct : 67;

  if (use_mb)
    {
      double g_rate = vm->mem.pacing_ema_alloc_words_ / vm->mem.pacing_ema_alloc_sec_;
      double s_rate = vm->mem.pacing_ema_gc_words_ / vm->mem.pacing_ema_gc_sec_;
      double c_scale = ___CAST(double, eff_pct) / 50.0;
      double c_eff = c_scale * c_scale;
      /* Dimensionally exact MemBalancer scale M_scale = 1/c_0 = 64 MiB (in words)
       * so sqrt(L * M_scale * g / (c_eff * s)) yields words directly:
       * sublinear O(sqrt(L)) headroom saving RSS on large heaps while avoiding
       * GC thrashing on fast-allocating small/medium heaps. */
      double scale_words =
        ___CAST(double, (___CAST(___SIZE_T, 64) * 1024 * 1024) >> ___LWS);
      if (s_rate < 1.0e4)
        s_rate = 1.0e4;
      if (c_eff < 1.0)
        c_eff = 1.0;
      mb_extra_total = gc_sqrt_f64((___CAST(double, mature_live_words) * scale_words * g_rate) /
                                   (c_eff * s_rate));
    }

  if (mcnt <= 0)
    trig = 8;
  else
    {
      ___SIZE_TS lin_trig = (___CAST(___SIZE_TS, mcnt) * 100 + (eff_pct - 1)) / eff_pct;
      ___SIZE_TS lin_extra = (lin_trig > ___CAST(___SIZE_TS, mcnt))
                               ? (lin_trig - ___CAST(___SIZE_TS, mcnt))
                               : 8;
      if (lin_extra < 8)
        lin_extra = 8;
      if (use_mb)
        {
          double mov_share =
            ___CAST(double, vm->mem.occupied_words_mature_) /
            ___CAST(double, mature_live_words);
          double mov_extra_words = mb_extra_total * (mov_share > 0.1 ? mov_share : 0.1);
          ___SIZE_TS mb_secs =
            ___CAST(___SIZE_TS, mov_extra_words / ___CAST(double, ___MSECTION_SIZE >> 1)) + 1;
          ___SIZE_TS max_extra = (___GSTATE->setup_params.max_heap > 0)
                                   ? lin_extra
                                   : ((lin_extra * 3) >> 1);
          if (max_extra < 8)
            max_extra = 8;
          if (mb_secs < 8)
            mb_secs = 8;
          if (mb_secs > max_extra)
            mb_secs = max_extra;
          trig64 = ___CAST(___SIZE_TS, mcnt) + mb_secs;
        }
      else
        {
          trig64 = ___CAST(___SIZE_TS, mcnt) + lin_extra;
        }
      if (trig64 < ___CAST(___SIZE_TS, mcnt) + 8)
        trig64 = ___CAST(___SIZE_TS, mcnt) + 8;
      trig = (trig64 > 1000000000) ? 1000000000 : ___CAST(int, trig64);
    }

  if (mstill <= 0)
    still_trig = 2 * ___MSECTION_SIZE;
  else
    {
      ___SIZE_TS lin_still =
        (mstill / still_pct) * 100 +
        (((mstill % still_pct) * 100 + (still_pct - 1)) / still_pct);
      ___SIZE_TS lin_still_extra = (lin_still > mstill) ? (lin_still - mstill) : (2 * ___MSECTION_SIZE);
      if (lin_still_extra < 2 * ___MSECTION_SIZE)
        lin_still_extra = 2 * ___MSECTION_SIZE;
      if (use_mb)
        {
          double st_share = ___CAST(double, mstill) / ___CAST(double, mature_live_words);
          ___SIZE_TS mb_still = ___CAST(___SIZE_TS, mb_extra_total * (st_share > 0.1 ? st_share : 0.1));
          ___SIZE_TS max_still = (___GSTATE->setup_params.max_heap > 0)
                                   ? lin_still_extra
                                   : ((lin_still_extra * 3) >> 1);
          if (max_still < 2 * ___MSECTION_SIZE)
            max_still = 2 * ___MSECTION_SIZE;
          if (mb_still < 2 * ___MSECTION_SIZE)
            mb_still = 2 * ___MSECTION_SIZE;
          if (mb_still > max_still)
            mb_still = max_still;
          still_trig = mstill + mb_still;
        }
      else
        {
          still_trig = mstill + lin_still_extra;
        }
      if (still_trig < 2 * ___MSECTION_SIZE)
        still_trig = 2 * ___MSECTION_SIZE;
    }

  if (ph_live <= 0)
    ph_trig = min_ph;
  else
    {
      ___WORD lin_ph_extra = (ph_live * ___CAST(___WORD, 100 - still_pct)) / still_pct;
      ___WORD ph_extra = (lin_ph_extra > min_ph) ? lin_ph_extra : min_ph;
      if (use_mb)
        {
          double ph_share = ___CAST(double, ph_words) / ___CAST(double, mature_live_words);
          double mb_ph_bytes = mb_extra_total * (ph_share > 0.1 ? ph_share : 0.1) * ___CAST(double, ___WS);
          ___WORD mb_ph = ___CAST(___WORD, mb_ph_bytes);
          if (mb_ph < min_ph)
            mb_ph = min_ph;
          if (mb_ph < ph_extra)
            ph_extra = mb_ph;
        }
      if (ph_extra > ___CAST(___WORD, 256) * 1024 * 1024)
        ph_extra = ___CAST(___WORD, 256) * 1024 * 1024;
      if (___GSTATE->setup_params.max_heap > 0)
        {
          ___WORD cap_ph = ___CAST(___WORD, ___GSTATE->setup_params.max_heap >> 1);
          if (cap_ph < min_ph)
            cap_ph = min_ph;
          if (ph_extra > cap_ph)
            ph_extra = cap_ph;
        }
      ph_trig = ph_live + ph_extra;
    }

  vm->mem.major_trigger_sections_ = trig;
  vm->mem.major_trigger_still_words_ = still_trig;
  ___WORD_STORE_RELEASE(&vm->mem.major_trigger_phantom_bytes_, ph_trig);
  ___WORD_STORE_RELEASE(&vm->mem.phantom_gc_needed_, 0);
  vm->mem.minor_gcs_since_major_ = 0;
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
  ___WORD_STORE_RELEASE(&vm->mem.major_alloc_words_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.major_work_done_words_, 0);
  ___WORD_STORE_RELEASE(&vm->mem.phantom_gc_needed_, 0);
  vm->mem.major_weak_tables_count_ = 0;
  vm->mem.major_still_bases_count_ = 0;
  vm->mem.major_still_lo_ = 0;
  vm->mem.major_still_span_ = 0;
  vm->mem.major_evacuate_count_ = 0;
  if (vm->mem.the_msections_ != 0)
    {
      ___msection *sec;
      for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
        {
          sec->major_static_gen = 0;
          sec->major_survive_count = 0;
          sec->static_major_dirty = 0;
        }
    }
  vm->mem.nb_msections_static_ = 0;

  major_fold_local_stats_stw(vm);

  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___WORD_STORE_RELEASE(&ps->mem.satb_active_, 0);
      ps->mem.stack_watermark_epoch_ = 0;
      ps->mem.satb_count_ = 0;
      ps->mem.satb_overflow_ = 0;
      ps->mem.major_mark_local_count_ = 0;
    }
}

/* Public adaptive pacing, phantom-byte, and off-heap RefC binary telemetry
 * (12 doubles: phantom_live, phantom_peak, phantom_trigger, major_trig_secs,
 *  major_trig_still, headroom_words, work_target_words, completed_in_time,
 *  emergency_remarks, refc_created, refc_shared, refc_freed). */
___EXP_FUNC(void,___gc_pacing_stats)
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
  out_stats[0]  = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_live_));
  out_stats[1]  = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.phantom_bytes_peak_));
  out_stats[2]  = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.major_trigger_phantom_bytes_));
  out_stats[3]  = ___CAST(double, vm->mem.major_trigger_sections_);
  out_stats[4]  = ___CAST(double, vm->mem.major_trigger_still_words_);
  out_stats[5]  = ___CAST(double, vm->mem.pacing_headroom_words_);
  out_stats[6]  = ___CAST(double, vm->mem.pacing_work_target_words_);
  out_stats[7]  = vm->mem.pacing_completed_in_time_;
  out_stats[8]  = vm->mem.pacing_emergency_remarks_;
  out_stats[9]  = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.refc_bins_created_));
  out_stats[10] = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.refc_bins_shared_));
  out_stats[11] = ___CAST(double, ___WORD_LOAD_ACQUIRE(&vm->mem.refc_bins_freed_));
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
  double add_slices = 0.0;
  double add_words = 0.0;
  double add_satb = 0.0;
  int np, p;
  if (___ps == 0 || out_stats == 0)
    return;
  vm = ___VMSTATE_FROM_PSTATE(___ps);
  np = vm->processor_count;
  for (p = 0; p < np; p++)
    {
      ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      add_slices += ___CAST(double, ___WORD_LOAD_ACQUIRE(&pps->mem.major_mark_slices_local_));
      add_words  += ___CAST(double, ___WORD_LOAD_ACQUIRE(&pps->mem.major_marked_words_local_));
      add_satb   += ___CAST(double, ___WORD_LOAD_ACQUIRE(&pps->mem.major_satb_logged_local_));
    }
  major_mark_lock(vm);
  out_stats[0] = vm->mem.nb_concurrent_major_cycles_;
  out_stats[1] = vm->mem.concurrent_major_mark_slices_ + add_slices;
  out_stats[2] = vm->mem.concurrent_major_marked_words_ + add_words;
  out_stats[3] = vm->mem.concurrent_major_reclaimed_sections_;
  out_stats[4] = vm->mem.concurrent_major_reclaimed_still_words_;
  out_stats[5] = vm->mem.concurrent_major_remark_real_time_;
  out_stats[6] = vm->mem.concurrent_major_satb_logged_ + add_satb;
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
