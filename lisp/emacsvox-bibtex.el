;;; emacsvox-bibtex.el --- Speech enable bibtex -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Emacsvox extension for editing bibtex files 
;; Keywords:emacsvox, audio interface to emacs, bibtex
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman 
;; Copyright (c) 1995 by T. V. Raman  
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


;;  required modules 
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;   Introduction
;;; Commentary:
;; Speech extensions for bibtex mode.
;;; Code:

;;;  Advice navigation commands

(defun ems--bibtex-next-field-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'bibtex-next-field :after #'ems--bibtex-next-field-after)

(defun ems--bibtex-find-text-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-line)))

(advice-add 'bibtex-find-text :after #'ems--bibtex-find-text-after)

(defun ems--end-of-bibtex-entry-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'end-of-bibtex-entry :after
            #'ems--end-of-bibtex-entry-after)

(defun ems--beginning-of-bibtex-entry-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'beginning-of-bibtex-entry :after
            #'ems--beginning-of-bibtex-entry-after)

;;;  Advice record editing commands

(defun ems--bibtex-remove-OPT-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-line)))

(advice-add 'bibtex-remove-OPT :after #'ems--bibtex-remove-OPT-after)

(defun ems--bibtex-empty-field-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'bibtex-empty-field :after #'ems--bibtex-empty-field-after)

(defun ems--bibtex-kill-optional-field-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'bibtex-kill-optional-field :after
            #'ems--bibtex-kill-optional-field-after)

(defun ems--bibtex-clean-entry-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (message "Cleaned up entry")))

(advice-add 'bibtex-clean-entry :after #'ems--bibtex-clean-entry-after)

;;;   advice record creation

;; list of commands that are advised:
                                        ;'(bibtex-Unpublished 
                                        ;        bibtex-string
                                        ;        bibtex-TechReport
                                        ;        bibtex-preamble
                                        ;        bibtex-Proceedings
                                        ;        bibtex-PhdThesis
                                        ;        bibtex-Misc
                                        ;        bibtex-MastersThesis
                                        ;        bibtex-Manual
                                        ;        bibtex-InProceedings
                                        ;        bibtex-InCollection
                                        ;        bibtex-InBook
                                        ;        bibtex-InProceedings
                                        ;        bibtex-Book
                                        ;        bibtex-Article)

(defun ems--bibtex-Unpublished-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Unpublished :after #'ems--bibtex-Unpublished-after)

(defun ems--bibtex-string-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-string :after #'ems--bibtex-string-after)

(defun ems--bibtex-TechReport-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-TechReport :after #'ems--bibtex-TechReport-after)

(defun ems--bibtex-preamble-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-preamble :after #'ems--bibtex-preamble-after)

(defun ems--bibtex-Proceedings-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Proceedings :after #'ems--bibtex-Proceedings-after)

(defun ems--bibtex-PhdThesis-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-PhdThesis :after #'ems--bibtex-PhdThesis-after)

(defun ems--bibtex-Misc-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Misc :after #'ems--bibtex-Misc-after)

(defun ems--bibtex-MastersThesis-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-MastersThesis :after
            #'ems--bibtex-MastersThesis-after)

(defun ems--bibtex-Manual-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Manual :after #'ems--bibtex-Manual-after)

(defun ems--bibtex-InProceedings-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-InProceedings :after
            #'ems--bibtex-InProceedings-after)

(defun ems--bibtex-InCollection-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-InCollection :after
            #'ems--bibtex-InCollection-after)

(defun ems--bibtex-InBook-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-InBook :after #'ems--bibtex-InBook-after)

(defun ems--bibtex-InProceedings-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-InProceedings :after
            #'ems--bibtex-InProceedings-after)

(defun ems--bibtex-Book-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Book :after #'ems--bibtex-Book-after)

(defun ems--bibtex-Article-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'bibtex-Article :after #'ems--bibtex-Article-after)

(provide  'emacsvox-bibtex)

