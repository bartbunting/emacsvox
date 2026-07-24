;;; emacsvox-supercite.el --- Speech enable SC  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacsvox extension to speech enable supercite
;; Keywords: Emacsvox, supercite, mail
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

;; Speech-enable supercite.

;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'supercite)

;;;  Advice

(defmacro emacsvox-supercite--define-region-advice (target verb)
  "Define native region feedback for TARGET using past-tense VERB."
  (declare (indent 1) (debug (symbolp stringp)))
  (let ((function (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (start end &rest _)
         "Announce a completed interactive Supercite region operation."
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'mark-object)
           (message ,(format "%s region containing %%s lines" verb)
                    (count-lines start end))))
       (advice-add ',target :after #',function))))

(emacsvox-supercite--define-region-advice sc-cite-region "Cited")
(emacsvox-supercite--define-region-advice sc-recite-region "Re-cited")
(emacsvox-supercite--define-region-advice sc-uncite-region "Uncited")

(defun emacsvox--advice-sc-insert-reference-around (orig-fun &rest args)
  "Speak what we inserted"
  (if (ems-interactive-p 'sc-insert-reference)
      (let ((opoint (point))
            (result (apply orig-fun args)))
        (emacsvox-speak-region opoint (point))
        (emacsvox-icon 'yank-object)
        result)
    (apply orig-fun args)))

(advice-add 'sc-insert-reference :around
            #'emacsvox--advice-sc-insert-reference-around)

(defun emacsvox--advice-sc-insert-citation-after (&rest _)
  "Speak what we inserted"
  (when (ems-interactive-p 'sc-insert-citation)
    (emacsvox-speak-line) (emacsvox-icon 'yank-object)))

(advice-add 'sc-insert-citation :after
            #'emacsvox--advice-sc-insert-citation-after)

(defun emacsvox--advice-sc-open-line-after (&rest _)
  "speak"
  (when (ems-interactive-p 'sc-open-line)
    (emacsvox-icon 'open-object) (tts-speak "Opened a blank line")))

(advice-add 'sc-open-line :after
            #'emacsvox--advice-sc-open-line-after)

(provide 'emacsvox-supercite)

;;;  end of file 
