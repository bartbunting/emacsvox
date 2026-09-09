;;; omnivox-choice-playback-tests.el --- Actual fallback evidence -*- lexical-binding: t; -*-
;;; Commentary:
;; Real registration, delivery, filters and owner cleanup with muted pipe writes.
;;; Code:
(require 'ert)
(require 'omnivox-choice-timeline-tests)
(require 'omnivox-choice-codec-tests)

(defmacro omnivox-choice-playback-test--with-runtime (&rest body)
  "Run BODY with isolated registrations and real dispatch ownership."
  (declare (indent 0) (debug t))
  `(omnivox-test--with-choice-registration
    (let ((tts--tracked-dispatch-sequence 0)
          (tts--tracked-dispatches (make-hash-table :test #'eql))
          (tts--marker-dispatches (make-hash-table :test #'eql))
          (tts--dispatch-lifecycles (make-hash-table :test #'eql))
          (omnivox-last-realized-routes (make-hash-table :test #'equal))
          (omnivox-realized-route-changed-hook nil)
          (tts-realized-voice-changed-hook nil)
          (omnivox-timeline-event-hook nil)
          (omnivox-marker-last-error nil)
          (tts-stopped-hook nil)
          (emacsvox-speak-messages nil)
          (emacsvox-aural-submission-controls-interruption nil)
          (emacsvox-aural-submission-delivery-policy 'ordered))
      (unwind-protect
          (progn
            (dolist (lane (list speaker notification))
              (process-put lane 'tts--speech-process-generation (if (eq lane speaker) 9 10))
              (process-put lane tts--tracked-playback-completion-property t)
              (process-put lane tts--marker-playback-events-property t))
            (omnivox-register-logical-voices)
            (dolist (write requests)
              (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))
            ,@body)
        (dolist (lane (list speaker notification))
          (tts--cancel-process-tracked-dispatches lane 'cancelled)
          (when-let* ((timer (process-get lane 'tts--dispatch-notification-timer)))
            (cancel-timer timer)))))))

(defun omnivox-choice-playback-test--submit (&optional marker completion effect)
  "Submit one layered span with optional MARKER, COMPLETION and EFFECT."
  (let* ((tts--marker-event-function marker)
         (tts--tracked-completion-function completion)
         (run (omnivox-choice-timeline-test--run '(:preset bolden :echo nil) nil)))
    (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () "")))
      (emacsvox-aural-call-with-delivery-transaction
       tts-speaker-process
       (lambda ()
         (when effect (emacsvox-aural--defer-delivery-effect effect))
         (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
         (tts--protocol-dispatch))))))

(defun omnivox-choice-playback-test--start (id &optional sequence utterance engine voice)
  "Return an independently specified consumed start event."
  (let ((engine (or engine "eloquence")) (voice (or voice "Reed")))
    (list :protocol_version 3 :dispatch_id id :sequence (or sequence 1) :type "utterance_started"
          :utterance_id (or utterance 1) :text "The quick brown fox." :engine_id engine
          :actual_voice (list :engine_id engine :voice_id voice) :logical_voice_id "bolden"
          :sample_rate 22050 :frame_count 100)))

(defun omnivox-choice-playback-test--receipt (id generation &optional sequence utterance)
  "Return the actual second fallback receipt for ID and GENERATION."
  (list :protocol_version 3 :dispatch_id id :sequence (or sequence 2) :type "voice_choice_applied"
        :utterance_id (or utterance 1) :span_id 1 :registry_generation generation :logical_voice_id "bolden"
        :choice (list :choice_id "eloquence-male" :reason '(:reason "explicit_alternative" :preference_index 1)
                      :realized '(:engine_id "eloquence" :voice_id "Reed")
                      :degraded_acss [] :degraded_effects ["chorus"])))

(defun omnivox-choice-playback-test--line (event)
  "Encode EVENT using the real marker line framing."
  (concat omnivox-marker-event-prefix
          (base64-encode-string (encode-coding-string (json-serialize event) 'utf-8 t) t) "\n"))

(defun omnivox-choice-playback-test--event (process event)
  "Feed EVENT through PROCESS's actual control and marker filters."
  (omnivox--control-process-filter process (omnivox-choice-playback-test--line event)))

(ert-deftest omnivox-choice-playback-early-split-pair-and-terminal-publish-after-return ()
  (omnivox-choice-playback-test--with-runtime
   (let (returned callbacks hooks)
     (let ((omnivox-realized-route-changed-hook (list (lambda (route) (push route hooks)))))
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (process command)
                    (should (string-prefix-p "emacsvox_timeline " command))
                    (omnivox-choice-playback-test--event process (omnivox-choice-playback-test--start 1))
                    (let* ((line (omnivox-choice-playback-test--line (omnivox-choice-playback-test--receipt 1 1)))
                           (split (/ (length line) 2)))
                      (omnivox--control-process-filter process (substring line 0 split))
                      (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'unverified))
                      (omnivox--control-process-filter process (substring line split)))
                    (tts--speaker-process-filter process "__EMACSVOX_TRACKED__ 1 completed\n")
                    (tts--dispatch-drain process)
                    (should-not callbacks)
                    (should-not hooks))))
         (setq returned (omnivox-choice-playback-test--submit
                         (lambda (id event) (should (= returned id)) (push (plist-get event :type) callbacks))
                         (lambda (id status) (should (= returned id)) (push status callbacks)))))
       (should (= returned 1))
       (should-not omnivox-marker-last-error)
       (let ((route (omnivox-last-realized-voice 'voice-bolden)))
         (should (equal (plist-get route :choice-id) "eloquence-male"))
         (should (eq (plist-get route :choice-status) 'verified))
         (should (eq (plist-get route :palette) 'reading))
         (should (equal (plist-get route :choice-adjustments) '(:richness 3 :rate-offset 0 :low-pass nil)))
         (should (equal (plist-get route :context) '(:echo nil)))
         (should-not (plist-member route :process)))
       (tts--dispatch-drain speaker)
       (should (equal (reverse callbacks) '("utterance_started" "voice_choice_applied" completed)))
       (should (= (length hooks) 2))
       (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes)))
       (should (= 0 (hash-table-count (process-get speaker 'omnivox--choice-snapshot-references))))))))

(ert-deftest omnivox-choice-playback-shares-one-registry-charge-and-releases-at-last-owner ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore))
     (omnivox-choice-playback-test--submit)
     (let ((first (process-get speaker 'tts--dispatch-metadata-bytes)))
       (omnivox-choice-playback-test--submit)
       (let* ((second (process-get speaker 'tts--dispatch-metadata-bytes))
              (snapshot (process-get speaker omnivox--choice-registration-property))
              (references (process-get speaker 'omnivox--choice-snapshot-references)))
         (should (< (- second first) first))
         (should (= 2 (car (gethash snapshot references))))))
   (tts-cancel-tracked-dispatch 1)
   (should (> (process-get speaker 'tts--dispatch-metadata-bytes) 0))
   (tts-cancel-tracked-dispatch 2)
   (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes))))))

(ert-deftest omnivox-choice-playback-old-registration-stays-valid-after-new-acknowledgement ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore))
     (omnivox-choice-playback-test--submit))
   (setf (plist-get (car (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)) :adjustments) '(:richness 9))
   (setq requests nil)
   (omnivox-register-logical-voices)
   (dolist (write requests)
     (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))
   (should (= (plist-get (process-get speaker omnivox--choice-registration-property) :registry-generation) 2))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1 1 1 "dectalk" "Paul"))
   (let ((receipt (omnivox-choice-playback-test--receipt 1 1)))
     (setf (plist-get (plist-get receipt :choice) :choice_id) "dectalk-paul"
           (plist-get (plist-get receipt :choice) :reason) '(:reason "preferred")
           (plist-get (plist-get receipt :choice) :realized) '(:engine_id "dectalk" :voice_id "Paul"))
     (omnivox-choice-playback-test--event speaker receipt))
   (should-not omnivox-marker-last-error)
   (should (equal (plist-get (omnivox-last-realized-voice 'bolden) :choice-adjustments)
                  '(:average-pitch nil :richness 7 :rate-offset 4)))))

(ert-deftest omnivox-choice-playback-rejects-wrong-receipt-without-changing-sequence-or-route ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore)) (omnivox-choice-playback-test--submit))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1))
   (let ((before (omnivox-last-realized-voice 'bolden)))
     (cl-letf (((symbol-function 'message) #'ignore))
       (dolist (change '((:span_id . 2) (:registry_generation . 2) (:utterance_id . 2)
                         (:logical_voice_id . "unrelated") (:sequence . 3)))
         (let ((event (omnivox-choice-playback-test--receipt 1 1)))
           (setf (plist-get event (car change)) (cdr change))
           (omnivox-choice-playback-test--event speaker event)))
       (let ((event (omnivox-choice-playback-test--receipt 1 1)))
         (setf (plist-get (plist-get event :choice) :choice_id) "dectalk-paul")
         (omnivox-choice-playback-test--event speaker event)))
     (should (equal before (omnivox-last-realized-voice 'bolden)))
     (should (= 1 (tts--marker-dispatch-last-sequence (gethash 1 tts--marker-dispatches)))))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--receipt 1 1))
   (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))))

(ert-deftest omnivox-choice-playback-policy-fallback-never-borrows-matching-row-patch ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore)) (omnivox-choice-playback-test--submit))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1))
   (let ((receipt (omnivox-choice-playback-test--receipt 1 1)))
     (setf (plist-get (plist-get receipt :choice) :choice_id) :null
           (plist-get (plist-get receipt :choice) :reason) '(:reason "global_default"))
     (omnivox-choice-playback-test--event speaker receipt))
   (let ((route (omnivox-last-realized-voice 'bolden)))
     (should (eq (plist-get route :choice-status) 'verified))
     (should (eq (plist-get route :choice-id) :null))
     (should-not (plist-get route :choice-adjustments)))))

(ert-deftest omnivox-choice-playback-cancellation-retains-evidence-but-rejects-late-receipts ()
  (omnivox-choice-playback-test--with-runtime
   (let (callbacks)
     (cl-letf (((symbol-function 'process-send-string) #'ignore))
       (omnivox-choice-playback-test--submit nil (lambda (_id status) (push status callbacks))))
     (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1))
     (let ((before (omnivox-last-realized-voice 'bolden)))
       (tts--cancel-process-tracked-dispatches speaker 'cancelled)
       (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--receipt 1 1))
       (should (equal before (omnivox-last-realized-voice 'bolden))))
     (should (equal callbacks '(cancelled)))
     (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes))))))

(ert-deftest omnivox-choice-playback-consumed-receipt-survives-write-failure-without-replay ()
  (omnivox-choice-playback-test--with-runtime
   (let ((writes 0) callbacks)
     (cl-letf (((symbol-function 'message) #'ignore)
               ((symbol-function 'process-send-string)
                (lambda (process _command)
                  (cl-incf writes)
                  (omnivox-choice-playback-test--event process (omnivox-choice-playback-test--start 1))
                  (omnivox-choice-playback-test--event process (omnivox-choice-playback-test--receipt 1 1))
                  (error "write failed after simulated consumption"))))
       (should-not (omnivox-choice-playback-test--submit nil (lambda (&rest _) (push t callbacks)))))
     (should (= writes 1))
     (should-not callbacks)
     (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))
     (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes))))))

(ert-deftest omnivox-choice-playback-metadata-exhaustion-precedes-navigation-stop ()
  (omnivox-choice-playback-test--with-runtime
   (let ((tts--dispatch-metadata-limit 1000)
         (emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-delivery-policy 'urgent)
         writes)
     (cl-letf (((symbol-function 'process-send-string) (lambda (&rest args) (push args writes))))
       (should-error (omnivox-choice-playback-test--submit)))
     (should-not writes)
     (should (= 0 (process-get speaker 'tts--dispatch-owner-count)))
     (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes))))))

(ert-deftest omnivox-choice-playback-new-ack-during-framing-rejects-before-write ()
  (omnivox-choice-playback-test--with-runtime
   (let ((frame (symbol-function 'emacsvox-aural--frame-structured-timeline)) writes)
     (cl-letf (((symbol-function 'emacsvox-aural--frame-structured-timeline)
                (lambda (envelope)
                  (prog1 (funcall frame envelope)
                    (process-put speaker omnivox--choice-registration-property
                                 (tts--dispatch-copy-data (process-get speaker omnivox--choice-registration-property))))))
               ((symbol-function 'message) #'ignore)
               ((symbol-function 'process-send-string) (lambda (&rest args) (push args writes))))
       (should-not (omnivox-choice-playback-test--submit)))
     (should-not writes)
     (should (= 0 (process-get speaker 'tts--dispatch-metadata-bytes))))))

(ert-deftest omnivox-choice-playback-repeated-physical-voice-keeps-original-row-identity ()
  (omnivox-choice-playback-test--with-runtime
   (let* ((set (cadr emacsvox-aural-routing--choice-sets))
          (rows (plist-get set :choices)))
     (setf (plist-get set :choices)
           (append rows (list (list :id "dectalk-soft" :selector (copy-tree (plist-get (car rows) :selector)) :adjustments nil)))))
   (setq requests nil)
   (omnivox-register-logical-voices)
   (dolist (write requests)
     (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))
   (cl-letf (((symbol-function 'process-send-string) #'ignore)) (omnivox-choice-playback-test--submit))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1 1 1 "dectalk" "Paul"))
   (let ((receipt (omnivox-choice-playback-test--receipt 1 2)))
     (setf (plist-get (plist-get receipt :choice) :choice_id) "dectalk-soft"
           (plist-get (plist-get receipt :choice) :reason) '(:reason "explicit_alternative" :preference_index 2)
           (plist-get (plist-get receipt :choice) :realized) '(:engine_id "dectalk" :voice_id "Paul"))
     (omnivox-choice-playback-test--event speaker receipt))
   (should-not omnivox-marker-last-error)
   (let ((route (omnivox-last-realized-voice 'bolden)))
     (should (equal (plist-get route :choice-id) "dectalk-soft"))
     (should-not (plist-get route :choice-adjustments)))))

(ert-deftest omnivox-choice-playback-two-lanes-reject-crossed-receipts-and-stale-degradation ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore))
     (omnivox-choice-playback-test--submit)
     (let ((tts-speaker-process notification)) (omnivox-choice-playback-test--submit)))
   (omnivox-choice-playback-test--event notification (omnivox-choice-playback-test--start 1))
   (should-not (omnivox-last-realized-voice 'bolden))
   (dolist (pair (list (cons speaker 1) (cons notification 2)))
     (omnivox-choice-playback-test--event (car pair) (omnivox-choice-playback-test--start (cdr pair)))
     (omnivox-choice-playback-test--event (car pair) (omnivox-choice-playback-test--receipt (cdr pair) 1)))
   (let ((before (omnivox-last-realized-voice 'bolden)))
     (should (eq (plist-get before :lane) 'notification))
     (omnivox-choice-playback-test--event speaker
      '(:protocol_version 3 :dispatch_id 1 :sequence 3 :utterance_id 1 :type "timeline_style_degraded"
        :degraded_acss ["stress"] :degraded_effects []))
     (should (equal before (omnivox-last-realized-voice 'bolden)))
     (tts--cancel-process-tracked-dispatches speaker 'cancelled)
     (should (tts--dispatch-observing-p (tts--dispatch-owner-for notification 2))))))

(ert-deftest omnivox-choice-playback-observations-truncate-with-separate-latest-started-evidence ()
  (omnivox-choice-playback-test--with-runtime
   (let ((omnivox--choice-observation-limit 2))
     (cl-letf (((symbol-function 'process-send-string) #'ignore)) (omnivox-choice-playback-test--submit))
     (dotimes (index 3)
       (let ((voice (format "Reed-%d" index))
             (receipt (omnivox-choice-playback-test--receipt 1 1 (+ 2 (* 2 index)) (1+ index))))
         (omnivox-choice-playback-test--event speaker
          (omnivox-choice-playback-test--start 1 (1+ (* 2 index)) (1+ index) "eloquence" voice))
         (setf (plist-get (plist-get receipt :choice) :realized) (list :engine_id "eloquence" :voice_id voice))
         (omnivox-choice-playback-test--event speaker receipt)))
     (should-not omnivox-marker-last-error)
     (let ((context (tts--dispatch-owner-context (tts--dispatch-owner-for speaker 1))))
       (should (= (length (plist-get context :observations)) 2))
       (should (plist-get context :truncated))
       (should (= (plist-get (plist-get context :last-started) :utterance_id) 3)))
     (let ((route (omnivox-last-realized-voice 'bolden)))
       (should (equal (plist-get route :voice-id) "Reed-2"))
       (should (plist-get route :observations-truncated))))))

(ert-deftest omnivox-choice-playback-sequence-gap-breaks-pair-and-next-complete-pair-recovers ()
  (omnivox-choice-playback-test--with-runtime
   (cl-letf (((symbol-function 'process-send-string) #'ignore)) (omnivox-choice-playback-test--submit))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1))
   (omnivox-choice-playback-test--event speaker
    '(:protocol_version 3 :dispatch_id 1 :sequence 3 :utterance_id 1 :type "semantic_event_reached" :action_id "semantic.1"))
   (cl-letf (((symbol-function 'message) #'ignore))
     (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--receipt 1 1 4)))
   (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'unverified))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start 1 5 2))
   (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--receipt 1 1 6 2))
   (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified))))

(ert-deftest omnivox-choice-playback-equivalent-ack-refresh-preserves-prepared-snapshot ()
  (omnivox-choice-playback-test--with-runtime
   (let ((frame (symbol-function 'emacsvox-aural--frame-structured-timeline)))
     (cl-letf (((symbol-function 'emacsvox-aural--frame-structured-timeline)
                (lambda (envelope)
                  (prog1 (funcall frame envelope)
                    (let* ((snapshot (process-get speaker omnivox--choice-registration-property))
                           (response (tts--dispatch-copy-data (plist-get snapshot :response))))
                      (setf (plist-get response :inventory_generation) 2)
                      (should (omnivox--accept-registration-response speaker response 1 (plist-get snapshot :content)))
                      (should (eq snapshot (process-get speaker omnivox--choice-registration-property)))))))
               ((symbol-function 'process-send-string) #'ignore))
       (should (= 1 (omnivox-choice-playback-test--submit)))))))

(ert-deftest omnivox-choice-playback-replaced-generation-cannot-accept-old-registration ()
  (omnivox-choice-playback-test--with-runtime
   (let* ((snapshot (process-get speaker omnivox--choice-registration-property))
          (content (plist-get snapshot :content))
          (response (plist-get snapshot :response)))
     (process-put speaker 'tts--speech-process-generation 11)
     (should-not (omnivox--accept-registration-response speaker response 1 content))
     (should-error (omnivox--choice-current-registration speaker))
     (let (writes)
       (cl-letf (((symbol-function 'process-send-string) (lambda (&rest args) (push args writes))))
         (should-error (omnivox-choice-playback-test--submit)))
       (should-not writes)))))

(ert-deftest omnivox-choice-playback-historical-summaries-and-public-values-are-bounded ()
  (omnivox-choice-playback-test--with-runtime
   (let ((omnivox--realized-route-limit 2))
     (dotimes (index 5)
       (omnivox--store-realized-route
        (list :logical-voice (format "voice-%d" index) :engine-id (copy-sequence "engine")
              :voice-id "physical" :time (seconds-to-time index))))
     (should (= 2 (hash-table-count omnivox-last-realized-routes)))
     (let ((public (omnivox-last-realized-voice "voice-4")))
       (aset (plist-get public :engine-id) 0 ?X)
       (should (equal (plist-get (omnivox-last-realized-voice "voice-4") :engine-id) "engine"))))))

(provide 'omnivox-choice-playback-tests)
;;; omnivox-choice-playback-tests.el ends here
