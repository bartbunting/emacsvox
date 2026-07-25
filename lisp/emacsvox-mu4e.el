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
      (tts-speak
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
      (tts-speak
       (format "%s from %s %s" subject sender date-str)))))

;;;  Headers View -- Navigation:

(defvar emacsvox-mu4e--advice nil
  "Current Mu4e targets and their native advice functions.")
(setq emacsvox-mu4e--advice nil)

(defun emacsvox-mu4e--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback ',target))))
      (push (list target :after advice-function) emacsvox-mu4e--advice))))

(defun emacsvox-mu4e--header-selection-feedback (_target)
  "Speak the selected Mu4e header."
  (emacsvox-icon 'select-object)
  (emacsvox-mu4e-speak-header-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-headers-next mu4e-headers-prev)
 #'emacsvox-mu4e--header-selection-feedback)

(defun emacsvox-mu4e--message-selection-feedback (_target)
  "Speak the selected Mu4e message."
  (emacsvox-icon 'select-object)
  (emacsvox-mu4e-speak-message-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-view-headers-next mu4e-view-headers-prev)
 #'emacsvox-mu4e--message-selection-feedback)

(defun emacsvox-mu4e--open-message-feedback (_target)
  "Speak a newly opened Mu4e message."
  (emacsvox-icon 'open-object)
  (emacsvox-mu4e-speak-message-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-headers-view-message)
 #'emacsvox-mu4e--open-message-feedback)

(defun emacsvox-mu4e--close-feedback (_target)
  "Announce closing a Mu4e view."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-mu4e--register-after-group
 '(mu4e-view-quit mu4e-quit)
 #'emacsvox-mu4e--close-feedback)

(defun emacsvox-mu4e--compose-feedback (target)
  "Announce Mu4e compose command TARGET."
  (emacsvox-icon 'open-object)
  (tts-speak
   (format "Compose %s"
           (substring (symbol-name target) (length "mu4e-compose-"))))
  (emacsvox-speak-mode-line))

(emacsvox-mu4e--register-after-group
 '(mu4e-compose-new mu4e-compose-reply mu4e-compose-forward
   mu4e-compose-edit mu4e-compose-resend)
 #'emacsvox-mu4e--compose-feedback)

(defun emacsvox-mu4e--search-feedback (_target)
  "Speak a newly displayed or edited Mu4e search."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-mu4e--register-after-group
 '(mu4e-search mu4e-search-edit)
 #'emacsvox-mu4e--search-feedback)

(defun emacsvox--advice-mu4e-search-narrow-after (&rest _)
  "Announce a narrowed Mu4e search."
  (when (ems-interactive-p 'mu4e-search-narrow)
    (emacsvox-icon 'open-object)
    (tts-speak "Narrowed search")
    (emacsvox-speak-mode-line)))

(push '(mu4e-search-narrow :after
        emacsvox--advice-mu4e-search-narrow-after)
      emacsvox-mu4e--advice)

(defun emacsvox-mu4e--delete-mark-feedback (_target)
  "Speak a destructive Mu4e header mark."
  (emacsvox-icon 'delete-object)
  (emacsvox-mu4e-speak-header-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-headers-mark-for-delete mu4e-headers-mark-for-trash
   mu4e-headers-mark-for-move mu4e-headers-mark-for-refile)
 #'emacsvox-mu4e--delete-mark-feedback)

(defun emacsvox-mu4e--mark-feedback (_target)
  "Speak a non-destructive Mu4e header mark."
  (emacsvox-icon 'mark-object)
  (emacsvox-mu4e-speak-header-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-headers-mark-for-read mu4e-headers-mark-for-unread
   mu4e-headers-mark-for-flag mu4e-headers-mark-for-unflag)
 #'emacsvox-mu4e--mark-feedback)

(defun emacsvox-mu4e--unmark-feedback (_target)
  "Speak an unmarked Mu4e header."
  (emacsvox-icon 'deselect-object)
  (emacsvox-mu4e-speak-header-summary))

(emacsvox-mu4e--register-after-group
 '(mu4e-headers-mark-for-unmark)
 #'emacsvox-mu4e--unmark-feedback)

(defun emacsvox-mu4e--execute-feedback (_target)
  "Announce execution of all Mu4e marks."
  (emacsvox-icon 'task-done)
  (tts-speak "Executed all marks"))

(emacsvox-mu4e--register-after-group
 '(mu4e-mark-execute-all)
 #'emacsvox-mu4e--execute-feedback)

(defun emacsvox-mu4e--open-feedback (_target)
  "Speak the Mu4e main view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-mu4e--register-after-group
 '(mu4e)
 #'emacsvox-mu4e--open-feedback)

(defun emacsvox-mu4e--update-feedback (_target)
  "Announce a Mu4e mail update."
  (emacsvox-icon 'progress)
  (tts-speak "Updating mail"))

(emacsvox-mu4e--register-after-group
 '(mu4e-update-mail-and-index)
 #'emacsvox-mu4e--update-feedback)

(defun emacsvox-mu4e--install-advice ()
  "Install advice for Mu4e features loaded so far."
  (dolist (entry emacsvox-mu4e--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-mu4e)))))))

(dolist (feature '(message mu4e mu4e-compose mu4e-headers mu4e-mark
                   mu4e-search mu4e-update mu4e-view))
  (eval `(with-eval-after-load ',feature
           (emacsvox-mu4e--install-advice))))

(provide 'emacsvox-mu4e)
;;;  end of file
