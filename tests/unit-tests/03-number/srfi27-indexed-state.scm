(include "#.scm")

;; These states come from the original indexed MRG32k3a initialization.
;; Cover each index axis, the top cached bit, and the unbounded fallback.
(define indexed-states
  '((0 0 #(1062452522 2961816100 342112271 2854655037 3321940838 3542344109))
    (0 1 #(2201928127 1089534031 2197944884 614974692 1546348754 1428003421))
    (1 0 #(3366385689 1784590529 942712179 1004147354 1448622337 3577622090))
    (1 1 #(3685827320 3417881304 1808930729 1779559468 2309667810 2176200141))
    (2147483648 2147483648
     #(2528219531 307955785 1995928044 1463288930 1956310259 119118416))
    (4294967295 4294967295
     #(1642517191 3282262004 1060904439 564637689 220789344 3782684230))
    (4294967296 0 #(1541417183 2620105258 2003721538 2818013371 2856265206 3941628513))
    (0 4294967296 #(4202712521 1028776743 456486496 2995389021 2140178150 2896754750))
    (0 79228162514264337593543950353
     #(2149939070 1245764948 1918294311 1560905652 550378821 4263233998))))

;; Separate source instances replay the checkpoint without sharing draw state.
(for-each
 (lambda (row)
   (let* ((source (make-random-source))
          (replay (make-random-source))
          (draw (random-source-make-integers source))
          (draw-replay (random-source-make-integers replay)))
     (random-source-pseudo-randomize! source (car row) (cadr row))
     (test-equal (caddr row) (random-source-state-ref source))
     (random-source-state-set! replay (random-source-state-ref source))
     (for-each (lambda (bound)
                 (test-eqv (draw bound) (draw-replay bound)))
               '(1 2 65 4096 65))
     (test-equal (random-source-state-ref source)
                 (random-source-state-ref replay))))
 indexed-states)

;; Invalid indices must leave the previously initialized source intact.
(let ((source (make-random-source)))
  (random-source-pseudo-randomize! source 1 1)
  (let ((state (random-source-state-ref source)))
    (test-error type-exception? (random-source-pseudo-randomize! source 'invalid 0))
    (test-error type-exception? (random-source-pseudo-randomize! source 0 0.0))
    (test-error range-exception? (random-source-pseudo-randomize! source -1 0))
    (test-error range-exception? (random-source-pseudo-randomize! source 0 -1))
    (test-equal state (random-source-state-ref source))))
