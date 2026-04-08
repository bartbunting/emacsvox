;;; emacsvox-woman.el --- Speech-enable WOMAN  -*- lexical-binding: t; -*-
;; $Id: emacsvox-woman.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable WOMAN An Emacs Interface to Man pages
;; Keywords: Emacsvox,  Audio Desktop woman, Man Pages
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
;; MERCHANTABILITY or FITNWOMAN FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; WOMAN ==  Man pages implemented in Emacs Lisp

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'dired)
(require 'woman nil 'no-error)

;;;  Map faces to voices

(voice-setup-add-map
 '(
   (Man-overstrike   voice-animate)
   (woman-unknown  voice-monotone-extra)
   (woman-edition voice-bolden-medium)
   (woman-bold voice-bolden)
   (woman-italic voice-animate)))

;;;  Advice interactive functions

(defun ems--WoMan-next-manpage-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'WoMan-next-manpage :after #'ems--WoMan-next-manpage-after)

(defun ems--WoMan-previous-manpage-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'WoMan-previous-manpage :after
            #'ems--WoMan-previous-manpage-after)

(provide 'emacsvox-woman)
;;;  end of file

