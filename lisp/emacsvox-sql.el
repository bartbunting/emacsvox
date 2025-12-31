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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:

;; This module speech enables sql-mode--
;; available from
;;  the Emacs package archive.
;; sql-mode.el implemented by the above package
;; sets up an Emacs to SQL interface where you can
;; interactively evaluate SQL expressions.
;;; Code:

;;;  advice

(defun ems--sqlplus-execute-command-after (&rest _)
  "speak and place point at the start of the output."
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (sqlplus-back-command 2) (forward-line 1)
    (emacsvox-speak-line)))

(advice-add 'sqlplus-execute-command :after
            #'ems--sqlplus-execute-command-after)

(defun ems--sqlplus-back-command-after (&rest _)
  "Move prompt appropriately,  and speak the line."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (forward-line 1)
    (emacsvox-speak-line)))

(advice-add 'sqlplus-back-command :after
            #'ems--sqlplus-back-command-after)

(defun ems--sqlplus-forward-command-after (&rest _)
  "Move prompt appropriately,  and speak the line."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (forward-line 1)
    (emacsvox-speak-line)))

(advice-add 'sqlplus-forward-command :after
            #'ems--sqlplus-forward-command-after)

(defun ems--sqlplus-next-command-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'sqlplus-next-command :after
            #'ems--sqlplus-next-command-after)

(defun ems--sqlplus-previous-command-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'sqlplus-previous-command :after
            #'ems--sqlplus-previous-command-after)

(defun ems--sql-send-region-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (emacsvox-icon 'select-object)
      (apply orig-fun args) (emacsvox-icon 'mark-object))
     (t (apply orig-fun args)))
    result))

(advice-add 'sql-send-region :around #'ems--sql-send-region-around)

(defun ems--sql-send-buffer-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (emacsvox-icon 'select-object)
      (apply orig-fun args) (emacsvox-icon 'mark-object))
     (t (apply orig-fun args)))
    result))

(advice-add 'sql-send-buffer :around #'ems--sql-send-buffer-around)

(provide 'emacsvox-sql)

;;;  end of file

