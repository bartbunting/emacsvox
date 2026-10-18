;;; emacsvox-embark.el --- Speech-enable EMBARK  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop embark
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
;; EMBARK == Context actions framework.
;; This module speech-enables embark.
;; Embark provides a context-action framework for Emacs, similar to a
;; right-click menu.  It works with vertico/consult for completion actions.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'embark nil 'noerror)

;;;  Forward Declarations:

(declare-function embark-act "embark" (&optional arg))
(declare-function embark-dwim "embark" (&optional arg))
(declare-function embark-collect "embark" nil)
(declare-function embark-export "embark" nil)
(declare-function embark-become "embark" nil)
(defvar embark-indicators)
(defvar embark-prompter)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (embark-keybinding voice-animate)
   (embark-target voice-bolden)))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-embark-act-after (&rest _)
  "Announce action completed."
  (when (ems-interactive-p 'embark-act)
    (emacsvox-icon 'button)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-embark-dwim-after (&rest _)
  "Announce default action taken."
  (when (ems-interactive-p 'embark-dwim)
    (emacsvox-icon 'button)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-embark-collect-after (&rest _)
  "Announce collect buffer."
  (when (ems-interactive-p 'embark-collect)
    (emacsvox-icon 'open-object)
    (tts-speak
     (format "Collected into %s" (buffer-name)))))

(defun emacsvox--advice-embark-export-after (&rest _)
  "Announce export result."
  (when (ems-interactive-p 'embark-export)
    (emacsvox-icon 'task-done)
    (tts-speak
     (format "Exported to %s" (buffer-name)))))

(defun emacsvox--advice-embark-become-after (&rest _)
  "Announce mode change."
  (when (ems-interactive-p 'embark-become)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-embark--advice
  '((embark-act :after emacsvox--advice-embark-act-after)
    (embark-dwim :after emacsvox--advice-embark-dwim-after)
    (embark-collect :after emacsvox--advice-embark-collect-after)
    (embark-export :after emacsvox--advice-embark-export-after)
    (embark-become :after emacsvox--advice-embark-become-after))
  "Current Embark targets and their native advice functions.")

(defun emacsvox-embark--install-advice ()
  "Install native advice for loaded Embark commands."
  (dolist (entry emacsvox-embark--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-embark)))))))

(with-eval-after-load 'embark
  (emacsvox-embark--install-advice))

(emacsvox-embark--install-advice)

(provide 'emacsvox-embark)

;;; emacsvox-embark.el ends here
