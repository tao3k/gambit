/* File: "mem.c" */

/* Copyright (c) 1994-2026 by Marc Feeley, All Rights Reserved.  */

#define ___INCLUDED_FROM_MEM
#define ___VERSION 409008
#include "gambit.h"

#include "os_setup.h"
#include "os_base.h"
#include "os_thread.h"
#include "os_time.h"
#include "setup.h"
#include "mem.h"
#include "rc.h"
#include "c_intf.h"
#include "actlog.h"

/* The following includes are needed for debugging. */

#include <stdlib.h>
#include <string.h>


/* Internal source organization; inclusion order is part of the contract.
 * Preserve original logical diagnostic coordinates across fragments. */
#if defined(__BASE_FILE__)
#define ___MEM_SOURCE_FILE __BASE_FILE__
#else
#define ___MEM_SOURCE_FILE "mem.c"
#endif

#include "_mem/configuration.inc"
#include "_mem/aligned-allocation.inc"
#include "_mem/rc-allocation.inc"
#include "_mem/root-tasks.inc"
#include "_mem/movable-sections.inc"
#include "_mem/permanent-allocation.inc"
#include "_mem/global-bindings.inc"
#include "_mem/still-refcount.inc"
#include "_mem/object-allocation.inc"
#include "_mem/symbols.inc"
#include "_mem/diagnostics.inc"
#include "_mem/heap-sections.inc"
#include "_mem/copy-reservations.inc"
#include "_mem/continuation-roots.inc"
#include "_mem/rc-roots.inc"
#include "_mem/object-scanning.inc"
#include "_mem/still-sweep.inc"
#include "_mem/memory-lifecycle.inc"
#include "_mem/wills.inc"
#include "_mem/weak-tables.inc"
#include "_mem/hash-table-api.inc"
#include "_mem/capacity-resize.inc"
#include "_mem/root-origins.inc"
#include "_mem/collection-round.inc"
#include "_mem/allocation-limits.inc"
#include "_mem/allocation-statistics.inc"

#undef ___MEM_SOURCE_FILE
