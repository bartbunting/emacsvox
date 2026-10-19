;;; emacsvox-eat-core.el --- EAT lifecycle and observation coordination  -*- lexical-binding: t; -*-

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
;; Lifecycle, foreground policy, timers, and observation coordination for EAT.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

;;; Forward variable declarations:

(defvar eat-char-mode-map)
(defvar eat-blink-mode)
(defvar eat-eshell-char-mode-map)
(defvar eat-eshell-emacs-mode-map)
(defvar eat-eshell-exec-hook)
(defvar eat-eshell-exit-hook)
(defvar eat-eshell-mode)
(defvar eat-eshell-semi-char-mode-map)
(defvar eat-eshell-update-hook)
(defvar eat-eshell-visual-command-mode)
(defvar eat-line-mode-map)
(defvar eat--line-mode)
(defvar eat-mode-map)
(defvar eat-semi-char-mode-map)
(defvar eat-terminal)
(defvar eat-trace-mode)
(defvar eshell-parent-buffer)
(defvar emacsvox-eat-review--source-buffer)

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-eat-screen)
(require 'emacsvox-eat-output)
(require 'emacsvox-eat-focus)
(require 'emacsvox-eat-presentation)
(eval-when-compile (require 'eat "eat" 'no-error))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-end "eat" (terminal))
(declare-function eat-term-live-p "eat" (object))
(declare-function eat-term-parameter "eat" (terminal parameter))
(declare-function eat-term-set-parameter "eat" (terminal parameter value))
(declare-function emacsvox-eat--cancel-completion "emacsvox-eat-input" ())
(declare-function emacsvox-eat--cancel-deletion "emacsvox-eat-input" ())
(declare-function emacsvox-eat--completion-current-p "emacsvox-eat-input" ())
(declare-function emacsvox-eat--completion-repeated-p
                  "emacsvox-eat-input" (completion))
(declare-function emacsvox-eat--current-deletion-intent
                  "emacsvox-eat-input" ())
(declare-function emacsvox-eat--current-navigation-intent
                  "emacsvox-eat-input" ())
(declare-function emacsvox-eat--deletion-intent-current-p
                  "emacsvox-eat-input" (intent))
(declare-function emacsvox-eat--kill-review-buffer
                  "emacsvox-eat-review" ())
(declare-function emacsvox-eat--merge-pending-navigation-intent
                  "emacsvox-eat-input" (intent))
(declare-function emacsvox-eat--navigation-intent-current-p
                  "emacsvox-eat-input" (intent))
(declare-function emacsvox-eat--pending-completion-output
                  "emacsvox-eat-input" (snapshot))
(declare-function emacsvox-eat--pending-inline-completion
                  "emacsvox-eat-input" (snapshot))
(declare-function emacsvox-eat--present-completion-output
                  "emacsvox-eat-input" (completion))
(declare-function emacsvox-eat--present-inline-completion
                  "emacsvox-eat-input" (text))
(declare-function emacsvox-eat--present-observed-deletion
                  "emacsvox-eat-input" (intent snapshot))
(declare-function emacsvox-eat--speak-input-correlated-update
                  "emacsvox-eat-input" (cursor))

;;;  Customization:

(defgroup emacsvox-eat nil
  "Speech access to EAT terminals."
  :group 'emacsvox
  :prefix "emacsvox-eat-")

(defcustom emacsvox-eat-autospeak t
  "Whether this terminal produces automatic foreground feedback.
Only the selected terminal with keyboard focus speaks, while following its
live cursor or editing line input.  Turning this off discards local pending
feedback; speech already sent to Omnivox may finish.  Explicit reading, input
feedback, verbosity, and background monitoring remain independent."
  :type 'boolean
  :group 'emacsvox-eat)

(make-variable-buffer-local 'emacsvox-eat-autospeak)

(defcustom emacsvox-eat-prompt-feedback 'earcon
  "Automatic feedback for a prompt identified by EAT shell integration.
Use `earcon' for a ready cue, `text' to read the prompt, or `silent' for no
prompt feedback.  This is independent of verbosity and obeys foreground
autospeak.  Without shell integration, new unfinished text remains ordinary
output, including password requests and confirmation questions."
  :type '(choice (const :tag "Ready cue" earcon)
                 (const :tag "Read prompt" text)
                 (const :tag "Silent" silent))
  :group 'emacsvox-eat)

(make-variable-buffer-local 'emacsvox-eat-prompt-feedback)

(defcustom emacsvox-eat-verbosity 'normal
  "Amount of automatic feedback produced for EAT terminals.
At `terse', retain routine output and metadata for review but do not speak
them automatically.  `normal' speaks bounded command output and status, while
`verbose' additionally announces bounded terminal title and directory changes
and successful shell-command status when EAT shell integration provides it.
Failure, lifecycle, bell, paste, and completion feedback remains available at
every level.  This option may be set buffer-locally for an individual
terminal."
  :type '(choice
          (const :tag "Terse" terse)
          (const :tag "Normal" normal)
          (const :tag "Verbose" verbose))
  :group 'emacsvox-eat)

(make-variable-buffer-local 'emacsvox-eat-verbosity)

(defcustom emacsvox-eat-monitor-background-output nil
  "Whether this EAT buffer cues output received while it is unselected.
Monitoring never speaks background terminal content or identity.  It plays a
rate-limited cue for quiesced text changes and reports the unread burst count
when the terminal is selected again."
  :type 'boolean
  :group 'emacsvox-eat)

(make-variable-buffer-local 'emacsvox-eat-monitor-background-output)

;;;  Lifecycle state:

(defvar-local emacsvox-eat--generation 0
  "Monotonic identity for the current EAT terminal presentation.")

(defvar-local emacsvox-eat--active-process nil
  "Process associated with the current EAT generation.")

(defvar-local emacsvox-eat--visual-command-origin-p nil
  "Non-nil when this process generation was launched by Eshell as visual.")

(defvar-local emacsvox-eat--eshell-output-owned-p nil
  "Non-nil until Eshell publishes the prompt after an EAT-owned command.")

(defvar-local emacsvox-eat--last-exited-process nil
  "Most recent EAT process whose exit was observed in this buffer.")

(defvar-local emacsvox-eat--completion-snapshot nil
  "Generation-scoped public screen state captured before terminal Tab input.")

(defvar-local emacsvox-eat--completion-timer nil
  "Timer that expires `emacsvox-eat--completion-snapshot'.")

(defvar-local emacsvox-eat--completion-serial 0
  "Monotonic identity for terminal completion transactions in this buffer.")

(defvar-local emacsvox-eat--screen-snapshot nil
  "Most recent public-API snapshot of the visible EAT screen.")

(defvar-local emacsvox-eat--pending-screen-baseline nil
  "Screen snapshot at the beginning of the current update burst.")

(defvar-local emacsvox-eat--pending-screen-diff nil
  "Aggregate screen diff waiting for the terminal to become quiescent.")

(defvar-local emacsvox-eat--pending-alternate-screen-transitions nil
  "Alternate-screen states crossed during the pending update burst.")

(defvar-local emacsvox-eat--quiescence-timer nil
  "Timer waiting to finish the current EAT update burst.")

(defvar-local emacsvox-eat--pending-automatic-p nil
  "Non-nil when the whole pending burst permits automatic feedback.")

(defvar emacsvox-eat--automatic-feedback-allowed-p t
  "Dynamically bound eligibility of automatic feedback in a finished burst.")

(defvar-local emacsvox-eat--pending-follow-live-p nil
  "Non-nil when every update in the pending burst followed the live cursor.")

(defvar-local emacsvox-eat--update-serial 0
  "Monotonic serial number for observed EAT screen updates.")

(defvar-local emacsvox-eat--recent-input nil
  "Generation, event, and deadline for one input-correlated screen update.")

(defvar-local emacsvox-eat--recent-navigation-intent nil
  "Content-free terminal navigation intent awaiting its first screen update.")

(defvar-local emacsvox-eat--pending-navigation-intent nil
  "Content-free terminal navigation intent for the current update burst.")

(defvar-local emacsvox-eat--input-row-offset nil
  "Character offset where editable input starts on its prompt row.")

(defvar-local emacsvox-eat--input-start-row nil
  "Screen row on which the current editable input starts.")

(defvar-local emacsvox-eat--deletion-intent nil
  "Observed main-screen deletion awaiting its rendered terminal result.")

(defvar-local emacsvox-eat--deletion-timer nil
  "Timer that resolves an unobserved terminal deletion with a cue.")

(defvar-local emacsvox-eat--deletion-serial 0
  "Monotonic identity for terminal deletion transactions in this buffer.")

(defvar-local emacsvox-eat--secure-input-active-p nil
  "Non-nil while EAT is reading and sending protected terminal input.")

(defvar-local emacsvox-eat--last-screen-diff nil
  "Most recent quiesced screen diff retained for explicit review.")

(defvar-local emacsvox-eat--last-changed-screen nil
  "Screen snapshot belonging to `emacsvox-eat--last-screen-diff'.")

(defvar-local emacsvox-eat--last-likely-focus nil
  "Latest bounded terminal focus object retained for explicit review.")

(defvar-local emacsvox-eat--last-focus-presentation-identity nil
  "Identity of the most recently spoken terminal focus object.")

(defvar-local emacsvox-eat--pending-user-input-p nil
  "Non-nil when the current update burst followed terminal input.")

(defvar-local emacsvox-eat--quiescence-started-at nil
  "Time at which the current bounded EAT update burst began.")

(defvar-local emacsvox-eat--last-completion-output nil
  "Latest quiesced terminal candidate/help-row presentation.")

(defvar-local emacsvox-eat--background-output-timer nil
  "Timer waiting to finish one monitored background-output burst.")

(defvar-local emacsvox-eat--background-output-started-at nil
  "Time at which the pending monitored background-output burst began.")

(defvar-local emacsvox-eat--background-output-serial 0
  "Monotonic serial number for monitored background-output updates.")

(defvar-local emacsvox-eat--background-output-pending-p nil
  "Non-nil when a monitored background text change awaits quiescence.")

(defvar-local emacsvox-eat--review-buffer nil
  "Read-only buffer holding this terminal's explicitly frozen screen review.")

(defvar-local emacsvox-eat--terminal-id nil
  "Process-local integer used in replaceable EAT delivery keys.")

(defvar emacsvox-eat--next-terminal-id 0
  "Next process-local identifier for an initialized EAT buffer.")

(defconst emacsvox-eat--quiescence-delay 0.06
  "Seconds of quiet that finish one EAT screen update burst.")

(defconst emacsvox-eat--quiescence-maximum-delay 0.25
  "Maximum seconds a continuous EAT update burst may postpone classification.")

(defconst emacsvox-eat--completion-timeout 2.0
  "Seconds a terminal-side completion may await compatible remote output.")

(defconst emacsvox-eat--navigation-timeout 0.75
  "Seconds terminal navigation intent may be correlated with screen changes.")

(defconst emacsvox-eat--deletion-timeout 0.75
  "Seconds a visible terminal deletion may await a rendered result.")

(defconst emacsvox-eat--maximum-spoken-candidates 8
  "Maximum inferred terminal candidates spoken automatically at once.")

(defconst emacsvox-eat--maximum-deletion-characters 32
  "Maximum characters spoken from one observed deletion burst.")

(defconst emacsvox-eat--maximum-review-lines 40
  "Maximum retained terminal rows spoken by one explicit review command.")

(defconst emacsvox-eat--maximum-review-characters 4000
  "Maximum retained terminal characters spoken by one review command.")

(defun emacsvox-eat--remember-input-row-offset (&optional snapshot)
  "Remember the input start at the cursor in main-screen SNAPSHOT.
Do nothing when an input start is already known for the current prompt."
  (unless emacsvox-eat--input-row-offset
    (let* ((snapshot (or snapshot emacsvox-eat--screen-snapshot))
           (text (plist-get snapshot :text))
           (offset (plist-get snapshot :cursor-offset))
           (row (plist-get snapshot :cursor-row)))
      (when (and text
                 (integerp offset)
                 (integerp row)
                 (not (plist-get snapshot :alternate-screen)))
        (let ((starts (emacsvox-eat--row-start-offsets text)))
          (when (< -1 row (length starts))
            (setq emacsvox-eat--input-row-offset
                  (- offset (aref starts row))
                  emacsvox-eat--input-start-row row))))))
  emacsvox-eat--input-row-offset)

(defun emacsvox-eat--cancel-quiescence ()
  "Cancel and clear the pending EAT quiescence transaction."
  (when (timerp emacsvox-eat--quiescence-timer)
    (cancel-timer emacsvox-eat--quiescence-timer))
  (emacsvox-eat--clear-collected-output)
  (setq emacsvox-eat--quiescence-timer nil
        emacsvox-eat--pending-screen-baseline nil
        emacsvox-eat--pending-screen-diff nil
        emacsvox-eat--pending-alternate-screen-transitions nil
        emacsvox-eat--pending-follow-live-p nil
        emacsvox-eat--pending-automatic-p nil
        emacsvox-eat--pending-user-input-p nil
        emacsvox-eat--pending-navigation-intent nil
        emacsvox-eat--quiescence-started-at nil))

(defun emacsvox-eat--install-prompt-observer ()
  "Wrap the terminal's public parsed-UI callback once when one exists."
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    (let ((original (eat-term-parameter eat-terminal 'ui-command-function)))
      (when (and (functionp original)
                 (not (eq original #'emacsvox-eat--prompt-ui-command)))
        (setf (eat-term-parameter eat-terminal 'emacsvox-eat-original-ui-command) original
              (eat-term-parameter eat-terminal 'ui-command-function)
              #'emacsvox-eat--prompt-ui-command)))))

(defun emacsvox-eat--retain-screen-change (diff snapshot)
  "Retain terminal DIFF ending at SNAPSHOT for explicit review."
  (setq emacsvox-eat--last-screen-diff diff
        emacsvox-eat--last-changed-screen snapshot)
  (if-let* ((focus (plist-get diff :likely-focus)))
      (progn
        (unless
            (equal
             (plist-get focus :identity)
             emacsvox-eat--last-focus-presentation-identity)
          (setq emacsvox-eat--last-focus-presentation-identity nil))
        (setq emacsvox-eat--last-likely-focus focus))
    (when (or (plist-get diff :text-changed)
              (plist-get diff :style-changed)
              (plist-get diff :cursor-moved)
              (plist-get diff :size-changed)
              (plist-get diff :alternate-screen-changed)
              (plist-get diff :generation-changed))
      (setq emacsvox-eat--last-likely-focus nil
            emacsvox-eat--last-focus-presentation-identity nil)))
  (emacsvox-eat--retain-metadata-change diff snapshot)
  (cond
   ((plist-get diff :prompt-status-changed)
    (setq emacsvox-eat--last-status-text
          (emacsvox-eat--prompt-status-text
           (plist-get diff :new-prompt-status))))
   (t
    (when-let* ((status (emacsvox-eat--retained-status-row diff snapshot)))
      (setq emacsvox-eat--last-status-text status)))))

(defun emacsvox-eat--screen-quiesced (diff snapshot)
  "Retain and present the selected terminal DIFF ending at SNAPSHOT."
  (prog1
      (cond
       ((when-let* ((states
                     (emacsvox-eat--alternate-screen-transitions
                      diff snapshot)))
          (emacsvox-eat--cancel-completion)
          (emacsvox-eat--cancel-deletion)
          (setq emacsvox-eat--recent-input nil
                emacsvox-eat--last-status-text nil
                emacsvox-eat--last-status-spoken-at 0.0
                emacsvox-eat--last-completion-output nil
                emacsvox-eat--last-likely-focus nil
                emacsvox-eat--last-focus-presentation-identity nil)
          (emacsvox-eat--retain-screen-change diff snapshot)
          (when (and emacsvox-eat-autospeak
                     emacsvox-eat--automatic-feedback-allowed-p)
            (emacsvox-eat--present-alternate-screen-transitions states))
          t))
       ((when-let* ((deletion (plist-get diff :deletion)))
          (emacsvox-eat--retain-screen-change diff snapshot)
          (emacsvox-eat--present-observed-deletion deletion snapshot)
          t))
       ((when-let* ((completion
                     (emacsvox-eat--pending-inline-completion snapshot)))
          (emacsvox-eat--retain-screen-change
           (plist-get completion :diff) snapshot)
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--last-completion-output nil)
          (emacsvox-eat--present-inline-completion
           (plist-get completion :text))
          t))
       ((when-let* ((completion
                     (emacsvox-eat--pending-completion-output snapshot)))
          (setq completion
                (plist-put
                 completion :repeated
                 (emacsvox-eat--completion-repeated-p completion)))
          (emacsvox-eat--retain-screen-change
           (plist-get completion :diff) snapshot)
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--last-completion-output completion)
          (emacsvox-eat--present-completion-output completion)
          t))
       ((when-let* ((focus (plist-get diff :likely-focus)))
          (emacsvox-eat--retain-screen-change diff snapshot)
          (emacsvox-eat--present-likely-focus focus)
          t))
       ((emacsvox-eat--main-screen-navigation-text diff snapshot)
        (emacsvox-eat--retain-screen-change diff snapshot)
        (emacsvox-eat--present-main-screen-navigation diff snapshot)
        t)
       ((emacsvox-eat--completion-current-p)
        ;; Candidate/help output can pause on a completed row before the peer
        ;; redraws its input.  Retain that partial screen without letting the
        ;; ordinary output path announce it and then repeat it at completion.
        (emacsvox-eat--retain-screen-change diff snapshot)
        (emacsvox-eat--diagnose-output 'retained 'completion-pending))
       (t
        (emacsvox-eat--retain-screen-change diff snapshot)
        (cond
         ((not emacsvox-eat-autospeak)
          (emacsvox-eat--diagnose-output 'retained 'autospeak-off))
         ((not emacsvox-eat--automatic-feedback-allowed-p)
          (emacsvox-eat--diagnose-output 'retained 'burst-ineligible))
         ((eq emacsvox-eat-verbosity 'terse)
          (emacsvox-eat--diagnose-output 'retained 'terse)))
        (when (and emacsvox-eat-autospeak
                   emacsvox-eat--automatic-feedback-allowed-p
                   (not (eq emacsvox-eat-verbosity 'terse)))
          (cond
           ((and (plist-get diff :unfinished-output-only)
                 (not (plist-get diff :prompt-output))
                 (emacsvox-eat--status-row diff snapshot))
            (emacsvox-eat--diagnose-output 'presentation-selected 'status)
            (emacsvox-eat--present-status (emacsvox-eat--status-row diff snapshot)))
           ((plist-get diff :collected-output)
            (emacsvox-eat--diagnose-output 'presentation-selected 'collected-output)
            (emacsvox-eat--submit
             (plist-get diff :collected-output)
             (emacsvox-eat--facts 'command-output 'command-output-received)
             'continuous))
           ((and (not (plist-get diff :output-observed))
                 (emacsvox-eat--complete-output-rows diff snapshot))
            (emacsvox-eat--diagnose-output 'presentation-selected 'screen-output)
            (let ((rows (emacsvox-eat--complete-output-rows diff snapshot)))
              (emacsvox-eat--present-output-rows rows)))
           (t
            (if-let* (((not (plist-get diff :prompt-output)))
                      (status (emacsvox-eat--status-row diff snapshot)))
                (progn
                  (emacsvox-eat--diagnose-output 'presentation-selected 'status)
                  (emacsvox-eat--present-status status))
              (emacsvox-eat--diagnose-output 'retained 'no-ordinary-output)))))))
    (when (and emacsvox-eat-autospeak emacsvox-eat--automatic-feedback-allowed-p)
      (emacsvox-eat--present-metadata-change diff snapshot)
      (emacsvox-eat--present-prompt-status diff))))

(defun emacsvox-eat--finish-quiescence
    (buffer generation serial &optional terminal-exiting-p)
  "Finish BUFFER's update burst identified by GENERATION and SERIAL.
When TERMINAL-EXITING-P is non-nil, use the live-follow state recorded while
the terminal still existed instead of consulting its deleted cursor."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat--quiescence-timer
                 (= generation emacsvox-eat--generation)
                 (= serial emacsvox-eat--update-serial))
        (setq emacsvox-eat--quiescence-timer nil)
        (let* ((completed-output-lines emacsvox-eat--collected-output-lines)
               (prompt-output-p (not (null emacsvox-eat--prompt-ranges)))
               (_ (emacsvox-eat--collect-unfinished-output))
               (prompt emacsvox-eat--pending-prompt)
              (baseline emacsvox-eat--pending-screen-baseline)
              (diff emacsvox-eat--pending-screen-diff)
              (snapshot emacsvox-eat--screen-snapshot)
              (collected-output (emacsvox-eat--collected-output-text))
              (output-observed emacsvox-eat--output-observed-p)
              (navigation emacsvox-eat--pending-navigation-intent)
              (deletion emacsvox-eat--deletion-intent)
              (alternate-screen-transitions
               (nreverse emacsvox-eat--pending-alternate-screen-transitions))
              (emacsvox-eat--automatic-feedback-allowed-p
               emacsvox-eat--pending-automatic-p)
              (followed-live-p emacsvox-eat--pending-follow-live-p)
              (user-input-p emacsvox-eat--pending-user-input-p))
          (setq emacsvox-eat--pending-prompt nil
                emacsvox-eat--pending-screen-baseline nil
                emacsvox-eat--pending-screen-diff nil
                emacsvox-eat--pending-alternate-screen-transitions nil
                emacsvox-eat--pending-follow-live-p nil
                emacsvox-eat--pending-automatic-p nil
                emacsvox-eat--pending-user-input-p nil
                emacsvox-eat--pending-navigation-intent nil
                emacsvox-eat--quiescence-started-at nil)
          (emacsvox-eat--clear-collected-output)
          (when (and diff
                     (emacsvox-eat--foreground-p))
            (setq diff (plist-put diff :user-input user-input-p))
            (when prompt-output-p
              (setq diff (plist-put diff :prompt-output t)))
            (when (and output-observed (zerop completed-output-lines))
              (setq diff (plist-put diff :unfinished-output-only t)))
            (when output-observed
              (setq diff (plist-put diff :output-observed t)))
            (when collected-output
              (setq diff (plist-put diff :collected-output collected-output)))
            (when alternate-screen-transitions
              (setq diff
                    (plist-put
                     diff :alternate-screen-transitions
                     alternate-screen-transitions)))
            (when (and (emacsvox-eat--navigation-intent-current-p navigation)
                       (not (plist-get navigation :ambiguous)))
              (setq diff (plist-put diff :navigation navigation))
              (when-let* ((focus
                           (emacsvox-eat--likely-focus-change
                            baseline snapshot diff navigation)))
                (setq diff (plist-put diff :likely-focus focus))))
            (when (and (emacsvox-eat--deletion-intent-current-p deletion)
                       (plist-get deletion :transported))
              (setq diff (plist-put diff :deletion deletion)))
            (if (if terminal-exiting-p
                    followed-live-p
                  (emacsvox-eat--following-live-p))
                (progn
                  (emacsvox-eat--screen-quiesced diff snapshot)
                  (when (and prompt emacsvox-eat-autospeak
                             emacsvox-eat--automatic-feedback-allowed-p)
                    (emacsvox-eat--present-ready-prompt prompt)))
              (emacsvox-eat--retain-screen-change diff snapshot)
              (emacsvox-eat--diagnose-output 'retained 'reviewing-scrollback))))))))

(defun emacsvox-eat--flush-quiescence-before-exit ()
  "Finish eligible foreground output before EAT deletes its process state."
  (when emacsvox-eat--quiescence-timer
    (when (timerp emacsvox-eat--quiescence-timer)
      (cancel-timer emacsvox-eat--quiescence-timer))
    (emacsvox-eat--finish-quiescence
     (current-buffer) emacsvox-eat--generation
     emacsvox-eat--update-serial 'terminal-exiting)))

(defun emacsvox-eat--schedule-quiescence ()
  "Restart the timer for the current selected EAT update burst."
  (when (timerp emacsvox-eat--quiescence-timer)
    (cancel-timer emacsvox-eat--quiescence-timer))
  (let* ((elapsed
          (max 0.0
               (- (float-time)
                  (or emacsvox-eat--quiescence-started-at (float-time)))))
         (deadline-delay
          (max 0.0 (- emacsvox-eat--quiescence-maximum-delay elapsed)))
         (delay (min emacsvox-eat--quiescence-delay deadline-delay)))
    (setq emacsvox-eat--quiescence-timer
          (run-at-time
           delay nil #'emacsvox-eat--finish-quiescence
           (current-buffer) emacsvox-eat--generation
           emacsvox-eat--update-serial))))

(defun emacsvox-eat--observe-screen ()
  "Capture and aggregate the current EAT screen without producing speech."
  (when-let* ((new (emacsvox-eat--capture-screen)))
    (let ((old emacsvox-eat--screen-snapshot)
          (navigation (emacsvox-eat--current-navigation-intent)))
      (unless (emacsvox-eat--automatic-eligible-p)
        (emacsvox-eat--discard-automatic-feedback))
      (setq emacsvox-eat--recent-navigation-intent nil)
      (setq emacsvox-eat--update-serial
            (1+ emacsvox-eat--update-serial)
            emacsvox-eat--screen-snapshot new)
      (if (or (not (emacsvox-eat--foreground-p))
              (null old)
              (not
               (equal
                (plist-get old :generation)
                (plist-get new :generation))))
          (emacsvox-eat--cancel-quiescence)
        (if emacsvox-eat--pending-screen-baseline
            (setq emacsvox-eat--pending-follow-live-p
                  (and emacsvox-eat--pending-follow-live-p
                       (emacsvox-eat--following-live-p))
                  emacsvox-eat--pending-automatic-p
                  (and emacsvox-eat--pending-automatic-p
                       (emacsvox-eat--automatic-eligible-p)))
          (setq emacsvox-eat--pending-screen-baseline old
                emacsvox-eat--pending-automatic-p
                (emacsvox-eat--automatic-eligible-p)
                emacsvox-eat--pending-follow-live-p
                (emacsvox-eat--following-live-p)
                emacsvox-eat--quiescence-started-at (float-time)))
        (when (not (eq (plist-get old :alternate-screen)
                       (plist-get new :alternate-screen)))
          (push (not (null (plist-get new :alternate-screen)))
                emacsvox-eat--pending-alternate-screen-transitions)
          ;; Terminal completion and replaceable status state cannot span a
          ;; change to or from an application's independent screen.
          (emacsvox-eat--cancel-completion)
          (emacsvox-eat--cancel-deletion)
          (setq navigation nil
                emacsvox-eat--recent-input nil
                emacsvox-eat--recent-navigation-intent nil
                emacsvox-eat--pending-navigation-intent nil
                emacsvox-eat--input-row-offset nil
                emacsvox-eat--input-start-row nil
                emacsvox-eat--last-status-text nil
                emacsvox-eat--last-status-spoken-at 0.0
                emacsvox-eat--last-completion-output nil
                emacsvox-eat--last-likely-focus nil
                emacsvox-eat--last-focus-presentation-identity nil))
        (setq emacsvox-eat--pending-user-input-p
              (or emacsvox-eat--pending-user-input-p
                  emacsvox-eat--recent-input
                  navigation
                  (emacsvox-eat--current-deletion-intent)
                  emacsvox-eat--completion-snapshot))
        (when navigation
          (emacsvox-eat--merge-pending-navigation-intent navigation))
        (setq emacsvox-eat--pending-screen-diff
              (emacsvox-eat--screen-diff
               emacsvox-eat--pending-screen-baseline new))
        (if (and (plist-get emacsvox-eat--pending-screen-diff :unchanged)
                 (zerop emacsvox-eat--collected-output-lines)
                 (null emacsvox-eat--pending-prompt)
                 (null emacsvox-eat--pending-alternate-screen-transitions))
            (emacsvox-eat--cancel-quiescence)
          (emacsvox-eat--schedule-quiescence))))))

(defun emacsvox-eat--cancel-background-output-burst ()
  "Cancel the pending monitored background-output burst."
  (when (timerp emacsvox-eat--background-output-timer)
    (cancel-timer emacsvox-eat--background-output-timer))
  (setq emacsvox-eat--background-output-timer nil
        emacsvox-eat--background-output-started-at nil
        emacsvox-eat--background-output-pending-p nil))

(defun emacsvox-eat--clear-background-monitor-state ()
  "Forget pending and unread monitored background-output state."
  (emacsvox-eat--cancel-background-output-burst)
  (setq emacsvox-eat--unread-output-count 0
        emacsvox-eat--last-background-cue-at nil))

(defun emacsvox-eat--background-output-change-p (old new)
  "Return non-nil when OLD to NEW is monitorable terminal text output."
  (when (and old new)
    (let ((diff (emacsvox-eat--screen-diff old new)))
      (and (plist-get diff :comparable)
           (plist-get diff :text-changed)
           (not (plist-get diff :size-changed))))))

(defun emacsvox-eat--schedule-background-output-burst ()
  "Coalesce the current monitored background-output burst."
  (when (timerp emacsvox-eat--background-output-timer)
    (cancel-timer emacsvox-eat--background-output-timer))
  (let* ((now (float-time))
         (started-at
          (or emacsvox-eat--background-output-started-at now))
         (elapsed (max 0.0 (- now started-at)))
         (deadline-delay
          (max 0.0 (- emacsvox-eat--quiescence-maximum-delay elapsed)))
         (delay (min emacsvox-eat--quiescence-delay deadline-delay)))
    (setq emacsvox-eat--background-output-started-at started-at
          emacsvox-eat--background-output-pending-p t
          emacsvox-eat--background-output-serial
          (1+ emacsvox-eat--background-output-serial)
          emacsvox-eat--background-output-timer
          (run-at-time
           delay nil #'emacsvox-eat--finish-background-output-burst
           (current-buffer) emacsvox-eat--generation
           emacsvox-eat--background-output-serial))))

(defun emacsvox-eat--commit-background-output-burst ()
  "Commit one pending background-output burst to the unread count."
  (when emacsvox-eat--background-output-pending-p
    (emacsvox-eat--cancel-background-output-burst)
    (setq emacsvox-eat--unread-output-count
          (min most-positive-fixnum
               (1+ emacsvox-eat--unread-output-count)))
    t))

(defun emacsvox-eat--finish-background-output-burst
    (buffer generation serial)
  "Finish BUFFER's monitored background burst GENERATION and SERIAL."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat-monitor-background-output
                 emacsvox-eat--background-output-timer
                 emacsvox-eat--background-output-pending-p
                 (= generation emacsvox-eat--generation)
                 (= serial emacsvox-eat--background-output-serial))
        (emacsvox-eat--commit-background-output-burst)
        (if (emacsvox-eat--selected-buffer-p)
            (emacsvox-eat--present-unread-output-count)
          (emacsvox-eat--cue-background-output))))))

(defun emacsvox-eat--window-selection-changed (window)
  "Report unread terminal output when WINDOW selects this EAT buffer."
  (if (and (window-live-p window)
           (eq window (selected-window))
           (emacsvox-eat--selected-buffer-p))
      (progn
        (emacsvox-eat--commit-background-output-burst)
        (emacsvox-eat--present-unread-output-count))
    ;; A deletion result belongs only to the terminal selection in which its
    ;; key was delivered.
    (emacsvox-eat--cancel-deletion)))

(defun emacsvox-eat--clear-sensitive-screen-state ()
  "Forget content-bearing EAT observation state in the current buffer."
  (emacsvox-eat--discard-automatic-feedback)
  (emacsvox-eat--clear-prompt-state)
  (emacsvox-eat--kill-review-buffer)
  (emacsvox-eat--clear-background-monitor-state)
  (emacsvox-eat--cancel-quiescence)
  (emacsvox-eat--cancel-completion)
  (emacsvox-eat--cancel-deletion)
  (setq emacsvox-eat--screen-snapshot nil
        emacsvox-eat--recent-input nil
        emacsvox-eat--recent-navigation-intent nil
        emacsvox-eat--pending-navigation-intent nil
        emacsvox-eat--input-row-offset nil
        emacsvox-eat--input-start-row nil
        emacsvox-eat--last-screen-diff nil
        emacsvox-eat--last-changed-screen nil
        emacsvox-eat--last-likely-focus nil
        emacsvox-eat--last-focus-presentation-identity nil
        emacsvox-eat--last-status-text nil
        emacsvox-eat--last-status-spoken-at 0.0
        emacsvox-eat--last-completion-output nil
        emacsvox-eat--last-metadata-change nil
        emacsvox-eat--last-metadata-spoken-at nil))

(defun emacsvox-eat--clear-transient-state ()
  "Clear asynchronous EAT interaction state in the current buffer."
  (emacsvox-eat--clear-sensitive-screen-state)
  (setq emacsvox-eat--secure-input-active-p nil
        emacsvox-eat--visual-command-origin-p nil
        emacsvox-eat--last-bell-at nil
        emacsvox-eat--last-bell-spoken-at nil))

(defun emacsvox-eat--advance-generation ()
  "Invalidate asynchronous state and advance the current EAT generation."
  (emacsvox-eat--clear-transient-state)
  (setq emacsvox-eat--generation (1+ emacsvox-eat--generation))
  emacsvox-eat--generation)

(defun emacsvox-eat--install-bell-observer ()
  "Wrap the current terminal's public bell callback exactly once."
  (emacsvox-eat--install-prompt-observer)
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    (let ((current
           (eat-term-parameter eat-terminal 'ring-bell-function)))
      (unless (eq current #'emacsvox-eat--ring-bell)
        (setf
         (eat-term-parameter
          eat-terminal 'emacsvox-eat-original-ring-bell-function)
         current)
        (setf
         (eat-term-parameter eat-terminal 'emacsvox-eat-buffer)
         (current-buffer))
        (setf (eat-term-parameter eat-terminal 'ring-bell-function)
              #'emacsvox-eat--ring-bell)))))

(defun emacsvox-eat--eshell-visual-command-p ()
  "Return non-nil in a normal EAT buffer launched for an Eshell visual command."
  (and (boundp 'eshell-parent-buffer)
       (buffer-live-p eshell-parent-buffer)))

(defun emacsvox-eat--process-started (process &optional quiet-start-p)
  "Start a new EAT generation for PROCESS."
  (let ((restart-p (> emacsvox-eat--generation 0))
        (visual-command-p (emacsvox-eat--eshell-visual-command-p)))
    (emacsvox-eat--advance-generation)
    (setq emacsvox-eat--active-process process
          emacsvox-eat--visual-command-origin-p visual-command-p
          emacsvox-eat--last-exited-process nil)
    (emacsvox-eat--install-bell-observer)
    ;; EAT creates and redisplays the terminal before its exec hook.  Retain
    ;; that empty public screen so even a command's first output is diffable.
    (setq emacsvox-eat--screen-snapshot (emacsvox-eat--capture-screen))
    ;; Initial creation already has the `eat' opening announcement.  A later
    ;; exec in the same terminal needs its own lifecycle boundary.
    (when (and (not quiet-start-p) emacsvox-eat-autospeak
               (emacsvox-eat--foreground-p))
      (cond
       (visual-command-p
        (emacsvox-eat--submit
         "Eshell visual command started"
         (emacsvox-eat--facts 'command-interaction 'operation-started)
         'state-change 'open-object))
       (restart-p
        (emacsvox-eat--submit
         "Terminal process restarted"
         (emacsvox-eat--facts 'command-interaction 'operation-started)
         'state-change 'open-object))))))

(defun emacsvox-eat--process-exited (process)
  "End the EAT generation belonging to PROCESS.
Ignore a stale or duplicate exit after another process has become active."
  (when
      (and
       (not (eq process emacsvox-eat--last-exited-process))
       (or
        (null emacsvox-eat--active-process)
        (eq process emacsvox-eat--active-process)))
    (let ((visual-command-p emacsvox-eat--visual-command-origin-p))
      ;; EAT drains and redisplays final process output before deleting the
      ;; terminal and running this hook.  Finish a burst observed at the live
      ;; cursor before generation invalidation cancels it.
      (emacsvox-eat--flush-quiescence-before-exit)
      (emacsvox-eat--advance-generation)
      (setq emacsvox-eat--active-process nil
            emacsvox-eat--last-exited-process process)
      (when (and emacsvox-eat-autospeak (emacsvox-eat--foreground-p))
        (let* ((status (process-status process))
               (exit-status
                (and
                 (memq status '(exit signal))
                 (process-exit-status process)))
               (normal-p
                (or
                 (eq status 'closed)
                 (and
                  (eq status 'exit)
                  (integerp exit-status)
                  (zerop exit-status))))
               (subject
                (if visual-command-p
                    "Eshell visual command"
                  "Terminal process"))
               (content
                (cond
                 (normal-p (concat subject " exited"))
                 ((eq status 'signal)
                  (if (integerp exit-status)
                      (format "%s ended by signal %d" subject exit-status)
                    (concat subject " ended by signal")))
                 ((integerp exit-status)
                  (format "%s exited with status %d" subject exit-status))
                 (t (concat subject " ended")))))
          (emacsvox-eat--submit
           content
           (emacsvox-eat--facts
            'command-interaction 'command-process-exited 'process-exit
            (when (integerp exit-status)
              (list :command-exit-status exit-status)))
           'notification
           (if normal-p 'close-object 'warn-user)))))))

(defun emacsvox-eat--eshell-process-started ()
  "Initialize observation for EAT's terminal embedded in Eshell."
  (emacsvox-eat--setup-buffer-state)
  (setq emacsvox-eat--eshell-output-owned-p t)
  (if-let* ((process (get-buffer-process (current-buffer))))
      (progn
        ;; Every external Eshell command is a new process, not a restart of
        ;; the Eshell session, so command start remains quiet.
        (emacsvox-eat--process-started process 'quiet))
    ;; EAT normally associates the process with the Eshell buffer before this
    ;; hook.  If that invariant changes, invalidate stale content and let the
    ;; first update establish a baseline without inventing process identity.
    (emacsvox-eat--advance-generation)))

(defun emacsvox-eat--eshell-process-exited ()
  "Finish observation for EAT's terminal embedded in Eshell."
  (if emacsvox-eat--active-process
      (emacsvox-eat--process-exited emacsvox-eat--active-process)
    (emacsvox-eat--advance-generation)))

(defun emacsvox-eat--eshell-prompt-ready ()
  "Release EAT's output ownership after Eshell publishes its next prompt."
  (when (local-variable-p 'emacsvox-eat--eshell-output-owned-p)
    (setq emacsvox-eat--eshell-output-owned-p nil)))

(defun emacsvox-eat--invalidate-all-buffer-state ()
  "Advance the generation of every initialized EAT speech buffer."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (local-variable-p 'emacsvox-eat--generation)
          (emacsvox-eat--advance-generation))))))

(defun emacsvox--advice-eat-reset-before (&rest _)
  "Invalidate pending EAT speech state before resetting the terminal."
  (emacsvox-eat--advance-generation))

(defun emacsvox--advice-eat-reload-before (&rest _)
  "Invalidate pending speech state in every EAT buffer before reload."
  (emacsvox-eat--invalidate-all-buffer-state))

;;;  Map Faces:

(voice-setup-add-map
 '(
   (eat-shell-prompt-annotation-failure voice-lighten)
   (eat-shell-prompt-annotation-running voice-monotone)
   (eat-shell-prompt-annotation-success voice-animate)
   (eat-term-bold voice-bolden)
   (eat-term-italic voice-smoothen)))
;;; Eat Setup:

(defun emacsvox-eat--terminal-buffer-p ()
  "Return non-nil for a normal or active Eshell-embedded EAT terminal."
  (or (derived-mode-p 'eat-mode)
      (and (derived-mode-p 'eshell-mode)
           eat-terminal
           (eat-term-live-p eat-terminal))))

(defun emacsvox-eat--setup-buffer-state ()
  "Initialize shared Emacsvox state for the current EAT terminal buffer."
  (unless (local-variable-p 'emacsvox-eat--generation)
    (setq-local emacsvox-eat--generation 0
                emacsvox-eat--active-process
                (get-buffer-process (current-buffer))
                emacsvox-eat--last-exited-process nil))
  (add-hook 'window-selection-change-functions
            #'emacsvox-eat--window-selection-changed nil t)
  (add-hook 'post-command-hook #'emacsvox-eat--check-foreground nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-eat--kill-review-buffer nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-eat--kill-review-buffer nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-eat--clear-transient-state nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-eat--clear-transient-state nil t)
  (emacsvox-eat--install-bell-observer)
  (cl-loop
   for map-symbol in
   '(eat-line-mode-map eat-semi-char-mode-map eat-mode-map eat-char-mode-map
     eat-eshell-emacs-mode-map eat-eshell-semi-char-mode-map
     eat-eshell-char-mode-map)
   for map = (and (boundp map-symbol) (symbol-value map-symbol))
   do
   (when (keymapp map) (define-key map emacsvox-prefix 'emacsvox-keymap))))

(defun emacsvox-eat-mode-setup ()
  "Placed on eat-mode-hook to do Emacsvox setup."
  (setq-local emacsvox-aural-module 'eat)
  (emacsvox-eat--setup-buffer-state))

(add-hook 'eat-mode-hook 'emacsvox-eat-mode-setup)

(defun emacsvox-eat--control-buffer ()
  "Return the EAT source controlled by the current terminal or review buffer."
  (cond
   ((emacsvox-eat--terminal-buffer-p) (current-buffer))
   ((derived-mode-p 'emacsvox-eat-review-mode)
    (if (and (buffer-live-p emacsvox-eat-review--source-buffer)
             (with-current-buffer emacsvox-eat-review--source-buffer
               (emacsvox-eat--terminal-buffer-p)))
        emacsvox-eat-review--source-buffer
      (user-error "The source EAT terminal is no longer available")))
   (t (user-error "This is not an EAT terminal or frozen review buffer"))))

(defun emacsvox-eat-toggle-autospeak (&optional argument)
  "Toggle automatic foreground feedback for this EAT terminal.
With positive prefix ARGUMENT enable it; with zero or negative prefix disable
it.  Speech already sent may finish.  Explicit reading and input feedback
remain available.  This also works from the terminal's frozen review buffer."
  (interactive "P")
  (let ((terminal (emacsvox-eat--control-buffer)) enabled)
    (with-current-buffer terminal
      (emacsvox-eat--discard-automatic-feedback)
      (setq-local emacsvox-eat-autospeak
                  (if argument (> (prefix-numeric-value argument) 0)
                    (not emacsvox-eat-autospeak)))
      (setq enabled emacsvox-eat-autospeak))
    (emacsvox-eat--submit
     (format "Terminal automatic feedback %s" (if enabled "enabled" "disabled"))
     (emacsvox-eat--facts 'command-interaction 'state-changed)
     'state-change 'button)
    enabled))

(defun emacsvox-eat-toggle-background-monitoring (&optional argument)
  "Toggle content-free background-output monitoring for this EAT terminal.
With positive prefix ARGUMENT, enable monitoring; with zero or a negative
prefix, disable it.  The command also works from its frozen review buffer."
  (interactive "P")
  (let ((terminal (emacsvox-eat--control-buffer))
        enabled-p)
    (with-current-buffer terminal
      (setq enabled-p
            (if argument
                (> (prefix-numeric-value argument) 0)
              (not emacsvox-eat-monitor-background-output)))
      (emacsvox-eat--clear-background-monitor-state)
      (setq-local emacsvox-eat-monitor-background-output enabled-p))
    (emacsvox-eat--submit
     (format "Background terminal monitoring %s"
             (if enabled-p "enabled" "disabled"))
     (emacsvox-eat--facts 'command-interaction 'state-changed)
     'state-change 'button)
    enabled-p))

(defun emacsvox-eat--verbosity-description (verbosity)
  "Return a concise human description of terminal VERBOSITY."
  (pcase verbosity
    ('terse
     "Terminal verbosity terse; routine output is retained for review")
    ('verbose
     (concat
      "Terminal verbosity verbose; bounded output, status, title, and "
      "directory changes are spoken"))
    (_ "Terminal verbosity normal; bounded output and status are spoken")))

(defun emacsvox-eat-cycle-verbosity ()
  "Cycle terse, normal, and verbose policy for this EAT terminal.
The command also works from the terminal's frozen review buffer."
  (interactive)
  (let ((terminal (emacsvox-eat--control-buffer))
        verbosity)
    (with-current-buffer terminal
      (setq-local
       emacsvox-eat-verbosity
       (pcase emacsvox-eat-verbosity
         ('terse 'normal)
         ('normal 'verbose)
         (_ 'terse)))
      (setq verbosity emacsvox-eat-verbosity))
    (emacsvox-eat--submit
     (emacsvox-eat--verbosity-description verbosity)
     (emacsvox-eat--facts 'command-interaction 'state-changed)
     'state-change 'button)
    verbosity))

(defun emacsvox-eat--selected-buffer-p ()
  "Return non-nil when the current EAT buffer is selected."
  (eq (current-buffer) (window-buffer (selected-window))))

(defun emacsvox-eat--foreground-p ()
  "Return non-nil when this terminal owns detectable keyboard focus.
On displays reporting unknown focus, selected-window ownership suffices."
  (and (emacsvox-eat--selected-buffer-p)
       (not (active-minibuffer-window))
       (or (not (display-graphic-p))
           (not (null (frame-focus-state (selected-frame)))))))

(defun emacsvox-eat--automatic-eligible-p ()
  "Return non-nil when new automatic terminal feedback is eligible."
  (and emacsvox-eat-autospeak
       (emacsvox-eat--foreground-p)
       (emacsvox-eat--following-live-p)))

(defun emacsvox-eat--discard-automatic-feedback ()
  "Discard only this terminal's locally pending automatic feedback.
Ordered output has already been sent.  Never stop a shared speech process."
  (when (or emacsvox-eat--pending-automatic-p emacsvox-eat--pending-prompt
            emacsvox-eat--collected-output emacsvox-eat--unfinished-output)
    (emacsvox-eat--diagnose-output 'discarded 'automatic-feedback-boundary))
  (setq emacsvox-eat--pending-automatic-p nil
        emacsvox-eat--pending-prompt nil
        emacsvox-eat--prompt-eligible-p nil)
  (emacsvox-eat--clear-output-frontier)
  (when emacsvox-eat--terminal-id
    (dolist (owner (list tts-speaker-process tts-notify-process))
      (when owner
        (dolist (kind '(status metadata))
          (emacsvox-aural-cancel-pending-deliveries
           owner (emacsvox-eat--terminal-delivery-key kind)))))))

(defun emacsvox-eat--check-foreground ()
  "Discard automatic feedback when this terminal loses eligibility."
  (unless (emacsvox-eat--automatic-eligible-p)
    (emacsvox-eat--discard-automatic-feedback)))

(defun emacsvox-eat--foreground-context-changed (&rest _)
  "Recheck initialized terminals after window, minibuffer, or frame changes."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (local-variable-p 'emacsvox-eat--generation)
        (emacsvox-eat--check-foreground)))))

(add-hook 'window-selection-change-functions
          #'emacsvox-eat--foreground-context-changed)
(add-hook 'minibuffer-setup-hook #'emacsvox-eat--foreground-context-changed)
(add-function :after after-focus-change-function
              #'emacsvox-eat--foreground-context-changed)

(defun emacsvox-eat--following-live-p ()
  "Return non-nil when the selected EAT window follows its live cursor.
Editable line-mode input after the terminal extent also counts as live.
EAT exposes its line-mode state through the minor-mode variable."
  (and (emacsvox-eat--selected-buffer-p)
       (eat-term-live-p eat-terminal)
       (or (= (eat-term-display-cursor eat-terminal)
              (window-point (selected-window)))
           (and (bound-and-true-p eat--line-mode)
                (>= (window-point (selected-window))
                    (eat-term-end eat-terminal))))))

;;; Speech-Enable Terminal Emulation:

(defun emacsvox-eat-update-hook ()
  "Speak an EAT update when its buffer is selected."
  (emacsvox-eat--install-bell-observer)
  (if emacsvox-eat--secure-input-active-p
      (emacsvox-eat--clear-sensitive-screen-state)
    (let ((selected-p (emacsvox-eat--selected-buffer-p))
          (old emacsvox-eat--screen-snapshot))
      (when (and selected-p emacsvox-eat-monitor-background-output)
        (emacsvox-eat--commit-background-output-burst)
        (emacsvox-eat--present-unread-output-count))
      (emacsvox-eat--observe-screen)
      (if (not selected-p)
          (progn
            (emacsvox-eat--cancel-completion)
            (emacsvox-eat--cancel-deletion)
            (setq emacsvox-eat--recent-input nil)
            (when (and emacsvox-eat-monitor-background-output
                       (emacsvox-eat--background-output-change-p
                        old emacsvox-eat--screen-snapshot))
              (emacsvox-eat--schedule-background-output-burst)))
        (let* ((emacsvox-show-point t)
               (cursor (eat-term-display-cursor eat-terminal)))
          (emacsvox-eat--speak-input-correlated-update cursor))))))

(provide 'emacsvox-eat-core)

;;; emacsvox-eat-core.el ends here
