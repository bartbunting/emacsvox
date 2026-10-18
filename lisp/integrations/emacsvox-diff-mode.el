;;; emacsvox-diff-mode.el --- Speech-enable DIFF -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop diff-mode
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
;; DIFF-MODE  support.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Faces from  diff-mode.el

(voice-setup-add-map
 '(
   (diff-added voice-brighten)
   (diff-changed voice-animate)
   (diff-context voice-monotone-extra)
   (diff-file-header voice-bolden)
   (diff-function voice-smoothen)
   (diff-header voice-bolden-extra)
   (diff-hunk-header voice-bolden-medium)
   (diff-index voice-monotone-extra)
   (diff-indicator-added voice-animate)
   (diff-indicator-changed voice-lighten)
   (diff-indicator-removed voice-smoothen)
   (diff-nonexistent voice-monotone-extra)
   (diff-refine-added voice-lighten)
   (diff-refine-changed voice-brighten-medium)
   (diff-refine-removed voice-smoothen)
   (diff-removed voice-smoothen-extra)))

;;;  Advice Interactive Commands:

(cl-loop
 for target in
 '(diff-next-complex-hunk
   diff-hunk-prev diff-hunk-next
   diff-file-next diff-file-prev)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Diff Mode navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(provide 'emacsvox-diff-mode)

;;; emacsvox-diff-mode.el ends here
