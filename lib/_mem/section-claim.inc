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
#define SECTION_CLAIM_TAIL_BYTES \
  ((2*sizeof(section_claim)+2*RAW_STACK_MAP_BYTES+___WS-1) & ~(___CAST(___SIZE_T,___WS)-1))
#define SECTION_CARD_COUNT ___msection_card_count(___MSECTION_SIZE)
#define SECTION_CARD_BYTES (___msection_card_words(___MSECTION_SIZE)*___WS)
#define SECTION_CARD_START_BYTES \
  ((SECTION_CARD_COUNT + ___WS - 1) & ~(___CAST(___SIZE_T,___WS) - 1))
#define SECTION_BYTES \
  (___sizeof_msection(___MSECTION_SIZE)+SECTION_CLAIM_TAIL_BYTES+SECTION_CARD_BYTES+SECTION_CARD_START_BYTES)
#define ___GC_CARD_NO_OBJ_START 0xFFu

static inline section_claim *section_claim_at(___msection *section, ___SIZE_TS offset)
{
  return ((section_claim *)(section->base+___MSECTION_SIZE+
                          ___msection_scan_words(___MSECTION_SIZE)))+
    (offset != 0);
}

static inline ___VOLATILE ___WORD *section_card_bits(___msection *section)
{
  char *tail = ___CAST(char*, section->base+___MSECTION_SIZE+
                       ___msection_scan_words(___MSECTION_SIZE));
  return ___CAST(___VOLATILE ___WORD*, tail + SECTION_CLAIM_TAIL_BYTES);
}

static inline unsigned char *section_card_starts(___msection *section)
{
  char *tail = ___CAST(char*, section->base+___MSECTION_SIZE+
                       ___msection_scan_words(___MSECTION_SIZE));
  return ___CAST(unsigned char*, tail + SECTION_CARD_BYTES + SECTION_CLAIM_TAIL_BYTES);
}

static inline void record_mature_obj_start(___msection *sec, ___WORD *hdr)
{
  unsigned char *starts = section_card_starts(sec);
  ___SIZE_TS off = hdr - sec->base;
  unsigned int card = ___CAST(unsigned int, off >> ___GC_CARD_SHIFT_WORDS);
  unsigned int in_card = ___CAST(unsigned int, off & (___GC_CARD_WORDS - 1));
  if (starts[card] == ___GC_CARD_NO_OBJ_START)
    starts[card] = ___CAST(unsigned char, in_card);
}

static inline ___msection *next_copy_plan_section(___msection *cur)
{
  while (cur != 0 && cur->gc_role != 0)
    cur = cur->next;
  return cur;
}

#endif
