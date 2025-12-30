;;; emacsvox-etable.el --- Speech enable table.el  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for table.el
;; Keywords:emacsvox, audio interface to emacs Tables
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



;;; Commentary:
;; table.el provides rich table editing for emacs.
;; this module speech-enables table.el
;;; Code:

;;  required modules 

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

(require 'table )

;;;  Update command remap list.

(defun ems--table--make-cell-map-after (&rest _)
  "Set up emacsvox for table.el"
  
  (when table-cell-map
    (cl-loop for k in
	     (where-is-internal 'emacsvox-self-insert-command
				(list table-cell-map))
	     do
	     (define-key table-cell-map k
			 '*table--cell-self-insert-command))
    (cl-loop for k in
	     '(("S-TAB" table-backward-cell)
	       ("." emacsvox-etable-speak-cell))
	     do (emacsvox-keymap-update table-cell-map k))))


(advice-add 'table--make-cell-map :after
	    #'ems--table--make-cell-map-after)




;;;  Advice edit commands


(defun ems--*table--cell-delete-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacsvox-speak-char t) (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add '*table--cell-delete-char :around
	    #'ems--*table--cell-delete-char-around)





(defun ems--*table--cell-delete-backward-char-around
    (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacsvox-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add '*table--cell-delete-backward-char :around
	    #'ems--*table--cell-delete-backward-char-around)





(defun ems--*table--cell-self-insert-command-after (&rest _)
  "Provide spoken output."
  (when (ems-interactive-p)
    (cond
     ((and (= 32 last-input-event) emacsvox-word-echo)
      (save-excursion
	(let ((orig (point)))
	  (table--finish-delayed-tasks) (backward-word 1)
	  (emacsvox-speak-region orig (point)))))
     (emacsvox-character-echo (dtk-stop)
			       (emacsvox-speak-this-char
				last-input-event)))))


(advice-add '*table--cell-self-insert-command :after
	    #'ems--*table--cell-self-insert-command-after)





(defun ems--*table--cell-quoted-insert-after (&rest _)
  "Speak the character that was inserted."
  (when (ems-interactive-p)
    (table--finish-delayed-tasks)
    (emacsvox-speak-this-char (preceding-char))))


(advice-add '*table--cell-quoted-insert :after
	    #'ems--*table--cell-quoted-insert-after)





(defun ems--*table--cell-newline-before (&rest _)
  "Speak the previous line if line echo is on.\nSee command \\[emacsvox-toggle-line-echo].  Otherwise cue the user to\nthe newly created blank line."
  
  (when (ems-interactive-p)
    (table--finish-delayed-tasks)
    (cond (emacsvox-line-echo (emacsvox-speak-line))
	  (t (if dtk-stop-immediately (dtk-stop))
	     (dtk-tone 225 120 'force)))))


(advice-add '*table--cell-newline :before
	    #'ems--*table--cell-newline-before)





(defun ems--*table--cell-newline-and-indent-around
    (orig-fun &rest args)
  "Speak the previous line if line echo is on.\nSee command \\[emacsvox-toggle-line-echo].\nOtherwise cue user to the line just created."
  (let ((result (apply orig-fun args)))
    
    (cond
     ((ems-interactive-p)
      (cond (emacsvox-line-echo (emacsvox-speak-line))
	    (t
	     (dtk-speak-using-voice voice-annotate
				    (format "indent %s"
					    (current-column)))
	     (dtk-interp-speak)))))
    (apply orig-fun args) result))


(advice-add '*table--cell-newline-and-indent :around
	    #'ems--*table--cell-newline-and-indent-around)





(defun ems--*table--cell-open-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((count (ad-get-arg 0)))
      (emacsvox-icon 'open-object)
      (message "Opened %s blank line%s" (if (= count 1) "a" count)
	       (if (= count 1) "" "s")))))


(advice-add '*table--cell-open-line :after
	    #'ems--*table--cell-open-line-after)




;;;  speak cell contents:

(defun emacsvox-etable-speak-cell ()
  "Speak current cell."
  (interactive)
  (let ((cell (table--probe-cell 'no-error)))
    (cond
     (cell
      (emacsvox-speak-rectangle
       (car cell)
       (cdr cell)))
     (t (error "Can't identify cell.")))))

(cl-loop for f in
         '(table-forward-cell table-backward-cell)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak by speaking current cell
      contents."
             (when (ems-interactive-p)
               (table--finish-delayed-tasks)
               (emacsvox-icon 'select-object)
               (emacsvox-etable-speak-cell)))))

(provide  'emacsvox-etable)

