;;; emacsvox-aural-voice-workbench-routing.el --- Voice workbench routing edits -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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
;; Voice workbench routing edits.
;; Load through `emacsvox-aural-voice-workbench'.

;;; Code:

(require 'emacsvox-aural-voice-workbench-views)

;; Workbench dependencies.
(declare-function emacsvox-aural-voice-workbench--announce
                  "emacsvox-aural-voice-workbench" (format-string &rest arguments))
(defvar emacsvox-aural-voice-workbench-inventory)
(declare-function emacsvox-aural-voice-workbench-refresh
                  "emacsvox-aural-voice-workbench" (&optional id))
(defvar emacsvox-aural-voice-workbench-view)
;; End workbench dependencies.

(defvar-local emacsvox-aural-voice-workbench-committed-profile nil
  "Routing-profile snapshot committed when this workbench opened.")

(defvar-local emacsvox-aural-voice-workbench-staged-profile nil
  "Mutable routing-profile snapshot staged in this workbench.")

(defvar-local emacsvox-aural-voice-workbench-undo-stack nil
  "Snapshots preceding staged Voice Workbench routing edits.")

(defvar-local emacsvox-aural-voice-workbench-last-edit nil
  "Description of the most recent staged routing edit.")

(defvar-local emacsvox-aural-voice-workbench-provenance nil
  "Ephemeral explanations for imported, preset, and suggested staged edits.")

(defconst emacsvox-aural-voice-workbench--session-profile-source
  'current-runtime-session
  "Source marker for an in-memory first-run routing profile.")

(defun emacsvox-aural-voice-workbench--current-profile-data (&optional inventory)
  "Return a safe routing snapshot using optional live INVENTORY."
  (if-let* ((entry
             (emacsvox-aural-routing-profile
              emacsvox-aural-active-routing-profile)))
      (copy-tree (emacsvox-aural-routing-profile-entry-data entry))
    (let* ((inventory (or inventory (tts-voice-inventory)))
           (profile
            (emacsvox-aural-routing-profile-from-omnivox
             (let ((id 'current-runtime)
                   (suffix 2))
               (while (emacsvox-aural-routing-profile id)
                 (setq id (intern (format "current-runtime-%d" suffix))
                       suffix (1+ suffix)))
               id)
             "Current unsaved adapter routing"))
           (preferred
            (or (copy-sequence
                 (plist-get inventory :preferred-engine-order))
                (and-let* ((engine-id
                            (plist-get inventory :preferred-engine-id)))
                  (list engine-id))))
           (fallback
            (copy-sequence (plist-get inventory :fallback-engine-order)))
           (disabled
            (copy-sequence (plist-get inventory :disabled-engine-ids))))
      (when preferred
        (setq profile (plist-put profile :engine-order preferred)))
      (when fallback
        (setf (plist-get (plist-get profile :fallback) :engines) fallback))
      (when disabled
        (setq profile (plist-put profile :disabled-engines disabled)))
      (emacsvox-aural-validate-routing-profile-data profile))))

(defun emacsvox-aural-voice-workbench--dirty-p ()
  "Return non-nil when staged routing differs from committed routing."
  (not
   (equal emacsvox-aural-voice-workbench-staged-profile
          emacsvox-aural-voice-workbench-committed-profile)))

(defun emacsvox-aural-voice-workbench--explicit-selectors (logical-voice)
  "Return LOGICAL-VOICE's explicitly staged selectors."
  (copy-tree
   (plist-get
    (emacsvox-aural-voice-workbench--resolved-voice logical-voice)
    :selectors)))

(defun emacsvox-aural-voice-workbench--active-profile ()
  "Return active routing profile data, or signal a user error."
  (if-let* ((entry
             (emacsvox-aural-routing-profile
              emacsvox-aural-active-routing-profile)))
      (emacsvox-aural-routing-profile-entry-data entry)
    (user-error "No active voice routing profile")))

(defun emacsvox-aural-voice-workbench--dirty-buffer ()
  "Return a live Voice Workbench buffer containing staged edits."
  (cl-find-if
   (lambda (buffer)
     (with-current-buffer buffer
       (and (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
            (emacsvox-aural-voice-workbench--dirty-p))))
   (buffer-list)))

(defun emacsvox-aural-voice-workbench--ensure-clean ()
  "Reject a quick routing change while Workbench edits are staged."
  (when-let* ((buffer (emacsvox-aural-voice-workbench--dirty-buffer)))
    (user-error
     "Save or cancel staged Voice Workbench edits in %s first"
     (buffer-name buffer))))

(defun emacsvox-aural-voice-workbench--usable-engine-p
    (engine disabled-engines)
  "Return non-nil when ENGINE can be preferred under DISABLED-ENGINES."
  (let ((engine-id (plist-get engine :engine-id))
        (health (format "%s" (or (plist-get engine :health) "unknown"))))
    (and engine-id
         (equal (plist-get engine :availability) "available")
         (not (member health '("failed" "unavailable")))
         (not (member engine-id disabled-engines)))))

(defun emacsvox-aural-voice-workbench--engine-candidates
    (&optional inventory profile)
  "Return readable usable-engine candidates from INVENTORY under PROFILE."
  (let* ((inventory (or inventory (tts-voice-inventory)))
         (profile (or profile
                      (emacsvox-aural-voice-workbench--current-profile-data
                       inventory)))
         (effective
          (emacsvox-aural-routing-effective-profile-data profile))
         (order (plist-get effective :engine-order))
         (disabled (plist-get profile :disabled-engines)))
    (cl-loop
     for engine in (plist-get inventory :engines)
     when (emacsvox-aural-voice-workbench--usable-engine-p engine disabled)
     collect
     (let* ((engine-id (plist-get engine :engine-id))
            (position (cl-position engine-id order :test #'equal)))
       (cons
        (format "%s [%s; %s; %s]"
                (or (plist-get engine :display-name) engine-id)
                engine-id
                (or (plist-get engine :health) "unknown")
                (if position
                    (format "position %d" (1+ position))
                  "not ranked"))
        engine-id)))))

(defun emacsvox-aural-voice-workbench--read-engine ()
  "Read one currently usable speech engine ID."
  (let ((candidates
         (emacsvox-aural-voice-workbench--engine-candidates)))
    (unless candidates
      (user-error "No available speech engine can be preferred"))
    (cdr
     (assoc-string
      (completing-read
       "Prefer speech engine: " candidates nil 'must-match)
      candidates))))

(defun emacsvox-aural-voice-workbench--engine (engine-id inventory)
  "Return ENGINE-ID from normalized INVENTORY."
  (cl-find
   engine-id (plist-get inventory :engines)
   :key (lambda (engine) (plist-get engine :engine-id))
   :test #'equal))

(defun emacsvox-aural-voice-workbench--validate-engine
    (engine-id inventory profile)
  "Return ENGINE-ID when INVENTORY and PROFILE permit preferring it."
  (let ((engine
         (emacsvox-aural-voice-workbench--engine engine-id inventory)))
    (unless engine
      (user-error "Speech engine %s is not in the current inventory" engine-id))
    (when (member engine-id (plist-get profile :disabled-engines))
      (user-error "Speech engine %s is disabled by the active profile"
                  engine-id))
    (unless (equal (plist-get engine :availability) "available")
      (user-error "Speech engine %s is currently unavailable" engine-id))
    (when (member (format "%s" (plist-get engine :health))
                  '("failed" "unavailable"))
      (user-error "Speech engine %s is currently %s"
                  engine-id (plist-get engine :health)))
    engine-id))

(defun emacsvox-aural-voice-workbench--engine-display-name
    (engine-id inventory)
  "Return readable ENGINE-ID name from INVENTORY."
  (let ((engine
         (emacsvox-aural-voice-workbench--engine engine-id inventory)))
    (or (plist-get engine :display-name) engine-id)))

(defun emacsvox-aural-voice-workbench--preference-callback
    (display-name scope)
  "Return terminal apply callback for DISPLAY-NAME and preference SCOPE."
  (lambda (status)
    (pcase (plist-get status :status)
      ('applied
       (if (and (memq scope '(restored runtime-restored))
                (not display-name))
           (emacsvox-aural-voice-workbench--announce
            (if (eq scope 'runtime-restored)
                "Initial engine order restored"
              "Saved engine order restored"))
         (emacsvox-aural-voice-workbench--announce
          (pcase scope
            ('saved "%s is now the saved preferred engine")
            ('restored "Saved engine order restored; %s is preferred")
            ('runtime-restored
             "Initial engine order restored; %s is preferred")
            (_ "%s is now preferred for this session"))
          display-name)))
      ('partial
       (emacsvox-aural-voice-workbench--announce
        "%s preference applied to only some speech processes"
        display-name))
      (_
       (emacsvox-aural-voice-workbench--announce
        "Could not apply %s as preferred engine: %s"
        display-name (or (plist-get status :status) "unknown status"))))))

(defun emacsvox-aural-prefer-engine (engine-id &optional save)
  "Prefer ENGINE-ID globally while preserving explicit voice routes.

By default the change lasts for this Emacs session.  With prefix argument
SAVE, atomically save it in the active routing profile.  Remaining engines
keep their relative order; explicit logical-voice routes and fallback policy
are unchanged.  When no profile has been saved yet, the live adapter policy
becomes an in-memory baseline; SAVE explicitly persists that baseline.  The
command does not stop speech already playing."
  (interactive
   (progn
     (emacsvox-aural-voice-workbench--ensure-clean)
     (list (emacsvox-aural-voice-workbench--read-engine)
           current-prefix-arg)))
  (emacsvox-aural-voice-workbench--ensure-clean)
  (let* ((active-entry
          (emacsvox-aural-routing-profile
           emacsvox-aural-active-routing-profile))
         (inventory (tts-voice-inventory))
         (profile
          (if active-entry
              (emacsvox-aural-routing-profile-entry-data active-entry)
            (emacsvox-aural-voice-workbench--current-profile-data inventory)))
         (engine-id
          (emacsvox-aural-voice-workbench--validate-engine
           engine-id inventory profile))
         (display-name
          (emacsvox-aural-voice-workbench--engine-display-name
           engine-id inventory)))
    (if (not save)
        (progn
          (unless active-entry
            (emacsvox-aural-register-routing-profile-data
             profile
             emacsvox-aural-voice-workbench--session-profile-source)
            (setq emacsvox-aural-active-routing-profile
                  (plist-get profile :id))
            (run-hooks 'emacsvox-aural-routing-profile-changed-hook))
          (emacsvox-aural-prefer-engine-for-session
           engine-id
           (emacsvox-aural-voice-workbench--preference-callback
            display-name 'session)))
      (let ((previous-session
             (copy-sequence emacsvox-aural-session-engine-order))
            (preferred
             (emacsvox-aural-routing-prefer-engine-in-data
              profile engine-id)))
        (setq emacsvox-aural-session-engine-order nil)
        (condition-case error-data
            (emacsvox-aural-commit-routing-profile-data
             preferred emacsvox-aural-routing-profiles-file
             (emacsvox-aural-voice-workbench--preference-callback
              display-name 'saved))
          (error
           (setq emacsvox-aural-session-engine-order previous-session)
           (signal (car error-data) (cdr error-data))))))
    engine-id))

(defun emacsvox-aural-restore-saved-engine-order ()
  "Clear the temporary preference and restore the saved or initial order."
  (interactive)
  (emacsvox-aural-voice-workbench--ensure-clean)
  (unless emacsvox-aural-session-engine-order
    (user-error "No temporary engine preference is active"))
  (let* ((entry
          (emacsvox-aural-routing-profile
           emacsvox-aural-active-routing-profile))
         (profile (emacsvox-aural-voice-workbench--active-profile))
         (engine-id (car (plist-get profile :engine-order)))
         (inventory (tts-voice-inventory))
         (display-name
          (emacsvox-aural-voice-workbench--engine-display-name
           engine-id inventory))
         (scope
          (if (eq (emacsvox-aural-routing-profile-entry-source entry)
                  emacsvox-aural-voice-workbench--session-profile-source)
              'runtime-restored
            'restored)))
    (emacsvox-aural-clear-session-engine-order
     (emacsvox-aural-voice-workbench--preference-callback
      display-name scope))))

(defun emacsvox-aural-voice-workbench--stage
    (description mutation &optional provenance)
  "Apply MUTATION and record DESCRIPTION and optional PROVENANCE for undo."
  (let ((before (copy-tree emacsvox-aural-voice-workbench-staged-profile))
        (before-provenance
         (copy-tree emacsvox-aural-voice-workbench-provenance)))
    (condition-case error-data
        (progn
          (funcall mutation)
          (setq emacsvox-aural-voice-workbench-staged-profile
                (emacsvox-aural-validate-routing-profile-data
                 emacsvox-aural-voice-workbench-staged-profile))
          (if (equal before emacsvox-aural-voice-workbench-staged-profile)
              (progn
                (emacsvox-aural-voice-workbench--announce
                 "No routing changes were needed")
                nil)
            (when provenance
              (push (copy-tree provenance)
                    emacsvox-aural-voice-workbench-provenance))
            (push (list :profile before :description description
                        :provenance before-provenance)
                  emacsvox-aural-voice-workbench-undo-stack)
            (setq emacsvox-aural-voice-workbench-last-edit description)
            (emacsvox-aural-voice-workbench-refresh)
            (emacsvox-aural-voice-workbench--announce
             "%s staged. Save is not yet applied" description)
            t))
      (error
       (setq emacsvox-aural-voice-workbench-staged-profile before
             emacsvox-aural-voice-workbench-provenance before-provenance)
       (signal (car error-data) (cdr error-data))))))

(defun emacsvox-aural-voice-workbench--current-engine-id ()
  "Return the engine ID on the current engine row."
  (unless (eq emacsvox-aural-voice-workbench-view 'engines)
    (user-error "Switch to the engine view first"))
  (or (tabulated-list-get-id)
      (user-error "Move to an engine row first")))

(defun emacsvox-aural-voice-workbench--policy-engine-list (field)
  "Return a copy of staged routing-policy engine FIELD."
  (copy-sequence
   (pcase field
     ('preferred
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :engine-order))
     ('fallback
      (plist-get
       (plist-get emacsvox-aural-voice-workbench-staged-profile :fallback)
       :engines))
     ('disabled
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :disabled-engines))
     (_ (error "Unknown routing-policy list: %S" field)))))

(defun emacsvox-aural-voice-workbench--set-policy-engine-list (field engines)
  "Set staged routing-policy FIELD to ordered ENGINES."
  (pcase field
    ('preferred
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           engines))
    ('fallback
     (let ((fallback
            (copy-tree
             (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback))))
       (setf (plist-get fallback :engines) engines)
       (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback)
             fallback)))
    ('disabled
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :disabled-engines)
           engines))))

(defun emacsvox-aural-voice-workbench--move-policy-engine
    (field direction label)
  "Move current engine in policy FIELD by DIRECTION, described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (index (cl-position engine-id engines :test #'equal)))
    (unless index
      (user-error "%s is not in the %s; use its toggle command first"
                  engine-id label))
    (let ((destination (+ index direction))
          (total (length engines)))
      (unless (<= 0 destination (1- (length engines)))
        (user-error
         "%s is already at position %d of %d, the %s boundary"
         engine-id (1+ index) total label))
      (cl-rotatef (nth index engines) (nth destination engines))
      (emacsvox-aural-voice-workbench--stage
       (format "Moved %s to position %d of %d in global %s"
               engine-id (1+ destination) total label)
       (lambda ()
         (emacsvox-aural-voice-workbench--set-policy-engine-list
          field engines))))))

(defun emacsvox-aural-voice-workbench--toggle-policy-engine
    (field label)
  "Toggle current engine membership in policy FIELD described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (present (member engine-id engines)))
    (emacsvox-aural-voice-workbench--stage
     (format "%s %s in %s"
             (if present "Removed" "Added") engine-id label)
     (lambda ()
       (emacsvox-aural-voice-workbench--set-policy-engine-list
        field
        (if present
            (delete engine-id engines)
          (append engines (list engine-id))))))))

(defun emacsvox-aural-voice-workbench-move-preferred-engine-up ()
  "Move the selected engine earlier in preferred engine order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine 'preferred -1 "preferred order"))

(defun emacsvox-aural-voice-workbench-move-preferred-engine-down ()
  "Move the selected engine later in preferred engine order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine 'preferred 1 "preferred order"))

(defun emacsvox-aural-voice-workbench-toggle-preferred-engine ()
  "Add or remove the current engine from global preferred order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'preferred "global preferred order"))

(defun emacsvox-aural-voice-workbench-toggle-fallback-engine ()
  "Add or remove the current engine from global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'fallback "global fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-up ()
  "Move the current engine earlier in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback -1 "fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-down ()
  "Move the current engine later in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback 1 "fallback order"))

(defun emacsvox-aural-voice-workbench-toggle-disabled-engine ()
  "Disable or restore the current engine in the staged policy."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'disabled "disabled engine list"))

(defun emacsvox-aural-voice-workbench-request-recovery-probe ()
  "Request a live recovery probe for the current failed engine."
  (interactive)
  (let ((engine-id
         (emacsvox-aural-voice-workbench--current-engine-id))
        (buffer (current-buffer)))
    (tts-request-engine-recovery-probe
     engine-id
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (emacsvox-aural-voice-workbench-refresh engine-id)
           (emacsvox-aural-voice-workbench--announce
            "%s recovery probe for %s"
            (if (equal (plist-get result :type)
                       "engine_recovery_probe_requested")
                "Armed" "Could not arm")
            engine-id)))))
    (emacsvox-aural-voice-workbench--announce
     "Requested recovery probe for %s" engine-id)))

(defun emacsvox-aural-voice-workbench-export-profile ()
  "Export the staged routing profile without activating it."
  (interactive)
  (let* ((kind
          (completing-read
           "Export routing: "
           '("portable copy without exact native IDs"
             "complete machine-local profile")
           nil 'must-match))
         (portable (string-prefix-p "portable" kind))
         (file
          (read-file-name
           "Export routing profile to: " emacsvox-user-directory nil nil
           (format "%s-routing.el"
                   (plist-get emacsvox-aural-voice-workbench-staged-profile
                              :id)))))
    (emacsvox-aural-export-routing-profile
     emacsvox-aural-voice-workbench-staged-profile file portable
     emacsvox-aural-voice-workbench-inventory)
    (emacsvox-aural-voice-workbench--announce
     "%s routing profile exported to %s"
     (if portable "Portable" "Complete") file)))

(defun emacsvox-aural-voice-workbench-import-profile ()
  "Read one data-only routing profile into the staged workbench copy."
  (interactive)
  (let* ((file
          (read-file-name
           "Import routing profile: " emacsvox-user-directory nil 'must-match))
         (profile (emacsvox-aural-read-routing-profile file)))
    (when
        (y-or-n-p
         (format "Replace staged routing with profile %s from %s? "
                 (plist-get profile :id) file))
      (emacsvox-aural-voice-workbench--stage
       (format "Imported routing profile %s" (plist-get profile :id))
       (lambda ()
         (setq emacsvox-aural-voice-workbench-staged-profile
               (copy-tree profile)))
       (list :kind 'imported :detail (abbreviate-file-name file))))))

(defun emacsvox-aural-voice-workbench-undo ()
  "Undo the most recent staged routing edit without changing saved state."
  (interactive)
  (let ((snapshot (pop emacsvox-aural-voice-workbench-undo-stack)))
    (unless snapshot (user-error "No staged routing edit to undo"))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree (plist-get snapshot :profile))
          emacsvox-aural-voice-workbench-provenance
          (copy-tree (plist-get snapshot :provenance))
          emacsvox-aural-voice-workbench-last-edit
          (format "Undid %s" (plist-get snapshot :description)))
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce
     "%s" emacsvox-aural-voice-workbench-last-edit)))

(defun emacsvox-aural-voice-workbench-cancel-staged ()
  "Restore the exact profile snapshot from when the workbench opened."
  (interactive)
  (when
      (or (not (emacsvox-aural-voice-workbench--dirty-p))
          (y-or-n-p "Discard every staged routing edit? "))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree emacsvox-aural-voice-workbench-committed-profile)
          emacsvox-aural-voice-workbench-undo-stack nil
          emacsvox-aural-voice-workbench-provenance nil
          emacsvox-aural-voice-workbench-last-edit "Cancelled staged edits")
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce "Staged routing edits cancelled")))

(provide 'emacsvox-aural-voice-workbench-routing)
;;; emacsvox-aural-voice-workbench-routing.el ends here
