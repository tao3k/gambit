/* Internal write-authority protocol.  Not a Scheme root or thread-stop API. */
#ifndef ___NATIVE_SCOPE_H
#define ___NATIVE_SCOPE_H

#define ___NATIVE_SCOPE_OK         0
#define ___NATIVE_SCOPE_REPLAY     1
#define ___NATIVE_SCOPE_BUSY       2
#define ___NATIVE_SCOPE_STALE      3
#define ___NATIVE_SCOPE_USED       4
#define ___NATIVE_SCOPE_EXHAUSTED  5
#define ___NATIVE_SCOPE_INVALID    6

/* Four control roles (0..3), four data roles (4..7).  Role 0 and role 4
 * belong to the generation owner.  Delegated roles have exactly one producer.
 * A role is spent until the next generation, even after release.  This makes
 * release idempotent without allowing a late release to clear a newer permit.
 */
#define ___NATIVE_SCOPE_CONTROL 0
#define ___NATIVE_SCOPE_DATA    4
#define ___NATIVE_SCOPE_ROLES   8
#define ___NATIVE_SCOPE_CLOSED ___CAST(___WORD,1)
#define ___NATIVE_SCOPE_LIVE_SHIFT 1
#define ___NATIVE_SCOPE_USED_SHIFT 9
#define ___NATIVE_SCOPE_ACTOR_SHIFT 17
#define ___NATIVE_SCOPE_GENERATION_SHIFT 25
#define ___NATIVE_SCOPE_LIVE_MASK (___CAST(___WORD,255)<<1)
#define ___NATIVE_SCOPE_USED_MASK (___CAST(___WORD,255)<<9)
#define ___NATIVE_SCOPE_TAG_MASK (~((___CAST(___WORD,1)<<17)-1))
/* Reserve the sign bit: all C shifts/conversions stay representable in WORD. */
#define ___NATIVE_SCOPE_MAX_GENERATION \
  ((___CAST(___UWORD,1)<<(___WORD_WIDTH-26))-1)

/* All APIs require a live VM/storage borrow.  Tokens do not extend VM lifetime.
 * Actor identities 1..255 are exclusive, pre-registered activation identities,
 * not processor ids.  Their registration and root lifetime are separate work.
 * Prepare and retain the candidate in stable storage BEFORE try_handoff.  A
 * lost response can then be queried without repeating Scheme/native effects.
 * REPLAY only observes the current tag; it grants no second initialization.
 * STALE says nothing about past result delivery; retain the external journal.
 */
extern void ___native_scope_init ___P((___native_scope *scope), ());
extern ___WORD ___native_scope_snapshot ___P((___native_scope *scope), ());
extern int ___native_scope_prepare
  ___P((___WORD previous, unsigned int actor, ___WORD *candidate), ());
extern int ___native_scope_try_handoff
  ___P((___native_scope *scope, ___WORD previous, ___WORD candidate), ());
extern int ___native_scope_try_acquire
  ___P((___native_scope *scope, ___WORD tag, unsigned int role), ());
extern int ___native_scope_close
  ___P((___native_scope *scope, ___WORD tag), ());
extern int ___native_scope_release
  ___P((___native_scope *scope, ___WORD tag, unsigned int role), ());
extern int ___native_scope_class_quiescent
  ___P((___native_scope *scope, ___WORD tag, unsigned int first_role), ());
extern int ___native_scope_quiescent
  ___P((___native_scope *scope, ___WORD tag), ());

/* Initialization is exclusive, before VM publication, never concurrent reset. */
extern void ___native_scope_init_vmstate
  ___P((___virtual_machine_state vms), ());

#endif
