;;; emacsvox-woman.el --- Speech-enable WOMAN  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop woman, Man Pages
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
;; WOMAN ==  Man pages implemented in Emacs Lisp

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'dired)
(require 'woman nil 'no-error)

;;;  Map faces to voices

(voice-setup-add-map
 '(
   (Man-overstrike   voice-animate)
   (woman-unknown  voice-monotone-extra)
   (woman-edition voice-bolden-medium)
   (woman-bold voice-bolden)
   (woman-italic voice-animate)))

;;;  Advice interactive functions

(defun emacsvox--advice-WoMan-next-manpage-after (&rest _)
  "speak."
  (when (ems-interactive-p 'WoMan-next-manpage)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'WoMan-next-manpage :after
            #'emacsvox--advice-WoMan-next-manpage-after)

(defun emacsvox--advice-WoMan-previous-manpage-after (&rest _)
  "speak."
  (when (ems-interactive-p 'WoMan-previous-manpage)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'WoMan-previous-manpage :after
            #'emacsvox--advice-WoMan-previous-manpage-after)

(provide 'emacsvox-woman)

;;; emacsvox-woman.el ends here
