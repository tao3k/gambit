/* Allocator stack claim. One definition for publication and admission. */
#ifndef ___SECTION_CLAIM_INC
#define ___SECTION_CLAIM_INC

/* Private ownership per semispace. Keep the public msection prefix and
 * its scan bitmap unchanged. Old and destination claims can coexist until
 * the collector has drained every old-space reader. */
enum stack_claim_state { STACK_UNCLAIMED, STACK_ACTIVE, STACK_PARKED, STACK_REUSABLE };

typedef struct section_claim
{
  ___processor_state stack_owner;
  ___WORD *stack_floor;
  ___WORD *parked_top, *parked_break;
  ___WORD *raw_low, *raw_high;
  unsigned char *raw_marks;
  ___msection *reuse_next;
  enum stack_claim_state stack_state;
  unsigned heap_used;
  unsigned source_pins;
} section_claim;

/* Two bits per word in each half. The map is initialized on first
 * publication. Clearing the claim makes stale map bytes unreachable. */
#define RAW_STACK_MAP_BYTES (((___MSECTION_SIZE>>1)+3)/4)
#define SECTION_BYTES (___sizeof_msection(___MSECTION_SIZE)+2*sizeof(section_claim)+2*RAW_STACK_MAP_BYTES)

static inline section_claim *section_claim_at(___msection *section, ___SIZE_TS offset)
{
  return ((section_claim *)(section->base+___MSECTION_SIZE+
                          ___msection_scan_words(___MSECTION_SIZE)))+
    (offset != 0);
}

#endif
