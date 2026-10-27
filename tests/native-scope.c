/* Deterministic controls for the write-authority protocol; no Scheme execution.
 * Link with lib/native_scope.c.  A whole-runtime/GC/SMP test is separate.
 */
#include <stdio.h>
#include "gambit.h"
#include "test-entry.h"
#include "native_scope.h"

#define CHECK(x) do { if (!(x)) { \
  fprintf (stderr,"native-scope:%d: %s\n",__LINE__,#x); return 1; \
} } while (0)

GAMBIT_TEST_MAIN
{
  ___native_scope scope;
  ___WORD a, b, c, other, exhausted, before;
  unsigned int role;
  ___native_scope_init (&scope);
  CHECK(___native_scope_prepare (0,1,&a) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_prepare (0,2,&other) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_handoff (&scope,0,a) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_handoff (&scope,0,a) == ___NATIVE_SCOPE_REPLAY);
  CHECK(___native_scope_try_handoff (&scope,0,other) == ___NATIVE_SCOPE_STALE);
  CHECK(___native_scope_try_acquire (&scope,a,1) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_release (&scope,a,1) == ___NATIVE_SCOPE_OK);
  before = ___native_scope_snapshot (&scope);
  CHECK(___native_scope_release (&scope,a,1) == ___NATIVE_SCOPE_REPLAY);
  CHECK(___native_scope_snapshot (&scope) == before);
  CHECK(___native_scope_try_acquire (&scope,a,1) == ___NATIVE_SCOPE_USED);
  for (role=2; role<8; role++)
    if (role != ___NATIVE_SCOPE_DATA)
      CHECK(___native_scope_try_acquire (&scope,a,role) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_prepare (a,2,&b) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_close (&scope,a) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_acquire (&scope,a,2) == ___NATIVE_SCOPE_BUSY);
  CHECK(___native_scope_quiescent (&scope,a) == ___NATIVE_SCOPE_BUSY);
  CHECK(___native_scope_try_handoff (&scope,a,b) == ___NATIVE_SCOPE_BUSY);
  for (role=0; role<8; role++)
    CHECK(___native_scope_release (&scope,a,role) == (role==1 ? ___NATIVE_SCOPE_REPLAY : ___NATIVE_SCOPE_OK));
  CHECK(___native_scope_quiescent (&scope,a) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_handoff (&scope,a,b) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_release (&scope,a,0) == ___NATIVE_SCOPE_STALE);
  CHECK(___native_scope_quiescent (&scope,b) == ___NATIVE_SCOPE_BUSY);
  /* A second interrupted helper cannot be bypassed by old owner's closure. */
  CHECK(___native_scope_prepare (b,3,&c) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_close (&scope,b) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_release (&scope,b,0) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_handoff (&scope,b,c) == ___NATIVE_SCOPE_BUSY);
  CHECK(___native_scope_class_quiescent (&scope,b,0) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_class_quiescent (&scope,b,4) == ___NATIVE_SCOPE_BUSY);
  CHECK(___native_scope_release (&scope,b,4) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_try_handoff (&scope,b,c) == ___NATIVE_SCOPE_OK);
  CHECK(___native_scope_prepare (c,0,&a) == ___NATIVE_SCOPE_INVALID);
  CHECK(___native_scope_prepare (c,256,&a) == ___NATIVE_SCOPE_INVALID);
  CHECK(___native_scope_try_acquire (&scope,c,8) == ___NATIVE_SCOPE_INVALID);
  CHECK(___native_scope_release (&scope,c,7) == ___NATIVE_SCOPE_INVALID);
  exhausted = ___CAST(___WORD,___NATIVE_SCOPE_MAX_GENERATION <<
                                ___NATIVE_SCOPE_GENERATION_SHIFT) |
              (___CAST(___WORD,1)<<___NATIVE_SCOPE_ACTOR_SHIFT);
  CHECK(___native_scope_prepare (exhausted,1,&a) == ___NATIVE_SCOPE_EXHAUSTED);
  puts ("native-scope controls passed");
  return 0;
}
