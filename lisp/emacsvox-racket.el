;;; emacsvox-racket.el --- Speech-enable RACKET  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable RACKET An Emacs IDE for  racket
;; Keywords: Emacsvox,  Audio Desktop racket IDE
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
;; MERCHANTABILITY or FITNRACKET FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; racket-mode implements an IDE for racket, a dialect of scheme.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (racket-check-syntax-def-face voice-bolden)
   (racket-check-syntax-use-face  voice-annotate)
   (racket-here-string-face voice-lighten)
   (racket-keyword-argument-face voice-animate-extra)
   (racket-paren-face voice-smoothen)
   (racket-selfeval-face voice-bolden-and-animate)))

;;;  Interactive Commands:

(cl-loop
 for f in
 '(racket--orp/enter racket--orp/next racket--orp/prev racket--orp/quit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   racket--profile-next
   racket--profile-prev racket--profile-quit
   racket--profile-refresh racket--profile-show-zero
   racket--profile-sort racket--profile-visit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   racket-visit-module racket-visit-definition
   racket-smart-open-bracket racket-insert-lambda racket-insert-closing
   racket-indent-line racket-check-syntax-mode-goto-def
   racket-check-syntax-mode-goto-next-def racket-check-syntax-mode-goto-next-use
   racket-check-syntax-mode-goto-prev-def racket-check-syntax-mode-goto-prev-use
   racket-backward-up-list)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'large-movement)))))

(defun ems--racket-describe-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'help)
    (with-current-buffer "*Racket Describe*" (emacsvox-speak-buffer))))

(advice-add 'racket-describe :after #'ems--racket-describe-after)

(provide 'emacsvox-racket)
;;;  end of file

