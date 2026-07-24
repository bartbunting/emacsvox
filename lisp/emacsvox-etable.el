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



;;; Commentary:
;; table.el provides rich table editing for emacs.
;; this module speech-enables table.el
;;; Code:

;;  required modules 

(require 'emacsvox-preamble)

(require 'table )

;;;  Update command remap list.

(defun emacsvox--advice-table--make-cell-map-after (&rest _)
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

(advice-add
 'table--make-cell-map :after
 #'emacsvox--advice-table--make-cell-map-after
 '((name . emacsvox)))

;;;  Advice edit commands

(defun emacsvox--advice-*table--cell-delete-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (when (ems-interactive-p '*table--cell-delete-char)
    (tts-tone 500 100 'force)
    (emacsvox-speak-char t))
  (apply orig-fun args))

(advice-add
 '*table--cell-delete-char :around
 #'emacsvox--advice-*table--cell-delete-char-around
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-delete-backward-char-around
    (orig-fun &rest args)
  "Speak character you're deleting."
  (when (ems-interactive-p '*table--cell-delete-backward-char)
    (tts-tone 500 100 'force)
    (emacsvox-speak-this-char (preceding-char)))
  (apply orig-fun args))

(advice-add
 '*table--cell-delete-backward-char :around
 #'emacsvox--advice-*table--cell-delete-backward-char-around
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-self-insert-command-after (&rest _)
  "Provide spoken output."
  (when (ems-interactive-p '*table--cell-self-insert-command)
    (cond
     ((and (= 32 last-input-event) emacsvox-word-echo)
      (save-excursion
        (let ((orig (point)))
          (table--finish-delayed-tasks) (backward-word 1)
          (emacsvox-speak-region orig (point)))))
     (emacsvox-character-echo (tts-stop)
                              (emacsvox-speak-this-char
                               last-input-event)))))

(advice-add
 '*table--cell-self-insert-command :after
 #'emacsvox--advice-*table--cell-self-insert-command-after
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-quoted-insert-after (&rest _)
  "Speak the character that was inserted."
  (when (ems-interactive-p '*table--cell-quoted-insert)
    (table--finish-delayed-tasks)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 '*table--cell-quoted-insert :after
 #'emacsvox--advice-*table--cell-quoted-insert-after
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-newline-before (&rest _)
  "Speak the previous line if line echo is on.\nSee command \\[emacsvox-toggle-line-echo].  Otherwise cue the user to\nthe newly created blank line."
  
  (when (ems-interactive-p '*table--cell-newline)
    (table--finish-delayed-tasks)
    (cond (emacsvox-line-echo (emacsvox-speak-line))
          (t (if tts-stop-immediately (tts-stop))
             (tts-tone 225 120 'force)))))

(advice-add
 '*table--cell-newline :before
 #'emacsvox--advice-*table--cell-newline-before
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-newline-and-indent-around
    (orig-fun &rest args)
  "Speak the previous line if line echo is on.\nSee command \\[emacsvox-toggle-line-echo].\nOtherwise cue user to the line just created."
  (when (ems-interactive-p '*table--cell-newline-and-indent)
    (cond
     (emacsvox-line-echo (emacsvox-speak-line))
     (t
      (tts-speak-using-voice
       voice-annotate (format "indent %s" (current-column)))
      (tts--protocol-dispatch))))
  (apply orig-fun args))

(advice-add
 '*table--cell-newline-and-indent :around
 #'emacsvox--advice-*table--cell-newline-and-indent-around
 '((name . emacsvox)))

(defun emacsvox--advice-*table--cell-open-line-after (count &rest _)
  "speak."
  (when (ems-interactive-p '*table--cell-open-line)
    (emacsvox-icon 'open-object)
    (message "Opened %s blank line%s" (if (= count 1) "a" count)
             (if (= count 1) "" "s"))))

(advice-add
 '*table--cell-open-line :after
 #'emacsvox--advice-*table--cell-open-line-after
 '((name . emacsvox)))

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

(cl-loop for target in
         '(table-forward-cell table-backward-cell)
         for function =
         (intern (format "emacsvox--advice-%s-after" target))
         do
         (eval
          `(progn
             (defun ,function (&rest _)
               "Speak the cell selected by an interactive table command."
               (when (ems-interactive-p ',target)
                 (table--finish-delayed-tasks)
                 (emacsvox-icon 'select-object)
                 (emacsvox-etable-speak-cell)))
             (advice-add
              ',target :after #',function '((name . emacsvox))))))

(provide  'emacsvox-etable)
