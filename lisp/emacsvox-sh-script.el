;;; emacsvox-sh-script.el --- Speech enable script -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; This module speech-enables sh-script.el 

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'sh-script)

;;;   advice interactive commands

(defun emacsvox--advice-sh-mode-after (&rest _)
  "Speech-enable sh-script editing."
  (tts-apply-punctuation-mode-policy)
  (unless emacsvox-audio-indentation
    (emacsvox-toggle-audio-indentation))
  (emacsvox-speak-mode-line))

(advice-add 'sh-mode :after
            #'emacsvox--advice-sh-mode-after)

(defun emacsvox-sh-script--interactive-insertion-p ()
  "Return non-nil when a self-insertion command is active."
  (or (ems-interactive-p 'self-insert-command)
      (ems-interactive-p 'skeleton-pair-insert-maybe)
      (ems-interactive-p 'sh-assignment)))

(defun emacsvox--advice-sh--maybe-here-document-around (orig-fun)
  "Call ORIG-FUN once and announce an inserted here document."
  (let ((start (point))
        (interactive-p (emacsvox-sh-script--interactive-insertion-p))
        result)
    (setq result (funcall orig-fun))
    (when (and interactive-p (/= (point) start))
      (message "Started a shell here document."))
    result))

(advice-add 'sh--maybe-here-document :around
            #'emacsvox--advice-sh--maybe-here-document-around)

(defun emacsvox--advice-sh-beginning-of-command-after (&rest _)
  "Speak point moved to."
  (when (ems-interactive-p 'sh-beginning-of-command)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'sh-beginning-of-command :after
            #'emacsvox--advice-sh-beginning-of-command-after)

(defun emacsvox--advice-sh-end-of-command-after (&rest _)
  "Speak point moved to."
  (when (ems-interactive-p 'sh-end-of-command)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'sh-end-of-command :after
            #'emacsvox--advice-sh-end-of-command-after)

(provide 'emacsvox-sh-script)

;;; emacsvox-sh-script.el ends here
