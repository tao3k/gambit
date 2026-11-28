;;; Moving-GC probe. The handler reports its own demand. The fill stops
;;; two words under that demand, so the call misses the fast grant and can
;;; collect. The label and the selected value are heap vectors.

(declare (extended-bindings) (not safe))

(c-declare "extern int ___rest_observation_body(void *actor);
extern ___WORD ___rest_observation_room(___processor_state);
extern ___WORD ___rest_observation_settled(___processor_state);
extern ___WORD ___rest_observation_last_demand(___WORD *, ___WORD *);
extern ___WORD ___rest_observation_last_entry_room(void);
extern void ___rest_observation_reset_admission(void);")

(define native-body-entry?
  (c-lambda () bool "___result = ___rest_observation_body(___PSTATE);"))

(define room
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_room(___ps));"))

(define settled
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_settled(___ps));"))

(define reset-admission
  (c-lambda () void "___rest_observation_reset_admission();"))

(define handler-words
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_last_demand(0, 0));"))

(define handler-entry-room
  (c-lambda () scheme-object
    "___result = ___FIX(___rest_observation_last_entry_room());"))

(define entry-count 0)
(define sink #f)
(define pad-index 0)
(define large-step #f)
(define small-step #f)
(define one-word-string? #f)
(define admission-overhead 0)

(define (body label key tail)
  (let ((observed (native-body-entry?)))
    (set! entry-count (+ entry-count 1))
    (vector observed label key tail)))

(define (ordinary label . tail)
  (body label #f tail))

(define (keyword-rest label #!key (flag #f) . tail)
  (body label flag tail))

(define (rest-keyword label #!rest tail #!key (flag #f))
  (body label flag tail))

(define (has? obj tail)
  (and (pair? tail)
       (or (eq? (car tail) obj) (has? obj (cdr tail)))))

(define (ordinary-shape label . tail) tail)
(define (keyword-shape label #!key (flag #f) . tail) (cons flag tail))
(define (rest-shape label #!rest tail #!key (flag #f)) (cons flag tail))

(define (prepare-steps)
  (let ((before (room)))
    (set! pad-index (+ pad-index 1))
    (set! sink (##cons pad-index sink))
    (let ((after (room)))
      (if (not (and (>= before 0) (> before after)))
          (error "moving rest allocation was not visible" before after))
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
              (error "moving rest has no one-word allocation"
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

(define (admitted-demand thunk)
  (reset-admission)
  (let ((before (room)))
    (thunk)
    (let ((words (handler-words))
          (entry (handler-entry-room)))
      (if (not (and (> words 0) (>= before 0) (>= entry 0) (>= before entry)))
          (error "moving rest handler rejected the demand" words before entry))
      (set! admission-overhead (- before entry))
      words)))

(let* ((mode (or (string->number (getenv "GAMBIT_SMP_REST_FORM" "1"))
                 (error "invalid moving rest form")))
       (label (vector 'caller-root))
       (selected (vector 'selected))
       (marker (vector 'marker))
       (words (admitted-demand
               (lambda ()
                 (case mode
                   ((1) (ordinary-shape label selected))
                   ((2) (rest-shape label flag: marker selected))
                   ((3) (keyword-shape label flag: marker selected))))))
       (target (+ words admission-overhead -2)))
  (if (not (> words 2)) (error "moving rest demand is too small" words))
  (prepare-steps)
  (if (not (reach target))
      (error "moving rest missed the collection tail" mode (room) (settled) target))
  (reset-admission)
  (let ((result (case mode
                  ((1) (ordinary label selected))
                  ((2) (rest-keyword label flag: marker selected))
                  ((3) (keyword-rest label flag: marker selected)))))
    (if (not (and (= entry-count 1)
                  (vector? result)
                  (eq? label (vector-ref result 1))
                  (eq? (if (= mode 1) #f marker) (vector-ref result 2))
                  (pair? (vector-ref result 3))
                  (if (= mode 2)
                      (has? selected (vector-ref result 3))
                      (eq? selected (car (vector-ref result 3))))))
        (error "moving rest did not deliver once with the expected roots"
               mode entry-count
               (and (vector? result) (vector-ref result 2))
               (and (vector? result) (vector-ref result 3))))
    (write (list 'NATIVE-MOVING-REST mode entry-count))
    (newline)))
