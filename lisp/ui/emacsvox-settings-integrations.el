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
(declare-function emacsvox-agent-shell--set-session-speech-level "emacsvox-agent-shell" (shell-buffer level))
(declare-function emacsvox-agent-shell-select-speech-level "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--cancel-background-pending-speech "emacsvox-agent-shell" ())
(declare-function emacsvox-eat--control-buffer "emacsvox-eat-core" ())
(declare-function emacsvox-eat--terminal-buffer-p "emacsvox-eat-core" ())

(defconst emacsvox-settings-integrations--menus
  '((notmuch . emacsvox-settings-integrations--notmuch)
    (eww . emacsvox-settings-integrations--eww)
    (org . emacsvox-settings-integrations--org)
    (markdown . emacsvox-settings-integrations--markdown)
    (info . emacsvox-settings-integrations--info)
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
    (markdown "Markdown reading" markdown-mode emacsvox-markdown emacsvox)
    (info "Info reading" info emacsvox-info emacsvox-info)
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
          ((derived-mode-p 'markdown-mode 'gfm-mode) 'markdown)
          ((derived-mode-p 'Info-mode) 'info)
          ((derived-mode-p 'notmuch-hello-mode 'notmuch-search-mode 'notmuch-show-mode 'notmuch-tree-mode) 'notmuch)
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
  "Restore the parent at SUFFIX, or announce the buffer when closing directly."
  (if (transient--stack-pop)
      (progn
        (transient--show)
        (when-let* ((object (cl-find suffix transient--suffixes
                                    :key (lambda (item) (oref item command)))))
          (with-selected-window transient--window
            (transient--goto-button object))))
    (emacsvox-transient--submit-text
     (emacsvox-transient--buffer-summary)
     (emacsvox-transient--menu-facts 'back 'command-menu-closed)
     'state-change 'close-object)))
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
    (let ((current-prefix-arg nil)
          (emacsvox-aural-submission-lane 'main)
          (emacsvox-aural-submission-delivery-policy 'replaceable)
          (emacsvox-aural-submission-replacement-key 'speaker)
          (emacsvox-aural-submission-interruption-policy 'lane))
      (call-interactively command))))
(defun emacsvox-settings-integrations--eat-autospeak ()
  "Toggle captured-terminal foreground speech through its existing lifecycle."
  (interactive)
  (emacsvox-settings-integrations--eat-call 'emacsvox-eat-toggle-autospeak))
(defun emacsvox-settings-integrations--eat-monitor ()
  "Toggle captured-terminal background cues through their existing lifecycle."
  (interactive)
  (emacsvox-settings-integrations--eat-call 'emacsvox-eat-toggle-background-monitoring))
(defconst emacsvox-settings-integrations--eat-choices
  '((prompt emacsvox-eat-prompt-feedback "Prompt feedback"
            emacsvox-settings-integrations--eat-prompt
            (earcon "Ready cue") (text "Read prompt") (silent "Silent"))
    (detail emacsvox-eat-verbosity "Automatic feedback detail"
            emacsvox-settings-integrations--eat-detail
            (terse "Terse: retain routine output for review")
            (normal "Normal: bounded output and status")
            (verbose "Verbose: also title and directory changes")))
  "EAT choice menus: kind, option, label, return command and value labels.")
(defun emacsvox-settings-integrations--eat-choice-spec ()
  "Return the active EAT choice specification."
  (assq (plist-get (emacsvox-aural-menu--context) :eat-choice)
        emacsvox-settings-integrations--eat-choices))
(defun emacsvox-settings-integrations--eat-choice-label (index)
  "Describe choice INDEX, including whether it is the current terminal value."
  (let* ((spec (emacsvox-settings-integrations--eat-choice-spec))
         (choice (nth index (nthcdr 4 spec)))
         (selected (eq (car choice)
                       (buffer-local-value (nth 1 spec)
                                           (emacsvox-settings-integrations--eat-source)))))
    (concat (cadr choice) (when selected ", selected"))))
(defun emacsvox-settings-integrations--eat-choose (kind)
  "Open KIND's choices without changing the captured terminal."
  (let* ((spec (assq kind emacsvox-settings-integrations--eat-choices))
         (source (emacsvox-settings-integrations--eat-source))
         (value (buffer-local-value (nth 1 spec) source))
         (index (or (seq-position (nthcdr 4 spec) value
                                 (lambda (choice selected) (eq (car choice) selected))) 0)))
    (transient-setup
     'emacsvox-settings-integrations--eat-choice nil nil
     :scope (plist-put (copy-sequence (emacsvox-aural-menu--context)) :eat-choice kind))
    (transient--show)
    (with-selected-window transient--window
      (transient--goto-button
       (cl-find
        (nth index '(emacsvox-settings-integrations--eat-choice-first
                     emacsvox-settings-integrations--eat-choice-second
                     emacsvox-settings-integrations--eat-choice-third))
        transient--suffixes :key (lambda (item) (oref item command)))))
    (emacsvox-transient--speak-button)))
(defun emacsvox-settings-integrations--eat-detail ()
  "Choose how much automatic terminal output to hear."
  (interactive)
  (emacsvox-settings-integrations--eat-choose 'detail))
(defun emacsvox-settings-integrations--eat-prompt ()
  "Choose ready cue, prompt text or silence."
  (interactive)
  (emacsvox-settings-integrations--eat-choose 'prompt))
(defun emacsvox-settings-integrations--eat-choice-back ()
  "Return without changing the terminal choice."
  (interactive)
  (emacsvox-settings-integrations--return
   (nth 3 (emacsvox-settings-integrations--eat-choice-spec))))
(defun emacsvox-settings-integrations--eat-choice-apply (index)
  "Apply choice INDEX locally and return to its parent control."
  (let* ((spec (emacsvox-settings-integrations--eat-choice-spec))
         (value (car (nth index (nthcdr 4 spec)))))
    (with-current-buffer (emacsvox-settings-integrations--eat-source)
      (set (make-local-variable (nth 1 spec)) value))
    (emacsvox-settings-integrations--return (nth 3 spec))
    (emacsvox-settings-integrations--say
     (emacsvox-settings-integrations--eat-label (nth 1 spec) (nth 2 spec)))))
(defun emacsvox-settings-integrations--eat-choice-first ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--eat-choice-apply 0))
(defun emacsvox-settings-integrations--eat-choice-second ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--eat-choice-apply 1))
(defun emacsvox-settings-integrations--eat-choice-third ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--eat-choice-apply 2))
(transient-define-prefix emacsvox-settings-integrations--eat-choice ()
  "Choose an option; Enter applies it and q cancels."
  [:description (lambda () (nth 2 (emacsvox-settings-integrations--eat-choice-spec)))
   ("1" (lambda () (emacsvox-settings-integrations--eat-choice-label 0))
    emacsvox-settings-integrations--eat-choice-first :transient transient--do-replace)
   ("2" (lambda () (emacsvox-settings-integrations--eat-choice-label 1))
    emacsvox-settings-integrations--eat-choice-second :transient transient--do-replace)
   ("3" (lambda () (emacsvox-settings-integrations--eat-choice-label 2))
    emacsvox-settings-integrations--eat-choice-third :transient transient--do-replace)]
  ["Finish"
   ("q" "Cancel" emacsvox-settings-integrations--eat-choice-back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--eat-choice nil nil
                   :scope (emacsvox-aural-menu--context)))

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
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient transient--do-suspend)
   ("d" (lambda () (emacsvox-settings-integrations--eat-label
                    'emacsvox-eat-verbosity "Automatic feedback detail"))
    emacsvox-settings-integrations--eat-detail
    :inapt-if-not emacsvox-settings-integrations--eat-p :transient transient--do-suspend)]
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
  '((emacsvox-settings-integrations--notmuch-completion emacsvox-notmuch
     emacsvox-notmuch-search-completion-style "Search completion" ((adaptive . "adaptive") (summary . "count only") (cue . "cue only") (silent . "silent")))
    (emacsvox-settings-integrations--notmuch-field-characters emacsvox-notmuch
     emacsvox-notmuch-automatic-field-character-limit "Per-field characters" nil 100 "no character limit")
    (emacsvox-settings-integrations--notmuch-field-bytes emacsvox-notmuch
     emacsvox-notmuch-automatic-field-byte-limit "Per-field UTF-8 bytes" nil 100 "no byte limit")
    (emacsvox-settings-integrations--notmuch-total-characters emacsvox-notmuch
     emacsvox-notmuch-automatic-total-character-limit "Total characters" nil 100 "no character limit")
    (emacsvox-settings-integrations--notmuch-total-bytes emacsvox-notmuch
     emacsvox-notmuch-automatic-total-byte-limit "Total UTF-8 bytes" nil 100 "no byte limit")
    (emacsvox-settings-integrations--eww-autospeak emacsvox-eww
     emacsvox-eww-autospeak "Section navigation autospeak" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--eww-images emacsvox-eww
     emacsvox-eww-inhibit-images "Suppress images (next rendering)" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--markdown-auto emacsvox-markdown
     emacsvox-markdown-auto-reading-mode "Reading mode in new buffers" ((t . "on") (nil . "off")))
    (emacsvox-settings-integrations--info-chunk emacsvox-info
     emacsvox-info-select-node-speak-chunk "Read when entering a node"
     ((screenfull . "screenful from point") (node . "entire node")))
    (emacsvox-settings-integrations--org-feedback emacsvox-org
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
    (emacsvox-settings-integrations--agent-input emacsvox-agent-shell
     emacsvox-agent-shell-input-activation "Input activation"
     ((automatic . "automatic") (explicit . "explicit")))
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
Choices are value/label pairs.
Numeric controls accept positive integers or none.")
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
    (emacsvox-settings-integrations--set-option entry value)))
(defun emacsvox-settings-integrations--set-option (entry value)
  "Apply ENTRY's global VALUE with its existing lifecycle and speech feedback."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let ((option (nth 2 entry)))
    (customize-set-variable option value)
    ;; Preserve the lifecycle used by the existing background-level command.
    (when (and (eq option 'emacsvox-agent-shell-background-speech-level)
               (memq value '(notify quiet)))
      (emacsvox-agent-shell--cancel-background-pending-speech))
    (emacsvox-settings-integrations--say
     (emacsvox-settings-integrations--label (car entry)))))
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

(defun emacsvox-settings-integrations--choice-entry-for (command)
  "Return COMMAND's choice control with concise explanations of its values."
  (let* ((session (eq command 'emacsvox-settings-integrations--agent-session))
         (entry (if session
                    (list command 'emacsvox-agent-shell 'emacsvox-agent-shell-speech-level
                          "Session speech" nil)
                  (copy-tree (emacsvox-settings-integrations--option command))))
         (levels '((full . "Full: responses and configured thought, plan and tool feedback")
                   (response . "Responses: responses and completion feedback")
                   (notify . "Notifications: completion only")
                   (quiet . "Quiet: suppress routine feedback; permissions and errors remain separate"))))
    (setf (nth 4 entry)
          (if session
              (cons '(auto . "Auto: follow foreground and background defaults") levels)
            (pcase (nth 2 entry)
              ((or 'emacsvox-agent-shell-foreground-speech-level
                   'emacsvox-agent-shell-background-speech-level) levels)
              ('emacsvox-agent-shell-speak-thought-process
               '((icon . "Cue: a sound without reading thoughts")
                 (speak . "Speak: read thought content") (nil . "Silent: no thought feedback")))
              ('emacsvox-agent-shell-tool-output-verbosity
               '((summary . "Summary: tool status and title")
                 (status . "Status cues: sounds when tools start and finish")
                 (full . "Full: read tool output within the reading limits")))
              ('emacsvox-org-table-after-movement-function
               '((emacsvox-org-table-speak-current-element . "Cell: read the cell contents")
                 (emacsvox-org-table-speak-column-header . "Column header: read the heading only")
                 (emacsvox-org-table-speak-row-header . "Row header: read the first column only")
                 (emacsvox-org-table-speak-column-header-and-element . "Column and cell: read the heading then the cell")
                 (emacsvox-org-table-speak-row-header-and-element . "Row and cell: read the first column then the cell")
                 (emacsvox-org-table-speak-both-headers-and-element . "Both headers and cell: read row, column, then cell")))
              ('emacsvox-notmuch-search-completion-style
               '((adaptive . "Adaptive: read a result in an untouched focused search; otherwise count only")
                 (summary . "Count only: announce the number of results")
                 (cue . "Cue only: signal successful completion with a sound")
                 (silent . "Silent: suppress successful completion feedback; failures remain audible")))
              ('emacsvox-info-select-node-speak-chunk
               '((screenfull . "Screenful: read about one window height from point")
                 (node . "Entire node: read all of the selected node")))
              ('emacsvox-agent-shell-input-activation
               '((automatic . "Automatic: type as soon as you reach the prompt")
                 (explicit . "Explicit: browse until you activate input")))
              (_ (nth 4 entry)))))
    entry))
(defun emacsvox-settings-integrations--choice-entry ()
  "Return the control whose choices are open."
  (emacsvox-settings-integrations--choice-entry-for
   (plist-get (emacsvox-aural-menu--context) :integration-choice)))
(defun emacsvox-settings-integrations--choice-value (entry)
  "Return ENTRY's current value in its session or global scope."
  (if (eq (car entry) 'emacsvox-settings-integrations--agent-session)
      (buffer-local-value (nth 2 entry) (emacsvox-settings-integrations--agent-source))
    (default-value (nth 2 entry))))
(defun emacsvox-settings-integrations--choice-label (index)
  "Describe choice INDEX and mark the current value."
  (let* ((entry (emacsvox-settings-integrations--choice-entry))
         (choice (nth index (nth 4 entry))))
    (concat (cdr choice)
            (when (equal (car choice) (emacsvox-settings-integrations--choice-value entry))
              ", selected"))))
(defun emacsvox-settings-integrations--choice-third-p ()
  "Whether the current control has a third choice."
  (nth 2 (nth 4 (emacsvox-settings-integrations--choice-entry))))
(defun emacsvox-settings-integrations--choice-fourth-p ()
  "Whether the current control has a fourth choice."
  (nth 3 (nth 4 (emacsvox-settings-integrations--choice-entry))))
(defun emacsvox-settings-integrations--choice-fifth-p ()
  "Whether the current control has a fifth choice."
  (nth 4 (nth 4 (emacsvox-settings-integrations--choice-entry))))
(defun emacsvox-settings-integrations--choice-sixth-p ()
  "Whether the current control has a sixth choice."
  (nth 5 (nth 4 (emacsvox-settings-integrations--choice-entry))))
(defun emacsvox-settings-integrations--choice-heading ()
  "Describe the current choice scope."
  (let ((entry (emacsvox-settings-integrations--choice-entry)))
    (concat (nth 3 entry)
            (if (eq (car entry) 'emacsvox-settings-integrations--agent-session)
                " (this session, temporary)" " (global default)"))))
(defun emacsvox-settings-integrations--choose (command)
  "Open COMMAND's choices without applying or saving a value."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((entry (emacsvox-settings-integrations--choice-entry-for command))
         (index (or (seq-position (nth 4 entry) (emacsvox-settings-integrations--choice-value entry)
                                 (lambda (choice value) (equal (car choice) value))) 0)))
    (transient-setup
     'emacsvox-settings-integrations--choice nil nil
     :scope (plist-put (copy-sequence (emacsvox-aural-menu--context)) :integration-choice command))
    (transient--show)
    (with-selected-window transient--window
      (transient--goto-button
       (cl-find (nth index '(emacsvox-settings-integrations--choice-first
                            emacsvox-settings-integrations--choice-second
                            emacsvox-settings-integrations--choice-third
                            emacsvox-settings-integrations--choice-fourth
                            emacsvox-settings-integrations--choice-fifth
                            emacsvox-settings-integrations--choice-sixth))
                transient--suffixes :key (lambda (item) (oref item command)))))
    (emacsvox-transient--speak-button)))
(defun emacsvox-settings-integrations--choice-back ()
  "Cancel and return to the originating control."
  (interactive)
  (emacsvox-settings-integrations--return
   (car (emacsvox-settings-integrations--choice-entry))))
(defun emacsvox-settings-integrations--choice-apply (index)
  "Apply choice INDEX and return to the originating control."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((entry (emacsvox-settings-integrations--choice-entry))
         (value (car (nth index (nth 4 entry)))))
    (emacsvox-settings-integrations--return (car entry))
    (if (eq (car entry) 'emacsvox-settings-integrations--agent-session)
        (let ((emacsvox-aural-submission-lane 'main)
              (emacsvox-aural-submission-delivery-policy 'replaceable)
              (emacsvox-aural-submission-replacement-key 'speaker)
              (emacsvox-aural-submission-interruption-policy 'lane))
          (emacsvox-agent-shell--set-session-speech-level
           (emacsvox-settings-integrations--agent-source) value))
      (emacsvox-settings-integrations--set-option entry value))))
(defun emacsvox-settings-integrations--choice-help (object)
  "Explain choice OBJECT and its scope without applying it."
  (let* ((entry (emacsvox-settings-integrations--choice-entry))
         (choice (nth (1- (string-to-number (oref object key))) (nth 4 entry))))
    ;; Help recreates the menu on return.  Retain the browsed button, which
    ;; can differ from both the current value and the key requested for Help.
    (with-selected-window transient--window
      (when-let* ((button (button-at (point)))
                 (suffix (button-get button 'button-data)))
        (oset transient--prefix scope
              (plist-put (oref transient--prefix scope)
                         :integration-choice-help-key (oref suffix key)))))
    (with-help-window (help-buffer)
      (princ (emacsvox-settings-integrations--choice-heading))
      (princ "\n\n")
      (princ (cdr choice))
      (princ "\n\n")
      (princ (if (eq (car entry) 'emacsvox-settings-integrations--agent-session)
                 "Selecting this value changes only the captured session. Auto follows the foreground and background defaults."
               "Selecting this value changes the global default. Use w in the parent menu to save it for future sessions."))
      (princ "\n\n")
      (princ
       (pcase (nth 2 entry)
         ('emacsvox-org-table-after-movement-function
          "This controls speech after moving between Org table cells. Column headers come from the first row; row headers come from the first column. Buffer-local settings take precedence over this global default.")
         ('emacsvox-info-select-node-speak-chunk
          "This controls automatic speech after interactive Info node navigation. Screenful starts at point and uses the window height; it is not restricted to the visible text. Changing this default does not read the current node. Buffer-local settings take precedence.")
         ('emacsvox-agent-shell-input-activation
          "Automatic preserves ordinary inline prompt editing. Explicit keeps navigation letters active at the prompt: RET there or C-c i starts editing; C-c e returns to browsing and preserves your draft. Leaving input or submitting it also returns to browsing. The choice applies to existing and new shells; buffer-local overrides take precedence. Dedicated viewport editors keep normal editing. Browse mode protects the draft from typing and ordinary paste; incoming output and inserted source context can still arrive.")
         ('emacsvox-notmuch-search-completion-style
          "This controls successful asynchronous searches. Adaptive can read the selected result while results arrive, then announce the final count. After another command or leaving the search, it announces only a count. Counts normally use the notification stream; refresh feedback uses the primary stream and can be interrupted. Failures remain audible in every style.")
         ((or 'emacsvox-agent-shell-speak-thought-process
              'emacsvox-agent-shell-tool-output-verbosity)
          "The session speech level must allow this kind of feedback.")
         (_ "Permissions and errors remain controlled separately."))))
    (pop-to-buffer (help-buffer))
    (emacsvox-transient--submit-text
     (emacsvox-aural-source-substring (point-min) (point-max))
     (emacsvox-transient--menu-facts 'help 'command-menu-suspended)
     'inspection 'help)))
(defun emacsvox-settings-integrations--choice-restore-help-focus (&rest _)
  "Restore the browsed choice once after returning from its Help."
  (when (and transient--prefix (window-live-p transient--window)
             (eq (oref transient--prefix command) 'emacsvox-settings-integrations--choice))
    (when-let* ((key (plist-get (oref transient--prefix scope) :integration-choice-help-key)))
      (oset transient--prefix scope
            (plist-put (oref transient--prefix scope) :integration-choice-help-key nil))
      (with-selected-window transient--window
        (transient--goto-button
         (cl-find key transient--suffixes :key (lambda (item) (oref item key)) :test #'equal))))))
(advice-add 'transient--show :after
            #'emacsvox-settings-integrations--choice-restore-help-focus)
(defun emacsvox-settings-integrations--choice-first ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 0))
(defun emacsvox-settings-integrations--choice-second ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 1))
(defun emacsvox-settings-integrations--choice-third ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 2))
(defun emacsvox-settings-integrations--choice-fourth ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 3))
(defun emacsvox-settings-integrations--choice-fifth ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 4))
(defun emacsvox-settings-integrations--choice-sixth ()
  "Apply this choice." (interactive)
  (emacsvox-settings-integrations--choice-apply 5))
(transient-define-prefix emacsvox-settings-integrations--choice ()
  "Choose an option; Enter applies it and q cancels."
  [:description emacsvox-settings-integrations--choice-heading
   ("1" (lambda () (emacsvox-settings-integrations--choice-label 0))
    emacsvox-settings-integrations--choice-first
    :show-help emacsvox-settings-integrations--choice-help :transient transient--do-replace)
   ("2" (lambda () (emacsvox-settings-integrations--choice-label 1))
    emacsvox-settings-integrations--choice-second
    :show-help emacsvox-settings-integrations--choice-help :transient transient--do-replace)
   ("3" (lambda () (emacsvox-settings-integrations--choice-label 2))
    emacsvox-settings-integrations--choice-third
    :if emacsvox-settings-integrations--choice-third-p
    :show-help emacsvox-settings-integrations--choice-help :transient transient--do-replace)
   ("4" (lambda () (emacsvox-settings-integrations--choice-label 3))
    emacsvox-settings-integrations--choice-fourth
    :show-help emacsvox-settings-integrations--choice-help
    :if emacsvox-settings-integrations--choice-fourth-p :transient transient--do-replace)
   ("5" (lambda () (emacsvox-settings-integrations--choice-label 4))
    emacsvox-settings-integrations--choice-fifth
    :show-help emacsvox-settings-integrations--choice-help
    :if emacsvox-settings-integrations--choice-fifth-p :transient transient--do-replace)
   ("6" (lambda () (emacsvox-settings-integrations--choice-label 5))
    emacsvox-settings-integrations--choice-sixth
    :show-help emacsvox-settings-integrations--choice-help
    :if emacsvox-settings-integrations--choice-sixth-p :transient transient--do-replace)]
  ["Finish"
   ("q" "Cancel" emacsvox-settings-integrations--choice-back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--choice nil nil
                   :scope (emacsvox-aural-menu--context)))

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
  "Override automatic speech for this session; Auto follows focus defaults."
  (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-session))
(defun emacsvox-settings-integrations--agent-save ()
  "Save these global defaults for future sessions; exclude the session override."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-agent-shell))
(defun emacsvox-settings-integrations--agent-custom ()
  "Edit additional Agent Shell options in Customize, with its own Save action."
  (interactive)
  (require 'emacsvox-agent-shell)
  (emacsvox-settings--custom 'emacsvox-agent-shell 'emacsvox-settings-integrations--agent-custom))

(defun emacsvox-settings-integrations--agent-foreground ()
  "Choose automatic feedback for focused sessions using Auto." (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-foreground))

(defun emacsvox-settings-integrations--agent-background ()
  "Choose automatic feedback for unfocused sessions using Auto." (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-background))

(defun emacsvox-settings-integrations--agent-thoughts ()
  "Choose thought speech or cues when the session speech level allows thoughts." (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-thoughts))

(defun emacsvox-settings-integrations--agent-tools ()
  "Choose tool feedback when the session speech level allows tool output." (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-tools))

(defun emacsvox-settings-integrations--agent-permissions ()
  "Speak permission requests as soon as they arrive." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-permissions))

(defun emacsvox-settings-integrations--agent-calls ()
  "Announce tool calls when the session speech level allows tool feedback." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-calls))

(defun emacsvox-settings-integrations--agent-processing ()
  "Signal processing start and completion, subject to the session speech level." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-processing))

(defun emacsvox-settings-integrations--agent-automatic-limit ()
  "Set the automatic speech limit; Shift arrows change it by 100 characters.
Limit automatic speech length; explicit response inspection stays complete.
Enter a positive character count or none for complete automatic content.
Provider-controlled permission fields and tool labels remain concise." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-automatic-limit))

(defun emacsvox-settings-integrations--agent-line-limit ()
  "Set the line speech limit; Shift arrows change it by 100 characters.
Limit long-line navigation speech and announce the omitted count.
Enter a positive character count or none to use the core long-line policy.
Explicit response and block-reading commands remain complete." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-line-limit))

(defun emacsvox-settings-integrations--agent-block-limit ()
  "Set the block speech limit; Shift arrows change it by 100 characters.
Limit the body read after block navigation; block labels stay concise.
Enter a positive character count or none for the complete body." (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--agent-block-limit))

(defun emacsvox-settings-integrations--agent-input ()
  "Choose automatic or explicit activation of the inline Agent Shell prompt.
Apply to existing and new shells, preserving local overrides and drafts.
Explicit uses RET at the prompt or C-c i to edit, and C-c e to browse.
Viewport editors retain normal editing. Use w to save for future sessions."
  (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--agent-input))

(transient-define-prefix emacsvox-settings-integrations--agent ()
  "Control Agent Shell speech, separating session overrides and global defaults."
  ["Captured session (temporary)"
   ("s" (lambda () (emacsvox-settings-integrations--agent-session-label))
    emacsvox-settings-integrations--agent-session
    :inapt-if-not emacsvox-settings-integrations--agent-p :transient transient--do-suspend)]
  ["Global speech defaults; w saves"
   ("f" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-foreground))
    emacsvox-settings-integrations--agent-foreground :transient transient--do-suspend)
   ("b" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-background))
    emacsvox-settings-integrations--agent-background :transient transient--do-suspend)
   ("t" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-thoughts))
    emacsvox-settings-integrations--agent-thoughts :transient transient--do-suspend)
   ("o" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-tools))
    emacsvox-settings-integrations--agent-tools :transient transient--do-suspend)
   ("p" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-permissions))
    emacsvox-settings-integrations--agent-permissions :transient t)
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-calls))
    emacsvox-settings-integrations--agent-calls :transient t)
   ("l" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-processing))
    emacsvox-settings-integrations--agent-processing :transient t)
  ]
  ["Shared table reading"
   ("T" "Tables: reading, navigation and scoped defaults" emacsvox-table-settings :transient transient--do-stack)]
  ["Global input preference; w saves"
   ("i" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-input))
    emacsvox-settings-integrations--agent-input :transient transient--do-suspend)]
  ["Global reading limits"
   ("a" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-automatic-limit))
    emacsvox-settings-integrations--agent-automatic-limit :transient t)
   ("n" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-line-limit))
    emacsvox-settings-integrations--agent-line-limit :transient t)
   ("k" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--agent-block-limit))
    emacsvox-settings-integrations--agent-block-limit :transient t)
  ]
  ["Defaults and advanced settings"
   ("w" "Save displayed global defaults" emacsvox-settings-integrations--agent-save :transient t)
   ("A" "Advanced Agent Shell settings (Customize)" emacsvox-settings-integrations--agent-custom :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--agent nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--org-feedback ()
  "Choose what to read after moving between Org table cells.
Change the global default; buffer-local settings still take precedence."
  (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--org-feedback))
(defun emacsvox-settings-integrations--org-save ()
  "Save global table feedback for future sessions; preserve local overrides."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-org))
(defun emacsvox-settings-integrations--org-tables ()
  "Edit Org table layout and behavior in Customize, with its own Save action."
  (interactive)
  (require 'org-table)
  (emacsvox-settings--custom 'org-table 'emacsvox-settings-integrations--org-tables))
(defun emacsvox-settings-integrations--org-custom ()
  "Edit additional Org speech options in Customize, with its own Save action."
  (interactive)
  (require 'emacsvox-org)
  (emacsvox-settings--custom 'emacsvox-org 'emacsvox-settings-integrations--org-custom))
(transient-define-prefix emacsvox-settings-integrations--org ()
  "Choose Org table feedback and reach its structured settings."
  ["Org table feedback (global); w saves"
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--org-feedback))
    emacsvox-settings-integrations--org-feedback :transient transient--do-suspend)]
  ["Shared table reading"
   ("T" "Tables: reading, navigation and scoped defaults" emacsvox-table-settings :transient transient--do-stack)]
  ["Structured and advanced settings"
   ("t" "Org table options (Customize)" emacsvox-settings-integrations--org-tables :transient transient--do-suspend)
   ("A" "Advanced Emacsvox Org settings (Customize)" emacsvox-settings-integrations--org-custom :transient transient--do-suspend)]
  ["Save"
   ("w" "Save table feedback default" emacsvox-settings-integrations--org-save :transient t)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--org nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--markdown-auto ()
  "Toggle automatic reading mode for newly initialized Markdown buffers.
Reading mode removes literal markup from speech while retaining voice cues.
This changes the global default without switching existing buffers. Use
`emacsvox-markdown-reading-mode' to switch the current buffer. Local overrides
take precedence. Use w to save the default for future sessions."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--markdown-auto))
(defun emacsvox-settings-integrations--markdown-save ()
  "Save automatic Markdown reading mode for future sessions.
Existing buffers keep their current reading mode and local overrides."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-markdown))
(transient-define-prefix emacsvox-settings-integrations--markdown ()
  "Control automatic Markdown reading mode."
  ["Markdown default (global); w saves"
   ("r" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--markdown-auto))
    emacsvox-settings-integrations--markdown-auto :transient t)
   ("w" "Save automatic reading default" emacsvox-settings-integrations--markdown-save :transient t)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--markdown nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--info-chunk ()
  "Choose automatic speech after interactive Info node navigation.
Browse a screenful from point or the entire node without changing the default
until selecting a choice. Changing it does not read the current node.
Buffer-local overrides take precedence. Use w to save for future sessions."
  (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--info-chunk))
(defun emacsvox-settings-integrations--info-save ()
  "Save the global Info node reading amount for future sessions.
Buffer-local overrides remain unchanged."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-info))
(transient-define-prefix emacsvox-settings-integrations--info ()
  "Control automatic speech when entering Info nodes."
  ["Info default (global); w saves"
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--info-chunk))
    emacsvox-settings-integrations--info-chunk :transient transient--do-suspend)
   ("w" "Save node reading default" emacsvox-settings-integrations--info-save :transient t)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--info nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--eww-autospeak ()
  "Toggle global automatic speech during EWW section navigation."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--eww-autospeak))
(defun emacsvox-settings-integrations--eww-images ()
  "Toggle image suppression and apply it to subsequent SHR rendering."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--eww-images)
  ;; Match EWW speech setup without reloading a page or replacing local overrides.
  (set-default 'shr-inhibit-images (default-value 'emacsvox-eww-inhibit-images)))
(defun emacsvox-settings-integrations--eww-save ()
  "Save displayed EWW defaults through Customize."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-eww))
(defun emacsvox-settings-integrations--eww-custom ()
  "Open advanced EWW speech settings and return here."
  (interactive)
  (require 'emacsvox-eww)
  (emacsvox-settings--custom 'emacsvox-eww 'emacsvox-settings-integrations--eww-custom))
(transient-define-prefix emacsvox-settings-integrations--eww ()
  "Control EWW automatic speech and image handling."
  ["EWW defaults (global); w saves"
   ("s" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--eww-autospeak))
    emacsvox-settings-integrations--eww-autospeak :transient t)
   ("i" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--eww-images))
    emacsvox-settings-integrations--eww-images :transient t)]
  ["Defaults and advanced settings"
   ("w" "Save displayed EWW defaults" emacsvox-settings-integrations--eww-save :transient t)
   ("A" "Advanced EWW settings (Customize)" emacsvox-settings-integrations--eww-custom :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--eww nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-settings-integrations--custom-option (option command)
  "Open the structured OPTION editor and return to menu COMMAND."
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (customize-option option)
     (let ((buffer (window-buffer (selected-window))))
       (with-current-buffer buffer
         (use-local-map (copy-keymap (current-local-map)))
         (local-set-key (kbd "q") #'emacsvox-settings--custom-quit))
       buffer)) command))
(defun emacsvox-settings-integrations--notmuch-completion ()
  "Choose feedback for successful Notmuch searches; failures remain audible."
  (interactive)
  (emacsvox-settings-integrations--choose 'emacsvox-settings-integrations--notmuch-completion))
(defun emacsvox-settings-integrations--notmuch-field-characters ()
  "Set the per-field character limit; Shift arrows change it by 100.
Limit characters read from each automatic mail field.
Enter a positive count or none; total presentation limits still apply."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--notmuch-field-characters))
(defun emacsvox-settings-integrations--notmuch-field-bytes ()
  "Set the per-field UTF-8 byte limit; Shift arrows change it by 100.
Limit UTF-8 bytes prepared and read from each automatic mail field.
Enter a positive count or none; total presentation limits still apply."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--notmuch-field-bytes))
(defun emacsvox-settings-integrations--notmuch-total-characters ()
  "Set the total character limit; Shift arrows change it by 100.
Limit characters in automatic mail feedback, including truncation notices.
Enter a positive count or none; the byte limit still applies."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--notmuch-total-characters))
(defun emacsvox-settings-integrations--notmuch-total-bytes ()
  "Set the total UTF-8 byte limit; Shift arrows change it by 100.
Limit UTF-8 bytes in automatic mail feedback, including truncation notices.
Enter a positive count or none; the character limit still applies."
  (interactive)
  (emacsvox-settings-integrations--edit 'emacsvox-settings-integrations--notmuch-total-bytes))
(defun emacsvox-settings-integrations--notmuch-search-fields ()
  "Choose which search-result fields are spoken and their order.
The structured editor has its own Apply and Save actions."
  (interactive)
  (require 'emacsvox-notmuch)
  (emacsvox-settings-integrations--custom-option
   'emacsvox-notmuch-search-result-fields 'emacsvox-settings-integrations--notmuch-search-fields))
(defun emacsvox-settings-integrations--notmuch-show-fields ()
  "Choose which message fields are spoken and their order.
The structured editor has its own Apply and Save actions."
  (interactive)
  (require 'emacsvox-notmuch)
  (emacsvox-settings-integrations--custom-option
   'emacsvox-notmuch-show-message-fields 'emacsvox-settings-integrations--notmuch-show-fields))
(defun emacsvox-settings-integrations--notmuch-search-icons ()
  "Map search status tags to fallback sounds or silence instead of spoken tags.
Semantic status cues take precedence when enabled.
This editor has its own Save action."
  (interactive)
  (require 'emacsvox-notmuch)
  (emacsvox-settings-integrations--custom-option
   'emacsvox-notmuch-search-status-icons 'emacsvox-settings-integrations--notmuch-search-icons))
(defun emacsvox-settings-integrations--notmuch-show-icons ()
  "Map message status tags to fallback sounds or silence instead of spoken tags.
Semantic status cues take precedence when enabled.
This editor has its own Save action."
  (interactive)
  (require 'emacsvox-notmuch)
  (emacsvox-settings-integrations--custom-option
   'emacsvox-notmuch-show-status-icons 'emacsvox-settings-integrations--notmuch-show-icons))
(defun emacsvox-settings-integrations--notmuch-presentation ()
  "Configure semantic mail status sounds in Presentation Options."
  (interactive)
  (require 'emacsvox-aural-feature-fragments)
  (emacsvox-aural-menu--open-browser
   #'emacsvox-aural-list-feature-fragments
   'emacsvox-settings-integrations--notmuch-presentation))
(defun emacsvox-settings-integrations--notmuch-save ()
  "Save completion and reading defaults for future sessions.
Structured field and status editors have their own Save actions."
  (interactive)
  (emacsvox-settings-integrations--save-options 'emacsvox-notmuch))
(defun emacsvox-settings-integrations--notmuch-custom ()
  "Edit additional mail speech options in Customize, with its own Save action."
  (interactive)
  (require 'emacsvox-notmuch)
  (emacsvox-settings--custom 'emacsvox-notmuch 'emacsvox-settings-integrations--notmuch-custom))
(transient-define-prefix emacsvox-settings-integrations--notmuch ()
  "Control mail feedback and open its structured field and cue editors."
  ["Spoken content: save inside each editor"
   ("s" "Spoken search fields (ordered list)" emacsvox-settings-integrations--notmuch-search-fields :transient transient--do-suspend)
   ("m" "Spoken message fields (ordered list)" emacsvox-settings-integrations--notmuch-show-fields :transient transient--do-suspend)]
  ["Status feedback (global)"
   ("c" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--notmuch-completion))
    emacsvox-settings-integrations--notmuch-completion :transient transient--do-suspend)
   ("i" "Search status tags and fallback cues (separate Save)" emacsvox-settings-integrations--notmuch-search-icons :transient transient--do-suspend)
   ("I" "Message status tags and fallback cues (separate Save)" emacsvox-settings-integrations--notmuch-show-icons :transient transient--do-suspend)
   ("p" "Semantic status cues (Presentation Options; separate Save)" emacsvox-settings-integrations--notmuch-presentation :transient transient--do-suspend)]
  ["Reading limits (global); w saves"
   ("f" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--notmuch-field-characters))
    emacsvox-settings-integrations--notmuch-field-characters :transient t)
   ("b" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--notmuch-field-bytes))
    emacsvox-settings-integrations--notmuch-field-bytes :transient t)
   ("t" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--notmuch-total-characters))
    emacsvox-settings-integrations--notmuch-total-characters :transient t)
   ("B" (lambda () (emacsvox-settings-integrations--label 'emacsvox-settings-integrations--notmuch-total-bytes))
    emacsvox-settings-integrations--notmuch-total-bytes :transient t)]
  ["Defaults and advanced settings"
   ("w" "Save completion and reading defaults" emacsvox-settings-integrations--notmuch-save :transient t)
   ("A" "Advanced Notmuch settings (Customize)" emacsvox-settings-integrations--notmuch-custom :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" emacsvox-settings-integrations--back :transient transient--do-replace)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations--notmuch nil nil :scope (emacsvox-aural-menu--context)))

;;;###autoload
(transient-define-prefix emacsvox-settings-integrations ()
  "Find integration settings and existing local speech controls."
  ["Captured buffer"
   ("s" (lambda () (emacsvox-settings-integrations--control-label))
    emacsvox-settings-integrations--control :inapt-if-not emacsvox-settings-integrations--control-p :transient t)
   ("c" (lambda () (emacsvox-settings-integrations--current-label)) emacsvox-settings-integrations--current
    :inapt-if-not emacsvox-settings-integrations--group-p :transient transient--do-suspend)]
  ["All integrations"
   ("a" "Choose integration settings" emacsvox-settings-integrations--all :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-integrations nil nil :scope (emacsvox-aural-menu--context)))
(provide 'emacsvox-settings-integrations)
;;; emacsvox-settings-integrations.el ends here
