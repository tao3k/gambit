/* Diagnostic-only hooks injected into a separately built producer. The
 * negative arm never retires, frees or reuses storage while the reader waits.
 * These hooks are not part of the production runtime or acceptance image. */
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static atomic_int dev_selected, dev_reader_ready, dev_reader_release;
static atomic_int dev_reader_done, dev_p0_before, dev_p0_inside, dev_p0_after;
static atomic_int dev_observer_after, dev_probe_done;
static pthread_t dev_observer;

static int dev_probe_mode(void)
{
  const char *mode = getenv("GAMBIT_DEV_RESTORE_BARRIER_PROBE");
  if (atomic_load(&dev_probe_done)) return 0;
  if (!mode) return 0;
  if (strcmp(mode,"positive")==0) return 1;
  if (strcmp(mode,"negative")==0) return 2;
  _Exit(77);
}

static void dev_wait(atomic_int *value, const char *name)
{
  int i;
  for (i=0; i<5000 && !atomic_load(value); i++) usleep(1000);
  if (!atomic_load(value)) {
    fprintf(stderr,"DEV-BARRIER-PROBE-TIMEOUT %s\n",name);
    fflush(stderr);
    _Exit(78);
  }
}

static int dev_pid(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  return ___PROCESSOR_ID(ps,vm);
}

static void dev_before_final_read(___processor_state ps)
{
  int expected=0;
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  if (!dev_probe_mode() || vm->processor_count!=2 || dev_pid(ps)!=1) return;
  if (!atomic_compare_exchange_strong(&dev_selected,&expected,1)) return;
  atomic_store(&dev_reader_ready,1);
  dev_wait(&dev_reader_release,"release-reader");
}
#define ___GC_TEST_BEFORE_FINAL_RESTORE_READ(slot) dev_before_final_read(___ps)

static void dev_after_restore(___processor_state ps)
{
  if (dev_probe_mode() && dev_pid(ps)==1 && atomic_load(&dev_selected))
    atomic_store(&dev_reader_done,1);
}

static void *dev_monitor(void *unused)
{
  (void)unused;
  dev_wait(&dev_p0_inside,"inside-production-wait-or-negative-bypass");
  usleep(50000);
  atomic_store(&dev_observer_after,atomic_load(&dev_p0_after));
  atomic_store(&dev_reader_release,1);
  return 0;
}

static int dev_before_restore_barrier(___processor_state ps)
{
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  int mode=dev_probe_mode();
  if (!mode || vm->processor_count!=2 || dev_pid(ps)!=0 ||
      atomic_load(&dev_p0_before)) return 0;
  dev_wait(&dev_reader_ready,"p1-final-old-read");
  if (pthread_create(&dev_observer,0,dev_monitor,0)!=0) _Exit(76);
  atomic_store(&dev_p0_before,1);
  if (mode==2) {
    /* The mutant skips only the restore barrier and stops before cleanup. */
    atomic_store(&dev_p0_inside,1);
    atomic_store(&dev_p0_after,1);
    dev_wait(&dev_reader_done,"negative-reader-done-before-cleanup");
    return 1;
  }
  return 0;
}

/* Called from the real setup.c child-message receive in the diagnostic build. */
void dev_probe_inside_barrier(___processor_state ps)
{
  if (dev_probe_mode()==1 && dev_pid(ps)==0 && atomic_load(&dev_p0_before))
    atomic_store(&dev_p0_inside,1);
}

static void dev_after_restore_barrier(___processor_state ps)
{
  int mode=dev_probe_mode();
  if (!mode || dev_pid(ps)!=0 || !atomic_load(&dev_p0_before)) return;
  atomic_store(&dev_p0_after,1);
  if (pthread_join(dev_observer,0)!=0) _Exit(75);
  if (!atomic_load(&dev_reader_done) || atomic_load(&dev_observer_after)!=(mode==2))
    _Exit(74);
  fprintf(stderr,"DEV-RESTORE-BARRIER-%s p2 reader-finished=%d observed-after=%d\n",
          mode==1?"POSITIVE":"NEGATIVE",atomic_load(&dev_reader_done),
          atomic_load(&dev_observer_after));
  fflush(stderr);
  /* The mutant cannot rejoin aligned later barriers. Stop before cleanup. */
  if (mode==2) _Exit(0);
  atomic_store(&dev_probe_done,1);
}
