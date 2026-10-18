;;; omnivox-library-runtime.el --- Native voice library runtime -*- lexical-binding: t; -*-

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
;; Native library inspection, process startup, acknowledgement and coordinated
;; activation.  This service does not load the interactive library or editors.
;; Callers own review and confirmation; the existing Apply state machine owns
;; transitions, and this module executes them against the captured processes.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'tts-queue-state)
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
(declare-function omnivox--send-control-request "omnivox-voices" (process request callback &optional timeout))
(declare-function omnivox--take-control-request "omnivox-voices" (process identifier))
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
(defvar omnivox--engine-startup nil "Prepared configuration shared by speech lanes.")
(defvar omnivox-library--current-engines nil "Published local activation and launcher.")
(defvar omnivox-library--birth-collector nil "Provider callback retaining every attempted process.")
(defvar omnivox-library--support-cache nil)
(defvar omnivox-library--sequence 0)
(defvar omnivox-library--busy nil)
(defvar omnivox-library--changed-hook nil "Hook after installed voice selections change.")
(defvar omnivox-library-last-result nil "Most recent local Apply result.")
(defconst omnivox-library--prefix "OMNIVOX-LOCAL ")
(defconst omnivox-library--timeout 45)

(defun omnivox-library--source-key ()
  "Identify the selected launcher and native library location."
  (let ((program (tts--resolve-program tts-program)))
    (list program (and program (file-attribute-modification-time
                               (file-attributes program)))
          (mapcar #'getenv '("OMNIVOX_PROGRAM" "OMNIVOX_VOICE_ROOT"
                            "XDG_DATA_HOME" "LOCALAPPDATA" "HOME")))))

(defun omnivox-library--inspect-async (callback)
  "Inspect the selected library without waiting for native processes.
Call CALLBACK once with REPLY and ERROR, either of which may be nil.
Return a cancellation function which releases only this private inspection.
Cancellation suppresses CALLBACK.  Capability discovery is asynchronous too."
  (let* ((source (omnivox-library--source-key))
         (program (car source))
         (key (list program (getenv "OMNIVOX_PROGRAM") (cadr source)))
         process timer done
         (help ""))
    (cl-labels
        ((finish (reply failure &optional cancel)
           (unless done
             (setq done t)
             (when timer (cancel-timer timer))
             (when process
               (process-put process 'omnivox-library-pending nil)
               (set-process-sentinel process #'ignore)
               (when (process-live-p process) (delete-process process)))
             (unless cancel (funcall callback reply failure))))
         (inspect ()
           (condition-case err
               (progn
                 (unless (equal source (omnivox-library--source-key))
                   (error "Voice library target changed"))
                 (setq process (omnivox-library--service))
                 (set-process-filter
                  process (lambda (worker output)
                            (condition-case failure
                                (omnivox-library--service-filter worker output)
                              (error (finish nil (error-message-string failure))))))
                 (set-process-sentinel
                  process (lambda (worker _event)
                            (unless (process-live-p worker)
                              (finish nil "Voice library inspection process exited"))))
                 (let ((id (cl-incf omnivox-library--sequence))
                       (pending (make-hash-table :test #'eql)))
                   (process-put process 'omnivox-library-pending pending)
                   ;; Install correlation before sending: a reply can be immediate.
                   (puthash id
                            (lambda (reply)
                              (cond
                               ((not (equal source (omnivox-library--source-key)))
                                (finish nil "Voice library target changed"))
                               ((equal (plist-get reply :type) "library")
                                (finish reply nil))
                               (t (finish nil (or (plist-get reply :message)
                                                  "Unexpected voice library response")))))
                            pending)
                   (process-send-string
                    process (concat (json-serialize (list :request_id id :command "inspect")) "\n"))))
             (error (finish nil (error-message-string err))))))
      (setq timer (run-at-time omnivox-library--timeout nil
                               (lambda () (finish nil "Voice library inspection timed out"))))
      (condition-case err
          (cond
           ((not (and program (omnivox-engine-settings--supported-p)))
            (finish nil "Voice management requires the bundled local Omnivox launcher"))
           ((assoc key omnivox-library--support-cache)
            (if (cdr (assoc key omnivox-library--support-cache)) (inspect)
              (finish nil "This launcher does not support voice management")))
           (t
            (setq process
                  (make-process
                   :name "Omnivox library capability" :command (list program "--help")
                   :connection-type 'pipe :coding 'utf-8-unix :noquery t
                   :filter (lambda (_worker output)
                             (setq help (concat help output))
                             (when (> (string-bytes help) (* 1024 1024))
                               (finish nil "Voice library capability output exceeds bound")))
                   :sentinel
                   (lambda (worker _event)
                     (when (and (not done) (memq (process-status worker) '(exit signal)))
                       (let ((supported
                              (and (eq (process-status worker) 'exit)
                                   (zerop (process-exit-status worker))
                                   (string-match-p "--voice-library-owner" help))))
                         (push (cons key (and supported t)) omnivox-library--support-cache)
                         (if supported (inspect)
                           (finish nil "This launcher does not support voice management")))))))))
        (error (finish nil (error-message-string err))))
      (lambda () (finish nil nil t)))))

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
  "Extend ENVIRONMENT with the retained native startup for this activation."
  (let ((process-environment (copy-sequence environment)))
    (when (or omnivox--library-startup omnivox--engine-startup)
      (dolist (name '("OMNIVOX_OWNED_STARTUP" "OMNIVOX_OWNED_STARTUP_SHA256"
                      "OMNIVOX_OWNED_LIBRARY" "OMNIVOX_OWNED_ENGINE_STARTUP"
                      "OMNIVOX_OWNED_ENGINE_STARTUP_SHA256"))
        (setenv name nil))
      (if omnivox--library-startup
          (progn
            (setenv "OMNIVOX_OWNED_STARTUP" (plist-get omnivox--library-startup :path))
            (setenv "OMNIVOX_OWNED_STARTUP_SHA256" (plist-get omnivox--library-startup :sha256))
            (setenv "OMNIVOX_OWNED_LIBRARY" (plist-get omnivox--library-startup :candidate)))
        (setenv "OMNIVOX_OWNED_ENGINE_STARTUP" (plist-get omnivox--engine-startup :path))
        (setenv "OMNIVOX_OWNED_ENGINE_STARTUP_SHA256" (plist-get omnivox--engine-startup :sha256))))
    process-environment))

(defun omnivox-library--engine-reference (process)
  "Return PROCESS's acknowledged startup reference, even after it exits."
  (when (and (processp process) (tts--omnivox-program-p tts-program)
             (not (omnivox-remote-enabled-p)))
    (let* ((owner (process-get process 'omnivox-library-owner))
           (identity (plist-get owner :activation_id)))
      (when (and (stringp identity)
                 (equal identity (process-get process 'omnivox-engine-activation)))
        (list :path (plist-get owner :startup) :sha256 (plist-get owner :startup_sha256)
              :activation-id identity)))))

(defun omnivox-library--remember-engines (process)
  "Retain published PROCESS's activation after lifecycle cleanup clears globals."
  (setq omnivox-library--current-engines
        (cons tts-program (omnivox-library--engine-reference process))))

(defun omnivox-library--current-engine-reference ()
  "Return the published activation for recovery through the same launcher."
  (when (and (equal tts-program (car omnivox-library--current-engines))
             (not (omnivox-remote-enabled-p)))
    (cdr omnivox-library--current-engines)))

(defun omnivox-library--prepare-engines ()
  "Prepare one local activation; retain compatibility with older launchers."
  (when (and (tts--omnivox-program-p tts-program) (not (omnivox-remote-enabled-p)))
    (let ((program (tts--resolve-program tts-program)))
      (when (and program (omnivox-library--supported-p program))
        (let* ((default-directory (expand-file-name "~/"))
               (service (omnivox-library--service)))
          (unwind-protect
              (let* ((host (omnivox-library--request service '(:command "host")))
                     (version (plist-get host :engine_configuration_version)))
                (when version
                  (unless (eql version 1) (error "Unsupported native engine configuration version"))
                  (let ((reply (omnivox-library--request service '(:command "engine-snapshot"))))
                    (unless (equal (plist-get reply :type) "prepared_startup")
                      (error "Missing prepared engine configuration"))
                    (omnivox-library-apply--uuid (plist-get reply :activation_id))
                    (list :path (plist-get reply :startup) :sha256 (plist-get reply :startup_sha256)
                          :activation-id (plist-get reply :activation_id)))))
            (when (process-live-p service) (delete-process service))))))))

(defun omnivox-library--acknowledge-engines (process startup)
  "Verify PROCESS installed STARTUP, independently of its launcher metadata.
This check does not publish capability or routing readiness hooks."
  (let* ((owner (process-get process 'omnivox-library-owner))
         (expected (or (plist-get startup :activation-id)
                       (and (stringp (plist-get owner :activation_id))
                            (plist-get owner :activation_id)))))
    (when expected
      (omnivox-library-apply--uuid expected)
      (unless (equal expected (plist-get owner :activation_id))
        (error "Native owner acknowledged a different engine configuration"))
      ;; External initialization has a 120-second batch budget.  Keep this
      ;; distinct from the routing deadline, which starts after capabilities.
      (let* ((omnivox-library--timeout 180)
             (capabilities (omnivox-library--control process '(:type "capabilities"))))
        (unless (and (equal (plist-get capabilities :type) "capabilities")
                     (seq-contains-p (plist-get capabilities :features) "engine_configuration_v1" #'equal))
          (error "Worker does not advertise engine configuration acknowledgement"))
        (let ((status (omnivox-library--control process '(:type "engine_configuration_status_v1"))))
          (unless (and (equal (plist-get status :type) "engine_configuration_status_v1")
                       (equal expected (plist-get status :activation_id)))
            (error "Worker acknowledged a different engine configuration"))
          (process-put process 'omnivox-engine-activation expected))))))

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

(defun omnivox-library--candidate-startup (generation role process &optional shared)
  "Resolve GENERATION and ROLE with PROCESS policy and optional SHARED engines."
  (let ((service (omnivox-library--service role)))
    (unwind-protect
        (let ((snapshot (omnivox-library--request
                         service (append (list :command "snapshot" :generation generation)
                                         (when (plist-get shared :activation-id)
                                           (list :startup (plist-get shared :path)
                                                 :startup_sha256 (plist-get shared :sha256)))))))
          (unless (equal (plist-get snapshot :type) "snapshot") (error "Missing native candidate snapshot"))
          (when (plist-get shared :activation-id)
            (unless (equal (plist-get shared :activation-id) (plist-get snapshot :activation_id))
              (error "Candidate lanes have different engine configurations")))
          (list :role role :startup
                (list :path (plist-get snapshot :startup) :sha256 (plist-get snapshot :startup_sha256)
                      :activation-id (plist-get snapshot :activation_id)
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
                                            (when (eq source process) (setq response result)))
                                          'managed))
    (unwind-protect
        (progn
          (omnivox-library--wait (lambda () response) process (plist-get command :type))
          (when (equal (plist-get response :type) "error") (error "%s" (plist-get response :message)))
          response)
      (when id (omnivox--take-control-request process id)))))

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
                         :activation-id (process-get process 'omnivox-engine-activation)
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
  (omnivox-library--acknowledge-engines process startup)
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
        (voices (seq-remove
                 (lambda (id)
                   (and (member (plist-get id :engine_id) providers)
                        (or (not (equal (plist-get id :engine_id) "rhvoice"))
                            (seq-some (lambda (row)
                                        (and (equal (plist-get row :engine_id) "rhvoice")
                                             (equal (plist-get row :physical_id) (plist-get id :voice_id))))
                                      (plist-get index :voices)))))
                 previous)))
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
           (omnivox-library--remember-engines tts-speaker-process)
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

(defun omnivox-library--managed-providers (providers index)
  "Resolve PROVIDERS against the installed voices in INDEX."
  (if (equal providers "both")
      (append '("piper" "flite")
              (seq-filter
               (lambda (provider)
                 (seq-some (lambda (voice) (equal provider (plist-get voice :engine_id)))
                           (plist-get index :voices)))
               '("mbrola" "rhvoice")))
    (list providers)))

(defun omnivox-library--edit-selection (source sha action &optional row operation)
  "Apply desired-state ACTION to captured SOURCE and library SHA.
ROW supplies the native voice record for a toggle.  OPERATION identifies an
already validated import.  This writes desired state only; callers own feedback,
refresh and any later review of Apply.  Always release the private service."
  (let ((command
         (pcase action
           ('toggle
            (list :command "enable" :engine (plist-get row :engine_id)
                  :voice (plist-get row :physical_id)
                  :enabled (if (eq (plist-get row :enabled) t) :false t)))
           ('slt '(:command "include-flite-slt"))
           ('import
            (omnivox-library-apply--uuid operation)
            (list :command "import" :operation operation
                  :package (omnivox-library--uuid) :revision (omnivox-library--uuid)))
           (_ (error "Unknown voice selection action: %S" action)))))
    (let ((service (omnivox-library--service)))
      (unwind-protect
          (progn
            (unless (equal source (omnivox-library--source-key))
              (user-error "Voice library target changed; press R to refresh"))
            (omnivox-library--request
             service (append command (list :expected_sha256 sha))))
        (when (process-live-p service) (delete-process service))))))

(provide 'omnivox-library-runtime)

;;; omnivox-library-runtime.el ends here
