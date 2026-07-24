;;; emacsvox-dictionary.el --- dictionaries  -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $
;; Description:   Speech enable dictionary mode
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
(require 'dictionary)

;;; Commentary:
;; Speech-enables emacs client for accessing dictionary
;; server at dict.org:2628
;;; Code:

;;;  Advice interactive commands to speak.

(defun emacsvox--advice-dictionary-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'dictionary :after #'emacsvox--advice-dictionary-after)

(defun emacsvox--advice-dictionary-close-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-close)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'dictionary-close :after
            #'emacsvox--advice-dictionary-close-after)

(defun emacsvox--advice-dictionary-select-dictionary-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-select-dictionary)
    (emacsvox-icon 'select-object) (message "Selected dictionary")))

(advice-add 'dictionary-select-dictionary :after
            #'emacsvox--advice-dictionary-select-dictionary-after)

(defun emacsvox--advice-dictionary-select-strategy-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-select-strategy)
    (emacsvox-icon 'select-object) (message "Selected strategy")))

(advice-add 'dictionary-select-strategy :after
            #'emacsvox--advice-dictionary-select-strategy-after)

(defun emacsvox--advice-dictionary-search-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-search)
    (emacsvox-icon 'search-hit) (emacsvox-speak-line)))

(advice-add 'dictionary-search :after
            #'emacsvox--advice-dictionary-search-after)

(defun emacsvox--advice-dictionary-lookup-definition-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-lookup-definition)
    (emacsvox-icon 'search-hit) (emacsvox-speak-line)))

(advice-add 'dictionary-lookup-definition :after
            #'emacsvox--advice-dictionary-lookup-definition-after)

(defun emacsvox--advice-dictionary-match-words-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-match-words)
    (emacsvox-icon 'search-hit) (emacsvox-speak-line)))

(advice-add 'dictionary-match-words :after
            #'emacsvox--advice-dictionary-match-words-after)

(defun emacsvox--advice-dictionary-previous-after (&rest _)
  "speak."
  (when (ems-interactive-p 'dictionary-previous)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'dictionary-previous :after
            #'emacsvox--advice-dictionary-previous-after)

(provide 'emacsvox-dictionary)
;;;  end of file
