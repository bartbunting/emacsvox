;;; emacsvox-autoload.el --- Autoload Generator  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop autoload
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
;; generate autoloads for emacsvox
;;; Code:

(require 'loaddefs-gen)

(defvar emacsvox-auto-autoloads-file
  (expand-file-name "emacsvox-loaddefs.el"
                    (file-name-directory load-file-name))
  "File that holds automatically generated autoloads for Emacsvox.")

(defun emacsvox-auto-generate-autoloads ()
  "Generate emacsvox autoloads."
  (loaddefs-generate
   emacsvox-lisp-directory emacsvox-auto-autoloads-file))

(provide 'emacsvox-autoload)

;;; emacsvox-autoload.el ends here
