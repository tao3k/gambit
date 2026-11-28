/* mem.c includes gambit.h and then mem.h. The batch below is that
 * include order's pair and vector layout. It is not ___REST_PARAM_RESERVE
 * and it is not ___MSECTION_FUDGE. A larger grant is not authorization:
 * the roots must already be published and the signed sum must fit.
 * This TU does not execute handler 7 or 9, does not allocate, and does
 * not call fatal_heap_overflow. Exit 0 means the short reserve still
 * undercounts; it is not a production admission. */
#define HAVE_CONFIG_H
#define ___INCLUDED_FROM_MEM
#define ___VERSION 409008
#include "gambit.h"
#include "mem.h"

#define REST_PAIR_WORDS (___PAIR_SIZE + ___PAIR_BODY)
#define REST_PHYSICAL(i, np) ((i) * REST_PAIR_WORDS + (np) + ___VECTOR_BODY)
#define REST_SHORT (___MAX_NB_ARGS + ___MAX_NB_PARMS + ___VECTOR_BODY + ___PAIR_SIZE + ___PAIR_BODY)

_Static_assert(___FRAME_RESERVE == 3, "gambit.h ABI reserve survives mem.h");
_Static_assert(___FRAME_SPACE(1) == 4, "one-slot frame span survives mem.h");
_Static_assert(___PAIR_SIZE == 2, "selected pair size");
_Static_assert(___PAIR_BODY == 1, "selected no-handle pair body");
_Static_assert(___VECTOR_BODY == 1, "selected no-handle vector body");
_Static_assert(REST_PAIR_WORDS == 3, "three words per pending pair");
_Static_assert(REST_PHYSICAL(3000, 1) == 9002, "3000 pairs plus one vector");
_Static_assert(REST_PHYSICAL(4000, 1) == 12002, "4000 pairs plus one vector");
_Static_assert(___REST_PARAM_RESERVE == REST_SHORT, "published reserve counts one word per argument");
_Static_assert(___REST_PARAM_RESERVE == 9220, "short reserve in the selected layout");
_Static_assert(___REST_PARAM_RESERVE < REST_PHYSICAL(4000, 1), "short reserve undercounts 4000 pairs");
_Static_assert(___MSECTION_FUDGE == ___REST_PARAM_RESERVE, "fudge follows the short reserve");
_Static_assert(___MSECTION_FUDGE < REST_PHYSICAL(4000, 1), "fudge does not cover the batch");

static int
rest_signed_sum (___WORD a, ___WORD b, ___WORD *sum)
{
  ___WORD word_max = (___WORD)((~(___UWORD)0) >> 1);

  if (a < 0 || b < 0 || a > word_max - b)
    return 0;
  *sum = a + b;
  return 1;
}

static int
rest_physical (___WORD i, ___WORD np, ___WORD *words)
{
  ___WORD word_max = (___WORD)((~(___UWORD)0) >> 1);
  ___WORD pair_words = (___WORD)REST_PAIR_WORDS;
  ___WORD pairs;
  ___WORD payload;

  if (i < 0 || np < 0 || pair_words < 0)
    return 0;
  if (i != 0 && pair_words > word_max / i)
    return 0;
  pairs = i * pair_words;
  if (!rest_signed_sum (pairs, np, &payload))
    return 0;
  return rest_signed_sum (payload, (___WORD)___VECTOR_BODY, words);
}

/* Roots are an input to this predicate. Production does not publish them. */
static int
rest_batch_authorized (___WORD grant, ___WORD batch, int roots_published)
{
  if (!roots_published || grant < 0 || batch < 0 || grant < batch)
    return 0;
  return 1;
}

static int
unsigned_mask_would_accept (___WORD batch)
{
  return batch >= 0 && (___UWORD)batch <= (___UWORD)-1;
}

#include <stdio.h>

int
main (void)
{
  ___WORD physical_4000 = 0;
  ___WORD physical_3000 = 0;
  ___WORD unused = 0;
  ___WORD word_max = (___WORD)((~(___UWORD)0) >> 1);
  int exact;
  int one_short;
  int reserve_rooted;
  int unrooted;
  int overflow_refused;

  if (!rest_physical (4000, 1, &physical_4000)
      || physical_4000 != (___WORD)REST_PHYSICAL (4000, 1))
    return 1;
  if (!rest_physical (3000, 1, &physical_3000)
      || physical_3000 != (___WORD)REST_PHYSICAL (3000, 1))
    return 1;
  exact = rest_batch_authorized (physical_4000, physical_4000, 1);
  one_short = rest_batch_authorized (physical_4000 - 1, physical_4000, 1);
  reserve_rooted = rest_batch_authorized ((___WORD)___REST_PARAM_RESERVE,
                                          physical_4000, 1);
  unrooted = rest_batch_authorized (word_max, physical_4000, 0);
  overflow_refused = !rest_signed_sum (word_max, 1, &unused);
  if (exact != 1 || one_short != 0 || reserve_rooted != 0 || unrooted != 0
      || !overflow_refused)
    return 2;
  /* The unsigned ceiling accepts this batch and is not authorization. */
  if (!unsigned_mask_would_accept (physical_4000)
      || rest_batch_authorized ((___WORD)___MSECTION_FUDGE, physical_4000, 1))
    return 2;
  printf ("REST-BATCH reserve=%d batch4000=%d batch3000=%d admit-exact=%d admit-one-short=%d admit-reserve=%d admit-unrooted=%d overflow-refused=%d\n",
          (int)___REST_PARAM_RESERVE, (int)physical_4000, (int)physical_3000,
          exact, one_short, reserve_rooted, unrooted, overflow_refused);
  return 0;
}
