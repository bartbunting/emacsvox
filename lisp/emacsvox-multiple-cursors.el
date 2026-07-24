;;; emacsvox-multiple-cursors.el --- Speech-enable MULTIPLE-CURSORS  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable MULTIPLE-CURSORS An Emacs Interface to multiple-cursors
;; Keywords: Emacsvox,  Audio Desktop multiple-cursors
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


;;; Commentary:
;; MULTIPLE-CURSORS == multiple-cursors
;; Speech-enable multiple-cursors for editing with multiple cursors.
;; Provides auditory feedback when adding, removing, and skipping cursors.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'multiple-cursors nil 'noerror)

(defvar mc/num-cursors)

(defvar emacsvox-multiple-cursors--advice nil
  "Current multiple-cursors targets and native advice functions.")
(setq emacsvox-multiple-cursors--advice nil)

(defun emacsvox-multiple-cursors--register-after-group (targets icon)
  "Define and register after advice for TARGETS using ICON."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Report cursor count after `%s'." target)
          (when (ems-interactive-p ',target)
            (dtk-speak (format "%s cursors" mc/num-cursors))
            (emacsvox-icon ',icon))))
      (push (list target :after advice-function)
            emacsvox-multiple-cursors--advice))))

(emacsvox-multiple-cursors--register-after-group
 '(mc/mark-next-like-this mc/mark-previous-like-this
   mc/mark-all-like-this mc/mark-all-in-region mc/edit-lines)
 'mark-object)

(emacsvox-multiple-cursors--register-after-group
 '(mc/unmark-next-like-this mc/unmark-previous-like-this)
 'deselect-object)

(emacsvox-multiple-cursors--register-after-group
 '(mc/skip-to-next-like-this mc/skip-to-previous-like-this)
 'select-object)

(defun emacsvox-multiple-cursors--install-advice ()
  "Install native advice after multiple-cursors loads."
  (dolist (entry emacsvox-multiple-cursors--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'multiple-cursors
  (emacsvox-multiple-cursors--install-advice))

(provide 'emacsvox-multiple-cursors)
;;;  end of file
