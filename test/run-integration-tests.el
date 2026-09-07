;;; run-integration-tests.el --- Pinned integration gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise Agent Shell, Notmuch, and EAT with the reviewed dependency lock.
;; Run make test-deps first.  CI uses a fresh checkout and private HOME.
;; Missing dependencies, changed prepared files, and skipped tests fail the gate.

;;; Code:

(require 'ert)
(require 'json)
(require 'package)

(unless (and noninteractive (version<= "30.2" emacs-version))
  (error "Run integration tests in batch Emacs 30.2 or newer"))
(dolist (program '("python3" "make" "git" "sh" "bash" "cat"))
  (unless (executable-find program)
    (error "Emacsvox integration tests require %s on PATH" program)))

(setq load-prefer-newer t)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (dependencies (expand-file-name
                      (or (getenv "EMACSVOX_TEST_DEPS_DIR") ".test-deps") root))
       (emacs (expand-file-name invocation-name invocation-directory)))
  ;; Verify before loading any third-party code, including autoloads.  Keep
  ;; checksum and prepared-tree validation in the preparer's single check path.
  (with-temp-buffer
    (unless (eq 0 (call-process
                   "python3" nil t nil
                   (expand-file-name "test/prepare-dependencies.py" root)
                   "--check" "--emacs" emacs "--directory" dependencies))
      (error "Integration dependencies failed verification:\n%s" (buffer-string)))
    (message "%s" (buffer-string)))
  (setq package-user-dir dependencies
        package-directory-list nil)
  (let* ((lock
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name "test/integration-dependencies.json" root))
           (json-parse-buffer :object-type 'alist :array-type 'list)))
         (names (mapcar (lambda (package) (alist-get 'name package))
                        (alist-get 'packages lock))))
    (dolist (name names)
      (add-to-list 'load-path (expand-file-name name dependencies)))
    (dolist (name names)
      (load (expand-file-name (format "%s/%s-autoloads.el" name name) dependencies)
            nil nil t)))
  ;; Fail at startup instead of allowing optional-package tests to skip.
  (dolist (feature '(compat acp shell-maker agent-shell agent-shell-chat-mode
                           eat notmuch))
    (require feature))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (add-to-list 'load-path (expand-file-name "test/" root))
  (load (expand-file-name "lisp/emacsvox-preamble.el" root) nil nil t)
  ;; This order also covers core advice being installed after Agent Shell.
  (dolist (module '(emacsvox-agent-shell-tests emacsvox-notmuch-tests
                                             emacsvox-eat-tests))
    (require module)))

(let ((stats (ert-run-tests-batch t)))
  (kill-emacs
   (if (and (> (ert-stats-total stats) 0)
            (= (ert-stats-completed stats) (ert-stats-total stats))
            (= (ert-stats-completed-unexpected stats) 0)
            (= (ert-stats-skipped stats) 0))
       0 1)))

;;; run-integration-tests.el ends here
