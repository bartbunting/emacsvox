;;; emacsvox-forms.el --- Speech enable  forms mode -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for forms-mode 
;; Keywords:emacsvox, audio interface to emacs forms 
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
;; Copyright (c) 1996 by T. V. Raman 
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


;;;  requires

(require 'forms)
(require 'emacsvox-preamble)

;;; Commentary:
;; Provide additional advice to forms-mode 
;;; Code:

;;;  Helper functions

(defvar emacsvox-forms-current-record-summarizer
  'emacsvox-forms-speak-field
  "Summarizer function for summarizing a record. Default is to
speak the first field")
(make-variable-buffer-local
 emacsvox-forms-current-record-summarizer)

(defun emacsvox-forms-summarize-current-record ()
  "Summarize current record"
  (interactive)
  
  (funcall emacsvox-forms-current-record-summarizer))

(defun emacsvox-forms-summarize-current-position ()
  "Summarize current position in list of records"
  (interactive)
  (cl-declare (special forms--current-record forms--total-records
                       forms-file))
  (dtk-speak
   (format "Record %s of %s from %s"
           forms--current-record forms--total-records forms-file)))

(defvar emacsvox-forms-rw-voice 'paul
  "Personality for read-write fields. ")

(defvar emacsvox-forms-ro-voice voice-annotate
  "Personality for read-only fields. ")

(defun emacsvox-forms-speak-field ()
  "Speak current form field name and value.
Assumes that point is at the front of a field value."
  (interactive)
  (let ((name nil)
        (value nil)
        (n-start nil))
    (save-excursion
      (backward-char 1)
      (setq n-start (point)))
    (setq name (buffer-substring n-start (point)))
    (setq value
          (buffer-substring
           (point)
           (or
            (next-single-property-change (point) 'read-only)
            (point))))
    (put-text-property 0 (length name)
                       'personality
                       emacsvox-forms-ro-voice name)
    (put-text-property 0 (length value)
                       'personality emacsvox-forms-rw-voice value)
    (dtk-speak (concat name " " value))))

;;;  Advise interactive  commands
(cl-loop
 for target in
 '(forms-search-forward forms-search-backward)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Forms search."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'search-hit)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in '(forms-next-record forms-prev-record)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and summarize after interactive Forms record movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (goto-char
          (next-single-property-change
           (point) 'read-only (current-buffer) (point-max)))
         (emacsvox-forms-summarize-current-record)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in '(forms-first-record forms-last-record forms-jump-record)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and summarize after interactive Forms record selection."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-forms-summarize-current-record)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-forms-exit-after (&rest _)
  "Cue and speak the mode line after interactively exiting Forms."
  (when (ems-interactive-p 'forms-exit)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'forms-exit :after #'emacsvox--advice-forms-exit-after
 '((name . emacsvox)))

(cl-loop
 for target in '(forms-next-field forms-prev-field)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Forms field movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-forms-speak-field)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-forms-delete-record-after (&rest _)
  "Cue after interactively deleting a Forms record."
  (when (ems-interactive-p 'forms-delete-record)
    (emacsvox-icon 'delete-object)))

(advice-add
 'forms-delete-record :after #'emacsvox--advice-forms-delete-record-after
 '((name . emacsvox)))

(defun emacsvox--advice-forms-insert-record-after (&rest _)
  "Cue after interactively inserting a Forms record."
  (when (ems-interactive-p 'forms-insert-record)
    (emacsvox-icon 'open-object)))

(advice-add
 'forms-insert-record :after #'emacsvox--advice-forms-insert-record-after
 '((name . emacsvox)))

(defun emacsvox--advice-forms-save-buffer-after (&rest _)
  "Cue after interactively saving a Forms buffer."
  (when (ems-interactive-p 'forms-save-buffer)
    (emacsvox-icon 'save-object)))

(advice-add
 'forms-save-buffer :after #'emacsvox--advice-forms-save-buffer-after
 '((name . emacsvox)))

;;;  smart filters

(defun emacsvox-forms-flush-unwanted-records ()
  "Prompt for pattern and flush matching lines"
  (interactive)
  (let ((pattern (read-from-minibuffer
                  "Specify filter pattern")))
    (when (> (length pattern) 0)
      (flush-lines
       pattern))))

(defun emacsvox-forms-rerun-filter ()
  "Rerun filter --allows us to nuke more matching records"
  (interactive)
  (cl-declare (special forms--file-buffer
                       forms--total-records forms-read-only))
  (with-current-buffer forms--file-buffer
    (let ((inhibit-read-only t)
          (file-modified (buffer-modified-p)))
      (emacsvox-forms-flush-unwanted-records)
      (if (not file-modified) (set-buffer-modified-p
                               nil))))
  (let (ro)
    (setq forms--total-records
          (with-current-buffer forms--file-buffer
            (prog1
                (progn
                  (bury-buffer (current-buffer))
                  (setq ro buffer-read-only)
                  (count-lines (point-min) (point-max))))))
    (if ro
        (setq forms-read-only t)))
  (message "%s records after filtering"
           forms--total-records))

;;;  emacsvox forms find file
;;;###autoload
(defun emacsvox-forms-find-file (filename)
  "Visit a forms file"
  (interactive
   (list
    (read-file-name "Forms file: "
                    (expand-file-name "forms/"
                                      emacsvox-etc-directory))))
  (load-file filename)
  (forms-find-file filename))

;;;  bind smart filters
(cl-declaim (special forms-mode-map forms-mode-ro-map
                     forms-mode-edit-map))
(add-hook
 'forms-mode-hooks
 #'(lambda nil 
     (mapc
      #'(lambda (map)
          (define-key map "\C-m" 'emacsvox-forms-rerun-filter)
          (define-key map "."
                      'emacsvox-forms-summarize-current-position)
          (define-key map "," 'emacsvox-forms-summarize-current-record))
      (list forms-mode-ro-map 
            forms-mode-map))
     ;; move to first field
     (forms-next-field 1)))

(provide  'emacsvox-forms)
