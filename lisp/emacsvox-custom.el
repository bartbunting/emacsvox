;;; emacsvox-custom.el --- Speech enable custom  -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to custom
;; Keywords: Emacsvox, Speak, Spoken Output, custom
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;;   Required modules:

(require 'emacsvox-preamble)
(require 'cus-edit)

;;;   Introduction
;;; Commentary:
;; Advise custom to speak.
;; most of the work is actually done by emacsvox-widget.el
;; which speech-enables the widget libraries.
;;; Code:

;;;  advice

(defun ems--Custom-reset-current-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'item) (dtk-speak "Reset current")))

(advice-add 'Custom-reset-current :after
            #'ems--Custom-reset-current-after)

(defun ems--Custom-reset-saved-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'unmodified-object) (dtk-speak "Reset to saved")))

(advice-add 'Custom-reset-saved :after #'ems--Custom-reset-saved-after)

(defun ems--Custom-reset-standard-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (dtk-speak "Erase customization")))

(advice-add 'Custom-reset-standard :after
            #'ems--Custom-reset-standard-after)

(defun ems--Custom-set-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (dtk-speak "Set for current session")))

(advice-add 'Custom-set :after #'ems--Custom-set-after)

(defun ems--Custom-save-around (orig-fun &rest args)
  "Silence messages and produce auditory feedback."
  (let ((result (apply orig-fun args)))
    (apply orig-fun args)
    (when (ems-interactive-p)
      (emacsvox-icon 'save-object) (dtk-speak "Set and saved"))
    result))

(advice-add 'Custom-save :around #'ems--Custom-save-around)

(defun ems--Custom-buffer-done-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'Custom-buffer-done :after #'ems--Custom-buffer-done-after)

(defun ems--customize-save-customized-after (&rest _)
  "speak. "
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object) (message "Saved customizations.")))

(advice-add 'customize-save-customized :after
            #'ems--customize-save-customized-after)

(defun ems--custom-save-all-after (&rest _)
  "speak. "
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object) (message "Saved customizations.")))

(advice-add 'custom-save-all :after #'ems--custom-save-all-after)

(defun ems--customize-save-customized-around (orig-fun &rest args)
  "Silence speech." (let ((dtk-quiet t)) (apply orig-fun args)))

(advice-add 'customize-save-customized :around
            #'ems--customize-save-customized-around)

(defun ems--custom-set-after (&rest _)
  "speak. "
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (message "Set all updates.")))

(advice-add 'custom-set :after #'ems--custom-set-after)

(defun ems--customize-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-custom-goto-group)
    (emacsvox-speak-line)))

(advice-add 'customize :after #'ems--customize-after)

(defun ems--customize-group-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-custom-goto-group)
    (emacsvox-speak-line)))

(advice-add 'customize-group :after #'ems--customize-group-after)

(defun ems--customize-browse-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'customize-browse :after #'ems--customize-browse-after)

(defun ems--customize-option-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (let ((symbol (ad-get-arg 0)))
      (emacsvox-icon 'open-object)
      (search-forward (custom-unlispify-tag-name symbol))
      (forward-line 0) (emacsvox-speak-line))))

(advice-add 'customize-option :after #'ems--customize-option-after)

(defun ems--customize-apropos-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (forward-line 0)
    (emacsvox-speak-line)))

(advice-add 'customize-apropos :after #'ems--customize-apropos-after)

(defun ems--customize-variable-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (let ((symbol (ad-get-arg 0)))
      (emacsvox-icon 'open-object)
      (search-forward (custom-unlispify-tag-name symbol))
      (forward-line 0) (emacsvox-speak-line))))

(advice-add 'customize-variable :after #'ems--customize-variable-after)

(defun ems--Custom-goto-parent-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Custom-goto-parent :after #'ems--Custom-goto-parent-after)

(defun ems--Custom-newline-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'Custom-newline :after #'ems--Custom-newline-after)

;;;  custom hook

(add-hook 'Custom-mode-hook
          
          #'(lambda nil
              (emacsvox-pronounce-refresh-pronunciations)))

;;;  define voices
(voice-setup-add-map
 '(
   (custom-variable-obsolete voice-monotone-extra)
   (custom-group-subtitle  voice-smoothen)
   (custom-themed voice-brighten)
   (custom-visibility voice-annotate)
   (custom-button voice-bolden)
   (custom-button-pressed voice-bolden-extra)
   (custom-button-pressed-unraised voice-bolden-extra)
   (custom-button-mouse voice-bolden-medium)
   (custom-button-unraised voice-smoothen)
   (custom-changed voice-smoothen)
   (custom-comment voice-monotone-medium)
   (custom-comment-tag voice-monotone-extra)
   (custom-documentation voice-brighten-medium)
   (custom-face-tag voice-lighten)
   (custom-group-tag voice-bolden)
   (custom-group-tag-1 voice-lighten-medium)
   (custom-invalid voice-animate-extra)
   (custom-link voice-bolden)
   (custom-modified voice-lighten-medium)
   (custom-rogue voice-bolden-and-animate)
   (custom-modified voice-lighten-medium)
   (custom-saved voice-smoothen-extra)
   (custom-set voice-smoothen-medium)
   (custom-state voice-smoothen)
   (custom-variable-button voice-animate)
   (custom-variable-tag voice-bolden-medium)))

;;;   custom navigation

(defvar emacsvox-custom-group-regexp
  "^/-"
  "Pattern identifying start of custom group.")

(defun emacsvox-custom-goto-group ()
  "Jump to custom group when in a customization buffer."
  (interactive)
  
  (when (eq major-mode 'custom-mode)
    (goto-char (point-min))
    (re-search-forward emacsvox-custom-group-regexp
                       nil t)
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(defvar emacsvox-custom-toolbar-regexp
  "^Operate on everything in this buffer:"
  "Pattern that identifies toolbar section.")

(defun emacsvox-custom-goto-toolbar ()
  "Jump to custom toolbar when in a customization buffer."
  (interactive)
  
  (when (eq major-mode 'custom-mode)
    (goto-char (point-min))
    (re-search-forward emacsvox-custom-toolbar-regexp nil
                       t)
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

;;;   bind emacsvox commands 

(cl-declaim (special custom-mode-map))
(define-key custom-mode-map "E" 'Custom-reset-standard)
(define-key custom-mode-map "r" 'Custom-reset-current)
(define-key custom-mode-map "R" 'Custom-reset-saved)
(define-key custom-mode-map "s" 'Custom-set)
(define-key  custom-mode-map "S" 'Custom-save)

(define-key custom-mode-map "," 'backward-paragraph)
(define-key custom-mode-map "." 'forward-paragraph)
(define-key custom-mode-map  "\M-t" 'emacsvox-custom-goto-toolbar)
(define-key custom-mode-map  "\M-g"
            'emacsvox-custom-goto-group)

;;;  augment custom widgets

(provide 'emacsvox-custom)
;;;  end of file 

