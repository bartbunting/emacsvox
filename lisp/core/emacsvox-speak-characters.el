;;; emacsvox-speak-characters --- Character speech and typing feedback -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
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

;; Character speech and typing feedback.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)
(require 'emacsvox-aural-submission)

(declare-function emacsvox-speak-word "emacsvox-speak" (&optional arg))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))

;;;   line, Word and Character echo

(defvar-local emacsvox-line-echo nil
  "If t, then emacsvox echoes lines as you type.
You can use \\[emacsvox-toggle-line-echo] to set this
option.")

(ems-generate-switcher 'emacsvox-toggle-line-echo
                       'emacsvox-line-echo
                       "Toggle state of  Emacsvox  line echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defvar-local emacsvox-word-echo t
  "If t, then emacsvox echoes words as you type.
You can use \\[emacsvox-toggle-word-echo] to toggle this
option.")

(ems-generate-switcher 'emacsvox-toggle-word-echo
                       'emacsvox-word-echo
                       "Toggle state of  Emacsvox  word echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defvar-local emacsvox-character-echo t
  "If t, then emacsvox echoes characters  as you type.
You can
use \\[emacsvox-toggle-character-echo] to toggle this
setting.")

(ems-generate-switcher 'emacsvox-toggle-character-echo
                       'emacsvox-character-echo
                       "Toggle state of  Emacsvox  character echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

;;; Echo Typing Chars:

(defun emacsvox-post-self-insert-hook ()
  "Speaks the character if emacsvox-character-echo is true.
See  command emacsvox-toggle-word-echo bound to
\\[emacsvox-toggle-word-echo].
Speech flushes as you type."
  (when buffer-read-only (tts-speak "Buffer is read-only. "))
  (when
      (and (eq (preceding-char) last-command-event) ; Sanity check.
           (not executing-kbd-macro)
           (not noninteractive))
    (let ((display (get-char-property (1- (point)) 'display)))
      (tts-stop 'all)
      (cond
       ((stringp display) (tts-speak display))
       ((and emacsvox-word-echo
             (= (char-syntax last-command-event)32))
        (save-excursion
          (condition-case
              nil
              (forward-word -1)
            (error nil))
          (emacsvox-speak-word)))
       (emacsvox-character-echo
        (emacsvox-speak-this-char (preceding-char)))))))

(defsubst emacsvox-is-alpha-p (c)
  "Return non-nil if C is a letter or number spoken without a Unicode name.
Use Unicode categories rather than the buffer's word syntax: Org treats
apostrophes as word constituents.  Keep numbers on the letter/phonetic path
and respect `tts-unicode-untouched-charsets'."
  (and (memq (get-char-code-property c 'general-category)
             '(Lu Ll Lt Lm Lo Nd Nl No))
       (tts-unicode-char-untouched-p c)))

;;;   phonemic table

(defvar emacsvox-char-to-phonetic-table
  '(
    ("1" . "one")
    ("2" . "two")
    ("3" . "three")
    ("4" . "four")
    ("5" . "five")
    ("6" . "six")
    ("7" . "seven")
    ("8" . "eight")
    ("9" . "nine")
    ("0" .  "zero")
    ("a" . "alpha")
    ("b" . "bravo")
    ("c" . "charlie")
    ("d" . "delta")
    ("e" . "echo")
    ("f" . "foxtrot")
    ("g" . "golf")
    ("h" . "hotel")
    ("i" . "india")
    ("j" . "juliet")
    ("k" . "kilo")
    ("l" . "lima")
    ("m" . "mike")
    ("n" . "november")
    ("o" . "oscar")
    ("p" . "poppa")
    ("q" . "quebec")
    ("r" . "romeo")
    ("s" . "sierra")
    ("t" . "tango")
    ("u" . "uniform")
    ("v" . "victor")
    ("w" . "whisky")
    ("x" . "xray")
    ("y" . "yankee")
    ("z" . "zulu"))
  "Mapping from characters to their phonemic equivalents.")

(defun emacsvox-get-phonetic-string (char)
  "Return the phonetic string for CHAR while preserving capitalization.
An uppercase ASCII letter capitalizes the phonetic word's first character so
the normal semantic capitalization presentation handles its cue."
  (let* ((char-string (char-to-string char))
         (phonetic
          (cdr
           (assoc
            (downcase char-string)
            emacsvox-char-to-phonetic-table))))
    (cond
     ((and phonetic (char-uppercase-p char))
      (concat (upcase (substring phonetic 0 1)) (substring phonetic 1)))
     (phonetic)
     ((tts-unicode-full-name-for-char char))
     (char-string))))

;;;  Speak Chars:

(defvar emacsvox--delayed-phonetic-timer nil
  "Timer for the pending phonetic character announcement.")

(defvar emacsvox--delayed-phonetic-request nil
  "Identity and source snapshot of the pending phonetic announcement.")

(defun emacsvox--delayed-phonetic-cancel (&rest _)
  "Discard the pending phonetic announcement, if any."
  (when (timerp emacsvox--delayed-phonetic-timer)
    (cancel-timer emacsvox--delayed-phonetic-timer))
  (setq emacsvox--delayed-phonetic-timer nil
        emacsvox--delayed-phonetic-request nil))

(defcustom emacsvox-delayed-phonetic-delay 1.0
  "Seconds of idle time before describing a letter phonetically.
Must be a positive, finite number.  Used by
`emacsvox-delayed-phonetic-mode'; changing it cancels a pending announcement."
  :type 'number
  :group 'emacsvox
  :set (lambda (symbol value)
         (unless (and (numberp value) (> value 0) (= (- value value) 0))
           (error "Phonetic delay must be a positive, finite number"))
         (emacsvox--delayed-phonetic-cancel)
         (set-default symbol value)))

(define-minor-mode emacsvox-delayed-phonetic-mode
  "Describe letters phonetically after pausing during character navigation.
Speak the letter normally, then use the same phonetic name as
`emacsvox-speak-char' after `emacsvox-delayed-phonetic-delay' seconds idle.
Further input, speech, stopping speech or disabling this global mode cancels
the pending description.  Typing, deletion and explicit phonetic reading do
not schedule descriptions.  This mode is enabled by default."
  :global t
  :init-value t
  :group 'emacsvox
  (emacsvox--delayed-phonetic-cancel)
  (if emacsvox-delayed-phonetic-mode
      (add-hook 'pre-command-hook #'emacsvox--delayed-phonetic-cancel)
    (remove-hook 'pre-command-hook #'emacsvox--delayed-phonetic-cancel))
  (dolist (function '(tts-speak tts-letter tts-dispatch tts-stop))
    (if emacsvox-delayed-phonetic-mode
        (advice-add function :before #'emacsvox--delayed-phonetic-cancel)
      (advice-remove function #'emacsvox--delayed-phonetic-cancel))))

(defun emacsvox--delayed-phonetic-announce (request)
  "Describe the saved character if REQUEST is still current and unchanged."
  (when (eq request emacsvox--delayed-phonetic-request)
    (emacsvox--delayed-phonetic-cancel)
    (pcase-let
        ((`(,buffer ,window ,position ,tick ,events ,keys ,submission
                    ,process ,char ,context ,review-valid-p)
          request))
      (when (and emacsvox-delayed-phonetic-mode
                 (not (input-pending-p))
                 ;; Unlike `pre-command-hook', this also notices a prefix key
                 ;; while Emacs is waiting for the rest of its key sequence.
                 (= events num-nonmacro-input-events)
                 (= keys num-input-keys)
                 (= submission emacsvox-aural--submission-sequence)
                 (or review-valid-p (eq window (selected-window)))
                 (buffer-live-p buffer)
                 (eq buffer (window-buffer window)))
        (with-current-buffer buffer
          (when (and (not tts-quiet)
                     (eq process tts-speaker-process)
                     (= tick (buffer-chars-modified-tick))
                     (if review-valid-p
                         (funcall review-valid-p)
                       (and (= position (point))
                            (not (stringp (get-char-property position 'display))))))
            (let ((emacsvox-aural-submission-context context)
                  (emacsvox-aural-submission-occasion 'navigation))
              (tts-speak (emacsvox-get-phonetic-string char)))))))))

(defun emacsvox--delayed-phonetic-schedule (char &optional review-valid-p)
  "Remember navigated CHAR for one optional delayed phonetic announcement.
REVIEW-VALID-P, when non-nil, validates a separate review cursor instead of
point and the selected window.  It runs in the captured source buffer."
  (when (and emacsvox-delayed-phonetic-mode
             (not tts-quiet)
             (eq emacsvox-aural-submission-occasion 'navigation)
             (or review-valid-p (eq char (char-after)))
             (<= ?a (downcase char) ?z)
             (numberp emacsvox-delayed-phonetic-delay)
             (> emacsvox-delayed-phonetic-delay 0)
             (= (- emacsvox-delayed-phonetic-delay
                   emacsvox-delayed-phonetic-delay) 0))
    (emacsvox--delayed-phonetic-cancel)
    (setq emacsvox--delayed-phonetic-request
          (list (current-buffer) (selected-window) (point)
                (buffer-chars-modified-tick) num-nonmacro-input-events num-input-keys
                emacsvox-aural--submission-sequence tts-speaker-process char
                (emacsvox-aural-capture-context nil 'navigation)
                review-valid-p))
    (setq emacsvox--delayed-phonetic-timer
          (run-with-idle-timer
           emacsvox-delayed-phonetic-delay nil
           #'emacsvox--delayed-phonetic-announce
           emacsvox--delayed-phonetic-request))))

(defun emacsvox-speak-this-char (char)
  "Speak this CHAR."
  (when char
    (cond
     ((emacsvox-is-alpha-p char)
      (tts-letter (char-to-string char))
      (emacsvox--delayed-phonetic-schedule char))
     ((and tts-handle-unicode (> char 128)) (emacsvox-speak-char-name char))
     (t (tts-speak (tts-char-to-speech char))))))

(defun emacsvox-speak-char (&optional prefix)
  "Speak character under point.
Pronounces character phonetically unless  called with a PREFIX arg."
  (interactive "P")
  (let ((char (following-char))
        (display (get-char-property (point) 'display))
        (icon (get-char-property (point) 'auditory-icon)))
    (when icon (emacsvox-icon icon))
    (when display
      (emacsvox-icon 'ellipses)
      (and (listp display) (message "%s" (car display))))
    (when char
      (cond
       ((stringp display) (tts-speak display))
       ((and (not prefix)
             (emacsvox-is-alpha-p char))
        (tts-speak (emacsvox-get-phonetic-string char)))
       (t (emacsvox-speak-this-char char))))))

(defun emacsvox-speak-preceding-char ()
  "Speak character before point."
  (interactive)
  (let ((char (preceding-char))
        (display (get-char-property (max (point-min) (1- (point))) 'display)))
    (when char
      (cond
       ((stringp display) (tts-speak display))
       ((> char 128) (emacsvox-speak-char-name char))
       (t (emacsvox-speak-this-char char))))))

(defun emacsvox-speak-char-name (char)
  "tell me what this is"
  (interactive)
  (tts-speak (tts-unicode-name-for-char char)))

(provide 'emacsvox-speak-characters)

;;; emacsvox-speak-characters.el ends here
