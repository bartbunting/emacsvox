;;; tts-speak.el --- Interface to speech server -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: TTS  Emacs Elisp
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
;; This module defines the generic TTS interface.
;;; Code:
;;

;;  required modules

(require 'cl-lib)
(require 'subr-x)
(require 'omnivox-remote)
(declare-function omnivox-engine-settings--environment "omnivox-engine-settings" (program))
(require 'emacsvox-aural-transport)
(require 'omnivox-punctuation-profiles)

;;;  Forward Declarations:

(defvar emacsvox-last-message)
(defvar emacsvox-speak-messages)
(defvar org-fold-core-style)
(defvar org-link-descriptive)
(defvar tts-default-voice)
(defvar tts-notify-process)
(defvar tts-speaker-process)
(defvar tts-punctuation-mode)
(defvar tts-split-caps)
(defvar tts-caps)
(defvar tts-speech-rate)
(defvar emacsvox-capitalization-presentation)
(defvar emacsvox-capitalization-presentation-values)
(defvar emacsvox-aural-source-invisible-property)
(defvar emacsvox-aural--source-visibility-captured-property)
(defvar emacsvox-aural--current-submission-id)
(defvar omnivox-default-voice-id)

(declare-function omnivox--negotiate-process "omnivox-voices" (process))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))

(declare-function ems--fastload "emacsvox-preamble" (file))
(declare-function emacsvox-aural-diagnostic-log-event
                  "emacsvox-aural-submission" (event &rest fields))
(declare-function emacsvox-aural--call-with-named-queue
                  "emacsvox-aural-transport" (name text function))
(declare-function voice-setup-get-voice-for-face "voice-setup" (face))
(declare-function emacsvox-icon "emacsvox-sounds.el" (icon))
(declare-function emacsvox-queue-icon "emacsvox-sounds.el" (icon))

;;;   TTS server configuration:

(defun tts--default-program ()
  "Return the configured speech-server program."
  (or
   (getenv "TTS_PROGRAM")
   (cond
    ((eq system-type 'darwin) "mac")
    (t "espeak"))))

(defvar tts-program
  (tts--default-program)
  "Speech-server program.

Omnivox is recommended for new installations.  Set the TTS_PROGRAM
environment variable to `omnivox' before loading Emacsvox.  When that
variable is unset, compatibility defaults select `mac' on macOS and
`espeak' elsewhere.  Other retained server names include `swiftmac',
`outloud', `dtk-exp', and `dtk-soft'.")

(defun tts--omnivox-program-p (&optional program)
  "Return non-nil when PROGRAM names the Omnivox server executable."
  (and
   (stringp (or program tts-program))
   (string-match-p
    "\\`omnivox\\(?:\\.exe\\)?\\'"
    (file-name-nondirectory (downcase (or program tts-program))))))

;;; Speech-server protocol:

;;;;  macros

(defmacro tts-with-punctuations (setting &rest body)
  "Set punctuation  and exec   body."
  (declare (indent 1) (debug t))
  (let ((requested-mode (make-symbol "requested-punctuation-mode")))
    `(let ((save-punctuation-mode tts-punctuation-mode)
           (,requested-mode ,setting))
       (unwind-protect
           (progn
             (unless (eq ,requested-mode save-punctuation-mode)
               (setq tts-punctuation-mode ,requested-mode)
               (when (process-live-p tts-speaker-process)
                 (tts--protocol-set-punctuations ,requested-mode)))
             ,@body)
         (unless (eq ,requested-mode save-punctuation-mode)
           (setq tts-punctuation-mode save-punctuation-mode)
           (when (process-live-p tts-speaker-process)
             (tts--protocol-set-punctuations save-punctuation-mode)))))))

;;;;  silence

(defun tts--protocol-silence (duration &optional force)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "sh %d%s\n"
           duration
           (if force "\nd" "")) (if force '(queue clear) 'queue)))

;;;;   tone

(defun tts--protocol-tone (pitch duration &optional force)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "t %d %d%s\n"
           pitch duration
           (if force "\nd" "")) (if force '(queue clear) 'queue)))

;;;;   queue

(defun tts--protocol-queue-text (text)
  
  (unless (string-match "^[[:space:]]+$" text)
    (emacsvox-aural--delivery-send-typed
     tts-speaker-process (format "q {%s }\n" text) 'queue)))

(defun tts--protocol-queue-code (code)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process (format "c {%s }\n" code) 'queue))

;;;;   speak

(defvar tts--dispatch-origin nil
  "Private origin of a producer's closing dispatch, or nil for an explicit flush.")

(defun tts--protocol-dispatch ()

  (emacsvox-aural--delivery-send-typed
   tts-speaker-process "d\n" 'clear
   (if (eq tts--dispatch-origin 'ordinary) 'ordinary-dispatch 'explicit-dispatch)))

(require 'tts-lifecycle)

;;;;  say

(defun tts--protocol-say (string)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "tts_say { %s}\n" string) 'interrupt))

;;;;  stop

(defun tts--protocol-stop ()
  
  (emacsvox-aural--delivery-send-typed tts-speaker-process "s\n" 'clear 'stop))

;;;;  sync

(defun tts--effective-capitalization-presentation ()
  "Return the capitalization presentation to send to the speech server."
  (if
      (and
       tts-caps
       (memq
        emacsvox-capitalization-presentation
        emacsvox-capitalization-presentation-values))
      emacsvox-capitalization-presentation
    'none))

(defun tts--protocol-sync-capitalization-presentation (&optional process)
  "Synchronize capitalization presentation with negotiated PROCESS.
PROCESS defaults to `tts-speaker-process'.  Older speech servers continue to
use their existing isolated-letter behavior."
  (let ((target (or process tts-speaker-process)))
    (when
        (and
         (processp target)
         (process-get target tts--capitalization-presentation-property))
      (emacsvox-aural--delivery-send-typed
       target
       (format
        "tts_set_capitalization_presentation %s\n"
        (tts--effective-capitalization-presentation)) 'neutral
       'sync-capitalization))))

(defun tts--protocol-sync ()
  "Synchronize speech state with running server"
  (tts--protocol-sync-capitalization-presentation)
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "tts_sync_state %s %s %s %s\n"
           (omnivox-punctuation-profiles--fallback tts-punctuation-mode)
           (if tts-split-caps 1 0)
           ;; Capitalization presentation is now carried by concrete aural
           ;; actions.  Disable legacy server-side scanning to avoid a second
           ;; cue for the same source boundary.
           0
           tts-speech-rate) 'neutral
   'sync-state)
  (when-let* ((command (omnivox-punctuation-profiles--command tts-punctuation-mode tts-speaker-process)))
    (emacsvox-aural--delivery-send-typed tts-speaker-process command 'neutral 'sync-punctuation-profile)))

;;;;   letter

(defun tts--protocol-letter (letter)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "l {%s}\n" letter) 'interrupt))

;;;;   language

(defun tts--require-legacy-language-protocol ()
  "Refuse legacy global language commands when the adapter has another owner."
  (when
      (eq
       (plist-get (tts-voice-capabilities) :language-selection)
       'logical-voices)
    (user-error
     "Omnivox routes language through logical voices; run M-x emacsvox-aural-voice-workbench")))

(defun tts--protocol-next-language (&optional say_it)
  (tts--require-legacy-language-protocol)
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "set_next_lang %s\n" say_it) 'neutral))

(defun tts--protocol-previous-language (&optional say_it)
  (tts--require-legacy-language-protocol)
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "set_previous_lang %s\n" say_it) 'neutral))

(defun tts--protocol-set-language (language say_it)
  (tts--require-legacy-language-protocol)
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "set_lang %s %s \n" language say_it) 'neutral))

(defun tts--protocol-set-preferred-language (alias language)
  (tts--require-legacy-language-protocol)
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "set_preferred_lang %s %s \n" alias language) 'neutral))

;;;;   Version, rate

(defun tts--protocol-version ()
  
  (emacsvox-aural--delivery-send-typed tts-speaker-process "version\n" 'neutral))

(defun tts--protocol-set-rate (rate)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "tts_set_speech_rate %s\n" rate) 'neutral))

;;;;  character scale

(defun tts--protocol-set-character-scale (factor)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "tts_set_character_scale %s\n"
           factor) 'neutral))

;;;;   split caps

(defun tts--protocol-set-split-caps (flag)
  
  (emacsvox-aural--delivery-send-typed
   tts-speaker-process
   (format "tts_split_caps %s\n" (if flag 1 0)) 'neutral))

;;;;  punctuations

(defun tts--protocol-set-punctuations (mode)
  "Set MODE through built-in and negotiated profile commands."
  (let ((profile (omnivox-punctuation-profiles--command mode tts-speaker-process)))
    (emacsvox-aural--delivery-send-typed
     tts-speaker-process
     (concat (format "tts_set_punctuations %s\n" (omnivox-punctuation-profiles--fallback mode))
             profile "d\n")
     (if profile '(neutral neutral clear) '(neutral clear)))))

;;;;  reset

(defun tts--protocol-reset ()
  
  (emacsvox-aural--delivery-send-typed tts-speaker-process "tts_reset \n" 'clear))

;;;   user customizations:

(defgroup tts nil
  "TTS." ;; ¿¿I guess this is shorthand for "Thou art Totally Screwed"??
  :group 'emacsvox
  :prefix "dtk-")

(defvar-local tts-strip-octals nil
  "Strip all octal chars. ")

(defcustom tts-hide-diagnostic-buffers t
  "Hide local speech-server diagnostic buffers from the standard buffer list.
When non-nil, their names start with a space.  Custom buffer switchers
may still list them.  Diagnostics are retained in either case; use
`tts-show-diagnostics' to inspect them.
Changes take effect when you restart speech with `tts-restart'."
  :type 'boolean
  :group 'tts)

(defcustom tts-speech-rate-base
  (if (string-match "dtk" tts-program) 180 50)
  "Value of lowest speech rate."
  :type 'integer
  :group 'tts)

(defcustom tts-speech-rate-step
  (if (string-match "dtk" tts-program) 50 8)
  "Speech rate step used by `tts-set-predefined-rate'."
  :type 'integer
  :group 'tts)

(defvar tts-handle-unicode nil
  "convert unicode characters if the speech server doesn't support it.
  This variable shouldn't usually be set")

(defvar-local tts-quiet nil
  "Silence speech ")

(defvar-local  tts-split-caps t
  "Flag indicating whether to use split caps.
 Use   `tts-toggle-split-caps'bound to \\[tts-toggle-split-caps].")

(defvar tts-cleanup-repeats
  (list
   ". " "." "_" "-" "=" "/" "+" "*" ":" ";" "%"
   "\\/" "/\\" "{" "}" "~" "$" ")" "#" "<>" "^" "<" ">")
  "List of repeating patterns to clean up.
Use `tts-add-cleanup-pattern'
 bound to \\[tts-add-cleanup-pattern]  to add  patterns.

More than 3 consecutive occurrences
of a  pattern   is
replaced with a repeat count. ")

;;;   internal variables

(defvar tts-character-scale 1.1
  "Factor used to  scale speech rate  when speaking letters.
  Use `tts-set-character-scale' bound to
\\[tts-set-character-scale].")

(defvar-local tts-caps nil
  "Non-nil means  indicate  capitalization.
The presentation is selected by `emacsvox-capitalization-presentation'.
Use `tts-toggle-caps' bound to \\[tts-toggle-caps].")

(defcustom emacsvox-capitalization-presentation 'tone
  "How enabled capitalization indication is presented.

`spoken' says \"cap\" or \"all caps\".  `tone' places a short tone at the
capitalized boundary, and `spoken-tone' combines both presentations.  `custom'
publishes capitalization facts for personal aural rules without adding a
built-in presentation.  `none' suppresses capitalization presentation while
leaving `tts-caps' enabled.  Camel-case splitting remains controlled
independently by `tts-split-caps'."
  :type
  '(choice
    (const :tag "Spoken cap or all caps" spoken)
    (const :tag "Capitalization tone" tone)
    (const :tag "Spoken label and tone" spoken-tone)
    (const :tag "Personal aural rules" custom)
    (const :tag "No capitalization presentation" none))
  :group 'emacsvox-aural)

(defcustom emacsvox-capitalization-capital-tone
  '(:pitch 440 :duration 20 :volume 1.0 :shape (:waveform sine))
  "Default tone for an individual capital letter.
The plist holds pitch in Hz, duration in milliseconds, volume from 0 to 1,
and a tone shape.  It applies to `tone' and `spoken-tone' presentations when
`tts-caps' is enabled.  Presentation rules can override these defaults.
Use the capitalization tone editor to preview waveforms and envelopes."
  :type '(plist :options ((:pitch number) (:duration number)
                         (:volume number) (:shape plist)))
  :group 'emacsvox-aural)

(defcustom emacsvox-capitalization-all-caps-tone
  '(:pitch 1300 :duration 20 :volume 1.0 :shape (:waveform sine))
  "Default tone for an all-capitals word.
The plist holds pitch in Hz, duration in milliseconds, volume from 0 to 1,
and a tone shape.  It applies to `tone' and `spoken-tone' presentations when
`tts-caps' is enabled.  Presentation rules can override these defaults.
Use the capitalization tone editor to preview waveforms and envelopes."
  :type '(plist :options ((:pitch number) (:duration number)
                         (:volume number) (:shape plist)))
  :group 'emacsvox-aural)

(defconst emacsvox-capitalization-presentation-values
  '(spoken tone spoken-tone custom none)
  "Supported values of `emacsvox-capitalization-presentation'.")

(defun emacsvox-set-capitalization-presentation (presentation &optional global)
  "Select capitalization PRESENTATION and preview representative text.

Set the option buffer-locally by default.  With interactive prefix GLOBAL,
also set the global default and use it in the current buffer."
  (interactive
   (list
    (intern
     (completing-read
      "Capitalization presentation: "
      (mapcar
       #'symbol-name emacsvox-capitalization-presentation-values)
      nil t nil nil
      (symbol-name emacsvox-capitalization-presentation)))
    current-prefix-arg))
  (unless (memq presentation emacsvox-capitalization-presentation-values)
    (user-error "Unknown capitalization presentation: %S" presentation))
  (when global
    (set-default 'emacsvox-capitalization-presentation presentation))
  (setq-local emacsvox-capitalization-presentation presentation)
  (when (called-interactively-p 'interactive)
    (let ((tts-caps t))
      (tts-speak "Capital camelCase NASA")))
  presentation)

(defconst tts-punctuation-mode-alist
  '("some" "all" "none")
  "List of  punctuation modes.")

(defcustom tts-punctuation-mode-policy-alist
  '((agent-shell-mode . all)
    (2048-mode . some)
    (eat-mode . all)
    (eshell-mode . all)
    (eww-mode . some)
    (Man-mode . all)
    (speedbar-mode . all)
    (sudoku-mode . some)
    (term-mode . all)
    (vterm-mode . all)
    (org-mode . some)
    (markdown-mode . some)
    (muse-mode . some)
    (LaTeX-mode . some)
    (TeX-mode . some)
    (texinfo-mode . some)
    (conf-unix-mode . all)
    (html-helper-mode . all)
    (sgml-mode . all)
    (xml-mode . all)
    (nxml-mode . all)
    (xsl-mode . all)
    (bibtex-mode . all)
    (prog-mode . all)
    (comint-mode . all)
    (text-mode . some))
  "Automatic punctuation modes, ordered from specific to general.

Each entry maps a major mode to `all', `some', `none', or
(profile ID FALLBACK), with a named Omnivox profile string and built-in fallback.  The first entry
for which `derived-mode-p' succeeds supplies the buffer policy.  A buffer
override set through `tts-set-punctuations' takes precedence.  When no entry
matches, the default value of `tts-punctuation-mode' is used."
  :type '(alist
          :key-type (symbol :tag "Major mode")
          :value-type
          (choice (const all) (const some) (const none)
                  (list :tag "Named Omnivox profile" (const profile) (string :tag "ID")
                        (choice :tag "Built-in fallback" (const all) (const some) (const none)))))
  :group 'tts)

(defvar-local tts-punctuation-mode-override nil
  "Explicit punctuation mode for this buffer, or nil for automatic policy.")

;; An explicit per-buffer choice should survive a major-mode transition.  The
;; automatic policy hook reapplies it after the mode has reset other locals.
(put 'tts-punctuation-mode-override 'permanent-local t)

(defvar tts--applying-punctuation-mode-policy nil
  "Non-nil while applying automatic punctuation state.")

(defvar-local tts-speech-rate
  100
  "Speech rate. Default rate is set via
    this is an internal variable; <tts-name>-default-speech-rate can
    be customized for the engine specific default.
 Use `tts-set-rate'
 bound to \\[tts-set-rate].")

;;; Style Helpers:

;; helper: Identify (a . b).
(defsubst tts-plain-cons-p (value)
  (and (consp value) (not (proper-list-p value))))

;; Helper: Get face->voice mapping

(defun tts-get-voice-for-face  (value)
    "Face->voice map"
    (when value
      (cond
       ((symbolp value) (voice-setup-get-voice-for-face value))
       ((tts-plain-cons-p value)) ;;pass on plain cons
       ((listp value)
        (delq nil (mapcar   #'voice-setup-get-voice-for-face value))))))

(defsubst tts-get-style (&optional pos)
  " Return  style based on personality or face at `POS'.   "
  (emacsvox-aural-filter-compatibility-voice
   (or
    (get-text-property (or pos (point)) 'personality)
    (tts-get-voice-for-face (get-text-property (or pos (point)) 'face)))))

;;;  helper: apply pronunciations

;; moved here from the emacsvox-pronounce module for efficient
;;compilation

;; Helper: like replace-match but preserves existing face or apply
;; 'match for pronunciation

(defun tts--replace-match-preserving-aural-plan
    (replacement &optional fixedcase literal subexp)
  "Replace the match with REPLACEMENT while retaining its concrete plan.

FIXEDCASE, LITERAL, and SUBEXP have the meanings accepted by
`replace-match'.  Semantic and contextual decisions are frozen before this
scratch-buffer cleanup, so replacement text must inherit the plan at the
start of the source match."
  (let ((start (match-beginning (or subexp 0)))
        (plan
         (get-text-property
          (match-beginning (or subexp 0))
          emacsvox-aural-concrete-plan-property))
        (positioned
         (get-text-property
          (match-beginning (or subexp 0))
          emacsvox-aural-concrete-positioned-actions-property)))
    (replace-match replacement fixedcase literal nil subexp)
    (when plan
      (put-text-property
       start (point) emacsvox-aural-concrete-plan-property plan))
    (when positioned
      (put-text-property
       start (point) emacsvox-aural-concrete-positioned-actions-property
       positioned))))

(defsubst tts-replace-match (replace)
  
  (let* ((start (match-beginning 0))
         (face
          (or
           (get-text-property start 'face) emacsvox-pronounce-personality)))
    (tts--replace-match-preserving-aural-plan replace t t)
    (when face (put-text-property start (point) 'face face))))

(defun tts-apply-pronunciations (pronunciation-table)
  "Applies pronunciations per pronunciation table to current buffer. "
  (cl-loop
   for w being the hash-keys of pronunciation-table do
   (let ((pronunciation (gethash w pronunciation-table)))
     (goto-char (point-min))
     (cond
      ((stringp pronunciation)
       ;; Also protect speech from old dictionaries and direct table edits.
       (when (equal w "")
         (user-error "Literal pronunciation terms must not be empty"))
       (while (search-forward w nil t)
         (tts--replace-pronunciation pronunciation)))
      ((consp pronunciation)
       (let ((matcher (car pronunciation))
             (pronouncer (cdr pronunciation))
             done)
         (while (and (not done) (funcall matcher w nil t))
           (let ((empty (= (match-beginning 0) (match-end 0)))
                 (replacement
                  (save-match-data
                    (funcall pronouncer
                             (buffer-substring
                              (match-beginning 0) (match-end 0))))))
             (tts--replace-pronunciation replacement)
             ;; A zero-width match consumes no source text.  Skip the next
             ;; source character, or finish after replacing at buffer end.
             ;; Nonempty matches may delete text without moving point.
             (when empty
               (if (eobp) (setq done t) (forward-char 1)))))))))))

;;;   Helpers to handle invisible text:

(defun tts--invisible-at-p (position)
  "Return non-nil when text at POSITION must be omitted from speech."
  (let ((hidden (get-char-property position emacsvox-aural-source-invisible-property)))
    (if (get-char-property position emacsvox-aural--source-visibility-captured-property)
        hidden
      ;; Older hidden snapshots and raw compatibility strings keep their
      ;; existing interpretation; captured visible text never consults this buffer.
      (or hidden (invisible-p position)))))

(defun tts--next-invisibility-change (position)
  "Return the next speech-invisibility boundary after POSITION."
  (let ((limit (point-max)))
    (min
     (next-single-property-change
      position 'invisible (current-buffer) limit)
     (next-single-property-change
      position emacsvox-aural-source-invisible-property
      (current-buffer) limit)
     (next-single-property-change
      position emacsvox-aural--source-visibility-captured-property
      (current-buffer) limit))))

(defun tts--previous-invisibility-change (position)
  "Return the previous speech-invisibility boundary before POSITION."
  (let ((limit (point-min)))
    (max
     (previous-single-property-change
      position 'invisible (current-buffer) limit)
     (previous-single-property-change
      position emacsvox-aural-source-invisible-property
      (current-buffer) limit)
     (previous-single-property-change
      position emacsvox-aural--source-visibility-captured-property
      (current-buffer) limit))))

(defun tts--skip-invisible-forward ()
  "Move across invisible text."
  (while (and (not (eobp))
              (tts--invisible-at-p (point)))
    (goto-char (tts--next-invisibility-change (point)))))

(defun tts--skip-invisible-backward ()
  "Move backwards over invisible text."
  (while (and (not (bobp))
              (tts--invisible-at-p (point)))
    (goto-char (tts--previous-invisibility-change (point)))))

(defun tts--delete-invisible-text ()
  "Delete invisible text."
  (goto-char (point-min))
  (let ((start (point)))
    (while (not (eobp))
      (cond
       ((tts--invisible-at-p (point))
        (tts--skip-invisible-forward)
        (delete-region start (point))
        (setq start (point)))
       (t (goto-char (tts--next-invisibility-change (point)))
          (setq start (point)))))))

;;;   Tones, Language, formatting speech etc.

(defun tts-silence (duration &optional force)
  "Produce `duration' ms of silence. "
  
  (unless tts-quiet
    (when (process-live-p tts-speaker-process)
      (tts--protocol-silence duration
                             (if force "\nd" "")))))

(defun tts-tone (pitch duration &optional force)
  "Produce a tone.
 Pitch   is  in hertz.
 Duration  is  in milliseconds.
Uses a 5ms fade-in and fade-out. "
  
  (unless (or tts-quiet (not (process-live-p tts-speaker-process)))
    (tts--protocol-tone pitch duration force)))

(defun tts-set-language (lang)
  "Set language. If your server supports it, also set the synthesis
 voice, using the syntax language:voice , where language can be
 omitted.  Adapters with logical-voice language routing reject this
 legacy global operation with an actionable error."
  (interactive "sEnter language: \n")
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-set-language lang nil)))
    (tts--protocol-set-language lang (called-interactively-p 'interactive))))

(defun tts-set-next-language ()
  "Switch to next legacy language.
Signal a user error when logical voices own language routing."
  (interactive)
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-next-language nil)))
    (tts--protocol-next-language (called-interactively-p 'interactive))))

(defun tts-set-previous-language ()
  "Switch to previous legacy language.
Signal a user error when logical voices own language routing."
  (interactive)
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-previous-language nil)))
    (tts--protocol-previous-language (called-interactively-p 'interactive))))

(defun tts-set-preferred-language (alias lang)
  "Set legacy language ALIAS to LANG.
Signal a user error when logical voices own language routing."
  (interactive "s")
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-set-preferred-language alias lang)))
    (tts--protocol-set-preferred-language alias lang)))

;; helper function:
;; Quote the string in current buffer so tcl does not barf.
;; Fix brackets by changing to text.
;; This is necessary because
;;  [] marks dtk commands; {} is special to tcl

(defconst tts-bracket-regexp
  "[][{}<>\\|`#\n]"
  "Brackets and other chars  that are special to dtk and tcl.
Newlines  become spaces so each server request is a single line.
{} is special to tcl.
[] is special to both dtk and tcl.
<> and | are fixed to improve pronunciation.
\\ is fixed because it tends to be a metacharacter")

(defun tts-strip-octals ()
  "Remove all octal chars."
  (let ((inhibit-read-only t))
    (goto-char (point-min))
    (while (re-search-forward "[\177-\377]+" nil t)
      (tts--replace-match-preserving-aural-plan " "))))

(defun tts-fix-brackets (mode)
  "Quote  delimiters that need special treatment. Argument MODE
specifies the current pronunciation mode --- See
\\[tts-bracket-regexp]"
  
  (let ((inhibit-read-only t))
    (goto-char (point-min))
    (cond
     ((eq 'all mode)
      (let ((start nil)
            (personality nil))
        (while (re-search-forward tts-bracket-regexp nil t)
          (setq start (match-beginning 0))
          (setq personality (tts-get-style (match-beginning 0)))
          (cond
           ((= 10 (char-after (match-beginning 0))) ; newline
            (tts--replace-match-preserving-aural-plan " "))
           ((= ?| (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " pipe " nil t))
           ((= ?< (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " less than " nil t))
           ((= ?> (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " greater than " nil t))
           ((= ?{ (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " left brace " nil t))
           ((= ?} (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " right brace " nil t))
           ((= ?\] (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan
             " right bracket " nil t))
           ((= ?\[ (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan
             " left bracket " nil t))
           ((= ?\\ (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " backslash " nil t))
           ((= ?# (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " pound " nil t))
           ((= ?` (char-after (match-beginning 0)))
            (tts--replace-match-preserving-aural-plan " backquote " nil t)))
          (when personality
            (put-text-property start (point)
                               'personality personality)))))
     (t
      (while (re-search-forward tts-bracket-regexp nil t)
        (tts--replace-match-preserving-aural-plan " " nil t))))))

(defvar-local tts-speak-nonprinting-chars nil
  "Speak non-printing chars.")

(defvar tts-octal-chars
  "[\000-\010\013\014\016-\037\177-\377]"
  "Regular expression matching control chars. ")

(defun tts-fix-control-chars ()
  "Handle control characters in speech stream."
  (let ((char nil))
    (goto-char (point-min))
    (cond
     (tts-strip-octals ;;;Strip octals if asked to
      (tts-strip-octals))
     (tts-speak-nonprinting-chars
      (while (re-search-forward tts-octal-chars nil t)
        (setq char (char-after (match-beginning 0)))
        (tts--replace-match-preserving-aural-plan
         (format " %s " (aref tts-character-to-speech-table char))
         nil t))))))
(defun tts--capitalization-word-character-p (character)
  "Return non-nil when CHARACTER continues a capitalization word."
  (and
   character
   (or
    (/= (upcase character) (downcase character))
    (get-char-code-property character 'numeric-value)
    (= character ?_))))

(defun tts--all-caps-run-character-p (character)
  "Return non-nil when CHARACTER may occur in an all-capitals run."
  (and
   character
   (or
    (char-uppercase-p character)
    (get-char-code-property character 'numeric-value)
    (memq character '(?_ ?-)))))

(defun tts--all-caps-run-end (text start)
  "Return the end of an all-capitals run in TEXT at START, or nil."
  (when
      (and
       (char-uppercase-p (aref text start))
       (or
        (zerop start)
        (not
         (tts--capitalization-word-character-p
          (aref text (1- start))))))
    (let ((end start)
          (length (length text))
          (count 0))
      (while
          (and
           (< end length)
           (tts--all-caps-run-character-p (aref text end)))
        (cl-incf end)
        (cl-incf count))
      (when
          (and
           (>= count 2)
           (or
            (= end length)
            (not
             (tts--capitalization-word-character-p
              (aref text end)))))
        end))))

(defun tts--capitalization-facts (kind)
  "Return semantic facts for capitalization KIND, or nil when disabled."
  (when
      (and
       tts-caps
       (not (eq emacsvox-capitalization-presentation 'none)))
    (let ((tone (if (eq kind 'capital) emacsvox-capitalization-capital-tone
                  emacsvox-capitalization-all-caps-tone)))
      (append
       (list :events '(capitalization-located)
             :capitalization-kind kind
             :capitalization-presentation emacsvox-capitalization-presentation)
       (when (memq emacsvox-capitalization-presentation '(tone spoken-tone))
         (list :capitalization-tone-pitch (plist-get tone :pitch)
               :capitalization-tone-duration (plist-get tone :duration)
               :capitalization-tone-volume (plist-get tone :volume)
               :capitalization-tone-shape (copy-tree (plist-get tone :shape))))))))

(defun tts--add-capitalization-annotation (text position facts positioned-p)
  "Add capitalization FACTS to TEXT at POSITION.
When POSITIONED-P is non-nil, preserve the surrounding speech run and attach
FACTS as an internal semantic position."
  (if positioned-p
      (let ((existing
             (copy-tree
              (get-text-property
               position emacsvox-aural-positioned-facts-property text))))
        (unless (member facts existing)
          (setq existing (append existing (list (copy-tree facts)))))
        (add-text-properties
         position (1+ position)
         (list emacsvox-aural-positioned-facts-property existing)
         text))
    (add-text-properties
     position (1+ position)
     (list
      emacsvox-aural-facts-property
      (emacsvox-aural-merge-facts
       (get-text-property position emacsvox-aural-facts-property text)
       facts))
     text)))

(defun tts--annotate-capitalization (text)
  "Return a copy of TEXT annotated at capitalized boundaries."
  (let ((result (copy-sequence text))
        (position 0)
        (length (length text))
        (positioned-p
         (eq emacsvox-capitalization-presentation 'tone)))
    (when-let* ((enabled (tts--capitalization-facts 'capital)))
      (while (< position length)
        (let ((all-caps-end
               (tts--all-caps-run-end text position)))
          (cond
           (all-caps-end
            (let ((facts (tts--capitalization-facts 'all-caps)))
              (tts--add-capitalization-annotation
               result position facts positioned-p))
            (setq position all-caps-end))
           (t
            (when (char-uppercase-p (aref text position))
              (tts--add-capitalization-annotation
               result position enabled positioned-p))
            (cl-incf position))))))
    result))

(add-hook
 'emacsvox-aural-source-annotation-functions
 #'tts--annotate-capitalization)

;; Takes a string, and replaces occurrences  of this pattern
;; that are longer than 3 by a string of the form \"count
;; string\". Second argument, mode, is the pronunciation
;; mode being used to speak.  Removing repeated chars, and
;; replacing them by a count:

(defun tts-replace-duplicates (string mode)
  "Replace repeating patterns.
 `STRING' is  the repeating string to replace.
` MODE' is  the current pronunciation mode."
  (let* ((inhibit-read-only t)
         (len (length string))
         (pattern (regexp-quote string))
         (reg
          (concat
           pattern pattern
           "\\(" pattern "\\)+"))
         (start nil)
         (personality nil)
         (replacement nil))
    (while (re-search-forward reg nil t)
      (setq personality (tts-get-style (match-beginning 0)))
      (setq replacement
            (if (eq 'all mode)
                (format
                 " aw %s %s"
                 (/ (- (match-end 0) (match-beginning 0)) len)
                 (if (string-equal " " string) " space " string))
              ""))
      (tts--replace-match-preserving-aural-plan replacement nil t)
      (setq start (- (point) (length replacement)))
      (when personality
        (put-text-property start (point) 'personality personality)))
    (goto-char (point-min))))

(defun tts-handle-repeating-patterns (mode)
  "Handle repeating patterns by replacing them with  `aw <length> char-names'"
  
  (when tts-cleanup-repeats
    (goto-char (point-min))
    (mapc
     #'(lambda (str)
         (tts-replace-duplicates str mode))
     tts-cleanup-repeats)))

(defun tts-quote (mode)
  "Clean-up text."
  (let ((inhibit-read-only t))
    ;; dtk will think it's processing a command otherwise:
    (tts-fix-brackets mode)
    ;; fix control chars
    (tts-fix-control-chars)))

(defun tts-fix-backslash ()
  "Quote backslash characters."
  (goto-char (point-min))
  (while (search-forward "\\" nil t)
    (tts--replace-match-preserving-aural-plan " backslash " nil t)))

;; Moving  across a chunk of text.
;; A chunk  is specified by a punctuation (todo? followed by whitespace)
;; or  multiple blank lines
;; or a comment start or end
;; or a parenthesis grouping start or end
;; leaves point at the end of the chunk.
;; returns  distance moved; nil if stationery
(defvar-local tts-chunk-separator-syntax ".>)$\""
  "Syntax classes  used when   splitting text.")

(defsubst tts-complement-chunk-separator-syntax ()
  "Return complement of syntactic class that splits clauses."
  
  (concat "^" tts-chunk-separator-syntax))

;; set chunk separator to match both whitespace and punctuations:
(defun tts-chunk-on-white-space-and-punctuations ()
  
  (setq tts-chunk-separator-syntax
        (concat tts-chunk-separator-syntax "-")))

(defun tts-chunk-only-on-punctuations ()
  
  (setq tts-chunk-separator-syntax
        (cl-delete-if
         #'(lambda (x) (= x ?-))
         tts-chunk-separator-syntax)))

;; invarianc: looking at complement
;; move across the complement and the following separator
;; return value is a boolean indicating if we moved.
;; side-effect is to move across a chunk
(defun tts-move-across-a-chunk (separator complement)
  "Move over a chunk of text.
Chunks are defined  based on major modes.
Argument SEPARATOR  is the syntax class of chunk separators.
Argument COMPLEMENT  is the complement of separator."
  (> (+ (skip-syntax-forward complement)
        (skip-syntax-forward separator))
     0))

(defun tts-speak-using-voice (voice text)
  "Use voice VOICE to speak text TEXT."
  
  (unless (or (eq 'inaudible voice)
              (null text) (string-equal text "")
              (and (listp voice) (memq 'inaudible voice)))
    ;; ensure text is a  string
    (unless (stringp text) (setq text (format "%s" text)))
    (emacsvox-aural--call-with-named-queue
     voice text (lambda () (tts--queue-using-voice voice text)))))

(defun tts--queue-using-voice (voice text)
  "Emit the original compatibility commands for VOICE and TEXT."
  (tts--protocol-queue-code
   (cond
    ((symbolp voice)
     (tts-get-voice-command
      (if (boundp voice)
          (symbol-value voice)
        voice)))
    ((listp voice)
     (mapconcat
      #'(lambda (v)
          (tts-get-voice-command
           (if (boundp v)
               (symbol-value v)
             v)))
      voice
      " "))
    (t "")))
  (tts--protocol-queue-text text)
  (tts--protocol-queue-code (tts-voice-reset-code)))

;; Internal function used by tts-speak to send text out.
;; Handles voice locking etc.
;; assumes in tts-scratch-buffer
;; start and end give the extent of the
;; text to be spoken.
;; note that property auditory-icon at the start  of a clause
;; causes the sound
;; to be queued.
;;
;; Similarly, property pause at the start of a clause specifies
;; amount of pause to insert.

(defsubst tts-next-single-property-change (start prop object limit)
  (let ((initial-value (get-text-property start prop object)))
    (cond
     ((atom initial-value)
      (next-single-property-change start prop object limit))
     (t
      (let ((pos start))
        (while
            (and (< pos limit)
                 (equal initial-value (get-text-property pos prop object)))
          (setq pos (next-single-property-change pos prop object limit)))
        pos)))))

;; Get position of previous style change from start to end. Here, style
;; change is any change in property personality, face or font-lock-face.

(defsubst tts-previous-style-change (start &optional end)
  (or end (setq end (point-min)))
  (max
   (previous-single-property-change start 'personality (current-buffer) end)
   (previous-single-property-change start 'face (current-buffer) end)
   (previous-single-property-change
    start 'font-lock-face (current-buffer) end)
   (previous-single-property-change
    start emacsvox-aural-concrete-plan-property
    (current-buffer) end)))

;; Get position of next style change from start   to end.
;; Here,  change is any change in property personality, face.
(defsubst tts-next-style-change (start &optional end)
  (or end (setq end (point-max)))
  (min
   (tts-next-single-property-change start 'personality (current-buffer) end)
   (tts-next-single-property-change start 'face (current-buffer) end)
   (tts-next-single-property-change
    start 'font-lock-face (current-buffer) end)
   (tts-next-single-property-change
    start emacsvox-aural-concrete-plan-property
    (current-buffer) end)))

(defun tts--concrete-plan-slice (plan start end)
  "Return PLAN and its leading pause clipped to START through END.

TTS may divide one concrete formatting run into several sentence chunks.
Only the first spoken chunk of a run may queue its before actions and leading
pause, even when TTS skips leading whitespace.  Only the chunk containing its
real end may queue its after actions and object-completion effects."
  (let* ((property emacsvox-aural-concrete-plan-property)
         (run-start
          (if (and
               (> start (point-min))
               (eq plan (get-text-property (1- start) property)))
              (previous-single-property-change
               start property nil (point-min))
            start))
         (continues-before
          (save-excursion
            (goto-char start)
            (skip-syntax-backward "-" run-start)
            (> (point) run-start)))
         (continues-after
          (and
           (< end (point-max))
           (eq plan (get-text-property end property))))
         (slice
          (if (or continues-before continues-after)
              (copy-emacsvox-aural-concrete-plan plan)
            plan)))
    (when continues-before
      (setf
       (emacsvox-aural-concrete-plan-before slice) nil
       (emacsvox-aural-concrete-plan-object-start-p slice) nil))
    (when continues-after
      (setf
       (emacsvox-aural-concrete-plan-after slice) nil
       (emacsvox-aural-concrete-plan-object-end-p slice) nil))
    (cons
     slice
     (unless continues-before
       (get-text-property run-start 'pause)))))

(defun tts--concrete-positioned-actions (start end &optional payload)
  "Return compiled actions positioned inside buffer text from START to END.
Offsets are UTF-8 byte offsets relative to START, matching the structured
timeline protocol.  PAYLOAD, when supplied, is the property-free text for
the same region and avoids extracting it again."
  (let ((position start)
        (payload (or payload (buffer-substring-no-properties start end)))
        (payload-position 0)
        (utf8-offset 0)
        result)
    (while (< position end)
      (when-let* ((actions
                   (get-text-property
                    position
                    emacsvox-aural-concrete-positioned-actions-property)))
        (push
         (list
          :utf8-offset
          utf8-offset
          :actions (copy-tree actions))
         result))
      (let* ((next
              (next-single-property-change
               position emacsvox-aural-concrete-positioned-actions-property
               (current-buffer) end))
             (next-payload-position
              (+ payload-position (- next position))))
        (cl-incf
         utf8-offset
         (string-bytes
          (substring payload payload-position next-payload-position)))
        (setq position next
              payload-position next-payload-position)))
    (nreverse result)))

(defun tts-audio-format (start end)
  "Format and speak text from `start' to `end'. "
  (if (emacsvox-aural-concrete-plan-at start)
      (let ((position start)
            runs)
        (while (< position end)
          (let* ((plan (emacsvox-aural-concrete-plan-at position))
                 (next
                  (next-single-property-change
                   position emacsvox-aural-concrete-plan-property
                   (current-buffer) end))
                 (payload
                  (buffer-substring-no-properties position next))
                 (slice
                  (tts--concrete-plan-slice plan position next)))
            (push
             (list
              (car slice)
              payload
              (cdr slice)
              (tts--concrete-positioned-actions position next payload))
             runs)
            (setq position next)))
        (emacsvox-aural-queue-concrete-runs (nreverse runs)))
    (when (and emacsvox-use-icons
               (get-text-property start 'auditory-icon))
      (emacsvox-queue-icon (get-text-property start 'auditory-icon)))
    (tts--protocol-queue-code (tts-voice-reset-code))
    (when-let* ((pause (get-text-property start 'pause)))
      (tts--protocol-silence pause))
    (cond
     ((not voice-lock-mode)
      (tts--protocol-queue-text (buffer-substring-no-properties start end)))
     (t                                 ; voiceify as we go
      (let ((last nil)
            (personality (tts-get-style start)))
        (while
            (and
             (< start end)
             (setq last (tts-next-style-change start end)))
          (if personality
              (tts-speak-using-voice
               personality (buffer-substring-no-properties start last))
            (tts--protocol-queue-text
             (buffer-substring-no-properties start last)))
          (setq
           start last
           personality (tts-get-style last))
          (when (get-text-property start 'pause)
            (tts--protocol-silence
             (get-text-property start 'pause) nil))))))))

;; Write out the string to the tts via TCL.
;; No quoting is done,
;; ifyou want to quote the text, see tts-speak

(defun tts-dispatch (string)
  "Send request  to speech server."
  (unless tts-quiet
    (when (process-live-p tts-speaker-process)
      (tts--protocol-say string))))

(defun tts-stop (&optional all)
  "Stop speech.
Optional argument ALL or an interactive call also stops a distinct
notification process."
  (interactive "P")
  (let ((owners (list tts-speaker-process)))
    (when
        (and
         (or all (called-interactively-p 'interactive))
         (process-live-p tts-notify-process)
         (not (eq tts-notify-process tts-speaker-process)))
      (setq owners (append owners (list tts-notify-process))))
    (dolist (owner owners) (tts--preparation-invalidate owner))
    (dolist (owner owners)
      (emacsvox-aural-cancel-pending-deliveries owner)
      (tts--interrupt-process owner))))

(defun tts-reset-default-voice ()
  
  (tts-dispatch (tts-get-voice-command tts-default-voice)))

;;;   adding cleanup patterns:

(defun tts-add-cleanup-pattern (&optional delete)
  "Add this pattern to the list of repeating patterns.
  Optional interactive prefix arg deletes
this pattern if previously added.    "
  (interactive "P")
  
  (cond
   (delete
    (setq tts-cleanup-repeats
          (delete
           (read-from-minibuffer "Specify repeating pattern to delete: ")
           tts-cleanup-repeats)))
   (t
    (cl-pushnew (read-from-minibuffer "Specify repeating pattern: ")
                tts-cleanup-repeats
                :test #'string-equal))))

;;;  helper --generate state switcher:

(defun ems-generate-switcher (command switch documentation)
  "Generate  command to switch  state."
  (eval
   `(defun ,command (&optional prefix)
      ,documentation
      (interactive "P")
      
      (cond
       (prefix
        (setq-default ,switch (not ,switch))
        (setq ,switch (default-value ',switch)))
       (t (setq ,switch (not ,switch))))
      (tts--protocol-sync)
      (when (called-interactively-p 'interactive)
        (emacsvox-icon (if ,switch 'on 'off))
        (message
         (format "Turned %s %s  %s."
                 (if ,switch "on" "off")
                 ',switch
                 (if prefix "" " locally")))))))

;;;   sending commands

(defun tts-set-rate (rate &optional prefix)
  "Set speaking RATE.
Interactive PREFIX arg means set   the global default value, and then set the
current local  value to the result."
  (interactive
   (list (read-from-minibuffer "Enter new rate: ")
         current-prefix-arg))
  (when (process-live-p tts-speaker-process)
    (cond
     (prefix
      (unless (eq tts-speaker-process (tts-notify-process))
        (let ((tts-speaker-process (tts-notify-process)))
          (tts-set-rate rate prefix)))
      (setq-default tts-speech-rate rate)
      (setq tts-speech-rate rate))
     (t (setq tts-speech-rate rate)))
    (tts--protocol-set-rate rate)
    (when (called-interactively-p 'interactive)
      (message "Set speech rate to %s %s"
               rate
               (if prefix "" "locally")))))

(defun tts-set-predefined-rate (&optional prefix)
  "Set speech rate to one of nine predefined levels.
Interactive PREFIX arg says to set the rate globally.
Formula used is:
rate = tts-speech-rate-base + tts-speech-rate-step * level."
  (interactive "P")
  (let ((level
         (condition-case nil
             (read (format "%c" last-input-event))
           (error nil))))
    (or (numberp level)
        (setq level
              (read-minibuffer "Enter level between 1 and 9:")))
    (cond
     ((or (not (numberp level))
          (< level 0)
          (> level 9))
      (error "Invalid level %s" level))
     (t (tts-set-rate
         (+ tts-speech-rate-base (* tts-speech-rate-step level))
         prefix)
        (when (called-interactively-p 'interactive)
          (message "Set speech rate to level %s %s"
                   level
                   (if prefix "" "locally")))))))

(defun tts-rate-adjust ()
  "Adjust speech rate in current buffer, inspired by
  text-scale-adjust.   Invoke this command via C-e d =/+ or
C-impel-d -. Pressing =,+, or - immediately continues to adjust
the speech rate.  Call when on a non-blank line to preview the effectt"
  (interactive )
  
  (let* ((base (event-basic-type last-command-event))
         (step
          (pcase base
            ((or ?+ ?=) tts-speech-rate-step)
            (?- (- tts-speech-rate-step))
            (_ tts-speech-rate-step))))
    (emacsvox-icon 'repeat-start)
    (tts-set-rate (+ tts-speech-rate  step))
    (emacsvox-speak-line)
    (emacsvox-icon (if (cl-minusp step) 'left 'right))
    (set-transient-map
     (let ((map (make-sparse-keymap)))
       (dolist (key '("=" "+" "-")) ;; = is often unshifted +.
         (define-key map key (lambda () (interactive) (tts-rate-adjust ))))
       map)
     t (lambda nil (emacsvox-icon 'repeat-end))
     (format "%s: Repeat with %%k" tts-speech-rate))))

(defun tts-set-character-scale (factor &optional prefix)
  "Set character scale FACTOR for   speech rate.
Speech rate is scaled by this factor when speaking characters.
Not presently used by either Dectalk or Viavoice TTS.
Interactive PREFIX arg means set the global default value, and
then set the current local value to the result."
  (interactive "nEnter new factor:\nP")
  (when (process-live-p tts-speaker-process)
    (cond
     (prefix
      (setq-default tts-character-scale factor)
      (setq tts-character-scale factor))
     (t (make-local-variable 'tts-character-scale)
        (setq tts-character-scale factor)))
    (tts--protocol-set-character-scale tts-character-scale)
    (when (called-interactively-p 'interactive)
      (message "Set character scale factor to %s %s"
               tts-character-scale
               (if prefix "" "locally")))))

(ems-generate-switcher
 'tts-toggle-quiet
 'tts-quiet
 "Toggles state of  tts-quiet.
Turning on this switch silences speech.  Optional interactive
prefix arg causes this setting to become global.")

(ems-generate-switcher
 'tts-toggle-split-caps
 'tts-split-caps
 "Toggle split caps mode.
Split caps mode is useful when reading Hungarian notation in
program source code.  Interactive PREFIX arg means toggle the
global default value, and then set the current local value to the
result.")

(ems-generate-switcher
 'tts-toggle-strip-octals
 'tts-strip-octals
 "Toggle stripping of octals.
Interactive prefix arg means
 toggle the global default value, and then set the current local
value to the result.")
(ems-generate-switcher
 'tts-toggle-caps
 'tts-caps
 "Toggle tts-caps.
Interactive PREFIX arg means toggle the global default
value, and then set the current local value to the result.")

(ems-generate-switcher
 'tts-toggle-speak-nonprinting-chars
 'tts-speak-nonprinting-chars
 "Toggle speak-nonprinting-chars.
Interactive PREFIX arg means toggle the global default
value, and then set the current local value to the result.")

(defun tts--punctuation-mode-policy-entry ()
  "Return the first automatic punctuation policy matching this buffer."
  (cl-find-if
   (lambda (entry) (derived-mode-p (car entry)))
   tts-punctuation-mode-policy-alist))

(defun tts-punctuation-mode-state ()
  "Return the effective punctuation mode and its source for this buffer.

The result is a plist containing `:mode', `:source-kind', and `:source'."
  (let ((entry (tts--punctuation-mode-policy-entry)))
    (cond
     (tts-punctuation-mode-override
      (list :mode tts-punctuation-mode-override
            :source-kind 'buffer-override
            :source 'buffer))
     (entry
      (list :mode (cdr entry)
            :source-kind 'mode-policy
            :source (car entry)))
     (t
      (list :mode (default-value 'tts-punctuation-mode)
            :source-kind 'global-default
            :source 'global)))))

(defun tts--punctuation-mode-description (&optional state)
  "Describe punctuation STATE, defaulting to the current buffer state."
  (let* ((state (or state (tts-punctuation-mode-state)))
         (mode (plist-get state :mode))
         (kind (plist-get state :source-kind))
         (source (plist-get state :source)))
    (format
     "Punctuation %s, %s"
     (omnivox-punctuation-profiles--describe mode)
     (pcase kind
       ('buffer-override "buffer override")
       ('mode-policy (format "%s policy" source))
       (_ "global default")))))

(defun tts-apply-punctuation-mode-policy ()
  "Apply this buffer's punctuation override, mode policy, or global default."
  (let* ((state (tts-punctuation-mode-state))
         (mode (plist-get state :mode))
         (tts--applying-punctuation-mode-policy t))
    (tts-set-punctuations mode)
    state))

(defun tts-set-punctuations (mode &optional prefix)
  "Set punctuation mode to MODE.
Values are `some', `all', `none', or (profile ID FALLBACK).
Named profiles require matching worker catalogues; otherwise use FALLBACK.
Interactive PREFIX arg means set   the global default value, and then set the
current local  value to the result."
  (interactive (list (omnivox-punctuation-profiles--read) current-prefix-arg))
  (omnivox-punctuation-profiles--fallback mode)
  (cond
   (prefix
    (setq tts-punctuation-mode mode)
    (setq-default tts-punctuation-mode mode))
   (t (make-local-variable 'tts-punctuation-mode)
      (setq tts-punctuation-mode mode)))
  (unless tts--applying-punctuation-mode-policy
    (setq-local tts-punctuation-mode-override mode))
  (when (process-live-p tts-speaker-process)
    (tts--protocol-set-punctuations mode))
  (when (called-interactively-p 'interactive)
    (message
     "%s%s"
     (tts--punctuation-mode-description)
     (if prefix "; global default also changed" ""))))

(defun tts-set-punctuations-to-all (&optional prefix)
  "Set punctuation  mode to all.
Interactive PREFIX arg sets punctuation mode globally."
  (interactive "P")
  (tts-set-punctuations 'all prefix))

(defun tts-set-punctuations-to-some (&optional prefix)
  "Set punctuation  mode to some.
Interactive PREFIX arg sets punctuation mode globally."
  (interactive "P")
  (tts-set-punctuations 'some prefix))

(defun tts-toggle-punctuation-mode (&optional prefix)
  "Toggle punctuation mode between \"some\" and \"all\".
Interactive PREFIX arg makes the new setting global."
  (interactive "P")
  
  (cond
   ((eq 'all (omnivox-punctuation-profiles--fallback tts-punctuation-mode))
    (tts-set-punctuations-to-some prefix))
   ((memq (omnivox-punctuation-profiles--fallback tts-punctuation-mode) '(some none))
    (tts-set-punctuations-to-all prefix)))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'button)
    (message
     "%s%s"
     (tts--punctuation-mode-description)
     (if prefix "; global default also changed" ""))))

(defun tts-reset-punctuation-mode ()
  "Clear the buffer override and restore automatic punctuation policy."
  (interactive)
  (kill-local-variable 'tts-punctuation-mode-override)
  (let ((state (tts-apply-punctuation-mode-policy)))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'button)
      (message "%s" (tts--punctuation-mode-description state)))
    state))

(defun tts-reset-state ()
  "Reset TTS engine."
  (interactive)
  (when (process-live-p tts-speaker-process)
    (tts--protocol-reset)))

(defun tts-speak-version ()
  "Speak version."
  (interactive)
  (tts--protocol-version))

;;;   Internal variables:

(defvar tts-stop-immediately t
  "If t, speech stopped immediately when new speech received.
Emacsvox sets this to nil if the current message being spoken is too
important to be interrupted.")

(defvar tts-stopped-hook nil
  "Functions called with the stopped speech process as their argument.")

(defvar tts-speaker-process nil
  "Speaker process handle.")

(defvar tts-notify-process nil
  "Notify speaker  process handle.")

(defvar-local tts-punctuation-mode 'all
  "Punctuation state (some, all or none).
Set by \\[tts-set-punctuations].")

(defvar tts-servers-alist nil
  "Speech servers.")

(defun tts-setup-servers-alist ()
  "Read servers/.servers"
  
  (let ((result nil)
        (servers
         (find-file-noselect
          (expand-file-name ".servers" emacsvox-servers-directory)))
        (this nil))
    (with-current-buffer servers
      (goto-char (point-min))
      (while (not (eobp))
        (unless
            (looking-at "^#")
          (setq this
                (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position)))
          (push this result))
        (forward-line 1)))
    (setq tts-servers-alist result)))

;;;   Mapping characters to speech:

(defvar tts-character-to-speech-table
  (make-vector 256 "")
  "Maps characters to pronunciation strings.")

;;  Assign entries in the table:
(defun tts-speak-setup-character-table ()
  "Setup pronunciations in the character table for theTTS engine."
  (let ((table tts-character-to-speech-table))
    (aset table 0 "control at")
    (aset table 1 "control a")
    (aset table 2 "control b")
    (aset table 3 "control c")
    (aset table 4 "control d")
    (aset table 5 "control e")
    (aset table 6 "control f")
    (aset table 7 "control g")
    (aset table 8 "control h")
    (aset table 9 "tab")
    (aset table 10 "newline")
    (aset table 11 "control k")
    (aset table 12 "control l")
    (aset table 13 "control m")
    (aset table 14 "control n")
    (aset table 15 "control o")
    (aset table 16 "control p")
    (aset table 17 "control q")
    (aset table 18 "control r")
    (aset table 19 "control s")
    (aset table 20 "control t")
    (aset table 21 "control u")
    (aset table 22 "control v")
    (aset table 23 "control w")
    (aset table 24 "control x")
    (aset table 25 "control y")
    (aset table 26 "control z")
    (aset table 27 "escape")
    (aset table 28 "control backslash")
    (aset table 29 "control right bracket")
    (aset table 30 "control caret")
    (aset table 31 "control underscore")
    (aset table 32 "space")
    (aset table 33 "exclamation")
    (aset table 34 "quotes")
    (aset table 35 "pound")
    (aset table 36 "dollar")
    (aset table 37 "percent")
    (aset table 38 "ampersand")
    (aset table 39 "apostrophe")
    (aset table 40 "left paren")
    (aset table 41 "right paren")
    (aset table 42 "star")
    (aset table 43 "plus")
    (aset table 44 "comma")
    (aset table 45 "dash")
    (aset table 46 "dot")
    (aset table 47 "slash")
    (aset table 48 "zero")
    (aset table 49 "one")
    (aset table 50 "two")
    (aset table 51 "three")
    (aset table 52 "four")
    (aset table 53 "five")
    (aset table 54 "six")
    (aset table 55 "seven")
    (aset table 56 "eight")
    (aset table 57 "nine")
    (aset table 58 "colon")
    (aset table 59 "semi")
    (aset table 60 "less than")
    (aset table 61 "equals")
    (aset table 62 "greater than")
    (aset table 63 "question mark")
    (aset table 64 "at")
    (aset table 65 " cap a")
    (aset table 66 " cap b")
    (aset table 67 "cap c")
    (aset table 68 "cap d")
    (aset table 69 "cap e")
    (aset table 70 "cap f")
    (aset table 71 "cap g")
    (aset table 72 "cap h")
    (aset table 73 "cap i")
    (aset table 74 "cap j")
    (aset table 75 "cap k")
    (aset table 76 "cap l")
    (aset table 77 "cap m")
    (aset table 78 "cap n")
    (aset table 79 "cap o")
    (aset table 80 "cap p")
    (aset table 81 "cap q")
    (aset table 82 "cap r")
    (aset table 83 "cap s")
    (aset table 84 "cap t")
    (aset table 85 "cap u")
    (aset table 86 "cap v")
    (aset table 87 "cap w")
    (aset table 88 "cap x")
    (aset table 89 "cap y")
    (aset table 90 "cap z")
    (aset table 91 "left bracket")
    (aset table 92 "backslash")
    (aset table 93 "right bracket")
    (aset table 94 "caret")
    (aset table 95 "underscore")
    (aset table 96 "backquote")
    (aset table 97 "a")
    (aset table 98 "b")
    (aset table 99 "c")
    (aset table 100 "d")
    (aset table 101 "e")
    (aset table 102 "f")
    (aset table 103 "g")
    (aset table 104 "h")
    (aset table 105 "i")
    (aset table 106 "j")
    (aset table 107 "k")
    (aset table 108 "l")
    (aset table 109 "m")
    (aset table 110 "n")
    (aset table 111 "o")
    (aset table 112 "p")
    (aset table 113 "q")
    (aset table 114 "r")
    (aset table 115 "s")
    (aset table 116 "t")
    (aset table 117 "u")
    (aset table 118 "v")
    (aset table 119 "w")
    (aset table 120 "x")
    (aset table 121 "y")
    (aset table 122 "z")
    (aset table 123 "left brace")
    (aset table 124 "pipe")
    (aset table 125 "right brace ")
    (aset table 126 "tilde")
    (aset table 127 "backspace")
    ;; Characters with the 8th bit set:
    (aset table 128 " octal 200 ")
    (aset table 129 " ")                ;shows up on WWW pages
    (aset table 130 " octal 202 ")
    (aset table 131 " octal 203 ")
    (aset table 132 " octal 204 ")
    (aset table 133 " octal 205 ")
    (aset table 134 " octal 206 ")
    (aset table 135 " octal 207 ")
    (aset table 136 " octal 210 ")
    (aset table 137 " octal 211 ")
    (aset table 138 " octal 212 ")
    (aset table 139 " octal 213 ")
    (aset table 140 " octal 214 ")
    (aset table 141 " octal 215 ")
    (aset table 142 " octal 216 ")
    (aset table 143 " octal 217 ")
    (aset table 144 " octal 220 ")
    (aset table 145 " octal 221 ")
    (aset table 146 " '  ")
    (aset table 147 " quote  ")
    (aset table 148 " octal 224 ")
    (aset table 149 " octal 225 ")
    (aset table 150 " octal 226 ")
    (aset table 151 " octal 227 ")
    (aset table 152 " octal 230 ")
    (aset table 153 " octal 231 ")
    (aset table 154 " octal 232 ")
    (aset table 155 " octal 233 ")
    (aset table 156 " octal 234 ")
    (aset table 157 " octal 235 ")
    (aset table 158 " octal 236 ")
    (aset table 159 " octal 237 ")
    (aset table 160 "  ")               ;non breaking space
    (aset table 161 " octal 241 ")
    (aset table 162 " octal 242 ")
    (aset table 163 " octal 243 ")
    (aset table 164 " octal 244 ")
    (aset table 165 " octal 245 ")
    (aset table 166 " octal 246 ")
    (aset table 167 " octal 247 ")
    (aset table 168 " octal 250 ")
    (aset table 169 " copyright ")      ;copyright sign
    (aset table 170 " octal 252 ")
    (aset table 171 " octal 253 ")
    (aset table 172 " octal 254 ")
    (aset table 173 "-")                ;soft hyphen
    (aset table 174 " (R) ")            ;registered sign
    (aset table 175 " octal 257 ")
    (aset table 176 " octal 260 ")
    (aset table 177 " octal 261 ")
    (aset table 178 " octal 262 ")
    (aset table 179 " octal 263 ")
    (aset table 180 " octal 264 ")
    (aset table 181 " octal 265 ")
    (aset table 182 " octal 266 ")
    (aset table 183 " octal 267 ")
    (aset table 184 " octal 270 ")
    (aset table 185 " octal 271 ")
    (aset table 186 " octal 272 ")
    (aset table 187 " octal 273 ")
    (aset table 188 " octal 274 ")
    (aset table 189 " octal 275 ")
    (aset table 190 " octal 276 ")
    (aset table 191 " octal 277 ")
    (aset table 192 " octal 300 ")
    (aset table 193 " octal 301 ")
    (aset table 194 " octal 302 ")
    (aset table 195 " octal 303 ")
    (aset table 196 " octal 304 ")
    (aset table 197 " octal 305 ")
    (aset table 198 " octal 306 ")
    (aset table 199 " octal 307 ")
    (aset table 200 " octal 310 ")
    (aset table 201 " octal 311 ")
    (aset table 202 " octal 312 ")
    (aset table 203 " octal 313 ")
    (aset table 204 " octal 314 ")
    (aset table 205 " octal 315 ")
    (aset table 206 " octal 316 ")
    (aset table 207 " octal 317 ")
    (aset table 208 " octal 320 ")
    (aset table 209 " octal 321 ")
    (aset table 210 " octal 322 ")
    (aset table 211 " octal 323 ")
    (aset table 212 " octal 324 ")
    (aset table 213 " octal 325 ")
    (aset table 214 " octal 326 ")
    (aset table 215 " octal 327 ")
    (aset table 216 " octal 330 ")
    (aset table 217 " octal 331 ")
    (aset table 218 " octal 332 ")
    (aset table 219 " octal 333 ")
    (aset table 220 " octal 334 ")
    (aset table 221 " octal 335 ")
    (aset table 222 " octal 336 ")
    (aset table 223 " octal 337 ")
    (aset table 224 " octal 340 ")
    (aset table 225 " octal 341 ")
    (aset table 226 " octal 342 ")
    (aset table 227 " octal 343 ")
    (aset table 228 " octal 344 ")
    (aset table 229 " octal 345 ")
    (aset table 230 " octal 346 ")
    (aset table 231 " octal 347 ")
    (aset table 232 " octal 350 ")
    (aset table 233 " octal 351 ")
    (aset table 234 " octal 352 ")
    (aset table 235 " octal 353 ")
    (aset table 236 " octal 354 ")
    (aset table 237 " octal 355 ")
    (aset table 238 " octal 356 ")
    (aset table 239 " octal 357 ")
    (aset table 240 " octal 360 ")
    (aset table 241 " octal 361 ")
    (aset table 242 " octal 362 ")
    (aset table 243 " octal 363 ")
    (aset table 244 " octal 364 ")
    (aset table 245 " octal 365 ")
    (aset table 246 " octal 366 ")
    (aset table 247 " octal 367 ")
    (aset table 248 " octal 370 ")
    (aset table 249 " octal 371 ")
    (aset table 250 " octal 372 ")
    (aset table 251 " octal 373 ")
    (aset table 252 " octal 374 ")
    (aset table 253 " octal 375 ")
    (aset table 254 " octal 376 ")
    (aset table 255 " octal 377 ")))

(tts-speak-setup-character-table)

(defun tts-char-to-speech (char)
  "Translate CHAR to speech string."
  
  (if (eq (char-charset char) 'ascii)
      (aref tts-character-to-speech-table char)
    (or (tts-unicode-short-name-for-char char)
        (format "octal %o" char))))

;;;   interactively selecting the server:

;; These functions will be reset on a per TTS engine basis
;; via `voice-setup' called by `tts-initialize'.
(defalias 'tts-get-voice-command (lambda (&rest _) ""))
(defalias 'tts-define-voice-from-acss #'ignore)
(defalias 'tts-voice-defined-p (lambda (&rest _) t))

(require 'tts-voice-api)

(defun tts--voice-preview-callback (callback result)
  "Call voice preview CALLBACK safely with RESULT and return RESULT."
  (when (functionp callback)
    (condition-case error-data
        (funcall callback result)
      (error
       (message "Voice preview callback failed: %s"
                (error-message-string error-data)))))
  result)

(defun tts--voice-preview-selector-kind (selector)
  "Return normalized kind symbol from voice preview SELECTOR."
  (let ((kind (plist-get selector :kind)))
    (if (stringp kind) (intern kind) kind)))

(defun tts--voice-preview-available-p (value)
  "Return non-nil when inventory availability VALUE is usable."
  (or (null value) (equal (format "%s" value) "available")))

(defun tts--voice-preview-engine (engine-id inventory)
  "Return usable ENGINE-ID from INVENTORY, or signal a preview error."
  (let ((engine
         (cl-find engine-id (plist-get inventory :engines)
                  :key (lambda (entry) (plist-get entry :engine-id))
                  :test #'equal)))
    (unless engine
      (error "Preview engine %s is not installed" engine-id))
    (unless (and
             (tts--voice-preview-available-p
              (plist-get engine :availability))
             (not (equal (format "%s" (plist-get engine :health)) "failed")))
      (error "Preview engine %s is unavailable" engine-id))
    engine))

(defun tts--voice-preview-property-equal-p (wanted actual)
  "Return non-nil when optional voice property WANTED matches ACTUAL."
  (or
   (null wanted)
   (and actual
        (string-equal (downcase (format "%s" wanted))
                      (downcase (format "%s" actual))))))

(defun tts--inventory-exact-voice (engine voice-id)
  "Find VOICE-ID in ENGINE, resolving bundled eSpeak variants on demand."
  (or (cl-find voice-id (plist-get engine :voices)
               :key (lambda (voice) (plist-get voice :voice-id)) :test #'equal)
      (when (and (equal (plist-get engine :engine-id) "espeak")
                 (stringp voice-id)
                 (string-match
                  "\\`\\(espeak:[A-Za-z0-9_-]+\\(?:[/\\\\][A-Za-z0-9_-]+\\)*\\)[+]\\([A-Za-z_-][A-Za-z0-9_-]*\\)\\'"
                  voice-id)
                 (<= (- (string-bytes voice-id) 7) 39))
        (let* ((base-id (match-string 1 voice-id))
               (variant-id (match-string 2 voice-id))
               (base (cl-find base-id (plist-get engine :voices)
                              :key (lambda (voice) (plist-get voice :voice-id)) :test #'equal))
               (variant (cl-find variant-id (plist-get engine :espeak-variants)
                                 :key (lambda (entry) (plist-get entry :id)) :test #'equal)))
          (when (and base variant)
            (let ((voice (copy-tree base)))
              (setq voice (plist-put voice :voice-id voice-id)
                    voice (plist-put voice :gender nil))
              (plist-put voice :display-name
                         (format "%s + %s" (plist-get base :display-name)
                                 (plist-get variant :display-name)))))))))

(defun tts--resolve-voice-preview-selector (selector &optional inventory)
  "Resolve normalized preview SELECTOR against INVENTORY.
Return a plist with separate `:engine-id' and `:voice-id' fields."
  (unless (listp selector)
    (signal 'wrong-type-argument (list 'listp selector)))
  (let* ((inventory (or inventory (tts-voice-inventory)))
         (kind (tts--voice-preview-selector-kind selector))
         (engine-id (plist-get selector :engine-id)))
    (pcase kind
      ('exact
       (let* ((voice-id (plist-get selector :voice-id))
              (engine (tts--voice-preview-engine engine-id inventory))
              (voice (tts--inventory-exact-voice engine voice-id)))
         (unless (and voice
                      (tts--voice-preview-available-p
                       (plist-get voice :availability)))
           (error "Preview voice %s/%s is unavailable" engine-id voice-id))
         (list :engine-id engine-id :voice-id voice-id :voice voice)))
      ('engine-default
       (let* ((engine (tts--voice-preview-engine engine-id inventory))
              (voices (plist-get engine :voices))
              (voice-id (or (plist-get engine :default-voice-id)
                            (plist-get (car voices) :voice-id))))
         (unless voice-id
           (error "Preview engine %s has no voices" engine-id))
         (tts--resolve-voice-preview-selector
          (list :kind 'exact :engine-id engine-id :voice-id voice-id)
          inventory)))
      ('properties
       (let ((engines
              (if engine-id
                  (list (tts--voice-preview-engine engine-id inventory))
                (plist-get inventory :engines)))
             found)
         (while (and engines (null found))
           (let ((engine (pop engines)))
             (when (and
                    (tts--voice-preview-available-p
                     (plist-get engine :availability))
                    (not (equal (format "%s" (plist-get engine :health))
                                "failed")))
               (dolist (voice (plist-get engine :voices))
                 (when (and
                        (null found)
                        (tts--voice-preview-available-p
                         (plist-get voice :availability))
                        (tts--voice-preview-property-equal-p
                         (plist-get selector :language)
                         (plist-get voice :language))
                        (tts--voice-preview-property-equal-p
                         (plist-get selector :gender)
                         (plist-get voice :gender)))
                   (setq found
                         (list
                          :engine-id (plist-get engine :engine-id)
                          :voice-id (plist-get voice :voice-id)
                          :voice voice)))))))
         (or found (error "No installed voice matches the preview selector"))))
      (_ (error "Invalid voice preview selector: %S" selector)))))

(defun tts-default-voice-preview-code (selector)
  "Return queued native voice code for standalone preview SELECTOR."
  (let* ((resolved (tts--resolve-voice-preview-selector selector))
         (voice-id (plist-get resolved :voice-id))
         (family (and (stringp voice-id) (intern-soft voice-id))))
    (unless (and family (tts-voice-defined-p family))
      (error "The active adapter cannot preview native voice %s" voice-id))
    (tts-get-voice-command family)))

(defvar tts-voice-preview-code-function #'tts-default-voice-preview-code
  "Function returning queued native code for one preview selector.")

(defun tts--voice-preview-dimensions (values)
  "Return the non-nil dimension keys in preview plist VALUES."
  (let (dimensions)
    (while values
      (let ((key (pop values)) (value (pop values)))
        (when value (push key dimensions))))
    (nreverse dimensions)))

(defun tts-default-voice-preview-sequence (entries callback)
  "Queue standalone preview ENTRIES once and call CALLBACK.
Legacy servers cannot acknowledge playback, so the result truthfully reports
`queued' after one dispatch. Each entry restores the configured default voice
before the following entry or subsequent ordinary speech."
  (when (cl-some (lambda (entry) (plist-member entry :selectors)) entries)
    (user-error "This adapter cannot preview complete voice chains; use an individual audition"))
  (let ((prepared
         (mapcar
          (lambda (entry)
            (let* ((selector (plist-get entry :selector))
                   (realized (tts--resolve-voice-preview-selector selector))
                   (code (funcall tts-voice-preview-code-function selector)))
              (list
               :entry entry :code code :realized realized
               :result
               (list
                :status 'queued
                :completion-guarantee 'queued-only
                :requested (copy-tree selector)
                :realized
                (list :engine-id (plist-get realized :engine-id)
                      :voice-id (plist-get realized :voice-id))
                :degraded-acss
                (append
                 (tts--voice-preview-dimensions (plist-get entry :acss))
                 (and
                  (numberp (plist-get entry :rate-offset))
                  (not (zerop (plist-get entry :rate-offset)))
                  '(rate-offset)))
                :degraded-effects
                (tts--voice-preview-dimensions (plist-get entry :effects))))))
          entries)))
    (tts-stop)
    (dolist (item prepared)
      (tts--protocol-queue-code (plist-get item :code))
      (tts--protocol-queue-text
       (or (plist-get (plist-get item :entry) :text) ""))
      (tts--protocol-queue-code (tts-voice-reset-code)))
    (tts--protocol-dispatch)
    (tts--voice-preview-callback
     callback
     (list :status 'queued :completion-guarantee 'queued-only
           :results (mapcar (lambda (item) (plist-get item :result))
                            prepared)))))

(defvar tts-voice-preview-function #'tts-default-voice-preview-sequence
  "Function previewing a sequence of normalized voice entries.

The function receives ENTRIES and CALLBACK. Each entry is a plist containing
`:text', `:acss', `:rate-offset', `:effects', and `:language', plus exactly
one of `:selector' for an individual audition or `:selectors' for a complete
voice.  Complete entries require explicit `:fallback-policy' and
`:disabled-engine-ids'; nil selectors mean Automatic.  The fallback policy
contains `:preferred-engines', `:allow-same-language-on-requested-engine',
`:global-default' and `:fallback-engines'.
CALLBACK receives one terminal result. Adapters without playback
acknowledgement use `queued' and `queued-only' rather than claiming natural
completion.")

(defun tts--validate-voice-preview-entry (entry)
  "Validate the common shape of individual or complete preview ENTRY."
  (unless (and (proper-list-p entry) (zerop (% (length entry) 2)))
    (error "Voice preview entry must be a plist"))
  (unless (and (stringp (plist-get entry :text))
               (not (string-empty-p (plist-get entry :text))))
    (error "Each voice preview entry requires nonempty text"))
  (when (eq (not (plist-member entry :selector)) (not (plist-member entry :selectors)))
    (error "Preview requires exactly one of :selector or :selectors")))

(defvar tts--emoji-preview-prepared nil
  "Non-nil while forwarding an already prepared editor preview.")

(defun tts--emoji-preview-wire-entries (entries)
  "Remove Emacs-only naming metadata from private adapter ENTRIES."
  (mapcar (lambda (entry)
            (let ((copy (copy-sequence entry)))
              (dolist (key '(:emoji-policy :emoji-prepared :emoji-naming))
                (cl-remf copy key))
              copy)) entries))

(defun tts--emoji-preview-entries (entries &optional captured-policy)
  "Prepare fresh preview ENTRIES with the remembered source's frozen policy.
CAPTURED-POLICY, when supplied as a one-element list, overrides current policy.
Resolve the source before entering a scratch buffer or asynchronous adapter."
  (let* ((source (if (fboundp 'emacsvox-aural-inspection-source-buffer)
                     (emacsvox-aural-inspection-source-buffer)
                   (current-buffer)))
         (policy (if captured-policy (car captured-policy)
                   (and (buffer-live-p source)
                        (with-current-buffer source (emacsvox-emoji--snapshot)))))
         (pronunciations (and (buffer-live-p source)
                              (buffer-local-value 'emacsvox-pronounce-table source)))
         (personality (and (buffer-live-p source)
                           (buffer-local-value 'emacsvox-pronounce-personality source))))
    (mapcar
     (lambda (entry)
       (let* ((entry (copy-tree entry))
              (policy (if (plist-member entry :emoji-policy) (plist-get entry :emoji-policy) policy))
              (text (plist-get entry :text))
              (retained (and (stringp text)
                             (text-property-any 0 (length text) 'emacsvox-emoji-retained t text))))
         (when retained
           (setq entry (plist-put entry :emoji-prepared t))
           (setq entry (plist-put entry :emoji-naming
                                  (get-text-property retained 'emacsvox-emoji-evidence text))))
         (unless (or (plist-get entry :emoji-prepared)
                     (not (plist-get policy :enabled)))
           (let* ((original (plist-get entry :text))
                  (policy (emacsvox-emoji--item-policy original policy))
                  (text (if pronunciations
                            (with-temp-buffer
                              (let ((emacsvox-pronounce-personality personality))
                                (insert original)
                                (tts-apply-pronunciations pronunciations)
                                (buffer-string)))
                          original))
                  (result (emacsvox-emoji--prepare text policy)))
             (setq entry (plist-put entry :text (plist-get result :text)))
             (setq entry (plist-put entry :emoji-naming
                                    (list :replacements (plist-get result :replacements)
                                          :diagnostics (plist-get result :diagnostics))))))
         (setq entry (plist-put entry :emoji-prepared t))
         entry)) entries)))

(defun tts--replace-pronunciation (replacement)
  "Apply explicit REPLACEMENT and protect its result from emoji naming."
  (let ((start (match-beginning 0)))
    (tts-replace-match replacement)
    (put-text-property start (point) 'emacsvox-emoji-pronounced t)))

(defun tts-preview-voices (entries callback)
  "Preview normalized ENTRIES and call CALLBACK with one terminal result."
  (unless (and (listp entries) entries)
    (error "Voice preview requires at least one entry"))
  (mapc #'tts--validate-voice-preview-entry entries)
  (unless (functionp tts-voice-preview-function)
    (error "The active speech adapter does not support voice preview"))
  (let ((prepared (if tts--emoji-preview-prepared (copy-tree entries)
                    (tts--emoji-preview-entries entries))))
    (funcall tts-voice-preview-function (tts--emoji-preview-wire-entries prepared)
             (lambda (result)
               (cl-loop for item in (plist-get result :results) for entry in prepared do
                        (plist-put item :request-snapshot (copy-tree entry)))
               (when callback (funcall callback result))))))

(cl-defun tts-preview-voice
    (text selector &key acss rate-offset effects language callback)
  "Preview TEXT through SELECTOR without changing saved routing.
ACSS and EFFECTS are unsaved normalized plists. RATE-OFFSET is a signed point
adjustment to the current speech rate. LANGUAGE constrains portable selection.
CALLBACK receives a normalized terminal result plist."
  (unless (and (stringp text) (not (string-empty-p text)))
    (error "Voice preview text must be a nonempty string"))
  (tts-preview-voices
   (list
    (list :text text :selector selector :acss acss
          :rate-offset rate-offset :effects effects :language language))
   (when callback
     (lambda (result)
       (let ((single
              (or (car (plist-get result :results))
                  (list :status (plist-get result :status)
                        :completion-guarantee
                        (plist-get result :completion-guarantee)))))
         (funcall callback
                  (append single
                          (list :sequence-status (plist-get result :status)))))))))

(defun tts--voice-family-name (value)
  "Return a comparison name for voice-family VALUE."
  (cond
   ((symbolp value) (symbol-name value))
   ((stringp value) value)
   (t nil)))

(defun tts--voice-family-name-equal-p (left right)
  "Return non-nil when voice-family names LEFT and RIGHT are equal."
  (let ((left-name (tts--voice-family-name left))
        (right-name (tts--voice-family-name right)))
    (and
     left-name right-name
     (string-equal
      (downcase left-name)
      (downcase right-name)))))

(defun tts-voice-family-capability (family &optional capabilities)
  "Return the family entry matching FAMILY in CAPABILITIES.

Exact identifiers and aliases win.  Generic family names such as `female'
then select the first entry advertising that generic characteristic."
  (let* ((capabilities (or capabilities (tts-voice-capabilities)))
         (families (plist-get capabilities :families))
         exact)
    (dolist (entry families)
      (when
          (or
           (tts--voice-family-name-equal-p family (car entry))
           (cl-some
            (lambda (alias)
              (tts--voice-family-name-equal-p family alias))
            (plist-get (cdr entry) :aliases)))
        (setq exact entry)))
    (or
     exact
     (cl-find-if
      (lambda (entry)
        (cl-some
         (lambda (generic)
           (tts--voice-family-name-equal-p family generic))
         (plist-get (cdr entry) :generic)))
      families))))

(defun tts-voice-family-id (family &optional capabilities)
  "Return the canonical adapter family identifier matching FAMILY."
  (car-safe (tts-voice-family-capability family capabilities)))

(defun tts-voice-parameter-capability (dimension &optional capabilities)
  "Return the parameter descriptor for ACSS DIMENSION."
  (assq
   dimension
   (plist-get
    (or capabilities (tts-voice-capabilities))
    :parameters)))

(defun tts-voice-reset-code ()
  "Return voice reset code."
  (tts-get-voice-command tts-default-voice))

(defvar tts-device "default"
  "Name of  sound device.")

(defcustom tts-cloud-server "cloud-outloud"
  "Set this to your preferred cloud TTS server."
  :type '(string
          (choice
           (:const "cloud-outloud" :tag "Outloud Variants")
           (:const "cloud-dtk" :tag "DTK Variants")
           (:const "cloud-espeak" :tag "ESpeak Variants")
           (:const "cloud-mac" :tag "Mac Variants")))
  :group 'dtk)

(defun tts-select-server (program )
  "Select  speech server `program'. "
  (interactive
   (list
    (completing-read
     "Speech server:"
     (or tts-servers-alist (tts-setup-servers-alist))
     nil t)))
  (setq tts-program program)
  (ems--fastload "voice-setup")
  (tts-initialize))

(defvar tts-multi-engines
  '("espeak" "omnivox" "outloud" "dtk-soft" "sharpwin" "swiftmac")
  "List of TTS engines that are multi capable.")

(defsubst tts-multistream-p (engine)
  "Checks if this tts-engine can support multiple streams."
  
  (and
   (not (string= tts-notification-device "default"))
   (or
    (tts--omnivox-program-p engine)
    (cl-find-if #'(lambda (e) (string-match e engine)) tts-multi-engines))))

(defun tts-cloud ()
  "Select  Cloud TTS server."
  (interactive)
  
  (tts-select-server tts-cloud-server)
  (setq emacsvox-play-program nil)
  (tts-initialize)
  (when (tts-multistream-p tts-cloud-server)
    (tts-notify-initialize)))

(defvar tts-local-server-process nil
  "Local server process.")

(defvar tts-speech-server-program "speech-server"
  "Local speech server script.")
(defvar tts-local-server-port "2222"
  "Port where we run our local server.")

(defcustom tts-local-engine "outloud"
  "Engine we use  for our local TTS  server."
  :type '(choice
          (const :tag "Dectalk Express" "dtk-exp")
          (const :tag "Viavoice Outloud" "outloud"))
  :group 'dtk)

(defun tts-local-server (program &optional prompt-port)
  "Select and start an local speech server interactively. Local server
lets Emacsvox on a remote host connect back via SSH port forwarding
for instance. Argument PROGRAM specifies the speech server
program. Port defaults to tts-local-server-port"
  (interactive
   (list
    (completing-read
     "Select speech server:"
     (or tts-servers-alist
         (tts-setup-servers-alist))
     nil
     t
     nil nil
     tts-program)
    current-prefix-arg))
  (setq
   tts-local-server-process
   (start-process
    "LocalTTS"
    "localTTS*"
    (expand-file-name tts-speech-server-program emacsvox-servers-directory)
    (if prompt-port
        (read-from-minibuffer "Port:" "3333")
      tts-local-server-port)
    (expand-file-name program emacsvox-servers-directory))))

;;;   initialize the speech process
(defconst tts-pamixer (executable-find "pamixer") "pamixer")

(defgroup tts-output nil
  "Output routing and independent Omnivox audio levels.
Volumes are percentages of the normal output level.  Changes made with
Customize affect subsequent audio; audio already prepared keeps its level.
Notification volumes require a separate notification process.  When using
main output, notifications follow the main process settings instead.
Earcon levels apply to sounds played by Omnivox, not external sound players."
  :tag "Audio output"
  :group 'tts)

(defconst tts--output-volume-settings
  '((tts-main-tone-volume speaker "tts_set_tone_volume")
    (tts-main-earcon-volume speaker "tts_set_sound_volume")
    (tts-notification-speech-volume notification "tts_set_voice_volume")
    (tts-notification-tone-volume notification "tts_set_tone_volume")
    (tts-notification-earcon-volume notification "tts_set_sound_volume"))
  "Output volume options, process roles and existing Omnivox commands.")

(defun tts--validate-output-volume (value)
  "Reject VALUE unless it is an integer percentage from zero to 100."
  (unless (and (integerp value) (<= 0 value 100))
    (user-error "Output volume must be an integer from 0 to 100")))

(defun tts--send-output-volume (process setting value)
  "Send SETTING's percentage VALUE to PROCESS without interrupting audio."
  (tts--validate-output-volume value)
  (tts-queue--send-typed
   process (format "%s %.2f\n" (nth 2 setting) (/ value 100.0)) 'neutral))

(defun tts--set-output-volume (symbol value)
  "Set output option SYMBOL to VALUE and update its live Omnivox process."
  (tts--validate-output-volume value)
  (set-default symbol value)
  (when (tts--omnivox-program-p)
    (let ((setting (assq symbol tts--output-volume-settings)))
      (dolist (process
               (delete-dups (list (bound-and-true-p tts-speaker-process)
                                  (bound-and-true-p tts-notify-process))))
        ;; Roles also protect against a dynamically rebound speaker variable
        ;; while notification feedback is being delivered.
        (when (and (processp process) (process-live-p process)
                   (eq (process-get process tts--speech-process-role-property)
                       (nth 1 setting)))
          (tts--send-output-volume process setting value))))))

(defcustom tts-main-tone-volume 100
  "Main-stream tone volume as a percentage from 0 to 100.
Zero silences tones.  Customize applies changes to subsequent Omnivox audio."
  :type 'integer :set #'tts--set-output-volume :group 'tts-output)

(defcustom tts-main-earcon-volume 100
  "Main-stream earcon volume as a percentage from 0 to 100.
Zero silences earcons played by Omnivox.  External sound players are unaffected.
Customize applies changes to subsequent audio."
  :type 'integer :set #'tts--set-output-volume :group 'tts-output)

(defcustom tts-notification-speech-volume 100
  "Notification speech volume as a percentage from 0 to 100.
Zero silences speech on the separate Omnivox notification process.
Customize applies changes to subsequent audio.  Main output uses main settings."
  :type 'integer :set #'tts--set-output-volume :group 'tts-output)

(defcustom tts-notification-tone-volume 100
  "Notification tone volume as a percentage from 0 to 100.
Zero silences tones on the separate Omnivox notification process.
Customize applies changes to subsequent audio.  Main output uses main settings."
  :type 'integer :set #'tts--set-output-volume :group 'tts-output)

(defcustom tts-notification-earcon-volume 100
  "Notification earcon volume as a percentage from 0 to 100.
Zero silences earcons played by the separate Omnivox notification process.
Customize applies changes to subsequent audio.  Main output uses main settings.
External sound players are unaffected."
  :type 'integer :set #'tts--set-output-volume :group 'tts-output)

(defun tts--initialize-output-volumes (process)
  "Restore saved output levels on a newly created Omnivox PROCESS."
  (when (tts--omnivox-program-p)
    (dolist (setting tts--output-volume-settings)
      (when (eq (process-get process tts--speech-process-role-property)
                (nth 1 setting))
        (tts--send-output-volume
         process setting (default-value (car setting)))))))

(defcustom tts-notification-device
  nil
  "Virtual sound device to use for notifications stream.
For Omnivox, nil starts a second process routed to both channels; `left',
`right', or `both' selects its process-wide route.  Set this to `default' or
the empty string to disable that separate process and fall back to main speech.
For other servers, nil disables a separate notification stream.  If you name a
device, make sure it exists first.  For SwiftMac, use `left' or `right'."
  :type '(choice
          (const :tag "Automatic" nil)
          (const :tag "Left" "left")
          (const :tag "Right" "right")
          (const :tag "Both channels" "both")
          (const :tag "Use main output (notifications remain audible)" "default")
          (string :tag "Other device" :value ""))
  :group 'tts
  :group 'tts-output)

;; Helper: tts-make-process:
(defvar omnivox-library--birth-collector)
(defvar omnivox--library-startup)
(defvar omnivox--engine-startup nil)
(declare-function omnivox-library--owner "omnivox-library-runtime" (process))
(declare-function omnivox-library--prepare-engines "omnivox-library-runtime" ())
(declare-function omnivox-library--engine-reference "omnivox-library-runtime" (process))
(declare-function omnivox-library--current-engine-reference "omnivox-library-runtime" ())
(declare-function omnivox-library--remember-engines "omnivox-library-runtime" (process))
(declare-function omnivox-library--acknowledge-engines "omnivox-library-runtime" (process startup))
(declare-function omnivox-library--command "omnivox-library-runtime" (program))
(declare-function omnivox-library--startup-environment "omnivox-library-runtime" (environment))
(defun tts--resolve-program (program)
  "Return the executable used for speech-server PROGRAM, or nil.

Absolute paths are used as supplied.  Native Windows prefers an executable
found on `exec-path', because the bundled launchers are POSIX scripts.  Other
platforms prefer a bundled launcher and fall back to `exec-path'."
  (let ((bundled (expand-file-name program emacsvox-servers-directory)))
    (cond
     ((file-name-absolute-p program) (expand-file-name program))
     ((eq system-type 'windows-nt)
      (executable-find program))
     ((file-executable-p bundled) bundled)
     ((executable-find program)))))

(defun tts--diagnostic-buffer (name &optional create)
  "Return the local speech diagnostic buffer for process NAME.
When CREATE is non-nil, create it if needed and apply
`tts-hide-diagnostic-buffers', preserving any existing contents."
  (let* ((visible (format "*%s diagnostics*" name))
         (hidden (concat " " visible))
         (preferred (if tts-hide-diagnostic-buffers hidden visible))
         (buffer (or (get-buffer preferred)
                     (get-buffer (if tts-hide-diagnostic-buffers visible hidden)))))
    (when create
      (if buffer
          (with-current-buffer buffer
            (unless (equal (buffer-name) preferred)
              (rename-buffer preferred)))
        (setq buffer (get-buffer-create preferred))))
    buffer))

(defun tts-show-diagnostics (name)
  "Show retained local speech-server diagnostics for NAME.
Choose Speaker for main speech or Notify for notifications.
Signal a user error if no diagnostic buffer is available."
  (interactive
   (list (completing-read "Speech diagnostics: " '("Speaker" "Notify")
                          nil t nil nil "Speaker")))
  (unless (member name '("Speaker" "Notify"))
    (user-error "Choose Speaker or Notify diagnostics"))
  (let ((buffer (tts--diagnostic-buffer name)))
    (unless buffer
      (user-error "No local %s diagnostics are available" name))
    (pop-to-buffer buffer)))

(defun tts-make-process (name)
  "Make a  TTS process called name."
  
  (let ((process-connection-type nil)
        (default-directory (expand-file-name "~/"))
        (program (unless (omnivox-remote-enabled-p)
                   (tts--resolve-program tts-program)))
        (process nil))
    (unless (or program (omnivox-remote-enabled-p))
      (error "Could not find speech server executable `%s'" tts-program))
    (setq process
          (if (omnivox-remote-enabled-p)
              (omnivox-remote-make-process name)
            (tts-queue--create
             (lambda ()
               (require 'omnivox-engine-settings)
               (require 'omnivox-library-runtime)
               (let ((process-environment (omnivox-engine-settings--environment program)))
                 (setq process-environment
                       (omnivox-library--startup-environment process-environment))
                 (make-process
                  :name name :command (omnivox-library--command program) :connection-type 'pipe
                  :coding 'utf-8-unix
                  :stderr (tts--diagnostic-buffer name t)))) nil)))
    (when (and (boundp 'omnivox-library--birth-collector) omnivox-library--birth-collector)
      (funcall omnivox-library--birth-collector process))
    (unless (process-live-p process) (error "Fail: Speech Server"))
    (set-process-coding-system process 'utf-8-unix 'utf-8-unix)
    (process-put
     process tts--speech-process-generation-property
     (cl-incf tts--speech-process-generation))
    (tts-queue--set-generation process tts--speech-process-generation)
    (process-put
     process tts--speech-process-role-property
     (if (string= name "Notify") 'notification 'speaker))
    (set-process-sentinel
     process (if (process-get process 'omnivox-remote-managed)
                 #'omnivox-remote--sentinel
               #'tts--speech-process-sentinel))
    (let (configured)
      (unwind-protect
          (progn
            (when (member "--voice-library-owner" (process-command process))
              (require 'omnivox-voices)
              (let ((owner (omnivox-library--owner process)))
                (when (or (stringp (plist-get owner :startup_error))
                          (process-get process 'omnivox-library-retired))
                  (error "Native speech startup failed; see the speech diagnostics")))
              (omnivox-library--acknowledge-engines
               process (or omnivox--library-startup omnivox--engine-startup)))
            (when (process-get process 'omnivox-remote-managed)
              (omnivox-remote--acknowledge-engines process))
            (tts--initialize-output-volumes process)
            (setq configured t))
        (unless (or configured
                    (and (boundp 'omnivox-library--birth-collector) omnivox-library--birth-collector))
          (tts--retire-process process))))
    process))

(declare-function voice-setup "voice-setup" ())
(defvar tts--initializing nil
  "Non-nil while full speech startup will configure both processes together.")

(defun tts-initialize ()
  "Initialize speech system."
  
  ;; fallback of fallbacks
  (unless tts-program (setq tts-program "espeak"))
  (when (omnivox-remote-enabled-p) (omnivox-remote--begin-activation))
  (require 'omnivox-library-runtime)
  (let* ((tts--initializing t)
         (omnivox--engine-startup (omnivox-library--prepare-engines))
         (new (tts-make-process "Speaker"))
         (old-speaker tts-speaker-process) quit-data)
    ;; Retire the old server only after its replacement starts successfully.
    ;; If retirement is quit, the unpublished replacement still needs an owner
    ;; responsible for deleting it.
    (unwind-protect
        (progn
          (when (processp old-speaker)
            (tts--retire-process old-speaker))
          (setq tts-speaker-process new)
          (omnivox-library--remember-engines new))
      (unless (eq tts-speaker-process new)
        (tts--retire-process new)))
    (cond
     ((tts-multistream-p tts-program)
      (condition-case error-data
          (tts-notify-initialize)
        ((error quit)
         (when (eq (car error-data) 'quit) (setq quit-data error-data))
         ;; An old notifier belongs to a different deliberate activation.
         ;; Keep main speech available, without publishing a mixed pair.
         (when omnivox--engine-startup
           (let ((stale tts-notify-process))
             (setq tts-notify-process nil)
             (when (and (processp stale) (not (eq stale new)))
               (tts--retire-process stale))))
         (when (and (omnivox-remote-enabled-p)
                    (tts--notification-process-configured-p)
                    (not (process-live-p tts-notify-process)))
           (setq omnivox-remote--last-error (error-message-string error-data))
           (omnivox-remote--schedule-retry))
         (message
          "Notification speech server unavailable; using available speech: %s"
          (error-message-string error-data)))))
     (t
      ;; Do not leave a notifier from the previously selected engine alive.
      (let ((old-notifier tts-notify-process))
        (setq tts-notify-process nil)
        (when (and (processp old-notifier)
                   (not (eq old-notifier old-speaker))
                   (not (eq old-notifier new)))
          (tts--retire-process old-notifier)))))
    (when (string-match "cloud" tts-program) ; we'll serve icons.
      (setq emacsvox-play-program nil))
    ;; `voice-setup' requires us, so we can't require it at top-level.
    (require 'voice-setup)
    (voice-setup)
    (when quit-data (signal (car quit-data) (cdr quit-data)))))

(defun tts--recover-speaker ()
  "Recover main speech from its retained activation without restarting its peer."
  (require 'omnivox-library-runtime)
  (if (omnivox-remote-enabled-p)
      (omnivox-remote--retry)
    (let ((omnivox--engine-startup
           (or (omnivox-library--engine-reference tts-speaker-process)
               (omnivox-library--engine-reference tts-notify-process)
               (omnivox-library--current-engine-reference))))
      (if (not omnivox--engine-startup)
          (tts-initialize)
        (let ((new (tts-make-process "Speaker")) (old tts-speaker-process))
          (unwind-protect
              (progn
                (when (processp old) (tts--retire-process old))
                (setq tts-speaker-process new)
                (omnivox-library--remember-engines new))
            (unless (eq tts-speaker-process new) (tts--retire-process new))))
        (require 'voice-setup)
        (voice-setup)))))

(defun tts-restart ()
  "Restart TTS server."
  (interactive)
  
  (tts-initialize)
  (when (process-live-p tts-speaker-process)
    (tts--protocol-sync)))

;;;   interactively select how text is split:

(defun tts-toggle-splitting-on-white-space ()
  "Toggle splitting of speech on white space. "
  (interactive)
  
  (cond
   ((not (string-match "-" tts-chunk-separator-syntax))
    (tts-chunk-on-white-space-and-punctuations)
    (when (called-interactively-p 'interactive)
      (message "Text will be split at punctuations and white space")))
   (t (tts-chunk-only-on-punctuations)
      (when (called-interactively-p 'interactive)
        (message "Text split  at clause boundaries")))))

(defun tts-set-chunk-separator-syntax (s)
  "Interactively set how text is split in chunks.
Argument S specifies the syntax class."
  (interactive
   (list
    (read-from-minibuffer "Specify separator syntax string: ")))
  
  (setq tts-chunk-separator-syntax s)
  (when (called-interactively-p 'interactive)
    (message "Set  separator to %s" s)))

;;;  speak text

(defvar-local tts-yank-excluded-properties
  '(category field follow-link fontified font-lock-face help-echo
             keymap local-map mouse-face read-only yank-handler)
  "Like yank-excluded-properties, but without  invisible
 and intangible in it.
This is so text marked invisible is silenced.")

(declare-function
 org-fold-core-set-folding-spec-property
 "org-fold-core" (spec property value &optional force))
(declare-function
 org-fold-core-set-folding-spec-property
 "org-fold-core" (spec property value &optional force))

(declare-function org-fold-initialize "org-fold" (ellipsis))
(declare-function org-set-regexps-and-options "org" (&optional tags-only))

(defun tts-org-fold ()
  "Prepare Org fold."
  (when
      (and
       (boundp 'org-fold-core-style) (eq org-fold-core-style 'text-properties))
    (outline-mode)
    (org-fold-initialize "...")
    (org-fold-core-set-folding-spec-property
     'org-fold-hidden
     :visible (not org-link-descriptive))))

(defun tts-speak (text)
  "Speak the TEXT string
unless   `tts-quiet' is set to t. "
  (let* ((context
          (or
           emacsvox-aural-submission-context
           (emacsvox-aural-capture-context)))
         (occasion
          (or
           emacsvox-aural-submission-occasion
           (plist-get context :occasion)
           'continuous)))
    (emacsvox-aural-call-with-submission
     #'tts--speak
     :context context
     :occasion occasion
     :arguments (list text))))

(defvar tts--tracked-completion-function nil
  "Completion callback for the dynamically current speech submission.")

(defvar tts--marker-event-function nil
  "Marker callback for the dynamically current speech submission.")

(defvar tts--scratch-buffers-in-use nil
  "Dynamically active TTS preparation buffers.

Nested speech uses this stack to avoid erasing an enclosing preparation.")

(defun tts-speak-tracked (text callback)
  "Speak TEXT and call CALLBACK after server playback completes.
CALLBACK receives the tracked dispatch identifier and terminal status.  A
`completed' status means the supporting server reports empty synthesis and
audio queues; it does not prove that a physical audio device was heard."
  (tts--require-tracked-playback-completion)
  (let* ((tts--tracked-completion-function callback)
         (identifier (tts-speak text)))
    (unless (integerp identifier)
      (error "Tracked speech was not submitted"))
    identifier))

(defun tts-speak-marked (text marker-callback completion-callback)
  "Speak TEXT with playback marker and terminal callbacks.
MARKER-CALLBACK receives a dispatch identifier and decoded event plist.
COMPLETION-CALLBACK receives the identifier and `completed', `cancelled', or
`failed'.  Events follow mixer source consumption and may lead acoustic output
by the audio device's buffering latency."
  (unless (functionp marker-callback)
    (signal 'wrong-type-argument (list 'functionp marker-callback)))
  (unless (functionp completion-callback)
    (signal 'wrong-type-argument (list 'functionp completion-callback)))
  (tts--require-marker-playback-events)
  (tts--require-tracked-playback-completion)
  (let* ((tts--marker-event-function marker-callback)
         (tts--tracked-completion-function completion-callback)
         (identifier (tts-speak text)))
    (unless (integerp identifier)
      (error "Marker-aware speech was not submitted"))
    identifier))

(defun tts--speak (text)
  "Implement `tts-speak' for TEXT with source context already captured."
  ;; ensure text is a  string
  (unless (stringp text) (when text (setq text (format "%s" text))))
  ;; ensure  the process  is live
  (unless (process-live-p tts-speaker-process) (tts--recover-speaker))
  ;; If you dont want me to talk,or my server is not running,
  ;; I will remain silent.
  ;; I also do nothing if text is nil or ""
  (unless
      (or tts-quiet (not (process-live-p tts-speaker-process))
          (null text) (zerop (length text)))
    (emacsvox-aural-call-with-delivery-transaction
     tts-speaker-process #'tts--speak-transaction text)))

(defun tts--speak-transaction (text)
  "Prepare and queue one complete speech transaction for TEXT."
  (unless (emacsvox-aural-prepared-text-p text)
    (setq
     text
     (emacsvox-aural-prepare-text
      text emacsvox-aural-submission-facts
      emacsvox-aural-submission-context)))
  ;; flush previous speech if asked to
  (when
      (and
       tts-stop-immediately
       (not emacsvox-aural-submission-controls-interruption))
    (if tts--current-preparation
        (setf (tts--preparation-legacy-stop tts--current-preparation) t)
      (tts-stop)))
  (when selective-display
    (let ((ctrl-m (string-match "\015" text)))
      (and ctrl-m (setq text (substring text 0 ctrl-m))
           (emacsvox-icon 'ellipses))))
  (let (                                ;snapshot relevant state
        (orig-mode major-mode)
        (char-alias  char-property-alias-alist)
        (links-desc (and (eq major-mode 'org-mode) org-link-descriptive  ))
        (inhibit-read-only t)
        (inhibit-modification-hooks t)
        (invisibility-spec buffer-invisibility-spec)
        (syntax-table (syntax-table))
        (pron-table emacsvox-pronounce-table)
        (pron-personality emacsvox-pronounce-personality)
        (chunk-sep tts-chunk-separator-syntax)
        (inherit-speak-nonprinting-chars tts-speak-nonprinting-chars)
        (inherit-strip-octals tts-strip-octals)
        (complement-sep (tts-complement-chunk-separator-syntax))
        (speech-rate tts-speech-rate)
        (caps tts-caps)
        (split-caps tts-split-caps)
        (capitalization-presentation emacsvox-capitalization-presentation)
        (start 1)
        (end nil)
        (mode tts-punctuation-mode)
        (voice-lock voice-lock-mode)) ; done snapshotting
    (let* ((nested-scratch-p (consp tts--scratch-buffers-in-use))
           (tts-scratch-buffer
            (if nested-scratch-p
                (generate-new-buffer " *tts-scratch-buffer* ")
              (get-buffer-create " *tts-scratch-buffer* ")))
           (tts--scratch-buffers-in-use
            (cons tts-scratch-buffer tts--scratch-buffers-in-use)))
      (unwind-protect
          (progn
            (with-current-buffer tts-scratch-buffer
              (setq buffer-undo-list  t)
              (erase-buffer)
              (when (eq orig-mode 'org-mode)
                (setq org-link-descriptive links-desc)
                (tts-org-fold))
              ;; inherit environment
              (setq                           ; mirror snapshot
               yank-excluded-properties tts-yank-excluded-properties
               char-property-alias-alist  char-alias
               emacsvox-pronounce-table pron-table
               emacsvox-pronounce-personality pron-personality
               buffer-invisibility-spec invisibility-spec
               tts-chunk-separator-syntax chunk-sep
               tts-speech-rate speech-rate
               tts-punctuation-mode mode
               tts-split-caps split-caps
               tts-caps caps
               tts-speak-nonprinting-chars inherit-speak-nonprinting-chars
               tts-strip-octals inherit-strip-octals
               voice-lock-mode voice-lock)
              (setq-local
               emacsvox-capitalization-presentation
               capitalization-presentation)
              (set-syntax-table syntax-table)
              (tts--protocol-sync)
              (insert-for-yank text)          ; insert and pre-process text
              (tts--delete-invisible-text)
              (tts-handle-repeating-patterns mode)
              (when pron-table (tts-apply-pronunciations pron-table))
              (let* ((original (buffer-string))
                     (prepared (emacsvox-aural--prepare-emoji-text original)))
                (unless (eq original prepared)
                  (erase-buffer)
                  (insert prepared)))
              (when tts-handle-unicode (tts-unicode-replace-chars mode))
              (tts-quote mode)
              (goto-char (point-min))         ; text is ready to be spoken
              (skip-syntax-forward "-")       ;skip leading whitespace
              (setq start (point))
              (while (and (not (eobp))
                          (tts-move-across-a-chunk chunk-sep complement-sep))
                (unless ;;;If  embedded punctuations, continue
                    (and (char-after (point))
                         (= ?. (char-syntax (preceding-char)))
                         (not (= 32 (char-syntax (following-char)))))
                  (skip-syntax-forward "-") ;skip  trailing whitespace
                  (setq end (point))
                  (tts-audio-format start end)
                  (setq start end)))     ; end while
              ;; process trailing text
              (unless (= start (point-max))
                (skip-syntax-forward " ")       ;skip leading whitespace
                (unless (eobp) (tts-audio-format (point) (point-max)))))
            (let ((tts--dispatch-origin 'ordinary))
              (cond
               (tts--marker-event-function
                (tts--protocol-dispatch-marked
                 tts--marker-event-function
                 tts--tracked-completion-function))
               (tts--tracked-completion-function
                (tts--protocol-dispatch-tracked
                 tts--tracked-completion-function))
               (t (tts--protocol-dispatch)))))
        (when (and nested-scratch-p (buffer-live-p tts-scratch-buffer))
          (kill-buffer tts-scratch-buffer))))))

(defmacro ems-with-messages-silenced (&rest body)
  "Evaluate body  after temporarily silencing messages."
  (declare (indent 0) (debug t))
  `(progn
     (defvar emacsvox-speak-messages)
     (let ((emacsvox-speak-messages nil)
           (inhibit-message t))
       ,@body)))

(defun tts-speak-list (text &optional group)
  "Speak a  list of strings.
 Optional argument group specifies grouping for intonation.  If
`group' is a list, it should specify split points where clause
boundaries are inserted.  Otherwise it is a number that specifies
grouping"
  
  (unless group (setq group 3))
  (when (numberp group)
    ;; Create split list
    (setq group
          (let ((q (/ (length text) group))
                (r (% (length text) group))
                (splits nil))
            (setq splits (cl-loop for i from 0 to (1- q) collect group))
            (if (zerop r)
                splits
              `(,@splits ,r)))))
  (cl-assert
   (= (length text) (apply #'+ group)) group "Argument mismatch:" text group)
  (let ((contents nil)
        (count 1))
    ;; A callback may assemble a list while ordinary speech owns its scratch
    ;; buffer.  Keep this text private until it enters the speech transaction.
    (with-temp-buffer
      (cl-loop
       for element in text do
       (let
           ((p (and (stringp element)
                    (get-text-property 0 'personality element))))
         (if (stringp element)
             (insert element)
           (insert (format " %s" element)))
         (cond
          ((= count (car group))
           (setq count 1)
           (pop group)
           (if p
               (insert (propertize ", " 'personality p))
             (insert ", ")))
          (t (cl-incf count)
             (insert " ")))))
      (setq contents (buffer-string)))
    (tts-with-punctuations 'some (tts-speak contents))
    t))

(defun tts--palette-letter (letter)
  "Deliver isolated LETTER using the palette's frozen default voice.
Keep character pronunciation, rate and pitch handling in the speech server."
  (let ((emacsvox-aural--isolated-letter t)
        (emacsvox-aural-submission-delivery-policy 'ordered)
        (emacsvox-aural-submission-replacement-key nil))
    (emacsvox-aural-call-with-delivery-transaction
     tts-speaker-process
     (lambda ()
       (let* ((palette (emacsvox-aural-effective-voice-palette))
              (voice (emacsvox-aural-compile-voice-style 'default palette))
              (plan (emacsvox-aural--make-concrete-plan
                     :voice-palette palette
                     :context (or emacsvox-aural-submission-context
                                  (emacsvox-aural-capture-context))
                     :content (emacsvox-aural--make-concrete-content
                               :text letter :speak t
                               :voice-request 'default
                               :voice-command (emacsvox-aural-compiled-voice-command voice)
                               :voice-style (emacsvox-aural-compiled-voice-style voice)))))
         (tts--protocol-sync)
         (emacsvox-aural-queue-concrete-plan plan letter)
         (tts--protocol-dispatch))))))

(defun tts-letter (letter)
  "Speak a LETTER."
  (unless tts-quiet
    (when (process-live-p tts-speaker-process)
      (if (and (stringp letter) (= (length letter) 1)
               (not (string-match-p "[[:space:][:cntrl:]]" letter))
               (not emacsvox-aural--delivery-transaction-active-p)
               (fboundp 'omnivox--choice-tuning-supported-p)
               (omnivox--choice-tuning-supported-p tts-speaker-process)
               (omnivox--process-supports-p tts-speaker-process "palette_letter_v1"))
          (tts--palette-letter letter)
        (tts--protocol-sync-capitalization-presentation)
        (tts--protocol-letter letter)))))
;;;  Notify:

(defun tts-notify-process ()
  "Return  Notification TTS handle or tts-speaker-process. "
  
  (cond
   ((null tts-notify-process) tts-speaker-process)
   ((and (processp tts-notify-process)
         (memq (process-status tts-notify-process) '(open run)))
    tts-notify-process)
   (t tts-speaker-process)))

(defun tts-notify-stop ()
  "Stop  speech on notification stream."
  (interactive)
  (let ((tts-speaker-process (tts-notify-process)))
    (when tts-speaker-process (tts-stop))))

(defun tts-notify-apply (func text)
  " Applies func to text with tts-speaker-process set to notification stream."
  (let ((tts-speaker-process (tts-notify-process)))
    (funcall func text)))
(declare-function emacsvox-log-notification "emacsvox-speak" (text))

(defun tts-notify (text &optional dont-log)
  "Speak text on notification stream.
Notification is logged in the notifications buffer unless `dont-log' is T. "
  
  (let* ((occasion
          (or
           emacsvox-aural-submission-occasion
           (plist-get emacsvox-aural-submission-context :occasion)
           'notification))
         (context
          (copy-tree
           (or
            emacsvox-aural-submission-context
            (emacsvox-aural-capture-context nil occasion))))
         (emacsvox-aural-submission-context
          (plist-put context :occasion occasion))
         (emacsvox-aural-submission-occasion occasion))
    (unless dont-log (emacsvox-log-notification text))
    (setq emacsvox-last-message text)
    (cond
     ((tts-notify-process)              ; we have a live notifier
      (tts-notify-apply #'tts-speak text))
     (t (tts-speak text))))
  text)

(defun tts-notify-icon (icon)
  "Play icon  on notification stream. "
  (let ((emacsvox-aural-submission-context
         (emacsvox-aural-capture-context nil 'notification)))
    (cond
     ((tts-notify-process)              ; we have a live notifier
      (tts-notify-apply #'emacsvox-icon icon)))))

(defun tts--notification-omnivox-audio-target ()
  "Return a validated Omnivox channel target for the notification process."
  (and
   (tts--omnivox-program-p)
   (if (null tts-notification-device)
       "both"
     (and
      (member tts-notification-device '("left" "right" "both"))
      tts-notification-device))))

(defun tts--notification-process-configured-p ()
  "Return non-nil when current settings request a notification process."
  (or
   (string-match-p "cloud" tts-program)
   (and
    (tts--omnivox-program-p)
    (or
     (null tts-notification-device)
     (member tts-notification-device '("left" "right" "both"))))
   (and
    (not (tts--omnivox-program-p))
    (stringp tts-notification-device)
    (not (member tts-notification-device '("" "default"))))))

(defun tts-notify-initialize ()
  "Initialize a separate notification TTS process when configured."
  (interactive)
  
  (require 'omnivox-library-runtime)
  (let ((omnivox--engine-startup
         (or omnivox--engine-startup
             (omnivox-library--engine-reference tts-speaker-process)
             (omnivox-library--engine-reference tts-notify-process)
             (omnivox-library--current-engine-reference)))
        (old tts-notify-process)
        (new nil)
        (tts-program
         (if (string-match "cloud" tts-program) "cloud-notify" tts-program)))
    (when (tts--notification-process-configured-p)
      (with-environment-variables
          (("ALSA_DEFAULT" tts-notification-device)
           ("SWIFTMAC_AUDIO_TARGET" tts-notification-device)
           ("SHARPWIN_AUDIO_TARGET" tts-notification-device)
           ("PULSE_SINK" tts-notification-device)
           ("OMNIVOX_AUDIO_TARGET"
            (tts--notification-omnivox-audio-target)))
        (setq new (tts-make-process "Notify"))
        (unless (process-live-p new)
          (error "Fail: Notification Speech Server"))))
    ;; Publish the replacement before retirement hooks observe global state.
    (setq tts-notify-process new)
    (when (and (processp new) (tts--omnivox-program-p)
               (not tts--initializing))
      ;; Full startup calls `voice-setup' for both lanes.  A notification-only
      ;; reset must restore its own routing and voice state as well.
      (let (configured)
        (unwind-protect
            (progn
              (require 'omnivox-voices)
              (omnivox--negotiate-process new)
              (let ((tts-speaker-process new)) (tts--protocol-sync))
              (unless (string-empty-p omnivox-default-voice-id)
                (tts-queue--send-typed
                 new (format "tts_set_voice %s\n" omnivox-default-voice-id)
                 'neutral))
              (setq configured t))
          (unless configured
            (setq tts-notify-process old)
            (tts--retire-process new)))))
    (when (and (processp old) (not (eq old new)))
      (tts--retire-process old))
    new))

;; Unicode character pronunciation support:
;;;  Header: Lukas

;; Copyright 2007, 2011 Lukas Loehrer
;; TVR: Integrated into Emacsvox July 6, 2008
;; Using patch from Lukas.
;;
;; Author: Lukas Loehrer <loehrerl |at| gmx.net>
;; Version: $Id$
;; Keywords:  TTS, Unicode

;;;  Customizations

(defcustom tts-unicode-character-replacement-alist
  '(
    (? . "-")                       ; START OF GUARDED AREA
    (?━ . "-")                          ; horiz bars
    (?┃ . "|")                          ; vertical block
    (?° . " degrees ")                  ; degree sign
    (?℃ . "Degree C")                   ; celsius
    (?℉ . "Degree F ")                  ; Fahrenheit
    (?“ . "\"")                         ;LEFT DOUBLE QUOTATION MARK
    (?” . "\"")                         ; RIGHT DOUBLE QUOTATION MARK
    (?⋆ . "*")                          ; STAR OPERATOR
    (?­ . "-")                          ; soft-hyphen
    (?‘ . "`")                          ; LEFT SINGLE QUOTATION MARK
    (?’ . "'")                          ; right SINGLE QUOTATION MARK
    (?‐ . " dash ")                          ; hyphenm
    (?– . " dash dash  ")                       ; n-dash
    (?— . " em dash  ")                      ; m-dash
    (?  . " ")                          ; hair space
    (?﻿ . " ")                           ; zero-width  no-break space
    (?‌ . "") ; zero width non-joiner
    (?​ . " ")                           ; zero-width space
    (?  . " ")                          ; thin space
    (?― . "----")                       ; horizontal bar
    (?‖ . "||")                         ; vertical bar
    (?… . "...")                        ; ellipses
    (?• . " bullet ")                   ; bullet
    (? . " ... ")                   ; message-waiting
    (?™ . "TM")                         ; trademark
    (?ﬀ . "ff")                         ; latin small ligature ff
    (?ﬁ . "fi")                         ; latin small ligature fi
    (?ﬂ . "fl")                         ; latin small ligature fl
    (?ﬃ . "ffi")                        ; latin small ligature ffi
    (?ﬄ . "Ffl")                        ; latin small ligature ffl
    )
  "Replacements for  characters."
  :group 'dtk
  :type '(alist
          :key-type (character :tag "character")
          :value-type (string :tag "replacement")))

(defcustom tts-unicode-name-transformation-rules-alist
  '(
    ("BOX DRAWING" . (lambda (_ignored) "."))
    ("^Mathematical Sans-Serif\\( small\\| capital\\)? letter \\(.*\\)$"
     . (lambda (s) (match-string 2 s)))
    ("^greek\\( small\\| capital\\)? letter \\(.*\\)$"
     . (lambda (s) (match-string 2 s)))
    ("^latin\\( small\\| capital\\)? letter \\(.*\\)$"
     . (lambda (s) (match-string 2 s)))
    ("^DEVANAGARI \\(sign\\|vowel sign\\|letter\\)? \\(.*\\)$"
     . (lambda (s) (match-string 2 s)))

    )
  "Alist of character name transformation rules."
  :group 'dtk
  :type
  '(repeat
    (cons :value ("." . identity)
          (regexp :tag "pattern")
          (function :tag "transformation"))))

;;;  Variables

(defcustom tts-unicode-untouched-charsets
  '(ascii latin-iso8859-1)
  "Characters of these charsets are  ignored by
  tts-unicode-replace-chars."
  :group 'dtk
  :type '(repeat symbol))

(defvar tts-unicode-handlers
  '(tts-unicode-user-table-handler tts-unicode-full-table-handler)
  "List of functions which are called in this order for replacing
an unspeakable character.  A handler returns a non-nil value if
the replacement was successful, nil otherwise.")

;;;  Helper functions

(defun tts-unicode-charset-limits (charset)
  "Return rough lower and upper limits for character codes in CHARSET."
  (cond
   ((eq charset 'ascii)
    (list 0 127))
   ((eq charset 'eight-bit-control)
    (list 128 159))
   ((eq charset 'eight-bit-graphic)
    (list 160 255))
   (t
    (let* ((chars (charset-chars charset))
           min max)
      (if (eq chars 96)
          (setq min 32 max 127)
        (setq min 33 max 126))
      (list (make-char charset min min) (make-char charset max max))))))

(defun tts-unicode-build-skip-regexp (charsets)
  "Construct regexp to match all but the characters in
tts-unicode-untouched-charsets."
  (format "[^%s]"
          (cl-loop for charset in charsets
                   when (charsetp charset)
                   concat
                   (apply
                    #'format
                    "%c-%c" (tts-unicode-charset-limits charset)))))

(defvar tts-unicode-charset-filter-regexp
  (tts-unicode-build-skip-regexp tts-unicode-untouched-charsets)
  "Regular exppression that matches characters not in
  tts-unicode-untouched-charsets.")

(defun tts-unicode-update-untouched-charsets (charsets)
  "Update list of charsets we will not touch."
  (setq tts-unicode-untouched-charsets charsets)
  (setq tts-unicode-charset-filter-regexp
        (tts-unicode-build-skip-regexp tts-unicode-untouched-charsets)))
;; Execute BODY like `progn' with CHARSETS at the front of priority list.
;; CHARSETS is a list of charsets.  See
;; `set-charset-priority'.  This affects the implicit sorting of lists of
;; charsets returned by operations such as `find-charset-region'.

(defmacro tts--with-charset-priority (charsets &rest body)
  (declare (indent 1) (debug t))
  (let ((current (make-symbol "current")))
    `(let ((,current (charset-priority-list)))
       (apply #'set-charset-priority ,charsets)
       (unwind-protect
           (progn ,@body)
         (apply #'set-charset-priority ,current)))))
;; Now use it:

(defun tts-unicode-char-in-charsets-p (char charsets)
  "Return t if CHAR is a member of one in the charsets in CHARSETS."
  (tts--with-charset-priority charsets (memq (char-charset char) charsets)))

(defun tts-unicode-char-untouched-p (char)
  "Return t if char is a member of one of the charsets in
tts-unicode-untouched-charsets."
  (tts-unicode-char-in-charsets-p char tts-unicode-untouched-charsets))

(defvar tts-unicode-cache (make-hash-table)
  "Cache for unicode data lookups.")

(defun emacsvox--advice-describe-char-unicode-data-around
    (orig-fun char &rest args)
  "Cache result."
  (let ((result (gethash char tts-unicode-cache 'not-found)))
    (if (eq result 'not-found)
        (let ((ret (apply orig-fun char args)))
          (puthash char ret tts-unicode-cache)
          ret)
      result)))

(advice-add 'describe-char-unicode-data :around
            #'emacsvox--advice-describe-char-unicode-data-around)

(defun tts-unicode-name-for-char (char)
  "Return unicode name for character CHAR. "
  (cond
   ((= char 128) "")
   (t
    (downcase
     (or
      (get-char-code-property char 'name)
      (get-char-code-property char 'old-name)
      (format "%c" char))))))

(defun tts-unicode-char-punctuation-p (char)
  "Use unicode properties to determine whether CHAR is a
ppunctuation character."
  (let ((category (get-char-code-property char 'category))
        (case-fold-search t))
    (when (stringp category)
      (string-match "punctuation" category))))

(defun tts-unicode-apply-name-transformation-rules (name)
  "Apply transformation rules in
tts-unicode-name-transformation-rules-alist to NAME."
  (let ((case-fold-search t))
    (funcall
     (or
      (assoc-default
       name
       tts-unicode-name-transformation-rules-alist 'string-match)
      'identity)
     name)))

(defun tts-unicode-uncustomize-char (char)
  "Delete custom replacement for CHAR.

When called interactively, CHAR defaults to the character after point."
  (interactive (list (following-char)))
  (setq tts-unicode-character-replacement-alist
        (cl-loop for elem in tts-unicode-character-replacement-alist
                 unless (eq (car elem) char) collect elem)))

(defun tts-unicode-customize-char (char replacement)
  "Add a custom replacement string for CHAR.

When called interactively, CHAR defaults to the character after point."
  (interactive
   (let ((char (following-char)))
     (list char
           (read-string
            (format
             "Replacement for %c (0x%x) from charset %s: "
             char char (char-charset char))))))
  (push (cons char replacement) tts-unicode-character-replacement-alist))

;;;  Character replacement handlers

(defun tts-unicode-user-table-handler (char)
  "Return user defined replacement character if it exists."
  (cdr (assq char tts-unicode-character-replacement-alist)))

(defun tts-unicode-full-table-handler (char)
  "Uses the unicode data file to find the name of CHAR."
  (let ((char-desc (tts-unicode-name-for-char char)))
    (when char-desc
      (format
       " %s " (tts-unicode-apply-name-transformation-rules char-desc)))))

;;;  External interface

(defun tts-unicode-full-name-for-char (char)
  "Return full name of CHAR. "
  (tts-unicode-name-for-char char))
(defun tts-unicode-short-name-for-char (char)
  "Return short name of CHAR. "
  (if (memq char tts-unicode-untouched-charsets)
      (char-to-string char)
    (tts-unicode-name-for-char char)))

(defun tts-unicode-replace-chars (mode)
  "Replace unicode characters with something  TTS friendly. "
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward tts-unicode-charset-filter-regexp nil t)
        (let* ((pos (match-beginning 0))
               (char (char-after pos))
               (props (text-properties-at pos))
               (replacement
                (save-match-data
                  (if (and
                       (memq mode '(some none))
                       (tts-unicode-char-punctuation-p char))
                      " "
                    (run-hook-with-args-until-success
                     'tts-unicode-handlers char)))))
          (tts--replace-match-preserving-aural-plan replacement t t)
          (when props
            (set-text-properties pos (point) props)))))))

;;; tts-speak.el ends here

(add-hook 'after-change-major-mode-hook
          #'tts-apply-punctuation-mode-policy)

(provide 'tts-speak)

;; coding: utf-8

;;; tts-speak.el ends here
