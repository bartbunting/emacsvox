;;; emacsvox-vertico.el --- Speech-enable Vertico  -*- lexical-binding: t; -*-
;; Author: Krzysztof Drewniak <krzysdrewniak@gmail.com>
;; Description:  Speech-enable Vertico, a modern Emacs completion interface
;; Keywords: Emacsvox, Audio Desktop, Vertico, completion

;;;   Copyright:

;; Copyright (C) 2021 Krzysztof Drewniak <krzysdrewniak@gmail.com>
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
;; MERCHANTABILITY or FITNMARKDOWN FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Vertico is a modern completion UI that uses Emacs's native completion engine
;; This module speech-enables Vertico's UI

;;; Code:
;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'vertico nil 'noerror)

;;;  Map faces to voices:

(voice-setup-add-map
 '((vertico-group-title voice-smoothen)
   (vertico-group-separator voice-overlay-0)))

;;;  Define bookkeeping variables for UI state

(defvar-local emacsvox-vertico--prev-candidate nil
  "Previously spoken candidate")

(defvar-local emacsvox-vertico--prev-index nil
  "Index of previously spoken candidate")

;;; 
(declare-function 'vertico--candidate "vertico.el" (&optional hl))

;;;  Advice interactive commands

(defun ems--vertico-insert-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (let* ((orig-point (point)))
      (apply orig-fun args) (emacsvox-icon 'complete)
      (emacsvox-speak-region orig-point (point)))
    result))

(advice-add 'vertico-insert :around #'ems--vertico-insert-around)

(defun ems--vertico--exhibit-after (&rest _)
  "speak."
  (cl-declare
   (special vertico--allow-prompt vertico--index vertico--base))
  (let
      ((new-cand
        (substring (vertico--candidate)
                   (if (>= vertico--index 0)
                       (if (stringp vertico--base)
                           (length vertico--base)
                         vertico--base)
                     0)))
       (to-speak nil))
    (unless (equal emacsvox-vertico--prev-candidate new-cand)
      (setq to-speak new-cand)
      (when
          (or (equal vertico--index emacsvox-vertico--prev-index)
              (and (not (equal vertico--index -1))
                   (equal emacsvox-vertico--prev-index -1)))
        (emacsvox-icon 'select-object)))
    (when to-speak (dtk-speak to-speak))
    (setq-local emacsvox-vertico--prev-candidate new-cand
                emacsvox-vertico--prev-index vertico--index)))

(advice-add 'vertico--exhibit :after #'ems--vertico--exhibit-after)

(cl-loop
 for (f icon) in
 '((vertico-scroll-up scroll)
   (vertico-scroll-down scroll)
   (vertico-first large-movement)
   (vertico-last large-movement)
   (vertico-next select-object)
   (vertico-previous select-object)
   (vertico-exit close-object)
   (vertico-kill delete-object))
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon ',icon)))))

(provide 'emacsvox-vertico)
;;;  end of file

