;;; emacspeak-dictionary.el --- dictionaries  -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $
;; Description:   Speech enable dictionary mode
;; Keywords: Emacspeak, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacspeak
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

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;; Commentary:
;; Speech-enables emacs client for accessing dictionary
;; server at dict.org:2628
;;; Code:

;;;  Advice interactive commands to speak.

(defun ems--dictionary-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-mode-line)))


(advice-add 'dictionary :after #'ems--dictionary-after)




(defun ems--dictionary-close-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-mode-line)))


(advice-add 'dictionary-close :after #'ems--dictionary-close-after)




(defun ems--dictionary-select-dictionary-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object) (message "Selected dictionary")))


(advice-add 'dictionary-select-dictionary :after
	    #'ems--dictionary-select-dictionary-after)




(defun ems--dictionary-select-strategy-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'select-object) (message "Selected strategy")))


(advice-add 'dictionary-select-strategy :after
	    #'ems--dictionary-select-strategy-after)





(defun ems--dictionary-search-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'search-hit) (emacspeak-speak-line)))


(advice-add 'dictionary-search :after #'ems--dictionary-search-after)




(defun ems--dictionary-lookup-definition-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'search-hit) (emacspeak-speak-line)))


(advice-add 'dictionary-lookup-definition :after
	    #'ems--dictionary-lookup-definition-after)





(defun ems--dictionary-match-words-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'search-hit) (emacspeak-speak-line)))


(advice-add 'dictionary-match-words :after
	    #'ems--dictionary-match-words-after)





(defun ems--dictionary-previous-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement) (emacspeak-speak-line)))


(advice-add 'dictionary-previous :after
	    #'ems--dictionary-previous-after)




(defun ems--dictionary-prev-link-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement)
    (emacspeak-speak-range 'link-function)))


(advice-add 'dictionary-prev-link :after
	    #'ems--dictionary-prev-link-after)





(defun ems--dictionary-next-link-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement)
    (emacspeak-speak-range 'link-function)))


(advice-add 'dictionary-next-link :after
	    #'ems--dictionary-next-link-after)




(provide 'emacspeak-dictionary)
;;;  end of file

