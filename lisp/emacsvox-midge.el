;;; emacsvox-midge.el --- Speech-enable Midge -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech-enable MIDGE
;; Keywords: Emacsvox, MIDI 
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

;; This module speech enables  midge.
;; Midge is a MIDI composer/editor tool.
;; From the package README file:
;; Midge, for midi generator, is a text to midi translator.
;; It creates type 1 (ie multitrack) midi files from text
;; descriptions of music. It is a single perl script, which
;; does not require any additional modules.
;; The package also provides a convenient emacs mode for
;; editing and playing  midge files.
;; Midge's homepage is at:
;; http://www.dmriley.demon.co.uk/code/midge/ 

;;; Code:

;;;  Speech enable interactive commands.

(defun ems--midge-indent-line-after (&rest _)
  "Speak line after indenting it."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'midge-indent-line :after #'ems--midge-indent-line-after)

(defun ems--midge-close-bracket-after (&rest _)
  "Speak closing delimiter we inserted"
  (when (ems-interactive-p)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'midge-close-bracket :after
            #'ems--midge-close-bracket-after)

(defun ems--midge-head-block-after (&rest _)
  "Announce insertion of head block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started head section")))

(advice-add 'midge-head-block :after #'ems--midge-head-block-after)

(defun ems--midge-body-block-after (&rest _)
  "Announce insertion of body block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started body section")))

(advice-add 'midge-body-block :after #'ems--midge-body-block-after)

(defun ems--midge-repeat-block-after (&rest _)
  "Announce insertion of repeat block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started repeat block")))

(advice-add 'midge-repeat-block :after #'ems--midge-repeat-block-after)

(defun ems--midge-choose-block-after (&rest _)
  "Announce insertion of choose block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started choose block")))

(advice-add 'midge-choose-block :after #'ems--midge-choose-block-after)

(defun ems--midge-bend-block-after (&rest _)
  "Announce insertion of bend block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started bend block")))

(advice-add 'midge-bend-block :after #'ems--midge-bend-block-after)

(defun ems--midge-define-block-after (&rest _)
  "Announce insertion of define block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (message "Started define block")))

(advice-add 'midge-define-block :after #'ems--midge-define-block-after)

(defun ems--midge-repeat-line-after (&rest _)
  "Announce insertion of repeat block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'midge-repeat-line :after #'ems--midge-repeat-line-after)

(defun ems--midge-bend-line-after (&rest _)
  "Announce insertion of bend block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'midge-bend-line :after #'ems--midge-bend-line-after)

(defun ems--midge-define-line-after (&rest _)
  "Announce insertion of define block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'midge-define-line :after #'ems--midge-define-line-after)

(defun ems--midge-choose-line-after (&rest _)
  "Announce insertion of choose block"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'midge-choose-line :after #'ems--midge-choose-line-after)

(defun ems--midge-compile-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-message-again)))

(advice-add 'midge-compile :after #'ems--midge-compile-after)

(defun ems--midge-compile-debug-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'midge-compile-debug :after
            #'ems--midge-compile-debug-after)

(defun ems--midge-compile-verbose-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'midge-compile-verbose :after
            #'ems--midge-compile-verbose-after)

(defun ems--midge-compile-ask-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'midge-compile-ask :after #'ems--midge-compile-ask-after)

;;;  midge-mode-hook

(defvar midge-mode-hook nil
  "midge setup hook")

(defun ems--midge-mode-after (&rest _)
  "Run midge-mode-hook" (run-hooks 'midge-mode-hook))

(advice-add 'midge-mode :after #'ems--midge-mode-after)

(provide 'emacsvox-midge)
;;;  end of file

