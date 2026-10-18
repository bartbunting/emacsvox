;;; emacsvox-gptel.el --- Speech-enable GPTEL  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop gptel
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
;; GPTEL ==  A simple LLM client for Emacs.
;; gptel supports ChatGPT, Claude, Gemini, and local models via
;; streaming responses in buffers. It provides a transient menu for
;; model/backend selection and works in dedicated chat buffers or
;; inline in any buffer.
;; This module speech-enables gptel.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'gptel nil 'noerror)

;;;  Forward Declarations:

(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel--num-messages-to-send)
(defvar gptel-post-response-functions)
(defvar gptel-post-stream-hook)

(declare-function gptel-send "gptel" (&optional arg))
(declare-function gptel-abort "gptel" (&optional buffer))
(declare-function gptel-menu "gptel-transient" nil)
(declare-function gptel--update-status "gptel" (&optional msg face))
(declare-function gptel-backend-name "gptel" (backend))

;;; Map Faces:

(voice-setup-add-map
 '(
   (gptel-context-highlight-face voice-brighten)
   (gptel-context-deletion-face voice-monotone-extra)
   (gptel-pre-response-face voice-smoothen)
   (gptel-post-response-face voice-animate)))

;;;  Track Last Response:

(defvar emacsvox-gptel--last-response-start nil
  "Start position of the last gptel response.")

(defvar emacsvox-gptel--last-response-end nil
  "End position of the last gptel response.")

(defvar emacsvox-gptel--last-response-buffer nil
  "Buffer containing the last gptel response.")

;;;  Advice Interactive Commands:

(defun emacsvox--advice-gptel-send-after (&rest _)
  "Announce that prompt is being sent."
  (when (ems-interactive-p 'gptel-send)
    (emacsvox-icon 'select-object)
    (tts-speak
     (format "Sending prompt to %s"
             (if (bound-and-true-p gptel-backend)
                 (gptel-backend-name gptel-backend)
               "LLM")))))

(defun emacsvox--advice-gptel-abort-after (&rest _)
  "Announce that request was aborted."
  (when (ems-interactive-p 'gptel-abort)
    (tts-stop 'all)
    (emacsvox-icon 'close-object)
    (tts-speak "Aborted LLM request")))

(defun emacsvox--advice-gptel-menu-after (&rest _)
  "Announce gptel menu and current model."
  (when (ems-interactive-p 'gptel-menu)
    (emacsvox-icon 'open-object)
    (tts-speak
     (format "gptel menu, model %s"
             (if (bound-and-true-p gptel-model)
                 gptel-model
               "default")))))

(defconst emacsvox-gptel--advice
  '((gptel-send :after emacsvox--advice-gptel-send-after)
    (gptel-abort :after emacsvox--advice-gptel-abort-after)
    (gptel-menu :after emacsvox--advice-gptel-menu-after))
  "Current GPTel targets and their native advice functions.")

(defun emacsvox-gptel--install-advice ()
  "Install native advice for loaded GPTel commands."
  (dolist (entry emacsvox-gptel--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-gptel)))))))

(with-eval-after-load 'gptel
  (emacsvox-gptel--install-advice))

(with-eval-after-load 'gptel-transient
  (emacsvox-gptel--install-advice))

(emacsvox-gptel--install-advice)

;;;  Hook Functions:

(defun emacsvox-gptel-stream-hook ()
  "Provide streaming tick feedback during response generation."
  (emacsvox-icon 'tick-tick))

(defun emacsvox-gptel-post-response (start end)
  "Announce completion and speak response between START and END."
  (setq emacsvox-gptel--last-response-start start
        emacsvox-gptel--last-response-end end
        emacsvox-gptel--last-response-buffer (current-buffer))
  (emacsvox-icon 'task-done)
  (emacsvox-pip (buffer-substring-no-properties start end)))

;;;  Interactive Commands:

;;;###autoload
(defun emacsvox-gptel-speak-response ()
  "Re-read the last gptel response."
  (interactive)
  (cond
   ((and emacsvox-gptel--last-response-buffer
         (buffer-live-p emacsvox-gptel--last-response-buffer)
         emacsvox-gptel--last-response-start
         emacsvox-gptel--last-response-end)
    (with-current-buffer emacsvox-gptel--last-response-buffer
      (tts-speak
       (buffer-substring-no-properties
        emacsvox-gptel--last-response-start
        emacsvox-gptel--last-response-end))))
   (t (message "No gptel response to speak"))))

;;;  Setup:

(defun emacsvox-gptel-setup ()
  "Set up Emacsvox hooks for gptel."
  (add-hook 'gptel-post-stream-hook #'emacsvox-gptel-stream-hook)
  (cl-pushnew #'emacsvox-gptel-post-response gptel-post-response-functions))

(with-eval-after-load 'gptel
  (emacsvox-gptel-setup))

(provide 'emacsvox-gptel)

;;; emacsvox-gptel.el ends here
