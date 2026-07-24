;;; emacsvox-abc-mode.el --- Speech-enable ABC  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ABC-MODE An Emacs Interface to abc-mode
;; Keywords: Emacsvox,  Audio Desktop abc-mode
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
;; MERCHANTABILITY or FITNABC-MODE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ABC-MODE ==  Specialized mode for editing  ABC Music notation.
;; See @url{http://www.lesession.co.uk/abc/abc_notation.htm} for details.
;; This package speech-enables abc-mode.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-abc-mode--advice-targets
 '(
   abc-align-bars
   abc-backward-song
   abc-crescendo-region
   abc-current-song-number
   abc-diminuendo-region
   abc-extract-chords
   abc-forward-song
   abc-insert-chord
   abc-insert-instrument
   abc-midi-chords
   abc-renumber-songs
   abc-repeat-region
   abc-slur-region)
  "Current ABC Mode commands that receive native advice.")

(cl-loop
 for target in emacsvox-abc-mode--advice-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-speak-line)
       (emacsvox-icon 'button)))))

(defun emacsvox-abc-mode--install-advice ()
  "Install advice after the optional ABC Mode package loads."
  (dolist (target emacsvox-abc-mode--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'abc-mode
  (emacsvox-abc-mode--install-advice))

(provide 'emacsvox-abc-mode)
;;;  end of file
