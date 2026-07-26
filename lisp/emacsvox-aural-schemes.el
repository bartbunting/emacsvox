;;; emacsvox-aural-schemes.el --- Contextual aural schemes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register and inherit declarative schemes, combine module, personal, session,
;; and buffer rule layers, preserve legacy personality hints, and persist user
;; data without evaluating it.

;;; Code:

(require 'cl-lib)
(require 'pp)
(require 'subr-x)
(require 'emacsvox-aural-resources)

(defvar emacsvox-user-directory (expand-file-name "~/.emacsvox/")
  "Emacsvox user data directory.")
(defvar emacsvox-sounds-current-pack)
(defvar read-eval)
(defvar emacsvox-aural-spatial-enabled)
(defvar emacsvox-aural-spatial-speech-enabled)
(defvar emacsvox-aural-spatial-cue-enabled)
(defvar emacsvox-aural-spatial-output)
(defvar emacsvox-aural-spatial-maximum-separation)
(defvar emacsvox-aural-spatial-remapping)

(declare-function emacsvox-sounds-follow-aural-scheme "emacsvox-sounds")

(define-error
  'emacsvox-aural-scheme-error
  "Invalid Emacsvox contextual aural scheme")

(cl-defstruct
    (emacsvox-aural-scheme-entry
     (:constructor emacsvox-aural--make-scheme-entry))
  "Registered raw and compiled scheme data."
  id data compiled built-in source)

(cl-defstruct
    (emacsvox-aural-module-fragment
     (:constructor emacsvox-aural--make-module-fragment))
  "Read-only scheme fragment supplied by an integration module."
  id module data compiled source)

(cl-defstruct
    (emacsvox-aural-feature-fragment-entry
     (:constructor emacsvox-aural--make-feature-fragment-entry))
  "Registered optional feature fragment."
  id data compiled built-in source)

(cl-defstruct
    (emacsvox-aural-profile-entry
     (:constructor emacsvox-aural--make-profile-entry))
  "Registered named presentation profile."
  id data source)

(defvar emacsvox-aural-scheme-registry (make-hash-table :test #'eq)
  "Map scheme identifiers to `emacsvox-aural-scheme-entry' records.")

(defvar emacsvox-aural-module-fragment-registry
  (make-hash-table :test #'eq)
  "Map fragment identifiers to read-only module rule fragments.")

(defvar emacsvox-aural-feature-fragment-registry
  (make-hash-table :test #'eq)
  "Map optional feature fragment identifiers to their records.")

(defvar emacsvox-aural-profile-registry (make-hash-table :test #'eq)
  "Map personal presentation profile identifiers to their records.")

(defvar emacsvox-aural-enabled-feature-fragments nil
  "Ordered identifiers of optional feature fragments in the cascade.")

(defvar emacsvox-aural-user-rules nil
  "Persistent personal rules loaded from `emacsvox-aural-schemes-file'.")

(defvar emacsvox-aural-session-rules nil
  "Temporary rules for the current Emacs session.")

(defvar-local emacsvox-aural-buffer-rules nil
  "Temporary aural rules applying only in the current buffer.")

(defvar-local emacsvox-aural-module nil
  "Semantic module identifier for aural presentation in this buffer.")

(defcustom emacsvox-aural-active-scheme 'default
  "Selected registered aural presentation scheme."
  :type 'symbol
  :group 'emacsvox-aural)

(defvar emacsvox-aural-voice-palette-override nil
  "Optional voice palette selected by a complete presentation profile.")

(defcustom emacsvox-aural-schemes-file
  (expand-file-name "aural-schemes.el" emacsvox-user-directory)
  "Data-only file containing personal aural schemes and rules."
  :type 'file
  :group 'emacsvox-aural)

(defconst emacsvox-aural-user-data-schema-version 4
  "Current schema version for the personal scheme data file.")

(defun emacsvox-aural--migrate-user-data-v1-to-v2 (data)
  "Add feature-fragment storage to version 1 user DATA."
  (setq data (plist-put data :feature-fragments nil))
  (setq data (plist-put data :enabled-feature-fragments nil))
  (plist-put data :schema-version 2))

(defun emacsvox-aural--migrate-user-data-v2-to-v3 (data)
  "Add saved presentation profiles to version 2 user DATA."
  (setq data (plist-put data :profiles nil))
  (plist-put data :schema-version 3))

(defun emacsvox-aural--migrate-user-data-v3-to-v4 (data)
  "Add personal voice palettes to version 3 user DATA."
  (setq data (plist-put data :voice-palettes nil))
  (plist-put data :schema-version 4))

(defconst emacsvox-aural--built-in-user-data-migrations
  '((1 . emacsvox-aural--migrate-user-data-v1-to-v2)
    (2 . emacsvox-aural--migrate-user-data-v2-to-v3)
    (3 . emacsvox-aural--migrate-user-data-v3-to-v4))
  "Required migrations supplied by Emacsvox.")

(defvar emacsvox-aural-user-data-migrations nil
  "Alist mapping old schema versions to data migration functions.

Each function receives one data plist and returns a plist with a greater
`:schema-version'.  Required Emacsvox migrations are always applied after
consulting this extension alist.")

(defvar emacsvox-aural-active-scheme-changed-hook nil
  "Hook run after selecting a different active scheme.")

(defvar emacsvox-aural-feature-fragments-changed-hook nil
  "Hook run after the ordered enabled feature fragments change.")

(defvar emacsvox-aural-profile-applied-hook nil
  "Hook run after a saved presentation profile is applied.")

(defvar emacsvox-aural-voice-palette-changed-hook nil
  "Hook run after the selected voice-palette override changes.")

(defvar emacsvox-aural-configuration-generation 0
  "Monotonic generation of compiled aural presentation configuration.")

(defvar emacsvox-aural-configuration-changed-hook nil
  "Abnormal hook run after an aural configuration generation changes.

Each function receives the new generation and a symbolic reason.")

(defvar emacsvox-aural--current-rules-cache
  (make-hash-table :test #'equal)
  "Validated contextual rule snapshots for the current configuration.")

(defvar emacsvox-aural--provider-cache
  (make-hash-table :test #'equal)
  "Effective scheme providers cached by configuration generation.")

(defvar emacsvox-aural--current-rules-cache-hits 0
  "Number of contextual rule snapshots served from cache.")

(defvar emacsvox-aural--current-rules-cache-misses 0
  "Number of contextual rule snapshots compiled for the cache.")

(defun emacsvox-aural-configuration-changed (&optional reason)
  "Advance the configuration generation and invalidate compiled caches.

REASON is a diagnostic symbol describing the completed state change."
  (cl-incf emacsvox-aural-configuration-generation)
  (clrhash emacsvox-aural--current-rules-cache)
  (clrhash emacsvox-aural--provider-cache)
  (run-hook-with-args
   'emacsvox-aural-configuration-changed-hook
   emacsvox-aural-configuration-generation
   (or reason 'configuration))
  emacsvox-aural-configuration-generation)

(defun emacsvox-aural-rule-cache-statistics ()
  "Return current rule-cache generation, hits, misses, and entry count."
  (list
   :generation emacsvox-aural-configuration-generation
   :hits emacsvox-aural--current-rules-cache-hits
   :misses emacsvox-aural--current-rules-cache-misses
   :entries (hash-table-count emacsvox-aural--current-rules-cache)))

(declare-function emacsvox-sounds-select-theme
                  "emacsvox-sounds" (&optional theme))

(defun emacsvox-aural--scheme-error (format-string &rest arguments)
  "Signal a scheme error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-scheme-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural-scheme-entry (id)
  "Return registered scheme entry ID, or nil."
  (gethash id emacsvox-aural-scheme-registry))

(defun emacsvox-aural-feature-fragment-entry (id)
  "Return registered feature fragment entry ID, or nil."
  (gethash id emacsvox-aural-feature-fragment-registry))

(defun emacsvox-aural-profile-entry (id)
  "Return registered presentation profile entry ID, or nil."
  (gethash id emacsvox-aural-profile-registry))

(cl-defun emacsvox-aural-register-scheme
    (data &key built-in source)
  "Compile and register scheme DATA with BUILT-IN and SOURCE metadata."
  (let* ((compiled (emacsvox-aural-compile-scheme data 'scheme source))
         (id (emacsvox-aural-scheme-id compiled)))
    (when (emacsvox-aural-scheme-entry id)
      (emacsvox-aural--scheme-error
       "Scheme is already registered: %S" id))
    (let ((entry
           (emacsvox-aural--make-scheme-entry
            :id id
            :data (copy-tree data)
            :compiled compiled
            :built-in built-in
            :source source)))
      (puthash id entry emacsvox-aural-scheme-registry)
      (emacsvox-aural-configuration-changed 'scheme-registered)
      entry)))

(cl-defun emacsvox-aural-register-module-fragment
    (module data &key source)
  "Register read-only scheme fragment DATA owned by MODULE."
  (emacsvox-aural--require-symbol module "Module fragment owner")
  (let* ((compiled (emacsvox-aural-compile-scheme data 'module source))
         (id (emacsvox-aural-scheme-id compiled)))
    (when (emacsvox-aural-scheme-parent compiled)
      (emacsvox-aural--scheme-error
       "Module fragment %S cannot inherit a user scheme" id))
    (when (gethash id emacsvox-aural-module-fragment-registry)
      (emacsvox-aural--scheme-error
       "Module fragment is already registered: %S" id))
    (let ((fragment
           (emacsvox-aural--make-module-fragment
            :id id
            :module module
            :data (copy-tree data)
            :compiled compiled
            :source source)))
      (puthash id fragment emacsvox-aural-module-fragment-registry)
      (emacsvox-aural-configuration-changed 'module-fragment-registered)
      fragment)))

(defun emacsvox-aural--compile-feature-fragment (data &optional source)
  "Compile feature fragment DATA from SOURCE."
  (let ((compiled (emacsvox-aural-compile-scheme data 'fragment source)))
    (when (emacsvox-aural-scheme-parent compiled)
      (emacsvox-aural--scheme-error
       "Feature fragment %S cannot inherit a scheme"
       (emacsvox-aural-scheme-id compiled)))
    (when (or
           (emacsvox-aural-scheme-resource-pack compiled)
           (emacsvox-aural-scheme-voice-palette compiled))
      (emacsvox-aural--scheme-error
       "Feature fragment %S cannot select resource providers"
       (emacsvox-aural-scheme-id compiled)))
    compiled))

(cl-defun emacsvox-aural-register-feature-fragment
    (data &key built-in source)
  "Compile and register optional feature fragment DATA.

BUILT-IN marks a read-only fragment and SOURCE is retained for diagnostics."
  (let* ((compiled (emacsvox-aural--compile-feature-fragment data source))
         (id (emacsvox-aural-scheme-id compiled)))
    (when (emacsvox-aural-feature-fragment-entry id)
      (emacsvox-aural--scheme-error
       "Feature fragment is already registered: %S" id))
    (let ((entry
           (emacsvox-aural--make-feature-fragment-entry
            :id id
            :data (copy-tree data)
            :compiled compiled
            :built-in built-in
            :source source)))
      (puthash id entry emacsvox-aural-feature-fragment-registry)
      (emacsvox-aural-configuration-changed 'feature-fragment-registered)
      entry)))

(defun emacsvox-aural-scheme-candidates ()
  "Return registered scheme identifiers as sorted completion strings."
  (let (ids)
    (maphash
     (lambda (id _) (push (symbol-name id) ids))
     emacsvox-aural-scheme-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-feature-fragment-candidates ()
  "Return registered feature fragment identifiers as sorted strings."
  (let (ids)
    (maphash
     (lambda (id _) (push (symbol-name id) ids))
     emacsvox-aural-feature-fragment-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-feature-fragment-enabled-p (id)
  "Return non-nil when feature fragment ID is enabled."
  (memq id emacsvox-aural-enabled-feature-fragments))

(defun emacsvox-aural--validate-enabled-feature-fragments
    (ids &optional registry)
  "Validate ordered feature fragment IDS against REGISTRY and return IDS."
  (unless (and (listp ids) (proper-list-p ids))
    (emacsvox-aural--scheme-error
     "Enabled feature fragments must be a proper list: %S" ids))
  (let ((registry
         (or registry emacsvox-aural-feature-fragment-registry))
        seen)
    (dolist (id ids)
      (emacsvox-aural--require-symbol id "Enabled feature fragment")
      (when (memq id seen)
        (emacsvox-aural--scheme-error
         "Feature fragment is enabled more than once: %S" id))
      (unless (gethash id registry)
        (emacsvox-aural--scheme-error
         "Unknown enabled feature fragment: %S" id))
      (push id seen)))
  ids)

(defun emacsvox-aural-set-enabled-feature-fragments (ids)
  "Set ordered enabled feature fragment IDS and run the change hook."
  (emacsvox-aural--validate-enabled-feature-fragments ids)
  (setq emacsvox-aural-enabled-feature-fragments (copy-sequence ids))
  (emacsvox-aural-configuration-changed 'feature-fragments)
  (run-hooks 'emacsvox-aural-feature-fragments-changed-hook)
  emacsvox-aural-enabled-feature-fragments)

(defun emacsvox-aural--scheme-chain (id &optional path)
  "Return inherited scheme entries for ID from parent to child."
  (when (memq id path)
    (emacsvox-aural--scheme-error
     "Scheme inheritance cycle: %S" (nreverse (cons id path))))
  (let ((entry (emacsvox-aural-scheme-entry id)))
    (unless entry
      (emacsvox-aural--scheme-error "Unknown scheme: %S" id))
    (if-let* ((parent
               (emacsvox-aural-scheme-parent
                (emacsvox-aural-scheme-entry-compiled entry))))
        (append
         (emacsvox-aural--scheme-chain parent (cons id path))
         (list entry))
      (list entry))))

(defun emacsvox-aural-effective-scheme-rules (&optional id include-disabled)
  "Return inherited compiled rules for scheme ID or the active scheme.

When INCLUDE-DISABLED is non-nil, retain validated disabled rules for
diagnostics and cross-layer identifier checks."
  (let ((chain
         (emacsvox-aural--scheme-chain
          (or id emacsvox-aural-active-scheme)))
        rules
        seen)
    (cl-loop
     for entry in chain
     for layer-order from 0
     do
     (dolist
         (rule
          (emacsvox-aural-scheme-rules
           (emacsvox-aural-scheme-entry-compiled entry)))
       (when (memq (emacsvox-aural-rule-id rule) seen)
         (emacsvox-aural--scheme-error
          "Duplicate inherited rule identifier in scheme %S: %S"
          (or id emacsvox-aural-active-scheme)
          (emacsvox-aural-rule-id rule)))
       (push (emacsvox-aural-rule-id rule) seen)
       (when (or include-disabled (emacsvox-aural-rule-enabled rule))
         (let ((copy (copy-emacsvox-aural-rule rule)))
           (setf (emacsvox-aural-rule-layer-order copy) layer-order)
           (push copy rules)))))
    (nreverse rules)))

(defun emacsvox-aural--compute-effective-scheme-provider (property id)
  "Compute inherited provider PROPERTY for scheme ID."
  (let (value)
    (dolist (entry (emacsvox-aural--scheme-chain id))
      (let ((scheme (emacsvox-aural-scheme-entry-compiled entry)))
        (pcase property
          ('resource-pack
           (when (emacsvox-aural-scheme-resource-pack scheme)
             (setq value (emacsvox-aural-scheme-resource-pack scheme))))
          ('voice-palette
           (when (emacsvox-aural-scheme-voice-palette scheme)
             (setq value (emacsvox-aural-scheme-voice-palette scheme)))))))
    value))

(defun emacsvox-aural-effective-scheme-provider (property &optional id)
  "Return inherited provider PROPERTY for scheme ID or the active scheme.

PROPERTY is `resource-pack' or `voice-palette'."
  (unless (memq property '(resource-pack voice-palette))
    (emacsvox-aural--scheme-error
     "Unknown scheme provider property: %S" property))
  (let* ((id (or id emacsvox-aural-active-scheme))
         (key
          (list
           emacsvox-aural-configuration-generation
           emacsvox-aural-scheme-registry property id))
         (missing (make-symbol "missing"))
         (cached (gethash key emacsvox-aural--provider-cache missing)))
    (if (eq cached missing)
        (let ((provider
               (emacsvox-aural--compute-effective-scheme-provider
                property id)))
          (puthash key (cons t provider) emacsvox-aural--provider-cache)
          provider)
      (cdr cached))))

(defun emacsvox-aural--validate-scheme-providers (id &optional defer-packs)
  "Validate provider references for scheme ID.

When DEFER-PACKS is non-nil, an empty resource-pack registry means packs have
not loaded yet; validation is deferred until the complete registry check."
  (when-let* ((pack
               (emacsvox-aural-effective-scheme-provider
                'resource-pack id)))
    (let ((record (emacsvox-aural-resource-pack pack)))
      (unless
          (or
           record
           (and
            defer-packs
            (zerop (hash-table-count
                    emacsvox-aural-resource-pack-registry))))
        (emacsvox-aural--scheme-error
         "Scheme %S names unknown resource pack %S" id pack))
      (when
          (and
           record
           (not (eq (emacsvox-aural-resource-pack-kind record) 'sound)))
        (emacsvox-aural--scheme-error
         "Scheme %S resource pack %S is not a sound pack" id pack))))
  (when-let* ((palette
               (emacsvox-aural-effective-scheme-provider
                'voice-palette id)))
    (unless (emacsvox-aural-voice-palette palette)
      (emacsvox-aural--scheme-error
       "Scheme %S names unknown voice palette %S" id palette)))
  t)

(defun emacsvox-aural-validate-scheme-registry ()
  "Validate inheritance and provider references for registered schemes."
  (maphash
   (lambda (id _)
     (emacsvox-aural--scheme-chain id)
     (emacsvox-aural-effective-scheme-rules id)
     (emacsvox-aural--validate-scheme-providers id))
   emacsvox-aural-scheme-registry)
  t)

(defun emacsvox-aural-select-scheme (id)
  "Select registered scheme ID and run the selection hook."
  (interactive
   (list
    (intern
     (completing-read
      "Aural scheme: "
      (emacsvox-aural-scheme-candidates)
      nil 'must-match nil nil
      (symbol-name emacsvox-aural-active-scheme)))))
  (unless (emacsvox-aural-scheme-entry id)
    (emacsvox-aural--scheme-error "Unknown scheme: %S" id))
  (emacsvox-aural--scheme-chain id)
  (emacsvox-aural-effective-scheme-rules id)
  (emacsvox-aural--validate-scheme-providers id t)
  (setq emacsvox-aural-active-scheme id)
  (emacsvox-aural-configuration-changed 'active-scheme)
  (run-hooks 'emacsvox-aural-active-scheme-changed-hook)
  id)

(defun emacsvox-aural--compile-rule-list
    (data origin source &optional include-disabled)
  "Compile rule DATA from ORIGIN and SOURCE, rejecting duplicate IDs.

When INCLUDE-DISABLED is non-nil, retain disabled rules in the result."
  (unless (listp data)
    (emacsvox-aural--scheme-error "Rule layer must be a list: %S" data))
  (let ((compiled
         (cl-loop
          for rule in data
          for index from 0
          collect
          (emacsvox-aural-compile-rule rule origin index source)))
        seen)
    (dolist (rule compiled)
      (when (memq (emacsvox-aural-rule-id rule) seen)
        (emacsvox-aural--scheme-error
         "Duplicate %S rule identifier: %S"
         origin (emacsvox-aural-rule-id rule)))
      (push (emacsvox-aural-rule-id rule) seen))
    (if include-disabled
        compiled
      (cl-remove-if-not #'emacsvox-aural-rule-enabled compiled))))

(defun emacsvox-aural--module-rules (module &optional include-disabled)
  "Return compiled read-only fragment rules matching MODULE.

When INCLUDE-DISABLED is non-nil, retain disabled fragment rules."
  (let (fragments rules)
    (maphash
     (lambda (_ fragment)
       (when (eq module (emacsvox-aural-module-fragment-module fragment))
         (push fragment fragments)))
     emacsvox-aural-module-fragment-registry)
    (setq
     fragments
     (sort
      fragments
      (lambda (left right)
        (string-lessp
         (symbol-name (emacsvox-aural-module-fragment-id left))
         (symbol-name (emacsvox-aural-module-fragment-id right))))))
    (cl-loop
     for fragment in fragments
     for layer-order from 0
     do
     (dolist
         (rule
          (emacsvox-aural-scheme-rules
           (emacsvox-aural-module-fragment-compiled fragment)))
       (when (or include-disabled (emacsvox-aural-rule-enabled rule))
         (let ((copy (copy-emacsvox-aural-rule rule)))
           (setf (emacsvox-aural-rule-layer-order copy) layer-order)
           (push copy rules)))))
    (nreverse rules)))

(defun emacsvox-aural--feature-fragment-rules (&optional include-disabled)
  "Return rules from enabled feature fragments in their explicit order.

When INCLUDE-DISABLED is non-nil, retain disabled rules."
  (emacsvox-aural--validate-enabled-feature-fragments
   emacsvox-aural-enabled-feature-fragments)
  (let (rules)
    (cl-loop
     for id in emacsvox-aural-enabled-feature-fragments
     for layer-order from 0
     for entry = (emacsvox-aural-feature-fragment-entry id)
     do
     (dolist
         (rule
          (emacsvox-aural-scheme-rules
           (emacsvox-aural-feature-fragment-entry-compiled entry)))
       (when (or include-disabled (emacsvox-aural-rule-enabled rule))
         (let ((copy (copy-emacsvox-aural-rule rule)))
           (setf (emacsvox-aural-rule-layer-order copy) layer-order)
           (push copy rules)))))
    (nreverse rules)))

(defun emacsvox-aural--require-unique-rule-ids (rules)
  "Return RULES after rejecting ambiguous duplicate rule identifiers."
  (let ((seen (make-hash-table :test #'eq)))
    (dolist (rule rules)
      (let ((id (emacsvox-aural-rule-id rule)))
        (when-let* ((existing (gethash id seen)))
          (emacsvox-aural--scheme-error
           "Rule identifier %S is reused by %S and %S"
           id
           (emacsvox-aural-rule-origin existing)
           (emacsvox-aural-rule-origin rule)))
        (puthash id rule seen)))
    rules))

(defun emacsvox-aural--compute-current-rules (context)
  "Compile every validated rule layer relevant to CONTEXT."
  (cl-remove-if-not
   #'emacsvox-aural-rule-enabled
   (emacsvox-aural--require-unique-rule-ids
    (append
     (emacsvox-aural--module-rules
      (plist-get context :module) t)
     (emacsvox-aural-effective-scheme-rules nil t)
     (emacsvox-aural--feature-fragment-rules t)
     (emacsvox-aural--compile-rule-list
      emacsvox-aural-user-rules
      'user emacsvox-aural-schemes-file t)
     (emacsvox-aural--compile-rule-list
      emacsvox-aural-session-rules 'session "session" t)
     (emacsvox-aural--compile-rule-list
      emacsvox-aural-buffer-rules
      'buffer
      (format "buffer:%s" (buffer-name))
      t)))))

(defun emacsvox-aural--current-rules-cache-key (context)
  "Return an immutable cache key for contextual rule CONTEXT."
  (list
   emacsvox-aural-configuration-generation
   emacsvox-aural-scheme-registry
   emacsvox-aural-module-fragment-registry
   emacsvox-aural-feature-fragment-registry
   emacsvox-aural-active-scheme
   (plist-get context :module)
   emacsvox-aural-enabled-feature-fragments
   emacsvox-aural-user-rules
   emacsvox-aural-session-rules
   emacsvox-aural-buffer-rules
   (buffer-name)))

(defun emacsvox-aural-current-rules (&optional context)
  "Return the validated immutable rule snapshot relevant to CONTEXT."
  (let* ((key (emacsvox-aural--current-rules-cache-key context))
         (missing (make-symbol "missing"))
         (cached
          (gethash key emacsvox-aural--current-rules-cache missing)))
    (if (eq cached missing)
        (let ((rules (emacsvox-aural--compute-current-rules context)))
          (cl-incf emacsvox-aural--current-rules-cache-misses)
          (puthash key rules emacsvox-aural--current-rules-cache)
          rules)
      (cl-incf emacsvox-aural--current-rules-cache-hits)
      cached)))

(defun emacsvox-aural-current-context
    (module occasion &optional legacy-personality legacy-source)
  "Capture current MODULE, OCCASION, and legacy presentation hints."
  (list
   :module (or module emacsvox-aural-module)
   :mode major-mode
   :mode-lineage (emacsvox-aural-mode-lineage major-mode)
   :occasion occasion
   :face-presentation-enabled
   emacsvox-aural-face-presentation-enabled
   :voice-lock-enabled
   (emacsvox-aural-voice-lock-enabled-p)
   :legacy-personality legacy-personality
   :legacy-source legacy-source
   :source-buffer (current-buffer)
   :source-buffer-name (buffer-name)
   :source-position (point)))

(defun emacsvox-aural--apply-legacy-content-style (plan context)
  "Apply CONTEXT's legacy voice fallback to resolved PLAN."
  (let* ((legacy (plist-get context :legacy-personality))
         (source (or (plist-get context :legacy-source) 'legacy-personality))
         (content (emacsvox-aural-render-plan-content plan)))
    (when
        (and
         (if (plist-member context :voice-lock-enabled)
             (plist-get context :voice-lock-enabled)
           (emacsvox-aural-voice-lock-enabled-p))
         legacy
         (not
          (assq
           'voice
           (emacsvox-aural-content-style-provenance content))))
      (setf (emacsvox-aural-content-style-voice content) legacy)
      (setf
       (emacsvox-aural-content-style-voice-provenance content)
       (mapcar
        (lambda (property) (cons property source))
        (cons 'preset emacsvox-aural-voice-dimensions)))
      (setf
       (emacsvox-aural-content-style-provenance content)
       (cons
        (cons 'voice source)
        (emacsvox-aural-content-style-provenance content))))
    plan))

(defun emacsvox-aural-resolve-active-inputs (inputs &optional anchor)
  "Resolve one object's semantic INPUTS through active layers for ANCHOR.

INPUTS is a nonempty list of (FACTS . CONTEXT) pairs.  Contextual rule
collection uses the first pair because object boundaries guarantee stable
module context."
  (unless (and (consp inputs) (cl-every #'consp inputs))
    (emacsvox-aural--scheme-error
     "Active aural resolution requires nonempty inputs: %S" inputs))
  (let* ((context (cdar inputs))
         (plan
          (emacsvox-aural-resolve-inputs
           inputs (emacsvox-aural-current-rules context) anchor)))
    (emacsvox-aural--apply-legacy-content-style plan context)))

(defun emacsvox-aural-resolve-active (facts &optional context anchor)
  "Resolve FACTS through active scheme and contextual rule layers.

Optional ANCHOR limits ordered actions to one object/run lifecycle."
  (let ((context
         (or
          context
          (emacsvox-aural-current-context nil 'continuous))))
    (emacsvox-aural-resolve-active-inputs
     (list (cons facts context)) anchor)))

(defun emacsvox-aural--legacy-icon-rule (icon)
  "Return the core compatibility rule that presents legacy ICON."
  (emacsvox-aural-compile-rule
   (list
    :id 'legacy-cue-default
    :match (list :legacy-cue icon)
    :render
    (list
     :before
     (list
      (list :id 'legacy-cue :kind 'cue :cue icon))))
   'core 0 "legacy icon adapter"))

(defun emacsvox-aural-resolve-legacy-icon
    (icon &optional context facts anchor)
  "Resolve legacy ICON through the active scheme in CONTEXT.

The returned plan initially contains ICON as action `legacy-cue'.  Contextual
rules can remove that action or replace its cue without changing callers.
Optional FACTS are composed with any known semantic event for ICON.  Optional
ANCHOR limits ordered actions to one object/run lifecycle."
  (emacsvox-aural--require-symbol icon "Legacy cue")
  (let* ((semantic (alist-get icon emacsvox-aural-legacy-icon-semantics))
         (facts (copy-tree facts))
         (events
          (append
           (when-let* ((event (plist-get facts :event))) (list event))
           (copy-sequence (plist-get facts :events))
           (when semantic (list semantic))))
         (facts
          (if events
              (plist-put facts :events (delete-dups events))
            facts))
         (context
          (plist-put
           (copy-sequence
            (or
             context
             (emacsvox-aural-current-context nil 'notification)))
           :legacy-cue icon))
         (compatibility-rule (emacsvox-aural--legacy-icon-rule icon)))
    (emacsvox-aural--apply-legacy-content-style
     (emacsvox-aural-resolve
      facts
      context
      (emacsvox-aural--require-unique-rule-ids
       (cons
        compatibility-rule
        (emacsvox-aural-current-rules context)))
      anchor)
     context)))

(defun emacsvox-aural-resolve-legacy-icon-inputs
    (icon inputs &optional anchor)
  "Resolve legacy ICON across one object's INPUTS for optional ANCHOR.

INPUTS must already contain ICON's semantic events and `:legacy-cue' context,
as produced by the transport source-boundary adapter."
  (unless (and (consp inputs) (cl-every #'consp inputs))
    (emacsvox-aural--scheme-error
     "Legacy icon resolution requires nonempty inputs: %S" inputs))
  (let ((context (cdar inputs)))
    (emacsvox-aural--apply-legacy-content-style
     (emacsvox-aural-resolve-inputs
      inputs
      (emacsvox-aural--require-unique-rule-ids
       (cons
        (emacsvox-aural--legacy-icon-rule icon)
        (emacsvox-aural-current-rules context)))
      anchor)
     context)))

(defun emacsvox-aural-make-legacy-cue-rule
    (id cue replacement &optional selectors)
  "Return personal rule ID remapping legacy CUE to REPLACEMENT.

When REPLACEMENT is nil, the old cue is suppressed.  SELECTORS is an
optional selector plist such as `(:mode org-mode)' or `(:module org)'."
  (emacsvox-aural--require-symbol id "Legacy cue rule identifier")
  (emacsvox-aural--require-symbol cue "Legacy cue")
  (when replacement
    (emacsvox-aural--require-symbol replacement "Replacement cue"))
  (emacsvox-aural--require-plist (or selectors nil) "Legacy cue selectors")
  (list
   :id id
   :match (append (list :legacy-cue cue) (copy-tree selectors))
   :render
   (list
    :before
    (append
     '(:remove (legacy-cue))
     (when replacement
       (list
        :append
        (list
         (list
          :id 'legacy-cue
          :kind 'cue
          :cue replacement))))))))

(defun emacsvox-aural-make-legacy-personality-rule
    (id personality replacement &optional selectors)
  "Return personal rule ID remapping legacy PERSONALITY to REPLACEMENT.

A nil REPLACEMENT explicitly clears the old voice.  SELECTORS is an optional
selector plist such as `(:mode org-mode)' or `(:module org)'."
  (emacsvox-aural--require-symbol id "Legacy personality rule identifier")
  (unless (or (symbolp personality) (consp personality))
    (emacsvox-aural--scheme-error
     "Legacy personality must be a symbol or cons: %S" personality))
  (emacsvox-aural--require-plist
   (or selectors nil) "Legacy personality selectors")
  (list
   :id id
   :match
   (append
    (list :legacy-personality personality)
   (copy-tree selectors))
   :render (list :content (list :voice replacement))))

(defconst emacsvox-aural--profile-spatial-keys
  '(:enabled :speech-enabled :cue-enabled :output
    :maximum-separation :remapping)
  "Data-only portable spatial settings accepted in presentation profiles.")

(defun emacsvox-aural--validate-profile-spatial (spatial)
  "Validate and return profile SPATIAL settings."
  (when spatial
    (emacsvox-aural--require-plist spatial "Profile spatial settings")
    (let ((unknown
           (cl-loop
            for (key _) on spatial by #'cddr
            unless (memq key emacsvox-aural--profile-spatial-keys)
            collect key)))
      (when unknown
        (emacsvox-aural--scheme-error
         "Unknown profile spatial settings: %S" unknown)))
    (dolist (key '(:enabled :speech-enabled :cue-enabled))
      (when
          (and
           (plist-member spatial key)
           (not (memq (plist-get spatial key) '(nil t))))
        (emacsvox-aural--scheme-error
         "Profile spatial %S must be boolean" key)))
    (when
        (and
         (plist-member spatial :output)
         (not (memq (plist-get spatial :output) '(auto mono))))
      (emacsvox-aural--scheme-error
       "Profile spatial output must be auto or mono"))
    (when
        (and
         (plist-member spatial :maximum-separation)
         (let ((value (plist-get spatial :maximum-separation)))
           (not
            (and
             (numberp value) (<= 0.0 value) (<= value 1.0)))))
      (emacsvox-aural--scheme-error
       "Profile maximum separation must be between 0 and 1"))
    (when
        (and
         (plist-member spatial :remapping)
         (not
          (memq
           (plist-get spatial :remapping)
           '(normal reverse collapse-left collapse-right center))))
      (emacsvox-aural--scheme-error
       "Profile spatial remapping is not data-safe: %S"
       (plist-get spatial :remapping))))
  spatial)

(defun emacsvox-aural--validate-profile-data
    (data &optional scheme-registry fragment-registry palette-registry)
  "Validate and return presentation profile DATA.

SCHEME-REGISTRY, FRAGMENT-REGISTRY, and PALETTE-REGISTRY permit validation of
a complete user file before its entries replace the live registries."
  (emacsvox-aural--require-plist data "Presentation profile")
  (let* ((id (plist-get data :id))
         (summary (plist-get data :summary))
         (scheme (plist-get data :scheme))
         (fragments (plist-get data :feature-fragments))
         (pack (plist-get data :sound-pack))
         (palette (plist-get data :voice-palette))
         (spatial (plist-get data :spatial))
         (scheme-registry
          (or scheme-registry emacsvox-aural-scheme-registry))
         (fragment-registry
          (or fragment-registry emacsvox-aural-feature-fragment-registry))
         (palette-registry
          (or palette-registry emacsvox-aural-voice-palette-registry))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless
           (memq
            key
            '(:id :summary :scheme :feature-fragments
              :sound-pack :voice-palette :spatial))
           collect key)))
    (when unknown
      (emacsvox-aural--scheme-error
       "Unknown presentation profile keys: %S" unknown))
    (emacsvox-aural--require-symbol id "Presentation profile identifier")
    (unless (and (stringp summary) (not (string-empty-p summary)))
      (emacsvox-aural--scheme-error
       "Presentation profile %S requires a summary" id))
    (emacsvox-aural--require-symbol scheme "Presentation profile scheme")
    (unless (gethash scheme scheme-registry)
      (emacsvox-aural--scheme-error
       "Presentation profile %S names unknown scheme %S" id scheme))
    (emacsvox-aural--validate-enabled-feature-fragments
     fragments fragment-registry)
    (when pack
      (emacsvox-aural--require-symbol pack "Presentation profile sound pack")
      (when
          (> (hash-table-count emacsvox-aural-resource-pack-registry) 0)
        (let ((record (emacsvox-aural-resource-pack pack)))
          (unless record
            (emacsvox-aural--scheme-error
             "Presentation profile %S names unknown sound pack %S" id pack))
          (unless (eq (emacsvox-aural-resource-pack-kind record) 'sound)
            (emacsvox-aural--scheme-error
             "Presentation profile %S pack %S is not a sound pack"
             id pack)))))
    (when palette
      (emacsvox-aural--require-symbol
       palette "Presentation profile voice palette")
      (when
          (and
           (> (hash-table-count palette-registry) 0)
           (not (gethash palette palette-registry)))
        (emacsvox-aural--scheme-error
         "Presentation profile %S names unknown voice palette %S"
         id palette)))
    (emacsvox-aural--validate-profile-spatial spatial)
    data))

(cl-defun emacsvox-aural-register-profile (data &key source replace)
  "Validate and register presentation profile DATA from SOURCE.

When REPLACE is non-nil, replace an existing personal entry of the same ID."
  (emacsvox-aural--validate-profile-data data)
  (let* ((id (plist-get data :id))
         (existing (emacsvox-aural-profile-entry id)))
    (when (and existing (not replace))
      (emacsvox-aural--scheme-error
       "Presentation profile is already registered: %S" id))
    (let ((entry
           (emacsvox-aural--make-profile-entry
            :id id :data (copy-tree data) :source source)))
      (puthash id entry emacsvox-aural-profile-registry)
      entry)))

(defun emacsvox-aural-profile-candidates ()
  "Return registered presentation profile identifiers as sorted strings."
  (let (ids)
    (maphash
     (lambda (id _) (push (symbol-name id) ids))
     emacsvox-aural-profile-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-delete-profile (id)
  "Delete registered presentation profile ID."
  (unless (emacsvox-aural-profile-entry id)
    (emacsvox-aural--scheme-error
     "Unknown presentation profile: %S" id))
  (remhash id emacsvox-aural-profile-registry)
  id)

(defun emacsvox-aural-capture-profile-data (id summary)
  "Return profile data named ID with SUMMARY from the current configuration."
  (emacsvox-aural--require-symbol id "Presentation profile identifier")
  (unless (and (stringp summary) (not (string-empty-p summary)))
    (emacsvox-aural--scheme-error
     "Presentation profile requires a summary"))
  (list
   :id id
   :summary summary
   :scheme emacsvox-aural-active-scheme
   :feature-fragments
   (copy-sequence emacsvox-aural-enabled-feature-fragments)
   :sound-pack
   (or
    (and
     (boundp 'emacsvox-sounds-current-pack)
     emacsvox-sounds-current-pack)
    (emacsvox-aural-effective-scheme-provider 'resource-pack))
   :voice-palette
   (or
    emacsvox-aural-voice-palette-override
    (emacsvox-aural-effective-scheme-provider 'voice-palette))
   :spatial
   (list
    :enabled emacsvox-aural-spatial-enabled
    :speech-enabled emacsvox-aural-spatial-speech-enabled
    :cue-enabled emacsvox-aural-spatial-cue-enabled
    :output emacsvox-aural-spatial-output
    :maximum-separation emacsvox-aural-spatial-maximum-separation
    :remapping
    (if (symbolp emacsvox-aural-spatial-remapping)
        emacsvox-aural-spatial-remapping
      'normal))))

(defun emacsvox-aural--apply-profile-spatial (spatial)
  "Apply validated profile SPATIAL settings."
  (when spatial
    (when (plist-member spatial :enabled)
      (setq emacsvox-aural-spatial-enabled
            (plist-get spatial :enabled)))
    (when (plist-member spatial :speech-enabled)
      (setq emacsvox-aural-spatial-speech-enabled
            (plist-get spatial :speech-enabled)))
    (when (plist-member spatial :cue-enabled)
      (setq emacsvox-aural-spatial-cue-enabled
            (plist-get spatial :cue-enabled)))
    (when (plist-member spatial :output)
      (setq emacsvox-aural-spatial-output
            (plist-get spatial :output)))
    (when (plist-member spatial :maximum-separation)
      (setq emacsvox-aural-spatial-maximum-separation
            (float (plist-get spatial :maximum-separation))))
    (when (plist-member spatial :remapping)
      (setq emacsvox-aural-spatial-remapping
            (plist-get spatial :remapping)))))

(defun emacsvox-aural-apply-profile (id)
  "Validate and transactionally apply presentation profile ID."
  (let* ((entry
          (or
           (emacsvox-aural-profile-entry id)
           (emacsvox-aural--scheme-error
            "Unknown presentation profile: %S" id)))
         (data (copy-tree (emacsvox-aural-profile-entry-data entry)))
         (_ (emacsvox-aural--validate-profile-data data))
         (scheme (plist-get data :scheme))
         (fragments (plist-get data :feature-fragments))
         (pack
          (or
           (plist-get data :sound-pack)
           (emacsvox-aural-effective-scheme-provider
            'resource-pack scheme)))
         (palette (plist-get data :voice-palette))
         (spatial (plist-get data :spatial))
         (old-scheme emacsvox-aural-active-scheme)
         (old-fragments
          (copy-sequence emacsvox-aural-enabled-feature-fragments))
         (old-palette emacsvox-aural-voice-palette-override)
         (old-pack
          (and
           (boundp 'emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack))
         (old-spatial
          (list
           :enabled emacsvox-aural-spatial-enabled
           :speech-enabled emacsvox-aural-spatial-speech-enabled
           :cue-enabled emacsvox-aural-spatial-cue-enabled
           :output emacsvox-aural-spatial-output
           :maximum-separation emacsvox-aural-spatial-maximum-separation
           :remapping emacsvox-aural-spatial-remapping))
         completed)
    (when pack
      (unless (emacsvox-aural-resource-pack pack)
        (emacsvox-aural--scheme-error
         "Presentation profile %S sound pack is unavailable: %S"
         id pack))
      (require 'emacsvox-sounds))
    (unwind-protect
        (progn
          ;; The profile selects its pack once after the scheme hook.  Suppress
          ;; only the ordinary follow-scheme theme switch to avoid two reloads.
          (let ((emacsvox-aural-active-scheme-changed-hook
                 (remove
                  'emacsvox-sounds-follow-aural-scheme
                  (copy-sequence
                   emacsvox-aural-active-scheme-changed-hook))))
            (emacsvox-aural-select-scheme scheme))
          (emacsvox-aural-set-enabled-feature-fragments fragments)
          (setq emacsvox-aural-voice-palette-override palette)
          (emacsvox-aural--apply-profile-spatial spatial)
          (when pack
            (emacsvox-sounds-select-theme pack))
          (setq completed t)
          (emacsvox-aural-configuration-changed 'profile-applied)
          (unless (eq old-palette palette)
            (run-hook-with-args
             'emacsvox-aural-voice-palette-changed-hook palette))
          (run-hook-with-args 'emacsvox-aural-profile-applied-hook id))
      (unless completed
        (setq
         emacsvox-aural-active-scheme old-scheme
         emacsvox-aural-enabled-feature-fragments old-fragments
         emacsvox-aural-voice-palette-override old-palette)
        (emacsvox-aural--apply-profile-spatial old-spatial)
        (when old-pack
          (ignore-errors (emacsvox-sounds-select-theme old-pack)))))
    id))

(defun emacsvox-aural-profile-current-p (id)
  "Return non-nil when live presentation settings equal profile ID."
  (when-let* ((entry (emacsvox-aural-profile-entry id)))
    (let* ((data (emacsvox-aural-profile-entry-data entry))
           (spatial (plist-get data :spatial))
           (pack
            (or
             (plist-get data :sound-pack)
             (emacsvox-aural-effective-scheme-provider
              'resource-pack (plist-get data :scheme)))))
      (and
       (eq (plist-get data :scheme) emacsvox-aural-active-scheme)
       (equal
        (plist-get data :feature-fragments)
        emacsvox-aural-enabled-feature-fragments)
       (eq
        (plist-get data :voice-palette)
        emacsvox-aural-voice-palette-override)
       (or
        (not (boundp 'emacsvox-sounds-current-pack))
        (eq pack emacsvox-sounds-current-pack))
       (or
        (null spatial)
        (and
         (or
          (not (plist-member spatial :enabled))
          (eq
           (plist-get spatial :enabled)
           emacsvox-aural-spatial-enabled))
         (or
          (not (plist-member spatial :speech-enabled))
          (eq
           (plist-get spatial :speech-enabled)
           emacsvox-aural-spatial-speech-enabled))
         (or
          (not (plist-member spatial :cue-enabled))
          (eq
           (plist-get spatial :cue-enabled)
           emacsvox-aural-spatial-cue-enabled))
         (or
          (not (plist-member spatial :output))
          (eq
           (plist-get spatial :output)
           emacsvox-aural-spatial-output))
         (or
          (not (plist-member spatial :maximum-separation))
          (=
           (plist-get spatial :maximum-separation)
           emacsvox-aural-spatial-maximum-separation))
         (or
          (not (plist-member spatial :remapping))
          (eq
           (plist-get spatial :remapping)
           emacsvox-aural-spatial-remapping))))))))

(defun emacsvox-aural-select-voice-palette (&optional palette)
  "Select voice PALETTE as a global override, or nil to follow the scheme."
  (when
      (and palette (not (emacsvox-aural-voice-palette palette)))
    (emacsvox-aural--scheme-error
     "Unknown voice palette: %S" palette))
  (setq emacsvox-aural-voice-palette-override palette)
  (emacsvox-aural-configuration-changed 'voice-palette)
  (run-hook-with-args 'emacsvox-aural-voice-palette-changed-hook palette)
  palette)

(defun emacsvox-aural--validate-user-data (data)
  "Validate and return current-schema user DATA."
  (emacsvox-aural--require-plist data "Aural user data")
  (let ((version (plist-get data :schema-version))
        (schemes (plist-get data :schemes))
        (fragments (plist-get data :feature-fragments))
        (enabled (plist-get data :enabled-feature-fragments))
        (palettes (plist-get data :voice-palettes))
        (profiles (plist-get data :profiles))
        (rules (plist-get data :user-rules))
        (unknown
         (cl-loop
          for (key _) on data by #'cddr
          unless
          (memq
           key
           '(:schema-version :schemes :feature-fragments
             :enabled-feature-fragments :voice-palettes
             :profiles :user-rules))
          collect key)))
    (unless (eq version emacsvox-aural-user-data-schema-version)
      (emacsvox-aural--scheme-error
       "Unsupported user data version: %S" version))
    (when unknown
      (emacsvox-aural--scheme-error
       "Unknown user data keys: %S" unknown))
    (unless (listp schemes)
      (emacsvox-aural--scheme-error "User schemes must be a list"))
    (unless (listp fragments)
      (emacsvox-aural--scheme-error "User feature fragments must be a list"))
    (unless (listp profiles)
      (emacsvox-aural--scheme-error
       "Presentation profiles must be a list"))
    (unless (listp palettes)
      (emacsvox-aural--scheme-error
       "Personal voice palettes must be a list"))
    (unless (listp rules)
      (emacsvox-aural--scheme-error "User rules must be a list"))
    (let ((scheme-registry (emacsvox-aural--built-in-scheme-registry))
          (fragment-registry
           (emacsvox-aural--built-in-feature-fragment-registry))
          (palette-registry
           (emacsvox-aural--built-in-voice-palette-registry))
          profile-ids)
      (dolist (scheme schemes)
        (let* ((compiled (emacsvox-aural-compile-scheme scheme))
               (id (emacsvox-aural-scheme-id compiled)))
          (when (gethash id scheme-registry)
            (emacsvox-aural--scheme-error
             "Duplicate or protected user scheme: %S" id))
          (puthash id t scheme-registry)))
      (dolist (fragment fragments)
        (let* ((compiled
                (emacsvox-aural--compile-feature-fragment fragment))
               (id (emacsvox-aural-scheme-id compiled)))
          (when (gethash id fragment-registry)
            (emacsvox-aural--scheme-error
             "Duplicate or protected user feature fragment: %S" id))
          (puthash id t fragment-registry)))
      (emacsvox-aural--validate-enabled-feature-fragments
       enabled fragment-registry)
      (dolist (palette palettes)
        (condition-case error
            (let* ((compiled
                    (emacsvox-aural-compile-voice-palette-data palette))
                   (id (emacsvox-aural-voice-palette-id compiled)))
              (when (gethash id palette-registry)
                (emacsvox-aural--scheme-error
                 "Duplicate or protected personal voice palette: %S" id))
              (puthash id compiled palette-registry))
          (emacsvox-aural-resource-error
           (emacsvox-aural--scheme-error
            "%s" (error-message-string error)))))
      (let ((emacsvox-aural-voice-palette-registry palette-registry))
        (maphash
         (lambda (id _)
           (emacsvox-aural-effective-voice-entries id))
         palette-registry))
      (dolist (profile profiles)
        (emacsvox-aural--validate-profile-data
         profile scheme-registry fragment-registry palette-registry)
        (let ((id (plist-get profile :id)))
          (when (memq id profile-ids)
            (emacsvox-aural--scheme-error
             "Duplicate presentation profile: %S" id))
          (push id profile-ids))))
    (emacsvox-aural--compile-rule-list rules 'user "user data")
    data))

(defun emacsvox-aural-migrate-user-data (data)
  "Apply registered migrations to user DATA and return current-schema data."
  (let ((current (copy-tree data))
        (seen nil))
    (while
        (not
         (eq
          (plist-get current :schema-version)
          emacsvox-aural-user-data-schema-version))
      (let ((version (plist-get current :schema-version)))
        (when (memq version seen)
          (emacsvox-aural--scheme-error
           "User data migration cycle at version %S" version))
        (push version seen)
        (let ((migration
               (or
                (alist-get version emacsvox-aural-user-data-migrations)
                (alist-get
                 version emacsvox-aural--built-in-user-data-migrations))))
          (unless migration
            (emacsvox-aural--scheme-error
             "No migration from user data version %S" version))
          (setq current (funcall migration current)))))
    (emacsvox-aural--validate-user-data current)))

(defun emacsvox-aural-read-user-data (&optional file)
  "Read and validate data from FILE or `emacsvox-aural-schemes-file'."
  (let ((file (or file emacsvox-aural-schemes-file)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (emacs-lisp-mode)
        (goto-char (point-min))
        (let* ((read-eval nil)
               (data (read (current-buffer))))
          (forward-comment (point-max))
          (unless (eobp)
            (emacsvox-aural--scheme-error
             "Trailing data in %s" file))
          (emacsvox-aural-migrate-user-data data))))))

(defun emacsvox-aural--built-in-scheme-registry ()
  "Return a registry containing only current built-in scheme entries."
  (let ((registry (make-hash-table :test #'eq)))
    (maphash
     (lambda (id entry)
       (when (emacsvox-aural-scheme-entry-built-in entry)
         (puthash id entry registry)))
     emacsvox-aural-scheme-registry)
    registry))

(defun emacsvox-aural--built-in-feature-fragment-registry ()
  "Return a registry containing only current built-in feature fragments."
  (let ((registry (make-hash-table :test #'eq)))
    (maphash
     (lambda (id entry)
       (when (emacsvox-aural-feature-fragment-entry-built-in entry)
         (puthash id entry registry)))
     emacsvox-aural-feature-fragment-registry)
    registry))

(defun emacsvox-aural--built-in-voice-palette-registry ()
  "Return a registry containing only current built-in voice palettes."
  (let ((registry (make-hash-table :test #'eq)))
    (maphash
     (lambda (id palette)
       (when (emacsvox-aural-voice-palette-built-in palette)
         (puthash id palette registry)))
     emacsvox-aural-voice-palette-registry)
    registry))

(defun emacsvox-aural-load-user-data (&optional file)
  "Load personal schemes and rules from FILE.

The file is read as data and is never evaluated."
  (when-let* ((data (emacsvox-aural-read-user-data file)))
    (let ((schemes (plist-get data :schemes))
          (fragments (plist-get data :feature-fragments))
          (enabled (plist-get data :enabled-feature-fragments))
          (palettes (plist-get data :voice-palettes))
          (profiles (plist-get data :profiles))
          (rules (plist-get data :user-rules))
          (registry (emacsvox-aural--built-in-scheme-registry))
          (fragment-registry
           (emacsvox-aural--built-in-feature-fragment-registry))
          (palette-registry
           (emacsvox-aural--built-in-voice-palette-registry))
          (profile-registry (make-hash-table :test #'eq))
          entries
          fragment-entries
          palette-entries)
      (dolist (scheme schemes)
        (let* ((compiled (emacsvox-aural-compile-scheme scheme))
               (id (emacsvox-aural-scheme-id compiled)))
          (when (gethash id registry)
            (emacsvox-aural--scheme-error
             "User scheme cannot replace built-in %S" id))
          (push
           (emacsvox-aural--make-scheme-entry
            :id id
            :data (copy-tree scheme)
            :compiled compiled
            :built-in nil
            :source (or file emacsvox-aural-schemes-file))
           entries)))
      (dolist (fragment fragments)
        (let* ((compiled
                (emacsvox-aural--compile-feature-fragment
                 fragment (or file emacsvox-aural-schemes-file)))
               (id (emacsvox-aural-scheme-id compiled)))
          (when (gethash id fragment-registry)
            (emacsvox-aural--scheme-error
             "User feature fragment cannot replace built-in %S" id))
          (push
           (emacsvox-aural--make-feature-fragment-entry
            :id id
            :data (copy-tree fragment)
            :compiled compiled
            :built-in nil
            :source (or file emacsvox-aural-schemes-file))
           fragment-entries)))
      (dolist (entry entries)
        (puthash
         (emacsvox-aural-scheme-entry-id entry)
         entry
         registry))
      (dolist (entry fragment-entries)
        (puthash
         (emacsvox-aural-feature-fragment-entry-id entry)
         entry
         fragment-registry))
      (dolist (palette palettes)
        (condition-case error
            (let* ((entry
                    (emacsvox-aural-compile-voice-palette-data
                     palette nil (or file emacsvox-aural-schemes-file)))
                   (id (emacsvox-aural-voice-palette-id entry)))
              (when (gethash id palette-registry)
                (emacsvox-aural--scheme-error
                 "Personal voice palette cannot replace built-in %S" id))
              (push entry palette-entries))
          (emacsvox-aural-resource-error
           (emacsvox-aural--scheme-error
            "%s" (error-message-string error)))))
      (dolist (entry palette-entries)
        (puthash
         (emacsvox-aural-voice-palette-id entry)
         entry
         palette-registry))
      (dolist (profile profiles)
        (emacsvox-aural--validate-profile-data
         profile registry fragment-registry palette-registry)
        (let* ((id (plist-get profile :id))
               (entry
                (emacsvox-aural--make-profile-entry
                 :id id
                 :data (copy-tree profile)
                 :source (or file emacsvox-aural-schemes-file))))
          (when (gethash id profile-registry)
            (emacsvox-aural--scheme-error
             "Duplicate presentation profile: %S" id))
          (puthash id entry profile-registry)))
      ;; Validate the complete replacement before changing live state.
      (let ((emacsvox-aural-scheme-registry registry)
            (emacsvox-aural-feature-fragment-registry fragment-registry)
            (emacsvox-aural-voice-palette-registry palette-registry)
            (emacsvox-aural-profile-registry profile-registry)
            (emacsvox-aural-enabled-feature-fragments enabled)
            (emacsvox-aural-user-rules rules))
        (maphash
         (lambda (id _)
           (emacsvox-aural--scheme-chain id)
           (emacsvox-aural-effective-scheme-rules id))
         registry)
        (emacsvox-aural--scheme-chain emacsvox-aural-active-scheme)
        (emacsvox-aural--validate-enabled-feature-fragments
         enabled fragment-registry)
        (maphash
         (lambda (id _)
           (emacsvox-aural-effective-voice-entries id))
         palette-registry)
        (emacsvox-aural-current-rules))
      (setq
       emacsvox-aural-scheme-registry registry
       emacsvox-aural-feature-fragment-registry fragment-registry
       emacsvox-aural-voice-palette-registry palette-registry
       emacsvox-aural-profile-registry profile-registry
       emacsvox-aural-enabled-feature-fragments (copy-sequence enabled)
       emacsvox-aural-user-rules (copy-tree rules))
      (emacsvox-aural-configuration-changed 'user-data-loaded)
      (run-hooks 'emacsvox-aural-feature-fragments-changed-hook)
      data)))

(defun emacsvox-aural-user-data ()
  "Return current personal schemes, fragments, palettes, profiles, and rules."
  (let (schemes fragments palettes profiles)
    (maphash
     (lambda (_ entry)
       (unless (emacsvox-aural-scheme-entry-built-in entry)
         (push (copy-tree (emacsvox-aural-scheme-entry-data entry)) schemes)))
     emacsvox-aural-scheme-registry)
    (maphash
     (lambda (_ entry)
       (unless (emacsvox-aural-feature-fragment-entry-built-in entry)
         (push
          (copy-tree (emacsvox-aural-feature-fragment-entry-data entry))
          fragments)))
     emacsvox-aural-feature-fragment-registry)
    (maphash
     (lambda (_ palette)
       (unless (emacsvox-aural-voice-palette-built-in palette)
         (push
          (emacsvox-aural-voice-palette-data-form palette)
          palettes)))
     emacsvox-aural-voice-palette-registry)
    (maphash
     (lambda (_ entry)
       (push
        (copy-tree (emacsvox-aural-profile-entry-data entry))
        profiles))
     emacsvox-aural-profile-registry)
    (setq
     schemes
     (sort
      schemes
      (lambda (left right)
        (string-lessp
         (symbol-name (plist-get left :id))
         (symbol-name (plist-get right :id))))))
    (setq
     fragments
     (sort
      fragments
      (lambda (left right)
        (string-lessp
         (symbol-name (plist-get left :id))
         (symbol-name (plist-get right :id))))))
    (setq
     palettes
     (sort
      palettes
      (lambda (left right)
        (string-lessp
         (symbol-name (plist-get left :id))
         (symbol-name (plist-get right :id))))))
    (setq
     profiles
     (sort
      profiles
      (lambda (left right)
        (string-lessp
         (symbol-name (plist-get left :id))
         (symbol-name (plist-get right :id))))))
    (list
     :schema-version emacsvox-aural-user-data-schema-version
     :schemes schemes
     :feature-fragments fragments
     :enabled-feature-fragments
     (copy-sequence emacsvox-aural-enabled-feature-fragments)
     :voice-palettes palettes
     :profiles profiles
     :user-rules (copy-tree emacsvox-aural-user-rules))))

(defun emacsvox-aural-save-user-data (&optional file)
  "Atomically save personal scheme data to FILE.

An existing file is copied to FILE~ before replacement."
  (let* ((file (expand-file-name (or file emacsvox-aural-schemes-file)))
         (directory (file-name-directory file))
         (data (emacsvox-aural--validate-user-data
                (emacsvox-aural-user-data)))
         temporary)
    (make-directory directory t)
    (setq temporary
          (make-temp-file
           (expand-file-name ".aural-schemes-" directory)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert ";;; Aural presentation scheme data -*- mode: emacs-lisp; -*-\n")
            (insert ";;; This file is read as data and is not evaluated.\n\n")
            (let ((print-length nil)
                  (print-level nil))
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

(defun emacsvox-aural--register-default-scheme ()
  "Register the built-in compatibility-preserving default scheme."
  (unless (emacsvox-aural-scheme-entry 'default)
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id default
       :summary "Compatibility-preserving Emacsvox presentation"
       :resource-pack chimes
       :voice-palette acss-default
       :rules ())
     :built-in t
     :source "built-in")))

(emacsvox-aural--register-default-scheme)

(provide 'emacsvox-aural-schemes)
;;; emacsvox-aural-schemes.el ends here
