;;; emacsvox-cmuscheme.el --- CMUScheme   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Speech-enable emacs for scheme and guile
;; Keywords: Emacsvox, cmuscheme
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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
;; speech-enable scheme support 

;;; Code:

;;  required modules

;;; Code:

(require 'emacsvox-preamble)

;;;  advice interactive commands.

;; speech-enable cmuscheme 

(defun ems--inferior-scheme-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (message "Welcome to inferior scheme mode.")))

(advice-add 'inferior-scheme-mode :after
            #'ems--inferior-scheme-mode-after)

(defun ems--run-scheme-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (message "Launched scheme %s" (ad-get-arg 0))))

(advice-add 'run-scheme :after #'ems--run-scheme-after)

(defun ems--scheme-send-region-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Sent %s lines to scheme. "
             (count-lines (region-beginning) (region-end)))))

(advice-add 'scheme-send-region :after #'ems--scheme-send-region-after)

(defun ems--scheme-send-definition-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Sent definition   to scheme. ")))

(advice-add 'scheme-send-definition :after
            #'ems--scheme-send-definition-after)

(defun ems--scheme-send-last-sexp-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Sent last sexp  to scheme. ")))

(advice-add 'scheme-send-last-sexp :after
            #'ems--scheme-send-last-sexp-after)

(defun ems--scheme-compile-region-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Compiling  %s lines to scheme. "
             (count-lines (region-beginning) (region-end)))))

(advice-add 'scheme-compile-region :after
            #'ems--scheme-compile-region-after)

(defun ems--scheme-compile-definition-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Compiled definition  to scheme. ")))

(advice-add 'scheme-compile-definition :after
            #'ems--scheme-compile-definition-after)

(defun ems--switch-to-scheme-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'switch-to-scheme :after #'ems--switch-to-scheme-after)

(defun ems--scheme-send-region-and-go-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'scheme-send-region-and-go :after
            #'ems--scheme-send-region-and-go-after)

(defun ems--scheme-send-definition-and-go-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'scheme-send-definition-and-go :after
            #'ems--scheme-send-definition-and-go-after)

(defun ems--scheme-load-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "loaded scheme file %s" (ad-get-arg 0))))

(advice-add 'scheme-load-file :after #'ems--scheme-load-file-after)

(defun ems--scheme-compile-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Compiled scheme file %s" (ad-get-arg 0))))

(advice-add 'scheme-compile-file :after
            #'ems--scheme-compile-file-after)

(provide 'emacsvox-cmuscheme)
;;;  end of file

