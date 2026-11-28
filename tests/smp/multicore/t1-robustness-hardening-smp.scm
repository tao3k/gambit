;;; Tier 1 SMP Robustness Hardening PBT Regression Suite
;;; Covers:
;;;   1. gc-hash-table Bit-8 cursor pin: exception escape, multi-shot call/cc,
;;;      serialization transform GC/escape, and concurrent SMP traversal.
;;;   2. Thread termination mutex abandonment: deterministic self-deadlock
;;;      (new-owner == terminating owner), self-termination fast path, and
;;;      concurrent AB/BA terminate vs mutex-unlock/lock hammer.
;;;   3. Lock-free atomic ##registered-modules concurrent register/lookup/remove.

(declare (standard-bindings) (extended-bindings))

(define (assert-true cond-val label . info)
  (if (not cond-val)
      (apply error (string-append "T1-FAIL: " label) info)))

(define (gcht-flags gcht)
  (##unchecked-structure-ref gcht 1 #f #f))

(define (gcht-cursor-count gcht)
  (fxarithmetic-shift-right (gcht-flags gcht) 9))

(define (gcht-rehashing? gcht)
  (not (= (fxand (gcht-flags gcht) 256) 0)))

(define (gcht-policy-flags gcht)
  (fxand (gcht-flags gcht) 255))

;; ---------------------------------------------------------------------------
;; 1. gc-hash-table Bit-8 cursor pin: exception, call/cc, serialization, SMP
;; ---------------------------------------------------------------------------
(define (test-gcht-cursor-pin)
  (let* ((keys (let loop ((i 0) (acc '()))
                 (if (= i 97) acc (loop (+ i 1) (cons (vector i) acc)))))
         (tbl (make-table test: eq?)))
    (for-each (lambda (k) (table-set! tbl k k)) keys)
    (let* ((gcht (##table-get-eq-gcht tbl (car keys)))
           (base-policy (fxand (gcht-policy-flags gcht) (fxnot 4))))

      ;; 1a. Exception escapes from table-for-each / table-search / table-foldl
      (let loop ((i 0))
        (if (< i 50)
            (begin
              (with-exception-catcher
               (lambda (e) 'caught)
               (lambda ()
                 (table-for-each
                  (lambda (k v)
                    (assert-true (>= (gcht-cursor-count gcht) 1) "pin-active-for-each")
                    (##gc)
                    (assert-true (eq? (table-ref tbl k #f) k) "ref-during-for-each")
                    (error 'escape-for-each))
                  tbl)))
              (assert-true (= (gcht-cursor-count gcht) 0)
                           "pin-leaked-after-for-each-exc" (gcht-flags gcht))

              (with-exception-catcher
               (lambda (e) 'caught)
               (lambda ()
                 (table-search
                  (lambda (k v)
                    (assert-true (>= (gcht-cursor-count gcht) 1) "pin-active-search")
                    (error 'escape-search))
                  tbl)))
              (assert-true (= (gcht-cursor-count gcht) 0)
                           "pin-leaked-after-search-exc" (gcht-flags gcht))

              (with-exception-catcher
               (lambda (e) 'caught)
               (lambda ()
                 (##table-foldl
                  cons '()
                  (lambda (k v)
                    (assert-true (>= (gcht-cursor-count gcht) 1) "pin-active-foldl")
                    (error 'escape-foldl))
                  tbl)))
              (assert-true (= (gcht-cursor-count gcht) 0)
                           "pin-leaked-after-foldl-exc" (gcht-flags gcht))
              (loop (+ i 1)))))

      ;; After unpin, a GC + table-ref must be allowed to rehash in situ and
      ;; clear FLAG_KEY_MOVED (bit 2 = 4).
      (##gc)
      (assert-true (eq? (table-ref tbl (car keys) #f) (car keys)) "post-exc-ref")
      (assert-true (= (fxand (gcht-flags gcht) 4) 0)
                   "post-exc-rehash-cleared-key-moved" (gcht-flags gcht))
      (assert-true (= (gcht-cursor-count gcht) 0) "post-exc-pin-zero")

      ;; 1b. Multi-shot call/cc re-entry inside table-for-each must stay balanced
      (let ((saved-k #f)
            (reentries 0)
            (visits 0))
        (table-for-each
         (lambda (k v)
           (set! visits (+ visits 1))
           (if (= visits 3)
               (call/cc (lambda (k-cont) (set! saved-k k-cont))))
           (assert-true (= (gcht-cursor-count gcht) 1)
                        "multishot-pin-count-exact-1" (gcht-flags gcht)))
         tbl)
        (assert-true (= (gcht-cursor-count gcht) 0) "multishot-pin-zero-first")
        (if (< reentries 4)
            (begin
              (set! reentries (+ reentries 1))
              (saved-k #f)))
        (assert-true (= reentries 4) "multishot-reentered-4x" reentries)
        (assert-true (= (gcht-cursor-count gcht) 0)
                     "multishot-pin-zero-final" (gcht-flags gcht))
        (assert-true (= (fxand (gcht-policy-flags gcht) (fxnot 4)) base-policy)
                     "multishot-policy-intact" (gcht-flags gcht) base-policy))

      ;; 1c. Serialization transform GC + escape must not leak Bit-8 into
      ;;     either the source table or the serialized representation
      (with-exception-catcher
       (lambda (e) 'caught)
       (lambda ()
         (object->u8vector
          tbl
          (lambda (x)
            (if (vector? x) (error 'ser-escape))
            x))))
      (assert-true (= (gcht-cursor-count gcht) 0)
                   "ser-escape-pin-zero" (gcht-flags gcht))

      (let* ((seen-ser 0)
             (bytes (object->u8vector
                     tbl
                     (lambda (x)
                       (set! seen-ser (+ seen-ser 1))
                       (if (= (modulo seen-ser 19) 0)
                           (begin
                             (##gc)
                             (table-ref tbl (car keys) #f)))
                       x)))
             (restored (u8vector->object bytes))
             (restored-gcht (##table-get-eq-gcht restored (car keys))))
        (assert-true (= (gcht-cursor-count gcht) 0)
                     "ser-success-src-pin-zero" (gcht-flags gcht))
        (assert-true (= (gcht-cursor-count restored-gcht) 0)
                     "ser-success-dst-pin-zero" (gcht-flags restored-gcht))
        (assert-true (= (table-length restored) 97)
                     "ser-restored-length" (table-length restored)))

      ;; 1d. Multi-threaded concurrent traversal + exception escape + GC hammer
      (let ((workers
             (let loop ((t 0) (acc '()))
               (if (= t 8)
                   acc
                   (loop
                    (+ t 1)
                    (cons
                     (thread-start!
                      (make-thread
                       (lambda ()
                         (let wloop ((r 0))
                           (if (< r 250)
                               (begin
                                 (cond
                                  ((= (modulo (+ r t) 4) 0)
                                   (let ((cnt 0))
                                     (table-for-each
                                      (lambda (k v)
                                        (set! cnt (+ cnt 1))
                                        (if (= cnt 10) (table-ref tbl k #f)))
                                      tbl)
                                     (assert-true (= cnt 97) "smp-for-each-count" cnt)))
                                  ((= (modulo (+ r t) 4) 1)
                                   (with-exception-catcher
                                    (lambda (e) 'ok)
                                    (lambda ()
                                      (table-search
                                       (lambda (k v)
                                         (if (eq? k (car keys))
                                             (error 'smp-escape))
                                         #f)
                                       tbl))))
                                  ((= (modulo (+ r t) 4) 2)
                                   (let ((n (##table-foldl
                                             (lambda (a b) (+ a 1)) 0
                                             (lambda (k v) k)
                                             tbl)))
                                     (assert-true (= n 97) "smp-foldl-count" n)))
                                  (else
                                   (##gc)
                                   (assert-true (eq? (table-ref tbl (car keys) #f) (car keys))
                                                "smp-ref-after-gc")))
                                 (wloop (+ r 1))))))))
                     acc))))))
        (for-each thread-join! workers))
      (assert-true (= (gcht-cursor-count gcht) 0)
                   "smp-final-pin-zero" (gcht-flags gcht))
      (assert-true (= (fxand (gcht-policy-flags gcht) (fxnot 4)) base-policy)
                   "smp-final-policy-intact" (gcht-flags gcht) base-policy))))

;; ---------------------------------------------------------------------------
;; 2. Thread termination mutex abandonment (self-deadlock + AB/BA stress)
;; ---------------------------------------------------------------------------
(define (test-mutex-abandon-no-deadlock)
  ;; 2a. Deterministic reproducer: T1 owns M, T2 waits via (mutex-lock! M #f T1),
  ;;     then T1 terminates. Before fix, ##btq-abandon! -> ##mutex-signal-no-reschedule!
  ;;     self-deadlocked 100% deterministically on (macro-trylock-thread! T1).
  (let loop ((i 0))
    (if (< i 60)
        (let* ((m (make-mutex))
               (owner-ready (make-mutex))
               (allow-exit (make-mutex))
               (waiter-entered (make-mutex)))
          (mutex-lock! owner-ready)
          (mutex-lock! allow-exit)
          (mutex-lock! waiter-entered)
          (let* ((t1 (thread-start!
                      (make-thread
                       (lambda ()
                         (mutex-lock! m #f (current-thread))
                         (mutex-unlock! owner-ready)
                         (mutex-lock! allow-exit)
                         (if (even? i)
                             (thread-terminate! (current-thread))
                             'normal-exit)))))
                 (t2 (thread-start!
                      (make-thread
                       (lambda ()
                         (mutex-lock! owner-ready)
                         (mutex-unlock! owner-ready)
                         (mutex-unlock! waiter-entered)
                         (with-exception-catcher
                          (lambda (e)
                            (assert-true (abandoned-mutex-exception? e)
                                         "expected-abandoned-exc" e)
                            'abandoned-caught)
                          (lambda ()
                            (mutex-lock! m #f t1)
                            'unexpected-normal)))))))
            (mutex-lock! waiter-entered)
            ;; Give t2 a moment to enqueue onto m's btq before t1 exits
            (thread-sleep! 0.001)
            (mutex-unlock! allow-exit)
            (let ((r2 (thread-join! t2)))
              (with-exception-catcher (lambda (e) 't1-terminated)
                                      (lambda () (thread-join! t1)))
              (assert-true (eq? r2 'abandoned-caught)
                           "self-owner-abandon-result" i r2)
              (assert-true (eq? (mutex-state m) 'abandoned)
                           "self-owner-mutex-state" i (mutex-state m))))
          (loop (+ i 1)))))

  ;; 2b. Cross-core AB/BA hammer: concurrent thread-terminate!, mutex-unlock!,
  ;;     and waiters requesting various new-owner targets (owner / self / #f / peer)
  (let rloop ((round 0))
    (if (< round 40)
        (let* ((m1 (make-mutex))
               (m2 (make-mutex))
               (peer (thread-start! (make-thread (lambda () (thread-sleep! 0.01)))))
               (ready (make-mutex)))
          (mutex-lock! ready)
          (let* ((owner (thread-start!
                         (make-thread
                          (lambda ()
                            (mutex-lock! m1 #f (current-thread))
                            (mutex-lock! m2 #f (current-thread))
                            (mutex-unlock! ready)
                            (thread-sleep! 0.002)))))
                 (w1 (thread-start!
                      (make-thread
                       (lambda ()
                         (mutex-lock! ready)
                         (mutex-unlock! ready)
                         (with-exception-catcher
                          (lambda (e) 'exc)
                          (lambda ()
                            (mutex-lock! m1 0.05 owner)
                            (mutex-unlock! m1)))))))
                 (w2 (thread-start!
                      (make-thread
                       (lambda ()
                         (mutex-lock! ready)
                         (mutex-unlock! ready)
                         (with-exception-catcher
                          (lambda (e) 'exc)
                          (lambda ()
                            (mutex-lock! m2 0.05 peer)
                            (mutex-unlock! m2)))))))
                 (unlocker (thread-start!
                            (make-thread
                             (lambda ()
                               (mutex-lock! ready)
                               (mutex-unlock! ready)
                               (if (odd? round)
                                   (mutex-unlock! m1))
                               (if (even? round)
                                   (thread-terminate! owner)))))))
            (for-each
             (lambda (th)
               (with-exception-catcher (lambda (e) 'joined-exc)
                                       (lambda () (thread-join! th))))
             (list owner w1 w2 unlocker peer)))
          (rloop (+ round 1))))))

;; ---------------------------------------------------------------------------
;; 3. Lock-free atomic ##registered-modules concurrent register/lookup/remove
;; ---------------------------------------------------------------------------
(define (test-registered-modules-atomic)
  (let* ((n-threads 8)
         (per-thread 150)
         (make-ref (lambda (t i)
                     (string->symbol
                      (string-append "t1-mod-" (number->string t) "-" (number->string i)))))
         (workers
          (let loop ((t 0) (acc '()))
            (if (= t n-threads)
                acc
                (loop
                 (+ t 1)
                 (cons
                  (thread-start!
                   (make-thread
                    (lambda ()
                      (let iloop ((i 0))
                        (if (< i per-thread)
                            (let* ((ref (make-ref t i))
                                   (d1 (vector ref 'v1 t i))
                                   (d2 (vector ref 'v2 t i)))
                              (##register-module-descr! ref d1)
                              (assert-true (##lookup-registered-module ref)
                                           "mod-present-v1" ref)
                              ;; Replace existing module entry atomically
                              (##register-module-descr! ref d2)
                              (let ((m (##lookup-registered-module ref)))
                                (assert-true (and m (eq? (vector-ref m 2) d2))
                                             "mod-replaced-v2" ref m))
                              (iloop (+ i 1))))))))
                  acc))))))
    (for-each thread-join! workers)
    ;; Every single one of the 8 * 150 = 1200 modules MUST be registered (zero lost updates)
    (let tloop ((t 0))
      (if (< t n-threads)
          (begin
            (let iloop ((i 0))
              (if (< i per-thread)
                  (let* ((ref (make-ref t i))
                         (m (##lookup-registered-module ref)))
                    (assert-true m "mod-lost-after-concurrent-register" ref)
                    (assert-true (eq? (vector-ref (vector-ref m 2) 1) 'v2)
                                 "mod-descr-version-v2" ref)
                    (iloop (+ i 1)))))
            (tloop (+ t 1)))))
    ;; Concurrent removal of all 1200 synthetic modules
    (let ((removers
           (let loop ((t 0) (acc '()))
             (if (= t n-threads)
                 acc
                 (loop
                  (+ t 1)
                  (cons
                   (thread-start!
                    (make-thread
                     (lambda ()
                       (let iloop ((i 0))
                         (if (< i per-thread)
                             (let ((ref (make-ref t i)))
                               (assert-true (##remove-registered-module ref)
                                            "mod-remove-found" ref)
                               (assert-true (not (##lookup-registered-module ref))
                                            "mod-removed-absent" ref)
                               (iloop (+ i 1))))))))
                   acc))))))
      (for-each thread-join! removers))
    ;; Verify every single synthetic module is gone
    (let tloop ((t 0))
      (if (< t n-threads)
          (begin
            (let iloop ((i 0))
              (if (< i per-thread)
                  (begin
                    (assert-true (not (##lookup-registered-module (make-ref t i)))
                                 "mod-still-present-after-remove" t i)
                    (iloop (+ i 1)))))
            (tloop (+ t 1)))))))

(test-gcht-cursor-pin)
(test-mutex-abandon-no-deadlock)
(test-registered-modules-atomic)
(println "T1-ROBUSTNESS-HARDENING-PASS gcht=ok abandon=ok modules=1200/1200")
