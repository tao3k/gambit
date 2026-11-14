;;; Caller-chain controls on the loaded GSI. Each refusal is the same
;;; predicate the chain uses before a frame load, and the load count stays zero.

(declare (extended-bindings) (not safe))

(c-declare "int ___rest_chain_control_probe(___processor_state, int, long *);")

(define probe
  (c-lambda (scheme-object) scheme-object
    "long loads=-1;
     int code=___rest_chain_control_probe(___PSTATE, ___INT(___arg1), &loads);
     ___result=___FIX(code*10+(int)loads);"))

(write (list 'NATIVE-CHAIN-CONTROL (probe 1) (probe 2) (probe 3)))
(newline)
