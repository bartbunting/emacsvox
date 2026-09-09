;;; omnivox-preview.el --- Owned Omnivox preview sequences -*- lexical-binding: t; -*-

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
;; Complete and individual samples share process ownership, guarded startup,
;; bounded preparation and unwind-safe control reservations. Private layered
;; samples preserve raw choices/context and validate server playback evidence.
;;; Code:
(require 'cl-lib)
(require 'tts-queue-state)
(require 'omnivox-choice-codec)

(defvar tts-speaker-process)
(defvar tts-stopped-hook)
(defvar omnivox-voice-preview-timeout)
(defvar omnivox--control-capabilities-property)
(defvar omnivox--control-request-sequence)
(defvar omnivox-control-max-payload-bytes)
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--preview-complete-request "omnivox-voices" (entry process))
(declare-function omnivox--preview-individual-request "omnivox-voices" (entry process))
(declare-function omnivox--choice-tuning-supported-p "omnivox-voices" (process))
(declare-function omnivox--preview-validate-values "omnivox-voices" (entry))
(declare-function omnivox--preview-validate-selector "omnivox-voices" (selector))
(declare-function omnivox--preview-policy-json "omnivox-voices" (policy disabled))
(declare-function omnivox--preview-valid-id-p "omnivox-voices" (value limit &optional pattern))
(declare-function omnivox--normalize-complete-preview-response "omnivox-voices" (entry response))
(declare-function omnivox--normalize-preview-response "omnivox-voices" (entry response effects-supported rate-supported))
(declare-function omnivox--encode-control-request "omnivox-voices" (request))
(declare-function omnivox--pending-requests "omnivox-voices" (process))
(declare-function omnivox--next-control-request-id "omnivox-voices" ())
(declare-function tts--interrupt-process "tts-speak" (process &optional notifications preserved preview))
(declare-function tts--voice-preview-callback "tts-speak" (callback result))
(declare-function emacsvox-aural--call-independent-callback "emacsvox-aural-transport" (function &rest arguments))
(declare-function emacsvox-aural-cancel-pending-deliveries "emacsvox-aural-transport" (&optional process))

(cl-defstruct (omnivox--preview (:constructor omnivox--preview-create))
  process generation capabilities guard items callback observer timer pending
  response results base-rate disabled busy finished notification interrupt individual current)

(defun omnivox--preview-copy (value)
  "Copy bounded preview VALUE including mutable strings, rejecting cycles."
  (let ((nodes 0) (bytes 0) (path (make-hash-table :test #'eq)))
    (cl-labels ((walk (item depth)
                 (when (or (> (cl-incf nodes) 262144) (> depth 256))
                   (error "Preview input is too large or deeply nested"))
                 (cond
                  ((stringp item)
                   (cl-incf bytes (string-bytes item))
                   (when (> bytes (* 16 1024 1024)) (error "Preview input exceeds 16 MiB"))
                   (substring-no-properties item))
                  ((or (consp item) (vectorp item))
                   (when (gethash item path) (error "Preview input contains a cycle"))
                   (puthash item t path)
                   (prog1 (if (consp item)
                              (cons (walk (car item) (1+ depth)) (walk (cdr item) (1+ depth)))
                            (apply #'vector (mapcar (lambda (child) (walk child (1+ depth))) item)))
                     (remhash item path)))
                  ((or (null item) (symbolp item) (numberp item)) item)
                  (t (error "Unsupported preview input")))))
      (walk value 0))))

(defun omnivox--preview-command (request identifier)
  "Encode the complete REQUEST line using reserved IDENTIFIER."
  (format "omnivox_control {%s}\n"
          (omnivox--encode-control-request
           (append (list :protocol_version 1 :request_id identifier) request))))

(defun omnivox--preview-layered-request (entry process)
  "Preflight raw private ENTRY for PROCESS without flattening its cascade."
  (unless (and (process-live-p process) (omnivox--choice-tuning-supported-p process))
    (user-error "Individual tuning preview needs the complete Omnivox voice-choice bundle; saving remains available"))
  (emacsvox-aural-routing--strict-properties
   entry '(:text :voice :context :placement :selection :fallback-policy :disabled-engine-ids
                 :expected-base-rate :role :variant)
   '(:text :voice :context :placement :selection :fallback-policy :disabled-engine-ids))
  (omnivox--choice-string (plist-get entry :text) (* 16 1024))
  (let* ((voice (plist-get entry :voice))
         (style (plist-get voice :shared))
         (rows (plist-get voice :choices))
         (placement (plist-get entry :placement))
         (selection (plist-get entry :selection))
         (policy (plist-get entry :fallback-policy))
         (expected (plist-get entry :expected-base-rate)))
    (omnivox--choice-object-keys voice '(:language :shared :choices))
    (when style
      (emacsvox-aural-routing--strict-properties style emacsvox-aural--voice-style-keys nil)
      (emacsvox-aural--validate-voice-style style "Private preview shared style"))
    ;; Preset/family resolution belongs to the snapshot projector, not this codec.
    (when (or (plist-get style :preset) (plist-get style :family))
      (error "Private preview requires an explicitly resolved shared style"))
    (omnivox--preview-validate-values (list :language (plist-get voice :language)
                                          :expected-base-rate expected))
    (emacsvox-aural-routing--validate-choices rows)
    (dolist (selector (append (mapcar (lambda (row) (plist-get row :selector)) rows)
                             (when (plist-get policy :global-default)
                               (list (plist-get policy :global-default)))))
      (emacsvox-aural-routing--strict-properties
       selector '(:kind :scope :engine-id :voice-id :language :gender) '(:kind))
      (omnivox--preview-validate-selector selector))
    (omnivox--choice-object-keys placement '(:pan))
    (omnivox--choice-normalized-number (plist-get placement :pan))
    (pcase (plist-get selection :mode)
      ('automatic (omnivox--choice-object-keys selection '(:mode)))
      ('choice
       (omnivox--choice-object-keys selection '(:mode :choice-id))
       (unless (cl-find (plist-get selection :choice-id) rows :test #'equal
                        :key (lambda (row) (plist-get row :id)))
         (error "Selected preview choice is absent from the captured voice")))
      (_ (error "Invalid private preview selection")))
    (omnivox--choice-object-keys
     policy '(:preferred-engines :allow-same-language-on-requested-engine :global-default :fallback-engines))
    (when (and (plist-member entry :role) (not (memq (plist-get entry :role) '(label sample))))
      (error "Invalid private preview entry role"))
    (when (and (plist-member entry :variant) (not (memq (plist-get entry :variant) '(original edited))))
      (error "Invalid private preview comparison variant"))
    (append
     (list :type "preview_voice_v2" :text (plist-get entry :text)
           :voice (list :language (or (plist-get voice :language) :null)
                        :shared (omnivox--choice-style-json style)
                        :choices (omnivox--choice-records-json rows))
           :context (omnivox--choice-patch-json (plist-get entry :context) t)
           :placement (list :pan (omnivox--choice-normalized-number (plist-get placement :pan)))
           :selection (if (eq (plist-get selection :mode) 'automatic) '(:mode "automatic")
                        (list :mode "choice" :choice_id (plist-get selection :choice-id)))
           :fallback_policy (omnivox--preview-policy-json policy (plist-get entry :disabled-engine-ids))
           :disabled_engine_ids (vconcat (plist-get entry :disabled-engine-ids)))
     (when expected (list :expected_base_rate expected)))))

(defun omnivox--preview-identity-key (identity)
  "Return an order-independent comparison key for validated audio IDENTITY."
  (let ((reason (plist-get identity :reason)) (physical (plist-get identity :realized)))
    (list (plist-get identity :choice_id) (plist-get reason :reason)
          (or (plist-get reason :preference_index) (plist-get reason :preferred_index)
              (plist-get reason :fallback_index))
          (plist-get physical :engine_id) (plist-get physical :voice_id)
          (sort (append (plist-get identity :degraded_acss) nil) #'string-lessp)
          (sort (append (plist-get identity :degraded_effects) nil) #'string-lessp))))

(defun omnivox--preview-correlate-identity (entry identity disabled)
  "Correlate validated IDENTITY with frozen ENTRY and effective DISABLED set."
  (let* ((rows (plist-get (plist-get entry :voice) :choices))
         (id (plist-get identity :choice_id))
         (index (cl-position id rows :test #'equal :key (lambda (row) (plist-get row :id))))
         (reason (plist-get identity :reason))
         (physical (plist-get identity :realized))
         (engine (plist-get physical :engine_id))
         (policy (plist-get entry :fallback-policy))
         (selection (plist-get entry :selection))
         selector)
    (when (member engine disabled) (error "Preview reports playback on a disabled engine"))
    (when (and (eq (plist-get selection :mode) 'choice)
               (not (equal id (plist-get selection :choice-id))))
      (error "Individual audition substituted another choice"))
    (if (not (eq id :null))
        (progn
          (unless (and index
                       (pcase (plist-get reason :reason)
                         ("preferred" (= index 0))
                         ("explicit_alternative" (= index (plist-get reason :preference_index)))))
            (error "Preview identity does not match the original fallback index"))
          (setq selector (plist-get (nth index rows) :selector)))
      (pcase (plist-get reason :reason)
        ("same_language_on_requested_engine"
         (unless (and (plist-get policy :allow-same-language-on-requested-engine)
                      (plist-get (plist-get entry :voice) :language)
                      (equal engine (plist-get (plist-get (car rows) :selector) :engine-id)))
           (error "Preview identity disagrees with same-language policy")))
        ((or "preferred_engine" "fallback_engine")
         (let* ((preferred (equal (plist-get reason :reason) "preferred_engine"))
                (engines (plist-get policy (if preferred :preferred-engines :fallback-engines)))
                (position (plist-get reason (if preferred :preferred_index :fallback_index))))
           (unless (and (< position (length engines)) (equal engine (nth position engines)))
             (error "Preview identity disagrees with captured engine order"))))
        ("global_default"
         (setq selector (plist-get policy :global-default))
         (unless selector (error "Preview reports an absent global default")))))
    (when selector
      (when (and (plist-get selector :engine-id)
                 (not (equal engine (plist-get selector :engine-id))))
        (error "Preview identity disagrees with selected engine"))
      (when (and (eq (plist-get selector :kind) 'exact)
                 (not (equal (plist-get physical :voice_id) (plist-get selector :voice-id))))
        (error "Preview identity disagrees with exact physical voice")))))

(defun omnivox--normalize-layered-preview-response (entry response)
  "Validate private RESPONSE against frozen ENTRY, retaining started evidence."
  (unless (eql (plist-get response :protocol_version) 1) (error "Invalid preview envelope version"))
  (omnivox--choice-unsigned (plist-get response :request_id) nil t)
  (when (equal (plist-get response :type) "error")
    (omnivox--choice-object-keys response '(:protocol_version :request_id :type :code :message))
    (omnivox--choice-string (plist-get response :code) 128)
    (omnivox--choice-string (plist-get response :message) 1024 nil t)
    (error "Preview not confirmed: %s" (plist-get response :message)))
  (omnivox--choice-object-keys
   response '(:protocol_version :request_id :type :status :accepted_audio :accepted_audio_truncated
                               :last_started :message :base_rate :effective_disabled_engine_ids))
  (unless (and (equal (plist-get response :type) "preview_voice_completed_v2")
               (member (plist-get response :status) '("completed" "cancelled" "failed"))
               (numberp (plist-get response :base_rate)) (<= 0 (plist-get response :base_rate) 2)
               (memq (plist-get response :accepted_audio_truncated) '(t :false)))
    (error "Invalid private preview terminal metadata"))
  (omnivox--choice-string (plist-get response :message) 1024 t t)
  (let* ((accepted (plist-get response :accepted_audio))
         (last (plist-get response :last_started))
         (disabled (plist-get response :effective_disabled_engine_ids))
         (truncated (eq (plist-get response :accepted_audio_truncated) t))
         (seen (make-hash-table :test #'equal)) started)
    (unless (and (vectorp accepted) (<= (length accepted) 32) (vectorp disabled))
      (error "Invalid private preview terminal arrays"))
    (dolist (engine (append disabled nil))
      (unless (omnivox--preview-valid-id-p engine 128 "\\`[0-9A-Za-z_.-]+\\'")
        (error "Invalid private preview disabled engine")))
    (setq disabled (append disabled nil))
    (unless (= (length disabled) (length (delete-dups (copy-sequence disabled))))
      (error "Duplicate private preview disabled engine"))
    (unless (cl-subsetp (plist-get entry :disabled-engine-ids) disabled :test #'equal)
      (error "Preview omitted requested engine disablement"))
    (dolist (identity (append accepted nil))
      (omnivox--choice-audio-identity identity t)
      (omnivox--preview-correlate-identity entry identity disabled)
      (let ((key (omnivox--preview-identity-key identity)))
        (when (gethash key seen) (error "Duplicate accepted preview identity"))
        (puthash key identity seen))
      (when (eq (plist-get identity :playback_started) t) (setq started t)))
    (if (eq last :null)
        (when started (error "Started preview audio omitted its last-started identity"))
      (omnivox--choice-audio-identity last)
      (omnivox--preview-correlate-identity entry last disabled)
      (let ((retained (gethash (omnivox--preview-identity-key last) seen)))
        (unless (if retained (eq (plist-get retained :playback_started) t) truncated)
          (error "Preview last-started identity disagrees with accepted audio"))))
    (list :status (intern (plist-get response :status)) :completion-guarantee 'playback
          :terminal-confirmed t :request-snapshot (omnivox--preview-copy entry)
          :accepted-audio (omnivox--preview-copy accepted) :accepted-audio-truncated truncated
          :last-started (unless (eq last :null) (omnivox--preview-copy last))
          :base-rate (plist-get response :base_rate) :effective-disabled-engine-ids disabled
          :message (unless (eq (plist-get response :message) :null) (plist-get response :message)))))

(defun omnivox--preview-layered-sequence (entries callback &optional current)
  "Preview private ENTRIES with CALLBACK while the optional CURRENT guard holds."
  (let ((entries (omnivox--preview-copy entries)))
    (unless (and (proper-list-p entries)
                 (cl-every (lambda (entry) (and (listp entry) (plist-member entry :voice))) entries))
      (user-error "Private preview requires complete voice entries"))
    (omnivox--preview-sequence entries callback nil current)))

(defun omnivox--preview-current-p (operation)
  "Whether OPERATION still owns the frozen foreground connection and settings."
  (let ((process (omnivox--preview-process operation)))
    (and (not (omnivox--preview-finished operation))
         (eq operation (process-get process 'omnivox--preview-operation))
         (eq process tts-speaker-process) (process-live-p process)
         (not (process-get process 'tts--speech-process-retiring))
         (equal (omnivox--preview-generation operation)
                (process-get process 'tts--speech-process-generation))
         (equal (omnivox--preview-capabilities operation)
                (process-get process omnivox--control-capabilities-property))
         (or (null (omnivox--preview-current operation))
             (condition-case nil (funcall (omnivox--preview-current operation)) (error nil))))))

(defun omnivox--preview-token-operation (token)
  "Resolve private TOKEN without evaluating its possibly invalidated view guard."
  (if (omnivox--preview-p token) token
    (when (and (consp token) (processp (car token)))
      (let ((current (process-get (car token) 'omnivox--preview-operation)))
        (and current (eq (cdr token) (omnivox--preview-current current)) current)))))

(defun omnivox--preview-cancel (operation)
  "Cancel OPERATION or its (process . view-guard) startup handle.
Never interrupt a newer preview or a changed speech queue."
  (setq operation (omnivox--preview-token-operation operation))
  (when (omnivox--preview-p operation)
    (omnivox--preview-finish operation 'cancelled "Preview input changed; playback unconfirmed" t)))

(defun omnivox--preview-clear-entry (operation)
  "Detach OPERATION's pending request and timer without invoking user code."
  (let ((inhibit-quit t)
        (timer (omnivox--preview-timer operation))
        (identifier (omnivox--preview-pending operation)))
    (setf (omnivox--preview-timer operation) nil
          (omnivox--preview-pending operation) nil
          (omnivox--preview-response operation) nil)
    (when identifier
      (remhash identifier (omnivox--pending-requests (omnivox--preview-process operation))))
    (when timer (cancel-timer timer))))

(defun omnivox--preview-notify (operation)
  "Complete OPERATION's interrupt before delivering its detached callback."
  (when (and (not (omnivox--preview-busy operation))
             (omnivox--preview-finished operation))
    (let* ((process (omnivox--preview-process operation))
           (owned (eq operation (process-get process 'omnivox--preview-operation)))
           (notification (omnivox--preview-notification operation)))
      (setf (omnivox--preview-notification operation) nil)
      (when owned (process-put process 'omnivox--preview-operation nil))
      (unwind-protect
          (when (and owned (omnivox--preview-interrupt operation)
                     (eq process tts-speaker-process)
                     (tts-queue--guard-valid-p (omnivox--preview-guard operation)))
            (tts--interrupt-process process))
        (when notification
          (emacsvox-aural--call-independent-callback
           #'tts--voice-preview-callback (car notification) (cadr notification)))))))

(defun omnivox--preview-finish (operation status &optional message interrupt abandon)
  "Retire OPERATION exactly once with STATUS and MESSAGE.
INTERRUPT stops owned playback before notification. ABANDON propagates a
nonlocal caller exit without retaining an asynchronous callback."
  (unless (omnivox--preview-finished operation)
    (let ((inhibit-quit t))
      (setf (omnivox--preview-finished operation) t
            (omnivox--preview-interrupt operation) interrupt
            (omnivox--preview-notification operation)
            (unless abandon
              (list (omnivox--preview-callback operation)
                    (list :status status :completion-guarantee 'playback
                          :message message :results (nreverse (omnivox--preview-results operation)))))
            (omnivox--preview-callback operation) nil
            (omnivox--preview-current operation) nil
            (omnivox--preview-results operation) nil
            (omnivox--preview-items operation) nil)
      (omnivox--preview-clear-entry operation)
      (remove-hook 'tts-stopped-hook (omnivox--preview-observer operation))
      (let ((process (omnivox--preview-process operation)))
        (when (eq (car (process-get process 'tts--interrupt-listener)) operation)
          (process-put process 'tts--interrupt-listener nil)))
      (setf (omnivox--preview-observer operation) nil)))
  (omnivox--preview-notify operation))

(defun omnivox--preview-interrupted (operation)
  "Retire OPERATION before Stop I/O, returning its post-interrupt notification.
No user code runs until the interrupt has left its write and observer stacks."
  (let ((busy (omnivox--preview-busy operation)) (inhibit-quit t))
    (setf (omnivox--preview-busy operation) t)
    (omnivox--preview-finish operation 'cancelled)
    (lambda (completed)
      (unless completed (setf (omnivox--preview-notification operation) nil))
      (setf (omnivox--preview-busy operation) busy)
      (omnivox--preview-notify operation))))

(defun omnivox--preview-receive (operation item identifier process response)
  "Latch RESPONSE for OPERATION's exact ITEM and IDENTIFIER on PROCESS."
  (when (and (eq process (omnivox--preview-process operation))
             (eql identifier (omnivox--preview-pending operation))
             (eq item (car (omnivox--preview-items operation)))
             (not (omnivox--preview-response operation))
             (not (omnivox--preview-finished operation)))
    (let ((result
           (condition-case err
               (cond
                ((plist-member (car item) :voice) (omnivox--normalize-layered-preview-response (car item) response))
                ((omnivox--preview-individual operation)
                 (omnivox--normalize-preview-response (car item) response (nth 2 item) (nth 3 item)))
                (t (omnivox--normalize-complete-preview-response (car item) response)))
             (error (list :status 'failed :terminal-confirmed nil
                          :request-snapshot (omnivox--preview-copy (car item))
                          :message (error-message-string err))))))
      (unless (memq (plist-get result :status) '(completed cancelled failed))
        (setq result '(:status failed :message "Invalid preview status")))
      (setf (omnivox--preview-response operation) result))
    (unless (omnivox--preview-busy operation) (omnivox--preview-drive operation))))

(defun omnivox--preview-send (operation item)
  "Reserve and write OPERATION's ITEM once, latching any reentrant response."
  (let* ((process (omnivox--preview-process operation))
         (identifier (omnivox--next-control-request-id))
         (pending (omnivox--pending-requests process))
         (request (copy-tree (cadr item)))
         complete)
    (when (and (not (omnivox--preview-individual operation)) (omnivox--preview-base-rate operation))
      (setq request (plist-put request :expected_base_rate (omnivox--preview-base-rate operation))))
    (unwind-protect
        (progn
          (setf (omnivox--preview-pending operation) identifier)
          (puthash identifier (lambda (owner response)
                                (omnivox--preview-receive operation item identifier owner response)) pending)
          (let ((timer (run-at-time
                        omnivox-voice-preview-timeout nil
                        (lambda ()
                          (when (eql identifier (omnivox--preview-pending operation))
                            (omnivox--preview-finish operation 'failed
                                                     "Voice preview timed out; playback unconfirmed" t))))))
            (if (omnivox--preview-finished operation)
                (when timer (cancel-timer timer))
              (setf (omnivox--preview-timer operation) timer)))
          (when (omnivox--preview-current-p operation)
            (let ((command (omnivox--preview-command request identifier)))
              (tts-queue--send process command (tts-queue--describe command 'neutral)
                               nil (omnivox--preview-guard operation)))
            (setq complete t)))
      (unless (and complete (omnivox--preview-current-p operation))
        (remhash identifier pending)))))

(defun omnivox--preview-consume (operation)
  "Consume one validated terminal without confusing comparison metadata."
  (let ((result (omnivox--preview-response operation)))
    (omnivox--preview-clear-entry operation)
    (when (and (not (omnivox--preview-individual operation))
               (eq (plist-get result :status) 'completed))
      (let ((rate (plist-get result :base-rate))
            (disabled (sort (copy-sequence (plist-get result :effective-disabled-engine-ids)) #'string-lessp)))
        (if (omnivox--preview-base-rate operation)
            (unless (and (= rate (omnivox--preview-base-rate operation))
                         (equal disabled (omnivox--preview-disabled operation)))
              (setq result (plist-put result :status 'failed))
              (setq result (plist-put result :message "Comparison policy changed; restart comparison")))
          (setf (omnivox--preview-base-rate operation) rate
                (omnivox--preview-disabled operation) disabled))))
    (push result (omnivox--preview-results operation))
    (pop (omnivox--preview-items operation))
    (unless (eq (plist-get result :status) 'completed)
      (omnivox--preview-finish operation (plist-get result :status) (plist-get result :message)))))

(defun omnivox--preview-drive (operation)
  "Advance OPERATION outside actual writes, with one outstanding entry."
  (let (returned failure waiting)
    (setf (omnivox--preview-busy operation) t)
    (unwind-protect
        (progn
          (condition-case err
              (while (and (not waiting) (not (omnivox--preview-finished operation)))
                (cond
                 ((not (omnivox--preview-current-p operation))
                  (omnivox--preview-finish operation 'cancelled "Preview connection or settings changed" t))
                 ((not (tts-queue--guard-valid-p (omnivox--preview-guard operation)))
                  (error "Speech input changed during preview; playback unconfirmed"))
                 ((omnivox--preview-response operation) (omnivox--preview-consume operation))
                 ((omnivox--preview-pending operation) (setq waiting t))
                 ((omnivox--preview-items operation)
                  (omnivox--preview-send operation (car (omnivox--preview-items operation))))
                 (t (omnivox--preview-finish operation 'completed))))
            (error (setq failure err)
                   (omnivox--preview-finish operation 'failed (error-message-string err))))
          (setq returned t))
      (unless returned (omnivox--preview-finish operation 'cancelled nil nil t))
      (setf (omnivox--preview-busy operation) nil)
      (omnivox--preview-notify operation))
    (when (and failure (omnivox--preview-individual operation))
      (signal (car failure) (cdr failure)))))

(defun omnivox--preview-sequence (entries callback individual &optional current)
  "Preflight ENTRIES, then own their preview until CALLBACK or cancellation.
INDIVIDUAL retains the legacy exact-audition wire and response shape.
CURRENT is an optional pure view/revision predicate. Return the operation token."
  (let* ((process tts-speaker-process)
         (previous (and (processp process) (process-get process 'omnivox--preview-operation)))
         (generation (and (processp process) (process-get process 'tts--speech-process-generation)))
         (epoch (and (processp process) (process-get process 'tts--dispatch-cancellation-epoch)))
         (guard (and (processp process) (tts-queue--startup-guard process)))
         (capabilities (and (processp process)
                            (omnivox--preview-copy (process-get process omnivox--control-capabilities-property))))
         (entries (omnivox--preview-copy entries))
         (bytes 0) items operation returned failure)
    (unless (and (proper-list-p entries) (<= 1 (length entries) 64))
      (user-error "Preview requires between one and 64 entries"))
    (unless (or (null current) (and (functionp current) (funcall current)))
      (user-error "Preview view or input changed"))
    (when (> (+ omnivox--control-request-sequence (length entries)) omnivox--choice-u64-max)
      (user-error "Omnivox control request IDs exhausted"))
    (unless (and (numberp omnivox-voice-preview-timeout) (> omnivox-voice-preview-timeout 0)
                 (< omnivox-voice-preview-timeout 1.0e+INF))
      (user-error "Preview timeout must be a positive finite number"))
    (dolist (entry entries)
      (unless (and (eq (and (plist-member entry :selector) t) (and individual t))
                   (eq (and (plist-member entry :voice) t)
                       (and (plist-member (car entries) :voice) t)))
        (user-error "A comparison must use the same preview form for every entry"))
      (let* ((request (cond ((plist-member entry :voice) (omnivox--preview-layered-request entry process))
                            (individual (omnivox--preview-individual-request entry process))
                            (t (omnivox--preview-complete-request entry process))))
             (bounded (copy-tree request)))
        (unless individual (setq bounded (plist-put bounded :expected_base_rate 1.2345678901234567)))
        (let ((command (omnivox--preview-command bounded omnivox--choice-u64-max)))
          ;; Reserve extra numeric spelling space for any finite host rate.
          (when (> (+ 64 (string-bytes (base64-decode-string
                                       (substring command (length "omnivox_control {") -2))))
                   omnivox-control-max-payload-bytes)
            (user-error "Preview envelope leaves no room for comparison metadata"))
          (cl-incf bytes (+ 128 (string-bytes command))))
        (when (> bytes (* 16 1024 1024)) (user-error "Preview sequence exceeds 16 MiB"))
        (push (list entry request
                    (omnivox--process-supports-p process "post_synthesis_effects_v1")
                    (omnivox--process-supports-p process "relative_rate_v1")) items)))
    (unless (and (eq process tts-speaker-process) (process-live-p process)
                 (equal generation (process-get process 'tts--speech-process-generation))
                 (equal epoch (process-get process 'tts--dispatch-cancellation-epoch))
                 (equal capabilities (process-get process omnivox--control-capabilities-property))
                 (eq previous (process-get process 'omnivox--preview-operation))
                 (or (null current) (funcall current)))
      (user-error "Preview connection or input changed during preflight"))
    (unless (and guard (tts-queue--guard-valid-p guard))
      (user-error "Preview needs an unchanged, proven speech input boundary"))
    (setq operation (omnivox--preview-create
                     :process process :generation generation :capabilities capabilities :guard guard
                     :items (nreverse items) :callback callback :individual individual :busy t :current current))
    (setf (omnivox--preview-observer operation)
          (lambda (owner)
            (when (eq owner process)
              (omnivox--preview-finish operation (if (process-live-p process) 'cancelled 'failed)))))
    (unwind-protect
        (progn
          (process-put process 'omnivox--preview-operation operation)
          (process-put process 'tts--interrupt-listener
                       (list operation (lambda () (omnivox--preview-interrupted operation))))
          (add-hook 'tts-stopped-hook (omnivox--preview-observer operation))
          (when previous (omnivox--preview-finish previous 'cancelled))
          (condition-case err
              (when (omnivox--preview-current-p operation)
                (emacsvox-aural-cancel-pending-deliveries process)
                (when (omnivox--preview-current-p operation)
                  (tts--interrupt-process process nil nil
                                          (list (omnivox--preview-guard operation)
                                                (omnivox--preview-observer operation) operation))))
            (error (setq failure err)
                   (omnivox--preview-finish operation 'failed (error-message-string err))))
          (setq returned t))
      (unless returned (omnivox--preview-finish operation 'cancelled nil nil t))
      (setf (omnivox--preview-busy operation) nil)
      (omnivox--preview-notify operation))
    (unless (omnivox--preview-finished operation) (omnivox--preview-drive operation))
    (when (and failure individual) (signal (car failure) (cdr failure)))
    operation))

(provide 'omnivox-preview)
;;; omnivox-preview.el ends here
