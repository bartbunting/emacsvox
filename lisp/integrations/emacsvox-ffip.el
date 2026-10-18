;;; emacsvox-ffip.el --- Speech-enable FFIP  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop ffip
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
;;; FFIP ==  find-file-in-project

;;; Code:

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defconst emacsvox-ffip--advice-targets
  '(find-file-in-project ffip
    find-file-in-project-at-point
    find-file-in-project-by-selected)
  "Current FFIP commands that receive native advice.")

(dolist (target emacsvox-ffip--advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Provide speech feedback after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-icon 'open-object)
          (emacsvox-speak-mode-line))))))

(defun emacsvox-ffip--install-advice ()
  "Install native advice after FFIP loads."
  (dolist (target emacsvox-ffip--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'find-file-in-project
  (emacsvox-ffip--install-advice))

(provide 'emacsvox-ffip)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-ffip.el ends here
