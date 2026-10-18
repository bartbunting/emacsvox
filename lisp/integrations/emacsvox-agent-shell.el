;;; emacsvox-agent-shell.el --- Speech-enable AGENT-SHELL  -*- lexical-binding: t; -*-

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
;; lifecycle announcements.  See the Agent Shell chapter in the Emacsvox
;; manual for setup, keys, privacy boundaries, inspection, and recovery; the
;; generated command reference lists the commands and options across these
;; modules.
;; See https://github.com/xenodium/agent-shell for agent-shell itself.

;;; Code:

;;   Required modules:

(require 'cl-lib)
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-render)
(require 'emacsvox-agent-shell-events)
(require 'emacsvox-agent-shell-presentation)
(require 'emacsvox-agent-shell-interaction)
(require 'emacsvox-table-reader)
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
;; These public entry points are `cl-defun' keyword APIs.  A value of t keeps
;; `check-declare' checking their source without presenting `&key' as positional
;; to the native byte compiler, whose declaration arglists follow `defun'.
(declare-function agent-shell-shell-buffer "agent-shell" t)
(declare-function agent-shell-session-id "agent-shell" t)
(declare-function agent-shell-status "agent-shell" t)
(declare-function agent-shell-initialized-p "agent-shell" t)
(declare-function agent-shell-config-options "agent-shell" t)
(declare-function agent-shell-elicitation--pending-p "agent-shell-elicitation" t)
(declare-function agent-shell-elicitation--preview-open-p "agent-shell-elicitation" (elicitation key value))
(declare-function agent-shell-elicitation--option-preview-at "agent-shell-elicitation" (elicitation key value))
(declare-function agent-shell-steering-supported-p "agent-shell" t)
(declare-function agent-shell-subscribe-to "agent-shell" t)
(declare-function agent-shell-unsubscribe "agent-shell" t)
(declare-function agent-shell-viewport--shell-buffer
                  "agent-shell-viewport" (&optional viewport-buffer))
(declare-function agent-shell-ui-toggle-fragment "agent-shell-ui" ())
(declare-function agent-shell-ui-toggle-all-fragments "agent-shell-ui" ())
(declare-function agent-shell-ui--toggle-fragment-at-point
                  "agent-shell-ui" ())
(declare-function shell-maker-busy "shell-maker" ())
(declare-function shell-maker-point-at-last-prompt-p "shell-maker" ())
(declare-function agent-shell--point-in-live-input-p "agent-shell-prompt" ())
(declare-function agent-shell--cost-indicator "agent-shell-usage" ())
(declare-function emacsvox-speak--present-physical-line
                  "emacsvox-speak" (&optional arg compatibility-actions))
(declare-function emacsvox-speak-region
                  "emacsvox-speak" (start end))

(defvar emacsvox-comint-autospeak)
(defvar comint-last-prompt)
(defvar emacsvox-show-point)
(defvar emacsvox-pronounce-date-mm-dd-yyyy-pattern)
(defvar emacsvox-pronounce-date-yyyy-mm-dd-pattern)
(defvar emacsvox-pronounce-rfc-3339-datetime-pattern)
(defvar emacsvox-pronounce-sha-checksum-pattern)
(defvar ems--speak-max-length)
(defvar tts-speaker-process)
(defvar agent-shell-ui--fold-toggle-state)
(defvar agent-shell-busy-submit-default-function)

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
- \\='status: Play status cues as the tool starts and finishes"
  :type '(choice (const :tag "Full output" full)
                 (const :tag "Summary" summary)
                 (const :tag "Status cues only" status))
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

(defcustom emacsvox-agent-shell-automatic-content-max-characters 2000
  "Maximum characters submitted for automatic Agent Shell speech.

Long responses, tool output, errors, permissions, and other unsolicited
content are shortened before Aural compiles them.  The spoken preview includes
exact omitted character and line counts plus an appropriate inspection hint.
This limit does not apply to explicit inspection commands such as
`emacsvox-agent-shell-speak-last-response'.  Set this to nil, or to a
non-positive value, to allow complete automatic response and output bodies;
provider-controlled permission fields and tool labels remain concise."
  :type '(choice (const :tag "Speak complete automatic content" nil)
                 (integer :tag "Characters"))
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

(unless emacsvox-table-reader--legacy-watching
  (dolist (option '(emacsvox-agent-shell-table-titles
                    emacsvox-agent-shell-table-data-position))
    (when (boundp option)
      (cl-pushnew option emacsvox-table-reader--legacy-preexisting))))

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

(emacsvox-table-reader--watch-legacy)

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

(defcustom emacsvox-agent-shell-line-speech-max-characters 512
  "Maximum Agent Shell characters compiled for line-navigation speech.

When a physical or visual line is longer, navigation speaks its first
characters and a count of the omitted remainder.  This prevents rendered tool
and search output from opening the core long-line prompt or building an
unnecessarily large presentation.  Set this to nil to restore the core
long-line policy.  Explicit Agent Shell response and block-reading commands are
not truncated."
  :type '(choice (const :tag "Use core long-line policy" nil)
                 (integer :tag "Characters"))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-block-navigation-max-characters 4096
  "Maximum body characters spoken after Agent Shell block navigation.

When a normalized block body is longer, navigation stops at a word boundary
where possible and announces the number of omitted characters.  Set this to
nil, or to a non-positive value, to speak the complete body.  This option does
not change concise block labels or the specialized table and source-block
navigation presentations."
  :type '(choice (const :tag "Speak complete block body" nil)
                 (integer :tag "Body characters"))
  :group 'emacsvox-agent-shell)

;;;  Speech Setup

(defconst emacsvox-agent-shell--unbound-local-value
  'emacsvox-agent-shell--unbound
  "Sentinel recording that an activation variable was unbound.")

(defconst emacsvox-agent-shell--buffer-activation-variables
  '(emacsvox-aural-module
    tts-punctuation-mode
    emacsvox-pronounce-table
    emacsvox-aural-source-transform-function)
  "Buffer-local values assigned while Agent Shell support is active.")

(defvar-local emacsvox-agent-shell--buffer-activation-active-p nil
  "Non-nil when Emacsvox has activated the current Agent Shell buffer.")

(defvar-local emacsvox-agent-shell--buffer-activation-values nil
  "Local values owned by the current Agent Shell activation.
Each entry records the variable, its prior locality and value, and the value
assigned by Emacsvox.  Cleanup restores only assignments that remain intact.")

(defun emacsvox-agent-shell--copy-owned-local-value (value)
  "Return a comparison snapshot of owned local VALUE."
  (cond
   ((hash-table-p value) (copy-hash-table value))
   ((consp value) (copy-tree value))
   ((stringp value) (copy-sequence value))
   (t value)))

(defun emacsvox-agent-shell--owned-local-value-unchanged-p
    (current assigned snapshot)
  "Return non-nil when CURRENT still matches owned ASSIGNED and SNAPSHOT."
  (and
   (eq current assigned)
   (if (hash-table-p current)
       (and
        (hash-table-p snapshot)
        (eq (hash-table-test current) (hash-table-test snapshot))
        (= (hash-table-count current) (hash-table-count snapshot))
        (let ((missing (make-symbol "missing"))
              (unchanged t))
          (maphash
           (lambda (key value)
             (unless (equal value (gethash key snapshot missing))
               (setq unchanged nil)))
           current)
          unchanged))
     (equal current snapshot))))

(defun emacsvox-agent-shell--local-value-state (variable)
  "Return VARIABLE with its current locality and value."
  (list variable
        (local-variable-p variable)
        (if (boundp variable)
            (symbol-value variable)
          emacsvox-agent-shell--unbound-local-value)))

(defun emacsvox-agent-shell--activate-buffer-values ()
  "Apply and record speech values owned by this Agent Shell activation."
  (unless emacsvox-agent-shell--buffer-activation-active-p
    (let* ((variables
            (if (local-variable-p 'emacsvox-comint-autospeak)
                emacsvox-agent-shell--buffer-activation-variables
              (cons 'emacsvox-comint-autospeak
                    emacsvox-agent-shell--buffer-activation-variables)))
           (previous
            (mapcar #'emacsvox-agent-shell--local-value-state variables)))
      (emacsvox-agent-shell-speech-setup)
      (setq-local
       emacsvox-aural-source-transform-function
       #'emacsvox-agent-shell--prepare-speech-text)
      (setq-local
       emacsvox-agent-shell--buffer-activation-values
       (mapcar
        (lambda (state)
          (let ((assigned (symbol-value (car state))))
            (append
             state
             (list assigned
                   (emacsvox-agent-shell--copy-owned-local-value assigned)))))
        previous))
      (setq-local emacsvox-agent-shell--buffer-activation-active-p t))))

(defun emacsvox-agent-shell--restore-buffer-values ()
  "Restore unchanged local values owned by this Agent Shell activation."
  (when emacsvox-agent-shell--buffer-activation-active-p
    (dolist (state emacsvox-agent-shell--buffer-activation-values)
      (pcase-let ((`(,variable ,previously-local-p ,previous
                      ,assigned ,assigned-snapshot)
                   state))
        (when (and (local-variable-p variable)
                   (emacsvox-agent-shell--owned-local-value-unchanged-p
                    (symbol-value variable) assigned assigned-snapshot))
          (if previously-local-p
              (if (eq previous emacsvox-agent-shell--unbound-local-value)
                  (progn
                    (make-local-variable variable)
                    (makunbound variable))
                (set (make-local-variable variable) previous))
            (kill-local-variable variable)))))
    (setq emacsvox-agent-shell--buffer-activation-values nil
          emacsvox-agent-shell--buffer-activation-active-p nil)))

;;;###autoload
(defun emacsvox-agent-shell-speech-setup ()
  "Speech setup for agent-shell."
  (setq-local emacsvox-aural-module 'agent-shell)
  ;; Enable autospeak by default for agent-shell buffers
  (unless (local-variable-p 'emacsvox-comint-autospeak)
    (setq-local emacsvox-comint-autospeak t))
  (tts-apply-punctuation-mode-policy)
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
    (agent-shell-thought-body voice-animate)
    (agent-shell-container-indicator voice-lighten)
    (agent-shell-diff-changes-label voice-bolden-medium)
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
    (agent-shell-markdown-list-marker voice-annotate)
    (agent-shell-markdown-list-done voice-monotone-extra)
    (agent-shell-markdown-table-header voice-bolden)
    (agent-shell-markdown-table-border inaudible)
    (agent-shell-markdown-source-block voice-monotone-extra)
    (agent-shell-markdown-source-block-language voice-smoothen))
  "Voice personalities for current agent-shell Markdown faces.")

(defconst emacsvox-agent-shell--markdown-unvoiced-faces
  (append '(agent-shell-markdown-table-zebra)
          (when (facep 'agent-shell-markdown-table)
            '(agent-shell-markdown-table)))
  "Agent-shell Markdown faces intentionally left without a voice.
Zebra striping and the optional base table face are purely visual.")

(defconst emacsvox-agent-shell--chat-face-voice-map
  '((agent-shell-chat-me-label voice-bolden)
    (agent-shell-chat-agent-label voice-brighten))
  "Voice personalities for optional agent-shell chat labels.")

(voice-setup-add-map emacsvox-agent-shell--ui-face-voice-map)
(voice-setup-add-map emacsvox-agent-shell--markdown-face-voice-map)
(with-eval-after-load 'agent-shell-chat-mode
  (voice-setup-add-map emacsvox-agent-shell--chat-face-voice-map))

;;;  Helper Functions

(defvar emacsvox-agent-shell--chat-label-context nil
  "Dynamically bound visible chat label for the current line speech.")

(defconst emacsvox-agent-shell--end-of-prompt-marker
  "<shell-maker-end-of-prompt>"
  "Text of Shell Maker's property-authenticated prompt delimiter.")

(defun emacsvox-agent-shell--prompt-face-between-p (start end)
  "Return non-nil when prompt face text occurs between START and END."
  (let ((position start)
        found)
    (while (and (< position end) (not found))
      (setq
       found
       (or
        (emacsvox-agent-shell--prompt-face-spec-p
         (get-text-property position 'face))
        (emacsvox-agent-shell--prompt-face-spec-p
         (get-text-property position 'font-lock-face))))
      (unless found
        (setq
         position
         (min
          (or (next-single-property-change position 'face nil end) end)
          (or
           (next-single-property-change position 'font-lock-face nil end)
           end)))))
    found))

(defun emacsvox-agent-shell--chat-overlay-tag (overlay)
  "Return the normalized structural chat tag represented by OVERLAY.
Current Agent Shell uses `agent-shell-chat--tag'.  Releases before
2026-08-29 used overlay `category' values instead."
  (or
   (overlay-get overlay 'agent-shell-chat--tag)
   (pcase (overlay-get overlay 'category)
     ('agent-shell-chat-me 'me)
     ('agent-shell-chat-me-label 'me-label)
     ('agent-shell-chat-me-surplus 'me-surplus)
     ('agent-shell-chat-me-input 'me-input)
     ('agent-shell-chat-agent 'agent))))

(defun emacsvox-agent-shell--chat-overlay-category (overlay)
  "Return the semantic chat category represented by OVERLAY."
  (pcase (emacsvox-agent-shell--chat-overlay-tag overlay)
    ((or 'me 'me-label) 'agent-shell-chat-me)
    ('agent 'agent-shell-chat-agent)))

(defun emacsvox-agent-shell--chat-overlay-rendering (overlay)
  "Return the visible label rendering supplied by chat OVERLAY."
  (seq-find
   (lambda (candidate)
     (and (stringp candidate)
          (not (string-empty-p (string-trim candidate)))))
   (list (overlay-get overlay 'before-string)
         ;; The live `me' overlay displays the input marker, not the name.
         ;; Its name is either in its before-string or a separate label row.
         (unless (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'me)
           (overlay-get overlay 'display)))))

(defun emacsvox-agent-shell--chat-label-predecessors (overlays)
  "Include adjacent label rows preceding chat OVERLAYS.
Recent Agent Shell draws each label row on a separate source character.
The overlay ending at the response can therefore hide only padding; follow
contiguous overlays of the same role back to the row carrying its name.
Never cross intervening content or inspect unrelated transcript overlays."
  (let ((result (copy-sequence overlays))
        (pending (copy-sequence overlays)))
    (while pending
      (let* ((overlay (pop pending))
             (category (emacsvox-agent-shell--chat-overlay-category overlay))
             (start (overlay-start overlay)))
        (when (and category (> start (point-min)))
          (dolist (previous (overlays-in (1- start) start))
            (when (and (= (overlay-end previous) start)
                       (< (overlay-start previous) start)
                       (eq category
                           (emacsvox-agent-shell--chat-overlay-category previous))
                       (not (memq previous result)))
              (push previous result)
              (push previous pending))))))
    result))

(defun emacsvox-agent-shell--live-chat-prompt-overlay-p (overlay)
  "Return non-nil when OVERLAY carries Agent Shell's live prompt marker."
  (and
   (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'me)
   (seq-some
    (lambda (candidate)
      (and (stringp candidate)
           (not (string-empty-p (string-trim candidate)))))
    (list (overlay-get overlay 'display)
          (overlay-get overlay 'line-prefix)
          (overlay-get overlay 'wrap-prefix)))))

(defun emacsvox-agent-shell--chat-label-context-between
    (source-start source-end)
  "Return the visible chat label context between SOURCE-START and SOURCE-END.
The optional chat mode renders labels as overlays, so this adapter captures
their semantic text without changing the underlying shell buffer.  An overlay
ending at SOURCE-START labels the content that follows it."
  (let* ((source-start
          (min (point-max) (max (point-min) source-start)))
         (source-end (min (point-max) (max source-start source-end)))
         (overlays
          (delete-dups
           (append
            ;; Chat labels often consume the whitespace before their content,
            ;; so the matching overlay ends exactly where the spoken line
            ;; begins.  Do not include overlays that merely begin at the line
            ;; end: those label the following turn.
            (and (> source-start (point-min))
                 (seq-filter
                  (lambda (candidate)
                    (= (overlay-end candidate) source-start))
                  (overlays-in (1- source-start) source-start)))
            (and (< source-start source-end)
                 (overlays-in source-start source-end)))))
         (chat-overlays
          (emacsvox-agent-shell--chat-label-predecessors
           (seq-filter
            (lambda (candidate)
              (emacsvox-agent-shell--chat-overlay-category candidate))
            overlays)))
         (preferred-category
          (and
           (cdr chat-overlays)
           (cond
            ((emacsvox-agent-shell--prompt-face-between-p
              source-start source-end)
             'agent-shell-chat-me)
            ((save-excursion
               (goto-char source-start)
               (text-property-any
                source-start source-end 'shell-maker--marker t))
             'agent-shell-chat-agent))))
         (overlay
          (or
           (and preferred-category
                (seq-find
                 (lambda (candidate)
                   (eq (emacsvox-agent-shell--chat-overlay-category candidate)
                       preferred-category))
                 (seq-filter
                  #'emacsvox-agent-shell--chat-overlay-rendering
                  chat-overlays)))
           (seq-find
            #'emacsvox-agent-shell--chat-overlay-rendering
            chat-overlays))))
    (when overlay
      (let* ((category
              (emacsvox-agent-shell--chat-overlay-category overlay))
             (rendered
              (emacsvox-agent-shell--chat-overlay-rendering overlay))
             (label-rendering
              (emacsvox-agent-shell--chat-label-rendering rendered))
             (label (car label-rendering)))
        (when label
          (append
           (list :category category :text label)
           (when (and
                  (eq category 'agent-shell-chat-me)
                  (or (cdr label-rendering)
                      (seq-some
                       #'emacsvox-agent-shell--live-chat-prompt-overlay-p
                       chat-overlays)))
             '(:editable t))))))))

(defun emacsvox-agent-shell--chat-label-context-at-point ()
  "Return the visible agent-shell chat label context on the current line."
  ;; Comint's input field starts after the prompt.  Include the whole physical
  ;; line so its preceding Me label wins over the decorative prompt marker.
  (let ((inhibit-field-text-motion t))
    (emacsvox-agent-shell--chat-label-context-between
     (line-beginning-position) (line-end-position))))

(defun emacsvox-agent-shell--visual-line-source-bounds ()
  "Return the current visual line's underlying source bounds."
  (save-excursion
    (let ((inhibit-field-text-motion t))
      (beginning-of-visual-line)
      (let ((start (point)))
        (end-of-visual-line)
        (cons start (point))))))

(defun emacsvox-agent-shell--response-row-source-bounds (bounds)
  "Return visible response bounds when BOUNDS starts in its hidden marker.
The chat indent can make visual motion land in the empty display overlay
before the first response character, including when approaching from below."
  (let ((start (car bounds)) (end (cdr bounds)))
    (when (get-text-property start 'shell-maker--marker)
      (cl-loop for overlay in (overlays-at start)
               when (and (eq (emacsvox-agent-shell--chat-overlay-tag overlay)
                             'agent)
                         (equal (overlay-get overlay 'display) "")
                         (< start (overlay-end overlay))
                         (< (overlay-end overlay) end))
               return (cons (overlay-end overlay) end)))))

(defun emacsvox-agent-shell--live-prompt-state-speech ()
  "Briefly describe a non-idle prompt's state, or return nil."
  (let ((status (condition-case nil
                    (agent-shell-status :shell-buffer (current-buffer))
                  (error 'unknown))))
    (pcase status
      ('ready nil)
      ('busy "Agent busy.")
      ('blocked (if (agent-shell-elicitation--pending-p)
                    "Waiting for an answer."
                  "Waiting for permission."))
      (_ "Input state unavailable."))))

(defun emacsvox-agent-shell--add-chat-label-for-speech (text)
  "Return TEXT prefixed by the visible chat label captured for speech."
  (if-let* ((context emacsvox-agent-shell--chat-label-context)
            (label (plist-get context :text)))
      (let* ((category (plist-get context :category))
             (prompt-state
              (when (plist-get context :editable)
                (emacsvox-agent-shell--live-prompt-state-speech)))
             (content
              (if (eq category 'agent-shell-chat-me)
                  (emacsvox-agent-shell--without-leading-chat-prompt text)
                text))
             (plain (substring-no-properties content))
             (marker-start
              (and
               (eq category 'agent-shell-chat-agent)
               (string-match "\\`[ \t\n\r]*" plain)
               (match-end 0)))
             (marker-end
              (and
               marker-start
               (< marker-start (length content))
               (get-text-property
                marker-start 'shell-maker--marker content)
               (string-prefix-p
                emacsvox-agent-shell--end-of-prompt-marker
                plain marker-start)
               (+ marker-start
                  (length emacsvox-agent-shell--end-of-prompt-marker)))))
        (when marker-end
          (setq content (substring content marker-end)))
        (setq content (string-trim-left content))
        (if (string-empty-p (string-trim (substring-no-properties content)))
            (if (plist-get context :editable)
                (concat label ". " (or prompt-state "Ready for input."))
              label)
          (concat label ". "
                  (when prompt-state (concat prompt-state " ")) content)))
    text))

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

(defvar emacsvox-agent-shell--line-navigation-speech-p nil
  "Non-nil while Agent Shell is preparing line-navigation speech.")

(defvar emacsvox-agent-shell--visual-line-kill-p nil
  "Non-nil while an interactive Agent Shell visual-line kill is running.")

(defun emacsvox-agent-shell--limit-line-navigation-speech (text)
  "Return bounded line-navigation speech TEXT for Agent Shell."
  (let ((limit emacsvox-agent-shell-line-speech-max-characters))
    (if (and emacsvox-agent-shell--line-navigation-speech-p
             (integerp limit)
             (> limit 0)
             (> (length text) limit))
        (concat
         (substring text 0 limit)
         (format " [line truncated; %d characters omitted]"
                 (- (length text) limit)))
      text)))

(defun emacsvox-agent-shell--prepare-speech-text (text)
  "Prepare TEXT for speech in agent-shell, leaving other modes unchanged."
  (if (and (stringp text)
           (derived-mode-p 'agent-shell-mode
                           'agent-shell-viewport-view-mode
                           'agent-shell-viewport-edit-mode))
      (let ((text
             (emacsvox-agent-shell--limit-line-navigation-speech text)))
        (emacsvox-agent-shell--add-chat-label-for-speech
         (emacsvox-agent-shell--replace-status-icons-for-speech
          (emacsvox-agent-shell--remove-visual-chrome-for-speech
           (emacsvox-agent-shell--speech-copy-without-yank-handler text)))))
    text))

(defconst emacsvox-agent-shell--vertical-toggle-hint-regexp
  "\\`Press RET to toggle\\'"
  "Exact message pattern for agent-shell's collapsible-label cursor sensor.")

(defconst emacsvox-agent-shell--item-action-hint-regexp
  "\\`Press RET to \\(?:copy\\|open\\)"
  "Message pattern for Agent Shell item actions spoken semantically.")

(defvar-local emacsvox-agent-shell--saved-message-filter nil
  "Saved local-state flag and value for `ems--message-filter'.")

(defvar-local emacsvox-agent-shell--vertical-navigation-active-p nil
  "Non-nil while an interactive vertical movement command is running.")

(defvar-local emacsvox-agent-shell--vertical-navigation-origin nil
  "Semantic block identity captured before vertical movement.")

(defun emacsvox-agent-shell--synthetic-agent-row-p (start end)
  "Return non-nil when START through END repeats an agent chat display row.

Agent Shell's multiline `before-string' can make upward visual motion visit
the hidden response marker and the first response row as one source interval
after that response row was already visited directly."
  (and
   emacsvox-agent-shell--vertical-navigation-active-p
   (< start end)
   (save-excursion
     (goto-char start)
     (search-forward "<shell-maker-end-of-prompt>" end t))
   (seq-some
    (lambda (overlay)
      (and
       (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'agent)
       (< (overlay-end overlay) end)))
    (overlays-in start end))))

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
  (setq emacsvox-aural-command-start-time
        (and emacsvox-agent-shell--vertical-navigation-active-p
             (float-time)))
  (when emacsvox-agent-shell--vertical-navigation-active-p
    (setq emacsvox-agent-shell--vertical-navigation-origin
          (emacsvox-agent-shell--block-location-identity
           (emacsvox-agent-shell--block-location-at-point)))))

(defun emacsvox-agent-shell--vertical-navigation-post-command ()
  "Clear transient vertical block-entry state."
  (setq emacsvox-agent-shell--vertical-navigation-active-p nil
        emacsvox-agent-shell--vertical-navigation-origin nil
        emacsvox-aural-command-start-time nil))

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

(defun emacsvox-agent-shell--end-of-prompt-marker-line-p ()
  "Return non-nil when the current line is only a hidden prompt marker."
  (let ((inhibit-field-text-motion t))
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (and
       (< start end)
       (text-property-any start end 'shell-maker--marker t)
       (string-match-p
        "\\`[ \t]*<shell-maker-end-of-prompt>[ \t]*\\'"
        (buffer-substring-no-properties start end))))))

(defun emacsvox-agent-shell--chat-navigation-source-bounds ()
  "Return the current visual source bounds when they carry a chat label."
  (when (or line-move-visual visual-line-mode)
    (let ((bounds (emacsvox-agent-shell--visual-line-source-bounds)))
      (when (emacsvox-agent-shell--chat-label-context-between
             (car bounds) (cdr bounds))
        bounds))))

(defun emacsvox-agent-shell--chat-padding-source-bounds ()
  "Return inclusive source bounds of chat label padding at point."
  (when-let* ((overlay
               (seq-find
                (lambda (candidate)
                  (memq (emacsvox-agent-shell--chat-overlay-tag candidate)
                        '(me-label me-surplus)))
                (overlays-at (point)))))
    (cons (max (point-min) (overlay-start overlay))
          (min (1- (point-max)) (1- (overlay-end overlay))))))

(defun emacsvox-agent-shell--adjacent-chat-padding-source-bounds (direction)
  "Return chat padding immediately beyond this visual row in DIRECTION."
  (when (or line-move-visual visual-line-mode)
    (save-excursion
      (let* ((bounds (emacsvox-agent-shell--visual-line-source-bounds))
             (position (pcase direction
                         ('forward (1+ (cdr bounds)))
                         ('backward (1- (car bounds))))))
        (when (<= (point-min) position (1- (point-max)))
          (goto-char position)
          (emacsvox-agent-shell--chat-padding-source-bounds))))))

(defun emacsvox-agent-shell--move-beyond-visual-source-row
    (direction bounds)
  "Move in DIRECTION beyond visual source BOUNDS.
Use source positions rather than `line-move', whose retained goal column can
skip a short wrapped continuation after Agent Shell's displayed Me label."
  (goto-char
   (pcase direction
     ('forward
      (min (point-max) (1+ (cdr bounds))))
     ('backward
      (max (point-min) (1- (car bounds)))))))

(defun emacsvox-agent-shell--move-through-prompt-marker (direction)
  "Move in DIRECTION through the current hidden prompt-marker line.
Forward movement uses the next logical line.  Backward movement lands on the
last source position of the preceding line, which preserves its final wrapped
visual row instead of inheriting a goal column that can skip it."
  (pcase direction
    ('forward
     (forward-line 1))
    ('backward
     (goto-char (max (point-min) (1- (line-beginning-position)))))))

(defun emacsvox-agent-shell--present-current-navigation-line ()
  "Present the current line after Agent Shell normalizes vertical motion."
  (let* ((facts (copy-tree emacsvox-aural-submission-facts))
         (events
          (append
           (copy-sequence (plist-get facts :events))
           '(focus-entered)))
         (emacsvox-aural-submission-facts
          (plist-put facts :events (delete-dups events)))
         (emacsvox-aural-submission-occasion 'navigation))
    (if (or line-move-visual visual-line-mode)
        (emacsvox-speak-visual-line)
      (emacsvox-speak-line))))

(defun emacsvox-agent-shell--normalize-folded-heading-position ()
  "Keep a collapsed heading's visual end inside its actionable text.

Visual motion can retain a goal column past the heading and land after its
invisible body.  That padding newline shares the heading's display row but
has neither its fragment state nor its RET binding."
  (when (and (or line-move-visual visual-line-mode)
             (> (point) (point-min))
             (or (eobp) (eq (char-after) ?\n))
             (not (get-text-property (point) 'agent-shell-ui-state))
             (not (invisible-p (point)))
             (get-text-property (1- (point)) 'invisible)
             (invisible-p (1- (point))))
    (let* ((hidden-start
            (previous-single-property-change
             (point) 'invisible nil (point-min)))
           (heading-position (1- hidden-start)))
      (when (and (>= heading-position (point-min))
                 (not (invisible-p heading-position))
                 (map-elt (get-text-property
                           heading-position 'agent-shell-ui-state)
                          :collapsed)
                 (memq (get-text-property
                        heading-position 'agent-shell-ui-section)
                       '(indicator label-left label-right)))
        ;; Retain the last display row when the heading itself wraps.
        (goto-char heading-position)))))

(defun emacsvox-agent-shell--vertical-motion-around
    (original-function nominal-direction arguments)
  "Normalize presentational chat rows during interactive vertical motion.

ORIGINAL-FUNCTION receives ARGUMENTS.  NOMINAL-DIRECTION is the direction of
a positive argument to the advised command."
  (let* ((target ems--interactive-fn-name)
         (interactive-p (memq target '(next-line previous-line)))
         (count (prefix-numeric-value (car arguments)))
         (normalize-p
          (and interactive-p
               (/= count 0)
               (derived-mode-p 'agent-shell-mode)))
         (direction
          (if (< count 0)
              (if (eq nominal-direction 'forward) 'backward 'forward)
            nominal-direction))
         (origin-point (point))
         (origin-source-bounds
          (and normalize-p
               (emacsvox-agent-shell--chat-navigation-source-bounds)))
         result)
    ;; Agent Shell may need to move again after the command reaches a display
    ;; alias.  Defer core line speech until that final destination is known.
    (setq result
          (if normalize-p
              (let ((ems--interactive-fn-name nil))
                (condition-case error-data
                    (apply original-function arguments)
                  ((beginning-of-buffer end-of-buffer)
                   ;; A multiline Me label can trap core visual motion at
                   ;; its newline anchor, far from either buffer boundary.
                   (let ((padding
                          (emacsvox-agent-shell--chat-padding-source-bounds)))
                     (unless
                         (and padding
                              (pcase direction
                                ('backward
                                 (and (eq (car error-data) 'beginning-of-buffer)
                                      (> (car padding) (point-min))))
                                ('forward
                                 (and (eq (car error-data) 'end-of-buffer)
                                      (< (cdr padding) (1- (point-max)))))))
                       (signal (car error-data) (cdr error-data)))))))
            (apply original-function arguments)))
    (when normalize-p
      ;; A multiline chat label can also stall motion on the preceding
      ;; ordinary row (for example, Cancelled), outside the label overlay.
      ;; Cross only the adjacent chat padding, and only if motion stalled.
      (when-let* (((= origin-point (point)))
                  (adjacent-padding
                   (emacsvox-agent-shell--adjacent-chat-padding-source-bounds
                    direction)))
        (emacsvox-agent-shell--move-beyond-visual-source-row
         direction adjacent-padding))
      ;; A retained goal column can land in the first response row's hidden
      ;; marker.  Recover its content before skipping marker-only rows.  Do
      ;; not repeat this row when motion started within it.
      (when-let* (((eq direction 'backward))
                  (response-bounds
                   (emacsvox-agent-shell--response-row-source-bounds
                    (emacsvox-agent-shell--visual-line-source-bounds)))
                  ((> origin-point (cdr response-bounds)))
                  ((< (point) (car response-bounds))))
        (goto-char (car response-bounds)))
      (let (previous padding)
        ;; A folded or transient row can make core visual motion return while
        ;; point remains at the row anchor.  Escape when source remains in the
        ;; requested direction instead of presenting that anchor indefinitely.
        (while (and (or
                     (setq padding
                           (emacsvox-agent-shell--chat-padding-source-bounds))
                     (emacsvox-agent-shell--end-of-prompt-marker-line-p)
                     (and
                      origin-source-bounds
                      (or
                       (/= origin-point (point))
                       (pcase direction
                         ('forward
                          (< (cdr origin-source-bounds) (point-max)))
                         ('backward
                          (> (car origin-source-bounds) (point-min)))))
                      (equal
                       origin-source-bounds
                       (emacsvox-agent-shell--chat-navigation-source-bounds))))
                    (not (eq previous (point))))
          (setq previous (point))
          (cond
           (padding
            (emacsvox-agent-shell--move-beyond-visual-source-row
             direction padding))
           ((emacsvox-agent-shell--end-of-prompt-marker-line-p)
            (emacsvox-agent-shell--move-through-prompt-marker direction))
           (t
            (emacsvox-agent-shell--move-beyond-visual-source-row
             direction origin-source-bounds)))))
      (emacsvox-agent-shell--normalize-folded-heading-position)
      ;; Core advice may wrap this adapter when loaded later.  We own the
      ;; final presentation, so do not let that outer advice repeat it.
      (ems-interactive-p target)
      (emacsvox-agent-shell--present-current-navigation-line))
    result))

(defun emacsvox-agent-shell--next-line-around
    (original-function &rest arguments)
  "Normalize Agent Shell presentational rows during downward motion."
  (emacsvox-agent-shell--vertical-motion-around
   original-function 'forward arguments))

(defun emacsvox-agent-shell--previous-line-around
    (original-function &rest arguments)
  "Normalize Agent Shell presentational rows during upward motion."
  (emacsvox-agent-shell--vertical-motion-around
   original-function 'backward arguments))

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
  "Restore the message filter saved before navigation feedback."
  (when emacsvox-agent-shell--saved-message-filter
    (let ((was-local
           (car emacsvox-agent-shell--saved-message-filter))
          (value
           (cdr emacsvox-agent-shell--saved-message-filter)))
      (setq emacsvox-agent-shell--saved-message-filter nil)
      (if was-local
          (setq-local ems--message-filter value)
        (kill-local-variable 'ems--message-filter)))))

(defun emacsvox-agent-shell--filter-message-through-post-command (regexp)
  "Filter messages matching REGEXP until navigation sensors have run."
  (emacsvox-agent-shell--restore-message-filter)
  (setq emacsvox-agent-shell--saved-message-filter
        (cons (local-variable-p 'ems--message-filter)
              ems--message-filter))
  (setq-local
   ems--message-filter
   (if (stringp ems--message-filter)
       (concat "\\(?:" ems--message-filter "\\|" regexp "\\)")
     regexp)))

(defun emacsvox-agent-shell--filter-vertical-toggle-hint ()
  "Temporarily filter the redundant action hint before vertical motion.
Normal Emacsvox line speech describes the collapsible label.  Keep
agent-shell's cursor-sensor message visible, but filter its exact text from
speech until the cursor sensor has run from `post-command-hook'."
  (when (memq this-command '(next-line previous-line))
    (emacsvox-agent-shell--filter-message-through-post-command
     emacsvox-agent-shell--vertical-toggle-hint-regexp)))

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

(defvar-local emacsvox-agent-shell--speech-control-active nil
  "Non-nil when agent-shell speech-level keys are active.")

(defcustom emacsvox-agent-shell-speech-delay 0.5
  "Delay used to coalesce streamed out-of-turn agent messages.
Normal response completion follows agent-shell's public `turn-complete' event,
so this value never determines when a submitted turn is spoken."
  :type 'number
  :group 'emacsvox-agent-shell)

(defvar emacsvox-agent-shell--speech-control-map
  (make-sparse-keymap)
  "Keymap for agent-shell speech-level controls.")

(defun emacsvox-agent-shell--install-speech-control-bindings ()
  "Install current speech controls, including when this file is reloaded."
  ;; The contextual table map takes precedence inside tables.  After exit,
  ;; repeated vertical table arrows must not fall through to list movement.
  (dolist (key '("C-M-<up>" "C-M-<down>"))
    (define-key emacsvox-agent-shell--speech-control-map (kbd key) #'ignore))
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
              #'emacsvox-agent-shell-previous-block-at-point)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "t")
              #'emacsvox-agent-shell-next-table)
  (define-key emacsvox-agent-shell--speech-control-map (kbd "T")
              #'emacsvox-agent-shell-previous-table)
  (dolist (binding '(("h" . emacsvox-agent-shell-next-heading)
                     ("H" . emacsvox-agent-shell-previous-heading)
                     ("k" . emacsvox-agent-shell-next-source-block)
                     ("K" . emacsvox-agent-shell-previous-source-block)
                     ("u" . emacsvox-agent-shell-next-user-prompt)
                     ("U" . emacsvox-agent-shell-previous-user-prompt)
                     ("j" . emacsvox-agent-shell-next-response)
                     ("J" . emacsvox-agent-shell-previous-response)
                     ("l" . emacsvox-agent-shell-next-link)
                     ("L" . emacsvox-agent-shell-previous-link)
                     ("e" . emacsvox-agent-shell-next-error)
                     ("E" . emacsvox-agent-shell-previous-error)))
    (define-key emacsvox-agent-shell--speech-control-map
                (kbd (car binding)) (cdr binding)))
  (when (fboundp 'emacsvox-agent-shell--install-table-entry-bindings)
    (emacsvox-agent-shell--install-table-entry-bindings)))

(emacsvox-agent-shell--install-speech-control-bindings)

(unless (assq 'emacsvox-agent-shell--speech-control-active
              minor-mode-map-alist)
  (push (cons 'emacsvox-agent-shell--speech-control-active
              emacsvox-agent-shell--speech-control-map)
        minor-mode-map-alist))

(defun emacsvox-agent-shell--live-input-bounds ()
  "Return the current live Agent Shell input bounds, or nil.

The chat-mode prompt overlay confirms that `comint-last-prompt' names the
visible live prompt rather than historical output.  User input begins at the
prompt's end and extends to `point-max'."
  (when (and (derived-mode-p 'agent-shell-mode)
             (consp comint-last-prompt))
    (let* ((end-marker (cdr comint-last-prompt))
           (start (and (markerp end-marker)
                       (eq (marker-buffer end-marker) (current-buffer))
                       (marker-position end-marker)))
           (end (point-max)))
      (when (and start
                 (< (point-min) start)
                 (<= start end)
                 (not (text-property-any start end 'field 'output))
                 (seq-some
                  (lambda (overlay)
                    (and (= (overlay-end overlay) start)
                         (emacsvox-agent-shell--live-chat-prompt-overlay-p
                          overlay)))
                  (overlays-in (1- start) start)))
        (cons start end)))))

(defun emacsvox-agent-shell--input-boundary-feedback (boundary)
  "Speak the live prompt input BOUNDARY without a decorative cue."
  (emacsvox-agent-shell--submit-text-feedback
   (if (eq boundary 'beginning)
       "Beginning of input"
     "End of input")
   (emacsvox-agent-shell--presentation-facts
    'agent-user-prompt 'boundary-entered)
   'navigation))

(defun emacsvox-agent-shell--hidden-chat-overlay-at (position direction)
  "Return the hidden chat overlay to cross at POSITION in DIRECTION."
  (let (best)
    (dolist (overlay (overlays-at position))
      (when (and
             (memq (emacsvox-agent-shell--chat-overlay-tag overlay)
                   '(me me-label me-surplus agent))
             ;; Split label rows replace source characters with a nonempty
             ;; display string.  Their underlying prompt/marker is still UI
             ;; source and must not be read one character at a time.
             (stringp (overlay-get overlay 'display))
             (< (overlay-start overlay) (overlay-end overlay))
             (or
              (null best)
              (if (eq direction 'forward)
                  (> (overlay-end overlay) (overlay-end best))
                (< (overlay-start overlay) (overlay-start best)))))
        (setq best overlay)))
    best))

(defun emacsvox-agent-shell--horizontal-chat-destination (direction steps)
  "Return a DIRECTION destination STEPS away across hidden chat source.

Return nil when ordinary character motion would not cross a hidden chat
overlay.  Each hidden overlay counts as no source characters, so a step into
one lands on the next real character in DIRECTION."
  (when (derived-mode-p 'agent-shell-mode)
    (let ((position (point))
          (delta (if (eq direction 'forward) 1 -1))
          crossed
          valid)
      (setq valid t)
      (dotimes (_ steps)
        (let ((next (+ position delta)))
          (if (not (<= (point-min) next (point-max)))
              (setq valid nil)
            (setq position next)
            (let (overlay)
              (while (and valid
                          (setq overlay
                                (emacsvox-agent-shell--hidden-chat-overlay-at
                                 position direction)))
                (setq crossed t
                      position
                      (if (eq direction 'forward)
                          (overlay-end overlay)
                        (1- (overlay-start overlay))))
                (unless (<= (point-min) position (point-max))
                  (setq valid nil)))))))
      (and valid crossed position))))

(defun emacsvox-agent-shell--horizontal-motion-around
    (original-function nominal-direction arguments)
  "Normalize interactive horizontal motion through Agent Shell chat UI.

ORIGINAL-FUNCTION receives ARGUMENTS when motion does not cross a prompt
boundary.  NOMINAL-DIRECTION is the positive-argument direction of the
advised command.  Live input boundaries remain semantic, while display-only
chat source is crossed as one unit before core character speech runs."
  (let* ((target ems--interactive-fn-name)
         (interactive-p
          (memq target '(left-char right-char backward-char forward-char)))
         (count (prefix-numeric-value (car arguments)))
         (direction
          (if (< count 0)
              (if (eq nominal-direction 'forward) 'backward 'forward)
            nominal-direction))
         (steps (abs count))
         (bounds (and interactive-p
                      (> steps 0)
                      (emacsvox-agent-shell--live-input-bounds)))
         (start (car-safe bounds))
         (end (cdr-safe bounds))
         boundary
         chat-destination)
    (when (and bounds (<= start (point)) (<= (point) end))
      (setq boundary
            (pcase direction
              ('backward
               (and (> steps (- (point) start)) 'beginning))
              ('forward
               (and (>= steps (- end (point))) 'end)))))
    (unless boundary
      (setq chat-destination
            (and interactive-p
                 (> steps 0)
                 (emacsvox-agent-shell--horizontal-chat-destination
                  direction steps))))
    (cond
     ((and interactive-p
           (emacsvox-agent-shell--table-text-motion
            target nominal-direction count nil)) nil)
     (boundary
      ;; Consume the interactive marker so core character advice cannot add
      ;; ellipses, "control at", or an end-of-buffer warning if its advice is
      ;; outside this adapter in the current advice order.
      (ems-interactive-p target)
      (goto-char (if (eq boundary 'beginning) start end))
      (emacsvox-agent-shell--input-boundary-feedback boundary)
      nil)
     (chat-destination
      ;; Chat overlays replace the underlying prompt/marker source.  Bypass it so
      ;; core character presentation cannot emit one ellipses icon per hidden
      ;; prompt character, then provide the same destination feedback here.
      (ems-interactive-p target)
      (goto-char chat-destination)
      (and tts-stop-immediately (tts-stop))
      (let ((emacsvox-aural-submission-occasion 'navigation))
        (emacsvox-speak-char t))
      nil)
     (t
      (apply original-function arguments)))))

(defun emacsvox-agent-shell--backward-char-around
    (original-function &rest arguments)
  "Keep interactive backward character motion inside live prompt input."
  (emacsvox-agent-shell--horizontal-motion-around
   original-function 'backward arguments))

(defun emacsvox-agent-shell--forward-char-around
    (original-function &rest arguments)
  "Keep interactive forward character motion inside live prompt input."
  (emacsvox-agent-shell--horizontal-motion-around
   original-function 'forward arguments))

(defun emacsvox-agent-shell--speak-live-input-visual-line
    (input-bounds boundary)
  "Speak the editable visual line within INPUT-BOUNDS.
BOUNDARY is `beginning' or `end' and supplies feedback for empty input."
  (pcase-let ((`(,visual-start . ,visual-end)
               (emacsvox-agent-shell--visual-line-source-bounds)))
    (let ((start (max (car input-bounds) visual-start))
          (end (min (cdr input-bounds) visual-end)))
      (if (< start end)
          (let ((emacsvox-agent-shell--chat-label-context nil)
                (emacsvox-agent-shell--line-navigation-speech-p t)
                (emacsvox-show-point nil))
            (emacsvox-speak-region start end))
        (emacsvox-agent-shell--input-boundary-feedback boundary)))))

(defun emacsvox-agent-shell--visual-line-input-around
    (original-function target boundary arguments)
  "Present an interactive live-input visual-line TARGET concisely.
ORIGINAL-FUNCTION receives ARGUMENTS unchanged.  BOUNDARY names the endpoint
selected by TARGET."
  (let* ((interactive-p (eq ems--interactive-fn-name target))
         (ordinary-motion-p
          (= 1 (prefix-numeric-value (car arguments))))
         (bounds (and interactive-p
                      ordinary-motion-p
                      (emacsvox-agent-shell--live-input-bounds)))
         (in-input-p
          (and bounds
               (<= (car bounds) (point))
               (<= (point) (cdr bounds)))))
    (if (not in-input-p)
        (apply original-function arguments)
      ;; Consume the marker before core after-advice runs; this adapter speaks
      ;; the editable visual line without the prompt label or point highlight.
      (ems-interactive-p target)
      (let ((result (apply original-function arguments)))
        (emacsvox-agent-shell--speak-live-input-visual-line bounds boundary)
        result))))

(defun emacsvox-agent-shell--beginning-of-visual-line-around
    (original-function &rest arguments)
  "Read live prompt input after interactive visual-line beginning motion."
  (emacsvox-agent-shell--visual-line-input-around
   original-function 'beginning-of-visual-line 'beginning arguments))

(defun emacsvox-agent-shell--end-of-visual-line-around
    (original-function &rest arguments)
  "Read live prompt input after interactive visual-line end motion."
  (emacsvox-agent-shell--visual-line-input-around
   original-function 'end-of-visual-line 'end arguments))

;;;  Advice Agent-Shell Functions

(defun emacsvox-agent-shell--kill-visual-line-around
    (original-function &rest arguments)
  "Mark an interactive Agent Shell visual-line kill.
Call ORIGINAL-FUNCTION with ARGUMENTS unchanged.  The marker lets the nested
`kill-region' announce its exact bounds instead of repeating the whole prompt
line."
  (let ((emacsvox-agent-shell--visual-line-kill-p
         (and (derived-mode-p 'agent-shell-mode)
              (eq ems--interactive-fn-name 'kill-visual-line))))
    (apply original-function arguments)))

(defun emacsvox-agent-shell--kill-region-around
    (original-function beginning end &rest arguments)
  "Speak an Agent Shell visual-line kill, then call ORIGINAL-FUNCTION.
BEGINNING and END are the exact bounds selected by `kill-visual-line'.
ARGUMENTS are passed to ORIGINAL-FUNCTION unchanged."
  (when emacsvox-agent-shell--visual-line-kill-p
    (let ((emacsvox-agent-shell--chat-label-context nil)
          (emacsvox-agent-shell--line-navigation-speech-p nil))
      (emacsvox-speak-region (min beginning end) (max beginning end))))
  (apply original-function beginning end arguments))

(defun emacsvox-agent-shell--live-input-source-bounds (visual-bounds)
  "Recover an empty or reversed VISUAL-BOUNDS interval in the live prompt.
Prompt display strings can confuse `end-of-visual-line'.  Moving forward
one display row from the draft still locates its end, including wrapped
input.  Keep the prompt source on the first row so speech can name Me."
  (when (<= (cdr visual-bounds) (car visual-bounds))
    (when-let* ((input (emacsvox-agent-shell--live-input-bounds))
                (prompt-start (marker-position (car comint-last-prompt)))
                ((<= prompt-start (point))))
      (save-excursion
        (let ((inhibit-field-text-motion t))
          (goto-char (max (point) (car input)))
          (let* ((physical-end (line-end-position))
                 (start (save-excursion (vertical-motion 0) (point)))
                 (end (progn (vertical-motion 1)
                             (min (point) physical-end))))
            (setq start (if (<= start (car input)) prompt-start start))
            (when (< start end)
              (cons start end))))))))

(defun emacsvox-agent-shell--call-with-folded-heading-cue
    (function arguments)
  "Call FUNCTION with ARGUMENTS, adding a folded cue to its speech submission.
Keep the cue in the same presentation as the heading so aural rules can
replace it and navigation interruption cannot cancel it separately."
  (let ((submit (symbol-function 'emacsvox-aural-submit)))
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (text &rest options)
            (apply submit text
                   (plist-put
                    options :compatibility-actions
                    (append (plist-get options :compatibility-actions)
                            (list (emacsvox-aural-compatibility-icon
                                   'ellipses))))))))
      (apply function arguments))))

(defun emacsvox-agent-shell--speak-visual-line-around
    (original-function &rest arguments)
  "Add semantic block-entry context to Agent Shell visual-line speech.

Core visual-line presentation owns blank-line semantics and interruption."
  (unless emacsvox-agent-shell--visual-line-kill-p
    (let* ((state (get-text-property (point) 'agent-shell-ui-state))
           (section (get-text-property (point) 'agent-shell-ui-section))
           (folded-heading-bounds
            (when (and state
                       (map-elt state :collapsed)
                       (memq section '(indicator label-left label-right)))
              (cons (line-beginning-position) (line-end-position))))
           (folded-heading-entry-p
            (and folded-heading-bounds
                 (emacsvox-agent-shell--vertical-block-entry-facts)))
           (source-bounds
            (if folded-heading-bounds
                ;; Invisible bodies can make the display engine treat a complete
                ;; folded fragment as one source span.  Narrowing to its visible
                ;; physical heading retains visual wrapping without copying the
                ;; hidden body or repeating the complete heading on every row.
                (save-restriction
                  (narrow-to-region
                   (car folded-heading-bounds)
                   (cdr folded-heading-bounds))
                  (emacsvox-agent-shell--visual-line-source-bounds))
              (emacsvox-agent-shell--visual-line-source-bounds)))
           (input-source-bounds
            (emacsvox-agent-shell--live-input-source-bounds source-bounds))
           (raw-source-bounds source-bounds)
           (response-source-bounds
            (emacsvox-agent-shell--response-row-source-bounds source-bounds))
           (source-bounds
            (or input-source-bounds response-source-bounds source-bounds))
           (source-start (car source-bounds))
           (source-end (cdr source-bounds))
           (emacsvox-agent-shell--chat-label-context
            (emacsvox-agent-shell--chat-label-context-between
             source-start source-end))
           (emacsvox-agent-shell--line-navigation-speech-p t)
           (ems--speak-max-length
            (if (and
                 (integerp emacsvox-agent-shell-line-speech-max-characters)
                 (> emacsvox-agent-shell-line-speech-max-characters 0))
                most-positive-fixnum
              ems--speak-max-length)))
      (unless
          (emacsvox-agent-shell--synthetic-agent-row-p
           (car raw-source-bounds) (cdr raw-source-bounds))
        (emacsvox-agent-shell--call-with-vertical-block-entry
         (cond
          ((or input-source-bounds response-source-bounds)
           (lambda (&rest _)
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-aural-source-substring source-start source-end)
              emacsvox-aural-submission-facts 'navigation)))
          (folded-heading-bounds
           (lambda (&rest call-arguments)
             (save-restriction
               (narrow-to-region
                (car folded-heading-bounds)
                (cdr folded-heading-bounds))
               (if folded-heading-entry-p
                   (emacsvox-agent-shell--call-with-folded-heading-cue
                    original-function call-arguments)
                 (apply original-function call-arguments)))))
          (t original-function))
         arguments)))))

(defun emacsvox-agent-shell--speak-line-around
    (original-function &rest arguments)
  "Add semantic block-entry facts to vertical line speech."
  (let* ((start (line-beginning-position))
         (end (line-end-position))
         (observed-at (float-time)))
    (emacsvox-aural-diagnostic-log-event
     'line-presentation-start
     :command this-command
     :buffer (buffer-name)
     :mode major-mode
     :point (point)
     :line (line-number-at-pos)
     :command-elapsed-ms
     (emacsvox-aural--diagnostic-elapsed-ms
      emacsvox-aural-command-start-time observed-at)
     :content-characters (- end start)
     :content (buffer-substring-no-properties start end))
    (let ((emacsvox-agent-shell--chat-label-context
           (emacsvox-agent-shell--chat-label-context-at-point))
          (emacsvox-agent-shell--line-navigation-speech-p t)
          (ems--speak-max-length
           (if (and
                (integerp emacsvox-agent-shell-line-speech-max-characters)
                (> emacsvox-agent-shell-line-speech-max-characters 0))
               most-positive-fixnum
             ems--speak-max-length)))
      (emacsvox-agent-shell--call-with-vertical-block-entry
       original-function arguments))))

(defun emacsvox-agent-shell--tts-speak-around
    (original-function text &rest arguments)
  "Preserve rendered Markdown properties while speaking agent-shell content.
Native submissions have already transformed and prepared their immutable text,
so this adapter leaves them untouched.  Bare legacy TTS calls are transformed
once without changing agent-shell's clipboard handler or source buffer."
  (apply original-function
         (if (emacsvox-aural-prepared-text-p text)
             text
           (emacsvox-agent-shell--prepare-speech-text text))
         arguments))

(defun emacsvox-agent-shell--agent-shell-after (&rest _)
  "Announce switching to agent-shell mode.
Provide an auditory icon if possible."
  (when (ems-interactive-p 'agent-shell)
    (tts-apply-punctuation-mode-policy)
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

(require 'emacsvox-agent-shell-navigation)
(emacsvox-agent-shell--install-block-repeat-bindings)

;; Load the rendered-table adapter after the shared speech map exists.
(require 'emacsvox-agent-shell-tables)
(emacsvox-agent-shell--install-table-adapter)

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
      ;; Keep the cursor sensor's echo-area hint, but speak the choice once.
      (emacsvox-agent-shell--filter-message-through-post-command
       (concat "\\`Press RET" (if key (concat " or " (regexp-quote key)) "")
               " to " (regexp-quote label) "\\'"))
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
  (let ((destination (point))
        (emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (when-let* (((not emacsvox-table-reader--suspended))
                ((eq (emacsvox-table-reader--preference 'activation) 'automatic))
                (table-position
                (if (get-text-property
                     destination 'agent-shell-markdown-table-source)
                    destination
                  (emacsvox-agent-shell--table-between
                   origin destination direction))))
      (goto-char table-position)
      (emacsvox-agent-shell--table-entry-feedback direction))))

(defun emacsvox-agent-shell--item-label-at (property position)
  "Return concise visible text for PROPERTY's run at POSITION."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                property position)))
    (emacsvox-agent-shell--nonempty-text
     (replace-regexp-in-string
      "[[:space:]\n\r]+" " "
      (buffer-substring-no-properties (car range) (cdr range))))))

(defun emacsvox-agent-shell--item-help-action-at (position)
  "Return the action described by `help-echo' at POSITION."
  (let* ((value (get-text-property position 'help-echo))
         (rendered
          (cond
           ((stringp value) value)
           ((functionp value)
            (condition-case nil
                (funcall value (selected-window) (current-buffer) position)
              (error nil))))))
    (emacsvox-agent-shell--nonempty-text rendered)))

(defun emacsvox-agent-shell--item-action-sentence (position fallback)
  "Return a speech-friendly action at POSITION, using FALLBACK if needed."
  (let* ((action
          (or (emacsvox-agent-shell--item-help-action-at position)
              fallback))
         (verb
          (concat (downcase (substring action 0 1))
                  (substring action 1))))
    (format "Press Return to %s."
            (string-remove-suffix "." verb))))

(defun emacsvox-agent-shell--image-position-at-point ()
  "Return the displayed image position at or immediately before point."
  (seq-find
   (lambda (position)
     (and (>= position (point-min))
          (< position (point-max))
          (eq (car-safe (get-text-property position 'display)) 'image)))
   (list (point) (1- (point)))))

(defun emacsvox-agent-shell--image-link-at-p (position)
  "Return non-nil when the rendered link at POSITION represents an image."
  (when-let* ((source
               (get-text-property position 'agent-shell-markdown-source)))
    (and (stringp source)
         (string-match-p "\\`[[:space:]]*!\\[" source))))

(defun emacsvox-agent-shell--semantic-item-feedback ()
  "Speak an actionable source block, image, or link at point.
Return non-nil when point represents one of those semantic items."
  (let ((position (point))
        speech)
    (cond
     ((get-text-property
       position 'agent-shell-markdown-source-block-copy)
      (let ((location
             (emacsvox-agent-shell--source-block-location-at-position
              position)))
        (setq
         speech
         (concat
          (if location
              (propertize
               (emacsvox-agent-shell--source-block-summary location)
               'face 'agent-shell-markdown-source-block-language)
            "Source block.")
          " Press Return to copy."))))
     ((when-let* ((image-position
                   (emacsvox-agent-shell--image-position-at-point)))
        (setq position image-position)
        (let* ((label
                (or
                 (emacsvox-agent-shell--item-label-at
                  'display image-position)
                 "Image"))
               (action
                (string-remove-suffix
                 "."
                 (emacsvox-agent-shell--item-action-sentence
                  image-position "open image"))))
          (setq speech
                (format "%s, image. %s; plus, minus, or zero to resize."
                        label action)))))
     ((and (get-text-property position 'agent-shell-markdown-url)
           (emacsvox-agent-shell--image-link-at-p position))
      (let ((label
             (or
              (emacsvox-agent-shell--item-label-at
               'agent-shell-markdown-url position)
              "Image")))
        (setq speech
              (format "%s, image. %s"
                      label
                      (emacsvox-agent-shell--item-action-sentence
                       position "open image")))))
     ((when-let* ((url
                   (get-text-property
                    position 'agent-shell-markdown-url)))
        (let ((label
               (or
                (emacsvox-agent-shell--item-label-at
                 'agent-shell-markdown-url position)
                (emacsvox-agent-shell--nonempty-text url)
                "Link")))
          (setq speech
                (concat
                 (propertize label 'face 'agent-shell-markdown-link)
                 ", link. "
                 (emacsvox-agent-shell--item-action-sentence
                  position "open")))))))
    (when speech
      ;; The cursor sensor still displays its dynamic hint in the echo area.
      ;; Filter only its redundant speech after this atomic announcement.
      (emacsvox-agent-shell--filter-message-through-post-command
       emacsvox-agent-shell--item-action-hint-regexp)
      (emacsvox-agent-shell--submit-text-feedback
       speech
       (emacsvox-agent-shell--block-location-facts
        (emacsvox-agent-shell--block-location-at-point position)
        'focus-entered)
       'navigation 'item)
      t)))

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
                  (emacsvox-agent-shell--question-feedback)
                  (emacsvox-agent-shell--permission-button-feedback)
                  (emacsvox-agent-shell--table-cell-feedback)
                  (emacsvox-agent-shell--semantic-item-feedback))
        (when-let* ((line (ems--this-line))
                    ((emacsvox-agent-shell--nonempty-text line)))
          (emacsvox-agent-shell--submit-text-feedback
           line
           (emacsvox-agent-shell--block-location-facts
            (emacsvox-agent-shell--block-location-at-point)
            'focus-entered)
           'navigation 'item))))))

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
                  (emacsvox-agent-shell--question-feedback)
                  (emacsvox-agent-shell--permission-button-feedback)
                  (emacsvox-agent-shell--table-cell-feedback)
                  (emacsvox-agent-shell--semantic-item-feedback))
        (when-let* ((line (ems--this-line))
                    ((emacsvox-agent-shell--nonempty-text line)))
          (emacsvox-agent-shell--submit-text-feedback
           line
           (emacsvox-agent-shell--block-location-facts
            (emacsvox-agent-shell--block-location-at-point)
            'focus-entered)
           'navigation 'item))))))

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

;;;  Viewport Mode Integration

(defun emacsvox-agent-shell--list-edit-around (original arguments command)
  "Describe the structure changed by list-edit COMMAND through ORIGINAL."
  (if (not (ems-interactive-p command))
      (apply original arguments)
    (let ((before (agent-shell-list-edit--at-item))
          (tick (buffer-chars-modified-tick)))
      (if (and (not before)
               (memq command '(agent-shell-list-edit-newline
                               agent-shell-list-edit-indent-line)))
          ;; These paths delegate to ordinary editing or completion.  Let
          ;; their native advice own line echo and completion feedback.
          (let ((ems--interactive-fn-name
                 (if (eq command 'agent-shell-list-edit-newline)
                     'newline 'indent-for-tab-command)))
            (apply original arguments))
        (prog1 (apply original arguments)
          (unless (= tick (buffer-chars-modified-tick))
            (let* ((item (agent-shell-list-edit--at-item))
                   (kind (or (map-elt item :type) 'none))
                   (indent (current-indentation))
                   (marker (map-elt item :marker))
                   (newline-p (eq command 'agent-shell-list-edit-newline))
                   (ended (and before (not item)))
                   (event (cond (ended 'agent-list-ended)
                                (newline-p 'agent-list-item-created)
                                (t 'agent-list-indentation-changed))))
              (emacsvox-agent-shell--submit-text-feedback
               (cond
                (ended "List ended.")
                ((eq kind 'numbered)
                 (format "Item %s, indentation %d." marker indent))
                ((eq kind 'bullet) (format "Bullet, indentation %d." indent))
                (t "New line."))
               (emacsvox-agent-shell--presentation-facts
                'agent-prompt-editor event nil
                (append (list :agent-list-kind kind :agent-list-indent indent)
                        (when marker (list :agent-list-marker marker))))
               'edit))))))))

(defun emacsvox-agent-shell--list-newline-around (original &rest arguments)
  "Speak list continuation or exit after ORIGINAL inserts a newline."
  (emacsvox-agent-shell--list-edit-around
   original arguments 'agent-shell-list-edit-newline))

(defun emacsvox-agent-shell--list-indent-around (original &rest arguments)
  "Speak the list indentation produced by ORIGINAL."
  (emacsvox-agent-shell--list-edit-around
   original arguments 'agent-shell-list-edit-indent-line))

(defun emacsvox-agent-shell--list-dedent-around (original &rest arguments)
  "Speak the list indentation produced by ORIGINAL."
  (emacsvox-agent-shell--list-edit-around
   original arguments 'agent-shell-list-edit-dedent-line))

(defun emacsvox-agent-shell--diff-around (original &rest arguments)
  "Orient the reader to the change review displayed by ORIGINAL."
  (let ((buffer (apply original arguments)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (derived-mode-p 'agent-shell-diff-mode)
          (let* ((files (length (plist-get arguments :diffs)))
                 (hunks (save-excursion
                          (goto-char (point-min))
                          (let ((count 0))
                            (while (re-search-forward "^@@ " nil t)
                              (cl-incf count))
                            count)))
                 (name (and (= files 1)
                            (map-elt (car (plist-get arguments :diffs)) :file))))
            (emacsvox-agent-shell--submit-text-feedback
             (format (substitute-command-keys
                      "Review changes. %s%d %s, %d %s. \\[diff-hunk-next] and \\[diff-hunk-prev] move between hunks.")
                     (if name (concat (file-name-nondirectory name) ". ") "")
                     files (if (= files 1) "file" "files")
                     hunks (if (= hunks 1) "hunk" "hunks"))
             (emacsvox-agent-shell--presentation-facts
              'agent-diff 'agent-diff-opened nil
              (list :agent-diff-files files :agent-diff-hunks hunks))
             'navigation 'open-object)))))
    buffer))

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
          (emacsvox-agent-shell--question-feedback)
          (emacsvox-agent-shell--permission-button-feedback)
          (emacsvox-agent-shell--table-cell-feedback)
          (emacsvox-agent-shell--semantic-item-feedback)))))

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
          (emacsvox-agent-shell--question-feedback)
          (emacsvox-agent-shell--permission-button-feedback)
          (emacsvox-agent-shell--table-cell-feedback)
          (emacsvox-agent-shell--semantic-item-feedback)))))

(defun emacsvox-agent-shell--viewport-show-buffer-after (&rest _)
  "Announce viewport display."
  (when (ems-interactive-p 'agent-shell-viewport--show-buffer)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-viewport-opened)
     'navigation 'open-object)))

(defun emacsvox-agent-shell--prompt-compose-after (&rest _)
  "Announce prompt composition."
  (when (ems-interactive-p 'agent-shell-prompt-compose)
    (emacsvox-agent-shell--submit-text-feedback
     "Compose prompt"
     (emacsvox-agent-shell--presentation-facts
      'agent-prompt-editor 'agent-prompt-opened)
     'edit 'open-object)))

(defun emacsvox-agent-shell--viewport-refresh-after (&rest _)
  "Announce viewport refresh."
  (when (ems-interactive-p 'agent-shell-viewport-refresh)
    (emacsvox-agent-shell--submit-text-feedback
     "Viewport refreshed"
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-viewport-refreshed)
     'state-change 'task-done)))

;;;  Interactive Commands for Viewport

(defun emacsvox-agent-shell--viewport-view-mode-after (&rest _)
  "Announce a switch to the viewport view mode."
  (when (ems-interactive-p 'agent-shell-viewport-view-mode)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-setting-changed nil
      '(:agent-viewport-mode view))
     'state-change 'select-object)))

(defun emacsvox-agent-shell--viewport-edit-mode-after (&rest _)
  "Announce a switch to the viewport edit mode."
  (when (ems-interactive-p 'agent-shell-viewport-edit-mode)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--brief-session-speech)
     (emacsvox-agent-shell--presentation-facts
      'agent-viewport 'agent-setting-changed nil
      '(:agent-viewport-mode edit))
     'state-change 'select-object)))

;;;  Tool Call Feedback

(defun emacsvox-agent-shell--buffer-setup ()
  "Activate speech, event support, and centralized cleanup in this shell."
  (emacsvox-agent-shell--activate-buffer-values)
  (unless emacsvox-agent-shell--config-option-cache
    (emacsvox-agent-shell--observe-config-options
     (emacsvox-agent-shell--config-options) nil))
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
  (emacsvox-agent-shell--interaction-cleanup)
  (emacsvox-agent-shell--response-section-cleanup)
  (emacsvox-agent-shell--cancel-pending-speech)
  (setq emacsvox-agent-shell--pending-bodies nil)
  (emacsvox-agent-shell--permission-event-cleanup)
  (emacsvox-agent-shell--lifecycle-event-cleanup)
  (emacsvox-agent-shell--tool-call-event-cleanup)
  (emacsvox-agent-shell--table-navigation-cleanup)
  (emacsvox-agent-shell--restore-buffer-values)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--buffer-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--buffer-cleanup t))

;;;  Enable/Disable support:

(defconst emacsvox-agent-shell--advice-list
  '((agent-shell-elicitation-act :around emacsvox-agent-shell--question-action-around)
    (agent-shell-elicitation-toggle-preview :around emacsvox-agent-shell--question-action-around)
    (agent-shell-elicitation-interrupt :around emacsvox-agent-shell--question-action-around)
    (agent-shell-elicitation-next-field :filter-return emacsvox-agent-shell--question-navigation-after)
    (agent-shell-elicitation-previous-field :filter-return emacsvox-agent-shell--question-navigation-after)
    (agent-shell-elicitation-jump-to-latest-form :filter-return emacsvox-agent-shell--question-navigation-after)
    (agent-shell-yank-dwim :around emacsvox-agent-shell--yank-dwim-around)
    (agent-shell--on-notification :around
     emacsvox-agent-shell--on-notification-around)
    (agent-shell--send-request :around emacsvox-agent-shell--send-request-around)
    (agent-shell-experimental--on-session-push-request :around
     emacsvox-agent-shell--push-request-around)
    (agent-shell-experimental--on-session-push-end :around
     emacsvox-agent-shell--push-end-around)
    (agent-shell--prompt-queue-process-next :around
     emacsvox-agent-shell--queue-process-around)
    (agent-shell--prompt-queue-display :after
     emacsvox-agent-shell--queue-display-after)
    (agent-shell--prompt-queue-enqueue :after
     emacsvox-agent-shell--prompt-enqueued-after)
    (agent-shell-experimental--send-steering :after
     emacsvox-agent-shell--steering-sent-after)
    (agent-shell-list-edit-newline :around
     emacsvox-agent-shell--list-newline-around)
    (agent-shell-list-edit-indent-line :around
     emacsvox-agent-shell--list-indent-around)
    (agent-shell-list-edit-dedent-line :around
     emacsvox-agent-shell--list-dedent-around)
    (agent-shell-diff :around emacsvox-agent-shell--diff-around)
    (emacsvox-speak-visual-line :around
     emacsvox-agent-shell--speak-visual-line-around)
    (emacsvox-speak-line :around
     emacsvox-agent-shell--speak-line-around)
    (beginning-of-visual-line :around
     emacsvox-agent-shell--beginning-of-visual-line-around)
    (end-of-visual-line :around
     emacsvox-agent-shell--end-of-visual-line-around)
    (kill-visual-line :around
     emacsvox-agent-shell--kill-visual-line-around)
    (kill-region :around
     emacsvox-agent-shell--kill-region-around)
    (left-char :around emacsvox-agent-shell--backward-char-around)
    (backward-char :around emacsvox-agent-shell--backward-char-around)
    (right-char :around emacsvox-agent-shell--forward-char-around)
    (forward-char :around emacsvox-agent-shell--forward-char-around)
    (forward-word :around emacsvox-agent-shell--forward-word-around)
    (right-word :around emacsvox-agent-shell--forward-word-around)
    (backward-word :around emacsvox-agent-shell--backward-word-around)
    (left-word :around emacsvox-agent-shell--backward-word-around)
    (next-line :around emacsvox-agent-shell--next-line-around)
    (previous-line :around emacsvox-agent-shell--previous-line-around)
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
    (agent-shell-set-session-model :around
     emacsvox-agent-shell--set-session-model-around)
    (agent-shell-set-session-mode :around
     emacsvox-agent-shell--set-session-mode-around)
    (agent-shell-cycle-session-mode :around
     emacsvox-agent-shell--cycle-session-mode-around)
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
    (agent-shell-viewport-compose-send-override :around
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
                    (append
                     '((name . emacsvox-agent-shell))
                     ;; Capture the interactive marker before core kill
                     ;; advice consumes it, whichever module loads first.
                     (when (eq target 'kill-visual-line)
                       '((depth . -10)))))))))

(defun emacsvox-agent-shell--remove-advice ()
  "Remove native Agent Shell advice."
  (dolist (entry emacsvox-agent-shell--advice-list)
    (pcase-let ((`(,target ,_where ,function) entry))
      (when (advice-member-p function target)
        (advice-remove target function)))))

(defun emacsvox-agent-shell-enable ()
  "Enable Emacsvox support for Agent Shell 0.85.3 or newer."
  (interactive)
  (unless (and (boundp 'agent-shell--version)
               (version<= "0.85.3" agent-shell--version))
    (user-error "Emacsvox requires Agent Shell 0.85.3 or newer"))
  (emacsvox-agent-shell--upgrade-response-monitoring)
  (emacsvox-agent-shell--install-advice)
  ;; Remove hooks installed by earlier versions before installing the
  ;; centralized setup path.
  (remove-hook 'agent-shell-mode-hook #'emacsvox-agent-shell-speech-setup)
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
    (emacsvox-agent-shell--submit-text-feedback
     "Enabled Emacsvox agent-shell support"
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change)))

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
    (emacsvox-agent-shell--submit-text-feedback
     "Disabled Emacsvox agent-shell support"
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-setting-changed)
     'state-change)))

(with-eval-after-load 'agent-shell
  (emacsvox-agent-shell-enable))

(provide 'emacsvox-agent-shell)

;;; emacsvox-agent-shell.el ends here
