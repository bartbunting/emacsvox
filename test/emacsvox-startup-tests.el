;;; emacsvox-startup-tests.el --- Core startup tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for core Emacsvox startup and mode preparation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(let* ((kind (or (getenv "EMACSVOX_STARTUP_TEST_LOAD") "source"))
       (file (pcase kind
               ("source" "emacsvox.el")
               ("compiled" "emacsvox.elc")
               (_ (error "Unknown startup test load kind: %s" kind))))
       (path (expand-file-name (concat "../lisp/" file)
                               (file-name-directory (or load-file-name buffer-file-name)))))
  ;; The compiled invocation follows make bytecode-check and loads this exact
  ;; file.  Do not silently prefer source for the lifecycle parity check.
  (load path nil nil t)
  (unless (equal (file-truename (symbol-file 'emacsvox--startup-thread 'defun))
                 (file-truename path))
    (error "Startup tests loaded the wrong implementation: %s" path)))

(defconst emacsvox-startup-tests--root
  (expand-file-name "../" (file-name-directory (or load-file-name buffer-file-name))))

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (setup
        (expand-file-name "../lisp/emacsvox-setup.el" test-directory)))
  (cl-letf (((symbol-function 'display-warning) #'ignore))
    (load setup nil nil)))

(ert-deftest emacsvox-setup-detects-newer-startup-source ()
  "The setup entry point identifies byte-code that can shadow new source."
  (let* ((directory (make-temp-file "emacsvox-setup-stale-" t))
         (source (expand-file-name "fixture.el" directory))
         (compiled (concat source "c"))
         (emacsvox-setup--startup-sources '("fixture.el"))
         (now (current-time)))
    (unwind-protect
        (progn
          (with-temp-file source (insert "source"))
          (with-temp-file compiled (insert "compiled"))
          (set-file-times source now)
          (set-file-times compiled (time-add now 10))
          (should-not (emacsvox-setup--stale-byte-code directory))
          (set-file-times source (time-add now 20))
          (should
           (equal
            (emacsvox-setup--stale-byte-code directory)
            (list source))))
      (delete-directory directory t))))

(ert-deftest emacsvox-setup-tracks-maintained-runtime-inventory ()
  "New TTS, voice, or speech build members must also enter the stale guard."
  (skip-unless (executable-find "make"))
  (let ((default-directory (expand-file-name "lisp/" emacsvox-startup-tests--root)))
    (with-temp-buffer
      (insert "audit-startup-inventory:\n"
              "\t@printf '%s\\n' $(TTS_OBJECTS) $(SPEAK_OBJECTS)\n")
      (let ((status (call-process-region
                     (point-min) (point-max) "make" t t nil
                     "--no-print-directory" "-s" "-f" "Makefile" "-f" "-"
                     "audit-startup-inventory")))
        (unless (eq status 0) (ert-fail (buffer-string))))
      (dolist (compiled (split-string (buffer-string)))
        (should (member (string-remove-suffix "c" compiled)
                        emacsvox-setup--startup-sources))))))

(ert-deftest emacsvox-setup-tracks-loaded-core-dependencies ()
  "A fresh core load cannot silently introduce an unguarded local dependency."
  (let ((emacs (expand-file-name invocation-name invocation-directory))
        (lisp (expand-file-name "lisp/" emacsvox-startup-tests--root)))
    (with-temp-buffer
      (let ((status
             (call-process
              emacs nil t nil "-Q" "--batch" "-L" lisp "-l"
              (expand-file-name "emacsvox-setup.el" lisp)
              "--eval"
              (prin1-to-string
               `(progn
                  ;; These are explicit interactive startup loads.  Do not
                  ;; start speech or prepare arbitrary optional packages here.
                  (require 'emacsvox-advice)
                  (require 'emacsvox-websearch)
                  (dolist (entry load-history)
                    (when (and (stringp (car entry))
                               (file-in-directory-p (car entry) ,lisp))
                      (let ((source (concat (file-name-base (car entry)) ".el")))
                        (unless (member source emacsvox-setup--startup-sources)
                          (error "Startup dependency missing from guard: %s"
                                 source))))))))))
        (unless (eq status 0) (ert-fail (buffer-string)))))))

(ert-deftest emacsvox-setup-loads-newer-omnivox-and-advice-source ()
  "Each formerly omitted dependency enables fallback in a fresh session."
  (let ((emacs (expand-file-name invocation-name invocation-directory)))
    (dolist (module '(omnivox-voices omnivox-remote emacsvox-advice))
      (let* ((root (make-temp-file "emacsvox-startup-fallback-" t))
             (source (expand-file-name (format "%s.el" module) root)))
        (unwind-protect
            (progn
              (copy-file (expand-file-name "lisp/emacsvox-setup.el"
                                           emacsvox-startup-tests--root)
                         (expand-file-name "emacsvox-setup.el" root))
              (with-temp-file (expand-file-name "emacsvox-preamble.el" root)
                (insert "(provide 'emacsvox-preamble)\n"))
              (with-temp-file (expand-file-name "emacsvox.el" root)
                (prin1 `(require ',module) (current-buffer))
                (insert "\n(provide 'emacsvox)\n"))
              (with-temp-file source
                (insert "(defun ev-startup-fixture () 'compiled)\n")
                (prin1 `(provide ',module) (current-buffer)))
              (with-temp-buffer
                (should (eq 0 (call-process emacs nil t nil "-Q" "--batch"
                                            "-f" "batch-byte-compile" source))))
              (with-temp-file source
                (insert "(defun ev-startup-fixture () 'source)\n")
                (prin1 `(provide ',module) (current-buffer)))
              (set-file-times (concat source "c") (seconds-to-time 1000000000))
              (set-file-times source (seconds-to-time 1000000010))
              (with-temp-buffer
                (let ((status
                       (call-process
                        emacs nil t nil "-Q" "--batch" "-L" root
                        "--eval" "(setq load-prefer-newer nil)"
                        "-l" (expand-file-name "emacsvox-setup.el" root)
                        "--eval"
                        (prin1-to-string
                         `(progn
                            (require 'ert)
                            (should (eq (ev-startup-fixture) 'source))
                            (should (equal (symbol-file 'ev-startup-fixture 'defun)
                                           ,source))
                            (should-not load-prefer-newer))))))
                  (unless (eq status 0) (ert-fail (buffer-string))))))
          (delete-directory root t))))))

(ert-deftest emacsvox-setup-prefers-source-while-loading-stale-tree ()
  "Stale startup byte-code enables `load-prefer-newer' for dependencies."
  (let ((load-path (copy-sequence load-path))
        (load-prefer-newer nil)
        observed)
    (cl-letf
        (((symbol-function 'emacsvox-setup--stale-byte-code)
          (lambda (&optional _) '("/checkout/emacsvox-aural.el")))
         ((symbol-function 'display-warning) #'ignore)
         ((symbol-function 'require)
          (lambda (feature &optional _filename _noerror)
            (push (list feature load-prefer-newer) observed)
            feature)))
      (emacsvox-setup--load "/checkout/lisp/"))
    (should
     (equal
      (nreverse observed)
      '((emacsvox-preamble t) (emacsvox t))))))

(ert-deftest emacsvox-startup-threads-preserve-source-loading-preference ()
  "A startup thread retains the setup guard after its dynamic extent ends."
  (dolist (preference '(nil t))
    (let* ((emacsvox--startup-tasks (make-hash-table :test #'eq))
           (load-prefer-newer (not preference))
           (thread
            (let ((load-prefer-newer preference))
              (emacsvox--startup-thread 'fixture (lambda () load-prefer-newer)))))
      (should (eq (thread-join thread) preference))
      (should (eq load-prefer-newer (not preference))))))

(ert-deftest emacsvox-startup-retains-delayed-tasks-and-completion ()
  "Repeated starts reuse a task before and after its observable completion."
  (let* ((emacsvox--startup-tasks (make-hash-table :test #'eq))
         (released nil)
         (started nil)
         (calls 0)
         (thread (emacsvox--startup-thread
                  'delayed
                  (lambda ()
                    (setq started t)
                    (while (not released) (thread-yield))
                    (cl-incf calls)
                    'finished))))
    (unwind-protect
        (progn
          (should (eq thread (emacsvox--startup-thread 'delayed #'ignore)))
          (let ((deadline (+ (float-time) 2)))
            (while (and (not started) (< (float-time) deadline)) (thread-yield)))
          (should started)
          (should (string-match-p "1 running" (emacsvox-startup-status)))
          (setq released t)
          (should (eq (thread-join thread) 'finished))
          (should (string-match-p "1 completed" (emacsvox-startup-status)))
          (should (eq thread (emacsvox--startup-thread 'delayed #'ignore)))
          (should (= calls 1))
          (let ((record (gethash 'delayed emacsvox--startup-tasks)))
            (should (numberp (plist-get record :started)))
            (should (>= (plist-get record :finished) (plist-get record :started)))))
      (setq released t)
      (thread-join thread))))

(ert-deftest emacsvox-startup-retains-task-errors-when-warning-path-fails ()
  "A task error survives failed warning delivery and is not retried."
  (let ((emacsvox--startup-tasks (make-hash-table :test #'eq))
        (calls 0))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (&rest _) (error "broken warning path"))))
      (let ((thread (emacsvox--startup-thread
                     'broken (lambda () (cl-incf calls) (error "original task failure")))))
        (thread-join thread)
        (should (string-match-p "broken: original task failure" (emacsvox-startup-status)))
        (should (eq thread (emacsvox--startup-thread 'broken #'ignore)))
        (should (= calls 1))
        (should (equal (plist-get (gethash 'broken emacsvox--startup-tasks) :error)
                       '(error "original task failure")))))))

(ert-deftest emacsvox-startup-retains-thread-creation-failure ()
  "Thread creation errors remain visible and cannot cause duplicate retries."
  (let ((emacsvox--startup-tasks (make-hash-table :test #'eq))
        (calls 0))
    (cl-letf (((symbol-function 'make-thread)
               (lambda (&rest _) (cl-incf calls) (error "threads unavailable")))
              ((symbol-function 'display-warning) #'ignore))
      (should-not (emacsvox--startup-thread 'broken #'ignore))
      (should-not (emacsvox--startup-thread 'broken #'ignore))
      (should (= calls 1))
      (should (string-match-p "threads unavailable" (emacsvox-startup-status))))))

(ert-deftest emacsvox-startup-records-quit-without-consuming-it ()
  "User quit propagates while the failed operation remains inspectable."
  (let ((record (emacsvox--startup-record "interrupted" 'registered))
        caught)
    (cl-letf (((symbol-function 'display-warning) #'ignore))
      (condition-case nil
          (emacsvox--startup-run record (lambda () (signal 'quit nil)))
        (quit (setq caught t))))
    (should caught)
    (should (eq (plist-get record :state) 'failed))
    (should (equal (plist-get record :error) '(quit)))))

(ert-deftest emacsvox-startup-failure-notifies-despite-warning-failure ()
  "A real-session failure attempts a notification even when warnings fail."
  (let ((record (emacsvox--startup-record "core-advice" 'pending))
        (noninteractive nil)
        notifications)
    (cl-letf (((symbol-function 'display-warning)
               (lambda (&rest _) (error "warning unavailable")))
              ((symbol-function 'tts-notify)
               (lambda (text &rest _) (push text notifications))))
      (emacsvox--startup-run record (lambda () (error "adapter load failed"))))
    (should (= (length notifications) 1))
    (should (string-match-p "core-advice failed.*M-x emacsvox-startup-status"
                            (car notifications)))
    (should (equal (plist-get record :error) '(error "adapter load failed")))))

(defmacro emacsvox-startup-tests--with-packages (&rest body)
  "Run BODY with disposable package libraries and isolated registrations."
  (declare (indent 0) (debug t))
  `(let* ((directory (make-temp-file "emacsvox-startup-packages-" t))
          (load-path (cons directory load-path))
          (load-history (copy-tree load-history))
          (after-load-alist (copy-tree after-load-alist))
          (emacsvox--startup-adapters (make-hash-table :test #'equal))
          (emacsvox--startup-tasks (make-hash-table :test #'eq)))
     (unwind-protect
         (cl-letf (((symbol-function 'display-warning) #'ignore))
           (dolist (package '("ev-immediate" "ev-deferred" "ev-later"))
             (with-temp-file (expand-file-name (concat package ".el") directory)
               (insert (format "(provide '%s)\n" package))))
           (with-temp-file (expand-file-name "ev-broken-adapter.el" directory)
             (insert "(signal 'file-missing '(\"adapter fixture\" \"missing-data\"))\n"))
           (with-temp-file (expand-file-name "ev-good-adapter.el" directory)
             (insert "(provide 'ev-good-adapter)\n"))
           ,@body)
       ;; `features' is not dynamically bindable on supported Emacs versions.
       ;; Remove the actual disposable features before restoring load-history.
       (dolist (feature '(ev-immediate ev-deferred ev-later
                                      ev-broken-adapter ev-good-adapter))
         (when (featurep feature) (unload-feature feature t)))
       (delete-directory directory t))))

(ert-deftest emacsvox-startup-isolates-immediate-and-deferred-adapter-failures ()
  "Real after-load dispatch retains both failures and still loads a later adapter."
  (emacsvox-startup-tests--with-packages
    (require 'ev-immediate)
    (let ((pairs '(("ev-immediate" ev-broken-adapter)
                   ("ev-deferred" ev-broken-adapter)
                   ("ev-later" ev-good-adapter))))
      (mapc #'emacsvox-package-setup pairs)
      (should (string-match-p "2 waiting for packages, 0 running, 1 failed"
                              (emacsvox-startup-status)))
      (require 'ev-deferred)
      (require 'ev-later)
      (should (featurep 'ev-good-adapter))
      (should (string-match-p "1 loaded, 0 waiting for packages, 0 running, 2 failed"
                              (emacsvox-startup-status)))
      (let ((callbacks (copy-tree after-load-alist)))
        (mapc #'emacsvox-package-setup pairs)
        (should (equal callbacks after-load-alist)))
      ;; Correcting a file and reloading its package must not silently retry
      ;; an adapter whose first attempt might have installed partial advice.
      (with-temp-file (expand-file-name "ev-broken-adapter.el" directory)
        (insert "(provide 'ev-broken-adapter)\n"))
      (load "ev-deferred" nil t)
      (should-not (featurep 'ev-broken-adapter))
      (should (equal
               (plist-get (gethash (car pairs) emacsvox--startup-adapters) :error)
               '(file-missing "adapter fixture" "missing-data"))))))

(ert-deftest emacsvox-startup-preparation-continues-after-adapter-failure ()
  "The actual preparation walk reaches later packages after an immediate error."
  (emacsvox-startup-tests--with-packages
    (require 'info)
    (require 'ev-immediate)
    (require 'ev-later)
    (let ((emacsvox-packages-to-prepare '(("ev-immediate" ev-broken-adapter)
                                         ("ev-later" ev-good-adapter)))
          (Info-file-list-for-emacs (copy-sequence Info-file-list-for-emacs))
          (line-move-visual (default-value 'line-move-visual))
          (use-dialog-box use-dialog-box))
      (emacsvox-prepare-emacs)
      (emacsvox-prepare-emacs)
      (should (featurep 'ev-good-adapter))
      (should (= (cl-count "emacsvox" Info-file-list-for-emacs :test #'equal) 1))
      (should (= (hash-table-count emacsvox--startup-adapters) 2)))))

(ert-deftest emacsvox-startup-deferred-adapter-retains-source-preference ()
  "An adapter registered under source fallback keeps it when loaded later."
  (emacsvox-startup-tests--with-packages
    (let ((load-prefer-newer t))
      (emacsvox-package-setup '("ev-deferred" ev-good-adapter)))
    (let ((load-prefer-newer nil)
          (original (symbol-function 'require))
          observed)
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest arguments)
                   (when (eq feature 'ev-good-adapter)
                     (setq observed load-prefer-newer))
                   (apply original feature arguments))))
        (require 'ev-deferred))
      (should observed)
      (should-not load-prefer-newer))))

(ert-deftest emacsvox-startup-status-speaks-once-and-opens-readable-errors ()
  "Interactive status selects its report and speaks; programmatic status is quiet."
  (emacsvox-startup-tests--with-packages
    (require 'ev-immediate)
    (emacsvox-package-setup '("ev-immediate" ev-broken-adapter))
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (push text spoken))))
        (let ((origin (current-buffer))
              (summary (emacsvox-startup-status)))
          (should-not spoken)
          (should (eq origin (current-buffer)))
          (save-window-excursion
            (unwind-protect
                (progn
                  (let ((noninteractive nil))
                    (funcall-interactively #'emacsvox-startup-status))
                  (should (equal spoken (list summary)))
                  (should (equal (buffer-name (window-buffer (selected-window)))
                                 "*Emacsvox Startup*"))
                  (with-current-buffer "*Emacsvox Startup*"
                    (should buffer-read-only)
                    (should (string-match-p "Original condition: (file-missing"
                                            (buffer-string)))
                    (should (string-match-p "missing-data" (buffer-string)))
                    (should (string-match-p "fresh session" (buffer-string)))))
              (when (get-buffer "*Emacsvox Startup*") (kill-buffer "*Emacsvox Startup*")))))))))

(ert-deftest emacsvox-programming-mode-uses-canonical-tts-state ()
  "Programming-mode setup configures speech through the canonical TTS API."
  (let ((tts-split-caps nil)
        (tts-caps nil)
        (emacsvox-audio-indentation t)
        events)
    (cl-letf
        (((symbol-function 'tts-apply-punctuation-mode-policy)
          (lambda () (push 'punctuation-policy events)))
         ((symbol-function 'tts-toggle-split-caps)
          (lambda () (push 'split-caps events)))
         ((symbol-function 'tts-toggle-caps)
          (lambda () (push 'caps events)))
         ((symbol-function 'emacsvox-pronounce-refresh-pronunciations)
          (lambda () (push 'pronunciations events)))
         ((symbol-function 'emacsvox-toggle-audio-indentation)
          (lambda () (push 'audio-indentation events))))
      (emacsvox-setup-programming-mode))
    (should
     (equal
      (nreverse events)
      '(punctuation-policy split-caps caps pronunciations)))))

(ert-deftest emacsvox-programming-mode-preserves-punctuation-override ()
  "Programming setup should not replace an explicit buffer punctuation mode."
  (with-temp-buffer
    (setq major-mode 'prog-mode)
    (let ((tts-speaker-process nil)
          (tts-split-caps t)
          (tts-caps t)
          (emacsvox-audio-indentation t))
      (tts-set-punctuations 'some)
      (cl-letf
          (((symbol-function 'emacsvox-pronounce-refresh-pronunciations)
            #'ignore))
        (emacsvox-setup-programming-mode))
      (should (eq tts-punctuation-mode 'some))
      (should (eq tts-punctuation-mode-override 'some)))))

(ert-deftest emacsvox-startup-applies-the-selected-presentation-profile ()
  "Startup restores the complete selected profile rather than only its ID."
  (with-temp-buffer
    (let (applied)
      (cl-letf
          (((symbol-function 'emacsvox-aural-current-profile-id)
            (lambda () 'work))
           ((symbol-function 'emacsvox-aural-apply-profile)
            (lambda (id source)
              (setq applied (list id source))
              id))
           ((symbol-function 'emacsvox-sounds-select-theme)
            (lambda (&rest _)
              (ert-fail "Selected profile unexpectedly used baseline fallback"))))
        (should (eq (emacsvox--restore-startup-presentation) 'work)))
      (should (equal applied (list 'work (current-buffer)))))))

(ert-deftest emacsvox-startup-without-profile-selects-baseline-sound-pack ()
  "Startup retains the baseline sound fallback when no profile is selected."
  (let (selected)
    (cl-letf
        (((symbol-function 'emacsvox-aural-current-profile-id) #'ignore)
         ((symbol-function 'emacsvox-aural-effective-scheme-provider)
          (lambda (provider &optional _scheme)
            (and (eq provider 'resource-pack) 'bart)))
         ((symbol-function 'emacsvox-sounds-select-theme)
          (lambda (pack) (setq selected pack))))
      (should-not (emacsvox--restore-startup-presentation)))
    (should (eq selected 'bart))))

(ert-deftest emacsvox-startup-profile-failure-warns-and-falls-back ()
  "A failed saved profile does not prevent startup from selecting sounds."
  (let (selected warning)
    (cl-letf
        (((symbol-function 'emacsvox-aural-current-profile-id)
          (lambda () 'work))
         ((symbol-function 'emacsvox-aural-apply-profile)
          (lambda (&rest _) (error "Unavailable pack")))
         ((symbol-function 'emacsvox-aural-effective-scheme-provider)
          (lambda (provider &optional _scheme)
            (and (eq provider 'resource-pack) 'chimes)))
         ((symbol-function 'emacsvox-sounds-select-theme)
          (lambda (pack) (setq selected pack)))
         ((symbol-function 'display-warning)
          (lambda (type message &optional level _buffer-name)
            (setq warning (list type message level)))))
      (should-not (emacsvox--restore-startup-presentation)))
    (should (eq selected 'chimes))
    (should (eq (car warning) 'emacsvox))
    (should (string-match-p "work.*Unavailable pack" (cadr warning)))
    (should (eq (caddr warning) :warning))))

(ert-deftest emacsvox-startup-protocol-readiness-schedules-bounded-fallback ()
  "Capability readiness schedules a bounded fallback announcement."
  (let ((process 'speaker)
        (tts-speaker-process 'speaker)
        (emacsvox-speak-ready-message t)
        (emacsvox-ready-message-routing-timeout 5)
        (emacsvox--ready-announcement-timer nil)
        scheduled)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (delay repeat function &rest arguments)
                 (setq scheduled (list delay repeat function arguments))
                 'timer)))
      (emacsvox--omnivox-protocol-ready process))
    (should (equal (car scheduled) 5))
    (should-not (cadr scheduled))
    (should (eq (caddr scheduled) #'emacsvox--speak-ready-message))
    (should (equal (car (cadddr scheduled)) process))))

(ert-deftest emacsvox-startup-routing-readiness-replaces-fallback ()
  "Acknowledged routing replaces the fallback with an immediate checkpoint."
  (let ((process 'speaker)
        (tts-speaker-process 'speaker)
        (emacsvox-speak-ready-message t)
        (emacsvox--ready-announced-process nil)
        (emacsvox--ready-announcement-timer 'fallback)
        cancelled scheduled)
    (cl-letf (((symbol-function 'timerp) (lambda (value) (eq value 'fallback)))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (setq cancelled timer)))
              ((symbol-function 'run-at-time)
               (lambda (delay repeat function &rest arguments)
                 (setq scheduled (list delay repeat function arguments))
                 'routing)))
      (emacsvox--omnivox-routing-ready process))
    (should (eq cancelled 'fallback))
    (should (equal (car scheduled) 0))
    (should-not (cadr scheduled))
    (should (eq (caddr scheduled) #'emacsvox--speak-ready-message))
    (should (equal (car (cadddr scheduled)) process))))

(ert-deftest emacsvox-startup-ready-message-is-a-stable-spoken-checkpoint ()
  "The routing-ready checkpoint is concise and spoken once per process."
  (let ((process 'speaker)
        (tts-speaker-process 'speaker)
        (emacsvox-speak-ready-message t)
        (emacsvox--ready-announced-process nil)
        spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--speak-ready-message process)
      (should (equal spoken "Emacsvox is ready."))
      (setq spoken nil)
      (emacsvox--speak-ready-message process))
    (should-not spoken)))

(provide 'emacsvox-startup-tests)
;;; emacsvox-startup-tests.el ends here
