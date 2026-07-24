;;; emacsvox-message.el --- Speech enable Message   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Emacsvox extensions for posting
;; Keywords:emacsvox, audio interface to emacs posting messages
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
;; advice for posting message commands
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'message)

;;;  customize
(defgroup emacsvox-message nil
  "Emacsvox customizations for message mode"
  :group 'emacsvox
  :group 'message
  :prefix "emacsvox-message-")

;;;  voice mapping

(voice-setup-add-map
 '(
   (message-cited-text voice-smoothen)
   (message-header-cc voice-bolden)
   (message-header-name voice-animate)
   (message-header-newsgroups voice-bolden)
   (message-header-other voice-monotone)
   (message-header-subject voice-animate)
   (message-header-to voice-brighten)
   (message-header-xheader voice-monotone)
   (message-mml voice-brighten)
   (message-separator voice-bolden-extra)))

;;;   advice interactive commands

(defmacro emacsvox-message--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive Message TARGET using BODY."
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
        ',target ,where #',function '((name . emacsvox))))))

(dolist (target '(message-send message-send-and-exit))
  (eval
   `(emacsvox-message--define-advice ,target :after
      (emacsvox-speak-mode-line)
      (emacsvox-icon 'close-object))))

(dolist
    (target
     '(message-goto-to
       message-goto-summary
       message-goto-subject
       message-goto-cc
       message-goto-bcc
       message-goto-fcc
       message-goto-keywords
       message-goto-newsgroups
       message-goto-followup-to
       message-goto-reply-to
       message-goto-signature
       message-goto-distribution
       message-insert-citation-line
       message-insert-to
       message-insert-newsgroups
       message-insert-courtesy-copy
       message-goto-from
       message-goto-mail-followup-to))
  (eval
   `(emacsvox-message--define-advice ,target :after
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-line))))

(emacsvox-message--define-advice message-goto-body :after
  (emacsvox-icon 'large-movement)
  (message "Beginning of message body"))

(emacsvox-message--define-advice message-insert-signature :after
  (message "Signed the article."))

(emacsvox-message--define-advice message-beginning-of-line :before
  (dtk-stop 'all)
  (emacsvox-icon 'select-object)
  (tts-speak "beginning of line"))

(emacsvox-message--define-advice message-newline-and-reformat :after
  (emacsvox-icon 'fill-object)
  (message "newline and reformat"))

(add-hook 'message-mode-hook
          #'emacsvox-pronounce-refresh-pronunciations)

(provide  'emacsvox-message)
