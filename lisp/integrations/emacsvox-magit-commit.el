;;; emacsvox-magit-commit.el --- Magit commit-message feedback -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop magit
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

;; Magit commit-message feedback.
;; Load through `emacsvox-magit'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-magit--rebase-operation-label "emacsvox-magit-rebase" (operation))
(declare-function emacsvox-magit--submit-text "emacsvox-magit" (content facts occasion &optional icon icon-phase))
(declare-function emacsvox-magit-view-facts "emacsvox-magit" (kind event))
(defvar git-commit-mode)
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defconst emacsvox-magit--commit-history-targets
  '((git-commit-prev-message previous-message select-object)
    (git-commit-next-message next-message select-object)
    (git-commit-search-message-backward search-backward search-hit)
    (git-commit-search-message-forward search-forward search-hit))
  "Commit-message history commands, operations, and cues.")

(defconst emacsvox-magit--commit-trailer-targets
  '((git-commit-ack ack "Acked-by")
    (git-commit-modified modified "Modified-by")
    (git-commit-review review "Reviewed-by")
    (git-commit-signoff signoff "Signed-off-by")
    (git-commit-test test "Tested-by")
    (git-commit-cc cc "Cc")
    (git-commit-reported reported "Reported-by")
    (git-commit-suggested suggested "Suggested-by")
    (git-commit-co-authored co-authored "Co-authored-by")
    (git-commit-co-developed co-developed "Co-developed-by"))
  "Commit trailer commands, operations, and displayed labels.")

(defconst emacsvox-magit--commit-insertion-targets
  '((git-commit-insert-changelog-gnu changelog-gnu
     "Inserted GNU changelog")
    (git-commit-insert-changelog-plain changelog-plain
     "Inserted plain changelog"))
  "Commit-message insertion commands and their feedback.")

(defun emacsvox-magit-commit-facts (operation event)
  "Return semantic commit-message facts for OPERATION and EVENT."
  (append
   (list :role 'vcs-commit-message :vcs-operation operation)
   (when event (list :events (list event)))))

(defun emacsvox-magit--commit-message-content ()
  "Return the editable commit message with source properties intact."
  (save-excursion
    (goto-char (point-min))
    (let ((end
           (if
               (and
                (stringp comment-start)
                (re-search-forward
                 (concat "^" (regexp-quote comment-start)) nil t))
               (line-beginning-position)
             (point-max))))
      (string-trim-right
       (buffer-substring (point-min) end)))))

(defun emacsvox-magit--commit-labelled-content (label &optional content)
  "Return LABEL followed by optional commit-message CONTENT."
  (concat
   (propertize
    (concat label (if content ". " "."))
    'personality 'voice-annotate)
   content))

(defun emacsvox-magit--call-commit-history
    (original target operation icon arguments)
  "Call ORIGINAL with ARGUMENTS and present commit history TARGET."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (emacsvox-magit--commit-labelled-content
            (if changed
                (emacsvox-magit--rebase-operation-label operation)
              (format
               "No %s available"
               (downcase
                (emacsvox-magit--rebase-operation-label operation))))
            (and changed (emacsvox-magit--commit-message-content)))
           (emacsvox-magit-commit-facts
            operation
            (if changed 'focus-entered 'operation-failed))
           'navigation
           (if changed icon 'warn-user))))
      result)))

(defun emacsvox-magit--call-commit-trailer
    (original target operation label arguments)
  "Call ORIGINAL with ARGUMENTS and present commit trailer TARGET.
OPERATION and LABEL describe the trailer."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let* ((changed (/= tick (buffer-chars-modified-tick)))
               (name (car arguments))
               (mail (cadr arguments))
               (detail
                (if
                    (and
                     changed
                     (stringp name)
                     (stringp mail))
                    (format "%s: %s <%s>" label name mail)
                  (format "No %s trailer inserted" label))))
          (emacsvox-magit--submit-text
           detail
           (emacsvox-magit-commit-facts
            operation
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'open-object 'warn-user))))
      result)))

(defun emacsvox-magit--call-commit-insertion
    (original target operation label arguments)
  "Call ORIGINAL with ARGUMENTS and present commit insertion TARGET."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (if changed label (format "No %s change" label))
           (emacsvox-magit-commit-facts
            operation
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'open-object 'warn-user))))
      result)))

(defun emacsvox--advice-git-commit-save-message-around
    (original &rest arguments)
  "Present an interactive commit-message save accurately."
  (if (not (eq ems--interactive-fn-name 'git-commit-save-message))
      (apply original arguments)
    (let ((message-content (emacsvox-magit--commit-message-content))
          (result (apply original arguments)))
      (when (ems-interactive-p 'git-commit-save-message)
        (let ((saved (> (length message-content) 0)))
          (emacsvox-magit--submit-text
           (if saved "Saved commit message" "Commit message was not saved")
           (emacsvox-magit-commit-facts
            'save
            (if saved 'operation-completed 'operation-failed))
           'state-change
           (if saved 'save-object 'warn-user))))
      result)))

(defun emacsvox--advice-magit-pop-revision-stack-around
    (original revision toplevel &rest arguments)
  "Present REVISION inserted into a commit message."
  (if
      (or
       (not (bound-and-true-p git-commit-mode))
       (not (eq ems--interactive-fn-name 'magit-pop-revision-stack)))
      (apply original revision toplevel arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original revision toplevel arguments)))
      (when (ems-interactive-p 'magit-pop-revision-stack)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (if changed
               (format "Inserted revision %s" revision)
             "No revision inserted")
           (emacsvox-magit-commit-facts
            'insert-revision
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'yank-object 'warn-user))))
      result)))

(defun emacsvox--advice-magit-diff-while-committing-after (&rest _)
  "Present the commit diff displayed by the user."
  (when (ems-interactive-p 'magit-diff-while-committing)
    (emacsvox-magit--submit-text
     "Displayed changes for this commit"
     (append
      (emacsvox-magit-view-facts 'diff 'vcs-view-opened)
      '(:vcs-operation inspect-commit))
     'navigation 'open-object)))

(defun emacsvox-magit--commit-start-feedback ()
  "Present entry into a Git commit-message editor."
  (emacsvox-magit--submit-text
   "Editing Git commit message"
   (emacsvox-magit-commit-facts 'edit 'vcs-view-opened)
   'state-change 'open-object))

(defun emacsvox-magit--commit-finish-feedback ()
  "Present creation of a Git commit after the repository confirms it."
  (when (ems-interactive-p 'with-editor-finish)
    (emacsvox-magit--submit-text
     "Created Git commit"
     (emacsvox-magit-commit-facts 'finish 'operation-completed)
     'state-change 'task-done)))

(defun emacsvox-magit--commit-cancel-feedback ()
  "Present cancellation of a Git commit message."
  (when (ems-interactive-p 'with-editor-cancel)
    (emacsvox-magit--submit-text
     "Canceled Git commit"
     (emacsvox-magit-commit-facts 'cancel 'operation-completed)
     'state-change 'close-object)))

(defconst emacsvox-magit--commit-around-advice
  (append
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-history-targets)
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-trailer-targets)
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-insertion-targets)
   '((git-commit-save-message
      emacsvox--advice-git-commit-save-message-around)
     (magit-pop-revision-stack
      emacsvox--advice-magit-pop-revision-stack-around)))
  "Around advice for commit-message interactions.")

(defconst emacsvox-magit--commit-after-advice
  '((magit-diff-while-committing
     emacsvox--advice-magit-diff-while-committing-after))
  "After advice for commit-message interactions.")

(provide 'emacsvox-magit-commit)
;;; emacsvox-magit-commit.el ends here
