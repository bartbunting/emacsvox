;;; omnivox-choice-consumer-tests.el --- Ordinary speech coverage -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Follow public producers through preparation, compilation and final wire.
;; Characterize remaining legacy entry points without claiming tuning support.
;;; Code:
(require 'omnivox-choice-playback-tests)
(require 'emacsvox-aural-transport-tests)
(require 'emacsvox-speak)

(defmacro omnivox-choice-consumer-test--with-speech (&rest body)
  "Run BODY with real speech preparation and captured WRITES on both lanes."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-transport-scheme
    (omnivox-choice-playback-test--with-runtime
     (let ((tts-program "omnivox") (tts-quiet nil) (tts-stop-immediately nil)
           (voice-lock-mode t) (emacsvox-use-icons nil) writes)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (process command) (push (cons process command) writes)))
                 ((symbol-function 'tts-voice-reset-code) (lambda () ""))
                 ((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda () '(:adapter omnivox :dimensions
                               (average-pitch pitch-range stress richness rate-offset echo))))
                 ((symbol-function 'voice-from-acss) (lambda (_) 'generated))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (_) "[[logical_voice generated]]")))
         ,@body)))))

(defun omnivox-choice-consumer-test--timeline (write)
  "Decode the one structured timeline in captured WRITE."
  (let ((command (cdr write)))
    (should (string-match "emacsvox_timeline {\\([^}]+\\)}" command))
    (json-parse-string
     (decode-coding-string (base64-decode-string (match-string 1 command)) 'utf-8 t)
     :object-type 'plist :array-type 'list :null-object nil :false-object nil)))

(ert-deftest omnivox-choice-consumer-named-speech-and-notification-retain-owned-identity ()
  (omnivox-choice-consumer-test--with-speech
   (dolist (voice '(bolden voice-bolden))
     (tts-speak (propertize "ordinary" 'personality voice))
     (tts-notify (propertize "notification" 'personality voice) t))
   (should (= (length writes) 4))
   (cl-loop for write in (reverse writes) for index from 0 do
            (let* ((document (omnivox-choice-consumer-test--timeline write))
                   (wrapper (car (plist-get document :spans)))
                   (span (plist-get wrapper :span)))
              (should (eq (car write) (if (cl-evenp index) speaker notification)))
              (should (= (plist-get document :protocol_version) 4))
              (should (= (plist-get document :registry_generation) 1))
              (should (equal (plist-get wrapper :mode) "layered"))
              (should (equal (plist-get span :logical_voice_id) "bolden"))
              (should-not (plist-get span :context))
              (should-not (plist-member span :acss))
              (should-not (plist-member span :effects))))))

(ert-deftest omnivox-choice-consumer-context-and-speech-action-remain-sparse ()
  (omnivox-choice-consumer-test--with-speech
   (emacsvox-test--transport-scheme
    '((:id consumer :match (:role heading)
       :render (:before ((:id label :kind speech :text "Heading"
                          :voice (:preset bolden :stress 0)))
                :content (:voice (:preset bolden :richness 0 :echo nil))))))
   (let ((emacsvox-aural-submission-facts '(:role heading)))
     (tts-speak "body"))
   (let* ((document (omnivox-choice-consumer-test--timeline (car writes)))
          (spans (plist-get document :spans)))
     (should (= (length spans) 2))
     (should (equal (mapcar (lambda (row) (plist-get row :mode)) spans)
                    '("layered" "layered")))
     (should (equal (plist-get (plist-get (car spans) :span) :context)
                    '(:stress (:op "set" :value 0.0))))
     (should (equal (plist-get (plist-get (cadr spans) :span) :context)
                    '(:richness (:op "set" :value 0.0) :echo (:op "default")))))))

(ert-deftest omnivox-choice-consumer-word-spelling-keeps-contextual-voice ()
  (omnivox-choice-consumer-test--with-speech
   (emacsvox-test--transport-scheme
    '((:id consumer :match (:role heading)
       :render (:content (:voice (:preset bolden :rate-offset 0))))))
   (let ((emacsvox-aural-submission-facts '(:role heading)))
     (emacsvox-speak-spell-word "aB"))
   (let* ((document (omnivox-choice-consumer-test--timeline (car writes)))
          (spans (plist-get document :spans)))
     (should (equal (mapconcat (lambda (row) (plist-get (plist-get row :span) :text)) spans "")
                    "a B "))
     (dolist (row spans)
       (should (equal (plist-get row :mode) "layered"))
       (should (equal (plist-get (plist-get row :span) :logical_voice_id) "bolden"))
       (should (equal (plist-get (plist-get row :span) :context)
                      '(:rate_offset (:op "set" :value 0))))))))

(ert-deftest omnivox-choice-consumer-old-notification-lane-uses-shared-style ()
  (omnivox-choice-consumer-test--with-speech
   (process-put notification omnivox--choice-registration-property nil)
   (process-put notification omnivox--control-capabilities-property
                '(:features ("logical_voice_registration")))
   (process-put notification emacsvox-aural--structured-timeline-process-property 3)
   (process-put notification emacsvox-aural--relative-rate-process-property t)
   (tts-notify (propertize "old lane" 'personality 'voice-bolden) t)
   (let* ((document (omnivox-choice-consumer-test--timeline (car writes)))
          (span (car (plist-get document :spans))))
     (should (eq (caar writes) notification))
     (should (= (plist-get document :protocol_version) 3))
     (should-not (plist-member document :registry_generation))
     (should (= (plist-get (plist-get span :acss) :richness) (/ 5.0 9.0)))
     (should (= (plist-get span :rate_offset) 2))
     (should-not (plist-member span :context)))))

(ert-deftest omnivox-choice-consumer-word-spelling-retains-owned-capital-voice ()
  (omnivox-choice-consumer-test--with-speech
   ;; Give the spelling producer's existing animate cue the same tuned chain.
   ;; Re-register through the real service after changing storage.
   (let ((emacsvox-aural-voice-palette-registry
          (emacsvox-test--voice-data-registry
           (list (emacsvox-test--choice-fixture :unchanged-parent)
                 (cl-subst 'animate 'bolden (emacsvox-test--choice-fixture :expected-palette)))))
         (emacsvox-aural-routing--choice-sets
          (cl-subst 'animate 'bolden emacsvox-aural-routing--choice-sets)))
     (setq requests nil)
     (cl-letf (((symbol-function 'omnivox--logical-voice-ids)
                (lambda () '("animate" "voice-animate")))
               ((symbol-function 'process-send-string)
                (lambda (process command)
                  (push (cons process (omnivox-test--choice-decode-command command)) requests))))
       (omnivox-register-logical-voices)
       (dolist (write requests)
         (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write))))
     (emacsvox-speak-spell-word "aB")
     (let* ((document (omnivox-choice-consumer-test--timeline (car writes)))
            (spans (plist-get document :spans))
            (capital (cl-find "B" spans :test #'equal
                              :key (lambda (row) (plist-get (plist-get row :span) :text)))))
       (should (= (plist-get document :registry_generation) 2))
       (should (equal (plist-get capital :mode) "layered"))
       (should (equal (plist-get (plist-get capital :span) :logical_voice_id) "animate"))
       (should-not (plist-get (plist-get capital :span) :context))
       (should (equal (plist-get (car spans) :mode) "legacy"))))))

(ert-deftest omnivox-choice-consumer-compound-personality-is-explicit-legacy ()
  (omnivox-choice-consumer-test--with-speech
   (tts-speak (propertize "compound" 'personality '(voice-bolden voice-smoothen)))
   (let* ((document (omnivox-choice-consumer-test--timeline (car writes)))
          (wrapper (car (plist-get document :spans))))
     (should (= (plist-get document :protocol_version) 4))
     (should (equal (plist-get wrapper :mode) "legacy"))
     (should-not (plist-member (plist-get wrapper :span) :context)))))

(ert-deftest omnivox-choice-consumer-raw-named-queue-prevents-layered-transaction ()
  "Expose the remaining compatibility boundary, including its whole-packet effect."
  (omnivox-choice-consumer-test--with-speech
   (emacsvox-aural-call-with-delivery-transaction
    speaker
    (lambda ()
      (tts-speak-using-voice 'voice-bolden "raw")
      (tts-speak (propertize "prepared" 'personality 'voice-bolden))))
   (should writes)
   (should (string-match-p "raw" (cdar writes)))
   (should (string-match-p "prepared" (cdar writes)))
   (should-not (string-match-p "emacsvox_timeline" (cdar writes)))
   (should-not (gethash 1 tts--marker-dispatches))))

(ert-deftest omnivox-choice-consumer-isolated-letter-retains-legacy-protocol ()
  "Character review still uses the server's special rate/capital/interrupt path."
  (omnivox-choice-consumer-test--with-speech
   (emacsvox-speak-this-char ?B)
   (should (equal (cdar writes) "l {B}\n"))
   (should-not (cl-some (lambda (write) (string-match-p "emacsvox_timeline" (cdr write))) writes))
   (should-not (gethash 1 tts--marker-dispatches))))

(provide 'omnivox-choice-consumer-tests)
;;; omnivox-choice-consumer-tests.el ends here
