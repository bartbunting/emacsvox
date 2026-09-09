;;; omnivox-choice-codec-tests.el --- Choice wire boundaries -*- lexical-binding: t; -*-
;;; Commentary:
;; Independent values exercise presence, neutral points and row identity.
;;; Code:
(require 'ert)
(require 'omnivox-voices)
(require 'omnivox-choice-codec)

(ert-deftest omnivox-choice-codec-keeps-inheritance-zero-and-default-distinct ()
  (let* ((raw '(:richness 0 :rate-offset 0 :low-pass nil :pan 5))
         (before (copy-tree raw))
         (wire (omnivox--choice-patch-json raw)))
    (should (equal wire '(:richness (:op "set" :value 0.0)
                         :rate_offset (:op "set" :value 0)
                         :low_pass (:op "default")
                         :pan (:op "set" :value 0.5))))
    (should-not (plist-member wire :stress))
    (should (equal raw before))
    (should (hash-table-p (omnivox--choice-patch-json nil)))))

(ert-deftest omnivox-choice-codec-context-nil-retains-old-acss-meaning ()
  (let ((patch '(:richness nil :rate-offset nil :echo nil :stress 0)))
    (should (equal (omnivox--choice-patch-json patch t)
                   '(:stress (:op "set" :value 0.0)
                     :rate_offset (:op "default") :echo (:op "default"))))
    (should (equal (plist-get (omnivox--choice-patch-json patch) :richness)
                   '(:op "default")))))

(ert-deftest omnivox-choice-codec-uses-the-same-contrast-and-neutral-points ()
  (let* ((omnivox-average-pitch-contrast 0.0)
         (raw '(:average-pitch 9 :gain 5 :pan 9 :low-pass 0 :high-pass 9))
         (shared (omnivox--choice-style-json raw))
         (patch (omnivox--choice-patch-json raw)))
    (should (= (plist-get (plist-get shared :acss) :average_pitch) (/ 5.0 9.0)))
    (should (= (plist-get (plist-get patch :average_pitch) :value) (/ 5.0 9.0)))
    (should (equal (plist-get shared :effects)
                   '(:gain 0.5 :low_pass 0.0 :high_pass 1.0 :pan 1.0
                     :reverb :null :echo :null :chorus :null)))))

(ert-deftest omnivox-choice-codec-completes-shared-nulls-and-rejects-ambiguity ()
  (let ((shared (omnivox--choice-shared-json '(:rate 0.0 :volume 1.0) nil nil)))
    (should (equal (plist-get shared :acss)
                   '(:rate 0.0 :average_pitch :null :pitch_range :null
                     :stress :null :richness :null :volume 1.0)))
    (should (eq (plist-get shared :rate_offset) :null)))
  (should-error (omnivox--choice-shared-json '(:rate 0) 0 nil))
  (dolist (invalid '(21 -21 1.0 t))
    (should-error (omnivox--choice-shared-json nil invalid nil)))
  (dolist (invalid '(1.01 -0.01 t "1"))
    (should-error (omnivox--choice-shared-json (list :stress invalid) nil nil))))

(ert-deftest omnivox-choice-codec-preserves-duplicate-physical-occurrences ()
  (let* ((selector '(:kind exact :scope local :engine-id "eloquence" :voice-id "Reed"))
         (rows (list (list :id "normal" :selector selector :adjustments '(:richness 0))
                     (list :id "soft" :selector selector :adjustments '(:richness nil))))
         (wire (omnivox--choice-records-json rows)))
    (should (equal (mapcar (lambda (row) (plist-get row :id)) wire) '("normal" "soft")))
    (should (equal (plist-get (aref wire 0) :selector) (plist-get (aref wire 1) :selector)))
    (should-not (equal (plist-get (aref wire 0) :adjustments)
                       (plist-get (aref wire 1) :adjustments)))
    (should-error (omnivox--choice-records-json (list (car rows) (car rows))))))

(ert-deftest omnivox-choice-codec-does-not-clamp-malformed-saved-patches ()
  (dolist (patch '((:richness 10) (:richness 0.5) (:low-pass -1)
                   (:gain 5 :gain 0) (:unknown 1) (:rate 3)))
    (should-error (omnivox--choice-patch-json patch))))

(defun omnivox-choice-codec-test--receipt ()
  "Return an independent actual-choice wire receipt."
  (list :protocol_version 3 :dispatch_id 41 :sequence 2 :type "voice_choice_applied"
        :utterance_id 8 :span_id 1 :registry_generation 6 :logical_voice_id "bolden"
        :choice (list :choice_id "alternate" :reason '(:reason "explicit_alternative" :preference_index 1)
                      :realized '(:engine_id "eloquence" :voice_id "Reed")
                      :degraded_acss [] :degraded_effects ["chorus"])))

(defun omnivox-choice-codec-test--decode (event)
  "Round-trip EVENT through the strict encoded record boundary."
  (omnivox--choice-decode-marker
   (base64-encode-string (encode-coding-string (json-serialize event) 'utf-8 t) t)))

(ert-deftest omnivox-choice-codec-marker-receipt-preserves-exact-row-and-policy-null ()
  (let ((event (omnivox-choice-codec-test--receipt)))
    (should (equal (omnivox-choice-codec-test--decode event) event))
    (let ((choice (plist-get event :choice)))
      (setf (plist-get choice :choice_id) :null
            (plist-get choice :reason) '(:reason "fallback_engine" :fallback_index 0)))
    (should (eq (plist-get (plist-get (omnivox-choice-codec-test--decode event) :choice) :choice_id) :null))))

(ert-deftest omnivox-choice-codec-marker-rejects-duplicate-members-at-every-depth ()
  (let ((json (json-serialize (omnivox-choice-codec-test--receipt))))
    (dolist (pair '(("\"dispatch_id\":41" . "\"dispatch_id\":41,\"dispatch_id\":42")
                    ("\"choice_id\":\"alternate\"" . "\"choice_id\":\"alternate\",\"choice_id\":null")
                    ("\"preference_index\":1" . "\"preference_index\":1,\"preference_index\":2")
                    ("\"engine_id\":\"eloquence\"" . "\"engine_id\":\"eloquence\",\"engine_id\":\"espeak\"")))
      (let ((invalid (string-replace (car pair) (cdr pair) json)))
        (should-not (equal invalid json))
        (should-error (omnivox--choice-decode-marker (base64-encode-string invalid t)))))))

(ert-deftest omnivox-choice-codec-marker-rejects-shape-type-and-identity-errors ()
  (dolist (field '(:dispatch_id :sequence :utterance_id :span_id :registry_generation))
    (dolist (value (list 0 -1 1.0 :null "1" (1+ omnivox--choice-u64-max)))
      (let ((event (omnivox-choice-codec-test--receipt)))
        (setf (plist-get event field) value)
        (should-error (omnivox-choice-codec-test--decode event)))))
  (dolist (mutate
           (list (lambda (event) (plist-put event :extra t))
                 (lambda (event) (cl-remf event :choice) event)
                 (lambda (event) (setf (plist-get (plist-get event :choice) :choice_id) :null) event)
                 (lambda (event) (setf (plist-get (plist-get event :choice) :reason) '(:reason "global_default")) event)
                 (lambda (event) (setf (plist-get (plist-get event :choice) :degraded_acss) :null) event)
                 (lambda (event) (setf (plist-get (plist-get event :choice) :degraded_effects) ["unknown"]) event)))
    (should-error (omnivox-choice-codec-test--decode (funcall mutate (omnivox-choice-codec-test--receipt))))))

(ert-deftest omnivox-choice-codec-marker-enforces-both-wire-bounds-and-canonical-base64 ()
  (let* ((json (json-serialize (omnivox-choice-codec-test--receipt)))
         (at-limit (concat json (make-string (- omnivox--choice-receipt-limit (string-bytes json)) ?\s))))
    (should (omnivox--choice-decode-marker (base64-encode-string at-limit t)))
    (should-error (omnivox--choice-decode-marker (base64-encode-string (concat at-limit " ") t)))
    (should-error (omnivox--choice-decode-marker (concat (base64-encode-string json t) "\n"))))
  (let ((event (list :protocol_version 3 :dispatch_id 1 :sequence 1 :type "utterance_started"
                     :utterance_id 1 :text (make-string 400000 ?a) :engine_id "espeak"
                     :actual_voice :null :logical_voice_id :null :sample_rate 22050 :frame_count 0)))
    (should-error (omnivox-choice-codec-test--decode event))))

(ert-deftest omnivox-choice-codec-marker-retains-existing-event-variants-under-version-three ()
  (let ((base '(:protocol_version 3 :dispatch_id 1 :sequence 1 :utterance_id 1)))
    (dolist (fields
             '((:type "utterance_started" :text "héllo" :engine_id "espeak" :actual_voice :null
                      :logical_voice_id :null :sample_rate 22050 :frame_count 0)
               (:type "marker_reached" :marker (:kind "word" :frame_offset 0 :text_start 0 :text_length 5 :value :null))
               (:type "semantic_event_reached" :action_id "semantic.1")
               (:type "timeline_action_resolved" :action_id "semantic.1" :resolution "span_boundary")
               (:type "timeline_style_degraded" :degraded_acss ["stress"] :degraded_effects [])))
      (let ((event (append base fields)))
        (should (equal (omnivox-choice-codec-test--decode event) event))))))

(provide 'omnivox-choice-codec-tests)
;;; omnivox-choice-codec-tests.el ends here
