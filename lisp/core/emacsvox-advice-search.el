;;; emacsvox-advice-search.el --- Core search and replacement feedback -*- lexical-binding: t; -*-

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

;; Core search and replacement feedback.
;; Load through `emacsvox-advice'.  The facade owns activation.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox--advice-perform-replace-around
    (original &rest arguments)
  "Call ORIGINAL with replacement messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(defun emacsvox--advice-replace-highlight-after (&rest _)
  "Speak the line after highlighting a replacement."
  (emacsvox-speak-line))

(defvar emacsvox-isearch--message-states nil
  "Stack of message-speech states owned by active Isearch sessions.
Each entry records the originating buffer, prior locality, and prior value.
Keep the owner because multi-buffer searches can end in a different buffer.")

(defun emacsvox-isearch--restore-message-state ()
  "Restore and retire the innermost owned message-speech state."
  (when emacsvox-isearch--message-states
    (pcase-let ((`(,buffer ,local ,value)
                 (pop emacsvox-isearch--message-states)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (if local
              (setq-local emacsvox-speak-messages value)
            (kill-local-variable 'emacsvox-speak-messages)))))))

(defun emacsvox-isearch-setup ()
  "Setup emacsvox isearch."
  (push (list (current-buffer)
              (local-variable-p 'emacsvox-speak-messages)
              emacsvox-speak-messages)
        emacsvox-isearch--message-states)
  (condition-case error-data
      (progn
        (emacsvox-icon 'open-object)
        (setq-local emacsvox-speak-messages isearch-lazy-count)
        (tts-speak (isearch-message-prefix)))
    ((error quit)
     (emacsvox-isearch--restore-message-state)
     (signal (car error-data) (cdr error-data)))))

(defun emacsvox-isearch-teardown ()
  "Teardown emacsvox isearch."
  (when emacsvox-isearch--message-states
    (emacsvox-isearch--restore-message-state)
    (emacsvox-icon 'close-object)))

(defun emacsvox--advice-isearch-search-after (&rest _)
  "Speak the hit."
  (cond ((null isearch-success) (emacsvox-icon 'search-miss))
        (t (emacsvox-icon 'search-hit)
           (when (sit-for 0.1)
             (save-excursion
               (ems-set-personality-temporarily (point)
                                                isearch-other-end
                                                'voice-bolden
                                                (tts-speak
                                                 (buffer-substring
                                                  (line-beginning-position)
                                                  (line-end-position)))))))))

(defun emacsvox--advice-isearch-delete-char-after (&rest _)
  "Speak the shortened isearch string and current hit."
  (tts-speak (propertize isearch-string 'personality 'voice-bolden))
  (when (sit-for 0.1)
    (emacsvox-icon 'search-hit)
    (ems-set-personality-temporarily (point)
                                     (if isearch-forward
                                         (- (point)
                                            (length isearch-string))
                                       (+ (point)
                                          (length isearch-string)))
                                     'voice-bolden
                                     (emacsvox-speak-line))))

(defun emacsvox--advice-isearch-toggle-case-fold-after (&rest _)
  "Announce the new isearch case-fold state."
  (emacsvox-icon (if isearch-case-fold-search 'off 'on))
  (tts-speak
   (format " Case is %s significant in search"
           (if isearch-case-fold-search " not" " "))))

(defun emacsvox--advice-isearch-toggle-regexp-after (&rest _)
  "Announce the new isearch regexp state."
  (emacsvox-icon (if isearch-regexp 'on 'off))
  (tts-speak (if isearch-regexp "Regexp search" "text search")))

(defun emacsvox--advice-isearch-occur-after (&rest _)
  "Cue interactively opening isearch matches in Occur."
  (when (ems-interactive-p 'isearch-occur)
    (emacsvox-icon 'open-object)))

(provide 'emacsvox-advice-search)
;;; emacsvox-advice-search.el ends here
