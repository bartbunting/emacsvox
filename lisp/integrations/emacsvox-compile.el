;;; emacsvox-compile.el --- Speech enable compile -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox compile
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

;; This module makes compiling code from inside Emacs speech friendly.
;;; Code:

;;  Required modules: 
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

(defmacro emacsvox-compile--define-interactive-after-advice
    (targets docstring &rest body)
  "Define native interactive after advice for compile TARGETS.
DOCSTRING and BODY define the feedback function for each command."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (advice-add
                ',target :after #',function '((name . emacsvox))))))
        targets)))

;;;  Personalities  
(voice-setup-add-map
 '(
   (compilation-line-number voice-smoothen)
   (compilation-column-number voice-smoothen)
   (compilation-info voice-lighten)
   (compilation-error voice-animate-extra)
   (compilation-warning voice-animate)
   (compilation-mode-line-exit voice-animate)
   (compilation-mode-line-fail voice-brighten)
   (compilation-mode-line-run voice-annotate)))

;;;   functions

(defun emacsvox-compilation-speak-error ()
  "Speech feedback about the compilation error. "
  (interactive)
  (let ((tts-stop-immediately nil)
        (emacsvox-show-point t))
    (emacsvox-speak-line)))

;;;   advice  interactive commands

(emacsvox-compile--define-interactive-after-advice
    (next-error previous-error
     compilation-next-file compilation-previous-file
     compile-goto-error compile-mouse-goto-error)
    "Speak the line containing the compilation error."
  (tts-stop 'all)
  (emacsvox-icon 'large-movement)
  (emacsvox-compilation-speak-error))

(emacsvox-compile--define-interactive-after-advice
    (compilation-next-error compilation-previous-error
     next-error-no-select previous-error-no-select)
    "Speak the selected compilation error."
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

;;;  advise process filter and sentinels

(defun emacsvox--advice-compile-after (&rest _)
  "Confirm an interactively launched compilation."
  (when (ems-interactive-p 'compile)
    (message "Launched compilation")
    (emacsvox-icon 'task-done)))

(advice-add
 'compile :after #'emacsvox--advice-compile-after
 '((name . emacsvox)))

(defun emacsvox--advice-compilation-sentinel-after (process status)
  "Cue completion and report PROCESS and STATUS."
  (emacsvox-icon 'task-done)
  (message "process %s %s" (process-name process) status))

(advice-add
 'compilation-sentinel :after
 #'emacsvox--advice-compilation-sentinel-after
 '((name . emacsvox)))

(provide 'emacsvox-compile)

;;; emacsvox-compile.el ends here
