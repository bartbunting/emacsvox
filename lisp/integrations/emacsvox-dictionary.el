;;; emacsvox-dictionary.el --- dictionaries  -*- lexical-binding: t; -*- 

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Speech-enables emacs client for accessing dictionary
;; server at dict.org:2628
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'dictionary)

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

;;; emacsvox-dictionary.el ends here
