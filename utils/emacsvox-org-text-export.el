;;; emacsvox-org-text-export.el --- Export the Org manual as plain text -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Author: Lubos Pintes <lubos.pintes@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: docs
;; URL: https://github.com/bartbunting/emacsvox
;;
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

;; Export the canonical Org manual to UTF-8 text with Org's standard ASCII
;; backend.  Keys, literals and links are authored as ordinary Org markup.

;;; Code:

(require 'emacsvox-org-export)
(require 'org)
(require 'ox-ascii)
(require 'subr-x)

(defun emacsvox-org-text-export (source output)
  "Export Org SOURCE as UTF-8 text OUTPUT and return OUTPUT."
  (let* ((source (expand-file-name source))
         (output (expand-file-name output)))
    (unless (file-regular-p source)
      (error "Org manual source is not a regular file: %s" source))
    (make-directory (file-name-directory output) t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source
            default-directory (file-name-directory source))
      (delay-mode-hooks (org-mode))
      (let ((org-export-time-stamp-file nil)
            (org-export-use-babel nil)
            (coding-system-for-write 'utf-8-unix))
        (org-export-to-file 'ascii output nil nil nil nil
                            '(:ascii-charset utf-8
                              :with-broken-links nil))))
    output))

(defun emacsvox-org-text-export-batch ()
  "Export the Org manual named by the batch environment as text."
  (condition-case condition
      (message "Exported Org manual to %s"
               (emacsvox-org-text-export
                (emacsvox-org-export--required-environment
                 "EMACSVOX_ORG_SOURCE")
                (emacsvox-org-export--required-environment
                 "EMACSVOX_ORG_OUTPUT")))
    (error
     (message "Org manual text export failed: %s"
              (error-message-string condition))
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(provide 'emacsvox-org-text-export)
;;; emacsvox-org-text-export.el ends here
