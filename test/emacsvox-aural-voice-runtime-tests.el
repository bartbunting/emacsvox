;;; emacsvox-aural-voice-runtime-tests.el --- Owned voice runtime tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Check owned routes at registration, compiler and preview boundaries.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-data-tests)
(require 'emacsvox-aural-voice-runtime)
(require 'emacsvox-aural-compiler)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-voice-workbench)
(require 'omnivox-voices)

(defmacro emacsvox-test--with-owned-runtime (&rest body)
  "Run BODY with independent owned palettes and deliberately different legacy routing."
  (declare (indent 0) (debug t))
  `(let* ((standard-root (emacsvox-aural-voice-palette 'acss-default))
          (inputs (emacsvox-test--voice-resolution-inputs))
          (emacsvox-aural-voice-palette-registry (plist-get inputs :registry))
          (emacsvox-aural-routing--choice-sets (plist-get inputs :sets))
          (emacsvox-aural-voice-palette-override 'reading-owned)
          (emacsvox-aural-voice-runtime--palette nil)
          (emacsvox-aural-voice-runtime--last-snapshot nil)
          (emacsvox-aural-routing--apply-operation 0)
          (emacsvox-aural-voice-runtime--defer-apply nil)
          (emacsvox-aural-session-routing-bindings nil)
          (emacsvox-aural-session-engine-order nil)
          (emacsvox-aural-configuration-changed-hook
           '(emacsvox-aural-voice-runtime--configuration-changed))
          (emacsvox-aural-routing-profile-changed-hook
           '(emacsvox-aural-voice-runtime--configuration-changed))
          (emacsvox-aural-voice-palette-changed-hook nil)
          (emacsvox-aural-routing-apply-status-hook nil)
          (emacsvox-aural-routing-apply-status nil)
          (omnivox--logical-acss-table (make-hash-table :test #'equal))
          (omnivox-average-pitch-contrast 1.0)
          (omnivox-logical-voice-preferences
           '((voice-bolden (exact "legacy" "Old"))
             (voice-annotate (exact "legacy" "Annotation"))
             (unrelated (exact "legacy" "Other"))))
          (omnivox-logical-voice-languages nil)
          (omnivox-engine-priority-ids '("dectalk" "eloquence"))
          (omnivox-fallback-engine-ids '("espeak"))
          (omnivox-disabled-engine-ids nil)
          (omnivox-global-default-selector nil)
          (omnivox-allow-same-language-fallback t))
     ;; Runtime palettes participate in the explicit standard inheritance tree.
     ;; Keep the independent old-format choice fixtures for the data tests.
     (puthash 'acss-default standard-root emacsvox-aural-voice-palette-registry)
     (dolist (id '(reading-owned alternative-owned source-base))
       (let ((data (emacsvox-aural-voice-palette-data-form
                    (emacsvox-aural-voice-palette id))))
         (setf (plist-get data :parent) 'acss-default)
         (puthash id (emacsvox-aural-compile-voice-palette-data data)
                  emacsvox-aural-voice-palette-registry)))
     ,@body))

(ert-deftest emacsvox-aural-voice-runtime-registration-keeps-owned-and-legacy-scopes ()
  "Owned choices and aliases override old bindings; unrelated IDs remain unchanged."
  (emacsvox-test--with-owned-runtime
   (let ((first (omnivox--logical-definition-json "voice-bolden" "legacy" t))
         (automatic (omnivox--logical-definition-json "voice-annotate" "legacy" t))
         (unrelated (omnivox--logical-definition-json "unrelated" "legacy" t)))
     (should (equal (plist-get first :preferences)
                    [(:kind "exact" :engine_id "dectalk" :voice_id "Paul")
                     (:kind "properties" :engine_id "eloquence" :language :null :gender "male")]))
     (should (= (plist-get (plist-get first :acss) :average_pitch) 0.0))
     (should (equal (plist-get first :language) "en-AU"))
     (should (equal (plist-get automatic :preferences) []))
     (should (equal (plist-get unrelated :preferences)
                    [(:kind "exact" :engine_id "legacy" :voice_id "Other")]))
     (setq emacsvox-aural-voice-palette-override 'alternative-owned)
     (should (equal (plist-get (omnivox--logical-definition-json "bolden" nil t) :preferences)
                    [(:kind "exact" :engine_id "eloquence" :voice_id "Reed")]))
     (setq emacsvox-aural-voice-palette-override 'reading-owned)
     (should (equal first (omnivox--logical-definition-json "voice-bolden" "legacy" t))))
   (should (member "bolden" (omnivox--logical-voice-ids)))
   (should (member "voice-bolden" (omnivox--logical-voice-ids)))
   (let ((omnivox-engine-priority-ids nil))
     (should (equal (plist-get (omnivox--logical-definition-json "annotate" "startup" nil) :preferences)
                    [(:kind "engine_default" :engine_id "startup")])))))

(ert-deftest emacsvox-aural-voice-runtime-selection-guards-stale-callbacks ()
  "A-B-A applies distinct snapshots and an old completion cannot replace status."
  (emacsvox-test--with-owned-runtime
   (let (calls)
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&optional callback)
                  (push (list emacsvox-aural-voice-palette-override
                              (omnivox--logical-definition-json "voice-bolden" nil t) callback) calls))))
       (dolist (palette '(reading-owned alternative-owned reading-owned))
         (emacsvox-aural-select-voice-palette palette))
       (should (= (length calls) 3))
       (funcall (nth 2 (car calls)) '(:status partial :processes ((:role speaker :status applied)
                                                                  (:role notification :status failed))))
       (funcall (nth 2 (cadr calls)) '(:status applied))
       (should (eq (plist-get emacsvox-aural-routing-apply-status :palette) 'reading-owned))
       (should (eq (plist-get emacsvox-aural-routing-apply-status :status) 'partial))
       (should (equal (nth 1 (car calls)) (nth 1 (car (last calls)))))
       (emacsvox-aural-select-voice-palette 'source-child)
       (should (equal (plist-get (nth 1 (car calls)) :preferences)
                      [(:kind "exact" :engine_id "legacy" :voice_id "Old")]))))))

(ert-deftest emacsvox-aural-voice-runtime-conflicting-session-change-rolls-back ()
  "Alias conflicts fail before changing live session state or starting an apply."
  (emacsvox-test--with-owned-runtime
   (let ((emacsvox-aural-session-routing-bindings
          '((voice-bolden (:kind exact :scope session :engine-id "dectalk" :voice-id "Paul")))))
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&rest _) (ert-fail "Conflict must not apply"))))
       (should-error
        (emacsvox-aural-set-session-routing-binding
         'bolden '((:kind exact :scope local :engine-id "eloquence" :voice-id "Reed")))
        :type 'emacsvox-aural-voice-data-conflict)
       (should (= (length emacsvox-aural-session-routing-bindings) 1))
       (should (eq (caar emacsvox-aural-session-routing-bindings) 'voice-bolden))))))

(ert-deftest emacsvox-aural-voice-runtime-compiler-preserves-cascade-and-identity ()
  "Contextual patches keep the owned base, routing name and transported effects."
  (emacsvox-test--with-owned-runtime
   (cl-letf (((symbol-function 'emacsvox-aural-active-voice-capabilities)
              (lambda () '(:adapter omnivox :family-selection routed
                                    :dimensions (family average-pitch pitch-range stress richness rate-offset))))
             ((symbol-function 'tts-voice-capabilities)
              (lambda () '(:adapter omnivox :family-selection routed)))
             ((symbol-function 'voice-from-acss) (lambda (&rest _) 'generated-test))
             ((symbol-function 'tts-get-voice-command) (lambda (_voice) "[[logical_voice generated-test]]")))
     (let* ((compiled (emacsvox-aural-compile-voice-style
                       '(:preset voice-bolden :average-pitch 8 :echo nil) 'reading-owned))
            (style (emacsvox-aural-compiled-voice-style compiled))
            (effects (emacsvox-aural--timeline-style-effects style)))
       (should (= (plist-get style :average-pitch) 8))
       (should (= (plist-get style :richness) 9))
       (should (= (plist-get style :rate-offset) -4))
       (should (= (plist-get style :low-pass) 7))
       (should-not (plist-get style :echo))
       (should (= (plist-get effects :gain) 0.5))
       (should (= (plist-get effects :pan) 0.5))
       (should (= (plist-get effects :low_pass) (/ 7.0 9)))
       (should (equal (emacsvox-aural--timeline-logical-voice
                       (emacsvox-aural-compiled-voice-command compiled)
                       (emacsvox-aural-compiled-voice-request compiled)) "voice-bolden")))
     (let ((voice-annotate (make-acss :average-pitch 3 :richness 6)))
       (should (emacsvox-aural-compiled-voice-p
                (emacsvox-aural-compile-voice-style 'voice-annotate 'reading-owned)))))))

(ert-deftest emacsvox-aural-voice-runtime-workbench-previews-the-complete-owned-chain ()
  "Logical preview uses owned choices, frozen policy and existing shared normalization."
  (emacsvox-test--with-owned-runtime
   (let ((emacsvox-aural-voice-workbench-staged-profile
          (emacsvox-aural-routing-profile-from-omnivox 'staged)))
     (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--active-palette)
                (lambda () 'reading-owned)))
       (let ((entry (emacsvox-aural-voice-workbench--logical-preview-entry 'voice-bolden)))
         (should (plist-member entry :selectors))
         (should-not (plist-member entry :selector))
         (should (equal (plist-get entry :selectors)
                        (plist-get (car emacsvox-aural-routing--choice-sets) :selectors)))
         (should (= (plist-get entry :rate-offset) -4))
         (should (= (plist-get (plist-get entry :acss) :average-pitch) 0.0))
         (should (= (plist-get (plist-get entry :effects) :gain) 0.5))
         (should (= (plist-get (plist-get entry :effects) :pan) 0.5))
         (should (equal (plist-get (plist-get entry :fallback-policy) :preferred-engines)
                        '("dectalk" "eloquence"))))))))

(ert-deftest emacsvox-aural-voice-runtime-two-lanes-freeze-owned-registrations ()
  "Real requests retain their palette snapshot and report partial lane failure."
  (emacsvox-test--with-owned-runtime
   (let* ((speaker (make-pipe-process :name "owned-main" :noquery t))
          (notification (make-pipe-process :name "owned-notify" :noquery t))
          (tts-speaker-process speaker) (tts-notify-process notification)
          (omnivox--logical-registry-generation 0)
          (omnivox--logical-registry-signature nil)
          (omnivox-voice-configuration-applied-hook nil)
          (omnivox-initial-routing-ready-hook nil)
          (omnivox-logical-voice-registration nil)
          (omnivox-voice-configuration-last-result nil)
          (real-run-at-time (symbol-function 'run-at-time))
          writes timers)
     (unwind-protect
         (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                    #'omnivox-apply-voice-configuration)
                   ((symbol-function 'run-at-time)
                    (lambda (&rest args)
                      (let ((timer (apply real-run-at-time args)))
                        (push timer timers) timer)))
                   ((symbol-function 'process-send-string)
                    (lambda (process command)
                      (push (cons process
                                  (json-parse-string
                                   (decode-coding-string
                                    (base64-decode-string (substring (nth 1 (split-string command)) 1 -1)) 'utf-8)
                                   :object-type 'plist :array-type 'list
                                   :null-object :null :false-object :false)) writes))))
           (dolist (process (list speaker notification))
             (process-put process omnivox--control-capabilities-property
                          '(:features ("runtime_routing_policy" "logical_voice_registration"))))
           (emacsvox-aural-select-voice-palette 'reading-owned)
           (ert-info ((format "Apply result: %S" emacsvox-aural-routing-apply-status))
             (should (= (length writes) 2)))
           ;; Mutate the selection after submission to establish that the
           ;; policy replies cannot recapture another palette's definitions.
           (let ((emacsvox-aural-voice-palette-override 'alternative-owned))
             (dolist (write (copy-sequence writes))
               (let ((request (cdr write)))
                 (should (equal (plist-get request :type) "set_routing_policy"))
                 (omnivox--dispatch-control-response
                  (car write)
                  (list :protocol_version 1 :request_id (plist-get request :request_id)
                        :type "routing_policy_applied"
                        :routing_policy
                        (list :routing_policy_generation (plist-get request :routing_policy_generation)
                              :policy (list :preferred_engine_ids (plist-get request :preferred_engine_ids)
                                            :fallback_engine_ids (plist-get request :fallback_engine_ids)
                                            :disabled_engine_ids (plist-get request :disabled_engine_ids))))))))
           (let ((registrations (cl-remove-if-not
                                 (lambda (write) (equal (plist-get (cdr write) :type) "register_logical_voices"))
                                 writes)))
             (should (= (length registrations) 2))
             (should (equal (plist-get (cdar registrations) :definitions)
                            (plist-get (cdadr registrations) :definitions)))
             (dolist (write registrations)
               (let* ((request (cdr write))
                      (definition (cl-find "voice-bolden" (plist-get request :definitions)
                                           :key (lambda (d) (plist-get d :id)) :test #'equal)))
                 (should (equal (plist-get definition :preferences)
                                '((:kind "exact" :engine_id "dectalk" :voice_id "Paul")
                                  (:kind "properties" :engine_id "eloquence" :language :null :gender "male"))))
                 (omnivox--dispatch-control-response
                  (car write)
                  (append (list :protocol_version 1 :request_id (plist-get request :request_id))
                          (if (eq (car write) speaker)
                              (list :type "logical_voices_registered"
                                    :registration (list :registry_generation (plist-get request :registry_generation)
                                                        :bindings nil))
                            '(:type "error" :code "invalid_configuration" :message "Test rejection")))))))
           (should (eq (plist-get emacsvox-aural-routing-apply-status :status) 'partial))
           (should (eq (plist-get emacsvox-aural-routing-apply-status :palette) 'reading-owned))
           (should (equal (mapcar (lambda (lane) (cons (plist-get lane :role) (plist-get lane :status)))
                                  (plist-get emacsvox-aural-routing-apply-status :processes))
                          '((speaker . applied) (notification . failed)))))
       (dolist (timer timers) (cancel-timer timer))
       (delete-process speaker)
       (delete-process notification)))))

(ert-deftest emacsvox-aural-voice-runtime-static-projection-uses-explicit-palette ()
  "Inactive palette compilation projects that palette's choices for standalone TTS."
  (emacsvox-test--with-owned-runtime
   (let ((capabilities '(:adapter dectalk :family-selection enumerated
                                  :dimensions (family average-pitch pitch-range stress richness rate-offset)
                                  :families ((paul :id "Paul" :default t) (harry :id "Harry")))))
     (cl-letf (((symbol-function 'emacsvox-aural-active-voice-capabilities) (lambda () capabilities))
               ((symbol-function 'tts-voice-capabilities) (lambda () capabilities))
               ((symbol-function 'tts-voice-inventory) (lambda () nil))
               ((symbol-function 'voice-from-acss) (lambda (&rest _) 'compiled-test))
               ((symbol-function 'tts-get-voice-command) (lambda (_) "test")))
       (let ((emacsvox-aural-voice-palette-override 'alternative-owned)
             (omnivox-engine-priority-ids nil)
             (omnivox-fallback-engine-ids nil))
         (should (eq (plist-get (emacsvox-aural-compiled-voice-style
                                 (emacsvox-aural-compile-voice-style 'voice-bolden 'reading-owned)) :family) 'paul))
         (let ((emacsvox-aural-voice-runtime--palette 'reading-owned)
               (omnivox-disabled-engine-ids '("dectalk")))
           (should (eq (emacsvox-aural-routing-static-family 'voice-bolden 'harry capabilities nil) 'harry))))))))

(ert-deftest emacsvox-aural-voice-runtime-automatic-preview-keeps-startup-policy ()
  "Automatic has no owned selectors and honors the foreground startup default."
  (emacsvox-test--with-owned-runtime
   (let ((omnivox-engine-priority-ids nil))
     (cl-letf (((symbol-function 'tts-voice-inventory)
                (lambda () '(:preferred-engine-id "startup"))))
       (let ((resolved (emacsvox-aural-voice-runtime--owned 'annotate)))
         (should (plist-get resolved :automatic))
         (should-not (plist-get resolved :selectors))
         (should (equal (plist-get (emacsvox-aural-voice-runtime--preview-policy resolved) :preferred-engines)
                        '("startup"))))))))

(ert-deftest emacsvox-aural-voice-runtime-new-palette-owns-status-after-profile-apply ()
  "An older routing-profile completion cannot replace a newer palette's status."
  (emacsvox-test--with-owned-runtime
   (let* ((data (emacsvox-aural-routing-profile-from-omnivox 'test-profile))
          (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
          (emacsvox-aural-active-routing-profile 'test-profile)
          (emacsvox-aural-voice-runtime--last-snapshot (emacsvox-aural-voice-runtime--snapshot))
          callbacks caller-result)
     (puthash 'test-profile (emacsvox-aural-routing--make-entry :id 'test-profile :data data)
              emacsvox-aural-routing-profile-registry)
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&optional callback) (push callback callbacks))))
       (emacsvox-aural-apply-routing-profile nil (lambda (result) (setq caller-result result)))
       (emacsvox-aural-select-voice-palette 'alternative-owned)
       (should (= (length callbacks) 2))
       (funcall (car callbacks) '(:status partial))
       (funcall (cadr callbacks) '(:status applied))
       (should (eq (plist-get caller-result :status) 'applied))
       (should (eq (plist-get emacsvox-aural-routing-apply-status :palette) 'alternative-owned))
       (should (eq (plist-get emacsvox-aural-routing-apply-status :status) 'partial))))))

(provide 'emacsvox-aural-voice-runtime-tests)

;;; emacsvox-aural-voice-runtime-tests.el ends here
