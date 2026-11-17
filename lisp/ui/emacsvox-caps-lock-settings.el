;;; emacsvox-caps-lock-settings.el --- Caps Lock reminder settings -*- lexical-binding: t; -*-

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
;; Choose tone or speech globally; edit the reminder tone in the shared editor.
;; Preview and draft changes do not enable the keyboard watcher.

;;; Code:
(require 'emacsvox-caps-lock)
(require 'emacsvox-tone-editor)
(require 'emacsvox-aural-preview)

(defun emacsvox-caps-lock-settings--say (text)
  "Speak concise settings feedback TEXT."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'caps-lock 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-caps-lock-settings--name ()
  "Name the current reminder presentation."
  (if (eq emacsvox-caps-lock-reminder-presentation 'spoken) "Speech" "Tone"))

(defun emacsvox-caps-lock-settings--choice-label (value label)
  "Describe VALUE with LABEL and mark the current choice."
  (concat label (when (eq value emacsvox-caps-lock-reminder-presentation) ", selected")))

(defun emacsvox-caps-lock-settings--tone ()
  "Use the editable tone for keyboard reminders while Caps Lock is on.
Apply globally for this session without enabling the watcher.  The tone does
not stop current speech.  State-change and focus-entry reports remain spoken.
Save the reminder choice separately to keep it across restarts."
  (interactive)
  (customize-set-variable 'emacsvox-caps-lock-reminder-presentation 'tone)
  (emacsvox-caps-lock-settings--say "Tone"))

(defun emacsvox-caps-lock-settings--spoken ()
  "Say Caps Lock for keyboard reminders while Caps Lock is on.
Apply globally for this session without enabling the watcher.  Ordinary-key
reminders follow normal key feedback; modifier reminders interrupt older main
speech.  Save the reminder choice separately to keep it across restarts."
  (interactive)
  (customize-set-variable 'emacsvox-caps-lock-reminder-presentation 'spoken)
  (emacsvox-caps-lock-settings--say "Speech"))

(transient-define-prefix emacsvox-caps-lock-settings--presentation ()
  "Choose tone or speech for Caps Lock key reminders globally.
Arrows browse without applying.  Enter selects and returns; q cancels.
This does not enable the watcher or change state/focus announcements.
Save the reminder choice in the parent menu to keep it across restarts."
  ["Reminder"
   ("t" (lambda () (emacsvox-caps-lock-settings--choice-label 'tone "Tone"))
    emacsvox-caps-lock-settings--tone :transient transient--do-replace)
   ("s" (lambda () (emacsvox-caps-lock-settings--choice-label 'spoken "Speech"))
    emacsvox-caps-lock-settings--spoken :transient transient--do-replace)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-aural-menu--choice-setup
   'emacsvox-caps-lock-settings--presentation
   (if (eq emacsvox-caps-lock-reminder-presentation 'spoken)
       'emacsvox-caps-lock-settings--spoken 'emacsvox-caps-lock-settings--tone)))

(defun emacsvox-caps-lock-settings--tone-data (&optional factory)
  "Read the global reminder tone, or its FACTORY values, as an editor draft."
  (let ((values (if factory
                    (eval (car (get 'emacsvox-caps-lock-reminder-tone 'standard-value)) t)
                  emacsvox-caps-lock-reminder-tone)))
    (emacsvox-tone-editor--data
     (plist-get values :pitch) (plist-get values :duration)
     (* 100 (plist-get values :volume)) (plist-get values :shape))))

(defun emacsvox-caps-lock-settings--tone-values (data)
  "Convert private editor DATA to a durable tone setting."
  (list :pitch (plist-get data :pitch) :duration (plist-get data :duration)
        :volume (/ (plist-get data :volume) 100.0)
        :shape (emacsvox-tone-editor--shape data)))

(defun emacsvox-caps-lock-settings--apply-tone (data save)
  "Apply tone DATA globally; SAVE also retains it through Customize."
  (let ((values (emacsvox-caps-lock-settings--tone-values data)))
    (if save (customize-save-variable 'emacsvox-caps-lock-reminder-tone values)
      (customize-set-variable 'emacsvox-caps-lock-reminder-tone values))))

(defun emacsvox-caps-lock-settings--preview-tone (data sample)
  "Preview private tone DATA, optionally with spoken SAMPLE content."
  (let* ((values (emacsvox-caps-lock-settings--tone-values data))
         (context (emacsvox-aural-menu--context))
         (emacsvox-aural--exact-tone-preview t))
    (with-current-buffer (emacsvox-aural-menu--source context)
      (emacsvox-aural--tone-volume-deliverable-p (plist-get values :volume))
      (emacsvox-aural--tone-shape-deliverable-p (plist-get values :shape))
      (let* ((action (emacsvox-aural--compile-action
                      (emacsvox-caps-lock--tone-action values)
                      'caps-lock-preview 'before 0 'run))
             (render (emacsvox-aural--make-render-plan
                      :before (list action)
                      :content (emacsvox-aural--make-content-style :speak sample))))
        (emacsvox-aural-preview-play-plan
         (emacsvox-aural-compile-plan
          render (when sample '(:content "Capital A"))
          (emacsvox-aural-context-at-point) 'local-cue))))))

(defun emacsvox-caps-lock-settings--edit-tone ()
  "Edit the global reminder tone in a private draft.
Space previews; P adds a spoken typing sample.  A applies for this session;
W also saves through Customize.  Editing preserves the tone/speech choice
and watcher enablement.  State-change and focus-entry speech are unchanged."
  (interactive)
  (emacsvox-tone-editor--open
   (emacsvox-aural-menu--context)
   (list :label "Caps Lock reminder tone"
         :read #'emacsvox-caps-lock-settings--tone-data
         :current #'emacsvox-caps-lock-settings--tone-data
         :apply #'emacsvox-caps-lock-settings--apply-tone
         :preview #'emacsvox-caps-lock-settings--preview-tone
         :apply-label "Apply reminder tone for session"
         :save-label "Save reminder tone through Customize"
         :apply-message "Reminder tone applied for this session"
         :save-message "Reminder tone saved"
         :apply-help "Apply this reminder tone globally for this session.
Only Tone uses these values.  The watcher, tone/speech choice, state-change
announcements and focus-entry speech stay unchanged."
         :save-help "Apply and save this global reminder tone through Customize.
Retain pitch, duration, individual volume, waveform, sweep and envelope across
restarts.  This does not enable the watcher or change the tone/speech choice."
         :current-help "Compare with the currently applied global reminder tone.
The private draft, saved settings and watcher stay unchanged.")))

(defun emacsvox-caps-lock-settings--preview ()
  "Preview the selected reminder without enabling the Caps Lock watcher.
Tone uses the currently applied global tone; Speech says Caps Lock.
This interrupts older main output and does not apply or save settings."
  (interactive)
  (if (eq emacsvox-caps-lock-reminder-presentation 'tone)
      (emacsvox-caps-lock-settings--preview-tone
       (emacsvox-caps-lock-settings--tone-data) nil)
    (emacsvox-aural-preview-play-plan
     (emacsvox-aural-compile-plan
      (emacsvox-aural--make-render-plan
       :content (emacsvox-aural--make-content-style :speak t))
      '(:content "Caps Lock") (emacsvox-aural-context-at-point) 'local-cue))))

(defun emacsvox-caps-lock-settings--save ()
  "Save only the global Tone or Speech reminder choice through Customize.
Save tone adjustments separately with W in the tone editor.  Watcher
enablement and keyboard Caps Lock state are unchanged."
  (interactive)
  (customize-save-variable 'emacsvox-caps-lock-reminder-presentation
                           emacsvox-caps-lock-reminder-presentation)
  (emacsvox-caps-lock-settings--say "Reminder choice saved"))

;;;###autoload
(transient-define-prefix emacsvox-caps-lock-settings ()
  "Choose and tune the global Caps Lock key reminder.
Enable Caps Lock announcements separately for automatic feedback.  The
default reminder is a tone; state-change and focus-entry reports stay spoken.
Selecting applies for this session; Save reminder choice keeps that choice.
The tone editor has its own Preview, Apply and Save controls."
  :refresh-suffixes t
  ["Caps Lock reminders (global)"
   ("r" (lambda () (concat "Reminder: " (emacsvox-caps-lock-settings--name)))
    emacsvox-caps-lock-settings--presentation :transient transient--do-stack)
   ("e" "Edit reminder tone" emacsvox-caps-lock-settings--edit-tone :transient transient--do-stack)
   ("SPC" "Preview reminder" emacsvox-caps-lock-settings--preview :transient t)
   ("S" "Stop preview" emacsvox-tone-editor--stop :transient t)]
  ["Save and finish"
   ("w" "Save reminder choice" emacsvox-caps-lock-settings--save :transient t)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (let ((context (condition-case nil
                     (emacsvox-aural-menu--context)
                   (user-error (emacsvox-aural-menu--capture t)))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-caps-lock-settings nil nil :scope context)))

(provide 'emacsvox-caps-lock-settings)
;;; emacsvox-caps-lock-settings.el ends here
