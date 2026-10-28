/* Private root origins and their single-executor scan obligations. */
#ifndef ___ROOT_H
#define ___ROOT_H
#include "gambit.h"
#include <limits.h>

enum ___root_task_state {
  ___ROOT_EMPTY, ___ROOT_READY, ___ROOT_CLAIMED,
  ___ROOT_SCANNING, ___ROOT_SCANNED, ___ROOT_DONE
};
enum ___root_origin_kind { ___ROOT_NONE, ___ROOT_RC, ___ROOT_VM, ___ROOT_BANK, ___ROOT_STACK, ___ROOT_SYMKEY, ___ROOT_GLOBALS };
/* This names the existing multi-VM glos allocation, not a new capacity limit.
 * Keep the allocator and view admission on the same physical extent. */
#define ___GLOBALS_CAPACITY 20000

/* One immutable extent per VM round. Storage remains on the coordinator's
 * C stack until every shard and the collective complete. Unknown work retains
 * this invocation; neither a local DONE nor count equality releases it. */
typedef struct ___global_root_snapshot_struct {
  ___virtual_machine_state vm;
  ___UWORD epoch;
  int count, participants;
  unsigned char shards[___MAX_PROCESSORS]; /* 0 absent, 1 leased, 2 complete */
} ___global_root_snapshot;

typedef struct ___global_root_source_struct {
  ___global_state global;
  ___virtual_machine_state vm;
  int count, participants, participant, lo, hi;
  const ___global_root_snapshot *snapshot;
  ___UWORD snapshot_epoch;
} ___global_root_source;

typedef struct ___root_origin_struct {
  enum ___root_origin_kind kind;
  union {
    ___rc_domain *rc;
    ___virtual_machine_state vm;
    ___execution_context *bank;
    ___execution_context *stack;
    ___global_state symkey;
    const ___global_root_source *globals;
  } source;
} ___root_origin;
typedef struct ___root_task_struct {
  ___root_origin origin;
  ___processor_state executor;
  ___UWORD epoch;
  ___SIZE_T scan_leases;
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

/* VM tasks are confined to the coordinator's live C invocation. The caller
 * supplies quiescence before publication and holds VM/round lifetime beyond
 * DONE. init is only for a fresh, unexposed record, never an unknown task. */
extern void ___root_task_init(___root_task*,___UWORD);
extern ___BOOL ___root_task_publish_vm(___root_task*,___virtual_machine_state,
                                      ___processor_state,___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim_vm(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan_vm(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish_vm(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed_vm(___root_task*,___processor_state,___UWORD);

/* Bank tasks borrow the current participant's stable VM context. Existing
 * safepoints/collective hold its writers and storage through the entire GC.
 * Stack/frame pointers and pc are not part of this bank root domain. */
extern ___BOOL ___root_task_publish_bank(___root_task*,___execution_context*,
                                        ___processor_state,___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim_bank(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan_bank(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish_bank(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed_bank(___root_task*,___processor_state,___UWORD);

/* Stack roots include live active-frame slots and the break-frame anchor.
 * The original scanner may rewrite frame links/copy captured tails in place.
 * Normal return alone completes its borrow; unknown work must never requeue. */
extern ___BOOL ___root_task_publish_stack(___root_task*,___execution_context*,
                                         ___processor_state,___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim_stack(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan_stack(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish_stack(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed_stack(___root_task*,___processor_state,___UWORD);
/* Two global symbol/keyword table anchor cells, scanned by the current VM
 * coordinator. Caller holds the actual outer registry/VM lifetime and excludes
 * admitted writers; a VM safepoint alone does not close cross-VM mutation. */
extern ___BOOL ___root_task_publish_symkey(___root_task*,___global_state,
                                          ___processor_state,___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim_symkey(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan_symkey(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish_symkey(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed_symkey(___root_task*,___processor_state,___UWORD);
/* Source storage is fresh caller-owned C metadata, borrowed read-only until
 * task/round completion. Valid metadata pointers and outer VM/registry holds
 * preexist lookup. Snapshot checks are not a cross-VM writer freeze. */
extern ___BOOL ___root_globals_begin(___global_root_snapshot*,___processor_state,___UWORD);
extern ___BOOL ___root_globals_end(___global_root_snapshot*,___processor_state);
extern ___BOOL ___root_globals_partition(int,int,int,int*,int*);
extern ___BOOL ___root_task_publish_globals(___root_task*,___global_root_source*,
                                           ___virtual_machine_state,
                                           ___processor_state,___UWORD,___UWORD*);
extern ___BOOL ___root_task_claim_globals(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_scan_globals(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_finish_globals(___root_task*,___processor_state,___UWORD);
extern ___BOOL ___root_task_completed_globals(___root_task*,___processor_state,___UWORD);
#endif
