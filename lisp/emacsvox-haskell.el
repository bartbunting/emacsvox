;;; emacsvox-haskell.el --- Speech-enable HASKELL  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop haskell
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
;; Speech-enable package haskell-mode

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (haskell-c2hs-hook-name-face voice-lighten)
   (haskell-c2hs-hook-pair-face voice-brighten)
   (haskell-constructor-face voice-bolden)
   (haskell-debug-heading-face voice-smoothen-extra)
   (haskell-debug-keybinding-face voice-smoothen)
   (haskell-debug-muted-face voice-annotate)
   (haskell-debug-newline-face voice-monotone-extra)
   (haskell-debug-trace-number-face voice-lighten)
   (haskell-debug-warning-face voice-warning)
   (haskell-definition-face voice-type-personality)
   (haskell-error-face voice-warning)
   (haskell-hole-face voice-bolden)
   (haskell-interactive-face-compile-error voice-warning)
   (haskell-interactive-face-compile-warning voice-warning)
   (haskell-interactive-face-garbage voice-monotone-medium)
   (haskell-interactive-face-prompt voice-brighten)
   (haskell-interactive-face-prompt-cont voice-brighten-extra)
   (haskell-interactive-face-result voice-lighten)
   (haskell-keyword-face voice-keyword-personality)
   (haskell-liquid-haskell-annotation-face voice-bolden-extra)
   (haskell-literate-comment-face voice-monotone-extra)
   (haskell-operator-face voice-smoothen-extra)
   (haskell-pragma-face voice-monotone-medium)
   (haskell-quasi-quote-face voice-string-personality)
   (haskell-type-face voice-type-personality)
   (haskell-warning-face voice-warning)))

;;;  Interactive Commands:
'(
  haskell-delete-nested
  haskell-describe
  haskell-ds-backward-decl
  haskell-ds-forward-decl
  haskell-error-mode
  haskell-font-lock--forward-type
  haskell-hide-toggle
  haskell-hide-toggle-all
  haskell-hoogle
  haskell-hoogle-kill-server
  haskell-hoogle-lookup-from-local
  haskell-hoogle-lookup-from-website
  haskell-hoogle-start-server
  haskell-indent-align-guards-and-rhs
  haskell-indent-cycle
  haskell-indent-insert-equal
  haskell-indent-insert-guard
  haskell-indent-insert-otherwise
  haskell-indent-insert-where
  haskell-indent-mode
  haskell-indent-put-region-in-literate
  haskell-indentation-common-electric-command
  haskell-indentation-indent-backwards
  haskell-indentation-indent-line
  haskell-indentation-indent-rigidly
  haskell-indentation-mode
  haskell-indentation-newline-and-indent
  haskell-kill-nested
  haskell-kill-session-process
  haskell-literate-mode
  haskell-menu
  haskell-menu-mode
  haskell-menu-mode-ret
  haskell-mode
  haskell-mode-enable-process-minor-mode
  haskell-mode-find-uses
  haskell-mode-format-imports
  haskell-mode-generate-tags
  haskell-mode-goto-loc
  haskell-mode-insert-scc-at-point
  haskell-mode-kill-scc-at-point
  haskell-mode-menu
  haskell-mode-show-type-at
  haskell-mode-stylish-buffer
  haskell-mode-tag-find
  haskell-mode-toggle-scc-at-point
  haskell-mode-view-news
  haskell-move-nested-left
  haskell-move-nested-right
  haskell-navigate-imports
  haskell-navigate-imports-go
  haskell-navigate-imports-return
  haskell-presentation-clear
  haskell-presentation-mode
  haskell-process-cabal
  haskell-process-cabal-build
  haskell-process-cabal-macros
  haskell-process-cd
  haskell-process-clear
  haskell-process-do-info
  haskell-process-do-type
  haskell-process-generate-tags
  haskell-process-interrupt
  haskell-process-load-file
  haskell-process-load-or-reload
  haskell-process-minimal-imports
  haskell-process-reload
  haskell-process-reload-devel-main
  haskell-process-restart
  haskell-process-unignore
  haskell-rgrep
  haskell-session-change
  haskell-session-change-target
  haskell-session-kill
  haskell-sort-imports
  haskell-svg-toggle-render-images
  haskell-unicode-input-method-enable
  haskell-update-ghc-support
  haskell-yesod-parse-routes-mode
  )

(defvar emacsvox-haskell--advice nil
  "Current Haskell mode targets and their native advice functions.")
(setq emacsvox-haskell--advice nil)

(defun emacsvox-haskell--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-haskell--advice))))

(defun emacsvox-haskell--task-feedback ()
  "Speak the line after completing a Haskell editing task."
  (emacsvox-speak-line)
  (emacsvox-icon 'task-done))

(emacsvox-haskell--register-after-group
 '(haskell-align-imports haskell-auto-insert-module-template)
 #'emacsvox-haskell--task-feedback)

(defun emacsvox-haskell--movement-feedback ()
  "Speak after a large Haskell source movement."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-haskell--register-after-group
 '(
   haskell-cabal-beginning-of-section haskell-cabal-beginning-of-subsection
   haskell-cabal-end-of-section haskell-cabal-end-of-subsection
   haskell-cabal-goto-benchmark-section haskell-cabal-goto-common-section
   haskell-cabal-goto-executable-section haskell-cabal-goto-exposed-modules
   haskell-cabal-goto-library-section haskell-cabal-goto-test-suite-section
   haskell-cabal-next-section haskell-cabal-next-subsection
   haskell-cabal-previous-section haskell-cabal-previous-subsection
   haskell-cabal-section-end haskell-cabal-indent-line
   haskell-delete-indentation haskell-forward-sexp haskell-mode-jump-to-def
   haskell-mode-jump-to-def-or-tag haskell-mode-jump-to-tag)
 #'emacsvox-haskell--movement-feedback)

(defun emacsvox--advice-haskell-cabal-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p 'haskell-cabal-mode)
    (emacsvox-setup-programming-mode)))

(push '(haskell-cabal-mode :after
        emacsvox--advice-haskell-cabal-mode-after)
      emacsvox-haskell--advice)

;;; haskell-debugger:

;;; haskell-interactive

;;; haskell-indentation

(defun emacsvox-haskell--selection-feedback ()
  "Speak the line selected by Haskell indentation."
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(emacsvox-haskell--register-after-group
 '(
   haskell-indentation-common-electric-command
   haskell-indentation-indent-backwards
   haskell-indentation-indent-line haskell-indentation-indent-rigidly
   haskell-indentation-newline-and-indent)
 #'emacsvox-haskell--selection-feedback)

(defun emacsvox-haskell--install-advice ()
  "Install advice for Haskell mode features loaded so far."
  (dolist (entry emacsvox-haskell--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(haskell-mode haskell-cabal haskell-indentation))
  (eval `(with-eval-after-load ',feature
           (emacsvox-haskell--install-advice))))

;;; haskell-mode-hook:

(add-hook
 'haskell-mode-hook
 #'(lambda ()
     (haskell-indentation-mode )))

(provide 'emacsvox-haskell)

;;; emacsvox-haskell.el ends here
