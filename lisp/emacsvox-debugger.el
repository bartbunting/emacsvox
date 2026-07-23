;;; emacsvox-debugger.el --- Speech-enable DEBUG -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable DEBUGGER An Emacs Interface to debugger
;; Keywords: Emacsvox,  Audio Desktop debugger
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
;; MERCHANTABILITY or FITNDEBUGGER FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; DEBUGGER ==  Emacs Interactive Debugger.
;; Speech-enable the debugger by speech-enabling interactive commands.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defun emacsvox--advice-debugger-continue-after (&rest _)
  "Cue completion after an interactive debugger continue command."
  (when (ems-interactive-p 'debugger-continue)
    (emacsvox-icon 'task-done)))

(advice-add
 'debugger-continue :after #'emacsvox--advice-debugger-continue-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(backtrace-forward-frame backtrace-backward-frame)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive backtrace navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-debugger-eval-expression-filter-return (result)
  "Speak and return RESULT from an interactive debugger evaluation."
  (when (ems-interactive-p 'debugger-eval-expression)
    (dtk-speak result))
  result)

(advice-add
 'debugger-eval-expression :filter-return
 #'emacsvox--advice-debugger-eval-expression-filter-return
 '((name . emacsvox)))

(defun emacsvox--advice-debugger-list-functions-after (&rest _)
  "Speak help after interactively listing debugged functions."
  (when (ems-interactive-p 'debugger-list-functions)
    (emacsvox-speak-help)))

(advice-add
 'debugger-list-functions :after
 #'emacsvox--advice-debugger-list-functions-after
 '((name . emacsvox)))

(defun emacsvox--advice-debugger-quit-after (&rest _)
  "Cue closure after interactively quitting the debugger."
  (when (ems-interactive-p 'debugger-quit)
    (emacsvox-icon 'close-object)))

(advice-add
 'debugger-quit :after #'emacsvox--advice-debugger-quit-after
 '((name . emacsvox)))

(provide 'emacsvox-debugger)
;;;  end of file
