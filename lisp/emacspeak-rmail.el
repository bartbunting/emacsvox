;;; emacspeak-rmail.el --- Speech enable RMail -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Emacspeak extension for rmail
;; Keywords:emacspeak, audio interface to emacs mail
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacspeak
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
;; emacspeak extensions to rmail
;;; Code:

;;;  requires
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;;   customizations:
(declare-function rmail-display-labels "rmail" nil)
(declare-function rmail-msgend "rmail" (n))
(declare-function rmail-msgbeg "rmail" (n))
(declare-function rmail-get-header "rmail" (name &optional msgnum))

(cl-declaim (special rmail-ignored-headers))
(setq rmail-ignored-headers
      (concat "^X-\\|"
              "^Content-\\|"
              "^Mime-\\|"
              rmail-ignored-headers))

;;;   helper functions:

(defun emacspeak-rmail-summarize-message (message)
  "Summarize message in rmail identified by message number message"
  (let ((subject (rmail-get-header "Subject" message))
        (to (rmail-get-header "To" message))
        (from (rmail-get-header "From" message))
        (lines (count-lines (rmail-msgbeg message) (rmail-msgend message)))
        (labels (rmail-display-labels)))
    (dtk-speak
     (format "%s %s   %s %s labelled %s "
             (or from "")
             (if (and to (< (length to) 80))
                 (format "to %s" to) "")
             (if subject (format "on %s" subject) "")
             (if lines (format "%s lines" lines) "")
             labels))))

;;;   Advice some commands.
;;;   buffer selection


(defun ems--rmail-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-mode-line)))


(advice-add 'rmail-quit :after #'ems--rmail-quit-after)





(defun ems--rmail-bury-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object) (emacspeak-speak-mode-line)))


(advice-add 'rmail-bury :after #'ems--rmail-bury-after)




(defun ems--rmail-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-current-message)))


(advice-add 'rmail :after #'ems--rmail-after)





(defun ems--rmail-expunge-and-save-after (&rest _)
  "speak" (when (ems-interactive-p) (emacspeak-icon 'save-object)))


(advice-add 'rmail-expunge-and-save :after
	    #'ems--rmail-expunge-and-save-after)




;;;   message navigation


(defun ems--rmail-beginning-of-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement) (emacspeak-speak-line)))


(advice-add 'rmail-beginning-of-message :after
	    #'ems--rmail-beginning-of-message-after)




;;;   folder navigation


(defun ems--rmail-first-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-first-message :after
	    #'ems--rmail-first-message-after)





(defun ems--rmail-first-unseen-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-first-unseen-message :after
	    #'ems--rmail-first-unseen-message-after)





(defun ems--rmail-last-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-last-message :after #'ems--rmail-last-message-after)





(defun ems--rmail-next-undeleted-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-next-undeleted-message :after
	    #'ems--rmail-next-undeleted-message-after)





(defun ems--rmail-next-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-next-message :after #'ems--rmail-next-message-after)





(defun ems--rmail-previous-undeleted-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-previous-undeleted-message :after
	    #'ems--rmail-previous-undeleted-message-after)




(defun ems--rmail-previous-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-previous-message :after
	    #'ems--rmail-previous-message-after)




(defun ems--rmail-next-labeled-message-around (orig-fun &rest args)
  "speak"
  (let ((result (apply orig-fun args)))
    (cl-declare (special rmail-current-message))
    (cond
     ((ems-interactive-p)
      (let ((original rmail-current-message))
	(apply orig-fun args)
	(cond
	 ((not (= original rmail-current-message))
	  (emacspeak-icon 'select-object)
	  (emacspeak-rmail-summarize-message rmail-current-message))
	 (t (emacspeak-icon 'search-miss)))))
     (t (apply orig-fun args)))
    result))


(advice-add 'rmail-next-labeled-message :around
	    #'ems--rmail-next-labeled-message-around)





(defun ems--rmail-previous-labeled-message-around
    (orig-fun &rest args)
  "speak"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((original rmail-current-message))
	(apply orig-fun args)
	(cond
	 ((not (= original rmail-current-message))
	  (emacspeak-icon 'select-object)
	  (emacspeak-rmail-summarize-message rmail-current-message))
	 (t (emacspeak-icon 'search-miss)))))
     (t (apply orig-fun args)))
    result))


(advice-add 'rmail-previous-labeled-message :around
	    #'ems--rmail-previous-labeled-message-around)





(defun ems--rmail-show-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-message rmail-current-message)))


(advice-add 'rmail-show-message :after #'ems--rmail-show-message-after)


  

;;;  delete and undelete messages


(defun ems--rmail-undelete-previous-message-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object)
    (emacspeak-rmail-summarize-current-message)))


(advice-add 'rmail-undelete-previous-message :after
	    #'ems--rmail-undelete-previous-message-after)




(defun ems--rmail-delete-message-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'delete-object) (message "Message discarded.")))


(advice-add 'rmail-delete-message :after
	    #'ems--rmail-delete-message-after)





(defun ems--rmail-delete-forward-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacspeak-icon 'delete-object)
    (emacspeak-rmail-summarize-current-message)))


(advice-add 'rmail-delete-forward :after
	    #'ems--rmail-delete-forward-after)





(defun ems--rmail-delete-backward-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacspeak-icon 'delete-object)
    (emacspeak-rmail-summarize-current-message)))


(advice-add 'rmail-delete-backward :after
	    #'ems--rmail-delete-backward-after)


  

;;;   Additional interactive commands

(defun emacspeak-rmail-summarize-current-message ()
  "Summarize current message"
  (interactive)
  (cl-declare (special rmail-current-message))
  (emacspeak-rmail-summarize-message rmail-current-message))
(defun  emacspeak-rmail-speak-current-message-labels ()
  "Speak labels of current message"
  (interactive)
  (dtk-speak
   (format "Labels are %s"
           (rmail-display-labels))))

;;;   key bindings
(when (and (boundp 'rmail-mode-map) (keymapp rmail-mode-map))  
  (cl-declaim (special rmail-mode-map))
  (define-key rmail-mode-map "\C-m" 'emacspeak-rmail-summarize-current-message)
  (define-key rmail-mode-map "L"
              'emacspeak-rmail-speak-current-message-labels))

(provide  'emacspeak-rmail)

