;;; emacsvox-dismal.el --- Speech enable Dismal -*- lexical-binding: t; -*-
;; Description: spread sheet extension
;; Keywords:emacsvox, audio interface to emacs spread sheets
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

;;;   Introduction

;; emacsvox extensions to the dismal spreadsheet. 
;; Dismal can be found at ftp://cs.nyu.edu/pub/local/fox/dismal
;;; Code:

;;;   requires 
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Forward Decls:

(declare-function dismal-get-val "ext:dismal" (r c))
(declare-function  dismal-convert-cellexpr-to-string "dismal" (sexp))
(declare-function dismal-get-exp "dismal" (r c))
(declare-function  dismal-display-current-cell-expr "dismal" (r c))
(declare-function  dis-forward-row "dismal" (rows))
(declare-function dis-backward-row "dismal" (rows))
(declare-function  dis-forward-column "dismal" (cols))
(declare-function  dis-backward-column "dismal" (cols))
(declare-function dis-recalculate-matrix "dismal" nil)

;;;   helper functions:

;; return cell value as a string

(defun emacsvox-dismal-cell-value (row col)
  (let ((value (dismal-get-val row col)))
    (if (floatp value)
        (format "%.2f" value)
      (dismal-convert-cellexpr-to-string value)value)))

(defun emacsvox-dismal-current-cell-value ()
  
  (emacsvox-dismal-cell-value dismal-current-row dismal-current-col))

;; return entry in col 0 of current row as a string:

(defun emacsvox-dismal-current-row-header ()
  
  (dismal-convert-cellexpr-to-string
   (dismal-get-exp dismal-current-row  0)))

(defun emacsvox-dismal-current-col-header ()
  
  (dismal-convert-cellexpr-to-string
   (dismal-get-exp 0  dismal-current-col)))

;;;   Additional interactive commands

(defun emacsvox-dismal-display-cell-expression ()
  "Display the expression in the message area"
  (interactive)
  
  (dismal-display-current-cell-expr dismal-current-row dismal-current-col))

(defun emacsvox-dismal-display-cell-value ()
  "Display the cell value in the message area"
  (interactive)
  
  (message "%s = %s"
           dismal-current-cell
           (emacsvox-dismal-current-cell-value)))

(defun emacsvox-dismal-display-cell-with-row-header ()
  "Displays current cell along with its row header.
The `row header' is the entry in column 0."
  (interactive)
  (cl-declare (special))
  (let ((row-head  (emacsvox-dismal-current-row-header))
        (value (emacsvox-dismal-current-cell-value)))
    (message "%s is %s"
             row-head value)))

(defun emacsvox-dismal-display-cell-with-col-header ()
  "Display current cell along with its column header.
The `column header' is the entry in row 0."
  (interactive)
  (let ((col-head  (emacsvox-dismal-current-col-header))
        (value (emacsvox-dismal-current-cell-value)))
    (message "%s is %s"
             col-head value)))

(defun emacsvox-dismal-forward-row-and-summarize (rows)
  "Move forward by arg rows
 (the next row by default)and summarize it."
  (interactive "p")
  (dis-forward-row rows)
  (emacsvox-dismal-row-summarize))

(defun emacsvox-dismal-backward-row-and-summarize (rows)
  "Move backward by arg rows
 (the previous row by default)and summarize it."
  (interactive "p")
  (dis-backward-row rows)
  (emacsvox-dismal-row-summarize))

(defun emacsvox-dismal-forward-col-and-summarize (cols)
  "Move forward by arg columns
 (the next column by default)and summarize it."
  (interactive "p")
  (dis-forward-column cols)
  (emacsvox-dismal-col-summarize))

(defun emacsvox-dismal-backward-col-and-summarize (cols)
  "Move backward by arg columns
 (the previous column by default)and summarize it."
  (interactive "p")
  (dis-backward-column cols)
  (emacsvox-dismal-col-summarize))

;;;   Intelligent summaries

(defvar emacsvox-dismal-sheet-summarizer-list nil
  "Specifies how the entire sheet  should be summarized. ")

(make-variable-buffer-local 'emacsvox-dismal-sheet-summarizer-list)

(defvar emacsvox-dismal-row-summarizer-list nil
  "Specifies how rows should be summarized. ")

(make-variable-buffer-local 'emacsvox-dismal-row-summarizer-list)

(defvar emacsvox-dismal-col-summarizer-list nil
  "Specifies how cols should be summarized. ")

(make-variable-buffer-local 'emacsvox-dismal-col-summarizer-list)

(setq-default emacsvox-dismal-row-summarizer-list nil)
(setq-default emacsvox-dismal-col-summarizer-list nil)
(setq-default emacsvox-dismal-sheet-summarizer-list nil)
(defvar emacsvox-dismal-value-personality voice-animate
  "Personality used for speaking cell values in summaries.")

(defun emacsvox-dismal-row-summarize  ()
  "Summarizes a row using the specification in list
emacsvox-dismal-row-summarizer-list"
  (interactive)
  (cl-declare (special emacsvox-dismal-row-summarizer-list
                       emacsvox-dismal-value-personality
                       voice-lock-mode
                       dismal-current-row))
  (unless  (and  emacsvox-dismal-row-summarizer-list
                 (vectorp emacsvox-dismal-row-summarizer-list))
    (setq emacsvox-dismal-row-summarizer-list
          (read-minibuffer "Specify summarizer as a vector:
" "[")))
  (let ((summary nil))
    (setq summary 
          (mapconcat
           #'(lambda (token)
               (let ((value nil))
                 (cond
                  ((stringp token) token)
                  ((numberp token)
                   (setq value
                         (format "%s"
                                 (emacsvox-dismal-cell-value
                                  dismal-current-row token)))
                   (put-text-property
                    0   (length value)
                    'personality  emacsvox-dismal-value-personality 
                    value)
                   value)
                  ((and (listp token)
                        (numberp (cl-first token))
                        (numberp (cl-second token)))
                   (setq value
                         (format "%s"
                                 (emacsvox-dismal-cell-value
                                  (cl-first token)
                                  (cl-second token))))
                   (put-text-property
                    0   (length value)
                    'personality emacsvox-dismal-value-personality 
                    value)
                   value)
                  (t  (format "%s" token)))))
           emacsvox-dismal-row-summarizer-list 
           " "))
    (dtk-speak summary)))

(defun emacsvox-dismal-col-summarize  ()
  "Summarizes a col using the specification in list
emacsvox-dismal-col-summarizer-list"
  (interactive)
  (cl-declare (special emacsvox-dismal-col-summarizer-list
                       emacsvox-dismal-value-personality voice-lock-mode
                       dismal-current-col))
  (unless  (and  emacsvox-dismal-col-summarizer-list
                 (vectorp emacsvox-dismal-col-summarizer-list))
    (setq emacsvox-dismal-col-summarizer-list
          (read-minibuffer "Specify summarizer as a vector:
" "[")))
  (let ((summary nil))
    (setq
     summary 
     (mapconcat
      #'(lambda (token)
          (let ((value nil))
            (cond
             ((stringp token) token)
             ((numberp token)
              (setq value
                    (format
                     "%s"
                     (emacsvox-dismal-cell-value token dismal-current-col)))
              (put-text-property 0 (length value)
                                 'personality
                                 emacsvox-dismal-value-personality value)
              value)
             ((and (listp token)
                   (numberp (cl-first token))
                   (numberp (cl-second token)))
              (setq value
                    (format "%s"
                            (emacsvox-dismal-cell-value
                             (cl-first token)
                             (cl-second token))))
              (put-text-property 0 (length value)
                                 'personality
                                 emacsvox-dismal-value-personality value)
              value)
             (t  (format "%s" token)))))
      emacsvox-dismal-col-summarizer-list 
      " "))
    (dtk-speak summary)))

(defun emacsvox-dismal-sheet-summarize  ()
  "Summarizes a sheet using the specification in list
emacsvox-dismal-sheet-summarizer-list"
  (interactive)
  
  (when emacsvox-dismal-sheet-summarizer-list
    (let ((emacsvox-speak-messages nil))
      (dis-recalculate-matrix))
    (message 
     (mapconcat
      #'(lambda (token)
          (cond
           ((stringp token) token)
           ((and (listp token)
                 (numberp (cl-first token))
                 (numberp (cl-second token)))
            (emacsvox-dismal-cell-value
             (cl-first token)
             (cl-second token)))
           (t  (format "%s" token))))
      emacsvox-dismal-sheet-summarizer-list 
      " "))))

(defun emacsvox-dismal-set-row-summarizer-list ()
  "Specify or reset row summarizer list."
  (interactive)
  
  (setq emacsvox-dismal-row-summarizer-list
        (read-minibuffer
         "Specify summarizer as a list: "
         (format "%S"
                 (or emacsvox-dismal-row-summarizer-list  "[")))))

(defun emacsvox-dismal-set-col-summarizer-list ()
  "Specify or reset col summarizer list."
  (interactive)
  
  (setq emacsvox-dismal-col-summarizer-list
        (read-minibuffer
         "Specify summarizer as a vector: "
         (format "%S"
                 (or emacsvox-dismal-col-summarizer-list  "[")))))

(defun emacsvox-dismal-set-sheet-summarizer-list ()
  "Specify or reset sheet summarizer list."
  (interactive)
  
  (setq emacsvox-dismal-sheet-summarizer-list
        (read-minibuffer
         "Specify summarizer as a list: "
         (format "%S"
                 (or emacsvox-dismal-sheet-summarizer-list  "[")))))

;;;   key bindings

;; record emacsvox stat that we want dismal to save
(defvar emacsvox-dismal-already-customized-dismal nil
  "Records if we have customized dismal.
Checked by emacsvox specific dis-mode-hooks entry.")

(add-hook
 'dis-mode-hooks
 #'(lambda nil
     
     (define-key dismal-map (concat emacsvox-prefix "e")
                 'dis-last-column)
     (define-key dismal-map emacsvox-prefix 'emacsvox-keymap)
     (unless emacsvox-dismal-already-customized-dismal
       (setq emacsvox-dismal-already-customized-dismal t)
       (push 'emacsvox-dismal-sheet-summarizer-list
             dismal-saved-variables)
       (push 'emacsvox-dismal-row-summarizer-list
             dismal-saved-variables)
       (push 'emacsvox-dismal-col-summarizer-list
             dismal-saved-variables))))

(add-hook
 'dis-mode-hooks
 #'(lambda nil
     
     (local-unset-key "\M-[")
     (local-unset-key emacsvox-prefix)
     (define-key dismal-map emacsvox-prefix 'emacsvox-keymap)
     (define-key dismal-map (concat emacsvox-prefix "e")
                 'dis-last-column)
     (define-key dismal-map  "," 'emacsvox-dismal-display-cell-expression)
     (define-key dismal-map  "." 'emacsvox-dismal-display-cell-value)
     (define-key dismal-map "R" 'emacsvox-dismal-display-cell-with-row-header)
     (define-key dismal-map "S" 'emacsvox-dismal-sheet-summarize)
     (define-key dismal-map "C" 'emacsvox-dismal-display-cell-with-col-header)
     (define-key dismal-map "\M-m" 'emacsvox-dismal-row-summarize)
     (define-key dismal-map '[up] 'emacsvox-dismal-backward-row-and-summarize)
     (define-key dismal-map '[down] 'emacsvox-dismal-forward-row-and-summarize)
     (define-key
      dismal-map '[left] 'emacsvox-dismal-backward-col-and-summarize)
     (define-key
      dismal-map '[right] 'emacsvox-dismal-forward-col-and-summarize)))

;;;   Advice some commands. 

;;;  customize for use with html helper mode

(defun ems--dis-html-dump-file-around (orig-fun &rest args)
  "Sets html-helper-build-new-buffer to nil first so we dont\nend up building a template page first."
  (let ((html-helper-build-new-buffer nil)) (apply orig-fun args)))

(advice-add 'dis-html-dump-file :around
            #'ems--dis-html-dump-file-around)

(defun ems--dis-html-dump-range-around (orig-fun &rest args)
  "Sets html-helper-build-new-buffer to nil first so we dont\nend up building a template page first."
  (let ((html-helper-build-new-buffer nil)) (apply orig-fun args)))

(advice-add 'dis-html-dump-range :around
            #'ems--dis-html-dump-range-around)

(provide  'emacsvox-dismal)

