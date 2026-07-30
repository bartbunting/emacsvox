;;; emacsvox-advice.el --- Advice Emacs Core   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Core advice forms that make emacsvox work
;; Keywords: Emacsvox, Speech, Advice, Spoken output
;;;  LCD Archive entry:a

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;; $Revision: 4550 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;  Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995, 1996, 1997 by T. V. Raman
;; All Rights Reserved.
;;
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

:

;;; Commentary:

;; This module defines the advice forms for making the core of Emacs speak
;; Advice forms that are specific to Emacs subsystems do not belong here!
;; I violate this at present by advising completion.
;; Note that we needed to advice a lot more for Emacs 19 and
;; Emacs 20 than we do for Emacs 21 and Emacs 22.
;; As of August 2007, this file is being purged of advice forms
;; not needed in Emacs 22.

;;; Code:

;;  Required modules: 

(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'advice))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defvar read-passwd--password-hidden)
(defvar emacsvox-aural-submission-facts nil
  "Dynamically bound semantic facts for the current speech submission.")
(defvar emacsvox-aural-submission-occasion nil
  "Dynamically bound occasion for the current speech submission.")

(defmacro emacsvox-advice--define-interactive-after-advice
    (targets docstring &rest body)
  "Define native interactive after advice for each command in TARGETS.
DOCSTRING and BODY define the feedback function for each command."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (advice-add
                ',target :after #',function '((name . emacsvox))))))
        targets)))

(defmacro emacsvox-advice--define-interactive-before-advice
    (targets docstring &rest body)
  "Define native interactive before advice for each command in TARGETS.
DOCSTRING and BODY define the feedback function for each command."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-before" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (advice-add
                ',target :before #',function '((name . emacsvox))))))
        targets)))

;;;   Advice Replace

(voice-setup-add-map '((query-replace voice-animate)))

(emacsvox-advice--define-interactive-after-advice
    (query-replace query-replace-regexp)
    "Cue completion of an interactive query replacement."
  (emacsvox-icon 'task-done))

(defun emacsvox--advice-perform-replace-around
    (original &rest arguments)
  "Call ORIGINAL with replacement messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(advice-add
 'perform-replace :around #'emacsvox--advice-perform-replace-around
 '((name . emacsvox)))

(defun emacsvox--advice-replace-highlight-after (&rest _)
  "Speak the line after highlighting a replacement."
  (emacsvox-speak-line))

(advice-add
 'replace-highlight :after #'emacsvox--advice-replace-highlight-after
 '((name . emacsvox)))

;;;  advice overlays

;;; Helpers:

(defun ems--add-personality (start end voice &optional object)
  "Apply personality VOICE."
  (when
      (and
       (integerp start) (integerp end)
       (not (= start end)))
    (with-current-buffer
        (if (bufferp object) object (current-buffer))
      (with-silent-modifications
        (put-text-property start end 'personality voice object)))))

(defun ems--remove-personality  (start end voice &optional object)
  "Remove  personality. "
  (when
      (and
       voice
       (integerp start) (integerp end)
       (not (= start end))
       (eq voice (get-text-property start 'personality object)))
    (with-current-buffer
        (if (bufferp object) object (current-buffer))
      (with-silent-modifications
        (put-text-property start end 'personality nil object)))))

(defvar ems--voiceify-overlays t
  "Voicify overlays")

;; Needed for  outline support:

(defun emacsvox--advice-remove-overlays-around
    (original &rest arguments)
  "Clean up properties mirrored from overlays."
  (let ((ems--voiceify-overlays nil)
        (beg (or (nth 0 arguments) (point-min)))
        (end (or (nth 1 arguments) (point-max)))
        (name (nth 2 arguments)))
    (when (zerop beg) (setq beg (point-min)))
    (with-silent-modifications (put-text-property beg end name nil))
    (apply original arguments)))

(advice-add
 'remove-overlays :around #'emacsvox--advice-remove-overlays-around
 '((name . emacsvox)))

(defun emacsvox--advice-delete-overlay-before (overlay)
  "Augment voice lock."
  (when ems--voiceify-overlays
    (let* ((buffer (overlay-buffer overlay))
           (start (overlay-start overlay))
           (end (overlay-end overlay))
           (voice
            (tts-get-voice-for-face (overlay-get overlay 'face)))
           (invisible (overlay-get overlay 'invisible)))
      (when (and start end voice buffer)
        (with-current-buffer buffer
          (save-restriction
            (widen) (ems--remove-personality start end voice buffer))))
      (when (and start end invisible)
        (with-silent-modifications
          (put-text-property start end 'invisible nil))))))

(advice-add
 'delete-overlay :before #'emacsvox--advice-delete-overlay-before
 '((name . emacsvox)))

(defun emacsvox--advice-overlay-put-after (overlay property value)
  "Augment voice lock."
  (when (and (overlay-buffer overlay) ems--voiceify-overlays)
    (let ((start (overlay-start overlay))
          (end (overlay-end overlay))
          voice)
      (cond
       ((and
         (or (memq property '(font-lock-face face))
             (and (eq property 'category) (get value 'face)))
         (integerp start) (integerp end))
        (when (eq property 'category)
          (setq value (get value 'face)))
        (setq voice (tts-get-voice-for-face value))
        (when voice
          (ems--add-personality start end voice
                                (overlay-buffer overlay))))
       ((eq property 'invisible)
        (with-current-buffer (overlay-buffer overlay)
          (with-silent-modifications
            (put-text-property start end 'invisible (or value nil)))))))))

(advice-add
 'overlay-put :after #'emacsvox--advice-overlay-put-after
 '((name . emacsvox)))

(defun emacsvox--advice-move-overlay-before
    (overlay beginning end &optional object)
  "Used by emacsvox to augment voice lock."
  (when ems--voiceify-overlays
    (let* ((buffer (overlay-buffer overlay))
           (voice
            (tts-get-voice-for-face (overlay-get overlay 'face)))
           (invisible (overlay-get overlay 'invisible)))
      (unless object (setq object (or buffer (current-buffer))))
      (when
          (and voice (integerp (overlay-start overlay))
               (integerp (overlay-end overlay)))
        (ems--remove-personality (overlay-start overlay)
                                 (overlay-end overlay) voice buffer)
        (ems--add-personality beginning end voice object))
      (when invisible
        (with-current-buffer buffer
          (with-silent-modifications
            (put-text-property (overlay-start overlay)
                               (overlay-end overlay) 'invisible nil)))
        (with-current-buffer object
          (with-silent-modifications
            (put-text-property
             beginning end 'invisible invisible)))))))

(advice-add
 'move-overlay :before #'emacsvox--advice-move-overlay-before
 '((name . emacsvox)))

;;;  advice cursor movement commands to speak

(defun emacsvox-advice--navigation-facts ()
  "Return current submission facts extended with focus-entry navigation."
  (let* ((facts (copy-tree emacsvox-aural-submission-facts))
         (events
          (append
           (copy-sequence (plist-get facts :events))
           '(focus-entered))))
    (plist-put facts :events (delete-dups events))))

(emacsvox-advice--define-interactive-after-advice
    (next-line previous-line)
    "Speak line. Speak  (visual) line if
`visual-line-mode' is  on, and
indicate  point  by an aural highlight.   Moving to
beginning or end of a physical line produces an  auditory icon."
  (let ((emacsvox-aural-submission-facts
         (emacsvox-advice--navigation-facts))
        (emacsvox-aural-submission-occasion 'navigation))
    (cond
     ((or line-move-visual visual-line-mode) (emacsvox-speak-visual-line))
     (t (emacsvox-speak-line)))))

(emacsvox-advice--define-interactive-after-advice
    (delete-horizontal-space)
    "Indicate deleted horizontal space."
  (emacsvox-icon 'delete-object))

(emacsvox-advice--define-interactive-before-advice
    (kill-visual-line)
    "Speak the visual line before killing it."
  (emacsvox-icon 'delete-object)
  (emacsvox-speak-visual-line))

(emacsvox-advice--define-interactive-after-advice
    (beginning-of-visual-line end-of-visual-line)
    "Speak visual line with show-point enabled."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-visual-line)))

(emacsvox-advice--define-interactive-after-advice
    (next-logical-line previous-logical-line
     delete-indentation back-to-indentation
     lisp-indent-line goto-line goto-line-relative)
    "Speak line with show-point enabled."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(defun emacsvox--button-movement-around (target original arguments)
  "Call ORIGINAL with ARGUMENTS and speak the button reached by TARGET."
  (if (ems-interactive-p target)
      (let (result)
        (ems-with-messages-silenced
          (setq result (apply original arguments))
          (condition-case nil
              (let* ((button (button-at (point)))
                     (start (button-start button))
                     (end (button-end button)))
                (tts-speak (buffer-substring start end))
                (emacsvox-icon 'large-movement))
            (error nil)))
        result)
    (apply original arguments)))

(defun emacsvox--advice-forward-button-around (original &rest arguments)
  "Speak the button reached by `forward-button'."
  (emacsvox--button-movement-around
   'forward-button original arguments))

(advice-add
 'forward-button :around #'emacsvox--advice-forward-button-around
 '((name . emacsvox)))

(defun emacsvox--advice-backward-button-around (original &rest arguments)
  "Speak the button reached by `backward-button'."
  (emacsvox--button-movement-around
   'backward-button original arguments))

(advice-add
 'backward-button :around #'emacsvox--advice-backward-button-around
 '((name . emacsvox)))

(defun emacsvox--advice-blink-matching-open-after (&rest _)
  "Speak the matching opening delimiter."
  (emacsvox-speak-matching-paren))

(advice-add
 'blink-matching-open :after
 #'emacsvox--advice-blink-matching-open-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (left-char right-char backward-char forward-char)
    "Speak char under point.
When on a close delimiter, speak matching delimiter after a small delay. "
  (and tts-stop-immediately (tts-stop))
  (emacsvox-speak-char t)
  (when
      (and
       (= ?\) (char-syntax (following-char)))
       (sit-for 0.25))
    (emacsvox-icon 'tick-tick)
    (save-excursion
      (forward-char 1)
      (emacsvox-speak-matching-paren))))

(emacsvox-advice--define-interactive-after-advice
    (forward-word right-word)
    "Speak the word after moving forward."
  (skip-syntax-forward " ")
  (emacsvox-speak-word))

(emacsvox-advice--define-interactive-after-advice
    (backward-word left-word)
    "Speak the word after moving backward."
  (emacsvox-speak-word))

(emacsvox-advice--define-interactive-after-advice
    (beginning-of-buffer end-of-buffer)
    "Speak the line."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line)
  (tts-notify (emacsvox-get-current-percentage-verbosely)))

(emacsvox-advice--define-interactive-after-advice
    (tab-to-tab-stop indent-for-tab-command reindent-then-newline-and-indent
     indent-sexp indent-pp-sexp indent-region indent-relative)
    "Speak the current column after indenting."
  (emacsvox-icon 'fill-object)
  (emacsvox-speak-current-column))

(emacsvox-advice--define-interactive-after-advice
    (backward-sentence forward-sentence)
    "Speak the sentence after moving."
  (emacsvox-speak-sentence))

(defun emacsvox--sexp-movement-around (target original arguments)
  "Call ORIGINAL with ARGUMENTS and speak the movement made by TARGET."
  (if (ems-interactive-p target)
      (let ((start (point))
            (end (line-end-position))
            (emacsvox-show-point t)
            result)
        (setq result (apply original arguments))
        (emacsvox-icon 'large-movement)
        (cond
         ((>= end (point))
          (emacsvox-speak-region start (point)))
         (t (emacsvox-speak-line)))
        result)
    (apply original arguments)))

(defmacro emacsvox-advice--define-sexp-movement-advice (targets)
  "Define native around advice for each movement command in TARGETS."
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (original &rest arguments)
                 ,(format "Speak movement produced by `%s'." target)
                 (emacsvox--sexp-movement-around
                  ',target original arguments))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        targets)))

(emacsvox-advice--define-sexp-movement-advice
 (forward-sexp backward-sexp beginning-of-defun end-of-defun))

(emacsvox-advice--define-interactive-after-advice
    (forward-paragraph backward-paragraph)
    "Speak the paragraph after moving."
  (emacsvox-icon 'paragraph)
  (emacsvox-speak-paragraph))

;; list navigation:

(emacsvox-advice--define-interactive-after-advice
    (forward-list backward-list up-list backward-up-list down-list)
    "Speak the line after list movement."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(emacsvox-advice--define-interactive-after-advice
    (forward-page backward-page)
    "Speak the page after moving."
  (emacsvox-icon 'scroll)
  (emacsvox-speak-page))

(emacsvox-advice--define-interactive-after-advice
    (scroll-other-window scroll-other-window-up scroll-other-window-down)
    "Speak the window that was scrolled."
  (save-window-excursion
    (with-selected-window (other-window-for-scrolling)
      (emacsvox-speak-windowful))))

(emacsvox-advice--define-interactive-after-advice
    (scroll-up scroll-down scroll-up-command scroll-down-command)
    "Speak the newly displayed screenful."
  (emacsvox-icon 'scroll)
  (tts-speak (emacsvox-get-window-contents))
  (tts-notify
   (propertize
    (format "%s " (emacsvox-get-current-percentage-into-buffer))
    'personality voice-smoothen)))

;;;  Advise modify case commands to speak

(defun emacsvox--case-word-around
    (target operation final-message original arguments)
  "Call ORIGINAL once, then speak TARGET's case change.
OPERATION is presented before an interactive change.  FINAL-MESSAGE is
announced when the change leaves point at the end of the buffer.  ARGUMENTS
are passed through unchanged."
  (if (ems-interactive-p target)
      (progn
        (emacsvox-speak-edit-operation operation)
        (let ((result (apply original arguments)))
          (cond
           ((and (numberp current-prefix-arg) (< current-prefix-arg 0))
            (let ((start (point)))
              (save-excursion
                (forward-word current-prefix-arg)
                (emacsvox-speak-region start (point)))))
           (t
            (save-excursion
              (skip-syntax-forward " ")
              (if (eobp) (message "%s" final-message)
                (emacsvox-speak-word)))))
          result))
    (apply original arguments)))

(defun emacsvox--advice-upcase-word-around (original &rest arguments)
  "Present the edit, then speak after `upcase-word'."
  (emacsvox--case-word-around
   'upcase-word 'uppercase "Upper cased final word in buffer"
   original arguments))

(advice-add
 'upcase-word :around #'emacsvox--advice-upcase-word-around
 '((name . emacsvox)))

(defun emacsvox--advice-downcase-word-around (original &rest arguments)
  "Present the edit, then speak after `downcase-word'."
  (emacsvox--case-word-around
   'downcase-word 'lowercase "Lower cased final word in buffer"
   original arguments))

(advice-add
 'downcase-word :around #'emacsvox--advice-downcase-word-around
 '((name . emacsvox)))

(defun emacsvox--advice-capitalize-word-around (original &rest arguments)
  "Present the edit, then speak after `capitalize-word'."
  (emacsvox--case-word-around
   'capitalize-word 'capitalize "Capitalized final word in buffer"
   original arguments))

(advice-add
 'capitalize-word :around #'emacsvox--advice-capitalize-word-around
 '((name . emacsvox)))

;;;  Advice insert-char:

(defun emacsvox--advice-insert-char-after (character &rest _)
  "Speak char."
  (when (ems-interactive-p 'insert-char)
    (emacsvox-speak-char-name character)))

(advice-add
 'insert-char :after #'emacsvox--advice-insert-char-after
 '((name . emacsvox)))

;;;  Advice deletion commands:

(defun emacsvox--backward-delete-char-around (target original arguments)
  "Speak before TARGET deletes backward, then call ORIGINAL with ARGUMENTS."
  (when (ems-interactive-p target)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-this-char (preceding-char)))
  (apply original arguments))

(defmacro emacsvox-advice--define-backward-delete-advice (targets)
  "Define native around advice for backward-deletion commands in TARGETS."
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (original &rest arguments)
                 ,(format "Speak the character deleted by `%s'." target)
                 (emacsvox--backward-delete-char-around
                  ',target original arguments))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        targets)))

(emacsvox-advice--define-backward-delete-advice
 (backward-delete-char backward-delete-char-untabify delete-backward-char))

(defun emacsvox--delete-char-around (target original arguments)
  "Speak before TARGET deletes a character, then call ORIGINAL with ARGUMENTS."
  (when (ems-interactive-p target)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-char t))
  (apply original arguments))

(defun emacsvox--advice-delete-forward-char-around (original &rest arguments)
  "Speak the character deleted by `delete-forward-char'."
  (emacsvox--delete-char-around
   'delete-forward-char original arguments))

(advice-add
 'delete-forward-char :around #'emacsvox--advice-delete-forward-char-around
 '((name . emacsvox)))

(defun emacsvox--advice-delete-char-around (original &rest arguments)
  "Speak the character deleted by `delete-char'."
  (emacsvox--delete-char-around 'delete-char original arguments))

(advice-add
 'delete-char :around #'emacsvox--advice-delete-char-around
 '((name . emacsvox)))

(defun emacsvox--advice-kill-word-before (&rest _)
  "Speak word beingkilled."
  (when (ems-interactive-p 'kill-word)
    (save-excursion
      (skip-syntax-forward " ")
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-word 1))))

(advice-add
 'kill-word :before #'emacsvox--advice-kill-word-before
 '((name . emacsvox)))

(defun emacsvox--advice-backward-kill-word-before (&rest _)
  "Speak word beingkilled."
  (when (ems-interactive-p 'backward-kill-word)
    (save-excursion
      (let ((start (point)))
        (forward-word -1)
        (emacsvox-speak-edit-operation 'deletion)
        (emacsvox-speak-region (point) start)))))

(advice-add
 'backward-kill-word :before #'emacsvox--advice-backward-kill-word-before
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-before-advice
    (kill-line kill-whole-line)
    "Speak the line before killing it."
  (emacsvox-icon 'delete-object)
  (emacsvox-speak-edit-operation 'deletion)
  (emacsvox-speak-line 1))

(defun emacsvox--advice-kill-sexp-before (&rest _)
  "Speak the killed  sexp."
  (when (ems-interactive-p 'kill-sexp)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-sexp 1)))

(advice-add
 'kill-sexp :before #'emacsvox--advice-kill-sexp-before
 '((name . emacsvox)))

(defun emacsvox--advice-kill-sentence-before (&rest _)
  "Speak the kill."
  (when (ems-interactive-p 'kill-sentence)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-line 1)))

(advice-add
 'kill-sentence :before #'emacsvox--advice-kill-sentence-before
 '((name . emacsvox)))

(defun emacsvox--advice-delete-blank-lines-before (&rest _)
  "speak."
  (when (ems-interactive-p 'delete-blank-lines)
    (let (thisblank singleblank)
      (save-excursion
        (forward-line 0) (setq thisblank (looking-at "[         ]*$"))
        (setq singleblank
              (and thisblank (not (looking-at "[        ]*\n[   ]*$"))
                   (or (bobp)
                       (progn
                         (forward-line -1) (not (looking-at "[  ]*$")))))))
      (cond
       ((and thisblank singleblank)
        (message "Deleting current blank line"))
       (thisblank (message "Deleting surrounding blank lines"))
       (t (message "Deleting possible subsequent blank lines"))))))

(advice-add
 'delete-blank-lines :before #'emacsvox--advice-delete-blank-lines-before
 '((name . emacsvox)))

;;;  advice tabify:

(defun emacsvox--advice-untabify-after (start end &rest _)
  "Fix NBSP chars."
  (save-excursion
    (save-restriction
      (narrow-to-region start end) (goto-char start)
      (while (re-search-forward (format "[%c]+" 160) end 'no-error)
        (replace-match " ")))))

(advice-add
 'untabify :after #'emacsvox--advice-untabify-after
 '((name . emacsvox)))

;;;  Advice PComplete

(defun emacsvox--advice-pcomplete-list-after (&rest _)
  "Announce an interactive PComplete listing."
  (when (ems-interactive-p 'pcomplete-list)
    (emacsvox-icon 'help) (emacsvox-icon 'complete)))

(advice-add
 'pcomplete-list :after #'emacsvox--advice-pcomplete-list-after
 '((name . emacsvox)))

(defun emacsvox--advice-pcomplete-show-completions-around
    (original &rest arguments)
  "Run ORIGINAL with PComplete messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(advice-add
 'pcomplete-show-completions :around
 #'emacsvox--advice-pcomplete-show-completions-around
 '((name . emacsvox)))

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

(advice-add
 'pcomplete :around #'emacsvox--advice-pcomplete-around
 '((name . emacsvox)))

;;;  Advice hippie expand:

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

(emacsvox-advice--define-completion-around-advice
 (hippie-expand complete)
 emacsvox--expanding-completion-around)

;;;  advice minibuffer to speak

(voice-setup-add-map '((minibuffer-prompt voice-bolden)))

(defun emacsvox--advice-quoted-insert-after (&rest _)
  "Speak the character inserted by interactive `quoted-insert'."
  (when (ems-interactive-p 'quoted-insert)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 'quoted-insert :after #'emacsvox--advice-quoted-insert-after
 '((name . emacsvox)))

(defun emacsvox--advice-read-event-before (&optional prompt &rest _)
  "Speak PROMPT before reading an event."
  (when prompt (tts-notify prompt)))

(advice-add
 'read-event :before #'emacsvox--advice-read-event-before
 '((name . emacsvox)))

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
    (tts-notify prompt)
    (sox-tones 2 2)
    (tts-speak-list spoken-choices)))

(advice-add
 'read-multiple-choice :before
 #'emacsvox--advice-read-multiple-choice-before
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (minibuffer-complete-history
     next-history-element previous-history-element
     next-line-or-history-element previous-line-or-history-element
     previous-matching-history-element next-matching-history-element)
    "Speak the history or completion element just inserted."
  (emacsvox-icon 'select-object)
  (tts-with-punctuations
   'all
   (tts-speak
    (or (minibuffer-contents)
        (emacsvox-get-current-completion)))))

(emacsvox-advice--define-interactive-after-advice
    (minibuffer-next-completion minibuffer-previous-completion
                                minibuffer-next-line-completion
                                minibuffer-previous-line-completion)
    "Speak the newly selected minibuffer completion."
  (tts-with-punctuations
   'all
   (emacsvox-icon 'item)
   (tts-speak (emacsvox-get-current-completion))))

(defvar emacsvox-last-message nil
  "Last output from `message'.")

(defvar ems--lazy-msg-time (current-time)
  "Time message was spoken")

(defcustom emacsvox-speak-messages-filter
  '("Decrypting" "psession"  "auto saving")
  "List of strings used to filter spoken messages."
  :type '(repeat :tag "Filtered Strings"
                 (string :tag "String" ))
  :set
  #'(lambda (sym val)
      (set-default sym val ) ; turn list into a pattern to use
      (setq ems--message-filter (regexp-opt val)))
  :group 'emacsvox-speak)

(defun emacsvox--advice-momentary-string-display-around
    (original &rest arguments)
  "Call ORIGINAL quietly after speaking its string and exit character."
  (let ((string (nth 0 arguments))
        (exit-character (nth 2 arguments)))
    (ems-with-messages-silenced
      (tts-notify
       (format "%s Press %s to exit" string
               (if exit-character
                   (format "%c" exit-character)
                 "space")))
      (apply original arguments))))

(advice-add
 'momentary-string-display :around
 #'emacsvox--advice-momentary-string-display-around
 '((name . emacsvox)))

(defun emacsvox--advice-progress-reporter-do-update-around
    (original &rest arguments)
  "Silence progress reporters."
  (let (result)
    (ems-with-messages-silenced
      (setq result (apply original arguments)))
    (when result (emacsvox-icon 'progress))
    result))

(advice-add
 'progress-reporter-do-update :around
 #'emacsvox--advice-progress-reporter-do-update-around
 '((name . emacsvox)))

(defun emacsvox--advice-progress-reporter-done-after (&rest _)
  "speak." (emacsvox-icon 'time))

(advice-add
 'progress-reporter-done :after
 #'emacsvox--advice-progress-reporter-done-after
 '((name . emacsvox)))

(defun emacsvox--message-around (original arguments)
  "Call ORIGINAL with ARGUMENTS and speak a new, unfiltered message."
  (let ((output nil)
        (overlay minibuffer-message-overlay))
    (let ((result (apply original arguments)))
      (unless (or inhibit-message (null emacsvox-speak-messages))
        (setq output
              (or (current-message)
                  (and overlay
                       (overlay-get overlay 'after-string))))
        (when output
          (setq output (string-trim output)))
        (when
            (and
             output
             (not (zerop (length output)))
             (not (string= output emacsvox-last-message))
             (not (string-match ems--message-filter output)))
          (setq emacsvox-last-message output)
          (emacsvox-icon 'key)
          (tts-with-punctuations 'all
            (tts-notify output 'dont-log))))
      result)))

(defun emacsvox--advice-minibuffer-message-around
    (original &rest arguments)
  "Call ORIGINAL and speak a new minibuffer message."
  (emacsvox--message-around original arguments))

(advice-add
 'minibuffer-message :around
 #'emacsvox--advice-minibuffer-message-around
 '((name . emacsvox)))

(defun emacsvox--advice-set-minibuffer-message-around
    (original &rest arguments)
  "Call ORIGINAL and speak a newly set minibuffer message."
  (emacsvox--message-around original arguments))

(advice-add
 'set-minibuffer-message :around
 #'emacsvox--advice-set-minibuffer-message-around
 '((name . emacsvox)))

(defun emacsvox--advice-message-around (original &rest arguments)
  "Call ORIGINAL and speak a new message."
  (emacsvox--message-around original arguments))

(advice-add
 'message :around #'emacsvox--advice-message-around
 '((name . emacsvox)))

(defun emacsvox--advice-display-message-or-buffer-around
    (original &rest arguments)
  "Call ORIGINAL and speak its message or displayed buffer."
  (let ((result (emacsvox--message-around original arguments)))
    (when (bufferp result)
      (tts-notify
       (format "Displayed message in buffer  %s" (nth 1 arguments))))
    result))

(advice-add
 'display-message-or-buffer :around
 #'emacsvox--advice-display-message-or-buffer-around
 '((name . emacsvox)))

(defvar emacsvox--last-docs nil
  "Last docs considered in `emacsvox-speak-eldoc'.")

(defun emacsvox-speak-eldoc (docs interactive)
  "Speak eldoc.  Intended for `eldoc-display-functions'."
  (with-current-buffer (get-buffer-create " *emacsvox-eldoc*")
    (erase-buffer)
    (insert (mapconcat #'car docs "\n"))
    (unless (equal docs emacsvox--last-docs)
      (emacsvox-icon 'doc))
    (when interactive (tts-notify  (buffer-string))))
  (setq emacsvox--last-docs docs))

(with-eval-after-load "eldoc"
  (add-hook 'eldoc-display-functions #'emacsvox-speak-eldoc)
  (voice-setup-add-map
   '((eldoc-highlight-function-argument voice-bolden))
   'emacsvox-advice))

(defvar ange-ftp-last-percent)

(defun emacsvox--advice-ange-ftp-process-handle-hash-around
    (original &rest arguments)
  "Call ORIGINAL quietly, speak FTP progress, and preserve its result."
  (let (result)
    (ems-with-messages-silenced
      (setq result (apply original arguments))
      (emacsvox-icon 'progress)
      (tts-speak (format " %s percent" ange-ftp-last-percent)))
    result))

(advice-add
 'ange-ftp-process-handle-hash :around
 #'emacsvox--advice-ange-ftp-process-handle-hash-around
 '((name . emacsvox)))

(cl-declaim (special command-error-function))
(setq command-error-function 'emacsvox-error-handler)
(defvar ems--last-error-msg nil
  "Cache last error message.")
(defvar ems--lazy-error-time (current-time)
  "Time error was spoken")

(defun emacsvox--present-command-error (data)
  "Display and present command error DATA as one urgent transaction."
  (let* ((text (error-message-string data))
         (content (propertize text 'face 'error))
         (facts
          (unless (eq (car-safe data) 'quit)
            '(:events (operation-failed)))))
    (setq emacsvox-last-message text)
    (let ((emacsvox-speak-messages nil))
      (message content))
    (condition-case nil
        (let ((tts-speaker-process (tts-notify-process)))
          (emacsvox-aural-submit
           content
           :facts facts
           :module 'core
           :occasion 'notification
           :delivery-policy 'urgent
           :compatibility-actions
           (list (emacsvox-aural-compatibility-icon 'warn-user))))
      (error
       ;; Error reporting must remain usable if native presentation fails.
       (ignore-errors (tts-notify content 'dont-log))))))

(defun emacsvox-error-handler (data _ _)
  "Display and present command error DATA."
  (emacsvox--present-command-error data))
(defconst ems--error-limit 1.0
  "Seconds used to rate-limit error messages.")

(defun emacsvox-fancy-error-handler (data _ caller)
  "Custom error handler."
  (let ((m (error-message-string data))
        (fn (if caller (symbol-name caller) "")))
    (when                               ; speak conditionally
        (and
         (not (string= ems--last-error-msg m)) ; dont repeat
         (< ems--error-limit               ; rate limit 
            (float-time (time-subtract (current-time) ems--lazy-msg-time))))
      (setq ems--last-error-msg m
            ems--lazy-error-time (current-time))
      (emacsvox-icon 'warn-user)
      (message
       (concat
        (propertize
         (if (string-match "^ad-Advice" fn) (substring fn 10) fn)
         'personality voice-bolden)
        m )))))

;; Silence messages from async handlers:

(defun emacsvox--silence-messages-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS while silencing messages."
  (ems-with-messages-silenced
    (apply original arguments)))

(advice-add
 'timer-event-handler :around #'emacsvox--silence-messages-around
 '((name . emacsvox)))

;;;  Advice completion-at-point:

(defun emacsvox--advice-completion-at-point-around
    (original &rest arguments)
  "Speak text completed by an interactive `completion-at-point' call."
  (emacsvox--completion-around
   'completion-at-point "^->_" #'emacsvox--speak-completion-text
   original arguments))

(advice-add
 'completion-at-point :around
 #'emacsvox--advice-completion-at-point-around
 '((name . emacsvox)))

(defun emacsvox--advice-minibuffer-choose-completion-around
    (original &rest arguments)
  "Speak text inserted by interactive minibuffer completion."
  (emacsvox--completion-around
   'minibuffer-choose-completion "^ >_" #'emacsvox--speak-completion-text
   original arguments))

(advice-add
 'minibuffer-choose-completion :around
 #'emacsvox--advice-minibuffer-choose-completion-around
 '((name . emacsvox)))

(defun emacsvox--advice-minibuffer-choose-completion-or-exit-after (&rest _)
  "Announce accepting or exiting minibuffer completion."
  (when (ems-interactive-p 'minibuffer-choose-completion-or-exit)
    (emacsvox-speak-line) (emacsvox-icon 'close-object)))

(advice-add
 'minibuffer-choose-completion-or-exit :after
 #'emacsvox--advice-minibuffer-choose-completion-or-exit-after
 '((name . emacsvox)))

;;;  advice various input functions to speak:

;; read-password--hide-password

(defun emacsvox--advice-read-passwd--hide-password-after (&rest _)
  "Speak the masked or visible password character."
  (tts-notify
   (if read-passwd--password-hidden "dot"
     (if (characterp last-input-event) (format "%c" last-input-event)
       "dot")))
  (emacsvox-icon 'repeat-active))

(advice-add
 'read-passwd--hide-password :after
 #'emacsvox--advice-read-passwd--hide-password-after
 '((name . emacsvox)))

(defun emacsvox--advice-read-passwd-toggle-visibility-after (&rest _)
  "Announce an interactive password visibility change."
  (when (ems-interactive-p 'read-passwd-toggle-visibility)
    (emacsvox-icon (if read-passwd--password-hidden 'off 'on))))

(advice-add
 'read-passwd-toggle-visibility :after
 #'emacsvox--advice-read-passwd-toggle-visibility-after
 '((name . emacsvox)))

(defun emacsvox--advice-read-passwd-before (&optional prompt &rest _)
  "Speak PROMPT before reading a password."
  (emacsvox-icon 'open-object)
  (tts-speak (or prompt "password: "))
  (emacsvox-icon 'pwd))

(advice-add
 'read-passwd :before #'emacsvox--advice-read-passwd-before
 '((name . emacsvox)))

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
                    'all (tts-notify (or prompt "key")))))
               (advice-add
                ',target :before #',function '((name . emacsvox))))))
        targets)))

(emacsvox-advice--define-read-prompt-advice
 (read-key read-key-sequence read-key-sequence-vector
           read-char read-char-exclusive))

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

(advice-add
 'read-char-choice :before #'emacsvox--advice-read-char-choice-before
 '((name . emacsvox)))

;;;  advice completion functions to speak:

(defvar dabbrev--last-expansion)

(emacsvox-advice--define-interactive-after-advice
    (dabbrev-expand dabbrev-completion)
    "Speak the expanded dabbrev text."
  (accept-process-output)
  (tts-with-punctuations 'all (tts-speak dabbrev--last-expansion)))

(voice-setup-add-map
 '(
   (completions-annotations voice-annotate)
   (completions-common-part voice-monotone-extra)
   (completions-first-difference voice-bolden)))

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

(emacsvox-advice--define-completion-around-advice
 (minibuffer-complete-word minibuffer-complete
                           crm-complete-word crm-complete
                           crm-complete-and-exit
                           crm-minibuffer-complete
                           crm-minibuffer-complete-and-exit)
 emacsvox--minibuffer-completion-around)

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

(emacsvox-advice--define-completion-around-advice
 (lisp-complete-symbol complete-symbol widget-complete)
 emacsvox--symbol-completion-around)

(define-key minibuffer-local-completion-map "\C-o" 'switch-to-completions)

(defun emacsvox--advice-switch-to-completions-after (&rest _)
  "Speak the first completion after switching to the completions buffer."
  (emacsvox-icon 'select-object)
  (tts-speak (emacsvox-get-current-completion)))

(advice-add
 'switch-to-completions :after
 #'emacsvox--advice-switch-to-completions-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (next-line-completion previous-line-completion
                          next-completion previous-completion)
    "Speak the newly selected completion."
  (emacsvox-icon 'select-object)
  (tts-with-punctuations
   'all (tts-speak (emacsvox-get-current-completion))))

(defun emacsvox--advice-choose-completion-before (&rest _)
  "Cue an interactive completion choice."
  (when (ems-interactive-p 'choose-completion)
    (emacsvox-icon 'button)))

(advice-add
 'choose-completion :before #'emacsvox--advice-choose-completion-before
 '((name . emacsvox)))

;;;  tmm support

(defun emacsvox--advice-tmm-goto-completions-after (&rest _)
  "Announce an interactive TMM completion."
  (when (ems-interactive-p 'tmm-goto-completions)
    (emacsvox-icon 'help)
    (tts-speak (emacsvox-get-current-completion))))

(advice-add
 'tmm-goto-completions :after
 #'emacsvox--advice-tmm-goto-completions-after
 '((name . emacsvox)))

(defun emacsvox--advice-tmm-menubar-before (&rest _)
  "Cue opening the text-mode menu bar interactively."
  (when (ems-interactive-p 'tmm-menubar)
    (emacsvox-icon 'open-object)))

(advice-add
 'tmm-menubar :before #'emacsvox--advice-tmm-menubar-before
 '((name . emacsvox)))

(defun emacsvox--advice-tmm-shortcut-after (&rest _)
  "Cue a TMM shortcut."
  (emacsvox-icon 'button))

(advice-add
 'tmm-shortcut :after #'emacsvox--advice-tmm-shortcut-after
 '((name . emacsvox)))

;;;  Advice centering and filling commands:

(defun emacsvox--advice-center-line-after (&optional _count)
  "Announce completion of interactive line centering."
  (when (ems-interactive-p 'center-line)
    (emacsvox-icon 'center)
    (message "Centered current line")))

(advice-add
 'center-line :after #'emacsvox--advice-center-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-center-region-after (beginning end)
  "Announce centering the region from BEGINNING to END."
  (when (ems-interactive-p 'center-region)
    (emacsvox-icon 'center)
    (message "Centered current region containing %s lines"
             (count-lines beginning end))))

(advice-add
 'center-region :after #'emacsvox--advice-center-region-after
 '((name . emacsvox)))

(defun emacsvox--advice-center-paragraph-after ()
  "Announce completion of interactive paragraph centering."
  (when (ems-interactive-p 'center-paragraph)
    (emacsvox-icon 'center)
    (message "Centered current paragraph")))

(advice-add
 'center-paragraph :after #'emacsvox--advice-center-paragraph-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (fill-paragraph lisp-fill-paragraph)
    "Announce completion of interactive paragraph filling."
  (emacsvox-icon 'fill-object)
  (message "Filled current paragraph"))

(defun emacsvox--advice-fill-region-after (beginning end &rest _)
  "Announce filling the region from BEGINNING to END."
  (when (ems-interactive-p 'fill-region)
    (emacsvox-icon 'fill-object)
    (message "Filled current region containing %s lines"
             (count-lines beginning end))))

(advice-add
 'fill-region :after #'emacsvox--advice-fill-region-after
 '((name . emacsvox)))

;;;  vc:

(voice-setup-add-map
 '(
   (log-edit-header voice-bolden)
   (log-edit-summary voice-lighten)
   (log-edit-unknown-header voice-monotone-extra)))

;; helper function: find out vc version:

;; guess the vc version number from the variable used in minor mode alist
(defvar vc-mode)

(defun emacsvox-vc-get-version-id ()
  "Return VC version id."
  
  (let ((id vc-mode))
    (cond
     ((and vc-mode
           (stringp vc-mode))
      (substring id 5 nil))
     (t " "))))

(defun emacsvox--vc-action-around
    (target read-only-icon writable-icon original arguments)
  "Call ORIGINAL once and announce an interactive VC action.
TARGET identifies the advised command.  READ-ONLY-ICON and WRITABLE-ICON
select feedback from the buffer state before the action.  ARGUMENTS are passed
to ORIGINAL unchanged."
  (if (ems-interactive-p target)
      (let ((announcement
             (format "Checking %s version %s "
                     (if buffer-read-only "out previous " " in new ")
                     (emacsvox-vc-get-version-id))))
        (emacsvox-icon
         (if buffer-read-only read-only-icon writable-icon))
        (let ((result (apply original arguments)))
          (message announcement)
          result))
    (apply original arguments)))

(defun emacsvox--advice-vc-toggle-read-only-around
    (original &rest arguments)
  "Call ORIGINAL once and announce an interactive VC read-only toggle."
  (emacsvox--vc-action-around
   'vc-toggle-read-only 'open-object 'close-object original arguments))

(advice-add
 'vc-toggle-read-only :around
 #'emacsvox--advice-vc-toggle-read-only-around
 '((name . emacsvox)))

(defun emacsvox--advice-vc-refresh-state-around
    (original &rest arguments)
  "Call ORIGINAL with VC refresh messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(advice-add
 'vc-refresh-state :around
 #'emacsvox--advice-vc-refresh-state-around
 '((name . emacsvox)))

(defun emacsvox--advice-vc-next-action-around
    (original &rest arguments)
  "Call ORIGINAL once and announce an interactive next VC action."
  (emacsvox--vc-action-around
   'vc-next-action 'close-object 'open-object original arguments))

(advice-add
 'vc-next-action :around #'emacsvox--advice-vc-next-action-around
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (vc-revert-buffer)
    "Cue completion of an interactive VC buffer revert."
  (emacsvox-icon 'open-object))

(emacsvox-advice--define-interactive-after-advice
    (vc-finish-logentry)
    "Announce completion of an interactive VC log entry."
  (emacsvox-icon 'close-object)
  (message "Checked in version %s " (emacsvox-vc-get-version-id)))

(emacsvox-advice--define-interactive-after-advice
    (vc-dir-next-line vc-dir-previous-line
     vc-dir-next-directory vc-dir-previous-directory)
    "Speak the destination of an interactive VC directory movement."
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(emacsvox-advice--define-interactive-after-advice
    (vc-dir-mark-file vc-dir-mark)
    "Announce an interactive VC directory mark."
  (emacsvox-speak-line)
  (emacsvox-icon 'mark-object))

(emacsvox-advice--define-interactive-after-advice
    (vc-dir)
    "Announce an interactively opened VC directory."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (vc-dir-hide-up-to-date)
    "Announce an interactive VC directory filter change."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (vc-dir-kill-line)
    "Announce deletion of an interactive VC directory entry."
  (emacsvox-icon 'delete-object)
  (emacsvox-speak-line))

;;;  composing mail

(defun emacsvox--mail-compose-after (&rest _)
  "Give auditory feedback after opening a mail composition buffer."
  (emacsvox-icon 'open-object)
  (save-excursion
    (goto-char (point-min))
    (emacsvox-speak-line)))

(dolist (command '(mail mail-other-window mail-other-frame))
  (advice-add
   command :after #'emacsvox--mail-compose-after '((name . emacsvox))))

(emacsvox-advice--define-interactive-after-advice
    (mail-text mail-subject mail-cc mail-bcc
     mail-to mail-reply-to mail-fcc)
    "Speak the current mail header field."
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (mail-signature)
    "Announce insertion of a mail signature."
  (message "Signed your message"))

(emacsvox-advice--define-interactive-after-advice
    (mail-send-and-exit)
    "Cue sending mail and speak the resulting mode line."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

;;;  misc functions that have to be hand fixed:

(emacsvox-advice--define-interactive-after-advice
    (zap-to-char)
    "Cue deletion and speak the remaining line."
  (emacsvox-icon 'delete-object)
  (emacsvox-speak-line 1))

(emacsvox-advice--define-interactive-after-advice
    (describe-mode)
    "Announce display of mode help."
  (message "Displayed mode help")
  (emacsvox-icon 'help))

(emacsvox-advice--define-interactive-after-advice
    (describe-repeat-maps)
    "Announce display of repeat-mode help."
  (message "Displayed  repeat-mode  help")
  (emacsvox-icon 'help))

(emacsvox-advice--define-interactive-after-advice
    (describe-bindings describe-prefix-bindings isearch-describe-bindings)
    "Announce display of key bindings."
  (message "Displayed key bindings in help window")
  (emacsvox-icon 'help))

(emacsvox-advice--define-interactive-after-advice
    (line-number-mode column-number-mode)
    "Cue a position indicator toggle and speak the resulting mode line."
  (emacsvox-icon 'button)
  (emacsvox-speak-mode-line))

(defun emacsvox--advice-not-modified-after (&optional argument)
  "Provide an auditory icon."
  (when (ems-interactive-p 'not-modified)
    (if argument (emacsvox-icon 'modified-object)
      (emacsvox-icon 'unmodified-object))))

(advice-add
 'not-modified :after #'emacsvox--advice-not-modified-after
 '((name . emacsvox)))

(defun emacsvox--advice-comment-dwim-after (&rest _)
  "Speak the affected text after an interactive comment command."
  (when (ems-interactive-p 'comment-dwim)
    (cond
     ((use-region-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))
    (emacsvox-icon 'task-done)))

(advice-add
 'comment-dwim :after #'emacsvox--advice-comment-dwim-after
 '((name . emacsvox)))

(defun emacsvox--advice-comment-region-after
    (beginning end &optional argument)
  "Announce an interactive comment operation on BEGINNING through END.
ARGUMENT is the optional prefix argument accepted by `comment-region'."
  (when (ems-interactive-p 'comment-region)
    (message
     "%s region containing %s lines"
     (if (or (consp argument)
             (and (numberp argument) (< argument 0)))
         "Uncommented"
       "Commented")
     (count-lines beginning end))))

(advice-add
 'comment-region :after #'emacsvox--advice-comment-region-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (save-buffer save-some-buffers)
    "Indicate completion of an interactive save."
  (emacsvox-icon 'save-object))

(defun emacsvox--region-deletion-around
    (target original beginning end arguments)
  "Call ORIGINAL and announce an interactive region deletion.
TARGET identifies the advised command.  BEGINNING and END are the affected
range, and ARGUMENTS contains any remaining arguments for ORIGINAL."
  (if (ems-interactive-p target)
      (let ((count (count-lines beginning end))
            (result (apply original beginning end arguments)))
        (emacsvox-icon 'delete-object)
        (message "Killed region containing %s lines" count)
        result)
    (apply original beginning end arguments)))

(defun emacsvox--advice-delete-region-around
    (original beginning end)
  "Call ORIGINAL and announce interactive deletion from BEGINNING to END."
  (emacsvox--region-deletion-around
   'delete-region original beginning end nil))

(advice-add
 'delete-region :around #'emacsvox--advice-delete-region-around
 '((name . emacsvox)))

(defun emacsvox--advice-kill-region-around
    (original beginning end &rest arguments)
  "Call ORIGINAL and announce an interactive kill from BEGINNING to END."
  (emacsvox--region-deletion-around
   'kill-region original beginning end arguments))

(advice-add
 'kill-region :around #'emacsvox--advice-kill-region-around
 '((name . emacsvox)))

(defun emacsvox--advice-completion-kill-region-around
    (original beginning end &rest arguments)
  "Call ORIGINAL and announce an interactive completion-region kill.
BEGINNING, END, and ARGUMENTS are passed to ORIGINAL unchanged."
  (emacsvox--region-deletion-around
   'completion-kill-region original beginning end arguments))

(advice-add
 'completion-kill-region :around
 #'emacsvox--advice-completion-kill-region-around
 '((name . emacsvox)))

(defun emacsvox--advice-kill-ring-save-after (&rest _)
  "Indicate that region has been copied to the kill ring.\nProduce an auditory icon if possible."
  (when (ems-interactive-p 'kill-ring-save)
    (emacsvox-icon 'mark-object)
    (message "region containing %s lines copied to kill ring "
             (count-lines (region-beginning) (region-end)))))

(advice-add
 'kill-ring-save :after #'emacsvox--advice-kill-ring-save-after
 '((name . emacsvox)))

(defun emacsvox--advice-find-file-after (&rest _)
  "Play an auditory icon if possible."
  (when (ems-interactive-p 'find-file)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add
 'find-file :after #'emacsvox--advice-find-file-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (kill-buffer kill-current-buffer quit-window)
    "Announce closing a buffer or window."
  (emacsvox-icon 'close-object)
  (tts-stop 'all)
  (emacsvox-speak-mode-line))

(emacsvox-advice--define-interactive-after-advice
    (delete-windows-on delete-other-frames delete-completion-window
                       split-window-below split-window-right)
    "Announce a change to the window configuration."
  (emacsvox-icon 'window-resize)
  (emacsvox-speak-mode-line))

(emacsvox-advice--define-interactive-after-advice
    (other-frame other-window
                 next-window-any-frame previous-window-any-frame
                 switch-to-prev-buffer switch-to-next-buffer
                 switch-to-buffer switch-to-buffer-other-window bury-buffer
                 next-buffer previous-buffer
                 switch-to-buffer-other-frame)
    "Announce a change of selected buffer, window, or frame."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(defun emacsvox--advice-pop-to-buffer-after (&rest _)
  "Announce an interactive buffer pop."
  (when (ems-interactive-p 'pop-to-buffer)
    (emacsvox-icon 'tick-tick) (emacsvox-speak-mode-line)))

(advice-add
 'pop-to-buffer :after #'emacsvox--advice-pop-to-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-scratch-buffer-after (&rest _)
  "Announce switching to the scratch buffer."
  (when (ems-interactive-p 'scratch-buffer)
    (emacsvox-icon 'tick-tick) (emacsvox-speak-mode-line)))

(advice-add
 'scratch-buffer :after #'emacsvox--advice-scratch-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-display-buffer-after (buffer-or-name &rest _)
  "Announce interactively displaying BUFFER-OR-NAME."
  (when (ems-interactive-p 'display-buffer)
    (emacsvox-icon 'open-object)
    (message "Displayed %s"
             (if (bufferp buffer-or-name)
                 (buffer-name buffer-or-name)
               buffer-or-name))))

(advice-add
 'display-buffer :after #'emacsvox--advice-display-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-make-frame-command-after (&rest _)
  "Announce interactively creating a frame."
  (when (ems-interactive-p 'make-frame-command)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add
 'make-frame-command :after #'emacsvox--advice-make-frame-command-after
 '((name . emacsvox)))

(defun emacsvox--advice-move-to-window-line-after (&rest _)
  "Speak after interactively moving within a window."
  (when (ems-interactive-p 'move-to-window-line)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add
 'move-to-window-line :after #'emacsvox--advice-move-to-window-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-rename-buffer-after (&rest _)
  "Speak the mode line after interactively renaming a buffer."
  (when (ems-interactive-p 'rename-buffer)
    (emacsvox-speak-mode-line)))

(advice-add
 'rename-buffer :after #'emacsvox--advice-rename-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-rename-uniquely-after (&rest _)
  "Speak the mode line after interactively making a buffer name unique."
  (when (ems-interactive-p 'rename-uniquely)
    (emacsvox-speak-mode-line)))

(advice-add
 'rename-uniquely :after #'emacsvox--advice-rename-uniquely-after
 '((name . emacsvox)))

(defun emacsvox--advice-local-set-key-before (&rest _)
  "Prompt using speech."
  (interactive
   (list (read-key-sequence "Locally bind key:")
         (read-command "To command:"))))

(advice-add
 'local-set-key :before #'emacsvox--advice-local-set-key-before
 '((name . emacsvox)))

(defun emacsvox--advice-global-set-key-before (&rest _)
  "Provide spoken prompts."
  (interactive
   (list (read-key-sequence "Globally bind key:")
         (read-command "To command:"))))

(advice-add
 'global-set-key :before #'emacsvox--advice-global-set-key-before
 '((name . emacsvox)))

(defun emacsvox--advice-modify-syntax-entry-before (&rest _)
  "Provide spoken prompts."
  (interactive
   (list (read-char "Modify syntax for: ")
         (read-string "Syntax Entry: ") current-prefix-arg)))

(advice-add
 'modify-syntax-entry :before
 #'emacsvox--advice-modify-syntax-entry-before
 '((name . emacsvox)))

(defun emacsvox--advice-help-do-xref-after (&rest _)
  "Speak the Help reference just selected."
  (emacsvox-speak-line)
  (emacsvox-icon 'item))

(advice-add
 'help-do-xref :after #'emacsvox--advice-help-do-xref-after
 '((name . emacsvox)))

(defun emacsvox--advice-help-xref-go-back-after (&rest _)
  "Speak the Help reference reached by moving backward."
  (emacsvox-speak-line))

(advice-add
 'help-xref-go-back :after
 #'emacsvox--advice-help-xref-go-back-after
 '((name . emacsvox)))

(defun emacsvox--advice-help-xref-go-forward-after (&rest _)
  "Speak the Help reference reached by moving forward."
  (emacsvox-speak-line))

(advice-add
 'help-xref-go-forward :after
 #'emacsvox--advice-help-xref-go-forward-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (help-view-source)
    "Announce viewing source from Help."
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(emacsvox-advice--define-interactive-after-advice
    (help-customize)
    "Announce opening Customize from Help."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

;; Silence help for help

(defun emacsvox--advice-help-window-display-message-around
    (original &rest arguments)
  "Call ORIGINAL with Help window messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(advice-add
 'help-window-display-message :around
 #'emacsvox--advice-help-window-display-message-around
 '((name . emacsvox)))

(defun emacsvox--describe-key-filter-return (target result)
  "Announce interactive key help and return RESULT unchanged.
TARGET identifies the key-description command."
  (when (ems-interactive-p target)
    (emacsvox-icon 'help)
    (unless result
      (emacsvox-speak-help)))
  result)

(defun emacsvox--advice-describe-key-filter-return (result)
  "Announce interactive `describe-key' help and return RESULT."
  (emacsvox--describe-key-filter-return 'describe-key result))

(advice-add
 'describe-key :filter-return
 #'emacsvox--advice-describe-key-filter-return
 '((name . emacsvox)))

(defun emacsvox--advice-describe-keymap-filter-return (result)
  "Announce interactive `describe-keymap' help and return RESULT."
  (emacsvox--describe-key-filter-return 'describe-keymap result))

(advice-add
 'describe-keymap :filter-return
 #'emacsvox--advice-describe-keymap-filter-return
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (describe-function describe-variable describe-symbol
     describe-face describe-font
     describe-text-properties describe-syntax
     describe-package
     describe-char describe-char-after describe-character-set
     describe-chars-in-region
     describe-coding-system describe-current-coding-system
     describe-current-coding-system-briefly
     describe-current-display-table describe-fontset
     describe-help-keys describe-input-method
     describe-language-environment
     describe-minor-mode describe-minor-mode-from-indicator
     describe-minor-mode-from-symbol
     describe-personal-keybindings describe-theme)
    "Speak help produced by an interactive description command."
  (emacsvox-icon 'help)
  (emacsvox-speak-help))

(emacsvox-advice--define-interactive-after-advice
    (help-with-tutorial)
    "Speak the tutorial window."
  (tts-set-punctuations 'all)
  (emacsvox-icon 'open-object)
  (emacsvox-speak-predefined-window 1))

(emacsvox-advice--define-interactive-after-advice
    (exchange-point-and-mark)
    "Cue a large movement and speak the line with point highlighted."
  (emacsvox-icon 'large-movement)
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(emacsvox-advice--define-interactive-after-advice
    (newline newline-and-indent electric-newline-and-maybe-indent)
    "Speak the previous line if line echo is on.
See command \\[emacsvox-toggle-line-echo]. Otherwise cue the user to
the newly created  line."
  (if emacsvox-line-echo
      (emacsvox-read-previous-line)
    (emacsvox-speak-edit-operation 'line-created)))

(defun emacsvox--eval-filter-return (target result)
  "Speak an interactive evaluation RESULT and return it unchanged.
TARGET identifies the evaluation command."
  (when (ems-interactive-p target)
    (let ((tts-chunk-separator-syntax " .<>()$\"'"))
      (tts-with-punctuations 'all
        (tts-speak (format "%s" result)))))
  result)

(defun emacsvox--advice-eval-last-sexp-filter-return (result)
  "Speak an interactive `eval-last-sexp' RESULT and return it."
  (emacsvox--eval-filter-return 'eval-last-sexp result))

(advice-add
 'eval-last-sexp :filter-return
 #'emacsvox--advice-eval-last-sexp-filter-return
 '((name . emacsvox)))

(defun emacsvox--advice-eval-expression-filter-return (result)
  "Speak an interactive `eval-expression' RESULT and return it."
  (emacsvox--eval-filter-return 'eval-expression result))

(advice-add
 'eval-expression :filter-return
 #'emacsvox--advice-eval-expression-filter-return
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (shell)
    "Cue an interactive shell and speak its mode line."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-advice--define-interactive-after-advice
    (find-tag pop-tag-mark tags-loop-continue)
    "Announce the destination of an interactive tag navigation command."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(defun emacsvox--advice-call-last-kbd-macro-around
    (original &rest arguments)
  "Call ORIGINAL once and announce an interactive keyboard macro."
  (if (ems-interactive-p 'call-last-kbd-macro)
      (let (result)
        (ems-with-messages-silenced
          (let ((tts-quiet t)
                (emacsvox-use-icons nil))
            (setq result (apply original arguments))))
        (message "Executed macro. ")
        (emacsvox-icon 'task-done)
        result)
    (apply original arguments)))

(advice-add
 'call-last-kbd-macro :around
 #'emacsvox--advice-call-last-kbd-macro-around
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (kbd-macro-query)
    "Announce that a keyboard macro will prompt at this point."
  (message "Will prompt at this point in macro"))

(emacsvox-advice--define-interactive-before-advice
    (start-kbd-macro)
    "Announce the start of keyboard macro definition."
  (emacsvox-icon 'open-object)
  (tts-speak "Started defining a keyboard macro "))

(emacsvox-advice--define-interactive-after-advice
    (end-kbd-macro)
    "Announce the end of keyboard macro definition."
  (emacsvox-icon 'close-object)
  (tts-speak "Finished defining keyboard macro "))

;; you DONT WANT TO SUSPEND EMACS WITHOUT CONFIRMATION

(defun emacsvox--advice-suspend-emacs-around (original &rest arguments)
  "Ask for confirmation."
  (let ((confirmation (yes-or-no-p "Do you want to suspend emacs ")))
    (cond
     (confirmation
      (message "Suspending Emacs ")
      (apply original arguments))
     (t (message "Not suspending emacs")))))

(advice-add
 'suspend-emacs :around #'emacsvox--advice-suspend-emacs-around
 '((name . emacsvox)))

(defun emacsvox--case-region-after (target action beginning end)
  "Announce an interactive case conversion from BEGINNING to END.
TARGET identifies the case command, and ACTION describes its result."
  (when (ems-interactive-p target)
    (message "%s region containing %s lines"
             action (count-lines beginning end))))

(defun emacsvox--advice-downcase-region-after
    (beginning end &optional _region-noncontiguous-p)
  "Announce an interactive downcase from BEGINNING to END."
  (emacsvox--case-region-after
   'downcase-region "Downcased" beginning end))

(advice-add
 'downcase-region :after #'emacsvox--advice-downcase-region-after
 '((name . emacsvox)))

(defun emacsvox--advice-upcase-region-after
    (beginning end &optional _region-noncontiguous-p)
  "Announce an interactive upcase from BEGINNING to END."
  (emacsvox--case-region-after
   'upcase-region "Upcased" beginning end))

(advice-add
 'upcase-region :after #'emacsvox--advice-upcase-region-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (narrow-to-region narrow-to-page)
    "Announce the size of the resulting accessible buffer restriction."
  (emacsvox-icon 'mark-object)
  (message "Narrowed editing region to %s lines"
           (count-lines (point-min) (point-max))))

(declare-function which-function "which-func" nil)

(defun emacsvox--advice-narrow-to-defun-after (&rest _)
  "Announce the function selected by interactive narrowing."
  (when (ems-interactive-p 'narrow-to-defun)
    (require 'which-func)
    (emacsvox-icon 'mark-object)
    (message "Narrowed to function %s" (which-function))))

(advice-add
 'narrow-to-defun :after #'emacsvox--advice-narrow-to-defun-after
 '((name . emacsvox)))

(defun emacsvox--advice-widen-after ()
  "Announce restoration of the complete buffer restriction."
  (when (ems-interactive-p 'widen)
    (emacsvox-icon 'open-object)
    (message "You can now edit the entire buffer ")))

(advice-add
 'widen :after #'emacsvox--advice-widen-after
 '((name . emacsvox)))

(defun emacsvox--advice-delete-other-windows-after (&rest _)
  "Announce interactively deleting all other windows."
  (when (ems-interactive-p 'delete-other-windows)
    (message "Deleted all other windows")
    (emacsvox-icon 'window-resize) (emacsvox-speak-mode-line)))

(advice-add
 'delete-other-windows :after #'emacsvox--advice-delete-other-windows-after
 '((name . emacsvox)))

(defun emacsvox--advice-split-window-vertically-after (&rest _)
  "Announce an interactive vertical window split."
  (when (ems-interactive-p 'split-window-vertically)
    (message "Split window vertically, current window has %s lines "
             (window-height))
    (emacsvox-speak-mode-line)))

(advice-add
 'split-window-vertically :after
 #'emacsvox--advice-split-window-vertically-after
 '((name . emacsvox)))

(defun emacsvox--advice-delete-window-after (&rest _)
  "Announce interactively deleting the selected window."
  (when (ems-interactive-p 'delete-window)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add
 'delete-window :after #'emacsvox--advice-delete-window-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (shrink-window shrink-window-if-larger-than-buffer balance-windows)
    "Announce the current window dimensions."
  (message "Current window has %s lines and %s columns"
           (window-height) (window-width)))

(defun emacsvox--advice-split-window-horizontally-after (&rest _)
  "Announce an interactive horizontal window split."
  (when (ems-interactive-p 'split-window-horizontally)
    (message
     "Split window horizontally current window has %s columns "
     (window-width))
    (emacsvox-speak-mode-line)))

(advice-add
 'split-window-horizontally :after
 #'emacsvox--advice-split-window-horizontally-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (transpose-chars)
    "Cue a character transpose and speak the resulting character."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-char t))

(emacsvox-advice--define-interactive-after-advice
    (transpose-lines)
    "Cue a line transpose and speak the resulting line."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (transpose-words)
    "Cue a word transpose and speak the resulting word."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-word))

(emacsvox-advice--define-interactive-after-advice
    (transpose-sexps)
    "Cue a sexp transpose and speak the resulting expression."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-sexp))

(defun emacsvox--advice-open-line-after (count)
  "Announce COUNT lines opened by an interactive `open-line'."
  (when (ems-interactive-p 'open-line)
    (emacsvox-icon 'open-object)
    (message "Opened %s blank line%s"
             (if (= count 1) "a" count)
             (if (= count 1) "" "s"))))

(advice-add
 'open-line :after #'emacsvox--advice-open-line-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (abort-recursive-edit)
    "Announce an aborted recursive edit."
  (message "Aborting recursive edit"))

(emacsvox-advice--define-interactive-after-advice
    (undo undo-redo undo-only)
    "Speak the result and modified state of an interactive undo command."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line))
  (if (buffer-modified-p)
      (emacsvox-icon 'modified-object)
    (emacsvox-icon 'unmodified-object)))

(emacsvox-advice--define-interactive-after-advice
    (view-emacs-news)
    "Cue and speak the mode line after displaying Emacs news."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defvar emacsvox--help-char-helpbuf " *Char Help*"
  "This is hard-coded in subr.el")

(defun emacsvox--advice-help-form-show-after (&rest _)
  "Speak displayed help form."
  (when (buffer-live-p (get-buffer emacsvox--help-char-helpbuf))
    (with-current-buffer emacsvox--help-char-helpbuf
      (goto-char (point-min))
      (emacsvox-speak-buffer))))

(advice-add
 'help-form-show :after #'emacsvox--advice-help-form-show-after
 '((name . emacsvox)))

(defcustom emacsvox-speak-tooltips nil
  "Enable to get tooltips spoken."
  :type 'boolean
  :group 'emacsvox)

(defun emacsvox--tooltip-show-around
    (original help &rest arguments)
  "Call ORIGINAL quietly, then optionally speak HELP.
ARGUMENTS are the remaining arguments passed to ORIGINAL."
  (let (result)
    (ems-with-messages-silenced
      (setq result (apply original help arguments)))
    (when (and emacsvox-speak-tooltips help)
      (tts-speak help))
    result))

(defun emacsvox--advice-tooltip-show-help-around
    (original help &rest arguments)
  "Call `tooltip-show-help' quietly and optionally speak HELP."
  (apply
   #'emacsvox--tooltip-show-around original help arguments))

(advice-add
 'tooltip-show-help :around
 #'emacsvox--advice-tooltip-show-help-around
 '((name . emacsvox)))

(defun emacsvox--advice-tooltip-show-help-non-mode-around
    (original help &rest arguments)
  "Call `tooltip-show-help-non-mode' quietly and optionally speak HELP."
  (apply
   #'emacsvox--tooltip-show-around original help arguments))

(advice-add
 'tooltip-show-help-non-mode :around
 #'emacsvox--advice-tooltip-show-help-non-mode-around
 '((name . emacsvox-tooltip-around)))

(defun emacsvox--tooltip-show-after (help)
  "Speak HELP and play its icon when tooltip speech is enabled."
  (when emacsvox-speak-tooltips
    (tts-speak help)
    (emacsvox-icon 'help)))

(defun emacsvox--advice-tooltip-show-help-non-mode-after
    (help &rest _)
  "Speak HELP after `tooltip-show-help-non-mode'."
  (emacsvox--tooltip-show-after help))

(advice-add
 'tooltip-show-help-non-mode :after
 #'emacsvox--advice-tooltip-show-help-non-mode-after
 '((name . emacsvox-tooltip-after)))

(defun emacsvox--advice-tooltip-sho-after (help &rest _)
  "Speak HELP after the legacy `tooltip-sho' entry point."
  (emacsvox--tooltip-show-after help))

(advice-add
 'tooltip-sho :after #'emacsvox--advice-tooltip-sho-after
 '((name . emacsvox)))

;;;  Emacs server
(defun emacsvox-speak-announce-server-buffer ()
  "Announce opening of an emacsclient buffer."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))
(add-hook 'server-done-hook
          #'(lambda nil
              (emacsvox-icon 'close-object)))

(add-hook 'server-switch-hook 'emacsvox-speak-announce-server-buffer)

(emacsvox-advice--define-interactive-after-advice
    (server-start)
    "Cue completion of an interactive Emacs server start."
  (emacsvox-icon 'task-done))

(emacsvox-advice--define-interactive-after-advice
    (server-edit)
    "Speak the mode line after interactively finishing a server edit."
  (emacsvox-speak-mode-line))

;;;  view echo area

(emacsvox-advice--define-interactive-after-advice
    (view-echo-area-messages)
    "Cue the Messages buffer displayed in another window."
  (emacsvox-icon 'open-object)
  (message "Displayed messages in other window."))

;;;  selective display

(defun emacsvox--advice-set-selective-display-after (argument)
  "Announce selective display set to ARGUMENT interactively."
  (when (ems-interactive-p 'set-selective-display)
    (message "Set selective display to %s" argument)
    (emacsvox-icon 'button)))

(advice-add
 'set-selective-display :after
 #'emacsvox--advice-set-selective-display-after
 '((name . emacsvox)))

;;;  avoid chatter when byte compiling etc

(defun emacsvox--advice-byte-compile-file-around
    (original &rest arguments)
  "Call ORIGINAL once and announce interactive byte compilation."
  (if (ems-interactive-p 'byte-compile-file)
      (let (result)
        (ems-with-messages-silenced
          (tts-speak "Byte compiling ")
          (setq result (apply original arguments))
          (emacsvox-icon 'task-done)
          (tts-speak "Done byte compiling "))
        result)
    (apply original arguments)))

(advice-add
 'byte-compile-file :around #'emacsvox--advice-byte-compile-file-around
 '((name . emacsvox)))

;;;  Stop talking if activity

(emacsvox-advice--define-interactive-before-advice
    (recenter-top-bottom recenter)
    "Speak the current line before interactive recentering."
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (beginning-of-line move-beginning-of-line)
    "Speak after moving interactively to the beginning of a line."
  (emacsvox-speak-line)
  (emacsvox-icon 'left))

(emacsvox-advice--define-interactive-after-advice
    (end-of-line move-end-of-line)
    "Speak the column after moving interactively to the end of a line."
  (emacsvox-speak-current-column)
  (emacsvox-icon 'right))

;;;  yanking and popping

(emacsvox-advice--define-interactive-after-advice
    (yank yank-pop)
    "Speak the text inserted by an interactive yank command."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-region (mark 'force) (point)))

;;;  advice non-incremental searchers

(emacsvox-advice--define-interactive-after-advice
    (search-forward search-backward
                    word-search-forward word-search-backward)
    "Speak the line reached by an interactive search."
  (emacsvox-speak-line)
  (emacsvox-icon 'search-hit))

;;;  customize isearch:

;; Fix key bindings:

(defvar isearch-mode-map)
(defvar minibuffer-local-isearch-map)
(defvar emacsvox-prefix)

(define-key minibuffer-local-isearch-map
            emacsvox-prefix 'emacsvox-keymap)
(define-key isearch-mode-map emacsvox-prefix 'emacsvox-keymap)
(define-key isearch-mode-map "\M-y" 'isearch-yank-pop)
;; face navigators
(define-key isearch-mode-map (kbd "M-C-b") 'emacsvox-speak-face-backward )
(define-key isearch-mode-map (kbd "M-C-f") 'emacsvox-speak-face-forward )
;; ISearch setup/teardown

;; Produce auditory icon
(defun emacsvox-isearch-setup ()
  "Setup emacsvox isearch."
  (emacsvox-icon 'open-object)
  (setq emacsvox-speak-messages isearch-lazy-count)
  (tts-speak (isearch-message-prefix)))

(defun emacsvox-isearch-teardown ()
  "Teardown emacsvox isearch."
  (setq emacsvox-speak-messages t)
  (emacsvox-icon 'close-object))

(add-hook 'isearch-mode-hook 'emacsvox-isearch-setup)
(add-hook 'isearch-mode-end-hook 'emacsvox-isearch-teardown)
(add-hook 'isearch-mode-end-hook-quit 'emacsvox-isearch-teardown)

;; Advice isearch-search to speak

(defun emacsvox--advice-isearch-search-after (&rest _)
  "Speak the hit."
  (cond ((null isearch-success) (emacsvox-icon 'search-miss))
        (t (emacsvox-icon 'search-hit)
           (when (sit-for 0.1)
             (save-excursion
               (ems-set-personality-temporarily (point)
                                                isearch-other-end
                                                voice-bolden
                                                (tts-speak
                                                 (buffer-substring
                                                  (line-beginning-position)
                                                  (line-end-position)))))))))

(advice-add
 'isearch-search :after #'emacsvox--advice-isearch-search-after
 '((name . emacsvox)))

(defun emacsvox--advice-isearch-delete-char-after (&rest _)
  "Speak the shortened isearch string and current hit."
  (tts-speak (propertize isearch-string 'personality voice-bolden))
  (when (sit-for 0.1)
    (emacsvox-icon 'search-hit)
    (ems-set-personality-temporarily (point)
                                     (if isearch-forward
                                         (- (point)
                                            (length isearch-string))
                                       (+ (point)
                                          (length isearch-string)))
                                     voice-bolden
                                     (emacsvox-speak-line))))

(advice-add
 'isearch-delete-char :after #'emacsvox--advice-isearch-delete-char-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (isearch-yank-word isearch-yank-kill isearch-yank-line)
    "Speak text yanked into an incremental search."
  (tts-speak (propertize isearch-string 'personality voice-bolden))
  (emacsvox-icon 'yank-object))

(emacsvox-advice--define-interactive-after-advice
    (isearch-ring-advance isearch-ring-retreat
                          isearch-ring-advance-edit isearch-ring-retreat-edit)
    "Speak the incremental search ring item."
  (tts-speak (propertize isearch-string 'personality voice-bolden))
  (emacsvox-icon 'item))

;; Note the advice on the next two toggle commands
;; checks the variable being toggled.
;; When our advice is called, emacs has not yet reflected
;; the newly toggled state.

(defun emacsvox--advice-isearch-toggle-case-fold-after (&rest _)
  "Announce the new isearch case-fold state."
  (emacsvox-icon (if isearch-case-fold-search 'off 'on))
  (tts-speak
   (format " Case is %s significant in search"
           (if isearch-case-fold-search " not" " "))))

(advice-add
 'isearch-toggle-case-fold :after
 #'emacsvox--advice-isearch-toggle-case-fold-after
 '((name . emacsvox)))

(defun emacsvox--advice-isearch-toggle-regexp-after (&rest _)
  "Announce the new isearch regexp state."
  (emacsvox-icon (if isearch-regexp 'on 'off))
  (tts-speak (if isearch-regexp "Regexp search" "text search")))

(advice-add
 'isearch-toggle-regexp :after
 #'emacsvox--advice-isearch-toggle-regexp-after
 '((name . emacsvox)))

(defun emacsvox--advice-isearch-occur-after (&rest _)
  "Cue interactively opening isearch matches in Occur."
  (when (ems-interactive-p 'isearch-occur)
    (emacsvox-icon 'open-object)))

(advice-add
 'isearch-occur :after #'emacsvox--advice-isearch-occur-after
 '((name . emacsvox)))

;;;  marking objects produces auditory icons

;; Prevent push-mark from displaying its mark set message
;; when called from functions that know better.

(defun emacsvox--advice-push-mark-around
    (original &rest arguments)
  "Call ORIGINAL with the mark-set message silenced."
  (ems-with-messages-silenced (apply original arguments)))

(advice-add
 'push-mark :around #'emacsvox--advice-push-mark-around
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (set-mark-command pop-to-mark-command)
    "Announce an interactive mark-ring operation."
  (emacsvox-icon 'mark-object)
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(defun emacsvox--advice-pop-global-mark-after ()
  "Speak the destination and buffer after popping the global mark."
  (when (ems-interactive-p 'pop-global-mark)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line))
    (tts-notify (buffer-name))))

(advice-add
 'pop-global-mark :after #'emacsvox--advice-pop-global-mark-after
 '((name . emacsvox)))

(defun emacsvox--marked-lines-after (target object)
  "Announce lines marked by TARGET as OBJECT."
  (when (ems-interactive-p target)
    (emacsvox-icon 'mark-object)
    (message "Marked %s containing %s lines"
             object (count-lines (point) (mark 'force)))))

(defun emacsvox--advice-mark-defun-after (&rest _)
  "Announce the function marked interactively."
  (emacsvox--marked-lines-after 'mark-defun "function"))

(advice-add
 'mark-defun :after #'emacsvox--advice-mark-defun-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-whole-buffer-after (&rest _)
  "Announce the buffer marked interactively."
  (emacsvox--marked-lines-after 'mark-whole-buffer "buffer"))

(advice-add
 'mark-whole-buffer :after
 #'emacsvox--advice-mark-whole-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-paragraph-after (&rest _)
  "Announce the paragraph marked interactively."
  (emacsvox--marked-lines-after 'mark-paragraph "paragraph"))

(advice-add
 'mark-paragraph :after #'emacsvox--advice-mark-paragraph-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-page-after (&rest _)
  "Announce the page marked interactively."
  (emacsvox--marked-lines-after 'mark-page "page"))

(advice-add
 'mark-page :after #'emacsvox--advice-mark-page-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-word-after (&rest _)
  "Announce the word marked interactively."
  (when (ems-interactive-p 'mark-word)
    (emacsvox-icon 'mark-object)
    (message "Word %s marked"
             (buffer-substring-no-properties
              (point) (mark 'force)))))

(advice-add
 'mark-word :after #'emacsvox--advice-mark-word-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-sexp-after (&rest _)
  "Announce the S-expression marked interactively."
  (when (ems-interactive-p 'mark-sexp)
    (let
        ((lines (count-lines (point) (marker-position (mark-marker))))
         (chars (abs (- (point) (marker-position (mark-marker))))))
      (emacsvox-icon 'mark-object)
      (message
       (if (> lines 1)
         (format "Marked S expression spanning %s lines" lines)
         (format "marked S expression containing %s characters" chars))))))

(advice-add
 'mark-sexp :after #'emacsvox--advice-mark-sexp-after
 '((name . emacsvox)))

(defun emacsvox--advice-mark-end-of-sentence-after (&rest _)
  "Cue an interactively marked sentence."
  (when (ems-interactive-p 'mark-end-of-sentence)
    (emacsvox-icon 'mark-object)))

(advice-add
 'mark-end-of-sentence :after
 #'emacsvox--advice-mark-end-of-sentence-after
 '((name . emacsvox)))

;;;  emacs registers

(emacsvox-advice--define-interactive-after-advice
    (point-to-register)
    "Cue storing point or the current frame configuration in a register."
  (emacsvox-icon 'mark-object)
  (if current-prefix-arg
      (message "Stored current frame configuration")
    (emacsvox-speak-line)))

(defun emacsvox--advice-copy-to-register-after
    (register start end &rest _)
  "Acknowledge an interactive copy from START to END into REGISTER."
  (when (ems-interactive-p 'copy-to-register)
    (let ((lines (count-lines start end))
          (characters (abs (- start end))))
      (if (> lines 1)
          (tts-notify
           (format "Copied %s lines to register %c" lines register))
        (tts-notify
         (format "Copied %s characters to register %c"
                 characters register))))))

(advice-add
 'copy-to-register :after #'emacsvox--advice-copy-to-register-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (view-register)
    "Speak the displayed contents of a register."
  (with-current-buffer "*Output*"
    (tts-speak (buffer-string))
    (emacsvox-icon 'open-object)))

(emacsvox-advice--define-interactive-after-advice
    (jump-to-register)
    "Speak the line reached by jumping to a register."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(emacsvox-advice--define-interactive-after-advice
    (insert-parentheses)
    "Speak the inserted parentheses and cue the opened object."
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(emacsvox-advice--define-interactive-after-advice
    (insert-register)
    "Cue inserted register text and speak its first line."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'yank-object)
    (emacsvox-speak-line)))

(defun emacsvox--advice-window-configuration-to-register-after
    (register &rest _)
  "Announce an interactive window configuration copy to REGISTER."
  (when (ems-interactive-p 'window-configuration-to-register)
    (message "Copied window configuration to register %c" register)))

(advice-add
 'window-configuration-to-register :after
 #'emacsvox--advice-window-configuration-to-register-after
 '((name . emacsvox)))

(defun emacsvox--advice-frameset-to-register-after (register)
  "Announce an interactive frameset copy to REGISTER."
  (when (ems-interactive-p 'frameset-to-register)
    (message "Copied frame  configuration to register %c" register)))

(advice-add
 'frameset-to-register :after
 #'emacsvox--advice-frameset-to-register-after
 '((name . emacsvox)))

(defun emacsvox--advice-frame-configuration-to-register-after
    (register &rest _)
  "Announce an interactive frame configuration copy to REGISTER."
  (when (ems-interactive-p 'frame-configuration-to-register)
    (message "Copied frame  configuration to register %c" register)))

(advice-add
 'frame-configuration-to-register :after
 #'emacsvox--advice-frame-configuration-to-register-after
 '((name . emacsvox)))

;;;  set up clause boundaries for specific modes:

(add-hook 'help-mode-hook #'emacsvox-speak-adjust-clause-boundaries)
(add-hook 'help-mode-hook #'emacsvox-pronounce-toggle-dictionaries)
(add-hook 'text-mode-hook #'emacsvox-speak-adjust-clause-boundaries)

;;;  setup minibuffer hooks:

;; We temporarily silence the pronunciation of default-directory when
;; in the minibuffer to speed up interaction. this is achieved by
;; defining a minibuffer-dictionary var that holds  pronunciations
;; local to the minibuffer. We add default-directory in the setup hook
;; and remove it in the exit hook.
;; We also use this to silence emacsvox-media-shortcuts, and may use
;; it in the future for other relevant use-cases.

(cl-declaim (special emacsvox-media-shortcuts))
(defvar emacsvox-minibuffer-dictionary
  (let ((table (make-hash-table)))
    (puthash emacsvox-media-shortcuts " " table)
    table)
  "Dictionary used in minibuffer.")

(defun emacsvox-minibuffer-setup-hook ()
  "Actions to take when entering the minibuffer with emacsvox running."
  (tts-stop 'all)
  (let ((inhibit-field-text-motion t))
    (setq emacsvox-pronounce-table emacsvox-minibuffer-dictionary)
    (puthash  default-directory "" emacsvox-pronounce-table)
    (emacsvox-icon 'open-object)
    (when minibuffer-default (emacsvox-icon 'help))
    (tts-with-punctuations
     'all
     (tts-notify
      (concat
       (buffer-string)
       (if (stringp minibuffer-default) minibuffer-default ""))))))

(add-hook 'minibuffer-setup-hook 'emacsvox-minibuffer-setup-hook 'at-end)

(defun emacsvox-minibuffer-exit-hook ()
  "Actions performed when exiting the minibuffer with Emacsvox loaded."
  (tts-stop 'all)
  (remhash  default-directory  emacsvox-pronounce-table)
  (emacsvox-icon 'close-object))

(add-hook 'minibuffer-exit-hook #'emacsvox-minibuffer-exit-hook)
(cl-declaim (special minibuffer-mode-map))
(define-key minibuffer-mode-map (kbd "C-c a") 'emacsvox-filter-after)
(define-key minibuffer-mode-map (kbd "C-c b") 'emacsvox-filter-before)
(define-key minibuffer-local-completion-map (kbd "C-c a") 'emacsvox-filter-after)
(define-key minibuffer-local-completion-map (kbd "C-c b")
            'emacsvox-filter-before)
(define-key minibuffer-local-ns-map (kbd "C-c a") 'emacsvox-filter-after)
(define-key minibuffer-local-ns-map (kbd "C-c b") 'emacsvox-filter-before)
;;;  Advice occur

(emacsvox-advice--define-interactive-after-advice
    (occur-prev occur-next occur-mode-goto-occurrence)
    "Announce the destination of interactive Occur navigation."
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))

(defun emacsvox--advice-occur-mode-display-occurrence-after ()
  "Announce interactively displaying an occurrence."
  (when (ems-interactive-p 'occur-mode-display-occurrence)
    (emacsvox-icon 'open-object)
    (message "Displayed occurrence in other window")))

(advice-add
 'occur-mode-display-occurrence :after
 #'emacsvox--advice-occur-mode-display-occurrence-after
 '((name . emacsvox)))

;;;  abbrev mode advice

(emacsvox-advice--define-interactive-after-advice
    (abbrev-edit-save-buffer)
    "Cue saving the edited abbrev definitions."
  (emacsvox-icon 'save-object)
  (tts-speak "Saved Abbrevs"))

(emacsvox-advice--define-interactive-after-advice
    (edit-abbrevs-redefine)
    "Cue redefining abbrevs from the edit buffer."
  (emacsvox-icon 'task-done)
  (tts-speak "Redefined abbrevs"))

(emacsvox-advice--define-interactive-after-advice
    (list-abbrevs)
    "Announce display of the abbrev list."
  (emacsvox-icon 'open-object)
  (message "Displayed abbrevs in other window."))

(emacsvox-advice--define-interactive-after-advice
    (edit-abbrevs)
    "Cue opening the abbrev editor and speak its mode line."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox--advice-expand-abbrev-around
    (original &rest arguments)
  "Call ORIGINAL once and speak an interactive abbrev expansion."
  (when buffer-read-only
    (tts-speak "Buffer is read-only. "))
  (if (ems-interactive-p 'expand-abbrev)
      (let ((start (save-excursion (backward-word 1) (point)))
            result)
        (setq result (apply original arguments))
        (tts-speak (buffer-substring start (point)))
        result)
    (apply original arguments)))

(advice-add
 'expand-abbrev :around #'emacsvox--advice-expand-abbrev-around
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (abbrev-mode)
    "Announce the new abbrev mode state."
  (emacsvox-icon 'button)
  (message "Turned %s abbrev mode" (if abbrev-mode "on" "off")))

;;;  advice where-is and friends

(defun ems-canonicalize-key-description (desc)
  "Change key description to a speech-friendly form."
  (let ((shift-regexp "S-\\(.\\)")
        (ctrl-regexp "C-\\(.\\)")
        (meta-regexp "M-\\(.\\)")
        (caps-regexp "\\b[A-Z]\\b")
        (hyper-regexp "C-x @ h")
        (alt-regexp "C-x @ a")
        (super-regexp "C-x @ s")
        (buffer-undo-list t))
    (with-temp-buffer
      
      (setq case-fold-search nil)
      (erase-buffer)
      (insert desc)
      (goto-char (point-min))
      (while (search-forward "SPC" nil t)
        (replace-match "space"))
      (goto-char (point-min))
      (while (search-forward "ESC" nil t)
        (replace-match "escape"))
      (goto-char (point-min))
      (while (search-forward "RET" nil t)
        (replace-match "return"))
      (goto-char (point-min))
      (while (re-search-forward hyper-regexp nil t)
        (replace-match "hyper "))
      (goto-char (point-min))
      (while (re-search-forward alt-regexp nil t)
        (replace-match "alt "))
      (goto-char (point-min))
      (while (re-search-forward super-regexp nil t)
        (replace-match "super "))
      (goto-char (point-min))
      (while (re-search-forward shift-regexp nil t)
        (replace-match "shift \\1"))
      (goto-char (point-min))
      (while (re-search-forward ctrl-regexp nil t)
        (replace-match "control \\1"))
      (goto-char (point-min))
      (while (re-search-forward meta-regexp nil t)
        (replace-match "meta \\1"))
      (goto-char (point-min))
      (goto-char (point-min))
      (while (re-search-forward caps-regexp nil t)
        (replace-match " cap \\& " t))
      (buffer-string))))

(defun emacsvox--advice-describe-key-briefly-around
    (original &rest arguments)
  "Call ORIGINAL once and speak an interactive key description."
  (if (ems-interactive-p 'describe-key-briefly)
      (let* ((emacsvox-speak-messages nil)
             (result (apply original arguments)))
        (tts-speak (ems-canonicalize-key-description result))
        result)
    (apply original arguments)))

(advice-add
 'describe-key-briefly :around
 #'emacsvox--advice-describe-key-briefly-around
 '((name . emacsvox)))

(defun ems--get-where-is (cmd )
  "Return string describing keys that invoke `cmd'. "
  (let* ((keys (where-is-internal cmd overriding-local-map nil nil ))
         (desc
          (if (zerop (length keys))
              "is not on any key"
            (mapconcat 'key-description keys ", "))))
    (concat
     (format "%s  " cmd)
     (ems-canonicalize-key-description desc))))

(defun emacsvox--advice-where-is-after (definition &optional _insert)
  "Speak keys for interactive `where-is' DEFINITION."
  (when (ems-interactive-p 'where-is)
    (tts-speak (ems--get-where-is definition))))

(advice-add
 'where-is :after #'emacsvox--advice-where-is-after
 '((name . emacsvox)))

;;;  apropos and friends
(emacsvox-advice--define-interactive-after-advice
    (apropos apropos-char apropos-library
     apropos-unicode apropos-user-option apropos-value apropos-variable
     apropos-command apropos-documentation)
    "Announce display of interactive Apropos results."
  (emacsvox-icon 'help)
  (message "Displayed apropos in other window."))

(defun emacsvox--advice-apropos-follow-after (&rest _)
  "Speak Help displayed by interactively following an Apropos result."
  (when (ems-interactive-p 'apropos-follow)
    (emacsvox-icon 'select-object) (emacsvox-speak-help)))

(advice-add
 'apropos-follow :after #'emacsvox--advice-apropos-follow-after
 '((name . emacsvox)))

;;;  toggling debug state

(defun emacsvox--debug-toggle-after (target state setting)
  "Announce an interactive debug toggle.
TARGET identifies the command, STATE is its new value, and SETTING names it."
  (when (ems-interactive-p target)
    (emacsvox-icon (if state 'on 'off))
    (message "Turned %s debug on %s" state setting)))

(defun emacsvox--advice-toggle-debug-on-error-after (&rest _)
  "Announce the new `debug-on-error' state."
  (emacsvox--debug-toggle-after
   'toggle-debug-on-error debug-on-error "error"))

(advice-add
 'toggle-debug-on-error :after
 #'emacsvox--advice-toggle-debug-on-error-after
 '((name . emacsvox)))

(defun emacsvox--advice-toggle-debug-on-quit-after (&rest _)
  "Announce the new `debug-on-quit' state."
  (emacsvox--debug-toggle-after
   'toggle-debug-on-quit debug-on-quit "quit"))

(advice-add
 'toggle-debug-on-quit :after
 #'emacsvox--advice-toggle-debug-on-quit-after
 '((name . emacsvox)))

;;;  alert if entering override mode

(emacsvox-advice--define-interactive-after-advice
    (overwrite-mode)
    "Announce the new overwrite mode state."
  (emacsvox-icon 'warn-user)
  (message "Turned %s overwrite mode" (or overwrite-mode "off")))

;;;  Options mode and custom

(emacsvox-advice--define-interactive-after-advice
    (customize)
    "Provide status update."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox--advice-customize-save-variable-around
    (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS while silencing Custom chatter."
  (ems-with-messages-silenced
    (let ((tts-quiet t))
      (apply original arguments))))

(advice-add
 'customize-save-variable :around
 #'emacsvox--advice-customize-save-variable-around
 '((name . emacsvox)))

;;;  transient mark mode

(emacsvox-advice--define-interactive-after-advice
    (transient-mark-mode)
    "Announce the new transient mark mode state."
  (emacsvox-icon (if transient-mark-mode 'on 'off))
  (message "Turned %s transient mark."
           (if transient-mark-mode "on" "off")))

;;;  provide auditory icon when window config changes

;;;  mail aliases

(emacsvox-advice--define-interactive-after-advice
    (expand-mail-aliases)
    "Speak the expanded mail alias at point."
  (let ((end (point))
        (start (re-search-backward " " nil t)))
    (message (buffer-substring start end))
    (emacsvox-icon 'select-object)))

;;;  elint

(defun emacsvox--elint-around (target original arguments)
  "Call ORIGINAL and announce interactive Elint completion.
TARGET identifies the Elint command, and ARGUMENTS are passed unchanged."
  (if (ems-interactive-p target)
      (ems-with-messages-silenced
        (let ((result (apply original arguments)))
          (emacsvox-icon 'task-done)
          (message "Displayed lint results in other window. ")
          result))
    (apply original arguments)))

(defun emacsvox--advice-elint-current-buffer-around
    (original &rest arguments)
  "Call ORIGINAL and announce interactive current-buffer linting."
  (emacsvox--elint-around
   'elint-current-buffer original arguments))

(advice-add
 'elint-current-buffer :around
 #'emacsvox--advice-elint-current-buffer-around
 '((name . emacsvox)))

(defun emacsvox--advice-elint-file-around
    (original &rest arguments)
  "Call ORIGINAL and announce interactive file linting."
  (emacsvox--elint-around 'elint-file original arguments))

(advice-add
 'elint-file :around #'emacsvox--advice-elint-file-around
 '((name . emacsvox)))

(defun emacsvox--advice-elint-defun-around
    (original &rest arguments)
  "Call ORIGINAL and announce interactive defun linting."
  (emacsvox--elint-around 'elint-defun original arguments))

(advice-add
 'elint-defun :around #'emacsvox--advice-elint-defun-around
 '((name . emacsvox)))

;;;  advice button creation to add voicification:

(defun emacsvox--mark-button-range (start end)
  "Mark the button from START to END with its auditory icon."
  (with-silent-modifications
    (condition-case nil
        (let ((inhibit-read-only t))
          (put-text-property start end 'auditory-icon 'button))
      (error nil))))

(defun emacsvox--advice-make-button-after (start end &rest _)
  "Add an auditory icon to the button from START to END."
  (emacsvox--mark-button-range start end))

(advice-add
 'make-button :after #'emacsvox--advice-make-button-after
 '((name . emacsvox)))

(defun emacsvox--advice-make-text-button-after (start end &rest _)
  "Add an auditory icon to the text button from START to END."
  (emacsvox--mark-button-range start end))

(advice-add
 'make-text-button :after #'emacsvox--advice-make-text-button-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (push-button)
    "Cue interactive button activation."
  (emacsvox-icon 'button))

;;;  silence whitespace cleanup:

(defun emacsvox--whitespace-cleanup-around (original arguments)
  "Call ORIGINAL with cleanup messages silenced, passing ARGUMENTS."
  (ems-with-messages-silenced (apply original arguments)))

(defun emacsvox--advice-whitespace-cleanup-around
    (original &rest arguments)
  "Call ORIGINAL with whitespace cleanup messages silenced."
  (emacsvox--whitespace-cleanup-around original arguments))

(advice-add
 'whitespace-cleanup :around
 #'emacsvox--advice-whitespace-cleanup-around
 '((name . emacsvox)))

(defun emacsvox--advice-whitespace-cleanup-internal-around
    (original &rest arguments)
  "Call ORIGINAL with internal whitespace cleanup messages silenced."
  (emacsvox--whitespace-cleanup-around original arguments))

(advice-add
 'whitespace-cleanup-internal :around
 #'emacsvox--advice-whitespace-cleanup-internal-around
 '((name . emacsvox)))

;;;  advice Finder:

(emacsvox-advice--define-interactive-after-advice
    (finder-commentary)
    "Speak Finder commentary and cue the opened buffer."
  (emacsvox-speak-buffer)
  (emacsvox-icon 'open-object))

(defun emacsvox--advice-finder-mode-after (&rest _)
  "Register the Emacsvox keyword and announce the Finder buffer."
  (when
      (and (boundp 'finder-known-keywords)
           (not (eq 'emacsvox (caar finder-known-keywords))))
    (push (cons 'emacsvox "Audio Desktop") finder-known-keywords))
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(advice-add
 'finder-mode :after #'emacsvox--advice-finder-mode-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (finder-exit)
    "Cue leaving Finder and speak the selected window's mode line."
  (emacsvox-icon 'close-object)
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-speak-mode-line)))

;;;  display world time

(emacsvox-advice--define-interactive-after-advice
    (world-clock)
    "Cue and speak the displayed world clock."
  (emacsvox-icon 'open-object)
  (save-current-buffer
    (set-buffer "*wclock*")
    (emacsvox-speak-buffer)))

;;;  browse-url

(defun emacsvox--browse-url-around (target original arguments)
  "Call ORIGINAL and prepare speech for interactive browsing.
TARGET identifies the browse command, and ARGUMENTS are passed unchanged."
  (when (ems-interactive-p target)
    (emacsvox-icon 'open-object)
    (emacsvox-eww-autospeak))
  (apply original arguments))

(defun emacsvox--advice-browse-url-of-buffer-around
    (original &rest arguments)
  "Call ORIGINAL after preparing speech for interactive buffer browsing."
  (emacsvox--browse-url-around
   'browse-url-of-buffer original arguments))

(advice-add
 'browse-url-of-buffer :around
 #'emacsvox--advice-browse-url-of-buffer-around
 '((name . emacsvox)))

(defun emacsvox--advice-browse-url-of-region-around
    (original &rest arguments)
  "Call ORIGINAL after preparing speech for interactive region browsing."
  (emacsvox--browse-url-around
   'browse-url-of-region original arguments))

(advice-add
 'browse-url-of-region :around
 #'emacsvox--advice-browse-url-of-region-around
 '((name . emacsvox)))

;;;  Cue input method changes

(emacsvox-advice--define-interactive-after-advice
    (toggle-input-method)
    "Announce the new input method state."
  (emacsvox-icon (if current-input-method 'on 'off))
  (tts-speak
   (format "Current input method is %s"
           (or current-input-method "none"))))

;;;  silence midnight cleanup:

(advice-add
 'clean-buffer-list :around #'emacsvox--silence-messages-around
 '((name . emacsvox)))

;;;  Splash Screen:

(emacsvox-advice--define-interactive-after-advice
    (about-emacs display-about-screen)
    "Speak the displayed splash or About buffer."
  (emacsvox-icon 'open-object)
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-speak-buffer)))

(emacsvox-advice--define-interactive-after-advice
    (exit-splash-screen)
    "Cue closing the splash screen and speak the resulting mode line."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

;;;  copyright commands:

(emacsvox-advice--define-interactive-after-advice
    (copyright copyright-update)
    "Cue completion and speak the updated copyright line."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-line))

(emacsvox-advice--define-interactive-after-advice
    (copyright-update-directory)
    "Cue completion of an interactive directory copyright update."
  (emacsvox-icon 'task-done))

;;;  Asking Questions:

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

(advice-add
 'yes-or-no-p :around #'emacsvox--advice-yes-or-no-p-around
 '((name . emacsvox)))

(defun emacsvox--advice-y-or-n-p-around (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS and cue a short question and answer."
  (emacsvox--question-around
   'ask-short-question 'y-answer 'n-answer original arguments))

(advice-add
 'y-or-n-p :around #'emacsvox--advice-y-or-n-p-around
 '((name . emacsvox)))

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

(advice-add
 'ask-user-about-lock :around
 #'emacsvox--advice-ask-user-about-lock-around
 '((name . emacsvox)))

(defun emacsvox--advice-ask-user-about-lock-help-after (&rest _)
  "Cue the display of lock-conflict help."
  (emacsvox-icon 'help))

(advice-add
 'ask-user-about-lock-help :after
 #'emacsvox--advice-ask-user-about-lock-help-after
 '((name . emacsvox)))

;;;  Advice process-menu

(defun emacsvox--advice-process-menu-delete-process-after (&rest _)
  "speak."
  (when (ems-interactive-p 'process-menu-delete-process)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add
 'process-menu-delete-process :after
 #'emacsvox--advice-process-menu-delete-process-after
 '((name . emacsvox)))

(defun emacsvox--advice-list-processes-after (&rest _)
  "speak."
  (when (ems-interactive-p 'list-processes)
    (emacsvox-icon 'open-object)
    (message "Displayed process list in other window.")))

(advice-add
 'list-processes :after #'emacsvox--advice-list-processes-after
 '((name . emacsvox)))

(defun emacsvox--advice-timer-list-after (&rest _)
  "Speak the mode line after displaying the interactive timer list."
  (when (ems-interactive-p 'timer-list)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'timer-list :after #'emacsvox--advice-timer-list-after
 '((name . emacsvox)))

;;; list-timers:

(defun emacsvox--advice-list-timers-after (&rest _)
  "Speak the current line after listing timers interactively."
  (when (ems-interactive-p 'list-timers)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-line)))

(advice-add
 'list-timers :after #'emacsvox--advice-list-timers-after
 '((name . emacsvox)))

;;; find-library:

(defun emacsvox--advice-find-library-after (&rest _)
  "Speak the mode line after finding a library interactively."
  (when (ems-interactive-p 'find-library)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'find-library :after #'emacsvox--advice-find-library-after
 '((name . emacsvox)))

;;; log-edit-done

(emacsvox-advice--define-interactive-after-advice
    (log-edit-done)
    "Speak the resulting mode line and cue the closed log edit."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'close-object))

;;;  advice find-func etc.

(emacsvox-advice--define-interactive-after-advice
    (find-function find-function-at-point find-variable
                   find-variable-at-point find-function-on-key)
    "Speak the source line after navigating to a definition."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

;;; Advice Semantic:

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

(advice-add
 'semantic-complete-symbol :around
 #'emacsvox--advice-semantic-complete-symbol-around
 '((name . emacsvox)))

(provide 'emacsvox-cedet)

;;;  advice Imenu

(defun emacsvox--advice-imenu-after (&rest _)
  "Speak the destination after navigating with Imenu interactively."
  (when (ems-interactive-p 'imenu)
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(advice-add
 'imenu :after #'emacsvox--advice-imenu-after
 '((name . emacsvox)))

;;; Advice property search

(defun emacsvox--property-search-filter-return (result target)
  "Speak property search RESULT for interactive TARGET and return RESULT."
  (when (ems-interactive-p target)
    (if result
        (progn
          (emacsvox-speak-region
           (prop-match-beginning result) (prop-match-end result))
          (emacsvox-icon 'select-object))
      (emacsvox-icon 'warn-user)
      (emacsvox-speak-line)))
  result)

(defun emacsvox--advice-text-property-search-backward-filter-return
    (result)
  "Speak the result of an interactive backward text-property search."
  (emacsvox--property-search-filter-return
   result 'text-property-search-backward))

(advice-add
 'text-property-search-backward :filter-return
 #'emacsvox--advice-text-property-search-backward-filter-return
 '((name . emacsvox)))

(defun emacsvox--advice-text-property-search-forward-filter-return
    (result)
  "Speak the result of an interactive forward text-property search."
  (emacsvox--property-search-filter-return
   result 'text-property-search-forward))

(advice-add
 'text-property-search-forward :filter-return
 #'emacsvox--advice-text-property-search-forward-filter-return
 '((name . emacsvox)))

;;; ielm: header-line

(defvar ielm-working-buffer)

(defun emacsvox--advice-ielm-after (&rest _)
  "Set and speak the header line after starting IELM interactively."
  (when (ems-interactive-p 'ielm)
    (setq header-line-format
          '((:eval
             (concat
              (propertize "Interactive Elisp" 'personality
                          voice-annotate)
              (format "On %s" (buffer-name ielm-working-buffer))))))
    (emacsvox-icon 'open-object)
    (emacsvox-speak-header-line)))

(advice-add
 'ielm :after #'emacsvox--advice-ielm-after
 '((name . emacsvox)))

;;; Help Navigation:

(emacsvox-advice--define-interactive-after-advice
    (help-goto-next-page help-goto-previous-page)
    "Speak the destination after navigating between Help pages."
  (emacsvox-icon 'scroll)
  (emacsvox-speak-line))

;;; C-x x commands

(defun emacsvox--advice-revert-buffer-quick-after (&rest _)
  "speak."
  (when (ems-interactive-p 'revert-buffer-quick)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add
 'revert-buffer-quick :after #'emacsvox--advice-revert-buffer-quick-after
 '((name . emacsvox)))

;;; Battery:

(defun emacsvox--advice-battery-around (original &rest arguments)
  "Call ORIGINAL once and speak an interactive battery report."
  (if (ems-interactive-p 'battery)
      (let (result)
        (ems-with-messages-silenced
          (setq result (apply original arguments))
          (tts-with-punctuations 'some
            (tts-speak result)))
        result)
    (apply original arguments)))

(advice-add
 'battery :around #'emacsvox--advice-battery-around
 '((name . emacsvox)))

;;; emacs lisp mode:

(add-hook
 'emacs-lisp-mode-hook
 #'(lambda ()
     (setq
      mode-name
      '("ELisp"
        (lexical-binding
         (:propertize
          ":l"
          'personality voice-smoothen
          help-echo "Using lexical-binding mode")
         (:propertize
          ":d"
          'personality voice-smoothen
          help-echo "Using old dynamic scoping mode "
          face warning mouse-face mode-line-highlight
          local-map
          (keymap
           (mode-line keymap
                      (mouse-1 . elisp-enable-lexical-binding)))))))))

;;; Spinner:

(defun emacsvox--advice-spinner-start-after (&rest _)
  "Cue the start of spinner activity."
  (emacsvox-icon 'repeat-start))

(advice-add
 'spinner-start :after #'emacsvox--advice-spinner-start-after
 '((name . emacsvox)))

(defun emacsvox--advice-spinner-stop-after (&rest _)
  "Cue the end of spinner activity."
  (emacsvox-icon 'repeat-stop))

(advice-add
 'spinner-stop :after #'emacsvox--advice-spinner-stop-after
 '((name . emacsvox)))

;;; Rectangle Motion

(emacsvox-advice--define-interactive-after-advice
    (rectangle-next-line rectangle-previous-line)
    "Speak the line after moving vertically in a rectangle."
  (emacsvox-speak-line))

(defvar rectangle-mark-mode nil
  "Non-nil when rectangle mark mode is active.")

(defun emacsvox--advice-rectangle-mark-mode-after (&rest _)
  "Announce the state of rectangle mark mode after an interactive toggle."
  (when (ems-interactive-p 'rectangle-mark-mode)
    (tts-notify
     (format "Turned %s rectangle mark mode"
             (if rectangle-mark-mode "on" "off")))
    (emacsvox-icon (if rectangle-mark-mode 'on 'off))))

(advice-add
 'rectangle-mark-mode :after
 #'emacsvox--advice-rectangle-mark-mode-after
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-after-advice
    (rectangle-backward-char rectangle-forward-char
                             rectangle-right-char rectangle-left-char)
    "Speak the character after moving horizontally in a rectangle."
  (emacsvox-speak-char t))
;;; Compose Mail:

(emacsvox-advice--define-interactive-after-advice
    (compose-mail)
    "Cue opening a mail composition buffer and speak its current line."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

;;; Speaking Spaces:

(emacsvox-advice--define-interactive-after-advice
    (cycle-spacing just-one-space)
    "Speak the line and resulting whitespace after normalizing spaces."
  (emacsvox-speak-line)
  (emacsvox-speak-spaces))

;;; psession:

(defun emacsvox--advice-psession--dump-object-to-file-save-alist-around
    (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS while silencing messages."
  (ems-with-messages-silenced
    (apply original arguments)))

(defun emacsvox--enable-psession-advice ()
  "Install Emacsvox advice for psession persistence."
  (advice-add
   'psession--dump-object-to-file-save-alist :around
   #'emacsvox--advice-psession--dump-object-to-file-save-alist-around
   '((name . emacsvox))))

(with-eval-after-load
    "psession"
  (emacsvox--enable-psession-advice))

(provide 'emacsvox-advice)

;;;  end of file
