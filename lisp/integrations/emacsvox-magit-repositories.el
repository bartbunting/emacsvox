;;; emacsvox-magit-repositories.el --- Magit repository-list feedback -*- lexical-binding: t; -*-

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

;; Magit repository-list feedback.
;; Load through `emacsvox-magit'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-magit--collect-finished-processes "emacsvox-magit" nil)
(defvar emacsvox-magit--git-processes)
(defvar emacsvox-magit--git-results)
(declare-function emacsvox-magit--line-content "emacsvox-magit" (&optional visibility))
(declare-function emacsvox-magit--submit-text "emacsvox-magit" (content facts occasion &optional icon icon-phase))
(declare-function emacsvox-magit-repository-facts "emacsvox-magit" (operation &optional event))
(declare-function emacsvox-magit-view-facts "emacsvox-magit" (kind event))
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox-magit--repolist-id ()
  "Return the repository identifier at point, if any."
  (and
   (fboundp 'tabulated-list-get-id)
   (ignore-errors (tabulated-list-get-id))))

(defun emacsvox-magit--repository-label (repository)
  "Return a concise label for REPOSITORY."
  (if (and (stringp repository) (> (length repository) 0))
      (file-name-nondirectory (directory-file-name repository))
    "repository"))

(defun emacsvox-magit--repolist-result-content (label)
  "Return LABEL followed by the newly focused repository row."
  (let ((line (emacsvox-magit--line-content)))
    (concat
     (propertize (concat label ". ") 'personality 'voice-annotate)
     line)))

(defun emacsvox-magit--call-repolist-tag
    (original target operation event icon arguments)
  "Call ORIGINAL with ARGUMENTS and present a repository tag change.
TARGET, OPERATION, EVENT, and ICON describe the interaction."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let* ((repository (emacsvox-magit--repolist-id))
           (result (apply original arguments)))
      (when (ems-interactive-p target)
        (emacsvox-magit--submit-text
         (emacsvox-magit--repolist-result-content
          (format
           "%s %s"
           (if (eq operation 'mark) "Marked" "Unmarked")
           (emacsvox-magit--repository-label repository)))
         (emacsvox-magit-repository-facts operation event)
         'state-change icon))
      result)))

(defun emacsvox--advice-magit-repolist-mark-around
    (original &rest arguments)
  "Present an interactively marked repository."
  (emacsvox-magit--call-repolist-tag
   original 'magit-repolist-mark 'mark 'entry-marked
   'mark-object arguments))

(defun emacsvox--advice-magit-repolist-unmark-around
    (original &rest arguments)
  "Present an interactively unmarked repository."
  (emacsvox-magit--call-repolist-tag
   original 'magit-repolist-unmark 'unmark 'entry-unmarked
   'unmark-object arguments))

(defun emacsvox--advice-magit-list-repositories-after (&rest _)
  "Present a repository list opened by the user."
  (when (ems-interactive-p 'magit-list-repositories)
    (emacsvox-magit--submit-text
     (emacsvox-magit--repolist-result-content "Repository list")
     (emacsvox-magit-view-facts 'repositories 'vcs-view-opened)
     'navigation 'open-object)))

(defun emacsvox--advice-magit-repolist-status-after (&rest _)
  "Present a status buffer opened from a repository list."
  (when (ems-interactive-p 'magit-repolist-status)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (append
      (emacsvox-magit-view-facts 'status 'vcs-view-opened)
      '(:vcs-operation open-status))
     'navigation 'open-object)))

(defun emacsvox--advice-magit-repolist-refresh-after (&rest _)
  "Present a repository-list refresh requested through `revert-buffer'."
  (when
      (and
       (derived-mode-p 'magit-repolist-mode)
       (ems-interactive-p 'revert-buffer))
    (emacsvox-magit--submit-text
     (emacsvox-magit--repolist-result-content "Refreshed repositories")
     (emacsvox-magit-repository-facts 'refresh 'refresh-completed)
     'notification 'task-done)))

(defun emacsvox-magit--repository-set-description (repositories)
  "Return a concise description of REPOSITORIES."
  (if (eq repositories 'all)
      "all displayed repositories"
    (format
     "%d %s"
     (length repositories)
     (if (= (length repositories) 1) "repository" "repositories"))))

(defun emacsvox--advice-magit-repolist-fetch-around
    (original repositories &rest arguments)
  "Present aggregate fetch lifecycle for REPOSITORIES."
  (if (not (ems-interactive-p 'magit-repolist-fetch))
      (apply original repositories arguments)
    (let ((emacsvox-magit--git-results (vector 0 nil))
          (emacsvox-magit--git-processes nil)
          (description
           (emacsvox-magit--repository-set-description repositories))
          (facts
           (append
            (emacsvox-magit-view-facts 'repositories nil)
            '(:vcs-operation fetch))))
      (emacsvox-magit--submit-text
       (format "Fetching %s" description)
       facts 'notification 'progress)
      (condition-case error-data
          (let* ((result (apply original repositories arguments))
                 (_ (emacsvox-magit--collect-finished-processes))
                 (total (aref emacsvox-magit--git-results 0))
                 (failed (length (aref emacsvox-magit--git-results 1))))
            (emacsvox-magit--submit-text
             (cond ((zerop total) "No repositories fetched")
                   ((zerop failed) (format "Fetched %s" description))
                   ((= failed total) (format "Failed to fetch %s" description))
                   (t (format "Fetched %d of %d repositories; %d failed"
                              (- total failed) total failed)))
             (plist-put
              (copy-sequence facts)
              :events (list (if (and (> total 0) (zerop failed))
                                'operation-completed 'operation-failed)))
             'notification (if (and (> total 0) (zerop failed))
                               'task-done 'warn-user))
            result)
        (error
         (emacsvox-magit--submit-text
          (format "Failed to fetch %s" description)
          (plist-put
           (copy-sequence facts)
           :events '(operation-failed))
          'notification 'warn-user)
         (signal (car error-data) (cdr error-data)))))))

(defun emacsvox--advice-magit-repolist-find-file-other-frame-around
    (original repositories file &rest arguments)
  "Present FILE opened across REPOSITORIES."
  (if
      (not
       (ems-interactive-p 'magit-repolist-find-file-other-frame))
      (apply original repositories file arguments)
    (let* ((result (apply original repositories file arguments))
           (description
            (emacsvox-magit--repository-set-description repositories)))
      (emacsvox-magit--submit-text
       (format "Opened %s in %s" file description)
       (append
        (emacsvox-magit-view-facts 'repositories 'operation-completed)
        '(:vcs-operation find-file))
       'state-change 'open-object)
      result)))

(defconst emacsvox-magit--repolist-around-advice
  '((magit-repolist-mark
     emacsvox--advice-magit-repolist-mark-around)
    (magit-repolist-unmark
     emacsvox--advice-magit-repolist-unmark-around)
    (magit-repolist-fetch
     emacsvox--advice-magit-repolist-fetch-around)
    (magit-repolist-find-file-other-frame
     emacsvox--advice-magit-repolist-find-file-other-frame-around))
  "Around advice for repository-list interactions.")

(defconst emacsvox-magit--repolist-after-advice
  '((magit-list-repositories
     emacsvox--advice-magit-list-repositories-after)
    (magit-repolist-status
     emacsvox--advice-magit-repolist-status-after)
    (magit-repolist-refresh
     emacsvox--advice-magit-repolist-refresh-after))
  "After advice for repository-list interactions.")

(provide 'emacsvox-magit-repositories)
;;; emacsvox-magit-repositories.el ends here
