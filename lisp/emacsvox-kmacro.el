;;; emacsvox-kmacro.el --- Speech-enable KMacros -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for KMACRO 
;; Keywords: Emacsvox, kmacro 
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4241 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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
;;;   Introduction
;; speech-enables kmacro --- a kbd macro interface

;;  required modules

;;; Code:
(require 'emacsvox-preamble)

;;;  bind keys 

(global-set-key [f13] 'kmacro-start-macro-or-insert-counter)
(global-set-key [f14] 'kmacro-end-or-call-macro)

;;;  Advice interactive commands

(defun ems--kmacro-start-macro-before (&rest _)
  "Provide auditory icon."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Defining new kbd macro.")))

(advice-add 'kmacro-start-macro :before
            #'ems--kmacro-start-macro-before)

(defun ems--kmacro-start-macro-or-insert-counter-before (&rest _)
  "Provide auditory icon if new macro is being defined."
  (when
      (and (ems-interactive-p) (not defining-kbd-macro)
           (not executing-kbd-macro))
    (emacsvox-icon 'yank-object) (message "Defining new kbd macro.")))

(advice-add 'kmacro-start-macro-or-insert-counter :before
            #'ems--kmacro-start-macro-or-insert-counter-before)

(defun ems--kmacro-end-or-call-macro-before (&rest _)
  "speak about we are about to do."
  (cond
   ((and (ems-interactive-p) defining-kbd-macro)
    (emacsvox-icon 'close-object)
    (message "Finished defining kbd macro."))
   (t (emacsvox-icon 'open-object) (message "Calling macro."))))

(advice-add 'kmacro-end-or-call-macro :before
            #'ems--kmacro-end-or-call-macro-before)

(defun ems--kmacro-end-or-call-macro-repeat-before (&rest _)
  "speak about we are about to do."
  (cond
   ((and (ems-interactive-p) defining-kbd-macro)
    (message "Finished defining kbd macro."))
   (t (emacsvox-icon 'select-object) (message "Calling macro."))))

(advice-add 'kmacro-end-or-call-macro-repeat :before
            #'ems--kmacro-end-or-call-macro-repeat-before)

(defun ems--kmacro-edit-macro-repeat-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'kmacro-edit-macro-repeat :after
            #'ems--kmacro-edit-macro-repeat-after)

(defun ems--kmacro-call-ring-2nd-repeat-before (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Calling  second macro from ring.")))

(advice-add 'kmacro-call-ring-2nd-repeat :before
            #'ems--kmacro-call-ring-2nd-repeat-before)

(defun ems--kmacro-call-macro-around (orig-fun &rest args)
  "Speech-enabled by emacsvox."
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages nil))
      (apply orig-fun args) result)
    result))

(advice-add 'kmacro-call-macro :around #'ems--kmacro-call-macro-around)

(defun ems--call-last-kbd-macro-around (orig-fun &rest args)
  "Speech-enabled by emacsvox."
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages t)) (apply orig-fun args) result)
    result))

(advice-add 'call-last-kbd-macro :around
            #'ems--call-last-kbd-macro-around)

(provide 'emacsvox-kmacro)
;;;  end of file

