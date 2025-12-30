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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Interactive Commands:


(defun ems--debugger-continue-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))


(advice-add 'debugger-continue :after #'ems--debugger-continue-after)




(cl-loop
 for f in 
 '(backtrace-forward-frame backtrace-backward-frame)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))


(defun ems--debugger-eval-expression-after (&rest _)
  "speak." (when (ems-interactive-p) (dtk-speak ad-return-value)))


(advice-add 'debugger-eval-expression :after
	    #'ems--debugger-eval-expression-after)





(defun ems--debugger-list-functions-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-speak-help)))


(advice-add 'debugger-list-functions :after
	    #'ems--debugger-list-functions-after)




(defun ems--debugger-quit-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))


(advice-add 'debugger-quit :after #'ems--debugger-quit-after)




(provide 'emacsvox-debugger)
;;;  end of file

