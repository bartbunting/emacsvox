;;; emacsvox-popup.el --- Speech-enable POPUP  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable POPUP An Emacs Interface to popup
;; Keywords: Emacsvox,  Audio Desktop popup
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
;; MERCHANTABILITY or FITNPOPUP FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; POPUP ==  popup.el from MELPA

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'popup "popup" 'no-error)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (popup-face voice-bolden)
   (popup-isearch-match voice-animate)
   (popup-menu-face voice-monotone-extra)
   (popup-menu-mouse-face voice-monotone-extra)
   (popup-menu-selection-face voice-lighten)
   (popup-menu-summary-face voice-smoothen)
   (popup-summary-face voice-smoothen)
   (popup-tip-face voice-lighten)))

;;;  Interactive Commands:

(defun emacsvox-popup-speak-item (popup)
  "Speak current item."
  (let ((msg (elt (popup-list popup) (popup-cursor popup))))
    (message msg)))

(defun emacsvox--advice-popup-menu-event-loop-around
    (orig-fun menu &rest args)
  "Speak MENU around ORIG-FUN while preserving its return value."
  (emacsvox-icon 'open-object)
  (emacsvox-popup-speak-item menu)
  (unwind-protect
      (apply orig-fun menu args)
    (emacsvox-icon 'close-object)))

(defun emacsvox--advice-popup-menu-read-key-sequence-before
    (_keymap &optional prompt _timeout)
  "Speak our prompt."
  (when (sit-for 2) (dtk-speak (or prompt "Menu:"))))

(defun emacsvox-popup--register-movement-group (targets icon)
  "Define native after advice for TARGETS using ICON."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (popup &rest _)
          ,(format "Speak the Popup item selected by `%s'." target)
          (emacsvox-icon ',icon)
          (emacsvox-popup-speak-item popup))))))

(defconst emacsvox-popup--selection-targets
  '(popup-next popup-previous)
  "Popup commands that select an adjacent item.")

(defconst emacsvox-popup--page-targets
  '(popup-page-next popup-page-previous)
  "Popup commands that select another page.")

(emacsvox-popup--register-movement-group
 emacsvox-popup--selection-targets 'select-object)
(emacsvox-popup--register-movement-group
 emacsvox-popup--page-targets 'scroll)

(defun emacsvox--advice-popup-menu-show-help-after
    (menu &optional _persist item)
  "Speak help if available."
  (let ((doc (popup-menu-documentation menu item)))
    (emacsvox-icon 'help)
    (if doc (dtk-speak doc) (dtk-speak "helpless"))))

(defconst emacsvox-popup--advice
  (append
   '((popup-menu-event-loop :around
      emacsvox--advice-popup-menu-event-loop-around)
     (popup-menu-read-key-sequence :before
      emacsvox--advice-popup-menu-read-key-sequence-before)
     (popup-menu-show-help :after
      emacsvox--advice-popup-menu-show-help-after))
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    (append emacsvox-popup--selection-targets
            emacsvox-popup--page-targets)))
  "Current Popup targets and their native advice functions.")

(defun emacsvox-popup--install-advice ()
  "Install native advice after Popup loads."
  (dolist (entry emacsvox-popup--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'popup
  (emacsvox-popup--install-advice))

;;;  Augment popup keymap:

(eval-after-load
    "popup"
  `(define-key popup-menu-keymap   emacsvox-prefix 'emacsvox-keymap))

(provide 'emacsvox-popup)
;;;  end of file
