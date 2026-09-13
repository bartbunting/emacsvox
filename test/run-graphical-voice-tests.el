;;; run-graphical-voice-tests.el --- Isolated graphical voice checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Use make graphical-voice-test.  The shell launcher supplies a private X
;; display, a result log and a hard deadline.  ERT's batch-and-exit entry point
;; rejects graphical Emacs; run ERT directly and own reporting and exit here.

;;; Code:

(let ((root (expand-file-name "../" (file-name-directory load-file-name)))
      (log (getenv "EMACSVOX_GRAPHICAL_TEST_LOG"))
      (debug-on-error nil)
      (debug-on-quit nil)
      (ring-bell-function #'ignore)
      (status 2))
  (condition-case err
      (progn
        (unless log (error "Use make graphical-voice-test to provide an isolated display and log"))
        ;; GUI `message' output would otherwise disappear with the test frame.
        (advice-add 'message :after
                    (lambda (format-string &rest arguments)
                      (when format-string
                        (with-temp-buffer
                          (insert (apply #'format-message format-string arguments) "\n")
                          (write-region (point-min) (point-max) log t 'silent)))))
        (unless (and (not noninteractive) (display-graphic-p))
          (error "Graphical voice tests require a graphical Emacs frame"))
        (unless (version<= "30.2" emacs-version)
          (error "Emacsvox requires Emacs 30.2 or newer"))
        (setq load-prefer-newer t)
        (add-to-list 'load-path (expand-file-name "lisp/" root))
        (add-to-list 'load-path (expand-file-name "test/" root))
        (require 'emacsvox-preamble)
        (require 'emacsvox-aural-voice-editor-tests)
        (require 'emacsvox-aural-feedback-details)
        (require 'emacsvox-aural-feedback-details-tests)
        (require 'emacsvox-emoji-integration-tests)
        (dolist (function '(emacsvox-aural-feedback-details--insert-voice-links
                            emacsvox-aural-voice-editor-refresh))
          (let ((file (symbol-file function)))
            (unless (and file (string-suffix-p ".elc" file))
              (error "Expected current byte-code for %s; got %s" function file))
            (message "%s: %s" function file)))
        (let ((stats (ert-run-tests-batch
                      '(member
                        emacsvox-aural-feedback-details-graphical-folding-and-draft-return
                        emacsvox-emoji-graphical-explanation-is-visible
                        emacsvox-aural-voice-editor-feedback-link-resumes-and-returns
                        emacsvox-aural-voice-editor-save-actions-follow-settings-and-previews
                        emacsvox-aural-voice-editor-field-navigation-stops-at-both-ends
                        emacsvox-aural-voice-editor-horizontal-arrows-navigate-nonnumeric-fields
                        emacsvox-aural-voice-editor-graphical-save-remains-visible))))
          (setq status (if (and (= (ert-stats-total stats) 7)
                                (= (ert-stats-completed stats) 7)
                                (zerop (ert-stats-completed-unexpected stats))
                                (zerop (ert-stats-skipped stats)))
                           0 1))))
    ((error quit)
     (let ((text (format "Graphical voice test runner failed: %S\n" err)))
       (if log
           (with-temp-buffer
             (insert text)
             (write-region (point-min) (point-max) log t 'silent))
         (princ text)))))
  (kill-emacs status))

;;; run-graphical-voice-tests.el ends here
