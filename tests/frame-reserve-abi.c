/* mem.c includes gambit.h and then mem.h. The one-slot span and RETI
 * coordinate below are the generated ABI literals. They are not recomputed
 * from ___FRAME_RESERVE after mem.h. */
#define HAVE_CONFIG_H
#define ___INCLUDED_FROM_MEM
#define ___VERSION 409008
#include "gambit.h"

_Static_assert(___FRAME_RESERVE == 3, "gambit.h ABI reserve");
_Static_assert(___FRAME_SPACE(1) == 4, "gambit.h one-slot span");

#include "mem.h"

#define ABI_FRAME_RESERVE 3
#define ABI_CEILING_DIV(n,m) (((n)+(m)-1)/(m))
#define ABI_ROUND(n,m) (ABI_CEILING_DIV(n,m)*(m))
#define ABI_FRAME_SPACE(n) ABI_ROUND((n)+ABI_FRAME_RESERVE,___FRAME_ALIGN)
#define ABI_FRAME_OVERHEAD(n) (ABI_FRAME_SPACE(n)-(n))
#define ABI_RETI_RA (-ABI_FRAME_OVERHEAD(___NB_GVM_REGS+1))
#define ABI_FRAME_RETI_RA (1-ABI_FRAME_RESERVE-ABI_RETI_RA)

_Static_assert(___FRAME_RESERVE == ABI_FRAME_RESERVE, "mem.h leaves the ABI reserve");
_Static_assert(___FRAME_ALIGN == 4, "selected frame alignment");
_Static_assert(___FRAME_SPACE(1) == 4, "one-slot span after mem.h");
_Static_assert(___FRAME_SPACE(1) == ABI_FRAME_SPACE(1), "RETN one-slot stride");
_Static_assert(___FRAME_RETI_RA == ABI_FRAME_RETI_RA, "RETI root coordinate");
_Static_assert(___FRAME_OVERHEAD(1) == ABI_FRAME_OVERHEAD(1), "one-slot overhead");
_Static_assert(___LARGEST_CONTINUATION_FRAME == ___MAX_NB_FRAME_SLOTS+1+___SUBTYPED_BODY,
               "largest continuation frame");
_Static_assert(___LARGEST_CONTINUATION_FRAME != ___FRAME_RESERVE, "capacity is a separate macro");
_Static_assert(___MSECTION_FUDGE >= ___LARGEST_CONTINUATION_FRAME, "fudge covers the largest frame");
_Static_assert(___FRAME_SPACE(1) != 8196, "capacity expression is not the one-slot span");

#include <stdio.h>

int main(void)
{
  printf("FRAME-ABI reserve=%d one-slot=%d reti=%d capacity=%d\n",
         ___FRAME_RESERVE, ___FRAME_SPACE(1), ___FRAME_RETI_RA,
         ___LARGEST_CONTINUATION_FRAME);
  return 0;
}
