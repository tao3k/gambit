/* VM-owned execution storage. This checks representation and public accessors;
 * reassigning a carrier here does not admit live migration in the runtime. */
#include "gambit.h"
#include "test-entry.h"
#include <stdio.h>
#include <string.h>

#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr,"runtime roles: line %d\n",__LINE__); return 1; } } while (0)

GAMBIT_TEST_MAIN
{
  ___processor_state_struct a, b;
  ___execution_context contexts[2];
  ___collector_worker workers[2];
  ___gc_participant participants[2];
  ___processor_state ___ps = &a;
  ___WORD sentinel[2];
  ___SCMOBJ x, y, z;
  memset(&a,0,sizeof a);
  memset(&b,0,sizeof b);
  memset(contexts,0,sizeof contexts);
  memset(workers,0,sizeof workers);
  memset(participants,0,sizeof participants);
  a.context = &contexts[0];
  b.context = &contexts[1];
  a.collector = &workers[0];
  b.collector = &workers[1];
  workers[0].carrier = &a;
  workers[1].carrier = &b;
  participants[0].context = a.context;
  participants[1].context = b.context;
  ___PSR0 = ___FIX(17);
  ___PSFP = sentinel;
  CHECK(contexts[0].r[0] == ___FIX(17));
  CHECK(contexts[0].fp == sentinel);
  CHECK(contexts[1].r[0] == 0);
  CHECK(___PROCESSOR_SCMOBJ(&a) == ___CONTEXT_PROCESSOR_SCMOBJ(&contexts[0]));
  CHECK(___PROCESSOR_SCMOBJ(&a) != ___PROCESSOR_SCMOBJ(&b));
  /* A collector updates context roots in place; reload those values rather
   * than the pre-collection C locals, then clear every occupied root slot. */
  ___GC_SAVE1(&a, ___FIX(1));
  contexts[0].saved[0] = ___FIX(11);
  ___GC_RESTORE1(&a, x);
  CHECK(x == ___FIX(11) && contexts[0].saved[0] == ___VOID);
  ___GC_SAVE2(&a, ___FIX(2), ___FIX(3));
  contexts[0].saved[0] = ___FIX(12);
  contexts[0].saved[1] = ___FIX(13);
  ___GC_RESTORE2(&a, x, y);
  CHECK(x == ___FIX(12) && y == ___FIX(13));
  CHECK(contexts[0].saved[0] == ___VOID && contexts[0].saved[1] == ___VOID);
  ___GC_SAVE3(&a, ___FIX(4), ___FIX(5), ___FIX(6));
  contexts[0].saved[0] = ___FIX(14);
  contexts[0].saved[1] = ___FIX(15);
  contexts[0].saved[2] = ___FIX(16);
  ___GC_RESTORE3(&a, x, y, z);
  CHECK(x == ___FIX(14) && y == ___FIX(15) && z == ___FIX(16));
  CHECK(contexts[0].saved[0] == ___VOID && contexts[0].saved[1] == ___VOID
        && contexts[0].saved[2] == ___VOID);
  CHECK(contexts[1].saved[0] == 0 && contexts[1].saved[1] == 0
        && contexts[1].saved[2] == 0);
  workers[0].scan_ptr_ = sentinel;
  workers[0].heap_chunks_to_scan_ = ___FIX(29);
  workers[0].arena.base = sentinel;
  workers[0].arena.cursor = sentinel + 1;
  workers[0].arena.limit = sentinel + 2;
  /* Storage cannot disappear merely because the carrier storage is cleared. */
  memset(&a,0,sizeof a);
  CHECK(participants[0].context->r[0] == ___FIX(17));
  CHECK(participants[0].context->fp == sentinel);
  CHECK(workers[0].scan_ptr_ == sentinel);
  CHECK(workers[0].heap_chunks_to_scan_ == ___FIX(29));
  CHECK(participants[1].context->r[0] == 0);
  /* The carrier is a collective adapter, not the root origin or destination
   * arena. Rebinding this representation must not retarget either storage. */
  workers[0].carrier = &b;
  CHECK(participants[0].context == &contexts[0]);
  CHECK(participants[0].context->r[0] == ___FIX(17));
  CHECK(workers[0].arena.base == sentinel);
  CHECK(workers[0].arena.cursor == sentinel + 1);
  CHECK(workers[0].arena.limit == sentinel + 2);
  CHECK(workers[0].scan_ptr_ == sentinel);
  printf("RUNTIME-ROLES-STORAGE-PASS word=%d context=%lu worker=%lu participant=%lu carrier=%lu vm=%lu\n",
    ___WORD_WIDTH, (unsigned long)sizeof contexts[0],
    (unsigned long)sizeof workers[0], (unsigned long)sizeof participants[0],
    (unsigned long)sizeof a, (unsigned long)sizeof(___virtual_machine_state_struct));
  return 0;
}
