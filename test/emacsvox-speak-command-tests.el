;;; emacsvox-speak-command-tests.el --- Core reading command contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Behavior coverage for commands extracted from the core reading library.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(ert-deftest emacsvox-speak-completion-graphical-candidates-and-return ()
  "Read real completion candidates, navigate with Space and return with C-o."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (let ((reference (generate-new-buffer " *reading completion reference*"))
          (previous-completions (get-buffer "*Completions*"))
          spoken)
      (unwind-protect
          (cl-letf (((symbol-function 'tts-speak)
                     (lambda (text) (push (substring-no-properties text) spoken)))
                    ((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'emacsvox-speak-line) #'ignore))
            (switch-to-buffer reference)
            (insert "draft")
            (with-output-to-temp-buffer "*Completions*"
              (display-completion-list '("alpha" "beta")))
            (let ((window (get-buffer-window "*Completions*")))
              (should (window-live-p window))
              (with-selected-window window
                (setq-local completion-reference-buffer nil)
                (goto-char (point-min))
                (next-completion 1)
                (should (equal (emacsvox-get-current-completion) "alpha"))
                (call-interactively (key-binding " "))
                (should (equal (emacsvox-get-current-completion) "beta"))
                (should (equal (car spoken) "beta"))
                (setq-local completion-reference-buffer reference)
                (should (eq (key-binding (kbd "C-o"))
                            #'emacsvox-switch-to-reference-buffer))
                (call-interactively (key-binding (kbd "C-o")))
                (should (eq (current-buffer) reference))
                (should (equal (buffer-string) "draft")))))
        (unless previous-completions
          (when (get-buffer "*Completions*") (kill-buffer "*Completions*")))
        (kill-buffer reference)))))

(ert-deftest emacsvox-speak-notification-history-retains-newest-lines ()
  "Keep the newest history entries and recreate a killed history buffer."
  (let ((emacsvox-notifications-buffer (generate-new-buffer " *history test*")))
    (unwind-protect
        (progn
          (dotimes (index (+ emacsvox-notifications-max 3))
            (emacsvox-log-notification (number-to-string index)))
          (emacsvox-notifications-truncate)
          (with-current-buffer emacsvox-notifications-buffer
            (should (= (count-lines (point-min) (point-max))
                       emacsvox-notifications-max))
            (should (string-prefix-p "3\n" (buffer-string))))
          (kill-buffer emacsvox-notifications-buffer)
          (cl-letf (((symbol-function 'emacsvox--notifications-init)
                     (lambda () (generate-new-buffer " *history replacement*"))))
            (emacsvox-log-notification "new history"))
          (with-current-buffer emacsvox-notifications-buffer
            (should (equal (buffer-string) "new history\n"))))
      (when (buffer-live-p emacsvox-notifications-buffer)
        (kill-buffer emacsvox-notifications-buffer)))))

(ert-deftest emacsvox-speak-message-cache-replay-preserves-text ()
  "Interactive cached replay also makes the text available for yanking."
  (let ((emacsvox-last-message "cached message")
        (current-prefix-arg '(4))
        (kill-ring nil)
        spoken)
    (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
              ((symbol-function 'called-interactively-p) (lambda (&rest _) t)))
      (funcall-interactively #'emacsvox-speak-message-again t)
      (should (equal spoken "cached message"))
      (should (equal (car kill-ring) "cached message")))))

(ert-deftest emacsvox-speak-pip-uses-available-notification-service ()
  "Use Piper when loaded and the notification stream otherwise."
  (let ((original-featurep (symbol-function 'featurep))
        available spoken)
    (cl-letf (((symbol-function 'pip-speak)
               (lambda (text) (push (cons 'piper text) spoken)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (cons 'notification text) spoken)))
              ((symbol-function 'featurep)
               (lambda (feature &optional subfeature)
                 (if (eq feature 'pip) available
                   (funcall original-featurep feature subfeature)))))
      (emacsvox-pip "fallback")
      (setq available t)
      (emacsvox-pip "piper")
      (should (equal spoken '((piper . "piper") (notification . "fallback")))))))

(provide 'emacsvox-speak-command-tests)
;;; emacsvox-speak-command-tests.el ends here
