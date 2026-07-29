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
         "emacsvox-aural-source.el"))
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
        (((symbol-function 'tts-set-punctuations)
          (lambda (mode) (push (list 'punctuations mode) events)))
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
      '((punctuations all) split-caps caps pronunciations)))))

(provide 'emacsvox-startup-tests)
;;; emacsvox-startup-tests.el ends here
