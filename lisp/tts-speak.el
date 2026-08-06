;;; tts-speak.el --- Interface to speech server -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacs interface to TTS
;; Keywords: TTS  Emacs Elisp
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4670 $ |
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
;; This module defines the generic TTS interface.
;;; Code:
;;

;;  required modules

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-transport)

;;;  Forward Declarations:

(defvar emacsvox-last-message)
(defvar org-fold-core-style)
(defvar org-link-descriptive)
(defvar tts-default-voice)
(defvar tts-notify-process)
(defvar tts-speaker-process)
(defvar tts-punctuation-mode)
(defvar tts-split-caps)
(defvar tts-caps)
(defvar tts-speech-rate)
(defvar emacsvox-aural-source-invisible-property)

(declare-function ems--fastload "emacsvox-preamble" (file))
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
  "Speech-server.
Choices:
dtk-exp     For the Dectalk Express.
outloud     For IBM ViaVoice Outloud
espeak      For eSpeak (default on Linux)
mac for MAC TTS (default on Mac)")

;;; Speech-server protocol:

;;;;  macros

(defmacro tts-with-punctuations (setting &rest body)
  "Set punctuation  and exec   body."
  (declare (indent 1) (debug t))
  `(let ((save-punctuation-mode tts-punctuation-mode))
     (unless (eq ,setting save-punctuation-mode)
       (tts--protocol-set-punctuations ,setting)
       (setq tts-punctuation-mode ,setting))
     ,@body
     (unless (eq ,setting save-punctuation-mode)
       (setq tts-punctuation-mode save-punctuation-mode)
       (tts--protocol-set-punctuations save-punctuation-mode))))

;;;;  silence

(defun tts--protocol-silence (duration &optional force)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "sh %d%s\n"
           duration
           (if force "\nd" ""))))

;;;;   tone

(defun tts--protocol-tone (pitch duration &optional force)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "t %d %d%s\n"
           pitch duration
           (if force "\nd" ""))))

;;;;   queue

(defun tts--protocol-queue-text (text)
  
  (unless (string-match "^[[:space:]]+$" text)
    (emacsvox-aural-delivery-send
     tts-speaker-process (format "q {%s }\n" text))))

(defun tts--protocol-queue-code (code)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process (format "c {%s }\n" code)))

;;;;   speak

(defun tts--protocol-dispatch ()
  
  (emacsvox-aural-delivery-send tts-speaker-process "d\n"))

(defconst tts--tracked-status-prefix "__EMACSVOX_TRACKED__"
  "Speech-server output prefix for tracked dispatch status records.")

(defconst tts--tracked-playback-completion-programs '("windows-outloud")
  "Speech servers that report interruptible playback completion.

Entries are executable basenames.  A server belongs here only when it emits a
tracked `completed' record after its synthesis and audio queues are empty, and
a `cancelled' record when pending input interrupts that wait.")

(defvar tts--tracked-dispatch-sequence 0
  "Sequence used to identify tracked speech dispatches.")

(defvar tts--tracked-dispatches (make-hash-table :test #'eql)
  "Tracked speech callbacks indexed by dispatch identifier.")

(defconst tts--tracked-filter-property 'tts--tracked-original-filter
  "Process property retaining the filter replaced for tracked speech.")

(defconst tts--tracked-fragment-property 'tts--tracked-output-fragment
  "Process property retaining incomplete tracked server output.")

(defun tts--forward-untracked-output (process output)
  "Forward untracked OUTPUT from PROCESS to its original filter."
  (when-let* ((filter (process-get process tts--tracked-filter-property)))
    (unless (eq filter #'tts--speaker-process-filter)
      (funcall filter process output))))

(defun tts-tracked-playback-completion-p (&optional program)
  "Return non-nil when speech-server PROGRAM reports playback completion.
PROGRAM defaults to `tts-program'.  The result describes the server protocol,
not proof that audio reached a physical output device."
  (member
   (file-name-nondirectory (or program tts-program ""))
   tts--tracked-playback-completion-programs))

(defun tts--require-tracked-playback-completion ()
  "Signal a clear error unless the active server supports tracked playback."
  (unless (tts-tracked-playback-completion-p)
    (user-error
     "Speech server `%s' cannot report playback completion; tracked reading is unavailable"
     (file-name-nondirectory (or tts-program "unset")))))

(defun tts--complete-tracked-dispatch (process line)
  "Handle tracked status LINE from PROCESS.
Return non-nil when LINE is a tracked status record."
  (when
      (string-match
       (format
        "\\`%s \\([[:digit:]]+\\) \\(completed\\|cancelled\\|failed\\)\\'"
        (regexp-quote tts--tracked-status-prefix))
       line)
    (let* ((identifier (string-to-number (match-string 1 line)))
           (status (intern (match-string 2 line)))
           (entry (gethash identifier tts--tracked-dispatches)))
      (when (and entry (eq process (car entry)))
        (remhash identifier tts--tracked-dispatches)
        (condition-case error-data
            (funcall (cdr entry) identifier status)
          (error
           (message "Tracked speech callback failed: %s"
                    (error-message-string error-data))))))
    t))

(defun tts--speaker-process-filter (process output)
  "Recognize tracked completion records in PROCESS OUTPUT."
  (let ((pending
         (concat
          (or (process-get process tts--tracked-fragment-property) "")
          output))
        line-end)
    (while (setq line-end (string-search "\n" pending))
      (let ((line (string-trim-right (substring pending 0 line-end) "\r")))
        (unless (tts--complete-tracked-dispatch process line)
          (tts--forward-untracked-output process (concat line "\n"))))
      (setq pending (substring pending (1+ line-end))))
    (process-put process tts--tracked-fragment-property pending)))

(defun tts--ensure-tracked-process-filter (process)
  "Install tracked completion filtering on PROCESS."
  (unless (eq (process-filter process) #'tts--speaker-process-filter)
    (process-put process tts--tracked-filter-property (process-filter process))
    (process-put process tts--tracked-fragment-property "")
    (set-process-filter process #'tts--speaker-process-filter)))

(defun tts-cancel-tracked-dispatch (identifier)
  "Forget tracked speech dispatch IDENTIFIER."
  (remhash identifier tts--tracked-dispatches))

(defun tts--cancel-process-tracked-dispatches (process)
  "Forget every tracked dispatch owned by PROCESS."
  (let (identifiers)
    (maphash
     (lambda (identifier entry)
       (when (eq process (car entry))
         (push identifier identifiers)))
     tts--tracked-dispatches)
    (dolist (identifier identifiers)
      (remhash identifier tts--tracked-dispatches))))

(defun tts--interrupt-process (process &optional notifications)
  "Stop PROCESS and retire callbacks that can no longer complete.

When NOTIFICATIONS is non-nil, also stop the notification speech stream.
Pending aural deliveries are owned by the caller because replacement and
urgent policies cancel different scopes."
  (when
      (and notifications
           (process-live-p tts-notify-process))
    (tts-notify-stop))
  (tts--cancel-process-tracked-dispatches process)
  (when (process-live-p process)
    (emacsvox-aural-delivery-send process "s\n" 'stop))
  (run-hook-with-args 'tts-stopped-hook process))

(defun tts--retire-process (process)
  "Cancel state owned by PROCESS, stop it, and delete it.

This is the primary speech-process lifecycle boundary.  Pending replaceable
delivery, tracked completion callbacks, and clients of `tts-stopped-hook' are
retired before PROCESS can become an unreachable dead owner."
  (when (processp process)
    (emacsvox-aural-cancel-pending-deliveries process)
    (tts--interrupt-process process)
    (delete-process process)))

(defun tts--protocol-dispatch-tracked (callback)
  "Dispatch queued speech and call CALLBACK with its terminal server status.
CALLBACK receives the dispatch identifier and either `completed', `cancelled',
or `failed'.  Return the identifier allocated to this dispatch."
  (unless (functionp callback)
    (signal 'wrong-type-argument (list 'functionp callback)))
  (tts--require-tracked-playback-completion)
  (tts--ensure-tracked-process-filter tts-speaker-process)
  (let ((identifier (cl-incf tts--tracked-dispatch-sequence)))
    (puthash
     identifier (cons tts-speaker-process callback)
     tts--tracked-dispatches)
    (emacsvox-aural-delivery-send
     tts-speaker-process
     (format "emacsvox_tracked_dispatch %d\n" identifier))
    identifier))

;;;;  say

(defun tts--protocol-say (string)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_say { %s}\n" string)))

;;;;  stop

(defun tts--protocol-stop ()
  
  (emacsvox-aural-delivery-send tts-speaker-process "s\n" 'stop))

;;;;  sync

(defun tts--protocol-sync ()
  "Synchronize speech state with running server"
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_sync_state %s %s %s %s\n"
           tts-punctuation-mode
           (if tts-split-caps 1 0)
           (if tts-caps 1 0)
           tts-speech-rate)))

;;;;   letter

(defun tts--protocol-letter (letter)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "l {%s}\n" letter)))

;;;;   language

(defun tts--protocol-next-language (&optional say_it)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "set_next_lang %s\n" say_it)))

(defun tts--protocol-previous-language (&optional say_it)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "set_previous_lang %s\n" say_it)))

(defun tts--protocol-set-language (language say_it)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "set_lang %s %s \n" language say_it)))

(defun tts--protocol-set-preferred-language (alias language)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "set_preferred_lang %s %s \n" alias language)))

;;;;   Version, rate

(defun tts--protocol-version ()
  
  (emacsvox-aural-delivery-send tts-speaker-process "version\n"))

(defun tts--protocol-set-rate (rate)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_set_speech_rate %s\n" rate)))

;;;;  character scale

(defun tts--protocol-set-character-scale (factor)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_set_character_scale %s\n"
           factor)))

;;;;   split caps

(defun tts--protocol-set-split-caps (flag)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_split_caps %s\n" (if flag 1 0))))

;;;;  punctuations

(defun tts--protocol-set-punctuations (mode)
  
  (emacsvox-aural-delivery-send
   tts-speaker-process
   (format "tts_set_punctuations %s\nd\n" mode)))

;;;;  reset

(defun tts--protocol-reset ()
  
  (emacsvox-aural-delivery-send tts-speaker-process "tts_reset \n"))

;;;   user customizations:

(defgroup tts nil
  "TTS." ;; ¿¿I guess this is shorthand for "Thou art Totally Screwed"??
  :group 'emacsvox
  :prefix "dtk-")

(defvar-local tts-strip-octals nil
  "Strip all octal chars. ")

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
Capitalized words are preceded by `cap', and upper-case words are
  preceded by `ac' spoken in a lower voice.
Use tts-toggle-caps
bound to \\[tts-toggle-caps].")

(defconst tts-punctuation-mode-alist
  '("some" "all" "none")
  "List of  punctuation modes.")

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
          emacsvox-aural-concrete-plan-property)))
    (replace-match replacement fixedcase literal nil subexp)
    (when plan
      (put-text-property
       start (point) emacsvox-aural-concrete-plan-property plan))))

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
       (while (search-forward w nil t)
         (tts-replace-match pronunciation)))
      ((consp pronunciation)
       (let ((matcher (car pronunciation))
             (pronouncer (cdr pronunciation))
             (pronunciation ""))
         (while (funcall matcher w nil t)
           (setq
            pronunciation
            (save-match-data
              (funcall pronouncer
                       (buffer-substring
                        (match-beginning 0) (match-end 0)))))
           (tts-replace-match pronunciation))))))))

;;;   Helpers to handle invisible text:

(defun tts--invisible-at-p (position)
  "Return non-nil when text at POSITION must be omitted from speech."
  (or
   (get-char-property position emacsvox-aural-source-invisible-property)
   (invisible-p position)))

(defun tts--next-invisibility-change (position)
  "Return the next speech-invisibility boundary after POSITION."
  (let ((limit (point-max)))
    (min
     (next-single-property-change
      position 'invisible (current-buffer) limit)
     (next-single-property-change
      position emacsvox-aural-source-invisible-property
      (current-buffer) limit))))

(defun tts--previous-invisibility-change (position)
  "Return the previous speech-invisibility boundary before POSITION."
  (let ((limit (point-min)))
    (max
     (previous-single-property-change
      position 'invisible (current-buffer) limit)
     (previous-single-property-change
      position emacsvox-aural-source-invisible-property
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
       (t (goto-char
           (or (next-single-property-change (point) 'invisible)
               (point-max)))
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
 omitted."
  (interactive "sEnter language: \n")
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-set-language lang nil)))
    (tts--protocol-set-language lang (called-interactively-p 'interactive))))

(defun tts-set-next-language ()
  "Switch to  next  language"
  (interactive)
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-next-language nil)))
    (tts--protocol-next-language (called-interactively-p 'interactive))))

(defun tts-set-previous-language ()
  "Switch to  previous  language"
  (interactive)
  
  (when (process-live-p tts-speaker-process)
    (unless (eq tts-speaker-process (tts-notify-process))
      (let ((tts-speaker-process (tts-notify-process)))
        (tts--protocol-previous-language nil)))
    (tts--protocol-previous-language (called-interactively-p 'interactive))))

(defun tts-set-preferred-language (alias lang)
  "Set language by alias."
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
(defconst tts-caps-regexp
  (concat
   "\\(\\b[A-Z][A-Z0-9_-]+\\b\\)"
   "\\|"
   "\\(\\b[A-Z]\\)")
  "Match capitalized or upper-case words.")

(defcustom tts-caps-prefix

  (propertize  "cap" 'personality 'acss-s4-r6)
  "Prefix used to indicate capitalization":type 'string
  :group 'tts
  :set #'(lambda (sym val)
           (set-default sym
                        (propertize  val 'personality 'acss-p3-s1-r3))))

(defcustom tts-allcaps-prefix

  (propertize  " acc " 'personality 'acss-s4-r6)
  "Prefix used to indicate AllCaps"
  :type 'string
  :group 'tts
  :set #'(lambda (sym val)
           (set-default sym
                        (propertize  val 'personality 'acss-p3-s1-r3))))

(defun tts-handle-caps ()
  "Handle capitalization"
  (when tts-caps
    (let ((inhibit-read-only t)
          (case-fold-search nil))
      (goto-char (point-min))
      (while
          (re-search-forward tts-caps-regexp nil t)
        (save-excursion
          (goto-char (match-beginning 0))
          (cond
           ((= 1  (- (match-end 0) (match-beginning 0)))
            (insert tts-caps-prefix))
           (t (insert tts-allcaps-prefix))))))))

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
    (tts-handle-caps)
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
    (tts--protocol-queue-code (tts-voice-reset-code))))

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

(defun tts-audio-format (start end)
  "Format and speak text from `start' to `end'. "
  (if (emacsvox-aural-concrete-plan-at start)
      (let ((position start)
            runs)
        (while (< position end)
          (let ((plan (emacsvox-aural-concrete-plan-at position))
                (next
                 (next-single-property-change
                  position emacsvox-aural-concrete-plan-property
                  (current-buffer) end)))
            (push
             (list
              plan
              (buffer-substring-no-properties position next)
              (get-text-property position 'pause))
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
  "Stop speech.  Optional arg `all' or interactive call silences
  notification stream as well."
  (interactive "P")
  (emacsvox-aural-cancel-pending-deliveries tts-speaker-process)
  (tts--interrupt-process tts-speaker-process)
  (when
      (and (tts-notify-process)
           (or all (called-interactively-p 'interactive)))
    (tts-notify-stop)))

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

(defun tts-set-punctuations (mode &optional prefix)
  "Set punctuation mode to MODE.
Possible values are `some', `all', or `none'.
Interactive PREFIX arg means set   the global default value, and then set the
current local  value to the result."
  (interactive
   (list
    (intern
     (completing-read "Enter punctuation mode: "
                      tts-punctuation-mode-alist
                      nil
                      t))
    current-prefix-arg))
  (when (process-live-p tts-speaker-process)
    (cond
     (prefix
      (setq tts-punctuation-mode mode)
      (setq-default tts-punctuation-mode mode))
     (t (make-local-variable 'tts-punctuation-mode)
        (setq tts-punctuation-mode mode)))
    (tts--protocol-set-punctuations mode)
    (when (called-interactively-p 'interactive)
      (message "set punctuation mode to %s %s"
               mode
               (if prefix "" "locally")))))

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
   ((eq 'all tts-punctuation-mode)
    (tts-set-punctuations-to-some prefix))
   ((eq 'some tts-punctuation-mode)
    (tts-set-punctuations-to-all prefix)))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'button)
    (message "set punctuation mode to %s %s"
             tts-punctuation-mode
             (if prefix "" "locally"))))

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
    (aset table 28 "control[*]backslash")
    (aset table 29 "control[*]right bracket")
    (aset table 30 "control[*]caret")
    (aset table 31 "control[*]underscore")
    (aset table 32 "space")
    (aset table 33 "exclamation")
    (aset table 34 "quotes")
    (aset table 35 "pound")
    (aset table 36 "dollar")
    (aset table 37 "percent")
    (aset table 38 "ampersand")
    (aset table 39 "apostrophe")
    (aset table 40 "left[*]paren")
    (aset table 41 "right[*]paren")
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
    (aset table 60 "less[*]than")
    (aset table 61 "equals")
    (aset table 62 "greater[*]than")
    (aset table 63 "question[*]mark")
    (aset table 64 "at")
    (aset table 65 " cap[*]a")
    (aset table 66 " cap[*]b")
    (aset table 67 "cap[*]c")
    (aset table 68 "cap[*]d")
    (aset table 69 "cap[*]e")
    (aset table 70 "cap[*]f")
    (aset table 71 "cap[*]g")
    (aset table 72 "cap[*]h")
    (aset table 73 "cap[*]i")
    (aset table 74 "cap[*]j")
    (aset table 75 "cap[*]k")
    (aset table 76 "cap[*]l")
    (aset table 77 "cap[*]m")
    (aset table 78 "cap[*]m")
    (aset table 79 "cap[*]o")
    (aset table 80 "cap[*]p")
    (aset table 81 "cap[*]q")
    (aset table 82 "cap[*]r")
    (aset table 83 "cap[*]s")
    (aset table 84 "cap[*]t")
    (aset table 85 "cap[*]u")
    (aset table 86 "cap[*]v")
    (aset table 87 "cap[*]w")
    (aset table 88 "cap[*]x")
    (aset table 89 "cap[*]y")
    (aset table 90 "cap[*]z")
    (aset table 91 "left[*]bracket")
    (aset table 92 "backslash")
    (aset table 93 "right[*]bracket")
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
    (aset table 123 "left[*]brace")
    (aset table 124 "pipe")
    (aset table 125 "right[*]brace ")
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

(defun tts-default-voice-capabilities ()
  "Return the compatibility capability descriptor for an unknown adapter."
  '(:adapter unknown
    :source compatibility
    :family-selection unsupported
    :families nil
    :generic-families nil
    :dimensions nil
    :parameters nil))

(defvar tts-voice-capabilities-function
  #'tts-default-voice-capabilities
  "Function returning the active speech adapter's voice capabilities.

The returned data is a plist.  `:adapter' identifies the adapter;
`:source' says whether its data is static, discovered, or a compatibility
fallback; `:family-selection' is `enumerated', `free-form', or
`unsupported'; `:families' contains entries of the form
(ID :label LABEL ...); `:dimensions' lists supported normalized ACSS
dimensions; and `:parameters' describes their accepted values.")

(defun tts-voice-capabilities ()
  "Return an isolated copy of the active adapter's voice capabilities."
  (let ((capabilities
         (and
          (functionp tts-voice-capabilities-function)
          (funcall tts-voice-capabilities-function))))
    (copy-tree
     (if (and (listp capabilities) (plist-get capabilities :adapter))
         capabilities
       (tts-default-voice-capabilities)))))

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
  '("espeak"  "outloud"   "dtk-soft" "sharpwin" "swiftmac")
  "List of TTS engines that are multi capable.")

(defsubst tts-multistream-p (engine)
  "Checks if this tts-engine can support multiple streams."
  
  (and
   (not (string= tts-notification-device "default"))
   (cl-find-if #'(lambda (e) (string-match e engine)) tts-multi-engines)))

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

(defcustom tts-notification-device
  nil
  "Virtual sound device to use for notifications stream.
Set to nil to disable a separate Notification stream.
If you set the device here, make sure it exists first.
For swiftmac, set this to `left' or `right'."
  :type '(choice
          (const :tag "None" nil)
          (string :value ""))
  :group 'tts)

;; Helper: tts-make-process:
(defun tts-make-process (name)
  "Make a  TTS process called name."
  
  (let ((process-connection-type nil)
        (default-directory (expand-file-name "~/"))
        (program (expand-file-name tts-program emacsvox-servers-directory))
        (process nil))
    (setq process
          (start-process name nil program))
    (unless (process-live-p process) (error "Fail: Speech Server"))
    (set-process-coding-system process 'utf-8 'utf-8)
    process))

(declare-function voice-setup "voice-setup" ())
(defun tts-initialize ()
  "Initialize speech system."
  
  ;; fallback of fallbacks
  (unless tts-program (setq tts-program "espeak"))
  (let ((new (tts-make-process "Speaker")))
    ;; Retire the old server only after its replacement starts successfully.
    (when (processp tts-speaker-process)
      (tts--retire-process tts-speaker-process))
    (setq tts-speaker-process new)
    (when (tts-multistream-p tts-program) (tts-notify-initialize))
    (when (string-match "cloud" tts-program) ; we'll serve icons.
      (setq emacsvox-play-program nil))
    ;; `voice-setup' requires us, so we can't require it at top-level.
    (require 'voice-setup)
    (voice-setup)))

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

(defun tts--speak (text)
  "Implement `tts-speak' for TEXT with source context already captured."
  ;; ensure text is a  string
  (unless (stringp text) (when text (setq text (format "%s" text))))
  ;; ensure  the process  is live
  (unless (process-live-p tts-speaker-process) (tts-initialize))
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
    (when (process-live-p tts-notify-process) (tts-notify-stop))
    (tts-stop))
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
        (tts-caps-prefix
         (if tts-caps
             (emacsvox-aural-prepare-text
              tts-caps-prefix
              (list :content
                    (substring-no-properties tts-caps-prefix))
              emacsvox-aural-submission-context)
           tts-caps-prefix))
        (tts-allcaps-prefix
         (if tts-caps
             (emacsvox-aural-prepare-text
              tts-allcaps-prefix
              (list :content
                    (substring-no-properties tts-allcaps-prefix))
              emacsvox-aural-submission-context)
           tts-allcaps-prefix))
        (tts-scratch-buffer (get-buffer-create " *tts-scratch-buffer* "))
        (start 1)
        (end nil)
        (mode tts-punctuation-mode)
        (voice-lock voice-lock-mode)) ; done snapshotting
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
      (set-syntax-table syntax-table)
      (tts--protocol-sync)
      (insert-for-yank text)          ; insert and pre-process text
      (tts--delete-invisible-text)
      (tts-handle-repeating-patterns mode)
      (when pron-table (tts-apply-pronunciations pron-table))
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
        (unless (eobp) (tts-audio-format (point) (point-max))))))
  (if tts--tracked-completion-function
      (tts--protocol-dispatch-tracked tts--tracked-completion-function)
    (tts--protocol-dispatch)))

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
  (let ((tts-scratch-buffer (get-buffer-create " *tts-scratch-buffer* "))
        (contents nil)
        (count 1)
        (inhibit-read-only t))
    (save-current-buffer
      (set-buffer tts-scratch-buffer)
      (setq buffer-undo-list  t)
      (erase-buffer)
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

(defun tts-letter (letter)
  "Speak a LETTER."
  (unless tts-quiet
    (when (process-live-p tts-speaker-process)
      (tts--protocol-letter letter))))
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

(defun tts-notify-initialize ()
  "Initialize notification TTS stream."
  (interactive)
  
  (let ((new nil)
        (tts-program
         (if (string-match "cloud" tts-program) "cloud-notify" tts-program)))
    (when (and tts-notify-process (process-live-p tts-notify-process))
      (delete-process tts-notify-process))
    (unless
        (and (not (string-match "cloud" tts-program))
             (zerop (length tts-notification-device)))
      (with-environment-variables
          (("ALSA_DEFAULT" tts-notification-device)
           ("SWIFTMAC_AUDIO_TARGET" tts-notification-device)
           ("SHARPWIN_AUDIO_TARGET" tts-notification-device)
           ("PULSE_SINK" tts-notification-device))
        (setq  new (tts-make-process "Notify"))
        (when (process-live-p new)
          (setq tts-notify-process new))))))

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

(provide 'tts-speak)

;; coding: utf-8
