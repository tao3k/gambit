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
      if (___WORD_LOAD_RELAXED(&base[___STILL_DIRTY]) == 0)
        {
          ___WORD_STORE_RELEASE(&base[___STILL_DIRTY], 1);
          ___WORD_STORE_RELEASE(&vm->mem.still_dirty_any_, 1);
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
      if (___WORD_LOAD_RELAXED(&base[___STILL_DIRTY]) == 0)
        {
          ___WORD_STORE_RELEASE(&base[___STILL_DIRTY], 1);
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
      if (typ != ___MOVABLE0)
        return 0;
      {
        ___processor_state ___ps = work->carrier;
        ___WORD *header = body - 1;
        ___msection *sec = ___gc_find_msection_cached(work, the_msections, header);
        if (sec == 0)
          return 0;
        if (sec->region_age == ___GC_REGION_MATURE)
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
  g->card_overflow = 0;
  g->hint_count = 0;
  g->promo_tail_count = 0;
  g->old_mature_tail = vm->mem.mature_tail_;
  g->young_head = g->old_mature_tail ? g->old_mature_tail->next : vm->mem.the_msections_->head;
  {
    int i;
    for (i = 0; i < ___MAX_PROCESSORS; i++)
      {
        g->young_heap_secs[i] = 0;
        g->promo_tails[i] = 0;
        g->promo_tail_starts[i] = 0;
      }
  }

  if (can_gen &&
      force_major == 0 &&
      requested_words_still == 0 &&
      vm->mem.nb_msections_mature_ > 0 &&
      vm->mem.nb_msections_mature_ < vm->mem.major_trigger_sections_ &&
      vm->mem.minor_gcs_since_major_ < 64 &&
      g->worker_count >= 1 &&
      np == vm->processor_count)
    {
      int ok = 1;
      if (___GSTATE->setup_params.max_heap > 0)
        {
          ___SIZE_TS cap_secs =
            (___GSTATE->setup_params.max_heap >> ___LWS) / ___MSECTION_SIZE;
          if (___CAST(___SIZE_TS, vm->mem.nb_msections_mature_ + 2 * np + 2) > cap_secs)
            ok = 0;
        }
      if (ok)
        g->is_minor = 1;
    }

  for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
    {
      sec->gc_dest_offset = 0;
      sec->gc_dest_words = 0;
      sec->gc_is_dest = 0;
      sec->gc_role = 0;
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

  if (g->is_minor)
    {
      int max_tails = g->worker_count;
      collect_minor_card_hints(vm);
      /* Select up to worker_count least-full existing mature sections with
       * remaining card-aligned headroom so parallel Minor GC workers pack
       * promotions into existing tails instead of leaking sparse sections. */
      for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
        {
          ___SIZE_TS start_w;
          if (sec->region_age != ___GC_REGION_MATURE)
            break;
          start_w = (sec->mature_words + ___GC_CARD_WORDS - 1) &
                    ~___CAST(___SIZE_TS, ___GC_CARD_WORDS - 1);
          if (start_w + ___MSECTION_FUDGE + 256 < (___MSECTION_SIZE >> 1))
            {
              if (g->promo_tail_count < max_tails)
                {
                  int idx = g->promo_tail_count++;
                  g->promo_tails[idx] = sec;
                  g->promo_tail_starts[idx] = start_w;
                }
              else
                {
                  int worst = 0, j;
                  for (j = 1; j < max_tails; j++)
                    if (g->promo_tail_starts[j] > g->promo_tail_starts[worst])
                      worst = j;
                  if (start_w < g->promo_tail_starts[worst])
                    {
                      g->promo_tails[worst] = sec;
                      g->promo_tail_starts[worst] = start_w;
                    }
                }
            }
          if (sec == g->old_mature_tail)
            break;
        }
    }
}

___HIDDEN void downgrade_minor_to_major(___processor_state ps)
{
  ___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(ps);
  ___gc_round *g = &___COLLECTION(vm);
  ___msection *sec;
  g->is_minor = 0;
  g->card_overflow = 0;
  g->hint_count = 0;
  g->promo_tail_count = 0;
  for (sec = vm->mem.the_msections_->head; sec != 0; sec = sec->next)
    {
      sec->gc_dest_offset = 0;
      sec->gc_dest_words = 0;
      sec->gc_is_dest = 0;
      sec->gc_role = 0;
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

  /* 2. Scan newly allocated or mutated still objects. */
  if (___WORD_LOAD_ACQUIRE(&vm->mem.still_dirty_any_) != 0)
    {
      for (i = w_id; i < g->participant_count; i += w_cnt)
        {
          ___processor_state source = ___PSTATE_FROM_PROCESSOR_ID(i, vm);
          ___WORD *base = ___CAST(___WORD*, source->mem.still_objs_);
          while (base != 0)
            {
#ifndef ___USE_HANDLES
              if (base[___STILL_DIRTY] != 0)
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
                  if (base[___STILL_DIRTY] != 0)
                    base[___STILL_DIRTY] = 0;
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

  /* 2. Finalize section ages and mature word counts. */
  if (g->is_minor || g->segregate_mature)
    {
      ___SIZE_TS mature_words_total = 0;
      int mature_count = 0;
      int active_young_count = 0;
      ___msection *best_tail = 0;
      ___SIZE_TS best_tail_words = ___MSECTION_SIZE;
      ___msection *mat_head = 0, *mat_tail = 0;
      ___msection *act_head = 0, *act_tail = 0;
      ___msection *free_head = 0, *free_tail = 0;

      for (sec = ms->head; sec != 0; sec = sec->next)
        {
          if (g->is_minor)
            {
              if (sec->gc_is_dest == 2)
                {
                  sec->mature_words = sec->gc_dest_words;
                  sec->region_age = ___GC_REGION_MATURE;
                }
              else if (sec->gc_is_dest == 1)
                {
                  if (sec->gc_dest_words > 1)
                    {
                      sec->region_age = ___GC_REGION_MATURE;
                      sec->active_offset = sec->gc_dest_offset;
                      sec->mature_words = sec->gc_dest_words;
                      sec->card_dirty_any = 0;
                      memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
                      sec->region_generation++;
                    }
                  else
                    {
                      sec->region_age = ___GC_REGION_YOUNG;
                      sec->active_offset = 0;
                      sec->mature_words = 0;
                    }
                }
            }
          else
            {
              /* Major GC with mature segregation */
              if (sec->gc_is_dest == 1 && sec->gc_dest_words > 1)
                {
                  sec->region_age = ___GC_REGION_MATURE;
                  sec->active_offset = sec->gc_dest_offset;
                  sec->mature_words = sec->gc_dest_words;
                  sec->card_dirty_any = 0;
                  memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
                }
              else
                {
                  sec->region_age = ___GC_REGION_YOUNG;
                  sec->active_offset = 0;
                  sec->mature_words = 0;
                  sec->card_dirty_any = 0;
                  memset(___CAST(void*, section_card_bits(sec)), 0, SECTION_CARD_BYTES);
                }
            }

          if (sec->region_age == ___GC_REGION_MATURE)
            {
              mature_count++;
              mature_words_total += sec->mature_words;
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
            else if (cur->gc_role == 1 || cur->gc_role == 2)
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
      vm->mem.alloc_msection_ = act_tail ? act_tail : mat_tail;
      vm->mem.nb_msections_assigned_ = mature_count + active_young_count;
      vm->mem.nb_msections_stacks_ = np;

      if (g->is_minor)
        vm->mem.minor_gcs_since_major_++;
      else
        {
          int trig = mature_count * 2;
          if (trig < mature_count + 8)
            trig = mature_count + 8;
          vm->mem.major_trigger_sections_ = trig;
          vm->mem.minor_gcs_since_major_ = 0;
        }
    }
  else
    {
      /* Non-segregated Major GC fallback (tight max_heap or probes) */
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
    }

  rebuild_mature_snapshot(vm);
}

#endif
