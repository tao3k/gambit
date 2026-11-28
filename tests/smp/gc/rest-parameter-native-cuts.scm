;;; Compiled probe for the physical boundary, caller chain and section race.
;;; The runtime observes its own geometry and locking.

(declare (extended-bindings) (not safe))

(c-declare "extern void ___rest_observation_arm_boundary(void) __attribute__((weak_import));
extern ___WORD ___rest_observation_room(___processor_state);
extern ___WORD ___rest_observation_settled(___processor_state);
extern ___WORD ___rest_observation_last_demand(___WORD *, ___WORD *);
extern ___WORD ___rest_observation_last_entry_room(void);
extern void ___rest_observation_reset_admission(void);
extern ___WORD ___rest_observation_demand(___WORD, ___WORD);
extern int ___rest_observation_arm_section_contest(___processor_state, ___WORD) __attribute__((weak_import));
extern int ___rest_observation_open(const char *);
extern int ___rest_observation_case(unsigned long long);
extern int ___rest_observation_case_end(void);
extern void ___rest_observation_arm_extend_join(int) __attribute__((weak_import));
extern void ___rest_observation_arm_admission_sections(int) __attribute__((weak_import));")
(define arm-boundary
  (c-lambda () void
    "if (___rest_observation_arm_boundary) ___rest_observation_arm_boundary();"))

(define room
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_room(___ps));"))

(define settled
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_settled(___ps));"))

(define admission-overhead 0)

(define reset-admission
  (c-lambda () void "___rest_observation_reset_admission();"))

(define handler-words
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_last_demand(0, 0));"))

(define handler-entry-room
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_last_entry_room());"))

(define (admitted-demand thunk)
  (reset-admission)
  (let ((before (room)))
    (thunk)
    (let ((words (handler-words))
          (entry (handler-entry-room)))
      (if (not (and (> words 0) (>= before 0) (>= entry 0) (>= before entry)))
          (error "rest probe handler rejected the demand" words before entry))
      (set! admission-overhead (- before entry))
      words)))

(define retained '())
(define pads #f)
(define pad-index 0)
(define large-step #f)
(define small-step #f)

(define one-word-string? #f)
(define sink #f)
(define anchors (vector #f #f))

(define (prepare-steps)
  (let ((before (room)))
    (set! pad-index (+ pad-index 1))
    (set! sink (##cons pad-index sink))
    (let ((after (room)))
      (if (not (and (>= before 0) (> before after)))
          (error "rest probe allocation was not visible" before after))
      (set! large-step (- before after))))
  (set! sink (make-string 0))
  (set! sink (##box sink))
  (let* ((string-before (room))
         (_string (set! sink (make-string 0)))
         (string-after (room))
         (_box (set! sink (##box sink)))
         (box-after (room))
         (string-cost (- string-before string-after))
         (box-cost (- string-after box-after)))
    (set! one-word-string? (= string-cost 1))
    (set! small-step
          (if (or one-word-string? (= box-cost 1))
              1
              (error "rest probe has no one-word allocation"
                     large-step string-cost box-cost)))))

(define (reach target)
  (let loop ((left (room)))
    (let* ((here (room))
           (gap (and (>= here 0) (- here target))))
      (cond ((eqv? (settled) target) #t)
            ((or (not gap) (<= gap 0) (< gap small-step) (negative? left)) #f)
            (else
             (let ((before here))
               (if (> gap large-step)
                   (begin
                     (set! pad-index (+ pad-index 1))
                     (set! sink (##cons pad-index sink)))
                   (set! sink (if one-word-string? (make-string 0) (##box sink))))
               (let ((after (room)))
                 (if (not (and (>= after 0) (< after before) (<= (- before after) gap)))
                     #f
                     (loop (+ left (- after before)))))))))))

(define section-changed?
  (c-lambda () scheme-object "
    static void *first;
    if (!first) first = ___ps->mem.stack_msection_;
    ___result = ___BOOLEAN(___ps->mem.stack_msection_ != first);
  "))

(define (parameter name)
  (or (string->number (getenv name "0")) (error "invalid rest probe parameter" name)))

(define (ordinary label . tail)
  (cons label tail))

(define (keyword-rest label #!key flag . tail)
  (cons label (cons flag tail)))

(define (rest-keyword label #!rest tail #!key flag)
  (cons label (cons flag tail)))

(define (arguments n)
  (let loop ((i n) (out '()))
    (if (= i 0) out (loop (- i 1) (cons i out)))))

(define (invoke form label payload)
  (let* ((proc (case form ((1) ordinary) ((2) rest-keyword) ((3) keyword-rest)))
         (actual (apply proc label payload)))
    (if (or (not (pair? actual)) (not (eq? (car actual) label)))
        (error "rest probe lost the caller's argument"))
    actual))

(define (allow-heap-short thunk)
  (with-exception-catcher
   (lambda (exn)
     (if (heap-overflow-exception? exn) #f (raise exn)))
   thunk))

(define (boundary form short?)
  (let* ((label (vector 'physical-boundary))
         (call (lambda ()
                 (case form
                   ((1) (ordinary label 1 2 3))
                   ((2) (rest-keyword label flag: 2))
                   ((3) (keyword-rest label flag: 1 2 3))
                   (else (error "unknown rest form" form)))))
         (words (admitted-demand call))
         (target (+ words admission-overhead (if short? -1 0))))
    (prepare-steps)
    (arm-boundary)
    (with-exception-catcher
     (lambda (exn)
       (if (and short? (heap-overflow-exception? exn)) #f (raise exn)))
     (lambda ()
       (if (not (reach target))
           (error "rest probe missed the physical boundary" form short? (room) (settled) target small-step words admission-overhead))
       (reset-admission)
       (let ((actual (call)))
         (if (and (not short?)
                  (or (not (pair? actual)) (not (eq? (car actual) label))))
             (error "rest probe lost the caller's argument"))
         actual)))))

(define stack-words
  (c-lambda () scheme-object "
    ___WORD *fp = ___ps->context ? ___ps->context->fp : 0;
    ___WORD *limit = ___ps->mem.alloc_stack_limit_;
    if (!fp || !limit || fp < limit) ___result = ___FIX(-1);
    else ___result = ___FIX((___WORD)(fp - limit));
  "))

(define (frame-words)
  (let ((before (stack-words)))
    (- before ((lambda () (stack-words))))))

(define (caller-chain)
  (let* ((label (vector 'caller-chain))
         (words (admitted-demand (lambda () (ordinary label 1 2))))
         (target (+ words admission-overhead -2))
         (frame (frame-words))
         (budget (and (> frame 0) (quotient (stack-words) frame))))
    (if (not budget) (error "rest probe could not measure a stack frame" frame))
    (if (not (> words 2)) (error "rest probe chain demand is too small" words))
    (prepare-steps)
    (arm-boundary)
    (with-exception-catcher
     (lambda (exn)
       (if (heap-overflow-exception? exn) #f (raise exn)))
     (lambda ()
       (let descend ((depth 0))
         (cond ((section-changed?)
                (if (not (reach target))
                    (error "rest probe missed the cross-section heap tail" (room) (settled)))
                (ordinary label 1 2))
               ((<= (stack-words) frame)
                (error "rest probe did not cross a stack section" depth (stack-words) frame))
               (else
                (let ((saved (descend (+ depth 1))))
                  (set! sink depth)
                  saved))))))))


(define rest-demand
  (c-lambda (scheme-object scheme-object) scheme-object
    "___result = ___FIX(___rest_observation_demand(___INT(___arg1), ___INT(___arg2)));"))

(define arm-section-contest
  (c-lambda (scheme-object) bool
    "if (___INT(___arg1) && ___rest_observation_open(0) && !___rest_observation_case(11)) {
       ___rest_observation_case_end();
       ___rest_observation_case(11);
     }
     ___result = ___rest_observation_arm_section_contest ? ___rest_observation_arm_section_contest(___ps, ___INT(___arg1)) : 0;"))

(define contest-symbol?
  (c-lambda () bool
    "___result = ___rest_observation_arm_section_contest ? 1 : 0;"))

(define arm-extend-join
  (c-lambda (scheme-object) void
    "if (___rest_observation_arm_extend_join) ___rest_observation_arm_extend_join(___INT(___arg1));"))

(define arm-admission-sections
  (c-lambda (scheme-object) void
    "if (___rest_observation_arm_admission_sections) ___rest_observation_arm_admission_sections(___INT(___arg1));"))

(define (section-race)
  (if (< (##current-vm-processor-count) 2)
      (error "section race requires two active processors"))
  (let* ((words (admitted-demand (lambda () (ordinary 'section-race 1 2))))
         (pending 8000)
         (need (rest-demand pending 2))
         (gate (make-mutex 'rest-race))
         (ready 0)
         (places (vector -1 -1 -1 -1))
         (rooms (vector -1 -1 -1 -1))
         (use-contest (contest-symbol?))
         (armed #f)
         (measured #f)
         (shortened 0)
         (failed #f))
    (define (arguments)
      (let loop ((i pending) (out '()))
        (if (= i 0) out (loop (- i 1) (cons i out)))))
    (define (chain n)
      (let loop ((i n) (out '()))
        (if (= i 0) out (loop (- i 1) (cons i out)))))
    (define (call-on carrier)
      (let* ((args (arguments))
             (kept (chain 12000)))
        (vector-set! places carrier (##current-processor-id))
        (vector-set! rooms carrier (settled))
        (mutex-lock! gate)
        (set! ready (+ ready 1))
        (mutex-unlock! gate)
        (let wait ()
          (mutex-lock! gate)
          (let ((both (= ready 2)))
            (mutex-unlock! gate)
            (if (not both)
                (wait)
                (when (not use-contest)
                  (mutex-lock! gate)
                  (let ((measure (not armed)))
                    (if measure (set! armed #t))
                    (mutex-unlock! gate)
                    (if measure
                        (begin
                          (arm-extend-join 2)
                          (arm-admission-sections 1)
                          (prepare-steps)
                          (mutex-lock! gate)
                          (set! measured #t)
                          (mutex-unlock! gate))))
                  (let spin ()
                    (mutex-lock! gate)
                    (let ((ready-steps measured))
                      (mutex-unlock! gate)
                      (if (not ready-steps)
                          (begin (thread-sleep! 0.001) (spin)))))
                  (let ((target (- (* pending large-step) 1))
                        (local '()))
                    (let fill ((stalls 0))
                      (let ((here (room)))
                        (cond ((and (>= here 0) (<= here target)) #t)
                              ((or (negative? here) (>= stalls 2))
                               (mutex-lock! gate)
                               (set! failed #t)
                               (set! shortened (+ shortened 1))
                               (mutex-unlock! gate)
                               (error "section race could not reach the demand tail"
                                      here (settled) target))
                              (else
                               (set! local (##cons local local))
                               (fill (if (< (room) here) 0 (+ stalls 1)))))))
                    (vector-set! anchors carrier local))
                  (mutex-lock! gate)
                  (set! shortened (+ shortened 1))
                  (mutex-unlock! gate)
                  (let spin ()
                    (mutex-lock! gate)
                    (let ((n shortened) (bad failed))
                      (mutex-unlock! gate)
                      (cond (bad (error "section race partner failed"))
                            ((< n 2)
                             (thread-sleep! 0.001)
                             (spin)))))))))
        (vector-set! places (+ carrier 2) (##current-processor-id))
        (vector-set! rooms (+ carrier 2) (settled))
        (with-exception-catcher
         (lambda (exn)
           (if (heap-overflow-exception? exn) #f (raise exn)))
         (lambda ()
           (apply ordinary (cons (vector 'section-race carrier kept) args))))))
    (if (not (and (> words 2) (> need words)))
        (error "section race demand is too small" words need))
    (let ((first (make-thread (lambda () (call-on 0))))
          (second (make-thread (lambda () (call-on 1)))))
      (if (and use-contest (not (arm-section-contest need)))
          (error "section race observer is not active"))
      ;; Starting on a processor does not prevent a later work steal.
      (##thread-pin! first (##processor 0))
      (##thread-pin! second (##processor 1))
      (##thread-start-on! 0 first)
      (##thread-start-on! 1 second)
      (thread-join! first)
      (thread-join! second)
      (if use-contest
          (arm-section-contest 0)
          (begin
            (arm-extend-join 0)
            (arm-admission-sections 0)))
      (if (not (equal? (vector->list places) '(0 1 0 1)))
          (error "section race did not stay on its two carriers" places rooms)))))

(let ((item (parameter "GAMBIT_SMP_REST_ITEM"))
      (form (parameter "GAMBIT_SMP_REST_FORM"))
      (short (parameter "GAMBIT_SMP_REST_SHORT")))
  (case item
    ((6) (boundary form (= short 1)))
    ((7) (caller-chain))
    ((9) (section-race))
    (else (error "unknown native rest cut" item)))
  (write (list 'NATIVE-REST-CUT item form short))
  (newline))
