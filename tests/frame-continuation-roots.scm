(c-declare "#include \"mem.h\"\n#include \"rc.h\"\n#include \"root.h\"")
;; Select the scan executor census through the VM's internal atomic request.
;; The frozen root population and all native cleanup owners remain unchanged.
((c-lambda () void #<<c-end
___virtual_machine_state vm = ___VMSTATE_FROM_PSTATE(___ps);
___WORD count = vm->processor_count>1 ? vm->processor_count-1 : 1;
___WORD_STORE_RELEASE(&___COLLECTION(vm).requested_workers,count);
c-end
))
;;; A wide live frame under real map. Public capture/return use the same winding
;;; protocol as call/cc; retain the raw continuation to audit both consumers.
(define native-thirty (c-lambda () int "___result = 30;"))
(define wide-saved #f)
(define wide-exit #f)
(define wide-visits '())
(define wide-winds '())
(define wide-native-calls 0)
(define forced-collections 0)
(define (collect-and-record)
  ;; Count only completed forced collections, including collections after a
  ;; captured frame has been materialized and after each resumed call returns.
  (##gc)
  (set! forced-collections (+ forced-collections 1)))
(define audited-frames 0)
(define audited-wide-slots 0)
(define (audit-roots cont)
  (let loop ((p cont) (fuel 256))
    (if p
        (begin
          (if (= fuel 0) (error "unbounded continuation chain"))
          (let* ((fs (##continuation-fs p))
                 (c-ret (##continuation-ret p))
                 (c-link (##continuation-link p))
                 (before (let slots ((i 1))
                           (if (> i fs) '()
                               (cons (##continuation-slot-live? p i)
                                     (slots (+ i 1))))))
                 (before-vals (let slots ((i 1) (bits before))
                                (if (null? bits) '()
                                    (cons (if (car bits)
                                              (##continuation-ref p i)
                                              #f)
                                          (slots (+ i 1) (cdr bits))))))
                 ;; Materialization can collect. p and before are ordinary roots.
                 (frame (##continuation-frame p)))
            (if (not (= fs (##frame-fs frame))) (error "frame extent changed"))
            (if (not (eq? c-ret (##frame-ret frame)))
                (error "frame return label disagreement"))
            (if (not (= c-link (##frame-link frame)))
                (error "frame link disagreement" c-link (##frame-link frame)))
            (let slots ((i 1) (bits before) (vals before-vals))
              (if (pair? bits)
                  (begin
                    (if (not (eq? (car bits) (##frame-slot-live? frame i)))
                        (error "root consumer disagreement" fs i))
                    (if (and (car bits)
                             (not (= i c-link))
                             (not (eq? (car vals) (##frame-ref frame i))))
                        (error "frame slot value disagreement" fs i c-link))
                    (if (and (> i 64) (car bits))
                        (set! audited-wide-slots (+ audited-wide-slots 1)))
                    (slots (+ i 1) (cdr bits) (cdr vals)))))
            (set! audited-frames (+ audited-frames 1)))
          (loop (##continuation-next p) (- fuel 1))))))
(define (wide-collect start)
  (call/cc (lambda (exit) (set! wide-exit exit) (start))))
(define (with-wide-roots thunk r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23 r24 r25 r26 r27 r28 r29 r30 r31 r32 r33 r34 r35 r36 r37 r38 r39 r40 r41 r42 r43 r44 r45 r46 r47 r48 r49 r50 r51 r52 r53 r54 r55 r56 r57 r58 r59 r60 r61 r62 r63 r64 r65 r66 r67 r68 r69 r70 r71 r72 r73 r74 r75 r76 r77 r78 r79 r80)
  (let ((answer (thunk)))
    (collect-and-record)
    (cons answer (list (vector-ref r1 0) (vector-ref r2 0) (vector-ref r3 0) (vector-ref r4 0) (vector-ref r5 0) (vector-ref r6 0) (vector-ref r7 0) (vector-ref r8 0) (vector-ref r9 0) (vector-ref r10 0) (vector-ref r11 0) (vector-ref r12 0) (vector-ref r13 0) (vector-ref r14 0) (vector-ref r15 0) (vector-ref r16 0) (vector-ref r17 0) (vector-ref r18 0) (vector-ref r19 0) (vector-ref r20 0) (vector-ref r21 0) (vector-ref r22 0) (vector-ref r23 0) (vector-ref r24 0) (vector-ref r25 0) (vector-ref r26 0) (vector-ref r27 0) (vector-ref r28 0) (vector-ref r29 0) (vector-ref r30 0) (vector-ref r31 0) (vector-ref r32 0) (vector-ref r33 0) (vector-ref r34 0) (vector-ref r35 0) (vector-ref r36 0) (vector-ref r37 0) (vector-ref r38 0) (vector-ref r39 0) (vector-ref r40 0) (vector-ref r41 0) (vector-ref r42 0) (vector-ref r43 0) (vector-ref r44 0) (vector-ref r45 0) (vector-ref r46 0) (vector-ref r47 0) (vector-ref r48 0) (vector-ref r49 0) (vector-ref r50 0) (vector-ref r51 0) (vector-ref r52 0) (vector-ref r53 0) (vector-ref r54 0) (vector-ref r55 0) (vector-ref r56 0) (vector-ref r57 0) (vector-ref r58 0) (vector-ref r59 0) (vector-ref r60 0) (vector-ref r61 0) (vector-ref r62 0) (vector-ref r63 0) (vector-ref r64 0) (vector-ref r65 0) (vector-ref r66 0) (vector-ref r67 0) (vector-ref r68 0) (vector-ref r69 0) (vector-ref r70 0) (vector-ref r71 0) (vector-ref r72 0) (vector-ref r73 0) (vector-ref r74 0) (vector-ref r75 0) (vector-ref r76 0) (vector-ref r77 0) (vector-ref r78 0) (vector-ref r79 0) (vector-ref r80 0)))))
(define root-ids (let loop ((i 80) (xs '()))
                  (if (= i 0) xs (loop (- i 1) (cons i xs)))))
(define (wide-compute)
  (wide-exit
   (dynamic-wind
    (lambda () (set! wide-winds (cons 'before wide-winds)))
    (lambda ()
      (map (lambda (x)
             (set! wide-visits (cons x wide-visits))
             (apply with-wide-roots
                    (cons (lambda ()
                            (cond ((= x 2)
                                   (continuation-capture
                                    (lambda (k)
                                      (set! wide-saved k)
                                      (audit-roots k)
                                      (collect-and-record)
                                      (audit-roots k)
                                      2)))
                                  ((= x 3)
                                   (set! wide-native-calls (+ wide-native-calls 1))
                                   (collect-and-record)
                                   (native-thirty))
                                  (else 1)))
                          (map (lambda (i) (vector i)) root-ids))))
           '(1 2 3)))
    (lambda () (set! wide-winds (cons 'after wide-winds))))))
(define b0 (wide-collect wide-compute))
(define b1 (wide-collect (lambda () (continuation-return wide-saved 20))))
(define b2 (wide-collect (lambda () (continuation-return wide-saved 200))))
(define (expected middle)
  (list (cons 1 root-ids) (cons middle root-ids) (cons 30 root-ids)))
(if (not (and (equal? b0 (expected 2))
              (equal? b1 (expected 20))
              (equal? b2 (expected 200))
              (equal? wide-visits '(3 3 3 2 1))
              (equal? wide-winds '(after before after before after before))
              (= wide-native-calls 3)
              (= forced-collections 11)
              (> audited-frames 0) (> audited-wide-slots 0)))
    (error "wide frame continuation mismatch" b0 b1 b2 wide-visits
           wide-winds wide-native-calls audited-frames audited-wide-slots))
(let ((expected (getenv "GAMBIT_SMP_EXPECTED_PROCESSORS" #f)))
  (if (and expected
           (not (= (string->number expected) (##current-vm-processor-count))))
      (error "unexpected processor population" expected)))
;; Counts and wide-root coverage are asserted above. Keep the acceptance
;; transcript deterministic across valid frame-chain lengths and populations.

(if (not ((c-lambda () bool #<<c-end
___virtual_machine_state vm=___VMSTATE_FROM_PSTATE(___ps);
___return(___COLLECTION(vm).worker_count==(vm->processor_count>1 ? vm->processor_count-1 : 1) && ___COLLECTION(vm).participant_count==vm->processor_count);
c-end
))) (error "requested map worker/root split was not observed"))

;; Verify IEEE-754 flonum values survive multi-shot continuation capture/return
;; across forced GC under the unified FrameSpec decoder.
(let ((fp-saved #f))
  (define (fp-work x y z)
    (let* ((a (##fl+ x y))
           (b (##fl* a z))
           (mid (continuation-capture
                 (lambda (k)
                   (set! fp-saved k)
                   (##gc)
                   1.5))))
      (##gc)
      (##fl- (##fl* b mid) x)))
  (let* ((r0 (wide-collect (lambda () (wide-exit (fp-work 1.25 2.75 3.5)))))
         (r1 (wide-collect (lambda () (continuation-return fp-saved 2.5))))
         (r2 (wide-collect (lambda () (continuation-return fp-saved 4.0)))))
    (if (not (and (= r0 19.75) (= r1 33.75) (= r2 54.75)))
        (error "flonum continuation frame mismatch" r0 r1 r2))))

;; Verify dynamic module cohort pin/unpin refcount protocol.
(if (not ((c-lambda () bool #<<c-end
___WORD before = ___dyn_cohort_pinned_count();
___dyn_cohort_pin();
___WORD mid1 = ___dyn_cohort_pinned_count();
___dyn_cohort_pin();
___WORD mid2 = ___dyn_cohort_pinned_count();
___dyn_cohort_unpin();
___WORD mid3 = ___dyn_cohort_pinned_count();
___dyn_cohort_unpin();
___WORD after = ___dyn_cohort_pinned_count();
___return(mid1 == before + 1 && mid2 == before + 2 &&
          mid3 == before + 1 && after == before);
c-end
))) (error "dyn cohort pin protocol mismatch"))

(display "FRAME-CONTINUATION-ROOTS-PASS\nFORCED-GC-COMPLETE count=11\n")
