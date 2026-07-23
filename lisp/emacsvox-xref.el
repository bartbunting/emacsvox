;;; emacsvox-xref.el --- Speech-enable XREF  -*- lexical-binding: t; -*-
;; $Id: emacsvox-xref.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable XREF An Emacs Interface to xref
;; Keywords: Emacsvox,  Audio Desktop xref
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
;; MERCHANTABILITY or FITNXREF FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; XREF ==  Cross-references in source code.
;; This is part of Emacs 25.
;; This module speech-enables xref

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'xref)

;;;   Advice Interactive Commands:

(cl-loop
 for target in
 '(
   xref-find-definitions xref-pop-marker-stack pop-tag-mark
   xref-next-line xref-prev-line xref-go-back
   xref-find-apropos xref-goto-xref)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Xref movement command."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-line)
         (emacsvox-icon 'large-movement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(
   xref-find-definitions-other-frame  xref-find-definitions-other-window
   xref-show-location-at-point)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Announce a cross-reference displayed by an interactive command."
       (when (ems-interactive-p ',target)
         (message "Displayed cross-reference.")
         (emacsvox-icon 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-xref-find-references-after (&rest _)
  "Speak after interactively finding Xref references."
  (when (ems-interactive-p 'xref-find-references)
    (emacsvox-speak-line)
    (emacsvox-icon 'task-done)))

(advice-add
 'xref-find-references :after
 #'emacsvox--advice-xref-find-references-after
 '((name . emacsvox)))

(provide 'emacsvox-xref)
;;;  end of file
