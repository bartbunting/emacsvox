;;; emacsvox-go-mode.el --- Speech-enable GO-MODE  -*- lexical-binding: t; -*-
;; $Id: emacsvox-go-mode.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable GO-MODE An Emacs Interface to go-mode
;; Keywords: Emacsvox,  Audio Desktop go-mode
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
;; MERCHANTABILITY or FITNGO-MODE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; GO-MODE ==  Go Language support in emacs

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice interactive commands:

(defvar emacsvox-go-mode--advice nil
  "Current Go mode targets and their native advice functions.")
(setq emacsvox-go-mode--advice nil)

(defun emacsvox-go-mode--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-go-mode--advice))))

(defun emacsvox-go-mode--selection-feedback ()
  "Speak the selected Go source line."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-go-mode--register-after-group
 '(go-goto-imports go-import-add godef-jump godef-jump-other-window
   go-mode-indent-line go-mode-insert-and-indent)
 #'emacsvox-go-mode--selection-feedback)

(defun emacsvox-go-mode--task-feedback ()
  "Play the task completion icon."
  (emacsvox-icon 'task-done))

(emacsvox-go-mode--register-after-group
 '(godoc gofmt)
 #'emacsvox-go-mode--task-feedback)

(defun emacsvox-go-mode--install-advice ()
  "Install native advice after Go mode loads."
  (dolist (entry emacsvox-go-mode--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'go-mode
  (emacsvox-go-mode--install-advice))

(provide 'emacsvox-go-mode)
;;;  end of file
