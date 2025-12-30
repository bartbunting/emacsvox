;;; emacsvox-re-builder.el --- re-builder  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable re-builder
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;; Speech-enable re-builder.
;; Will be used to advantage in efficiently setting up outline
;; regexp wizards


;;  required modules
;;; Code:

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Map faces to personalities 
(voice-setup-add-map
 '(
   (reb-match-0 voice-overlay-0)
   (reb-match-1 voice-overlay-1)
   (reb-match-2 voice-overlay-2)
   (reb-match-3 voice-overlay-3)))

;;;  Speech-enable interactive commands.


(defun ems--re-builder-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))


(advice-add 're-builder :after #'ems--re-builder-after)





(defun ems--reb-quit-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))


(advice-add 'reb-quit :after #'ems--reb-quit-after)





(defun ems--reb-next-match-after (&rest _)
  "Speak matched line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (save-excursion
	(set-buffer reb-target-buffer) (emacsvox-speak-line)
	(emacsvox-icon 'large-movement)))))


(advice-add 'reb-next-match :after #'ems--reb-next-match-after)





(defun ems--reb-prev-match-after (&rest _)
  "Speak matched line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (save-excursion
	(set-buffer reb-target-buffer) (emacsvox-speak-line)
	(emacsvox-icon 'large-movement)))))


(advice-add 'reb-prev-match :after #'ems--reb-prev-match-after)





(defun ems--reb-toggle-case-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (save-excursion
      (set-buffer reb-target-buffer)
      (emacsvox-icon (if case-fold-search 'on 'off)))))


(advice-add 'reb-toggle-case :after #'ems--reb-toggle-case-after)





(defun ems--reb-copy-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'yank-object)))


(advice-add 'reb-copy :after #'ems--reb-copy-after)





(defun ems--reb-enter-subexp-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'open-object)))


(advice-add 'reb-enter-subexp-mode :after
	    #'ems--reb-enter-subexp-mode-after)





(defun ems--reb-quit-subexp-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))


(advice-add 'reb-quit-subexp-mode :after
	    #'ems--reb-quit-subexp-mode-after)





(defun ems--reb-auto-update-after (&rest _)
  "Speak after update is done."
  (when (buffer-live-p reb-target-buffer)
    (with-current-buffer reb-target-buffer
      (with-silent-modifications
	(mapc #'(lambda (o) (overlay-put o 'auditory-icon 'item))
	      reb-overlays))))
  (emacsvox-speak-message-again))


(advice-add 'reb-auto-update :after #'ems--reb-auto-update-after)




(provide 'emacsvox-re-builder)
;;;  end of file

