;;; Stale generation and close-while-pinned controls on the loaded GSI.
;;; Status words are the image's own ___rest_status values.

(declare (extended-bindings) (not safe))

(c-declare "void ___rest_stale_probe(___processor_state);
void ___rest_reuse_probe(___processor_state);
extern ___WORD ___rest_stale_pin_status;
extern ___WORD ___rest_stale_load_delta;
extern ___WORD ___rest_stale_still_pinned;
extern ___WORD ___rest_stale_incarnation_status;
extern ___WORD ___rest_stale_incarnation_loads;
extern ___WORD ___rest_reuse_status;
extern ___WORD ___rest_reuse_pin;
extern ___WORD ___rest_reuse_loads;
extern ___WORD ___rest_close_status;
extern ___WORD ___rest_close_pin;
extern ___WORD ___rest_close_loads;")

(define stale (c-lambda () void "___rest_stale_probe(___PSTATE);"))
(define reuse (c-lambda () void "___rest_reuse_probe(___PSTATE);"))
(define pin (c-lambda () scheme-object "___result=___FIX(___rest_stale_pin_status);"))
(define loads (c-lambda () scheme-object "___result=___FIX(___rest_stale_load_delta);"))
(define still (c-lambda () scheme-object "___result=___FIX(___rest_stale_still_pinned);"))
(define incarn (c-lambda () scheme-object "___result=___FIX(___rest_stale_incarnation_status);"))
(define incarn-loads (c-lambda () scheme-object "___result=___FIX(___rest_stale_incarnation_loads);"))
(define reuse-status (c-lambda () scheme-object "___result=___FIX(___rest_reuse_status);"))
(define reuse-pin (c-lambda () scheme-object "___result=___FIX(___rest_reuse_pin);"))
(define reuse-loads (c-lambda () scheme-object "___result=___FIX(___rest_reuse_loads);"))
(define close-status (c-lambda () scheme-object "___result=___FIX(___rest_close_status);"))
(define close-pin (c-lambda () scheme-object "___result=___FIX(___rest_close_pin);"))
(define close-loads (c-lambda () scheme-object "___result=___FIX(___rest_close_loads);"))

(stale)
(write (list 'NATIVE-REST-STALE (pin) (loads) (still) (incarn) (incarn-loads)))
(newline)
(reuse)
(write (list 'NATIVE-REST-REUSE (reuse-status) (reuse-pin) (reuse-loads)
             (close-status) (close-pin) (close-loads)))
(newline)
