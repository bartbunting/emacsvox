;;; emacsvox-startup-tests.el --- Core startup tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for core Emacsvox startup and mode preparation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(load (expand-file-name "../lisp/emacsvox.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

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
    (let* ((load-prefer-newer (not preference))
           (thread
            (let ((load-prefer-newer preference))
              (emacsvox--startup-thread (lambda () load-prefer-newer)))))
      (should (eq (thread-join thread) preference))
      (should (eq load-prefer-newer (not preference))))))

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
