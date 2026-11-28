(include "#.scm")

;;; Create some threads but don't start them.

(define driver (current-thread))

;; Keep the target alive until the driver finishes submitting interrupts.
;; A relative sleep does not guarantee this under scheduler or host load.
(define (waiting-thread name)
  (make-thread
   (lambda ()
     (thread-send driver 'ready)
     (thread-receive)
     (println name " ending"))))

(define t1 (waiting-thread "t1"))
(define t2 (waiting-thread "t2"))
(define delivered '())

(define t3 (make-thread (lambda () (println "t3 ending"))))

(define t4 (make-thread (lambda () (println "t4 ending"))))


;;; Interrupting a thread after it begins executing the body
;;; has always worked:

(println "t1 starting")

(thread-start! t1)

(test-eq 'ready (thread-receive))

(thread-interrupt! t1 (lambda () (println "t1 interrupt")))

(thread-send t1 'done)
(thread-join! t1)


;;; Multiple interruptions has caused problems in the past:

(println "t2 starting")

(thread-start! t2)

(test-eq 'ready (thread-receive))

(define (record-interrupt number)
  (set! delivered (cons number delivered))
  (println "t2 interrupt #" number))

(thread-interrupt! t2 (lambda () (record-interrupt 1)))
(thread-interrupt! t2 (lambda () (record-interrupt 2)))
(thread-interrupt! t2 (lambda () (record-interrupt 3)))

(thread-send t2 'done)
(thread-join! t2)
(test-equal '(3 2 1) delivered)


;;; Interrupting a thread after it is started but before it begins
;;; executing the body has caused problems in the past:

(println "t3 starting")

(thread-start! t3)

(thread-interrupt! t3 (lambda () (println "t3 interrupt")))

(thread-sleep! .05)
