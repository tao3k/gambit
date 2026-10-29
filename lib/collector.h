/* Collector-private copy/scan authority. RootOrigin and RootTask remain the
 * sole root population; these records own work and physical restoration only. */
#ifndef ___COLLECTOR_H
#define ___COLLECTOR_H
#include "gambit.h"
#include <limits.h>
#define ___WORD_LOAD_ACQUIRE(p) ___LOAD_GLOBAL_WORD(p)
#define ___gc_atomic_load(p) ___LOAD_GLOBAL_WORD(p)
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
    int source_worker; /* -1: independent empty span; otherwise unique W tail */
  } ___gc_resume_space;

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
/* start of current group of movable objects being copied by mark_array */
___WORD *alloc_heap_chunk_start_;

/* allocation limit for movable objects in current chunk */
___WORD *alloc_heap_chunk_limit_;

#ifndef ___SINGLE_THREADED_VMS

/* Collector transport gate: successful CAS acquires the published queue.
 * No unlocked head/tail observations or generic ticket-lock grant polling. */
___VOLATILE ___WORD chunk_gate_;

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
    ___VOLATILE ___WORD requested_workers; /* 0: all; snapshotted after freeze */
    ___BOOL overflow;     /* one VM result, consumed by every participant */
    ___SIZE_TS source_words; /* frozen allocation census, not a live oracle */
    int source_sections;
    ___SIZE_TS destination_offset; /* round parity, independent of a carrier */
    ___gc_census census;
    int decision; /* 0 undecided, 1 accepted, 2 known refusal, 3 retained */
    int observed[___MAX_PROCESSORS];
    int planned_copy_sections, issued_copy_sections, large_sections;
    ___msection *copy_first, *copy_past;
    ___WORD *invalid_copy_cell;
    ___WORD *invalid_copy_body;
    int invalid_copy_worker;
    ___VOLATILE ___WORD frame_gate; /* GC stack/link writers and readers */
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
static inline int ___gc_arena_handoff
 (___gc_worker_arena *a, ___gc_resume_space *r, ___WORD epoch)
{
  ___pstate_mem *m;
  if (a->handed_off || a->pending || !a->section || !r->context ||
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
  if (!r->context || r->epoch != epoch || r->accepted || r->loan_used ||
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
