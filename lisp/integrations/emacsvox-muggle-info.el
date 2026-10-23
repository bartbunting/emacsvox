;;; emacsvox-muggle-info.el --- Info summary Muggle -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop muggles
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
;; Info summary Muggle without installing entry keys.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)
(require 'info)

(defhydra emacsvox-muggles-info-summary
                      (
                       :color blue :hint nil
                       :body-pre (emacsvox-hydra-body-pre "Info Summary")
                       :pre
                       emacsvox-hydra-pre
                       :post emacsvox-hydra-post)
                      "info mode"
                      ("]"   Info-forward-node)
                      ("["   Info-backward-node)
                      ("n"   Info-next)
                      ("p"   Info-prev)
                      ("s"   Info-search)
                      ("S"   Info-search-case-sensitively)

                      ("l"   Info-history-back)
                      ("r"   Info-history-forward)
                      ("H"   Info-history)
                      ("t"   Info-top-node)
                      ("<"   Info-top-node)
                      (">"   Info-final-node)

                      ("u"   Info-up)
                      ("^"   Info-up)
                      ("m"   Info-menu)
                      ("g"   Info-goto-node)
                      ("b"   beginning-of-buffer)
                      ("e"   end-of-buffer)

                      ("f"   Info-follow-reference)
                      ("i"   Info-index)
                      (","   Info-index-next)
                      ("I"   Info-virtual-index)

                      ("T"   Info-toc)
                      ("d"   Info-directory)
                      ("c"   Info-copy-current-node-name)
                      ("C"   clone-buffer)
                      ("a"   info-apropos)

                      ("1"   Info-nth-menu-item)
                      ("2"   Info-nth-menu-item)
                      ("3"   Info-nth-menu-item)
                      ("4"   Info-nth-menu-item)
                      ("5"   Info-nth-menu-item)
                      ("6"   Info-nth-menu-item)
                      ("7"   Info-nth-menu-item)
                      ("8"   Info-nth-menu-item)
                      ("9"   Info-nth-menu-item)

                      ("?"   Info-summary "Info summary")
                      ("h"   Info-help "Info help")
                      ("q"   quit-window "Info exit")
                      ("C-g" nil "cancel" :color blue))

(defun emacsvox-muggle-info--enter (original &rest arguments)
  "Run ORIGINAL only in an Info buffer."
  (unless (derived-mode-p 'Info-mode)
    (user-error "Info summary requires an Info buffer"))
  (apply original arguments))
(advice-add 'emacsvox-muggles-info-summary/body :around
            #'emacsvox-muggle-info--enter)

(provide 'emacsvox-muggle-info)
;;; emacsvox-muggle-info.el ends here
