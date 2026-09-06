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

(provide 'emacsvox-native-bytecode-tests)
;;; emacsvox-native-bytecode-tests.el ends here
