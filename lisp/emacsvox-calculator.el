;;; emacsvox-calculator.el --- Extend calculator -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable desktop calculator
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

;;  required modules

(require 'emacsvox-preamble)

;;; Commentary:

;; Speech enable desktop calculator 

;;; Code:

;;;   helpers 

(defun emacsvox-calculator-summarize ()
  "Summarize state of the calculator"
  (emacsvox-speak-line))

;;;   advice interactive commands 

(defun ems--calculator-around (orig-fun &rest args)
  "Fix while waiting for a bug-fix in Emacs."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((header-line-format nil)) (apply orig-fun args)))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator :around #'ems--calculator-around)

(defun ems--calculator-after (&rest _)
  "Speech enable calculator."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Welcome to the pocket calculator.")))

(advice-add 'calculator :after #'ems--calculator-after)

(defun ems--calculator-digit-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args) (emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-digit :around #'ems--calculator-digit-around)

(defun ems--calculator-exp-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args) (emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-exp :around #'ems--calculator-exp-around)

(defun ems--calculator-op-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (apply orig-fun args)
      (emacsvox-icon 'select-object) (emacsvox-calculator-summarize))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-op :around #'ems--calculator-op-around)

(defun ems--calculator-op-or-exp-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args) (emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-op-or-exp :around
            #'ems--calculator-op-or-exp-around)

(defun ems--calculator-open-paren-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args) (emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-open-paren :around
            #'ems--calculator-open-paren-around)

(defun ems--calculator-close-paren-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args) (emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-close-paren :around
            #'ems--calculator-close-paren-around)

(defun ems--calculator-saved-up-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (apply orig-fun args)
      (emacsvox-icon 'select-object) (emacsvox-calculator-summarize))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-saved-up :around
            #'ems--calculator-saved-up-around)

(defun ems--calculator-saved-down-around (orig-fun &rest args)
  "Speak the digit."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (apply orig-fun args)
      (emacsvox-icon 'select-object) (emacsvox-calculator-summarize))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-saved-down :around
            #'ems--calculator-saved-down-around)

(defun ems--calculator-save-on-list-after (&rest _)
  "Provide speech feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object) (emacsvox-calculator-summarize)))

(advice-add 'calculator-save-on-list :after
            #'ems--calculator-save-on-list-after)

(defun ems--calculator-clear-saved-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-calculator-summarize)))

(advice-add 'calculator-clear-saved :after
            #'ems--calculator-clear-saved-after)

(defun ems--calculator-enter-after (&rest _)
  "Provide speech feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-calculator-summarize)))

(advice-add 'calculator-enter :after #'ems--calculator-enter-after)

(defun ems--calculator-backspace-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacsvox-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'calculator-backspace :around
            #'ems--calculator-backspace-around)

(defun ems--calculator-clear-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-calculator-summarize)))

(advice-add 'calculator-clear :after #'ems--calculator-clear-after)

(defun ems--calculator-copy-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-current-kill 1)))

(advice-add 'calculator-copy :after #'ems--calculator-copy-after)

(defun ems--calculator-paste-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'yank-object)))

(advice-add 'calculator-paste :after #'ems--calculator-paste-after)

(defun ems--calculator-get-register-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-calculator-summarize)))

(advice-add 'calculator-get-register :after
            #'ems--calculator-get-register-after)

(defun ems--calculator-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'calculator-quit :after #'ems--calculator-quit-after)

(defun ems--calculator-save-and-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'calculator-save-and-quit :after
            #'ems--calculator-save-and-quit-after)

(defun ems--calculator-update-display-after (&rest _)
  "Speak the updated  display. " (emacsvox-speak-line))

(advice-add 'calculator-update-display :after
            #'ems--calculator-update-display-after)

;;;   keys 
(cl-declaim (special calculator-mode-map))
(when (boundp 'calculator-mode-map)
  (define-key calculator-mode-map "k" 'calculator-copy)
  (define-key calculator-mode-map "p" 'calculator-paste)
  (define-key calculator-mode-map "\d" 'calculator-backspace)
  )

(provide 'emacsvox-calculator)
;;;  end of file

