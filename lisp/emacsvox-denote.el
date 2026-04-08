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

(defun ems--denote-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak (format "Created note %s" (buffer-name)))))

(advice-add 'denote :after #'ems--denote-after)

(defun ems--denote-open-or-create-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak (format "Note %s" (buffer-name)))))

(advice-add 'denote-open-or-create :after #'ems--denote-open-or-create-after)

(defun ems--denote-rename-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Renamed")))

(advice-add 'denote-rename-file :after #'ems--denote-rename-file-after)

(defun ems--denote-rename-file-using-front-matter-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Renamed from front matter")))

(advice-add 'denote-rename-file-using-front-matter :after
            #'ems--denote-rename-file-using-front-matter-after)

(defun ems--denote-link-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'complete)
    (dtk-speak "Linked")))

(advice-add 'denote-link :after #'ems--denote-link-after)

(defun ems--denote-link-or-create-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'complete)
    (dtk-speak "Linked")))

(advice-add 'denote-link-or-create :after #'ems--denote-link-or-create-after)

(defun ems--denote-backlinks-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Backlinks")))

(advice-add 'denote-backlinks :after #'ems--denote-backlinks-after)

(defun ems--denote-keywords-add-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Keywords added")))

(advice-add 'denote-keywords-add :after #'ems--denote-keywords-add-after)

(defun ems--denote-keywords-remove-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (dtk-speak "Keywords removed")))

(advice-add 'denote-keywords-remove :after #'ems--denote-keywords-remove-after)

(defun ems--denote-dired-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(advice-add 'denote-dired :after #'ems--denote-dired-after)

(provide 'emacsvox-denote)
;;;  end of file
