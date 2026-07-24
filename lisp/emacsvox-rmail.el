;;; emacsvox-rmail.el --- Speech enable RMail -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Emacsvox extension for rmail
;; Keywords:emacsvox, audio interface to emacs mail
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
;;; Commentary:
;; emacsvox extensions to rmail
;;; Code:

;;;  requires
(require 'emacsvox-preamble)

;;;   customizations:
(declare-function rmail-display-labels "rmail" nil)
(declare-function rmail-msgend "rmail" (n))
(declare-function rmail-msgbeg "rmail" (n))
(declare-function rmail-get-header "rmail" (name &optional msgnum))

(cl-declaim (special rmail-current-message rmail-ignored-headers))
(setq rmail-ignored-headers
      (concat "^X-\\|"
              "^Content-\\|"
              "^Mime-\\|"
              rmail-ignored-headers))

;;;   helper functions:

(defun emacsvox-rmail-summarize-message (message)
  "Summarize message in rmail identified by message number message"
  (let ((subject (rmail-get-header "Subject" message))
        (to (rmail-get-header "To" message))
        (from (rmail-get-header "From" message))
        (lines (count-lines (rmail-msgbeg message) (rmail-msgend message)))
        (labels (rmail-display-labels)))
    (tts-speak
     (format "%s %s   %s %s labelled %s "
             (or from "")
             (if (and to (< (length to) 80))
                 (format "to %s" to) "")
             (if subject (format "on %s" subject) "")
             (if lines (format "%s lines" lines) "")
             labels))))

;;;   Advice some commands.

(defmacro emacsvox-rmail--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive Rmail TARGET."
  (declare (indent 2))
  (let ((function
         (intern (format "emacsvox--advice-%s-%s"
                         target
                         (substring (symbol-name where) 1)))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback %s `%s'." where target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target ,where #',function
        '((name . ,function))))))

;;;   buffer selection

(emacsvox-rmail--define-advice rmail-quit :after
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-rmail--define-advice rmail-bury :after
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(emacsvox-rmail--define-advice rmail :after
  (emacsvox-icon 'select-object)
  (emacsvox-rmail-summarize-current-message))

(emacsvox-rmail--define-advice rmail-expunge-and-save :after
  (emacsvox-icon 'save-object))

;;;   message navigation

(emacsvox-rmail--define-advice rmail-beginning-of-message :after
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

;;;   folder navigation

(dolist
    (target
     '(rmail-first-message
       rmail-first-unseen-message
       rmail-last-message
       rmail-next-undeleted-message
       rmail-next-message
       rmail-previous-undeleted-message
       rmail-previous-message
       rmail-show-message))
  (eval
   `(emacsvox-rmail--define-advice ,target :after
      (emacsvox-icon 'select-object)
      (emacsvox-rmail-summarize-message rmail-current-message))))

(defmacro emacsvox-rmail--define-labeled-advice (target)
  "Define direct around advice for labeled-message TARGET."
  (let ((function
         (intern (format "emacsvox--advice-%s-around" target))))
    `(progn
       (defun ,function (original &rest arguments)
         ,(format "Call `%s' once and report whether it moved." target)
         (let ((interactive-p (ems-interactive-p ',target))
               (original-message rmail-current-message))
           (let ((result (apply original arguments)))
             (when interactive-p
               (if (/= original-message rmail-current-message)
                   (progn
                     (emacsvox-icon 'select-object)
                     (emacsvox-rmail-summarize-message
                      rmail-current-message))
                 (emacsvox-icon 'search-miss)))
             result)))
       (advice-add
        ',target :around #',function
        '((name . ,function))))))

(emacsvox-rmail--define-labeled-advice rmail-next-labeled-message)
(emacsvox-rmail--define-labeled-advice rmail-previous-labeled-message)

;;;  delete and undelete messages

(emacsvox-rmail--define-advice rmail-undelete-previous-message :after
  (emacsvox-icon 'select-object)
  (emacsvox-rmail-summarize-current-message))

(emacsvox-rmail--define-advice rmail-delete-message :after
  (emacsvox-icon 'delete-object)
  (message "Message discarded."))

(dolist
    (target '(rmail-delete-forward rmail-delete-backward))
  (eval
   `(emacsvox-rmail--define-advice ,target :after
      (emacsvox-icon 'delete-object)
      (emacsvox-rmail-summarize-current-message))))

;;;   Additional interactive commands

(defun emacsvox-rmail-summarize-current-message ()
  "Summarize current message"
  (interactive)
  
  (emacsvox-rmail-summarize-message rmail-current-message))
(defun  emacsvox-rmail-speak-current-message-labels ()
  "Speak labels of current message"
  (interactive)
  (tts-speak
   (format "Labels are %s"
           (rmail-display-labels))))

;;;   key bindings
(when (and (boundp 'rmail-mode-map) (keymapp rmail-mode-map))  
  (cl-declaim (special rmail-mode-map))
  (define-key rmail-mode-map "\C-m" 'emacsvox-rmail-summarize-current-message)
  (define-key rmail-mode-map "L"
              'emacsvox-rmail-speak-current-message-labels))

(provide  'emacsvox-rmail)
