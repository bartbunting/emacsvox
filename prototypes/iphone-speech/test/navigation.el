;;; navigation.el --- Exercise interactive Agent Shell motion -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Author: Emacsvox contributors
;; Maintainer: Emacsvox maintainers
;; Keywords: accessibility, speech
;; URL: https://github.com/bartbunting/emacsvox

;; You can redistribute and modify this file under the GNU General Public
;; License version 2 or later. See COPYING in the repository root.

;;; Commentary:
;; This file is used by the isolated iPhone speech prototype.

;;; Code:

(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)

(defun iphone-test-navigation ()
  (condition-case err
      (let ((buffer (iphone-test-render-response)))
        (switch-to-buffer buffer)
        (sit-for 0.3)
        (goto-char (point-min))
        (search-forward "Starting row")
        (beginning-of-line)
        (redisplay t)
        (unless (and (eq (key-binding (kbd "C-n")) 'next-line)
                     (eq (tts-notify-process) tts-speaker-process)
                     (equal (car (process-command tts-speaker-process)) (getenv "TTS_PROGRAM")))
          (error "Unexpected key binding or backend"))
        (dolist (row '("Cobalt lighthouse" "Amber orchard"))
          (execute-kbd-macro (kbd "C-n"))
          (unless (string-search row (thing-at-point 'line t))
            (error "C-n missed its response row"))
          (sit-for 0.35))
        (tts-letter "Z")
        (sit-for 0.2)
        (tts-notify "Notification probe")
        (sit-for 0.2)
        (agent-shell--emit-event
         :event 'permission-request
         :data '((:request-id . 42) (:tool-call-id . "tool")
                 (:tool-call . ((:title . "Inspect sample")))))
        (sit-for 0.2)
        (call-interactively #'tts-stop)
        (sit-for 0.2)
        (execute-kbd-macro (kbd "M-x agent-shell-prompt-compose RET"))
        (sit-for 0.3)
        (dolist (fn '(agent-shell--on-notification emacsvox-agent-shell--next-line-around
                      emacsvox-speak-visual-line tts-letter))
          (princ (format "%s: %s\n" fn (symbol-file fn)) #'external-debugging-output))
        (kill-emacs 0))
    (error
     (princ (format "Navigation check: %S\n" err) #'external-debugging-output)
     (kill-emacs 1))))

(add-hook 'emacs-startup-hook (lambda () (run-at-time 1 nil #'iphone-test-navigation)))

;;; navigation.el ends here
