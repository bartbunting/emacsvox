;;; emacsvox-dumb-jump.el --- DUMB-JUMP  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop dumb-jump
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
;; DUMB-JUMP ==  Jump to imputed cross-references  in source code.
;; This module speech-enables dumb-jump

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-dumb-jump--advice-targets
  '(dumb-jump-back
    dumb-jump-go
    dumb-jump-go-current-window
    dumb-jump-go-other-window
    dumb-jump-go-prefer-external
    dumb-jump-go-prefer-external-other-window
    dumb-jump-go-prompt)
  "Current Dumb Jump commands that receive speech feedback.")

(cl-loop
 for target in emacsvox-dumb-jump--advice-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))
       (emacsvox-icon 'large-movement)))))

(defun emacsvox-dumb-jump--install-advice ()
  "Install native advice after the optional Dumb Jump package loads."
  (dolist (target emacsvox-dumb-jump--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'dumb-jump
  (emacsvox-dumb-jump--install-advice))

(provide 'emacsvox-dumb-jump)

;;; emacsvox-dumb-jump.el ends here
