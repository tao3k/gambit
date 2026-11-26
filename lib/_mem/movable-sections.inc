#line 829 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation of movable objects.  */

#include "_mem/section-claim.inc"

/* OS-backed msection storage & CPU+RAM-adaptive STW drained-fromspace page reclamation.
 * Formally verified in gc_fromspace_reclaim.qnt, GcFromspaceReclaimRefinement.lean,
 * AdaptiveHeapScalingRefinement.lean, and adaptive_heap_scaling_pso.c:
 * - Controlled by configure --enable-gc-fromspace-reclaim=auto|off|N and
 *   overridable via -D___GC_FROM_RECLAIM_MIN_SECTIONS=<val>:
 *     0  : adaptive (derives threshold from OS RAM / (64 * CPUs), min_heap/LLC, and max_heap)
 *     <0 : disabled (zero reclamation syscalls)
 *     >0 : explicit minimum msection threshold
 * - Only active for non-executable anonymous mappings (when ___SUPPORT_LOWLEVEL_EXEC
 *   is off and custom_msection_alloc == 0).
 * - Slice 2 Generational + Immix aware: NEVER touches live mature active_offset
 *   halves or active young stack/heap halves; releases drained opposite halves
 *   and both halves of completely unclaimed FREE YOUNG sections (incl. 100%-dead
 *   mature sections returned by Immix Remark).
 */
#ifndef ___GC_FROM_RECLAIM_MIN_SECTIONS
#define ___GC_FROM_RECLAIM_MIN_SECTIONS 0
#endif

#if defined(__APPLE__) && defined(HAVE_SYS_SYSCTL_H)
#include <sys/sysctl.h>
#endif

#if defined(HAVE_SYS_MMAN_H) && !defined(_WIN32) && !defined(___SUPPORT_LOWLEVEL_EXEC) && (defined(MAP_ANON) || defined(MAP_ANONYMOUS))
#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif
#define ___USE_MMAP_MSECTIONS 1

___HIDDEN ___SIZE_T msection_os_page_size ___PVOID
{
  static ___SIZE_T cached = 0;
  ___SIZE_T ps =
#if defined(__ATOMIC_RELAXED)
    __atomic_load_n(&cached, __ATOMIC_RELAXED);
#else
    cached;
#endif
  if (ps == 0)
    {
      long raw =
#ifdef _SC_PAGESIZE
        sysconf(_SC_PAGESIZE);
#else
        4096L;
#endif
      if (raw >= 4096L && (raw & (raw - 1L)) == 0)
        ps = (___SIZE_T)raw;
      else
        ps = 4096;
#if defined(__ATOMIC_RELAXED)
      __atomic_store_n(&cached, ps, __ATOMIC_RELAXED);
#else
      cached = ps;
#endif
    }
  return ps;
}

___HIDDEN ___SIZE_T msection_os_phys_memory_bytes ___PVOID
{
  static ___SIZE_T cached = 0;
  static int probed = 0;
  int done =
#if defined(__ATOMIC_ACQUIRE)
    __atomic_load_n(&probed, __ATOMIC_ACQUIRE);
#else
    probed;
#endif
  if (!done)
    {
      ___SIZE_T mem = 0;
#if defined(__APPLE__) && defined(CTL_HW) && defined(HW_MEMSIZE)
      {
        uint64_t hw_mem = 0;
        size_t sz = sizeof(hw_mem);
        int mib[2] = { CTL_HW, HW_MEMSIZE };
        if (sysctl(mib, 2, &hw_mem, &sz, 0, 0) == 0 && hw_mem > 0)
          mem = (hw_mem > (uint64_t)(~(___SIZE_T)0)) ? (~(___SIZE_T)0) : (___SIZE_T)hw_mem;
      }
#elif defined(_SC_PHYS_PAGES) && defined(_SC_PAGESIZE)
      {
        long pages = sysconf(_SC_PHYS_PAGES);
        long ps = sysconf(_SC_PAGESIZE);
        if (pages > 0 && ps > 0)
          {
            ___SIZE_T up = (___SIZE_T)pages;
            ___SIZE_T ups = (___SIZE_T)ps;
            mem = (up <= (~(___SIZE_T)0) / ups) ? (up * ups) : (~(___SIZE_T)0);
          }
      }
#endif
#if defined(__ATOMIC_RELEASE)
      __atomic_store_n(&cached, mem, __ATOMIC_RELAXED);
      __atomic_store_n(&probed, 1, __ATOMIC_RELEASE);
#else
      cached = mem;
      probed = 1;
#endif
      return mem;
    }
#if defined(__ATOMIC_RELAXED)
  return __atomic_load_n(&cached, __ATOMIC_RELAXED);
#else
  return cached;
#endif
}

___HIDDEN ___SIZE_T msection_os_cpu_count ___PVOID
{
  static ___SIZE_T cached = 0;
  static int probed = 0;
  int done =
#if defined(__ATOMIC_ACQUIRE)
    __atomic_load_n(&probed, __ATOMIC_ACQUIRE);
#else
    probed;
#endif
  if (!done)
    {
      ___SIZE_T cpus = 0;
#ifdef _SC_NPROCESSORS_ONLN
      {
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        if (n > 0)
          cpus = (___SIZE_T)n;
      }
#endif
#if defined(__APPLE__) && defined(CTL_HW) && defined(HW_NCPU)
      if (cpus == 0)
        {
          int hw_cpus = 0;
          size_t sz = sizeof(hw_cpus);
          int mib[2] = { CTL_HW, HW_NCPU };
          if (sysctl(mib, 2, &hw_cpus, &sz, 0, 0) == 0 && hw_cpus > 0)
            cpus = (___SIZE_T)hw_cpus;
        }
#endif
#if defined(__ATOMIC_RELEASE)
      __atomic_store_n(&cached, cpus, __ATOMIC_RELAXED);
      __atomic_store_n(&probed, 1, __ATOMIC_RELEASE);
#else
      cached = cpus;
      probed = 1;
#endif
      return cpus;
    }
#if defined(__ATOMIC_RELAXED)
  return __atomic_load_n(&cached, __ATOMIC_RELAXED);
#else
  return cached;
#endif
}

___HIDDEN ___SIZE_T msection_adaptive_reclaim_min_sections
   (int configured,
    ___SIZE_T phys_mem_bytes,
    ___SIZE_T cpu_count,
    ___SIZE_T min_heap_bytes,
    ___SIZE_T max_heap_bytes)
{
  const ___SIZE_T half_bytes = (___CAST(___SIZE_T, ___MSECTION_SIZE >> 1)) * ___WS;
  const ___SIZE_T floor_min_bytes = (___SIZE_T)16u * 1024u * 1024u;
  const ___SIZE_T adaptive_cap_bytes = (___SIZE_T)128u * 1024u * 1024u;
  const ___SIZE_T fallback_cap_bytes = (___SIZE_T)64u * 1024u * 1024u;
  const ___SIZE_T max_heap_floor_bytes = (___SIZE_T)16u * 1024u * 1024u;
  ___SIZE_T eff_cpus;
  ___SIZE_T cache_floor;
  ___SIZE_T target_bytes;
  ___SIZE_T min_sec;

  if (configured < 0)
    return ~(___SIZE_T)0;
  if (configured > 0)
    return (___SIZE_T)configured;

  eff_cpus = (cpu_count > 0u) ? cpu_count : 1u;

  cache_floor = (min_heap_bytes <= (~(___SIZE_T)0) / 4u)
                  ? (min_heap_bytes * 4u)
                  : (~(___SIZE_T)0);
  if (cache_floor < floor_min_bytes)
    cache_floor = floor_min_bytes;

  if (phys_mem_bytes > 0u)
    {
      ___SIZE_T ram_share = (eff_cpus <= (~(___SIZE_T)0) / 64u)
                              ? (phys_mem_bytes / (64u * eff_cpus))
                              : 0u;
      target_bytes = (ram_share > cache_floor) ? ram_share : cache_floor;
      if (target_bytes > adaptive_cap_bytes)
        target_bytes = adaptive_cap_bytes;
    }
  else
    {
      target_bytes = (cache_floor < fallback_cap_bytes) ? cache_floor : fallback_cap_bytes;
    }

  if (max_heap_bytes > 0u)
    {
      ___SIZE_T cap_share = max_heap_bytes / 4u;
      if (cap_share < max_heap_floor_bytes)
        cap_share = max_heap_floor_bytes;
      if (cap_share < target_bytes)
        target_bytes = cap_share;
    }

  min_sec = (target_bytes + (half_bytes - 1u)) / half_bytes;
  return (min_sec > 0u) ? min_sec : 1u;
}

___HIDDEN ___SIZE_T msection_mmap_size ___PVOID
{
  ___SIZE_T ps = msection_os_page_size();
  ___SIZE_T raw = SECTION_BYTES;
  return (raw + (ps - 1)) & ~(ps - 1);
}

___HIDDEN ___msection *alloc_msection_storage ___PVOID
{
  void *p = mmap(0, msection_mmap_size(), PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANON, -1, 0);
  return (p == MAP_FAILED) ? 0 : ___CAST(___msection*, p);
}

___HIDDEN void free_msection_storage(___msection *s)
{
  if (s != 0)
    (void)munmap(___CAST(void*, s), msection_mmap_size());
}

___HIDDEN void release_drained_source_half(___msection *section, ___SIZE_TS source_offset)
{
  ___SIZE_T ps = msection_os_page_size();
  ___SIZE_TS half_words = (___MSECTION_SIZE >> 1);
  ___SIZE_T half_bytes = (___CAST(___SIZE_T, half_words)) * ___WS;
  ___UWORD lo, hi, plo, phi;
  if (!section || (source_offset != 0 && source_offset != half_words))
    return;
  if (ps < 4096 || (ps & (ps - 1)) != 0)
    return;
  lo = ___CAST(___UWORD, section->base + source_offset);
  /* Pre-addition overflow guards (CBMC-verified against UINTPTR_MAX). */
  if (lo > (~(___UWORD)0) - (___UWORD)half_bytes)
    return;
  hi = lo + (___UWORD)half_bytes;
  if (lo > (~(___UWORD)0) - (___UWORD)(ps - 1))
    return;
  plo = (lo + (___UWORD)(ps - 1)) & ~(___UWORD)(ps - 1);
  phi = hi & ~(___UWORD)(ps - 1);
  if (plo >= lo && phi <= hi && phi > plo)
    {
#if defined(__APPLE__)
      (void)mmap(___CAST(void*, plo), (___SIZE_T)(phi - plo),
                 PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
#elif defined(__linux__) && defined(MADV_DONTNEED)
      (void)madvise(___CAST(void*, plo), (___SIZE_T)(phi - plo), MADV_DONTNEED);
#endif
    }
}

___HIDDEN void reclaim_drained_source_pages
   (___virtual_machine_state ___vms,
    ___msections *sections,
    ___SIZE_TS source_offset,
    int is_minor,
    ___SIZE_T min_heap_bytes,
    ___SIZE_T max_heap_bytes)
{
  ___msection *section;
  ___msection *start_sec;
  ___msection *alloc_ms;
  ___SIZE_T min_sections;
  const ___SIZE_TS half = (___MSECTION_SIZE >> 1);
  if (!___vms || !sections || sections->nb_sections <= 0)
    return;
  min_sections = msection_adaptive_reclaim_min_sections
    (___GC_FROM_RECLAIM_MIN_SECTIONS,
     msection_os_phys_memory_bytes(),
     msection_os_cpu_count(),
     min_heap_bytes,
     max_heap_bytes);
  if ((___SIZE_T)sections->nb_sections < min_sections)
    return;
  alloc_ms = ___vms->mem.alloc_msection_;
  /* On Minor GC, skip mature prefix in O(1) so Minor GC stays O(Y). */
  start_sec = (is_minor && ___vms->mem.mature_tail_ != 0)
                ? ___vms->mem.mature_tail_->next
                : sections->head;
  for (section = start_sec; section != 0; section = section->next)
    {
      if (section->region_age == ___GC_REGION_MATURE)
        {
          ___SIZE_TS opp = half - section->active_offset;
          if (opp != section->active_offset &&
              section_claim_at(section, opp)->stack_state == 0 &&
              !section_claim_at(section, opp)->heap_used)
            release_drained_source_half(section, opp);
        }
      else if (alloc_ms != 0 && section->index > alloc_ms->index)
        {
          /* Unassigned FREE YOUNG section (incl. Immix reclaimed dead sections):
           * release every unclaimed half immediately. */
          if (section_claim_at(section, 0)->stack_state == 0 &&
              !section_claim_at(section, 0)->heap_used)
            release_drained_source_half(section, 0);
          if (section_claim_at(section, half)->stack_state == 0 &&
              !section_claim_at(section, half)->heap_used)
            release_drained_source_half(section, half);
        }
      else
        {
          if (section_claim_at(section, source_offset)->stack_state == 0 &&
              !section_claim_at(section, source_offset)->heap_used)
            release_drained_source_half(section, source_offset);
        }
    }
}
#else
___HIDDEN ___msection *alloc_msection_storage ___PVOID
{
  return ___CAST(___msection*, alloc_mem_aligned_heap(___WORDS(SECTION_BYTES), 1, 0));
}

___HIDDEN void free_msection_storage(___msection *s)
{
  free_mem_aligned_heap(s);
}

___HIDDEN void release_drained_source_half(___msection *section, ___SIZE_TS source_offset)
{
  (void)section;
  (void)source_offset;
}

___HIDDEN void reclaim_drained_source_pages
   (___virtual_machine_state ___vms,
    ___msections *sections,
    ___SIZE_TS source_offset,
    int is_minor,
    ___SIZE_T min_heap_bytes,
    ___SIZE_T max_heap_bytes)
{
  (void)___vms;
  (void)sections;
  (void)source_offset;
  (void)is_minor;
  (void)min_heap_bytes;
  (void)max_heap_bytes;
}
#endif

/*
 * 'find_msection (ms, ptr)' finds the position in the 'ms->sections'
 * array of the msection that contains the pointer 'ptr'.  More
 * precisely, if ___ALLOC_MEM_UP is defined, it returns the integer
 * 'i' (-1<=i<=n-1) such that 'ptr' is between the start of section i
 * and section i+1.  -1 is returned if 'ptr' is lower than the lowest
 * section and 'n' is returned if 'ptr' is not lower than the highest
 * section.  If ___ALLOC_MEM_UP is not defined, it returns the integer
 * 'i' (0<=i<=n) such that 'ptr' is between the start of section i and
 * section i-1.  n is returned if 'ptr' is lower than the lowest
 * section and 0 is returned if 'ptr' is not lower than the highest
 * section.
 */

___HIDDEN int find_msection
   ___P((___msections *ms,
         void *ptr),
        (ms,
         ptr)
___msections *ms;
void *ptr;)
{
  int ns = ms->nb_sections;
  ___msection **sections = ms->sections;
  int lo, hi;

#ifdef ___ALLOC_MEM_UP
  if (ns == 0 ||
      ptr < ___CAST(void*,sections[0]))
    return -1;
#else
  if (ns == 0 ||
      ptr < ___CAST(void*,sections[ns-1]))
    return ns;
#endif

  /* binary search */

  lo = 0;
  hi = ns-1;

  /* loop invariant: lo <= find_msection (ms, ptr) <= hi */

  while (lo < hi)
    {
      int mid = (lo+hi) / 2; /* lo <= mid < hi */
#ifdef ___ALLOC_MEM_UP
      if (ptr < ___CAST(void*,sections[mid+1])) hi = mid; else lo = mid+1;
#else
      if (ptr < ___CAST(void*,sections[mid])) lo = mid+1; else hi = mid;
#endif
    }

  return lo;
}


/*
 * 'adjust_msections (msp, n)' contracts or expands the msections
 * pointed to by 'msp' so that it contains 'n' sections.  When the
 * msections is contracted, the last sections allocated (i.e. those at
 * the end of the doubly-linked list of sections) will be reclaimed.
 * When expanding the msections there may not be enough memory to
 * allocate new sections so the operation may fail.  However
 * 'adjust_msections' will always leave the msections in a consistent
 * state and there will be at least as many sections as when the
 * expansion was started.  Failure can be detected by checking the
 * 'nb_sections' field.
 */

___HIDDEN void adjust_msections
   ___P((___msections **msp,
         int n),
        (msp,
         n)
___msections **msp;
int n;)
{
  int max_ns, ns;
  ___msections *ms = *msp;
  ___msection *hd;
  ___msection *tl;

  if (ms == 0)
    {
      max_ns = 0;
      ns = 0;
      hd = 0;
      tl = 0;
    }
  else
    {
      max_ns = ms->max_nb_sections;
      ns = ms->nb_sections;
      hd = ms->head;
      tl = ms->tail;
    }

  if (ms == 0 || n > max_ns)
    {
      /* must allocate a new msections structure */

      ___msections *new_ms;
      int i;

      while (n > max_ns) /* grow max_nb_sections until big enough */
        max_ns = 2*max_ns + 1;

      new_ms = ___CAST(___msections*,
                       alloc_mem_aligned
                         (___WORDS(___sizeof_msections(max_ns)),
                          1,
                          0));

      if (new_ms == 0)
        return;

      new_ms->max_nb_sections = max_ns;
      new_ms->nb_sections = ns;
      new_ms->head = hd;
      new_ms->tail = tl;

      for (i=ns-1; i>=0; i--)
        new_ms->sections[i] = ms->sections[i];

      if (ms != 0)
        free_mem_aligned (ms);

      ms = new_ms;

      *msp = ms;
    }

  if (n < ns)
    {
      /* contraction of the msections */

      int j;

      while (ns > n)
        {
          ___msection *s = tl;

          tl = tl->prev;

          if (tl == 0)
            hd = 0;
          else
            tl->next = 0;

          for (j=s->pos; j<ns-1; j++)
            {
              ms->sections[j] = ms->sections[j+1];
              ms->sections[j]->pos = j;
            }

          free_msection_storage (s);

          ns--;
        }

      ms->nb_sections = ns;
      ms->head = hd;
      ms->tail = tl;

      /*
       * Contraction of the msections structure is not performed
       * because there is typically very little memory to be
       * reclaimed.
       */
    }
  else
    {
      /* expansion of the msections */

      int i, j;

      while (ns < n)
        {
          ___msection *s = alloc_msection_storage ();

          if (s == 0)
            return;

          i = find_msection (ms, ___CAST(void*,s));

#ifdef ___ALLOC_MEM_UP
          i++;
#endif

          for (j=ns; j>i; j--)
            {
              ms->sections[j] = ms->sections[j-1];
              ms->sections[j]->pos = j;
            }

          ms->sections[i] = s;

          if (tl == 0)
            {
              hd = s;
              s->index = 0;
            }
          else
            {
              tl->next = s;
              s->index = tl->index + 1;
            }

          *section_claim_at(s,0)=(section_claim){0};
          *section_claim_at(s,___MSECTION_SIZE>>1)=(section_claim){0};
          s->copy_gate=0;
          s->region_generation=1;
          s->region_age=___GC_REGION_YOUNG;
          s->card_dirty_any=0;
          s->active_offset=0;
          s->mature_words=0;
          s->scan_end_words=0;
          s->gc_src_offset=0;
          s->gc_dest_offset=0;
          s->gc_dest_words=0;
          s->gc_is_dest=0;
          s->gc_role=0;
          s->major_mark_epoch=0;
          s->major_snapshot_words=0;
          s->major_live_words=0;
          memset(s->major_line_live,0,sizeof(s->major_line_live));
          s->major_evacuate=0;
          s->major_hole_start=0;
          s->major_hole_end=0;
          memset(___CAST(void*,section_card_bits(s)),0,SECTION_CARD_BYTES);
          memset(___CAST(void*,section_card_starts(s)),___GC_CARD_NO_OBJ_START,SECTION_CARD_COUNT);
          memset(___CAST(void*,section_major_mark_bits(s)),0,SECTION_MAJOR_MARK_BYTES);
          s->pos = i;
          s->prev = tl;
          s->next = 0;

          tl = s;

          ms->nb_sections = ++ns;
          ms->head = hd;
          ms->tail = tl;
        }
    }
}


/*
 * 'free_msections (msp)' releases all memory associated with the
 * msections pointed to by 'msp'.
 */

___HIDDEN void free_msections
   ___P((___msections **msp),
        (msp)
___msections **msp;)
{
  ___msections *ms = *msp;

  if (ms != 0)
    {
      int i;

      for (i=ms->nb_sections-1; i>=0; i--)
        free_msection_storage (ms->sections[i]);

      free_mem_aligned (ms);

      *msp = 0;
    }
}


/* End internal memory fragment. */
