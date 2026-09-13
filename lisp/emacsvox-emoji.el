;;; emacsvox-emoji.el --- Conservative emoji speech names -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
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

;; Optional speech naming uses exact entries from Emacs's bundled emoji data.
;; Keep the private upstream table behind this adapter; never use the picker
;; helper, which can fall back to naming the first character of a sequence.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar emoji--names)

(defun emacsvox-emoji--lookup (sequence)
  "Return exact name and data evidence for SEQUENCE, or a diagnostic.
Failures are data, never speech errors.  No network or display is involved."
  (condition-case nil
      (if (and (stringp sequence)
               (require 'emoji-labels nil t)
               (boundp 'emoji--names)
               (hash-table-p emoji--names)
               (eq (hash-table-test emoji--names) 'equal))
          (let ((name (gethash sequence emoji--names)))
            (if (and (stringp name) (not (string-empty-p name)))
                (list :name (substring-no-properties name)
                      :emacs-version emacs-version
                      :data-file (symbol-file 'emoji--names 'defvar))
              (list :diagnostic 'missing-name)))
        (list :diagnostic 'unavailable-data))
    (error (list :diagnostic 'unavailable-data))))

(provide 'emacsvox-emoji)
;;; emacsvox-emoji.el ends here
