;;; Scheduler continuation ownership: immediate decisions versus committed waits.
;;; One native Scheme fixture; no alternative scheduler or test runner.
(declare (standard-bindings) (extended-bindings))
(c-declare "#include \"mem.h\"\n#include \"rc.h\"\n/* Shared by Scheme carriers, entirely nonallocating while the ticket is held.\n * No copied lock implementation, extra native threads, or hidden GC roots. */\nstatic ___TICKETLOCK handoff_lock = ___TICKETLOCK_INIT_STATIC;\nstatic ___UWORD handoff_count, handoff_complement;\nstatic int handoff_bad;\nstatic void handoff_reset(void) {\n  ___TICKETLOCK_INIT(handoff_lock);\n  handoff_count=0;handoff_complement=~handoff_count;handoff_bad=0;\n}\nstatic void handoff_run(___processor_state ___ps,int rounds) {\n  int i;___WORD ___temp;\n  for(i=0;i<rounds;i++) {\n    if(i&1) { while(!___TICKETLOCK_TRYLOCK2(handoff_lock.next_ticket,handoff_lock.current_ticket,___temp)) ___CPU_RELAX(); }\n    else { ___TICKETLOCK_LOCK(handoff_lock); }\n    if(handoff_complement!=~handoff_count)handoff_bad=1;\n    handoff_count++;handoff_complement=~handoff_count;\n    ___TICKETLOCK_UNLOCK(handoff_lock);\n  }\n}\nstatic int handoff_check(___processor_state ___ps,int expected) {\n  int ok=!handoff_bad && handoff_count==(___UWORD)expected && handoff_complement==~handoff_count;\n  /* All carriers joined: exclusive construction is permitted; reuse is atomic. */\n  handoff_lock.next_ticket=handoff_lock.current_ticket=-___FIX(1);\n  ___TICKETLOCK_LOCK(handoff_lock);___TICKETLOCK_UNLOCK(handoff_lock);\n  return ok && ___WORD_LOAD_ACQUIRE(&handoff_lock.next_ticket)==0 && ___WORD_LOAD_ACQUIRE(&handoff_lock.current_ticket)==0;\n}\n")

(define (require value . context)
  (if (not value) (apply error "mutex suspension contract" context)))

(define (running-cont-empty?)
  (##declare (not interrupts-enabled))
  (##c-code "___RESULT = ___BOOLEAN(___CONTINUATION_FRAME_FIELD(___THREAD_CONT_FIELD(___CURRENTTHREAD)) == ___END_OF_CONT_MARKER);"))

(define (smp?)
  (##declare (not interrupts-enabled))
  (##c-code "
#ifdef ___SINGLE_THREADED_VMS
___RESULT = ___FAL;
#else
___RESULT = ___TRU;
#endif
"))

(define (smp-wait-case thunk)
  (if (smp?)
      (thunk)
      (display "WAIT-SMP-NOT-ADMITTED single-threaded build; original populations unchanged\n")))

(define (slow-lock mutex timeout owner)
  (##declare (not interrupts-enabled))
  ;; Only the SMP implementation has this three-argument private protocol.
  ;; The single-context build checks the same decisions through its public
  ;; interface; it does not qualify the SMP slow-path ownership change.
  (if (##c-code "
#ifdef ___SINGLE_THREADED_VMS
___RESULT = ___TRU;
#else
___RESULT = ___FAL;
#endif
")
      (mutex-lock! mutex timeout owner)
      (begin
        (##check-heap-limit)
        (##primitive-lock! mutex 1 9)
        (if owner (##primitive-lock! owner 1 9))
        (##mutex-lock-out-of-line! mutex timeout owner))))

(define (await-mutex thread mutex)
  (let loop ()
    (let ((state (thread-state thread)))
      (if (and (thread-state-waiting? state)
               (eq? (thread-state-waiting-for state) mutex))
          #t
          (begin (thread-yield!) (loop))))))

(define (fresh thunk) (thread-join! (thread-start! (make-thread thunk))))

(define (probe)
  (fresh
   (lambda ()
     (let* ((m (make-mutex))
            (before (running-cont-empty?))
            (answer (slow-lock m #f (current-thread)))
            (after (running-cont-empty?)))
       (mutex-unlock! m)
       (write (list 'MUTEX-SUSPENSION-PROBE before answer after)) (newline)
       (require (and before answer) 'probe-formed)))))

(define (immediate opcode)
  (fresh
   (lambda ()
     (let ((m (make-mutex)))
       (if (= opcode 2) (mutex-lock! m))
       (let* ((before (running-cont-empty?))
              (answer (slow-lock m (if (= opcode 2) 0 #f)
                                 (if (= opcode 1) #f (current-thread))))
              (after (running-cont-empty?)))
         (mutex-unlock! m)
         (##gc)
         (list before answer after))))))

(define (blocking)
  (let* ((m (make-mutex)) (count (vector 0)) (answer #f))
    (mutex-lock! m)
    (let ((target (thread-start!
                   (make-thread
                    (lambda ()
                      (set! answer (slow-lock m #f (current-thread)))
                      (mutex-unlock! m)
                      'completed)))))
      (await-mutex target m)
      (do ((n 0 (+ n 1))) ((= n 12))
        (require (= (thread-interrupt!
                     target
                     (lambda ()
                       (vector-set! count 0 (+ 1 (vector-ref count 0)))
                       (##gc)
                       (vector-ref count 0)))
                    (+ n 1)) 'interrupt-result n)
        (await-mutex target m))
      (mutex-unlock! m)
      (require (eq? (thread-join! target) 'completed) 'blocked-completion)
      (require (and answer (= (vector-ref count 0) 12)) 'blocked-result))))

;; A captured service continuation contains the waiting caller suffix, even
;; after the original physical thread has completed. Each restoration may wait
;; again on the current thread, without reviving the old queue registration.
(define (waiting-continuation #!optional (kind 'mutex))
  (let ((mutex (make-mutex)) (changed (make-condition-variable))
        (dependent #f) (started? #f)
        (saved #f) (back #f) (replay? #f)
        (enters 0) (exits 0) (completed 0)
        (parameter (make-parameter 'initial))
        (payload (vector (cons 'shared 'root))) (observed #f)
        (deadline (seconds->time (+ (time->seconds (current-time)) 1))))
    (define (await target)
      (let loop ()
        (let ((state (thread-state target)))
          (if (and started? (thread-state-waiting? state)
                   (if (eq? kind 'join)
                       (condition-variable? (thread-state-waiting-for state))
                       (eq? (thread-state-waiting-for state)
                            (case kind ((cv) changed) ((sleep) #f) (else mutex)))))
              #t
              (begin (thread-yield!) (loop))))))
    (if (memq kind '(mutex join)) (mutex-lock! mutex #f #f))
    (if (eq? kind 'join)
        (begin
          (set! dependent
                (thread-start!
                 (make-thread
                  (lambda ()
                    (mutex-lock! mutex #f #f)
                    (mutex-unlock! mutex)
                    payload))))
          (await-mutex dependent mutex)))
    (let ((target
           (thread-start!
            (make-thread
             (lambda ()
               (let ((answer
                      (dynamic-wind
                       (lambda () (set! enters (+ enters 1)))
                       (lambda ()
                         (set! started? #t)
                         (require
                          (case kind
                            ((mutex) (mutex-lock! mutex #f #f))
                            ((join) (eq? (thread-join! dependent) payload))
                            ((sleep) (thread-sleep! deadline) #t)
                            ((cv)
                             (mutex-lock! mutex #f #f)
                             (mutex-unlock! mutex changed)))
                          'logical-wait kind)
                         (require (running-cont-empty?) 'consumed-physical-root)
                         (if (eq? kind 'mutex) (mutex-unlock! mutex))
                         (require (equal? (vector-ref payload 0) '(shared . root))
                                  'waiting-root)
                         (set! completed (+ completed 1))
                         (parameter))
                       (lambda () (set! exits (+ exits 1))))))
                 (if replay? (back answer) answer)))))))
      (await target)
      (require
       (eq? (thread-interrupt!
             target
             (lambda ()
               (parameter 'service-update)
               (let ((value
                      (call/cc (lambda (k) (set! saved k) 'captured))))
                 (##gc)
                 value)))
            'captured)
       'captured-service kind)
      ;; CV interruption terminates this wait, with no signal credit. Resource
      ;; predicates (mutex/join) instead stay parked until actual completion.
      (if (not (eq? kind 'cv))
          (begin
            (await target)
            (do ((i 0 (+ i 1))) ((= i 4))
              (require (eq? (thread-interrupt! target
                             (lambda () (##gc) (parameter)))
                            'service-update)
                       'parameter-not-rewound)
              (await target))
            (if (memq kind '(mutex join)) (mutex-unlock! mutex))))
      (require (eq? (thread-join! target 5 'timeout) 'service-update)
               'initial-wait-return kind)
      (set! replay? #t)
      (do ((i 0 (+ i 1))) ((= i 3))
        (set! observed (call/cc (lambda (k) (set! back k) (saved 'late))))
        (require (eq? observed 'service-update) 'multi-shot-wait-return kind)
        (require (running-cont-empty?) 'current-physical-root)
        (##gc))
      (require (and (= enters 4) (= exits 4) (= completed 4))
               'wind-counts kind enters exits completed)
      (if (eq? kind 'mutex)
          (let* ((gate (make-mutex))
                 (worker (make-thread
                          (lambda ()
                            (let ((ok (mutex-lock! gate #f #f)))
                              (mutex-unlock! gate) ok)))))
            (mutex-lock! gate #f #f)
            (thread-start! worker)
            (await-mutex worker gate)
            (require (eq? (thread-interrupt! worker
                           (lambda () (mutex-unlock! gate) (##gc) 'released))
                          'released)
                     'release-during-service)
            (require (eq? (thread-join! worker 5 'timeout) #t)
                     'registration-rechecks-release)))
      (display (case kind
                 ((mutex) "MUTEX-WAIT-CONTINUATION-PASS")
                 ((join) "JOIN-WAIT-CONTINUATION-PASS")
                 ((sleep) "SLEEP-WAIT-CONTINUATION-PASS")
                 ((cv) "CV-WAIT-CONTINUATION-PASS")))
      (display " captures=1 restores=3 gc parameter dynamic-wind\n"))))

(define (waiting-io)
  (let* ((port (open-process
                (list path: (car (command-line))
                      arguments: '("-:p1" "--io-child")
                      stdin-redirection: #t stdout-redirection: #t)))
         (target (thread-start! (make-thread (lambda () (read-line port))))))
    (await-mutex target port)
    (require (eq? (thread-interrupt! target (lambda () (##gc) 'io-service))
                  'io-service)
             'blocked-io-service)
    (display "io-result\n" port)
    (force-output port)
    (require (equal? (thread-join! target 5 'timeout) "io-result")
             'io-post-wake-read)
    (require (= (process-status port) 0) 'io-child-exit)
    (close-port port)
    (display "IO-WAIT-SERVICE-PASS interrupt-abort post-check read child-reaped\n")))

;; Last-round counters, not RSS or a guessed continuation-allocation counter.
;; Restrict observation to one processor so another mutator cannot start a
;; collector round while this non-allocating native snapshot is read.
(define snapshot-wait-gc!
  (c-lambda (scheme-object) bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___PSTATE);
___root_round *round=___ROOT_UNION(vm);
___SIZE_TS values[8], copied=0, links=0;
int i;
___result=vm->processor_count==1 && round && round->state==___ROOT_ROUND_IDLE
 && round->collection.decision==1 && round->collection.census.state==___GC_PLAN_ACCEPTED;
if(___result) {
 for(i=0;i<round->collection.worker_count;i++) {
  copied+=round->workers[i].copied_words;
  links+=round->workers[i].frame_links_;
 }
 values[0]=round->collection.census.source_words;
 values[1]=round->collection.census.destination_words;
 values[2]=round->collection.census.objects;
 values[3]=round->collection.census.frames;
 values[4]=copied; values[5]=links;
 values[6]=round->collection.planned_copy_sections;
 values[7]=round->collection.issued_copy_sections;
 for(i=0;i<8;i++) if(values[i]>(___SIZE_TS)___MAX_FIX) ___result=0;
 if(___result) for(i=0;i<8;i++) ___VECTORELEM(___arg1,i)=___FIX(values[i]);
}
c-end
))

(define (waiting-work count)
  (let ((mutex (make-mutex)) (values (make-vector 8 0)) (observations '()))
    (mutex-lock! mutex #f #f)
    (let ((target
           (thread-start!
            (make-thread
             (lambda ()
               (let walk ((depth 32))
                 (if (= depth 0)
                     (begin (mutex-lock! mutex #f #f) (mutex-unlock! mutex) 0)
                     (+ 1 (walk (- depth 1))))))))))
      (await-mutex target mutex)
      (do ((i 0 (+ i 1))) ((= i count))
        (require (thread-interrupt! target
                   (lambda () (##gc) (snapshot-wait-gc! values)))
                 'single-processor-idle-gc-snapshot)
        (set! observations (cons (vector->list values) observations))
        (await-mutex target mutex))
      (mutex-unlock! mutex)
      (require (= (thread-join! target 5 -1) 32) 'deep-wait-caller)
      (write (list 'MUTEX-WAIT-WORK 'requests count 'caller-depth 32
                   'columns '(source-words destination-words objects frames
                              copied-words frame-links planned-copy-sections issued-copy-sections)
                   'rounds (reverse observations)))
      (newline))))

(define (cost count)
  (let* ((m (make-mutex)) (counter (vector 0)) (senders 10))
    (mutex-lock! m)
    (let ((target (thread-start! (make-thread (lambda () (mutex-lock! m) (mutex-unlock! m))))))
      (await-mutex target m)
      (let* ((before (##process-statistics)) (start (real-time))
             (threads
              (map (lambda (i)
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (do ((n i (+ n senders))) ((>= n count))
                           (thread-interrupt!
                            target
                            (lambda () (##vector-inc! counter 0))))))))
                   '(0 1 2 3 4 5 6 7 8 9))))
        (for-each thread-join! threads)
        (let ((wall (- (real-time) start)) (after (##process-statistics)))
          (mutex-unlock! m)
          (thread-join! target)
          (require (= (vector-ref counter 0) count) 'cost-count)
          (write (list 'MUTEX-SUSPENSION-COST count wall before after)) (newline))))))

(define (signature actions)
  (let loop ((xs actions))
    (if (null? xs)
        #f
        (let* ((opcode (car xs)) (observation (immediate opcode)))
          (cond ((not (car observation)) 'entry-not-empty)
                ((not (eq? (cadr observation) (not (= opcode 2)))) 'result-mismatch)
                ((not (caddr observation)) 'unnecessary-saved-continuation)
                (else (loop (cdr xs))))))))

(define (remove-at xs index)
  (if (= index 0) (cdr xs) (cons (car xs) (remove-at (cdr xs) (- index 1)))))

(define (shrink actions reason #!optional (observe signature))
  (let again ((xs actions) (index 0))
    (if (= index (length xs))
        xs
        (let ((candidate (remove-at xs index)))
          (if (eq? reason (observe candidate))
              (again candidate 0)
              (again xs (+ index 1)))))))

(define (pbt)
  (let ((seed 173) (actions 0) (failure #f))
    (define (draw)
      (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
      (modulo (quotient seed 65536) 3))
    (do ((case 0 (+ case 1))) ((= case 24))
      (let* ((history (let loop ((n 12) (xs '()))
                        (if (= n 0) xs (loop (- n 1) (cons (draw) xs)))))
             (reason (signature history)))
        (set! actions (+ actions 12))
        (if (and reason (not failure))
            (set! failure (list reason history)))))
    (if failure
        (let* ((reason (car failure)) (original (cadr failure))
               (minimal (shrink original reason)))
          (call-with-output-file "mutex-suspension-minimal.scm"
            (lambda (port) (write minimal port) (newline port)))
          (require (eq? reason (signature minimal)) 'replay)
          (do ((i 0 (+ i 1))) ((= i (length minimal)))
            (require (not (eq? reason (signature (remove-at minimal i)))) 'minimal))
          (write (list 'MUTEX-SUSPENSION-SHRINK reason (length original)
                       (length minimal) 'deletion-one-minimal #t 'replayed #t minimal))
          (newline)
          #f)
        (begin
          (write (list 'MUTEX-SUSPENSION-PBT-PASS 'seed 173 'cases 24 'actions actions))
          (newline)
          #t))))


;; Actual production ticket service on Scheme carriers; no separate lock runner.
(define (ordered-handoff)
  ((c-lambda () void "handoff_reset();"))
  (let ((workers
         (map (lambda (id)
                (thread-start!
                 (make-thread
                  (lambda ()
                    ((c-lambda (int) void "handoff_run(___PSTATE,___arg1);") 4096)))))
              '(0 1 2 3))))
    (for-each thread-join! workers)
    (require ((c-lambda (int) bool "___result = handoff_check(___PSTATE,___arg1);") 16384)
             'ordered-lock-handoff)
    (display "LOCK-HANDOFF-PASS mutations=16384 trylock reservation ownership wrap\n")))

;; Exercise the real direct-start and migration writers, not a copied queue.
;; Existing request-service PBT continues to own replay/shrink calibration.
(define (queue-ownership)
  (let* ((processors (##current-vm-processor-count))
         (workers
          (map (lambda (id)
                 (let ((thread
                        (make-thread
                         (lambda ()
                           (do ((i 0 (+ i 1))) ((= i 16) id)
                             (##thread-migrate-to! (modulo (+ id i) processors))
                             (thread-yield!)
                             (if (= (modulo i 4) 0) (##gc)))))))
                   (##thread-start-on! (modulo id processors) thread)))
               '(0 1 2 3))))
    (for-each (lambda (thread expected)
                (require (= (thread-join! thread) expected) 'migrating-activation)
                (require
                 (with-exception-catcher started-thread-exception?
                   (lambda () (##thread-start-on! 0 thread) #f))
                 'duplicate-direct-start-rejected))
              workers '(0 1 2 3))
    (display "QUEUE-OWNERSHIP-PASS direct-start migrate source-withdraw duplicate-refusal gc\n")))

;; Real two-edge owner propagation. Abandoning a prepared plan changes no
;; key; a refused complete lease changes no key. After GC the retained plan
;; still commits the whole owner effect before any public setter can return.
(define (priority-owner-chain)
  (let ((gate (make-mutex)) (owned (make-mutex))
        (order '()) (middle #f) (leaf #f) (competitor #f) (work #f)
        (base (thread-base-priority (current-thread))))
    (mutex-lock! gate)
    (set! middle
      (thread-start! (make-thread
        (lambda ()
          (mutex-lock! owned)
          (mutex-lock! gate)
          (set! order (cons 'owner order))
          (mutex-unlock! gate)
          (mutex-unlock! owned)))))
    (await-mutex middle gate)
    (set! leaf (thread-start! (make-thread
      (lambda () (mutex-lock! owned) (mutex-unlock! owned)))))
    (await-mutex leaf owned)
    (set! competitor (make-thread
      (lambda ()
        (mutex-lock! gate)
        (set! order (cons 'competitor order))
        (mutex-unlock! gate))))
    (thread-base-priority-set! competitor 5)
    (thread-start! competitor)
    (await-mutex competitor gate)
    (let ((before (thread-base-priority leaf)))
      (require
        (with-exception-catcher
          (lambda (exception) (eq? exception 'abandoned-priority-plan))
          (lambda ()
            (set! work (##thread-priority-plan leaf 17.0 0))
            (##gc)
            (raise 'abandoned-priority-plan)))
        'priority-plan-unwind)
      (require (= before (thread-base-priority leaf)) 'priority-no-premature-key)
      (let ((refused
             (let ()
               (##declare (not interrupts-enabled) (not safe))
               (if (##primitive-trylock! leaf 1 9)
                   (let ((answer (##thread-priority-try! 17.0 0 work)))
                     (##primitive-unlock! leaf 1 9)
                     (not answer))
                   #f))))
        (require refused 'priority-plan-refusal))
      (require (= before (thread-base-priority leaf)) 'priority-refusal-no-key)
      (require (not (##thread-priority-try! 17.0 0 work)) 'priority-retired-plan))
    ;; Public calls reuse the same real owner chain through different keys.
    (for-each (lambda (priority)
                (thread-base-priority-set! leaf priority)
                (thread-priority-boost-set! leaf 0)
                (##gc))
              '(7 11 6 17))
    (mutex-unlock! gate)
    (for-each thread-join! (list middle leaf competitor))
    (require (equal? (reverse order) '(owner competitor)) 'priority-owner-propagation order)
    ;; The existing SMP unlock downgrade hooks are disabled. Restore this
    ;; fixture's caller after all joins so later yield-based probes do not
    ;; inherit its deliberately elevated priority. This is public test cleanup.
    (thread-base-priority-set! (current-thread) base)
    (display "PRIORITY-OWNER-CHAIN-PASS plan-unwind refusal gc owner-propagation\n")))

;; Real owner rings and domain-aware histories share the existing replay/shrink
;; machinery. Raw NaN payloads remain public values. Numeric solved-key receipts
;; are read after the work has retired, outside every mutation lease.
(define (priority-cycle count)
  (let* ((main (current-thread)) (gate (make-mutex))
         (locks (list->vector (map (lambda (i) (make-mutex)) (let loop ((i 0) (xs '())) (if (= i count) xs (loop (+ i 1) (cons i xs)))))))
         (threads (make-vector count #f))
         (base (thread-base-priority main))
         (values (vector +nan.0 -inf.0 -0.0 3.0 +inf.0))
         (worker #f) (seed 173))
    (define (actor first second)
      (make-thread
        (lambda ()
          (with-exception-catcher
            (lambda (e) (if (abandoned-mutex-exception? e) 'abandoned (raise e)))
            (lambda ()
              (mutex-lock! first)
              (thread-send main 'ready)
              (mutex-lock! gate)
              (mutex-unlock! gate)
              (thread-send main 'waiting)
              (mutex-lock! second))))))
    (define (observe actions)
      (let ((expected (make-vector count +nan.0)))
        (do ((i 0 (+ i 1))) ((= i count))
          (thread-base-priority-set! (vector-ref threads i) +nan.0))
        (let loop ((actions actions))
          (if (null? actions) #f
              (let* ((action (car actions)) (index (modulo action count))
                     (value (vector-ref values (modulo (quotient action count) 5)))
                     (thread (vector-ref threads index))
                     (work
                      (let retry ()
                        (let ((work (##thread-priority-plan thread value 0)))
                          (if (##thread-priority-try! value 0 work) work (retry)))))
                     ;; priority-update's floats follow its type and two
                     ;; ticket words. The source-owned private layout is in
                     ;; _thread#.scm; this is a read-only test receipt.
                     (receipt (##unchecked-structure-ref work 3 #f #f)))
                (vector-set! expected index value)
                (if (= (modulo action 5) 0) (##gc))
                (thread-base-priority-set! thread value)
                (let maximum ((i 0) (key -inf.0))
                  (if (< i count)
                      (let ((value (vector-ref expected i)))
                        (maximum (+ i 1) (if (and (not (##flnan? value)) (< key value)) value key)))
                      (let check ((i 0))
                        (cond ((= i count) (loop (cdr actions)))
                              ((not (= (##f64vector-ref receipt (+ i 7)) key)) 'cycle-closure)
                              ((let ((actual (thread-base-priority (vector-ref threads i)))
                                     (expected (vector-ref expected i)))
                                 (not (or (= actual expected)
                                          (and (##flnan? actual) (##flnan? expected)))))
                               'cycle-payload)
                              (else (check (+ i 1))))))))))))
    (mutex-lock! gate)
    ;; Equal setup keys let every actor register; restore before the property.
    (thread-base-priority-set! main -inf.0)
    (do ((i 0 (+ i 1))) ((= i count))
      (let ((thread (actor (vector-ref locks i) (vector-ref locks (modulo (+ i 1) count)))))
        ;; The oracle below varies base values only. Remove the inherited
        ;; boost explicitly; the public default is nonzero (1e-6).
        (thread-priority-boost-set! thread 0)
        (thread-base-priority-set! thread +nan.0)
        (vector-set! threads i thread)
        (thread-start! thread)))
    (do ((i 0 (+ i 1))) ((= i count)) (thread-receive))
    (mutex-unlock! gate)
    (do ((i 0 (+ i 1))) ((= i count)) (thread-receive))
    (do ((i 0 (+ i 1))) ((= i count))
      (await-mutex (vector-ref threads i) (vector-ref locks (modulo (+ i 1) count))))
    (thread-base-priority-set! main base)
    (set! worker
      (##thread-start-on! (modulo 1 (##current-vm-processor-count))
        (make-thread (lambda () (thread-sleep! 0.05) (##gc) 'gc-complete))))
    (thread-base-priority-set! (vector-ref threads 0) +nan.0)
    (do ((case 0 (+ case 1))) ((= case 24))
      (let* ((history
              (let draw ((n 12) (actions '()))
                (if (= n 0) actions
                    (begin
                      (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
                      (draw (- n 1) (cons (modulo (quotient seed 65536) (* count 5)) actions))))))
             (reason (observe history)))
        (if reason
            (let ((minimal (shrink history reason observe)))
              (require (eq? reason (observe minimal)) 'priority-cycle-replay)
              (write (list 'PRIORITY-CYCLE-SHRINK reason count minimal))
              (newline)
              (error "priority cycle property" reason)))))
    (require (eq? (thread-join! worker) 'gc-complete) 'priority-cycle-gc)
    (for-each thread-terminate! (vector->list threads))
    (for-each (lambda (t)
                (with-exception-catcher
                  (lambda (e) (if (not (terminated-thread-exception? e)) (raise e)))
                  (lambda () (thread-join! t))))
              (vector->list threads))
    (write (list 'PRIORITY-CYCLE-PBT-PASS 'seed 173 'owners count 'cases 24 'actions 288
                 'payloads 'nan-infinity-zero-finite 'gc-complete #t 'actors-joined #t))
    (newline)))

;; Public setters exercise the production key transaction. Compare acquisition
;; order under the real mutex; no copied BTQ implementation or scheduler policy.
(define (priority-ownership)
  (priority-owner-chain)
  (let* ((m (make-mutex)) (order '()) (threads '())
         (deadline (seconds->time (+ 1 (time->seconds (current-time))))))
    (mutex-lock! m)
    (set! threads
      (map (lambda (id)
             (thread-start!
              (make-thread
               (lambda ()
                 (require (mutex-lock! m deadline) 'priority-deadline id)
                 (set! order (cons id order))
                 (mutex-unlock! m)))))
           '(0 1 2)))
    (for-each (lambda (t) (await-mutex t m)) threads)
    ;; Waiting nodes occupy both the BTQ and TOQ. Repeated changes must release
    ;; every lease, and preserve the original effective-priority comparator.
    (for-each (lambda (t p)
                (thread-base-priority-set! t p)
                (thread-priority-boost-set! t 0)
                (thread-base-priority-set! t p)
                (require (= (thread-base-priority t) p) 'priority-base p))
              threads '(1 3 2))
    (##gc)
    (mutex-unlock! m)
    (for-each thread-join! threads)
    (require (equal? (reverse order) '(1 2 0)) 'priority-order order))
  (fresh
   (lambda ()
     (let ((thread (current-thread)) (seed 173))
       (define (observe actions)
         (let loop ((xs actions))
           (if (null? xs) #f
               (let ((n (car xs)))
                 (thread-base-priority-set! thread n)
                 (thread-priority-boost-set! thread (+ n 1))
                 (if (and (= (thread-base-priority thread) n)
                          (= (thread-priority-boost thread) (+ n 1)))
                     (loop (cdr xs)) 'priority-value)))))
       (do ((case 0 (+ case 1))) ((= case 24))
         (let* ((history
                 (let loop ((n 12) (xs '()))
                   (if (= n 0) xs
                       (begin
                         (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
                         (loop (- n 1) (cons (modulo (quotient seed 65536) 7) xs))))))
                (reason (observe history)))
           (if reason
               (let ((minimal (shrink history reason observe)))
                 (write (list 'PRIORITY-SHRINK reason minimal)) (newline)
                 (require (eq? reason (observe minimal)) 'priority-replay)
                 (error "priority ownership counterexample" minimal)))))
       ;; A conversion exception precedes all leases; a subsequent setter must
       ;; still succeed. Public argument checking remains the original API.
       (require (with-exception-catcher (lambda (e) #t)
                  (lambda () (thread-base-priority-set! thread 'invalid) #f))
                'priority-invalid-argument)
       ;; Public real-number payloads, including inherited NaN, stay intact.
       ;; Scheduling keys have a separate canonical ordered-domain contract.
       (thread-base-priority-set! thread +nan.0)
       (thread-base-priority-set! thread +nan.0)
       (require (##flnan? (thread-base-priority thread)) 'priority-nan-preserved)
       (require (##flnan? (thread-join!
                           (thread-start! (make-thread
                             (lambda () (thread-base-priority (current-thread)))))))
                'priority-nan-inherited-payload)
       (thread-base-priority-set! thread 0))))
  (display "PRIORITY-OWNERSHIP-PASS btq toq gc exception replay seed=173 cases=24\n"))

(define args (cdr (command-line)))
(cond ((equal? args '("--handoff")) (smp-wait-case ordered-handoff))
      ((equal? args '("--queue-ownership")) (smp-wait-case queue-ownership))
      ((equal? args '("--priority")) (smp-wait-case priority-ownership))
      ((equal? args '("--priority-cycle")) (smp-wait-case (lambda () (for-each priority-cycle '(2 3 8)))))
      ((equal? args '("--probe")) (probe))
      ((equal? args '("--wait-continuation")) (smp-wait-case waiting-continuation))
      ((equal? args '("--join-continuation")) (smp-wait-case (lambda () (waiting-continuation 'join))))
      ((equal? args '("--sleep-continuation")) (smp-wait-case (lambda () (waiting-continuation 'sleep))))
      ((equal? args '("--cv-continuation")) (smp-wait-case (lambda () (waiting-continuation 'cv))))
      ((equal? args '("--wait-io")) (smp-wait-case waiting-io))
      ((equal? args '("--io-child"))
       (let ((line (read-line)))
         (if (not (eof-object? line))
             (begin (display line) (newline) (force-output)))))
      ((and (pair? args) (string=? (car args) "--wait-work"))
       (smp-wait-case (lambda () (waiting-work (string->number (cadr args))))))
      ((equal? args '("--pbt")) (if (not (pbt)) (exit 70)))
      ((and (pair? args) (string=? (car args) "--replay"))
       (let ((history (call-with-input-file (cadr args) read)))
         (write (list 'MUTEX-SUSPENSION-REPLAY (signature history))) (newline)))
      ((and (pair? args) (string=? (car args) "--cost")) (cost (string->number (cadr args))))
      (else
       (require (pbt) 'pbt)
       (blocking)
       (display "MUTEX-SUSPENSION-PASS\n")))
