;;; emacsvox-muggle-view.el --- View navigation Muggle -*- lexical-binding: t; -*-

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
;; View-style navigation and reading without enabling View mode or entry keys.
;; Temporary hints are restored unless explicitly changed during the visit.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)
(require 'view)

(defvar emacsvox-muggle-view--hint-state nil
  "Original and temporary hint values for the active visit.")

(defun emacsvox-muggle-view--begin ()
  "Temporarily toggle hints and announce View navigation."
  (setq emacsvox-muggle-view--hint-state
        (list hydra-is-helpful (not hydra-is-helpful)))
  (emacsvox-hydra-toggle-talkative)
  (emacsvox-hydra-body-pre "View"))

(defun emacsvox-muggle-view--restore ()
  "Restore temporary hints unless changed during the visit."
  (when emacsvox-muggle-view--hint-state
    (when (eq hydra-is-helpful (cadr emacsvox-muggle-view--hint-state))
      (setq hydra-is-helpful (car emacsvox-muggle-view--hint-state)))
    (setq emacsvox-muggle-view--hint-state nil)))

(defun emacsvox-muggle-view--finish ()
  "Restore hints and provide normal exit feedback."
  (emacsvox-muggle-view--restore)
  (emacsvox-hydra-post))

(defhydra emacsvox-muggles-view
          (:body-pre
           (emacsvox-muggle-view--begin)
           :hint nil
           :pre emacsvox-hydra-pre :post emacsvox-muggle-view--finish)
          "View Mode"
          ("?" (emacsvox-hydra-self-help "emacsvox-muggles-view"))
          ("$" set-selective-display)
          ("%"  View-goto-percent)
          ("'" register-to-point)
          ("(" backward-sexp)
          (")" forward-sexp)
          ("." set-mark-command)
          ("/" View-search-regexp-forward)
          ("<" beginning-of-buffer)
          ("<return>" nil "quit")
          ("=" what-line)
          (">" end-of-buffer)
          ("@" View-back-to-mark)
          ("A"beginning-of-defun)
          ("DEL" View-scroll-page-backward)
          ("E"end-of-defun)
          ("J" (emacsvox-hide-or-expose-block 'all))
          ("SPC" View-scroll-page-forward)
          ("[" backward-page)
          ("\\" View-search-regexp-backward)
          ("]" forward-page)
          ("a" move-beginning-of-line)
          ("b" backward-word)
          ("c" emacsvox-speak-char)
          ("d" View-scroll-half-page-forward)
          ("e" move-end-of-line)
          ("f" forward-word)
          ("g" goto-line)
          ("h" backward-char)
          ("i" emacsvox-speak-mode-line)
          ("j" next-line)
          ("k" previous-line)
          ("l" forward-char)
          ("m" point-to-register)
          ("n" View-search-last-regexp-forward)
          ("p" View-search-last-regexp-backward)
          ("q" nil "quit")
          ("r" copy-to-register)
          ("s" emacsvox-hydra-toggle-talkative)
          ("t" (recenter 0))
          ("u" View-scroll-half-page-backward)
          ("w"emacsvox-speak-word)
          ("x" exchange-point-and-mark)
          ("y" kill-ring-save)
          ("{" backward-paragraph)
          ("}" forward-paragraph)
          )

(defun emacsvox-muggle-view--keep-hints (&rest _)
  "Keep an explicit hint choice when leaving this menu."
  (setq emacsvox-muggle-view--hint-state nil))

(advice-add 'emacsvox-muggles-view/emacsvox-hydra-toggle-talkative :after
            #'emacsvox-muggle-view--keep-hints)

(defun emacsvox-muggle-view--enter (original &rest arguments)
  "Run ORIGINAL, restoring temporary hint state if entry fails."
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-view--restore)
     (signal (car err) (cdr err)))))

(advice-add 'emacsvox-muggles-view/body :around
            #'emacsvox-muggle-view--enter)
(provide 'emacsvox-muggle-view)
;;; emacsvox-muggle-view.el ends here
