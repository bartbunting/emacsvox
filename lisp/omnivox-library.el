;;; omnivox-library.el --- Local installed voices and Apply -*- lexical-binding: t; -*-

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

;; The bundled local launcher resolves a native owner for each speech lane.
;; Private stdio management holds the profile lease across paired Apply.
;; Startup records live on the native host; no remote management is provided.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-ui)
(require 'omnivox-engine-settings)
(require 'omnivox-library-apply)

(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar tts-notification-device)
(defvar tts--speech-process-generation-property)
(defvar omnivox--control-inventory-property)
(defvar omnivox--control-capabilities-property)
(defvar omnivox--logical-registry-generation)
(defvar omnivox--control-registration-property)
(defvar omnivox-engine-inventory)
(declare-function omnivox--send-control-request "omnivox-voices" (process request callback))
(declare-function omnivox--pending-requests "omnivox-voices" (process))
(declare-function omnivox--install-control-filter "omnivox-voices" (process))
(declare-function omnivox--process-routing-policy-current-p "omnivox-voices" (process))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--routing-registration-policy "omnivox-voices" (registration))
(declare-function omnivox--process-routing-registration "omnivox-voices" (process))
(declare-function omnivox--negotiate-process "omnivox-voices" (process))
(declare-function omnivox--registration-request "omnivox-voices" (generation content))
(declare-function omnivox--accept-registration-response "omnivox-voices" (process response generation content))
(declare-function omnivox--routing-policy-content "omnivox-voices" (process))
(declare-function omnivox--process-logical-registry-content "omnivox-voices" (process))
(defvar omnivox--library-startup nil "Dynamically bound native startup record.")
(defvar omnivox-library--birth-collector nil "Provider callback retaining every attempted process.")
(defvar omnivox-library--support-cache nil)
(defvar omnivox-library--sequence 0)
(defvar omnivox-library--busy nil)
(defvar omnivox-library-last-result nil "Most recent local Apply result.")
(defvar-local omnivox-library--engine nil)
(defvar-local omnivox-library--index nil)
(defvar-local omnivox-library--index-sha nil)
(defconst omnivox-library--prefix "OMNIVOX-LOCAL ")
(defconst omnivox-library--timeout 45)

(defun omnivox-library--wait (predicate process description &optional seconds)
  "Wait boundedly for PREDICATE from PROCESS, describing failure with DESCRIPTION."
  (let ((deadline (+ (float-time) (or seconds omnivox-library--timeout))))
    (while (not (funcall predicate))
      (unless (and (process-live-p process)
                   (not (process-get process 'omnivox-library-retired))
                   (< (float-time) deadline))
        (error "%s: process exited or deadline expired" description))
      (accept-process-output process 0.05))))

(defun omnivox-library--supported-p (program)
  "Check PROGRAM's ordinary help before using its local owner extension."
  (and (omnivox-engine-settings--supported-p)
       (let* ((key (list program (getenv "OMNIVOX_PROGRAM")
                         (file-attribute-modification-time (file-attributes program))))
              (cached (assoc key omnivox-library--support-cache)))
         (if cached (cdr cached)
           (let ((buffer (generate-new-buffer " *Omnivox local capability*")) process supported)
             (unwind-protect
                 (condition-case nil
                     (progn
                       (setq process (make-process :name "Omnivox local capability"
                                                   :buffer buffer :command (list program "--help")
                                                   :connection-type 'pipe :noquery t))
                       (let ((deadline (+ (float-time) 5)))
                         (while (and (process-live-p process) (< (float-time) deadline))
                           (accept-process-output process 0.05)))
                       (setq supported
                             (and (eq (process-status process) 'exit)
                                  (zerop (process-exit-status process))
                                  (with-current-buffer buffer
                                    (string-match-p "--voice-library-owner" (buffer-string))))))
                   (error nil))
               (when (process-live-p process) (delete-process process))
               (kill-buffer buffer))
             (push (cons key (and supported t)) omnivox-library--support-cache)
             supported)))))

(defun omnivox-library--command (program)
  "Build PROGRAM's local startup command, retaining older-server compatibility."
  (if (or omnivox--library-startup (omnivox-library--supported-p program))
      (list program "--voice-library-owner") (list program)))

(defun omnivox-library--startup-environment (environment)
  "Extend ENVIRONMENT with frozen native inputs during explicit Apply."
  (let ((process-environment (copy-sequence environment)))
    (when omnivox--library-startup
      (setenv "OMNIVOX_OWNED_STARTUP" (plist-get omnivox--library-startup :path))
      (setenv "OMNIVOX_OWNED_STARTUP_SHA256" (plist-get omnivox--library-startup :sha256))
      (setenv "OMNIVOX_OWNED_LIBRARY" (plist-get omnivox--library-startup :candidate)))
    process-environment))

(defun omnivox-library--handle-line (process line)
  "Consume a local owner response LINE from its exact PROCESS connection."
  (when (string-prefix-p omnivox-library--prefix line)
    (when (> (string-bytes line) (* 2 1024 1024)) (error "Local response is too large"))
    (let* ((response (json-parse-string (substring line (length omnivox-library--prefix))
                                      :object-type 'plist :array-type 'array
                                      :null-object :null :false-object :false))
           (pending (process-get process 'omnivox-library-pending))
           (callback (and pending (gethash (plist-get response :request_id) pending))))
      (when (and (equal (plist-get response :type) "retired")
                 (equal (plist-get response :worker)
                        (plist-get (process-get process 'omnivox-library-owner) :worker)))
        (process-put process 'omnivox-library-retired t))
      (when callback
        (remhash (plist-get response :request_id) pending)
        (funcall callback response)))
    t))

(defun omnivox-library--service-filter (process output)
  "Consume bounded local-service OUTPUT from PROCESS."
  (let ((text (concat (or (process-get process 'omnivox-library-fragment) "") output)))
    (when (> (string-bytes text) (* 4 1024 1024)) (error "Local service output exceeds bound"))
    (while (string-match "\n" text)
      (let ((end (match-beginning 0)))
        (unless (omnivox-library--handle-line process (substring text 0 end))
          (error "Unexpected local service output"))
        (setq text (substring text (1+ end)))))
    (process-put process 'omnivox-library-fragment text)))

(defun omnivox-library--service (&optional role)
  "Start private management on this session's selected local native target."
  (require 'omnivox-voices)
  (let ((program (tts--resolve-program tts-program)))
    (unless (and program (omnivox-library--supported-p program))
      (user-error "Installed voices require the updated bundled local Omnivox launcher"))
    (let ((process-environment (omnivox-engine-settings--environment program)))
      (when (eq role 'notification)
        (dolist (variable '("ALSA_DEFAULT" "SWIFTMAC_AUDIO_TARGET" "SHARPWIN_AUDIO_TARGET" "PULSE_SINK"))
          (setenv variable tts-notification-device))
        (setenv "OMNIVOX_AUDIO_TARGET" (tts--notification-omnivox-audio-target)))
      (make-process :name "Omnivox voice library" :command (list program "--voice-library-service")
                    :connection-type 'pipe :coding 'utf-8-unix :noquery t
                    :filter #'omnivox-library--service-filter
                    :stderr (get-buffer-create "*Omnivox voice library diagnostics*")))))

(defun omnivox-library--candidate-startup (generation role process)
  "Resolve native inputs for GENERATION and ROLE using PROCESS voice policy."
  (let ((service (omnivox-library--service role)))
    (unwind-protect
        (let ((snapshot (omnivox-library--request service (list :command "snapshot" :generation generation))))
          (unless (equal (plist-get snapshot :type) "snapshot") (error "Missing native candidate snapshot"))
          (list :role role :startup
                (list :path (plist-get snapshot :startup) :sha256 (plist-get snapshot :startup_sha256)
                      :policy (omnivox--routing-policy-content process)
                      :registration (omnivox--process-logical-registry-content process))))
      (when (process-live-p service) (delete-process service)))))

(defun omnivox-library--request (process command &optional owner)
  "Send COMMAND on PROCESS and return its correlated response.
OWNER sends the private prefix through the speech queue."
  (let* ((id (cl-incf omnivox-library--sequence))
         (pending (or (process-get process 'omnivox-library-pending)
                      (let ((table (make-hash-table :test #'eql)))
                        (process-put process 'omnivox-library-pending table) table)))
         response
         (line (concat (when owner omnivox-library--prefix)
                       (json-serialize (append (list :request_id id) command)
                                       :null-object :null :false-object :false) "\n")))
    (puthash id (lambda (reply) (setq response reply)) pending)
    (unwind-protect
        (progn
          (if owner (tts-queue--send-typed process line 'neutral) (process-send-string process line))
          (omnivox-library--wait (lambda () response) process (plist-get command :command))
          (when (equal (plist-get response :type) "error")
            (error "%s" (plist-get response :message)))
          response)
      (remhash id pending))))

(defun omnivox-library--control (process command)
  "Obtain a correlated ordinary control response for COMMAND on PROCESS."
  (let (response id)
    (setq id (omnivox--send-control-request process command
                                          (lambda (source result)
                                            (when (eq source process) (setq response result)))))
    (unwind-protect
        (progn
          (omnivox-library--wait (lambda () response) process (plist-get command :type))
          (when (equal (plist-get response :type) "error") (error "%s" (plist-get response :message)))
          response)
      (when id (remhash id (omnivox--pending-requests process))))))

(defun omnivox-library--owner (process)
  "Obtain the native owner and frozen startup of live speech PROCESS."
  (unless (and (process-live-p process)
               (member "--voice-library-owner" (process-command process)))
    (user-error "This speech session predates native ownership; restart speech with the updated build first"))
  (omnivox--install-control-filter process)
  (let ((owner (omnivox-library--request process '(:command "describe") t)))
    (unless (equal (plist-get owner :type) "owner") (error "Missing native speech owner"))
    (omnivox-library-apply--uuid (plist-get owner :worker))
    (process-put process 'omnivox-library-owner owner)
    (when (eq (plist-get owner :retired) t)
      (process-put process 'omnivox-library-retired t))
    owner))

(defun omnivox-library--proof (process role)
  "Read readiness and library status from this exact PROCESS and ROLE."
  (unless (and (process-get process omnivox--control-registration-property)
               (omnivox--process-routing-policy-current-p process))
    (error "Speech routing and logical registration are not ready"))
  (unless (omnivox--process-supports-p process "voice_library_v1")
    (error "Speech worker does not advertise voice_library_v1"))
  (let* ((inventory (omnivox-library--control process '(:type "inventory")))
         (status (omnivox-library--control process '(:type "voice_library_status_v1")))
         (owner (omnivox-library--owner process)))
    (unless (= (plist-get inventory :inventory_generation) (plist-get status :inventory_generation))
      (error "Inventory changed during Apply verification"))
    (unless (equal (plist-get owner :configuration) (plist-get status :configuration))
      (error "Native owner and speech worker configurations differ"))
    (list :role role :worker (plist-get owner :worker) :ready t :negotiated t
          :inventory-generation (plist-get inventory :inventory_generation)
          :request-id (plist-get status :request_id) :status status)))

(defun omnivox-library--snapshot (process role)
  "Freeze ROLE's actual native and acknowledged Emacs settings on PROCESS."
  (let* ((proof (omnivox-library--proof process role))
         (owner (process-get process 'omnivox-library-owner))
         (registration (process-get process 'omnivox-library-accepted-registration))
         (status (plist-get proof :status)))
    (unless registration (error "Actual logical registration is not retained; restart speech first"))
    (list :role role :worker (plist-get owner :worker)
          :startup (list :path (plist-get owner :startup) :sha256 (plist-get owner :startup_sha256)
                         :policy (omnivox-library--policy-snapshot process)
                         :registration (tts--dispatch-copy-data registration))
          :configuration (plist-get status :configuration)
          :overridden-engines (plist-get status :overridden_engines)
          :eligible-voices (plist-get status :eligible_voices))))

(defun omnivox-library--policy-snapshot (process)
  "Freeze PROCESS's acknowledged policy using wire arrays, including empty ones."
  (let ((policy (omnivox--routing-registration-policy (omnivox--process-routing-registration process))))
    (unless policy (error "Actual routing policy has not been acknowledged"))
    (cl-loop for field in '(:preferred_engine_ids :fallback_engine_ids :disabled_engine_ids)
             append (list field (vconcat (plist-get policy field))))))

(defun omnivox-library--ready (process startup)
  "Establish ordinary readiness on PROCESS with frozen STARTUP settings."
  (let ((registration (tts--dispatch-copy-data (plist-get startup :registration))))
    (when (plist-member registration :choice-process-generation)
      (setq registration (plist-put registration :choice-process-generation
                                    (process-get process tts--speech-process-generation-property))))
    (process-put process 'omnivox-library-frozen-policy (plist-get startup :policy))
    (process-put process 'omnivox-library-frozen-registration registration)
    (omnivox--negotiate-process process)
    (omnivox-library--wait
     (lambda () (and (process-get process omnivox--control-inventory-property)
                     (omnivox--process-routing-policy-current-p process))) process "Speech routing readiness")
    (let* ((generation (cl-incf omnivox--logical-registry-generation))
           (response (omnivox-library--control process (omnivox--registration-request generation registration))))
      (unless (omnivox--accept-registration-response process response generation registration)
        (error "Logical registration was not accepted")))))

(defun omnivox-library--retire (process)
  "Retire PROCESS only after obtaining native tree and pipe cleanup evidence."
  (unless (process-get process 'omnivox-library-retired)
    (let* ((owner (or (process-get process 'omnivox-library-owner) (omnivox-library--owner process)))
         (worker (plist-get owner :worker))
         (receipt (omnivox-library--request process (list :command "retire" :worker worker) t)))
    (unless (and (equal (plist-get receipt :type) "retired")
                 (equal worker (plist-get receipt :worker)))
      (error "Native retirement was not confirmed"))
      (process-put process 'omnivox-library-retired t)))
  (tts--retire-process process))

(defun omnivox-library--json-data (value)
  "Convert frozen coordinator VALUE into plain JSON data for native storage."
  (cond
   ((memq value '(t :null :false)) value)
   ((null value) :null)
   ((symbolp value) (symbol-name value))
   ((vectorp value) (vconcat (mapcar #'omnivox-library--json-data value)))
   ((and (listp value) (keywordp (car value)))
    (cl-loop for (key item) on value by #'cddr append
             (list key (omnivox-library--json-data item))))
   ((listp value) (vconcat (mapcar #'omnivox-library--json-data value)))
   (t value)))

(defun omnivox-library--json (value)
  "Serialize frozen VALUE without evaluating or printing native startup secrets."
  (json-serialize (omnivox-library--json-data value) :null-object :null :false-object :false))

(defun omnivox-library--uuid ()
  "Allocate a fresh client operation identifier. Native ownership is separate."
  (let ((hex (secure-hash 'sha256 (format "%s/%s/%s/%s" (emacs-pid) (current-time) (random) (cl-incf omnivox-library--sequence)))))
    (format "%s-%s-4%s-8%s-%s" (substring hex 0 8) (substring hex 8 12)
            (substring hex 13 16) (substring hex 17 20) (substring hex 20 32))))

(defun omnivox-library--configuration (pointer)
  "Extract configuration from native active POINTER, preserving explicit null."
  (if (eq pointer :null) :null
    (list :target_id (plist-get pointer :target_id) :profile_id (plist-get pointer :profile_id)
          :generation_id (plist-get pointer :generation_id) :sha256 (plist-get pointer :sha256))))

(defun omnivox-library--eligible (index previous providers policy)
  "Project INDEX and unmanaged PREVIOUS eligibility for PROVIDERS and POLICY."
  (let ((disabled (append (plist-get index :disabled_physical_ids) nil))
        (engines (append (plist-get policy :disabled_engine_ids) nil))
        (voices (seq-remove (lambda (id) (member (plist-get id :engine_id) providers)) previous)))
    (seq-doseq (row (plist-get index :voices))
      (when (and (member (plist-get row :engine_id) providers)
                 (eq (plist-get row :enabled) t))
        (push (list :engine_id (plist-get row :engine_id) :voice_id (plist-get row :physical_id)) voices)))
    (vconcat
     (sort (seq-remove (lambda (id) (or (member id disabled) (member (plist-get id :engine_id) engines))) voices)
           (lambda (a b) (string< (concat (plist-get a :engine_id) "\0" (plist-get a :voice_id))
                                  (concat (plist-get b :engine_id) "\0" (plist-get b :voice_id))))))))

(defvar omnivox-library--retained-service nil "Native lease retained after an uncertain Apply.")
(defvar omnivox-library--retained-processes nil "Actual processes retained for failed Apply inspection.")

(defun omnivox-library--execute (service plan old-pair)
  "Execute reviewed PLAN using SERVICE and the exact original OLD-PAIR.
All attempted replacement processes remain owned until retirement is confirmed."
  (let ((operation (omnivox-library-apply--begin plan))
        (pair (vector nil nil)) (probes (vector nil nil)) (proofs nil)
        cleanup-failed admission-requested
        (previous (plist-get plan :previous-lanes))
        (candidate (plist-get plan :candidate-startup))
        (omnivox-library--busy t)
        (inhibit-quit t))
    (cl-labels
        ((workers (processes)
           (vconcat (cl-loop for process across processes for role in '(speaker notification)
                            collect (list :role role :worker (plist-get (omnivox-library--owner process) :worker)))))
         (retire (processes)
           (let (failures)
             (seq-doseq (process processes)
               (when process
                 (condition-case error-data (omnivox-library--retire process)
                   (error (setq cleanup-failed t)
                          (push (error-message-string error-data) failures)))))
             (when failures (error "%s" (string-join (nreverse failures) "; ")))))
         (start (processes startups)
           (dotimes (index 2)
             (let ((omnivox--library-startup (plist-get (aref startups index) :startup))
                   (omnivox-library--birth-collector (lambda (process) (aset processes index process))))
               ;; Record each attempt before any readiness check can fail.
               (aset processes index (tts-make-process (if (= index 0) "Speaker" "Notify"))))))
         (verify (processes startups)
           (vconcat
            (cl-loop for process across processes for startup across startups
                     for role in '(speaker notification) collect
                     (progn
                       (omnivox-library--ready process (plist-get startup :startup))
                       (omnivox-library--proof process role)))))
         (publish ()
           (setq tts-speaker-process (aref pair 0) tts-notify-process (aref pair 1))
           (seq-doseq (process pair)
             (process-put process 'omnivox-library-frozen-policy nil)
             (process-put process 'omnivox-library-frozen-registration nil)
             (let ((tts-speaker-process process)) (tts--protocol-sync)))
           (setq omnivox-engine-inventory (process-get tts-speaker-process omnivox--control-inventory-property))
           ;; Inventory arrived during preflight, before these workers became
           ;; the current pair.  Views must now capture the published pair.
           (condition-case err
               (run-hooks 'tts-voice-inventory-changed-hook)
             (error (message "Voices applied; display refresh failed: %s" (error-message-string err)))))
         (action (action)
           (pcase (plist-get action :phase)
             ('preflight
              (setq admission-requested t)
              (omnivox-library--request service (list :command "begin" :operation (plist-get plan :operation-id)
                                                     :generation (plist-get (plist-get plan :candidate) :generation_id)
                                                     :plan_json (omnivox-library--json plan)))
              (unwind-protect
                  (progn (start probes candidate) (setq proofs (verify probes candidate))
                         (seq-doseq (proof proofs)
                           (when-let* ((overrides (seq-intersection
                                                  (plist-get (plist-get proof :status) :overridden_engines)
                                                  (plist-get (plist-get plan :impact) :providers) #'equal)))
                             (error "Explicit %s file settings override installed voices; resolve them in engine settings before Apply"
                                    (string-join (append overrides nil) ", "))))
                         (let ((ids (workers probes)))
                           (retire probes)
                           (list :ok t :workers ids :proofs proofs :quiescent t)))
                (retire probes)))
             ('activating
              (unless (and (eq (aref old-pair 0) tts-speaker-process)
                           (eq (aref old-pair 1) tts-notify-process))
                (error "Speech pair changed during Apply review"))
              (dotimes (index 2)
                (unless (omnivox-library-apply--equal
                         (aref previous index)
                         (omnivox-library--snapshot (aref old-pair index) (if (= index 0) 'speaker 'notification)))
                  (error "Actual speech settings changed during preflight")))
              (omnivox-library--request service '(:command "activating"))
              (list :ok t :previous-active (plist-get plan :previous-active)
                    :index-sha256 (plist-get plan :index-sha256) :previous-lanes previous))
             ('retire-old (retire old-pair) '(:ok t :quiescent t))
             ('start-candidate (start pair candidate) (list :ok t :workers (workers pair)))
             ('verify-candidate (setq proofs (verify pair candidate)) (list :ok t :proofs proofs))
             ('commit
              (seq-doseq (process pair)
                (unless (and (process-live-p process) (not (process-get process 'omnivox-library-retired)))
                  (error "Verified speech worker exited before commit")))
              (let* ((wire (vconcat
                            (mapcar (lambda (proof)
                                      (list :role (symbol-name (plist-get proof :role)) :worker (plist-get proof :worker)
                                            :ready t :negotiated t :inventory_generation (plist-get proof :inventory-generation)
                                            :request_id (plist-get proof :request-id) :status (plist-get proof :status))) proofs)))
                     (reply (omnivox-library--request service (list :command "commit" :proofs_json (omnivox-library--json wire)))))
                (unless (and (equal (plist-get reply :type) "committed")
                             (equal (plist-get reply :configuration) (plist-get plan :candidate)))
                  (error "Native commit response differs from the candidate"))
                (omnivox-library--request service '(:command "finish" :state "succeeded"))
                (publish)
                (list :ok t :commit 'committed :active (plist-get plan :candidate))))
             ('rolling-back
              (omnivox-library--request service '(:command "rolling-back"))
              (list :ok t :previous-active (plist-get plan :previous-active)))
             ('retire-candidate (retire pair) (setq pair (vector nil nil)) '(:ok t :quiescent t))
             ('start-previous (start pair previous) (list :ok t :workers (workers pair)))
             ('verify-previous (setq proofs (verify pair previous)) (list :ok t :proofs proofs))
             ('finish
              (when cleanup-failed
                (error "Native cleanup is unconfirmed; the profile lease and attempts remain retained"))
              (let ((state (plist-get action :final)))
                ;; Cancellation before preflight has no native transaction.
                ;; Once begin was sent, never assume a missing reply means that
                ;; no lease or journal exists.
                (when admission-requested
                  (omnivox-library--request service (list :command "finish" :state (symbol-name state))))
                (when (eq state 'rolled-back) (publish))
                (list :ok t :state state))))))
      (while (not (omnivox-library-apply--operation-result operation))
        (when quit-flag
          (setq quit-flag nil)
          (omnivox-library-apply--cancel operation))
        (let* ((next (omnivox-library-apply--action operation))
               (receipt
                (condition-case error-data
                    (action next)
                  (quit
                   (omnivox-library-apply--cancel operation)
                   ;; Complete cleanup/rollback even after C-g. Never strand a
                   ;; native request or abandon a partially started pair.
                   (setq inhibit-quit t quit-flag nil)
                   '(:ok nil :message "Apply cancelled"))
                  (error (list :ok nil :message (error-message-string error-data))))))
          (omnivox-library-apply--complete operation (plist-get next :operation-id)
                                         (plist-get next :ticket) (plist-get next :phase) receipt)))
      (setq omnivox-library-last-result (omnivox-library-apply--operation-result operation))
      (when (memq (plist-get omnivox-library-last-result :status) '(interrupted recovery-failed))
        (setq omnivox-library--retained-service service
              omnivox-library--retained-processes (append old-pair probes pair nil)))
      omnivox-library-last-result)))

;;;###autoload
(defun omnivox-library-apply (providers)
  "Review and apply installed enabled voices for PROVIDERS to both speech lanes."
  (interactive (list "both"))
  (when (or omnivox-library--busy (process-live-p omnivox-library--retained-service))
    (user-error "An Apply is active or needs inspection; see omnivox-library-last-result"))
  (unless (and (process-live-p tts-speaker-process) (process-live-p tts-notify-process)
               (not (eq tts-speaker-process tts-notify-process)))
    (user-error "Apply requires separate live main and notification speech processes"))
  (let ((service (omnivox-library--service))
        (old-pair (vector tts-speaker-process tts-notify-process)))
    (unwind-protect
        (let* ((library (omnivox-library--request service '(:command "inspect")))
               (index (plist-get library :index))
               (managed (if (equal providers "both") '("piper" "flite") (list providers)))
               (previous (vector (omnivox-library--snapshot (aref old-pair 0) 'speaker)
                                 (omnivox-library--snapshot (aref old-pair 1) 'notification)))
               (generation (omnivox-library--uuid))
               (staged (omnivox-library--request service
                                                (list :command "stage" :generation generation
                                                      :expected_sha256 (plist-get library :sha256)
                                                      :piper (if (member "piper" managed) t :false)
                                                      :flite (if (member "flite" managed) t :false))))
               (candidate (plist-get staged :candidate))
               (startups
                (vector (omnivox-library--candidate-startup generation 'speaker (aref old-pair 0))
                        (omnivox-library--candidate-startup generation 'notification (aref old-pair 1))))
               (eligible (omnivox-library--eligible index (append (plist-get (aref previous 0) :eligible-voices) nil)
                                                    managed (plist-get (plist-get (aref startups 0) :startup) :policy)))
               (removed (seq-difference (plist-get (aref previous 0) :eligible-voices) eligible #'equal))
               (plan (list :operation-id (omnivox-library--uuid) :candidate (plist-get candidate :configuration)
                           :previous-active (omnivox-library--configuration (plist-get library :active))
                           :index-sha256 (plist-get library :sha256)
                           :overridden-engines (vconcat (seq-remove (lambda (id) (member id managed))
                                                                   (plist-get (aref previous 0) :overridden-engines)))
                           :eligible-voices eligible :previous-lanes previous :candidate-startup startups
                           :impact (list :providers (vconcat managed) :removed (vconcat removed)))))
          (with-current-buffer (get-buffer-create "*Omnivox Apply review*")
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (format "Apply enabled %s voices\n\nBoth speech streams will stop and restart.\nFiles and saved palette references are retained.\n\nVoices becoming unavailable: %d\n" providers (length removed)))
              (seq-doseq (voice removed) (insert (format "%s: %s\n" (plist-get voice :engine_id) (plist-get voice :voice_id))))
              (insert "\nIf either replacement fails, both previous configurations will be restored.\n")
              (special-mode)))
          (display-buffer "*Omnivox Apply review*")
          (when (yes-or-no-p (format "Apply %s voices and restart both speech streams? " providers))
            (let ((result (omnivox-library--execute service plan old-pair)))
              (message "Voice library: %s%s" (plist-get result :status)
                       (if-let* ((failures (plist-get result :failures)))
                           (format "; %s" (plist-get (car failures) :reason)) ""))
              result)))
      (unless (eq service omnivox-library--retained-service)
        (when (process-live-p service) (delete-process service))))))

(defconst omnivox-library--empty-help
  "No voices have been added to this library.

This screen lists managed voices, including disabled voices.
Press d to browse downloadable voices.
Press b to add the bundled Flite SLT voice, then a to review Apply.
Press q to return to engine details.
"
  "Explanation displayed when the managed voice library is empty.")

(defun omnivox-library-refresh ()
  "Refresh installed metadata without loading models or changing speech."
  (interactive)
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (let ((reply (omnivox-library--request service '(:command "inspect"))))
          (setq omnivox-library--index (plist-get reply :index)
                omnivox-library--index-sha (plist-get reply :sha256)
                tabulated-list-entries
                (mapcar (lambda (row)
                          (list (cons (plist-get row :engine_id) (plist-get row :physical_id))
                                (vector (plist-get row :engine_id) (plist-get row :display_name)
                                        (if (eq (plist-get row :enabled) t) "Enabled" "Disabled")
                                        (plist-get row :physical_id))))
                        (seq-filter (lambda (row)
                                      (or (null omnivox-library--engine)
                                          (equal omnivox-library--engine (plist-get row :engine_id))))
                                    (plist-get omnivox-library--index :voices))))
          (tabulated-list-print t)
          (unless tabulated-list-entries
            (let ((inhibit-read-only t))
              (insert (if (equal omnivox-library--engine "piper")
                          "No Piper voices have been added.\n\nPress d to browse downloadable voices; q returns to engine details.\n"
                        omnivox-library--empty-help))
              (goto-char (point-min)))))
      (when (process-live-p service) (delete-process service)))))

(defun omnivox-library-toggle ()
  "Toggle desired enablement of the installed voice at point. Apply is separate."
  (interactive)
  (let* ((id (or (tabulated-list-get-id) (user-error "No installed voice on this row")))
         (row (seq-find (lambda (row) (and (equal (car id) (plist-get row :engine_id))
                                           (equal (cdr id) (plist-get row :physical_id))))
                        (plist-get omnivox-library--index :voices)))
         (service (omnivox-library--service)))
    (unwind-protect
        (omnivox-library--request service (list :command "enable" :engine (car id) :voice (cdr id)
                                               :enabled (if (eq (plist-get row :enabled) t) :false t)
                                               :expected_sha256 omnivox-library--index-sha))
      (when (process-live-p service) (delete-process service)))
    (omnivox-library-refresh)
    (message "Desired enablement saved; press a to review and Apply")))

(defun omnivox-library-import-validated (operation)
  "Install a successfully validated native OPERATION, initially disabled."
  (interactive "sNative validation operation UUID: ")
  (omnivox-library-apply--uuid operation)
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (omnivox-library--request service (list :command "import" :operation operation
                                               :package (omnivox-library--uuid) :revision (omnivox-library--uuid)
                                               :expected_sha256 omnivox-library--index-sha))
      (when (process-live-p service) (delete-process service))))
  (omnivox-library-refresh)
  (message "Voices installed disabled; original files retained"))

(defun omnivox-library-include-flite-slt ()
  "Include built-in Flite SLT in desired state, enabled for the next Apply."
  (interactive)
  (when (equal omnivox-library--engine "piper")
    (user-error "Bundled SLT belongs to Flite; open the Flite library to add it"))
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (omnivox-library--request service (list :command "include-flite-slt"
                                               :expected_sha256 omnivox-library--index-sha))
      (when (process-live-p service) (delete-process service))))
  (omnivox-library-refresh)
  (message "Built-in Flite SLT included and enabled for the next Apply"))

(defun omnivox-library-show-result ()
  "Show the last Apply outcome and any retained native process attempts."
  (interactive)
  (unless omnivox-library-last-result (user-error "No Apply result in this Emacs session"))
  (with-current-buffer (get-buffer-create "*Omnivox Apply result*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Voice library: %s\n\n" (plist-get omnivox-library-last-result :status)))
      (dolist (failure (plist-get omnivox-library-last-result :failures))
        (insert (format "%s: %s\n" (plist-get failure :phase) (plist-get failure :reason))))
      (dolist (process (delq nil (delete-dups (copy-sequence omnivox-library--retained-processes))))
        (insert (format "\n%s: connection %s; native cleanup %s; owner %s\n"
                        (process-name process) (process-status process)
                        (if (process-get process 'omnivox-library-retired) "confirmed" "not confirmed")
                        (plist-get (process-get process 'omnivox-library-owner) :worker))))
      (goto-char (point-min)) (special-mode)))
  (pop-to-buffer "*Omnivox Apply result*"))

(defun omnivox-library-download ()
  "Browse downloadable voices for this library engine."
  (interactive)
  (require 'omnivox-catalogue)
  (omnivox-catalogue omnivox-library--engine))

(defvar-keymap omnivox-library-mode-map
  :doc "Installed-voice actions."
  "d" #'omnivox-library-download "g" #'omnivox-library-refresh "e" #'omnivox-library-toggle
  "a" #'omnivox-library-apply "i" #'omnivox-library-import-validated
  "b" #'omnivox-library-include-flite-slt "r" #'omnivox-library-show-result)

(defun omnivox-library--speak-row ()
  "Speak the selected voice and desired state."
  (if (null tabulated-list-entries)
      (emacsvox-aural-ui-speak
       (if (equal omnivox-library--engine "piper")
           "No Piper voices added. Press d to download voices; q returns."
         "No voices added. Press d to download voices; b includes bundled Flite SLT; q returns."))
    (when-let* ((row (tabulated-list-get-entry)))
      (emacsvox-aural-ui-speak
       (format "%s. %s. %s" (aref row 0) (aref row 1) (aref row 2))))))

(define-derived-mode omnivox-library-mode emacsvox-aural-tabulated-mode "Omnivox Voices"
  "Installed voices: e toggles enablement; a reviews Apply; i installs an import."
  (emacsvox-aural-ui-configure-tabulated
   "Installed Omnivox voices"
   #'omnivox-library--speak-row #'omnivox-library-refresh
   #'omnivox-library--speak-row)
  (setq tabulated-list-format [("Engine" 10 t) ("Voice" 28 t) ("Desired state" 14 t) ("Physical ID" 0 nil)])
  (setq header-line-format "d download; e enable/disable; a Apply both engines; b include SLT; i validated import; r result; g refresh; q back")
  (tabulated-list-init-header))

;;;###autoload
(defun omnivox-library (&optional engine)
  "Open installed voices on the local speech target, optionally for ENGINE."
  (interactive)
  (require 'emacsvox-aural-ui)
  (pop-to-buffer (get-buffer-create "*Omnivox Installed Voices*"))
  (omnivox-library-mode)
  (setq omnivox-library--engine (and (member engine '("piper" "flite")) engine))
  (omnivox-library-refresh))

(provide 'omnivox-library)
;;; omnivox-library.el ends here
