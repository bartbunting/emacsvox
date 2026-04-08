;;; emacsvox-lua.el --- Speech-enable LUA  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable LUA An Emacs Interface to lua
;; Keywords: Emacsvox,  Audio Desktop lua
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
;; MERCHANTABILITY or FITNLUA FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; LUA == lua-mode
;; Speech-enable lua-mode.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice Interactive Commands:
(cl-loop
 for f in
 '(
   lua-backwards-to-block-begin-or-end lua-beginning-of-proc
   lua-end-of-proc
   lua-forward-sexp lua-goto-matching-block)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defun ems--lua-start-process-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-start-process :after #'ems--lua-start-process-after)

(defun ems--lua-kill-process-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-kill-process :after #'ems--lua-kill-process-after)

(defun ems--lua-search-documentation-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-search-documentation :after
            #'ems--lua-search-documentation-after)

(cl-loop
 for f in
 '(
   lua-send-buffer lua-send-current-line
   lua-send-lua-region lua-send-proc lua-send-region)
 do
 (eval
  `(defadvice,f (after emacsvox pre act comp)
                "speak."
                (when (ems-interactive-p)
                  (emacsvox-icon 'task-done)))))

(defun ems--lua-show-process-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'lua-show-process-buffer :after
            #'ems--lua-show-process-buffer-after)

(provide 'emacsvox-lua)
;;;  end of file

