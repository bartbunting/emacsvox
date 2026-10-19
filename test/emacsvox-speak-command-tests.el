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

(provide 'emacsvox-speak-command-tests)
;;; emacsvox-speak-command-tests.el ends here
