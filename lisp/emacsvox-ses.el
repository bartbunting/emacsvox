;;; emacsvox-ses.el --- Speech-enable ses -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for SES 
;; Keywords: Emacsvox, ses 
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; ses implements a simple spread sheet and is part of Emacs
;; This module speech-enables ses
;;; Code:

;;  required modules

;;; Code:
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'ses)

;;;  emacsvox ses accessors 

;; these additional accessors are defined in terms of the
;; earlier helpers by Emacsvox.
(defun emacsvox-ses-current-cell-symbol ()
  "Return symbol for current cell."
  (or 
   (get-text-property (point) 'cursor-intangible)
   (get-text-property (point) 'intangible)))

(defun emacsvox-ses-current-cell-value ()
  "Return current cell value."
  
  (ses-cell-value
   (car (ses-sym-rowcol (emacsvox-ses-current-cell-symbol)))
   (cdr (ses-sym-rowcol (emacsvox-ses-current-cell-symbol)))))

(defun emacsvox-ses-get-cell-value-by-name (cell-name)
  "Return current  value of cell specified by name."
  
  (ses-cell-value
   
   (car (ses-sym-rowcol cell-name))
   (cdr (ses-sym-rowcol cell-name))))

;;;  emacsvox ses summarizers 

(defun emacsvox-ses-summarize-cell (cell-name)
  "Summarize specified  cell."
  (interactive
   (list
    (read-minibuffer "Cell: ")))
  (cond
   (cell-name
    (dtk-speak
     (format "%s: %s"
             cell-name
             (emacsvox-ses-get-cell-value-by-name cell-name))))
   (t (message "No cell here"))))

(defun emacsvox-ses-summarize-current-cell (&rest _ignore)
  "Summarize current cell."
  (interactive)
  (emacsvox-ses-summarize-cell
   (emacsvox-ses-current-cell-symbol)))

;;;  advice internals

;;;  new navigation commands 

;; ses uses intangible properties to enable cell navigation
;; here we define navigation primitives that call built-ins and
;;then speak the right information.

(defun emacsvox-ses-forward-column-and-summarize ()
  "Move to next column and summarize."
  (interactive)
  (forward-char)
  (emacsvox-ses-summarize-current-cell))

(defun emacsvox-ses-backward-column-and-summarize ()
  "Move to previous column and summarize."
  (interactive)
  (forward-char -1)
  (emacsvox-ses-summarize-current-cell))

(defun emacsvox-ses-forward-row-and-summarize ()
  "Move to next row and summarize."
  (interactive)
  (forward-line 1)
  (emacsvox-ses-summarize-current-cell))

(defun emacsvox-ses-backward-row-and-summarize ()
  "Move to previous row  and summarize."
  (interactive)
  (forward-line -1)
  (emacsvox-ses-summarize-current-cell))

;;;  advice interactive commands

(defun emacsvox-ses-setup ()
  "Setup SES for use with emacsvox."
  
  )


(defun ems--ses-forward-or-insert-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ses-summarize-current-cell)))


(advice-add 'ses-forward-or-insert :after
	    #'ems--ses-forward-or-insert-after)





(defun ems--ses-recalculate-cell-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ses-summarize-current-cell) (emacsvox-icon 'task-done)))


(advice-add 'ses-recalculate-cell :after
	    #'ems--ses-recalculate-cell-after)





(defun ems--ses-jump-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ses-summarize-current-cell)))


(advice-add 'ses-jump :after #'ems--ses-jump-after)




;;;  Setup:

(emacsvox-ses-setup)

(provide 'emacsvox-ses)
;;;  end of file

