;;; emacsvox-bibtex.el --- Speech enable bibtex -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs, bibtex
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
;; Speech extensions for bibtex mode.
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)

(require 'bibtex)

(defmacro emacsvox-bibtex--define-after-advice (target &rest body)
  "Define direct after advice for interactive BibTeX TARGET using BODY."
  (declare (indent 1))
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback after `%s'." target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target :after #',function '((name . emacsvox))))))

;;;  Advice navigation commands

(dolist
    (target
     '(bibtex-next-field
       bibtex-beginning-of-entry
       bibtex-end-of-entry))
  (eval
   `(emacsvox-bibtex--define-after-advice ,target
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-line))))

(emacsvox-bibtex--define-after-advice bibtex-find-text
  (emacsvox-icon 'button)
  (emacsvox-speak-line))

;;;  Advice record editing commands

(emacsvox-bibtex--define-after-advice bibtex-remove-OPT-or-ALT
  (emacsvox-icon 'button)
  (emacsvox-speak-line))

(dolist (target '(bibtex-empty-field bibtex-kill-field))
  (eval
   `(emacsvox-bibtex--define-after-advice ,target
      (emacsvox-icon 'delete-object)
      (emacsvox-speak-line))))

(emacsvox-bibtex--define-after-advice bibtex-clean-entry
  (emacsvox-icon 'task-done)
  (message "Cleaned up entry"))

;;;  Advice record creation

(dolist
    (target
     '(bibtex-Unpublished
       bibtex-String
       bibtex-TechReport
       bibtex-Preamble
       bibtex-Proceedings
       bibtex-PhdThesis
       bibtex-Misc
       bibtex-MastersThesis
       bibtex-Manual
       bibtex-InProceedings
       bibtex-InCollection
       bibtex-InBook
       bibtex-Book
       bibtex-Article))
  (eval
   `(emacsvox-bibtex--define-after-advice ,target
      (emacsvox-icon 'open-object)
      (emacsvox-speak-line))))

(provide  'emacsvox-bibtex)

;;; emacsvox-bibtex.el ends here
