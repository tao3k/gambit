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
#define ___LARGE_HEAP_MMAP_MIN_BYTES ((___SIZE_T)32768u)
#define ___MEDIUM_STILL_SLAB_MIN_BYTES ((___SIZE_T)3072u)
#define ___CENSUS_QUEUE_RETAIN_MAX_BYTES ((___SIZE_T)(512u * 1024u))

#if defined(___SINGLE_THREADED_VMS) || defined(___USE_POSIX_THREAD_SYSTEM)
#define ___USE_MEDIUM_STILL_SLAB 1
#endif

#ifdef ___USE_MEDIUM_STILL_SLAB
#define ___STILL_SLAB_CLASSES 7u
#define ___STILL_SLAB_SHARDS  4u
#define ___STILL_SLAB_BUCKETS (___STILL_SLAB_CLASSES * ___STILL_SLAB_SHARDS)

typedef struct ___still_slab_chunk_struct
  {
    struct ___still_slab_chunk_struct *prev;
    struct ___still_slab_chunk_struct *next;
    uint64_t free_mask;
    uint64_t all_mask;
    ___SIZE_T slot_bytes;
    ___SIZE_T map_bytes;
    unsigned int bucket_idx;
    unsigned int in_partial;
  } ___still_slab_chunk;

typedef struct ___still_slab_bucket_struct
  {
    ___still_slab_chunk *partial_head;
    ___still_slab_chunk *empty_cache;
  } ___still_slab_bucket;

static ___still_slab_bucket still_slab_buckets_[___STILL_SLAB_BUCKETS];
static ___VOLATILE int still_slab_cached_empty_count_ = 0;

#if !defined(___SINGLE_THREADED_VMS)
static pthread_mutex_t still_slab_locks_[___STILL_SLAB_BUCKETS] = {
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER,
  PTHREAD_MUTEX_INITIALIZER, PTHREAD_MUTEX_INITIALIZER
};
#define ___STILL_SLAB_LOCK(b)   pthread_mutex_lock(&still_slab_locks_[(b)])
#define ___STILL_SLAB_UNLOCK(b) pthread_mutex_unlock(&still_slab_locks_[(b)])
#else
#define ___STILL_SLAB_LOCK(b)   ((void)(b))
#define ___STILL_SLAB_UNLOCK(b) ((void)(b))
#endif

static inline unsigned int still_slab_ctz64(uint64_t mask)
{
#if defined(__GNUC__)
  return (unsigned int)__builtin_ctzll(mask);
#else
  unsigned int idx = 0u;
  while (((mask >> idx) & (uint64_t)1u) == (uint64_t)0u) idx++;
  return idx;
#endif
}

static inline void still_slab_unlink_partial
   (___still_slab_bucket *bucket, ___still_slab_chunk *chunk)
{
  if (chunk->prev != 0)
    chunk->prev->next = chunk->next;
  else
    bucket->partial_head = chunk->next;
  if (chunk->next != 0)
    chunk->next->prev = chunk->prev;
  chunk->prev = 0;
  chunk->next = 0;
  chunk->in_partial = 0u;
}

static inline void still_slab_push_partial
   (___still_slab_bucket *bucket, ___still_slab_chunk *chunk)
{
  chunk->prev = 0;
  chunk->next = bucket->partial_head;
  if (bucket->partial_head != 0)
    bucket->partial_head->prev = chunk;
  bucket->partial_head = chunk;
  chunk->in_partial = 1u;
}

___HIDDEN void *still_slab_alloc
   (___SIZE_TS words, ___SIZE_T align_bytes, ___SIZE_T mod_bytes)
{
  /* 7 fine-grained 25%-step size classes (4K..32K) keep max internal
   * fragmentation <= 25% while every map_bytes is a multiple of 16 KiB
   * (exact page multiple on both 4 KiB Linux and 16 KiB Apple Silicon). */
  static const ___SIZE_T class_slot_bytes[___STILL_SLAB_CLASSES] = {
    4096u, 6144u, 8192u, 12288u, 16384u, 24576u, 32768u
  };
  static const ___SIZE_T class_map_bytes[___STILL_SLAB_CLASSES] = {
    131072u, 196608u, 131072u, 196608u, 262144u, 393216u, 524288u
  };
  static const uint64_t class_all_masks[___STILL_SLAB_CLASSES] = {
    (((uint64_t)1u << 32) - (uint64_t)2u),
    (((uint64_t)1u << 32) - (uint64_t)2u),
    (((uint64_t)1u << 16) - (uint64_t)2u),
    (((uint64_t)1u << 16) - (uint64_t)2u),
    (((uint64_t)1u << 16) - (uint64_t)2u),
    (((uint64_t)1u << 16) - (uint64_t)2u),
    (((uint64_t)1u << 16) - (uint64_t)2u)
  };
  ___SIZE_T need;
  unsigned int cls, shard, bidx, idx;
  ___still_slab_bucket *bucket;
  ___still_slab_chunk *chunk;
  ___UWORD slot_lo, raw_start, ptr_u;
  void **cptr;

  if (align_bytes > 2048u || words <= 0)
    return 0;
  need = (___SIZE_T)sizeof(void*) + (align_bytes - 1u) + mod_bytes +
         (___SIZE_T)words * ___WS;
  if (need > class_slot_bytes[___STILL_SLAB_CLASSES - 1u])
    return 0;
  for (cls = 0u; cls < ___STILL_SLAB_CLASSES; cls++)
    if (need <= class_slot_bytes[cls])
      break;
  shard = (unsigned int)((___CAST(___UWORD, &shard) >> 12) & (___STILL_SLAB_SHARDS - 1u));
  bidx = cls * ___STILL_SLAB_SHARDS + shard;
  bucket = &still_slab_buckets_[bidx];

  ___STILL_SLAB_LOCK(bidx);
  chunk = bucket->partial_head;
  if (chunk == 0 && bucket->empty_cache != 0)
    {
      chunk = bucket->empty_cache;
      bucket->empty_cache = 0;
#if defined(__ATOMIC_RELAXED)
      (void)__atomic_fetch_sub(&still_slab_cached_empty_count_, 1, __ATOMIC_RELAXED);
#else
      still_slab_cached_empty_count_--;
#endif
      still_slab_push_partial(bucket, chunk);
    }
  if (chunk == 0)
    {
      ___SIZE_T mbytes = class_map_bytes[cls];
      void *raw;
      ___STILL_SLAB_UNLOCK(bidx);
      raw = mmap(0, mbytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
      if (raw == MAP_FAILED)
        return 0;
      chunk = ___CAST(___still_slab_chunk*, raw);
      chunk->prev = 0;
      chunk->next = 0;
      chunk->all_mask = class_all_masks[cls];
      chunk->free_mask = chunk->all_mask;
      chunk->slot_bytes = class_slot_bytes[cls];
      chunk->map_bytes = mbytes;
      chunk->bucket_idx = bidx;
      chunk->in_partial = 0u;
      ___STILL_SLAB_LOCK(bidx);
      still_slab_push_partial(bucket, chunk);
    }

  idx = still_slab_ctz64(chunk->free_mask);
  chunk->free_mask &= ~((uint64_t)1u << idx);
  if (chunk->free_mask == (uint64_t)0u)
    still_slab_unlink_partial(bucket, chunk);
  ___STILL_SLAB_UNLOCK(bidx);

  slot_lo = ___CAST(___UWORD, chunk) + (___UWORD)idx * (___UWORD)chunk->slot_bytes;
  raw_start = slot_lo + (___UWORD)sizeof(void*);
  ptr_u = ((raw_start + (___UWORD)(align_bytes - 1u)) & -___CAST(___UWORD, align_bytes)) +
          (___UWORD)mod_bytes;
  cptr = ___CAST(void**, (ptr_u - (___UWORD)sizeof(void*)) & -___CAST(___UWORD, sizeof(void*)));
  *cptr = ___CAST(void*, ___CAST(___UWORD, chunk) | (___UWORD)2u);
  return ___CAST(void*, ptr_u);
}

___HIDDEN void still_slab_free(void *ptr, ___still_slab_chunk *chunk)
{
  unsigned int bidx = chunk->bucket_idx;
  unsigned int idx = (unsigned int)((___CAST(___UWORD, ptr) - ___CAST(___UWORD, chunk)) /
                                    (___UWORD)chunk->slot_bytes);
  ___still_slab_bucket *bucket = &still_slab_buckets_[bidx];
  ___still_slab_chunk *to_unmap = 0;
  ___SIZE_T to_unmap_bytes = 0u;
  int was_full;

  ___STILL_SLAB_LOCK(bidx);
  was_full = (chunk->free_mask == (uint64_t)0u);
  chunk->free_mask |= ((uint64_t)1u << idx);
  if (chunk->free_mask == chunk->all_mask)
    {
      if (chunk->in_partial)
        still_slab_unlink_partial(bucket, chunk);
      if (bucket->empty_cache == 0)
        {
          bucket->empty_cache = chunk;
#if defined(__ATOMIC_RELAXED)
          (void)__atomic_fetch_add(&still_slab_cached_empty_count_, 1, __ATOMIC_RELAXED);
#else
          still_slab_cached_empty_count_++;
#endif
        }
      else
        {
          to_unmap = chunk;
          to_unmap_bytes = chunk->map_bytes;
        }
    }
  else if (was_full)
    {
      still_slab_push_partial(bucket, chunk);
    }
  ___STILL_SLAB_UNLOCK(bidx);

  if (to_unmap != 0)
    (void)munmap(___CAST(void*, to_unmap), to_unmap_bytes);
}

___HIDDEN void still_slab_purge_empty ___PVOID
{
  unsigned int bidx;
#if defined(__ATOMIC_RELAXED)
  if (__atomic_load_n(&still_slab_cached_empty_count_, __ATOMIC_RELAXED) <= 0)
    return;
#else
  if (still_slab_cached_empty_count_ <= 0)
    return;
#endif
  for (bidx = 0u; bidx < ___STILL_SLAB_BUCKETS; bidx++)
    {
      ___still_slab_chunk *c;
      ___SIZE_T mbytes = 0u;
      ___STILL_SLAB_LOCK(bidx);
      c = still_slab_buckets_[bidx].empty_cache;
      if (c != 0)
        {
          still_slab_buckets_[bidx].empty_cache = 0;
          mbytes = c->map_bytes;
#if defined(__ATOMIC_RELAXED)
          (void)__atomic_fetch_sub(&still_slab_cached_empty_count_, 1, __ATOMIC_RELAXED);
#else
          still_slab_cached_empty_count_--;
#endif
        }
      ___STILL_SLAB_UNLOCK(bidx);
      if (c != 0)
        (void)munmap(___CAST(void*, c), mbytes);
    }
}
#else
___HIDDEN void still_slab_purge_empty ___PVOID {}
#endif

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

___HIDDEN void still_slab_purge_empty ___PVOID {}
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
  if (heap && words > 0 && multiplier > 0)
    {
      ___SIZE_T align_bytes = (___SIZE_T)multiplier * ___WS;
      ___SIZE_T mod_bytes = (___SIZE_T)modulus * ___WS;
#ifdef ___USE_MEDIUM_STILL_SLAB
      if ((___SIZE_T)words >= (___MEDIUM_STILL_SLAB_MIN_BYTES / ___WS) &&
          (___SIZE_T)words < (___LARGE_HEAP_MMAP_MIN_BYTES / ___WS))
        {
          void *slab_ptr = still_slab_alloc(words, align_bytes, mod_bytes);
          if (slab_ptr != 0)
            return slab_ptr;
        }
#endif
      if ((___SIZE_T)words >= (___LARGE_HEAP_MMAP_MIN_BYTES / ___WS))
        {
          ___SIZE_T ps = os_heap_page_size();
          ___SIZE_T hdr_bytes = (___SIZE_T)(2u * sizeof(___UWORD) + sizeof(void*));
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
    if ((raw_c & (___UWORD)3u) == (___UWORD)1u)
      {
        ___UWORD *hdr = ___CAST(___UWORD*, raw_c & ~(___UWORD)3u);
        ___SIZE_T map_bytes = (___SIZE_T)hdr[0];
        (void)munmap(___CAST(void*, hdr), map_bytes);
        return 1;
      }
#ifdef ___USE_MEDIUM_STILL_SLAB
    if ((raw_c & (___UWORD)3u) == (___UWORD)2u)
      {
        ___still_slab_chunk *chunk = ___CAST(___still_slab_chunk*, raw_c & ~(___UWORD)3u);
        still_slab_free(ptr, chunk);
        return 1;
      }
#endif
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
