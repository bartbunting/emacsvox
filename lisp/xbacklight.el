;;; xbacklight.el --- Brightness   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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
;; Provide an emacs front-end to xbacklight.
;; This is a tool that controls the brightness on laptops.
;; To install xbacklight,
;; sudo apt-get install xbacklight

;; This module  is most   easily used in conjunction with  hydra:
;; M-x package-install hydra

;;; Code:

;;;  required packages

(eval-when-compile (require 'cl-lib))

;;;   Variables:

(defconst xbacklight-cmd
  (executable-find "xbacklight")
  "xbacklight executable.")

;;;  Commands:

;;;###autoload
(defun xbacklight-get ()
  "Get  brightness level."
  (interactive)
  
  (when xbacklight-cmd
    (let ((value (shell-command-to-string (format "%s -get " xbacklight-cmd))))
      (cond
       ((= 0 (length value)) (message "XBacklight not supported."))
       ((numberp (read value))
        (message "Brightness is %d" (round  (read value))))
       (t (message "Brightness is %s" value))))))

;;;###autoload
(defun xbacklight-set (brightness)
  "Set brightness."
  (interactive "sBrightness: ")
  
  (when xbacklight-cmd
    (start-process "XBacklight" nil xbacklight-cmd "-set" brightness)))

(defvar xbacklight-step  "10"
  "Step-size used when incrementing and decrementing brightness.")

;;;###autoload
(defun xbacklight-increment ()
  "Increase brightness."
  (interactive)
  (start-process "XBacklight" nil  xbacklight-cmd "-inc" xbacklight-step))

;;;###autoload
(defun xbacklight-decrement ()
  "Decrease brightness."
  (interactive)
  (start-process "XBacklight" nil xbacklight-cmd  "-dec" xbacklight-step))

;;;###autoload
(defun xbacklight-black ()
  "Black screen."
  (interactive)
  (xbacklight-set "0"))

;;;###autoload
(defun xbacklight-white ()
  "White screen."
  (interactive)
  (xbacklight-set "100"))

(provide 'xbacklight)

;;; xbacklight.el ends here
