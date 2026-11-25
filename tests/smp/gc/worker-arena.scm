;;; One compiled control for refill, restoration-space loan and role handoff.
;;; GAMBIT_TEST_ARENA_MODE is refill (default) or loan. Populations are runtime
;;; options, never topology-specific source files or another test runner.
(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#worker_arena#"
              install! finish! coherent? refill-count mode loan? roots seen check))
(c-declare #<<c-end
/* Existing allocator test hook: deny NEW section refill for this one GC.
 * Reserved destination and restoration sections are unchanged. */
static ___msection *worker_arena_no_section(void) { return 0; }
c-end
)
(define install!
  (c-lambda () bool #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
if (vm->processor_count != 1 || vm->mem.custom_msection_alloc_ != 0)
  ___return(0);
vm->mem.custom_msection_alloc_ = worker_arena_no_section;
___return(1);
c-end
))
(define finish!
  (c-lambda () bool #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
___collector_worker *w = ___ps->collector;
___gc_resume_space *r = &vm->gc_participants[0].resume;
___context_mem *m = &___ps->context->mem;
vm->mem.custom_msection_alloc_ = 0; /* restore before any Scheme assertion */
___return(r->loan_used && r->accepted && w->arena.refills == 1 &&
          w->arena.handed_off && !w->arena.pending &&
          m->heap_msection_ == r->stack_section &&
          m->stack_msection_ == r->stack_section &&
          m->alloc_heap_limit_+2 == r->loan_limit &&
          m->alloc_stack_limit_ == r->loan_limit &&
          m->alloc_heap_ptr_ <= m->alloc_heap_limit_ &&
          m->alloc_stack_ptr_ >= r->stack_floor &&
          m->words_prev_msections_ == w->arena.retired_words);
c-end
))
(define refill-count
  (c-lambda () int #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
int refills = 0;
for (int i=0; i<vm->processor_count; i++) {
  ___gc_participant *p = &vm->gc_participants[i];
  ___collector_worker *w = ___PSTATE_FROM_PROCESSOR_ID(i,vm)->collector;
  ___context_mem *m = &p->context->mem;
  if (!p->resume.accepted || !p->resume.restored) ___return(-1);
  if (w->id >= vm->gc_round.worker_count) continue;
  if (!w->arena.handed_off || w->arena.pending ||
      w->arena.epoch != vm->gc_round.epoch || w->copy_begin_ || w->tail_cell_ ||
      m->words_prev_msections_ < w->arena.retired_words ||
      m->stack_msection_ != p->resume.stack_section ||
      (p->resume.loan_used && m->alloc_stack_limit_ < p->resume.loan_limit))
    ___return(-1);
  refills += w->arena.refills;
}
___return(refills);
c-end
))
(define coherent?
  (c-lambda () bool #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
int count = vm->processor_count;
unsigned char seen[___MAX_PROCESSORS] = {0};
if (count < 1 || vm->gc_round.participant_count != count ||
    vm->gc_round.worker_count < 1 || vm->gc_round.worker_count > count) ___return(0);
for (int i=0; i<count; ++i) {
  ___processor_state carrier = ___PSTATE_FROM_PROCESSOR_ID(i,vm);
  ___collector_worker *worker = carrier->collector;
  if (worker->vm != vm || worker->id < 0 || worker->id >= count || seen[worker->id] ||
      worker->phase != ___GC_WORKER_IDLE ||
      !vm->gc_participants[i].resume.accepted ||
      !vm->gc_participants[i].resume.restored ||
      vm->gc_participants[i].context != carrier->context ||
      vm->gc_participants[i].phase != ___GC_RUNNING ||
      vm->gc_origins[i].state != 0 ||
      vm->gc_root_tasks[i].phase != ___GC_ROOT_CLEANUP ||
      vm->gc_root_tasks[i].claim != 2) ___return(0);
  seen[worker->id] = 1;
  if (worker->id < vm->gc_round.worker_count) {
    if (worker->reserve != &vm->gc_participants[i].resume ||
        !worker->arena.handed_off || worker->arena.epoch != vm->gc_round.epoch ||
        worker->arena.pending || worker->copy_begin_ || worker->tail_cell_)
      ___return(0);
  } else if (worker->reserve != 0 || vm->gc_participants[i].resume.source_worker != -1)
    ___return(0);
}
___return(1);
c-end
))
(define mode (getenv "GAMBIT_TEST_ARENA_MODE" "refill"))
(if (not (member mode '("refill" "loan"))) (error "unknown arena scenario" mode))
(define loan? (string=? mode "loan"))
(define roots
  (let loop ((i (if loan? 9999 131071)) (r '()))
    (if (< i 0) r
        (loop (- i 1) (cons (vector i (cons i i)) r)))))
(define seen #f)
(define (check)
  (if (not (coherent?)) (error "worker/root/carrier authority conflated"))
  (for-each (lambda (v)
              (if (not (= (vector-ref v 0) (car (vector-ref v 1))))
                  (error "arena handoff lost a root"))) roots))
(if loan?
    (begin
      (if (not (install!)) (error "loan control requires unmodified one-member owner"))
      (##gc)
      ;; Remove the deny-refill hook before Scheme assertions/allocations.
      (if (not (finish!)) (error "copy and restoration intervals overlap or lost custody"))
      (check)
      (##gc) (check)
      (display "WORKER-ARENA-LOAN-PASS epochs=2\n"))
    (begin
      (let loop ((n 0))
        (if (< n 3)
            (begin
              (##gc) (check)
              (let ((count (refill-count)))
                (if (< count 0) (error "arena/resume custody lost"))
                (if (> count 0) (set! seen #t)))
              (loop (+ n 1)))))
      (if (not seen) (error "workload did not exercise physical worker refill"))
      (display "WORKER-ARENA-REFILL-PASS epochs=3\n")))
