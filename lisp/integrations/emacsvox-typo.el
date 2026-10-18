;;; emacsvox-typo.el --- Speech-enable TYPO  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop typo
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
;; TYPO == Typographical Editing This module speech-enables typo-mode.
;; Typo-mode's magic insertion commands are speech-enabled to speak
;; the inserted char.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-typo--advice-targets
  '(typo-insert-quotation-mark typo-cycle-dashes typo-cycle-ellipsis
    typo-cycle-left-angle-brackets typo-cycle-left-single-quotation-mark
    typo-cycle-multiplication-signs typo-cycle-right-angle-brackets
    typo-cycle-right-single-quotation-mark typo-cycle-spaces)
  "Current Typo commands that receive native advice.")

(dolist (target emacsvox-typo--advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Speak the character inserted by `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-speak-this-char (preceding-char)))))))

(defun emacsvox-typo--install-advice ()
  "Install native advice after Typo loads."
  (dolist (target emacsvox-typo--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'typo
  (emacsvox-typo--install-advice))

(provide 'emacsvox-typo)

;;; emacsvox-typo.el ends here
