;;; emacsvox-tide.el --- Speech-enable TIDE  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable TIDE An Emacs Interface to tide
;; Keywords: Emacsvox,  Audio Desktop,  tide: Typescript IDE
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; MERCHANTABILITY or FITNTIDE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; TIDE ==  Typescript IDE for emacs.
;; This module speech-enables both tide and typescript-mode.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (tide-file voice-lighten)
   (tide-hl-identifier-face voice-animate)
   (tide-imenu-type-face voice-annotate)
   (tide-line-number voice-monotone-extra)
   (tide-match voice-bolden)))

;;;  Interactive Commands:

(defun ems--tide-compile-file-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'tide-compile-file :after #'ems--tide-compile-file-after)

(defun ems--tide-documentation-at-point-after (&rest _)
  "Speak documentation if any."
  (let ((documentation (ad-get-arg 0)))
    (when documentation
      (dtk-speak documentation) (emacsvox-icon 'help))))

(advice-add 'tide-documentation-at-point :after
            #'ems--tide-documentation-at-point-after)

(cl-loop
 for f in
 '(
   tide-find-next-reference tide-find-previous-reference tide-goto-reference
   tide-jump-back tide-jump-to-definition)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defun ems--tide-format-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'tide-format :after #'ems--tide-format-after)

(defun ems--tide-references-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'tide-references :after #'ems--tide-references-after)

(provide 'emacsvox-tide)
;;;  end of file

