;;; omnivox-choice-registration-tests.el --- Per-lane layered registries -*- lexical-binding: t; -*-
;;; Commentary:
;; Real request tables, frozen operations and old/new lane combinations.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-voice-choice-tests)
(require 'omnivox-voices)

(defconst omnivox-test--choice-features
  '("logical_voice_registration" "voice_choice_tuning_v1"
    "presentation_timeline_v4" "playback_marker_events_v3"))

(defun omnivox-test--choice-decode-command (command)
  "Decode captured control COMMAND using the normal plist/list reader."
  (let* ((encoded (string-trim (substring command (length "omnivox_control "))))
         (payload (substring encoded 1 -1)))
    (json-parse-string (decode-coding-string (base64-decode-string payload) 'utf-8 t)
                       :object-type 'plist :array-type 'list :null-object nil :false-object nil)))

(defmacro omnivox-test--with-choice-registration (&rest body)
  "Run BODY against isolated tuned storage and two controlled process lanes."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-tuned-storage
    (let* ((speaker (make-pipe-process :name "choice-main" :noquery t))
           (notification (make-pipe-process :name "choice-notify" :noquery t))
           (tts-speaker-process speaker) (tts-notify-process notification)
           (emacsvox-aural-voice-palette-override 'reading)
           (emacsvox-aural-session-routing-bindings nil)
           (omnivox--logical-registry-generation 0)
           (omnivox--logical-registry-signature nil)
           (omnivox-average-pitch-contrast 1.0)
           (omnivox-logical-voice-preferences nil)
           (omnivox-logical-voice-languages nil)
           (omnivox-engine-priority-ids nil) (omnivox-fallback-engine-ids nil)
           (omnivox-disabled-engine-ids nil)
           (omnivox-global-default-selector nil)
           (omnivox-initial-routing-ready-hook nil)
           (omnivox-voice-configuration-applied-hook nil)
           requests terminal)
      (unwind-protect
          (cl-letf (((symbol-function 'process-send-string)
                     (lambda (process command)
                       (push (cons process (omnivox-test--choice-decode-command command)) requests)))
                    ((symbol-function 'omnivox--logical-voice-ids)
                     (lambda () '("bolden" "voice-bolden" "unrelated"))))
            (dolist (process (list speaker notification))
              (process-put process omnivox--control-capabilities-property
                           (list :features omnivox-test--choice-features)))
            ,@body)
        (delete-process speaker)
        (delete-process notification)))))

(defun omnivox-test--choice-registration-ack (write)
  "Acknowledge captured WRITE using the actual versioned response shape."
  (let* ((request (cdr write))
         (generation (plist-get request :registry_generation)))
    (append (list :protocol_version 1 :request_id (plist-get request :request_id))
            (if (equal (plist-get request :type) "register_logical_voices_v2")
                (list :type "logical_voices_registered_v2" :registry_generation generation
                      :inventory_generation 1 :definition_count (length (plist-get request :definitions))
                      :unresolved_logical_voice_ids [])
              (list :type "logical_voices_registered"
                    :registration (list :registry_generation generation :bindings []))))))

(ert-deftest omnivox-choice-registration-negotiates-the-whole-bundle-per-lane ()
  (omnivox-test--with-choice-registration
   (dolist (missing '("voice_choice_tuning_v1" "presentation_timeline_v4" "playback_marker_events_v3"))
     (process-put notification omnivox--control-capabilities-property
                  (list :features (remove missing omnivox-test--choice-features)))
     (should-not (omnivox--choice-tuning-supported-p notification))
     (let ((content (omnivox--process-logical-registry-content notification)))
       (should-not (plist-get content :type))
       (should (plist-member (aref (plist-get content :definitions) 0) :preferences))))
   (should (omnivox--choice-tuning-supported-p speaker))
   (let* ((content (omnivox--process-logical-registry-content speaker))
          (definitions (plist-get content :definitions))
          (first (plist-get (aref definitions 0) :definition))
          (alias (plist-get (aref definitions 1) :definition)))
     (should (equal (plist-get content :type) "register_logical_voices_v2"))
     (should (equal (plist-get first :choices) (plist-get alias :choices)))
     (should (equal (mapcar (lambda (row) (plist-get row :id)) (plist-get first :choices))
                    (mapcar (lambda (row) (plist-get row :id)) (emacsvox-test--tuned-choices))))
     (should (equal (plist-get (aref definitions 2) :mode) "legacy"))
     (should (plist-member (plist-get content :fallback_policy) :preferred_engines))
     (should (plist-member (plist-get first :shared) :rate_offset)))))

(ert-deftest omnivox-choice-registration-freezes-new-and-old-operations ()
  (omnivox-test--with-choice-registration
   (process-put notification omnivox--control-capabilities-property
                '(:features ("logical_voice_registration")))
   (omnivox-apply-voice-configuration (lambda (result) (push result terminal)))
   (should (= (length requests) 2))
   (let ((sent (copy-tree requests)))
     ;; Changes after submission cannot become the acknowledged registry.
     (setf (plist-get (car (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)) :adjustments)
           '(:richness 9))
     (dolist (write sent)
       (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))
     (should (= (length terminal) 1))
     (should (eq (plist-get (car terminal) :status) 'applied))
     (should (equal (plist-get (cdr (assq speaker sent)) :type) "register_logical_voices_v2"))
     (should (equal (plist-get (cdr (assq notification sent)) :type) "register_logical_voices"))
     (should (equal (json-parse-string
                     (json-serialize (plist-get (plist-get (process-get speaker omnivox--choice-registration-property) :content) :definitions))
                     :object-type 'plist :array-type 'list :null-object nil :false-object nil)
                    (plist-get (cdr (assq speaker sent)) :definitions)))
     (should (plist-get (car terminal) :choice-tuning-unapplied))
     (should-not (plist-member (cdr (assq notification sent)) :choice-tuning-unapplied))
     (should-not (process-get notification omnivox--choice-registration-property)))))

(ert-deftest omnivox-choice-registration-rejects-mismatched-flat-acknowledgements ()
  (omnivox-test--with-choice-registration
   (setq tts-notify-process nil)
   (dolist (field '(:registry_generation :definition_count :inventory_generation :unresolved_logical_voice_ids))
     (setq requests nil terminal nil)
     (omnivox-apply-voice-configuration (lambda (result) (push result terminal)))
     (let ((ack (omnivox-test--choice-registration-ack (car requests))))
       (setq ack (plist-put ack field (if (eq field :unresolved_logical_voice_ids) ["not-registered"] -1)))
       (omnivox--dispatch-control-response speaker ack))
     (should (eq (plist-get (car terminal) :status) 'failed))
     (should-not (process-get speaker omnivox--choice-registration-property)))))

(ert-deftest omnivox-choice-registration-late-ack-cannot-replace-newer-snapshot ()
  (omnivox-test--with-choice-registration
   (setq tts-notify-process nil)
   (omnivox-register-logical-voices)
   (let ((old (car requests)))
     (setf (plist-get (car (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)) :adjustments)
           '(:richness 9))
     (omnivox-register-logical-voices)
     (let ((new (car requests)))
       (should (< (plist-get (cdr old) :registry_generation) (plist-get (cdr new) :registry_generation)))
       (omnivox--dispatch-control-response speaker (omnivox-test--choice-registration-ack new))
       (let ((accepted (copy-tree (process-get speaker omnivox--choice-registration-property))))
         (omnivox--dispatch-control-response speaker (omnivox-test--choice-registration-ack old))
         (should (equal accepted (process-get speaker omnivox--choice-registration-property))))))))

(ert-deftest omnivox-choice-registration-temporary-routing-never-joins-saved-patches ()
  (omnivox-test--with-choice-registration
   (let* ((selector (plist-get (car (emacsvox-test--tuned-choices)) :selector))
          (emacsvox-aural-session-routing-bindings (list (cons 'bolden (list selector))))
          (definition (omnivox--choice-definition-json (omnivox--logical-definition-json "bolden" nil t)))
          (rows (plist-get (plist-get definition :definition) :choices)))
     (should (= (length rows) 1))
     (should (hash-table-p (plist-get (aref rows 0) :adjustments)))
     (should (= (hash-table-count (plist-get (aref rows 0) :adjustments)) 0)))))

(ert-deftest omnivox-choice-registration-unsupported-warning-belongs-to-the-connection ()
  (omnivox-test--with-choice-registration
   (let (messages)
     (cl-letf (((symbol-function 'message) (lambda (format-string &rest args)
                                          (push (apply #'format format-string args) messages))))
       (dolist (process (list speaker speaker notification notification))
         (omnivox--choice-warn-unapplied process '(:choice-tuning-unapplied t))))
     (should (= (length messages) 2)))
   (let* ((draft (emacsvox-aural-voice-drafts--make))
          (proposal (emacsvox-aural-voice-drafts--make-save
                     :state 'applied :result '(:choice-tuning-unapplied t))))
     (setf (emacsvox-aural-voice-draft-proposal draft) proposal)
     (should (equal (plist-get (emacsvox-aural-voice-drafts--status draft) :label)
                    "Saved; individual tuning not applied")))))

(provide 'omnivox-choice-registration-tests)
;;; omnivox-choice-registration-tests.el ends here
