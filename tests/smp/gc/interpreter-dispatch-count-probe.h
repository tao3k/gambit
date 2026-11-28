/* Diagnostic-only generated-C site counters. Atomic increments perturb the
 * workload; their timing is not a performance measurement. */
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static _Atomic unsigned long long dev_rte_normal_count;
static _Atomic unsigned long long dev_rte_hook_count;
static _Atomic unsigned long long dev_app1red_count, dev_app2red_count, dev_app1sub_count, dev_app2sub_count;
static int dev_rte_enabled;

static void dev_rte_report(void)
{
  fprintf(stderr,"DEV-RTE-COUNTS normal=%llu hook=%llu\n",
          atomic_load_explicit(&dev_rte_normal_count,memory_order_relaxed),
          atomic_load_explicit(&dev_rte_hook_count,memory_order_relaxed));
  fprintf(stderr,"DEV-APP-COUNTS app1red=%llu app2red=%llu app1sub=%llu app2sub=%llu\n",
    atomic_load(&dev_app1red_count), atomic_load(&dev_app2red_count),
    atomic_load(&dev_app1sub_count), atomic_load(&dev_app2sub_count));
  fflush(stderr);
}

__attribute__((constructor)) static void dev_rte_start(void)
{
  if (getenv("GAMBIT_DEV_RTE_COUNT")) {
    dev_rte_enabled=1;
    if (atexit(dev_rte_report)!=0) _Exit(77);
  }
}

#define DEV_RTE_NORMAL() do { if(dev_rte_enabled) \
  atomic_fetch_add_explicit(&dev_rte_normal_count,1,memory_order_relaxed); } while(0)
#define DEV_RTE_HOOK() do { if(dev_rte_enabled) \
  atomic_fetch_add_explicit(&dev_rte_hook_count,1,memory_order_relaxed); } while(0)

#define DEV_APP_COUNT(name) do { if(dev_rte_enabled) atomic_fetch_add_explicit(&dev_##name##_count,1,memory_order_relaxed); } while(0)
