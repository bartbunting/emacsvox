;;; emacsvox-gnuplot.el --- speech-enable gnuplot -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech-enable
;; gnuplot mode
;; Keywords: Emacsvox, WWW interaction
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;;  required modules

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:

;; This module speech-enables gnuplot-mode
;; an Emacs add-on that enables fluent interaction with
;; gnuplot.
;; Use gnuplot to generate plots of mathematical functions
;; for inclusion in documents.

;;; Code:

;;;  advice interactive commands

(defun ems--gnuplot-send-region-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(advice-add 'gnuplot-send-region-to-gnuplot :after
            #'ems--gnuplot-send-region-to-gnuplot-after)

(defun ems--gnuplot-send-line-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(advice-add 'gnuplot-send-line-to-gnuplot :after
            #'ems--gnuplot-send-line-to-gnuplot-after)

(defun ems--gnuplot-send-line-and-forward-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(advice-add 'gnuplot-send-line-and-forward :after
            #'ems--gnuplot-send-line-and-forward-after)

(defun ems--gnuplot-send-buffer-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(advice-add 'gnuplot-send-buffer-to-gnuplot :after
            #'ems--gnuplot-send-buffer-to-gnuplot-after)

(defun ems--gnuplot-send-file-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(advice-add 'gnuplot-send-file-to-gnuplot :after
            #'ems--gnuplot-send-file-to-gnuplot-after)

(defun ems--gnuplot-delchar-or-maybe-eof-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (cond
       ((= (point) (point-max))
        (message "Sending EOF to comint process"))
       (t (dtk-tone 500 100 'force) (emacsvox-speak-char t)))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'gnuplot-delchar-or-maybe-eof :around
            #'ems--gnuplot-delchar-or-maybe-eof-around)

(defun ems--gnuplot-kill-gnuplot-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'gnuplot-kill-gnuplot-buffer :after
            #'ems--gnuplot-kill-gnuplot-buffer-after)

(defun ems--gnuplot-show-gnuplot-buffer-after (&rest _)
  "Speak status."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'gnuplot-show-gnuplot-buffer :after
            #'ems--gnuplot-show-gnuplot-buffer-after)

(defun ems--gnuplot-complete-keyword-around (orig-fun &rest args)
  "Say what you completed."
  (let ((result (apply orig-fun args)))
    (let
        ((prior (save-excursion (skip-syntax-backward "^ >") (point)))
         (dtk-stop-immediately dtk-stop-immediately))
      (when dtk-stop-immediately (dtk-stop)) (apply orig-fun args)
      (when (> (point) prior)
        (setq dtk-stop-immediately nil)
        (dtk-speak (buffer-substring prior (point))))
      result)
    result))

(advice-add 'gnuplot-complete-keyword :around
            #'ems--gnuplot-complete-keyword-around)

(defun ems--gnuplot-indent-line-after (&rest _)
  "Speak line we idnented."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'gnuplot-indent-line :after
            #'ems--gnuplot-indent-line-after)

(defun ems--gnuplot-negate-option-after (&rest _)
  "Speak line we negated."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'gnuplot-negate-option :after
            #'ems--gnuplot-negate-option-after)

(add-hook 'gnuplot-mode-hook
          #'(lambda nil
              (dtk-set-punctuations 'all)))

(provide 'emacsvox-gnuplot)
;;;  end of file

