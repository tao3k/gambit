/* Private root-task protocol. This cut dispatches RC sources only. */
#ifndef ___ROOT_H
#define ___ROOT_H
#include "gambit.h"

enum ___root_task_state {
  ___ROOT_EMPTY, ___ROOT_READY, ___ROOT_CLAIMED,
  ___ROOT_SCANNING, ___ROOT_SCANNED, ___ROOT_DONE
};
typedef struct ___root_task_struct {
  ___rc_domain *source;
  ___processor_state executor;
  ___UWORD epoch;
  enum ___root_task_state state;
} ___root_task;

/* Source attachment/roster lifetime must cover lookup before these calls.
 * A stale raw domain pointer is not a task handle. No requeue/recovery API. */
extern ___BOOL ___root_task_publish(___rc_domain*,___processor_state,
                                    ___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim(___rc_domain*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan(___rc_domain*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish(___rc_domain*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed(___rc_domain*,___processor_state,___UWORD);
#endif
