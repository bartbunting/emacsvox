;;; emacsvox-speak-messages.el --- Message history and replay -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Message history and replay.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)

(defvar emacsvox-notifications-buffer)
(defvar emacsvox-last-message)
(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))
(declare-function ems--this-line "emacsvox-speak" ())
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function pip-speak "pip" (text))

;;; Helper: Log Message Quietly

(defun ems--log-message (m)
  "Log  message M without echoing it."
  (let ((inhibit-read-only t))
    (with-current-buffer (messages-buffer)
      (goto-char (point-max))
      (insert (format "%s\n" m)))))

(defvar-local emacsvox-speak-messages t
  "Option indicating if messages are spoken.  If nil,
emacsvox will not speak messages as they are echoed to the
message area.  You can use command
`emacsvox-toggle-speak-messages' bound to
\\[emacsvox-toggle-speak-messages].")

(defun emacsvox--notifications-init ()
  "Init Notifications buffer."
  (let ((buffer (get-buffer-create " *Notifications*")))
    (with-current-buffer buffer
      (special-mode)
      buffer)))

(defun emacsvox-view-notifications ()
  "Display notifications."
  (interactive)

  (unless (buffer-live-p emacsvox-notifications-buffer)
    (setq emacsvox-notifications-buffer (emacsvox--notifications-init)))
  (emacsvox-icon 'open-object)
  (funcall-interactively #'pop-to-buffer emacsvox-notifications-buffer))

(defconst emacsvox-notifications-max 128
  " notifications cache-size")

(defun emacsvox-notifications-truncate ()
  "Trim notifications cache."
  (with-current-buffer emacsvox-notifications-buffer
    (let ((lines (count-lines (point-min) (point-max)))
          (inhibit-read-only t))
      (when (> lines emacsvox-notifications-max)
        (goto-char (point-min))
        (forward-line (- lines emacsvox-notifications-max))
        (delete-region (point-min) (point))))))

(defun emacsvox-log-notification (text)
  "Log a notification in our notifications buffer."

  (unless (buffer-live-p emacsvox-notifications-buffer)
    (setq emacsvox-notifications-buffer (emacsvox--notifications-init)))
  (with-current-buffer emacsvox-notifications-buffer
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "%s\n" text)))))

;;;    quieten messages

(ems-generate-switcher 'emacsvox-toggle-speak-messages
                       'emacsvox-speak-messages
                       "Toggle  state of whether emacsvox echoes messages.")

;;;   Speak the last message again:

(defvar ems--message-filter nil
  "Internal variable holding  pattern used to filter spoken messages.")

(defun emacsvox-speak-message-again (&optional from-message-cache)
  "Speak the last message from Emacs once again.
The message is also placed in the kill ring for convenient yanking "
  (interactive "P")

  (when  (and emacsvox-last-message (called-interactively-p 'interactive))
    (kill-new emacsvox-last-message))
  (cond
   (from-message-cache (tts-speak emacsvox-last-message))
   (t
    (save-current-buffer
      (set-buffer "*Messages*")
      (goto-char (point-max))
      (skip-syntax-backward " >")
      (emacsvox-speak-line)
      (when  (called-interactively-p 'interactive)
        (kill-new (ems--this-line)))))))

;;; Pip: Use Piper if available.
;; Uses pip if piper loaded, otherwise falls back to notifications

(defun emacsvox-pip (text)
  "Speak text, either using piper or regular notification stream."
  (cond
   ((featurep 'pip) (pip-speak text))
   (t (tts-notify text))))

(provide 'emacsvox-speak-messages)

;;; emacsvox-speak-messages.el ends here
