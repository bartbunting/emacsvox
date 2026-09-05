;;; emacsvox-aural-history.el --- Frozen aural observability -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Bounded, data-only records of presentations actually submitted to a live
;; transport.  History never retains source buffers and does not resolve rules,
;; resources, voices, or backend transport.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-rules)

(defvar emacsvox-aural-submission-delivery-policy)
(defvar emacsvox-aural-source-buffer-id)

(cl-defstruct
    (emacsvox-aural-presentation-record
     (:constructor emacsvox-aural--make-presentation-record))
  "One bounded, data-only record of a transport-submitted presentation.

PLAN remains the representative first run for compatibility.  PLANS and
PAUSES retain bounded formatting-run previews in a native transaction."
  id queued-at plan source-buffer-name source-position object-id run-id
  plans pauses transaction-id payload-preview payload-character-count
  payload-byte-count payload-sha256 payload-truncated-p)

(defconst emacsvox-aural--history-preview-max-bytes 4096
  "Maximum aggregate UTF-8 speech preview retained in one history record.")

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

(defvar emacsvox-aural--presented-plan-collector nil
  "Dynamically bound function collecting effective queued plans.

Queue transport calls the function once for each concrete formatting run,
after applying payload replacement and source icon policy to a data-only copy.
Native submissions use this to report what was actually presented without
mutating their compiled plans or depending on history retention.")

(defvar emacsvox-aural--history-transaction-id nil
  "Identifier of the dynamically active native history transaction.")

(defvar emacsvox-aural--history-transaction-runs nil
  "Reverse-ordered frozen runs in the active history transaction.")

(defvar emacsvox-aural--delivery-history-registrar nil
  "Dynamically bound function registering deferred history delivery.

The delivery transport calls this function while capturing a packet.  It
returns a no-argument effect that commits the transaction's frozen history
record only if that packet is actually sent.")

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
   ((recordp value)
    (let ((copy (copy-sequence value)))
      (cl-loop
       for index from 1 below (length value)
       do
       (aset
        copy index
        (emacsvox-aural--history-value (aref value index))))
      copy))
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
         (frozen-context (emacsvox-aural-concrete-plan-context frozen)))
    (when (plist-member frozen-context :source-buffer)
      (setq frozen-context (plist-put frozen-context :source-buffer nil)))
    (setf
     (emacsvox-aural-concrete-plan-context frozen)
     frozen-context)
    (when
        (and
         emacsvox-aural--history-respect-icon-policy
         (not (emacsvox-aural-icons-enabled-p context)))
      (let ((before (emacsvox-aural-concrete-plan-before frozen))
            (after (emacsvox-aural-concrete-plan-after frozen)))
        (when
            (cl-some
             (lambda (action)
               (eq 'cue (emacsvox-aural-concrete-action-kind action)))
             (append before after))
          (setf
           (emacsvox-aural-concrete-plan-before frozen)
           (cl-remove
            'cue before :key #'emacsvox-aural-concrete-action-kind))
          (setf
           (emacsvox-aural-concrete-plan-after frozen)
           (cl-remove
            'cue after :key #'emacsvox-aural-concrete-action-kind))
          (push
           '(:reason icons-disabled-at-source)
           (emacsvox-aural-concrete-plan-degradations frozen)))))
    (when text-supplied-p
      (setf
       (emacsvox-aural-concrete-content-text
        (emacsvox-aural-concrete-plan-content frozen))
       (and text (substring-no-properties text))))
    frozen))

(defun emacsvox-aural--retain-presentation-record (record)
  "Retain bounded presentation RECORD and return it."
  (if (zerop emacsvox-aural-presentation-history-limit)
      (setq emacsvox-aural-presentation-history nil)
    (push record emacsvox-aural-presentation-history)
    (when
        (> (length emacsvox-aural-presentation-history)
           emacsvox-aural-presentation-history-limit)
      (setcdr
       (nthcdr
        (1- emacsvox-aural-presentation-history-limit)
        emacsvox-aural-presentation-history)
       nil)))
  record)

(defun emacsvox-aural--history-text-prefix (text byte-limit)
  "Return the longest character prefix of TEXT within BYTE-LIMIT UTF-8 bytes."
  (cond
   ((or (not (stringp text)) (<= byte-limit 0)) "")
   ((<= (string-bytes text) byte-limit) text)
   (t
    (let ((low 0)
          (high (1+ (length text))))
      (while (< (1+ low) high)
        (let ((middle (/ (+ low high) 2)))
          (if (<= (string-bytes (substring text 0 middle)) byte-limit)
              (setq low middle)
            (setq high middle))))
      (substring text 0 low)))))

(defun emacsvox-aural--history-plan-payload-texts (plan)
  "Return ordered speech payload strings represented by concrete PLAN."
  (let (texts)
    (dolist (action (emacsvox-aural-concrete-plan-before plan))
      (when
          (and
           (eq 'speech (emacsvox-aural-concrete-action-kind action))
           (stringp (emacsvox-aural-concrete-action-text action)))
        (push (emacsvox-aural-concrete-action-text action) texts)))
    (when-let* ((text
                 (emacsvox-aural-concrete-content-text
                  (emacsvox-aural-concrete-plan-content plan))))
      (push text texts))
    (dolist (action (emacsvox-aural-concrete-plan-after plan))
      (when
          (and
           (eq 'speech (emacsvox-aural-concrete-action-kind action))
           (stringp (emacsvox-aural-concrete-action-text action)))
        (push (emacsvox-aural-concrete-action-text action) texts)))
    (nreverse texts)))

(defun emacsvox-aural--history-payload-metadata (plans)
  "Return preview, totals, digest, and truncation metadata for PLANS."
  (let ((texts
         (cl-mapcan
          (lambda (plan)
            (copy-sequence
             (emacsvox-aural--history-plan-payload-texts plan)))
          plans))
        (remaining emacsvox-aural--history-preview-max-bytes)
        preview-parts
        (character-count 0)
        (byte-count 0)
        digest)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (dolist (text texts)
        (let* ((bytes (string-bytes text))
               (prefix (emacsvox-aural--history-text-prefix text remaining)))
          (cl-incf character-count (length text))
          (cl-incf byte-count bytes)
          (when (not (string-empty-p prefix))
            (push prefix preview-parts)
            (cl-decf remaining (string-bytes prefix)))
          (insert (number-to-string bytes) ":")
          (insert (encode-coding-string text 'utf-8 t))
          (insert "\0")))
      (setq digest (secure-hash 'sha256 (current-buffer))))
    (list
     :preview (apply #'concat (nreverse preview-parts))
     :character-count character-count
     :byte-count byte-count
     :sha256 digest
     :truncated-p
     (> byte-count emacsvox-aural--history-preview-max-bytes))))

(defun emacsvox-aural--bound-history-plan-payload (plan remaining)
  "Bound concrete PLAN's retained speech strings using REMAINING UTF-8 bytes.

Return the preview budget left after PLAN."
  (cl-labels
      ((bound-text
        (text)
        (let ((preview
               (emacsvox-aural--history-text-prefix text remaining)))
          (cl-decf remaining (string-bytes preview))
          preview))
       (bound-action
        (action)
        (when
            (and
             (eq 'speech (emacsvox-aural-concrete-action-kind action))
             (stringp (emacsvox-aural-concrete-action-text action)))
          (setf
           (emacsvox-aural-concrete-action-text action)
           (bound-text (emacsvox-aural-concrete-action-text action))))))
    (dolist (action (emacsvox-aural-concrete-plan-before plan))
      (bound-action action))
    (let* ((content (emacsvox-aural-concrete-plan-content plan))
           (text (emacsvox-aural-concrete-content-text content)))
      (when (stringp text)
        (setf
         (emacsvox-aural-concrete-content-text content)
         (bound-text text))))
    (dolist (action (emacsvox-aural-concrete-plan-after plan))
      (bound-action action))
    (let ((facts (emacsvox-aural-concrete-plan-facts plan))
          (content
           (emacsvox-aural-concrete-content-text
            (emacsvox-aural-concrete-plan-content plan))))
      (when (plist-member facts :content)
        (setf
         (emacsvox-aural-concrete-plan-facts plan)
         (plist-put facts :content content))))
    ;; Render plans may repeat speech-action strings.  Keep their policy shape
    ;; for explanation while the concrete preview and record digest own text.
    (when-let* ((render (emacsvox-aural-concrete-plan-source-plan plan)))
      (dolist
          (action
           (append
            (emacsvox-aural-render-plan-before render)
            (emacsvox-aural-render-plan-after render)))
        (when (eq 'speech (emacsvox-aural-action-kind action))
          (setf (emacsvox-aural-action-text action) "")
          (setf (emacsvox-aural-action-text-template action) nil))))
    remaining))

(defun emacsvox-aural--bound-history-plans (plans)
  "Bound retained payload strings across frozen PLANS and return PLANS."
  (let ((remaining emacsvox-aural--history-preview-max-bytes))
    (dolist (plan plans)
      (setq remaining
            (emacsvox-aural--bound-history-plan-payload plan remaining))))
  plans)

(defun emacsvox-aural--make-history-record
    (plans pauses &optional transaction-id)
  "Return a history record for frozen PLANS, PAUSES, and TRANSACTION-ID."
  (let* ((payload (emacsvox-aural--history-payload-metadata plans))
         (plans
          (if (plist-get payload :truncated-p)
              (emacsvox-aural--bound-history-plans plans)
            plans))
         (plan (car plans))
         (context (emacsvox-aural-concrete-plan-context plan)))
    (emacsvox-aural--make-presentation-record
     :id (cl-incf emacsvox-aural--presentation-sequence)
     :queued-at (current-time)
     :plan plan
     :plans plans
     :pauses pauses
     :transaction-id transaction-id
     :payload-preview (plist-get payload :preview)
     :payload-character-count (plist-get payload :character-count)
     :payload-byte-count (plist-get payload :byte-count)
     :payload-sha256 (plist-get payload :sha256)
     :payload-truncated-p (plist-get payload :truncated-p)
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
          (lambda ()
            (setq deferred-state
                  (plist-put deferred-state :registered t))
            (lambda ()
              (if-let* ((record (plist-get deferred-state :record)))
                  (emacsvox-aural--retain-presentation-record record)
                (setq deferred-state
                      (plist-put deferred-state :delivered t))))))
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

(defun emacsvox-aural-presentation-record-effective-payload-truncated-p
    (record)
  "Return non-nil when RECORD retains only a payload preview."
  (condition-case nil
      (emacsvox-aural-presentation-record-payload-truncated-p record)
    (args-out-of-range nil)))

(defun emacsvox-aural-presentation-record-runs (record)
  "Return RECORD as bounded PLAN, payload-preview, and leading-pause runs."
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

(defun emacsvox-aural-presentation-at-point ()
  "Return the latest record only when it still belongs to the current item.
Require source identity, position, and modification tick.  Older records
remain available through Recent Feedback, including after source edits."
  (when-let* ((record (emacsvox-aural-last-presentation (current-buffer)))
              (context (emacsvox-aural-concrete-plan-context
                        (emacsvox-aural-presentation-record-plan record)))
              (identity (plist-get context :source-buffer-id)))
    (when (and (boundp 'emacsvox-aural-source-buffer-id)
               (eq identity emacsvox-aural-source-buffer-id)
               (equal (point) (emacsvox-aural-presentation-record-source-position record))
               (equal (buffer-modified-tick)
                      (plist-get context :source-modification-tick)))
      record)))

(provide 'emacsvox-aural-history)

;;; emacsvox-aural-history.el ends here
