;;; omnivox-control-codec.el --- Omnivox control wire data  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Bart Bunting <bart@ursys.com.au>
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

;; Bounded control and marker encoding, voice selectors, and preview values.
;; These helpers validate and translate data.  The voice adapter retains
;; process capability checks, request admission, callbacks and registration.
;; Pitch conversion and generic preview metadata use the established adapter
;; and TTS helpers; loading this module does not initialize either runtime.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function omnivox-scale-average-pitch "omnivox-voices" (value))
(declare-function tts--voice-preview-dimensions "tts-voice-api" (plist))
(declare-function tts--voice-preview-selector-kind "tts-voice-api" (selector))

(defconst omnivox-control-protocol-version 1
  "Control protocol version supported by this adapter.")

(defconst omnivox-control-event-prefix "__OMNIVOX_CONTROL__ "
  "Prefix of Base64-JSON control events emitted by Omnivox.")

(defconst omnivox-control-max-payload-bytes (* 256 1024)
  "Maximum decoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox-control-max-encoded-bytes 349532
  "Maximum encoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox-marker-event-protocol-versions '(1 2)
  "Marker event protocol versions supported by this adapter.")

(defconst omnivox-marker-event-prefix "__EMACSVOX_MARKER__ "
  "Prefix of Base64-JSON playback marker events emitted by Omnivox.")

(defconst omnivox-marker-max-payload-bytes (* 2 1024 1024)
  "Maximum decoded Omnivox marker event accepted by Emacsvox.")

(defconst omnivox-marker-max-encoded-bytes 2796208
  "Maximum encoded Omnivox marker event accepted by Emacsvox.")

(defun omnivox--encode-control-request (request)
  "Encode control REQUEST as bounded, unwrapped Base64 JSON."
  (let* ((json (json-serialize request))
         (payload (encode-coding-string json 'utf-8 t)))
    (when (> (string-bytes payload) omnivox-control-max-payload-bytes)
      (error "Omnivox control request exceeds %d bytes"
             omnivox-control-max-payload-bytes))
    (base64-encode-string payload t)))

(defun omnivox--decode-control-response (payload &optional strict)
  "Decode bounded Base64-JSON PAYLOAD, retaining native types when STRICT."
  (when (> (string-bytes payload) omnivox-control-max-encoded-bytes)
    (error "Encoded Omnivox control response exceeds its size limit"))
  (let ((decoded (base64-decode-string payload)))
    (when (> (string-bytes decoded) omnivox-control-max-payload-bytes)
      (error "Decoded Omnivox control response exceeds its size limit"))
    (let ((text (decode-coding-string decoded 'utf-8 t)))
      (when (and strict
                 (not (and (equal payload (base64-encode-string decoded t))
                           (equal decoded (encode-coding-string text 'utf-8 t)))))
        (error "Invalid private preview encoding"))
      (json-parse-string
       text :object-type 'plist :array-type (if strict 'array 'list)
       :null-object (if strict :null nil) :false-object (if strict :false nil)))))

(defun omnivox--decode-marker-event (payload)
  "Decode and validate one bounded Base64-JSON marker event PAYLOAD."
  (when (> (string-bytes payload) omnivox-marker-max-encoded-bytes)
    (error "Encoded Omnivox marker event exceeds its size limit"))
  (let ((decoded (base64-decode-string payload)))
    (when (> (string-bytes decoded) omnivox-marker-max-payload-bytes)
      (error "Decoded Omnivox marker event exceeds its size limit"))
    (json-parse-string
     (decode-coding-string decoded 'utf-8 t)
     :object-type 'plist :array-type 'list
     :null-object nil :false-object nil)))

(defun omnivox--required-selector-id (value kind)
  "Validate and return selector ID VALUE described by KIND."
  (unless (and (stringp value) (not (string-empty-p value)))
    (error "Omnivox %s must be a nonempty string" kind))
  value)

(defun omnivox--selector-json (selector)
  "Convert one portable SELECTOR form to its JSON plist representation."
  (pcase selector
    (`(exact ,engine-id ,voice-id)
     (list
      :kind "exact"
      :engine_id (omnivox--required-selector-id engine-id "engine ID")
      :voice_id (omnivox--required-selector-id voice-id "voice ID")))
    (`(engine-default ,engine-id)
     (list
      :kind "engine_default"
      :engine_id (omnivox--required-selector-id engine-id "engine ID")))
    (`(properties . ,properties)
     (unless (proper-list-p properties)
       (error "Invalid Omnivox property selector: %S" selector))
     (let ((engine-id (plist-get properties :engine))
           (language (plist-get properties :language))
           (gender (plist-get properties :gender)))
       (when engine-id
         (omnivox--required-selector-id engine-id "engine ID"))
       (when (and language (not (stringp language)))
         (error "Omnivox selector language must be a string"))
       (when (and gender (not (or (symbolp gender) (stringp gender))))
         (error "Omnivox selector gender must be a symbol or string"))
       (list
        :kind "properties"
        :engine_id (or engine-id :null)
        :language (or language :null)
        :gender
        (if gender
            (downcase
             (if (symbolp gender) (symbol-name gender) gender))
          :null))))
    (_ (error "Invalid Omnivox voice selector: %S" selector))))

(defun omnivox--preview-selector-json (selector)
  "Convert normalized generic preview SELECTOR to Omnivox JSON data."
  (let ((kind (plist-get selector :kind)))
    (when (stringp kind) (setq kind (intern kind)))
    (pcase kind
      ('exact
       (omnivox--selector-json
        (list 'exact
              (plist-get selector :engine-id)
              (plist-get selector :voice-id))))
      ('engine-default
       (omnivox--selector-json
        (list 'engine-default (plist-get selector :engine-id))))
      ('properties
       (omnivox--selector-json
        (list 'properties
              :engine (plist-get selector :engine-id)
              :language (plist-get selector :language)
              :gender (plist-get selector :gender))))
      (_ (error "Invalid generic Omnivox preview selector: %S" selector)))))

(defun omnivox--preview-acss-json (acss)
  "Convert normalized generic ACSS plist to Omnivox JSON fields."
  (let (result)
    (dolist
        (mapping
         '((:rate . :rate)
           (:average-pitch . :average_pitch)
           (:pitch-range . :pitch_range)
           (:stress . :stress)
           (:richness . :richness)
           (:volume . :volume)))
      (when (plist-member acss (car mapping))
        (let ((value (plist-get acss (car mapping))))
          (when (and (eq (car mapping) :average-pitch) (numberp value))
            (setq value (omnivox-scale-average-pitch value)))
          (setq result (plist-put result (cdr mapping) value)))))
    (or result (make-hash-table :test #'equal))))

(defun omnivox--preview-effects-json (effects)
  "Convert normalized generic EFFECTS plist to Omnivox JSON fields."
  (let (result)
    (dolist
        (mapping
         '((:gain . :gain)
           (:low-pass . :low_pass)
           (:high-pass . :high_pass)
           (:pan . :pan)
           (:reverb . :reverb)
           (:echo . :echo)
           (:chorus . :chorus)))
      (when (plist-member effects (car mapping))
        (setq result
              (plist-put result (cdr mapping)
                         (plist-get effects (car mapping))))))
    (or result (make-hash-table :test #'equal))))

(defun omnivox--preview-dimension-symbol (value)
  "Return generic dimension symbol for Omnivox wire VALUE."
  (intern (replace-regexp-in-string "_" "-" (format "%s" value))))

(defun omnivox--normalize-preview-response
    (entry response effects-supported rate-supported)
  "Normalize preview RESPONSE for ENTRY and EFFECTS-SUPPORTED status."
  (if (not (equal (plist-get response :type) "preview_completed"))
      (list
       :status 'failed :completion-guarantee 'playback
       :requested (copy-tree (plist-get entry :selector))
       :realized nil
       :degraded-acss
       (append
        (tts--voice-preview-dimensions (plist-get entry :acss))
        (and
         (numberp (plist-get entry :rate-offset))
         (not (zerop (plist-get entry :rate-offset)))
         '(rate-offset)))
       :degraded-effects
       (tts--voice-preview-dimensions (plist-get entry :effects))
       :message (or (plist-get response :message)
                    "Omnivox returned an invalid preview response"))
    (let* ((realized (plist-get response :realized))
           (selector (plist-get entry :selector))
           (mismatch
            (and (equal (plist-get response :status) "completed")
                 (memq (tts--voice-preview-selector-kind selector) '(exact engine-default))
                 (not (and (equal (plist-get selector :engine-id)
                                  (plist-get realized :engine_id))
                           (or (eq (tts--voice-preview-selector-kind selector) 'engine-default)
                               (equal (plist-get selector :voice-id)
                                      (plist-get realized :voice_id))))))))
      (list
       :status (if mismatch 'failed (intern (or (plist-get response :status) "failed")))
       :completion-guarantee 'playback
       :requested (copy-tree (plist-get entry :selector))
       :realized
       (and realized
            (list :engine-id (plist-get realized :engine_id)
                  :voice-id (plist-get realized :voice_id)))
       :degraded-acss
       (let ((degraded
              (mapcar #'omnivox--preview-dimension-symbol
                      (plist-get response :degraded_acss))))
         (when (and
                (numberp (plist-get entry :rate-offset))
                (not (zerop (plist-get entry :rate-offset))))
           (if rate-supported
               (when (memq 'rate degraded)
                 (setq degraded
                       (cons 'rate-offset (delq 'rate degraded))))
             (push 'rate-offset degraded)))
         degraded)
       :degraded-effects
       (if effects-supported
           (mapcar #'omnivox--preview-dimension-symbol
                   (plist-get response :degraded_effects))
         (tts--voice-preview-dimensions (plist-get entry :effects)))
       :message (if mismatch
                    "The server did not realize the requested exact engine and voice"
                  (plist-get response :message))))))

(defun omnivox--preview-valid-id-p (value limit &optional pattern)
  "Return non-nil for a bounded ID VALUE, with LIMIT bytes and PATTERN."
  (let ((case-fold-search nil))
    (and (stringp value) (not (string-empty-p value))
         (<= (string-bytes value) limit)
         (not (string-match-p "[[:cntrl:]]" value))
         (or (null pattern) (string-match-p pattern value)))))

(defun omnivox--preview-validate-selector (selector)
  "Validate generic SELECTOR without predicting physical availability."
  (unless (and (proper-list-p selector) (zerop (% (length selector) 2)))
    (error "Preview selector must be a plist"))
  (let ((kind (tts--voice-preview-selector-kind selector))
        (engine (plist-get selector :engine-id))
        (language (plist-get selector :language))
        (gender (plist-get selector :gender)))
    (unless (memq kind '(exact engine-default properties))
      (error "Invalid preview selector kind: %S" kind))
    (when (or engine (memq kind '(exact engine-default)))
      (unless (omnivox--preview-valid-id-p engine 128 "\\`[0-9A-Za-z_.-]+\\'")
        (error "Invalid preview engine ID")))
    (when (and (eq kind 'exact)
               (not (omnivox--preview-valid-id-p (plist-get selector :voice-id) 4096)))
      (error "Invalid preview physical voice ID"))
    (when (and language
               (not (omnivox--preview-valid-id-p language 64 "\\`[0-9A-Za-z-]+\\'")))
      (error "Invalid preview selector language"))
    (when (and gender
               (not (member (downcase (format "%s" gender)) '("female" "male" "neutral"))))
      (error "Invalid preview selector gender"))))

(defun omnivox--preview-policy-json (policy disabled)
  "Validate and encode complete generic POLICY and DISABLED engine IDs."
  (unless (and (proper-list-p policy) (zerop (% (length policy) 2)))
    (error "Complete preview policy must be a plist"))
  (dolist (key '(:preferred-engines :allow-same-language-on-requested-engine
                                    :global-default :fallback-engines))
    (unless (plist-member policy key)
      (error "Complete preview policy requires %s" key)))
  (unless (memq (plist-get policy :allow-same-language-on-requested-engine) '(nil t))
    (error "Complete preview same-language policy must be boolean"))
  (dolist (ids (list (plist-get policy :preferred-engines)
                     (plist-get policy :fallback-engines) disabled))
    (unless (proper-list-p ids) (error "Preview engine order must be a list"))
    (dolist (id ids)
      (unless (omnivox--preview-valid-id-p id 128 "\\`[0-9A-Za-z_.-]+\\'")
        (error "Invalid preview policy engine ID"))))
  (unless (= (length disabled) (length (delete-dups (copy-sequence disabled))))
    (error "Preview disabled engines must not contain duplicates"))
  (when-let* ((selector (plist-get policy :global-default)))
    (omnivox--preview-validate-selector selector))
  (list :preferred_engines (vconcat (plist-get policy :preferred-engines))
        :allow_same_language_on_requested_engine
        (if (plist-get policy :allow-same-language-on-requested-engine) t :false)
        :global_default
        (if (plist-get policy :global-default)
            (omnivox--preview-selector-json (plist-get policy :global-default)) :null)
        :fallback_engines (vconcat (plist-get policy :fallback-engines))))

(defun omnivox--preview-validate-values (entry)
  "Validate normalized settings in ENTRY before either preview mode interrupts."
  (let ((language (plist-get entry :language))
        (offset (plist-get entry :rate-offset))
        (expected (plist-get entry :expected-base-rate)))
    (when (and language
               (not (omnivox--preview-valid-id-p language 64 "\\`[0-9A-Za-z-]+\\'")))
      (error "Invalid complete preview language"))
    (when (and offset
               (not (and (integerp offset) (<= -20 offset 20)
                         (null (plist-get (plist-get entry :acss) :rate)))))
      (error "Preview rate offset must be -20..20 and cannot accompany absolute rate"))
    (when (and expected
               (not (and (numberp expected) (<= 0 expected 2))))
      (error "Comparison base rate must be between zero and two"))
    (dolist (field '(:acss :effects))
      (let ((values (plist-get entry field)))
        (unless (and (proper-list-p values) (zerop (% (length values) 2)))
          (error "Preview %s must be a normalized plist" field))
        (while values
          (let ((key (pop values)) (value (pop values)))
            (unless (memq key (if (eq field :acss)
                                  '(:rate :average-pitch :pitch-range :stress :richness :volume)
                                '(:gain :pan :low-pass :high-pass :reverb :echo :chorus)))
              (error "Unknown preview dimension %s" key))
            (unless (or (null value) (and (numberp value) (= value value)
                                          (< (abs value) 1.0e+INF)))
              (error "Preview %s must be a finite number or nil" key))))))
))

(defun omnivox--preview-physical-result (voice)
  "Normalize one physical VOICE from a complete preview response."
  (when voice
    (unless (and (omnivox--preview-valid-id-p (plist-get voice :engine_id) 128)
                 (omnivox--preview-valid-id-p (plist-get voice :voice_id) 4096))
      (error "Invalid physical identity in preview response"))
    (list :engine-id (plist-get voice :engine_id) :voice-id (plist-get voice :voice_id))))

(defun omnivox--normalize-complete-preview-response (entry response)
  "Normalize complete preview RESPONSE, retaining the submitted ENTRY snapshot."
  (condition-case error-data
      (progn
        (unless (equal (plist-get response :type) "preview_voice_completed")
          (error "%s" (or (plist-get response :message) "Invalid complete preview response")))
        (dolist (key '(:status :realized :realizations :realizations_truncated
                               :degraded_acss :degraded_effects :message :base_rate
                               :effective_disabled_engine_ids))
          (unless (plist-member response key) (error "Preview response omitted %s" key)))
        (unless (and (member (plist-get response :status) '("completed" "cancelled" "failed"))
                     (numberp (plist-get response :base_rate))
                     (<= 0 (plist-get response :base_rate) 2)
                     (proper-list-p (plist-get response :realizations))
                     (<= (length (plist-get response :realizations)) 32)
                     (memq (plist-get response :realizations_truncated) '(nil t))
                     (proper-list-p (plist-get response :effective_disabled_engine_ids)))
          (error "Invalid complete preview terminal metadata"))
        (dolist (engine (plist-get response :effective_disabled_engine_ids))
          (unless (omnivox--preview-valid-id-p engine 128)
            (error "Invalid disabled engine in preview response")))
        (dolist (field '(:degraded_acss :degraded_effects))
          (unless (and (proper-list-p (plist-get response field))
                       (cl-every (lambda (dimension)
                                   (member dimension
                                           (if (eq field :degraded_acss)
                                               '("rate" "average_pitch" "pitch_range" "stress" "richness" "volume")
                                             '("gain" "pan" "low_pass" "high_pass" "reverb" "echo" "chorus"))))
                                 (plist-get response field)))
            (error "Invalid preview degradation metadata")))
        (when (memq nil (plist-get response :realizations))
          (error "Preview accepted-audio identities cannot be null"))
        (unless (or (null (plist-get response :message)) (stringp (plist-get response :message)))
          (error "Invalid preview status message"))
        (let ((degraded (mapcar #'omnivox--preview-dimension-symbol
                                (plist-get response :degraded_acss))))
          (when (and (plist-get entry :rate-offset)
                     (not (zerop (plist-get entry :rate-offset))) (memq 'rate degraded))
            (setq degraded (cons 'rate-offset (delq 'rate degraded))))
          (list :status (intern (plist-get response :status))
                :completion-guarantee 'playback :request-snapshot (copy-tree entry)
                :requested (copy-tree (plist-get entry :selectors))
                :realized (omnivox--preview-physical-result (plist-get response :realized))
                :realizations (mapcar #'omnivox--preview-physical-result
                                      (plist-get response :realizations))
                :realizations-truncated (plist-get response :realizations_truncated)
                :base-rate (plist-get response :base_rate)
                :effective-disabled-engine-ids (copy-sequence (plist-get response :effective_disabled_engine_ids))
                :degraded-acss degraded
                :degraded-effects (mapcar #'omnivox--preview-dimension-symbol
                                          (plist-get response :degraded_effects))
                :message (plist-get response :message))))
    (error (list :status 'failed :completion-guarantee 'playback
                 :request-snapshot (copy-tree entry) :message (error-message-string error-data)))))

(provide 'omnivox-control-codec)

;;; omnivox-control-codec.el ends here
