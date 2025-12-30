;;; emacsvox-bbdb.el --- Speech enable BBDB -*- lexical-binding: t; -*-

;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for bbdb 
;; Keywords:emacsvox, audio interface to emacs bbdb 
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@crl.dec.com 
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


;;;   Required libraries
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:
;; Speech-enables BBDB.
;; I have used BBDB to manage email address and contact information since 1991.
;;; Code:

;;;  personalities 

(voice-setup-add-map
 '(
   (bbdb-field-name voice-monotone-extra)
   (bbdb-name voice-bolden)
   (bbdb-organization voice-lighten)))

;;;   Variable settings:

;; Emacsvox will not work if bbdb is in electric mode
(cl-declaim (special bbdb-electric-p))
(setq bbdb-electric-p nil)
(cl-declaim (special bbdb-mode-map))

(add-hook
 'bbdb-mode-hook
 #'(lambda ()
     (define-key  bbdb-mode-map "b" 'bbdb)
     (define-key bbdb-mode-map "N" 'bbdb-name)
     (define-key bbdb-mode-map "c" 'bbdb-create)
     ))

;;;  Advice:


(defun ems--bbdb-delete-current-field-or-record-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))


(advice-add 'bbdb-delete-current-field-or-record :after
	    #'ems--bbdb-delete-current-field-or-record-after)





(defun ems--bbdb-edit-current-field-before (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'open-object)))


(advice-add 'bbdb-edit-current-field :before
	    #'ems--bbdb-edit-current-field-before)





(defun ems--bbdb-send-mail-before (&rest _)
  "speak"
  (when (ems-interactive-p)
    (let
	((to
	  (if (consp (ad-get-arg 0))
	      (bbdb-dwim-net-address (car (ad-get-arg 0)))
	    (bbdb-dwim-net-address (ad-get-arg 0))))
	 (subject (ad-get-arg 1)))
      (emacsvox-icon 'open-object)
      (message "Starting an email message  %s to %s %s "
	       (if subject (format "about %s" subject) "") to
	       (if (consp (ad-get-arg 0)) " and others " " ")))))


(advice-add 'bbdb-send-mail :before #'ems--bbdb-send-mail-before)





(defun ems--bbdb-next-record-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))


(advice-add 'bbdb-next-record :after #'ems--bbdb-next-record-after)





(defun ems--bbdb-prev-record-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))


(advice-add 'bbdb-prev-record :after #'ems--bbdb-prev-record-after)





(defun ems--bbdb-omit-record-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))


(advice-add 'bbdb-omit-record :after #'ems--bbdb-omit-record-after)





(defun ems--bbdb-bury-buffer-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))


(advice-add 'bbdb-bury-buffer :after #'ems--bbdb-bury-buffer-after)





(defun ems--bbdb-elide-record-after (&rest _)
  "speak"
  (when (ems-interactive-p) (message "Toggled  record display")))


(advice-add 'bbdb-elide-record :after #'ems--bbdb-elide-record-after)





(defun ems--bbdb-transpose-fields-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))


(advice-add 'bbdb-transpose-fields :after
	    #'ems--bbdb-transpose-fields-after)





(defun ems--bbdb-complete-name-around (orig-fun &rest args)
  "Speak"
  (let ((result (apply orig-fun args)))
    
    (cond
     ((ems-interactive-p)
      (let
	  ((prior (point)) (completion-ignore-case t)
	   (completions nil) (buffer (current-buffer)))
	(apply orig-fun args)
	(cond
	 ((and (setq completions (get-buffer "*Completions*"))
	       (window-live-p (get-buffer-window completions)))
	  (switch-to-completions)
	  (setq completion-reference-buffer buffer)
	  (unless (get-text-property (point) 'mouse-face)
	    (goto-char
	     (next-single-property-change (point) 'mouse-face)))
	  (dtk-speak (emacsvox-get-current-completion)))
	 (t (dtk-speak (buffer-substring prior (point)))))))
     (t (apply orig-fun args)))
    result))


(advice-add 'bbdb-complete-name :around
	    #'ems--bbdb-complete-name-around)




;;;   Advice mail-ua  specific hooks


(defun ems--bbdb/vm-show-sender-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-speak-other-window)))


(advice-add 'bbdb/vm-show-sender :after
	    #'ems--bbdb/vm-show-sender-after)





(defun ems--bbdb/rmail-show-sender-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-speak-other-window)))


(advice-add 'bbdb/rmail-show-sender :after
	    #'ems--bbdb/rmail-show-sender-after)





(defun ems--bbdb/mh-show-sender-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-speak-other-window)))


(advice-add 'bbdb/mh-show-sender :after
	    #'ems--bbdb/mh-show-sender-after)




;;;  silence messages 


(defun ems--bbdb-update-records-around (orig-fun &rest args)
  "Silence messages."
  (ems-with-messages-silenced (apply orig-fun args)))


(advice-add 'bbdb-update-records :around
	    #'ems--bbdb-update-records-around)




(provide  'emacsvox-bbdb)

