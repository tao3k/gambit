#line 24 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

#ifdef ___DEBUG_GARBAGE_COLLECT

/*
 * Defining the symbol ENABLE_CONSISTENCY_CHECKS will enable the GC to
 * perform checks that detect when the heap is in an inconsistent
 * state.  This is useful to detect bugs in the GC and the rest of the
 * system.  To perform the consistency checks, the verbosity level in
 * ___GSTATE->setup_params.debug_settings must be at least 1.  The checks are
 * very extensive and consequently are expensive.  They should only be
 * used for debugging.
 */

#define ENABLE_CONSISTENCY_CHECKS


/*
 * Defining the symbol SHOW_FRAMES will cause the GC to print out a
 * trace of the continuation frames that are processed.
 */

#undef SHOW_FRAMES


#define ENABLE_GC_TRACE_PHASES
#define ENABLE_GC_ACTLOG_PHASES
#define ENABLE_GC_ACTLOG_SCAN_COMPLETE_HEAP_CHUNK

#endif


/*---------------------------------------------------------------------------*/

/*
 * Object representation.
 *
 * Memory allocated Scheme objects can be allocated using one of three
 * allocation strategies:
 *
 *    Permanently allocated:
 *      These objects, called 'permanent objects' for short, are never
 *      moved or reclaimed, and all pointers to memory allocated
 *      objects they contain must point to permanent objects.  As a
 *      consequence, the GC does not have to scan permanent objects.
 *      Permanent objects can be allocated on the C heap, but they are
 *      typically allocated in C global variables and structures that
 *      are set up when the program starts up or when a module is
 *      dynamically loaded.
 *
 *    Still dynamically allocated:
 *      These objects, called 'still objects' for short, are allocated
 *      on the C heap.  Still objects are never moved but they can be
 *      reclaimed by the GC.  A mark-and-sweep GC is used to
 *      garbage-collect still objects.
 *
 *    Movable dynamically allocated:
 *      These objects, called 'movable objects' for short, are allocated
 *      in an area of memory that is managed by a compacting GC.  The GC
 *      can move and reclaim movable objects.
 *
 * Scheme objects are encoded using integers of type ___WORD.  A
 * ___WORD either encodes an immediate value or encodes a pointer
 * when the object is memory allocated.  The 2 or 3 lower bits of a
 * ___WORD contain a primary type tag for the object and the other
 * bits contain the immediate value or the pointer.  Because all
 * memory allocated objects are aligned on ___WORD boundaries (and a
 * ___WORD is either 4 or 8 bytes), the 2 or 3 lower bits of pointers
 * are zero and can be used to store the tag without reducing the
 * address space.  When 2 tag bits are used, the four tags are:
 *
 *  immediate:
 *    ___tFIXNUM    object is a small integer (fixnum)
 *    ___tSPECIAL   object is a boolean, character, or other immediate
 *
 *  memory allocated:
 *    if ___USE_SAME_TAG_FOR_PAIRS_AND_SUBTYPED is defined
 *    ___tMEM1 = ___tSUBTYPED = ___tPAIR   subtyped object, possibly a pair
 *    ___tMEM2                             contained object, or a pair
 *    otherwise
 *    ___tMEM1 = ___tSUBTYPED              subtyped object, but not a pair
 *    ___tMEM2 = ___tPAIR                  a pair
 *
 * See the file gambit.h for the tag assignments when 3 tag bits are used.
 *
 * A special type of object exists to support object finalization:
 * 'will' objects.  Wills contain a weak reference to an object, the
 * testator and a strong reference to a procedure, the action
 * procedure.  A will becomes executable when its testator object is
 * not strongly reachable (i.e. the testator object is either
 * unreachable or only reachable using paths from the roots that
 * traverse at least one weak reference).  When the GC detects that a
 * will has become executable it is placed on a list of executable
 * wills.  Following the GC, this list is traversed to invoke the
 * action procedures.
 *
 * All memory allocated objects, including pairs, are composed of at
 * least a head and a body.  The head is a single ___WORD that
 * contains 3 "head" tag bits (the 3 lower bits), a subtype tag (the
 * next 5 bits), and the length of the object in bytes (the remaining
 * bits).  The head is followed by the body of the object, which
 * contains the rest of the information associated with the object.
 * Depending on the subtype, the body can contain raw binary data
 * (such as when the object is a string) and Scheme objects (such as
 * when the object is a vector).  Memory allocated objects have the
 * following layout:
 *
 *      _head_   _____body______
 *     /      \ /               \
 *    +--------+--------+--------+
 *    |llllssst|        |        |
 *    +--------+--------+--------+
 *      ^   ^ ^
 *      |   | |
 * length   | |
 *    subtype head tag
 *
 * Of the 8 possible head tags, only 5 are currently used:
 *
 *    ___PERM     (P) the object is a permanent object
 *    ___STILL    (S) the object is a still object
 *    ___MOVABLE0 (M) the object is a movable object in generation 0
 *    ___FORW     (F) the object has been moved by the GC (counts as 2 tags)
 *
 * Permanent objects have the following layout:
 *
 *      _head_   _____body______
 *     /      \ /               \
 *    +--------+--------+--------+
 *    |       P|        |        |
 *    +--------+--------+--------+
 *
 * Still objects have the following layout:
 *
 *      _link_   _ref__   length   _mark_   _head_   _____body______
 *     /      \ / count\ /      \ /      \ /      \ /               \
 *    +--------+--------+--------+--------+--------+--------+--------+
 *    |        |        |        |        |       S|        |        |
 *    +--------+--------+--------+--------+--------+--------+--------+
 *
 * All still objects are linked in a list using the 'link' field.  The
 * 'refcount' field contains a reference count, which counts the
 * number of pointers to this object that are hidden from the GC
 * (typically these hidden pointers are in C data structures).  When
 * 'refcount' is zero, the object will survive a GC only if it is
 * pointed to by a GC root or a live Scheme object.  The 'length'
 * field contains the length of the object and is only used to
 * maintain statistics on the space allocated.  The 'mark' field is
 * used by the GC to indicate that the object has been marked (at the
 * start of a GC it is set to -1).  The 'mark' field links all objects
 * that have been marked but have not yet been scanned.  It contains a
 * pointer to the next still object that needs to be scanned.
 *
 * Movable objects have the following layout:
 *
 *      _head_   _____body______
 *     /      \ /               \
 *    +--------+--------+--------+
 *    |       M|        |        |
 *    +--------+--------+--------+
 *
 * When a movable object is moved by the GC, the head is replaced
 * with a pointer to the copy, tagged with ___FORW.
 *
 * Layout of body.
 *
 *      _head_   __________body__________
 *     /      \ /                        \
 *    +--------+--------+--------+--------+
 *    |        | field_0| field_1|  etc.  |
 *    +--------+--------+--------+--------+
 *
 * Some types of objects have bodies that only contain pointers to
 * other Scheme objects.  For example, pairs have two fields (car and
 * cdr) and vectors have one field per element.  Other object types
 * have bodies that only contain raw binary data (such as strings and
 * bignums).  The remaining object types have bodies that contain both
 * pointers to Scheme objects and raw binary data.  Their layout is
 * summarized below.
 *
 * Symbols:
 *     subtype = ___sSYMBOL
 *     field_0 = name (a string or a fixnum <n> for a symbol named "g<n>")
 *     field_1 = hash code (non-negative fixnum)
 *     field_2 = link to next symbol in symbol table (#f for uninterned)
 *     field_3 = C pointer to global variable (0 if none exists)
 *
 *     Note: interned symbols must be permanently allocated;
 *           uninterned symbols can be permanent, still or movable
 *
 * Keywords:
 *     subtype = ___sKEYWORD
 *     field_0 = name (a string or a fixnum <n> for a keyword named "g<n>")
 *     field_1 = hash code (non-negative fixnum)
 *     field_2 = link to next symbol in keyword table (#f for uninterned)
 *
 * Procedures:
 *
 *   nonclosures (toplevel procedures)
 *     subtype = ___sPROCEDURE (length contains parameter descriptor)
 *     field_0 = C pointer to this object
 *     field_1 = C pointer to label (only when using gcc)
 *     field_2 = C pointer to host C procedure
 *
 *   closures:
 *     subtype = ___sPROCEDURE
 *     field_0 = C pointer to entry procedure
 *     field_1 = free variable 1
 *     field_2 = free variable 2
 *     ...
 *
 *     Note: the entry procedure must be a nonclosure procedure
 *
 * Return points:
 *     subtype = ___sRETURN
 *     field_0 = return frame descriptor
 *     field_1 = C pointer to label (only when using gcc)
 *     field_2 = C pointer to host C procedure
 *
 * Wills:
 *     subtype = ___sWEAK
 *     field_0 = C pointer to field_0 of next will in list
 *     field_1 = testator object
 *     field_2 = action procedure
 *
 *     Note: wills must be movable
 *
 * GC hash tables:
 *     subtype = ___sWEAK
 *     field_0 = C pointer to field_0 of next GC hash table in list
 *     field_1 = flags
 *     field_2 = count*2 (twice number of active key-value entries)
 *     field_3 = used*2 (twice number of total entries including deleted)
 *     field_4 = key of entry #0
 *     field_5 = value of entry #0
 *     ...
 *
 * Continuations:
 *     subtype = ___sCONTINUATION
 *     field_0 = first frame (C pointer to stack at first and then Scheme obj)
 *     field_1 = dynamic environment (#f when continuation is delimited)
 *
 * Frame:
 *     subtype = ___sFRAME
 *     field_0 = return address
 *     field_1 = frame slot 1
 *     field_2 = frame slot 2
 *     ...
 */


/*---------------------------------------------------------------------------*/

#define ___PSTATE_MEM(var) ___ps->mem.var
#define ___VMSTATE_MEM(var) ___VMSTATE_FROM_PSTATE(___ps)->mem.var

#define tospace_offset          ___PSTATE_MEM(tospace_offset_)
#define msection_free_list      ___PSTATE_MEM(msection_free_list_)
#define stack_msection          ___PSTATE_MEM(stack_msection_)
#define alloc_stack_start       ___PSTATE_MEM(alloc_stack_start_)
#define alloc_stack_ptr         ___PSTATE_MEM(alloc_stack_ptr_)
#define alloc_stack_limit       ___PSTATE_MEM(alloc_stack_limit_)
#define heap_msection           ___PSTATE_MEM(heap_msection_)
#define alloc_heap_start        ___PSTATE_MEM(alloc_heap_start_)
#define alloc_heap_ptr          ___PSTATE_MEM(alloc_heap_ptr_)
#define alloc_heap_limit        ___PSTATE_MEM(alloc_heap_limit_)
#define alloc_heap_chunk_start  ___PSTATE_MEM(alloc_heap_chunk_start_)
#define alloc_heap_chunk_limit  ___PSTATE_MEM(alloc_heap_chunk_limit_)

#ifndef ___SINGLE_THREADED_VMS
#define heap_chunks_to_scan_lock ___PSTATE_MEM(heap_chunks_to_scan_lock_)
#endif

#define heap_chunks_to_scan     ___PSTATE_MEM(heap_chunks_to_scan_)
#define heap_chunks_to_scan_head ___PSTATE_MEM(heap_chunks_to_scan_head_)
#define heap_chunks_to_scan_tail ___PSTATE_MEM(heap_chunks_to_scan_tail_)
#define scan_ptr                ___PSTATE_MEM(scan_ptr_)
#define still_objs_to_scan      ___PSTATE_MEM(still_objs_to_scan_)
#define still_objs              ___PSTATE_MEM(still_objs_)
#define words_still_objs        ___PSTATE_MEM(words_still_objs_)
#define words_still_objs_deferred ___PSTATE_MEM(words_still_objs_deferred_)
#define bytes_allocated_minus_occupied ___PSTATE_MEM(bytes_allocated_minus_occupied_)
#define traverse_weak_refs      ___PSTATE_MEM(traverse_weak_refs_)
#define nonexecutable_wills     ___PSTATE_MEM(nonexecutable_wills_)
#define executable_wills        ___PSTATE_MEM(executable_wills_)
#define reached_gc_hash_tables  ___PSTATE_MEM(reached_gc_hash_tables_)
#define words_prev_msections    ___PSTATE_MEM(words_prev_msections_)
#define stack_fudge_used        ___PSTATE_MEM(stack_fudge_used_)
#define heap_fudge_used         ___PSTATE_MEM(heap_fudge_used_)

#ifdef ___DEBUG_GARBAGE_COLLECT
#define reference_location      ___PSTATE_MEM(reference_location_)
#define container_body          ___PSTATE_MEM(container_body_)
#define mark_array_call_line    ___PSTATE_MEM(mark_array_call_line_)
#endif

#define heap_size               ___VMSTATE_MEM(heap_size_)
#define normal_overflow_reserve ___VMSTATE_MEM(normal_overflow_reserve_)
#define overflow_reserve        ___VMSTATE_MEM(overflow_reserve_)
#define occupied_words_movable  ___VMSTATE_MEM(occupied_words_movable_)
#define occupied_words_still    ___VMSTATE_MEM(occupied_words_still_)
#define the_msections           ___VMSTATE_MEM(the_msections_)
#define alloc_msection          ___VMSTATE_MEM(alloc_msection_)
#define nb_msections_assigned   ___VMSTATE_MEM(nb_msections_assigned_)
#define nb_msections_stacks     ___VMSTATE_MEM(nb_msections_stacks_)
#define target_heap_space_hist  ___VMSTATE_MEM(target_heap_space_hist_)
#define target_heap_space_hist_last ___VMSTATE_MEM(target_heap_space_hist_last_)
#define target_processor_count  ___VMSTATE_MEM(target_processor_count_)

#ifndef ___SINGLE_THREADED_VMS
#define misc_mem_lock           ___VMSTATE_MEM(misc_mem_lock_)
#define alloc_mem_lock          ___VMSTATE_MEM(alloc_mem_lock_)
#define scan_termination_mutex  ___VMSTATE_MEM(scan_termination_mutex_)
#define scan_termination_condvar ___VMSTATE_MEM(scan_termination_condvar_)
#define scan_workers_count      ___VMSTATE_MEM(scan_workers_count_)
#endif

#define nb_gcs                  ___VMSTATE_MEM(nb_gcs_)
#define gc_user_time            ___VMSTATE_MEM(gc_user_time_)
#define gc_sys_time             ___VMSTATE_MEM(gc_sys_time_)
#define gc_real_time            ___VMSTATE_MEM(gc_real_time_)

#define latest_gc_user_time     ___VMSTATE_MEM(latest_gc_user_time_)
#define latest_gc_sys_time      ___VMSTATE_MEM(latest_gc_sys_time_)
#define latest_gc_real_time     ___VMSTATE_MEM(latest_gc_real_time_)
#define latest_gc_heap_size     ___VMSTATE_MEM(latest_gc_heap_size_)
#define latest_gc_alloc         ___VMSTATE_MEM(latest_gc_alloc_)
#define latest_gc_live          ___VMSTATE_MEM(latest_gc_live_)
#define latest_gc_movable       ___VMSTATE_MEM(latest_gc_movable_)
#define latest_gc_still         ___VMSTATE_MEM(latest_gc_still_)

#define custom_msection_alloc   ___VMSTATE_MEM(custom_msection_alloc_)

/* words occupied by this processor by movable objects */

#define words_movable_objs(ps) \
(2*(ps->mem.words_prev_msections_ \
    + (ps->mem.alloc_heap_ptr_ - ps->mem.alloc_heap_start_) \
    + (ps->mem.alloc_stack_start_ - ps->mem.alloc_stack_ptr_)))

/* bytes occupied by this processor */

#define bytes_occupied(ps) \
(___CAST(___F64,ps->mem.words_still_objs_ \
                + ps->mem.words_still_objs_deferred_ \
                + words_movable_objs(___ps)) * ___WS)

/*---------------------------------------------------------------------------*/

#ifdef ___SINGLE_THREADED_VMS

#define ALLOC_MEM_LOCK()
#define ALLOC_MEM_UNLOCK()
#define MISC_MEM_LOCK()
#define MISC_MEM_UNLOCK()

#else

#define ALLOC_MEM_LOCK() ___SPINLOCK_LOCK(alloc_mem_lock)
#define ALLOC_MEM_UNLOCK() ___SPINLOCK_UNLOCK(alloc_mem_lock)
#define MISC_MEM_LOCK() ___SPINLOCK_LOCK(misc_mem_lock)
#define MISC_MEM_UNLOCK() ___SPINLOCK_UNLOCK(misc_mem_lock)

#endif


/*---------------------------------------------------------------------------*/

/*
 * Memory for movable objects (including continuation frames) are
 * allocated in fixed size msections.  Each processor starts off with
 * an msection for its stack (for allocating continuation frames) and
 * an msection for allocating small objects.  Stack allocations are
 * done by decrementing the stack pointer and small objects are
 * allocated by incrementing the heap pointer.  Each msection is
 * divided in two zones of equal size, used as a fromspace and tospace
 * by the garbage collector.  When a processor fills a fromspace, a
 * new msection is obtained from a list of free msections to continue
 * allocating.  The diagram below shows a possible layout of msections
 * for a situation with 3 processors and 12 msections:
 *
 *      sp                                                       hp
 *       v                                                       v
 *   +---+---+-------+  +-----+-+-------+  +----+--+-------+  +--+----+-------+
 * 0 |   |###|       |  |#####| |       |  |####|  |       |  |##|    |       |
 *   +---+---+-------+  +-----+-+-------+  +----+--+-------+  +--+----+-------+
 *
 *    sp                   hp
 *     v                   v
 *   +-+-----+-------+  +--+----+-------+
 * 1 | |#####|       |  |##|    |       |
 *   +-+-----+-------+  +--+----+-------+
 *
 *       sp                                      hp
 *        v                                      v
 *   +----+--+-------+  +----+--+-------+  +-----+-+-------+
 * 2 |    |##|       |  |####|  |       |  |#####| |       |
 *   +----+--+-------+  +----+--+-------+  +-----+-+-------+
 *
 *
 * free list of msections (msections yet to be assigned to processors):
 *   +-------+-------+  +-------+-------+  +-------+-------+
 *   |       |       |  |       |       |  |       |       |
 *   +-------+-------+  +-------+-------+  +-------+-------+
 *
 *
 * In this example, 4 msections are assigned to processor 0.  The first one
 * is being used as a stack to allocate continuation frames.  The other
 * msections of that processor are being used for allocating small objects
 * (two msections are full and the last is not yet full).  There are
 * three msections in the free list of msections.
 *
 * The heap size is defined as the space occupied by still objects and
 * msections at the end of the latest garbage collection.  To determine
 * when to trigger a garbage collection, the memory manager needs to know
 * approximately (but conservatively) how much of the heap is free.  The
 * free heap space is defined as the heap size minus the space of the
 * msections assigned to processors minus the space occupied by still
 * objects minus the overflow reserve.  When an allocation request would
 * cause the free heap space to become negative, a garbage collection is
 * performed first to free space and possibly resize the heap.
 *
 * A given msection can be used for allocating small objects or for
 * allocating continuation frames or for both.  The position of the
 * various pointers is as follows (only the fromspace is shown).
 *
 * Msection only used for allocating movable objects:
 *
 *   <-------------------------- ___MSECTION_SIZE/2 ------------------------->
 *  +----+----+---------------------------------------------------------------+
 *  |obj1|obj2|                                         |<-___MSECTION_FUDGE->|
 *  +----+----+---------------------------------------------------------------+
 *  ^         ^                                         ^                     ^
 *  |         |                                         |                     |
 *  |         alloc_heap_ptr            ___ps->heap_limit      alloc_heap_limit
 *  alloc_heap_start
 *
 * Msection only used for allocating continuation frames:
 *
 *   <-------------------------- ___MSECTION_SIZE/2 ------------------------->
 *  +-----------------------------------------------------------+------+------+
 *  |<-___MSECTION_FUDGE->|                                     |frame2|frame1|
 *  +-----------------------------------------------------------+------+------+
 *  ^                     ^                                     ^             ^
 *  |                     |                                     |             |
 *  alloc_stack_limit     ___ps->context->stack_limit      alloc_stack_ptr             |
 *                                                            alloc_stack_start
 *
 * Msection used for allocating movable objects and allocating
 * continuation frames:
 *
 *   <-------------------------- ___MSECTION_SIZE/2 ------------------------->
 *  +----+-------------------------------------------------------------+------+
 *  |objs|        |<-___MSECTION_FUDGE->|<-___MSECTION_FUDGE->|        |frames|
 *  +----+-------------------------------------------------------------+------+
 *  ^    ^        ^                     ^                     ^        ^      ^
 *  |    |        |                     |                     |        |      |
 *  |    |        |     alloc_heap_limit alloc_stack_limit    |        |      |
 *  |    |        ___ps->heap_limit          ___ps->context->stack_limit        |      |
 *  |    alloc_heap_ptr                                  alloc_stack_ptr      |
 *  alloc_heap_start                                          alloc_stack_start
 */

#define compute_heap_size() \
(compute_msection_size(the_msections->nb_sections) + occupied_words_still)

#define compute_msection_size(nb_sections) \
(___CAST(___SIZE_TS,nb_sections) * ___MSECTION_SIZE)

#define compute_free_heap_space_approximately() \
(heap_size - compute_msection_size(nb_msections_assigned) \
 - occupied_words_still - overflow_reserve)

#define compute_free_heap_space_in_msections(nb_sections) \
(compute_msection_space(nb_sections - nb_msections_stacks) \
 - occupied_words_movable)

#define compute_msection_space(nb_sections) \
(___CAST(___SIZE_TS,nb_sections) * (___MSECTION_SIZE - 2*___MSECTION_FUDGE))

#define compute_nb_msections_needed(words) \
(___CEILING_DIV(words, ___MSECTION_SIZE - 2*___MSECTION_FUDGE))

#define compute_nb_msections_min(processor_count) \
(___MIN_NB_MSECTIONS_PER_PROCESSOR * processor_count)

/*---------------------------------------------------------------------------*/

/* Constants related to representation of permanent and still objects: */

#ifdef ___USE_HANDLES
#define ___PERM_HANDLE 0
#define ___PERM_BODY 2
#else
#define ___PERM_HANDLE ___PERM_BODY
#define ___PERM_BODY 1
#endif
#define ___PERM_HEADER (___PERM_BODY-1)

#define ___STILL_LINK 0
#define ___STILL_REFCOUNT 1
#define ___STILL_LENGTH 2
#define ___STILL_MARK 3
#ifdef ___USE_HANDLES
#define ___STILL_HANDLE 4
#define ___STILL_BODY 6
#else
#define ___STILL_HANDLE ___STILL_BODY
#define ___STILL_BODY (5+1)/************/
#endif
#define ___STILL_HEADER (___STILL_BODY-1)


/* End internal memory fragment. */
