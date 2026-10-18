;;; emacsvox-go-mode.el --- Speech-enable GO-MODE  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop go-mode
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
;; GO-MODE ==  Go Language support in emacs

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice interactive commands:

(defvar emacsvox-go-mode--advice nil
  "Current Go mode targets and their native advice functions.")
(setq emacsvox-go-mode--advice nil)

(defun emacsvox-go-mode--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-go-mode--advice))))

(defun emacsvox-go-mode--selection-feedback ()
  "Speak the selected Go source line."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-go-mode--register-after-group
 '(go-goto-imports go-import-add godef-jump godef-jump-other-window
   go-mode-indent-line go-mode-insert-and-indent)
 #'emacsvox-go-mode--selection-feedback)

(defun emacsvox-go-mode--task-feedback ()
  "Play the task completion icon."
  (emacsvox-icon 'task-done))

(emacsvox-go-mode--register-after-group
 '(godoc gofmt)
 #'emacsvox-go-mode--task-feedback)

(defun emacsvox-go-mode--install-advice ()
  "Install native advice after Go mode loads."
  (dolist (entry emacsvox-go-mode--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'go-mode
  (emacsvox-go-mode--install-advice))

(provide 'emacsvox-go-mode)

;;; emacsvox-go-mode.el ends here
