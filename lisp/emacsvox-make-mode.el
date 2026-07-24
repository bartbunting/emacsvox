;;; emacsvox-make-mode.el --- Speech enable make  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacsvox extension to speech enable make-mode
;; Keywords: Emacsvox, Make
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

;;;   required modules

(require 'emacsvox-preamble)
(require 'make-mode)

;;; Commentary:

;; This module speech enables make-mode

;;; Code:

;;;  advice

(defun emacsvox--advice-makefile-next-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-next-dependency)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-next-dependency :after
            #'emacsvox--advice-makefile-next-dependency-after)

(defun emacsvox--advice-makefile-browser-next-line-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-browser-next-line)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'makefile-browser-next-line :after
            #'emacsvox--advice-makefile-browser-next-line-after)

(defun emacsvox--advice-makefile-browser-previous-line-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-browser-previous-line)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'makefile-browser-previous-line :after
            #'emacsvox--advice-makefile-browser-previous-line-after)

(defun emacsvox--advice-makefile-previous-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p 'makefile-previous-dependency)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-previous-dependency :after
            #'emacsvox--advice-makefile-previous-dependency-after)

(defun emacsvox--advice-makefile-backslash-region-after
    (from to &rest _)
  "Speak how many lines we backslashed"
  (when (ems-interactive-p 'makefile-backslash-region)
    (message "Backslashed region containing %s lines"
             (count-lines from to))
    (emacsvox-icon 'select-object)))

(advice-add 'makefile-backslash-region :after
            #'emacsvox--advice-makefile-backslash-region-after)

(defun emacsvox--advice-makefile-browser-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p 'makefile-browser-quit)
    (emacsvox-speak-mode-line) (emacsvox-icon 'close-object)))

(advice-add 'makefile-browser-quit :after
            #'emacsvox--advice-makefile-browser-quit-after)

(defun emacsvox--advice-makefile-switch-to-browser-after (&rest _)
  "Provide status information"
  (when (ems-interactive-p 'makefile-switch-to-browser)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'makefile-switch-to-browser :after
            #'emacsvox--advice-makefile-switch-to-browser-after)

(defun emacsvox--advice-makefile-browser-toggle-around (orig-fun)
  "Speak what happened"
  (if (ems-interactive-p 'makefile-browser-toggle)
      (let ((this-line (max (count-lines (point-min) (point)) 1)))
        (prog1 (funcall orig-fun)
          (emacsvox-icon
           (if (makefile-browser-get-state-for-line this-line) 'on 'off))
          (emacsvox-speak-line)))
    (funcall orig-fun)))

(advice-add 'makefile-browser-toggle :around
            #'emacsvox--advice-makefile-browser-toggle-around)

(defun emacsvox--advice-makefile-browser-insert-selection-after (&rest _)
  "Provide status message"
  (when (ems-interactive-p 'makefile-browser-insert-selection)
    (message "Inserted selections into client  %s"
             (buffer-name makefile-browser-client))))

(advice-add 'makefile-browser-insert-selection :after
            #'emacsvox--advice-makefile-browser-insert-selection-after)

;;;  personalities 

(voice-setup-add-map
 '(
   (makefile-space voice-monotone-extra)
   (makefile-targets voice-bolden)
   (makefile-shell voice-animate)
   (makefile-makepp-perl voice-smoothen)
   ))

;;;  setup mode hook:

(provide 'emacsvox-make-mode)

;;;  end of file 
