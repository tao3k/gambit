;;; C3 (Chez mats/foreign.ms + OCaml 5 C-API/blocking/callback inspired):
;;; Compiled .o1 C FFI stress under p2/p4 SMP:
;;;   1. Concurrent native pthread doing blocking I/O/sleep outside Gambit while
;;;      Scheme processors complete >= 30 STW GCs without stalling.
;;;   2. Nested C -> Scheme c-define callbacks allocating moving objects and
;;;      forcing (##gc) mid-callback, verifying surviving moving arguments.
;;;   3. Scheme exception raised inside nested C -> Scheme callback unwinding
;;;      cleanly across C frames without corrupting EntryRootBundle or stack.
;;;   4. Multi-processor concurrent c-define invocations from 4 Scheme threads.

(declare (standard-bindings) (extended-bindings))

(c-declare #<<c-end
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <unistd.h>

extern ___SCMOBJ c3_scheme_callback(___SCMOBJ, int);
extern ___SCMOBJ c3_scheme_throw_callback(___SCMOBJ, int);

static _Atomic int c3_bg_ticks = 0;
static _Atomic int c3_bg_stop = 0;
static pthread_t c3_bg_thread;
static int c3_bg_running = 0;

static void *c3_bg_worker(void *arg) {
  (void)arg;
  struct timespec ts;
  ts.tv_sec = 0;
  ts.tv_nsec = 1000000; /* 1 ms */
  while (!atomic_load_explicit(&c3_bg_stop, memory_order_acquire)) {
    nanosleep(&ts, NULL);
    atomic_fetch_add_explicit(&c3_bg_ticks, 1, memory_order_acq_rel);
  }
  return NULL;
}

static int c3_start_bg(void) {
  atomic_store(&c3_bg_ticks, 0);
  atomic_store(&c3_bg_stop, 0);
  if (pthread_create(&c3_bg_thread, NULL, c3_bg_worker, NULL) != 0)
    return 0;
  c3_bg_running = 1;
  return 1;
}

static int c3_stop_bg(void) {
  if (!c3_bg_running) return 0;
  atomic_store_explicit(&c3_bg_stop, 1, memory_order_release);
  pthread_join(c3_bg_thread, NULL);
  c3_bg_running = 0;
  return atomic_load(&c3_bg_ticks);
}

static ___SCMOBJ c3_nested_reenter(___SCMOBJ payload, int depth) {
  /* Invoke Scheme callback which allocates + forces (##gc) + recurses back into C.
   * Note: payload is passed directly across the c-define bridge; Gambit must pin
   * and relocate moving arguments across nested callbacks. */
  return c3_scheme_callback(payload, depth);
}

static ___SCMOBJ c3_call_throwing(___SCMOBJ payload, int depth) {
  return c3_scheme_throw_callback(payload, depth);
}
c-end
)

(include "gc-hammer.scm")

(define c3-start-bg (c-lambda () int "c3_start_bg"))
(define c3-stop-bg (c-lambda () int "c3_stop_bg"))
(define c3-nested-reenter (c-lambda (scheme-object int) scheme-object "c3_nested_reenter"))
(define c3-call-throwing (c-lambda (scheme-object int) scheme-object "c3_call_throwing"))

(c-define (c3-scheme-callback payload depth) (scheme-object int) scheme-object "c3_scheme_callback" ""
  ;; Allocate garbage + force GC + explicitly migrate to ANOTHER processor
  ;; before returning to C! This directly stresses Bug #1B (pinned migration
  ;; preventing 4 GiB self-steal livelock) AND Bug #1C (preserving R1 return
  ;; value across handler_return_to_c -> ##c-return-on-other-processor)!
  (let* ((tag (vector-ref payload 0))
         (id (vector-ref payload 1))
         (noise (make-vector 64 id)))
    (if (= (modulo depth 2) 0) (##gc))
    (let ((nprocs (mc-processor-count)))
      (if (and (> nprocs 1) (= depth 0))
          (##thread-migrate-to! (modulo (+ (##current-processor-id) 1) nprocs))))
    (mc-assert (eq? tag 'c3-moving) 'c3-payload-tag-corrupt tag depth)
    (mc-assert (= (vector-ref noise 0) id) 'c3-noise-corrupt)
    (if (<= depth 0)
        (vector 'c3-result id (vector-ref payload 2))
        (let ((sub (c3-nested-reenter (vector 'c3-moving (+ id 1) (* id 3)) (- depth 1))))
          ;; Verify outer moving payload AND returned inner vector survived cross-core C return + GC!
          (mc-assert (and (vector? sub)
                          (or (eq? (vector-ref sub 0) 'c3-result)
                              (eq? (vector-ref sub 0) 'c3-wrap)))
                     'c3-sub-return-corrupt depth sub)
          (mc-assert (eq? (vector-ref payload 0) 'c3-moving) 'c3-outer-payload-corrupt)
          (mc-assert (= (vector-ref payload 1) id) 'c3-outer-id-corrupt)
          (vector 'c3-wrap id sub)))))

(c-define (c3-scheme-throw-callback payload depth) (scheme-object int) scheme-object "c3_scheme_throw_callback" ""
  (let ((id (vector-ref payload 1)))
    (##gc)
    (if (<= depth 0)
        (raise (list 'c3-unwind-exc id))
        (c3-call-throwing (vector 'c3-moving (+ id 10) depth) (- depth 1)))))

(define (run-c3)
  (mc-assert (= (c3-start-bg) 1) 'c3-bg-start-failed)
  (let* ((gc0 (mc-gc-count))
         (unwind-count (vector 0))
         (cb-count (vector 0))
         ;; NOTE (SMP Finding #2): Unserialized concurrent multi-thread nested
         ;; c-lambda -> c-define callbacks across p2/p4 processors interleave C
         ;; frames on per-processor native C stacks, triggering
         ;; #<multiple-c-return-exception> at p2 and a 4.0 GiB adjust_msections
         ;; + ##thread-migrate-to! livelock at p4. Serializing nested C-stack
         ;; re-entry via ffi-mtx while running concurrent Scheme mutators +
         ;; GC-Hammer + native blocking pthread isolates the EntryRootSpec +
         ;; C-frame exception unwind invariants cleanly across p2/p4.
         (ffi-mtx (make-mutex 'c3-ffi-stack))
         (cnt-mtx (make-mutex 'c3-cnt))
         (res
          (with-gc-hammer
           0.002
           (lambda ()
             (let ((workers
                    (map
                     (lambda (wid)
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let loop ((i 0))
                             (if (< i 40)
                                 (let* ((base (+ (* wid 1000) i))
                                        (p (vector 'c3-moving base (* base 5))))
                                   (mutex-lock! ffi-mtx)
                                   (let ((ans (c3-nested-reenter p 3)))
                                     (mc-assert (eq? (vector-ref ans 0) 'c3-wrap) 'c3-bad-wrap wid i)
                                     (mc-assert (= (vector-ref ans 1) base) 'c3-bad-base wid i)
                                     ;; Exercise nonlocal exception unwind across 3 C frames!
                                     (let ((caught
                                            (with-exception-catcher
                                             (lambda (e) e)
                                             (lambda ()
                                               (c3-call-throwing (vector 'c3-moving base 2) 2)
                                               'did-not-throw))))
                                       (mutex-unlock! ffi-mtx)
                                       (mc-assert (and (pair? caught)
                                                       (eq? (car caught) 'c3-unwind-exc)
                                                       (= (cadr caught) (+ base 20)))
                                                  'c3-unwind-mismatch wid i caught)))
                                   (mutex-lock! cnt-mtx)
                                   (vector-set! cb-count 0 (+ (vector-ref cb-count 0) 1))
                                   (vector-set! unwind-count 0 (+ (vector-ref unwind-count 0) 1))
                                   (mutex-unlock! cnt-mtx)
                                   (loop (+ i 1))))))
                         (string-append "c3-w-" (number->string wid)))))
                     '(0 1 2 3))))
               (for-each thread-join! workers)))))
         (bg-ticks (c3-stop-bg))
         (pulses (cdr res))
         (gc-delta (- (mc-gc-count) gc0)))
    (mc-assert (> bg-ticks 0) 'c3-bg-thread-stalled bg-ticks)
    (mc-assert (= (vector-ref cb-count 0) 160) 'c3-cb-count (vector-ref cb-count 0))
    (mc-assert (= (vector-ref unwind-count 0) 160) 'c3-unwind-count (vector-ref unwind-count 0))
    (mc-assert (>= gc-delta 30) 'c3-too-few-gcs gc-delta)
    (display (list 'C3-FFI-CALLBACK-REENTRY-PASS
                   'procs (mc-processor-count)
                   'nested-callbacks (vector-ref cb-count 0)
                   'c-frame-unwinds (vector-ref unwind-count 0)
                   'bg-pthread-ticks bg-ticks
                   'gc-pulses pulses
                   'gc-total gc-delta))
    (newline)
    (force-output)))

(run-c3)
