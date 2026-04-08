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

;;;  Advice Mark Commands:

(cl-loop
 for f in
 '(mc/mark-next-like-this mc/mark-previous-like-this
   mc/mark-all-like-this mc/mark-all-in-region)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-speak (format "%s cursors" mc/num-cursors))
       (emacsvox-icon 'mark-object)))))

;;;  Advice Unmark Commands:

(cl-loop
 for f in
 '(mc/unmark-next-like-this mc/unmark-previous-like-this)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-speak (format "%s cursors" mc/num-cursors))
       (emacsvox-icon 'deselect-object)))))

;;;  Advice Skip Commands:

(cl-loop
 for f in
 '(mc/skip-to-next-like-this mc/skip-to-previous-like-this)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-speak (format "%s cursors" mc/num-cursors))
       (emacsvox-icon 'select-object)))))

;;;  Advice Edit Lines:

(defadvice mc/edit-lines (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak (format "%s cursors" mc/num-cursors))
    (emacsvox-icon 'mark-object)))

(provide 'emacsvox-multiple-cursors)
;;;  end of file
