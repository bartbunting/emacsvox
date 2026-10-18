;;; emacsvox-orgalist.el --- Speech-enable ORGALIST -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop orgalist
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
;; Speech-enable orgalist --- create org-like lists everywhere.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-orgalist--advice-targets
  '(orgalist--cycle-indentation orgalist-check-item orgalist-cycle-bullet
    orgalist-indent-item orgalist-indent-item-tree orgalist-insert-item
    orgalist-insert-radio-list orgalist-move-item-down orgalist-move-item-up
    orgalist-next-item orgalist-outdent-item orgalist-outdent-item-tree
    orgalist-previous-item)
  "Current Orgalist commands that receive native advice.")

(dolist (target emacsvox-orgalist--advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Provide speech feedback after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-speak-line)
          (emacsvox-icon 'select-object))))))

(defun emacsvox-orgalist--install-advice ()
  "Install native advice after Orgalist loads."
  (dolist (target emacsvox-orgalist--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'orgalist
  (emacsvox-orgalist--install-advice))

(provide 'emacsvox-orgalist)

;;; emacsvox-orgalist.el ends here
