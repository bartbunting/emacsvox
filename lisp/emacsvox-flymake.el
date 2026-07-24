;;; emacsvox-flymake.el --- Speech-enable FLYMAKE  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable FLYMAKE An Emacs Interface to flymake
;; Keywords: Emacsvox,  Audio Desktop flymake
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNFLYMAKE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Speech-enable flymake

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'flymake)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (flymake-error voice-monotone)
   (flymake-note voice-smoothen)
   (flymake-warning voice-animate)))

;;;  Interactive Commands:

(cl-loop
 for target in
 '(flymake-goto-diagnostic
   flymake-goto-next-error
   flymake-goto-prev-error)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Flymake navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-flymake-proc-compile-after (&rest _)
  "Cue completion after an interactive legacy Flymake compilation."
  (when (ems-interactive-p 'flymake-proc-compile)
    (emacsvox-icon 'task-done)))

(with-eval-after-load 'flymake-proc
  (advice-add 'flymake-proc-compile :after
              #'emacsvox--advice-flymake-proc-compile-after))

(provide 'emacsvox-flymake)
;;;  end of file
