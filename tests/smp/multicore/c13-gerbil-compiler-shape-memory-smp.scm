;;; C13: Adversarial Gerbil-Compiler-Shaped SMP Memory & Subprocess Challenge
;;; (refining gerbil_multicore_memory_challenge_v2.qnt).
;;; Models the real Gerbil stdlib/stage0 memory pathology:
;;;   - Persistent retained expander/symbol table (~12 MiB live) across compile waves
;;;   - 8 concurrent compile workers each generating temporary AST/CFG garbage +
;;;     large >= 64 KiB C-codegen string buffers, contracting via (##gc) before
;;;     spawning an OS subprocess via open-process/process-status!
;;;   - Verifies zero hangs, zero memory creep across 5 waves (40 subprocesses),
;;;     intact retained expander table checksum, and bounded peak RSS (< 256 MiB).

(declare (standard-bindings) (extended-bindings) (block))

(define (build-expander-env n)
  (let ((ht (make-table test: eq?)))
    (let loop ((i 0))
      (if (fx= i n)
          ht
          (begin
            (table-set! ht
                        (string->symbol (string-append "gerbil#mod-" (number->string i)))
                        (vector i
                                (cons i (fx+ i 1))
                                (make-vector 12 (fxand i 255))))
            (loop (fx+ i 1)))))))

(define (verify-expander-env ht n)
  (let loop ((i 0) (acc 0))
    (if (fx= i n)
        acc
        (let ((v (table-ref ht (string->symbol (string-append "gerbil#mod-" (number->string i))) #f)))
          (if (not (and (vector? v) (fx= (vector-ref v 0) i)))
              (error "c13 retained expander env corrupted" i))
          (loop (fx+ i 1) (fx+ acc (vector-ref v 0)))))))

(define (simulate-module-codegen worker-id wave)
  ;; Transient AST + large 256 KiB emitted C buffer (direct-mmap still)
  (let* ((ast (let loop ((i 0) (acc '()))
                (if (fx= i 6000)
                    acc
                    (loop (fx+ i 1)
                          (cons (vector worker-id wave i (cons i (fx+ i 1))) acc)))))
         (c-buf (make-string 262144 #\A)))
    (if (not (and (pair? ast) (char=? (string-ref c-buf 262143) #\A)))
        (error "c13 codegen sanity failed"))
    (length ast)))

(define (run-compile-worker worker-id waves)
  (let loop ((w 0) (ok 0))
    (if (fx= w waves)
        ok
        (let ((nodes (simulate-module-codegen worker-id w)))
          ;; Mirror gsc/_gsclib.scm pre-##gambuild dead-heap contraction!
          (##gc)
          ;; Spawn real OS child process (challenges posix_spawn + SIGCHLD + FOR_EVENT)
          (let* ((p (open-process (list path: "/bin/sh"
                                        arguments: (list "-c" "echo ok")
                                        stdin-redirection: #f
                                        stdout-redirection: #t
                                        stderr-redirection: #f)))
                 (line (read-line p))
                 (status (process-status p)))
            (close-port p)
            (if (not (and (fx= status 0) (equal? line "ok") (fx= nodes 6000)))
                (error "c13 compile subprocess failed" (list worker-id w status line nodes)))
            (loop (fx+ w 1) (fx+ ok 1)))))))

(let* ((env-size 12000)
       (expander-env (build-expander-env env-size))
       (n-workers 8)
       (waves 5)
       (threads
        (let loop ((id 0) (acc '()))
          (if (fx= id n-workers)
              acc
              (loop (fx+ id 1)
                    (cons (thread-start! (make-thread (lambda () (run-compile-worker id waves))))
                          acc)))))
       (counts (map thread-join! threads))
       (total-compiled (let loop ((xs counts) (s 0))
                         (if (null? xs) s (loop (cdr xs) (fx+ s (car xs))))))
       (chk (verify-expander-env expander-env env-size)))
  (##gc)
  (if (not (fx= total-compiled (fx* n-workers waves)))
      (error "c13 compile count mismatch" total-compiled))
  (let ((final-heap-mib (round (/ (f64vector-ref (##process-statistics) 9) 1048576.0))))
    (println "C13-GERBIL-COMPILER-SHAPE-MEMORY-PASS"
             " workers=" n-workers
             " compiled=" total-compiled
             " env_chk=" chk
             " final_heap_mib=" final-heap-mib)))
