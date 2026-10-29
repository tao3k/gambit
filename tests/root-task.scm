;;; gambit.smp.gc.root-task: native replay, independent oracle and shrinking.
;;; RC, VM, bank, stack, symbol/keyword and global-variable origins share this generator, oracle, replay and shrink driver.
;;; Each replay is a fresh process. No Scheme allocation while a source is frozen.
(c-declare #<<c-end
#include "rc.h"
#include "mem.h"
#include "os_thread.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void *root_task_bytes;
static void replay_intern(___SCMOBJ,___SCMOBJ,int);
static void replay_global_snapshot(___SCMOBJ,___SCMOBJ,int);
c-end
)
(define prepare-source
  (c-lambda () bool "root_task_bytes=___EXT(___alloc_rc)(___PSA(___PSTATE) 1); ___result=root_task_bytes!=0;"))
(define replay-native
  (c-lambda (scheme-object scheme-object int int) void #<<c-end
___processor_state ps=___PSTATE;
___rc_domain *d=ps->mem.rc_domain_;
___UWORD base, receipt;
___root_task local_task, *task;
___global_root_source globals_source;
___global_root_snapshot globals_snapshot;
___execution_context *bank=ps->context;
___SCMOBJ commands=___arg1, expected_rows=___arg2;
int mutation=___arg3;
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
___WORD alien_source=0;
int family=___arg4;
if(family==6) replay_global_snapshot(commands,expected_rows,mutation);
if(family==7) replay_intern(commands,expected_rows,mutation);
int i,n=___INT(___VECTORLENGTH(commands));
___RC_LOCK(d);
base=d->task.epoch;
if(d->phase!=___RC_OPEN || d->task.state!=___ROOT_DONE || d->task.scan_leases!=0) {
  ___RC_UNLOCK(d); printf("(root-task-result precondition 0)\n"); fflush(stdout); _Exit(72);
}
{
  ___rc_header *h;
  for(h=d->head.next;h!=&d->head;h=h->next) if(h->data!=___FAL) {
    ___RC_UNLOCK(d); printf("(root-task-result precondition 1)\n"); fflush(stdout); _Exit(72);
  }
}
___RC_UNLOCK(d);
if(family) {
  if(vm->processor_count!=1) { printf("(root-task-result precondition 2)\n"); fflush(stdout); _Exit(72); }
  /* Snapshot C arguments before touching the register bank. No Scheme
   * allocation/callback/return follows; each trial destroys its child image. */
  if(family==1) {
    ___SCMOBJ *cells=___BODY0_AS(___VM_SCMOBJ(vm),___tSUBTYPED);
    for(i=0;i<___VM_SIZE;i++) cells[i]=___FAL;
  } else if(family==2) {
    ___SCMOBJ *cells=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank->processor_scmobj,___WS)),___tSUBTYPED);
    for(i=0;i<sizeof(bank->r)/sizeof(*bank->r);i++) bank->r[i]=___FAL;
    for(i=0;i<sizeof(bank->saved)/sizeof(*bank->saved);i++) bank->saved[i]=___FAL;
    for(i=0;i<sizeof(bank->type_cache)/sizeof(*bank->type_cache);i++) bank->type_cache[i]=___FAL;
    for(i=0;i<___PROCESSOR_SIZE;i++) cells[i]=___FAL;
  } else if(family==3) {
    /* Control replay uses an empty break anchor, not fabricated frame bodies.
     * Full active/captured frames are exercised by the Scheme histories below.
     * No Scheme allocation, callback or return may follow this reset. */
    bank->fp=bank->stack_break;
    ___FP_STK(bank->stack_break,-___BREAK_FRAME_NEXT)=___END_OF_CONT_MARKER;
  } else if(family==4) {
    /* Immediate-only control replay. No Scheme allocation, symbol lookup,
     * callback or return follows before _Exit in this disposable p1 child. */
    ___GSTATE->symbol_table=___FAL; ___GSTATE->keyword_table=___FAL;
  } else {
    /* Snapshot all C commands first; no Scheme operation follows. Clear the
     * actual globals payload, never the registry count or roster. */
#ifdef ___SINGLE_VM
    int bucket;
    for(bucket=0;bucket<___GLO_SUBLIST_COUNT;bucket++) {
      ___glo_struct *glo=___GSTATE->mem.glo_list.sublist[bucket].head;
      for(;glo!=0;glo=glo->next) glo->val=___FAL;
    }
#else
    for(i=0;i<___GSTATE->mem.glo_list.count;i++) vm->glos[i]=___FAL;
#endif
  }
  if(family==5 &&
     (!___root_task_publish(d,ps,base,&receipt) ||
      !___root_globals_begin(&globals_snapshot,ps,receipt))) {
    printf("(root-task-result precondition 3)\n"); fflush(stdout); _Exit(72);
  }
  ___root_task_init(&local_task,base);
}
task=family?&local_task:&d->task;
for(i=0;i<n;i++) {
  ___SCMOBJ row=___VECTORELEM(commands,i), expected=___VECTORELEM(expected_rows,i);
  int op=___INT(___VECTORELEM(row,0)), delta=___INT(___VECTORELEM(row,1));
  ___processor_state actor=___INT(___VECTORELEM(row,2))==0?ps:0;
  ___UWORD key=base+delta;
  long observed[5];
  int accepted=0,j;
  /* Calibrated adapter mutation: production finish must reject the stale key.
   * The oracle remains unchanged; this is not a production runtime defect. */
  if(mutation==1 && op==3 && delta==1 && actor==ps) --key;
  if(family==1) switch(op) {
  case 0: accepted=___root_task_publish_vm(task,vm,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_vm(task,actor,key); break;
  case 2: accepted=___root_task_scan_vm(task,actor,key); break;
  case 3: accepted=___root_task_finish_vm(task,actor,key); break;
  case 4: accepted=___root_task_publish_vm(task,___CAST(___virtual_machine_state,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_vm(task,actor,key); break;
  } else if(family==2) switch(op) {
  case 0: accepted=___root_task_publish_bank(task,bank,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_bank(task,actor,key); break;
  case 2: accepted=___root_task_scan_bank(task,actor,key); break;
  case 3: accepted=___root_task_finish_bank(task,actor,key); break;
  case 4: accepted=___root_task_publish_bank(task,___CAST(___execution_context*,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_bank(task,actor,key); break;
  } else if(family==3) switch(op) {
  case 0: accepted=___root_task_publish_stack(task,bank,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_stack(task,actor,key); break;
  case 2: accepted=___root_task_scan_stack(task,actor,key); break;
  case 3: accepted=___root_task_finish_stack(task,actor,key); break;
  case 4: accepted=___root_task_publish_stack(task,___CAST(___execution_context*,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_stack(task,actor,key); break;
  } else if(family==4) switch(op) {
  case 0: accepted=___root_task_publish_symkey(task,___GSTATE,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_symkey(task,actor,key); break;
  case 2: accepted=___root_task_scan_symkey(task,actor,key); break;
  case 3: accepted=___root_task_finish_symkey(task,actor,key); break;
  case 4: accepted=___root_task_publish_symkey(task,___CAST(___global_state,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_symkey(task,actor,key); break;
  } else if(family==5) switch(op) {
  case 0: accepted=___root_task_publish_globals(task,&globals_source,vm,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim_globals(task,actor,key); break;
  case 2: accepted=___root_task_scan_globals(task,actor,key); break;
  case 3: accepted=___root_task_finish_globals(task,actor,key); break;
  case 4: accepted=___root_task_publish_globals(task,&globals_source,___CAST(___virtual_machine_state,&alien_source),actor,key,&receipt); break;
  case 5: accepted=___root_task_completed_globals(task,actor,key); break;
  case 6: {
    /* Adversarial metadata input, not a production mutation/recovery API.
     * There is no running scan in this synchronous child. Restore only test
     * metadata after checking that an altered view cannot acquire a claim. */
    if(task->origin.kind==___ROOT_GLOBALS) {
      ___global_root_source saved=globals_source;
      switch(delta) {
      case -1: globals_source.count++; break;
      case 0: globals_source.lo++; break;
      case 1: globals_source.participants++; break;
      case 2: globals_source.vm=___CAST(___virtual_machine_state,&alien_source); break;
      }
      accepted=___root_task_claim_globals(task,actor,base+1);
      globals_source=saved;
    }
    break;
  }
  } else switch(op) {
  case 0: accepted=___root_task_publish(d,actor,key,&receipt); break;
  case 1: accepted=___root_task_claim(d,actor,key); break;
  case 2: accepted=___root_task_scan(d,actor,key); break;
  case 3: accepted=___root_task_finish(d,actor,key); break;
  case 4: accepted=___rc_prepare_cleanup(ps); if(accepted) ___rc_cancel_cleanup(ps); break;
  case 5: accepted=___root_task_completed(d,actor,key); break;
  }
  ___RC_LOCK(d);
  observed[0]=accepted; observed[1]=task->state;
  observed[2]=family?(task->origin.kind!=___ROOT_NONE):d->phase;
  observed[3]=task->scan_leases; observed[4]=task->epoch-base;
  ___RC_UNLOCK(d);
  for(j=0;j<5;j++) if(observed[j]!=___INT(___VECTORELEM(expected,j))) {
    printf("(root-task-result mismatch %d %d %d %ld %ld (%ld %ld %ld %ld %ld))\n",i,op,j,
      (long)___INT(___VECTORELEM(expected,j)),observed[j],observed[0],observed[1],observed[2],observed[3],observed[4]);
    fflush(stdout); _Exit(71);
  }
}
printf("(root-task-result pass %d)\n",n); fflush(stdout);
/* Prefixes may intentionally retain a claim/lease. Never reset that state in
 * process merely to shrink another trial. The OS reclaims this child image. */
_Exit(0);
c-end
))

;;; The existing replay/shrinker drives a second actual C source contract.
;;; Four pre-created permanent symbols avoid pretending to qualify concurrent
;;; interning. A real second VM supplies an OPEN registration source while the
;;; first VM is frozen. No Scheme operation follows the destructive control cut.
(c-declare #<<c-end
static void replay_global_snapshot(___SCMOBJ commands,___SCMOBJ expected,int mutation)
{
#ifdef ___SINGLE_VM
  printf("(root-task-result unsupported multiple-vms-required)\n");fflush(stdout);_Exit(72);
#else
  ___processor_state ps=___PSTATE, writer;
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps), other;
  ___SCMOBJ symbols[4], err;
  ___global_root_snapshot snapshot;
  ___global_root_source source;
  ___root_task task;
  ___UWORD base,epoch,receipt;
  int i,j,n=___INT(___VECTORLENGTH(commands)),initial,active=0;
  char name[80];
  if(vm->processor_count!=1) _Exit(72);
  for(i=0;i<4;i++) {
    snprintf(name,sizeof(name),"___globals_snapshot_identity_%d",i);
    symbols[i]=___make_symkey_from_UTF_8_string(name,___sSYMBOL);
    if(___FIXNUMP(symbols[i]) || ___GLOBALVARSTRUCT(symbols[i])!=0) _Exit(72);
  }
  other=calloc(1,sizeof(*other));
  if(other==0 || ___setup_vmstate(other)!=___FIX(___NO_ERR)) _Exit(72);
  writer=___PSTATE_FROM_PROCESSOR_ID(0,other);
  if(writer->mem.rc_domain_==0 || other->glos==0) _Exit(72);
  initial=___CAST(int,___GSTATE->mem.glo_list.count);
  for(i=0;i<initial;i++) vm->glos[i]=___FAL;
  base=ps->mem.rc_domain_->task.epoch;
  ___root_task_init(&task,base);
  for(i=0;i<n;i++) {
    ___SCMOBJ row=___VECTORELEM(commands,i),want=___VECTORELEM(expected,i);
    int op=___INT(___VECTORELEM(row,0)),slot=___INT(___VECTORELEM(row,1))+1;
    int accepted=0,old=___CAST(int,___GSTATE->mem.glo_list.count);
    long seen[5];
    if(op==0 || op==2 || op==8) {
      if(op==8) ___SET_REAL_PSTATE(0);
      else ___thread_set_pstate(op==0?ps:writer);
      err=___make_global_var(symbols[slot]);
      ___thread_set_pstate(ps);
      accepted=err==symbols[slot];
      if(___GSTATE->mem.glo_list.count>old && op==2 && vm->glos[old]!=___UNB1) _Exit(73);
    } else if(op==1 && !active && vm->mem.globals_snapshot_==0 &&
              ps->mem.rc_domain_->phase==___RC_OPEN) {
      accepted=___root_task_publish(ps->mem.rc_domain_,ps,base,&epoch) &&
               ___root_globals_begin(&snapshot,ps,epoch);
      if(accepted) active=1;
    } else if(op==3) accepted=___root_task_publish_globals(&task,&source,vm,ps,base,&receipt);
    else if(op==4) accepted=___root_task_claim_globals(&task,ps,base+1);
    else if(op==5) accepted=___root_task_scan_globals(&task,ps,base+1);
    else if(op==6) accepted=___root_task_finish_globals(&task,ps,base+1);
    else if(op==7 && active) {
      accepted=___root_globals_end(&snapshot,ps);
      if(accepted) active=0;
    }
    seen[0]=accepted;seen[1]=___GSTATE->mem.glo_list.count-initial;
    seen[2]=active?(task.origin.kind==___ROOT_GLOBALS?source.count:snapshot.count)-initial:-1;
    /* A labeled live-count observer mutation calibrates this same C replay;
     * it does not replace the production implementation or oracle. */
    if(mutation && active) seen[2]=___GSTATE->mem.glo_list.count-initial;
    seen[3]=task.state;seen[4]=task.scan_leases;
    for(j=0;j<5;j++) if(seen[j]!=___INT(___VECTORELEM(want,j))) {
      printf("(root-task-result mismatch %d %d %ld %ld (%ld %ld %ld %ld %ld))\n",
        i,op,(long)j,seen[j],seen[0],seen[1],seen[2],seen[3],seen[4]);
      fflush(stdout);_Exit(71);
    }
  }
  printf("(root-task-result pass %d)\n",n);fflush(stdout);_Exit(0);
#endif
}
c-end
)
(define (snapshot-oracle commands)
  (let ((registered (make-vector 4 #f)) (added 0) (captured -1)
        (phase 0) (state 0) (lease 0))
    (list->vector
     (map (lambda (row)
            (let ((op (vector-ref row 0)) (slot (+ 1 (vector-ref row 1))) (ok #f))
              (case op
                ((0 2 8)
                 (set! ok (or (vector-ref registered slot) (= op 2)
                              (and (= op 0) (= phase 0))))
                 (if (and ok (not (vector-ref registered slot)))
                     (begin (vector-set! registered slot #t) (set! added (+ added 1)))))
                ((1) (if (= phase 0) (begin (set! phase 1) (set! captured added) (set! ok #t))))
                ((3) (if (= phase 1) (begin
                         (if (= state 0) (begin (set! state 1) (set! lease 1))) (set! ok #t))))
                ((4) (if (and (= phase 1) (= state 1)) (begin (set! state 2) (set! ok #t))))
                ((5) (if (and (= phase 1) (= state 2)) (begin (set! state 4) (set! ok #t))))
                ((6) (if (and (= phase 1) (memv state '(4 5)))
                         (begin (set! state 5) (set! lease 0) (set! ok #t))))
                ((7) (if (and (= phase 1) (= state 5))
                         (begin (set! phase 2) (set! captured -1) (set! ok #t)))))
              (vector (if ok 1 0) added captured state lease))) commands))))

(c-declare #<<c-end
#ifdef ___USE_POSIX_THREAD_SYSTEM
typedef struct intern_trial_gate {
  pthread_mutex_t mutex;
  pthread_cond_t cond;
  const char *name;
  unsigned int type;
  int started,missed,done0,armed;
  ___SCMOBJ values[2];
} intern_trial_gate;
static intern_trial_gate *intern_current_gate;
static ___THREAD_LOCAL_STORAGE_CLASS int intern_actor_rank=-1;
/* The predecessor-only mutation calls this after a real lookup miss. Both
 * actors miss before rank0 constructs, then rank1 waits for rank0 to return.
 * Thus the retained old failure needs no concurrent bucket writes or UB. */
void test_symkey_split(const char *name)
{
  intern_trial_gate *g=intern_current_gate;
  if(!g || !g->armed || strcmp(name,g->name)!=0 || intern_actor_rank<0) return;
  pthread_mutex_lock(&g->mutex);++g->missed;pthread_cond_broadcast(&g->cond);
  if(intern_actor_rank==0) { while(g->missed<2) pthread_cond_wait(&g->cond,&g->mutex); }
  else { while(!g->done0) pthread_cond_wait(&g->cond,&g->mutex); }
  pthread_mutex_unlock(&g->mutex);
}
static void *intern_actor(void *which)
{
  intern_trial_gate *g=intern_current_gate;
  int i=(int)(size_t)which;intern_actor_rank=i;
  pthread_mutex_lock(&g->mutex);++g->started;pthread_cond_broadcast(&g->cond);
  while(g->started<2) pthread_cond_wait(&g->cond,&g->mutex);
  pthread_mutex_unlock(&g->mutex);
  g->values[i]=___make_symkey_from_UTF_8_string((char*)g->name,g->type);
  pthread_mutex_lock(&g->mutex);if(i==0) g->done0=1;
  pthread_cond_broadcast(&g->cond);pthread_mutex_unlock(&g->mutex);
  return 0;
}
static ___SCMOBJ intern_concurrent(char *name,unsigned int type,int fresh,int *same)
{
  intern_trial_gate g;pthread_t threads[2];int i;
  memset(&g,0,sizeof(g));g.name=name;g.type=type;g.armed=fresh;
  if(pthread_mutex_init(&g.mutex,0) || pthread_cond_init(&g.cond,0)) _Exit(75);
  intern_current_gate=&g;
  for(i=0;i<2;i++) if(pthread_create(&threads[i],0,intern_actor,(void*)(size_t)i)) _Exit(75);
  for(i=0;i<2;i++) if(pthread_join(threads[i],0)) _Exit(75);
  *same=g.values[0]==g.values[1];intern_current_gate=0;
  pthread_cond_destroy(&g.cond);pthread_mutex_destroy(&g.mutex);
  return g.values[0];
}
#else
void test_symkey_split(const char *name) { (void)name; }
#endif
typedef struct intern_visit_data { ___SCMOBJ *known;int seen[4],ok; } intern_visit_data;
static void intern_visit(___SCMOBJ sym,void *data)
{
  intern_visit_data *d=(intern_visit_data*)data;int k;
  for(k=0;k<4;k++) if(sym==d->known[k]) { if(d->seen[k]) d->ok=0;d->seen[k]=1; }
}
static void replay_intern(___SCMOBJ commands,___SCMOBJ expected,int mutation)
{
#ifndef ___USE_POSIX_THREAD_SYSTEM
  printf("(root-task-result unsupported posix-required)\n");fflush(stdout);_Exit(72);
#else
  ___processor_state ps=___PSTATE;
  int rows[96][3],wanted[96][5],n=___INT(___VECTORLENGTH(commands));
  int initial[2],i,j,k;
  char names[4][80];___SCMOBJ strings[4],known[2][4];
  if(n>96 || ___VMSTATE_FROM_PSTATE(ps)->processor_count!=1) _Exit(72);
  for(i=0;i<n;i++) {
    for(j=0;j<3;j++) rows[i][j]=___INT(___VECTORELEM(___VECTORELEM(commands,i),j));
    for(j=0;j<5;j++) wanted[i][j]=___INT(___VECTORELEM(___VECTORELEM(expected,i),j));
  }
  for(k=0;k<4;k++) {
    snprintf(names[k],sizeof(names[k]),"gambit.smp.symkey-publication.%d",k);
    if(___NONNULLUTF_8STRING_to_SCMOBJ(0,names[k],&strings[k],-1)!=___FIX(___NO_ERR)) _Exit(72);
    for(j=0;j<2;j++) {
      known[j][k]=___FAL;
      if(___find_symkey_from_UTF_8_string(names[k],j?___sKEYWORD:___sSYMBOL)!=___FAL) _Exit(72);
    }
  }
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  initial[0]=___INT(___VECTORELEM(___GSTATE->symbol_table,0));
  initial[1]=___INT(___VECTORELEM(___GSTATE->keyword_table,0));
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  for(i=0;i<n;i++) {
    int op=rows[i][0],slot=rows[i][1]+1,t=rows[i][2],same=1,ok=1,found=0;
    unsigned int type=t?___sKEYWORD:___sSYMBOL;
    ___SCMOBJ result=___FAL;long seen[5];
    switch(op) {
    case 0: case 3: result=___find_symkey_from_UTF_8_string(names[slot],type);break;
    case 1: result=___make_symkey_from_UTF_8_string(names[slot],type);break;
    case 2: result=___make_symkey_from_scheme_string(strings[slot],type);break;
    case 4: result=___new_symkey(strings[slot],type);break;
    case 5: ok=!___EXT(___garbage_collect)(___PSA(ps) 0);break;
    case 6: result=intern_concurrent(names[slot],type,known[t][slot]==___FAL,&same);break;
    case 7: {
      intern_visit_data d;memset(&d,0,sizeof(d));d.known=known[t];d.ok=1;
      ___for_each_symkey(type,intern_visit,&d);
      for(k=0;k<4;k++) if(d.seen[k]!=(known[t][k]!=___FAL)) d.ok=0;
      ok=d.ok;break;
    }
    case 8: result=___make_symkey_from_UTF_8_string("\xc0",type);ok=0;
      if(!___FIXNUMP(result)) _Exit(76);result=___FAL;break;
    }
    if(result!=___FAL) {
      if(___FIXNUMP(result)) ok=0;
      else {
        found=1;
        if(known[t][slot]==___FAL) known[t][slot]=result;
        else if(result!=known[t][slot]) same=0;
        if(___find_symkey_from_scheme_string(strings[slot],type)!=result) same=0;
      }
    }
    seen[0]=ok;
    ___MUTEX_LOCK(___GSTATE->mem.global_gate);
    seen[1]=___INT(___VECTORELEM(___GSTATE->symbol_table,0))-initial[0];
    seen[2]=___INT(___VECTORELEM(___GSTATE->keyword_table,0))-initial[1];
    ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
    seen[3]=found;seen[4]=same;
    if(mutation && op==4) seen[4]=0;
    for(j=0;j<5;j++) if(seen[j]!=wanted[i][j]) {
      printf("(root-task-result mismatch %d %d %d %ld (%ld %ld %ld %ld %ld))\n",
       i,op,j,seen[j],seen[0],seen[1],seen[2],seen[3],seen[4]);fflush(stdout);_Exit(71);
    }
  }
  printf("(root-task-result pass %d)\n",n);fflush(stdout);_Exit(0);
#endif
}
c-end
)
(define (intern-oracle commands)
  (let ((have (vector (make-vector 4 #f) (make-vector 4 #f))) (counts (vector 0 0)))
    (list->vector
     (map (lambda (row)
            (let* ((op (vector-ref row 0)) (slot (+ 1 (vector-ref row 1)))
                   (t (vector-ref row 2)) (keys (vector-ref have t))
                   (make? (memv op '(1 2 4 6))))
              (if (and make? (not (vector-ref keys slot)))
                  (begin (vector-set! keys slot #t)
                         (vector-set! counts t (+ 1 (vector-ref counts t)))))
              (vector (if (= op 8) 0 1) (vector-ref counts 0) (vector-ref counts 1)
                      (if (and (memv op '(0 1 2 3 4 6)) (vector-ref keys slot)) 1 0) 1))) commands))))

;;; The oracle describes externally observable requests. SCANNED is the native
;;; refinement cut after the real scanner, before root_dispatch.finish.
(c-declare #<<c-end
/* The predecessor function body is copied from the selected86fdffcc source;
 * only its function name changes. Production has no old-writer fallback. */
___BOOL test_rc_write_predecessor(___processor_state ps, void *ptr, ___SCMOBJ value)
{
  ___rc_header *h;
  ___rc_domain *d;
  if (ptr == 0 || ps == 0 || ps != ___PSTATE) return 0;
  h=___CAST(___rc_header*,ptr)-1; d=h->domain;
  if (d == 0 || d != ps->mem.rc_domain_) return 0;
  ___RC_LOCK(d);
  if (d->owner != ps || d->phase != ___RC_OPEN || h->refcount <= 0)
    { ___RC_UNLOCK(d); return 0; }
  h->data=value;
  ___RC_UNLOCK(d);
  return 1;
}


static void *test_rc_write_slots[4];
static const ___SCMOBJ *test_rc_write_cells[4][2];
c-end
)
(define rc-write-act
 (c-lambda (int int bool scheme-object scheme-object) int #<<c-end
int op=___arg1,i=___arg2,b=0,refs=0;
void *p=test_rc_write_slots[i];
___rc_header *h=p?(___rc_header*)p-1:0;
___SCMOBJ value=___arg4;
___result=0;
if(p) { b=h->root_borrows; refs=___EXT(___refcount_rc)(p); }
switch(op) {
case 0:
  if(!p) {
    p=___EXT(___alloc_rc)(___PSA(___PSTATE) 0);
    if(p && ___try_set_data_rc(___PSTATE,p,value)) { test_rc_write_slots[i]=p; ___result=1; }
    else if(p) ___EXT(___release_rc)(p);
  } break;
case 1:
  if(p && b<2) {
    test_rc_write_cells[i][b]=___borrow_rc_root(___PSTATE,p);
    ___result=test_rc_write_cells[i][b]!=0;
  } break;
case 2: case 7:
  if(p) ___result=___arg3?test_rc_write_predecessor(___PSTATE,p,value):___try_set_data_rc(___PSTATE,p,value);
  break;
case 3:
  if(p && b>0) {
    ___return_rc_root(p); test_rc_write_cells[i][b-1]=0;
    if(refs==0 && b==1) test_rc_write_slots[i]=0;
    ___result=1;
  } break;
case 4:
  if(p && refs>0) {
    ___EXT(___release_rc)(p);
    if(refs==1 && b==0) test_rc_write_slots[i]=0;
    ___result=1;
  } break;
case 5:
  if(p && refs>0 && refs<3) { ___EXT(___addref_rc)(p); ___result=1; } break;
case 6: ___result=1; break; /* Scheme performs the real GC before inspection. */
case 8: {
  const ___SCMOBJ *a,*z; int accepted,unchanged;
  p=___EXT(___alloc_rc)(___PSA(___PSTATE) 0);
  if(!p || !___try_set_data_rc(___PSTATE,p,___arg4)) _Exit(74);
  a=___borrow_rc_root(___PSTATE,p); z=___borrow_rc_root(___PSTATE,p);
  if(!a || !z) _Exit(74);
  accepted=___arg3?test_rc_write_predecessor(___PSTATE,p,___arg5):___try_set_data_rc(___PSTATE,p,___arg5);
  unchanged=*a==___arg4 && *z==___arg4;
  ___return_rc_root(p); ___return_rc_root(p); ___EXT(___release_rc)(p);
  ___result=!accepted && unchanged;
} break;
}
c-end
))
(define rc-write-inspect
 (c-lambda (int int int scheme-object) bool #<<c-end
void *p=test_rc_write_slots[___arg1];
int j;
___result=p?(___EXT(___refcount_rc)(p)==___arg2 &&
  ((___rc_header*)p-1)->root_borrows==___arg3 && ___EXT(___data_rc)(p)==___arg4):(___arg2==0 && ___arg3==0);
if(p) for(j=0;j<___arg3;j++)
  if(!test_rc_write_cells[___arg1][j] || *test_rc_write_cells[___arg1][j]!=___arg4) ___result=0;
c-end
))
(define rc-write-exit
  (c-lambda (int) void "fflush(stdout);fflush(stderr);_Exit(___arg1);"))
(define (replay-rc-write commands fault)
  (let ((refs (make-vector 4 0)) (loans (make-vector 4 0))
        (tags (make-vector 4 -1)) (objects (make-vector 8 #f)) (gcs 0))
    (do ((i 0 (+ i 1))) ((= i 8)) (vector-set! objects i (vector i 0)))
    (let loop ((xs commands) (at 0))
      (if (null? xs)
          (begin
            (do ((i 0 (+ i 1))) ((= i 4))
              (do ((b (vector-ref loans i) (- b 1))) ((= b 0))
                (rc-write-act 3 i #f #f #f))
              (do ((n (vector-ref refs i) (- n 1))) ((= n 0))
                (rc-write-act 4 i #f #f #f)))
            (write (list 'root-task-result 'pass at 'gc gcs)) (newline) (exit))
          (let* ((row (car xs)) (op (vector-ref row 0))
                 (slot (modulo (+ 1 (vector-ref row 1)) 4)) (tag (vector-ref row 2))
                 (n (vector-ref refs slot)) (b (vector-ref loans slot))
                 (live (or (> n 0) (> b 0)))
                 (chosen (if (= op 7) (max 0 (vector-ref tags slot)) tag))
                 (value (vector-ref objects (+ (* slot 2) chosen)))
                 (other (vector-ref objects (+ (* slot 2) (- 1 chosen))))
                 (wanted (case op
                           ((0) (if live 0 1))
                           ((1) (if (and (> n 0) (< b 2)) 1 0))
                           ((2) (if (and (> n 0) (or (= b 0) (= chosen (vector-ref tags slot)))) 1 0))
                           ((3) (if (> b 0) 1 0))
                           ((4) (if (> n 0) 1 0))
                           ((5) (if (and (> n 0) (< n 3)) 1 0))
                           ((6 8) 1)
                           ((7) (if (> n 0) 1 0))))
                 (actual
                  (begin
                    ;; Mutable contents remain legal: only slot rebinding is closed.
                    (if (and (= op 7) live) (vector-set! value 1 (+ 1 (vector-ref value 1))))
                    (rc-write-act op slot (= fault 1) value other))))
            (if (not (= actual wanted))
                (begin (write (list 'root-task-result 'mismatch at op 0 actual wanted))
                       (newline) (force-output) (rc-write-exit 71)))
            (if (= actual 1)
                (case op
                  ((0) (vector-set! refs slot 1) (vector-set! tags slot chosen))
                  ((1) (vector-set! loans slot (+ b 1)))
                  ((2) (vector-set! tags slot chosen))
                  ((3) (vector-set! loans slot (- b 1)))
                  ((4) (vector-set! refs slot (- n 1)))
                  ((5) (vector-set! refs slot (+ n 1)))))
            (if (= op 6) (begin (set! gcs (+ gcs 1)) (##gc)))
            (do ((i 0 (+ i 1))) ((= i 4))
              (let* ((rn (vector-ref refs i)) (bn (vector-ref loans i))
                     (tag (max 0 (vector-ref tags i)))
                     (expected (vector-ref objects (+ (* i 2) tag))))
                (if (not (rc-write-inspect i rn bn expected))
                    (begin (write (list 'root-task-result 'mismatch at op 1 i rn bn))
                           (newline) (force-output) (rc-write-exit 71)))))
            (loop (cdr xs) (+ at 1)))))))
(define (rc-write-suite)
  (set! family 'rc-write) (set! trials 0)
  (let ((seed 1729) (actions 0))
    (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
    (define (noise n)
      (if (= n 0) '() (cons (vector (next 8) (- (next 4) 1) (next 2)) (noise (- n 1)))))
    (define chain
      '(#(0 0 0) #(1 0 0) #(1 0 0) #(2 0 1) #(6 0 0) #(7 0 0)
        #(3 0 0) #(2 0 1) #(4 0 0) #(6 0 0) #(2 0 1) #(3 0 0)
        #(6 0 0) #(0 0 1) #(2 0 0) #(8 0 0)))
    (let ((result (trial chain 0)))
      (if (signature result) (error "RC writer mandatory history failed" result))
      (write (list 'RC-WRITE-MOVING-BORROW-PASS result)) (newline))
    (set! actions (length chain))
    (do ((i 0 (+ i 1))) ((= i 12))
      (let* ((commands (append (noise 8) chain (noise 8))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (error "RC writer stateful property failed" result (shrink commands 0 (signature result))))))
    (write (list 'RC-WRITE-PBT-PASS 'seed 1729 'cases 12 'actions actions)) (newline)
    (let* ((commands (append (make-list 6 '#(6 0 0)) (list '#(8 0 0)) (make-list 6 '#(6 0 0))))
           (failure (trial commands 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(8 0))) (error "actual predecessor writer control missed" failure))
      (let* ((minimal (shrink commands 1 wanted)) (again (trial minimal 1))
             (one? (one-minimal? minimal 1 wanted)) (positive (trial minimal 0)))
        (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted) (not (signature positive))))
            (error "actual RC writer shrink/replay failed" minimal again positive))
        (for-each
         (lambda (pair) (with-output-to-file (trace-file (car pair))
                          (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
         '(("legacy-minimal" . 1) ("current-minimal" . 0)))
        (write (list 'RC-WRITE-IMPLEMENTATION-SHRINK-PASS 'from 13 'to (length minimal)
                     'deletion-one-minimal one? 'replayed #t 'production-pass #t)) (newline)))
    (delete-file input-file)))

(cond-expand
 (marker-input-test
;;; Explicit scalar marker inputs reuse the existing replay and shrink driver.
;;; The optional allocator adapter compiles the actual c_intf.c, not a model.
(c-declare #<<c-end
#ifdef ___TEST_MARKER_INPUT
#include "c_intf.h"
static int test_marker_mode, test_marker_collections;
static ___SIZE_T test_marker_base_nodes,test_marker_base_borrows;
static int test_marker_custody;
void *test_marker_alloc(___PSD ___SIZE_T bytes)
{
  ___PSGET
  if (test_marker_mode==3) return 0;
  return ___EXT(___alloc_rc)(___PSP bytes);
}
const ___SCMOBJ *test_marker_borrow(___processor_state ps,void *ptr)
{
  if (test_marker_mode==4) return 0;
  return ___borrow_rc_root(ps,ptr);
}
___SCMOBJ test_marker_vector(___processor_state ps,___SIZE_TS n,___SCMOBJ init)
{
  ___rc_domain *d=ps->mem.rc_domain_;
  ___SIZE_T extra=test_marker_mode==6?0:1;
  ___RC_LOCK(d);
  test_marker_custody=d->nodes==test_marker_base_nodes+extra &&
    d->borrows==test_marker_base_borrows+extra;
  ___RC_UNLOCK(d);
  if (test_marker_mode==2) return ___FIX(___HEAP_OVERFLOW_ERR);
  if (test_marker_mode==1 || test_marker_mode==5 || test_marker_mode==6) {
    if (___garbage_collect(___PSA(ps) 0)) return ___FIX(___HEAP_OVERFLOW_ERR);
    ++test_marker_collections;
  }
  return ___EXT(___make_vector)(ps,n,init);
}
/* Selected920cf0c7 explicit-value constructor sequence. The false selector is
 * outside this test: no closure trampoline/provider is substituted here. */
static ___SCMOBJ test_marker_predecessor(___processor_state ps,
                                       ___SCMOBJ *marker,___SCMOBJ proc)
{
  ___SCMOBJ x=test_marker_vector(ps,
#ifdef ___SINGLE_THREADED_VMS
                                1,
#else
                                2,
#endif
                                ___FAL);
  if (___FIXNUMP(x)) return ___FIX(___SFUN_HEAP_OVERFLOW_ERR);
  ___VECTORELEM(x,0)=proc;
#ifndef ___SINGLE_THREADED_VMS
  ___VECTORELEM(x,1)=___FIX(___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps)));
#endif
  *marker=x;
  return ___FIX(___NO_ERR);
}
#endif
c-end
)
(define marker-input-act
 (c-lambda (scheme-object int bool) bool #<<c-end
#ifndef ___TEST_MARKER_INPUT
___result=0;
#else
___processor_state ps=___PSTATE;
___rc_domain *d=ps->mem.rc_domain_;
___SIZE_T nodes,borrows;
___SCMOBJ before=___arg1,marker=___FAL,err;
const ___SCMOBJ *cell=0;
void *held=0;
int op=___arg2,ok=1;
___RC_LOCK(d);nodes=d->nodes;borrows=d->borrows;___RC_UNLOCK(d);
test_marker_mode=op;test_marker_collections=0;test_marker_custody=1;
test_marker_base_nodes=nodes;test_marker_base_borrows=borrows;
if(op==6 && (!___TESTTYPE(before,___tSUBTYPED) ||
   ___HD_TYP(___SUBTYPED_HEADER(before))!=___PERM)) _Exit(76);
if(op==5) {
  held=___EXT(___alloc_rc)(___PSA(ps) 0);
  if(!held || !___try_set_data_rc(ps,held,___arg1)) _Exit(74);
  cell=___borrow_rc_root(ps,held);
  if(!cell) _Exit(74);
  err=___make_sfun_stack_marker_root(ps,&marker,cell);
} else if(___arg3 && op==1) {
  err=test_marker_predecessor(ps,&marker,before);
} else {
  err=___EXT(___make_sfun_stack_marker)(ps,&marker,before);
}
test_marker_mode=0;
if(op>=2 && op<=4)
  ok=err==___FIX(___SFUN_HEAP_OVERFLOW_ERR) && marker==___FAL;
else {
  ok=err==___FIX(___NO_ERR) && marker!=___FAL;
  if(ok) {
    /* Compare to the caller's GC-updated CFUN_ARG; never dereference stale
     * predecessor memory. Clear the marker before any subsequent collection. */
    ok=___VECTORELEM(marker,0)==___arg1;
#ifndef ___SINGLE_THREADED_VMS
    ok=ok && ___VECTORELEM(marker,1)==___FIX(___PROCESSOR_ID(ps,___VMSTATE_FROM_PSTATE(ps)));
#endif
    ___EXT(___kill_sfun_stack_marker)(marker);
  }
  if(op==1 || op==5 || op==6) {
    if(test_marker_collections!=1 || ((op!=6) && before==___arg1)) _Exit(75);
  } else if(test_marker_collections!=0) _Exit(75);
}
if(held) { ___return_rc_root(held);___EXT(___release_rc)(held); }
___RC_LOCK(d);ok=ok && d->nodes==nodes && d->borrows==borrows;___RC_UNLOCK(d);
___result=ok && test_marker_custody;
#endif
c-end
))
(define (marker-input-permanent x) x)
(define (replay-marker-input commands fault)
  (let loop ((xs commands) (at 0))
    (if (null? xs)
        (begin (write (list 'root-task-result 'pass at)) (newline) (exit))
        (let* ((row (car xs)) (op (vector-ref row 0))
               (payload (if (= op 6) marker-input-permanent
                            (let ((value (vector at (vector-ref row 1) (vector-ref row 2))))
                              (lambda () value)))))
          (if (not (marker-input-act payload op (= fault 1)))
              (begin (write (list 'root-task-result 'mismatch at op 0))
                     (newline) (force-output) (rc-write-exit 71)))
          (loop (cdr xs) (+ at 1))))))
(define (marker-input-suite)
  (set! family 'marker-input) (set! trials 0)
  (let ((seed 1951) (actions 7))
    (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
    (define (noise n)
      (if (= n 0) '() (cons (vector (next 7) (- (next 4) 1) (next 2)) (noise (- n 1)))))
    (let ((result (trial '(#(0 0 0) #(1 0 0) #(2 0 0) #(3 0 0) #(4 0 0) #(5 0 0) #(6 0 0)) 0)))
      (if (signature result) (error "marker input mandatory requests failed" result))
      (write (list 'MARKER-INPUT-GC-REFUSAL-PASS result)) (newline))
    (do ((i 0 (+ i 1))) ((= i 12))
      (let* ((commands (noise 24)) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (error "marker input property failed" result (shrink commands 0 (signature result))))))
    (write (list 'MARKER-INPUT-PBT-PASS 'seed 1951 'cases 12 'actions actions)) (newline)
    (let* ((commands (append (make-list 6 '#(0 0 0)) (list '#(1 0 0)) (make-list 6 '#(0 0 0))))
           (failure (trial commands 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(1 0))) (error "actual predecessor marker control missed" failure))
      (let* ((minimal (shrink commands 1 wanted)) (again (trial minimal 1))
             (one? (one-minimal? minimal 1 wanted)) (positive (trial minimal 0)))
        (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted) (not (signature positive))))
            (error "marker input shrink/replay failed" minimal again positive))
        (for-each
         (lambda (pair) (with-output-to-file (trace-file (car pair))
                          (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
         '(("legacy-minimal" . 1) ("current-minimal" . 0)))
        (write (list 'MARKER-INPUT-IMPLEMENTATION-SHRINK-PASS 'from 13 'to 1
                     'deletion-one-minimal one? 'replayed #t 'production-pass #t)) (newline)))
    (delete-file input-file)))

)
 (else (begin)))

;;; Tcl construction uses this same replay/shrink driver, with an optional
;;; real Tcl provider. The ordinary root target has no Tcl link dependency.
(c-declare #<<c-end
#ifdef ___TEST_TCL_COMMAND
#include <tcl.h>
static int test_tcl_force;
static ___SCMOBJ test_tcl_last;
static Tcl_Interp *test_tcl_interp[4];
static ___SIZE_T test_tcl_base;
char *tcltk_call(void *root,char **args);
static char *test_tcl_entry(void *root,char **args);
static ___SCMOBJ test_tcl_vector(___processor_state ps,___SIZE_TS n,___SCMOBJ init)
{
  if (test_tcl_force==2) return ___FIX(___HEAP_OVERFLOW_ERR);
  if (test_tcl_force==1 && ___garbage_collect(___PSA(ps) 0))
    return ___FIX(___HEAP_OVERFLOW_ERR);
  return test_tcl_last=___EXT(___make_vector)(ps,n,init);
}
/* Interpose only the real allocator call in the production header. All RC,
 * still, Tcl registration/deletion and observations remain real operations. */
#pragma push_macro("___EXT")
#undef ___EXT
#define ___EXT(f) f
#define ___make_vector test_tcl_vector
#define tcltk_call test_tcl_entry
#include "command.h"
#undef tcltk_call
#undef ___make_vector
#pragma pop_macro("___EXT")

/* The old inline constructor's allocation/publication/result sequence.
 * PSD is supplied so the otherwise ill-formed SMP call can be calibrated.
 * The live caller cell models the original ___arg2/___CFUN_ARG reload, rather
 * than inventing a stale scalar-argument failure in this predecessor control. */
static int test_tcl_predecessor(___processor_state ps,Tcl_Interp *interp,
                              const char *name,const ___SCMOBJ *caller)
{
  void *cd;
  ___SCMOBJ vect;
  if (interp==NULL) return 0;
  cd=___EXT(___alloc_rc)(___PSA(ps) 0);
  if (!cd) return 0;
  vect=___EXT(___make_vector)(ps,1,___FAL);
  if (___FIXNUMP(vect)) { ___EXT(___release_rc)(cd); return 0; }
  ___VECTORELEM(vect,0)=*caller;
  ___EXT(___set_data_rc)(cd,vect);
  test_tcl_last=vect;
  return Tcl_CreateCommand(interp,name,scheme_call_cmd,cd,scheme_delete_cmd)!=NULL;
}
#endif
c-end
)
(define tcl-command-version
 (c-lambda () char-string #<<c-end
#ifdef ___TEST_TCL_COMMAND
static char version[80]; int major,minor,patch,type;
Tcl_GetVersion(&major,&minor,&patch,&type);
snprintf(version,sizeof(version),"%d.%d.%d/%d rc=%zu",major,minor,patch,type,sizeof(___rc_header));
___result=version;
#else
___result=NULL;
#endif
c-end
))
(define tcl-command-init
 (c-lambda () bool #<<c-end
#ifdef ___TEST_TCL_COMMAND
Tcl_FindExecutable("gambit-root-task");
test_tcl_base=___PSTATE->mem.rc_domain_->nodes;
___result=1;
#else
___result=0;
#endif
c-end
))
(define tcl-command-action
 (c-lambda (int int scheme-object bool int) int #<<c-end
#ifdef ___TEST_TCL_COMMAND
___processor_state ps=___PSTATE;
int op=___arg1,slot=___arg2,result=0;
void *check=___EXT(___alloc_rc)(___PSA(ps) 0);
const ___SCMOBJ *caller;
___SIZE_T before=ps->mem.rc_domain_->nodes;
if (!check) _Exit(74);
___EXT(___set_data_rc)(check,___arg3);
caller=___borrow_rc_root(ps,check);
if(!caller) _Exit(74);
test_tcl_force=___arg5; test_tcl_last=___FAL;
switch(op) {
case 0: case 6:
  if(!test_tcl_interp[slot]) test_tcl_interp[slot]=Tcl_CreateInterp();
  if(op==6) test_tcl_force=2;
  result=scheme_create_cmd(ps,test_tcl_interp[slot],"owned",*caller);
  break;
case 1:
  result=test_tcl_interp[slot] && Tcl_DeleteCommand(test_tcl_interp[slot],"owned")==TCL_OK;
  break;
case 2: {
  Tcl_CmdInfo info;
  if(test_tcl_interp[slot] && Tcl_GetCommandInfo(test_tcl_interp[slot],"owned",&info)) {
    ___SCMOBJ vect=___EXT(___data_rc)(info.clientData);
    result=___VECTORELEM(vect,0)==*caller && ___EXT(___still_obj_refcount)(vect)==1;
  }
  break;
}
case 3: {
  Tcl_Interp *dead=Tcl_CreateInterp();
  Tcl_Preserve(dead); Tcl_DeleteInterp(dead);
  result=___arg4?test_tcl_predecessor(ps,dead,"rejected",caller):scheme_create_cmd(ps,dead,"rejected",*caller);
  if(result || ps->mem.rc_domain_->nodes!=before ||
     (!___FIXNUMP(test_tcl_last) && test_tcl_last!=___FAL && ___EXT(___still_obj_refcount)(test_tcl_last)!=0)) result=2;
  Tcl_Release(dead);
  break;
}
case 4:
  if(test_tcl_interp[slot]) { Tcl_DeleteInterp(test_tcl_interp[slot]); test_tcl_interp[slot]=NULL; result=1; }
  break;
case 5: result=1; break;
case 7: result=scheme_create_cmd(ps,NULL,"absent",*caller); break;
}
___return_rc_root(check); ___EXT(___release_rc)(check);
___result=result;
#else
___result=-1;
#endif
c-end
))
(define tcl-command-inspect
 (c-lambda (int) bool #<<c-end
#ifdef ___TEST_TCL_COMMAND
___result=___PSTATE->mem.rc_domain_->nodes==test_tcl_base+___arg1 && ___PSTATE->mem.rc_domain_->borrows==0;
#else
___result=0;
#endif
c-end
))
(define (replay-tcl-command commands fault)
  (if (not (tcl-command-init)) (error "Tcl provider not enabled for this fixture"))
  (let ((live (make-vector 4 #f)) (opened (make-vector 4 #f))
        (procs (make-vector 4 #f)))
    (do ((i 0 (+ i 1))) ((= i 4))
      (vector-set! procs i (let ((tag (vector i))) (lambda () (vector-ref tag 0)))))
    (let loop ((xs commands) (at 0))
      (if (null? xs)
          (begin
            (do ((i 0 (+ i 1))) ((= i 4)) (tcl-command-action 4 i (vector-ref procs i) #f 0))
            (if (not (tcl-command-inspect 0)) (error "Tcl cleanup debt remains"))
            (write (list 'root-task-result 'pass at)) (newline) (exit))
          (let* ((row (car xs)) (op (vector-ref row 0))
                 (slot (+ 1 (vector-ref row 1))) (force (vector-ref row 2))
                 (wanted (case op ((0 5) 1) ((1 2) (if (vector-ref live slot) 1 0))
                                      ((3 6 7) 0) ((4) (if (vector-ref opened slot) 1 0))))
                 (actual (tcl-command-action op slot (vector-ref procs slot) (= fault 1) force)))
            (if (not (= wanted actual))
                (begin (write (list 'root-task-result 'mismatch at op 0 actual wanted))
                       (newline) (force-output) (rc-write-exit 71)))
            (case op
              ((0) (vector-set! live slot #t) (vector-set! opened slot #t))
              ((1) (vector-set! live slot #f))
              ((4) (vector-set! live slot #f) (vector-set! opened slot #f))
              ((6) (vector-set! opened slot #t)))
            (if (= op 5) (##gc))
            (let ((count (let sum ((i 0) (n 0))
                           (if (= i 4) n (sum (+ i 1) (+ n (if (vector-ref live i) 1 0)))))))
              (if (not (tcl-command-inspect count))
                  (begin (write (list 'root-task-result 'mismatch at op 1 count))
                         (newline) (force-output) (rc-write-exit 71))))
            (loop (cdr xs) (+ at 1)))))))
(define (tcl-command-suite)
  (set! family 'tcl-command) (set! trials 0)
  (write (list 'TCL-COMMAND-PROVIDER (tcl-command-version))) (newline)
  (let ((seed 1931) (actions 0))
    (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
    (define (noise n) (if (= n 0) '() (cons (vector (next 8) (- (next 4) 1) (next 2)) (noise (- n 1)))))
    (define chain '(#(0 0 1) #(2 0 0) #(0 0 1) #(2 0 0) #(3 0 0) #(2 0 0)
                    #(6 0 0) #(2 0 0) #(7 0 0) #(1 0 0) #(5 0 0) #(4 0 0)))
    (let ((result (trial chain 0)))
      (if (signature result) (error "Tcl mandatory history failed" result))
      (write (list 'TCL-COMMAND-GC-ROLLBACK-PASS result)) (newline))
    (set! actions (length chain))
    (do ((i 0 (+ i 1))) ((= i 12))
      (let* ((commands (append (noise 6) chain (noise 6))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result) (error "Tcl constructor property failed" result (shrink commands 0 (signature result))))))
    (write (list 'TCL-COMMAND-PBT-PASS 'seed 1931 'cases 12 'actions actions)) (newline)
    (let* ((commands (append (make-list 6 '#(5 0 0)) (list '#(3 0 0)) (make-list 6 '#(5 0 0))))
           (failure (trial commands 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(3 0))) (error "Tcl predecessor control missed" failure))
      (let* ((minimal (shrink commands 1 wanted)) (again (trial minimal 1))
             (one? (one-minimal? minimal 1 wanted)) (positive (trial minimal 0)))
        (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted) (not (signature positive))))
            (error "Tcl shrink/replay failed" minimal again positive))
        (for-each (lambda (pair) (with-output-to-file (trace-file (car pair))
                       (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
                  '(("legacy-minimal" . 1) ("current-minimal" . 0)))
        (write (list 'TCL-COMMAND-IMPLEMENTATION-SHRINK-PASS 'from 13 'to 1
                     'deletion-one-minimal one? 'replayed #t 'production-pass #t)) (newline)))
    (delete-file input-file)))

(cond-expand
 (symkey-callback-test
  (begin
   (c-declare #<<c-end
#define SYMKEY_COUNT_LIMIT ((___MAX_FIX < INT_MAX) ? ___MAX_FIX : INT_MAX)
static int test_callback_fault,test_callback_live;
static void *test_callback_allocate(___SIZE_T bytes)
{
  void *p;
  if (test_callback_fault==1) return 0;
  p=___ALLOC_MEM(bytes);if(p) ++test_callback_live;return p;
}
static void test_callback_free(void *p)
{ --test_callback_live;___FREE_MEM(p); }
___HIDDEN ___SCMOBJ test_old_table
   ___P((unsigned int subtype),
        (subtype)
unsigned int subtype;)
{
  switch (subtype)
    {
    case ___sKEYWORD:
      return ___GSTATE->keyword_table;
    default: /* assume ___sSYMBOL */
      return ___GSTATE->symbol_table;
    }
}


___HIDDEN ___BOOL test_old_table_permanent(___SCMOBJ tbl)
{
  return ___MEM_ALLOCATED(tbl) && ___HD_TYP(___HEADER(tbl))==___PERM &&
         ___HD_SUBTYPE(___HEADER(tbl))==___sVECTOR &&
         ___INT(___VECTORLENGTH(tbl))>1;
}

static void test_old_for_each_symkey
   ___P((unsigned int subtype,
         void (*visit) (___SCMOBJ symkey, void *data),
         void *data),
        (subtype,
         visit,
         data)
unsigned int subtype;
void (*visit) ();
void *data;)
{
  ___SCMOBJ tbl;
  int i;
  /* Internal caller census: os_tty visit_symbol reads permanent names only.
   * This private callback must not reenter registry/GC/Scheme. */
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  tbl=test_old_table(subtype);
  if (!test_old_table_permanent(tbl))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return; }

  for (i=___INT(___VECTORLENGTH(tbl))-1; i>0; i--)
    {
      ___SCMOBJ probe = ___VECTORELEM(tbl, i);

      while (probe != ___NUL)
        {
          visit (probe, data);
          probe = ___SYMKEY_NEXT_FIELD(probe);
        }
    }
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
}

#pragma push_macro("___ALLOC_MEM")
#pragma push_macro("___FREE_MEM")
#undef ___ALLOC_MEM
#undef ___FREE_MEM
#define ___ALLOC_MEM(bytes) test_callback_allocate(bytes)
#define ___FREE_MEM(ptr) test_callback_free(ptr)
___HIDDEN ___SCMOBJ test_adapter_table
   ___P((unsigned int subtype),
        (subtype)
unsigned int subtype;)
{
  switch (subtype)
    {
    case ___sKEYWORD:
      return ___GSTATE->keyword_table;
    default: /* assume ___sSYMBOL */
      return ___GSTATE->symbol_table;
    }
}


___HIDDEN ___BOOL test_adapter_table_permanent(___SCMOBJ tbl)
{
  return ___MEM_ALLOCATED(tbl) && ___HD_TYP(___HEADER(tbl))==___PERM &&
         ___HD_SUBTYPE(___HEADER(tbl))==___sVECTOR &&
         ___INT(___VECTORLENGTH(tbl))>1;
}

/* One checked identity-copy contract serves Scheme views and native callbacks.
 * Caller holds global_gate. No allocation, callback or Scheme/GC occurs here.
 * A size mismatch writes no destination cells; copied identities are permanent. */
___HIDDEN ___SCMOBJ test_adapter_copy_real(___SCMOBJ *items,
                                    ___SIZE_TS length,unsigned int subtype)
{
  ___SCMOBJ table=test_adapter_table(subtype),result,probe;
  int count,used=0,i;
  if (!test_adapter_table_permanent(table) ||
      !___FIXNUMP(___VECTORELEM(table,0)) ||
      ___INT(___VECTORELEM(table,0))<0 ||
      ___VECTORELEM(table,0)>___FIX(SYMKEY_COUNT_LIMIT))
    return ___FIX(___HEAP_OVERFLOW_ERR);
  result=___VECTORELEM(table,0);
  count=___INT(result);
  if (items==0 || length!=count) return result;
  for (i=___INT(___VECTORLENGTH(table))-1;i>0;i--)
    for (probe=___VECTORELEM(table,i);probe!=___NUL;
         probe=___SYMKEY_NEXT_FIELD(probe))
      {
        if (used>=count || !___MEM_ALLOCATED(probe) ||
            ___HD_TYP(___HEADER(probe))!=___PERM ||
            ___INT(___SUBTYPE(probe))!=subtype)
          return ___FIX(___HEAP_OVERFLOW_ERR);
        items[used++]=probe;
      }
  return used==count ? result : ___FIX(___HEAP_OVERFLOW_ERR);
}

static ___SCMOBJ test_adapter_copy(___SCMOBJ *items,___SIZE_TS n,unsigned int kind) {
 if(test_callback_fault==2 && items!=0) return ___FIX(___HEAP_OVERFLOW_ERR);
 return test_adapter_copy_real(items,n,kind);
}
/* The Scheme caller allocates/roots its vector outside the registry gate. */
___SCMOBJ test_adapter_view(___SCMOBJ view,unsigned int subtype)
{
  ___SCMOBJ result;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  if (view==___FAL)
    result=test_adapter_copy(0,0,subtype);
  else if (!___MEM_ALLOCATED(view) ||
           ___HD_SUBTYPE(___HEADER(view))!=___sVECTOR)
    result=___FIX(___HEAP_OVERFLOW_ERR);
  else
    result=test_adapter_copy(___BODY_AS(view,___tVECTOR),
                            ___INT(___VECTORLENGTH(view)),subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  return result;
}

/* Native callbacks borrow a private identity array, never buckets or NEXT.
 * A live global-state owner and normally returning callbacks are required.
 * The native allocator cannot enter Scheme/GC. Keeping query/allocation/copy
 * in one gate avoids treating ordinary concurrent growth as caller failure.
 * No registry lock or movable address survives the callback boundary.
 * Permanent identities need no extra RC roots and do not extend VM lifetime. */
___BOOL test_adapter_for_each
   ___P((unsigned int subtype,
         void (*visit) (___SCMOBJ symkey, void *data),
         void *data),
        (subtype,visit,data)
unsigned int subtype;
void (*visit) ();
void *data;)
{
  ___SCMOBJ count,result,*items=0;
  ___SIZE_T length,i;
  if (visit==0) return 0;
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  count=test_adapter_copy(0,0,subtype);
  if (count<___FIX(0))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  length=___INT(count);
  if (length==0)
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 1; }
  if (length>~___CAST(___SIZE_T,0)/sizeof(*items))
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  items=___CAST(___SCMOBJ*,___ALLOC_MEM(length*sizeof(*items)));
  if (items==0)
    { ___MUTEX_UNLOCK(___GSTATE->mem.global_gate); return 0; }
  result=test_adapter_copy(items,length,subtype);
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  if (result!=count)
    { ___FREE_MEM(items); return 0; }
  for (i=0;i<length;i++) visit(items[i],data);
  ___FREE_MEM(items);
  return 1;
}
#pragma pop_macro("___FREE_MEM")
#pragma pop_macro("___ALLOC_MEM")

typedef struct test_callback_data {
  unsigned int subtype;int op,slot,seen,once,held,bad,nested;
  long visited;
} test_callback_data;
static ___SCMOBJ test_callback_ids[2][4];
static const ___SCMOBJ *test_callback_input_root;
static int test_callback_gc_count,test_callback_moved_count;
static ___SCMOBJ test_callback_create(int kind,int slot)
{
  char name[80];___SCMOBJ value;
  snprintf(name,sizeof(name),"___symkey_callback_slot_%d",slot);
  value=___make_symkey_from_UTF_8_string(name,kind?___sKEYWORD:___sSYMBOL);
  if (!___FIXNUMP(value)) test_callback_ids[kind][slot]=value;
  return value;
}
static void test_callback_visit(___SCMOBJ sym,void *data)
{
  test_callback_data *d=___CAST(test_callback_data*,data);int k,i,available;
#ifdef ___USE_POSIX_THREAD_SYSTEM
  available=pthread_mutex_trylock(&___GSTATE->mem.global_gate)==0;
  if(available) pthread_mutex_unlock(&___GSTATE->mem.global_gate);
#else
  available=0;
#endif
  ++d->visited;
  if(!available) {d->held=1;return;} /* Observe the real old lock; never deadlock. */
  k=d->subtype==___sKEYWORD;
  for(i=0;i<4;i++) if(sym==test_callback_ids[k][i]) d->seen|=1<<i;
  if(d->once++) return;
  if(d->op==2 && ___FIXNUMP(test_callback_create(k,d->slot))) d->bad=1;
  if(d->op==3) {
    test_callback_data child={0};child.subtype=d->subtype;
    if(!___for_each_symkey(d->subtype,test_callback_visit,&child)||child.held||child.bad)
      d->bad=1;
    d->nested=child.seen;
  }
  if(d->op==4) {
    ___SCMOBJ before=*test_callback_input_root;
    if(___garbage_collect(___PSA(___PSTATE) 0)) d->bad=1;
    ++test_callback_gc_count;
    if(*test_callback_input_root==before) d->bad=1;
    else ++test_callback_moved_count;
  }
}

c-end
)
(define replay-symkey-callback-native
 (c-lambda (scheme-object int) void #<<c-end
#ifdef ___USE_POSIX_THREAD_SYSTEM
___processor_state ps=___PSTATE;
void *held=___EXT(___alloc_rc)(___PSA(ps) 0);
const ___SCMOBJ *root;
int i,k,steps;
if(!held||!___try_set_data_rc(ps,held,___arg1)||(root=___borrow_rc_root(ps,held))==0) _Exit(74);
test_callback_input_root=root;
for(k=0;k<2;k++) {
  ___SCMOBJ anchor=___make_symkey_from_UTF_8_string("___symkey_callback_anchor",k?___sKEYWORD:___sSYMBOL);
  if(___FIXNUMP(anchor)) _Exit(74);
  for(i=0;i<4;i++) test_callback_ids[k][i]=___FAL;
}
steps=___INT(___VECTORLENGTH(___VECTORELEM(*root,0)));
for(i=0;i<steps;i++) {
  ___SCMOBJ row=___VECTORELEM(___VECTORELEM(*root,0),i);
  int op=___INT(___VECTORELEM(row,0)),slot=___INT(___VECTORELEM(row,1))+1;
  int kind=___INT(___VECTORELEM(row,2)),actual,wanted,ok;
  test_callback_data data={0};data.subtype=kind?___sKEYWORD:___sSYMBOL;data.op=op;data.slot=slot;
  if(op==1) actual=!___FIXNUMP(test_callback_create(kind,slot));
  else if(op>=5) {
    test_callback_fault=op==5?1:op==6?2:0;
    /* Interpose validation refusal without mutating a registry count. */
    actual=op==7?___for_each_symkey(data.subtype,0,&data):
      test_adapter_for_each(op==6?___sSYMBOL:data.subtype,test_callback_visit,&data);
    test_callback_fault=0;
    if(test_callback_live||data.visited) actual=99;
  } else {
    if(___arg2) {test_old_for_each_symkey(data.subtype,test_callback_visit,&data);ok=1;}
    else ok=___for_each_symkey(data.subtype,test_callback_visit,&data);
    actual=data.seen;
    if(!ok||data.held||data.bad||(op==3&&data.nested!=data.seen)) actual=99;
  }
  wanted=___INT(___VECTORELEM(___VECTORELEM(*root,1),i));
  if(actual!=wanted) {
    printf("(root-task-result mismatch %d %d 0 %d %d)\n",i,op,actual,wanted);fflush(stdout);_Exit(71);
  }
}
___return_rc_root(held);___EXT(___release_rc)(held);
printf("(root-task-result pass %d (gc-moved %d %d) (word-bytes %zu))\n",steps,test_callback_gc_count,test_callback_moved_count,sizeof(___SCMOBJ));fflush(stdout);_Exit(0);
#else
_Exit(72);
#endif
c-end
))
(define (replay-symkey-callback commands fault)
 (let ((masks (vector 0 0)))
  (define (add mask slot) (bitwise-ior mask (arithmetic-shift 1 slot)))
  (let ((expected
    (map (lambda (row)
      (let* ((op (vector-ref row 0)) (slot (+ 1 (vector-ref row 1)))
             (kind (vector-ref row 2)) (before (vector-ref masks kind)))
       (case op
        ((1) (vector-set! masks kind (add before slot)) 1)
        ((2) (vector-set! masks kind (add before slot)) before)
        ((5 6 7) 0)
        (else before)))) commands)))
   (replay-symkey-callback-native (vector (list->vector commands) (list->vector expected)) fault))))
(define (symkey-callback-suite)
 (set! family 'symkey-callback) (set! trials 0)
 (let ((seed 1973) (actions 0))
  (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
  (define (noise n) (if (= n 0) '() (cons (vector (next 8) (- (next 4) 1) (next 2)) (noise (- n 1)))))
  (define chain '(#(0 0 0) #(1 0 0) #(0 0 0) #(2 1 0) #(0 1 0) #(3 0 0) #(4 0 0)
                  #(1 -1 1) #(3 0 1) #(4 0 1) #(5 0 0) #(6 0 0) #(7 0 1)))
  (let ((result (trial chain 0)))
   (if (signature result) (error "callback mandatory history failed" result))
   (write (list 'SYMKEY-CALLBACK-REENTRY-GC-REFUSAL-PASS result)) (newline))
  (set! actions (length chain))
  (do ((i 0 (+ i 1))) ((= i 12))
   (let* ((commands (append (noise 6) chain (noise 6))) (result (trial commands 0)))
    (set! actions (+ actions (length commands)))
    (if (signature result) (error "callback property failed" result (shrink commands 0 (signature result))))))
  (write (list 'SYMKEY-CALLBACK-PBT-PASS 'seed 1973 'cases 12 'actions actions)) (newline)
  (let* ((commands (append (make-list 6 '#(1 0 0)) '(#(0 0 0)) (make-list 6 '#(1 1 0))))
         (failure (trial commands 1)) (wanted (signature failure)))
   (if (not (equal? wanted '(0 0))) (error "real predecessor lock control missed" failure))
   (let* ((minimal (shrink commands 1 wanted)) (again (trial minimal 1))
          (one? (one-minimal? minimal 1 wanted)) (positive (trial minimal 0)))
    (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted) (not (signature positive))))
     (error "callback shrink/replay failed" minimal again positive))
    (for-each (lambda (pair) (with-output-to-file (trace-file (car pair))
      (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
      '(("legacy-minimal" . 1) ("current-minimal" . 0)))
    (let ((old-file (trial-file (trace-file "legacy-minimal")))
          (new-file (trial-file (trace-file "current-minimal"))))
     (if (not (and (equal? (signature old-file) wanted) (not (signature new-file))))
      (error "serialized callback replay mismatch" old-file new-file))
     (display "SYMKEY-CALLBACK-SERIALIZED-REPLAY-PASS\n"))
    (write (list 'SYMKEY-CALLBACK-IMPLEMENTATION-SHRINK-PASS 'from 13 'to 1 'deletion-one-minimal one? 'production-pass #t)) (newline)))
  (delete-file input-file)))
))
 (else (begin)))


;;; Same replay driver, actual Tcl dispatcher/header and production Scheme entry.
(cond-expand
 (tcl-command-test
  (begin
(c-declare #<<c-end

#ifdef ___TEST_TCL_COMMAND
static Tcl_Interp *test_callback_interp;
static void *test_callback_roots[4];
static int test_callback_mode,test_callback_depth,test_callback_bad;
static int test_callback_gc,test_callback_moves,test_callback_calls;
static void *test_callback_probe_root;
static char *test_tcl_old_entry(___SCMOBJ value,char **args)
{
  /* Probe only. Do not collect/delete through the unsafe old ABI. */
  (void)args;
  if(___EXT(___refcount_rc)(test_callback_probe_root)!=2 ||
     value!=___EXT(___data_rc)(test_callback_probe_root)) test_callback_bad=1;
  return NULL;
}
___HIDDEN int test_tcl_old_call
   ___P((ClientData client_data,
         Tcl_Interp *interp,
         int argc,
         const char **argv),
        (client_data,
         interp,
         argc,
         argv)
ClientData client_data;
Tcl_Interp *interp;
int argc;
const char **argv;)
{
  char *result = test_tcl_old_entry (___EXT(___data_rc) (___CAST(void*,client_data)),
                             ___CAST(char**,argv+1));

  /*
   * Propagate result to Tcl.
   */

  if (result == NULL)
    {
      Tcl_SetResult (interp,
                     "",
                     TCL_STATIC);
    }
  else
    {
      /*
       * The resulting C string was dynamically allocated by
       * Gambit's C interface.  We have to ensure it is
       * deallocated by a call to ___release_string by Tcl
       * when it no longer needs the string.
       */

      Tcl_SetResult (interp,
                     result,
                     ___CAST(Tcl_FreeProc*,___EXT(___release_string)));
    }

  return TCL_OK;
}

static char *test_tcl_entry(void *root,char **args)
{
  ___processor_state ps=___PSTATE;
  ___SCMOBJ before,after;
  char *result;
  int level=test_callback_depth++;
  if(level>=4 || ___EXT(___refcount_rc)(root)!=level+2) _Exit(76);
  test_callback_roots[level]=root;
  before=___VECTORELEM(___EXT(___data_rc)(root),0);
  if(test_callback_mode==1 || test_callback_mode==3) {
    if(___garbage_collect(___PSA(ps) 0)) _Exit(74);
    ++test_callback_gc;
    after=___VECTORELEM(___EXT(___data_rc)(root),0);
    if(before!=after) ++test_callback_moves;else _Exit(75);
  }
  ++test_callback_calls;
  result=tcltk_call(root,args); /* actual generated SFUN conversion and Scheme body */
  test_callback_roots[level]=NULL;
  --test_callback_depth;
  return result;
}
#endif
c-end
)
; The RC identity stays pinned by scheme_call_cmd through every allocating
; argument conversion and nested callback. Read its GC-updated payload only
; after entering Scheme; no unrooted Scheme value crosses that C boundary.
(define ##tcltk-command-payload
  (c-lambda ((pointer void)) scheme-object
    "___result=___EXT(___data_rc)(___arg1);"))

(c-define (##tcltk-call root args)
          ((pointer void) nonnull-char-string-list) char-string "tcltk_call" ""
  (let* ((vect (##tcltk-command-payload root))
         (proc (##vector-ref vect 0)))
    (let ((result (##apply proc args)))
      (if (##string? result)
          result
          #f))))

(define tcl-callback-step
 (c-lambda () bool #<<c-end
___processor_state ps=___PSTATE;
void *root=test_callback_roots[test_callback_depth-1];
int ok=root!=NULL;
if(ok && test_callback_depth==1 && (test_callback_mode==2 || test_callback_mode==3)) {
  ok=Tcl_Eval(test_callback_interp,"owned inner")==TCL_OK;
}
if(ok && ((test_callback_mode==4 && test_callback_depth==1) ||
          (test_callback_mode==3 && test_callback_depth==2))) {
  ok=Tcl_DeleteCommand(test_callback_interp,"owned")==TCL_OK;
  if(ok && ___EXT(___refcount_rc)(root)!=test_callback_depth) ok=0;
}
if(ok) {
  ___SCMOBJ before=___VECTORELEM(___EXT(___data_rc)(root),0);
  if(___garbage_collect(___PSA(ps) 0)) _Exit(74);
  ++test_callback_gc;
  if(before!=___VECTORELEM(___EXT(___data_rc)(root),0)) ++test_callback_moves;
  else _Exit(75);
}
___result=ok;
c-end
))
(define tcl-callback-action
 (c-lambda (scheme-object int bool) bool #<<c-end
___processor_state ps=___PSTATE;
___rc_domain *d=ps->mem.rc_domain_;
___SIZE_T nodes=d->nodes;
int ok,mode=___arg2;
void *root;
Tcl_CmdInfo info;
test_callback_mode=mode;test_callback_depth=0;test_callback_bad=0;
test_callback_gc=0;test_callback_moves=0;test_callback_calls=0;
test_callback_interp=Tcl_CreateInterp();
if(!test_callback_interp || !scheme_create_cmd(ps,test_callback_interp,"owned",___arg1)) _Exit(74);
if(!Tcl_GetCommandInfo(test_callback_interp,"owned",&info)) _Exit(74);
root=info.clientData;test_callback_probe_root=root;
if(___arg3) {
  info.proc=test_tcl_old_call;
  if(!Tcl_SetCommandInfo(test_callback_interp,"owned",&info)) _Exit(74);
  /* Calibrate the same legacy probe: externally supplying the missing owner
   * must pass before removing it exposes the real count mismatch. */
  ___EXT(___addref_rc)(root);
  if(Tcl_Eval(test_callback_interp,"owned calibration")!=TCL_OK || test_callback_bad) _Exit(76);
  ___EXT(___release_rc)(root);
  test_callback_bad=0;
}
ok=Tcl_Eval(test_callback_interp,"owned outer")==TCL_OK;
if(!___arg3) {
  ok=ok && strcmp(Tcl_GetStringResult(test_callback_interp),mode==5?"":"owned-result")==0;
  ok=ok && test_callback_calls==((mode==2 || mode==3)?2:1);
  ok=ok && test_callback_gc==test_callback_moves && test_callback_gc>0;
  ok=ok && d->nodes==nodes+((mode==3 || mode==4)?0:1);
  if(mode!=3 && mode!=4) ok=ok && ___EXT(___refcount_rc)(root)==1;
}
Tcl_DeleteInterp(test_callback_interp);test_callback_interp=NULL;
ok=ok && d->nodes==nodes && d->borrows==0 && test_callback_depth==0;
___result=ok && !test_callback_bad;
c-end
))
(define (replay-tcl-callback commands fault)
 (if (not (tcl-command-init)) (error "Tcl provider unavailable"))
 (let loop ((xs commands) (at 0))
  (if (null? xs)
   (begin (write (list 'root-task-result 'pass at)) (newline) (exit))
   (let* ((row (car xs)) (mode (vector-ref row 0))
          (tag (vector at (vector-ref row 1) (vector-ref row 2)))
          (proc (lambda args
                 (if (not (tcl-callback-step)) (error "callback ownership failed"))
                 (if (= (vector-ref tag 0) -1) (error "captured tag corrupted"))
                 (if (= mode 5) #f "owned-result"))))
    (if (not (tcl-callback-action proc mode (= fault 1)))
     (begin (write (list 'root-task-result 'mismatch at mode 0))
            (newline) (force-output) (rc-write-exit 71)))
    (loop (cdr xs) (+ at 1))))))
(define (tcl-callback-suite)
 (set! family 'tcl-callback) (set! trials 0)
 (let ((seed 1993) (actions 6))
  (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
  (define (noise n) (if (= n 0) '() (cons (vector (next 6) (- (next 4) 1) (next 2)) (noise (- n 1)))))
  (let ((result (trial '(#(0 0 0) #(1 0 0) #(2 0 0) #(3 0 0) #(4 0 0) #(5 0 0)) 0)))
   (if (signature result) (error "callback mandatory cases failed" result))
   (write (list 'TCL-CALLBACK-NESTED-DELETE-GC-PASS result)) (newline))
  (do ((i 0 (+ i 1))) ((= i 12))
   (let* ((commands (noise 24)) (result (trial commands 0)))
    (set! actions (+ actions (length commands)))
    (if (signature result) (error "callback property failed" result (shrink commands 0 (signature result))))))
  (write (list 'TCL-CALLBACK-PBT-PASS 'seed 1993 'cases 12 'actions actions)) (newline)
  (let* ((commands (make-list 13 '#(0 0 0))) (failure (trial commands 1)) (wanted (signature failure)))
   (if (not (equal? wanted '(0 0))) (error "old callback control missed" failure))
   (let* ((minimal (shrink commands 1 wanted)) (one? (one-minimal? minimal 1 wanted))
          (again (trial minimal 1)) (positive (trial minimal 0)))
    (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted) (not (signature positive))))
     (error "callback shrink/replay failed" minimal again positive))
    (for-each (lambda (pair) (with-output-to-file (trace-file (car pair))
     (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
     '(("legacy-minimal" . 1) ("current-minimal" . 0)))
    (if (not (and (equal? (signature (trial-file (trace-file "legacy-minimal"))) wanted)
                  (not (signature (trial-file (trace-file "current-minimal"))))))
     (error "callback serialized replay failed"))
    (display "TCL-CALLBACK-SERIALIZED-REPLAY-PASS\n")
    (write (list 'TCL-CALLBACK-IMPLEMENTATION-SHRINK-PASS 'from 13 'to 1 'deletion-one-minimal one?)) (newline)))
  (delete-file input-file)))
 ))
 (else (begin)))

(define family 'rc)
(define (trace-tag)
  (case family ((tcl-callback) 'tcl-callback-trace) ((symkey-callback) 'symkey-callback-trace) ((marker-input) 'marker-input-trace) ((tcl-command) 'tcl-command-trace) ((rc-write) 'rc-write-trace) ((view) 'symkey-view-trace) ((intern) 'symkey-publication-trace) ((snapshot) 'globals-snapshot-trace) ((vm) 'vm-root-task-trace) ((bank) 'bank-root-task-trace) ((stack) 'stack-root-task-trace) ((symkey) 'symkey-root-task-trace) ((globals) 'globals-root-task-trace)
    ((continuation) 'continuation-history)
    (else 'root-task-trace)))
(define (trace-file suffix)
  (string-append (case family ((tcl-callback) "tcl-callback-") ((symkey-callback) "symkey-callback-") ((marker-input) "marker-input-") ((tcl-command) "tcl-command-") ((rc-write) "rc-write-") ((view) "symkey-view-") ((intern) "symkey-publication-") ((snapshot) "globals-snapshot-") ((vm) "vm-root-task-")
                  ((bank) "bank-root-task-") ((stack) "stack-root-task-") ((symkey) "symkey-root-task-") ((globals) "globals-root-task-")
                  ((continuation) "continuation-history-") (else "root-task-")) suffix ".trace"))
(define (oracle commands)
  (let ((state (if (eq? family 'rc) 5 0)) (phase 0) (lease 0) (epoch 0))
    (list->vector
     (map
      (lambda (row)
        (let* ((op (vector-ref row 0)) (key (vector-ref row 1))
               (owner (= (vector-ref row 2) 0))
               (current (and owner (= key epoch))) (accepted #f))
          (case op
            ((0)
             (cond ((and owner (= phase 0) (= key epoch))
                    (set! epoch (+ epoch 1)) (set! phase 1)
                    (set! lease 1) (set! state 1) (set! accepted #t))
                   ((and owner (= phase 1) (= key (- epoch 1)))
                    (set! accepted #t))))
            ((1) (if (and current (= phase 1) (= state 1))
                     (begin (set! state 2) (set! accepted #t))))
            ((2) (if (and current (= phase 1) (= state 2))
                     (begin (set! state 4) (set! accepted #t))))
            ((3) (if (and current (= phase 1) (or (= state 4) (= state 5)))
                     (begin (set! state 5) (set! lease 0) (set! accepted #t))))
            ((4) (set! accepted (and (eq? family 'rc) (= phase 0))))
            ((5) (set! accepted (and current (= state 5) (= lease 0)))))
          (vector (if accepted 1 0) state phase lease epoch)))
      commands))))

(define (trace? x)
  (and (list? x) (= (length x) 4) (memq (car x) '(tcl-callback-trace symkey-callback-trace marker-input-trace tcl-command-trace rc-write-trace root-task-trace vm-root-task-trace bank-root-task-trace stack-root-task-trace symkey-root-task-trace globals-root-task-trace globals-snapshot-trace symkey-publication-trace symkey-view-trace continuation-history))
       (integer? (cadr x)) (<= 1 (cadr x) 3) (list? (caddr x))
       (<= (length (caddr x)) 96)
       (if (eq? (car x) 'symkey-view-trace)
           (memv (cadddr x) '(0 1 2))
           (memv (cadddr x) '(0 1)))
       (let loop ((xs (caddr x)))
         (or (null? xs)
             (let ((r (car xs)))
               (and (vector? r) (= (vector-length r) 3)
                    (integer? (vector-ref r 0)) (<= 0 (vector-ref r 0) (case (car x) ((tcl-callback-trace) 5) ((symkey-callback-trace) 7) ((symkey-view-trace) 9) ((rc-write-trace) 8) ((marker-input-trace) 6) ((tcl-command-trace) 7) ((globals-snapshot-trace symkey-publication-trace) 8) ((globals-root-task-trace) 6) (else 5)))
                    (memv (vector-ref r 1) '(-1 0 1 2))
                    (memv (vector-ref r 2) '(0 1)) (loop (cdr xs))))))))
(define (replay trace)
  (if (not (trace? trace)) (error "invalid structured root-task trace"))
  (set! family (case (car trace) ((tcl-callback-trace) 'tcl-callback) ((symkey-callback-trace) 'symkey-callback) ((marker-input-trace) 'marker-input) ((tcl-command-trace) 'tcl-command) ((rc-write-trace) 'rc-write) ((symkey-view-trace) 'view) ((symkey-publication-trace) 'intern) ((globals-snapshot-trace) 'snapshot) ((vm-root-task-trace) 'vm)
                 ((bank-root-task-trace) 'bank) ((stack-root-task-trace) 'stack) ((symkey-root-task-trace) 'symkey) ((globals-root-task-trace) 'globals)
                 ((continuation-history) 'continuation) (else 'rc)))
  (if (not (prepare-source)) (error "root-task source allocation failed"))
  (do ((i 0 (+ i 1))) ((= i (cadr trace))) (##gc))
  (let ((commands (caddr trace)))
    (cond ((eq? family 'symkey-callback)
           (cond-expand (symkey-callback-test (replay-symkey-callback commands (cadddr trace)))
                        (else (error "symkey callback test feature not selected"))))
          ((eq? family 'marker-input)
           (cond-expand (marker-input-test (replay-marker-input commands (cadddr trace)))
                        (else (error "marker-input test feature not selected"))))
          ((eq? family 'tcl-callback)
           (cond-expand (tcl-command-test (replay-tcl-callback commands (cadddr trace)))
                        (else (error "Tcl callback feature not selected"))))
          ((eq? family 'tcl-command) (replay-tcl-command commands (cadddr trace)))
          ((eq? family 'rc-write) (replay-rc-write commands (cadddr trace)))
          ((eq? family 'view) (replay-view commands (cadddr trace)))
          ((eq? family 'continuation) (replay-continuation commands (cadddr trace)))
          (else (replay-native (list->vector commands) (case family ((snapshot) (snapshot-oracle commands)) ((intern) (intern-oracle commands)) (else (oracle commands))) (cadddr trace)
                       (case family ((intern) 7) ((snapshot) 6) ((vm) 1) ((bank) 2) ((stack) 3) ((symkey) 4) ((globals) 5) (else 0)))))))

(define self (car (command-line)))
(define input-file "root-task-input.dat")
(define trials 0)
(define (trial commands fault)
  (set! trials (+ trials 1))
  (with-output-to-file input-file
    (lambda () (write (list (trace-tag) 1 commands fault)) (newline)))
  (trial-file input-file))
(define (trial-file path)
  (let* ((port (open-input-process
                (list path: self arguments: (list "-:p1" "--replay" path)
                      stderr-redirection: #t)))
         (result (with-exception-catcher (lambda (e) '(root-task-result runtime-error))
                   (lambda () (read port))))
         (status (process-status port)))
    (close-input-port port)
    (cond ((and (list? result) (>= (length result) 3)
                (eq? (car result) 'root-task-result))
           (cond ((and (eq? (cadr result) 'pass) (= status 0)) result)
                 ((and (eq? (cadr result) 'mismatch) (= status (arithmetic-shift 71 8))) result)
                 (else (error "native replay failed outside property oracle" status result))))
          (else (error "malformed native replay outcome" status result)))))
(define (signature result)
  (and (eq? (cadr result) 'mismatch) (list (list-ref result 3) (list-ref result 4))))
(define (take xs n) (if (= n 0) '() (cons (car xs) (take (cdr xs) (- n 1)))))
(define (drop xs n) (if (= n 0) xs (drop (cdr xs) (- n 1))))
(define (remove-range xs from n) (append (take xs from) (drop xs (+ from n))))
(define (shrink commands fault wanted)
  ;; Chunk deletion followed by a deletion-1-minimality check. Expected results
  ;; are recomputed after each deletion, preserving meaningful preconditions.
  (let size-loop ((xs commands) (size (max 1 (quotient (length commands) 2))))
    (let try ((at 0))
      (cond ((> (+ at size) (length xs))
             (if (= size 1) xs (size-loop xs (max 1 (quotient size 2)))))
            (else
             (let ((candidate (remove-range xs at size)))
               (if (equal? (signature (trial candidate fault)) wanted)
                   (size-loop candidate (min size (max 1 (length candidate))))
                   (try (+ at 1)))))))))
(define (one-minimal? commands fault wanted)
  (let loop ((i 0))
    (or (= i (length commands))
        (and (not (equal? (signature (trial (remove-range commands i 1) fault)) wanted))
             (loop (+ i 1))))))

(define (suite)
  (set! trials 0)
  (let ((state 173) (actions 0))
    (define (next n)
      (set! state (modulo (+ (* state 48271) 17) 2147483647)) (modulo state n))
    (define (noise n)
      (if (= n 0) '()
          (cons (vector (next (if (eq? family 'globals) 7 6)) (list-ref '(-1 0 1 2) (next 4)) (next 2))
                (noise (- n 1)))))
    (define chain (append (list (vector 0 0 0))
                          (if (eq? family 'globals)
                              (map (lambda (field) (vector 6 field 0)) '(-1 0 1 2)) '())
                          (list (vector 1 1 0) (vector 2 1 0) (vector 3 1 0))))
    (do ((sample 0 (+ sample 1))) ((= sample 24))
      (let* ((commands (append (noise 16) chain (noise 16)))
             (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "real root-task implementation property failed" result minimal)))))
    (write (list 'ROOT-TASK-PBT-PASS 'family family 'seed 173 'cases 24 'actions actions)) (newline)
    ;; A known stale-finish invocation mutation must be detected and reduced
    ;; against the same real C implementation, never a copied simulator.
    (let* ((noisy (append (make-list 12 (vector 5 0 0)) chain
                          (make-list 8 (vector 4 0 0))))
           (failure (trial noisy 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(3 0))) (error "stale-finish negative control missed" failure))
      (let* ((minimal (shrink noisy 1 wanted))
             (replayed (trial minimal 1))
             (minimal? (one-minimal? minimal 1 wanted)))
        (if (not (and (= (length minimal) 4) minimal?
                      (equal? (signature replayed) wanted)
                      (equal? (list-ref replayed 7) '(0 4 1 1 1))))
            (error "native shrink/replay certificate failed" minimal replayed))
        (with-output-to-file (trace-file "minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (write (list 'ROOT-TASK-SHRINK-PASS 'family family 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'trials trials))
        (newline)))
    (delete-file input-file)
    (display "ROOT-TASK-REPLAY-PASS\n") (force-output)))

;;; A semantic history uses the same typed trace, fresh-process replay and
;;; deletion shrinker. Its oracle observes dynamic-wind entry/exit and result
;;; graph identity, never a copy of the runtime's frame or GC algorithm.
(define (replay-continuation commands fault)
  (let ((saved #f) (deliver #f) (generation 0) (seed 0)
        (before 0) (after 0) (last -3) (resumes 0) (gc-since-resume #f)
        (eg 0) (eb 0) (ea 0) (el -3) (er 0) (have #f))
    (define (capture value)
      (set! generation (+ generation 1)) (set! seed value)
      (set! last -3) (set! resumes 0) (set! gc-since-resume #f)
      (call/cc
       (lambda (exit)
         (set! deliver exit)
         (let* ((payload (vector generation seed))
                (result
                 (dynamic-wind
                  (lambda () (set! before (+ before 1)))
                  (lambda ()
                    (map (lambda (x)
                           (if (= x 1)
                               (continuation-capture (lambda (k) (set! saved k) (deliver 'captured)))
                               payload)) '(0 1 2)))
                  (lambda () (set! after (+ after 1))))))
           ;; Latest dispatcher is intentional: multi-shot restore must return
           ;; to the current action, not restart the old history driver.
           (deliver result)))))
    (define (resume value)
      (let* ((actual (if (and (= fault 1) (> resumes 0) gc-since-resume)
                         (+ value 1) value))
             (result (call/cc (lambda (exit) (set! deliver exit) (continuation-return saved actual)))))
        (set! resumes (+ resumes 1)) (set! gc-since-resume #f)
        (set! last (cadr result))
        (and (= (length result) 3) (eq? (car result) (caddr result))
             (vector? (car result))
             (= (vector-ref (car result) 0) generation)
             (= (vector-ref (car result) 1) seed))))
    (let loop ((xs commands) (at 0))
      (if (null? xs)
          (begin (write (list 'root-task-result 'pass at)) (newline) (exit 0))
          (let* ((row (car xs)) (op (vector-ref row 0))
                 (value (vector-ref row 1)) (owner (= (vector-ref row 2) 0))
                 (accepted 0) (expected-accepted 0) (graph #t))
            (case op
              ((0) (if owner
                       (begin (set! eg (+ eg 1)) (set! eb (+ eb 1)) (set! ea (+ ea 1))
                              (set! el -3) (set! er 0) (set! have #t)
                              (set! expected-accepted 1)
                              (capture value) (set! accepted 1))))
              ((1) (if (and owner have)
                       (begin (set! eb (+ eb 1)) (set! ea (+ ea 1))
                              (set! er (+ er 1)) (set! el value)
                              (set! expected-accepted 1)
                              (set! graph (resume value)) (set! accepted 1))))
              ((2) (##gc) (set! gc-since-resume #t)
                   (set! expected-accepted 1) (set! accepted 1))
              ((3) (if (and owner have)
                       (begin (set! expected-accepted 1) (set! accepted 1)
                              (set! graph (and (##continuation? saved)
                                               (>= (##continuation-fs saved) 0))))))
              ((5) (set! expected-accepted (if (and owner have) 1 0))
                   (set! accepted (if (and owner saved) 1 0))))
            (let ((expected (vector expected-accepted eg eb ea el er 1))
                  (observed (vector accepted generation before after last resumes (if graph 1 0))))
              (let compare ((j 0))
                (if (< j 7)
                    (if (= (vector-ref expected j) (vector-ref observed j))
                        (compare (+ j 1))
                        (begin
                          (write (list 'root-task-result 'mismatch at op j
                                       (vector-ref expected j) (vector-ref observed j)
                                       (vector->list observed)))
                          (newline) (exit 71))))))
            (loop (cdr xs) (+ at 1)))))))

(define (continuation-suite)
  (set! family 'continuation) (set! trials 0)
  (let ((state 173) (actions 0))
    (define (next n)
      (set! state (modulo (+ (* state 48271) 17) 2147483647)) (modulo state n))
    (define (noise n)
      (if (= n 0) '()
          (cons (vector (next 6) (list-ref '(-1 0 1 2) (next 4)) (next 2)) (noise (- n 1)))))
    (define chain (list (vector 0 0 0) (vector 1 1 0) (vector 2 0 0) (vector 1 2 0)))
    (do ((sample 0 (+ sample 1))) ((= sample 24))
      (let* ((commands (append (noise 16) chain (noise 16))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "real continuation history failed" result minimal)))))
    (write (list 'CONTINUATION-HISTORY-PBT-PASS 'seed 173 'cases 24 'actions actions)) (newline)
    (let* ((noisy (append (make-list 12 (vector 5 0 0)) chain (make-list 8 (vector 4 0 0))))
           (failure (trial noisy 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(1 4))) (error "continuation invocation negative control missed" failure))
      (let* ((minimal (shrink noisy 1 wanted)) (replayed (trial minimal 1))
             (minimal? (one-minimal? minimal 1 wanted)))
        (if (not (and (= (length minimal) 4) minimal? (equal? (signature replayed) wanted)))
            (error "continuation shrink/replay certificate failed" minimal replayed))
        (with-output-to-file (trace-file "minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (write (list 'CONTINUATION-HISTORY-SHRINK-PASS 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'trials trials)) (newline)))
    (delete-file input-file)
    (display "CONTINUATION-HISTORY-REPLAY-PASS\n") (force-output)))



;;; Finite arithmetic/adapter checks, not another temporal model.
(define partition-check
  (c-lambda () bool #<<c-end
int n,np,id,lo,hi,prior,cases=0,empty=0;
___result=1;
for(n=0;n<=64;n++) for(np=1;np<=8;np++) {
  prior=0;
  for(id=0;id<np;id++) {
    if(!___root_globals_partition(n,id,np,&lo,&hi) || lo!=prior ||
       lo!=(id*n)/np || hi!=((id+1)*n)/np || lo>hi || hi>n) ___result=0;
    if(lo==hi) empty++;
    prior=hi;cases++;
  }
  if(prior!=n) ___result=0;
}
if(___root_globals_partition(-1,0,1,&lo,&hi) ||
   ___root_globals_partition(1,-1,1,&lo,&hi) ||
   ___root_globals_partition(1,1,1,&lo,&hi) ||
   ___root_globals_partition(1,0,0,&lo,&hi) ||
   ___root_globals_partition(1,0,1,0,&hi) ||
   ___root_globals_partition(1,0,1,&lo,0)) ___result=0;
if(___result) printf("GLOBALS-PARTITION-PASS cases=%d empty=%d invalid=6\n",cases,empty);
c-end
))
(define (globals-partitions)
  (if (not (partition-check)) (error "actual global partition arithmetic failed")))

(define globals-owned #f)
(define globals-relocate
  (c-lambda (scheme-object scheme-object) bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___PSTATE);
___SCMOBJ *cells[2]={0,0},before[2],saved[2];
int owners=vm->processor_count,id,lo,hi,i,failed=0,moved=0;
___result=0;
/* This is the existing p1/p2 fixture topology, not a runtime capacity limit.
 * Borrow only unbound cells; restore before Scheme allocation/lookup/return.
 * No user foreign cleanup callback is installed in this one-VM image. */
if((owners==1 || owners==2) && ___PROCESSOR_ID(___PSTATE,vm)==0) {
  for(id=0;id<owners;id++) {
#ifdef ___SINGLE_VM
    ___root_globals_partition(___GLO_SUBLIST_COUNT,id,owners,&lo,&hi);
    for(i=lo;i<hi && cells[id]==0;i++) {
      ___glo_struct *g=___GSTATE->mem.glo_list.sublist[i].head;
      for(;g!=0;g=g->next) if(g->val==___UNB1) {cells[id]=&g->val;break;}
    }
#else
    ___root_globals_partition(___GSTATE->mem.glo_list.count,id,owners,&lo,&hi);
    for(i=lo;i<hi;i++) if(vm->glos[i]==___UNB1) {cells[id]=&vm->glos[i];break;}
#endif
    if(cells[id]==0) break;
    printf("GLOBALS-ROOT-SHARD owner=%d lo=%d hi=%d\n",id,lo,hi);
  }
  if(id==owners) {
    for(id=0;id<owners;id++) {
      saved[id]=*cells[id];before[id]=id?___arg2:___arg1;*cells[id]=before[id];
    }
    failed=___EXT(___garbage_collect)(___PSA(___PSTATE) 0);
    for(id=0;id<owners;id++) {if(*cells[id]!=before[id]) moved++;*cells[id]=saved[id];}
    ___result=!failed && moved==owners;
  }
}
c-end
))
(define (globals-moving-roots)
  (dynamic-wind
   (lambda () #f)
   (lambda ()
     (set! globals-owned (cons 1103 (make-vector 7 751)))
     (if (not (globals-relocate (cons 1109 757) (cons 1117 761)))
         (error "actual global shard relocation or unbound-cell admission failed"))
     (##gc)
     (if (not (and (pair? globals-owned) (= (car globals-owned) 1103)
                   (equal? (cdr globals-owned) (make-vector 7 751))))
         (error "generated global setter/root value lost across moving GC"))
     (write (list 'GLOBALS-ROOT-MOVING-PASS 'participants (##current-vm-processor-count))) (newline))
   (lambda () (set! globals-owned #f))))

;;; Native-only relocation window: keep old tables in registered RC roots,
;;; install two small valid empty tables, collect, then restore old anchors
;;; before any Scheme lookup/allocation/callback/return. No user cleanup
;;; callback is installed in this exclusive one-VM/p1 fixture image.
(define symkey-relocate
  (c-lambda (scheme-object scheme-object) bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___PSTATE);
void *symbols=0, *keywords=0;
___SCMOBJ before_symbol=___arg1, before_keyword=___arg2;
int failed, moved;
___result=0;
if(vm->processor_count==1 && ___PROCESSOR_ID(___PSTATE,vm)==0 &&
   ___HD_TYP(___HEADER(before_symbol))==___MOVABLE0 &&
   ___HD_TYP(___HEADER(before_keyword))==___MOVABLE0) {
  symbols=___EXT(___alloc_rc)(___PSA(___PSTATE) 1);
  keywords=___EXT(___alloc_rc)(___PSA(___PSTATE) 1);
  if(symbols!=0 && keywords!=0 &&
     ___try_set_data_rc(___PSTATE,symbols,___GSTATE->symbol_table) &&
     ___try_set_data_rc(___PSTATE,keywords,___GSTATE->keyword_table)) {
    /* The actual two anchor cells, not copied values, are the moving roots.
     * Only native GC executes while valid empty tables are installed. */
    ___GSTATE->symbol_table=before_symbol;
    ___GSTATE->keyword_table=before_keyword;
    failed=___EXT(___garbage_collect)(___PSA(___PSTATE) 0);
    moved=___GSTATE->symbol_table!=before_symbol &&
          ___GSTATE->keyword_table!=before_keyword;
    ___GSTATE->symbol_table=___EXT(___data_rc)(symbols);
    ___GSTATE->keyword_table=___EXT(___data_rc)(keywords);
    ___result=!failed && moved;
  }
  if(keywords!=0) ___EXT(___release_rc)(keywords);
  if(symbols!=0) ___EXT(___release_rc)(symbols);
}
c-end
))
(define (symkey-moving-roots)
  (let ((symbol (string->symbol "gambit.smp.gc.root-task.symbol-anchor"))
        (keyword (string->keyword "gambit.smp.gc.root-task.keyword-anchor")))
    (if (not (symkey-relocate (vector 0 '()) (vector 0 '())))
        (error "symbol/keyword native relocation or p1/RC/movable precondition failed"))
    (##gc)
    (if (not (and (eq? symbol (string->symbol "gambit.smp.gc.root-task.symbol-anchor"))
                  (eq? keyword (string->keyword "gambit.smp.gc.root-task.keyword-anchor"))))
        (error "interned identity lost after original table restoration"))
    (display "SYMKEY-ROOT-MOVING-PASS\n")))

(c-declare "static ___SCMOBJ vm_root_before; static int vm_root_owned;")
(define vm-install
  (c-lambda (scheme-object) bool #<<c-end
___SCMOBJ *cells=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED);
/* Field2 is unused-field2 in both real _thread#.scm VM definitions. */
___result=cells[2]==___FAL;
if(___result) { cells[2]=___arg1; vm_root_before=___arg1; vm_root_owned=1; }
c-end
))
(define vm-value
  (c-lambda () scheme-object "___result=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2];"))
(define vm-moved?
  (c-lambda () bool "___result=___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2]!=vm_root_before;"))
(define vm-clear
  (c-lambda () void "if(vm_root_owned) { ___BODY0_AS(___VM_SCMOBJ(___VMSTATE_FROM_PSTATE(___PSTATE)),___tSUBTYPED)[2]=___FAL; vm_root_before=___FAL; vm_root_owned=0; }"))
(define (vm-moving-roots)
  (dynamic-wind
   (lambda () #f)
   (lambda ()
     (thread-join!
      (thread-start!
       (make-thread
        (lambda ()
          (if (not (vm-install (cons (+ 987 (##current-processor-id)) (make-vector 7 731))))
              (error "VM fixture unused-field2 unavailable"))
          #t))))
     (##gc)
     (if (not (vm-moved?)) (error "VM source payload did not move"))
     (##gc)
     (let ((value (vm-value)))
       (if (not (and (pair? value) (= (car value) 987)
                     (equal? (cdr value) (make-vector 7 731))))
           (error "VM root payload lost after moving GC")))
     (display "VM-ROOT-MOVING-PASS\n"))
   vm-clear))

(c-declare "static ___SCMOBJ bank_root_before; static ___execution_context *bank_root_context; static int bank_root_owned;")
(define bank-install
  (c-lambda (scheme-object) bool #<<c-end
___execution_context *source=___PSTATE->context;
___SCMOBJ *cells=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(source->processor_scmobj,___WS)),___tSUBTYPED);
/* unused-field15 in the real processor definition, _thread#.scm. */
___result=cells[15]==___FAL && !bank_root_owned;
if(___result) { cells[15]=___arg1; bank_root_before=___arg1; bank_root_context=source; bank_root_owned=1; }
c-end
))
(define bank-value
  (c-lambda () scheme-object "___result=___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(___PSTATE->context->processor_scmobj,___WS)),___tSUBTYPED)[15];"))
(define bank-moved?
  (c-lambda () bool "___result=bank_root_owned && bank_root_context==___PSTATE->context && ___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank_root_context->processor_scmobj,___WS)),___tSUBTYPED)[15]!=bank_root_before;"))
(define bank-clear
  (c-lambda () void "if(bank_root_owned && bank_root_context==___PSTATE->context) { ___BODY0_AS(___SUBTYPED_FROM_START(___ALIGNUP(bank_root_context->processor_scmobj,___WS)),___tSUBTYPED)[15]=___FAL; bank_root_before=___FAL; bank_root_context=0; bank_root_owned=0; }"))
(define (bank-moving-roots)
  (for-each
   (lambda (owner)
     (let ((thread
            (make-thread
             (lambda ()
               (dynamic-wind
                (lambda () #f)
                (lambda ()
                  (if (not (= (##current-processor-id) owner)) (error "bank fixture wrong owner"))
                  (if (not (bank-install (cons (+ 997 owner) (make-vector 7 739))))
                      (error "processor fixture unused-field15 unavailable"))
                  (##gc)
                  (if (not (bank-moved?)) (error "bank root cell not updated" owner))
                  (##gc)
                  (let ((value (bank-value)))
                    (if (not (and (pair? value) (= (car value) (+ 997 owner))
                                  (equal? (cdr value) (make-vector 7 739))))
                        (error "bank moving root lost" owner)))
                  (write (list 'BANK-ROOT-MOVING-PASS 'owner owner)) (newline))
                bank-clear)))))
       (if (> (##current-vm-processor-count) 1)
           (##thread-pin! thread (##processor owner)))
       (thread-start! thread) (thread-join! thread)))
   (if (> (##current-vm-processor-count) 1) '(0 1) '(0))))

(c-declare #<<c-end
static int intern_fail_vector,intern_failed_vectors,intern_scan_publish,intern_scan_ran;
static int intern_silent;
static ___SCMOBJ intern_scan_expected[2];
___SCMOBJ test_symkey_vector_allocate(___processor_state ps,___SIZE_TS len,___SCMOBJ init)
{
  if(intern_fail_vector && ps==0) { intern_fail_vector=0;++intern_failed_vectors;return ___FIX(___HEAP_OVERFLOW_ERR); }
  return ___make_vector(ps,len,init);
}
static void intern_force_growth(unsigned int type,int fail)
{
  ___SCMOBJ before,*values,tbl,sym;int n,count,len,i;char name[100];
  ___MUTEX_LOCK(___GSTATE->mem.global_gate);
  before=type==___sKEYWORD?___GSTATE->keyword_table:___GSTATE->symbol_table;
  len=___INT(___VECTORLENGTH(before));count=___INT(___VECTORELEM(before,0));
  ___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
  if(len>(INT_MAX-1)/4) _Exit(75);
  n=len*4-count+1;if(n<1) n=1;
  values=malloc((size_t)n*sizeof(*values));if(!values) _Exit(75);
  for(i=0;i<n;i++) {
    snprintf(name,sizeof(name),"gambit.smp.symkey-growth.%u.%d.%d",type,count,i);
    if(fail && i==n-1) intern_fail_vector=1;
    values[i]=___make_symkey_from_UTF_8_string(name,type);
    if(___FIXNUMP(values[i])) _Exit(77);
  }
  tbl=type==___sKEYWORD?___GSTATE->keyword_table:___GSTATE->symbol_table;
  if(___INT(___VECTORELEM(tbl,0))!=count+n ||
     (fail?(tbl!=before || intern_failed_vectors!=1 || intern_fail_vector):(___INT(___VECTORLENGTH(tbl))<=len))) _Exit(77);
  for(i=0;i<n;i++) {
    snprintf(name,sizeof(name),"gambit.smp.symkey-growth.%u.%d.%d",type,count,i);
    if(___find_symkey_from_UTF_8_string(name,type)!=values[i]) _Exit(77);
  }
  free(values);
  if(fail) {
    snprintf(name,sizeof(name),"gambit.smp.symkey-growth.retry.%u.%d",type,count);
    sym=___make_symkey_from_UTF_8_string(name,type);
    tbl=type==___sKEYWORD?___GSTATE->keyword_table:___GSTATE->symbol_table;
    if(___FIXNUMP(sym) || ___INT(___VECTORLENGTH(tbl))<=len || ___INT(___VECTORELEM(tbl,0))!=count+n+1) _Exit(77);
  }
  if(!intern_silent) printf("(SYMKEY-GROWTH-PASS type %u count %d added %d buckets-before %d buckets-after %d failed-vector %d)\n",
    type,count,n,len-1,___INT(___VECTORLENGTH(tbl))-1,fail);fflush(stdout);
}
/* A source mutation artifact invokes this strictly outside the registry
 * gate, after actual GC anchor capture. Normal production has no hook. */
void test_symkey_scan_publish(void)
{
  if(intern_scan_publish) {
    intern_scan_publish=0;++intern_scan_ran;
    intern_force_growth(___sSYMBOL,0);intern_force_growth(___sKEYWORD,0);
    intern_scan_expected[0]=___GSTATE->symbol_table;
    intern_scan_expected[1]=___GSTATE->keyword_table;
  }
}
c-end
)
(define intern-growth
 (c-lambda (int) void #<<c-end
int mode=___arg1,failed;
if(mode==2) {
  intern_scan_publish=1;intern_scan_ran=0;
  failed=___EXT(___garbage_collect)(___PSA(___PSTATE) 0);
  if(failed || intern_scan_ran!=1) _Exit(77);
  /* In the positive adapter the two newly published permanent anchors survive
   * the collector's local view. A stale write-back loses this longer table. */
  if(___GSTATE->symbol_table!=intern_scan_expected[0] ||
     ___GSTATE->keyword_table!=intern_scan_expected[1]) _Exit(77);
  printf("SYMKEY-GC-PUBLICATION-PASS\n");fflush(stdout);
} else {
  intern_failed_vectors=0;intern_force_growth(___sSYMBOL,mode==1);
  intern_failed_vectors=0;intern_force_growth(___sKEYWORD,mode==1);
  if(___EXT(___garbage_collect)(___PSA(___PSTATE) 0)) _Exit(77);
  printf("SYMKEY-GROWTH-GC-PASS\n");fflush(stdout);
}
c-end
))

(define (intern-suite)
 (set! family 'intern) (set! trials 0)
 (let ((seed 941) (actions 0))
  (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
  (define (noise n) (if (= n 0) '() (cons (vector (next 9) (- (next 4) 1) (next 2)) (noise (- n 1)))))
  (define chain (list (vector 3 0 0) (vector 3 0 0) (vector 4 0 0) (vector 4 0 0)
                      (vector 6 1 0) (vector 6 1 1) (vector 5 0 0) (vector 7 0 0) (vector 7 0 1)))
  (if (signature (trial chain 0)) (error "canonical native publication control failed"))
  (set! actions (length chain))
  (do ((sample 0 (+ sample 1))) ((= sample 12))
   (let* ((commands (append (noise 12) chain (noise 12))) (result (trial commands 0)))
    (set! actions (+ actions (length commands)))
    (if (signature result)
     (let ((minimal (shrink commands 0 (signature result))))
      (with-output-to-file (trace-file "failure") (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
      (error "actual interner property failed" result minimal)))))
  (write (list 'SYMKEY-PUBLICATION-PBT-PASS 'seed 941 'cases 12 'actions actions)) (newline)
  (let* ((noisy (append (make-list 6 (vector 0 0 0)) chain (make-list 6 (vector 7 0 0))))
         (wanted (signature (trial noisy 1))))
   (if (not (equal? wanted '(4 4))) (error "interner observer calibration missed" wanted))
   (let* ((minimal (shrink noisy 1 wanted)) (again (trial minimal 1)) (one? (one-minimal? minimal 1 wanted)))
    (if (not (and (= (length minimal) 1) one? (equal? wanted (signature again)) (not (signature (trial minimal 0)))))
        (error "interner shrink/replay failed" minimal again))
    (with-output-to-file (trace-file "minimal") (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
    (write (list 'SYMKEY-PUBLICATION-SHRINK-PASS 'from (length noisy) 'to (length minimal)
                 'replayed #t 'deletion-one-minimal one? 'production-pass #t 'trials trials)) (newline)))
  (delete-file input-file)))

;;; Managed fold views: protocol histories through actual Scheme/C consumers.
(c-declare #<<c-end
typedef struct test_view_reference_data {
  ___SCMOBJ vector; int used,size,ok;
} test_view_reference_data;
static void test_view_visit(___SCMOBJ sym,void *data)
{
  test_view_reference_data *d=(test_view_reference_data*)data;
  if(d->used>=d->size) d->ok=0;
  else ___VECTORELEM(d->vector,d->used++)=sym;
}
c-end
)
(define view-count
 (c-lambda (bool) int #<<c-end
___SCMOBJ table;
___MUTEX_LOCK(___GSTATE->mem.global_gate);
table=___arg1?___GSTATE->symbol_table:___GSTATE->keyword_table;
___result=___INT(___VECTORELEM(table,0));
___MUTEX_UNLOCK(___GSTATE->mem.global_gate);
c-end
))
(define view-reference-fill
 (c-lambda (scheme-object bool) bool #<<c-end
test_view_reference_data d;
d.vector=___arg1;d.used=0;d.size=___INT(___VECTORLENGTH(d.vector));d.ok=1;
___for_each_symkey(___arg2?___sSYMBOL:___sKEYWORD,test_view_visit,&d);
___result=d.ok && d.used==d.size;
c-end
))
(define view-grow
 (c-lambda (bool) void
  "intern_silent=1;intern_force_growth(___arg1?___sSYMBOL:___sKEYWORD,0);intern_silent=0;"))
(define view-gap-copy
 (c-lambda (scheme-object bool int) scheme-object #<<c-end
char name[100];int same;
unsigned int type=___arg2?___sSYMBOL:___sKEYWORD;
snprintf(name,sizeof(name),"gambit.smp.view-gap.%d.%u",___arg3,type);
#ifdef ___USE_POSIX_THREAD_SYSTEM
if(___find_symkey_from_UTF_8_string(name,type)!=___FAL) _Exit(75);
if(___FIXNUMP(intern_concurrent(name,type,1,&same)) || !same) _Exit(75);
#else
if(___FIXNUMP(___make_symkey_from_UTF_8_string(name,type))) _Exit(75);
#endif
___result=___symkey_table_view(___arg1,type);
c-end
))

(define (view-reference symbol?)
  (let ((v (make-vector (view-count symbol?) #f)))
    (if (not (view-reference-fill v symbol?)) (error "reference reader changed during exclusive fixture cut"))
    v))
(define (view-bijection? items reference)
  (let ((set (make-table test: eq?)) (ok #t) (count 0))
    (vector-for-each (lambda (sym) (table-set! set sym 1)) reference)
    (for-each (lambda (sym)
                (if (not (= (table-ref set sym 0) 1)) (set! ok #f))
                (table-set! set sym 0) (set! count (+ count 1))) items)
    (and ok (= count (vector-length reference)))))

;; Exact92d predecessor traversal, compiled as an implementation control.
;; Production keeps only the new fold; this is not an observation mutation.
(define (view-predecessor-fold f base symkey-table)
  (declare (standard-bindings) (extended-bindings))
  (let loop1 ((i (##fx- (##vector-length symkey-table) 1))
              (result base))
    (if (##fx> i 0)
        (let loop2 ((symkey (##vector-ref symkey-table i)) (result result))
          (if (##mem-allocated? symkey)
              (loop2 (##c-code "___RESULT = ___SYMKEY_NEXT_FIELD(___ARG1);" symkey)
                     (f result symkey))
              (loop1 (##fx- i 1) result)))
        result)))

;; The raw predecessor getter is confined to a negative control. It does not
;; reintroduce a production bucket interface or change the observation oracle.
(define view-predecessor-getter
  (c-lambda (bool) scheme-object
    "___result=___arg1?___GSTATE->symbol_table:___GSTATE->keyword_table;"))
(define (view-getter symbol?)
  ((if symbol? ##symbol-table ##keyword-table)))

(define (view-fold symbol? f base predecessor?)
  (if predecessor?
      (view-predecessor-fold f base (view-predecessor-getter symbol?))
      (if symbol?
          (##symbol-table-foldl f base)
          (##symkey-table-foldl f base (##keyword-table)))))

(define (view-oracle commands)
  (let ((have (vector #f #f)))
    (list->vector
     (map (lambda (row)
            (let ((op (vector-ref row 0)) (t (vector-ref row 2)))
              (if (= op 0) (vector-set! have t #t))
              (vector (if (and (= op 1) (not (vector-ref have t))) 0 1) 1 1 1)))
          commands))))

(define (replay-view commands fault)
  (let ((expected (view-oracle commands))
        (views (vector #f #f)) (copies (vector #f #f))
        (grown (vector #f #f)) (gc-count 0) (resumes 0)
        (fold-counts '()) (known (vector (make-vector 4 #f) (make-vector 4 #f))))
    (define (collect) (set! gc-count (+ gc-count 1)) (##gc))
    (define (grow symbol?)
      (let ((t (if symbol? 0 1)))
        (if (not (vector-ref grown t))
            (begin (view-grow symbol?) (vector-set! grown t #t)))))
    (define (continuation-check symbol?)
      (let ((reference (view-reference symbol?)) (saved #f)
            (generation 0) (enters 0) (leaves 0))
        (let ((items
               (dynamic-wind
                (lambda () (set! enters (+ enters 1)))
                (lambda ()
                  (view-fold symbol?
                   (lambda (lst sym)
                     (if (not saved)
                         (call/cc (lambda (k) (set! saved k) #f)))
                     (cons sym lst))
                   '() #f))
                (lambda () (set! leaves (+ leaves 1))))))
          (if (< generation 2)
              (begin (grow symbol?) (collect)
                     (set! generation (+ generation 1))
                     (set! resumes (+ resumes 1)) (saved #f))
              (and (= enters 3) (= leaves 3)
                   (view-bijection? items reference))))))
    (let loop ((xs commands) (at 0))
      (if (null? xs)
          (begin
            (write (list 'root-task-result 'pass (length commands)
                         'gc gc-count 'resumes resumes))
            (newline) (exit 0))
          (let* ((row (car xs)) (op (vector-ref row 0))
                 (slot (+ 1 (vector-ref row 1))) (t (vector-ref row 2))
                 (symbol? (= t 0)) (accepted 1) (ok #t) (source-ok #t))
            (case op
              ((0)
               (let* ((reference (view-reference symbol?))
                      (v (view-getter symbol?)))
                 (set! ok (view-bijection? (vector->list v) reference))
                 (vector-set! views t v)
                 (vector-set! copies t (vector-copy v))))
              ((1)
               (let ((v (vector-ref views t)))
                 (if (not v) (set! accepted 0)
                     (let* ((i (modulo slot (vector-length v)))
                            (old (vector-ref v i)) (reference (view-reference symbol?)))
                       (vector-set! v i #f)
                       (vector-set! (vector-ref copies t) i #f)
                       (set! source-ok
                             (and (= (vector-length reference) (view-count symbol?))
                                  (or (not old) (memq old (vector->list reference)))
                                  (not (memq #f (vector->list reference)))))))))
              ((2) (collect))
              ((3)
               (let* ((name (string-append "gambit.smp.view-name." (number->string slot)))
                      (value ((if symbol? string->symbol string->keyword) name))
                      (keys (vector-ref known t)))
                 (set! ok (or (not (vector-ref keys slot)) (eq? value (vector-ref keys slot))))
                 (vector-set! keys slot value)))
              ((4) (grow symbol?))
              ((5)
               (let* ((reference (view-reference symbol?)) (first #t)
                      (items
                       (view-fold symbol?
                        (lambda (lst sym)
                          (if first (begin (set! first #f) (grow symbol?) (collect)))
                          (cons sym lst))
                        '() (= fault 1))))
                 (set! fold-counts (list 'captured (vector-length reference) 'visited (length items)))
                 (set! ok (view-bijection? items reference))))
              ((6) (set! ok (continuation-check symbol?)))
              ((7)
               (let* ((n (view-count symbol?)) (v (make-vector n #f))
                      (actual (view-gap-copy v symbol? at)))
                 (set! ok (and (= actual (+ n 1))
                               (equal? v (make-vector n #f))))))
              ((8)
               (let ((entered 0) (left 0) (caught #f))
                 (with-exception-catcher
                  (lambda (e) (set! caught #t))
                  (lambda ()
                    (dynamic-wind
                     (lambda () (set! entered (+ entered 1)))
                     (lambda ()
                       (view-fold symbol?
                        (lambda (lst sym) (collect) (error "view callback escape control"))
                        '() #f))
                     (lambda () (set! left (+ left 1))))))
                 (collect)
                 (set! ok (and caught (= entered 1) (= left 1)
                               (= (length (view-fold symbol? (lambda (lst sym) (cons sym lst)) '() #f))
                                  (view-count symbol?))))))
              ((9)
               (let* ((get (if (= fault 2) view-predecessor-getter view-getter))
                      (first (get symbol?)) (second (get symbol?)))
                 ;; Refuse the old shared alias before mutating it: a negative
                 ;; control must not corrupt the registry and invent failures.
                 (set! ok (not (eq? first second)))
                 (if ok
                     (let* ((reference (view-reference symbol?))
                            (saved (vector-copy first)))
                       (set! ok (and (view-bijection? (vector->list first) reference)
                                     (equal? first second)))
                       (grow symbol?) (collect)
                       (set! ok (and ok (equal? first saved) (equal? second saved)))
                       (if (> (vector-length first) 0) (vector-set! first 0 #f))
                       (collect)
                       (set! source-ok
                             (and (equal? second saved)
                                  (not (memq #f (vector->list (view-reference symbol?)))))))))))

            (let* ((stable
                    (and (or (not (vector-ref views 0))
                             (equal? (vector-ref views 0) (vector-ref copies 0)))
                         (or (not (vector-ref views 1))
                             (equal? (vector-ref views 1) (vector-ref copies 1)))))
                   (observed (vector accepted (if ok 1 0) (if stable 1 0) (if source-ok 1 0)))
                   (wanted (vector-ref expected at)))
              (do ((j 0 (+ j 1))) ((= j 4))
                (if (not (= (vector-ref observed j) (vector-ref wanted j)))
                    (begin
                      (write (list 'root-task-result 'mismatch at op j
                                   (vector-ref observed j) (vector->list observed) fold-counts))
                      (newline) (exit 71)))))
            (loop (cdr xs) (+ at 1)))))))

(define (view-suite)
  (set! family 'view) (set! trials 0)
  (let ((seed 997) (actions 0))
    (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
    (define (noise n)
      (if (= n 0) '() (cons (vector (next 10) (- (next 4) 1) (next 2)) (noise (- n 1)))))
    (define chain (list (vector 0 0 0) (vector 0 0 1) (vector 5 0 0)
                        (vector 6 0 0) (vector 1 1 0) (vector 2 0 0)
                        (vector 7 0 1) (vector 8 0 1) (vector 9 0 0) (vector 9 0 1)))
    (let ((control (trial chain 0)))
      (if (signature control) (error "actual view mandatory control failed" control))
      (write (list 'SYMKEY-VIEW-CONTINUATION-PASS 'mandatory-result control)) (newline))
    (set! actions (length chain))
    (do ((sample 0 (+ sample 1))) ((= sample 12))
      (let* ((commands (append (noise 8) chain (noise 8))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "actual managed view property failed" result minimal)))))
    (write (list 'SYMKEY-VIEW-PBT-PASS 'seed 997 'cases 12 'actions actions)) (newline)
    (let* ((commands (append (make-list 6 (vector 2 0 0)) (list (vector 5 0 0))
                             (make-list 6 (vector 0 0 0))))
           (failure (trial commands 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(5 1))) (error "compiled predecessor fold counterexample missed" failure))
      (let* ((minimal (shrink commands 1 wanted)) (again (trial minimal 1))
             (one? (one-minimal? minimal 1 wanted)) (positive (trial minimal 0)))
        (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted)
                      (not (signature positive))))
            (error "actual predecessor view shrink/replay failed" minimal again positive))
        (with-output-to-file (trace-file "legacy-minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (with-output-to-file (trace-file "current-minimal")
          (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
        (write (list 'SYMKEY-VIEW-IMPLEMENTATION-SHRINK-PASS 'from (length commands)
                     'to (length minimal) 'trials trials 'deletion-one-minimal one?
                     'replayed #t 'production-pass #t 'predecessor failure 'minimal-result again))
        (newline)))
    (let* ((commands (append (make-list 6 (vector 2 0 0)) (list (vector 9 0 0))
                             (make-list 6 (vector 0 0 0))))
           (failure (trial commands 2)) (wanted (signature failure)) (before trials))
      (if (not (equal? wanted '(9 1))) (error "raw getter alias counterexample missed" failure))
      (let* ((minimal (shrink commands 2 wanted)) (again (trial minimal 2))
             (one? (one-minimal? minimal 2 wanted)) (positive (trial minimal 0)))
        (if (not (and (= (length minimal) 1) one? (equal? (signature again) wanted)
                      (not (signature positive))))
            (error "actual getter alias shrink/replay failed" minimal again positive))
        (for-each
         (lambda (pair)
           (with-output-to-file (trace-file (car pair))
             (lambda () (write (list (trace-tag) 1 minimal (cdr pair))) (newline))))
         '(("getter-legacy-minimal" . 2) ("getter-current-minimal" . 0)))
        (write (list 'SYMKEY-GETTER-IMPLEMENTATION-SHRINK-PASS 'from (length commands)
                     'to (length minimal) 'trials (- trials before) 'deletion-one-minimal one?
                     'replayed #t 'production-pass #t)) (newline)))
    (delete-file input-file)))

(define (snapshot-suite)
  ((c-lambda () void #<<c-end
printf("(GLOBALS-SNAPSHOT-LAYOUT global-added %lu vm-pointer %lu snapshot %lu source %lu task %lu participants-capacity %d)\n",
  (unsigned long)(sizeof(___gstate_mem)-3*sizeof(void*)-sizeof(___glo_list_struct)),
  (unsigned long)sizeof(void*),(unsigned long)sizeof(___global_root_snapshot),
  (unsigned long)sizeof(___global_root_source),(unsigned long)sizeof(___root_task),___MAX_PROCESSORS);
fflush(stdout);
c-end
))
  (set! family 'snapshot) (set! trials 0)
  (let ((seed 881) (actions 0))
    (define (next n) (set! seed (modulo (+ (* seed 48271) 17) 2147483647)) (modulo seed n))
    (define (noise n) (if (= n 0) '() (cons (vector (next 9) (- (next 4) 1) 0) (noise (- n 1)))))
    (define chain (map (lambda (op) (vector op 0 0)) '(1 3 2 4 7 5 6 7)))
    (let ((result (trial chain 0)))
      (if (signature result) (error "actual cross-VM prefix control failed" result)))
    (set! actions (length chain))
    (display "GLOBALS-SNAPSHOT-PREFIX-PASS\n")
    (do ((sample 0 (+ sample 1))) ((= sample 12))
      (let* ((commands (append (noise 12) chain (noise 12))) (result (trial commands 0)))
        (set! actions (+ actions (length commands)))
        (if (signature result)
            (let ((minimal (shrink commands 0 (signature result))))
              (with-output-to-file (trace-file "failure")
                (lambda () (write (list (trace-tag) 1 minimal 0)) (newline)))
              (error "actual snapshot property failed" result minimal)))))
    (write (list 'GLOBALS-SNAPSHOT-PBT-PASS 'seed 881 'cases 12 'actions actions)) (newline)
    (let* ((noisy (append (make-list 6 (vector 7 0 0)) chain (make-list 6 (vector 8 2 0))))
           (failure (trial noisy 1)) (wanted (signature failure)))
      (if (not (equal? wanted '(2 2))) (error "live-count calibration missed" failure))
      (let* ((minimal (shrink noisy 1 wanted)) (replayed (trial minimal 1))
             (minimal? (one-minimal? minimal 1 wanted)))
        (if (not (and (= (length minimal) 2) minimal?
                      (equal? (signature replayed) wanted) (not (signature (trial minimal 0)))))
            (error "snapshot replay/shrink failed" minimal replayed))
        (with-output-to-file (trace-file "minimal")
          (lambda () (write (list (trace-tag) 1 minimal 1)) (newline)))
        (write (list 'GLOBALS-SNAPSHOT-SHRINK-PASS 'from (length noisy) 'to (length minimal)
                     'deletion-one-minimal minimal? 'replayed #t 'production-pass #t 'trials trials))
        (newline)))
    (delete-file input-file)))

(define (globals-capacity)
  (let ((refused
         ((c-lambda () scheme-object #<<c-end
#ifdef ___SINGLE_VM
___result=___FAL;
#else
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___PSTATE);
___SCMOBJ sym=___FAL,first=___FAL,err;
char name[80];
int initial=___CAST(int,___GSTATE->mem.glo_list.count),i;
for(i=initial;i<___GLOBALS_CAPACITY;i++) {
  snprintf(name,sizeof(name),"___globals_capacity_identity_%d",i);
  sym=___make_symkey_from_UTF_8_string(name,___sSYMBOL);
  if(___FIXNUMP(sym) || ___GLOBALVARSTRUCT(sym)!=0 || ___make_global_var(sym)!=sym ||
     ___GLOBALVARSTRUCT(sym)->val!=i || vm->glos[i]!=___UNB1) _Exit(74);
  if(first==___FAL) first=sym;
}
sym=___make_symkey_from_UTF_8_string("___globals_capacity_refused",___sSYMBOL);
err=___make_global_var(sym);
if(err!=___FIX(___IMPL_LIMIT_ERR) || ___GLOBALVARSTRUCT(sym)!=0 ||
   ___GSTATE->mem.glo_list.count!=___GLOBALS_CAPACITY ||
   (first!=___FAL && ___make_global_var(first)!=first)) _Exit(74);
printf("(GLOBALS-CAPACITY-NATIVE-PASS initial %d actual %d added %d)\n",initial,___GLOBALS_CAPACITY,___GLOBALS_CAPACITY-initial);
fflush(stdout);___result=sym;
#endif
c-end
))))
    (if (not refused) (error "capacity control requires multiple VMs"))
    (let ((caught #f))
      (with-exception-catcher
       (lambda (e) (if (not (heap-overflow-exception? e)) (raise e)) (set! caught #t))
       (lambda () (##make-global-var refused)))
      (if (not caught) (error "capacity refusal did not reach Scheme"))
      (display "GLOBALS-CAPACITY-SCHEME-PASS\n"))))

;;; Child descriptor closure keeps the same forked PID and exact byte stream.
(c-declare #<<c-end
#ifdef USE_POSIX
static int process_initial_stdin = -1;
#endif
#if defined(USE_POSIX) && defined(__GNUC__)
static void __attribute__((constructor)) process_stdio_snapshot (void)
{
  process_initial_stdin = fcntl (0, F_GETFD);
  if (getenv("GAMBIT_TEST_PROCESS_STDIO") != NULL)
    {
      char text[96];
      int n = snprintf(text,sizeof(text),"(%ld %s)\n",(long)getpid(),
                       process_initial_stdin < 0 ? "#t" : "#f");
      _Exit(write(STDOUT_FILENO,text,n)==n ? 0 : 73);
    }
}
#endif
c-end
)
(define process-fd
 (c-lambda (int int) int #<<c-end
#ifdef USE_POSIX
int fd=___arg2;
switch(___arg1) {
case 0:
#ifdef __GNUC__
  fd=open("/dev/null",O_RDONLY); if(fd>=0) { int high=fcntl(fd,F_DUPFD,FD_SETSIZE+1); close(fd); fd=high; }
#else
  fd=-1;
#endif
  break;
case 1: fd=fcntl(fd,F_GETFD); break;
case 2: fd=close(fd); break;
case 3: fd=getpid(); break;
case 4: fd=fcntl(0,F_SETFD,FD_CLOEXEC); break;
case 5: fd=process_initial_stdin; break;
case 6:
#ifdef __GNUC__
  fd=1;
#else
  fd=0;
#endif
  break;
}
___result=fd;
#else
___result=-1;
#endif
c-end
))
(define (process-contract)
  (define (check x label) (if (not x) (error "process descriptor contract" label)))
  (define (observe args . settings)
    (let* ((port (open-input-process (append (list path: (path-expand self)
                         arguments: (cons "-:p1" args) stderr-redirection: #t) settings)))
           (pid (process-pid port)) (answer (read port)) (status (process-status port)))
      (close-input-port port)
      (check (= status 0) 'exit)
      (check (and (pair? answer) (= pid (car answer))) 'same-pid)
      (cdr answer)))
  (let ((fd (process-fd 0 0)))
    (if (and (= (process-fd 6 0) 1) (< fd 0)) (error "descriptor probe allocation failed"))
    (if (< fd 0) (display "PROCESS-POSIX-DESCRIPTORS-UNAVAILABLE\n"))
    (if (>= fd 0)
      (begin
        (check (equal? (observe (list "--process-probe" (number->string fd))) '(#f #t)) 'high-fd-closed)
        (check (>= (process-fd 1 fd) 0) 'parent-retains-fd)
        (check (equal? (observe (list "--process-probe" (number->string fd)) directory: (current-directory)) '(#f #t)) 'cwd-preserved)
        (check (equal? (observe '("--process-env") environment: '("GAMBIT_PROCESS_CONTRACT=owned")) '("owned")) 'env-preserved)
        (check (= (process-fd 2 fd) 0) 'parent-release)
  (check (equal? (observe '("--process-stdin" "closed")) '(#t)) 'closed-stdin-fallback)
  (check (equal? (observe '("--process-stdin" "cloexec")) '(#t)) 'cloexec-stdin-fallback)
        (display "PROCESS-POSIX-DESCRIPTORS-PASS\n"))))
  (let* ((port (open-input-process (list path: (path-expand self)
                   arguments: '("-:p1" "--process-bytes") stderr-redirection: #t char-encoding: 'ISO-8859-1)))
         (bytes (let loop ((xs '())) (let ((b (read-u8 port)))
                   (if (eof-object? b) (reverse xs) (loop (cons b xs)))))))
    (check (= (process-status port) 0) 'bytes-exit) (close-input-port port)
    (check (= (length bytes) 512) 'all-byte-length)
    (let loop ((i 0) (xs bytes))
      (if (< i 512)
          (begin (check (= (car xs) (modulo i 256)) 'all-bytes)
                 (loop (+ i 1) (cdr xs))))))
  (let ((caught #f))
    (with-exception-catcher (lambda (e) (set! caught #t))
      (lambda () (open-input-process (list path: (string-append (path-expand self) ".absent-process")))))
    (check caught 'exec-failure))
  (display "PROCESS-DESCRIPTOR-CONTRACT-PASS\n"))

(let ((args (cdr (command-line))))
  (cond ((equal? args '("--symkey-callback"))
         (cond-expand (symkey-callback-test (symkey-callback-suite))
                      (else (error "symkey callback test feature not selected"))))
        ((equal? args '("--process-contract")) (process-contract))
        ((equal? args '("--process-env")) (write (list (process-fd 3 0) (getenv "GAMBIT_PROCESS_CONTRACT"))) (newline))
        ((equal? args '("--process-bytes"))
         (do ((i 0 (+ i 1))) ((= i 256)) (write-u8 i)) (force-output)
         (do ((i 0 (+ i 1))) ((= i 256)) (write-u8 i (current-error-port))) (force-output (current-error-port)))
        ((and (= (length args) 2) (string=? (car args) "--process-probe"))
         (write (list (process-fd 3 0) (>= (process-fd 1 (string->number (cadr args))) 0) (>= (process-fd 5 0) 0))) (newline))
        ((and (= (length args) 2) (string=? (car args) "--process-stdin"))
         (if (string=? (cadr args) "closed") (process-fd 2 0) (process-fd 4 0))
         (let* ((port (open-input-process (list path: (path-expand self) arguments: '("-:p1" "--process-probe" "-1") stdin-redirection: #f
                            environment: '("GAMBIT_TEST_PROCESS_STDIO=1"))))
                (answer (read port)) (status (process-status port)))
           (close-input-port port) (if (not (= status 0)) (error "stdin child failed"))
           (write (list (process-fd 3 0) (cadr answer))) (newline)))
        ((and (= (length args) 1) (string=? (car args) "--intern-growth")) (intern-growth 0))
        ((and (= (length args) 1) (string=? (car args) "--intern-growth-fault")) (intern-growth 1))
        ((and (= (length args) 1) (string=? (car args) "--intern-gc-publish")) (intern-growth 2))
        ((and (= (length args) 1) (string=? (car args) "--marker-input"))
         (cond-expand (marker-input-test (marker-input-suite))
                      (else (error "marker-input test feature not selected"))))
        ((and (= (length args) 1) (string=? (car args) "--tcl-callback"))
         (cond-expand (tcl-command-test (tcl-callback-suite))
                      (else (error "Tcl callback feature not selected"))))
        ((and (= (length args) 1) (string=? (car args) "--tcl-command")) (tcl-command-suite))
        ((and (= (length args) 1) (string=? (car args) "--rc-writes")) (rc-write-suite))
        ((and (= (length args) 1) (string=? (car args) "--symkey-views")) (view-suite))
        ((and (= (length args) 1) (string=? (car args) "--symkey-publication")) (intern-suite))
        ((and (= (length args) 1) (string=? (car args) "--globals-snapshot")) (snapshot-suite))
        ((and (= (length args) 1) (string=? (car args) "--globals-capacity")) (globals-capacity))
        ((and (= (length args) 2) (string=? (car args) "--replay"))
         (replay (call-with-input-file (cadr args) read)))
        ((and (= (length args) 1) (string=? (car args) "--moving-bank")) (bank-moving-roots))
        ((and (= (length args) 1) (string=? (car args) "--moving-globals")) (globals-moving-roots))
        ((null? args) (globals-partitions) (globals-moving-roots) (symkey-moving-roots) (vm-moving-roots) (for-each (lambda (kind) (set! family kind) (suite)) '(rc vm bank stack symkey globals))
         (continuation-suite))
        (else (error "usage: root-task [--replay TRACE | --moving-bank | --moving-globals]"))))
