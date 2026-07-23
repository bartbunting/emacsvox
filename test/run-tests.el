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
       (lisp-directory (expand-file-name "lisp/" root-directory)))
  (add-to-list 'load-path test-directory)
  (add-to-list 'load-path lisp-directory)
  ;; Load source explicitly so tests never exercise a stale .elc file.
  (load (expand-file-name "emacsvox-preamble.el" lisp-directory)
        nil nil)
  (require 'emacsvox-advice-tests)
  (require 'emacsvox-trace-tests))

(ert-run-tests-batch-and-exit)

;;; run-tests.el ends here
