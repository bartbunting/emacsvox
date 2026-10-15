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
   ("h" "Review, replay, and edit retained feedback" emacsvox-settings-workflows--recent :transient transient--do-suspend)]
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
