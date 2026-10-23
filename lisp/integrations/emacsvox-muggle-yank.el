;;; emacsvox-muggle-yank.el --- Repeatable yank Muggle -*- lexical-binding: t; -*-

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
;; Repeatable yank Muggle without installing entry keys.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)
(require 'ido)

(defun emacsvox-muggles-ido-yank ()
  "Choose kill-ring text with Ido, replacing the last yank when appropriate.
Cancelling the choice leaves the buffer unchanged."
  (interactive)
  (let* ((replace (eq last-command 'yank))
         (start (and replace (region-beginning)))
         (end (and replace (region-end)))
         (text (ido-completing-read
                "Yank what? " (mapcar #'substring-no-properties kill-ring)))
         (origin (if replace start (point))))
    (atomic-change-group
      (when replace (delete-region start end))
      (insert text))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'yank-object)
      (emacsvox-speak-region origin (point)))))

(declare-function browse-kill-ring "browse-kill-ring" ())
(defun emacsvox-muggle-yank--list ()
  "Open the optional kill-ring browser."
  (interactive)
  (unless (require 'browse-kill-ring nil t)
    (user-error "The browse-kill-ring package is unavailable; use i for Ido"))
  (call-interactively #'browse-kill-ring))

(defvar emacsvox-muggle-yank--hint-state nil
  "Original and temporary hints for the active visit.")

(defun emacsvox-muggle-yank--begin ()
  "Quiet hints for this visit, preserving the previous choice."
  (unless emacsvox-muggle-yank--hint-state
    (setq emacsvox-muggle-yank--hint-state (list hydra-is-helpful nil))
    (when hydra-is-helpful (emacsvox-hydra-toggle-talkative))))

(defun emacsvox-muggle-yank--restore ()
  "Restore temporary hints unless changed during the visit."
  (when emacsvox-muggle-yank--hint-state
    (when (eq hydra-is-helpful (cadr emacsvox-muggle-yank--hint-state))
      (setq hydra-is-helpful (car emacsvox-muggle-yank--hint-state)))
    (setq emacsvox-muggle-yank--hint-state nil)))

(defun emacsvox-muggle-yank--finish ()
  "Restore hints and announce exit."
  (emacsvox-muggle-yank--restore)
  (emacsvox-hydra-post))

(defhydra
 emacsvox-muggles-yank-pop
 (:body-pre (progn
              (emacsvox-muggle-yank--begin)
              (emacsvox-hydra-body-pre "Yank"))
            :pre
            (progn
              (emacsvox-muggle-yank--begin)
              (emacsvox-hydra-pre))
            :post emacsvox-muggle-yank--finish)
 "Yank"
 ("?" (emacsvox-hydra-self-help "emacsvox-muggles-yank-pop"))
 ("C-y" yank nil)
 ("M-y" yank-pop nil)
 ("y" (funcall-interactively #'yank-pop 1) "next")
 ("Y" (funcall-interactively #'yank-pop -1) "prev")
 ("i" emacsvox-muggles-ido-yank "IDo Yank" :color blue)
 ("s" emacsvox-muggles-ido-yank "IDo Yank" :color blue)
 ("l" emacsvox-muggle-yank--list "list" :color blue))

(defun emacsvox-muggle-yank--enter (original &rest arguments)
  "Run ORIGINAL with isolated temporary hints."
  (when (and hydra-curr-map
             (not (eq hydra-curr-body-fn 'emacsvox-muggles-yank-pop/body)))
    (hydra-keyboard-quit))
  (condition-case err
      (apply original arguments)
    ((error quit)
     (emacsvox-muggle-yank--restore)
     (signal (car err) (cdr err)))))

(defun emacsvox-muggle-yank--body-enter (original &rest arguments)
  "Close the previous visit before entering ORIGINAL."
  (when hydra-curr-map (hydra-keyboard-quit))
  (apply #'emacsvox-muggle-yank--enter original arguments))

(advice-add 'emacsvox-muggles-yank-pop/body :around
            #'emacsvox-muggle-yank--body-enter)
(dolist (command '(emacsvox-muggles-yank-pop/yank
                   emacsvox-muggles-yank-pop/yank-pop))
  (advice-add command :around #'emacsvox-muggle-yank--enter))

(provide 'emacsvox-muggle-yank)
;;; emacsvox-muggle-yank.el ends here
