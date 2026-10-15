;;; emacsvox-settings-workflows.el --- Linked editing workflows -*- lexical-binding: t; -*-

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
;; Link focused menus to existing editors, retaining their persistence semantics.
;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-history)
(require 'emacsvox-pronounce)
(defvar omnivox-average-pitch-contrast)
(defvar emacsvox-aural-preview-label-verbosity)
(declare-function emacsvox-aural-set-history-limit "emacsvox-aural-recent-feedback" (limit))
(declare-function emacsvox-aural-toggle-interface-history-recording "emacsvox-aural-recent-feedback" ())
(declare-function emacsvox-aural-feedback-outline-mode "emacsvox-aural-feedback-details" (&optional arg))
(declare-function emacsvox-aural-change-feedback--remap-at-point "emacsvox-aural-change-feedback" ())
(declare-function emacsvox-aural-remap-earcon-at-point "emacsvox-aural-tools" (&optional record))
(declare-function emacsvox-edit-aural-rules "emacsvox-aural-editor" (scope &optional fragment source-buffer))
(declare-function emacsvox-aural-home-drafts "emacsvox-aural-home" ())

(defun emacsvox-settings-workflows--open (feature command suffix &optional at-item)
  "Open COMMAND from FEATURE, returning to SUFFIX; optionally use captured AT-ITEM."
  (require feature)
  (let (opened)
    (emacsvox-aural-menu--open-browser
     (lambda ()
       (if at-item (emacsvox-aural-menu--call-at-item command)
         (call-interactively command))
       (setq opened (window-buffer (selected-window)))) suffix)
    (with-current-buffer opened
      (when (derived-mode-p 'emacsvox-aural-feedback-details-mode)
        (emacsvox-aural-feedback-outline-mode 1))
      (when (derived-mode-p 'emacsvox-aural-feedback-details-mode 'help-mode)
        (setq-local emacsvox-aural-ui--help-return-function
                    (if (derived-mode-p 'help-mode)
                        (let ((return emacsvox-aural-ui--return-function)
                              (buffer opened))
                          (lambda ()
                            (with-current-buffer buffer
                              (setq emacsvox-aural-ui--return-function nil)
                              (emacsvox-aural-ui-help-return-mode -1))
                            (funcall return)))
                      emacsvox-aural-ui--return-function))))))
(defun emacsvox-settings-workflows--change ()
  "Open a retained feedback draft for the captured source item."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-change-feedback
   #'emacsvox-aural-change-feedback 'emacsvox-settings-workflows--change t))
(defun emacsvox-settings-workflows--voice ()
  "Choose a voice mapping for the captured item in a preview draft."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-change-feedback
   #'emacsvox-aural-change-feedback--remap-at-point 'emacsvox-settings-workflows--voice t))
(defun emacsvox-settings-workflows--cue ()
  "Prepare a cue override for the captured item, choosing its scope explicitly."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-tools
   #'emacsvox-aural-remap-earcon-at-point 'emacsvox-settings-workflows--cue t))
(defun emacsvox-settings-workflows--explain ()
  "Explain the effective feedback for the captured item."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-explanation
   #'emacsvox-explain-aural-presentation 'emacsvox-settings-workflows--explain t))
(defun emacsvox-settings-workflows--recent ()
  "Review retained feedback and edit the selected frozen record."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-recent-feedback
   #'emacsvox-aural-list-recent-feedback 'emacsvox-settings-workflows--recent))

(defun emacsvox-settings-workflows--tune ()
  "Tune the named voice used at the captured source item.
Changes affect every use of that named voice.  Preview, save, and application
remain explicit in the editor; q retains unfinished work and returns here."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-change-feedback
   #'emacsvox-aural-change-feedback--tune-at-point 'emacsvox-settings-workflows--tune t))

(defun emacsvox-settings-workflows--say (text &optional icon)
  "Announce TEXT interruptibly with optional ICON."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'settings 'command-menu-value-changed)
   'state-change (or icon 'select-object)))

(defun emacsvox-settings-workflows--history-say (text)
  "Announce history setting TEXT without retaining the announcement."
  (let ((emacsvox-aural--history-recording-inhibited t))
    (emacsvox-settings-workflows--say text)))

(defun emacsvox-settings-workflows--history-limit (&optional delta)
  "Set the global history limit, or adjust it by DELTA.
Lowering the limit immediately removes the oldest excess records.  Zero clears
and disables history; increasing it cannot restore removed records.  Enter
accepts an exact nonnegative integer; Shift-arrows adjust by one.  Save is
separate and saves the limit, never the retained spoken text."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (require 'emacsvox-aural-recent-feedback)
  (let ((value (if delta
                   (max 0 (+ emacsvox-aural-presentation-history-limit delta))
                 (emacsvox-aural-menu--read-number
                  "History limit (lowering removes old entries; 0 clears): "
                  emacsvox-aural-presentation-history-limit))))
    (cl-letf (((symbol-function 'emacsvox-aural-tools--speak-history-setting) #'ignore))
      (emacsvox-aural-set-history-limit value))
    (emacsvox-settings-workflows--history-say
     (if (zerop value) "History disabled; retained records cleared"
       (format "History limit: %d" value)))))

(defun emacsvox-settings-workflows--history-interface ()
  "Toggle recording of Aural interface presentations globally.
Enable temporarily to diagnose interface feedback.  Navigation, previews and
status can then displace source feedback.  Save defaults separately."
  (interactive)
  (require 'emacsvox-aural-recent-feedback)
  (cl-letf (((symbol-function 'emacsvox-aural-tools--speak-history-setting)
             #'emacsvox-settings-workflows--history-say))
    (emacsvox-aural-toggle-interface-history-recording)))

(defun emacsvox-settings-workflows--history-save ()
  "Save the history limit and interface-recording policy through Customize.
This does not save retained feedback or restore discarded records."
  (interactive)
  (dolist (option '(emacsvox-aural-presentation-history-limit
                    emacsvox-aural-history-record-interface-presentations))
    (customize-save-variable option (symbol-value option)))
  (emacsvox-settings-workflows--history-say "History defaults saved"))

(defun emacsvox-settings-workflows--adjust (delta)
  "Adjust the selected numeric workflow control by DELTA steps."
  (let* ((object (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (button-get button 'button-data))))
         (command (and object (oref object command))))
    (if (memq command '(emacsvox-settings-workflows--history-limit
                        emacsvox-settings-workflows--pitch-contrast))
        (funcall command delta)
      (emacsvox-settings-workflows--say
       "Not adjustable. Enter activates; left and right change sections."
       'warn-user))))
(defun emacsvox-settings-workflows--decrease ()
  "Lower the selected numeric setting by one step."
  (interactive) (emacsvox-settings-workflows--adjust -1))
(defun emacsvox-settings-workflows--increase ()
  "Raise the selected numeric setting by one step."
  (interactive) (emacsvox-settings-workflows--adjust 1))
(defun emacsvox-settings-workflows--bindings (map)
  "Add numeric workflow adjustments to transient MAP."
  (when (and transient-enable-menu-navigation transient--prefix
             (memq (oref transient--prefix command) '(emacsvox-settings-history
                       emacsvox-settings-voice-presentation)))
    (keymap-set map "S-<left>" #'emacsvox-settings-workflows--decrease)
    (keymap-set map "S-<right>" #'emacsvox-settings-workflows--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return
            #'emacsvox-settings-workflows--bindings)
(dolist (command '(emacsvox-settings-workflows--decrease
                   emacsvox-settings-workflows--increase))
  (define-key transient-predicate-map (vector command) #'transient--do-stay))

;;;###autoload
(transient-define-prefix emacsvox-settings-history ()
  "Manage retained feedback globally; lowering the limit deletes old records.
Changes apply immediately.  Save defaults separately through Customize."
  :refresh-suffixes t
  ["History policy (global)"
   ("l" (lambda () (format "Retained records: %d (0 clears)"
                           emacsvox-aural-presentation-history-limit))
    emacsvox-settings-workflows--history-limit :transient t)
   ("i" (lambda () (format "Record Aural interfaces: %s"
                           (if emacsvox-aural-history-record-interface-presentations "on" "off")))
    emacsvox-settings-workflows--history-interface :transient t)]
  ["Save and finish"
   ("w" "Save history defaults" emacsvox-settings-workflows--history-save :transient t)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (require 'emacsvox-aural-history)
  (transient-setup 'emacsvox-settings-history nil nil :scope (emacsvox-aural-menu--context)))

;;;###autoload
(transient-define-prefix emacsvox-settings-feedback ()
  "Explain and edit current or recent feedback, preserving source context."
  ["Captured item"
   ("x" "Explain effective feedback" emacsvox-settings-workflows--explain :transient transient--do-suspend)
   ("c" "Change voice, cue, or tone (preview draft)" emacsvox-settings-workflows--change :transient transient--do-suspend)
   ("t" "Tune this item's named voice (shared)" emacsvox-settings-workflows--tune :transient transient--do-suspend)
   ("v" "Choose a voice for this item" emacsvox-settings-workflows--voice :transient transient--do-suspend)
   ("e" "Remap a cue with explicit scope" emacsvox-settings-workflows--cue :transient transient--do-suspend)]
  ["Recent feedback"
   ("h" "Review, replay, and edit retained feedback" emacsvox-settings-workflows--recent :transient transient--do-suspend)
   ("H" "History limits and recording" emacsvox-settings-history :transient transient--do-stack)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-feedback nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-workflows--rules (scope suffix)
  "Edit rules in SCOPE for the captured source, returning to SUFFIX."
  (emacsvox-settings-workflows--open
   'emacsvox-aural-editor
   (lambda () (interactive) (emacsvox-edit-aural-rules scope nil (current-buffer)))
   suffix))
(defun emacsvox-settings-workflows--personal ()
  "Edit personal rules with an explicit persistent save." (interactive)
  (emacsvox-settings-workflows--rules 'personal 'emacsvox-settings-workflows--personal))
(defun emacsvox-settings-workflows--session ()
  "Edit session rules without writing startup defaults." (interactive)
  (emacsvox-settings-workflows--rules 'session 'emacsvox-settings-workflows--session))
(defun emacsvox-settings-workflows--buffer ()
  "Edit rules for the captured buffer." (interactive)
  (emacsvox-settings-workflows--rules 'buffer 'emacsvox-settings-workflows--buffer))
(defun emacsvox-settings-workflows--features ()
  "Manage built-in and personal Presentation Options." (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-feature-fragments
   #'emacsvox-aural-list-feature-fragments 'emacsvox-settings-workflows--features))
(defun emacsvox-settings-workflows--face-label ()
  "Describe global visual-face presentation."
  (format "Visual-face presentation: %s"
          (if emacsvox-aural-face-presentation-enabled "on" "off")))
(defun emacsvox-settings-workflows--face ()
  "Toggle global face presentation through its change lifecycle." (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (emacsvox-aural-toggle-face-presentation)
  (emacsvox-transient--submit-text
   (emacsvox-settings-workflows--face-label)
   (emacsvox-transient--menu-facts 'presentation 'command-menu-value-changed)
   'state-change 'select-object))
(defun emacsvox-settings-workflows--save-face ()
  "Save only visual-face presentation as a startup default." (interactive)
  (customize-save-variable 'emacsvox-aural-face-presentation-enabled
                           emacsvox-aural-face-presentation-enabled)
  (emacsvox-transient--submit-text
   "Visual-face presentation default saved"
   (emacsvox-transient--menu-facts 'presentation 'command-menu-value-changed)
   'state-change 'save-object))

(defun emacsvox-settings-workflows--overrides ()
  "Review personal, session, and captured-buffer rules together.
Opening the overview changes no rules.  Edit, preview, disable, or remove a
selected rule explicitly; q returns to this menu."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-overrides
   #'emacsvox-aural-list-overrides 'emacsvox-settings-workflows--overrides))

(defun emacsvox-settings-workflows--semantics ()
  "Browse the registered roles, states, and events used by presentation rules.
This is a reference view; inspecting vocabulary changes no settings."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-semantics
   #'emacsvox-aural-list-semantics 'emacsvox-settings-workflows--semantics))

(defun emacsvox-settings-workflows--training-label ()
  "Describe session-wide training explanations."
  (format "Training explanations (session): %s"
          (if emacsvox-aural-training-mode "on" "off")))

(defun emacsvox-settings-workflows--training ()
  "Toggle automatic presentation explanations for this Emacs session.
Training adds explanations to supported feedback.  It affects all buffers,
uses the existing training lifecycle, and does not save a startup default."
  (interactive)
  (emacsvox-aural-training-mode (if emacsvox-aural-training-mode -1 1))
  (emacsvox-transient--submit-text
   (emacsvox-settings-workflows--training-label)
   (emacsvox-transient--menu-facts 'training 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-settings-workflows--source-toggle-label (option label)
  "Describe buffer-local OPTION with LABEL in the captured source."
  (format "%s: %s" label
          (if (buffer-local-value option
               (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
              "on" "off")))

(defun emacsvox-settings-workflows--voice-lock ()
  "Toggle legacy face/personality voice mapping in the captured buffer.
Semantic presentation and explicit face rules remain independent.  This uses
Voice Lock's change hooks and does not save a startup default."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (voice-lock-mode (if voice-lock-mode -1 1)))
  (emacsvox-settings-workflows--say
   (emacsvox-settings-workflows--source-toggle-label 'voice-lock-mode "Voice Lock in source")))

(defun emacsvox-settings-workflows--global-voice-lock ()
  "Toggle global Voice Lock through its minor-mode lifecycle.
This updates existing buffers and the policy for new buffers.  Modes may opt
out on startup.  It does not disable semantic presentation or explicit face
rules.  Save this global default separately; local overrides are not saved."
  (interactive)
  (global-voice-lock-mode (if global-voice-lock-mode -1 1))
  (emacsvox-settings-workflows--say
   (format "Global Voice Lock: %s" (if global-voice-lock-mode "on" "off"))))

(defun emacsvox-settings-workflows--save-voice-lock ()
  "Save only global Voice Lock through Customize.
Local Voice Lock, local silence and earcon switches are not saved here."
  (interactive)
  (customize-save-variable 'global-voice-lock-mode global-voice-lock-mode)
  (emacsvox-settings-workflows--say "Global Voice Lock default saved" 'save-object))

(defun emacsvox-settings-workflows--silence ()
  "Silence or restore the captured item's mapped voice in its source buffer.
This toggles the existing local personality/face suppression, which can affect
other text with that mapping in the same buffer.  It neither retunes a shared
voice nor silences every presentation.  A globally inaudible mapping cannot be
restored here.  Changes last for this buffer and are not saved."
  (interactive)
  (require 'voice-setup)
  (let (report cue)
    ;; Keep the existing target selection and local-map lifecycle, but combine
    ;; its message and cue into one interruptible menu announcement.
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (setq report (apply #'format format-string args))))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (setq cue icon))))
      (emacsvox-aural-menu--call-at-item #'voice-setup-toggle-silence-personality))
    (when report (emacsvox-settings-workflows--say report cue))))

(defun emacsvox-settings-workflows--icons ()
  "Toggle earcons only in the captured source buffer for this session.
This creates a local override.  Speech remains available when earcons are off.
Use Inherit to remove the override and follow the current global default."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (emacsvox-toggle-icons))
  (emacsvox-settings-workflows--say
   (emacsvox-settings-workflows--source-toggle-label 'emacsvox-use-icons "Earcons in source")))

(defun emacsvox-settings-workflows--default-icons ()
  "Toggle the earcon default for buffers without a local override.
Existing local overrides, including the source's, remain unchanged.  This is
session state, not a Customize option; there is no startup save here.  Turning
it off also removes menu cues in buffers inheriting the default."
  (interactive)
  (set-default 'emacsvox-use-icons (not (default-value 'emacsvox-use-icons)))
  (emacsvox-settings-workflows--say
   (format "Earcon default: %s" (if (default-value 'emacsvox-use-icons) "on" "off"))))

(defun emacsvox-settings-workflows--inherit-icons ()
  "Remove the captured buffer's earcon override and follow the global default.
This affects the source buffer immediately and does not save startup settings."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (kill-local-variable 'emacsvox-use-icons))
  (emacsvox-settings-workflows--say
   (concat (emacsvox-settings-workflows--source-toggle-label 'emacsvox-use-icons "Earcons in source")
           ", following default")))

(defun emacsvox-settings-workflows--preview-label-name ()
  "Describe the global voice comparison label policy."
  (require 'emacsvox-aural-preview)
  (pcase emacsvox-aural-preview-label-verbosity
    ('names "engine and voice names")
    ('brief "letters or numbers")
    (_ "no labels")))

(defun emacsvox-settings-workflows--preview-label-choice (value label)
  "Describe VALUE's LABEL and whether it is selected."
  (concat label (when (eq value emacsvox-aural-preview-label-verbosity) ", selected")))

(defun emacsvox-settings-workflows--preview-label-apply (value)
  "Apply comparison label VALUE and return to the invoking control."
  (customize-set-variable 'emacsvox-aural-preview-label-verbosity value)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-settings-workflows--say
   (concat "Comparison labels: " (emacsvox-settings-workflows--preview-label-name))))

(defun emacsvox-settings-workflows--preview-names ()
  "Identify physical comparison samples by engine and voice name.
This global policy keeps each label in the same cancellable sequence as its
unchanged sample.  It applies immediately; Save defaults separately."
  (interactive) (emacsvox-settings-workflows--preview-label-apply 'names))
(defun emacsvox-settings-workflows--preview-brief ()
  "Identify physical comparison samples only by letter or sequence number.
The sample text stays unchanged.  This global policy applies immediately;
Save defaults separately."
  (interactive) (emacsvox-settings-workflows--preview-label-apply 'brief))
(defun emacsvox-settings-workflows--preview-unlabelled ()
  "Omit identifying labels from physical voice comparisons globally.
Samples keep their text and order, but no longer say which voice is playing.
This applies immediately; Save defaults separately."
  (interactive) (emacsvox-settings-workflows--preview-label-apply nil))

(transient-define-prefix emacsvox-settings-preview-labels ()
  "Choose physical voice comparison labels; navigation changes nothing.
Enter applies the selected policy and returns.  Cancel retains the old policy."
  ["Comparison labels (global)"
   ("n" (lambda () (emacsvox-settings-workflows--preview-label-choice 'names "Engine and voice names"))
    emacsvox-settings-workflows--preview-names :transient transient--do-replace)
   ("b" (lambda () (emacsvox-settings-workflows--preview-label-choice 'brief "Letters or numbers"))
    emacsvox-settings-workflows--preview-brief :transient transient--do-replace)
   ("o" (lambda () (emacsvox-settings-workflows--preview-label-choice nil "No labels"))
    emacsvox-settings-workflows--preview-unlabelled :transient transient--do-replace)]
  ["Finish"
   ("q" "Cancel" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (require 'emacsvox-aural-preview)
  (transient-setup 'emacsvox-settings-preview-labels nil nil :scope (emacsvox-aural-menu--context))
  (transient--show)
  (with-selected-window transient--window
    (transient--goto-button
     (transient-suffix-object
      (pcase emacsvox-aural-preview-label-verbosity
        ('names 'emacsvox-settings-workflows--preview-names)
        ('brief 'emacsvox-settings-workflows--preview-brief)
        (_ 'emacsvox-settings-workflows--preview-unlabelled)))))
  (emacsvox-transient--speak-button))

(defun emacsvox-settings-workflows--pitch-label ()
  "Describe the current Omnivox contrast, including when opened from search."
  (require 'omnivox-voices)
  (format "Omnivox pitch contrast: %g" omnivox-average-pitch-contrast))

(defun emacsvox-settings-workflows--pitch-contrast (&optional delta)
  "Set global Omnivox pitch contrast, or adjust by DELTA tenths.
Zero neutralises average pitch, 0.5 is the gentle default, 1 restores the
historical curve, and values through 2 increase contrast.  This scales every
ACSS average-pitch level rather than retuning one named voice.  It affects
subsequent Omnivox speech and previews via live logical-voice registration;
other speech backends are unaffected.  Save the default separately."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (require 'omnivox-voices)
  (let ((value (if delta
                   (max 0.0 (min 2.0 (+ omnivox-average-pitch-contrast (* delta 0.1))))
                 (emacsvox-aural-menu--read-number
                  "Omnivox average-pitch contrast (0 to 2): " omnivox-average-pitch-contrast))))
    (unless (and (numberp value) (<= 0 value 2))
      (user-error "Pitch contrast must be from 0 to 2"))
    (customize-set-variable 'omnivox-average-pitch-contrast value)
    (emacsvox-settings-workflows--say (format "Pitch contrast: %g" omnivox-average-pitch-contrast))))

(defun emacsvox-settings-workflows--voice-presentation-save ()
  "Save global comparison labels and Omnivox pitch contrast through Customize.
This does not save a palette, named voice, physical choice, or engine order."
  (interactive)
  (dolist (option '(emacsvox-aural-preview-label-verbosity omnivox-average-pitch-contrast))
    (customize-save-variable option (symbol-value option)))
  (emacsvox-settings-workflows--say "Voice presentation defaults saved" 'save-object))

;;;###autoload
(transient-define-prefix emacsvox-settings-voice-presentation ()
  "Set comparison labels and overall Omnivox pitch contrast globally.
Changes apply now; Save defaults explicitly to keep them across restarts."
  :refresh-suffixes t
  ["Voice presentation (global)"
   ("l" (lambda () (concat "Comparison labels: " (emacsvox-settings-workflows--preview-label-name)))
    emacsvox-settings-preview-labels :transient transient--do-stack)
   ("p" (lambda () (emacsvox-settings-workflows--pitch-label))
    emacsvox-settings-workflows--pitch-contrast :transient t)]
  ["Save and finish"
   ("w" "Save voice presentation defaults" emacsvox-settings-workflows--voice-presentation-save :transient t)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (require 'emacsvox-aural-preview)
  (require 'omnivox-voices)
  (transient-setup 'emacsvox-settings-voice-presentation nil nil :scope (emacsvox-aural-menu--context)))

;;;###autoload
(transient-define-prefix emacsvox-settings-switches ()
  "Control Voice Lock, local silence, and earcons with explicit scopes.
Only global Voice Lock has a Customize save here.  Other switches last for the
session or buffer; Help explains which presentation each switch affects."
  :refresh-suffixes t
  ["Captured buffer"
   ("v" (lambda () (emacsvox-settings-workflows--source-toggle-label 'voice-lock-mode "Voice Lock"))
    emacsvox-settings-workflows--voice-lock :transient t)
   ("s" "Silence or restore mapped voice at captured item" emacsvox-settings-workflows--silence :transient t)
   ("e" (lambda () (emacsvox-settings-workflows--source-toggle-label 'emacsvox-use-icons "Earcons"))
    emacsvox-settings-workflows--icons :transient t)
   ("i" "Inherit earcon default" emacsvox-settings-workflows--inherit-icons :transient t)]
  ["Global policy"
   ("V" (lambda () (format "Voice Lock: %s" (if global-voice-lock-mode "on" "off")))
    emacsvox-settings-workflows--global-voice-lock :transient t)
   ("E" (lambda () (format "Earcon default: %s" (if (default-value 'emacsvox-use-icons) "on" "off")))
    emacsvox-settings-workflows--default-icons :transient t)]
  ["Save and finish"
   ("w" "Save global Voice Lock default" emacsvox-settings-workflows--save-voice-lock :transient t)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (require 'emacsvox-aural-compatibility-voice)
  (transient-setup 'emacsvox-settings-switches nil nil :scope (emacsvox-aural-menu--context)))

(define-minor-mode emacsvox-settings-workflows--dictionary-return-mode
  "Return from a linked dictionary editor without taking letters from fields."
  :lighter nil
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'emacsvox-settings-workflows--dictionary-return)
    (define-key map (kbd "q")
                '(menu-item "Return to pronunciation settings" emacsvox-settings-workflows--dictionary-return
                            :filter (lambda (command) (unless (widget-field-at (point)) command))))
    map))

(defun emacsvox-settings-workflows--dictionary-return ()
  "Return to pronunciation settings, retaining in-memory dictionary edits.
This neither saves dictionaries nor rolls back edits.  C-c C-c works inside
fields too; q remains literal text in editable fields."
  (interactive)
  (let ((editor (current-buffer))
        (return emacsvox-aural-ui--return-function))
    (unless (and return (funcall return))
      (user-error "The menu's source buffer is no longer available"))
    (with-current-buffer editor
      (emacsvox-settings-workflows--dictionary-return-mode -1)
      (setq emacsvox-aural-ui--return-function nil))))

(defun emacsvox-settings-workflows--dictionary-edit ()
  "Edit an existing Emacs pronunciation dictionary using its widget editor.
Choose a file, directory or mode dictionary.  Fields update the in-memory
collection; Save writes dictionaries to their own file, not Customize or the
Omnivox host.  Return with C-c C-c, or q outside fields, retaining edits.
Reopen to resume the buffer; Refresh applies entries to the captured source.
Opening alone neither enables source pronunciations nor writes a file."
  (interactive)
  (require 'wid-edit)
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         opened)
    (emacsvox-aural-menu--open-browser
     (lambda ()
       (when (zerop (hash-table-count emacsvox-pronounce-dictionaries))
         (user-error "No dictionaries to edit; define an entry or load a dictionary first"))
       (let* ((keys (mapcar #'symbol-name (hash-table-keys emacsvox-pronounce-dictionaries)))
              (key (completing-read "Edit Emacs dictionary: " keys nil t))
              (existing (get-buffer (format "*Dict: %s" key))))
         (if existing
             (pop-to-buffer existing)
           ;; The legacy opener enables source pronunciations as a side effect.
           ;; Inspection through settings must preserve the captured buffer.
           (let ((emacsvox-pronounce-table emacsvox-pronounce-table))
             (emacsvox-pronounce-edit-pronunciations key)))
         (setq opened (current-buffer))
         (emacsvox-aural-ui-register-interface source)
         (setq-local emacsvox-aural-ui-source-position (plist-get context :position)
                     emacsvox-aural-ui-source-guard (plist-get context :guard))
         (emacsvox-settings-workflows--dictionary-return-mode 1)
         opened))
     'emacsvox-settings-workflows--dictionary-edit)
    (with-current-buffer opened
      (emacsvox-settings-workflows--say
       "Emacs dictionary editor. Tab moves fields. Save writes dictionaries. Control C Control C returns; q returns outside fields."
       'open-object))))

(defun emacsvox-settings-workflows--dictionary-define ()
  "Define a pronunciation at the captured source, choosing its scope.
Buffer entries are temporary.  File, directory and mode entries update the
in-memory dictionaries and need a separate Save to the Emacs dictionary file.
The existing prompt can load saved dictionaries first; no speech restart is
needed.  The captured item must still be valid."
  (interactive)
  (emacsvox-aural-menu--call-at-item #'emacsvox-pronounce-define-pronunciation)
  (emacsvox-settings-workflows--say
   "Pronunciation defined. Save file, directory, or mode dictionaries separately."))

(defun emacsvox-settings-workflows--dictionary-load ()
  "Load an Emacs dictionary file into the in-memory collection.
This reads the existing Lisp dictionary format, separate from host punctuation.
Refresh the captured buffer afterward to use the loaded entries.  Finish and
close existing widget editors first: their retained fields are not reloaded.
Loading neither writes dictionaries nor restarts speech."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (unless (eq t (call-interactively #'emacsvox-pronounce-load-dictionaries))
      (user-error "Dictionary load did not complete; check the file and reported error")))
  (emacsvox-settings-workflows--say "Emacs dictionaries loaded. Refresh the source to use them."))

(defun emacsvox-settings-workflows--dictionary-refresh ()
  "Rebuild and enable the captured buffer's pronunciation table.
This uses its file, directory and mode dictionaries, replacing temporary
buffer-only entries.  It neither saves dictionaries nor restarts speech."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (emacsvox-pronounce-refresh-pronunciations))
  (emacsvox-settings-workflows--say "Source pronunciations refreshed from dictionaries"))

(defun emacsvox-settings-workflows--dictionary-toggle ()
  "Toggle pronunciation substitution in the captured buffer.
Turning on composes the table from applicable dictionaries; turning off clears
it, including temporary buffer-only entries.  An empty table has no effect.
This switch is temporary and is not saved with dictionaries."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (emacsvox-pronounce-toggle-dictionaries))
  (emacsvox-settings-workflows--say (emacsvox-settings-workflows--dictionary-label)))

(defun emacsvox-settings-workflows--dictionary-label ()
  "Describe pronunciation substitution in the captured source."
  (format "Source pronunciations: %s"
          (if (buffer-local-value 'emacsvox-pronounce-table
               (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
              "on" "off")))

(defun emacsvox-settings-workflows--dictionary-save ()
  "Save file, directory and mode dictionaries to an Emacs dictionary file.
Choose the file explicitly; its configured basename is offered in the Emacsvox
user directory.  Buffer-only entries are not included.  This is separate from Customize and
host punctuation saving, and requires no speech restart."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (call-interactively #'emacsvox-pronounce-save-dictionaries))
  (emacsvox-settings-workflows--say "Emacs pronunciation dictionaries saved" 'save-object))

;;;###autoload
(transient-define-prefix emacsvox-settings-dictionaries ()
  "Manage Emacs pronunciation dictionaries for words and phrases.
These dictionaries have their own Save file, separate from Customize and
Omnivox punctuation.  Opening the menu changes nothing."
  :refresh-suffixes t
  ["Define and edit"
   ("d" "Define pronunciation with explicit scope" emacsvox-settings-workflows--dictionary-define :transient t)
   ("e" "Edit existing dictionary (widget fields)" emacsvox-settings-workflows--dictionary-edit :transient transient--do-suspend)]
  ["Captured buffer"
   ("t" (lambda () (emacsvox-settings-workflows--dictionary-label))
    emacsvox-settings-workflows--dictionary-toggle :transient t)
   ("r" "Refresh from dictionaries (replaces buffer-only entries)" emacsvox-settings-workflows--dictionary-refresh :transient t)]
  ["Dictionary files"
   ("l" "Load dictionaries from file" emacsvox-settings-workflows--dictionary-load :transient t)
   ("w" "Save dictionaries to file" emacsvox-settings-workflows--dictionary-save :transient t)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-dictionaries nil nil :scope (emacsvox-aural-menu--context)))

;;;###autoload
(transient-define-prefix emacsvox-settings-presentation ()
  "Manage presentation features and explicitly scoped rule drafts."
  :refresh-suffixes t
  ["Presentation (global)"
   ("f" "Presentation Options: activate, copy, edit" emacsvox-settings-workflows--features :transient transient--do-suspend)
   ("v" (lambda () (emacsvox-settings-workflows--face-label)) emacsvox-settings-workflows--face :transient t)
   ("w" "Save visual-face default" emacsvox-settings-workflows--save-face :transient t)]
  ["Feedback rules: save inside each editor"
   ("o" "Combined feedback rules" emacsvox-settings-workflows--overrides :transient transient--do-suspend)
   ("p" "Personal rules (persistent)" emacsvox-settings-workflows--personal :transient transient--do-suspend)
   ("s" "Session rules (temporary)" emacsvox-settings-workflows--session :transient transient--do-suspend)
   ("b" "Captured buffer rules (temporary)" emacsvox-settings-workflows--buffer :transient transient--do-suspend)]
  ["Presentation switches"
   ("l" "Voice Lock, local silence, and earcons" emacsvox-settings-switches :transient transient--do-stack)]
  ["Learn about feedback"
   ("h" "Semantic vocabulary reference" emacsvox-settings-workflows--semantics :transient transient--do-suspend)
   ("t" (lambda () (emacsvox-settings-workflows--training-label)) emacsvox-settings-workflows--training :transient t)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-presentation nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-workflows--profiles ()
  "Manage saved presentation profiles using their existing activation rules."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-profiles
   #'emacsvox-aural-list-profiles 'emacsvox-settings-workflows--profiles))
(defun emacsvox-settings-workflows--palettes ()
  "Manage palette inheritance, reset, import, portable export, and full backup."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-voice-palettes
   #'emacsvox-aural-list-voice-palettes 'emacsvox-settings-workflows--palettes))
(defun emacsvox-settings-workflows--drafts ()
  "Resume an unfinished draft directly in its owning editor.
Choose among retained drafts when more than one exists.  Opening writes nothing;
the editor keeps its existing save, discard, and finish choices."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-home
   #'emacsvox-aural-home-drafts 'emacsvox-settings-workflows--drafts))

;;;###autoload
(transient-define-prefix emacsvox-settings-setups ()
  "Manage saved setups and retained drafts in their owning editors."
  ["Saved setups: activation and startup are separate"
   ("p" "Presentation profiles: inspect, create, activate" emacsvox-settings-workflows--profiles :transient transient--do-suspend)
   ("v" "Palettes: inheritance, reset, import and export" emacsvox-settings-workflows--palettes :transient transient--do-suspend)]
  ["Unfinished work"
   ("c" "Changed settings, saved defaults and drafts" emacsvox-settings-changes :transient transient--do-suspend)
   ("d" "Resume retained drafts" emacsvox-settings-workflows--drafts :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-setups nil nil :scope (emacsvox-aural-menu--context)))


(defun emacsvox-settings-workflows--doctor ()
  "Inspect installation findings without changing settings or starting speech.
Doctor's r runs the selected repair explicitly; q returns to this menu."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-doctor
   #'emacsvox-aural-doctor 'emacsvox-settings-workflows--doctor))

(defun emacsvox-settings-workflows--spatial ()
  "Explain available spatial backends and current output policy.
This report changes no routing or saved settings; q returns to this menu."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-explanation
   (lambda ()
     (interactive)
     (pop-to-buffer (emacsvox-aural-describe-spatial-capabilities)))
   'emacsvox-settings-workflows--spatial))

(defun emacsvox-settings-workflows--diagnostic-buffer (name suffix)
  "Show existing speech diagnostics for NAME, returning to SUFFIX."
  (let (buffer map)
    (emacsvox-aural-menu--open-browser
     (lambda ()
       (tts-show-diagnostics name)
       (setq buffer (window-buffer (selected-window)))
       (with-current-buffer buffer
         (setq map (current-local-map))
         (use-local-map (copy-keymap (or map (make-sparse-keymap)))))
       buffer)
     suffix)
    (with-current-buffer buffer
      (let ((return emacsvox-aural-ui--return-function))
        (local-set-key
         (kbd "q")
         (lambda ()
           (interactive)
           (setq emacsvox-aural-ui--return-function nil)
           (use-local-map map)
           (quit-window)
           (funcall return)))))))

(defun emacsvox-settings-workflows--main-diagnostics ()
  "Read retained local main speech-server output, without starting a server.
If no diagnostics exist, report that fact.  q returns to this menu."
  (interactive)
  (emacsvox-settings-workflows--diagnostic-buffer
   "Speaker" 'emacsvox-settings-workflows--main-diagnostics))

(defun emacsvox-settings-workflows--notification-diagnostics ()
  "Read retained local notification-server output, without starting a server.
Remote speech may have no local diagnostics.  q returns to this menu."
  (interactive)
  (emacsvox-settings-workflows--diagnostic-buffer
   "Notify" 'emacsvox-settings-workflows--notification-diagnostics))

(defun emacsvox-settings-workflows--logging-label ()
  "Describe the current session's diagnostic logging."
  (format "Log complete spoken text: %s"
          (if emacsvox-aural-diagnostic-log-file "on" "off")))

(defun emacsvox-settings-workflows--logging ()
  "Toggle diagnostic logging for this session, including complete spoken text.
Reuse the last log path or ~/.emacsvox-aural-diagnostics.log.  This does not
save a startup default.  Advanced options control the file and retention."
  (interactive)
  (let ((emacsvox-speak-messages nil))
    (emacsvox-aural-toggle-diagnostic-logging))
  (emacsvox-transient--submit-text
   (emacsvox-settings-workflows--logging-label)
   (emacsvox-transient--menu-facts 'diagnostics 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-settings-workflows--diagnostic-options ()
  "Customize diagnostic log location, size, retention, and buffer visibility.
Use Customize's Apply and Save explicitly.  Buffer naming changes take effect
on speech restart; this view does not restart speech.  q returns to this menu."
  (interactive)
  (require 'emacsvox-settings)
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (custom-buffer-create
      '((emacsvox-aural-diagnostic-log-file custom-variable)
        (emacsvox-aural-diagnostic-log-max-bytes custom-variable)
        (emacsvox-aural-diagnostic-log-retained-files custom-variable)
        (tts-hide-diagnostic-buffers custom-variable))
      "*Customize Speech Diagnostics*")
     (let ((buffer (window-buffer (selected-window))))
       (with-current-buffer buffer
         (use-local-map (copy-keymap (current-local-map)))
         (local-set-key (kbd "q") #'emacsvox-settings--custom-quit))
       buffer))
   'emacsvox-settings-workflows--diagnostic-options))

;;;###autoload
(transient-define-prefix emacsvox-settings-diagnostics ()
  "Inspect speech and presentation; only explicit actions change settings.
Doctor offers individual repairs.  Logging includes complete spoken text."
  :refresh-suffixes t
  ["Inspect without changing settings"
   ("d" "Aural Doctor: findings and explicit repairs" emacsvox-settings-workflows--doctor :transient transient--do-suspend)
   ("s" "Spatial capabilities and policy" emacsvox-settings-workflows--spatial :transient transient--do-suspend)
   ("m" "Main speech diagnostics" emacsvox-settings-workflows--main-diagnostics :transient transient--do-suspend)
   ("n" "Notification speech diagnostics" emacsvox-settings-workflows--notification-diagnostics :transient transient--do-suspend)]
  ["Logging"
   ("l" (lambda () (emacsvox-settings-workflows--logging-label)) emacsvox-settings-workflows--logging :transient t)
   ("A" "Advanced diagnostic options" emacsvox-settings-workflows--diagnostic-options :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-diagnostics nil nil :scope (emacsvox-aural-menu--context)))

(provide 'emacsvox-settings-workflows)
;;; emacsvox-settings-workflows.el ends here
