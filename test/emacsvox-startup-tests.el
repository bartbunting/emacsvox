;;; emacsvox-startup-tests.el --- Core startup tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for core Emacsvox startup and mode preparation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox)

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

(ert-deftest emacsvox-setup-tracks-aural-runtime-sources ()
  "The stale guard covers the TTS and voice dependencies of aural startup."
  (dolist
      (source
       '("tts-speak.el"
         "emacsvox-version.el"
         "voice-setup.el"
         "voice-defs.el"
         "dectalk-voices.el"
         "plain-voices.el"
         "espeak-voices.el"
         "outloud-voices.el"
         "mac-voices.el"
         "swiftmac-voices.el"
         "emacsvox-pronounce.el"
         "emacsvox-speak.el"))
    (should (member source emacsvox-setup--startup-sources))))

(ert-deftest emacsvox-setup-tracks-extracted-aural-services ()
  "The stale guard covers independently compiled aural service modules."
  (dolist
      (source
       '("emacsvox-aural-concrete.el"
         "emacsvox-aural-history.el"
         "emacsvox-aural-profile-service.el"
         "emacsvox-aural-providers.el"
         "emacsvox-aural-compiler.el"
         "emacsvox-aural-source.el"
         "emacsvox-aural-planner.el"))
    (should (member source emacsvox-setup--startup-sources))))

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

(ert-deftest emacsvox-startup-announces-readiness-after-omnivox-negotiation ()
  "The stable welcome checkpoint is deferred beyond the process filter."
  (let ((process 'speaker)
        (tts-speaker-process 'speaker)
        (emacsvox-speak-ready-message t)
        (emacsvox--ready-announcement-timer nil)
        scheduled)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (delay repeat function &rest arguments)
                 (setq scheduled (list delay repeat function arguments))
                 'timer)))
      (emacsvox--omnivox-ready process))
    (should (equal (car scheduled) 0))
    (should-not (cadr scheduled))
    (should (eq (caddr scheduled) #'emacsvox--speak-ready-message))))

(ert-deftest emacsvox-startup-ready-message-is-a-stable-spoken-checkpoint ()
  "The post-negotiation checkpoint is concise and user-facing."
  (let ((emacsvox-speak-ready-message t)
        spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--speak-ready-message))
    (should (equal spoken "Emacsvox is ready."))))

(provide 'emacsvox-startup-tests)
;;; emacsvox-startup-tests.el ends here
