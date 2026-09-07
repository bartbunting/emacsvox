;;; prepare-dependencies.el --- Generate isolated test autoloads -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Internal helper for prepare-dependencies.py.  This reads only the verified
;; dependency sources in its private staging directory, using the selected Emacs.

;;; Code:

(require 'loaddefs-gen)
(require 'json)
;; Make cl-defun available before the generator tries loading its source file
;; in the generator's restricted source-only loading context.
(require 'cl-lib)

(unless (version<= "30.2" emacs-version)
  (error "Emacsvox test dependencies require Emacs 30.2 or newer"))

(let* ((root (or (getenv "EMACSVOX_TEST_DEPS_STAGE")
                 (error "EMACSVOX_TEST_DEPS_STAGE is required")))
       (names (json-parse-string (getenv "EMACSVOX_TEST_DEPS_NAMES")
                                :array-type 'list))
       (directories (mapcar (lambda (name) (expand-file-name name root)) names)))
  (dolist (directory directories)
    (add-to-list 'load-path directory))
  (dolist (name names)
    (let ((directory (expand-file-name name root)))
      (loaddefs-generate directory
                        (expand-file-name (concat name "-autoloads.el") directory)
                        nil nil nil t))))

;;; prepare-dependencies.el ends here
