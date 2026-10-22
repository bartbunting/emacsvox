;;; emacsvox-muggle-org-table.el --- Org table editing Muggle -*- lexical-binding: t; -*-

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
;; Native Org table commands, independently loadable without entry bindings.
;; These commands retain Org's editing, realignment and row-creation behavior.
;;; Code:
(require 'org)
(require 'hydra)
(require 'emacsvox-hydra)
(require 'emacsvox-org)

(defvar emacsvox-muggle-org-table--hint-state nil
  "Hint state captured during this Muggle's active visit.")

(defun emacsvox-muggle-org-table--begin ()
  "Announce entry and temporarily quiet automatic hints."
  (emacsvox-hydra-body-pre "Org table editing")
  (setq emacsvox-muggle-org-table--hint-state (list hydra-is-helpful)
        hydra-is-helpful nil))

(defun emacsvox-muggle-org-table--restore ()
  "Restore temporary hints unless they were changed during this visit."
  (when emacsvox-muggle-org-table--hint-state
    (unless hydra-is-helpful
      (setq hydra-is-helpful (car emacsvox-muggle-org-table--hint-state)))
    (setq emacsvox-muggle-org-table--hint-state nil)))

(defun emacsvox-muggle-org-table--finish ()
  "Restore hints and provide normal exit feedback."
  (emacsvox-muggle-org-table--restore)
  (emacsvox-hydra-post))

(defhydra emacsvox-muggles-org-table
  (:body-pre (emacsvox-muggle-org-table--begin)
   :pre emacsvox-hydra-pre :post emacsvox-muggle-org-table--finish)
  "Org table editing"
  ("?" (emacsvox-hydra-self-help "emacsvox-muggles-org-table"))
  ("j" org-table-next-row)
  ("k" org-table-previous-row)
  ("h" org-table-previous-field)
  ("l" org-table-next-field)
  ("SPC" emacsvox-org-table-speak-current-element)
  ("." emacsvox-org-table-speak-coordinates)
  ("b" emacsvox-org-table-speak-both-headers-and-element)
  ("r" emacsvox-org-table-speak-row-header-and-element)
  ("c" emacsvox-org-table-speak-column-header-and-element)
  ("q" nil "quit" :exit t))

(defun emacsvox-muggle-org-table--enter (original &rest arguments)
  "Validate the table before ORIGINAL; restore temporary state on failure."
  (unless (and (derived-mode-p 'org-mode) (org-at-table-p))
    (user-error "Org table editing requires a table in an Org buffer"))
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-org-table--restore)
     (signal (car err) (cdr err)))))

(advice-add 'emacsvox-muggles-org-table/body :around
            #'emacsvox-muggle-org-table--enter)
(provide 'emacsvox-muggle-org-table)
;;; emacsvox-muggle-org-table.el ends here
