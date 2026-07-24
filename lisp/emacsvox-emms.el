;;; emacsvox-emms.el --- Speech-enable EMMS -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech-enable EMMS
;; Keywords: Emacsvox, Multimedia
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4150 $ |
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

;;;   Introduction

;;; Commentary:
;; Speech-enables EMMS --- the Emacs equivalent of XMMS
;; available from  the Emacs package archive.
;; http://savannah.gnu.org/project/emms
;; EMMS is under active development,
;; to get the current CVS version, use Emacsvox command
;; M-x emacsvox-cvs-gnu-get-project-snapshot RET emms RET
;; 
;;; Code:

;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(declare-function emms-playlist-current-selected-track "emacsvox-emms" t)
(declare-function emms-player-pause "emacsvox-emms" t)

;;;  module emms:

(defun emacsvox-emms-speak-current-track ()
  "Speak current track."
  (interactive)
  (message
   (cdr (assq 'name (emms-playlist-current-selected-track)))))

(defvar emacsvox-emms--advice nil
  "Current EMMS targets and their native advice functions.")
(setq emacsvox-emms--advice nil)

(defun emacsvox-emms--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-emms--advice))))

(defun emacsvox-emms--selection-feedback ()
  "Play a selection icon after an EMMS operation."
  (emacsvox-icon 'select-object))

(emacsvox-emms--register-after-group
 '(emms-next emms-next-noerror emms-previous
   emms-start emms-stop emms-sort emms-shuffle emms-random
   emms-playlist-mode-play-smart)
 #'emacsvox-emms--selection-feedback)

(defun emacsvox-emms--large-movement-feedback ()
  "Speak after moving to the end of an EMMS playlist."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-emms--register-after-group
 '(emms-playlist-first emms-playlist-last
   emms-playlist-mode-first emms-playlist-mode-last)
 #'emacsvox-emms--large-movement-feedback)

(defun emacsvox-emms--open-feedback ()
  "Speak after opening an EMMS browser."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(emacsvox-emms--register-after-group
 '(emms-browser)
 #'emacsvox-emms--open-feedback)

(defun emacsvox-emms--close-feedback ()
  "Speak after closing an EMMS browser."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'close-object))

(emacsvox-emms--register-after-group
 '(emms-browser-bury-buffer)
 #'emacsvox-emms--close-feedback)

(defun emacsvox-emms--mode-line-feedback ()
  "Speak the current mode line after an EMMS command."
  (emacsvox-speak-mode-line))

(emacsvox-emms--register-after-group
 '(emms-playlist-mode-go
   emms-playlist-mode-next
   emms-playlist-mode-previous
   emms-playlist-mode-switch-buffer
   emms-streams)
 #'emacsvox-emms--mode-line-feedback)

(defun emacsvox-emms--task-feedback ()
  "Confirm an EMMS playlist operation."
  (emacsvox-icon 'task-done))

(emacsvox-emms--register-after-group
 '(emms-playlist-clear emms-playlist-mode-kill-track)
 #'emacsvox-emms--task-feedback)

(defun emacsvox-emms--bury-playlist-feedback ()
  "Announce the buffer selected after burying an EMMS playlist."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(emacsvox-emms--register-after-group
 '(emms-playlist-mode-bury-buffer)
 #'emacsvox-emms--bury-playlist-feedback)

(defun emacsvox--advice-emms-info-really-initialize-track-around
    (original &rest args)
  "Call ORIGINAL with ARGS while silencing metadata chatter."
  (ems-with-messages-silenced
   (apply original args)))

(push '(emms-info-really-initialize-track :around
        emacsvox--advice-emms-info-really-initialize-track-around)
      emacsvox-emms--advice)

(defconst emacsvox-emms--removed-targets
  '(emms-browser-next-filter emms-browser-previous-filter
    emms-stream-mode emms-stream-delete-bookmark
    emms-stream-save-bookmarks-file emms-stream-quit
    emms-stream-popup emms-stream-popup-revert
    emms-stream-next-line emms-stream-previous-line)
  "Commands removed by current EMMS browser and streams implementations.")

(defun emacsvox-emms--install-advice ()
  "Install native advice for currently loaded EMMS features."
  (dolist (entry emacsvox-emms--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature
         '(emms emms-browser emms-info emms-playlist-mode emms-streams))
  (eval
   `(with-eval-after-load ',feature
      (emacsvox-emms--install-advice))))

;;;  pause/resume if needed

(defun emacsvox-emms-pause-or-resume ()
  "Pause/resume if emms is running. For use  in
emacsvox-silence-hook."
  
  (when (and (boundp 'emms-player-playing-p)
             (not (null emms-player-playing-p)))
    (emms-player-pause)))

(add-hook 'emacsvox-silence-hook 'emacsvox-emms-pause-or-resume)

(provide 'emacsvox-emms)
;;;  end of file
