;;; emacsvox-magit-rebase.el --- Magit rebase feedback -*- lexical-binding: t; -*-

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

;; Magit rebase feedback.
;; Load through `emacsvox-magit'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-magit--line-content "emacsvox-magit" (&optional visibility))
(declare-function emacsvox-magit--section-value "emacsvox-magit" (section property))
(declare-function emacsvox-magit--submit-text "emacsvox-magit" (content facts occasion &optional icon icon-phase))
(declare-function emacsvox-magit-view-facts "emacsvox-magit" (kind event))
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defconst emacsvox-magit--rebase-action-targets
  '((git-rebase-pick pick select-object)
    (git-rebase-drop drop delete-object)
    (git-rebase-reword reword select-object)
    (git-rebase-edit edit select-object)
    (git-rebase-squash squash select-object)
    (git-rebase-squish fixup-edit-current select-object)
    (git-rebase-fixup fixup select-object)
    (git-rebase-alter fixup-use-current select-object)
    (git-rebase-kill-line toggle-comment delete-object)
    (git-rebase-insert insert open-object)
    (git-rebase-exec exec select-object)
    (git-rebase-label label select-object)
    (git-rebase-reset reset select-object)
    (git-rebase-update-ref update-ref select-object)
    (git-rebase-merge merge select-object)
    (git-rebase-merge-toggle-editmsg toggle-merge-message select-object)
    (git-rebase-noop noop select-object)
    (git-rebase-break break select-object)
    (git-rebase-move-line-up move-up large-movement)
    (git-rebase-move-line-down move-down large-movement)
    (git-rebase-undo undo large-movement))
  "Interactive rebase editing commands, operations, and compatibility cues.")

(defconst emacsvox-magit--rebase-view-targets
  '((git-rebase-show-commit open-object)
    (git-rebase-show-or-scroll-up scroll)
    (git-rebase-show-or-scroll-down scroll))
  "Interactive rebase commands that display or scroll a commit.")

(defun emacsvox-magit--rebase-action-symbol ()
  "Return the normalized rebase action at point, if one is recognized."
  (when (fboundp 'git-rebase-current-line)
    (let* ((entry (ignore-errors (git-rebase-current-line)))
           (action (emacsvox-magit--section-value entry 'action))
           (options
            (emacsvox-magit--section-value entry 'action-options)))
      (when (and (stringp action) (> (length action) 0))
        (cond
         ((member action '("f -c" "fixup -c")) 'fixup-edit-message)
         ((member action '("f -C" "fixup -C")) 'fixup-use-message)
         ((and
           (equal action "merge")
           (string-prefix-p "-c " (or options "")))
          'merge-edit-message)
         ((and
           (equal action "merge")
           (string-prefix-p "-C " (or options "")))
          'merge-use-message)
         (t
          (intern
           (replace-regexp-in-string
            "[[:space:]]+" "-"
            (downcase action)))))))))

(defun emacsvox-magit-rebase-facts (operation event)
  "Return semantic facts for rebase OPERATION and EVENT at point."
  (let ((action (emacsvox-magit--rebase-action-symbol)))
    (append
     '(:role vcs-rebase-entry)
     (when operation (list :vcs-operation operation))
     (when action (list :vcs-rebase-action action))
     (when event (list :events (list event))))))

(defun emacsvox-magit--rebase-operation-label (operation)
  "Return a concise spoken label for rebase OPERATION."
  (let ((label
         (replace-regexp-in-string "-" " " (symbol-name operation))))
    (concat (upcase (substring label 0 1)) (substring label 1))))

(defun emacsvox-magit--present-rebase-line
    (operation event occasion icon &optional announcement)
  "Present the current rebase line under OPERATION, EVENT, and OCCASION.
Present compatibility ICON before the line.  ANNOUNCEMENT may be a string
to prepend, or non-nil to prepend the default operation label."
  (let ((content (emacsvox-magit--line-content)))
    (when announcement
      (setq
       content
       (concat
        (propertize
         (format
          "%s. "
          (if (stringp announcement)
              announcement
            (emacsvox-magit--rebase-operation-label operation)))
         'personality 'voice-annotate)
        content)))
    (emacsvox-magit--submit-text
     content
     (emacsvox-magit-rebase-facts operation event)
     occasion icon)))

(defun emacsvox-magit--call-rebase-action
    (original target operation icon arguments)
  "Call ORIGINAL with ARGUMENTS and present interactive rebase TARGET.
OPERATION and ICON describe the requested edit."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (if (= tick (buffer-chars-modified-tick))
            (emacsvox-magit--present-rebase-line
             operation 'operation-failed 'state-change 'warn-user
             (format
              "No %s change"
              (downcase
               (emacsvox-magit--rebase-operation-label operation))))
          (emacsvox-magit--present-rebase-line
           operation 'operation-completed 'state-change icon t)))
      result)))

(defun emacsvox--advice-git-rebase-backward-line-after (&rest _)
  "Present the rebase entry selected by backward movement."
  (when (ems-interactive-p 'git-rebase-backward-line)
    (emacsvox-magit--present-rebase-line
     'move-backward 'focus-entered 'navigation 'select-object)))

(defun emacsvox--advice-git-rebase-forward-line-after (&rest _)
  "Present the rebase entry selected by `forward-line'."
  (when
      (and
       (derived-mode-p 'git-rebase-mode)
       (ems-interactive-p 'forward-line))
    (emacsvox-magit--present-rebase-line
     'move-forward 'focus-entered 'navigation 'select-object)))

(defun emacsvox-magit--rebase-finish-feedback ()
  "Present successful submission of an interactive rebase plan."
  (when (ems-interactive-p 'with-editor-finish)
    (emacsvox-magit--submit-text
     "Submitted interactive rebase"
     (append
      (emacsvox-magit-view-facts 'rebase 'operation-completed)
      '(:vcs-operation finish))
     'state-change 'task-done)))

(defun emacsvox-magit--rebase-cancel-feedback ()
  "Present cancellation of an interactive rebase plan."
  (when (ems-interactive-p 'with-editor-cancel)
    (emacsvox-magit--submit-text
     "Canceled interactive rebase"
     (append
      (emacsvox-magit-view-facts 'rebase 'operation-completed)
      '(:vcs-operation cancel))
     'state-change 'close-object)))

(provide 'emacsvox-magit-rebase)
;;; emacsvox-magit-rebase.el ends here
