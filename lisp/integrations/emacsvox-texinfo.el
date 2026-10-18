;;; emacsvox-texinfo.el --- Speech enable texinfo -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, texinfo
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

;; This module speech enables net-texinfo mode

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'texinfo)

;;;  voice locking

(defun emacsvox-texinfo-mode-hook ()
  "Setup Emacsvox extensions"
  
  (tts-apply-punctuation-mode-policy)
  (or tts-split-caps
      (tts-toggle-split-caps))
  (or emacsvox-audio-indentation
      (emacsvox-toggle-audio-indentation)))

(add-hook 'texinfo-mode-hook 'emacsvox-texinfo-mode-hook)

;;;  advice

(defun emacsvox--advice-texinfo-insert-@end-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@end)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@end :after
            #'emacsvox--advice-texinfo-insert-@end-after)

(defun emacsvox--advice-texinfo-insert-block-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-block)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-block :after
            #'emacsvox--advice-texinfo-insert-block-after)

(defun emacsvox--advice-texinfo-insert-@item-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@item)
    (emacsvox-icon 'item) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@item :after
            #'emacsvox--advice-texinfo-insert-@item-after)

(defun emacsvox--advice-texinfo-insert-@node-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@node)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@node :after
            #'emacsvox--advice-texinfo-insert-@node-after)

(provide 'emacsvox-texinfo)

;;; emacsvox-texinfo.el ends here
