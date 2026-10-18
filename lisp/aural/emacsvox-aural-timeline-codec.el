;;; emacsvox-aural-timeline-codec.el --- Structured timeline wire data -*- lexical-binding: t; -*-

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

;; Validate structured speech timelines, map UTF-8 action offsets, and produce
;; bounded direct or multipart wire frames.  This module handles data only.
;; The transport retains plan construction, queue admission and delivery state.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'omnivox-choice-codec)

(defvar emacsvox-aural--isolated-letter nil
  "Non-nil while delivering one negotiated palette-aware character.")

(defconst emacsvox-aural--structured-timeline-version 3
  "Structured presentation timeline version emitted by Emacsvox.")

(defconst emacsvox-aural--timeline-frame-max-bytes (* 256 1024)
  "Maximum decoded JSON bytes in one direct timeline transport frame.")

(defconst emacsvox-aural--timeline-aggregate-max-bytes (* 16 1024 1024)
  "Maximum decoded JSON bytes in one logical multipart timeline.")

(defconst emacsvox-aural--timeline-max-parts 64
  "Maximum number of transport fragments in one logical timeline.")

(defconst emacsvox-aural--timeline-encoded-fragment-max-bytes
  (* 4 (/ (+ emacsvox-aural--timeline-frame-max-bytes 2) 3))
  "Maximum Base64 bytes carried by one multipart transport fragment.")

(defconst emacsvox-aural--timeline-id-max-bytes 128
  "Maximum UTF-8 size of one timeline identifier.")

(defconst emacsvox-aural--timeline-replacement-key-max-bytes 128
  "Maximum UTF-8 size of one timeline replacement key.")

(defconst emacsvox-aural--timeline-resource-path-max-bytes 4096
  "Maximum UTF-8 size of one timeline audio-resource path.")

(defconst emacsvox-aural--timeline-max-spans (* 4096 64)
  "Maximum speech spans in one logical V3 timeline.")

(defconst emacsvox-aural--timeline-max-actions 4096
  "Maximum non-speech actions in one complete V3 timeline.")

(defconst emacsvox-aural--timeline-max-actions-per-speech-window 512
  "Maximum actions in one prepared Omnivox speech window.")

(defconst emacsvox-aural--timeline-speech-window-words 15
  "Maximum words synthesized in one prepared Omnivox speech window.")

(defun emacsvox-aural--timeline-validate-id (value kind)
  "Validate timeline identifier VALUE described by KIND."
  (unless
      (and
       (stringp value)
       (not (string-empty-p value))
       (<= (string-bytes value) emacsvox-aural--timeline-id-max-bytes))
    (emacsvox-aural--transport-error
     "%s must contain 1 to %d UTF-8 bytes"
     kind emacsvox-aural--timeline-id-max-bytes)))

(defun emacsvox-aural--timeline-source-word-spans (text)
  "Return source word spans in TEXT, treating legacy separators as whitespace.

Omnivox punctuation expansion and split-caps can subdivide these words but do
not join them, so every prepared 15-word window fits within one corresponding
source-word window."
  (let ((separator "\\(?:[[:space:]]+\\|\\[\\*\\]\\)")
        (position 0)
        spans)
    (while (string-match separator text position)
      (when (< position (match-beginning 0))
        (push (cons position (match-beginning 0)) spans))
      (setq position (match-end 0)))
    (when (< position (length text))
      (push (cons position (length text)) spans))
    (vconcat (nreverse spans))))

(defun emacsvox-aural--timeline-source-word-index
    (spans position affinity)
  "Locate POSITION with AFFINITY in source word SPANS.

This mirrors Omnivox chunk affinity conservatively: before positions select
the next source word at a boundary, and after positions select the previous
source word."
  (let ((low 0)
        (high (length spans)))
    (unless (> high 0)
      (emacsvox-aural--transport-error
       "Cannot locate a timeline action in speech with no source words"))
    (cond
     ((equal affinity "before")
      (while (< low high)
        (let ((middle (/ (+ low high) 2)))
          (if (> (cdr (aref spans middle)) position)
              (setq high middle)
            (setq low (1+ middle)))))
      (min low (1- (length spans))))
     ((equal affinity "after")
      (while (< low high)
        (let ((middle (/ (+ low high) 2)))
          (if (< (car (aref spans middle)) position)
              (setq low (1+ middle))
            (setq high middle))))
      (max 0 (1- low)))
     (t
      (emacsvox-aural--transport-error
       "Structured action has invalid affinity %S" affinity)))))

(defun emacsvox-aural--validate-span-action-windows
    (span-id text actions offset-positions)
  "Validate ACTIONS against bounded speech windows in span SPAN-ID.

TEXT is the source speech and OFFSET-POSITIONS maps validated UTF-8 offsets to
character positions.  The source-side check is conservative; Omnivox repeats
the authoritative check after punctuation and split-cap preprocessing."
  (when
      (> (length actions)
         emacsvox-aural--timeline-max-actions-per-speech-window)
    (let* ((word-spans (emacsvox-aural--timeline-source-word-spans text))
           (word-count (length word-spans)))
      (if (zerop word-count)
          (emacsvox-aural--transport-error
           "Structured timeline span %S contains %d actions in one speech window; limit is %d"
           span-id (length actions)
           emacsvox-aural--timeline-max-actions-per-speech-window)
        (let ((counts (make-vector word-count 0))
              (window-total 0))
          (dolist (action actions)
            (let* ((wire-position (plist-get action :position))
                   (kind (plist-get wire-position :position))
                   (affinity (plist-get wire-position :affinity))
                   (position
                    (cond
                     ((equal kind "text_offset")
                      (gethash
                       (plist-get wire-position :utf8_offset)
                       offset-positions))
                     ((equal kind "span_boundary")
                      (if (equal affinity "before") 0 (length text)))
                     (t
                      (emacsvox-aural--transport-error
                       "Structured action has invalid position %S" kind))))
                   (word-index
                    (emacsvox-aural--timeline-source-word-index
                     word-spans position affinity)))
              (aset counts word-index (1+ (aref counts word-index)))))
          (dotimes (word-index word-count)
            (cl-incf window-total (aref counts word-index))
            (when
                (>= word-index emacsvox-aural--timeline-speech-window-words)
              (cl-decf
               window-total
               (aref
                counts
                (- word-index emacsvox-aural--timeline-speech-window-words))))
            (when
                (> window-total
                   emacsvox-aural--timeline-max-actions-per-speech-window)
              (emacsvox-aural--transport-error
               "Structured timeline span %S contains %d actions in one speech window; limit is %d"
               span-id window-total
               emacsvox-aural--timeline-max-actions-per-speech-window))))))))

(defun emacsvox-aural--validate-structured-timeline (envelope)
  "Validate a version-3 through version-7 ENVELOPE before transport."
  (unless (memq (plist-get envelope :protocol_version) '(3 4 5 6 7))
    (emacsvox-aural--transport-error
     "Structured delivery requires timeline protocol versions 3 through 7"))
  (when (memq (plist-get envelope :protocol_version) '(4 5 6 7))
    (omnivox--choice-object-keys
     envelope (append '(:protocol_version :generation :dispatch_id :registry_generation :delivery_policy :spans :actions)
                      (when (equal (plist-get envelope :delivery_policy) "replaceable") '(:replacement_key))))
    (unless (member (plist-get envelope :delivery_policy) '("ordered" "urgent" "replaceable"))
      (emacsvox-aural--transport-error "Invalid layered delivery policy"))
    (when (equal (plist-get envelope :delivery_policy) "replaceable")
      (omnivox--choice-string (plist-get envelope :replacement_key)
                              emacsvox-aural--timeline-replacement-key-max-bytes)))
  (dolist (field (append '(:generation :dispatch_id)
                         (when (memq (plist-get envelope :protocol_version) '(4 5 6 7)) '(:registry_generation))))
    (unless
        (let ((value (plist-get envelope field)))
          (and (integerp value) (> value 0)
               (or (not (memq (plist-get envelope :protocol_version) '(4 5 6 7)))
                   (<= value (1- (expt 2 64))))))
      (emacsvox-aural--transport-error
       "Structured timeline %S must be a positive integer" field)))
  (let* ((spans (append (plist-get envelope :spans) nil))
         (actions (append (plist-get envelope :actions) nil))
         (span-texts (make-hash-table :test #'eql))
         (span-offsets (make-hash-table :test #'eql))
         (span-offset-positions (make-hash-table :test #'eql))
         (span-actions (make-hash-table :test #'eql))
         (action-ids (make-hash-table :test #'equal)))
    (unless
        (and
         spans
         (<= (length spans) emacsvox-aural--timeline-max-spans))
      (emacsvox-aural--transport-error
       "Structured timeline must contain 1 to %d speech spans"
       emacsvox-aural--timeline-max-spans))
    (when (> (length actions) emacsvox-aural--timeline-max-actions)
      (emacsvox-aural--transport-error
       "Structured timeline exceeds %d actions"
       emacsvox-aural--timeline-max-actions))
    (dolist (wrapper spans)
      (let* ((v4 (memq (plist-get envelope :protocol_version) '(4 5 6 7)))
             (span (if v4 (plist-get wrapper :span) wrapper)))
        (when v4
          (omnivox--choice-object-keys wrapper '(:mode :span))
          (unless (member (plist-get wrapper :mode)
                          (if (memq (plist-get envelope :protocol_version) '(5 6 7))
                              '("legacy" "layered" "engine_layered") '("legacy" "layered")))
            (emacsvox-aural--transport-error "Unknown layered span mode"))
          (when (member (plist-get wrapper :mode) '("layered" "engine_layered"))
            (omnivox--choice-object-keys span '(:id :text :logical_voice_id :context :placement))
            (omnivox--choice-string (plist-get span :logical_voice_id) 128)
            (omnivox--choice-validate-wire-patch (plist-get span :context))
            (omnivox--choice-object-keys (plist-get span :placement) '(:pan))
            (let ((pan (plist-get (plist-get span :placement) :pan)))
              (unless (or (eq pan :null) (and (numberp pan) (<= 0 pan 1)))
                (emacsvox-aural--transport-error "Invalid layered span placement")))))
        (let ((id (plist-get span :id))
              (text (plist-get span :text))
              (logical-voice (plist-get span :logical_voice_id))
              (effects (plist-get span :effects)))
          (unless (and (integerp id) (> id 0) (not (gethash id span-texts)))
            (emacsvox-aural--transport-error
             "Structured timeline has an invalid or duplicate span ID: %S" id))
          (unless (and (stringp text) (not (string-empty-p text)))
            (emacsvox-aural--transport-error
             "Structured timeline span %S has no speech text" id))
          (when (and logical-voice (not (eq logical-voice :null)))
            (emacsvox-aural--timeline-validate-id
             logical-voice "Logical voice ID"))
          (when (equal (plist-get effects :mode) "replace")
            (emacsvox-aural--timeline-validate-id
             (plist-get effects :state_id) "Effect state ID"))
          (when v4 (omnivox--choice-unsigned id nil t))
          (puthash id text span-texts))))
    (dolist (action actions)
      (let* ((id (plist-get action :id))
             (position (plist-get action :position))
             (span-id (plist-get position :span_id))
             (span-text (gethash span-id span-texts))
             (type (plist-get action :type)))
        (emacsvox-aural--timeline-validate-id id "Action ID")
        (when (gethash id action-ids)
          (emacsvox-aural--transport-error
           "Structured timeline has duplicate action ID %S" id))
        (puthash id t action-ids)
        (unless span-text
          (emacsvox-aural--transport-error
           "Structured action %S references unknown span %S" id span-id))
        (puthash
         span-id (cons action (gethash span-id span-actions)) span-actions)
        (when (equal (plist-get position :position) "text_offset")
          (puthash
           span-id
           (cons
            (plist-get position :utf8_offset)
            (gethash span-id span-offsets))
           span-offsets))
        (when (equal type "audio")
          (let ((path (plist-get action :path)))
            (unless
                (and
                 (stringp path)
                 (not (string-empty-p path))
                 (<=
                  (string-bytes path)
                  emacsvox-aural--timeline-resource-path-max-bytes))
              (emacsvox-aural--transport-error
               "Audio action %S path must contain 1 to %d UTF-8 bytes"
               id emacsvox-aural--timeline-resource-path-max-bytes))))))
    (maphash
     (lambda (span-id offsets)
       (puthash
        span-id
        (emacsvox-aural--utf8-offset-position-table
         (gethash span-id span-texts) offsets)
        span-offset-positions))
     span-offsets)
    (maphash
     (lambda (span-id actions)
       (emacsvox-aural--validate-span-action-windows
        span-id
        (gethash span-id span-texts)
        actions
        (or
         (gethash span-id span-offset-positions)
         (make-hash-table :test #'eql))))
     span-actions))
  envelope)

(defun emacsvox-aural--structured-timeline-payload (envelope)
  "Return ENVELOPE as bounded UTF-8 JSON and Base64 payload data."
  (let* ((json (json-serialize envelope))
         (payload (encode-coding-string json 'utf-8 t))
         (payload-bytes (string-bytes payload)))
    (when (> payload-bytes emacsvox-aural--timeline-aggregate-max-bytes)
      (emacsvox-aural--transport-error
       "Structured aural presentation contains %d JSON bytes; aggregate limit is %d"
       payload-bytes emacsvox-aural--timeline-aggregate-max-bytes))
    (list payload-bytes (base64-encode-string payload t))))

(defun emacsvox-aural--encode-structured-timeline (envelope)
  "Encode structured timeline ENVELOPE as bounded Base64 JSON."
  (cadr (emacsvox-aural--structured-timeline-payload envelope)))

(defun emacsvox-aural--frame-structured-timeline (envelope)
  "Return complete bounded protocol commands carrying ENVELOPE."
  (emacsvox-aural--validate-structured-timeline envelope)
  (pcase-let* ((`(,payload-bytes ,encoded)
                (emacsvox-aural--structured-timeline-payload envelope))
               (generation (plist-get envelope :generation))
               (dispatch-id (plist-get envelope :dispatch_id)))
    (if emacsvox-aural--isolated-letter
        (let* ((spans (plist-get envelope :spans))
               (span (and (= (length spans) 1) (aref spans 0))))
          (unless (and (memq (plist-get envelope :protocol_version) '(4 5 6 7))
                       (member (plist-get span :mode) '("layered" "engine_layered"))
                       (= (length (plist-get (plist-get span :span) :text)) 1)
                       (zerop (length (plist-get envelope :actions)))
                       (equal (plist-get envelope :delivery_policy) "ordered")
                       (null (plist-get envelope :replacement_key))
                       (<= payload-bytes emacsvox-aural--timeline-frame-max-bytes))
            (error "Palette character could not be represented faithfully"))
          (list (format "emacsvox_letter {%s}\n" encoded)))
      (if (<= payload-bytes emacsvox-aural--timeline-frame-max-bytes)
          (list (format "emacsvox_timeline {%s}\n" encoded))
        (let* ((fragment-bytes
                emacsvox-aural--timeline-encoded-fragment-max-bytes)
               (part-count (/ (+ (length encoded) fragment-bytes -1)
                              fragment-bytes)))
          (when (> part-count emacsvox-aural--timeline-max-parts)
            (emacsvox-aural--transport-error
             "Structured aural presentation needs %d transport parts; limit is %d"
             part-count emacsvox-aural--timeline-max-parts))
          (cl-loop
           for part-index from 0 below part-count
           for start = (* part-index fragment-bytes)
           for end = (min (length encoded) (+ start fragment-bytes))
           collect
           (format
            "emacsvox_timeline_part %d %d %d %d %d %d %s\n"
            (plist-get envelope :protocol_version)
            generation dispatch-id part-index part-count payload-bytes
            (substring encoded start end))))))))

(defun emacsvox-aural--utf8-offset-position-table (text offsets)
  "Map UTF-8 byte OFFSETS to character positions in TEXT with one scan."
  (let* ((utf8 (encode-coding-string text 'utf-8 t))
         (byte-length (length utf8))
         (requested (make-hash-table :test #'eql))
         (positions (make-hash-table :test #'eql))
         (remaining 0))
    (dolist (offset offsets)
      (unless
          (and (integerp offset) (>= offset 0) (<= offset byte-length))
        (emacsvox-aural--transport-error
         "Invalid positioned action offset %S for %S" offset text))
      (unless (gethash offset requested)
        (puthash offset t requested)
        (cl-incf remaining)))
    (let ((byte-position 0)
          (character-position 0))
      (cl-labels
          ((record-position
            ()
            (when (gethash byte-position requested)
              (puthash byte-position character-position positions)
              (remhash byte-position requested)
              (cl-decf remaining))))
        (record-position)
        (while (and (> remaining 0) (< byte-position byte-length))
          (cl-incf byte-position)
          (while
              (and
               (< byte-position byte-length)
               (= (logand (aref utf8 byte-position) #xc0) #x80))
            (cl-incf byte-position))
          (cl-incf character-position)
          (record-position))))
    (when (> remaining 0)
      (let (invalid-offset)
        (maphash
         (lambda (offset _present)
           (unless invalid-offset (setq invalid-offset offset)))
         requested)
        (emacsvox-aural--transport-error
         "Positioned action offset %S splits a UTF-8 character in %S"
         invalid-offset text)))
    positions))

(provide 'emacsvox-aural-timeline-codec)

;;; emacsvox-aural-timeline-codec.el ends here
