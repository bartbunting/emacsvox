;;; emacsvox-agent-shell-interaction.el --- Agent Shell interaction feedback  -*- lexical-binding: t; -*-

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

;; Handle questions, session settings, steering, push, queue and compose
;; outcomes. Keep callback generations and interaction snapshots with cleanup.
;; The facade owns advice installation and activation; event subscriptions call
;; these helpers.
;; Load through `emacsvox-agent-shell'. Loading definitions installs no advice
;; or buffer hooks.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-events)

(declare-function emacsvox-agent-shell--speech-level-at-least-p
                  "emacsvox-agent-shell-presentation" (level &optional buffer))
(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell-presentation" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--deliver-announcement
                  "emacsvox-agent-shell-presentation" (facts occasion icon text &optional delivery-policy))
(declare-function emacsvox-agent-shell--session-buffer
                  "emacsvox-agent-shell-presentation" (&optional buffer))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell-presentation" (text facts occasion &optional icon delivery-policy replacement-key))
(declare-function agent-shell-elicitation--preview-open-p "agent-shell-elicitation" (elicitation key value))
(declare-function agent-shell-elicitation--option-preview-at "agent-shell-elicitation" (elicitation key value))
(defvar agent-shell--state)

(declare-function emacsvox-agent-shell--header-state
                  "emacsvox-agent-shell-presentation" (&optional buffer))
(declare-function emacsvox-agent-shell--notify-event
                  "emacsvox-agent-shell-presentation" (text facts &optional icon occasion))
(defvar emacsvox-agent-shell-signal-processing)
(defvar emacsvox-agent-shell-processing-start-icon)
(declare-function agent-shell-status "agent-shell" t)
(declare-function agent-shell-initialized-p "agent-shell" t)
(declare-function agent-shell-config-options "agent-shell" t)
(declare-function agent-shell--config-options "agent-shell" (state))
(declare-function shell-maker-busy "shell-maker" ())
(declare-function emacsvox-agent-shell--begin-response-turn
                  "emacsvox-agent-shell-events" ())
(declare-function emacsvox-agent-shell-lifecycle-facts
                  "emacsvox-agent-shell-events" (event))
(declare-function emacsvox-agent-shell--handle-lifecycle-event
                  "emacsvox-agent-shell-events" (event))
(defvar emacsvox-agent-shell--tool-call-status-cache)
(defvar emacsvox-agent-shell--tool-output-cache)
(defvar emacsvox-agent-shell--permission-detail-cache)
(defvar agent-shell-viewport-dismiss-on-send)

;;; Question forms

(defvar emacsvox-agent-shell--question-command-active nil
  "Non-nil while an interactive question action owns its feedback.")

(defun emacsvox-agent-shell--question-at-point ()
  "Return the question control, form and field at point, or nil.
Resolve form values in the owning shell, including from a viewport."
  (when-let* ((control (get-text-property (point) 'agent-shell-elicitation-control))
              (shell (emacsvox-agent-shell--session-buffer))
              (form (map-nested-elt (buffer-local-value 'agent-shell--state shell)
                                    (list :elicitations (map-elt control :id)))))
    (list control form
          (seq-find (lambda (field)
                      (equal (map-elt field :key) (map-elt control :key)))
                    (map-elt form :fields)))))

(defun emacsvox-agent-shell--question-presentation (control form field)
  "Return speech and semantic facts for CONTROL in FORM and FIELD."
  (let* ((action (map-elt control :action))
         (key (map-elt control :key))
         (value (map-elt control :value))
         (current (map-nested-elt form (list :values key)))
         (option (seq-find (lambda (option) (equal value (map-elt option :value)))
                           (map-elt field :options)))
         (label (or (map-elt field :title) key "Question"))
         (requirement (if (map-elt field :required) 'required 'optional))
         (preview (map-elt option :preview))
         (opened (and preview (agent-shell-elicitation--preview-open-p form key value)))
         (selection
          (pcase action
            ('select (if (equal value current) 'selected 'unselected))
            ('toggle (if (if value (member value current) (eq current t))
                         'checked 'unchecked))
            ((or 'read 'custom) (if (and current (not (equal current "")))
                                   'filled 'empty))))
         (speech
          (pcase action
            ('submit "Submit answers. Press Return to submit.")
            ('decline "Decline question. Press Return to decline.")
            ('preview (format "%s preview, %s. Press Return to %s."
                              (or (map-elt option :title) value label)
                              (if opened "expanded" "collapsed")
                              (if opened "close" "open")))
            (_ (format "%s, %s. %s. %s%s"
                       label requirement
                       (pcase action
                         ((or 'select 'toggle)
                          (format "%s, %s" (or (map-elt option :title) value label) selection))
                         ('custom (format "Your own answer, %s"
                                          (if (eq selection 'empty) "empty" current)))
                         (_ (format "%s" (if (eq selection 'empty) "empty" current))))
                       (pcase action
                         ('select "Press Return to select.")
                         ('toggle "Press Return to toggle.")
                         (_ "Press Return to edit."))
                       (if preview
                           (format " Preview %s; question mark to %s."
                                   (if opened "expanded" "collapsed")
                                   (if opened "close" "open")) ""))))))
    (list speech
          (emacsvox-agent-shell--presentation-facts
           'agent-question 'focus-entered nil
           (append (list :agent-question-control action)
                   (when key (list :agent-question-field key
                                   :agent-question-requirement requirement))
                   (when selection (list :agent-question-selection selection)))))))

(defun emacsvox-agent-shell--question-feedback (&optional occasion)
  "Speak the question control at point for OCCASION, returning non-nil."
  (when-let* ((data (emacsvox-agent-shell--question-at-point))
              (presentation (apply #'emacsvox-agent-shell--question-presentation data)))
    (let ((facts (cadr presentation)))
      (when (eq occasion 'state-change)
        (setq facts (plist-put facts :events '(agent-question-changed))))
      (emacsvox-agent-shell--submit-text-feedback
       (car presentation) facts (or occasion 'navigation) 'item))
    t))

(defun emacsvox-agent-shell--question-navigation-after (result &rest _)
  "Speak successful explicit question navigation RESULT once."
  (when (and result
             (or (ems-interactive-p 'agent-shell-elicitation-next-field)
                 (ems-interactive-p 'agent-shell-elicitation-previous-field)
                 (ems-interactive-p 'agent-shell-elicitation-jump-to-latest-form)))
    (unless (emacsvox-agent-shell--question-feedback)
      (emacsvox-agent-shell--submit-text-feedback
       (ems--this-line) '(:role agent-question) 'navigation 'item)))
  result)

(defun emacsvox-agent-shell--question-action-around (original &rest arguments)
  "Run ORIGINAL with ARGUMENTS and speak its confirmed question change."
  (if (not (or (ems-interactive-p 'agent-shell-elicitation-act)
               (ems-interactive-p 'agent-shell-elicitation-toggle-preview)
               (ems-interactive-p 'agent-shell-elicitation-interrupt)))
      (apply original arguments)
    (let* ((emacsvox-agent-shell--question-command-active t)
           (before (emacsvox-agent-shell--question-at-point))
           (control (car before))
           (action (map-elt control :action))
           (preview-command (eq this-command 'agent-shell-elicitation-toggle-preview))
           (ems--message-filter
            (concat "\\(?:" ems--message-filter "\\|\\`\\(?:Answer sent\\|Declined\\)\\'\\)")))
      (prog1 (apply original arguments)
        (when-let* ((after (emacsvox-agent-shell--question-at-point))
                    ((eq (map-elt (cadr after) :status) 'pending)))
          (emacsvox-agent-shell--question-feedback 'state-change)
          (when (or preview-command (eq action 'preview))
            (let* ((form (cadr after))
                   (key (map-elt control :key))
                   (value (map-elt control :value))
                   (preview (agent-shell-elicitation--option-preview-at form key value)))
              (when (and preview (agent-shell-elicitation--preview-open-p form key value))
                (emacsvox-agent-shell--submit-text-feedback
                 preview '(:role agent-question) 'inspection)))))))))

(defun emacsvox-agent-shell--question-event (event)
  "Present question EVENT with session speech policy and semantic facts."
  (let* ((data (map-elt event :data))
         (request (eq (map-elt event :event) 'elicitation-request))
         (form (map-nested-elt agent-shell--state
                              (list :elicitations (map-elt data :request-id))))
         (action (map-elt data :action))
         (facts (emacsvox-agent-shell--presentation-facts
                 'agent-question
                 (if request 'agent-question-requested 'agent-question-resolved)
                 nil (list :agent-question-state
                           (if request 'pending
                             (pcase action ('accept 'answered) ('decline 'declined) (_ 'cancelled))))))
         (text (if request
                   (format "Answer needed. %s. %d fields. Use Tab to move through answers and Return to choose or edit."
                           (or (map-elt data :message)
                               (map-elt (car (map-elt form :fields)) :title)
                               "Agent question")
                           (length (seq-remove (lambda (field) (map-elt field :folded-into))
                                               (map-elt form :fields))))
                 (pcase action
                   ('accept "Answers sent.")
                   ('decline "Question declined.")
                   (_ "Question cancelled.")))))
    (cond
     (emacsvox-agent-shell--question-command-active
      (emacsvox-agent-shell--submit-text-feedback text facts 'state-change 'select-object))
     ((emacsvox-agent-shell--speech-level-at-least-p 'notify)
      (emacsvox-agent-shell--deliver-announcement
       facts 'notification (if request 'warn-user 'select-object) text
       (when request 'urgent))))))

(defvar-local emacsvox-agent-shell--config-option-cache nil
  "Last observed values of session configuration options.")

(defvar-local emacsvox-agent-shell--callback-generation 0
  "Generation invalidating asynchronous callbacks on cleanup or session change.")

(defvar-local emacsvox-agent-shell--push-active-p nil
  "Non-nil while collecting an accepted server-pushed turn.")

(defvar emacsvox-agent-shell--queue-start-count nil
  "Number of pending prompts before the current queue submission, or nil.")

(defvar emacsvox-agent-shell--setting-command-active nil
  "Non-nil while an interactive model or mode command makes its request.")

(defvar emacsvox-agent-shell--setting-callback-active nil
  "Non-nil when the config option adapter owns a success announcement.")

(defun emacsvox-agent-shell--callback-current-p (buffer generation)
  "Return non-nil if BUFFER still owns a callback from GENERATION."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (and (derived-mode-p 'agent-shell-mode)
              (= generation emacsvox-agent-shell--callback-generation)))))

(defun emacsvox-agent-shell--interaction-cleanup ()
  "Invalidate asynchronous work and clear session interaction snapshots."
  (cl-incf emacsvox-agent-shell--callback-generation)
  (setq emacsvox-agent-shell--push-active-p nil
        emacsvox-agent-shell--tool-call-status-cache nil
        emacsvox-agent-shell--tool-output-cache nil
        emacsvox-agent-shell--permission-detail-cache nil
        emacsvox-agent-shell--config-option-cache nil))

(defun emacsvox-agent-shell--initialized-p ()
  "Return non-nil when the owning shell has finished initialization.
Use the public readiness API on 0.86.1 and the pipeline flags on 0.85.3."
  (if (fboundp 'agent-shell-initialized-p)
      (agent-shell-initialized-p)
    (and (map-elt agent-shell--state :initialized)
         (map-nested-elt agent-shell--state '(:session :id))
         (or (not (map-elt agent-shell--state :needs-authentication))
             (map-elt agent-shell--state :authenticated))
         (cl-every
          (lambda (pair)
            (let ((default (map-nested-elt agent-shell--state
                                           (list :agent-config (car pair)))))
              (or (not default) (not (funcall default))
                  (map-elt agent-shell--state (cdr pair)))))
          '((:default-model-id . :set-model)
            (:default-session-mode-id . :set-session-mode)
            (:default-config-options . :set-config-options))))))

(defun emacsvox-agent-shell--config-options ()
  "Read normalized config options, preferring the public API when ready."
  (when (boundp 'agent-shell--state)
    (if (fboundp 'agent-shell-config-options)
        (when (and (derived-mode-p 'agent-shell-mode)
                   (emacsvox-agent-shell--initialized-p))
          (agent-shell-config-options))
      (agent-shell--config-options agent-shell--state))))

(defun emacsvox-agent-shell--observe-config-options (options announce)
  "Remember OPTIONS and, when ANNOUNCE is non-nil, speak changed values.
Newly advertised options establish a baseline; they are not value changes."
  (unless (hash-table-p emacsvox-agent-shell--config-option-cache)
    (setq emacsvox-agent-shell--config-option-cache
          (make-hash-table :test #'equal)))
  (dolist (option options)
    (let* ((id (map-elt option :id))
           (value (map-elt option :current-value))
           (missing (make-symbol "missing"))
           (previous (gethash id emacsvox-agent-shell--config-option-cache missing)))
      (puthash id (copy-tree value) emacsvox-agent-shell--config-option-cache)
      (when (and announce id (not (eq previous missing))
                 (not (equal previous value)))
        (let ((name (or (map-elt option :name) id))
              (label (or (and (fboundp 'agent-shell--config-option-value-choices)
                              (car (seq-find
                                    (lambda (choice)
                                      (equal value (map-elt (cdr choice) :value)))
                                    (agent-shell--config-option-value-choices option))))
                         (and (fboundp 'agent-shell--config-option-value-name)
                              (agent-shell--config-option-value-name option value))
                         (format "%s" value))))
          (emacsvox-agent-shell--notify-event
           (format "%s: %s." name label)
           (emacsvox-agent-shell--presentation-facts
            'agent-session 'agent-setting-changed nil
            (list :agent-setting-id (format "%s" id)
                  :agent-setting-value (format "%s" value)))
           'select-object 'state-change))))))

(defun emacsvox-agent-shell--steering-feedback (outcome &optional detail)
  "Announce the confirmed steering OUTCOME and optional error DETAIL."
  (let* ((result (pcase outcome
                   ("injected" 'accepted)
                   ("startedNewTurn" 'detached)
                   ("submitted" 'submitted)
                   (_ 'declined)))
         (text (pcase result
                 ('accepted "Steering accepted.")
                 ('detached "Steered prompt started a separate turn. Still in progress.")
                 ('submitted "Steered prompt submitted as a new turn.")
                 (_ (if (and (stringp detail) (not (string-empty-p detail)))
                        (format "Steering declined: %s. Stopping the running turn." detail)
                      "Steering declined. Stopping the running turn.")))))
    (emacsvox-agent-shell--notify-event
     text
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-steering-resolved nil
      (list :agent-steering-result result))
     (if (memq result '(declined detached)) 'warn-user 'select-object))))

(defun emacsvox-agent-shell--send-request-around (original &rest arguments)
  "Adapt missing steering and config-success events around ORIGINAL.
Only structured request methods establish authority.  Preserve the original
callbacks, arguments, return values, and transport behavior."
  (let* ((method (map-nested-elt (plist-get arguments :request) '(:method)))
         (steering (equal method "_session/steering"))
         (setting (equal method "session/set_config_option"))
         (buffer (map-elt (plist-get arguments :state) :buffer)))
    (if (not (and (or steering setting) (buffer-live-p buffer)))
        (apply original arguments)
      (let* ((generation (buffer-local-value 'emacsvox-agent-shell--callback-generation buffer))
             (success (plist-get arguments :on-success))
             (failure (plist-get arguments :on-failure))
             (setting-message-regexp
              (when setting
                (concat "\\`"
                        (regexp-opt
                         (append '("Model" "Session mode" "Thought level")
                                 (with-current-buffer buffer
                                   (seq-keep (lambda (option)
                                               (let ((name (map-elt option :name)))
                                                 (and (stringp name) name)))
                                             (emacsvox-agent-shell--config-options)))))
                        ": ")))
             (announce-setting
              (with-current-buffer buffer
                (emacsvox-agent-shell--initialized-p))))
        (when setting
          (with-current-buffer buffer
            (emacsvox-agent-shell--observe-config-options
             (emacsvox-agent-shell--config-options) nil)))
        (setq arguments (copy-sequence arguments))
        (setq arguments
              (plist-put
               arguments :on-success
               (lambda (&rest response)
                 (let* ((outcome (map-elt (car response) 'outcome))
                        (steering-outcome
                         (if (and steering (equal outcome "promptRequired")
                                  (buffer-live-p buffer)
                                  (not (with-current-buffer buffer (shell-maker-busy))))
                             "submitted" outcome))
                        (emacsvox-agent-shell--setting-callback-active setting)
                        (ems--message-filter
                         (if (and setting announce-setting)
                             (concat "\\(?:" ems--message-filter "\\|"
                                     setting-message-regexp "\\)")
                           ems--message-filter)))
                   (when success (apply success response))
                   (when (emacsvox-agent-shell--callback-current-p buffer generation)
                     (with-current-buffer buffer
                       (if steering
                           (emacsvox-agent-shell--steering-feedback
                            steering-outcome)
                         (emacsvox-agent-shell--observe-config-options
                          (emacsvox-agent-shell--config-options) announce-setting))))))))
        (when steering
          (setq arguments
                (plist-put
                 arguments :on-failure
                 (lambda (&rest response)
                   (when failure (apply failure response))
                   (when (emacsvox-agent-shell--callback-current-p buffer generation)
                     (with-current-buffer buffer
                       (emacsvox-agent-shell--steering-feedback
                        "failed" (map-elt (car response) 'message))))))))
        (apply original arguments)))))

(defun emacsvox-agent-shell--push-request-around (original &rest arguments)
  "Begin speech collection only after ORIGINAL accepts a server push."
  (let* ((state (plist-get arguments :state))
         (buffer (map-elt state :buffer))
         (id (map-elt (plist-get arguments :acp-request) 'id))
         (busy-before
          (seq-some (lambda (request)
                      (member (map-elt request :method) '("session/prompt" "session/push")))
                    (map-elt state :active-requests))))
    (prog1 (apply original arguments)
      (when (and (not busy-before) (buffer-live-p buffer)
                 (seq-some (lambda (request)
                             (and (equal (map-elt request :method) "session/push")
                                  (equal (map-elt request :id) id)))
                           (map-elt state :active-requests)))
        (with-current-buffer buffer
          (unless emacsvox-agent-shell--push-active-p
            (setq emacsvox-agent-shell--push-active-p t)
            (emacsvox-agent-shell--begin-response-turn)
            (when (and emacsvox-agent-shell-signal-processing
                       (emacsvox-agent-shell--speech-level-at-least-p 'full))
              (emacsvox-agent-shell--notify-event
               "Agent update started."
               (emacsvox-agent-shell-lifecycle-facts '((:event . input-submitted)))
               emacsvox-agent-shell-processing-start-icon))))))))

(defun emacsvox-agent-shell--push-end-around (original &rest arguments)
  "Finish pushed speech at ORIGINAL's completion callback, before queue drain."
  (let ((buffer (map-elt (plist-get arguments :state) :buffer))
        (finished (plist-get arguments :on-finished)))
    (setq arguments (copy-sequence arguments))
    (setq arguments
          (plist-put
           arguments :on-finished
           (lambda (&rest callback-arguments)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (when emacsvox-agent-shell--push-active-p
                   (unwind-protect
                       (let ((emacsvox-aural-submission-lane 'notification))
                         (emacsvox-agent-shell--handle-lifecycle-event
                          '((:event . turn-complete)
                            (:data . ((:stop-reason . "end_turn"))))))
                     (setq emacsvox-agent-shell--push-active-p nil)))))
             (when finished (apply finished callback-arguments)))))
    (apply original arguments)))

(defun emacsvox-agent-shell--pending-prompt-count ()
  "Return the current queue length."
  (length (map-elt agent-shell--state :pending-prompts)))

(defun emacsvox-agent-shell--queue-feedback (state)
  "Announce queue STATE and its remaining prompt count."
  (let ((count (emacsvox-agent-shell--pending-prompt-count)))
    (emacsvox-agent-shell--notify-event
     (if (eq state 'started)
         (let ((submitted (- (or emacsvox-agent-shell--queue-start-count count)
                             count)))
           (if (> submitted 1)
               (format "%d queued prompts started together. %d remaining."
                       submitted count)
             (format "Queued prompt started. %d remaining." count)))
       (format "Queue paused. %d %s waiting. Resume with M-x agent-shell-prompt-queue-resume."
               count (if (= count 1) "prompt" "prompts")))
     (emacsvox-agent-shell--presentation-facts
      'agent-session 'agent-queue-changed nil
      (list :agent-queue-state state :agent-queue-count count))
     (if (eq state 'started) 'progress 'warn-user))))

(declare-function emacsvox-agent-shell--input-write-around
                  "emacsvox-agent-shell-motion" (original args))

(defun emacsvox-agent-shell--queue-process-around (original &rest arguments)
  "Capture ORIGINAL's queue size so public input events describe actual draining."
  (let ((emacsvox-agent-shell--queue-start-count
         (emacsvox-agent-shell--pending-prompt-count)))
    (emacsvox-agent-shell--input-write-around original arguments)))

(defun emacsvox-agent-shell--queue-display-after (&rest _)
  "Announce the pending queue that Agent Shell has paused."
  (when (and (> (emacsvox-agent-shell--pending-prompt-count) 0)
             emacsvox-agent-shell-signal-processing)
    (emacsvox-agent-shell--queue-feedback 'paused)))

(defun emacsvox-agent-shell--session-setting-speech
    (property label fallback)
  "Describe session PROPERTY using LABEL, or return FALLBACK."
  (if-let* ((state (emacsvox-agent-shell--header-state))
            (value (plist-get state property)))
      (format "%s %s." label value)
    fallback))

(defun emacsvox-agent-shell--session-setting-around
    (original-function arguments command property label fallback)
  "Call ORIGINAL-FUNCTION with ARGUMENTS and announce a successful change.
COMMAND identifies the interactive command.  PROPERTY, LABEL, and FALLBACK
describe the resulting session setting.  Agent Shell changes settings
asynchronously, so interactive feedback is added to its success callback and
reads the state only after Agent Shell has updated it."
  (if (not (ems-interactive-p command))
      (apply original-function arguments)
    (let ((original-callback (car arguments))
          (shell-buffer (current-buffer))
          (generation emacsvox-agent-shell--callback-generation)
          (emacsvox-agent-shell--setting-command-active t))
      (apply
       original-function
       (cons
        (lambda (&rest callback-arguments)
          (when original-callback
            (apply original-callback callback-arguments))
          (when (and (not emacsvox-agent-shell--setting-callback-active)
                     (emacsvox-agent-shell--callback-current-p shell-buffer generation))
            (with-current-buffer shell-buffer
              (emacsvox-agent-shell--notify-event
               (emacsvox-agent-shell--session-setting-speech
                property label fallback)
               (emacsvox-agent-shell--presentation-facts
                'agent-session 'agent-setting-changed)
               'select-object 'state-change))))
        (cdr arguments))))))

(defun emacsvox-agent-shell--set-session-model-around
    (original-function &rest arguments)
  "Announce an interactive model change after it succeeds."
  (emacsvox-agent-shell--session-setting-around
   original-function arguments 'agent-shell-set-session-model
   :model "Model" "Model changed."))

(defun emacsvox-agent-shell--set-session-mode-around
    (original-function &rest arguments)
  "Announce an interactive session mode change after it succeeds."
  (emacsvox-agent-shell--session-setting-around
   original-function arguments 'agent-shell-set-session-mode
   :mode "Session mode" "Session mode changed."))

(defun emacsvox-agent-shell--cycle-session-mode-around
    (original-function &rest arguments)
  "Announce an interactive session mode cycle after it succeeds."
  (emacsvox-agent-shell--session-setting-around
   original-function arguments 'agent-shell-cycle-session-mode
   :mode "Session mode" "Session mode changed."))

(defun emacsvox-agent-shell--viewport-submit-disposition ()
  "Return how a viewport prompt will be handled, or nil when unknown.
The public session status is sampled before submission because a successful
direct submission immediately changes it to busy."
  (condition-case nil
      (when-let* ((shell-buffer (emacsvox-agent-shell--session-buffer)))
        (pcase (agent-shell-status :shell-buffer shell-buffer)
          ((or 'busy 'blocked)
           ;; Observe the actual custom busy route during submission.
           nil)
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
     ('steered "Steering sent.")
     ('submitted "Prompt submitted.")
     (_ "Prompt sent."))
   (cond
    (keep-composing " Continue composing.")
    (dismiss " Compose window dismissed.")
    (t ""))))

(defvar emacsvox-agent-shell--viewport-submission nil
  "Dynamically bound disposition cell for the owning viewport send command.
Nested send helpers share this cell and must not announce independently.")

(defun emacsvox-agent-shell--prompt-enqueued-after (&rest _)
  "Record actual queueing during an interactive viewport submission."
  (when emacsvox-agent-shell--viewport-submission
    (setcar emacsvox-agent-shell--viewport-submission 'queued)))

(defun emacsvox-agent-shell--steering-sent-after (&rest _)
  "Record steering dispatch without claiming that the agent accepted it."
  (when emacsvox-agent-shell--viewport-submission
    (setcar emacsvox-agent-shell--viewport-submission 'steered)))

(defun emacsvox-agent-shell--viewport-compose-send-around
    (original-function &rest arguments)
  "Announce a prompt's actual submission route and where focus remains."
  (let* ((interactive-p
          (and (not emacsvox-agent-shell--viewport-submission)
               (or (ems-interactive-p 'agent-shell-viewport-compose-send)
                   (ems-interactive-p
                    'agent-shell-viewport-compose-send-override))))
         (keep-composing
          (and interactive-p (car arguments)))
         (dismiss
          (and interactive-p
               (not keep-composing)
               (boundp 'agent-shell-viewport-dismiss-on-send)
               agent-shell-viewport-dismiss-on-send))
         (emacsvox-agent-shell--viewport-submission
          (if interactive-p
              (list (emacsvox-agent-shell--viewport-submit-disposition))
            emacsvox-agent-shell--viewport-submission)))
    (prog1
        (apply original-function arguments)
      (when interactive-p
        (emacsvox-agent-shell--submit-text-feedback
         (emacsvox-agent-shell--viewport-submit-announcement
          (car emacsvox-agent-shell--viewport-submission)
          keep-composing dismiss)
         (emacsvox-agent-shell--presentation-facts
          'agent-prompt-editor 'agent-prompt-submitted nil
          (list :agent-prompt-disposition
                (or (car emacsvox-agent-shell--viewport-submission) 'sent)))
         'state-change
         (if keep-composing 'task-done 'close-object))))))

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
        (emacsvox-agent-shell--submit-text-feedback
         "Prompt composition cancelled."
         (emacsvox-agent-shell--presentation-facts
          'agent-prompt-editor 'agent-prompt-cancelled)
         'state-change 'close-object)))))

(provide 'emacsvox-agent-shell-interaction)

;;; emacsvox-agent-shell-interaction.el ends here
