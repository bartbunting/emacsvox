;;; emacsvox-elpy.el --- Speech-enable ELPY -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ELPY An Emacs Interface to elpy
;; Keywords: Emacsvox,  Audio Desktop elpy
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
;; MERCHANTABILITY or FITNELPY FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ELPY ==  Emacs Lisp Python IDE
;; Speech-enables all aspects of elpy.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice Interactive Commands:

(defconst emacsvox-elpy--task-targets
  '(elpy-autopep8-fix-code elpy-config elpy-check
    elpy-occur-definitions elpy-rgrep-symbol
    elpy-set-project-root elpy-set-project-variable
    elpy-set-test-runner
    elpy-shell-send-statement-and-step elpy-shell-send-region-or-buffer
    elpy-shell-switch-to-buffer elpy-shell-switch-to-shell
    elpy-use-cpython elpy-use-ipython
    elpy-importmagic-add-import elpy-importmagic-fixup)
  "Elpy commands that report task completion.")

(cl-loop
 for target in emacsvox-elpy--task-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s' completes." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-mode-line)))))

(defun emacsvox--advice-elpy-enable-after (&rest _)
  "Report enabling Elpy."
  (when (ems-interactive-p 'elpy-enable)
    (emacsvox-icon 'on) (message "Enabled elpy")))

(defun emacsvox--advice-elpy-disable-after (&rest _)
  "Report disabling Elpy."
  (when (ems-interactive-p 'elpy-disable)
    (emacsvox-icon 'off) (message "Disabled elpy")))

(defun emacsvox--advice-elpy-doc-after (&rest _)
  "Report displaying Elpy documentation."
  (when (ems-interactive-p 'elpy-doc)
    (emacsvox-icon 'help) (message "Displayed help in other window.")))

(defun emacsvox--advice-elpy-find-file-after (&rest _)
  "Speak after visiting a file with Elpy."
  (when (ems-interactive-p 'elpy-find-file)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defconst emacsvox-elpy--movement-targets
  '(elpy-flymake-next-error elpy-flymake-previous-error
    elpy-goto-definition
    elpy-nav-backward-block elpy-nav-backward-indent
    elpy-nav-expand-to-indentation elpy-nav-forward-block
    elpy-nav-forward-indent
    elpy-nav-indent-shift-left elpy-nav-indent-shift-right
    elpy-open-and-indent-line-below elpy-open-and-indent-line-above
    elpy-nav-move-line-or-region-down elpy-nav-move-line-or-region-up)
  "Elpy movement and navigation commands.")

(cl-loop
 for target in emacsvox-elpy--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s' moves point." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defconst emacsvox-elpy--removed-targets
  '(elpy-shell-send-current-statement)
  "Obsolete Elpy command names removed during migration.")

(defconst emacsvox-elpy--advice-targets
  (append emacsvox-elpy--task-targets
          '(elpy-enable elpy-disable elpy-doc elpy-find-file)
          emacsvox-elpy--movement-targets)
  "Current Elpy targets that receive native after advice.")

(defun emacsvox-elpy--install-advice ()
  "Install native advice after the optional Elpy package loads."
  (dolist (target emacsvox-elpy--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'elpy
  (emacsvox-elpy--install-advice))

(provide 'emacsvox-elpy)
;;;  end of file
