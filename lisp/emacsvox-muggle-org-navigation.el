;;; emacsvox-muggle-org-navigation.el --- Org heading navigation Muggle -*- lexical-binding: t; -*-

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
;; Independently loadable heading navigation, extracted from extra-muggles.
;; This library defines commands without installing entry keys.  The managed
;; entry is optional; direct M-x use remains available in Org buffers.
;;; Code:

(require 'org)
(require 'hydra)
(require 'emacsvox-hydra)
(require 'emacsvox-outline)

(defvar emacsvox-muggle-org-navigation--hint-state nil
  "Hint state captured during this Muggle's active visit.")

(defun emacsvox-muggle-org-navigation--begin ()
  "Announce entry and temporarily quiet automatic Hydra hints."
  (emacsvox-hydra-body-pre "Org heading navigation")
  (setq emacsvox-muggle-org-navigation--hint-state (list hydra-is-helpful)
        hydra-is-helpful nil))

(defun emacsvox-muggle-org-navigation--restore ()
  "Restore temporary hint state unless it was changed during the visit."
  (when emacsvox-muggle-org-navigation--hint-state
    (unless hydra-is-helpful
      (setq hydra-is-helpful (car emacsvox-muggle-org-navigation--hint-state)))
    (setq emacsvox-muggle-org-navigation--hint-state nil)))

(defun emacsvox-muggle-org-navigation--finish ()
  "Restore visit state before normal Hydra exit feedback."
  (emacsvox-muggle-org-navigation--restore)
  (emacsvox-hydra-post))

(defhydra emacsvox-muggles-org-nav
  (:body-pre (emacsvox-muggle-org-navigation--begin)
   :hint nil :pre emacsvox-hydra-pre
   :post emacsvox-muggle-org-navigation--finish :color red :columns 3)
  "Org heading navigation"
  ("?" (emacsvox-hydra-self-help "emacsvox-muggles-org-nav") "help")
  ("SPC" emacsvox-outline-speak-this-heading "speak section")
  ("n" emacsvox-outline-speak-next-heading "next section")
  ("p" emacsvox-outline-speak-previous-heading "previous section")
  ("f" org-forward-heading-same-level "next at same level")
  ("b" org-backward-heading-same-level "previous at same level")
  ("u" outline-up-heading "parent heading")
  ("g" org-goto "go to heading" :exit t)
  ("q" nil "quit" :exit t))

(defun emacsvox-muggle-org-navigation--enter (original &rest arguments)
  "Validate context before ORIGINAL and restore visit state on failure."
  (unless (derived-mode-p 'org-mode)
    (user-error "Org heading navigation requires an Org buffer"))
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-org-navigation--restore)
     (signal (car err) (cdr err)))))

(advice-add 'emacsvox-muggles-org-nav/body :around
            #'emacsvox-muggle-org-navigation--enter)

(provide 'emacsvox-muggle-org-navigation)
;;; emacsvox-muggle-org-navigation.el ends here
