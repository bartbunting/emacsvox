;;; omnivox-native-preview-tests.el --- Native private previews -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Independent wire examples and real preview ownership, with muted playback.
;;; Code:
(require 'omnivox-preview-tests)
(require 'emacsvox-aural-voice-editor)

(defconst omnivox-native-test--fixture
  (expand-file-name "fixtures/voice-editor/engine-parameters-wire.json"
                    (file-name-directory (or load-file-name buffer-file-name))))
(defconst omnivox-native-test--features
  '("engine_parameter_catalogue_v1" "engine_voice_parameters_v1"
    "presentation_timeline_v5" "playback_marker_events_v4"))

(defun omnivox-native-test--message (key)
  (with-temp-buffer
    (insert-file-contents omnivox-native-test--fixture)
    (plist-get (plist-get (json-parse-buffer :object-type 'plist :null-object :null :false-object :false)
                         :messages) key)))

(defun omnivox-native-test--entry (&optional choice)
  (omnivox--preview-copy
   (list :text "A heading." :role 'sample :variant 'edited
         :voice '(:language "en-US" :shared (:richness 4)
                  :choices ((:id "paul-main" :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
                             :adjustments nil :native (:engine-id "dectalk" :schema-id "dectalk.design-voice.v1"
                                                       :parameters (("sm" :op set :value 55))))
                            (:id "paul-soft" :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
                             :adjustments nil :native (:engine-id "dectalk" :schema-id "dectalk.design-voice.v1"
                                                       :parameters (("sm" :op set :value 80))))
                            (:id "eci-default" :selector (:kind engine-default :scope portable :engine-id "eloquence")
                             :adjustments nil :native (:engine-id "eloquence" :schema-id "eloquence.eci-units.v1"
                                                       :parameters (("breathiness" :op set :value 42))))
                            (:id "espeak-default" :selector (:kind engine-default :scope portable :engine-id "espeak")
                             :adjustments nil)))
         :context nil :placement '(:pan nil)
         :selection (if choice (list :mode 'choice :choice-id choice) '(:mode automatic))
         :fallback-policy '(:preferred-engines nil :allow-same-language-on-requested-engine t
                            :global-default nil :fallback-engines ("espeak"))
         :disabled-engine-ids nil)))

(defun omnivox-native-test--bundle (process)
  (omnivox-preview-test--bundle process)
  (process-put process omnivox--control-capabilities-property
               (list :features (append omnivox-native-test--features
                                       (plist-get (process-get process omnivox--control-capabilities-property) :features)))))

(defun omnivox-native-test--terminal (&optional id)
  (let ((response (omnivox-native-test--message :preview_completed)))
    (setf (plist-get response :request_id) (or id 41)) response))

(defun omnivox-native-test--common (entry)
  (let ((copy (omnivox--preview-copy entry)))
    (dolist (row (plist-get (plist-get copy :voice) :choices)) (cl-remf row :native)) copy))

(ert-deftest omnivox-native-preview-choice-wire-matches-independent-fixture ()
  (emacsvox-test--with-complete-preview
   (omnivox-native-test--bundle speaker)
   (let* ((entry (omnivox-native-test--entry "paul-main"))
          (before (omnivox--preview-copy entry))
          (request (omnivox--preview-layered-request entry speaker))
          (decoded (json-parse-string (json-serialize request) :object-type 'plist :null-object :null :false-object :false))
          (fixture (omnivox-native-test--message :preview)))
     (should (equal (plist-get request :type) "preview_voice_v3"))
     (should (equal (plist-get (plist-get decoded :voice) :choices)
                    (plist-get (plist-get fixture :voice) :choices)))
     (dolist (key '(:context :placement :selection :fallback_policy :disabled_engine_ids))
       (should (equal (plist-get decoded key) (plist-get fixture key))))
     (should (equal entry before))
     (should (= 0 stops)) (should-not writes))))

(ert-deftest omnivox-native-preview-wire-preserves-false-zero-default-and-string-ids ()
  (let* ((row (car (plist-get (plist-get (omnivox-native-test--entry) :voice) :choices)))
         (id "uninterned-native-control-782143")
         (parameters (list (list id :op 'set :value nil)
                           '("zero" :op set :value 0) '("reset" :op default)
                           '("enum" :op set :value "soft") '("enabled" :op set :value t))))
    (setf (plist-get (plist-get row :native) :parameters) parameters)
    (should-not (intern-soft id))
    (let ((wire (plist-get (plist-get (aref (omnivox--native-choice-records-json (list row)) 0) :native) :parameters)))
      (should (eq (plist-get (gethash id wire) :value) :false))
      (should (eql (plist-get (gethash "zero" wire) :value) 0))
      (should (equal (gethash "reset" wire) '(:op "default")))
      (should (equal (plist-get (gethash "enum" wire) :value) "soft"))
      (should (eq (plist-get (gethash "enabled" wire) :value) t)))
    (should-not (intern-soft id))
    (should-error (omnivox--choice-records-json (list row)))
    (setf (plist-get (plist-get row :native) :engine-id) "eloquence")
    (should-error (omnivox--native-choice-records-json (list row)))))

(ert-deftest omnivox-native-preview-preflights-every-capability-and-comparison-half ()
  (emacsvox-test--with-complete-preview
   (let ((entry (omnivox-native-test--entry)))
     (dolist (missing omnivox-native-test--features)
       (omnivox-native-test--bundle speaker)
       (process-put speaker omnivox--control-capabilities-property
                    (list :features (remove missing (plist-get (process-get speaker omnivox--control-capabilities-property) :features))))
       (should-error (omnivox--preview-layered-sequence
                      (list (omnivox-native-test--common entry) entry) #'ignore) :type 'user-error)
       (should-error (emacsvox-aural-voice-editor--submit-preview
                      (list (omnivox-native-test--common entry) entry) #'ignore (lambda () t)) :type 'user-error)))
   (should (= 0 stops)) (should-not writes)
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-native-preview-qualified-fixture-and-version-separation ()
  (let* ((entry (omnivox-native-test--entry "paul-main"))
         (response (omnivox-native-test--terminal))
         (result (omnivox--normalize-layered-preview-response entry response t)))
    (should (plist-get result :terminal-confirmed))
    (should (eq (plist-get result :status) 'completed))
    (should (= 7 (plist-get (plist-get (plist-get (plist-get result :last-started) :native_application) :identity) :runtime_generation)))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (setf (plist-get response :type) "preview_voice_completed_v2")
    (should-error (omnivox--normalize-layered-preview-response entry response t))))

(ert-deftest omnivox-native-preview-rejects-unqualified-or-common-only-evidence ()
  (dolist (mutate
           (list (lambda (a) (setf (plist-get a :plan_id) :null))
                 (lambda (a) (setf (plist-get a :identity) :null))
                 (lambda (a) (setf (plist-get a :reason) "Ignored native settings"))
                 (lambda (a) (setf (plist-get a :masked_parameters) ["absent"]))
                 (lambda (a) (setf (plist-get a :masked_parameters) ["sm" "sm"]))
                 (lambda (a) (setf (plist-get (plist-get a :identity) :runtime_generation) 0))
                 (lambda (a) (setf (plist-get (plist-get a :identity) :schema_id) "another.schema"))
                 (lambda (a) (setf (plist-get a :status) "common_only"
                                    (plist-get a :plan_id) :null (plist-get a :identity) :null
                                    (plist-get a :reason) "Helper unavailable"))))
    (let* ((response (omnivox-native-test--terminal))
           (application (plist-get (aref (plist-get response :accepted_audio) 0) :native_application)))
      (funcall mutate application)
      (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t)))))

(ert-deftest omnivox-native-preview-requires-application-field-and-execution-for-native-row ()
  (dolist (value '(:absent :null nil))
    (let* ((response (omnivox-native-test--terminal))
           (accepted (aref (plist-get response :accepted_audio) 0)))
      (if (eq value :absent) (cl-remf accepted :native_application)
        (setf (plist-get accepted :native_application) value))
      (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t))))
  (let* ((entry (omnivox-native-test--entry)) (response (omnivox-native-test--terminal)))
    (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--common entry) response t))
    (setf (plist-get (aref (plist-get response :accepted_audio) 0) :native_application) :null
          (plist-get (plist-get response :last_started) :native_application) :null)
    (should (plist-get (omnivox--normalize-layered-preview-response (omnivox-native-test--common entry) response t) :terminal-confirmed))))

(ert-deftest omnivox-native-preview-duplicate-voices-retain-choice-and-plan-identity ()
  (let* ((entry (omnivox-native-test--entry "paul-soft"))
         (response (omnivox-native-test--terminal)))
    (should-error (omnivox--normalize-layered-preview-response entry response t))
    (dolist (identity (list (aref (plist-get response :accepted_audio) 0) (plist-get response :last_started)))
      (setf (plist-get identity :choice_id) "paul-soft"
            (plist-get identity :reason) '(:reason "explicit_alternative" :preference_index 1)))
    (should (plist-get (omnivox--normalize-layered-preview-response entry response t) :terminal-confirmed))
    (setf (plist-get (plist-get (plist-get response :last_started) :native_application) :plan_id) "different-plan")
    (should-error (omnivox--normalize-layered-preview-response entry response t))
    (setf (plist-get response :accepted_audio_truncated) t)
    (should (plist-get (omnivox--normalize-layered-preview-response entry response t) :last-started))))

(ert-deftest omnivox-native-preview-same-voice-with-distinct-plans-is-not-deduplicated ()
  (let* ((response (omnivox-native-test--terminal))
         (first (aref (plist-get response :accepted_audio) 0))
         (second (omnivox--preview-copy first)))
    (setf (plist-get (plist-get second :native_application) :plan_id) "plan-24"
          (plist-get response :accepted_audio) (vector first second))
    (should (= 2 (length (plist-get (omnivox--normalize-layered-preview-response
                                   (omnivox-native-test--entry) response t) :accepted-audio))))
    (setf (plist-get (plist-get second :native_application) :plan_id) "plan-23")
    (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t))))

(ert-deftest omnivox-native-preview-common-fallback-cannot-inherit-native-evidence ()
  (dolist (policy '(nil t))
    (let* ((response (omnivox-native-test--terminal)) (entry (omnivox-native-test--entry)))
      (dolist (identity (list (aref (plist-get response :accepted_audio) 0) (plist-get response :last_started)))
        (setf (plist-get identity :choice_id) (if policy :null "espeak-default")
              (plist-get identity :reason) (if policy '(:reason "fallback_engine" :fallback_index 0)
                                            '(:reason "explicit_alternative" :preference_index 3))
              (plist-get identity :realized) '(:engine_id "espeak" :voice_id "en+f3")))
      (should-error (omnivox--normalize-layered-preview-response entry response t))
      (dolist (identity (list (aref (plist-get response :accepted_audio) 0) (plist-get response :last_started)))
        (setf (plist-get identity :native_application) :null))
      (should (plist-get (omnivox--normalize-layered-preview-response entry response t) :terminal-confirmed))
      (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry "paul-main") response t)))))

(ert-deftest omnivox-native-preview-started-plan-must-match-all-qualified-evidence ()
  (dolist (field '(:profile_id :catalogue_revision :runtime_generation :masked_parameters))
    (let* ((response (omnivox-native-test--terminal))
           (application (plist-get (plist-get response :last_started) :native_application)))
      (pcase field
        (:profile_id (setf (plist-get (plist-get application :identity) field) "other.runtime.v1"))
        (:catalogue_revision (setf (plist-get (plist-get application :identity) field) (make-string 64 ?2)))
        (:runtime_generation (setf (plist-get (plist-get application :identity) field) 8))
        (:masked_parameters (setf (plist-get application field) ["sm"])))
      (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t)))))

(ert-deftest omnivox-native-preview-native-and-common-comparison-negotiate-each-entry ()
  (emacsvox-test--with-complete-preview
   (omnivox-native-test--bundle speaker)
   (let ((entry (omnivox-native-test--entry)))
     (omnivox--preview-layered-sequence (list (omnivox-native-test--common entry) entry)
                                       (lambda (r) (push r results))))
   (should (equal (plist-get (emacsvox-test--omnivox-decode-command (car writes)) :type) "preview_voice_v2"))
   (let ((response (omnivox-native-test--terminal)))
     (setf (plist-get response :type) "preview_voice_completed_v2")
     (dolist (identity (list (aref (plist-get response :accepted_audio) 0) (plist-get response :last_started)))
       (cl-remf identity :native_application))
     (omnivox-preview-test--control-line speaker response))
   (should (equal (plist-get (emacsvox-test--omnivox-decode-command (car writes)) :type) "preview_voice_v3"))
   (omnivox-preview-test--control-line speaker (omnivox-native-test--terminal 42))
   (should (eq (plist-get (car results) :status) 'completed))
   (should (= 2 (length writes)))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-native-preview-accepted-audio-is-not-started-playback ()
  (dolist (status '("completed" "failed" "cancelled"))
    (let ((response (omnivox-native-test--terminal)))
      (setf (plist-get response :status) status
            (plist-get response :last_started) :null
            (plist-get (aref (plist-get response :accepted_audio) 0) :playback_started) :false)
      (let ((result (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t)))
        (should (plist-get result :terminal-confirmed)) (should-not (plist-get result :last-started)))
      (setf (plist-get (aref (plist-get response :accepted_audio) 0) :playback_started) t)
      (should-error (omnivox--normalize-layered-preview-response (omnivox-native-test--entry) response t)))))

(ert-deftest omnivox-native-preview-editor-freezes-comparison-with-private-evidence ()
  (emacsvox-test--with-complete-preview
   (omnivox-native-test--bundle speaker)
   (let* ((entry (omnivox-native-test--entry "paul-main"))
          (second (omnivox-native-test--entry "paul-main"))
          (omnivox-last-realized-routes (make-hash-table :test #'equal)))
     (puthash "bolden" 'ordinary-evidence omnivox-last-realized-routes)
     (process-put notifier 'omnivox--choice-registration 'notification-evidence)
     (emacsvox-aural-voice-editor--submit-preview (list entry second) (lambda (r) (push r results)) (lambda () t))
     (should (= stops 1))
     (setf (plist-get (plist-get second :voice) :choices) nil)
     (omnivox-preview-test--control-line speaker (omnivox-native-test--terminal))
     (let ((request (emacsvox-test--omnivox-decode-command (car writes))))
       (should (equal (plist-get request :type) "preview_voice_v3"))
       (should (= 4 (length (plist-get (plist-get request :voice) :choices))))
       (should (= (plist-get request :expected_base_rate) 0.65)))
     (omnivox-preview-test--control-line speaker (omnivox-native-test--terminal 42))
     (should (= 1 (length results)))
     (should (= 2 (length (plist-get (car results) :results))))
     (dolist (result (plist-get (car results) :results))
       (should (plist-get result :terminal-confirmed))
       (should (equal (plist-get (plist-get (plist-get result :last-started) :native_application) :plan_id) "plan-23")))
     (should (eq (gethash "bolden" omnivox-last-realized-routes) 'ordinary-evidence))
     (should (eq (process-get notifier 'omnivox--choice-registration) 'notification-evidence))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-native-preview-unconfirmed-first-half-stops-comparison ()
  (emacsvox-test--with-complete-preview
   (omnivox-native-test--bundle speaker)
   (omnivox--preview-layered-sequence (list (omnivox-native-test--entry) (omnivox-native-test--entry))
                                     (lambda (r) (push r results)))
   (let ((response (omnivox-native-test--terminal)))
     (setf (plist-get response :type) "preview_voice_completed_v2")
     (omnivox-preview-test--control-line speaker response))
   (should (= 1 (length writes)))
   (should (eq (plist-get (car results) :status) 'failed))
   (should-not (plist-get (car (plist-get (car results) :results)) :terminal-confirmed))
   (omnivox-preview-test--clean speaker)))

(provide 'omnivox-native-preview-tests)
;;; omnivox-native-preview-tests.el ends here
