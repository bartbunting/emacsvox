;;; emacsvox-ivy.el --- Speech-enable IVY  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable IVY An Emacs Interface to ivy
;; Keywords: Emacsvox,  Audio Desktop ivy
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
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
;; MERCHANTABILITY or FITNIVY FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; IVY ==  One More Smart Completion Technique 
;; Speech-enable ivy-style completion.
;; This is still experimental and preliminary.
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (ivy-action voice-animate)
   (ivy-confirm-face voice-bolden)
   (ivy-current-match voice-lighten)
   (ivy-cursor voice-smoothen)
   (ivy-match-required-face voice-bolden-extra)
   (ivy-minibuffer-match-face-1 voice-monotone-extra)
   (ivy-minibuffer-match-face-2 voice-monotone-medium)
   (ivy-minibuffer-match-face-3 voice-monotone-medium)
   (ivy-minibuffer-match-face-4 voice-monotone-extra)
   (ivy-modified-buffer voice-bolden-and-animate)
   (ivy-remote voice-lighten)
   (ivy-subdir voice-smoothen)
   (ivy-virtual voice-animate)))

;;;  Interactive Commands:

(defconst emacsvox-ivy--switch-targets
  '(ivy-switch-buffer-other-window ivy-switch-buffer)
  "Ivy commands that switch buffers.")

(cl-loop
 for target in emacsvox-ivy--switch-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (with-current-buffer (window-buffer (selected-window))
         (emacsvox-speak-mode-line))))))

(defconst emacsvox-ivy--done-targets
  '(ivy-done ivy-alt-done ivy-immediate-done)
  "Ivy commands that finish completion.")

(cl-loop
 for target in emacsvox-ivy--done-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'close-object)))))

(defun emacsvox-ivy-speak-selection ()
  "Speak current ivy selection."
  
  (tts-speak
   (format
    "%d: %s"
    ivy--length
    (elt ivy--old-cands ivy--index))))

(defconst emacsvox-ivy--navigation-targets
  '(ivy-beginning-of-buffer
    ivy-end-of-buffer
    ivy-next-line
    ivy-previous-line)
  "Ivy commands that move through candidates.")

(cl-loop
 for target in emacsvox-ivy--navigation-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak selection."
     (when (ems-interactive-p ',target)
       (emacsvox-ivy-speak-selection)
       (emacsvox-icon 'select-object)))))

(defun emacsvox--advice-ivy--exhibit-after (&rest _)
  "Speak updated Ivy list." (emacsvox-ivy-speak-selection)
  (sit-for 5) (emacsvox-speak-rest-of-buffer))

(defun emacsvox--advice-ivy-read-before (prompt &rest _)
  "Speak prompt" (emacsvox-icon 'open-object)
  (tts-speak prompt))

(defconst emacsvox-ivy--advice
  (append
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    (append
     emacsvox-ivy--switch-targets
     emacsvox-ivy--done-targets
     emacsvox-ivy--navigation-targets))
   '((ivy--exhibit :after emacsvox--advice-ivy--exhibit-after)
     (ivy-read :before emacsvox--advice-ivy-read-before)))
  "Current Ivy targets and their native advice functions.")

(defun emacsvox-ivy--install-advice ()
  "Install advice after the optional Ivy package loads."
  (dolist (entry emacsvox-ivy--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'ivy
  (emacsvox-ivy--install-advice))

(provide 'emacsvox-ivy)
;;;  end of file
