;;; emacsvox-agent-shell-presentation.el --- Agent Shell speech policy and presentation  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop agent-shell
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

;; Apply foreground and background speech policy, bound automatic content,
;; describe session headers and submit common feedback. Event capture,
;; interaction callbacks and navigation use these unchanged entry points.
;; Configuration, keymaps, advice installation and activation stay in the
;; facade. Load through `emacsvox-agent-shell'; definitions do not activate it.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-events)

(defvar tts-speaker-process)
(defvar emacsvox-agent-shell-speak-thought-process)
(defvar emacsvox-agent-shell-tool-output-verbosity)
(defvar emacsvox-agent-shell-speak-permissions)
(defvar emacsvox-agent-shell-speak-tool-calls)
(defvar emacsvox-agent-shell-foreground-speech-level)
(defvar emacsvox-agent-shell-background-speech-level)
(defvar emacsvox-agent-shell-automatic-content-max-characters)
(defvar emacsvox-agent-shell-speech-level)
(declare-function agent-shell--context-usage-face
                  "agent-shell-usage" (percentage))
(declare-function agent-shell-shell-buffer "agent-shell" t)
(declare-function agent-shell-session-id "agent-shell" t)
(declare-function shell-maker-busy "shell-maker" ())
(declare-function agent-shell--cost-indicator "agent-shell-usage" ())
(defvar agent-shell--state)
(defvar emacsvox-agent-shell--push-active-p)
(declare-function emacsvox-agent-shell--cancel-pending-speech
                  "emacsvox-agent-shell-events" ())
(defvar agent-shell-show-context-usage-indicator)
(defvar agent-shell-show-session-id)
(defvar agent-shell-viewport--position-cache)

(defconst emacsvox-agent-shell--speech-level-values
  '((quiet . 0) (notify . 1) (response . 2) (full . 3))
  "Numeric ordering of agent-shell automatic speech levels.")

(defun emacsvox-agent-shell--viewport-session-buffer (viewport-buffer)
  "Return VIEWPORT-BUFFER's live Agent Shell session without creating one."
  (when (buffer-live-p viewport-buffer)
    (let ((shell-buffer
           (with-current-buffer viewport-buffer
             (agent-shell-shell-buffer
              :viewport-buffer viewport-buffer :no-error t :no-create t))))
      (when (and (buffer-live-p shell-buffer)
                 (with-current-buffer shell-buffer
                   (derived-mode-p 'agent-shell-mode)))
        shell-buffer))))

(defun emacsvox-agent-shell--session-focused-p (&optional buffer)
  "Return non-nil when BUFFER's agent-shell session has keyboard focus.
A selected viewport counts as focus for its associated shell buffer."
  (let* ((shell-buffer (or buffer (current-buffer)))
         (selected-buffer (window-buffer (selected-window))))
    (and (buffer-live-p shell-buffer)
         (or (eq shell-buffer selected-buffer)
             (and (buffer-live-p selected-buffer)
                  (with-current-buffer selected-buffer
                    (and
                     (derived-mode-p 'agent-shell-viewport-view-mode
                                     'agent-shell-viewport-edit-mode)
                     (eq shell-buffer
                         (emacsvox-agent-shell--viewport-session-buffer
                          selected-buffer)))))))))

(defun emacsvox-agent-shell--session-label (&optional buffer)
  "Return a concise spoken label for agent-shell BUFFER."
  (let* ((name (buffer-name (or buffer (current-buffer))))
         (trimmed (and name
                       (string-trim name
                                    "[*[:space:]]+"
                                    "[*[:space:]]+"))))
    (if (and trimmed (not (string-empty-p trimmed)))
        trimmed
      "Agent shell")))

(defun emacsvox-agent-shell--effective-speech-level (&optional buffer)
  "Return the automatic speech level currently effective for BUFFER."
  (let ((target (or buffer (current-buffer))))
    (with-current-buffer target
      (if (memq emacsvox-agent-shell-speech-level
                '(full response notify quiet))
          emacsvox-agent-shell-speech-level
        (if (emacsvox-agent-shell--session-focused-p target)
            emacsvox-agent-shell-foreground-speech-level
          emacsvox-agent-shell-background-speech-level)))))

(defun emacsvox-agent-shell--speech-level-at-least-p (level &optional buffer)
  "Return non-nil when BUFFER's effective speech level includes LEVEL."
  (>= (or (alist-get (emacsvox-agent-shell--effective-speech-level buffer)
                     emacsvox-agent-shell--speech-level-values)
          0)
      (or (alist-get level emacsvox-agent-shell--speech-level-values) 0)))

(defun emacsvox-agent-shell--presentation-facts
    (role &optional event states attributes)
  "Return Agent Shell facts for ROLE, EVENT, STATES, and ATTRIBUTES.

ATTRIBUTES is a property list of registered semantic attributes."
  (append
   (list :role role)
   (when event (list :events (list event)))
   (when states (list :states (copy-sequence states)))
   (copy-tree attributes)))

(defun emacsvox-agent-shell--omitted-span-counts (text cut)
  "Return omitted character and affected-line counts for TEXT after CUT."
  (cons (- (length text) cut)
        (1+ (cl-count ?\n text :start cut))))

(defun emacsvox-agent-shell--bounded-text-with-notice
    (text limit notice-function)
  "Bound TEXT to LIMIT, appending NOTICE-FUNCTION's omission description.

NOTICE-FUNCTION receives omitted character and affected-line counts.  Keep a
word boundary when one is available without discarding the entire opening."
  (if (or (not (integerp limit))
          (<= limit 0)
          (<= (length text) limit))
      text
    (let* ((initial-counts
            (emacsvox-agent-shell--omitted-span-counts text 0))
           (initial-notice
            (funcall notice-function
                     (car initial-counts) (cdr initial-counts))))
      (if (>= (length initial-notice) limit)
          (substring initial-notice 0 limit)
        (let* ((available (- limit (length initial-notice)))
               (prefix (substring text 0 available))
               (next-character (aref text available))
               (word-start
                (unless
                    (string-match-p
                     "\\`[[:space:]]\\'" (char-to-string next-character))
                  (string-match
                   "[[:space:]][^[:space:]]*\\'" prefix)))
               (preview
                (string-trim-right
                 (substring prefix 0 (or word-start available))))
               (cut (length preview))
               (counts
                (emacsvox-agent-shell--omitted-span-counts text cut))
               (notice
                (funcall notice-function (car counts) (cdr counts))))
          (concat preview notice))))))

(defun emacsvox-agent-shell--automatic-inspection-hint (facts)
  "Return an explicit inspection hint appropriate for semantic FACTS."
  (pcase (plist-get facts :role)
    ('agent-response "Use C-c r for the complete response.")
    ('agent-tool "Inspect the tool block for complete output.")
    ('agent-error "Inspect the error block for complete details.")
    ('permission-request
     "Review the permission prompt for complete details.")
    (_ "Inspect the Agent Shell buffer for complete content.")))

(defun emacsvox-agent-shell--limit-automatic-content
    (text facts &optional inspection-hint)
  "Return TEXT bounded for automatic speech under FACTS.

INSPECTION-HINT overrides the role-sensitive route to complete content."
  (emacsvox-agent-shell--bounded-text-with-notice
   text emacsvox-agent-shell-automatic-content-max-characters
   (lambda (characters lines)
     (format
      " [automatic speech shortened: %d %s omitted across %d %s. %s]"
      characters (if (= characters 1) "character" "characters")
      lines (if (= lines 1) "line" "lines")
      (or inspection-hint
          (emacsvox-agent-shell--automatic-inspection-hint facts))))))

(defconst emacsvox-agent-shell--permission-field-max-characters 160
  "Maximum untrusted characters retained in one permission speech field.")

(defun emacsvox-agent-shell--permission-field-text (text label)
  "Return bounded permission TEXT identified by LABEL, or nil."
  (when (stringp text)
    (let ((trimmed
           (string-trim (substring-no-properties text))))
      (unless (string-empty-p trimmed)
        (emacsvox-agent-shell--bounded-text-with-notice
         trimmed emacsvox-agent-shell--permission-field-max-characters
         (lambda (characters lines)
           (format
            " [%s shortened: %d %s omitted across %d %s]"
            label characters
            (if (= characters 1) "character" "characters")
            lines (if (= lines 1) "line" "lines"))))))))

(defun emacsvox-agent-shell--notify-background
    (facts occasion icon text &optional separator)
  "Notify the background session with FACTS, OCCASION, ICON, and TEXT.
SEPARATOR defaults to a sentence boundary between the session label and TEXT."
  (let ((speech
         (emacsvox-agent-shell--limit-automatic-content
          (format "%s%s%s"
                  (emacsvox-agent-shell--session-label)
                  (or separator ". ")
                  text)
          facts)))
    (emacsvox-aural-call-with-submission
     (lambda ()
       (tts-notify-icon icon)
       (tts-notify speech))
     :facts facts
     :module 'agent-shell
     :occasion occasion)))

(defun emacsvox-agent-shell--deliver-announcement
    (facts occasion icon text &optional delivery-policy)
  "Deliver ICON and TEXT under FACTS and OCCASION for the current session.
When DELIVERY-POLICY is non-nil, it governs the complete foreground or
background transaction."
  (let* ((focused (emacsvox-agent-shell--session-focused-p))
         (deliver
          (lambda ()
            (if focused
                (emacsvox-agent-shell--submit-automatic-text-feedback
                 text facts occasion icon)
              (emacsvox-agent-shell--notify-background
               facts occasion icon text)))))
    ;; A distinct notification stream cannot interrupt or cancel pending work
    ;; owned by the primary speaker.  Stop that owner separately, while a
    ;; single-stream notification lets the urgent transaction own interruption.
    (when
        (and
         (eq delivery-policy 'urgent)
         (not focused)
         (not (eq (tts-notify-process) tts-speaker-process)))
      (tts-stop))
    (if delivery-policy
        (emacsvox-aural-call-with-submission
         deliver
         :facts facts
         :module 'agent-shell
         :occasion occasion
         :delivery-policy delivery-policy)
      (funcall deliver))))

(defconst emacsvox-agent-shell--speech-level-cycle
  '(full response notify quiet)
  "Order used by `emacsvox-agent-shell-cycle-speech-level'.")

(defconst emacsvox-agent-shell--speech-level-choices
  '(("automatic" . auto)
    ("full" . full)
    ("response" . response)
    ("notify" . notify)
    ("quiet" . quiet))
  "Completion candidates for interactive agent-shell speech levels.")

(defun emacsvox-agent-shell--session-buffer (&optional buffer)
  "Return the agent-shell session associated with BUFFER.
Signal a user error when BUFFER is neither a shell nor an associated viewport."
  (let ((candidate (or buffer (current-buffer))))
    (with-current-buffer candidate
      (cond
       ((derived-mode-p 'agent-shell-mode) candidate)
       ((derived-mode-p 'agent-shell-viewport-view-mode
                        'agent-shell-viewport-edit-mode)
        (or (emacsvox-agent-shell--viewport-session-buffer candidate)
            (user-error "This viewport has no agent-shell session")))
       (t (user-error "Not in an agent-shell session"))))))

(defun emacsvox-agent-shell--nonempty-text (value)
  "Return VALUE as trimmed plain text, or nil when it has no text."
  (when (stringp value)
    (let ((text (string-trim (substring-no-properties value))))
      (unless (string-empty-p text) text))))

(defun emacsvox-agent-shell--agent-name (state)
  "Return the spoken agent name represented by STATE."
  (when-let* ((name
               (emacsvox-agent-shell--nonempty-text
                (map-nested-elt state '(:agent-config :buffer-name)))))
    (if (string-match-p "\\bagent\\'" (downcase name))
        name
      (format "%s agent" name))))

(defun emacsvox-agent-shell--context-percentage (state)
  "Return the displayed context percentage represented by STATE."
  (when (bound-and-true-p agent-shell-show-context-usage-indicator)
    (let* ((usage (map-elt state :usage))
           (used (map-elt usage :context-used))
           (size (map-elt usage :context-size)))
      (when (and (numberp used) (numberp size) (> size 0))
        (round (/ (* 100.0 used) size))))))

(defun emacsvox-agent-shell--viewport-position ()
  "Return the current viewport position as a spoken string, or nil.
This isolates agent-shell's private viewport position API so upstream drift is
easy to detect and adapt."
  (when (derived-mode-p 'agent-shell-viewport-view-mode
                        'agent-shell-viewport-edit-mode)
    (when-let* ((position
                 (or (and (boundp 'agent-shell-viewport--position-cache)
                          agent-shell-viewport--position-cache)
                     (and (fboundp 'agent-shell-viewport--position)
                          (ignore-errors
                            (agent-shell-viewport--position)))))
                (current (map-elt position :current))
                (total (map-elt position :total)))
      (format "%s of %s" current total))))

(defun emacsvox-agent-shell--header-state (&optional buffer)
  "Return semantic header state for BUFFER, or nil when unavailable.
BUFFER may be an agent shell or one of its viewports.  Access to the private
aggregate `agent-shell--state' is kept here so compatibility changes remain
localized; model, thought-level, mode, session ID, and busy values use public
accessors where agent-shell provides them."
  (let* ((target (or buffer (current-buffer)))
         (viewport-p
          (with-current-buffer target
            (derived-mode-p 'agent-shell-viewport-view-mode
                            'agent-shell-viewport-edit-mode)))
         (position
          (when viewport-p
            (with-current-buffer target
              (emacsvox-agent-shell--viewport-position))))
         (viewport-mode
          (when viewport-p
            (with-current-buffer target major-mode)))
         (shell-buffer
          (condition-case nil
              (emacsvox-agent-shell--session-buffer target)
            (error nil))))
    (when (buffer-live-p shell-buffer)
      (with-current-buffer shell-buffer
        (when-let* ((state
                     (and (boundp 'agent-shell--state)
                          agent-shell--state)))
          (let* ((busy
                  (or (and (fboundp 'shell-maker-busy)
                           (ignore-errors (shell-maker-busy)))
                      (eq 'busy
                          (map-nested-elt state '(:heartbeat :status)))))
                 (project
                  (emacsvox-agent-shell--nonempty-text
                   (and (fboundp 'agent-shell--project-name)
                        (ignore-errors (agent-shell--project-name)))))
                 (status
                  (when viewport-p
                    (cond
                     ((and busy
                           (eq viewport-mode
                               'agent-shell-viewport-edit-mode))
                      "edit queue")
                     (busy "busy")
                     ((eq viewport-mode 'agent-shell-viewport-edit-mode)
                      "edit")
                     (t "view")))))
            (list
             :agent (or (emacsvox-agent-shell--agent-name state)
                        (emacsvox-agent-shell--session-label shell-buffer))
             :project project
             :busy busy
             :viewport-position position
             :viewport-status status
             :model
             (emacsvox-agent-shell--nonempty-text
              (and (fboundp 'agent-shell-get-model-name)
                   (ignore-errors (agent-shell-get-model-name state))))
             :thought-level
             (emacsvox-agent-shell--nonempty-text
              (and (fboundp 'agent-shell-get-thought-level-name)
                   (ignore-errors
                     (agent-shell-get-thought-level-name state))))
             :mode
             (emacsvox-agent-shell--nonempty-text
              (and (fboundp 'agent-shell-get-mode-name)
                   (ignore-errors (agent-shell-get-mode-name state))))
             :context-percentage
             (emacsvox-agent-shell--context-percentage state)
             :cost
             (and (fboundp 'agent-shell--cost-indicator)
                  (ignore-errors (agent-shell--cost-indicator)))
             :session-id
             (when (bound-and-true-p agent-shell-show-session-id)
               (emacsvox-agent-shell--nonempty-text
                (if (fboundp 'agent-shell-session-id)
                    (ignore-errors
                      (agent-shell-session-id :shell-buffer shell-buffer))
                  (map-nested-elt state '(:session :id))))))))))))

(defun emacsvox-agent-shell--format-brief-header (state)
  "Return a concise focus announcement for semantic header STATE."
  (let ((parts
         (delq
          nil
          (list
           (plist-get state :agent)
           (plist-get state :project)
           (when-let* ((position (plist-get state :viewport-position)))
             (format "viewport %s" position))
           (or (plist-get state :viewport-status)
               (and (plist-get state :busy) "busy"))))))
    (when parts
      (concat (mapconcat #'identity parts ", ") "."))))

(defun emacsvox-agent-shell--header-context-face (percentage)
  "Return agent-shell's semantic face for context PERCENTAGE.
Use the guarded private helper when available so speech follows the graphical
indicator; retain current agent-shell thresholds as a compatibility fallback."
  (if (fboundp 'agent-shell--context-usage-face)
      (agent-shell--context-usage-face percentage)
    ;; Preserve useful contrast with agent-shell releases predating the helper.
    (cond
     ((>= percentage 85) 'agent-shell-error)
     ((>= percentage 60) 'agent-shell-warning)
     (t 'agent-shell-success))))

(defun emacsvox-agent-shell--header-status-face (status)
  "Return the semantic viewport face for spoken STATUS."
  (pcase status
    ((or "edit" "edit queue") 'agent-shell-viewport-status-edit)
    ("busy" 'agent-shell-viewport-status-busy)
    ("view" 'agent-shell-viewport-status-view)))

(defun emacsvox-agent-shell--format-full-header (state)
  "Return a voiced full spoken description of semantic header STATE."
  (let ((parts
         (delq
          nil
          (list
           (when-let* ((agent (plist-get state :agent)))
             (propertize agent 'face 'agent-shell-buffer-name))
           (when-let* ((project (plist-get state :project)))
             (propertize (format "Project %s" project)
                         'face 'agent-shell-session-directory))
           (when (and (plist-get state :busy)
                      (not (plist-get state :viewport-status)))
             (propertize "Busy" 'face 'agent-shell-warning))
           (when-let* ((position (plist-get state :viewport-position)))
             (format "Viewport %s" position))
           (when-let* ((status (plist-get state :viewport-status)))
             (propertize
              (concat (upcase (substring status 0 1))
                      (substring status 1))
              'face (emacsvox-agent-shell--header-status-face status)))
           (when-let* ((model (plist-get state :model)))
             (propertize (format "Model %s" model)
                         'face 'agent-shell-model))
           (when-let* ((thought (plist-get state :thought-level)))
             (propertize (format "Thought level %s" thought)
                         'face 'agent-shell-thought-level))
           (when-let* ((mode (plist-get state :mode)))
             (propertize (format "Mode %s" mode)
                         'face 'agent-shell-session-mode))
           (when-let* ((percentage
                        (plist-get state :context-percentage)))
             (propertize
              (format "Context %d percent" percentage)
              'face
              (emacsvox-agent-shell--header-context-face percentage)))
           (when-let* ((cost (plist-get state :cost)))
             (propertize (format "Cost %s" cost)
                         'face 'agent-shell-secondary))
           (when-let* ((session-id (plist-get state :session-id)))
             (propertize (format "Session ID %s" session-id)
                         'face 'agent-shell-session-id))))))
    (when parts
      (concat (mapconcat #'identity parts ". ") "."))))

(defun emacsvox-agent-shell--brief-session-speech (&optional buffer)
  "Return concise semantic speech for Agent Shell BUFFER."
  (or
   (when-let* ((state (emacsvox-agent-shell--header-state buffer)))
     (emacsvox-agent-shell--format-brief-header state))
   (emacsvox-agent-shell--session-label buffer)))

(defun emacsvox-agent-shell--unspoken-graphical-header-p ()
  "Return non-nil when the current agent header has no speakable text."
  (and header-line-format
       (derived-mode-p 'agent-shell-mode
                       'agent-shell-viewport-view-mode
                       'agent-shell-viewport-edit-mode)
       (string-empty-p
        (string-trim
         (substring-no-properties
          (or (format-mode-line header-line-format) ""))))))

(defun emacsvox-agent-shell--speak-focus-header-if-needed ()
  "Speak the concise semantic header when its graphical form is inaccessible.
Return non-nil when an announcement was delivered."
  (when (emacsvox-agent-shell--unspoken-graphical-header-p)
    (when-let* ((state (emacsvox-agent-shell--header-state))
                (speech
                 (emacsvox-agent-shell--format-brief-header state)))
      (emacsvox-agent-shell--submit-text-feedback
       speech
       (emacsvox-agent-shell--presentation-facts
        'agent-session 'agent-content-inspected)
       'inspection 'item)
      t)))

(defun emacsvox-agent-shell-speak-header ()
  "Speak the full semantic header for the current agent-shell session."
  (interactive)
  (let* ((state
          (or (emacsvox-agent-shell--header-state)
              (user-error "Agent header state is unavailable")))
         (speech (emacsvox-agent-shell--format-full-header state)))
    (tts-stop)
    (emacsvox-agent-shell--submit-text-feedback
     speech
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-content-inspected)
     'inspection 'item)))

(defun emacsvox-agent-shell--next-speech-level (level)
  "Return the speech level following LEVEL in the interactive cycle."
  (or (cadr (memq level emacsvox-agent-shell--speech-level-cycle))
      (car emacsvox-agent-shell--speech-level-cycle)))

(defun emacsvox-agent-shell--read-speech-level
    (prompt current &optional include-auto)
  "Read a speech level with PROMPT, defaulting to CURRENT.
When INCLUDE-AUTO is non-nil, include the automatic focus-aware choice."
  (let* ((choices
          (if include-auto
              emacsvox-agent-shell--speech-level-choices
            (cdr emacsvox-agent-shell--speech-level-choices)))
         (default (or (car (rassq current choices)) (caar choices)))
         (selected
          (completing-read
           (format-prompt prompt default)
           (mapcar #'car choices)
           nil t nil nil default)))
    (alist-get selected choices nil nil #'string=)))

(defun emacsvox-agent-shell--set-session-speech-level
    (shell-buffer level)
  "Set SHELL-BUFFER's speech override to LEVEL and announce the result."
  (let ((label (emacsvox-agent-shell--session-label shell-buffer))
        announcement)
    (with-current-buffer shell-buffer
      (setq-local emacsvox-agent-shell-speech-level level)
      (when (memq level '(notify quiet))
        (emacsvox-agent-shell--cancel-pending-speech))
      (setq announcement
            (if (eq level 'auto)
                (format "Agent speech automatic: %s when focused, %s in background."
                        emacsvox-agent-shell-foreground-speech-level
                        emacsvox-agent-shell-background-speech-level)
              (format "Agent speech %s for %s." level label))))
    (emacsvox-agent-shell--submit-text-feedback
     announcement
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed nil
      (list :agent-speech-level level))
     'state-change
     (if (eq level 'quiet) 'off 'select-object))
    level))

(defun emacsvox-agent-shell-select-speech-level ()
  "Select the automatic speech level for the current agent-shell session."
  (interactive)
  (let ((shell-buffer (emacsvox-agent-shell--session-buffer)))
    (emacsvox-agent-shell--set-session-speech-level
     shell-buffer
     (with-current-buffer shell-buffer
       (emacsvox-agent-shell--read-speech-level
        "Session speech level" emacsvox-agent-shell-speech-level t)))))

(defun emacsvox-agent-shell--cancel-background-pending-speech ()
  "Cancel queued speech affected by a non-content background default."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (derived-mode-p 'agent-shell-mode)
                   (eq emacsvox-agent-shell-speech-level 'auto)
                   (not (emacsvox-agent-shell--session-focused-p buffer)))
          (emacsvox-agent-shell--cancel-pending-speech))))))

(defun emacsvox-agent-shell-select-background-speech-level ()
  "Select the automatic speech level shared by background sessions."
  (interactive)
  (let ((level
         (emacsvox-agent-shell--read-speech-level
          "Background speech level"
          emacsvox-agent-shell-background-speech-level)))
    (setq emacsvox-agent-shell-background-speech-level level)
    (when (memq level '(notify quiet))
      (emacsvox-agent-shell--cancel-background-pending-speech))
    (emacsvox-agent-shell--submit-text-feedback
     (format "Background agent speech %s." level)
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed nil
      (list :agent-speech-level level))
     'state-change
     (if (eq level 'quiet) 'off 'select-object))))

(defun emacsvox-agent-shell-cycle-speech-level (&optional reset)
  "Cycle automatic speech for the current agent-shell session.
Cycle from the effective level toward less speech: full, response, notify,
quiet, then full again.  With prefix argument RESET, restore `auto' so focus
selects the configured foreground or background level."
  (interactive "P")
  (let ((shell-buffer (emacsvox-agent-shell--session-buffer)))
    (emacsvox-agent-shell--set-session-speech-level
     shell-buffer
     (if reset
         'auto
       (emacsvox-agent-shell--next-speech-level
        (emacsvox-agent-shell--effective-speech-level shell-buffer))))))

(defun emacsvox-agent-shell--submit-icon-feedback (facts occasion icon)
  "Submit compatibility ICON under FACTS and OCCASION without text."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'agent-shell
   :occasion occasion
   :compatibility-actions
   (list (emacsvox-aural-compatibility-icon icon))))

(defun emacsvox-agent-shell--submit-text-feedback
    (text facts occasion &optional icon delivery-policy replacement-key)
  "Submit Agent Shell TEXT with FACTS, OCCASION, and optional compatibility ICON."
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'agent-shell
   :occasion occasion
   :delivery-policy delivery-policy
   :replacement-key replacement-key
   :compatibility-actions
   (when icon
     (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-agent-shell--submit-automatic-text-feedback
    (text facts occasion
          &optional icon inspection-hint delivery-policy replacement-key)
  "Submit bounded automatic TEXT with semantic and compatibility context.

FACTS, OCCASION, and ICON have the same meanings as in
`emacsvox-agent-shell--submit-text-feedback'.  INSPECTION-HINT overrides the
role-sensitive route announced when content is shortened.  DELIVERY-POLICY
and REPLACEMENT-KEY control interruption of the complete bounded submission."
  (emacsvox-agent-shell--submit-text-feedback
   (emacsvox-agent-shell--limit-automatic-content
    text facts inspection-hint)
   facts occasion icon delivery-policy replacement-key))

(defun emacsvox-agent-shell--present-content
    (content block-type facts occasion)
  "Present CONTENT of BLOCK-TYPE under explicit FACTS and OCCASION."
  (let ((trimmed-content (string-trim content)))
    (pcase block-type
      ('agent-message
       (when (emacsvox-agent-shell--speech-level-at-least-p 'response)
         (emacsvox-agent-shell--submit-automatic-text-feedback
          trimmed-content facts occasion nil nil 'replaceable 'speaker)))
      ('user-message
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-automatic-text-feedback
          (concat "User: " trimmed-content) facts occasion 'item)))
      ('thought
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (pcase emacsvox-agent-shell-speak-thought-process
           ('speak
            (emacsvox-agent-shell--submit-automatic-text-feedback
             (concat "Thinking: " trimmed-content) facts occasion))
           ('icon
            (emacsvox-agent-shell--submit-icon-feedback
             facts occasion 'progress))
           (_ nil))))
      ('permission
       (when emacsvox-agent-shell-speak-permissions
         (emacsvox-agent-shell--deliver-announcement
          facts occasion 'warn-user trimmed-content)))
      ('tool-call
       (when (and emacsvox-agent-shell-speak-tool-calls
                  (emacsvox-agent-shell--speech-level-at-least-p 'full))
         (pcase emacsvox-agent-shell-tool-output-verbosity
           ('full
            (emacsvox-agent-shell--submit-automatic-text-feedback
             trimmed-content facts occasion))
           ('summary
            ;; Extract just the first few lines or a summary
            (let ((lines (split-string trimmed-content "\n" t)))
              (if (<= (length lines) 3)
                  (emacsvox-agent-shell--submit-automatic-text-feedback
                   trimmed-content facts occasion)
                (emacsvox-agent-shell--submit-automatic-text-feedback
                 (string-join (seq-take lines 3) " ")
                 facts occasion))))
           ('status
            ;; Just play an icon for status-only mode
            (emacsvox-agent-shell--submit-icon-feedback
             facts occasion 'task-done)))))
      ('plan
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-automatic-text-feedback
          (concat "Plan: " trimmed-content) facts occasion 'item)))
      ('error
       (emacsvox-agent-shell--deliver-announcement
        facts occasion 'warn-user trimmed-content))
      ('unknown
       (cond
        ((emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-automatic-text-feedback
          trimmed-content facts occasion))
        ((emacsvox-agent-shell--speech-level-at-least-p 'response)
         (emacsvox-agent-shell--submit-automatic-text-feedback
          "Additional agent content available." facts occasion))))
      (_
       ;; Fallback: speak if content is substantial
       (when (and (> (length trimmed-content) 0)
                  (emacsvox-agent-shell--speech-level-at-least-p 'response))
         (emacsvox-agent-shell--submit-automatic-text-feedback
          trimmed-content facts occasion))))))

(defun emacsvox-agent-shell-content-facts (block-type)
  "Return semantic facts for Agent Shell BLOCK-TYPE."
  (let ((role
         (pcase block-type
           ('agent-message 'agent-response)
           ('user-message 'agent-user-prompt)
           ('thought 'agent-thought)
           ('tool-call 'agent-tool)
           ('permission 'permission-request)
           ('plan 'agent-plan)
           ('error 'agent-error)
           (_ 'agent-block))))
    (emacsvox-agent-shell--presentation-facts
     role nil nil
     (append
      (when emacsvox-agent-shell--push-active-p '(:agent-turn-origin pushed))
      (when (eq role 'agent-block)
        (list :agent-block-kind 'other))))))

(defun emacsvox-agent-shell--speak-content (content block-type)
  "Present Agent Shell CONTENT of BLOCK-TYPE with semantic context."
  (let* ((facts (emacsvox-agent-shell-content-facts block-type))
         (occasion
          (if (memq block-type '(permission error))
              'notification
            'continuous)))
    (emacsvox-agent-shell--present-content
     content block-type facts occasion)))

(defun emacsvox-agent-shell--notify-event (text facts &optional icon occasion)
  "Submit bounded asynchronous TEXT and FACTS on the notification lane.
ICON belongs to the same transaction.  Background text identifies its shell."
  (let ((speech
         (when text
           (emacsvox-agent-shell--limit-automatic-content
            (if (emacsvox-agent-shell--session-focused-p) text
              (concat (emacsvox-agent-shell--session-label) ". " text))
            facts))))
    (apply (if speech #'emacsvox-aural-submit #'emacsvox-aural-submit-actions)
           (append
            (when speech (list speech))
            (list :facts facts :module 'agent-shell
                  :occasion (or occasion 'notification) :lane 'notification
                  :compatibility-actions
                  (when icon (list (emacsvox-aural-compatibility-icon icon))))))))

(defun emacsvox-agent-shell--speak-mode-line-around
    (original-function &rest arguments)
  "Read the full semantic header when invoked interactively in agent-shell.
Automatic mode-line speech continues through the normal Emacsvox path, as
does an interactive call with a prefix argument for buffer information."
  (let ((buffer-info (car arguments))
        (target (window-buffer (selected-window))))
    (if (and (null buffer-info)
             (ems-interactive-p 'emacsvox-speak-mode-line)
             (buffer-live-p target)
             (with-current-buffer target
               (derived-mode-p 'agent-shell-mode
                               'agent-shell-viewport-view-mode
                               'agent-shell-viewport-edit-mode)))
        (with-current-buffer target
          (emacsvox-agent-shell-speak-header))
      (apply original-function arguments))))

(defun emacsvox-agent-shell--speak-header-line-around
    (original-function &rest arguments)
  "Speak semantic agent-shell state when a graphical header has no text."
  (or (emacsvox-agent-shell--speak-focus-header-if-needed)
      (apply original-function arguments)))

(provide 'emacsvox-agent-shell-presentation)

;;; emacsvox-agent-shell-presentation.el ends here
