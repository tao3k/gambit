;;;============================================================================

;;; File: "test.scm"

;;; (gambit concurrent) — Unit & 12-Core SMP Linearizability Stress Tests

(import (gambit concurrent))
(import (srfi 230))
(import (_test))

;;;============================================================================
;;; 1. Lock-Free Treiber Stack (unit + MPMC SMP conservation)

(define st (make-lf-stack))
(test-equal #t (lf-stack? st))
(test-equal #t (lf-stack-empty? st))
(call-with-values (lambda () (lf-stack-try-pop! st))
  (lambda (ok v) (test-equal #f ok) (test-equal #f v)))

(lf-stack-push! st 'a)
(lf-stack-push! st 'b)
(test-equal #f (lf-stack-empty? st))
(call-with-values (lambda () (lf-stack-try-pop! st))
  (lambda (ok v) (test-equal #t ok) (test-equal 'b v)))
(call-with-values (lambda () (lf-stack-try-pop! st))
  (lambda (ok v) (test-equal #t ok) (test-equal 'a v)))
(test-equal #t (lf-stack-empty? st))

;;;============================================================================
;;; 2. Lock-Free Michael-Scott Queue (unit FIFO)

(define q (make-lf-queue))
(test-equal #t (lf-queue? q))
(test-equal #t (lf-queue-empty? q))
(call-with-values (lambda () (lf-queue-try-dequeue! q))
  (lambda (ok v) (test-equal #f ok)))

(lf-queue-enqueue! q 10)
(lf-queue-enqueue! q 20)
(lf-queue-enqueue! q 30)
(test-equal #f (lf-queue-empty? q))
(call-with-values (lambda () (lf-queue-try-dequeue! q))
  (lambda (ok v) (test-equal #t ok) (test-equal 10 v)))
(call-with-values (lambda () (lf-queue-try-dequeue! q))
  (lambda (ok v) (test-equal #t ok) (test-equal 20 v)))
(call-with-values (lambda () (lf-queue-try-dequeue! q))
  (lambda (ok v) (test-equal #t ok) (test-equal 30 v)))
(test-equal #t (lf-queue-empty? q))

;;;============================================================================
;;; 3. Lock-Free Chase-Lev Work-Stealing Deque (unit LIFO pop + FIFO steal)

(define dq (make-ws-deque 16))
(test-equal #t (ws-deque? dq))
(test-equal 0 (ws-deque-size dq))
(test-equal #t (ws-deque-push! dq 't1))
(test-equal #t (ws-deque-push! dq 't2))
(test-equal #t (ws-deque-push! dq 't3))
(test-equal 3 (ws-deque-size dq))
;; Thief steals FIFO from top -> 't1
(call-with-values (lambda () (ws-deque-try-steal! dq))
  (lambda (ok v) (test-equal #t ok) (test-equal 't1 v)))
;; Owner pops LIFO from bottom -> 't3
(call-with-values (lambda () (ws-deque-try-pop! dq))
  (lambda (ok v) (test-equal #t ok) (test-equal 't3 v)))
;; Last element -> 't2
(call-with-values (lambda () (ws-deque-try-pop! dq))
  (lambda (ok v) (test-equal #t ok) (test-equal 't2 v)))
(test-equal 0 (ws-deque-size dq))

;;;============================================================================
;;; 4. Wait-Free-Read / Lock-Free-Write Concurrent Hash Table (unit)

(define ct (make-concurrent-table 32))
(test-equal #t (concurrent-table? ct))
(test-equal 0 (concurrent-table-size ct))
(test-equal 'missing (concurrent-table-ref ct 'k1 'missing))
(concurrent-table-set! ct 'k1 100)
(concurrent-table-set! ct 'k2 200)
(test-equal 2 (concurrent-table-size ct))
(test-equal 100 (concurrent-table-ref ct 'k1))
(test-equal 200 (concurrent-table-ref ct 'k2))
(concurrent-table-update! ct 'k1 (lambda (found old) (if found (+ old 50) 0)))
(test-equal 150 (concurrent-table-ref ct 'k1))
(test-equal #t (concurrent-table-delete! ct 'k1))
(test-equal #f (concurrent-table-delete! ct 'k1))
(test-equal 1 (concurrent-table-size ct))
(test-equal #f (concurrent-table-ref ct 'k1))

;;;============================================================================
;;; 5. True Multicore SMP Conservation & Linearizability Stress Tests

(let* ((nprocs (##current-vm-processor-count))
       (nworkers (max 4 (* 2 nprocs)))
       (items-per-worker 1000)
       (expected-total (* nworkers items-per-worker))
       (expected-sum (* nworkers (/ (* items-per-worker (+ items-per-worker 1)) 2))))

  ;; 5a. Treiber Stack: N producers + N consumers -> exact item conservation
  (let* ((s (make-lf-stack))
         (popped-cnt (make-atomic-fxbox 0))
         (popped-sum (make-atomic-fxbox 0))
         (done-prod (make-atomic-fxbox 0))
         (prods
          (let loop ((w 0) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let pl ((i 1))
                          (when (<= i items-per-worker)
                            (lf-stack-push! s i)
                            (pl (+ i 1))))
                        (atomic-fxbox+/fetch! done-prod 1 (memory-order release)))))
                            acc)))))
         (cons-ts
          (let loop ((w 0) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let cl ((local-c 0) (local-s 0))
                          (call-with-values (lambda () (lf-stack-try-pop! s))
                            (lambda (ok v)
                              (if ok
                                  (cl (+ local-c 1) (+ local-s v))
                                  (if (and (= (atomic-fxbox-ref done-prod (memory-order acquire)) nworkers)
                                           (lf-stack-empty? s))
                                      (begin
                                        (atomic-fxbox+/fetch! popped-cnt local-c (memory-order relaxed))
                                        (atomic-fxbox+/fetch! popped-sum local-s (memory-order relaxed)))
                                      (begin (thread-yield!) (cl local-c local-s))))))))))
                            acc))))))
    (for-each thread-join! prods)
    (for-each thread-join! cons-ts)
    (test-equal expected-total (atomic-fxbox-ref popped-cnt))
    (test-equal expected-sum (atomic-fxbox-ref popped-sum))
    (test-equal #t (lf-stack-empty? s)))

  ;; 5b. Michael-Scott Queue: N producers + N consumers -> exact conservation
  (let* ((mq (make-lf-queue))
         (deq-cnt (make-atomic-fxbox 0))
         (deq-sum (make-atomic-fxbox 0))
         (done-prod (make-atomic-fxbox 0))
         (prods
          (let loop ((w 0) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let pl ((i 1))
                          (when (<= i items-per-worker)
                            (lf-queue-enqueue! mq i)
                            (pl (+ i 1))))
                        (atomic-fxbox+/fetch! done-prod 1 (memory-order release)))))
                            acc)))))
         (cons-ts
          (let loop ((w 0) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let cl ((local-c 0) (local-s 0))
                          (call-with-values (lambda () (lf-queue-try-dequeue! mq))
                            (lambda (ok v)
                              (if ok
                                  (cl (+ local-c 1) (+ local-s v))
                                  (if (and (= (atomic-fxbox-ref done-prod (memory-order acquire)) nworkers)
                                           (lf-queue-empty? mq))
                                      (begin
                                        (atomic-fxbox+/fetch! deq-cnt local-c (memory-order relaxed))
                                        (atomic-fxbox+/fetch! deq-sum local-s (memory-order relaxed)))
                                      (begin (thread-yield!) (cl local-c local-s))))))))))
                            acc))))))
    (for-each thread-join! prods)
    (for-each thread-join! cons-ts)
    (test-equal expected-total (atomic-fxbox-ref deq-cnt))
    (test-equal expected-sum (atomic-fxbox-ref deq-sum))
    (test-equal #t (lf-queue-empty? mq)))

  ;; 5c. Chase-Lev Work-Stealing Deque: 1 owner + (nworkers-1) thieves -> exact conservation
  (let* ((ws (make-ws-deque 4096))
         (nitems 4000)
         (ws-expected-sum (/ (* nitems (+ nitems 1)) 2))
         (taken-cnt (make-atomic-fxbox 0))
         (taken-sum (make-atomic-fxbox 0))
         (owner-done (make-atomic-fxbox 0))
         (thieves
          (let loop ((w 1) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let tl ((lc 0) (ls 0))
                          (call-with-values (lambda () (ws-deque-try-steal! ws))
                            (lambda (ok v)
                              (if ok
                                  (tl (+ lc 1) (+ ls v))
                                  (if (and (= (atomic-fxbox-ref owner-done (memory-order acquire)) 1)
                                           (= (ws-deque-size ws) 0))
                                      (begin
                                        (atomic-fxbox+/fetch! taken-cnt lc (memory-order relaxed))
                                        (atomic-fxbox+/fetch! taken-sum ls (memory-order relaxed)))
                                      (begin (thread-yield!) (tl lc ls))))))))))
                            acc))))))
    ;; Owner pushes and interleaves pops
    (let ol ((i 1) (lc 0) (ls 0))
      (if (<= i nitems)
          (begin
            (let push-retry ()
              (unless (ws-deque-push! ws i)
                (thread-yield!)
                (push-retry)))
            (if (= (modulo i 3) 0)
                (call-with-values (lambda () (ws-deque-try-pop! ws))
                  (lambda (ok v)
                    (if ok (ol (+ i 1) (+ lc 1) (+ ls v)) (ol (+ i 1) lc ls))))
                (ol (+ i 1) lc ls)))
          (let drain ((lc lc) (ls ls))
            (call-with-values (lambda () (ws-deque-try-pop! ws))
              (lambda (ok v)
                (if ok
                    (drain (+ lc 1) (+ ls v))
                    (begin
                      (atomic-fxbox+/fetch! taken-cnt lc (memory-order relaxed))
                      (atomic-fxbox+/fetch! taken-sum ls (memory-order relaxed))
                      (atomic-fxbox-set! owner-done 1 (memory-order release)))))))))
    (for-each thread-join! thieves)
    (test-equal nitems (atomic-fxbox-ref taken-cnt))
    (test-equal ws-expected-sum (atomic-fxbox-ref taken-sum)))

  ;; 5d. Sharded Concurrent Hash Table: N workers contend on atomic updates + reads
  (let* ((tbl (make-concurrent-table 64))
         (nkeys 32)
         (updates-per-worker 500)
         (ts
          (let loop ((w 0) (acc '()))
            (if (= w nworkers) acc
                (loop (+ w 1)
                      (cons (thread-start! (make-thread (lambda ()
                        (let ul ((i 0))
                          (when (< i updates-per-worker)
                            (let ((k (modulo (+ i w) nkeys)))
                              (concurrent-table-update! tbl k (lambda (f old) (if f (+ old 1) 1)))
                              (let ((v (concurrent-table-ref tbl k 0)))
                                (unless (> v 0) (error "concurrent-table torn read" k v))))
                            (ul (+ i 1)))))))
                            acc))))))
    (for-each thread-join! ts)
    (test-equal nkeys (concurrent-table-size tbl))
    (let ((total-updates
           (let sl ((k 0) (acc 0))
             (if (= k nkeys) acc (sl (+ k 1) (+ acc (concurrent-table-ref tbl k 0)))))))
      (test-equal (* nworkers updates-per-worker) total-updates))))

;;;============================================================================
;;; Overflow-Safe Power-of-Two Guards, Hash/API Validation, GC Slot Clearing
;;; & Non-Negative Concurrent Table Size Torture

(let ((check-err
       (lambda (thunk)
         (with-exception-catcher (lambda (e) #t) (lambda () (thunk) #f))))
      (max-pow2
       (let lp ((x 1))
         (let ((y (##fxarithmetic-shift-left x 1)))
           (if (##fx<= y x) x (lp y))))))
  ;; Overflowing capacities must raise cleanly without infinite-looping
  (test-equal #t (check-err (lambda () (make-ws-deque (##fx+ max-pow2 1)))))
  (test-equal #t (check-err (lambda () (make-concurrent-table (##fx+ max-pow2 1)))))

  ;; Invalid eq-fn / hash-fn / updater rejected cleanly
  (test-equal #t (check-err (lambda () (make-concurrent-table 16 123 equal?-hash))))
  (test-equal #t (check-err (lambda () (make-concurrent-table 16 equal? 456))))
  (let ((t-api (make-concurrent-table 16)))
    (test-equal #t (check-err (lambda () (concurrent-table-update! t-api 'k 789)))))

  ;; Custom hash returning non-integer raises; bignum hash works deterministically
  (let ((t-bad (make-concurrent-table 16 equal? (lambda (k) 'not-an-int)))
        (t-big (make-concurrent-table 16 string=? (lambda (s) (+ (expt 2 80) (string-length s))))))
    (test-equal #t (check-err (lambda () (concurrent-table-set! t-bad 'a 1))))
    (test-equal #t (check-err (lambda () (concurrent-table-ref t-bad 'a))))
    (test-equal #t (check-err (lambda () (concurrent-table-delete! t-bad 'a))))
    (concurrent-table-set! t-big "alpha" 10)
    (concurrent-table-set! t-big "beta" 20)
    (test-equal 10 (concurrent-table-ref t-big (string-copy "alpha")))
    (test-equal 20 (concurrent-table-ref t-big (string-copy "beta")))
    (test-equal 2 (concurrent-table-size t-big))
    (test-equal #t (concurrent-table-delete! t-big (string-copy "alpha")))
    (test-equal 1 (concurrent-table-size t-big))))

;; Chase-Lev ws-deque-try-pop! clears exclusively owned slots (t < b) for GC
(let ((d (make-ws-deque 16))
      (obj1 (list 'payload-1))
      (obj2 (list 'payload-2)))
  (test-equal #t (ws-deque-push! d obj1))
  (test-equal #t (ws-deque-push! d obj2))
  ;; Pop top item with t=0 < b=1 -> slot 1 must be cleared to #f immediately
  (test-equal obj2 (ws-deque-try-pop-or! d #f))
  (let ((slots (##structure-ref d 3 (##structure-type d) #f)))
    (test-equal #f (vector-ref slots 1)))
  (test-equal obj1 (ws-deque-try-pop-or! d #f))
  (test-equal 0 (ws-deque-size d)))

;; Multi-segment lf-queue boundary churn (> 1024 items, crossing 4+ 256-slot segments)
;; + concurrent insert/delete table-size non-negativity + GC under adaptive-P SMP.
(let* ((nprocs (##current-vm-processor-count))
       (w (max 2 (min 8 nprocs)))
       (ct-race (make-concurrent-table 16))
       (neg-seen (make-atomic-fxbox 0))
       (q-seg (make-lf-queue))
       (q-items 1024))
  ;; Multi-segment lf-queue exact FIFO conservation across 4 segment boundaries
  (let push-lp ((i 0))
    (when (< i q-items)
      (lf-queue-enqueue! q-seg i)
      (push-lp (+ i 1))))
  (let pop-lp ((i 0) (ok #t))
    (if (< i q-items)
        (let ((v (lf-queue-try-dequeue-or! q-seg -1)))
          (pop-lp (+ i 1) (and ok (= v i))))
        (begin
          (test-equal #t ok)
          (test-equal -1 (lf-queue-try-dequeue-or! q-seg -1))
          (test-equal #t (lf-queue-empty? q-seg)))))

  ;; Concurrent insert/delete + continuous size reader never observes negative size
  (let ((threads
         (let loop ((t 0) (acc '()))
           (if (= t w)
               acc
               (loop (+ t 1)
                     (cons
                      (thread-start!
                       (make-thread
                        (lambda ()
                          (let rloop ((r 0))
                            (when (< r 400)
                              (let ((k (modulo r 8)))
                                (concurrent-table-set! ct-race k r)
                                (if (< (concurrent-table-size ct-race) 0)
                                    (atomic-fxbox+/fetch! neg-seen 1))
                                (concurrent-table-delete! ct-race k)
                                (if (< (concurrent-table-size ct-race) 0)
                                    (atomic-fxbox+/fetch! neg-seen 1))
                                (if (and (= t 0) (= (modulo r 64) 63)) (##gc)))
                              (rloop (+ r 1)))))))
                      acc))))))
    (for-each thread-join! threads)
    (test-equal 0 (atomic-fxbox-ref neg-seen))
    (test-equal 0 (concurrent-table-size ct-race))))

;;;============================================================================
