;;; omnivox-library-apply.el --- Coordinate voice-library activation -*- lexical-binding: t; -*-

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

;; Private, effect-driven Apply coordinator.  A native provider executes one
;; issued action and returns its correlated receipt.  This module decides when
;; retirement, replacement, commit and paired rollback may follow.  It performs
;; no process or file operations itself.  There is deliberately no interactive
;; entry point until a native provider supplies ownership and durable receipts.
;; See docs/voice-library-apply-controller.org for the provider boundary.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(cl-defstruct (omnivox-library-apply--operation
               (:constructor omnivox-library-apply--create))
  plan phase ticket issued cancelled workers seen evidence failure final result)

(defun omnivox-library-apply--copy (value)
  "Copy bounded data VALUE, including strings, rejecting cycles and handles."
  (let ((nodes 0) (bytes 0) (path (make-hash-table :test #'eq)))
    (cl-labels
        ((walk (item depth)
           (when (or (> (cl-incf nodes) 262144) (> depth 128))
             (error "Activation data is too large or deeply nested"))
           (cond
            ((stringp item)
             (when (> (cl-incf bytes (string-bytes item)) (* 16 1024 1024))
               (error "Activation data exceeds 16 MiB"))
             (substring-no-properties item))
            ((or (consp item) (vectorp item) (hash-table-p item))
             (when (gethash item path) (error "Activation data contains a cycle"))
             (puthash item t path)
             (prog1
                 (cond
                  ((consp item)
                   (cons (walk (car item) (1+ depth)) (walk (cdr item) (1+ depth))))
                  ((hash-table-p item)
                   ;; Voice-choice adjustments use tables for JSON objects,
                   ;; particularly {}.  Freeze their contents like other data.
                   (let ((copy (make-hash-table :test (hash-table-test item))))
                     (maphash (lambda (key child)
                                (puthash (walk key (1+ depth))
                                         (walk child (1+ depth)) copy)) item)
                     copy))
                  (t (vconcat (mapcar (lambda (child) (walk child (1+ depth))) item))))
               (remhash item path)))
            ((or (null item) (symbolp item) (numberp item)) item)
            (t (error "Activation plans must contain data, not live handles")))))
      (walk value 0))))

(defun omnivox-library-apply--equal (left right)
  "Compare frozen data LEFT and RIGHT, including JSON object contents."
  (cond
   ((eq left right) t)
   ((and (hash-table-p left) (hash-table-p right))
    (and (eq (hash-table-test left) (hash-table-test right))
         (= (hash-table-count left) (hash-table-count right))
         (let ((missing (make-symbol "missing")))
           (catch 'different
             (maphash
              (lambda (key value)
                (let ((other (gethash key right missing)))
                  (unless (and (not (eq other missing))
                               (omnivox-library-apply--equal value other))
                    (throw 'different nil)))) left)
             t))))
   ((and (consp left) (consp right))
    (and (omnivox-library-apply--equal (car left) (car right))
         (omnivox-library-apply--equal (cdr left) (cdr right))))
   ((and (vectorp left) (vectorp right))
    (and (= (length left) (length right))
         (cl-loop for a across left for b across right
                  always (omnivox-library-apply--equal a b))))
   (t (equal left right))))

(defun omnivox-library-apply--keys (object keys)
  "Require exactly KEYS once each in plist OBJECT."
  (unless (and (proper-list-p object) (= (length object) (* 2 (length keys))))
    (error "Invalid activation record"))
  (let (seen)
    (cl-loop for (key _value) on object by #'cddr do
             (unless (and (memq key keys) (not (memq key seen)))
               (error "Unknown or duplicate activation field %S" key))
             (push key seen)))
  object)

(defun omnivox-library-apply--string (value limit &optional pattern)
  "Require a nonempty bounded VALUE with optional full-string PATTERN."
  (unless (and (stringp value) (<= 1 (string-bytes value) limit)
               (not (string-match-p "[[:cntrl:]]" value))
               (or (not pattern) (string-match-p (concat "\\`" pattern "\\'") value)))
    (error "Invalid activation identifier"))
  value)

(defun omnivox-library-apply--uuid (value)
  "Validate canonical UUID VALUE."
  (omnivox-library-apply--string
   value 36 "[0-9a-f]\\{8\\}-[0-9a-f]\\{4\\}-[0-9a-f]\\{4\\}-[0-9a-f]\\{4\\}-[0-9a-f]\\{12\\}"))

(defun omnivox-library-apply--hash (value)
  "Validate SHA-256 VALUE."
  (omnivox-library-apply--string value 64 "[0-9a-f]\\{64\\}"))

(defun omnivox-library-apply--configuration (value)
  "Normalize complete configuration VALUE, preserving explicit legacy null."
  (if (eq value :null) :null
    (omnivox-library-apply--keys value '(:target_id :profile_id :generation_id :sha256))
    (list :target_id (omnivox-library-apply--uuid (plist-get value :target_id))
          :profile_id (omnivox-library-apply--uuid (plist-get value :profile_id))
          :generation_id (omnivox-library-apply--uuid (plist-get value :generation_id))
          :sha256 (omnivox-library-apply--hash (plist-get value :sha256)))))

(defun omnivox-library-apply--ordered (value physical)
  "Normalize sorted, unique vector VALUE of engine IDs or PHYSICAL pairs."
  (unless (and (vectorp value) (<= (length value) 4096))
    (error "Invalid activation identity array"))
  (let (previous result)
    (seq-doseq (item value)
      (let* ((entry
              (if physical
                  (progn
                    (omnivox-library-apply--keys item '(:engine_id :voice_id))
                    (list :engine_id (omnivox-library-apply--string (plist-get item :engine_id) 128)
                          :voice_id (omnivox-library-apply--string (plist-get item :voice_id) 4096)))
                (omnivox-library-apply--string item 128)))
             ;; A NUL cannot occur in either component, so this preserves tuple order.
             (key (if physical (concat (plist-get entry :engine_id) "\0" (plist-get entry :voice_id)) entry)))
        (when (and previous (not (string< previous key)))
          (error "Activation identities must be sorted and unique"))
        (setq previous key)
        (push entry result)))
    (vconcat (nreverse result))))

(defun omnivox-library-apply--pair (rows)
  "Require one speaker and one notification record in vector ROWS."
  (unless (and (vectorp rows) (= (length rows) 2)
               (eq (plist-get (aref rows 0) :role) 'speaker)
               (eq (plist-get (aref rows 1) :role) 'notification))
    (error "Activation needs the ordered speaker and notification pair"))
  rows)

(defun omnivox-library-apply--begin (plan)
  "Freeze reviewed PLAN and return its private Apply operation.
The caller must obtain native startup snapshots and show restart/voice impact
before calling this function.  It does not infer snapshots from active.json."
  (setq plan (omnivox-library-apply--copy plan))
  (omnivox-library-apply--keys
   plan '(:operation-id :candidate :previous-active :index-sha256
                       :overridden-engines :eligible-voices :previous-lanes
                       :candidate-startup :impact))
  (omnivox-library-apply--uuid (plist-get plan :operation-id))
  (omnivox-library-apply--hash (plist-get plan :index-sha256))
  (dolist (key '(:candidate :previous-active))
    (setf (plist-get plan key) (omnivox-library-apply--configuration (plist-get plan key))))
  (when (eq (plist-get plan :candidate) :null) (error "Apply requires a candidate generation"))
  (unless (eq (plist-get plan :previous-active) :null)
    (dolist (key '(:target_id :profile_id))
      (unless (equal (plist-get (plist-get plan :candidate) key)
                     (plist-get (plist-get plan :previous-active) key))
        (error "Active pointer belongs to another target/profile"))))
  (setf (plist-get plan :overridden-engines)
        (omnivox-library-apply--ordered (plist-get plan :overridden-engines) nil)
        (plist-get plan :eligible-voices)
        (omnivox-library-apply--ordered (plist-get plan :eligible-voices) t))
  (omnivox-library-apply--pair (plist-get plan :candidate-startup))
  (seq-doseq (lane (plist-get plan :candidate-startup))
    (omnivox-library-apply--keys lane '(:role :startup))
    (unless (plist-get lane :startup) (error "Candidate native startup snapshot is missing")))
  (let (seen)
    (seq-doseq (lane (omnivox-library-apply--pair (plist-get plan :previous-lanes)))
      (omnivox-library-apply--keys
       lane '(:role :worker :startup :configuration :overridden-engines :eligible-voices))
      (let ((worker (omnivox-library-apply--uuid (plist-get lane :worker))))
        (when (member worker seen) (error "Speech lanes must have distinct owners"))
        (push worker seen))
      (unless (plist-get lane :startup) (error "Previous native startup snapshot is missing"))
      (setf (plist-get lane :configuration)
            (omnivox-library-apply--configuration (plist-get lane :configuration))
            (plist-get lane :overridden-engines)
            (omnivox-library-apply--ordered (plist-get lane :overridden-engines) nil)
            (plist-get lane :eligible-voices)
            (omnivox-library-apply--ordered (plist-get lane :eligible-voices) t)))
    (omnivox-library-apply--create :plan plan :phase 'preflight :ticket 1 :seen seen)))

(defun omnivox-library-apply--action (operation)
  "Issue the next native-provider action for OPERATION, at most once.
The receipt must name its operation UUID, ticket and phase.  Re-reading cannot
repeat a restart or pointer write.  The provider retains ownership across calls."
  (unless (or (omnivox-library-apply--operation-issued operation)
              (omnivox-library-apply--operation-result operation))
    (prog1
        (omnivox-library-apply--copy
         (list :operation-id (plist-get (omnivox-library-apply--operation-plan operation) :operation-id)
               :ticket (omnivox-library-apply--operation-ticket operation)
               :phase (omnivox-library-apply--operation-phase operation)
               :plan (omnivox-library-apply--operation-plan operation)
               :workers (omnivox-library-apply--operation-workers operation)
               :evidence (omnivox-library-apply--operation-evidence operation)
               :final (omnivox-library-apply--operation-final operation)))
      (setf (omnivox-library-apply--operation-issued operation) t))))

(defun omnivox-library-apply--next (operation phase)
  "Move OPERATION to PHASE with a fresh one-use ticket."
  (setf (omnivox-library-apply--operation-phase operation) phase
        (omnivox-library-apply--operation-issued operation) nil)
  (cl-incf (omnivox-library-apply--operation-ticket operation)))

(defun omnivox-library-apply--finish (operation status)
  "Request durable terminal STATUS for OPERATION."
  (setf (omnivox-library-apply--operation-final operation) status)
  (omnivox-library-apply--next operation 'finish))

(defun omnivox-library-apply--done (operation status)
  "Retain terminal observed STATUS without inventing native journal success."
  (setf (omnivox-library-apply--operation-result operation)
        (list :status status :failures (reverse (omnivox-library-apply--operation-failure operation))
              :phase (omnivox-library-apply--operation-phase operation)
              :workers (omnivox-library-apply--copy (omnivox-library-apply--operation-workers operation))
              :cancel-requested (omnivox-library-apply--operation-cancelled operation))
        (omnivox-library-apply--operation-phase operation) 'done))

(defun omnivox-library-apply--fresh-workers (operation workers)
  "Validate and retain new WORKERS, rejecting any previously used owner."
  (omnivox-library-apply--pair workers)
  (let ((seen (copy-sequence (omnivox-library-apply--operation-seen operation))))
    (seq-doseq (lane workers)
      (omnivox-library-apply--keys lane '(:role :worker))
      (let ((id (omnivox-library-apply--uuid (plist-get lane :worker))))
        (when (member id seen) (error "Activation reused a retired or probe owner"))
        (push id seen)))
    (setf (omnivox-library-apply--operation-seen operation) seen))
  workers)

(defun omnivox-library-apply--proofs (operation proofs previous)
  "Check per-lane PROOFS for the candidate or PREVIOUS startup configurations."
  (omnivox-library-apply--pair proofs)
  (let ((plan (omnivox-library-apply--operation-plan operation))
        (workers (omnivox-library-apply--operation-workers operation)))
    (dotimes (index 2)
      (let* ((proof (aref proofs index))
             (expected (if previous (aref (plist-get plan :previous-lanes) index) plan))
             (configuration (plist-get expected (if previous :configuration :candidate)))
             (status (plist-get proof :status)))
        (omnivox-library-apply--keys
         proof '(:role :worker :ready :negotiated :inventory-generation :request-id :status))
        (unless (and (eq (plist-get proof :ready) t)
                     (equal (plist-get proof :worker) (plist-get (aref workers index) :worker)))
          (error "Readiness belongs to another speech worker"))
        (if (eq status :legacy)
            (unless (and previous (eq configuration :null)
                         (null (plist-get proof :negotiated)) (eq (plist-get proof :request-id) :null))
              (error "Managed activation requires negotiated library status"))
          (omnivox-library-apply--keys
           status '(:protocol_version :request_id :type :configuration :overridden_engines
                                      :eligible_voices :inventory_generation))
          (unless (and (eq (plist-get proof :negotiated) t)
                       (eql (plist-get status :protocol_version) 1)
                       (equal (plist-get status :type) "voice_library_status_v1")
                       (integerp (plist-get proof :request-id))
                       (<= 1 (plist-get proof :request-id) (1- (expt 2 64)))
                       (eql (plist-get proof :request-id) (plist-get status :request_id))
                       (integerp (plist-get proof :inventory-generation))
                       (<= 0 (plist-get proof :inventory-generation) (1- (expt 2 64)))
                       (eql (plist-get proof :inventory-generation) (plist-get status :inventory_generation))
                       (equal configuration (omnivox-library-apply--configuration (plist-get status :configuration)))
                       (equal (plist-get expected :overridden-engines)
                              (omnivox-library-apply--ordered (plist-get status :overridden_engines) nil))
                       (equal (plist-get expected :eligible-voices)
                              (omnivox-library-apply--ordered (plist-get status :eligible_voices) t)))
            (error "Speech lane acknowledged different library inputs or eligibility"))))))
  proofs)

(defun omnivox-library-apply--failed (operation reason)
  "Handle failure REASON in OPERATION without assuming an unknown commit failed."
  (push (list :phase (omnivox-library-apply--operation-phase operation) :reason reason)
        (omnivox-library-apply--operation-failure operation))
  (pcase (omnivox-library-apply--operation-phase operation)
    ((or 'preflight 'activating)
     (omnivox-library-apply--finish operation 'failed))
    ((or 'start-candidate 'verify-candidate)
     (omnivox-library-apply--next operation 'rolling-back))
    ('rolling-back
     ;; Even without a durable rollback record, retire attempted candidates.
     ;; Do not begin another native load until that journal problem is resolved.
     (setf (omnivox-library-apply--operation-final operation) 'recovery-failed)
     (omnivox-library-apply--next operation 'retire-candidate))
    ('commit (omnivox-library-apply--done operation 'interrupted))
    ('finish (omnivox-library-apply--done operation 'interrupted))
    (_ (omnivox-library-apply--finish operation 'recovery-failed))))

(defun omnivox-library-apply--complete (operation operation-id ticket phase receipt)
  "Consume a correlated provider RECEIPT for OPERATION, or ignore a stale one.
OPERATION-ID, TICKET and PHASE must match the issued action.  Provider failures
include :ok nil.  A commit failure is ambiguous unless :commit is explicitly
not-committed; never restart old workers under a possibly committed pointer."
  (when (and (not (omnivox-library-apply--operation-result operation))
             (omnivox-library-apply--operation-issued operation)
             (equal operation-id (plist-get (omnivox-library-apply--operation-plan operation) :operation-id))
             (eql ticket (omnivox-library-apply--operation-ticket operation))
             (eq phase (omnivox-library-apply--operation-phase operation)))
    (condition-case error-data
        (let* ((receipt (omnivox-library-apply--copy receipt))
               (plan (omnivox-library-apply--operation-plan operation))
               (cancelled (omnivox-library-apply--operation-cancelled operation)))
          (omnivox-library-apply--keys
           receipt (if (not (eq (plist-get receipt :ok) t)) '(:ok :message)
                     (pcase phase
                       ('preflight '(:ok :workers :proofs :quiescent))
                       ('activating '(:ok :previous-active :index-sha256 :previous-lanes))
                       ((or 'retire-old 'retire-candidate) '(:ok :quiescent))
                       ((or 'start-candidate 'start-previous) '(:ok :workers))
                       ((or 'verify-candidate 'verify-previous) '(:ok :proofs))
                       ('commit '(:ok :commit :active))
                       ('rolling-back '(:ok :previous-active))
                       ('finish '(:ok :state)))))
          (unless (eq (plist-get receipt :ok) t) (error "Native action failed: %s" (plist-get receipt :message)))
          (pcase phase
            ('preflight
             (setf (omnivox-library-apply--operation-workers operation)
                   (omnivox-library-apply--fresh-workers operation (plist-get receipt :workers)))
             (omnivox-library-apply--proofs operation (plist-get receipt :proofs) nil)
             (unless (eq (plist-get receipt :quiescent) t) (error "Preflight workers have not exited"))
             (setf (omnivox-library-apply--operation-workers operation) nil)
             (if cancelled (omnivox-library-apply--finish operation 'cancelled)
               (omnivox-library-apply--next operation 'activating)))
            ('activating
             (unless (and (equal (plist-get receipt :previous-active) (plist-get plan :previous-active))
                          (equal (plist-get receipt :index-sha256) (plist-get plan :index-sha256))
                          (omnivox-library-apply--equal
                           (plist-get receipt :previous-lanes) (plist-get plan :previous-lanes)))
               (error "Apply plan changed before retirement"))
             (if cancelled (omnivox-library-apply--finish operation 'cancelled)
               (omnivox-library-apply--next operation 'retire-old)))
            ((or 'retire-old 'retire-candidate)
             (unless (eq (plist-get receipt :quiescent) t) (error "Native pair cleanup is unconfirmed"))
             (setf (omnivox-library-apply--operation-workers operation) nil)
             (if (and (eq phase 'retire-candidate)
                      (eq (omnivox-library-apply--operation-final operation) 'recovery-failed))
                 (omnivox-library-apply--finish operation 'recovery-failed)
               (omnivox-library-apply--next
                operation (if (eq phase 'retire-candidate) 'start-previous
                            (if cancelled 'rolling-back 'start-candidate)))))
            ((or 'start-candidate 'start-previous)
             (setf (omnivox-library-apply--operation-workers operation)
                   (omnivox-library-apply--fresh-workers operation (plist-get receipt :workers)))
             (omnivox-library-apply--next
              operation (if (eq phase 'start-previous) 'verify-previous
                          (if cancelled 'rolling-back 'verify-candidate))))
            ((or 'verify-candidate 'verify-previous)
             (setf (omnivox-library-apply--operation-evidence operation)
                   (omnivox-library-apply--proofs operation (plist-get receipt :proofs) (eq phase 'verify-previous)))
             (if (eq phase 'verify-previous) (omnivox-library-apply--finish operation 'rolled-back)
               (omnivox-library-apply--next operation (if cancelled 'rolling-back 'commit))))
            ('commit
             (pcase (plist-get receipt :commit)
               ('committed
                (unless (equal (plist-get receipt :active) (plist-get plan :candidate))
                  (error "Committed pointer does not match candidate"))
                (omnivox-library-apply--done operation 'succeeded))
               ('not-committed
                (unless (equal (plist-get receipt :active) (plist-get plan :previous-active))
                  (error "Active pointer changed despite uncommitted result"))
                (omnivox-library-apply--next operation 'rolling-back))
               (_ (error "Active-pointer commit outcome is unknown"))))
            ('rolling-back
             (unless (equal (plist-get receipt :previous-active) (plist-get plan :previous-active))
               (error "Cannot roll back against a changed active pointer"))
             (omnivox-library-apply--next operation 'retire-candidate))
            ('finish
             (unless (eq (plist-get receipt :state) (omnivox-library-apply--operation-final operation))
               (error "Native terminal journal differs from coordinator result"))
             (omnivox-library-apply--done operation (plist-get receipt :state)))))
      (error (omnivox-library-apply--failed operation (error-message-string error-data))))
    t))

(defun omnivox-library-apply--cancel (operation)
  "Request cancellation of OPERATION without abandoning an in-flight action.
The driver cancels owned preflight work and still delivers its cleanup receipt.
After retirement, continue paired rollback.  A confirmed commit wins a race
with cancellation; an uncertain commit requires explicit reconciliation."
  (unless (omnivox-library-apply--operation-result operation)
    (setf (omnivox-library-apply--operation-cancelled operation) t)
    ;; An unissued commit has no possible external effect and can be withdrawn.
    (unless (omnivox-library-apply--operation-issued operation)
      (pcase (omnivox-library-apply--operation-phase operation)
        ((or 'preflight 'activating 'retire-old)
         (omnivox-library-apply--finish operation 'cancelled))
        ((or 'start-candidate 'verify-candidate 'commit)
         (omnivox-library-apply--next operation 'rolling-back))))))

(provide 'omnivox-library-apply)
;;; omnivox-library-apply.el ends here
