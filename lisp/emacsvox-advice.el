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

(voice-setup-set-voice-for-face 'query-replace 'voice-animate)

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

(defun ems--remove-overlays-around (orig-fun &rest args)
  "Clean up properties mirrored from overlays."
  (let
      ((ems--voiceify-overlays nil)
       (beg (or (ad-get-arg 0) (point-min)))
       (end (or (ad-get-arg 1) (point-max))) (name (ad-get-arg 2)))
    (when (zerop beg) (setq beg (point-min)))
    (with-silent-modifications (put-text-property beg end name nil))
    (apply orig-fun args)))

(advice-add 'remove-overlays :around #'ems--remove-overlays-around)

(defun ems--delete-overlay-before (&rest _)
  "Augment voice lock."
  (when ems--voiceify-overlays
    (let*
        ((o (ad-get-arg 0)) (buffer (overlay-buffer o))
         (start (overlay-start o)) (end (overlay-end o))
         (voice (dtk-get-voice-for-face (overlay-get o 'face)))
         (invisible (overlay-get o 'invisible)))
      (when (and start end voice buffer)
        (with-current-buffer buffer
          (save-restriction
            (widen) (ems--remove-personality start end voice buffer))))
      (when (and start end invisible)
        (with-silent-modifications
          (put-text-property start end 'invisible nil))))))

(advice-add 'delete-overlay :before #'ems--delete-overlay-before)

(defun ems--overlay-put-after (&rest _)
  "Augment voice lock."
  (when (and (overlay-buffer (ad-get-arg 0)) ems--voiceify-overlays)
    (let*
        ((overlay (ad-get-arg 0)) (prop (ad-get-arg 1))
         (value (ad-get-arg 2)) (start (overlay-start overlay))
         (end (overlay-end overlay)) (voice nil))
      (cond
       ((and
         (or (memq prop '(font-lock-face face))
             (and (eq prop 'category) (get value 'face)))
         (integerp start) (integerp end))
        (when (eq prop 'category) (setq value (get value 'face)))
        (setq voice (dtk-get-voice-for-face value))
        (when voice
          (ems--add-personality start end voice
                                (overlay-buffer overlay))))
       ((eq prop 'invisible)
        (with-current-buffer (overlay-buffer overlay)
          (with-silent-modifications
            (put-text-property start end 'invisible (or value nil)))))))))

(advice-add 'overlay-put :after #'ems--overlay-put-after)

(defun ems--move-overlay-before (&rest _)
  "Used by emacsvox to augment voice lock."
  (when ems--voiceify-overlays
    (let*
        ((overlay (ad-get-arg 0)) (beg (ad-get-arg 1))
         (end (ad-get-arg 2)) (object (ad-get-arg 3))
         (buffer (overlay-buffer overlay))
         (voice (dtk-get-voice-for-face (overlay-get overlay 'face)))
         (invisible (overlay-get overlay 'invisible)))
      (unless object (setq object (or buffer (current-buffer))))
      (when
          (and voice (integerp (overlay-start overlay))
               (integerp (overlay-end overlay)))
        (ems--remove-personality (overlay-start overlay)
                                 (overlay-end overlay) voice buffer)
        (ems--add-personality beg end voice object))
      (when invisible
        (with-current-buffer buffer
          (with-silent-modifications
            (put-text-property (overlay-start overlay)
                               (overlay-end overlay) 'invisible nil)))
        (with-current-buffer object
          (with-silent-modifications
            (put-text-property beg end 'invisible invisible)))))))

(advice-add 'move-overlay :before #'ems--move-overlay-before)

;;;  advice cursor movement commands to speak

(emacsvox-advice--define-interactive-after-advice
    (next-line previous-line)
    "Speak line. Speak  (visual) line if
`visual-line-mode' is  on, and
indicate  point  by an aural highlight.   Moving to
beginning or end of a physical line produces an  auditory icon."
  (cond
   ((or line-move-visual visual-line-mode) (emacsvox-speak-visual-line))
   (t (emacsvox-speak-line))))

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
                (dtk-speak (buffer-substring start end))
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

(defun ems--blink-matching-open-after (&rest _)
  "Speak" (emacsvox-speak-matching-paren))

(advice-add 'blink-matching-open :after
            #'ems--blink-matching-open-after)

(emacsvox-advice--define-interactive-after-advice
    (left-char right-char backward-char forward-char)
    "Speak char under point.
When on a close delimiter, speak matching delimiter after a small delay. "
  (and dtk-stop-immediately (dtk-stop))
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
  (dtk-notify (emacsvox-get-current-percentage-verbously)))

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
  (dtk-speak (emacsvox-get-window-contents))
  (dtk-notify
   (propertize
    (format "%s " (emacsvox-get-current-percentage-into-buffer))
    'personality voice-smoothen)))

;;;  Advise modify case commands to speak

(defun emacsvox--case-word-around
    (target tone final-message original arguments)
  "Call ORIGINAL once, then speak TARGET's case change.
TONE is played before an interactive change.  FINAL-MESSAGE is announced when
the change leaves point at the end of the buffer.  ARGUMENTS are passed through
unchanged."
  (if (ems-interactive-p target)
      (progn
        (funcall tone)
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
  "Provide a tone, then speak after `upcase-word'."
  (emacsvox--case-word-around
   'upcase-word #'dtk-tone-upcase "Upper cased final word in buffer"
   original arguments))

(advice-add
 'upcase-word :around #'emacsvox--advice-upcase-word-around
 '((name . emacsvox)))

(defun emacsvox--advice-downcase-word-around (original &rest arguments)
  "Provide a tone, then speak after `downcase-word'."
  (emacsvox--case-word-around
   'downcase-word #'dtk-tone-downcase "Lower cased final word in buffer"
   original arguments))

(advice-add
 'downcase-word :around #'emacsvox--advice-downcase-word-around
 '((name . emacsvox)))

(defun emacsvox--advice-capitalize-word-around (original &rest arguments)
  "Provide a tone, then speak after `capitalize-word'."
  (emacsvox--case-word-around
   'capitalize-word #'dtk-tone-upcase "Capitalized final word in buffer"
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
    (dtk-tone-deletion)
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
    (dtk-tone-deletion)
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
      (skip-syntax-forward " ") (dtk-tone-deletion)
      (emacsvox-speak-word 1))))

(advice-add
 'kill-word :before #'emacsvox--advice-kill-word-before
 '((name . emacsvox)))

(defun emacsvox--advice-backward-kill-word-before (&rest _)
  "Speak word beingkilled."
  (when (ems-interactive-p 'backward-kill-word)
    (save-excursion
      (let ((start (point)))
        (forward-word -1) (dtk-tone-deletion)
        (emacsvox-speak-region (point) start)))))

(advice-add
 'backward-kill-word :before #'emacsvox--advice-backward-kill-word-before
 '((name . emacsvox)))

(emacsvox-advice--define-interactive-before-advice
    (kill-line kill-whole-line)
    "Speak the line before killing it."
  (emacsvox-icon 'delete-object)
  (dtk-tone-deletion)
  (emacsvox-speak-line 1))

(defun emacsvox--advice-kill-sexp-before (&rest _)
  "Speak the killed  sexp."
  (when (ems-interactive-p 'kill-sexp)
    (emacsvox-icon 'delete-object) (dtk-tone-deletion)
    (emacsvox-speak-sexp 1)))

(advice-add
 'kill-sexp :before #'emacsvox--advice-kill-sexp-before
 '((name . emacsvox)))

(defun emacsvox--advice-kill-sentence-before (&rest _)
  "Speak the kill."
  (when (ems-interactive-p 'kill-sentence)
    (emacsvox-icon 'delete-object) (dtk-tone-deletion)
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
  (dtk-speak (buffer-substring start end)))

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
              (dtk-speak (buffer-substring start (point)))
            (dtk-speak (word-at-point))))
        result)
    (apply original arguments)))

(emacsvox-advice--define-completion-around-advice
 (hippie-expand complete)
 emacsvox--expanding-completion-around)

;;;  advice minibuffer to speak

(voice-setup-set-voice-for-face 'minibuffer-prompt 'voice-bolden)

(defun emacsvox--advice-quoted-insert-after (&rest _)
  "Speak the character inserted by interactive `quoted-insert'."
  (when (ems-interactive-p 'quoted-insert)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 'quoted-insert :after #'emacsvox--advice-quoted-insert-after
 '((name . emacsvox)))

(defun emacsvox--advice-read-event-before (&optional prompt &rest _)
  "Speak PROMPT before reading an event."
  (when prompt (dtk-notify prompt)))

(advice-add
 'read-event :before #'emacsvox--advice-read-event-before
 '((name . emacsvox)))

(defun emacsvox--advice-read-multiple-choice-before
    (prompt choices &rest _)
  "Speak PROMPT and CHOICES before prompting."
  (let
      ((dtk-stop-immediately nil)
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
    (dtk-notify prompt)
    (sox-tones 2 2)
    (dtk-speak-list spoken-choices)))

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
   (dtk-speak
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
   (dtk-speak (emacsvox-get-current-completion))))

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

(defun ems--momentary-string-display-around (orig-fun &rest args)
  "Speak."
  (ems-with-messages-silenced
   (let ((msg (ad-get-arg 0)) (exit (ad-get-arg 2)))
     (dtk-notify
      (format "%s Press %s to exit" msg
              (if exit (format "%c" exit) "space")))
     (apply orig-fun args))))

(advice-add 'momentary-string-display :around
            #'ems--momentary-string-display-around)

(defun ems--progress-reporter-do-update-around (orig-fun &rest args)
  "Silence progress reporters."
  (let ((result (apply orig-fun args)))
    (ems-with-messages-silenced (apply orig-fun args))
    (when result (emacsvox-icon 'progress)) result))

(advice-add 'progress-reporter-do-update :around
            #'ems--progress-reporter-do-update-around)

(defun ems--progress-reporter-done-after (&rest _)
  "speak." (emacsvox-icon 'time))

(advice-add 'progress-reporter-done :after
            #'ems--progress-reporter-done-after)

(cl-loop
 for f in
 '( minibuffer-message set-minibuffer-message
    message display-message-or-buffer) do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Speak message. Duplicates will not be spoken."
     (let ((m nil)
           (o minibuffer-message-overlay))
       ad-do-it
       (cond
        ((or inhibit-message (null emacsvox-speak-messages)) ad-return-value)
        (t                              ; possibly peak it 
         (setq m
               (or (current-message) (and   o (overlay-get o 'after-string))))
         (when m (setq m (string-trim m)))
         (when
             (and                       ;dup throttle
              m
              (not (zerop (length m)))
              (not (string= m emacsvox-last-message))
              (not (string-match ems--message-filter m)))
           (setq emacsvox-last-message  m)
;;; so we really need to speak it
           (emacsvox-icon 'key)
           (tts-with-punctuations 'all (dtk-notify m 'dont-log)))))
       ad-return-value))))

(defun ems--display-message-or-buffer-after (&rest _)
  "Icon"
  (let ((buffer-name (ad-get-arg 1)))
    (when (bufferp ad-return-value)
      (dtk-notify
       (format "Displayed message in buffer  %s" buffer-name)))))

(advice-add 'display-message-or-buffer :after
            #'ems--display-message-or-buffer-after)

(defvar emacsvox--last-docs nil
  "Last docs considered in `emacsvox-speak-eldoc'.")

(defun emacsvox-speak-eldoc (docs interactive)
  "Speak eldoc.  Intended for `eldoc-display-functions'."
  (with-current-buffer (get-buffer-create " *emacsvox-eldoc*")
    (erase-buffer)
    (insert (mapconcat #'car docs "\n"))
    (unless (equal docs emacsvox--last-docs)
      (emacsvox-icon 'doc))
    (when interactive (dtk-notify  (buffer-string))))
  (setq emacsvox--last-docs docs))

(with-eval-after-load "eldoc"
  (add-hook 'eldoc-display-functions #'emacsvox-speak-eldoc)
  (voice-setup-set-voice-for-face
   'eldoc-highlight-function-argument 'voice-bolden))

(defun ems--ange-ftp-process-handle-hash-around (orig-fun &rest args)
  "Jibber intelligently." 
  (ems-with-messages-silenced (apply orig-fun args)
                              (emacsvox-icon 'progress)
                              (dtk-speak
                               (format " %s percent"
                                       ange-ftp-last-percent))))

(advice-add 'ange-ftp-process-handle-hash :around
            #'ems--ange-ftp-process-handle-hash-around)

(cl-declaim (special command-error-function))
(setq command-error-function 'emacsvox-error-handler)
(defvar ems--last-error-msg nil
  "Cache last error message.")
(defvar ems--lazy-error-time (current-time)
  "Time error was spoken")

(defun emacsvox-error-handler (data _ _)
  "Custom error handler"
  (emacsvox-icon 'warn-user)
  (message (propertize (error-message-string data) 'face 'error)))
(defconst ems--error-limit 1.0
  "Seconds used to rate-limit error messages.")

(defun emacsvox-fancy-error-handler (data _ caller)
  "Custom error handler."
  
  (cl-declare (special ems--last-error-msg
                       ems--lazy-error-time))
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

(defun ems--timer-event-handler-around (orig-fun &rest args)
  "Silence messages from by timer events."
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'timer-event-handler :around
            #'ems--timer-event-handler-around)

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
  (dtk-notify
   (if read-passwd--hide-password "dot"
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
    (emacsvox-icon (if read-passwd--hide-password 'off 'on))))

(advice-add
 'read-passwd-toggle-visibility :after
 #'emacsvox--advice-read-passwd-toggle-visibility-after
 '((name . emacsvox)))

(defun emacsvox--advice-read-passwd-before (&optional prompt &rest _)
  "Speak PROMPT before reading a password."
  (emacsvox-icon 'open-object)
  (dtk-speak (or prompt "password: "))
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
                 (emacsvox-icon 'char)
                 (setq emacsvox-last-message prompt)
                 (setq emacsvox-read-char-prompt-cache prompt)
                 (tts-with-punctuations
                  'all (dtk-notify (or prompt "key"))))
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
    (tts-with-punctuations 'all (dtk-speak message))))

(advice-add
 'read-char-choice :before #'emacsvox--advice-read-char-choice-before
 '((name . emacsvox)))

;;;  advice completion functions to speak:

(defvar dabbrev--last-expansion)

(emacsvox-advice--define-interactive-after-advice
    (dabbrev-expand dabbrev-completion)
    "Speak the expanded dabbrev text."
  (accept-process-output)
  (tts-with-punctuations 'all (dtk-speak dabbrev--last-expansion)))

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
               'all (dtk-speak (buffer-substring (point) prior)))
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
           (dtk-speak (buffer-substring prior (point))))
        (emacsvox-speak-completions-if-available)))
    result))

(emacsvox-advice--define-completion-around-advice
 (lisp-complete-symbol complete-symbol widget-complete)
 emacsvox--symbol-completion-around)

(define-key minibuffer-local-completion-map "\C-o" 'switch-to-completions)

(defun emacsvox--advice-switch-to-completions-after (&rest _)
  "Speak the first completion after switching to the completions buffer."
  (emacsvox-icon 'select-object)
  (dtk-speak (emacsvox-get-current-completion)))

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
   'all (dtk-speak (emacsvox-get-current-completion))))

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
    (dtk-speak (emacsvox-get-current-completion))))

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

(defun ems--center-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'center) (message "Centered current line")))

(advice-add 'center-line :after #'ems--center-line-after)

(defun ems--center-region-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'center)
    (message "Centered current region containing %s lines"
             (count-lines (region-beginning) (region-end)))))

(advice-add 'center-region :after #'ems--center-region-after)

(defun ems--center-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'center) (message "Centered current paragraph")))

(advice-add 'center-paragraph :after #'ems--center-paragraph-after)

(cl-loop
 for f in
 '(fill-paragraph lisp-fill-paragraph)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'fill-object)
       (message "Filled current paragraph")))))

(defun ems--fill-region-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object)
    (message "Filled current region containing %s lines"
             (count-lines (region-beginning) (region-end)))))

(advice-add 'fill-region :after #'ems--fill-region-after)

;;;  vc:

(voice-setup-add-map
 '(
   (log-edit-header voice-bolden)
   (log-edit-summary voice-lighten)
   (log-edit-unknown-header voice-monotone-extra)))

;; helper function: find out vc version:

;; guess the vc version number from the variable used in minor mode alist
(defun emacsvox-vc-get-version-id ()
  "Return VC version id."
  
  (let ((id vc-mode))
    (cond
     ((and vc-mode
           (stringp vc-mode))
      (substring id 5 nil))
     (t " "))))

(defun ems--vc-toggle-read-only-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let
          ((message
            (format "Checking %s version %s "
                    (if buffer-read-only "out previous " " in new ")
                    (emacsvox-vc-get-version-id))))
        (if buffer-read-only (emacsvox-icon 'open-object)
          (emacsvox-icon 'close-object))
        (apply orig-fun args) (message message)))
     (t (apply orig-fun args)))
    result))

(advice-add 'vc-toggle-read-only :around
            #'ems--vc-toggle-read-only-around)

(defun ems--vc-refresh-state-around (orig-fun &rest args)
  "Silence messages"
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'vc-refresh-state :around #'ems--vc-refresh-state-around)

(defun ems--vc-next-action-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let
          ((message
            (format "Checking %s version %s "
                    (if buffer-read-only "out previous " " in new ")
                    (emacsvox-vc-get-version-id))))
        (if buffer-read-only (emacsvox-icon 'close-object)
          (emacsvox-icon 'open-object))
        (apply orig-fun args) (message message)))
     (t (apply orig-fun args)))
    result))

(advice-add 'vc-next-action :around #'ems--vc-next-action-around)

(defun ems--vc-revert-buffer-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'open-object)))

(advice-add 'vc-revert-buffer :after #'ems--vc-revert-buffer-after)

(defun ems--vc-finish-logentry-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (message "Checked in version %s " (emacsvox-vc-get-version-id))))

(advice-add 'vc-finish-logentry :after #'ems--vc-finish-logentry-after)

(cl-loop
 for f in
 '(vc-dir-next-line vc-dir-previous-line
                    vc-dir-next-directory vc-dir-previous-directory)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'select-object)))))

(defun ems--vc-dir-mark-file-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

(advice-add 'vc-dir-mark-file :after #'ems--vc-dir-mark-file-after)

(defun ems--vc-dir-mark-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

(advice-add 'vc-dir-mark :after #'ems--vc-dir-mark-after)

(defun ems--vc-dir-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'vc-dir :after #'ems--vc-dir-after)

(defun ems--vc-dir-hide-up-to-date-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-line)))

(advice-add 'vc-dir-hide-up-to-date :after
            #'ems--vc-dir-hide-up-to-date-after)

(defun ems--vc-dir-kill-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'vc-dir-kill-line :after #'ems--vc-dir-kill-line-after)

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

(defun ems--mail-signature-after (&rest _)
  "Announce you signed the message."
  (when (ems-interactive-p) (message "Signed your message")))

(advice-add 'mail-signature :after #'ems--mail-signature-after)

(defun ems--mail-send-and-exit-after (&rest _)
  "Speak the modeline of active buffer."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'mail-send-and-exit :after #'ems--mail-send-and-exit-after)

;;;  misc functions that have to be hand fixed:

(defun ems--zap-to-char-after (&rest _)
  "Speak line that is left."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line 1)))

(advice-add 'zap-to-char :after #'ems--zap-to-char-after)

(defun ems--describe-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Displayed mode help") (emacsvox-icon 'help)))

(advice-add 'describe-mode :after #'ems--describe-mode-after)

(defun ems--describe-repeat-maps-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Displayed  repeat-mode  help") (emacsvox-icon 'help)))

(advice-add 'describe-repeat-maps :after
            #'ems--describe-repeat-maps-after)

(cl-loop
 for f in
 '(
   describe-bindings describe-prefix-bindings isearch-describe-bindings)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (message "Displayed key bindings in help window")
       (emacsvox-icon 'help)))))

(defun ems--line-number-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-mode-line)))

(advice-add 'line-number-mode :after #'ems--line-number-mode-after)

(defun ems--column-number-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-mode-line)))

(advice-add 'column-number-mode :after #'ems--column-number-mode-after)

(defun emacsvox--advice-not-modified-after (&optional argument)
  "Provide an auditory icon."
  (when (ems-interactive-p 'not-modified)
    (if argument (emacsvox-icon 'modified-object)
      (emacsvox-icon 'unmodified-object))))

(advice-add
 'not-modified :after #'emacsvox--advice-not-modified-after
 '((name . emacsvox)))

(defun ems--comment-dwim-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (cond
     ((use-region-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))
    (emacsvox-icon 'task-done)))

(advice-add 'comment-dwim :after #'ems--comment-dwim-after)

(defun ems--comment-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (let ((prefix-arg (ad-get-arg 2)))
      (message "%s region containing %s lines"
               (if (and prefix-arg (< prefix-arg 0)) "Uncommented"
                 "Commented")
               (count-lines (point) (mark 'force))))))

(advice-add 'comment-region :after #'ems--comment-region-after)

(emacsvox-advice--define-interactive-after-advice
    (save-buffer save-some-buffers)
    "Indicate completion of an interactive save."
  (emacsvox-icon 'save-object))

(cl-loop
 for f in
 '(delete-region kill-region completion-kill-region)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Indicate region has been killed.
Use an auditory icon if possible."
     (cond
      ((ems-interactive-p)
       (let ((count (count-lines (region-beginning) (region-end))))
         ad-do-it
         (emacsvox-icon 'delete-object)
         (message "Killed region containing %s lines" count)))
      (t ad-do-it))
     ad-return-value)))

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
  (dtk-stop 'all)
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

(defun ems--local-set-key-before (&rest _)
  "Prompt using speech."
  (interactive
   (list (read-key-sequence "Locally bind key:")
         (read-command "To command:"))))

(advice-add 'local-set-key :before #'ems--local-set-key-before)

(defun ems--global-set-key-before (&rest _)
  "Provide spoken prompts."
  (interactive
   (list (read-key-sequence "Globally bind key:")
         (read-command "To command:"))))

(advice-add 'global-set-key :before #'ems--global-set-key-before)

(defun ems--modify-syntax-entry-before (&rest _)
  "Provide spoken prompts."
  (interactive
   (list (read-char "Modify syntax for: ")
         (read-string "Syntax Entry: ") current-prefix-arg)))

(advice-add 'modify-syntax-entry :before
            #'ems--modify-syntax-entry-before)

(defun ems--help-do-xref-after (&rest _)
  "Speak the ref we moved to." (emacsvox-speak-line)
  (emacsvox-icon 'item))

(advice-add 'help-do-xref :after #'ems--help-do-xref-after)

(cl-loop
 for f in 
 '(help-xref-go-back help-xref-go-forward)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (emacsvox-speak-line))))

(defun ems--help-view-source-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'open-object)))

(advice-add 'help-view-source :after #'ems--help-view-source-after)

(defun ems--help-customize-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'help-customize :after #'ems--help-customize-after)

;; Silence help for help

(defun ems--help-window-display-message-around (orig-fun &rest args)
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'help-window-display-message :around
            #'ems--help-window-display-message-around)

(cl-loop
 for f in
 '(describe-key describe-keymap)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak the help."
     (when (ems-interactive-p)
       (emacsvox-icon 'help)
       (unless ad-return-value
         (emacsvox-speak-help))))))

(cl-loop
 for f in
 '(
   describe-function describe-variable describe-symbol
   describe-face describe-font
   describe-text-properties describe-syntax
   describe-package
   describe-char describe-char-after describe-character-set
   describe-chars-in-region
   describe-coding-system describe-current-coding-system
   describe-current-coding-system-briefly
   describe-current-display-table describe-fontset
   describe-help-keys describe-input-method describe-language-environment
   describe-minor-mode describe-minor-mode-from-indicator
   describe-minor-mode-from-symbol
   describe-personal-keybindings describe-theme)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak the help."
     (when (ems-interactive-p)
       (emacsvox-icon 'help)
       (emacsvox-speak-help)))))

(defun ems--help-with-tutorial-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-set-punctuations 'all) (emacsvox-icon 'open-object)
    (emacsvox-speak-predefined-window 1)))

(advice-add 'help-with-tutorial :after #'ems--help-with-tutorial-after)

(defun ems--exchange-point-and-mark-after (&rest _)
  "Speak the line.\nIndicate large movement with an auditory icon if possible.\nAuditory highlight indicates position of point."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(advice-add 'exchange-point-and-mark :after
            #'ems--exchange-point-and-mark-after)

(emacsvox-advice--define-interactive-after-advice
    (newline newline-and-indent electric-newline-and-maybe-indent)
    "Speak the previous line if line echo is on.
See command \\[emacsvox-toggle-line-echo]. Otherwise cue the user to
the newly created  line."
  (if emacsvox-line-echo
      (emacsvox-read-previous-line)
    (dtk-tone 225 75 'force)))

(cl-loop
 for f in
 '(eval-last-sexp eval-expression)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Also speaks the result of evaluation."
     (when (ems-interactive-p)
       (let ((dtk-chunk-separator-syntax " .<>()$\"'"))
         (tts-with-punctuations 'all
                                (dtk-speak (format "%s" ad-return-value))))))))

(defun ems--shell-after (&rest _)
  "Announce switching to shell mode.\nProvide an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'shell :after #'ems--shell-after)

(cl-loop
 for f in
 '(find-tag pop-tag-mark tags-cl-loop-continue)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak the line please."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(defun emacsvox--advice-call-last-kbd-macro-around
    (original &rest arguments)
  "Call ORIGINAL once and announce an interactive keyboard macro."
  (if (ems-interactive-p 'call-last-kbd-macro)
      (let (result)
        (ems-with-messages-silenced
          (let ((dtk-quiet t)
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

(defun ems--kbd-macro-query-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (message "Will prompt at this point in macro")))

(advice-add 'kbd-macro-query :after #'ems--kbd-macro-query-after)

(defun ems--start-kbd-macro-before (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Started defining a keyboard macro ")))

(advice-add 'start-kbd-macro :before #'ems--start-kbd-macro-before)

(defun ems--end-kbd-macro-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (dtk-speak "Finished defining keyboard macro ")))

(advice-add 'end-kbd-macro :after #'ems--end-kbd-macro-after)

;; you DONT WANT TO SUSPEND EMACS WITHOUT CONFIRMATION

(defun ems--suspend-emacs-around (orig-fun &rest args)
  "Ask for confirmation."
  (let ((confirmation (yes-or-no-p "Do you want to suspend emacs ")))
    (cond
     (confirmation (message "Suspending Emacs ") (apply orig-fun args))
     (t (message "Not suspending emacs")))))

(advice-add 'suspend-emacs :around #'ems--suspend-emacs-around)

(defun ems--downcase-region-after (&rest _)
  "Give spoken confirmation."
  (when (ems-interactive-p)
    (message "Downcased region containing %s lines"
             (count-lines (region-beginning) (region-end)))))

(advice-add 'downcase-region :after #'ems--downcase-region-after)

(defun ems--upcase-region-after (&rest _)
  "Give spoken confirmation."
  (when (ems-interactive-p)
    (message "Upcased region containing %s lines"
             (count-lines (region-beginning) (region-end)))))

(advice-add 'upcase-region :after #'ems--upcase-region-after)

(cl-loop
 for f in
 '(narrow-to-region narrow-to-page)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Announce yourself."
     (when (ems-interactive-p)
       (emacsvox-icon 'mark-object)
       (message "Narrowed editing region to %s lines"
                (count-lines (region-beginning)
                             (region-end)))))))
(declare-function which-function "which-func" nil)

(defun ems--narrow-to-defun-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (require 'which-func) (emacsvox-icon 'mark-object)
    (message "Narrowed to function %s" (which-function))))

(advice-add 'narrow-to-defun :after #'ems--narrow-to-defun-after)

(defun ems--widen-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "You can now edit the entire buffer ")))

(advice-add 'widen :after #'ems--widen-after)

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

(defun ems--transpose-chars-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-char t)))

(advice-add 'transpose-chars :after #'ems--transpose-chars-after)

(defun ems--transpose-lines-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)))

(advice-add 'transpose-lines :after #'ems--transpose-lines-after)

(defun ems--transpose-words-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-word)))

(advice-add 'transpose-words :after #'ems--transpose-words-after)

(defun ems--transpose-sexps-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-sexp)))

(advice-add 'transpose-sexps :after #'ems--transpose-sexps-after)

(defun ems--open-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((count (ad-get-arg 0)))
      (emacsvox-icon 'open-object)
      (message "Opened %s blank line%s" (if (= count 1) "a" count)
               (if (= count 1) "" "s")))))

(advice-add 'open-line :after #'ems--open-line-after)

(defun ems--abort-recursive-edit-after (&rest _)
  "speak."
  (when (ems-interactive-p) (message "Aborting recursive edit")))

(advice-add 'abort-recursive-edit :after
            #'ems--abort-recursive-edit-after)

(cl-loop
 for f in
 '(undo undo-redo undo-only)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))
       (if (buffer-modified-p)
           (emacsvox-icon 'modified-object)
         (emacsvox-icon 'unmodified-object))))))

(defun ems--view-emacs-news-after (&rest _)
  "Provide auditory cue."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'view-emacs-news :after #'ems--view-emacs-news-after)

(defvar emacsvox--help-char-helpbuf " *Char Help*"
  "This is hard-coded in subr.el")

(defun ems--help-form-show-after (&rest _)
  "Speak displayed help form."
  
  (when (buffer-live-p (get-buffer emacsvox--help-char-helpbuf))
    (with-current-buffer emacsvox--help-char-helpbuf
      (goto-char (point-min)) (emacsvox-speak-buffer))))

(advice-add 'help-form-show :after #'ems--help-form-show-after)

(defcustom emacsvox-speak-tooltips nil
  "Enable to get tooltips spoken."
  :type 'boolean
  :group 'emacsvox)
(cl-loop
 for f in
 '(tooltip-show-help tooltip-show-help-non-mode) do
 (eval
  `(defadvice   ,f  (around emacsvox pre act comp)
     "speak."
     (ems-with-messages-silenced ad-do-it)
     (cond
      (emacsvox-speak-tooltips
       (let ((msg (ad-get-arg 0)))
         (when msg (dtk-speak msg))))))))

(cl-loop
 for f in
 '(tooltip-show-help-non-mode tooltip-sho)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak the tooltip."
     (when emacsvox-speak-tooltips
       (let ((help (ad-get-arg 0)))
         (dtk-speak help)
         (emacsvox-icon 'help))))))

;;;  Emacs server
(defun emacsvox-speak-announce-server-buffer ()
  "Announce opening of an emacsclient buffer."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))
(add-hook 'server-done-hook
          #'(lambda nil
              (emacsvox-icon 'close-object)))

(add-hook 'server-switch-hook 'emacsvox-speak-announce-server-buffer)

(defun ems--server-start-after (&rest _)
  "Provide auditory confirmation."
  (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'server-start :after #'ems--server-start-after)

(defun ems--server-edit-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-speak-mode-line)))

(advice-add 'server-edit :after #'ems--server-edit-after)

;;;  view echo area

(defun ems--view-echo-area-messages-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Displayed messages in other window.")))

(advice-add 'view-echo-area-messages :after
            #'ems--view-echo-area-messages-after)

;;;  selective display

(defun ems--set-selective-display-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (message "Set selective display to %s" (ad-get-arg 0))
    (emacsvox-icon 'button)))

(advice-add 'set-selective-display :after
            #'ems--set-selective-display-after)

;;;  avoid chatter when byte compiling etc

(defun emacsvox--advice-byte-compile-file-around
    (original &rest arguments)
  "Call ORIGINAL once and announce interactive byte compilation."
  (if (ems-interactive-p 'byte-compile-file)
      (let (result)
        (ems-with-messages-silenced
          (dtk-speak "Byte compiling ")
          (setq result (apply original arguments))
          (emacsvox-icon 'task-done)
          (dtk-speak "Done byte compiling "))
        result)
    (apply original arguments)))

(advice-add
 'byte-compile-file :around #'emacsvox--advice-byte-compile-file-around
 '((name . emacsvox)))

;;;  Stop talking if activity

(cl-loop
 for f in
 '(recenter-top-bottom recenter)
 do
 (eval
  `(defadvice ,f (before emacsvox pre act comp)
     "Icon."
     (when (ems-interactive-p)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(beginning-of-line move-beginning-of-line)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Icon."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'left)))))

(cl-loop
 for f in
 '(end-of-line move-end-of-line)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Icon."
     (when (ems-interactive-p)
       (emacsvox-speak-current-column)
       (emacsvox-icon 'right)))))

;;;  yanking and popping

(cl-loop
 for f in
 '(yank yank-pop)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Say what you yanked.
Produce an auditory icon if possible."
     (when (ems-interactive-p)
       (emacsvox-icon 'yank-object)
       (emacsvox-speak-region (mark 'force) (point))))))

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
  (dtk-speak (isearch-message-prefix)))

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
                                                (dtk-speak
                                                 (buffer-substring
                                                  (line-beginning-position)
                                                  (line-end-position)))))))))

(advice-add
 'isearch-search :after #'emacsvox--advice-isearch-search-after
 '((name . emacsvox)))

(defun emacsvox--advice-isearch-delete-char-after (&rest _)
  "Speak the shortened isearch string and current hit."
  (dtk-speak (propertize isearch-string 'personality voice-bolden))
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
  (dtk-speak (propertize isearch-string 'personality voice-bolden))
  (emacsvox-icon 'yank-object))

(emacsvox-advice--define-interactive-after-advice
    (isearch-ring-advance isearch-ring-retreat
                          isearch-ring-advance-edit isearch-ring-retreat-edit)
    "Speak the incremental search ring item."
  (dtk-speak (propertize isearch-string 'personality voice-bolden))
  (emacsvox-icon 'item))

;; Note the advice on the next two toggle commands
;; checks the variable being toggled.
;; When our advice is called, emacs has not yet reflected
;; the newly toggled state.

(defun emacsvox--advice-isearch-toggle-case-fold-after (&rest _)
  "Announce the new isearch case-fold state."
  (emacsvox-icon (if isearch-case-fold-search 'off 'on))
  (dtk-speak
   (format " Case is %s significant in search"
           (if isearch-case-fold-search " not" " "))))

(advice-add
 'isearch-toggle-case-fold :after
 #'emacsvox--advice-isearch-toggle-case-fold-after
 '((name . emacsvox)))

(defun emacsvox--advice-isearch-toggle-regexp-after (&rest _)
  "Announce the new isearch regexp state."
  (emacsvox-icon (if isearch-regexp 'on 'off))
  (dtk-speak (if isearch-regexp "Regexp search" "text search")))

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

(defun ems--push-mark-around (orig-fun &rest args)
  "Never show the mark set message."
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'push-mark :around #'ems--push-mark-around)

(cl-loop
 for f in
 '(set-mark-command pop-to-mark-command)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Produce an auditory icon if possible."
     (when (ems-interactive-p)
       (emacsvox-icon 'mark-object)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))))))

(defun ems--pop-global-mark-after (&rest _)
  "Speak buffer name if notification stream is available."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))
    (dtk-notify (buffer-name))))

(advice-add 'pop-global-mark :after #'ems--pop-global-mark-after)

(defun ems--mark-defun-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "Marked function containing %s lines"
             (count-lines (point) (mark 'force)))))

(advice-add 'mark-defun :after #'ems--mark-defun-after)

(defun ems--mark-whole-buffer-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message
     (format "Marked buffer containing %s lines"
             (count-lines (point) (mark 'force))))))

(advice-add 'mark-whole-buffer :after #'ems--mark-whole-buffer-after)

(defun ems--mark-paragraph-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message
     (format "Marked paragraph containing %s lines"
             (count-lines (point) (mark 'force))))))

(advice-add 'mark-paragraph :after #'ems--mark-paragraph-after)

(defun ems--mark-page-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message
     (format "Marked page containing %s lines"
             (count-lines (point) (mark 'force))))))

(advice-add 'mark-page :after #'ems--mark-page-after)

(defun ems--mark-word-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message
     (format "Word %s marked"
             (buffer-substring-no-properties (point) (mark 'force))))))

(advice-add 'mark-word :after #'ems--mark-word-after)

(defun ems--mark-sexp-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (let
        ((lines (count-lines (point) (marker-position (mark-marker))))
         (chars (abs (- (point) (marker-position (mark-marker))))))
      (emacsvox-icon 'mark-object)
      (message
       (if (> lines 1)
           (format "Marked S expression spanning %s lines" lines)
         (format "marked S expression containing %s characters" chars))))))

(advice-add 'mark-sexp :after #'ems--mark-sexp-after)

(defun ems--mark-end-of-sentence-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'mark-end-of-sentence :after
            #'ems--mark-end-of-sentence-after)

;;;  emacs registers

(defun ems--point-to-register-after (&rest _)
  "Produce auditory icon to indicate mark set."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (if current-prefix-arg
        (message "Stored current frame configuration")
      (emacsvox-speak-line))))

(advice-add 'point-to-register :after #'ems--point-to-register-after)

(defun ems--copy-to-register-after (&rest _)
  "Acknowledge the copy."
  (when (ems-interactive-p)
    (let
        ((start (ad-get-arg 1)) (end (ad-get-arg 2))
         (register (ad-get-arg 0)) (lines nil) (chars nil))
      (setq lines (count-lines start end) chars (abs (- start end)))
      (if (> lines 1)
          (dtk-notify
           (format "Copied %s lines to register %c" lines register))
        (dtk-notify
         (format "Copied %s characters to register %c" chars register))))))

(advice-add 'copy-to-register :after #'ems--copy-to-register-after)

(defun ems--view-register-after (&rest _)
  "Speak displayed contents."
  (when (ems-interactive-p)
    (with-current-buffer "*Output*"
      (dtk-speak (buffer-string)) (emacsvox-icon 'open-object))))

(advice-add 'view-register :after #'ems--view-register-after)

(defun ems--jump-to-register-after (&rest _)
  "Speak the line you jumped to."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(advice-add 'jump-to-register :after #'ems--jump-to-register-after)

(defun ems--insert-parentheses-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'open-object)))

(advice-add 'insert-parentheses :after #'ems--insert-parentheses-after)

(defun ems--insert-register-after (&rest _)
  "Speak the first line of the inserted text."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'yank-object) (emacsvox-speak-line))))

(advice-add 'insert-register :after #'ems--insert-register-after)

(defun ems--window-configuration-to-register-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Copied window configuration to register %c"
             (ad-get-arg 0))))

(advice-add 'window-configuration-to-register :after
            #'ems--window-configuration-to-register-after)

(cl-loop
 for f in
 '(frameset-to-register frame-configuration-to-register)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (message "Copied frame  configuration to register %c" (ad-get-arg 0))))))

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
  (dtk-stop 'all)
  (let ((inhibit-field-text-motion t))
    (setq emacsvox-pronounce-table emacsvox-minibuffer-dictionary)
    (puthash  default-directory "" emacsvox-pronounce-table)
    (emacsvox-icon 'open-object)
    (when minibuffer-default (emacsvox-icon 'help))
    (tts-with-punctuations
     'all
     (dtk-notify
      (concat
       (buffer-string)
       (if (stringp minibuffer-default) minibuffer-default ""))))))

(add-hook 'minibuffer-setup-hook 'emacsvox-minibuffer-setup-hook 'at-end)

(defun emacsvox-minibuffer-exit-hook ()
  "Actions performed when exiting the minibuffer with Emacsvox loaded."
  (dtk-stop 'all)
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

(cl-loop
 for f in
 '(occur-prev occur-next occur-mode-goto-occurrence)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'large-movement)))))

(defun ems--occur-mode-display-occurrence-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Displayed occurrence in other window")))

(advice-add 'occur-mode-display-occurrence :after
            #'ems--occur-mode-display-occurrence-after)

;;;  abbrev mode advice

(defun ems--abbrev-edit-save-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object) (dtk-speak "Saved Abbrevs")))

(advice-add 'abbrev-edit-save-buffer :after
            #'ems--abbrev-edit-save-buffer-after)

(defun ems--edit-abbrevs-redefine-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Redefined abbrevs")))

(advice-add 'edit-abbrevs-redefine :after
            #'ems--edit-abbrevs-redefine-after)

(defun ems--list-abbrevs-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Displayed abbrevs in other window.")))

(advice-add 'list-abbrevs :after #'ems--list-abbrevs-after)

(defun ems--edit-abbrevs-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'edit-abbrevs :after #'ems--edit-abbrevs-after)

(defun ems--expand-abbrev-around (orig-fun &rest args)
  "Speak what you expanded."
  (let ((result (apply orig-fun args)))
    (when buffer-read-only (dtk-speak "Buffer is read-only. "))
    (cond
     ((ems-interactive-p)
      (let ((start (save-excursion (backward-word 1) (point))))
        (apply orig-fun args)
        (dtk-speak (buffer-substring start (point)))))
     (t (apply orig-fun args)))
    result))

(advice-add 'expand-abbrev :around #'ems--expand-abbrev-around)

(defun ems--abbrev-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button)
    (message "Turned %s abbrev mode" (if abbrev-mode "on" "off"))))

(advice-add 'abbrev-mode :after #'ems--abbrev-mode-after)

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

(defun ems--describe-key-briefly-around (orig-fun &rest args)
  "Speak what you displayed"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((emacsvox-speak-messages nil))
        (apply orig-fun args)
        (dtk-speak (ems-canonicalize-key-description result))))
     (t (apply orig-fun args)))
    result))

(advice-add 'describe-key-briefly :around
            #'ems--describe-key-briefly-around)

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

(defun ems--where-is-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (dtk-speak (ems--get-where-is (ad-get-arg 0)))))

(advice-add 'where-is :after #'ems--where-is-after)

;;;  apropos and friends
(cl-loop
 for f in
 '(
   apropos apropos-char apropos-library
   apropos-unicode apropos-user-option apropos-value apropos-variable
   apropos-command apropos-documentation)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Provide an auditory icon."
     (when (ems-interactive-p)
       (emacsvox-icon 'help)
       (message "Displayed apropos in other window.")))))

(defun ems--apropos-follow-after (&rest _)
  "Speak the help you displayed."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-help)))

(advice-add 'apropos-follow :after #'ems--apropos-follow-after)

;;;  toggling debug state

(defun ems--toggle-debug-on-error-after (&rest _)
  "Produce an auditory icon."
  (when (ems-interactive-p)
    (if debug-on-error (emacsvox-icon 'on) nil (emacsvox-icon 'off))
    (message "Turned %s debug on error" debug-on-error)))

(advice-add 'toggle-debug-on-error :after
            #'ems--toggle-debug-on-error-after)

(defun ems--toggle-debug-on-quit-after (&rest _)
  "Produce an auditory icon."
  (when (ems-interactive-p)
    (if debug-on-error (emacsvox-icon 'on) nil (emacsvox-icon 'off))
    (message "Turned %s debug on quit" debug-on-quit)))

(advice-add 'toggle-debug-on-quit :after
            #'ems--toggle-debug-on-quit-after)

;;;  alert if entering override mode

(defun ems--overwrite-mode-after (&rest _)
  "Provide auditory indication that overwrite mode has changed."
  (when (ems-interactive-p)
    (emacsvox-icon 'warn-user)
    (message "Turned %s overwrite mode" (or overwrite-mode "off"))))

(advice-add 'overwrite-mode :after #'ems--overwrite-mode-after)

;;;  Options mode and custom

(defun ems--customize-after (&rest _)
  "Provide status update."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'customize :after #'ems--customize-after)

(defun ems--customize-save-variable-around (orig-fun &rest args)
  "Silence chatter."
  (ems-with-messages-silenced
   (let ((dtk-quiet t)) (apply orig-fun args))))

(advice-add 'customize-save-variable :around
            #'ems--customize-save-variable-around)

;;;  transient mark mode

(defun ems--transient-mark-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon (if transient-mark-mode 'on 'off))
    (message "Turned %s transient mark."
             (if transient-mark-mode "on" "off"))))

(advice-add 'transient-mark-mode :after
            #'ems--transient-mark-mode-after)

;;;  provide auditory icon when window config changes

;;;  mail aliases

(defun ems--expand-mail-aliases-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((end (point)) (start (re-search-backward " " nil t)))
      (message (buffer-substring start end))
      (emacsvox-icon 'select-object))))

(advice-add 'expand-mail-aliases :after
            #'ems--expand-mail-aliases-after)

;;;  elint

(cl-loop
 for f in
 '(elint-current-buffer elint-file elint-defun)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Silence messages while elint is running."
     (cond
      ((ems-interactive-p)
       (ems-with-messages-silenced
        ad-do-it
        (emacsvox-icon 'task-done)
        (message "Displayed lint results in other window. ")))
      (t ad-do-it))
     ad-return-value)))

;;;  advice button creation to add voicification:

(cl-loop
 for f in
 '(make-button make-text-button)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Adds property personality."
     (let ((start (ad-get-arg 0))
           (end (ad-get-arg 1)))
       (with-silent-modifications
         (condition-case
             nil
             (let ((inhibit-read-only t))
               (put-text-property start end 'auditory-icon 'button))
           (error nil)))))))

(defun ems--push-button-after (&rest _)
  "Produce auditory icon."
  (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'push-button :after #'ems--push-button-after)

;;;  silence whitespace cleanup:

(cl-loop
 for f in
 '(whitespace-cleanup whitespace-cleanup-internal)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Silence messages."
     (ems-with-messages-silenced
      ad-do-it
      ad-return-value))))

;;;  advice Finder:

(defun ems--finder-commentary-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-buffer) (emacsvox-icon 'open-object)))

(advice-add 'finder-commentary :after #'ems--finder-commentary-after)

(defun ems--finder-mode-after (&rest _)
  "speak"
  (when
      (and (boundp 'finder-known-keywords)
           (not (eq 'emacsvox (caar finder-known-keywords))))
    (push (cons 'emacsvox "Audio Desktop") finder-known-keywords))
  (emacsvox-icon 'open-object) (emacsvox-speak-mode-line))

(advice-add 'finder-mode :after #'ems--finder-mode-after)

(defun ems--finder-exit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (with-current-buffer (window-buffer (selected-window))
      (emacsvox-speak-mode-line))))

(advice-add 'finder-exit :after #'ems--finder-exit-after)

;;;  display world time

(defun ems--world-clock-after (&rest _)
  "Speak what you displayed."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (save-current-buffer
      (set-buffer "*wclock*") (emacsvox-speak-buffer))))

(advice-add 'world-clock :after #'ems--world-clock-after)

;;;  browse-url

(cl-loop for f in
         '(browse-url-of-buffer browse-url-of-region)
         do
         (eval
          `(defadvice ,f (around emacsvox pre act comp)
             "Automatically speak results of rendering."
             (cond
              ((ems-interactive-p)
               (emacsvox-icon 'open-object)
               (emacsvox-eww-autospeak)
               ad-do-it)
              (t ad-do-it))
             ad-return-value)))

;;;  Cue input method changes

(defun ems--toggle-input-method-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon (if current-input-method 'on 'off))
    (dtk-speak
     (format "Current input method is %s"
             (or current-input-method "none")))))

(advice-add 'toggle-input-method :after
            #'ems--toggle-input-method-after)

;;;  silence midnight cleanup:

(defun ems--clean-buffer-list-around (orig-fun &rest args)
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'clean-buffer-list :around #'ems--clean-buffer-list-around)

;;;  Splash Screen:

(cl-loop
 for f in
 '(about-emacs display-about-screen)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (with-current-buffer (window-buffer (selected-window))
         (emacsvox-speak-buffer))))))

(defun ems--exit-splash-screen-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'exit-splash-screen :after #'ems--exit-splash-screen-after)

;;;  copyright commands:

(cl-loop
 for f in
 '(copyright copyright-update)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)))))

(defun ems--copyright-update-directory-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'copyright-update-directory :after
            #'ems--copyright-update-directory-after)

;;;  Asking Questions:

(defun ems--yes-or-no-p-around (orig-fun &rest args)
  "Play auditory icon."
  (emacsvox-icon 'ask-question)
  (let ((result (apply orig-fun args)))
    (emacsvox-icon (if result 'yes-answer 'no-answer))
    result))

(advice-add 'yes-or-no-p :around #'ems--yes-or-no-p-around)

(defun ems--y-or-n-p-around (orig-fun &rest args)
  "Play auditory icon."
  (emacsvox-icon 'ask-short-question)
  (let ((result (apply orig-fun args)))
    (emacsvox-icon (if result 'y-answer 'n-answer))
    result))

(advice-add 'y-or-n-p :around #'ems--y-or-n-p-around)

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

(defun ems--ask-user-about-lock-help-after (&rest _)
  "Play auditory icon." (emacsvox-icon 'help))

(advice-add 'ask-user-about-lock-help :after
            #'ems--ask-user-about-lock-help-after)

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

(defun ems--timer-list-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'timer-list :after #'ems--timer-list-after)

;;; list-timers:

(defun ems--list-timers-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'list-timers :after #'ems--list-timers-after)

;;; find-library:

(defun ems--find-library-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'find-library :after #'ems--find-library-after)

;;; log-edit-done

(defun ems--log-edit-done-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'close-object)))

(advice-add 'log-edit-done :after #'ems--log-edit-done-after)

;;;  advice find-func etc.

(cl-loop
 for f in
 '(
   find-function find-function-at-point find-variable
   find-variable-at-point find-function-on-key)
 do
 (eval
  `(defadvice ,f  (after emacsvox pre act comp)
     "Speak current line"
     (when  (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

;;; Advice Semantic:

(defun ems--semantic-complete-symbol-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (let ((prior (point)) (dtk-stop-immediately t))
      (emacsvox-kill-buffer-carefully "*Completions*")
      (apply orig-fun args)
      (if (> (point) prior)
          (tts-with-punctuations 'all (emacsvox-speak-rest-of-buffer))
        (emacsvox-speak-completions-if-available))
      result)
    result))

(advice-add 'semantic-complete-symbol :around
            #'ems--semantic-complete-symbol-around)

(provide 'emacsvox-cedet)

;;;  advice Imenu

(defun ems--imenu-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'imenu :after #'ems--imenu-after)

;;; Advice property search

(cl-loop
 for f in
 '(text-property-search-backward text-property-search-forward)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak range."
     (when (ems-interactive-p)
       (unless ad-return-value
         (emacsvox-icon 'warn-user)
         (emacsvox-speak-line))
       (when-let* ((m ad-return-value))
         (emacsvox-speak-region
          (prop-match-beginning m) (prop-match-end m))
         (emacsvox-icon 'select-object))))))

;;; ielm: header-line

(defun ems--ielm-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    
    (setq header-line-format
          '((:eval
             (concat
              (propertize "Interactive Elisp" 'personality
                          voice-annotate)
              (format "On %s" (buffer-name ielm-working-buffer))))))
    (emacsvox-icon 'open-object) (emacsvox-speak-header-line)))

(advice-add 'ielm :after #'ems--ielm-after)

;;; Help Navigation:

(cl-loop
 for f in
 '(help-goto-next-page help-goto-previous-page)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'scroll)
       (emacsvox-speak-line)))))

;;; C-x x commands

(defun emacsvox--advice-revert-buffer-quick-after (&rest _)
  "speak."
  (when (ems-interactive-p 'revert-buffer-quick)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add
 'revert-buffer-quick :after #'emacsvox--advice-revert-buffer-quick-after
 '((name . emacsvox)))

;;; Battery:

(defun ems--battery-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (ems-with-messages-silenced (apply orig-fun args)
                                  (tts-with-punctuations 'some
                                                         (dtk-speak
                                                          result))))
     (t (apply orig-fun args)))
    result))

(advice-add 'battery :around #'ems--battery-around)

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

(defun ems--spinner-start-after (&rest _)
  "Icon." (emacsvox-icon 'repeat-start))

(advice-add 'spinner-start :after #'ems--spinner-start-after)

(defun ems--spinner-stop-after (&rest _)
  "Icon." (emacsvox-icon 'repeat-stop))

(advice-add 'spinner-stop :after #'ems--spinner-stop-after)

;;; Rectangle Motion

(cl-loop
 for f in
 '(rectangle-next-line rectangle-previous-line)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)))))

(defun ems--rectangle-mark-mode-after (&rest _)
  "speak." 
  (when (ems-interactive-p)
    (dtk-notify
     (format "Turned %s rectangle mark mode"
             (if rectangle-mark-mode "on" "off")))
    (emacsvox-icon (if rectangle-mark-mode 'on 'off))))

(advice-add 'rectangle-mark-mode :after
            #'ems--rectangle-mark-mode-after)

(cl-loop
 for f in
 '(
   rectangle-backward-char rectangle-forward-char
   rectangle-right-char rectangle-left-char)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-char t )))))
;;; Compose Mail:

(defun ems--compose-mail-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'compose-mail :after #'ems--compose-mail-after)

;;; Speaking Spaces:

(defun ems--cycle-spacing-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-speak-spaces)))

(advice-add 'cycle-spacing :after #'ems--cycle-spacing-after)

(defun ems--just-one-space-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-speak-spaces)))

(advice-add 'just-one-space :after #'ems--just-one-space-after)

;;; psession:
(with-eval-after-load
    "psession"
  (defadvice psession--dump-object-to-file-save-alist
      (around emacsvox pre act comp)
    "Silence."
    (ems-with-messages-silenced ad-do-it)))

(provide 'emacsvox-advice)

;;;  end of file
