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

(defgroup emacsvox-aural nil
  "Semantic aural presentation schemes."
  :group 'emacsvox
  :prefix "emacsvox-aural-")

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

(defvar emacsvox-aural-scheme-registry (make-hash-table :test #'eq)
  "Map scheme identifiers to `emacsvox-aural-scheme-entry' records.")

(defvar emacsvox-aural-module-fragment-registry
  (make-hash-table :test #'eq)
  "Map fragment identifiers to read-only module rule fragments.")

(defvar emacsvox-aural-feature-fragment-registry
  (make-hash-table :test #'eq)
  "Map optional feature fragment identifiers to their records.")

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

(defcustom emacsvox-aural-schemes-file
  (expand-file-name "aural-schemes.el" emacsvox-user-directory)
  "Data-only file containing personal aural schemes and rules."
  :type 'file
  :group 'emacsvox-aural)

(defconst emacsvox-aural-user-data-schema-version 2
  "Current schema version for the personal scheme data file.")

(defun emacsvox-aural--migrate-user-data-v1-to-v2 (data)
  "Add feature-fragment storage to version 1 user DATA."
  (setq data (plist-put data :feature-fragments nil))
  (setq data (plist-put data :enabled-feature-fragments nil))
  (plist-put data :schema-version 2))

(defconst emacsvox-aural--built-in-user-data-migrations
  '((1 . emacsvox-aural--migrate-user-data-v1-to-v2))
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

(defun emacsvox-aural-effective-scheme-provider (property &optional id)
  "Return inherited provider PROPERTY for scheme ID or the active scheme.

PROPERTY is `resource-pack' or `voice-palette'."
  (unless (memq property '(resource-pack voice-palette))
    (emacsvox-aural--scheme-error
     "Unknown scheme provider property: %S" property))
  (let (value)
    (dolist
        (entry
         (emacsvox-aural--scheme-chain
          (or id emacsvox-aural-active-scheme)))
      (let ((scheme (emacsvox-aural-scheme-entry-compiled entry)))
        (pcase property
          ('resource-pack
           (when (emacsvox-aural-scheme-resource-pack scheme)
             (setq value (emacsvox-aural-scheme-resource-pack scheme))))
          ('voice-palette
           (when (emacsvox-aural-scheme-voice-palette scheme)
             (setq value (emacsvox-aural-scheme-voice-palette scheme)))))))
    value))

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

(defun emacsvox-aural-current-rules (&optional context)
  "Return every compiled rule layer relevant to CONTEXT."
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
      emacsvox-aural-buffer-rules 'buffer (current-buffer) t)))))

(defun emacsvox-aural-current-context
    (module occasion &optional legacy-personality legacy-source)
  "Capture current MODULE, OCCASION, and legacy presentation hints."
  (list
   :module (or module emacsvox-aural-module)
   :mode major-mode
   :mode-lineage (emacsvox-aural-mode-lineage major-mode)
   :occasion occasion
   :legacy-personality legacy-personality
   :legacy-source legacy-source
   :source-buffer (current-buffer)
   :source-buffer-name (buffer-name)))

(defun emacsvox-aural-resolve-active (facts &optional context)
  "Resolve FACTS through active scheme and contextual rule layers."
  (let* ((context
          (or
           context
           (emacsvox-aural-current-context nil 'continuous)))
         (legacy (plist-get context :legacy-personality))
         (source (or (plist-get context :legacy-source) 'legacy-personality))
         (plan
          (emacsvox-aural-resolve
           facts context (emacsvox-aural-current-rules context)))
         (content (emacsvox-aural-render-plan-content plan)))
    (when
        (and
         legacy
         (not
          (assq
           'voice
           (emacsvox-aural-content-style-provenance content))))
      (setf (emacsvox-aural-content-style-voice content) legacy)
      (setf
       (emacsvox-aural-content-style-provenance content)
       (cons
        (cons 'voice source)
        (emacsvox-aural-content-style-provenance content))))
    plan))

(defun emacsvox-aural-resolve-legacy-icon (icon &optional context facts)
  "Resolve legacy ICON through the active scheme in CONTEXT.

The returned plan initially contains ICON as action `legacy-cue'.  Contextual
rules can remove that action or replace its cue without changing callers.
Optional FACTS are composed with any known semantic event for ICON."
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
         (compatibility-rule
          (emacsvox-aural-compile-rule
           (list
            :id 'legacy-cue-default
            :match (list :legacy-cue icon)
            :render
            (list
             :before
             (list
              (list :id 'legacy-cue :kind 'cue :cue icon))))
           'core 0 "legacy icon adapter")))
    (emacsvox-aural-resolve
     facts
     context
     (emacsvox-aural--require-unique-rule-ids
      (cons
       compatibility-rule
       (emacsvox-aural-current-rules context))))))

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

(defun emacsvox-aural--validate-user-data (data)
  "Validate and return current-schema user DATA."
  (emacsvox-aural--require-plist data "Aural user data")
  (let ((version (plist-get data :schema-version))
        (schemes (plist-get data :schemes))
        (fragments (plist-get data :feature-fragments))
        (enabled (plist-get data :enabled-feature-fragments))
        (rules (plist-get data :user-rules))
        (unknown
         (cl-loop
          for (key _) on data by #'cddr
          unless
          (memq
           key
           '(:schema-version :schemes :feature-fragments
             :enabled-feature-fragments :user-rules))
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
    (unless (listp rules)
      (emacsvox-aural--scheme-error "User rules must be a list"))
    (let (ids)
      (dolist (scheme schemes)
        (let ((compiled (emacsvox-aural-compile-scheme scheme)))
          (when (memq (emacsvox-aural-scheme-id compiled) ids)
            (emacsvox-aural--scheme-error
             "Duplicate user scheme: %S"
             (emacsvox-aural-scheme-id compiled)))
          (push (emacsvox-aural-scheme-id compiled) ids))))
    (let ((registry
           (emacsvox-aural--built-in-feature-fragment-registry))
          ids)
      (dolist (fragment fragments)
        (let* ((compiled
                (emacsvox-aural--compile-feature-fragment fragment))
               (id (emacsvox-aural-scheme-id compiled)))
          (when (or (memq id ids) (gethash id registry))
            (emacsvox-aural--scheme-error
             "Duplicate or protected user feature fragment: %S" id))
          (push id ids)
          (puthash id t registry)))
      (emacsvox-aural--validate-enabled-feature-fragments enabled registry))
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
        (let ((read-eval nil))
          (let ((data (read (current-buffer))))
            (forward-comment (point-max))
            (unless (eobp)
              (emacsvox-aural--scheme-error
               "Trailing data in %s" file))
            (emacsvox-aural-migrate-user-data data)))))))

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

(defun emacsvox-aural-load-user-data (&optional file)
  "Load personal schemes and rules from FILE.

The file is read as data and is never evaluated."
  (when-let* ((data (emacsvox-aural-read-user-data file)))
    (let ((schemes (plist-get data :schemes))
          (fragments (plist-get data :feature-fragments))
          (enabled (plist-get data :enabled-feature-fragments))
          (rules (plist-get data :user-rules))
          (registry (emacsvox-aural--built-in-scheme-registry))
          (fragment-registry
           (emacsvox-aural--built-in-feature-fragment-registry))
          entries
          fragment-entries)
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
      ;; Validate the complete replacement before changing live state.
      (let ((emacsvox-aural-scheme-registry registry)
            (emacsvox-aural-feature-fragment-registry fragment-registry)
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
        (emacsvox-aural-current-rules))
      (setq
       emacsvox-aural-scheme-registry registry
       emacsvox-aural-feature-fragment-registry fragment-registry
       emacsvox-aural-enabled-feature-fragments (copy-sequence enabled)
       emacsvox-aural-user-rules (copy-tree rules))
      (run-hooks 'emacsvox-aural-feature-fragments-changed-hook)
      data)))

(defun emacsvox-aural-user-data ()
  "Return current personal schemes, fragments, and rules as versioned data."
  (let (schemes fragments)
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
    (list
     :schema-version emacsvox-aural-user-data-schema-version
     :schemes schemes
     :feature-fragments fragments
     :enabled-feature-fragments
     (copy-sequence emacsvox-aural-enabled-feature-fragments)
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
