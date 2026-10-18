;;; emacsvox-advice-completion.el --- Core completion feedback   -*- lexical-binding: t; -*-

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

;; Completion, expansion and candidate speech for the core advice facade.
;; The facade retains advice installation, face maps and key bindings in their
;; established order.  Generated interactive wrappers delegate feedback here.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-preamble)

(defun emacsvox--advice-pcomplete-list-after (&rest _)
  "Announce an interactive PComplete listing."
  (when (ems-interactive-p 'pcomplete-list)
    (emacsvox-icon 'help) (emacsvox-icon 'complete)))

(defun emacsvox--advice-pcomplete-show-completions-around
    (original &rest arguments)
  "Run ORIGINAL with PComplete messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(defun emacsvox--speak-completion-text (start end)
  "Speak completion text between START and END."
  (tts-speak (buffer-substring start end)))

(defun emacsvox--completion-around
    (target backward-syntax speaker original arguments)
  "Call ORIGINAL once and announce an interactive completion.
TARGET names the advised command.  BACKWARD-SYNTAX locates the beginning of
the completion before the call.  SPEAKER receives the resulting start and end
positions.  ARGUMENTS are passed to ORIGINAL unchanged."
  (let ((start
         (save-excursion
           (skip-syntax-backward backward-syntax)
           (point))))
    (let ((result (apply original arguments)))
      (when (ems-interactive-p target)
        (funcall speaker start (point))
        (emacsvox-icon 'complete))
      result)))

(defun emacsvox--advice-pcomplete-around (original &rest arguments)
  "Speak text completed by an interactive `pcomplete' call."
  (emacsvox--completion-around
   'pcomplete "^ >" #'emacsvox-speak-region original arguments))

(declare-function word-at-point "thingatpt" ())

(defmacro emacsvox-advice--define-completion-around-advice
    (targets helper)
  "Define native around advice using HELPER for each command in TARGETS."
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (original &rest arguments)
                 ,(format "Provide completion feedback for `%s'." target)
                 (,helper ',target original arguments))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        targets)))

(defun emacsvox--expanding-completion-around
    (target original arguments)
  "Call ORIGINAL once and announce expansion by TARGET.
ARGUMENTS are passed to ORIGINAL unchanged."
  (if (ems-interactive-p target)
      (let ((start
             (save-excursion
               (skip-syntax-backward "^ >")
               (point)))
            result)
        (ems-with-messages-silenced
          (setq result (apply original arguments))
          (emacsvox-icon 'complete)
          (if (< start (point))
              (tts-speak (buffer-substring start (point)))
            (tts-speak (word-at-point))))
        result)
    (apply original arguments)))

(declare-function emacsvox-vertico--note-minibuffer-content-presented
                  "emacsvox-vertico" nil)

(defun emacsvox--advice-completion-at-point-around
    (original &rest arguments)
  "Speak text completed by an interactive `completion-at-point' call."
  (emacsvox--completion-around
   'completion-at-point "^->_" #'emacsvox--speak-completion-text
   original arguments))

(defun emacsvox--advice-minibuffer-choose-completion-around
    (original &rest arguments)
  "Speak text inserted by interactive minibuffer completion."
  (emacsvox--completion-around
   'minibuffer-choose-completion "^ >_" #'emacsvox--speak-completion-text
   original arguments))

(defun emacsvox--advice-minibuffer-choose-completion-or-exit-after (&rest _)
  "Announce accepting or exiting minibuffer completion."
  (when (ems-interactive-p 'minibuffer-choose-completion-or-exit)
    (emacsvox-speak-line) (emacsvox-icon 'close-object)))

(defvar dabbrev--last-expansion)

(defun emacsvox--minibuffer-completion-around
    (target original arguments)
  "Call ORIGINAL once and announce minibuffer completion by TARGET.
ARGUMENTS are passed to ORIGINAL unchanged."
  (if (ems-interactive-p target)
      (let ((prior (point))
            result)
        (ems-with-messages-silenced
          (emacsvox-kill-buffer-carefully "*Completions*")
          (setq result (apply original arguments))
          (if (> (point) prior)
              (tts-with-punctuations
               'all (tts-speak (buffer-substring (point) prior)))
            (emacsvox-speak-completions-if-available)))
        result)
    (apply original arguments)))

(defun emacsvox--symbol-completion-around
    (_target original arguments)
  "Call ORIGINAL once and announce symbol completion.
ARGUMENTS are passed to ORIGINAL unchanged."
  (let ((prior
         (save-excursion
           (skip-syntax-backward "^ >")
           (point)))
        result)
    (ems-with-messages-silenced
      (setq result (apply original arguments))
      (if (> (point) prior)
          (tts-with-punctuations
           'all
           (tts-speak (buffer-substring prior (point))))
        (emacsvox-speak-completions-if-available)))
    result))

(defun emacsvox--advice-switch-to-completions-after (&rest _)
  "Speak the first completion after switching to the completions buffer."
  (emacsvox-icon 'select-object)
  (tts-speak (emacsvox-get-current-completion)))

(defun emacsvox--advice-choose-completion-before (&rest _)
  "Cue an interactive completion choice."
  (when (ems-interactive-p 'choose-completion)
    (emacsvox-icon 'button)))

(defun emacsvox--advice-tmm-goto-completions-after (&rest _)
  "Announce an interactive TMM completion."
  (when (ems-interactive-p 'tmm-goto-completions)
    (emacsvox-icon 'help)
    (tts-speak (emacsvox-get-current-completion))))

(defun emacsvox--advice-tmm-menubar-before (&rest _)
  "Cue opening the text-mode menu bar interactively."
  (when (ems-interactive-p 'tmm-menubar)
    (emacsvox-icon 'open-object)))

(defun emacsvox--advice-tmm-shortcut-after (&rest _)
  "Cue a TMM shortcut."
  (emacsvox-icon 'button))

(defun emacsvox--advice-semantic-complete-symbol-around
    (original &rest arguments)
  "Call ORIGINAL once and speak the resulting semantic completion."
  (let ((prior (point))
        (tts-stop-immediately t))
    (emacsvox-kill-buffer-carefully "*Completions*")
    (let ((result (apply original arguments)))
      (if (> (point) prior)
          (tts-with-punctuations 'all
            (emacsvox-speak-rest-of-buffer))
        (emacsvox-speak-completions-if-available))
      result)))

(defun emacsvox-advice-completion--history ()
  "Speak the history or completion element just inserted."
  (emacsvox-icon 'select-object)
  (tts-with-punctuations
   'all
   (tts-speak
    (or (minibuffer-contents)
        (emacsvox-get-current-completion))))
  (when
      (fboundp 'emacsvox-vertico--note-minibuffer-content-presented)
    (emacsvox-vertico--note-minibuffer-content-presented)))

(defun emacsvox-advice-completion--minibuffer-candidate ()
  "Speak the newly selected minibuffer completion."
  (tts-with-punctuations
   'all
   (emacsvox-icon 'item)
   (tts-speak (emacsvox-get-current-completion))))

(defun emacsvox-advice-completion--expansion ()
  "Speak the expanded dabbrev text."
  (accept-process-output)
  (tts-with-punctuations 'all (tts-speak dabbrev--last-expansion)))

(defun emacsvox-advice-completion--candidate ()
  "Speak the newly selected completion."
  (emacsvox-icon 'select-object)
  (tts-with-punctuations
   'all (tts-speak (emacsvox-get-current-completion))))

(provide 'emacsvox-advice-completion)

;;; emacsvox-advice-completion.el ends here
