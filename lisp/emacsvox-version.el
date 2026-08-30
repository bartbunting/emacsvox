;;; emacsvox-version.el --- Emacsvox release identity -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Read the canonical release identifier from the repository-level VERSION
;; file.  Reading it when this module loads keeps source and byte-code users on
;; the same value without generating a second version source.

;;; Code:

(defvar emacsvox-version-root
  (if (boundp 'emacsvox-directory)
      (symbol-value 'emacsvox-directory)
    (expand-file-name
     "../" (file-name-directory (or load-file-name buffer-file-name))))
  "Root directory containing the canonical Emacsvox VERSION file.")

(defvar emacsvox-version-file
  (expand-file-name "VERSION" emacsvox-version-root)
  "Canonical Emacsvox version file.")

(defconst emacsvox-version-regexp
  (concat
   "[0-9]\\{4\\}\\."
   "\\(?:[1-9]\\|1[0-2]\\)\\."
   "\\(?:0\\|[1-9][0-9]*\\)")
  "Regular expression matching a stable Emacsvox calendar version.")

(defun emacsvox-version--read ()
  "Read and validate `emacsvox-version-file'."
  (unless (file-readable-p emacsvox-version-file)
    (error "Cannot read Emacsvox version file: %s" emacsvox-version-file))
  (with-temp-buffer
    (insert-file-contents emacsvox-version-file)
    (let ((contents (buffer-substring-no-properties (point-min) (point-max))))
      (unless
          (string-match
           (concat "\\`\\(" emacsvox-version-regexp "\\)\\(?:\n\\)?\\'")
           contents)
        (error
         "Invalid Emacsvox version in %s: %S"
         emacsvox-version-file contents))
      (match-string 1 contents))))

(defvar emacsvox-version-number
  (emacsvox-version--read)
  "Stable Emacsvox release identifier read from the canonical VERSION file.")

(provide 'emacsvox-version)

;;; emacsvox-version.el ends here
