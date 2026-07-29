;;; emacsvox-tabulated-list.el --- Speech-enable   -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable TABULATED-LIST 
;;; Keywords: Emacsvox,  Audio Desktop tabulated-list
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; TABULATED-LIST ==  tabulated list mode
;; Speech-enable tabulated lists and provide commands for intelligent
;; spoken output 

;;; Code:

;;; Forward variable declarations:

(defvar tabulated-list-format)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'tabulated-list)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (tabulated-list-fake-header voice-bolden)))

;;;  Interactive Commands:

(defun emacsvox-tabulated-list--cell-facts (empty)
  "Return semantic facts for the current field, including EMPTY state."
  (append
   '(:role field)
   (when empty '(:states (empty)))))

(defun emacsvox-tabulated-list--submit-cell (content facts)
  "Submit cell CONTENT and FACTS through aural presentation policy."
  (if (zerop (length content))
      (emacsvox-aural-submit-actions
       :facts facts :module 'tabulated-list :occasion 'navigation)
    (emacsvox-aural-submit
     content :facts facts :module 'tabulated-list :occasion 'navigation)))

(defun emacsvox-tabulated-list-speak-cell ()
  "Speak current cell. "
  (interactive)
  (when (bobp) (error "Beginning  of buffer"))
  (when (eobp) (error "End of buffer"))
  (save-excursion
    (when-let*
        ((name (get-text-property (point) 'tabulated-list-column-name))
         (col
          (cl-position name tabulated-list-format
                       :test #'string= :key #'car))
         (value (elt (tabulated-list-get-entry)  col)))
      (when (= 0 col) (emacsvox-icon 'left))
      (when (= (1- (length tabulated-list-format)) col)
        (emacsvox-icon 'right))
      (when (listp value) (setq value (car value)))
      (let* ((empty (zerop (length (string-trim value))))
             (content
              (if (called-interactively-p 'interactive)
                  (concat name " " value)
                value)))
        (emacsvox-tabulated-list--submit-cell
         content
         (emacsvox-tabulated-list--cell-facts empty))))))

(cl-loop
 for target in
 '(tabulated-list-next-column tabulated-list-previous-column)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Tabulated List column movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-tabulated-list-speak-cell)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox-tabulated-list-next-row ()
  "Move to next row and speak that cell"
  (interactive)
  (let ((col
         (cl-position
          (get-text-property (point) 'tabulated-list-column-name)
          tabulated-list-format
          :test #'string= :key #'car)))
    (forward-line 1)
    (tabulated-list-next-column  col)
    (when-let* ((goal (next-single-property-change (point)
                                                  'tabulated-list-column-name)))
      (goto-char goal))
    (emacsvox-tabulated-list-speak-cell)))

(defun emacsvox-tabulated-list-previous-row ()
  "Move to previous row and speak that cell."
  (interactive)
  (let ((col
         (cl-position
          (get-text-property (point) 'tabulated-list-column-name)
          tabulated-list-format
          :test #'string= :key #'car)))
    (forward-line -1)
    (tabulated-list-next-column  col)
    (when-let* ((goal (next-single-property-change
                      (point) 'tabulated-list-column-name)))
      (goto-char goal))
    (emacsvox-tabulated-list-speak-cell)))

(defun emacsvox-tabulated-list-setup ()
  "Setup Emacsvox"
  
  (cl-loop
   for b in
   '(
     ( "." emacsvox-tabulated-list-speak-cell)
     ("<down>"  emacsvox-tabulated-list-next-row)
     ("<left>" tabulated-list-previous-column)
     ("<right>" tabulated-list-next-column)
     ("<up>" emacsvox-tabulated-list-previous-row))
   do
   
   (emacsvox-keymap-update tabulated-list-mode-map b)))

(emacsvox-tabulated-list-setup)

(provide 'emacsvox-tabulated-list)
;;;  end of file

                                        ; 
                                        ; 
                                        ; 
