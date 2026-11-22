;;; response.el --- Render an isolated Agent Shell test response -*- lexical-binding: t; -*-

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

(defun iphone-test-render-response (&optional reply)
  "Return a new Agent Shell buffer containing REPLY or the short test response."
  (save-current-buffer
    (let* ((agent-shell-show-welcome-message nil)
           (agent-shell-openai-codex-acp-command '("true"))
           ;; Render a reproducible incoming reply without contacting Codex.
           (buffer (cl-letf (((symbol-function 'agent-shell--handle) #'ignore))
                     (agent-shell--start :config (agent-shell-openai-make-codex-config)
                                         :cwd default-directory :session-strategy 'new))))
      (set-buffer buffer)
      (agent-shell--emit-event :event 'input-submitted :data nil)
      (agent-shell--on-notification
       :state agent-shell--state
       :acp-notification
       `((method . "session/update")
         (params . ((update . ((sessionUpdate . "agent_message_chunk")
                               (content . ((type . "text")
                                           (text . ,(or reply "Starting row\nCobalt lighthouse\nAmber orchard\nLast row"))))))))))
      (agent-shell--flush-stream-render agent-shell--state)
      (agent-shell--emit-event :event 'turn-complete :data '((:stop-reason . "end_turn")))
      buffer)))

;;; response.el ends here
