;;; emacsvox-pipewire.el --- Speech-enable PIPEWIRE -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable PIPEWIRE An Emacs Interface to pipewire
;;; Keywords: Emacsvox,  Audio Desktop pipewire
;;  LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

;;  Copyright:

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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;  introduction

;;; Commentary:
;; PIPEWIRE ==  Pipewire Interaction from Emacs.

;;; Code:

;;  Required modules: 

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'pipewire "pipewire" 'no-error )

;;; Map Faces:

(voice-setup-add-map 
 '(
   (pipewire-default-object voice-smoothen)
   (pipewire-label voice-lighten)
   (pipewire-muted voice-brighten)
   (pipewire-volume voice-bolden)))

;;; Interactive Commands:

(defun emacsvox--advice-pipewire-after (&rest _)
  "speak."
  (when (ems-interactive-p 'pipewire)
    (emacsvox-toggle-audio-indentation) (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-pipewire--control-targets
  '(pipewire-decrease-volume pipewire-decrease-volume-single
    pipewire-set-volume pipewire-set-profile
    pipewire-increase-volume pipewire-increase-volume-single)
  "Current Pipewire controls that receive native advice.")

(dolist (target emacsvox-pipewire--control-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Provide speech feedback after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-speak-line)
          (emacsvox-icon 'button))))))

(defconst emacsvox-pipewire--advice
  (cons
   '(pipewire :after emacsvox--advice-pipewire-after)
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    emacsvox-pipewire--control-targets))
  "Current Pipewire targets and their native advice functions.")

(defun emacsvox-pipewire--install-advice ()
  "Install native advice after Pipewire loads."
  (dolist (entry emacsvox-pipewire--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'pipewire
  (emacsvox-pipewire--install-advice))

(provide 'emacsvox-pipewire)
;; end of file
