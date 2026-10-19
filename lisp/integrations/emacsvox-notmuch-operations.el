;;; emacsvox-notmuch-operations.el --- Notmuch tag and archive outcomes -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop notmuch
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

;; Notmuch tag and archive outcomes.
;; Load through `emacsvox-notmuch'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-notmuch--leading-compatibility-actions "emacsvox-notmuch" (icon))
(declare-function emacsvox-notmuch--prepare-field-text "emacsvox-notmuch" (value label &optional transform))
(declare-function emacsvox-notmuch--status-compatibility-actions "emacsvox-notmuch" (result status-icons occasion &optional include-attachments))
(declare-function emacsvox-notmuch--submit-content "emacsvox-notmuch" (text facts occasion compatibility-actions &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--submit-text-feedback "emacsvox-notmuch" (facts occasion icon text &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--view-summary "emacsvox-notmuch" nil)
(declare-function emacsvox-notmuch-format-search-result "emacsvox-notmuch-search" (result))
(declare-function emacsvox-notmuch-format-show-message "emacsvox-notmuch-show" (message))
(declare-function emacsvox-notmuch-message-facts "emacsvox-notmuch" (message &optional event))
(defvar emacsvox-notmuch-search-status-icons)
(defvar emacsvox-notmuch-show-status-icons)
(defvar notmuch-archive-tags)
(declare-function notmuch-interactive-region "notmuch-lib" ())
(declare-function notmuch-search-foreach-result "notmuch" (beg end fn))
(declare-function notmuch-search-get-result "notmuch" (&optional pos))
(declare-function notmuch-show-get-message-properties "notmuch-show" ())
(declare-function notmuch-show-mapc "notmuch-show" (function))
(declare-function notmuch-show-move-to-message-top "notmuch-show" ())
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox-notmuch--tag-change-summary (tag-changes)
  "Return a concise description of Notmuch TAG-CHANGES."
  (let (added removed changed)
    (dolist (change tag-changes)
      (cond
       ((string-prefix-p "+" change)
        (push (substring change 1) added))
       ((string-prefix-p "-" change)
        (push (substring change 1) removed))
       (t (push change changed))))
    (string-join
     (delq
      nil
      (list
       (when added
         (format
          "Added %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse added))
           ", ")))
       (when removed
         (format
          "Removed %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse removed))
           ", ")))
       (when changed
         (format
          "Changed %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse changed))
           ", ")))))
     "; ")))

(defun emacsvox-notmuch--tag-change-name (tag-change)
  "Return the bare tag name from TAG-CHANGE."
  (if (string-match-p "\\`[+-]" tag-change)
      (substring tag-change 1)
    tag-change))

(defun emacsvox-notmuch--ordinary-tag-changes (tag-changes status-icons)
  "Return TAG-CHANGES not represented by STATUS-ICONS."
  (cl-remove-if
   (lambda (change)
     (assoc
      (emacsvox-notmuch--tag-change-name change)
      status-icons))
   tag-changes))

(defun emacsvox-notmuch--removed-status-p (tag-changes status-icons)
  "Return non-nil when TAG-CHANGES removes a status in STATUS-ICONS."
  (cl-some
   (lambda (change)
     (and
      (string-prefix-p "-" change)
      (assoc (substring change 1) status-icons)))
   tag-changes))

(defun emacsvox-notmuch--tag-operation-feedback
    (tag-changes status-icons item &optional show-message-p)
  "Submit TAG-CHANGES and updated Notmuch ITEM as one transaction.

STATUS-ICONS keeps represented statuses nonverbal.  When SHOW-MESSAGE-P is
non-nil, ITEM is a Show message with attachment state; otherwise it is a
search result."
  (when tag-changes
    (let* ((ordinary
            (emacsvox-notmuch--ordinary-tag-changes
             tag-changes status-icons))
           (change-summary
            (and ordinary
                 (emacsvox-notmuch--tag-change-summary ordinary)))
           (item-summary
            (and item
                 (if show-message-p
                     (emacsvox-notmuch-format-show-message item)
                   (emacsvox-notmuch-format-search-result item))))
           (content
            (string-join
             (delq nil (list change-summary item-summary))
             "\n"))
           (facts
            (append
             (if item
                 (emacsvox-notmuch-message-facts
                  item 'message-marked)
               '(:role message :events (message-marked)))
             '(:mail-action-kind tag)))
           (actions
            (append
             (when ordinary
               (list
                (emacsvox-aural-compatibility-icon 'task-done)))
             (when
                 (emacsvox-notmuch--removed-status-p
                  tag-changes status-icons)
               (list
                (emacsvox-aural-compatibility-icon
                 'deselect-object)))
             (and
              item
              (emacsvox-notmuch--status-compatibility-actions
               item status-icons 'state-change show-message-p)))))
      (emacsvox-notmuch--submit-content
       content facts 'state-change actions))))

(defun emacsvox-notmuch--tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch result."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-search-status-icons
   (notmuch-search-get-result)))

(defun emacsvox-notmuch--show-tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch message."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-show-status-icons
   (and
    (eq major-mode 'notmuch-show-mode)
    (notmuch-show-get-message-properties))
   t))

(defun emacsvox-notmuch--current-tags ()
  "Return a copy of the tags at point in a Notmuch search or Show buffer."
  (let ((tags
         (pcase major-mode
           ('notmuch-search-mode
            (plist-get (notmuch-search-get-result) :tags))
           ('notmuch-show-mode
            (plist-get
             (notmuch-show-get-message-properties)
             :tags)))))
    (and tags (copy-sequence tags))))

(defun emacsvox-notmuch--tag-differences (before after)
  "Return Notmuch tag operations that transform BEFORE into AFTER."
  (append
   (mapcar
    (lambda (tag) (concat "+" tag))
    (cl-remove-if (lambda (tag) (member tag before)) after))
   (mapcar
    (lambda (tag) (concat "-" tag))
    (cl-remove-if (lambda (tag) (member tag after)) before))))

(defun emacsvox-notmuch--search-tag-bounds (target arguments)
  "Return the Search bounds targeted by TARGET with ARGUMENTS."
  (if (eq target 'notmuch-search-tag-all)
      (cons (point-min) (point-max))
    (let ((beginning (nth 1 arguments))
          (end (nth 2 arguments)))
      (if (and beginning end)
          (cons beginning end)
        (pcase-let ((`(,region-beginning ,region-end)
                      (notmuch-interactive-region)))
          (cons region-beginning region-end))))))

(defun emacsvox-notmuch--search-tag-snapshot-entry (position)
  "Capture the Search result at POSITION for tag-state comparison."
  (when-let* ((result (notmuch-search-get-result position)))
    (list
     :id (plist-get result :thread)
     :tags (copy-sequence (plist-get result :tags)))))

(defun emacsvox-notmuch--show-tag-snapshot-entry ()
  "Capture the current Show message for tag-state comparison."
  (save-excursion
    (notmuch-show-move-to-message-top)
    (when-let* ((message (notmuch-show-get-message-properties)))
      (list
       :id (plist-get message :id)
       :tags (copy-sequence (plist-get message :tags))))))

(defun emacsvox-notmuch--capture-tag-snapshot
    (target arguments &optional all-show-messages)
  "Capture the items whose tags TARGET will change using ARGUMENTS.
When ALL-SHOW-MESSAGES is non-nil, capture every message in a Show buffer."
  (pcase major-mode
    ('notmuch-search-mode
     (pcase-let ((`(,beginning . ,end)
                   (emacsvox-notmuch--search-tag-bounds target arguments))
                  (entries nil))
       (notmuch-search-foreach-result beginning end
         (lambda (position)
           (when-let* ((entry
                        (emacsvox-notmuch--search-tag-snapshot-entry
                         position)))
             (push entry entries))))
       (setq entries (nreverse entries))
       (list
        :buffer (current-buffer)
        :kind 'search
        :identifiable
        (cl-every (lambda (entry) (plist-get entry :id)) entries)
        :entries entries)))
    ('notmuch-show-mode
     (let (entries)
       (if (or all-show-messages
               (eq target 'notmuch-show-tag-all))
           (notmuch-show-mapc
            (lambda ()
              (when-let* ((entry
                           (emacsvox-notmuch--show-tag-snapshot-entry)))
                (push entry entries))))
         (when-let* ((entry (emacsvox-notmuch--show-tag-snapshot-entry)))
           (push entry entries)))
       (setq entries (nreverse entries))
       (list
        :buffer (current-buffer)
        :kind 'show
        :identifiable
        (cl-every (lambda (entry) (plist-get entry :id)) entries)
        :entries entries)))))

(defun emacsvox-notmuch--current-tag-state (snapshot)
  "Return an ID-to-tags table for the buffer in SNAPSHOT."
  (when-let* ((buffer (plist-get snapshot :buffer))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let ((state (make-hash-table :test #'equal)))
        (pcase (plist-get snapshot :kind)
          ('search
           (notmuch-search-foreach-result (point-min) (point-max)
             (lambda (position)
               (when-let* ((result (notmuch-search-get-result position))
                           (id (plist-get result :thread)))
                 (puthash
                  id (copy-sequence (plist-get result :tags)) state)))))
          ('show
           (notmuch-show-mapc
            (lambda ()
              (when-let* ((message (notmuch-show-get-message-properties))
                          (id (plist-get message :id)))
                (puthash
                 id (copy-sequence (plist-get message :tags)) state))))))
        state))))

(defun emacsvox-notmuch--tag-snapshot-result (snapshot)
  "Return authoritative tag differences and availability for SNAPSHOT."
  (let ((state
         (and
          (plist-get snapshot :identifiable)
          (emacsvox-notmuch--current-tag-state snapshot)))
        (missing (make-symbol "missing-tag-target"))
        (available t)
        changes)
    (if (not state)
        (setq available nil)
      (dolist (entry (plist-get snapshot :entries))
        (let ((current (gethash (plist-get entry :id) state missing)))
          (if (eq current missing)
              (setq available nil)
            (setq changes
                  (append
                   changes
                   (emacsvox-notmuch--tag-differences
                    (plist-get entry :tags) current)))))))
    (list :available available :changes (delete-dups changes))))

(defun emacsvox-notmuch--tag-unchanged-feedback ()
  "Report that an interactive Notmuch tag command changed no tags."
  (emacsvox-notmuch--submit-text-feedback
   '(:role message :mail-action-kind tag)
   'state-change nil "Tags unchanged"))

(defun emacsvox-notmuch--direct-tag-state-around
    (target original arguments)
  "Report actual tag changes made by direct TARGET.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((mode major-mode)
          (snapshot (emacsvox-notmuch--capture-tag-snapshot target arguments)))
      (let ((result (apply original arguments)))
        (when (ems-interactive-p target)
          (when snapshot
            (let* ((outcome
                    (emacsvox-notmuch--tag-snapshot-result snapshot))
                   (changes (plist-get outcome :changes)))
              (when (plist-get outcome :available)
                (if changes
                    (pcase mode
                      ('notmuch-search-mode
                       (emacsvox-notmuch--tag-feedback changes))
                      ('notmuch-show-mode
                       (emacsvox-notmuch--show-tag-feedback changes)))
                  (emacsvox-notmuch--tag-unchanged-feedback))))))
        result))))

(defun emacsvox-notmuch--tag-state-around (target original arguments)
  "Report structured tag changes made by TARGET.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (let ((mode major-mode)
        (before (emacsvox-notmuch--current-tags))
        (result (apply original arguments)))
    (when (ems-interactive-p target)
      (let ((changes
             (emacsvox-notmuch--tag-differences
              before
              (emacsvox-notmuch--current-tags))))
        (when changes
          (pcase mode
            ('notmuch-search-mode
             (emacsvox-notmuch--tag-feedback changes))
            ('notmuch-show-mode
             (emacsvox-notmuch--show-tag-feedback changes))))))
    result))

(defun emacsvox--advice-notmuch-tag-jump-around
    (original &rest arguments)
  "Report the tag operation selected from Notmuch's tag menu."
  (emacsvox-notmuch--tag-state-around
   'notmuch-tag-jump original arguments))

(defun emacsvox--advice-notmuch-show-mark-read-around
    (original &rest arguments)
  "Report an interactive Notmuch read-state change."
  (emacsvox-notmuch--tag-state-around
   'notmuch-show-mark-read original arguments))

(defvar emacsvox-notmuch--archive-context nil
  "Dynamically bound state for one user-owned archive operation.")

(defun emacsvox-notmuch--archive-location ()
  "Return the current Notmuch location for movement comparison."
  (let ((mode major-mode))
    (list
     :buffer (current-buffer)
     :mode mode
     :id
     (ignore-errors
       (pcase mode
         ('notmuch-show-mode
          (plist-get (notmuch-show-get-message-properties) :id))
         ('notmuch-search-mode
          (plist-get (notmuch-search-get-result) :thread))))
     :point (point))))

(defun emacsvox-notmuch--archive-location-changed-p (before after)
  "Return non-nil when archive locations BEFORE and AFTER differ."
  (or
   (not (eq (plist-get before :buffer) (plist-get after :buffer)))
   (not (eq (plist-get before :mode) (plist-get after :mode)))
   (let ((before-id (plist-get before :id))
         (after-id (plist-get after :id)))
     (if (or before-id after-id)
         (not (equal before-id after-id))
       (/= (plist-get before :point) (plist-get after :point))))))

(defun emacsvox-notmuch--record-archive-snapshot (snapshot)
  "Record the actual result of SNAPSHOT in the active archive context."
  (when (and emacsvox-notmuch--archive-context snapshot)
    (let ((outcome (emacsvox-notmuch--tag-snapshot-result snapshot)))
      (setf (alist-get 'observed emacsvox-notmuch--archive-context) t)
      (unless (plist-get outcome :available)
        (setf (alist-get 'complete emacsvox-notmuch--archive-context) nil))
      (when (plist-get outcome :changes)
        (setf (alist-get 'changed emacsvox-notmuch--archive-context) t)))))

(defun emacsvox-notmuch--archive-outcome (context)
  "Return the truthful archive outcome represented by CONTEXT."
  (cond
   ((not (alist-get 'configured context)) 'not-configured)
   ((alist-get 'changed context) 'changed)
   ((and (alist-get 'observed context)
         (alist-get 'complete context))
    'unchanged)))

(defun emacsvox-notmuch--archive-feedback
    (object unarchive outcome moved)
  "Report OUTCOME for archiving OBJECT and any destination MOVED to.
When UNARCHIVE is non-nil, report the reverse operation."
  (let* ((show-message-p (eq major-mode 'notmuch-show-mode))
         (item
          (and
           (or (eq outcome 'changed) moved)
           (pcase major-mode
             ('notmuch-show-mode
              (notmuch-show-get-message-properties))
             ('notmuch-search-mode
              (notmuch-search-get-result)))))
         (confirmation
          (pcase outcome
            ('changed
             (format
              "%s %s"
              (if unarchive "Unarchived" "Archived")
              (symbol-name object)))
            ('unchanged "Archive tags unchanged")
            ('not-configured "Archive tags are not configured")))
         (item-summary
          (and
           item
           (if show-message-p
               (emacsvox-notmuch-format-show-message item)
             (emacsvox-notmuch-format-search-result item))))
         (destination-summary
          (or
           item-summary
           (and moved
                (if (eq major-mode 'notmuch-search-mode)
                    "End of search results"
                  (emacsvox-notmuch--view-summary)))))
         (facts
          (append
           (if (eq object 'thread)
               '(:role message-thread)
             '(:role message))
           '(:mail-action-kind archive)
           (and (eq outcome 'changed)
                '(:events (operation-completed)))))
         (actions
          (append
           (and
            (eq outcome 'changed)
            (emacsvox-notmuch--leading-compatibility-actions
             (if unarchive 'open-object 'close-object)))
           (and
            item
            (emacsvox-notmuch--status-compatibility-actions
             item
             (if show-message-p
                 emacsvox-notmuch-show-status-icons
               emacsvox-notmuch-search-status-icons)
             'state-change
             show-message-p)))))
    (when (or confirmation destination-summary)
      (emacsvox-notmuch--submit-content
       (string-join
        (delq nil (list confirmation destination-summary))
        "\n")
       facts 'state-change actions))))

(defun emacsvox-notmuch--archive-state-around
    (target object original arguments all-show-messages observe-state)
  "Report the actual archive state change made by TARGET on OBJECT.
Call ORIGINAL once with ARGUMENTS.  ALL-SHOW-MESSAGES means OBJECT spans the
whole Show buffer.  When OBSERVE-STATE is non-nil, compare the targeted tags.
Nested archive commands contribute state to the outer interactive owner
instead of producing their own feedback."
  (let* ((owner
          (and
           (null emacsvox-notmuch--archive-context)
           (eq ems--interactive-fn-name target)))
         (context
          (or
           emacsvox-notmuch--archive-context
           (and
            owner
            (list
             (cons 'configured (and notmuch-archive-tags t))
             (cons 'observed nil)
             (cons 'complete t)
             (cons 'changed nil))))))
    (if (not context)
        (apply original arguments)
      (let* ((configured (alist-get 'configured context))
             (snapshot
              (and
               configured observe-state
               (emacsvox-notmuch--capture-tag-snapshot
                target arguments all-show-messages)))
             (before-location
              (and owner (emacsvox-notmuch--archive-location)))
             (emacsvox-notmuch--archive-context context)
             (result (apply original arguments)))
        (when
            (and
             configured snapshot
             (or
              (not owner)
              (not (alist-get 'observed context))))
          (emacsvox-notmuch--record-archive-snapshot snapshot))
        (when (and owner (ems-interactive-p target))
          (emacsvox-notmuch--archive-feedback
           object (car arguments)
           (emacsvox-notmuch--archive-outcome context)
           (emacsvox-notmuch--archive-location-changed-p
            before-location (emacsvox-notmuch--archive-location))))
        result))))

(defun emacsvox--advice-notmuch-search-archive-thread-around
    (original &rest arguments)
  "Report actual Search archive state around ORIGINAL with ARGUMENTS."
  (emacsvox-notmuch--archive-state-around
   'notmuch-search-archive-thread 'thread original arguments nil t))

(provide 'emacsvox-notmuch-operations)
;;; emacsvox-notmuch-operations.el ends here
