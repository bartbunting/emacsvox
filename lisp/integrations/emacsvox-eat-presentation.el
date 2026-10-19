;;; emacsvox-eat-presentation.el --- EAT status and output presentation  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop eat
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
;; EAT status and output presentation.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-eat-focus)
(eval-when-compile (require 'cl-lib))
(defvar eat-terminal)

;; Core owns settings, lifecycle identities and foreground eligibility.
(defvar emacsvox-eat-prompt-feedback)
(defvar emacsvox-eat-verbosity)
(defvar emacsvox-eat-monitor-background-output)
(defvar emacsvox-eat--generation)
(defvar emacsvox-eat--terminal-id)
(defvar emacsvox-eat--next-terminal-id)
(defvar emacsvox-eat--secure-input-active-p)
(defvar emacsvox-eat--recent-input)
(declare-function emacsvox-eat--selected-buffer-p "emacsvox-eat-core" ())
(declare-function emacsvox-eat--following-live-p "emacsvox-eat-core" ())
(declare-function emacsvox-eat--cancel-deletion "emacsvox-eat-input" ())
(declare-function eat-term-parameter "eat" (terminal parameter))

(defconst emacsvox-eat--status-minimum-interval 1.5
  "Minimum seconds between automatic in-progress terminal status updates.")

(defconst emacsvox-eat--bell-minimum-interval 0.5
  "Minimum seconds between spoken bells from one EAT terminal.")

(defconst emacsvox-eat--metadata-minimum-interval 1.0
  "Minimum seconds between automatic EAT metadata announcements.")

(defconst emacsvox-eat--background-cue-minimum-interval 5.0
  "Minimum seconds between cues for one monitored background terminal.")

(defvar-local emacsvox-eat--last-status-text nil
  "Latest conservatively classified terminal status or progress row.")

(defvar-local emacsvox-eat--last-status-spoken-at 0.0
  "Time at which automatic EAT status speech was most recently submitted.")

(defvar-local emacsvox-eat--last-bell-at nil
  "Time at which EAT most recently delivered a terminal bell.")

(defvar-local emacsvox-eat--last-bell-spoken-at nil
  "Time at which Emacsvox most recently announced an EAT terminal bell.")

(defvar-local emacsvox-eat--last-metadata-change nil
  "Latest bounded title or working-directory change retained for review.")

(defvar-local emacsvox-eat--last-metadata-spoken-at nil
  "Time at which EAT metadata was most recently announced automatically.")

(defvar-local emacsvox-eat--unread-output-count 0
  "Number of quiesced background-output bursts not yet acknowledged.")

(defvar-local emacsvox-eat--last-background-cue-at nil
  "Time at which monitored background output most recently played a cue.")

(defun emacsvox-eat--facts (role event &optional operation properties)
  "Return terminal command-interaction facts for ROLE and EVENT.
OPERATION and additional PROPERTIES are optional."
  (append
   (list :role role
         :command-interaction-kind 'shell
         :events (list event))
   (when operation (list :command-operation operation))
   properties))

(defun emacsvox-eat--submit
    (content facts occasion &optional icon delivery-policy replacement-key)
  "Submit terminal CONTENT with semantic and delivery metadata.
FACTS, OCCASION, and compatibility ICON describe presentation.  Optional
DELIVERY-POLICY and REPLACEMENT-KEY control whole-transaction delivery."
  (apply
   #'emacsvox-aural-submit content
   (append
    (list :facts facts :module 'eat :occasion occasion)
    (when delivery-policy (list :delivery-policy delivery-policy))
    (when replacement-key (list :replacement-key replacement-key))
    (list
     :compatibility-actions
     (when icon
       (list (emacsvox-aural-compatibility-icon icon)))))))

(defun emacsvox-eat--present-ready-prompt (text)
  "Present identified prompt TEXT according to the buffer's prompt preference."
  (let ((facts (emacsvox-eat--facts 'command-prompt 'command-prompt-ready)))
    (pcase emacsvox-eat-prompt-feedback
      ('text (unless (string-empty-p text)
               (emacsvox-eat--submit text facts 'continuous)))
      ('earcon
       (emacsvox-aural-submit-actions
        :facts facts :module 'eat :occasion 'continuous :lane 'main
        :compatibility-actions (list (emacsvox-aural-compatibility-icon 'item)))))))

(defun emacsvox-eat--status-text-p (text)
  "Return non-nil when terminal TEXT has conservative status syntax."
  (let ((case-fold-search t))
    (or
     (string-match-p
      (concat
       "[0-9]+\\(?:\\.[0-9]+\\)?%"
       "\\|\\_<\\(?:progress\\|loading\\|downloading"
       "\\|uploading\\|processing\\|complete\\|completed"
       "\\|done\\|failed\\|error\\)\\_>")
      text)
     (string-match-p "\\`[[:space:]]*--.+--[[:space:]]*\\'" text))))

(defun emacsvox-eat--status-row (diff snapshot)
  "Return a conservative automatic main-screen status from DIFF at SNAPSHOT."
  (when (and (plist-get diff :text-changed)
             (not (plist-get diff :user-input))
             (not (plist-get diff :size-changed))
             (not (plist-get diff :alternate-screen-changed))
             (not (plist-get snapshot :alternate-screen)))
    (when-let* ((change (plist-get diff :row-change))
                (cursor-row (plist-get snapshot :cursor-row))
                (old-rows (plist-get change :old-rows))
                (new-rows (plist-get change :new-rows))
                ((= (length old-rows) 1))
                ((= (length new-rows) 1))
                ((= (plist-get change :start) cursor-row))
                (row (car new-rows))
                ((emacsvox-eat--status-text-p row)))
      row)))

(defun emacsvox-eat--application-status-row (diff snapshot)
  "Return a styled bottom-row application status retained for review.
Unlike `emacsvox-eat--status-row', this never authorizes automatic speech."
  (when (and (plist-get diff :text-changed)
             (not (plist-get diff :size-changed))
             (not (plist-get diff :alternate-screen-changed))
             (plist-get snapshot :alternate-screen))
    (when-let* ((change (plist-get diff :row-change))
                (old-rows (plist-get change :old-rows))
                (new-rows (plist-get change :new-rows))
                ((= (length old-rows) 1))
                ((= (length new-rows) 1))
                (row-index (plist-get change :start))
                ((= row-index (1- (length (plist-get snapshot :rows)))))
                ((not (equal row-index (plist-get snapshot :cursor-row))))
                (row (car new-rows))
                ((emacsvox-eat--status-text-p row))
                ((seq-some
                  (lambda (region)
                    (<= (plist-get region :row-start)
                        row-index
                        (plist-get region :row-end)))
                  (emacsvox-eat--highlight-regions snapshot))))
      row)))

(defun emacsvox-eat--retained-status-row (diff snapshot)
  "Return a conservative status from DIFF at SNAPSHOT for explicit review."
  (or (emacsvox-eat--status-row diff snapshot)
      (emacsvox-eat--application-status-row diff snapshot)))

(defun emacsvox-eat--terminal-delivery-key (kind)
  "Return a stable replacement key for terminal presentation KIND."
  (unless emacsvox-eat--terminal-id
    (setq emacsvox-eat--next-terminal-id
          (1+ emacsvox-eat--next-terminal-id)
          emacsvox-eat--terminal-id emacsvox-eat--next-terminal-id))
  (list 'eat kind emacsvox-eat--terminal-id emacsvox-eat--generation))

(defun emacsvox-eat--final-status-p (text)
  "Return non-nil when status TEXT describes completion or failure."
  (let ((case-fold-search t))
    (or
     (and
      (string-match "\\([0-9]+\\(?:\\.[0-9]+\\)?\\)%" text)
      (>= (string-to-number (match-string 1 text)) 100))
     (string-match-p
      "\\_<\\(?:complete\\|completed\\|done\\|failed\\|error\\)\\_>"
      text))))

(defun emacsvox-eat--present-status (text)
  "Retain and, when due, present terminal status TEXT."
  (let ((now (float-time)))
    (setq emacsvox-eat--last-status-text text)
    (when (or (emacsvox-eat--final-status-p text)
              (>= (- now emacsvox-eat--last-status-spoken-at)
                  emacsvox-eat--status-minimum-interval))
      (setq emacsvox-eat--last-status-spoken-at now)
      (when-let* ((content (emacsvox-eat--bounded-output (list text))))
        (emacsvox-eat--submit
         content
         (emacsvox-eat--facts 'command-output 'command-output-received)
         'continuous nil 'replaceable
         (emacsvox-eat--terminal-delivery-key 'status))))))

(defun emacsvox-eat--prompt-status-text (status)
  "Return a content-free description of EAT prompt STATUS."
  (pcase status
    ('running "Shell command running")
    ('success "Shell command succeeded")
    ('failure "Shell command failed")))

(defun emacsvox-eat--present-prompt-status (diff)
  "Present the conservative automatic shell prompt status represented by DIFF.
Failures are always announced.  A success is announced only at verbose
terminal verbosity and only after an observed running or failed state."
  (when (plist-get diff :prompt-status-changed)
    (let ((old (plist-get diff :old-prompt-status))
          (new (plist-get diff :new-prompt-status)))
      (cond
       ((eq new 'failure)
        (emacsvox-eat--submit
         "Shell command failed"
         (emacsvox-eat--facts 'command-interaction 'operation-failed)
         'notification 'warn-user))
       ((and (eq new 'success)
             (eq emacsvox-eat-verbosity 'verbose)
             (memq old '(running failure)))
        (emacsvox-eat--submit
         "Shell command succeeded"
         (emacsvox-eat--facts 'command-interaction 'operation-completed)
         'state-change 'task-done))))))

(defun emacsvox-eat--metadata-change (diff snapshot)
  "Return bounded changed terminal metadata from DIFF and SNAPSHOT."
  (when (or (plist-get diff :title-changed)
            (plist-get diff :cwd-changed))
    (list
     :generation (plist-get snapshot :generation)
     :observed-at (float-time)
     :title-changed (not (null (plist-get diff :title-changed)))
     :title (plist-get snapshot :title)
     :cwd-changed (not (null (plist-get diff :cwd-changed)))
     :cwd (plist-get snapshot :cwd))))

(defun emacsvox-eat--metadata-lines (diff snapshot)
  "Return human descriptions of metadata changed in DIFF at SNAPSHOT."
  (let (lines)
    (when (plist-get diff :title-changed)
      (push
       (if-let* ((title (plist-get snapshot :title))
                 ((not (string-empty-p title))))
           (format "Terminal title: %s" title)
         "Terminal title cleared")
       lines))
    (when (plist-get diff :cwd-changed)
      (push
       (if-let* ((cwd (plist-get snapshot :cwd))
                 ((not (string-empty-p cwd))))
           (format "Working directory: %s" cwd)
         "Working directory unavailable")
       lines))
    (nreverse lines)))

(defun emacsvox-eat--retain-metadata-change (diff snapshot)
  "Retain bounded terminal metadata changed in DIFF at SNAPSHOT."
  (when-let* ((change (emacsvox-eat--metadata-change diff snapshot)))
    (setq emacsvox-eat--last-metadata-change change)))

(defun emacsvox-eat--present-metadata-change (diff snapshot)
  "Present verbose terminal metadata changed in DIFF at SNAPSHOT when due."
  (when (eq emacsvox-eat-verbosity 'verbose)
    (when-let* ((lines (emacsvox-eat--metadata-lines diff snapshot)))
      (let ((now (float-time)))
        (when (or (null emacsvox-eat--last-metadata-spoken-at)
                  (>= (- now emacsvox-eat--last-metadata-spoken-at)
                      emacsvox-eat--metadata-minimum-interval))
          (setq emacsvox-eat--last-metadata-spoken-at now)
          (emacsvox-eat--submit
           (string-join lines "\n")
           (emacsvox-eat--facts 'command-interaction 'state-changed)
           'state-change nil 'replaceable
           (emacsvox-eat--terminal-delivery-key 'metadata)))))))

(defun emacsvox-eat--alternate-screen-transitions (diff snapshot)
  "Return chronological alternate-screen states represented by DIFF.
SNAPSHOT supplies the final state when DIFF was not produced by the observer."
  (or (plist-get diff :alternate-screen-transitions)
      (and (plist-get diff :alternate-screen-changed)
           (list (not (null (plist-get snapshot :alternate-screen)))))))

(defun emacsvox-eat--present-alternate-screen-transitions (states)
  "Present each alternate-screen state in chronological STATES once."
  (dolist (entered-p states)
    (emacsvox-eat--submit
     (if entered-p
         "Terminal application screen entered"
       "Terminal application screen exited")
     (emacsvox-eat--facts
      'command-interaction
      (if entered-p 'operation-started 'operation-completed))
     'state-change
     (if entered-p 'open-object 'close-object))))

(defun emacsvox-eat--cue-background-output ()
  "Play a bounded content-free cue for monitored background output."
  (let ((now (float-time)))
    (when (and (not (active-minibuffer-window))
               (or (null emacsvox-eat--last-background-cue-at)
                   (>= (- now emacsvox-eat--last-background-cue-at)
                       emacsvox-eat--background-cue-minimum-interval)))
      (setq emacsvox-eat--last-background-cue-at now)
      (condition-case nil
          (emacsvox-icon 'more)
        (error nil)))))

(defun emacsvox-eat--present-unread-output-count ()
  "Report and acknowledge this selected terminal's unread output count."
  (when (and emacsvox-eat-monitor-background-output
             (not emacsvox-eat--secure-input-active-p)
             (emacsvox-eat--selected-buffer-p)
             (> emacsvox-eat--unread-output-count 0))
    (let ((count emacsvox-eat--unread-output-count))
      (emacsvox-eat--submit
       (if (= count 1)
           "One unread terminal output burst"
         (format "%d unread terminal output bursts" count))
       (emacsvox-eat--facts 'command-interaction 'object-changed)
       'notification)
      (setq emacsvox-eat--unread-output-count 0
            emacsvox-eat--last-background-cue-at nil))))

(defun emacsvox-eat--present-output-rows (rows)
  "Present bounded terminal output ROWS as one native aural transaction."
  (when-let* ((content (emacsvox-eat--bounded-output rows)))
    (emacsvox-eat--submit
     content
     (emacsvox-eat--facts 'command-output 'command-output-received)
     'continuous)))

(defun emacsvox-eat--observe-bell (terminal)
  "Record and, when appropriate, announce a bell from TERMINAL.
The terminal's original bell callback has already run."
  (when-let* ((buffer
               (ignore-errors
                 (eat-term-parameter terminal 'emacsvox-eat-buffer)))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (eq terminal eat-terminal)
        (let ((now (float-time)))
          (setq emacsvox-eat--last-bell-at now
                ;; A bell is its own input response; do not also speak the
                ;; adjacent prompt character through legacy echo feedback.
                emacsvox-eat--recent-input nil)
          ;; A bell can be the terminal's complete response to deletion at an
          ;; input boundary.  Do not add a later ambiguous-deletion cue.
          (emacsvox-eat--cancel-deletion)
          (when (and (not emacsvox-eat--secure-input-active-p)
                     (emacsvox-eat--selected-buffer-p)
                     (emacsvox-eat--following-live-p)
                     (or (null emacsvox-eat--last-bell-spoken-at)
                         (>= (- now emacsvox-eat--last-bell-spoken-at)
                             emacsvox-eat--bell-minimum-interval)))
            (setq emacsvox-eat--last-bell-spoken-at now)
            ;; EAT's original callback already provides the configured bell.
            ;; Keep the semantic event available for optional spoken labels,
            ;; without adding default speech or a second compatibility cue.
            (emacsvox-aural-submit-actions
             :facts
             (emacsvox-eat--facts 'command-interaction 'command-terminal-bell)
             :module 'eat :occasion 'notification)))))))

(defun emacsvox-eat--ring-bell (terminal)
  "Preserve TERMINAL's original bell callback, then notify Emacsvox safely."
  (let ((original
         (ignore-errors
           (eat-term-parameter
            terminal 'emacsvox-eat-original-ring-bell-function))))
    (prog1
        (when (and (functionp original)
                   (not (eq original #'emacsvox-eat--ring-bell)))
          (funcall original terminal))
      ;; Accessibility feedback must never break terminal escape processing.
      (condition-case nil
          (emacsvox-eat--observe-bell terminal)
        (error nil)))))

(provide 'emacsvox-eat-presentation)
;;; emacsvox-eat-presentation.el ends here
