;;; emacsvox-hydra.el --- Speech-Enable hydra  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable hydra
;; Keywords: Emacsvox,  Audio Desktop hydra
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; Location https://github.com/robertmeta/emacsvox
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
  
  (setq hydra-is-helpful (not hydra-is-helpful))
  (emacsvox-icon (if hydra-is-helpful 'on 'off)))

;;;  Emacsvox Helpers:
(defun emacsvox-hydra-body-pre (&optional name)
  "Provide auditory icon"
  (when name (tts-speak name))
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

(defvar emacsvox-hydra--lv-cache nil
  "Emacsvox's private cache of the last lv message.")

(voice-setup-set-voice-for-face 'lv-separator  'inaudible)

(defun emacsvox--advice-lv-message-after (&rest _)
  "speak."  (emacsvox-icon 'help)
  (with-current-buffer (window-buffer (lv-window))
    (setq emacsvox-hydra--lv-cache
          (buffer-substring (point-min) (point-max)))
    (emacsvox-speak-buffer)))

(defun emacsvox--advice-lv-delete-window-after (&rest _)
  "speak." (dtk-stop 'all) (emacsvox-icon 'delete-object))

(defconst emacsvox-hydra--advice
  '((lv-message :after emacsvox--advice-lv-message-after)
    (lv-delete-window :after emacsvox--advice-lv-delete-window-after))
  "LV targets and their native advice functions.")

(defun emacsvox-hydra--install-advice ()
  "Install advice after Hydra's optional LV dependency loads."
  (dolist (entry emacsvox-hydra--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'lv
  (emacsvox-hydra--install-advice))

(provide 'emacsvox-hydra)
;;;  end of file
