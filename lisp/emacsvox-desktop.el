;;; emacsvox-desktop.el ---  Speech-enable desktop  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  desktop transformation routines
;; Keywords: Emacsvox,  Audio Desktop, DESKTOP
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; advice desktop package
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
;;; Interactive Command: Preserve buffer
;;;###autoload
(defun emacsvox-desktop-preserve (buffer)
  "Preserve: Dont kill this buffer when clearing desktop."
  (interactive
   (list (read-buffer "Preserve Buffer: " (current-buffer) t)))
  
  (cl-pushnew buffer desktop-clear-preserve-buffers)
  (message "Preserving %s for this session." buffer))

;;;   desktop


(defun ems--desktop-clear-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (dtk-notify "cleared desktop")
    (emacsvox-icon 'delete-object)))


(advice-add 'desktop-clear :after #'ems--desktop-clear-after)





(defun ems--desktop-save-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'save-object)))


(advice-add 'desktop-save :after #'ems--desktop-save-after)





(defun ems--desktop-lazy-create-buffer-around (orig-fun &rest args)
  "Silence messages."
  (ems-with-messages-silenced (apply orig-fun args)))


(advice-add 'desktop-lazy-create-buffer :around
	    #'ems--desktop-lazy-create-buffer-around)




(provide 'emacsvox-desktop)
;;;  end of file

