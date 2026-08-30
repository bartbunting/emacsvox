;;; emacsvox-windmove.el --- windmove  -*- lexical-binding: t; -*- 

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, windmove
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

;; Package  windmove (bundled with Emacs 21)
;; provides commands for navigating to windows based on
;; relative position.
;; 

;;  required modules

;;; Code:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  advice window navigation

(cl-loop
 for target in '(windmove-left windmove-right windmove-up windmove-down)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak the window selected by an interactive windmove command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(provide 'emacsvox-windmove)

;;; emacsvox-windmove.el ends here
