;;; omnivox-inventory.el --- Omnivox inventory and capabilities  -*- lexical-binding: t; -*-

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

;; Normalize observed engine and voice inventories for the generic voice API.
;; Read capability and process snapshots without requesting or applying changes.
;; The voice adapter owns negotiation, response handling and cached observations.

;;; Code:

(require 'cl-lib)
(require 'omnivox-control-codec)

(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))

(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar omnivox-control-capabilities)
(defvar omnivox-engine-inventory)
(defvar omnivox-engine-inventory-time)
(defvar omnivox--control-inventory-property)

(defun omnivox--status-value (record fallback)
  "Return status string from RECORD, or FALLBACK."
  (let ((status (and (listp record) (plist-get record :status))))
    (if (stringp status) status fallback)))

(defun omnivox--status-reason (record)
  "Return the optional reason from availability or health RECORD."
  (and (listp record) (plist-get record :reason)))

(defun omnivox--control-feature-p (feature)
  "Return non-nil when the main Omnivox process advertised FEATURE."
  (and omnivox-control-capabilities
       (member feature (plist-get omnivox-control-capabilities :features))))

(defun omnivox--inventory-process-agreement ()
  "Describe agreement between distinct live Omnivox speech processes."
  (let ((processes
         (cl-remove-if-not
          #'process-live-p
          (delete-dups (list tts-speaker-process tts-notify-process)))))
    (cond
     ((< (length processes) 2) "single-process")
     ((cl-every
       (lambda (process)
         (process-get process omnivox--control-inventory-property))
       processes)
      (let ((signatures
             (mapcar
              (lambda (process)
                (let ((inventory
                       (process-get
                        process omnivox--control-inventory-property)))
                  (list
                   (plist-get inventory :inventory_generation)
                   (plist-get inventory :preferred_engine_id)
                   (plist-get inventory :routing_policy))))
              processes)))
        (if (cl-every (lambda (signature)
                        (equal signature (car signatures)))
                      (cdr signatures))
            "agree"
          "differ")))
     (t "pending"))))

(defun omnivox--inventory-voice (engine-id voice)
  "Normalize Omnivox VOICE belonging to ENGINE-ID."
  (let ((id (plist-get voice :id)))
    (list
     :engine-id (or (plist-get id :engine_id) engine-id)
     :voice-id (plist-get id :voice_id)
     :display-name (plist-get voice :display_name)
     :language (plist-get voice :language)
     :gender (plist-get voice :gender)
     :quality (plist-get voice :quality)
     :availability
     (omnivox--status-value (plist-get voice :availability) "unknown")
     :availability-reason
     (omnivox--status-reason (plist-get voice :availability)))))

(defun omnivox--inventory-runtime (engine-id)
  "Return live runtime status for ENGINE-ID from the main inventory."
  (cl-find-if
   (lambda (status)
     (equal engine-id (plist-get status :engine_id)))
   (append (plist-get omnivox-engine-inventory :engine_runtime) nil)))

(defun omnivox--inventory-engine
    (engine &optional inventory-kind runtime-status)
  "Normalize one engine descriptor and optional RUNTIME-STATUS."
  (let* ((engine-id (plist-get engine :id))
         (capabilities (plist-get engine :capabilities))
         (acss (plist-get capabilities :acss))
         (markers (plist-get capabilities :markers)))
    (list
     :engine-id engine-id
     :display-name (plist-get engine :display_name)
     :version (plist-get engine :version)
     :availability
     (omnivox--status-value (plist-get engine :availability) "unknown")
     :availability-reason
     (omnivox--status-reason (plist-get engine :availability))
     :health (omnivox--status-value (plist-get engine :health) "unknown")
     :health-reason (omnivox--status-reason (plist-get engine :health))
     :circuit (or (plist-get runtime-status :circuit) "unknown")
     :last-failure (plist-get runtime-status :last_failure)
     :cooldown-remaining-ms
     (plist-get runtime-status :cooldown_remaining_ms)
     :disabled-by-policy
     (and (plist-get runtime-status :disabled_by_policy) t)
     :default-voice-id (plist-get engine :default_voice_id)
     :inventory-kind (or inventory-kind "live")
     :audio-output (plist-get capabilities :audio_output)
     :marker-support
     (delq
      nil
      (mapcar
       (lambda (entry) (and (plist-get markers (car entry)) (cdr entry)))
       '((:word . word) (:sentence . sentence) (:phoneme . phoneme)
         (:native_index . native-index))))
     :anchor-support
     (cond
      ((plist-get markers :native_index) "exact/native-index")
      ((plist-get markers :word) "word-boundary")
      (t "none"))
     :acss-dimensions
     (delq
      nil
      (mapcar
       (lambda (entry) (and (plist-get acss (car entry)) (cdr entry)))
       '((:rate . rate) (:average_pitch . average-pitch)
         (:pitch_range . pitch-range) (:stress . stress)
         (:richness . richness) (:volume . volume))))
     :post-synthesis-dimensions
     (copy-sequence (plist-get capabilities :post_synthesis_dimensions))
     :preview-support
     (if (omnivox--control-feature-p "exact_voice_preview")
         "exact"
       "logical-route")
     :routing-policy-support
     (if (omnivox--control-feature-p "runtime_routing_policy")
         "runtime"
       "unsupported")
     :capabilities (copy-tree capabilities)
     :espeak-variants
     (when (omnivox--control-feature-p "espeak_variants_v1")
       (mapcar (lambda (variant)
                 (list :id (plist-get variant :id)
                       :display-name (plist-get variant :display_name)))
               (append (plist-get engine :espeak_variants) nil)))
     :voices
     (mapcar
      (lambda (voice) (omnivox--inventory-voice engine-id voice))
      (append (plist-get engine :voices) nil)))))

(defun omnivox-voice-inventory ()
  "Return the normalized live Omnivox engine and voice inventory."
  (if (not omnivox-engine-inventory)
      (list
       :adapter "omnivox" :source "live" :status "pending"
       :generation nil :received-at nil :stale nil
       :preferred-engine-id nil
       :preferred-engine-order nil
       :fallback-engine-order nil
       :disabled-engine-ids nil
       :process-agreement (omnivox--inventory-process-agreement)
       :preview-support "pending"
       :complete-preview-support "pending"
       :routing-policy-support "pending"
       :engines nil)
    (let* ((live (process-live-p tts-speaker-process))
           (received omnivox-engine-inventory-time)
           (age (and received (float-time (time-subtract nil received))))
           (registration (plist-get omnivox-engine-inventory :routing_policy))
           (policy (plist-get registration :policy)))
      (list
       :adapter "omnivox"
       :source (if live "live" "cached")
       :status "available"
       :generation
       (plist-get omnivox-engine-inventory :inventory_generation)
       :received-at received
       :age-seconds age
       :stale (not live)
       :preferred-engine-id
       (plist-get omnivox-engine-inventory :preferred_engine_id)
       :routing-policy-generation
       (plist-get registration :routing_policy_generation)
       :preferred-engine-order
       (append (plist-get policy :preferred_engine_ids) nil)
       :fallback-engine-order
       (append (plist-get policy :fallback_engine_ids) nil)
       :disabled-engine-ids
       (append (plist-get policy :disabled_engine_ids) nil)
       :process-agreement (omnivox--inventory-process-agreement)
       :preview-support
       (if (omnivox--control-feature-p "exact_voice_preview")
           "exact"
         "logical-route")
       :complete-preview-support
       (if (and live (omnivox--process-supports-p tts-speaker-process "voice_chain_preview_v1"))
           "supported" "unsupported")
       :routing-policy-support
       (if (omnivox--control-feature-p "runtime_routing_policy")
           "runtime"
         "unsupported")
       :engines
       (mapcar
        (lambda (engine)
          (omnivox--inventory-engine
           engine (if live "live" "cached")
           (omnivox--inventory-runtime (plist-get engine :id))))
        (append (plist-get omnivox-engine-inventory :engines) nil))))))

(defun omnivox--discovered-acss-dimensions ()
  "Return the union of normalized ACSS dimensions advertised by Omnivox."
  (let ((mapping
         '((:rate . rate)
           (:average_pitch . average-pitch)
           (:pitch_range . pitch-range)
           (:stress . stress)
           (:richness . richness)
           (:volume . volume)))
        dimensions)
    (dolist (engine (append (plist-get omnivox-engine-inventory :engines) nil))
      (let ((acss
             (plist-get (plist-get engine :capabilities) :acss)))
        (dolist (entry mapping)
          (when (plist-get acss (car entry))
            (push (cdr entry) dimensions)))))
    (sort (delete-dups dimensions)
          (lambda (left right)
            (string-lessp (symbol-name left) (symbol-name right))))))

(defun omnivox--discovered-post-synthesis-dimensions ()
  "Return normalized post-synthesis dimensions advertised by Omnivox."
  (let (dimensions)
    (dolist (engine (append (plist-get omnivox-engine-inventory :engines) nil))
      (dolist
          (dimension
           (append
            (plist-get (plist-get engine :capabilities)
                       :post_synthesis_dimensions)
            nil))
        (when dimension
          (push (omnivox--preview-dimension-symbol dimension) dimensions))))
    (sort (delete-dups dimensions)
          (lambda (left right)
            (string-lessp (symbol-name left) (symbol-name right))))))

(defun omnivox-voice-capabilities ()
  "Return discovered ACSS and routed-family capabilities for Omnivox."
  (let ((dimensions
         (remove 'rate (omnivox--discovered-acss-dimensions)))
        (effects (omnivox--discovered-post-synthesis-dimensions)))
    (when (and
           (omnivox--control-feature-p "relative_rate_v1")
           (memq 'rate (omnivox--discovered-acss-dimensions)))
      (push 'rate-offset dimensions))
    (list
     :adapter 'omnivox
     :source (if omnivox-engine-inventory 'discovered 'pending)
     :language-selection 'logical-voices
     :family-selection 'routed
     :families nil
     :generic-families '(male female child)
     :dimensions dimensions
     :post-synthesis-dimensions effects
     :parameters
     (mapcar
      (lambda (dimension)
        (if (eq dimension 'rate-offset)
            (list dimension :type 'integer :minimum -20 :maximum 20 :default 0)
          (list dimension :type 'integer :minimum 0 :maximum 9 :default 5)))
      dimensions))))

(provide 'omnivox-inventory)

;;; omnivox-inventory.el ends here
