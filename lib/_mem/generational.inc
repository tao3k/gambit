/* Bounded Generational Minor GC, Lock-Free Card Write Barrier, and Mature
 * Section Lifecycle. Mutator write barriers are strictly non-allocating and
 * non-collecting; mature_sections_ is mutated exclusively during STW GC. */

#ifndef ___GENERATIONAL_INC
#define ___GENERATIONAL_INC

static inline ___msection *wb_find_mature_section
   (___processor_state ___ps,
    ___virtual_machine_state vm,
    ___UWORD addr)
{
  int nm = vm->mem.nb_msections_mature_;
  ___UWORD half_bytes = ___CAST(___UWORD, ___MSECTION_SIZE >> 1) * ___WS;
  ___msection *sec = 0;

  if (nm <= 0)
    return 0;
  if (addr - vm->mem.mature_addr_lo_ >= vm->mem.mature_addr_span_)
    return 0;

  if (___ps->mem.wb_last_sec_ != 0 &&
      ___ps->mem.wb_last_epoch_ == vm->mem.mature_snapshot_epoch_)
    {
      ___msection *cand = ___ps->mem.wb_last_sec_;
      if (addr - ___CAST(___UWORD, cand->base + cand->active_offset) < half_bytes)
        return cand;
    }

  {
    ___msection **arr = vm->mem.mature_sections_;
    int lo = 0;
    int hi = nm - 1;
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
      {
        ___ps->mem.wb_last_sec_ = sec;
        ___ps->mem.wb_last_epoch_ = vm->mem.mature_snapshot_epoch_;
        return sec;
      }
  }
  return 0;
}

___EXP_FUNC(void,___gc_write_barrier_slow)
   ___P((___processor_state ___ps,
         ___SCMOBJ obj,
         ___WORD *slot_ptr),
        (___ps,
         obj,
         slot_ptr)
___processor_state ___ps;
___SCMOBJ obj;
___WORD *slot_ptr;)
{
  ___virtual_machine_state vm;
  ___WORD head;
  int htyp;

  if (___ps == 0 || !___MEM_ALLOCATED(obj) || slot_ptr == 0)
    return;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  head = ___HEADER(obj);
  htyp = ___HD_TYP(head);

  if (htyp == ___STILL)
    {
#ifndef ___USE_HANDLES
      ___WORD *base = ___BODY0(obj) - ___STILL_BODY;
      ___WORD flags = ___WORD_LOAD_RELAXED(&base[___STILL_DIRTY]);
      if ((flags & (___STILL_FLAG_YOUNG | ___STILL_FLAG_DIRTY)) == 0)
        {
          ___WORD_FETCH_OR_RELEASE(&base[___STILL_DIRTY], ___STILL_FLAG_DIRTY);
          ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 1);
        }
      /* Cache strictly interior 512B card of this already-dirty/young still
       * object so sequential mutations to large still vectors/tables elide
       * redundant slow-barrier calls (SATB check still runs before this cache). */
      {
        ___UWORD card_bytes = ___CAST(___UWORD, ___GC_CARD_WORDS) * ___WS;
        ___UWORD card_lo = ___CAST(___UWORD, slot_ptr) & ~(card_bytes - 1);
        ___UWORD body_lo = ___CAST(___UWORD, ___BODY0(obj));
        ___UWORD body_hi = body_lo + ___CAST(___UWORD, ___HD_WORDS(head)) * ___WS;
        if (card_lo >= body_lo && card_lo < body_hi && body_hi - card_lo >= card_bytes)
          ___ps->mem.wb_last_card_lo_ = card_lo;
      }
#endif
      return;
    }

  if (htyp != ___MOVABLE0)
    return;

  {
    ___UWORD addr = ___CAST(___UWORD, slot_ptr);
    ___msection *sec = wb_find_mature_section(___ps, vm, addr);
    if (sec != 0)
      {
        ___SIZE_TS word_off =
          ___CAST(___SIZE_TS, (addr - ___CAST(___UWORD, sec->base)) / ___WS);
        ___SIZE_TS card_word_base =
          (word_off >> ___GC_CARD_SHIFT_WORDS) << ___GC_CARD_SHIFT_WORDS;
        ___gc_card_mark_in_section(sec, section_card_bits(sec), word_off,
                                   ___MSECTION_SIZE, &___ps->mem.card_hints_);
        ___ps->mem.wb_last_card_lo_ = ___CAST(___UWORD, sec->base + card_word_base);
      }
  }
}

/* Cross-processor-safe card barrier for C runtime writes where the caller's
 * processor_state is not passed (e.g. ___raise_high_level_interrupt_pstate).
 * Marks the mature card/still dirty flag atomically without touching any
 * remote processor's per-processor hint log or SATB buffer. */
void ___gc_write_barrier_slot_vm
   ___P((___virtual_machine_state vm,
         ___SCMOBJ obj,
         ___WORD *slot_ptr),
        (vm,
         obj,
         slot_ptr)
___virtual_machine_state vm;
___SCMOBJ obj;
___WORD *slot_ptr;)
{
  ___WORD head;
  int htyp;

  if (vm == 0 || !___MEM_ALLOCATED(obj) || slot_ptr == 0)
    return;

  head = ___HEADER(obj);
  htyp = ___HD_TYP(head);

  if (htyp == ___STILL)
    {
#ifndef ___USE_HANDLES
      ___WORD *base = ___BODY0(obj) - ___STILL_BODY;
      ___WORD flags = ___WORD_LOAD_RELAXED(&base[___STILL_DIRTY]);
      if ((flags & (___STILL_FLAG_YOUNG | ___STILL_FLAG_DIRTY)) == 0)
        {
          ___WORD_FETCH_OR_RELEASE(&base[___STILL_DIRTY], ___STILL_FLAG_DIRTY);
          ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 1);
        }
#endif
      return;
    }

  if (htyp != ___MOVABLE0)
    return;

  {
    int nm = vm->mem.nb_msections_mature_;
    ___UWORD addr = ___CAST(___UWORD, slot_ptr);
    if (nm > 0 && addr - vm->mem.mature_addr_lo_ < vm->mem.mature_addr_span_)
      {
        ___msection **arr = vm->mem.mature_sections_;
        ___UWORD half_bytes = ___CAST(___UWORD, ___MSECTION_SIZE >> 1) * ___WS;
        int lo = 0, hi = nm - 1;
        ___msection *sec;
        while (lo < hi)
          {
            int mid = lo + ((hi - lo + 1) >> 1);
            if (___CAST(___UWORD, arr[mid]->base) <= addr)
              lo = mid;
            else
              hi = mid - 1;
          }
        sec = arr[lo];
        if (addr - ___CAST(___UWORD, sec->base + sec->active_offset) < half_bytes)
          {
            ___SIZE_TS word_off =
              ___CAST(___SIZE_TS, (addr - ___CAST(___UWORD, sec->base)) / ___WS);
            ___gc_card_mark_in_section(sec, section_card_bits(sec), word_off,
                                       ___MSECTION_SIZE, 0);
            ___WORD_STORE_RELEASE(&vm->mem.card_overflow_any_, 1);
          }
      }
  }
}

___EXP_FUNC(void,___gc_write_barrier_range)
   ___P((___processor_state ___ps,
         ___SCMOBJ obj,
         ___WORD *start_ptr,
         ___SIZE_TS words),
        (___ps,
         obj,
         start_ptr,
         words)
___processor_state ___ps;
___SCMOBJ obj;
___WORD *start_ptr;
___SIZE_TS words;)
{
  ___virtual_machine_state vm;
  ___WORD head;
  int htyp;

  if (___ps == 0 || !___MEM_ALLOCATED(obj) || start_ptr == 0 || words <= 0)
    return;

  vm = ___VMSTATE_FROM_PSTATE(___ps);
  head = ___HEADER(obj);
  htyp = ___HD_TYP(head);

  if (htyp == ___STILL)
    {
#ifndef ___USE_HANDLES
      ___WORD *base = ___BODY0(obj) - ___STILL_BODY;
      ___WORD flags = ___WORD_LOAD_RELAXED(&base[___STILL_DIRTY]);
      if ((flags & (___STILL_FLAG_YOUNG | ___STILL_FLAG_DIRTY)) == 0)
        {
          ___WORD_FETCH_OR_RELEASE(&base[___STILL_DIRTY], ___STILL_FLAG_DIRTY);
          ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 1);
        }
#endif
      return;
    }

  if (htyp != ___MOVABLE0)
    return;

  {
    ___UWORD addr = ___CAST(___UWORD, start_ptr);
    ___msection *sec = wb_find_mature_section(___ps, vm, addr);
    if (sec != 0)
      {
        ___SIZE_TS first_off =
          ___CAST(___SIZE_TS, (addr - ___CAST(___UWORD, sec->base)) / ___WS);
        ___SIZE_TS last_off = first_off + words - 1;
        ___SIZE_TS half_end = sec->active_offset + (___MSECTION_SIZE >> 1) - 1;
        ___SIZE_TS cur;
        if (last_off > half_end)
          last_off = half_end;
        cur = first_off;
        for (;;)
          {
            ___gc_card_mark_in_section(sec, section_card_bits(sec), cur,
                                       ___MSECTION_SIZE, &___ps->mem.card_hints_);
            if ((cur >> ___GC_CARD_SHIFT_WORDS) >= (last_off >> ___GC_CARD_SHIFT_WORDS))
              break;
            cur = ((cur >> ___GC_CARD_SHIFT_WORDS) + 1) << ___GC_CARD_SHIFT_WORDS;
          }
      }
  }
}

___EXP_FUNC(void,___gc_generational_stats)
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
  out_stats[0] = vm->mem.nb_minor_gcs_;
  out_stats[1] = vm->mem.nb_major_gcs_;
  out_stats[2] = vm->mem.minor_gc_real_time_;
  out_stats[3] = vm->mem.major_gc_real_time_;
  out_stats[4] = ___CAST(double, vm->mem.nb_msections_mature_);
  out_stats[5] = ___CAST(double, vm->mem.minor_promoted_words_);
  out_stats[6] = ___CAST(double, vm->mem.minor_dirty_cards_scanned_);
  out_stats[7] = ___CAST(double, vm->mem.minor_overflow_fallbacks_);
}

___EXP_FUNC(int,___gc_set_generational_enabled)
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
  prev = vm->mem.gen_gc_enabled_;
  if (enabled >= 0)
    vm->mem.gen_gc_enabled_ = enabled ? 1 : 0;
  return prev;
}

/* Round-aware unmarked predicate for wills and weak GC hash tables.
 * In Minor GC, still objects and mature movable objects are conservatively
 * treated as live; only unforwarded young movable objects are unmarked. */
static inline int gc_obj_unmarked(___collector_worker *work, ___SCMOBJ obj)
{
  ___WORD *body = ___BODY0(obj);
  ___WORD head = body[-1];
  int typ = ___HD_TYP(head);
  if (___COLLECTION(work->vm).is_minor)
    {
      if (typ == ___STILL)
        {
#ifndef ___USE_HANDLES
          ___WORD *base = body - ___STILL_BODY;
          if ((base[___STILL_DIRTY] & ___STILL_FLAG_YOUNG) != 0 &&
              base[___STILL_MARK] == -1)
            return 1;
#endif
          return 0;
        }
      if (typ != ___MOVABLE0)
        return 0;
      {
        ___processor_state ___ps = work->carrier;
        ___WORD *header = body - 1;
        ___msection *sec = ___gc_find_msection_cached(work, the_msections, header);
        if (sec == 0)
          return 0;
        if (sec->region_age == ___GC_REGION_MATURE && !sec->gc_evacuating)
          return 0;
        if (sec->gc_is_dest &&
            ___CAST(___UWORD, header) - ___CAST(___UWORD, sec->base + sec->gc_dest_offset)
              < (___MSECTION_SIZE >> 1) * ___WS)
          return 0;
        return 1;
      }
    }
  if (typ == ___MOVABLE0)
    return 1;
  if (typ == ___STILL && body[___STILL_MARK - ___STILL_BODY] == -1)
    return 1;
  return 0;
}

/* Sort collected hints by (section pointer, card_index) for ascending scan and
 * deduplication of multi-card mature objects. Total hints <= MAX_PROCS * 64. */
___HIDDEN void sort_card_hints(___gc_card_hint *arr, int n)
{
  int i, j;
  for (i = 1; i < n; i++)
    {
      ___gc_card_hint key = arr[i];
      ___UWORD ks = ___CAST(___UWORD, key.section);
      j = i - 1;
      while (j >= 0)
        {
          ___UWORD js = ___CAST(___UWORD, arr[j].section);
          if (js > ks || (js == ks && arr[j].card_index > key.card_index))
            {
              arr[j + 1] = arr[j];
              j--;
            }
          else
            break;
        }
      arr[j + 1] = key;
    }
}

___HIDDEN void collect_minor_card_hints(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  int np = g->participant_count;
  int p, count = 0, overflow = 0;

  if (___WORD_LOAD_ACQUIRE(&vm->mem.card_overflow_any_) != 0)
    {
      overflow = 1;
      ___WORD_STORE_RELEASE(&vm->mem.card_overflow_any_, 0);
    }

  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ___gc_card_hint_log *log = &ps->mem.card_hints_;
      if (log->overflow)
        overflow = 1;
      if (!overflow)
        {
          unsigned int i;
          for (i = 0; i < log->count; i++)
            {
              ___gc_card_hint h = log->entries[i];
              if (h.section != 0 &&
                  h.section->region_age == ___GC_REGION_MATURE &&
                  h.section->region_generation == h.region_generation)
                {
                  if (count < ___MAX_PROCESSORS * ___GC_CARD_HINT_CAPACITY)
                    g->hints[count++] = h;
                  else
                    {
                      overflow = 1;
                      break;
                    }
                }
            }
        }
    }

  g->card_overflow = overflow;
  if (!overflow && count > 1)
    {
      int out = 0, i;
      sort_card_hints(g->hints, count);
      for (i = 0; i < count; i++)
        {
          if (out == 0 ||
              g->hints[i].section != g->hints[out - 1].section ||
              g->hints[i].card_index != g->hints[out - 1].card_index)
            g->hints[out++] = g->hints[i];
        }
      count = out;
    }
  g->hint_count = overflow ? 0 : count;
}

___HIDDEN int section_has_promo_room(___msection *sec, ___SIZE_TS *start_w_out)
{
  ___SIZE_TS start_w = (sec->mature_words + ___GC_CARD_WORDS - 1) &
                       ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
  if (start_w + ___MSECTION_FUDGE + 256 < (___MSECTION_SIZE >> 1))
    {
      if (start_w_out != 0)
        *start_w_out = start_w;
      return 1;
    }
  return 0;
}

___HIDDEN ___SIZE_TS section_best_promo_span
   (___msection *sec,
    int allow_hole,
    ___SIZE_TS *start_w_out,
    ___SIZE_TS *end_w_out,
    int *is_hole_out)
{
  ___SIZE_TS tail_start = 0, tail_room = 0;
  ___SIZE_TS hole_room = 0;
  if (section_has_promo_room(sec, &tail_start))
    tail_room = (___MSECTION_SIZE >> 1) - tail_start;
  if (allow_hole &&
      sec->major_hole_end > sec->major_hole_start &&
      (sec->major_hole_end - sec->major_hole_start) >= 512)
    hole_room = sec->major_hole_end - sec->major_hole_start;

  /* Prefer Immix hole recycling whenever a substantial dead hole exists
   * (>= 1024 words or larger than tail room) to keep mature RSS tightly bounded. */
  if (hole_room > 0 && (hole_room >= 1024 || hole_room >= tail_room))
    {
      if (start_w_out != 0) *start_w_out = sec->major_hole_start;
      if (end_w_out != 0) *end_w_out = sec->major_hole_end;
      if (is_hole_out != 0) *is_hole_out = 1;
      return hole_room;
    }
  if (tail_room > 0)
    {
      if (start_w_out != 0) *start_w_out = tail_start;
      if (end_w_out != 0) *end_w_out = (___MSECTION_SIZE >> 1);
      if (is_hole_out != 0) *is_hole_out = 0;
      return tail_room;
    }
  return 0;
}

___HIDDEN void promo_cand_add(___virtual_machine_state vm, ___msection *sec)
{
  int cap = ___MAX_PROCESSORS * 2;
  int i;
  ___SIZE_TS room;
  if (sec == 0 || sec->region_age != ___GC_REGION_MATURE)
    return;
  room = section_best_promo_span(sec, 1, 0, 0, 0);
  if (room == 0)
    return;
  for (i = 0; i < vm->mem.promo_cand_count_; i++)
    if (vm->mem.promo_cands_[i] == sec)
      return;
  if (vm->mem.promo_cand_count_ < cap)
    {
      vm->mem.promo_cands_[vm->mem.promo_cand_count_++] = sec;
      return;
    }
  {
    int worst = 0;
    ___SIZE_TS worst_room = section_best_promo_span(vm->mem.promo_cands_[0], 1, 0, 0, 0);
    for (i = 1; i < cap; i++)
      {
        ___SIZE_TS r = section_best_promo_span(vm->mem.promo_cands_[i], 1, 0, 0, 0);
        if (r < worst_room)
          {
            worst = i;
            worst_room = r;
          }
      }
    if (room > worst_room)
      vm->mem.promo_cands_[worst] = sec;
  }
}

___HIDDEN void prepare_generational_round
   (___processor_state ps,
    ___SIZE_TS requested_words_still)
{
  ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(ps);
  ___gc_round *g = &___COLLECTION(vm);
  ___msection *sec;
  ___SIZE_TS young_src_off = ps->mem.tospace_offset_;
  ___WORD force_major = ___WORD_LOAD_ACQUIRE(&vm->mem.force_major_gc_);
  int np = g->participant_count;
  int p;
  int can_gen = 1;

  ___WORD_STORE_RELEASE(&vm->mem.force_major_gc_, 0);

#if defined(___DISABLE_GENERATIONAL_GC) || defined(___GAMBIT_DEV_RESTORE_PROBE) || \
    defined(___GC_SLOT_TEST_FROZEN) || defined(___GC_COPY_CONTROL_ACTIVE) || \
    defined(___CALL_GC_FREQUENTLY) || defined(CALL_GC_FREQUENTLY)
  can_gen = 0;
#endif
  if (vm->mem.custom_msection_alloc_ != 0)
    can_gen = 0;
  if (___GSTATE->setup_params.max_heap > 0)
    {
      ___SIZE_TS cap_secs =
        (___GSTATE->setup_params.max_heap >> ___LWS) / ___MSECTION_SIZE;
      if (cap_secs < ___CAST(___SIZE_TS, 2 * np + 10))
        can_gen = 0;
    }

  /* Keep mature segregation active whenever generational GC is enabled or
   * mature sections with independent active_offset already exist. */
  g->segregate_mature = (can_gen && (vm->mem.gen_gc_enabled_ || vm->mem.nb_msections_mature_ > 0)) ? 1 : 0;
  if (!vm->mem.gen_gc_enabled_)
    can_gen = 0;
  g->is_minor = 0;
  g->evac_selective = 0;
  g->major_action = 0;
  vm->mem.major_last_reclaimed_sections_ = 0;
  g->has_wills = 0;
  g->has_young_still = 0;
  g->card_overflow = 0;
  g->hint_count = 0;
  g->promo_tail_count = 0;
  g->old_mature_tail = vm->mem.mature_tail_;
  g->young_head = g->old_mature_tail ? g->old_mature_tail->next : vm->mem.the_msections_->head;
  for (p = 0; p < np; p++)
    {
      ___processor_state pps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      if (___UNTAG(pps->mem.nonexecutable_wills_) != 0 ||
          ___UNTAG(pps->mem.executable_wills_) != 0)
        g->has_wills = 1;
      if (pps->mem.young_still_objs_ != 0)
        g->has_young_still = 1;
    }
  {
    int i;
    for (i = 0; i < ___MAX_PROCESSORS; i++)
      {
        g->young_heap_secs[i] = 0;
        g->promo_tails[i] = 0;
        g->promo_tail_starts[i] = 0;
        g->promo_tail_ends[i] = 0;
        g->promo_tail_is_hole[i] = 0;
      }
  }

  if (can_gen &&
      force_major == 0 &&
      (requested_words_still == 0 ||
       (___GSTATE->setup_params.max_heap == 0 && g->has_young_still)) &&
      g->worker_count >= 1 &&
      np == vm->processor_count)
    {
      int ok = 1;
      ___WORD phase = ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_);
      ___WORD req_start = ___WORD_LOAD_ACQUIRE(&vm->mem.major_request_start_);
      int major_due = (vm->mem.nb_msections_mature_ >= vm->mem.major_trigger_sections_ ||
                       vm->mem.mature_still_words_ >= vm->mem.major_trigger_still_words_ ||
                       vm->mem.minor_gcs_since_major_ >= 64);
      int need_compact = (vm->mem.major_evacuate_count_ >= 4 &&
                          vm->mem.major_evacuate_count_ * 3 >= vm->mem.nb_msections_mature_);

      if (___GSTATE->setup_params.max_heap > 0)
        {
          ___SIZE_TS cap_secs =
            (___GSTATE->setup_params.max_heap >> ___LWS) / ___MSECTION_SIZE;
          if (___CAST(___SIZE_TS, vm->mem.nb_msections_mature_ + 2 * np + 2) > cap_secs)
            ok = 0;
        }

      if (ok && phase == ___GC_MAJOR_MARKING)
        {
          g->is_minor = 1;
          if (!major_has_pending_mark_work(vm) ||
              req_start == 2 ||
              vm->mem.minor_gcs_since_major_ >= 8 ||
              vm->mem.nb_msections_mature_ >= vm->mem.major_trigger_sections_ * 2 ||
              vm->mem.mature_still_words_ >= vm->mem.major_trigger_still_words_ * 2)
            g->major_action = 3; /* ___GC_MAJOR_ACTION_REMARK */
          else
            g->major_action = 2; /* ___GC_MAJOR_ACTION_DRAIN_SATB */
        }
      else if (ok && phase == ___GC_MAJOR_IDLE)
        {
          if (major_due || req_start != 0)
            {
              if (vm->mem.concurrent_major_enabled_ != 0 &&
                  !need_compact &&
                  (vm->mem.nb_msections_mature_ > 0 || vm->mem.mature_still_words_ > 0))
                {
                  g->is_minor = 1;
                  g->major_action = 1; /* ___GC_MAJOR_ACTION_START */
                }
            }
          else if (vm->mem.major_evacuate_count_ >= 2 &&
                   vm->mem.nb_msections_mature_ > vm->mem.major_evacuate_count_)
            {
              /* Slice 2 v3 Selective Immix Evacuation: defragment sparse (<50% live)
               * mature sections without waiting for 2x heap growth or copying dense
               * mature sections. Runs strictly when major_phase_ == IDLE. */
              g->is_minor = 1;
              g->evac_selective = 1;
            }
          else if (vm->mem.nb_msections_mature_ > 0)
            {
              g->is_minor = 1;
            }
        }
    }

  if (!g->is_minor && ___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE)
    g->major_action = 4; /* ___GC_MAJOR_ACTION_ABORT */

  if (g->is_minor)
    {
      /* Mature sections maintain gc_dest_*==0, gc_role==0, gc_src_offset==active_offset,
       * and scan_end_words==mature_words across Minor GCs. Walk ONLY young sections O(Y),
       * plus bounded sparse mature selection when g->evac_selective != 0. */
      int max_tails = g->worker_count;
      int allow_hole = (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) == ___GC_MAJOR_IDLE &&
                        g->major_action != 1 &&
                        !g->evac_selective);
      int ci;
      if (g->evac_selective && g->old_mature_tail != 0)
        {
          int budget = vm->mem.nb_msections_mature_ >> 2;
          int picked = 0;
          if (budget < 8) budget = 8;
          if (budget > 64) budget = 64;
          for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
            {
              sec->gc_evacuating = 0;
              if (sec->region_age == ___GC_REGION_MATURE &&
                  sec->major_evacuate == 1 &&
                  picked < budget)
                {
                  sec->gc_evacuating = 1;
                  sec->gc_src_offset = sec->active_offset;
                  sec->scan_end_words = sec->mature_words;
                  picked++;
                }
              if (sec == g->old_mature_tail)
                break;
            }
          if (picked == 0)
            g->evac_selective = 0;
        }
      for (sec = g->young_head; sec != 0; sec = sec->next)
        {
          sec->gc_dest_offset = 0;
          sec->gc_dest_words = 0;
          sec->gc_is_dest = 0;
          sec->gc_role = 0;
          sec->gc_evacuating = 0;
          sec->gc_src_offset = young_src_off;
          sec->scan_end_words = 0;
        }

      collect_minor_card_hints(vm);

      /* Select up to worker_count roomiest mature promotion tails or IDLE Immix
       * dead-line holes from the O(W) candidate cache (strictly excluding any
       * section currently selected for selective evacuation). */
      for (ci = 0; ci < vm->mem.promo_cand_count_; ci++)
        {
          ___SIZE_TS start_w = 0, end_w = 0, room;
          int is_hole = 0;
          sec = vm->mem.promo_cands_[ci];
          if (sec == 0 || sec->region_age != ___GC_REGION_MATURE || sec->gc_evacuating)
            continue;
          room = section_best_promo_span(sec, allow_hole, &start_w, &end_w, &is_hole);
          if (room == 0)
            continue;
          if (g->promo_tail_count < max_tails)
            {
              int idx = g->promo_tail_count++;
              g->promo_tails[idx] = sec;
              g->promo_tail_starts[idx] = start_w;
              g->promo_tail_ends[idx] = end_w;
              g->promo_tail_is_hole[idx] = ___CAST(unsigned char, is_hole);
            }
          else
            {
              int worst = 0, j;
              ___SIZE_TS worst_room = g->promo_tail_ends[0] - g->promo_tail_starts[0];
              for (j = 1; j < max_tails; j++)
                {
                  ___SIZE_TS r = g->promo_tail_ends[j] - g->promo_tail_starts[j];
                  if (r < worst_room)
                    {
                      worst = j;
                      worst_room = r;
                    }
                }
              if (room > worst_room)
                {
                  g->promo_tails[worst] = sec;
                  g->promo_tail_starts[worst] = start_w;
                  g->promo_tail_ends[worst] = end_w;
                  g->promo_tail_is_hole[worst] = ___CAST(unsigned char, is_hole);
                }
            }
        }
    }
  else
    {
      for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
        {
          sec->gc_dest_offset = 0;
          sec->gc_dest_words = 0;
          sec->gc_is_dest = 0;
          sec->gc_role = 0;
          sec->gc_evacuating = 0;
          if (sec->region_age == ___GC_REGION_MATURE)
            {
              sec->gc_src_offset = sec->active_offset;
              sec->scan_end_words = sec->mature_words;
            }
          else
            {
              sec->gc_src_offset = young_src_off;
              sec->scan_end_words = 0;
            }
        }
    }
}

___HIDDEN void downgrade_minor_to_major(___processor_state ps)
{
  ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(ps);
  ___gc_round *g = &___COLLECTION(vm);
  ___SIZE_TS young_src_off = ps->mem.tospace_offset_;
  ___msection *sec;
  g->is_minor = 0;
  g->evac_selective = 0;
  g->major_action = (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE) ? 4 : 0;
  g->card_overflow = 0;
  g->hint_count = 0;
  g->promo_tail_count = 0;
  for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
    {
      sec->gc_dest_offset = 0;
      sec->gc_dest_words = 0;
      sec->gc_is_dest = 0;
      sec->gc_role = 0;
      sec->gc_evacuating = 0;
      if (sec->region_age == ___GC_REGION_MATURE)
        {
          sec->gc_src_offset = sec->active_offset;
          sec->scan_end_words = sec->mature_words;
        }
      else
        {
          sec->gc_src_offset = young_src_off;
          sec->scan_end_words = 0;
        }
    }
}

___HIDDEN void scan_mature_object(___collector_worker *work, ___WORD *body, ___WORD head);

___HIDDEN void scan_mature_card_list
   (___collector_worker *work,
    ___msection *sec,
    const unsigned int *cards,
    int ncards)
{
  ___WORD *base = sec->base + sec->active_offset;
  ___WORD *scan_end = base + sec->scan_end_words;
  unsigned int half_card_base =
    ___CAST(unsigned int, sec->active_offset >> ___GC_CARD_SHIFT_WORDS);
  unsigned char *starts = section_card_starts(sec);
  ___WORD *last_scanned_end = 0;
  int idx;

  for (idx = 0; idx < ncards; idx++)
    {
      unsigned int c = cards[idx];
      ___WORD *card_lo = sec->base + (___CAST(___SIZE_TS, c) << ___GC_CARD_SHIFT_WORDS);
      ___WORD *card_hi = card_lo + ___GC_CARD_WORDS;
      ___WORD *p;

      if (card_lo < base || card_lo >= scan_end)
        continue;
      if (card_hi > scan_end)
        card_hi = scan_end;

      if (starts[c] == 0)
        p = card_lo;
      else
        {
          int prev = ___CAST(int, c) - 1;
          while (prev >= ___CAST(int, half_card_base) &&
                 starts[prev] == ___GC_CARD_NO_OBJ_START)
            prev--;
          if (prev >= ___CAST(int, half_card_base))
            {
              p = sec->base + (___CAST(___SIZE_TS, prev) << ___GC_CARD_SHIFT_WORDS) + starts[prev];
              while (p < card_lo)
                {
                  ___WORD h = *p;
                  if (___TESTTYPE(h, ___FORW))
                    p += 1;
                  else
                    {
                      ___SIZE_TS sz = ___HD_WORDS(h) + 1;
                      if (p + sz > card_lo)
                        break;
                      p += sz;
                    }
                }
            }
          else
            p = (starts[c] < ___GC_CARD_WORDS) ? (card_lo + starts[c]) : card_hi;
        }

      while (p < card_hi)
        {
          ___WORD head = *p;
          if (___TESTTYPE(head, ___FORW))
            {
              p += 1;
              continue;
            }
          {
            ___SIZE_TS words = ___HD_WORDS(head);
            ___WORD *body = p + 1;
            ___WORD *obj_end = body + words;
            int subtype = ___HD_SUBTYPE(head);

            if ((p < card_lo || obj_end > card_hi) &&
                (subtype == ___sVECTOR || subtype == ___sBOXVALUES ||
                 subtype == ___sSTRUCTURE))
              {
                ___WORD *slo = (body > card_lo) ? body : card_lo;
                ___WORD *shi = (obj_end < card_hi) ? obj_end : card_hi;
                if (slo < shi)
                  mark_array(work, slo, shi - slo);
                p = (obj_end < card_hi) ? obj_end : card_hi;
                continue;
              }

            if (p < last_scanned_end)
              {
                p = obj_end;
                continue;
              }
            last_scanned_end = obj_end;
            scan_mature_object(work, body, head);
            p = obj_end;
          }
        }
    }
}

___HIDDEN void scan_remembered_set(___collector_worker *work)
{
  ___virtual_machine_state vm = work->vm;
  ___gc_round *g = &___COLLECTION(vm);
  int is_census = (work->census != 0);
  int w_id = is_census ? 0 : work->id;
  int w_cnt = is_census ? 1 : g->worker_count;
  int i;

  if (!g->is_minor)
    return;

  if (g->evac_selective)
    {
      /* Selective Immix Evacuation root completeness: pinned mature sections
       * and mature still objects may hold pointers into gc_evacuating sections
       * on CLEAN cards. Partition all pinned mature sections and mature still
       * objects disjointly across workers so every pinned object is scanned
       * exactly once and every reference into YOUNG or gc_evacuating is updated. */
      ___msection *sec;
      int sec_idx = 0;
      if (g->old_mature_tail != 0)
        {
          for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
            {
              if (sec->region_age != ___GC_REGION_MATURE)
                break;
              if (!sec->gc_evacuating)
                {
                  if ((sec_idx % w_cnt) == w_id)
                    {
                      ___WORD *p = sec->base + sec->active_offset;
                      ___WORD *end = p + sec->scan_end_words;
                      while (p < end)
                        {
                          ___WORD head = *p;
                          if (___TESTTYPE(head, ___FORW))
                            {
                              p += 1;
                              continue;
                            }
                          {
                            ___SIZE_TS words = ___HD_WORDS(head);
                            scan_mature_object(work, p + 1, head);
                            p += words + 1;
                          }
                        }
                    }
                  sec_idx++;
                }
              if (sec == g->old_mature_tail)
                break;
            }
        }
      for (i = w_id; i < g->participant_count; i += w_cnt)
        {
          ___processor_state source = ___PSTATE_FROM_PROCESSOR_ID(i, vm);
          ___WORD *base = ___CAST(___WORD*, source->mem.still_objs_);
          while (base != 0)
            {
              ___WORD head = base[___STILL_HEADER];
#ifndef ___USE_HANDLES
              if ((base[___STILL_DIRTY] & ___STILL_FLAG_YOUNG) == 0 &&
                  still_subtype_has_pointers(___HD_SUBTYPE(head)))
#else
              if (still_subtype_has_pointers(___HD_SUBTYPE(head)))
#endif
                scan_mature_object(work, base + ___STILL_BODY, head);
              base = ___CAST(___WORD*, base[___STILL_LINK]);
            }
        }
      return;
    }

  /* 1. Scan dirty mature movable cards. */
  if (!g->card_overflow)
    {
      int run_idx = 0;
      int pos = 0;
      while (pos < g->hint_count)
        {
          ___msection *sec = g->hints[pos].section;
          int start = pos;
          while (pos < g->hint_count && g->hints[pos].section == sec)
            pos++;
          if ((run_idx % w_cnt) == w_id)
            {
              unsigned int cards[___GC_CARD_HINT_CAPACITY * ___MAX_PROCESSORS];
              int n = pos - start;
              int j;
              for (j = 0; j < n; j++)
                cards[j] = g->hints[start + j].card_index;
              scan_mature_card_list(work, sec, cards, n);
              if (!is_census && w_id == 0)
                vm->mem.minor_dirty_cards_scanned_ += n;
            }
          run_idx++;
        }
    }
  else
    {
      ___msection *sec;
      int sec_idx = 0;
      if (!is_census && w_id == 0)
        vm->mem.minor_overflow_fallbacks_++;
      for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
        {
          if (sec->region_age != ___GC_REGION_MATURE)
            break;
          if ((sec_idx % w_cnt) == w_id &&
              ___WORD_LOAD_ACQUIRE(&sec->card_dirty_any) != 0)
            {
              ___VOLATILE ___WORD *cbits = section_card_bits(sec);
              unsigned int half_card_lo =
                ___CAST(unsigned int, sec->active_offset >> ___GC_CARD_SHIFT_WORDS);
              unsigned int half_card_hi =
                half_card_lo + ((___MSECTION_SIZE >> 1) >> ___GC_CARD_SHIFT_WORDS);
              unsigned int w_lo = half_card_lo / ___WORD_WIDTH;
              unsigned int w_hi = (half_card_hi + ___WORD_WIDTH - 1) / ___WORD_WIDTH;
              unsigned int cards[64];
              int ncards = 0;
              unsigned int wi;
              for (wi = w_lo; wi < w_hi; wi++)
                {
                  ___UWORD word = ___CAST(___UWORD, ___WORD_LOAD_ACQUIRE(&cbits[wi]));
                  while (word != 0)
                    {
                      unsigned int bit;
#if defined(__GNUC__)
                      bit = (___WORD_WIDTH == 64)
                            ? ___CAST(unsigned int, __builtin_ctzll(word))
                            : ___CAST(unsigned int, __builtin_ctz(word));
#else
                      bit = 0;
                      while (((word >> bit) & 1u) == 0) bit++;
#endif
                      word &= word - 1;
                      cards[ncards++] = wi * ___WORD_WIDTH + bit;
                      if (ncards == 64)
                        {
                          scan_mature_card_list(work, sec, cards, ncards);
                          if (!is_census && w_id == 0)
                            vm->mem.minor_dirty_cards_scanned_ += ncards;
                          ncards = 0;
                        }
                    }
                }
              if (ncards > 0)
                {
                  scan_mature_card_list(work, sec, cards, ncards);
                  if (!is_census && w_id == 0)
                    vm->mem.minor_dirty_cards_scanned_ += ncards;
                }
            }
          sec_idx++;
          if (sec == g->old_mature_tail)
            break;
        }
    }

  /* 2. Scan mutated mature still objects. */
  if (___WORD_LOAD_ACQUIRE(&vm->mem.still_dirty_any_) != 0)
    {
      for (i = w_id; i < g->participant_count; i += w_cnt)
        {
          ___processor_state source = ___PSTATE_FROM_PROCESSOR_ID(i, vm);
          ___WORD *base = ___CAST(___WORD*, source->mem.still_objs_);
          while (base != 0)
            {
#ifndef ___USE_HANDLES
              if ((base[___STILL_DIRTY] & ___STILL_FLAG_DIRTY) != 0)
#endif
                scan_mature_object(work, base + ___STILL_BODY, base[___STILL_HEADER]);
              base = ___CAST(___WORD*, base[___STILL_LINK]);
            }
        }
    }
}

___HIDDEN void rebuild_mature_snapshot(___virtual_machine_state vm)
{
  ___msections *ms = vm->mem.the_msections_;
  int nm = vm->mem.nb_msections_mature_;
  int ns = ms ? ms->nb_sections : 0;
  int i, out = 0;

  if (nm <= 0 || ms == 0)
    {
      vm->mem.mature_addr_lo_ = 0;
      vm->mem.mature_addr_span_ = 0;
      vm->mem.mature_snapshot_epoch_++;
      return;
    }

  if (nm > vm->mem.mature_sections_cap_)
    {
      int cap = vm->mem.mature_sections_cap_ ? vm->mem.mature_sections_cap_ : 16;
      ___msection **narr;
      while (cap < nm)
        cap *= 2;
      narr = ___CAST(___msection**, ___ALLOC_MEM(cap * sizeof(___msection*)));
      if (narr == 0)
        {
          /* Fallback: disable further minor GCs until space frees */
          vm->mem.mature_addr_lo_ = 0;
          vm->mem.mature_addr_span_ = 0;
          vm->mem.nb_msections_mature_ = 0;
          vm->mem.mature_tail_ = 0;
          vm->mem.mature_snapshot_epoch_++;
          return;
        }
      if (vm->mem.mature_sections_ != 0)
        ___FREE_MEM(vm->mem.mature_sections_);
      vm->mem.mature_sections_ = narr;
      vm->mem.mature_sections_cap_ = cap;
    }

#ifdef ___ALLOC_MEM_UP
  for (i = 0; i < ns; i++)
    if (ms->sections[i]->region_age == ___GC_REGION_MATURE)
      vm->mem.mature_sections_[out++] = ms->sections[i];
#else
  for (i = ns - 1; i >= 0; i--)
    if (ms->sections[i]->region_age == ___GC_REGION_MATURE)
      vm->mem.mature_sections_[out++] = ms->sections[i];
#endif

  vm->mem.nb_msections_mature_ = out;
  if (out > 0)
    {
      ___UWORD lo = ___CAST(___UWORD, vm->mem.mature_sections_[0]->base);
      ___UWORD hi = ___CAST(___UWORD, vm->mem.mature_sections_[out - 1]->base + ___MSECTION_SIZE);
      vm->mem.mature_addr_lo_ = lo;
      vm->mem.mature_addr_span_ = (hi > lo) ? (hi - lo) : 0;
    }
  else
    {
      vm->mem.mature_addr_lo_ = 0;
      vm->mem.mature_addr_span_ = 0;
    }
  vm->mem.mature_snapshot_epoch_++;
}

/* Re-order the doubly-linked list of the_msections into canonical partitions:
 *   [ MATURE (least-full last) ] -> [ active YOUNG stacks & heaps ] -> [ FREE YOUNG ]
 * Does not modify ms->sections[] address-sorted array or s->pos. */
___HIDDEN void finalize_gc_sections(___virtual_machine_state vm)
{
  ___gc_round *g = &___COLLECTION(vm);
  ___msections *ms = vm->mem.the_msections_;
  int np = g->participant_count;
  int p;
  ___msection *sec;

  /* 1. Clear dirty cards (O(H) normal minor, O(dirty) overflow/major) & hints. */
  if (g->is_minor)
    {
      if (!g->card_overflow)
        {
          int i;
          for (i = 0; i < g->hint_count; i++)
            {
              ___msection *s = g->hints[i].section;
              unsigned int c = g->hints[i].card_index;
              ___VOLATILE ___WORD *cbits = section_card_bits(s);
              unsigned int wi = c / ___WORD_WIDTH;
              ___UWORD bit = ___CAST(___UWORD, 1) << (c & (___WORD_WIDTH - 1));
              ___WORD cur = ___WORD_LOAD_RELAXED(&cbits[wi]);
              ___WORD_STORE_RELEASE(&cbits[wi], ___CAST(___WORD, ___CAST(___UWORD, cur) & ~bit));
              if (___WORD_LOAD_RELAXED(&s->card_dirty_any) != 0)
                ___WORD_STORE_RELEASE(&s->card_dirty_any, 0);
            }
        }
      else
        {
          for (sec = ms->head; sec != 0; sec = sec->next)
            {
              if (sec->region_age != ___GC_REGION_MATURE)
                break;
              if (sec->card_dirty_any)
                ___gc_card_clear_section(sec, section_card_bits(sec), ___MSECTION_SIZE);
              if (sec == g->old_mature_tail)
                break;
            }
        }

      if (___WORD_LOAD_ACQUIRE(&vm->mem.still_dirty_any_) != 0)
        {
#ifndef ___USE_HANDLES
          for (p = 0; p < np; p++)
            {
              ___WORD *base = ___CAST(___WORD*, ___PSTATE_FROM_PROCESSOR_ID(p, vm)->mem.still_objs_);
              while (base != 0)
                {
                  if ((base[___STILL_DIRTY] & ___STILL_FLAG_DIRTY) != 0)
                    ___WORD_FETCH_AND_RELEASE(
                      &base[___STILL_DIRTY],
                      ~___CAST(___WORD, ___STILL_FLAG_DIRTY));
                  base = ___CAST(___WORD*, base[___STILL_LINK]);
                }
            }
#endif
          ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 0);
        }
    }
  else
    {
      ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 0);
    }

  for (p = 0; p < np; p++)
    {
      ___processor_state ps = ___PSTATE_FROM_PROCESSOR_ID(p, vm);
      ps->mem.wb_last_card_lo_ = 0;
      ___gc_card_reset_epoch(&ps->mem.card_hints_, g->epoch + 1, 0, 0, 0);
    }

  /* Recompute live mature still word total in O(np). */
  {
    ___SIZE_TS mstill = 0;
    for (p = 0; p < np; p++)
      mstill += ___PSTATE_FROM_PROCESSOR_ID(p, vm)->mem.words_still_objs_mature_;
    vm->mem.mature_still_words_ = mstill;
  }

  /* 2. Finalize section ages and mature word counts. */
  if (g->is_minor)
    {
      /* O(Y + W) Minor GC finalizer: preserve existing mature prefix [head..old_mature_tail]
       * untouched, update only modified promo_tails and newly promoted young sections, and
       * skip rebuild_mature_snapshot() in O(1) whenever no new mature section was added. */
      int i, new_mat_count = 0, active_young_count = 0;
      ___msection *new_mat_head = 0, *new_mat_tail = 0;
      ___msection *act_head = 0, *act_tail = 0;
      ___msection *free_head = 0, *free_tail = 0;
      ___msection *cur;

      for (i = 0; i < g->promo_tail_count; i++)
        {
          ___msection *s = g->promo_tails[i];
          if (s != 0)
            {
              if (s->gc_is_dest == 3)
                {
                  /* Close recycled Immix dead-line hole [hole_lo, hole_hi) strictly
                   * after all parallel chunk-stealing workers drained behind BARRIER(). */
                  ___WORD *hbase = s->base + s->active_offset;
                  ___SIZE_TS hole_lo = g->promo_tail_starts[i];
                  ___SIZE_TS hole_hi = g->promo_tail_ends[i];
                  ___SIZE_TS cur_off = s->gc_dest_words;
                  unsigned char *starts = section_card_starts(s);
                  unsigned int lo_card =
                    ___CAST(unsigned int, (s->active_offset + hole_lo) >> ___GC_CARD_SHIFT_WORDS);

                  if (cur_off <= hole_lo + 1 || cur_off >= hole_hi)
                    {
                      /* Empty hole (nothing promoted): restore single filler & retain hole. */
                      hbase[hole_lo] = ___MAKE_HD_WORDS(hole_hi - hole_lo - 1, ___sU8VECTOR);
                      starts[lo_card] = 0;
                      s->major_hole_start = hole_lo;
                      s->major_hole_end = hole_hi;
                    }
                  else
                    {
                      ___SIZE_TS next_lo = (cur_off + ___GC_CARD_WORDS - 1) &
                                           ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
                      /* Replace initial NULL_CHUNK_LINK at hole_lo with 1-word leaf filler. */
                      hbase[hole_lo] = ___MAKE_HD_WORDS(0, ___sU8VECTOR);
                      starts[lo_card] = 0;
                      if (hole_hi > next_lo && (hole_hi - next_lo) >= 512)
                        {
                          if (next_lo > cur_off)
                            {
                              hbase[cur_off] = ___MAKE_HD_WORDS(next_lo - cur_off - 1, ___sU8VECTOR);
                              record_mature_obj_start(s, hbase + cur_off);
                            }
                          hbase[next_lo] = ___MAKE_HD_WORDS(hole_hi - next_lo - 1, ___sU8VECTOR);
                          record_mature_obj_start(s, hbase + next_lo);
                          s->major_hole_start = next_lo;
                          s->major_hole_end = hole_hi;
                        }
                      else
                        {
                          hbase[cur_off] = ___MAKE_HD_WORDS(hole_hi - cur_off - 1, ___sU8VECTOR);
                          record_mature_obj_start(s, hbase + cur_off);
                          s->major_hole_start = 0;
                          s->major_hole_end = 0;
                        }
                      vm->mem.concurrent_major_holes_recycled_ += 1.0;
                    }
                  s->region_age = ___GC_REGION_MATURE;
                }
              else if (s->gc_is_dest == 2)
                {
                  if (s->gc_dest_words > s->mature_words)
                    vm->mem.occupied_words_mature_ += (s->gc_dest_words - s->mature_words);
                  s->mature_words = s->gc_dest_words;
                  s->scan_end_words = s->mature_words;
                  s->region_age = ___GC_REGION_MATURE;
                }
              s->gc_is_dest = 0;
              s->gc_dest_offset = 0;
              s->gc_dest_words = 0;
              s->gc_role = 0;
              s->gc_src_offset = s->active_offset;
            }
        }

      /* 2a. If selective Immix evacuation ran, unlink all evacuated sparse
       * mature sections from [head .. old_mature_tail] into free_head..free_tail
       * before pruning promo_cands_ and splicing new_mat / act / free. */
      int evac_reclaimed = 0;
      if (g->evac_selective && g->old_mature_tail != 0)
        {
          ___msection *s = ms->head;
          ___msection *stop_after = g->old_mature_tail;
          ___msection *new_old_tail = 0;
          while (s != 0)
            {
              ___msection *nxt = s->next;
              int is_last = (s == stop_after);
              if (s->gc_evacuating)
                {
                  if (s->prev != 0) s->prev->next = s->next;
                  else ms->head = s->next;
                  if (s->next != 0) s->next->prev = s->prev;
                  else ms->tail = s->prev;

                  if (vm->mem.nb_msections_mature_ > 0)
                    vm->mem.nb_msections_mature_--;
                  if (vm->mem.occupied_words_mature_ >= s->mature_words)
                    vm->mem.occupied_words_mature_ -= s->mature_words;
                  else
                    vm->mem.occupied_words_mature_ = 0;
                  if (vm->mem.major_evacuate_count_ > 0)
                    vm->mem.major_evacuate_count_--;

                  s->region_age = ___GC_REGION_YOUNG;
                  s->active_offset = 0;
                  s->mature_words = 0;
                  s->scan_end_words = 0;
                  s->gc_src_offset = 0;
                  s->gc_dest_offset = 0;
                  s->gc_dest_words = 0;
                  s->gc_is_dest = 0;
                  s->gc_role = 0;
                  s->gc_evacuating = 0;
                  s->card_dirty_any = 0;
                  s->major_mark_epoch = 0;
                  s->major_snapshot_words = 0;
                  s->major_live_words = 0;
                  s->major_evacuate = 0;
                  s->major_hole_start = 0;
                  s->major_hole_end = 0;
                  memset(___CAST(void*, section_card_bits(s)), 0, SECTION_CARD_BYTES);
                  memset(___CAST(void*, section_card_starts(s)), ___GC_CARD_NO_OBJ_START, SECTION_CARD_COUNT);
                  *section_claim_at(s, 0) = (section_claim){0};
                  *section_claim_at(s, ___MSECTION_SIZE >> 1) = (section_claim){0};
                  s->region_generation++;
                  s->prev = 0;
                  s->next = 0;
                  if (free_tail) { free_tail->next = s; s->prev = free_tail; free_tail = s; }
                  else { free_head = free_tail = s; }
                  evac_reclaimed++;
                }
              else
                {
                  new_old_tail = s;
                }
              if (is_last)
                break;
              s = nxt;
            }
          g->old_mature_tail = new_old_tail;
          vm->mem.major_last_reclaimed_sections_ = evac_reclaimed;
        }

      /* Prune full or unlinked sections out of O(W) promo_cands_ cache. */
      {
        int out = 0;
        for (i = 0; i < vm->mem.promo_cand_count_; i++)
          {
            ___msection *s = vm->mem.promo_cands_[i];
            if (s != 0 && s->region_age == ___GC_REGION_MATURE &&
                section_best_promo_span(s, 1, 0, 0, 0) > 0)
              vm->mem.promo_cands_[out++] = s;
          }
        vm->mem.promo_cand_count_ = out;
      }

      /* Partition ONLY young suffix [young_head .. tail]. */
      cur = g->young_head;
      if (g->old_mature_tail != 0)
        g->old_mature_tail->next = 0;
      else
        ms->head = 0;

      while (cur != 0)
        {
          ___msection *nxt = cur->next;
          cur->prev = 0;
          cur->next = 0;
          if (cur->gc_is_dest == 1 && cur->gc_dest_words > 1)
            {
              cur->region_age = ___GC_REGION_MATURE;
              cur->active_offset = cur->gc_dest_offset;
              cur->gc_src_offset = cur->active_offset;
              cur->mature_words = cur->gc_dest_words;
              cur->scan_end_words = cur->mature_words;
              {
                /* Newly promoted mature sections land before mature_tail_, which
                 * Minor GC's O(Y) reclaim_drained_source_pages intentionally skips.
                 * Immediately release the dead opposite half (512 KiB) so promoted
                 * Immix mature sections never strand 2x physical RSS. */
                ___SIZE_TS half = (___MSECTION_SIZE >> 1);
                ___SIZE_TS opp = half - cur->active_offset;
                if (opp != cur->active_offset &&
                    section_claim_at(cur, opp)->stack_state == 0 &&
                    !section_claim_at(cur, opp)->heap_used)
                  {
                    *section_claim_at(cur, opp) = (section_claim){0};
                    if (vm->mem.custom_msection_alloc_ == 0 &&
                        ___GC_FROM_RECLAIM_MIN_SECTIONS >= 0)
                      release_drained_source_half(cur, opp);
                  }
              }
              cur->gc_is_dest = 0;
              cur->gc_dest_offset = 0;
              cur->gc_dest_words = 0;
              cur->gc_role = 0;
              cur->card_dirty_any = 0;
              memset(___CAST(void*, section_card_bits(cur)), 0, SECTION_CARD_BYTES);
              if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) == ___GC_MAJOR_MARKING)
                {
                  cur->major_mark_epoch = vm->mem.major_epoch_;
                  cur->major_snapshot_words = 0;
                  cur->major_live_words = ___CAST(___WORD, cur->mature_words);
                  cur->major_evacuate = 0;
                  cur->major_hole_start = 0;
                  cur->major_hole_end = 0;
                }
              else
                {
                  cur->major_mark_epoch = 0;
                  cur->major_snapshot_words = 0;
                  cur->major_live_words = 0;
                  cur->major_evacuate = 0;
                  cur->major_hole_start = 0;
                  cur->major_hole_end = 0;
                }
              cur->region_generation++;
              new_mat_count++;
              vm->mem.occupied_words_mature_ += cur->mature_words;
              promo_cand_add(vm, cur);
              if (new_mat_tail) { new_mat_tail->next = cur; cur->prev = new_mat_tail; new_mat_tail = cur; }
              else { new_mat_head = new_mat_tail = cur; }
            }
          else if (cur->gc_role == 1 || cur->gc_role == 2)
            {
              cur->region_age = ___GC_REGION_YOUNG;
              cur->active_offset = 0;
              cur->mature_words = 0;
              cur->gc_is_dest = 0;
              cur->gc_dest_offset = 0;
              cur->gc_dest_words = 0;
              cur->gc_role = 0;
              active_young_count++;
              if (act_tail) { act_tail->next = cur; cur->prev = act_tail; act_tail = cur; }
              else { act_head = act_tail = cur; }
            }
          else
            {
              cur->region_age = ___GC_REGION_YOUNG;
              cur->active_offset = 0;
              cur->mature_words = 0;
              cur->gc_is_dest = 0;
              cur->gc_dest_offset = 0;
              cur->gc_dest_words = 0;
              cur->gc_role = 0;
              *section_claim_at(cur, 0) = (section_claim){0};
              *section_claim_at(cur, ___MSECTION_SIZE >> 1) = (section_claim){0};
              if (free_tail) { free_tail->next = cur; cur->prev = free_tail; free_tail = cur; }
              else { free_head = free_tail = cur; }
            }
          cur = nxt;
        }

      /* Splice [old_mature] -> [new_mat] -> [act] -> [free]. */
      ms->tail = g->old_mature_tail;
      if (new_mat_head)
        {
          if (ms->tail) { ms->tail->next = new_mat_head; new_mat_head->prev = ms->tail; ms->tail = new_mat_tail; }
          else { ms->head = new_mat_head; ms->tail = new_mat_tail; }
          vm->mem.mature_tail_ = new_mat_tail;
        }
      else
        vm->mem.mature_tail_ = g->old_mature_tail;

      if (act_head)
        {
          if (ms->tail) { ms->tail->next = act_head; act_head->prev = ms->tail; ms->tail = act_tail; }
          else { ms->head = act_head; ms->tail = act_tail; }
        }
      if (free_head)
        {
          if (ms->tail) { ms->tail->next = free_head; free_head->prev = ms->tail; ms->tail = free_tail; }
          else { ms->head = free_head; ms->tail = free_tail; }
        }

      /* Renumber indices across full list if selective evac unlinked mature sections,
       * otherwise ONLY across the newly spliced suffix O(Y). */
      {
        ___msection *idx_cur = (evac_reclaimed > 0)
          ? ms->head
          : (g->old_mature_tail ? g->old_mature_tail->next : ms->head);
        int idx = (evac_reclaimed > 0)
          ? 0
          : (g->old_mature_tail ? (g->old_mature_tail->index + 1) : 0);
        while (idx_cur != 0)
          {
            idx_cur->index = idx++;
            idx_cur = idx_cur->next;
          }
      }

      vm->mem.nb_msections_mature_ += new_mat_count;
      vm->mem.alloc_msection_ = act_tail ? act_tail : vm->mem.mature_tail_;
      vm->mem.nb_msections_assigned_ = vm->mem.nb_msections_mature_ + active_young_count;
      vm->mem.nb_msections_stacks_ = np;
      vm->mem.minor_gcs_since_major_++;

      /* O(1) skip: when no mature section was added or evacuated, mature_sections_[]
       * and mature_snapshot_epoch_ stay valid and wb_last_sec_ remains hot! */
      if (new_mat_count > 0 || evac_reclaimed > 0)
        rebuild_mature_snapshot(vm);
      return;
    }
  else if (g->segregate_mature)
    {
      ___SIZE_TS mature_words_total = 0;
      int mature_count = 0;
      int active_young_count = 0;
      ___msection *best_tail = 0;
      ___SIZE_TS best_tail_words = ___MSECTION_SIZE;
      ___msection *mat_head = 0, *mat_tail = 0;
      ___msection *act_head = 0, *act_tail = 0;
      ___msection *free_head = 0, *free_tail = 0;

      vm->mem.promo_cand_count_ = 0;

      for (sec = ms->head; sec != 0; sec = sec->next)
        {
          /* Major GC with mature segregation */
          if (sec->gc_is_dest == 1 && sec->gc_dest_words > 1)
            {
              sec->region_age = ___GC_REGION_MATURE;
              sec->active_offset = sec->gc_dest_offset;
              sec->gc_src_offset = sec->active_offset;
              sec->mature_words = sec->gc_dest_words;
              sec->scan_end_words = sec->mature_words;
              sec->card_dirty_any = 0;
              memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
            }
          else
            {
              sec->region_age = ___GC_REGION_YOUNG;
              sec->active_offset = 0;
              sec->mature_words = 0;
              sec->scan_end_words = 0;
              sec->card_dirty_any = 0;
              memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
            }
          sec->gc_is_dest = 0;
          sec->gc_dest_offset = 0;
          sec->gc_dest_words = 0;
          sec->major_mark_epoch = 0;
          sec->major_snapshot_words = 0;
          sec->major_live_words = 0;
          sec->major_evacuate = 0;
          sec->gc_evacuating = 0;
          sec->major_hole_start = 0;
          sec->major_hole_end = 0;

          if (sec->region_age == ___GC_REGION_MATURE)
            {
              mature_count++;
              mature_words_total += sec->mature_words;
              promo_cand_add(vm, sec);
              if (sec->mature_words < best_tail_words)
                {
                  best_tail_words = sec->mature_words;
                  best_tail = sec;
                }
            }
        }

      /* Partition doubly-linked list: MATURE (best_tail last) -> ACTIVE YOUNG -> FREE YOUNG. */
      {
        ___msection *cur = ms->head;
        while (cur != 0)
          {
            ___msection *nxt = cur->next;
            int role = cur->gc_role;
            cur->gc_role = 0;
            cur->prev = 0;
            cur->next = 0;
            if (cur->region_age == ___GC_REGION_MATURE)
              {
                if (cur != best_tail)
                  {
                    if (mat_tail) { mat_tail->next = cur; cur->prev = mat_tail; mat_tail = cur; }
                    else { mat_head = mat_tail = cur; }
                  }
              }
            else if (role == 1 || role == 2)
              {
                active_young_count++;
                if (act_tail) { act_tail->next = cur; cur->prev = act_tail; act_tail = cur; }
                else { act_head = act_tail = cur; }
              }
            else
              {
                *section_claim_at(cur, 0) = (section_claim){0};
                *section_claim_at(cur, ___MSECTION_SIZE >> 1) = (section_claim){0};
                if (free_tail) { free_tail->next = cur; cur->prev = free_tail; free_tail = cur; }
                else { free_head = free_tail = cur; }
              }
            cur = nxt;
          }
        if (best_tail != 0)
          {
            if (mat_tail) { mat_tail->next = best_tail; best_tail->prev = mat_tail; mat_tail = best_tail; }
            else { mat_head = mat_tail = best_tail; }
          }

        /* Splice the three chains together */
        ms->head = 0;
        ms->tail = 0;
        if (mat_head) { ms->head = mat_head; ms->tail = mat_tail; }
        if (act_head)
          {
            if (ms->tail) { ms->tail->next = act_head; act_head->prev = ms->tail; ms->tail = act_tail; }
            else { ms->head = act_head; ms->tail = act_tail; }
          }
        if (free_head)
          {
            if (ms->tail) { ms->tail->next = free_head; free_head->prev = ms->tail; ms->tail = free_tail; }
            else { ms->head = free_head; ms->tail = free_tail; }
          }
        {
          int idx = 0;
          for (sec = ms->head; sec != 0; sec = sec->next)
            sec->index = idx++;
        }
      }

      vm->mem.nb_msections_mature_ = mature_count;
      vm->mem.mature_tail_ = mat_tail;
      vm->mem.occupied_words_mature_ = mature_words_total;
      vm->mem.major_evacuate_count_ = 0;
      vm->mem.alloc_msection_ = act_tail ? act_tail : mat_tail;
      vm->mem.nb_msections_assigned_ = mature_count + active_young_count;
      vm->mem.nb_msections_stacks_ = np;

      gc_update_major_triggers(vm);
    }
  else
    {
      /* Non-segregated Major GC fallback (tight max_heap or probes) */
      vm->mem.promo_cand_count_ = 0;
      for (sec = ms->head; sec != 0; sec = sec->next)
        {
          sec->region_age = ___GC_REGION_YOUNG;
          sec->active_offset = 0;
          sec->mature_words = 0;
          sec->card_dirty_any = 0;
        }
      vm->mem.nb_msections_mature_ = 0;
      vm->mem.mature_tail_ = 0;
      vm->mem.occupied_words_mature_ = 0;
      vm->mem.minor_gcs_since_major_ = 0;
      vm->mem.major_trigger_still_words_ =
        (vm->mem.mature_still_words_ * 2 > 4 * ___MSECTION_SIZE)
        ? (vm->mem.mature_still_words_ * 2)
        : (4 * ___MSECTION_SIZE);
    }

  rebuild_mature_snapshot(vm);
}

#endif
