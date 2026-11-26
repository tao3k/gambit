;;; C7 (Family 8/9 multi-VM fault isolation under true multicore load):
;;; Simultaneously maintains:
;;;   - VM-quarantined: holds an unresolved ___VM_RETAINED cleanup debt
;;;   - VM-churner: native OS thread cycling secondary VM setup/cleanup + reader
;;;                 pins + incarnation monotonicity checks
;;;   - VM-primary (p2/p4): 4 concurrent Scheme mutator threads allocating &
;;;                 completing >= 30 independent STW GCs with zero stalls!

(declare (standard-bindings) (extended-bindings))

(c-declare #<<c-end
#include "lifecycle.h"
#include "rc.h"
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

static void c7_retry_backoff(int tries) {
  if (tries < 32) {
    sched_yield();
  } else {
    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 200000L; /* 200 us backoff under oversubscribed CI vCPUs */
    nanosleep(&ts, NULL);
  }
}

extern void ___thread_set_pstate(___processor_state);

static _Atomic int c7_churn_cycles = 0;
static _Atomic int c7_churn_errors = 0;
static _Atomic int c7_registry_retries = 0;
static _Atomic int c7_stop = 0;
static pthread_t c7_churn_thread;
static int c7_churn_started = 0;
static ___virtual_machine_state c7_retained_vm = NULL;

static ___SCMOBJ c7_release_unknown(void *p) {
  (void)p;
  return ___FIX(___UNKNOWN_ERR);
}

static int c7_install_quarantined_vm(___processor_state primary) {
#ifdef ___SINGLE_VM
  (void)primary;
  return 1;
#else
  ___virtual_machine_state vm = calloc(1, sizeof(*vm));
  ___processor_state sec;
  ___SCMOBJ obj;
  if (!vm) return 0;
  if (___setup_vmstate(vm) != ___FIX(___NO_ERR)) {
    free(vm);
    return 0;
  }
  sec = ___PSTATE_FROM_PROCESSOR_ID(0, vm);
  ___thread_set_pstate(sec);
  if (___POINTER_to_SCMOBJ(sec, vm, ___FAL, c7_release_unknown, &obj, 0) != ___FIX(___NO_ERR)) {
    ___cleanup_vmstate(vm);
    ___thread_set_pstate(primary);
    free(vm);
    return 0;
  }
  /* Cleanup must fail and quarantine VM in ___VM_RETAINED without blocking primary VM! */
  if (___cleanup_vmstate(vm) || !vm->lifecycle || vm->lifecycle->phase != ___VM_RETAINED) {
    ___thread_set_pstate(primary);
    return 0;
  }
  ___thread_set_pstate(primary);
  c7_retained_vm = vm;
  return 1;
#endif
}

static void *c7_vm_churn_worker(void *arg) {
#ifdef ___SINGLE_VM
  (void)arg;
  return NULL;
#else
  (void)arg;
  ___WORD last_incarnation = 0;
  while (!atomic_load_explicit(&c7_stop, memory_order_acquire)) {
    ___virtual_machine_state extra = calloc(1, sizeof(*extra));
    if (!extra) {
      atomic_fetch_add(&c7_churn_errors, 1);
      break;
    }
    /* Retry transient vm_registry_try_write() contention with heartbeat vm_registry_flush */
    ___SCMOBJ se = ___FIX(___UNKNOWN_ERR);
    for (int tries = 0; tries < 512; ++tries) {
      se = ___setup_vmstate(extra);
      if (se == ___FIX(___NO_ERR)) break;
      atomic_fetch_add(&c7_registry_retries, 1);
      c7_retry_backoff(tries);
    }
    if (se != ___FIX(___NO_ERR)) {
      fprintf(stderr, "c7: setup_vmstate failed after retries (se=%ld)\n", (long)se);
      atomic_fetch_add(&c7_churn_errors, 1);
      free(extra);
      break;
    }
    ___WORD inc = extra->lifecycle ? extra->lifecycle->incarnation : 0;
    if (inc <= last_incarnation) {
      fprintf(stderr, "c7: incarnation non-monotonic (%ld <= %ld)\n", (long)inc, (long)last_incarnation);
      atomic_fetch_add(&c7_churn_errors, 1);
    }
    last_incarnation = inc;
    ___processor_state sec = ___PSTATE_FROM_PROCESSOR_ID(0, extra);
    ___thread_set_pstate(sec);
    /* Exercise reader borrow/close exclusion on the secondary VM */
    if (!___lifecycle_members_begin(extra) || ___lifecycle_members_close(extra)) {
      fprintf(stderr, "c7: lifecycle_members_begin/close failed\n");
      atomic_fetch_add(&c7_churn_errors, 1);
    }
    ___lifecycle_members_end(extra);
    /* NOTE (SMP Finding #3): ___cleanup_vmstate can return 0 in phase ___VM_DRAINED
     * when vm_registry_try_write() collides with heartbeat vm_registry_flush.
     * Caller MUST retry unlink while DRAINED and NEVER free(extra) while linked! */
    int cleaned = 0;
    for (int tries = 0; tries < 512; ++tries) {
      if (___cleanup_vmstate(extra)) { cleaned = 1; break; }
      if (!extra->lifecycle || extra->lifecycle->phase != ___VM_DRAINED) break;
      atomic_fetch_add(&c7_registry_retries, 1);
      c7_retry_backoff(tries);
    }
    if (!cleaned) {
      fprintf(stderr, "c7: cleanup_vmstate failed (phase=%d)\n",
              extra->lifecycle ? (int)extra->lifecycle->phase : -1);
      atomic_fetch_add(&c7_churn_errors, 1);
      ___thread_set_pstate(NULL);
      break; /* Never free a VM still linked in vm_registry! */
    }
#ifndef ___OS_WIN32
    if (sec->os.fdset.readfds != NULL ||
        sec->os.fdset.writefds != NULL ||
        sec->os.fdset.exceptfds != NULL ||
        sec->os.fdset.size != 0) {
      atomic_fetch_add(&c7_churn_errors, 1);
    }
#endif
    ___thread_set_pstate(NULL);
    free(extra);
    atomic_fetch_add_explicit(&c7_churn_cycles, 1, memory_order_acq_rel);
  }
  return NULL;
#endif
}

static int c7_start_churn(void) {
  atomic_store(&c7_churn_cycles, 0);
  atomic_store(&c7_churn_errors, 0);
  atomic_store(&c7_registry_retries, 0);
  atomic_store(&c7_stop, 0);
  if (pthread_create(&c7_churn_thread, NULL, c7_vm_churn_worker, NULL) != 0)
    return 0;
  c7_churn_started = 1;
  return 1;
}

static int c7_stop_churn_and_check(void) {
  if (!c7_churn_started) return -1;
  atomic_store_explicit(&c7_stop, 1, memory_order_release);
  pthread_join(c7_churn_thread, NULL);
  c7_churn_started = 0;
  if (atomic_load(&c7_churn_errors) != 0) return -2;
#ifndef ___SINGLE_VM
  if (!c7_retained_vm || !c7_retained_vm->lifecycle ||
      c7_retained_vm->lifecycle->phase != ___VM_RETAINED)
    return -3;
#endif
  return atomic_load(&c7_churn_cycles);
}
c-end
)

(include "gc-hammer.scm")

(define c7-install-quarantined (c-lambda () int "___return(c7_install_quarantined_vm(___ps));"))
(define c7-start-churn (c-lambda () int "c7_start_churn"))
(define c7-stop-and-check (c-lambda () int "c7_stop_churn_and_check"))
(define c7-exit (c-lambda (int) void "_Exit(___arg1);"))

(define (run-c7)
  (mc-assert (= (c7-install-quarantined) 1) 'c7-quarantine-install-failed)
  (mc-assert (= (c7-start-churn) 1) 'c7-churn-start-failed)
  (let* ((gc0 (mc-gc-count))
         (res
          (with-gc-hammer
           0.002
           (lambda ()
             ;; Healthy primary VM runs 4 allocating Scheme workers + >= 30 GCs
             (let ((ws
                    (map
                     (lambda (wid)
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let loop ((i 0) (acc 0))
                             (if (< i 2000)
                                 (let ((v (make-vector 32 (+ wid i))))
                                   ;; 50 explicit GCs per worker guarantees >= 50 total GCs even
                                   ;; if all 4 p4 processors coalesce every STW GC in lockstep.
                                   (if (= (modulo i 40) 0) (##gc))
                                   (loop (+ i 1) (+ acc (vector-ref v 0))))
                                 acc)))
                         (string-append "c7-mut-" (number->string wid)))))
                     '(0 1 2 3))))
               (for-each thread-join! ws)))))
         (cycles (c7-stop-and-check))
         (pulses (cdr res))
         (gc-delta (- (mc-gc-count) gc0)))
    (mc-assert (> cycles 0) 'c7-churn-failed cycles)
    (mc-assert (>= gc-delta 30) 'c7-primary-vm-gc-stalled gc-delta)
    (display (list 'C7-MULTI-VM-FAULT-ISOLATION-PASS
                   'procs (mc-processor-count)
                   'secondary-vm-cycles cycles
                   'quarantined-vm-isolated #t
                   'gc-pulses pulses
                   'gc-total gc-delta))
    (newline)
    (force-output)
    ;; Use _Exit like vm-lifecycle.scm because c7_retained_vm intentionally holds retained debt.
    (c7-exit 0)))

(run-c7)
