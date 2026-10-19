;;; emacsvox-advice-windows.el --- Core buffer and window feedback -*- lexical-binding: t; -*-

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

;; Core buffer and window feedback.
;; Load through `emacsvox-advice'.  The facade owns activation.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox--advice-find-file-after (&rest _)
  "Play an auditory icon if possible."
  (when (ems-interactive-p 'find-file)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-kill-buffer-around (original &rest arguments)
  "Announce the destination after ORIGINAL finishes killing a buffer.
Consume the interactive marker before cleanup can kill related buffers."
  (let* ((interactive (ems-interactive-p 'kill-buffer))
         (result (apply original arguments)))
    (when (and interactive result)
      (emacsvox-icon 'close-object)
      (tts-stop 'all)
      (emacsvox-speak-mode-line))
    result))

(defun emacsvox--advice-pop-to-buffer-after (&rest _)
  "Announce an interactive buffer pop."
  (when (ems-interactive-p 'pop-to-buffer)
    (emacsvox-icon 'tick-tick) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-scratch-buffer-after (&rest _)
  "Announce switching to the scratch buffer."
  (when (ems-interactive-p 'scratch-buffer)
    (emacsvox-icon 'tick-tick) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-display-buffer-after (buffer-or-name &rest _)
  "Announce interactively displaying BUFFER-OR-NAME."
  (when (ems-interactive-p 'display-buffer)
    (emacsvox-icon 'open-object)
    (message "Displayed %s"
             (if (bufferp buffer-or-name)
                 (buffer-name buffer-or-name)
               buffer-or-name))))

(defun emacsvox--advice-make-frame-command-after (&rest _)
  "Announce interactively creating a frame."
  (when (ems-interactive-p 'make-frame-command)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-move-to-window-line-after (&rest _)
  "Speak after interactively moving within a window."
  (when (ems-interactive-p 'move-to-window-line)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(defun emacsvox--advice-rename-buffer-after (&rest _)
  "Speak the mode line after interactively renaming a buffer."
  (when (ems-interactive-p 'rename-buffer)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-rename-uniquely-after (&rest _)
  "Speak the mode line after interactively making a buffer name unique."
  (when (ems-interactive-p 'rename-uniquely)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-delete-other-windows-after (&rest _)
  "Announce interactively deleting all other windows."
  (when (ems-interactive-p 'delete-other-windows)
    (message "Deleted all other windows")
    (emacsvox-icon 'window-resize) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-split-window-vertically-after (&rest _)
  "Announce an interactive vertical window split."
  (when (ems-interactive-p 'split-window-vertically)
    (message "Split window vertically, current window has %s lines "
             (window-height))
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-delete-window-after (&rest _)
  "Announce interactively deleting the selected window."
  (when (ems-interactive-p 'delete-window)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-split-window-horizontally-after (&rest _)
  "Announce an interactive horizontal window split."
  (when (ems-interactive-p 'split-window-horizontally)
    (message
     "Split window horizontally current window has %s columns "
     (window-width))
    (emacsvox-speak-mode-line)))

(defun emacsvox-speak-announce-server-buffer ()
  "Announce opening of an emacsclient buffer."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(defun emacsvox--advice-revert-buffer-quick-after (&rest _)
  "speak."
  (when (ems-interactive-p 'revert-buffer-quick)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(provide 'emacsvox-advice-windows)
;;; emacsvox-advice-windows.el ends here
