;;; emacsvox-ace-window.el --- Speech-enable ACE-WINDOW  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop ace-window
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
;; ACE-WINDOW == ace-window
;; Speech-enable ace-window for fast window switching.
;; Provides auditory feedback when selecting, swapping, deleting,
;; and maximizing windows.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'ace-window nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (aw-leading-char-face voice-animate)
   (aw-background-face voice-monotone-extra)
   (aw-mode-line-face voice-bolden)))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-ace-window-after (&rest _)
  "speak."
  (when (ems-interactive-p 'ace-window)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-ace-swap-window-after (&rest _)
  "speak."
  (when (ems-interactive-p 'ace-swap-window)
    (tts-speak "Swapped windows")
    (emacsvox-icon 'task-done)))

(defun emacsvox--advice-ace-delete-window-after (&rest _)
  "speak."
  (when (ems-interactive-p 'ace-delete-window)
    (tts-speak "Deleted window")
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-ace-delete-other-windows-after (&rest _)
  "speak."
  (when (ems-interactive-p 'ace-delete-other-windows)
    (tts-speak "One window")
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-ace-window--advice-targets
  '(ace-window
    ace-swap-window
    ace-delete-window
    ace-delete-other-windows)
  "Current Ace Window commands that receive native advice.")

(defun emacsvox-ace-window--install-advice ()
  "Install advice after the optional Ace Window package loads."
  (dolist (target emacsvox-ace-window--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'ace-window
  (emacsvox-ace-window--install-advice))

(provide 'emacsvox-ace-window)

;;; emacsvox-ace-window.el ends here
