;;; shared-session.el --- Open a draft in the isolated PC test frame -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)
(require 'server)
(when (getenv "EMACSVOX_TRIAL_ROUTED")
  (load (expand-file-name "../frame-speech.el" (file-name-directory load-file-name)) nil nil t)
  (iphone-frame-speech-enable))
(defvar iphone-shared-buffer nil)

(defun iphone-shared-show-draft ()
  (when-let* ((id (frame-parameter nil 'emacsvox-phone-id))
              ((not (display-graphic-p)))
              ((buffer-live-p iphone-shared-buffer)))
    (when (getenv "EMACSVOX_TRIAL_ROUTED") (iphone-frame-speech-attach id))
    (if (and (getenv "EMACSVOX_TRIAL_ROUTED") (frame-parameter nil 'emacsvox-native-ssh))
        (unless (iphone-frame-speech--open-terminal-buffer
                 (if (buffer-live-p iphone-frame-speech--entry-buffer)
                     iphone-frame-speech--entry-buffer iphone-shared-buffer))
          (goto-char (point-max)))
      (switch-to-buffer iphone-shared-buffer)
      (goto-char (point-max)))
    (when (getenv "EMACSVOX_TRIAL_ROUTED")
      (unless (frame-parameter nil 'emacsvox-native-ssh)
        (iphone-frame-speech-subscribe iphone-shared-buffer))
      (iphone-frame-speech--packet (frame-parameter nil 'emacsvox-phone-speaker) "attached" id))
    (redisplay t)
    (unless (frame-parameter nil 'emacsvox-native-ssh)
      (call-process "tmux" nil nil nil "-N" "-S"
                  (expand-file-name "tmux.sock" server-socket-dir)
                  "wait-for" "-S" id))))

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
