/* Actual execution-root storage and existing public accessor contract. */
#include "gambit.h"
#include "test-entry.h"
#include <stdio.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr,"execution context storage: line %d\n",__LINE__); return 1; } } while (0)
GAMBIT_TEST_MAIN
{
  ___processor_state_struct a, b;
  ___execution_context roots[2];
  ___processor_state ___ps = &a;
  ___WORD stack[2];
  ___SCMOBJ x, y, z;
  memset(&a,0,sizeof a); memset(&b,0,sizeof b);
  memset(roots,0,sizeof roots);
  a.context=&roots[0]; b.context=&roots[1];
  ___PSR0=___FIX(17); ___PSFP=stack;
  CHECK(roots[0].r[0]==___FIX(17) && roots[0].fp==stack);
  CHECK(roots[1].r[0]==0 && roots[1].fp==0);
  CHECK(___PROCESSOR_SCMOBJ(&a)!=___PROCESSOR_SCMOBJ(&b));
  ___GC_SAVE1(&a,___FIX(1)); roots[0].saved[0]=___FIX(11);
  ___GC_RESTORE1(&a,x);
  CHECK(x==___FIX(11) && roots[0].saved[0]==___VOID);
  ___GC_SAVE2(&a,___FIX(2),___FIX(3));
  roots[0].saved[0]=___FIX(12); roots[0].saved[1]=___FIX(13);
  ___GC_RESTORE2(&a,x,y);
  CHECK(x==___FIX(12) && y==___FIX(13));
  CHECK(roots[0].saved[0]==___VOID && roots[0].saved[1]==___VOID);
  ___GC_SAVE3(&a,___FIX(4),___FIX(5),___FIX(6));
  roots[0].saved[0]=___FIX(14); roots[0].saved[1]=___FIX(15);
  roots[0].saved[2]=___FIX(16);
  ___GC_RESTORE3(&a,x,y,z);
  CHECK(x==___FIX(14) && y==___FIX(15) && z==___FIX(16));
  CHECK(roots[0].saved[0]==___VOID && roots[0].saved[1]==___VOID &&
        roots[0].saved[2]==___VOID);
  CHECK(roots[1].saved[0]==0 && roots[1].saved[1]==0 && roots[1].saved[2]==0);
  /* This is a storage model control, not permission to rebind live roots. */
  a.context=&roots[1]; ___PSR0=___FIX(29);
  CHECK(roots[0].r[0]==___FIX(17) && roots[1].r[0]==___FIX(29));
  CHECK(a.context!=&roots[0] && roots[0].fp==stack);
  printf("EXECUTION-STORAGE-PASS context=%lu carrier=%lu vm=%lu\n",
         (unsigned long)sizeof(roots[0]),(unsigned long)sizeof(a),
         (unsigned long)sizeof(___virtual_machine_state_struct));
  return 0;
}
