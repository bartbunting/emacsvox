;;; emacsvox-remote-startup.el --- Isolated remote launcher setup -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Loaded before emacsvox-setup.el by bin/emacsvox --remote.  Environment
;; values remain data, including paths containing quotes or Lisp syntax.

;;; Code:

(setq tts-program "omnivox"
      omnivox-remote-host (getenv "EMACSVOX_REMOTE_HOST")
      omnivox-remote-port (string-to-number (getenv "EMACSVOX_REMOTE_PORT"))
      omnivox-remote-token-file (getenv "EMACSVOX_REMOTE_TOKEN_FILE"))

(defun emacsvox-remote-startup ()
  "Load Emacsvox, reporting connection errors without transport backtraces."
  (condition-case problem
      (load (expand-file-name "lisp/emacsvox-setup.el" (getenv "EMACSVOX_DIR")) nil t)
    ;; Unwind transport frames before reporting the error: an ordinary batch
    ;; initialization backtrace could otherwise expose authentication arguments.
    (error (error "Remote Emacsvox startup failed: %s" (error-message-string problem)))))

;;; emacsvox-remote-startup.el ends here
