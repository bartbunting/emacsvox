;;; emacsvox-aural-rules.el --- Aural Presentation rule engine -*- lexical-binding: t; -*-

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

;; Compile safe versioned presentation rule sets into validated internal
;; structures, match them against semantic facts and source context, and
;; produce an ordered backend-independent render plan.  The retained internal
;; scheme records are not user-selectable configurations.  This module performs
;; no audio or speech I/O.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural)
(require 'emacsvox-aural-spatial)

(define-error
  'emacsvox-aural-rule-error
  "Invalid Emacsvox aural presentation rule")

(defconst emacsvox-aural-scheme-schema-version 1
  "Current declarative aural scheme schema version.")

(defconst emacsvox-aural-origin-ranks
  '((core . 0)
    (module . 1)
    (scheme . 2)
    (fragment . 3)
    (user . 4)
    (session . 5)
    (buffer . 6))
  "Resolver origin layers ordered from weakest to strongest.")

(defconst emacsvox-aural-action-kinds
  '(speech cue pause tone)
  "Action kinds supported by the pure render-plan engine.")

(defconst emacsvox-aural-action-anchors
  '(object run transition)
  "Lifetimes at which ordered aural actions may be emitted.")

(defconst emacsvox-aural-tone-audio-modes
  '(overlay insert)
  "Ways a tone action may share or advance the speech timeline.")

(defconst emacsvox-aural-voice-dimensions
  '(family average-pitch pitch-range stress richness)
  "Device-independent dimensions supported by aural voice styles.")

(defconst emacsvox-aural-voice-rate-dimensions '(rate-offset)
  "Portable relative speech-rate dimensions carried with voice styles.")

(defconst emacsvox-aural-post-synthesis-dimensions
  '(gain low-pass high-pass pan reverb echo chorus)
  "Portable post-synthesis dimensions carried with aural voice styles.")

(defun emacsvox-aural-normalize-post-synthesis-value (dimension value)
  "Normalize portable DIMENSION VALUE for the post-synthesis wire.

Portable values use integer levels zero through nine.  Gain and pan use level
five as their exact neutral point, while retaining zero and nine as the wire
endpoints.  The other dimensions use the ordinary linear mapping."
  (when (numberp value)
    (let ((level (float (max 0 (min 9 value)))))
      (if (memq dimension '(gain pan))
          (if (<= level 5.0)
              (/ level 10.0)
            (+ 0.5 (/ (- level 5.0) 8.0)))
        (/ level 9.0)))))

(defconst emacsvox-aural-rich-voice-dimensions
  (append emacsvox-aural-voice-dimensions
          emacsvox-aural-voice-rate-dimensions
          emacsvox-aural-post-synthesis-dimensions)
  "All dimensions editable as one portable rich voice style.")

(defconst emacsvox-aural--voice-style-keys
  '(:preset :family :average-pitch :pitch-range :stress :richness
    :rate-offset :rate
    :gain :low-pass :high-pass :pan :reverb :echo :chorus)
  "Properties accepted in an explicit aural voice style.

`:rate' is accepted only to load legacy palettes.  New styles use the signed
`:rate-offset' property.")

(defconst emacsvox-aural--selector-keys
  '(:role :event :events :state :states :module :mode :occasion
    :legacy-cue :legacy-face :legacy-personality :requires)
  "Reserved selector keys that are not registered semantic attributes.")

(defconst emacsvox-aural--fact-keys
  '(:role :event :events :state :states :content)
  "Reserved semantic fact keys that are not registered attributes.")

(defconst emacsvox-aural--context-keys
  '(:module :mode :mode-lineage :occasion :legacy-cue
    :face-presentation-enabled :voice-lock-enabled :icons-enabled
    :legacy-face-source :legacy-faces :legacy-face-provenance
    :legacy-personality
    :legacy-source :source-buffer :source-buffer-name :source-position
    :buffer-rules
    :history-recording-inhibited :presentation-transaction-id)
  "Keys accepted in a presentation context plist.")

(cl-defstruct
    (emacsvox-aural-selector
     (:constructor emacsvox-aural--make-selector))
  "A validated selector compiled from declarative rule data."
  role events states attributes required-attributes module mode occasion legacy-cue
  legacy-face legacy-personality semantic-aliases)

(cl-defstruct
    (emacsvox-aural-action
     (:constructor emacsvox-aural--make-action))
  "A validated backend-independent action."
  id kind text text-template template-fields cue pitch duration voice volume space
  anchor source tone audio-mode)

(cl-defstruct
    (emacsvox-aural-phase-operations
     (:constructor emacsvox-aural--make-phase-operations))
  "Ordered operations contributed to a before or after phase."
  suppress
  replace-set-p
  replace
  remove
  prepend
  append
  anchor)

(cl-defstruct
    (emacsvox-aural-content-patch
     (:constructor emacsvox-aural--make-content-patch))
  "Scalar content-style values contributed by one rule."
  suppress
  speak-set-p
  speak
  voice-set-p
  voice
  volume-set-p
  volume
  space-set-p
  space)

(cl-defstruct
    (emacsvox-aural-contribution
     (:constructor emacsvox-aural--make-contribution))
  "Compiled before, content, and after contributions from one rule."
  before content after)

(cl-defstruct
    (emacsvox-aural-rule
     (:constructor emacsvox-aural--make-rule))
  "A validated compiled presentation rule."
  id enabled origin layer-order order selector contribution source)

(cl-defstruct
    (emacsvox-aural-scheme
     (:constructor emacsvox-aural--make-scheme))
  "A validated compiled aural scheme."
  id schema-version summary parent resource-pack voice-palette origin rules
  source)

(cl-defstruct
    (emacsvox-aural-input
     (:constructor emacsvox-aural--make-input))
  "Normalized semantic facts and presentation context."
  role events states attributes content module mode mode-lineage occasion
  face-presentation-enabled voice-lock-enabled
  legacy-cue legacy-face-source legacy-faces legacy-face-provenance
  legacy-personality
  legacy-source source-buffer source-buffer-name facts semantic-aliases)

(cl-defstruct
    (emacsvox-aural-content-style
     (:constructor emacsvox-aural--make-content-style))
  "Resolved scalar styling for object content."
  speak voice volume space provenance voice-provenance)

(cl-defstruct
    (emacsvox-aural-render-plan
     (:constructor emacsvox-aural--make-render-plan))
  "Ordered backend-independent result of rule resolution."
  before content after matched-rules rule-scores semantic-matches)

(defun emacsvox-aural--rule-error (format-string &rest arguments)
  "Signal a rule error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-rule-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural--plist-p (value)
  "Return non-nil when VALUE is a proper keyword plist."
  (and
   (listp value)
   (proper-list-p value)
   (zerop (% (length value) 2))
   (cl-loop
    for (key _) on value by #'cddr
    always (keywordp key))))

(defun emacsvox-aural--require-plist (value label)
  "Return VALUE when it is a plist, otherwise report LABEL."
  (unless (emacsvox-aural--plist-p value)
    (emacsvox-aural--rule-error "%s must be a keyword plist: %S" label value))
  value)

(defun emacsvox-aural--require-symbol (value label)
  "Return VALUE when it is a non-keyword symbol, otherwise report LABEL."
  (unless (and (symbolp value) value (not (keywordp value)))
    (emacsvox-aural--rule-error
     "%s must be a non-keyword symbol: %S" label value))
  value)

(defun emacsvox-aural--acss-p (value)
  "Return non-nil when VALUE is a `voice-setup' ACSS record."
  (and
   (recordp value)
   (> (length value) 0)
   (eq (aref value 0) 'acss)))

(defun emacsvox-aural-voice-style-p (value)
  "Return non-nil when VALUE is an explicit aural voice style plist.

An explicit style may name a complete base with `:preset' and override ACSS,
rate, or post-synthesis dimensions."
  (and
   (emacsvox-aural--plist-p value)
   (cl-loop
    for (key _) on value by #'cddr
    thereis (memq key emacsvox-aural--voice-style-keys))))

(defun emacsvox-aural--voice-dimension-key (dimension)
  "Return the keyword property corresponding to voice DIMENSION."
  (intern (concat ":" (symbol-name dimension))))

(defun emacsvox-aural--validate-voice-style (style label)
  "Validate explicit voice STYLE described by LABEL and return STYLE."
  (unless (emacsvox-aural-voice-style-p style)
    (emacsvox-aural--rule-error
     "%s must contain :preset or an ACSS dimension: %S" label style))
  (let ((unknown
         (cl-loop
          for (key _) on style by #'cddr
          unless (memq key emacsvox-aural--voice-style-keys)
          collect key)))
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown properties in %s: %S" label unknown)))
  (when (plist-member style :preset)
    (let ((preset (plist-get style :preset)))
      (unless (or
               (null preset)
               (and
                (symbolp preset)
                (not (keywordp preset))))
        (emacsvox-aural--rule-error
         "%s :preset must be a non-keyword symbol or nil: %S"
         label preset))))
  (when (plist-member style :family)
    (let ((family (plist-get style :family)))
      (unless (or (null family) (symbolp family) (stringp family))
        (emacsvox-aural--rule-error
         "%s :family must be a symbol, string, or nil: %S" label family))))
  (dolist (dimension
           (append
            '(average-pitch pitch-range stress richness)
            emacsvox-aural-post-synthesis-dimensions))
    (let ((key (emacsvox-aural--voice-dimension-key dimension)))
      (when (plist-member style key)
        (let ((value (plist-get style key)))
          (unless (or
                   (null value)
                   (and (integerp value) (<= 0 value 9)))
            (emacsvox-aural--rule-error
             "%s %S must be an integer from 0 through 9, or nil: %S"
             label key value))))))
  (when (plist-member style :rate-offset)
    (let ((value (plist-get style :rate-offset)))
      (unless (or
               (null value)
               (and (integerp value) (<= -20 value 20)))
        (emacsvox-aural--rule-error
         "%s :rate-offset must be an integer from -20 through 20, or nil: %S"
         label value))))
  ;; Keep old palette files loadable, but compilation deliberately does not
  ;; apply this absolute zero-to-nine value.
  (when (plist-member style :rate)
    (let ((value (plist-get style :rate)))
      (unless (or
               (null value)
               (and (integerp value) (<= 0 value 9)))
        (emacsvox-aural--rule-error
         "%s legacy :rate must be an integer from 0 through 9, or nil: %S"
         label value))))
  style)

(defun emacsvox-aural-validate-voice-value (voice label)
  "Validate declarative VOICE described by LABEL and return VOICE.

Symbols and lists of personality symbols are complete presets.  Explicit
style plists and raw ACSS records are composable.  Nil selects the default
voice."
  (cond
   ((emacsvox-aural-voice-style-p voice)
    (emacsvox-aural--validate-voice-style voice label))
   ((or (null voice)
        (and (symbolp voice) (not (keywordp voice)))
        (emacsvox-aural--acss-p voice)
        (and
         (proper-list-p voice)
         voice
         (cl-every
          (lambda (item)
            (and (symbolp item) (not (keywordp item))))
          voice)))
    voice)
   (t
    (emacsvox-aural--rule-error
     (concat
      "%s must be a named preset, personality list, explicit ACSS style, "
      "raw ACSS record, or nil: %S")
     label voice))))

(defun emacsvox-aural--require-kind (id kind label)
  "Return semantic ID when registered as KIND, otherwise report LABEL."
  (let* ((canonical (emacsvox-aural-canonical-semantic-id id))
         (record (emacsvox-aural-semantic canonical)))
    (unless record
      (emacsvox-aural--rule-error "%s is not registered: %S" label id))
    (unless (eq (emacsvox-aural-semantic-kind record) kind)
      (emacsvox-aural--rule-error
       "%s %S is registered as %S, not %S"
       label id (emacsvox-aural-semantic-kind record) kind))
    canonical))

(defun emacsvox-aural--normalize-symbols (singular plural label)
  "Combine SINGULAR and PLURAL into unique symbols for LABEL."
  (let ((values
         (append
          (when singular (list singular))
          (cond
           ((null plural) nil)
           ((listp plural) plural)
           (t
            (emacsvox-aural--rule-error
             "%s must be a list: %S" label plural))))))
    (dolist (value values)
      (emacsvox-aural--require-symbol value label))
    (delete-dups values)))

(defun emacsvox-aural--keyword-attribute (keyword)
  "Return the semantic identifier represented by KEYWORD."
  (intern (substring (symbol-name keyword) 1)))

(defun emacsvox-aural--valid-attribute-value-p (record value)
  "Return non-nil when VALUE satisfies attribute RECORD metadata."
  (and
   (or
    (null (emacsvox-aural-semantic-allowed-values record))
    (member value (emacsvox-aural-semantic-allowed-values record)))
   (pcase (emacsvox-aural-semantic-value-type record)
     ('nil t)
     ('positive-integer (and (integerp value) (> value 0)))
     ('integer (integerp value))
     ('number (numberp value))
     ('string (stringp value))
     ('symbol (symbolp value))
     ('boolean (or (null value) (eq value t)))
     (_ t))))

(defun emacsvox-aural--extract-attributes (plist reserved label)
  "Extract registered attributes from PLIST excluding RESERVED keys.

LABEL identifies the source in validation errors."
  (let (attributes)
    (cl-loop
     for (key value) on plist by #'cddr
     unless (memq key reserved)
     do
     (let* ((raw-id (emacsvox-aural--keyword-attribute key))
            (id (emacsvox-aural-canonical-semantic-id raw-id))
            (record (emacsvox-aural-semantic id)))
       (unless (and record (eq (emacsvox-aural-semantic-kind record) 'attribute))
         (emacsvox-aural--rule-error
          "%s contains unknown attribute %S" label key))
       (when (assq id attributes)
         (emacsvox-aural--rule-error
          "%s defines attribute %S more than once" label id))
       (unless (emacsvox-aural--valid-attribute-value-p record value)
         (emacsvox-aural--rule-error
          "%s has invalid value for %S: %S" label id value))
       (push (cons id value) attributes)))
    (nreverse attributes)))

(defun emacsvox-aural--semantic-alias-records (ids)
  "Return unique alias records referenced by semantic IDS."
  (let (aliases)
    (dolist (id ids)
      (when-let* ((alias (emacsvox-aural-semantic-alias id)))
        (unless
            (cl-find
             (emacsvox-aural-semantic-alias-id alias)
             aliases
             :key #'emacsvox-aural-semantic-alias-id
             :test #'eq)
          (push alias aliases))))
    (nreverse aliases)))

(defun emacsvox-aural--semantic-ids-in-plist (plist reserved)
  "Return raw semantic identifiers represented by PLIST outside RESERVED."
  (cl-loop
   for (key _) on plist by #'cddr
   unless (memq key reserved)
   collect (emacsvox-aural--keyword-attribute key)))

(defun emacsvox-aural--canonicalize-facts (facts)
  "Return (CANONICAL-FACTS . ALIASES) for declarative FACTS.

Singular event and state keys are folded into their plural forms.  Every
attribute occurs once under its canonical identifier, in stable identifier
order.  ALIASES records deprecated identifiers encountered during migration."
  (emacsvox-aural--require-plist facts "Semantic facts")
  (let* ((raw-role (plist-get facts :role))
         (raw-events
          (emacsvox-aural--normalize-symbols
           (plist-get facts :event)
           (plist-get facts :events)
           "Fact events"))
         (raw-states
          (emacsvox-aural--normalize-symbols
           (plist-get facts :state)
           (plist-get facts :states)
           "Fact states"))
         (raw-attributes
          (emacsvox-aural--semantic-ids-in-plist
           facts emacsvox-aural--fact-keys))
         (alias-records
          (emacsvox-aural--semantic-alias-records
           (append
            (when raw-role (list raw-role))
            raw-events raw-states raw-attributes)))
         (role
          (and raw-role
               (emacsvox-aural--require-kind
                raw-role 'role "Fact role")))
         (events
          (delete-dups
           (mapcar
            (lambda (event)
              (emacsvox-aural--require-kind event 'event "Fact event"))
            raw-events)))
         (states
          (delete-dups
           (mapcar
            (lambda (state)
              (emacsvox-aural--require-kind state 'state "Fact state"))
            raw-states)))
         (attributes
          (sort
           (emacsvox-aural--extract-attributes
            facts emacsvox-aural--fact-keys "Semantic facts")
           (lambda (left right)
             (string-lessp
              (symbol-name (car left))
              (symbol-name (car right))))))
         canonical)
    (when role
      (setq canonical (plist-put canonical :role role)))
    (when events
      (setq canonical (plist-put canonical :events events)))
    (when states
      (setq canonical (plist-put canonical :states states)))
    (dolist (attribute attributes)
      (setq
       canonical
       (plist-put
        canonical
        (intern (format ":%s" (car attribute)))
        (cdr attribute))))
    (when (plist-member facts :content)
      (setq canonical (plist-put canonical :content (plist-get facts :content))))
    (cons canonical alias-records)))

(defun emacsvox-aural-canonical-facts (facts)
  "Return the authoritative canonical representation of semantic FACTS."
  (car (emacsvox-aural--canonicalize-facts facts)))

(defun emacsvox-aural-migrate-facts
    (facts &optional from-version)
  "Migrate semantic FACTS from FROM-VERSION to the current contract.

Aliases are stable migration hooks: identifiers deprecated at or after
FROM-VERSION are replaced by their canonical targets.  Future versions are
rejected so callers cannot silently discard an unknown contract."
  (let ((version (or from-version emacsvox-aural-semantic-schema-version)))
    (unless
        (and
         (integerp version)
         (> version 0)
         (<= version emacsvox-aural-semantic-schema-version))
      (emacsvox-aural--rule-error
       "Unsupported semantic contract version: %S" version))
    (emacsvox-aural-canonical-facts facts)))

(defun emacsvox-aural-merge-facts (base local)
  "Canonically merge BASE facts with range-local LOCAL facts.

LOCAL overrides scalar role, content, and attribute values.  Event and state
sets compose with local values first.  The result contains one authoritative
property for each semantic field."
  (let* ((base (emacsvox-aural-canonical-facts (or base nil)))
         (local (emacsvox-aural-canonical-facts (or local nil)))
         (role
          (if (plist-member local :role)
              (plist-get local :role)
            (plist-get base :role)))
         (events
          (delete-dups
           (append
            (copy-sequence (plist-get local :events))
            (copy-sequence (plist-get base :events)))))
         (states
          (delete-dups
           (append
            (copy-sequence (plist-get local :states))
            (copy-sequence (plist-get base :states)))))
         (content-set-p
          (or
           (plist-member local :content)
           (plist-member base :content)))
         (content
          (if (plist-member local :content)
              (plist-get local :content)
            (plist-get base :content)))
         (base-attributes
          (emacsvox-aural--extract-attributes
           base emacsvox-aural--fact-keys "Base semantic facts"))
         (local-attributes
          (emacsvox-aural--extract-attributes
           local emacsvox-aural--fact-keys "Range-local semantic facts"))
         (attributes (copy-tree base-attributes))
         result)
    (dolist (attribute local-attributes)
      (setf (alist-get (car attribute) attributes) (cdr attribute)))
    (setq
     attributes
     (sort
      attributes
      (lambda (left right)
        (string-lessp
         (symbol-name (car left))
         (symbol-name (car right))))))
    (when role
      (setq result (plist-put result :role role)))
    (when events
      (setq result (plist-put result :events events)))
    (when states
      (setq result (plist-put result :states states)))
    (dolist (attribute attributes)
      (setq
       result
       (plist-put
        result
        (intern (format ":%s" (car attribute)))
        (cdr attribute))))
    (when content-set-p
      (setq result (plist-put result :content content)))
    result))

(defun emacsvox-aural--require-attribute-ids (value label)
  "Validate attribute identifier list VALUE for LABEL."
  (unless (and (listp value) (proper-list-p value))
    (emacsvox-aural--rule-error "%s must be a proper list: %S" label value))
  (let (attributes)
    (dolist (id value)
      (push
       (emacsvox-aural--require-kind id 'attribute label)
       attributes))
    (delete-dups (nreverse attributes))))

(defun emacsvox-aural-semantic-lineage (id)
  "Return canonical semantic ID followed by its fallback ancestors."
  (let ((current (emacsvox-aural-canonical-semantic-id id))
        lineage)
    (while current
      (when (memq current lineage)
        (emacsvox-aural--rule-error
         "Semantic fallback cycle involving %S" current))
      (push current lineage)
      (setq
       current
       (when-let* ((record (emacsvox-aural-semantic current)))
         (emacsvox-aural-semantic-fallback record))))
    (nreverse lineage)))

(defun emacsvox-aural-semantic-distance (selected actual)
  "Return fallback distance when SELECTED matches ACTUAL, or nil.

Distance zero is an exact match.  A positive distance means ACTUAL falls
back to the more general SELECTED semantic."
  (cl-position
   (emacsvox-aural-canonical-semantic-id selected)
   (emacsvox-aural-semantic-lineage actual)
   :test #'eq))

(defun emacsvox-aural--semantic-restriction-allows-p (actual allowed)
  "Return non-nil when ACTUAL is covered by one of ALLOWED semantics."
  (cl-some
   (lambda (candidate)
     (numberp (emacsvox-aural-semantic-distance candidate actual)))
   allowed))

(defun emacsvox-aural--validate-semantic-combination
    (role events states attributes occasion label)
  "Validate an operational semantic combination described by LABEL."
  (let* ((role-record (and role (emacsvox-aural-semantic role)))
         (entries
          (append
           (mapcar (lambda (id) (cons 'event id)) events)
           (mapcar (lambda (id) (cons 'state id)) states)
           (mapcar (lambda (entry) (cons 'attribute (car entry))) attributes))))
    (when (and role-record occasion)
      (let ((allowed (emacsvox-aural-semantic-occasions role-record)))
        (when (and allowed (not (memq occasion allowed)))
          (emacsvox-aural--rule-error
           "%s uses role %S on unsupported occasion %S; allowed: %S"
           label role occasion allowed))))
    (dolist (entry entries)
      (let* ((kind (car entry))
             (id (cdr entry))
             (record (emacsvox-aural-semantic id))
             (roles (emacsvox-aural-semantic-roles record))
             (role-contract
              (and
               role-record
               (pcase kind
                 ('event (emacsvox-aural-semantic-events role-record))
                 ('state (emacsvox-aural-semantic-states role-record))
                 ('attribute
                  (emacsvox-aural-semantic-attributes role-record))))))
        (when (and roles (null role))
          (emacsvox-aural--rule-error
           "%s uses %S without one of its required roles %S"
           label id roles))
        (when
            (and
             roles role
             (not
              (emacsvox-aural--semantic-restriction-allows-p role roles)))
          (emacsvox-aural--rule-error
           "%s combines %S with invalid role %S; allowed: %S"
           label id role roles))
        (when
            (and
             role-contract
             (not
              (emacsvox-aural--semantic-restriction-allows-p
               id role-contract)))
          (emacsvox-aural--rule-error
           "%s combines role %S with unsupported %S %S; allowed: %S"
           label role kind id role-contract))
        (when occasion
          (let ((allowed (emacsvox-aural-semantic-occasions record)))
            (when (and allowed (not (memq occasion allowed)))
              (emacsvox-aural--rule-error
               "%s uses %S on unsupported occasion %S; allowed: %S"
               label id occasion allowed))))))
    t))

(defun emacsvox-aural--selector-semantics (selector)
  "Return semantic records explicitly selected by SELECTOR."
  (delq
   nil
   (mapcar
    #'emacsvox-aural-semantic
    (append
     (when (emacsvox-aural-selector-role selector)
       (list (emacsvox-aural-selector-role selector)))
     (emacsvox-aural-selector-events selector)
     (emacsvox-aural-selector-states selector)
     (mapcar #'car (emacsvox-aural-selector-attributes selector))
     (emacsvox-aural-selector-required-attributes selector)))))

(defun emacsvox-aural--template-fields (template label)
  "Return validated semantic fields referenced by TEMPLATE for LABEL."
  (unless (and (stringp template) (not (string-empty-p template)))
    (emacsvox-aural--rule-error "%s must be a nonempty string" label))
  (let ((position 0)
        fields)
    (while (string-match "{\\([^{}]+\\)}" template position)
      (when
          (string-match-p
           "[{}]" (substring template position (match-beginning 0)))
        (emacsvox-aural--rule-error
         "%s contains an unmatched brace: %S" label template))
      (let ((name (match-string 1 template)))
        (unless
            (string-match-p
             "\\`[[:alpha:]][[:alnum:]-]*\\'" name)
          (emacsvox-aural--rule-error
           "%s contains invalid placeholder {%s}" label name))
        (let* ((field (intern name))
               (record (emacsvox-aural-semantic field)))
          (unless
              (or
               (eq field 'role)
               (and
                record
                (eq (emacsvox-aural-semantic-kind record) 'attribute)))
            (emacsvox-aural--rule-error
             "%s names unsupported semantic field {%s}" label name))
          (push field fields)))
      (setq position (match-end 0)))
    (when (string-match-p "[{}]" (substring template position))
      (emacsvox-aural--rule-error
       "%s contains an unmatched brace: %S" label template))
    (delete-dups (nreverse fields))))

(defun emacsvox-aural--compile-selector (selector rule-id)
  "Compile SELECTOR for RULE-ID."
  (emacsvox-aural--require-plist selector (format "Selector for %S" rule-id))
  (let* ((raw-role (plist-get selector :role))
         (raw-events
          (emacsvox-aural--normalize-symbols
           (plist-get selector :event)
           (plist-get selector :events)
           "Selector events"))
         (raw-states
          (emacsvox-aural--normalize-symbols
           (plist-get selector :state)
           (plist-get selector :states)
           "Selector states"))
         (raw-required (or (plist-get selector :requires) nil))
         (raw-attributes
          (emacsvox-aural--semantic-ids-in-plist
           selector emacsvox-aural--selector-keys))
         (semantic-aliases
          (emacsvox-aural--semantic-alias-records
           (append
            (when raw-role (list raw-role))
            raw-events raw-states raw-required raw-attributes)))
         (role
          (and
           raw-role
           (emacsvox-aural--require-kind
            raw-role 'role "Selector role")))
         (events
          (delete-dups
           (mapcar
            (lambda (event)
              (emacsvox-aural--require-kind
               event 'event "Selector event"))
            raw-events)))
         (states
          (delete-dups
           (mapcar
            (lambda (state)
              (emacsvox-aural--require-kind
               state 'state "Selector state"))
            raw-states)))
         (module (plist-get selector :module))
         (mode (plist-get selector :mode))
         (occasion (plist-get selector :occasion))
         (legacy-cue (plist-get selector :legacy-cue))
         (legacy-face (plist-get selector :legacy-face))
         (legacy-personality (plist-get selector :legacy-personality))
         (required-attributes
          (emacsvox-aural--require-attribute-ids
           raw-required
           "Required selector attributes"))
         (attributes
          (emacsvox-aural--extract-attributes
           selector emacsvox-aural--selector-keys
           (format "Selector for %S" rule-id))))
    (when module
      (emacsvox-aural--require-symbol module "Selector module"))
    (when mode
      (emacsvox-aural--require-symbol mode "Selector mode"))
    (when occasion
      (unless (emacsvox-aural-occasion occasion)
        (emacsvox-aural--rule-error
         "Selector occasion is not registered: %S" occasion)))
    (when legacy-cue
      (emacsvox-aural--require-symbol legacy-cue "Selector legacy cue"))
    (when legacy-face
      (emacsvox-aural--require-symbol legacy-face "Selector legacy face"))
    (when legacy-personality
      (unless (or (symbolp legacy-personality) (consp legacy-personality))
        (emacsvox-aural--rule-error
         "Selector legacy personality must be a symbol or cons: %S"
         legacy-personality)))
    (let ((redundant
           (cl-intersection
            required-attributes (mapcar #'car attributes) :test #'eq)))
      (when redundant
        (emacsvox-aural--rule-error
         "Selector for %S both fixes and requires attributes: %S"
         rule-id redundant)))
    (emacsvox-aural--validate-semantic-combination
     role events states
     (append
      attributes
      (mapcar (lambda (id) (cons id :required)) required-attributes))
     occasion
     (format "Selector for %S" rule-id))
    (emacsvox-aural--make-selector
     :role role
     :events events
     :states states
     :attributes attributes
     :required-attributes required-attributes
     :module module
     :mode mode
     :occasion occasion
     :legacy-cue legacy-cue
     :legacy-face legacy-face
     :legacy-personality legacy-personality
     :semantic-aliases semantic-aliases)))

(defun emacsvox-aural--selector-default-anchor (selector)
  "Return the backward-compatible action anchor for SELECTOR.

Compatibility face and personality selectors describe formatting runs.
Semantic, contextual, and legacy-cue selectors describe complete objects."
  (if
      (or
       (emacsvox-aural-selector-legacy-face selector)
       (emacsvox-aural-selector-legacy-personality selector))
      'run
    'object))

(defun emacsvox-aural--numeric-action-expression-field
    (value property action-id positive)
  "Validate numeric action VALUE and return its referenced semantic field.

PROPERTY and ACTION-ID identify diagnostics.  When POSITIVE is non-nil, a
literal number must be greater than zero; otherwise it may be zero.  VALUE may
instead be `(:fact ATTRIBUTE)', which is resolved after rule matching."
  (cond
   ((numberp value)
    (unless (if positive (> value 0) (>= value 0))
      (emacsvox-aural--rule-error
       "Action %S %s must be %s: %S"
       action-id property
       (if positive "positive" "nonnegative") value))
    nil)
   ((and
     (proper-list-p value)
     (= (length value) 2)
     (eq (car value) :fact)
     (symbolp (cadr value)))
    (cadr value))
   (t
    (emacsvox-aural--rule-error
     "Action %S %s must be a number or (:fact ATTRIBUTE): %S"
     action-id property value))))

(defun emacsvox-aural--compile-action
    (data rule-id phase index default-anchor)
  "Compile action DATA contributed by RULE-ID in PHASE at INDEX.

DEFAULT-ANCHOR is inferred from the rule selector when DATA omits `:anchor'."
  (emacsvox-aural--require-plist
   data (format "%S action %d for %S" phase index rule-id))
  (let* ((kind (plist-get data :kind))
         (id
          (or
           (plist-get data :id)
           (intern (format "%s/%s/%d" rule-id phase index))))
         (text (plist-get data :text))
         (text-template (plist-get data :text-template))
         (cue (or (plist-get data :cue) (plist-get data :name)))
         (tone (plist-get data :tone))
         (pitch (plist-get data :pitch))
         (duration (plist-get data :duration))
         (audio-mode
          (if (plist-member data :audio-mode)
              (plist-get data :audio-mode)
            'overlay))
         (voice (plist-get data :voice))
         (volume (plist-get data :volume))
         (space (plist-get data :space))
         (anchor (or (plist-get data :anchor) default-anchor))
         (allowed
          '(:id :kind :text :text-template :cue :name :tone :pitch :duration
            :audio-mode :voice :volume :space :anchor))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless (memq key allowed)
           collect key))
         template-fields)
    (emacsvox-aural--require-symbol id "Action identifier")
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown properties for action %S: %S" id unknown))
    (unless (memq kind emacsvox-aural-action-kinds)
      (emacsvox-aural--rule-error
       "Invalid action kind for %S: %S" id kind))
    (let* ((kind-properties
            (pcase kind
              ('speech
               '(:id :kind :text :text-template :voice :volume :space
                 :anchor))
              ('cue '(:id :kind :cue :name :volume :space :anchor))
              ('pause '(:id :kind :duration :anchor))
              ('tone
               '(:id :kind :tone :pitch :duration :audio-mode :anchor))
              (_ allowed)))
           (incompatible
            (cl-loop
             for (key _) on data by #'cddr
             unless (memq key kind-properties)
             collect key)))
      (when incompatible
        (emacsvox-aural--rule-error
         "Properties do not apply to %S action %S: %S"
         kind id incompatible)))
    (pcase kind
      ('speech
       (when (and text text-template)
         (emacsvox-aural--rule-error
          "Speech action %S cannot combine :text and :text-template" id))
       (cond
        (text
         (unless (and (stringp text) (not (string-empty-p text)))
           (emacsvox-aural--rule-error
            "Speech action %S requires nonempty :text" id)))
        (text-template
         (setq
          template-fields
          (emacsvox-aural--template-fields
           text-template
           (format "Speech action %S template" id))))
        (t
         (emacsvox-aural--rule-error
          "Speech action %S requires :text or :text-template" id))))
      ('cue
       (when (and (plist-member data :cue) (plist-member data :name))
         (emacsvox-aural--rule-error
          "Cue action %S cannot combine :cue and compatibility :name" id))
       (emacsvox-aural--require-symbol cue (format "Cue for action %S" id)))
      ('pause
       (unless (and (numberp duration) (>= duration 0))
         (emacsvox-aural--rule-error
          "Pause action %S requires nonnegative :duration" id)))
      ('tone
       (unless (memq audio-mode emacsvox-aural-tone-audio-modes)
         (emacsvox-aural--rule-error
          "Tone action %S audio mode must be overlay or insert: %S"
          id audio-mode))
       (let ((pitch-present-p (plist-member data :pitch))
             (duration-present-p (plist-member data :duration)))
         (cond
          (tone
           (when (or pitch-present-p duration-present-p)
             (emacsvox-aural--rule-error
              "Tone action %S cannot combine :tone with :pitch or :duration"
              id))
           (emacsvox-aural--require-symbol
            tone (format "Tone for action %S" id)))
          ((and pitch-present-p duration-present-p)
           (setq
            template-fields
            (delq
             nil
             (list
              (emacsvox-aural--numeric-action-expression-field
               pitch :pitch id t)
              (emacsvox-aural--numeric-action-expression-field
               duration :duration id nil)))))
          (t
           (emacsvox-aural--rule-error
            "Tone action %S requires :tone or both :pitch and :duration"
            id))))))
    (when (and volume (not (numberp volume)))
      (emacsvox-aural--rule-error
       "Action volume must be numeric for %S" id))
    (when (plist-member data :voice)
      (emacsvox-aural-validate-voice-value
       voice (format "Voice for action %S" id)))
    (unless (memq anchor emacsvox-aural-action-anchors)
      (emacsvox-aural--rule-error
       "Action anchor for %S must be object, run, or transition: %S"
       id anchor))
    (when space
      (condition-case error
          (emacsvox-aural-spatial-validate-space
           space (format "Action space for %S" id))
        (error
         (emacsvox-aural--rule-error "%s" (error-message-string error)))))
    (when (and space (eq kind 'pause))
      (emacsvox-aural--rule-error
       "Pause action %S cannot have spatial presentation" id))
    (emacsvox-aural--make-action
     :id id
     :kind kind
     :text text
     :text-template text-template
     :template-fields template-fields
     :cue cue
     :tone tone
     :pitch pitch
     :duration duration
     :audio-mode (and (eq kind 'tone) audio-mode)
     :voice voice
     :volume volume
     :space (copy-tree space)
     :anchor anchor
     :source rule-id)))

(defun emacsvox-aural-phase-actions (operations)
  "Return every action introduced by phase OPERATIONS."
  (append
   (emacsvox-aural-phase-operations-replace operations)
   (emacsvox-aural-phase-operations-prepend operations)
   (emacsvox-aural-phase-operations-append operations)))

(defun emacsvox-aural-rule-actions (rule)
  "Return every ordered action introduced by compiled RULE."
  (let ((contribution (emacsvox-aural-rule-contribution rule)))
    (append
     (emacsvox-aural-phase-actions
      (emacsvox-aural-contribution-before contribution))
     (emacsvox-aural-phase-actions
      (emacsvox-aural-contribution-after contribution)))))

(defun emacsvox-aural--validate-template-guarantees
    (selector contribution rule-id)
  "Validate CONTRIBUTION templates for RULE-ID against SELECTOR guarantees."
  (let ((attributes (emacsvox-aural-selector-attributes selector))
        (required
         (emacsvox-aural-selector-required-attributes selector)))
    (dolist
        (action
         (append
          (emacsvox-aural-phase-actions
           (emacsvox-aural-contribution-before contribution))
          (emacsvox-aural-phase-actions
           (emacsvox-aural-contribution-after contribution))))
      (dolist (field (emacsvox-aural-action-template-fields action))
        (unless
            (if (eq field 'role)
                (emacsvox-aural-selector-role selector)
              (or (assq field attributes) (memq field required)))
          (emacsvox-aural--rule-error
           "Rule %S template field {%s} is not guaranteed by its selector"
           rule-id field))))))

(defun emacsvox-aural--compile-actions
    (actions rule-id phase default-anchor &optional id-namespace)
  "Compile ACTIONS contributed by RULE-ID to PHASE.

DEFAULT-ANCHOR supplies the rule's inferred lifetime.  ID-NAMESPACE
distinguishes generated identifiers for separate operations."
  (unless (listp actions)
    (emacsvox-aural--rule-error
     "%S actions for %S must be a list" phase rule-id))
  (let ((compiled
         (cl-loop
          for action in actions
          for index from 0
          collect
          (emacsvox-aural--compile-action
           action rule-id (or id-namespace phase) index default-anchor)))
        seen)
    (dolist (action compiled)
      (when (memq (emacsvox-aural-action-id action) seen)
        (emacsvox-aural--rule-error
         "Duplicate action identifier for %S: %S"
         rule-id (emacsvox-aural-action-id action)))
      (push (emacsvox-aural-action-id action) seen))
    compiled))

(defun emacsvox-aural--compile-phase
    (data rule-id phase default-anchor)
  "Compile phase DATA contributed by RULE-ID to PHASE.

DEFAULT-ANCHOR scopes destructive operations and actions that omit an
explicit anchor."
  (cond
   ((null data)
    (emacsvox-aural--make-phase-operations :anchor default-anchor))
   ((and (listp data) (or (null data) (listp (car data))))
    (emacsvox-aural--make-phase-operations
     :append
     (emacsvox-aural--compile-actions
      data rule-id phase default-anchor)
     :anchor default-anchor))
   (t
    (emacsvox-aural--require-plist
     data (format "%S operations for %S" phase rule-id))
    (let* ((allowed '(:suppress :replace :remove :prepend :append :anchor))
           (unknown
            (cl-loop
             for (key _) on data by #'cddr
             unless (memq key allowed)
             collect key))
           (suppress (plist-get data :suppress))
           (replace-set-p (plist-member data :replace))
           (remove (plist-get data :remove))
           (prepend (plist-get data :prepend))
           (append-actions (plist-get data :append))
           (anchor (or (plist-get data :anchor) default-anchor)))
      (when unknown
        (emacsvox-aural--rule-error
         "Unknown %S operations for %S: %S" phase rule-id unknown))
      (when (and suppress
                 (or replace-set-p remove prepend append-actions))
        (emacsvox-aural--rule-error
         "Suppression cannot be combined with other %S operations for %S"
         phase rule-id))
      (unless (or (null remove)
                  (and (listp remove) (cl-every #'symbolp remove)))
        (emacsvox-aural--rule-error
         "Remove identifiers for %S must be symbols" rule-id))
      (unless (memq anchor emacsvox-aural-action-anchors)
        (emacsvox-aural--rule-error
         "%S phase anchor for %S must be object, run, or transition: %S"
         phase rule-id anchor))
      (let* ((replace-actions
              (when replace-set-p
                (emacsvox-aural--compile-actions
                 (plist-get data :replace)
                 rule-id phase anchor
                 (intern (format "%s-replace" phase)))))
             (prepend-actions
              (when prepend
                (emacsvox-aural--compile-actions
                 prepend
                 rule-id phase default-anchor
                 (intern (format "%s-prepend" phase)))))
             (compiled-append
              (when append-actions
                (emacsvox-aural--compile-actions
                 append-actions
                 rule-id phase default-anchor
                 (intern (format "%s-append" phase)))))
             (all-actions
              (append replace-actions prepend-actions compiled-append))
             seen)
        (dolist (action replace-actions)
          (unless (eq (emacsvox-aural-action-anchor action) anchor)
            (emacsvox-aural--rule-error
             "Replacement action %S must use the %S phase anchor %S"
             (emacsvox-aural-action-id action) phase anchor)))
        (dolist (action all-actions)
          (when (memq (emacsvox-aural-action-id action) seen)
            (emacsvox-aural--rule-error
             "Duplicate action identifier across %S operations for %S: %S"
             phase rule-id (emacsvox-aural-action-id action)))
          (push (emacsvox-aural-action-id action) seen))
        (emacsvox-aural--make-phase-operations
         :suppress suppress
         :replace-set-p replace-set-p
         :replace replace-actions
         :remove (copy-sequence remove)
         :prepend prepend-actions
         :append compiled-append
         :anchor anchor))))))

(defun emacsvox-aural--compile-content (data rule-id)
  "Compile content style DATA contributed by RULE-ID."
  (if (null data)
      (emacsvox-aural--make-content-patch)
    (emacsvox-aural--require-plist
     data (format "Content style for %S" rule-id))
    (let* ((allowed '(:suppress :speak :voice :volume :space))
           (unknown
            (cl-loop
             for (key _) on data by #'cddr
             unless (memq key allowed)
             collect key))
           (volume (plist-get data :volume))
           (space (plist-get data :space)))
      (when unknown
        (emacsvox-aural--rule-error
         "Unknown content properties for %S: %S" rule-id unknown))
      (when (and (plist-member data :speak)
                 (not (memq (plist-get data :speak) '(nil t))))
        (emacsvox-aural--rule-error
         "Content :speak must be boolean for %S" rule-id))
      (when (and volume (not (numberp volume)))
        (emacsvox-aural--rule-error
         "Content volume must be numeric for %S" rule-id))
      (when (plist-member data :voice)
        (emacsvox-aural-validate-voice-value
         (plist-get data :voice) (format "Content voice for %S" rule-id)))
      (when space
        (condition-case error
            (emacsvox-aural-spatial-validate-space
             space (format "Content space for %S" rule-id))
          (error
           (emacsvox-aural--rule-error "%s" (error-message-string error)))))
      (emacsvox-aural--make-content-patch
       :suppress (plist-get data :suppress)
       :speak-set-p (plist-member data :speak)
       :speak (plist-get data :speak)
       :voice-set-p (plist-member data :voice)
       :voice (plist-get data :voice)
       :volume-set-p (plist-member data :volume)
       :volume volume
       :space-set-p (plist-member data :space)
       :space (copy-tree space)))))

(defun emacsvox-aural--compile-contribution (render rule-id selector)
  "Compile RENDER contribution for RULE-ID using SELECTOR defaults."
  (emacsvox-aural--require-plist render (format "Render data for %S" rule-id))
  (let ((unknown
         (cl-loop
          for (key _) on render by #'cddr
          unless (memq key '(:before :content :after))
          collect key))
        (default-anchor
         (emacsvox-aural--selector-default-anchor selector)))
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown render phases for %S: %S" rule-id unknown))
    (emacsvox-aural--make-contribution
     :before
     (emacsvox-aural--compile-phase
      (plist-get render :before) rule-id 'before default-anchor)
     :content
     (emacsvox-aural--compile-content
      (plist-get render :content) rule-id)
     :after
     (emacsvox-aural--compile-phase
      (plist-get render :after) rule-id 'after default-anchor))))

(defun emacsvox-aural--phase-operations-active-p (operations)
  "Return non-nil when OPERATIONS can affect an action phase."
  (or
   (emacsvox-aural-phase-operations-suppress operations)
   (emacsvox-aural-phase-operations-replace-set-p operations)
   (emacsvox-aural-phase-operations-remove operations)
   (emacsvox-aural-phase-operations-prepend operations)
   (emacsvox-aural-phase-operations-append operations)))

(defun emacsvox-aural--content-patch-active-p (patch)
  "Return non-nil when content PATCH can affect presentation."
  (or
   (emacsvox-aural-content-patch-suppress patch)
   (emacsvox-aural-content-patch-speak-set-p patch)
   (emacsvox-aural-content-patch-voice-set-p patch)
   (emacsvox-aural-content-patch-volume-set-p patch)
   (emacsvox-aural-content-patch-space-set-p patch)))

(defun emacsvox-aural--validate-render-phases
    (selector contribution rule-id)
  "Validate CONTRIBUTION phases against SELECTOR semantics for RULE-ID."
  (let (used)
    (when
        (emacsvox-aural--phase-operations-active-p
         (emacsvox-aural-contribution-before contribution))
      (push 'before used))
    (when
        (emacsvox-aural--content-patch-active-p
         (emacsvox-aural-contribution-content contribution))
      (push 'content used))
    (when
        (emacsvox-aural--phase-operations-active-p
         (emacsvox-aural-contribution-after contribution))
      (push 'after used))
    (dolist (record (emacsvox-aural--selector-semantics selector))
      (let ((allowed (emacsvox-aural-semantic-phases record)))
        (dolist (phase used)
          (when (and allowed (not (memq phase allowed)))
            (emacsvox-aural--rule-error
             "Rule %S renders in phase %S, unsupported by semantic %S; allowed: %S"
             rule-id phase
             (emacsvox-aural-semantic-id record)
             allowed)))))
    t))

(defun emacsvox-aural-compile-rule
    (data origin &optional index source layer-order)
  "Compile declarative rule DATA from ORIGIN.

INDEX supplies the default visible order.  SOURCE is retained for diagnostics.
LAYER-ORDER records inheritance order within one origin."
  (emacsvox-aural--require-plist data "Aural rule")
  (unless (assq origin emacsvox-aural-origin-ranks)
    (emacsvox-aural--rule-error "Unknown rule origin: %S" origin))
  (unless (or (null layer-order) (integerp layer-order))
    (emacsvox-aural--rule-error
     "Rule layer order must be an integer: %S" layer-order))
  (let* ((id (plist-get data :id))
         (enabled
          (if (plist-member data :enabled)
              (plist-get data :enabled)
            t))
         (order (if (plist-member data :order)
                    (plist-get data :order)
                  (or index 0)))
         (match (or (plist-get data :match) nil))
         (render (plist-get data :render))
         (allowed '(:id :enabled :order :match :render))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless (memq key allowed)
           collect key)))
    (emacsvox-aural--require-symbol id "Rule identifier")
    (unless (memq enabled '(nil t))
      (emacsvox-aural--rule-error
       "Rule :enabled must be boolean for %S" id))
    (unless (integerp order)
      (emacsvox-aural--rule-error "Rule order must be an integer for %S" id))
    (unless (plist-member data :render)
      (emacsvox-aural--rule-error "Rule %S has no :render contribution" id))
    (when unknown
      (emacsvox-aural--rule-error "Unknown keys for rule %S: %S" id unknown))
    (let* ((selector (emacsvox-aural--compile-selector match id))
           (contribution
            (emacsvox-aural--compile-contribution render id selector)))
      (emacsvox-aural--validate-template-guarantees
       selector contribution id)
      (emacsvox-aural--validate-render-phases
       selector contribution id)
      (emacsvox-aural--make-rule
       :id id
       :enabled enabled
       :origin origin
       :layer-order (or layer-order 0)
       :order order
       :selector selector
       :contribution contribution
       :source source))))

(defun emacsvox-aural-compile-scheme (data &optional origin source)
  "Compile declarative scheme DATA from ORIGIN and SOURCE."
  (emacsvox-aural--require-plist data "Aural scheme")
  (let* ((origin (or origin 'scheme))
         (version (plist-get data :schema-version))
         (id (plist-get data :id))
         (summary (plist-get data :summary))
         (parent (plist-get data :parent))
         (resource-pack (plist-get data :resource-pack))
         (voice-palette (plist-get data :voice-palette))
         (rules (plist-get data :rules))
         (allowed
          '(:schema-version :id :summary :parent :resource-pack
            :voice-palette :rules))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless (memq key allowed)
           collect key)))
    (unless (eq version emacsvox-aural-scheme-schema-version)
      (emacsvox-aural--rule-error
       "Unsupported scheme version %S; expected %S"
       version emacsvox-aural-scheme-schema-version))
    (emacsvox-aural--require-symbol id "Scheme identifier")
    (unless (and (stringp summary) (not (string-empty-p summary)))
      (emacsvox-aural--rule-error
       "Scheme %S requires a nonempty summary" id))
    (when parent
      (emacsvox-aural--require-symbol parent "Parent scheme identifier"))
    (when resource-pack
      (emacsvox-aural--require-symbol resource-pack "Scheme resource pack"))
    (when voice-palette
      (emacsvox-aural--require-symbol voice-palette "Presentation voice palette"))
    (unless (listp rules)
      (emacsvox-aural--rule-error "Rules for scheme %S must be a list" id))
    (when unknown
      (emacsvox-aural--rule-error "Unknown keys for scheme %S: %S" id unknown))
    (let ((compiled
           (cl-loop
            for rule in rules
            for index from 0
            collect (emacsvox-aural-compile-rule rule origin index source)))
          seen)
      (dolist (rule compiled)
        (when (memq (emacsvox-aural-rule-id rule) seen)
          (emacsvox-aural--rule-error
           "Duplicate rule identifier in scheme %S: %S"
           id (emacsvox-aural-rule-id rule)))
        (push (emacsvox-aural-rule-id rule) seen))
      (emacsvox-aural--make-scheme
       :id id
       :schema-version version
       :summary summary
       :parent parent
       :resource-pack resource-pack
       :voice-palette voice-palette
       :origin origin
       :rules compiled
       :source source))))

(defun emacsvox-aural-mode-lineage (mode)
  "Return MODE followed by its declared derived-mode ancestors."
  (let ((current mode)
        lineage)
    (while current
      (when (memq current lineage)
        (emacsvox-aural--rule-error
         "Derived-mode parent cycle involving %S" current))
      (push current lineage)
      (setq current (get current 'derived-mode-parent)))
    (nreverse lineage)))

(defun emacsvox-aural-normalize-input (facts &optional context)
  "Validate FACTS and CONTEXT and return an internal input record."
  (emacsvox-aural--require-plist (or context nil) "Presentation context")
  (let ((unknown
         (cl-loop
          for (key _) on context by #'cddr
          unless (memq key emacsvox-aural--context-keys)
          collect key)))
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown presentation context keys: %S" unknown)))
  (let* ((canonicalized (emacsvox-aural--canonicalize-facts facts))
         (facts (car canonicalized))
         (semantic-aliases (cdr canonicalized))
         (role (plist-get facts :role))
         (events (copy-sequence (plist-get facts :events)))
         (states (copy-sequence (plist-get facts :states)))
         (attributes
          (emacsvox-aural--extract-attributes
           facts emacsvox-aural--fact-keys "Semantic facts"))
         (module (plist-get context :module))
         (mode (plist-get context :mode))
         (occasion (plist-get context :occasion))
         (face-presentation-enabled
          (if (plist-member context :face-presentation-enabled)
              (plist-get context :face-presentation-enabled)
            emacsvox-aural-face-presentation-enabled))
         (voice-lock-enabled
          (if (plist-member context :voice-lock-enabled)
              (plist-get context :voice-lock-enabled)
            (emacsvox-aural-voice-lock-enabled-p)))
         (icons-enabled (emacsvox-aural-icons-enabled-p context))
         (legacy-cue (plist-get context :legacy-cue))
         (legacy-face-source (plist-get context :legacy-face-source))
         (legacy-faces (plist-get context :legacy-faces))
         (legacy-face-provenance
          (plist-get context :legacy-face-provenance))
         (legacy-personality (plist-get context :legacy-personality))
         (legacy-source (plist-get context :legacy-source))
         (source-buffer (plist-get context :source-buffer))
         (source-buffer-name (plist-get context :source-buffer-name))
         (source-position (plist-get context :source-position))
         (buffer-rules (plist-get context :buffer-rules))
         (history-recording-inhibited
          (plist-get context :history-recording-inhibited))
         (presentation-transaction-id
          (plist-get context :presentation-transaction-id))
         (lineage
          (or
           (plist-get context :mode-lineage)
           (and mode (emacsvox-aural-mode-lineage mode)))))
    (when module
      (emacsvox-aural--require-symbol module "Context module"))
    (when mode
      (emacsvox-aural--require-symbol mode "Context mode"))
    (when occasion
      (unless (emacsvox-aural-occasion occasion)
        (emacsvox-aural--rule-error
         "Context occasion is not registered: %S" occasion)))
    (emacsvox-aural--validate-semantic-combination
     role events states attributes occasion "Semantic facts")
    (unless (memq face-presentation-enabled '(nil t))
      (emacsvox-aural--rule-error
       "Context face presentation state must be boolean: %S"
       face-presentation-enabled))
    (unless (memq voice-lock-enabled '(nil t))
      (emacsvox-aural--rule-error
       "Context Voice Lock state must be boolean: %S"
       voice-lock-enabled))
    (unless (memq icons-enabled '(nil t))
      (emacsvox-aural--rule-error
       "Context auditory icon state must be boolean: %S"
       icons-enabled))
    (when legacy-cue
      (emacsvox-aural--require-symbol legacy-cue "Context legacy cue"))
    (when legacy-face-source
      (emacsvox-aural--require-symbol
       legacy-face-source "Context legacy face source"))
    (when legacy-faces
      (unless (and (proper-list-p legacy-faces) (cl-every #'symbolp legacy-faces))
        (emacsvox-aural--rule-error
         "Context legacy faces must be a symbol list: %S" legacy-faces)))
    (when legacy-face-provenance
      (unless
          (and
           (proper-list-p legacy-face-provenance)
           (cl-every
            (lambda (entry)
              (and
               (emacsvox-aural--plist-p entry)
               (symbolp (plist-get entry :face))
               (memq
                (plist-get entry :source)
                '(overlay text-property))
               (memq
                (plist-get entry :property)
                '(face font-lock-face))
               (natnump (plist-get entry :order))))
            legacy-face-provenance))
        (emacsvox-aural--rule-error
         "Context legacy face provenance is invalid: %S"
         legacy-face-provenance)))
    (when legacy-personality
      (unless (or (symbolp legacy-personality) (consp legacy-personality))
        (emacsvox-aural--rule-error
         "Context legacy personality must be a symbol or cons: %S"
         legacy-personality)))
    (when legacy-source
      (emacsvox-aural--require-symbol legacy-source "Legacy presentation source"))
    (when source-buffer
      (unless (bufferp source-buffer)
        (emacsvox-aural--rule-error
         "Context source buffer must be a buffer: %S" source-buffer)))
    (when source-buffer-name
      (unless (stringp source-buffer-name)
        (emacsvox-aural--rule-error
         "Context source buffer name must be a string: %S"
         source-buffer-name)))
    (when source-position
      (unless (natnump source-position)
        (emacsvox-aural--rule-error
         "Context source position must be a natural number: %S"
         source-position)))
    (when buffer-rules
      (unless (proper-list-p buffer-rules)
        (emacsvox-aural--rule-error
         "Context buffer rules must be a proper list: %S" buffer-rules)))
    (unless (memq history-recording-inhibited '(nil t))
      (emacsvox-aural--rule-error
       "Context history recording inhibition must be boolean: %S"
       history-recording-inhibited))
    (when presentation-transaction-id
      (unless (natnump presentation-transaction-id)
        (emacsvox-aural--rule-error
         "Context presentation transaction ID must be a natural number: %S"
         presentation-transaction-id)))
    (when lineage
      (unless (and (listp lineage) (cl-every #'symbolp lineage))
        (emacsvox-aural--rule-error
         "Context mode lineage must be a symbol list: %S" lineage))
      (unless (eq (car lineage) mode)
        (emacsvox-aural--rule-error
         "Context mode lineage must begin with %S: %S" mode lineage)))
    (emacsvox-aural--make-input
     :role role
     :events events
     :states states
     :attributes attributes
     :content (plist-get facts :content)
     :module module
     :mode mode
     :mode-lineage (copy-sequence lineage)
     :occasion occasion
     :face-presentation-enabled face-presentation-enabled
     :voice-lock-enabled voice-lock-enabled
     :legacy-cue legacy-cue
     :legacy-face-source legacy-face-source
     :legacy-faces (delete-dups (copy-sequence legacy-faces))
     :legacy-face-provenance (copy-tree legacy-face-provenance)
     :legacy-personality legacy-personality
     :legacy-source legacy-source
     :source-buffer source-buffer
     :source-buffer-name source-buffer-name
     :facts (copy-tree facts)
     :semantic-aliases semantic-aliases)))

(defun emacsvox-aural--mode-distance (selector input)
  "Return mode ancestry distance for SELECTOR and INPUT, or nil."
  (when-let* ((selected (emacsvox-aural-selector-mode selector)))
    (cl-position selected (emacsvox-aural-input-mode-lineage input) :test #'eq)))

(defun emacsvox-aural--face-distance (selector input)
  "Return face precedence distance for SELECTOR and INPUT, or nil."
  (when-let* ((selected (emacsvox-aural-selector-legacy-face selector)))
    (cl-position selected (emacsvox-aural-input-legacy-faces input) :test #'eq)))

(defun emacsvox-aural--semantic-match-detail
    (kind selected actual)
  "Return provenance when SELECTED matches ACTUAL semantic of KIND."
  (when-let* ((distance (emacsvox-aural-semantic-distance selected actual)))
    (list
     :kind kind
     :selected selected
     :actual actual
     :distance distance
     :path
     (cl-subseq
      (emacsvox-aural-semantic-lineage actual)
      0 (1+ distance)))))

(defun emacsvox-aural--best-semantic-match
    (kind selected actuals &optional value)
  "Return strongest match for SELECTED among ACTUALS of KIND.

ACTUALS contains identifiers, or attribute conses when KIND is `attribute'.
When VALUE is supplied, an attribute must also have that value."
  (let (best)
    (dolist (actual-entry actuals)
      (let* ((actual
              (if (eq kind 'attribute)
                  (car actual-entry)
                actual-entry))
             (eligible
              (or
               (not (eq kind 'attribute))
               (eq value :emacsvox-aural-any)
               (equal value (cdr actual-entry))))
             (detail
              (and
               eligible
               (emacsvox-aural--semantic-match-detail
                kind selected actual))))
        (when
            (and
             detail
             (or
              (null best)
              (< (plist-get detail :distance)
                 (plist-get best :distance))))
          (setq best detail))))
    best))

(defun emacsvox-aural-rule-semantic-matches (rule input)
  "Return semantic match provenance for RULE and INPUT, or `no-match'."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (role (emacsvox-aural-selector-role selector))
         (events (emacsvox-aural-selector-events selector))
         (states (emacsvox-aural-selector-states selector))
         (attributes (emacsvox-aural-selector-attributes selector))
         (required
          (emacsvox-aural-selector-required-attributes selector))
         details)
    (catch 'no-match
      (when role
        (let ((detail
               (and
                (emacsvox-aural-input-role input)
                (emacsvox-aural--semantic-match-detail
                 'role role (emacsvox-aural-input-role input)))))
          (unless detail (throw 'no-match 'no-match))
          (push detail details)))
      (dolist (event events)
        (let ((detail
               (emacsvox-aural--best-semantic-match
                'event event (emacsvox-aural-input-events input))))
          (unless detail (throw 'no-match 'no-match))
          (push detail details)))
      (dolist (state states)
        (let ((detail
               (emacsvox-aural--best-semantic-match
                'state state (emacsvox-aural-input-states input))))
          (unless detail (throw 'no-match 'no-match))
          (push detail details)))
      (dolist (attribute attributes)
        (let ((detail
               (emacsvox-aural--best-semantic-match
                'attribute
                (car attribute)
                (emacsvox-aural-input-attributes input)
                (cdr attribute))))
          (unless detail (throw 'no-match 'no-match))
          (push detail details)))
      (dolist (attribute required)
        (let ((detail
               (emacsvox-aural--best-semantic-match
                'attribute
                attribute
                (emacsvox-aural-input-attributes input)
                :emacsvox-aural-any)))
          (unless detail (throw 'no-match 'no-match))
          (push detail details)))
      (nreverse details))))

(defun emacsvox-aural-rule-matches-p (rule input)
  "Return non-nil when compiled RULE matches normalized INPUT."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (module (emacsvox-aural-selector-module selector))
         (mode (emacsvox-aural-selector-mode selector))
         (occasion (emacsvox-aural-selector-occasion selector))
         (legacy-cue (emacsvox-aural-selector-legacy-cue selector))
         (legacy-face (emacsvox-aural-selector-legacy-face selector))
         (legacy-personality
          (emacsvox-aural-selector-legacy-personality selector)))
    (and
     (emacsvox-aural-rule-enabled rule)
     (not
      (eq
       (emacsvox-aural-rule-semantic-matches rule input)
       'no-match))
     (or (null module) (eq module (emacsvox-aural-input-module input)))
     (or (null mode) (numberp (emacsvox-aural--mode-distance selector input)))
     (or
      (null occasion)
      (eq occasion (emacsvox-aural-input-occasion input)))
     (or
      (null legacy-cue)
      (eq legacy-cue (emacsvox-aural-input-legacy-cue input)))
     (or
      (null legacy-face)
      (and
       (emacsvox-aural-input-face-presentation-enabled input)
       (memq legacy-face (emacsvox-aural-input-legacy-faces input))))
     (or
      (null legacy-personality)
      (and
       (emacsvox-aural-input-voice-lock-enabled input)
       (equal
        legacy-personality
        (emacsvox-aural-input-legacy-personality input)))))))

(defun emacsvox-aural-rule-score (rule input)
  "Return RULE specificity vector for normalized INPUT."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (origin
          (alist-get
           (emacsvox-aural-rule-origin rule)
           emacsvox-aural-origin-ranks))
         (identity
          (+ (if (emacsvox-aural-selector-role selector) 1 0)
             (length (emacsvox-aural-selector-events selector))))
         (semantic-details
          (emacsvox-aural-rule-semantic-matches rule input))
         (semantic-closeness
          (if (eq semantic-details 'no-match)
              0
            (-
             (cl-loop
              for detail in semantic-details
              sum (plist-get detail :distance)))))
         (module (emacsvox-aural-selector-module selector))
         (mode (emacsvox-aural-selector-mode selector))
         (distance (and mode (emacsvox-aural--mode-distance selector input)))
         (face-distance (emacsvox-aural--face-distance selector input))
         (combined-exact
          (if (and module mode (numberp distance) (zerop distance)) 1 0))
         (mode-rank
          (cond
           ((null mode) 0)
           ((and (numberp distance) (zerop distance)) 2)
           ((numberp distance) 1)
           (t 1)))
         (mode-closeness (if distance (- distance) 0))
         (constraints
          (+ (length (emacsvox-aural-selector-states selector))
             (length (emacsvox-aural-selector-attributes selector))
             (length
              (emacsvox-aural-selector-required-attributes selector))
             (if (emacsvox-aural-selector-legacy-cue selector) 1 0)
             (if (emacsvox-aural-selector-legacy-face selector) 1 0)
             (if
                 (emacsvox-aural-selector-legacy-personality selector)
                 1
               0))))
    (vector
     origin
     identity
     semantic-closeness
     combined-exact
     mode-rank
     mode-closeness
     (if module 1 0)
     constraints
     (if face-distance (- face-distance) 0)
     (emacsvox-aural-rule-layer-order rule)
     (emacsvox-aural-rule-order rule))))

(defun emacsvox-aural--score-less-p (left right)
  "Return non-nil when specificity vector LEFT is weaker than RIGHT."
  (catch 'comparison
    (dotimes (index (length left))
      (let ((l (aref left index))
            (r (aref right index)))
        (cond
         ((< l r) (throw 'comparison t))
         ((> l r) (throw 'comparison nil)))))
    nil))

(defun emacsvox-aural-matching-rules (rules input)
  "Return matching RULES sorted from weakest to strongest for INPUT."
  (let (matches)
    (dolist (rule rules)
      (when (emacsvox-aural-rule-matches-p rule input)
        (push (cons (emacsvox-aural-rule-score rule input) rule) matches)))
    (mapcar
     #'cdr
     (sort
      matches
      (lambda (left right)
        (let ((left-score (car left))
              (right-score (car right)))
          (if (equal left-score right-score)
              (string-lessp
               (symbol-name (emacsvox-aural-rule-id (cdr left)))
               (symbol-name (emacsvox-aural-rule-id (cdr right))))
            (emacsvox-aural--score-less-p left-score right-score))))))))

(defun emacsvox-aural--best-rule-match (rule inputs)
  "Return RULE's strongest (SCORE . INPUT) match in normalized INPUTS."
  (let (best-input best-score)
    (dolist (input inputs)
      (when (emacsvox-aural-rule-matches-p rule input)
        (let ((score (emacsvox-aural-rule-score rule input)))
          (when
              (or
               (null best-score)
               (emacsvox-aural--score-less-p best-score score))
            (setq best-input input
                  best-score score)))))
    (and best-score (cons best-score best-input))))

(defun emacsvox-aural--matching-rules-for-inputs (rules inputs)
  "Return scored RULES matching any normalized member of INPUTS.

Each result is (SCORE RULE INPUT), retaining the strongest matching input so
several lifecycle plans can reuse the same matching work."
  (let (matches)
    (dolist (rule rules)
      (when-let* ((best (emacsvox-aural--best-rule-match rule inputs)))
        (push (list (car best) rule (cdr best)) matches)))
    (sort
     matches
     (lambda (left right)
       (let ((left-score (car left))
             (right-score (car right)))
         (if (equal left-score right-score)
             (string-lessp
              (symbol-name (emacsvox-aural-rule-id (cadr left)))
              (symbol-name (emacsvox-aural-rule-id (cadr right))))
           (emacsvox-aural--score-less-p left-score right-score)))))))

(defun emacsvox-aural--fallback-list-distance (general specific)
  "Return fallback distance from SPECIFIC list to GENERAL list, or nil."
  (when (= (length general) (length specific))
    (let ((distance 0)
          valid)
      (setq valid t)
      (cl-mapc
       (lambda (general-id specific-id)
         (let ((item-distance
                (emacsvox-aural-semantic-distance
                 general-id specific-id)))
           (if (numberp item-distance)
               (setq distance (+ distance item-distance))
             (setq valid nil))))
       general specific)
      (and valid distance))))

(defun emacsvox-aural--fallback-attribute-distance (general specific)
  "Return fallback distance from SPECIFIC attributes to GENERAL, or nil."
  (when (= (length general) (length specific))
    (let ((distance 0)
          valid)
      (setq valid t)
      (cl-mapc
       (lambda (general-entry specific-entry)
         (let ((item-distance
                (and
                 (equal (cdr general-entry) (cdr specific-entry))
                 (emacsvox-aural-semantic-distance
                  (car general-entry) (car specific-entry)))))
           (if (numberp item-distance)
               (setq distance (+ distance item-distance))
             (setq valid nil))))
       general specific)
      (and valid distance))))

(defun emacsvox-aural-selector-fallback-distance (general specific)
  "Return positive fallback distance from SPECIFIC selector to GENERAL.

Return nil unless all non-semantic selector constraints are equal and the
semantic selections have the same shape.  Exact selectors return nil because
they do not form a fallback-shadow relationship."
  (let* ((context-accessors
          '(emacsvox-aural-selector-module
            emacsvox-aural-selector-mode
            emacsvox-aural-selector-occasion
            emacsvox-aural-selector-legacy-cue
            emacsvox-aural-selector-legacy-face
            emacsvox-aural-selector-legacy-personality))
         (context-equal
          (cl-every
           (lambda (accessor)
             (equal
              (funcall accessor general)
              (funcall accessor specific)))
           context-accessors))
         (general-role (emacsvox-aural-selector-role general))
         (specific-role (emacsvox-aural-selector-role specific))
         (role-distance
          (cond
           ((and (null general-role) (null specific-role)) 0)
           ((and general-role specific-role)
            (emacsvox-aural-semantic-distance
             general-role specific-role))
           (t nil)))
         (event-distance
          (emacsvox-aural--fallback-list-distance
           (emacsvox-aural-selector-events general)
           (emacsvox-aural-selector-events specific)))
         (state-distance
          (emacsvox-aural--fallback-list-distance
           (emacsvox-aural-selector-states general)
           (emacsvox-aural-selector-states specific)))
         (attribute-distance
          (emacsvox-aural--fallback-attribute-distance
           (emacsvox-aural-selector-attributes general)
           (emacsvox-aural-selector-attributes specific)))
         (required-distance
          (emacsvox-aural--fallback-list-distance
           (emacsvox-aural-selector-required-attributes general)
           (emacsvox-aural-selector-required-attributes specific))))
    (when
        (and
         context-equal
         (numberp role-distance)
         (numberp event-distance)
         (numberp state-distance)
         (numberp attribute-distance)
         (numberp required-distance))
      (let ((total
             (+ role-distance event-distance state-distance
                attribute-distance required-distance)))
        (and (> total 0) total)))))

(defun emacsvox-aural-fallback-shadow-diagnostics (rules)
  "Return stable fallback-overlap diagnostics for compiled RULES."
  (let (diagnostics)
    (while rules
      (let ((left (pop rules)))
        (dolist (right rules)
          (let* ((left-selector (emacsvox-aural-rule-selector left))
                 (right-selector (emacsvox-aural-rule-selector right))
                 (left-distance
                  (emacsvox-aural-selector-fallback-distance
                   left-selector right-selector))
                 (right-distance
                  (emacsvox-aural-selector-fallback-distance
                   right-selector left-selector)))
            (cond
             (left-distance
              (push
               (list
                :general (emacsvox-aural-rule-id left)
                :specific (emacsvox-aural-rule-id right)
                :distance left-distance)
               diagnostics))
             (right-distance
              (push
               (list
                :general (emacsvox-aural-rule-id right)
                :specific (emacsvox-aural-rule-id left)
                :distance right-distance)
               diagnostics)))))))
    (nreverse diagnostics)))

(defun emacsvox-aural--remove-actions (actions ids)
  "Return ACTIONS without actions whose identifiers occur in IDS."
  (cl-remove-if
   (lambda (action) (memq (emacsvox-aural-action-id action) ids))
   actions))

(defun emacsvox-aural--actions-at-anchor (actions anchor)
  "Return ACTIONS whose lifecycle matches ANCHOR.

When ANCHOR is nil, retain every action for compatibility callers that
resolve an undivided render plan."
  (if (null anchor)
      (copy-sequence actions)
    (cl-remove-if-not
     (lambda (action)
       (eq (emacsvox-aural-action-anchor action) anchor))
     actions)))

(defun emacsvox-aural--apply-phase (actions operations &optional anchor)
  "Apply phase OPERATIONS to current ACTIONS for ANCHOR.

An omitted ANCHOR retains the original undivided resolution behavior."
  (cond
   ((and
     (emacsvox-aural-phase-operations-suppress operations)
     (or
      (null anchor)
      (eq
       anchor
       (emacsvox-aural-phase-operations-anchor operations))))
    nil)
   (t
    (let* ((operation-applies
            (or
             (null anchor)
             (eq
              anchor
              (emacsvox-aural-phase-operations-anchor operations))))
           (result
            (if
                (and
                 operation-applies
                 (emacsvox-aural-phase-operations-replace-set-p operations))
                (emacsvox-aural--actions-at-anchor
                 (emacsvox-aural-phase-operations-replace operations)
                 anchor)
              (copy-sequence actions))))
      (when operation-applies
        (setq
         result
         (emacsvox-aural--remove-actions
          result (emacsvox-aural-phase-operations-remove operations))))
      (append
       (emacsvox-aural--actions-at-anchor
        (emacsvox-aural-phase-operations-prepend operations)
        anchor)
       result
       (emacsvox-aural--actions-at-anchor
        (emacsvox-aural-phase-operations-append operations)
        anchor))))))

(defun emacsvox-aural--set-content-provenance (content property rule-id)
  "Record that RULE-ID selected PROPERTY on CONTENT."
  (setf
   (emacsvox-aural-content-style-provenance content)
   (cons
    (cons property rule-id)
    (assq-delete-all
     property (emacsvox-aural-content-style-provenance content)))))

(defun emacsvox-aural--acss-to-voice-style (value)
  "Convert raw ACSS VALUE to a partial declarative voice style."
  (let (style)
    (dolist (dimension emacsvox-aural-voice-dimensions)
      (let* ((accessor (intern (format "acss-%s" dimension)))
             (dimension-value
              (and (fboundp accessor) (funcall accessor value))))
        (when dimension-value
          (setq
           style
           (plist-put
            style
            (emacsvox-aural--voice-dimension-key dimension)
            dimension-value)))))
    style))

(defun emacsvox-aural--canonical-voice-style (voice)
  "Return composable VOICE as a declarative style plist."
  (cond
   ((emacsvox-aural-voice-style-p voice) (copy-tree voice))
   ((emacsvox-aural--acss-p voice)
    (emacsvox-aural--acss-to-voice-style voice))
   (t nil)))

(defun emacsvox-aural--set-voice-provenance
    (content property rule-id)
  "Record RULE-ID as the provider of voice PROPERTY on CONTENT."
  (setf
   (emacsvox-aural-content-style-voice-provenance content)
   (cons
    (cons property rule-id)
    (assq-delete-all
     property
     (emacsvox-aural-content-style-voice-provenance content)))))

(defun emacsvox-aural--reset-voice-provenance (content rule-id)
  "Record RULE-ID as the complete voice provider on CONTENT."
  (setf
   (emacsvox-aural-content-style-voice-provenance content)
   (mapcar
    (lambda (property) (cons property rule-id))
    (cons 'preset emacsvox-aural-voice-dimensions))))

(defun emacsvox-aural--apply-voice (content voice rule-id)
  "Apply declarative VOICE from RULE-ID to CONTENT.

Named voices replace the complete inherited voice.  Explicit style data
overrides only the dimensions it mentions, unless it includes `:preset',
which establishes a new complete base before applying those dimensions."
  (if (or
       (emacsvox-aural-voice-style-p voice)
       (emacsvox-aural--acss-p voice))
      (let* ((incoming (emacsvox-aural--canonical-voice-style voice))
             (current (emacsvox-aural-content-style-voice content))
             (result
              (cond
               ((emacsvox-aural-voice-style-p current)
                (copy-tree current))
               ((emacsvox-aural--acss-p current)
                (emacsvox-aural--canonical-voice-style current))
               (current (list :preset current))
               (t nil))))
        (when (plist-member incoming :preset)
          (setq result (list :preset (plist-get incoming :preset)))
          (emacsvox-aural--reset-voice-provenance content rule-id))
        (dolist (dimension emacsvox-aural-voice-dimensions)
          (let ((key (emacsvox-aural--voice-dimension-key dimension)))
            (when (plist-member incoming key)
              (setq result (plist-put result key (plist-get incoming key)))
              (emacsvox-aural--set-voice-provenance
               content dimension rule-id))))
        (setf (emacsvox-aural-content-style-voice content) result))
    (setf (emacsvox-aural-content-style-voice content) voice)
    (emacsvox-aural--reset-voice-provenance content rule-id)))

(defun emacsvox-aural--apply-content (content patch rule-id)
  "Apply scalar content PATCH from RULE-ID to CONTENT."
  (when (emacsvox-aural-content-patch-suppress patch)
    (setf (emacsvox-aural-content-style-speak content) nil)
    (emacsvox-aural--set-content-provenance content 'speak rule-id))
  (when (emacsvox-aural-content-patch-speak-set-p patch)
    (setf
     (emacsvox-aural-content-style-speak content)
     (emacsvox-aural-content-patch-speak patch))
    (emacsvox-aural--set-content-provenance content 'speak rule-id))
  (when (emacsvox-aural-content-patch-voice-set-p patch)
    (emacsvox-aural--apply-voice
     content (emacsvox-aural-content-patch-voice patch) rule-id)
    (emacsvox-aural--set-content-provenance content 'voice rule-id))
  (when (emacsvox-aural-content-patch-volume-set-p patch)
    (setf
     (emacsvox-aural-content-style-volume content)
     (emacsvox-aural-content-patch-volume patch))
    (emacsvox-aural--set-content-provenance content 'volume rule-id))
  (when (emacsvox-aural-content-patch-space-set-p patch)
    (setf
     (emacsvox-aural-content-style-space content)
     (copy-tree (emacsvox-aural-content-patch-space patch)))
    (emacsvox-aural--set-content-provenance content 'space rule-id))
  content)

(defun emacsvox-aural--resolve-matches (matches anchor)
  "Build one render plan from prepared MATCHES for lifecycle ANCHOR."
  (let ((plan
         (emacsvox-aural--make-render-plan
          :before nil
          :content (emacsvox-aural--make-content-style :speak t)
          :after nil
          :matched-rules nil
          :rule-scores nil
          :semantic-matches nil)))
    (dolist (match matches)
      (let* ((score (car match))
             (rule (cadr match))
             (contribution (emacsvox-aural-rule-contribution rule))
             (rule-id (emacsvox-aural-rule-id rule))
             (best-input (caddr match)))
        (setf
         (emacsvox-aural-render-plan-before plan)
         (emacsvox-aural--apply-phase
          (emacsvox-aural-render-plan-before plan)
          (emacsvox-aural-contribution-before contribution)
          anchor))
        (emacsvox-aural--apply-content
         (emacsvox-aural-render-plan-content plan)
         (emacsvox-aural-contribution-content contribution)
         rule-id)
        (setf
         (emacsvox-aural-render-plan-after plan)
         (emacsvox-aural--apply-phase
          (emacsvox-aural-render-plan-after plan)
          (emacsvox-aural-contribution-after contribution)
          anchor))
        (setf
         (emacsvox-aural-render-plan-matched-rules plan)
         (append
          (emacsvox-aural-render-plan-matched-rules plan)
          (list rule-id)))
        (setf
         (emacsvox-aural-render-plan-rule-scores plan)
         (append
          (emacsvox-aural-render-plan-rule-scores plan)
          (list
           (cons rule-id score))))
        (setf
         (emacsvox-aural-render-plan-semantic-matches plan)
         (append
          (emacsvox-aural-render-plan-semantic-matches plan)
          (list
           (cons
            rule-id
            (emacsvox-aural-rule-semantic-matches
             rule best-input)))))))
    plan))

(defun emacsvox-aural--resolve-inputs-for-anchors (inputs rules anchors)
  "Resolve INPUTS through RULES once for each lifecycle in ANCHORS.

Return an alist whose keys retain ANCHORS' order and whose values are distinct
render plans sharing only immutable normalized and matching work."
  (unless (and (consp inputs) (cl-every #'consp inputs))
    (emacsvox-aural--rule-error
     "Aural resolution requires nonempty (facts . context) inputs: %S"
     inputs))
  (unless (consp anchors)
    (emacsvox-aural--rule-error
     "Aural resolution requires at least one lifecycle anchor"))
  (dolist (anchor anchors)
    (when
        (and anchor (not (memq anchor emacsvox-aural-action-anchors)))
      (emacsvox-aural--rule-error "Invalid resolution anchor: %S" anchor)))
  (let* ((normalized
          (mapcar
           (lambda (input)
             (emacsvox-aural-normalize-input (car input) (cdr input)))
           inputs))
         (matches
          (emacsvox-aural--matching-rules-for-inputs rules normalized)))
    (mapcar
     (lambda (anchor)
       (cons anchor (emacsvox-aural--resolve-matches matches anchor)))
     anchors)))

(defun emacsvox-aural-resolve-inputs (inputs rules &optional anchor)
  "Resolve semantic INPUTS through compiled RULES for optional ANCHOR.

INPUTS is a nonempty list of (FACTS . CONTEXT) pairs belonging to one aural
object.  Rules matching several formatting runs contribute once at their
strongest score.  ANCHOR is nil for the compatibility undivided plan, or one
of `object', `run', and `transition'."
  (cdar
   (emacsvox-aural--resolve-inputs-for-anchors
    inputs rules (list anchor))))

(defun emacsvox-aural-resolve (facts context rules &optional anchor)
  "Resolve semantic FACTS and CONTEXT through compiled RULES.

Optional ANCHOR limits ordered actions to one lifecycle.  Content styling
continues to resolve for formatting-run compilation."
  (emacsvox-aural-resolve-inputs
   (list (cons facts context)) rules anchor))

(provide 'emacsvox-aural-rules)

;;; emacsvox-aural-rules.el ends here
