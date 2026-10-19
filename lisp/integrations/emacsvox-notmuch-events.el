;;; emacsvox-notmuch-events.el --- Notmuch asynchronous search feedback -*- lexical-binding: t; -*-

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

;; Notmuch asynchronous search feedback.
;; Load through `emacsvox-notmuch'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-notmuch--leading-compatibility-actions "emacsvox-notmuch" (icon))
(declare-function emacsvox-notmuch--status-compatibility-actions "emacsvox-notmuch" (result status-icons occasion &optional include-attachments))
(declare-function emacsvox-notmuch--submit-content "emacsvox-notmuch" (text facts occasion compatibility-actions &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--submit-text-feedback "emacsvox-notmuch" (facts occasion icon text &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch-format-search-result "emacsvox-notmuch-search" (result))
(declare-function emacsvox-notmuch-message-facts "emacsvox-notmuch" (message &optional event))
(defvar emacsvox-notmuch-search-completion-style)
(defvar emacsvox-notmuch-search-status-icons)
(declare-function emacsvox-notmuch-speak-search-result "emacsvox-notmuch-search" (&optional result))
(declare-function emacsvox-notmuch-view-facts "emacsvox-notmuch" (kind action event))
(declare-function notmuch-search-get-result "notmuch" (&optional pos))
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defconst emacsvox-notmuch--search-process-property
  'emacsvox-notmuch-search-completion
  "Process property holding user-owned search completion state.")

(defconst emacsvox-notmuch--search-sentinel-finished-property
  'emacsvox-notmuch-search-sentinel-finished
  "Process property recording that Notmuch finished its search sentinel.")

(defvar-local emacsvox-notmuch--tracked-search-process nil
  "User-owned Notmuch process currently tracked in this search buffer.")

(defun emacsvox-notmuch--search-result-count (&optional buffer)
  "Count structured Notmuch search results in BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (let ((position (point-min))
          (limit (point-max))
          (count 0))
      (while (< position limit)
        (when (get-text-property position 'notmuch-search-result)
          (cl-incf count))
        (setq position
              (or
               (next-single-property-change
                position 'notmuch-search-result nil limit)
               limit)))
      count)))

(defun emacsvox-notmuch--search-request-kind ()
  "Return the completion kind for the current user-owned search request.
Return nil for programmatic searches and the deliberately silent global
refresh command."
  (let ((owner ems--interactive-fn-name))
    (cond
     ((or
       (null owner)
       (eq owner 'notmuch-refresh-all-buffers)
       (eq this-command 'notmuch-refresh-all-buffers))
      nil)
     ((memq
       owner
       '(notmuch-search-refresh-view
         notmuch-refresh-this-buffer
         notmuch-poll-and-refresh-this-buffer))
      'refresh)
     (t 'search))))

(defun emacsvox-notmuch--search-buffer-focused-p (buffer)
  "Return non-nil when BUFFER is displayed in the selected window."
  (and
   (buffer-live-p buffer)
   (window-live-p (selected-window))
   (eq buffer (window-buffer (selected-window)))))

(defun emacsvox-notmuch--search-summary (kind count)
  "Return a generic completed-search summary for KIND with COUNT results."
  (format
   "%s, %d %s"
   (if (eq kind 'refresh) "Search refreshed" "Search complete")
   count
   (if (= count 1) "thread" "threads")))

(defun emacsvox-notmuch--search-completion-facts (kind event)
  "Return completion facts for search KIND and EVENT."
  (emacsvox-notmuch-view-facts
   'search (if (eq kind 'refresh) 'refresh 'search) event))

(defun emacsvox-notmuch--notify-search-feedback (facts icon &optional text)
  "Send generic Notmuch search feedback through the notification stream.
FACTS describe the event, ICON is its leading cue, and TEXT is optional."
  (emacsvox-aural-submit-notification
   text
   :facts facts
   :module 'notmuch
   :occasion 'notification
   :compatibility-actions
   (emacsvox-notmuch--leading-compatibility-actions icon)))

(defun emacsvox-notmuch--announce-search-start ()
  "Signal that a user-owned non-refresh Notmuch search has started."
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-view-facts 'search 'search nil)
   'state-change 'progress nil))

(defun emacsvox-notmuch--search-completion-feedback
    (buffer kind facts icon &optional text)
  "Present search KIND's completion in BUFFER using FACTS, ICON and TEXT.
A user-owned refresh joins primary speech without interrupting current speech,
even after leaving BUFFER.  Navigation can cancel it.  Other completions use
notifications."
  (if (eq kind 'refresh)
      (with-current-buffer buffer
        (emacsvox-notmuch--submit-text-feedback
         facts 'notification icon text 'ordered 'none))
    (emacsvox-notmuch--notify-search-feedback facts icon text)))

(defun emacsvox-notmuch--maybe-speak-initial-search-result (process)
  "Speak PROCESS's selected result once, as soon as a complete row exists."
  (when-let* ((state (process-get
                     process emacsvox-notmuch--search-process-property))
              ((eq (plist-get state :kind) 'search))
              ((not (plist-get state :initial-result-spoken)))
              ((not (plist-get state :interacted)))
              (buffer (process-buffer process))
              ((emacsvox-notmuch--search-buffer-focused-p buffer)))
    (with-current-buffer buffer
      (when (and (eq major-mode 'notmuch-search-mode)
                 (eq emacsvox-notmuch--tracked-search-process process)
                 (eq emacsvox-notmuch-search-completion-style 'adaptive)
                 (not (input-pending-p)))
        (when-let* ((result (notmuch-search-get-result)))
          ;; Mark delivery before speech, which can itself process new output.
          (process-put
           process emacsvox-notmuch--search-process-property
           (plist-put (copy-sequence state) :initial-result-spoken t))
          (emacsvox-notmuch-speak-search-result result))))))

(defun emacsvox--advice-notmuch-search-process-filter-after (process _output)
  "Present the initial row after Notmuch has parsed new PROCESS output."
  (emacsvox-notmuch--maybe-speak-initial-search-result process))

(defun emacsvox-notmuch--announce-foreground-search-complete
    (buffer count)
  "Present completed focused search BUFFER with final result COUNT."
  (with-current-buffer buffer
    (let* ((summary (emacsvox-notmuch--search-summary 'search count))
           (result (notmuch-search-get-result))
           (view-facts
            (emacsvox-notmuch--search-completion-facts
             'search 'mail-view-opened)))
      (if result
          (let* ((summary-content (concat summary "\n"))
                 (result-content
                  (emacsvox-notmuch-format-search-result result))
                 (result-facts
                  (emacsvox-notmuch-message-facts result 'focus-entered)))
            (add-text-properties
             0 (length summary-content)
             (list
              emacsvox-aural-object-property 'search-summary
              emacsvox-aural-facts-property view-facts)
             summary-content)
            ;; Each field and separator needs the same message facts as
            ;; ordinary result navigation.  Keep them local to the row so
            ;; unread state and focus events cannot leak into the count.
            (let ((position 0)
                  (limit (length result-content)))
              (while (< position limit)
                (let ((end (next-single-property-change
                            position emacsvox-aural-facts-property
                            result-content limit)))
                  (put-text-property
                   position end emacsvox-aural-facts-property
                   (emacsvox-aural-merge-facts
                    result-facts
                    (get-text-property
                     position emacsvox-aural-facts-property result-content))
                   result-content)
                  (setq position end))))
            (add-text-properties
             0 (length result-content)
             (list emacsvox-aural-object-property 'search-result
                   emacsvox-aural-occasion-property 'navigation)
             result-content)
            (emacsvox-notmuch--submit-content
             (concat summary-content result-content)
             '(:role message) 'state-change
             (append
              (emacsvox-notmuch--leading-compatibility-actions 'task-done)
              (emacsvox-notmuch--status-compatibility-actions
               result emacsvox-notmuch-search-status-icons 'navigation))))
        (emacsvox-notmuch--submit-text-feedback
         view-facts 'state-change 'task-done summary)))))

(defun emacsvox-notmuch--announce-search-complete (state buffer)
  "Announce a successful completed search described by STATE in BUFFER."
  (let* ((kind (plist-get state :kind))
         (count (emacsvox-notmuch--search-result-count buffer))
         (summary (emacsvox-notmuch--search-summary kind count))
         (focused (emacsvox-notmuch--search-buffer-focused-p buffer))
         (interacted (plist-get state :interacted))
         (facts
          (emacsvox-notmuch--search-completion-facts
           kind 'refresh-completed)))
    (pcase emacsvox-notmuch-search-completion-style
      ('silent nil)
      ('cue
       (emacsvox-notmuch--search-completion-feedback
        buffer kind facts 'task-done))
      ('summary
       (emacsvox-notmuch--search-completion-feedback
        buffer kind facts 'task-done summary))
      ('adaptive
       (if (and
            (eq kind 'search)
            focused
            (not interacted)
            (not (plist-get state :initial-result-spoken))
            (not (input-pending-p)))
           (emacsvox-notmuch--announce-foreground-search-complete
            buffer count)
         (emacsvox-notmuch--search-completion-feedback
          buffer kind facts 'task-done summary)))
      (_
       (emacsvox-notmuch--search-completion-feedback
        buffer kind facts 'task-done summary)))))

(defun emacsvox-notmuch--note-search-interaction ()
  "Record a command issued while this Notmuch search is still running."
  (if-let* ((process emacsvox-notmuch--tracked-search-process)
            (state
             (process-get process emacsvox-notmuch--search-process-property)))
      (process-put
       process emacsvox-notmuch--search-process-property
       (plist-put (copy-sequence state) :interacted t))
    (setq emacsvox-notmuch--tracked-search-process nil)
    (remove-hook
     'pre-command-hook #'emacsvox-notmuch--note-search-interaction t)))

(defun emacsvox-notmuch--clear-tracked-search (process buffer)
  "Stop tracking completed search PROCESS in BUFFER when it still owns it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (eq emacsvox-notmuch--tracked-search-process process)
        (setq emacsvox-notmuch--tracked-search-process nil)
        (remove-hook
         'pre-command-hook #'emacsvox-notmuch--note-search-interaction t)))))

(defun emacsvox-notmuch--finish-search-process (process)
  "Deliver one terminal presentation for tracked Notmuch search PROCESS."
  (when-let* ((state
               (process-get process emacsvox-notmuch--search-process-property)))
    (process-put process emacsvox-notmuch--search-process-property nil)
    (let ((buffer (process-buffer process))
          (status (process-status process)))
      (emacsvox-notmuch--clear-tracked-search process buffer)
      (cond
       ((not (buffer-live-p buffer)) nil)
       ((and
         (eq status 'exit)
         (zerop (process-exit-status process)))
        (emacsvox-notmuch--announce-search-complete state buffer))
       (t
        (emacsvox-notmuch--search-completion-feedback
         buffer (plist-get state :kind)
         (emacsvox-notmuch--search-completion-facts
          (plist-get state :kind) 'refresh-failed)
         'warn-user
         (if (eq (plist-get state :kind) 'refresh)
             "Search refresh failed"
           "Search failed")))))))

(defun emacsvox-notmuch--track-search-process (kind)
  "Track the current buffer's user-owned Notmuch process as KIND."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (let ((state (list :kind kind :interacted nil)))
      (process-put process emacsvox-notmuch--search-process-property state)
      (setq-local emacsvox-notmuch--tracked-search-process process)
      (add-hook
       'pre-command-hook #'emacsvox-notmuch--note-search-interaction nil t)
      ;; A small search can run its sentinel before `notmuch-search' returns.
      (if
          (process-get
           process emacsvox-notmuch--search-sentinel-finished-property)
          (emacsvox-notmuch--finish-search-process process)
        (when (and
               (eq kind 'search)
               (emacsvox-notmuch--search-buffer-focused-p (current-buffer)))
          (emacsvox-notmuch--announce-search-start))
        ;; Output may have arrived before the search command returned and
        ;; installed tracking.  Do not wait for another filter invocation.
        (emacsvox-notmuch--maybe-speak-initial-search-result process)))))

(defun emacsvox--advice-notmuch-search-around (original &rest arguments)
  "Track completion of a user-owned call to `notmuch-search'."
  (let ((kind (emacsvox-notmuch--search-request-kind)))
    (prog1 (apply original arguments)
      (when kind
        (emacsvox-notmuch--track-search-process kind)))))

(defun emacsvox--advice-notmuch-search-process-sentinel-after (process _event)
  "Record and announce completion after Notmuch's sentinel for PROCESS."
  (process-put
   process emacsvox-notmuch--search-sentinel-finished-property t)
  (when (memq (process-status process) '(exit signal))
    (emacsvox-notmuch--finish-search-process process)))

(provide 'emacsvox-notmuch-events)
;;; emacsvox-notmuch-events.el ends here
