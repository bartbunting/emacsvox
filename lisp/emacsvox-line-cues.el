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
(require 'emacsvox-tone-editor)

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
  "Return this cue's captured context, including inside the shared editor."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-line-cues-edit))
                      (oref prefix scope) (emacsvox-aural-menu--context))))
    (unless (assq (plist-get (plist-get context :cue-draft) :kind)
                  emacsvox-line-cues--entries)
      (user-error "Open a line or boundary cue first"))
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
(defun emacsvox-line-cues--id (kind &optional session)
  "Return the owned rule identifier for KIND, optionally for SESSION."
  (intern (format "settings-line-cue-%s%s" kind (if session "-session" ""))))
(defun emacsvox-line-cues--rules (kind value &optional session)
  "Build KIND's rule for VALUE, with a distinct identifier for SESSION."
  (unless (eq value 'bundled)
    (let* ((entry (assq kind emacsvox-line-cues--entries))
           (action (nth 3 entry)))
      (if (not action)
          (list (emacsvox-aural-make-legacy-cue-rule
                 (emacsvox-line-cues--id kind session) (nth 2 entry)
                 (unless (eq value 'silent) value)))
        (list (list :id (emacsvox-line-cues--id kind session)
                    :match (list :line-condition kind)
                    :render
                    (list :before
                          (append (list :remove (list action))
                                  (unless (eq value 'silent)
                                    (list :append
                                          (list (append (list :id action :kind 'tone)
                                                        (if (numberp (car value))
                                                            (list :pitch (car value) :duration (cdr value))
                                                          value)))))))))))))
(defun emacsvox-line-cues--saved (kind)
  "Read only the personal rule owned for KIND."
  (cl-remove-if-not (lambda (r) (eq (plist-get r :id) (emacsvox-line-cues--id kind)))
                    emacsvox-aural-user-rules))
(defun emacsvox-line-cues--session (kind)
  "Return this menu's session rule for KIND."
  (cl-remove-if-not (lambda (r) (eq (plist-get r :id) (emacsvox-line-cues--id kind t)))
                    emacsvox-aural-session-rules))

(defun emacsvox-line-cues--rule-value (kind rules &optional session)
  "Read KIND's owned RULES, refusing rules edited outside this menu."
  (let* ((action (car (plist-get (plist-get (plist-get (car rules) :render) :before) :append)))
         (value (cond ((not rules) 'bundled) ((not action) 'silent)
                      ((nth 3 (assq kind emacsvox-line-cues--entries))
                       (if (or (plist-member action :volume) (plist-member action :shape))
                           (cl-loop for (key val) on action by #'cddr
                                    when (memq key '(:pitch :duration :volume :shape))
                                    append (list key (copy-tree val)))
                         (cons (plist-get action :pitch) (plist-get action :duration))))
                      (t (plist-get action :cue)))))
    (unless (equal rules (emacsvox-line-cues--rules kind value session))
      (user-error "This cue rule was edited elsewhere; use the rule editor"))
    value))

(defun emacsvox-line-cues--draft (kind)
  "Resume KIND's draft without overwriting conflicting edits or session rules."
  (let* ((saved (emacsvox-line-cues--saved kind))
         (session (emacsvox-line-cues--session kind))
         (_ (emacsvox-line-cues--rule-value kind saved))
         (value (emacsvox-line-cues--rule-value kind (or session saved) session))
         (old (gethash kind emacsvox-line-cues--drafts))
         (unchanged (and old (equal saved (plist-get old :saved))
                        (equal session (plist-get old :session)))))
    (when (and old (not unchanged)
               (not (equal (plist-get old :value) (plist-get old :initial))))
      (user-error "Cue changed; discard the draft first"))
    (if unchanged old
      (let ((draft (list :kind kind :saved (copy-tree saved) :session (copy-tree session)
                         :initial (copy-tree value) :value (copy-tree value))))
        (puthash kind draft emacsvox-line-cues--drafts) draft))))

(defun emacsvox-line-cues--tone-values (&optional value)
  "Return full tone values for VALUE or the current draft, retaining old pairs."
  (let ((value (or value (plist-get (emacsvox-line-cues--current) :value))))
    (cond ((and (consp value) (numberp (car value)))
           (list :pitch (car value) :duration (cdr value) :volume 1.0 :shape '(:waveform sine)))
          ((consp value) (append (copy-tree value)
                                (unless (plist-member value :volume) '(:volume 1.0))
                                (unless (plist-member value :shape) '(:shape (:waveform sine)))))
          (t (let ((tone (emacsvox-aural-tone (nth 2 (emacsvox-line-cues--entry)))))
               (list :pitch (emacsvox-aural-tone-pitch tone)
                     :duration (emacsvox-aural-tone-duration tone)
                     :volume 1.0 :shape '(:waveform sine)))))))

(defun emacsvox-line-cues--values ()
  "Return the current tone's pitch and duration pair for the simple controls."
  (let ((values (emacsvox-line-cues--tone-values)))
    (cons (plist-get values :pitch) (plist-get values :duration))))
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
      (setf (plist-get draft :value)
            (if (and (consp (plist-get draft :value))
                     (keywordp (car (plist-get draft :value))))
                (plist-put (copy-tree (plist-get draft :value))
                           (if pitch :pitch :duration) value)
              values)))
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
  (emacsvox-line-cues--say "Silent in draft. Apply or Save to use it."))
(defun emacsvox-line-cues--reset ()
  "Restore the bundled cue in this draft."
  (interactive)
  (let ((draft (emacsvox-line-cues--current)))
    (setf (plist-get draft :value) 'bundled))
  (emacsvox-line-cues--say "Bundled cue in draft. Apply or Save to restore it."))
(defun emacsvox-line-cues--discard ()
  "Discard edits and reread the saved rule."
  (interactive)
  (let* ((context (emacsvox-line-cues--context))
         (kind (plist-get (emacsvox-line-cues--current) :kind)))
    (remhash kind emacsvox-line-cues--drafts)
    (setf (plist-get context :cue-draft) (emacsvox-line-cues--draft kind)))
  (emacsvox-line-cues--say "Draft discarded"))
(defun emacsvox-line-cues--commit (save)
  "Apply the draft as a session rule; SAVE persists it as a personal rule."
  (let* ((draft (emacsvox-line-cues--current)) (kind (plist-get draft :kind))
         (saved (emacsvox-line-cues--saved kind))
         (session (emacsvox-line-cues--session kind))
         (value (plist-get draft :value))
         (rules (emacsvox-line-cues--rules kind value)))
    (unless (and (equal saved (plist-get draft :saved))
                 (equal session (plist-get draft :session)))
      (user-error "Cue changed; discard this draft first"))
    (when (cl-some (lambda (buffer)
                    (with-current-buffer buffer
                      (and (memq emacsvox-aural-editor-scope '(personal session))
                           emacsvox-aural-editor-dirty)))
                  (buffer-list))
      (user-error "Finish the unsaved personal or session rule editor first"))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-line-cues--context))
      (when save
        (let ((emacsvox-aural-editor-scope 'personal))
          (emacsvox-aural-editor--commit-layer
           (append (cl-remove-if (lambda (r) (memq r saved)) emacsvox-aural-user-rules) rules)))
        ;; Persistence has succeeded even if a subsequent session update fails.
        (setf (plist-get draft :saved) (copy-tree rules)))
      (let* ((emacsvox-aural-editor-scope 'session)
             (replacement
              (unless save
                (or (emacsvox-line-cues--rules kind value t)
                    (emacsvox-line-cues--rules
                     kind (if (nth 3 (assq kind emacsvox-line-cues--entries))
                              (emacsvox-line-cues--tone-values 'bundled)
                            (nth 2 (assq kind emacsvox-line-cues--entries))) t)))))
        (emacsvox-aural-editor--commit-layer
         (append (cl-remove-if (lambda (r) (memq r session)) emacsvox-aural-session-rules)
                 replacement))
        (setf (plist-get draft :session) (copy-tree replacement))))
    (setf (plist-get draft :initial) (copy-tree value))))

(defun emacsvox-line-cues--apply ()
  "Apply this cue globally for this session without writing personal rules.
Other contextual rules still apply. Save persists this cue for future sessions."
  (interactive)
  (emacsvox-line-cues--commit nil)
  (emacsvox-line-cues--say "Cue applied for this session"))

(defun emacsvox-line-cues--save ()
  "Save this cue's conditional rule and remove its temporary session override.
Other rules remain intact. Restoring bundled removes this menu's personal rule."
  (interactive)
  (emacsvox-line-cues--commit t)
  (emacsvox-line-cues--say "Saved global cue. Other presentation rules still apply."))

(defun emacsvox-line-cues--tone-data (&optional factory current)
  "Return shared-editor values for the draft, FACTORY or CURRENT comparison."
  (let* ((kind (plist-get (emacsvox-line-cues--current) :kind))
         (value (cond (factory 'bundled)
                      (current (emacsvox-line-cues--rule-value
                                kind (or (emacsvox-line-cues--session kind)
                                         (emacsvox-line-cues--saved kind))
                                (emacsvox-line-cues--session kind)))))
         (values (emacsvox-line-cues--tone-values value)))
    (emacsvox-tone-editor--data (plist-get values :pitch) (plist-get values :duration)
                               (* 100 (plist-get values :volume)) (plist-get values :shape))))

(defun emacsvox-line-cues--editor-values (data)
  "Convert shared-editor DATA to durable tone values."
  (list :pitch (plist-get data :pitch) :duration (plist-get data :duration)
        :volume (/ (plist-get data :volume) 100.0) :shape (emacsvox-tone-editor--shape data)))

(defun emacsvox-line-cues--apply-tone (data save)
  "Apply private tone DATA, persisting the conditional rule when SAVE is non-nil."
  (let ((draft (emacsvox-line-cues--current)))
    (setf (plist-get draft :value) (emacsvox-line-cues--editor-values data)))
  (emacsvox-line-cues--commit save))

(defun emacsvox-line-cues--preview-tone (data _sample)
  "Preview private DATA without changing the parent draft or any rules."
  (let* ((context (copy-sequence (emacsvox-line-cues--context)))
         (draft (copy-tree (emacsvox-line-cues--current)))
         (transient--prefix (clone transient--prefix)))
    (setf (plist-get draft :value) (emacsvox-line-cues--editor-values data))
    (oset transient--prefix scope (plist-put context :cue-draft draft))
    (emacsvox-line-cues--preview)))

(defun emacsvox-line-cues--edit-tone ()
  "Edit this line condition's tone in a private shared-editor draft.
A applies a global session rule; W saves a personal rule. C compares the
current tone values. Silence, bundled restoration and earcons stay in
the parent."
  (interactive)
  (emacsvox-tone-editor--open
   (emacsvox-line-cues--context)
   (list :label (emacsvox-line-cues--title) :read #'emacsvox-line-cues--tone-data
         :current (lambda () (emacsvox-line-cues--tone-data nil t))
         :apply #'emacsvox-line-cues--apply-tone :preview #'emacsvox-line-cues--preview-tone
         :apply-label "Apply line tone for session" :save-label "Save line tone as personal rule"
         :save-message "Saved line tone; other presentation rules still apply")))

(defun emacsvox-line-cues--preview ()
  "Preview just this draft's cue without applying or saving it."
  (interactive)
  (let* ((entry (emacsvox-line-cues--entry))
         (value (plist-get (emacsvox-line-cues--current) :value)))
    (if (eq value 'silent) (progn (emacsvox-aural-preview-stop) (emacsvox-line-cues--say "Silent cue"))
      (let* ((data (if (nth 3 entry)
                       (append (list :kind 'tone) (emacsvox-line-cues--tone-values))
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
   ("E" "Edit tone shape and envelope" emacsvox-line-cues--edit-tone :if emacsvox-line-cues--tone-p :transient transient--do-stack)
   ("n" "Silence cue in draft" emacsvox-line-cues--silent :transient t)]
  ["Preview and save"
   ("SPC" "Preview cue only" emacsvox-line-cues--preview :transient t)
   ("s" "Stop preview" emacsvox-line-cues--stop :transient t)
   ("r" "Restore bundled cue in draft" emacsvox-line-cues--reset :transient t)
   ("D" "Discard draft edits" emacsvox-line-cues--discard :transient t)
   ("A" "Apply this cue for session" emacsvox-line-cues--apply :transient t)
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
