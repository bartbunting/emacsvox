;;; emacsvox-aural-history.el --- Frozen aural observability -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Bounded, data-only records of presentations actually submitted to a live
;; transport.  History never retains source buffers and does not resolve rules,
;; resources, voices, or backend transport.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural)
(require 'emacsvox-aural-concrete)

(defvar emacsvox-aural-submission-delivery-policy)

(cl-defstruct
    (emacsvox-aural-presentation-record
     (:constructor emacsvox-aural--make-presentation-record))
  "One bounded, data-only record of a transport-submitted presentation.

PLAN remains the representative first run for compatibility.  PLANS and
PAUSES retain every exact formatting run in a native transaction."
  id queued-at plan source-buffer-name source-position object-id run-id
  plans pauses transaction-id)

(defvar emacsvox-aural-plan-presented-hook nil
  "Abnormal hook run after presenting one concrete aural plan.

Each function receives the `emacsvox-aural-concrete-plan' that was submitted.
Queue transport runs this after writing the transaction; standalone local cues
run it after playback has been requested.")

(defcustom emacsvox-aural-presentation-history-limit 20
  "Maximum number of transport-submitted presentations retained for inspection.

History records contain frozen data and source names and positions, but never
retain source buffers.  Set this to zero to disable history."
  :type 'natnum
  :group 'emacsvox-aural)

(defcustom emacsvox-aural-history-record-interface-presentations nil
  "Whether presentations originating in Aural interfaces enter history.

Leave this nil during normal use so interface navigation, opening, closing,
help, previews, and status speech do not displace source-buffer feedback.
Enable it temporarily when diagnosing presentation inside the Aural UI."
  :type 'boolean
  :group 'emacsvox-aural)

(defvar emacsvox-aural-presentation-history nil
  "Newest-first bounded list of frozen presentation records.")

(defvar emacsvox-aural--presentation-sequence 0
  "Sequence used to identify frozen presentation records.")

(defvar emacsvox-aural--history-respect-icon-policy nil
  "Non-nil while queue history must remove disabled cue actions.")

(defvar emacsvox-aural--history-transaction-id nil
  "Identifier of the dynamically active native history transaction.")

(defvar emacsvox-aural--history-transaction-runs nil
  "Reverse-ordered frozen runs in the active history transaction.")

(defvar emacsvox-aural--delivery-history-registrar nil
  "Dynamically bound function registering deferred history delivery.

The delivery transport calls this function while capturing a replaceable
packet.  It returns a no-argument effect that commits the transaction's frozen
history record only if that packet is actually sent.")

(defun emacsvox-aural--history-value (value)
  "Return a data-only copy of VALUE that cannot retain a source buffer."
  (cond
   ((bufferp value) nil)
   ((markerp value)
    (list
     :marker-position (marker-position value)
     :source-buffer-name
     (and (marker-buffer value) (buffer-name (marker-buffer value)))))
   ((stringp value) (substring-no-properties value))
   ((consp value)
    (cons
     (emacsvox-aural--history-value (car value))
     (emacsvox-aural--history-value (cdr value))))
   ((hash-table-p value)
    (let ((copy
           (make-hash-table
            :test (hash-table-test value)
            :size (max 1 (hash-table-count value)))))
      (maphash
       (lambda (key item)
         (puthash
          (emacsvox-aural--history-value key)
          (emacsvox-aural--history-value item)
          copy))
       value)
      copy))
   ((vectorp value)
    (vconcat (mapcar #'emacsvox-aural--history-value value)))
   (t value)))

(cl-defun emacsvox-aural--freeze-presentation-plan
    (plan &optional (text nil text-supplied-p))
  "Return a data-only copy of PLAN containing optional exact TEXT."
  (let* ((context (emacsvox-aural-concrete-plan-context plan))
         (frozen (emacsvox-aural--history-value plan))
         (frozen-context
          (plist-put
           (emacsvox-aural-concrete-plan-context frozen)
           :source-buffer nil)))
    (setf
     (emacsvox-aural-concrete-plan-context frozen)
     frozen-context)
    (when
        (and
         emacsvox-aural--history-respect-icon-policy
         (not (emacsvox-aural-icons-enabled-p context)))
      (setf
       (emacsvox-aural-concrete-plan-before frozen)
       (cl-remove
        'cue
        (emacsvox-aural-concrete-plan-before frozen)
        :key #'emacsvox-aural-concrete-action-kind))
      (setf
       (emacsvox-aural-concrete-plan-after frozen)
       (cl-remove
        'cue
        (emacsvox-aural-concrete-plan-after frozen)
        :key #'emacsvox-aural-concrete-action-kind))
      (push
       '(:reason icons-disabled-at-source)
       (emacsvox-aural-concrete-plan-degradations frozen)))
    (when text-supplied-p
      (setf
       (emacsvox-aural-concrete-content-text
        (emacsvox-aural-concrete-plan-content frozen))
       (and text (substring-no-properties text))))
    frozen))

(defun emacsvox-aural--retain-presentation-record (record)
  "Retain bounded presentation RECORD and return it."
  (push record emacsvox-aural-presentation-history)
  (when
      (> (length emacsvox-aural-presentation-history)
         emacsvox-aural-presentation-history-limit)
    (setcdr
     (nthcdr
      (1- emacsvox-aural-presentation-history-limit)
      emacsvox-aural-presentation-history)
     nil))
  record)

(defun emacsvox-aural--make-history-record
    (plans pauses &optional transaction-id)
  "Return a history record for frozen PLANS, PAUSES, and TRANSACTION-ID."
  (let* ((plan (car plans))
         (context (emacsvox-aural-concrete-plan-context plan)))
    (emacsvox-aural--make-presentation-record
     :id (cl-incf emacsvox-aural--presentation-sequence)
     :queued-at (current-time)
     :plan plan
     :plans plans
     :pauses pauses
     :transaction-id transaction-id
     :source-buffer-name (plist-get context :source-buffer-name)
     :source-position (plist-get context :source-position)
     :object-id
     (emacsvox-aural--history-value
      (emacsvox-aural-concrete-plan-object-id plan))
     :run-id
     (and
      (null (cdr plans))
      (emacsvox-aural--history-value
       (emacsvox-aural-concrete-plan-run-id plan))))))

(cl-defun emacsvox-aural-record-presentation
    (plan &optional (text nil text-supplied-p) pause)
  "Retain a bounded data-only record of transport-submitted PLAN.

When TEXT is supplied, freeze that exact queue payload in the copied content
rather than the source-plan content.  PAUSE is the run's leading transport
pause.  During a matching native transaction, collect the frozen run for one
combined history record."
  (unless (natnump emacsvox-aural-presentation-history-limit)
    (signal
     'emacsvox-aural-transport-error
     (list
      (format
       "Presentation history limit must be a natural number: %S"
       emacsvox-aural-presentation-history-limit))))
  (let ((context (emacsvox-aural-concrete-plan-context plan)))
    (cond
     ((zerop emacsvox-aural-presentation-history-limit)
      (setq emacsvox-aural-presentation-history nil))
     ((plist-get context :history-recording-inhibited) nil)
     (t
      (let ((frozen
             (if text-supplied-p
                 (emacsvox-aural--freeze-presentation-plan plan text)
               (emacsvox-aural--freeze-presentation-plan plan))))
        (if
            (and
             emacsvox-aural--history-transaction-id
             (equal
              emacsvox-aural--history-transaction-id
              (plist-get context :presentation-transaction-id)))
            (push
             (list frozen (emacsvox-aural--history-value pause))
             emacsvox-aural--history-transaction-runs)
          (emacsvox-aural--retain-presentation-record
           (emacsvox-aural--make-history-record
            (list frozen)
            (list (emacsvox-aural--history-value pause))))))))))

(defun emacsvox-aural-call-with-presentation-transaction
    (transaction-id function &rest arguments)
  "Call FUNCTION with ARGUMENTS and retain one history TRANSACTION-ID.

Concrete runs submitted beneath the call are retained together when
their plans carry the matching transaction identifier.  Unrelated legacy
presentations keep independent history records."
  (let* ((emacsvox-aural--history-transaction-id transaction-id)
         (emacsvox-aural--history-transaction-runs nil)
         (deferred-state (list :registered nil :delivered nil :record nil))
         (emacsvox-aural--delivery-history-registrar
          (and
           (eq emacsvox-aural-submission-delivery-policy 'replaceable)
           (lambda ()
             (setq deferred-state
                   (plist-put deferred-state :registered t))
             (lambda ()
               (if-let* ((record (plist-get deferred-state :record)))
                   (emacsvox-aural--retain-presentation-record record)
                 (setq deferred-state
                       (plist-put deferred-state :delivered t)))))))
         result)
    (unwind-protect
        (setq result (apply function arguments))
      (when emacsvox-aural--history-transaction-runs
        (let* ((runs
                (nreverse emacsvox-aural--history-transaction-runs))
               (record
                (emacsvox-aural--make-history-record
                 (mapcar #'car runs)
                 (mapcar #'cadr runs)
                 transaction-id)))
          (if (plist-get deferred-state :registered)
              (progn
                (setq deferred-state
                      (plist-put deferred-state :record record))
                (when (plist-get deferred-state :delivered)
                  (emacsvox-aural--retain-presentation-record record)))
            (emacsvox-aural--retain-presentation-record record)))))
    result))

(defun emacsvox-aural-presentation-record-effective-plans (record)
  "Return every frozen concrete plan retained by RECORD."
  (or
   (condition-case nil
       (emacsvox-aural-presentation-record-plans record)
     (args-out-of-range nil))
   (list (emacsvox-aural-presentation-record-plan record))))

(defun emacsvox-aural-presentation-record-effective-transaction-id
    (record)
  "Return RECORD's transaction identifier, including for older records."
  (condition-case nil
      (emacsvox-aural-presentation-record-transaction-id record)
    (args-out-of-range nil)))

(defun emacsvox-aural-presentation-record-runs (record)
  "Return RECORD as exact PLAN, payload, and leading-pause runs."
  (let ((plans
         (emacsvox-aural-presentation-record-effective-plans record))
        (pauses
         (condition-case nil
             (emacsvox-aural-presentation-record-pauses record)
           (args-out-of-range nil))))
    (cl-loop
     for plan in plans
     for pause in (or pauses (make-list (length plans) nil))
     collect
     (list
      plan
      (emacsvox-aural-concrete-content-text
       (emacsvox-aural-concrete-plan-content plan))
      pause))))

(defun emacsvox-aural-last-presentation (&optional source)
  "Return the latest frozen presentation record for optional SOURCE.

SOURCE may be a buffer or buffer name.  With nil, return the latest record
from any source."
  (if (null source)
      (car emacsvox-aural-presentation-history)
    (let ((name (if (bufferp source) (buffer-name source) source)))
      (cl-find
       name emacsvox-aural-presentation-history
       :key #'emacsvox-aural-presentation-record-source-buffer-name
       :test #'equal))))

(provide 'emacsvox-aural-history)
;;; emacsvox-aural-history.el ends here
