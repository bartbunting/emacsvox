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
(require 'emacsvox-agent-shell-motion)
(require 'emacsvox-agent-shell-presentation)
(require 'emacsvox-agent-shell-interaction)
(require 'emacsvox-table-reader)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'agent-shell nil 'noerror)
(require 'shell-maker nil 'noerror)

(declare-function agent-shell-copy-source-block-at-point
                  "agent-shell" (&optional pos))
(declare-function agent-shell-goto-last-interaction "agent-shell" ())
(declare-function agent-shell-interaction-at-point "agent-shell" ())
(declare-function agent-shell-markdown-source-block-at-point
                  "agent-shell-markdown" (&optional pos))
;; These public entry points are `cl-defun' keyword APIs.  A value of t keeps
;; `check-declare' checking their source without presenting `&key' as positional
;; to the native byte compiler, whose declaration arglists follow `defun'.
(declare-function agent-shell-session-id "agent-shell" t)
(declare-function agent-shell-steering-supported-p "agent-shell" t)
(declare-function agent-shell-subscribe-to "agent-shell" t)
(declare-function agent-shell-unsubscribe "agent-shell" t)
(declare-function agent-shell-viewport--shell-buffer
                  "agent-shell-viewport" (&optional viewport-buffer))
(declare-function agent-shell-ui-toggle-fragment "agent-shell-ui" ())
(declare-function agent-shell-ui-toggle-all-fragments "agent-shell-ui" ())
(declare-function agent-shell-ui--toggle-fragment-at-point
                  "agent-shell-ui" ())
(declare-function shell-maker-point-at-last-prompt-p "shell-maker" ())
(declare-function agent-shell--point-in-live-input-p "agent-shell-prompt" ())
(declare-function emacsvox-speak--present-physical-line
                  "emacsvox-speak" (&optional arg compatibility-actions))

(defvar emacsvox-comint-autospeak)
(defvar emacsvox-pronounce-date-mm-dd-yyyy-pattern)
(defvar emacsvox-pronounce-date-yyyy-mm-dd-pattern)
(defvar emacsvox-pronounce-rfc-3339-datetime-pattern)
(defvar emacsvox-pronounce-sha-checksum-pattern)
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

(defcustom emacsvox-agent-shell-input-activation 'automatic
  "How the inline Agent Shell prompt becomes editable.
Automatic preserves ordinary typing at the live prompt.  Explicit keeps the
shell in browse mode until RET at the prompt or `C-c i' activates editing.
`C-c e' returns to browsing without discarding the draft.  Dedicated viewport
editors retain their normal editing behaviour."
  :type '(choice (const :tag "Automatic" automatic)
                 (const :tag "Explicit" explicit))
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (fboundp 'emacsvox-agent-shell--input-refresh)
           (emacsvox-agent-shell--input-refresh)))
  :group 'emacsvox-agent-shell)

(defcustom emacsvox-agent-shell-input-state-feedback 'speech
  "Feedback when entering inline editing or explicitly returning to browsing.
Speech says Editing or Browsing.  Earcon plays agent-input-on for editing and
agent-input-off for browsing; Both combines them.  The bundled recordings are
08-pop-and-collapse-on and 08-pop-and-collapse-off.  Earcons require auditory
icons to be enabled.  Submission confirmations remain separate.
This default applies immediately; buffer-local overrides take precedence."
  :type '(choice (const :tag "Speech" speech)
                 (const :tag "Earcon" earcon)
                 (const :tag "Both" both))
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
  (emacsvox-agent-shell--mark-existing-diff-headings)
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
  (emacsvox-agent-shell--table-navigation-setup)
  (emacsvox-agent-shell--input-setup))

(defun emacsvox-agent-shell--buffer-cleanup ()
  "Cancel speech work and remove all support state from this shell buffer."
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max)
                            '(emacsvox-agent-shell-diff-heading nil)))
  (emacsvox-agent-shell--interaction-cleanup)
  (emacsvox-agent-shell--response-section-cleanup)
  (emacsvox-agent-shell--cancel-pending-speech)
  (setq emacsvox-agent-shell--pending-bodies nil)
  (emacsvox-agent-shell--permission-event-cleanup)
  (emacsvox-agent-shell--lifecycle-event-cleanup)
  (emacsvox-agent-shell--tool-call-event-cleanup)
  (emacsvox-agent-shell--table-navigation-cleanup)
  (emacsvox-agent-shell--input-cleanup)
  (emacsvox-agent-shell--restore-buffer-values)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--buffer-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--buffer-cleanup t))

;;;  Enable/Disable support:

(defconst emacsvox-agent-shell--advice-list
  '((agent-shell--diff-box :filter-return emacsvox-agent-shell--mark-diff-heading)
    (agent-shell--typing-at-prompt-p :filter-return emacsvox-agent-shell--input-typing-p)
    (agent-shell-submit :around emacsvox-agent-shell--input-submit-around)
    (agent-shell-submit-override :around emacsvox-agent-shell--input-submit-override-around)
    (agent-shell-elicitation-act :around emacsvox-agent-shell--question-action-around)
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
    (agent-shell-prompt-compose :around
     emacsvox-agent-shell--input-compose-around)
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
