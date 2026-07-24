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

;;; Forward variable declarations:

(defvar vertico--allow-prompt)
(defvar vertico--base)
(defvar vertico--index)
;;   Required modules:

(eval-when-compile (require 'cl-lib))
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

(defun emacsvox--advice-vertico-insert-around (orig-fun &rest args)
  "Call ORIG-FUN once and speak the inserted completion."
  (let ((orig-point (point))
        (result (apply orig-fun args)))
    (emacsvox-icon 'complete)
    (emacsvox-speak-region orig-point (point))
    result))

(defun emacsvox--advice-vertico--exhibit-after (&rest _)
  "speak."
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
    (when to-speak (tts-speak to-speak))
    (setq-local emacsvox-vertico--prev-candidate new-cand
                emacsvox-vertico--prev-index vertico--index)))

(defconst emacsvox-vertico--icon-targets
 '((vertico-scroll-up scroll)
   (vertico-scroll-down scroll)
   (vertico-first large-movement)
   (vertico-last large-movement)
   (vertico-next select-object)
   (vertico-previous select-object)
   (vertico-exit close-object))
 "Current Vertico commands and their auditory icons.")

(dolist (entry emacsvox-vertico--icon-targets)
  (pcase-let ((`(,target ,icon) entry))
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Play an auditory icon after `%s'." target)
          (when (ems-interactive-p ',target)
            (emacsvox-icon ',icon)))))))

(defconst emacsvox-vertico--advice
  (append
   '((vertico-insert :around emacsvox--advice-vertico-insert-around)
     (vertico--exhibit :after emacsvox--advice-vertico--exhibit-after))
   (mapcar
    (lambda (entry)
      (let ((target (car entry)))
        (list target :after
              (intern (format "emacsvox--advice-%s-after" target)))))
    emacsvox-vertico--icon-targets))
  "Current Vertico targets and their native advice functions.")

(defun emacsvox-vertico--install-advice ()
  "Install native advice after Vertico loads."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'vertico
  (emacsvox-vertico--install-advice))

(provide 'emacsvox-vertico)
;;;  end of file
