/* Per-VM 2-bit side-table deferred reference counting for mature Immix lines.
 *
 * Each mature section has 512 128-word Immix lines. Each line carries a 2-bit
 * saturating count packed 4 lines per byte (128 bytes per section):
 *   0 = FREE / dead (reclaimable when SATB is inactive)
 *   1 = RC_1 (single incoming reference)
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
    unsigned char *bits;
    int sec_cap;
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
      if (tbl->bits != 0)
        ___FREE_MEM(tbl->bits);
      ___FREE_MEM(tbl);
      g->lxr_drc = 0;
    }
}

/* Grow the per-VM 2-bit side-table during STW to cover [0 .. need_secs). */
___HIDDEN lxr_drc_table *lxr_drc_ensure(___virtual_machine_state vm, int need_secs)
{
  ___root_round *rr = lxr_drc_root_round(vm);
  ___gc_round *g;
  lxr_drc_table *tbl;
  int ncap;
  unsigned char *nbits;

  if (rr == 0 || need_secs <= 0)
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
  if (need_secs <= tbl->sec_cap)
    return tbl;

  ncap = tbl->sec_cap ? (tbl->sec_cap * 2) : 64;
  while (ncap < need_secs)
    ncap *= 2;
  nbits = ___CAST(unsigned char*,
                  ___ALLOC_MEM(___CAST(___SIZE_T, ncap) * ___LXR_BYTES_PER_SEC));
  if (nbits == 0)
    return tbl;
  if (tbl->sec_cap > 0 && tbl->bits != 0)
    memcpy(nbits, tbl->bits, ___CAST(___SIZE_T, tbl->sec_cap) * ___LXR_BYTES_PER_SEC);
  memset(nbits + ___CAST(___SIZE_T, tbl->sec_cap) * ___LXR_BYTES_PER_SEC,
         0,
         ___CAST(___SIZE_T, ncap - tbl->sec_cap) * ___LXR_BYTES_PER_SEC);
  if (tbl->bits != 0)
    ___FREE_MEM(tbl->bits);
  tbl->bits = nbits;
  tbl->sec_cap = ncap;
  return tbl;
}

static inline unsigned int lxr_drc_get
   (const lxr_drc_table *tbl,
    int sec_pos,
    ___SIZE_TS line)
{
  ___SIZE_TS byte_idx;
  unsigned int shift;
  if (tbl == 0 || tbl->bits == 0 || sec_pos < 0 || sec_pos >= tbl->sec_cap ||
      line < 0 || line >= ___LXR_LINES_PER_SEC)
    return ___LXR_RC_STUCK;
  byte_idx = ___CAST(___SIZE_TS, sec_pos) * ___LXR_BYTES_PER_SEC + (line >> 2);
  shift = ___CAST(unsigned int, (line & 3) << 1);
  return (tbl->bits[byte_idx] >> shift) & 3u;
}

static inline void lxr_drc_set
   (lxr_drc_table *tbl,
    int sec_pos,
    ___SIZE_TS line,
    unsigned int val)
{
  ___SIZE_TS byte_idx;
  unsigned int shift;
  if (tbl == 0 || tbl->bits == 0 || sec_pos < 0 || sec_pos >= tbl->sec_cap ||
      line < 0 || line >= ___LXR_LINES_PER_SEC)
    return;
  byte_idx = ___CAST(___SIZE_TS, sec_pos) * ___LXR_BYTES_PER_SEC + (line >> 2);
  shift = ___CAST(unsigned int, (line & 3) << 1);
  tbl->bits[byte_idx] = ___CAST(unsigned char,
    (tbl->bits[byte_idx] & ~(3u << shift)) | ((val & 3u) << shift));
}

static inline void lxr_drc_inc_line
   (lxr_drc_table *tbl,
    int sec_pos,
    ___SIZE_TS line)
{
  unsigned int cur = lxr_drc_get(tbl, sec_pos, line);
  if (cur < ___LXR_RC_STUCK)
    lxr_drc_set(tbl, sec_pos, line, cur + 1u);
}

static inline unsigned int lxr_drc_dec_line
   (lxr_drc_table *tbl,
    int sec_pos,
    ___SIZE_TS line)
{
  unsigned int cur = lxr_drc_get(tbl, sec_pos, line);
  if (cur == ___LXR_RC_STUCK || cur == ___LXR_RC_FREE)
    return cur;
  lxr_drc_set(tbl, sec_pos, line, cur - 1u);
  return cur - 1u;
}

/* Synchronize a mature section's 2-bit side-table from exact SATB sweep state:
 * dead lines recorded in major_line_live[] reset to RC_FREE; live lines reset
 * from RC_STUCK back to RC_ONE so subsequent epochs can track them again. */
___HIDDEN void lxr_drc_sync_section_after_sweep
   (___virtual_machine_state vm,
    ___msection *sec)
{
  lxr_drc_table *tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  ___SIZE_TS ln;
  if (tbl == 0 || tbl->bits == 0 || sec == 0 ||
      sec->pos < 0 || sec->pos >= tbl->sec_cap)
    return;
  for (ln = 0; ln < ___LXR_LINES_PER_SEC; ln++)
    {
      ___UWORD w = sec->major_line_live[ln / ___WORD_WIDTH];
      ___UWORD bit = ___CAST(___UWORD, 1) << (ln & (___WORD_WIDTH - 1));
      if ((w & bit) != 0)
        lxr_drc_set(tbl, sec->pos, ln, ___LXR_RC_FREE);
      else
        lxr_drc_set(tbl, sec->pos, ln, ___LXR_RC_ONE);
    }
}

/* Mark lines populated by Minor GC hole promotion as RC_ONE. */
___HIDDEN void lxr_drc_mark_promoted_span
   (___virtual_machine_state vm,
    ___msection *sec,
    ___SIZE_TS word_lo,
    ___SIZE_TS word_hi)
{
  lxr_drc_table *tbl = ___CAST(lxr_drc_table*, ___COLLECTION(vm).lxr_drc);
  ___SIZE_TS ln_lo, ln_hi, ln;
  if (tbl == 0 || tbl->bits == 0 || sec == 0 ||
      sec->pos < 0 || sec->pos >= tbl->sec_cap || word_hi <= word_lo)
    return;
  ln_lo = word_lo >> 7;
  ln_hi = (word_hi + 127) >> 7;
  if (ln_hi > ___LXR_LINES_PER_SEC)
    ln_hi = ___LXR_LINES_PER_SEC;
  for (ln = ln_lo; ln < ln_hi; ln++)
    lxr_drc_set(tbl, sec->pos, ln, ___LXR_RC_ONE);
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
  if (lxr_drc_get(tbl, sec->pos, line) != ___LXR_RC_FREE)
    return 0;
  sec->major_line_live[line / ___WORD_WIDTH] |=
    (___CAST(___UWORD, 1) << (line & (___WORD_WIDTH - 1)));
  sec->region_generation++;
  tbl->lines_reclaimed++;
  return 1;
}

#endif
