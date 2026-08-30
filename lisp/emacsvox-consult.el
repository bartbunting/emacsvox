;;; emacsvox-consult.el --- Speech-enable CONSULT  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2022, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop consult
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
;; CONSULT ==  A modern completing-read 
;; @itemize
;; @item Setup @code{consult-after-jump-hook} to speak  where we
;; land.
;; @item Advice needed interactive commands.
;; @item Map faces.
;; @item Setup: Put consult commands on @code{C-/}
;; @end itemize
;;; Code:

;;   Required modules

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(eval-when-compile  (require 'consult "consult" 'no-error))
;;;  Map Faces:

(voice-setup-add-map 
 '(
   (consult-async-failed voice-lighten)
   (consult-async-finished voice-monotone)
   (consult-async-running voice-animated)
   (consult-async-split voice-brighten)
   (consult-bookmark voice-bolden)
   (consult-buffer voice-bolden)
   (consult-file voice-bolden)
   (consult-grep-context voice-animate)
   (consult-help voice-lighten)
   (consult-highlight-mark voice-animate)
   (consult-highlight-match voice-brighten)
   (consult-key voice-monotone)
   (consult-line-number voice-smoothen)
   (consult-line-number-prefix voice-lighten)
   (consult-line-number-wrapped voice-lighten)
   (consult-preview-insertion voice-bolden)
   (consult-preview-line voice-animate)
   (consult-preview-match voice-bolden)))

;;;  Interactive Commands:

'(
  consult-complex-command
  consult-flymake
  consult-focus-lines
  consult-global-mark
  consult-goto-line
  consult-history
  consult-isearch-backward
  consult-isearch-forward
  consult-isearch-history
  consult-keep-lines
  consult-kmacro
  consult-line
  consult-line-multi
  consult-mark
  consult-minor-mode-menu
  consult-mode-command
  consult-narrow
  consult-narrow-help
  consult-preview-at-point
  consult-preview-at-point-mode
  consult-project-buffer
  consult-recent-file
  consult-register
  consult-register-load
  consult-register-store
  consult-theme
  consult-yank-from-kill-ring
  consult-yank-pop
  consult-yank-replace
  )

(add-hook 'consult-after-jump-hook #'emacsvox-speak-line)

(defconst emacsvox-consult--selection-targets
  '(consult-bookmark consult-compile-error)
  "Consult commands that select a location.")

(cl-loop
 for target in emacsvox-consult--selection-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the location selected by Consult."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(defconst emacsvox-consult--open-targets
  '(consult-buffer
    consult-buffer-other-frame
    consult-buffer-other-tab
    consult-buffer-other-window
    consult-find
    consult-fd)
  "Consult commands that open a buffer or file.")

(cl-loop
 for target in emacsvox-consult--open-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak after opening a Consult selection."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

(defconst emacsvox-consult--advice-targets
  (append emacsvox-consult--selection-targets
          emacsvox-consult--open-targets)
  "Current Consult targets that receive native after advice.")

(defun emacsvox-consult--install-advice ()
  "Install advice for functions present in current Consult."
  (dolist (target emacsvox-consult--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(dolist (feature '(consult consult-compile))
  (eval-after-load feature #'emacsvox-consult--install-advice))

;;; Set it up:
(defvar  emacsvox-consult-keymap nil "Emacsvox consult keymap")

(define-prefix-command 'emacsvox-consult-keymap)

(global-set-key (kbd "C-/") 'emacsvox-consult-keymap)

(cl-loop
 for b in
 '(
   ("#" consult-register-load)
   ("'" consult-register-store)
   ("/" consult-history)
   ("4b" consult-buffer-other-window)
   ("5b" consult-buffer-other-frame)
   (":" consult-complex-command)
   ("B" consult-bookmark)
   ("G" consult-goto-line)
   ("H" consult-history)
   ("K" consult-keep-lines)
   ("L" consult-line-multi)
   ("M" consult-mark)
   ("M-x" consult-mode-command)
   ("M-y" consult-yank-pop)
   ("b" consult-buffer)
   ("c" consult-locate)
   ("d" consult-find)
   ("e" consult-compile-error)
   ("g" consult-grep)
   ("f" consult-fd)
   ("h" consult-org-heading)
   ("i" consult-info)
   ("j" consult-imenu)
   ("k" consult-global-mark)
   ("l" consult-line)
   ("m" consult-man)
   ("o" consult-outline)
   ("p" consult-project-buffer)
   ("r" consult-ripgrep)
   ("s" consult-isearch-history)
   ("u" consult-focus-lines)
   )
 do
 (define-key  emacsvox-consult-keymap (kbd (car b))  (cadr b)))

(provide 'emacsvox-consult)

;;; emacsvox-consult.el ends here
