;;; emacsvox-desktop.el ---  Speech-enable desktop  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop, DESKTOP
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
;; advice desktop package
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'desktop)
;;; Interactive Command: Preserve buffer
;;;###autoload
(defun emacsvox-desktop-preserve (buffer)
  "Preserve: Dont kill this buffer when clearing desktop."
  (interactive
   (list (read-buffer "Preserve Buffer: " (current-buffer) t)))
  
  (cl-pushnew buffer desktop-clear-preserve-buffers)
  (message "Preserving %s for this session." buffer))

;;;   desktop

(defun emacsvox--advice-desktop-clear-after (&rest _)
  "speak."
  (when (ems-interactive-p 'desktop-clear)
    (emacsvox-speak-mode-line) (tts-notify "cleared desktop")
    (emacsvox-icon 'delete-object)))

(advice-add 'desktop-clear :after
            #'emacsvox--advice-desktop-clear-after)

(defun emacsvox--advice-desktop-save-after (&rest _)
  "speak."
  (when (ems-interactive-p 'desktop-save)
    (emacsvox-icon 'save-object)))

(advice-add 'desktop-save :after
            #'emacsvox--advice-desktop-save-after)

(defun emacsvox--advice-desktop-lazy-create-buffer-around
    (orig-fun &rest args)
  "Silence messages."
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'desktop-lazy-create-buffer :around
            #'emacsvox--advice-desktop-lazy-create-buffer-around)

(provide 'emacsvox-desktop)

;;; emacsvox-desktop.el ends here
