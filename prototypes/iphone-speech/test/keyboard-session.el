;;; keyboard-session.el --- Prepare the external keyboard listening test -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)

(defun iphone-keyboard-prepare ()
  (switch-to-buffer
   (iphone-test-render-response
    (string-join '("Starting row"
                   "Cobalt lighthouse keepers counted every lantern before the evening ferry came home."
                   "Amber orchard trees stood in long rows beside the old stone wall."
                   "Last row") "\n")))
  (rename-buffer "Phone keyboard sample")
  (goto-char (point-min))
  (search-forward "Starting row")
  (beginning-of-line)
  (redisplay t)
  (with-temp-file (getenv "EMACSVOX_KEYBOARD_READY") (insert "ready\n")))

(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 0.3 nil #'iphone-keyboard-prepare)))
;;; keyboard-session.el ends here
