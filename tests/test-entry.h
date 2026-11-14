/* Include after gambit.h. Match the entry selected by the configured builder;
 * standalone C controls do not enter Gambit's generated Scheme main. */
#ifndef GAMBIT_TEST_ENTRY_H
#define GAMBIT_TEST_ENTRY_H

#if defined(___OS_WIN32) && defined(_WINDOWS)
#define GAMBIT_TEST_MAIN \
static int gambit_test_body (void); \
___BEGIN_C_LINKAGE \
int WINAPI WinMain (HINSTANCE instance, HINSTANCE previous, \
                   LPSTR command_line, int show) \
{ \
  (void)instance; (void)previous; (void)command_line; (void)show; \
  return gambit_test_body (); \
} \
___END_C_LINKAGE \
static int gambit_test_body (void)
#else
#define GAMBIT_TEST_MAIN int main (void)
#endif

#endif
