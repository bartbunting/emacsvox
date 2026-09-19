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

(provide 'omnivox-native-codec)
;;; omnivox-native-codec.el ends here
