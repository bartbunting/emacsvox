;;; emacsvox-speak-completion.el --- Completion reading and navigation -*- lexical-binding: t; -*-

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

;; Completion reading and navigation.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'minibuffer)
(require 'tts-speak)
(require 'emacsvox-aural-source)

(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))

;;;  Completion helper:

(defun emacsvox-speak-completions-if-available ()
  "Speak completions if available."
  (interactive)
  (let ((completions (get-buffer "*Completions*")))
    (cond
     ((and completions
           (window-live-p (get-buffer-window completions)))
      (with-minibuffer-completions-window
        (emacsvox-icon 'help)
        (tts-chunk-on-white-space-and-punctuations)
        (next-completion 1)
        (tts-with-punctuations
         'all (emacsvox-speak-line))))
     (t (emacsvox-speak-line)))))

(defun emacsvox-get-current-completion ()
  "Return the completion under point in the *Completions* buffer."
  (with-minibuffer-completions-window
    (let (beg end)
      (if (and (not (eobp)) (get-text-property (point) 'completion--string))
          (setq end (point) beg (1+ (point))))
      (if (and (not (bobp))
               (get-text-property (1- (point)) 'completion--string))
          (setq end (1- (point)) beg (point)))
      (if (and  (bobp)
                (next-completion 1))
          (setq end (1- (point)) beg (point)))
      (if (null beg) (error "No current  completion "))
      (setq beg (or
                 (previous-single-property-change beg 'completion--string)
                 (point-min)))
      (setq end
            (or (next-single-property-change end 'completion--string)
                (point-max)))
      (emacsvox-aural-source-substring beg end))))

;;;   completion helpers

;; switching to completions window from minibuffer:

(defun emacsvox-get-minibuffer-contents ()
  "Return contents of the minibuffer."
  (save-current-buffer
    (set-buffer (window-buffer (minibuffer-window)))
    (minibuffer-contents)))

(defun emacsvox-switch-to-reference-buffer ()
  "Switch back to buffer that generated completions."
  (interactive)

  (if completion-reference-buffer
      (switch-to-buffer completion-reference-buffer)
    (error "Reference buffer not found."))
  (when (called-interactively-p 'interactive)
    (emacsvox-speak-line)
    (emacsvox-icon 'select-object)))

(defun emacsvox-completions-move-to-completion-group ()
  "Move to group of choices beginning with character last
typed. If no such group exists, then we try to search for that
char, or dont move. "
  (interactive)

  (let ((pattern
         (format
          "[ \t\n]%s%c"
          (or (emacsvox-get-minibuffer-contents) "")
          last-input-event))
        (input (format "%c" last-input-event))
        (case-fold-search t))
    (when (or (re-search-forward pattern nil t)
              (re-search-backward pattern nil t)
              (search-forward input nil t)
              (search-backward input nil t))
      (skip-syntax-forward " ")
      (emacsvox-icon 'search-hit))
    (tts-speak (emacsvox-get-current-completion))))

(defun emacsvox-completion-setup-hook ()
  "Set things up for emacsvox."
  (with-minibuffer-completions-window
    (goto-char (point-min))
    (emacsvox-icon 'help)))

(provide 'emacsvox-speak-completion)

;;; emacsvox-speak-completion.el ends here
