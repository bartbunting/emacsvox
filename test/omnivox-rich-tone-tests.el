;;; omnivox-rich-tone-tests.el --- Negotiated tone delivery -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise real registration, ordinary producers and retained marker evidence.
;;; Code:
(require 'omnivox-native-runtime-tests)
(require 'emacsvox-aural-replay-tests)

(defconst omnivox-rich-tone-test--features
  '("rich_tones_v1" "presentation_tone_v2" "presentation_timeline_v6"))

(defun omnivox-rich-tone-test--enable (process)
  "Add the complete richer-tone bundle to native PROCESS."
  (omnivox-native-runtime-test--enable process)
  (emacsvox-aural-enable-presentation-tone process 2)
  (process-put process omnivox--control-capabilities-property
               (list :features
                     (append omnivox-rich-tone-test--features
                             (plist-get (process-get process omnivox--control-capabilities-property)
                                        :features)))))

(ert-deftest omnivox-rich-tone-negotiation-requires-complete-worker-local-bundle ()
  (omnivox-test--with-choice-registration
    (dolist (missing (append omnivox-rich-tone-test--features omnivox-native-test--features))
      (omnivox-rich-tone-test--enable speaker)
      (process-put speaker omnivox--control-capabilities-property
                   (list :features (remove missing
                                           (plist-get (process-get speaker omnivox--control-capabilities-property)
                                                      :features))))
      (should-not (omnivox--rich-tones-supported-p speaker)))
    (omnivox-rich-tone-test--enable speaker)
    (should (omnivox--rich-tones-supported-p speaker))
    (should-not (omnivox--rich-tones-supported-p notification))
    ;; A replacement process starts without its predecessor's capabilities.
    (let ((replacement (make-pipe-process :name "rich-tone-reconnected" :noquery t)))
      (unwind-protect
          (progn
            (should-not (omnivox--rich-tones-supported-p replacement))
            (should-not (process-get replacement emacsvox-aural--presentation-tone-process-property)))
        (delete-process replacement)))))

(ert-deftest omnivox-rich-tone-capabilities-select-v6-before-registration ()
  (omnivox-test--with-choice-registration
    (omnivox-rich-tone-test--enable speaker)
    (cl-letf (((symbol-function 'omnivox-register-logical-voices) #'ignore))
      (omnivox--handle-capabilities-response
       speaker (append '(:type "capabilities")
                       (process-get speaker omnivox--control-capabilities-property))))
    (should (= 6 (process-get speaker emacsvox-aural--structured-timeline-process-property)))
    (should (= 2 (process-get speaker emacsvox-aural--presentation-tone-process-property)))
    (should-error (omnivox--choice-current-registration speaker))))

(ert-deftest omnivox-rich-tone-ordinary-speech-stays-v6-with-native-markers ()
  (omnivox-native-runtime-test--with-speech
    (omnivox-rich-tone-test--enable speaker)
    ;; Simulate a fresh registration on the newly negotiated worker.
    (process-put speaker omnivox--choice-registration-property nil)
    (omnivox-native-runtime-test--register)
    (tts-speak (propertize "ordinary" 'personality 'bolden))
    (tts-notify (propertize "notification" 'personality 'bolden) t)
    (dolist (write writes)
      (let ((document (omnivox-choice-consumer-test--timeline write)))
        (should (= (plist-get document :protocol_version)
                   (if (eq (car write) speaker) 6 5)))))
    (let ((id (omnivox-choice-playback-test--submit)))
      (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--start id))
      (omnivox-choice-playback-test--event speaker (omnivox-native-runtime-test--receipt id speaker))
      (should (eq (plist-get (omnivox-last-realized-voice 'bolden) :choice-status) 'verified)))))

(ert-deftest omnivox-rich-tone-multipart-and-capability-loss ()
  (omnivox-native-runtime-test--with-speech
    (omnivox-rich-tone-test--enable speaker)
    (process-put speaker omnivox--choice-registration-property nil)
    (omnivox-native-runtime-test--register)
    (let* ((snapshot (omnivox--choice-current-registration speaker))
           (document (car (emacsvox-aural--build-structured-timeline
                           2 91 (list (omnivox-choice-timeline-test--run 'bolden nil)) snapshot)))
           (emacsvox-aural--timeline-frame-max-bytes 128)
           (emacsvox-aural--timeline-encoded-fragment-max-bytes 172))
      (should (cl-every (lambda (part) (string-prefix-p "emacsvox_timeline_part 6 " part))
                        (emacsvox-aural--frame-structured-timeline document)))
      (process-put speaker omnivox--control-capabilities-property
                   (list :features omnivox-native-test--features))
      (should-error (omnivox--choice-current-registration speaker)))))

(ert-deftest omnivox-rich-tone-standalone-classic-uses-negotiated-version ()
  (omnivox-test--with-choice-registration
    (dolist (version '(1 2))
      (let (commands)
        (emacsvox-aural-enable-presentation-tone speaker version)
        (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                   (lambda (_process command _kind) (push command commands))))
          (emacsvox-aural--protocol-presentation-tone 880 40 'insert))
        (should (equal commands
                       (list (if (= version 2)
                                 "emacsvox_tone 2 insert 880 40 1.0 sine classic\n"
                               "emacsvox_tone 1 insert 880 40\n"))))
        (should (emacsvox-aural--legacy-frame-command-p (string-trim (car commands))))))))

(defun omnivox-rich-tone-test--action (volume &optional facts)
  "Compile a literal or fact-derived tone VOLUME using FACTS."
  (emacsvox-aural--compile-concrete-action
   (emacsvox-aural--compile-action
    (list :id 'test-tone :kind 'tone :pitch 880 :duration 40 :volume volume
          :audio-mode 'insert)
    'test 'before 0 'run)
   facts nil nil nil))

(ert-deftest omnivox-rich-tone-volume-reaches-standalone-and-timeline-unchanged ()
  (omnivox-native-runtime-test--with-speech
    (omnivox-rich-tone-test--enable speaker)
    (process-put speaker omnivox--choice-registration-property nil)
    (omnivox-native-runtime-test--register)
    (dolist (gain '(0 0.35 1))
      (let* ((action (omnivox-rich-tone-test--action gain))
             (run (omnivox-choice-timeline-test--run 'bolden nil))
             commands)
        (setf (emacsvox-aural-concrete-plan-before (car run)) (list action))
        (let* ((document (car (emacsvox-aural--build-structured-timeline
                              2 91 (list run) (omnivox--choice-current-registration speaker))))
               (tone (seq-find (lambda (a) (equal (plist-get a :type) "tone"))
                               (plist-get document :actions))))
          (should (= (plist-get document :protocol_version) 6))
          (should (= (plist-get tone :volume) gain)))
        (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                   (lambda (_process command _kind) (push command commands))))
          (emacsvox-aural-queue-concrete-action action))
        (should (equal commands (list (format "emacsvox_tone 2 insert 880 40 %s sine classic\n" gain))))
        (should (emacsvox-aural--legacy-frame-command-p (string-trim (car commands))))))))

(ert-deftest omnivox-rich-tone-old-worker-omits-cue-but-keeps-speech-and-evidence ()
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id quieter :match (:role heading)
        :render (:before ((:id quiet :kind tone :pitch 880 :duration 40 :volume 0.35))))))
    (let* ((result (emacsvox-test--capture-native-timeline "Keep this speech" :facts '(:role heading)))
           (timeline (plist-get result :timeline))
           (record (car emacsvox-aural-presentation-history))
           (plan (emacsvox-aural-presentation-record-plan record)))
      (should (equal (plist-get (car (plist-get timeline :spans)) :text) "Keep this speech"))
      (should-not (seq-find (lambda (a) (equal (plist-get a :type) "tone")) (plist-get timeline :actions)))
      (should (seq-find (lambda (d) (and (eq (plist-get d :reason) 'unsupported-tone-volume)
                                        (eq (plist-get d :policy) 'omit)))
                        (emacsvox-aural-concrete-plan-degradations plan)))
      (should (= (emacsvox-aural-concrete-action-requested-volume
                  (car (emacsvox-aural-concrete-plan-before plan))) 0.35)))))

(ert-deftest omnivox-rich-tone-old-worker-preview-refuses-inaccurate-volume ()
  (omnivox-test--with-choice-registration
    (let ((action (omnivox-rich-tone-test--action 0.3)) commands)
      (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                 (lambda (&rest args) (push args commands)))
                ((symbol-function 'tts--protocol-tone)
                 (lambda (&rest args) (push args commands))))
        (emacsvox-aural-queue-concrete-action action)
        (should-not commands)
        (let ((emacsvox-aural--exact-tone-preview t))
          (should-error (emacsvox-aural-queue-concrete-action action) :type 'user-error))
        (should-not commands)))))

(ert-deftest omnivox-rich-tone-frozen-volume-and-validation ()
  (omnivox-test--with-choice-registration
    (emacsvox-aural-enable-presentation-tone speaker 2)
    (let* ((facts (list :spelling-tone-pitch 0.35))
           (action (omnivox-rich-tone-test--action '(:fact spelling-tone-pitch) facts)))
      (setf (plist-get facts :spelling-tone-pitch) 0.9)
      (should (= (emacsvox-aural-concrete-action-requested-volume action) 0.35)))
    (dolist (bad '(nil -0.1 1.1 "0.5" 0.0e+NaN 1.0e+INF))
      (should-error (omnivox-rich-tone-test--action bad))
      (should-error (omnivox-rich-tone-test--action '(:fact spelling-tone-pitch)
                                                   (list :spelling-tone-pitch bad))))))

(ert-deftest omnivox-rich-tone-storage-promotes-only-personal-tone-volume ()
  (emacsvox-test--with-transport-scheme
    (let ((base (emacsvox-aural-user-data)))
      (should (= (plist-get base :schema-version) 9))
      (dolist (version '(9 10 11))
        (let ((data (plist-put (copy-tree base) :schema-version version)))
          (should (= (plist-get (emacsvox-aural-migrate-user-data data) :schema-version) version)))))
    (setq emacsvox-aural-user-rules
          '((:id quieter :match (:role heading)
             :render (:before ((:id quiet :kind tone :pitch 880 :duration 40 :volume 0.35))))))
    (let ((data (emacsvox-aural-user-data)))
      (should (= (plist-get data :schema-version) 11))
      (should (emacsvox-aural--validate-user-data data))
      (let* ((directory (make-temp-file "emacsvox-tone-volume-" t))
             (file (expand-file-name "aural.el" directory)))
        (unwind-protect
            (progn
              (emacsvox-aural--write-user-data data file)
              (should (equal data (emacsvox-aural-read-user-data file))))
          (delete-directory directory t)))
      (dolist (version '(9 10))
        (should-error (emacsvox-aural--validate-user-data
                       (plist-put (copy-tree data) :schema-version version)))))))

(ert-deftest omnivox-rich-tone-native-voice-save-preserves-volume-schema ()
  (emacsvox-test--with-voice-save
    (let* ((data (emacsvox-aural-read-user-data))
           (rules '((:id quieter :match (:role heading)
                     :render (:before ((:id quiet :kind tone :pitch 880
                                        :duration 40 :volume 0.35))))))
           (old (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
           (changed (emacsvox-aural-voice-data--put-choices
                     old 'bolden (emacsvox-test--native-choices) "native-after")))
      (setq data (plist-put data :schema-version 11)
            data (plist-put data :user-rules rules))
      (emacsvox-aural--write-user-data data)
      (let ((proposal (emacsvox-aural-voice-drafts--prepare
                       draft (plist-get changed :palette) (plist-get changed :choice-sets))))
        (emacsvox-aural-voice-drafts--save proposal)
        (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))
        (let ((saved (emacsvox-aural-read-user-data)))
          (should (= (plist-get saved :schema-version) 11))
          (should (equal (plist-get saved :user-rules) rules)))))))

(ert-deftest omnivox-rich-tone-replay-keeps-frozen-gain-and-preflights-old-workers ()
  (let* ((record (emacsvox-replay-test--record))
         (plan (emacsvox-aural-presentation-record-plan record))
         (action (emacsvox-aural--make-concrete-action
                  :kind 'tone :pitch 880 :duration 40 :audio-mode 'insert
                  :requested-volume 0.35 :volume-capability 'supported)))
    (setf (emacsvox-aural-concrete-plan-before plan) (list action))
    (emacsvox-test--with-complete-preview
      (omnivox-preview-test--bundle speaker)
      (should-error (emacsvox-aural-replay--play record) :type 'user-error)
      (should-not writes)
      (should (= stops 0))
      (emacsvox-aural-enable-presentation-tone speaker 2)
      (process-put speaker tts--tracked-playback-completion-property t)
      (let ((operation (emacsvox-aural-replay--play record)))
        (should (seq-some (lambda (write)
                            (string-match-p "emacsvox_tone 2 insert 880 40 0.35 sine classic" write)) writes))
        (tts-stop)
        (should (emacsvox-aural-replay--operation-finished operation)))
      (omnivox-preview-test--clean speaker))
    ;; A cue omitted in the original must not appear when replayed on a new worker.
    (setf (emacsvox-aural-concrete-action-volume-degradation action) '(:policy omit))
    (should-not (seq-find (lambda (step) (eq (car step) 'action))
                          (emacsvox-aural-replay--steps record)))))


(defconst omnivox-rich-tone-test--shape
  '(:waveform triangle :envelope (:attack-ms 5 :decay-ms 10 :sustain-level 0.4 :release-ms 15)))

(defun omnivox-rich-tone-test--shaped-action (shape &optional facts)
  "Compile tone SHAPE using FACTS."
  (emacsvox-aural--compile-concrete-action
   (emacsvox-aural--compile-action
    (list :id 'shaped :kind 'tone :pitch 880 :duration 40 :shape shape :audio-mode 'overlay)
    'test 'before 0 'run) facts nil nil nil))

(ert-deftest omnivox-rich-tone-shape-validation-and-freezing ()
  (omnivox-test--with-choice-registration
    (emacsvox-aural-enable-presentation-tone speaker 2)
    (let* ((shape (copy-tree omnivox-rich-tone-test--shape))
           (facts (list :spelling-tone-shape shape))
           (action (omnivox-rich-tone-test--shaped-action '(:fact spelling-tone-shape) facts)))
      (setf (plist-get (plist-get shape :envelope) :attack-ms) 60000)
      (should (equal (emacsvox-aural-concrete-action-shape action) omnivox-rich-tone-test--shape)))
    (dolist (shape '(nil (:waveform noise) (:waveform sine :waveform sine)
                    (:waveform sine :extra 2) (:waveform sine :envelope nil)
                    (:waveform sine :envelope (:attack-ms -1 :decay-ms 2 :sustain-level 0.5 :release-ms 3))
                    (:waveform sine :envelope (:attack-ms 1.2 :decay-ms 2 :sustain-level 0.5 :release-ms 3))
                    (:waveform sine :envelope (:attack-ms 1 :decay-ms 2 :sustain-level 0.0e+NaN :release-ms 3))
                    (:waveform sine :envelope (:attack-ms 1 :decay-ms 2 :sustain-level 1.1 :release-ms 3))))
      (should-error (omnivox-rich-tone-test--shaped-action shape))
      (should-error (omnivox-rich-tone-test--shaped-action '(:fact spelling-tone-shape)
                                                           (list :spelling-tone-shape shape))))))

(ert-deftest omnivox-rich-tone-shape-reaches-both-delivery-paths ()
  (omnivox-native-runtime-test--with-speech
    (omnivox-rich-tone-test--enable speaker)
    (process-put speaker omnivox--choice-registration-property nil)
    (omnivox-native-runtime-test--register)
    (dolist (waveform '(sine triangle square))
      (dolist (adsr '(nil t))
        (let* ((shape (append (list :waveform waveform)
                              (when adsr (list :envelope (copy-tree (plist-get omnivox-rich-tone-test--shape :envelope))))))
               (action (omnivox-rich-tone-test--shaped-action shape))
               (run (omnivox-choice-timeline-test--run 'bolden nil)) commands)
          (setf (emacsvox-aural-concrete-plan-before (car run)) (list action))
          (let* ((document (car (emacsvox-aural--build-structured-timeline
                                2 91 (list run) (omnivox--choice-current-registration speaker))))
                 (tone (seq-find (lambda (a) (equal (plist-get a :type) "tone")) (plist-get document :actions))))
            (should (equal (plist-get tone :shape)
                           (append (list :waveform (symbol-name waveform))
                                   (when adsr '(:envelope (:attack_ms 5 :decay_ms 10 :sustain_level 0.4 :release_ms 15)))))))
          (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                     (lambda (_ command _kind) (push command commands))))
            (emacsvox-aural-queue-concrete-action action))
          (should (equal (car commands) (format "emacsvox_tone 2 overlay 880 40 1.0 %s %s\n"
                                                waveform (if adsr "adsr 5 10 0.4 15" "classic"))))
          (should (emacsvox-aural--legacy-frame-command-p (string-trim (car commands)))))))))

(ert-deftest omnivox-rich-tone-shape-old-worker-keeps-speech-and-diagnostic ()
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     `((:id shaped :match (:role heading)
        :render (:before ((:id tone :kind tone :pitch 880 :duration 40
                          :shape ,omnivox-rich-tone-test--shape))))))
    (let* ((result (emacsvox-test--capture-native-timeline "Still speaking" :facts '(:role heading)))
           (timeline (plist-get result :timeline))
           (plan (emacsvox-aural-presentation-record-plan (car emacsvox-aural-presentation-history))))
      (should (equal (plist-get (car (plist-get timeline :spans)) :text) "Still speaking"))
      (should-not (seq-find (lambda (a) (equal (plist-get a :type) "tone")) (plist-get timeline :actions)))
      (should (seq-find (lambda (d) (eq (plist-get d :reason) 'unsupported-tone-shape))
                        (emacsvox-aural-concrete-plan-degradations plan)))
      (let ((emacsvox-aural--exact-tone-preview t))
        (should-error (emacsvox-aural-queue-concrete-action
                       (car (emacsvox-aural-concrete-plan-before plan))) :type 'user-error)))))

(ert-deftest omnivox-rich-tone-shape-storage-roundtrip ()
  (emacsvox-test--with-transport-scheme
    (setq emacsvox-aural-user-rules
          `((:id shaped :match (:role heading)
             :render (:before ((:id tone :kind tone :pitch 880 :duration 40
                               :shape ,omnivox-rich-tone-test--shape))))))
    (let ((data (emacsvox-aural-user-data)) (file (make-temp-file "tone-shape-")))
      (unwind-protect
          (progn
            (should (= (plist-get data :schema-version) 12))
            (emacsvox-aural--write-user-data data file)
            (should (equal (emacsvox-aural-read-user-data file) data))
            (dolist (version '(9 10 11))
              (should-error (emacsvox-aural--validate-user-data
                             (plist-put (copy-tree data) :schema-version version)))))
        (delete-file file)))))

(ert-deftest omnivox-rich-tone-shape-replay-is-frozen-and-capability-checked ()
  (let* ((record (emacsvox-replay-test--record))
         (plan (emacsvox-aural-presentation-record-plan record))
         (action (emacsvox-aural--make-concrete-action
                  :kind 'tone :pitch 880 :duration 40 :audio-mode 'overlay
                  :shape (copy-tree omnivox-rich-tone-test--shape))))
    (setf (emacsvox-aural-concrete-plan-before plan) (list action))
    (emacsvox-test--with-complete-preview
      (omnivox-preview-test--bundle speaker)
      (should-error (emacsvox-aural-replay--play record) :type 'user-error)
      (should-not writes)
      (should (= stops 0))
      (emacsvox-aural-enable-presentation-tone speaker 2)
      (process-put speaker tts--tracked-playback-completion-property t)
      (let ((operation (emacsvox-aural-replay--play record)))
        (should (seq-some (lambda (write)
                            (string-match-p "triangle adsr 5 10 0.4 15" write)) writes))
        (tts-stop)
        (should (emacsvox-aural-replay--operation-finished operation)))
      (omnivox-preview-test--clean speaker))
    (setf (emacsvox-aural-concrete-action-shape-degradation action) '(:policy omit))
    (should-not (seq-find (lambda (step) (eq (car step) 'action))
                          (emacsvox-aural-replay--steps record)))))

(ert-deftest omnivox-rich-tone-shape-frequency-and-format-boundaries ()
  (omnivox-test--with-choice-registration
    (emacsvox-aural-enable-presentation-tone speaker 2)
    (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed) #'ignore))
      (emacsvox-aural--protocol-presentation-tone 24000 40 'overlay 1 '(:waveform sine))
      (emacsvox-aural--protocol-presentation-tone 20000 40 'overlay 1 '(:waveform triangle))
      (should-error (emacsvox-aural--protocol-presentation-tone
                     20001 40 'overlay 1 '(:waveform triangle)))
      (should-not (emacsvox-aural--tone-shape-deliverable-p '(:waveform triangle) 5))
      (should (emacsvox-aural--tone-shape-deliverable-p '(:waveform sine) 5))
      (let ((emacsvox-aural--exact-tone-preview t))
        (should-error (emacsvox-aural--tone-shape-deliverable-p '(:waveform triangle) 5)
                      :type 'user-error)))))

(provide 'omnivox-rich-tone-tests)
;;; omnivox-rich-tone-tests.el ends here
