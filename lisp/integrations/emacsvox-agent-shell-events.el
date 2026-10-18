;;; emacsvox-agent-shell-events.el --- Agent Shell response and event speech  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop agent-shell
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

;; Capture rendered response sections and translate lifecycle, permission and
;; tool events into speech.  This module retains the event subscriptions,
;; timers, marker snapshots and caches with their existing cleanup functions.
;; The facade owns shared feedback policy and calls setup and teardown in the
;; established order.  Loading these definitions does not subscribe buffers.
;; Load through `emacsvox-agent-shell'.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-render)
(require 'emacsvox-agent-shell-navigation)

(declare-function emacsvox-agent-shell--session-focused-p
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--effective-speech-level
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--speech-level-at-least-p
                  "emacsvox-agent-shell" (level &optional buffer))
(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--permission-field-text
                  "emacsvox-agent-shell" (text label))
(declare-function emacsvox-agent-shell--notify-background
                  "emacsvox-agent-shell" (facts occasion icon text &optional separator))
(declare-function emacsvox-agent-shell--deliver-announcement
                  "emacsvox-agent-shell" (facts occasion icon text &optional delivery-policy))
(declare-function emacsvox-agent-shell--submit-icon-feedback
                  "emacsvox-agent-shell" (facts occasion icon))
(declare-function emacsvox-agent-shell--submit-automatic-text-feedback
                  "emacsvox-agent-shell" (text facts occasion
          &optional icon inspection-hint delivery-policy replacement-key))
(declare-function emacsvox-agent-shell--speak-content
                  "emacsvox-agent-shell" (content block-type))
(declare-function emacsvox-agent-shell--question-event
                  "emacsvox-agent-shell-interaction" (event))
(declare-function emacsvox-agent-shell--notify-event
                  "emacsvox-agent-shell" (text facts &optional icon occasion))
(declare-function emacsvox-agent-shell--interaction-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--initialized-p
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--config-options
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--observe-config-options
                  "emacsvox-agent-shell" (options announce))
(declare-function emacsvox-agent-shell--queue-feedback
                  "emacsvox-agent-shell" (state))
(defvar emacsvox-agent-shell-tool-output-verbosity)
(defvar emacsvox-agent-shell-speak-permissions)
(defvar emacsvox-agent-shell-speak-tool-calls)
(defvar emacsvox-agent-shell-signal-processing)
(defvar emacsvox-agent-shell-processing-start-icon)
(defvar emacsvox-agent-shell-processing-end-icon)
(defvar emacsvox-agent-shell--push-active-p)
(defvar emacsvox-agent-shell--queue-start-count)
(defvar emacsvox-agent-shell-speech-delay)
(declare-function agent-shell-status "agent-shell" t)
(declare-function agent-shell-subscribe-to "agent-shell" t)
(declare-function agent-shell-unsubscribe "agent-shell" t)

(defvar emacsvox-agent-shell--pending-speech-timer nil
  "Legacy timer left by pause-based response speech.
New response capture uses semantic turn completion and never creates this
timer.  It remains buffer-local so reloading or disabling support can cancel
a timer created by an older loaded version.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-speech-timer)

(defvar emacsvox-agent-shell--pending-speech-qualified-ids nil
  "List of rendered turn-content IDs pending speech, in arrival order.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-speech-qualified-ids)

(defvar emacsvox-agent-shell--pending-bodies nil
  "Legacy hash table mapping qualified ID to rendered turn-content body.
Current response capture keeps buffer markers instead, but this table remains
available so a timer created by an older loaded version can finish safely.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-bodies)

(defvar emacsvox-agent-shell--pending-section-markers nil
  "Hash table mapping pending qualified IDs to body marker pairs.")

(make-variable-buffer-local 'emacsvox-agent-shell--pending-section-markers)

(defvar-local emacsvox-agent-shell--response-turn-active-p nil
  "Non-nil while a submitted agent turn can produce semantic sections.")

(defvar-local emacsvox-agent-shell--last-completed-answer nil
  "Most recent answer captured at an authoritative completed-turn boundary.")

(defvar-local emacsvox-agent-shell--latest-turn-outcome nil
  "Observed latest turn state: `active', `completed', `failed', or nil.")

(defvar-local emacsvox-agent-shell--setting-warning-cache nil
  "Hash table mapping announced Agent Shell setting-warning IDs to digests.")

(defvar-local emacsvox-agent-shell--out-of-turn-speech-timer nil
  "Timer coalescing the latest rendered out-of-turn message updates.")

(defvar-local emacsvox-agent-shell--out-of-turn-pending-ids nil
  "Out-of-turn message IDs awaiting delivery, in arrival order.")

(defvar-local emacsvox-agent-shell--out-of-turn-bodies nil
  "Legacy hash table of rendered out-of-turn bodies by qualified ID.")

(defvar-local emacsvox-agent-shell--out-of-turn-section-markers nil
  "Hash table mapping out-of-turn qualified IDs to body marker pairs.")

(defvar-local emacsvox-agent-shell--out-of-turn-delivered-ids nil
  "Hash table mapping recent out-of-turn IDs to delivered body digests.")

(defvar-local emacsvox-agent-shell--out-of-turn-delivered-order nil
  "Recent out-of-turn delivered IDs in most-recently-used order.")

(defvar-local emacsvox-agent-shell--permission-subscription nil
  "Subscription token for permission request events in this shell.")

(defvar-local emacsvox-agent-shell--permission-response-subscription nil
  "Subscription token for permission response events in this shell.")

(defvar-local emacsvox-agent-shell--permission-action-cache nil
  "Hash table mapping pending permission requests to normalized actions.")

(defvar-local emacsvox-agent-shell--lifecycle-subscription nil
  "Subscription token for lifecycle events in this shell.")

(defvar-local emacsvox-agent-shell--tool-call-subscription nil
  "Subscription token for tool call update events in this shell.")

(defvar-local emacsvox-agent-shell--tool-call-status-cache nil
  "Hash table mapping tool call IDs to their last announced status.")

(defvar-local emacsvox-agent-shell--tool-output-cache nil
  "Digests of terminal tool output already observed in this turn.")

(defvar-local emacsvox-agent-shell--permission-detail-cache nil
  "Snapshots of operations whose permissions are still pending.")

(defvar emacsvox-agent-shell--rendering-tool-update nil
  "Dynamically scoped public event and renderer output for one tool update.")

(defconst emacsvox-agent-shell--out-of-turn-version-limit 64
  "Maximum delivered out-of-turn message versions retained per shell.")

(defun emacsvox-agent-shell--should-speak-p (buffer)
  "Determine if content should be spoken for BUFFER."
  (with-current-buffer buffer
    (and (bound-and-true-p emacsvox-comint-autospeak)
         (emacsvox-agent-shell--speech-level-at-least-p
          'response buffer))))

(defun emacsvox-agent-shell--release-section-marker-pair (pair)
  "Detach the start and end markers in section marker PAIR."
  (when (markerp (car-safe pair))
    (set-marker (car pair) nil))
  (when (markerp (cdr-safe pair))
    (set-marker (cdr pair) nil)))

(defun emacsvox-agent-shell--clear-section-markers (table)
  "Detach and remove every marker pair in hash TABLE."
  (when (hash-table-p table)
    (maphash
     (lambda (_qualified-id pair)
       (emacsvox-agent-shell--release-section-marker-pair pair))
     table)
    (clrhash table)))

(defun emacsvox-agent-shell--forget-section-markers
    (table qualified-id)
  "Detach and remove QUALIFIED-ID's marker pair from hash TABLE."
  (when (hash-table-p table)
    (when-let* ((pair (gethash qualified-id table)))
      (emacsvox-agent-shell--release-section-marker-pair pair))
    (remhash qualified-id table)))

(defun emacsvox-agent-shell--remember-section-markers
    (table qualified-id body-start body-end)
  "Update TABLE's body markers for QUALIFIED-ID to BODY-START and BODY-END.
The end marker advances when text is inserted at the boundary, so a streamed
append remains covered even before the next section-hook invocation."
  (let ((pair (gethash qualified-id table)))
    (if (and (markerp (car-safe pair))
             (markerp (cdr-safe pair)))
        (progn
          (set-marker (car pair) body-start (current-buffer))
          (set-marker (cdr pair) body-end (current-buffer)))
      (setq pair
            (cons (copy-marker body-start)
                  (copy-marker body-end t)))
      (puthash qualified-id pair table))
    pair))

(defun emacsvox-agent-shell--section-marker-snapshot
    (qualified-id pair)
  "Return QUALIFIED-ID and final rendered body represented by marker PAIR."
  (when-let* ((start-marker (car-safe pair))
              (end-marker (cdr-safe pair))
              ((markerp start-marker))
              ((markerp end-marker))
              ((eq (marker-buffer start-marker) (current-buffer)))
              ((eq (marker-buffer end-marker) (current-buffer)))
              (body-start (marker-position start-marker))
              (body-end (marker-position end-marker))
              ((< body-start body-end))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              ((equal qualified-id (map-elt state :qualified-id)))
              (body
               (string-trim
                (buffer-substring body-start body-end)))
              ((not (string-empty-p body))))
    (cons qualified-id body)))

(defun emacsvox-agent-shell--cancel-pending-speech ()
  "Cancel and discard response speech pending in the current shell."
  (when (timerp emacsvox-agent-shell--pending-speech-timer)
    (cancel-timer emacsvox-agent-shell--pending-speech-timer))
  (setq emacsvox-agent-shell--pending-speech-timer nil
        emacsvox-agent-shell--pending-speech-qualified-ids nil)
  (emacsvox-agent-shell--clear-section-markers
   emacsvox-agent-shell--pending-section-markers)
  (setq emacsvox-agent-shell--pending-section-markers nil)
  (when (hash-table-p emacsvox-agent-shell--pending-bodies)
    (clrhash emacsvox-agent-shell--pending-bodies)))

(defun emacsvox-agent-shell--response-section-snapshot (range)
  "Return qualified ID and rendered turn content represented by section RANGE.
Agent responses, thoughts, and plans are collected; other sections return nil.
Agent-shell calls its experimental section hook after Markdown rendering, so
the body retains semantic faces and omits markup that is no longer displayed."
  (when-let* ((body-start (map-nested-elt range '(:body :start)))
              ((< body-start (point-max)))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              (qualified-id (map-elt state :qualified-id))
              (semantic-type
               (emacsvox-agent-shell--semantic-block-type
                qualified-id state body-start))
              ((memq semantic-type '(agent-response thought plan)))
              (body-end
               (or (next-single-property-change
                    body-start 'agent-shell-ui-section nil (point-max))
                   (point-max)))
              ((< body-start body-end))
              (body
               (string-trim
                (buffer-substring body-start body-end)))
              ((not (string-empty-p body))))
    (cons qualified-id body)))

(defun emacsvox-agent-shell--out-of-turn-message-id-p (qualified-id)
  "Return non-nil when QUALIFIED-ID is an explicit out-of-turn agent message."
  (and (stringp qualified-id)
       (string-prefix-p "out-of-turn-" qualified-id)
       (string-suffix-p "agent_message_chunk" qualified-id)))

(defun emacsvox-agent-shell--deliver-out-of-turn-body (body)
  "Deliver rendered out-of-turn agent message BODY according to focus policy."
  (when (bound-and-true-p emacsvox-comint-autospeak)
    (let ((facts '(:role agent-response))
          (occasion 'notification)
          (focused (emacsvox-agent-shell--session-focused-p)))
      (cond
       ((and focused
             (emacsvox-agent-shell--speech-level-at-least-p 'response))
        (emacsvox-agent-shell--submit-automatic-text-feedback
         (concat "Agent update: " body) facts occasion 'item
         "Inspect the Agent Shell buffer for the complete update."))
       ((and (not focused)
             (emacsvox-agent-shell--speech-level-at-least-p 'notify))
        (emacsvox-agent-shell--notify-background
         facts occasion 'item "Agent update available."))))))

(defun emacsvox-agent-shell--out-of-turn-body-changed-p
    (qualified-id body)
  "Remember QUALIFIED-ID's BODY version and return non-nil when it changed."
  (unless (hash-table-p emacsvox-agent-shell--out-of-turn-delivered-ids)
    (setq emacsvox-agent-shell--out-of-turn-delivered-ids
          (make-hash-table :test #'equal)))
  ;; A cache created by the previous implementation contains permanent t
  ;; sentinels but has no LRU order.  Drop it once so live reload cannot retain
  ;; unbounded legacy IDs or suppress the next changed snapshot.
  (when (and (null emacsvox-agent-shell--out-of-turn-delivered-order)
             (> (hash-table-count
                 emacsvox-agent-shell--out-of-turn-delivered-ids)
                0))
    (clrhash emacsvox-agent-shell--out-of-turn-delivered-ids))
  (let* ((digest (secure-hash 'sha256 body))
         (changed-p
          (not (equal
                digest
                (gethash
                 qualified-id
                 emacsvox-agent-shell--out-of-turn-delivered-ids)))))
    (puthash qualified-id digest
             emacsvox-agent-shell--out-of-turn-delivered-ids)
    (setq emacsvox-agent-shell--out-of-turn-delivered-order
          (cons
           qualified-id
           (delete qualified-id
                   emacsvox-agent-shell--out-of-turn-delivered-order)))
    (while (> (length emacsvox-agent-shell--out-of-turn-delivered-order)
              emacsvox-agent-shell--out-of-turn-version-limit)
      (let ((evicted
             (car
              (last emacsvox-agent-shell--out-of-turn-delivered-order))))
        (setq emacsvox-agent-shell--out-of-turn-delivered-order
              (butlast
               emacsvox-agent-shell--out-of-turn-delivered-order))
        (remhash evicted
                 emacsvox-agent-shell--out-of-turn-delivered-ids)))
    changed-p))

(defun emacsvox-agent-shell--deliver-out-of-turn-pending (buffer)
  "Deliver changed out-of-turn snapshots and clear pending state for BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq emacsvox-agent-shell--out-of-turn-speech-timer nil)
      (let ((qualified-ids emacsvox-agent-shell--out-of-turn-pending-ids))
        (setq emacsvox-agent-shell--out-of-turn-pending-ids nil)
        (dolist (qualified-id qualified-ids)
          (when-let* ((body
                       (or
                        (when-let*
                            ((pair
                              (and
                               (hash-table-p
                                emacsvox-agent-shell--out-of-turn-section-markers)
                               (gethash
                                qualified-id
                                emacsvox-agent-shell--out-of-turn-section-markers)))
                             (snapshot
                              (emacsvox-agent-shell--section-marker-snapshot
                               qualified-id pair)))
                          (cdr snapshot))
                        (and
                         (hash-table-p
                          emacsvox-agent-shell--out-of-turn-bodies)
                         (gethash
                          qualified-id
                          emacsvox-agent-shell--out-of-turn-bodies))))
                      ((emacsvox-agent-shell--out-of-turn-body-changed-p
                        qualified-id body)))
            (emacsvox-agent-shell--deliver-out-of-turn-body body))
          (emacsvox-agent-shell--forget-section-markers
           emacsvox-agent-shell--out-of-turn-section-markers
           qualified-id)
          (when (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
            (remhash qualified-id
                     emacsvox-agent-shell--out-of-turn-bodies)))))))

(defun emacsvox-agent-shell--schedule-out-of-turn-delivery (qualified-id)
  "Queue QUALIFIED-ID for coalesced out-of-turn speech."
  (unless (member qualified-id
                  emacsvox-agent-shell--out-of-turn-pending-ids)
    (setq emacsvox-agent-shell--out-of-turn-pending-ids
          (append emacsvox-agent-shell--out-of-turn-pending-ids
                  (list qualified-id))))
  (when (timerp emacsvox-agent-shell--out-of-turn-speech-timer)
    (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer))
  (setq emacsvox-agent-shell--out-of-turn-speech-timer
        (run-with-timer
         (max 0 emacsvox-agent-shell-speech-delay) nil
         #'emacsvox-agent-shell--deliver-out-of-turn-pending
         (current-buffer))))

(defun emacsvox-agent-shell--record-out-of-turn-snapshot (snapshot)
  "Coalesce legacy rendered out-of-turn message SNAPSHOT for speech."
  (let ((qualified-id (car snapshot))
        (body (cdr snapshot)))
    (unless (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
      (setq emacsvox-agent-shell--out-of-turn-bodies
            (make-hash-table :test #'equal)))
    (puthash qualified-id body
             emacsvox-agent-shell--out-of-turn-bodies)
    (emacsvox-agent-shell--schedule-out-of-turn-delivery
     qualified-id)))

(defun emacsvox-agent-shell--record-out-of-turn-section
    (qualified-id body-start body-end)
  "Coalesce QUALIFIED-ID's rendered BODY-START to BODY-END for later speech."
  (unless (hash-table-p
           emacsvox-agent-shell--out-of-turn-section-markers)
    (setq emacsvox-agent-shell--out-of-turn-section-markers
          (make-hash-table :test #'equal)))
  (emacsvox-agent-shell--remember-section-markers
   emacsvox-agent-shell--out-of-turn-section-markers
   qualified-id body-start body-end)
  (emacsvox-agent-shell--schedule-out-of-turn-delivery
   qualified-id))

(defun emacsvox-agent-shell--setting-warning-id-p (qualified-id)
  "Return non-nil when QUALIFIED-ID is a default-setting warning fragment."
  (and
   (stringp qualified-id)
   (string-prefix-p "bootstrapping-" qualified-id)
   (string-match-p "-unapplied\\(?:-\\|\\'\\)" qualified-id)))

(defun emacsvox-agent-shell--setting-warning-text (text)
  "Return the concise Agent Shell setting warning represented by TEXT."
  (when (stringp text)
    (let ((plain (substring-no-properties text)))
      (when (string-match "Warning:[^\n\r]*" plain)
        (string-trim-right (match-string 0 plain) "[ \t│]+")))))

(defun emacsvox-agent-shell--record-setting-warning-section (range)
  "Announce a changed default-setting warning represented by section RANGE."
  (when-let* ((body-start (map-nested-elt range '(:body :start)))
              ((< body-start (point-max)))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (state (get-text-property body-start 'agent-shell-ui-state))
              (qualified-id (map-elt state :qualified-id))
              ((emacsvox-agent-shell--setting-warning-id-p qualified-id))
              (body-end
               (or
                (next-single-property-change
                 body-start 'agent-shell-ui-section nil (point-max))
                (point-max)))
              ((< body-start body-end))
              (warning
               (emacsvox-agent-shell--setting-warning-text
                (buffer-substring body-start body-end)))
              (digest (secure-hash 'sha256 warning)))
    (unless (hash-table-p emacsvox-agent-shell--setting-warning-cache)
      (setq emacsvox-agent-shell--setting-warning-cache
            (make-hash-table :test #'equal)))
    (unless
        (equal
         digest
         (gethash qualified-id emacsvox-agent-shell--setting-warning-cache))
      (puthash qualified-id digest
               emacsvox-agent-shell--setting-warning-cache)
      (when emacsvox-agent-shell-signal-processing
        (emacsvox-agent-shell--deliver-announcement
         (emacsvox-agent-shell--presentation-facts
          'agent-error 'operation-failed)
         'notification 'warn-user warning)))))

(defun emacsvox-agent-shell--record-response-section (range)
  "Remember semantic turn content or an out-of-turn message in RANGE.
Only buffer markers are updated while a response streams.  Rendered text is
copied once, when the turn completes or the out-of-turn debounce timer fires."
  (emacsvox-agent-shell--record-setting-warning-section range)
  (emacsvox-agent-shell--record-tool-output-section range)
  (when-let* ((body-start (map-nested-elt range '(:body :start)))
              ((< body-start (point-max)))
              ((eq (get-text-property body-start 'agent-shell-ui-section)
                   'body))
              (body-end
               (or (next-single-property-change
                    body-start 'agent-shell-ui-section nil (point-max))
                   (point-max)))
              ((< body-start body-end))
              (state
               (get-text-property body-start 'agent-shell-ui-state))
              (qualified-id (map-elt state :qualified-id))
              (semantic-type
               (emacsvox-agent-shell--semantic-block-type
                qualified-id state body-start))
              ((memq semantic-type '(agent-response thought plan)))
              ((or emacsvox-agent-shell--response-turn-active-p
                   (and
                    (eq semantic-type 'agent-response)
                    (emacsvox-agent-shell--out-of-turn-message-id-p
                     qualified-id)))))
    (if (and (eq semantic-type 'agent-response)
             (emacsvox-agent-shell--out-of-turn-message-id-p qualified-id))
        (emacsvox-agent-shell--record-out-of-turn-section
         qualified-id body-start body-end)
      (unless (hash-table-p
               emacsvox-agent-shell--pending-section-markers)
        (setq emacsvox-agent-shell--pending-section-markers
                (make-hash-table :test #'equal)))
      (emacsvox-agent-shell--remember-section-markers
       emacsvox-agent-shell--pending-section-markers
       qualified-id body-start body-end)
      (unless (member qualified-id
                      emacsvox-agent-shell--pending-speech-qualified-ids)
        (setq emacsvox-agent-shell--pending-speech-qualified-ids
              (append emacsvox-agent-shell--pending-speech-qualified-ids
                      (list qualified-id)))))))

(defun emacsvox-agent-shell--out-of-turn-cleanup ()
  "Cancel and clear out-of-turn speech state in the current shell."
  (when (timerp emacsvox-agent-shell--out-of-turn-speech-timer)
    (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer))
  (setq emacsvox-agent-shell--out-of-turn-speech-timer nil
        emacsvox-agent-shell--out-of-turn-pending-ids nil)
  (emacsvox-agent-shell--clear-section-markers
   emacsvox-agent-shell--out-of-turn-section-markers)
  (when (hash-table-p emacsvox-agent-shell--out-of-turn-bodies)
    (clrhash emacsvox-agent-shell--out-of-turn-bodies))
  (when (hash-table-p emacsvox-agent-shell--out-of-turn-delivered-ids)
    (clrhash emacsvox-agent-shell--out-of-turn-delivered-ids))
  (setq emacsvox-agent-shell--out-of-turn-section-markers nil
        emacsvox-agent-shell--out-of-turn-bodies nil
        emacsvox-agent-shell--out-of-turn-delivered-ids nil
        emacsvox-agent-shell--out-of-turn-delivered-order nil))

(defun emacsvox-agent-shell--response-section-setup ()
  "Install semantic rendered turn-content capture in the current shell."
  ;; Cancel a pause timer that may survive reloading an older implementation.
  (when (timerp emacsvox-agent-shell--pending-speech-timer)
    (cancel-timer emacsvox-agent-shell--pending-speech-timer)
    (setq emacsvox-agent-shell--pending-speech-timer nil))
  (add-hook 'agent-shell-section-functions
            #'emacsvox-agent-shell--record-response-section nil t)
  ;; Enabling or reloading support during a live request should begin taking
  ;; complete snapshots on its next rendered chunk.
  (unless emacsvox-agent-shell--response-turn-active-p
    (setq emacsvox-agent-shell--response-turn-active-p
          (condition-case nil
              (memq (agent-shell-status) '(busy blocked))
            (error nil))))
  (when emacsvox-agent-shell--response-turn-active-p
    (setq emacsvox-agent-shell--latest-turn-outcome 'active)))

(defun emacsvox-agent-shell--response-section-cleanup ()
  "Remove semantic rendered turn-content capture from the current shell."
  (remove-hook 'agent-shell-section-functions
               #'emacsvox-agent-shell--record-response-section t)
  (when (hash-table-p emacsvox-agent-shell--setting-warning-cache)
    (clrhash emacsvox-agent-shell--setting-warning-cache))
  (setq emacsvox-agent-shell--response-turn-active-p nil
        emacsvox-agent-shell--last-completed-answer nil
        emacsvox-agent-shell--latest-turn-outcome nil
        emacsvox-agent-shell--setting-warning-cache nil)
  (emacsvox-agent-shell--out-of-turn-cleanup))

(defun emacsvox-agent-shell--begin-response-turn ()
  "Start collecting rendered turn content for a newly submitted turn."
  (emacsvox-agent-shell--cancel-pending-speech)
  (setq emacsvox-agent-shell--response-turn-active-p t
        emacsvox-agent-shell--latest-turn-outcome 'active))

(defun emacsvox-agent-shell--discard-response-turn ()
  "Discard collected turn content and finish the current turn."
  (setq emacsvox-agent-shell--push-active-p nil
        emacsvox-agent-shell--response-turn-active-p nil
        emacsvox-agent-shell--latest-turn-outcome 'failed)
  (emacsvox-agent-shell--cancel-pending-speech))

(defun emacsvox-agent-shell--finish-response-turn ()
  "Speak collected rendered turn content once and finish the current turn."
  (setq emacsvox-agent-shell--response-turn-active-p nil
        emacsvox-agent-shell--latest-turn-outcome 'completed)
  (when-let* ((answer
               (or
                (emacsvox-agent-shell--deliver-pending-blocks
                 (current-buffer)
                 (copy-sequence
                  emacsvox-agent-shell--pending-speech-qualified-ids))
                (emacsvox-agent-shell--rendered-latest-agent-answer))))
    (setq emacsvox-agent-shell--last-completed-answer answer)))

(defun emacsvox-agent-shell--permission-announcement (event)
  "Return a semantic announcement for permission request EVENT."
  (let* ((data (map-elt event :data))
         (tool-call (map-elt data :tool-call))
         (tool-call-id (map-elt data :tool-call-id))
         (title (map-elt tool-call :title))
         (spoken-title
          (emacsvox-agent-shell--permission-field-text
           title "permission description"))
         (spoken-tool-call-id
          (emacsvox-agent-shell--permission-field-text
           tool-call-id "tool identifier"))
         (description
          (cond
           (spoken-title)
           (spoken-tool-call-id (format "Tool %s" spoken-tool-call-id))
           (t "Unknown tool")))
         (choices
          (cl-loop
           for action in (append (map-elt tool-call :permission-actions) nil)
           for option = (map-elt action :option)
           for spoken-option =
           (emacsvox-agent-shell--permission-field-text
            option "permission choice")
           when spoken-option collect spoken-option)))
    (concat
     (format "Permission request. %s." description)
     (when choices
       (concat
        " "
        (mapconcat
         #'identity
         (cl-loop
          for choice in choices
          for index from 1
          collect (format "Choice %d: %s." index choice))
         " "))))))

(defun emacsvox-agent-shell--handle-permission-request (event)
  "Interrupt current speech and announce permission request EVENT."
  (let* ((data (map-elt event :data))
         (tool-call-id (map-elt data :tool-call-id))
         (key (or (map-elt data :request-id)
                  (map-elt data :tool-call-id)))
         (actions (map-nested-elt event '(:data :tool-call
                                                :permission-actions))))
    (when key
      (unless (hash-table-p emacsvox-agent-shell--permission-action-cache)
        (setq emacsvox-agent-shell--permission-action-cache
              (make-hash-table :test #'equal)))
      (puthash key actions emacsvox-agent-shell--permission-action-cache))
    (when tool-call-id
      (unless (hash-table-p emacsvox-agent-shell--permission-detail-cache)
        (setq emacsvox-agent-shell--permission-detail-cache
              (make-hash-table :test #'equal)))
      (puthash tool-call-id
               (cons key (emacsvox-agent-shell--permission-details
                          (map-elt data :tool-call)))
               emacsvox-agent-shell--permission-detail-cache)))
  ;; Rendered turn-content capture ignores permission fragments, so the urgent
  ;; transaction interrupts current speech without discarding turn content
  ;; collected so far.  A later section update refreshes the complete body
  ;; snapshot.
  (when emacsvox-agent-shell-speak-permissions
    (emacsvox-agent-shell--deliver-announcement
     (emacsvox-agent-shell--presentation-facts
      'permission-request 'agent-permission-requested)
     'notification 'warn-user
     (emacsvox-agent-shell--permission-announcement event)
     'urgent)))

(defun emacsvox-agent-shell--handle-permission-response (event)
  "Announce the semantic result of permission response EVENT."
  (let* ((data (map-elt event :data))
         (key (or (map-elt data :request-id)
                  (map-elt data :tool-call-id)))
         (option-id (map-elt data :option-id))
         (cancelled (map-elt data :cancelled))
         (actions (and key
                       (hash-table-p
                        emacsvox-agent-shell--permission-action-cache)
                       (gethash key
                                emacsvox-agent-shell--permission-action-cache)))
         (action (seq-find
                  (lambda (candidate)
                    (equal option-id (map-elt candidate :option-id)))
                  actions))
         (option (map-elt action :option))
         (kind (map-elt action :kind)))
    (when (and key
               (hash-table-p emacsvox-agent-shell--permission-action-cache))
      (remhash key emacsvox-agent-shell--permission-action-cache))
    (when (hash-table-p emacsvox-agent-shell--permission-detail-cache)
      (maphash
       (lambda (id entry)
         (when (or (equal id (map-elt data :tool-call-id))
                   (equal (car entry) key))
           (remhash id emacsvox-agent-shell--permission-detail-cache)))
       emacsvox-agent-shell--permission-detail-cache))
    (when emacsvox-agent-shell-speak-permissions
      (let* ((result
              (cond
               (cancelled 'cancelled)
               ((equal kind "reject_once") 'denied)
               ((member kind '("allow_once" "allow_always")) 'allowed)
               (t 'sent)))
             (facts
              (emacsvox-agent-shell--presentation-facts
               'permission-request 'agent-permission-resolved nil
               (list :agent-permission-result result))))
        (pcase result
          ('cancelled
           (emacsvox-agent-shell--deliver-announcement
            facts 'state-change
            'close-object "Permission cancelled."))
          ('denied
           (emacsvox-agent-shell--deliver-announcement
            facts 'state-change 'close-object
            (format "Permission denied: %s." (or option "Reject"))))
          ('allowed
           (emacsvox-agent-shell--deliver-announcement
            facts 'state-change 'select-object
            (format "Permission granted: %s." (or option "Allow"))))
          (_
           (emacsvox-agent-shell--deliver-announcement
            facts 'state-change
            'select-object "Permission response sent.")))))))

(defun emacsvox-agent-shell--permission-event-setup ()
  "Subscribe the current agent-shell buffer to permission events."
  (unless emacsvox-agent-shell--permission-subscription
    (setq emacsvox-agent-shell--permission-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'permission-request
           :on-event #'emacsvox-agent-shell--handle-permission-request)))
  (unless emacsvox-agent-shell--permission-response-subscription
    (setq emacsvox-agent-shell--permission-response-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'permission-response
           :on-event #'emacsvox-agent-shell--handle-permission-response))))

(defun emacsvox-agent-shell--permission-event-cleanup ()
  "Remove the current buffer's permission subscriptions and cached state."
  (when emacsvox-agent-shell--permission-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--permission-subscription)
    (setq emacsvox-agent-shell--permission-subscription nil))
  (when emacsvox-agent-shell--permission-response-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--permission-response-subscription)
    (setq emacsvox-agent-shell--permission-response-subscription nil))
  (when (hash-table-p emacsvox-agent-shell--permission-action-cache)
    (clrhash emacsvox-agent-shell--permission-action-cache))
  (setq emacsvox-agent-shell--permission-action-cache nil)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--permission-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--permission-event-cleanup t))

(defun emacsvox-agent-shell--speak-agent-error (event)
  "Announce the ACP error described by lifecycle EVENT."
  (let* ((data (map-elt event :data))
         (message (map-elt data :message))
         (code (map-elt data :code))
         (detail
          (cond
           ((and (stringp message) (not (string-empty-p (string-trim message))))
            (string-trim (substring-no-properties message)))
           (code (format "code %s" code))
           (t nil))))
    (emacsvox-agent-shell--deliver-announcement
     (emacsvox-agent-shell--presentation-facts
      'agent-error 'processing-failed)
     'notification 'warn-user
     (if detail
         (format "Agent error: %s" detail)
       "Agent error."))))

(defun emacsvox-agent-shell--speak-turn-completion (event)
  "Announce the outcome described by turn completion EVENT."
  (let ((facts (emacsvox-agent-shell-lifecycle-facts event))
        (stop-reason (map-nested-elt event '(:data :stop-reason))))
    (if (equal stop-reason "end_turn")
        (when (emacsvox-agent-shell--speech-level-at-least-p 'notify)
          (if (emacsvox-agent-shell--session-focused-p)
              (emacsvox-agent-shell--submit-icon-feedback
               facts 'notification emacsvox-agent-shell-processing-end-icon)
            (emacsvox-agent-shell--notify-background
             facts 'notification
             emacsvox-agent-shell-processing-end-icon "finished." " ")))
      (pcase stop-reason
        ("cancelled"
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'close-object "Agent turn cancelled."))
        ("max_tokens"
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'warn-user
          "Agent stopped: maximum token limit reached."))
        ("max_turn_requests"
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'warn-user
          "Agent stopped: request limit reached."))
        ("refusal"
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'warn-user "Agent refused the request."))
        ((pred stringp)
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'warn-user
          (format "Agent stopped: %s."
                  (string-replace "_" " " stop-reason))))
        (_
         (emacsvox-agent-shell--deliver-announcement
          facts 'notification 'warn-user
          "Agent stopped for an unknown reason."))))))

(defun emacsvox-agent-shell-lifecycle-facts (event)
  "Return semantic processing facts for Agent Shell lifecycle EVENT."
  (let* ((event-type (map-elt event :event))
         (stop-reason
          (map-nested-elt event '(:data :stop-reason)))
         (semantic-event
          (pcase event-type
            ((or 'init-started 'input-submitted) 'processing-started)
            ('init-finished 'processing-completed)
            ('turn-complete
             (if (equal stop-reason "end_turn")
                 'processing-completed
               'processing-failed))
            ('error 'processing-failed))))
    (append
     '(:role agent-session)
     (when emacsvox-agent-shell--push-active-p
       '(:agent-turn-origin pushed))
     (when semantic-event (list :events (list semantic-event)))
     (when (eq semantic-event 'processing-started)
       '(:states (processing))))))

(defun emacsvox-agent-shell--handle-lifecycle-event (event)
  "Provide semantic processing feedback for public Agent Shell EVENT."
  (let ((event-type (map-elt event :event))
        (facts (emacsvox-agent-shell-lifecycle-facts event)))
    ;; Response collection is independent of lifecycle cue preferences.
    ;; `turn-complete' is the semantic boundary: no network-pause timer is
    ;; allowed to deliver a partial response.
    (pcase event-type
      ((or 'elicitation-request 'elicitation-response)
       (emacsvox-agent-shell--question-event event))
      ('session-selected
       (emacsvox-agent-shell--interaction-cleanup)
       (emacsvox-agent-shell--out-of-turn-cleanup)
       (setq emacsvox-agent-shell--response-turn-active-p nil
             emacsvox-agent-shell--last-completed-answer nil
             emacsvox-agent-shell--latest-turn-outcome nil))
      ('session-restored
       (setq emacsvox-agent-shell--response-turn-active-p nil
             emacsvox-agent-shell--last-completed-answer
             (emacsvox-agent-shell--rendered-latest-agent-answer)
             emacsvox-agent-shell--latest-turn-outcome
             (and emacsvox-agent-shell--last-completed-answer
                  'completed)))
      ('input-submitted
       (emacsvox-agent-shell--begin-response-turn)
       (when (and emacsvox-agent-shell--queue-start-count
                  (emacsvox-agent-shell--speech-level-at-least-p 'notify))
         (emacsvox-agent-shell--queue-feedback 'started)))
      ('config-option-update
       (emacsvox-agent-shell--observe-config-options
        (map-nested-elt event '(:data :config-options))
        (emacsvox-agent-shell--initialized-p)))
      ('init-finished
       (emacsvox-agent-shell--observe-config-options
        (emacsvox-agent-shell--config-options) nil))
      ('turn-complete
       (if (equal (map-nested-elt event '(:data :stop-reason)) "end_turn")
           (emacsvox-agent-shell--finish-response-turn)
         (emacsvox-agent-shell--discard-response-turn)))
      ('error
       (emacsvox-agent-shell--discard-response-turn)))
    (when (and (memq event-type '(turn-complete error))
               (hash-table-p emacsvox-agent-shell--tool-call-status-cache))
      (clrhash emacsvox-agent-shell--tool-call-status-cache))
    (when (memq event-type '(turn-complete error))
      (setq emacsvox-agent-shell--tool-output-cache nil
            emacsvox-agent-shell--permission-detail-cache nil))
    (when emacsvox-agent-shell-signal-processing
      (pcase event-type
        ((or 'init-started 'input-submitted)
         (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
           (emacsvox-agent-shell--submit-icon-feedback
            facts 'notification
            emacsvox-agent-shell-processing-start-icon)))
        ('init-finished
         (when (emacsvox-agent-shell--speech-level-at-least-p 'full)
           (emacsvox-agent-shell--submit-icon-feedback
            facts 'notification
            emacsvox-agent-shell-processing-end-icon)))
        ('turn-complete
         (emacsvox-agent-shell--speak-turn-completion event))
        ('error
         (emacsvox-agent-shell--speak-agent-error event))))))

(defun emacsvox-agent-shell--lifecycle-event-setup ()
  "Subscribe the current agent-shell buffer to lifecycle events."
  (unless emacsvox-agent-shell--lifecycle-subscription
    (setq emacsvox-agent-shell--lifecycle-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :on-event #'emacsvox-agent-shell--handle-lifecycle-event))))

(defun emacsvox-agent-shell--lifecycle-event-cleanup ()
  "Remove the current buffer's lifecycle event subscription."
  (when emacsvox-agent-shell--lifecycle-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--lifecycle-subscription)
    (setq emacsvox-agent-shell--lifecycle-subscription nil))
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--lifecycle-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--lifecycle-event-cleanup t))

(defun emacsvox-agent-shell--deliver-pending-blocks (buffer qualified-ids)
  "Deliver pending QUALIFIED-IDS from BUFFER and return its agent answer.
Clear the stored bodies after taking their final rendered snapshots."
  (when (and buffer (buffer-live-p buffer))
    (with-current-buffer buffer
      (let* ((speak-p (emacsvox-agent-shell--should-speak-p buffer))
             (response-only-p
              (and
               speak-p
               (eq
                (emacsvox-agent-shell--effective-speech-level buffer)
                'response)))
            answer-bodies)
        (dolist (qualified-id qualified-ids)
          (let* ((pair
                  (and
                   (hash-table-p
                    emacsvox-agent-shell--pending-section-markers)
                   (gethash
                    qualified-id
                    emacsvox-agent-shell--pending-section-markers)))
                 (snapshot
                  (and pair
                       (emacsvox-agent-shell--section-marker-snapshot
                        qualified-id pair)))
                 (content
                  (or
                   (cdr-safe snapshot)
                   (and
                    (hash-table-p emacsvox-agent-shell--pending-bodies)
                    (gethash
                     qualified-id
                     emacsvox-agent-shell--pending-bodies))))
                 (body-start
                  (and (markerp (car-safe pair))
                       (eq (marker-buffer (car pair)) (current-buffer))
                       (marker-position (car pair))))
                 (state
                  (and body-start
                       (< body-start (point-max))
                       (get-text-property
                        body-start 'agent-shell-ui-state)))
                 (block-id
                  (if (string-match "-\\([^-]+\\)$" qualified-id)
                      (match-string 1 qualified-id)
                    qualified-id))
                 (block-type
                  (emacsvox-agent-shell--classify-block
                   block-id qualified-id state body-start)))
            (when content
              (let ((trimmed (string-trim content)))
                (when (not (string-empty-p trimmed))
                  (when (eq block-type 'agent-message)
                    (push trimmed answer-bodies))
                  (when (and
                         speak-p
                         (not
                          (and response-only-p
                               (eq block-type 'agent-message))))
                    (emacsvox-agent-shell--speak-content
                     trimmed block-type)))))))
        (let ((answer
               (when answer-bodies
                 (string-join (nreverse answer-bodies) "\n"))))
          ;; At the ordinary response level, all rendered answer fragments are
          ;; one automatic response.  This applies the unsolicited-content
          ;; budget once per turn and avoids queueing progress updates ahead of
          ;; the final answer.  Full mode retains semantic per-block ordering.
          (when (and response-only-p answer)
            (emacsvox-agent-shell--speak-content answer 'agent-message))
          (emacsvox-agent-shell--clear-section-markers
           emacsvox-agent-shell--pending-section-markers)
          (when emacsvox-agent-shell--pending-bodies
            (clrhash emacsvox-agent-shell--pending-bodies))
          (setq emacsvox-agent-shell--pending-section-markers nil
                emacsvox-agent-shell--pending-speech-qualified-ids nil
                emacsvox-agent-shell--pending-speech-timer nil)
          answer)))))

(defun emacsvox-agent-shell--execute-delayed-speech (buffer qualified-ids)
  "Deliver pending QUALIFIED-IDS left by an older timer in BUFFER.
Retained so a timer created by a previously loaded pause-based implementation
can finish safely while support is being reloaded."
  (emacsvox-agent-shell--deliver-pending-blocks buffer qualified-ids))

(defun emacsvox-agent-shell--classify-block
    (block-id &optional qualified-id state position)
  "Classify BLOCK-ID to determine content type.
When renderer STATE is present, QUALIFIED-ID and POSITION provide authoritative
group provenance; ID-only inference remains for legacy pending-body timers.
Returns one of: \\='agent-message, \\='user-message, \\='thought,
\\='tool-call, \\='permission, \\='plan, \\='error, or \\='unknown."
  (if state
      (let ((semantic-type
             (emacsvox-agent-shell--semantic-block-type
              (or qualified-id block-id) state position)))
        (cond
         ((eq semantic-type 'agent-response) 'agent-message)
         ((eq semantic-type 'user-prompt) 'user-message)
         ((memq semantic-type '(thought tool-call permission plan error))
          semantic-type)
         (t 'unknown)))
    (cond
     ((string-match-p "agent_message_chunk" block-id) 'agent-message)
     ((string-match-p "user_message_chunk" block-id) 'user-message)
     ((string-match-p "agent_thought_chunk" block-id) 'thought)
     ((string-match-p "^permission-" block-id) 'permission)
     ((string-equal block-id "plan") 'plan)
     ((string-match-p "^failed-\\|^Error" block-id) 'error)
     ((and
       (not
        (string-match-p
         "-chunk\\|^permission-\\|^plan\\|^Error\\|^failed-"
         block-id))
       (> (length block-id) 10))
      'tool-call)
     (t 'unknown))))

(defun emacsvox-agent-shell--meaningful-tool-text (text)
  "Return a concise speech version of meaningful tool TEXT, or nil."
  (when (and (stringp text) (string-match-p "[[:alnum:]]" text))
    (let ((clean
           (replace-regexp-in-string
            "[[:space:]\n\r]+" " "
            (string-trim (substring-no-properties text)))))
      (if (> (length clean) 120)
          (concat (substring clean 0 117) "...")
        clean))))

(defun emacsvox-agent-shell--tool-call-description (tool-call tool-call-id)
  "Return a concise description of TOOL-CALL identified by TOOL-CALL-ID."
  (or (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :title))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :description))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :command))
      (emacsvox-agent-shell--meaningful-tool-text
       (map-elt tool-call :kind))
      (emacsvox-agent-shell--meaningful-tool-text tool-call-id)
      "unknown tool"))

(defun emacsvox-agent-shell--permission-details (tool)
  "Snapshot TOOL's requested operation, excluding output and progress."
  (copy-tree (mapcar (lambda (key) (map-elt tool key))
                     '(:title :description :command :raw-input))))

(defun emacsvox-agent-shell--observe-permission-details (event)
  "Announce changed operation details for an already pending permission EVENT."
  (when-let* ((id (map-nested-elt event '(:data :tool-call-id)))
              ((hash-table-p emacsvox-agent-shell--permission-detail-cache))
              (previous (gethash id emacsvox-agent-shell--permission-detail-cache))
              (tool (map-nested-elt event '(:data :tool-call))))
    (if (member (map-elt tool :status) '("completed" "failed"))
        (remhash id emacsvox-agent-shell--permission-detail-cache)
      (let ((details (emacsvox-agent-shell--permission-details tool)))
        (unless (equal details (cdr previous))
          (puthash id (cons (car previous) details)
                   emacsvox-agent-shell--permission-detail-cache)
          (when emacsvox-agent-shell-speak-permissions
            (let* ((print-length 8) (print-level 3)
                   (input (or (map-elt tool :command)
                              (when (map-elt tool :raw-input)
                                (prin1-to-string (map-elt tool :raw-input)))))
                   (detail (emacsvox-agent-shell--permission-field-text
                            input "tool input")))
              (emacsvox-agent-shell--notify-event
               (concat "Permission details changed. "
                       (emacsvox-agent-shell--tool-call-description tool id)
                       (when detail (concat ". Input: " detail)))
               (emacsvox-agent-shell--presentation-facts
                'permission-request 'agent-permission-details-updated)
               'warn-user))))))))

(defun emacsvox-agent-shell--tool-call-announcement (status description)
  "Return a semantic announcement for tool STATUS and DESCRIPTION."
  (let ((verb (pcase status
                ("pending" "pending")
                ("in_progress" "started")
                ("completed" "completed")
                ("failed" "failed"))))
    (concat (format "Tool %s: %s" verb description)
            (unless (string-match-p "[.!?]$" description) "."))))

(defun emacsvox-agent-shell--tool-content-block-text (block)
  "Extract speakable text from ACP tool content BLOCK."
  (cond
   ((stringp block) (substring-no-properties block))
   ((consp block)
    (let ((text (or (map-elt block :text) (map-elt block 'text)))
          (content (or (map-elt block :content) (map-elt block 'content))))
      (cond
       ((stringp text) (substring-no-properties text))
       ((stringp content) (substring-no-properties content))
       ((consp content)
        (emacsvox-agent-shell--tool-content-block-text content)))))
   (t nil)))

(defun emacsvox-agent-shell--tool-output-text (content)
  "Extract speakable terminal output from ACP tool CONTENT."
  (let* ((blocks
          (cond
           ((stringp content) (list content))
           ((vectorp content) (append content nil))
           ((and (listp content)
                 (or (assq 'type content) (assq :type content)
                     (assq 'text content) (assq :text content)))
            (list content))
           ((listp content) content)))
         (texts
          (seq-keep
           (lambda (block)
             (when-let* ((text
                          (emacsvox-agent-shell--tool-content-block-text
                           block))
                         (trimmed (string-trim text))
                         ((not (string-empty-p trimmed))))
               trimmed))
           blocks)))
    (when texts (string-join texts "\n"))))

(defun emacsvox-agent-shell--tool-call-feedback-text
    (status description content)
  "Return one spoken object for tool STATUS, DESCRIPTION, and CONTENT.

Return nil when the configured verbosity requests status cues only."
  (unless (eq emacsvox-agent-shell-tool-output-verbosity 'status)
    (let ((announcement
           (emacsvox-agent-shell--tool-call-announcement
            status description)))
      (if
          (and
           (eq emacsvox-agent-shell-tool-output-verbosity 'full)
           (member status '("completed" "failed")))
          (if-let* ((output
                     (emacsvox-agent-shell--tool-output-text content)))
              (format "%s Output: %s" announcement output)
            announcement)
        announcement))))

(defun emacsvox-agent-shell--handle-tool-call-update (event)
  "Collect renderer output or present the public tool update EVENT."
  (emacsvox-agent-shell--observe-permission-details event)
  (if (and emacsvox-agent-shell--rendering-tool-update
           (eq (current-buffer)
               (plist-get emacsvox-agent-shell--rendering-tool-update :buffer))
           (equal (map-nested-elt event '(:data :tool-call-id))
                  (plist-get emacsvox-agent-shell--rendering-tool-update :id))
           (eq emacsvox-agent-shell-tool-output-verbosity 'full)
           (member (map-nested-elt event '(:data :tool-call :status))
                   '("completed" "failed")))
      (setf (plist-get emacsvox-agent-shell--rendering-tool-update :event)
            (copy-tree event))
    (emacsvox-agent-shell--present-tool-update event)))

(defun emacsvox-agent-shell--present-tool-update (event)
  "Present changed status or terminal output from public tool EVENT."
  (let* ((data (map-elt event :data))
         (tool-call-id (map-elt data :tool-call-id))
         (tool-call (map-elt data :tool-call))
         (status (map-elt tool-call :status))
         (output (or (emacsvox-agent-shell--tool-output-text
                      (map-elt tool-call :output))
                     (emacsvox-agent-shell--tool-output-text
                      (map-elt tool-call :content))))
         (digest (and output (secure-hash 'sha256 output))))
    (when (and tool-call-id status)
      (unless (hash-table-p emacsvox-agent-shell--tool-call-status-cache)
        (setq emacsvox-agent-shell--tool-call-status-cache
              (make-hash-table :test #'equal)))
      (unless (hash-table-p emacsvox-agent-shell--tool-output-cache)
        (setq emacsvox-agent-shell--tool-output-cache
              (make-hash-table :test #'equal)))
      (let* ((previous
              (gethash tool-call-id
                       emacsvox-agent-shell--tool-call-status-cache))
             (status-changed (not (equal status previous)))
             (output-changed
              (and digest
                   (eq emacsvox-agent-shell-tool-output-verbosity 'full)
                   (member status '("completed" "failed"))
                   (not (equal digest
                               (gethash tool-call-id
                                        emacsvox-agent-shell--tool-output-cache))))))
        (puthash tool-call-id status
                 emacsvox-agent-shell--tool-call-status-cache)
        (when digest
          (puthash tool-call-id digest emacsvox-agent-shell--tool-output-cache))
        (when (and emacsvox-agent-shell-speak-tool-calls
                   (emacsvox-agent-shell--speech-level-at-least-p 'full)
                   (member status
                           '("pending" "in_progress" "completed" "failed"))
                   (or status-changed output-changed))
          (let* ((facts
                  (emacsvox-agent-shell--presentation-facts
                   'agent-tool
                   (if status-changed 'agent-tool-status-changed
                     'agent-tool-output-updated) nil
                   (list
                    :agent-tool-status
                    (if (equal status "in_progress")
                        'in-progress
                      (intern status)))))
                 (text
                  (emacsvox-agent-shell--tool-call-feedback-text
                   status
                   (emacsvox-agent-shell--tool-call-description
                    tool-call tool-call-id)
                   output)))
            (emacsvox-agent-shell--notify-event text facts)))))))

(defun emacsvox-agent-shell--record-tool-output-section (range)
  "Capture RANGE's rendered body for the tool event in this rendering pass."
  (when-let* ((update emacsvox-agent-shell--rendering-tool-update)
              ((eq (plist-get update :buffer) (current-buffer)))
              ((plist-get update :event))
              (start (map-nested-elt range '(:body :start)))
              ((< start (point-max)))
              ((eq (get-text-property start 'agent-shell-ui-section) 'body))
              (state (get-text-property start 'agent-shell-ui-state))
              ((equal (map-elt state :qualified-id)
                      (plist-get update :qualified-id)))
              ;; Markdown can insert or delete characters after RANGE was
              ;; computed.  Read the current body boundary, as response speech
              ;; does, and stop if another fragment's state begins first.
              (end (min
                    (next-single-property-change
                     start 'agent-shell-ui-section nil (point-max))
                    (next-single-property-change
                     start 'agent-shell-ui-state nil (point-max)))))
    (setf (plist-get emacsvox-agent-shell--rendering-tool-update :output)
          (emacsvox-agent-shell--remove-visual-chrome-for-speech
           (buffer-substring start end)))))

(defun emacsvox-agent-shell--on-notification-around (original &rest arguments)
  "Join public tool status with the output rendered by ORIGINAL.
Agent Shell omits Codex rawOutput and rendered diffs from its tool event.
Scope this compatibility adapter to the exact buffer, notification, and
fragment.  Fragment names alone never manufacture a tool event."
  (let* ((state (plist-get arguments :state))
         (notification (plist-get arguments :acp-notification))
         (update (map-nested-elt notification '(params update)))
         (id (map-elt update 'toolCallId))
         (emacsvox-agent-shell--rendering-tool-update
          (when (and id (equal (map-elt update 'sessionUpdate)
                               "tool_call_update"))
            (list :buffer (map-elt state :buffer) :id id
                  :qualified-id (format "%s-%s" (map-elt state :request-count) id)
                  :event nil :output nil))))
    (prog1 (apply original arguments)
      (when-let* ((capture emacsvox-agent-shell--rendering-tool-update)
                  (event (plist-get capture :event))
                  (buffer (plist-get capture :buffer))
                  ((buffer-live-p buffer)))
        (when-let* ((output (plist-get capture :output)))
          (setf (alist-get :output (alist-get :tool-call (alist-get :data event)))
                output))
        (with-current-buffer buffer
          (emacsvox-agent-shell--present-tool-update event))))))

(defun emacsvox-agent-shell--tool-call-event-setup ()
  "Subscribe the current agent-shell buffer to tool call updates."
  (unless emacsvox-agent-shell--tool-call-subscription
    (setq emacsvox-agent-shell--tool-call-subscription
          (agent-shell-subscribe-to
           :shell-buffer (current-buffer)
           :event 'tool-call-update
           :on-event #'emacsvox-agent-shell--handle-tool-call-update))))

(defun emacsvox-agent-shell--tool-call-event-cleanup ()
  "Remove the current buffer's tool subscription and cached state."
  (when emacsvox-agent-shell--tool-call-subscription
    (agent-shell-unsubscribe
     :subscription emacsvox-agent-shell--tool-call-subscription)
    (setq emacsvox-agent-shell--tool-call-subscription nil))
  (when (hash-table-p emacsvox-agent-shell--tool-call-status-cache)
    (clrhash emacsvox-agent-shell--tool-call-status-cache))
  (setq emacsvox-agent-shell--tool-call-status-cache nil)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--tool-call-event-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--tool-call-event-cleanup t))

(provide 'emacsvox-agent-shell-events)

;;; emacsvox-agent-shell-events.el ends here
