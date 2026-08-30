;;; emacsvox-aural-compatibility-voice.el --- Legacy voice policy -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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

;; Aural-facing control over the per-buffer legacy face and personality voice
;; adapter.  Voice Lock remains the compatibility implementation while aural
;; presentation owns the user-facing policy.

;;; Code:

(require 'emacsvox-aural)

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function tts-speak "tts-speak" (text))

(define-minor-mode voice-lock-mode
  "Toggle the legacy face and personality voice compatibility adapter."
  :init-value nil
  :keymap nil
  (when (called-interactively-p 'interactive)
    (emacsvox-icon (if voice-lock-mode 'on 'off))))

(defun voice-lock-mode--turn-on ()
  "Turn on the Voice Lock compatibility adapter."
  (interactive)
  (voice-lock-mode 1))

(define-globalized-minor-mode global-voice-lock-mode
  voice-lock-mode
  voice-lock-mode--turn-on
  :init-value t
  :group 'emacsvox-aural
  (when (called-interactively-p 'interactive)
    (emacsvox-icon (if global-voice-lock-mode 'on 'off))))

(defvar text-property-default-nonsticky)

(unless (assq 'personality text-property-default-nonsticky)
  (push (cons 'personality t) text-property-default-nonsticky))

(unless (assq 'voice-lock-mode minor-mode-alist)
  (push '(voice-lock-mode " Voice") minor-mode-alist))

(defvar emacsvox-aural-compatibility-voice-changed-hook nil
  "Hook run after compatibility voice policy changes in a buffer.

Hook functions receive the buffer and its new enabled state.")

(defun emacsvox-aural--voice-lock-mode-changed ()
  "Publish a Voice Lock adapter change through the aural policy hook."
  (run-hook-with-args
   'emacsvox-aural-compatibility-voice-changed-hook
   (current-buffer)
   (emacsvox-aural-compatibility-voice-enabled-p)))

(add-hook
 'voice-lock-mode-hook
 #'emacsvox-aural--voice-lock-mode-changed)

(defun emacsvox-aural-set-compatibility-voice-enabled
    (enabled &optional buffer)
  "Set legacy compatibility voices to ENABLED in BUFFER.

This controls only legacy face and personality voice mapping.  Semantic
presentation and explicit visual-face presentation rules remain independent."
  (unless (memq enabled '(nil t))
    (error "Compatibility voice state must be nil or t: %S" enabled))
  (let ((buffer (or buffer (current-buffer))))
    (unless (buffer-live-p buffer)
      (user-error "Compatibility voice source buffer is no longer live"))
    (with-current-buffer buffer
      (voice-lock-mode (if enabled 1 -1))
      (emacsvox-aural-compatibility-voice-enabled-p buffer))))

;;;###autoload
(defun emacsvox-aural-toggle-compatibility-voice (&optional arg buffer)
  "Toggle legacy compatibility voices in BUFFER.

With a positive prefix ARG, enable them.  With zero or a negative prefix,
disable them.  This does not change semantic presentation or explicit
visual-face presentation rules."
  (interactive "P")
  (let* ((buffer (or buffer (current-buffer)))
         (enabled
          (if (null arg)
              (not
               (emacsvox-aural-compatibility-voice-enabled-p buffer))
            (> (prefix-numeric-value arg) 0)))
         (current
          (emacsvox-aural-set-compatibility-voice-enabled
           enabled buffer)))
    (when (called-interactively-p 'interactive)
      (let ((text
             (format
              "Legacy compatibility voices %s in %s."
              (if current "enabled" "disabled")
              (buffer-name buffer))))
        (if (fboundp 'tts-speak)
            (tts-speak text)
          (message "%s" text))))
    current))

(provide 'emacsvox-aural-compatibility-voice)

;;; emacsvox-aural-compatibility-voice.el ends here
