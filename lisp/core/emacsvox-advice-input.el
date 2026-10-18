;;; emacsvox-advice-input.el --- Core prompts and minibuffer interaction   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995, 1996, 1997 by T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speech, Advice, Spoken output
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

;; Prompt and password feedback, question cues, and minibuffer setup/cleanup.
;; Keep password edit tracking, prompt caches and pronunciation state beside
;; their consumers.  The facade installs advice, hooks, face maps and keys.

;; Setup suppresses default-directory pronunciation when generic minibuffer
;; speech owns the content; completion UIs that own initial presentation retain
;; it.  Exit removes the temporary entry.  The dictionary also suppresses
;; pronunciation of emacsvox-media-shortcuts.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-preamble)

(defvar emacsvox-last-message)
(cl-declaim (special emacsvox-media-shortcuts))

(defvar read-passwd--password-hidden)

(defvar read-passwd--hide-password)

(defun emacsvox--advice-quoted-insert-after (&rest _)
  "Speak the character inserted by interactive `quoted-insert'."
  (when (ems-interactive-p 'quoted-insert)
    (emacsvox-speak-this-char (preceding-char))))

(defun emacsvox--advice-read-event-before (&optional prompt &rest _)
  "Speak PROMPT before reading an event."
  (when prompt (tts-speak prompt)))

(defun emacsvox--advice-read-multiple-choice-before
    (prompt choices &rest _)
  "Speak PROMPT and CHOICES before prompting."
  (let
      ((tts-stop-immediately nil)
       (spoken-choices
        (mapcar
         #'(lambda (c) (format "%c: %s" (cl-first c) (cl-second c)))
         choices))
       (details
        (mapcar
         #'(lambda (c)
             (format "%c: %s: %s" (cl-first c) (cl-second c)
                     (or (cl-third c) "")))
         choices)))
    (emacsvox-icon 'open-object)
    (ems--log-message
     (concat prompt (mapconcat #'identity details "\n ")))
    (tts-speak prompt)
    (sox-tones 2 2)
    (tts-speak-list spoken-choices)))

(defvar-local emacsvox--password-modified-tick nil
  "Character modification tick at the last password masking update.")

(defun emacsvox--password-hidden-p ()
  "Return whether password input is masked in the current minibuffer.
Emacs 30 and 31 use different names for the visibility state.
Treat unknown state as hidden."
  (cond
   ((boundp 'read-passwd--password-hidden) read-passwd--password-hidden)
   ((boundp 'read-passwd--hide-password) read-passwd--hide-password)
   (t t)))

(defun emacsvox--advice-read-passwd--hide-password-after (&rest _)
  "Give password feedback only when the input changes."
  ;; Masking also runs during setup and after navigation.  Text-property
  ;; changes made by masking must not count as password edits.
  (let* ((tick (buffer-chars-modified-tick))
         (changed (and emacsvox--password-modified-tick
                       (/= tick emacsvox--password-modified-tick))))
    (setq emacsvox--password-modified-tick tick)
    (when changed
      (tts-notify
       (if (or (emacsvox--password-hidden-p)
               (not (eq this-command 'self-insert-command)))
           "dot"
         (if (characterp last-input-event) (format "%c" last-input-event)
           "dot")))
      (emacsvox-icon 'repeat-active))))

(defun emacsvox--advice-read-passwd-toggle-visibility-after (&rest _)
  "Announce an interactive password visibility change."
  (when (ems-interactive-p 'read-passwd-toggle-visibility)
    (emacsvox-icon (if (emacsvox--password-hidden-p) 'off 'on))))

(defvar emacsvox-read-char-prompt-cache nil
  "Cache prompt from read-char etc.")

(defmacro emacsvox-advice--define-read-prompt-advice (targets)
  "Define native prompt advice for each key reader in TARGETS."
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-before" target))))
            `(progn
               (defun ,function (&optional prompt &rest _)
                 ,(format "Speak PROMPT before calling `%s'." target)
                 (setq emacsvox-last-message prompt)
                 (setq emacsvox-read-char-prompt-cache prompt)
                 (when emacsvox-speak-messages
                   (emacsvox-icon 'char)
                   (tts-with-punctuations
                    'all (tts-speak (or prompt "key")))))
               (advice-add
                ',target :before #',function '((name . emacsvox))))))
        targets)))

(defun emacsvox--advice-read-char-choice-before (prompt characters &rest _)
  "Speak PROMPT and permitted CHARACTERS before reading a choice."
  (let
      ((message
        (format "%s: %s" prompt
                (mapconcat
                 #'(lambda (character) (format "%c" character))
                 characters ", "))))
    (ems--log-message message)
    (tts-with-punctuations 'all (tts-speak message))))

(defvar emacsvox-minibuffer-dictionary
  (let ((table (make-hash-table)))
    (puthash emacsvox-media-shortcuts " " table)
    table)
  "Dictionary used in minibuffer.")

(declare-function emacsvox-vertico--owns-minibuffer-content-p
                  "emacsvox-vertico" nil)

(defun emacsvox-minibuffer-setup-hook ()
  "Actions to take when entering the minibuffer with emacsvox running."
  (tts-stop 'all)
  (let ((inhibit-field-text-motion t)
        (vertico-owns-content-p
         (and
          (fboundp 'emacsvox-vertico--owns-minibuffer-content-p)
          (emacsvox-vertico--owns-minibuffer-content-p))))
    (setq emacsvox-pronounce-table emacsvox-minibuffer-dictionary)
    (unless vertico-owns-content-p
      (puthash default-directory "" emacsvox-pronounce-table))
    (emacsvox-icon 'open-object)
    (when minibuffer-default (emacsvox-icon 'help))
    (cond
     ((bound-and-true-p read-passwd-mode)
      ;; Announce after the setup stop, and never include a default secret.
      (emacsvox-icon 'pwd)
      (tts-speak (minibuffer-prompt)))
     ((not vertico-owns-content-p)
      (tts-with-punctuations
       'all
       (tts-speak
        (concat
         (buffer-string)
         (if (stringp minibuffer-default) minibuffer-default ""))))))))

(defun emacsvox-minibuffer-exit-hook ()
  "Actions performed when exiting the minibuffer with Emacsvox loaded."
  (tts-stop 'all)
  (remhash  default-directory  emacsvox-pronounce-table)
  (emacsvox-icon 'close-object))

(defun emacsvox--question-around
    (question-icon yes-icon no-icon original arguments)
  "Call ORIGINAL with ARGUMENTS and cue the question and answer.
QUESTION-ICON is played before the call.  YES-ICON or NO-ICON is
played afterward according to the result."
  (emacsvox-icon question-icon)
  (let ((result (apply original arguments)))
    (emacsvox-icon (if result yes-icon no-icon))
    result))

(defun emacsvox--advice-yes-or-no-p-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS and cue a long question and answer."
  (emacsvox--question-around
   'ask-question 'yes-answer 'no-answer original arguments))

(defun emacsvox--advice-y-or-n-p-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS and cue a short question and answer."
  (emacsvox--question-around
   'ask-short-question 'y-answer 'n-answer original arguments))

(defun emacsvox--advice-ask-user-about-lock-around
    (original &rest arguments)
  "Call ORIGINAL once and cue an interactive lock question and answer."
  (if (ems-interactive-p 'ask-user-about-lock)
      (progn
        (emacsvox-icon 'ask-short-question)
        (let ((result (apply original arguments)))
          (emacsvox-icon (if result 'y-answer 'n-answer))
          result))
    (apply original arguments)))

(defun emacsvox--advice-ask-user-about-lock-help-after (&rest _)
  "Cue the display of lock-conflict help."
  (emacsvox-icon 'help))

(provide 'emacsvox-advice-input)

;;; emacsvox-advice-input.el ends here
