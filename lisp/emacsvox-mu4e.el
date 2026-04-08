;;; emacsvox-mu4e.el --- Speech-enable MU4E  -*- lexical-binding: t; -*-
;;; $Author: Robert Melton $
;;; Description:  Speech-enable MU4E An Emacs Interface to mu4e
;;; Keywords: Emacsvox,  Audio Desktop mu4e
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; MU4E == mu4e: an Emacs front-end for the mu mail indexer/searcher.
;; This module speech-enables mu4e for use on the Emacsvox audio desktop.
;; It covers the four main mu4e views:
;; - Main view (dashboard)
;; - Headers view (message list)
;; - Message view (reading a message)
;; - Compose view (writing a message)

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'mu4e nil 'noerror)

;;; Forward declarations:

(declare-function mu4e-message-at-point "mu4e-message" (&optional noerror))
(declare-function mu4e-message-field "mu4e-message" (msg field))
(declare-function mu4e-contact-name "mu4e-contacts" (contact))
(declare-function mu4e-contact-email "mu4e-contacts" (contact))

;;;  Map Faces:

(voice-setup-add-map
 '(
   (mu4e-header-highlight-face voice-bolden)
   (mu4e-unread-face voice-animate)
   (mu4e-flagged-face voice-brighten)
   (mu4e-replied-face voice-monotone)
   (mu4e-header-face voice-smoothen)
   (mu4e-contact-face voice-lighten)
   (mu4e-compose-separator-face voice-bolden-extra)
   (mu4e-draft-face voice-animate-extra)
   (mu4e-trashed-face voice-monotone-extra)
   (mu4e-moved-face voice-monotone-medium)
   (mu4e-attach-number-face voice-brighten)
   (mu4e-cited-1-face voice-smoothen)
   (mu4e-cited-2-face voice-smoothen-medium)
   (mu4e-cited-3-face voice-smoothen-extra)
   (mu4e-cited-4-face voice-monotone)
   (mu4e-cited-5-face voice-monotone-medium)
   (mu4e-cited-6-face voice-monotone-extra)
   (mu4e-cited-7-face voice-lighten)
   (mu4e-compose-header-face voice-bolden)
   (mu4e-context-face voice-animate)
   (mu4e-footer-face voice-monotone)
   (mu4e-header-key-face voice-bolden)
   (mu4e-header-title-face voice-bolden-extra)
   (mu4e-header-value-face voice-lighten)
   (mu4e-highlight-face voice-animate)
   (mu4e-link-face voice-brighten)
   (mu4e-modeline-face voice-bolden)
   (mu4e-region-code voice-monotone)
   (mu4e-special-header-value-face voice-lighten-extra)
   (mu4e-system-face voice-monotone)
   (mu4e-title-face voice-bolden-extra)
   (mu4e-url-number-face voice-brighten)
   (mu4e-warning-face voice-animate-extra)))

;;;  Helpers:

(defun emacsvox-mu4e-speak-header-summary ()
  "Speak a summary of the message at point in headers view."
  (when-let* ((msg (mu4e-message-at-point 'noerror)))
    (let* ((subject (or (mu4e-message-field msg :subject) "No subject"))
           (from (mu4e-message-field msg :from))
           (sender (if from
                       (let ((contact (car from)))
                         (or (plist-get contact :name)
                             (plist-get contact :email)
                             "Unknown"))
                     "Unknown"))
           (flags (mu4e-message-field msg :flags))
           (flag-str
            (mapconcat
             (lambda (f)
               (pcase f
                 ('unread "unread")
                 ('flagged "flagged")
                 ('replied "replied")
                 ('attach "attachment")
                 ('draft "draft")
                 ('trashed "trashed")
                 (_ nil)))
             flags " ")))
      (dtk-speak
       (format "%s from %s %s"
               subject sender
               (if (string-empty-p (string-trim flag-str)) ""
                 flag-str))))))

(defun emacsvox-mu4e-speak-message-summary ()
  "Speak a summary of the message in the view buffer."
  (when-let* ((msg (mu4e-message-at-point 'noerror)))
    (let* ((subject (or (mu4e-message-field msg :subject) "No subject"))
           (from (mu4e-message-field msg :from))
           (sender (if from
                       (let ((contact (car from)))
                         (or (plist-get contact :name)
                             (plist-get contact :email)
                             "Unknown"))
                     "Unknown"))
           (date (mu4e-message-field msg :date))
           (date-str (if date (format-time-string "%B %d" date) "")))
      (dtk-speak
       (format "%s from %s %s" subject sender date-str)))))

;;;  Headers View -- Navigation:

(defun ems--mu4e-headers-next-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-mu4e-speak-header-summary)))

(advice-add 'mu4e-headers-next :after #'ems--mu4e-headers-next-after)

(defun ems--mu4e-headers-prev-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-mu4e-speak-header-summary)))

(advice-add 'mu4e-headers-prev :after #'ems--mu4e-headers-prev-after)

;;;  Headers View -- Open/Close Message:

(defun ems--mu4e-headers-view-message-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (emacsvox-mu4e-speak-message-summary)))

(advice-add 'mu4e-headers-view-message :after
            #'ems--mu4e-headers-view-message-after)

(defun ems--mu4e-view-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(advice-add 'mu4e-view-quit :after #'ems--mu4e-view-quit-after)

;;;  Compose Actions:

(cl-loop
 for f in
 '(mu4e-compose-new mu4e-compose-reply mu4e-compose-forward
   mu4e-compose-edit mu4e-compose-resend)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (dtk-speak
        (format "Compose %s"
                ,(substring (symbol-name f)
                            (length "mu4e-compose-"))))
       (emacsvox-speak-mode-line)))))

;;;  Send:

(defun ems--message-send-and-exit-after (&rest _)
  "Announce send in mu4e compose buffers."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (dtk-speak "Message sent")))

(advice-add 'message-send-and-exit :after
            #'ems--message-send-and-exit-after)

;;;  Search and Filter:

(defun ems--mu4e-headers-search-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(advice-add 'mu4e-headers-search :after
            #'ems--mu4e-headers-search-after)

(defun ems--mu4e-headers-search-narrow-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Narrowed search")
    (emacsvox-speak-mode-line)))

(advice-add 'mu4e-headers-search-narrow :after
            #'ems--mu4e-headers-search-narrow-after)

(defun ems--mu4e-headers-search-edit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(advice-add 'mu4e-headers-search-edit :after
            #'ems--mu4e-headers-search-edit-after)

;;;  Mark Actions:

(cl-loop
 for f in
 '(mu4e-headers-mark-for-delete mu4e-headers-mark-for-trash
   mu4e-headers-mark-for-move mu4e-headers-mark-for-refile)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'delete-object)
       (emacsvox-mu4e-speak-header-summary)))))

(cl-loop
 for f in
 '(mu4e-headers-mark-for-read mu4e-headers-mark-for-unread
   mu4e-headers-mark-for-flag mu4e-headers-mark-for-unflag)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'mark-object)
       (emacsvox-mu4e-speak-header-summary)))))

(defun ems--mu4e-headers-mark-for-unmark-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-mu4e-speak-header-summary)))

(advice-add 'mu4e-headers-mark-for-unmark :after
            #'ems--mu4e-headers-mark-for-unmark-after)

;;;  Execute Marks:

(defun ems--mu4e-mark-execute-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Executed all marks")))

(advice-add 'mu4e-mark-execute-all :after
            #'ems--mu4e-mark-execute-all-after)

;;;  Main View:

(cl-loop
 for f in
 '(mu4e mu4e-main-view)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

;;;  Update and Quit:

(defun ems--mu4e-update-mail-and-index-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'progress)
    (dtk-speak "Updating mail")))

(advice-add 'mu4e-update-mail-and-index :after
            #'ems--mu4e-update-mail-and-index-after)

(defun ems--mu4e-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(advice-add 'mu4e-quit :after #'ems--mu4e-quit-after)

;;;  View Mode Navigation:

(cl-loop
 for f in
 '(mu4e-view-headers-next mu4e-view-headers-prev)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-mu4e-speak-message-summary)))))

(provide 'emacsvox-mu4e)
;;;  end of file
