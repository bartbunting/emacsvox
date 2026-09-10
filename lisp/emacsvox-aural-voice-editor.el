;;; emacsvox-aural-voice-editor.el --- Common spoken voice editor -*- lexical-binding: t; -*-

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

;; One view for named voices and physical experiments, backed by retained
;; session drafts and the acknowledged save coordinator.  Shared tuning is the
;; default; optional row tuning preserves inheritance and native defaults.

;;; Code:

(require 'button)
(require 'emacsvox-aural-voice-editing)
(require 'emacsvox-aural-voice-workbench)
(defvar emacsvox-aural-voice-context--base)
(declare-function emacsvox-aural-voice-context-stop "emacsvox-aural-voice-context" ())
(declare-function omnivox-preview-voice-sequence "omnivox-voices" (entries callback))
(declare-function omnivox--choice-tuning-supported-p "omnivox-voices" (process))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--preview-layered-sequence "omnivox-preview" (entries callback &optional current))
(declare-function omnivox--preview-sequence "omnivox-preview" (entries callback individual &optional current))
(declare-function omnivox--preview-cancel "omnivox-preview" (operation))
(declare-function omnivox--preview-token-operation "omnivox-preview" (token))
(autoload 'emacsvox-aural-voice-context-open "emacsvox-aural-voice-context"
  "Inspect this voice draft in a captured source context." t)

(defvar emacsvox-aural-voice-editor--contexts (make-hash-table :test #'equal)
  "Retained editor context for each authoritative draft.")
(defvar emacsvox-aural-voice-editor--preview-owner nil
  "Context owning the current editor sample.")
(defvar-local emacsvox-aural-voice-editor--context nil)

(defun emacsvox-aural-voice-editor--submit-preview (entries callback current)
  "Submit private ENTRIES with CALLBACK while CURRENT still owns the view.
Select a faithful wire form before any entry interrupts foreground speech."
  (let* ((entries (tts--dispatch-copy-data entries))
         (process tts-speaker-process)
         (adapter tts-voice-preview-function)
         (omnivox (and (eq adapter #'omnivox-preview-voice-sequence)
                       (processp process) (process-live-p process)))
         (layered (and omnivox (omnivox--choice-tuning-supported-p process)))
         (individual (eq (plist-get (plist-get (car entries) :selection) :mode) 'choice))
         (prepared (unless layered (mapcar #'emacsvox-aural-voice-editing--legacy-preview entries)))
         (kind (if layered 'layered (if individual 'individual-audition 'shared-chain)))
         (receive
          (lambda (result)
            (setq result (copy-tree result))
            (cl-loop for item in (plist-get result :results) for entry in entries do
                     (plist-put item :request-snapshot (copy-tree entry)))
            (funcall callback (plist-put result :preview-kind kind)))))
    (unless (and (eq adapter tts-voice-preview-function) (eq process tts-speaker-process) (funcall current))
      (user-error "Preview input or connection changed during preparation"))
    (unless layered
      (cl-loop for entry in entries for legacy in prepared do
               (let* ((voice (plist-get entry :voice))
                      (id (plist-get (plist-get entry :selection) :choice-id))
                      (row (cl-find id (plist-get voice :choices) :test #'equal
                                    :key (lambda (choice) (plist-get choice :id))))
                      (customized (or (plist-get row :adjustments) (plist-get entry :context))))
                 (when (and individual customized)
                   (unless omnivox
                     (user-error "This adapter cannot faithfully audition individual tuning"))
                   (when (> (length entries) 1)
                     (user-error "Comparing individual tuning needs the complete voice-choice bundle; audition one row at a time"))
                   (let ((engine (plist-get (plist-get legacy :selector) :engine-id))
                         (disabled (plist-get entry :disabled-engine-ids)))
                     (when (and disabled (or (null engine) (member engine disabled)))
                       (user-error "This older audition cannot preserve the captured engine disablement")))
                   (when (and (plist-get legacy :effects)
                              (not (omnivox--process-supports-p process "post_synthesis_effects_v1")))
                     (user-error "This audition needs post-synthesis effect support"))
                   (when (and (numberp (plist-get legacy :rate-offset))
                              (/= (plist-get legacy :rate-offset) 0)
                              (not (omnivox--process-supports-p process "relative_rate_v1")))
                     (user-error "This audition needs relative rate support"))))))
    (cond (layered (omnivox--preview-layered-sequence entries receive current))
          (omnivox (omnivox--preview-sequence prepared receive individual current))
          (t (tts-preview-voices prepared receive) nil))))

(defun emacsvox-aural-voice-editor--invalidate (context)
  "Invalidate CONTEXT before cancelling its exact operation or notifying views."
  (when context
    (dolist (key '(:preview-generation :preview-operation :preview-startup :preview-result))
      (unless (plist-member context key) (nconc context (list key nil))))
    (setf (plist-get context :preview-generation) (1+ (or (plist-get context :preview-generation) 0)))
    (when (plist-get context :preview-result)
      (setf (plist-get context :preview-result) (plist-put (plist-get context :preview-result) :earlier t)))
    (let ((operation (plist-get context :preview-operation))
          (startup (plist-get context :preview-startup))
          (owned (eq emacsvox-aural-voice-editor--preview-owner context)))
      (setf (plist-get context :preview-operation) nil (plist-get context :preview-startup) nil)
      (when owned (setq emacsvox-aural-voice-editor--preview-owner nil))
      (cond (operation (omnivox--preview-cancel operation))
            ((and owned (not startup)) (tts-stop)))
      (when startup (omnivox--preview-cancel startup)))))

(defun emacsvox-aural-voice-editor--current-view (context generation revision buffer)
  "Whether CONTEXT's GENERATION and draft REVISION still belong to BUFFER."
  (and (buffer-live-p buffer) (eq buffer (plist-get context :buffer))
       (eq context (buffer-local-value 'emacsvox-aural-voice-editor--context buffer))
       (= generation (plist-get context :preview-generation))
       (= revision (emacsvox-aural-voice-draft-revision (plist-get context :draft)))))

(defun emacsvox-aural-voice-editor--start-entries (context entries revision)
  "Own prepared ENTRIES for CONTEXT at captured draft REVISION."
  (let* ((buffer (plist-get context :buffer))
         (adapter tts-voice-preview-function)
         (process tts-speaker-process)
         (generation (1+ (or (plist-get context :preview-generation) 0)))
         (current (lambda () (and (eq adapter tts-voice-preview-function) (eq process tts-speaker-process)
                                   (emacsvox-aural-voice-editor--current-view context generation revision buffer))))
         (startup (when (and (processp process) (eq adapter #'omnivox-preview-voice-sequence))
                    (cons process current)))
         returned operation)
    (emacsvox-aural-voice-editor--context-put context :preview-generation generation)
    (unless (funcall current) (user-error "Voice draft changed during preview preparation"))
    (when startup
      (when-let* ((previous (plist-get context :preview-startup))
                  (admitted (omnivox--preview-token-operation previous)))
        (emacsvox-aural-voice-editor--context-put context :preview-operation admitted))
      (emacsvox-aural-voice-editor--context-put context :preview-startup startup))
    (setq emacsvox-aural-voice-editor--preview-owner context)
    (unwind-protect
        (progn
          (setq operation
                (emacsvox-aural-voice-editor--submit-preview
                 entries
                 (lambda (result)
                   (when (funcall current)
                     (setq result (plist-put result :draft-revision revision))
                     (setq result (plist-put result :view-generation generation))
                     (setf (plist-get context :preview-result) (copy-tree result))
                     (when (eq emacsvox-aural-voice-editor--preview-owner context)
                       (setq emacsvox-aural-voice-editor--preview-owner nil))
                     (with-current-buffer buffer
                       (emacsvox-aural-voice-editor--put :preview-operation nil)
                       (emacsvox-aural-voice-editor-refresh))
                     (when (and (funcall current) (memq (plist-get result :status) '(failed error unsupported)))
                       (tts-notify (emacsvox-aural-voice-editor--preview-status result))))) current))
          (when (and (funcall current) (eq emacsvox-aural-voice-editor--preview-owner context))
            (emacsvox-aural-voice-editor--context-put context :preview-operation operation))
          (setq returned t))
      (when (and (not returned) (funcall current)
                 (eq emacsvox-aural-voice-editor--preview-owner context))
        (setq emacsvox-aural-voice-editor--preview-owner nil))
      (when (eq startup (plist-get context :preview-startup))
        (emacsvox-aural-voice-editor--context-put context :preview-startup nil)))))

(defun emacsvox-aural-voice-editor--get (key)
  "Read KEY from the current editor context."
  (plist-get emacsvox-aural-voice-editor--context key))
(defun emacsvox-aural-voice-editor--put (key value)
  "Store KEY with VALUE in the retained current context."
  (emacsvox-aural-voice-editor--context-put emacsvox-aural-voice-editor--context key value))
(defun emacsvox-aural-voice-editor--context-put (context key value)
  "Store KEY with VALUE in explicit CONTEXT, independent of buffer switches."
  (unless context (error "No voice editor context"))
  (unless (plist-member context key) (nconc context (list key nil)))
  (setf (plist-get context key) value))
(defun emacsvox-aural-voice-editor--draft ()
  "Return the current authoritative draft."
  (emacsvox-aural-voice-editor--get :draft))
(defun emacsvox-aural-voice-editor--working ()
  "Return a copy of the working voice."
  (copy-tree (emacsvox-aural-voice-draft-working (emacsvox-aural-voice-editor--draft))))

(defun emacsvox-aural-voice-editor--policy ()
  "Capture complete workstation policy including its startup default."
  (let* ((resolved (emacsvox-aural-voice-runtime--resolve 'bolden))
         (policy (copy-tree (plist-get resolved :policy))))
    (unless (plist-get policy :engine-order)
      (when-let* ((preferred (plist-get (tts-voice-inventory) :preferred-engine-id)))
        (setq policy (plist-put policy :engine-order (list preferred)))))
    policy))

(defun emacsvox-aural-voice-editor--context-for (palette voice &optional new)
  "Resume or capture a named PALETTE VOICE context without activation.
NEW prepares an explicit neutral voice, rejecting existing or reserved names."
  (let* ((profile (emacsvox-aural-routing-profile emacsvox-aural-active-routing-profile))
         (routing (and profile (copy-tree (emacsvox-aural-routing-profile-entry-data profile))))
         (opened
          (if new
              (progn
                (emacsvox-aural--validate-id voice "New voice name")
                (unless (eq voice (emacsvox-aural--canonical-voice-name voice))
                  (user-error "Reserved alias: %s; use %s" voice
                              (emacsvox-aural--canonical-voice-name voice)))
                (when (assq voice (emacsvox-aural-effective-voice-entries palette))
                  (user-error "Voice already exists: %s" voice))
                (list :name voice :owner palette
                      :snapshot '(:definition (:family nil :average-pitch nil
                                               :pitch-range nil :stress nil :richness nil)
                                  :selectors nil :choices nil :language nil)))
            (emacsvox-aural-voice-editing--snapshot palette voice routing)))
         (name (plist-get opened :name))
         (key (list 'base palette name)))
    (or (gethash key emacsvox-aural-voice-editor--contexts)
        (let ((context
               (list :draft (emacsvox-aural-voice-drafts--open key (emacsvox-aural-voice-editing--freeze (plist-get opened :snapshot) palette) (list palette))
                     :palette palette :voice name :routing routing :policy (emacsvox-aural-voice-editor--policy)
                     :destination palette :summary nil :owner (plist-get opened :owner)
                     :diagnostics (plist-get opened :diagnostics) :experiment nil :new new
                     :inventory (tts-voice-inventory)
                     :temporary (plist-get (emacsvox-aural-voice-runtime--resolve name palette) :session)
                     :text emacsvox-aural-voice-workbench-preview-text :expanded nil :effects nil
                     :automatic-sample t :preview-generation 0 :preview-result nil :origin nil :buffer nil)))
          (puthash key context emacsvox-aural-voice-editor--contexts)
          (when new
            (setf (emacsvox-aural-voice-draft-baseline (plist-get context :draft)) nil))
          context))))

(defun emacsvox-aural-voice-editor--button (id text command &optional dimension)
  "Insert a spoken field ID labelled TEXT invoking COMMAND, with DIMENSION."
  (insert "  ")
  (when (memq id '(fallbacks more))
    (setq text (emacsvox-aural-ui--expansion-text
                text (emacsvox-aural-voice-editor--get (if (eq id 'fallbacks) :expanded :effects)))))
  (insert-text-button text 'follow-link t 'voice-field id 'voice-dimension dimension
                      'action (lambda (button)
                                (goto-char (button-start button))
                                (funcall command)))
  (insert "\n"))

(defun emacsvox-aural-voice-editor--toggle (key field)
  "Toggle context KEY and announce FIELD's new state."
  (emacsvox-aural-voice-editor-stop)
  (let ((enabled (not (emacsvox-aural-voice-editor--get key))))
    (emacsvox-aural-voice-editor--put key enabled)
    (emacsvox-aural-voice-editor-refresh)
    (emacsvox-aural-voice-editor--locate field)
    (if (memq key '(:expanded :effects))
        (emacsvox-aural-ui--announce-expansion enabled)
      (emacsvox-aural-ui--call-with-feedback
       (if enabled 'on 'off) #'emacsvox-aural-voice-editor-speak))))

(defun emacsvox-aural-voice-editor--locate (field)
  "Move to the button identified by FIELD, or the first available button."
  (goto-char (point-min))
  (let ((button (next-button (point-min))) found)
    (while (and button (not found))
      (if (equal field (button-get button 'voice-field)) (setq found button)
        (setq button (next-button (button-end button)))))
    (when (or found (setq found (next-button (point-min)))) (goto-char (button-start found)))))

(defun emacsvox-aural-voice-editor--adjustment-text (dimension style chain)
  "Describe DIMENSION's value, change and advertised support for CHAIN."
  (let* ((key (emacsvox-aural--voice-dimension-key dimension))
         (value (plist-get style key))
         (baseline (emacsvox-aural-voice-editor--tuning-style
                    (emacsvox-aural-voice-draft-baseline (emacsvox-aural-voice-editor--draft))
                    (emacsvox-aural-voice-editor--get :palette)))
         (engine (cl-find (plist-get (car chain) :engine-id)
                          (plist-get (emacsvox-aural-voice-editor--get :inventory) :engines)
                          :key (lambda (entry) (plist-get entry :engine-id)) :test #'equal))
         (emacsvox-aural-voice-tuner-route-engine engine)
         (emacsvox-aural-voice-tuner-route-selector (car chain)))
    (concat (emacsvox-aural-voice-tuner--dimension-label dimension) ": "
            (when (emacsvox-aural-voice-editor--get :tuning-choice)
              (let ((patch (plist-get (emacsvox-aural-voice-editor--tuning-row) :adjustments)))
                (cond ((not (plist-member patch key)) "use shared value — ")
                      ((null (plist-get patch key)) "explicit ")
                      (t "custom value — "))))
            (emacsvox-aural-voice-tuner--value-description dimension value)
            (unless (and (equal value (plist-get baseline key))
                         (or (not (emacsvox-aural-voice-editor--get :tuning-choice))
                             (let* ((old (plist-get (emacsvox-aural-voice-editor--tuning-row
                                                    (emacsvox-aural-voice-draft-baseline (emacsvox-aural-voice-editor--draft))) :adjustments))
                                    (new (plist-get (emacsvox-aural-voice-editor--tuning-row) :adjustments)))
                               (equal (and (plist-member old key) (list (plist-get old key)))
                                      (and (plist-member new key) (list (plist-get new key)))))))
              (format " [changed; was %s]" (emacsvox-aural-voice-tuner--value-description dimension (plist-get baseline key))))
            (cond ((eq dimension 'family) " [portable fallback; not part of full preview]")
                  ((and engine (not (emacsvox-aural-voice-tuner--supported-p dimension)))
                   (if (emacsvox-aural-voice-editor--get :tuning-choice)
                       " [unsupported by this engine; value retained]"
                     " [unsupported by the preferred engine; value retained]"))
                  ((and chain (not engine)) " [engine support not known]")))))

(defun emacsvox-aural-voice-editor--tuning-row (&optional snapshot)
  "Return the selected row in SNAPSHOT, or nil when absent or editing shared."
  (when-let* ((id (emacsvox-aural-voice-editor--get :tuning-choice)))
    (cl-find id (emacsvox-aural-voice-editing--rows
                 (or snapshot (emacsvox-aural-voice-editor--working)))
             :test #'equal :key (lambda (row) (plist-get row :id)))))

(defun emacsvox-aural-voice-editor--tuning-style (snapshot palette)
  "Return raw shared or selected-row settings in SNAPSHOT from PALETTE."
  (let ((style (emacsvox-aural-voice-editing--style snapshot palette))
        (patch (copy-tree (plist-get (emacsvox-aural-voice-editor--tuning-row snapshot) :adjustments))))
    (while patch (setq style (plist-put style (pop patch) (pop patch))))
    style))

(defun emacsvox-aural-voice-editor--customize (id)
  "Open optional tuning for stable ID, or return to shared settings for nil."
  (when (and id (not (cl-find id (emacsvox-aural-voice-editing--rows (emacsvox-aural-voice-editor--working))
                            :test #'equal :key (lambda (row) (plist-get row :id)))))
    (user-error "This fallback row no longer exists"))
  (emacsvox-aural-voice-editor-stop)
  (emacsvox-aural-voice-editor--put :tuning-choice id)
  (emacsvox-aural-voice-editor-refresh)
  (emacsvox-aural-voice-editor--locate (if id 'tuning-scope 'fallbacks))
  (emacsvox-aural-voice-editor-speak))

(defun emacsvox-aural-voice-editor--inherit ()
  "Make the selected row's current dimension follow shared settings."
  (interactive)
  (emacsvox-aural-voice-editor--set-choice
   (or (get-text-property (point) 'voice-dimension) (user-error "Choose an adjustment field"))
   'inherit nil))

(defun emacsvox-aural-voice-editor--set-choice (dimension operation value)
  "Apply OPERATION and stored VALUE to the selected row's DIMENSION."
  (let* ((id (or (emacsvox-aural-voice-editor--get :tuning-choice) (user-error "Choose a fallback to customize first")))
         (snapshot (emacsvox-aural-voice-editor--working))
         (rows (emacsvox-aural-voice-data--adjust-choice
                (emacsvox-aural-voice-editing--rows snapshot) id
                (emacsvox-aural--voice-dimension-key dimension) operation value)))
    (emacsvox-aural-voice-editor--changed
     (plist-put snapshot :choices rows)
     (pcase operation
       ('inherit (format "Use shared value, %s"
                         (emacsvox-aural-voice-tuner--value-description
                          dimension (plist-get (emacsvox-aural-voice-editing--style snapshot
                                                (emacsvox-aural-voice-editor--get :palette))
                                               (emacsvox-aural--voice-dimension-key dimension)))))
       ('default "Adapter default")
       (_ (format "%s" (emacsvox-aural-voice-tuner--control-value dimension value)))))))

(defun emacsvox-aural-voice-editor--preview-status (result)
  "Describe RESULT without confusing spoken labels or accepted audio with starts."
  (if (eq (plist-get result :preview-kind) 'layered)
      (let* ((samples (cl-remove-if-not
                       (lambda (entry) (eq (plist-get (plist-get entry :request-snapshot) :role) 'sample))
                       (plist-get result :results)))
             (latest (car (last samples)))
             (started (cl-find-if (lambda (entry) (plist-get entry :last-started)) (reverse samples)))
             (identity (plist-get started :last-started))
             (physical (plist-get identity :realized))
             (rows (plist-get (plist-get (plist-get started :request-snapshot) :voice) :choices))
             (position (cl-position (plist-get identity :choice_id) rows :test #'equal
                                    :key (lambda (row) (plist-get row :id))))
             (accepted (cl-some (lambda (entry) (> (length (plist-get entry :accepted-audio)) 0)) samples))
             (degraded (append (plist-get identity :degraded_acss) (plist-get identity :degraded_effects) nil)))
        (concat (if (plist-get result :earlier) "Earlier preview " "Preview ")
                (format "%s" (plist-get result :status))
                (if identity
                    (format "; last sample playback started on %s/%s; %s"
                            (plist-get physical :engine_id) (plist-get physical :voice_id)
                            (if (eq (plist-get identity :choice_id) :null) "policy fallback"
                              (format "choice %s" (if position (1+ position) "from this sample"))))
                  (if accepted "; audio accepted; no sample start confirmed" "; no sample start confirmed"))
                (unless (plist-get latest :terminal-confirmed) "; latest sample playback unconfirmed")
                (when degraded (format "; unsupported adjustments: %s"
                                        (mapconcat (lambda (field) (replace-regexp-in-string "_" " " field)) degraded ", ")))
                (when (plist-get result :message) (format "; %s" (plist-get result :message)))))
    (let* ((played (delete-dups (apply #'append (mapcar (lambda (entry) (copy-tree (plist-get entry :realizations)))
                                                       (plist-get result :results)))))
         (last (car (last (plist-get result :results))))
         (degraded (append (plist-get last :degraded-acss) (plist-get last :degraded-effects))))
    (format "%s%s %s%s%s%s%s" (if (plist-get result :earlier) "Earlier " "")
            (if (eq (plist-get result :preview-kind) 'individual-audition) "Individual audition" "Preview")
            (or (plist-get result :status) "not played")
            (if (eq (plist-get result :completion-guarantee) 'queued-only) "; playback unconfirmed" "")
            (if played (format "; audio from %s" (mapconcat (lambda (voice)
                                                              (format "%s/%s" (plist-get voice :engine-id) (plist-get voice :voice-id))) played ", ")) "")
            (if degraded (format "; unsupported adjustments: %s" degraded) "")
            (if (or (plist-get result :message) (plist-get last :message))
                (format "; %s" (or (plist-get result :message) (plist-get last :message))) "")))))

(defun emacsvox-aural-voice-editor-refresh ()
  "Refresh the common editor, preserving the current field and point's column."
  (interactive)
  (let* ((field (get-text-property (point) 'voice-field)) (column (current-column))
         (draft (emacsvox-aural-voice-editor--draft))
         (snapshot (emacsvox-aural-voice-editor--working))
         (palette (emacsvox-aural-voice-editor--get :palette))
         (voice (emacsvox-aural-voice-editor--get :voice))
         (tuning (emacsvox-aural-voice-editor--get :tuning-choice))
         (row (emacsvox-aural-voice-editor--tuning-row snapshot))
         (style (emacsvox-aural-voice-editor--tuning-style snapshot palette))
         (chain (plist-get snapshot :selectors))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (format "Edit %s — %s\n%s\n\n"
                    (or voice "physical voice experiment") (or palette "no destination yet")
                    (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))
    (insert (if voice "Shared settings provide the base for every fallback choice. Customized rows can override them.\n"
              "Temporary experiment. Choose a destination before saving.\n"))
    (when (emacsvox-aural-voice-editor--get :temporary)
      (insert "Temporary routing is active. Base previews and saves exclude it.\n"))
    (when (emacsvox-aural-voice-editor--get :diagnostics)
      (insert "Local choices are missing; preview uses the portable fallback.\n"))
    (when (and palette (not (emacsvox-aural-voice-runtime--owned-p palette)))
      (insert (format "Legacy source: %s; routing profile: %s. First save creates an independent copy.\n"
                      palette (or (plist-get (emacsvox-aural-voice-editor--get :routing) :id) "Automatic"))))
    (when (and palette (not (eq palette (emacsvox-aural-effective-voice-palette))))
      (insert "This palette is inactive. Save and apply will select it for this session.\n"))
    (insert "\nDestination\n")
    (emacsvox-aural-voice-editor--button 'save
                                         (if voice
                                             (format "%s to %s"
                                                     (if (when-let* ((save (emacsvox-aural-voice-draft-proposal draft)))
                                                           (memq (emacsvox-aural-voice-save-state save) '(partial failed apply-failed)))
                                                         "Retry save and apply" "Save and apply") voice)
                                           "Choose where to use this voice")
                                         #'emacsvox-aural-voice-editor-save)
    (when voice
      (emacsvox-aural-voice-editor--button 'collection "Save to collection without selecting"
                                           #'emacsvox-aural-voice-editor-save-to-collection))
    (insert "\nPhysical voice\n")
    (emacsvox-aural-voice-editor--button 'primary
                                         (if chain (emacsvox-aural-voice-workbench--selector-description (car chain)) "Automatic selection")
                                         (lambda () (emacsvox-aural-voice-editor-choose 0)))
    (when voice
      (emacsvox-aural-voice-editor--button 'fallbacks
                                           (format "Fallbacks: %s" (if (cdr chain) (format "%d explicit" (length (cdr chain))) "Automatic"))
                                           (lambda () (emacsvox-aural-voice-editor--toggle :expanded 'fallbacks)))
      (when (emacsvox-aural-voice-editor--get :expanded)
        (cl-loop for choice in chain for index from 0 do
                 (let ((selected (plist-get (nth index (emacsvox-aural-voice-editing--rows snapshot)) :id)))
                   (emacsvox-aural-voice-editor--button (cons 'choice index)
                                                        (format "%d. %s — %s" (1+ index)
                                                                (emacsvox-aural-voice-workbench--selector-description choice)
                                                                (if (plist-get (nth index (plist-get snapshot :choices)) :adjustments)
                                                                    "customized" "uses shared settings"))
                                                        (lambda () (emacsvox-aural-voice-editor-choice-actions selected)))))
        (emacsvox-aural-voice-editor--button 'add "Add fallback" (lambda () (emacsvox-aural-voice-editor-choose nil)))
        (emacsvox-aural-voice-editor--button 'automatic "Use Automatic; clear explicit choices" #'emacsvox-aural-voice-editor-automatic)
        (insert (format "  After explicit choices: workstation engine order %s; fallback engines %s.\n"
                        (plist-get (emacsvox-aural-voice-editor--get :policy) :engine-order)
                        (plist-get (plist-get (emacsvox-aural-voice-editor--get :policy) :fallback) :engines))))
      )
    (insert (if tuning "\nIndividual fallback adjustments\n" "\nShared adjustments\n"))
    (when tuning
      (emacsvox-aural-voice-editor--button
       'tuning-scope
       (if row (format "Customizing choice %d, %s; return to shared settings"
                       (1+ (cl-position tuning (emacsvox-aural-voice-editing--rows snapshot)
                                         :test #'equal :key (lambda (item) (plist-get item :id))))
                       (emacsvox-aural-voice-workbench--selector-description (plist-get row :selector)))
         "This fallback was removed; return to shared settings")
       (lambda () (emacsvox-aural-voice-editor--customize nil))))
    (insert "Left/right adjusts numeric fields; otherwise moves between fields.\n"
            "RET edits a value; d restores adapter default. Zero is an explicit value.\n")
    (when tuning (insert "RET also offers Use shared value; i restores inheritance. Only this row changes.\n"))
    (dolist (dimension (unless (and tuning (null row))
                        (append '(rate-offset average-pitch pitch-range stress richness)
                               (when (emacsvox-aural-voice-editor--get :effects)
                                 (append (unless tuning '(family))
                                         '(gain low-pass high-pass pan reverb echo chorus))))))
      (let ((field dimension))
        (emacsvox-aural-voice-editor--button dimension
                                             (emacsvox-aural-voice-editor--adjustment-text
                                              dimension style (if tuning (list (plist-get row :selector)) chain))
                                             (lambda () (emacsvox-aural-voice-editor-edit field)) dimension)))
    (emacsvox-aural-voice-editor--button 'more
                                         "More adjustments and effects"
                                         (lambda () (emacsvox-aural-voice-editor--toggle :effects 'more)))
    (insert "\nListen — base voice, without contextual rules\n")
    (emacsvox-aural-voice-editor--button 'play (if tuning "Audition this choice" "Play edited") #'emacsvox-aural-voice-editor-play)
    (emacsvox-aural-voice-editor--button 'compare (if tuning "Compare original and edited choice" "Compare original and edited") #'emacsvox-aural-voice-editor-compare)
    (when tuning
      (emacsvox-aural-voice-editor--button 'play-chain "Play whole fallback chain"
                                            (lambda () (emacsvox-aural-voice-editor--preview nil))))
    (emacsvox-aural-voice-editor--button 'stop "Stop sample" #'emacsvox-aural-voice-editor-stop)
    (emacsvox-aural-voice-editor--button 'text (format "Sample text: %s" (emacsvox-aural-voice-editor--get :text))
                                         #'emacsvox-aural-voice-editor-text)
    (emacsvox-aural-voice-editor--button 'auto-sample
                                         (format "Automatic sample after adjustment: %s" (if (emacsvox-aural-voice-editor--get :automatic-sample) "on" "off"))
                                         (lambda () (emacsvox-aural-voice-editor--toggle :automatic-sample 'auto-sample)))
    (when (emacsvox-aural-voice-editor--get :preview-result)
      (emacsvox-aural-voice-editor--button 'preview-status
                                           (emacsvox-aural-voice-editor--preview-status (emacsvox-aural-voice-editor--get :preview-result))
                                           #'emacsvox-aural-voice-editor-speak))
    (insert "\nChanges and recovery\n")
    (insert (format "  Changes: %s\n"
                    (or (mapconcat (lambda (field) (pcase field
                                                     (:definition "shared adjustments") (:selectors "physical choices")
                                                     (:choices "fallback choices or custom adjustments")
                                                     (:language "language") (:reset-choices "Automatic selection")
                                                     (_ "voice settings")))
                                   (emacsvox-aural-voice-drafts--dirty-fields draft) ", ") "none")))
    (when-let* ((proposal (emacsvox-aural-voice-draft-proposal draft))
                (message (plist-get (emacsvox-aural-voice-save-result proposal) :message)))
      (insert (format "  Last save: %s\n" message)))
    (emacsvox-aural-voice-editor--button 'undo "Undo last edit" #'emacsvox-aural-voice-editor-undo)
    (emacsvox-aural-voice-editor--button 'leave "Leave and keep draft for this session" #'emacsvox-aural-voice-editor-leave)
    (emacsvox-aural-voice-editor--button 'details "Details and last playback evidence" #'emacsvox-aural-voice-editor-details)
    (when voice
      (emacsvox-aural-voice-editor--button 'context "Effective sound / Where settings came from…"
                                           #'emacsvox-aural-voice-context-open))
    (setq header-line-format (format "%s | %s" (or voice "Experiment")
                                     (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))
    (emacsvox-aural-voice-editor--locate field)
    (when field (move-to-column column))))

(defun emacsvox-aural-voice-editor-stop ()
  "Stop this editor's sample without stopping another editor's newer preview."
  (interactive)
  (emacsvox-aural-voice-editor--invalidate emacsvox-aural-voice-editor--context))
(defun emacsvox-aural-voice-editor-speak ()
  "Read the current labelled field using the ordinary navigation voice."
  (interactive)
  (emacsvox-aural-voice-editor-stop)
  (emacsvox-aural-ui--speak-control (if-let* ((button (button-at (point)))) (button-label button)
                             (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))
(defun emacsvox-aural-voice-editor-next ()
  "Move to and read the next editor field."
  (interactive) (emacsvox-aural-voice-editor--move-field 1))
(defun emacsvox-aural-voice-editor-previous ()
  "Move to and read the previous editor field."
  (interactive) (emacsvox-aural-voice-editor--move-field -1))

(defun emacsvox-aural-voice-editor--move-field (direction)
  "Move in DIRECTION without wrapping, announcing the field or boundary."
  (let* ((current (button-at (point)))
         (next (if (> direction 0)
                   (next-button (if current (button-end current) (point)))
                 (previous-button (if current (button-start current) (point))))))
    (if next
        (progn (goto-char (button-start next))
               (emacsvox-aural-voice-editor-speak))
      (emacsvox-aural-voice-editor-stop)
      (emacsvox-aural-ui-speak
       (format "%s field%s" (if (> direction 0) "Last" "First")
               (if current (concat ". " (button-label current)) ""))))))

(defun emacsvox-aural-voice-editor--changed (snapshot &optional value-label)
  "Install SNAPSHOT and prefix its automatic sample with VALUE-LABEL."
  (emacsvox-aural-voice-drafts--edit (emacsvox-aural-voice-editor--draft) snapshot)
  (emacsvox-aural-voice-editor-refresh)
  (if (emacsvox-aural-voice-editor--get :automatic-sample)
      (progn
        (emacsvox-aural-voice-editor-stop)
        (condition-case err (emacsvox-aural-voice-editor--preview nil (emacsvox-aural-voice-editor--get :tuning-choice) value-label)
          (error (emacsvox-aural-ui-speak
                  (format "Changes kept. Preview unavailable: %s" (error-message-string err))))))
    (emacsvox-aural-voice-editor-speak)))

(defun emacsvox-aural-voice-editor--set (dimension displayed)
  "Set DIMENSION from DISPLAYED control units, retaining stored cutoff semantics."
  (when (and displayed (not (eq dimension 'family)))
    (let* ((metadata (emacsvox-aural--voice-style-field dimension))
           (minimum (plist-get metadata :minimum))
           (maximum (plist-get metadata :maximum)))
      (unless (and (integerp displayed) (<= minimum displayed maximum))
        (user-error "Enter a whole number from %s to %s, or leave blank for adapter default"
                    minimum maximum))))
  (if (emacsvox-aural-voice-editor--get :tuning-choice)
      (emacsvox-aural-voice-editor--set-choice
       dimension (if displayed 'set 'default)
       (emacsvox-aural-voice-tuner--stored-value dimension displayed))
    (emacsvox-aural-voice-editor--changed
     (emacsvox-aural-voice-editing--adjust
      (emacsvox-aural-voice-editor--working) (emacsvox-aural-voice-editor--get :palette) dimension
      (emacsvox-aural-voice-tuner--stored-value dimension displayed))
     (if displayed (format "%s" displayed) "Adapter default"))))
(defun emacsvox-aural-voice-editor-edit (&optional dimension)
  "Edit DIMENSION or the current numeric field; blank means adapter default."
  (interactive)
  (let* ((dimension (or dimension (get-text-property (point) 'voice-dimension)
                        (user-error "Choose an adjustment field")))
         (context emacsvox-aural-voice-editor--context)
         (revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft)))
         (choice (emacsvox-aural-voice-editor--get :tuning-choice))
         (action (if choice (completing-read "Adjustment: " '("Set value" "Use shared value" "Adapter default") nil t) "Set value"))
         (input (if (equal action "Set value") (read-string (format "%s (blank for adapter default): " dimension)) ""))
         (value (unless (string-empty-p input)
                  (if (eq dimension 'family) (intern input)
                    (unless (string-match-p "\\`[+-]?[0-9]+\\'" input) (user-error "Enter a whole number"))
                    (string-to-number input)))))
    (unless (and (eq context emacsvox-aural-voice-editor--context)
                 (equal choice (emacsvox-aural-voice-editor--get :tuning-choice))
                 (= revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft))))
      (user-error "Voice changed while editing; choose the adjustment again"))
    (if (equal action "Use shared value")
        (emacsvox-aural-voice-editor--set-choice dimension 'inherit nil)
      (emacsvox-aural-voice-editor--set dimension value))))

(defun emacsvox-aural-voice-editor-default ()
  "Restore the current adjustment to the adapter default and audition it."
  (interactive)
  (emacsvox-aural-voice-editor--set
   (or (get-text-property (point) 'voice-dimension)
       (user-error "Choose an adjustment to restore its adapter default"))
   nil))

(defun emacsvox-aural-voice-editor-activate ()
  "Activate the current field, leaving its spoken result as the final feedback."
  (interactive)
  (let ((button (or (button-at (point)) (user-error "Choose an editor field"))))
    ;; Toggles own their state cue. Other actions attach a button cue to their
    ;; spoken result or prompt; previews retain their own playback transaction.
    (if (memq (button-get button 'voice-field) '(more fallbacks auto-sample))
        (button-activate button)
      (emacsvox-aural-ui--call-with-feedback 'button (lambda () (button-activate button))))))
(defun emacsvox-aural-voice-editor-adjust (delta)
  "Adjust the current field by DELTA in displayed units."
  (let* ((dimension (or (get-text-property (point) 'voice-dimension) (user-error "Choose a numeric adjustment")))
         (style (emacsvox-aural-voice-editor--tuning-style (emacsvox-aural-voice-editor--working)
                                                     (emacsvox-aural-voice-editor--get :palette)))
         (value (plist-get style (emacsvox-aural--voice-dimension-key dimension))))
    (when (eq dimension 'family) (user-error "Press RET to choose a family"))
    (let* ((metadata (emacsvox-aural--voice-style-field dimension))
           (minimum (plist-get metadata :minimum))
           (maximum (plist-get metadata :maximum))
           (current (emacsvox-aural-voice-tuner--control-value dimension value))
           (next (max minimum (min maximum (+ delta (or current (if (memq dimension '(gain pan)) 5 0)))))))
      (if (equal current next)
          (progn
            (emacsvox-aural-voice-editor-stop)
            (emacsvox-aural-ui-speak
             (format "%s %s" (if (> delta 0) "Maximum" "Minimum") next)))
        (emacsvox-aural-voice-editor--set dimension next)))))
(defun emacsvox-aural-voice-editor-increase ()
  "Increase a numeric adjustment, or move to the next field."
  (interactive)
  (if (memq (get-text-property (point) 'voice-dimension) '(nil family))
      (emacsvox-aural-voice-editor-next)
    (emacsvox-aural-voice-editor-adjust 1)))
(defun emacsvox-aural-voice-editor-decrease ()
  "Decrease a numeric adjustment, or move to the previous field."
  (interactive)
  (if (memq (get-text-property (point) 'voice-dimension) '(nil family))
      (emacsvox-aural-voice-editor-previous)
    (emacsvox-aural-voice-editor-adjust -1)))

(defun emacsvox-aural-voice-editor--pick ()
  "Search the inventory and audition candidates before choosing a selector."
  (let* ((emacsvox-aural-voice-workbench-inventory (tts-voice-inventory))
         (choices (emacsvox-aural-voice-workbench--physical-candidates))
         selected)
    (unless choices (user-error "No available physical voices"))
    (unwind-protect
        (while (not selected)
          (let* ((name (completing-read "Physical voice (search engine or name): " choices nil t))
                 (pair (cdr (assoc name choices)))
                 (selector (list :kind 'exact :scope 'local :engine-id (plist-get (car pair) :engine-id)
                                 :voice-id (plist-get (cadr pair) :voice-id)))
                 action)
            (unless pair (user-error "No physical voice selected"))
            (while (not (member action '("Use this voice" "Search again" "Cancel")))
              (setq action (completing-read (format "%s: " name)
                                            '("Use this voice" "Audition candidate" "Search again" "Cancel") nil t))
              (when (equal action "Audition candidate")
                (let* ((snapshot (plist-put (emacsvox-aural-voice-editor--working) :selectors (list selector)))
                       (_ (setq snapshot (plist-put snapshot :choices
                                                    (list (list :id "candidate" :selector selector :adjustments nil)))))
                       (entry (emacsvox-aural-voice-editing--cascade
                               snapshot (emacsvox-aural-voice-editor--get :palette)
                               (emacsvox-aural-voice-editor--get :policy) (emacsvox-aural-voice-editor--get :text)
                               nil "candidate")))
                  (emacsvox-aural-voice-editor--start-entries
                   emacsvox-aural-voice-editor--context (list entry)
                   (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft))))))
            (emacsvox-aural-voice-editor-stop)
            (pcase action
              ("Cancel" (user-error "Choice unchanged"))
              ("Use this voice" (setq selected selector)))))
      (emacsvox-aural-voice-editor-stop))
    selected))
(defun emacsvox-aural-voice-editor-choose (choice)
  "Replace stable CHOICE (or a current index), or append when CHOICE is nil."
  (let* ((snapshot (emacsvox-aural-voice-editor--working))
         (revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft)))
         (rows (emacsvox-aural-voice-editing--rows snapshot))
         (index (if (stringp choice) (cl-position choice rows :test #'equal :key (lambda (row) (plist-get row :id))) choice))
         (row (and index (nth index rows)))
         (selector (progn (when (and (stringp choice) (null index)) (user-error "This fallback row no longer exists"))
                           (emacsvox-aural-voice-editor--pick)))
         (replacement (emacsvox-aural-voice-editor--replacement row)))
    (unless (= revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft)))
      (user-error "Voice changed while choosing a replacement; choose the row again"))
    (emacsvox-aural-voice-editor--changed
     (emacsvox-aural-voice-editing--keep snapshot
                                         (list :selectors (list selector)) 'physical
                                         (if index 'replace 'fallback) index replacement))))

(defun emacsvox-aural-voice-editor--replacement (row)
  "Choose explicitly whether replacement ROW should retain its custom settings."
  (if (not (plist-get row :adjustments)) 'keep
    (if (equal (completing-read "New physical voice may need different tuning: "
                                '("Use shared settings" "Keep this row's custom settings") nil t)
               "Use shared settings") 'reset 'keep)))
(defun emacsvox-aural-voice-editor-automatic ()
  "Explicitly replace the saved choice chain with Automatic."
  (interactive)
  (let ((snapshot (emacsvox-aural-voice-editor--working)))
    (setq snapshot (plist-put snapshot :selectors nil))
    (setq snapshot (plist-put snapshot :choices nil))
    (emacsvox-aural-voice-editor--changed (plist-put snapshot :reset-choices t))))
(defun emacsvox-aural-voice-editor-choice-actions (choice)
  "Edit, reorder, remove or audition stable CHOICE (or a current index)."
  (let* ((snapshot (emacsvox-aural-voice-editor--working))
         (revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft)))
         (rows (emacsvox-aural-voice-editing--rows snapshot))
         (index (if (stringp choice) (cl-position choice rows :test #'equal :key (lambda (row) (plist-get row :id))) choice))
         (id (and index (plist-get (nth index rows) :id)))
         (action (progn (unless id (user-error "This fallback row no longer exists"))
                        (completing-read "Choice action: " '("Replace" "Move earlier" "Move later" "Remove" "Audition this choice"
                                                               "Compare original and edited choice" "Customize this voice") nil t))))
    (unless id (user-error "This fallback row no longer exists"))
    (unless (= revision (emacsvox-aural-voice-draft-revision (emacsvox-aural-voice-editor--draft)))
      (user-error "Voice changed while choosing an action; choose the row again"))
    (pcase action
      ("Replace" (emacsvox-aural-voice-editor-choose id))
      ("Customize this voice" (emacsvox-aural-voice-editor--customize id))
      ("Audition this choice" (emacsvox-aural-voice-editor--preview nil id))
      ("Compare original and edited choice" (emacsvox-aural-voice-editor--preview t id))
      (_ (if (equal action "Remove") (setq rows (append (cl-subseq rows 0 index) (nthcdr (1+ index) rows)))
           (let ((target (+ index (if (equal action "Move earlier") -1 1))))
             (unless (< -1 target (length rows)) (user-error "Already at the boundary"))
             (setq rows (emacsvox-aural-voice-data--move-choice rows id target))))
         (setq snapshot (plist-put snapshot :choices rows))
         (emacsvox-aural-voice-editor--changed
          (plist-put snapshot :selectors (emacsvox-aural-voice-data--selectors rows)))))))

(defun emacsvox-aural-voice-editor--preview (compare &optional individual value-label)
  "Preview COMPARE or INDIVIDUAL voices, prefixing sample text with VALUE-LABEL."
  (let* ((context emacsvox-aural-voice-editor--context)
         (draft (emacsvox-aural-voice-editor--draft))
         (revision (emacsvox-aural-voice-draft-revision draft))
         (policy (emacsvox-aural-voice-editor--get :policy))
         (text (concat (when value-label (concat value-label ". "))
                       (emacsvox-aural-voice-editor--get :text)))
         (palette (emacsvox-aural-voice-editor--get :palette))
         (working (emacsvox-aural-voice-draft-working draft))
         (id (cond ((stringp individual) individual)
                   ((or individual (not (emacsvox-aural-voice-editor--get :voice)))
                    (or (plist-get (nth (or individual 0) (emacsvox-aural-voice-editing--rows working)) :id)
                        (user-error "No physical row to audition")))))
         (snapshots (append (when compare (list (emacsvox-aural-voice-draft-original draft)))
                            (list working))) entries)
    (cl-loop for snapshot in snapshots for index from 0 do
             (let ((entry (emacsvox-aural-voice-editing--cascade snapshot palette policy text nil id)))
               (setq entry (plist-put entry :variant (if (and compare (= index 0)) 'original 'edited)))
               (setq entries (append entries
                                     (if compare
                                         (let ((label (if (= index 0) "Original" "Edited")))
                                           (list (plist-put (plist-put (copy-tree entry) :text (concat label ".")) :role 'label) entry))
                                       (list entry))))))
    (emacsvox-aural-voice-editor--start-entries context entries revision)))
(defun emacsvox-aural-voice-editor-play () "Play the edited voice or selected tuning row without saving." (interactive) (emacsvox-aural-voice-editor--preview nil (emacsvox-aural-voice-editor--get :tuning-choice)))
(defun emacsvox-aural-voice-editor-compare () "Compare original and edited voices, or the selected tuning row." (interactive) (emacsvox-aural-voice-editor--preview t (emacsvox-aural-voice-editor--get :tuning-choice)))
(defun emacsvox-aural-voice-editor-text ()
  "Change the common comparison text."
  (interactive)
  (let ((text (read-string "Sample text: " (emacsvox-aural-voice-editor--get :text))))
    (when (string-empty-p text) (user-error "Sample text must not be empty"))
    (emacsvox-aural-voice-editor-stop)
    (emacsvox-aural-voice-editor--put :text text) (emacsvox-aural-voice-editor-refresh)))
(defun emacsvox-aural-voice-editor-undo ()
  "Undo the last draft change."
  (interactive) (emacsvox-aural-voice-drafts--undo (emacsvox-aural-voice-editor--draft))
  (emacsvox-aural-voice-editor-refresh) (emacsvox-aural-voice-editor-speak))

(defun emacsvox-aural-voice-editor--destination ()
  "Choose a personal palette before preparing the first save."
  (let* ((palette (emacsvox-aural-voice-editor--get :palette))
         (record (gethash palette emacsvox-aural-voice-palette-registry)))
    (if (and (emacsvox-aural-voice-runtime--owned-p palette)
             (not (emacsvox-aural-voice-palette-built-in record))) palette
      (or (let ((chosen (emacsvox-aural-voice-editor--get :destination)))
            (and (not (eq chosen palette)) chosen))
          (let* ((name (read-string "New personal palette: " (format "%s-personal" palette)))
                 (id (intern name)))
            (when (or (string-empty-p name) (gethash id emacsvox-aural-voice-palette-registry))
              (user-error "Choose an unused palette name"))
            (emacsvox-aural-voice-editor--put :destination id)
            id)))))

(defun emacsvox-aural-voice-editor--save (select)
  "Save the current voice with explicit SELECT behavior."
  (if (not (emacsvox-aural-voice-editor--get :voice))
      (emacsvox-aural-voice-editor-keep-experiment)
    (let* ((draft (emacsvox-aural-voice-editor--draft))
           (previous (emacsvox-aural-voice-draft-proposal draft))
           (palette (emacsvox-aural-voice-editor--get :palette))
           (voice (emacsvox-aural-voice-editor--get :voice))
           (proposal
            (if (and previous (memq (emacsvox-aural-voice-save-state previous)
                                    '(partial failed apply-failed applying))) previous
              (let* ((destination (emacsvox-aural-voice-editor--destination))
                     (data (emacsvox-aural-voice-editing--proposal
                            palette voice (emacsvox-aural-voice-editor--working) destination
                            (format "Personal voices based on %s" palette)
                            (emacsvox-aural-voice-editor--get :routing)
                            (emacsvox-aural-voice-editor--get :new))))
                (emacsvox-aural-voice-drafts--prepare draft (plist-get data :palette) (plist-get data :choice-sets)
                                                      :select select :sources (list palette))))))
      (unless (eq (and select t) (and (emacsvox-aural-voice-save-select proposal) t))
        (user-error "The pending save has a different activation choice; retry its original save action"))
      (emacsvox-aural-voice-drafts--save proposal)
      (when (memq 'published (emacsvox-aural-voice-save-completed proposal))
        (let* ((destination (plist-get (emacsvox-aural-voice-save-palette proposal) :id))
               (old-key (emacsvox-aural-voice-draft-key draft)) (key (list 'base destination voice)))
          (unless (equal old-key key)
            (remhash old-key emacsvox-aural-voice-drafts--registry)
            (remhash old-key emacsvox-aural-voice-editor--contexts)
            (setf (emacsvox-aural-voice-draft-key draft) key)
            (puthash key draft emacsvox-aural-voice-drafts--registry)
            (puthash key emacsvox-aural-voice-editor--context emacsvox-aural-voice-editor--contexts))
          (setf (emacsvox-aural-voice-draft-watches draft)
                (emacsvox-aural-voice-drafts--watch (list destination)))
          (emacsvox-aural-voice-editor--put :owner destination)
          (emacsvox-aural-voice-editor--put :new nil)
          (emacsvox-aural-voice-editor--put :palette destination)))
      (emacsvox-aural-voice-editor-refresh)
      (emacsvox-aural-ui-speak (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))))
(defun emacsvox-aural-voice-editor-save () "Save and apply this named voice, or choose an experiment destination." (interactive) (emacsvox-aural-voice-editor--save t))
(defun emacsvox-aural-voice-editor-save-to-collection () "Save the named voice without selecting its palette." (interactive) (emacsvox-aural-voice-editor--save nil))

(defun emacsvox-aural-voice-editor--read-choice (snapshot prompt &optional preferred)
  "Read a stable row from SNAPSHOT with PROMPT and optional PREFERRED ID."
  (let ((choices (cl-loop for row in (emacsvox-aural-voice-editing--rows snapshot) for index from 1
                          collect (cons (format "%d. %s" index (emacsvox-aural-voice-workbench--selector-description
                                                                (plist-get row :selector)))
                                        (plist-get row :id)))))
    (unless choices (user-error "This voice has no explicit fallback choice; keep a physical voice first"))
    (cdr (assoc (completing-read prompt choices nil t nil nil
                                 (or (car (rassoc preferred choices)) (caar choices))) choices))))

(defun emacsvox-aural-voice-editor-keep-experiment ()
  "Choose the experiment's destination row and scope, retaining other draft edits."
  (interactive)
  (let* ((experiment (emacsvox-aural-voice-editor--working))
         (origin emacsvox-aural-voice-editor--context)
         (origin-buffer (current-buffer))
         (origin-draft (plist-get origin :draft))
         (origin-revision (emacsvox-aural-voice-draft-revision origin-draft))
         (palette (intern (completing-read "Destination palette: "
                                           (hash-table-keys emacsvox-aural-voice-palette-registry) nil t nil nil
                                           (symbol-name (emacsvox-aural-effective-voice-palette)))))
         (voice (emacsvox-aural-voice-palettes--read-voice palette "Use for named voice: "))
         (context (emacsvox-aural-voice-editor--context-for palette voice))
         (draft (plist-get context :draft))
         (revision (emacsvox-aural-voice-draft-revision draft))
         (destination (copy-tree (emacsvox-aural-voice-draft-working draft)))
         (options '(("Physical voice and adjustments — this choice" . both)
                    ("Physical voice only" . physical)
                    ("Adjustments only — selected choice" . adjustments)
                    ("Shared adjustments only — all inheriting choices" . shared)
                    ("Physical voice and shared adjustments — all inheriting choices" . shared-both)))
         (part (cdr (assoc (completing-read "Keep from experiment: " options nil t nil nil (caar options)) options)))
         (placement (if (memq part '(adjustments shared)) 'replace
                      (cdr (assoc (completing-read "Place physical voice: "
                                                   '("Replace selected choice" "Add as preferred" "Add as fallback") nil t nil nil
                                                   (if (plist-get destination :selectors) "Replace selected choice" "Add as preferred"))
                                  '(("Replace selected choice" . replace) ("Add as preferred" . preferred) ("Add as fallback" . fallback))))))
         (id (when (and (not (eq part 'shared)) (eq placement 'replace))
               (emacsvox-aural-voice-editor--read-choice destination "Destination fallback: " (plist-get context :tuning-choice))))
         (rows (emacsvox-aural-voice-editing--rows destination))
         (index (and id (cl-position id rows :test #'equal :key (lambda (row) (plist-get row :id)))))
         (replacement (when (and (memq part '(physical shared-both)) (eq placement 'replace))
                        (emacsvox-aural-voice-editor--replacement (nth index rows))))
         (proposed (if (memq part '(both adjustments))
                       (emacsvox-aural-voice-editing--keep-for-choice destination experiment part placement id)
                     (emacsvox-aural-voice-editing--keep destination experiment
                                                       (pcase part ('shared 'adjustments) ('shared-both 'both) (_ part))
                                                       placement index replacement)))
         (merge (or (not (emacsvox-aural-voice-drafts--dirty-fields draft))
                    (equal (completing-read "Destination has a draft: "
                                           '("Add chosen changes to this draft" "Resume draft without adding") nil t nil nil
                                           "Add chosen changes to this draft")
                           "Add chosen changes to this draft"))))
    (unless (and (buffer-live-p origin-buffer)
                 (with-current-buffer origin-buffer (eq origin emacsvox-aural-voice-editor--context))
                 (= origin-revision (emacsvox-aural-voice-draft-revision origin-draft))
                 (= revision (emacsvox-aural-voice-draft-revision draft)))
      (user-error "Experiment or destination changed while choosing; start the keep action again"))
    (unless merge
      (emacsvox-aural-voice-editor--show context origin-buffer)
      (user-error "Resumed destination draft; experiment retained"))
    (emacsvox-aural-voice-drafts--edit draft proposed)
    (emacsvox-aural-voice-editor--context-put context :experiment origin)
    (emacsvox-aural-voice-editor--context-put context :tuning-choice nil)
    (emacsvox-aural-voice-editor--show context origin-buffer)
    (emacsvox-aural-ui-speak
     (concat "Destination draft ready. "
             (pcase part
               ((or 'both 'adjustments) "The chosen row now uses the experiment's adjustments and adapter defaults; shared settings and other rows are retained. ")
               ((or 'shared 'shared-both) "Shared settings changed; customized row values still override them. ")
               (_ "Physical choice changed; the destination's adjustments determine its sound. "))
             "Play edited previews the proposed combination. Save and apply to keep it."))))

(defun emacsvox-aural-voice-editor-details ()
  "Show ownership, saved/requested values and actual playback evidence."
  (interactive)
  (let ((context emacsvox-aural-voice-editor--context))
    (with-help-window "*Voice editor details*"
      (princ (emacsvox-aural-voice-editor--explain-playback (plist-get context :preview-result)))
      (princ "\nStored definitions and diagnostic data\n")
      (princ (format "Base voice in %s; definition owner %s.\nShared settings are the base; each row can override individual fields.\nSelection after Save and apply lasts for this session. Use a Presentation Profile to retain it after restart.\n\nWorking voice: %S\n\nWorkstation policy: %S\n\nTemporary override: %S\n\nLast playback evidence: %S\n"
                     (plist-get context :palette) (plist-get context :owner)
                     (emacsvox-aural-voice-draft-working (plist-get context :draft))
                     (plist-get context :policy) (plist-get context :temporary) (plist-get context :preview-result))))))

(defun emacsvox-aural-voice-editor--field-value (dimension value)
  "Describe requested DIMENSION VALUE in displayed units, retaining zero."
  (if (null value) "adapter default"
    (let ((number (emacsvox-aural-voice-tuner--control-value dimension value))
          (description (emacsvox-aural-voice-tuner--value-description dimension value)))
      (if (equal (format "%s" number) description) description
        (format "%s (%s)" number description)))))

(defun emacsvox-aural-voice-editor--explain-playback (result)
  "Explain RESULT's last confirmed sample using only its captured raw request."
  (let* ((sample (and (eq (plist-get result :preview-kind) 'layered)
                      (cl-find-if
                       (lambda (item) (and (eq (plist-get (plist-get item :request-snapshot) :role) 'sample)
                                          (plist-get item :last-started)))
                       (reverse (plist-get result :results)))))
         (entry (plist-get sample :request-snapshot))
         (identity (plist-get sample :last-started))
         (id (plist-get identity :choice_id))
         (unsupported (append (plist-get identity :degraded_acss) (plist-get identity :degraded_effects) nil)))
    (concat "Where the last sample's settings came from\n"
            (if result (concat (emacsvox-aural-voice-editor--preview-status result) "\n") "No preview result.\n")
            (if (not sample)
                "No confirmed sample row is available for field-source details.\n"
              (concat
               (format "%s sample, using the settings captured for that request.\n"
                       (capitalize (symbol-name (or (plist-get entry :variant) 'edited))))
               "Shared settings, then the actual fallback row, then context; later explicit fields replace earlier ones.\n"
               "These values describe composed requests, not measured native or acoustic values.\n"
               (mapconcat
                (lambda (field)
                  (let* ((key (plist-get field :dimension))
                         (dimension (intern (substring (symbol-name key) 1)))
                         (value (lambda (item) (emacsvox-aural-voice-editor--field-value dimension item))))
                    (format "%s: %s; source %s. Shared: %s; row: %s; context: %s.%s"
                            (emacsvox-aural-voice-tuner--dimension-label dimension)
                            (funcall value (plist-get field :value)) (plist-get field :source)
                            (funcall value (plist-get field :shared))
                            (pcase (plist-get field :choice-state)
                              ('inherit (if (eq id :null) "policy fallback, no row patch" "use shared value"))
                              ('default "explicit adapter default") (_ (funcall value (plist-get field :choice))))
                            (pcase (plist-get field :context-state)
                              ('inherit "no override") ('legacy-nil "explicit nil, retains underlying value")
                              ('default "explicit adapter default") (_ (funcall value (plist-get field :context))))
                            (if (member (replace-regexp-in-string "-" "_" (symbol-name dimension)) unsupported)
                                " Unsupported by the engine that started this sample." ""))))
                (emacsvox-aural-voice-editing--field-sources entry (unless (eq id :null) id)) "\n")
               "\n")))))

(defun emacsvox-aural-voice-editor--leave-choice ()
  "Resolve unsaved work before hiding or killing this editor."
  (if (not (emacsvox-aural-voice-drafts--dirty-fields (emacsvox-aural-voice-editor--draft))) t
    (pcase (completing-read "Unsaved voice changes: " '("Keep draft and return" "Discard changes and return" "Continue editing") nil t nil nil "Keep draft and return")
      ("Continue editing" nil)
      ("Discard changes and return"
       (let ((draft (emacsvox-aural-voice-editor--draft)))
         (emacsvox-aural-voice-drafts--discard draft)
         (when (and (emacsvox-aural-voice-editor--get :new)
                    (null (emacsvox-aural-voice-draft-proposal draft)))
           (remhash (emacsvox-aural-voice-draft-key draft) emacsvox-aural-voice-drafts--registry)
           (remhash (emacsvox-aural-voice-draft-key draft) emacsvox-aural-voice-editor--contexts)
           (emacsvox-aural-voice-editor--put :discarded t)))
       t)
      (_ t))))
(defun emacsvox-aural-voice-editor-leave ()
  "Return to the originating field while retaining this session's draft."
  (interactive)
  (when (emacsvox-aural-voice-editor--leave-choice)
    (emacsvox-aural-voice-editor-stop)
    (let ((origin (emacsvox-aural-voice-editor--get :origin))
          (row (emacsvox-aural-voice-editor--get :origin-row))
          (column (emacsvox-aural-voice-editor--get :origin-column)))
      ;; Selecting the origin alone leaves this editor in the window history,
      ;; so quitting the workbench can immediately reveal it again.
      (quit-window (emacsvox-aural-voice-editor--get :discarded))
      (if (and (markerp origin) (marker-buffer origin))
          (progn (pop-to-buffer (marker-buffer origin))
                 (if (and row (derived-mode-p 'tabulated-list-mode))
                     (progn (emacsvox-aural-ui-goto-row row) (move-to-column (or column 0)))
                   (goto-char origin)))))))

(defvar emacsvox-aural-voice-editor-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-interface-mode-map)
    (dolist (key '("n" "<down>" "TAB")) (define-key map (kbd key) #'emacsvox-aural-voice-editor-next))
    (dolist (key '("p" "<up>" "<backtab>")) (define-key map (kbd key) #'emacsvox-aural-voice-editor-previous))
    ;; Button-local Tab bindings otherwise take precedence over this map.
    (define-key map [remap forward-button] #'emacsvox-aural-voice-editor-next)
    (define-key map [remap backward-button] #'emacsvox-aural-voice-editor-previous)
    (define-key map [remap push-button] #'emacsvox-aural-voice-editor-activate)
    (dolist (pair '(("SPC" . emacsvox-aural-voice-editor-speak) ("<right>" . emacsvox-aural-voice-editor-increase)
                    ("<left>" . emacsvox-aural-voice-editor-decrease) ("P" . emacsvox-aural-voice-editor-play)
                    ("B" . emacsvox-aural-voice-editor-compare) ("S" . emacsvox-aural-voice-editor-stop)
                    ("T" . emacsvox-aural-voice-editor-text) ("u" . emacsvox-aural-voice-editor-undo)
                    ("d" . emacsvox-aural-voice-editor-default)
                    ("i" . emacsvox-aural-voice-editor--inherit)
                    ("w" . emacsvox-aural-voice-editor-save) ("C-c C-c" . emacsvox-aural-voice-editor-save)
                    ("h" . emacsvox-aural-home)
                    ("q" . emacsvox-aural-voice-editor-leave) ("?" . describe-mode)))
      (define-key map (kbd (car pair)) (cdr pair))) map))
(define-derived-mode emacsvox-aural-voice-editor-mode emacsvox-aural-interface-mode "Voice-Editor"
  "Edit shared named-voice adjustments and ordered physical choices."
  (setq-local emacsvox-aural-ui-extra-actions
              '(("Play edited base voice" . emacsvox-aural-voice-editor-play)
                ("Compare original and edited" . emacsvox-aural-voice-editor-compare)
                ("Save and apply" . emacsvox-aural-voice-editor-save)
                ("Save to collection" . emacsvox-aural-voice-editor-save-to-collection)
                ("Leave and retain draft" . emacsvox-aural-voice-editor-leave)))
  (add-hook 'kill-buffer-query-functions #'emacsvox-aural-voice-editor--leave-choice nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-aural-voice-editor-stop nil t))

(defun emacsvox-aural-voice-editor--show (context source)
  "Show retained CONTEXT, recording a return position in SOURCE."
  ;; Keep context identity stable for the registry and asynchronous callbacks.
  (emacsvox-aural-voice-editor--invalidate context)
  (dolist (key '(:origin-row :origin-column :announced-apply :seen-revision))
    (unless (plist-member context key) (nconc context (list key nil))))
  (let ((ordinary (and (buffer-live-p source) (emacsvox-aural-inspection-remember-source-buffer source)))
        (buffer (or (and (buffer-live-p (plist-get context :buffer)) (plist-get context :buffer))
                    (generate-new-buffer (format "*Voice editor: %s*" (or (plist-get context :voice) "experiment"))))))
    (when (and (buffer-live-p source) (not (eq source buffer)))
      (with-current-buffer source
        (setf (plist-get context :origin) (copy-marker (point))
              (plist-get context :origin-row) (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id))
              (plist-get context :origin-column) (current-column))))
    (setf (plist-get context :buffer) buffer)
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-editor-mode) (emacsvox-aural-voice-editor-mode))
      (setq emacsvox-aural-voice-editor--context context)
      (emacsvox-aural-inspection-attach-source ordinary)
      (emacsvox-aural-voice-editor-refresh))
    (emacsvox-aural-ui--pop-to-buffer buffer #'emacsvox-aural-voice-editor-speak)
    buffer))

(defun emacsvox-aural-voice-editor-open (palette voice &optional source text)
  "Open or resume PALETTE's named VOICE, returning to SOURCE with sample TEXT."
  (let ((context (emacsvox-aural-voice-editor--context-for palette voice)))
    (when text (setf (plist-get context :text) text))
    (emacsvox-aural-voice-editor--show context (or source (current-buffer)))))

(defun emacsvox-aural-voice-editor-new (palette voice &optional source text)
  "Draft a new neutral VOICE in PALETTE, returning to SOURCE with sample TEXT.
Opening the editor writes nothing.  Saving from the standard palette creates
a personal child containing the new voice."
  (let ((context (emacsvox-aural-voice-editor--context-for palette voice t)))
    (when text (setf (plist-get context :text) text))
    (emacsvox-aural-voice-editor--show context (or source (current-buffer)))))

(defun emacsvox-aural-voice-editor--copy (palette voice name source text)
  "Open an independent NAME draft from PALETTE's VOICE, returning to SOURCE.
Use TEXT for previews.  Saving from a built-in palette creates a personal child."
  (let* ((opened (emacsvox-aural-voice-editing--snapshot palette voice nil))
         (key (list 'base palette name)))
    (when (plist-get opened :diagnostics)
      (user-error "Cannot copy %s: its saved local voice choices are missing" voice))
    (when (gethash key emacsvox-aural-voice-editor--contexts)
      (user-error "A draft named %s already exists; save or discard it first" name))
    (let* ((context (emacsvox-aural-voice-editor--context-for palette name t))
           (snapshot (emacsvox-aural-voice-editing--freeze (plist-get opened :snapshot) palette)))
      (emacsvox-aural-voice-drafts--edit (plist-get context :draft) snapshot)
      (when text (setf (plist-get context :text) text))
      (emacsvox-aural-voice-editor--show context source))))

(defun emacsvox-aural-voice-editor-experiment (pair source text)
  "Open an exact physical PAIR experiment with adapter defaults and sample TEXT."
  (let* ((selector (list :kind 'exact :scope 'local :engine-id (plist-get (car pair) :engine-id)
                         :voice-id (plist-get (cadr pair) :voice-id)))
         (key (list 'experiment selector))
         (context (or (gethash key emacsvox-aural-voice-editor--contexts)
                      (list :draft (emacsvox-aural-voice-drafts--open
                                    key (emacsvox-aural-voice-editing--freeze
                                         (list :definition nil :selectors (list selector) :language (plist-get (cadr pair) :language)) nil))
                            :palette nil :voice nil :experiment t :policy (emacsvox-aural-voice-editor--policy)
                            :text text :expanded nil :effects nil :automatic-sample t :preview-generation 0
                            :preview-result nil :origin nil :buffer nil))))
    (puthash key context emacsvox-aural-voice-editor--contexts)
    (emacsvox-aural-voice-editor--show context source)))

(defun emacsvox-aural-voice-editor--draft-changed (draft)
  "Refresh DRAFT views and announce completed applies without moving focus."
  (maphash (lambda (_ context)
             (when (eq draft (plist-get context :draft))
               (unless (equal (plist-get context :seen-revision) (emacsvox-aural-voice-draft-revision draft))
                 (emacsvox-aural-voice-editor--invalidate context)
                 (unless (plist-member context :seen-revision) (nconc context (list :seen-revision nil)))
                 (setf (plist-get context :seen-revision) (emacsvox-aural-voice-draft-revision draft)))
               (when (buffer-live-p (plist-get context :buffer))
                 (with-current-buffer (plist-get context :buffer) (emacsvox-aural-voice-editor-refresh)))
               (when-let* ((proposal (emacsvox-aural-voice-draft-proposal draft))
                           (operation (emacsvox-aural-voice-save-operation proposal)))
                 (let ((key (cons operation (emacsvox-aural-voice-save-state proposal))))
                   (when (and (memq (cdr key) '(applied apply-failed superseded))
                              (not (equal key (plist-get context :announced-apply))))
                     (setf (plist-get context :announced-apply) key)
                     (tts-notify (format "%s: %s" (plist-get context :voice)
                                         (plist-get (emacsvox-aural-voice-drafts--status draft) :label))))))))
           emacsvox-aural-voice-editor--contexts)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (cond ((derived-mode-p 'emacsvox-aural-voice-palette-previews-mode)
             (emacsvox-aural-voice-palette-previews-refresh))
            ((and (derived-mode-p 'emacsvox-aural-voice-context-mode)
                  (eq draft (plist-get emacsvox-aural-voice-context--base :draft)))
             (emacsvox-aural-voice-context-stop))
            ((derived-mode-p 'emacsvox-aural-voice-workbench-mode)
             (emacsvox-aural-voice-workbench-refresh))))))
(add-hook 'emacsvox-aural-voice-drafts--changed-hook #'emacsvox-aural-voice-editor--draft-changed)

(defun emacsvox-aural-voice-editor--pending ()
  "Return retained voice contexts needing editing or save/apply recovery."
  (let (contexts)
    (maphash (lambda (_ context)
               (let* ((draft (plist-get context :draft))
                      (proposal (emacsvox-aural-voice-draft-proposal draft)))
                 (when (or (emacsvox-aural-voice-drafts--dirty-fields draft)
                           (and proposal (memq (emacsvox-aural-voice-save-state proposal)
                                               '(partial failed applying apply-failed superseded))))
                   (push context contexts)))) emacsvox-aural-voice-editor--contexts)
    (nreverse contexts)))

(defun emacsvox-aural-voice-editor--status-for (palette voice)
  "Return a shared draft state label for PALETTE VOICE, or nil."
  (let* ((name (or (plist-get (emacsvox-aural-voice-runtime--resolve voice palette) :name) voice))
         (context (gethash (list 'base palette name) emacsvox-aural-voice-editor--contexts)))
    (when context
      (plist-get (emacsvox-aural-voice-drafts--status (plist-get context :draft)) :label))))

(provide 'emacsvox-aural-voice-editor)
;;; emacsvox-aural-voice-editor.el ends here
