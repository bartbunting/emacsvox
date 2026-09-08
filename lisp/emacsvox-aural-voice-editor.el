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
;; session drafts and the acknowledged save coordinator.  Shared tuning is
;; explicit; individual fallback adjustments are intentionally not advertised.

;;; Code:

(require 'button)
(require 'emacsvox-aural-voice-editing)
(require 'emacsvox-aural-voice-workbench)
(autoload 'emacsvox-aural-voice-context-open "emacsvox-aural-voice-context"
  "Inspect this voice draft in a captured source context." t)

(defvar emacsvox-aural-voice-editor--contexts (make-hash-table :test #'equal)
  "Retained editor context for each authoritative draft.")
(defvar emacsvox-aural-voice-editor--preview-owner nil
  "Context owning the current editor sample.")
(defvar-local emacsvox-aural-voice-editor--context nil)

(defun emacsvox-aural-voice-editor--get (key)
  "Read KEY from the current editor context."
  (plist-get emacsvox-aural-voice-editor--context key))
(defun emacsvox-aural-voice-editor--put (key value)
  "Store KEY with VALUE in the retained current context."
  (unless (plist-member emacsvox-aural-voice-editor--context key)
    (nconc emacsvox-aural-voice-editor--context (list key nil)))
  (setf (plist-get emacsvox-aural-voice-editor--context key) value))
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

(defun emacsvox-aural-voice-editor--context-for (palette voice)
  "Resume or capture a named PALETTE VOICE context without activation."
  (let* ((profile (emacsvox-aural-routing-profile emacsvox-aural-active-routing-profile))
         (routing (and profile (copy-tree (emacsvox-aural-routing-profile-entry-data profile))))
         (opened (emacsvox-aural-voice-editing--snapshot palette voice routing))
         (name (plist-get opened :name))
         (key (list 'base palette name)))
    (or (gethash key emacsvox-aural-voice-editor--contexts)
        (let ((context
               (list :draft (emacsvox-aural-voice-drafts--open key (emacsvox-aural-voice-editing--freeze (plist-get opened :snapshot) palette) (list palette))
                     :palette palette :voice name :routing routing :policy (emacsvox-aural-voice-editor--policy)
                     :destination palette :summary nil :owner (plist-get opened :owner)
                     :diagnostics (plist-get opened :diagnostics) :experiment nil
                     :inventory (tts-voice-inventory)
                     :temporary (plist-get (emacsvox-aural-voice-runtime--resolve name palette) :session)
                     :text emacsvox-aural-voice-workbench-preview-text :expanded nil :effects nil
                     :automatic-sample t :preview-generation 0 :preview-result nil :origin nil :buffer nil)))
          (puthash key context emacsvox-aural-voice-editor--contexts)
          context))))

(defun emacsvox-aural-voice-editor--button (id text command &optional dimension)
  "Insert a spoken field ID labelled TEXT invoking COMMAND, with DIMENSION."
  (insert "  ")
  (insert-text-button text 'follow-link t 'voice-field id 'voice-dimension dimension
                      'action (lambda (_) (funcall command)))
  (insert "\n"))

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
         (baseline (emacsvox-aural-voice-editing--style
                    (emacsvox-aural-voice-draft-baseline (emacsvox-aural-voice-editor--draft))
                    (emacsvox-aural-voice-editor--get :palette)))
         (engine (cl-find (plist-get (car chain) :engine-id)
                          (plist-get (emacsvox-aural-voice-editor--get :inventory) :engines)
                          :key (lambda (entry) (plist-get entry :engine-id)) :test #'equal))
         (emacsvox-aural-voice-tuner-route-engine engine)
         (emacsvox-aural-voice-tuner-route-selector (car chain)))
    (concat (emacsvox-aural-voice-tuner--dimension-label dimension) ": "
            (emacsvox-aural-voice-tuner--value-description dimension value)
            (unless (equal value (plist-get baseline key))
              (format " [changed; was %s]" (emacsvox-aural-voice-tuner--value-description dimension (plist-get baseline key))))
            (cond ((eq dimension 'family) " [portable fallback; not part of full preview]")
                  ((and engine (not (emacsvox-aural-voice-tuner--supported-p dimension)))
                   " [unsupported by the preferred engine; value retained]")
                  ((and chain (not engine)) " [engine support not known]")))))

(defun emacsvox-aural-voice-editor--preview-status (result)
  "Describe actual accepted audio evidence in terminal RESULT."
  (let* ((played (delete-dups (apply #'append (mapcar (lambda (entry) (copy-tree (plist-get entry :realizations)))
                                                      (plist-get result :results)))))
         (last (car (last (plist-get result :results))))
         (degraded (append (plist-get last :degraded-acss) (plist-get last :degraded-effects))))
    (format "Preview %s%s%s%s" (or (plist-get result :status) "not played")
            (if played (format "; audio from %s" (mapconcat (lambda (voice)
                                                              (format "%s/%s" (plist-get voice :engine-id) (plist-get voice :voice-id))) played ", ")) "")
            (if degraded (format "; unsupported adjustments: %s" degraded) "")
            (if (or (plist-get result :message) (plist-get last :message))
                (format "; %s" (or (plist-get result :message) (plist-get last :message))) ""))))

(defun emacsvox-aural-voice-editor-refresh ()
  "Refresh the common editor, preserving the current field and point's column."
  (interactive)
  (let* ((field (get-text-property (point) 'voice-field)) (column (current-column))
         (draft (emacsvox-aural-voice-editor--draft))
         (snapshot (emacsvox-aural-voice-editor--working))
         (palette (emacsvox-aural-voice-editor--get :palette))
         (voice (emacsvox-aural-voice-editor--get :voice))
         (style (emacsvox-aural-voice-editing--style snapshot palette))
         (chain (plist-get snapshot :selectors))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (format "Edit %s — %s\n%s\n\n"
                    (or voice "physical voice experiment") (or palette "no destination yet")
                    (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))
    (insert (if voice "Adjustments apply to every fallback choice in this named voice.\n"
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
                                           (format "Fallbacks: %s — %s" (if (cdr chain) (format "%d explicit" (length (cdr chain))) "Automatic")
                                                   (if (emacsvox-aural-voice-editor--get :expanded) "collapse" "expand"))
                                           (lambda () (emacsvox-aural-voice-editor--put :expanded (not (emacsvox-aural-voice-editor--get :expanded)))
                                             (emacsvox-aural-voice-editor-refresh)))
      (when (emacsvox-aural-voice-editor--get :expanded)
        (cl-loop for choice in chain for index from 0 do
                 (let ((selected index))
                   (emacsvox-aural-voice-editor--button (cons 'choice index)
                                                        (format "%d. %s — shared adjustments" (1+ index)
                                                                (emacsvox-aural-voice-workbench--selector-description choice))
                                                        (lambda () (emacsvox-aural-voice-editor-choice-actions selected)))))
        (emacsvox-aural-voice-editor--button 'add "Add fallback" (lambda () (emacsvox-aural-voice-editor-choose nil)))
        (emacsvox-aural-voice-editor--button 'automatic "Use Automatic; clear explicit choices" #'emacsvox-aural-voice-editor-automatic)
        (insert (format "  After explicit choices: workstation engine order %s; fallback engines %s.\n"
                        (plist-get (emacsvox-aural-voice-editor--get :policy) :engine-order)
                        (plist-get (plist-get (emacsvox-aural-voice-editor--get :policy) :fallback) :engines))))
      )
    (insert "\nShared adjustments\n")
    (dolist (dimension (append '(rate-offset average-pitch pitch-range stress richness)
                               (when (emacsvox-aural-voice-editor--get :effects)
                                 '(family gain low-pass high-pass pan reverb echo chorus))))
      (let ((field dimension))
        (emacsvox-aural-voice-editor--button dimension
                                             (emacsvox-aural-voice-editor--adjustment-text dimension style chain)
                                             (lambda () (emacsvox-aural-voice-editor-edit field)) dimension)))
    (emacsvox-aural-voice-editor--button 'more "More adjustments and effects…"
                                         (lambda () (emacsvox-aural-voice-editor--put :effects (not (emacsvox-aural-voice-editor--get :effects)))
                                           (emacsvox-aural-voice-editor-refresh)))
    (insert "\nListen — base voice, without contextual rules\n")
    (emacsvox-aural-voice-editor--button 'play "Play edited" #'emacsvox-aural-voice-editor-play)
    (emacsvox-aural-voice-editor--button 'compare "Compare original and edited" #'emacsvox-aural-voice-editor-compare)
    (emacsvox-aural-voice-editor--button 'stop "Stop sample" #'emacsvox-aural-voice-editor-stop)
    (emacsvox-aural-voice-editor--button 'text (format "Sample text: %s" (emacsvox-aural-voice-editor--get :text))
                                         #'emacsvox-aural-voice-editor-text)
    (emacsvox-aural-voice-editor--button 'auto-sample
                                         (format "Automatic sample after adjustment: %s" (if (emacsvox-aural-voice-editor--get :automatic-sample) "on" "off"))
                                         (lambda () (emacsvox-aural-voice-editor--put :automatic-sample (not (emacsvox-aural-voice-editor--get :automatic-sample)))
                                           (emacsvox-aural-voice-editor-refresh)
                                           (emacsvox-aural-voice-editor-speak)))
    (when (emacsvox-aural-voice-editor--get :preview-result)
      (emacsvox-aural-voice-editor--button 'preview-status
                                           (emacsvox-aural-voice-editor--preview-status (emacsvox-aural-voice-editor--get :preview-result))
                                           #'emacsvox-aural-voice-editor-speak))
    (insert "\nChanges and recovery\n")
    (insert (format "  Changes: %s\n"
                    (or (mapconcat (lambda (field) (pcase field
                                                     (:definition "shared adjustments") (:selectors "physical choices")
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
  (when (eq emacsvox-aural-voice-editor--preview-owner emacsvox-aural-voice-editor--context)
    (setq emacsvox-aural-voice-editor--preview-owner nil)
    (tts-stop)))
(defun emacsvox-aural-voice-editor-speak ()
  "Read the current labelled field using the ordinary navigation voice."
  (interactive)
  (emacsvox-aural-voice-editor-stop)
  (emacsvox-aural-ui-speak (if-let* ((button (button-at (point)))) (button-label button)
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
        (condition-case err (emacsvox-aural-voice-editor--preview nil nil value-label)
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
  (emacsvox-aural-voice-editor--changed
   (emacsvox-aural-voice-editing--adjust
    (emacsvox-aural-voice-editor--working) (emacsvox-aural-voice-editor--get :palette) dimension
    (emacsvox-aural-voice-tuner--stored-value dimension displayed))
   (if displayed (format "%s" displayed) "Adapter default")))
(defun emacsvox-aural-voice-editor-edit (&optional dimension)
  "Edit DIMENSION or the current numeric field; blank means adapter default."
  (interactive)
  (let* ((dimension (or dimension (get-text-property (point) 'voice-dimension)
                        (user-error "Choose an adjustment field")))
         (input (read-string (format "%s (blank for adapter default): " dimension)))
         (value (unless (string-empty-p input)
                  (if (eq dimension 'family) (intern input)
                    (unless (string-match-p "\\`[+-]?[0-9]+\\'" input) (user-error "Enter a whole number"))
                    (string-to-number input)))))
    (emacsvox-aural-voice-editor--set dimension value)))
(defun emacsvox-aural-voice-editor-adjust (delta)
  "Adjust the current field by DELTA in displayed units."
  (let* ((dimension (or (get-text-property (point) 'voice-dimension) (user-error "Choose a numeric adjustment")))
         (style (emacsvox-aural-voice-editing--style (emacsvox-aural-voice-editor--working)
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
(defun emacsvox-aural-voice-editor-increase () "Increase the current displayed adjustment." (interactive) (emacsvox-aural-voice-editor-adjust 1))
(defun emacsvox-aural-voice-editor-decrease () "Decrease the current displayed adjustment." (interactive) (emacsvox-aural-voice-editor-adjust -1))

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
                       (entry (emacsvox-aural-voice-editing--preview
                               snapshot (emacsvox-aural-voice-editor--get :palette)
                               (emacsvox-aural-voice-editor--get :policy) (emacsvox-aural-voice-editor--get :text))))
                  (setq entry (map-delete (map-delete (map-delete entry :selectors) :fallback-policy) :disabled-engine-ids))
                  (setq emacsvox-aural-voice-editor--preview-owner emacsvox-aural-voice-editor--context)
                  (tts-preview-voices
                   (list (plist-put entry :selector selector))
                   (lambda (result)
                     (when (memq (plist-get result :status) '(failed error unsupported))
                       (tts-notify (emacsvox-aural-voice-editor--preview-status result))))))))
            (pcase action
              ("Cancel" (user-error "Choice unchanged"))
              ("Use this voice" (setq selected selector)))))
      (emacsvox-aural-voice-editor-stop))
    selected))
(defun emacsvox-aural-voice-editor-choose (index)
  "Replace choice INDEX, or append a fallback when INDEX is nil."
  (let ((selector (emacsvox-aural-voice-editor--pick)))
    (emacsvox-aural-voice-editor--changed
     (emacsvox-aural-voice-editing--keep (emacsvox-aural-voice-editor--working)
                                         (list :selectors (list selector)) 'physical
                                         (if index 'replace 'fallback) index))))
(defun emacsvox-aural-voice-editor-automatic ()
  "Explicitly replace the saved choice chain with Automatic."
  (interactive)
  (let ((snapshot (emacsvox-aural-voice-editor--working)))
    (setq snapshot (plist-put snapshot :selectors nil))
    (emacsvox-aural-voice-editor--changed (plist-put snapshot :reset-choices t))))
(defun emacsvox-aural-voice-editor-choice-actions (index)
  "Edit, reorder, remove or individually audition choice INDEX."
  (let* ((action (completing-read "Choice action: " '("Replace" "Move earlier" "Move later" "Remove" "Audition this choice") nil t))
         (snapshot (emacsvox-aural-voice-editor--working))
         (chain (plist-get snapshot :selectors)))
    (pcase action
      ("Replace" (emacsvox-aural-voice-editor-choose index))
      ("Audition this choice" (emacsvox-aural-voice-editor--preview nil index))
      (_ (if (equal action "Remove") (setq chain (append (cl-subseq chain 0 index) (nthcdr (1+ index) chain)))
           (let ((target (+ index (if (equal action "Move earlier") -1 1))))
             (unless (< -1 target (length chain)) (user-error "Already at the boundary"))
             (cl-rotatef (nth index chain) (nth target chain))))
         (emacsvox-aural-voice-editor--changed (plist-put snapshot :selectors chain))))))

(defun emacsvox-aural-voice-editor--preview (compare &optional individual value-label)
  "Preview COMPARE or INDIVIDUAL voices, prefixing sample text with VALUE-LABEL."
  (let* ((context emacsvox-aural-voice-editor--context)
         (generation (1+ (emacsvox-aural-voice-editor--get :preview-generation)))
         (draft (emacsvox-aural-voice-editor--draft))
         (policy (emacsvox-aural-voice-editor--get :policy))
         (text (concat (when value-label (concat value-label ". "))
                       (emacsvox-aural-voice-editor--get :text)))
         (palette (emacsvox-aural-voice-editor--get :palette))
         (snapshots (append (when compare (list (emacsvox-aural-voice-draft-original draft)))
                            (list (emacsvox-aural-voice-draft-working draft)))) entries)
    (emacsvox-aural-voice-editor--put :preview-generation generation)
    (cl-loop for snapshot in snapshots for index from 0 do
             (let ((entry (emacsvox-aural-voice-editing--preview snapshot palette policy text)))
               (when (or individual (not (emacsvox-aural-voice-editor--get :voice)))
                 (setq entry (list :text text :selector (nth (or individual 0) (plist-get snapshot :selectors))
                                   :acss (plist-get entry :acss) :effects (plist-get entry :effects)
                                   :rate-offset (plist-get entry :rate-offset) :language (plist-get entry :language))))
               (setq entries (append entries
                                     (if compare
                                         (let ((label (if (= index 0) "Original" "Edited")))
                                           (list (plist-put (copy-tree entry) :text (concat label ".")) entry))
                                       (list entry))))))
    (setq emacsvox-aural-voice-editor--preview-owner context)
    (tts-preview-voices entries
                        (lambda (result)
                          (when (= generation (plist-get context :preview-generation))
                            (setf (plist-get context :preview-result) (copy-tree result))
                            (when (eq emacsvox-aural-voice-editor--preview-owner context)
                              (setq emacsvox-aural-voice-editor--preview-owner nil))
                            (when (buffer-live-p (plist-get context :buffer))
                              (with-current-buffer (plist-get context :buffer)
                                (emacsvox-aural-voice-editor-refresh)))
                            (when (memq (plist-get result :status) '(failed error unsupported))
                              (tts-notify (emacsvox-aural-voice-editor--preview-status result))))))))
(defun emacsvox-aural-voice-editor-play () "Play the edited base voice without saving." (interactive) (emacsvox-aural-voice-editor--preview nil))
(defun emacsvox-aural-voice-editor-compare () "Compare captured original and edited base voices." (interactive) (emacsvox-aural-voice-editor--preview t))
(defun emacsvox-aural-voice-editor-text ()
  "Change the common comparison text."
  (interactive)
  (let ((text (read-string "Sample text: " (emacsvox-aural-voice-editor--get :text))))
    (when (string-empty-p text) (user-error "Sample text must not be empty"))
    (emacsvox-aural-voice-editor--put :text text) (emacsvox-aural-voice-editor-refresh)))
(defun emacsvox-aural-voice-editor-undo ()
  "Undo the last draft change."
  (interactive) (emacsvox-aural-voice-drafts--undo (emacsvox-aural-voice-editor--draft))
  (emacsvox-aural-voice-editor-refresh) (emacsvox-aural-voice-editor-speak))

(defun emacsvox-aural-voice-editor--destination ()
  "Choose the first saved independent palette before preparing its proposal."
  (let* ((palette (emacsvox-aural-voice-editor--get :palette))
         (record (gethash palette emacsvox-aural-voice-palette-registry)))
    (if (and (emacsvox-aural-voice-runtime--owned-p palette)
             (not (emacsvox-aural-voice-palette-built-in record))) palette
      (or (let ((chosen (emacsvox-aural-voice-editor--get :destination)))
            (and (not (eq chosen palette)) chosen))
          (let* ((name (read-string "New independent personal palette: " (format "%s-personal" palette)))
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
                            (format "Personal voices copied from %s" palette) (emacsvox-aural-voice-editor--get :routing))))
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
          (emacsvox-aural-voice-editor--put :palette destination)))
      (emacsvox-aural-voice-editor-refresh)
      (emacsvox-aural-ui-speak (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))))
(defun emacsvox-aural-voice-editor-save () "Save and apply this named voice, or choose an experiment destination." (interactive) (emacsvox-aural-voice-editor--save t))
(defun emacsvox-aural-voice-editor-save-to-collection () "Save the named voice without selecting its palette." (interactive) (emacsvox-aural-voice-editor--save nil))

(defun emacsvox-aural-voice-editor-keep-experiment ()
  "Choose what the experiment contributes, preserving destination fallback choices."
  (interactive)
  (let* ((experiment (emacsvox-aural-voice-editor--working))
         (origin emacsvox-aural-voice-editor--context)
         (palette (intern (completing-read "Destination palette: "
                                           (hash-table-keys emacsvox-aural-voice-palette-registry) nil t nil nil
                                           (symbol-name (emacsvox-aural-effective-voice-palette)))))
         (voice (emacsvox-aural-voice-palettes--read-voice palette "Use for named voice: "))
         (context (emacsvox-aural-voice-editor--context-for palette voice))
         (draft (plist-get context :draft))
         (part (cdr (assoc (completing-read "Keep from experiment: "
                                            '("Physical voice only" "Shared adjustments only — all fallback choices" "Both — shared adjustments for all fallback choices") nil t)
                           '(("Physical voice only" . physical)
                             ("Shared adjustments only — all fallback choices" . adjustments)
                             ("Both — shared adjustments for all fallback choices" . both)))))
         (placement (if (eq part 'adjustments) 'replace
                      (cdr (assoc (completing-read "Place physical voice: " '("Replace first choice" "Add as preferred" "Add as fallback") nil t)
                                  '(("Replace first choice" . replace) ("Add as preferred" . preferred) ("Add as fallback" . fallback)))))))
    (when (emacsvox-aural-voice-drafts--dirty-fields draft)
      (unless (equal (completing-read "Destination has a draft: " '("Resume its changes" "Replace its unsaved changes with this experiment") nil t)
                     "Replace its unsaved changes with this experiment")
        (emacsvox-aural-voice-editor--show context (current-buffer))
        (user-error "Resumed destination draft; experiment retained")))
    (emacsvox-aural-voice-drafts--edit draft
                                       (emacsvox-aural-voice-editing--keep (emacsvox-aural-voice-draft-baseline draft) experiment part placement))
    (setf (plist-get context :experiment) origin)
    (emacsvox-aural-voice-editor--show context (current-buffer))
    (emacsvox-aural-ui-speak "Destination proposal ready. Preview now plays the proposed saved combination. Save and apply to keep it.")))

(defun emacsvox-aural-voice-editor-details ()
  "Show ownership, saved/requested values and actual playback evidence."
  (interactive)
  (let ((context emacsvox-aural-voice-editor--context))
    (with-help-window "*Voice editor details*"
      (princ (format "Base voice in %s; definition owner %s.\nAdjustments are shared by all fallback choices.\nSelection after Save and apply lasts for this session. Use a Presentation Profile to retain it after restart.\n\nWorking voice: %S\n\nWorkstation policy: %S\n\nTemporary override: %S\n\nLast playback evidence: %S\n"
                     (plist-get context :palette) (plist-get context :owner)
                     (emacsvox-aural-voice-draft-working (plist-get context :draft))
                     (plist-get context :policy) (plist-get context :temporary) (plist-get context :preview-result))))))

(defun emacsvox-aural-voice-editor--leave-choice ()
  "Resolve unsaved work before hiding or killing this editor."
  (if (not (emacsvox-aural-voice-drafts--dirty-fields (emacsvox-aural-voice-editor--draft))) t
    (pcase (completing-read "Unsaved voice changes: " '("Keep draft and return" "Discard changes and return" "Continue editing") nil t nil nil "Keep draft and return")
      ("Continue editing" nil)
      ("Discard changes and return" (emacsvox-aural-voice-drafts--discard (emacsvox-aural-voice-editor--draft)) t)
      (_ t))))
(defun emacsvox-aural-voice-editor-leave ()
  "Return to the originating field while retaining this session's draft."
  (interactive)
  (when (emacsvox-aural-voice-editor--leave-choice)
    (emacsvox-aural-voice-editor-stop)
    (let ((origin (emacsvox-aural-voice-editor--get :origin))
          (row (emacsvox-aural-voice-editor--get :origin-row))
          (column (emacsvox-aural-voice-editor--get :origin-column)))
      (if (and (markerp origin) (marker-buffer origin))
          (progn (pop-to-buffer (marker-buffer origin))
                 (if (and row (derived-mode-p 'tabulated-list-mode))
                     (progn (emacsvox-aural-ui-goto-row row) (move-to-column (or column 0)))
                   (goto-char origin)))
        (quit-window)))))

(defvar emacsvox-aural-voice-editor-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-interface-mode-map)
    (dolist (key '("n" "<down>" "TAB")) (define-key map (kbd key) #'emacsvox-aural-voice-editor-next))
    (dolist (key '("p" "<up>" "<backtab>")) (define-key map (kbd key) #'emacsvox-aural-voice-editor-previous))
    ;; Button-local Tab bindings otherwise take precedence over this map.
    (define-key map [remap forward-button] #'emacsvox-aural-voice-editor-next)
    (define-key map [remap backward-button] #'emacsvox-aural-voice-editor-previous)
    (dolist (pair '(("SPC" . emacsvox-aural-voice-editor-speak) ("<right>" . emacsvox-aural-voice-editor-increase)
                    ("<left>" . emacsvox-aural-voice-editor-decrease) ("P" . emacsvox-aural-voice-editor-play)
                    ("B" . emacsvox-aural-voice-editor-compare) ("S" . emacsvox-aural-voice-editor-stop)
                    ("T" . emacsvox-aural-voice-editor-text) ("u" . emacsvox-aural-voice-editor-undo)
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
  (dolist (key '(:origin-row :origin-column :announced-apply))
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
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-voice-editor-speak)
    buffer))

(defun emacsvox-aural-voice-editor-open (palette voice &optional source text)
  "Open or resume PALETTE's named VOICE, returning to SOURCE with sample TEXT."
  (let ((context (emacsvox-aural-voice-editor--context-for palette voice)))
    (when text (setf (plist-get context :text) text))
    (emacsvox-aural-voice-editor--show context (or source (current-buffer)))))
(defun emacsvox-aural-voice-editor-experiment (pair source text)
  "Open an exact physical PAIR experiment with adapter defaults and sample TEXT."
  (let* ((selector (list :kind 'exact :scope 'local :engine-id (plist-get (car pair) :engine-id)
                         :voice-id (plist-get (cadr pair) :voice-id)))
         (key (list 'experiment selector))
         (context (or (gethash key emacsvox-aural-voice-editor--contexts)
                      (list :draft (emacsvox-aural-voice-drafts--open key (list :definition nil :selectors (list selector) :language (plist-get (cadr pair) :language)))
                            :palette nil :voice nil :experiment t :policy (emacsvox-aural-voice-editor--policy)
                            :text text :expanded nil :effects nil :automatic-sample t :preview-generation 0
                            :preview-result nil :origin nil :buffer nil))))
    (puthash key context emacsvox-aural-voice-editor--contexts)
    (emacsvox-aural-voice-editor--show context source)))

(defun emacsvox-aural-voice-editor--draft-changed (draft)
  "Refresh DRAFT views and announce completed applies without moving focus."
  (maphash (lambda (_ context)
             (when (eq draft (plist-get context :draft))
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
