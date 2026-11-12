;;; prepare-menu-dependencies.el --- Compile private menu dependencies -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Compile a disposable copy after the shell runner verifies the source tree.
;; Keep source shorthands enabled, as required by Magit and its dependencies.

;;; Code:

(require 'bytecomp)
(require 'json)
(let* ((source (getenv "EMACSVOX_TEST_DEPS_DIR"))
       (destination (expand-file-name "dependencies/" (getenv "EMACSVOX_MENU_TEST_PROFILE")))
       (manifest (json-read-file (expand-file-name "manifest.json" source)))
       (names (append (alist-get 'packages manifest) nil)))
  (setq package-user-dir (expand-file-name "elpa/" (getenv "EMACSVOX_MENU_TEST_PROFILE"))
        package-directory-list nil
        native-comp-jit-compilation nil)
  (make-directory destination)
  (dolist (name names)
    (let ((directory (expand-file-name name destination)))
      (copy-directory (expand-file-name name source) directory)
      (add-to-list 'load-path directory)))
  (dolist (name names)
    (load (expand-file-name (format "%s/%s-autoloads.el" name name) destination) nil t))
  ;; Compile macro providers before their consumers. The other integrations
  ;; keep the verified source loading used by the integration gate.
  (dolist (name '("compat" "cond-let" "llama" "transient" "with-editor" "magit" "markdown-mode"))
    (dolist (file (directory-files (expand-file-name name destination) t "\\`[^.].*\\.el\\'"))
      (unless (string-match-p "-\\(?:autoloads\\|pkg\\)\\.el\\'" file)
        (unless (byte-compile-file file)
          (error "Menu dependency compilation failed: %s" file))))))

;;; prepare-menu-dependencies.el ends here
