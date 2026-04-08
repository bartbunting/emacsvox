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

;;;  Advice

(defun ems--sc-cite-region-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "Cited region containing %s lines"
             (count-lines (ad-get-arg 0) (ad-get-arg 1)))))

(advice-add 'sc-cite-region :after #'ems--sc-cite-region-after)

(defun ems--sc-recite-region-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "Re-cited region containing %s lines"
             (count-lines (ad-get-arg 0) (ad-get-arg 1)))))

(advice-add 'sc-recite-region :after #'ems--sc-recite-region-after)

(defun ems--sc-uncite-region-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "Uncited region containing %s lines"
             (count-lines (ad-get-arg 0) (ad-get-arg 1)))))

(advice-add 'sc-uncite-region :after #'ems--sc-uncite-region-after)

(defun ems--sc-insert-reference-around (orig-fun &rest args)
  "Speak what we inserted"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((opoint (point)))
        (apply orig-fun args) (emacsvox-speak-region opoint (point))
        (emacsvox-icon 'yank-object)))
     (t (apply orig-fun args)))
    result))

(advice-add 'sc-insert-reference :around
            #'ems--sc-insert-reference-around)

(defun ems--sc-insert-citation-after (&rest _)
  "Speak what we inserted"
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'yank-object)))

(advice-add 'sc-insert-citation :after #'ems--sc-insert-citation-after)

(defun ems--sc-open-line-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (dtk-speak "Opened a blank line")))

(advice-add 'sc-open-line :after #'ems--sc-open-line-after)

(provide 'emacsvox-supercite)

;;;  end of file 

