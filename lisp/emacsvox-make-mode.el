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

;;;   required modules

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:

;; This module speech enables make-mode

;;; Code:

;;;  advice

(defun ems--makefile-next-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-next-dependency :after
            #'ems--makefile-next-dependency-after)

(defun ems--makefile-browser-next-line-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'makefile-browser-next-line :after
            #'ems--makefile-browser-next-line-after)

(defun ems--makefile-browser-previous-line-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'makefile-browser-previous-line :after
            #'ems--makefile-browser-previous-line-after)

(defun ems--makefile-previous-dependency-after (&rest _)
  "Speak line we moved to"
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(advice-add 'makefile-previous-dependency :after
            #'ems--makefile-previous-dependency-after)

(defun ems--makefile-complete-around (orig-fun &rest args)
  "Speak what we completed"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let
          ((orig (save-excursion (skip-syntax-backward "^ >") (point))))
        (apply orig-fun args) (emacsvox-speak-region orig (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'makefile-complete :around #'ems--makefile-complete-around)

(defun ems--makefile-backslash-region-after (&rest _)
  "Speak how many lines we backslashed"
  (when (ems-interactive-p)
    (message "Backslashed region containing %s lines"
             (count-lines (region-beginning) (region-end)))
    (emacsvox-icon 'select-object)))

(advice-add 'makefile-backslash-region :after
            #'ems--makefile-backslash-region-after)

(defun ems--makefile-browser-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'close-object)))

(advice-add 'makefile-browser-quit :after
            #'ems--makefile-browser-quit-after)

(defun ems--makefile-switch-to-browser-after (&rest _)
  "Provide status information"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'makefile-switch-to-browser :after
            #'ems--makefile-switch-to-browser-after)

(defun ems--makefile-browser-toggle-around (orig-fun &rest args)
  "Speak what happened"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let
          ((this-line (max (count-lines (point-min) (point)) 1))
           (state nil))
        (apply orig-fun args)
        (setq state (makefile-browser-get-state-for-line this-line))
        (emacsvox-icon (if state 'on 'off)) (emacsvox-speak-line)))
     (t (apply orig-fun args)))
    result))

(advice-add 'makefile-browser-toggle :around
            #'ems--makefile-browser-toggle-around)

(defun ems--makefile-browser-insert-selection-after (&rest _)
  "Provide status message"
  (when (ems-interactive-p)
    (message "Inserted selections into client  %s"
             (buffer-name makefile-browser-client))))

(advice-add 'makefile-browser-insert-selection :after
            #'ems--makefile-browser-insert-selection-after)

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

