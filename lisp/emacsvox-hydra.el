;;; emacsvox-hydra.el --- Speech-Enable hydra  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable hydra
;; Keywords: Emacsvox,  Audio Desktop hydra
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Speech-enable package hydra:
;; For  uses of hydra see module @xref{emacsvox-muggles}.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'hydra "hydra" 'no-error)

;;;  Map Hydra Colors To Voices:

(voice-setup-add-map
 '(
   (hydra-face-red voice-bolden)
   (hydra-face-blue voice-lighten)
   (hydra-face-amaranth voice-animate)
   (hydra-face-pink voice-bolden-medium)
   (hydra-face-teal voice-lighten-medium)))

;;;  Toggle Talkative:
(defun emacsvox-hydra-toggle-talkative ()
  "Toggle hydra-is-helpful"
  (interactive)
  (cl-declare (special hydra-is-helpful))
  (setq hydra-is-helpful (not hydra-is-helpful))
  (emacsvox-icon (if hydra-is-helpful 'on 'off)))

;;;  Emacsvox Helpers:
(defun emacsvox-hydra-body-pre (&optional name)
  "Provide auditory icon"
  (when name (dtk-speak name))
  (emacsvox-icon 'open-object))
(defun emacsvox-hydra-pre ()
  "Provide auditory icon"
  (emacsvox-icon 'progress))
(defun emacsvox-hydra-post ()
  "Provide auditory icon. "
  (dtk-stop 'all)
  (when emacsvox-use-icons
    (emacsvox-icon 'close-object)))

;;;  Setup Help And Hint 

;; We use plain messages:

(when (featurep 'emacsvox)
  (setq
   hydra-head-format "%s "
   hydra-hint-display-type nil
   hydra-hint-display-type #'message))
(defun emacsvox-hydra-self-help (name)
  "Speak hint for specified Hydra."
  (message (eval (symbol-value (intern (format "%s/hint" name))))))

;;; lv-message:

(defvar ems--lv-cache nil
  "Emacsvox's private cache of the last lv message.")

(voice-setup-set-voice-for-face 'lv-separator  'inaudible)


(defun ems--lv-message-after (&rest _)
  "speak." (cl-declare (special ems--lv-cache)) (emacsvox-icon 'help)
  (with-current-buffer (window-buffer (lv-window))
    (setq ems--lv-cache (buffer-substring (point-min) (point-max)))
    (emacsvox-speak-buffer)))


(advice-add 'lv-message :after #'ems--lv-message-after)





(defun ems--lv-delete-window-after (&rest _)
  "speak." (dtk-stop 'all) (emacsvox-icon 'delete-object))


(advice-add 'lv-delete-window :after #'ems--lv-delete-window-after)




(provide 'emacsvox-hydra)
;;;  end of file

