;;; emacsvox-aural-replay-tests.el --- Historical voice replay tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Real registration, dispatch filters and history with isolated speech lanes.
;;; Code:
(require 'omnivox-choice-playback-tests)
(require 'emacsvox-aural-replay)
(require 'omnivox-native-runtime-tests)

(defmacro emacsvox-replay-test--with-runtime (&rest body)
  (declare (indent 0) (debug t))
  `(omnivox-choice-playback-test--with-runtime
    (let ((emacsvox-aural-presentation-history nil)
          (emacsvox-aural--history-recording-inhibited nil)
          (emacsvox-aural-history-record-interface-presentations t)
          (emacsvox-aural-presentation-history-limit 20))
      ,@body)))

(defun emacsvox-replay-test--submit (process &optional runs)
  "Submit RUNS on PROCESS and return its dispatch ID and retained record."
  (let ((tts-speaker-process process) identifier)
    (cl-letf (((symbol-function 'process-send-string) #'ignore)
              ((symbol-function 'tts-voice-reset-code) (lambda () "")))
      (setq identifier
            (if runs
                (emacsvox-aural-call-with-presentation-transaction
                 42 (lambda ()
                      (dolist (run runs)
                        (setf (emacsvox-aural-concrete-plan-context (car run))
                              '(:presentation-transaction-id 42 :icons-enabled nil)))
                      (emacsvox-aural-call-with-delivery-transaction
                       process (lambda () (emacsvox-aural-queue-concrete-runs runs)
                                 (tts--protocol-dispatch)))))
              (omnivox-choice-playback-test--submit))))
    (list identifier (car emacsvox-aural-presentation-history))))

(defun emacsvox-replay-test--observe (process id &optional preferred text span sequence utterance)
  "Feed a valid actual voice receipt through PROCESS's real marker filter."
  (let ((start (omnivox-choice-playback-test--start id sequence utterance
                                                    (if preferred "dectalk" "eloquence")
                                                    (if preferred "Paul" "Reed")))
        (receipt (omnivox-choice-playback-test--receipt id 1 (1+ (or sequence 1)) utterance)))
    (when text (setf (plist-get start :text) text))
    (when span (setf (plist-get receipt :span_id) span))
    (when preferred
      (setf (plist-get (plist-get receipt :choice) :choice_id) "dectalk-paul"
            (plist-get (plist-get receipt :choice) :reason) '(:reason "preferred")
            (plist-get (plist-get receipt :choice) :realized) '(:engine_id "dectalk" :voice_id "Paul")))
    (omnivox-choice-playback-test--event process start)
    (omnivox-choice-playback-test--event process receipt)))

(defun emacsvox-replay-test--complete (process id &optional status)
  (tts--speaker-process-filter process (format "__EMACSVOX_TRACKED__ %d %s\n" id (or status "completed")))
  (tts--dispatch-drain process))

(ert-deftest emacsvox-aural-replay-keeps-notification-voice-after-main-and-palette-change ()
  "Original playback uses that notification's actual fallback and captured tuning."
  (emacsvox-replay-test--with-runtime
   (pcase-let* ((`(,notify-id ,record) (emacsvox-replay-test--submit notification))
                (`(,main-id ,_) (emacsvox-replay-test--submit speaker)))
     (emacsvox-replay-test--observe notification notify-id)
     (emacsvox-replay-test--observe speaker main-id t)
     (emacsvox-replay-test--complete notification notify-id)
     (emacsvox-replay-test--complete speaker main-id)
     ;; The same logical voice's most recent route and saved definition differ.
     (should (equal (plist-get (omnivox-last-realized-voice 'bolden) :engine-id) "dectalk"))
     (setf (plist-get (car (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)) :adjustments)
           '(:richness 9))
     (let* ((entry (cadar (emacsvox-aural-replay--steps record)))
            (request (omnivox--preview-layered-request entry speaker))
            (choices (plist-get (plist-get request :voice) :choices)))
       (should (= (length choices) 1))
       (should (equal (plist-get (car (append choices nil)) :selector)
                      '(:kind "exact" :engine_id "eloquence" :voice_id "Reed")))
       (should (equal (plist-get entry :context) '(:echo nil)))
       (should (equal (plist-get (car (plist-get (plist-get entry :voice) :choices)) :adjustments)
                      '(:richness 3 :rate-offset 0 :low-pass nil)))
       (should (equal (plist-get entry :selection) '(:mode choice :choice-id "eloquence-male")))
       (should (eq (plist-get (car (emacsvox-aural--playback-dispatches
                                    (emacsvox-aural-replay--capture record))) :lane) 'notification))
       (should-not (string-match-p "#<\\(process\\|buffer\\)" (prin1-to-string record)))))))

(ert-deftest emacsvox-aural-replay-rejects-missing-cancelled-and-foreign-evidence ()
  (emacsvox-replay-test--with-runtime
   (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit notification)))
     (should-error (emacsvox-aural-replay--steps record) :type 'user-error)
     (emacsvox-replay-test--observe speaker id)
     (should-error (emacsvox-aural-replay--steps record) :type 'user-error)
     (emacsvox-replay-test--observe notification id)
     (emacsvox-replay-test--complete notification id "cancelled")
     (should-error (emacsvox-aural-replay--steps record) :type 'user-error))))

(ert-deftest emacsvox-aural-replay-slices-coalesced-fields-without-changing-voice ()
  (emacsvox-replay-test--with-runtime
   (let ((runs (list (omnivox-choice-timeline-test--run 'bolden nil nil "One ")
                     (omnivox-choice-timeline-test--run 'bolden nil nil "two."))))
     (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit speaker runs)))
       (emacsvox-replay-test--observe speaker id nil "One two.")
       (emacsvox-replay-test--complete speaker id)
       (should (equal (mapcar (lambda (step) (plist-get (cadr step) :text))
                              (emacsvox-aural-replay--steps record '(1))) '("two.")))
       (should (= (length (emacsvox-aural-replay--steps record)) 2))))))

(ert-deftest emacsvox-aural-replay-aligns-uniform-voice-after-host-punctuation-processing ()
  (emacsvox-replay-test--with-runtime
   (let ((runs (list (omnivox-choice-timeline-test--run 'bolden nil nil "One ")
                     (omnivox-choice-timeline-test--run 'bolden nil nil "two."))))
     (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit speaker runs)))
       (emacsvox-replay-test--observe speaker id nil "One two dot ")
       (emacsvox-replay-test--complete speaker id)
       (should (equal (mapcar (lambda (step) (plist-get (cadr step) :text))
                              (emacsvox-aural-replay--steps record '(1))) '("two.")))))))

(ert-deftest emacsvox-aural-replay-preserves-different-realizations-within-one-span ()
  (emacsvox-replay-test--with-runtime
   (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit speaker)))
     (emacsvox-replay-test--observe speaker id t "The quick " 1 1 1)
     (emacsvox-replay-test--observe speaker id nil "brown fox." 1 3 2)
     (emacsvox-replay-test--complete speaker id)
     (let ((steps (emacsvox-aural-replay--steps record)))
       (should (equal (mapcar (lambda (step) (plist-get (cadr step) :text)) steps)
                      '("The quick " "brown fox.")))
       (should (equal (mapcar (lambda (step)
                                (plist-get (plist-get (car (plist-get (plist-get (cadr step) :voice) :choices)) :selector) :engine-id)) steps)
                      '("dectalk" "eloquence")))))))

(ert-deftest emacsvox-aural-replay-policy-fallback-keeps-shared-settings-without-borrowing-a-row ()
  (emacsvox-replay-test--with-runtime
   (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit speaker)))
     (omnivox-choice-playback-test--event speaker (omnivox-choice-playback-test--start id))
     (let ((receipt (omnivox-choice-playback-test--receipt id 1)))
       (setf (plist-get (plist-get receipt :choice) :choice_id) :null
             (plist-get (plist-get receipt :choice) :reason) '(:reason "global_default"))
       (omnivox-choice-playback-test--event speaker receipt))
     (emacsvox-replay-test--complete speaker id)
     (let* ((entry (cadar (emacsvox-aural-replay--steps record)))
            (request (omnivox--preview-layered-request entry speaker))
            (row (car (plist-get (plist-get entry :voice) :choices))))
       (should (equal (plist-get request :type) "preview_voice_v2"))
       (should (equal (plist-get (plist-get row :selector) :voice-id) "Reed"))
       (should-not (plist-get row :adjustments))
       (should-not (plist-get row :native))
       (should (plist-get (plist-get entry :voice) :shared))))))

(defun emacsvox-replay-test--record ()
  "Return a completed notification captured through the real history path."
  (emacsvox-replay-test--with-runtime
   (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit notification)))
     (emacsvox-replay-test--observe notification id)
     (emacsvox-replay-test--complete notification id)
     record)))

(defun emacsvox-replay-test--reply (process id &optional wrong)
  "Complete an exact historical preview, optionally reporting the WRONG voice."
  (let* ((response (omnivox-preview-test--terminal id))
         (identity (omnivox-preview-test--identity "eloquence-male")))
    (setf (plist-get identity :reason) '(:reason "preferred"))
    (when wrong
      (setf (plist-get identity :realized) '(:engine_id "eloquence" :voice_id "Shelley")))
    (setf (plist-get response :accepted_audio) (vector (append identity '(:playback_started t)))
          (plist-get response :last_started) identity)
    (omnivox-preview-test--control-line process response)))

(ert-deftest emacsvox-aural-replay-sends-private-exact-voice-without-changing-history-or-registry ()
  (let* ((record (emacsvox-replay-test--record))
         (emacsvox-aural-presentation-history (list record))
         (history emacsvox-aural-presentation-history))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (let ((operation (emacsvox-aural-replay--play record)))
       (should-not (emacsvox-aural-replay--operation-finished operation))
       (should (= (length writes) 1))
       (let* ((request (omnivox--decode-control-response
                        (substring (car writes) (length "omnivox_control {") -2) t))
              (row (aref (plist-get (plist-get request :voice) :choices) 0)))
         (should (equal (plist-get request :type) "preview_voice_v2"))
         (should (equal (plist-get row :selector)
                        '(:kind "exact" :engine_id "eloquence" :voice_id "Reed")))
         (should (equal (plist-get request :selection) '(:mode "choice" :choice_id "eloquence-male")))
         (should (eq (plist-get (plist-get request :fallback_policy) :global_default) :null)))
       (emacsvox-replay-test--reply speaker 41)
       (should (emacsvox-aural-replay--operation-finished operation))
       (should-not (process-get speaker 'emacsvox-aural-replay))
       (should (eq history emacsvox-aural-presentation-history))
       (should-not (process-get speaker omnivox--choice-registration-property))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest emacsvox-aural-replay-stop-and-replacement-retire-old-callbacks ()
  (let ((record (emacsvox-replay-test--record)))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (let* ((first (emacsvox-aural-replay--play record))
            (second (emacsvox-aural-replay--play record)))
       (should (emacsvox-aural-replay--operation-finished first))
       (should-not (emacsvox-aural-replay--operation-finished second))
       (should (= (length writes) 2))
       (emacsvox-replay-test--reply speaker 41)
       (should-not (emacsvox-aural-replay--operation-finished second))
       (tts-stop)
       (should (emacsvox-aural-replay--operation-finished second))
       (emacsvox-replay-test--reply speaker 42)
       (should (= (length writes) 2))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest emacsvox-aural-replay-rejects-substituted-voice-and-stops-next-stage ()
  (let ((record (emacsvox-replay-test--record)))
    (setf (emacsvox-aural-concrete-plan-after (emacsvox-aural-presentation-record-plan record))
          (list (emacsvox-aural--make-concrete-action :kind 'pause :duration 10)))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (let ((operation (emacsvox-aural-replay--play record)))
       (emacsvox-replay-test--reply speaker 41 t)
       (should (emacsvox-aural-replay--operation-finished operation))
       (should (= (length writes) 1))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest emacsvox-aural-replay-preflights-missing-evidence-before-interrupting ()
  (let ((record (emacsvox-replay-test--record)))
    (setf (emacsvox-aural-presentation-record-playback record) nil)
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (should-error (emacsvox-aural-replay--play record) :type 'user-error)
     (should-not writes)
     (should (= stops 0)))))

(ert-deftest emacsvox-aural-replay-startup-stop-does-not-restart-speech ()
  (let ((record (emacsvox-replay-test--record)))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (let* (observed
            (hook (lambda (_owner) (unless observed (setq observed t) (tts-stop)))))
       (add-hook 'tts-stopped-hook hook)
       (unwind-protect
           (should (emacsvox-aural-replay--operation-finished (emacsvox-aural-replay--play record)))
         (remove-hook 'tts-stopped-hook hook))
       (should-not writes)
       (omnivox-preview-test--clean speaker)))))

(ert-deftest emacsvox-aural-replay-bounded-evidence-never-blocks-delivery ()
  (emacsvox-replay-test--with-runtime
   (let ((emacsvox-aural-replay--byte-limit 1))
     (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit notification)))
       (should id)
       (emacsvox-replay-test--observe notification id)
       (emacsvox-replay-test--complete notification id)
       (should-error (emacsvox-aural-replay--steps record) :type 'user-error)
       (should (= 0 (process-get notification 'tts--dispatch-metadata-bytes)))))))

(ert-deftest emacsvox-aural-replay-orders-pauses-and-cleans-up-after-completion ()
  (let* ((record (emacsvox-replay-test--record))
         (plan (emacsvox-aural-presentation-record-plan record)))
    (setf (emacsvox-aural-concrete-plan-before plan)
          (list (emacsvox-aural--make-concrete-action :kind 'pause :duration 10))
          (emacsvox-aural-concrete-plan-after plan)
          (list (emacsvox-aural--make-concrete-action :kind 'pause :duration 20)))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--bundle speaker)
     (process-put speaker tts--tracked-playback-completion-property t)
     (let ((operation (emacsvox-aural-replay--play record)))
       (should-not (emacsvox-aural-replay--operation-finished operation))
       (should-not (cl-some (lambda (write) (string-prefix-p "omnivox_control " write)) writes))
       (emacsvox-replay-test--complete speaker (emacsvox-aural-replay--operation-dispatch operation))
       (should (string-prefix-p "omnivox_control " (car writes)))
       (emacsvox-replay-test--reply speaker 41)
       (should (string-match-p "emacsvox_tracked_dispatch " (car writes)))
       (emacsvox-replay-test--complete speaker (emacsvox-aural-replay--operation-dispatch operation))
       (should (eq (emacsvox-aural-replay--operation-finished operation) 'completed))
       (should-not (emacsvox-aural-replay--operation-timer operation))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest emacsvox-aural-replay-spoken-label-keeps-its-own-actual-voice ()
  (emacsvox-replay-test--with-runtime
   (let* ((run (omnivox-choice-timeline-test--run 'bolden nil nil "Content"))
          (label (emacsvox-aural--make-concrete-action :kind 'speech :text "Label" :voice-request 'bolden)))
     (setf (emacsvox-aural-concrete-plan-before (car run)) (list label))
     (pcase-let ((`(,id ,record) (emacsvox-replay-test--submit speaker (list run))))
       (emacsvox-replay-test--observe speaker id nil "Label" 1 1 1)
       (emacsvox-replay-test--observe speaker id t "Content" 2 3 2)
       (emacsvox-replay-test--complete speaker id)
       (let* ((plan (emacsvox-aural-presentation-record-plan record))
              (action (car (emacsvox-aural-concrete-plan-before plan)))
              (steps (emacsvox-aural-replay--steps record nil (list plan action 'before)))
              (entry (cadar steps)))
         (should (= (length steps) 1))
         (should (equal (plist-get entry :text) "Label"))
         (should (equal (plist-get (plist-get (car (plist-get (plist-get entry :voice) :choices)) :selector) :engine-id)
                        "eloquence")))))))

(ert-deftest emacsvox-aural-replay-cue-timeout-cleans-up-without-stopping-newer-speech ()
  (dolist (newer '(nil t))
    (let* ((record (emacsvox-replay-test--record))
           (plan (emacsvox-aural-presentation-record-plan record)))
      (setf (emacsvox-aural-concrete-plan-before plan)
            (list (emacsvox-aural--make-concrete-action :kind 'pause :duration 10)))
      (emacsvox-test--with-complete-preview
       (omnivox-preview-test--bundle speaker)
       (process-put speaker tts--tracked-playback-completion-property t)
       (let* ((operation (emacsvox-aural-replay--play record))
              (timer (emacsvox-aural-replay--operation-timer operation))
              (before stops))
         (when newer (tts-queue--send-typed speaker "q {Later speech}\n" 'queue))
         (apply (timer--function timer) (timer--args timer))
         (should (eq (emacsvox-aural-replay--operation-finished operation) (if newer 'cancelled 'failed)))
         (should (= stops (+ before (if newer 0 1))))
         (should-not (emacsvox-aural-replay--operation-timer operation))
         (should-not (gethash (emacsvox-aural-replay--operation-dispatch operation) tts--tracked-dispatches))
         (omnivox-preview-test--clean speaker))))))

(ert-deftest emacsvox-aural-replay-native-retains-only-the-applied-native-layer ()
  (dolist (common-only '(nil t))
    (omnivox-native-runtime-test--with-speech
     (let ((emacsvox-aural-presentation-history nil))
       (pcase-let* ((`(,id ,record) (emacsvox-replay-test--submit speaker))
                    (receipt (omnivox-native-runtime-test--receipt id speaker)))
         (when common-only
           (setf (plist-get receipt :native_application)
                 '(:status "common_only" :plan_id :null :identity :null :masked_parameters [] :reason "Helper unavailable")))
         (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--start id))
         (omnivox-choice-playback-test--event speaker receipt)
         (emacsvox-replay-test--complete speaker id)
         (let* ((entry (cadar (emacsvox-aural-replay--steps record)))
                (row (car (plist-get (plist-get entry :voice) :choices))))
           (should (equal (plist-get (plist-get row :selector) :voice-id) "paul"))
           (should (eq (not (null (plist-get row :native))) (not common-only)))
           (should (equal (plist-get (omnivox--preview-layered-request entry speaker) :type)
                          (if common-only "preview_voice_v2" "preview_voice_v3")))))))))

(provide 'emacsvox-aural-replay-tests)
;;; emacsvox-aural-replay-tests.el ends here
