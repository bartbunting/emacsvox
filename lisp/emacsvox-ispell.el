;;; emacsvox-ispell.el --- Speech enable Ispell -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable ispell
;; Keywords: Emacsvox, Ispell, Spoken Output, Ispell version 2.30
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


;;; Commentary:
;; This module speech enables ispell.  Implementation note: This is
;; hard because of how ispell.el is written Namely, all of the work is
;; done by one huge hairy function.  This makes advising it hard.  The
;; ispell commands work well with Emacsvox as long as the list of
;; correction choices are few.  For interactively moving through
;; corrections, install package flyspell-correct from MELPA
;; (package-install "flyspell-correct") Then use M-x flyspell-mode.
;; Package flyspell is speech-enabled by Emacsvox module
;; emacsvox-flyspell And that module sets up flyspell-correct to use
;; IDO-style completion, i.e. you can move through corrections with
;; C-r and C-s.

;;; Code:

;;;  requires

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;   ispell command cl-loop:

;; defun ispell-command-loop (miss guess word start end)
;; Advice speaks the line containing the error with the erroneous
;; word highlighted.

(defgroup emacsvox-ispell nil
  "Spell checking group."
  :group  'emacsvox)

(defcustom emacsvox-ispell-max-choices 8
  "Emacsvox will not speak the choices if there are more than this
many available corrections."
  :type 'number
  :group 'emacsvox-ispell)

(defun emacsvox--advice-ispell-command-loop-before
    (choices _guess _word start end)
  "Speak the misspelled text and correction CHOICES from START to END."
  (let
      ((line nil) (pos ""))
    (setq line
          (ems-set-personality-temporarily start end voice-bolden
                                           (buffer-substring
                                            (line-beginning-position)
                                            (line-end-position))))
    (with-temp-buffer
      (setq voice-lock-mode t) (setq buffer-undo-list t)
      (dtk-set-punctuations 'all) (insert line)
      (cond
       ((< (length choices) emacsvox-ispell-max-choices)
        (cl-loop for choice in choices and position from 0 do
                 (setq pos
                       (propertize (format "%d" position) 'personality
                                   voice-smoothen))
                 (insert pos) (insert (format " %s\n" choice))))
       (t
        (insert (format "%s corrections available." (length choices)))))
      (modify-syntax-entry 10 ">") (dtk-speak (buffer-string)))))

(advice-add
 'ispell-command-loop :before
 #'emacsvox--advice-ispell-command-loop-before
 '((name . emacsvox)))

(defun ems--ispell-comments-and-strings-around (orig-fun &rest args)
  "Stop chatter by turning off messages"
  (cond
   ((ems-interactive-p)
    (let ((dtk-stop-immediately t))
      (ems-with-messages-silenced ad-do-it)
      (emacsvox-icon 'task-done)))
   (t ad-do-it)))

(advice-add 'ispell-comments-and-strings :around
            #'ems--ispell-comments-and-strings-around)

(defun emacsvox--advice-ispell-help-before (&rest _)
  "Speak the help message. "
  (let ((dtk-stop-immediately nil))
    (dtk-speak (documentation 'ispell-help))))

(advice-add
 'ispell-help :before #'emacsvox--advice-ispell-help-before
 '((name . emacsvox)))

;;;   Advice top-level ispell commands:

(cl-loop
 for f in
 '(ispell-buffer ispell-region)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Produce auditory icons for ispell."
     (cond
      ((ems-interactive-p)
       (let ((dtk-stop-immediately t))
         (ems-with-messages-silenced ad-do-it)
         (emacsvox-icon 'task-done)))
      (t ad-do-it))
     ad-return-value)))

(defun ems--ispell-word-around (orig-fun &rest args)
  "Produce auditory icons for ispell."
  (let ((result (apply orig-fun args)))
    
    (cond
     ((ems-interactive-p)
      (let ((dtk-stop-immediately t))
        (setq emacsvox-last-message nil)
        (ems-with-messages-silenced (apply orig-fun args))
        (emacsvox-speak-message-again) (emacsvox-icon 'task-done)))
     (t (apply orig-fun args)))
    result))

(advice-add 'ispell-word :around #'ems--ispell-word-around)

(provide 'emacsvox-ispell)
