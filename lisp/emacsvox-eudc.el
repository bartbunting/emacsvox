;;; emacsvox-eudc.el --- Speech enable  LDAP -*- lexical-binding: t; -*- 

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; EUDC --Emacs Universal Directory Client 
;; provides a unified interface to directory servers
;; e.g. ldap servers
;; this module speech enables eudc 

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'widget)
(require 'emacsvox-widget)
(require 'eudc)
(declare-function widget-at "wid-edit" (&optional pos))
(declare-function widget-type "wid-edit" (widget))

;;;  speech enable interactive commands 

(defun emacsvox--advice-eudc-move-to-next-record-after (&rest _)
  "speak. "
  (when (ems-interactive-p 'eudc-move-to-next-record)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'eudc-move-to-next-record :after
            #'emacsvox--advice-eudc-move-to-next-record-after)

(defun emacsvox--advice-eudc-move-to-previous-record-after (&rest _)
  "speak. "
  (when (ems-interactive-p 'eudc-move-to-previous-record)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'eudc-move-to-previous-record :after
            #'emacsvox--advice-eudc-move-to-previous-record-after)

;;;  speech enable  eudc widgets 

(defun emacsvox-eudc-widget-help (widget)
  "Provides emacsvox help for eudc widgets. "
  (cond
   ((eq (widget-type widget) 'editable-field)
    (concat (ems--this-line) "Edit "))
   ((eq (widget-type widget) 'push-button)
    (concat "Push button "
            (widget-value widget)))
   (t (emacsvox-widget-default-summarize widget))))

(defun emacsvox-eudc-widgets-add-emacsvox-help ()
  "Adds emacsvox widget help to all EUDC widgets. "
  (save-excursion 
    (goto-char (point-min))
    (while  (not (eobp))
      (goto-char (next-overlay-change (point)))
      (when (widget-at (point))
        (widget-put (widget-at (point))
                    :emacsvox-help 
                    'emacsvox-eudc-widget-help)
        (forward-line 1)))))

(defun emacsvox--advice-eudc-query-form-after (&rest _)
  "Attach emacsvox help to all EUDC widgets.\nSummarize the form to welcome the user. "
  
  (emacsvox-eudc-widgets-add-emacsvox-help)
  (emacsvox-icon 'open-object)
  (let
      ((server (propertize "Server " 'personality voice-smoothen))
       (host eudc-server))
    (tts-speak
     (concat server " " host " "
             (when (widget-at (point))
               (emacsvox-eudc-widget-help (widget-at (point))))))))

(advice-add 'eudc-query-form :after
            #'emacsvox--advice-eudc-query-form-after)

;;;  additional interactive commands 

(defun emacsvox-eudc-send-mail ()
  "Send email to the address given by the current record. "
  (interactive)
  (unless (eq major-mode  'eudc-mode)
    (error "This command should be called in EUDC buffers. "))
  (let ((record
         (overlay-get (car (overlays-at (point))) 'eudc-record))
        (mail nil))
    (unless record (error "Not on a record. "))
    (setq mail
          (cdr (assq 'mail record)))
    (if mail
        (sendmail-user-agent-compose mail)
      (error "Cannot determine email address from record %s"
             (cdr (assq 'mail record))))))

;;;  bind additional commands 

(cl-declaim (special eudc-mode-map))
(when (boundp 'eudc-mode-map)
  (define-key eudc-mode-map "m" 'emacsvox-eudc-send-mail)
  )

;;;  voiceify values in results 

(defvar emacsvox-eudc-attribute-value-personality
  voice-animate
  "Personality t use for voiceifying attribute values. ")

(defun emacsvox--advice-eudc-print-attribute-value-around
    (orig-fun &rest args)
  "voiceify attribute values"
  (if (not emacsvox-eudc-attribute-value-personality)
      (apply orig-fun args)
    (let ((start (point)))
      (let ((result (apply orig-fun args)))
        (with-silent-modifications
          (put-text-property start (point) 'personality
                             emacsvox-eudc-attribute-value-personality))
        result))))

(advice-add 'eudc-print-attribute-value :around
            #'emacsvox--advice-eudc-print-attribute-value-around)

(provide 'emacsvox-eudc)

;;; emacsvox-eudc.el ends here
