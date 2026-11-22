;;; shared-session.el --- Open a draft in the isolated PC test frame -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)
(require 'server)
(defvar iphone-shared-buffer nil)

(defun iphone-shared-show-draft ()
  (when-let* ((id (frame-parameter nil 'emacsvox-phone-id))
              ((not (display-graphic-p)))
              ((buffer-live-p iphone-shared-buffer)))
    (switch-to-buffer iphone-shared-buffer)
    (goto-char (point-max))
    (redisplay t)
    (call-process "tmux" nil nil nil "-N" "-S"
                  (expand-file-name "tmux.sock" server-socket-dir)
                  "wait-for" "-S" id)))

(defun iphone-shared-prepare ()
  (setq iphone-shared-buffer (iphone-test-render-response))
  (switch-to-buffer iphone-shared-buffer)
  (rename-buffer "Shared Codex sample")
  (emacsvox-agent-shell-edit-input)
  (goto-char (point-max))
  (insert "Started on PC")
  (setq server-name "shared"
        server-socket-dir (getenv "EMACSVOX_SHARED_DIR")
        server-client-instructions nil)
  (add-hook 'server-after-make-frame-hook #'iphone-shared-show-draft)
  (server-start)
  (let ((ready (expand-file-name "ready" server-socket-dir)))
    (with-temp-file (concat ready ".tmp")
      (insert (expand-file-name "emacsclient" invocation-directory)))
    (rename-file (concat ready ".tmp") ready)))

(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 0.3 nil #'iphone-shared-prepare)))
;;; shared-session.el ends here
