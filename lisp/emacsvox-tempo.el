;;; emacsvox-tempo.el --- Speech enable tempo  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Spoken Feedback, Template filling, html editing
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
;; tempo.el provides the
;; infrastructure  for building up templates.
;; This is used by html-helper-mode to allow for easy writing of HTML
;; This module extends Emacsvox to provide fluent spoken feedback
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'tempo)

;;;   First setup tempo variables:

;; Prompting in the minibuffer is useful:

(cl-declaim  (special tempo-interactive))
(setq tempo-interactive t)
(add-hook
 'tempo-insert-string-hook
 #'(lambda (string)
     (tts-speak string)
     string))

;;;   Advice: 

(defun emacsvox--advice-tempo-forward-mark-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'tempo-forward-mark)
    (emacsvox-speak-line)))

(advice-add 'tempo-forward-mark :after
            #'emacsvox--advice-tempo-forward-mark-after)

(defun emacsvox--advice-tempo-backward-mark-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'tempo-backward-mark)
    (emacsvox-speak-line)))

(advice-add 'tempo-backward-mark :after
            #'emacsvox--advice-tempo-backward-mark-after)

(defun emacsvox--advice-html-helper-smart-insert-item-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'html-helper-smart-insert-item)
    (emacsvox-speak-line)))

(with-eval-after-load 'html-helper-mode
  (advice-add 'html-helper-smart-insert-item :after
              #'emacsvox--advice-html-helper-smart-insert-item-after))

(emacsvox-pronounce-add-super 'sgml-mode 'html-helper-mode)

(provide 'emacsvox-tempo)

;;; emacsvox-tempo.el ends here
