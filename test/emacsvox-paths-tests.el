;;; emacsvox-paths-tests.el --- Source layout bootstrap tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

(require 'ert)
(require 'cl-lib)
(defconst emacsvox-paths-tests--root
  (expand-file-name "../" (file-name-directory (or load-file-name buffer-file-name))))
(load (expand-file-name "lisp/emacsvox-paths.el" emacsvox-paths-tests--root) nil t)

(defmacro emacsvox-paths-tests--with-tree (&rest body)
  "Run BODY with a private installation root and Lisp directory."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "emacsvox layout with spaces " t))
          (directory (expand-file-name "lisp/" root)))
     (unwind-protect
         (progn
           (make-directory directory)
           (make-directory (expand-file-name "etc" root))
           (copy-file (expand-file-name "etc/lisp-directories" emacsvox-paths-tests--root)
                      (expand-file-name "etc/lisp-directories" root))
           ,@body)
       (delete-directory root t))))

(ert-deftest emacsvox-paths-registers-only-declared-directories-in-order ()
  (emacsvox-paths-tests--with-tree
    (dolist (name '("integrations" "core" "personal" "core/old"))
      (make-directory (expand-file-name name directory) t))
    (let* ((core (expand-file-name "core/" directory))
           (integrations (expand-file-name "integrations/" directory))
           (load-path (list "/unrelated/" (directory-file-name directory)
                            nil (directory-file-name core))))
      (emacsvox-paths--register directory)
      (emacsvox-paths--register directory)
      (should (equal load-path
                     (list directory core integrations "/unrelated/" nil))))))

(ert-deftest emacsvox-paths-rejects-invalid-registry-without-changing-load-path ()
  (emacsvox-paths-tests--with-tree
    (dolist (contents '("" "core\n.\n" ".\n.\n" ".\ncore\ncore\n"
                        ".\nCORE\n" ".\n../private\n" ".\n/private\n"
                        ".\nC:/private\n" ".\ncore/old\n" ".\ncore\\old\n"
                        ".\n(load \"private.el\")\n"))
      (with-temp-file (expand-file-name "etc/lisp-directories" root)
        (insert contents))
      (let* ((original (copy-sequence load-path)) (load-path original))
        (should-error (emacsvox-paths--register directory))
        (should (eq load-path original))))))

(ert-deftest emacsvox-paths-requires-the-shipped-registry ()
  (emacsvox-paths-tests--with-tree
    (delete-file (expand-file-name "etc/lisp-directories" root))
    (should-error (emacsvox-paths--source-directories directory))))

(ert-deftest emacsvox-paths-allows-a-linked-checkout-root ()
  (emacsvox-paths-tests--with-tree
    (let ((alias (expand-file-name "linked-checkout" root)))
      (condition-case nil
          (make-symbolic-link root alias)
        (file-error (ert-skip "Creating directory symlinks is unavailable")))
      (unwind-protect
          (should (equal (emacsvox-paths--source-directories
                          (expand-file-name "lisp/" alias))
                         (list (expand-file-name "lisp/" alias))))
        (delete-file alias)))))

(ert-deftest emacsvox-paths-rejects-files-and-linked-subdirectories ()
  (emacsvox-paths-tests--with-tree
    (let ((core (expand-file-name "core" directory))
          (outside (expand-file-name "outside" root)))
      (with-temp-file core (insert "not a directory"))
      (should-error (emacsvox-paths--source-directories directory))
      (delete-file core)
      (make-directory outside)
      (condition-case nil
          (make-symbolic-link outside core)
        (file-error (ert-skip "Creating directory symlinks is unavailable")))
      (should-error (emacsvox-paths--source-directories directory))
      (delete-file core)
      (make-symbolic-link (expand-file-name "absent" root) core)
      (should-error (emacsvox-paths--source-directories directory)))))

(ert-deftest emacsvox-paths-bootstrap-loads-relocated-source-and-bytecode ()
  "Direct preamble loading finds nested libraries without starting speech."
  (emacsvox-paths-tests--with-tree
    (let* ((emacs (expand-file-name invocation-name invocation-directory))
           (default-directory (file-name-as-directory root))
           (process-environment (copy-sequence process-environment))
           (nested (expand-file-name "integrations/" directory))
           (source (expand-file-name "ev-layout-fixture.el" nested)))
      (setenv "HOME" root)
      (setenv "XDG_CONFIG_HOME" (expand-file-name "config" root))
      (setenv "XDG_DATA_HOME" (expand-file-name "data" root))
      (setenv "XDG_STATE_HOME" (expand-file-name "state" root))
      (make-directory nested)
      (copy-file (expand-file-name "VERSION" emacsvox-paths-tests--root)
                 (expand-file-name "VERSION" root))
      ;; Use the real core sources: the preamble intentionally loads the TTS
      ;; libraries after registering paths.  No installed checkout may fill in
      ;; missing dependencies or supply another copy of the fixture.
      (dolist (file (directory-files
                    (expand-file-name "lisp" emacsvox-paths-tests--root)
                    t "\\.el\\'"))
        (copy-file file (expand-file-name (file-name-nondirectory file) directory)))
      (with-temp-file source
        (insert ";;; Fixture -*- lexical-binding: t; -*-\n"
                "(defun ev-layout-fixture () 'nested)\n"
                "(provide 'ev-layout-fixture)\n"))
      (dolist (compiled '(nil t))
        (when compiled
          (with-temp-buffer
            (let ((status (apply #'call-process emacs nil t nil
                                 "-Q" "--batch" "-L" directory
                                 "-f" "batch-byte-compile"
                                 (append
                                  (mapcar (lambda (name) (expand-file-name name directory))
                                          '("emacsvox-paths.el" "emacsvox-version.el"
                                            "emacsvox-preamble.el"))
                                  (list source)))))
              (unless (zerop status) (ert-fail (buffer-string))))))
        (with-temp-buffer
          (let ((status
                 (call-process
                  emacs nil t nil "-Q" "--batch"
                  "--eval"
                  (prin1-to-string
                   `(progn
                      (require 'ert)
                      (load ,(expand-file-name
                              (if compiled "emacsvox-paths.elc" "emacsvox-paths.el")
                              directory) nil t t)
                      (emacsvox-paths--register ,directory)
                      (should-not (featurep 'tts-speak))
                      (should-not (featurep 'emacsvox))
                      (should-not (process-list))))
                  "-l"
                  (expand-file-name (if compiled "emacsvox-preamble.elc"
                                      "emacsvox-preamble.el") directory)
                  "--eval"
                  (prin1-to-string
                   `(progn
                      (require 'ert)
                      (should-not (process-list))
                      (require 'ev-layout-fixture)
                      (should (eq (ev-layout-fixture) 'nested))
                      (should (equal (symbol-file 'ev-layout-fixture 'defun)
                                     ,(concat source (if compiled "c" ""))))
                      (should (equal (symbol-file 'emacsvox-paths--register 'defun)
                                     ,(expand-file-name
                                       (if compiled "emacsvox-paths.elc" "emacsvox-paths.el")
                                       directory)))
                      (should (equal emacsvox-directory ,(file-name-as-directory root)))
                      (dolist (pair '((emacsvox-sounds-dir . "sounds/")
                                      (emacsvox-info-directory . "info/")
                                      (emacsvox-servers-directory . "servers/")))
                        (should (equal (symbol-value (car pair))
                                       (expand-file-name (cdr pair) ,root)))))))))
            (unless (zerop status) (ert-fail (buffer-string)))))))))

(ert-deftest emacsvox-paths-rejects-shadowing-and-cleans-only-owned-bytecode ()
  (emacsvox-paths-tests--with-tree
    (make-directory (expand-file-name "integrations" directory))
    (make-directory (expand-file-name "private" directory))
    (dolist (name '("integrations/moved.el" "moved.elc"
                    "integrations/moved.elc" "private/personal.elc" "notes.txt"))
      (with-temp-file (expand-file-name name directory) (insert "; fixture")))
    (let ((original load-path))
      (should-error (emacsvox-paths--register directory))
      (should (eq load-path original)))
    (emacsvox-paths--clean-bytecode directory)
    (should (file-exists-p (expand-file-name "private/personal.elc" directory)))
    (should (file-exists-p (expand-file-name "notes.txt" directory)))
    (should-not (file-exists-p (expand-file-name "moved.elc" directory)))
    (should-not (file-exists-p (expand-file-name "integrations/moved.elc" directory)))
    (let ((load-path load-path)) (emacsvox-paths--register directory))))

(ert-deftest emacsvox-paths-rejects-duplicate-source-and-case-collisions ()
  (emacsvox-paths-tests--with-tree
    (make-directory (expand-file-name "integrations" directory))
    (with-temp-file (expand-file-name "library.el" directory) (insert "; root"))
    (dolist (name '("library.el" "Library.el"))
      (let ((nested (expand-file-name (concat "integrations/" name) directory)))
        (with-temp-file nested (insert "; nested"))
        (should-error (emacsvox-paths--check-sources directory))
        (delete-file nested)))))

(ert-deftest emacsvox-paths-cleanup-validates-links-before-deleting ()
  (emacsvox-paths-tests--with-tree
    (let ((owned (expand-file-name "aaa.elc" directory))
          (outside (expand-file-name "outside.elc" root))
          (linked (expand-file-name "zzz.elc" directory)))
      (with-temp-file owned (insert "; owned"))
      (with-temp-file outside (insert "; external"))
      (condition-case nil
          (make-symbolic-link outside linked)
        (file-error (ert-skip "Creating file symlinks is unavailable")))
      (should-error (emacsvox-paths--clean-bytecode directory))
      (should (file-exists-p owned))
      (should (file-exists-p outside)))))

(ert-deftest emacsvox-paths-windows-junction-cannot-redirect-cleanup ()
  (skip-unless (eq system-type 'windows-nt))
  (emacsvox-paths-tests--with-tree
    (let* ((outside (expand-file-name "outside" root))
           (child (expand-file-name "Integrations" directory))
           (marker (expand-file-name "keep.elc" outside))
           (command (expand-file-name "System32/cmd.exe" (getenv "SystemRoot"))))
      (make-directory outside)
      (with-temp-file marker (insert "; preserve outside byte-code"))
      (unwind-protect
          (progn
            (with-temp-buffer
              (unless (eq 0 (call-process command nil t nil "/c" "mklink" "/J"
                                           (subst-char-in-string ?/ ?\\ child)
                                           (subst-char-in-string ?/ ?\\ outside)))
                (ert-fail (buffer-string))))
            (should-error (emacsvox-paths--register directory))
            (should-error (emacsvox-paths--clean-bytecode directory))
            (should (file-exists-p marker))
            (delete-file marker)
            (delete-directory outside)
            (should-error (emacsvox-paths--source-directories directory)))
        ;; CMD removes the junction itself, never its target or target files.
        (when (assoc-string "integrations" (directory-files directory) t)
          (call-process command nil nil nil "/c" "rmdir"
                        (subst-char-in-string ?/ ?\\ child)))))))

(provide 'emacsvox-paths-tests)
;;; emacsvox-paths-tests.el ends here
