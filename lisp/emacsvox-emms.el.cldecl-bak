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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(declare-function emms-playlist-current-selected-track "emacsvox-emms" t)
(declare-function emms-player-pause "emacsvox-emms" t)

;;;  module emms:

(defun emacsvox-emms-speak-current-track ()
  "Speak current track."
  (interactive)
  (message
   (cdr (assq 'name (emms-playlist-current-selected-track)))))

(cl-loop for f in
         '(emms-next emms-next-noerror emms-previous)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "Speak track name."
             (when (ems-interactive-p)
               (emacsvox-icon 'select-object)))))

;; these commands should not be made to talk since that would  interferes
;; with real work.
(cl-loop for f in
         '(emms-start emms-stop emms-sort
                      emms-shuffle emms-random emms-playlist-mode-play-smart)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "Provide auditory icon."
             (when (ems-interactive-p)
               (emacsvox-icon 'select-object)))))

(cl-loop
 for f in
 '(emms-playlist-first emms-playlist-last
                       emms-playlist-mode-first emms-playlist-mode-last)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))
(cl-loop for f in
         '(emms-browser emms-browser-next-filter
                        emms-browser-previous-filter)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-speak-mode-line)
               (emacsvox-icon 'open-object)))))


(defun ems--emms-browser-bury-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'close-object)))


(advice-add 'emms-browser-bury-buffer :after
	    #'ems--emms-browser-bury-buffer-after)




;;; Playlists
(cl-loop for f in
         '(emms-playlist-mode-go
                        emms-playlist-mode-next
                        emms-playlist-mode-previous
                        emms-playlist-mode-switch-buffer
                        )
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-speak-mode-line)))))

(cl-loop for f in
         '(emms-playlist-clear emms-playlist-mode-kill-track)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-icon 'task-done)))))

;;;  Module emms-streaming:
(cl-declaim (special emms-stream-mode-map))

(defun ems--emms-stream-mode-after (&rest _)
  "Update keymaps."
  (define-key emms-stream-mode-map "" 'emacsvox-keymap))


(advice-add 'emms-stream-mode :after #'ems--emms-stream-mode-after)





(defun ems--emms-stream-delete-bookmark-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))


(advice-add 'emms-stream-delete-bookmark :after
	    #'ems--emms-stream-delete-bookmark-after)





(defun ems--emms-stream-save-bookmarks-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object) (message "Saved stream bookmarks.")))


(advice-add 'emms-stream-save-bookmarks-file :after
	    #'ems--emms-stream-save-bookmarks-file-after)




(cl-loop for f in
         '(emms-streams emms-stream-quit
                        emms-stream-popup emms-stream-popup-revert
                        )
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-speak-mode-line)))))

(cl-loop for f in
         '(emms-stream-next-line emms-stream-previous-line)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-speak-line)))))

(defun ems--emms-playlist-mode-bury-buffer-after (&rest _)
  "Announce the buffer that becomes current."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))


(advice-add 'emms-playlist-mode-bury-buffer :after
	    #'ems--emms-playlist-mode-bury-buffer-after)




;;;  silence chatter from info


(defun ems--emms-info-really-initialize-track-around
    (orig-fun &rest args)
  "Silence messages."
  (ems-with-messages-silenced (apply orig-fun args)))


(advice-add 'emms-info-really-initialize-track :around
	    #'ems--emms-info-really-initialize-track-around)




;;;  pause/resume if needed

(defun emacsvox-emms-pause-or-resume ()
  "Pause/resume if emms is running. For use  in
emacsvox-silence-hook."
  (cl-declare (special emms-player-playing-p))
  (when (and (boundp 'emms-player-playing-p)
             (not (null emms-player-playing-p)))
    (emms-player-pause)))

(add-hook 'emacsvox-silence-hook 'emacsvox-emms-pause-or-resume)

(provide 'emacsvox-emms)
;;;  end of file

