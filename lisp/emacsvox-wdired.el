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
;; Location https://github.com/robertmeta/emacsvox
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

(cl-loop
 for target in '(wdired-next-line wdired-previous-line)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Wdired line movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-dired-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-wdired-upcase-word-after (&rest _)
  "Confirm interactively upper-casing a file name."
  (when (ems-interactive-p 'wdired-upcase-word)
    (tts-with-punctuations 'some (dtk-speak "upper cased file name. "))))

(advice-add
 'wdired-upcase-word :after #'emacsvox--advice-wdired-upcase-word-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-capitalize-word-after (&rest _)
  "Confirm interactively capitalizing a file name."
  (when (ems-interactive-p 'wdired-capitalize-word)
    (tts-with-punctuations 'some (dtk-speak "Capitalized file name. "))))

(advice-add
 'wdired-capitalize-word :after
 #'emacsvox--advice-wdired-capitalize-word-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-downcase-word-after (&rest _)
  "Confirm interactively lower-casing a file name."
  (when (ems-interactive-p 'wdired-downcase-word)
    (tts-with-punctuations 'some
                           (dtk-speak "Down cased file\n  name. "))))

(advice-add
 'wdired-downcase-word :after
 #'emacsvox--advice-wdired-downcase-word-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-toggle-bit-after (&rest _)
  "Confirm interactively toggling a permission bit."
  (when (ems-interactive-p 'wdired-toggle-bit)
    (emacsvox-icon 'button) (dtk-speak "Toggled permission bit.")))

(advice-add
 'wdired-toggle-bit :after #'emacsvox--advice-wdired-toggle-bit-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-abort-changes-after (&rest _)
  "Confirm interactively cancelling Wdired changes."
  (when (ems-interactive-p 'wdired-abort-changes)
    (emacsvox-icon 'close-object)
    (tts-with-punctuations 'some (dtk-speak "Cancelling  changes. "))))

(advice-add
 'wdired-abort-changes :after
 #'emacsvox--advice-wdired-abort-changes-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-finish-edit-after (&rest _)
  "Confirm interactively committing Wdired changes."
  (when (ems-interactive-p 'wdired-finish-edit)
    (emacsvox-icon 'save-object)
    (tts-with-punctuations 'some (dtk-speak "Committed changes. "))))

(advice-add
 'wdired-finish-edit :after #'emacsvox--advice-wdired-finish-edit-after
 '((name . emacsvox)))

(defun emacsvox--advice-wdired-change-to-wdired-mode-after (&rest _)
  "Confirm interactively entering Wdired mode."
  (when (ems-interactive-p 'wdired-change-to-wdired-mode)
    (emacsvox-icon 'open-object)
    (tts-with-punctuations 'some
                           (dtk-speak
                            "Entering writeable dir ed mode. "))))

(advice-add
 'wdired-change-to-wdired-mode :after
 #'emacsvox--advice-wdired-change-to-wdired-mode-after
 '((name . emacsvox)))

(provide 'emacsvox-wdired)
;;;  end of file
