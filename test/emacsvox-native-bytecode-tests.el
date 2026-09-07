;;; emacsvox-native-bytecode-tests.el --- Native build inventory checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
(require 'ert)
(require 'cl-lib)
(defconst emacsvox-native-tests-root
  (expand-file-name "../" (file-name-directory load-file-name)))
(load (expand-file-name "utils/emacsvox-native-bytecode.el" emacsvox-native-tests-root) nil t)

(ert-deftest emacsvox-native-build-matches-canonical-make-inventory ()
  (let ((native (mapcar (lambda (path) (concat (file-name-nondirectory path) "c"))
                        (emacsvox-native-bytecode-plan emacsvox-native-tests-root)))
        expected)
    (with-temp-buffer
      (should (zerop (call-process "make" nil t nil "--no-print-directory" "-s" "-C"
                                   (expand-file-name "lisp" emacsvox-native-tests-root)
                                   "documentation-modules")))
      (setq expected (split-string (buffer-string))))
    (should (equal (sort native #'string<) (sort expected #'string<)))))

(ert-deftest emacsvox-native-build-expands-variables-and-orders-dependencies ()
  (let ((root (make-temp-file "emacsvox-native-plan-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "lisp" root))
          (with-temp-file (expand-file-name "lisp/Makefile" root)
            (insert "BASE = voice.elc\nOBJECTS = app.elc $(BASE)\napp.elc: $(BASE)\n"))
          (should (equal (mapcar #'file-name-nondirectory (emacsvox-native-bytecode-plan root))
                         '("voice.el" "app.el")))
          (with-temp-file (expand-file-name "lisp/Makefile" root)
            (insert "OBJECTS = app.elc voice.elc\napp.elc: voice.elc\nvoice.elc: app.elc\n"))
          (should-error (emacsvox-native-bytecode-plan root)))
      (delete-directory root t))))
(ert-deftest emacsvox-native-build-check-rejects-missing-mismatched-and-orphaned-bytecode ()
  (let* ((root (make-temp-file "emacsvox-native-check-" t))
         (process-environment (copy-sequence process-environment))
         (source (expand-file-name "lisp/app.el" root))
         (compiled (concat source "c")))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "lisp" root))
          (with-temp-file (expand-file-name "lisp/Makefile" root) (insert "OBJECTS = app.elc\n"))
          (with-temp-file source (insert "; source\n"))
          (setenv "EMACSVOX_NATIVE_ROOT" (base64-encode-string (encode-coding-string root 'utf-8) t))
          (setenv "EMACSVOX_NATIVE_BYTECODE" "check")
          (should-error (let ((system-type 'windows-nt)) (emacsvox-native-bytecode-main)))
          (with-temp-file compiled (insert ";;; in Emacs version 29.4\n"))
          (should-error (let ((system-type 'windows-nt)) (emacsvox-native-bytecode-main)))
          (with-temp-file compiled (insert ";;; in Emacs version " emacs-version "\n"))
          (should (string-match-p "1 modules" (with-output-to-string (let ((system-type 'windows-nt)) (emacsvox-native-bytecode-main)))))
          (with-temp-file (expand-file-name "lisp/removed.elc" root) (insert "; orphan\n"))
          (should-error (let ((system-type 'windows-nt)) (emacsvox-native-bytecode-main))))
      (delete-directory root t))))

(ert-deftest emacsvox-native-check-matches-make-dependency-freshness ()
  "Native checks reject the same source and dependency staleness as Make."
  (skip-unless (executable-find "make"))
  (let* ((root (make-temp-file "emacsvox-native-edges-" t))
         (directory (expand-file-name "lisp" root))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (make-directory directory)
          (with-temp-file (expand-file-name "Makefile" directory)
            (insert "OBJECTS = app.elc middle.elc base.elc\n"
                    "all: $(OBJECTS)\napp.elc: middle.elc\nmiddle.elc: base.elc\n"
                    "%.elc: %.el\n\t@touch $@\n"))
          (setenv "EMACSVOX_NATIVE_ROOT"
                  (base64-encode-string (encode-coding-string root 'utf-8) t))
          (setenv "EMACSVOX_NATIVE_BYTECODE" "check")
          (dolist (case '((current (100 100 100) nil t)
                          (direct (100 120 110) nil nil)
                          (transitive (120 110 130) nil nil)
                          (missing (100 110 120) missing nil)
                          (source (100 110 120) source nil)))
            (ert-info ((format "Freshness case: %s" (car case)))
              (cl-mapc
               (lambda (name age)
                 (let* ((source (expand-file-name (concat name ".el") directory))
                        (compiled (concat source "c")))
                   (with-temp-file source (insert "; fixture source\n"))
                   (set-file-times source (seconds-to-time 1000000000))
                   (with-temp-file compiled
                     (insert ";;; in Emacs version " emacs-version "\n"))
                   (set-file-times compiled (seconds-to-time (+ 1000000000 age)))))
               '("base" "middle" "app") (nth 1 case))
              (pcase (nth 2 case)
                ('missing (delete-file (expand-file-name "base.elc" directory)))
                ('source (set-file-times (expand-file-name "base.el" directory)
                                         (seconds-to-time 1000000200))))
              (let (failure)
                (condition-case error-data
                    (with-output-to-string
                      (let ((system-type 'windows-nt)) (emacsvox-native-bytecode-main)))
                  (error (setq failure (error-message-string error-data))))
                (should (eq (not failure) (nth 3 case)))
                (when (memq (car case) '(direct transitive))
                  (should (string-match-p "dependency" failure))))
              (with-temp-buffer
                (let ((status (call-process "make" nil t nil "-C" directory
                                            "--question" "all")))
                  (should (memq status '(0 1)))
                  (should (eq (zerop status) (nth 3 case))))))))
      (delete-directory root t))))

(provide 'emacsvox-native-bytecode-tests)
;;; emacsvox-native-bytecode-tests.el ends here
