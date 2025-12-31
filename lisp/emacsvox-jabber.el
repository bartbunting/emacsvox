;;; emacsvox-jabber.el --- Speech-Enable jabber  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: speech-enable jabber
;; Keywords: Emacsvox, jabber
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

:

;;; Commentary:
;; emacs-jabber.el implements a  jabber client for emacs
;; emacs-jabber is hosted at sourceforge.
;; I use emacs-jabber with my gmail.com account

;;; Code:

;;   Required modules:

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(with-no-warnings (require 'jabber "jabber" 'no-error))

;;; Forward decls:
(declare-function jabber-activity-switch-to "jabber" (&optional jid-param))
(declare-function jabber-jid-user "jabber" (jid))
(declare-function jabber-jid-displayname "jabber" (string))
(declare-function jabber-jid-resource "jabber" (jid))
(declare-function jabber-muc-sender-p "jabber" (jid))
nil

;;;  map voices

(voice-setup-add-map
 '(
   (jabber-activity-face        voice-animate-extra)
   (jabber-chat-error           voice-monotone)
   (jabber-chat-prompt-foreign  voice-brighten-medium)
   (jabber-chat-prompt-local    voice-smoothen-medium)
   (jabber-chat-prompt-system   voice-brighten-extra)
   (jabber-chat-text-foreign    voice-lighten) 
   (jabber-chat-text-local      voice-smoothen)
   (jabber-rare-time-face       voice-animate-extra)
   (jabber-roster-user-away     voice-smoothen-extra)
   (jabber-roster-user-chatty   voice-brighten)
   (jabber-roster-user-dnd      voice-lighten-medium)
   (jabber-roster-user-error    voice-monotone)
   (jabber-roster-user-offline  voice-smoothen-extra)
   (jabber-roster-user-online   voice-bolden)
   (jabber-roster-user-xa       voice-lighten)
   (jabber-title-large          voice-bolden-extra)
   (jabber-title-medium         voice-bolden)
   (jabber-title-small          voice-lighten)
   ))

;;;  Advice interactive commands:

(defun ems--jabber-switch-to-roster-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'jabber-switch-to-roster-buffer :after
            #'ems--jabber-switch-to-roster-buffer-after)

;;;  silence keepalive

(cl-loop
 for f in
 '(
   image-type jabber-chat-with jabber-chat-with-jid-at-point
   jabber-keepalive-do jabber-fsm-handle-sentinel
   jabber-xml-resolve-namespace-prefixes
   jabber-process-roster jabber-keepalive-got-response)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Silence  messages."
     (ems-with-messages-silenced
      ad-do-it
      ad-return-value))))

;;;  jabber activity:

(defun ems--jabber-activity-switch-to-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'jabber-activity-switch-to :after
            #'ems--jabber-activity-switch-to-after)

;;;  chat buffer:

(defun ems--jabber-chat-buffer-send-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p) (emacsvox-icon 'close-object)))

(advice-add 'jabber-chat-buffer-send :after
            #'ems--jabber-chat-buffer-send-after)

;;;  alerts

(defcustom emacsvox-jabber-speak-presence-alerts nil
  "Set to T if you want to hear presence alerts."
  :type  'boolean
  :group 'emacsvox-jabber)

(defun ems--jabber-send-default-presence-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Sent default presence.")))

(advice-add 'jabber-send-default-presence :after
            #'ems--jabber-send-default-presence-after)

(defun ems--jabber-send-away-presence-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (message "Set to be away.")))

(advice-add 'jabber-send-away-presence :after
            #'ems--jabber-send-away-presence-after)

(defun ems--jabber-send-xa-presence-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (message "Set extended  away.")))

(advice-add 'jabber-send-xa-presence :after
            #'ems--jabber-send-xa-presence-after)

(defun ems--jabber-go-to-next-jid-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'jabber-go-to-next-jid :after
            #'ems--jabber-go-to-next-jid-after)

(defun ems--jabber-go-to-previous-jid-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'jabber-go-to-previous-jid :after
            #'ems--jabber-go-to-previous-jid-after)

(defun emacsvox-jabber-presence-default-message (&rest _ignore)
  "Default presence alert used by Emacsvox.
Silently drops alerts on the floor --- Google Talk is too chatty otherwise."
  nil)
(cl-declaim (special jabber-alert-presence-message-function))
(setq
 jabber-alert-presence-message-function
 #'emacsvox-jabber-presence-default-message)

;; this is what I use as my jabber alert function:
(defun emacsvox-jabber-message-default-message (from buffer text)
  "Speak the message."
  
  (when (or jabber-message-alert-same-buffer
            (not (memq (selected-window) (get-buffer-window-list buffer))))
    (emacsvox-icon 'item)
    (dtk-notify
     (if (jabber-muc-sender-p from)
         (format "Private message from %s in %s"
                 (jabber-jid-resource from)
                 (jabber-jid-displayname (jabber-jid-user from)))
       (format "%s: %s" (jabber-jid-displayname from) text)))))

;;;  interactive commands:

(defun emacsvox-jabber-popup-roster ()
  "Pop to Jabber roster."
  (interactive)
  
  (unless jabber-connections  (call-interactively 'jabber-connect))
  (unless (buffer-live-p jabber-roster-buffer)
    (call-interactively 'jabber-display-roster))
  (pop-to-buffer jabber-roster-buffer)
  (goto-char (point-min))
  (forward-line 4)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(defun ems--jabber-connect-all-after (&rest _)
  "switch to roster so we give it a chance to update."
  (when (ems-interactive-p) (switch-to-buffer jabber-roster-buffer)))

(advice-add 'jabber-connect-all :after #'ems--jabber-connect-all-after)

(defun ems--jabber-roster-update-around (orig-fun &rest args)
  "Make this operation a No-Op unless the roster is visible."
  (when (get-buffer-window-list jabber-roster-buffer)
    (apply orig-fun args)))

(advice-add 'jabber-roster-update :around
            #'ems--jabber-roster-update-around)

(defun ems--jabber-display-roster-around (orig-fun &rest args)
  "Make this operation a No-Op unless called interactively."
  (when (ems-interactive-p) (apply orig-fun args)))

(advice-add 'jabber-display-roster :around
            #'ems--jabber-display-roster-around)

(add-hook 'jabber-post-connect-hook 'jabber-switch-to-roster-buffer)

(defun emacsvox-jabber-connected ()
  "Function to add to jabber-post-connection-hook."
  (emacsvox-icon 'task-done)
  (dtk-notify "Connected to jabber."))
(add-hook 'jabber-post-connect-hook #'emacsvox-jabber-connected)

;;;  Pronunciations
(cl-declaim (special emacsvox-pronounce-internet-smileys-pronunciations))
(emacsvox-pronounce-augment
 'jabber-chat-mode
 emacsvox-pronounce-internet-smileys-pronunciations)
(emacsvox-pronounce-augment
 'jabber-mode
 emacsvox-pronounce-internet-smileys-pronunciations)

;;;  Browse chat buffers:
(defun emacsvox-jabber-chat-speak-this-message(&optional copy-as-kill)
  "Speak chat message under point.
With optional interactive prefix arg `copy-as-kill', copy it to
the kill ring as well."
  (interactive "P")
  (let ((range (emacsvox-speak-range)))
    (when copy-as-kill (kill-new range))
    (dtk-speak range)))

(defun emacsvox-jabber-chat-next-message ()
  "Move forward to and speak the next message in this chat session."
  (interactive)
  (cl-assert
   (eq major-mode 'jabber-chat-mode) nil  "Not in a Jabber chat buffer.")
  (end-of-line)
  (goto-char (next-single-property-change (point) 'face nil(point-max)))
  (while (and (not (eobp))
              (or (null (get-text-property (point) 'face))
                  (get-text-property (point) 'field)))
    (goto-char (next-single-property-change (point) 'face  nil  (point-max))))
  (cond
   ((eobp)
    (message "On last message")
    (emacsvox-icon 'warn-user))
   (t(emacsvox-icon 'select-object)
     (emacsvox-speak-range))))

(defun emacsvox-jabber-chat-previous-message ()
  "Move backward to and speak the previous message in this chat session."
  (interactive)
  (cl-assert
   (eq major-mode 'jabber-chat-mode) nil "Not in a Jabber chat buffer.")
  (beginning-of-line)
  (goto-char (previous-single-property-change (point) 'face nil  (point-min)))
  (while  (and (not (bobp))
               (or (null (get-text-property (point) 'face))
                   (get-text-property (point) 'field)))
    (goto-char
     (previous-single-property-change (point) 'face  nil  (point-min))))
  (cond
   ((bobp)
    (message "On first message")
    (emacsvox-icon 'warn-user))
   (t(emacsvox-icon 'select-object)
     (emacsvox-speak-range))))

(when (boundp 'jabber-chat-mode-map)
  (cl-loop
   for k in
   '(
     ("M-n" emacsvox-jabber-chat-next-message)
     ("M-p" emacsvox-jabber-chat-previous-message)
     ("M-SPC " emacsvox-jabber-chat-speak-this-message))
   do
   (emacsvox-keymap-update  jabber-chat-mode-map k)))

;;;  Speak recent message:

(defun emacsvox-jabber-speak-recent-message ()
  "Speak most recent message if one exists."
  (interactive)
  
  (cond
   (jabber-activity-jids
    (save-excursion
      (jabber-activity-switch-to)
      (goto-char (point-max))
      (emacsvox-jabber-chat-previous-message)))
   (t (message "No recent message."))))

;;; Setup:

(defun emacsvox-jabber-setup ()
  "Initial jabber setup."
  
  (cl-loop 
   for b in
   '(
     ("r" jabber-activity-switch-to)
     ("j" emacsvox-jabber-popup-roster)
     ("SPC" emacsvox-jabber-speak-recent-message))
   do
   (define-key emacsvox-x-keymap (cl-first b) (cl-second b))))

(cl-eval-when '(load) (emacsvox-jabber-setup))

(provide 'emacsvox-jabber)
;;;  end of file

