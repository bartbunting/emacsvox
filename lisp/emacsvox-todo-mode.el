;;; emacsvox-todo-mode.el --- speech-enable todo -*- lexical-binding: t; -*-

;; Copyright (c) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, todo-mode
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
;; todo-mode (part of Emacs 21) provides todo-lists that can be
;; integrated with the Emacs calendar.
;; This module speech-enables todo-mode
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'todo-mode)

;;;   Advice interactive commands:

(cl-loop
 for target in
 '(todo-forward-item
   todo-backward-item
   todo-next-item
   todo-previous-item
   todo-forward-category
   todo-backward-category
   todo-jump-to-category)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Todo navigation operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-speak-line)))
     (advice-add ',target :after #',function))))

(defun emacsvox--advice-todo-save-after (&rest _)
  "speak."
  (when (ems-interactive-p 'todo-save)
    (emacsvox-icon 'save-object)))

(advice-add 'todo-save :after #'emacsvox--advice-todo-save-after)

(defun emacsvox--advice-todo-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'todo-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'todo-quit :after #'emacsvox--advice-todo-quit-after)

(provide 'emacsvox-todo-mode)

;;; emacsvox-todo-mode.el ends here
