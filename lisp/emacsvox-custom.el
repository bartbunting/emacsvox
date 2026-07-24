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
;; Location https://github.com/robertmeta/emacsvox
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

(defmacro emacsvox-custom--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive Customize TARGET."
  (declare (indent 2))
  (let ((function
         (intern (format "emacsvox--advice-%s-%s"
                         target
                         (substring (symbol-name where) 1)))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback %s `%s'." where target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target ,where #',function
        '((name . ,function))))))

(emacsvox-custom--define-advice Custom-reset-current :after
  (emacsvox-icon 'item)
  (dtk-speak "Reset current"))

(emacsvox-custom--define-advice Custom-reset-saved :after
  (emacsvox-icon 'unmodified-object)
  (dtk-speak "Reset to saved"))

(emacsvox-custom--define-advice Custom-reset-standard :after
  (emacsvox-icon 'delete-object)
  (dtk-speak "Erase customization"))

(emacsvox-custom--define-advice Custom-set :after
  (emacsvox-icon 'button)
  (dtk-speak "Set for current session"))

(defun emacsvox--advice-Custom-save-around
    (original &rest arguments)
  "Call ORIGINAL once and report an interactive Customize save."
  (let ((interactive-p (ems-interactive-p 'Custom-save)))
    (let ((result (apply original arguments)))
      (when interactive-p
        (emacsvox-icon 'save-object)
        (dtk-speak "Set and saved"))
      result)))

(advice-add
 'Custom-save :around
 #'emacsvox--advice-Custom-save-around
 '((name . emacsvox--advice-Custom-save-around)))

(emacsvox-custom--define-advice Custom-buffer-done :after
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(dolist
    (target '(customize-save-customized custom-save-all))
  (eval
   `(emacsvox-custom--define-advice ,target :after
      (emacsvox-icon 'save-object)
      (message "Saved customizations."))))

(defun emacsvox--advice-customize-save-customized-around
    (original &rest arguments)
  "Call ORIGINAL once with speech silenced."
  (let ((dtk-quiet t))
    (apply original arguments)))

(advice-add
 'customize-save-customized :around
 #'emacsvox--advice-customize-save-customized-around
 '((name . emacsvox--advice-customize-save-customized-around)))

(defun emacsvox-custom--advice-customize-after (&rest _)
  "Open and speak the first group after interactive `customize'."
  (when (ems-interactive-p 'customize)
    (emacsvox-icon 'open-object)
    (emacsvox-custom-goto-group)
    (emacsvox-speak-line)))

;; Replace the generic core feedback carrying this same stable name.
(advice-add
 'customize :after
 #'emacsvox-custom--advice-customize-after
 '((name . emacsvox)))

(emacsvox-custom--define-advice customize-group :after
  (emacsvox-icon 'open-object)
  (emacsvox-custom-goto-group)
  (emacsvox-speak-line))

(emacsvox-custom--define-advice customize-browse :after
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defmacro emacsvox-custom--define-option-advice (target)
  "Define direct after advice for option-opening TARGET."
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (symbol &rest _)
         ,(format "Report the option opened by `%s'." target)
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'open-object)
           (search-forward (custom-unlispify-tag-name symbol))
           (forward-line 0)
           (emacsvox-speak-line)))
       (advice-add
        ',target :after #',function
        '((name . ,function))))))

(emacsvox-custom--define-option-advice customize-option)
(emacsvox-custom--define-option-advice customize-variable)

(emacsvox-custom--define-advice customize-apropos :after
  (emacsvox-icon 'open-object)
  (forward-line 0)
  (emacsvox-speak-line))

(emacsvox-custom--define-advice Custom-goto-parent :after
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-custom--define-advice Custom-newline :after
  (emacsvox-icon 'button))

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
