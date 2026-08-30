;;; emacsvox-<skeleton>.el --- Speech-enable <SKELETON>  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2022, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop <skeleton>
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
;; <SKELETON> == 

;;; Code:

;;   Required modules

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(let ((print-length 0)
      (faces (emacsvox-wizards-enumerate-unmapped-faces "^<skeleton>"))
      (start (point)))
  (insert "\n\n(voice-setup-add-map \n'(\n")
  (cl-loop for f in faces do 
           (insert (format "(%s)\n" f)))
  (insert "\n)\n)")
  (goto-char start)
  (backward-sexp)
  (kill-sexp)
  (goto-char (search-forward "("))
  (indent-pp-sexp))

;;;  Interactive Commands:

(let ((print-length nil)
      (start (point))
      (commands (emacsvox-wizards-enumerate-uncovered-commands "^<skeleton>")))
  (insert "'(\n")
  (cl-loop for c in commands do (insert (format "%s\n" c)))
  (insert ")\n")
  (goto-char start)
  (backward-sexp)
  (kill-sexp)
  (goto-char (search-forward "("))
  (indent-pp-sexp))

(provide 'emacsvox-<skeleton>)

;;; emacsvox-<skeleton>.el ends here
