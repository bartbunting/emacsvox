;;; emacsvox-hideshow.el --- speech-enable hideshow -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable hideshow
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;;  required modules

(require 'emacsvox-preamble)
(require 'hideshow)

;;; Commentary:

;; speech-enable hideshow.el
;;; Code:

;;;  speech enable interactive commands 

(defun emacsvox--advice-hs-hide-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-all)
    (emacsvox-icon 'close-object) (message "Hid all blocks.")))

(advice-add 'hs-hide-all :after
            #'emacsvox--advice-hs-hide-all-after)

(defun emacsvox--advice-hs-show-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-show-all)
    (emacsvox-icon 'open-object) (message "Exposed all blocks.")))

(advice-add 'hs-show-all :after
            #'emacsvox--advice-hs-show-all-after)

(defun emacsvox--advice-hs-hide-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-block)
    (emacsvox-icon 'close-object) (message "Hid current block.")))

(advice-add 'hs-hide-block :after
            #'emacsvox--advice-hs-hide-block-after)

(defun emacsvox--advice-hs-show-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-show-block)
    (emacsvox-icon 'open-object) (message "Exposed current  block.")))

(advice-add 'hs-show-block :after
            #'emacsvox--advice-hs-show-block-after)

(defun emacsvox--advice-hs-hide-level-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-level)
    (emacsvox-icon 'close-object)
    (message "Hid all blocks below specified level.")))

(advice-add 'hs-hide-level :after
            #'emacsvox--advice-hs-hide-level-after)

(defun emacsvox--advice-hs-toggle-hiding-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-toggle-hiding)
    (cond
     ((hs-already-hidden-p) (emacsvox-icon 'close-object)
      (message "Hid block"))
     (t (emacsvox-icon 'open-object) (message "Exposed block")))))

(advice-add 'hs-toggle-hiding :after
            #'emacsvox--advice-hs-toggle-hiding-after)

(defun emacsvox--advice-hs-hide-initial-comment-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-initial-comment-block)
    (emacsvox-icon 'close-object)
    (message "Hid initial comment block.")))

(advice-add 'hs-hide-initial-comment-block :after
            #'emacsvox--advice-hs-hide-initial-comment-block-after)

(provide 'emacsvox-hideshow)
;;;  end of file
