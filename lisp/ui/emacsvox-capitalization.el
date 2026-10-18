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
;; Apply and save beep defaults through Customize; preserve contextual rules.

;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-preview)
(require 'emacsvox-tone-editor)

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
  "Toggle camel-case splitting independently of indication.
Capital cues and a voice's own pronunciation can make both choices sound
similar. Compare with Indication off to hear splitting without capital cues."
  (interactive)
  (let ((value (not (emacsvox-capitalization--value 'tts-split-caps))))
    (emacsvox-capitalization--set 'tts-split-caps value)
    (emacsvox-capitalization--say (if value "Split camel case on" "Split camel case off"))))

(defun emacsvox-capitalization--presentation-label (value label)
  "Describe presentation VALUE with LABEL and its current selection state."
  (concat label (when (eq value (emacsvox-capitalization--value
                                'emacsvox-capitalization-presentation))
                  ", selected")))

(defun emacsvox-capitalization--choose-presentation (value label)
  "Apply presentation VALUE in the captured scope and announce LABEL."
  (emacsvox-capitalization--set 'emacsvox-capitalization-presentation value)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-capitalization--say label))

(defun emacsvox-capitalization--spoken ()
  "Say cap or all caps when capitalization indication is enabled.
Apply in the parent menu's buffer/global scope. This does not enable indication
or save startup defaults. Presentation rules can override the spoken label."
  (interactive) (emacsvox-capitalization--choose-presentation 'spoken "Spoken"))
(defun emacsvox-capitalization--tone ()
  "Play the capital-letter or all-caps beep when indication is enabled.
Use the capital-letter or all-caps beep defaults, subject to presentation rules.
Apply in the parent scope without enabling indication or saving defaults."
  (interactive) (emacsvox-capitalization--choose-presentation 'tone "Tone"))
(defun emacsvox-capitalization--spoken-tone ()
  "Combine spoken labels and beeps when indication is enabled.
Apply in the parent scope without enabling indication or saving defaults.
Presentation rules can override these cues."
  (interactive) (emacsvox-capitalization--choose-presentation 'spoken-tone "Spoken and tone"))
(defun emacsvox-capitalization--custom ()
  "Use presentation rules for capitalization feedback without a built-in cue.
Publish capitalization facts when indication is enabled. Apply in the parent
scope without enabling indication or saving defaults."
  (interactive) (emacsvox-capitalization--choose-presentation 'custom "Personal rules"))
(defun emacsvox-capitalization--none ()
  "Suppress capitalization feedback; leave indication and splitting unchanged.
Apply in the parent menu's scope without saving startup defaults."
  (interactive) (emacsvox-capitalization--choose-presentation 'none "None"))

(transient-define-prefix emacsvox-capitalization--presentation ()
  "Choose capitalization presentation from a list.
Up and Down browse without applying. Enter selects in the parent menu's scope
and returns to Presentation; q cancels. The current choice is marked selected.
Indication and camel-case splitting are separate; Save remains in the parent."
  ["Presentation"
   ("s" (lambda () (emacsvox-capitalization--presentation-label 'spoken "Spoken"))
    emacsvox-capitalization--spoken :transient transient--do-replace)
   ("t" (lambda () (emacsvox-capitalization--presentation-label 'tone "Tone"))
    emacsvox-capitalization--tone :transient transient--do-replace)
   ("b" (lambda () (emacsvox-capitalization--presentation-label 'spoken-tone "Spoken and tone"))
    emacsvox-capitalization--spoken-tone :transient transient--do-replace)
   ("c" (lambda () (emacsvox-capitalization--presentation-label 'custom "Personal rules"))
    emacsvox-capitalization--custom :transient transient--do-replace)
   ("n" (lambda () (emacsvox-capitalization--presentation-label 'none "None"))
    emacsvox-capitalization--none :transient transient--do-replace)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-capitalization--presentation nil nil
                   :scope (emacsvox-aural-menu--context))
  (transient--show)
  (with-selected-window transient--window
    (transient--goto-button
     (emacsvox-transient--menu-suffix
      (cdr (assq (emacsvox-capitalization--value 'emacsvox-capitalization-presentation)
                 '((spoken . emacsvox-capitalization--spoken)
                   (tone . emacsvox-capitalization--tone)
                   (spoken-tone . emacsvox-capitalization--spoken-tone)
                   (custom . emacsvox-capitalization--custom)
                   (none . emacsvox-capitalization--none)))))))
  (emacsvox-transient--speak-button))

(defun emacsvox-capitalization--preview ()
  "Read representative text using the displayed settings and current rules."
  (interactive)
  (let ((caps (emacsvox-capitalization--value 'tts-caps))
        (split (emacsvox-capitalization--value 'tts-split-caps))
        (presentation (emacsvox-capitalization--value 'emacsvox-capitalization-presentation)))
    (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
      (let ((tts-caps caps) (tts-split-caps split)
            (emacsvox-capitalization-presentation presentation))
        (tts-speak "Alice checks readWriteBuffer before Bob calls saveCurrentFile. NASA sends XML over HTTP.")))))

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
  "Build personal tone overrides for KIND from legacy pairs or full VALUES."
  (when values
    (let* ((legacy (numberp (car values)))
           (pitch (if legacy (car values) (plist-get values :pitch)))
           (duration (if legacy (cdr values) (plist-get values :duration))))
      (mapcar
       (lambda (presentation)
         (let* ((stem (if (eq kind 'capital) "capital" "all-caps"))
                (action (intern (format "core-%s-%s-action" stem
                                        (if (eq presentation 'tone) "tone" "spoken-tone-tone")))))
           (list :id (emacsvox-capitalization--rule-id kind presentation)
                 :match (list :event 'capitalization-located :capitalization-kind kind
                              :capitalization-presentation presentation)
                 :render
                 (list :before
                       (list :anchor 'run :remove (list action)
                             :append
                             (list (append (list :id action :kind 'tone
                                                 :pitch pitch :duration duration
                                                 :audio-mode 'insert :anchor 'run)
                                           (unless legacy
                                             (list :volume (plist-get values :volume)
                                                   :shape (plist-get values :shape))))))))))
       '(tone spoken-tone)))))

(defun emacsvox-capitalization--saved (kind)
  "Read only this menu's personal rules for KIND."
  (cl-remove-if-not
   (lambda (rule) (memq (plist-get rule :id)
                        (mapcar (lambda (p) (emacsvox-capitalization--rule-id kind p))
                                '(tone spoken-tone))))
   emacsvox-aural-user-rules))

(defun emacsvox-capitalization--option (kind)
  "Return the Customize option for KIND."
  (if (eq kind 'capital) 'emacsvox-capitalization-capital-tone
    'emacsvox-capitalization-all-caps-tone))

(defun emacsvox-capitalization--legacy-values (kind)
  "Read KIND's old menu-generated rules only when both are unchanged in form.
Rules with other matches or action structures remain personal rules."
  (let* ((saved (emacsvox-capitalization--saved kind))
         (action (car (plist-get (plist-get (plist-get (car saved) :render) :before) :append)))
         (values (and saved
                      (if (or (plist-member action :shape) (plist-member action :volume))
                          (list :pitch (plist-get action :pitch) :duration (plist-get action :duration)
                                :volume (plist-get action :volume) :shape (plist-get action :shape))
                        (cons (plist-get action :pitch) (plist-get action :duration))))))
    (when (and saved (equal saved (emacsvox-capitalization--rules kind values)))
      (if (numberp (car values))
          (list :pitch (car values) :duration (cdr values) :volume 1.0 :shape '(:waveform sine))
        values))))

(defun emacsvox-capitalization--draft (kind)
  "Resume KIND's draft, checking for changed defaults and legacy rules."
  (let* ((saved (emacsvox-capitalization--saved kind))
         (current (default-value (emacsvox-capitalization--option kind)))
         (old (gethash kind emacsvox-capitalization--drafts))
         (unchanged (and old (equal saved (plist-get old :saved))
                         (equal current (plist-get old :initial)))))
    (when (and old (not unchanged)
               (not (equal (plist-get old :values) (plist-get old :initial))))
      (user-error "Cue changed while this draft was open; discard the draft first"))
    (if unchanged old
      (let ((draft (list :kind kind :saved (copy-tree saved)
                         :initial (copy-tree current)
                         :values (copy-tree (or (emacsvox-capitalization--legacy-values kind) current)))))
        (puthash kind draft emacsvox-capitalization--drafts)
        draft))))

(defun emacsvox-capitalization--cue-context ()
  "Return the captured cue editor context after validating its source."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (and prefix (memq (oref prefix command) '(emacsvox-capitalization-cue emacsvox-tone-editor))
                       (oref prefix scope))))
    (unless context (user-error "Open a capitalization cue first"))
    (emacsvox-aural-menu--source context)
    context))

(defun emacsvox-capitalization--cue-values ()
  "Return draft pitch/duration, falling back to the bundled resource."
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (tone (emacsvox-aural-tone (emacsvox-capitalization--tone-id (plist-get draft :kind)))))
    (let ((values (plist-get draft :values)))
      (cond ((null values)
             (cons (emacsvox-aural-tone-pitch tone) (emacsvox-aural-tone-duration tone)))
            ((numberp (car values)) values)
            (t (cons (plist-get values :pitch) (plist-get values :duration)))))))

(defun emacsvox-capitalization--cue-title ()
  "Describe the cue, global scope, and whether its draft differs."
  (let ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft)))
    (format "%s beep (global): %s"
            (if (eq (plist-get draft :kind) 'capital) "Capital-letter" "All-caps")
            (cond ((emacsvox-capitalization--legacy-values (plist-get draft :kind))
                   "legacy settings; Save to migrate")
                  ((not (equal (plist-get draft :values) (plist-get draft :initial)))
                   "preview changes")
                  (t "current defaults")))))

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
    (if (keywordp (car-safe (plist-get draft :values)))
        (setf (plist-get (plist-get draft :values) (if pitch :pitch :duration)) value)
      (setf (plist-get draft :values) values))
    (emacsvox-capitalization--say
     (format "%s%s %s" (if (and delta (= current value)) "Minimum. " "")
             value (if pitch "Hz" "milliseconds")))))

(defun emacsvox-capitalization--pitch ()
  "Set draft pitch; Shift arrows change it by 25 Hz." (interactive) (emacsvox-capitalization--cue-edit 'pitch))
(defun emacsvox-capitalization--duration ()
  "Set draft duration; Shift arrows change it by 5 ms." (interactive) (emacsvox-capitalization--cue-edit 'duration))
(defun emacsvox-capitalization--volume (&optional direction)
  "Set this beep's preview volume; DIRECTION steps by five percentage points.
Only this capital-letter or all-caps beep changes. Shared main-tone volume
still scales it. Apply changes the session; Save persists through Customize."
  (interactive)
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (data (emacsvox-capitalization--tone-data))
         (current (plist-get data :volume))
         (value (if direction (max 0 (min 100 (+ current (* 5 direction))))
                  (emacsvox-aural-menu--read-number "Beep volume (0 to 100): " current))))
    (unless (and (numberp value) (<= 0 value 100))
      (user-error "Beep volume must be between 0 and 100"))
    (setf (plist-get data :volume) value
          (plist-get draft :values) (emacsvox-capitalization--tone-values data))
    (emacsvox-capitalization--say (format "%s percent; preview only until Apply or Save" value))))

(defun emacsvox-capitalization--cue-adjust (direction)
  "Adjust the focused cue control in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (pcase command
      ('emacsvox-capitalization--pitch (emacsvox-capitalization--cue-edit 'pitch (* 25 direction)))
      ('emacsvox-capitalization--duration (emacsvox-capitalization--cue-edit 'duration (* 5 direction)))
      ('emacsvox-capitalization--volume (emacsvox-capitalization--volume direction))
      (_ (user-error "Choose Pitch, Duration or Beep volume first")))))
(defun emacsvox-capitalization--decrease ()
  "Decrease the selected cue setting." (interactive) (emacsvox-capitalization--cue-adjust -1))
(defun emacsvox-capitalization--increase ()
  "Increase the selected cue setting." (interactive) (emacsvox-capitalization--cue-adjust 1))

(defun emacsvox-capitalization--tone-data (&optional factory current)
  "Read the retained tone draft, FACTORY values, or CURRENT defaults."
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (kind (plist-get draft :kind))
         (option (emacsvox-capitalization--option kind))
         (values (cond (factory (eval (car (get option 'standard-value)) t))
                       (current (or (emacsvox-capitalization--legacy-values kind)
                                    (default-value option)))
                       (t (plist-get draft :values)))))
    (emacsvox-tone-editor--data
     (plist-get values :pitch) (plist-get values :duration)
     (* 100 (plist-get values :volume)) (plist-get values :shape))))

(defun emacsvox-capitalization--tone-values (data)
  "Convert editor DATA to this cue's Customize value."
  (list :pitch (plist-get data :pitch) :duration (plist-get data :duration)
        :volume (/ (plist-get data :volume) 100.0) :shape (emacsvox-tone-editor--shape data)))

(defun emacsvox-capitalization--preview-tone (data sample)
  "Preview private DATA alone or in a capitalization SAMPLE."
  (let* ((context (emacsvox-capitalization--cue-context))
         (kind (plist-get (plist-get context :cue-draft) :kind))
         (values (emacsvox-capitalization--tone-values data))
         (emacsvox-aural--exact-tone-preview t))
    (with-current-buffer (emacsvox-aural-menu--source context)
      (emacsvox-aural--tone-volume-deliverable-p (plist-get values :volume))
      (emacsvox-aural--tone-shape-deliverable-p (plist-get values :shape))
      (if sample
          (let* ((legacy (and (emacsvox-capitalization--legacy-values kind)
                              (emacsvox-capitalization--saved kind)))
                 (emacsvox-aural-user-rules
                  (cl-remove-if (lambda (rule) (memq rule legacy)) emacsvox-aural-user-rules))
                 (tts-caps t) (tts-split-caps nil)
                 (emacsvox-capitalization-presentation 'tone))
            (cl-progv (list (emacsvox-capitalization--option kind)) (list values)
              (tts-speak (if (eq kind 'capital)
                             "Alice visits Bob on Monday. Carol meets David on Friday."
                           "NASA sends XML to HTTP. CPU and RAM checks report OK."))))
        (let* ((action (emacsvox-aural--compile-action
                        (append (list :id 'capitalization-cue-preview :kind 'tone) values)
                        'capitalization-cue-preview 'before 0 'run))
               (render (emacsvox-aural--make-render-plan
                        :before (list action) :content (emacsvox-aural--make-content-style :speak nil))))
          (emacsvox-aural-preview-play-plan
           (emacsvox-aural-compile-plan render nil (emacsvox-aural-context-at-point) 'local-cue)))))))

(defun emacsvox-capitalization--cue-sample ()
  "Read several examples using this beep's preview settings.
Temporarily enable tone indication; contextual rules still apply."
  (interactive)
  (emacsvox-capitalization--preview-tone (emacsvox-capitalization--tone-data) t))

(defun emacsvox-capitalization--cue-preview ()
  "Preview this retained draft without applying or saving it."
  (interactive)
  (emacsvox-capitalization--preview-tone (emacsvox-capitalization--tone-data) nil))

(defun emacsvox-capitalization--apply-tone (data save)
  "Apply DATA as global defaults; SAVE also persists them through Customize."
  (let ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft)))
    (setf (plist-get draft :values) (emacsvox-capitalization--tone-values data))
    (emacsvox-capitalization--commit-cue save)))

(defun emacsvox-capitalization--edit-tone ()
  "Edit global capitalization defaults in a private tone draft.
A applies this cue globally; W also saves it through Customize. C compares
current defaults. Presentation rules can override these defaults. Old
menu-generated rules migrate on Save; contextual rules remain unchanged."
  (interactive)
  (let ((context (emacsvox-capitalization--cue-context)))
    (emacsvox-tone-editor--open
     context
     (list :label (emacsvox-capitalization--cue-title)
           :read #'emacsvox-capitalization--tone-data
           :current (lambda () (emacsvox-capitalization--tone-data nil t))
           :apply #'emacsvox-capitalization--apply-tone
           :apply-label "Apply global beep defaults"
           :apply-message "Applied global beep defaults; presentation rules still apply"
           :save-label "Save global beep defaults in Customize"
           :save-message "Saved global beep defaults; presentation rules still apply"
           :preview #'emacsvox-capitalization--preview-tone))))

(defun emacsvox-capitalization--stop ()
  "Stop preview output." (interactive) (emacsvox-aural-preview-stop))

(defun emacsvox-capitalization--cue-reset ()
  "Restore factory values in the draft; Apply or Save makes them effective."
  (interactive)
  (let ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft)))
    (setf (plist-get draft :values)
          (emacsvox-capitalization--tone-values (emacsvox-capitalization--tone-data t))))
  (emacsvox-capitalization--say "Factory values ready to preview. Apply or Save to use them."))

(defun emacsvox-capitalization--cue-discard ()
  "Discard preview changes and reread current defaults or legacy settings."
  (interactive)
  (let* ((context (emacsvox-capitalization--cue-context))
         (kind (plist-get (plist-get context :cue-draft) :kind)))
    (remhash kind emacsvox-capitalization--drafts)
    (setf (plist-get context :cue-draft) (emacsvox-capitalization--draft kind))
    (emacsvox-capitalization--say "Preview changes discarded; applied defaults unchanged")))

(defun emacsvox-capitalization--commit-cue (save)
  "Apply this cue's draft; SAVE persists it and migrates old menu rules.
Write Customize first so a failed rule-store write leaves the old cue intact.
Retry Save after correcting the write failure to complete the migration."
  (let* ((draft (plist-get (emacsvox-capitalization--cue-context) :cue-draft))
         (kind (plist-get draft :kind))
         (option (emacsvox-capitalization--option kind))
         (saved (emacsvox-capitalization--saved kind))
         (legacy (emacsvox-capitalization--legacy-values kind))
         (values (copy-tree (plist-get draft :values))))
    (unless (and (equal saved (plist-get draft :saved))
                 (equal (default-value option) (plist-get draft :initial)))
      (user-error "Cue changed; discard this draft and reopen it"))
    (when legacy
      (unless save
        (user-error "Save this cue once to migrate its old personal rules to Customize"))
      (when (cl-some (lambda (buffer)
                      (with-current-buffer buffer
                        (and (eq emacsvox-aural-editor-scope 'personal) emacsvox-aural-editor-dirty)))
                    (buffer-list))
        (user-error "Finish the unsaved personal-rule editor before migrating this cue")))
    ;; The older controls accept fractional durations and any positive pitch.
    ;; Validate the tone contract without imposing the shared editor's ranges.
    (emacsvox-aural--compile-action
     (append (list :id 'capitalization-default :kind 'tone) values)
     'capitalization-default 'before 0 'run)
    (let ((previous (copy-tree (default-value option)))
          (properties (copy-tree (symbol-plist option))))
      (condition-case err
          (if save (customize-save-variable option values) (set-default option values))
        (error
         (set-default option previous)
         (setplist option properties)
         (signal (car err) (cdr err)))))
    (setf (plist-get draft :initial) (copy-tree values))
    (when legacy
      (let ((emacsvox-aural-editor-scope 'personal))
        (condition-case err
            (emacsvox-aural-editor--commit-layer
             (cl-remove-if (lambda (rule) (memq rule saved)) emacsvox-aural-user-rules))
          (error
           (error "Customize saved; old cue rules retained. Retry Save: %s"
                  (error-message-string err)))))
      (setf (plist-get draft :saved) nil))))

(defun emacsvox-capitalization--cue-apply ()
  "Apply this draft as global beep defaults for the current Emacs session.
Presentation rules still apply. Save once first when migrating old menu rules."
  (interactive)
  (emacsvox-capitalization--commit-cue nil)
  (emacsvox-capitalization--say "Applied global beep defaults. Presentation rules still apply."))

(defun emacsvox-capitalization--cue-save ()
  "Apply and save this beep's defaults through Customize.
Migrate only unchanged old menu-generated rules; preserve contextual rules."
  (interactive)
  (emacsvox-capitalization--commit-cue t)
  (emacsvox-capitalization--say "Saved global beep defaults. Presentation rules still apply."))

(defun emacsvox-capitalization--letter ()
  "Edit the capital-letter beep." (interactive) (emacsvox-capitalization-cue 'capital))
(defun emacsvox-capitalization--all-caps ()
  "Edit the all-caps beep." (interactive) (emacsvox-capitalization-cue 'all-caps))

(transient-define-prefix emacsvox-capitalization-cue (kind)
  "Preview and adjust one global capitalization beep.
Edits remain available in this session until applied or discarded. A applies
session defaults; S saves them through Customize for future sessions."
  :refresh-suffixes t
  [:description emacsvox-capitalization--cue-title
   ("p" (lambda () (format "Pitch: %s Hz" (car (emacsvox-capitalization--cue-values)))) emacsvox-capitalization--pitch :transient t)
   ("d" (lambda () (format "Duration: %s milliseconds" (cdr (emacsvox-capitalization--cue-values)))) emacsvox-capitalization--duration :transient t)
   ("v" (lambda () (format "Beep volume: %s percent" (plist-get (emacsvox-capitalization--tone-data) :volume))) emacsvox-capitalization--volume :transient t)
   ("E" "Tone editor: waveform, envelope and presets" emacsvox-capitalization--edit-tone :transient transient--do-stack)]
  ["Preview and save (other rules may override)"
   ("SPC" "Preview beep only" emacsvox-capitalization--cue-preview :transient t)
   ("P" "Read sentence with several beeps" emacsvox-capitalization--cue-sample :transient t)
   ("s" "Stop preview" emacsvox-capitalization--stop :transient t)
   ("r" "Restore factory values for preview" emacsvox-capitalization--cue-reset :transient t)
   ("D" "Discard preview edits" emacsvox-capitalization--cue-discard :transient t)
   ("A" "Apply global beep defaults" emacsvox-capitalization--cue-apply :transient t)
   ("S" "Save this cue in Customize" emacsvox-capitalization--cue-save :transient t)
   ("q" "Back (keep preview edits)" transient-quit-one)
   ("C-q" "Close menus (keep preview edits)" transient-quit-all)]
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
  "Choose capitalization indication, presentation, splitting, and global beep defaults."
  :refresh-suffixes t
  ["Capitalization"
   ("g" (lambda () (concat "Scope: " (emacsvox-aural-menu--scope-label))) emacsvox-aural-menu--toggle-scope :transient t)
   ("i" (lambda () (format "Indication: %s" (if (emacsvox-capitalization--value 'tts-caps) "on" "off"))) emacsvox-capitalization--indication :transient t)
   ("p" (lambda () (format "Presentation: %s" (emacsvox-capitalization--value 'emacsvox-capitalization-presentation))) emacsvox-capitalization--presentation :transient transient--do-stack)
   ("c" (lambda () (format "Split camel case: %s" (if (emacsvox-capitalization--value 'tts-split-caps) "on" "off"))) emacsvox-capitalization--split :transient t)
   ("SPC" "Preview reading settings" emacsvox-capitalization--preview :transient t)]
  ["Global beep defaults (save separately)"
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
