;;; run-notmuch-tests.el --- Run focused Notmuch tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Batch entry point for exercising the same Notmuch suite against an
;; explicitly selected source or compiled integration module.

;;; Code:

(require 'ert)

(when (< emacs-major-version 31)
  (error "Emacsvox tests require Emacs 31 or later"))

(setq load-prefer-newer t)

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root-directory (expand-file-name "../" test-directory))
       (lisp-directory (expand-file-name "lisp/" root-directory)))
  (add-to-list 'load-path test-directory)
  (add-to-list 'load-path lisp-directory)
  (require 'emacsvox-notmuch-tests))

(princ
 (format
  "Notmuch focused tests (%s): module=%s\n"
  emacsvox-notmuch-test--module-load-kind
  emacsvox-notmuch-test--loaded-module-path))

(ert-run-tests-batch-and-exit "\\`emacsvox-notmuch-")

;;; run-notmuch-tests.el ends here
