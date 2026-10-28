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
(define family 'rc)
(define (trace-tag)
  (case family ((view) 'symkey-view-trace) ((intern) 'symkey-publication-trace) ((snapshot) 'globals-snapshot-trace) ((vm) 'vm-root-task-trace) ((bank) 'bank-root-task-trace) ((stack) 'stack-root-task-trace) ((symkey) 'symkey-root-task-trace) ((globals) 'globals-root-task-trace)
    ((continuation) 'continuation-history)
    (else 'root-task-trace)))
(define (trace-file suffix)
  (string-append (case family ((view) "symkey-view-") ((intern) "symkey-publication-") ((snapshot) "globals-snapshot-") ((vm) "vm-root-task-")
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
  (and (list? x) (= (length x) 4) (memq (car x) '(root-task-trace vm-root-task-trace bank-root-task-trace stack-root-task-trace symkey-root-task-trace globals-root-task-trace globals-snapshot-trace symkey-publication-trace symkey-view-trace continuation-history))
       (integer? (cadr x)) (<= 1 (cadr x) 3) (list? (caddr x))
       (<= (length (caddr x)) 96) (memv (cadddr x) '(0 1))
       (let loop ((xs (caddr x)))
         (or (null? xs)
             (let ((r (car xs)))
               (and (vector? r) (= (vector-length r) 3)
                    (integer? (vector-ref r 0)) (<= 0 (vector-ref r 0) (case (car x) ((globals-snapshot-trace symkey-publication-trace symkey-view-trace) 8) ((globals-root-task-trace) 6) (else 5)))
                    (memv (vector-ref r 1) '(-1 0 1 2))
                    (memv (vector-ref r 2) '(0 1)) (loop (cdr xs))))))))
(define (replay trace)
  (if (not (trace? trace)) (error "invalid structured root-task trace"))
  (set! family (case (car trace) ((symkey-view-trace) 'view) ((symkey-publication-trace) 'intern) ((globals-snapshot-trace) 'snapshot) ((vm-root-task-trace) 'vm)
                 ((bank-root-task-trace) 'bank) ((stack-root-task-trace) 'stack) ((symkey-root-task-trace) 'symkey) ((globals-root-task-trace) 'globals)
                 ((continuation-history) 'continuation) (else 'rc)))
  (if (not (prepare-source)) (error "root-task source allocation failed"))
  (do ((i 0 (+ i 1))) ((= i (cadr trace))) (##gc))
  (let ((commands (caddr trace)))
    (cond ((eq? family 'view) (replay-view commands (cadddr trace)))
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
  (let* ((port (open-input-process
                (list path: self arguments: (list "-:p1" "--replay" input-file)
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
       (##thread-pin! thread (##processor owner))
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

(define (view-fold symbol? f base predecessor?)
  (if predecessor?
      (view-predecessor-fold f base (if symbol? (##symbol-table) (##keyword-table)))
      (if symbol?
          (##symbol-table-foldl f base)
          (##symkey-table-foldl f base (##symkey-table-view #f)))))

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
                      (v (##symkey-table-view symbol?)))
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
                                  (view-count symbol?)))))))
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
      (if (= n 0) '() (cons (vector (next 9) (- (next 4) 1) (next 2)) (noise (- n 1)))))
    (define chain (list (vector 0 0 0) (vector 0 0 1) (vector 5 0 0)
                        (vector 6 0 0) (vector 1 1 0) (vector 2 0 0)
                        (vector 7 0 1) (vector 8 0 1)))
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

(let ((args (cdr (command-line))))
  (cond ((and (= (length args) 1) (string=? (car args) "--intern-growth")) (intern-growth 0))
        ((and (= (length args) 1) (string=? (car args) "--intern-growth-fault")) (intern-growth 1))
        ((and (= (length args) 1) (string=? (car args) "--intern-gc-publish")) (intern-growth 2))
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
