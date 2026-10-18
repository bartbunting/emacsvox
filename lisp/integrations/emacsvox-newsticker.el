;;; emacsvox-newsticker.el --- newsticker  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, newsticker
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

;; Newsticker provides a continuously updating newsticker using
;; RSS
;; Provides functionality similar to amphetadesk --but in pure elisp

;;  required modules

;;; Code:
(require 'emacsvox-preamble)
(require 'newsticker)

;;;  define personalities 
(voice-setup-add-map
 '(
   (newsticker-new-item-face voice-brighten)
   (newsticker-old-item-face voice-monotone-extra)
   (newsticker-feed-face voice-animate)
   ))

;;;  advice functions

(defmacro emacsvox-newsticker--define-silent-advice (targets)
  "Define once-only message-silencing advice for TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest args)
                 "Run one Newsticker operation without automatic speech."
                 (let ((emacsvox-speak-messages nil))
                   (apply orig-fun args)))
               (advice-add ',target :around #',function))))
        targets)))

(emacsvox-newsticker--define-silent-advice
    (newsticker--cache-remove
     newsticker--get-news-by-url-callback
     newsticker-get-news
     newsticker--cache-save))

;;;  advice interactive commands

(defun emacsvox-newsticker-summarize-item ()
  "Summarize current item."
  (emacsvox-speak-line))

(defmacro emacsvox-newsticker--define-navigation-advice (targets)
  "Define native after advice for Newsticker navigation TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 "Speak the current Newsticker item after navigation."
                 (when (ems-interactive-p ',target)
                   (emacsvox-icon 'large-movement)
                   (emacsvox-newsticker-summarize-item)))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-newsticker--define-navigation-advice
    (newsticker-next-item
     newsticker-previous-item
     newsticker-next-new-item
     newsticker-previous-new-item
     newsticker-previous-feed
     newsticker-next-feed))

(provide 'emacsvox-newsticker)

;;; emacsvox-newsticker.el ends here
