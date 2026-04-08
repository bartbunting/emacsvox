;;; emacsvox-elpy.el --- Speech-enable ELPY -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ELPY An Emacs Interface to elpy
;; Keywords: Emacsvox,  Audio Desktop elpy
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNELPY FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ELPY ==  Emacs Lisp Python IDE
;; Speech-enables all aspects of elpy.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice Interactive Commands:

(cl-loop
 for f in
 '(
   elpy-autopep8-fix-code elpy-config elpy-check
   elpy-occur-definitions elpy-rgrep-symbol
   elpy-set-project-root elpy-set-project-variable
   elpy-set-test-runner
   elpy-shell-send-current-statement elpy-shell-send-region-or-buffer
   elpy-shell-switch-to-buffer elpy-shell-switch-to-shell
   elpy-use-cpython elpy-use-ipython
   elpy-importmagic-add-import elpy-importmagic-fixup)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-mode-line)))))

(defun ems--elpy-enable-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'on) (message "Enabled elpy")))

(advice-add 'elpy-enable :after #'ems--elpy-enable-after)

(defun ems--elpy-disable-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'off) (message "Disabled elpy")))

(advice-add 'elpy-disable :after #'ems--elpy-disable-after)

(defun ems--elpy-doc-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'help) (message "Displayed help in other window.")))

(advice-add 'elpy-doc :after #'ems--elpy-doc-after)

(defun ems--elpy-find-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'elpy-find-file :after #'ems--elpy-find-file-after)

(cl-loop
 for f in
 '(elpy-flymake-next-error elpy-flymake-previous-error
                           elpy-goto-definition)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

                                        ; elpy-flymake-show-error

(cl-loop
 for f in
 '(
   elpy-nav-backward-block elpy-nav-backward-indent
   elpy-nav-expand-to-indentation elpy-nav-forward-block
   elpy-nav-forward-indent
   elpy-nav-indent-shift-left elpy-nav-indent-shift-right
   elpy-open-and-indent-line-below elpy-open-and-indent-line-above
   elpy-nav-move-line-or-region-down elpy-nav-move-line-or-region-up)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(provide 'emacsvox-elpy)
;;;  end of file

