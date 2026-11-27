/* Per-section 2-bit side-table deferred reference counting for mature Immix lines.
 *
 * Each mature section owns an inline 128-byte 2-bit table inside its trailing
 * metadata (section_lxr_drc_bits(sec)), eliminating any aliasing across
 * adjust_msections() re-indexing of sec->pos:
 *   0 = FREE / dead (reclaimable when SATB is inactive)
 *   1 = RC_1 (single incoming reference; default 0x55 initialization)
 *   2 = RC_2 (multiple incoming references)
 *   3 = RC_STUCK (saturated; cleared only by backup concurrent SATB sweep)
 *
 * Safety invariants:
 *   - Prompt line reclamation runs strictly when major_phase_ == ___GC_MAJOR_IDLE
 *     so an unmarked object is never deleted while an SATB trace is active.
 *   - Reusing or reclaiming a line bumps section->region_generation so stale
 *     pre-reuse card hints are rejected during remembered-set scanning.
 */

#ifndef ___LXR_DRC_INC
#define ___LXR_DRC_INC

#define ___LXR_LINES_PER_SEC     (8 * ___WORD_WIDTH)
#define ___LXR_BYTES_PER_SEC     ((___LXR_LINES_PER_SEC + 3) / 4)
#define ___LXR_RC_FREE           0u
#define ___LXR_RC_ONE            1u
#define ___LXR_RC_TWO            2u
#define ___LXR_RC_STUCK          3u

typedef struct lxr_drc_table_struct
  {
    ___SIZE_TS lines_reclaimed;
    ___SIZE_TS lines_deferred_satb;
    ___SIZE_TS stuck_resets;
  } lxr_drc_table;

static inline ___root_round *lxr_drc_root_round(___virtual_machine_state vm)
{
  ___processor_state p0;
  if (vm == 0)
    return 0;
  p0 = ___PSTATE_FROM_PROCESSOR_ID(0, vm);
  if (p0 == 0 || p0->mem.rc_domain_ == 0)
    return 0;
  return p0->mem.rc_domain_->round;
}

___HIDDEN void lxr_drc_free(___virtual_machine_state vm)
{
  ___root_round *rr = lxr_drc_root_round(vm);
  ___gc_round *g;
  lxr_drc_table *tbl;
  if (rr == 0)
    return;
  g = &rr->collection;
  tbl = ___CAST(lxr_drc_table*, g->lxr_drc);
  if (tbl != 0)
    {
      ___FREE_MEM(tbl);
      g->lxr_drc = 0;
    }
}

/* Ensure the per-VM telemetry counters record is allocated during STW. */
___HIDDEN lxr_drc_table *lxr_drc_ensure(___virtual_machine_state vm, int need_secs)
{
  ___root_round *rr = lxr_drc_root_round(vm);
  ___gc_round *g;
  lxr_drc_table *tbl;

  (void)need_secs;
  if (rr == 0)
    return 0;
  g = &rr->collection;
  tbl = ___CAST(lxr_drc_table*, g->lxr_drc);
  if (tbl == 0)
    {
      tbl = ___CAST(lxr_drc_table*, ___ALLOC_MEM(sizeof(lxr_drc_table)));
      if (tbl == 0)
        return 0;
      memset(tbl, 0, sizeof(lxr_drc_table));
      g->lxr_drc = tbl;
    }
  return tbl;
}

static inline unsigned int lxr_drc_get
   (___msection *sec,
    ___SIZE_TS line)
{
  unsigned char *bits;
  unsigned int shift;
  if (sec == 0 || line < 0 || line >= ___LXR_LINES_PER_SEC)
    return ___LXR_RC_STUCK;
  bits = section_lxr_drc_bits(sec);
  shift = ___CAST(unsigned int, (line & 3) << 1);
  return (bits[line >> 2] >> shift) & 3u;
}

static inline void lxr_drc_set
   (___msection *sec,
    ___SIZE_TS line,
    unsigned int val)
{
  unsigned char *bits;
  unsigned int shift;
  if (sec == 0 || line < 0 || line >= ___LXR_LINES_PER_SEC)
    return;
  bits = section_lxr_drc_bits(sec);
  shift = ___CAST(unsigned int, (line & 3) << 1);
  bits[line >> 2] = ___CAST(unsigned char,
    (bits[line >> 2] & ~(3u << shift)) | ((val & 3u) << shift));
}

static inline void lxr_drc_inc_line
   (___msection *sec,
    ___SIZE_TS line)
{
  unsigned int cur = lxr_drc_get(sec, line);
  if (cur < ___LXR_RC_STUCK)
    lxr_drc_set(sec, line, cur + 1u);
}

static inline unsigned int lxr_drc_dec_line
   (___msection *sec,
    ___SIZE_TS line)
{
  unsigned int cur = lxr_drc_get(sec, line);
  if (cur == ___LXR_RC_STUCK || cur == ___LXR_RC_FREE)
    return cur;
  lxr_drc_set(sec, line, cur - 1u);
  return cur - 1u;
}

___HIDDEN void lxr_drc_ensure_capacity(___virtual_machine_state vm, int need_secs)
{
  (void)lxr_drc_ensure(vm, need_secs);
}

/* Synchronize a mature section's inline 2-bit side-table from exact SATB sweep
 * state: dead lines recorded in major_line_live[] reset to RC_FREE; live lines
 * reset from RC_STUCK back to RC_ONE so subsequent epochs can track them again. */
___HIDDEN void lxr_drc_sync_section_after_sweep
   (___virtual_machine_state vm,
    ___msection *sec)
{
  lxr_drc_table *tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  ___SIZE_TS ln;
  ___SIZE_TS local_resets = 0;
  if (sec == 0)
    return;
  for (ln = 0; ln < ___LXR_LINES_PER_SEC; ln++)
    {
      ___UWORD w = sec->major_line_live[ln / ___WORD_WIDTH];
      ___UWORD bit = ___CAST(___UWORD, 1) << (ln & (___WORD_WIDTH - 1));
      if ((w & bit) != 0)
        lxr_drc_set(sec, ln, ___LXR_RC_FREE);
      else
        {
          if (lxr_drc_get(sec, ln) == ___LXR_RC_STUCK)
            local_resets++;
          lxr_drc_set(sec, ln, ___LXR_RC_ONE);
        }
    }
  if (tbl != 0 && local_resets > 0)
    {
#if defined(__ATOMIC_RELAXED)
      __atomic_fetch_add(&tbl->stuck_resets, local_resets, __ATOMIC_RELAXED);
#else
      tbl->stuck_resets += local_resets;
#endif
    }
}

/* Mark lines populated by Minor GC hole/tail/fresh promotion as RC_ONE. */
___HIDDEN void lxr_drc_mark_promoted_span
   (___virtual_machine_state vm,
    ___msection *sec,
    ___SIZE_TS word_lo,
    ___SIZE_TS word_hi)
{
  ___SIZE_TS ln_lo, ln_hi, ln;
  (void)vm;
  if (sec == 0 || word_hi <= word_lo)
    return;
  ln_lo = word_lo >> 7;
  ln_hi = (word_hi + 127) >> 7;
  if (ln_hi > ___LXR_LINES_PER_SEC)
    ln_hi = ___LXR_LINES_PER_SEC;
  for (ln = ln_lo; ln < ln_hi; ln++)
    lxr_drc_set(sec, ln, ___LXR_RC_ONE);
}

/* Promptly reclaim a zero-RC mature line when SATB tracing is inactive,
 * bumping region_generation to invalidate any stale remembered-set hints. */
___HIDDEN int lxr_drc_try_reclaim_line
   (___virtual_machine_state vm,
    ___msection *sec,
    ___SIZE_TS line)
{
  lxr_drc_table *tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  if (tbl == 0 || sec == 0 || sec->region_age != ___GC_REGION_MATURE ||
      sec->gc_evacuating || line < 0 || line >= ___LXR_LINES_PER_SEC)
    return 0;
  if (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE)
    {
      tbl->lines_deferred_satb++;
      return 0;
    }
  if (lxr_drc_get(sec, line) != ___LXR_RC_FREE)
    return 0;
  sec->major_line_live[line / ___WORD_WIDTH] |=
    (___CAST(___UWORD, 1) << (line & (___WORD_WIDTH - 1)));
  sec->region_generation++;
  tbl->lines_reclaimed++;
  return 1;
}

/* Reclaim newly RC_FREE mature lines outside the active hole into
 * major_line_live[] strictly when SATB tracing is IDLE; defer and count
 * when SATB tracing is active. */
___HIDDEN int lxr_drc_reclaim_free_lines_idle
   (___virtual_machine_state vm,
    ___msection *sec)
{
  lxr_drc_table *tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  ___SIZE_TS max_ln, active_lo, active_hi, ln;
  int reclaimed = 0;
  int satb_active;

  if (tbl == 0 || sec == 0 ||
      sec->region_age != ___GC_REGION_MATURE || sec->gc_evacuating ||
      sec->major_mark_epoch == 0)
    return 0;

  max_ln = sec->major_snapshot_words >> 7;
  if (max_ln > (sec->mature_words >> 7))
    max_ln = sec->mature_words >> 7;
  if (max_ln > ___LXR_LINES_PER_SEC)
    max_ln = ___LXR_LINES_PER_SEC;
  active_lo = sec->major_hole_start >> 7;
  active_hi = sec->major_hole_end >> 7;
  satb_active = (___WORD_LOAD_ACQUIRE(&vm->mem.major_phase_) != ___GC_MAJOR_IDLE);

  for (ln = 0; ln < max_ln; ln++)
    {
      ___UWORD w, bit;
      if (ln >= active_lo && ln < active_hi)
        continue;
      w = sec->major_line_live[ln / ___WORD_WIDTH];
      bit = ___CAST(___UWORD, 1) << (ln & (___WORD_WIDTH - 1));
      if ((w & bit) != 0)
        continue;
      if (lxr_drc_get(sec, ln) == ___LXR_RC_FREE)
        {
          if (satb_active)
            tbl->lines_deferred_satb++;
          else if (lxr_drc_try_reclaim_line(vm, sec, ln))
            reclaimed++;
        }
    }
  return reclaimed;
}

___HIDDEN void lxr_drc_sync_vm_stats(___virtual_machine_state vm)
{
  lxr_drc_table *tbl;
  if (vm == 0 || lxr_drc_root_round(vm) == 0)
    return;
  tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  if (tbl == 0)
    return;
  vm->mem.lxr_lines_reclaimed_ = ___CAST(___F64, tbl->lines_reclaimed);
  vm->mem.lxr_lines_deferred_satb_ = ___CAST(___F64, tbl->lines_deferred_satb);
  vm->mem.lxr_stuck_resets_ = ___CAST(___F64, tbl->stuck_resets);
}

#endif
