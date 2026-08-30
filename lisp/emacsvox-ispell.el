;;; emacsvox-ispell.el --- Speech enable Ispell -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Ispell, Spoken Output, Ispell version 2.30
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; This module speech enables ispell.  Implementation note: This is
;; hard because of how ispell.el is written Namely, all of the work is
;; done by one huge hairy function.  This makes advising it hard.  The
;; ispell commands work well with Emacsvox as long as the list of
;; correction choices are few.  For interactively moving through
;; corrections, install package flyspell-correct from MELPA
;; (package-install "flyspell-correct") Then use M-x flyspell-mode.
;; Package flyspell is speech-enabled by Emacsvox module
;; emacsvox-flyspell.  That module uses standard completion by default, so
;; Vertico or another active completion frontend presents correction choices.
;; IDO, Popup, and Helm remain available as explicit alternatives.

;;; Code:

;;;  requires

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

(defvar emacsvox-last-message)
(defvar emacsvox-speak-messages)

;;;   ispell command cl-loop:

;; defun ispell-command-loop (miss guess word start end)
;; Advice speaks the line containing the error with the erroneous
;; word highlighted.

(defgroup emacsvox-ispell nil
  "Spell checking group."
  :group  'emacsvox)

(defcustom emacsvox-ispell-max-choices 8
  "Maximum number of correction choices Emacsvox will speak.
When Ispell returns more choices, Emacsvox speaks this many of the
highest-ranked corrections and announces the total."
  :type 'number
  :group 'emacsvox-ispell)

(defconst emacsvox-ispell--command-characters
  '(?\s ?i ?a ?A ?r ?R ?? ?x ?X ?q ?l ?u ?m)
  "Characters reserved for commands by `ispell-command-loop'.")

(defun emacsvox-ispell--choice-keys (count)
  "Return the first COUNT correction keys used by Ispell."
  (let ((key ?0)
        keys)
    (dotimes (_ count)
      (while (memq key emacsvox-ispell--command-characters)
        (setq key (1+ key)))
      (push key keys)
      (setq key (1+ key)))
    (nreverse keys)))

(defun emacsvox--advice-ispell-command-loop-before
    (choices _guess _word start end)
  "Speak the misspelled text and correction CHOICES from START to END."
  (let*
      ((line nil)
       (total (length choices))
       (limit (min total (max 0 emacsvox-ispell-max-choices)))
       (keys (emacsvox-ispell--choice-keys limit))
       (pos ""))
    (setq line
          (ems-set-personality-temporarily start end voice-bolden
                                           (buffer-substring
                                            (line-beginning-position)
                                            (line-end-position))))
    (with-temp-buffer
      (setq voice-lock-mode t) (setq buffer-undo-list t)
      (tts-set-punctuations 'all)
      (insert line "\n")
      (cond
       ((zerop total)
        (insert "No suggested corrections.\n"))
       (t
        (when (> total limit)
          (insert
           (format
            "%d corrections available; speaking the first %d.\n"
            total limit)))
        (insert "Choose by key.\n")
        (cl-loop
         for choice in choices
         for key in keys
         repeat limit do
         (setq pos
               (propertize
                (single-key-description key)
                'personality voice-smoothen))
         (insert pos)
         (insert (format " %s\n" choice)))))
      (insert "Space keeps the spelling.")
      (modify-syntax-entry 10 ">") (tts-speak (buffer-string)))))

(defun emacsvox--advice-ispell-command-loop-around
    (original choices guess word start end)
  "Speak CHOICES, then call ORIGINAL without generic prompt speech.
GUESS, WORD, START, and END are the remaining native arguments to
`ispell-command-loop'.  Generic message feedback is silenced while Ispell
waits for a correction key, but its visual prompt remains available."
  (emacsvox--advice-ispell-command-loop-before
   choices guess word start end)
  (let ((emacsvox-speak-messages nil))
    (funcall original choices guess word start end)))

(advice-remove
 'ispell-command-loop
 #'emacsvox--advice-ispell-command-loop-before)
(advice-add
 'ispell-command-loop :around
 #'emacsvox--advice-ispell-command-loop-around
 '((name . emacsvox)))

(defun emacsvox--ispell-call-with-completion-feedback
    (target original arguments)
  "Call ORIGINAL with ARGUMENTS and announce interactive TARGET completion."
  (if (ems-interactive-p target)
      (let ((tts-stop-immediately t))
        (let ((result
               (ems-with-messages-silenced
                 (apply original arguments))))
          (emacsvox-icon 'task-done)
          result))
    (apply original arguments)))

(defun emacsvox--advice-ispell-comments-and-strings-around
    (original &rest arguments)
  "Suppress chatter from interactive comment and string spell checking."
  (emacsvox--ispell-call-with-completion-feedback
   'ispell-comments-and-strings original arguments))

(advice-add
 'ispell-comments-and-strings :around
 #'emacsvox--advice-ispell-comments-and-strings-around
 '((name . emacsvox)))

(defun emacsvox--advice-ispell-help-before (&rest _)
  "Speak the help message. "
  (let ((tts-stop-immediately nil))
    (tts-speak (documentation 'ispell-help))))

(advice-add
 'ispell-help :before #'emacsvox--advice-ispell-help-before
 '((name . emacsvox)))

;;;   Advice top-level ispell commands:

(defun emacsvox--advice-ispell-buffer-around (original)
  "Suppress chatter from interactive whole-buffer spell checking."
  (emacsvox--ispell-call-with-completion-feedback
   'ispell-buffer original nil))

(advice-add
 'ispell-buffer :around #'emacsvox--advice-ispell-buffer-around
 '((name . emacsvox)))

(defun emacsvox--advice-ispell-region-around (original &rest arguments)
  "Suppress chatter from interactive region spell checking."
  (emacsvox--ispell-call-with-completion-feedback
   'ispell-region original arguments))

(advice-add
 'ispell-region :around #'emacsvox--advice-ispell-region-around
 '((name . emacsvox)))

(defun emacsvox--advice-ispell-word-around (original &rest arguments)
  "Produce auditory icons for ispell."
  (if (ems-interactive-p 'ispell-word)
      (let ((tts-stop-immediately t))
        (setq emacsvox-last-message nil)
        (let ((result
               (ems-with-messages-silenced
                 (apply original arguments))))
          (emacsvox-speak-message-again)
          (emacsvox-icon 'task-done)
          result))
    (apply original arguments)))

(advice-add
 'ispell-word :around #'emacsvox--advice-ispell-word-around
 '((name . emacsvox)))

(provide 'emacsvox-ispell)

;;; emacsvox-ispell.el ends here
