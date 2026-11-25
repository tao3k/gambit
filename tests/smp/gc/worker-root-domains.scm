(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#worker_root_domains#"
  record! drop! drop-children! cleanup-closed? workers! coherent? released? entries note-entry request roots check saved exit winds
  collect answer first second third rc-check? rc-drop! callback callback! callback-value
  callback-count callback-void callback-count! callback-void! scopes-drained?))
(c-declare #<<c-end
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
___SCMOBJ gambit_smp_gc_root_domains_callback(___SCMOBJ,char*,int);
int gambit_smp_gc_root_domains_count(___SCMOBJ);
void gambit_smp_gc_root_domains_void(___SCMOBJ);
static struct domain_payload { pthread_t thread; int owner; int generation; } domain_payloads[___MAX_PROCESSORS], domain_child_payloads[___MAX_PROCESSORS];
static _Atomic int domain_entries, domain_released, domain_bad;
static _Atomic int domain_releases[___MAX_PROCESSORS];
static ___SCMOBJ domain_objects[___MAX_PROCESSORS], domain_children[___MAX_PROCESSORS];
static _Atomic int domain_child_releases[___MAX_PROCESSORS];
static _Atomic int domain_cleanup_rejected, domain_slot_rejected;
static _Atomic int domain_reentry_rejected, domain_run_rejected, domain_collect_rejected, domain_alloc_rejected;
extern ___SCMOBJ *___borrow_rc_root(___processor_state,void *);
extern void ___return_rc_root(void *);
static void *domain_rc[___MAX_PROCESSORS];
static ___SCMOBJ *domain_rc_root[___MAX_PROCESSORS];
static _Atomic int domain_rc_rejected;
static _Atomic int domain_initialization_rejected;
static int domain_initialization_closed(___processor_state ps) {
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  int id=___PROCESSOR_ID(ps,vm);
  ___execution_context *context=ps->context;
  ___collector_worker *worker=ps->collector;
  ___WORD incarnation=vm->gc_origins[id].incarnation;
  ___WORD *fp=context->fp, *hp=context->hp;
  ___rc_header *head=&context->mem.rc_head_;
  ___rc_header *next=head->next, *prev=head->prev;
  if (!___gc_cleanup_empty(&vm->gc_participants[id].cleanup)) return 0;
  if (___setup_pstate(ps,vm)!=___FIX(___UNKNOWN_ERR)) {
    /* Stop before returning through frames an incorrect setup may overwrite.
     * This is also the predecessor's bounded negative control. */
    fputs("CONTEXT-INITIALIZATION-OVERWROTE-LIVE-ORIGIN\n",stderr);
    exit(2);
  }
  return ps->context==context && ps->collector==worker &&
    vm->gc_origins[id].incarnation==incarnation &&
    vm->gc_participants[id].phase==___GC_RUNNING &&
    context->fp==fp && context->hp==hp &&
    head->next==next && head->prev==prev;
}
static ___SCMOBJ domain_release(void *p) {
  struct domain_payload *d=p;
  ___processor_state ___ps=___GET_PSTATE();
  ___processor_state ps=___ps;
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  if (!pthread_equal(pthread_self(),d->thread) || ___PROCESSOR_ID(ps,vm)!=d->owner)
    atomic_fetch_add(&domain_bad,1);
  {
    ___gc_cleanup_escrow *e=&vm->gc_participants[d->owner].cleanup;
    if (!e->pending || !e->inflight || e->payload!=p || e->release_fn!=domain_release ||
        vm->gc_participants[d->owner].phase!=___GC_OWNER_CLEANUP)
      atomic_fetch_add(&domain_bad,1);
  }
  if (d->generation) {
    atomic_fetch_add(&domain_child_releases[d->owner],1);
  } else {
    ___SCMOBJ obj, err, oversized;
    void *denied_bank=0;
    ___SCMOBJ unchanged=*domain_rc_root[d->owner], marker=___FIX(123);
    if (___begin_sfun(ps,&denied_bank,unchanged,2)!=___FIX(___NO_ERR) &&
        denied_bank==0 && ___alloc_rc(___PSP 0)==0 &&
        !___set_data_rc(domain_rc[d->owner],___FAL) &&
        ___borrow_rc_root(ps,domain_rc[d->owner])==0 &&
        ___make_sfun_stack_marker(ps,&marker,unchanged)!=___FIX(___NO_ERR) &&
        marker==___FIX(123) && *domain_rc_root[d->owner]==unchanged)
      atomic_fetch_add(&domain_rc_rejected,1);
    else atomic_fetch_add(&domain_bad,1);
    atomic_fetch_add(&domain_released,1);
    atomic_fetch_add(&domain_releases[d->owner],1);
    ___WORD before_r[___NB_GVM_REGS];
    ___WORD *before_fp=ps->context->fp, *before_hp=ps->context->hp;
    ___jmpbuf_struct *before_catcher=ps->catcher;
    memcpy(before_r,ps->context->r,sizeof(before_r));
    if (___run(___PSP ___FAL)==___FIX(___UNKNOWN_ERR))
      atomic_fetch_add(&domain_run_rejected,1);
    else atomic_fetch_add(&domain_bad,1);
    {
      int before=___GSTATE->setup_state;
      ___cleanup();
      if (before==1 && ___GSTATE->setup_state==before && vm->processor_count==3 &&
          vm->gc_participants[d->owner].phase==___GC_OWNER_CLEANUP)
        atomic_fetch_add(&domain_cleanup_rejected,1);
      else atomic_fetch_add(&domain_bad,1);
    }
    {
      ___WORD before=vm->gc_origins[d->owner].incarnation;
      ___execution_context *context=ps->context;
      ___collector_worker *worker=ps->collector;
#ifndef ___SINGLE_THREADED_VMS
      int sync=ps->sync_initialized;
#endif
      if (___setup_pstate(ps,vm)==___FIX(___UNKNOWN_ERR) &&
          vm->gc_origins[d->owner].incarnation==before &&
          ps->context==context && ps->collector==worker &&
#ifndef ___SINGLE_THREADED_VMS
          ps->sync_initialized==sync &&
#endif
          vm->gc_participants[d->owner].phase==___GC_OWNER_CLEANUP)
        atomic_fetch_add(&domain_slot_rejected,1);
      else atomic_fetch_add(&domain_bad,1);
    }
    if (___call(___PSP 0,___FAL,___FAL)==___FIX(___UNKNOWN_ERR))
      atomic_fetch_add(&domain_reentry_rejected,1);
    else atomic_fetch_add(&domain_bad,1);
    if (___garbage_collect(___PSP 0)) atomic_fetch_add(&domain_collect_rejected,1);
    else atomic_fetch_add(&domain_bad,1);
    oversized=___alloc_scmobj(ps,___sU8VECTOR,vm->mem.heap_size_*___WS);
    if (___FIXNUMP(oversized)) atomic_fetch_add(&domain_alloc_rejected,1);
    else { atomic_fetch_add(&domain_bad,1); ___release_scmobj(oversized); }
    if (ps->context->fp!=before_fp || ps->context->hp!=before_hp ||
        ps->catcher!=before_catcher ||
        memcmp(before_r,ps->context->r,sizeof(before_r))!=0)
      atomic_fetch_add(&domain_bad,1);
    domain_child_payloads[d->owner].owner=d->owner;
    domain_child_payloads[d->owner].generation=1;
    domain_child_payloads[d->owner].thread=pthread_self();
    err=___POINTER_to_SCMOBJ(ps,&domain_child_payloads[d->owner],___FAL,
                           domain_release,&obj,0);
    if (err!=___FIX(___NO_ERR)) atomic_fetch_add(&domain_bad,1);
    else domain_children[d->owner]=obj; /* explicit still refcount root */
  }
  return ___FIX(___NO_ERR);
}
static int domain_record(___processor_state ps, ___SCMOBJ root) {
  ___processor_state ___ps=ps;
  ___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(ps);
  int id=___PROCESSOR_ID(ps,vm);
  ___SCMOBJ obj, err;
  if (!domain_initialization_closed(ps)) return 0;
  atomic_fetch_add(&domain_initialization_rejected,1);
  domain_rc[id]=___alloc_rc(___PSP 0);
  if (!domain_rc[id] || !___set_data_rc(domain_rc[id],root)) return 0;
  domain_rc_root[id]=___borrow_rc_root(ps,domain_rc[id]);
  if (!domain_rc_root[id]) return 0;
  ___release_rc(domain_rc[id]); /* borrow owns the only native reference */
  domain_payloads[id].thread=pthread_self(); domain_payloads[id].owner=id;
  err=___POINTER_to_SCMOBJ(ps,&domain_payloads[id],___FAL,domain_release,&obj,0);
  if (err!=___FIX(___NO_ERR)) return 0;
  domain_objects[id]=obj; /* still refcount=1 protects this C-held object */
  return 1;
}
c-end
)
(define record! (c-lambda (scheme-object) bool "___return(domain_record(___ps,___arg1));"))
(define rc-check? (c-lambda () bool #<<c-end
if (atomic_load(&domain_rc_rejected)!=3 ||
    atomic_load(&domain_initialization_rejected)!=3) ___return(0);
for(int i=0;i<3;i++) {
  ___SCMOBJ v=*domain_rc_root[i];
  ___SCMOBJ ___temp;
  if (!___VECTORP(v) || ___INT(___VECTORELEM(v,0))!=271828 ||
      ___VECTORELEM(v,1)!=v) ___return(0);
}
___SCMOBJ marker;
if (___make_sfun_stack_marker(___ps,&marker,*domain_rc_root[0])!=___FIX(___NO_ERR)) ___return(0);
if (___VECTORELEM(marker,0)!=*domain_rc_root[0]) ___return(0);
___kill_sfun_stack_marker(marker);
___return(1);
c-end
))
(define rc-drop! (c-lambda () void "for(int i=0;i<3;i++) { ___return_rc_root(domain_rc[i]); domain_rc[i]=0; domain_rc_root[i]=0; }"))
(define drop! (c-lambda () void "for(int i=0;i<3;i++) { ___release_scmobj(domain_objects[i]); domain_objects[i]=___FAL; }"))
(define drop-children! (c-lambda () void "for(int i=0;i<3;i++) { ___release_scmobj(domain_children[i]); domain_children[i]=___FAL; }"))
(define cleanup-closed?
  (c-lambda (bool) bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
if (atomic_load(&domain_bad) || atomic_load(&domain_reentry_rejected)!=3 ||
    atomic_load(&domain_run_rejected)!=3 || atomic_load(&domain_cleanup_rejected)!=3 || atomic_load(&domain_slot_rejected)!=3 ||
    atomic_load(&domain_collect_rejected)!=3 || atomic_load(&domain_alloc_rejected)!=3)
  ___return(0);
for (int i=0;i<3;i++) {
  if (!___gc_cleanup_empty(&vm->gc_participants[i].cleanup)) ___return(0);
  ___WORD *base=(___WORD *)vm->gc_participants[i].context->mem.still_objs_;
  ___SIZE_TS words=0; int child_found=0;
  for (;base;base=(___WORD *)base[___STILL_LINK]) {
    words+=base[___STILL_LENGTH];
    if (!___arg1 && base+___STILL_BODY==___BODY0(domain_children[i])) child_found++;
  }
  if (words!=vm->gc_participants[i].context->mem.words_still_objs_ ||
      vm->gc_participants[i].context->mem.words_still_objs_deferred_!=0 ||
      (!___arg1 && (child_found!=1 || atomic_load(&domain_child_releases[i])!=0)) ||
      (___arg1 && atomic_load(&domain_child_releases[i])!=1)) ___return(0);
}
___return(1);
c-end
))
(define note-entry (c-lambda () void "atomic_fetch_add(&domain_entries,1);"))
(define entries (c-lambda () int "___return(atomic_load(&domain_entries));"))
(define released? (c-lambda () bool "___return(atomic_load(&domain_released)==3 && atomic_load(&domain_bad)==0 && atomic_load(&domain_releases[0])==1 && atomic_load(&domain_releases[1])==1 && atomic_load(&domain_releases[2])==1);"))
(define workers!
  (c-lambda (int) void #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
___WORD old=___gc_atomic_load(&vm->gc_round.requested_workers);
while (___gc_cas(&vm->gc_round.requested_workers,old,___arg1)!=old)
  old=___gc_atomic_load(&vm->gc_round.requested_workers);
c-end
))
(define coherent?
  (c-lambda (int) bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
if (vm->processor_count!=3 || vm->gc_round.participant_count!=3 ||
    vm->gc_round.worker_count!=___arg1) ___return(0);
for (int i=0;i<3;i++) {
  ___gc_participant *p=&vm->gc_participants[i];
  int rank=(i+1)%3;
  if (p->phase!=___GC_RUNNING || p->resume.epoch!=vm->gc_round.epoch ||
      !p->resume.accepted || !p->resume.restored ||
      p->resume.source_worker!=(rank<___arg1 ? rank : -1) ||
      vm->gc_root_tasks[i].phase!=___GC_ROOT_CLEANUP ||
      vm->gc_root_tasks[i].claim!=2 || vm->gc_origins[i].state!=0)
    ___return(0);
  ___collector_worker *w=___PSTATE_FROM_PROCESSOR_ID(i,vm)->collector;
  if (w->phase!=___GC_WORKER_IDLE || w->id!=rank) ___return(0);
  if (rank<___arg1) {
    if (!w->arena.handed_off || w->arena.epoch!=vm->gc_round.epoch ||
        w->reserve!=&p->resume || w->arena.pending || w->tail_cell_ || w->copy_begin_ ||
        w->copy_request.state || w->copied_words>w->copied_source_words)
      ___return(0);
  } else if (w->reserve!=0) ___return(0);
}
___return(1);
c-end
))
(define roots (map (lambda (i) (let ((v (vector i #f))) (vector-set! v 1 v) v)) '(0 1 2)))
(define (request)
  (let ((payload (vector 314159)))
    (##current-vm-resize-ready
     (lambda ()
       (declare (not interrupts-enabled))
       (if (not (= (vector-ref payload 0) 314159)) (error "entry root lost"))
       (if (not (record! (let ((v (vector 271828 #f))) (vector-set! v 1 v) v))) (error "foreign construction failed"))
       (note-entry)
       (##startup-processor!)) 3)))
(if (not (= (##current-vm-processor-count) 1)) (error "requires managed initial owner"))
(workers! 1)
(if (not (record! (let ((v (vector 271828 #f))) (vector-set! v 1 v) v))) (error "main foreign construction failed"))
(if (not (= (request) 0)) (error "three root domains not admitted"))
(if (not (= (entries) 2)) (error "startup completion missing"))
(drop!)
(define (check count)
  (workers! count) (##gc)
  (if (not (coherent? count)) (error "root/worker/host completion incomplete" count))
  (for-each (lambda (v) (if (not (eq? v (vector-ref v 1))) (error "shared root lost"))) roots))
(check 1)
(if (not (released?)) (error "owner-affine cleanup not exactly once"))
(if (not (cleanup-closed? #f)) (error "fresh cleanup generation lost or not accounted"))
(drop-children!)
(check 2)
(if (not (cleanup-closed? #t)) (error "derived finalizers lost or repeated"))
(check 3) (check 1)
(define saved #f) (define exit #f) (define winds '())
(define (collect thunk) (call/cc (lambda (k) (set! exit k) (thunk))))
(define first
  (collect (lambda ()
    (exit (dynamic-wind
      (lambda () (set! winds (cons 'before winds)))
      (lambda () (map (lambda (x)
        (if (= x 2) (call/cc (lambda (k) (set! saved k) (check 1) 2))
            (begin (check 1) x))) '(1 2 3)))
      (lambda () (set! winds (cons 'after winds))))))))
(define second (collect (lambda () (saved 20))))
(define third (collect (lambda () (saved 200))))
(if (not (and (equal? first '(1 2 3)) (equal? second '(1 20 3))
              (equal? third '(1 200 3))
              (equal? winds '(after before after before after before))
              (released?))) (error "multi-shot domain restoration changed semantics"))
(check 1)
(if (not (rc-check?)) (error "RC borrowed roots lost or closure admitted writer"))
(rc-drop!)
(c-define (callback value text depth) (scheme-object char-string int)
  scheme-object "gambit_smp_gc_root_domains_callback" ""
  (##gc)
  (if (not (= (string-length text) 65536)) (error "converted argument lost"))
  (if (> depth 0) (callback! value (- depth 1)) value))
(define callback!
  (c-lambda (scheme-object int) scheme-object #<<c-end
static char payload[65537];
memset(payload,'x',65536); payload[65536]=0;
___return(gambit_smp_gc_root_domains_callback(___arg1,payload,___arg2));
c-end
))
(define callback-value (let ((v (vector 271828 #f))) (vector-set! v 1 v) v))
(if (not (eq? (callback! callback-value 1) callback-value))
    (error "nested SFUN lost reloaded argument"))
(c-define (callback-count value) (scheme-object) int
  "gambit_smp_gc_root_domains_count" "" (##gc) (vector-length value))
(c-define (callback-void value) (scheme-object) void
  "gambit_smp_gc_root_domains_void" "" (##gc) (vector-set! value 0 161803))
(define callback-count!
  (c-lambda (scheme-object) int "___return(gambit_smp_gc_root_domains_count(___arg1));"))
(define callback-void!
  (c-lambda (scheme-object) void "gambit_smp_gc_root_domains_void(___arg1);"))
(define scopes-drained?
  (c-lambda () bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
for(int i=0;i<3;i++) if(vm->execution_contexts[i].mem.rc_root_borrows_) ___return(0);
___return(1);
c-end
))
(if (not (= (callback-count! callback-value) 2)) (error "SFUN result conversion lost value"))
(callback-void! callback-value)
(if (not (and (= (vector-ref callback-value 0) 161803) (scopes-drained?)))
    (error "SFUN void exit lost effect or retained known scope"))
(display "WORKER-ROOT-DOMAINS-PASS roots=3 workers=1,2,3,1 cleanup=3\n")
