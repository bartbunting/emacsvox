;;; emacsvox-winring.el --- Speech enable WinRing -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to winring
;; Keywords: Emacsvox, Speak, Spoken Output, winring
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;;   Required modules:

(require 'emacsvox-preamble)

;;;   Introduction
;;; Commentary:
;; window configurations in emacs are very useful 
;; you can display the same file in different windows,
;; and have different  portions of the file displayed.
;; winring allows you to manage window configurations,
;; and this module speech-enables it.
;;; Code:

;;;  Advice commands

(defun ems--winring-jump-to-configuration-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-describe-tapestry winring-name)))

(advice-add 'winring-jump-to-configuration :after
            #'ems--winring-jump-to-configuration-after)

(defun ems--winring-next-configuration-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-describe-tapestry winring-name)))

(advice-add 'winring-next-configuration :after
            #'ems--winring-next-configuration-after)

(defun ems--winring-prev-configuration-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-describe-tapestry winring-name)))

(advice-add 'winring-prev-configuration :after
            #'ems--winring-prev-configuration-after)

(defun ems--winring-new-configuration-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'winring-new-configuration :after
            #'ems--winring-new-configuration-after)

(defun ems--winring-delete-configuration-after (&rest _)
  "provide auditory feedback"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-mode-line)))

(advice-add 'winring-delete-configuration :after
            #'ems--winring-delete-configuration-after)

(provide 'emacsvox-winring)
;;;  end of file 

