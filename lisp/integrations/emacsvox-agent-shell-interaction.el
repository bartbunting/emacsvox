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

;; Handle interactive questions and their confirmed outcomes. The facade owns
;; advice installation and activation; event subscriptions call these helpers.
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
                  "emacsvox-agent-shell" (level &optional buffer))
(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--deliver-announcement
                  "emacsvox-agent-shell" (facts occasion icon text &optional delivery-policy))
(declare-function emacsvox-agent-shell--session-buffer
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell" (text facts occasion &optional icon delivery-policy replacement-key))
(declare-function agent-shell-elicitation--preview-open-p "agent-shell-elicitation" (elicitation key value))
(declare-function agent-shell-elicitation--option-preview-at "agent-shell-elicitation" (elicitation key value))
(defvar agent-shell--state)

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

(provide 'emacsvox-agent-shell-interaction)

;;; emacsvox-agent-shell-interaction.el ends here
