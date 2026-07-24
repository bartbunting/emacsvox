;;; emacsvox-embark.el --- Speech-enable EMBARK  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable EMBARK An Emacs Interface to embark
;; Keywords: Emacsvox,  Audio Desktop embark
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;;
;; This file is not part of GNU Emacs, but the same permissions apply.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


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
    (dtk-speak
     (format "Collected into %s" (buffer-name)))))

(defun emacsvox--advice-embark-export-after (&rest _)
  "Announce export result."
  (when (ems-interactive-p 'embark-export)
    (emacsvox-icon 'task-done)
    (dtk-speak
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
;;;  end of file
