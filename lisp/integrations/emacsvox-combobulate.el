;;; emacsvox-combobulate.el --- Speech-enable   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop combobulate
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
;;; COMBOBULATE: Navigate, Manipulate code with  tree-sitter's
;; concrete-tree;
;; https://github.com/mickeynp/combobulate.git (push)

;;; Code:

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (combobulate-active-indicator-face voice-animated)
   (combobulate-dimmed-indicator-face voice-bolden)
   (combobulate-refactor-highlight-face voice-annotate)
   (combobulate-tree-branch-face voice-lighten)
   (combobulate-tree-highlighted-node-face voice-brighten)
   (combobulate-tree-pulse-node-face voice-smoothen)))

;;;  Interactive Commands:

'(
  combobulate-clone-node-dwim
  combobulate-drag-down
  combobulate-drag-up
  combobulate-edit-cluster-dwim
  combobulate-envelop
  combobulate-envelop-node
  combobulate-envelop-python-ts-mode-decorate
  combobulate-envelop-python-ts-mode-nest-for
  combobulate-envelop-python-ts-mode-nest-if
  combobulate-envelop-python-ts-mode-nest-while
  combobulate-envelop-python-ts-mode-wrap-parentheses
  combobulate-kill-node-dwim
  combobulate-mark-defun
  combobulate-mark-node-dwim
  combobulate-maybe-auto-close-tag
  combobulate-maybe-close-tag-or-self-insert
  combobulate-maybe-insert-attribute
  combobulate-python-indent-for-tab-command
  combobulate-splice-down
  combobulate-splice-up
  combobulate-transpose-sexps
  combobulate-vanish-node
  )

(defun emacsvox-combobulate-speak-line ()
  "Speak"
  (let ((emacsvox-show-point  t))
    (emacsvox-speak-line)))

(defconst emacsvox-combobulate--advice-targets
  '(combobulate-navigate-beginning-of-defun
    combobulate-navigate-down
    combobulate-navigate-end-of-defun
    combobulate-navigate-logical-next
    combobulate-navigate-logical-previous
    combobulate-navigate-next
    combobulate-navigate-previous
    combobulate-navigate-up)
  "Current Combobulate navigation commands.")

(cl-loop
 for target in emacsvox-combobulate--advice-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak after navigating with Combobulate."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-combobulate-speak-line)))))

(defun emacsvox-combobulate--install-advice ()
  "Install advice after the optional Combobulate package loads."
  (dolist (target emacsvox-combobulate--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'combobulate
  (emacsvox-combobulate--install-advice))

(provide 'emacsvox-combobulate)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-combobulate.el ends here
