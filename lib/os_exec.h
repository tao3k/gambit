/* Parent-prepared Darwin exec-image plan.  Private to the process backend.
 * This does not replace fork: the child still performs Gambit's interrupt,
 * affinity, cwd and environment transitions before replacing its image. */
#ifndef ___OS_EXEC_H
#define ___OS_EXEC_H

#if defined(__APPLE__) && defined(__MACH__)
#include <spawn.h>
#include <paths.h>
#include <stdint.h>

#if defined(POSIX_SPAWN_SETEXEC) && defined(POSIX_SPAWN_CLOEXEC_DEFAULT)
#define ___USE_EXEC_IMAGE_PLAN

typedef struct {
  posix_spawnattr_t attributes;
  posix_spawn_file_actions_t actions;
  int attributes_ready;
  int actions_ready;
  const char *direct_path;
  char **paths;
  size_t path_count;
} ___exec_image_plan;

static void ___exec_image_plan_destroy (___exec_image_plan *plan)
{
  if (plan->actions_ready)
    posix_spawn_file_actions_destroy (&plan->actions);
  if (plan->attributes_ready)
    posix_spawnattr_destroy (&plan->attributes);
  if (plan->paths != NULL)
    ___FREE_MEM (plan->paths);
  memset (plan, 0, sizeof (*plan));
}

/* Copy PATH recipes, not filesystem resolutions.  Relative and empty entries
 * are interpreted only after the child's real chdir.  No allocation, getenv,
 * file-action construction or parent-environment mutation is needed there. */
static int ___exec_image_plan_prepare
  (___exec_image_plan *plan, const char *file, char *const env[], int redirects)
{
  int fd;
  memset (plan, 0, sizeof (*plan));
  if (file[0] == '\0') return 0;
  if (strchr (file, '/') != NULL)
    plan->direct_path = file;
  else
    {
      const char *path = NULL;
      const char *entry;
      char *text;
      size_t count = 1, file_len = strlen (file), path_len, i;
      for (i=0; env[i]!=NULL; ++i)
        if (strncmp (env[i], "PATH=", 5) == 0)
          { path = env[i]+5; break; }
      if (path == NULL) path = _PATH_DEFPATH;
      path_len = strlen (path);
      for (entry=path; *entry!='\0'; ++entry)
        if (*entry == ':') ++count;
      if (file_len > SIZE_MAX-sizeof (char*)-2 ||
          count > (SIZE_MAX-path_len)/(sizeof (char*)+file_len+2))
        return 0;
      plan->paths = ___ALLOC_MEM
        (path_len + count*(sizeof (char*)+file_len+2));
      if (plan->paths == NULL) return 0;
      plan->path_count = count;
      text = (char*)(plan->paths+count);
      entry = path;
      for (i=0; i<count; ++i)
        {
          const char *past = strchr (entry, ':');
          size_t length = past == NULL ? strlen (entry) : (size_t)(past-entry);
          plan->paths[i] = text;
          if (length != 0)
            {
              memcpy (text, entry, length);
              text += length;
              *text++ = '/';
            }
          memcpy (text, file, file_len+1);
          text += file_len+1;
          if (past != NULL) entry = past+1;
        }
    }

  if (posix_spawnattr_init (&plan->attributes) != 0) goto unavailable;
  plan->attributes_ready = 1;
  if (posix_spawn_file_actions_init (&plan->actions) != 0) goto unavailable;
  plan->actions_ready = 1;
  if (posix_spawnattr_setflags (&plan->attributes,
        POSIX_SPAWN_SETEXEC | POSIX_SPAWN_CLOEXEC_DEFAULT) != 0)
    goto unavailable;
  for (fd=STDIN_FILENO; fd<=STDERR_FILENO; ++fd)
    {
      int flags = fcntl (fd, F_GETFD);
      if (flags < 0 && errno != EBADF) goto unavailable;
      /* Snapshot before pipe allocation.  A redirected std fd is materialized
       * by the original child dup2 sequence; other closed/CLOEXEC fds stay so. */
      if (((redirects & (1 << fd)) != 0 ||
           (flags >= 0 && !(flags & FD_CLOEXEC))) &&
          posix_spawn_file_actions_adddup2 (&plan->actions, fd, fd) != 0)
        goto unavailable;
    }
  return 1;

unavailable:
  ___exec_image_plan_destroy (plan);
  return 0; /* The existing fork/execvp path remains authoritative. */
}

/* A successful SETEXEC never returns.  On failure the caller retains its
 * original errno pipe and performs the original execvp fallback, including
 * ENOEXEC shell handling and its exact final error classification. */
static void ___exec_image_plan_replace
  (const ___exec_image_plan *plan, char *const argv[], char *const env[])
{
  size_t i;
  if (plan->direct_path != NULL)
    {
      posix_spawn (NULL, plan->direct_path, &plan->actions,
                   &plan->attributes, argv, env);
      return;
    }
  for (i=0; i<plan->path_count; ++i)
    {
      int status = posix_spawn (NULL, plan->paths[i], &plan->actions,
                                &plan->attributes, argv, env);
      if (status != ENOENT && status != ENOTDIR && status != EACCES)
        return;
    }
}
#endif
#endif
#endif
