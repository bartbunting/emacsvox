;;; emacsvox-avy.el --- Speech-enable AVY  -*- lexical-binding: t; -*-
;; $Author: Robert Melton $
;; Description:  Speech-enable AVY An Emacs Interface to avy
;; Keywords: Emacsvox,  Audio Desktop avy
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
;; AVY == Jump to visible text using a char-based decision tree.
;; This module speech-enables avy navigation commands.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'avy nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (avy-lead-face voice-bolden)
   (avy-lead-face-0 voice-brighten)
   (avy-lead-face-1 voice-animate)
   (avy-lead-face-2 voice-lighten)
   (avy-background-face voice-monotone)))

;;;  Goto Commands:

(cl-loop
 for f in
 '(avy-goto-char avy-goto-char-2 avy-goto-char-timer
   avy-goto-word-0 avy-goto-word-1
   avy-goto-line
   avy-goto-subword-0 avy-goto-subword-1
   avy-isearch avy-resume)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak line after jump."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

;;;  Copy, Move, Kill Commands:

(cl-loop
 for f in
 '(avy-copy-line avy-copy-region
   avy-move-line avy-move-region
   avy-kill-whole-line avy-kill-region avy-kill-ring-save)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Confirm action."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (dtk-speak ,(format "%s done" (symbol-name f)))))))

(provide 'emacsvox-avy)
;;;  end of file
