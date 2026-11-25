#! /bin/sh
":";THISDIR="`dirname $0`";GSI="${GAMBIT_BOOT_GSI:-$THISDIR/../gsi/gsi}";if test "`basename $0`" = "igsc.scm" ; then exec "$GSI" -:dar,=$THISDIR/.. -f "$0" "$@"; else GSI="${GAMBIT_BOOT_GSI:-$THISDIR/gsi/gsi}";exec "$GSI" -:dar,=$THISDIR -f "$0" "$@"; fi

;;;============================================================================

;;; File: "igsc.scm"

;;; Copyright (c) 1994-2026 by Marc Feeley, All Rights Reserved.

;;;----------------------------------------------------------------------------

;; This is a drop-in replacement for gsc-boot, which is the Gambit
;; Scheme compiler used to compile the Gambit system.  It has the
;; advantage of executing the whole compiler with all type checking
;; turned on, which is useful to debug the compiler.  Also, it only
;; requires a working Gambit interpreter (gsi), preferably a recent
;; version.
;;
;; To bootstrap Gambit using igsc.scm, from the root directory do:
;;
;;   cp gsc/igsc.scm gsc-boot
;;   make bootclean
;;   make

;;;----------------------------------------------------------------------------


(define-macro (at-expansion-time expr) (eval expr) '(begin))

(at-expansion-time (define ##compilation-options '()))

;; (command-line) is the SRFI-193 script line, which is ("") here.
;; Copying it erases -c and the source file, so ##main-gsi/gsc sees no
;; arguments and blocks in the REPL.  The host argv is
;; gsi -:dar -f igsc.scm -:~~... -f -c -o out file.scm.  Keep only the
;; arguments after this script, and drop runtime -: options.

(define (igsc-runtime-option? arg)
  (and (string? arg)
       (>= (string-length arg) 2)
       (string=? (substring arg 0 2) "-:")))

(define (igsc-script-arg? arg)
  (and (string? arg)
       (let ((base (path-strip-directory arg)))
         (or (string=? base "igsc.scm")
             (string=? base "gsc-boot")))))

(let* ((cl ##processed-command-line)
       (tail
        (let loop ((rest (cdr cl)))
          (cond ((or (null? rest) (null? (cdr rest)))
                 (cdr cl))
                ((and (string? (car rest))
                      (string=? (car rest) "-f")
                      (igsc-script-arg? (cadr rest)))
                 (cddr rest))
                (else
                 (loop (cdr rest)))))))
  ;; argv[0] is the gsi binary, so ##command-name is "gsi" and
  ;; ##main-gsi/gsc takes the interpreter.  Name this invocation gsc.
  (set! ##processed-command-line
        (cons "gsc"
              (let strip ((rest tail) (rev '()))
                (cond ((null? rest)
                       (reverse rev))
                      ((igsc-runtime-option? (car rest))
                       (strip (cdr rest) rev))
                      (else
                       (strip (cdr rest) (cons (car rest) rev))))))))

;; command-name and command-args must consume this same canonical invocation.
(##script-command-line-set! #f)

(display "compiler-args ")
(write (cdr ##processed-command-line))
(newline)
(force-output)

;; normalize program name

(set! ##processed-command-line
      (cons (path-normalize (car ##processed-command-line))
            (cdr ##processed-command-line)))

;;;----------------------------------------------------------------------------

(define gsc-modules '(
"_utils"
"_source"
"_parms"
"_env"
"_ptree1"
"_ptree2"
"_gvm"
"_back"
"_front"
"_prims"
"_assert"
"_asm"
"_x86"
"_arm"
"_riscv"
"_codegen"
"_t-univ-1"
"_t-univ-2"
"_t-univ-3"
"_t-univ-4"
"_t-cpu-abstract-machine"
"_t-cpu-primitives"
"_t-cpu-object-desc"
"_t-cpu-utils"
"_t-cpu-backend-x86"
"_t-cpu-backend-arm"
"_t-cpu-backend-riscv"
"_t-cpu"
"_t-c-1"
"_t-c-3"
"_t-c-2"
"_gsclib"
"_gsc"
"_gscdebug"
))

(define (load-from-root dir)
  (lambda (base)
    (with-output-to-port
        (current-error-port)
      (lambda ()
        (let ((file (string-append "~~/" dir base ".scm")))
          (display "loading ")
          (write file)
          (newline)
          (force-output)
          (load file)
          (display "loaded ")
          (write file)
          (newline)
          (force-output))))))

;;;----------------------------------------------------------------------------

(eval '(begin
        (##namespace ("c#"))
        (##include "~~/lib/header.scm")))

((load-from-root "gsc/") "_host")

;; use custom absent object otherwise the interpreter gets confused

(define c#absent-object (string->symbol "#<absent>")) ;; (##type-cast -6 2)

(for-each (load-from-root "gsc/") gsc-modules)

(eval '(##namespace ("")))

(display "compiler-main")
(newline)
(force-output)

(##main-gsi/gsc)

;;;----------------------------------------------------------------------------
