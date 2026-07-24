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
;; Location https://github.com/robertmeta/emacsvox
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
(require 'calculator)

;;; Commentary:

;; Speech enable desktop calculator 

;;; Code:

;;;   helpers 

(defun emacsvox-calculator-summarize ()
  "Summarize state of the calculator"
  (emacsvox-speak-line))

;;;   advice interactive commands 

(defun emacsvox--advice-calculator-around (orig-fun &rest args)
  "Fix while waiting for a bug-fix in Emacs."
  (if (ems-interactive-p 'calculator)
      (let ((header-line-format nil))
        (apply orig-fun args))
    (apply orig-fun args)))

(advice-add
 'calculator :around #'emacsvox--advice-calculator-around
 '((name . emacsvox--advice-calculator-around)))

(defmacro emacsvox-calculator--define-after-advice (target &rest body)
  "Define direct after advice for interactive Calculator TARGET using BODY."
  (declare (indent 1))
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback after `%s'." target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target :after #',function
        '((name . ,function))))))

(emacsvox-calculator--define-after-advice calculator
  (emacsvox-icon 'open-object)
  (message "Welcome to the pocket calculator."))

(defmacro emacsvox-calculator--define-insertion-advice (target)
  "Define direct around advice that speaks text inserted by TARGET."
  (let ((function
         (intern (format "emacsvox--advice-%s-around" target))))
    `(progn
       (defun ,function (orig-fun &rest args)
         ,(format "Speak text inserted by `%s'." target)
         (if (ems-interactive-p ',target)
             (let ((start (point)))
               (prog1
                   (apply orig-fun args)
                 (emacsvox-speak-region start (point))))
           (apply orig-fun args)))
       (advice-add
        ',target :around #',function
        '((name . ,function))))))

(dolist
    (target
     '(calculator-digit
       calculator-exp
       calculator-op-or-exp
       calculator-open-paren
       calculator-close-paren))
  (eval `(emacsvox-calculator--define-insertion-advice ,target)))

(defmacro emacsvox-calculator--define-selection-advice (target)
  "Define direct around advice that summarizes selection by TARGET."
  (let ((function
         (intern (format "emacsvox--advice-%s-around" target))))
    `(progn
       (defun ,function (orig-fun &rest args)
         ,(format "Summarize the calculator after `%s'." target)
         (if (ems-interactive-p ',target)
             (prog1
                 (apply orig-fun args)
               (emacsvox-icon 'select-object)
               (emacsvox-calculator-summarize))
           (apply orig-fun args)))
       (advice-add
        ',target :around #',function
        '((name . ,function))))))

(dolist
    (target
     '(calculator-op
       calculator-saved-up
       calculator-saved-down))
  (eval `(emacsvox-calculator--define-selection-advice ,target)))

(dolist
    (spec
     '((calculator-save-on-list save-object)
       (calculator-clear-saved delete-object)
       (calculator-enter select-object)
       (calculator-clear delete-object)
       (calculator-get-register yank-object)))
  (eval
   `(emacsvox-calculator--define-after-advice ,(car spec)
      (emacsvox-icon ',(cadr spec))
      (emacsvox-calculator-summarize))))

(defun emacsvox--advice-calculator-backspace-around (orig-fun &rest args)
  "Speak character you're deleting."
  (when (ems-interactive-p 'calculator-backspace)
    (dtk-tone 500 100 'force)
    (emacsvox-speak-this-char (preceding-char)))
  (apply orig-fun args))

(advice-add
 'calculator-backspace :around
 #'emacsvox--advice-calculator-backspace-around
 '((name . emacsvox--advice-calculator-backspace-around)))

(emacsvox-calculator--define-after-advice calculator-copy
  (emacsvox-icon 'delete-object)
  (emacsvox-speak-current-kill 1))

(emacsvox-calculator--define-after-advice calculator-paste
  (emacsvox-icon 'yank-object))

(dolist (target '(calculator-quit calculator-save-and-quit))
  (eval
   `(emacsvox-calculator--define-after-advice ,target
      (emacsvox-icon 'close-object)
      (emacsvox-speak-mode-line))))

(defun emacsvox--advice-calculator-update-display-after (&rest _)
  "Speak the updated  display. " (emacsvox-speak-line))

(advice-add
 'calculator-update-display :after
 #'emacsvox--advice-calculator-update-display-after
 '((name . emacsvox--advice-calculator-update-display-after)))

;;;   keys 
(cl-declaim (special calculator-mode-map))
(when (boundp 'calculator-mode-map)
  (define-key calculator-mode-map "k" 'calculator-copy)
  (define-key calculator-mode-map "p" 'calculator-paste)
  (define-key calculator-mode-map "\d" 'calculator-backspace)
  )

(provide 'emacsvox-calculator)
;;;  end of file
