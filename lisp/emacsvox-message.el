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
(cl-loop
 for f in
 '(message-send message-send-and-exit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Provide auditory context"
     (when  (ems-interactive-p)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'close-object)))))

(defun ems--message-goto-to-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-to :after #'ems--message-goto-to-after)

(defun ems--message-goto-summary-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-summary :after
            #'ems--message-goto-summary-after)

(defun ems--message-goto-subject-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-subject :after
            #'ems--message-goto-subject-after)

(defun ems--message-goto-cc-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-cc :after #'ems--message-goto-cc-after)

(defun ems--message-goto-bcc-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-bcc :after #'ems--message-goto-bcc-after)

(defun ems--message-goto-fcc-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-fcc :after #'ems--message-goto-fcc-after)

(defun ems--message-goto-keywords-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-keywords :after
            #'ems--message-goto-keywords-after)

(defun ems--message-goto-newsgroups-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-newsgroups :after
            #'ems--message-goto-newsgroups-after)

(defun ems--message-goto-followup-to-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-followup-to :after
            #'ems--message-goto-followup-to-after)

(defun ems--message-goto-reply-to-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-reply-to :after
            #'ems--message-goto-reply-to-after)

(defun ems--message-goto-body-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (message "Beginning of message body")))

(advice-add 'message-goto-body :after #'ems--message-goto-body-after)

(defun ems--message-goto-signature-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-signature :after
            #'ems--message-goto-signature-after)

(defun ems--message-goto-distribution-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-distribution :after
            #'ems--message-goto-distribution-after)

(defun ems--message-insert-citation-line-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-insert-citation-line :after
            #'ems--message-insert-citation-line-after)

(defun ems--message-insert-to-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-insert-to :after #'ems--message-insert-to-after)

(defun ems--message-insert-signature-after (&rest _)
  "speak" (when (ems-interactive-p) (message "Signed the article.")))

(advice-add 'message-insert-signature :after
            #'ems--message-insert-signature-after)

(defun ems--message-insert-newsgroups-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-insert-newsgroups :after
            #'ems--message-insert-newsgroups-after)

(defun ems--message-insert-courtesy-copy-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-insert-courtesy-copy :after
            #'ems--message-insert-courtesy-copy-after)

(defun ems--message-beginning-of-line-before (&rest _)
  "Stop speech first."
  (when (ems-interactive-p)
    (dtk-stop 'all) (emacsvox-icon 'select-object)
    (dtk-speak "beginning of line")))

(advice-add 'message-beginning-of-line :before
            #'ems--message-beginning-of-line-before)

(defun ems--message-goto-from-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-from :after #'ems--message-goto-from-after)

(defun ems--message-goto-mail-followup-to-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'message-goto-mail-followup-to :after
            #'ems--message-goto-mail-followup-to-after)

(defun ems--message-newline-and-reformat-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object) (message "newline and reformat")))

(advice-add 'message-newline-and-reformat :after
            #'ems--message-newline-and-reformat-after)

(add-hook 'message-mode-hook
          #'emacsvox-pronounce-refresh-pronunciations)

(provide  'emacsvox-message)

