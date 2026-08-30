;;; emacsvox-make-mode.el --- Speech enable make  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Make
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

;; This module speech enables make-mode

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'make-mode)

;; Emacs 30.1 retired the Makefile target browser in favor of Imenu.
(keymap-set makefile-mode-map "C-c C-b" #'imenu)

;;;  advice

(defun emacsvox--advice-makefile-next-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-next-dependency)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-next-dependency :after
            #'emacsvox--advice-makefile-next-dependency-after)

(defun emacsvox--advice-makefile-previous-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-previous-dependency)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-previous-dependency :after
            #'emacsvox--advice-makefile-previous-dependency-after)

(defun emacsvox--advice-makefile-backslash-region-after
    (from to &rest _)
  "Speak how many lines we backslashed"
  (when (ems-interactive-p 'makefile-backslash-region)
    (message "Backslashed region containing %s lines"
             (count-lines from to))
    (emacsvox-icon 'select-object)))

(advice-add 'makefile-backslash-region :after
            #'emacsvox--advice-makefile-backslash-region-after)

;;;  personalities 

(voice-setup-add-map
 '(
   (makefile-space voice-monotone-extra)
   (makefile-targets voice-bolden)
   (makefile-shell voice-animate)
   (makefile-makepp-perl voice-smoothen)
   ))

;;;  setup mode hook:

(provide 'emacsvox-make-mode)

;;; emacsvox-make-mode.el ends here
