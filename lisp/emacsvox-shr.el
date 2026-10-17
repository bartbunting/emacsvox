;;; emacsvox-shr.el --- Speech-enable shared HTML link navigation  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop shr
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
;;
;; Provide link navigation feedback for all SHR clients, including HTML mail,
;; without loading EWW.  EWW's existing specialised link speaker remains
;; available when that integration is loaded.

;;; Code:

(require 'emacsvox-preamble)
(require 'shr)

(defvar-local emacsvox-eww-a-speaker nil
  "Specialized link speaker.")

(defun emacsvox--advice-shr-link-message-around (original &rest arguments)
  "Keep SHR's URL echo visible without speaking a duplicate notification."
  (let ((ems--message-filter
         (concat
          (when ems--message-filter
            (concat "\\(?:" ems--message-filter "\\)\\|"))
          "\\`[[:alpha:]][[:alnum:]+.-]*:")))
    (apply original arguments)))

(cl-loop
 for target in
 '(shr-next-link shr-previous-link)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the styled label after interactive HTML link navigation."
       (when (ems-interactive-p ',target)
         (if emacsvox-eww-a-speaker
             (funcall emacsvox-eww-a-speaker)
           (emacsvox-speak-region
            (point)
            (next-single-property-change
             (point) 'help-echo nil (point-max))))))
     (advice-add
      ',target :after #',function '((name . emacsvox)))
     (advice-add
      ',target :around #'emacsvox--advice-shr-link-message-around
      '((name . emacsvox-link-message))))))

(provide 'emacsvox-shr)
;;; emacsvox-shr.el ends here
