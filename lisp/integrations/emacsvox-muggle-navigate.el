;;; emacsvox-muggle-navigate.el --- Repeatable text navigation Muggle -*- lexical-binding: t; -*-

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
;; Repeatable text navigation, independently loadable without entry bindings.
;; Deliberate entry preserves the legacy initial next-line action.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)

(defvar emacsvox-muggle-navigate--hint-state nil
  "Original and temporary hint values for the active visit.")

(defun emacsvox-muggle-navigate--begin ()
  "Announce entry, temporarily toggle hints and move down one line."
  (emacsvox-hydra-body-pre "Navigator")
  (setq emacsvox-muggle-navigate--hint-state
        (list hydra-is-helpful (not hydra-is-helpful)))
  (emacsvox-hydra-toggle-talkative)
  (condition-case nil (call-interactively #'next-line) (error nil)))

(defun emacsvox-muggle-navigate--restore ()
  "Restore temporary hints unless changed during the visit."
  (when emacsvox-muggle-navigate--hint-state
    (when (eq hydra-is-helpful (cadr emacsvox-muggle-navigate--hint-state))
      (setq hydra-is-helpful (car emacsvox-muggle-navigate--hint-state)))
    (setq emacsvox-muggle-navigate--hint-state nil)))

(defun emacsvox-muggle-navigate--finish ()
  "Restore hints and provide normal exit feedback."
  (emacsvox-muggle-navigate--restore)
  (emacsvox-hydra-post))

(defhydra emacsvox-muggles-navigate
  (:body-pre (emacsvox-muggle-navigate--begin)
   :hint nil :pre emacsvox-hydra-pre :post emacsvox-muggle-navigate--finish)
  "Navigator"
  ("?" (emacsvox-hydra-self-help "emacsvox-muggles-navigate"))
  ("s" emacsvox-hydra-toggle-talkative "quiet")
  ("n" next-line "next")
  ("p" previous-line "previous")
  ("f" forward-char)
  ("b" backward-char)
  ("a" beginning-of-line)
  ("e" move-end-of-line)
  ("j" next-line)
  ("k" previous-line)
  ("v" scroll-up-command)
  ("V" scroll-down-command)
  ("l" recenter-top-bottom)
  ("<" beginning-of-buffer)
  (">" end-of-buffer)
  ("q" nil "quit" :exit t))

(defun emacsvox-muggle-navigate--keep-hints (&rest _)
  "Keep an explicit hint choice when leaving this menu."
  (setq emacsvox-muggle-navigate--hint-state nil))

(advice-add 'emacsvox-muggles-navigate/emacsvox-hydra-toggle-talkative :after
            #'emacsvox-muggle-navigate--keep-hints)

(defun emacsvox-muggle-navigate--enter (original &rest arguments)
  "Run ORIGINAL, restoring temporary hint state if entry fails."
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-navigate--restore)
     (signal (car err) (cdr err)))))

(advice-add 'emacsvox-muggles-navigate/body :around
            #'emacsvox-muggle-navigate--enter)
(provide 'emacsvox-muggle-navigate)
;;; emacsvox-muggle-navigate.el ends here
