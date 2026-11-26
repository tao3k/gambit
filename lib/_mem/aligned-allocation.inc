#line 538 ___MEM_SOURCE_FILE
/*---------------------------------------------------------------------------*/

/* Allocation and reclamation of aligned blocks of memory.
 * Large heap-backed still blocks and oversized census queues (>= 64 KiB) use
 * direct anonymous mmap/munmap when available so dead buffers return physical
 * pages to the OS immediately without libmalloc MALLOC_LARGE (empty) retention.
 */

#if defined(__APPLE__)
#include <malloc/malloc.h>
#elif defined(__GLIBC__)
#include <malloc.h>
#endif

#if defined(HAVE_SYS_MMAN_H) && !defined(_WIN32) && !defined(___SUPPORT_LOWLEVEL_EXEC) && !defined(___DEBUG_ALLOC_MEM) && (defined(MAP_ANON) || defined(MAP_ANONYMOUS))
#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif
#define ___USE_MMAP_LARGE_HEAP 1
#define ___LARGE_HEAP_MMAP_MIN_BYTES ((___SIZE_T)65536u)
#define ___CENSUS_QUEUE_RETAIN_MAX_BYTES ((___SIZE_T)(512u * 1024u))

___HIDDEN ___SIZE_T os_heap_page_size ___PVOID
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

___HIDDEN ___SCMOBJ *census_queue_alloc(___SIZE_T capacity)
{
  ___SIZE_T bytes;
  if (capacity == 0 || capacity > (~(___SIZE_T)0) / sizeof(___SCMOBJ))
    return 0;
  bytes = capacity * sizeof(___SCMOBJ);
  if (bytes >= ___LARGE_HEAP_MMAP_MIN_BYTES)
    {
      ___SIZE_T ps = os_heap_page_size();
      if (bytes <= (~(___SIZE_T)0) - (ps - 1u))
        {
          ___SIZE_T map_bytes = (bytes + (ps - 1u)) & ~(ps - 1u);
          void *p = mmap(0, map_bytes, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANON, -1, 0);
          return (p == MAP_FAILED) ? 0 : ___CAST(___SCMOBJ*, p);
        }
      return 0;
    }
  return ___CAST(___SCMOBJ*, ___ALLOC_MEM(bytes));
}

___HIDDEN void census_queue_free(___SCMOBJ *q, ___SIZE_T capacity)
{
  ___SIZE_T bytes;
  if (!q)
    return;
  if (capacity > 0 && capacity <= (~(___SIZE_T)0) / sizeof(___SCMOBJ))
    {
      bytes = capacity * sizeof(___SCMOBJ);
      if (bytes >= ___LARGE_HEAP_MMAP_MIN_BYTES)
        {
          ___SIZE_T ps = os_heap_page_size();
          ___SIZE_T map_bytes = (bytes + (ps - 1u)) & ~(ps - 1u);
          (void)munmap(___CAST(void*, q), map_bytes);
          return;
        }
    }
  ___FREE_MEM(q);
}
#else
#define ___CENSUS_QUEUE_RETAIN_MAX_BYTES ((___SIZE_T)(512u * 1024u))

___HIDDEN ___SCMOBJ *census_queue_alloc(___SIZE_T capacity)
{
  if (capacity == 0 || capacity > (~(___SIZE_T)0) / sizeof(___SCMOBJ))
    return 0;
  return ___CAST(___SCMOBJ*, ___ALLOC_MEM(capacity * sizeof(___SCMOBJ)));
}

___HIDDEN void census_queue_free(___SCMOBJ *q, ___SIZE_T capacity)
{
  (void)capacity;
  if (q)
    ___FREE_MEM(q);
}
#endif

___HIDDEN void os_heap_pressure_relief ___PVOID
{
#if defined(__APPLE__)
  (void)malloc_zone_pressure_relief(NULL, 0);
#elif defined(__GLIBC__)
  (void)malloc_trim(0);
#endif
}


/*
 * 'alloc_mem_aligned_aux (words, multiplier, modulus, heap)'
 * allocates an aligned block of memory (using '___alloc_mem' when
 * heap is false, and '___alloc_mem_heap' when heap is true).  'words'
 * is the size of the block in words and 'multiplier' and 'modulus'
 * specify its alignment in words.  'multiplier' must be a power of
 * two and 0<=modulus<multiplier.  The pointer returned corresponds to
 * an address that is equal to (i*multiplier+modulus)*sizeof (___WORD)
 * for some 'i'.
 */

___HIDDEN void *alloc_mem_aligned_aux
   ___P((___SIZE_TS words,
         unsigned int multiplier,
         unsigned int modulus,
         ___BOOL heap),
        (words,
         multiplier,
         modulus,
         heap)
___SIZE_TS words;
unsigned int multiplier;
unsigned int modulus;
___BOOL heap;)
{
  void *container; /* pointer to block returned by ___alloc_mem{_heap} */
  unsigned int extra; /* space for alignment to multiplier */

  /* Make sure alignment is sufficient for pointers */

  if (multiplier < sizeof (void*) / ___WS)
    multiplier = sizeof (void*) / ___WS;

  /* How many extra bytes are needed for padding */

  extra = (multiplier * ___WS) - 1;
  if (modulus < sizeof (void*) / ___WS)
    extra += sizeof (void*);

#ifdef ___USE_MMAP_LARGE_HEAP
  if (heap && words > 0 && multiplier > 0 &&
      (___SIZE_T)words >= (___LARGE_HEAP_MMAP_MIN_BYTES / ___WS))
    {
      ___SIZE_T ps = os_heap_page_size();
      ___SIZE_T hdr_bytes = (___SIZE_T)(2u * sizeof(___UWORD) + sizeof(void*));
      ___SIZE_T align_bytes = (___SIZE_T)multiplier * ___WS;
      ___SIZE_T mod_bytes = (___SIZE_T)modulus * ___WS;
      ___SIZE_T prefix_max = hdr_bytes + (align_bytes - 1u) + mod_bytes;
      if ((___SIZE_T)words <= ((~(___SIZE_T)0) - prefix_max) / ___WS)
        {
          ___SIZE_T need_bytes = prefix_max + (___SIZE_T)words * ___WS;
          if (need_bytes <= (~(___SIZE_T)0) - (ps - 1u))
            {
              ___SIZE_T map_bytes = (need_bytes + (ps - 1u)) & ~(ps - 1u);
              void *map_base = mmap(0, map_bytes, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANON, -1, 0);
              if (map_base == MAP_FAILED)
                return 0;
              {
                ___UWORD *hdr = ___CAST(___UWORD*, map_base);
                ___UWORD raw_start = ___CAST(___UWORD, map_base) + (___UWORD)hdr_bytes;
                ___UWORD ptr_u =
                  ((raw_start + (___UWORD)(align_bytes - 1u)) &
                   -___CAST(___UWORD, align_bytes)) +
                  (___UWORD)mod_bytes;
                void *ptr = ___CAST(void*, ptr_u);
                void **cptr = ___CAST(void**,
                                      (ptr_u - (___UWORD)sizeof(void*)) &
                                      -___CAST(___UWORD, sizeof(void*)));
                hdr[0] = (___UWORD)map_bytes;
                hdr[1] = (___UWORD)0x474d4150u;
                *cptr = ___CAST(void*, ___CAST(___UWORD, map_base) | (___UWORD)1u);
                return ptr;
              }
            }
        }
    }
#endif

  if (heap)
    container = ___ALLOC_MEM_HEAP(extra + (words+modulus) * ___WS);
  else
    container = ___ALLOC_MEM(extra + (words+modulus) * ___WS);

  if (container == 0)
    return 0;
  else
    {
      void *ptr = ___CAST(void*,
                          (((___CAST(___WORD,container) + extra) &
                            -___CAST(___WORD,multiplier * ___WS)) +
                           modulus * ___WS));
      void **cptr = ___CAST(void**,
                            (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                            -___CAST(___WORD,sizeof (void*)));

      *cptr = container;
      return ptr;
    }
}


___HIDDEN void *alloc_mem_aligned
   ___P((___SIZE_TS words,
         unsigned int multiplier,
         unsigned int modulus),
        (words,
         multiplier,
         modulus)
___SIZE_TS words;
unsigned int multiplier;
unsigned int modulus;)
{
  return alloc_mem_aligned_aux (words, multiplier, modulus, 0);
}


___HIDDEN void *alloc_mem_aligned_heap
   ___P((___SIZE_TS words,
         unsigned int multiplier,
         unsigned int modulus),
        (words,
         multiplier,
         modulus)
___SIZE_TS words;
unsigned int multiplier;
unsigned int modulus;)
{
  return alloc_mem_aligned_aux (words, multiplier, modulus, 1);
}


/*
 * 'free_mem_aligned (ptr)' reclaims the aligned block of memory 'ptr'
 * that was allocated using 'alloc_mem_aligned'.
 */

___HIDDEN void free_mem_aligned
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  void **cptr = ___CAST(void**,
                        (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                        -___CAST(___WORD,sizeof (void*)));
  ___FREE_MEM(*cptr);
}


/*
 * 'free_mem_aligned_heap_ex (ptr)' reclaims the aligned block of memory
 * 'ptr' allocated using 'alloc_mem_aligned_heap'. Returns 1 if reclaimed
 * via direct munmap, 0 if returned to C heap allocator.
 */

___HIDDEN int free_mem_aligned_heap_ex
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  void **cptr = ___CAST(void**,
                        (___CAST(___WORD,ptr) - ___CAST(___WORD,sizeof (void*))) &
                        -___CAST(___WORD,sizeof (void*)));
#ifdef ___USE_MMAP_LARGE_HEAP
  {
    ___UWORD raw_c = ___CAST(___UWORD, *cptr);
    if (raw_c & (___UWORD)1u)
      {
        ___UWORD *hdr = ___CAST(___UWORD*, raw_c & ~(___UWORD)1u);
        ___SIZE_T map_bytes = (___SIZE_T)hdr[0];
        (void)munmap(___CAST(void*, hdr), map_bytes);
        return 1;
      }
  }
#endif
  ___FREE_MEM_HEAP(*cptr);
  return 0;
}


/*
 * 'free_mem_aligned_heap (ptr)' reclaims the aligned block of memory 'ptr'
 * that was allocated using 'alloc_mem_aligned_heap'.
 */

___HIDDEN void free_mem_aligned_heap
   ___P((void *ptr),
        (ptr)
void *ptr;)
{
  (void)free_mem_aligned_heap_ex (ptr);
}


/* End internal memory fragment. */
