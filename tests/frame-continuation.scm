(c-declare "#include \"mem.h\"\n#include \"rc.h\"\n#include \"root.h\"")
;; Select the scan executor census through the VM's internal atomic request.
;; The frozen root population and all native cleanup owners remain unchanged.
((c-lambda () void #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
___WORD_STORE_RELEASE(&___COLLECTION(vm).requested_workers,1);
c-end
))
;;; End-to-end generated frame/ABI control: native suffix, GC, repeated restore.
(define native-thirty (c-lambda () int "___result = 30;"))
(define saved #f)
(define complete #f)
(define visits '())
(define winds '())
(define native-calls 0)
(define (collect start)
  (call/cc (lambda (exit) (set! complete exit) (start))))
(define (compute)
  (let ((answer
         (dynamic-wind
          (lambda () (set! winds (cons 'before winds)))
          (lambda ()
            (map (lambda (x)
                   (set! visits (cons x visits))
                   (cond ((= x 2)
                          (call/cc (lambda (k) (set! saved k) (##gc) 2)))
                         ((= x 3)
                          (set! native-calls (+ native-calls 1))
                          (##gc)
                          (native-thirty))
                         (else 10)))
                 '(1 2 3)))
          (lambda () (set! winds (cons 'after winds))))))
    (complete answer)))
(define a0 (collect compute))
(define a1 (collect (lambda () (saved 20))))
(define a2 (collect (lambda () (saved 200))))
(if (not (and (equal? a0 '(10 2 30))
              (equal? a1 '(10 20 30))
              (equal? a2 '(10 200 30))
              (equal? visits '(3 3 3 2 1))
              (equal? winds '(after before after before after before))
              (= native-calls 3)))
    (error "frame continuation mismatch" a0 a1 a2 visits winds native-calls))
(display "FRAME-CONTINUATION-PASS\n")

;; Collector reference repair must retain the table's index-algorithm owner.
;; Keep keys alive independently; this is not a weak-key-retention test.
(define index-keys
  (let loop ((i 80) (xs '()))
    (if (= i 0) xs (loop (- i 1) (cons (vector i) xs)))))
(define hash-calls 0)
(define scheme-index
  (make-table test: eq?
              hash: (lambda (key)
                      (set! hash-calls (+ hash-calls 1))
                      (vector-ref key 0))))
(define native-index (make-table test: eq?))
(for-each (lambda (key)
            (table-set! scheme-index key (vector-ref key 0))
            (table-set! native-index key (vector-ref key 0)))
          index-keys)
(define calls-before-gc hash-calls)
(##gc)
(if (not (= calls-before-gc hash-calls))
    (error "collector invoked Scheme hash callback"))
(for-each (lambda (key)
            (if (not (and (= (table-ref scheme-index key -1) (vector-ref key 0))
                          (= (table-ref native-index key -1) (vector-ref key 0))))
                (error "GC changed hash-index lookup")))
          index-keys)
(if (not (> hash-calls calls-before-gc))
    (error "Scheme lookup did not own its hash callbacks"))
(display "HASH-INDEX-OWNER-PASS\n")

(if (not ((c-lambda () bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
___return(___COLLECTION(vm).worker_count==1 && ___ROOT_UNION(vm)->participants==vm->processor_count);
c-end
))) (error "requested map worker/root split was not observed"))
