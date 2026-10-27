/* Private RC source ownership. No collector arena or task scheduler lives here. */
#ifndef ___RC_H
#define ___RC_H

#include "root.h"

#if defined(___USE_POSIX_THREAD_SYSTEM) || defined(___USE_WIN32_THREAD_SYSTEM)
#define ___RC_LOCK(d) ___MUTEX_LOCK((d)->gate)
#define ___RC_UNLOCK(d) ___MUTEX_UNLOCK((d)->gate)
#define ___RC_DESTROY(d) ___MUTEX_DESTROY((d)->gate)
#ifdef ___USE_POSIX_THREAD_SYSTEM
#define ___RC_INIT(d) ___MUTEX_INIT((d)->gate)
#else
#define ___RC_INIT(d) (___MUTEX_INIT((d)->gate),1)
#endif
#else
#define ___RC_LOCK(d) ((void)0)
#define ___RC_UNLOCK(d) ((void)0)
#define ___RC_DESTROY(d) ((void)0)
#define ___RC_INIT(d) 1
#endif

enum ___rc_phase { ___RC_OPEN, ___RC_FROZEN, ___RC_CLOSING, ___RC_DETACHED };
struct ___rc_domain_struct {
#if defined(___USE_POSIX_THREAD_SYSTEM) || defined(___USE_WIN32_THREAD_SYSTEM)
  ___MUTEX_DECL(gate)
#endif
  ___rc_header head;
  ___processor_state owner;
  ___SIZE_T nodes, borrows;
  enum ___rc_phase phase;
  ___root_task task;
};

/* Cleanup is a transaction: close sources before any still/OS cleanup.
 * Refusal changes nothing. A successful close admits only reference release. */
extern ___BOOL ___rc_prepare_cleanup(___processor_state);
extern void ___rc_cancel_cleanup(___processor_state);
extern const ___SCMOBJ *___borrow_rc_root(___processor_state, void*);
extern void ___return_rc_root(void*);
extern ___BOOL ___try_set_data_rc(___processor_state, void*, ___SCMOBJ);

#endif
