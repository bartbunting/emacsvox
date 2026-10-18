;;; emacsvox-net-utils.el --- net-utils  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, network utilities
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

;; This module speech enables net-utils
;;; Code:
;;;  requires
(require 'emacsvox-preamble)
(require 'net-utils)

;;;  advice

(cl-loop
 for target in
 '(
   arp route traceroute
   ifconfig iwconfig ping netstat
   dns-lookup-host nslookup-host)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Announce results after an interactive network utility command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (message "Displayed results of %s in other window" ',target)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(provide 'emacsvox-net-utils)

;;; emacsvox-net-utils.el ends here
