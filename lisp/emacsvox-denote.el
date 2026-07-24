;;; emacsvox-denote.el --- Speech-enable DENOTE  -*- lexical-binding: t; -*-
;; $Author: Robert Melton $
;; Description:  Speech-enable DENOTE An Emacs Interface to denote
;; Keywords: Emacsvox,  Audio Desktop denote
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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
;; DENOTE == Protesilaos Stavrou's note-taking package.
;; Speech-enable denote for creating, linking, and managing notes
;; using a strict file-naming scheme with org/markdown/text.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'denote nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (denote-faces-link voice-bolden)
   (denote-faces-subdirectory voice-smoothen)
   (denote-faces-date voice-animate)
   (denote-faces-keywords voice-lighten)
   (denote-faces-signature voice-monotone)
   (denote-faces-title voice-brighten)
   (denote-faces-delimiter voice-smoothen)
   (denote-faces-extension voice-monotone)))

;;;  Interactive Commands:

(defun emacsvox--advice-denote-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote)
    (emacsvox-icon 'open-object)
    (dtk-speak (format "Created note %s" (buffer-name)))))

(defun emacsvox--advice-denote-open-or-create-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-open-or-create)
    (emacsvox-icon 'open-object)
    (dtk-speak (format "Note %s" (buffer-name)))))

(defun emacsvox--advice-denote-rename-file-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-rename-file)
    (emacsvox-icon 'task-done)
    (dtk-speak "Renamed")))

(defun emacsvox--advice-denote-rename-file-using-front-matter-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-rename-file-using-front-matter)
    (emacsvox-icon 'task-done)
    (dtk-speak "Renamed from front matter")))

(defun emacsvox--advice-denote-link-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-link)
    (emacsvox-icon 'complete)
    (dtk-speak "Linked")))

(defun emacsvox--advice-denote-link-or-create-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-link-or-create)
    (emacsvox-icon 'complete)
    (dtk-speak "Linked")))

(defun emacsvox--advice-denote-backlinks-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-backlinks)
    (emacsvox-icon 'open-object)
    (dtk-speak "Backlinks")))

(defun emacsvox--advice-denote-keywords-add-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-keywords-add)
    (emacsvox-icon 'task-done)
    (dtk-speak "Keywords added")))

(defun emacsvox--advice-denote-keywords-remove-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-keywords-remove)
    (emacsvox-icon 'delete-object)
    (dtk-speak "Keywords removed")))

(defun emacsvox--advice-denote-dired-after (&rest _)
  "speak."
  (when (ems-interactive-p 'denote-dired)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-denote--advice
  '((denote :after emacsvox--advice-denote-after)
    (denote-open-or-create :after
     emacsvox--advice-denote-open-or-create-after)
    (denote-rename-file :after
     emacsvox--advice-denote-rename-file-after)
    (denote-rename-file-using-front-matter :after
     emacsvox--advice-denote-rename-file-using-front-matter-after)
    (denote-link :after emacsvox--advice-denote-link-after)
    (denote-link-or-create :after
     emacsvox--advice-denote-link-or-create-after)
    (denote-backlinks :after emacsvox--advice-denote-backlinks-after)
    (denote-keywords-add :after
     emacsvox--advice-denote-keywords-add-after)
    (denote-keywords-remove :after
     emacsvox--advice-denote-keywords-remove-after)
    (denote-dired :after emacsvox--advice-denote-dired-after))
  "Current Denote targets and their native advice functions.")

(defun emacsvox-denote--install-advice ()
  "Install native advice for loaded Denote commands."
  (dolist (entry emacsvox-denote--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-denote)))))))

(with-eval-after-load 'denote
  (emacsvox-denote--install-advice))

(emacsvox-denote--install-advice)

(provide 'emacsvox-denote)
;;;  end of file
