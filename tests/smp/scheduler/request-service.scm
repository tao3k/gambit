;;; Real service identity, wait ownership and multi-shot completion consumers.
(##include "~~lib/_gambit#.scm")
(##include "~~lib/_thread#.scm")
(##namespace ("gambit#tests#smp#scheduler#request-service#"
              check target delivered request-count gate changed ready))
(define (check actual expected)
  (if (not (equal? actual expected))
      (error "request service contract" actual expected)))

;; The public running/parked routes must use one request service authority.
(define gate (make-mutex))
(define changed (make-condition-variable))
(define ready #f)
(define delivered 0)
(define request-count 64)
(define target
  (thread-start!
   (make-thread
    (lambda ()
      (mutex-lock! gate)
      (set! ready #t)
      (condition-variable-broadcast! changed)
      (let wait ()
        (if (< delivered request-count)
            (begin (mutex-unlock! gate changed 5)
                   (mutex-lock! gate)
                   (wait))))
      (mutex-unlock! gate)
      delivered))))
(mutex-lock! gate)
(let wait ()
  (if (not ready)
      (begin (mutex-unlock! gate changed 5) (mutex-lock! gate) (wait))))
(mutex-unlock! gate)
(let loop ((i 0))
  (if (< i request-count)
      (begin
        (check (thread-interrupt!
                target
                (lambda ()
                  (if (= (modulo i 8) 0) (##gc))
                  (set! delivered (+ delivered 1))
                  (vector i (current-thread))))
               (vector i target))
        (loop (+ i 1)))))
(mutex-lock! gate)
(condition-variable-signal! changed)
(mutex-unlock! gate)
(check (thread-join! target 5 'timeout) request-count)

;; Completion is not replayed when a user continuation reenters the service
;; return suffix. Keep a new owner on the completion mutex across both restores.
(let* ((completion (make-mutex))
       (saved #f)
       (returns 0)
       (request (macro-make-thread-request
                 (current-thread)
                 (lambda () (call/cc (lambda (k) (set! saved k) 'first)))
                 completion 'queued #f)))
  (mutex-lock! completion)
  (##thread-intr-service! request)
  (set! returns (+ returns 1))
  (check (macro-thread-request-state request) 'returned)
  (check (macro-thread-request-result request) 'first)
  (if (= returns 1) (mutex-lock! completion))
  (check (mutex-state completion) (current-thread))
  (if (< returns 3) (saved 'reentered))
  (mutex-unlock! completion))
(display "REQUEST-SERVICE-PASS public=64 multi-shot=3 retained-completion-owner\n")

;; Deterministic implementation histories, replay and deletion shrinking.
;; This tests the real service/GC boundary; QNT owns competing schedules.
(let ((seed 173) (actions 0))
  (define (next)
    (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
    seed)
  (define (replay history mutation?)
    (let* ((completion (make-mutex))
           (calls 0)
           (valid? #t)
           (adopted? #f)
           (request (macro-make-thread-request
                     (current-thread)
                     (lambda () (set! calls (+ calls 1)) 'payload)
                     completion 'queued #f)))
      (mutex-lock! completion)
      (for-each
       (lambda (action)
         (set! actions (+ actions 1))
         (case action
           ((service)
            ;; Calibrate the property against a real state corruption at the
            ;; implementation boundary, not a different expected call count.
            ;; Removing terminal admission lets the actual service function
            ;; execute again and release the later owner's completion mutex.
            (if (and mutation? adopted?)
                (macro-thread-request-state-set! request 'queued))
            (##thread-intr-service! request)
            (if (not adopted?)
                (begin (mutex-lock! completion) (set! adopted? #t))))
           ((gc) (##gc)))
         (set! valid?
               (and valid?
                    (eq? (macro-thread-request-target request) (current-thread))
                    (<= calls 1)))
         (if adopted?
             (set! valid?
                   (and valid?
                        (eq? (mutex-state completion) (current-thread))
                        (eq? (macro-thread-request-result request) 'payload)))))
       history)
      (if (eq? (mutex-state completion) (current-thread))
          (mutex-unlock! completion))
      valid?))
  (let trials ((n 0))
    (if (< n 12)
        (let ((history
               (let make ((i 0))
                 (if (= i 12) '()
                     (cons (if (= (modulo (next) 3) 0) 'gc 'service)
                           (make (+ i 1)))))))
          (check (replay history #f) #t)
          (check (replay history #f) #t)
          (trials (+ n 1)))))
  (let shrink ((prefix '()) (rest '(gc service gc service gc)))
    (if (null? rest)
        (let ((minimal (reverse prefix)))
          (check minimal '(service service))
          (check (replay minimal #t) #f)
          (check (replay minimal #f) #t)
          (display "REQUEST-SERVICE-PBT-PASS seed=173 cases=12 replayed deletion-shrink=5-to-2 production-pass\n"))
        (let ((candidate (append (reverse prefix) (cdr rest))))
          (if (not (replay candidate #t))
              (shrink prefix (cdr rest))
              (shrink (cons (car rest) prefix) (cdr rest)))))))

;; A blocked requester can itself be a service activation. Its child request
;; must survive GC, and a target-side escape must retain the existing native
;; thread termination / abandoned-mutex protocol, rather than invent a reply.
(let* ((inner
        (thread-start!
         (make-thread
          (lambda ()
            (with-exception-catcher
             (lambda (e) (if (eq? e 'service-escape) 'caught (raise e)))
             (lambda () (thread-receive 5 'timeout)))))))
       (outer
        (thread-start!
         (make-thread (lambda () (thread-receive 5 'timeout)))))
       (result
        (thread-interrupt!
         outer
         (lambda ()
           (let ((value (thread-interrupt!
                         inner
                         (lambda () (##gc) (vector 'nested (current-thread))))))
             (check (vector-ref value 0) 'nested)
             (check (eq? (vector-ref value 1) inner) #t)
             (with-exception-catcher
              (lambda (e)
                (if (abandoned-mutex-exception? e) 'abandoned (raise e)))
              (lambda ()
                (thread-interrupt! inner (lambda () (raise 'service-escape))))))))))
  (check result 'abandoned)
  (check (thread-join! inner 5 'timeout) 'caught)
  (thread-send outer 'stop)
  (check (thread-join! outer 5 'timeout) 'stop))
(display "REQUEST-SERVICE-NESTED-PASS child-gc target-escape abandonment parent-result\n")

;; Actual owner death precedes a late multi-shot return. Reviving Scheme
;; control does not revive the dead activation's physical completion rights.
(let* ((completion (make-mutex))
       (request #f)
       (saved #f)
       (back #f)
       (recovering? #f)
       (target
        (make-thread
         (lambda ()
           (with-exception-catcher
            (lambda (e) (if (eq? e 'retained-escape) 'escaped (raise e)))
            (lambda ()
              (##thread-intr-service! request)
              (if recovering? (back 'resumed) 'unexpected-return)))))))
  (set! request
        (macro-make-thread-request
         target
         (lambda ()
           (let ((value (call/cc (lambda (k) (set! saved k) (raise 'retained-escape)))))
             (##gc)
             value))
         completion 'queued #f))
  (mutex-lock! completion #f target)
  (thread-start! target)
  (check (thread-join! target 5 'timeout) 'escaped)
  (check (mutex-state completion) 'abandoned)
  ;; The baseline mutex slow path does not consistently raise on a mutex
  ;; already abandoned before acquisition. Test physical ownership directly.
  (with-exception-catcher
   (lambda (e) (if (abandoned-mutex-exception? e) #t (raise e)))
   (lambda () (mutex-lock! completion)))
  (check (mutex-state completion) (current-thread))
  (set! recovering? #t)
  (check (call/cc (lambda (k) (set! back k) (saved 'late))) 'resumed)
  (check (list (macro-thread-request-state request)
               (macro-thread-request-result request)
               (eq? (mutex-state completion) (current-thread)))
         '(abandoned #f #t))
  (mutex-unlock! completion))
(display "REQUEST-SERVICE-DEAD-OWNER-PASS retained-continuation no-late-result new-owner-preserved\n")
