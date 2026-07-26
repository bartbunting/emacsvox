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
  usage)

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

(defvar emacsvox-aural-semantic-registry
  (make-hash-table :test #'eq)
  "Map semantic identifiers to `emacsvox-aural-semantic' records.")

(defvar emacsvox-aural-occasion-registry
  (make-hash-table :test #'eq)
  "Map occasion identifiers to `emacsvox-aural-occasion' records.")

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
        occasions phases usage)
  "Register semantic ID and return its immutable registry record.

KIND is one of `role', `event', `state', or `attribute'.  SUMMARY and OWNER
document intent and ownership.  VALUE-TYPE and ALLOWED-VALUES constrain
attributes.  FALLBACK names another semantic identifier.  OCCASIONS and PHASES
document supported presentation contexts.  USAGE is optional extended help."
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
  (when (and allowed-values (not (eq kind 'attribute)))
    (emacsvox-aural--registration-error
     "Only attributes may declare allowed values: %S" id))
  (when (and value-type (not (eq kind 'attribute)))
    (emacsvox-aural--registration-error
     "Only attributes may declare a value type: %S" id))
  (when (gethash id emacsvox-aural-semantic-registry)
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
          :usage usage)))
    (puthash id record emacsvox-aural-semantic-registry)
    record))

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
  (gethash id emacsvox-aural-semantic-registry))

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
             (nreverse path)))))))
  t)

(defun emacsvox-aural-validate-registry ()
  "Validate cross-references in the semantic and occasion registries."
  (dolist (record (emacsvox-aural-semantics))
    (dolist (occasion (emacsvox-aural-semantic-occasions record))
      (unless (emacsvox-aural-occasion occasion)
        (emacsvox-aural--registration-error
         "Semantic %S names unknown occasion %S"
         (emacsvox-aural-semantic-id record)
         occasion))))
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
  (emacsvox-aural-validate-registry))

(emacsvox-aural--register-builtins)

(provide 'emacsvox-aural)
;;; emacsvox-aural.el ends here
