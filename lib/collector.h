/* Collector-private copy/scan authority. RootOrigin and RootTask remain the
 * sole root population; these records own work and physical restoration only. */
#ifndef ___COLLECTOR_H
#define ___COLLECTOR_H
#include "gambit.h"
#include <limits.h>
#define ___gc_atomic_load(p) ___WORD_LOAD_ACQUIRE(p)
typedef struct ___gc_resume_space_struct
  {
    ___execution_context *context;
    ___processor_state owner;
    ___WORD epoch;
    ___msection *stack_section;
    ___WORD *loan_base;
    ___WORD *loan_limit;
    ___WORD *stack_floor;
    int loan_used;
    int accepted;
    int restored; /* active stack restored, before owner-affine cleanup */
    int source_drained; /* published after the last local old-space read */
    int source_worker; /* -1: independent empty span; otherwise unique W tail */
    int copy_admitted; /* set only after the checked continuation copy */
    ___msection *source_section; /* stack section captured at copy preflight */
    ___WORD *source_fp;
    ___WORD *source_break;
    ___SIZE_TS source_half; /* active half of source_section, in words */
    ___SIZE_TS source_words; /* validated [fp, break + first-break) span */
  } ___gc_resume_space;

/* Both endpoints must already lie in one half. The word count is formed
 * only after that proof, so a foreign cursor is never subtracted. */
static inline int ___gc_stack_span_words
 (___WORD *half_base, ___WORD *half_past, ___WORD *fp, ___WORD *stack_break,
  ___SIZE_TS break_words, ___SIZE_TS *words)
{
  ___UWORD base = ___CAST(___UWORD,half_base);
  ___UWORD past = ___CAST(___UWORD,half_past);
  ___UWORD start = ___CAST(___UWORD,fp);
  ___UWORD brk = ___CAST(___UWORD,stack_break);
  ___UWORD bytes = ___CAST(___UWORD,break_words) * ___WS;
  ___UWORD end;
  if (half_base == 0 || fp == 0 || stack_break == 0 || past <= base ||
      start < base || brk < start || brk > past || bytes > past - brk ||
      ((base | past | start | brk) % ___WS) != 0)
    return 0;
  end = brk + bytes;
  if (end > past) return 0;
  *words = (end - start) / ___WS;
  return *words >= 1;
}

/* Room is [floor, cursor). Exact fit is room == words. One word short fails.
 * The cursor may be one past the active half. */
static inline int ___gc_stack_span_fits
 (___WORD *half_base, ___WORD *half_past, ___WORD *floor, ___WORD *cursor,
  ___SIZE_TS words)
{
  ___UWORD base = ___CAST(___UWORD,half_base);
  ___UWORD past = ___CAST(___UWORD,half_past);
  ___UWORD low = ___CAST(___UWORD,floor);
  ___UWORD high = ___CAST(___UWORD,cursor);
  if (words < 1 || half_base == 0 || floor == 0 || cursor == 0 ||
      past <= base || low < base || high < low || high > past ||
      ((base | past | low | high) % ___WS) != 0)
    return 0;
  return (high - low) / ___WS >= ___CAST(___UWORD,words);
}

/* Address of census_continuation's first frame load. Forming it does not
 * read the cell. */
static inline ___WORD *___gc_stack_first_read_cell (___WORD *fp)
{
  return &___FP_STK(fp, -___FRAME_STACK_RA);
}

/* cell is one of the words in [start, start+words). No load. */
static inline int ___gc_stack_cell_inside
 (___WORD *start, ___SIZE_TS words, ___WORD *cell)
{
  ___UWORD base = ___CAST(___UWORD,start);
  ___UWORD addr = ___CAST(___UWORD,cell);
  ___UWORD end;
  if (start == 0 || cell == 0 || words < 1 || (base % ___WS) != 0 ||
      (addr % ___WS) != 0)
    return 0;
  end = base + ___CAST(___UWORD,words) * ___WS;
  return addr >= base && addr < end;
}

typedef struct ___gc_worker_arena_struct
  {
    ___WORD *base;
    ___WORD *cursor;
    ___WORD *limit;
    ___WORD *physical_limit; /* immutable restoration limit, beyond copy fudge */
    int large;
    ___WORD *pending;
    ___WORD *pending_past;
    ___msection *section;
    ___WORD epoch;
    ___SIZE_TS retired_words;
    ___SIZE_TS refills;
    int handed_off;
  } ___gc_worker_arena;

typedef enum ___gc_worker_phase_enum
  {
    ___GC_WORKER_IDLE, ___GC_WORKER_PREPARED, ___GC_WORKER_STRONG_COMPLETE,
    ___GC_WORKER_WEAK_COMPLETE, ___GC_WORKER_COMPLETE
  } ___gc_worker_phase;

/* VM-owned request survives loss of the C activation before arena refill.
 * state: 0 settled, 1 prepared, 2 physically reserved. Unknown stops retain it;
 * a record is not permission to replay a partially published copy. */
typedef struct ___gc_copy_request_struct
  {
    ___msection *source_section;
    ___WORD *source_begin;
    ___SIZE_TS source_words;
    ___SIZE_TS destination_words; /* header and worst alignment included */
    ___WORD epoch;
    ___VOLATILE ___WORD state;
    int frame;
  } ___gc_copy_request;

/* Planning never modifies a Scheme payload, root, forwarding word or will.
 * Queue storage belongs to this VM. Allocation publication is a transaction;
 * an unsettled transaction is retained, never silently reset for another GC. */
enum ___gc_plan_state { ___GC_PLAN_IDLE, ___GC_PLAN_READING,
  ___GC_PLAN_ALLOCATING, ___GC_PLAN_READY, ___GC_PLAN_ACCEPTED,
  ___GC_PLAN_REFUSED, ___GC_PLAN_RETAINED };
typedef struct ___gc_census_struct {
  ___SCMOBJ *queue, *replacement, *retired;
  ___SIZE_T capacity, count, next, peak_bytes;
  enum ___gc_plan_state state;
  ___SIZE_TS source_words, destination_words, objects, frames, still;
  ___SIZE_TS small_words, small_max, largest_request, large_count;
  ___SIZE_TS source_offset;
  int failed;
} ___gc_census;

/* Two sufficient online no-fit bounds. The max-request bound is sharp for
 * tiny objects; the adjacent-bin charge prevents near-capacity requests from
 * making the certificate arbitrarily pessimistic. Each charged payload/link
 * word participates in at most two adjacent-bin pairs. */
static inline int ___gc_copy_section_bound(int workers, ___SIZE_TS small_words,
 ___SIZE_TS maximum, ___SIZE_TS large, ___SIZE_TS capacity, ___SIZE_TS chunk,
 int *sections)
{
 ___SIZE_TS budget,gain,closed,paired,total;
 if(workers<1 || small_words<0 || maximum<0 || maximum>capacity || large<0 ||
    capacity<1 || chunk<1 || small_words>___MAX_FIX-small_words/chunk ||
    large>(INT_MAX-workers)/2)return 0;
 budget=small_words+small_words/chunk;gain=capacity-(maximum?maximum:1)+1;
 closed=budget/gain;paired=(2*budget)/capacity;
 if(paired<closed)closed=paired;
 total=workers+2*large+closed;
 if(total>INT_MAX)return 0;
 *sections=(int)total;return 1;
}
static inline int ___gc_copy_plan_fits(int roots,int copies,int pool)
{return roots>0 && copies>0 && roots<=pool && copies<=pool-roots;}

#define ___GC_SEC_CACHE_BITS 6
#define ___GC_SEC_CACHE_SIZE (1 << ___GC_SEC_CACHE_BITS)
#define ___GC_SEC_CACHE_MASK (___GC_SEC_CACHE_SIZE - 1)

typedef struct ___collector_worker_struct
  {
    struct ___virtual_machine_state_struct *vm;
    int id; /* work authority; never derived from a native carrier address */
    ___gc_worker_phase phase;
    ___gc_census *census; /* nonnull only during the closed read-only preflight */
    struct ___processor_state_struct *carrier; /* collective/actlog adapter */
    ___gc_resume_space *reserve; /* explicit finite restoration-space loan */
    ___gc_worker_arena arena; /* private destination, never the scanned origin */
    ___gc_copy_request copy_request;
    ___SIZE_TS copied_source_words; /* settled unique heap/frame source spans */
    ___SIZE_TS copied_words; /* forwarding wins and captured frames */
    ___SIZE_TS destination_revisits;
    ___SIZE_TS duplicate_scans; /* tasks discharged by another scan owner */
    /* Private, unpublished allocation and first-field repair are separate
     * debts. Neither chunk completion nor a forwarding loss pays them. */
    ___WORD *copy_begin_;
    ___WORD *copy_past_;
    ___WORD *tail_cell_;
    ___SIZE_TS copy_reserved_words_;
    ___SIZE_TS copy_padding_words_;
    ___SIZE_TS tail_started_;
    ___SIZE_TS tail_completed_;
    ___SIZE_TS frame_accesses_;
    ___SIZE_TS frame_links_;
    /* Transport authority is distinct from object/Tail authority. These
     * cursors are worker-owned, never reconstructed from the allocation tip. */
    ___WORD *local_scan_chunk_;
    ___WORD *active_scan_chunk_;
    ___WORD *active_scan_object_;
    int scan_origin_; /* 1 local frontier, 2 own FIFO, 3 stolen FIFO */
    ___SIZE_TS chunks_published_;
    ___SIZE_TS chunks_claimed_;
    ___SIZE_TS chunks_completed_;
    /* Worker-owned section lookup hints; scoped to (vm, id) without TLS or races. */
    ___msection *scan_state_section_;
    ___WORD *scan_state_base_;
    ___SIZE_TS scan_state_offset_;
    ___SIZE_TS scan_state_epoch_;
    ___msection *census_section_;
    ___WORD *census_base_;
    ___SIZE_TS census_offset_;
    ___SIZE_TS census_epoch_;
    ___msection *sec_cache_[___GC_SEC_CACHE_SIZE];
    ___SIZE_TS sec_cache_epoch_;
    int sec_cache_nb_sections_;
/* start of current group of movable objects being copied by mark_array */
___WORD *alloc_heap_chunk_start_;

/* allocation limit for movable objects in current chunk */
___WORD *alloc_heap_chunk_limit_;

#ifndef ___SINGLE_THREADED_VMS

/* Collector transport gate: successful CAS acquires the published queue.
 * No unlocked head/tail observations or generic ticket-lock grant polling. */
___VOLATILE ___WORD chunk_gate_;
___VOLATILE ___WORD chunks_queued_; /* ordered count for lock-free empty check */

#endif

/* list of complete movable object chunks to scan */
___WORD heap_chunks_to_scan_;

/* fifo of complete movable object chunks remaining to scan */
___WORD *heap_chunks_to_scan_head_;
___WORD *heap_chunks_to_scan_tail_;

/* scan pointer in currently scanned (possibly incomplete) chunk */
___WORD *scan_ptr_;

/* still objects remaining to scan */
___WORD still_objs_to_scan_;

/* indicates if weak references must be traversed */
___BOOL traverse_weak_refs_;

/* GC hash tables reached by GC */
___WORD reached_gc_hash_tables_;

#ifdef ___DEBUG_GARBAGE_COLLECT

/* GC state used for debugging */
int reference_location_; /* where is offending reference located */
___WORD *container_body_; /* body of object containing offending reference */
int mark_array_call_line_; /* where was mark_array called */

#endif
  } ___collector_worker;

typedef struct ___gc_round_struct
  {
    ___WORD epoch; /* monotonically published; exhaustion refuses admission */
    int participant_count; /* closed by the existing collective before scan */
    int worker_count; /* executor census; distinct from frozen root census */
    int coordinator_id; /* active coordinator processor ID for this round */
    int worker_proc[___MAX_PROCESSORS]; /* worker_idx (0..worker_count-1) -> proc_id */
    int proc_worker[___MAX_PROCESSORS]; /* proc_id -> worker_idx, or -1 if non-worker/parked */
    unsigned char active[___MAX_PROCESSORS]; /* 1 if proc_id participates actively in this round */
    ___VOLATILE ___WORD requested_workers; /* 0: all; snapshotted after freeze */
    ___BOOL overflow;     /* one VM result, consumed by every participant */
    ___SIZE_TS source_words; /* frozen allocation census, not a live oracle */
    int source_sections;
    ___SIZE_TS destination_offset; /* round parity, independent of a carrier */
    ___gc_census census;
    int decision; /* 0 undecided, 1 accepted, 2 known refusal, 3 retained */
    int observed[___MAX_PROCESSORS];
    int planned_copy_sections, issued_copy_sections, large_sections;
    ___msection *copy_first, *copy_past, *copy_cursor;
    ___WORD *invalid_copy_cell;
    ___WORD *invalid_copy_body;
    int invalid_copy_worker;
    ___VOLATILE ___WORD frame_gate; /* GC stack/link writers and readers */
    /* Generational Minor GC & mature segregation state for this round */
    int is_minor;
    int evac_selective; /* 1 = selective Immix evacuation of gc_evacuating mature sections */
    int segregate_mature;
    int major_action; /* 0=none, 1=start, 2=drain_satb, 3=remark_sweep, 4=abort */
    int has_wills;
    int has_young_still;
    int card_overflow;
    int hint_count;
    ___msection *young_head;
    ___msection *old_mature_tail;
    int promo_tail_count;
    ___msection *promo_tails[___MAX_PROCESSORS];
    ___SIZE_TS promo_tail_starts[___MAX_PROCESSORS];
    ___SIZE_TS promo_tail_ends[___MAX_PROCESSORS];
    unsigned char promo_tail_is_hole[___MAX_PROCESSORS];
    int major_sweep_nm;
    ___F64 major_remark_r0;
    ___SIZE_TS major_reclaimed_still[___MAX_PROCESSORS];
    ___SIZE_TS major_live_still[___MAX_PROCESSORS];
    ___msection *young_heap_secs[___MAX_PROCESSORS];
    ___gc_card_hint hints[___MAX_PROCESSORS * ___GC_CARD_HINT_CAPACITY];
  } ___gc_round;
static inline void ___gc_copy_acquire (___VOLATILE ___WORD *gate)
{
  while (___COMPARE_AND_SWAP_WORD(gate,0,1) != 0)
    ___CPU_RELAX();
}

static inline void ___gc_copy_release (___VOLATILE ___WORD *gate)
{
  ___FETCH_AND_CLEAR_WORD(gate);
}

static inline int ___gc_arena_reserve
 (___gc_worker_arena *a, ___SIZE_TS words)
{
  if (a->handed_off || a->pending != 0 || words < 0 ||
      words > a->limit-a->cursor) return 0;
  a->pending = a->cursor;
  a->cursor += words;
  a->pending_past = a->cursor;
  return 1;
}

/* Caller supplies the weak-descendant drain and exclusive resume-plan
 * ownership. Epoch checks are not substitutes for that physical boundary.
 * Retired copied prefixes and the final interval enter context accounting
 * exactly once; the RC/still/root domain is never copied or rebound. */
static inline int ___gc_resume_owner_matches
 (const ___gc_resume_space *r, ___processor_state processor)
{
  return processor != 0 && r->context != 0 && r->owner == processor &&
         processor->context == r->context;
}

/* The caller owns the section and supplies its actual destination half.
 * Integer comparisons avoid relational comparisons of unrelated pointers;
 * they validate address bounds, not section lifetime or ownership. */
static inline int ___gc_resume_heap_interval_matches
 (___WORD *section_base, ___WORD *section_past, ___WORD *start,
  ___WORD *cursor, ___WORD *limit)
{
  ___UWORD base = ___CAST(___UWORD,section_base);
  ___UWORD past = ___CAST(___UWORD,section_past);
  ___UWORD first = ___CAST(___UWORD,start);
  ___UWORD current = ___CAST(___UWORD,cursor);
  ___UWORD end = ___CAST(___UWORD,limit);
  return base != 0 && base <= first && first <= current && current <= end &&
         end <= past && ((base | past | first | current | end) % ___WS) == 0;
}

/* Requires the aligned, ordered interval above. Compare remaining words
 * without forming a pointer before the beginning of the destination section. */
static inline int ___gc_resume_heap_needs_refill
 (___WORD *cursor, ___WORD *limit, ___SIZE_TS fudge)
{
  ___UWORD current = ___CAST(___UWORD,cursor);
  ___UWORD end = ___CAST(___UWORD,limit);
  return (end-current)/___WS < ___CAST(___UWORD,fudge);
}

/* Publication postcondition for a validated interval. Remaining words must
 * cover the fudge, so a first closure no larger than that fudge fits in the
 * physical span. This does not observe the generated allocation site. */
static inline int ___gc_published_reserve_fits
 (___WORD *cursor, ___WORD *limit, ___SIZE_TS fudge, ___SIZE_TS first_words)
{
  ___UWORD current = ___CAST(___UWORD,cursor);
  ___UWORD end = ___CAST(___UWORD,limit);
  if (cursor == 0 || limit == 0 || current > end || first_words == 0 ||
      ___CAST(___UWORD,fudge) < ___CAST(___UWORD,first_words))
    return 0;
  return (end - current) / ___WS >= ___CAST(___UWORD,fudge);
}

/* Copy completion, movable resume and a still reservation are separate.
 * shared_overflow is the resize or plan result. movable_resumed is this
 * processor's published heap interval. still_charged is this request's
 * words currently in occupied_words_still. A movable resume answers only
 * a zero-word caller. A positive still caller succeeds only when its own
 * reservation is charged, and then the charge is transferred rather than
 * refunded. Failure with no charge refunds nothing. */
static inline int ___gc_caller_overflow
 (int shared_overflow, int movable_resumed,
  unsigned long requested_words_still, int still_charged)
{
  if (requested_words_still == 0)
    return movable_resumed ? 0 : shared_overflow;
  if (shared_overflow || !still_charged)
    return 1;
  return 0;
}

/* The first refund changes the account. A later call is a no-op. */
static inline int ___still_refund_once
 (int *refunded, long *occupied, long words)
{
  if (refunded == 0 || occupied == 0 || *refunded || words < 0)
    return 0;
  *refunded = 1;
  *occupied -= words;
  return 1;
}

static inline int ___gc_arena_handoff
 (___gc_worker_arena *a, ___gc_resume_space *r, ___WORD epoch)
{
  ___pstate_mem *m;
  if (a->handed_off || a->pending || !a->section ||
      !___gc_resume_owner_matches(r,r->owner) ||
      r->accepted || r->source_worker < 0 || a->epoch != epoch || r->epoch != epoch) return 0;
  m = &r->owner->mem;
  m->heap_msection_ = a->section;
  m->alloc_heap_start_ = a->base;
  m->alloc_heap_ptr_ = a->cursor;
  m->alloc_heap_limit_ = a->physical_limit;
  m->words_prev_msections_ += a->retired_words;
  m->alloc_stack_limit_ = r->stack_floor;
  a->handed_off = 1;
  r->accepted = 1;
  return 1;
}

/* A root domain without an assigned worker tail uses its already reserved
 * stack section's disjoint bottom interval. No extra section is allocated.
 * Caller supplies the same descendant/writer drain as arena_handoff. */
static inline int ___gc_resume_without_arena
 (___gc_resume_space *r, ___WORD epoch)
{
  ___pstate_mem *m;
  if (!___gc_resume_owner_matches(r,r->owner) ||
      r->epoch != epoch || r->accepted || r->loan_used ||
      r->source_worker != -1 ||
      !r->stack_section || r->loan_limit-r->loan_base <= 2) return 0;
  m = &r->owner->mem;
  m->heap_msection_ = r->stack_section;
  m->alloc_heap_start_ = m->alloc_heap_ptr_ = r->loan_base;
  m->alloc_heap_limit_ = r->loan_limit-2;
  m->alloc_stack_limit_ = r->loan_limit;
  r->stack_floor = r->loan_limit;
  r->accepted = 1;
  return 1;
}

static inline int ___gc_arena_commit
 (___gc_worker_arena *a, ___WORD *begin, ___WORD *past)
{
  if (a->pending == 0 || a->pending != begin ||
      a->pending_past != past || a->cursor != past) return 0;
  a->pending = 0; a->pending_past = 0;
  return 1;
}


#endif
