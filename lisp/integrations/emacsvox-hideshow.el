;;; emacsvox-hideshow.el --- speech-enable hideshow -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; speech-enable hideshow.el
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'hideshow)

;;;  speech enable interactive commands 

(defun emacsvox--advice-hs-hide-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-all)
    (emacsvox-icon 'close-object) (message "Hid all blocks.")))

(advice-add 'hs-hide-all :after
            #'emacsvox--advice-hs-hide-all-after)

(defun emacsvox--advice-hs-show-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-show-all)
    (emacsvox-icon 'open-object) (message "Exposed all blocks.")))

(advice-add 'hs-show-all :after
            #'emacsvox--advice-hs-show-all-after)

(defun emacsvox--advice-hs-hide-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-block)
    (emacsvox-icon 'close-object) (message "Hid current block.")))

(advice-add 'hs-hide-block :after
            #'emacsvox--advice-hs-hide-block-after)

(defun emacsvox--advice-hs-show-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-show-block)
    (emacsvox-icon 'open-object) (message "Exposed current  block.")))

(advice-add 'hs-show-block :after
            #'emacsvox--advice-hs-show-block-after)

(defun emacsvox--advice-hs-hide-level-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-level)
    (emacsvox-icon 'close-object)
    (message "Hid all blocks below specified level.")))

(advice-add 'hs-hide-level :after
            #'emacsvox--advice-hs-hide-level-after)

(defun emacsvox--advice-hs-toggle-hiding-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-toggle-hiding)
    (cond
     ((hs-already-hidden-p) (emacsvox-icon 'close-object)
      (message "Hid block"))
     (t (emacsvox-icon 'open-object) (message "Exposed block")))))

(advice-add 'hs-toggle-hiding :after
            #'emacsvox--advice-hs-toggle-hiding-after)

(defun emacsvox--advice-hs-hide-initial-comment-block-after (&rest _)
  "speak."
  (when (ems-interactive-p 'hs-hide-initial-comment-block)
    (emacsvox-icon 'close-object)
    (message "Hid initial comment block.")))

(advice-add 'hs-hide-initial-comment-block :after
            #'emacsvox--advice-hs-hide-initial-comment-block-after)

(provide 'emacsvox-hideshow)

;;; emacsvox-hideshow.el ends here
