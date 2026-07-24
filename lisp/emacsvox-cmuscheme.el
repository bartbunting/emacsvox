;;; emacsvox-cmuscheme.el --- CMUScheme   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Speech-enable emacs for scheme and guile
;; Keywords: Emacsvox, cmuscheme
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
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
;; speech-enable scheme support 

;;; Code:

;;  required modules

;;; Code:

(require 'emacsvox-preamble)
(require 'cmuscheme)

;;;  advice interactive commands.

;; speech-enable cmuscheme 

(defmacro emacsvox-cmuscheme--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive CMU Scheme TARGET."
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

(emacsvox-cmuscheme--define-advice inferior-scheme-mode :after
  (emacsvox-icon 'task-done)
  (message "Welcome to inferior scheme mode."))

(defun emacsvox--advice-run-scheme-after (command &rest _)
  "Report COMMAND after interactive `run-scheme'."
  (when (ems-interactive-p 'run-scheme)
    (emacsvox-icon 'task-done)
    (message "Launched scheme %s" command)))

(advice-add
 'run-scheme :after
 #'emacsvox--advice-run-scheme-after
 '((name . emacsvox--advice-run-scheme-after)))

(defmacro emacsvox-cmuscheme--define-region-advice
    (target action)
  "Define explicit region feedback for TARGET using ACTION."
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (start end &rest _)
         ,(format "Report the region processed by `%s'." target)
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'select-object)
           (message
            ,(format "%s %%s lines to scheme. " action)
            (count-lines start end))))
       (advice-add
        ',target :after #',function
        '((name . ,function))))))

(emacsvox-cmuscheme--define-region-advice
 scheme-send-region "Sent")
(emacsvox-cmuscheme--define-region-advice
 scheme-compile-region "Compiling ")

(emacsvox-cmuscheme--define-advice scheme-send-definition :after
  (emacsvox-icon 'select-object)
  (message "Sent definition   to scheme. "))

(emacsvox-cmuscheme--define-advice scheme-send-last-sexp :after
  (emacsvox-icon 'select-object)
  (message "Sent last sexp  to scheme. "))

(emacsvox-cmuscheme--define-advice scheme-compile-definition :after
  (emacsvox-icon 'select-object)
  (message "Compiled definition  to scheme. "))

(dolist
    (target
     '(switch-to-scheme
       scheme-send-region-and-go
       scheme-send-definition-and-go))
  (eval
   `(emacsvox-cmuscheme--define-advice ,target :after
      (emacsvox-icon 'select-object)
      (emacsvox-speak-mode-line))))

(defmacro emacsvox-cmuscheme--define-file-advice
    (target action)
  "Define explicit file feedback for TARGET using ACTION."
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (file-name &rest _)
         ,(format "Report the file processed by `%s'." target)
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'select-object)
           (message ,(format "%s scheme file %%s" action) file-name)))
       (advice-add
        ',target :after #',function
        '((name . ,function))))))

(emacsvox-cmuscheme--define-file-advice scheme-load-file "loaded")
(emacsvox-cmuscheme--define-file-advice scheme-compile-file "Compiled")

(provide 'emacsvox-cmuscheme)
;;;  end of file
