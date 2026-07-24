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
;; Location https://github.com/robertmeta/emacsvox
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
(require 'kmacro)

;;;  bind keys 

(global-set-key [f13] 'kmacro-start-macro-or-insert-counter)
(global-set-key [f14] 'kmacro-end-or-call-macro)

;;;  Advice interactive commands

(defun emacsvox--advice-kmacro-start-macro-before (&rest _)
  "Provide auditory icon."
  (when (ems-interactive-p 'kmacro-start-macro)
    (emacsvox-icon 'open-object) (message "Defining new kbd macro.")))

(advice-add 'kmacro-start-macro :before
            #'emacsvox--advice-kmacro-start-macro-before)

(defun emacsvox--advice-kmacro-start-macro-or-insert-counter-before
    (&rest _)
  "Provide auditory icon if new macro is being defined."
  (when
      (and
       (ems-interactive-p 'kmacro-start-macro-or-insert-counter)
       (not defining-kbd-macro)
       (not executing-kbd-macro))
    (emacsvox-icon 'yank-object) (message "Defining new kbd macro.")))

(advice-add 'kmacro-start-macro-or-insert-counter :before
            #'emacsvox--advice-kmacro-start-macro-or-insert-counter-before)

(defun emacsvox--advice-kmacro-end-or-call-macro-before (&rest _)
  "speak about we are about to do."
  (cond
   ((and
     (ems-interactive-p 'kmacro-end-or-call-macro)
     defining-kbd-macro)
    (emacsvox-icon 'close-object)
    (message "Finished defining kbd macro."))
   (t (emacsvox-icon 'open-object) (message "Calling macro."))))

(advice-add 'kmacro-end-or-call-macro :before
            #'emacsvox--advice-kmacro-end-or-call-macro-before)

(defun emacsvox--advice-kmacro-end-or-call-macro-repeat-before
    (&rest _)
  "speak about we are about to do."
  (cond
   ((and
     (ems-interactive-p 'kmacro-end-or-call-macro-repeat)
     defining-kbd-macro)
    (message "Finished defining kbd macro."))
   (t (emacsvox-icon 'select-object) (message "Calling macro."))))

(advice-add 'kmacro-end-or-call-macro-repeat :before
            #'emacsvox--advice-kmacro-end-or-call-macro-repeat-before)

(defun emacsvox--advice-kmacro-edit-macro-repeat-after (&rest _)
  "speak."
  (when (ems-interactive-p 'kmacro-edit-macro-repeat)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'kmacro-edit-macro-repeat :after
            #'emacsvox--advice-kmacro-edit-macro-repeat-after)

(defun emacsvox--advice-kmacro-call-ring-2nd-repeat-before (&rest _)
  "speak."
  (when (ems-interactive-p 'kmacro-call-ring-2nd-repeat)
    (message "Calling  second macro from ring.")))

(advice-add 'kmacro-call-ring-2nd-repeat :before
            #'emacsvox--advice-kmacro-call-ring-2nd-repeat-before)

(defun emacsvox--advice-kmacro-call-macro-around (orig-fun &rest args)
  "Speech-enabled by emacsvox."
  (let ((emacsvox-speak-messages nil))
    (apply orig-fun args)))

(advice-add 'kmacro-call-macro :around
            #'emacsvox--advice-kmacro-call-macro-around)

(defun emacsvox--advice-kmacro-call-last-kbd-macro-around
    (orig-fun &rest args)
  "Speech-enabled by emacsvox."
  (let ((emacsvox-speak-messages t))
    (apply orig-fun args)))

(advice-add 'call-last-kbd-macro :around
            #'emacsvox--advice-kmacro-call-last-kbd-macro-around)

(provide 'emacsvox-kmacro)
;;;  end of file
