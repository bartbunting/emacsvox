;;; run-caps-lock-tests.el --- Caps Lock source and byte-code gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with make caps-lock-test, compiled-caps-lock-test or graphical-caps-lock-test.
;;; Code:
(require 'ert)
(when-let* ((log (getenv "EMACSVOX_CAPS_LOCK_TEST_LOG")))
  (advice-add 'message :after
              (lambda (format-string &rest arguments)
                (when format-string
                  (with-temp-buffer
                    (insert (apply #'format-message format-string arguments) "\n")
                    (write-region (point-min) (point-max) log t 'silent))))))
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (compiled (equal (getenv "EMACSVOX_CAPS_LOCK_TEST_LOAD") "compiled"))
       (module (expand-file-name
                (concat "lisp/core/emacsvox-caps-lock." (if compiled "elc" "el")) root)))
  (setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" root))
  (setq load-prefer-newer (not compiled))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (require 'emacsvox-preamble)
  (let ((timers (copy-sequence timer-list))
        (processes (process-list))
        (focus after-focus-change-function))
    (load module nil t t)
    (unless (and (equal timers timer-list) (equal processes (process-list))
                 (eq focus after-focus-change-function) (not emacsvox-caps-lock-mode))
      (error "Loading Caps Lock definitions started a watcher")))
  (unless (equal (file-truename module)
                 (file-truename (symbol-file 'emacsvox-caps-lock-mode)))
    (error "Caps Lock tests loaded the wrong module"))
  (message "Caps Lock module: %s; Emacs %s" module emacs-version)
  (load (expand-file-name "test/emacsvox-caps-lock-tests.el" root) nil t t)
  (when (getenv "EMACSVOX_CAPS_LOCK_TEST_DISPLAY")
    (unless (display-graphic-p) (error "Expected the private graphical display"))
    (load (expand-file-name "test/emacsvox-caps-lock-graphical-tests.el" root) nil t t)))
(if noninteractive
    (ert-run-tests-batch-and-exit "^emacsvox-caps-lock-")
  (let ((debug-on-error nil) (debug-on-quit nil) (status 2))
    (condition-case err
        (let ((stats (ert-run-tests-batch "^emacsvox-caps-lock-")))
          (setq status (if (and (zerop (ert-stats-completed-unexpected stats))
                                (zerop (ert-stats-skipped stats))) 0 1)))
      ((error quit) (message "Graphical Caps Lock check failed: %S" err)))
    (kill-emacs status)))
;;; run-caps-lock-tests.el ends here
