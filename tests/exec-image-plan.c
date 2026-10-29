/* Exercise the actual private Darwin plan, including a real image replacement.
 * This is native process coverage, not GC/SMP or package qualification. */
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

static int fail_allocation;
static int live_allocations;
static void *plan_alloc (size_t size)
{
  void *p;
  if (fail_allocation) return NULL;
  p = malloc (size);
  if (p != NULL) ++live_allocations;
  return p;
}
static void plan_free (void *p)
{
  if (p != NULL) { --live_allocations; free (p); }
}
#define ___ALLOC_MEM plan_alloc
#define ___FREE_MEM plan_free
#include "../lib/os_exec.h"

#ifdef ___USE_EXEC_IMAGE_PLAN
extern char **environ;

static void run_plan (___exec_image_plan *plan, char **argv, char **env,
                      const char *directory, int expected, int fallback)
{
  int status;
  pid_t child = fork ();
  assert (child >= 0);
  if (child == 0)
    {
      if (directory != NULL && chdir (directory) != 0) _exit (110);
      ___exec_image_plan_replace (plan, argv, env);
      if (fallback)
        { environ = env; execvp (argv[0], argv); }
      _exit (111);
    }
  while (waitpid (child, &status, 0) < 0) assert (errno == EINTR);
  assert (WIFEXITED (status) && WEXITSTATUS (status) == expected);
}

static void prepare_checks (void)
{
  ___exec_image_plan plan;
  char *env[] = {"PATH=missing::bin:/bin", NULL};
  char *no_path[] = {NULL};
  assert (___exec_image_plan_prepare (&plan, "sh", env, 0));
  assert (plan.path_count == 4);
  assert (!strcmp (plan.paths[0], "missing/sh"));
  assert (!strcmp (plan.paths[1], "sh"));
  assert (!strcmp (plan.paths[2], "bin/sh"));
  assert (!strcmp (plan.paths[3], "/bin/sh"));
  ___exec_image_plan_destroy (&plan);
  ___exec_image_plan_destroy (&plan); /* Idempotent private retirement. */
  assert (live_allocations == 0);
  fail_allocation = 1;
  assert (!___exec_image_plan_prepare (&plan, "sh", env, 0));
  ___exec_image_plan_destroy (&plan);
  assert (live_allocations == 0);
  fail_allocation = 0;
  assert (!___exec_image_plan_prepare (&plan, "", env, 0));
  assert (___exec_image_plan_prepare (&plan, "sh", no_path, 0));
  assert (plan.path_count == 2 && !strcmp (plan.paths[0], "/usr/bin/sh"));
  ___exec_image_plan_destroy (&plan);
}

int main (int argc, char **argv)
{
  ___exec_image_plan plan;
  char executable[4096], directory[4096], path_setting[8192];
  char template[] = "exec-image-plan.XXXXXX";
  char *temporary, *slash;
  char *env[] = {path_setting, "PLAN_PAYLOAD=child", NULL};
  char *child_argv[] = {NULL, "--child", "0", NULL};
  char *shell_argv[] = {"sh", "-c", "test \"$PLAN_PAYLOAD\" = child", NULL};
  int saved_stdout, flags, fd;

  if (argc == 3 && !strcmp (argv[1], "--child"))
    {
      int closed = fcntl (STDOUT_FILENO, F_GETFD) < 0 && errno == EBADF;
      return (closed == atoi (argv[2]) && getenv ("PLAN_PAYLOAD") != NULL) ? 0 : 112;
    }
  assert (realpath (argv[0], executable) != NULL);
  strcpy (directory, executable);
  slash = strrchr (directory, '/'); assert (slash != NULL); *slash = '\0';
  child_argv[0] = strrchr (executable, '/')+1;
  snprintf (path_setting, sizeof (path_setting), "PATH=/this-path-does-not-exist:%s", directory);
  prepare_checks ();
  assert (___exec_image_plan_prepare (&plan, child_argv[0], env, 0));
  run_plan (&plan, child_argv, env, NULL, 0, 0); /* Bare name, kernel-only. */
  ___exec_image_plan_destroy (&plan);

  /* PATH is the explicit child's recipe, not the parent's filesystem lookup. */
  strcpy (path_setting, "PATH=missing:/bin");
  assert (___exec_image_plan_prepare (&plan, "sh", env, 0));
  run_plan (&plan, shell_argv, env, directory, 0, 0);
  ___exec_image_plan_destroy (&plan);
  strcpy (path_setting, "PATH=:");
  assert (___exec_image_plan_prepare (&plan, child_argv[0], env, 0));
  run_plan (&plan, child_argv, env, directory, 0, 0); /* Empty PATH at child cwd. */
  ___exec_image_plan_destroy (&plan);

  saved_stdout = fcntl (STDOUT_FILENO, F_DUPFD_CLOEXEC, 3);
  assert (saved_stdout >= 0);
  assert (close (STDOUT_FILENO) == 0);
  assert (___exec_image_plan_prepare (&plan, executable, env, 0));
  child_argv[2] = "1";
  run_plan (&plan, child_argv, env, NULL, 0, 0);
  ___exec_image_plan_destroy (&plan);
  assert (dup2 (saved_stdout, STDOUT_FILENO) == STDOUT_FILENO);
  flags = fcntl (STDOUT_FILENO, F_GETFD); assert (flags >= 0);
  assert (fcntl (STDOUT_FILENO, F_SETFD, flags | FD_CLOEXEC) == 0);
  assert (___exec_image_plan_prepare (&plan, executable, env, 0));
  run_plan (&plan, child_argv, env, NULL, 0, 0);
  ___exec_image_plan_destroy (&plan);
  assert (fcntl (STDOUT_FILENO, F_SETFD, flags) == 0);

  /* Parent snapshot says closed, but the real child redirect creates stdout. */
  assert (close (STDOUT_FILENO) == 0);
  assert (___exec_image_plan_prepare (&plan, executable, env, 2));
  assert (dup2 (saved_stdout, STDOUT_FILENO) == STDOUT_FILENO);
  child_argv[2] = "0";
  run_plan (&plan, child_argv, env, NULL, 0, 0);
  ___exec_image_plan_destroy (&plan);
  close (saved_stdout);

  /* Kernel ENOEXEC must still permit the existing execvp shell fallback. */
  temporary = mkdtemp (template); assert (temporary != NULL);
  snprintf (directory, sizeof (directory), "%s/plain-script", temporary);
  fd = open (directory, O_CREAT | O_WRONLY | O_EXCL, 0700); assert (fd >= 0);
  assert (write (fd, "exit 23\n", 8) == 8); close (fd);
  assert (___exec_image_plan_prepare (&plan, directory, env, 0));
  { char *script_argv[] = {directory, NULL};
    run_plan (&plan, script_argv, env, NULL, 23, 1); }
  ___exec_image_plan_destroy (&plan);
  unlink (directory); rmdir (temporary);
  assert (live_allocations == 0);
  puts ("EXEC-IMAGE-PLAN-OK");
  return 0;
}
#else
int main (void)
{
  puts ("EXEC-IMAGE-PLAN-NOT-APPLICABLE");
  return 0;
}
#endif
