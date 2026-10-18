;;; emacsvox-hide-lines.el --- HIDE-LINES  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop hide-lines
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
;; HIDE-LINES ==  hide/show lines from melpa

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-hide-lines--advice-targets
  '(hide-lines hide-lines-show-all
    hide-lines-matching hide-lines-not-matching)
  "Current hide-lines commands that receive native advice.")

(dolist (target emacsvox-hide-lines--advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Provide speech feedback after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-speak-line)
          (emacsvox-icon 'button))))))

(defun emacsvox-hide-lines--install-advice ()
  "Install native advice after hide-lines loads."
  (dolist (target emacsvox-hide-lines--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'hide-lines
  (emacsvox-hide-lines--install-advice))

(provide 'emacsvox-hide-lines)

;;; emacsvox-hide-lines.el ends here
