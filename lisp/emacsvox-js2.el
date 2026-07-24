;;; emacsvox-js2.el --- Speech-enable JS2  -*- lexical-binding: t; -*-
;;
;; $Author: raman $
;; Description:  Speech-enable JS2 An Emacs Interface to js2
;; Keywords: Emacsvox,  Audio Desktop js2
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 1.1 $ |
;; Location https://github.com/robertmeta/emacsvox
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
;; MERCHANTABILITY or FITNJS2 FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; JS2-mode http://js2-mode.googlecode.com/svn/trunk
;; is a new, powerful Emacs mode for working with JavaScript.
;; This module speech-enables js2.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;   map faces to voices:

(voice-setup-add-map
 '(
   (js2-function-call  voice-annotate)
   (js2-object-property  voice-smoothen)
   (js2-object-property-access voice-lighten)
   (js2-error voice-bolden-extra)
   (js2-external-variable voice-animate) 
   (js2-function-param voice-lighten-extra)
   (js2-instance-member voice-lighten-medium)
   (js2-jsdoc-html-tag-delimiter voice-smoothen)
   (js2-jsdoc-html-tag-name voice-bolden-medium)
   (js2-jsdoc-tag voice-bolden-medium)
   (js2-jsdoc-type voice-smoothen-medium)
   (js2-jsdoc-value voice-lighten-medium)
   (js2-magic-paren voice-lighten)
   (js2-private-function-call voice-smoothen-extra)
   (js2-private-member voice-lighten-extra)
   (js2-warning voice-bolden-and-animate)
   ))

;;;  Advice new interactive commands:

(defvar emacsvox-js2--advice nil
  "Current JS2 targets and their native advice functions.")
(setq emacsvox-js2--advice nil)

(defun emacsvox-js2--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback ',target))))
      (push (list target :after advice-function) emacsvox-js2--advice))))

(defun emacsvox-js2--movement-feedback (_target)
  "Speak after moving through JavaScript source."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(emacsvox-js2--register-after-group
 '(js2-jump-to-definition js2-mode-forward-sexp
   js2-mode-backward-sibling js2-next-error)
 #'emacsvox-js2--movement-feedback)

(defun emacsvox-js2--mark-feedback (_target)
  "Speak the marked JavaScript definition."
  (emacsvox-icon 'mark-object)
  (emacsvox-speak-line))

(emacsvox-js2--register-after-group
 '(js2-mark-defun)
 #'emacsvox-js2--mark-feedback)

(defun emacsvox-js2--line-feedback (_target)
  "Speak the current JavaScript line."
  (emacsvox-speak-line))

(emacsvox-js2--register-after-group
 '(js2-beginning-of-line js2-indent-line js2-forward-sws
   js2-backward-sws js2-end-of-line)
 #'emacsvox-js2--line-feedback)

(defun emacsvox-js2--hide-feedback (target)
  "Announce the item hidden by JS2 command TARGET."
  (emacsvox-icon 'close-object)
  (message "Hid %s"
           (substring (symbol-name target) (length "js2-mode-hide-"))))

(emacsvox-js2--register-after-group
 '(js2-mode-hide-comments js2-mode-hide-element
   js2-mode-hide-functions js2-mode-hide-warnings-and-errors)
 #'emacsvox-js2--hide-feedback)

(defun emacsvox-js2--show-feedback (target)
  "Announce the item shown by JS2 command TARGET."
  (emacsvox-icon 'open-object)
  (message "Showed %s"
           (substring (symbol-name target) (length "js2-mode-show-"))))

(emacsvox-js2--register-after-group
 '(js2-mode-show-all js2-mode-show-comments
   js2-mode-show-element js2-mode-show-functions)
 #'emacsvox-js2--show-feedback)

(defun emacsvox-js2--toggle-feedback (target)
  "Announce the item toggled by JS2 command TARGET."
  (emacsvox-icon 'button)
  (message "Toggled %s"
           (substring (symbol-name target) (length "js2-mode-toggle-"))))

(emacsvox-js2--register-after-group
 '(js2-mode-toggle-warnings-and-errors js2-mode-toggle-hide-functions
   js2-mode-toggle-hide-comments js2-mode-toggle-element)
 #'emacsvox-js2--toggle-feedback)

(defun emacsvox--advice-js2-narrow-to-defun-after (&rest _)
  "speak."
  (when (ems-interactive-p 'js2-narrow-to-defun)
    (emacsvox-icon 'mark-object)
    (message "Narrowed to current function.")))

(push '(js2-narrow-to-defun :after
        emacsvox--advice-js2-narrow-to-defun-after)
      emacsvox-js2--advice)

(defun emacsvox-js2--install-advice ()
  "Install native advice after JS2 mode loads."
  (dolist (entry emacsvox-js2--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'js2-mode
  (emacsvox-js2--install-advice))

;;;  js2-mode hook

(defun emacsvox-js2-hook ()
  "Hook to setup emacsvox."
  
  (define-key js2-mode-map "\C-e" 'emacsvox-keymap)
  (define-key js2-mode-map "\C-ee" 'js2-end-of-line)
  (when (locate-library "js2-imenu-extras")
    (require 'js2-imenu-extras)
    (js2-imenu-extras-setup)))

(add-hook 'js2-mode-hook 'emacsvox-js2-hook)

(provide 'emacsvox-js2)
;;;  end of file
