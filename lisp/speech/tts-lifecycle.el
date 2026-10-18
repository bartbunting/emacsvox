;;; tts-lifecycle.el --- Speech preparation and dispatch lifecycle -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: TTS  Emacs Elisp
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

;; Keep speech preparation, dispatch tracking, output observation, interruption
;; and retirement together.  These operations share process generations,
;; cancellation epochs, queue guards and callback ownership.
;;
;; The existing handoff with aural transport is retained: transport captures
;; packets and binds semantic owners; this module reserves, sends, publishes
;; and retires dispatches.  The public `tts-speak' entry point still owns speech
;; configuration, process creation, text preparation and notification commands.
;; Load through `tts-speak'.  Loading definitions does not start speech or
;; install process filters; the existing runtime entry points do that.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tts-queue-state)
(require 'emacsvox-aural-transport)

(declare-function tts-notify-stop "tts-speak" ())
(defvar emacsvox-speak-messages)
(defvar tts-notify-process)
(defvar tts-speaker-process)
(defvar emacsvox-aural--current-submission-id)
(defvar tts-program)
(defvar tts--dispatch-origin)
(defvar tts-stopped-hook)
(declare-function emacsvox-aural-diagnostic-log-event
                  "emacsvox-aural-submission" (event &rest fields))

(defconst tts--tracked-status-prefix "__EMACSVOX_TRACKED__"
  "Speech-server output prefix for tracked dispatch status records.")

(defconst tts--tracked-playback-completion-programs '("windows-outloud")
  "Speech servers that report interruptible playback completion.

Entries are executable basenames.  A server belongs here only when it emits a
tracked `completed' record after its synthesis and audio queues are empty, and
a `cancelled' record when pending input interrupts that wait.")

(defconst tts--tracked-playback-completion-property
  'tts--tracked-playback-completion
  "Process property recording negotiated tracked playback support.")

(defconst tts--marker-playback-events-property
  'tts--marker-playback-events
  "Process property recording negotiated marker playback support.")

(defconst tts--capitalization-presentation-property
  'tts--capitalization-presentation
  "Process property recording negotiated capitalization presentation support.")

(defvar tts--tracked-dispatch-sequence 0
  "Sequence used to identify tracked speech dispatches.")

(defvar tts--tracked-dispatches (make-hash-table :test #'eql)
  "Tracked speech callbacks indexed by dispatch identifier.")

(cl-defstruct (tts--dispatch-lifecycle
               (:constructor tts--dispatch-lifecycle-create))
  process submission-id submitted-at source-observed-at)

(defvar tts--dispatch-lifecycles (make-hash-table :test #'eql)
  "Client-observed lifecycle timing indexed by dispatch identifier.")

(cl-defstruct (tts--marker-dispatch
               (:constructor tts--marker-dispatch-create))
  process callback semantic-actions owner (last-sequence 0))

(defvar tts--marker-dispatches (make-hash-table :test #'eql)
  "Marker callback state indexed by tracked dispatch identifier.")

(cl-defstruct (tts--dispatch-owner (:constructor tts--dispatch-owner-create))
  id process generation epoch submission-id marker completion semantics
  (state 'prepared) published terminal retired released tracking-failed metadata-bytes
  write-started-at write-ended-at context admission-function release-function
  preparation reserved (semantics-bound t))

(cl-defstruct (tts--preparation (:constructor tts--preparation-create))
  process generation owners cancelled closed ready stop-used legacy-stop queue-guard)
(defvar tts--preparations (make-hash-table :test #'eq))
(defvar tts--prepared-owners (make-hash-table :test #'eql))
(defvar tts--current-preparation nil)
(defconst tts--preparation-limit 128)
(define-error 'tts--preparation-cancelled "Speech preparation was cancelled")

(defun tts--preparation-check (&optional preparation)
  "Reject cancelled PREPARATION, defaulting to the current scope."
  (when-let* ((scope (or preparation tts--current-preparation)))
    (let ((process (tts--preparation-process scope)))
      (when (or (tts--preparation-cancelled scope)
                (tts--preparation-closed scope)
                (and (tts--preparation-queue-guard scope)
                     (not (tts-queue--guard-valid-p (tts--preparation-queue-guard scope))))
                (and (processp process)
                     (or (not (process-live-p process))
                         (process-get process 'tts--speech-process-retiring)
                         (not (equal (tts--preparation-generation scope)
                                     (process-get process 'tts--speech-process-generation))))))
        (setf (tts--preparation-cancelled scope) t)
        (signal 'tts--preparation-cancelled nil)))))

(defun tts--preparation-output-guard (process)
  "Return the current preparation's queue guard only for its own PROCESS."
  (and tts--current-preparation
       (eq process (tts--preparation-process tts--current-preparation))
       (tts--preparation-queue-guard tts--current-preparation)))

(defun tts--preparation-set-queue-guard (guard)
  "Attach GUARD to the current preparation without exposing its structure."
  (unless tts--current-preparation (signal 'tts--preparation-cancelled nil))
  (setf (tts--preparation-queue-guard tts--current-preparation) guard))

(defun tts--preparation-cancel-current ()
  "Mark the current preparation cancelled, even if its caller catches an error."
  (when tts--current-preparation
    (setf (tts--preparation-cancelled tts--current-preparation) t)))

(defun tts--preparation-invalidate (process &optional preserved)
  "Cancel PROCESS's open preparations except the explicitly PRESERVED scope."
  (maphash (lambda (scope _)
             (when (and (eq process (tts--preparation-process scope))
                        (not (eq scope preserved)))
               (setf (tts--preparation-cancelled scope) t)))
           tts--preparations))

(defun tts--preparation-release-owners (owners)
  "Release unpublished OWNERS even if one cleanup exits nonlocally."
  (when owners
    (let ((owner (car owners)))
      (unwind-protect
          (unless (tts--dispatch-owner-published owner)
            (unwind-protect (tts--dispatch-abandon owner)
              (unless (tts--dispatch-owner-released owner)
                (tts--dispatch-release owner))))
        (setf (tts--dispatch-owner-preparation owner) nil)
        (tts--preparation-release-owners (cdr owners))))))

(defun tts--call-with-preparation (process function &rest arguments)
  "Call FUNCTION with ARGUMENTS in a new cancellable scope for PROCESS."
  (let* ((scope (tts--preparation-create
                 :process process
                 :generation (and (processp process)
                                  (process-get process 'tts--speech-process-generation))))
         (tts--current-preparation scope))
    (unwind-protect
        (condition-case nil
            (progn
              (when (>= (cl-loop for other being the hash-keys of tts--preparations
                                 count (eq process (tts--preparation-process other)))
                        tts--preparation-limit)
                (error "Speech preparation capacity is exhausted"))
              (puthash scope t tts--preparations)
              (tts--preparation-check scope)
              (prog1 (apply function arguments)
                (tts--preparation-check scope)))
          (tts--preparation-cancelled nil))
      (unwind-protect
          (progn
            (setf (tts--preparation-closed scope) t)
            (tts--preparation-release-owners (tts--preparation-owners scope)))
        (setf (tts--preparation-owners scope) nil)
        (remhash scope tts--preparations)))))

(defun tts--preparation-interrupt (process)
  "Perform the current preparation's one intentional policy stop on PROCESS."
  (let ((scope tts--current-preparation))
    (when scope
      (tts--preparation-check scope)
      (unless (and (eq process (tts--preparation-process scope))
                   (tts--preparation-ready scope)
                   (not (tts--preparation-stop-used scope))
                   (cl-every (lambda (owner)
                               (and (eq (tts--dispatch-owner-state owner) 'prepared)
                                    (not (tts--dispatch-owner-retired owner))))
                             (tts--preparation-owners scope)))
        (signal 'tts--preparation-cancelled nil))
      (setf (tts--preparation-stop-used scope) t))
    (if scope (tts--interrupt-process process nil scope)
      (tts--interrupt-process process))
    (tts--preparation-check scope)))

(defun tts--preparation-before-delivery (process)
  "Validate the current scope before policy interruption of PROCESS."
  (when tts--current-preparation
    (dolist (owner (tts--preparation-owners tts--current-preparation))
      (tts--dispatch-check-admission owner))
    (tts--preparation-check)
    (setf (tts--preparation-ready tts--current-preparation) t)
    (when (tts--preparation-legacy-stop tts--current-preparation)
      (emacsvox-aural-cancel-pending-deliveries process)
      (tts--preparation-interrupt process))))

(defun tts--dispatch-set-accounting (process count bytes)
  "Set PROCESS's owner COUNT and metadata BYTES with rollback on nonlocal exit."
  (let ((old-count (process-get process 'tts--dispatch-owner-count))
        (old-bytes (process-get process 'tts--dispatch-metadata-bytes))
        (inhibit-quit t) complete)
    (unwind-protect
        (progn
          (process-put process 'tts--dispatch-owner-count count)
          (process-put process 'tts--dispatch-metadata-bytes bytes)
          (setq complete t))
      (unless complete
        (process-put process 'tts--dispatch-owner-count old-count)
        (process-put process 'tts--dispatch-metadata-bytes old-bytes)))))

(defconst tts--dispatch-owner-limit 128)
(defconst tts--dispatch-metadata-limit (* 32 1024 1024))
(defconst tts--dispatch-notification-limit 8192)
(defconst tts--dispatch-notification-byte-limit (* 16 1024 1024))
(defvar tts--dispatch-call-depth 0)
(defvar tts--dispatch-drain-active nil)
(defvar tts--input-drain-depth 0)
(defvar emacsvox-aural--submission-depth 0)
(defvar emacsvox-aural--delivery-dispatch-owners nil)

(defun tts--dispatch-copy-data (value)
  "Copy bounded dispatch VALUE, including strings and vector contents."
  (let ((copies (make-hash-table :test #'eq)) pending)
    (cl-labels
        ((allocate (source)
           (if (not (or (stringp source) (consp source) (vectorp source)
                        (hash-table-p source))) source
             (or (gethash source copies)
                 (let ((copy (cond ((consp source) (cons nil nil))
                                   ((hash-table-p source) (copy-hash-table source))
                                   (t (copy-sequence source)))))
                   (puthash source copy copies)
                   (unless (stringp source) (push (cons source copy) pending))
                   copy)))))
      (let ((result (allocate value)))
        (while pending
          (let* ((pair (pop pending)) (source (car pair)) (copy (cdr pair)))
            (cond
             ((consp source)
              (setcar copy (allocate (car source)))
              (setcdr copy (allocate (cdr source))))
             ((hash-table-p source)
              (clrhash copy)
              (maphash (lambda (key item) (puthash (allocate key) (allocate item) copy)) source))
             (t
              (dotimes (index (length source))
                (aset copy index (allocate (aref source index))))))))
        result))))

(defun tts--dispatch-owner-for (process identifier)
  "Return PROCESS's retained owner for IDENTIFIER, including a terminal ticket."
  (when-let* ((entry (gethash identifier tts--marker-dispatches)))
    (when (eq process (tts--marker-dispatch-process entry))
      (tts--marker-dispatch-owner entry))))

(defun tts--dispatch-new-owner (marker completion semantics &optional deferred)
  "Reserve an inactive dispatch for MARKER, COMPLETION and SEMANTICS.
With DEFERRED, require final semantic binding before admission."
  (unless tts--current-preparation
    (error "Speech dispatch reservation requires a preparation scope"))
  (tts--preparation-check)
  (let* ((process tts-speaker-process)
         (copied (tts--dispatch-copy-data semantics))
         (count (or (process-get process 'tts--dispatch-owner-count) 0))
         (used (or (process-get process 'tts--dispatch-metadata-bytes) 0))
         (print-circle t) (print-length nil) (print-level nil)
         (bytes (string-bytes (prin1-to-string copied))))
    (tts--preparation-check)
    (unless (eq process (tts--preparation-process tts--current-preparation))
      (error "Speech reservation belongs to another process"))
    (setq count (or (process-get process 'tts--dispatch-owner-count) 0)
          used (or (process-get process 'tts--dispatch-metadata-bytes) 0))
    (when (or (>= count tts--dispatch-owner-limit)
              (> (+ used bytes) tts--dispatch-metadata-limit))
      (error "Speech dispatch tracking capacity is exhausted"))
    (let ((owner
           (tts--dispatch-owner-create
            :id (cl-incf tts--tracked-dispatch-sequence) :process process
            :generation (process-get process 'tts--speech-process-generation)
            :submission-id (and (boundp 'emacsvox-aural--current-submission-id)
                                emacsvox-aural--current-submission-id)
            :marker marker :completion completion
            :semantics copied :metadata-bytes bytes :semantics-bound (not deferred)
            :preparation tts--current-preparation)))
      (let ((inhibit-quit t))
        (push owner (tts--preparation-owners tts--current-preparation))
        (puthash (tts--dispatch-owner-id owner) owner tts--prepared-owners)
        (tts--dispatch-set-accounting process (1+ count) (+ used bytes))
        (setf (tts--dispatch-owner-reserved owner) t)
        (when emacsvox-aural--delivery-transaction-active-p
          (push owner emacsvox-aural--delivery-dispatch-owners)))
      owner)))

(defun tts--dispatch-bind-semantics (owner semantics)
  "Bind deferred OWNER to copied SEMANTICS exactly once, charging only the delta."
  (let* ((copied (tts--dispatch-copy-data semantics))
         (print-circle t) (print-length nil) (print-level nil)
         (bytes (string-bytes (prin1-to-string copied)))
         (process (tts--dispatch-owner-process owner)))
    (tts--preparation-check (tts--dispatch-owner-preparation owner))
    (when (or (tts--dispatch-owner-retired owner)
              (tts--dispatch-owner-released owner))
      (signal 'tts--preparation-cancelled nil))
    (unless (and (eq (tts--dispatch-owner-state owner) 'prepared)
                 (tts--dispatch-owner-reserved owner)
                 (not (tts--dispatch-owner-retired owner))
                 (not (tts--dispatch-owner-released owner))
                 (not (tts--dispatch-owner-semantics-bound owner)))
      (error "Speech dispatch cannot bind semantics again"))
    (let* ((old-map (tts--dispatch-owner-semantics owner))
           (old-charge (tts--dispatch-owner-metadata-bytes owner))
           (old-bytes (string-bytes (prin1-to-string old-map)))
           (used (or (process-get process 'tts--dispatch-metadata-bytes) 0))
           (count (or (process-get process 'tts--dispatch-owner-count) 0))
           (delta (- bytes old-bytes))
           (inhibit-quit t) complete)
      (when (> (+ used delta) tts--dispatch-metadata-limit)
        (error "Speech dispatch tracking capacity is exhausted"))
      (unwind-protect
          (progn
            (tts--dispatch-set-accounting process count (+ used delta))
            (setf (tts--dispatch-owner-semantics owner) copied
                  (tts--dispatch-owner-metadata-bytes owner) (+ old-charge delta)
                  (tts--dispatch-owner-semantics-bound owner) t)
            (setq complete t))
        (unless complete
          (setf (tts--dispatch-owner-semantics owner) old-map
                (tts--dispatch-owner-metadata-bytes owner) old-charge
                (tts--dispatch-owner-semantics-bound owner) nil)
          (tts--dispatch-set-accounting process count used)))))
  owner)

(defun tts--dispatch-check-admission (owner)
  "Validate inactive OWNER without installing playback observation."
  (tts--preparation-check (tts--dispatch-owner-preparation owner))
  (when (or (tts--dispatch-owner-retired owner)
            (tts--dispatch-owner-released owner))
    (signal 'tts--preparation-cancelled nil))
  (unless (eq (tts--dispatch-owner-state owner) 'prepared)
    (error "Speech dispatch is already armed"))
  (unless (tts--dispatch-owner-semantics-bound owner)
    (error "Speech dispatch semantics have not been bound"))
  (when-let* ((validate (tts--dispatch-owner-admission-function owner)))
    (funcall validate owner))
  (tts--preparation-check (tts--dispatch-owner-preparation owner))
  (when (tts--dispatch-owner-retired owner)
    (signal 'tts--preparation-cancelled nil)))

(defun tts--dispatch-arm (owner)
  "Install inactive OWNER immediately before writing its complete packet."
  (let ((process (tts--dispatch-owner-process owner))
        (id (tts--dispatch-owner-id owner)))
    (tts--dispatch-check-admission owner)
    (unless (and (eq (tts--dispatch-owner-state owner) 'prepared)
                 (not (tts--dispatch-owner-retired owner))
                 (process-live-p process)
                 (not (process-get process 'tts--speech-process-retiring))
                 (equal (tts--dispatch-owner-generation owner)
                        (process-get process 'tts--speech-process-generation)))
      (error "Speech dispatch owner is no longer available"))
    (setf (tts--dispatch-owner-state owner) 'writing
          (tts--dispatch-owner-write-started-at owner) (float-time)
          (tts--dispatch-owner-epoch owner)
          (or (process-get process 'tts--dispatch-cancellation-epoch) 0))
    (process-put process 'tts--owns-playback-events t)
    (puthash id (tts--marker-dispatch-create
                 :process process :callback (tts--dispatch-owner-marker owner)
                 :semantic-actions (tts--dispatch-owner-semantics owner)
                 :owner owner)
             tts--marker-dispatches)
    (when (tts--dispatch-owner-completion owner)
      (puthash id (cons process (tts--dispatch-owner-completion owner))
               tts--tracked-dispatches))
    (puthash id (tts--dispatch-lifecycle-create
                 :process process :submission-id (tts--dispatch-owner-submission-id owner)
                 :submitted-at (tts--dispatch-owner-write-started-at owner))
             tts--dispatch-lifecycles)
    (remhash id tts--prepared-owners)))

(defun tts--dispatch-release-reservation (owner)
  "Release OWNER's generic reservation, or leave it intact on failure."
  (when (tts--dispatch-owner-reserved owner)
    (let ((process (tts--dispatch-owner-process owner)))
      (tts--dispatch-set-accounting
       process (1- (process-get process 'tts--dispatch-owner-count))
       (- (process-get process 'tts--dispatch-metadata-bytes)
          (tts--dispatch-owner-metadata-bytes owner)))
      (setf (tts--dispatch-owner-reserved owner) nil))))

(defun tts--dispatch-release (owner)
  "Release OWNER's reservation and indexes exactly once."
  (unless (tts--dispatch-owner-released owner)
    (let ((id (tts--dispatch-owner-id owner))
          (inhibit-quit t))
      (unwind-protect
          (unwind-protect
              (when-let* ((release (tts--dispatch-owner-release-function owner)))
                (funcall release owner)
                (setf (tts--dispatch-owner-release-function owner) nil))
            ;; Internal metadata release rolls back an interrupted mutation.
            ;; Finish that cleanup before propagating the original exit.
            (when-let* ((release (tts--dispatch-owner-release-function owner)))
              (funcall release owner)
              (setf (tts--dispatch-owner-release-function owner) nil)))
        (unwind-protect
            (unwind-protect (tts--dispatch-release-reservation owner)
              (tts--dispatch-release-reservation owner))
          (unless (or (tts--dispatch-owner-reserved owner)
                      (tts--dispatch-owner-release-function owner))
            (remhash id tts--prepared-owners)
            (remhash id tts--tracked-dispatches)
            (remhash id tts--marker-dispatches)
            (remhash id tts--dispatch-lifecycles)
            (setf (tts--dispatch-owner-released owner) t)))))))

(defun tts--dispatch-discard-notifications (owner)
  "Remove queued notifications for OWNER and release their budget."
  (let* ((process (tts--dispatch-owner-process owner))
         (queue (process-get process 'tts--dispatch-notifications))
         kept (bytes 0) (count 0))
    (dolist (item queue)
      (unless (eq owner (aref item 0))
        (push item kept)
        (cl-incf bytes (aref item 3))
        (cl-incf count)))
    (setq kept (nreverse kept))
    (process-put process 'tts--dispatch-notifications kept)
    (process-put process 'tts--dispatch-notification-tail (last kept))
    (process-put process 'tts--dispatch-notification-count count)
    (process-put process 'tts--dispatch-notification-bytes bytes)))

(defun tts--dispatch-abandon (owner &optional status)
  "Irrevocably retire OWNER, retaining diagnostics with terminal STATUS."
  (unwind-protect
      (unless (tts--dispatch-owner-retired owner)
        (setf (tts--dispatch-owner-retired owner) t)
        (tts--finish-dispatch-lifecycle
         (tts--dispatch-owner-process owner) (tts--dispatch-owner-id owner)
         (or status 'failed)))
    (unwind-protect (tts--dispatch-discard-notifications owner)
      (tts--dispatch-release owner))))

(defun tts--dispatch-schedule-drain (process)
  "Arrange one asynchronous notification drain for PROCESS."
  (when (and (process-get process 'tts--dispatch-notifications)
             (not (process-get process 'tts--dispatch-notification-timer)))
    (process-put process 'tts--dispatch-notification-timer
                 (run-at-time 0.01 nil #'tts--dispatch-drain process))))

(defun tts--dispatch-enqueue (owner function arguments &optional terminal)
  "Queue FUNCTION with ARGUMENTS for OWNER, reserving TERMINAL separately."
  (let* ((process (tts--dispatch-owner-process owner))
         (print-circle t) (print-length nil) (print-level nil)
         (bytes (if terminal 0 (string-bytes (prin1-to-string arguments))))
         (used (or (process-get process 'tts--dispatch-notification-bytes) 0))
         (count (or (process-get process 'tts--dispatch-notification-count) 0)))
    (if (and (not terminal)
             (or (>= count tts--dispatch-notification-limit)
                 (> (+ used bytes) tts--dispatch-notification-byte-limit)))
        (progn
          (tts--dispatch-discard-notifications owner)
          (setf (tts--dispatch-owner-terminal owner) 'failed
                (tts--dispatch-owner-tracking-failed owner) t)
          (process-put process 'tts--dispatch-tracking-error
                       (list :reason 'notification-overflow :dispatch-id (tts--dispatch-owner-id owner)))
          (tts--finish-dispatch-lifecycle process (tts--dispatch-owner-id owner) 'failed)
          (tts--dispatch-enqueue owner nil nil t)
          nil)
      (let ((cell (list (vector owner function
                                (tts--dispatch-copy-data arguments) bytes terminal))))
        (if-let* ((tail (process-get process 'tts--dispatch-notification-tail)))
            (setcdr tail cell)
          (process-put process 'tts--dispatch-notifications cell))
        (process-put process 'tts--dispatch-notification-tail cell)
        (process-put process 'tts--dispatch-notification-bytes (+ used bytes))
        (process-put process 'tts--dispatch-notification-count (1+ count)))
      (when (tts--dispatch-owner-published owner)
        (tts--dispatch-schedule-drain process))
      t)))

(defun tts--dispatch-drain (process)
  "Deliver ready PROCESS notifications outside submission and filter stacks."
  (when-let* ((timer (process-get process 'tts--dispatch-notification-timer)))
    (cancel-timer timer))
  (process-put process 'tts--dispatch-notification-timer nil)
  (if (or (> tts--dispatch-call-depth 0) (> emacsvox-aural--submission-depth 0)
          emacsvox-aural--delivery-transaction-active-p tts--dispatch-drain-active
          (> tts--input-drain-depth 0)
          (process-get process 'tts--input-draining)
          (process-get process 'omnivox--input-draining))
      (tts--dispatch-schedule-drain process)
    (let ((tts--dispatch-drain-active t) waiting)
      (unwind-protect
          (while (and (not waiting) (process-get process 'tts--dispatch-notifications))
            (let* ((queue (process-get process 'tts--dispatch-notifications))
                   (item (car queue)) (owner (aref item 0)))
              (cond
               ((and (not (tts--dispatch-owner-retired owner))
                     (not (tts--dispatch-owner-published owner)))
                (setq waiting t))
               (t
                (process-put process 'tts--dispatch-notifications (cdr queue))
                (unless (cdr queue)
                  (process-put process 'tts--dispatch-notification-tail nil))
                (process-put process 'tts--dispatch-notification-count
                             (1- (process-get process 'tts--dispatch-notification-count)))
                (process-put process 'tts--dispatch-notification-bytes
                             (- (process-get process 'tts--dispatch-notification-bytes)
                                (aref item 3)))
                (unless (and (equal (tts--dispatch-owner-generation owner)
                                    (process-get process 'tts--speech-process-generation))
                             (equal (tts--dispatch-owner-epoch owner)
                                    (or (process-get process 'tts--dispatch-cancellation-epoch) 0)))
                  (tts--dispatch-abandon owner 'cancelled))
                (unless (tts--dispatch-owner-retired owner)
                  (if (aref item 4)
                      (progn
                        (tts--dispatch-release owner)
                        (when-let* ((callback (tts--dispatch-owner-completion owner)))
                          (tts--call-tracked-dispatch-callback
                           callback (tts--dispatch-owner-id owner)
                           (tts--dispatch-owner-terminal owner))))
                    (condition-case error-data
                        (apply #'emacsvox-aural--call-independent-callback
                               (aref item 1) (aref item 2))
                      (error (message "Marker speech callback failed: %s"
                                      (error-message-string error-data))))))))))
        (unless waiting (tts--dispatch-schedule-drain process))))))

(defun tts--dispatch-publish (owner)
  "Publish successfully written OWNER without reopening terminal tracking."
  (let ((process (tts--dispatch-owner-process owner)))
    (when (and (eq (tts--dispatch-owner-state owner) 'sent)
               (not (tts--dispatch-owner-retired owner))
               (not (tts--dispatch-owner-tracking-failed owner))
               (process-live-p process)
               (equal (tts--dispatch-owner-epoch owner)
                      (or (process-get process 'tts--dispatch-cancellation-epoch) 0)))
      (setf (tts--dispatch-owner-published owner) t)
      (when emacsvox-aural--submission-failure-cleanups
        (push (lambda () (tts--dispatch-abandon owner))
              (cdr emacsvox-aural--submission-failure-cleanups)))
      (tts--dispatch-schedule-drain process)
      t)))

(defun tts--dispatch-write-packet (process command owners &optional description)
  "Arm OWNERS and send COMMAND to PROCESS once, retaining the write outcome."
  (let ((tts--dispatch-call-depth (1+ tts--dispatch-call-depth))
        complete)
    (unwind-protect
        (progn
          (tts--preparation-check)
          (dolist (owner owners) (tts--dispatch-arm owner))
          (tts--preparation-check)
          (when (cl-some #'tts--dispatch-owner-retired owners)
            (signal 'tts--preparation-cancelled nil))
          (tts-queue--send process command description nil (tts--preparation-output-guard process))
          (setq complete t)
          (dolist (owner owners)
            (setf (tts--dispatch-owner-state owner) 'sent
                  (tts--dispatch-owner-write-ended-at owner) (float-time))
            (tts--diagnostic-log-dispatch-event
             'dispatch-sent :submission-id (tts--dispatch-owner-submission-id owner)
             :dispatch-id (tts--dispatch-owner-id owner)
             :process-name (process-name process)
             :process-generation (tts--dispatch-owner-generation owner)
             :write-started-at (tts--dispatch-owner-write-started-at owner)
             :write-ended-at (tts--dispatch-owner-write-ended-at owner)
             :server-program tts-program)))
      (unless complete
        (dolist (owner owners) (tts--dispatch-abandon owner))))))

(defun tts--dispatch-command (owner command)
  "Capture OWNER and COMMAND or send and publish them directly."
  (if emacsvox-aural--delivery-transaction-active-p
      (progn
        (emacsvox-aural--capture-delivery-entry
         (emacsvox-aural--make-delivery-entry
          :process (tts--dispatch-owner-process owner)
          :command command :owners (list owner)
          :queue-description (tts-queue--describe command 'clear)
          :kind (if (eq tts--dispatch-origin 'ordinary)
                    'ordinary-dispatch 'explicit-dispatch)))
        (tts--dispatch-owner-id owner))
    (unwind-protect
        (progn
          (tts--dispatch-write-packet
           (tts--dispatch-owner-process owner) command (list owner)
           (tts-queue--describe command 'clear))
          (when (tts--dispatch-publish owner) (tts--dispatch-owner-id owner)))
      (unless (tts--dispatch-owner-published owner)
        (tts--dispatch-abandon owner)))))

(defun tts--diagnostic-log-dispatch-event (event &rest fields)
  "Append diagnostic dispatch EVENT and FIELDS when logging is available."
  (when (fboundp 'emacsvox-aural-diagnostic-log-event)
    (condition-case error-data
        (apply #'emacsvox-aural-diagnostic-log-event event fields)
      (error
       (message "Speech lifecycle diagnostic failed: %s"
                (error-message-string error-data))))))

(defun tts--register-dispatch-lifecycle
    (identifier process submission-id)
  "Record successful send of dispatch IDENTIFIER to PROCESS.
SUBMISSION-ID identifies the native aural submission when one owns it."
  (let* ((submitted-at (float-time))
         (lifecycle
          (tts--dispatch-lifecycle-create
           :process process
           :submission-id submission-id
           :submitted-at submitted-at)))
    (puthash identifier lifecycle tts--dispatch-lifecycles)
    (tts--diagnostic-log-dispatch-event
     'dispatch-sent
     :submission-id submission-id
     :dispatch-id identifier
     :process-name (and (processp process) (process-name process))
     :process-generation
     (and
      (processp process)
      (process-get process 'tts--speech-process-generation))
     :server-program tts-program)
    lifecycle))

(defun tts--observe-dispatch-source (process identifier event)
  "Record first source-consumption EVENT for IDENTIFIER owned by PROCESS."
  (when-let* ((lifecycle (gethash identifier tts--dispatch-lifecycles)))
    (when
        (and
         (eq process (tts--dispatch-lifecycle-process lifecycle))
         (equal (plist-get event :type) "utterance_started")
         (null (tts--dispatch-lifecycle-source-observed-at lifecycle)))
      (let ((observed-at (float-time)))
        (setf
         (tts--dispatch-lifecycle-source-observed-at lifecycle)
         observed-at)
        (tts--diagnostic-log-dispatch-event
         'mixer-source-observed
         :submission-id (tts--dispatch-lifecycle-submission-id lifecycle)
         :dispatch-id identifier
         :dispatch-elapsed-ms
         (* 1000.0
            (- observed-at
               (tts--dispatch-lifecycle-submitted-at lifecycle)))
         :utterance-id (plist-get event :utterance_id)
         :engine-id (plist-get event :engine_id)
         :actual-voice (plist-get event :actual_voice)
         :logical-voice-id (plist-get event :logical_voice_id))))))

(defun tts--finish-dispatch-lifecycle (process identifier status)
  "Record terminal STATUS for dispatch IDENTIFIER owned by PROCESS."
  (when-let* ((lifecycle (gethash identifier tts--dispatch-lifecycles)))
    (when (eq process (tts--dispatch-lifecycle-process lifecycle))
      (remhash identifier tts--dispatch-lifecycles)
      (let* ((finished-at (float-time))
             (submitted-at
              (tts--dispatch-lifecycle-submitted-at lifecycle))
             (source-at
              (tts--dispatch-lifecycle-source-observed-at lifecycle)))
        (tts--diagnostic-log-dispatch-event
         'playback-terminal-observed
         :submission-id (tts--dispatch-lifecycle-submission-id lifecycle)
         :dispatch-id identifier
         :status status
         :dispatch-elapsed-ms (* 1000.0 (- finished-at submitted-at))
         :onset-elapsed-ms
         (and source-at (* 1000.0 (- source-at submitted-at)))
         :source-to-terminal-ms
         (and source-at (* 1000.0 (- finished-at source-at))))))))

(defvar tts--speech-process-generation 0
  "Sequence distinguishing speech-server process instances.")

(defconst tts--speech-process-generation-property
  'tts--speech-process-generation
  "Process property holding one speech-server generation.")

(defconst tts--speech-process-role-property
  'tts--speech-process-role
  "Process property identifying the main or notification speech stream.")

(defconst tts--speech-process-retiring-property
  'tts--speech-process-retiring
  "Process property set before intentional speech-server retirement.")

(defconst tts--speech-process-exit-handled-property
  'tts--speech-process-exit-handled
  "Process property preventing duplicate terminal sentinel handling.")

(defconst tts--tracked-filter-property 'tts--tracked-original-filter
  "Process property retaining the filter replaced for tracked speech.")

(defconst tts--tracked-fragment-property 'tts--tracked-output-fragment
  "Process property retaining incomplete tracked server output.")

(defun tts--forward-untracked-output (process output)
  "Forward untracked OUTPUT from PROCESS to its original filter."
  (when-let* ((filter (process-get process tts--tracked-filter-property)))
    (unless (eq filter #'tts--speaker-process-filter)
      (funcall filter process output))))

(defun tts-tracked-playback-completion-p (&optional program)
  "Return non-nil when speech-server PROGRAM reports playback completion.
PROGRAM defaults to `tts-program'.  The result describes the server protocol,
not proof that audio reached a physical output device."
  (let ((basename (file-name-nondirectory (or program tts-program ""))))
    (or
     (member basename tts--tracked-playback-completion-programs)
     (and
      (process-live-p tts-speaker-process)
      (process-get
       tts-speaker-process tts--tracked-playback-completion-property)
      (equal
       basename
       (file-name-nondirectory (or tts-program "")))))))

(defun tts--require-tracked-playback-completion ()
  "Signal a clear error unless the active server supports tracked playback."
  (unless (tts-tracked-playback-completion-p)
    (user-error
     "Speech server `%s' cannot report playback completion; tracked reading is unavailable"
     (file-name-nondirectory (or tts-program "unset")))))

(defun tts-marker-playback-events-p ()
  "Return non-nil when the active speech process supports marker events."
  (and
   (process-live-p tts-speaker-process)
   (process-get tts-speaker-process tts--marker-playback-events-property)))

(defun tts--require-marker-playback-events ()
  "Signal a clear error unless the active server supports marker events."
  (unless (tts-marker-playback-events-p)
    (user-error
     "Speech server `%s' does not support marker-aware playback"
     (file-name-nondirectory (or tts-program "unset")))))

(defun tts--dispatch-observing-p (owner)
  "Return non-nil while OWNER can accept new playback evidence."
  (let ((process (tts--dispatch-owner-process owner)))
    (and (memq (tts--dispatch-owner-state owner) '(writing sent))
         (not (tts--dispatch-owner-released owner))
         (not (tts--dispatch-owner-retired owner))
         (not (tts--dispatch-owner-terminal owner))
         (process-live-p process)
         (not (process-get process 'tts--speech-process-retiring))
         (equal (tts--dispatch-owner-generation owner)
                (process-get process 'tts--speech-process-generation))
         (equal (tts--dispatch-owner-epoch owner)
                (or (process-get process 'tts--dispatch-cancellation-epoch) 0)))))

(defun tts--complete-tracked-dispatch (process line)
  "Handle terminal LINE from PROCESS, retaining early owned completion."
  (if (string-match
       (concat "\\`" (regexp-quote tts--tracked-status-prefix)
               " \\([[:digit:]]+\\) \\(completed\\|cancelled\\|failed\\)\\'") line)
      (let* ((id (string-to-number (match-string 1 line)))
             (status (intern (match-string 2 line)))
             (owner (tts--dispatch-owner-for process id)))
        (if (not owner)
            (tts--complete-legacy-tracked-dispatch process line)
          (when (tts--dispatch-observing-p owner)
            (setf (tts--dispatch-owner-terminal owner) status)
            (tts--finish-dispatch-lifecycle process id status)
            (tts--dispatch-enqueue owner nil nil t)))
        t)
    nil))

(defun tts--complete-legacy-tracked-dispatch (process line)
  "Handle tracked status LINE from PROCESS.
Return non-nil when LINE is a tracked status record."
  (when
      (string-match
       (format
        "\\`%s \\([[:digit:]]+\\) \\(completed\\|cancelled\\|failed\\)\\'"
        (regexp-quote tts--tracked-status-prefix))
       line)
    (let* ((identifier (string-to-number (match-string 1 line)))
           (status (intern (match-string 2 line)))
           (entry (gethash identifier tts--tracked-dispatches))
           (marker-entry (gethash identifier tts--marker-dispatches)))
      (tts--finish-dispatch-lifecycle process identifier status)
      (when (and marker-entry
                 (eq process (tts--marker-dispatch-process marker-entry)))
        (remhash identifier tts--marker-dispatches))
      (when (and entry (eq process (car entry)))
        (remhash identifier tts--tracked-dispatches)
        (tts--call-tracked-dispatch-callback
         (cdr entry) identifier status)))
    t))

(defun tts--call-tracked-dispatch-callback (callback identifier status)
  "Call tracked CALLBACK for IDENTIFIER with terminal STATUS safely."
  (condition-case error-data
      (emacsvox-aural--call-independent-callback
       callback identifier status)
    (error
     (message "Tracked speech callback failed: %s"
              (error-message-string error-data)))))

(defun tts--dispatch-playback-marker-event (process event &optional observer)
  "Observe owned PROCESS EVENT immediately and deliver callbacks asynchronously."
  (let* ((id (plist-get event :dispatch_id))
         (owner (and (integerp id) (tts--dispatch-owner-for process id))))
    (if (not owner)
        (unless (or (process-get process 'tts--owns-playback-events)
                    (gethash id tts--prepared-owners))
          (when observer (funcall observer nil))
          (tts--dispatch-legacy-playback-marker-event process event))
      (let ((entry (gethash id tts--marker-dispatches))
            (sequence (plist-get event :sequence)))
        (when (and (tts--dispatch-observing-p owner) (integerp sequence)
                   (> sequence (tts--marker-dispatch-last-sequence entry)))
          (unless (= sequence (1+ (tts--marker-dispatch-last-sequence entry)))
            (process-put process 'tts--marker-sequence-gap
                         (list :dispatch-id id
                               :previous (tts--marker-dispatch-last-sequence entry)
                               :received sequence))
            (tts--dispatch-enqueue
             owner #'message
             (list "Marker dispatch %d skipped from sequence %d to %d"
                   id (tts--marker-dispatch-last-sequence entry) sequence)))
          (setf (tts--marker-dispatch-last-sequence entry) sequence)
          (tts--observe-dispatch-source process id event)
          (when (and observer (tts--dispatch-observing-p owner))
            (funcall observer owner))
          (when-let* (((tts--dispatch-observing-p owner))
                      (callback (tts--dispatch-owner-marker owner)))
            (let* ((action (plist-get event :action_id))
                   (semantic (and action (alist-get action (tts--dispatch-owner-semantics owner)
                                                    nil nil #'equal)))
                   (delivered (if semantic (plist-put (copy-sequence event) :semantic_value semantic)
                                event)))
              (tts--dispatch-enqueue owner callback (list id delivered))))
          t)))))

(defun tts--dispatch-legacy-playback-marker-event (process event)
  "Deliver decoded marker EVENT owned by PROCESS.
Return non-nil when EVENT belongs to a live marker dispatch."
  (let* ((identifier (plist-get event :dispatch_id))
         (sequence (plist-get event :sequence))
         (entry
          (and (integerp identifier)
               (gethash identifier tts--marker-dispatches))))
    (when (integerp identifier)
      (tts--observe-dispatch-source process identifier event))
    (when
        (and
         entry
         (eq process (tts--marker-dispatch-process entry))
         (integerp sequence)
         (> sequence (tts--marker-dispatch-last-sequence entry)))
      (when
          (/= sequence (1+ (tts--marker-dispatch-last-sequence entry)))
        (message
         "Marker dispatch %d skipped from sequence %d to %d"
         identifier
         (tts--marker-dispatch-last-sequence entry)
         sequence))
      (setf (tts--marker-dispatch-last-sequence entry) sequence)
      (condition-case error-data
          (let* ((action-id (plist-get event :action_id))
                 (semantic-value
                  (and
                   (stringp action-id)
                   (alist-get
                    action-id
                    (tts--marker-dispatch-semantic-actions entry)
                    nil nil #'equal)))
                 (delivered
                  (if semantic-value
                      (plist-put
                       (copy-sequence event) :semantic_value semantic-value)
                    event)))
            (funcall
             (tts--marker-dispatch-callback entry) identifier delivered))
        (error
         (message "Marker speech callback failed: %s"
                  (error-message-string error-data))))
      t)))

(defun tts--consume-process-lines (process output fragment busy handler limit)
  "Drain PROCESS OUTPUT through HANDLER using FRAGMENT and BUSY properties.
Retain at most LIMIT bytes between calls; nested input follows existing input."
  (let ((pending (concat (or (process-get process fragment) "") output)))
    (when (> (string-bytes pending) (* 16 1024 1024))
      (process-put process fragment "")
      (tts--cancel-process-tracked-dispatches process 'failed)
      (error "Speech process input queue exceeded its bound"))
    (process-put process fragment pending))
  (unless (process-get process busy)
    (let ((tts--input-drain-depth (1+ tts--input-drain-depth)) complete)
      (process-put process busy t)
      (unwind-protect
          (progn
            (while (string-search "\n" (or (process-get process fragment) ""))
              (let* ((pending (process-get process fragment))
                     (end (string-search "\n" pending))
                     (line (string-trim-right (substring pending 0 end) "\r")))
                ;; Consume before invoking a callback that can accept more input.
                (process-put process fragment (substring pending (1+ end)))
                (if (> (string-bytes line) limit)
                    (error "Speech process output line exceeded its bound")
                  (funcall handler process line))))
            (when (> (string-bytes (or (process-get process fragment) "")) limit)
              (process-put process fragment "")
              (error "Speech process output fragment exceeded its bound"))
            (setq complete t))
        (process-put process busy nil)
        (when (and (not complete) (string-search "\n" (or (process-get process fragment) "")))
          (run-at-time 0.01 nil #'tts--consume-process-lines
                       process "" fragment busy handler limit))))))

(defun tts--speaker-process-filter (process output)
  "Recognize tracked completion records in PROCESS OUTPUT."
  (tts--consume-process-lines
   process output tts--tracked-fragment-property 'tts--input-draining
   (lambda (owner line)
     (unless (tts--complete-tracked-dispatch owner line)
       (tts--forward-untracked-output owner (concat line "\n"))))
   (* 4 1024 1024)))

(defun tts--ensure-tracked-process-filter (process)
  "Install tracked completion filtering on PROCESS."
  (unless (eq (process-filter process) #'tts--speaker-process-filter)
    (process-put process tts--tracked-filter-property (process-filter process))
    (process-put process tts--tracked-fragment-property "")
    (set-process-filter process #'tts--speaker-process-filter)))

(defun tts-cancel-tracked-dispatch (identifier)
  "Forget tracked speech dispatch IDENTIFIER."
  (when-let* ((owner (gethash identifier tts--prepared-owners)))
    (tts--dispatch-abandon owner 'cancelled))
  (when-let* ((entry (gethash identifier tts--marker-dispatches))
              (owner (tts--marker-dispatch-owner entry)))
    (tts--dispatch-abandon owner 'cancelled))
  (when-let* ((lifecycle (gethash identifier tts--dispatch-lifecycles)))
    (tts--finish-dispatch-lifecycle
     (tts--dispatch-lifecycle-process lifecycle) identifier 'cancelled))
  (remhash identifier tts--tracked-dispatches)
  (remhash identifier tts--marker-dispatches))

(defun tts--cancel-process-tracked-dispatches (process status &optional preserved)
  "Retire every tracked dispatch owned by PROCESS with terminal STATUS.

Entries are removed before callbacks run, so reentrant stop and server output
cannot deliver a second terminal result."
  (unless (memq status '(completed cancelled failed))
    (error "Invalid tracked dispatch terminal status: %S" status))
  (tts--preparation-invalidate process preserved)
  (let (prepared)
    (maphash (lambda (_ owner)
               (when (and (eq process (tts--dispatch-owner-process owner))
                          (not (and preserved
                                    (eq preserved (tts--dispatch-owner-preparation owner))
                                    (not (tts--preparation-cancelled preserved)))))
                 (push owner prepared))) tts--prepared-owners)
    (tts--preparation-release-owners prepared))
  (when (processp process)
    (process-put process 'tts--dispatch-cancellation-epoch
                 (1+ (or (process-get process 'tts--dispatch-cancellation-epoch) 0))))
  (let (entries marker-identifiers lifecycle-identifiers)
    (maphash
     (lambda (identifier entry)
       (when (eq process (car entry))
         (let ((owner (tts--dispatch-owner-for process identifier)))
           (when (or (not owner) (tts--dispatch-owner-published owner))
             (push (cons identifier (cdr entry)) entries)))))
     tts--tracked-dispatches)
    (maphash
     (lambda (identifier entry)
       (when (eq process (tts--marker-dispatch-process entry))
         (push identifier marker-identifiers)))
     tts--marker-dispatches)
    (dolist (identifier marker-identifiers)
      (when-let* ((owner (tts--dispatch-owner-for process identifier)))
        (tts--dispatch-abandon owner status))
      (remhash identifier tts--marker-dispatches))
    (dolist (entry entries)
      (remhash (car entry) tts--tracked-dispatches))
    (maphash
     (lambda (identifier lifecycle)
       (when (eq process (tts--dispatch-lifecycle-process lifecycle))
         (push identifier lifecycle-identifiers)))
     tts--dispatch-lifecycles)
    (dolist (identifier lifecycle-identifiers)
      (tts--finish-dispatch-lifecycle process identifier status))
    (dolist (entry (nreverse entries))
      (tts--call-tracked-dispatch-callback
       (cdr entry) (car entry) status))))

(defun tts--speech-process-terminal-p (process)
  "Return non-nil when PROCESS has reached a terminal status."
  (memq (process-status process) '(exit signal closed failed)))

(defun tts--speech-process-failure (process event)
  "Return a data-only failure record for PROCESS and sentinel EVENT."
  (list
   :time (current-time)
   :reason 'speech-process-exited
   :process-name (process-name process)
   :process-role
   (process-get process tts--speech-process-role-property)
   :process-generation
   (process-get process tts--speech-process-generation-property)
   :process-status (process-status process)
   :exit-status (process-exit-status process)
   :event (string-trim event)))

(defun tts--speech-process-sentinel (process event)
  "Retire runtime state when speech PROCESS exits with EVENT."
  (when
      (and
       (tts--speech-process-terminal-p process)
       (not
        (process-get process tts--speech-process-exit-handled-property)))
    (process-put process tts--speech-process-exit-handled-property t)
    (unless
        (process-get process tts--speech-process-retiring-property)
      (let ((current
             (or
              (eq process tts-speaker-process)
              (eq process tts-notify-process)))
            (failure (tts--speech-process-failure process event)))
        (tts-queue--retire process)
        (emacsvox-aural-cancel-pending-deliveries process)
        (when-let* ((fragment
                     (process-get process tts--tracked-fragment-property)))
          (unless (string-empty-p fragment)
            (tts--forward-untracked-output process fragment)))
        (process-put process tts--tracked-fragment-property nil)
        (tts--cancel-process-tracked-dispatches process 'failed)
        (when (eq process tts-speaker-process)
          (setq tts-speaker-process nil))
        (when (eq process tts-notify-process)
          (setq tts-notify-process nil))
        (when current
          (condition-case error-data
              (emacsvox-aural--call-independent-callback
               #'run-hook-with-args 'tts-stopped-hook process)
            (error
             (message "Speech stopped hook failed: %s"
                      (error-message-string error-data)))))
        (setq emacsvox-aural-last-delivery-failure failure)
        (condition-case error-data
            (run-hook-with-args
             'emacsvox-aural-delivery-failed-hook failure)
          (error
           (message "Speech failure hook failed: %s"
                    (error-message-string error-data))))
        (message
         "Emacsvox speech server %s exited: %s"
         (process-name process)
         (let ((description (plist-get failure :event)))
           (if (string-empty-p description)
               (plist-get failure :process-status)
             description)))))))

(defun tts--interrupt-process (process &optional notifications preserved preview)
  "Stop PROCESS and retire callbacks that can no longer complete.

When NOTIFICATIONS is non-nil, also stop the notification speech stream.
Pending aural deliveries are owned by the caller because replacement and
urgent policies cancel different scopes.  Private PREVIEW is a one-use
startup guard, Stop observer and operation identity.  Only this invocation
excludes that observer."
  (let* ((listener (and (processp process) (process-get process 'tts--interrupt-listener)))
         (completion (when (and listener (not (eq (car listener) (nth 2 preview))))
                       (funcall (cadr listener))))
         completed)
    (unwind-protect
        (progn
          (when
              (and notifications
                   (process-live-p tts-notify-process)
                   (not (eq process tts-notify-process)))
            (tts-notify-stop))
          ;; Retirement owns these callbacks already.  A stopped observer may itself
          ;; call `tts-stop', so do not enter the same hook again for that owner.
          (unless (and (processp process)
                       (process-get process tts--speech-process-retiring-property))
            (tts--preparation-invalidate process preserved)
            (when (processp process)
              (process-put process 'tts--dispatch-cancellation-epoch
                           (1+ (or (process-get process 'tts--dispatch-cancellation-epoch) 0))))
            (unwind-protect
                (when (process-live-p process)
                  (let* ((guard (or (car preview)
                                    (and preserved (tts--preparation-queue-guard preserved))))
                         (receipt (emacsvox-aural--delivery-send-typed
                                   process "s\n" 'clear 'stop guard t)))
                    (when guard (tts-queue--advance-stop guard receipt))))
              (tts--cancel-process-tracked-dispatches process 'cancelled preserved))
            (emacsvox-aural--call-independent-callback
             #'run-hook-wrapped 'tts-stopped-hook
             (lambda (function owner)
               ;; A reentrant public Stop calls this function without PREVIEW, so it
               ;; invokes every observer even while this outer invocation is running.
               (unless (eq function (cadr preview)) (funcall function owner))
               nil)
             process))
          (setq completed t))
      (when completion (funcall completion completed)))))

(defun tts--retire-process (process)
  "Cancel state owned by PROCESS, stop it, and delete it.

This is the primary speech-process lifecycle boundary.  Pending replaceable
delivery, tracked completion callbacks, and clients of `tts-stopped-hook' are
retired before PROCESS can become an unreachable dead owner.  Ordinary cleanup
errors are logged without preventing other cleanup or recovery.  A quit is
deferred until cleanup finishes, then re-signalled.  Repeated retirement of
the same owner is harmless."
  (when (and (processp process)
             (not (process-get process tts--speech-process-retiring-property)))
    (tts--preparation-invalidate process)
    (process-put process tts--speech-process-retiring-property t)
    (tts-queue--retire process)
    ;; Logging during teardown must not try to speak through the old server.
    ;; Diagnostics remain in the echo area and *Messages* after recovery.
    (let ((emacsvox-speak-messages nil)
          failures quit-data)
      (cl-labels
          ((attempt (stage function &rest arguments)
             (condition-case error-data
                 (apply function arguments)
               (error
                (push (format "%s: %s" stage (error-message-string error-data))
                      failures))
               (quit (setq quit-data error-data)))))
        (unwind-protect
            (progn
              (attempt "pending deliveries"
                       #'emacsvox-aural-cancel-pending-deliveries process)
              (when (process-live-p process)
                (attempt "stop command"
                         #'emacsvox-aural-delivery-send process "s\n" 'stop))
              (attempt "tracked callbacks"
                       #'tts--cancel-process-tracked-dispatches process 'cancelled)
              (emacsvox-aural--call-independent-callback
               #'run-hook-wrapped 'tts-stopped-hook
               (lambda (function owner)
                 (attempt
                  (if (symbolp function)
                      (format "stopped hook %s" function)
                    "stopped hook (anonymous)")
                  function owner)
                 nil)
               process))
          (delete-process process)))
      (dolist (failure (nreverse failures))
        (message "Speech server %s retired with cleanup error in %s"
                 (process-name process) failure))
      (when quit-data (signal (car quit-data) (cdr quit-data))))))

(defun tts--call-with-dispatch-preparation (function)
  "Call FUNCTION in the enclosing capture scope or a fresh direct scope."
  (if emacsvox-aural--delivery-transaction-active-p
      (funcall function)
    (tts--call-with-preparation tts-speaker-process function)))

(defun tts--protocol-dispatch-tracked (callback)
  "Dispatch queued speech and call CALLBACK with its terminal server status.
CALLBACK receives the dispatch identifier and either `completed', `cancelled',
or `failed'.  Return the identifier allocated to this dispatch."
  (unless (functionp callback)
    (signal 'wrong-type-argument (list 'functionp callback)))
  (tts--require-tracked-playback-completion)
  (tts--ensure-tracked-process-filter tts-speaker-process)
  (tts--call-with-dispatch-preparation
   (lambda ()
     (let ((owner (tts--dispatch-new-owner
                   nil callback nil emacsvox-aural--delivery-transaction-active-p)))
       (tts--dispatch-command
        owner (format "emacsvox_tracked_dispatch %d\n" (tts--dispatch-owner-id owner)))))))

(defun tts--protocol-dispatch-marked (marker-callback completion-callback)
  "Dispatch queued speech with marker and terminal callbacks.
MARKER-CALLBACK receives the dispatch identifier and a decoded event plist.
COMPLETION-CALLBACK receives the identifier and terminal status."
  (unless (functionp marker-callback)
    (signal 'wrong-type-argument (list 'functionp marker-callback)))
  (unless (functionp completion-callback)
    (signal 'wrong-type-argument (list 'functionp completion-callback)))
  (tts--require-marker-playback-events)
  (tts--require-tracked-playback-completion)
  (tts--ensure-tracked-process-filter tts-speaker-process)
  (tts--call-with-dispatch-preparation
   (lambda ()
     (let ((owner (tts--dispatch-new-owner
                   marker-callback completion-callback nil
                   emacsvox-aural--delivery-transaction-active-p)))
       (tts--dispatch-command
        owner (format "emacsvox_marker_dispatch %d\n" (tts--dispatch-owner-id owner)))))))

(defun tts--prepare-structured-dispatch
    (marker-callback completion-callback semantic-actions)
  "Return a structured dispatch ID, publication function and inactive owner.

SEMANTIC-ACTIONS maps opaque wire IDs to richer client values.  The returned
effect must run only after the complete timeline command has been sent."
  (when (and marker-callback (not (functionp marker-callback)))
    (signal 'wrong-type-argument (list 'functionp marker-callback)))
  (when (and completion-callback (not (functionp completion-callback)))
    (signal 'wrong-type-argument (list 'functionp completion-callback)))
  (tts--require-tracked-playback-completion)
  (when marker-callback (tts--require-marker-playback-events))
  (tts--ensure-tracked-process-filter tts-speaker-process)
  (let ((owner (tts--dispatch-new-owner marker-callback completion-callback semantic-actions)))
    (list (tts--dispatch-owner-id owner)
          (lambda () (tts--dispatch-publish owner)) owner)))

(provide 'tts-lifecycle)

;;; tts-lifecycle.el ends here
