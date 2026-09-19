;;; emacsvox-aural-voice-engine-controls.el --- Engine-described voice controls -*- lexical-binding: t; -*-

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
;; A descriptor-driven view of the existing voice draft.  Discovery never
;; samples, edits are sparse and previews and saving retain their usual owners.
;;; Code:
(require 'emacsvox-aural-voice-editor)
(require 'omnivox-parameters)
(declare-function omnivox--native-tuning-supported-p "omnivox-voices" (process))

(defun emacsvox-aural-voice-engine-controls--state ()
  "Return the active engine-controls view state."
  (or (emacsvox-aural-voice-editor--get :engine-controls) (user-error "Open Engine controls first")))

(defun emacsvox-aural-voice-engine-controls--put (key value)
  "Store view KEY and VALUE without changing the draft."
  (emacsvox-aural-voice-editor--context-put (emacsvox-aural-voice-engine-controls--state) key value))

(defun emacsvox-aural-voice-engine-controls--row ()
  "Return the currently owned choice, or nil if it was removed."
  (cl-find (plist-get (emacsvox-aural-voice-engine-controls--state) :choice)
           (plist-get (emacsvox-aural-voice-draft-working (emacsvox-aural-voice-editor--draft)) :choices)
           :test #'equal :key (lambda (row) (plist-get row :id))))

(defun emacsvox-aural-voice-engine-controls--fresh-p ()
  "Whether the checked catalogue still belongs to this view and worker."
  (let* ((state (emacsvox-aural-voice-engine-controls--state))
         (process (plist-get state :process)))
    (and (eq (plist-get (plist-get state :result) :status) 'ready)
         (eq process tts-speaker-process) (processp process) (process-live-p process)
         (not (process-get process 'tts--speech-process-retiring))
         (equal (plist-get (plist-get state :result) :epoch) (omnivox-parameters--epoch process))
         (equal (plist-get state :selector) (plist-get (emacsvox-aural-voice-engine-controls--row) :selector)))))

(defun emacsvox-aural-voice-engine-controls--editable-p (descriptor)
  "Whether DESCRIPTOR is currently qualified for edits to the selected choice."
  (let* ((state (emacsvox-aural-voice-engine-controls--state))
         (native (plist-get (emacsvox-aural-voice-engine-controls--row) :native)))
    (and (emacsvox-aural-voice-engine-controls--fresh-p)
         (omnivox--native-tuning-supported-p (plist-get state :process))
         (omnivox-parameters--editable-p descriptor)
         (or (not native)
             (equal (plist-get native :schema-id)
                    (plist-get (plist-get (plist-get state :catalogue) :identity) :schema_id))))))

(defun emacsvox-aural-voice-engine-controls--cancel ()
  "Detach this view's query without stopping speech or other observers."
  (when-let* ((state (emacsvox-aural-voice-editor--get :engine-controls)))
    (when (plist-get state :waiter) (omnivox-parameters--cancel (plist-get state :waiter)))
    (when (timerp (plist-get state :retry)) (cancel-timer (plist-get state :retry)))
    (emacsvox-aural-voice-engine-controls--put :retry nil)
    (emacsvox-aural-voice-engine-controls--put :waiter nil)
    (emacsvox-aural-voice-engine-controls--put :token nil)))

(defun emacsvox-aural-voice-engine-controls--closed ()
  "Release the view when its buffer closes, retaining only the ordinary draft."
  (emacsvox-aural-voice-engine-controls--cancel)
  (when emacsvox-aural-voice-editor--context
    (emacsvox-aural-voice-editor--put :engine-controls nil)))

(defun emacsvox-aural-voice-engine-controls--request (buffer state token process selector epoch deadline)
  "Request controls for the retained view, retrying busy replies until DEADLINE."
  (when (and (buffer-live-p buffer)
             (with-current-buffer buffer
               (and (eq state (emacsvox-aural-voice-editor--get :engine-controls))
                    (eq token (plist-get state :token)))))
    (with-current-buffer buffer
      (emacsvox-aural-voice-engine-controls--put :retry nil)
      (cond
       ((not (and (eq process tts-speaker-process)
                  (or (not (processp process)) (equal epoch (omnivox-parameters--epoch process)))
                  (equal selector (plist-get (emacsvox-aural-voice-engine-controls--row) :selector))))
        (emacsvox-aural-voice-engine-controls--put :result '(:status stale :message "Voice or speech connection changed; refresh controls"))
        (emacsvox-aural-voice-engine-controls--render))
       ((>= (float-time) deadline)
        (emacsvox-aural-voice-engine-controls--render))
       (t
        (emacsvox-aural-voice-engine-controls--put
         :waiter
         (omnivox-parameters--request
          process (plist-get selector :engine-id) (plist-get selector :voice-id)
          (lambda (result)
            (with-current-buffer buffer
              (unless (and (eq process tts-speaker-process)
                           (or (not (processp process)) (equal epoch (omnivox-parameters--epoch process)))
                           (equal selector (plist-get (emacsvox-aural-voice-engine-controls--row) :selector)))
                (setq result '(:status stale :message "Voice or speech connection changed; refresh controls")))
              (emacsvox-aural-voice-engine-controls--put :result result)
              (when (eq (plist-get result :status) 'ready)
                (emacsvox-aural-voice-engine-controls--put :catalogue (plist-get result :catalogue))
                (unless (plist-member state :expanded)
                  (emacsvox-aural-voice-engine-controls--put
                   :expanded (when-let* ((first (seq-first (plist-get (plist-get result :catalogue) :parameters))))
                               (list (plist-get first :group))))))
              (when (and (eq (plist-get result :status) 'busy) (< (float-time) deadline))
                (emacsvox-aural-voice-engine-controls--put
                 :retry (run-at-time
                         (min (- deadline (float-time))
                              (max 0.2 (/ (or (plist-get result :retry-after-ms) 200) 1000.0)))
                         nil #'emacsvox-aural-voice-engine-controls--request
                         buffer state token process selector epoch deadline)))
              (emacsvox-aural-voice-engine-controls--render)))
          (lambda () (and (buffer-live-p buffer)
                         (with-current-buffer buffer
                           (and (eq state (emacsvox-aural-voice-editor--get :engine-controls))
                                (eq token (plist-get state :token)))))))))))))

(defun emacsvox-aural-voice-engine-controls-refresh ()
  "Check controls asynchronously, retrying busy replies for up to five seconds.
Do not stop speech or play a sample.  Leaving this view cancels retries."
  (interactive)
  (emacsvox-aural-voice-engine-controls--cancel)
  (let* ((state (emacsvox-aural-voice-engine-controls--state))
         (selector (copy-tree (plist-get (emacsvox-aural-voice-engine-controls--row) :selector)))
         (engine (plist-get selector :engine-id)) (process tts-speaker-process)
         (buffer (current-buffer)) (token (list 'catalogue)))
    (unless engine (user-error "The choice no longer selects a specific engine"))
    (emacsvox-aural-voice-engine-controls--put :token token)
    (emacsvox-aural-voice-engine-controls--put :process process)
    (emacsvox-aural-voice-engine-controls--put :selector selector)
    (emacsvox-aural-voice-engine-controls--put :result '(:status checking))
    (emacsvox-aural-voice-engine-controls--render)
    (emacsvox-aural-voice-engine-controls--request
     buffer state token process selector
     (and (processp process) (omnivox-parameters--epoch process)) (+ (float-time) 5))))

(defun emacsvox-aural-voice-engine-controls--value (value)
  "Describe a wire scalar VALUE without confusing false, zero and unknown."
  (cond ((eq value :null) "unknown") ((eq value :false) "false") ((eq value t) "true")
        (t (format "%s" value))))

(defun emacsvox-aural-voice-engine-controls--operation (id)
  "Return the stored native operation for string ID."
  (cdr (assoc id (plist-get (plist-get (emacsvox-aural-voice-engine-controls--row) :native) :parameters))))

(defun emacsvox-aural-voice-engine-controls--summary (descriptor)
  "Describe DESCRIPTOR's requested value, origin and availability."
  (let* ((id (plist-get descriptor :id)) (operation (emacsvox-aural-voice-engine-controls--operation id))
         (unit (plist-get descriptor :unit)))
    (format "%s: %s%s" (plist-get descriptor :label)
            (pcase (plist-get operation :op)
              ('set (format "%s%s; adjusted here"
                            (emacsvox-aural-voice-engine-controls--value (if (null (plist-get operation :value)) :false (plist-get operation :value)))
                            (if (eq unit :null) "" (concat " " unit))))
              ('default "engine voice default")
              (_ "follows common settings"))
            (if (emacsvox-aural-voice-engine-controls--editable-p descriptor) ""
              (format "; read only%s" (if (equal (plist-get descriptor :scope) "voice") ""
                                        (concat "; " (plist-get descriptor :scope) " setting")))))))

(defun emacsvox-aural-voice-engine-controls--range (descriptor)
  "Return the described value range for DESCRIPTOR."
  (let ((type (plist-get descriptor :value_type)))
    (pcase (plist-get type :kind)
      ((or "integer" "number") (format "%s to %s" (plist-get type :minimum) (plist-get type :maximum)))
      ("boolean" "true / false")
      ("enum" (format "%d choices" (length (plist-get type :choices))))
      (_ "Not reported"))))

(defun emacsvox-aural-voice-engine-controls--table-row (descriptor)
  "Format DESCRIPTOR as parameter, value, source and range columns."
  (let* ((operation (emacsvox-aural-voice-engine-controls--operation (plist-get descriptor :id)))
         (unit (plist-get descriptor :unit))
         (value (if (eq (plist-get operation :op) 'set)
                    (concat (emacsvox-aural-voice-engine-controls--value
                             (if (null (plist-get operation :value)) :false (plist-get operation :value)))
                            (if (eq unit :null) "" (concat " " unit)))
                  "—"))
         (source (pcase (plist-get operation :op)
                   ('set "Adjusted here") ('default "Voice default") (_ "Common settings"))))
    (format "%-26s %-18s %-22s %s%s"
            (plist-get descriptor :label) value source
            (emacsvox-aural-voice-engine-controls--range descriptor)
            (if (emacsvox-aural-voice-engine-controls--editable-p descriptor) ""
              (concat "; read only; " (plist-get descriptor :scope))))))

(defun emacsvox-aural-voice-engine-controls--toggle (key &optional group)
  "Toggle view KEY, optionally the expanded GROUP."
  (let ((old (plist-get (emacsvox-aural-voice-engine-controls--state) key)))
    (emacsvox-aural-voice-engine-controls--put key
      (if group (if (member group old) (remove group old) (cons group old)) (not old))))
  (emacsvox-aural-voice-engine-controls--render)
  (emacsvox-aural-voice-editor-speak))

(defun emacsvox-aural-voice-engine-controls-search ()
  "Filter controls by label, identifier or help, across collapsed groups."
  (interactive)
  (emacsvox-aural-voice-engine-controls--put :filter
    (read-string "Find engine controls (empty shows all): " (plist-get (emacsvox-aural-voice-engine-controls--state) :filter)))
  (emacsvox-aural-voice-engine-controls--render))

(defun emacsvox-aural-voice-engine-controls--status-text ()
  "Describe current qualification and discovery for a navigable status row."
  (let* ((state (emacsvox-aural-voice-engine-controls--state)) (result (plist-get state :result))
         (row (emacsvox-aural-voice-engine-controls--row)) (native (plist-get row :native))
         (catalogue (plist-get state :catalogue)))
    (cond
     ((not row) "Choice removed; return to common settings or undo")
     ((not (emacsvox-aural-voice-engine-controls--fresh-p))
      (or (plist-get result :message)
          (pcase (plist-get result :status)
            ('checking "Checking engine controls…")
            ('busy (if (plist-get state :retry) "Waiting for the engine; retrying automatically"
                     "Engine still busy; press g to try again after speech finishes"))
            (_ "Controls are not current; refresh to edit"))))
     ((and native (not (equal (plist-get native :schema-id) (plist-get (plist-get catalogue :identity) :schema_id))))
      "Saved settings use a different schema; reset or remove them before editing")
     ((not (omnivox--native-tuning-supported-p (plist-get state :process)))
      "Read only; this worker cannot apply native voice settings")
     (t (format "Ready; %d described controls" (length (plist-get catalogue :parameters)))))))

(defun emacsvox-aural-voice-engine-controls--render ()
  "Render descriptor rows while preserving the selected field and groups."
  (let* ((state (emacsvox-aural-voice-engine-controls--state))
         (field (get-text-property (point) 'voice-field))
         (window (get-buffer-window (current-buffer))) (start (when window (window-start window)))
         (catalogue (plist-get state :catalogue))
         (row (emacsvox-aural-voice-engine-controls--row)) (native (plist-get row :native))
         (filter (or (plist-get state :filter) "")) (changed (plist-get state :changed))
         (descriptors (sort (append (plist-get catalogue :parameters) nil)
                            (lambda (a b) (< (plist-get a :order) (plist-get b :order)))))
         (groups (delete-dups (mapcar (lambda (d) (plist-get d :group)) descriptors)))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (format "%s — %s\nEngine-specific settings: %s\n%s\n\n"
                    (or (emacsvox-aural-voice-editor--get :voice) "Voice experiment")
                    (emacsvox-aural-voice-editor--get :palette)
                    (if row (emacsvox-aural-voice-workbench--selector-description (plist-get row :selector)) "Choice removed")
                    (plist-get (emacsvox-aural-voice-drafts--status (emacsvox-aural-voice-editor--draft)) :label)))
    (dolist (action '((play "Preview this choice" emacsvox-aural-voice-editor-play)
                      (compare "Compare original and edited choice" emacsvox-aural-voice-editor-compare)
                      (stop "Stop sample" emacsvox-aural-voice-editor-stop)
                      (save "Save and apply" emacsvox-aural-voice-editor-save)
                      (undo "Undo last edit" emacsvox-aural-voice-editor-undo)
                      (back "Back to common settings" emacsvox-aural-voice-engine-controls-back)
                      (refresh "Refresh controls" emacsvox-aural-voice-engine-controls-refresh)
                      (search "Search controls" emacsvox-aural-voice-engine-controls-search)))
      (emacsvox-aural-voice-editor--button (car action) (cadr action) (caddr action)))
    (emacsvox-aural-voice-editor--button 'changed
      (format "Adjusted controls only: %s" (if changed "on" "off"))
      (lambda () (emacsvox-aural-voice-engine-controls--toggle :changed)))
    (emacsvox-aural-voice-editor--button 'auto-sample
      (format "Automatic sample after adjustment: %s" (if (emacsvox-aural-voice-editor--get :automatic-sample) "on" "off"))
      (lambda () (emacsvox-aural-voice-editor--toggle :automatic-sample 'auto-sample)))
    (emacsvox-aural-voice-editor--button 'reset "Reset engine-specific settings" #'emacsvox-aural-voice-engine-controls-reset-all)
    (emacsvox-aural-voice-editor--button 'effective "Explain planned settings"
      (lambda () (emacsvox-aural-voice-editor--explain emacsvox-aural-voice-editor--context nil)))
    (emacsvox-aural-voice-editor--button 'status
      (emacsvox-aural-voice-engine-controls--status-text) #'emacsvox-aural-voice-engine-controls-refresh)
    (when (emacsvox-aural-voice-editor--get :preview-result)
      (emacsvox-aural-voice-editor--button 'preview-status
        (emacsvox-aural-voice-editor--preview-status (emacsvox-aural-voice-editor--get :preview-result))
        #'emacsvox-aural-voice-editor-speak))
    (insert "\nRET edits; left/right adjusts a set numeric value; ? reads parameter help.\ni follows common settings; d requests the voice default; u undoes. P plays a sample.\n")
    (unless (string-empty-p filter) (insert (format "Search: %s\n" filter)))
    (dolist (group groups)
      (let* ((members (cl-remove-if-not
                       (lambda (d) (and (equal group (plist-get d :group))
                                        (or (not changed) (emacsvox-aural-voice-engine-controls--operation (plist-get d :id)))
                                        (or (string-empty-p filter)
                                            (let ((case-fold-search t))
                                              (string-match-p (regexp-quote filter) (format "%s %s %s" (plist-get d :label) (plist-get d :id) (plist-get d :help))))))) descriptors))
             (expanded (or (not (string-empty-p filter)) changed (member group (plist-get state :expanded)))))
        (when members
          (if (or changed (not (string-empty-p filter)))
              (insert (format "%s: filtered controls\n" (capitalize (replace-regexp-in-string "_" " " group))))
            (emacsvox-aural-voice-editor--button (list 'group group)
              (format "%s: %s; %d controls" (capitalize (replace-regexp-in-string "_" " " group))
                      (if expanded "Expanded" "Collapsed") (length members))
              (lambda () (emacsvox-aural-voice-engine-controls--toggle :expanded group))))
          (when expanded
            (insert (format "  %-26s %-18s %-22s %s\n" "Parameter" "Value" "Source" "Range"))
            (dolist (descriptor members)
              (emacsvox-aural-voice-editor--button (list 'parameter (plist-get descriptor :id))
                (emacsvox-aural-voice-engine-controls--table-row descriptor)
                (lambda () (emacsvox-aural-voice-engine-controls--edit descriptor))))))))
    (dolist (operation (plist-get native :parameters))
      (when (and (not (cl-find (car operation) descriptors :test #'equal :key (lambda (d) (plist-get d :id))))
                 (let ((case-fold-search t)) (string-match-p (regexp-quote filter) (car operation))))
        (let ((id (car operation)))
          (emacsvox-aural-voice-editor--button (list 'parameter id)
            (format "%s: saved adjustment; not described here; RET removes it" id)
            (lambda () (emacsvox-aural-voice-engine-controls--apply id 'inherit))))))
    (unless descriptors (insert "No described controls available.\n"))
    (setq header-line-format "Engine-specific settings | ? help | P preview | w save | q common settings")
    (emacsvox-aural-voice-editor--locate field)
    (when window (set-window-start window (min (or start 1) (point-max))))))

(defun emacsvox-aural-voice-engine-controls--describe (descriptor)
  "Show DESCRIPTOR help, default evidence, mapping inputs and side effects."
  (let* ((catalogue (plist-get (emacsvox-aural-voice-engine-controls--state) :catalogue))
         (default (plist-get descriptor :default))
         (inputs (delete-dups (cl-loop for mapping across (plist-get catalogue :mappings)
                                      when (member (plist-get descriptor :id) (append (plist-get mapping :native_outputs) nil))
                                      append (append (plist-get mapping :common_inputs) nil)))))
    (emacsvox-aural-voice-editor-stop)
    (let ((help-window-select t))
      (emacsvox-aural-ui-with-help-window
       (princ (format "%s\n%s\n\nRange: %s%s.\nScope: %s.\nDefault: %s; source: %s.\nCommon inputs: %s.\nSide effects: %s.\nAvailability: %s%s.\n"
                     (plist-get descriptor :label) (plist-get descriptor :help)
                     (emacsvox-aural-voice-engine-controls--range descriptor)
                     (if (eq (plist-get descriptor :unit) :null) "" (concat " " (plist-get descriptor :unit)))
                     (plist-get descriptor :scope)
                     (emacsvox-aural-voice-engine-controls--value (plist-get default :value))
                     (replace-regexp-in-string "_" " " (plist-get default :source))
                     (if inputs (string-join inputs ", ") "none reported")
                     (if (> (length (plist-get descriptor :side_effects)) 0) (string-join (append (plist-get descriptor :side_effects) nil) ", ") "none reported")
                     (plist-get (plist-get descriptor :availability) :status)
                     (let ((reason (plist-get (plist-get descriptor :availability) :reason)))
                       (if (eq reason :null) "" (concat "; " reason)))))))
    (with-current-buffer (help-buffer)
      (emacsvox-aural-ui-speak (buffer-substring-no-properties (point-min) (point-max))))))

(defun emacsvox-aural-voice-engine-controls-help ()
  "Display and speak the current parameter's help; q returns to its row."
  (interactive)
  (let* ((field (get-text-property (point) 'voice-field))
         (descriptor (and (eq (car-safe field) 'parameter)
                          (cl-find (cadr field) (plist-get (plist-get (emacsvox-aural-voice-engine-controls--state) :catalogue) :parameters)
                                   :test #'equal :key (lambda (d) (plist-get d :id))))))
    (if descriptor (emacsvox-aural-voice-engine-controls--describe descriptor)
      (user-error "Choose a parameter row for help"))))

(defun emacsvox-aural-voice-engine-controls--apply (id operation &optional value)
  "Apply OPERATION and VALUE to ID, honoring the editor's automatic sample option."
  (let* ((state (emacsvox-aural-voice-engine-controls--state))
         (catalogue (plist-get state :catalogue)) (snapshot (emacsvox-aural-voice-editor--working))
         (row (emacsvox-aural-voice-engine-controls--row)) (native (plist-get row :native))
         (descriptor (cl-find id (plist-get catalogue :parameters) :test #'equal :key (lambda (d) (plist-get d :id)))))
    (unless row (user-error "The selected choice was removed"))
    (unless (eq operation 'inherit)
      (unless (and descriptor (emacsvox-aural-voice-engine-controls--editable-p descriptor))
        (user-error "This control is not currently editable; refresh or read its help"))
      (when (and (eq operation 'set)
                 (not (omnivox-parameters--accepts-p (plist-get descriptor :value_type) (if (null value) :false value))))
        (user-error "Value is outside the engine's type or range")))
    (when (or native (not (eq operation 'inherit)))
      (setq snapshot
            (plist-put snapshot :choices
                       (emacsvox-aural-voice-data--adjust-native
                        (plist-get snapshot :choices) (plist-get state :choice)
                        (or (plist-get native :engine-id) (plist-get catalogue :engine-id))
                        (or (plist-get native :schema-id) (plist-get (plist-get catalogue :identity) :schema_id))
                        id operation value)))
      (unless (equal snapshot (emacsvox-aural-voice-editor--working))
        (emacsvox-aural-voice-editor--changed
         snapshot (format "%s, %s" (or (plist-get descriptor :label) id)
                          (pcase operation ('inherit "common settings") ('default "voice default")
                                 (_ (emacsvox-aural-voice-engine-controls--value (if (null value) :false value))))))))))

(defun emacsvox-aural-voice-engine-controls--edit (descriptor)
  "Read DESCRIPTOR's operation with completion and stale-input checks."
  (if (not (emacsvox-aural-voice-engine-controls--editable-p descriptor))
      (emacsvox-aural-voice-engine-controls--describe descriptor)
    (let* ((state (emacsvox-aural-voice-engine-controls--state)) (catalogue (plist-get state :catalogue))
           (draft (emacsvox-aural-voice-editor--draft)) (revision (emacsvox-aural-voice-draft-revision draft))
           (id (plist-get descriptor :id)) (type (plist-get descriptor :value_type))
           (old (emacsvox-aural-voice-engine-controls--operation id))
           (previous (and (eq (plist-get old :op) 'set) (plist-get old :value)))
           (operation (completing-read (concat (plist-get descriptor :label) ": ")
                                       '("Set value" "Follow common settings" "Engine voice default" "Parameter help") nil t nil nil "Set value"))
           (value (when (equal operation "Set value")
                    (pcase (plist-get type :kind)
                      ("boolean" (equal (completing-read "Value: " '("true" "false") nil t nil nil
                                                       (if (and (eq (plist-get old :op) 'set) (null previous)) "false" "true")) "true"))
                      ("enum" (let ((choices (mapcar (lambda (c) (cons (format "%s (%s)" (plist-get c :label) (plist-get c :value))
                                                                       (plist-get c :value))) (append (plist-get type :choices) nil))))
                                (cdr (assoc (completing-read "Value: " choices nil t nil nil
                                                            (or (car (rassoc previous choices)) (caar choices))) choices))))
                      (_ (read-number (format "Value (%s to %s%s): " (plist-get type :minimum) (plist-get type :maximum)
                                               (if (eq (plist-get descriptor :unit) :null) "" (concat " " (plist-get descriptor :unit))))
                                      (and (numberp previous) previous)))))))
      (unless (and (eq state (emacsvox-aural-voice-editor--get :engine-controls))
                   (eq catalogue (plist-get state :catalogue)) (= revision (emacsvox-aural-voice-draft-revision draft))
                   (emacsvox-aural-voice-engine-controls--editable-p descriptor))
        (user-error "Voice or controls changed while editing; try again"))
      (if (equal operation "Parameter help") (emacsvox-aural-voice-engine-controls--describe descriptor)
        (emacsvox-aural-voice-engine-controls--apply id
          (pcase operation ("Set value" 'set) ("Engine voice default" 'default)
                 ("Follow common settings" 'inherit) (_ (user-error "Choose an editing operation"))) value)))))

(defun emacsvox-aural-voice-engine-controls-inherit ()
  "Remove this control's override, following common settings."
  (interactive)
  (let ((field (get-text-property (point) 'voice-field)))
    (unless (eq (car-safe field) 'parameter) (user-error "Choose an engine control"))
    (emacsvox-aural-voice-engine-controls--apply (cadr field) 'inherit)))

(defun emacsvox-aural-voice-engine-controls-default ()
  "Request this control's engine voice default without copying a measured value."
  (interactive)
  (let ((field (get-text-property (point) 'voice-field)))
    (unless (eq (car-safe field) 'parameter) (user-error "Choose an engine control"))
    (emacsvox-aural-voice-engine-controls--apply (cadr field) 'default)))

(defun emacsvox-aural-voice-engine-controls--adjust (delta)
  "Adjust the current numeric parameter by DELTA engine steps."
  (let* ((field (get-text-property (point) 'voice-field))
         (descriptor (and (eq (car-safe field) 'parameter)
                          (cl-find (cadr field) (plist-get (plist-get (emacsvox-aural-voice-engine-controls--state) :catalogue) :parameters)
                                   :test #'equal :key (lambda (d) (plist-get d :id)))))
         (operation (and descriptor (emacsvox-aural-voice-engine-controls--operation (cadr field))))
         (type (plist-get descriptor :value_type)))
    (cond
     ((not descriptor) (emacsvox-aural-voice-editor--move-field delta))
     ((not (emacsvox-aural-voice-engine-controls--editable-p descriptor))
      (user-error "This parameter is read only; press ? for help"))
     ((not (and (member (plist-get type :kind) '("integer" "number"))
                (eq (plist-get operation :op) 'set)))
      ;; An inherited or unknown default value must not be guessed from a bound.
      (emacsvox-aural-voice-engine-controls--edit descriptor))
     (t
      (let* ((current (plist-get operation :value))
             (step (plist-get type :step))
             (next (max (plist-get type :minimum)
                        (min (plist-get type :maximum) (+ current (* delta (if (numberp step) step 1)))))))
        (if (= current next)
            (progn (emacsvox-aural-voice-editor-stop)
                   (emacsvox-aural-ui-speak (format "%s %s" (if (> delta 0) "Maximum" "Minimum") next)))
          (emacsvox-aural-voice-engine-controls--apply (cadr field) 'set next)))))))

(defun emacsvox-aural-voice-engine-controls-increase ()
  "Increase the selected native parameter by one engine step."
  (interactive) (emacsvox-aural-voice-engine-controls--adjust 1))

(defun emacsvox-aural-voice-engine-controls-decrease ()
  "Decrease the selected native parameter by one engine step."
  (interactive) (emacsvox-aural-voice-engine-controls--adjust -1))

(defun emacsvox-aural-voice-engine-controls-reset-all ()
  "Remove only this choice's native settings, retaining an undo step."
  (interactive)
  (let* ((snapshot (emacsvox-aural-voice-editor--working))
         (id (plist-get (emacsvox-aural-voice-engine-controls--state) :choice))
         (row (cl-find id (plist-get snapshot :choices) :test #'equal :key (lambda (r) (plist-get r :id)))))
    (unless row (user-error "The selected choice was removed"))
    (setf (plist-get snapshot :choices)
          (mapcar (lambda (choice)
                    (when (equal id (plist-get choice :id)) (cl-remf choice :native)) choice)
                  (plist-get snapshot :choices)))
    (unless (equal snapshot (emacsvox-aural-voice-editor--working))
      (emacsvox-aural-voice-editor--changed snapshot "Engine-specific settings reset"))))

(defun emacsvox-aural-voice-engine-controls-back ()
  "Return to common settings, keeping the same draft and selected choice."
  (interactive)
  (emacsvox-aural-voice-engine-controls--cancel)
  (emacsvox-aural-voice-editor--put :engine-controls nil)
  (emacsvox-aural-voice-engine-controls-mode -1)
  (emacsvox-aural-voice-editor-refresh)
  (emacsvox-aural-voice-editor--locate 'engine-controls)
  (emacsvox-aural-voice-editor-speak))

(define-minor-mode emacsvox-aural-voice-engine-controls-mode
  "Edit descriptor-based engine controls within the current voice draft."
  :lighter nil
  :keymap (let ((map (make-sparse-keymap)))
            (dolist (pair '(("q" . emacsvox-aural-voice-engine-controls-back)
                            ("g" . emacsvox-aural-voice-engine-controls-refresh)
                            ("/" . emacsvox-aural-voice-engine-controls-search)
                            ("?" . emacsvox-aural-voice-engine-controls-help)
                            ("<right>" . emacsvox-aural-voice-engine-controls-increase)
                            ("<left>" . emacsvox-aural-voice-engine-controls-decrease)
                            ("i" . emacsvox-aural-voice-engine-controls-inherit)
                            ("d" . emacsvox-aural-voice-engine-controls-default)))
              (define-key map (kbd (car pair)) (cdr pair))) map))

(defun emacsvox-aural-voice-engine-controls-open ()
  "Open described engine controls for a selected physical choice in this draft."
  (interactive)
  (let* ((snapshot (emacsvox-aural-voice-editor--working))
         (rows (emacsvox-aural-voice-editing--rows snapshot))
         (id (or (emacsvox-aural-voice-editor--get :tuning-choice)
                 (and (= (length rows) 1) (plist-get (car rows) :id))
                 (emacsvox-aural-voice-editor--read-choice snapshot "Voice for engine-specific settings: ")))
         (row (cl-find id rows :test #'equal :key (lambda (r) (plist-get r :id)))))
    (unless (plist-get (plist-get row :selector) :engine-id) (user-error "Choose a physical voice with a specific engine first"))
    (emacsvox-aural-voice-engine-controls--cancel)
    (emacsvox-aural-voice-editor--put :tuning-choice id)
    (emacsvox-aural-voice-editor--put :engine-controls (list :choice id :result '(:status checking)))
    (emacsvox-aural-voice-engine-controls-mode 1)
    (add-hook 'kill-buffer-hook #'emacsvox-aural-voice-engine-controls--closed nil t)
    (emacsvox-aural-voice-engine-controls-refresh)))

(provide 'emacsvox-aural-voice-engine-controls)
;;; emacsvox-aural-voice-engine-controls.el ends here
