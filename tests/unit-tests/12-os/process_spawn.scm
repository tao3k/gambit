(include "#.scm")

(define (process-first-line settings)
  (let* ((process (open-input-process settings))
         (output (read-line process))
         (status (process-status process)))
    (close-input-port process)
    (cons status output)))

;; Darwin uses posix_spawn for ordinary process ports.  These assertions pin
;; the fork/exec behavior that the optimized path must preserve.
(if (equal? (cadr (system-type)) 'apple)
    (begin
      (test-equal
       '(0 . "GAMBIT_PROCESS_SPAWN_CONTRACT=present")
       (process-first-line
        (list path: "/usr/bin/env"
              environment:
              (list "GAMBIT_PROCESS_SPAWN_CONTRACT=present"
                    "PATH=/usr/bin:/bin")
              directory: "/private/tmp")))

      (test-equal
       '(0 . "/private/tmp")
       (process-first-line
        (list path: "/bin/pwd"
              directory: "/private/tmp")))

      ;; stderr shares the redirected output pipe in open-input-process.
      (test-equal
       '(0 . "stderr-only")
       (process-first-line
        (list path: "/bin/sh"
              arguments: (list "-c" "printf stderr-only >&2")
              stderr-redirection: #t)))

      ;; A child PATH must resolve a bare executable name, as execvp did.
      (let* ((path-dir (create-temporary-directory "spawn-path"))
             (command (string-append path-dir "/custom-pwd")))
        (dynamic-wind
          (lambda () (create-symbolic-link "/bin/pwd" command))
          (lambda ()
            (test-equal
             (cons 0 path-dir)
             (process-first-line
              (list path: "custom-pwd"
                    environment: (list (string-append "PATH=" path-dir))
                    directory: path-dir))))
          (lambda ()
            (delete-file command)
            (delete-directory path-dir))))

      (test-error-tail
       no-such-file-or-directory-exception?
       (open-input-process
        (list path: "/definitely/missing/gambit-process-spawn")))))
