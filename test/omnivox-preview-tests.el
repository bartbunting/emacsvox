;;; omnivox-preview-tests.el --- Private preview ownership contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise real coordinator, Stop and stream observation with muted primitives.
;;; Code:
(require 'ert)
(require 'emacsvox-tts-tests)
(require 'tts-queue-state-tests)

(defconst omnivox-preview-test--wire-fixture
  (expand-file-name "fixtures/voice-editor/fallback-tuning-wire.json"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun omnivox-preview-test--entry (individual)
  (if individual (emacsvox-test--individual-preview-entry)
    (emacsvox-test--complete-preview-entry)))

(defun omnivox-preview-test--start (individual &optional count callback)
  (omnivox-preview-voice-sequence
   (make-list (or count 1) (omnivox-preview-test--entry individual)) (or callback #'ignore)))

(defun omnivox-preview-test--reply (speaker id individual)
  (omnivox--dispatch-control-response
   speaker (if individual (emacsvox-test--individual-preview-response id)
             ;; Match normal legacy decoding, which maps arrays/null to lists/nil.
             (omnivox--decode-control-response
              (base64-encode-string
               (json-serialize (emacsvox-test--complete-preview-response id)) t)))))

(defun omnivox-preview-test--clean (speaker)
  (should-not (process-get speaker 'omnivox--preview-operation))
  (should-not (process-get speaker 'tts--interrupt-listener))
  (should-not tts-stopped-hook)
  (should (zerop (hash-table-count (omnivox--pending-requests speaker)))))

(ert-deftest omnivox-preview-startup-clears-framed-pending-queue ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (tts-queue--send-typed speaker "q {earlier}\n" 'queue)
     (setq writes nil)
     (omnivox-preview-test--start individual)
     (should (= stops 1))
     (should (= (length writes) 1))
     (should (tts-queue--known-empty-p speaker))
     (omnivox-preview-test--reply speaker 41 individual)
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-startup-grant-cannot-send-speech-or-clear-twice ()
  (tts-queue-state-test--with-process
   (tts-queue--send-typed process "q {earlier}\n" 'queue)
   (let ((guard (tts-queue--startup-guard process)))
     (should guard)
     (should-error (tts-queue--send process "q {new}\n" (tts-queue--describe "q {new}\n" 'queue) nil guard))
     (should (= (length writes) 1))))
  (tts-queue-state-test--with-process
   (let* ((guard (tts-queue--startup-guard process))
          (receipt (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear) nil guard t)))
     (tts-queue--advance-stop guard receipt)
     (should (tts-queue--guard-valid-p guard))
     (should-not (tts-queue--guard-startup guard))
     (should-error (tts-queue--advance-stop guard receipt))
     (should-error (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear) nil guard t))
     (should (= (length writes) 1)))))

(ert-deftest omnivox-preview-unproven-boundary-rejects-before-stop ()
  (emacsvox-test--with-complete-preview
   (process-send-string speaker "q {")
   (setq writes nil)
   (should-error (omnivox-preview-test--start nil))
   (should-not writes)
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-stop-during-preflight-cancels-startup ()
  (emacsvox-test--with-complete-preview
   (let ((prepare (symbol-function 'omnivox--preview-complete-request)))
     (cl-letf (((symbol-function 'omnivox--preview-complete-request)
                (lambda (&rest args) (prog1 (apply prepare args) (tts-stop)))))
       (should-error (omnivox-preview-test--start nil))))
   (should-not writes)
   (should (= stops 1))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-public-stop-in-own-stop-hook-cancels ()
  (emacsvox-test--with-complete-preview
   (let (observed)
     (let ((hook (lambda (_owner) (unless observed (setq observed t) (tts-stop)))))
       (add-hook 'tts-stopped-hook hook)
       (omnivox-preview-test--start nil 1 (lambda (value) (push value results)))
       (remove-hook 'tts-stopped-hook hook)))
   (should-not writes)
   (should (= stops 2))
   (should (= (length results) 1))
   (should (eq (plist-get (car results) :status) 'cancelled))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-either-mode-can-supersede-startup ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (let (replacement)
       (let ((hook (lambda (_owner)
                     (unless replacement
                       (setq replacement t)
                       (omnivox-preview-test--start (not individual))))))
         (add-hook 'tts-stopped-hook hook)
         (omnivox-preview-test--start individual 1 (lambda (value) (push value results)))
         (remove-hook 'tts-stopped-hook hook)))
     (should (= (length writes) 1))
     (should (= (length results) 1))
     (should (eq (plist-get (car results) :status) 'cancelled))
     (omnivox-preview-test--reply speaker 41 (not individual))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-early-response-advances-after-write-only ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (let ((depth 0) (maximum 0))
       (setq preview-write-hook
             (lambda (_owner command)
               (unless (equal command "s\n")
                 (cl-incf depth) (setq maximum (max maximum depth))
                 (unwind-protect
                     (let* ((request (emacsvox-test--omnivox-decode-command command))
                            (id (plist-get request :request_id)))
                       (omnivox-preview-test--reply speaker id individual))
                   (cl-decf depth)))))
       (omnivox-preview-test--start individual 64 (lambda (value) (push value results)))
       (should (= maximum 1))
       (should (= (length writes) 64))
       (should (= (length (plist-get (car results) :results)) 64))
       (should (eq (plist-get (car results) :status) 'completed))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest omnivox-preview-early-response-then-failure-never-starts-next ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (setq preview-write-hook
           (lambda (_owner command)
             (unless (equal command "s\n")
               (omnivox-preview-test--reply speaker 41 individual)
               (error "write failed after response"))))
     (if individual
         (should-error (omnivox-preview-test--start t 2 (lambda (value) (push value results))))
       (omnivox-preview-test--start nil 2 (lambda (value) (push value results))))
     (should (= omnivox--control-request-sequence 41))
     (should (eq (plist-get (car results) :status) 'failed))
     (should-not (plist-get (car results) :results))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-nonlocal-exits-release-every-reservation ()
  (dolist (individual '(nil t))
    (dolist (stage '(stop send))
      (dolist (exit-kind '(quit throw))
        (emacsvox-test--with-complete-preview
         (setq preview-write-hook
               (lambda (_owner command)
                 (when (eq (equal command "s\n") (eq stage 'stop))
                   (if (eq exit-kind 'quit) (signal 'quit nil) (throw 'preview-exit 'escaped)))))
         (catch 'preview-exit
           (condition-case nil (omnivox-preview-test--start individual 2) (quit nil)))
         (omnivox-preview-test--clean speaker))))))

(ert-deftest omnivox-preview-public-stop-nonlocal-exits-retire-waiting-sample ()
  (dolist (exit-kind '(error quit throw))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--start t)
     (setq preview-write-hook
           (lambda (_owner command)
             (when (equal command "s\n")
               (pcase exit-kind
                 ('error (error "Stop write failed"))
                 ('quit (signal 'quit nil))
                 ('throw (throw 'preview-exit 'escaped))))))
     (catch 'preview-exit (condition-case nil (tts-stop) ((error quit) nil)))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-stop-callback-runs-after-interrupt-in-independent-capture ()
  (emacsvox-test--with-complete-preview
   (let (observed)
     (omnivox-preview-test--start
      t 1 (lambda (_result)
            (should-not emacsvox-aural--delivery-transaction-active-p)
            (setq observed stops)
            (omnivox-preview-test--start nil)))
     (let ((emacsvox-aural--delivery-transaction-active-p t)) (tts-stop))
     (should (= observed 2))
     (should (= stops 3))
     (omnivox-preview-test--reply speaker 42 nil)
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-timeout-before-reentrant-exact-replacement ()
  (emacsvox-test--with-complete-preview
   (let (timeout before)
     (cl-letf (((symbol-function 'run-at-time)
                (lambda (_time _repeat callback) (setq timeout callback) nil)))
       (omnivox-preview-test--start nil 1
                                    (lambda (_result) (setq before stops) (omnivox-preview-test--start t)))
       (funcall timeout)
       (should (= before 2))
       (should (= stops 3))
       (should (gethash 42 (omnivox--pending-requests speaker)))
       (omnivox-preview-test--reply speaker 42 t)
       (omnivox-preview-test--clean speaker)))))

(ert-deftest omnivox-preview-overlapping-heartbeat-prevents-advancement ()
  (emacsvox-test--with-complete-preview
   (setq preview-write-hook
         (lambda (_owner command)
           (unless (equal command "s\n")
             (let (preview-write-hook) (tts-queue--send-typed speaker "OMNIVOX-REMOTE ping\n" 'neutral))
             (omnivox-preview-test--reply speaker 41 nil))))
   (omnivox-preview-test--start nil 2 (lambda (value) (push value results)))
   (should (= omnivox--control-request-sequence 41))
   (should (eq (plist-get (car results) :status) 'failed))
   (should-not (plist-get (car results) :results))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-input-strings-are-frozen ()
  (emacsvox-test--with-complete-preview
   (let ((entry (copy-tree (emacsvox-test--complete-preview-entry))))
     (setf (plist-get entry :text) (copy-sequence (plist-get entry :text)))
     (let ((selector (car (plist-get entry :selectors))))
       (setf (plist-get selector :voice-id) (copy-sequence (plist-get selector :voice-id))))
     (tts-preview-voices (list entry entry) #'ignore)
     (aset (plist-get entry :text) 0 ?X)
     (aset (plist-get (car (plist-get entry :selectors)) :voice-id) 0 ?X)
     (omnivox-preview-test--reply speaker 41 nil)
     (let ((request (emacsvox-test--omnivox-decode-command (car writes))))
       (should (string-prefix-p "The quick" (plist-get request :text)))
       (should (equal "Paul" (plist-get (car (plist-get request :preferences)) :voice_id)))))))

(ert-deftest omnivox-preview-invalid-later-exact-entry-does-not-interrupt ()
  (emacsvox-test--with-complete-preview
   (should-error (omnivox-preview-voice-sequence
                  (list (emacsvox-test--individual-preview-entry)
                        '(:text "bad" :selector (:kind exact :engine-id "test"))) #'ignore))
   (should-not writes)
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-rejects-cycle-and-capacity-before-stop ()
  (emacsvox-test--with-complete-preview
   (let ((cyclic (list (emacsvox-test--individual-preview-entry))))
     (setcdr cyclic cyclic)
     (should-error (omnivox--preview-individual-sequence cyclic #'ignore)))
   (should-error (omnivox-preview-test--start t 65))
   (let ((omnivox--control-request-sequence omnivox--choice-u64-max))
     (should-error (omnivox-preview-test--start nil)))
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(defun omnivox-preview-test--bundle (speaker)
  "Advertise the full bundle on private SPEAKER without registering voices."
  (process-put speaker omnivox--control-capabilities-property
               '(:features ("voice_choice_tuning_v1" "presentation_timeline_v4" "playback_marker_events_v3"
                            "exact_voice_preview" "voice_chain_preview_v1"))))

(defun omnivox-preview-test--layered (&optional choice)
  "Return independently specified raw sample data, optionally selecting CHOICE."
  (omnivox--preview-copy
   (list :text "6 The quick brown fox." :role 'sample :variant 'edited
         :voice '(:language "en-AU" :shared (:average-pitch 9 :richness 9 :rate-offset 2)
                  :choices ((:id "primary" :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
                             :adjustments (:average-pitch nil :rate-offset 0))
                            (:id "alternate" :selector (:kind exact :scope local :engine-id "eloquence" :voice-id "Reed")
                             :adjustments (:richness 0 :echo nil))
                            (:id "soft" :selector (:kind exact :scope local :engine-id "eloquence" :voice-id "Reed")
                             :adjustments (:richness nil))))
         :context '(:richness 9 :average-pitch nil :rate-offset nil :echo 0)
         :placement '(:pan nil) :selection (if choice (list :mode 'choice :choice-id choice) '(:mode automatic))
         :fallback-policy '(:preferred-engines ("eloquence") :allow-same-language-on-requested-engine nil
                            :global-default nil :fallback-engines ("espeak"))
         :disabled-engine-ids '("winrt"))))

(defun omnivox-preview-test--identity (&optional id index)
  "Return actual second-choice identity, optionally changed to ID and INDEX."
  (omnivox--preview-copy
   (list :choice_id (or id "alternate")
         :reason (list :reason "explicit_alternative" :preference_index (or index 1))
         :realized '(:engine_id "eloquence" :voice_id "Reed") :degraded_acss [] :degraded_effects ["chorus"])))

(defun omnivox-preview-test--terminal (&optional id)
  "Return a strict server terminal for ID with independent accepted/start facts."
  (list :protocol_version 1 :request_id (or id 41) :type "preview_voice_completed_v2"
        :status "completed" :accepted_audio (vector (append (omnivox-preview-test--identity) '(:playback_started t)))
        :accepted_audio_truncated :false :last_started (omnivox-preview-test--identity)
        :message :null :base_rate 0.65 :effective_disabled_engine_ids ["winrt"]))

(defun omnivox-preview-test--control-line (speaker response)
  "Deliver RESPONSE through the real bounded control decoder on SPEAKER."
  (omnivox--handle-control-line
   speaker (concat omnivox-control-event-prefix (omnivox--encode-control-request response))))

(ert-deftest omnivox-preview-v2-projects-full-rows-and-sparse-context ()
  (emacsvox-test--with-complete-preview
   (omnivox-preview-test--bundle speaker)
   (let* ((entry (omnivox-preview-test--layered "soft"))
          (request (omnivox--preview-layered-request entry speaker))
          (voice (plist-get request :voice)) (rows (plist-get voice :choices)))
     (should (equal (plist-get request :type) "preview_voice_v2"))
     (should (equal (plist-get request :selection) '(:mode "choice" :choice_id "soft")))
     (should (equal (mapcar (lambda (row) (plist-get row :id)) rows) '("primary" "alternate" "soft")))
     (should (equal (plist-get (aref rows 1) :selector) (plist-get (aref rows 2) :selector)))
     (should (equal (plist-get (aref rows 0) :adjustments)
                    '(:average_pitch (:op "default") :rate_offset (:op "set" :value 0))))
     (should (equal (plist-get (aref rows 1) :adjustments)
                    '(:richness (:op "set" :value 0.0) :echo (:op "default"))))
     (should (equal (plist-get request :context)
                    '(:richness (:op "set" :value 1.0) :rate_offset (:op "default") :echo (:op "set" :value 0.0))))
     (should (equal (plist-get request :placement) '(:pan :null)))
     (should (= (plist-get (plist-get (plist-get voice :shared) :acss) :richness) 1.0))
     (should (equal entry (omnivox-preview-test--layered "soft"))))))

(ert-deftest omnivox-preview-v2-preflights-both-halves-and-complete-bundle ()
  (emacsvox-test--with-complete-preview
   (dolist (missing '("voice_choice_tuning_v1" "presentation_timeline_v4" "playback_marker_events_v3"))
     (omnivox-preview-test--bundle speaker)
     (process-put speaker omnivox--control-capabilities-property
                  (list :features (remove missing (plist-get (process-get speaker omnivox--control-capabilities-property) :features))))
     (should-error (omnivox--preview-layered-sequence (list (omnivox-preview-test--layered)) #'ignore)))
   (omnivox-preview-test--bundle speaker)
   (dolist (invalid (list (plist-put (omnivox-preview-test--layered) :text "")
                          (plist-put (omnivox-preview-test--layered) :text (make-string 16385 ?a))
                          (plist-put (omnivox-preview-test--layered) :selection '(:mode choice :choice-id "deleted"))
                          (plist-put (omnivox-preview-test--layered) :context '(:echo 10))
                          (plist-put (omnivox-preview-test--layered) :placement '(:pan 1.1))
                          (plist-put (omnivox-preview-test--layered) :expected-base-rate 1.0e+INF)
                          (append (omnivox-preview-test--layered) '(:context nil))))
     (should-error (omnivox--preview-layered-sequence (list (omnivox-preview-test--layered) invalid) #'ignore)))
   (let ((cycle (list :voice nil)))
     (setcdr (cdr cycle) cycle)
     (should-error (omnivox--preview-layered-sequence (list cycle) #'ignore)))
   (let* ((entry (omnivox-preview-test--layered))
          (row (car (plist-get (plist-get entry :voice) :choices))))
     (plist-put row :selector (append (plist-get row :selector) '(:engine-id "other")))
     (should-error (omnivox--preview-layered-sequence (list entry) #'ignore)))
   (should (= stops 0)) (should-not writes)
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-v2-freezes-comparison-and-keeps-private-evidence ()
  (emacsvox-test--with-complete-preview
   (omnivox-preview-test--bundle speaker)
   (let* ((entry (omnivox-preview-test--layered))
          (second (omnivox-preview-test--layered))
          (omnivox-last-realized-routes (make-hash-table :test #'equal)))
     (puthash "bolden" 'ordinary-evidence omnivox-last-realized-routes)
     (omnivox--preview-layered-sequence (list entry second) (lambda (result) (push result results)))
     (aset (plist-get second :text) 0 ?9)
     (setf (plist-get (plist-get second :voice) :choices) nil)
     (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal))
     (let ((request (emacsvox-test--omnivox-decode-command (car writes))))
       (should (= (plist-get request :expected_base_rate) 0.65))
       (should (equal (plist-get request :text) "6 The quick brown fox."))
       (should (= (length (plist-get (plist-get request :voice) :choices)) 3)))
     (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal 42))
     (should (= (length results) 1))
     (should (= (length (plist-get (car results) :results)) 2))
     (dolist (result (plist-get (car results) :results))
       (should (plist-get result :terminal-confirmed))
       (should (equal (plist-get result :last-started) (omnivox-preview-test--identity)))
       (should (eq (plist-get (plist-get result :request-snapshot) :role) 'sample)))
     (should (eq (gethash "bolden" omnivox-last-realized-routes) 'ordinary-evidence))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-v2-validates-started-evidence-independently-of-accept-order ()
  (let* ((entry (omnivox-preview-test--layered))
         (response (omnivox-preview-test--terminal))
         (other (omnivox-preview-test--identity "soft" 2)))
    (plist-put response :accepted_audio
               (vector (append (omnivox-preview-test--identity) '(:playback_started t))
                       (append other '(:playback_started t))))
    ;; The first accepted row may be the most recently started row.
    (should (equal (plist-get (omnivox--normalize-layered-preview-response entry response) :last-started)
                   (omnivox-preview-test--identity)))
    (plist-put response :accepted_audio (vector (append other '(:playback_started t))))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :accepted_audio_truncated t)
    (should (plist-get (omnivox--normalize-layered-preview-response entry response) :last-started))
    (plist-put response :last_started :null)
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :accepted_audio (vector (append other '(:playback_started :false))))
    (dolist (status '("completed" "cancelled" "failed"))
      (plist-put response :status status)
      (should-not (plist-get (omnivox--normalize-layered-preview-response entry response) :last-started)))
    (plist-put response :last_started other)
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :last_started :null)
    (plist-put response :accepted_audio [])
    (plist-put response :accepted_audio_truncated :false)
    (should (plist-get (omnivox--normalize-layered-preview-response entry response) :terminal-confirmed))))

(ert-deftest omnivox-preview-v2-checks-original-row-and-exact-physical-identity ()
  (dolist (status '("completed" "cancelled" "failed"))
    (dolist (change '((:choice_id "missing") (:reason (:reason "preferred"))
                      (:reason (:reason "explicit_alternative" :preference_index 2))
                      (:realized (:engine_id "espeak" :voice_id "Reed"))
                      (:realized (:engine_id "eloquence" :voice_id "Paul"))))
      (let ((response (omnivox-preview-test--terminal)))
        (plist-put response :status status)
        (plist-put response :last_started (plist-put (omnivox-preview-test--identity) (car change) (cadr change)))
        (should-error (omnivox--normalize-layered-preview-response (omnivox-preview-test--layered) response)))))
  (should-error (omnivox--normalize-layered-preview-response
                 (omnivox-preview-test--layered "soft") (omnivox-preview-test--terminal)))
  (let* ((entry (omnivox-preview-test--layered "alternate"))
         (voice (plist-get entry :voice)) (rows (plist-get voice :choices)))
    (plist-put voice :choices (list (car rows) (nth 2 rows) (nth 1 rows)))
    (should-error (omnivox--normalize-layered-preview-response entry (omnivox-preview-test--terminal)))
    (let ((response (omnivox-preview-test--terminal)) (identity (omnivox-preview-test--identity "alternate" 2)))
      (plist-put response :last_started identity)
      (plist-put response :accepted_audio (vector (append identity '(:playback_started t))))
      (should (plist-get (omnivox--normalize-layered-preview-response entry response) :terminal-confirmed)))))

(ert-deftest omnivox-preview-v2-policy-substitutes-retain-null-choice-id ()
  (let* ((entry (omnivox-preview-test--layered)) (response (omnivox-preview-test--terminal))
         (identity (omnivox-preview-test--identity)))
    (plist-put identity :choice_id :null)
    (plist-put identity :reason '(:reason "preferred_engine" :preferred_index 0))
    (plist-put response :last_started identity)
    (plist-put response :accepted_audio (vector (append identity '(:playback_started t))))
    (should (eq (plist-get (plist-get (omnivox--normalize-layered-preview-response entry response) :last-started)
                           :choice_id) :null))
    (should-error (omnivox--normalize-layered-preview-response (omnivox-preview-test--layered "alternate") response))
    (plist-put identity :reason '(:reason "preferred_engine" :preferred_index 1))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put identity :reason '(:reason "global_default"))
    (should-error (omnivox--normalize-layered-preview-response entry response))))

(ert-deftest omnivox-preview-v2-rejects-malformed-terminal-types-and-duplicates ()
  (dolist (change '((:accepted_audio nil) (:accepted_audio :null) (:accepted_audio :false)
                    (:accepted_audio_truncated nil) (:last_started nil) (:last_started [])
                    (:message :false) (:status "partial") (:base_rate 1.0e+INF) (:base_rate -0.1)
                    (:effective_disabled_engine_ids ["winrt" "winrt"]) (:effective_disabled_engine_ids [])
                    (:effective_disabled_engine_ids ["winrt" "eloquence"])))
    (let ((response (omnivox-preview-test--terminal)))
      (plist-put response (car change) (cadr change))
      (should-error (omnivox--normalize-layered-preview-response (omnivox-preview-test--layered) response))))
  (let* ((entry (omnivox-preview-test--layered)) (response (omnivox-preview-test--terminal))
         (accepted (aref (plist-get response :accepted_audio) 0)))
    (should-error (omnivox--normalize-layered-preview-response entry (append response '(:status "completed"))))
    (should-error (omnivox--normalize-layered-preview-response entry (append response '(:unknown 1))))
    (plist-put response :accepted_audio (vector accepted (copy-sequence accepted)))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :accepted_audio (make-vector 33 accepted))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :accepted_audio (vector (plist-put (copy-sequence accepted) :playback_started :null)))
    (should-error (omnivox--normalize-layered-preview-response entry response))
    (plist-put response :message (make-string 513 #x00e9))
    (should-error (omnivox--normalize-layered-preview-response entry response))))

(ert-deftest omnivox-preview-v2-decoder-retains-null-false-and-array ()
  (let* ((payload (base64-encode-string "{\"null\":null,\"flag\":false,\"array\":[],\"object\":{}}" t))
         (strict (omnivox--decode-control-response payload t)))
    (should (equal strict '(:null :null :flag :false :array [] :object nil)))
    (should (equal (omnivox--decode-control-response payload) '(:null nil :flag nil :array nil :object nil)))
    (should-error (omnivox--decode-control-response (concat payload "\n") t)))
  (should-error (omnivox--decode-control-response (base64-encode-string (unibyte-string ?\" 255 ?\") t) t)))

(ert-deftest omnivox-preview-v2-accepts-the-paired-server-terminal-fixture ()
  (let* ((fixture (with-temp-buffer
                    (insert-file-contents omnivox-preview-test--wire-fixture)
                    (json-parse-buffer :object-type 'plist :array-type 'array :null-object :null :false-object :false)))
         (terminal (plist-get (plist-get fixture :messages) :preview_completed))
         (entry (omnivox-preview-test--layered))
         (rows (plist-get (plist-get entry :voice) :choices)))
    (cl-mapc (lambda (row id) (plist-put row :id id)) rows
             '("dectalk-paul" "eloquence-reed" "eloquence-reed-soft"))
    (plist-put entry :disabled-engine-ids nil)
    (let* ((decoded (omnivox--decode-control-response (omnivox--encode-control-request terminal) t))
           (result (omnivox--normalize-layered-preview-response entry decoded)))
      (should (eq (plist-get result :status) 'completed))
      (should (plist-get result :terminal-confirmed))
      (should (equal (plist-get (plist-get result :last-started) :choice_id) "eloquence-reed")))))

(ert-deftest omnivox-preview-v2-correlatable-invalid-response-fails-only-its-entry ()
  (emacsvox-test--with-complete-preview
   (omnivox-preview-test--bundle speaker)
   (omnivox--preview-layered-sequence (list (omnivox-preview-test--layered) (omnivox-preview-test--layered))
                                    (lambda (value) (push value results)))
   (let ((response (plist-put (omnivox-preview-test--terminal) :accepted_audio :null)))
     (omnivox-preview-test--control-line speaker response))
   (should (= (length writes) 1))
   (should (eq (plist-get (car results) :status) 'failed))
   (should-not (plist-get (car (plist-get (car results) :results)) :terminal-confirmed))
   (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal))
   (should (= (length results) 1))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-v2-ambiguous-envelope-keeps-deadline-and-reservations ()
  (emacsvox-test--with-complete-preview
   (omnivox-preview-test--bundle speaker)
   (omnivox--preview-layered-sequence (list (omnivox-preview-test--layered)) (lambda (value) (push value results)))
   (let* ((pending (omnivox--pending-requests speaker))
          (callback (gethash 41 pending)) (operation (process-get speaker 'omnivox--preview-operation)))
     (puthash 42 #'ignore pending)
     ;; json-serialize deduplicates plist keys; malformed wire must be literal.
     (omnivox--handle-control-line
      speaker (concat omnivox-control-event-prefix
                      (base64-encode-string
                       (concat (substring (json-serialize (omnivox-preview-test--terminal)) 0 -1)
                               ",\"request_id\":42}") t)))
     (should (eq callback (gethash 41 pending)))
     (should (gethash 42 pending))
     (should (omnivox--preview-timer operation))
     (should-not results)
     (remhash 42 pending)
     (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal))
     (should (eq (plist-get (car results) :status) 'completed)))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-v2-control-error-and-policy-change-stop-comparison ()
  (dolist (kind '(admission rate disablement))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (omnivox--preview-layered-sequence (make-list 3 (omnivox-preview-test--layered)) (lambda (value) (push value results)))
     (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal))
     (let ((response (pcase kind
                       ('admission '(:protocol_version 1 :request_id 42 :type "error" :code "invalid_request" :message "Rate changed"))
                       ('rate (plist-put (omnivox-preview-test--terminal 42) :base_rate 0.7))
                       ('disablement (plist-put (omnivox-preview-test--terminal 42) :effective_disabled_engine_ids ["winrt" "other"])))))
       (omnivox-preview-test--control-line speaker response))
     (should (= (length writes) 2))
     (should (eq (plist-get (car results) :status) 'failed))
     (should (plist-get (car (plist-get (car results) :results)) :terminal-confirmed))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-v2-supersedes-legacy-and-local-stop-cannot-invent-evidence ()
  (emacsvox-test--with-complete-preview
   (omnivox-preview-test--bundle speaker)
   (omnivox-preview-test--start t 1 (lambda (value) (push value results)))
   (omnivox--preview-layered-sequence (list (omnivox-preview-test--layered)) (lambda (value) (push value results)))
   (should (eq (plist-get (car results) :status) 'cancelled))
   (should (= (length writes) 2))
   (tts-stop)
   (should (= (length results) 2))
   (should (eq (plist-get (car results) :status) 'cancelled))
   (should-not (plist-get (car results) :results))
   (omnivox-preview-test--control-line speaker (omnivox-preview-test--terminal 42))
   (omnivox-preview-test--reply speaker 41 t)
   (should (= (length results) 2))
   (omnivox-preview-test--clean speaker)))

(provide 'omnivox-preview-tests)
;;; omnivox-preview-tests.el ends here
