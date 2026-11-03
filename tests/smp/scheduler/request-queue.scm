;;; Both real C queue entries must become detached before Scheme can reroute.
(##namespace ("gambit#tests#smp#scheduler#request-queue#" detached?))
(define detached?
  (c-lambda (scheme-object scheme-object) bool #<<c-end
___processor_state ps = ___PSTATE;
___SCMOBJ first, second;
___EXT(___raise_high_level_interrupt_pstate)(ps, ___arg1);
___EXT(___raise_high_level_interrupt_pstate)(ps, ___arg2);
first = ___EXT(___get_next_high_level_interrupt_pstate)(ps);
___result = first == ___arg1 && ___VECTORELEM(first, 0) == ___NUL;
second = ___EXT(___get_next_high_level_interrupt_pstate)(ps);
___result = ___result && second == ___arg2
             && ___VECTORELEM(second, 0) == ___NUL
             && ___EXT(___get_next_high_level_interrupt_pstate)(ps) == ___NUL;
c-end
))
(if (not (detached? (vector '() #f) (vector '() #f)))
    (error "C queue did not transfer detached ownership"))
(display "REQUEST-QUEUE-PASS source-head-tail detached-next sole-consumer\n")
