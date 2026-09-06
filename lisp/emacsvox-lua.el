;;; emacsvox-lua.el --- Speech-enable LUA  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop lua
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
;; LUA == lua-mode
;; Speech-enable lua-mode.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
;; Built into Emacs 31; an optional package on Emacs 30.
(require 'lua-mode nil t)

;;;  Advice Interactive Commands:
(defmacro emacsvox-lua--define-after-advice
    (targets docstring &rest body)
  "Define native after advice for TARGETS using DOCSTRING and BODY."
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
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-lua--define-after-advice
    (lua-backwards-to-block-begin-or-end
     lua-beginning-of-proc
     lua-end-of-proc
     lua-forward-sexp
     lua-goto-matching-block)
    "Speak the Lua navigation destination."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(defun emacsvox--advice-lua-start-process-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lua-start-process)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-start-process :after
            #'emacsvox--advice-lua-start-process-after)

(defun emacsvox--advice-lua-kill-process-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lua-kill-process)
    (emacsvox-icon 'delete-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-kill-process :after
            #'emacsvox--advice-lua-kill-process-after)

(defun emacsvox--advice-lua-search-documentation-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lua-search-documentation)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-search-documentation :after
            #'emacsvox--advice-lua-search-documentation-after)

(emacsvox-lua--define-after-advice
    (lua-send-buffer
     lua-send-current-line
     lua-send-lua-region
     lua-send-proc
     lua-send-region)
    "Cue an interactive Lua send operation."
  (emacsvox-icon 'task-done))

(defun emacsvox--advice-lua-show-process-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lua-show-process-buffer)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-show-process-buffer :after
            #'emacsvox--advice-lua-show-process-buffer-after)

(provide 'emacsvox-lua)

;;; emacsvox-lua.el ends here
