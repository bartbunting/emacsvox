;;; emacsvox-aural-inspection.el --- Context for aural inspection -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Source-buffer ownership and at-point context capture shared by aural
;; managers, editors, explanations, and previews.  Each interface keeps its
;; own ordinary source buffer; the most recent source remains only as a
;; fallback for interfaces opened without an explicit association.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-transport)

(defvar emacsvox-aural-inspection-last-source-buffer nil
  "Most recent ordinary buffer used as an aural inspection source.")

(defun emacsvox-aural-inspection-last-source-buffer ()
  "Return the most recent live ordinary inspection source.

Clear the compatibility fallback when its buffer has died."
  (unless
      (and
       (buffer-live-p emacsvox-aural-inspection-last-source-buffer)
       (not
        (emacsvox-aural-ui-interface-buffer-p
         emacsvox-aural-inspection-last-source-buffer)))
    (setq emacsvox-aural-inspection-last-source-buffer nil))
  emacsvox-aural-inspection-last-source-buffer)

(defun emacsvox-aural-inspection--resolve-source (buffer seen)
  "Resolve ordinary source BUFFER, avoiding interface cycles in SEEN."
  (when
      (and
       (buffer-live-p buffer)
       (not (minibufferp buffer))
       (not (memq buffer seen)))
    (if (emacsvox-aural-ui-interface-buffer-p buffer)
        (if
            (local-variable-p 'emacsvox-aural-ui-source-buffer buffer)
            (emacsvox-aural-inspection--resolve-source
             (buffer-local-value
              'emacsvox-aural-ui-source-buffer buffer)
             (cons buffer seen))
          (emacsvox-aural-inspection-last-source-buffer))
      buffer)))

(defun emacsvox-aural-inspection-source-buffer (&optional buffer)
  "Return the ordinary inspection source associated with BUFFER.

BUFFER defaults to the current buffer.  An ordinary buffer is its own source.
An aural interface uses its explicitly attached source.  When an interface
has never had a source attached, use the most recent live source as a
compatibility fallback.  An explicitly attached source that has died resolves
to nil rather than an unrelated newer fallback."
  (emacsvox-aural-inspection--resolve-source
   (or buffer (current-buffer)) nil))

(defun emacsvox-aural-inspection-remember-source-buffer (&optional buffer)
  "Remember and return the ordinary source associated with BUFFER.

BUFFER defaults to the current buffer.  Interface buffers contribute their
attached ordinary source rather than becoming sources themselves."
  (let ((source
         (emacsvox-aural-inspection-source-buffer
          (or buffer (current-buffer)))))
    (when source
      (setq emacsvox-aural-inspection-last-source-buffer source))
    source))

(defun emacsvox-aural-inspection-attach-source (source)
  "Attach ordinary inspection SOURCE to the current aural interface.

SOURCE may be nil.  Attaching nil is deliberate and prevents this interface
from later adopting an unrelated global fallback."
  (unless (emacsvox-aural-ui-interface-buffer-p)
    (user-error "This is not an aural interface buffer"))
  (let ((source
         (and
          source
          (emacsvox-aural-inspection--resolve-source source nil))))
    (setq-local emacsvox-aural-ui-source-buffer source)
    source))

(defun emacsvox-aural-inspection-point-position ()
  "Return a position at or immediately before point that can hold properties."
  (cond
   ((= (point-min) (point-max)) nil)
   ((= (point) (point-max)) (1- (point)))
   (t (point))))

(defun emacsvox-aural-inspection-plan-at-point ()
  "Return the frozen concrete aural plan at point, or nil."
  (when-let* ((position (emacsvox-aural-inspection-point-position)))
    (get-text-property
     position emacsvox-aural-concrete-plan-property)))

(defun emacsvox-aural-facts-at-point ()
  "Return semantic facts attached to the object at point, or nil."
  (when-let* ((position (emacsvox-aural-inspection-point-position)))
    (or
     (get-text-property
      position emacsvox-aural-facts-property)
     (when-let* ((plan (emacsvox-aural-inspection-plan-at-point)))
       (copy-tree (emacsvox-aural-concrete-plan-facts plan))))))

(defun emacsvox-aural-context-at-point ()
  "Return frozen presentation context at point or capture current context."
  (or
   (when-let* ((plan (emacsvox-aural-inspection-plan-at-point)))
     (copy-tree (emacsvox-aural-concrete-plan-context plan)))
   (let ((context (emacsvox-aural-capture-context))
         (position (emacsvox-aural-inspection-point-position)))
     (when position
       (let* ((provenance
               (emacsvox-aural-capture-source-faces position))
              (faces
               (mapcar
                (lambda (entry) (plist-get entry :face))
                provenance)))
         (when faces
           (setq
            context
            (plist-put context :legacy-faces (copy-sequence faces)))
           (setq
            context
            (plist-put
             context :legacy-face-source
             (emacsvox-aural--source-face-summary provenance)))
           (setq
            context
            (plist-put
             context :legacy-face-provenance
             (copy-tree provenance))))))
     context)))

(defun emacsvox-aural-inspection-context-for-occasion (context occasion)
  "Return a copy of CONTEXT whose presentation OCCASION is frozen."
  (plist-put (copy-tree context) :occasion occasion))

(defun emacsvox-aural-inspection-representative-input (rule)
  "Return representative facts and context that match RULE."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (facts nil)
         (context
          (emacsvox-aural-capture-context
           (emacsvox-aural-selector-module selector)
           (or
            (emacsvox-aural-selector-occasion selector)
            'inspection))))
    (when-let* ((role (emacsvox-aural-selector-role selector)))
      (setq facts (plist-put facts :role role)))
    (when-let* ((events (emacsvox-aural-selector-events selector)))
      (setq facts (plist-put facts :events (copy-sequence events))))
    (when-let* ((states (emacsvox-aural-selector-states selector)))
      (setq facts (plist-put facts :states (copy-sequence states))))
    (dolist
        (attribute (emacsvox-aural-selector-attributes selector))
      (setq
       facts
       (plist-put
        facts
        (intern (format ":%s" (car attribute)))
        (cdr attribute))))
    (dolist
        (attribute
         (emacsvox-aural-selector-required-attributes selector))
      (unless
          (assq attribute (emacsvox-aural-selector-attributes selector))
        (let* ((record (emacsvox-aural-semantic attribute))
               (value
                (or
                 (car (emacsvox-aural-semantic-allowed-values record))
                 (pcase (emacsvox-aural-semantic-value-type record)
                   ('positive-integer 1)
                   ('integer 0)
                   ('number 0)
                   ('string "example")
                   ('symbol 'example)
                   ('boolean t)
                   (_ 'example)))))
          (setq
           facts
           (plist-put
            facts
            (intern (format ":%s" attribute))
            value)))))
    (when-let* ((mode (emacsvox-aural-selector-mode selector)))
      (setq context (plist-put context :mode mode))
      (setq
       context
       (plist-put context :mode-lineage
                  (emacsvox-aural-mode-lineage mode))))
    (when-let* ((face (emacsvox-aural-selector-legacy-face selector)))
      (setq context (plist-put context :legacy-faces (list face)))
      (setq context (plist-put context :legacy-face-source 'preview)))
    (list facts context)))

(provide 'emacsvox-aural-inspection)

;;; emacsvox-aural-inspection.el ends here
