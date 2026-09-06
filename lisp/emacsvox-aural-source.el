;;; emacsvox-aural-source.el --- Aural source boundary -*- lexical-binding: t; -*-

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

;; Immutable submission context, semantic text properties, source formatting
;; records, and data-only face snapshots captured before speech text enters a
;; scratch buffer.  This module does not compile or queue presentations.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-schemes)

(cl-defstruct
    (emacsvox-aural-source-run
     (:constructor emacsvox-aural--make-source-run))
  "One source formatting run captured inside an aural object."
  start end facts context icon)

(defvar emacsvox-aural-submission-context nil
  "Dynamically bound source context for the current speech submission.")

(defvar emacsvox-aural-submission-facts nil
  "Dynamically bound semantic facts for the current speech submission.")

(defvar emacsvox-aural-submission-module nil
  "Dynamically bound module for the current speech submission.")

(defvar emacsvox-aural-submission-occasion nil
  "Dynamically bound occasion for the current speech submission.")

(defconst emacsvox-aural-submission-lanes
  '(main notification)
  "Supported ownership lanes for complete aural submissions.")

(defvar emacsvox-aural-submission-lane nil
  "Dynamically bound ownership lane for the current aural submission.")

(defconst emacsvox-aural-delivery-policies
  '(ordered replaceable urgent)
  "Supported delivery policies for complete aural submissions.")

(defvar emacsvox-aural-submission-delivery-policy nil
  "Dynamically bound delivery policy for the current aural submission.")

(defvar emacsvox-aural-submission-replacement-key nil
  "Dynamically bound replacement key for the current aural submission.")

(defconst emacsvox-aural-interruption-policies
  '(none lane)
  "Supported onset interruption policies for aural submissions.")

(defvar emacsvox-aural-submission-interruption-policy nil
  "Dynamically bound onset interruption policy for an aural submission.")

(defvar emacsvox-aural-submission-controls-interruption nil
  "Non-nil when the native delivery policy owns speech interruption.

`emacsvox-aural-submit' and `emacsvox-aural-submit-actions' bind this while
their complete transactions are delivered.  Compatibility callers and bare
`tts-speak' calls leave it nil and retain legacy stop-before-speaking
behaviour.")

(defvar-local emacsvox-aural-source-transform-function nil
  "Optional function that transforms source text before aural preparation.

The function receives one nonempty source string and must return a string.
It is intended for mode-specific, presentation-only transformations that must
remain synchronized with the concrete plans frozen by a native submission.")

(defvar emacsvox-aural-source-annotation-functions nil
  "Functions that add presentation properties before source planning.

Each function receives a source string and must return a string.  Annotation
must preserve the visible characters; transformations belong in
`emacsvox-aural-source-transform-function'.")

(defvar emacsvox-aural-ui-interface-buffer)

(defconst emacsvox-aural-facts-property
  'emacsvox-aural-facts
  "Text property holding semantic facts for one formatted text run.")

(defconst emacsvox-aural-positioned-facts-property
  'emacsvox-aural-positioned-facts
  "Text property holding semantic facts anchored inside a formatting run.

Its value is a list of fact plists.  Unlike
`emacsvox-aural-facts-property', this property does not create an object or
speech-run boundary; the planner compiles its presentation at the property's
source position.")

(defconst emacsvox-aural-module-property
  'emacsvox-aural-module
  "Text property overriding the semantic module for one text run.")

(defconst emacsvox-aural-occasion-property
  'emacsvox-aural-occasion
  "Text property overriding presentation occasion for one text run.")

(defconst emacsvox-aural-object-property
  'emacsvox-aural-object
  "Text property explicitly identifying one aural object.

Adjacent text with the same non-nil value belongs to one object even when
run-local semantic or presentation properties change.  Without this property,
the complete submission is one inferred object until semantic facts, module,
occasion, or a new queued icon changes.")

(defconst emacsvox-aural-source-faces-property
  'emacsvox-aural-source-faces
  "Text property holding an authoritative named source-face snapshot.")

(defconst emacsvox-aural-source-invisible-property
  'emacsvox-aural-source-invisible
  "Text property recording effective source invisibility.

The value is non-nil only when `invisible-p' was non-nil in the source buffer.
It lets later TTS cleanup preserve that decision without depending on another
buffer's `buffer-invisibility-spec'.")

(defconst emacsvox-aural--source-visibility-captured-property
  'emacsvox-aural--source-visibility-captured
  "Non-nil on text whose effective visibility was captured, including visible text.")

(defun emacsvox-aural-transform-source-text (text)
  "Apply the current mode-specific source transformation to TEXT."
  (let ((result
         (if emacsvox-aural-source-transform-function
             (funcall emacsvox-aural-source-transform-function text)
           text)))
    (unless (stringp result)
      (error "Aural source transformation returned non-string: %S" result))
    result))

(defun emacsvox-aural-annotate-source-text (text)
  "Apply registered source annotation functions to TEXT in order."
  (let ((result text))
    (dolist (function emacsvox-aural-source-annotation-functions)
      (setq result (funcall function result))
      (unless (stringp result)
        (error "Aural source annotation returned non-string: %S" result)))
    result))

(defun emacsvox-aural-source-text-property (position property &optional object)
  "Return the actual PROPERTY at POSITION in OBJECT.

Unlike `get-text-property', do not resolve `char-property-alias-alist'.
OBJECT defaults to the current buffer and may also be a string."
  (plist-get (text-properties-at position object) property))

(defun emacsvox-aural-capture-context (&optional module occasion)
  "Capture immutable source context for MODULE and OCCASION."
  (let ((context
         (copy-tree
          (emacsvox-aural-current-context
           (or module emacsvox-aural-submission-module)
           (or
            occasion
            emacsvox-aural-submission-occasion
            'continuous)))))
    (when
        (and
         (boundp 'emacsvox-aural-ui-interface-buffer)
         emacsvox-aural-ui-interface-buffer
         (not emacsvox-aural-history-record-interface-presentations))
      (setq
       context
       (plist-put context :history-recording-inhibited t)))
    context))

(defun emacsvox-aural-delivery-policy-for-occasion (occasion)
  "Return the default complete-submission delivery policy for OCCASION.

Navigation replaces an older pending presentation because only the current
location remains useful.  All other occasions retain submission order unless a
caller explicitly requests another policy."
  (if (eq occasion 'navigation) 'replaceable 'ordered))

(defun emacsvox-aural-interruption-policy-for (lane occasion)
  "Return the default onset interruption policy for LANE and OCCASION."
  (if (and (eq lane 'main) (eq occasion 'navigation)) 'lane 'none))

(defun emacsvox-aural--validate-delivery
    (lane policy replacement-key interruption-policy)
  "Validate LANE, delivery POLICY, REPLACEMENT-KEY, and INTERRUPTION-POLICY."
  (unless (memq lane emacsvox-aural-submission-lanes)
    (error "Unsupported aural submission lane: %S" lane))
  (unless (memq policy emacsvox-aural-delivery-policies)
    (error "Unsupported aural delivery policy: %S" policy))
  (when (and (eq policy 'replaceable) (null replacement-key))
    (error "Replaceable aural delivery requires a replacement key"))
  (unless (memq interruption-policy emacsvox-aural-interruption-policies)
    (error "Unsupported aural interruption policy: %S"
           interruption-policy)))

(cl-defun emacsvox-aural-call-with-submission
    (function
     &key facts context module occasion lane delivery-policy replacement-key
     interruption-policy arguments)
  "Call FUNCTION with ARGUMENTS inside one frozen aural submission.

FACTS, CONTEXT, MODULE, and OCCASION describe the source presentation.  LANE
is `main' or `notification' and defaults to `main'.
DELIVERY-POLICY is `ordered', `replaceable', or `urgent'.  Replaceable
submissions with the same REPLACEMENT-KEY supersede one another before
delivery; the default key is `speaker'.  INTERRUPTION-POLICY is `none' or
`lane'; main-lane navigation defaults to `lane'.  An enclosing submission
remains authoritative so nested compatibility helpers cannot replace more
specific presentation or delivery intent."
  (let* ((effective-facts
          (or emacsvox-aural-submission-facts facts))
         (effective-module
          (or emacsvox-aural-submission-module module))
         (effective-occasion
          (or emacsvox-aural-submission-occasion occasion 'continuous))
         (effective-lane
          (or emacsvox-aural-submission-lane lane 'main))
         (effective-delivery-policy
          (or
           emacsvox-aural-submission-delivery-policy
           delivery-policy
           (emacsvox-aural-delivery-policy-for-occasion
            effective-occasion)))
         (effective-replacement-key
          (when (eq effective-delivery-policy 'replaceable)
            (or
             (and
              emacsvox-aural-submission-delivery-policy
              emacsvox-aural-submission-replacement-key)
             replacement-key
             'speaker)))
         (effective-interruption-policy
          (or
           emacsvox-aural-submission-interruption-policy
           interruption-policy
           (emacsvox-aural-interruption-policy-for
            effective-lane effective-occasion)))
         (effective-context
          (or
           emacsvox-aural-submission-context
           context
           (emacsvox-aural-capture-context
            effective-module effective-occasion)))
         (emacsvox-aural-submission-facts effective-facts)
         (emacsvox-aural-submission-context effective-context)
         (emacsvox-aural-submission-module effective-module)
         (emacsvox-aural-submission-occasion effective-occasion)
         (emacsvox-aural-submission-lane effective-lane)
         (emacsvox-aural-submission-delivery-policy
          effective-delivery-policy)
         (emacsvox-aural-submission-replacement-key
          effective-replacement-key)
         (emacsvox-aural-submission-interruption-policy
          effective-interruption-policy))
    (emacsvox-aural--validate-delivery
     effective-lane effective-delivery-policy effective-replacement-key
     effective-interruption-policy)
    (apply function arguments)))

(defun emacsvox-aural-face-names (value)
  "Return ordered named faces explicitly represented by face VALUE.

Anonymous attribute plists contribute only named faces reached through
`:inherit'.  Duplicate names retain their first, strongest position."
  (cl-labels
      ((collect
        (item)
        (cond
         ((and (symbolp item) (facep item)) (list item))
         ((and (stringp item) (facep item))
          (when-let* ((name (intern-soft item)))
            (list name)))
         ((and (proper-list-p item) (keywordp (car item)))
          (collect (plist-get item :inherit)))
         ((proper-list-p item)
          (apply #'append (mapcar #'collect item)))
         (t nil))))
    (delete-dups (collect value))))

(defun emacsvox-aural--source-face-records
    (value source property &optional overlay)
  "Return provenance records for named faces in VALUE.

SOURCE is `overlay' or `text-property', PROPERTY is `face' or
`font-lock-face', and OVERLAY supplies source range and priority metadata."
  (mapcar
   (lambda (face)
     (append
      (list
       :face face
       :source source
       :property property)
      (when overlay
        (list
         :priority (copy-tree (overlay-get overlay 'priority))
         :overlay-start (overlay-start overlay)
         :overlay-end (overlay-end overlay)))))
   (emacsvox-aural-face-names value)))

(defun emacsvox-aural--normalize-source-face-records (records)
  "Deduplicate ordered source-face RECORDS and assign stable order."
  (let (seen result)
    (dolist (record records)
      (let ((face (plist-get record :face)))
        (unless (memq face seen)
          (push face seen)
          (setq
           result
           (append
            result
            (list
             (plist-put
              (copy-tree record) :order (length result))))))))
    result))

(defun emacsvox-aural-capture-source-faces (&optional position buffer)
  "Capture ordered named source faces at POSITION in BUFFER.

Overlay faces are ordered by decreasing Emacs overlay priority, followed by
the explicit `face' and `font-lock-face' text properties.  Within each source,
`face' precedes `font-lock-face'.  Returned provenance is data-only and never
retains an overlay object.  POSITION and BUFFER default to point and the
current buffer."
  (with-current-buffer (or buffer (current-buffer))
    (let ((position (or position (point)))
          records)
      (dolist (overlay (overlays-at position t))
        (dolist (property '(face font-lock-face))
          (when-let* ((value (overlay-get overlay property)))
            (setq
             records
             (append
              records
              (emacsvox-aural--source-face-records
               value 'overlay property overlay))))))
      (dolist (property '(face font-lock-face))
        (when-let* ((value
                     (emacsvox-aural-source-text-property
                      position property)))
          (setq
           records
           (append
            records
            (emacsvox-aural--source-face-records
             value 'text-property property)))))
      (emacsvox-aural--normalize-source-face-records records))))

(defun emacsvox-aural-source-substring (start end &optional buffer)
  "Copy START through END from BUFFER with source presentation snapshots.

This is the source-boundary counterpart of `buffer-substring'.  It preserves
ordinary text properties and annotates the returned string with ordered,
data-only face provenance, effective invisibility, and effective auditory icons
without changing BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (let ((text (buffer-substring start end))
          (position start)
          previous-snapshot)
      (while (< position end)
        (let* ((next (next-char-property-change position end))
               (snapshot
                (emacsvox-aural-capture-source-faces position))
               (frozen-snapshot
                (cond
                 ((null snapshot)
                  (setq previous-snapshot nil))
                 ((equal snapshot previous-snapshot)
                  previous-snapshot)
                 (t
                  (setq previous-snapshot (copy-tree snapshot)))))
               (invisible (get-char-property position 'invisible))
               (effectively-invisible (invisible-p position))
               (icon (get-char-property position 'auditory-icon))
               (properties
                (append
                 (when frozen-snapshot
                   (list
                    emacsvox-aural-source-faces-property
                    frozen-snapshot))
                 (when invisible
                   (list 'invisible (copy-tree invisible)))
                 (list emacsvox-aural--source-visibility-captured-property t
                       emacsvox-aural-source-invisible-property
                       (and effectively-invisible t))
                 (when icon
                   (list 'auditory-icon (copy-tree icon))))))
          (when properties
            (add-text-properties
             (- position start) (- next start)
             properties
             text))
          (setq position next)))
      text)))

(defun emacsvox-aural--string-face-snapshot (text position)
  "Return authoritative source-face records for TEXT at POSITION."
  (or
   (copy-tree
    (get-text-property
     position emacsvox-aural-source-faces-property text))
   (let (records)
     (dolist (property '(face font-lock-face))
       (when-let* ((value
                    (emacsvox-aural-source-text-property
                     position property text)))
         (setq
          records
          (append
           records
           (emacsvox-aural--source-face-records
            value 'text-property property)))))
     (emacsvox-aural--normalize-source-face-records records))))

(defun emacsvox-aural--source-face-names (snapshot)
  "Return ordered names from source-face SNAPSHOT."
  (mapcar
   (lambda (record) (plist-get record :face))
   snapshot))

(defun emacsvox-aural--source-face-summary (snapshot)
  "Return the strongest source identifier represented by SNAPSHOT."
  (when-let* ((record (car snapshot))
              (source (plist-get record :source))
              (property (plist-get record :property)))
    (if (eq source 'overlay)
        (intern (format "overlay-%s" property))
      property)))

(provide 'emacsvox-aural-source)

;;; emacsvox-aural-source.el ends here
