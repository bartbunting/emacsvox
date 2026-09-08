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

(provide 'omnivox-choice-codec)
;;; omnivox-choice-codec.el ends here
