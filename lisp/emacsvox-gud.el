;;; emacsvox-gud.el --- Speech enable debugger -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for gud interaction
;; Keywords:emacsvox, audio interface to emacs debuggers
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by T. V. Raman
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



;;; Commentary:
;; Provide additional advice to ease debugger interaction with gud
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'gud)

;;;   Advise key helpers:

(defun emacsvox--advice-gud-display-line-after (&rest _)
  "Speak the error line"
  
  (let ((marker gud-overlay-arrow-position))
    (emacsvox-icon 'large-movement)
    (and marker (marker-buffer marker) (marker-position marker)
         (save-current-buffer
           (set-buffer (marker-buffer marker))
           (goto-char (marker-position marker)) (emacsvox-speak-line)))))

(advice-add 'gud-display-line :after
            #'emacsvox--advice-gud-display-line-after)

(defconst emacsvox-gud--command-targets
  '(gud-break
    gud-tbreak
    gud-remove
    gud-step
    gud-stepi
    gud-next
    gud-nexti
    gud-cont
    gud-finish
    gud-jump)
  "Debugger commands that receive quiet execution feedback.")

(cl-loop
 for target in emacsvox-gud--command-targets
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,function (orig-fun &rest args)
     "Run a generated GUD command quietly, then cue its dispatch."
     (ems-with-messages-silenced
      (let ((result (apply orig-fun args)))
        (emacsvox-icon 'select-object)
        result)))))

(defun emacsvox-gud--install-command-advice ()
  "Attach advice to the GUD commands defined by the active debugger."
  (dolist (target emacsvox-gud--command-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :around function)))))

(dolist
    (hook
     '(gud-gdb-mode-hook
       sdb-mode-hook
       dbx-mode-hook
       xdb-mode-hook
       perldb-mode-hook
       pdb-mode-hook
       guiler-mode-hook
       jdb-mode-hook
       lldb-mode-hook))
  (add-hook hook #'emacsvox-gud--install-command-advice))

;; Handle a debugger that was started before this integration loaded.
(emacsvox-gud--install-command-advice)

;;;  Advise interactive commands:

(provide  'emacsvox-gud)
