;;; emacsvox-sql.el --- Speech enable sql-mode  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable sql-mode
;; Keywords: Emacsvox, database interaction
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'sql)

(declare-function sqlplus-back-command "sqlplus" (&optional count))

;;; Commentary:

;; This module speech enables sql-mode--
;; available from
;;  the Emacs package archive.
;; sql-mode.el implemented by the above package
;; sets up an Emacs to SQL interface where you can
;; interactively evaluate SQL expressions.
;;; Code:

;;;  advice

(defun emacsvox--advice-sqlplus-execute-command-after (&rest _)
  "speak and place point at the start of the output."
  (when (ems-interactive-p 'sqlplus-execute-command)
    (emacsvox-icon 'scroll) (sqlplus-back-command 2) (forward-line 1)
    (emacsvox-speak-line)))

(defun emacsvox--advice-sqlplus-back-command-after (&rest _)
  "Move prompt appropriately,  and speak the line."
  (when (ems-interactive-p 'sqlplus-back-command)
    (emacsvox-icon 'large-movement) (forward-line 1)
    (emacsvox-speak-line)))

(defun emacsvox--advice-sqlplus-forward-command-after (&rest _)
  "Move prompt appropriately,  and speak the line."
  (when (ems-interactive-p 'sqlplus-forward-command)
    (emacsvox-icon 'large-movement) (forward-line 1)
    (emacsvox-speak-line)))

(defun emacsvox--advice-sqlplus-next-command-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'sqlplus-next-command)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(defun emacsvox--advice-sqlplus-previous-command-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'sqlplus-previous-command)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(defconst emacsvox-sql--sqlplus-targets
  '(sqlplus-execute-command
    sqlplus-back-command
    sqlplus-forward-command
    sqlplus-next-command
    sqlplus-previous-command)
  "Commands supplied by the optional sqlplus package.")

(defun emacsvox-sql--install-sqlplus-advice ()
  "Attach speech feedback to available sqlplus commands."
  (dolist (target emacsvox-sql--sqlplus-targets)
    (when (fboundp target)
      (advice-add
       target :after
       (intern (format "emacsvox--advice-%s-after" target))))))

(with-eval-after-load 'sqlplus
  (emacsvox-sql--install-sqlplus-advice))

(defmacro emacsvox-sql--define-send-advice (targets)
  "Define once-only native around advice for SQL send TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest args)
                 "Run one SQL send operation and cue interactive dispatch."
                 (if (ems-interactive-p ',target)
                     (progn
                       (emacsvox-icon 'select-object)
                       (let ((result (apply orig-fun args)))
                         (emacsvox-icon 'mark-object)
                         result))
                   (apply orig-fun args)))
               (advice-add ',target :around #',function))))
        targets)))

(emacsvox-sql--define-send-advice
    (sql-send-region sql-send-buffer))

(provide 'emacsvox-sql)

;;;  end of file
