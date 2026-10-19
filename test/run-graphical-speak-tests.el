;;; run-graphical-speak-tests.el --- Isolated graphical reading checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Use make graphical-speak-test for an isolated display and bounded lifetime.

;;; Code:
(require 'cl-lib)
(require 'ert)
(let ((root (expand-file-name "../" (file-name-directory load-file-name)))
      (log (getenv "EMACSVOX_GRAPHICAL_SPEAK_TEST_LOG"))
      (debug-on-error nil)
      (debug-on-quit nil)
      (ring-bell-function #'ignore))
  (condition-case err
      (progn
        (unless (and log (display-graphic-p))
          (error "Use make graphical-speak-test to provide a private display and log"))
        (advice-add 'message :after
                    (lambda (format-string &rest arguments)
                      (when format-string
                        (with-temp-buffer
                          (insert (apply #'format-message format-string arguments) "\n")
                          (write-region (point-min) (point-max) log t 'silent)))))
        (setenv "EMACSVOX_SPEAK_TEST_LOAD" "compiled")
        (cl-letf (((symbol-function 'ert-run-tests-batch-and-exit)
                   (lambda (&rest _)
                     ;; Exercise cue construction without a desktop audio server.
                     (cl-letf (((symbol-function 'emacsvox-sounds-play-concrete-cue)
                                #'ignore))
                      (let ((stats
                            (ert-run-tests-batch
                             '(or "^emacsvox-indentation-" "^emacsvox-speak-completion-"
                                  "^emacsvox-speak-windows-"
                                  "^emacsvox-speak-status-graphical-"
                                  (member emacsvox-reading-unit-prompt-is-spoken-once-on-main)))))
                       (kill-emacs
                        (if (and (> (ert-stats-total stats) 0)
                                 (zerop (ert-stats-completed-unexpected stats))
                                 (zerop (ert-stats-skipped stats)))
                            0 1)))))))
          (load (expand-file-name "test/run-speak-tests.el" root) nil t t)))
    ((error quit)
     (when log
       (with-temp-buffer
         (insert (format "Graphical reading runner failed: %S\n" err))
         (write-region (point-min) (point-max) log t 'silent)))
     (kill-emacs 2))))

;;; run-graphical-speak-tests.el ends here
