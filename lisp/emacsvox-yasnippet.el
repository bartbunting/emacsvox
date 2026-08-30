;;; emacsvox-yasnippet.el --- YASNIPPET  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop yasnippet
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
;; YASNIPPET ==  Template based editing using snippets.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map personalities:

(voice-setup-add-map '((yas-field-highlight-face voice-animate)))

;;;  Advice interactive commands:

(defconst emacsvox-yasnippet--field-targets
  '(yas-prev-field
    yas-expand
    yas-next-field
    yas-next-field-or-maybe-expand)
  "Yasnippet commands that move or expand fields.")

(cl-loop
 for target in emacsvox-yasnippet--field-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "provide feedback"
     (let ((emacsvox-show-point t))
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(defun emacsvox--advice-yas-insert-snippet-after (&rest _)
  "Speak inserted template."
  (when (ems-interactive-p 'yas-insert-snippet)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(defconst emacsvox-yasnippet--advice-targets
  (append emacsvox-yasnippet--field-targets '(yas-insert-snippet))
  "Current Yasnippet targets that receive native after advice.")

(defun emacsvox-yasnippet--install-advice ()
  "Install advice after the optional Yasnippet package loads."
  (dolist (target emacsvox-yasnippet--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'yasnippet
  (emacsvox-yasnippet--install-advice))

(provide 'emacsvox-yasnippet)

;;; emacsvox-yasnippet.el ends here
