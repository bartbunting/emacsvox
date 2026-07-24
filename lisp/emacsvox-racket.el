;;; emacsvox-racket.el --- Speech-enable RACKET  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable RACKET An Emacs IDE for  racket
;; Keywords: Emacsvox,  Audio Desktop racket IDE
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
;; MERCHANTABILITY or FITNRACKET FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; racket-mode implements an IDE for racket, a dialect of scheme.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (racket-check-syntax-def-face voice-bolden)
   (racket-check-syntax-use-face  voice-annotate)
   (racket-here-string-face voice-lighten)
   (racket-keyword-argument-face voice-animate-extra)
   (racket-paren-face voice-smoothen)
   (racket-selfeval-face voice-bolden-and-animate)))

;;;  Interactive Commands:

(defvar emacsvox-racket--advice nil
  "Current Racket mode targets and their native advice functions.")
(setq emacsvox-racket--advice nil)

(defun emacsvox-racket--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-racket--advice))))

(defun emacsvox-racket--selection-feedback ()
  "Speak a selection in Racket's open-require-path UI."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-racket--register-after-group
 '(racket--orp/enter racket--orp/next racket--orp/prev racket--orp/quit)
 #'emacsvox-racket--selection-feedback)

(defun emacsvox-racket--profile-feedback ()
  "Speak an updated Racket profile view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-racket--register-after-group
 '(racket-profile-refresh racket-profile-show-zero racket-profile-visit)
 #'emacsvox-racket--profile-feedback)

(defun emacsvox-racket--movement-feedback ()
  "Speak after moving through Racket source."
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))

(emacsvox-racket--register-after-group
 '(racket-visit-module racket-visit-definition
   racket-smart-open-bracket racket-insert-lambda racket-insert-closing
   racket-indent-line racket-xp-next-definition racket-xp-previous-definition
   racket-xp-next-use racket-xp-previous-use racket-backward-up-list)
 #'emacsvox-racket--movement-feedback)

(defun emacsvox--advice-racket-describe-after (&rest _)
  "speak."
  (when (ems-interactive-p 'racket-describe)
    (emacsvox-icon 'help)
    (with-current-buffer "*Racket Describe*" (emacsvox-speak-buffer))))

(push '(racket-describe :after emacsvox--advice-racket-describe-after)
      emacsvox-racket--advice)

(defun emacsvox-racket--install-advice ()
  "Install advice for Racket mode features loaded so far."
  (dolist (entry emacsvox-racket--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(racket-mode racket-collection racket-profile
                   racket-xp))
  (eval `(with-eval-after-load ',feature
           (emacsvox-racket--install-advice))))

(provide 'emacsvox-racket)
;;;  end of file
