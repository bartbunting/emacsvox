;;; emacsvox-paths.el --- Declared Lisp source directories -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, tools
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Read the shared data-only directory registry without loading Emacsvox or
;; starting speech.  The Makefile remains the compiled-module inventory.
;; Callers supply their own Lisp root; this module retains no checkout path.

;;; Code:

(require 'subr-x)

(defun emacsvox-paths--directory-names (directory)
  "Read declared relative directory names for Lisp root DIRECTORY.
The registry is ../etc/lisp-directories.  It starts with a single dot for
the root, followed by unique lowercase directory names, one per line.
Blank lines and lines beginning with # are ignored.  No data is evaluated."
  (let ((case-fold-search nil) names)
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "../etc/lisp-directories" directory))
      (dolist (line (split-string (buffer-string) "\n"))
        (let ((name (string-trim line)))
          (unless (or (string-empty-p name) (string-prefix-p "#" name))
            (unless (or (equal name ".")
                        (string-match-p "\\`[a-z][a-z0-9-]*\\'" name))
              (error "Invalid Lisp directory name: %s" name))
            (when (member name names)
              (error "Duplicate Lisp directory name: %s" name))
            (push name names)))))
    (setq names (nreverse names))
    (unless (equal (car names) ".")
      (error "Lisp directory registry must start with the bootstrap root"))
    names))

(defun emacsvox-paths--check-native-directories (directories)
  "Reject Windows reparse points in child DIRECTORIES.
Emacs reports symbolic links but does not identify directory junctions.
Query native file attributes together, without retaining checkout state."
  (when (and directories (eq system-type 'windows-nt))
    (let* ((program (expand-file-name
                     "System32/WindowsPowerShell/v1.0/powershell.exe"
                     (or (getenv "SystemRoot") (error "SystemRoot is unset"))))
           (script
            (concat
             "$ErrorActionPreference='Stop'; foreach ($p in @("
             (mapconcat
              (lambda (path)
                (concat "'" (replace-regexp-in-string "'" "''" path t t) "'"))
              directories ",")
             ")) { if ([IO.File]::GetAttributes($p) -band "
             "[IO.FileAttributes]::ReparsePoint) { Write-Output $p; exit 1 } }")))
      (with-temp-buffer
        (unless (eq 0 (call-process
                       program nil t nil "-NoProfile" "-NonInteractive"
                       "-EncodedCommand"
                       (base64-encode-string (encode-coding-string script 'utf-16le) t)))
          (error "Cannot validate native Lisp directories (junctions are unsupported): %s"
                 (string-trim (buffer-string))))))))

(defun emacsvox-paths--source-directories (directory)
  "Return existing declared source directories below Lisp root DIRECTORY.
Return absolute directory names in registry order.  Absent subdirectories
are allowed during migration.  Reject linked subdirectories and entries
that exist as files.  Never traverse undeclared directories."
  (let ((root (file-name-as-directory (expand-file-name directory)))
        entries children result)
    (unless (file-directory-p root)
      (error "Missing Lisp root: %s" root))
    ;; A dangling Windows junction is still a directory entry even when
    ;; `file-exists-p' follows it to an absent target.
    (setq entries (directory-files root nil nil t))
    (dolist (name (emacsvox-paths--directory-names root))
      (let ((path (expand-file-name name root)))
        (when (and (not (equal name "."))
                   (if (eq system-type 'windows-nt)
                       (assoc-string name entries t)
                     (member name entries)))
          (push path children))
        (when (and (not (equal name ".")) (file-symlink-p path))
          (error "Linked Lisp directory is not supported: %s" path))
        (when (file-exists-p path)
          (unless (file-directory-p path)
            (error "Lisp directory is a file: %s" path))
          (push (file-name-as-directory path) result))))
    (setq result (nreverse result))
    (emacsvox-paths--check-native-directories children)
    result))

(defun emacsvox-paths--files (directory suffix &optional include-hidden directories)
  "List regular files ending in SUFFIX in DIRECTORY's declared directories.
Include hidden files only when INCLUDE-HIDDEN is non-nil, for source audits.
Reject file symlinks as well as linked directories.
Return absolute names; do not descend beyond the declared directories.
DIRECTORIES, when supplied, is the already validated set for this operation."
  (let (result)
    (dolist (path (or directories (emacsvox-paths--source-directories directory)))
      (dolist (file (directory-files path t
                                     (concat (if include-hidden "\\`.*" "\\`[^.].*")
                                             (regexp-quote suffix) "\\'")))
        (unless (and (file-regular-p file) (not (file-symlink-p file)))
          (error "Lisp input is not a regular file: %s" file))
        (push file result)))
    (nreverse result)))

(defun emacsvox-paths--validate-modules (directory modules)
  "Validate relative compiled MODULES against DIRECTORY's registry.
Reject path escapes, undeclared parents and case-insensitive basename
collisions.  Return MODULES unchanged."
  (let ((names (emacsvox-paths--directory-names directory))
        (seen (make-hash-table :test #'equal))
        (case-fold-search nil))
    (dolist (module modules)
      (unless (and (stringp module)
                   (string-match-p
                    "\\`\\(?:[a-z][a-z0-9-]*/\\)?[a-zA-Z0-9_-]+\\.elc\\'" module)
                   (member (or (and (file-name-directory module)
                                    (directory-file-name (file-name-directory module)))
                               ".") names))
        (error "Invalid compiled module path: %s" module))
      (let* ((key (downcase (file-name-nondirectory module)))
             (previous (gethash key seen)))
        (when (and previous (not (equal previous module)))
          (error "Duplicate Lisp library: %s and %s" previous module))
        (puthash key module seen)))
    modules))

(defun emacsvox-paths--check-sources (directory &optional directories)
  "Reject duplicate source library names in DIRECTORY's declared tree.
DIRECTORIES may supply an already validated set for this operation."
  (emacsvox-paths--validate-modules
   directory
   (mapcar (lambda (file) (concat (file-relative-name file directory) "c"))
           (emacsvox-paths--files directory ".el" nil directories))))

(defun emacsvox-paths--check-orphans (directory &optional directories)
  "Reject byte-code without its source in DIRECTORY's declared tree.
DIRECTORIES may supply an already validated set for this operation."
  (dolist (file (emacsvox-paths--files directory ".elc" nil directories))
    (unless (file-regular-p (substring file 0 -1))
      (error "Orphaned Emacsvox byte-code: %s; %s" file
             (if (eq system-type 'windows-nt)
                 "rerun the Windows installer"
               "run make bytecode-rebuild")))))

(defun emacsvox-paths--check-bytecode (directory)
  "Check all existing byte-code in DIRECTORY for age, version and orphans.
The build inventory separately checks missing compiled modules."
  (let ((directories (emacsvox-paths--source-directories directory)))
    (emacsvox-paths--check-sources directory directories)
    (emacsvox-paths--check-orphans directory directories)
    (dolist (file (emacsvox-paths--files directory ".elc" nil directories))
      (when (file-newer-than-file-p (substring file 0 -1) file)
        (error "Stale Emacsvox byte-code: %s; %s" file
               (if (eq system-type 'windows-nt)
                   "rerun the Windows installer"
                 "run make bytecode")))
      (unless (with-temp-buffer
                (insert-file-contents file nil 0 200)
                (search-forward (concat ";;; in Emacs version " emacs-version "\n") nil t))
        (error "Byte-code compiler mismatch: %s; %s" file
               (if (eq system-type 'windows-nt)
                   "rerun the Windows installer"
                 "run make bytecode-rebuild"))))))

(defun emacsvox-paths--clean-bytecode (directory)
  "Remove generated byte-code in DIRECTORY's declared tree.
Validate all paths before deleting anything.  Keep undeclared directories,
sources and personal files intact, including beside old orphaned byte-code."
  (let ((files (emacsvox-paths--files directory ".elc")))
    (mapc #'delete-file files)))

(defun emacsvox-paths--register (directory)
  "Prepend DIRECTORY's declared source directories to `load-path'.
Preserve registry order and unrelated load paths.  Repeated registration
does not add duplicates, including when a path lacks its trailing slash.
Validate the complete directory set before changing `load-path'."
  (let ((directories (emacsvox-paths--source-directories directory))
        other-paths)
    (emacsvox-paths--check-sources directory directories)
    (emacsvox-paths--check-orphans directory directories)
    (dolist (entry load-path)
      (unless (and (stringp entry)
                   (member (file-name-as-directory (expand-file-name entry))
                           directories))
        (push entry other-paths)))
    (setq load-path (append directories (nreverse other-paths)))
    directories))

(provide 'emacsvox-paths)
;;; emacsvox-paths.el ends here
