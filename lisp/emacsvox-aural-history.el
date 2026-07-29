;;; emacsvox-aural-history.el --- Frozen aural observability -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Bounded, data-only records of presentations that were actually played or
;; queued.  History never retains source buffers and does not resolve rules,
;; resources, voices, or backend transport.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural)
(require 'emacsvox-aural-concrete)

(cl-defstruct
    (emacsvox-aural-presentation-record
     (:constructor emacsvox-aural--make-presentation-record))
  "One bounded, data-only record of an actually queued presentation."
  id queued-at plan source-buffer-name source-position object-id run-id)

(defvar emacsvox-aural-plan-presented-hook nil
  "Abnormal hook run after presenting one concrete aural plan.

Each function receives the `emacsvox-aural-concrete-plan' that was presented.
Queue transport runs this after queueing; standalone local cues run it after
playback has been requested.")

(defcustom emacsvox-aural-presentation-history-limit 20
  "Maximum number of actually queued presentations retained for inspection.

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

(cl-defun emacsvox-aural-record-presentation
    (plan &optional (text nil text-supplied-p))
  "Retain a bounded data-only record of actually presented PLAN.

When TEXT is supplied, freeze that exact queue payload in the copied content
rather than the source-plan content."
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
      (let* ((frozen (emacsvox-aural--history-value plan))
             (frozen-context
              (plist-put
               (emacsvox-aural-concrete-plan-context frozen)
               :source-buffer nil))
             (record
              (emacsvox-aural--make-presentation-record
               :id (cl-incf emacsvox-aural--presentation-sequence)
               :queued-at (current-time)
               :plan frozen
               :source-buffer-name (plist-get context :source-buffer-name)
               :source-position (plist-get context :source-position)
               :object-id
               (emacsvox-aural--history-value
                (emacsvox-aural-concrete-plan-object-id plan))
               :run-id
               (emacsvox-aural--history-value
                (emacsvox-aural-concrete-plan-run-id plan)))))
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
        (push record emacsvox-aural-presentation-history)
        (when
            (> (length emacsvox-aural-presentation-history)
               emacsvox-aural-presentation-history-limit)
          (setcdr
           (nthcdr
            (1- emacsvox-aural-presentation-history-limit)
            emacsvox-aural-presentation-history)
           nil))
        record)))))

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
