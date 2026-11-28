/* Diagnostic image only. Link this file solely when the runtime is compiled
 * with -D___GAMBIT_DEV_RESTORE_PROBE. It is not a production object.
 *
 * GAMBIT_DEV_RESTORE_COLLECTIVE:
 *   unset             return without skipping, exiting, or changing a cursor
 *   positive          real barrier, then witness the bound closure after its
 *                     label, trampoline and four free-field stores
 *   negative          skip only that barrier and exit before cleanup
 *   barrier-positive real barrier and ordinary return, without allocation checks
 *   pair-negative     require rejection of a one-word-short pair before its header
 *   join-positive     arm only when the generated join receiver requests GC
 *   join-negative     bypass the real barrier during that join collection
 *   join-short        reject the short closure during that join collection
 *   rte-positive      collect before the selected interpreted unary RTE
 *   rte-short         reject a one-word-short extent before its header
 *   closure-negative  move the local cursor one word short of the required span
 *                     and require rejection before the closure header store
 * Any other value exits 77. A missed handshake exits 78. This is not a
 * proof of every reader, every allocation, or the acceptance image.
 * DEV-FIRST-CLOSURE-POSITIVE is printed only after the bound closure's label
 * and trampoline stores and the ADD_CLO_ELEM store that completes free
 * fields 0..3. The header store and bump only arm that witness. An invalid
 * or non-closure first observation exits before its header write. The reload
 * hook does not read the uninitialized local ___hp. Direct ___hp updates in
 * the kernel, system and number generators are hooked before the write.
 * The native still, permanent and RC allocation attempts are observed before
 * their allocator calls, including a still attempt that returns from GC. */
#include "gambit.h"
#include "../../../lib/mem.h"
#include "../../../lib/collector.h"
#include "restore-collective-probe.h"

#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef ___DEV_RESTORE_JOIN_LABEL
#define ___DEV_RESTORE_JOIN_LABEL 3
#endif

static atomic_int dev_mode_cached = -1;
static atomic_int dev_resume_cut_armed;
static atomic_int dev_selected, dev_reader_ready, dev_reader_release;
static atomic_int dev_reader_done, dev_p0_before, dev_p0_inside, dev_p0_after;
static atomic_int dev_barrier_passed;
static atomic_int dev_alloc_done;
static atomic_int dev_alloc_claimed;
static _Atomic(___virtual_machine_state) dev_vm;
static ___processor_state dev_reader_owner;
static ___UWORD dev_reader_epoch;

enum {
  DEV_INTENT_NONE = 0,
  DEV_INTENT_ALLOW = 1,
  DEV_INTENT_UNEXPECTED = 2,
  DEV_INTENT_UNSAFE = 3,
  DEV_INTENT_CENSUS = 4
};

typedef struct {
  ___processor_state owner;
  ___execution_context *context;
  ___UWORD epoch;
  ___msection *section;
  ___SIZE_TS half;
  ___WORD *published, *base, *limit;
  ___processor_state bound_owner, pending_owner;
  ___WORD *bound_cursor, *pending_cursor, *tracked_hp, *body;
  const char *bound_host;
  ___SIZE_TS bound_free, bound_words, pending_free, pending_words;
  ___WORD bound_header, pending_header;
  const char *pair_host;
  int pair_line, pair_mask;
  const char *vector_host;
  int vector_line, vector_mask;
  ___WORD vector_fields[3];
  ___WORD pair_car, pair_cdr;
  int armed, reloaded, census_gap, intent, pending;
  int hp_defined, label_ready, field_mask, init_armed;
} dev_alloc_state;

static _Thread_local dev_alloc_state dev_alloc_tls;

static int dev_configured_mode(void)
{
  const char *text;
  int value, expected;
  int cached = atomic_load(&dev_mode_cached);
  if (cached != -1) return cached;
  text = getenv("GAMBIT_DEV_RESTORE_COLLECTIVE");
  value = 0;
  if (text) {
    if (strcmp(text, "positive") == 0) value = 1;
    else if (strcmp(text, "negative") == 0) value = 2;
    else if (strcmp(text, "closure-negative") == 0) value = 3;
    else if (strcmp(text, "barrier-positive") == 0) value = 4;
    else if (strcmp(text, "pair-negative") == 0) value = 5;
    else if (strcmp(text, "join-positive") == 0) value = 11;
    else if (strcmp(text, "join-negative") == 0) value = 12;
    else if (strcmp(text, "join-short") == 0) value = 13;
    else if (strcmp(text, "rte-positive") == 0) value = 16;
    else if (strcmp(text, "rte-short") == 0) value = 17;
    else _Exit(77);
  }
  expected = -1;
  if (!atomic_compare_exchange_strong(&dev_mode_cached, &expected, value))
    return expected;
  return value;
}

static int dev_mode(void)
{
  int mode = dev_configured_mode();
  return mode < 10 ? mode : atomic_load(&dev_resume_cut_armed) ? mode - 10 : 0;
}

static void dev_wait(atomic_int *value, const char *name)
{
  int i;
  for (i = 0; i < 5000 && !atomic_load(value); i++) usleep(1000);
  if (!atomic_load(value)) {
    fprintf(stderr, "DEV-BARRIER-PROBE-TIMEOUT %s\n", name);
    fflush(stderr);
    _Exit(78);
  }
}

static int dev_pid(___processor_state ps)
{
  return ___PROCESSOR_ID(ps, ___VMSTATE_FROM_PSTATE(ps));
}

static int dev_select_vm(___virtual_machine_state vm)
{
  ___virtual_machine_state expected = 0;
  return atomic_compare_exchange_strong(&dev_vm, &expected, vm) || expected == vm;
}

static int dev_arm_cut(___processor_state ps, const char *kind)
{
  int expected = 0;
  ___virtual_machine_state vm;
  if (!ps || dev_pid(ps) != 0) return 0;
  vm = ___VMSTATE_FROM_PSTATE(ps);
  if (vm->processor_count != 2 || !dev_select_vm(vm) ||
      !atomic_compare_exchange_strong(&dev_resume_cut_armed, &expected, 1))
    return 0;
  fprintf(stderr, "DEV-LINKED-%s-GC-REQUEST carrier=0\n", kind);
  fflush(stderr);
  return 1;
}

int ___dev_restore_at_join(___processor_state ps)
{
  int mode = dev_configured_mode();
  return mode >= 11 && mode <= 13 && dev_arm_cut(ps, "JOIN");
}

int ___dev_restore_at_rte(___processor_state ps, ___WORD argument)
{
  int mode = dev_configured_mode();
  return (mode == 16 || mode == 17) && argument == ___FIX(1234567)
    && dev_arm_cut(ps, "RTE");
}

/* The reader publishes both non-atomic identity fields before reader_ready.
 * Other carriers acquire that publication before inspecting either field. */
static int dev_matches_round(___processor_state ps, ___UWORD epoch)
{
  return ps && atomic_load(&dev_reader_ready)
    && atomic_load(&dev_vm) == ___VMSTATE_FROM_PSTATE(ps)
    && epoch == dev_reader_epoch;
}

void ___dev_restore_before_final_read(___processor_state ps, ___UWORD epoch)
{
  int expected = 0;
  ___virtual_machine_state vm;
  if (!dev_mode() || !ps) return;
  vm = ___VMSTATE_FROM_PSTATE(ps);
  if (vm->processor_count != 2 || dev_pid(ps) != 1 || !dev_select_vm(vm)) return;
  if (!atomic_compare_exchange_strong(&dev_selected, &expected, 1)) return;
  dev_reader_owner = ps;
  dev_reader_epoch = epoch;
  atomic_store(&dev_reader_ready, 1);
  dev_wait(&dev_reader_release, "release-reader");
}

void ___dev_restore_after_reader(___processor_state ps, ___UWORD epoch)
{
  if (dev_mode() && dev_matches_round(ps, epoch) && ps == dev_reader_owner)
    atomic_store(&dev_reader_done, 1);
}

int ___dev_restore_before_barrier(___processor_state ps, ___UWORD epoch)
{
  ___virtual_machine_state vm;
  int mode = dev_mode();
  if (!mode || !ps) return 0;
  vm = ___VMSTATE_FROM_PSTATE(ps);
  if (vm->processor_count != 2 || dev_pid(ps) != 0 || atomic_load(&dev_p0_before)
      || !dev_select_vm(vm))
    return 0;
  dev_wait(&dev_reader_ready, "p1-final-old-read");
  if (!dev_matches_round(ps, epoch)) _Exit(74);
  atomic_store(&dev_p0_before, 1);
  /* Skip only this restore barrier. The after hook exits before cleanup. */
  return mode == 2;
}

void ___dev_restore_inside_barrier(___processor_state ps)
{
  int mode = dev_mode();
  if (mode != 0 && mode != 2 && ps && dev_pid(ps) == 0 &&
      atomic_load(&dev_p0_before) && !atomic_load(&dev_p0_after) &&
      atomic_load(&dev_vm) == ___VMSTATE_FROM_PSTATE(ps) &&
      !atomic_exchange(&dev_p0_inside, 1)) {
    /* Reaching this hook proves the real child-message load returned
     * SYNC_WAITING. Release only after observing the held reader there. */
    if (atomic_load(&dev_reader_release) || atomic_load(&dev_reader_done))
      _Exit(74);
    atomic_store(&dev_reader_release, 1);
  }
}

void ___dev_restore_after_barrier(___processor_state ps, ___UWORD epoch)
{
  int mode = dev_mode();
  if (!mode || !dev_matches_round(ps, epoch) || dev_pid(ps) != 0 || !atomic_load(&dev_p0_before)) return;
  if (atomic_load(&dev_barrier_passed)) return;
  if (mode == 2) {
    /* Observe the crossed cut while the reader is still held. Let it
     * finish before exiting; the production cleanup is never reached. */
    if (atomic_load(&dev_p0_inside) || atomic_load(&dev_reader_release) ||
        atomic_load(&dev_reader_done))
      _Exit(74);
    atomic_store(&dev_p0_after, 1);
    atomic_store(&dev_reader_release, 1);
    dev_wait(&dev_reader_done, "negative-reader-done-before-cleanup");
  } else if (!atomic_load(&dev_p0_inside) || !atomic_load(&dev_reader_done)) {
    _Exit(74);
  } else {
    atomic_store(&dev_p0_after, 1);
  }
  fprintf(stderr, "DEV-RESTORE-BARRIER-%s p2 reader-finished=%d observed-after=%d epoch=%lu\n",
          mode == 2 ? "NEGATIVE" : "POSITIVE",
          atomic_load(&dev_reader_done), mode == 2, (unsigned long)epoch);
  fflush(stderr);
  if (mode == 2) _Exit(0);
  atomic_store(&dev_barrier_passed, 1);
}

void ___dev_restore_alloc_expire(___processor_state ps, ___UWORD epoch)
{
  dev_alloc_state *s = &dev_alloc_tls;
  if (s->armed && s->owner == ps && s->epoch != epoch && !atomic_load(&dev_alloc_done)) {
    fprintf(stderr, "DEV-FIRST-ALLOC-INCONCLUSIVE reason=new-collection\n");
    fflush(stderr);
    _Exit(79);
  }
}

void ___dev_restore_alloc_arm(___processor_state ps, ___UWORD epoch)
{
  int mode = dev_mode();
  dev_alloc_state *s;
  if ((mode != 1 && mode != 3 && mode != 5 && mode != 6 && mode != 7) ||
      !atomic_load(&dev_barrier_passed)
      || !dev_matches_round(ps, epoch) || !ps->context)
    return;
  s = &dev_alloc_tls;
  if (s->armed) return;
  s->owner = ps;
  s->context = ps->context;
  s->epoch = epoch;
  s->section = ps->mem.heap_msection_;
  s->half = ps->mem.tospace_offset_;
  s->published = ps->context->hp;
  s->base = ps->mem.alloc_heap_start_;
  s->limit = ps->mem.alloc_heap_limit_;
  if (!s->section || (s->half != 0 && s->half != (___MSECTION_SIZE >> 1)) ||
      !___gc_resume_heap_interval_matches(s->section->base + s->half,
        s->section->base + s->half + (___MSECTION_SIZE >> 1),
        s->base, s->published, s->limit)) {
    fprintf(stderr, "DEV-FIRST-ALLOC-INCONCLUSIVE reason=invalid-publication-grant\n");
    fflush(stderr);
    _Exit(79);
  }
  s->reloaded = 0;
  s->census_gap = 0;
  s->intent = DEV_INTENT_NONE;
  s->pending = 0;
  s->hp_defined = 0;
  s->tracked_hp = 0;
  s->body = 0;
  s->label_ready = 0;
  s->field_mask = 0;
  s->init_armed = 0;
  s->pair_host = 0;
  s->pair_mask = 0;
  s->vector_host = 0;
  s->vector_mask = 0;
  s->armed = 1;
}

static int dev_window(___processor_state ps, dev_alloc_state *s)
{
  if (!ps || !s->armed || atomic_load(&dev_alloc_done)) return 0;
  if (s->owner != ps || s->context != ps->context ||
      s->section != ps->mem.heap_msection_ || s->half != ps->mem.tospace_offset_ ||
      s->base != ps->mem.alloc_heap_start_ || s->limit != ps->mem.alloc_heap_limit_) {
    fprintf(stderr, "DEV-FIRST-ALLOC-INCONCLUSIVE reason=publication-grant-changed\n");
    fflush(stderr);
    _Exit(79);
  }
  return 1;
}

___WORD *___dev_restore_alloc_reload(___processor_state ps, ___WORD *new_hp)
{
  dev_alloc_state *s = &dev_alloc_tls;
  if (!dev_window(ps, s)) return new_hp;
  /* new_hp is the single evaluation of ___PSHEAP. ___D_HEAP declares the
   * local ___hp with no initializer and ___REGISTER is empty, so this hook
   * must not receive or read it. The first call records only new_hp. */
  if (!s->hp_defined) {
    s->tracked_hp = new_hp;
    s->hp_defined = 1;
    s->reloaded = new_hp == s->published;
    s->census_gap = !s->reloaded;
    return new_hp;
  }
  /* A later published cursor that differs from a cursor this probe stored
   * is visible. A local ___hp change that never reached a hooked bump or a
   * heap write is overwritten by this assignment and is not a proven gap. */
  if (s->reloaded && !s->pending && !atomic_load(&dev_alloc_done)
      && new_hp != s->tracked_hp)
    s->census_gap = 1;
  s->tracked_hp = new_hp;
  return new_hp;
}

static int dev_span_inside(dev_alloc_state *s, ___WORD *hp, ___SIZE_TS words)
{
  uintptr_t cursor = (uintptr_t)hp;
  uintptr_t base = (uintptr_t)s->base;
  uintptr_t end = (uintptr_t)s->limit;
  return words > 0 && cursor >= base && cursor < end
    && (cursor - base) % sizeof(___WORD) == 0 && (end - cursor) % sizeof(___WORD) == 0
    && (end - cursor) / sizeof(___WORD) >= (uintptr_t)words;
}

static int dev_cursor_bound(___processor_state ps, dev_alloc_state *s, ___WORD *hp)
{
  return hp == s->published && ps->context->hp == s->published
    && ps->mem.alloc_heap_start_ == s->base
    && ps->mem.alloc_heap_limit_ == s->limit;
}

static int dev_claim_first(void)
{
  int expected = 0;
  return atomic_compare_exchange_strong(&dev_alloc_claimed, &expected, 1);
}

void ___dev_restore_pair_before(___processor_state ps, ___WORD **cursor,
                                const char *host, int line)
{
  dev_alloc_state *s = &dev_alloc_tls;
  ___SIZE_TS words = ___PAIR_SIZE + ___PAIR_BODY;
  ___WORD *hp;
  int mode;
  if (!dev_window(ps, s) || !dev_claim_first()) return;
  hp = *cursor;
  mode = dev_mode();
  if (!s->reloaded || s->census_gap || !dev_cursor_bound(ps, s, hp) ||
      !dev_span_inside(s, hp, words) || (mode != 1 && mode != 5)) {
    fprintf(stderr, "DEV-FIRST-PAIR-REFUSED host=%s line=%d words=%ld\n",
            host, line, (long)words);
    fflush(stderr);
    _Exit(79);
  }
  if (mode == 5) {
    *cursor = s->limit - (words - 1);
    if (dev_span_inside(s, *cursor, words)) _Exit(79);
    fprintf(stderr, "DEV-FIRST-PAIR-NEGATIVE rejected-before-write host=%s line=%d words=%ld room=%ld epoch=%lu carrier=%d\n",
            host, line, (long)words, (long)(s->limit - *cursor),
            (unsigned long)s->epoch, dev_pid(ps));
    fflush(stderr);
    _Exit(0);
  }
  s->pending = 1;
  s->pending_owner = ps;
  s->pending_cursor = hp;
  s->pending_words = words;
  s->pair_host = host;
  s->pair_line = line;
}

___WORD ___dev_restore_pair_value(___processor_state ps, ___WORD *hp,
                                 int index, ___WORD value)
{
  dev_alloc_state *s = &dev_alloc_tls;
  if (!s->pair_host || !dev_window(ps, s)) return value;
  if (hp != s->pending_cursor) _Exit(79);
  if (index == ___PAIR_CAR && !(s->pair_mask & 1)) {
    s->pair_car = value;
    s->pair_mask |= 1;
  } else if (index == ___PAIR_CDR && !(s->pair_mask & 2)) {
    s->pair_cdr = value;
    s->pair_mask |= 2;
  } else
    _Exit(79);
  return value;
}

void ___dev_restore_pair_after(___processor_state ps, ___WORD *hp)
{
  dev_alloc_state *s = &dev_alloc_tls;
  ___WORD *start = s->pending_cursor;
  if (!s->pair_host || !dev_window(ps, s)) return;
  if (hp != start + s->pending_words || s->pair_mask != 3 ||
      start[0] != ___MAKE_HD_WORDS(___PAIR_SIZE, ___sPAIR) ||
      start[___PAIR_BODY+___PAIR_CAR] != s->pair_car ||
      start[___PAIR_BODY+___PAIR_CDR] != s->pair_cdr)
    _Exit(79);
  fprintf(stderr, "DEV-FIRST-PAIR-POSITIVE host=%s line=%d words=%ld init=car-cdr epoch=%lu carrier=%d\n",
          s->pair_host, s->pair_line, (long)s->pending_words,
          (unsigned long)s->epoch, dev_pid(ps));
  fflush(stderr);
  s->pair_host = 0;
  s->pending = 0;
  atomic_store(&dev_alloc_done, 1);
}

___WORD ___dev_restore_vector_header(___processor_state ps, ___WORD **cursor,
                                  ___SIZE_TS fields, const char *host, int line)
{
  dev_alloc_state *s = &dev_alloc_tls;
  ___SIZE_TS words = 3 + ___VECTOR_BODY;
  ___WORD header = ___MAKE_HD_WORDS(fields, ___sVECTOR);
  int mode;
  if (!dev_window(ps, s)) return header;
  mode = dev_mode();
  if (mode != 6 && mode != 7) {
    ___dev_restore_census_other(ps, *cursor, "vector");
    return header;
  }
  if (!dev_claim_first()) return header;
  if (fields != 3 || ___VECTOR_BODY != 1 ||
      strcmp(host, "___H__23__23_cprc_2d_prc_2d_req1") != 0 ||
      !s->reloaded || s->census_gap || !dev_cursor_bound(ps, s, *cursor) ||
      !dev_span_inside(s, *cursor, words)) {
    fprintf(stderr, "DEV-FIRST-RTE-VECTOR-REFUSED host=%s line=%d fields=%ld\n",
            host, line, (long)fields);
    fflush(stderr);
    _Exit(79);
  }
  if (mode == 7) {
    *cursor = s->limit - (words - 1);
    if (dev_span_inside(s, *cursor, words)) _Exit(79);
    fprintf(stderr, "DEV-FIRST-RTE-VECTOR-NEGATIVE rejected-before-write host=%s line=%d words=%ld room=%ld epoch=%lu carrier=%d\n",
            host, line, (long)words, (long)(s->limit - *cursor),
            (unsigned long)s->epoch, dev_pid(ps));
    fflush(stderr);
    _Exit(0);
  }
  s->pending = 1;
  s->pending_cursor = *cursor;
  s->vector_host = host;
  s->vector_line = line;
  return header;
}

___WORD ___dev_restore_vector_value(___processor_state ps, ___WORD *hp,
                                    int index, ___WORD value)
{
  dev_alloc_state *s = &dev_alloc_tls;
  if (!s->vector_host || !dev_window(ps, s)) return value;
  if (hp != s->pending_cursor || index < 0 || index >= 3 ||
      (s->vector_mask & (1 << index))) _Exit(79);
  s->vector_mask |= 1 << index;
  s->vector_fields[index] = value;
  return value;
}

void ___dev_restore_vector_after(___processor_state ps, ___WORD *hp)
{
  dev_alloc_state *s = &dev_alloc_tls;
  ___WORD *start = s->pending_cursor;
  ___SIZE_TS words = 3 + ___VECTOR_BODY;
  int i;
  if (!s->vector_host || !dev_window(ps, s)) return;
  if (hp != start + words || s->vector_mask != 7 ||
      start[0] != ___MAKE_HD_WORDS(3, ___sVECTOR)) _Exit(79);
  for (i = 0; i < 3; i++)
    if (start[___VECTOR_BODY+i] != s->vector_fields[i]) _Exit(79);
  if (s->vector_fields[2] != ___FIX(1234567)) _Exit(79);
  fprintf(stderr, "DEV-FIRST-RTE-VECTOR-POSITIVE host=%s line=%d words=%ld init=all-fields epoch=%lu carrier=%d\n",
          s->vector_host, s->vector_line, (long)words,
          (unsigned long)s->epoch, dev_pid(ps));
  fflush(stderr);
  s->vector_host = 0;
  s->pending = 0;
  atomic_store(&dev_alloc_done, 1);
}

void ___dev_restore_census_native(const char *kind)
{
  dev_alloc_state *s = &dev_alloc_tls;
  /* A still allocation can resume inside C after the collection, before
   * a generated host reloads ___hp. The arm, rather than reload, gates it. */
  if (!dev_window(s->owner, s) || !dev_claim_first()) return;
  fprintf(stderr, "DEV-FIRST-ALLOC-OTHER kind=%s epoch=%lu carrier=%d\n",
          kind, (unsigned long)s->epoch, dev_pid(s->owner));
  fflush(stderr);
  _Exit(79);
}

static void dev_reject_exit(dev_alloc_state *s)
{
  if (s->intent == DEV_INTENT_UNEXPECTED)
    fprintf(stderr, "DEV-FIRST-CLOSURE-UNEXPECTED free=%ld words=%ld host=%s\n",
            (long)s->bound_free, (long)s->bound_words, s->bound_host);
  else if (s->intent == DEV_INTENT_UNSAFE)
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE unsafe-before-write words=%ld free=%ld\n",
            (long)s->bound_words, (long)s->bound_free);
  else
    fprintf(stderr, "DEV-FIRST-CLOSURE-CENSUS-MISSING words=%ld free=%ld nonmacro-census=missing\n",
            (long)s->bound_words, (long)s->bound_free);
  fflush(stderr);
  _Exit(79);
}

void ___dev_restore_alloc_before(___processor_state ps, ___WORD **cursor,
                                ___SIZE_TS free_vars, ___SIZE_TS words, const char *host)
{
  dev_alloc_state *s;
  ___WORD *hp;
  int mode = dev_mode();
  if (!mode || atomic_load(&dev_alloc_done) || !ps) return;
  if (mode == 2 && atomic_load(&dev_p0_before) && !atomic_load(&dev_barrier_passed)) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE premature words=%ld free=%ld\n",
            (long)words, (long)free_vars);
    fflush(stderr);
    _Exit(79);
  }
  s = &dev_alloc_tls;
  /* The claimed closure keeps its binding until its four fields complete.
   * A later closure must not replace that binding or clear it. */
  if (s->pending || s->init_armed) return;
  if (!dev_window(ps, s)) {
    s->intent = DEV_INTENT_NONE;
    return;
  }
  if (!s->hp_defined) {
    fprintf(stderr, "DEV-FIRST-ALLOC-INCONCLUSIVE reason=missing-reload\n");
    fflush(stderr);
    _Exit(79);
  }
  hp = *cursor;
  /* Bind the processor, cursor and range. Do not print POSITIVE and do not
   * claim the global first slot: the following header census exits before
   * the store when this observation is rejected. */
  s->bound_owner = ps;
  s->bound_cursor = hp;
  s->bound_host = host;
  s->bound_free = free_vars;
  s->bound_words = words;
  s->bound_header = ___MAKE_HD_WORDS(free_vars + ___CLO_FREEVARS, ___sPROCEDURE);
  if (!s->reloaded || s->census_gap || !dev_cursor_bound(ps, s, hp))
    s->intent = DEV_INTENT_CENSUS;
  else if (!dev_span_inside(s, hp, words))
    s->intent = DEV_INTENT_UNSAFE;
  else if (mode == 5 || free_vars != 4 ||
           strcmp(host, "___H__23__23_thread_2d_join_2d_wait_21_") != 0)
    s->intent = DEV_INTENT_UNEXPECTED;
  else if (mode == 3) {
    s->intent = DEV_INTENT_NONE;
    if (!dev_claim_first()) return;
    /* Calibrate the same span predicate with the actual generated local
     * cursor. No competing carrier can inject after losing the claim. */
    *cursor = s->limit - (words - 1);
    if (dev_span_inside(s, *cursor, words)) {
      fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE short-span-accepted\n");
      fflush(stderr);
      _Exit(79);
    }
    fprintf(stderr,
            "DEV-FIRST-CLOSURE-NEGATIVE rejected-before-write words=%ld room=%ld epoch=%lu carrier=%d\n",
            (long)words, (long)(s->limit - *cursor), (unsigned long)s->epoch, dev_pid(ps));
    fflush(stderr);
    _Exit(0);
  }
  else
    s->intent = DEV_INTENT_ALLOW;
}

void ___dev_restore_census_other(___processor_state ps, ___WORD *hp,
                                const char *kind)
{
  dev_alloc_state *s;
  int bound;
  if (!ps || !dev_window(ps, &dev_alloc_tls)) return;
  s = &dev_alloc_tls;
  bound = s->intent != DEV_INTENT_NONE && s->bound_owner == ps
    && hp == s->bound_cursor;
  if (atomic_load(&dev_alloc_claimed) || !dev_claim_first()) {
    if (!s->pending) s->intent = DEV_INTENT_NONE;
    return;
  }
  if (bound && s->intent == DEV_INTENT_ALLOW) {
    s->pending = 1;
    s->pending_owner = s->bound_owner;
    s->pending_cursor = s->bound_cursor;
    s->pending_words = s->bound_words;
    s->pending_free = s->bound_free;
    s->pending_header = s->bound_header;
    return;
  }
  if (bound) dev_reject_exit(s);
  if (s->intent != DEV_INTENT_NONE && s->bound_owner == ps) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch cursor\n");
    fflush(stderr);
    _Exit(79);
  }
  fprintf(stderr, "DEV-FIRST-ALLOC-OTHER kind=%s\n", kind ? kind : "unknown");
  fflush(stderr);
  _Exit(79);
}

static void dev_note_bump(dev_alloc_state *s, ___processor_state ps,
                          ___WORD *hp, ___SIZE_TS words)
{
  /* hp is the cursor production already passed into the hooked bump.
   * Ignore it until a reload has stored a defined published cursor. */
  if (!(s->armed && s->owner == ps && s->context == ps->context && s->hp_defined)) return;
  if (s->reloaded && !s->pending && !atomic_load(&dev_alloc_done)
      && hp != s->tracked_hp)
    s->census_gap = 1;
  s->tracked_hp = hp + words;
}

static int dev_header_identity(___processor_state ps, dev_alloc_state *s)
{
  ___WORD *cursor;
  if (!dev_window(ps, s) || ps != s->pending_owner) return 0;
  cursor = s->pending_cursor;
  if (cursor != s->published || s->pending_free != 4) return 0;
  if (!dev_span_inside(s, cursor, s->pending_words)) return 0;
  if (ps->context->hp != s->published
      && ps->context->hp != cursor + s->pending_words)
    return 0;
  return cursor[0] == s->pending_header;
}

static ___SIZE_TS dev_census_move(___processor_state ps, ___WORD *hp,
                                ___SIZE_TS words, const char *kind,
                                int provisional)
{
  dev_alloc_state *s;
  if (!ps || !dev_window(ps, &dev_alloc_tls)) {
    if (ps) dev_note_bump(&dev_alloc_tls, ps, hp, words);
    return words;
  }
  s = &dev_alloc_tls;
  if (atomic_load(&dev_alloc_claimed) || !dev_claim_first()) {
    s->intent = DEV_INTENT_NONE;
    dev_note_bump(s, ps, hp, words);
    return words;
  }
  /* Exit before the caller's +=. A provisional bump is not a committed
   * object; name it and stop so a later closure cannot become first. */
  if (provisional)
    fprintf(stderr,
            "DEV-FIRST-ALLOC-INCONCLUSIVE kind=%s words=%ld reason=provisional-cursor\n",
            kind ? kind : "provisional", (long)words);
  else
    fprintf(stderr, "DEV-FIRST-ALLOC-OTHER kind=%s words=%ld\n",
            kind ? kind : "bump", (long)words);
  fflush(stderr);
  _Exit(79);
  return words;
}

___SIZE_TS ___dev_restore_census_bump(___processor_state ps, ___WORD *hp,
                                     ___SIZE_TS words)
{
  dev_alloc_state *s;
  if (ps && dev_window(ps, &dev_alloc_tls)) {
    s = &dev_alloc_tls;
    if (s->pending && s->pending_owner == ps && hp == s->pending_cursor) {
      if (words != s->pending_words) {
        fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch bump words=%ld\n",
                (long)words);
        fflush(stderr);
        _Exit(79);
      }
      dev_note_bump(s, ps, hp, words);
      return words;
    }
  }
  return dev_census_move(ps, hp, words, "macro-bump", 0);
}

___SIZE_TS ___dev_restore_census_direct(___processor_state ps, ___WORD *hp,
                                       ___SIZE_TS words, const char *kind)
{
  return dev_census_move(ps, hp, words, kind, 0);
}

___SIZE_TS ___dev_restore_census_provisional(___processor_state ps, ___WORD *hp,
                                            ___SIZE_TS words, const char *kind)
{
  return dev_census_move(ps, hp, words, kind, 1);
}

void ___dev_restore_note_cursor(___processor_state ps, ___WORD *hp)
{
  dev_alloc_state *s;
  if (!ps || !dev_mode()) return;
  s = &dev_alloc_tls;
  if (!(s->armed && s->owner == ps && s->hp_defined)) return;
  s->tracked_hp = hp;
}

void ___dev_restore_alloc_after(___processor_state ps, ___WORD *hp)
{
  dev_alloc_state *s;
  if (!ps) return;
  s = &dev_alloc_tls;
  if (!s->pending || s->pending_owner != ps || s->init_armed) return;
  /* Header and bump only. thread-join still executes BEGIN_SETUP_CLO and
   * four ADD_CLO_ELEM stores after this expression returns. */
  if (!dev_header_identity(ps, s) || hp != s->pending_cursor + s->pending_words) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch header words=%ld free=%ld\n",
            (long)s->pending_words, (long)s->pending_free);
    fflush(stderr);
    _Exit(79);
  }
  s->body = s->pending_cursor + ___SUBTYPED_BODY;
  s->label_ready = 0;
  s->field_mask = 0;
  s->init_armed = 1;
}

static void dev_positive(dev_alloc_state *s)
{
  fprintf(stderr,
          "DEV-FIRST-CLOSURE-POSITIVE words=%ld free=4 init=fields-completed label=checked trampoline=sequenced first-allocation=covered-entries epoch=%lu carrier=%d\n",
          (long)s->pending_words, (unsigned long)s->epoch, dev_pid(s->owner));
  fflush(stderr);
  s->pending = 0;
  s->intent = DEV_INTENT_NONE;
  s->init_armed = 0;
  s->label_ready = 0;
  s->field_mask = 0;
  atomic_store(&dev_alloc_done, 1);
}

void ___dev_restore_clo_label(___processor_state ps, ___WORD *ptr, ___WORD label, int index)
{
  dev_alloc_state *s;
  if (!ps || !ptr) return;
  s = &dev_alloc_tls;
  if (!s->init_armed || !s->pending || s->pending_owner != ps) return;
  if (ptr != s->body) return;
  if (!dev_header_identity(ps, s) || index != ___DEV_RESTORE_JOIN_LABEL ||
      ptr[___LABEL_ENTRY_OR_DESCR] != label) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch label\n");
    fflush(stderr);
    _Exit(79);
  }
  if (s->label_ready) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch label-repeat\n");
    fflush(stderr);
    _Exit(79);
  }
  s->label_ready = 1;
}

void ___dev_restore_clo_field(___processor_state ps, ___WORD *ptr,
                             ___SIZE_TS index, ___WORD value)
{
  dev_alloc_state *s;
  ___SIZE_TS offset;
  if (!ps || !ptr) return;
  s = &dev_alloc_tls;
  if (!s->init_armed || !s->pending || s->pending_owner != ps) return;
  if (ptr != s->body) return;
  if (!s->label_ready) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch field-before-label\n");
    fflush(stderr);
    _Exit(79);
  }
  if (index >= 4 || !dev_header_identity(ps, s)
      || s->body != s->pending_cursor + ___SUBTYPED_BODY) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch field index=%ld\n",
            (long)index);
    fflush(stderr);
    _Exit(79);
  }
  offset = (___SIZE_TS)___SUBTYPED_BODY + index + (___SIZE_TS)___CLO_FREEVARS;
  if (offset >= s->pending_words || ptr[index + ___CLO_FREEVARS] != value) {
    fprintf(stderr, "DEV-FIRST-CLOSURE-NEGATIVE write-mismatch field-value index=%ld\n",
            (long)index);
    fflush(stderr);
    _Exit(79);
  }
  s->field_mask |= 1 << (int)index;
  if (s->field_mask != 0xf) return;
  dev_positive(s);
}
