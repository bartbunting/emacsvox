;;; emacsvox-calc.el --- Speech enable Calc   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, calculator, accessibility
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
;; This module extends the Emacs Calculator.
;; Extensions are minimal.
;; We force a calc-load-everything,
;; And use an after advice on this function
;; To fix all of calc's interactive functions
;;; Code:

;;  required modules
(require 'emacsvox-preamble)
(require 'calc)

;;;   advice calc interaction 

(defun emacsvox--advice-calc-dispatch-after (&rest _)
  "speak."
  (when (ems-interactive-p 'calc-dispatch)
    (emacsvox-icon 'open-object)))

(advice-add 'calc-dispatch :after
            #'emacsvox--advice-calc-dispatch-after)

(defun emacsvox--advice-calc-quit-after (&rest _)
  "Announce the buffer that becomes current when calc is quit."
  (when (ems-interactive-p 'calc-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'calc-quit :after #'emacsvox--advice-calc-quit-after)

;;;   speak output 

(defun emacsvox--advice-calc-call-last-kbd-macro-around
    (orig-fun &rest args)
  "Speak."
  (if (ems-interactive-p 'calc-call-last-kbd-macro)
      (let ((result
             (ems-with-messages-silenced
               (apply orig-fun args))))
        (tts-with-punctuations 'all
          (emacsvox-read-previous-line))
        (emacsvox-icon 'task-done)
        result)
    (apply orig-fun args)))

(with-eval-after-load 'calc-prog
  (advice-add 'calc-call-last-kbd-macro :around
              #'emacsvox--advice-calc-call-last-kbd-macro-around))

(defun emacsvox--advice-calc-do-around (orig-fun &rest args)
  "Speak previous line of output."
  (let ((result
         (ems-with-messages-silenced
           (apply orig-fun args))))
    (tts-with-punctuations 'all (emacsvox-read-previous-line)
                           (emacsvox-icon 'select-object))
    result))

(advice-add 'calc-do :around #'emacsvox--advice-calc-do-around)

(defun emacsvox--advice-calc-trail-here-after (&rest _)
  "Speak previous line of output." (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(advice-add 'calc-trail-here :after
            #'emacsvox--advice-calc-trail-here-after)

(provide 'emacsvox-calc)

;;; emacsvox-calc.el ends here
