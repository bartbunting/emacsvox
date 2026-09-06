;;; configure-emacsvox.el --- Prepare an Emacsvox checkout -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Portable first-run configuration for systems without Make.  Invoke with:
;;
;;   emacs -Q --batch -l etc/configure-emacsvox.el

;;; Code:

(defvar emacsvox-lisp-directory)

(let* ((script (or load-file-name buffer-file-name))
       (root (expand-file-name "../" (file-name-directory script)))
       (lisp-directory (expand-file-name "lisp/" root))
       (autoloads (expand-file-name "emacsvox-autoload.el" lisp-directory)))
  (unless (version<= "30.2" emacs-version)
    (error "Emacsvox requires Emacs 30.2 or newer; got %s from %s"
           emacs-version invocation-directory))
  (unless (file-readable-p autoloads)
    (error "Incomplete Emacsvox checkout; cannot read %s" autoloads))
  (add-to-list 'load-path lisp-directory)
  (setq emacsvox-lisp-directory lisp-directory)
  (load autoloads nil nil t)
  (emacsvox-auto-generate-autoloads)
  (princ
   (format
    (concat
     "Configured Emacsvox in %s\n"
     "Next, select a speech server and load lisp/emacsvox-setup.el.\n")
    (directory-file-name root))))

;;; configure-emacsvox.el ends here
