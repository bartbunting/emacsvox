;;; emacsvox-erc.el --- speech-enable erc -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox module for speech-enabling erc.el
;; Keywords: Emacsvox, erc
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4502 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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


;;; Commentary:
;; erc.el is a modern Emacs client for IRC including color
;; and font locking support. 
;; erc.el - an Emacs IRC client (by Alexander L. Belikoff)
;; http://www.cs.cmu.edu/~berez/irc/erc.el

;;; Code:

;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'erc)
;;;   variables

(cl-declaim (special emacsvox-sounds-dir))

;;;  personalities 

(defgroup emacsvox-erc nil
  "Emacsvox extension for IRC client ERC."
  :group 'emacsvox
  :prefix "emacsvox-erc-")

(defcustom emacsvox-erc-ignore-notices t
  "Set to T if you dont want to see notification  messages from the
server."
  :type 'boolean
  :group 'emacsvox-erc)

(voice-setup-add-map
 '(
   (erc-direct-msg-face voice-animate)
   (erc-input-face voice-smoothen)
   (erc-bold-face voice-bolden)
   (erc-inverse-face voice-lighten-extra)
   (erc-underline-face voice-brighten-medium)
   (erc-prompt-face voice-animate)
   (erc-notice-face  'inaudible)
   (erc-action-face voice-monotone-extra)
   (erc-error-face voice-bolden-and-animate)
   (erc-dangerous-host-face voice-brighten-extra)
   (erc-pal-face voice-animate-extra)
   (erc-keyword-face voice-animate)
   ))

;;;   helpers

;;;  advice interactive commands
(cl-declaim (special emacsvox-pronounce-internet-smileys-pronunciations))
(emacsvox-pronounce-augment
 'erc-mode
 emacsvox-pronounce-internet-smileys-pronunciations)

(defvar voice-lock-mode)

(defun emacsvox--advice-erc-mode-after (&rest _)
  "Turn on voice lock mode."
  (emacsvox-pronounce-refresh-pronunciations)
  (setq voice-lock-mode t))

(advice-add 'erc-mode :after #'emacsvox--advice-erc-mode-after)

(defun emacsvox--advice-erc-select-after (&rest _)
  "Announce an interactively selected ERC buffer."
  (when (ems-interactive-p 'erc-select)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'erc-select :after #'emacsvox--advice-erc-select-after)

(defun emacsvox--advice-erc-send-current-line-after (&rest _)
  "Provide auditory icon."
  (when (ems-interactive-p 'erc-send-current-line)
    (emacsvox-icon 'select-object)))

(advice-add 'erc-send-current-line :after
            #'emacsvox--advice-erc-send-current-line-after)

;;;  monitoring chatrooms 
(defvar emacsvox-erc-room-monitor nil
  "Local to each chat room. If turned on,
user is notified about activity in the room.")
(make-variable-buffer-local 'emacsvox-erc-room-monitor)

(defvar emacsvox-erc-people-to-monitor nil
  "List of strings specifying people to monitor in a given room.")

(make-variable-buffer-local
 'emacsvox-erc-people-to-monitor)

(defvar emacsvox-erc-monitor-my-messages t
  "If T, then messages to your specified nick will be
spoken.")

(make-variable-buffer-local 'emacsvox-erc-monitor-my-messages)

(defcustom emacsvox-erc-my-nick ""
  "My IRC nick."
  :type 'string
  :group 'emacsvox-erc)

(defun emacsvox-erc-read-person (action)
  "Helper to prompt for and read person in ERC."
  (read-from-minibuffer
   (format "%s person" action)
   (save-excursion
     (let ((start (point)))
       (search-backward  "<" (point-min) t)
       (when (not (= start (point)))
         (setq start (point))
         (search-forward " ")
         (buffer-substring start (1- (point))))))))

(defun emacsvox-erc-add-name-to-monitor (name &optional
                                              quiten-pronunciation)
  "Add people to monitor in this room.
Optional interactive prefix  arg defines a pronunciation that
  silences speaking of this perso's name."
  (interactive
   (list
    (emacsvox-erc-read-person "Add ")
    current-prefix-arg))
  
  (unless (eq major-mode 'erc-mode)
    (error "Not in an ERC buffer."))
  (cl-pushnew name emacsvox-erc-people-to-monitor :test #'string-equal)
  (when quiten-pronunciation
    (emacsvox-pronounce-add-local-entry name ""))
  (emacsvox-icon 'select-object)
  (message "monitoring %s"
           (mapconcat #'identity 
                      emacsvox-erc-people-to-monitor " ")))

(defun emacsvox-erc-delete-name-from-monitor (name)
  "Remove name to monitor in this room."
  (interactive
   (list
    (emacsvox-erc-read-person "Delete ")))
  
  (unless (eq major-mode 'erc-mode)
    (error "Not in an ERC buffer."))
  (setq emacsvox-erc-people-to-monitor
        (cl-remove-if
         #'(lambda (x)
             (string-equal x name))
         emacsvox-erc-people-to-monitor))
  (emacsvox-icon 'delete-object)
  (message "monitoring %s"
           (mapconcat #'identity 
                      emacsvox-erc-people-to-monitor " ")))
(defcustom emacsvox-erc-speak-all-participants nil
  "Speak all things said if t."
  :type 'boolean
  :group 'emacsvox-erc)

(make-variable-buffer-local 'emacsvox-erc-speak-all-participants)

(defun emacsvox-erc-compute-message (string _buffer)
  "Uses environment of buffer to decide what message to
display. String is the original message."
  (let ((who-from (car (split-string string)))
        (case-fold-search t))
    (cond
     (emacsvox-erc-speak-all-participants string)
     ((and
       (not (string-match "^\\*\\*\\*" who-from))
       emacsvox-erc-people-to-monitor
       (cl-find
        who-from
        emacsvox-erc-people-to-monitor
        :test #'string-equal))
      string)
     ((and emacsvox-erc-monitor-my-messages
           (stringp emacsvox-erc-my-nick)
           (string-match emacsvox-erc-my-nick string))
      string)
     (t nil))))

(ems-generate-switcher
 'emacsvox-erc-toggle-speak-all-participants
 'emacsvox-erc-speak-all-participants
 "Toggle state of ERC speak all participants..
Interactive 
PREFIX arg means toggle the global default value, and then
set the current local value to the result.")

(defun emacsvox--advice-erc-insert-line-after (string buffer)
  "Speak monitored ERC message STRING inserted in BUFFER."
  (setq buffer
        (or buffer
            (and (boundp 'erc-server-process)
                 (processp erc-server-process)
                 (process-buffer erc-server-process))))
  (when (and (stringp string) (buffer-live-p buffer))
    (with-current-buffer buffer
      (when (and emacsvox-erc-room-monitor
                 emacsvox-erc-monitor-my-messages)
        (let ((emacsvox-speak-messages nil)
              (case-fold-search t)
              (msg (emacsvox-erc-compute-message string buffer)))
          (when msg
            (emacsvox-icon 'progress)
            (message "%s" msg)
            (tts-with-punctuations tts-punctuation-mode
              (tts-speak msg))))))))

(advice-add 'erc-insert-line :after
            #'emacsvox--advice-erc-insert-line-after)

(ems-generate-switcher 'emacsvox-erc-toggle-room-monitor
                       'emacsvox-erc-room-monitor
                       "Toggle state of ERC room monitor.
Interactive 
PREFIX arg means toggle the global default value, and then
set the current local value to the result.")

(ems-generate-switcher 'emacsvox-erc-toggle-my-monitor
                       'emacsvox-erc-monitor-my-messages
                       "Toggle state of ERC  monitor of my messages.
Interactive PREFIX arg means toggle the global default value, and then
set the current local value to the result.")

;;;  silence server messages 

(defun emacsvox--advice-erc-parse-server-response-around
    (orig-fun &rest args)
  "Run the ERC server parser once with automatic message speech silenced."
  (let ((emacsvox-speak-messages nil))
    (apply orig-fun args)))

(advice-add 'erc-parse-server-response :around
            #'emacsvox--advice-erc-parse-server-response-around)

;;;  define emacsvox keys
(cl-declaim (special erc-mode-map))
(when (and (boundp 'erc-mode-map)
           (keymapp erc-mode-map))
  (define-key erc-mode-map
              (kbd "C-c SPC") 'emacsvox-erc-toggle-speak-all-participants)
  (define-key erc-mode-map (kbd "C-c m")
              'emacsvox-erc-toggle-my-monitor)
  (define-key erc-mode-map (kbd "C-c C-m") 'emacsvox-erc-toggle-room-monitor)
  (define-key erc-mode-map (kbd "C-c C-a")
              'emacsvox-erc-add-name-to-monitor)
  (define-key erc-mode-map
              (kbd "C-c C-d") 'emacsvox-erc-delete-name-from-monitor))

;;;  cricket rules 
(defvar emacsvox-erc-cricket-bowling-figures-pattern
  " [0-9]+-[0-9]+-[0-9]+-[0-9] "
  "Pattern for matching bowling figures.")

(defun emacsvox-erc-cricket-convert-bowling-figures (pattern)
  "Pronounce bowling figures in cricket."
  (let ((fields (split-string pattern "-")))
    (format " %s for %s off %s overs with %s maidens "
            (cond
             ((string-equal "0" (cl-fourth fields)) 
              "none")
             (t (cl-fourth fields)))
            (cl-third fields)
            (cl-first fields)
            (cond
             ((string-equal "0" (cl-second fields)) 
              "no")
             (t (cl-second fields))))))

(defvar emacsvox-erc-cricket-4-6-pattern
  " [0-9]+x[46]"
  "Matches pattern used to  score number of fours and sixes in IRC #cricket.")

(defun emacsvox-erc-cricket-convert-4-6-pattern (pattern)
  "Convert 4/6 pattern for IRC cricket channels."
  (format "%s %s"
          (substring pattern 0 -2)
          (cond
           ((string-equal "4" 
                          (substring pattern -1))
            "fours")
           (t "sixes"))))
(defun emacsvox-erc-setup-cricket-rules ()
  "Set up #cricket channels."
  (interactive)
  (emacsvox-pronounce-add-local-entry
   "km/h," " kays, ")
  (emacsvox-pronounce-add-local-entry
   emacsvox-erc-cricket-bowling-figures-pattern
   (cons 're-search-forward
         'emacsvox-erc-cricket-convert-bowling-figures))
  (emacsvox-pronounce-add-local-entry
   emacsvox-erc-cricket-4-6-pattern
   (cons 're-search-forward
         'emacsvox-erc-cricket-convert-4-6-pattern))
  (emacsvox-pronounce-add-local-entry
   " [0-9]+nb"
   (cons
    're-search-forward
    #'(lambda (pattern)
        (format "%s no balls "
                (substring pattern 0 -2)))))
  (emacsvox-pronounce-add-local-entry
   "[0-9]+b"
   (cons
    're-search-forward
    #'(lambda (pattern)
        (format "%s balls "
                (substring pattern 0 -1)))))
  (emacsvox-pronounce-add-local-entry
   " [0-9]+w "
   (cons
    're-search-forward
    #'(lambda (pattern)
        (format "%s wides "
                (substring pattern 0 -1)))))
  (tts-set-punctuations 'some))

(provide 'emacsvox-erc)

;;;  end of file
