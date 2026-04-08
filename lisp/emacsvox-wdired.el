;;; emacsvox-wdired.el --- Speech-enable wdired  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech-enable WDIRED
;; Keywords: Emacsvox, Multimedia
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

;;;   Introduction

;;; Commentary:
;; Speech-enable wdired to permit in-place renaming of groups of files.

;;; Code:
;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice interactive commands.

(cl-loop for c in
         '(wdired-next-line wdired-previous-line)
         do
         (eval
          `(defadvice ,c (after emacsvox pre act comp)
             "Speak."
             (when (ems-interactive-p)
               (emacsvox-icon 'select-object)
               (emacsvox-dired-speak-line)))))

(defun ems--wdired-upcase-word-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (tts-with-punctuations 'some (dtk-speak "upper cased file name. "))))

(advice-add 'wdired-upcase-word :after #'ems--wdired-upcase-word-after)

(defun ems--wdired-capitalize-word-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (tts-with-punctuations 'some (dtk-speak "Capitalized file name. "))))

(advice-add 'wdired-capitalize-word :after
            #'ems--wdired-capitalize-word-after)

(defun ems--wdired-downcase-word-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (tts-with-punctuations 'some
                           (dtk-speak "Down cased file\n  name. "))))

(advice-add 'wdired-downcase-word :after
            #'ems--wdired-downcase-word-after)

(defun ems--wdired-toggle-bit-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (dtk-speak "Toggled permission bit.")))

(advice-add 'wdired-toggle-bit :after #'ems--wdired-toggle-bit-after)

(defun ems--wdired-abort-changes-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (tts-with-punctuations 'some (dtk-speak "Cancelling  changes. "))))

(advice-add 'wdired-abort-changes :after
            #'ems--wdired-abort-changes-after)

(defun ems--wdired-finish-edit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object)
    (tts-with-punctuations 'some (dtk-speak "Committed changes. "))))

(advice-add 'wdired-finish-edit :after #'ems--wdired-finish-edit-after)

(defun ems--wdired-change-to-wdired-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (tts-with-punctuations 'some
                           (dtk-speak
                            "Entering writeable dir ed mode. "))))

(advice-add 'wdired-change-to-wdired-mode :after
            #'ems--wdired-change-to-wdired-mode-after)

(provide 'emacsvox-wdired)
;;;  end of file

