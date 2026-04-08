;;; emacsvox-yasnippet.el --- YASNIPPET  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable YASNIPPET An Emacs Interface to yasnippet
;; Keywords: Emacsvox,  Audio Desktop yasnippet
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
;; MERCHANTABILITY or FITNYASNIPPET FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; YASNIPPET ==  Template based editing using snippets.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map personalities:

(voice-setup-set-voice-for-face 'yas-field-highlight-face 'voice-animate)

;;;  Advice interactive commands:

(cl-loop 
 for f in 
 '(
   yas-prev-field yas-expand
   yas-next-field yas-next-field-or-maybe-expand)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "provide feedback"
     (let ((emacsvox-show-point t))
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(defun ems--yas-insert-snippet-after (&rest _)
  "Speak inserted template."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'yas-insert-snippet :after #'ems--yas-insert-snippet-after)

(provide 'emacsvox-yasnippet)
;;;  end of file

