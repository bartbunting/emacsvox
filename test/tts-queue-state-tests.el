;;; tts-queue-state-tests.el --- Observed stream boundaries -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Independent expected streams drive the real observer around fake primitives.
;;; Code:
(require 'ert)
(require 'tts-queue-state)
(defvar tts-queue-state-test--behavior nil)

(defconst tts-queue-state-test--fixture
  (expand-file-name "fixtures/voice-editor/queue-handoff.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(defun tts-queue-state-test--cases (group)
  (with-temp-buffer
    (insert-file-contents tts-queue-state-test--fixture)
    (goto-char (point-min))
    (let ((read-eval nil)) (plist-get (read (current-buffer)) group))))

(defmacro tts-queue-state-test--with-process (&rest body)
  (declare (indent 0) (debug t))
  `(let ((process (make-pipe-process :name "queue-proof-test" :noquery t :coding 'utf-8-unix))
         writes tts-queue-state-test--behavior)
     (unwind-protect
         (cl-letf (((symbol-function 'process-send-string)
                    (lambda (target string)
                      (when tts-queue-state-test--behavior (funcall tts-queue-state-test--behavior target string))
                      (push (cons target string) writes)))
                   ((symbol-function 'process-send-region) (lambda (&rest _) nil))
                   ((symbol-function 'process-send-eof) (lambda (&rest _) nil)))
		  (tts-queue--install)
		  (should (tts-queue--coverage-p))
		  (tts-queue--attach process nil t)
		  ,@body)
       (delete-process process))))

(defun tts-queue-state-test--set (process state &optional remote)
  (process-put process 'tts-queue--state
               (tts-queue--make-state
                :generation (process-get process 'tts--speech-process-generation)
                :remote remote :queue (cl-position (car state) '(empty pending unknown))
                :framing (if (eq (cadr state) 'boundary) 0 1)
                :unusable (eq (caddr state) 'unusable))))
(defun tts-queue-state-test--get (process)
  (let ((state (tts-queue--state process)))
    (list (nth (tts-queue--state-queue state) '(empty pending unknown))
          (if (zerop (tts-queue--state-framing state)) 'boundary 'unproven)
          (if (tts-queue--state-unusable state) 'unusable 'usable))))

(defun tts-queue-state-test--entry (entry)
  (let* ((kind (car entry)) (args (cdr entry))
         (string
          (cond
           ((stringp (car args)) (car args))
           ((plist-get args :payload-bytes)
            (concat "s" (make-string (1- (plist-get args :payload-bytes)) ?\s)
                    (if (eq (plist-get args :ending) 'crlf) "\r\n" "\n")))
           ((plist-get args :invalid-utf8) (concat (unibyte-string 255) "s\n"))
           ((plist-get args :nul) "s\0\n")
           ((eq kind 'replaceable-frame) "emacsvox_tx 1 {cSB7WH0KZAo=}\n")
           (t (error "Unhandled fixture entry: %S" entry))))
         (effect (pcase kind
                   ((or 'stop 'reset 'dispatch) 'clear)
                   ((or 'state 'heartbeat) 'neutral)
                   ('replaceable-frame 'frame)
                   (_ nil))))
    (cons string (and effect (tts-queue--describe string effect)))))

(ert-deftest tts-queue-state-independent-framing-fixture ()
  (dolist (case (tts-queue-state-test--cases :framing-cases))
    (ert-info ((format "Fixture %S" (plist-get case :id)))
      (tts-queue-state-test--with-process
       (tts-queue-state-test--set process (plist-get case :before)
                                  (eq (plist-get case :transport) 'remote))
       (dolist (entries (plist-get case :writes))
         (if (eq (caar entries) 'eof)
             (process-send-eof process)
           (let* ((pairs (mapcar #'tts-queue-state-test--entry entries))
                  (packet (tts-queue--packet (mapcar #'car pairs) (mapcar #'cdr pairs)))
                  (fault (cl-some (lambda (entry) (memq :outcome entry)) entries))
                  (tts-queue-state-test--behavior (and fault (lambda (&rest _) (error "Partial write")))))
             (if fault
                 (should-error (tts-queue--send process (car packet) (cdr packet)))
               (tts-queue--send process (car packet) (cdr packet))))))
       (should (equal (plist-get case :after) (tts-queue-state-test--get process)))
       (should (eq (plist-get case :serial)
                   (if (zerop (tts-queue--state-serial (tts-queue--state process)))
                       'unchanged 'changed)))))))

(ert-deftest tts-queue-state-queue-effects-at-known-boundary ()
  (dolist (case (tts-queue-state-test--cases :proof-cases))
    (tts-queue-state-test--with-process
     (tts-queue-state-test--set process (list (plist-get case :before) 'boundary 'usable))
     (let* ((effect (plist-get case :effect))
            (kind (pcase effect
                    ((or 'dispatch 'stop) 'clear)
                    ((or 'letter 'immediate-say) 'interrupt)
                    ((or 'timeline 'heartbeat) 'neutral)
                    ('queue 'queue)
                    (`(replaceable-frame . ,_) 'frame)))
            (wire (pcase effect
                    ('dispatch "d\n") ('stop "s\n") ('letter "l A\n")
                    ('immediate-say "tts_say {A}\n") ('timeline "emacsvox_timeline {e30=}\n")
                    ('heartbeat "OMNIVOX-REMOTE ping\n") ('queue "q {A}\n")
                    (`(replaceable-frame . ,_) "emacsvox_tx 1 {cSB7WH0KZAo=}\n")
                    (_ "opaque\n")))
            (tts-queue-state-test--behavior (and (plist-get case :write) (lambda (&rest _) (error "Write failure")))))
       (if tts-queue-state-test--behavior
           (should-error (tts-queue--send-typed process wire kind))
         (if kind (tts-queue--send-typed process wire kind) (process-send-string process wire))))
     (should (eq (plist-get case :after) (car (tts-queue-state-test--get process)))))))

(ert-deftest tts-queue-state-neutral-overlap-and-nonlocal-outcomes ()
  (dolist (remote '(nil t))
    (dolist (outcome '(nested error quit throw))
      (tts-queue-state-test--with-process
       (tts-queue-state-test--set process '(pending boundary usable) remote)
       (let ((tts-queue-state-test--behavior
              (lambda (&rest _)
                (pcase outcome
                  ('nested (let (tts-queue-state-test--behavior) (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral)))
                  ('error (error "Write failed"))
                  ('quit (signal 'quit nil))
                  ('throw (throw 'failed t))))))
         (condition-case nil
             (catch 'failed (tts-queue--send-typed process "s\n" 'clear))
           ((error quit) nil)))
       (should (equal (tts-queue-state-test--get process)
                      (list 'unknown 'unproven (if remote 'unusable 'usable))))
       (should-not (tts-queue--state-flight (tts-queue--state process)))))))

(ert-deftest tts-queue-state-alias-region-eof-and-other-process ()
  (tts-queue-state-test--with-process
   (with-temp-buffer
     (set-process-buffer process (current-buffer))
     (dolist (argument (list process (process-name process) (current-buffer) (buffer-name) nil))
       (tts-queue-state-test--set process '(empty boundary usable))
       (process-send-string argument "q {prefix")
       (should (equal '(unknown unproven usable) (tts-queue-state-test--get process))))
     (set-process-buffer process nil))
   (process-send-region process (point-min) (point-max))
   (should (equal '(unknown unproven usable) (tts-queue-state-test--get process)))
   (process-send-eof process)
   (should (equal '(unknown unproven unusable) (tts-queue-state-test--get process)))
   (let ((other (make-pipe-process :name "other-proof-test" :noquery t :coding 'utf-8-unix)))
     (unwind-protect
         (progn
           (tts-queue-state-test--set process '(pending boundary usable))
           (tts-queue--attach other nil t)
           (let ((tts-queue-state-test--behavior (lambda (&rest _) (let (tts-queue-state-test--behavior) (tts-queue--send-typed other "q {B}\n" 'queue)))))
             (should (tts-queue--send-typed process "s\n" 'clear)))
           (should (equal '(empty boundary usable) (tts-queue-state-test--get process)))
           (should (equal '(pending boundary usable) (tts-queue-state-test--get other))))
       (delete-process other)))))

(ert-deftest tts-queue-state-command-mutation-and-observer-coverage ()
  (tts-queue-state-test--with-process
   (let* ((command (copy-sequence "s\n")) (description (tts-queue--describe command 'clear)))
     (aset command 0 ?d)
     (should-error (tts-queue--packet (list command) (list description)))
     (should-error (tts-queue--send process command description))
     (should-not writes))
   (let ((advice (lambda (&rest _) nil)))
     (unwind-protect
         (progn
           (advice-add 'process-send-string :override advice)
           (should-not (tts-queue--send-typed process "s\n" 'clear))
           (should (equal '(unknown unproven usable) (tts-queue-state-test--get process))))
       (advice-remove 'process-send-string advice)))
   (let ((advice (lambda (next target _string) (funcall next target "q {injected}\n"))))
     (unwind-protect
         (progn
           (advice-add 'process-send-string :around advice)
           (should-not (tts-queue--send-typed process "s\n" 'clear))
           (should (equal '(unknown unproven usable) (tts-queue-state-test--get process))))
       (advice-remove 'process-send-string advice)))
   (let ((advice (lambda (next &rest args) (apply next args))))
     (unwind-protect
         (progn
           (advice-add 'process-send-string :around advice '((depth . 101)))
           (should-not (tts-queue--coverage-p))
           (should-not (tts-queue--send-typed process "s\n" 'clear)))
       (advice-remove 'process-send-string advice)))))

(ert-deftest tts-queue-state-creation-auth-and-generation-handoff ()
  (tts-queue-state-test--with-process
   (process-put process 'tts-queue--state nil)
   (tts-queue--create (lambda () process) nil)
   (should (equal '(empty boundary usable) (tts-queue-state-test--get process)))
   (tts-queue--send-typed process "q {PENDING}\n" 'queue)
   (process-put process 'tts--speech-process-generation 7)
   (tts-queue--set-generation process 7)
   (should (equal '(pending boundary usable) (tts-queue-state-test--get process)))
   (tts-queue--set-generation process 8)
   (should (equal '(unknown unproven usable) (tts-queue-state-test--get process)))
   (process-put process 'tts--speech-process-generation nil)
   (dolist (remote '(nil t))
     (process-put process 'tts-queue--state nil)
     (cl-letf (((symbol-function (if remote 'make-network-process 'make-process))
                (lambda (&rest _) process)))
       (tts-queue--create (lambda () process) remote))
     (should (equal (tts-queue-state-test--get process)
                    (if remote '(unknown unproven unusable)
                      '(unknown unproven usable)))))
   (process-put process 'tts-queue--state nil)
   (tts-queue--create (lambda () (process-send-string process "q {EARLY}\n") process) nil)
   (should (equal '(unknown unproven usable) (tts-queue-state-test--get process)))
   (dolist (intervening '(nil t))
     (process-put process 'tts-queue--state nil)
     (tts-queue--create (lambda () process) t)
     (let* ((command (format "OMNIVOX-REMOTE 1 %s %s speaker\n" (make-string 64 ?a) (make-string 32 ?b)))
            (receipt (tts-queue--send process command (tts-queue--describe command 'neutral) t)))
       (when intervening (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral))
       (tts-queue--authenticated process receipt)
       (should (equal (tts-queue-state-test--get process)
                      (if intervening '(unknown unproven unusable) '(empty boundary usable))))))))

(ert-deftest tts-queue-state-encoding-bounds-and-rollover ()
  (tts-queue-state-test--with-process
   (should-not (tts-queue--utf8-p (unibyte-string 255)))
   (should (tts-queue--utf8-p "é"))
   (should (tts-queue--record-valid-p (concat "s" (make-string 524287 ?\s) "\r\n")))
   (should-not (tts-queue--record-valid-p (concat "s" (make-string 524287 ?\s) "\r\n") t))
   (set-process-coding-system process 'utf-16 'utf-16)
   (should-not (tts-queue--send-typed process "s\n" 'clear))
   (should (equal '(unknown unproven usable) (tts-queue-state-test--get process)))
   (set-process-coding-system process 'utf-8-unix 'utf-8-unix)
   (let ((state (tts-queue--state process)))
     (setf (tts-queue--state-serial state) most-positive-fixnum)
     (tts-queue--send-typed process "s\n" 'clear)
     (should-not (eq state (tts-queue--state process)))
     (should (eq 'unknown (car (tts-queue-state-test--get process)))))))

(ert-deftest tts-queue-state-guards-require-exact-own-stop-and-registry ()
  (tts-queue-state-test--with-process
   (process-put process 'test-registry (list 'snapshot))
   (let* ((guard (tts-queue--guard process 'test-registry))
          (receipt (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear)
                                    nil guard t)))
     (should-not (tts-queue--guard-valid-p guard))
     (tts-queue--advance-stop guard receipt)
     (should (tts-queue--guard-valid-p guard))
     (should-error (tts-queue--advance-stop guard receipt))
     (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral)
     (should (tts-queue--guard-valid-p guard))
     (process-put process 'test-registry (list 'new-snapshot))
     (should-not (tts-queue--guard-valid-p guard)))
   (let ((guard (tts-queue--guard process)))
     (tts-queue--send-typed process "q {X}\n" 'queue)
     (tts-queue--send-typed process "d\n" 'clear)
     (should (tts-queue--known-empty-p process))
     (should-not (tts-queue--guard-valid-p guard)))
   (let* ((guard (tts-queue--guard process))
          (receipt (tts-queue--send-typed process "s\n" 'clear)))
     (should-error (tts-queue--advance-stop guard receipt)))))

(ert-deftest tts-queue-state-guarded-write-rejects-overlap-and-argument-rewriting ()
  (tts-queue-state-test--with-process
   (let ((guard (tts-queue--guard process))
         (tts-queue-state-test--behavior
          (lambda (&rest _) (let (tts-queue-state-test--behavior)
                              (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral)))))
     (should-error (tts-queue--send process "emacsvox_timeline {e30=}\n"
                                    (tts-queue--describe "emacsvox_timeline {e30=}\n" 'neutral)
                                    nil guard))
     (should-not (tts-queue--known-empty-p process)))
   (tts-queue-state-test--set process '(empty boundary usable))
   (let ((guard (tts-queue--guard process))
         (advice (lambda (next target _command) (funcall next target "q {OTHER}\n"))))
     (unwind-protect
         (progn
           (advice-add 'process-send-string :around advice)
           (should-error (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear)
                                          nil guard t)))
       (advice-remove 'process-send-string advice)))
   (should-not (tts-queue--known-empty-p process))))

(ert-deftest tts-queue-state-bookkeeping-failure-and-malformed-state-stay-unknown ()
  (tts-queue-state-test--with-process
   (let ((bump (symbol-function 'tts-queue--bump)))
     (cl-letf (((symbol-function 'tts-queue--bump)
                (lambda (target state) (funcall bump target state) (error "Publication failed"))))
       (should-error (tts-queue--send-typed process "s\n" 'clear))))
   (should (equal '(unknown unproven usable) (tts-queue-state-test--get process)))
   (should-not (tts-queue--state-flight (tts-queue--state process)))
   (process-put process 'tts-queue--state '(malformed))
   (should-not (tts-queue--known-empty-p process))
   (tts-queue--send-typed process "s\n" 'clear)
   (should-not (tts-queue--known-empty-p process))
   (tts-queue--send-typed process "s\n" 'clear)
   (should (tts-queue--known-empty-p process))))

(provide 'tts-queue-state-tests)
;;; tts-queue-state-tests.el ends here
