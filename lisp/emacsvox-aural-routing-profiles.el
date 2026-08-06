;;; emacsvox-aural-routing-profiles.el --- Machine routing for voices -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Store physical-engine routing separately from portable ACSS voice palettes.
;; Property selectors can travel between machines, exact native identifiers
;; require explicit local scope, and session selectors are never persisted.

;;; Code:

(require 'cl-lib)
(require 'pp)
(require 'subr-x)
(require 'emacsvox-preamble)

(defvar read-eval)
(defvar omnivox-logical-voice-preferences nil)
(defvar omnivox-logical-voice-languages nil)
(defvar omnivox-engine-priority-ids nil)
(defvar omnivox-fallback-engine-ids '("espeak"))
(defvar omnivox-disabled-engine-ids nil)
(defvar omnivox-global-default-selector nil)
(defvar omnivox-allow-same-language-fallback t)

(declare-function omnivox-register-logical-voices "omnivox-voices" ())
(declare-function omnivox-set-routing-policy "omnivox-voices" ())
(declare-function emacsvox-aural-voice "emacsvox-aural-resources"
                  (name &optional palette-id))

(define-error
  'emacsvox-aural-routing-profile-error
  "Invalid Emacsvox voice routing profile")

(defconst emacsvox-aural-routing-profile-schema-version 2
  "Current data schema for one routing profile.")

(defconst emacsvox-aural-routing-user-data-schema-version 1
  "Current data schema for the machine-local routing file.")

(defcustom emacsvox-aural-routing-profiles-file
  (expand-file-name "aural-routing-profiles.el" emacsvox-user-directory)
  "Data-only file containing machine-local voice routing profiles.

This file is deliberately separate from portable voice palettes.  It may
contain explicitly local physical voice IDs and should not be synchronized
unless the user has reviewed those bindings."
  :type 'file
  :group 'emacsvox-aural)

(cl-defstruct
    (emacsvox-aural-routing-profile-entry
     (:constructor emacsvox-aural-routing--make-entry))
  "One validated physical-voice routing profile."
  id data source)

(defvar emacsvox-aural-routing-profile-registry
  (make-hash-table :test #'eq)
  "Map routing profile identifiers to validated entries.")

(defvar emacsvox-aural-active-routing-profile nil
  "Identifier of the active machine routing profile, or nil.")

(defvar emacsvox-aural-session-routing-bindings nil
  "Temporary logical-voice routing overrides for this Emacs session.

Each entry is (LOGICAL-VOICE . SELECTORS).  Session bindings replace the
active profile's selectors for that logical voice and are never saved.")

(defvar emacsvox-aural-routing-profile-changed-hook nil
  "Hook run after routing profiles or their active selection change.")

(defun emacsvox-aural-routing--error (format-string &rest arguments)
  "Signal a routing error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-routing-profile-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural-routing--plist-p (value)
  "Return non-nil when VALUE is a proper keyword plist."
  (and (proper-list-p value)
       (cl-evenp (length value))
       (cl-loop for (key _) on value by #'cddr always (keywordp key))))

(defun emacsvox-aural-routing--require-plist (value description)
  "Require VALUE to be a plist described by DESCRIPTION."
  (unless (emacsvox-aural-routing--plist-p value)
    (emacsvox-aural-routing--error "%s must be a keyword plist" description))
  value)

(defun emacsvox-aural-routing--reject-unknown-keys
    (value allowed description)
  "Reject keys in VALUE outside ALLOWED for DESCRIPTION."
  (let (unknown)
    (cl-loop
     for (key _) on value by #'cddr
     unless (memq key allowed)
     do (push key unknown))
    (when unknown
      (emacsvox-aural-routing--error
       "%s has unknown keys: %S" description (nreverse unknown)))))

(defun emacsvox-aural-routing--require-id (value description)
  "Return nonempty string VALUE described by DESCRIPTION."
  (unless (and (stringp value) (not (string-empty-p value)))
    (emacsvox-aural-routing--error "%s must be a nonempty string" description))
  value)

(defun emacsvox-aural-routing--logical-name (value)
  "Return the stable string form of logical voice VALUE."
  (unless (or (and value (symbolp value))
              (and (stringp value) (not (string-empty-p value))))
    (emacsvox-aural-routing--error
     "Logical voice must be a symbol or nonempty string: %S" value))
  (if (symbolp value) (symbol-name value) value))

(defun emacsvox-aural-routing--validate-engine-list (engines description)
  "Validate and copy ordered ENGINES described by DESCRIPTION."
  (unless (proper-list-p engines)
    (emacsvox-aural-routing--error "%s must be a list" description))
  (let (seen result)
    (dolist (engine engines)
      (emacsvox-aural-routing--require-id engine description)
      (when (member engine seen)
        (emacsvox-aural-routing--error
         "%s contains duplicate engine %S" description engine))
      (push engine seen)
      (push engine result))
    (nreverse result)))

(defun emacsvox-aural-validate-routing-selector (selector &optional persisted)
  "Validate and normalize routing SELECTOR.

When PERSISTED is non-nil, reject temporary session scope.  Exact physical
voice IDs require local or session scope and can never be portable."
  (emacsvox-aural-routing--require-plist selector "Routing selector")
  (emacsvox-aural-routing--reject-unknown-keys
   selector '(:kind :scope :engine-id :voice-id :language :gender)
   "Routing selector")
  (let* ((kind (plist-get selector :kind))
         (scope (or (plist-get selector :scope) 'portable))
         (engine-id (plist-get selector :engine-id))
         (voice-id (plist-get selector :voice-id))
         (language (plist-get selector :language))
         (gender (plist-get selector :gender)))
    (unless (memq kind '(exact engine-default properties))
      (emacsvox-aural-routing--error
       "Unknown routing selector kind: %S" kind))
    (unless (memq scope '(portable local session))
      (emacsvox-aural-routing--error "Unknown routing scope: %S" scope))
    (when (and persisted (eq scope 'session))
      (emacsvox-aural-routing--error
       "Session routing selectors cannot be persisted"))
    (pcase kind
      ('exact
       (when (eq scope 'portable)
         (emacsvox-aural-routing--error
          "Exact physical voice IDs require local or session scope"))
       (emacsvox-aural-routing--require-id engine-id "Exact engine ID")
       (emacsvox-aural-routing--require-id voice-id "Exact voice ID")
       (list :kind 'exact :scope scope
             :engine-id engine-id :voice-id voice-id))
      ('engine-default
       (emacsvox-aural-routing--require-id engine-id "Engine-default ID")
       (list :kind 'engine-default :scope scope :engine-id engine-id))
      ('properties
       (when engine-id
         (emacsvox-aural-routing--require-id engine-id "Property engine ID"))
       (when (and language
                  (not (and (stringp language)
                            (not (string-empty-p language)))))
         (emacsvox-aural-routing--error
          "Selector language must be a nonempty string"))
       (when gender
         (unless (or (symbolp gender) (stringp gender))
           (emacsvox-aural-routing--error
            "Selector gender must be female, male, or neutral"))
         (setq gender
               (intern
                (downcase
                 (if (symbolp gender) (symbol-name gender) gender))))
         (unless (memq gender '(female male neutral))
           (emacsvox-aural-routing--error
            "Selector gender must be female, male, or neutral")))
       (append
        (list :kind 'properties :scope scope)
        (and engine-id (list :engine-id engine-id))
        (and language (list :language language))
        (and gender (list :gender gender)))))))

(defun emacsvox-aural-routing--validate-binding (binding)
  "Validate and normalize one persisted logical voice BINDING."
  (emacsvox-aural-routing--require-plist binding "Routing binding")
  (emacsvox-aural-routing--reject-unknown-keys
   binding '(:logical-voice :language :selectors) "Routing binding")
  (let ((voice (plist-get binding :logical-voice))
        (language (plist-get binding :language))
        (selectors (plist-get binding :selectors)))
    (emacsvox-aural-routing--logical-name voice)
    (when (and language
               (not (and (stringp language) (not (string-empty-p language)))))
      (emacsvox-aural-routing--error
       "Routing binding language must be a nonempty string"))
    (unless (proper-list-p selectors)
      (emacsvox-aural-routing--error "Routing selectors must be a list"))
    (append
     (list :logical-voice voice)
     (and language (list :language language))
     (list
      :selectors
      (mapcar
       (lambda (selector)
         (emacsvox-aural-validate-routing-selector selector t))
       selectors)))))

(defun emacsvox-aural-validate-routing-profile-data (data)
  "Validate and return a normalized copy of routing profile DATA."
  (emacsvox-aural-routing--require-plist data "Routing profile")
  (emacsvox-aural-routing--reject-unknown-keys
   data
   '(:schema-version :id :summary :engine-order :disabled-engines
     :fallback :bindings)
   "Routing profile")
  (let ((version (plist-get data :schema-version))
        (id (plist-get data :id))
        (summary (or (plist-get data :summary) ""))
        (engine-order (plist-get data :engine-order))
        (disabled-engines (plist-get data :disabled-engines))
        (fallback (or (plist-get data :fallback) '()))
        (bindings (plist-get data :bindings))
        seen)
    (unless (memq version '(1 2))
      (emacsvox-aural-routing--error
       "Unsupported routing profile version: %S" version))
    (unless (and id (symbolp id))
      (emacsvox-aural-routing--error "Routing profile ID must be a symbol"))
    (unless (stringp summary)
      (emacsvox-aural-routing--error "Routing profile summary must be a string"))
    (setq engine-order
          (emacsvox-aural-routing--validate-engine-list
           engine-order "Engine order"))
    (setq disabled-engines
          (emacsvox-aural-routing--validate-engine-list
           disabled-engines "Disabled engines"))
    (emacsvox-aural-routing--require-plist fallback "Fallback policy")
    (emacsvox-aural-routing--reject-unknown-keys
     fallback
     '(:allow-same-language :global-default :engines)
     "Fallback policy")
    (let ((allow (plist-get fallback :allow-same-language))
          (global (plist-get fallback :global-default))
          (engines (plist-get fallback :engines)))
      (unless (booleanp allow)
        (emacsvox-aural-routing--error
         "Fallback allow-same-language must be boolean"))
      (setq fallback
            (list
             :allow-same-language allow
             :global-default
             (and global
                  (emacsvox-aural-validate-routing-selector global t))
             :engines
             (emacsvox-aural-routing--validate-engine-list
              engines "Fallback engines"))))
    (unless (proper-list-p bindings)
      (emacsvox-aural-routing--error "Routing bindings must be a list"))
    (setq bindings
          (mapcar #'emacsvox-aural-routing--validate-binding bindings))
    (dolist (binding bindings)
      (let ((name
             (emacsvox-aural-routing--logical-name
              (plist-get binding :logical-voice))))
        (when (member name seen)
          (emacsvox-aural-routing--error
           "Duplicate logical voice binding: %s" name))
        (push name seen)))
    (list
     :schema-version emacsvox-aural-routing-profile-schema-version
     :id id :summary summary
     :engine-order engine-order :disabled-engines disabled-engines
     :fallback fallback :bindings bindings)))

(defun emacsvox-aural-routing-profile (id)
  "Return the registered routing profile entry named ID."
  (gethash id emacsvox-aural-routing-profile-registry))

(defun emacsvox-aural-register-routing-profile-data
    (data &optional source replace)
  "Validate and register routing profile DATA from SOURCE.

When REPLACE is nil, reject an existing profile with the same identifier."
  (let* ((validated (emacsvox-aural-validate-routing-profile-data data))
         (id (plist-get validated :id)))
    (when (and (gethash id emacsvox-aural-routing-profile-registry)
               (not replace))
      (emacsvox-aural-routing--error
       "Routing profile already exists: %S" id))
    (let ((entry
           (emacsvox-aural-routing--make-entry
            :id id :data validated :source source)))
      (puthash id entry emacsvox-aural-routing-profile-registry)
      (run-hooks 'emacsvox-aural-routing-profile-changed-hook)
      entry)))

(defun emacsvox-aural-routing--binding (logical-voice bindings)
  "Return LOGICAL-VOICE's entry from BINDINGS."
  (let ((name (emacsvox-aural-routing--logical-name logical-voice)))
    (cl-find-if
     (lambda (binding)
       (equal
        name
        (emacsvox-aural-routing--logical-name
         (plist-get binding :logical-voice))))
     bindings)))

(defun emacsvox-aural-routing-explicit-selectors-from-data
    (logical-voice data &optional include-session)
  "Return explicit selectors for LOGICAL-VOICE in profile DATA.

A session binding replaces saved selectors when INCLUDE-SESSION is non-nil.
Global engine order is deliberately excluded from this projection."
  (let* ((logical-name
          (emacsvox-aural-routing--logical-name logical-voice))
         (session
          (and
           include-session
           (cl-find-if
            (lambda (entry)
              (equal
               logical-name
               (emacsvox-aural-routing--logical-name (car entry))))
            emacsvox-aural-session-routing-bindings)))
         (binding
          (and data
               (emacsvox-aural-routing--binding
                logical-voice (plist-get data :bindings))))
         (selectors (if session (cdr session) (plist-get binding :selectors))))
    (copy-tree selectors)))

(defun emacsvox-aural-routing-selectors-from-data
    (logical-voice data &optional include-session)
  "Return effective ordered selectors for LOGICAL-VOICE in profile DATA.

A session binding replaces saved selectors when INCLUDE-SESSION is non-nil.
Otherwise saved selectors are followed by distinct engine defaults from the
profile's global engine order.  This effective projection is for display and
legacy adapters; current Omnivox receives the global order separately."
  (let* ((logical-name
          (emacsvox-aural-routing--logical-name logical-voice))
         (session
          (and
           include-session
           (cl-find-if
            (lambda (entry)
              (equal
               logical-name
               (emacsvox-aural-routing--logical-name (car entry))))
            emacsvox-aural-session-routing-bindings)))
         (selectors
          (emacsvox-aural-routing-explicit-selectors-from-data
           logical-voice data include-session))
         (used-engines
          (delq nil (mapcar (lambda (selector)
                              (plist-get selector :engine-id))
                            selectors))))
    (if session
        selectors
      (dolist (engine (plist-get data :engine-order))
        (unless (member engine used-engines)
          (setq selectors
                (append
                 selectors
                 (list
                  (list :kind 'engine-default :scope 'portable
                        :engine-id engine))))))
      selectors)))

(defun emacsvox-aural-routing-selectors (logical-voice &optional profile-id)
  "Return effective ordered selectors for LOGICAL-VOICE and PROFILE-ID."
  (let* ((entry
          (emacsvox-aural-routing-profile
           (or profile-id emacsvox-aural-active-routing-profile)))
         (data (and entry (emacsvox-aural-routing-profile-entry-data entry))))
    (emacsvox-aural-routing-selectors-from-data logical-voice data t)))

(defun emacsvox-aural-set-session-routing-binding
    (logical-voice selectors)
  "Set temporary SELECTORS for LOGICAL-VOICE, or clear it when nil."
  (let* ((name (emacsvox-aural-routing--logical-name logical-voice))
         (normalized
          (mapcar
           (lambda (selector)
             (let ((copy (copy-tree selector)))
               (setq copy (plist-put copy :scope 'session))
               (emacsvox-aural-validate-routing-selector copy)))
           selectors)))
    (setq emacsvox-aural-session-routing-bindings
          (cl-remove-if
           (lambda (entry)
             (equal name
                    (emacsvox-aural-routing--logical-name (car entry))))
           emacsvox-aural-session-routing-bindings))
    (when selectors
      (push (cons logical-voice normalized)
            emacsvox-aural-session-routing-bindings))
    (run-hooks 'emacsvox-aural-routing-profile-changed-hook)
    normalized))

(defun emacsvox-aural-routing--style-family (definition)
  "Return the requested ACSS family from voice DEFINITION, or nil."
  (cond
   ((and (recordp definition)
         (> (length definition) 1)
         (eq (aref definition 0) 'acss))
    (aref definition 1))
   ((and (listp definition) (plist-member definition :family))
    (plist-get definition :family))
   ((and (symbolp definition) (boundp definition))
    (emacsvox-aural-routing--style-family (symbol-value definition)))))

(defun emacsvox-aural-routing-family-diagnostics
    (logical-voice &optional palette-id)
  "Diagnose ACSS family interaction for routed LOGICAL-VOICE.

When PALETTE-ID is available, LOGICAL-VOICE may name a palette entry.  An
exact selector owns physical voice selection; the family remains a portable
fallback request and its possible trait mismatch is reported rather than
silently changing either saved layer."
  (let* ((definition
          (or
           (and (fboundp 'emacsvox-aural-voice)
                (ignore-errors
                  (emacsvox-aural-voice logical-voice palette-id)))
           logical-voice))
         (family (emacsvox-aural-routing--style-family definition))
         (selectors (emacsvox-aural-routing-selectors logical-voice))
         diagnostics)
    (when family
      (cl-loop
       for selector in selectors
       for index from 0
       when (eq (plist-get selector :kind) 'exact)
       do
       (push
        (list
         :kind 'exact-route-overrides-family
         :severity 'info
         :logical-voice logical-voice
         :selector-index index
         :engine-id (plist-get selector :engine-id)
         :voice-id (plist-get selector :voice-id)
         :requested-family family
         :message
         (format
          (concat
           "Exact route %s/%s selects the physical voice; ACSS family %s "
           "is retained only for portable fallback")
          (plist-get selector :engine-id)
          (plist-get selector :voice-id) family))
        diagnostics)))
    (nreverse diagnostics)))

(defun emacsvox-aural-routing--selector-from-omnivox (selector)
  "Convert one legacy Omnivox SELECTOR to routing-profile data."
  (pcase selector
    (`(exact ,engine-id ,voice-id)
     (list :kind 'exact :scope 'local
           :engine-id engine-id :voice-id voice-id))
    (`(engine-default ,engine-id)
     (list :kind 'engine-default :scope 'portable :engine-id engine-id))
    (`(properties . ,properties)
     (append
      (list :kind 'properties :scope 'portable)
      (and (plist-get properties :engine)
           (list :engine-id (plist-get properties :engine)))
      (and (plist-get properties :language)
           (list :language (plist-get properties :language)))
      (and (plist-get properties :gender)
           (list :gender (plist-get properties :gender)))))
    (_ (emacsvox-aural-routing--error
        "Invalid existing Omnivox selector: %S" selector))))

(defun emacsvox-aural-routing--selector-to-omnivox (selector)
  "Convert routing profile SELECTOR to the Omnivox Customize form."
  (pcase (plist-get selector :kind)
    ('exact
     (list 'exact (plist-get selector :engine-id)
           (plist-get selector :voice-id)))
    ('engine-default
     (list 'engine-default (plist-get selector :engine-id)))
    ('properties
     (append
      (list 'properties)
      (and (plist-get selector :engine-id)
           (list :engine (plist-get selector :engine-id)))
      (and (plist-get selector :language)
           (list :language (plist-get selector :language)))
      (and (plist-get selector :gender)
           (list :gender (plist-get selector :gender)))))
    (_ (emacsvox-aural-routing--error
        "Invalid normalized routing selector: %S" selector))))

(defun emacsvox-aural-routing-profile-from-omnivox (id &optional summary)
  "Return staged routing profile ID imported from current Omnivox settings."
  (let (names bindings)
    (dolist (entry omnivox-logical-voice-preferences)
      (push (emacsvox-aural-routing--logical-name (car entry)) names))
    (dolist (entry omnivox-logical-voice-languages)
      (push (emacsvox-aural-routing--logical-name (car entry)) names))
    (dolist (name (sort (delete-dups names) #'string-lessp))
      (let ((preferences
             (cl-find-if
              (lambda (entry)
                (equal name
                       (emacsvox-aural-routing--logical-name (car entry))))
              omnivox-logical-voice-preferences))
            (language
             (cl-find-if
              (lambda (entry)
                (equal name
                       (emacsvox-aural-routing--logical-name (car entry))))
              omnivox-logical-voice-languages)))
        (push
         (append
          (list :logical-voice (car (or preferences language)))
          (and language (list :language (cdr language)))
          (list
           :selectors
           (mapcar #'emacsvox-aural-routing--selector-from-omnivox
                   (cdr preferences))))
         bindings)))
    (emacsvox-aural-validate-routing-profile-data
     (list
      :schema-version emacsvox-aural-routing-profile-schema-version
      :id id :summary (or summary "Imported Omnivox routing")
      :engine-order (copy-sequence omnivox-engine-priority-ids)
      :disabled-engines (copy-sequence omnivox-disabled-engine-ids)
      :fallback
      (list
       :allow-same-language omnivox-allow-same-language-fallback
       :global-default
       (and omnivox-global-default-selector
            (emacsvox-aural-routing--selector-from-omnivox
             omnivox-global-default-selector))
       :engines (copy-sequence omnivox-fallback-engine-ids))
      :bindings (nreverse bindings)))))

(defun emacsvox-aural-apply-routing-profile (&optional id)
  "Atomically apply routing profile ID to Omnivox adapter settings."
  (let* ((id (or id emacsvox-aural-active-routing-profile))
         (entry (emacsvox-aural-routing-profile id)))
    (unless entry
      (emacsvox-aural-routing--error "Unknown routing profile: %S" id))
    (let* ((data (emacsvox-aural-routing-profile-entry-data entry))
           (fallback (plist-get data :fallback))
           (bindings (plist-get data :bindings))
           voices preferences languages)
      (dolist (binding bindings)
        (push (plist-get binding :logical-voice) voices))
      (dolist (session emacsvox-aural-session-routing-bindings)
        (unless
            (cl-find-if
             (lambda (voice)
               (equal
                (emacsvox-aural-routing--logical-name voice)
                (emacsvox-aural-routing--logical-name (car session))))
             voices)
          (push (car session) voices)))
      (dolist (voice (nreverse voices))
        (let* ((binding (emacsvox-aural-routing--binding voice bindings))
               (selectors
                (emacsvox-aural-routing-explicit-selectors-from-data
                 voice data t))
               (language (plist-get binding :language)))
          (when selectors
            (push
             (cons voice
                   (mapcar #'emacsvox-aural-routing--selector-to-omnivox
                           selectors))
             preferences))
          (when language (push (cons voice language) languages))))
      (setq omnivox-logical-voice-preferences (nreverse preferences)
            omnivox-logical-voice-languages (nreverse languages)
            omnivox-engine-priority-ids
            (copy-sequence (plist-get data :engine-order))
            omnivox-fallback-engine-ids
            (copy-sequence (plist-get fallback :engines))
            omnivox-disabled-engine-ids
            (copy-sequence (plist-get data :disabled-engines))
            omnivox-global-default-selector
            (and (plist-get fallback :global-default)
                 (emacsvox-aural-routing--selector-to-omnivox
                  (plist-get fallback :global-default)))
            omnivox-allow-same-language-fallback
            (plist-get fallback :allow-same-language)
            emacsvox-aural-active-routing-profile id)
      (when (fboundp 'omnivox-set-routing-policy)
        (omnivox-set-routing-policy))
      (when (fboundp 'omnivox-register-logical-voices)
        (omnivox-register-logical-voices))
      (run-hooks 'emacsvox-aural-routing-profile-changed-hook)
      id)))

(defun emacsvox-aural-routing-user-data ()
  "Return sorted machine-local routing profile data."
  (let (profiles)
    (maphash
     (lambda (_ entry)
       (push
        (copy-tree (emacsvox-aural-routing-profile-entry-data entry))
        profiles))
     emacsvox-aural-routing-profile-registry)
    (setq profiles
          (sort
           profiles
           (lambda (left right)
             (string-lessp
              (symbol-name (plist-get left :id))
              (symbol-name (plist-get right :id))))))
    (list
     :schema-version emacsvox-aural-routing-user-data-schema-version
     :active-profile emacsvox-aural-active-routing-profile
     :profiles profiles)))

(defun emacsvox-aural-validate-routing-user-data (data)
  "Validate and return machine-local routing user DATA."
  (emacsvox-aural-routing--require-plist data "Routing user data")
  (emacsvox-aural-routing--reject-unknown-keys
   data '(:schema-version :active-profile :profiles) "Routing user data")
  (unless (eq (plist-get data :schema-version)
              emacsvox-aural-routing-user-data-schema-version)
    (emacsvox-aural-routing--error
     "Unsupported routing user data version: %S"
     (plist-get data :schema-version)))
  (let ((active (plist-get data :active-profile))
        (profiles (plist-get data :profiles))
        ids normalized)
    (when (and active (not (symbolp active)))
      (emacsvox-aural-routing--error
       "Active routing profile must be a symbol or nil"))
    (unless (proper-list-p profiles)
      (emacsvox-aural-routing--error "Routing profiles must be a list"))
    (dolist (profile profiles)
      (let* ((validated
              (emacsvox-aural-validate-routing-profile-data profile))
             (id (plist-get validated :id)))
        (when (memq id ids)
          (emacsvox-aural-routing--error
           "Duplicate routing profile: %S" id))
        (push id ids)
        (push validated normalized)))
    (when (and active (not (memq active ids)))
      (emacsvox-aural-routing--error
       "Active routing profile is not saved: %S" active))
    (list
     :schema-version emacsvox-aural-routing-user-data-schema-version
     :active-profile active :profiles (nreverse normalized))))

(defun emacsvox-aural-read-routing-profiles (&optional file)
  "Read and validate routing data from FILE without evaluating it."
  (let ((file (or file emacsvox-aural-routing-profiles-file)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (emacs-lisp-mode)
        (goto-char (point-min))
        (let ((read-eval nil)
              (data (read (current-buffer))))
          (forward-comment (point-max))
          (unless (eobp)
            (emacsvox-aural-routing--error "Trailing data in %s" file))
          (emacsvox-aural-validate-routing-user-data data))))))

(defun emacsvox-aural-load-routing-profiles (&optional file apply-active)
  "Atomically load routing profiles from FILE.

When APPLY-ACTIVE is non-nil, also apply the saved active profile."
  (when-let* ((data (emacsvox-aural-read-routing-profiles file)))
    (let ((registry (make-hash-table :test #'eq))
          (source (or file emacsvox-aural-routing-profiles-file)))
      (dolist (profile (plist-get data :profiles))
        (let* ((id (plist-get profile :id))
               (entry
                (emacsvox-aural-routing--make-entry
                 :id id :data (copy-tree profile) :source source)))
          (puthash id entry registry)))
      (setq emacsvox-aural-routing-profile-registry registry
            emacsvox-aural-active-routing-profile
            (plist-get data :active-profile)
            emacsvox-aural-session-routing-bindings nil)
      (when (and apply-active emacsvox-aural-active-routing-profile)
        (emacsvox-aural-apply-routing-profile))
      (run-hooks 'emacsvox-aural-routing-profile-changed-hook)
      data)))

(defun emacsvox-aural-save-routing-profiles (&optional file)
  "Atomically save machine-local routing profiles to FILE."
  (let* ((file
          (expand-file-name (or file emacsvox-aural-routing-profiles-file)))
         (directory (file-name-directory file))
         (data
          (emacsvox-aural-validate-routing-user-data
           (emacsvox-aural-routing-user-data)))
         temporary)
    (make-directory directory t)
    (setq temporary
          (make-temp-file
           (expand-file-name ".aural-routing-" directory)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert ";;; Machine-local voice routing -*- mode: emacs-lisp; -*-\n")
            (insert ";;; This file is read as data and is not evaluated.\n\n")
            (let ((print-length nil) (print-level nil))
              (pp data (current-buffer)))
            (write-region (point-min) (point-max) temporary nil 'silent))
          (set-file-modes temporary #o600)
          (when (file-exists-p file)
            (copy-file file (concat file "~") t t t))
          (rename-file temporary file t)
          (setq temporary nil))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))
    file))

(provide 'emacsvox-aural-routing-profiles)
;;; emacsvox-aural-routing-profiles.el ends here
