;;; emacsvox-bbdb.el --- Speech enable BBDB -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs bbdb
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
;; Speech-enables BBDB.
;; I have used BBDB to manage email address and contact information since 1991.
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(declare-function bbdb-record-list "bbdb-com" (records &optional full))

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

(defun emacsvox--advice-bbdb-delete-field-or-record-after (&rest _)
  "Speak after deleting a BBDB field or record."
  (when (ems-interactive-p 'bbdb-delete-field-or-record)
    (emacsvox-icon 'delete-object)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))

(defun emacsvox--advice-bbdb-edit-field-before (&rest _)
  "Provide an auditory icon before editing a BBDB field."
  (when (ems-interactive-p 'bbdb-edit-field)
    (emacsvox-icon 'open-object)))

(defun emacsvox--advice-bbdb-mail-before
    (records &optional subject _n _verbose)
  "Announce mail to RECORDS about SUBJECT."
  (when (ems-interactive-p 'bbdb-mail)
    (let* ((record-list (bbdb-record-list records))
           (to (and record-list (bbdb-dwim-mail (car record-list)))))
      (emacsvox-icon 'open-object)
      (message "Starting an email message %s to %s%s"
               (if subject (format "about %s" subject) "")
               (or to "no recipient")
               (if (cdr record-list) " and others" "")))))

(defun emacsvox--advice-bbdb-next-record-after (&rest _)
  "Speak after moving to the next BBDB record."
  (when (ems-interactive-p 'bbdb-next-record)
    (emacsvox-icon 'large-movement)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))

(defun emacsvox--advice-bbdb-prev-record-after (&rest _)
  "Speak after moving to the previous BBDB record."
  (when (ems-interactive-p 'bbdb-prev-record)
    (emacsvox-icon 'large-movement)
    (save-excursion
      (when (looking-at "\\?") (forward-line 1))
      (emacsvox-speak-line))))

(defun emacsvox--advice-bbdb-omit-record-after (&rest _)
  "Speak after omitting a BBDB record."
  (when (ems-interactive-p 'bbdb-omit-record)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-line)))

(defun emacsvox--advice-bbdb-toggle-records-layout-after (&rest _)
  "Confirm a change to the BBDB record layout."
  (when (ems-interactive-p 'bbdb-toggle-records-layout)
    (message "Toggled record display")))

(defun emacsvox--advice-bbdb-transpose-fields-after (&rest _)
  "Speak after transposing BBDB fields."
  (when (ems-interactive-p 'bbdb-transpose-fields)
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(defun emacsvox--advice-bbdb-complete-mail-around (original &rest arguments)
  "Speak the completion produced by ORIGINAL with ARGUMENTS."
  (let* ((prior (point))
         (buffer (current-buffer))
         (completion-ignore-case t)
         (result (apply original arguments)))
    (when (ems-interactive-p 'bbdb-complete-mail)
      (let ((completions (get-buffer "*Completions*")))
        (if (and completions
                 (window-live-p (get-buffer-window completions)))
            (progn
              (switch-to-completions)
              (setq completion-reference-buffer buffer)
              (unless (get-text-property (point) 'mouse-face)
                (goto-char
                 (next-single-property-change (point) 'mouse-face)))
              (tts-speak (emacsvox-get-current-completion)))
          (tts-speak
           (with-current-buffer buffer
             (buffer-substring prior (point)))))))
    result))

;;;   Advice mail-ua specific hooks

(defun emacsvox--advice-bbdb-mua-display-sender-after (&rest _)
  "Speak the BBDB record displayed for the message sender."
  (when (ems-interactive-p 'bbdb-mua-display-sender)
    (emacsvox-speak-other-window)))

;;;  Silence messages

(defun emacsvox--advice-bbdb-update-records-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS while silencing messages."
  (ems-with-messages-silenced
   (apply original arguments)))

(defconst emacsvox-bbdb--advice
  '((bbdb-delete-field-or-record :after
     emacsvox--advice-bbdb-delete-field-or-record-after)
    (bbdb-edit-field :before emacsvox--advice-bbdb-edit-field-before)
    (bbdb-mail :before emacsvox--advice-bbdb-mail-before)
    (bbdb-next-record :after emacsvox--advice-bbdb-next-record-after)
    (bbdb-prev-record :after emacsvox--advice-bbdb-prev-record-after)
    (bbdb-omit-record :after emacsvox--advice-bbdb-omit-record-after)
    (bbdb-toggle-records-layout :after
     emacsvox--advice-bbdb-toggle-records-layout-after)
    (bbdb-transpose-fields :after
     emacsvox--advice-bbdb-transpose-fields-after)
    (bbdb-complete-mail :around
     emacsvox--advice-bbdb-complete-mail-around)
    (bbdb-mua-display-sender :after
     emacsvox--advice-bbdb-mua-display-sender-after)
    (bbdb-update-records :around
     emacsvox--advice-bbdb-update-records-around))
  "Current BBDB targets and their native advice functions.")

(defun emacsvox-bbdb--install-advice ()
  "Install advice for functions present in current BBDB."
  (dolist (entry emacsvox-bbdb--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(bbdb bbdb-com bbdb-mua))
  (eval-after-load feature #'emacsvox-bbdb--install-advice))

(provide  'emacsvox-bbdb)

;;; emacsvox-bbdb.el ends here
