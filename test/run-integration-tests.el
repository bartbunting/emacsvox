;;; run-integration-tests.el --- Pinned integration gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise Agent Shell, Notmuch, and EAT with the reviewed dependency lock.
;; Run make test-deps first.  CI uses a fresh checkout and private HOME.
;; Missing dependencies, changed prepared files, and skipped selected tests fail.
;; Graphical cases run separately through make graphical-integration-test.

;;; Code:

(require 'ert)
(require 'json)
(require 'package)

(defconst emacsvox-integration-test--graphical-tests
  '(emacsvox-agent-shell-live-input-graphical-visual-speech
    emacsvox-agent-shell-live-input-graphical-wrapped-speech)
  "Cases owned by the graphical gate and excluded from the batch gate.")

(defun emacsvox-integration-test--run ()
  "Verify pinned inputs and run the cases for this Emacs display mode."
  (unless (version<= "30.2" emacs-version)
    (error "Integration tests require Emacs 30.2 or newer"))
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
    (dolist (module '(emacsvox-agent-shell-render-tests
                      emacsvox-agent-shell-tests emacsvox-notmuch-tests
                                               emacsvox-eat-tests))
      (require module)))

  (dolist (name emacsvox-integration-test--graphical-tests)
    (ert-get-test name))
  (let* ((graphical-selector (cons 'member emacsvox-integration-test--graphical-tests))
         (stats (ert-run-tests-batch
                 (if noninteractive (list 'not graphical-selector) graphical-selector))))
    (if (and (> (ert-stats-total stats) 0)
             (or noninteractive
                 (= (ert-stats-total stats) (length emacsvox-integration-test--graphical-tests)))
             (= (ert-stats-completed stats) (ert-stats-total stats))
             (zerop (ert-stats-completed-unexpected stats))
             (zerop (ert-stats-skipped stats)))
        0 1)))

(let ((log (getenv "EMACSVOX_GRAPHICAL_TEST_LOG"))
      (debug-on-error nil)
      (debug-on-quit nil)
      (ring-bell-function #'ignore)
      (status 2))
  (condition-case err
      (progn
        (unless noninteractive
          (unless (and log (display-graphic-p))
            (error "Use make graphical-integration-test for an isolated graphical frame"))
          ;; Preserve GUI diagnostics before the private frame exits.
          (advice-add 'message :after
                      (lambda (format-string &rest arguments)
                        (when format-string
                          (with-temp-buffer
                            (insert (apply #'format-message format-string arguments) "\n")
                            (write-region (point-min) (point-max) log t 'silent))))))
        (setq status (emacsvox-integration-test--run)))
    ((error quit)
     (let ((text (format "Integration test runner failed: %S\n" err)))
       (if log
           (with-temp-buffer
             (insert text)
             (write-region (point-min) (point-max) log t 'silent))
         (princ text)))))
  (kill-emacs status))

;;; run-integration-tests.el ends here
