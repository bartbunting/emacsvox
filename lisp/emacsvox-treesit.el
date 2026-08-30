;;; emacsvox-treesit.el --- Speech-enable TREESIT  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop treesit
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
;;; TREESIT ==  Syntax Trees
;; Speech-enable treesit navigation commands.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'treesit "treesit" 'no-error)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (treesit-explorer-anonymous-node 'voice-smoothen)
   (treesit-explorer-field-name voice-brighten)))

;;;  Advice Interactive Commands:

(cl-loop
 for target in
 '(treesit-end-of-defun treesit-beginning-of-defun treesit-forward-sexp)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive tree-sitter navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add ',target :after #',function))))

;;; Interactive Helpers:

(defun emacsvox-treesit-inspect ()
  "If inspect-mode is on, speak current node."
  (interactive)
  
  (cond
   (treesit-inspect-mode (message (format-mode-line treesit--inspect-name)))
   ((y-or-n-p "Turn on treesitter inspector?")
    (treesit-inspect-mode)
    (message (format-mode-line treesit--inspect-name)))))

(provide 'emacsvox-treesit)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-treesit.el ends here
