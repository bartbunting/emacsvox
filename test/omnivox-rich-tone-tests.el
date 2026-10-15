;;; omnivox-rich-tone-tests.el --- Negotiated tone delivery -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise real registration, ordinary producers and retained marker evidence.
;;; Code:
(require 'omnivox-native-runtime-tests)

(defconst omnivox-rich-tone-test--features
  '("rich_tones_v1" "presentation_tone_v2" "presentation_timeline_v6"))

(defun omnivox-rich-tone-test--enable (process)
  "Add the complete richer-tone bundle to native PROCESS."
  (omnivox-native-runtime-test--enable process)
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
                                 "emacsvox_tone 2 insert 880 40 1 sine classic\n"
                               "emacsvox_tone 1 insert 880 40\n"))))
        (should (emacsvox-aural--legacy-frame-command-p (string-trim (car commands))))))))

(provide 'omnivox-rich-tone-tests)
;;; omnivox-rich-tone-tests.el ends here
