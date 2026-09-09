;;; omnivox-choice-codec.el --- Individual voice wire values -*- lexical-binding: t; -*-

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

;; Pure conversions for the negotiated per-choice voice bundle.  Raw saved
;; values retain presence until conversion; contextual nil keeps its existing
;; ACSS meaning.  Physical route selection belongs to the server.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'emacsvox-aural-rules)
(require 'emacsvox-aural-routing-profiles)

(declare-function omnivox-scale-average-pitch "omnivox-voices" (value))
(declare-function omnivox--preview-selector-json "omnivox-voices" (selector))

(defconst omnivox--choice-wire-fields
  '((:average-pitch :average_pitch acss)
    (:pitch-range :pitch_range acss)
    (:stress :stress acss)
    (:richness :richness acss)
    (:rate-offset :rate_offset rate)
    (:gain :gain effect)
    (:low-pass :low_pass effect)
    (:high-pass :high_pass effect)
    (:pan :pan effect)
    (:reverb :reverb effect)
    (:echo :echo effect)
    (:chorus :chorus effect))
  "Raw key, wire key and normalization group for each sparse field.")

(defun omnivox--choice-normalize-value (field value)
  "Normalize non-nil raw VALUE using FIELD's wire conversion."
  (let ((key (car field)))
    (pcase (caddr field)
      ('rate value)
      ('effect (emacsvox-aural-normalize-post-synthesis-value
                (intern (substring (symbol-name key) 1)) value))
      (_ (let ((normalized (/ (float value) 9.0)))
           (if (eq key :average-pitch)
               (omnivox-scale-average-pitch normalized)
             normalized))))))

(defun omnivox--choice-patch-json (patch &optional context)
  "Convert a raw sparse PATCH to set/default operations without mutation.
CONTEXT preserves legacy contextual ACSS nil as no audible override."
  (emacsvox-aural-routing--validate-choice-adjustments patch)
  (let (result)
    (dolist (field omnivox--choice-wire-fields)
      (when (plist-member patch (car field))
        (let ((value (plist-get patch (car field))))
          (unless (and context (eq (caddr field) 'acss) (null value))
            (setq result
                  (plist-put result (cadr field)
                             (if (null value) '(:op "default")
                               (list :op "set" :value
                                     (omnivox--choice-normalize-value field value)))))))))
    (or result (make-hash-table :test #'equal))))

(defun omnivox--choice-records-json (choices)
  "Convert complete raw CHOICES, preserving order and occurrence identity."
  (emacsvox-aural-routing--validate-choices choices)
  (vconcat
   (mapcar (lambda (choice)
             (list :id (plist-get choice :id)
                   :selector (omnivox--preview-selector-json (plist-get choice :selector))
                   :adjustments (omnivox--choice-patch-json (plist-get choice :adjustments))))
           choices)))

(defun omnivox--choice-normalized-number (value)
  "Validate a nullable normalized VALUE and return its JSON representation."
  (unless (or (null value) (and (numberp value) (<= 0 value 1)))
    (error "Individual voice value must be nil or a finite number from zero to one"))
  (if (null value) :null value))

(defun omnivox--choice-shared-json (acss rate-offset effects)
  "Complete normalized ACSS, RATE-OFFSET and EFFECTS for a shared wire base.
ACSS uses wire field names and already includes adapter pitch contrast."
  (unless (or (null rate-offset)
              (and (integerp rate-offset) (<= -20 rate-offset 20)))
    (error "Individual voice relative rate must be nil or an integer from -20 to 20"))
  (when (and (plist-get acss :rate) rate-offset)
    (error "Individual voice cannot combine absolute and relative rate"))
  (let (wire-acss wire-effects)
    (dolist (key '(:rate :average_pitch :pitch_range :stress :richness :volume))
      (setq wire-acss (plist-put wire-acss key
                                 (omnivox--choice-normalized-number (plist-get acss key)))))
    (dolist (key '(:gain :low_pass :high_pass :pan :reverb :echo :chorus))
      (setq wire-effects (plist-put wire-effects key
                                    (omnivox--choice-normalized-number (plist-get effects key)))))
    (list :acss wire-acss :rate_offset (or rate-offset :null) :effects wire-effects)))

(defun omnivox--choice-style-json (style)
  "Convert raw shared STYLE to the complete wire base without capability loss.
Legacy absolute rate remains unapplied, as in the existing style compiler."
  (let (acss effects patch)
    (dolist (field omnivox--choice-wire-fields)
      (when (plist-member style (car field))
        (setq patch (plist-put patch (car field) (plist-get style (car field))))))
    (emacsvox-aural-routing--validate-choice-adjustments patch)
    (dolist (field omnivox--choice-wire-fields)
      (let ((value (plist-get style (car field))))
        (when (and value (not (eq (caddr field) 'rate)))
          (let ((normalized (omnivox--choice-normalize-value field value)))
            (if (eq (caddr field) 'acss)
                (setq acss (plist-put acss (cadr field) normalized))
              (setq effects (plist-put effects (cadr field) normalized)))))))
    (omnivox--choice-shared-json acss (plist-get style :rate-offset) effects)))

(defun omnivox--choice-span-projection (registration logical request balance)
  "Project LOGICAL, raw REQUEST and BALANCE against frozen REGISTRATION.
Return wire fields and compact provenance for an inspectable layered span.
Opaque legacy requests return nil.  Do not infer context by diffing
effective values."
  (let* ((content (plist-get registration :content))
         (definition (cl-find logical (plist-get content :definitions) :test #'equal
                              :key (lambda (entry) (plist-get (plist-get entry :definition) :id)))))
    (when (and (equal (plist-get definition :mode) "layered")
               (or (null request) (symbolp request) (stringp request)
                   (and (emacsvox-aural-voice-style-p request)
                        (or (null (plist-get request :preset))
                            (symbolp (plist-get request :preset))))))
      (let (raw)
        (when (emacsvox-aural-voice-style-p request)
          (dolist (field omnivox--choice-wire-fields)
            (when (plist-member request (car field))
              (setq raw (plist-put raw (car field) (plist-get request (car field)))))))
        (let* ((patch (omnivox--choice-patch-json raw t))
               (placement (list :pan (if (numberp balance)
                                        (/ (1+ (float (max -1.0 (min 1.0 balance)))) 2.0)
                                      :null))))
          (list (list :logical_voice_id logical :context patch :placement placement)
                (list :mode 'layered :logical-id logical :raw-context raw
                      :wire-context patch :placement placement)))))))

(defconst omnivox--choice-u64-max (1- (expt 2 64)))
(defconst omnivox--choice-marker-line-limit (* 512 1024))
(defconst omnivox--choice-receipt-limit (* 32 1024))

(defun omnivox--choice-object-keys (object keys)
  "Require OBJECT to contain exactly KEYS, including nullable members."
  (unless (and (proper-list-p object) (zerop (% (length object) 2)))
    (error "Expected an individual voice JSON object"))
  (let (seen)
    (cl-loop for (key _value) on object by #'cddr do
             (when (or (not (memq key keys)) (memq key seen))
               (error "Unknown or duplicate individual voice field %S" key))
             (push key seen))
    (unless (= (length seen) (length keys))
      (error "Missing individual voice JSON field")))
  object)

(defun omnivox--choice-unsigned (value &optional maximum positive)
  "Require unsigned integer VALUE within MAXIMUM, optionally POSITIVE."
  (unless (and (integerp value) (<= (if positive 1 0) value
                                    (or maximum omnivox--choice-u64-max)))
    (error "Invalid individual voice integer %S" value))
  value)

(defun omnivox--choice-validate-wire-patch (patch)
  "Validate complete sparse wire PATCH without accepting mixed raw values."
  (unless (or (and (hash-table-p patch) (zerop (hash-table-count patch)))
              (consp patch))
    (error "Expected a sparse adjustment object"))
  (unless (hash-table-p patch)
    (let ((keys (cl-loop for (key _value) on patch by #'cddr collect key))
          (allowed (mapcar #'cadr omnivox--choice-wire-fields)))
      (omnivox--choice-object-keys patch keys)
      (dolist (key keys)
        (unless (memq key allowed) (error "Unknown adjustment field %S" key))
        (let ((operation (plist-get patch key)))
          (pcase (plist-get operation :op)
            ("default" (omnivox--choice-object-keys operation '(:op)))
            ("set"
             (omnivox--choice-object-keys operation '(:op :value))
             (let ((value (plist-get operation :value)))
               (unless (if (eq key :rate_offset)
                           (and (integerp value) (<= -20 value 20))
                         (and (numberp value) (<= 0 value 1)))
                 (error "Invalid adjustment value"))))
            (_ (error "Invalid adjustment operation")))))))
  patch)

(defun omnivox--choice-string (value maximum &optional nullable empty)
  "Require a bounded string VALUE with optional NULLABLE or EMPTY allowance."
  (unless (or (and nullable (eq value :null))
              (and (stringp value) (or empty (not (string-empty-p value)))
                   (<= (string-bytes value) maximum)))
    (error "Invalid individual voice string"))
  value)

(defun omnivox--choice-physical-id (value)
  "Validate exact physical identity VALUE without inferring a choice row."
  (omnivox--choice-object-keys value '(:engine_id :voice_id))
  (omnivox--choice-string (plist-get value :engine_id) 128)
  (omnivox--choice-string (plist-get value :voice_id) 4096)
  value)

(defun omnivox--choice-degradations (value allowed)
  "Require bounded distinct enum array VALUE using ALLOWED dimensions."
  (unless (and (vectorp value) (<= (length value) (length allowed))
               (cl-every (lambda (item) (member item allowed)) value)
               (= (length value) (length (delete-dups (append value nil)))))
    (error "Invalid individual voice degradation array")))

(defun omnivox--choice-audio-identity (choice &optional accepted)
  "Validate CHOICE audio identity, optionally an ACCEPTED audio record."
  (omnivox--choice-object-keys
   choice (append '(:choice_id :reason :realized :degraded_acss :degraded_effects)
                  (when accepted '(:playback_started))))
  (let ((id (plist-get choice :choice_id))
        (reason (plist-get choice :reason)))
    (unless (or (eq id :null)
                (and (stringp id) (string-match-p "\\`[A-Za-z0-9_.-]\\{1,128\\}\\'" id)))
      (error "Invalid individual choice ID"))
    (let* ((kind (plist-get reason :reason))
           (index-key (pcase kind
                        ("explicit_alternative" :preference_index)
                        ("preferred_engine" :preferred_index)
                        ("fallback_engine" :fallback_index))))
      (unless (member kind '("preferred" "explicit_alternative" "same_language_on_requested_engine"
                             "preferred_engine" "global_default" "fallback_engine"))
        (error "Invalid individual choice resolution reason"))
      (omnivox--choice-object-keys reason (if index-key (list :reason index-key) '(:reason)))
      (when index-key
        (omnivox--choice-unsigned (plist-get reason index-key) nil
                                  (eq index-key :preference_index)))
      (unless (if (member kind '("preferred" "explicit_alternative"))
                  (stringp id) (eq id :null))
        (error "Individual choice ID disagrees with resolution reason"))))
  (omnivox--choice-physical-id (plist-get choice :realized))
  (omnivox--choice-degradations (plist-get choice :degraded_acss)
                                '("rate" "average_pitch" "pitch_range" "stress" "richness" "volume"))
  (omnivox--choice-degradations (plist-get choice :degraded_effects)
                                '("gain" "low_pass" "high_pass" "pan" "chorus" "reverb" "echo"))
  (when (and accepted (not (memq (plist-get choice :playback_started) '(t :false))))
    (error "Invalid accepted audio playback flag"))
  choice)

(defun omnivox--choice-validate-marker (event)
  "Validate every member of a decoded version-3 marker EVENT."
  (let* ((type (plist-get event :type))
         (fields
          (pcase type
            ("utterance_started" '(:text :engine_id :actual_voice :logical_voice_id :sample_rate :frame_count))
            ("voice_choice_applied" '(:span_id :registry_generation :logical_voice_id :choice))
            ("marker_reached" '(:marker))
            ("semantic_event_reached" '(:action_id))
            ("timeline_action_resolved" '(:action_id :resolution))
            ("timeline_style_degraded" '(:degraded_acss :degraded_effects))
            (_ (error "Unknown version-3 marker type")))))
    (omnivox--choice-object-keys event (append '(:protocol_version :dispatch_id :sequence :type :utterance_id) fields))
    (unless (eql (plist-get event :protocol_version) 3) (error "Expected version-3 marker"))
    (dolist (key '(:dispatch_id :sequence :utterance_id))
      (omnivox--choice-unsigned (plist-get event key) nil t))
    (pcase type
      ("utterance_started"
       (omnivox--choice-string (plist-get event :text) omnivox--choice-marker-line-limit nil t)
       (omnivox--choice-string (plist-get event :engine_id) 128)
       (omnivox--choice-string (plist-get event :logical_voice_id) 128 t)
       (unless (eq (plist-get event :actual_voice) :null)
         (omnivox--choice-physical-id (plist-get event :actual_voice))
         (unless (equal (plist-get event :engine_id)
                        (plist-get (plist-get event :actual_voice) :engine_id))
           (error "Started voice disagrees with engine")))
       (omnivox--choice-unsigned (plist-get event :sample_rate) (1- (expt 2 32)))
       (omnivox--choice-unsigned (plist-get event :frame_count)))
      ("voice_choice_applied"
       (dolist (key '(:span_id :registry_generation))
         (omnivox--choice-unsigned (plist-get event key) nil t))
       (omnivox--choice-string (plist-get event :logical_voice_id) 128)
       (omnivox--choice-audio-identity (plist-get event :choice)))
      ("marker_reached"
       (let ((marker (plist-get event :marker)))
         (omnivox--choice-object-keys marker '(:kind :frame_offset :text_start :text_length :value))
         (unless (member (plist-get marker :kind) '("word" "sentence" "phoneme" "native_index"))
           (error "Invalid synthesis marker kind"))
         (omnivox--choice-unsigned (plist-get marker :frame_offset))
         (dolist (key '(:text_start :text_length))
           (unless (eq (plist-get marker key) :null)
             (omnivox--choice-unsigned (plist-get marker key) (1- (expt 2 32)))))
         (omnivox--choice-string (plist-get marker :value) omnivox--choice-marker-line-limit t t)))
      ((or "semantic_event_reached" "timeline_action_resolved")
       (omnivox--choice-string (plist-get event :action_id) 128)
       (when (and (equal type "timeline_action_resolved")
                  (not (member (plist-get event :resolution) '("exact" "word_boundary" "span_boundary" "omitted"))))
         (error "Invalid timeline anchor resolution")))
      ("timeline_style_degraded"
       (omnivox--choice-degradations (plist-get event :degraded_acss)
                                     '("rate" "average_pitch" "pitch_range" "stress" "richness" "volume"))
       (omnivox--choice-degradations (plist-get event :degraded_effects)
                                     '("gain" "low_pass" "high_pass" "pan" "chorus" "reverb" "echo")))))
  event)

(defun omnivox--choice-decode-marker (payload)
  "Decode strict version-3 Base64 marker PAYLOAD, retaining null and booleans."
  ;; The remote bound includes the prefix, separating space and newline.
  (when (> (+ (string-bytes payload) (length "__EMACSVOX_MARKER__") 2)
           omnivox--choice-marker-line-limit)
    (error "Version-3 marker exceeds the remote line limit"))
  (let* ((bytes (base64-decode-string payload))
         (text (decode-coding-string bytes 'utf-8 t)))
    (unless (and (equal payload (base64-encode-string bytes t))
                 (equal bytes (encode-coding-string text 'utf-8 t)))
      (error "Invalid version-3 marker encoding"))
    ;; Native plist decoding preserves duplicate members for the exact-key
    ;; validators; arrays remain vectors so [] cannot impersonate {} or null.
    (let ((event (json-parse-string text :object-type 'plist :array-type 'array
                                    :null-object :null :false-object :false)))
      (omnivox--choice-validate-marker event)
      (when (and (equal (plist-get event :type) "voice_choice_applied")
                 (> (string-bytes bytes) omnivox--choice-receipt-limit))
        (error "Individual voice receipt exceeds its decoded limit"))
      event)))

(provide 'omnivox-choice-codec)
;;; omnivox-choice-codec.el ends here
