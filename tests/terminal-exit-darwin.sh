#!/usr/bin/env bash
# Run against the configured Gambit source tree after its build, on Darwin.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]]
gambit="$(cd "${1:?configured Gambit source directory required}" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gambit-terminal-exit.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
gambopt="-:~~bin=$gambit/bin,~~lib=$gambit/lib,~~include=$gambit/include"
cat > "$work/observer.c" <<'C'
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
static void mark(const char *event, size_t size) {
  int fd = open(getenv("GAMBIT_CLOSE_LOG"), O_WRONLY|O_CREAT|O_APPEND, 0600);
  if (fd >= 0) { (void)write(fd, event, size); close(fd); }
}
static void *observe_open(const char *path, int flags) {
  mark("open\n", 5);
  return dlopen(path, flags);
}
static int observe_close(void *p) {
  mark("close\n", 6);
  return dlclose(p);
}
__attribute__((used,section("__DATA,__interpose")))
static const struct {const void *replacement; const void *original;} open_entry = {observe_open, dlopen};
__attribute__((used,section("__DATA,__interpose")))
static const struct {const void *replacement; const void *original;} entry = {observe_close, dlclose};
C
cat > "$work/module.scm" <<'SCM'
(c-declare "#include <stdio.h>\n#include <stdlib.h>\nstatic void end(void){puts(\"MODULE-ATEXIT\");fflush(stdout);}\n__attribute__((constructor)) static void start(void){puts(\"MODULE-INIT\");fflush(stdout);atexit(end);}\n__attribute__((destructor)) static void stop(void){puts(\"MODULE-DESTRUCTOR\");fflush(stdout);}\n")
(display "MODULE-LOADED\n")
SCM
/usr/bin/clang -dynamiclib "$work/observer.c" -o "$work/observer.dylib"
"$gambit/gsc/gsc" "$gambopt" -dynamic "$work/module.scm"
for mode in normal explicit; do
  code="(begin (load \"$work/module.o1\") (display \"SCHEME-DONE\\n\") (force-output)"
  if [[ "$mode" == explicit ]]; then code="$code (exit 7))"; expected=7; else code="$code)"; expected=0; fi
  : > "$work/$mode.close"
  rc=0
  DYLD_INSERT_LIBRARIES="$work/observer.dylib" GAMBIT_CLOSE_LOG="$work/$mode.close" \
    "$gambit/gsi/gsi" "$gambopt" -e "$code" > "$work/$mode.log" 2>&1 || rc=$?
  [[ "$rc" == "$expected" ]]
  grep -q '^open$' "$work/$mode.close"
  if grep -q '^close$' "$work/$mode.close"; then
    echo "$mode: module closed during terminal cleanup" >&2
    exit 1
  fi
  for line in MODULE-INIT MODULE-LOADED SCHEME-DONE MODULE-DESTRUCTOR MODULE-ATEXIT; do
    [[ "$(grep -c "^$line$" "$work/$mode.log")" == 1 ]]
  done
done
# A normal dlclose remains synchronous even in the standalone process.
cat > "$work/image.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
static void done(void) { puts("IMAGE-ATEXIT"); fflush(stdout); }
__attribute__((constructor)) static void start(void) { puts("IMAGE-INIT"); fflush(stdout); atexit(done); }
__attribute__((destructor)) static void stop(void) { puts("IMAGE-DESTRUCTOR"); fflush(stdout); }
C
cat > "$work/normal-close.scm" <<'SCM'
(c-declare "#include <dlfcn.h>\nstatic int exercise(char *path){void *p=dlopen(path,RTLD_NOW|RTLD_LOCAL); return !p || dlclose(p);}")
(define exercise (c-lambda (char-string) int "exercise"))
(if (not (= 0 (exercise (getenv "GAMBIT_IMAGE_PATH")))) (error "dlclose failed"))
(display "AFTER-CLOSE\n")
(force-output)
SCM
/usr/bin/clang -dynamiclib "$work/image.c" -o "$work/image.dylib"
"$gambit/gsc/gsc" "$gambopt" -dynamic "$work/normal-close.scm"
GAMBIT_IMAGE_PATH="$work/image.dylib" "$gambit/gsi/gsi" "$gambopt" "$work/normal-close.o1" > "$work/normal-close.log" 2>&1
printf 'IMAGE-INIT\nIMAGE-DESTRUCTOR\nIMAGE-ATEXIT\nAFTER-CLOSE\n' > "$work/normal-close.expected"
cmp "$work/normal-close.expected" "$work/normal-close.log"
cp "$gambit/tests/server.scm" "$gambit/tests/server.h" "$work/"
cat > "$work/embed.c" <<'C'
#include <stdio.h>
#include "gambit.h"
#include "server.h"
extern ___mod_or_lnk ___LNK_server__(___global_state);
int main(int argc, char **argv) {
  ___setup_params_struct p; ___setup_params_reset(&p);
  p.version=___VERSION; p.linker=___LNK_server__;
  if (___setup(&p) != ___FIX(___NO_ERR)) return 10;
  char expression[4096];
  if (snprintf(expression,sizeof expression,"(load \"%s\")",argv[1]) >= sizeof expression) return 11;
  char *answer=eval_string(expression);
  if (!answer) return 12;
  ___release_string(answer);
  if (argc > 2) ___cleanup_and_exit_process(9);
  ___cleanup();
  puts("EMBED-CLEANED"); fflush(stdout);
  return 0;
}
C
"$gambit/gsc/gsc" "$gambopt" -exe -cc-options '-D___LIBRARY' -o "$work/embed" "$work/embed.c" "$work/server.scm"
: > "$work/embed.close"
DYLD_INSERT_LIBRARIES="$work/observer.dylib" GAMBIT_CLOSE_LOG="$work/embed.close" \
  "$work/embed" "$work/module.o1" > "$work/embed.log" 2>&1
[[ "$(grep -c '^close$' "$work/embed.close")" == 1 ]]
[[ "$(grep -c '^MODULE-DESTRUCTOR$' "$work/embed.log")" == 1 ]]
[[ "$(grep -c '^MODULE-ATEXIT$' "$work/embed.log")" == 1 ]]
[[ "$(tail -1 "$work/embed.log")" == EMBED-CLEANED ]]
: > "$work/embed-exit.close"
rc=0
DYLD_INSERT_LIBRARIES="$work/observer.dylib" GAMBIT_CLOSE_LOG="$work/embed-exit.close" \
  "$work/embed" "$work/module.o1" exit > "$work/embed-exit.log" 2>&1 || rc=$?
[[ "$rc" == 9 ]]
grep -q '^open$' "$work/embed-exit.close"
if grep -q '^close$' "$work/embed-exit.close"; then
  echo 'explicit process exit closed module during cleanup' >&2
  exit 1
fi
[[ "$(grep -c '^MODULE-DESTRUCTOR$' "$work/embed-exit.log")" == 1 ]]
[[ "$(grep -c '^MODULE-ATEXIT$' "$work/embed-exit.log")" == 1 ]]
printf 'GAMBIT-TERMINAL-EXIT-OK\n'
