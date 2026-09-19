;;; omnivox-native-runtime-tests.el --- Registered native speech -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Frozen registration, real ordinary producers, and consumed playback evidence.
;;; Code:
(require 'emacsvox-aural-provider-workflows)
(require 'omnivox-choice-consumer-tests)
(require 'omnivox-native-preview-tests)

(defun omnivox-native-runtime-test--enable (process)
  (process-put process omnivox--control-capabilities-property
               (list :features (append omnivox-native-test--features
                                       (plist-get (process-get process omnivox--control-capabilities-property) :features)))))

(defun omnivox-native-runtime-test--ack (request &optional status)
  (let (states)
    (mapc (lambda (wrapper)
            (when (equal (plist-get wrapper :mode) "engine_layered")
              (let ((definition (plist-get wrapper :definition)))
                (mapc (lambda (row)
                        (unless (eq (plist-get row :native) :null)
                          (push (list :logical_voice_id (plist-get definition :id) :choice_id (plist-get row :id)
                                      :status (or status "supported")
                                      :reason (if (or (null status) (equal status "supported")) :null "Runtime not checked")) states)))
                      (plist-get definition :choices))))) (plist-get request :definitions))
    (list :protocol_version 1 :request_id (plist-get request :request_id) :type "logical_voices_registered_v3"
          :registry_generation (plist-get request :registry_generation) :inventory_generation 12
          :definition_count (length (plist-get request :definitions)) :unresolved_logical_voice_ids []
          :native_status (vconcat (nreverse states)))))

(defun omnivox-native-runtime-test--register ()
  (let (captured)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process text)
                 (push (cons process (omnivox--decode-control-response
                                      (substring text (length "omnivox_control {") -2) t)) captured))))
      (omnivox-register-logical-voices))
    (dolist (write captured)
      (omnivox-preview-test--control-line (car write) (omnivox-native-runtime-test--ack (cdr write))))))

(defmacro omnivox-native-runtime-test--with-speech (&rest body)
  (declare (indent 0) (debug t))
  `(omnivox-choice-consumer-test--with-speech
    (emacsvox-test--with-native-storage
     (dolist (lane (list speaker notification)) (omnivox-native-runtime-test--enable lane))
     (omnivox-native-runtime-test--register)
     ,@body)))

(defun omnivox-native-runtime-test--start (id)
  (let ((event (omnivox-choice-playback-test--start id nil nil "dectalk" "paul")))
    (setf (plist-get event :protocol_version) 4) event))

(defun omnivox-native-runtime-test--receipt (id process)
  (let ((event (omnivox-native-test--message :playback_receipt)))
    (setf (plist-get event :dispatch_id) id
          (plist-get event :registry_generation)
          (plist-get (process-get process omnivox--choice-registration-property) :registry-generation)) event))

(ert-deftest omnivox-native-runtime-independent-registration-and-marker-fixtures ()
  (let* ((request (omnivox-native-test--message :registration))
         (response (omnivox-native-test--message :registration_ack)))
    (should (omnivox--native-registration-valid-p response 41 request))
    (should-not (omnivox--native-registration-valid-p response 42 request))
    (setf (plist-get response :native_status) [])
    (should-not (omnivox--native-registration-valid-p response 41 request)))
  (let* ((event (omnivox-native-test--message :playback_receipt))
         (payload (base64-encode-string (json-serialize event) t)))
    (should (equal event (omnivox--native-decode-marker payload)))
    (should-error (omnivox--choice-decode-marker payload))
    (setf (plist-get event :protocol_version) 3)
    (should-error (omnivox--native-validate-marker event))))

(ert-deftest omnivox-native-runtime-registration-statuses-are-complete-and-owned ()
  (let ((request (omnivox-native-test--message :registration)))
    (dolist (change '(missing duplicate foreign-choice foreign-voice unknown-status missing-reason false-reason extra-field))
      (let* ((response (omnivox-native-test--message :registration_ack))
             (states (plist-get response :native_status)) (first (aref states 0)))
        (pcase change
          ('missing (setf (plist-get response :native_status) (seq-take states 2)))
          ('duplicate (aset states 1 first))
          ('foreign-choice (setf (plist-get first :choice_id) "unregistered"))
          ('foreign-voice (setf (plist-get first :logical_voice_id) "unregistered"))
          ('unknown-status (setf (plist-get first :status) "applied"))
          ('missing-reason (setf (plist-get first :status) "deferred"))
          ('false-reason (setf (plist-get first :reason) :false))
          ('extra-field (setq response (append response '(:native_status [])))))
        (should-not (omnivox--native-registration-valid-p response 41 request))))))

(ert-deftest omnivox-native-runtime-mixed-lanes-preserve-native-with-honest-save-result ()
  (omnivox-test--with-choice-registration
   (emacsvox-test--with-native-storage
    (omnivox-native-runtime-test--enable speaker)
    (omnivox-apply-voice-configuration (lambda (result) (push result terminal)))
    (let ((main (cdr (assq speaker requests))) (notify (cdr (assq notification requests))))
      (should (equal (plist-get main :type) "register_logical_voices_v3"))
      (should (equal (plist-get notify :type) "register_logical_voices_v2"))
      (should-not (process-get speaker emacsvox-aural--structured-timeline-process-property))
      (omnivox-preview-test--control-line speaker (omnivox-native-runtime-test--ack main))
      (should-not terminal)
      (should (= 5 (process-get speaker emacsvox-aural--structured-timeline-process-property)))
      (omnivox--dispatch-control-response notification (omnivox-test--choice-registration-ack (assq notification requests)))
      (should (plist-get (car terminal) :choice-tuning-unapplied))
      (let ((lanes (plist-get (car terminal) :processes)))
        (should (= 1 (cl-count-if (lambda (lane) (plist-get lane :choice-tuning-unapplied)) lanes))))))))

(ert-deftest omnivox-native-runtime-deferred-registration-never-claims-full-application ()
  (dolist (status '("supported" "deferred" "unavailable"))
    (omnivox-test--with-choice-registration
     (emacsvox-test--with-native-storage
      (dolist (lane (list speaker notification)) (omnivox-native-runtime-test--enable lane))
      (omnivox-apply-voice-configuration (lambda (result) (push result terminal)))
      (dolist (write requests)
        (omnivox-preview-test--control-line (car write) (omnivox-native-runtime-test--ack (cdr write) status)))
      (should (eq (and (plist-get (car terminal) :choice-tuning-unapplied) t)
                  (not (equal status "supported"))))
      (dolist (lane (plist-get (car terminal) :processes))
        (should (vectorp (plist-get (plist-get lane :registration) :native_status))))))))

(ert-deftest omnivox-native-runtime-invalid-or-stale-ack-cannot-enable-native-timeline ()
  (omnivox-test--with-choice-registration
   (emacsvox-test--with-native-storage
    (omnivox-native-runtime-test--enable speaker)
    (let* ((content (omnivox--process-logical-registry-content speaker))
           (request (append '(:request_id 1) (omnivox--registration-request 41 content)))
           (response (omnivox-native-runtime-test--ack request)))
      (setf (plist-get response :native_status) [])
      (should-not (omnivox--accept-registration-response speaker response 41 content))
      (should-not (process-get speaker omnivox--choice-registration-property))
      (should-not (process-get speaker emacsvox-aural--structured-timeline-process-property))
      (setq response (omnivox-native-runtime-test--ack request))
      (process-put speaker 'tts--speech-process-generation 99)
      (should-not (omnivox--accept-registration-response speaker response 41 content))
      (process-put speaker 'tts--speech-process-generation nil)
      (should (omnivox--accept-registration-response speaker response 41 content))
      (let ((snapshot (process-get speaker omnivox--choice-registration-property)))
        (setf (plist-get response :registry_generation) 40)
        (should-not (omnivox--accept-registration-response speaker response 40 content))
        (should (eq snapshot (process-get speaker omnivox--choice-registration-property))))))))

(ert-deftest omnivox-native-runtime-ordinary-main-and-notification-use-acknowledged-native-registry ()
  (omnivox-native-runtime-test--with-speech
   (dolist (voice '(bolden voice-bolden))
     (tts-speak (propertize "ordinary" 'personality voice))
     (tts-notify (propertize "notification" 'personality voice) t))
   (should (= 4 (length writes)))
   (dolist (write writes)
     (let* ((document (omnivox-choice-consumer-test--timeline write))
            (span (car (plist-get document :spans))))
       (should (= 5 (plist-get document :protocol_version)))
       (should (= (plist-get document :registry_generation)
                  (plist-get (process-get (car write) omnivox--choice-registration-property) :registry-generation)))
       (should (equal (plist-get span :mode) "engine_layered"))
       (should-not (plist-member (plist-get span :span) :native))
       (should-not (plist-member (plist-get span :span) :acss))))))

(ert-deftest omnivox-native-runtime-refresh-updates-status-without-rewriting-old-evidence ()
  (omnivox-test--with-choice-registration
   (emacsvox-test--with-native-storage
    (omnivox-native-runtime-test--enable speaker)
    (let* ((content (omnivox--process-logical-registry-content speaker))
           (request (append '(:request_id 1) (omnivox--registration-request 41 content)))
           (old-reply (omnivox-native-runtime-test--ack request "deferred")))
      (should (omnivox--accept-registration-response speaker old-reply 41 content))
      (let ((old (process-get speaker omnivox--choice-registration-property)))
        (setf (plist-get request :request_id) 2)
        (let ((reply (omnivox-native-runtime-test--ack request)))
          (should (omnivox--accept-registration-response speaker reply 41 content))
          (let ((current (process-get speaker omnivox--choice-registration-property)))
            (should-not (eq old current))
            (should (equal (plist-get (aref (plist-get (plist-get old :response) :native_status) 0) :status) "deferred"))
            (should (equal (plist-get (aref (plist-get (plist-get current :response) :native_status) 0) :status) "supported"))
            (should-not (omnivox--accept-registration-response speaker old-reply 41 content))
            (should (eq current (process-get speaker omnivox--choice-registration-property))))))))))

(ert-deftest omnivox-native-runtime-timeline-preserves-context-and-versioned-modes ()
  (omnivox-native-runtime-test--with-speech
   (let* ((snapshot (omnivox--choice-current-registration speaker))
          (runs (list (omnivox-choice-timeline-test--run 'unrelated '(:echo 3))
                      (omnivox-choice-timeline-test--run '(:preset bolden :richness 0 :echo nil) nil)))
          (built (emacsvox-aural--build-structured-timeline 2 91 runs snapshot))
          (document (car built)) (spans (plist-get document :spans)))
     (should (equal (mapcar (lambda (span) (plist-get span :mode)) spans) '("legacy" "engine_layered")))
     (should (equal (plist-get (plist-get (aref spans 1) :span) :context)
                    '(:richness (:op "set" :value 0.0) :echo (:op "default"))))
     (should (emacsvox-aural--frame-structured-timeline document))
     (let ((emacsvox-aural--timeline-frame-max-bytes 128)
           (emacsvox-aural--timeline-encoded-fragment-max-bytes 172))
       (should (cl-every (lambda (part) (string-prefix-p "emacsvox_timeline_part 5 " part))
                         (emacsvox-aural--frame-structured-timeline document))))
     (setf (plist-get document :protocol_version) 4)
     (should-error (emacsvox-aural--frame-structured-timeline document)))))

(ert-deftest omnivox-native-runtime-receipts-distinguish-applied-and-common-only ()
  (dolist (status '("applied" "common_only"))
    (omnivox-native-runtime-test--with-speech
     (let* ((id (omnivox-choice-playback-test--submit))
            (event (omnivox-native-runtime-test--receipt id speaker)))
       (when (equal status "common_only")
         (setf (plist-get event :native_application)
               '(:status "common_only" :plan_id :null :identity :null :masked_parameters [] :reason "Helper unavailable")))
       (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--start id))
       (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'unverified))
       (omnivox-choice-playback-test--event speaker event)
       (should-not omnivox-marker-last-error)
       (let ((route (omnivox-last-realized-voice 'bolden)))
         (should (eq (plist-get route :choice-status) 'verified))
         (should (equal (plist-get (plist-get route :native-application) :status) status)))
       (tts--cancel-process-tracked-dispatches speaker 'cancelled)
       (should (zerop (process-get speaker 'tts--dispatch-metadata-bytes)))))))

(ert-deftest omnivox-native-runtime-invalid-evidence-does-not-consume-the-marker-sequence ()
  (dolist (fault '(null schema mask version absent duplicate-field))
    (omnivox-native-runtime-test--with-speech
     (let* ((id (omnivox-choice-playback-test--submit))
            (event (omnivox-native-runtime-test--receipt id speaker)))
       (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--start id))
       (pcase fault
         ('null (setf (plist-get event :native_application) :null))
         ('schema (setf (plist-get (plist-get (plist-get event :native_application) :identity) :schema_id) "other.schema"))
         ('mask (setf (plist-get (plist-get event :native_application) :masked_parameters) ["absent"]))
         ('version (setf (plist-get event :protocol_version) 3) (cl-remf event :native_application))
         ('absent (cl-remf event :native_application)))
       (if (eq fault 'duplicate-field)
           (omnivox--control-process-filter
            speaker (concat omnivox-marker-event-prefix
                            (base64-encode-string
                             (concat (substring (json-serialize event) 0 -1) ",\"native_application\":null}") t) "\n"))
         (omnivox-choice-playback-test--event speaker event))
       (ert-info ((format "Malformed native receipt: %s" fault))
         (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'unverified)))
       (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--receipt id speaker))
       (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))))))

(ert-deftest omnivox-native-runtime-receipt-belongs-to-its-frozen-registration-and-lane ()
  (omnivox-native-runtime-test--with-speech
   (let* ((id (omnivox-choice-playback-test--submit))
          (event (omnivox-native-runtime-test--receipt id speaker)))
     (omnivox-choice-playback-test--event notification (omnivox-native-runtime-test--start id))
     (should-not (omnivox-last-realized-voice 'bolden))
     (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--start id))
     (setf (plist-get (car (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)) :native)
           '(:engine-id "dectalk" :schema-id "future.schema" :parameters (("future" :op set :value 9))))
     (omnivox-native-runtime-test--register)
     (omnivox-choice-playback-test--event speaker event)
     (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))
     (should (equal (plist-get (plist-get (plist-get (omnivox-last-realized-voice 'bolden) :native-application) :identity) :schema_id)
                    "dectalk.design-voice.v1")))))

(ert-deftest omnivox-native-runtime-policy-fallback-never-borrows-native-settings ()
  (omnivox-native-runtime-test--with-speech
   (let* ((id (omnivox-choice-playback-test--submit))
          (start (omnivox-native-runtime-test--start id))
          (event (omnivox-native-runtime-test--receipt id speaker))
          (choice (plist-get event :choice)))
     (setf (plist-get start :engine_id) "espeak"
           (plist-get start :actual_voice) '(:engine_id "espeak" :voice_id "en+f3")
           (plist-get choice :choice_id) :null
           (plist-get choice :reason) '(:reason "fallback_engine" :fallback_index 0)
           (plist-get choice :realized) '(:engine_id "espeak" :voice_id "en+f3"))
     (omnivox-choice-playback-test--event speaker start)
     (omnivox-choice-playback-test--event speaker event)
     (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'unverified))
     (setf (plist-get event :native_application) :null)
     (omnivox-choice-playback-test--event speaker event)
     (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))
     (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :native-application) :null)))))

(ert-deftest omnivox-native-runtime-capability-loss-refuses-an-old-native-snapshot ()
  (omnivox-native-runtime-test--with-speech
   (let ((snapshot (process-get speaker omnivox--choice-registration-property)))
     (process-put speaker omnivox--control-capabilities-property
                  (list :features omnivox-test--choice-features))
     (should-error (omnivox--choice-current-registration speaker))
     (should (eq snapshot (process-get speaker omnivox--choice-registration-property)))
     (should-not writes))))

(provide 'omnivox-native-runtime-tests)
;;; omnivox-native-runtime-tests.el ends here
