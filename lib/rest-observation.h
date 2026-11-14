/* Opt-in native observations. The wire format contains no Scheme objects to
 * retain and the writer never allocates, locks, collects, or performs I/O. */
#ifndef GAMBIT_REST_OBSERVATION_H
#define GAMBIT_REST_OBSERVATION_H
#include <stdint.h>

enum ___rest_observation_kind {
  REST_CASE_BEGIN=1, REST_CASE_END, REST_HEAP_SPAN, REST_STACK_SPAN,
  REST_ARGUMENT_SPAN, REST_PREFLIGHT, REST_STORE, REST_POP, REST_SNAPSHOT,
  REST_PIN, REST_SOURCE_READ, REST_SUCCESSOR, REST_UNPIN,
  REST_ROOTS, REST_ROOT_VALUE, REST_GC_BEGIN, REST_GC_END, REST_RELOAD,
  REST_SAVED_FP, REST_RETURN_FP, REST_READY, REST_DELIVER,
  REST_LOCK, REST_CAPACITY, REST_CLAIM, REST_REFUSE, REST_UNLOCK,
  REST_BACKING, REST_DEMAND, REST_ROOT_REPAIRED, REST_BODY,
  REST_LOCK_REQUEST, REST_FP_ADJUST, REST_NATIVE_BEGIN, REST_NATIVE_CUT, REST_GRANT,
  REST_BREAK_LINK, REST_SECTION_VIEW, REST_SECTION_PUBLISHED, REST_WATCHED_DEMAND,
  REST_PARENT, REST_RELOAD_INSTALLED, REST_RETRY_GRANT, REST_TAIL, REST_EXIT
};

#ifdef ___GAMBIT_REST_OBSERVATION
int ___rest_observation_open(const char *path);
int ___rest_observation_case(uint64_t id);
int ___rest_observation_case_end(void);
int ___rest_observation_close(void);
int ___rest_observation_watch(uint64_t argument_words);
int ___rest_observation_body(void *actor);
void ___rest_observation_delivered(void *actor, void *record, uint64_t attempt, uint64_t epoch);
void ___rest_observation_emit(uint64_t kind, uint64_t actor, uint64_t record,
  uint64_t attempt, uint64_t epoch, uint64_t a, uint64_t b, uint64_t c,
  uint64_t d, uint64_t e, uint64_t f, uint64_t g, uint64_t h);
/* Precondition: the caller owns the complete, readable word interval. This
 * function cannot authorize an arbitrary pointer supplied by a fixture. */
void ___rest_observation_snapshot(uint64_t actor, uint64_t region, uint64_t phase,
                                const void *base, uint64_t words);
void ___rest_observation_store(void *actor, void *fp, void *address);
void ___rest_observation_adjust(void *actor, void *fp, intptr_t words);
void ___rest_observation_pop(void *actor, void *fp);
void ___rest_observation_repair(void *actor, void *cell, uint64_t old_value,
                               uint64_t new_value, uint64_t round);
#define REST_OBS(k,p,r,t,e,a,b,c,d,f,g,h,i) \
  ___rest_observation_emit((k),(uintptr_t)(p),(uintptr_t)(r),(t),(e), \
    (uintptr_t)(a),(uintptr_t)(b),(uintptr_t)(c),(uintptr_t)(d), \
    (uintptr_t)(f),(uintptr_t)(g),(uintptr_t)(h),(uintptr_t)(i))
#define REST_OBS_REPAIR(p,c,o,n,e) ___rest_observation_repair((p),(c),(o),(n),(e))
#else
#define REST_OBS(k,p,r,t,e,a,b,c,d,f,g,h,i) ((void)0)
#define REST_OBS_REPAIR(p,c,o,n,e) ((void)0)
#endif
#endif
