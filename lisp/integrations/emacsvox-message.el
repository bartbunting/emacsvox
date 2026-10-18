;;; emacsvox-message.el --- Speech enable Message   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs posting messages
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; advice for posting message commands
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'message)
(require 'mml)
(require 'subr-x)

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

(defvar-local emacsvox-message--send-active nil
  "Non-nil while Emacsvox is reporting a Message send operation.")

(defun emacsvox--advice-message-send-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS and report the complete send outcome."
  (if emacsvox-message--send-active
      (apply original arguments)
    (let ((emacsvox-message--send-active t))
      (emacsvox-icon 'progress)
      (tts-speak "Sending message")
      (condition-case error-data
          (let ((result (apply original arguments)))
            (if result
                (progn
                  (emacsvox-icon 'task-done)
                  (tts-speak "Message sent"))
              (emacsvox-icon 'warn-user)
              (tts-speak "Message was not sent"))
            result)
        (quit
         (emacsvox-icon 'warn-user)
         (tts-speak "Send interrupted; delivery status unknown")
         (signal (car error-data) (cdr error-data)))
        (error
         (emacsvox-icon 'warn-user)
         (tts-speak
          (format "Send failed or incomplete: %s"
                  (error-message-string error-data)))
         (signal (car error-data) (cdr error-data)))))))

(advice-add
 'message-send :around #'emacsvox--advice-message-send-around
 '((name . emacsvox)))

(defun emacsvox--advice-message-setup-1-after (&rest _)
  "Announce a newly prepared Message composition buffer."
  (emacsvox-icon 'open-object)
  (tts-speak "Compose message")
  (emacsvox-speak-line))

(advice-add
 'message-setup-1 :after #'emacsvox--advice-message-setup-1-after
 '((name . emacsvox)))

(defun emacsvox-message--header-value (header)
  "Return the value of Message HEADER in the current buffer."
  (save-excursion
    (save-restriction
      (widen)
      (message-narrow-to-headers-or-head)
      (message-fetch-field header))))

(defun emacsvox-message--attachment-count ()
  "Return the number of named MML parts in the current message."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((count 0))
        (while (re-search-forward
                "^<#part[ \t][^\n]*\\bfilename=" nil t)
          (setq count (1+ count)))
        count))))

(defun emacsvox-message-speak-compose-status ()
  "Speak sender, recipients, subject, attachments, and point location."
  (interactive)
  (let* ((from (emacsvox-message--header-value "From"))
         (to (emacsvox-message--header-value "To"))
         (cc (emacsvox-message--header-value "Cc"))
         (subject (emacsvox-message--header-value "Subject"))
         (attachments (emacsvox-message--attachment-count))
         (parts
          (list
           "Compose message"
           (if (string-empty-p (or from ""))
               "From address unspecified"
             (format "From %s" from))
           (if (string-empty-p (or to ""))
               "No primary recipients"
             (format "To %s" to))
           (if (string-empty-p (or subject ""))
               "No subject"
             (format "Subject %s" subject)))))
    (unless (string-empty-p (or cc ""))
      (setq parts (append parts (list (format "C C %s" cc)))))
    (setq
     parts
     (append
      parts
      (list
       (if (zerop attachments)
           "No attachments"
         (format "%d %s"
                 attachments
                 (if (= attachments 1) "attachment" "attachments")))
       (if (message-point-in-header-p)
           "Point is in the headers"
         "Point is in the message body"))))
    (tts-speak (mapconcat #'identity parts ". "))))

(define-key
 message-mode-map (kbd "C-c C-f C-p")
 #'emacsvox-message-speak-compose-status)

(defun emacsvox--advice-mml-attach-file-after (file &rest _)
  "Confirm attaching FILE to a Message buffer."
  (when (derived-mode-p 'message-mode)
    (emacsvox-icon 'save-object)
    (tts-speak
     (format "Attached %s"
             (file-name-nondirectory (expand-file-name file))))))

(advice-add
 'mml-attach-file :after #'emacsvox--advice-mml-attach-file-after
 '((name . emacsvox)))

(defun emacsvox--advice-mml-attach-buffer-after (buffer &rest _)
  "Confirm attaching BUFFER to a Message buffer."
  (when (derived-mode-p 'message-mode)
    (emacsvox-icon 'save-object)
    (tts-speak
     (format "Attached buffer %s"
             (if (bufferp buffer) (buffer-name buffer) buffer)))))

(advice-add
 'mml-attach-buffer :after #'emacsvox--advice-mml-attach-buffer-after
 '((name . emacsvox)))

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
  (tts-stop 'all)
  (emacsvox-icon 'select-object)
  (tts-speak "beginning of line"))

(emacsvox-message--define-advice message-newline-and-reformat :after
  (emacsvox-icon 'fill-object)
  (message "newline and reformat"))

(add-hook 'message-mode-hook
          #'emacsvox-pronounce-refresh-pronunciations)

(provide  'emacsvox-message)

;;; emacsvox-message.el ends here
