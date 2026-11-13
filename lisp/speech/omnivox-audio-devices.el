;;; omnivox-audio-devices.el --- Independent physical output choices -*- lexical-binding: t; -*-

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
;; Saved choices are projected into ordinary startup, resolved by the speech
;; host, and kept separate from confirmed session choices and engine snapshots.
;; Apply is asynchronous.  An unanswered operation blocks assumed recovery.
;;; Code:
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar tts-notification-device)
(declare-function omnivox--send-control-request "omnivox-voices" (process request callback &optional timeout))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox-remote-enabled-p "omnivox-remote" ())
(declare-function tts--omnivox-program-p "tts-speak" (&optional program))
(declare-function tts--resolve-program "tts-speak" (program))

(defgroup omnivox-audio-devices nil
  "Physical outputs for local Omnivox speech."
  :group 'tts)

(defcustom omnivox-audio-device-preferences nil
  "Saved physical output choices, scoped to the speech host and lane.
Each entry is (HOST LANE SELECTION LABEL).  LANE is speaker or notification;
SELECTION is default or the opaque backend-qualified device ID.  LABEL is
only a display name.  Use the output device editor to choose, Apply and Save
separately.  Saving affects future Emacs sessions; it never changes live output.
At most eight hosts per lane are supported.  Explicit OMNIVOX_AUDIO_DEVICE
and command line overrides take precedence at startup.  Other speech
backends ignore this."
  :type '(repeat (list (string :tag "Speech host")
                      (choice (const speaker) (const notification))
                      (string :tag "Device ID or default") (string :tag "Label")))
  :group 'omnivox-audio-devices)

(defvar omnivox-audio-devices--lanes nil
  "Session records keyed by speech program and lane, including unresolved Apply.")

(defun omnivox-audio-devices--record (role)
  "Return the retained session record for ROLE and this speech program."
  (cdr (assoc (cons tts-program role) omnivox-audio-devices--lanes)))

(defun omnivox-audio-devices--put (role record)
  "Retain RECORD for ROLE without modifying another speech program or lane."
  (setf (alist-get (cons tts-program role) omnivox-audio-devices--lanes nil nil #'equal) record))

(defun omnivox-audio-devices--selection-p (selection)
  "Whether SELECTION is a bounded default choice or opaque backend ID."
  (or (equal selection '(:mode "system_default"))
      (and (equal (plist-get selection :mode) "device")
           (stringp (plist-get selection :id))
           (<= (string-bytes (plist-get selection :id)) 1024)
           (string-match-p "\\`[^:[:cntrl:]]+:[^[:cntrl:]]+\\'" (plist-get selection :id)))))

(defun omnivox-audio-devices--value (selection)
  "Return the startup value of validated SELECTION."
  (unless (omnivox-audio-devices--selection-p selection) (error "Invalid audio device choice"))
  (if (equal (plist-get selection :mode) "system_default") "default" (plist-get selection :id)))

(defun omnivox-audio-devices--selection (value)
  "Decode a saved or startup VALUE, preserving its opaque identity."
  (let ((selection (if (equal value "default") '(:mode "system_default")
                     (list :mode "device" :id value))))
    (omnivox-audio-devices--value selection)
    selection))

(defun omnivox-audio-devices--projection (role)
  "Encode saved host choices for ROLE without querying or starting a process."
  (let (hosts rows)
    (dolist (entry omnivox-audio-device-preferences)
      (pcase-let ((`(,host ,lane ,value ,_label) entry))
        (unless (and (stringp host) (<= 1 (string-bytes host) 512)
                     (not (string-match-p "[[:cntrl:]]" host))
                     (memq lane '(speaker notification)))
          (error "Invalid saved audio device preference"))
        (when (eq lane role)
          (when (member host hosts) (error "Repeated audio device preference for %s" host))
          (push host hosts)
          (push (list :host_scope host :selection (omnivox-audio-devices--selection value)) rows))))
    (when (> (length rows) 8) (error "Save device choices for at most eight speech hosts"))
    (let ((json (json-serialize (vconcat (nreverse rows)))))
      (when (> (string-bytes json) 16384) (error "Saved audio device preferences exceed 16 KiB"))
      json)))

(defun omnivox-audio-devices--startup-environment (environment role)
  "Project saved and confirmed session choices into ENVIRONMENT for ROLE.
This runs before the owner starts speech.  Emergency startup bypasses it."
  (let* ((process-environment (copy-sequence environment))
         (record (omnivox-audio-devices--record role)))
    (when (plist-get record :pending)
      (user-error "%s output Apply is unresolved; refresh its status or explicitly choose a recovery device" role))
    (setenv "OMNIVOX_AUDIO_DEVICE_PREFERENCES" (omnivox-audio-devices--projection role))
    (setenv "OMNIVOX_OWNED_AUDIO_DEVICE"
            (when-let* ((selection (or (plist-get record :override)
                                      (plist-get (plist-get (plist-get record :status) :state) :selection))))
              (omnivox-audio-devices--value selection)))
    (setenv "OMNIVOX_OWNED_AUDIO_DEVICE_HOST"
            (when (getenv "OMNIVOX_OWNED_AUDIO_DEVICE")
              (or (plist-get record :override-host) (plist-get (plist-get record :status) :host_scope))))
    process-environment))

(defun omnivox-audio-devices--assert-resolved (role)
  "Reject ordinary recovery of ROLE while a sent Apply has no known outcome."
  (when (and (tts--omnivox-program-p) (not (omnivox-remote-enabled-p))
             (plist-get (omnivox-audio-devices--record role) :pending))
    (user-error "%s output Apply is unresolved; refresh it or explicitly choose a recovery device" role)))

(defun omnivox-audio-devices--status-p (status)
  "Whether STATUS contains a coherent, bounded output identity."
  (let* ((state (plist-get status :state)) (revision (plist-get state :revision))
         (operation (plist-get state :last_operation)) (change (plist-get operation :change)))
    (and (stringp (plist-get status :incarnation))
         (<= 1 (string-bytes (plist-get status :incarnation)) 128)
         (stringp (plist-get status :host_scope))
         (<= 1 (string-bytes (plist-get status :host_scope)) 512)
         (integerp revision) (<= 0 revision #xffffffffffffffff)
         (omnivox-audio-devices--selection-p (plist-get state :selection))
         (or (null (plist-get state :connected))
             (omnivox-audio-devices--selection-p (list :mode "device" :id (plist-get state :connected))))
         (or (null operation)
             (and (integerp (plist-get change :sequence))
                  (<= 1 (plist-get change :sequence) #xffffffffffffffff)
                  (integerp (plist-get change :expected_revision))
                  (<= 0 (plist-get change :expected_revision) #xffffffffffffffff)
                  (omnivox-audio-devices--selection-p (plist-get change :selection))
                  (member (plist-get operation :outcome)
                          '("preparing" "applied" "unchanged" "rejected" "cancelled")))))))

(defun omnivox-audio-devices--observe (process role status)
  "Remember validated STATUS for PROCESS and ROLE, respecting operation identity."
  (when (omnivox-audio-devices--status-p status)
    (let* ((tts-program (or (process-get process 'omnivox-audio-device-program) tts-program))
           (record (omnivox-audio-devices--record role))
           (pending (plist-get record :pending))
           (operation (plist-get (plist-get status :state) :last_operation))
           (previous (plist-get record :status)))
      (when (and (or (null record) (eq process (plist-get record :process)))
                 (or (not (process-get process 'omnivox-audio-device-status))
                     (equal (plist-get status :incarnation)
                            (plist-get (process-get process 'omnivox-audio-device-status) :incarnation)))
                 (or (not (equal (plist-get previous :incarnation) (plist-get status :incarnation)))
                     (and (<= (plist-get (plist-get previous :state) :revision)
                              (plist-get (plist-get status :state) :revision))
                          (<= (or (plist-get (plist-get (plist-get (plist-get previous :state) :last_operation) :change) :sequence) 0)
                              (or (plist-get (plist-get operation :change) :sequence) 0)))))
        (when (and pending
                   (equal (plist-get pending :incarnation) (plist-get status :incarnation))
                   (equal (plist-get pending :change) (plist-get operation :change))
                   (not (equal "preparing" (plist-get operation :outcome))))
          (setq record (plist-put record :pending nil)))
        (setq record (plist-put record :process process)
              record (plist-put record :status status)
              record (plist-put record :override nil)
              record (plist-put record :override-host nil))
        (omnivox-audio-devices--put role record)
        (process-put process 'omnivox-audio-device-status status)
        t))))

(defun omnivox-audio-devices--negotiate (process)
  "Read PROCESS's initial route on its existing connection without delaying speech."
  (when (omnivox--process-supports-p process "audio_device_selection_v1")
    (let* ((role (or (process-get process 'tts--speech-process-role) 'speaker))
           (record (omnivox-audio-devices--record role)))
      (unless (plist-get record :pending)
        (process-put process 'omnivox-audio-device-program tts-program)
        (omnivox-audio-devices--put role (plist-put record :process process))
        (condition-case nil
            (omnivox--send-control-request
             process '(:type "audio_device_status_v1")
             (lambda (_ response) (omnivox-audio-devices--observe process role response)))
          (error nil))))))

(defun omnivox-audio-devices--supported-p (process)
  "Whether PROCESS offers local physical output selection."
  (and (processp process) (process-live-p process)
       (not (process-get process 'omnivox-library-retired))
       (not (process-get process 'tts--speech-process-retiring))
       (not (process-get process 'omnivox-remote-managed))
       (not (process-get process 'omnivox-emergency-output))
       (fboundp 'omnivox--process-supports-p)
       (omnivox--process-supports-p process "audio_device_selection_v1")))

(defun omnivox-audio-devices--discover (process callback)
  "Discover outputs for PROCESS, calling CALLBACK with a catalogue or error.
With no live worker, an explicit editor refresh may run bounded discovery;
ordinary startup never launches this diagnostic process."
  (require 'omnivox-voices)
  (cond
   ((or (omnivox-remote-enabled-p) (not (tts--omnivox-program-p)))
    (funcall callback '(:type "error" :message "Physical device selection requires local Omnivox")))
   ((omnivox-audio-devices--supported-p process)
    (omnivox--send-control-request process '(:type "audio_devices_v1")
                                    (lambda (_ response) (funcall callback response)) 3))
   ((and (process-live-p process)
         (not (process-get process 'omnivox-library-retired)))
    (funcall callback '(:type "error" :message "This worker does not support physical device selection")))
   (t
    (let ((program (tts--resolve-program tts-program)) (output "") timer done worker)
      (cl-labels ((finish (response)
                   (unless done
                     (setq done t)
                     (when (timerp timer) (cancel-timer timer))
                     (when (process-live-p worker) (delete-process worker))
                     (funcall callback response))))
        (condition-case error-data
            (progn
              (setq worker
                    (make-process
                     :name "Omnivox output discovery" :command (list program "--list-audio-devices")
                     :connection-type 'pipe :coding 'utf-8-unix :noquery t
                     :stderr (get-buffer-create " *Omnivox output discovery errors*")
                     :filter (lambda (_ chunk)
                               (if (> (+ (string-bytes output) (string-bytes chunk)) 524288)
                                   (finish '(:type "error" :message "Output catalogue exceeds its bound"))
                                 (setq output (concat output chunk))))
                     :sentinel
                     (lambda (owner _event)
                       (when (memq (process-status owner) '(exit signal))
                         (finish
                          (condition-case nil
                              (if (zerop (process-exit-status owner))
                                  (json-parse-string output :object-type 'plist :array-type 'list
                                                     :null-object nil :false-object :false)
                                '(:type "error" :message "Output discovery failed; inspect diagnostics"))
                            (error '(:type "error" :message "Invalid output catalogue"))))))))
              (unless done
                (setq timer (run-at-time 3 nil (lambda () (finish '(:type "error" :message "Output discovery timed out")))))))
          (error (finish (list :type "error" :message (error-message-string error-data))))))))))

(defun omnivox-audio-devices--refresh-status (process role callback &optional cancel)
  "Read PROCESS status for ROLE and call CALLBACK.  CANCEL cancels retained Apply."
  (unless (omnivox-audio-devices--supported-p process)
    (user-error "This worker is unavailable or does not support device selection"))
  (let* ((pending (plist-get (omnivox-audio-devices--record role) :pending))
         (request (if (and cancel pending)
                      (list :type "cancel_audio_device_v1" :incarnation (plist-get pending :incarnation)
                            :sequence (plist-get (plist-get pending :change) :sequence))
                    '(:type "audio_device_status_v1"))))
    (omnivox--send-control-request
     process request
     (lambda (_ response)
       (let ((status (if (equal (plist-get response :type) "audio_device_result_v1")
                         (plist-get response :status) response)))
         (omnivox-audio-devices--observe process role status)
         (funcall callback status))) 1)))

(defun omnivox-audio-devices--apply (process role selection callback &optional host)
  "Apply SELECTION to PROCESS's ROLE and call CALLBACK with outcome and status.
Timeout leaves a retained pending operation.  No new identity is sent on retry.
When HOST is supplied, reject a catalogue from a different speech host."
  (omnivox-audio-devices--value selection)
  (unless (omnivox-audio-devices--supported-p process)
    (user-error "This worker does not support live device selection"))
  (when (or (plist-get (omnivox-audio-devices--record role) :pending)
            (plist-get (omnivox-audio-devices--record role) :query-operation))
    (user-error "Earlier device Apply is unresolved; refresh or cancel it first"))
  (let ((deadline (+ (float-time) 3)) (program tts-program) (identity (list 'apply)) done timer pending)
    (process-put process 'omnivox-audio-device-program program)
    (omnivox-audio-devices--put
     role (plist-put (plist-put (omnivox-audio-devices--record role) :process process)
                     :query-operation identity))
    (cl-labels
        ((finish (outcome &optional status)
           (unless done
             (setq done t)
             (when (timerp timer) (cancel-timer timer))
             (let* ((tts-program program) (record (omnivox-audio-devices--record role)))
               (when (eq (plist-get record :query-operation) identity)
                 (omnivox-audio-devices--put role (plist-put record :query-operation nil))))
             (funcall callback outcome status)))
         (send (request receiver)
           (condition-case nil
               (omnivox--send-control-request process request receiver 0.5)
             (error (finish "unknown"))))
         (poll ()
           (if (or (>= (float-time) deadline) (not (process-live-p process)))
               (finish "unknown")
             (send '(:type "audio_device_status_v1") #'observe)))
         (observe (_ response)
           (unless done
             (let* ((tts-program program)
                    (status (if (equal (plist-get response :type) "audio_device_result_v1")
                                (plist-get response :status) response))
                    (operation (plist-get (plist-get status :state) :last_operation)))
               (cond
                ((not (omnivox-audio-devices--status-p status))
                 (setq timer (run-at-time 0.025 nil #'poll)))
                ((and (equal (plist-get response :type) "audio_device_result_v1")
                      (member (plist-get response :outcome) '("busy" "stale"))
                      (equal (plist-get response :sequence) (plist-get (plist-get pending :change) :sequence))
                      (equal (plist-get pending :incarnation) (plist-get status :incarnation)))
                 (let ((record (omnivox-audio-devices--record role)))
                   (when (equal pending (plist-get record :pending))
                     (omnivox-audio-devices--put role (plist-put record :pending nil))))
                 (omnivox-audio-devices--observe process role status)
                 (finish (plist-get response :outcome) status))
                ((or (not (equal (plist-get pending :incarnation) (plist-get status :incarnation)))
                     (not (equal (plist-get pending :change) (plist-get operation :change))))
                 (finish "unknown" status))
                (t
                 (if (not (omnivox-audio-devices--observe process role status))
                     (finish "stale" status)
                   (if (equal (plist-get operation :outcome) "preparing")
                       (setq timer (run-at-time 0.025 nil #'poll))
                     (finish (plist-get operation :outcome) status))))))))
         (start (_ status)
           (unless done
             (let* ((tts-program program)
                    (state (plist-get status :state))
                    (operation (plist-get state :last_operation))
                    (sequence (1+ (or (plist-get (plist-get operation :change) :sequence) 0))))
               (cond
                ((not (eq identity (plist-get (omnivox-audio-devices--record role) :query-operation)))
                 (finish "stale"))
                ((not (omnivox-audio-devices--status-p status)) (finish "unavailable"))
                ((and host (not (equal host (plist-get status :host_scope)))) (finish "rejected" status))
                ((or (equal "preparing" (plist-get operation :outcome))
                     (> sequence #xffffffffffffffff)) (finish "busy" status))
                (t
                 (setq pending (list :incarnation (plist-get status :incarnation)
                                     :change (list :sequence sequence :expected_revision (plist-get state :revision)
                                                   :selection selection)))
                 ;; Retain before writing: immediate callbacks and lost replies
                 ;; must not permit recovery onto the previous route.
                 (omnivox-audio-devices--put role (list :process process :status status :pending pending :query-operation identity))
                 (send (append '(:type "apply_audio_device_v1") pending) #'observe)))))))
      (send '(:type "audio_device_status_v1") #'start))))

(defun omnivox-audio-devices--fallback-p ()
  "Whether notification fallback has no conflicting physical destination.
Unknown managed routes never imply permission to use main speech instead."
  (or (not (tts--omnivox-program-p)) (omnivox-remote-enabled-p)
      (equal tts-notification-device "default")
      (let* ((main (omnivox-audio-devices--record 'speaker))
             (notify (omnivox-audio-devices--record 'notification))
             (main-status (plist-get main :status)) (notify-status (plist-get notify :status)))
        (if (or main notify omnivox-audio-device-preferences (getenv "OMNIVOX_AUDIO_DEVICE"))
            (and (not (plist-get main :pending)) (not (plist-get notify :pending))
                 (not (plist-get main :override)) (not (plist-get notify :override))
                 main-status notify-status
                 (equal (plist-get main-status :host_scope) (plist-get notify-status :host_scope))
                 (equal (plist-get (plist-get main-status :state) :selection)
                        (plist-get (plist-get notify-status :state) :selection)))
          t))))

(provide 'omnivox-audio-devices)
;;; omnivox-audio-devices.el ends here
