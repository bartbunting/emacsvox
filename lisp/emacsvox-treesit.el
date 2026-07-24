;;; emacsvox-treesit.el --- Speech-enable TREESIT  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable TREESIT An Emacs Interface to treesit
;;; Keywords: Emacsvox,  Audio Desktop treesit
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


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
