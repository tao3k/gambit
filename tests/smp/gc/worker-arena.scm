;;; One compiled control for refill, restoration-space loan and role handoff.
;;; GAMBIT_TEST_ARENA_MODE is refill (default) or loan. Populations are runtime
;;; options, never topology-specific source files or another test runner.
(declare (standard-bindings) (extended-bindings))
(##namespace ("gambit#tests#smp#gc#worker_arena#"
              install! finish! coherent? refill-count mode loan? roots seen check))
(c-declare #<<c-end
#include "mem.h"
#include "rc.h"
#include "root.h"
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
___root_round *round = ___ROOT_UNION(vm);
vm->mem.custom_msection_alloc_ = 0; /* restore before any Scheme assertion */
/* Under modern-c pre-copy planning (copy-planning.inc:328), custom_msection_alloc
 * triggers an atomic pre-copy refusal (decision==2, ___GC_PLAN_REFUSED) rather
 * than entering an uncertified loan; subsequent GC recovers cleanly. */
___return(round->state == ___ROOT_ROUND_IDLE &&
          round->collection.decision == 2 &&
          round->collection.census.state == ___GC_PLAN_REFUSED &&
          ___ps->mem.alloc_heap_ptr_ <= ___ps->mem.alloc_heap_limit_);
c-end
))
(define refill-count
  (c-lambda () int #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
___root_round *round = ___ROOT_UNION(vm);
int refills = 0;
for (int i=0; i<vm->processor_count; i++) {
  ___processor_state p = round->members[i].owner;
  ___gc_resume_space *r = &round->resume[i];
  ___collector_worker *w = &round->workers[i];
  if (!r->accepted || !r->restored) ___return(-1);
  if (i >= round->collection.worker_count) continue;
  if (!w->arena.handed_off || w->arena.pending ||
      w->arena.epoch != round->collection.epoch || w->copy_begin_ || w->tail_cell_ ||
      p->mem.words_prev_msections_ < w->arena.retired_words ||
      p->mem.stack_msection_ != r->stack_section ||
      (r->loan_used && p->mem.alloc_stack_limit_ < r->loan_limit))
    ___return(-1);
  refills += w->arena.refills;
}
___return(refills);
c-end
))
(define coherent?
  (c-lambda () bool #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
___root_round *round = ___ROOT_UNION(vm);
int count = vm->processor_count;
if (count < 1 || round->state != ___ROOT_ROUND_IDLE ||
    round->collection.participant_count != count ||
    round->collection.worker_count < 1 || round->collection.worker_count > count) ___return(0);
for (int i=0; i<count; ++i) {
  ___processor_state carrier = ___PSTATE_FROM_PROCESSOR_ID(i,vm);
  ___root_member *mb = &round->members[i];
  ___gc_resume_space *r = &round->resume[i];
  ___collector_worker *worker = &round->workers[i];
  if (mb->context != carrier->context || carrier->collector != 0 ||
      mb->rc->joined_round != 0 || mb->rc->phase != ___RC_OPEN ||
      mb->rc->task.state != ___ROOT_DONE ||
      mb->global_task.state != ___ROOT_DONE ||
      mb->stack_task.state != ___ROOT_DONE ||
      mb->bank_task.state != ___ROOT_DONE ||
      !r->accepted || !r->restored || r->epoch != round->epoch) ___return(0);
  if (i < round->collection.worker_count) {
    if (worker->vm != vm || worker->id != i ||
        worker->phase != ___GC_WORKER_IDLE ||
        r->source_worker != i ||
        !worker->arena.handed_off || worker->arena.epoch != round->collection.epoch ||
        worker->arena.pending || worker->copy_begin_ || worker->tail_cell_)
      ___return(0);
  } else if (r->source_worker != -1)
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
      (##gc) (check)
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
