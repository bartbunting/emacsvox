;;; emacsvox-aural-submission.el --- Aural presentation transactions -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Combine semantic content and explicitly ordered compatibility actions at
;; one frozen source boundary.  Legacy entry points remain independent
;; adapters until their callers migrate to this service.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-planner)
(require 'emacsvox-aural-source)

(declare-function tts-speak "tts-speak" (text))

(define-error
  'emacsvox-aural-submission-error
  "Cannot submit an Emacsvox aural presentation transaction")

(cl-defstruct
    (emacsvox-aural-compatibility-action
     (:constructor emacsvox-aural--make-compatibility-action))
  "One ordered compatibility action within a native submission."
  phase kind value)

(cl-defstruct
    (emacsvox-aural-submission
     (:constructor emacsvox-aural--make-submission))
  "One frozen native aural presentation transaction."
  id facts context content compatibility-actions prepared-content plans)

(defvar emacsvox-aural--submission-sequence 0
  "Sequence used to identify native aural submissions.")

(defun emacsvox-aural--submission-error (format-string &rest arguments)
  "Signal a submission error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-submission-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural-compatibility-icon (icon &optional phase)
  "Return a compatibility action presenting legacy ICON during PHASE.

PHASE is `before' by default and may alternatively be `after'."
  (unless (symbolp icon)
    (emacsvox-aural--submission-error
     "Compatibility icon must be a symbol: %S" icon))
  (let ((phase (or phase 'before)))
    (unless (memq phase '(before after))
      (emacsvox-aural--submission-error
       "Compatibility action phase must be before or after: %S" phase))
    (emacsvox-aural--make-compatibility-action
     :phase phase :kind 'legacy-icon :value icon)))

(defun emacsvox-aural--normalized-compatibility-actions (actions)
  "Return validated private copies of compatibility ACTIONS."
  (mapcar
   (lambda (action)
     (unless (emacsvox-aural-compatibility-action-p action)
       (emacsvox-aural--submission-error
        "Invalid compatibility action: %S" action))
     (unless
         (memq
          (emacsvox-aural-compatibility-action-phase action)
          '(before after))
       (emacsvox-aural--submission-error
        "Compatibility action phase must be before or after: %S"
        (emacsvox-aural-compatibility-action-phase action)))
     (unless
         (eq
          (emacsvox-aural-compatibility-action-kind action)
          'legacy-icon)
       (emacsvox-aural--submission-error
        "Unsupported compatibility action kind: %S"
        (emacsvox-aural-compatibility-action-kind action)))
     (unless
         (symbolp
          (emacsvox-aural-compatibility-action-value action))
       (emacsvox-aural--submission-error
        "Compatibility icon must be a symbol: %S"
        (emacsvox-aural-compatibility-action-value action)))
     (copy-emacsvox-aural-compatibility-action action))
   actions))

(defun emacsvox-aural--submission-facts-with-compatibility
    (facts actions)
  "Return FACTS enriched by known semantics from compatibility ACTIONS."
  (let* ((facts (copy-tree facts))
         (events
          (append
           (when-let* ((event (plist-get facts :event))) (list event))
           (copy-sequence (plist-get facts :events)))))
    (dolist (action actions)
      (when-let* ((semantic
                   (plist-get
                    (emacsvox-aural-legacy-icon-input
                     (emacsvox-aural-compatibility-action-value action))
                    :semantic)))
        (setq events (append events (list semantic)))))
    (if events
        (plist-put facts :events (delete-dups events))
      facts)))

(defun emacsvox-aural--source-compatibility-actions (actions)
  "Return data-only source records for compatibility ACTIONS."
  (mapcar
   (lambda (action)
     (list
      :phase (emacsvox-aural-compatibility-action-phase action)
      :kind (emacsvox-aural-compatibility-action-kind action)
      :value (emacsvox-aural-compatibility-action-value action)))
   actions))

(defun emacsvox-aural--submission-plans-in (prepared)
  "Return consecutive concrete plans carried by PREPARED text."
  (let ((position 0)
        plans)
    (while (< position (length prepared))
      (let ((plan (emacsvox-aural-concrete-plan-at position prepared)))
        (unless plan
          (emacsvox-aural--submission-error
           "Prepared submission has no concrete plan at %d" position))
        (push plan plans))
      (setq
       position
       (next-single-property-change
        position emacsvox-aural-concrete-plan-property
        prepared (length prepared))))
    (nreverse plans)))

(defun emacsvox-aural--submit-content
    (content compatibility-actions)
  "Submit CONTENT with normalized COMPATIBILITY-ACTIONS."
  (unless (and (stringp content) (> (length content) 0))
    (emacsvox-aural--submission-error
     "Native aural submission content must be a nonempty string: %S"
     content))
  (let* ((id (cl-incf emacsvox-aural--submission-sequence))
         (actions
          (emacsvox-aural--normalized-compatibility-actions
           compatibility-actions))
         (facts
          (emacsvox-aural--submission-facts-with-compatibility
           emacsvox-aural-submission-facts actions))
         (context (copy-tree emacsvox-aural-submission-context))
         (source (copy-sequence content))
         (object-id (list 'submission id)))
    (add-text-properties
     0 (length source)
     (list emacsvox-aural-object-property object-id)
     source)
    (let* ((prepared
            (emacsvox-aural-prepare-text
             source facts context
             (emacsvox-aural--source-compatibility-actions actions)))
           (plans (emacsvox-aural--submission-plans-in prepared))
           (submission
            (emacsvox-aural--make-submission
             :id id
             :facts (copy-tree facts)
             :context (copy-tree context)
             :content (copy-sequence content)
             :compatibility-actions
             (mapcar #'copy-emacsvox-aural-compatibility-action actions)
             :prepared-content prepared
             :plans plans)))
      (dolist (plan plans)
        (setf
         (emacsvox-aural-concrete-plan-context plan)
         (plist-put
          (emacsvox-aural-concrete-plan-context plan)
          :presentation-transaction-id id)))
      (emacsvox-aural-call-with-presentation-transaction
       id #'tts-speak prepared)
      submission)))

(cl-defun emacsvox-aural-submit
    (content &key facts context module occasion compatibility-actions)
  "Present CONTENT as one native aural transaction.

FACTS and frozen CONTEXT describe one user-visible object.  MODULE and
OCCASION are used when CONTEXT must be captured.  COMPATIBILITY-ACTIONS is an
ordered list produced by `emacsvox-aural-compatibility-icon'.  Before actions
precede semantic before-actions; after actions follow semantic after-actions.
Semantic rules are resolved once for the object, while legacy icons resolve
only their cue-specific adapter policy."
  (emacsvox-aural-call-with-submission
   #'emacsvox-aural--submit-content
   :facts facts
   :context context
   :module (or module (plist-get context :module))
   :occasion
   (or occasion (plist-get context :occasion) 'continuous)
   :arguments (list content compatibility-actions)))

(provide 'emacsvox-aural-submission)
;;; emacsvox-aural-submission.el ends here
