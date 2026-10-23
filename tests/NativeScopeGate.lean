namespace GambitSMP.NativeScopeGate
structure Gate where
  generation : Nat
  actor : Nat
  closed : Bool
  used : Nat → Bool
  live : Nat → Bool

def SameTag (s t : Gate) := s.generation=t.generation ∧ s.actor=t.actor
def Ready (s : Gate) := s.closed=true ∧ ∀ r, s.live r=false
def CanAcquire (s : Gate) (r : Nat) := s.closed=false ∧ r<8 ∧ s.used r=false
def release (s : Gate) (r : Nat) := {s with live:=fun n => if n=r then false else s.live n}
def close (s : Gate) := {s with closed:=true}
def usedOwner (r : Nat) := r==0 || r==4
def advance (s : Gate) (actor : Nat) := {generation:=s.generation+1,actor:=actor,closed:=false,used:=usedOwner,live:=usedOwner : Gate}

theorem closeRejectsAcquisition (s : Gate) (r : Nat) : ¬ CanAcquire (close s) r := by simp [CanAcquire,close]
theorem spentRoleRejectsAcquisition (s : Gate) (r : Nat) (h : s.used r=true) : ¬ CanAcquire s r := by simp [CanAcquire,h]
theorem releaseKeepsUsed (s : Gate) (r n : Nat) : (release s r).used n=s.used n := rfl
theorem releaseIsIdempotent (s : Gate) (r : Nat) : release (release s r) r=release s r := by
 simp [release]
theorem releaseKeepsOtherPermit (s : Gate) (r n : Nat) (h : n≠r) : (release s r).live n=s.live n := by simp [release,h]
theorem releasePreservesTag (s : Gate) (r : Nat) : SameTag (release s r) s := ⟨rfl,rfl⟩
theorem liveWriterBlocksHandoff (s : Gate) (r : Nat) (h : s.live r=true) : ¬ Ready s := by
 intro ready
 have x := ready.2 r
 simp [h] at x
theorem openGateBlocksHandoff (s : Gate) (h : s.closed=false) : ¬ Ready s := by simp [Ready,h]
theorem newOwnerControlAccounted (s : Gate) (actor : Nat) : (advance s actor).live 0=true := rfl
theorem newOwnerDataAccounted (s : Gate) (actor : Nat) : (advance s actor).live 4=true := rfl
theorem oldTagCannotReleaseSuccessor (s : Gate) (actor : Nat) : ¬ SameTag s (advance s actor) := by simp [SameTag,advance]
def guardedRelease (s : Gate) (generation actor r : Nat) :=
 if s.generation=generation ∧ s.actor=actor then release s r else s
theorem staleReleaseIsNoop (s : Gate) (g a r : Nat) (h : ¬ (s.generation=g ∧ s.actor=a)) : guardedRelease s g a r=s := by simp [guardedRelease,h]
def CanAdvance (s : Gate) (bound : Nat) := Ready s ∧ s.generation<bound
theorem exhaustionRejects (s : Gate) (bound : Nat) (h : s.generation=bound) : ¬ CanAdvance s bound := by simp [CanAdvance,h]
def Covers (s : Gate) := ∀ r, s.live r=true → s.used r=true
theorem releasePreservesCoverage (s : Gate) (r : Nat) (h : Covers s) : Covers (release s r) := by
 intro n live
 by_cases e : n=r
 · simp [release,e] at live
 · exact h n (by simpa [release,e] using live)
theorem advanceHasCoverage (s : Gate) (a : Nat) : Covers (advance s a) := by
 intro r live
 exact live
-- Finite-word arithmetic, C/ISA ordering, role/actor registration and last-use
-- release witnesses remain separate source-refinement obligations.
end GambitSMP.NativeScopeGate
