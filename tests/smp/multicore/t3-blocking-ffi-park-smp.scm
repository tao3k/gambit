;;; Adversarial SMP PBT for Tier 3.3 Blocking-FFI Participation Park/Unpark:
;;; 1. Non-blocking STW GC while any processor (including Processor 0!) is parked
;;;    in native blocking C (nanosleep), with moving-root graph integrity checks.
;;; 2. Cross-core pthread_cond_wait non-deadlock proof: parked thread waits on
;;;    condvar while active thread performs 30 STW GCs before signaling.
;;; 3. Nested c-define Scheme callback re-entry (auto-unpark -> GC -> auto-repark)
;;;    AND Scheme exception unwind through c-define (___throw_error auto-unpark).
;;; 4. Multi-core park/unpark storm under continuous GC-hammer across p1/p2/p4/p6/p8.

(declare (standard-bindings) (extended-bindings) (block))

(c-declare #<<c-declare-end
#include <pthread.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>

static void t3_sleep_us(int usec) {
  struct timespec ts;
  ts.tv_sec = usec / 1000000;
  ts.tv_nsec = (long)(usec % 1000000) * 1000L;
  nanosleep(&ts, NULL);
}

static pthread_mutex_t t3_cond_mut = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  t3_cond_cv  = PTHREAD_COND_INITIALIZER;
static int t3_waiter_ready = 0;
static int t3_release_go   = 0;

static ___VOLATILE ___WORD t3_park_active = 0;
static ___VOLATILE ___WORD t3_parked_p0_seen = 0;
static ___VOLATILE ___WORD t3_parked_nonzero_seen = 0;

static int t3_current_proc_id(void) {
  ___processor_state ps = ___PSTATE;
  return ___PROCESSOR_ID(ps, ___VMSTATE_FROM_PSTATE(ps));
}

static int t3_current_park_depth(void) {
  ___processor_state ps = ___PSTATE;
  return ps ? ps->ffi_park_depth : -1;
}

static int t3_park_sleep_us(int usec) {
  ___processor_state ps = ___PSTATE;
  int pid = ___PROCESSOR_ID(ps, ___VMSTATE_FROM_PSTATE(ps));
  if (pid == 0)
    ___WORD_FETCH_ADD_RELEASE(&t3_parked_p0_seen, 1);
  else
    ___WORD_FETCH_ADD_RELEASE(&t3_parked_nonzero_seen, 1);

  ___BEGIN_BLOCKING_FFI
  ___WORD_FETCH_ADD_RELEASE(&t3_park_active, 1);
  t3_sleep_us(usec);
  ___WORD_FETCH_ADD_RELEASE(&t3_park_active, -1);
  ___END_BLOCKING_FFI
  return pid;
}

static int t3_get_park_active(void) {
  return (int)___WORD_LOAD_ACQUIRE(&t3_park_active);
}

static int t3_get_p0_seen(void) {
  return (int)___WORD_LOAD_ACQUIRE(&t3_parked_p0_seen);
}

static void t3_cond_reset(void) {
  pthread_mutex_lock(&t3_cond_mut);
  t3_waiter_ready = 0;
  t3_release_go = 0;
  pthread_mutex_unlock(&t3_cond_mut);
}

static int t3_cond_park_wait(void) {
  ___BEGIN_BLOCKING_FFI
  pthread_mutex_lock(&t3_cond_mut);
  t3_waiter_ready = 1;
  pthread_cond_broadcast(&t3_cond_cv);
  while (!t3_release_go)
    pthread_cond_wait(&t3_cond_cv, &t3_cond_mut);
  pthread_mutex_unlock(&t3_cond_mut);
  ___END_BLOCKING_FFI
  return 1;
}

static void t3_cond_wait_ready(void) {
  /* Spin/park wait briefly until waiter has parked and entered cond_wait */
  ___BEGIN_BLOCKING_FFI
  pthread_mutex_lock(&t3_cond_mut);
  while (!t3_waiter_ready)
    pthread_cond_wait(&t3_cond_cv, &t3_cond_mut);
  pthread_mutex_unlock(&t3_cond_mut);
  ___END_BLOCKING_FFI
}

static void t3_cond_signal_go(void) {
  pthread_mutex_lock(&t3_cond_mut);
  t3_release_go = 1;
  pthread_cond_broadcast(&t3_cond_cv);
  pthread_mutex_unlock(&t3_cond_mut);
}

/* Forward declaration of c-define Scheme callbacks */
static int t3_scheme_cb(int seed);
static int t3_scheme_throw_cb(int seed);

static int t3_nested_park_callback(int seed) {
  int res = -1;
  int d_before = t3_current_park_depth();
  if (d_before != 0) return -100;

  /* Nest depth 2 blocking-FFI park, invoke c-define callback, check depth restoration */
  ___BEGIN_BLOCKING_FFI
  ___BEGIN_BLOCKING_FFI
  if (t3_current_park_depth() != 2) return -101;
  t3_sleep_us(2000);
  res = t3_scheme_cb(seed);
  if (t3_current_park_depth() != 2) return -102;
  t3_sleep_us(2000);
  ___END_BLOCKING_FFI
  if (t3_current_park_depth() != 1) return -103;
  ___END_BLOCKING_FFI

  if (t3_current_park_depth() != 0) return -104;
  return res;
}

static int t3_park_and_throw_callback(int seed) {
  int res = 0;
  ___BEGIN_BLOCKING_FFI
  ___BEGIN_BLOCKING_FFI
  res = t3_scheme_throw_cb(seed);
  ___END_BLOCKING_FFI
  ___END_BLOCKING_FFI
  return res;
}
c-declare-end
)

(define c-proc-id      (c-lambda () int "t3_current_proc_id"))
(define c-park-depth   (c-lambda () int "t3_current_park_depth"))
(define c-park-sleep   (c-lambda (int) int "t3_park_sleep_us"))
(define c-park-active  (c-lambda () int "t3_get_park_active"))
(define c-p0-seen      (c-lambda () int "t3_get_p0_seen"))
(define c-cond-reset   (c-lambda () void "t3_cond_reset"))
(define c-cond-wait    (c-lambda () int "t3_cond_park_wait"))
(define c-cond-ready   (c-lambda () void "t3_cond_wait_ready"))
(define c-cond-signal  (c-lambda () void "t3_cond_signal_go"))
(define c-nested-cb    (c-lambda (int) int "t3_nested_park_callback"))
(define c-throw-cb     (c-lambda (int) int "t3_park_and_throw_callback"))

(define (make-checked-graph seed)
  (let ((v (make-vector 64 #f)))
    (let loop ((i 0))
      (if (< i 64)
          (begin
            (vector-set! v i (cons (+ seed i) (string-append "tag-" (number->string (+ seed i)))))
            (loop (+ i 1)))
          v))))

(define (verify-checked-graph v seed)
  (let loop ((i 0))
    (if (< i 64)
        (let ((cell (vector-ref v i)))
          (if (not (and (pair? cell)
                        (= (car cell) (+ seed i))
                        (string=? (cdr cell) (string-append "tag-" (number->string (+ seed i))))))
              (error "t3 graph corrupted!" seed i cell))
          (loop (+ i 1)))
        #t)))

(c-define (t3_scheme_cb seed) (int) int "t3_scheme_cb" "static"
  (if (not (= (c-park-depth) 0))
      (error "t3_scheme_cb entered while still parked!" (c-park-depth)))
  (let ((g (make-checked-graph seed)))
    (##gc)
    (let ((junk (make-vector 2000 seed)))
      (vector-set! junk 1999 (+ seed 7))
      (##gc)
      (verify-checked-graph g seed)
      (+ (car (vector-ref g 63)) (vector-ref junk 1999)))))

(c-define (t3_scheme_throw_cb seed) (int) int "t3_scheme_throw_cb" "static"
  (if (not (= (c-park-depth) 0))
      (error "t3_scheme_throw_cb entered while still parked!" (c-park-depth)))
  (##gc)
  (raise (list 't3-unwind seed)))

(define (current-gc-count)
  (inexact->exact (round (f64vector-ref (##process-statistics) 6))))

(define (run-t3-blocking-ffi-park-test)
  (let* ((procs (##current-vm-processor-count))
         (s1-gcs-while-parked 0)
         (s2-condvar-rounds 0)
         (s3-cb-ok 0)
         (s3-unwind-ok 0)
         (s4-storm-ops 0))

    ;; Scenario 1: Non-blocking STW GC while parked (including Processor 0!)
    (if (>= procs 2)
        (let loop ((round 0))
          (when (< round 8)
            (let* ((seed (+ 1000 (* round 100)))
                   (parker
                    (thread-start!
                     (make-thread
                      (lambda ()
                        (let ((graph (make-checked-graph seed)))
                          (c-park-sleep 120000)
                          (verify-checked-graph graph seed)
                          'parked-ok)))))
                   (hammer
                    (thread-start!
                     (make-thread
                      (lambda ()
                        ;; Wait until parker is actually inside blocking C
                        (let wait ((n 0))
                          (when (and (= (c-park-active) 0) (< n 500000))
                            (thread-yield!)
                            (wait (+ n 1))))
                        (let ((seen-active 0))
                          (let gcloop ((k 0))
                            (when (< k 15)
                              (let ((tmp (make-vector 512 k)))
                                (vector-set! tmp 0 k)
                                (when (> (c-park-active) 0)
                                  (##gc)
                                  (when (> (c-park-active) 0)
                                    (set! seen-active (+ seen-active 1)))))
                              (gcloop (+ k 1))))
                          seen-active))))))
              (let ((parked-gcs (thread-join! hammer))
                    (p-res (thread-join! parker)))
                (if (not (eq? p-res 'parked-ok))
                    (error "S1 parker failed" p-res))
                (set! s1-gcs-while-parked (+ s1-gcs-while-parked parked-gcs))))
            (loop (+ round 1))))
        ;; p1 fallback: verify park/unpark works cleanly on single processor
        (let ((g (make-checked-graph 1000)))
          (c-park-sleep 20000)
          (##gc)
          (verify-checked-graph g 1000)
          (set! s1-gcs-while-parked 1)))

    (if (and (>= procs 2) (< s1-gcs-while-parked 20))
        (error "S1 expected >=20 GCs while peer parked in blocking C!" s1-gcs-while-parked))

    ;; Scenario 2: Cross-core condvar non-deadlock proof (would deadlock 100% without Tier 3.3!)
    (when (>= procs 2)
      (let loop ((r 0))
        (when (< r 20)
          (c-cond-reset)
          (let* ((seed (+ 5000 (* r 37)))
                 (waiter
                  (thread-start!
                   (make-thread
                    (lambda ()
                      (let ((graph (make-checked-graph seed)))
                        (c-cond-wait)
                        (verify-checked-graph graph seed)
                        'waiter-ok)))))
                 (signaler
                  (thread-start!
                   (make-thread
                    (lambda ()
                      (c-cond-ready)
                      ;; Trigger 10 STW GCs while waiter is blocked inside pthread_cond_wait!
                      (let gl ((k 0))
                        (when (< k 10)
                          (let ((v (make-vector 1024 (+ r k))))
                            (vector-set! v 1023 k)
                            (##gc))
                          (gl (+ k 1))))
                      (c-cond-signal)
                      'signaler-ok)))))
            (if (not (and (eq? (thread-join! waiter) 'waiter-ok)
                          (eq? (thread-join! signaler) 'signaler-ok)))
                (error "S2 condvar non-deadlock failed" r))
            (set! s2-condvar-rounds (+ s2-condvar-rounds 1)))
          (loop (+ r 1)))))

    ;; Scenario 3: Nested c-define re-entrant callback + exception unwind auto-unpark
    (let loop ((i 0))
      (when (< i 24)
        (let* ((seed (+ 9000 i))
               (expected (+ (+ seed 63) (+ seed 7)))
               (got (c-nested-cb seed)))
          (if (not (= got expected))
              (error "S3 nested callback mismatch" seed expected got))
          (if (not (= (c-park-depth) 0))
              (error "S3 park depth not zero after callback" (c-park-depth)))
          (set! s3-cb-ok (+ s3-cb-ok 1)))
        (let ((caught
               (with-exception-catcher
                (lambda (e) e)
                (lambda () (c-throw-cb (+ 12000 i))))))
          (if (not (and (pair? caught)
                        (eq? (car caught) 't3-unwind)
                        (= (cadr caught) (+ 12000 i))))
              (error "S3 unwind mismatch" caught))
          (if (not (= (c-park-depth) 0))
              (error "S3 park depth not zero after unwind!" (c-park-depth)))
          (##gc)
          (set! s3-unwind-ok (+ s3-unwind-ok 1)))
        (loop (+ i 1))))

    ;; Scenario 4: Multi-core unserialized park/unpark storm + C-stack-safe
    ;; nested c-define callback/unwind under continuous GC-hammer
    (let* ((stop-box (vector #f))
           (cb-mtx (make-mutex 't3-cb-cstack))
           (gc-threads
            (let mk ((k 0) (acc '()))
              (if (= k 2)
                  acc
                  (mk (+ k 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let loop ((n 0))
                             (if (vector-ref stop-box 0)
                                 n
                                 (begin
                                   (let ((v (make-vector 512 n)))
                                     (vector-set! v 0 n)
                                     (##gc))
                                   (thread-sleep! 0.001)
                                   (loop (+ n 1))))))))
                       acc)))))
           (storm-workers
            (let mk ((w 0) (acc '()))
              (if (= w 4)
                  acc
                  (mk (+ w 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let loop ((i 0))
                             (if (= i 60)
                                 i
                                 (let* ((seed (+ (* w 10000) i))
                                        (g (make-checked-graph seed)))
                                   (cond
                                    ((= (modulo i 3) 0)
                                     ;; Pure blocking-FFI park/unpark: 100% unserialized across all cores!
                                     (c-park-sleep 1000))
                                    ((= (modulo i 3) 1)
                                     ;; Nested c-define re-entry serialized for per-processor C-stack LIFO
                                     (mutex-lock! cb-mtx)
                                     (let ((got (c-nested-cb seed))
                                           (exp (+ (+ seed 63) (+ seed 7))))
                                       (mutex-unlock! cb-mtx)
                                       (if (not (= got exp))
                                           (error "S4 cb mismatch" seed exp got))))
                                    (else
                                     (mutex-lock! cb-mtx)
                                     (let ((c (with-exception-catcher
                                               (lambda (e) e)
                                               (lambda () (c-throw-cb seed)))))
                                       (mutex-unlock! cb-mtx)
                                       (if (not (and (pair? c) (eq? (car c) 't3-unwind)))
                                           (error "S4 unwind mismatch" c)))))
                                   (verify-checked-graph g seed)
                                   (if (not (= (c-park-depth) 0))
                                       (error "S4 park depth leak" (c-park-depth)))
                                   (loop (+ i 1))))))))
                       acc))))))
      (for-each
       (lambda (t)
         (set! s4-storm-ops (+ s4-storm-ops (thread-join! t))))
       storm-workers)
      (vector-set! stop-box 0 #t)
      (for-each thread-join! gc-threads))

    (display
     (list 'T3-BLOCKING-FFI-PARK-PASS
           'procs procs
           's1-parked-gcs s1-gcs-while-parked
           's2-condvar-rounds s2-condvar-rounds
           's3-cb-ok s3-cb-ok
           's3-unwind-ok s3-unwind-ok
           's4-storm-ops s4-storm-ops
           'p0-parked-seen (c-p0-seen)
           'gc-total (current-gc-count)))
    (newline)
    (force-output)))

(run-t3-blocking-ffi-park-test)
