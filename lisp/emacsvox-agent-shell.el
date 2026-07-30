;;; emacsvox-agent-shell.el --- Speech-enable AGENT-SHELL  -*- lexical-binding: t; -*-
;; $Author: T. V. Raman $
;; Description:  Speech-enable AGENT-SHELL - Native agentic integrations
;; Keywords: Emacsvox,  Audio Desktop agent-shell
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;
;;  $Revision: 1.0 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 2025, T. V. Raman
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;
;; agent-shell provides native agentic integrations for AI agents
;; like Claude Code, Gemini CLI, Goose, Cursor, and others.
;; It is built on shell-maker and provides a comint-based interface.
;;
;; This module speech-enables agent-shell, providing:
;; - Semantic response, thought, and plan speech at turn-completion boundaries
;; - On-demand full and structural-overview speech for the latest agent answer
;; - Permission, lifecycle, error, and tool-status feedback
;; - Focus-aware foreground and background speech levels
;; - Semantic header and face-to-voice support
;; - Typed transcript and fenced source-block navigation
;; - Two-dimensional rendered Markdown table navigation and copying
;; - Viewport mode integration and reload-safe buffer teardown
;;
;; Customize `emacsvox-agent-shell' for speech levels, table feedback, and
;; lifecycle announcements.  The interactive commands document their keys.
;; See https://github.com/xenodium/agent-shell for agent-shell itself.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'agent-shell nil 'noerror)
(require 'shell-maker nil 'noerror)

(declare-function agent-shell--context-usage-face
                  "agent-shell-usage" (percentage))
(declare-function agent-shell-copy-source-block-at-point
                  "agent-shell" (&optional pos))
(declare-function agent-shell-goto-last-interaction "agent-shell" ())
(declare-function agent-shell-interaction-at-point "agent-shell" ())
(declare-function agent-shell-markdown-source-block-at-point
                  "agent-shell-markdown" (&optional pos))
(declare-function agent-shell-ui-toggle-fragment "agent-shell-ui" ())
(declare-function agent-shell-ui-toggle-all-fragments "agent-shell-ui" ())
(declare-function agent-shell-ui--toggle-fragment-at-point
                  "agent-shell-ui" ())
(declare-function emacsvox-speak--present-line-condition
                  "emacsvox-speak" (condition))
(declare-function emacsvox-speak--visual-line-condition
                  "emacsvox-speak" ())

(defvar emacsvox-comint-autospeak)
(defvar emacsvox-pronounce-date-mm-dd-yyyy-pattern)
(defvar emacsvox-pronounce-date-yyyy-mm-dd-pattern)
(defvar emacsvox-pronounce-rfc-3339-datetime-pattern)
(defvar emacsvox-pronounce-sha-checksum-pattern)
(defvar tts-speaker-process)
(defvar agent-shell-ui--fold-toggle-state)

;;;  Customization

(defgroup emacsvox-agent-shell nil
  "Speech-enable agent-shell for Emacsvox."
  :group 'emacsvox
  :prefix "emacsvox-agent-shell-")



(defcustom emacsvox-agent-shell-speak-thought-process 'icon
  "How to handle agent thought process chunks.
- \\='speak: Speak the thought process content
- \\='icon: Play an auditory icon only (default)
- nil: Silent, no feedback"
  :type '(choice (const :tag "Speak content" speak)
                 (const :tag "Icon only" icon)
                 (const :tag "Silent" nil))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-tool-output-verbosity 'summary
  "Verbosity level for tool call output.
- \\='full: Speak the complete tool output
- \\='summary: Speak a summary (status and title)
- \\='status: Only speak the final status"
  :type '(choice (const :tag "Full output" full)
                 (const :tag "Summary" summary)
                 (const :tag "Status only" status))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-speak-permissions t
  "Whether to speak permission requests immediately.
When t, permission requests are spoken as soon as they appear."
  :type 'boolean
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-speak-tool-calls t
  "Whether to announce tool calls as they happen."
  :type 'boolean
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-signal-processing t
  "Whether to announce the agent's processing lifecycle.
When non-nil, public agent-shell events produce start and completion
icons.  Exceptional completion and error events also produce a brief
spoken explanation.  Initialization has its own start and completion
cues."
  :type 'boolean
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-foreground-speech-level 'response
  "Automatic speech level for the focused agent-shell session.
The focused session is the selected agent-shell buffer or the shell associated
with the selected viewport.  `full' preserves configured response, thought,
plan, tool, and lifecycle feedback.  `response' speaks agent responses and
completion feedback while suppressing routine thought, plan, and tool chatter.
`notify' only signals completion, and `quiet' suppresses routine feedback.
Permissions and errors remain controlled separately because they may require
action."
  :type '(choice (const :tag "Full detail" full)
                 (const :tag "Responses" response)
                 (const :tag "Notifications" notify)
                 (const :tag "Quiet" quiet))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-background-speech-level 'notify
  "Automatic speech level for an unfocused agent-shell session.
The available levels have the same meaning as
`emacsvox-agent-shell-foreground-speech-level'.  Background completion uses
Emacsvox's notification stream and includes the session buffer name."
  :type '(choice (const :tag "Full detail" full)
                 (const :tag "Responses" response)
                 (const :tag "Notifications" notify)
                 (const :tag "Quiet" quiet))
  :group 'emacsvox-agent-shell)

(defvar-local emacsvox-agent-shell-speech-level 'auto
  "Per-session override for automatic agent-shell speech.
The value `auto' follows the foreground and background defaults.  The values
`full', `response', `notify', and `quiet' force that level for this session.
Use `emacsvox-agent-shell-cycle-speech-level' to change it interactively.")

(defcustom emacsvox-agent-shell-processing-start-icon 'progress
  "Auditory icon played when the model starts processing a prompt."
  :type 'symbol
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-processing-end-icon 'task-done
  "Auditory icon played when the model finishes processing."
  :type 'symbol
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-table-titles '(column)
  "Table titles spoken with the current Markdown table cell.
Column titles come from the first row when the Markdown source has a
separator row.  Row titles come from the first column, following
Emacsvox's table convention.  Customize this set to enable either,
both, or neither kind of title."
  :type '(set (const :tag "Column titles" column)
              (const :tag "Row titles" row))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-table-data-position 'first
  "Whether table cell data is spoken before or after its titles."
  :type '(choice (const :tag "Data before titles" first)
                 (const :tag "Titles before data" last))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-status-speech-labels
  '((pending . "pending")
    (in-progress . "in progress")
    (completed . "completed")
    (failed . "failed"))
  "Words spoken for agent-shell's rendered status icons.
These substitutions affect only speech copies in agent-shell and its viewport;
the visual icons remain unchanged.  Remove an entry to leave that status icon
for the active speech server to interpret."
  :type '(repeat
          (cons
           (choice (const :tag "Pending" pending)
                   (const :tag "In progress" in-progress)
                   (const :tag "Completed" completed)
                   (const :tag "Failed" failed))
           (string :tag "Spoken label")))
  :group 'emacsvox-agent-shell)

;;;  Speech Setup

;;;###autoload
(defun emacsvox-agent-shell-speech-setup ()
  "Speech setup for agent-shell."
  (setq-local emacsvox-aural-module 'agent-shell)
  (setq buffer-undo-list t)
  ;; Enable autospeak by default for agent-shell buffers
  (unless (local-variable-p 'emacsvox-comint-autospeak)
    (setq-local emacsvox-comint-autospeak t))
  (tts-set-punctuations 'all)
  (emacsvox-pronounce-add-dictionary-entry
   'agent-shell-mode
   emacsvox-pronounce-uuid-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-uuid))
  (emacsvox-pronounce-add-dictionary-entry
   'agent-shell-mode
   emacsvox-pronounce-sha-checksum-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-sha-checksum))
  (emacsvox-pronounce-add-dictionary-entry
   'agent-shell-mode
   emacsvox-pronounce-date-mm-dd-yyyy-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-mm-dd-yyyy-date))
  (emacsvox-pronounce-add-dictionary-entry
   'agent-shell-mode
   emacsvox-pronounce-date-yyyy-mm-dd-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-yyyy-mm-dd-date))
  (emacsvox-pronounce-add-dictionary-entry
   'agent-shell-mode
   emacsvox-pronounce-rfc-3339-datetime-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-decode-rfc-3339-datetime))
  (emacsvox-pronounce-refresh-pronunciations))

;;;  Voice Personalities

(defconst emacsvox-agent-shell--ui-face-voice-map
  '((agent-shell-model voice-brighten-extra)
    (agent-shell-thought-level voice-animate-extra)
    (agent-shell-container-indicator voice-lighten)
    (agent-shell-buffer-name voice-animate)
    (agent-shell-session-id voice-lighten)
    (agent-shell-session-mode voice-smoothen)
    (agent-shell-session-title voice-bolden)
    (agent-shell-session-directory voice-lighten-extra)
    (agent-shell-session-date voice-monotone-extra)
    (agent-shell-section-heading voice-bolden)
    (agent-shell-section-annotation voice-monotone)
    (agent-shell-success voice-brighten-extra)
    (agent-shell-warning voice-brighten)
    (agent-shell-error voice-bolden-and-animate)
    (agent-shell-pending voice-monotone-extra)
    (agent-shell-secondary voice-monotone-extra)
    (agent-shell-list-name voice-brighten)
    (agent-shell-list-value voice-lighten)
    (agent-shell-prompt voice-lighten-extra)
    (agent-shell-input voice-bolden-medium)
    (agent-shell-key-binding voice-annotate)
    (agent-shell-link voice-bolden)
    (agent-shell-permission-title voice-bolden)
    (agent-shell-viewport-prompt voice-monotone)
    (agent-shell-viewport-status-edit voice-brighten-extra)
    (agent-shell-viewport-status-busy voice-brighten))
  "Voice personalities for current agent-shell interface faces.")

(defconst emacsvox-agent-shell--ui-unvoiced-faces
  '(agent-shell-viewport-status-view)
  "Agent-shell interface faces intentionally left without a voice.
The neutral viewport view face carries no state beyond its spoken text.")

(defconst emacsvox-agent-shell--markdown-face-voice-map
  '((agent-shell-markdown-bold voice-bolden)
    (agent-shell-markdown-italic voice-animate)
    (agent-shell-markdown-strikethrough voice-annotate)
    (agent-shell-markdown-inline-code voice-monotone-extra)
    (agent-shell-markdown-link voice-bolden)
    (agent-shell-markdown-blockquote voice-lighten)
    (agent-shell-markdown-header-1 voice-brighten)
    (agent-shell-markdown-header-2 voice-animate)
    (agent-shell-markdown-header-3 voice-lighten)
    (agent-shell-markdown-header-4 voice-smoothen)
    (agent-shell-markdown-header-5 voice-monotone)
    (agent-shell-markdown-header-6 voice-monotone-extra)
    (agent-shell-markdown-table-header voice-bolden)
    (agent-shell-markdown-table-border inaudible)
    (agent-shell-markdown-source-block voice-monotone-extra)
    (agent-shell-markdown-source-block-language voice-smoothen))
  "Voice personalities for current agent-shell Markdown faces.")

(defconst emacsvox-agent-shell--markdown-unvoiced-faces
  '(agent-shell-markdown-table-zebra)
  "Agent-shell Markdown faces intentionally left without a voice.
Zebra striping is purely visual and should not alter table data speech.")

(voice-setup-add-map emacsvox-agent-shell--ui-face-voice-map)
(voice-setup-add-map emacsvox-agent-shell--markdown-face-voice-map)

;;;  Helper Functions

(defun emacsvox-agent-shell--speech-copy-without-yank-handler (text)
  "Return TEXT prepared for speech without invoking its clipboard handler.
Agent-shell Markdown uses `yank-handler' to make pasted content plain.  Speech
must bypass that handler so `tts-speak' retains faces and other aural display
properties while copying TEXT into its private scratch buffer."
  (if (and (stringp text)
           (> (length text) 0)
           (text-property-not-all 0 (length text) 'yank-handler nil text))
      (let ((copy (copy-sequence text)))
        (remove-text-properties 0 (length copy) '(yank-handler nil) copy)
        copy)
    text))

;; Agent-shell exposes a customizable renderer but no semantic status text
;; property.  Keep this glyph/face compatibility adapter isolated here; the
;; rendered-plan fixture test detects upstream rendering drift.
(defconst emacsvox-agent-shell--status-icon-contexts
  '((?… agent-shell-pending pending)
    (?… agent-shell-warning in-progress)
    (?✓ agent-shell-success completed)
    (?✗ agent-shell-error failed))
  "Rendered icon, face, and semantic status triples used for speech.")

(defun emacsvox-agent-shell--face-spec-includes-p (spec face)
  "Return non-nil when face SPEC contains FACE."
  (cond
   ((eq spec face) t)
   ((consp spec)
    (or (emacsvox-agent-shell--face-spec-includes-p (car spec) face)
        (emacsvox-agent-shell--face-spec-includes-p (cdr spec) face)))
   (t nil)))

(defun emacsvox-agent-shell--status-at (text position)
  "Return the semantic status represented at POSITION in TEXT."
  (let ((character (aref text position))
        (face (get-text-property position 'face text))
        (font-lock-face
         (get-text-property position 'font-lock-face text)))
    (cl-loop
     for (icon status-face status)
     in emacsvox-agent-shell--status-icon-contexts
     when (and (= character icon)
               (or
                (emacsvox-agent-shell--face-spec-includes-p
                 face status-face)
                (emacsvox-agent-shell--face-spec-includes-p
                 font-lock-face status-face)))
     return status)))

(defun emacsvox-agent-shell--replace-status-icons-for-speech (text)
  "Return TEXT with faced agent-shell status icons replaced semantically.
Only the returned speech string is changed.  Replacement words retain the
icon's text properties so its status voice remains available to Emacsvox."
  (let (replacements)
    (dotimes (position (length text))
      (when-let* ((status (emacsvox-agent-shell--status-at text position))
                  (label
                   (map-elt emacsvox-agent-shell-status-speech-labels
                            status)))
        (let ((replacement (format " %s " label)))
          (set-text-properties
           0 (length replacement) (text-properties-at position text)
           replacement)
          ;; Positions are visited in ascending order, so pushing makes this
          ;; list safe to apply from the end of the string toward its start.
          (push (cons position replacement) replacements))))
    (if (null replacements)
        text
      (let ((result text))
        (dolist (replacement replacements result)
          (let ((position (car replacement)))
            (setq result
                  (concat (substring result 0 position)
                          (cdr replacement)
                          (substring result (1+ position))))))))))

(defun emacsvox-agent-shell--prepare-speech-text (text)
  "Prepare TEXT for speech in agent-shell, leaving other modes unchanged."
  (if (and (stringp text)
           (derived-mode-p 'agent-shell-mode
                           'agent-shell-viewport-view-mode
                           'agent-shell-viewport-edit-mode))
      (emacsvox-agent-shell--replace-status-icons-for-speech
       (emacsvox-agent-shell--speech-copy-without-yank-handler text))
    text))

(defconst emacsvox-agent-shell--vertical-toggle-hint-regexp
  "\\`Press RET to toggle\\'"
  "Exact message pattern for agent-shell's collapsible-label cursor sensor.")

(defvar-local emacsvox-agent-shell--saved-message-filter nil
  "Saved local-state flag and value for `ems--message-filter'.")

(defvar-local emacsvox-agent-shell--vertical-navigation-active-p nil
  "Non-nil while an interactive vertical movement command is running.")

(defvar-local emacsvox-agent-shell--vertical-navigation-origin nil
  "Semantic block identity captured before vertical movement.")

(defun emacsvox-agent-shell--block-location-identity (location)
  "Return a stable identity for semantic block LOCATION."
  (when location
    (list
     (plist-get location :type)
     (plist-get location :position)
     (plist-get location :end))))

(defun emacsvox-agent-shell--vertical-navigation-pre-command ()
  "Remember the semantic block before interactive vertical movement."
  (setq emacsvox-agent-shell--vertical-navigation-active-p
        (memq this-command '(next-line previous-line)))
  (when emacsvox-agent-shell--vertical-navigation-active-p
    (setq emacsvox-agent-shell--vertical-navigation-origin
          (emacsvox-agent-shell--block-location-identity
           (emacsvox-agent-shell--block-location-at-point)))))

(defun emacsvox-agent-shell--vertical-navigation-post-command ()
  "Clear transient vertical block-entry state."
  (setq emacsvox-agent-shell--vertical-navigation-active-p nil
        emacsvox-agent-shell--vertical-navigation-origin nil))

(defun emacsvox-agent-shell--vertical-block-entry-facts ()
  "Return destination facts when vertical movement entered another block."
  (when emacsvox-agent-shell--vertical-navigation-active-p
    (when-let* ((location
                 (emacsvox-agent-shell--block-location-at-point))
                ((not
                  (equal
                   emacsvox-agent-shell--vertical-navigation-origin
                   (emacsvox-agent-shell--block-location-identity
                    location)))))
      (emacsvox-agent-shell--block-location-facts
       location 'focus-entered))))

(defun emacsvox-agent-shell--call-with-vertical-block-entry
    (original-function arguments)
  "Call ORIGINAL-FUNCTION with ARGUMENTS and authoritative entry facts."
  (if-let* ((facts (emacsvox-agent-shell--vertical-block-entry-facts))
            (module 'agent-shell)
            (occasion 'navigation)
            (context
             (emacsvox-aural-capture-context module occasion)))
      (let ((emacsvox-aural-submission-facts facts)
            (emacsvox-aural-submission-context context)
            (emacsvox-aural-submission-module module)
            (emacsvox-aural-submission-occasion occasion))
        (apply original-function arguments))
    (apply original-function arguments)))

(defun emacsvox-agent-shell--restore-message-filter ()
  "Restore the message filter saved before vertical motion."
  (when emacsvox-agent-shell--saved-message-filter
    (let ((was-local
           (car emacsvox-agent-shell--saved-message-filter))
          (value
           (cdr emacsvox-agent-shell--saved-message-filter)))
      (setq emacsvox-agent-shell--saved-message-filter nil)
      (if was-local
          (setq-local ems--message-filter value)
        (kill-local-variable 'ems--message-filter)))))

(defun emacsvox-agent-shell--filter-vertical-toggle-hint ()
  "Temporarily filter the redundant action hint before vertical motion.
Normal Emacsvox line speech describes the collapsible label.  Keep
agent-shell's cursor-sensor message visible, but filter its exact text from
speech until the cursor sensor has run from `post-command-hook'."
  (when (memq this-command '(next-line previous-line))
    (emacsvox-agent-shell--restore-message-filter)
    (setq emacsvox-agent-shell--saved-message-filter
          (cons (local-variable-p 'ems--message-filter)
                ems--message-filter))
    (setq-local
     ems--message-filter
     (if (stringp ems--message-filter)
         (concat "\\(?:" ems--message-filter "\\|"
                 emacsvox-agent-shell--vertical-toggle-hint-regexp
                 "\\)")
       emacsvox-agent-shell--vertical-toggle-hint-regexp))))

(defun emacsvox-agent-shell--vertical-toggle-hint-setup ()
  "Install buffer-local filtering for vertical collapsible-label entry."
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--vertical-navigation-pre-command nil t)
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--filter-vertical-toggle-hint nil t)
  ;; Cursor sensors run from `post-command-hook'.  Restore afterward so
  ;; non-arrow entry still speaks the action hint.
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--restore-message-filter t t)
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--vertical-navigation-post-command t t))

(defun emacsvox-agent-shell--vertical-toggle-hint-cleanup ()
  "Remove vertical collapsible-label filtering from the current buffer."
  (emacsvox-agent-shell--restore-message-filter)
  (emacsvox-agent-shell--vertical-navigation-post-command)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--vertical-navigation-pre-command t)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--filter-vertical-toggle-hint t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--restore-message-filter t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--vertical-navigation-post-command t))

(defvar emacsvox-agent-shell--pending-speech-timer nil
  "Legacy timer left by pause-based response speech.
New response capture uses semantic turn completion and never creates this
timer.  It remains buffer-local so reloading or disabling support can cancel
a timer created by an older loaded version.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-speech-timer)

(defvar emacsvox-agent-shell--pending-speech-qualified-ids nil
  "List of rendered turn-content IDs pending speech, in arrival order.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-speech-qualified-ids)

(defvar emacsvox-agent-shell--pending-bodies nil
  "Legacy hash table mapping qualified ID to rendered turn-content body.
Current response capture keeps buffer markers instead, but this table remains
available so a timer created by an older loaded version can finish safely.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-bodies)

(defvar emacsvox-agent-shell--pending-section-markers nil
  "Hash table mapping pending qualified IDs to body marker pairs.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-section-markers)

(defvar-local emacsvox-agent-shell--response-turn-active-p nil
  "Non-nil while a submitted agent turn can produce semantic sections.")

(defvar-local emacsvox-agent-shell--out-of-turn-speech-timer nil
  "Timer coalescing the latest rendered out-of-turn message updates.")

(defvar-local emacsvox-agent-shell--out-of-turn-pending-ids nil
  "Out-of-turn message IDs awaiting delivery, in arrival order.")

(defvar-local emacsvox-agent-shell--out-of-turn-bodies nil
  "Legacy hash table of rendered out-of-turn bodies by qualified ID.")

(defvar-local emacsvox-agent-shell--out-of-turn-section-markers nil
  "Hash table mapping out-of-turn qualified IDs to body marker pairs.")

(defvar-local emacsvox-agent-shell--out-of-turn-delivered-ids nil
  "Hash table of out-of-turn qualified IDs already delivered once.")

(defvar-local emacsvox-agent-shell--permission-subscription nil
  "Subscription token for permission request events in this shell.")

(defvar-local emacsvox-agent-shell--permission-response-subscription nil
  "Subscription token for permission response events in this shell.")

(defvar-local emacsvox-agent-shell--permission-action-cache nil
  "Hash table mapping pending permission requests to normalized actions.")

(defvar-local emacsvox-agent-shell--lifecycle-subscription nil
  "Subscription token for lifecycle events in this shell.")

(defvar-local emacsvox-agent-shell--tool-call-subscription nil
  "Subscription token for tool call update events in this shell.")

(defvar-local emacsvox-agent-shell--tool-call-status-cache nil
  "Hash table mapping tool call IDs to their last announced status.")

(defvar-local emacsvox-agent-shell--table-navigation-active nil
  "Non-nil when contextual Markdown table keys are active.")

(defvar-local emacsvox-agent-shell--table-navigation-table-start nil
  "Start position of the rendered table currently being navigated.")

(defvar-local emacsvox-agent-shell--table-navigation-origin nil
  "Point before the command most recently tracked for table entry.")

(defvar-local emacsvox-agent-shell--speech-control-active nil
  "Non-nil when agent-shell speech-level keys are active.")

(defcustom emacsvox-agent-shell-speech-delay 0.5
  "Delay used to coalesce streamed out-of-turn agent messages.
Normal response completion follows agent-shell's public `turn-complete' event,
so this value never determines when a submitted turn is spoken."
  :type 'number
  :group 'emacsvox-agent-shell)

(defconst emacsvox-agent-shell--speech-level-values
  '((quiet . 0) (notify . 1) (response . 2) (full . 3))
  "Numeric ordering of agent-shell automatic speech levels.")

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
                     (fboundp 'agent-shell-viewport--shell-buffer)
                     (eq shell-buffer
                         (agent-shell-viewport--shell-buffer
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

(defun emacsvox-agent-shell--call-with-aural-presentation
    (facts occasion function &rest arguments)
  "Call FUNCTION with ARGUMENTS inside one frozen Agent Shell presentation.

FACTS and OCCASION describe this boundary.  An enclosing, more specific
submission remains authoritative so compatibility helpers can safely use this
function without replacing lifecycle, permission, tool, or content intent."
  (emacsvox-aural-call-with-submission
   function
   :facts (or facts '(:role agent-session))
   :module 'agent-shell
   :occasion (or occasion 'continuous)
   :arguments arguments))

(defun emacsvox-agent-shell--presentation-facts
    (role &optional event states attributes)
  "Return Agent Shell facts for ROLE, EVENT, STATES, and ATTRIBUTES.

ATTRIBUTES is a property list of registered semantic attributes."
  (append
   (list :role role)
   (when event (list :events (list event)))
   (when states (list :states (copy-sequence states)))
   (copy-tree attributes)))

(defun emacsvox-agent-shell--present-feedback
    (facts occasion icon function &rest arguments)
  "Present compatibility ICON then call FUNCTION with ARGUMENTS.

FACTS and OCCASION are frozen before either modality is delivered."
  (emacsvox-agent-shell--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-agent-shell--deliver-announcement (icon text)
  "Deliver ICON and TEXT for the current session without background chatter."
  (emacsvox-agent-shell--call-with-aural-presentation
   '(:role agent-session) 'notification
   (lambda ()
     (if (emacsvox-agent-shell--session-focused-p)
         (emacsvox-aural-submit
          text
          :module 'agent-shell
          :occasion 'notification
          :compatibility-actions
          (list (emacsvox-aural-compatibility-icon icon)))
       (tts-notify-icon icon)
       (tts-notify
        (format "%s. %s"
                (emacsvox-agent-shell--session-label)
                text))))))

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
        (or (and (fboundp 'agent-shell-viewport--shell-buffer)
                 (agent-shell-viewport--shell-buffer candidate))
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
localized; individual model, thought-level, mode, and busy values use public
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
             :session-id
             (when (bound-and-true-p agent-shell-show-session-id)
               (emacsvox-agent-shell--nonempty-text
                (map-nested-elt state '(:session :id)))))))))))

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

(defvar emacsvox-agent-shell--speech-control-map
  (make-sparse-keymap)
  "Keymap for agent-shell speech-level controls.")

(defun emacsvox-agent-shell--install-speech-control-bindings ()
  "Install current speech controls, including when this file is reloaded."
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c C-q")
              #'emacsvox-agent-shell-select-speech-level)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c C-S-q")
              #'emacsvox-agent-shell-select-background-speech-level)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c C-b")
              #'emacsvox-agent-shell-speak-source-block)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c C-y")
              #'emacsvox-agent-shell-copy-source-block)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c r")
              #'emacsvox-agent-shell-speak-last-response)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c R")
              #'emacsvox-agent-shell-speak-response-overview)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c ]")
              #'emacsvox-agent-shell-next-block-of-type)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "C-c [")
              #'emacsvox-agent-shell-previous-block-of-type)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "]")
              #'emacsvox-agent-shell-next-block-at-point)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "[")
              #'emacsvox-agent-shell-previous-block-at-point))

(emacsvox-agent-shell--install-speech-control-bindings)

(unless (assq 'emacsvox-agent-shell--speech-control-active
              minor-mode-map-alist)
  (push (cons 'emacsvox-agent-shell--speech-control-active
              emacsvox-agent-shell--speech-control-map)
        minor-mode-map-alist))

(defun emacsvox-agent-shell--should-speak-p (buffer)
  "Determine if content should be spoken for BUFFER."
  (with-current-buffer buffer
    (and (bound-and-true-p emacsvox-comint-autospeak)
         (emacsvox-agent-shell--speech-level-at-least-p
          'response buffer))))

(defun emacsvox-agent-shell--release-section-marker-pair (pair)
  "Detach the start and end markers in section marker PAIR."
  (when (markerp (car-safe pair))
    (set-marker (car pair) nil))
  (when (markerp (cdr-safe pair))
    (set-marker (cdr pair) nil)))

(defun emacsvox-agent-shell--clear-section-markers (table)
  "Detach and remove every marker pair in hash TABLE."
  (when (hash-table-p table)
    (maphash
     (lambda (_qualified-id pair)
       (emacsvox-agent-shell--release-section-marker-pair pair))
     table)
    (clrhash table)))

(defun emacsvox-agent-shell--forget-section-markers
    (table qualified-id)
  "Detach and remove QUALIFIED-ID's marker pair from hash TABLE."
  (when (hash-table-p table)
    (when-let* ((pair (gethash qualified-id table)))
      (emacsvox-agent-shell--release-section-marker-pair pair))
    (remhash qualified-id table)))

(defun emacsvox-agent-shell--remember-section-markers
    (table qualified-id body-start body-end)
  "Update TABLE's body markers for QUALIFIED-ID to BODY-START and BODY-END.
The end marker advances when text is inserted at the boundary, so a streamed
append remains covered even before the next section-hook invocation."
  (let ((pair (gethash qualified-id table)))
    (if (and (markerp (car-safe pair))
             (markerp (cdr-safe pair)))
        (progn
          (set-marker (car pair) body-start (current-buffer))
          (set-marker (cdr pair) body-end (current-buffer)))
      (setq pair
            (cons (copy-marker body-start)
                  (copy-marker body-end t)))
      (puthash qualified-id pair table))
    pair))

(defun emacsvox-agent-shell--section-marker-snapshot
    (qualified-id pair)
  "Return QUALIFIED-ID and final rendered body represented by marker PAIR."
  (when-let* ((start-marker (car-safe pair))
              (end-marker (cdr-safe pair))
              ((markerp start-marker))
              ((markerp end-marker))
              ((eq (marker-buffer start-marker) (current-buffer)))
              ((eq (marker-buffer end-marker) (current-buffer)))
              (body-start (marker-position start-marker))
              (body-end (marker-position end-marker))
              ((< body-start body-end))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              ((equal qualified-id (map-elt state :qualified-id)))
              (body
               (string-trim
                (buffer-substring body-start body-end)))
              ((not (string-empty-p body))))
    (cons qualified-id body)))

(defun emacsvox-agent-shell--cancel-pending-speech ()
  "Cancel and discard response speech pending in the current shell."
  (when (timerp emacsvox-agent-shell--pending-speech-timer)
    (cancel-timer emacsvox-agent-shell--pending-speech-timer))
  (setq emacsvox-agent-shell--pending-speech-timer nil
        emacsvox-agent-shell--pending-speech-qualified-ids nil)
  (emacsvox-agent-shell--clear-section-markers
   emacsvox-agent-shell--pending-section-markers)
  (setq emacsvox-agent-shell--pending-section-markers nil)
  (when (hash-table-p emacsvox-agent-shell--pending-bodies)
    (clrhash emacsvox-agent-shell--pending-bodies)))

(defun emacsvox-agent-shell--response-section-snapshot (range)
  "Return qualified ID and rendered turn content represented by section RANGE.
Agent responses, thoughts, and plans are collected; other sections return nil.
Agent-shell calls its experimental section hook after Markdown rendering, so
the body retains semantic faces and omits markup that is no longer displayed."
  (when-let* ((body-start (map-nested-elt range '(:body :start)))
              ((< body-start (point-max)))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              (qualified-id (map-elt state :qualified-id))
              ((and (stringp qualified-id)
                    (string-match-p
                     "\\(?:agent_message_chunk\\|agent_thought_chunk\\|-plan\\)\\'"
                     qualified-id)))
              (body-end
               (or (next-single-property-change
                    body-start 'agent-shell-ui-section nil (point-max))
                   (point-max)))
              ((< body-start body-end))
              (body
               (string-trim
                (buffer-substring body-start body-end)))
              ((not (string-empty-p body))))
    (cons qualified-id body)))

(defun emacsvox-agent-shell--out-of-turn-message-id-p (qualified-id)
  "Return non-nil when QUALIFIED-ID is an explicit out-of-turn agent message."
  (and (stringp qualified-id)
       (string-prefix-p "out-of-turn-" qualified-id)
       (string-suffix-p "agent_message_chunk" qualified-id)))

(defun emacsvox-agent-shell--deliver-out-of-turn-body (body)
  "Deliver rendered out-of-turn agent message BODY according to focus policy."
  (when (bound-and-true-p emacsvox-comint-autospeak)
    (emacsvox-agent-shell--call-with-aural-presentation
     '(:role agent-response) 'notification
     (lambda ()
       (let ((focused (emacsvox-agent-shell--session-focused-p)))
         (cond
          ((and focused
                (emacsvox-agent-shell--speech-level-at-least-p 'response))
           (emacsvox-aural-submit
            (concat "Agent update: " body)
            :module 'agent-shell
            :occasion 'notification
            :compatibility-actions
            (list (emacsvox-aural-compatibility-icon 'item))))
          ((and (not focused)
                (emacsvox-agent-shell--speech-level-at-least-p 'notify))
           (tts-notify-icon 'item)
           (tts-notify
            (format "%s. Agent update available."
                    (emacsvox-agent-shell--session-label))))))))))

(defun emacsvox-agent-shell--deliver-out-of-turn-pending (buffer)
  "Deliver and clear coalesced out-of-turn messages for live BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq emacsvox-agent-shell--out-of-turn-speech-timer nil)
      (let ((qualified-ids emacsvox-agent-shell--out-of-turn-pending-ids))
        (setq emacsvox-agent-shell--out-of-turn-pending-ids nil)
        (unless (hash-table-p
                 emacsvox-agent-shell--out-of-turn-delivered-ids)
          (setq emacsvox-agent-shell--out-of-turn-delivered-ids
                (make-hash-table :test #'equal)))
        (dolist (qualified-id qualified-ids)
          (unless (gethash
                   qualified-id
                   emacsvox-agent-shell--out-of-turn-delivered-ids)
            (when-let* ((body
                         (or
                          (when-let*
                              ((pair
                                (and
                                 (hash-table-p
                                  emacsvox-agent-shell--out-of-turn-section-markers)
                                 (gethash
                                  qualified-id
                                  emacsvox-agent-shell--out-of-turn-section-markers)))
                               (snapshot
                                (emacsvox-agent-shell--section-marker-snapshot
                                 qualified-id pair)))
                            (cdr snapshot))
                          (and
                           (hash-table-p
                            emacsvox-agent-shell--out-of-turn-bodies)
                           (gethash
                            qualified-id
                            emacsvox-agent-shell--out-of-turn-bodies)))))
              (puthash
               qualified-id t
               emacsvox-agent-shell--out-of-turn-delivered-ids)
              (emacsvox-agent-shell--deliver-out-of-turn-body body)))
          (emacsvox-agent-shell--forget-section-markers
           emacsvox-agent-shell--out-of-turn-section-markers
           qualified-id)
          (when (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
            (remhash qualified-id
                     emacsvox-agent-shell--out-of-turn-bodies)))))))

(defun emacsvox-agent-shell--schedule-out-of-turn-delivery (qualified-id)
  "Queue QUALIFIED-ID for coalesced out-of-turn speech."
  (unless (member qualified-id
                  emacsvox-agent-shell--out-of-turn-pending-ids)
    (setq emacsvox-agent-shell--out-of-turn-pending-ids
          (append emacsvox-agent-shell--out-of-turn-pending-ids
                  (list qualified-id))))
  (when (timerp emacsvox-agent-shell--out-of-turn-speech-timer)
    (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer))
  (setq emacsvox-agent-shell--out-of-turn-speech-timer
        (run-with-timer
         (max 0 emacsvox-agent-shell-speech-delay) nil
         #'emacsvox-agent-shell--deliver-out-of-turn-pending
         (current-buffer))))

(defun emacsvox-agent-shell--record-out-of-turn-snapshot (snapshot)
  "Coalesce legacy rendered out-of-turn message SNAPSHOT for speech."
  (let ((qualified-id (car snapshot))
        (body (cdr snapshot)))
    (unless (and (hash-table-p
                  emacsvox-agent-shell--out-of-turn-delivered-ids)
                 (gethash
                  qualified-id
                  emacsvox-agent-shell--out-of-turn-delivered-ids))
      (unless (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
        (setq emacsvox-agent-shell--out-of-turn-bodies
              (make-hash-table :test #'equal)))
      (puthash qualified-id body
               emacsvox-agent-shell--out-of-turn-bodies)
      (emacsvox-agent-shell--schedule-out-of-turn-delivery
       qualified-id))))

(defun emacsvox-agent-shell--record-out-of-turn-section
    (qualified-id body-start body-end)
  "Coalesce QUALIFIED-ID's rendered BODY-START to BODY-END for later speech."
  (unless (and (hash-table-p
                emacsvox-agent-shell--out-of-turn-delivered-ids)
               (gethash
                qualified-id
                emacsvox-agent-shell--out-of-turn-delivered-ids))
    (unless (hash-table-p
             emacsvox-agent-shell--out-of-turn-section-markers)
      (setq emacsvox-agent-shell--out-of-turn-section-markers
            (make-hash-table :test #'equal)))
    (emacsvox-agent-shell--remember-section-markers
     emacsvox-agent-shell--out-of-turn-section-markers
     qualified-id body-start body-end)
    (emacsvox-agent-shell--schedule-out-of-turn-delivery
     qualified-id)))

(defun emacsvox-agent-shell--record-response-section (range)
  "Remember semantic turn content or an out-of-turn message in RANGE.
Only buffer markers are updated while a response streams.  Rendered text is
copied once, when the turn completes or the out-of-turn debounce timer fires."
  (when-let* ((body-start (map-nested-elt range '(:body :start)))
              ((< body-start (point-max)))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (body-end
               (or (next-single-property-change
                    body-start 'agent-shell-ui-section nil (point-max))
                   (point-max)))
              ((< body-start body-end))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              (qualified-id (map-elt state :qualified-id))
              ((and (stringp qualified-id)
                    (string-match-p
                     "\\(?:agent_message_chunk\\|agent_thought_chunk\\|-plan\\)\\'"
                     qualified-id)))
              ((or emacsvox-agent-shell--response-turn-active-p
                   (emacsvox-agent-shell--out-of-turn-message-id-p
                    qualified-id))))
    (if (emacsvox-agent-shell--out-of-turn-message-id-p qualified-id)
        (emacsvox-agent-shell--record-out-of-turn-section
         qualified-id body-start body-end)
      (unless (hash-table-p
               emacsvox-agent-shell--pending-section-markers)
        (setq emacsvox-agent-shell--pending-section-markers
                (make-hash-table :test #'equal)))
      (emacsvox-agent-shell--remember-section-markers
       emacsvox-agent-shell--pending-section-markers
       qualified-id body-start body-end)
      (unless (member qualified-id
                      emacsvox-agent-shell--pending-speech-qualified-ids)
        (setq emacsvox-agent-shell--pending-speech-qualified-ids
              (append emacsvox-agent-shell--pending-speech-qualified-ids
                      (list qualified-id)))))))

(defun emacsvox-agent-shell--out-of-turn-cleanup ()
  "Cancel and clear out-of-turn speech state in the current shell."
  (when (timerp emacsvox-agent-shell--out-of-turn-speech-timer)
    (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer))
  (setq emacsvox-agent-shell--out-of-turn-speech-timer nil
        emacsvox-agent-shell--out-of-turn-pending-ids nil)
  (emacsvox-agent-shell--clear-section-markers
   emacsvox-agent-shell--out-of-turn-section-markers)
  (when (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
    (clrhash emacsvox-agent-shell--out-of-turn-bodies))
  (when (hash-table-p emacsvox-agent-shell--out-of-turn-delivered-ids)
    (clrhash emacsvox-agent-shell--out-of-turn-delivered-ids))
  (setq emacsvox-agent-shell--out-of-turn-section-markers nil
        emacsvox-agent-shell--out-of-turn-bodies nil
        emacsvox-agent-shell--out-of-turn-delivered-ids nil))

(defun emacsvox-agent-shell--response-section-setup ()
  "Install semantic rendered turn-content capture in the current shell."
  ;; Cancel a pause timer that may survive reloading an older implementation.
  (when (timerp emacsvox-agent-shell--pending-speech-timer)
    (cancel-timer emacsvox-agent-shell--pending-speech-timer)
    (setq emacsvox-agent-shell--pending-speech-timer nil))
  (add-hook 'agent-shell-section-functions
            #'emacsvox-agent-shell--record-response-section nil t)
  ;; Enabling or reloading support during a live request should begin taking
  ;; complete snapshots on its next rendered chunk.
  (unless emacsvox-agent-shell--response-turn-active-p
    (setq emacsvox-agent-shell--response-turn-active-p
          (condition-case nil
              (memq (agent-shell-status) '(busy blocked))
            (error nil)))))

(defun emacsvox-agent-shell--response-section-cleanup ()
  "Remove semantic rendered turn-content capture from the current shell."
  (remove-hook 'agent-shell-section-functions
               #'emacsvox-agent-shell--record-response-section t)
  (setq emacsvox-agent-shell--response-turn-active-p nil)
  (emacsvox-agent-shell--out-of-turn-cleanup))

(defun emacsvox-agent-shell--begin-response-turn ()
  "Start collecting rendered turn content for a newly submitted turn."
  (emacsvox-agent-shell--cancel-pending-speech)
  (setq emacsvox-agent-shell--response-turn-active-p t))

(defun emacsvox-agent-shell--discard-response-turn ()
  "Discard collected turn content and finish the current turn."
  (setq emacsvox-agent-shell--response-turn-active-p nil)
  (emacsvox-agent-shell--cancel-pending-speech))

(defun emacsvox-agent-shell--finish-response-turn ()
  "Speak collected rendered turn content once and finish the current turn."
  (setq emacsvox-agent-shell--response-turn-active-p nil)
  (emacsvox-agent-shell--deliver-pending-blocks
   (current-buffer)
   (copy-sequence emacsvox-agent-shell--pending-speech-qualified-ids)))

(defun emacsvox-agent-shell--permission-announcement (event)
  "Return a semantic announcement for permission request EVENT."
  (let* ((data (map-elt event :data))
         (tool-call (map-elt data :tool-call))
         (tool-call-id (map-elt data :tool-call-id))
         (title (map-elt tool-call :title))
         (description
          (cond
           ((and (stringp title) (not (string-empty-p title)))
            (substring-no-properties title))
           ((and (stringp tool-call-id)
                 (not (string-empty-p tool-call-id)))
            (format "Tool %s" tool-call-id))
           (t "Unknown tool")))
         (choices
          (cl-loop
           for action in (append (map-elt tool-call :permission-actions) nil)
           for option = (map-elt action :option)
           when (and (stringp option) (not (string-empty-p option)))
           collect (substring-no-properties option))))
    (concat
     (format "Permission request. %s." description)
     (when choices
       (concat
        " "
        (mapconcat
         #'identity
         (cl-loop
          for choice in choices
          for index from 1
          collect (format "Choice %d: %s." index choice))
         " "))))))

(defun emacsvox-agent-shell--handle-permission-request (event)
  "Interrupt current speech and announce permission request EVENT."
  (let* ((data (map-elt event :data))
         (key (or (map-elt data :request-id)
                  (map-elt data :tool-call-id)))
         (actions (map-nested-elt event '(:data :tool-call
                                                :permission-actions))))
    (when key
      (unless (hash-table-p emacsvox-agent-shell--permission-action-cache)
        (setq emacsvox-agent-shell--permission-action-cache
              (make-hash-table :test #'equal)))
      (puthash key actions emacsvox-agent-shell--permission-action-cache)))
  ;; Rendered turn-content capture ignores permission fragments, so an urgent
  ;; request interrupts current speech without discarding turn content collected
  ;; so far.  A later section update refreshes the complete body snapshot.
  (when emacsvox-agent-shell-speak-permissions
    (tts-stop)
    (emacsvox-agent-shell--call-with-aural-presentation
     (emacsvox-agent-shell--presentation-facts
      'permission-request 'agent-permission-requested)
     'notification
     #'emacsvox-agent-shell--deliver-announcement
     'warn-user
     (emacsvox-agent-shell--permission-announcement event))))

(defun emacsvox-agent-shell--handle-permission-response (event)
  "Announce the semantic result of permission response EVENT."
  (let* ((data (map-elt event :data))
         (key (or (map-elt data :request-id)
                  (map-elt data :tool-call-id)))
         (option-id (map-elt data :option-id))
         (cancelled (map-elt data :cancelled))
         (actions (and key
                       (hash-table-p
                        emacsvox-agent-shell--permission-action-cache)
                       (gethash key
                                emacsvox-agent-shell--permission-action-cache)))
         (action (seq-find
                  (lambda (candidate)
                    (equal option-id (map-elt candidate :option-id)))
                  actions))
         (option (map-elt action :option))
         (kind (map-elt action :kind)))
    (when (and key
               (hash-table-p emacsvox-agent-shell--permission-action-cache))
      (remhash key emacsvox-agent-shell--permission-action-cache))
    (when emacsvox-agent-shell-speak-permissions
      (let ((result
             (cond
              (cancelled 'cancelled)
              ((equal kind "reject_once") 'denied)
              ((member kind '("allow_once" "allow_always")) 'allowed)
              (t 'sent))))
        (emacsvox-agent-shell--call-with-aural-presentation
         (emacsvox-agent-shell--presentation-facts
          'permission-request 'agent-permission-resolved nil
          (list :agent-permission-result result))
         'state-change
         (lambda ()
           (pcase result
             ('cancelled
              (emacsvox-agent-shell--deliver-announcement
               'close-object "Permission cancelled."))
             ('denied
              (emacsvox-agent-shell--deliver-announcement
               'close-object
               (format "Permission denied: %s." (or option "Reject"))))
             ('allowed
              (emacsvox-agent-shell--deliver-announcement
               'select-object
               (format "Permission granted: %s." (or option "Allow"))))
             (_
              (emacsvox-agent-shell--deliver-announcement
               'select-object "Permission response sent.")))))))))

(defun emacsvox-agent-shell--permission-event-setup ()
  "Subscribe the current agent-shell buffer to permission events."
  (unless emacsvox-agent-shell--permission-subscription
    (setq emacsvox-agent-shell--permission-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'permission-request
           :on-event #'emacsvox-agent-shell--handle-permission-request)))
  (unless emacsvox-agent-shell--permission-response-subscription
    (setq emacsvox-agent-shell--permission-response-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'permission-response
           :on-event #'emacsvox-agent-shell--handle-permission-response))))

(defun emacsvox-agent-shell--permission-event-cleanup ()
  "Remove the current buffer's permission subscriptions and cached state."
  (when emacsvox-agent-shell--permission-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--permission-subscription)
    (setq emacsvox-agent-shell--permission-subscription nil))
  (when emacsvox-agent-shell--permission-response-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--permission-response-subscription)
    (setq emacsvox-agent-shell--permission-response-subscription nil))
  (when (hash-table-p emacsvox-agent-shell--permission-action-cache)
    (clrhash emacsvox-agent-shell--permission-action-cache))
  (setq emacsvox-agent-shell--permission-action-cache nil)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--permission-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--permission-event-cleanup t))

(defun emacsvox-agent-shell--speak-agent-error (event)
  "Announce the ACP error described by lifecycle EVENT."
  (let* ((data (map-elt event :data))
         (message (map-elt data :message))
         (code (map-elt data :code))
         (detail
          (cond
           ((and (stringp message) (not (string-empty-p (string-trim message))))
            (string-trim (substring-no-properties message)))
           (code (format "code %s" code))
           (t nil))))
    (emacsvox-agent-shell--call-with-aural-presentation
     (emacsvox-agent-shell--presentation-facts
      'agent-error 'processing-failed)
     'notification
     #'emacsvox-agent-shell--deliver-announcement
     'warn-user
     (if detail
         (format "Agent error: %s" detail)
       "Agent error."))))

(defun emacsvox-agent-shell--submit-lifecycle-icon (icon)
  "Submit configurable lifecycle ICON within the current semantic boundary."
  (emacsvox-aural-submit-actions
   :compatibility-actions
   (list (emacsvox-aural-compatibility-icon icon))))

(defun emacsvox-agent-shell--speak-turn-completion (event)
  "Announce the outcome described by turn completion EVENT."
  (emacsvox-agent-shell--call-with-aural-presentation
   (emacsvox-agent-shell-lifecycle-facts event)
   'notification
   (lambda ()
     (let ((stop-reason (map-nested-elt event '(:data :stop-reason))))
       (if (equal stop-reason "end_turn")
           (when (emacsvox-agent-shell--speech-level-at-least-p 'notify)
             (if (emacsvox-agent-shell--session-focused-p)
                 (emacsvox-agent-shell--submit-lifecycle-icon
                  emacsvox-agent-shell-processing-end-icon)
               (tts-notify-icon emacsvox-agent-shell-processing-end-icon)
               (tts-notify
                (format "%s finished."
                        (emacsvox-agent-shell--session-label)))))
         (pcase stop-reason
           ("cancelled"
            (emacsvox-agent-shell--deliver-announcement
             'close-object "Agent turn cancelled."))
           ("max_tokens"
            (emacsvox-agent-shell--deliver-announcement
             'warn-user "Agent stopped: maximum token limit reached."))
           ("max_turn_requests"
            (emacsvox-agent-shell--deliver-announcement
             'warn-user "Agent stopped: request limit reached."))
           ("refusal"
            (emacsvox-agent-shell--deliver-announcement
             'warn-user "Agent refused the request."))
           ((pred stringp)
            (emacsvox-agent-shell--deliver-announcement
             'warn-user
             (format "Agent stopped: %s."
                     (string-replace "_" " " stop-reason))))
           (_
            (emacsvox-agent-shell--deliver-announcement
             'warn-user "Agent stopped for an unknown reason."))))))))

(defun emacsvox-agent-shell-lifecycle-facts (event)
  "Return semantic processing facts for Agent Shell lifecycle EVENT."
  (let* ((event-type (map-elt event :event))
         (stop-reason
          (map-nested-elt event '(:data :stop-reason)))
         (semantic-event
          (pcase event-type
            ((or 'init-started 'input-submitted) 'processing-started)
            ('init-finished 'processing-completed)
            ('turn-complete
             (if (equal stop-reason "end_turn")
                 'processing-completed
               'processing-failed))
            ('error 'processing-failed))))
    (append
     '(:role agent-session)
     (when semantic-event (list :events (list semantic-event)))
     (when (eq semantic-event 'processing-started)
       '(:states (processing))))))

(defun emacsvox-agent-shell--handle-lifecycle-event-compatibility (event)
  "Provide semantic processing feedback for public agent-shell EVENT."
  (let ((event-type (map-elt event :event)))
    ;; Response collection is independent of lifecycle cue preferences.
    ;; `turn-complete' is the semantic boundary: no network-pause timer is
    ;; allowed to deliver a partial response.
    (pcase event-type
      ('input-submitted
       (emacsvox-agent-shell--begin-response-turn))
      ('turn-complete
       (if (equal (map-nested-elt event '(:data :stop-reason)) "end_turn")
           (emacsvox-agent-shell--finish-response-turn)
         (emacsvox-agent-shell--discard-response-turn)))
      ('error
       (emacsvox-agent-shell--discard-response-turn)))
    (when (and (memq event-type '(turn-complete error))
               (hash-table-p emacsvox-agent-shell--tool-call-status-cache))
      (clrhash emacsvox-agent-shell--tool-call-status-cache))
    (when emacsvox-agent-shell-signal-processing
      (pcase event-type
        ((or 'init-started 'input-submitted)
         (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
           (emacsvox-agent-shell--submit-lifecycle-icon
            emacsvox-agent-shell-processing-start-icon)))
        ('init-finished
         (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
           (emacsvox-agent-shell--submit-lifecycle-icon
            emacsvox-agent-shell-processing-end-icon)))
        ('turn-complete
         (emacsvox-agent-shell--speak-turn-completion event))
        ('error
         (emacsvox-agent-shell--speak-agent-error event))))))

(defun emacsvox-agent-shell--handle-lifecycle-event (event)
  "Present Agent Shell lifecycle EVENT with semantic submission context."
  (emacsvox-agent-shell--call-with-aural-presentation
   (emacsvox-agent-shell-lifecycle-facts event)
   'notification
   #'emacsvox-agent-shell--handle-lifecycle-event-compatibility
   event))

(defun emacsvox-agent-shell--lifecycle-event-setup ()
  "Subscribe the current agent-shell buffer to lifecycle events."
  (unless emacsvox-agent-shell--lifecycle-subscription
    (setq emacsvox-agent-shell--lifecycle-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :on-event #'emacsvox-agent-shell--handle-lifecycle-event))))

(defun emacsvox-agent-shell--lifecycle-event-cleanup ()
  "Remove the current buffer's lifecycle event subscription."
  (when emacsvox-agent-shell--lifecycle-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--lifecycle-subscription)
    (setq emacsvox-agent-shell--lifecycle-subscription nil))
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--lifecycle-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--lifecycle-event-cleanup t))

(defun emacsvox-agent-shell--deliver-pending-blocks (buffer qualified-ids)
  "Deliver pending QUALIFIED-IDS from BUFFER and clear their stored bodies."
  (when (and buffer (buffer-live-p buffer))
    (with-current-buffer buffer
      (when (emacsvox-agent-shell--should-speak-p buffer)
        (dolist (qualified-id qualified-ids)
          (when-let* ((content
                       (or
                        (when-let*
                            ((pair
                              (and
                               (hash-table-p
                                emacsvox-agent-shell--pending-section-markers)
                               (gethash
                                qualified-id
                                emacsvox-agent-shell--pending-section-markers)))
                             (snapshot
                              (emacsvox-agent-shell--section-marker-snapshot
                               qualified-id pair)))
                          (cdr snapshot))
                        (and
                         (hash-table-p emacsvox-agent-shell--pending-bodies)
                         (gethash
                          qualified-id
                          emacsvox-agent-shell--pending-bodies))))
                      (block-id
                       (if (string-match "-\\([^-]+\\)$" qualified-id)
                           (match-string 1 qualified-id)
                         qualified-id))
                      (block-type
                       (emacsvox-agent-shell--classify-block block-id))
                      (trimmed (string-trim content)))
            (when (not (string-empty-p trimmed))
              (emacsvox-agent-shell--speak-content
               trimmed block-type)))))
      (emacsvox-agent-shell--clear-section-markers
       emacsvox-agent-shell--pending-section-markers)
      (when emacsvox-agent-shell--pending-bodies
        (clrhash emacsvox-agent-shell--pending-bodies))
      (setq emacsvox-agent-shell--pending-section-markers nil
            emacsvox-agent-shell--pending-speech-qualified-ids nil
            emacsvox-agent-shell--pending-speech-timer nil))))

(defun emacsvox-agent-shell--execute-delayed-speech (buffer qualified-ids)
  "Deliver pending QUALIFIED-IDS left by an older timer in BUFFER.
Retained so a timer created by a previously loaded pause-based implementation
can finish safely while support is being reloaded."
  (emacsvox-agent-shell--deliver-pending-blocks buffer qualified-ids))

(defun emacsvox-agent-shell--classify-block (block-id)
  "Classify BLOCK-ID to determine content type.
Returns one of: \\='agent-message, \\='user-message, \\='thought,
\\='tool-call, \\='permission, \\='plan, \\='error, or \\='unknown."
  (cond
   ((string-match-p "agent_message_chunk" block-id) 'agent-message)
   ((string-match-p "user_message_chunk" block-id) 'user-message)
   ((string-match-p "agent_thought_chunk" block-id) 'thought)
   ((string-match-p "^permission-" block-id) 'permission)
   ((string-equal block-id "plan") 'plan)
   ((string-match-p "^failed-\\|^Error" block-id) 'error)
   ((and (not (string-match-p "-chunk\\|^permission-\\|^plan\\|^Error\\|^failed-" block-id))
         (> (length block-id) 10)) 'tool-call)
   (t 'unknown)))

(defun emacsvox-agent-shell--submit-content-text (text &optional icon)
  "Submit Agent Shell content TEXT with optional compatibility ICON."
  (emacsvox-aural-submit
   text
   :compatibility-actions
   (when icon
     (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-agent-shell--submit-content-icon (icon)
  "Submit Agent Shell content compatibility ICON without spoken text."
  (emacsvox-aural-submit-actions
   :compatibility-actions
   (list (emacsvox-aural-compatibility-icon icon))))

(defun emacsvox-agent-shell--submit-text-feedback
    (text facts occasion &optional icon)
  "Submit Agent Shell TEXT with FACTS, OCCASION, and optional compatibility ICON."
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'agent-shell
   :occasion occasion
   :compatibility-actions
   (when icon
     (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-agent-shell--speak-content-compatibility (content block-type)
  "Speak CONTENT based on BLOCK-TYPE with appropriate feedback."
  (let ((trimmed-content (string-trim content)))
    (pcase block-type
      ('agent-message
       (when (emacsvox-agent-shell--speech-level-at-least-p 'response)
         (emacsvox-agent-shell--submit-content-text trimmed-content)))
      ('user-message
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-content-text
          (concat "User: " trimmed-content) 'item)))
      ('thought
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (pcase emacsvox-agent-shell-speak-thought-process
           ('speak
            (emacsvox-agent-shell--submit-content-text
             (concat "Thinking: " trimmed-content)))
           ('icon
            (emacsvox-agent-shell--submit-content-icon 'progress))
           (_ nil))))
      ('permission
       (when emacsvox-agent-shell-speak-permissions
         (emacsvox-agent-shell--deliver-announcement
          'warn-user trimmed-content)))
      ('tool-call
       (when (and emacsvox-agent-shell-speak-tool-calls
                  (emacsvox-agent-shell--speech-level-at-least-p 'full))
         (pcase emacsvox-agent-shell-tool-output-verbosity
           ('full
            (emacsvox-agent-shell--submit-content-text trimmed-content))
           ('summary
            ;; Extract just the first few lines or a summary
            (let ((lines (split-string trimmed-content "\n" t)))
              (if (<= (length lines) 3)
                  (emacsvox-agent-shell--submit-content-text trimmed-content)
                (emacsvox-agent-shell--submit-content-text
                 (string-join (seq-take lines 3) " ")))))
           ('status
            ;; Just play an icon for status-only mode
            (emacsvox-agent-shell--submit-content-icon 'task-done)))))
      ('plan
       (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-content-text
          (concat "Plan: " trimmed-content) 'item)))
      ('error
       (emacsvox-agent-shell--deliver-announcement
        'warn-user trimmed-content))
      ('unknown
       (cond
        ((emacsvox-agent-shell--speech-level-at-least-p 'full)
         (emacsvox-agent-shell--submit-content-text trimmed-content))
        ((emacsvox-agent-shell--speech-level-at-least-p 'response)
         (emacsvox-agent-shell--submit-content-text
          "Additional agent content available."))))
      (_
       ;; Fallback: speak if content is substantial
       (when (and (> (length trimmed-content) 0)
                  (emacsvox-agent-shell--speech-level-at-least-p 'response))
         (emacsvox-agent-shell--submit-content-text trimmed-content))))))

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
     (when (eq role 'agent-block)
       (list :agent-block-kind 'other)))))

(defun emacsvox-agent-shell--speak-content (content block-type)
  "Present Agent Shell CONTENT of BLOCK-TYPE with semantic context."
  (let* ((facts (emacsvox-agent-shell-content-facts block-type))
         (occasion
          (if (memq block-type '(permission error))
              'notification
            'continuous)))
    (emacsvox-agent-shell--call-with-aural-presentation
     facts occasion
     #'emacsvox-agent-shell--speak-content-compatibility
     content block-type)))

;;;  Advice Agent-Shell Functions

(defun emacsvox-agent-shell--speak-visual-line-around
    (original-function &rest arguments)
  "Add semantic blank-line presentation to visual speech in agent-shell."
  (let ((condition
         (and
          (derived-mode-p
           'agent-shell-mode
           'agent-shell-viewport-view-mode
           'agent-shell-viewport-edit-mode)
          (emacsvox-speak--visual-line-condition))))
    (when condition
      (tts-stop 'all))
    (prog1
        (emacsvox-agent-shell--call-with-vertical-block-entry
         original-function arguments)
      (when condition
        (emacsvox-speak--present-line-condition condition)))))

(defun emacsvox-agent-shell--speak-line-around
    (original-function &rest arguments)
  "Add semantic block-entry facts to vertical line speech."
  (emacsvox-agent-shell--call-with-vertical-block-entry
   original-function arguments))

(defun emacsvox-agent-shell--tts-speak-around
    (original-function text &rest arguments)
  "Preserve rendered Markdown properties while speaking agent-shell content.
This changes only the temporary speech string; agent-shell's clipboard handler
and the source buffer remain untouched."
  (apply original-function
         (emacsvox-agent-shell--prepare-speech-text text)
         arguments))

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

(defun emacsvox-agent-shell--agent-shell-after (&rest _)
  "Announce switching to agent-shell mode.
Provide an auditory icon if possible."
  (when (ems-interactive-p 'agent-shell)
    (tts-set-punctuations 'all)
    (or tts-split-caps
        (tts-toggle-split-caps))
    (emacsvox-pronounce-refresh-pronunciations)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-opened)
     'navigation 'open-object)))

(defun emacsvox-agent-shell--agent-shell-start-after (&rest _)
  "Announce agent shell startup."
  (when (ems-interactive-p 'agent-shell-start)
    (emacsvox-agent-shell--submit-text-feedback
     "Agent shell started"
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-opened)
     'state-change 'open-object)))

(defun emacsvox-agent-shell--agent-shell-new-shell-after (&rest _)
  "Announce new agent shell."
  (when (ems-interactive-p 'agent-shell-new-shell)
    (emacsvox-agent-shell--submit-text-feedback
     "New agent shell"
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-opened)
     'state-change 'open-object)))

(defun emacsvox-agent-shell--agent-shell-toggle-after (&rest _)
  "Provide auditory feedback when toggling agent shell."
  (when (ems-interactive-p 'agent-shell-toggle)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-opened)
     'navigation 'select-object)))

(defun emacsvox-agent-shell--agent-shell-other-buffer-after (&rest _)
  "Announce buffer switch."
  (when (ems-interactive-p 'agent-shell-other-buffer)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-opened)
     'navigation 'select-object)))

(defun emacsvox-agent-shell--agent-shell-interrupt-after (&rest _)
  "Confirm interruption."
  (when (ems-interactive-p 'agent-shell-interrupt)
    (emacsvox-agent-shell--submit-text-feedback
     "Agent interrupted"
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-session-interrupted)
     'state-change 'close-object)))

;;;  Output Monitoring

(defun emacsvox-agent-shell--upgrade-response-monitoring ()
  "Upgrade already enabled shell buffers to section-based monitoring."
  ;; Reloading this file preserves buffer-local subscription tokens.  They
  ;; identify buffers where support was already enabled and need the new local
  ;; section hook immediately, without restarting their sessions.
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'agent-shell-mode)
                 emacsvox-agent-shell--lifecycle-subscription)
        (emacsvox-agent-shell--response-section-setup)))))

(emacsvox-agent-shell--upgrade-response-monitoring)

;;;  Navigation Commands

(defconst emacsvox-agent-shell--block-type-choices
  '(("Agent response" . agent-response)
    ("User prompt" . user-prompt)
    ("Thought or reasoning" . thought)
    ("Tool call" . tool-call)
    ("Activity group" . activity-group)
    ("Plan" . plan)
    ("Permission" . permission)
    ("Error" . error)
    ("Table" . table)
    ("Source block" . source-block)
    ("Other" . other))
  "Completion candidates for semantic agent-shell block navigation.")

(defun emacsvox-agent-shell--normalize-block-type (type)
  "Return current semantic navigation type for TYPE.
`tool-group' is the name used by older loaded support versions."
  (if (eq type 'tool-group) 'activity-group type))

(defvar emacsvox-agent-shell--block-navigation-type 'agent-response
  "Most recently selected semantic agent-shell block type.")

;; Preserve a live session's selection when reloading across the rename.
(when (eq emacsvox-agent-shell--block-navigation-type 'tool-group)
  (setq emacsvox-agent-shell--block-navigation-type 'activity-group))

(defun emacsvox-agent-shell--block-type-label (type)
  "Return the display label for semantic block TYPE."
  (or (car (rassq
            (emacsvox-agent-shell--normalize-block-type type)
            emacsvox-agent-shell--block-type-choices))
      "Other"))

(defun emacsvox-agent-shell--block-role (type)
  "Return the registered semantic role for Agent Shell block TYPE."
  (pcase (emacsvox-agent-shell--normalize-block-type type)
    ('agent-response 'agent-response)
    ('user-prompt 'agent-user-prompt)
    ('thought 'agent-thought)
    ('tool-call 'agent-tool)
    ('permission 'permission-request)
    ('plan 'agent-plan)
    ('error 'agent-error)
    ('source-block 'agent-source-block)
    ('table 'agent-table)
    (_ 'agent-block)))

(defun emacsvox-agent-shell--block-facts
    (type &optional event attributes)
  "Return semantic facts for Agent Shell block TYPE.

EVENT describes the interaction and ATTRIBUTES augments the registered block
kind."
  (let ((kind (emacsvox-agent-shell--normalize-block-type type)))
    (emacsvox-agent-shell--presentation-facts
     (emacsvox-agent-shell--block-role kind)
     event nil
     (append (list :agent-block-kind kind) attributes))))

(defun emacsvox-agent-shell--block-location-facts (location &optional event)
  "Return semantic facts for block LOCATION and optional EVENT."
  (let ((type (or (plist-get location :type) 'other))
        attributes)
    (when-let* ((language (plist-get location :language)))
      (setq attributes
            (append attributes (list :agent-source-language language))))
    (when-let* ((visibility (plist-get location :visibility)))
      (setq attributes
            (append attributes (list :visibility visibility))))
    (emacsvox-agent-shell--block-facts
     type event attributes)))

(defun emacsvox-agent-shell--accept-block-type-default ()
  "Accept the default block type when the minibuffer is empty.
Otherwise insert the invoking character normally."
  (interactive)
  (if (string-empty-p (minibuffer-contents-no-properties))
      (exit-minibuffer)
    (self-insert-command 1)))

(defun emacsvox-agent-shell--block-type-minibuffer-setup (accept-key)
  "Bind ACCEPT-KEY to accept an empty block-type minibuffer."
  (when accept-key
    (use-local-map (copy-keymap (current-local-map)))
    (local-set-key (kbd accept-key)
                   #'emacsvox-agent-shell--accept-block-type-default)))

(defun emacsvox-agent-shell--read-block-type (&optional accept-key)
  "Read and remember a semantic agent-shell block type.
When ACCEPT-KEY is non-nil, let it accept the default on empty input."
  (let* ((default
          (emacsvox-agent-shell--block-type-label
           emacsvox-agent-shell--block-navigation-type))
         (selection
          (minibuffer-with-setup-hook
              (lambda ()
                (emacsvox-agent-shell--block-type-minibuffer-setup
                 accept-key))
            (let ((completion-ignore-case t))
              (completing-read
               (format-prompt "Block type" default)
               (mapcar #'car emacsvox-agent-shell--block-type-choices)
               nil t nil nil default)))))
    (setq emacsvox-agent-shell--block-navigation-type
          (cdr
           (assoc-string
            selection emacsvox-agent-shell--block-type-choices t)))))

(defun emacsvox-agent-shell--semantic-block-type (qualified-id state)
  "Classify QUALIFIED-ID and fragment STATE for navigation.
Agent-shell currently exposes fragment identity but no public semantic type;
keep that compatibility inference isolated here."
  (cond
   ((and (stringp qualified-id)
         (string-match-p "agent_message_chunk\\'" qualified-id))
    'agent-response)
   ((and (stringp qualified-id)
         (string-match-p "user_message_chunk\\'" qualified-id))
    'user-prompt)
   ((and (stringp qualified-id)
         (string-match-p "agent_thought_chunk\\'" qualified-id))
    'thought)
   ((and (stringp qualified-id)
         (string-match-p "permission-" qualified-id))
    'permission)
   ;; Both old `tool-calls-N' headers and current `activity-N' headers use
   ;; agent-shell-ui's stable generic group kind.
   ((eq (map-elt state :kind) 'group) 'activity-group)
   ((map-elt state :group-id) 'tool-call)
   ((and (stringp qualified-id)
         (string-match-p "-plan\\'" qualified-id))
    'plan)
   ((and (stringp qualified-id)
         (string-match-p
          "\\(?:failed-\\|Error\\|out-of-turn-acp-bug\\|[Uu]nhandled\\)"
          qualified-id))
    'error)
   (t 'other)))

(defun emacsvox-agent-shell--string-section-range
    (text start end section)
  "Return SECTION's text-property range in TEXT between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section text end)
                 end)))
        (when (eq (get-text-property
                   position 'agent-shell-ui-section text)
                  section)
          (setq result (cons position next)))
        (setq position next)))
    result))

(defun emacsvox-agent-shell--agent-answer-from-response (response)
  "Return only rendered agent answer bodies from interaction RESPONSE.
Preserve their speech properties and order while excluding thoughts, plans,
tools, and other semantic fragments.  Use the complete text as a compatibility
fallback only when RESPONSE has no agent-shell semantic fragment properties."
  (when (stringp response)
    (let ((position 0)
          (end (length response))
          semantic-p
          bodies)
      (while (< position end)
        (let* ((state
                (get-text-property
                 position 'agent-shell-ui-state response))
               (next
                (or (next-single-property-change
                     position 'agent-shell-ui-state response end)
                    end)))
          (when state
            (setq semantic-p t)
            (when
                (eq
                 (emacsvox-agent-shell--semantic-block-type
                  (map-elt state :qualified-id) state)
                 'agent-response)
              (when-let* ((body-range
                           (emacsvox-agent-shell--string-section-range
                            response position next 'body))
                          (body
                           (string-trim
                            (substring
                             response
                             (car body-range) (cdr body-range))))
                          ((not (string-empty-p body))))
                (push body bodies))))
          (setq position next)))
      (cond
       (bodies (string-join (nreverse bodies) "\n"))
       ((not semantic-p)
        (let ((plain (string-trim response)))
          (unless (string-empty-p plain) plain)))))))

(defun emacsvox-agent-shell--latest-agent-answer ()
  "Return the latest rendered answer for the current agent-shell session."
  (let ((shell-buffer (emacsvox-agent-shell--session-buffer)))
    (with-current-buffer shell-buffer
      (save-excursion
        (condition-case nil
            (progn
              (agent-shell-goto-last-interaction)
              (when-let* ((interaction
                           (agent-shell-interaction-at-point))
                          (response (map-elt interaction :response)))
                (emacsvox-agent-shell--agent-answer-from-response
                 response)))
          (error nil))))))

(defconst emacsvox-agent-shell--response-overview-preview-limit 120
  "Maximum characters used for a response overview's opening phrase.")

(defconst emacsvox-agent-shell--markdown-heading-faces
  '(agent-shell-markdown-header-1
    agent-shell-markdown-header-2
    agent-shell-markdown-header-3
    agent-shell-markdown-header-4
    agent-shell-markdown-header-5
    agent-shell-markdown-header-6)
  "Rendered Markdown faces counted as headings in response overviews.")

(defun emacsvox-agent-shell--string-run-count (text predicate)
  "Count contiguous runs in TEXT for which PREDICATE returns non-nil.
PREDICATE receives TEXT and the start position of each property run."
  (let ((position 0)
        (end (length text))
        active-p
        (count 0))
    (while (< position end)
      (let ((match-p (funcall predicate text position)))
        (when (and match-p (not active-p))
          (setq count (1+ count)))
        (setq active-p match-p
              position
              (or (next-property-change position text end) end))))
    count))

(defun emacsvox-agent-shell--string-property-run-count (text property)
  "Count contiguous non-nil PROPERTY runs in TEXT."
  (emacsvox-agent-shell--string-run-count
   text
   (lambda (value position)
     (get-text-property position property value))))

(defun emacsvox-agent-shell--string-heading-run-count (text)
  "Count contiguous rendered Markdown heading runs in TEXT."
  (emacsvox-agent-shell--string-run-count
   text
   (lambda (value position)
     (let ((face (get-text-property position 'face value))
           (font-lock-face
            (get-text-property position 'font-lock-face value)))
       (seq-some
        (lambda (heading)
          (or (emacsvox-agent-shell--face-spec-includes-p face heading)
              (emacsvox-agent-shell--face-spec-includes-p
               font-lock-face heading)))
        emacsvox-agent-shell--markdown-heading-faces)))))

(defun emacsvox-agent-shell--response-overview-preview (answer)
  "Return a bounded opening sentence or phrase from ANSWER."
  (let* ((plain
          (string-trim
           (replace-regexp-in-string
            "[[:space:]]+" " " (substring-no-properties answer))))
         (limit emacsvox-agent-shell--response-overview-preview-limit)
         (sentence-start
          (string-match "[.!?]\\(?:[[:space:]]\\|\\'\\)" plain))
         (sentence-end (and sentence-start (1+ sentence-start))))
    (cond
     ((and sentence-end (<= sentence-end limit))
      (substring plain 0 sentence-end))
     ((<= (length plain) limit) plain)
     (t
      (let* ((prefix (substring plain 0 limit))
             (word-start
              (string-match "[[:space:]][^[:space:]]*\\'" prefix))
             (cut (or word-start limit)))
        (concat (string-trim-right (substring prefix 0 cut))
                ", continued"))))))

(defun emacsvox-agent-shell--response-overview (answer)
  "Return a concise structural overview of rendered ANSWER."
  (let* ((lines (1+ (cl-count ?\n answer)))
         (headings
          (emacsvox-agent-shell--string-heading-run-count answer))
         (source-blocks
          (emacsvox-agent-shell--string-property-run-count
           answer 'agent-shell-markdown-source-block-body))
         (tables
          (emacsvox-agent-shell--string-property-run-count
           answer 'agent-shell-markdown-table-source))
         (parts
          (list (format "%d %s" lines (if (= lines 1) "line" "lines")))))
    (dolist (entry `((,headings . "heading")
                     (,source-blocks . "code block")
                     (,tables . "table")))
      (when (> (car entry) 0)
        (setq parts
              (append
               parts
               (list
                (format "%d %s%s"
                        (car entry) (cdr entry)
                        (if (= (car entry) 1) "" "s")))))))
    (format "Last response: %s. Begins: %s"
            (string-join parts ", ")
            (emacsvox-agent-shell--response-overview-preview answer))))

(defun emacsvox-agent-shell-speak-last-response ()
  "Speak the latest agent answer in full without moving point."
  (interactive)
  (if-let* ((answer (emacsvox-agent-shell--latest-agent-answer)))
      (progn
        (tts-stop)
        (emacsvox-agent-shell--submit-text-feedback
         answer
         (emacsvox-agent-shell--presentation-facts
          'agent-response 'agent-content-inspected)
         'inspection 'item))
    (emacsvox-agent-shell--submit-text-feedback
     "No agent response available."
     (emacsvox-agent-shell--presentation-facts
      'agent-response 'operation-failed)
     'inspection 'warn-user)))

(defun emacsvox-agent-shell-speak-response-overview ()
  "Speak a concise structural overview of the latest agent answer."
  (interactive)
  (if-let* ((answer (emacsvox-agent-shell--latest-agent-answer)))
      (progn
        (tts-stop)
        (emacsvox-agent-shell--submit-text-feedback
         (emacsvox-agent-shell--response-overview answer)
         (emacsvox-agent-shell--presentation-facts
          'agent-response 'agent-content-inspected)
         'inspection 'item))
    (emacsvox-agent-shell--submit-text-feedback
     "No agent response available."
     (emacsvox-agent-shell--presentation-facts
      'agent-response 'operation-failed)
     'inspection 'warn-user)))

(defun emacsvox-agent-shell--concise-block-text (text)
  "Return a concise single-line version of block TEXT."
  (when text
    (let ((plain
           (string-trim
            (replace-regexp-in-string
             "[[:space:]]+" " " (substring-no-properties text)))))
      (unless (string-empty-p plain)
        (if (> (length plain) 80)
            (concat (substring plain 0 77) "...")
          plain)))))

(defun emacsvox-agent-shell--block-section-text (start end section)
  "Return text for fragment SECTION between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section nil end)
                 end)))
        (when (eq (get-text-property position 'agent-shell-ui-section)
                  section)
          (setq result
                (buffer-substring-no-properties position next)))
        (setq position next)))
    (emacsvox-agent-shell--concise-block-text result)))

(defun emacsvox-agent-shell--block-section-range (start end section)
  "Return the range of fragment SECTION between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section nil end)
                 end)))
        (when (eq (get-text-property position 'agent-shell-ui-section)
                  section)
          (setq result (cons position next)))
        (setq position next)))
    result))

(defun emacsvox-agent-shell--visible-block-text (start end)
  "Return complete visible block text between START and END."
  (when (and start end (< start end))
    (let ((text (filter-buffer-substring start end)))
      (setq text (string-trim (substring-no-properties text)))
      (unless (string-empty-p text) text))))

(defun emacsvox-agent-shell--fragment-visibility (start end state)
  "Return semantic visibility for foldable fragment STATE from START to END."
  (when (text-property-any
         start end 'agent-shell-ui-section 'indicator)
    (if (map-elt state :collapsed) 'folded 'expanded)))

(defun emacsvox-agent-shell--fragment-location (start end state)
  "Return a semantic location for fragment STATE from START to END."
  (let* ((qualified-id (map-elt state :qualified-id))
         (type
          (emacsvox-agent-shell--semantic-block-type qualified-id state))
         (left
          (emacsvox-agent-shell--block-section-text
           start end 'label-left))
         (right
          (emacsvox-agent-shell--block-section-text
           start end 'label-right))
         (indicator
          (text-property-any
           start end 'agent-shell-ui-section 'indicator))
         (visibility
          (emacsvox-agent-shell--fragment-visibility start end state))
         (label
          (emacsvox-agent-shell--concise-block-text
           (string-join (delq nil (list left right)) " ")))
         (body-range
          (emacsvox-agent-shell--block-section-range start end 'body))
         (body
          (if body-range
              (emacsvox-agent-shell--visible-block-text
               (car body-range) (cdr body-range))
            (when (eq type 'user-prompt)
              (emacsvox-agent-shell--visible-block-text start end)))))
    (list :position start
          :end end
          :type type
          :state state
          :label label
          :body body
          :visibility visibility
          :fold-state
          (when indicator
            (if (eq visibility 'folded) "collapsed" "expanded")))))

(defun emacsvox-agent-shell--fragment-locations ()
  "Return semantic locations for all agent-shell UI fragments."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((state (get-text-property position 'agent-shell-ui-state))
             (next
              (or (next-single-property-change
                   position 'agent-shell-ui-state nil (point-max))
                  (point-max))))
        (when (and state (< position next))
          (push (emacsvox-agent-shell--fragment-location
                 position next state)
                locations))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--face-includes-p (value face)
  "Return non-nil when face specification VALUE includes FACE."
  (or (eq value face)
      (and (listp value) (memq face value))))

(defun emacsvox-agent-shell--prompt-locations ()
  "Return semantic user-prompt locations in the current buffer."
  (let (locations)
    (dolist (property '(agent-shell-viewport-prompt font-lock-face face))
      (let ((position (point-min)))
        (while (< position (point-max))
          (let* ((value (get-text-property position property))
                 (next
                  (or (next-single-property-change
                       position property nil (point-max))
                      (point-max)))
                 (prompt-p
                  (if (eq property 'agent-shell-viewport-prompt)
                      value
                    (emacsvox-agent-shell--face-includes-p
                     value 'agent-shell-prompt)))
                 (body-end
                  (when prompt-p
                    (if (eq property 'agent-shell-viewport-prompt)
                        next
                      (or (text-property-any
                           next (point-max) 'shell-maker--marker t)
                          (point-max))))))
            (when prompt-p
              (push
               (list :position position
                     :end body-end
                     :type 'user-prompt
                     :body
                     (emacsvox-agent-shell--visible-block-text
                      position body-end))
               locations))
            (setq position next)))))
    (nreverse locations)))

(defun emacsvox-agent-shell--table-locations ()
  "Return semantic locations for rendered Markdown tables."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((source
              (get-text-property
               position 'agent-shell-markdown-table-source))
             (next
              (or (next-single-property-change
                   position 'agent-shell-markdown-table-source
                   nil (point-max))
                  (point-max))))
        (when source
          (when-let* ((cell
                      (text-property-any
                       position next
                       'agent-shell-markdown-table-cell-start t)))
            (push (list :position cell
                        :start position
                        :end next
                        :type 'table
                        :state
                        (get-text-property cell 'agent-shell-ui-state))
                  locations)))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--property-range-at-position
    (property position)
  "Return PROPERTY's complete non-nil range containing POSITION."
  (when (and (< position (point-max))
             (get-text-property position property))
    (cons
     (or (previous-single-property-change
          (min (1+ position) (point-max))
          property nil (point-min))
         (point-min))
     (or (next-single-property-change
          position property nil (point-max))
         (point-max)))))

(defun emacsvox-agent-shell--fragment-location-at-position
    (position &optional metadata-only)
  "Return the agent-shell UI fragment containing POSITION.
When METADATA-ONLY is non-nil, do not copy its labels or body."
  (when-let* ((state
               (and (< position (point-max))
                    (get-text-property position 'agent-shell-ui-state)))
              (range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-ui-state position)))
    (if metadata-only
        (list
         :position (car range)
         :end (cdr range)
         :type
         (emacsvox-agent-shell--semantic-block-type
          (map-elt state :qualified-id) state)
         :state state
         :visibility
         (emacsvox-agent-shell--fragment-visibility
          (car range) (cdr range) state))
      (emacsvox-agent-shell--fragment-location
       (car range) (cdr range) state))))

(defun emacsvox-agent-shell--table-location-at-position (position)
  "Return the rendered Markdown table containing POSITION."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-markdown-table-source position))
              (cell
               (text-property-any
                (car range) (cdr range)
                'agent-shell-markdown-table-cell-start t)))
    (list :position cell
          :start (car range)
          :end (cdr range)
          :type 'table
          :state (get-text-property cell 'agent-shell-ui-state))))

(defun emacsvox-agent-shell--source-block-language (source)
  "Return the fenced code language recorded in Markdown SOURCE."
  (when (and (stringp source)
             (string-match
              "\\`[ \t]*`\\{3,\\}[ \t]*\\([[:alnum:]+#-]*\\)"
              source))
    (emacsvox-agent-shell--nonempty-text (match-string 1 source))))

(defun emacsvox-agent-shell--source-block-panel-start (body-start)
  "Return the rendered panel start preceding BODY-START."
  (let ((start body-start))
    (while (and (> start (point-min))
                (stringp
                 (get-text-property
                  (1- start) 'agent-shell-markdown-source)))
      (setq start
            (or (previous-single-property-change
                 start 'agent-shell-markdown-source nil (point-min))
                (point-min))))
    start))

(defun emacsvox-agent-shell--source-block-panel-end (body-end)
  "Return the rendered panel end following BODY-END."
  (let ((end body-end))
    (while (and (< end (point-max))
                (stringp
                 (get-text-property end 'agent-shell-markdown-source)))
      (setq end
            (or (next-single-property-change
                 end 'agent-shell-markdown-source nil (point-max))
                (point-max))))
    end))

(defun emacsvox-agent-shell--source-block-line-count (body)
  "Return the number of logical lines in source block BODY."
  (if (or (not (stringp body)) (string-empty-p body))
      0
    (let ((lines 1)
          (position 0))
      (while (string-match "\n" body position)
        (setq lines (1+ lines)
              position (match-end 0)))
      lines)))

(defun emacsvox-agent-shell--source-block-locations ()
  "Return semantic locations for rendered Markdown source blocks."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((body-p
              (get-text-property
               position 'agent-shell-markdown-source-block-body))
             (next
              (or (next-single-property-change
                   position 'agent-shell-markdown-source-block-body
                   nil (point-max))
                  (point-max))))
        (when body-p
          (let* ((source
                  (get-text-property
                   position 'agent-shell-markdown-source))
                 (body
                  (agent-shell-markdown-source-block-at-point position)))
            (push
             (list
              :position position
              :start
              (emacsvox-agent-shell--source-block-panel-start position)
              :end (emacsvox-agent-shell--source-block-panel-end next)
              :type 'source-block
              :state (get-text-property position 'agent-shell-ui-state)
              :language
              (emacsvox-agent-shell--source-block-language source)
              :line-count
              (emacsvox-agent-shell--source-block-line-count body)
              :body body)
             locations)))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--source-block-location-at-body (position)
  "Return the rendered source-block location whose body contains POSITION."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-markdown-source-block-body position))
              (body-start (car range))
              (body-end (cdr range))
              (source
               (get-text-property
                body-start 'agent-shell-markdown-source))
              (body
               (agent-shell-markdown-source-block-at-point body-start)))
    (list
     :position body-start
     :start (emacsvox-agent-shell--source-block-panel-start body-start)
     :end (emacsvox-agent-shell--source-block-panel-end body-end)
     :type 'source-block
     :state (get-text-property body-start 'agent-shell-ui-state)
     :language (emacsvox-agent-shell--source-block-language source)
     :line-count (emacsvox-agent-shell--source-block-line-count body)
     :body body)))

(defun emacsvox-agent-shell--markdown-panel-range-at-position (position)
  "Return the contiguous rendered Markdown panel containing POSITION."
  (when (and (< position (point-max))
             (stringp
              (get-text-property position 'agent-shell-markdown-source)))
    (let ((start position)
          (end position))
      (while (and (> start (point-min))
                  (stringp
                   (get-text-property
                    (1- start) 'agent-shell-markdown-source)))
        (setq start
              (or (previous-single-property-change
                   start 'agent-shell-markdown-source nil (point-min))
                  (point-min))))
      (while (and (< end (point-max))
                  (stringp
                   (get-text-property
                    end 'agent-shell-markdown-source)))
        (setq end
              (or (next-single-property-change
                   end 'agent-shell-markdown-source nil (point-max))
                  (point-max))))
      (cons start end))))

(defun emacsvox-agent-shell--source-block-location-at-position (position)
  "Return the rendered source block whose panel contains POSITION."
  (when-let* ((panel
               (emacsvox-agent-shell--markdown-panel-range-at-position
                position))
              (body
               (text-property-any
                (car panel) (cdr panel)
                'agent-shell-markdown-source-block-body t)))
    (emacsvox-agent-shell--source-block-location-at-body body)))

(defun emacsvox-agent-shell--deduplicate-block-locations (locations)
  "Return LOCATIONS without duplicate type/position pairs."
  (let (seen result)
    (dolist (location locations)
      (let ((key (cons (plist-get location :type)
                       (plist-get location :position))))
        (unless (member key seen)
          (push key seen)
          (push location result))))
    (nreverse result)))

(defun emacsvox-agent-shell--block-locations ()
  "Return all semantic transcript block locations in buffer order."
  (let* ((fragments (emacsvox-agent-shell--fragment-locations))
         (prompts (emacsvox-agent-shell--prompt-locations))
         (tables (emacsvox-agent-shell--table-locations))
         (source-blocks
          (emacsvox-agent-shell--source-block-locations))
         (locations (append fragments prompts tables source-blocks)))
    ;; A restored viewport normally retains response fragment state.  Keep a
    ;; whole-response fallback for older or plain viewport content.
    (when (and (derived-mode-p 'agent-shell-viewport-view-mode)
               (not (seq-find
                     (lambda (item)
                       (eq (plist-get item :type) 'agent-response))
                     fragments)))
      (when-let* ((prompt (car (last prompts)))
                  (start (plist-get prompt :end))
                  (response
                   (save-excursion
                     (goto-char start)
                     (skip-chars-forward " \\t\\n\\r")
                     (and (< (point) (point-max)) (point)))))
        (push (list :position response
                    :end (point-max)
                    :type 'agent-response
                    :body
                    (emacsvox-agent-shell--visible-block-text
                     response (point-max)))
              locations)))
    (sort (emacsvox-agent-shell--deduplicate-block-locations locations)
          (lambda (left right)
            (< (plist-get left :position)
               (plist-get right :position))))))

(defun emacsvox-agent-shell--fragment-location-in-direction
    (type direction origin)
  "Return the nearest UI fragment of TYPE from ORIGIN in DIRECTION."
  (save-excursion
    (goto-char origin)
    (let ((current
           (emacsvox-agent-shell--fragment-location-at-position
            origin t)))
      (if (and (eq direction 'backward)
               current
               (eq (plist-get current :type) type)
               (< (plist-get current :position) origin))
          (emacsvox-agent-shell--fragment-location-at-position
           (plist-get current :position))
        ;; Begin outside the current property run.  Starting a property
        ;; search inside a run can return only its remaining substring, and
        ;; `not-current' can skip an immediately adjacent matching run.
        (when current
          (goto-char
           (if (eq direction 'forward)
               (plist-get current :end)
             (plist-get current :position))))
        (when-let* ((match
                     (funcall
                      (if (eq direction 'forward)
                          #'text-property-search-forward
                        #'text-property-search-backward)
                      'agent-shell-ui-state nil
                      (lambda (_value state)
                        (eq
                         (emacsvox-agent-shell--semantic-block-type
                          (map-elt state :qualified-id) state)
                         type)))))
          (emacsvox-agent-shell--fragment-location
           (prop-match-beginning match)
           (prop-match-end match)
           (prop-match-value match)))))))

(defun emacsvox-agent-shell--property-location-in-direction
    (property location-function direction origin &optional end-boundary)
  "Find PROPERTY from ORIGIN and convert it with LOCATION-FUNCTION.
Search in DIRECTION.  Forward locations must begin after ORIGIN.  Backward
locations must begin before ORIGIN, or end no later than ORIGIN when
END-BOUNDARY is non-nil."
  (save-excursion
    (goto-char origin)
    (let (location match)
      (while
          (and
           (not location)
           (setq match
                 (funcall
                  (if (eq direction 'forward)
                      #'text-property-search-forward
                    #'text-property-search-backward)
                  property nil (lambda (_value value) value))))
        (let ((candidate
               (funcall location-function
                        (prop-match-beginning match))))
          (when
              (and candidate
                   (if (eq direction 'forward)
                       (> (plist-get candidate :position) origin)
                     (if end-boundary
                         (<= (plist-get candidate :end) origin)
                       (< (plist-get candidate :position) origin))))
            (setq location candidate))))
      location)))

(defun emacsvox-agent-shell--prompt-location-from-match (property match)
  "Return a user-prompt location for PROPERTY search MATCH."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                property (prop-match-beginning match)))
              (start (car range))
              (end
               (if (eq property 'agent-shell-viewport-prompt)
                   (cdr range)
                 (or (text-property-any
                      (cdr range) (point-max) 'shell-maker--marker t)
                     (point-max)))))
    (list :position start
          :end end
          :type 'user-prompt
          :body
          (emacsvox-agent-shell--visible-block-text start end))))

(defun emacsvox-agent-shell--prompt-property-location-in-direction
    (property direction origin)
  "Return the nearest prompt marked by PROPERTY from ORIGIN in DIRECTION."
  (save-excursion
    (goto-char origin)
    (let (location match)
      (while
          (and
           (not location)
           (setq match
                 (funcall
                  (if (eq direction 'forward)
                      #'text-property-search-forward
                    #'text-property-search-backward)
                  property nil
                  (if (eq property 'agent-shell-viewport-prompt)
                      (lambda (_value value) value)
                    (lambda (_value value)
                      (emacsvox-agent-shell--face-includes-p
                       value 'agent-shell-prompt))))))
        (let ((candidate
               (emacsvox-agent-shell--prompt-location-from-match
                property match)))
          (when
              (and candidate
                   (if (eq direction 'forward)
                       (> (plist-get candidate :position) origin)
                     (< (plist-get candidate :position) origin)))
            (setq location candidate))))
      location)))

(defun emacsvox-agent-shell--nearest-location (locations direction)
  "Return the nearest of LOCATIONS in DIRECTION."
  (car
   (sort
    (delq nil locations)
    (if (eq direction 'forward)
        (lambda (left right)
          (< (plist-get left :position)
             (plist-get right :position)))
      (lambda (left right)
        (> (plist-get left :position)
           (plist-get right :position)))))))

(defun emacsvox-agent-shell--prompt-location-in-direction
    (direction origin)
  "Return the nearest rendered user prompt from ORIGIN in DIRECTION."
  (emacsvox-agent-shell--nearest-location
   (mapcar
    (lambda (property)
      (emacsvox-agent-shell--prompt-property-location-in-direction
       property direction origin))
    '(agent-shell-viewport-prompt font-lock-face face))
   direction))

(defun emacsvox-agent-shell--fragment-type-exists-p (type)
  "Return non-nil when the buffer contains a UI fragment of TYPE."
  (save-excursion
    (goto-char (point-min))
    (text-property-search-forward
     'agent-shell-ui-state nil
     (lambda (_value state)
       (eq
        (emacsvox-agent-shell--semantic-block-type
         (map-elt state :qualified-id) state)
        type)))))

(defun emacsvox-agent-shell--viewport-response-location ()
  "Return the plain restored-viewport response fallback, if present."
  (when (and (derived-mode-p 'agent-shell-viewport-view-mode)
             (not
              (emacsvox-agent-shell--fragment-type-exists-p
               'agent-response)))
    (when-let* ((prompt
                 (emacsvox-agent-shell--prompt-location-in-direction
                  'backward (point-max)))
                (start (plist-get prompt :end))
                (response
                 (save-excursion
                   (goto-char start)
                   (skip-chars-forward " \t\n\r")
                   (and (< (point) (point-max)) (point)))))
      (list :position response
            :end (point-max)
            :type 'agent-response
            :body
            (emacsvox-agent-shell--visible-block-text
             response (point-max))))))

(defun emacsvox-agent-shell--block-location-in-direction
    (type direction origin)
  "Return the nearest semantic TYPE from ORIGIN in DIRECTION."
  (setq type (emacsvox-agent-shell--normalize-block-type type))
  (pcase type
    ('table
     (emacsvox-agent-shell--property-location-in-direction
      'agent-shell-markdown-table-source
      #'emacsvox-agent-shell--table-location-at-position
      direction origin t))
    ('source-block
     (emacsvox-agent-shell--property-location-in-direction
      'agent-shell-markdown-source-block-body
      #'emacsvox-agent-shell--source-block-location-at-body
      direction origin t))
    ('user-prompt
     (emacsvox-agent-shell--nearest-location
      (list
       (emacsvox-agent-shell--fragment-location-in-direction
        type direction origin)
       (emacsvox-agent-shell--prompt-location-in-direction
        direction origin))
      direction))
    ('agent-response
     (or
      (emacsvox-agent-shell--fragment-location-in-direction
       type direction origin)
      (when-let* ((fallback
                   (emacsvox-agent-shell--viewport-response-location))
                  (position (plist-get fallback :position))
                  ((if (eq direction 'forward)
                       (> position origin)
                     (< position origin))))
        fallback)))
    (_
     (emacsvox-agent-shell--fragment-location-in-direction
      type direction origin))))

(defun emacsvox-agent-shell--prompt-location-at-position (position)
  "Return the rendered user prompt containing POSITION."
  (when (< position (point-max))
    (when-let* ((candidate
                 (emacsvox-agent-shell--prompt-location-in-direction
                  'backward (min (point-max) (1+ position))))
                (start (plist-get candidate :position))
                (end (plist-get candidate :end))
                ((<= start position))
                ((< position end)))
      candidate)))

(defun emacsvox-agent-shell--innermost-block-location (locations)
  "Return the innermost semantic block from LOCATIONS."
  (car
   (sort
    (delq nil locations)
    (lambda (left right)
      (let ((left-size
             (- (plist-get left :end)
                (or (plist-get left :start)
                    (plist-get left :position))))
            (right-size
             (- (plist-get right :end)
                (or (plist-get right :start)
                    (plist-get right :position)))))
        (or (< left-size right-size)
            (and (= left-size right-size)
                 (memq (plist-get left :type) '(table source-block))
                 (not
                  (memq (plist-get right :type)
                        '(table source-block))))))))))

(defun emacsvox-agent-shell--fragment-location-by-id
    (qualified-id origin)
  "Return fragment QUALIFIED-ID nearest ORIGIN, preferring earlier content."
  (save-excursion
    (goto-char origin)
    (let ((predicate
           (lambda (_value state)
             (equal (map-elt state :qualified-id) qualified-id))))
      (when-let* ((match
                   (or
                    (text-property-search-backward
                     'agent-shell-ui-state nil predicate)
                    (progn
                      (goto-char origin)
                      (text-property-search-forward
                       'agent-shell-ui-state nil predicate)))))
        (list :position (prop-match-beginning match)
              :end (prop-match-end match)
              :type
              (emacsvox-agent-shell--semantic-block-type
               (map-elt (prop-match-value match) :qualified-id)
               (prop-match-value match))
              :state (prop-match-value match))))))

(defun emacsvox-agent-shell--expand-block-parent (location)
  "Expand LOCATION's collapsed parent group when necessary."
  (when-let* ((state (plist-get location :state))
              (group-id (map-elt state :group-id))
              ((invisible-p (plist-get location :position)))
              (parent
               (emacsvox-agent-shell--fragment-location-by-id
                group-id (plist-get location :position)))
              (parent-state (plist-get parent :state))
              ((map-elt parent-state :collapsed)))
    (goto-char (plist-get parent :position))
    (agent-shell-ui-toggle-fragment)))

(defun emacsvox-agent-shell--source-block-summary (location)
  "Return a concise spoken summary of source block LOCATION."
  (let ((language (plist-get location :language))
        (lines (plist-get location :line-count)))
    (if language
        (format "%s source block, %d %s."
                language lines (if (= lines 1) "line" "lines"))
      (format "Source block, %d %s."
              lines (if (= lines 1) "line" "lines")))))

(defun emacsvox-agent-shell--source-block-speech (location)
  "Return full voiced speech for source block LOCATION."
  (concat
   (propertize
    (emacsvox-agent-shell--source-block-summary location)
    'face 'agent-shell-markdown-source-block-language)
   " "
   (propertize
    (or (plist-get location :body) "")
    'face 'agent-shell-markdown-source-block)))

(defun emacsvox-agent-shell--activity-group-speech-label (label)
  "Return a semantic activity-group heading for rendered LABEL."
  (let ((case-fold-search t))
    (cond
     ((not label) "Activity group")
     ((string-match-p "\\_<activity\\_>" label) label)
     (t (concat "Activity group, " label)))))

(defun emacsvox-agent-shell--block-location-speech (location)
  "Return complete semantic speech for block LOCATION."
  (let* ((type (plist-get location :type))
         (label (plist-get location :label))
         (body (plist-get location :body))
         (fallback
          (or label
              (emacsvox-agent-shell--block-type-label
               type))))
    (cond
     ((eq type 'activity-group)
      (concat
       (string-join
        (delq nil
              (list
               (emacsvox-agent-shell--activity-group-speech-label label)
               (plist-get location :fold-state)))
        ", ")
       "."))
     (body
      (string-join (delq nil (list label body)) ". "))
     (t
      (concat
       (string-join
        (delq nil (list fallback (plist-get location :fold-state))) ", ")
       ".")))))

(defun emacsvox-agent-shell--jump-block-of-type
    (type direction &optional origin)
  "Move to semantic block TYPE in DIRECTION and announce it.
Use ORIGIN instead of point as the navigation boundary when non-nil."
  (unless (derived-mode-p 'agent-shell-mode
                          'agent-shell-viewport-view-mode)
    (user-error "Not in an agent-shell transcript"))
  (let* ((origin (or origin (point)))
         (target
          (emacsvox-agent-shell--block-location-in-direction
           type direction origin)))
    (if target
        (progn
          (emacsvox-agent-shell--expand-block-parent target)
          (goto-char (plist-get target :position))
          (tts-stop)
          (pcase type
            ('table
             (emacsvox-agent-shell--call-with-aural-presentation
              (emacsvox-agent-shell--block-location-facts
               target 'focus-entered)
              'navigation
              #'emacsvox-agent-shell--table-entry-feedback
              direction))
            ('source-block
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-agent-shell--source-block-summary target)
              (emacsvox-agent-shell--block-location-facts
               target 'focus-entered)
              'navigation 'open-object))
            (_
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-agent-shell--block-location-speech target)
              (emacsvox-agent-shell--block-location-facts
               target 'focus-entered)
              'navigation 'large-movement)))
          target)
      (emacsvox-agent-shell--submit-text-feedback
       (format "No %s %s%s."
               (if (eq direction 'forward) "later" "earlier")
               (downcase (emacsvox-agent-shell--block-type-label type))
               (if (eq type 'source-block) "" " block"))
       (emacsvox-agent-shell--block-facts type 'operation-failed)
       'navigation 'warn-user)
      nil)))

(defun emacsvox-agent-shell--block-location-at-point (&optional position)
  "Return the innermost semantic block containing POSITION or point.
Rendered tables and source blocks win ties with enclosing transcript blocks."
  (setq position (or position (point)))
  (or
   (emacsvox-agent-shell--innermost-block-location
    (list
     (emacsvox-agent-shell--table-location-at-position position)
     (emacsvox-agent-shell--source-block-location-at-position position)
     (emacsvox-agent-shell--fragment-location-at-position position t)
     (emacsvox-agent-shell--prompt-location-at-position position)))
   (when-let* ((fallback
                (emacsvox-agent-shell--viewport-response-location))
               ((<= (plist-get fallback :position) position))
               ((< position (plist-get fallback :end))))
     fallback)))

(defun emacsvox-agent-shell--fragment-toggle-target ()
  "Return the fragment targeted by the public toggle command at point."
  (or
   (emacsvox-agent-shell--fragment-location-at-position (point))
   (when-let* ((location
                (emacsvox-agent-shell--block-location-at-point))
               (state (plist-get location :state))
               (qualified-id (map-elt state :qualified-id))
               (fragment
                (emacsvox-agent-shell--fragment-location-by-id
                 qualified-id (point))))
     (emacsvox-agent-shell--fragment-location-at-position
      (plist-get fragment :position)))
   (save-excursion
     (when-let* ((match
                  (text-property-search-forward
                   'agent-shell-ui-state nil
                   (lambda (_value state) state))))
       (emacsvox-agent-shell--fragment-location-at-position
        (prop-match-beginning match))))))

(defun emacsvox-agent-shell--fragment-after-toggle (location)
  "Return the current fragment corresponding to pre-toggle LOCATION."
  (when-let* ((state (plist-get location :state))
              (qualified-id (map-elt state :qualified-id))
              (fragment
               (emacsvox-agent-shell--fragment-location-by-id
                qualified-id (plist-get location :position))))
    (emacsvox-agent-shell--fragment-location-at-position
     (plist-get fragment :position))))

(defun emacsvox-agent-shell--block-visibility-facts (location)
  "Return state-change facts for foldable block LOCATION."
  (emacsvox-agent-shell--presentation-facts
   'agent-block 'visibility-changed nil
   (list
    :agent-block-kind
    (emacsvox-agent-shell--normalize-block-type
     (plist-get location :type))
    :visibility (plist-get location :visibility))))

(defun emacsvox-agent-shell--expanded-block-speech (location)
  "Return useful content speech for expanded block LOCATION."
  (let ((type (plist-get location :type)))
    (or
     (when (eq type 'activity-group)
       (when-let* ((state (plist-get location :state))
                   (qualified-id (map-elt state :qualified-id))
                   (members
                    (seq-filter
                     (lambda (candidate)
                       (equal
                        (map-elt
                         (plist-get candidate :state) :group-id)
                        qualified-id))
                     (emacsvox-agent-shell--fragment-locations))))
         (string-join
          (mapcar #'emacsvox-agent-shell--block-location-speech members)
          "\n")))
     (and (plist-get location :body)
          (emacsvox-agent-shell--block-location-speech location))
     (emacsvox-agent-shell--block-location-speech location))))

(defun emacsvox-agent-shell--call-toggle-fragment
    (original-function arguments interactive-p)
  "Call fragment toggle ORIGINAL-FUNCTION with ARGUMENTS.

When INTERACTIVE-P is non-nil, announce a resulting visibility change."
  (let ((before
         (and
          interactive-p
          (emacsvox-agent-shell--fragment-toggle-target)))
        result)
    (setq result (apply original-function arguments))
    (when (and interactive-p before)
      (when-let* ((after
                   (emacsvox-agent-shell--fragment-after-toggle before))
                  (visibility (plist-get after :visibility))
                  ((not (eq visibility
                            (plist-get before :visibility)))))
        (emacsvox-agent-shell--submit-text-feedback
         (if (eq visibility 'expanded)
             (emacsvox-agent-shell--expanded-block-speech after)
           (emacsvox-agent-shell--block-location-speech after))
         (emacsvox-agent-shell--block-visibility-facts after)
         'state-change
         (if (eq visibility 'folded) 'close-object 'open-object))))
    result))

(defun emacsvox-agent-shell--toggle-fragment-around
    (original-function &rest arguments)
  "Announce a public interactive fragment visibility change."
  (emacsvox-agent-shell--call-toggle-fragment
   original-function arguments
   (ems-interactive-p 'agent-shell-ui-toggle-fragment)))

(defun emacsvox-agent-shell--toggle-fragment-action-around
    (original-function &rest arguments)
  "Announce a fragment toggle invoked by an inline RET or mouse action."
  (let ((target ems--interactive-fn-name))
    (emacsvox-agent-shell--call-toggle-fragment
     original-function arguments
     (and (functionp target) (ems-interactive-p target)))))

(defun emacsvox-agent-shell--toggle-all-fragments-around
    (original-function &rest arguments)
  "Announce the result of interactively toggling all fragments."
  (let ((interactive-p
         (ems-interactive-p 'agent-shell-ui-toggle-all-fragments))
        result)
    (setq result (apply original-function arguments))
    (when interactive-p
      (when-let* ((visibility
                   (pcase agent-shell-ui--fold-toggle-state
                     ('collapsed 'folded)
                     ('expanded 'expanded))))
        (emacsvox-agent-shell--submit-text-feedback
         (format "All Agent Shell blocks %s"
                 (if (eq visibility 'folded) "collapsed" "expanded"))
         (emacsvox-agent-shell--presentation-facts
          'agent-session 'visibility-changed nil
          (list :visibility visibility))
         'state-change
         (if (eq visibility 'folded) 'close-object 'open-object))))
    result))

(defun emacsvox-agent-shell--source-block-at-point ()
  "Return the semantic source block containing point, or signal an error."
  (let ((location (emacsvox-agent-shell--block-location-at-point)))
    (unless (eq (plist-get location :type) 'source-block)
      (user-error "Not in a rendered source block"))
    location))

(defun emacsvox-agent-shell-speak-source-block ()
  "Read the complete rendered Markdown source block at point."
  (interactive)
  (let ((location (emacsvox-agent-shell--source-block-at-point)))
    (tts-stop)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--source-block-speech location)
     (emacsvox-agent-shell--block-facts
      'source-block 'agent-content-inspected
      (when-let* ((language (plist-get location :language)))
        (list :agent-source-language language)))
     'inspection 'item)))

(defun emacsvox-agent-shell-copy-source-block ()
  "Copy the rendered Markdown source block at point using agent-shell."
  (interactive)
  (let ((location (emacsvox-agent-shell--source-block-at-point)))
    (prog1
        (let ((inhibit-message t))
          (agent-shell-copy-source-block-at-point
           (plist-get location :position)))
      (emacsvox-agent-shell--submit-text-feedback
       "Copied source block"
       (emacsvox-agent-shell--block-facts
        'source-block 'agent-content-copied
        (when-let* ((language (plist-get location :language)))
          (list :agent-source-language language)))
       'state-change 'yank-object))))

(defun emacsvox-agent-shell--literal-character-input-p ()
  "Return non-nil when this command key should insert at an editable prompt."
  (and (integerp last-command-event)
       (> (length (this-command-keys-vector)) 0)
       (eq (key-binding (this-command-keys-vector)) this-command)
       (or (derived-mode-p 'agent-shell-viewport-edit-mode)
           (and (derived-mode-p 'agent-shell-mode)
                (not (shell-maker-busy))
                (shell-maker-point-at-last-prompt-p)))))

(defun emacsvox-agent-shell--navigate-block-at-point (direction)
  "Navigate in DIRECTION using the semantic block containing point."
  (if (emacsvox-agent-shell--literal-character-input-p)
      (self-insert-command 1)
    (if-let* ((location (emacsvox-agent-shell--block-location-at-point))
              (type (plist-get location :type)))
        (progn
          (setq emacsvox-agent-shell--block-navigation-type type)
          (when (emacsvox-agent-shell--jump-block-of-type
                 type direction (plist-get location :position))
            (emacsvox-agent-shell--activate-block-repeat-map)))
      (emacsvox-agent-shell--select-and-jump-block
       direction
       (pcase (cons direction last-command-event)
         (`(forward . ,?\]) "]")
         (`(backward . ,?\[) "["))))))

(defvar emacsvox-agent-shell--block-repeat-map
  (make-sparse-keymap)
  "Temporary map for repeating semantic block navigation.")

(defun emacsvox-agent-shell--install-block-repeat-bindings ()
  "Install reload-safe semantic block repeat keys."
  (define-key emacsvox-agent-shell--block-repeat-map (kbd "]")
              #'emacsvox-agent-shell-repeat-next-block)
  (define-key emacsvox-agent-shell--block-repeat-map (kbd "[")
              #'emacsvox-agent-shell-repeat-previous-block))

(emacsvox-agent-shell--install-block-repeat-bindings)

(defun emacsvox-agent-shell--activate-block-repeat-map ()
  "Activate temporary bracket bindings for semantic block repetition."
  (set-transient-map emacsvox-agent-shell--block-repeat-map t))

(defun emacsvox-agent-shell--select-and-jump-block
    (direction &optional accept-key)
  "Select a block type and move in DIRECTION.
When ACCEPT-KEY is non-nil, let it accept the selector's default."
  (when (emacsvox-agent-shell--jump-block-of-type
         (emacsvox-agent-shell--read-block-type accept-key) direction)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(defun emacsvox-agent-shell-next-block-of-type ()
  "Select a semantic block type and move to its next occurrence."
  (interactive)
  (emacsvox-agent-shell--select-and-jump-block 'forward))

(defun emacsvox-agent-shell-previous-block-of-type ()
  "Select a semantic block type and move to its previous occurrence."
  (interactive)
  (emacsvox-agent-shell--select-and-jump-block 'backward))

(defun emacsvox-agent-shell-next-block-at-point ()
  "Move to the next block matching the semantic block at point.
When invoked by `]' at an editable prompt, insert that character instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward))

(defun emacsvox-agent-shell-previous-block-at-point ()
  "Move to the previous block matching the semantic block at point.
When invoked by `[' at an editable prompt, insert that character instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward))

(defun emacsvox-agent-shell-repeat-next-block ()
  "Move to the next occurrence of the selected semantic block type."
  (interactive)
  (when (emacsvox-agent-shell--jump-block-of-type
         emacsvox-agent-shell--block-navigation-type 'forward)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(defun emacsvox-agent-shell-repeat-previous-block ()
  "Move to the previous occurrence of the selected semantic block type."
  (interactive)
  (when (emacsvox-agent-shell--jump-block-of-type
         emacsvox-agent-shell--block-navigation-type 'backward)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(defun emacsvox-agent-shell--markdown-table-separator-p (row)
  "Return non-nil if Markdown table ROW is a separator row."
  (string-match-p "\\`[ \t]*|[-:| \t]+|[ \t]*\\'" row))

(defun emacsvox-agent-shell--markdown-table-parse-row (row)
  "Return the logical cells parsed from Markdown table ROW.
Preserve cell text properties and ignore pipes protected by agent-shell's
Markdown renderer."
  (let ((length (length row))
        (position 0)
        cells
        ended-with-separator)
    (while (and (< position length)
                (memq (aref row position) '(?\s ?\t)))
      (setq position (1+ position)))
    (when (and (< position length) (eq (aref row position) ?|))
      (setq position (1+ position)))
    (let ((cell-start position))
      (while (< position length)
        (let ((character (aref row position)))
          (cond
           ((and (eq character ?|)
                 (not (get-text-property
                       position 'agent-shell-markdown-frozen row)))
            (push (string-trim (substring row cell-start position)) cells)
            (setq position (1+ position)
                  cell-start position
                  ended-with-separator t))
           ((eq character ?\\)
            (setq position (min length (+ position 2))
                  ended-with-separator nil))
           (t
            (unless (memq character '(?\s ?\t))
              (setq ended-with-separator nil))
            (setq position (1+ position))))))
      (unless ended-with-separator
        (push (string-trim (substring row cell-start length)) cells))
    (nreverse cells))))

(defun emacsvox-agent-shell--markdown-table-rows (source)
  "Parse Markdown table SOURCE into rows and separator metadata."
  (let (rows separator-p)
    (dolist (line (split-string source "\n"))
      (unless (string-empty-p (string-trim line))
        (if (emacsvox-agent-shell--markdown-table-separator-p line)
            (setq separator-p t)
          (push (emacsvox-agent-shell--markdown-table-parse-row line)
                rows))))
    (list :rows (nreverse rows) :column-titles-p separator-p)))

(defun emacsvox-agent-shell--markdown-table-region-at-point ()
  "Return the rendered Markdown table region at point, or nil."
  (when (get-text-property (point) 'agent-shell-markdown-table-source)
    (cons
     (or (previous-single-property-change
          (min (1+ (point)) (point-max))
          'agent-shell-markdown-table-source nil (point-min))
         (point-min))
     (or (next-single-property-change
          (point) 'agent-shell-markdown-table-source nil (point-max))
         (point-max)))))

(defun emacsvox-agent-shell--markdown-table-cell-starts (region)
  "Return navigable cell positions in rendered Markdown table REGION."
  (let (positions)
    (save-excursion
      (save-restriction
        (narrow-to-region (car region) (cdr region))
        (goto-char (point-min))
        (while-let ((match (text-property-search-forward
                            'agent-shell-markdown-table-cell-start t t)))
          (push (prop-match-beginning match) positions))))
    (nreverse positions)))

(defun emacsvox-agent-shell--markdown-table-cell-at-point ()
  "Return semantic Markdown table cell data for point, or nil."
  (when-let* ((source (get-text-property
                       (point) 'agent-shell-markdown-table-source))
              (region (emacsvox-agent-shell--markdown-table-region-at-point))
              (starts
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
    (let ((cell-index -1)
          (index 0))
      (dolist (start starts)
        (when (<= start (point))
          (setq cell-index index))
        (setq index (1+ index)))
      (when (>= cell-index 0)
        (let* ((parsed (emacsvox-agent-shell--markdown-table-rows source))
               (rows (plist-get parsed :rows))
               (column-titles-p (plist-get parsed :column-titles-p))
               (remaining cell-index)
               (row-index 0)
               current-row
               column-index)
          (while (and rows (not current-row))
            (if (< remaining (length (car rows)))
                (setq current-row (car rows)
                      column-index remaining)
              (setq remaining (- remaining (length (car rows)))
                    rows (cdr rows)
                    row-index (1+ row-index))))
          (when current-row
            (let ((all-rows (plist-get parsed :rows)))
              (list
               :data (nth column-index current-row)
               :row-index row-index
               :row-count (length all-rows)
               :column-index column-index
               :column-count
               (apply #'max 0 (mapcar #'length all-rows))
               :column-titles-p column-titles-p
               :rows all-rows
               :column-title
               (when column-titles-p
                 (nth column-index (car all-rows)))
               :row-title
               (unless (and column-titles-p (zerop row-index))
                 (car current-row))))))))))

(defun emacsvox-agent-shell--table-title (title face data)
  "Return TITLE voiced with FACE unless it is blank or duplicates DATA."
  (when-let* ((title (and title (string-trim title)))
              ((not (string-empty-p title)))
              ((not (string= (substring-no-properties title)
                             (substring-no-properties data)))))
    (setq title (copy-sequence title))
    (add-face-text-property 0 (length title) face t title)
    title))

(defun emacsvox-agent-shell--table-cell-speech (cell)
  "Format semantic table CELL according to the table speech options."
  (let* ((raw-data (or (plist-get cell :data) ""))
         (data (string-trim raw-data))
         (data (if (string-empty-p data) "blank" data))
         (row-title
          (when (memq 'row emacsvox-agent-shell-table-titles)
            (emacsvox-agent-shell--table-title
             (plist-get cell :row-title) 'italic data)))
         (column-title
          (when (memq 'column emacsvox-agent-shell-table-titles)
            (emacsvox-agent-shell--table-title
             (plist-get cell :column-title) 'bold data)))
         (titles (delq nil (list row-title column-title)))
         (parts (if (eq emacsvox-agent-shell-table-data-position 'first)
                    (cons data titles)
                  (append titles (list data)))))
    (concat (mapconcat #'identity parts ", ") ".")))

(defun emacsvox-agent-shell--table-cell-facts (cell &optional event)
  "Return registered semantic facts for table CELL and optional EVENT."
  (emacsvox-agent-shell--presentation-facts
   'agent-table-cell event nil
   (list
    :agent-table-row (plist-get cell :row-index)
    :agent-table-column (plist-get cell :column-index))))

(defun emacsvox-agent-shell--table-cell-feedback ()
  "Speak the rendered Markdown table cell at point semantically."
  (when-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--table-cell-speech cell)
     (emacsvox-agent-shell--table-cell-facts cell 'focus-entered)
     'navigation 'item)
    t))

(defun emacsvox-agent-shell--table-context-speech (cell)
  "Format the position and dimensions of semantic table CELL."
  (let ((row-index (plist-get cell :row-index))
        (row-count (plist-get cell :row-count))
        (column (1+ (plist-get cell :column-index)))
        (column-count (plist-get cell :column-count)))
    (cond
     ((and (plist-get cell :column-titles-p) (zerop row-index))
      (let ((data-rows (1- row-count)))
        (format "Header row, column %d of %d; table has %d data %s."
                column column-count data-rows
                (if (= data-rows 1) "row" "rows"))))
     ((plist-get cell :column-titles-p)
      (format "Data row %d of %d, column %d of %d."
              row-index (1- row-count) column column-count))
     (t
      (format "Row %d of %d, column %d of %d."
              (1+ row-index) row-count column column-count)))))

(defun emacsvox-agent-shell--table-dimensions-speech (cell)
  "Format the dimensions of the table containing semantic CELL."
  (let* ((column-titles-p (plist-get cell :column-titles-p))
         (rows (- (plist-get cell :row-count)
                  (if column-titles-p 1 0)))
         (columns (plist-get cell :column-count)))
    (format "Table, %d %s, %d %s."
            rows
            (if column-titles-p
                (if (= rows 1) "data row" "data rows")
              (if (= rows 1) "row" "rows"))
            columns
            (if (= columns 1) "column" "columns"))))

(defun emacsvox-agent-shell--table-entry-feedback (direction)
  "Enter and speak the table at point in navigation DIRECTION."
  (when-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
              (starts
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
    (goto-char (if (eq direction 'forward) (car starts) (car (last starts))))
    (when-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (setq emacsvox-agent-shell--table-navigation-active t
            emacsvox-agent-shell--table-navigation-table-start (car region))
      (emacsvox-agent-shell--submit-text-feedback
       (concat (emacsvox-agent-shell--table-dimensions-speech cell)
               " "
               (emacsvox-agent-shell--table-cell-speech cell))
       (emacsvox-agent-shell--presentation-facts
        'agent-table 'agent-table-entered)
       'navigation 'open-object)
      t)))

(defun emacsvox-agent-shell-table-speak-context ()
  "Speak current Markdown table position and dimensions."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (emacsvox-agent-shell--submit-text-feedback
       (emacsvox-agent-shell--table-context-speech cell)
       (emacsvox-agent-shell--table-cell-facts
        cell 'agent-content-inspected)
       'inspection 'item)
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-speak-cell ()
  "Speak the logical Markdown table cell at point."
  (interactive)
  (unless (emacsvox-agent-shell--table-cell-feedback)
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-speak-dimensions ()
  "Speak the dimensions of the Markdown table at point."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (emacsvox-agent-shell--submit-text-feedback
       (emacsvox-agent-shell--table-dimensions-speech cell)
       (emacsvox-agent-shell--presentation-facts
        'agent-table 'agent-content-inspected)
       'inspection 'item)
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell--table-leading-title-speech (title face)
  "Format leading table TITLE with FACE, or return nil when it is blank."
  (when-let* ((title (emacsvox-agent-shell--table-title title face "")))
    (concat title ".")))

(defun emacsvox-agent-shell--table-row-speech (cell)
  "Format the logical table row containing semantic CELL."
  (let* ((rows (plist-get cell :rows))
         (row-index (plist-get cell :row-index))
         (row (nth row-index rows))
         (column-titles-p (plist-get cell :column-titles-p))
         (header-row-p (and column-titles-p (zerop row-index)))
         (row-title
          (when (and (not header-row-p)
                     (memq 'row emacsvox-agent-shell-table-titles))
            (emacsvox-agent-shell--table-leading-title-speech
             (car row) 'italic)))
         (first-column (if row-title 1 0))
         entries)
    (when header-row-p
      (push "Header row." entries))
    (when row-title
      (push row-title entries))
    (cl-loop
     for data in (nthcdr first-column row)
     for column from first-column
     do
     (push
      (emacsvox-agent-shell--table-cell-speech
       (list :data data
             :column-title
             (when column-titles-p (nth column (car rows)))))
      entries))
    (string-join (nreverse entries) " ")))

(defun emacsvox-agent-shell--table-column-speech (cell)
  "Format the logical table column containing semantic CELL."
  (let* ((rows (plist-get cell :rows))
         (column (plist-get cell :column-index))
         (column-titles-p (plist-get cell :column-titles-p))
         (column-title
          (when (and column-titles-p
                     (memq 'column emacsvox-agent-shell-table-titles))
            (emacsvox-agent-shell--table-leading-title-speech
             (nth column (car rows)) 'bold)))
         (data-rows (if column-titles-p (cdr rows) rows))
         entries)
    (when column-title
      (push column-title entries))
    (dolist (row data-rows)
      (push
       (emacsvox-agent-shell--table-cell-speech
        (list :data (nth column row)
              :row-title (car row)))
       entries))
    (string-join (nreverse entries) " ")))

(defun emacsvox-agent-shell-table-speak-row ()
  "Speak the logical Markdown table row at point."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (emacsvox-agent-shell--submit-text-feedback
       (emacsvox-agent-shell--table-row-speech cell)
       (emacsvox-agent-shell--table-cell-facts
        cell 'agent-content-inspected)
       'inspection 'item)
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-speak-column ()
  "Speak the logical Markdown table column at point."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (emacsvox-agent-shell--submit-text-feedback
       (emacsvox-agent-shell--table-column-speech cell)
       (emacsvox-agent-shell--table-cell-facts
        cell 'agent-content-inspected)
       'inspection 'item)
    (user-error "Not in a rendered Markdown table")))

;; Agent-shell does not currently expose a current-cell value or copy command.
;; Prefer speech-enabling that command if agent-shell adds one in the future.
(defun emacsvox-agent-shell--table-plain-cell (data)
  "Return table cell DATA without padding or text properties."
  (substring-no-properties (string-trim (or data ""))))

(defun emacsvox-agent-shell--table-copy (text object)
  "Copy plain TEXT to the kill ring and announce copied table OBJECT."
  (kill-new (substring-no-properties text))
  (emacsvox-agent-shell--submit-text-feedback
   (format "Copied table %s." object)
   (emacsvox-agent-shell--presentation-facts
    (if (string= object "cell") 'agent-table-cell 'agent-table)
    'agent-content-copied)
   'state-change 'save-object))

(defun emacsvox-agent-shell-table-copy-cell ()
  "Copy the logical Markdown table cell at point to the kill ring.
Remove renderer padding, borders, and text properties.  Preserve the complete
logical value of a wrapped cell."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (emacsvox-agent-shell--table-copy
       (emacsvox-agent-shell--table-plain-cell (plist-get cell :data))
       "cell")
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-copy-row ()
  "Copy the logical Markdown table row at point to the kill ring.
Separate cells with tabs and omit Markdown separator syntax."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point))
            (row (nth (plist-get cell :row-index)
                      (plist-get cell :rows))))
      (emacsvox-agent-shell--table-copy
       (mapconcat #'emacsvox-agent-shell--table-plain-cell row "\t")
       "row")
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-copy-column ()
  "Copy the logical Markdown table column at point to the kill ring.
Separate cells with newlines and omit Markdown separator syntax."
  (interactive)
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (let ((column (plist-get cell :column-index)))
        (emacsvox-agent-shell--table-copy
         (mapconcat
          (lambda (row)
            (emacsvox-agent-shell--table-plain-cell (nth column row)))
          (plist-get cell :rows)
          "\n")
         "column"))
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell--table-cell-position (cell row column)
  "Return the rendered position for ROW and COLUMN relative to CELL.
Return nil when that logical cell does not exist."
  (let* ((rows (plist-get cell :rows))
         (region (emacsvox-agent-shell--markdown-table-region-at-point))
         (starts
          (and region
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
         (target-row (nth row rows)))
    (when (and target-row (<= 0 column) (< column (length target-row)))
      (nth (+ column
              (apply #'+ (mapcar #'length (seq-take rows row))))
           starts))))

(defun emacsvox-agent-shell--table-boundary-feedback (message)
  "Play a boundary cue and speak MESSAGE."
  (emacsvox-agent-shell--submit-text-feedback
   message
   (emacsvox-agent-shell--presentation-facts
    'agent-table 'boundary-entered)
   'navigation 'warn-user))

(defun emacsvox-agent-shell--table-exit-destination (region direction)
  "Return a useful point outside table REGION in DIRECTION."
  (pcase direction
    ('backward
     (when (> (car region) (point-min))
       (save-excursion
         (goto-char (car region))
         (backward-char 1)
         (skip-chars-backward " \t\n\r")
         (beginning-of-line)
         (back-to-indentation)
         (point))))
    ('forward
     (when (< (cdr region) (point-max))
       (save-excursion
         (goto-char (cdr region))
         (skip-chars-forward " \t\n\r")
         (back-to-indentation)
         (point))))))

(defun emacsvox-agent-shell--table-exit (direction)
  "Leave the rendered table at point in DIRECTION and speak the destination."
  (if-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
            (destination
             (emacsvox-agent-shell--table-exit-destination region direction)))
      (progn
        (goto-char destination)
        (setq emacsvox-agent-shell--table-navigation-active nil
              emacsvox-agent-shell--table-navigation-table-start nil)
        (let ((line
               (string-trim
                (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position)))))
          (emacsvox-agent-shell--submit-text-feedback
           (format "%s table.%s"
                   (if (eq direction 'backward) "Before" "After")
                   (if (string-empty-p line) "" (concat " " line)))
           (emacsvox-agent-shell--presentation-facts
            'agent-table 'agent-table-exited)
           'navigation 'close-object)))
    (emacsvox-agent-shell--table-boundary-feedback
     (format "No content %s table."
             (if (eq direction 'backward) "before" "after")))))

(defun emacsvox-agent-shell-table-exit-backward ()
  "Leave the current Markdown table and move to preceding content."
  (interactive)
  (emacsvox-agent-shell--table-exit 'backward))

(defun emacsvox-agent-shell-table-exit-forward ()
  "Leave the current Markdown table and move to following content."
  (interactive)
  (emacsvox-agent-shell--table-exit 'forward))

(defun emacsvox-agent-shell--table-move (row-delta column-delta)
  "Move by ROW-DELTA and COLUMN-DELTA in the logical table at point."
  (if-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (let* ((row (plist-get cell :row-index))
             (column (plist-get cell :column-index))
             (rows (plist-get cell :rows))
             (target-row (+ row row-delta))
             (target-column (+ column column-delta)))
        (cond
         ((< target-row 0)
          (emacsvox-agent-shell--table-exit 'backward))
         ((>= target-row (length rows))
          (emacsvox-agent-shell--table-exit 'forward))
         ((< target-column 0)
          (emacsvox-agent-shell--table-boundary-feedback
           "Left edge of table."))
         ((>= target-column (length (nth target-row rows)))
          (emacsvox-agent-shell--table-boundary-feedback
           (if (zerop row-delta)
               "Right edge of table."
             "No cell in that row.")))
         (t
          (if-let* ((target
                    (emacsvox-agent-shell--table-cell-position
                     cell target-row target-column)))
              (progn
                (goto-char target)
                (emacsvox-agent-shell--table-cell-feedback))
            (emacsvox-agent-shell--table-boundary-feedback
             "No rendered cell at that position.")))))
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-next-column (&optional count)
  "Move COUNT columns right in the current logical Markdown table row."
  (interactive "p")
  (emacsvox-agent-shell--table-move 0 (or count 1)))

(defun emacsvox-agent-shell-table-previous-column (&optional count)
  "Move COUNT columns left in the current logical Markdown table row."
  (interactive "p")
  (emacsvox-agent-shell--table-move 0 (- (or count 1))))

(defun emacsvox-agent-shell-table-next-row (&optional count)
  "Move COUNT logical Markdown table rows down, retaining the column."
  (interactive "p")
  (emacsvox-agent-shell--table-move (or count 1) 0))

(defun emacsvox-agent-shell-table-previous-row (&optional count)
  "Move COUNT logical Markdown table rows up, retaining the column."
  (interactive "p")
  (emacsvox-agent-shell--table-move (- (or count 1)) 0))

(defvar emacsvox-agent-shell--table-navigation-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<right>")
                #'emacsvox-agent-shell-table-next-column)
    (define-key map (kbd "<left>")
                #'emacsvox-agent-shell-table-previous-column)
    (define-key map (kbd "<down>") #'emacsvox-agent-shell-table-next-row)
    (define-key map (kbd "<up>") #'emacsvox-agent-shell-table-previous-row)
    (define-key map (kbd "M-<up>")
                #'emacsvox-agent-shell-table-exit-backward)
    (define-key map (kbd "M-<down>")
                #'emacsvox-agent-shell-table-exit-forward)
    (define-key map (kbd "r") #'emacsvox-agent-shell-table-speak-row)
    (define-key map (kbd "c") #'emacsvox-agent-shell-table-speak-column)
    (define-key map (kbd "SPC") #'emacsvox-agent-shell-table-speak-cell)
    (define-key map (kbd ".") #'emacsvox-agent-shell-table-speak-context)
    (define-key map (kbd "=") #'emacsvox-agent-shell-table-speak-dimensions)
    (define-key map (kbd "w") #'emacsvox-agent-shell-table-copy-cell)
    (define-key map (kbd "a")
                #'emacsvox-agent-shell-table-select-speaking-method)
    map)
  "Contextual keymap active while point is in a rendered Markdown table.")

(defun emacsvox-agent-shell--install-table-copy-bindings ()
  "Install reload-safe table copying keys in the contextual table map."
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "k") #'emacsvox-agent-shell-table-copy-cell)
    (define-key map (kbd "r") #'emacsvox-agent-shell-table-copy-row)
    (define-key map (kbd "c") #'emacsvox-agent-shell-table-copy-column)
    (define-key emacsvox-agent-shell--table-navigation-map (kbd "k") map)))

(emacsvox-agent-shell--install-table-copy-bindings)

(unless (assq 'emacsvox-agent-shell--table-navigation-active
              minor-mode-map-alist)
  (push (cons 'emacsvox-agent-shell--table-navigation-active
              emacsvox-agent-shell--table-navigation-map)
        minor-mode-map-alist))

(defun emacsvox-agent-shell--table-navigation-entry-feedback (direction)
  "Announce entry at point, falling back to table edge in DIRECTION."
  (if-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
            (cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (progn
        (setq emacsvox-agent-shell--table-navigation-active t
              emacsvox-agent-shell--table-navigation-table-start
              (car region))
        (emacsvox-agent-shell--submit-text-feedback
         (concat (emacsvox-agent-shell--table-dimensions-speech cell)
                 " "
                 (emacsvox-agent-shell--table-cell-speech cell))
         (emacsvox-agent-shell--presentation-facts
          'agent-table 'agent-table-entered)
         'navigation 'open-object))
    (emacsvox-agent-shell--table-entry-feedback direction)))

(defun emacsvox-agent-shell--table-navigation-pre-command ()
  "Remember point before a possible contextual table entry."
  (setq emacsvox-agent-shell--table-navigation-origin (point)))

(defun emacsvox-agent-shell--table-navigation-post-command ()
  "Track table entry and toggle the contextual table keymap."
  (let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
         (table-start (and region (car region))))
    (cond
     ((not region)
      (setq emacsvox-agent-shell--table-navigation-active nil
            emacsvox-agent-shell--table-navigation-table-start nil))
     ((not (equal table-start
                  emacsvox-agent-shell--table-navigation-table-start))
      (setq emacsvox-agent-shell--table-navigation-active t)
      (tts-stop)
      (emacsvox-agent-shell--table-navigation-entry-feedback
       (if (and emacsvox-agent-shell--table-navigation-origin
                (< (point) emacsvox-agent-shell--table-navigation-origin))
           'backward
         'forward)))
     (t
      (setq emacsvox-agent-shell--table-navigation-active t)))))

(defun emacsvox-agent-shell--table-navigation-setup ()
  "Install contextual Markdown table navigation in the current buffer."
  (setq-local emacsvox-aural-module 'agent-shell)
  (setq emacsvox-agent-shell--speech-control-active t)
  (emacsvox-agent-shell--vertical-toggle-hint-setup)
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--table-navigation-pre-command nil t)
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--table-navigation-post-command nil t)
  (add-hook 'kill-buffer-hook
            #'emacsvox-agent-shell--table-navigation-cleanup nil t)
  (add-hook 'change-major-mode-hook
            #'emacsvox-agent-shell--table-navigation-cleanup nil t)
  (if-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point)))
      (setq emacsvox-agent-shell--table-navigation-active t
            emacsvox-agent-shell--table-navigation-table-start (car region))
    (setq emacsvox-agent-shell--table-navigation-active nil
          emacsvox-agent-shell--table-navigation-table-start nil)))

(defun emacsvox-agent-shell--table-navigation-cleanup ()
  "Remove contextual Markdown table navigation from the current buffer."
  (emacsvox-agent-shell--vertical-toggle-hint-cleanup)
  (setq emacsvox-agent-shell--speech-control-active nil
        emacsvox-agent-shell--table-navigation-active nil
        emacsvox-agent-shell--table-navigation-table-start nil
        emacsvox-agent-shell--table-navigation-origin nil)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--table-navigation-pre-command t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--table-navigation-post-command t)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--table-navigation-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--table-navigation-cleanup t)
  (kill-local-variable 'emacsvox-aural-module))

(defun emacsvox-agent-shell--table-settings-speech ()
  "Return a complete spoken summary of the table speech settings."
  (format "Table speech: %s; column titles %s; row titles %s."
          (if (eq emacsvox-agent-shell-table-data-position 'first)
              "data first"
            "titles first")
          (if (memq 'column emacsvox-agent-shell-table-titles) "on" "off")
          (if (memq 'row emacsvox-agent-shell-table-titles) "on" "off")))

(defun emacsvox-agent-shell--toggle-table-title (title)
  "Toggle table TITLE and retain canonical column, row ordering."
  (let ((titles
         (if (memq title emacsvox-agent-shell-table-titles)
             (remove title emacsvox-agent-shell-table-titles)
           (cons title emacsvox-agent-shell-table-titles))))
    (setq emacsvox-agent-shell-table-titles
          (seq-filter (lambda (candidate) (memq candidate titles))
                      '(column row)))))

(defun emacsvox-agent-shell-table-select-speaking-method ()
  "Interactively change automatic Markdown table cell speech.
Press c to toggle column titles, r to toggle row titles, or o to
switch between data-first and title-first ordering.  Speak the complete
resulting configuration after the change."
  (interactive)
  (pcase
      (read-char-choice
       "Toggle table speech: c column titles, r row titles, o order: "
       '(?c ?r ?o))
    (?c (emacsvox-agent-shell--toggle-table-title 'column))
    (?r (emacsvox-agent-shell--toggle-table-title 'row))
    (?o (setq emacsvox-agent-shell-table-data-position
              (if (eq emacsvox-agent-shell-table-data-position 'first)
                  'last
                'first))))
  (emacsvox-agent-shell--submit-text-feedback
   (emacsvox-agent-shell--table-settings-speech)
   (emacsvox-agent-shell--presentation-facts
    'agent-table 'agent-setting-changed)
   'state-change 'button))

(defun emacsvox-agent-shell--permission-button-text-at-point ()
  "Return the visible permission button text at point, without decoration."
  (when (get-text-property (point) 'agent-shell-permission-button)
    (let ((start (point))
          (end (point)))
      (while (and (> start (point-min))
                  (eq (get-text-property (1- start) 'button) 'permission))
        (setq start (1- start)))
      (while (and (< end (point-max))
                  (eq (get-text-property end 'button) 'permission))
        (setq end (1+ end)))
      (let ((text (string-trim
                   (buffer-substring-no-properties start end))))
        (when (and (string-prefix-p "[" text)
                   (string-suffix-p "]" text))
          (setq text (string-trim (substring text 1 -1))))
        text))))

(defun emacsvox-agent-shell--permission-button-positions-on-line ()
  "Return permission button marker positions on the current line."
  (let ((position (line-beginning-position))
        (end (line-end-position))
        positions)
    (while (and (< position end)
                (setq position
                      (text-property-any
                       position end 'agent-shell-permission-button t)))
      (push position positions)
      (setq position
            (or (next-single-property-change
                 position 'agent-shell-permission-button nil end)
                end)))
    (nreverse positions)))

(defun emacsvox-agent-shell--permission-button-feedback ()
  "Speak the focused permission choice, position, and activation key."
  (when-let* ((text (emacsvox-agent-shell--permission-button-text-at-point))
              (positions
               (emacsvox-agent-shell--permission-button-positions-on-line))
              (offset (cl-position (point) positions :test #'=)))
    (let ((label text)
          key)
      (when (string-match "\\`\\(.*\\) (\\([^()]+\\))\\'" text)
        (setq label (string-trim (match-string 1 text))
              key (match-string 2 text)))
      (emacsvox-agent-shell--submit-text-feedback
       (format "%s, choice %d of %d. Press Return%s."
               label
               (1+ offset)
               (length positions)
               (if key (format " or %s" key) ""))
       (emacsvox-agent-shell--presentation-facts
        'permission-request 'focus-entered '(selected)
        (list :completion-index offset))
       'navigation 'item)
      t)))

(defun emacsvox-agent-shell--table-sequential-edge-p (direction)
  "Return non-nil at the table edge in sequential DIRECTION."
  (when-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point))
              (rows (plist-get cell :rows)))
    (let* ((row (plist-get cell :row-index))
           (column (plist-get cell :column-index))
           (index (+ column
                     (apply #'+
                            (mapcar #'length (seq-take rows row)))))
           (count (apply #'+ (mapcar #'length rows))))
      (if (eq direction 'forward)
          (= index (1- count))
        (zerop index)))))

(defun emacsvox-agent-shell--table-between (origin destination direction)
  "Return a visible table position between ORIGIN and DESTINATION.
Search in DIRECTION.  When item navigation did not move, extend the search to
the corresponding buffer boundary."
  (let ((property 'agent-shell-markdown-table-source)
        found)
    (save-excursion
      (pcase direction
        ('forward
         (let ((limit (if (> destination origin) destination (point-max)))
               (position origin))
           (while (and (< position limit) (not found))
             (setq position
                   (next-single-property-change
                    position property nil limit))
             (when (and (< position limit)
                        (get-text-property position property)
                        (not (invisible-p position)))
               (setq found position)))))
        ('backward
         (let ((limit (if (< destination origin) destination (point-min)))
               (position origin))
           (while (and (> position limit) (not found))
             (setq position
                   (previous-single-property-change
                    position property nil limit))
             (let ((candidate (max limit (1- position))))
               (when (and (> position limit)
                          (get-text-property candidate property)
                          (not (invisible-p candidate)))
                 (setq found candidate)))))))
      found)))

(defun emacsvox-agent-shell--table-discovery-feedback
    (origin direction)
  "Stop at and announce a table skipped from ORIGIN in DIRECTION."
  (let ((destination (point)))
    (when-let* ((table-position
                (if (get-text-property
                     destination 'agent-shell-markdown-table-source)
                    destination
                  (emacsvox-agent-shell--table-between
                   origin destination direction))))
      (goto-char table-position)
      (emacsvox-agent-shell--table-entry-feedback direction))))

(defun emacsvox-agent-shell--next-item-around
    (original-function &rest arguments)
  "Discover, enter, traverse, and leave rendered tables semantically."
  (let ((interactive-p (ems-interactive-p 'agent-shell-next-item))
        (origin (point))
        (modification-tick (buffer-chars-modified-tick))
        (started-in-table-p
         (get-text-property (point) 'agent-shell-markdown-table-source))
        handled-p)
    (if (and interactive-p started-in-table-p
             (emacsvox-agent-shell--table-sequential-edge-p 'forward))
        (progn
          (setq handled-p t)
          (emacsvox-agent-shell--table-exit 'forward))
      (apply original-function arguments))
    ;; Plain n self-inserts at a live prompt; a text change is not navigation.
    (when (and interactive-p
               (not handled-p)
               (= modification-tick (buffer-chars-modified-tick)))
      (unless (or (and (not started-in-table-p)
                       (emacsvox-agent-shell--table-discovery-feedback
                        origin 'forward))
                  (emacsvox-agent-shell--permission-button-feedback)
                  (emacsvox-agent-shell--table-cell-feedback))
        (emacsvox-agent-shell--submit-text-feedback
         (ems--this-line)
         (emacsvox-agent-shell--block-location-facts
          (emacsvox-agent-shell--block-location-at-point)
          'focus-entered)
         'navigation 'item)))))

(defun emacsvox-agent-shell--previous-item-around
    (original-function &rest arguments)
  "Discover, enter, traverse, and leave rendered tables semantically."
  (let ((interactive-p (ems-interactive-p 'agent-shell-previous-item))
        (origin (point))
        (modification-tick (buffer-chars-modified-tick))
        (started-in-table-p
         (get-text-property (point) 'agent-shell-markdown-table-source))
        handled-p)
    (if (and interactive-p started-in-table-p
             (emacsvox-agent-shell--table-sequential-edge-p 'backward))
        (progn
          (setq handled-p t)
          (emacsvox-agent-shell--table-exit 'backward))
      (apply original-function arguments))
    ;; Plain p self-inserts at a live prompt; a text change is not navigation.
    (when (and interactive-p
               (not handled-p)
               (= modification-tick (buffer-chars-modified-tick)))
      (unless (or (and (not started-in-table-p)
                       (emacsvox-agent-shell--table-discovery-feedback
                        origin 'backward))
                  (emacsvox-agent-shell--permission-button-feedback)
                  (emacsvox-agent-shell--table-cell-feedback))
        (emacsvox-agent-shell--submit-text-feedback
         (ems--this-line)
         (emacsvox-agent-shell--block-location-facts
          (emacsvox-agent-shell--block-location-at-point)
          'focus-entered)
         'navigation 'item)))))

(defun emacsvox-agent-shell--jump-to-permission-after
    (result &rest _)
  "Announce jump to permission."
  (prog1 result
    (when (and
           (ems-interactive-p
            'agent-shell-jump-to-latest-permission-button-row)
           result)
      (emacsvox-agent-shell--permission-button-feedback))))

(defun emacsvox-agent-shell--next-permission-button-after
    (result &rest _)
  "Speak the next permission choice after moving to it."
  (prog1 result
    (when (and
           (ems-interactive-p 'agent-shell-next-permission-button)
           result)
      (emacsvox-agent-shell--permission-button-feedback))))

(defun emacsvox-agent-shell--previous-permission-button-after
    (result &rest _)
  "Speak the previous permission choice after moving to it."
  (prog1 result
    (when (and
           (ems-interactive-p 'agent-shell-previous-permission-button)
           result)
      (emacsvox-agent-shell--permission-button-feedback))))

;;;  Session Management

(defun emacsvox-agent-shell--session-setting-speech
    (property label fallback)
  "Describe session PROPERTY using LABEL, or return FALLBACK."
  (if-let* ((state (emacsvox-agent-shell--header-state))
            (value (plist-get state property)))
      (format "%s %s." label value)
    fallback))

(defun emacsvox-agent-shell--set-session-model-after (&rest _)
  "Announce model change."
  (when (ems-interactive-p 'agent-shell-set-session-model)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--session-setting-speech
      :model "Model" "Model changed.")
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change 'select-object)))

(defun emacsvox-agent-shell--set-session-mode-after (&rest _)
  "Announce session mode change."
  (when (ems-interactive-p 'agent-shell-set-session-mode)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--session-setting-speech
      :mode "Session mode" "Session mode changed.")
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change 'select-object)))

(defun emacsvox-agent-shell--cycle-session-mode-after (&rest _)
  "Announce session mode cycle."
  (when (ems-interactive-p 'agent-shell-cycle-session-mode)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--session-setting-speech
      :mode "Session mode" "Session mode changed.")
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change 'select-object)))

;;;  Viewport Mode Integration

(defun emacsvox-agent-shell--viewport-next-item-around
    (original-function &rest arguments)
  "Discover, enter, traverse, and leave tables in the viewport."
  (let ((interactive-p
         (ems-interactive-p 'agent-shell-viewport-next-item))
        (origin (point))
        (started-in-table-p
         (get-text-property (point) 'agent-shell-markdown-table-source))
        handled-p)
    (if (and interactive-p started-in-table-p
             (emacsvox-agent-shell--table-sequential-edge-p 'forward))
        (progn
          (setq handled-p t)
          (emacsvox-agent-shell--table-exit 'forward))
      (apply original-function arguments))
    (when (and interactive-p (not handled-p))
      (or (and (not started-in-table-p)
               (emacsvox-agent-shell--table-discovery-feedback
                origin 'forward))
          (emacsvox-agent-shell--table-cell-feedback)))))

(defun emacsvox-agent-shell--viewport-previous-item-around
    (original-function &rest arguments)
  "Discover, enter, traverse, and leave tables in the viewport."
  (let ((interactive-p
         (ems-interactive-p 'agent-shell-viewport-previous-item))
        (origin (point))
        (started-in-table-p
         (get-text-property (point) 'agent-shell-markdown-table-source))
        handled-p)
    (if (and interactive-p started-in-table-p
             (emacsvox-agent-shell--table-sequential-edge-p 'backward))
        (progn
          (setq handled-p t)
          (emacsvox-agent-shell--table-exit 'backward))
      (apply original-function arguments))
    (when (and interactive-p (not handled-p))
      (or (and (not started-in-table-p)
               (emacsvox-agent-shell--table-discovery-feedback
                origin 'backward))
          (emacsvox-agent-shell--table-cell-feedback)))))

(defun emacsvox-agent-shell--viewport-show-buffer-after (&rest _)
  "Announce viewport display."
  (when (ems-interactive-p 'agent-shell-viewport--show-buffer)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-viewport-opened)
     'navigation 'open-object #'emacsvox-speak-mode-line)))

(defun emacsvox-agent-shell--prompt-compose-after (&rest _)
  "Announce prompt composition."
  (when (ems-interactive-p 'agent-shell-prompt-compose)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-prompt-editor 'agent-prompt-opened)
     'edit 'open-object #'message "Compose prompt")))

(defun emacsvox-agent-shell--viewport-refresh-after (&rest _)
  "Announce viewport refresh."
  (when (ems-interactive-p 'agent-shell-viewport-refresh)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-viewport-refreshed)
     'state-change 'task-done #'message "Viewport refreshed")))

(defun emacsvox-agent-shell--viewport-submit-disposition ()
  "Return how a viewport prompt will be handled, or nil when unknown.
The public session status is sampled before submission because a successful
direct submission immediately changes it to busy."
  (condition-case nil
      (when-let* ((shell-buffer (emacsvox-agent-shell--session-buffer)))
        (pcase (agent-shell-status :shell-buffer shell-buffer)
          ((or 'busy 'blocked) 'queued)
          ('ready 'submitted)))
    (error nil)))

(defun emacsvox-agent-shell--viewport-submit-announcement
    (disposition keep-composing dismiss)
  "Describe viewport submission DISPOSITION and its composition outcome.
KEEP-COMPOSING means the cleared editor remains ready for another prompt.
DISMISS means the compose window is dismissed."
  (concat
   (pcase disposition
     ('queued "Prompt queued.")
     ('submitted "Prompt submitted.")
     (_ "Prompt sent."))
   (cond
    (keep-composing " Continue composing.")
    (dismiss " Compose window dismissed.")
    (t ""))))

(defun emacsvox-agent-shell--viewport-compose-send-around
    (original-function &rest arguments)
  "Announce whether a prompt was submitted or queued and where focus remains."
  (let* ((interactive-p
          (ems-interactive-p 'agent-shell-viewport-compose-send))
         (keep-composing
          (and interactive-p (car arguments)))
         (dismiss
          (and interactive-p
               (not keep-composing)
               (boundp 'agent-shell-viewport-dismiss-on-send)
               agent-shell-viewport-dismiss-on-send))
         (disposition
          (and interactive-p
               (emacsvox-agent-shell--viewport-submit-disposition))))
    (prog1
        (apply original-function arguments)
      (when interactive-p
        (emacsvox-agent-shell--present-feedback
         (emacsvox-agent-shell--presentation-facts
          'agent-prompt-editor 'agent-prompt-submitted nil
          (list :agent-prompt-disposition (or disposition 'sent)))
         'state-change
         (if keep-composing 'task-done 'close-object)
         #'tts-speak
         (emacsvox-agent-shell--viewport-submit-announcement
          disposition keep-composing dismiss))))))

(defun emacsvox-agent-shell--viewport-compose-cancel-around
    (original-function &rest arguments)
  "Announce an accepted prompt composition cancellation."
  (let ((interactive-p
         (ems-interactive-p 'agent-shell-viewport-compose-cancel))
        (viewport-buffer (current-buffer))
        (original-mode major-mode))
    (prog1
        (apply original-function arguments)
      (when (and interactive-p
                 (or (not (buffer-live-p viewport-buffer))
                     (not (eq (current-buffer) viewport-buffer))
                     (not
                      (eq
                       (buffer-local-value 'major-mode viewport-buffer)
                       original-mode))))
        (emacsvox-agent-shell--present-feedback
         (emacsvox-agent-shell--presentation-facts
          'agent-prompt-editor 'agent-prompt-cancelled)
         'state-change 'close-object #'tts-speak
         "Prompt composition cancelled.")))))

;;;  Interactive Commands for Viewport

(defun emacsvox-agent-shell--viewport-view-mode-after (&rest _)
  "Announce a switch to the viewport view mode."
  (when (ems-interactive-p 'agent-shell-viewport-view-mode)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-setting-changed nil
      '(:agent-viewport-mode view))
     'state-change 'select-object #'emacsvox-speak-mode-line)))

(defun emacsvox-agent-shell--viewport-edit-mode-after (&rest _)
  "Announce a switch to the viewport edit mode."
  (when (ems-interactive-p 'agent-shell-viewport-edit-mode)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-setting-changed nil
      '(:agent-viewport-mode edit))
     'state-change 'select-object #'emacsvox-speak-mode-line)))

;;;  Tool Call Feedback

(defun emacsvox-agent-shell--meaningful-tool-text (text)
  "Return a concise speech version of meaningful tool TEXT, or nil."
  (when (and (stringp text) (string-match-p "[[:alnum:]]" text))
    (let ((clean
           (replace-regexp-in-string
            "[[:space:]\n\r]+" " "
            (string-trim (substring-no-properties text)))))
      (if (> (length clean) 120)
          (concat (substring clean 0 117) "...")
        clean))))

(defun emacsvox-agent-shell--tool-call-description (tool-call tool-call-id)
  "Return a concise description of TOOL-CALL identified by TOOL-CALL-ID."
  (or (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :title))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :description))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :command))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :kind))
      (emacsvox-agent-shell--meaningful-tool-text tool-call-id)
      "unknown tool"))

(defun emacsvox-agent-shell--tool-call-announcement (status description)
  "Return a semantic announcement for tool STATUS and DESCRIPTION."
  (let ((verb (pcase status
                ("pending" "pending")
                ("in_progress" "started")
                ("completed" "completed")
                ("failed" "failed"))))
    (concat (format "Tool %s: %s" verb description)
            (unless (string-match-p "[.!?]$" description) "."))))

(defun emacsvox-agent-shell--tool-content-block-text (block)
  "Extract speakable text from ACP tool content BLOCK."
  (cond
   ((stringp block) (substring-no-properties block))
   ((listp block)
    (let ((text (or (map-elt block :text) (map-elt block 'text)))
          (content (or (map-elt block :content) (map-elt block 'content))))
      (cond
       ((stringp text) (substring-no-properties text))
       ((stringp content) (substring-no-properties content))
       ((listp content)
        (emacsvox-agent-shell--tool-content-block-text content)))))
   (t nil)))

(defun emacsvox-agent-shell--tool-output-text (content)
  "Extract speakable terminal output from ACP tool CONTENT."
  (let* ((blocks
          (cond
           ((stringp content) (list content))
           ((vectorp content) (append content nil))
           ((and (listp content)
                 (or (assq 'type content) (assq :type content)
                     (assq 'text content) (assq :text content)))
            (list content))
           ((listp content) content)))
         (texts
          (seq-keep
           (lambda (block)
             (when-let* ((text
                          (emacsvox-agent-shell--tool-content-block-text
                           block))
                         (trimmed (string-trim text))
                         ((not (string-empty-p trimmed))))
               trimmed))
           blocks)))
    (when texts (string-join texts "\n"))))

(defun emacsvox-agent-shell--tool-call-feedback-text
    (status description content)
  "Return one spoken object for tool STATUS, DESCRIPTION, and CONTENT.

Return nil when the configured verbosity requests status cues only."
  (unless (eq emacsvox-agent-shell-tool-output-verbosity 'status)
    (let ((announcement
           (emacsvox-agent-shell--tool-call-announcement
            status description)))
      (if
          (and
           (eq emacsvox-agent-shell-tool-output-verbosity 'full)
           (member status '("completed" "failed")))
          (if-let* ((output
                     (emacsvox-agent-shell--tool-output-text content)))
              (format "%s Output: %s" announcement output)
            announcement)
        announcement))))

(defun emacsvox-agent-shell--handle-tool-call-update (event)
  "Announce a new semantic status from public tool update EVENT."
  (let* ((data (map-elt event :data))
         (tool-call-id (map-elt data :tool-call-id))
         (tool-call (map-elt data :tool-call))
         (status (map-elt tool-call :status)))
    (when (and tool-call-id status)
      (unless (hash-table-p emacsvox-agent-shell--tool-call-status-cache)
        (setq emacsvox-agent-shell--tool-call-status-cache
              (make-hash-table :test #'equal)))
      (let ((previous
             (gethash tool-call-id
                      emacsvox-agent-shell--tool-call-status-cache)))
        (puthash tool-call-id status
                 emacsvox-agent-shell--tool-call-status-cache)
        (when (and emacsvox-agent-shell-speak-tool-calls
                   (emacsvox-agent-shell--speech-level-at-least-p 'full)
                   (member status
                           '("pending" "in_progress" "completed" "failed"))
                   (not (equal status previous)))
          (let* ((facts
                  (emacsvox-agent-shell--presentation-facts
                   'agent-tool 'agent-tool-status-changed nil
                   (list
                    :agent-tool-status
                    (if (equal status "in_progress")
                        'in-progress
                      (intern status)))))
                 (text
                  (emacsvox-agent-shell--tool-call-feedback-text
                   status
                   (emacsvox-agent-shell--tool-call-description
                    tool-call tool-call-id)
                   (map-elt tool-call :content))))
            (if text
                (emacsvox-aural-submit
                 text
                 :facts facts
                 :module 'agent-shell
                 :occasion 'notification)
              (emacsvox-aural-submit-actions
               :facts facts
               :module 'agent-shell
               :occasion 'notification))))))))

(defun emacsvox-agent-shell--tool-call-event-setup ()
  "Subscribe the current agent-shell buffer to tool call updates."
  (unless emacsvox-agent-shell--tool-call-subscription
    (setq emacsvox-agent-shell--tool-call-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'tool-call-update
           :on-event #'emacsvox-agent-shell--handle-tool-call-update))))

(defun emacsvox-agent-shell--tool-call-event-cleanup ()
  "Remove the current buffer's tool subscription and cached state."
  (when emacsvox-agent-shell--tool-call-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--tool-call-subscription)
    (setq emacsvox-agent-shell--tool-call-subscription nil))
  (when (hash-table-p emacsvox-agent-shell--tool-call-status-cache)
    (clrhash emacsvox-agent-shell--tool-call-status-cache))
  (setq emacsvox-agent-shell--tool-call-status-cache nil)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--tool-call-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--tool-call-event-cleanup t))

(defun emacsvox-agent-shell--buffer-setup ()
  "Install event support and centralized cleanup in this shell buffer."
  (setq-local emacsvox-aural-module 'agent-shell)
  (add-hook 'kill-buffer-hook
            #'emacsvox-agent-shell--buffer-cleanup nil t)
  (add-hook 'change-major-mode-hook
            #'emacsvox-agent-shell--buffer-cleanup nil t)
  (emacsvox-agent-shell--response-section-setup)
  (emacsvox-agent-shell--permission-event-setup)
  (emacsvox-agent-shell--lifecycle-event-setup)
  (emacsvox-agent-shell--tool-call-event-setup)
  (emacsvox-agent-shell--table-navigation-setup))

(defun emacsvox-agent-shell--buffer-cleanup ()
  "Cancel speech work and remove all support state from this shell buffer."
  (emacsvox-agent-shell--response-section-cleanup)
  (emacsvox-agent-shell--cancel-pending-speech)
  (setq emacsvox-agent-shell--pending-bodies nil)
  (emacsvox-agent-shell--permission-event-cleanup)
  (emacsvox-agent-shell--lifecycle-event-cleanup)
  (emacsvox-agent-shell--tool-call-event-cleanup)
  (emacsvox-agent-shell--table-navigation-cleanup)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--buffer-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--buffer-cleanup t))

;;;  Enable/Disable support:

(defconst emacsvox-agent-shell--advice-list
  '((emacsvox-speak-visual-line :around
     emacsvox-agent-shell--speak-visual-line-around)
    (emacsvox-speak-line :around
     emacsvox-agent-shell--speak-line-around)
    (tts-speak :around emacsvox-agent-shell--tts-speak-around)
    (emacsvox-speak-mode-line :around
     emacsvox-agent-shell--speak-mode-line-around)
    (emacsvox-speak-header-line :around
     emacsvox-agent-shell--speak-header-line-around)
    (agent-shell :after emacsvox-agent-shell--agent-shell-after)
    (agent-shell-start :after
     emacsvox-agent-shell--agent-shell-start-after)
    (agent-shell-new-shell :after
     emacsvox-agent-shell--agent-shell-new-shell-after)
    (agent-shell-toggle :after
     emacsvox-agent-shell--agent-shell-toggle-after)
    (agent-shell-ui-toggle-fragment :around
     emacsvox-agent-shell--toggle-fragment-around)
    (agent-shell-ui--toggle-fragment-at-point :around
     emacsvox-agent-shell--toggle-fragment-action-around)
    (agent-shell-ui-toggle-all-fragments :around
     emacsvox-agent-shell--toggle-all-fragments-around)
    (agent-shell-other-buffer :after
     emacsvox-agent-shell--agent-shell-other-buffer-after)
    (agent-shell-interrupt :after
     emacsvox-agent-shell--agent-shell-interrupt-after)
    (agent-shell-next-item :around
     emacsvox-agent-shell--next-item-around)
    (agent-shell-previous-item :around
     emacsvox-agent-shell--previous-item-around)
    (agent-shell-jump-to-latest-permission-button-row :filter-return
     emacsvox-agent-shell--jump-to-permission-after)
    (agent-shell-next-permission-button :filter-return
     emacsvox-agent-shell--next-permission-button-after)
    (agent-shell-previous-permission-button :filter-return
     emacsvox-agent-shell--previous-permission-button-after)
    (agent-shell-set-session-model :after
     emacsvox-agent-shell--set-session-model-after)
    (agent-shell-set-session-mode :after
     emacsvox-agent-shell--set-session-mode-after)
    (agent-shell-cycle-session-mode :after
     emacsvox-agent-shell--cycle-session-mode-after)
    (agent-shell-viewport--show-buffer :after
     emacsvox-agent-shell--viewport-show-buffer-after)
    (agent-shell-viewport-next-item :around
     emacsvox-agent-shell--viewport-next-item-around)
    (agent-shell-viewport-previous-item :around
     emacsvox-agent-shell--viewport-previous-item-around)
    (agent-shell-prompt-compose :after
     emacsvox-agent-shell--prompt-compose-after)
    (agent-shell-viewport-refresh :after
     emacsvox-agent-shell--viewport-refresh-after)
    (agent-shell-viewport-compose-send :around
     emacsvox-agent-shell--viewport-compose-send-around)
    (agent-shell-viewport-compose-cancel :around
     emacsvox-agent-shell--viewport-compose-cancel-around)
    (agent-shell-viewport-view-mode :after
     emacsvox-agent-shell--viewport-view-mode-after)
    (agent-shell-viewport-edit-mode :after
     emacsvox-agent-shell--viewport-edit-mode-after))
  "Agent Shell targets and their native advice functions.")

(defun emacsvox-agent-shell--install-advice ()
  "Install native advice for the current Agent Shell API."
  (dolist (entry emacsvox-agent-shell--advice-list)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and
             (fboundp target)
             (not (advice-member-p function target)))
        (advice-add target where function
                    '((name . emacsvox-agent-shell)))))))

(defun emacsvox-agent-shell--remove-advice ()
  "Remove native Agent Shell advice."
  (dolist (entry emacsvox-agent-shell--advice-list)
    (pcase-let ((`(,target ,_where ,function) entry))
      (when (advice-member-p function target)
        (advice-remove target function)))))

(defun emacsvox-agent-shell-enable ()
  "Enable Emacsvox support for agent-shell."
  (interactive)
  (emacsvox-agent-shell--upgrade-response-monitoring)
  (emacsvox-agent-shell--install-advice)
  (add-hook 'agent-shell-mode-hook #'emacsvox-agent-shell-speech-setup)
  ;; Remove hooks installed by earlier versions before installing the
  ;; centralized setup path.
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--permission-event-setup)
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--lifecycle-event-setup)
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--tool-call-event-setup)
  (add-hook 'agent-shell-mode-hook #'emacsvox-agent-shell--buffer-setup)
  (add-hook 'agent-shell-viewport-view-mode-hook
            #'emacsvox-agent-shell--table-navigation-setup)
  (add-hook 'agent-shell-viewport-edit-mode-hook
            #'emacsvox-agent-shell--table-navigation-setup)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (cond
       ((derived-mode-p 'agent-shell-mode)
        (emacsvox-agent-shell--buffer-setup))
       ((derived-mode-p 'agent-shell-viewport-view-mode
                        'agent-shell-viewport-edit-mode)
        (emacsvox-agent-shell--table-navigation-setup)))))
  (when (called-interactively-p 'interactive)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change nil #'message
     "Enabled Emacsvox agent-shell support")))

(defun emacsvox-agent-shell-disable ()
  "Disable Emacsvox support for agent-shell."
  (interactive)
  (emacsvox-agent-shell--remove-advice)
  (remove-hook 'agent-shell-mode-hook #'emacsvox-agent-shell-speech-setup)
  (remove-hook 'agent-shell-mode-hook #'emacsvox-agent-shell--buffer-setup)
  (remove-hook 'agent-shell-viewport-view-mode-hook
               #'emacsvox-agent-shell--table-navigation-setup)
  (remove-hook 'agent-shell-viewport-edit-mode-hook
               #'emacsvox-agent-shell--table-navigation-setup)
  ;; Also remove setup hooks left by earlier versions.
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--permission-event-setup)
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--lifecycle-event-setup)
  (remove-hook 'agent-shell-mode-hook
               #'emacsvox-agent-shell--tool-call-event-setup)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (cond
       ((derived-mode-p 'agent-shell-mode)
        (emacsvox-agent-shell--buffer-cleanup))
       ((derived-mode-p 'agent-shell-viewport-view-mode
                        'agent-shell-viewport-edit-mode)
        (emacsvox-agent-shell--table-navigation-cleanup)))))
  (when (called-interactively-p 'interactive)
    (emacsvox-agent-shell--present-feedback
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change nil #'message
     "Disabled Emacsvox agent-shell support")))

(with-eval-after-load 'agent-shell
  (emacsvox-agent-shell-enable))

(provide 'emacsvox-agent-shell)
;;;  end of file
