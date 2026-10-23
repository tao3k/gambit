// Concrete-word refinement candidate: one record, eight roles, three generations.
// Current C uses 6/38 generation bits on 32/64-bit WORD, and never wraps.
// VM storage lifetime, unique actor/role assignment and last-use release are premises.
module native_scope_gate {
 type S={gen:int,actor:int,closed:bool,used:Set[int],live:Set[int],
  pending:int,rg:int,ra:int,rc:bool,ru:Set[int],rl:Set[int],bad:bool}
 var s:S
 val roles=0.to(7)
 val bound=3
 action init=s'={gen:0,actor:0,closed:true,used:Set(),live:Set(),
  pending:-1,rg:0,ra:0,rc:true,ru:Set(),rl:Set(),bad:false}
 def snapshotMatches(x:S):bool=x.rg==x.gen and x.ra==x.actor and x.rc==x.closed and x.ru==x.used and x.rl==x.live
 action take(actor:int):bool=all{s.closed,s.live==Set(),s.gen<bound,
  s'={...s,gen:s.gen+1,actor:actor,closed:false,used:Set(0,4),live:Set(0,4)}}
 action readAcquire(role:int):bool=all{role.in(roles),not(s.closed),not(role.in(s.used)),
  s'={...s,pending:role,rg:s.gen,ra:s.actor,rc:s.closed,ru:s.used,rl:s.live}}
 action acquireCas=all{s.pending>=0,snapshotMatches(s),not(s.closed),
  s'={...s,used:s.used.union(Set(s.pending)),live:s.live.union(Set(s.pending)),pending:-1}}
 action failedCas=all{s.pending>=0,not(snapshotMatches(s)),s'={...s,pending:-1}}
 action close=all{s.gen>0,s'={...s,closed:true}}
 // Actual C permits are nonreusable within one generation; release is idempotent.
 action release(role:int):bool=all{role.in(s.used),s'={...s,live:s.live.exclude(Set(role))}}
 action staleRelease=all{s.gen>1,s'=s}
 action replayTake=all{s.gen>0,s'=s}
 action usedRoleReject=all{1.in(s.used),s'=s}
 action invalidRoleReject=s'=s
 action queryUnknown=s'=s
 action exhaustedReject=all{s.gen==bound,s.closed,s.live==Set(),s'=s}
 action idle=s'=s
 val safe=all{s.live.subseteq(s.used),s.used.subseteq(roles),s.gen>=0,s.gen<=bound,
  (s.gen==0) or (s.actor>0 and Set(0,4).subseteq(s.used)),not(s.bad)}
 action step=any{take(1),take(2),readAcquire(1),readAcquire(2),readAcquire(3),readAcquire(5),
  readAcquire(6),readAcquire(7),acquireCas,failedCas,close,release(0),release(1),release(2),release(3),
  release(4),release(5),release(6),release(7),staleRelease,replayTake,queryUnknown,idle}
 action drainOwner=release(0).then(release(4))
 action finishOwner=close.then(drainOwner)
 action owner=init.then(take(1))
 action helper=owner.then(finishOwner).then(take(2))
 action check=all{safe,s'=s}
 action unsafeAcquireCas=all{s.pending>=0,s'={...s,
  used:s.used.union(Set(s.pending)),live:s.live.union(Set(s.pending)),pending:-1,
  bad:s.bad or s.closed or not(snapshotMatches(s))}}
 action unsafeReuseSpent=all{1.in(s.used),not(1.in(s.live)),
  s'={...s,live:s.live.union(Set(1)),bad:true}}
 action unsafeTake=all{s.gen<bound,s'={...s,gen:s.gen+1,actor:2,closed:false,
  used:Set(0,4),live:Set(0,4),bad:s.bad or not(s.closed) or s.live!=Set()}}
 action unsafeOldRelease=all{s.gen>1,0.in(s.live),s'={...s,live:s.live.exclude(Set(0)),bad:true}}
 action reject=all{not(safe),s'=s}
 action negativeInit=owner.then(readAcquire(1)).then(close)
 action negativeStep=unsafeAcquireCas
 run ownerAccountedBeforeReplyTest=owner.then(queryUnknown).then(check)
 run delegatedPermitTest=owner.then(readAcquire(1)).then(acquireCas).then(release(1)).then(check)
 run closeWinsReadCasTest=owner.then(readAcquire(1)).then(close).then(failedCas).then(check)
 run acquireWinsCloseTest=owner.then(readAcquire(1)).then(acquireCas).then(close).then(release(1)).then(drainOwner).then(check)
 run lateAcquireAfterHandoffTest=owner.then(readAcquire(1)).then(finishOwner).then(take(2)).then(failedCas).then(check)
 run spentRoleNeverReusedTest=owner.then(readAcquire(1)).then(acquireCas).then(release(1)).then(usedRoleReject).then(check)
 run duplicateReleaseDoesNotChangeOthersTest=owner.then(readAcquire(1)).then(acquireCas).then(release(1)).then(release(1)).then(check)
 run lostHandoffResponseTest=helper.then(queryUnknown).then(replayTake).then(check)
 run staleReleasePreservesHelperTest=helper.then(staleRelease).then(check)
 run separateClassDrainTest=helper.then(close).then(release(0)).then(check)
 run secondHelperInterruptionTest=helper.then(readAcquire(5)).then(acquireCas).then(close).then(drainOwner).then(queryUnknown).then(release(5)).then(take(1)).then(check)
 run generationExhaustionTest=helper.then(finishOwner).then(take(1)).then(finishOwner).then(exhaustedReject).then(check)
 run allRolesTest=owner.then(readAcquire(1)).then(acquireCas).then(readAcquire(2)).then(acquireCas).then(readAcquire(3)).then(acquireCas).then(readAcquire(5)).then(acquireCas).then(readAcquire(6)).then(acquireCas).then(readAcquire(7)).then(acquireCas).then(check)
 run invalidRoleRejectedTest=owner.then(invalidRoleReject).then(check)
 run delayedCasAfterCloseCounterexampleTest=negativeInit.then(unsafeAcquireCas).then(reject)
 run spentRoleReusedCounterexampleTest=owner.then(readAcquire(1)).then(acquireCas).then(release(1)).then(unsafeReuseSpent).then(reject)
 run liveOwnerBypassedCounterexampleTest=owner.then(close).then(unsafeTake).then(reject)
 run oldGenerationReleaseCounterexampleTest=helper.then(unsafeOldRelease).then(reject)
}
