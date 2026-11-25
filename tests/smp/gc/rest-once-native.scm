;;; One delivery of a fresh activation, then the same record resumes again.
;;; The second status is the image's own duplicate code.

(declare (extended-bindings) (not safe))

(c-declare "void ___rest_once_probe(___processor_state);
int ___rest_observation_open(const char *);
int ___rest_observation_case(unsigned long long);
int ___rest_observation_case_end(void);
extern ___WORD ___rest_once_first;
extern ___WORD ___rest_once_second;
extern ___WORD ___rest_once_delta;
extern ___WORD ___rest_once_result;")

(define run
  (c-lambda () void
    "{ ___rest_observation_open(0);
       ___rest_observation_case(1);
       ___rest_once_probe(___PSTATE);
       ___rest_observation_case_end(); }"))

(define first (c-lambda () scheme-object "___result=___FIX(___rest_once_first);"))
(define second (c-lambda () scheme-object "___result=___FIX(___rest_once_second);"))
(define delta (c-lambda () scheme-object "___result=___FIX(___rest_once_delta);"))
(define result (c-lambda () scheme-object "___result=___FIX(___rest_once_result);"))

(run)
(write (list 'NATIVE-REST-ONCE (first) (second) (delta) (result)))
(newline)
