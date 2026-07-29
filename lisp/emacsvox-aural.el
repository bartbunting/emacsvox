;;; emacsvox-aural.el --- Semantic aural presentation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; This module owns the device-independent vocabulary used by aural
;; presentation schemes.  It deliberately contains no speech-server, sound
;; player, major-mode, or resource resolution.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup emacsvox-aural nil
  "Semantic aural presentation schemes."
  :group 'emacsvox
  :prefix "emacsvox-aural-")

(defcustom emacsvox-aural-face-presentation-enabled t
  "Whether rules selected by explicit visual faces participate.

This control affects rules with a `:legacy-face' selector.  It does not
disable semantic role, state, event, or attribute presentation, and it does
not replace `voice-lock-mode'.  Voice Lock continues to control only the
legacy face/personality-to-voice compatibility mapping."
  :type 'boolean
  :group 'emacsvox-aural)

(defvar emacsvox-aural-face-presentation-changed-hook nil
  "Hook run after explicit visual-face presentation is toggled.")

(defvar-local emacsvox-aural-suppressed-personalities nil
  "Compatibility personalities suppressed in the current buffer.

The value is nil or an `equal' hash table whose keys are legacy personality
values.  Suppression affects content voice policy, not semantic actions.")

(defvar voice-lock-mode)
(defvar emacsvox-use-icons)

(declare-function tts-speak "tts-speak" (text))

(defun emacsvox-aural-compatibility-voice-enabled-p (&optional buffer)
  "Return whether legacy compatibility voices are active in BUFFER.

Before Voice Lock is loaded, preserve the historical enabled default."
  (with-current-buffer (or buffer (current-buffer))
    (or (not (boundp 'voice-lock-mode))
        (not (null voice-lock-mode)))))

(defun emacsvox-aural-voice-lock-enabled-p (&optional buffer)
  "Return whether the Voice Lock compatibility adapter is active in BUFFER."
  (emacsvox-aural-compatibility-voice-enabled-p buffer))

(defun emacsvox-aural-voice-inaudible-p (voice)
  "Return non-nil when VOICE requests compatibility content suppression."
  (or
   (eq voice 'inaudible)
   (and (proper-list-p voice) (memq 'inaudible voice))))

(defun emacsvox-aural-filter-compatibility-voice (voice)
  "Apply the current buffer's local compatibility policy to VOICE."
  (if
      (and
       voice
       emacsvox-aural-suppressed-personalities
       (gethash voice emacsvox-aural-suppressed-personalities))
      'inaudible
    voice))

(defun emacsvox-aural-icons-enabled-p (&optional context buffer)
  "Return whether cue actions are enabled for CONTEXT in BUFFER.

An explicit `:icons-enabled' value in CONTEXT is authoritative.  Otherwise
read the buffer-local `emacsvox-use-icons' value in BUFFER, defaulting to
enabled before the sound compatibility layer has been loaded."
  (if (plist-member context :icons-enabled)
      (plist-get context :icons-enabled)
    (with-current-buffer (or buffer (current-buffer))
      (or
       (not (boundp 'emacsvox-use-icons))
       (not (null emacsvox-use-icons))))))

;;;###autoload
(defun emacsvox-aural-toggle-face-presentation (&optional arg)
  "Toggle explicit visual-face presentation.

With a positive prefix ARG, enable it.  With zero or a negative prefix,
disable it.  This does not change semantic presentation or Voice Lock."
  (interactive "P")
  (setq
   emacsvox-aural-face-presentation-enabled
   (if (null arg)
       (not emacsvox-aural-face-presentation-enabled)
     (> (prefix-numeric-value arg) 0)))
  (run-hooks 'emacsvox-aural-face-presentation-changed-hook)
  (when (called-interactively-p 'interactive)
    (let ((text
           (format
            "Visual face presentation %s. Voice Lock remains independent."
            (if emacsvox-aural-face-presentation-enabled
                "enabled"
              "disabled"))))
      (if (fboundp 'tts-speak)
          (tts-speak text)
        (message "%s" text))))
  emacsvox-aural-face-presentation-enabled)

(define-error
  'emacsvox-aural-registration-error
  "Invalid Emacsvox aural registry entry")

(cl-defstruct
    (emacsvox-aural-semantic
     (:constructor emacsvox-aural--make-semantic))
  "A registered semantic object, event, state, or attribute."
  id
  kind
  summary
  owner
  value-type
  allowed-values
  fallback
  occasions
  phases
  usage
  roles
  attributes
  states
  events)

(cl-defstruct
    (emacsvox-aural-semantic-alias
     (:constructor emacsvox-aural--make-semantic-alias))
  "A stable deprecated name for a canonical semantic identifier."
  id
  target
  owner
  summary
  since-version)

(cl-defstruct
    (emacsvox-aural-occasion
     (:constructor emacsvox-aural--make-occasion))
  "A registered reason for presenting semantic facts."
  id
  summary
  owner
  usage)

(defconst emacsvox-aural-semantic-kinds
  '(role event state attribute)
  "Valid kinds for semantic registry entries.")

(defconst emacsvox-aural-render-phases
  '(before content after)
  "Valid phases named by semantic registration metadata.")

(defconst emacsvox-aural-semantic-schema-version 1
  "Current version of the operational semantic identifier contract.")

(defvar emacsvox-aural-semantic-registry
  (make-hash-table :test #'eq)
  "Map semantic identifiers to `emacsvox-aural-semantic' records.")

(defvar emacsvox-aural-occasion-registry
  (make-hash-table :test #'eq)
  "Map occasion identifiers to `emacsvox-aural-occasion' records.")

(defvar emacsvox-aural-semantic-alias-registry
  (make-hash-table :test #'eq)
  "Map deprecated semantic identifiers to stable alias records.")

(defconst emacsvox-aural-legacy-icon-semantics
  '((emacsvox . product-identity)
    (repeat-stop . activity-ended)
    (unmark-object . selection-cleared)
    (shutdown . game-over))
  "Compatibility mapping from ambiguous legacy icons to semantic events.")

(defun emacsvox-aural--registration-error (format-string &rest arguments)
  "Signal a registration error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-registration-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural--validate-id (id label)
  "Return ID when it is a non-keyword symbol, otherwise report LABEL."
  (unless (and (symbolp id) id (not (keywordp id)))
    (emacsvox-aural--registration-error
     "%s must be a non-keyword symbol: %S" label id))
  id)

(defun emacsvox-aural--validate-summary (summary label)
  "Return SUMMARY when it is nonempty, otherwise report LABEL."
  (unless (and (stringp summary) (not (string-empty-p summary)))
    (emacsvox-aural--registration-error
     "%s summary must be a nonempty string" label))
  summary)

(defun emacsvox-aural--validate-symbol-list (values valid label)
  "Validate VALUES as unique symbols from VALID for LABEL."
  (unless (and (listp values)
               (cl-every #'symbolp values)
               (= (length values) (length (delete-dups (copy-sequence values))))
               (or (null valid)
                   (cl-every (lambda (value) (memq value valid)) values)))
    (emacsvox-aural--registration-error
     "Invalid %s list: %S" label values))
  values)

(cl-defun emacsvox-aural-register-semantic
    (id &key kind summary (owner 'core) value-type allowed-values fallback
        occasions phases usage roles attributes states events)
  "Register semantic ID and return its immutable registry record.

KIND is one of `role', `event', `state', or `attribute'.  SUMMARY and OWNER
document intent and ownership.  VALUE-TYPE and ALLOWED-VALUES constrain
attributes.  FALLBACK names another semantic identifier.  OCCASIONS and PHASES
restrict supported presentation contexts when non-nil.  ROLES restricts the
roles with which a state, event, or attribute may occur.  ATTRIBUTES, STATES,
and EVENTS restrict facts permitted with a role.  USAGE is optional extended
help.  Cross-references are checked by `emacsvox-aural-validate-registry'."
  (emacsvox-aural--validate-id id "Semantic identifier")
  (unless (memq kind emacsvox-aural-semantic-kinds)
    (emacsvox-aural--registration-error
     "Invalid semantic kind for %S: %S" id kind))
  (emacsvox-aural--validate-summary summary (format "Semantic %S" id))
  (emacsvox-aural--validate-id owner (format "Owner for %S" id))
  (when fallback
    (emacsvox-aural--validate-id fallback (format "Fallback for %S" id)))
  (when occasions
    (emacsvox-aural--validate-symbol-list occasions nil "occasion"))
  (when phases
    (emacsvox-aural--validate-symbol-list
     phases emacsvox-aural-render-phases "phase"))
  (dolist (contract
           `((,roles . "role")
             (,attributes . "attribute")
             (,states . "state")
             (,events . "event")))
    (when (car contract)
      (emacsvox-aural--validate-symbol-list
       (car contract) nil (cdr contract))))
  (when (and roles (eq kind 'role))
    (emacsvox-aural--registration-error
     "Role %S may not declare a :roles restriction" id))
  (when (and (or attributes states events) (not (eq kind 'role)))
    (emacsvox-aural--registration-error
     "Only roles may restrict attributes, states, or events: %S" id))
  (when (and allowed-values (not (eq kind 'attribute)))
    (emacsvox-aural--registration-error
     "Only attributes may declare allowed values: %S" id))
  (when (and value-type (not (eq kind 'attribute)))
    (emacsvox-aural--registration-error
     "Only attributes may declare a value type: %S" id))
  (when (or
         (gethash id emacsvox-aural-semantic-registry)
         (gethash id emacsvox-aural-semantic-alias-registry))
    (emacsvox-aural--registration-error
     "Semantic identifier is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-semantic
          :id id
          :kind kind
          :summary summary
          :owner owner
          :value-type value-type
          :allowed-values (copy-tree allowed-values)
          :fallback fallback
          :occasions (copy-sequence occasions)
          :phases (copy-sequence phases)
          :usage usage
          :roles (copy-sequence roles)
          :attributes (copy-sequence attributes)
          :states (copy-sequence states)
          :events (copy-sequence events))))
    (puthash id record emacsvox-aural-semantic-registry)
    record))

(cl-defun emacsvox-aural-register-semantic-alias
    (id target &key (owner 'core) summary
        (since-version emacsvox-aural-semantic-schema-version))
  "Register deprecated semantic ID as an alias for canonical TARGET.

SINCE-VERSION records the semantic contract version in which TARGET became
canonical.  Alias use remains supported, but rule and fact compilation expose
a deprecation diagnostic."
  (emacsvox-aural--validate-id id "Semantic alias")
  (emacsvox-aural--validate-id target (format "Alias target for %S" id))
  (emacsvox-aural--validate-id owner (format "Alias owner for %S" id))
  (when summary
    (emacsvox-aural--validate-summary summary (format "Alias %S" id)))
  (unless (and (integerp since-version) (> since-version 0))
    (emacsvox-aural--registration-error
     "Alias %S version must be a positive integer: %S" id since-version))
  (when (> since-version emacsvox-aural-semantic-schema-version)
    (emacsvox-aural--registration-error
     "Alias %S requires future semantic version %S"
     id since-version))
  (when (or
         (gethash id emacsvox-aural-semantic-registry)
         (gethash id emacsvox-aural-semantic-alias-registry))
    (emacsvox-aural--registration-error
     "Semantic identifier is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-semantic-alias
          :id id
          :target target
          :owner owner
          :summary summary
          :since-version since-version)))
    (puthash id record emacsvox-aural-semantic-alias-registry)
    record))

(defun emacsvox-aural-semantic-alias (id)
  "Return the semantic alias record named ID, or nil."
  (gethash id emacsvox-aural-semantic-alias-registry))

(defun emacsvox-aural-canonical-semantic-id (id)
  "Return the stable canonical identifier for semantic ID.

Return ID unchanged when it is neither a registered semantic nor an alias.
Registry validation rejects missing targets and alias cycles."
  (let ((current id)
        seen)
    (while-let ((alias (emacsvox-aural-semantic-alias current)))
      (when (memq current seen)
        (emacsvox-aural--registration-error
         "Semantic alias cycle: %S" (nreverse (cons current seen))))
      (push current seen)
      (setq current (emacsvox-aural-semantic-alias-target alias)))
    current))

(defun emacsvox-aural-semantic-alias-diagnostic (id)
  "Return a deprecation diagnostic for semantic alias ID, or nil."
  (when-let* ((alias (emacsvox-aural-semantic-alias id)))
    (format
     "Semantic %s is deprecated since contract version %d; use %s%s"
     id
     (emacsvox-aural-semantic-alias-since-version alias)
     (emacsvox-aural-canonical-semantic-id id)
     (if-let* ((summary (emacsvox-aural-semantic-alias-summary alias)))
         (format " (%s)" summary)
       ""))))

(cl-defun emacsvox-aural-register-occasion
    (id &key summary (owner 'core) usage)
  "Register presentation occasion ID and return its registry record."
  (emacsvox-aural--validate-id id "Occasion identifier")
  (emacsvox-aural--validate-summary summary (format "Occasion %S" id))
  (emacsvox-aural--validate-id owner (format "Owner for %S" id))
  (when (gethash id emacsvox-aural-occasion-registry)
    (emacsvox-aural--registration-error
     "Occasion identifier is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-occasion
          :id id :summary summary :owner owner :usage usage)))
    (puthash id record emacsvox-aural-occasion-registry)
    record))

(defun emacsvox-aural-semantic (id)
  "Return the registered semantic record for ID, or nil."
  (gethash
   (emacsvox-aural-canonical-semantic-id id)
   emacsvox-aural-semantic-registry))

(defun emacsvox-aural-occasion (id)
  "Return the registered presentation occasion record for ID, or nil."
  (gethash id emacsvox-aural-occasion-registry))

(defun emacsvox-aural--sorted-records (table accessor)
  "Return records from TABLE sorted by the symbol returned by ACCESSOR."
  (let (records)
    (maphash (lambda (_ record) (push record records)) table)
    (sort
     records
     (lambda (left right)
       (string-lessp
        (symbol-name (funcall accessor left))
        (symbol-name (funcall accessor right)))))))

(defun emacsvox-aural-semantics ()
  "Return all semantic registry records in identifier order."
  (emacsvox-aural--sorted-records
   emacsvox-aural-semantic-registry
   #'emacsvox-aural-semantic-id))

(defun emacsvox-aural-semantic-aliases ()
  "Return all semantic alias records in identifier order."
  (emacsvox-aural--sorted-records
   emacsvox-aural-semantic-alias-registry
   #'emacsvox-aural-semantic-alias-id))

(defun emacsvox-aural-occasions ()
  "Return all presentation occasion records in identifier order."
  (emacsvox-aural--sorted-records
   emacsvox-aural-occasion-registry
   #'emacsvox-aural-occasion-id))

(defun emacsvox-aural-semantic-candidates ()
  "Return registered semantic identifiers as completion strings."
  (mapcar
   (lambda (record)
     (symbol-name (emacsvox-aural-semantic-id record)))
   (emacsvox-aural-semantics)))

(defun emacsvox-aural-occasion-candidates ()
  "Return registered occasion identifiers as completion strings."
  (mapcar
   (lambda (record)
     (symbol-name (emacsvox-aural-occasion-id record)))
   (emacsvox-aural-occasions)))

(defun emacsvox-aural-semantic-description (id)
  "Return a concise description of registered semantic ID."
  (when-let* ((record (emacsvox-aural-semantic id)))
    (format
     "%s (%s, owner %s): %s%s"
     (emacsvox-aural-semantic-id record)
     (emacsvox-aural-semantic-kind record)
     (emacsvox-aural-semantic-owner record)
     (emacsvox-aural-semantic-summary record)
     (if-let* ((fallback (emacsvox-aural-semantic-fallback record)))
         (format "; fallback %s" fallback)
       ""))))

(defun emacsvox-aural--validate-fallbacks ()
  "Validate semantic fallback existence and cycles."
  (dolist (record (emacsvox-aural-semantics))
    (let ((current record)
          path)
      (while (emacsvox-aural-semantic-fallback current)
        (let ((fallback (emacsvox-aural-semantic-fallback current)))
          (when (memq fallback path)
            (emacsvox-aural--registration-error
             "Semantic fallback cycle: %S"
             (nreverse (cons fallback path))))
          (push (emacsvox-aural-semantic-id current) path)
          (setq current (emacsvox-aural-semantic fallback))
          (unless current
            (emacsvox-aural--registration-error
             "Unknown semantic fallback %S in path %S"
             fallback
             (nreverse path)))
          (unless
              (eq
               (emacsvox-aural-semantic-kind record)
               (emacsvox-aural-semantic-kind current))
            (emacsvox-aural--registration-error
             "Semantic fallback %S for %S has kind %S, expected %S"
             fallback
             (emacsvox-aural-semantic-id record)
             (emacsvox-aural-semantic-kind current)
             (emacsvox-aural-semantic-kind record)))))))
  t)

(defun emacsvox-aural--validate-semantic-reference-list
    (record field kind)
  "Validate semantic RECORD's FIELD as references of KIND."
  (dolist (id (funcall field record))
    (let ((target (emacsvox-aural-semantic id)))
      (unless target
        (emacsvox-aural--registration-error
         "Semantic %S names unknown %S %S"
         (emacsvox-aural-semantic-id record) kind id))
      (unless (eq (emacsvox-aural-semantic-kind target) kind)
        (emacsvox-aural--registration-error
         "Semantic %S names %S %S registered as %S"
         (emacsvox-aural-semantic-id record)
         kind id (emacsvox-aural-semantic-kind target))))))

(defun emacsvox-aural--validate-aliases ()
  "Validate semantic alias targets and cycles."
  (dolist (alias (emacsvox-aural-semantic-aliases))
    (let ((target
           (emacsvox-aural-canonical-semantic-id
            (emacsvox-aural-semantic-alias-id alias))))
      (unless (gethash target emacsvox-aural-semantic-registry)
        (emacsvox-aural--registration-error
         "Semantic alias %S names unknown target %S"
         (emacsvox-aural-semantic-alias-id alias) target))))
  t)

(defun emacsvox-aural-validate-registry ()
  "Validate cross-references in the semantic and occasion registries."
  (dolist (record (emacsvox-aural-semantics))
    (dolist (occasion (emacsvox-aural-semantic-occasions record))
      (unless (emacsvox-aural-occasion occasion)
        (emacsvox-aural--registration-error
         "Semantic %S names unknown occasion %S"
         (emacsvox-aural-semantic-id record)
         occasion)))
    (emacsvox-aural--validate-semantic-reference-list
     record #'emacsvox-aural-semantic-roles 'role)
    (emacsvox-aural--validate-semantic-reference-list
     record #'emacsvox-aural-semantic-attributes 'attribute)
    (emacsvox-aural--validate-semantic-reference-list
     record #'emacsvox-aural-semantic-states 'state)
    (emacsvox-aural--validate-semantic-reference-list
     record #'emacsvox-aural-semantic-events 'event))
  (emacsvox-aural--validate-aliases)
  (emacsvox-aural--validate-fallbacks))

(defun emacsvox-aural-audit-semantic-ids (ids)
  "Return unique unregistered semantic identifiers found in IDS."
  (let (unknown)
    (dolist (id ids)
      (unless (or (memq id unknown) (emacsvox-aural-semantic id))
        (push id unknown)))
    (sort unknown
          (lambda (left right)
            (string-lessp (symbol-name left) (symbol-name right))))))

(defun emacsvox-aural-legacy-icon-input (icon)
  "Describe legacy ICON as presentation input without playing it."
  (list
   :source 'legacy-icon
   :cue icon
   :semantic (alist-get icon emacsvox-aural-legacy-icon-semantics)))

(defun emacsvox-aural-legacy-personality-input (personality &optional source)
  "Describe legacy PERSONALITY as a presentation hint from SOURCE."
  (list
   :source (or source 'personality-property)
   :voice personality))

(defun emacsvox-aural--register-builtins ()
  "Register the initial core vocabulary and presentation occasions."
  (dolist
      (definition
       '((navigation "Point or focus moved to the object")
         (continuous "Continuous reading reached the object")
         (state-change "An action changed a registered state")
         (edit "The object was created or changed")
         (inspection "The user requested detail or explanation")
         (notification "An asynchronous event requested attention")))
    (unless (emacsvox-aural-occasion (car definition))
      (emacsvox-aural-register-occasion
       (car definition) :summary (cadr definition))))
  (dolist
      (definition
       '((heading role "A titled structural section")
         (folded state "Descendants of an object are hidden")
         (focus-entered event "Navigation arrived at an aural object")
         (state-changed event "A registered state changed")
         (object-changed event "A registered object was created or modified")
         (product-identity event "Emacsvox identity or readiness was presented")
         (activity-ended event "A repeating or ongoing activity ended")
         (selection-cleared event "A mark or selection was removed")
         (game-over event "A game ended without successful completion")))
    (unless (emacsvox-aural-semantic (car definition))
      (emacsvox-aural-register-semantic
       (car definition)
       :kind (cadr definition)
       :summary (caddr definition))))
  (unless (emacsvox-aural-semantic 'level)
    (emacsvox-aural-register-semantic
     'level
     :kind 'attribute
     :summary "One-based structural depth"
     :value-type 'positive-integer))
  (unless (emacsvox-aural-semantic 'visibility)
    (emacsvox-aural-register-semantic
     'visibility
     :kind 'attribute
     :summary "Whether structural descendants are visible"
     :value-type 'symbol
     :allowed-values '(folded expanded)))
  (unless (emacsvox-aural-semantic 'line-condition)
    (emacsvox-aural-register-semantic
     'line-condition
     :kind 'attribute
     :summary "Why the selected line segment is represented without text"
     :value-type 'symbol
     :allowed-values
     '(empty whitespace-only separator decorative unspeakable)
     :usage
     "Describes the result of line selection, filtering, and punctuation policy."))
  (unless (emacsvox-aural-semantic 'edit-operation)
    (emacsvox-aural-register-semantic
     'edit-operation
     :kind 'attribute
     :summary "The text-editing operation being presented"
     :value-type 'symbol
     :allowed-values '(deletion line-created uppercase lowercase capitalize)
     :occasions '(edit)
     :usage
     "Lets presentation policy replace fixed feedback for editing operations."))
  (unless (emacsvox-aural-semantic-alias 'collapsed)
    (emacsvox-aural-register-semantic-alias
     'collapsed 'folded
     :summary "Use the canonical folded state identifier"))
  (emacsvox-aural-validate-registry))

(emacsvox-aural--register-builtins)

(provide 'emacsvox-aural)
;;; emacsvox-aural.el ends here
