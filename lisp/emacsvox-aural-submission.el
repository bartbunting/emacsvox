;;; emacsvox-aural-submission.el --- Aural presentation transactions -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Combine semantic content and explicitly ordered compatibility actions at
;; one frozen source boundary.  Legacy entry points remain independent
;; adapters until their callers migrate to this service.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-planner)
(require 'emacsvox-aural-source)

(declare-function tts-speak "tts-speak" (text))
(autoload 'emacsvox-aural-present "emacsvox-aural-transport")

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
  id delivery-policy replacement-key facts context content
  compatibility-actions prepared-content plans)

(defvar emacsvox-aural--submission-sequence 0
  "Sequence used to identify native aural submissions.")

(defcustom emacsvox-aural-diagnostic-log-file nil
  "File receiving opt-in aural submission diagnostics.

When non-nil, Emacsvox appends one Lisp plist per line with command timing,
submission timing, and complete submitted text.  The log can therefore contain
sensitive material and is disabled by default.  Emacsvox creates the file with
owner-only permissions and tightens an existing file before appending to it."
  :type '(choice (const :tag "Disabled" nil) file)
  :group 'emacsvox-aural)

(defcustom emacsvox-aural-diagnostic-log-max-bytes (* 16 1024 1024)
  "Soft size limit for one aural diagnostic log file.

Before appending a record that would cross this limit, Emacsvox renames the
current log to a session-tagged archive.  A single oversized record remains
intact and may exceed the limit.  Set this to nil to disable rotation."
  :type '(choice (const :tag "Do not rotate" nil) integer)
  :group 'emacsvox-aural)

(defcustom emacsvox-aural-diagnostic-log-retained-files 4
  "Number of rotated aural diagnostic log files to retain.

The active log is additional to this number."
  :type 'integer
  :group 'emacsvox-aural)

(defvar emacsvox-aural--diagnostic-session-id
  (format
   "%s-%d"
   (format-time-string "%Y%m%dT%H%M%SZ" nil t)
   (emacs-pid))
  "Stable identifier for this Emacs diagnostic logging session.")

(defvar emacsvox-aural--diagnostic-rotation-sequence 0
  "Sequence making diagnostic archive names unique within this Emacs.")

(defvar-local emacsvox-aural-command-start-time nil
  "Floating-point time when a diagnosed interactive command started.")

(defvar emacsvox-aural-last-diagnostic-log-error nil
  "Most recent error encountered while writing aural diagnostics.")

(defun emacsvox-aural--diagnostic-elapsed-ms (start &optional end)
  "Return milliseconds elapsed from numeric START through END."
  (when (numberp start)
    (* 1000.0 (- (or end (float-time)) start))))

(defun emacsvox-aural--secure-diagnostic-log-file (file)
  "Ensure diagnostic log FILE exists and is readable only by its owner."
  (unless (file-exists-p file)
    (let ((previous-modes (default-file-modes)))
      (unwind-protect
          (progn
            (set-default-file-modes #o600)
            (write-region "" nil file 'append 'silent))
        (set-default-file-modes previous-modes))))
  (set-file-modes file #o600))

(defun emacsvox-aural--diagnostic-archive-files (file)
  "Return session-tagged archives belonging to diagnostic log FILE."
  (let* ((directory (file-name-directory file))
         (prefix
          (concat (file-name-nondirectory file) ".archive-")))
    (directory-files
     directory t
     (concat "\\`" (regexp-quote prefix) ".+\\'")
     t)))

(defun emacsvox-aural--prune-diagnostic-archives (file)
  "Remove excess session-tagged archives belonging to FILE."
  (let* ((retained
          (if (and
               (integerp emacsvox-aural-diagnostic-log-retained-files)
               (> emacsvox-aural-diagnostic-log-retained-files 0))
              emacsvox-aural-diagnostic-log-retained-files
            0))
         (archives
          (sort
           (emacsvox-aural--diagnostic-archive-files file)
           (lambda (first second)
             (time-less-p
              (file-attribute-modification-time (file-attributes second))
              (file-attribute-modification-time
               (file-attributes first)))))))
    (dolist (archive (nthcdr retained archives))
      (condition-case nil
          (delete-file archive)
        (file-missing nil)))))

(defun emacsvox-aural--rotate-diagnostic-log-if-needed
    (file incoming-bytes)
  "Rotate FILE before appending INCOMING-BYTES when it would cross its limit.

Return non-nil when this call rotated the active file."
  (when
      (and
       (integerp emacsvox-aural-diagnostic-log-max-bytes)
       (> emacsvox-aural-diagnostic-log-max-bytes 0)
       (file-exists-p file)
       (when-let* ((attributes (file-attributes file)))
         (let ((size (file-attribute-size attributes)))
           (and
            (> size 0)
            (> (+ size incoming-bytes)
               emacsvox-aural-diagnostic-log-max-bytes)))))
    (let ((archive
           (format
            "%s.archive-%s-%06d"
            file emacsvox-aural--diagnostic-session-id
            (cl-incf emacsvox-aural--diagnostic-rotation-sequence))))
      (condition-case nil
          (progn
            (rename-file file archive nil)
            (set-file-modes archive #o600)
            t)
        ;; Another Emacs may have rotated the shared path after our size check.
        (file-missing nil)))))

(defun emacsvox-aural-diagnostic-log-event (event &rest fields)
  "Append opt-in diagnostic EVENT and FIELDS to the configured log.

Logging never prevents presentation; a write failure is retained in
`emacsvox-aural-last-diagnostic-log-error'."
  (when emacsvox-aural-diagnostic-log-file
    (condition-case error-data
        (let* ((now (current-time))
               (file (expand-file-name emacsvox-aural-diagnostic-log-file))
               (directory (file-name-directory file))
               (record
                (append
                 (list
                  :time (float-time now)
                  :utc (format-time-string
                        "%Y-%m-%dT%H:%M:%S.%3NZ" now t)
                  :session-id emacsvox-aural--diagnostic-session-id
                  :emacs-pid (emacs-pid)
                  :event event)
                 fields))
               (coding-system-for-write 'utf-8-unix))
          (when directory (make-directory directory t))
          (emacsvox-aural--secure-diagnostic-log-file file)
          (with-temp-buffer
            (let ((print-circle t)
                  (print-length nil)
                  (print-level nil))
              (prin1 record (current-buffer)))
            (insert "\n")
            (let* ((encoded
                    (encode-coding-string
                     (buffer-string) coding-system-for-write t))
                   (rotated
                    (emacsvox-aural--rotate-diagnostic-log-if-needed
                     file (string-bytes encoded))))
              (when rotated
                (emacsvox-aural--secure-diagnostic-log-file file))
              (write-region
               (point-min) (point-max) file 'append 'silent)
              (when rotated
                (emacsvox-aural--prune-diagnostic-archives file))))
          (emacsvox-aural--secure-diagnostic-log-file file)
          (setq emacsvox-aural-last-diagnostic-log-error nil)
          record)
      (error
       (setq emacsvox-aural-last-diagnostic-log-error error-data)
       nil))))

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
  (setq content (emacsvox-aural-transform-source-text content))
  (when (string-empty-p content)
    (emacsvox-aural--submission-error
     "Aural source transformation returned empty content"))
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
    ;; Preserve an explicit object model supplied by a native caller.  In its
    ;; absence, keep the established whole-submission object boundary.
    (unless
        (text-property-not-all
         0 (length source) emacsvox-aural-object-property nil source)
      (add-text-properties
       0 (length source)
       (list emacsvox-aural-object-property object-id)
       source))
    (let* ((prepared
            (emacsvox-aural-prepare-text
             source facts context
             (emacsvox-aural--source-compatibility-actions actions)))
           (plans (emacsvox-aural--submission-plans-in prepared))
           (submission
            (emacsvox-aural--make-submission
             :id id
             :delivery-policy emacsvox-aural-submission-delivery-policy
             :replacement-key emacsvox-aural-submission-replacement-key
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
      (let* ((presented-plans nil)
             (emacsvox-aural--presented-plan-collector
              (lambda (presented-plan)
                (push presented-plan presented-plans))))
        (emacsvox-aural-call-with-presentation-transaction
         id #'tts-speak prepared)
        (when presented-plans
          (setf
           (emacsvox-aural-submission-plans submission)
           (nreverse presented-plans))))
      submission)))

(defun emacsvox-aural--submit-actions (compatibility-actions)
  "Submit frozen semantic facts and COMPATIBILITY-ACTIONS without content."
  (let* ((id (cl-incf emacsvox-aural--submission-sequence))
         (actions
          (emacsvox-aural--normalized-compatibility-actions
           compatibility-actions))
         (facts
          (emacsvox-aural--submission-facts-with-compatibility
           emacsvox-aural-submission-facts actions))
         (context (copy-tree emacsvox-aural-submission-context))
         (plan-context
          (plist-put
           (copy-tree context)
           :presentation-transaction-id id))
         (presented-plans nil)
         (emacsvox-aural--presented-plan-collector
          (lambda (presented-plan)
            (push presented-plan presented-plans)))
         (plan
          (emacsvox-aural-call-with-presentation-transaction
           id #'emacsvox-aural-present facts plan-context
           (emacsvox-aural--source-compatibility-actions actions))))
    (emacsvox-aural--make-submission
     :id id
     :delivery-policy emacsvox-aural-submission-delivery-policy
     :replacement-key emacsvox-aural-submission-replacement-key
     :facts facts
     :context context
     :content nil
     :compatibility-actions
     (mapcar #'copy-emacsvox-aural-compatibility-action actions)
     :prepared-content nil
     :plans (or (nreverse presented-plans) (list plan)))))

(cl-defun emacsvox-aural-submit-actions
    (&key
     facts context module occasion delivery-policy replacement-key
     compatibility-actions)
  "Present semantic FACTS as one action-only native transaction.

FACTS describe one user-visible event or object but supply no spoken object
content.  Matching rules may still produce ordered speech, cue, pause, or tone
actions.  Frozen CONTEXT controls policy; MODULE and OCCASION are used when it
must be captured.  DELIVERY-POLICY and REPLACEMENT-KEY control whole-transaction
delivery.  COMPATIBILITY-ACTIONS is an ordered list produced by
`emacsvox-aural-compatibility-icon'.  Before actions precede semantic
before-actions; after actions follow semantic after-actions.  A resolution
with no enabled output does not start the speech server, dispatch, or create a
presentation-history record."
  (when (plist-member facts :content)
    (emacsvox-aural--submission-error
     "Action-only aural facts cannot contain spoken content: %S"
     (plist-get facts :content)))
  (let ((emacsvox-aural-submission-controls-interruption t))
    (emacsvox-aural-call-with-submission
     #'emacsvox-aural--submit-actions
     :facts facts
     :context context
     :module (or module (plist-get context :module))
     :occasion
     (or occasion (plist-get context :occasion) 'notification)
     :delivery-policy delivery-policy
     :replacement-key replacement-key
     :arguments (list compatibility-actions))))

(cl-defun emacsvox-aural-submit
    (content
     &key facts context module occasion delivery-policy replacement-key
     compatibility-actions)
  "Present CONTENT as one native aural transaction.

FACTS and frozen CONTEXT describe one user-visible object.  MODULE and
OCCASION are used when CONTEXT must be captured.  DELIVERY-POLICY and
REPLACEMENT-KEY control whole-transaction delivery.  COMPATIBILITY-ACTIONS is an
ordered list produced by `emacsvox-aural-compatibility-icon'.  Before actions
precede semantic before-actions; after actions follow semantic after-actions.
Semantic rules are resolved once for the object, while legacy icons resolve
only their cue-specific adapter policy."
  (let* ((command-start emacsvox-aural-command-start-time)
         (submit-observed-at (float-time))
         (plain-content
          (and (stringp content) (substring-no-properties content)))
         submission
         completed)
    (emacsvox-aural-diagnostic-log-event
     'submission-start
     :command this-command
     :buffer (buffer-name)
     :mode major-mode
     :point (point)
     :command-elapsed-ms
     (emacsvox-aural--diagnostic-elapsed-ms
      command-start submit-observed-at)
     :content-characters (and plain-content (length plain-content))
     :content plain-content)
    (let ((work-start (float-time)))
      (unwind-protect
          (progn
            (setq
             submission
             (let ((emacsvox-aural-submission-controls-interruption t))
               (emacsvox-aural-call-with-submission
                #'emacsvox-aural--submit-content
                :facts facts
                :context context
                :module (or module (plist-get context :module))
                :occasion
                (or occasion (plist-get context :occasion) 'continuous)
                :delivery-policy delivery-policy
                :replacement-key replacement-key
                :arguments (list content compatibility-actions))))
            (setq completed t))
        (let ((finished-at (float-time)))
          (emacsvox-aural-diagnostic-log-event
           'submission-complete
           :command this-command
           :buffer (buffer-name)
           :mode major-mode
           :status (if completed 'completed 'failed)
           :submission-id
           (and submission (emacsvox-aural-submission-id submission))
           :command-elapsed-ms
           (emacsvox-aural--diagnostic-elapsed-ms
            command-start finished-at)
           :submission-elapsed-ms
           (emacsvox-aural--diagnostic-elapsed-ms work-start finished-at))))
      submission)))

(provide 'emacsvox-aural-submission)
;;; emacsvox-aural-submission.el ends here
