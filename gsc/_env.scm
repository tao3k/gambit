;;;============================================================================

;;; File: "_env.scm"

;;; Copyright (c) 1994-2021 by Marc Feeley, All Rights Reserved.

(include "fixnum.scm")

(include     "_envadt.scm")
(include-adt "_gvmadt.scm")
(include-adt "_ptreeadt.scm")
(include-adt "_sourceadt.scm")

;;;----------------------------------------------------------------------------

;;;; Environment manipulation and declaration handling module

;;;----------------------------------------------------------------------------

(define next-var-stamp #f)

(define (var-lexical-level var)
  (let ((bound (var-bound var)))
    (if (or (eq? bound #f) (eq? bound #t))
        0
        (let loop ((node bound) (n 0))
          (if node
              (loop (node-parent node)
                    (+ n (if (prc? node) 1 0)))
              n)))))


;; temporary variables are used to name intermediate values

(define (make-temp-var name)
  (make-var name #t (ptset-empty) (ptset-empty) #f #t))

;; special variable used to denote the return address of a procedure

(define ret-var '())
(define ret-var-set '())

;; special variable used to denote the pointer to the closed variables

(define closure-env-var '())

;; special variable used to denote empty slots

(define empty-var '())

(define (resize-var-list lst n)
  (let loop ((lst lst) (n n))
    (cond ((= n 0) lst)
          ((< n 0) (loop (cdr lst) (+ n 1)))
          (else    (loop (cons empty-var lst) (- n 1))))))

;; structure that represents environments:

(define make-global-environment #f)
(set! make-global-environment
  (lambda ()
    (env-frame #f '())))

(define (env-frame env vars)
  (vector
   ;; All functional views of the frame share the ordered list and, for a
   ;; global frame, its name index. Lexical frames keep the existing list.
   (cons vars
         (and (not env)
              (let ((index (make-table 'test: eq?)))
                (for-each
                 (lambda (var)
                   (let ((name (var-name var)))
                     (if (not (table-ref index name #f))
                         (table-set! index name var))))
                 vars)
                index)))
   ;; macro definitions
   '()
   ;; declarations
   (if env (env-decl-ref env) '())
   ;; namespace
   '()
   ;; parent env
   env
   ;; externals. This field is only used in the global environment, but many
   ;; functional setter functions assume `make-global-environment` and
   ;; `env-frame` return the same shape of object.
   (if env (env-externals-ref env) (make-table))))

(define (env-new-var! env name source)
  (let* ((glob (not (env-parent-ref env)))
         (var (make-var name (not glob) (ptset-empty) (ptset-empty) source #f))
         (frame (vector-ref env 0)))
    (if glob
        (table-set! (cdr frame) name var))
    (set-car! frame (cons var (car frame)))
    var))

(define (env-macro env name def)
  (let ((name* (or (and (not (full-name? name))
                        (env-namespace-lookup env name))
                   name)))
    (env-macros-set env (cons (cons name* def) (env-macros-ref env)))))

(define (env-macros-set env macro)
  (vector (vector-ref env 0)
          macro
          (env-decl-ref env)
          (env-namespace-ref env)
          (env-parent-ref env)
          (env-externals-ref env)))

(define (env-declare env d)
  (env-decl-set env (cons d (env-decl-ref env))))

(define (env-decl-set env decl)
  (vector (vector-ref env 0)
          (env-macros-ref env)
          decl
          (env-namespace-ref env)
          (env-parent-ref env)
          (env-externals-ref env)))

(define (env-namespace env n)
  (env-namespace-set env (cons n (env-namespace-ref env))))

(define (env-namespace-set env namespace)
  (vector (vector-ref env 0)
          (env-macros-ref env)
          (env-decl-ref env)
          namespace
          (env-parent-ref env)
          (env-externals-ref env)))

(define (env-vars-ref env)              (car (vector-ref env 0)))
(define (env-macros-ref env)            (vector-ref env 1))
(define (env-decl-ref env)              (vector-ref env 2))
(define (env-namespace-ref env)         (vector-ref env 3))
(define (env-parent-ref env)            (vector-ref env 4))
(define (env-externals-ref env)         (vector-ref env 5))

(define (env-frame-lookup-var env name)
  (let* ((frame (vector-ref env 0))
         (index (cdr frame)))
    (if index
        (table-ref index name #f)
        (let loop ((vars (car frame)))
          (and (pair? vars)
               (let ((var (car vars)))
                 (if (eq? (var-name var) name)
                     var
                     (loop (cdr vars)))))))))

(define (env-namespace-lookup env name)
  (let loop ((lst (env-namespace-ref env)))
    (if (pair? lst)
        (let* ((x (car lst))
               (space (car x))
               (aliases (cdr x)))
          (if (null? aliases)
              (make-full-name space name)
              (let ((a (assq name aliases)))
                (if a
                    (make-full-name space (cdr a))
                    (loop (cdr lst))))))
        #f)))

(define (env-namespace-lookup-both env name)
  (let loop ((lst (env-namespace-ref env)))
    (if (pair? lst)
        (let* ((x (car lst))
               (space (car x))
               (aliases (cdr x)))
          (if (null? aliases)
              (cons (make-full-name space name) x)
              (let ((a (assq name aliases)))
                (if a
                    (cons (make-full-name space (cdr a))
                          x)
                    (loop (cdr lst))))))
        #f)))


;; One index per macro-list object. The first binding in the list wins, matching
;; the previous left-to-right scan. A new list is a new binding generation, so
;; the index is not reused for a different list, parent, or namespace.
;; A generation that only conses onto an already indexed tail shares that tail
;; index. The new binding is an overlay and wins over the same name in the tail.
;; Long unindexed spines still build one table. Overlay chains flatten so a
;; lookup does not walk every generation.
(define macro-list-index (make-table 'test: eq? 'weak-keys: #t))
(define macro-index-miss (cons 'macro-index-miss '()))
(define macro-overlay-limit 32)

(define (macro-list-cached lst)
  (table-ref macro-list-index lst #f))

(define (macro-list-empty)
  (make-table 'test: eq?))

(define (macro-list-ref node name)
  (let loop ((node node))
    (cond ((table? node)
           (table-ref node name macro-index-miss))
          ((eq? (vector-ref node 1) name)
           (vector-ref node 2))
          (else
           (loop (vector-ref node 3))))))

(define (macro-list-flatten node)
  (let ((index (macro-list-empty)))
    (let loop ((node node))
      (cond ((table? node)
             (table-for-each
               (lambda (k v)
                 (if (eq? (table-ref index k macro-index-miss)
                          macro-index-miss)
                     (table-set! index k v)))
               node))
            (else
             (let ((name (vector-ref node 1)))
               (if (eq? (table-ref index name macro-index-miss)
                        macro-index-miss)
                   (table-set! index name (vector-ref node 2))))
             (loop (vector-ref node 3)))))
    index))

(define (macro-list-extend name value base)
  (let ((depth (if (table? base)
                   1
                   (+ 1 (vector-ref base 4)))))
    (if (> depth macro-overlay-limit)
        (let ((index (macro-list-flatten base)))
          (table-set! index name value)
          index)
        (vector 'macro-overlay name value base depth))))

(define (macro-list-prefix-length lst limit)
  (let loop ((lst lst) (n 0))
    (cond ((>= n limit) n)
          ((or (not (pair? lst)) (macro-list-cached lst)) n)
          (else (loop (cdr lst) (+ n 1))))))

(define (macro-list-suffix lst n)
  (if (= n 0)
      lst
      (macro-list-suffix (cdr lst) (- n 1))))

(define (macro-list-overlay-prefix lst base n)
  (if (= n 0)
      base
      (let ((rest (macro-list-overlay-prefix (cdr lst) base (- n 1))))
        (let ((head (car lst)))
          (macro-list-extend (car head) (cdr head) rest)))))

(define (macro-list-table macros)
  (or (table-ref macro-list-index macros #f)
      (let ((n (macro-list-prefix-length macros macro-overlay-limit)))
        (if (and (> n 0) (< n macro-overlay-limit))
            (let* ((suffix (macro-list-suffix macros n))
                   (base (or (macro-list-cached suffix)
                             (macro-list-empty)))
                   (index (macro-list-overlay-prefix macros base n)))
              (table-set! macro-list-index macros index)
              index)
            (let ((index (make-table 'test: eq?)))
              (let loop ((lst macros))
                (if (pair? lst)
                    (let ((name (caar lst)))
                      (if (eq? (table-ref index name macro-index-miss)
                               macro-index-miss)
                          (table-set! index name (cdar lst)))
                      (loop (cdr lst)))))
              (table-set! macro-list-index macros index)
              index)))))

(define (env-lookup env name stop-at-first-frame? proc)
  (define (search env name full?)
    (if full?
        (search* env name #t)
        (let ((full-name-and-ns (env-namespace-lookup-both env name)))
          (if full-name-and-ns
              (let ((full-name (car full-name-and-ns))
                    (ns (cdr full-name-and-ns))
                    (ext (env-externals-ref env)))
                (table-set! ext
                            full-name
                            ns)
                (search* env (car full-name-and-ns) #t))
              (search* env name #f)))))

  (define (search* env name full?)

    (define (search-macros macros)
      (let ((hit (macro-list-ref (macro-list-table macros) name)))
        (if (not (eq? hit macro-index-miss))
            (proc env name hit)
            (let ((var (env-frame-lookup-var env name))
                  (parent (env-parent-ref env)))
              (cond (var (proc env name var))
                    ((or stop-at-first-frame? (not parent)) (proc env name #f))
                    (else (search parent name full?)))))))

    (search-macros (env-macros-ref env)))

  (search env name (full-name? name)))

(define (namespace-valid? str)     ;; non-null name followed by a "#" at end
  (let ((len (string-length str))) ;; is valid as is the special prefix ""
    (or (= len 0)
        (and (>= len 2)
             (char=? (string-ref str (- len 1)) #\#)))))

(define (full-name? sym)           ;; full name if it contains a "#"
  (let ((str (symbol->string sym)))
    (let loop ((i (- (string-length str) 1)))
      (if (< i 0)
          #f
          (if (char=? (string-ref str i) #\#)
              #t
              (loop (- i 1)))))))

(define (make-full-name prefix sym)
  (if (= (string-length prefix) 0)
      sym
      (string->symbol (string-append prefix (symbol->string sym)))))

(define (env-lookup-var env name source)
  (env-lookup env name #f
              (lambda (env name x)
                (if x
                    (if (var? x)
                        x
                        (compiler-internal-error
                         "env-lookup-var, name is that of a macro" name))
                    (env-new-var! env name source)))))

(define (env-define-var env name source)
  (env-lookup env name #t
              (lambda (env name x)
                (if x
                    (if (var? x)
                        (pt-syntax-error
                         source
                         "Duplicate definition of a variable")
                        (compiler-internal-error
                         "env-define-var, name is that of a macro" name))
                    (env-new-var! env name source)))))

(define (env-lookup-global-var env name)
  (let ((env* (env-global-env env)))
    (or (env-frame-lookup-var env* name)
        (env-new-var! env* name #f))))

(define (env-global-variables env)
  (env-vars-ref (env-global-env env)))

(define (env-global-env env)
  (let loop ((env env))
    (let ((env* (env-parent-ref env)))
      (if env*
          (loop env*)
          env))))

(define (env-lookup-macro env name)
  (env-lookup env name #f
              (lambda (env name x)
                (if (or (not x) (var? x)) #f x))))


;;; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

;;;; Declarations

;; A declaration has the form: (##declare <item1> <item2> ...)
;;
;; an <item> can be one of 5 types:
;;
;; - flag declaration           : (<id>)
;; - parameterized declaration  : (<id> <exact-integer>)
;; - boolean declaration        : (<id>)  or  (NOT <id>)
;; - namable declaration        : (<id> <name>...)
;; - namable boolean declaration: (<id> <name>...)  or  (NOT <id> <name>...)

;; Declarations table (for parsing):

(define flag-declarations            '())
(define parameterized-declarations   '())
(define boolean-declarations         '())
(define namable-declarations         '())
(define namable-boolean-declarations '())

(define (define-flag-decl name type)
  (set! flag-declarations (cons (cons name type) flag-declarations))
  '())

(define (define-parameterized-decl name allow-boolean)
  (set! parameterized-declarations (cons (cons name allow-boolean) parameterized-declarations))
  '())

(define (define-boolean-decl name)
  (set! boolean-declarations (cons name boolean-declarations))
  '())

(define (define-namable-decl name type)
  (set! namable-declarations (cons (cons name type) namable-declarations))
  '())

(define (define-namable-boolean-decl name)
  (set! namable-boolean-declarations (cons name namable-boolean-declarations))
  '())

;; Declaration constructors:

(define (flag-decl source type val)
  (list type val))

(define (parameterized-decl source id parm)
  (list id parm))

(define (boolean-decl source id pos)
  (list id pos))

(define (namable-decl source type val names)
  (cons type (cons val names)))

(define (namable-boolean-decl source id pos names)
  (cons id (cons pos names)))

;; Declaration querying:

(define (declaration-value name element default env)
  (let loop ((lst (env-decl-ref env)))
    (if (pair? lst)
        (let ((d (car lst)))
          (if (and (eq? (car d) name)
                   (or (null? (cddr d)) (memq element (cddr d))))
              (cadr d)
              (loop (cdr lst))))
        default)))


;;; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

(define (env.begin!)                    ; initialize module
  (set! next-var-stamp (make-counter 0))
  (set! ret-var (make-temp-var 'ret))
  (set! ret-var-set (varset-singleton ret-var))
  (set! closure-env-var (make-temp-var 'closure-env))
  (set! empty-var (make-temp-var #f))
  '())

(define (env.end!)                      ; finalize module
  (set! next-var-stamp '())
  (set! ret-var '())
  (set! ret-var-set '())
  (set! closure-env-var '())
  (set! empty-var '())
  '())


;;;============================================================================
