;;; emacsvox-settings-integrations.el --- Integration settings discovery -*- lexical-binding: t; -*-

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
;; Discover actual integration options and invoke existing source controls.
;;; Code:
(require 'emacsvox-settings)
(declare-function emacsvox-agent-shell--session-buffer "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell-select-speech-level "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--cancel-background-pending-speech "emacsvox-agent-shell" ())
(declare-function emacsvox-eat--control-buffer "emacsvox-eat-core" ())
(declare-function emacsvox-eat--terminal-buffer-p "emacsvox-eat-core" ())

(defconst emacsvox-settings-integrations--menus
  '((org . emacsvox-settings-integrations--org)
    (agent . emacsvox-settings-integrations--agent)
    (comint . emacsvox-settings-integrations--comint)
    (eat . emacsvox-settings-integrations--eat))
  "Focused Transient prefixes for converted integrations.")

;;;###autoload
(defun emacsvox-settings-for-buffer ()
  "Open Emacsvox settings for the current buffer.
Use its focused integration menu when available, otherwise general buffer
settings.  Changes retain the scope shown by each control."
  (interactive)
  (let* ((context (emacsvox-aural-menu--capture nil))
         (kind (let ((transient--prefix
                      (transient-prefix :command 'emacsvox-settings-integrations
                                        :scope context)))
                 (emacsvox-settings-integrations--kind)))
         (menu (alist-get kind emacsvox-settings-integrations--menus)))
    (setq transient--stack nil)
    (transient-setup (or menu 'emacsvox-settings-buffer) nil nil :scope context)))

(defconst emacsvox-settings-integrations--catalogue
  '((comint "Shell/comint" comint emacsvox-comint nil)
    (agent "Agent Shell" agent-shell emacsvox-agent-shell emacsvox-agent-shell)
    (eat "EAT terminals" eat emacsvox-eat emacsvox-eat)
    (org "Org tables" org emacsvox-org emacsvox-org)
    (notmuch "Notmuch mail" notmuch emacsvox-notmuch emacsvox-notmuch)
    (eww "EWW browser" eww emacsvox-eww emacsvox-eww))
  "Integration ID, label, package library, speech feature, and Custom group.
A nil group denotes a focused menu with buffer-only controls.")
(defun emacsvox-settings-integrations--kind ()
  "Identify the integration belonging to the captured buffer."
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (cond ((derived-mode-p 'agent-shell-mode 'agent-shell-viewport-view-mode
                           'agent-shell-viewport-edit-mode) 'agent)
          ((or (derived-mode-p 'eat-mode 'emacsvox-eat-review-mode)
               (and (bound-and-true-p eat-terminal)
                    (fboundp 'emacsvox-eat--terminal-buffer-p)
                    (emacsvox-eat--terminal-buffer-p))) 'eat)
          ((derived-mode-p 'comint-mode) 'comint)
          ((derived-mode-p 'org-mode) 'org)
          ((derived-mode-p 'notmuch-search-mode 'notmuch-show-mode 'notmuch-tree-mode) 'notmuch)
          ((derived-mode-p 'eww-mode) 'eww))))
(defun emacsvox-settings-integrations--open (kind suffix)
  "Open KIND's focused menu or Custom group, returning to SUFFIX."
  (let ((entry (assq kind emacsvox-settings-integrations--catalogue)))
    (unless entry (user-error "No integration settings group for this buffer"))
    (unless (locate-library (symbol-name (nth 2 entry)))
      (user-error "%s is not installed" (nth 1 entry)))
    (require (nth 3 entry))
    (if-let* ((menu (alist-get kind emacsvox-settings-integrations--menus)))
        (transient-setup
         menu nil nil
         :scope (plist-put (copy-sequence (emacsvox-aural-menu--context))
                           :integration-return suffix))
      (emacsvox-settings--custom (nth 4 entry) suffix))))
(defun emacsvox-settings-integrations--current ()
  "Open settings for the captured buffer's integration."
  (interactive)
  (emacsvox-settings-integrations--open (emacsvox-settings-integrations--kind)
                                       'emacsvox-settings-integrations--current))
(defun emacsvox-settings-integrations--all ()
  "Choose an installed integration's speech settings."
  (interactive)
  (condition-case nil
      (let* ((choices (mapcar (lambda (entry) (cons (nth 1 entry) (car entry)))
                             (cl-remove-if-not
                              (lambda (entry) (locate-library (symbol-name (nth 2 entry))))
                              emacsvox-settings-integrations--catalogue)))
             (kind (cdr (assoc (completing-read "Integration settings: " choices nil t) choices))))
        (emacsvox-settings-integrations--open kind 'emacsvox-settings-integrations--all))
    (quit (emacsvox-settings-integrations--return 'emacsvox-settings-integrations--all))))

(defun emacsvox-settings-integrations--return (suffix)
  "Restore the stacked menu and focus its originating SUFFIX."
  (when (transient--stack-pop)
    (transient--show)
    (when-let* ((object (transient-suffix-object suffix)))
      (with-selected-window transient--window
        (transient--goto-button object)))))
(defun emacsvox-settings-integrations--comint-back ()
  "Return from Comint settings to the originating menu entry."
  (interactive)
  (emacsvox-settings-integrations--return
   (or (plist-get (emacsvox-aural-menu--context) :integration-return)
       'emacsvox-settings-search)))
(defun emacsvox-settings-integrations--control-label ()
  "Describe the source integration's existing local speech control."
  (pcase (emacsvox-settings-integrations--kind)
    ('agent "Choose this Agent Shell session's speech level")
    ('eat "Toggle this terminal's foreground speech")
    ('comint "Toggle this buffer's automatic output speech")
    (_ "Local speech control unavailable for this buffer")))
(defun emacsvox-settings-integrations--control-p ()
  "Whether the captured integration provides a local speech control."
  (memq (emacsvox-settings-integrations--kind) '(agent eat comint)))
(defun emacsvox-settings-integrations--group-p ()
  "Whether the captured integration has an inventoried settings entry."
  (assq (emacsvox-settings-integrations--kind) emacsvox-settings-integrations--catalogue))
(defun emacsvox-settings-integrations--current-label ()
  "Describe the settings entry or explain how to choose another integration."
  (if (emacsvox-settings-integrations--group-p)
      "This integration's settings"
    "No settings for this buffer; use a to choose an integration"))
(defun emacsvox-settings-integrations--control ()
  "Run the existing local control in the captured buffer, without saving."
  (interactive)
  (let ((command (pcase (emacsvox-settings-integrations--kind)
                   ('agent 'emacsvox-agent-shell-select-speech-level)
                   ('eat 'emacsvox-eat-toggle-autospeak)
                   ('comint 'emacsvox-toggle-comint-autospeak))))
    (unless (and command (fboundp command))
      (user-error "The source integration's speech control is unavailable"))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
      ;; These commands interpret prefixes differently; this entry is local.
      (let ((current-prefix-arg nil)) (call-interactively command)))))

(defun emacsvox-settings-integrations--comint-p ()
  "Whether the captured buffer supports ordinary Comint speech controls."
  (eq (emacsvox-settings-integrations--kind) 'comint))
(defun emacsvox-settings-integrations--comint-label (variable label)
  "Describe Comint VARIABLE with LABEL in the captured buffer."
  (if (not (emacsvox-settings-integrations--comint-p))
      (concat label ": open from a shell or Comint buffer")
    (require 'emacsvox-comint)
    (format "%s: %s" label
            (if (buffer-local-value variable
                   (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
                "on" "off"))))
(defun emacsvox-settings-integrations--comint-toggle (command)
  "Run Comint COMMAND locally in the captured buffer."
  (unless (emacsvox-settings-integrations--comint-p)
    (user-error "Open these controls from a shell or Comint buffer"))
  (require 'emacsvox-comint)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (let ((current-prefix-arg nil)) (call-interactively command))))
(defun emacsvox-settings-integrations--comint-autospeak ()
  "Toggle automatic output speech only in the captured Comint buffer."
  (interactive)
  (emacsvox-settings-integrations--comint-toggle 'emacsvox-toggle-comint-autospeak))
(defun emacsvox-settings-integrations--comint-monitor ()
  "Toggle background output monitoring only in the captured Comint buffer."
  (interactive)
  (emacsvox-settings-integrations--comint-toggle 'emacsvox-toggle-comint-output-monitor))

(transient-define-prefix emacsvox-settings-integrations--comint ()
  "Control output speech for the captured Comint buffer without saving defaults."
  ["Shell/comint: this buffer, temporary"
   ("s" (lambda () (emacsvox-settings-integrations--comint-label
                    'emacsvox-comint-autospeak "Automatic output speech"))
    emacsvox-settings-integrations--comint-autospeak
    :inapt-if-not emacsvox-settings-integrations--comint-p :transient t)
   ("b" (lambda () (emacsvox-settings-integrations--comint-label
                    'emacsvox-comint-output-monitor "Background monitoring (needs automatic speech)"))
    emacsvox-settings-integrations--comint-monitor
    :inapt-if-not emacsvox-settings-integrations--comint-p :transient t)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--comint-back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--comint nil nil
                   :scope (emacsvox-aural-menu--context)))

(defconst emacsvox-settings-integrations--eat-options
  '(emacsvox-eat-autospeak emacsvox-eat-monitor-background-output
    emacsvox-eat-prompt-feedback emacsvox-eat-verbosity)
  "Terminal options saved only by the EAT menu's explicit Save action.")
(defun emacsvox-settings-integrations--eat-source ()
  "Return the terminal owned by the captured EAT buffer or frozen review."
  (require 'emacsvox-eat)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (emacsvox-eat--control-buffer)))
(defun emacsvox-settings-integrations--eat-p ()
  "Whether the captured source still owns an EAT terminal."
  (and (eq (emacsvox-settings-integrations--kind) 'eat)
       (condition-case nil (emacsvox-settings-integrations--eat-source)
         (user-error nil))))
(defun emacsvox-settings-integrations--eat-label (variable label)
  "Describe terminal VARIABLE with LABEL, including its current value."
  (if (not (emacsvox-settings-integrations--eat-p))
      (concat label ": open from a live EAT terminal or its review")
    (let ((value (buffer-local-value variable (emacsvox-settings-integrations--eat-source))))
      (format "%s: %s" label
              (pcase value
                ('t "on") ('nil "off") ('earcon "ready cue")
                ('text "read prompt") (_ value))))))
(defun emacsvox-settings-integrations--eat-call (command)
  "Run the existing local EAT COMMAND in the captured terminal."
  (with-current-buffer (emacsvox-settings-integrations--eat-source)
    (let ((current-prefix-arg nil)) (call-interactively command))))
(defun emacsvox-settings-integrations--eat-autospeak ()
  "Toggle captured-terminal foreground speech through its existing lifecycle."
  (interactive)
  (emacsvox-settings-integrations--eat-call 'emacsvox-eat-toggle-autospeak))
(defun emacsvox-settings-integrations--eat-monitor ()
  "Toggle captured-terminal background cues through their existing lifecycle."
  (interactive)
  (emacsvox-settings-integrations--eat-call 'emacsvox-eat-toggle-background-monitoring))
(defun emacsvox-settings-integrations--eat-detail ()
  "Cycle automatic feedback detail for the captured terminal."
  (interactive)
  (emacsvox-settings-integrations--eat-call 'emacsvox-eat-cycle-verbosity))
(defun emacsvox-settings-integrations--eat-prompt ()
  "Cycle ready cue, prompt text and silence for the captured terminal."
  (interactive)
  (with-current-buffer (emacsvox-settings-integrations--eat-source)
    (set (make-local-variable 'emacsvox-eat-prompt-feedback)
         (pcase (symbol-value 'emacsvox-eat-prompt-feedback)
           ('earcon 'text) ('text 'silent) (_ 'earcon))))
  (emacsvox-transient--submit-text
   (emacsvox-settings-integrations--eat-label 'emacsvox-eat-prompt-feedback "Prompt feedback")
   (emacsvox-transient--menu-facts 'eat-prompt 'command-menu-value-changed)
   'state-change 'select-object))
(defun emacsvox-settings-integrations--eat-save ()
  "Save these four terminal values as defaults through Customize."
  (interactive)
  (let* ((source (emacsvox-settings-integrations--eat-source))
         (values (mapcar (lambda (option) (cons option (buffer-local-value option source)))
                         emacsvox-settings-integrations--eat-options)))
    (dolist (entry values) (customize-save-variable (car entry) (cdr entry))))
  (emacsvox-transient--submit-text
   "Saved four EAT defaults; terminals without local overrides inherit them"
   (emacsvox-transient--menu-facts 'eat-defaults 'command-menu-value-changed)
   'state-change 'save-object))
(defun emacsvox-settings-integrations--eat-custom ()
  "Open advanced EAT Customize options, returning to this menu."
  (interactive)
  (require 'emacsvox-eat)
  (emacsvox-settings--custom 'emacsvox-eat 'emacsvox-settings-integrations--eat-custom))
(defun emacsvox-settings-integrations--eat-back ()
  "Return from EAT settings to the originating menu entry."
  (interactive)
  (emacsvox-settings-integrations--return
   (or (plist-get (emacsvox-aural-menu--context) :integration-return)
       'emacsvox-settings-search)))

(transient-define-prefix emacsvox-settings-integrations--eat ()
  "Control the captured EAT terminal, saving defaults only on request."
  ["EAT: captured terminal, local changes"
   ("s" (lambda () (emacsvox-settings-integrations--eat-label
                    'emacsvox-eat-autospeak "Automatic foreground speech"))
    emacsvox-settings-integrations--eat-autospeak
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient t)
   ("b" (lambda () (emacsvox-settings-integrations--eat-label
                    'emacsvox-eat-monitor-background-output "Background cues and unread count"))
    emacsvox-settings-integrations--eat-monitor
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient t)
   ("p" (lambda () (emacsvox-settings-integrations--eat-label
                    'emacsvox-eat-prompt-feedback "Prompt feedback (shell integration)"))
    emacsvox-settings-integrations--eat-prompt
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient t)
   ("d" (lambda () (emacsvox-settings-integrations--eat-label
                    'emacsvox-eat-verbosity "Automatic feedback detail"))
    emacsvox-settings-integrations--eat-detail
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient t)]
  ["Defaults and advanced settings"
   ("w" "Save these four values as defaults" emacsvox-settings-integrations--eat-save
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient t)
   ("A" "Advanced EAT settings (Customize)" emacsvox-settings-integrations--eat-custom
    :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--eat-back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--eat nil nil
                   :scope (emacsvox-aural-menu--context)))

(defconst emacsvox-settings-integrations--options
   '((emacsvox-settings-integrations--org-feedback emacsvox-org
     emacsvox-org-table-after-movement-function "After moving in a table"
     ((emacsvox-org-table-speak-current-element . "cell")
      (emacsvox-org-table-speak-column-header . "column header")
      (emacsvox-org-table-speak-row-header . "row header")
      (emacsvox-org-table-speak-column-header-and-element . "column header and cell")
      (emacsvox-org-table-speak-row-header-and-element . "row header and cell")
      (emacsvox-org-table-speak-both-headers-and-element . "both headers and cell")))
    (emacsvox-settings-integrations--agent-foreground emacsvox-agent-shell
     emacsvox-agent-shell-foreground-speech-level "Foreground speech"
     ((full . "full") (response . "responses") (notify . "notifications") (quiet . "quiet")))
    (emacsvox-settings-integrations--agent-background emacsvox-agent-shell
     emacsvox-agent-shell-background-speech-level "Background speech"
     ((full . "full") (response . "responses") (notify . "notifications") (quiet . "quiet")))
    (emacsvox-settings-integrations--agent-thoughts emacsvox-agent-shell
     emacsvox-agent-shell-speak-thought-process "Thought feedback"
     ((icon . "cue") (speak . "speak") (nil . "silent")))
    (emacsvox-settings-integrations--agent-tools emacsvox-agent-shell
     emacsvox-agent-shell-tool-output-verbosity "Tool output"
     ((summary . "summary") (status . "status cues") (full . "full")))
    (emacsvox-settings-integrations--agent-permissions emacsvox-agent-shell
     emacsvox-agent-shell-speak-permissions "Speak permission requests" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--agent-calls emacsvox-agent-shell
     emacsvox-agent-shell-speak-tool-calls "Announce tool calls" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--agent-processing emacsvox-agent-shell
     emacsvox-agent-shell-signal-processing "Processing lifecycle cues" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--agent-automatic-limit emacsvox-agent-shell
     emacsvox-agent-shell-automatic-content-max-characters "Automatic content characters" nil 100 "complete content")
    (emacsvox-settings-integrations--agent-line-limit emacsvox-agent-shell
     emacsvox-agent-shell-line-speech-max-characters "Line navigation characters" nil 100 "core long-line policy")
    (emacsvox-settings-integrations--agent-block-limit emacsvox-agent-shell
     emacsvox-agent-shell-block-navigation-max-characters "Block navigation characters" nil 100 "complete body"))
  "Global controls: command, feature, option, label, choices, step and nil label.
Choices are value/label pairs. Numeric controls accept positive integers or none.")
(defun emacsvox-settings-integrations--option (command)
  "Return the global control owned by COMMAND, loading its option definitions."
  (let ((entry (assq command emacsvox-settings-integrations--options)))
    (unless entry (user-error "Select a settings control first"))
    (require (nth 1 entry))
    entry))
(defun emacsvox-settings-integrations--label (command)
  "Describe COMMAND's global default, preserving custom values."
  (let* ((entry (emacsvox-settings-integrations--option command))
         (value (default-value (nth 2 entry))))
    (format "%s: %s" (nth 3 entry)
            (or (cdr (assoc value (nth 4 entry)))
                (and (null value) (nth 6 entry))
                (format "%s" value)))))
(defun emacsvox-settings-integrations--say (text)
  "Speak interruptible settings feedback TEXT."
  (emacsvox-transient--submit-text text
   (emacsvox-transient--menu-facts 'integration-setting 'command-menu-value-changed)
   'state-change 'select-object))
(defun emacsvox-settings-integrations--read-limit (prompt initial)
  "Read a limit with PROMPT and INITIAL, retaining the selected control."
  (let ((prefix transient--prefix)
        (focus (when (window-live-p transient--window)
                 (with-selected-window transient--window
                   (get-text-property (point) 'button-data)))))
    (unwind-protect (read-string prompt initial)
      (when (and focus prefix (eq prefix transient--prefix))
        (transient--show)
        (with-selected-window transient--window (transient--goto-button focus))))))
(defun emacsvox-settings-integrations--edit (command &optional delta)
  "Change COMMAND's global option, optionally adjusting its number by DELTA."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((entry (emacsvox-settings-integrations--option command))
         (option (nth 2 entry)) (old (default-value option))
         (choices (nth 4 entry))
         (value
          (if choices
              (car (or (cadr (member (assoc old choices) choices)) (car choices)))
            (if delta (max 1 (+ (or old 0) (* delta (nth 5 entry))))
              (let ((input (emacsvox-settings-integrations--read-limit (format "%s (positive integer or none): " (nth 3 entry))
                                        (if old (number-to-string old) "none"))))
                (cond ((equal (downcase (string-trim input)) "none") nil)
                      ((string-match-p "\\`[0-9]+\\'" input) (string-to-number input))
                      (t (user-error "Enter a positive integer or none"))))))))
    (when (and (not choices) value (<= value 0))
      (user-error "Enter a positive integer or none"))
    (customize-set-variable option value)
    ;; Preserve the lifecycle used by the existing background-level command.
    (when (and (eq option 'emacsvox-agent-shell-background-speech-level)
               (memq value '(notify quiet)))
      (emacsvox-agent-shell--cancel-background-pending-speech))
    (emacsvox-settings-integrations--say (emacsvox-settings-integrations--label command))))
(defun emacsvox-settings-integrations--adjust (direction)
  "Adjust the selected numeric integration control in DIRECTION."
  (let* ((command (with-selected-window (emacsvox-transient--navigation-window)
                    (when-let* ((button (button-at (point))))
                      (oref (button-get button 'button-data) command))))
         (entry (assq command emacsvox-settings-integrations--options)))
    (unless (nth 5 entry) (user-error "Select a numeric control first"))
    (emacsvox-settings-integrations--edit command direction)))
(defun emacsvox-settings-integrations--decrease ()
  "Decrease the selected integration limit." (interactive)
  (emacsvox-settings-integrations--adjust -1))
(defun emacsvox-settings-integrations--increase ()
  "Increase the selected integration limit." (interactive)
  (emacsvox-settings-integrations--adjust 1))
(defun emacsvox-settings-integrations--number-bindings (map)
  "Add shifted-arrow adjustment to focused integration MAP."
  (when (and transient--prefix
             (memq (oref transient--prefix command)
                   '(emacsvox-settings-integrations--agent emacsvox-settings-integrations--notmuch)))
    (keymap-set map "S-<left>" #'emacsvox-settings-integrations--decrease)
    (keymap-set map "S-<right>" #'emacsvox-settings-integrations--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return
            #'emacsvox-settings-integrations--number-bindings)
(define-key transient-predicate-map [emacsvox-settings-integrations--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-settings-integrations--increase] #'transient--do-stay)
(defun emacsvox-settings-integrations--save-options (feature)
  "Save FEATURE's displayed global controls through Customize."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (require feature)
  (dolist (entry emacsvox-settings-integrations--options)
    (when (eq feature (nth 1 entry))
      (customize-save-variable (nth 2 entry) (default-value (nth 2 entry)))))
  (emacsvox-settings-integrations--say "Saved displayed global defaults"))
(defun emacsvox-settings-integrations--back ()
  "Return to the originating integration entry, or close a direct menu."
  (interactive)
  (emacsvox-settings-integrations--return
   (or (plist-get (emacsvox-aural-menu--context) :integration-return)
       'emacsvox-settings-search)))

(defun emacsvox-settings-integrations--agent-source ()
  "Resolve the captured Agent Shell session or viewport without creating one."
  (require 'emacsvox-agent-shell)
  (emacsvox-agent-shell--session-buffer
   (emacsvox-aural-menu--source (emacsvox-aural-menu--context))))
(defun emacsvox-settings-integrations--agent-p ()
  "Whether the captured buffer owns an Agent Shell session."
  (condition-case nil (emacsvox-settings-integrations--agent-source) (user-error nil)))
(defun emacsvox-settings-integrations--agent-session-label ()
  "Describe the current session override, separate from global defaults."
  (if (emacsvox-settings-integrations--agent-p)
      (format "Session speech: %s"
              (buffer-local-value 'emacsvox-agent-shell-speech-level
                                  (emacsvox-settings-integrations--agent-source)))
    "Session speech: open from Agent Shell or its viewport"))
(defun emacsvox-settings-integrations--agent-session ()
  "Choose speech for the captured session through its existing lifecycle."
  (interactive)
  (with-current-buffer (emacsvox-settings-integrations--agent-source)
    (call-interactively #'emacsvox-agent-shell-select-speech-level)))
(defun emacsvox-settings-integrations--agent-save ()
  "Save displayed Agent Shell defaults, excluding the session override."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-agent-shell))
(defun emacsvox-settings-integrations--agent-custom ()
  "Open advanced Agent Shell settings and return here."
  (interactive)
  (require 'emacsvox-agent-shell)
  (emacsvox-settings--custom 'emacsvox-agent-shell 'emacsvox-settings-integrations--agent-custom))

(defun emacsvox-settings-integrations--agent-foreground ()
  "Change the global foreground speech." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-foreground))

(defun emacsvox-settings-integrations--agent-background ()
  "Change the global background speech." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-background))

(defun emacsvox-settings-integrations--agent-thoughts ()
  "Change the global thought feedback." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-thoughts))

(defun emacsvox-settings-integrations--agent-tools ()
  "Change the global tool output." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-tools))

(defun emacsvox-settings-integrations--agent-permissions ()
  "Change the global speak permission requests." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-permissions))

(defun emacsvox-settings-integrations--agent-calls ()
  "Change the global announce tool calls." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-calls))

(defun emacsvox-settings-integrations--agent-processing ()
  "Change the global processing lifecycle cues." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-processing))

(defun emacsvox-settings-integrations--agent-automatic-limit ()
  "Change the global automatic content limit." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-automatic-limit))

(defun emacsvox-settings-integrations--agent-line-limit ()
  "Change the global line navigation limit." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-line-limit))

(defun emacsvox-settings-integrations--agent-block-limit ()
  "Change the global block navigation limit." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-block-limit))

(transient-define-prefix emacsvox-settings-integrations--agent ()
  "Control Agent Shell speech, separating session overrides and global defaults."
  ["Captured session (temporary)"
   ("s" (lambda () (emacsvox-settings-integrations--agent-session-label))
    emacsvox-settings-integrations--agent-session
    :inapt-if-not emacsvox-settings-integrations--agent-p :transient t)]
  ["Global speech defaults; w saves"
   ("f" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-foreground))
    emacsvox-settings-integrations--agent-foreground :transient t)
   ("b" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-background))
    emacsvox-settings-integrations--agent-background :transient t)
   ("t" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-thoughts))
    emacsvox-settings-integrations--agent-thoughts :transient t)
   ("o" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-tools))
    emacsvox-settings-integrations--agent-tools :transient t)
   ("p" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-permissions))
    emacsvox-settings-integrations--agent-permissions :transient t)
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-calls))
    emacsvox-settings-integrations--agent-calls :transient t)
   ("l" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-processing))
    emacsvox-settings-integrations--agent-processing :transient t)
  ]
  ["Global reading limits: Enter exact value; Shift-arrows adjust"
   ("a" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-automatic-limit))
    emacsvox-settings-integrations--agent-automatic-limit :transient t)
   ("n" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-line-limit))
    emacsvox-settings-integrations--agent-line-limit :transient t)
   ("k" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-block-limit))
    emacsvox-settings-integrations--agent-block-limit :transient t)
  ]
  ["Save and finish"
   ("w" "Save displayed global defaults" emacsvox-settings-integrations--agent-save :transient t)
   ("A" "Advanced Agent Shell settings (Customize)" emacsvox-settings-integrations--agent-custom :transient transient--do-suspend)
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--agent nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--org-feedback ()
  "Cycle the global Org table movement feedback."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--org-feedback))
(defun emacsvox-settings-integrations--org-save ()
  "Save the displayed Org feedback default."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-org))
(defun emacsvox-settings-integrations--org-tables ()
  "Open Org's structured table settings and return to this entry."
  (interactive)
  (require 'org-table)
  (emacsvox-settings--custom 'org-table 'emacsvox-settings-integrations--org-tables))
(defun emacsvox-settings-integrations--org-custom ()
  "Open advanced Emacsvox Org settings and return here."
  (interactive)
  (require 'emacsvox-org)
  (emacsvox-settings--custom 'emacsvox-org 'emacsvox-settings-integrations--org-custom))
(transient-define-prefix emacsvox-settings-integrations--org ()
  "Choose Org table feedback and reach its structured settings."
  ["Org table feedback (global); w saves"
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--org-feedback))
    emacsvox-settings-integrations--org-feedback :transient t)
   ("w" "Save table feedback default" emacsvox-settings-integrations--org-save :transient t)]
  ["Structured and advanced settings"
   ("t" "Org table options (Customize)" emacsvox-settings-integrations--org-tables :transient transient--do-suspend)
   ("A" "Advanced Emacsvox Org settings (Customize)" emacsvox-settings-integrations--org-custom :transient transient--do-suspend)
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--org nil nil :scope (emacsvox-aural-menu--context)))

;;;###autoload
(transient-define-prefix emacsvox-settings-integrations ()
  "Find integration settings and existing local speech controls."
  ["Captured buffer"
   ("s" (lambda () (emacsvox-settings-integrations--control-label))
    emacsvox-settings-integrations--control :inapt-if-not emacsvox-settings-integrations--control-p :transient t)
   ("c" (lambda () (emacsvox-settings-integrations--current-label)) emacsvox-settings-integrations--current
    :inapt-if-not emacsvox-settings-integrations--group-p :transient transient--do-suspend)]
  ["All integrations"
   ("a" "Choose integration settings" emacsvox-settings-integrations--all :transient transient--do-suspend)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations nil nil :scope (emacsvox-aural-menu--context)))
(provide 'emacsvox-settings-integrations)
;;; emacsvox-settings-integrations.el ends here
