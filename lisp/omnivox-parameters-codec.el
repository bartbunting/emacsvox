;;; omnivox-parameters-codec.el --- Engine parameter metadata -*- lexical-binding: t; -*-

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
;; Validate inert current-worker catalogues.  IDs remain strings, JSON false
;; remains :false and unknown value types remain readable but not editable.

;;; Code:
(require 'omnivox-choice-codec)

(defun omnivox-parameters--require (condition field)
  "Require CONDITION for catalogue FIELD."
  (unless condition (error "Invalid engine parameter %s" field)))

(defun omnivox-parameters--id (value)
  "Require bounded string identifier VALUE without interning it."
  (omnivox-parameters--require (emacsvox-aural-routing--native-id-p value) "identifier"))

(defun omnivox-parameters--text (value limit)
  "Require nonempty text VALUE within UTF-8 LIMIT, without control characters."
  (omnivox-parameters--require
   (and (stringp value) (> (length value) 0)
        (<= (string-bytes (encode-coding-string value 'utf-8 t)) limit)
        (not (string-match-p "[[:cntrl:]]" value))) "text"))

(defun omnivox-parameters--array (value limit)
  "Require JSON array VALUE with at most LIMIT elements."
  (omnivox-parameters--require (and (vectorp value) (<= (length value) limit)) "array"))

(defun omnivox-parameters--ids (values limit)
  "Validate unique identifier array VALUES within LIMIT."
  (omnivox-parameters--array values limit)
  (let (seen)
    (mapc (lambda (id)
            (omnivox-parameters--id id)
            (omnivox-parameters--require (not (member id seen)) "duplicate identifier")
            (push id seen)) values)))

(defun omnivox-parameters--finite-p (value)
  "Return non-nil for finite JSON number VALUE."
  (and (numberp value) (< -1.0e+INF value 1.0e+INF)))

(defun omnivox-parameters--integer-p (value)
  "Return non-nil for signed 64-bit integer VALUE."
  (and (integerp value) (<= (- (expt 2 63)) value (1- (expt 2 63)))))

(defun omnivox-parameters--boolean (value)
  "Require strict JSON Boolean VALUE, distinct from null."
  (omnivox-parameters--require (memq value '(t :false)) "Boolean"))

(defun omnivox-parameters--revision (value)
  "Require lowercase SHA-256 catalogue revision VALUE."
  (omnivox-parameters--require
   (and (stringp value) (let ((case-fold-search nil))
                         (string-match-p "\\`[0-9a-f]\\{64\\}\\'" value))) "revision"))

(defun omnivox-parameters--identity (identity)
  "Validate schema, profile, digest and runtime ID in IDENTITY."
  (omnivox--choice-object-keys identity '(:schema_id :profile_id :catalogue_revision :runtime_generation))
  (omnivox-parameters--id (plist-get identity :schema_id))
  (omnivox-parameters--id (plist-get identity :profile_id))
  (omnivox-parameters--revision (plist-get identity :catalogue_revision))
  (omnivox--choice-unsigned (plist-get identity :runtime_generation) nil t))

(defun omnivox-parameters--token (token)
  "Require nullable bounded opaque cursor TOKEN."
  (unless (eq token :null)
    (omnivox-parameters--require
     (and (stringp token) (string-match-p "\\`[!-~]\\{1,128\\}\\'" token)) "cursor")))

(defun omnivox-parameters--type (type)
  "Validate descriptor TYPE; return nil for a future, unsupported kind."
  (emacsvox-aural-routing--strict-properties
   type (and (proper-list-p type) (cl-loop for (key _) on type by #'cddr collect key)) '(:kind))
  (omnivox-parameters--id (plist-get type :kind))
  (pcase (plist-get type :kind)
    ((or "integer" "number")
     (omnivox--choice-object-keys type '(:kind :minimum :maximum :step))
     (let ((predicate (if (equal (plist-get type :kind) "integer")
                          #'omnivox-parameters--integer-p #'omnivox-parameters--finite-p)))
       (dolist (key '(:minimum :maximum :step))
         (omnivox-parameters--require (funcall predicate (plist-get type key)) "numeric range")))
     (omnivox-parameters--require
      (and (<= (plist-get type :minimum) (plist-get type :maximum)) (> (plist-get type :step) 0)) "numeric range") t)
    ("boolean" (omnivox--choice-object-keys type '(:kind)) t)
    ("enum"
     (omnivox--choice-object-keys type '(:kind :choices))
     (let ((choices (plist-get type :choices)) ids)
       (omnivox-parameters--array choices 64)
       (omnivox-parameters--require (> (length choices) 0) "enum choices")
       (mapc (lambda (choice)
               (omnivox--choice-object-keys choice '(:value :label))
               (let ((id (plist-get choice :value)))
                 (omnivox-parameters--id id)
                 (omnivox-parameters--require (not (member id ids)) "duplicate enum")
                 (push id ids))
               (omnivox-parameters--text (plist-get choice :label) 128)) choices)) t)))

(defun omnivox-parameters--accepts-p (type value)
  "Return whether TYPE accepts VALUE without imposing a nudge-step grid."
  (pcase (plist-get type :kind)
    ((or "integer" "number")
     (and (if (equal (plist-get type :kind) "integer")
              (omnivox-parameters--integer-p value) (omnivox-parameters--finite-p value))
          (<= (plist-get type :minimum) value (plist-get type :maximum))))
    ("boolean" (memq value '(t :false)))
    ("enum" (cl-find value (plist-get type :choices) :test #'equal :key (lambda (item) (plist-get item :value))))))

(defun omnivox-parameters--descriptor (descriptor voice)
  "Validate DESCRIPTOR, including the physical VOICE needed for readback."
  (omnivox--choice-object-keys descriptor
                              '(:id :label :help :group :order :unit :value_type :scope
                                :adjustable :availability :default :side_effects))
  (dolist (key '(:id :group)) (omnivox-parameters--id (plist-get descriptor key)))
  (omnivox-parameters--text (plist-get descriptor :label) 128)
  (omnivox-parameters--text (plist-get descriptor :help) 1024)
  (omnivox--choice-unsigned (plist-get descriptor :order) (1- (expt 2 32)))
  (unless (eq (plist-get descriptor :unit) :null) (omnivox-parameters--id (plist-get descriptor :unit)))
  (omnivox-parameters--require (member (plist-get descriptor :scope) '("voice" "engine" "startup")) "scope")
  (omnivox-parameters--boolean (plist-get descriptor :adjustable))
  (let* ((availability (plist-get descriptor :availability))
         (default (plist-get descriptor :default))
         (known (omnivox-parameters--type (plist-get descriptor :value_type))))
    (omnivox--choice-object-keys availability '(:status :reason))
    (omnivox-parameters--require
     (member (plist-get availability :status) '("supported" "voice_unavailable" "runtime_unsupported" "not_checked")) "availability")
    (if (equal (plist-get availability :status) "supported")
        (omnivox-parameters--require (eq (plist-get availability :reason) :null) "availability reason")
      (omnivox-parameters--text (plist-get availability :reason) 1024))
    (omnivox--choice-object-keys default '(:source :value :reset_supported))
    (omnivox-parameters--boolean (plist-get default :reset_supported))
    (omnivox-parameters--require
     (member (plist-get default :source) '("unknown" "runtime_readback" "qualified_profile")) "default source")
    (if (equal (plist-get default :source) "unknown")
        (omnivox-parameters--require (eq (plist-get default :value) :null) "unknown default")
      (let ((value (plist-get default :value)))
        (omnivox-parameters--require
         (or (memq value '(t :false))
             (if (integerp value) (omnivox-parameters--integer-p value)
               (omnivox-parameters--finite-p value))
             (emacsvox-aural-routing--native-id-p value)) "default value"))
      (when known
        (omnivox-parameters--require
         (omnivox-parameters--accepts-p (plist-get descriptor :value_type) (plist-get default :value)) "default type")))
    (when (equal (plist-get default :source) "runtime_readback")
      (omnivox-parameters--require (not (eq voice :null)) "voice readback"))
    (when (and (eq (plist-get descriptor :adjustable) t) (equal (plist-get descriptor :scope) "voice"))
      (omnivox-parameters--require (eq (plist-get default :reset_supported) t) "voice reset")))
  (omnivox-parameters--ids (plist-get descriptor :side_effects) 512)
  (omnivox-parameters--require (not (member (plist-get descriptor :id)
                                          (append (plist-get descriptor :side_effects) nil))) "self effect"))

(defun omnivox-parameters--editable-p (descriptor)
  "Return non-nil for a known, qualified per-voice DESCRIPTOR."
  (and (member (plist-get (plist-get descriptor :value_type) :kind) '("integer" "number" "boolean" "enum"))
       (equal (plist-get descriptor :scope) "voice")
       (eq (plist-get descriptor :adjustable) t)
       (equal (plist-get (plist-get descriptor :availability) :status) "supported")
       (eq (plist-get (plist-get descriptor :default) :reset_supported) t)))

(defun omnivox-parameters--page (response engine voice)
  "Validate strict decoded RESPONSE against ENGINE and nullable VOICE."
  (omnivox-parameters--require (<= (string-bytes (json-serialize response)) (* 256 1024)) "page size")
  (omnivox--choice-object-keys response '(:protocol_version :request_id :type :engine_id :result))
  (omnivox-parameters--require
   (and (eql (plist-get response :protocol_version) 1)
        (equal (plist-get response :type) "engine_parameters_v1")
        (equal (plist-get response :engine_id) engine)) "response identity")
  (omnivox--choice-unsigned (plist-get response :request_id) nil t)
  (let ((result (plist-get response :result)))
    (pcase (plist-get result :status)
      ("busy"
       (omnivox--choice-object-keys result '(:status :retry_after_ms))
       (omnivox--choice-unsigned (plist-get result :retry_after_ms) 5000 t))
      ("unavailable"
       (omnivox--choice-object-keys result '(:status :reason :message))
       (omnivox-parameters--require (member (plist-get result :reason)
                                          '("engine_unavailable" "voice_unavailable" "not_described" "unsupported_helper")) "unavailable reason")
       (omnivox-parameters--text (plist-get result :message) 1024))
      ("ready"
       (omnivox--choice-object-keys result '(:status :identity :voice_id :parameters :mappings :next_cursor))
       (omnivox-parameters--identity (plist-get result :identity))
       (omnivox-parameters--require (equal voice (plist-get result :voice_id)) "voice identity")
       (omnivox-parameters--array (plist-get result :parameters) 64)
       (let (ids)
         (mapc (lambda (descriptor)
                 (omnivox-parameters--descriptor descriptor voice)
                 (omnivox-parameters--require (not (member (plist-get descriptor :id) ids)) "duplicate parameter")
                 (push (plist-get descriptor :id) ids)) (plist-get result :parameters)))
       (omnivox-parameters--array (plist-get result :mappings) 512)
       (mapc (lambda (mapping)
               (omnivox--choice-object-keys mapping '(:common_inputs :native_outputs))
               (omnivox-parameters--ids (plist-get mapping :common_inputs) 14)
               (omnivox-parameters--ids (plist-get mapping :native_outputs) 512)
               (omnivox-parameters--require
                (and (> (length (plist-get mapping :common_inputs)) 0)
                     (> (length (plist-get mapping :native_outputs)) 0)
                     (cl-every (lambda (input) (member input '("rate" "rate_offset" "average_pitch" "pitch_range" "stress" "richness" "volume" "gain" "low_pass" "high_pass" "pan" "reverb" "echo" "chorus")))
                               (plist-get mapping :common_inputs))) "mapping")) (plist-get result :mappings))
       (omnivox-parameters--token (plist-get result :next_cursor))
       (omnivox-parameters--require
        (or (eq (plist-get result :next_cursor) :null) (> (length (plist-get result :parameters)) 0)) "empty continuation"))
      (_ (error "Invalid engine parameter status")))
    result))

(provide 'omnivox-parameters-codec)
;;; omnivox-parameters-codec.el ends here
