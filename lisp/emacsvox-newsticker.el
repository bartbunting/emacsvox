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

;;;  define personalities 
(voice-setup-add-map
 '(
   (newsticker-new-item-face voice-brighten)
   (newsticker-old-item-face voice-monotone-extra)
   (newsticker-feed-face voice-animate)
   ))

;;;  advice functions

(defun ems--newsticker--cache-remove-around (orig-fun &rest args)
  "Silence messages temporarily to avoid chatter."
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages nil))
      (apply orig-fun args) result)
    result))

(advice-add 'newsticker--cache-remove :around
            #'ems--newsticker--cache-remove-around)

(defun ems--newsticker-callback-enter-around (orig-fun &rest args)
  "Silence messages temporarily to avoid chatter."
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages nil))
      (apply orig-fun args) result)
    result))

(advice-add 'newsticker-callback-enter :around
            #'ems--newsticker-callback-enter-around)

(defun ems--newsticker-retrieval-tick-around (orig-fun &rest args)
  "Silence messages temporarily to avoid chatter."
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages nil))
      (apply orig-fun args) result)
    result))

(advice-add 'newsticker-retrieval-tick :around
            #'ems--newsticker-retrieval-tick-around)

;;;  advice interactive commands

(defun emacsvox-newsticker-summarize-item ()
  "Summarize current item."
  (emacsvox-speak-line))

(cl-loop for f in
         '(newsticker-next-item newsticker-previous-item
                                newsticker-next-new-item
                                newsticker-previous-new-item
                                newsticker-previous-feed newsticker-next-feed
                                )
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "Speak."
             (when (ems-interactive-p)
               (emacsvox-icon 'large-movement)
               (emacsvox-newsticker-summarize-item)))))

;;;   silence auto activity

(cl-loop for f in
         '(newsticker-get-news-with-delay
           newsticker-get-news
           newsticker--cache-save)
         do
         (eval
          `(defadvice  ,f (around emacsvox pre act comp)
             "Silence messages."
             (let ((emacsvox-speak-messages nil))
               ad-do-it))))

(provide 'emacsvox-newsticker)
;;;  end of file

