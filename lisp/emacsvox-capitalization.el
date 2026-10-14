;;; emacsvox-capitalization.el --- Capitalization settings and cue drafts -*- lexical-binding: t; -*-

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
;; Buffer/global reading options and two retained global cue drafts.
;; Save cue overrides through the existing personal-rule store.

;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-preview)

(defvar emacsvox-capitalization--drafts (make-hash-table :test #'eq)
  "Retained global cue drafts, keyed by capitalization kind.")

(defun emacsvox-capitalization--value (symbol)
  "Read SYMBOL in the selected settings scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (if (cdr (plist-get context :settings)) (default-value symbol)
      (buffer-local-value symbol source))))

(defun emacsvox-capitalization--say (text)
  "Announce TEXT as replaceable menu feedback."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'capitalization 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-capitalization--set (symbol value)
  "Set SYMBOL to VALUE using the captured buffer/global scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (global (cdr (plist-get context :settings))))
    (with-current-buffer source
      (if (eq symbol 'emacsvox-capitalization-presentation)
          (emacsvox-set-capitalization-presentation value global)
        (when global (set-default symbol value))
        (set (make-local-variable symbol) value))
      (when (process-live-p tts-speaker-process) (tts--protocol-sync)))))

(defun emacsvox-capitalization--indication ()
  "Toggle capitalization indication in the selected scope."
  (interactive)
  (let ((value (not (emacsvox-capitalization--value 'tts-caps))))
    (emacsvox-capitalization--set 'tts-caps value)
    (emacsvox-capitalization--say (if value "Indication on" "Indication off"))))

(defun emacsvox-capitalization--split ()
  "Toggle camel-case splitting independently of indication."
  (interactive)
  (let ((value (not (emacsvox-capitalization--value 'tts-split-caps))))
    (emacsvox-capitalization--set 'tts-split-caps value)
    (emacsvox-capitalization--say (if value "Split camel case on" "Split camel case off"))))

(defun emacsvox-capitalization--presentation ()
  "Choose spoken, tone, combined, personal-rule, or no presentation."
  (interactive)
  (let* ((choices '(("Spoken" . spoken) ("Tone" . tone)
                    ("Spoken and tone" . spoken-tone) ("Personal rules" . custom)
                    ("None" . none)))
         (selected (cdr (assoc (completing-read "Capitalization presentation: " choices nil t)
                               choices))))
    (emacsvox-capitalization--set 'emacsvox-capitalization-presentation selected)
    (emacsvox-capitalization--say (car (rassq selected choices)))))

(defun emacsvox-capitalization--preview ()
  "Read representative text using the displayed settings and current rules."
  (interactive)
  (let ((caps (emacsvox-capitalization--value 'tts-caps))
        (split (emacsvox-capitalization--value 'tts-split-caps))
        (presentation (emacsvox-capitalization--value 'emacsvox-capitalization-presentation)))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
      (let ((tts-caps caps) (tts-split-caps split)
            (emacsvox-capitalization-presentation presentation))
        (tts-speak "Capital camelCase NASA")))))

(defun emacsvox-capitalization--save ()
  "Save the three displayed reading options as startup defaults."
  (interactive)
  (let ((values (mapcar (lambda (symbol) (cons symbol (emacsvox-capitalization--value symbol)))
                        '(tts-caps tts-split-caps emacsvox-capitalization-presentation))))
    (dolist (entry values) (customize-save-variable (car entry) (cdr entry)))
    (emacsvox-capitalization--say "Saved capitalization defaults. Buffer overrides still apply.")))

(defun emacsvox-capitalization--tone-id (kind)
  "Return the bundled tone resource for KIND."
  (if (eq kind 'capital) 'capital-letter-tone 'capital-all-caps-tone))

(defun emacsvox-capitalization--rule-id (kind presentation)
  "Return the personal cue rule identifier for KIND and PRESENTATION."
  (intern (format "settings-%s-%s" kind presentation)))

(defun emacsvox-capitalization--rules (kind values)
  "Build the two personal tone overrides for KIND using VALUES, or none."
  (when values
    (mapcar
     (lambda (presentation)
       (let* ((stem (if (eq kind 'capital) "capital" "all-caps"))
              (action (intern (format "core-%s-%s-action" stem
                                      (if (eq presentation 'tone) "tone" "spoken-tone-tone")))))
         (list :id (emacsvox-capitalization--rule-id kind presentation)
               :match (list :event 'capitalization-located :capitalization-kind kind
                            :capitalization-presentation presentation)
               :render (list :before
                             (list :anchor 'run :remove (list action)
                                   :append (list (list :id action :kind 'tone
                                                       :pitch (car values) :duration (cdr values)
                                                       :audio-mode 'insert :anchor 'run)))))))
     '(tone spoken-tone))))

(defun emacsvox-capitalization--saved (kind)
  "Read only this menu's personal rules for KIND."
  (cl-remove-if-not
   (lambda (rule) (memq (plist-get rule :id)
                        (mapcar (lambda (p) (emacsvox-capitalization--rule-id kind p))
                                '(tone spoken-tone))))
   emacsvox-aural-user-rules))

(defun emacsvox-capitalization--draft (kind)
  "Resume KIND's draft, checking for externally changed or edited rules."
  (let* ((saved (emacsvox-capitalization--saved kind))
         (old (gethash kind emacsvox-capitalization--drafts))
         (action (car (plist-get (plist-get (plist-get (car saved) :render) :before) :append)))
         (values (and saved (cons (plist-get action :pitch) (plist-get action :duration)))))
    (unless (equal saved (emacsvox-capitalization--rules kind values))
      (user-error "This cue's rules were edited elsewhere; use the personal rule editor"))
    (when (and old (not (equal saved (plist-get old :saved)))
               (not (equal (plist-get old :values) (plist-get old :initial))))
      (user-error "Saved cue changed while this draft was open; discard the draft first"))
    (if (and old (equal saved (plist-get old :saved))) old
      (let ((draft (list :kind kind :saved (copy-tree saved)
                         :initial (copy-tree values) :values (copy-tree values))))
        (puthash kind draft emacsvox-capitalization--drafts)
        draft))))

(defun emacsvox-capitalization--cue-context ()
  "Return the captured cue editor context after validating its source."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (and prefix (eq (oref prefix command) 'emacsvox-capitalization-cue)
                       (oref prefix scope))))
    (unless context (user-error "Open a capitalization cue first"))
    (emacsvox-aural-menu--source context)
    context))

(defun emacsvox-capitalization--cue-values ()
  "Return draft pitch/duration, falling back to the bundled resource."
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (tone (emacsvox-aural-tone (emacsvox-capitalization--tone-id (plist-get draft :kind)))))
    (or (plist-get draft :values)
        (cons (emacsvox-aural-tone-pitch tone) (emacsvox-aural-tone-duration tone)))))

(defun emacsvox-capitalization--cue-title ()
  "Describe the cue, global scope, and whether its draft differs."
  (let ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft)))
    (format "%s beep (global): %s"
            (if (eq (plist-get draft :kind) 'capital) "Capital-letter" "All-caps")
            (cond ((not (equal (plist-get draft :values) (plist-get draft :initial)))
                   "unsaved preview draft")
                  ((plist-get draft :values) "saved override")
                  (t "bundled cue")))))

(defun emacsvox-capitalization--cue-edit (field &optional delta)
  "Edit cue FIELD exactly, or adjust it by DELTA units."
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (values (copy-tree (emacsvox-capitalization--cue-values)))
         (pitch (eq field 'pitch))
         (current (if pitch (car values) (cdr values)))
         (value (if delta (max (if pitch 1 0) (+ current delta))
                  (emacsvox-aural-menu--read-number
                   (if pitch "Pitch in Hz: " "Duration in milliseconds: ") current))))
    (unless (and (numberp value) (if pitch (> value 0) (>= value 0)))
      (user-error "Pitch must be positive; duration must be nonnegative"))
    (if pitch (setcar values value) (setcdr values value))
    (setf (plist-get draft :values) values)
    (emacsvox-capitalization--say
     (format "%s%s %s" (if (and delta (= current value)) "Minimum. " "")
             value (if pitch "Hz" "milliseconds")))))

(defun emacsvox-capitalization--pitch ()
  "Set draft pitch in Hz." (interactive) (emacsvox-capitalization--cue-edit 'pitch))
(defun emacsvox-capitalization--duration ()
  "Set draft duration in milliseconds." (interactive) (emacsvox-capitalization--cue-edit 'duration))
(defun emacsvox-capitalization--cue-adjust (direction)
  "Adjust the focused cue control in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (pcase command
      ('emacsvox-capitalization--pitch (emacsvox-capitalization--cue-edit 'pitch (* 25 direction)))
      ('emacsvox-capitalization--duration (emacsvox-capitalization--cue-edit 'duration (* 5 direction)))
      (_ (user-error "Choose Pitch or Duration first")))))
(defun emacsvox-capitalization--decrease ()
  "Decrease the selected cue setting." (interactive) (emacsvox-capitalization--cue-adjust -1))
(defun emacsvox-capitalization--increase ()
  "Increase the selected cue setting." (interactive) (emacsvox-capitalization--cue-adjust 1))

(defun emacsvox-capitalization--cue-preview ()
  "Preview this draft's beep alone without applying or saving it."
  (interactive)
  (let* ((values (emacsvox-capitalization--cue-values))
         (action (emacsvox-aural--compile-action
                  (list :id 'capitalization-cue-preview :kind 'tone
                        :pitch (car values) :duration (cdr values))
                  'capitalization-cue-preview 'before 0 'run))
         (render (emacsvox-aural--make-render-plan
                  :before (list action) :content (emacsvox-aural--make-content-style :speak nil))))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-capitalization--cue-context))
      (emacsvox-aural-preview-play-plan
       (emacsvox-aural-compile-plan render nil (emacsvox-aural-context-at-point) 'local-cue)))))

(defun emacsvox-capitalization--stop ()
  "Stop preview output." (interactive) (emacsvox-aural-preview-stop))

(defun emacsvox-capitalization--cue-reset ()
  "Preview bundled values; Save removes only this menu's override rules."
  (interactive)
  (let ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft)))
    (setf (plist-get draft :values) nil))
  (emacsvox-capitalization--say "Bundled cue in draft. Save to remove this menu's override."))

(defun emacsvox-capitalization--cue-discard ()
  "Discard this preview draft and reread the saved cue rules."
  (interactive)
  (let* ((context (emacsvox-capitalization--cue-context))
         (kind (plist-get (plist-get context :cue-draft) :kind)))
    (remhash kind emacsvox-capitalization--drafts)
    (setf (plist-get context :cue-draft) (emacsvox-capitalization--draft kind))
    (emacsvox-capitalization--say "Draft discarded")))

(defun emacsvox-capitalization--cue-save ()
  "Save only this cue's draft as global personal rules, preserving other rules."
  (interactive)
  (let* ((context (emacsvox-capitalization--cue-context))
         (draft (plist-get context :cue-draft))
         (kind (plist-get draft :kind))
         (saved (emacsvox-capitalization--saved kind))
         (rules (emacsvox-capitalization--rules kind (plist-get draft :values))))
    (unless (equal saved (plist-get draft :saved))
      (user-error "Saved cue changed; discard this draft and reopen it"))
    (when (cl-some (lambda (buffer)
                     (with-current-buffer buffer
                       (and (eq emacsvox-aural-editor-scope 'personal) emacsvox-aural-editor-dirty)))
                   (buffer-list))
      (user-error "Finish the unsaved personal-rule editor first"))
    (with-current-buffer (emacsvox-aural-menu--source context)
      (let ((emacsvox-aural-editor-scope 'personal))
        (emacsvox-aural-editor--commit-layer
         (append (cl-remove-if (lambda (rule) (memq rule saved)) emacsvox-aural-user-rules) rules))))
    (setf (plist-get draft :saved) (copy-tree rules)
          (plist-get draft :initial) (copy-tree (plist-get draft :values)))
    (emacsvox-capitalization--say
     (if rules "Saved global cue override. Other presentation rules still apply."
       "Removed this menu's cue override. Other presentation rules still apply."))))

(defun emacsvox-capitalization--letter ()
  "Edit the capital-letter beep." (interactive) (emacsvox-capitalization-cue 'capital))
(defun emacsvox-capitalization--all-caps ()
  "Edit the all-caps beep." (interactive) (emacsvox-capitalization-cue 'all-caps))

(transient-define-prefix emacsvox-capitalization-cue (kind)
  "Tune one global capitalization beep in a retained preview draft."
  :refresh-suffixes t
  [:description emacsvox-capitalization--cue-title
   ("p" (lambda () (format "Pitch: %s Hz" (car (emacsvox-capitalization--cue-values)))) emacsvox-capitalization--pitch :transient t)
   ("d" (lambda () (format "Duration: %s milliseconds" (cdr (emacsvox-capitalization--cue-values)))) emacsvox-capitalization--duration :transient t)]
  ["Preview and save (other rules may override)"
   ("SPC" "Preview beep only" emacsvox-capitalization--cue-preview :transient t)
   ("s" "Stop preview" emacsvox-capitalization--stop :transient t)
   ("r" "Restore bundled cue in draft" emacsvox-capitalization--cue-reset :transient t)
   ("D" "Discard preview edits" emacsvox-capitalization--cue-discard :transient t)
   ("S" "Save this cue globally" emacsvox-capitalization--cue-save :transient t)
   ("q" "Back (retain draft)" transient-quit-one)
   ("C-q" "Close menus (retain draft)" transient-quit-all)]
  (interactive (list (intern (completing-read "Capitalization kind: " '(capital all-caps) nil t))))
  (unless (memq kind '(capital all-caps)) (user-error "Unknown capitalization kind"))
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-capitalization))
                      (copy-sequence (oref prefix scope)) (emacsvox-aural-menu--capture nil))))
    (transient-setup 'emacsvox-capitalization-cue nil nil
                     :scope (plist-put context :cue-draft (emacsvox-capitalization--draft kind)))))

(defun emacsvox-capitalization--bindings (map)
  "Add shifted-arrow adjustment to cue menu MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-capitalization-cue))
    (keymap-set map "S-<left>" #'emacsvox-capitalization--decrease)
    (keymap-set map "S-<right>" #'emacsvox-capitalization--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-capitalization--bindings)
(define-key transient-predicate-map [emacsvox-capitalization--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-capitalization--increase] #'transient--do-stay)

;;;###autoload
(transient-define-prefix emacsvox-capitalization (&optional global)
  "Choose capitalization indication, presentation, splitting, and global beep drafts."
  :refresh-suffixes t
  ["Capitalization"
   ("g" (lambda () (concat "Scope: " (emacsvox-aural-menu--scope-label))) emacsvox-aural-menu--toggle-scope :transient t)
   ("i" (lambda () (format "Indication: %s" (if (emacsvox-capitalization--value 'tts-caps) "on" "off"))) emacsvox-capitalization--indication :transient t)
   ("p" (lambda () (format "Presentation: %s" (emacsvox-capitalization--value 'emacsvox-capitalization-presentation))) emacsvox-capitalization--presentation :transient t)
   ("c" (lambda () (format "Split camel case: %s" (if (emacsvox-capitalization--value 'tts-split-caps) "on" "off"))) emacsvox-capitalization--split :transient t)
   ("SPC" "Preview reading settings" emacsvox-capitalization--preview :transient t)]
  ["Global beep drafts (save separately)"
   ("l" "Capital-letter beep" emacsvox-capitalization--letter :transient transient--do-stack)
   ("a" "All-caps beep" emacsvox-capitalization--all-caps :transient transient--do-stack)]
  ["Save and finish"
   ("S" "Save displayed reading defaults" emacsvox-capitalization--save :transient t)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive "P")
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (memq (oref prefix command) '(emacsvox-aural-menu-speech emacsvox-capitalization)))
                      (oref prefix scope) (emacsvox-aural-menu--capture global))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-capitalization nil nil :scope context)))

(provide 'emacsvox-capitalization)
;;; emacsvox-capitalization.el ends here
