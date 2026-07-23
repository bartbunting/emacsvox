;;; run-tests.el --- Run Emacsvox tests in batch mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Batch entry point for the Emacsvox ERT suite.

;;; Code:

(require 'ert)

(when (< emacs-major-version 31)
  (error "Emacsvox tests require Emacs 31 or later"))

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root-directory (expand-file-name "../" test-directory))
       (lisp-directory (expand-file-name "lisp/" root-directory))
       (utils-directory (expand-file-name "utils/" root-directory)))
  (add-to-list 'load-path test-directory)
  (add-to-list 'load-path lisp-directory)
  (add-to-list 'load-path utils-directory)
  ;; Load source explicitly so tests never exercise a stale .elc file.
  (load (expand-file-name "emacsvox-preamble.el" lisp-directory)
        nil nil)
  (require 'emacsvox-advice-tests)
  (require 'emacsvox-advice-audit-tests)
  (require 'emacsvox-converter-tests)
  (require 'emacsvox-dired-tests)
  (require 'emacsvox-mail-tests)
  (require 'emacsvox-core-migration-tests)
  (require 'emacsvox-completion-tests)
  (require 'emacsvox-input-tests)
  (require 'emacsvox-search-tests)
  (require 'emacsvox-file-tests)
  (require 'emacsvox-process-tests)
  (require 'emacsvox-vc-tests)
  (require 'emacsvox-overlay-tests)
  (require 'emacsvox-message-tests)
  (require 'emacsvox-timer-tests)
  (require 'emacsvox-navigation-tests)
  (require 'emacsvox-rectangle-tests)
  (require 'emacsvox-register-tests)
  (require 'emacsvox-button-tests)
  (require 'emacsvox-tooltip-tests)
  (require 'emacsvox-formatting-tests)
  (require 'emacsvox-help-tests)
  (require 'emacsvox-region-tests)
  (require 'emacsvox-eval-tests)
  (require 'emacsvox-narrowing-tests)
  (require 'emacsvox-undo-tests)
  (require 'emacsvox-position-tests)
  (require 'emacsvox-mark-tests)
  (require 'emacsvox-cleanup-tests)
  (require 'emacsvox-elint-tests)
  (require 'emacsvox-trace-tests))

(ert-run-tests-batch-and-exit)

;;; run-tests.el ends here
