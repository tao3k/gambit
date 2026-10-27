/* Exercise the adapter on real Windows and its dispatch/return contract on
 * other hosts. The synthetic branch does not qualify the Windows SDK ABI. */
#include <stdio.h>
#include "gambit.h"

#ifndef ___OS_WIN32
#define GAMBIT_TEST_SYNTHETIC_WINMAIN
#define ___OS_WIN32
#ifndef _WINDOWS
#define _WINDOWS
#endif
#define WINAPI
typedef void *HINSTANCE;
typedef char *LPSTR;
#endif

#include "test-entry.h"

static int called;

GAMBIT_TEST_MAIN
{
  called++;
  puts ("TEST-ENTRY-PASS");
#ifdef GAMBIT_TEST_SYNTHETIC_WINMAIN
  return 7;
#else
  return 0;
#endif
}

#ifdef GAMBIT_TEST_SYNTHETIC_WINMAIN
int main (void)
{
  int result = WinMain (0,0,0,0);
  return result == 7 && called == 1 ? 0 : 1;
}
#endif
