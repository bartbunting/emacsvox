;;; emacsvox-newsticker.el --- newsticker  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for NEWSTICKER 
;; Keywords: Emacsvox, newsticker 
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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

;; Newsticker provides a continuously updating newsticker using
;; RSS
;; Provides functionality similar to amphetadesk --but in pure elisp

;;  required modules

;;; Code:
(require 'emacsvox-preamble)
(require 'newsticker)

;;;  define personalities 
(voice-setup-add-map
 '(
   (newsticker-new-item-face voice-brighten)
   (newsticker-old-item-face voice-monotone-extra)
   (newsticker-feed-face voice-animate)
   ))

;;;  advice functions

(defmacro emacsvox-newsticker--define-silent-advice (targets)
  "Define once-only message-silencing advice for TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest args)
                 "Run one Newsticker operation without automatic speech."
                 (let ((emacsvox-speak-messages nil))
                   (apply orig-fun args)))
               (advice-add ',target :around #',function))))
        targets)))

(emacsvox-newsticker--define-silent-advice
    (newsticker--cache-remove
     newsticker--get-news-by-url-callback
     newsticker-get-news
     newsticker--cache-save))

;;;  advice interactive commands

(defun emacsvox-newsticker-summarize-item ()
  "Summarize current item."
  (emacsvox-speak-line))

(defmacro emacsvox-newsticker--define-navigation-advice (targets)
  "Define native after advice for Newsticker navigation TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 "Speak the current Newsticker item after navigation."
                 (when (ems-interactive-p ',target)
                   (emacsvox-icon 'large-movement)
                   (emacsvox-newsticker-summarize-item)))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-newsticker--define-navigation-advice
    (newsticker-next-item
     newsticker-previous-item
     newsticker-next-new-item
     newsticker-previous-new-item
     newsticker-previous-feed
     newsticker-next-feed))

(provide 'emacsvox-newsticker)
;;;  end of file
