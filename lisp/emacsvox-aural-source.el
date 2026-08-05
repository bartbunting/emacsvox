;;; emacsvox-aural-source.el --- Aural source boundary -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

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

(defconst emacsvox-aural-delivery-policies
  '(ordered replaceable urgent)
  "Supported delivery policies for complete aural submissions.")

(defvar emacsvox-aural-submission-delivery-policy nil
  "Dynamically bound delivery policy for the current aural submission.")

(defvar emacsvox-aural-submission-replacement-key nil
  "Dynamically bound replacement key for the current aural submission.")

(defvar emacsvox-aural-submission-controls-interruption nil
  "Non-nil when the native delivery policy owns speech interruption.

`emacsvox-aural-submit' and `emacsvox-aural-submit-actions' bind this while
their complete transactions are delivered.  Compatibility callers and bare
`tts-speak' calls leave it nil and retain legacy stop-before-speaking
behaviour.")

(defvar emacsvox-aural-ui-interface-buffer)

(defconst emacsvox-aural-facts-property
  'emacsvox-aural-facts
  "Text property holding semantic facts for one formatted text run.")

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

(defun emacsvox-aural--validate-delivery (policy replacement-key)
  "Validate delivery POLICY and REPLACEMENT-KEY."
  (unless (memq policy emacsvox-aural-delivery-policies)
    (error "Unsupported aural delivery policy: %S" policy))
  (when (and (eq policy 'replaceable) (null replacement-key))
    (error "Replaceable aural delivery requires a replacement key")))

(cl-defun emacsvox-aural-call-with-submission
    (function
     &key facts context module occasion delivery-policy replacement-key
     arguments)
  "Call FUNCTION with ARGUMENTS inside one frozen aural submission.

FACTS, CONTEXT, MODULE, and OCCASION describe the source presentation.
DELIVERY-POLICY is `ordered', `replaceable', or `urgent'.  Replaceable
submissions with the same REPLACEMENT-KEY supersede one another before
delivery; the default key is `speaker'.  An enclosing submission remains
authoritative so nested compatibility helpers cannot replace more specific
presentation or delivery intent."
  (let* ((effective-facts
          (or emacsvox-aural-submission-facts facts))
         (effective-module
          (or emacsvox-aural-submission-module module))
         (effective-occasion
          (or emacsvox-aural-submission-occasion occasion 'continuous))
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
         (emacsvox-aural-submission-delivery-policy
          effective-delivery-policy)
         (emacsvox-aural-submission-replacement-key
          effective-replacement-key))
    (emacsvox-aural--validate-delivery
     effective-delivery-policy effective-replacement-key)
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
  "Copy START through END from BUFFER with source-face snapshots.

This is the source-boundary counterpart of `buffer-substring'.  It preserves
ordinary text properties and annotates the returned string with ordered,
data-only overlay and text-property face provenance without changing BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (let ((text (buffer-substring start end))
          (position start))
      (while (< position end)
        (let* ((next (next-char-property-change position end))
               (snapshot
                (emacsvox-aural-capture-source-faces position)))
          (when snapshot
            (add-text-properties
             (- position start) (- next start)
             (list
              emacsvox-aural-source-faces-property
              (copy-tree snapshot))
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
