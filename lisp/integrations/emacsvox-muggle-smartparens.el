;;; emacsvox-muggle-smartparens.el --- Smartparens Muggle -*- lexical-binding: t; -*-

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
;; Smartparens Muggle without installing entry keys.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)
(require 'smartparens nil t)

(defvar emacsvox-muggle-smartparens--hint-state nil
  "Original and temporary hints for the active visit.")

(defun emacsvox-muggle-smartparens--begin ()
  "Quiet hints for this visit, preserving the previous choice."
  (unless emacsvox-muggle-smartparens--hint-state
    (setq emacsvox-muggle-smartparens--hint-state (list hydra-is-helpful nil))
    (when hydra-is-helpful (emacsvox-hydra-toggle-talkative))))

(defun emacsvox-muggle-smartparens--restore ()
  "Restore temporary hints unless changed during the visit."
  (when emacsvox-muggle-smartparens--hint-state
    (when (eq hydra-is-helpful (cadr emacsvox-muggle-smartparens--hint-state))
      (setq hydra-is-helpful (car emacsvox-muggle-smartparens--hint-state)))
    (setq emacsvox-muggle-smartparens--hint-state nil)))

(defun emacsvox-muggle-smartparens--finish ()
  "Restore hints and announce exit."
  (emacsvox-muggle-smartparens--restore)
  (emacsvox-hydra-post))

(defhydra emacsvox-muggles-smartparens
           (:body-pre
            (progn
              (emacsvox-muggle-smartparens--begin)
              (emacsvox-hydra-body-pre "SmartParens"))
            :pre emacsvox-hydra-pre
            :post emacsvox-muggle-smartparens--finish)
           "Smart Parens"
           ("'" #'(lambda (_) (interactive "P") (sp-wrap-with-pair "'")))
           ("(" #'(lambda (_) (interactive "P") (sp-wrap-with-pair "(")))
           ("<down>" sp-splice-sexp-killing-forward)
           ("<left>" sp-forward-barf-sexp)
           ("<right>" sp-forward-slurp-sexp)
           ("<up>" sp-splice-sexp-killing-backward)
           ("?" (emacsvox-hydra-self-help "emacsvox-muggles-smartparens"))
           ("C-<left>" sp-backward-barf-sexp)
           ("C-<right>" sp-backward-slurp-sexp)
           ("R" sp-splice-sexp)
           ("\"" #'(lambda (_) (interactive "P") (sp-wrap-with-pair "\"")))
           ("a" beginning-of-defun)
           ("b" sp-backward-sexp)
           ("c" sp-convolute-sexp)
           ("d" sp-down-sexp)
           ("e" end-of-defun)
           ("f" sp-forward-sexp)
           ("i" sp-indent-defun)
           ("j" sp-join-sexp)
           ("k" sp-kill-sexp)
           ("n" sp-next-sexp)
           ("p" sp-previous-sexp)
           ("r" sp-splice-sexp-killing-around)
           ("s" sp-split-sexp)
           ("t" sp-transpose-sexp)
           ("u" sp-backward-up-sexp)
           ("w" sp-copy-sexp)
           ("{" #'(lambda (_) (interactive "P") (sp-wrap-with-pair "{"))))

(defun emacsvox-muggle-smartparens--enter (original &rest arguments)
  "Check Smartparens context before running ORIGINAL."
  (unless (require 'smartparens nil t)
    (user-error "The smartparens package is unavailable"))
  (unless (bound-and-true-p smartparens-mode)
    (user-error "Enable smartparens-mode in this buffer first"))
  (when hydra-curr-map (hydra-keyboard-quit))
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-smartparens--restore)
     (signal (car err) (cdr err)))))
(advice-add 'emacsvox-muggles-smartparens/body :around
            #'emacsvox-muggle-smartparens--enter)

(provide 'emacsvox-muggle-smartparens)
;;; emacsvox-muggle-smartparens.el ends here
