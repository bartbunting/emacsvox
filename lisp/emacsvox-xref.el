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

;;;   Advice Interactive Commands:

(cl-loop
 for   f in 
 '(
   xref-find-definitions xref-pop-marker-stack pop-tag-mark
   xref-next-line xref-prev-line xref-go-back
   xref-find-regexp  xref-pop-marker-stack
   xref-find-apropos xref-goto-xref)
 do
 (eval
  `(defadvice ,f (after emacsvox pre  act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'large-movement)))))

(cl-loop
 for f in 
 '(
   xref-find-definitions-other-frame  xref-find-definitions-other-window
   xref-show-location-at-point)
 do
 (eval
  `(defadvice ,f (after emacsvox pre  act comp)
     "speak."
     (when (ems-interactive-p)
       (message "Displayed cross-reference.")
       (emacsvox-icon 'select-object)))))

(defun ems--xref-find-references-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'task-done)))

(advice-add 'xref-find-references :after
            #'ems--xref-find-references-after)

(provide 'emacsvox-xref)
;;;  end of file

