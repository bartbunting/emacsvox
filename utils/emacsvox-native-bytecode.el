;;; emacsvox-native-bytecode.el --- Native Windows byte-code build -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Consume the canonical lisp/Makefile module inventory and dependency rules.
;; No shell, make executable, or second maintained module list is required.
;;; Code:
(require 'cl-lib)
(require 'subr-x)

(defun emacsvox-native-bytecode-plan (root)
  "Return the Makefile's compiled modules in dependency order below ROOT."
  (let ((variables (make-hash-table :test #'equal))
        (dependencies (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)) lines result)
    (with-temp-buffer
      (insert-file-contents (expand-file-name "lisp/Makefile" root))
      (goto-char (point-min))
      (while (re-search-forward "\\\\\n" nil t) (replace-match " " t t))
      (setq lines (split-string (buffer-string) "\n")))
    (dolist (line lines)
      (when (string-match "^\\([A-Z_]+\\)[ \t]*=[ \t]*\\(.*\\)$" line)
        (puthash (match-string 1 line) (match-string 2 line) variables)))
    (cl-labels
        ((expand-value
           (value &optional seen)
           (save-match-data
             (replace-regexp-in-string
              "\\$(\\([A-Z_]+\\))"
              (lambda (reference)
                (let ((name (substring reference 2 -1)))
                  (when (member name seen) (error "Cyclic Makefile variable: %s" name))
                  (expand-value (or (gethash name variables)
                                    (error "Unknown Makefile variable: %s" name))
                                (cons name seen)))) value t t)))
         (visit
           (module)
           (pcase (gethash module visited)
             ('done nil)
             ('active (error "Cyclic module dependency: %s" module))
             (_ (puthash module 'active visited)
                (dolist (dependency (gethash module dependencies)) (visit dependency))
                (puthash module 'done visited)
                (push (expand-file-name (concat "lisp/" (string-remove-suffix "c" module)) root) result)))))
      (dolist (line lines)
        (when (string-match "^\\([^#\t][^:]*\\):[ \t]*\\(.*\\)$" line)
          (let* ((target-text (match-string 1 line))
                 (input-text (match-string 2 line))
                 (targets (split-string (expand-value target-text)))
                 (inputs (split-string (expand-value input-text))))
            (dolist (target targets)
              (when (string-suffix-p ".elc" target)
                (puthash target
                         (append (gethash target dependencies)
                                 (cl-remove-if-not (lambda (x) (string-suffix-p ".elc" x)) inputs))
                         dependencies))))))
      (dolist (module (split-string (expand-value (or (gethash "OBJECTS" variables) (error "Missing OBJECTS")))))
        (unless (string-match-p "\\`[a-zA-Z0-9_-]+\\.elc\\'" module)
          (error "Unsupported compiled module: %s" module))
        (visit module)))
    (nreverse result)))

(defun emacsvox-native-bytecode-main ()
  "Build or check this native checkout, selected through environment data."
  (unless (and (eq system-type 'windows-nt) (version<= "31" emacs-version))
    (error "Native Windows Emacs 31+ required"))
  (let* ((root (decode-coding-string (base64-decode-string (getenv "EMACSVOX_NATIVE_ROOT")) 'utf-8))
         (directory (expand-file-name "lisp" root))
         (sources (emacsvox-native-bytecode-plan root))
         (load-prefer-newer t)
         (gc-cons-threshold 64000000))
    (if (equal (getenv "EMACSVOX_NATIVE_BYTECODE") "check")
        (progn
          (dolist (compiled (directory-files directory t "\\.elc\\'"))
            (unless (file-exists-p (string-remove-suffix "c" compiled))
              (error "Orphaned native byte-code; rerun the Windows installer: %s" compiled)))
          (dolist (source sources)
            (let ((compiled (concat source "c")))
              (unless (and (file-exists-p compiled)
                           (not (file-newer-than-file-p source compiled))
                           (with-temp-buffer
                             (insert-file-contents compiled nil 0 200)
                             (search-forward (concat ";;; in Emacs version " emacs-version "\n") nil t)))
                (error "Missing or stale native byte-code; rerun the Windows installer: %s" compiled)))))
      (dolist (compiled (directory-files directory t "\\.elc\\'")) (delete-file compiled))
      (load (expand-file-name "emacsvox-preamble.el" directory) nil t)
      (load (expand-file-name "emacsvox-autoload.el" directory) nil t)
      (emacsvox-auto-generate-autoloads)
      (load (expand-file-name "emacsvox-loaddefs.el" directory) nil t)
      (require 'bytecomp)
      (dolist (source sources)
        (unless (byte-compile-file source) (error "Compilation failed: %s" source))))
    (princ (format "Native byte-code %s: %d modules, Emacs %s\n"
                   (or (getenv "EMACSVOX_NATIVE_BYTECODE") "build") (length sources) emacs-version))))
;;; emacsvox-native-bytecode.el ends here
