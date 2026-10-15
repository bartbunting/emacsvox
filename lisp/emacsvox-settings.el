;;; emacsvox-settings.el --- Settings discovery -*- lexical-binding: t; -*-

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
;; Search settings and action destinations with captured source context.
;;; Code:
(require 'emacsvox-aural-menu)
(require 'cus-edit)

(defconst emacsvox-settings--destinations
  '(("Aural Doctor and recovery" emacsvox-settings-workflows emacsvox-settings-diagnostics "d")
    ("Spatial capabilities" emacsvox-settings-workflows emacsvox-settings-diagnostics "s")
    ("Main speech diagnostics" emacsvox-settings-workflows emacsvox-settings-diagnostics "m")
    ("Notification speech diagnostics" emacsvox-settings-workflows emacsvox-settings-diagnostics "n")
    ("Diagnostic logging" emacsvox-settings-workflows emacsvox-settings-diagnostics "l")
    ("Tune the named voice at point" emacsvox-settings-workflows emacsvox-settings-feedback "t")
    ("Combined feedback rules" emacsvox-settings-workflows emacsvox-settings-presentation "o")
    ("Training explanations" emacsvox-settings-workflows emacsvox-settings-presentation "t")
    ("Semantic vocabulary reference" emacsvox-settings-workflows emacsvox-settings-presentation "h")
    ("Edit current and recent feedback" emacsvox-settings-workflows emacsvox-settings-feedback "c")
    ("Presentation features and scoped rules" emacsvox-settings-workflows emacsvox-settings-presentation "f")
    ("Saved setups, profiles and drafts" emacsvox-settings-workflows emacsvox-settings-setups "p")
    ("Integration speech settings" emacsvox-settings-integrations emacsvox-settings-integrations "a")
    ("Shell/comint automatic output speech" emacsvox-settings-integrations emacsvox-settings-integrations--comint "s")
    ("Shell/comint background output monitoring" emacsvox-settings-integrations emacsvox-settings-integrations--comint "b")
    ("EAT automatic foreground speech" emacsvox-settings-integrations emacsvox-settings-integrations--eat "s")
    ("EAT background cues and unread count" emacsvox-settings-integrations emacsvox-settings-integrations--eat "b")
    ("EAT prompt feedback" emacsvox-settings-integrations emacsvox-settings-integrations--eat "p")
    ("EAT automatic feedback detail" emacsvox-settings-integrations emacsvox-settings-integrations--eat "d")
    ("Agent session speech level" emacsvox-settings-integrations emacsvox-settings-integrations--agent "s")
    ("Agent foreground speech default" emacsvox-settings-integrations emacsvox-settings-integrations--agent "f")
    ("Agent background speech default" emacsvox-settings-integrations emacsvox-settings-integrations--agent "b")
    ("Agent thought feedback" emacsvox-settings-integrations emacsvox-settings-integrations--agent "t")
    ("Agent tool output verbosity" emacsvox-settings-integrations emacsvox-settings-integrations--agent "o")
    ("Agent permission feedback" emacsvox-settings-integrations emacsvox-settings-integrations--agent "p")
    ("Agent tool call announcements" emacsvox-settings-integrations emacsvox-settings-integrations--agent "c")
    ("Agent processing lifecycle cues" emacsvox-settings-integrations emacsvox-settings-integrations--agent "l")
    ("Agent automatic content limit" emacsvox-settings-integrations emacsvox-settings-integrations--agent "a")
    ("Agent line navigation limit" emacsvox-settings-integrations emacsvox-settings-integrations--agent "n")
    ("Agent block navigation limit" emacsvox-settings-integrations emacsvox-settings-integrations--agent "k")
    ("Notmuch search completion" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "c")
    ("Notmuch per-field characters" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "f")
    ("Notmuch per-field utf-8 bytes" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "b")
    ("Notmuch total characters" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "t")
    ("Notmuch total utf-8 bytes" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "B")
    ("Notmuch spoken search fields (ordered list)" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "s")
    ("Notmuch spoken message fields (ordered list)" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "m")
    ("Notmuch search status tags and fallback cues" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "i")
    ("Notmuch message status tags and fallback cues" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "I")
    ("Notmuch semantic status cues" emacsvox-settings-integrations emacsvox-settings-integrations--notmuch "p")
    ("EWW section navigation autospeak" emacsvox-settings-integrations emacsvox-settings-integrations--eww "s")
    ("EWW suppress images" emacsvox-settings-integrations emacsvox-settings-integrations--eww "i")
    ("Org table movement feedback" emacsvox-settings-integrations emacsvox-settings-integrations--org "c")
    ("Changed settings, saved defaults and drafts" emacsvox-settings-workflows emacsvox-settings-setups "c")
    ("Speech rate" emacsvox-aural-menu emacsvox-aural-menu-speech "r")
    ("Punctuation levels and profiles" emacsvox-aural-menu emacsvox-aural-menu-punctuation "p")
    ("Punctuation pronunciations" emacsvox-aural-menu emacsvox-aural-menu-punctuation "e")
    ("Indentation presentation" emacsvox-indentation emacsvox-indentation "p")
    ("Indentation pitch and duration" emacsvox-indentation emacsvox-indentation-tone "b")
    ("Capitalization indication and camel case" emacsvox-capitalization emacsvox-capitalization "i")
    ("Capital-letter beep" emacsvox-capitalization emacsvox-capitalization "l")
    ("All-caps beep" emacsvox-capitalization emacsvox-capitalization "a")
    ("Character echo" emacsvox-interaction emacsvox-interaction "c")
    ("Word echo" emacsvox-interaction emacsvox-interaction "w")
    ("Completed-line echo" emacsvox-interaction emacsvox-interaction "l")
    ("Point indication and presentation" emacsvox-interaction emacsvox-interaction "i")
    ("Spoken messages" emacsvox-interaction emacsvox-interaction "m")
    ("Delayed phonetics" emacsvox-interaction emacsvox-interaction "d")
    ("Menu navigation and announcements" emacsvox-aural-menu emacsvox-aural-menu-navigation "m")
    ("Output volumes" emacsvox-aural-menu emacsvox-aural-menu-sounds "t")
    ("Line and boundary cues" emacsvox-aural-menu emacsvox-aural-menu-line-cues "b")
    ("Notification routing and history" emacsvox-output-settings emacsvox-output-settings "r")
    ("Spatial output and separation" emacsvox-output-settings emacsvox-output-settings "d")
    ("Sound packs" emacsvox-aural-menu emacsvox-aural-menu-sounds "p")
    ("Voices and engines" emacsvox-aural-menu emacsvox-aural-menu-voices "b")
    ("Voice palettes" emacsvox-aural-menu emacsvox-aural-menu-voices "p"))
  "Search labels, defining features, destination prefixes, and selected keys.")

(defconst emacsvox-settings--actions
  '(("Change this feedback" emacsvox-settings-workflows emacsvox-settings-feedback "c")
    ("Browse voices" emacsvox-aural-menu emacsvox-aural-menu-voices "b")
    ("Preferred speech engine" emacsvox-aural-menu emacsvox-aural-menu-voices "e")
    ("Speech rate" emacsvox-aural-menu emacsvox-aural-menu-speech "r")
    ("Punctuation" emacsvox-aural-menu emacsvox-aural-menu-punctuation "e")
    ("Audio output" emacsvox-aural-menu emacsvox-aural-menu-sounds "t")
    ("Review notifications" emacsvox-output-settings emacsvox-output-settings "h")
    ("Return to source item" emacsvox-aural-menu emacsvox-aural-menu "b")
    ("Resume unfinished changes" emacsvox-settings-workflows emacsvox-settings-setups "d")
    ("Explain this item" emacsvox-settings-workflows emacsvox-settings-feedback "x")
    ("Choose a voice for this item" emacsvox-settings-workflows emacsvox-settings-feedback "v")
    ("Edit the named voice used here" emacsvox-settings-workflows emacsvox-settings-feedback "t")
    ("Change a sound for this item" emacsvox-settings-workflows emacsvox-settings-feedback "e")
    ("Your feedback rules" emacsvox-settings-workflows emacsvox-settings-presentation "o")
    ("Recent feedback" emacsvox-settings-workflows emacsvox-settings-feedback "h")
    ("Presentation profiles" emacsvox-settings-workflows emacsvox-settings-setups "p")
    ("Voice palettes" emacsvox-aural-menu emacsvox-aural-menu-voices "p")
    ("Voice Workbench" emacsvox-aural-menu emacsvox-aural-menu-voices "w")
    ("Presentation options" emacsvox-settings-workflows emacsvox-settings-presentation "f")
    ("Current buffer rules" emacsvox-settings-workflows emacsvox-settings-presentation "b")
    ("Semantic vocabulary" emacsvox-settings-workflows emacsvox-settings-presentation "h")
    ("Sound packs" emacsvox-aural-menu emacsvox-aural-menu-sounds "p")
    ("Spatial capabilities" emacsvox-settings-workflows emacsvox-settings-diagnostics "s")
    ("Spatial settings" emacsvox-output-settings emacsvox-output-settings "d")
    ("Explain feedback as you navigate" emacsvox-settings-workflows emacsvox-settings-presentation "t")
    ("Aural Doctor" emacsvox-settings-workflows emacsvox-settings-diagnostics "d")
    ("Read the Emacsvox manual" emacsvox-aural-menu emacsvox-aural-menu "i"))
  "Canonical action labels and focused destinations.")

(defconst emacsvox-settings--search-aliases
  '(("Capital-letter beep" "caps beep" "capital beep")
    ("All-caps beep" "allcaps beep" "all caps beep" "caps beep")
    ("Explain this item" "Feedback for this item")
    ("Recent feedback" "Recent aural feedback"))
  "Additional search terms for settings, displayed under their original labels.")

(defun emacsvox-settings--search-matches (string table predicate)
  "Return labels in TABLE matching STRING or an alias, respecting PREDICATE."
  (let ((case-fold-search t)
        (pattern (regexp-quote string)))
    (cl-remove-if-not
     (lambda (label)
       (cl-some (lambda (term) (string-match-p pattern term))
                (cons label (cdr (assoc label emacsvox-settings--search-aliases)))))
     (all-completions "" table predicate))))

(defun emacsvox-settings--search-all (string table predicate _point)
  "Complete STRING against settings labels and aliases in TABLE with PREDICATE."
  (let ((matches (emacsvox-settings--search-matches string table predicate)))
    (when matches (nconc matches 0))))

(defun emacsvox-settings--search-try (string table predicate point)
  "Complete a unique setting in TABLE, keeping ambiguous STRING at POINT."
  (let ((matches (emacsvox-settings--search-matches string table predicate)))
    (cond
     ((null matches) nil)
     ((test-completion string matches) t)
     ((null (cdr matches)) (cons (car matches) (length (car matches))))
     (t (cons string point)))))

(defun emacsvox-settings--open (entry)
  "Open settings ENTRY with the current captured source and scope."
  (let* ((context (emacsvox-aural-menu--context))
         (command (nth 2 entry)))
    (emacsvox-aural-menu--source context)
    (require (nth 1 entry))
    (transient-setup command nil nil :scope
                     (if (memq command '(emacsvox-indentation emacsvox-indentation-tone))
                         (plist-get context :settings) context))
    (transient--show)
    (with-selected-window transient--window
      (transient--goto-button
       (cl-find (nth 3 entry) transient--suffixes
                :key (lambda (suffix) (oref suffix key)) :test #'equal)))))
(defun emacsvox-settings--find (prompt entries)
  "Read a destination from ENTRIES with PROMPT, then focus its control."
  (let ((completion-ignore-case t)
        ;; Keep the completion frontend, but give these searches consistent matching.
        (completion-styles '(emacsvox-settings))
        (completion-category-defaults nil)
        (completion-category-overrides nil)
        (completion-styles-alist
         (cons '(emacsvox-settings emacsvox-settings--search-try
                 emacsvox-settings--search-all "Find settings by label or alias.")
               completion-styles-alist)))
    (emacsvox-settings--open
     (or (assoc-string
          (minibuffer-with-setup-hook
              (lambda ()
                ;; Preserve the frontend's other bindings and shared maps.
                (use-local-map (copy-keymap (current-local-map)))
                (local-set-key (kbd "SPC") #'self-insert-command))
            (completing-read prompt entries nil t))
          entries t)
         (user-error "Choose a destination")))))

;;;###autoload
(defun emacsvox-settings-search ()
  "Find a focused setting and select its control without activating it."
  (interactive)
  (emacsvox-settings--find "Emacsvox setting: " emacsvox-settings--destinations))

;;;###autoload
(defun emacsvox-settings-search-actions ()
  "Find an action and select its focused-menu control without activating it.
Match partial names without case sensitivity.  RET accepts a search result;
another RET activates its control.  q returns to the menu where you searched."
  (interactive)
  (emacsvox-settings--find "Emacsvox action: " emacsvox-settings--actions))
(defun emacsvox-settings--speech ()
  "Open speech settings for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Speech rate" emacsvox-settings--destinations)))
(defun emacsvox-settings--indentation ()
  "Open indentation for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Indentation presentation" emacsvox-settings--destinations)))
(defun emacsvox-settings--interaction ()
  "Open typing and interaction for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Character echo" emacsvox-settings--destinations)))
(defun emacsvox-settings--capitalization ()
  "Open capitalization for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Capitalization indication and camel case" emacsvox-settings--destinations)))
(defun emacsvox-settings--mode-group ()
  "Return the captured source mode's actual Customize group, if known."
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (custom-group-of-mode major-mode)))
(defun emacsvox-settings--custom-quit ()
  "Use Customize's normal finish action, then return to the originating menu."
  (interactive)
  (let ((return emacsvox-aural-ui--return-function))
    (Custom-buffer-done)
    (when return (funcall return))))
(defun emacsvox-settings--custom (group command)
  "Open Customize GROUP and return to menu suffix COMMAND with q."
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (customize-group group)
     (let ((buffer (window-buffer (selected-window))))
       (with-current-buffer buffer
         (use-local-map (copy-keymap (current-local-map)))
         (local-set-key (kbd "q") #'emacsvox-settings--custom-quit))
       buffer)) command))
(defun emacsvox-settings--mode ()
  "Open the captured major mode's Customize group."
  (interactive)
  (emacsvox-settings--custom
   (or (emacsvox-settings--mode-group) (user-error "This mode has no known Customize group"))
   'emacsvox-settings--mode))
(defun emacsvox-settings--advanced ()
  "Open the complete Emacsvox Customize group."
  (interactive)
  (emacsvox-settings--custom 'emacsvox 'emacsvox-settings--advanced))
(defun emacsvox-settings--buffer-title ()
  "Describe the captured buffer and its major mode."
  (let ((source (emacsvox-aural-menu--source (emacsvox-aural-menu--context))))
    (format "Settings for %s (%s)" (buffer-name source)
            (buffer-local-value 'major-mode source))))
;;;###autoload
(transient-define-prefix emacsvox-settings-buffer ()
  "Find settings relevant to the captured source buffer."
  [:description emacsvox-settings--buffer-title
   ("s" "Speech rate and punctuation" emacsvox-settings--speech :transient transient--do-stack)
   ("i" "Indentation" emacsvox-settings--indentation :transient transient--do-stack)
   ("t" "Typing, point, and interaction" emacsvox-settings--interaction :transient transient--do-stack)
   ("c" "Capitalization" emacsvox-settings--capitalization :transient transient--do-stack)
   ("d" "Changed settings and drafts" emacsvox-settings-changes :transient transient--do-suspend)
   ("j" "Integration speech settings" emacsvox-settings-integrations :transient transient--do-stack)
   ("m" "Major-mode settings (Customize)" emacsvox-settings--mode :inapt-if-not emacsvox-settings--mode-group :transient transient--do-suspend)]
  ["Discover more"
   ("/" "Find an Emacsvox setting" emacsvox-settings-search :transient transient--do-stack)
   ("a" "Find an action" emacsvox-settings-search-actions :transient transient--do-suspend)
   ("A" "Advanced Emacsvox settings (Customize)" emacsvox-settings--advanced :transient transient--do-suspend)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let ((context (copy-sequence (emacsvox-aural-menu--context))))
    ;; Buffer discovery starts locally without changing the parent's scope flag.
    (setq context (plist-put context :settings
                             (cons (emacsvox-aural-menu--source context) nil)))
    (transient-setup 'emacsvox-settings-buffer nil nil :scope context)))
(provide 'emacsvox-settings)
;;; emacsvox-settings.el ends here
