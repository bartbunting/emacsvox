;;; emacsvox-pianobar.el --- Speech-enable Pandora  -*- lexical-binding: t; -*-
;; $Id: emacsvox-pianobar.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable PIANOBAR An Emacs Interface to pianobar
;; Keywords: Emacsvox,  Audio Desktop pianobar
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
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
;; MERCHANTABILITY or FITNPIANOBAR FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; @subsection PIANOBAR ==  Pandora Client for Emacs

;; pianobar git://github.com/PromyLOPh/pianobar.git Ubuntu/Debian:
;; sudo apt-get install pianobar 

;; Pianobar Is a stand-alone client for Pandora Radio. pianobar.el
;; available on the Emacs Wiki at
;; http://www.emacswiki.org/emacs/pianobar.el Provides access to
;; Pandora Radio via pianobar from the comfort of Emacs. This module
;; speech-enables Pianobar and enhances it for the Complete Audio
;; Desktop.

;; @subsection Emacsvox Usage:

;; Emacsvox implements command emacsvox-pianobar, a light-weight
;; wrapper on top of pianobar. Emacsvox binds this command to
;; @code{C-' '}. 
;;  Command emacsvox-pianobar is designed to let you
;; launch Pandora channels and switch tracks/channels without moving
;; away from your primary tasks such as editing code or
;; reading/composing email. Toward this end, launching command
;; emacsvox-pianobar the first time initializes the
;; @code{*pianobar*} buffer and launches command @code{pianobar};
;; but focus  remains   in your current buffer. Pianobar can be
;; controlled with single keystrokes while in  the pianobar  buffer
;; --- switch to   using @code{C-e ''}. The most
;; useful keys are @code{right} for skipping tracks, @code{up} and
;; @code{down} for switching channels etc.; see the keys bound in
;; @code{pianobar-key-map} for a complete list. Pressing @code{C-e '}
;; in  the @code{*pianobar*} buffer  buries the
;; @code{*pianobar*}. From here on, Pianobar can be controlled
;; by pressing the Pianobar prefix key (@code{C-e '}) followed by
;; keys from @code{pianobar-key-map}.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'pianobar "pianobar" 'no-error)
(require 'ansi-color)
(require 'emacsvox-comint)
;;;  Pianobar Fixups:

(defun emacsvox-pianobar-current-song  ()
  "Return current song."
  (cl-declare (special pianobar-current-song))
  (ansi-color-apply
   (substring pianobar-current-song
              (+ 2 (string-match "|>" pianobar-current-song)))))


(defun ems--pianobar-currently-playing-around (orig-fun &rest args)
  "Override with our own notifier."
  (message (emacsvox-pianobar-current-song)))


(advice-add 'pianobar-currently-playing :around
	    #'ems--pianobar-currently-playing-around)




;;;  Advice Interactive Commands:

(declare-function pianobar "ext:pianobar" nil)
(declare-function pianobar-send-string  "ext:pianobar" (cmd))
(defun emacsvox-pianobar-volume-down ()
  "Decrease volume"
  (interactive)
  (pianobar-send-string "(\n"))

(defun emacsvox-pianobar-volume-up ()
  "Increase volume"
  (interactive)
  (pianobar-send-string ")\n"))

(defun ems--pianobar-after (&rest _)
  "speak."
  (with-current-buffer pianobar-buffer
    (define-key pianobar-key-map "l" 'pianobar-love-current-song)
    (define-key pianobar-key-map "t"
		'emacsvox-pianobar-electric-mode-toggle)
    (define-key pianobar-key-map (kbd "RET")
		'emacsvox-pianobar-send-raw)
    (define-key pianobar-key-map [right] 'pianobar-next-song)
    (dotimes (i 10)
      (define-key pianobar-key-map (format "%s" i)
		  'emacsvox-pianobar-switch-to-preset))
    (dotimes (i 25)
      (define-key pianobar-key-map (format "%c" (+ i 65))
		  'emacsvox-pianobar-switch-to-preset))
    (define-key pianobar-key-map [up]
		'emacsvox-pianobar-previous-preset)
    (define-key pianobar-key-map [down]
		'emacsvox-pianobar-next-preset)
    (define-key pianobar-key-map ","
		'emacsvox-pianobar-previous-preset)
    (define-key pianobar-key-map "." 'emacsvox-pianobar-next-preset)
    (define-key pianobar-key-map "<"
		'emacsvox-pianobar-previous-preset)
    (define-key pianobar-key-map ">" 'emacsvox-pianobar-next-preset)
    (define-key pianobar-key-map "(" 'emacsvox-pianobar-volume-down)
    (define-key pianobar-key-map [prior]
		'emacsvox-pianobar-volume-down)
    (define-key pianobar-key-map ")" 'emacsvox-pianobar-volume-up)
    (define-key pianobar-key-map [next] 'emacsvox-pianobar-volume-up)
    (use-local-map pianobar-key-map) (emacsvox-speak-mode-line)
    (bury-buffer) (emacsvox-icon 'open-object)))


(advice-add 'pianobar :after #'ems--pianobar-after)




;; Advice all actions to play a pre-auditory icon

(cl-loop
 for  f in
 '(pianobar-pause-song pianobar-love-current-song
                       pianobar-ban-current-song pianobar-bookmark-song
                       pianobar-create-station pianobar-delete-current-station
                       pianobar-explain-song
                       pianobar-add-shared-station pianobar-song-history
                       pianobar-currently-playing pianobar-add-shared-station
                       pianobar-move-song-different-station pianobar-next-song
                       pianobar-rename-current-station
                       pianobar-change-station
                       pianobar-tired-of-song
                       pianobar-upcoming-songs
                       pianobar-select-quickmix-stations pianobar-next-song)
 do
 (eval
  `(defadvice ,f (before emacsvox pre act comp)
     "Play auditory icon."
     (when (ems-interactive-p)
       (emacsvox-icon 'item)))))


(defun ems--pianobar-window-toggle-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((state (get-buffer-window pianobar-buffer)))
      (cond
       (state (emacsvox-icon 'open-object)
	      (dtk-speak "Displayed pianobar"))
       (t (emacsvox-icon 'close-object) (dtk-speak "Hid Pianobar "))))))


(advice-add 'pianobar-window-toggle :after
	    #'ems--pianobar-window-toggle-after)





(defun ems--pianobar-quit-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))


(advice-add 'pianobar-quit :after #'ems--pianobar-quit-after)




;;;  emacsvox-pianobar

(defvar emacsvox-pianobar-electric-mode t
  "Records if electric mode is on.")

(defun emacsvox-pianobar-electric-mode-toggle ()
  "Toggle electric mode in pianobar buffer.
If electric mode is on, keystrokes invoke pianobar commands directly."
  (interactive)
  (cl-declare (special emacsvox-pianobar-electric-mode
                       pianobar-key-map pianobar-buffer))
  (with-current-buffer pianobar-buffer
    (cond
     (emacsvox-pianobar-electric-mode  ; turn it off
      (use-local-map nil)
      (setq emacsvox-pianobar-electric-mode nil)
      (emacsvox-icon 'off))
     (t                                 ;turn it on
      (use-local-map pianobar-key-map)
      (setq emacsvox-pianobar-electric-mode t)
      (emacsvox-icon 'on)))
    (message "Turned %s pianobar electric mode."
             (if emacsvox-pianobar-electric-mode 'on 'off))))

;;;###autoload
(defun emacsvox-pianobar  ()
  "Start or control Emacsvox Pianobar player."
  (interactive)
  (cl-declare (special pianobar-buffer emacsvox-comint-autospeak))
  (cond
   ((and  (buffer-live-p (get-buffer pianobar-buffer))
          (processp (get-buffer-process pianobar-buffer))
          (eq 'run (process-status (get-buffer-process  pianobar-buffer))))
    (call-interactively 'emacsvox-pianobar-command))
   (t
    (pianobar)
    (with-current-buffer (get-buffer pianobar-buffer)
      (when emacsvox-comint-autospeak (emacsvox-toggle-comint-autospeak))))))

(defun emacsvox-pianobar-hide-or-show ()
  "Hide or show pianobar."
  (cond
   ((eq (current-buffer) (get-buffer pianobar-buffer))
    (bury-buffer)
    (emacsvox-icon 'close-object))
   ((get-buffer-window pianobar-buffer)
    (bury-buffer pianobar-buffer)
    (delete-windows-on pianobar-buffer)
    (emacsvox-icon 'close-object))
   (t (pop-to-buffer pianobar-buffer)
      (emacsvox-icon 'open-object))))

(defun emacsvox-pianobar-command (key)
  "Invoke Pianobar  commands."
  (interactive (list (read-key-sequence "Pianobar Key: ")))
  (cl-declare (special pianobar-key-map))
  (cond
   ((and (stringp key)
         (string= "'" key))
    (emacsvox-pianobar-hide-or-show)
    (emacsvox-speak-mode-line))
   ((lookup-key pianobar-key-map key)
    (call-interactively (lookup-key pianobar-key-map key)))
   (t (pianobar-send-string  key))))

(defvar emacsvox-pianobar-max-preset 28
  "Number of presets.")

(defvar emacsvox-pianobar-current-preset 0
  "Current preset.")

;; Station Presets
(defun emacsvox-pianobar-switch-to-preset ()
  "Switch to one of the  presets."
  (interactive)
  (cl-declare (special last-input-event emacsvox-pianobar-current-preset))
  (let ((preset last-input-event))
    (setq emacsvox-pianobar-current-preset
          (cond
           ((and (<= 48 preset) (<= preset 57))
            (- preset 48)) ; 0..9
           ((and (<= 65 preset) (<= preset 90)) ; 10.. 35 A..Z
            (- preset 55))
           (t (read-string "Preset: "))))
    (pianobar-send-string (format "s%s\n" emacsvox-pianobar-current-preset))))

(defun emacsvox-pianobar-next-preset ()
  "Switch to next preset."
  (interactive)
  (cl-declare (special
               emacsvox-pianobar-current-preset emacsvox-pianobar-max-preset))
  (when (= emacsvox-pianobar-max-preset emacsvox-pianobar-current-preset)
    (setq emacsvox-pianobar-current-preset -1))
  (setq emacsvox-pianobar-current-preset
        (1+ emacsvox-pianobar-current-preset))
  (pianobar-send-string (format "s%s\n" emacsvox-pianobar-current-preset)))

(defun emacsvox-pianobar-previous-preset ()
  "Switch to previous preset."
  (interactive)
  (cl-declare (special
               emacsvox-pianobar-current-preset emacsvox-pianobar-max-preset))
  (when (zerop emacsvox-pianobar-current-preset)
    (setq emacsvox-pianobar-current-preset (1+ emacsvox-pianobar-max-preset)))
  (setq emacsvox-pianobar-current-preset
        (1- emacsvox-pianobar-current-preset))
  (pianobar-send-string (format "s%s\n" emacsvox-pianobar-current-preset)))

(defun emacsvox-pianobar-send-raw  (string)
  "Send raw string with newline added to pianobar."
  (interactive "sString:")
  (pianobar-send-string (format "%s\n" string)))

(provide 'emacsvox-pianobar)
;; reload pianobar to fix our vol-change commands.

;;;  end of file

