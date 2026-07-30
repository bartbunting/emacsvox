;;; emacsvox-wdired.el --- Speech-enable wdired  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech-enable WDIRED
;; Keywords: Emacsvox, Multimedia
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

;;;   Introduction

;;; Commentary:
;; Speech-enable wdired to permit in-place renaming of groups of files.

;;; Code:
;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-dired)

;;;  Advice interactive commands.

(defmacro emacsvox-wdired--define-navigation-advice (&rest targets)
  "Define semantic Wdired navigation advice for TARGETS."
  (declare (indent 0) (debug (&rest symbolp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,(format "Present the entry selected by `%s'." target)
                 (when (ems-interactive-p ',target)
                   (emacsvox-dired-present-current
                    'select-object 'navigation 'focus-entered)))
               (advice-add
                ',target :after #',function '((name . emacsvox))))))
        targets)))

(emacsvox-wdired--define-navigation-advice
  wdired-next-line wdired-previous-line)

(defun emacsvox-wdired--edit-facts (kind)
  "Return current-entry facts for pending Wdired edit KIND."
  (append
   (emacsvox-dired-entry-facts 'object-changed)
   (list :filesystem-edit-kind kind)))

(defun emacsvox-wdired--present-edit (kind text &optional icon)
  "Present pending Wdired edit KIND with TEXT and optional ICON."
  (emacsvox-dired--submit-text
   text (emacsvox-wdired--edit-facts kind) 'edit icon))

(defmacro emacsvox-wdired--define-edit-advice (&rest specifications)
  "Define Wdired edit advice from SPECIFICATIONS.
Each specification is (TARGET KIND TEXT ICON)."
  (declare
   (indent 0)
   (debug (&rest (symbolp symbolp stringp &optional symbolp))))
  `(progn
     ,@(mapcar
        (lambda (specification)
          (pcase-let*
              ((`(,target ,kind ,text ,icon) specification)
               (function
                (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,(format "Present the edit made by `%s'." target)
                 (when (ems-interactive-p ',target)
                   (emacsvox-wdired--present-edit
                    ',kind ,text ',icon)))
               (advice-add
                ',target :after #',function '((name . emacsvox))))))
        specifications)))

(emacsvox-wdired--define-edit-advice
  (wdired-upcase-word filename-upcase "Uppercased file name" nil)
  (wdired-capitalize-word filename-capitalize "Capitalized file name" nil)
  (wdired-downcase-word filename-downcase "Downcased file name" nil)
  (wdired-set-bit permission-set "Set permission bit" button)
  (wdired-toggle-bit permission-toggled "Toggled permission bit" button)
  (wdired-mouse-toggle-bit permission-toggled "Toggled permission bit" button))

(defmacro emacsvox-wdired--define-operation-advice (&rest specifications)
  "Define Wdired operation advice from SPECIFICATIONS.
Each specification is (TARGET OPERATION ICON FALLBACK)."
  (declare (indent 0) (debug (&rest (symbolp symbolp symbolp stringp))))
  `(progn
     ,@(mapcar
        (lambda (specification)
          (pcase-let*
              ((`(,target ,operation ,icon ,fallback) specification)
               (function
                (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest arguments)
                 ,(format "Present the result of `%s'." target)
                 (emacsvox-dired--operation-around
                  orig-fun arguments ',target ',operation ',icon ,fallback))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        specifications)))

(emacsvox-wdired--define-operation-advice
  (wdired-abort-changes wdired-abort close-object "Canceled Wdired changes")
  (wdired-finish-edit wdired-commit save-object "Committed Wdired changes")
  (wdired-exit wdired-exit close-object "Exited writable Dired"))

(defun emacsvox-wdired--enter-around (orig-fun arguments target)
  "Call ORIG-FUN with ARGUMENTS and present TARGET entering Wdired."
  (if (ems-interactive-p target)
      (let ((context
             (emacsvox-aural-capture-context 'dired 'state-change))
            result)
        (let ((emacsvox-speak-messages nil))
          (setq result (apply orig-fun arguments)))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--submit-message
           "Entering writable Dired mode"
           (emacsvox-dired-operation-facts 'wdired-edit 'started)
           'state-change 'open-object))
        result)
    (apply orig-fun arguments)))

(defun emacsvox--advice-wdired-change-to-wdired-mode-around
    (orig-fun &rest arguments)
  "Present direct entry into writable Dired."
  (emacsvox-wdired--enter-around
   orig-fun arguments 'wdired-change-to-wdired-mode))

(advice-add
 'wdired-change-to-wdired-mode :around
 #'emacsvox--advice-wdired-change-to-wdired-mode-around
 '((name . emacsvox)))

(defun emacsvox--advice-dired-toggle-read-only-around
    (orig-fun &rest arguments)
  "Present entry into writable Dired through the Dired toggle."
  (emacsvox-wdired--enter-around
   orig-fun arguments 'dired-toggle-read-only))

(advice-add
 'dired-toggle-read-only :around
 #'emacsvox--advice-dired-toggle-read-only-around
 '((name . emacsvox-wdired)))

(provide 'emacsvox-wdired)
;;;  end of file
