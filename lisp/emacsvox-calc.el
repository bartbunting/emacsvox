;;; emacsvox-calc.el --- Speech enable Calc   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;;; Description: 
;;; Keywords:
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.



;;; Commentary:
;; This module extends the Emacs Calculator.
;; Extensions are minimal.
;; We force a calc-load-everything,
;; And use an after advice on this function
;; To fix all of calc's interactive functions
;;; Code:

;;  required modules
(require 'emacsvox-preamble)
(require 'calc)

;;;   advice calc interaction 

(defun emacsvox--advice-calc-dispatch-after (&rest _)
  "speak."
  (when (ems-interactive-p 'calc-dispatch)
    (emacsvox-icon 'open-object)))

(advice-add 'calc-dispatch :after
            #'emacsvox--advice-calc-dispatch-after)

(defun emacsvox--advice-calc-quit-after (&rest _)
  "Announce the buffer that becomes current when calc is quit."
  (when (ems-interactive-p 'calc-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'calc-quit :after #'emacsvox--advice-calc-quit-after)

;;;   speak output 

(defun emacsvox--advice-calc-call-last-kbd-macro-around
    (orig-fun &rest args)
  "Speak."
  (if (ems-interactive-p 'calc-call-last-kbd-macro)
      (let ((result
             (ems-with-messages-silenced
               (apply orig-fun args))))
        (tts-with-punctuations 'all
          (emacsvox-read-previous-line))
        (emacsvox-icon 'task-done)
        result)
    (apply orig-fun args)))

(with-eval-after-load 'calc-prog
  (advice-add 'calc-call-last-kbd-macro :around
              #'emacsvox--advice-calc-call-last-kbd-macro-around))

(defun emacsvox--advice-calc-do-around (orig-fun &rest args)
  "Speak previous line of output."
  (let ((result
         (ems-with-messages-silenced
           (apply orig-fun args))))
    (tts-with-punctuations 'all (emacsvox-read-previous-line)
                           (emacsvox-icon 'select-object))
    result))

(advice-add 'calc-do :around #'emacsvox--advice-calc-do-around)

(defun emacsvox--advice-calc-trail-here-after (&rest _)
  "Speak previous line of output." (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(advice-add 'calc-trail-here :after
            #'emacsvox--advice-calc-trail-here-after)

(provide 'emacsvox-calc)
