;;; emacsvox-advice-editing.el --- Core editing feedback -*- lexical-binding: t; -*-

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

;; Core editing feedback.
;; Load through `emacsvox-advice'.  The facade owns activation.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

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

(defun emacsvox--advice-downcase-word-around (original &rest arguments)
  "Present the edit, then speak after `downcase-word'."
  (emacsvox--case-word-around
   'downcase-word 'lowercase "Lower cased final word in buffer"
   original arguments))

(defun emacsvox--advice-capitalize-word-around (original &rest arguments)
  "Present the edit, then speak after `capitalize-word'."
  (emacsvox--case-word-around
   'capitalize-word 'capitalize "Capitalized final word in buffer"
   original arguments))

(defun emacsvox--advice-insert-char-after (character &rest _)
  "Speak char."
  (when (ems-interactive-p 'insert-char)
    (emacsvox-speak-char-name character)))

(defun emacsvox--backward-delete-char-around (target original arguments)
  "Speak before TARGET deletes backward, then call ORIGINAL with ARGUMENTS."
  (when (ems-interactive-p target)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-this-char (preceding-char)))
  (apply original arguments))

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

(defun emacsvox--advice-delete-char-around (original &rest arguments)
  "Speak the character deleted by `delete-char'."
  (emacsvox--delete-char-around 'delete-char original arguments))

(defun emacsvox--advice-kill-word-before (&rest _)
  "Speak word beingkilled."
  (when (ems-interactive-p 'kill-word)
    (save-excursion
      (skip-syntax-forward " ")
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-word 1))))

(defun emacsvox--advice-backward-kill-word-before (&rest _)
  "Speak word beingkilled."
  (when (ems-interactive-p 'backward-kill-word)
    (save-excursion
      (let ((start (point)))
        (forward-word -1)
        (emacsvox-speak-edit-operation 'deletion)
        (emacsvox-speak-region (point) start)))))

(defun emacsvox--advice-kill-sexp-before (&rest _)
  "Speak the killed  sexp."
  (when (ems-interactive-p 'kill-sexp)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-sexp 1)))

(defun emacsvox--advice-kill-sentence-before (&rest _)
  "Speak the kill."
  (when (ems-interactive-p 'kill-sentence)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-line 1)))

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

(defun emacsvox--advice-untabify-after (start end &rest _)
  "Fix NBSP chars."
  (save-excursion
    (save-restriction
      (narrow-to-region start end) (goto-char start)
      (while (re-search-forward (format "[%c]+" 160) end 'no-error)
        (replace-match " ")))))

(defun emacsvox--advice-center-line-after (&optional _count)
  "Announce completion of interactive line centering."
  (when (ems-interactive-p 'center-line)
    (emacsvox-icon 'center)
    (message "Centered current line")))

(defun emacsvox--advice-center-region-after (beginning end)
  "Announce centering the region from BEGINNING to END."
  (when (ems-interactive-p 'center-region)
    (emacsvox-icon 'center)
    (message "Centered current region containing %s lines"
             (count-lines beginning end))))

(defun emacsvox--advice-center-paragraph-after ()
  "Announce completion of interactive paragraph centering."
  (when (ems-interactive-p 'center-paragraph)
    (emacsvox-icon 'center)
    (message "Centered current paragraph")))

(defun emacsvox--advice-fill-region-after (beginning end &rest _)
  "Announce filling the region from BEGINNING to END."
  (when (ems-interactive-p 'fill-region)
    (emacsvox-icon 'fill-object)
    (message "Filled current region containing %s lines"
             (count-lines beginning end))))

(defun emacsvox--advice-comment-dwim-after (&rest _)
  "Speak the affected text after an interactive comment command."
  (when (ems-interactive-p 'comment-dwim)
    (cond
     ((use-region-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))
    (emacsvox-icon 'task-done)))

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

(defun emacsvox--advice-kill-region-around
    (original beginning end &rest arguments)
  "Call ORIGINAL and announce an interactive kill from BEGINNING to END."
  (emacsvox--region-deletion-around
   'kill-region original beginning end arguments))

(defun emacsvox--advice-completion-kill-region-around
    (original beginning end &rest arguments)
  "Call ORIGINAL and announce an interactive completion-region kill.
BEGINNING, END, and ARGUMENTS are passed to ORIGINAL unchanged."
  (emacsvox--region-deletion-around
   'completion-kill-region original beginning end arguments))

(defun emacsvox--advice-kill-ring-save-after (&rest _)
  "Indicate that region has been copied to the kill ring.\nProduce an auditory icon if possible."
  (when (ems-interactive-p 'kill-ring-save)
    (emacsvox-icon 'mark-object)
    (message "region containing %s lines copied to kill ring "
             (count-lines (region-beginning) (region-end)))))

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

(defun emacsvox--advice-upcase-region-after
    (beginning end &optional _region-noncontiguous-p)
  "Announce an interactive upcase from BEGINNING to END."
  (emacsvox--case-region-after
   'upcase-region "Upcased" beginning end))

(defun emacsvox--advice-open-line-after (count)
  "Announce COUNT lines opened by an interactive `open-line'."
  (when (ems-interactive-p 'open-line)
    (emacsvox-icon 'open-object)
    (message "Opened %s blank line%s"
             (if (= count 1) "a" count)
             (if (= count 1) "" "s"))))

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

(provide 'emacsvox-advice-editing)
;;; emacsvox-advice-editing.el ends here
