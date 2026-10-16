;;; emacsvox-line-cues.el --- Line and boundary cue drafts -*- lexical-binding: t; -*-

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
;; Retain preview drafts and save only owned overrides in personal rules.
;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-tools)

(defconst emacsvox-line-cues--entries
  '((empty "Blank line" line-empty core-empty-line-tone-action)
    (whitespace-only "Whitespace-only line" line-whitespace core-whitespace-line-tone-action)
    (separator "Separator line" line-separator core-separator-line-tone-action)
    (decorative "Decorated line" line-decoration core-decorative-line-tone-action)
    (unspeakable "Unspeakable line" line-unspeakable core-unspeakable-line-tone-action)
    (warn-user "Boundary and warning earcon (all uses)" warn-user)
    (large-movement "Large movement earcon (all uses)" large-movement))
  "Kind, label, resource, and optional line action to replace.")
(defvar emacsvox-line-cues--drafts (make-hash-table :test #'eq)
  "Retained drafts keyed by cue kind.")

(defun emacsvox-line-cues--context ()
  "Return this editor's captured context, checking its source."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (and prefix (eq (oref prefix command) 'emacsvox-line-cues-edit)
                       (oref prefix scope))))
    (unless context (user-error "Open a line or boundary cue first"))
    (emacsvox-aural-menu--source context)
    context))
(defun emacsvox-line-cues--current ()
  "Return the current retained draft."
  (plist-get (emacsvox-line-cues--context) :cue-draft))
(defun emacsvox-line-cues--entry ()
  "Return the description of this draft's cue."
  (assq (plist-get (emacsvox-line-cues--current) :kind) emacsvox-line-cues--entries))
(defun emacsvox-line-cues--tone-p ()
  "Return non-nil for a line tone."
  (nth 3 (emacsvox-line-cues--entry)))
(defun emacsvox-line-cues--say (text)
  "Speak replaceable feedback TEXT."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'line-cue 'command-menu-value-changed)
   'state-change 'select-object))
(defun emacsvox-line-cues--id (kind)
  "Return the owned personal-rule identifier for KIND."
  (intern (format "settings-line-cue-%s" kind)))
(defun emacsvox-line-cues--rules (kind value)
  "Build KIND's rule for VALUE: bundled, silent, a tone pair, or an earcon."
  (unless (eq value 'bundled)
    (let* ((entry (assq kind emacsvox-line-cues--entries))
           (action (nth 3 entry)))
      (if (not action)
          (list (emacsvox-aural-make-legacy-cue-rule
                 (emacsvox-line-cues--id kind) (nth 2 entry)
                 (unless (eq value 'silent) value)))
        (list (list :id (emacsvox-line-cues--id kind)
                    :match (list :line-condition kind)
                    :render
                    (list :before
                          (append (list :remove (list action))
                                  (unless (eq value 'silent)
                                    (list :append
                                          (list (list :id action :kind 'tone
                                                      :pitch (car value) :duration (cdr value)))))))))))))
(defun emacsvox-line-cues--saved (kind)
  "Read only the personal rule owned for KIND."
  (cl-remove-if-not (lambda (r) (eq (plist-get r :id) (emacsvox-line-cues--id kind)))
                    emacsvox-aural-user-rules))
(defun emacsvox-line-cues--draft (kind)
  "Resume KIND's draft without overwriting conflicting edits."
  (let* ((saved (emacsvox-line-cues--saved kind))
         (action (car (plist-get (plist-get (plist-get (car saved) :render) :before) :append)))
         (value (cond ((not saved) 'bundled) ((not action) 'silent)
                      ((nth 3 (assq kind emacsvox-line-cues--entries))
                       (cons (plist-get action :pitch) (plist-get action :duration)))
                      (t (plist-get action :cue))))
         (old (gethash kind emacsvox-line-cues--drafts)))
    (unless (equal saved (emacsvox-line-cues--rules kind value))
      (user-error "This cue rule was edited elsewhere; use the personal-rule editor"))
    (when (and old (not (equal saved (plist-get old :saved)))
               (not (equal (plist-get old :value) (plist-get old :initial))))
      (user-error "Saved cue changed; discard the draft first"))
    (if (and old (equal saved (plist-get old :saved))) old
      (let ((draft (list :kind kind :saved (copy-tree saved)
                         :initial (copy-tree value) :value (copy-tree value))))
        (puthash kind draft emacsvox-line-cues--drafts) draft))))
(defun emacsvox-line-cues--values ()
  "Return this tone's draft values or its resource defaults."
  (let ((value (plist-get (emacsvox-line-cues--current) :value)))
    (if (consp value) value
      (let ((tone (emacsvox-aural-tone (nth 2 (emacsvox-line-cues--entry)))))
        (cons (emacsvox-aural-tone-pitch tone) (emacsvox-aural-tone-duration tone))))))
(defun emacsvox-line-cues--title ()
  "Describe cue scope and draft state."
  (let ((draft (emacsvox-line-cues--current)))
    (format "%s, global: %s%s" (nth 1 (emacsvox-line-cues--entry))
            (pcase (plist-get draft :value) ('bundled "bundled") ('silent "silent") (_ "override"))
            (if (equal (plist-get draft :value) (plist-get draft :initial)) "" "; unsaved draft"))))
(defun emacsvox-line-cues--edit (field &optional delta)
  "Edit tone FIELD exactly or by DELTA."
  (unless (emacsvox-line-cues--tone-p) (user-error "Choose a line tone first"))
  (when (and (not delta) (window-live-p transient--window))
    (with-selected-window transient--window
      (transient--goto-button
       (emacsvox-transient--menu-suffix (if (eq field 'pitch) 'emacsvox-line-cues--pitch
                                 'emacsvox-line-cues--duration)))))
  (let* ((values (copy-tree (emacsvox-line-cues--values)))
         (pitch (eq field 'pitch))
         (old (if pitch (car values) (cdr values)))
         (minimum (if pitch 1 0))
         (value (if delta (max minimum (+ old delta))
                  (emacsvox-aural-menu--read-number
                   (if pitch "Pitch in Hz: " "Duration in milliseconds: ") old))))
    (unless (and (numberp value) (= (- value value) 0) (>= value minimum)
                 (or pitch (integerp value)))
      (user-error "Enter a finite positive pitch or nonnegative integer duration"))
    (if pitch (setcar values value) (setcdr values value))
    (let ((draft (emacsvox-line-cues--current)))
      (setf (plist-get draft :value) values))
    (emacsvox-line-cues--say (format "%s%s %s" (if (and delta (= old value)) "Minimum. " "")
                                    value (if pitch "Hz" "milliseconds")))))
(defun emacsvox-line-cues--pitch ()
  "Set draft pitch; Shift arrows change it by 25 Hz." (interactive) (emacsvox-line-cues--edit 'pitch))
(defun emacsvox-line-cues--duration ()
  "Set draft duration; Shift arrows change it by 5 ms." (interactive) (emacsvox-line-cues--edit 'duration))
(defun emacsvox-line-cues--choose ()
  "Choose a replacement earcon for this global draft."
  (interactive)
  (let ((draft (emacsvox-line-cues--current)))
    (setf (plist-get draft :value)
          (intern (emacsvox-transient--read #'completing-read "Earcon: " (emacsvox-aural-tools--earcon-remap-candidates) nil t))))
  (emacsvox-line-cues--say "Earcon in draft. Space previews; capital S saves."))
(defun emacsvox-line-cues--silent ()
  "Suppress only this cue when the draft is saved."
  (interactive)
  (let ((draft (emacsvox-line-cues--current)))
    (setf (plist-get draft :value) 'silent))
  (emacsvox-line-cues--say "Silent in draft. Save to apply."))
(defun emacsvox-line-cues--reset ()
  "Restore the bundled cue in this draft."
  (interactive)
  (let ((draft (emacsvox-line-cues--current)))
    (setf (plist-get draft :value) 'bundled))
  (emacsvox-line-cues--say "Bundled cue in draft. Save to remove this override."))
(defun emacsvox-line-cues--discard ()
  "Discard edits and reread the saved rule."
  (interactive)
  (let* ((context (emacsvox-line-cues--context))
         (kind (plist-get (emacsvox-line-cues--current) :kind)))
    (remhash kind emacsvox-line-cues--drafts)
    (setf (plist-get context :cue-draft) (emacsvox-line-cues--draft kind)))
  (emacsvox-line-cues--say "Draft discarded"))
(defun emacsvox-line-cues--save ()
  "Persist only this draft's owned rule through the personal-rule store."
  (interactive)
  (let* ((draft (emacsvox-line-cues--current)) (kind (plist-get draft :kind))
         (saved (emacsvox-line-cues--saved kind))
         (rules (emacsvox-line-cues--rules kind (plist-get draft :value))))
    (unless (equal saved (plist-get draft :saved))
      (user-error "Saved cue changed; discard this draft first"))
    (when (cl-some (lambda (buffer)
                    (with-current-buffer buffer
                      (and (eq emacsvox-aural-editor-scope 'personal) emacsvox-aural-editor-dirty)))
                  (buffer-list))
      (user-error "Finish the unsaved personal-rule editor first"))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-line-cues--context))
      (let ((emacsvox-aural-editor-scope 'personal))
        (emacsvox-aural-editor--commit-layer
         (append (cl-remove-if (lambda (rule) (memq rule saved)) emacsvox-aural-user-rules) rules))))
    (setf (plist-get draft :saved) (copy-tree rules)
          (plist-get draft :initial) (copy-tree (plist-get draft :value)))
    (emacsvox-line-cues--say "Saved global cue. Other presentation rules still apply.")))
(defun emacsvox-line-cues--preview ()
  "Preview just this draft's cue without applying or saving it."
  (interactive)
  (let* ((entry (emacsvox-line-cues--entry))
         (value (plist-get (emacsvox-line-cues--current) :value)))
    (if (eq value 'silent) (progn (emacsvox-aural-preview-stop) (emacsvox-line-cues--say "Silent cue"))
      (let* ((data (if (nth 3 entry)
                       (let ((pair (emacsvox-line-cues--values)))
                         (list :kind 'tone :pitch (car pair) :duration (cdr pair)))
                     (list :kind 'cue :cue (if (eq value 'bundled) (nth 2 entry) value))))
             (action (emacsvox-aural--compile-action
                      (append '(:id line-cue-preview) data) 'line-cue-preview 'before 0 'object))
             (render (emacsvox-aural--make-render-plan
                      :before (list action) :content (emacsvox-aural--make-content-style :speak nil))))
        (with-current-buffer (emacsvox-aural-menu--source (emacsvox-line-cues--context))
          (emacsvox-aural-preview-play-plan
           (emacsvox-aural-compile-plan render nil (emacsvox-aural-context-at-point) 'local-cue)))))))
(defun emacsvox-line-cues--adjust (direction)
  "Adjust the selected tone control in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (pcase command
      ('emacsvox-line-cues--pitch (emacsvox-line-cues--edit 'pitch (* 25 direction)))
      ('emacsvox-line-cues--duration (emacsvox-line-cues--edit 'duration (* 5 direction)))
      (_ (user-error "Choose Pitch or Duration first")))))
(defun emacsvox-line-cues--stop ()
  "Stop the private cue preview."
  (interactive)
  (emacsvox-aural-preview-stop))
(defun emacsvox-line-cues--decrease ()
  "Decrease this tone control." (interactive) (emacsvox-line-cues--adjust -1))
(defun emacsvox-line-cues--increase ()
  "Increase this tone control." (interactive) (emacsvox-line-cues--adjust 1))
(defun emacsvox-line-cues--bindings (map)
  "Add shifted adjustments to the cue editor MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-line-cues-edit))
    (keymap-set map "S-<left>" #'emacsvox-line-cues--decrease)
    (keymap-set map "S-<right>" #'emacsvox-line-cues--increase)) map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-line-cues--bindings)
(define-key transient-predicate-map [emacsvox-line-cues--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-line-cues--increase] #'transient--do-stay)

;;;###autoload
(transient-define-prefix emacsvox-line-cues-edit (kind)
  "Edit a retained global line or boundary cue draft of KIND."
  :refresh-suffixes t
  [:description emacsvox-line-cues--title
   ("p" (lambda () (format "Pitch: %s Hz" (car (emacsvox-line-cues--values)))) emacsvox-line-cues--pitch :if emacsvox-line-cues--tone-p :transient t)
   ("d" (lambda () (format "Duration: %s milliseconds" (cdr (emacsvox-line-cues--values)))) emacsvox-line-cues--duration :if emacsvox-line-cues--tone-p :transient t)
   ("e" "Choose replacement earcon" emacsvox-line-cues--choose :if-not emacsvox-line-cues--tone-p :transient t)
   ("n" "Silence cue in draft" emacsvox-line-cues--silent :transient t)]
  ["Preview and save"
   ("SPC" "Preview cue only" emacsvox-line-cues--preview :transient t)
   ("s" "Stop preview" emacsvox-line-cues--stop :transient t)
   ("r" "Restore bundled cue in draft" emacsvox-line-cues--reset :transient t)
   ("D" "Discard draft edits" emacsvox-line-cues--discard :transient t)
   ("S" "Save this cue globally" emacsvox-line-cues--save :transient t)
   ("q" "Back (retain draft)" transient-quit-one)
   ("C-q" "Close menus (retain draft)" transient-quit-all)]
  (interactive (list (intern (completing-read "Cue: " (mapcar #'car emacsvox-line-cues--entries) nil t))))
  (unless (assq kind emacsvox-line-cues--entries) (user-error "Unknown cue"))
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-aural-menu-line-cues))
                      (copy-sequence (oref prefix scope))
                    (emacsvox-aural-menu--capture nil))))
    (transient-setup 'emacsvox-line-cues-edit nil nil
                     :scope (plist-put context :cue-draft (emacsvox-line-cues--draft kind)))))

(provide 'emacsvox-line-cues)
;;; emacsvox-line-cues.el ends here
