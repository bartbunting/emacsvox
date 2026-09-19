;;; omnivox-native-codec.el --- Native voice wire values -*- lexical-binding: t; -*-

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
;; Versioned native choice records and qualified application evidence.  Native
;; parameter IDs stay strings; storage false becomes JSON false, never null.
;; Private previews require native execution for the actual selected choice.
;;; Code:
(require 'omnivox-parameters-codec)

(defun omnivox--native-choice-records-json (choices)
  "Convert raw CHOICES to native-aware wire records with required nulls."
  (vconcat
   (mapcar
    (lambda (choice)
      (let* ((native (plist-get choice :native))
             (common (copy-tree choice))
             (parameters (make-hash-table :test #'equal)))
        (cl-remf common :native)
        (dolist (parameter (plist-get native :parameters))
          (let ((operation (cdr parameter)))
            (puthash (copy-sequence (car parameter))
                     (if (eq (plist-get operation :op) 'default) (list :op "default")
                       (list :op "set" :value (if (null (plist-get operation :value))
                                                 :false (plist-get operation :value))))
                     parameters)))
        (append (aref (omnivox--choice-records-json (list common)) 0)
                (list :native
                      (if native
                          (list :engine_id (plist-get native :engine-id)
                                :schema_id (plist-get native :schema-id) :parameters parameters)
                        :null)))))
    (emacsvox-aural-routing--validate-choices choices nil t))))

(defun omnivox--native-application (application)
  "Validate bounded native APPLICATION evidence, preserving its qualification."
  (omnivox--choice-object-keys application '(:status :plan_id :identity :masked_parameters :reason))
  (omnivox-parameters--ids (plist-get application :masked_parameters) 64)
  (unless (eq (plist-get application :identity) :null)
    (omnivox-parameters--identity (plist-get application :identity)))
  (pcase (plist-get application :status)
    ("applied"
     (omnivox-parameters--id (plist-get application :plan_id))
     (omnivox-parameters--require (not (eq (plist-get application :identity) :null)) "application identity")
     (omnivox-parameters--require (eq (plist-get application :reason) :null) "application reason"))
    ("common_only"
     (omnivox-parameters--require
      (and (eq (plist-get application :plan_id) :null)
           (zerop (length (plist-get application :masked_parameters)))) "common-only application")
     (omnivox-parameters--text (plist-get application :reason) 1024))
    (_ (error "Unknown native application status")))
  application)

(defun omnivox--native-audio-identity (identity &optional accepted)
  "Validate native-aware audio IDENTITY, optionally an ACCEPTED record."
  (omnivox--choice-object-keys
   identity (append '(:choice_id :reason :realized :degraded_acss :degraded_effects :native_application)
                    (when accepted '(:playback_started))))
  (let ((common (copy-sequence identity)))
    (cl-remf common :native_application)
    (omnivox--choice-audio-identity common accepted))
  (unless (eq (plist-get identity :native_application) :null)
    (omnivox--native-application (plist-get identity :native_application)))
  (when (> (string-bytes (json-serialize identity)) (* 48 1024))
    (error "Native audio evidence exceeds its size limit"))
  identity)

(defun omnivox--native-application-key (application)
  "Return an order-independent comparison key for validated APPLICATION."
  (unless (eq application :null)
    (let ((identity (plist-get application :identity)))
      (list (plist-get application :status) (plist-get application :plan_id)
            (unless (eq identity :null)
              (mapcar (lambda (key) (plist-get identity key))
                      '(:schema_id :profile_id :catalogue_revision :runtime_generation)))
            (sort (append (plist-get application :masked_parameters) nil) #'string-lessp)
            (plist-get application :reason)))))

(defun omnivox--native-preview-correlate (entry identity)
  "Require IDENTITY to report strict native execution for frozen ENTRY's row."
  (let* ((rows (plist-get (plist-get entry :voice) :choices))
         (row (cl-find (plist-get identity :choice_id) rows :test #'equal
                       :key (lambda (choice) (plist-get choice :id))))
         (native (plist-get row :native))
         (application (plist-get identity :native_application)))
    (if (not native)
        (unless (eq application :null)
          (error "Preview claims native execution for a choice without native settings"))
      (unless (and (listp application)
                   (equal (plist-get application :status) "applied")
                   (equal (plist-get native :engine-id)
                          (plist-get (plist-get identity :realized) :engine_id))
                   (equal (plist-get native :schema-id)
                          (plist-get (plist-get application :identity) :schema_id)))
        (error "Preview did not apply the selected choice's native settings"))
      (mapc (lambda (id)
              (unless (assoc id (plist-get native :parameters))
                (error "Preview masked an absent native parameter")))
            (plist-get application :masked_parameters)))))

(defun omnivox--native-registration-valid-p (response generation content)
  "Validate native registration RESPONSE for frozen GENERATION and CONTENT."
  (condition-case nil
      (let ((expected (make-hash-table :test #'equal))
            (seen (make-hash-table :test #'equal))
            (definitions (plist-get content :definitions)))
        (omnivox--choice-object-keys
         response '(:protocol_version :request_id :type :registry_generation :inventory_generation
                                     :definition_count :unresolved_logical_voice_ids :native_status))
        (omnivox-parameters--require
         (and (eql (plist-get response :protocol_version) 1)
              (equal (plist-get response :type) "logical_voices_registered_v3")
              (eql (plist-get response :registry_generation) generation)
              (eql (plist-get response :definition_count) (length definitions))) "registration identity")
        (dolist (key '(:request_id :registry_generation :inventory_generation))
          (omnivox--choice-unsigned (plist-get response key) nil t))
        (let ((unresolved (plist-get response :unresolved_logical_voice_ids)) ids)
          (mapc (lambda (wrapper) (push (plist-get (plist-get wrapper :definition) :id) ids)) definitions)
          (omnivox-parameters--array unresolved (length definitions))
          (mapc (lambda (id) (omnivox-parameters--require (member id ids) "unresolved voice")) unresolved)
          (omnivox-parameters--require
           (= (length unresolved) (length (delete-dups (append unresolved nil)))) "duplicate unresolved voice"))
        (mapc (lambda (wrapper)
                (when (equal (plist-get wrapper :mode) "engine_layered")
                  (let ((definition (plist-get wrapper :definition)))
                    (mapc (lambda (choice)
                            (unless (eq (plist-get choice :native) :null)
                              (puthash (list (plist-get definition :id) (plist-get choice :id)) t expected)))
                          (plist-get definition :choices))))) definitions)
        (omnivox-parameters--array (plist-get response :native_status) (hash-table-count expected))
        (mapc (lambda (status)
                (omnivox--choice-object-keys status '(:logical_voice_id :choice_id :status :reason))
                (let ((key (list (plist-get status :logical_voice_id) (plist-get status :choice_id))))
                  (omnivox-parameters--require (and (gethash key expected) (not (gethash key seen))) "native status owner")
                  (puthash key t seen))
                (pcase (plist-get status :status)
                  ("supported" (omnivox-parameters--require (eq (plist-get status :reason) :null) "supported reason"))
                  ((or "deferred" "unavailable") (omnivox-parameters--text (plist-get status :reason) 1024))
                  (_ (error "Unknown native support status")))) (plist-get response :native_status))
        (= (hash-table-count expected) (hash-table-count seen)))
    (error nil)))

(defun omnivox--native-validate-marker (event)
  "Validate strict version-4 EVENT without relaxing older marker readers."
  (unless (eql (plist-get event :protocol_version) 4) (error "Expected version-4 marker"))
  (let ((common (copy-sequence event)))
    (when (equal (plist-get event :type) "voice_choice_applied")
      (unless (= 1 (cl-loop for (key _) on event by #'cddr count (eq key :native_application)))
        (error "Native receipt requires one application member"))
      (unless (eq (plist-get event :native_application) :null)
        (omnivox--native-application (plist-get event :native_application)))
      (cl-remf common :native_application))
    (setf (plist-get common :protocol_version) 3)
    (omnivox--choice-validate-marker common))
  event)

(defun omnivox--native-decode-marker (payload)
  "Decode bounded, canonical version-4 marker PAYLOAD, retaining JSON types."
  (when (> (+ (string-bytes payload) (length "__EMACSVOX_MARKER__") 2)
           omnivox--choice-marker-line-limit)
    (error "Native marker exceeds the remote line limit"))
  (let* ((bytes (base64-decode-string payload))
         (text (decode-coding-string bytes 'utf-8 t)))
    (unless (and (equal payload (base64-encode-string bytes t))
                 (equal bytes (encode-coding-string text 'utf-8 t)))
      (error "Invalid native marker encoding"))
    (let ((event (json-parse-string text :object-type 'plist :array-type 'array
                                   :null-object :null :false-object :false)))
      (omnivox--native-validate-marker event)
      (when (and (equal (plist-get event :type) "voice_choice_applied")
                 (> (string-bytes bytes) omnivox--choice-receipt-limit))
        (error "Native receipt exceeds its decoded limit"))
      event)))

(defun omnivox--native-receipt-correlate (row application physical)
  "Correlate ROW's ordinary speech APPLICATION with actual PHYSICAL identity."
  (let ((native (plist-get row :native)))
    (if (not native)
        (unless (eq application :null) (error "Native application has no owning choice"))
      (when (eq application :null) (error "Native choice omitted its application status"))
      (when (equal (plist-get application :status) "applied")
        (unless (and (equal (plist-get native :engine-id) (plist-get physical :engine_id))
                     (equal (plist-get native :schema-id)
                            (plist-get (plist-get application :identity) :schema_id)))
          (error "Native receipt disagrees with its choice"))
        (mapc (lambda (id)
                (unless (assoc id (plist-get native :parameters))
                  (error "Native receipt masked an absent parameter")))
              (plist-get application :masked_parameters))))))

(provide 'omnivox-native-codec)
;;; omnivox-native-codec.el ends here
