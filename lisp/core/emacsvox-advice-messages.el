;;; emacsvox-advice-messages.el --- Core message and error feedback   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995, 1996, 1997 by T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speech, Advice, Spoken output
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

;; Message filtering and duplicate suppression, progress, Eldoc and errors.
;; Caches and filter configuration stay with their feedback functions.  The
;; facade retains advice installation, Eldoc hooks and error-handler selection.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defvar emacsvox-last-message nil
  "Last output from `message'.")

(defvar ems--lazy-msg-time (current-time)
  "Time message was spoken")

(defcustom emacsvox-speak-messages-filter
  '("Decrypting" "psession"  "auto saving")
  "List of strings used to filter spoken messages."
  :type '(repeat :tag "Filtered Strings"
                 (string :tag "String" ))
  :set
  #'(lambda (sym val)
      (set-default sym val ) ; turn list into a pattern to use
      (setq ems--message-filter (regexp-opt val)))
  :group 'emacsvox-speak)

(defun emacsvox--advice-momentary-string-display-around
    (original &rest arguments)
  "Call ORIGINAL quietly after speaking its string and exit character."
  (let ((string (nth 0 arguments))
        (exit-character (nth 2 arguments)))
    (ems-with-messages-silenced
      (tts-notify
       (format "%s Press %s to exit" string
               (if exit-character
                   (format "%c" exit-character)
                 "space")))
      (apply original arguments))))

(defun emacsvox--advice-progress-reporter-do-update-around
    (original &rest arguments)
  "Silence progress reporters."
  (let (result)
    (ems-with-messages-silenced
      (setq result (apply original arguments)))
    (when result (emacsvox-icon 'progress))
    result))

(defun emacsvox--advice-progress-reporter-done-after (&rest _)
  "speak." (emacsvox-icon 'time))

(defun emacsvox--message-around (original arguments)
  "Call ORIGINAL with ARGUMENTS and speak a new, unfiltered message."
  (let ((output nil)
        (overlay minibuffer-message-overlay))
    (let ((result (apply original arguments)))
      (unless (or inhibit-message (null emacsvox-speak-messages))
        (setq output
              (or (current-message)
                  (and overlay
                       (overlay-get overlay 'after-string))))
        (when output
          (setq output (string-trim output)))
        (when
            (and
             output
             (not (zerop (length output)))
             ;; Prompt readers cache their full text, including padding.
             (not (string= output (string-trim (or emacsvox-last-message ""))))
             (not (string-match ems--message-filter output)))
          (setq emacsvox-last-message output)
          (emacsvox-icon 'key)
          (tts-with-punctuations 'all
            (tts-notify output 'dont-log))))
      result)))

(defun emacsvox--advice-minibuffer-message-around
    (original &rest arguments)
  "Call ORIGINAL and speak a new minibuffer message."
  (emacsvox--message-around original arguments))

(defun emacsvox--advice-set-minibuffer-message-around
    (original &rest arguments)
  "Call ORIGINAL and speak a newly set minibuffer message."
  (emacsvox--message-around original arguments))

(defun emacsvox--advice-message-around (original &rest arguments)
  "Call ORIGINAL and speak a new message."
  (emacsvox--message-around original arguments))

(defun emacsvox--advice-display-message-or-buffer-around
    (original &rest arguments)
  "Call ORIGINAL and speak its message or displayed buffer."
  (let ((result (emacsvox--message-around original arguments)))
    (when (bufferp result)
      (tts-notify
       (format "Displayed message in buffer  %s" (nth 1 arguments))))
    result))

(defvar emacsvox--last-docs nil
  "Last docs considered in `emacsvox-speak-eldoc'.")

(defun emacsvox-speak-eldoc (docs interactive)
  "Speak eldoc.  Intended for `eldoc-display-functions'."
  (with-current-buffer (get-buffer-create " *emacsvox-eldoc*")
    (erase-buffer)
    (insert (mapconcat #'car docs "\n"))
    (unless (equal docs emacsvox--last-docs)
      (emacsvox-icon 'doc))
    (when interactive (tts-notify  (buffer-string))))
  (setq emacsvox--last-docs docs))

(defvar ange-ftp-last-percent)

(defun emacsvox--advice-ange-ftp-process-handle-hash-around
    (original &rest arguments)
  "Call ORIGINAL quietly, speak FTP progress, and preserve its result."
  (let (result)
    (ems-with-messages-silenced
      (setq result (apply original arguments))
      (emacsvox-icon 'progress)
      (tts-speak (format " %s percent" ange-ftp-last-percent)))
    result))

(defvar ems--last-error-msg nil
  "Cache last error message.")

(defvar ems--lazy-error-time (current-time)
  "Time error was spoken")

(defun emacsvox--present-command-error (data)
  "Display and present command error DATA as one bounded transaction."
  (let* ((quit-p (eq (car-safe data) 'quit))
         (text (error-message-string data))
         (content (propertize text 'face 'error))
         (facts
          (unless quit-p
            '(:events (operation-failed)))))
    (setq emacsvox-last-message text)
    (let ((emacsvox-speak-messages nil))
      (message content))
    (condition-case nil
        (let ((tts-speaker-process (tts-notify-process)))
          (emacsvox-aural-submit
           content
           :facts facts
           :module 'core
           :occasion 'notification
           :delivery-policy (if quit-p 'replaceable 'urgent)
           :replacement-key (and quit-p 'command-quit)
           :compatibility-actions
           (list (emacsvox-aural-compatibility-icon 'warn-user))))
      (error
       ;; Error reporting must remain usable if native presentation fails.
       (ignore-errors (tts-notify content 'dont-log))))))

(defun emacsvox-error-handler (data _ _)
  "Display and present command error DATA."
  (emacsvox--present-command-error data))

(defconst ems--error-limit 1.0
  "Seconds used to rate-limit error messages.")

(defun emacsvox-fancy-error-handler (data _ caller)
  "Custom error handler."
  (let ((m (error-message-string data))
        (fn (if caller (symbol-name caller) "")))
    (when                               ; speak conditionally
        (and
         (not (string= ems--last-error-msg m)) ; dont repeat
         (< ems--error-limit               ; rate limit
            (float-time (time-subtract (current-time) ems--lazy-msg-time))))
      (setq ems--last-error-msg m
            ems--lazy-error-time (current-time))
      (emacsvox-icon 'warn-user)
      (message
       (concat
        (propertize
         (if (string-match "^ad-Advice" fn) (substring fn 10) fn)
         'personality 'voice-bolden)
        m )))))

(defun emacsvox--silence-messages-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS while silencing messages."
  (ems-with-messages-silenced
    (apply original arguments)))

(provide 'emacsvox-advice-messages)

;;; emacsvox-advice-messages.el ends here
