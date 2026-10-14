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

(defconst emacsvox-settings-integrations--catalogue
  '((comint "Shell/comint" comint emacsvox-comint nil)
    (agent "Agent Shell" agent-shell emacsvox-agent-shell emacsvox-agent-shell)
    (eat "EAT terminals" eat emacsvox-eat-core emacsvox-eat)
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
          ((derived-mode-p 'eat-mode 'emacsvox-eat-review-mode) 'eat)
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
    (if (eq kind 'comint)
        (transient-setup
         'emacsvox-settings-integrations--comint nil nil
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
