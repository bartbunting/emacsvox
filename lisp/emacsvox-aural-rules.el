;;; emacsvox-aural-rules.el --- Aural scheme rule engine -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Compile safe versioned plist schemes into validated internal structures,
;; match them against semantic facts and source context, and produce an ordered
;; backend-independent render plan.  This module performs no audio or speech
;; I/O.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural)

(define-error
  'emacsvox-aural-rule-error
  "Invalid Emacsvox aural presentation rule")

(defconst emacsvox-aural-scheme-schema-version 1
  "Current declarative aural scheme schema version.")

(defconst emacsvox-aural-origin-ranks
  '((core . 0)
    (module . 1)
    (scheme . 2)
    (user . 3)
    (session . 4)
    (buffer . 5))
  "Resolver origin layers ordered from weakest to strongest.")

(defconst emacsvox-aural-action-kinds
  '(speech cue pause)
  "Action kinds supported by the initial pure render-plan engine.")

(defconst emacsvox-aural--selector-keys
  '(:role :event :events :state :states :module :mode :occasion
    :legacy-cue :legacy-personality)
  "Reserved selector keys that are not registered semantic attributes.")

(defconst emacsvox-aural--fact-keys
  '(:role :event :events :state :states :content)
  "Reserved semantic fact keys that are not registered attributes.")

(defconst emacsvox-aural--context-keys
  '(:module :mode :mode-lineage :occasion :legacy-cue
    :legacy-personality :legacy-source :source-buffer
    :source-buffer-name)
  "Keys accepted in a presentation context plist.")

(cl-defstruct
    (emacsvox-aural-selector
     (:constructor emacsvox-aural--make-selector))
  "A validated selector compiled from declarative rule data."
  role events states attributes module mode occasion legacy-cue
  legacy-personality)

(cl-defstruct
    (emacsvox-aural-action
     (:constructor emacsvox-aural--make-action))
  "A validated backend-independent action."
  id kind text cue duration voice volume space source)

(cl-defstruct
    (emacsvox-aural-phase-operations
     (:constructor emacsvox-aural--make-phase-operations))
  "Ordered operations contributed to a before or after phase."
  suppress
  replace-set-p
  replace
  remove
  prepend
  append)

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
  id origin layer-order order selector contribution source)

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
  legacy-cue legacy-personality legacy-source source-buffer
  source-buffer-name)

(cl-defstruct
    (emacsvox-aural-content-style
     (:constructor emacsvox-aural--make-content-style))
  "Resolved scalar styling for object content."
  speak voice volume space provenance)

(cl-defstruct
    (emacsvox-aural-render-plan
     (:constructor emacsvox-aural--make-render-plan))
  "Ordered backend-independent result of rule resolution."
  before content after matched-rules rule-scores)

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

(defun emacsvox-aural--require-kind (id kind label)
  "Return semantic ID when registered as KIND, otherwise report LABEL."
  (let ((record (emacsvox-aural-semantic id)))
    (unless record
      (emacsvox-aural--rule-error "%s is not registered: %S" label id))
    (unless (eq (emacsvox-aural-semantic-kind record) kind)
      (emacsvox-aural--rule-error
       "%s %S is registered as %S, not %S"
       label id (emacsvox-aural-semantic-kind record) kind))
    id))

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
  "Extract registered attributes from PLIST excluding RESERVED keys."
  (let (attributes)
    (cl-loop
     for (key value) on plist by #'cddr
     unless (memq key reserved)
     do
     (let* ((id (emacsvox-aural--keyword-attribute key))
            (record (emacsvox-aural-semantic id)))
       (unless (and record (eq (emacsvox-aural-semantic-kind record) 'attribute))
         (emacsvox-aural--rule-error
          "%s contains unknown attribute %S" label key))
       (unless (emacsvox-aural--valid-attribute-value-p record value)
         (emacsvox-aural--rule-error
          "%s has invalid value for %S: %S" label id value))
       (push (cons id value) attributes)))
    (nreverse attributes)))

(defun emacsvox-aural--compile-selector (selector rule-id)
  "Compile SELECTOR for RULE-ID."
  (emacsvox-aural--require-plist selector (format "Selector for %S" rule-id))
  (let* ((role (plist-get selector :role))
         (events
          (emacsvox-aural--normalize-symbols
           (plist-get selector :event)
           (plist-get selector :events)
           "Selector events"))
         (states
          (emacsvox-aural--normalize-symbols
           (plist-get selector :state)
           (plist-get selector :states)
           "Selector states"))
         (module (plist-get selector :module))
         (mode (plist-get selector :mode))
         (occasion (plist-get selector :occasion))
         (legacy-cue (plist-get selector :legacy-cue))
         (legacy-personality (plist-get selector :legacy-personality))
         (attributes
          (emacsvox-aural--extract-attributes
           selector emacsvox-aural--selector-keys
           (format "Selector for %S" rule-id))))
    (when role
      (emacsvox-aural--require-kind role 'role "Selector role"))
    (dolist (event events)
      (emacsvox-aural--require-kind event 'event "Selector event"))
    (dolist (state states)
      (emacsvox-aural--require-kind state 'state "Selector state"))
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
    (when legacy-personality
      (unless (or (symbolp legacy-personality) (consp legacy-personality))
        (emacsvox-aural--rule-error
         "Selector legacy personality must be a symbol or cons: %S"
         legacy-personality)))
    (emacsvox-aural--make-selector
     :role role
     :events events
     :states states
     :attributes attributes
     :module module
     :mode mode
     :occasion occasion
     :legacy-cue legacy-cue
     :legacy-personality legacy-personality)))

(defun emacsvox-aural--compile-action (data rule-id phase index)
  "Compile action DATA contributed by RULE-ID in PHASE at INDEX."
  (emacsvox-aural--require-plist
   data (format "%S action %d for %S" phase index rule-id))
  (let* ((kind (plist-get data :kind))
         (id
          (or
           (plist-get data :id)
           (intern (format "%s/%s/%d" rule-id phase index))))
         (text (plist-get data :text))
         (cue (or (plist-get data :cue) (plist-get data :name)))
         (duration (plist-get data :duration))
         (voice (plist-get data :voice))
         (volume (plist-get data :volume))
         (space (plist-get data :space)))
    (emacsvox-aural--require-symbol id "Action identifier")
    (unless (memq kind emacsvox-aural-action-kinds)
      (emacsvox-aural--rule-error
       "Invalid action kind for %S: %S" id kind))
    (pcase kind
      ('speech
       (unless (and (stringp text) (not (string-empty-p text)))
         (emacsvox-aural--rule-error
          "Speech action %S requires nonempty :text" id)))
      ('cue
       (emacsvox-aural--require-symbol cue (format "Cue for action %S" id)))
      ('pause
       (unless (and (numberp duration) (>= duration 0))
         (emacsvox-aural--rule-error
          "Pause action %S requires nonnegative :duration" id))))
    (when (and volume (not (numberp volume)))
      (emacsvox-aural--rule-error
       "Action volume must be numeric for %S" id))
    (when (and space (not (emacsvox-aural--plist-p space)))
      (emacsvox-aural--rule-error
       "Action space must be a plist for %S" id))
    (emacsvox-aural--make-action
     :id id
     :kind kind
     :text text
     :cue cue
     :duration duration
     :voice voice
     :volume volume
     :space (copy-tree space)
     :source rule-id)))

(defun emacsvox-aural--compile-actions
    (actions rule-id phase &optional id-namespace)
  "Compile ACTIONS contributed by RULE-ID to PHASE.

ID-NAMESPACE distinguishes generated identifiers for separate operations."
  (unless (listp actions)
    (emacsvox-aural--rule-error
     "%S actions for %S must be a list" phase rule-id))
  (let ((compiled
         (cl-loop
          for action in actions
          for index from 0
          collect
          (emacsvox-aural--compile-action
           action rule-id (or id-namespace phase) index)))
        seen)
    (dolist (action compiled)
      (when (memq (emacsvox-aural-action-id action) seen)
        (emacsvox-aural--rule-error
         "Duplicate action identifier for %S: %S"
         rule-id (emacsvox-aural-action-id action)))
      (push (emacsvox-aural-action-id action) seen))
    compiled))

(defun emacsvox-aural--compile-phase (data rule-id phase)
  "Compile phase DATA contributed by RULE-ID to PHASE."
  (cond
   ((null data)
    (emacsvox-aural--make-phase-operations))
   ((and (listp data) (or (null data) (listp (car data))))
    (emacsvox-aural--make-phase-operations
     :append (emacsvox-aural--compile-actions data rule-id phase)))
   (t
    (emacsvox-aural--require-plist
     data (format "%S operations for %S" phase rule-id))
    (let* ((allowed '(:suppress :replace :remove :prepend :append))
           (unknown
            (cl-loop
             for (key _) on data by #'cddr
             unless (memq key allowed)
             collect key))
           (suppress (plist-get data :suppress))
           (replace-set-p (plist-member data :replace))
           (remove (plist-get data :remove))
           (prepend (plist-get data :prepend))
           (append-actions (plist-get data :append)))
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
      (let* ((replace-actions
              (when replace-set-p
                (emacsvox-aural--compile-actions
                 (plist-get data :replace)
                 rule-id phase
                 (intern (format "%s-replace" phase)))))
             (prepend-actions
              (when prepend
                (emacsvox-aural--compile-actions
                 prepend
                 rule-id phase
                 (intern (format "%s-prepend" phase)))))
             (compiled-append
              (when append-actions
                (emacsvox-aural--compile-actions
                 append-actions
                 rule-id phase
                 (intern (format "%s-append" phase)))))
             (all-actions
              (append replace-actions prepend-actions compiled-append))
             seen)
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
         :append compiled-append))))))

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
      (when (and space (not (emacsvox-aural--plist-p space)))
        (emacsvox-aural--rule-error
         "Content space must be a plist for %S" rule-id))
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

(defun emacsvox-aural--compile-contribution (render rule-id)
  "Compile RENDER contribution for RULE-ID."
  (emacsvox-aural--require-plist render (format "Render data for %S" rule-id))
  (let ((unknown
         (cl-loop
          for (key _) on render by #'cddr
          unless (memq key '(:before :content :after))
          collect key)))
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown render phases for %S: %S" rule-id unknown))
    (emacsvox-aural--make-contribution
     :before
     (emacsvox-aural--compile-phase
      (plist-get render :before) rule-id 'before)
     :content
     (emacsvox-aural--compile-content
      (plist-get render :content) rule-id)
     :after
     (emacsvox-aural--compile-phase
      (plist-get render :after) rule-id 'after))))

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
         (order (if (plist-member data :order)
                    (plist-get data :order)
                  (or index 0)))
         (match (or (plist-get data :match) nil))
         (render (plist-get data :render))
         (allowed '(:id :order :match :render))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless (memq key allowed)
           collect key)))
    (emacsvox-aural--require-symbol id "Rule identifier")
    (unless (integerp order)
      (emacsvox-aural--rule-error "Rule order must be an integer for %S" id))
    (unless (plist-member data :render)
      (emacsvox-aural--rule-error "Rule %S has no :render contribution" id))
    (when unknown
      (emacsvox-aural--rule-error "Unknown keys for rule %S: %S" id unknown))
    (emacsvox-aural--make-rule
     :id id
     :origin origin
     :layer-order (or layer-order 0)
     :order order
     :selector (emacsvox-aural--compile-selector match id)
     :contribution (emacsvox-aural--compile-contribution render id)
     :source source)))

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
      (emacsvox-aural--require-symbol voice-palette "Scheme voice palette"))
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
  (emacsvox-aural--require-plist facts "Semantic facts")
  (emacsvox-aural--require-plist (or context nil) "Presentation context")
  (let ((unknown
         (cl-loop
          for (key _) on context by #'cddr
          unless (memq key emacsvox-aural--context-keys)
          collect key)))
    (when unknown
      (emacsvox-aural--rule-error
       "Unknown presentation context keys: %S" unknown)))
  (let* ((role (plist-get facts :role))
         (events
          (emacsvox-aural--normalize-symbols
           (plist-get facts :event)
           (plist-get facts :events)
           "Fact events"))
         (states
          (emacsvox-aural--normalize-symbols
           (plist-get facts :state)
           (plist-get facts :states)
           "Fact states"))
         (attributes
          (emacsvox-aural--extract-attributes
           facts emacsvox-aural--fact-keys "Semantic facts"))
         (module (plist-get context :module))
         (mode (plist-get context :mode))
         (occasion (plist-get context :occasion))
         (legacy-cue (plist-get context :legacy-cue))
         (legacy-personality (plist-get context :legacy-personality))
         (legacy-source (plist-get context :legacy-source))
         (source-buffer (plist-get context :source-buffer))
         (source-buffer-name (plist-get context :source-buffer-name))
         (lineage
          (or
           (plist-get context :mode-lineage)
           (and mode (emacsvox-aural-mode-lineage mode)))))
    (when role
      (emacsvox-aural--require-kind role 'role "Fact role"))
    (dolist (event events)
      (emacsvox-aural--require-kind event 'event "Fact event"))
    (dolist (state states)
      (emacsvox-aural--require-kind state 'state "Fact state"))
    (when module
      (emacsvox-aural--require-symbol module "Context module"))
    (when mode
      (emacsvox-aural--require-symbol mode "Context mode"))
    (when occasion
      (unless (emacsvox-aural-occasion occasion)
        (emacsvox-aural--rule-error
         "Context occasion is not registered: %S" occasion)))
    (when legacy-cue
      (emacsvox-aural--require-symbol legacy-cue "Context legacy cue"))
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
     :legacy-cue legacy-cue
     :legacy-personality legacy-personality
     :legacy-source legacy-source
     :source-buffer source-buffer
     :source-buffer-name source-buffer-name)))

(defun emacsvox-aural--mode-distance (selector input)
  "Return mode ancestry distance for SELECTOR and INPUT, or nil."
  (when-let* ((selected (emacsvox-aural-selector-mode selector)))
    (cl-position selected (emacsvox-aural-input-mode-lineage input) :test #'eq)))

(defun emacsvox-aural-rule-matches-p (rule input)
  "Return non-nil when compiled RULE matches normalized INPUT."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (role (emacsvox-aural-selector-role selector))
         (events (emacsvox-aural-selector-events selector))
         (states (emacsvox-aural-selector-states selector))
         (attributes (emacsvox-aural-selector-attributes selector))
         (module (emacsvox-aural-selector-module selector))
         (mode (emacsvox-aural-selector-mode selector))
         (occasion (emacsvox-aural-selector-occasion selector))
         (legacy-cue (emacsvox-aural-selector-legacy-cue selector))
         (legacy-personality
          (emacsvox-aural-selector-legacy-personality selector)))
    (and
     (or (null role) (eq role (emacsvox-aural-input-role input)))
     (cl-every
      (lambda (event) (memq event (emacsvox-aural-input-events input)))
      events)
     (cl-every
      (lambda (state) (memq state (emacsvox-aural-input-states input)))
      states)
     (cl-every
      (lambda (attribute)
        (equal
         (alist-get
          (car attribute) (emacsvox-aural-input-attributes input)
          :emacsvox-aural-missing)
         (cdr attribute)))
      attributes)
     (or (null module) (eq module (emacsvox-aural-input-module input)))
     (or (null mode) (numberp (emacsvox-aural--mode-distance selector input)))
     (or
      (null occasion)
      (eq occasion (emacsvox-aural-input-occasion input)))
     (or
      (null legacy-cue)
      (eq legacy-cue (emacsvox-aural-input-legacy-cue input)))
     (or
      (null legacy-personality)
      (equal
       legacy-personality
       (emacsvox-aural-input-legacy-personality input))))))

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
         (module (emacsvox-aural-selector-module selector))
         (mode (emacsvox-aural-selector-mode selector))
         (distance (and mode (emacsvox-aural--mode-distance selector input)))
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
             (if (emacsvox-aural-selector-legacy-cue selector) 1 0)
             (if
                 (emacsvox-aural-selector-legacy-personality selector)
                 1
               0))))
    (vector
     origin
     identity
     combined-exact
     mode-rank
     mode-closeness
     (if module 1 0)
     constraints
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

(defun emacsvox-aural--remove-actions (actions ids)
  "Return ACTIONS without actions whose identifiers occur in IDS."
  (cl-remove-if
   (lambda (action) (memq (emacsvox-aural-action-id action) ids))
   actions))

(defun emacsvox-aural--apply-phase (actions operations)
  "Apply phase OPERATIONS to current ACTIONS."
  (cond
   ((emacsvox-aural-phase-operations-suppress operations) nil)
   (t
    (let ((result
           (if (emacsvox-aural-phase-operations-replace-set-p operations)
               (copy-sequence
                (emacsvox-aural-phase-operations-replace operations))
             (copy-sequence actions))))
      (setq
       result
       (emacsvox-aural--remove-actions
        result (emacsvox-aural-phase-operations-remove operations)))
      (append
       (copy-sequence
        (emacsvox-aural-phase-operations-prepend operations))
       result
       (copy-sequence
        (emacsvox-aural-phase-operations-append operations)))))))

(defun emacsvox-aural--set-content-provenance (content property rule-id)
  "Record that RULE-ID selected PROPERTY on CONTENT."
  (setf
   (emacsvox-aural-content-style-provenance content)
   (cons
    (cons property rule-id)
    (assq-delete-all
     property (emacsvox-aural-content-style-provenance content)))))

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
    (setf
     (emacsvox-aural-content-style-voice content)
     (emacsvox-aural-content-patch-voice patch))
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

(defun emacsvox-aural-resolve (facts context rules)
  "Resolve semantic FACTS and CONTEXT through compiled RULES."
  (let* ((input (emacsvox-aural-normalize-input facts context))
         (matches (emacsvox-aural-matching-rules rules input))
         (plan
          (emacsvox-aural--make-render-plan
           :before nil
           :content (emacsvox-aural--make-content-style :speak t)
           :after nil
           :matched-rules nil
           :rule-scores nil)))
    (dolist (rule matches)
      (let ((contribution (emacsvox-aural-rule-contribution rule))
            (rule-id (emacsvox-aural-rule-id rule)))
        (setf
         (emacsvox-aural-render-plan-before plan)
         (emacsvox-aural--apply-phase
          (emacsvox-aural-render-plan-before plan)
          (emacsvox-aural-contribution-before contribution)))
        (emacsvox-aural--apply-content
         (emacsvox-aural-render-plan-content plan)
         (emacsvox-aural-contribution-content contribution)
         rule-id)
        (setf
         (emacsvox-aural-render-plan-after plan)
         (emacsvox-aural--apply-phase
          (emacsvox-aural-render-plan-after plan)
          (emacsvox-aural-contribution-after contribution)))
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
           (cons rule-id (emacsvox-aural-rule-score rule input)))))))
    plan))

(provide 'emacsvox-aural-rules)
;;; emacsvox-aural-rules.el ends here
