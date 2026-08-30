;;; emacsvox-flymake.el --- Speech-enable FLYMAKE  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop flymake
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
;; Speech-enable flymake

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'flymake)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (flymake-error voice-monotone)
   (flymake-note voice-smoothen)
   (flymake-warning voice-animate)))

;;;  Interactive Commands:

(cl-loop
 for target in
 '(flymake-goto-diagnostic
   flymake-goto-next-error
   flymake-goto-prev-error)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Flymake navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-flymake-proc-compile-after (&rest _)
  "Cue completion after an interactive legacy Flymake compilation."
  (when (ems-interactive-p 'flymake-proc-compile)
    (emacsvox-icon 'task-done)))

(with-eval-after-load 'flymake-proc
  (advice-add 'flymake-proc-compile :after
              #'emacsvox--advice-flymake-proc-compile-after))

(provide 'emacsvox-flymake)

;;; emacsvox-flymake.el ends here
