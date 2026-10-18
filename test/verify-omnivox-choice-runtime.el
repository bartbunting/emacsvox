;;; verify-omnivox-choice-runtime.el --- Muted real-server acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Opt-in fresh-batch acceptance. Set EMACSVOX_CHOICE_TEST_SERVER to a staged
;; development Omnivox executable advertising the complete choice bundle.
;; It starts isolated eSpeak processes with --audio-output null. No installed
;; server or personal configuration is changed. Build byte-code first; set
;; EMACSVOX_CHOICE_TEST_SOURCE=1 only when deliberately exercising source.
;; Set EMACSVOX_RICH_TONE_TEST=1 to require richer-tone negotiation and check
;; standalone and timeline gain on both workers, including reconnection.
;; EMACSVOX_EXTENDED_TONE_TEST=1 additionally requires extended tone shapes.

;;; Code:
(unless noninteractive (error "Run acceptance in a fresh batch Emacs"))
(require 'cl-lib)
(require 'ert)
(setq load-prefer-newer t)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (directory (expand-file-name "lisp/" root))
       (source (getenv "EMACSVOX_CHOICE_TEST_SOURCE")))
  (add-to-list 'load-path directory)
  (add-to-list 'load-path (expand-file-name "test/" root))
  (load (expand-file-name "emacsvox-preamble.el" directory) nil t)
  (dolist (name '("speech/tts-speak" "speech/omnivox-choice-codec" "aural/emacsvox-aural-transport" "speech/omnivox-voices"
                 "aural/emacsvox-aural-history" "aural/emacsvox-aural-replay"))
    (load (expand-file-name (concat name (if source ".el" ".elc")) directory) nil t)))
(require 'omnivox-choice-playback-tests)
(require 'emacsvox-aural-replay)
(defun omnivox-choice-acceptance--wait (predicate)
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (unless (funcall predicate) (error "Timed out waiting for muted client/server acceptance"))))
(defun omnivox-choice-acceptance--control (process type)
  (let (answer)
    (omnivox--send-control-request process (list :type type) (lambda (_ response) (setq answer response)))
    (omnivox-choice-acceptance--wait (lambda () answer))
    answer))
(defun omnivox-choice-acceptance--process (name generation)
  (let ((process (make-process :name name :noquery t :connection-type 'pipe
                               :command (list (or (getenv "EMACSVOX_CHOICE_TEST_SERVER") (error "Set EMACSVOX_CHOICE_TEST_SERVER"))
                                              "--engine" "espeak" "--audio-output" "null")
                               :stderr (get-buffer-create " *choice-live-errors*")
                               :filter #'tts--speaker-process-filter)))
    (process-put process 'tts--speech-process-generation generation)
    (omnivox--install-control-filter process)
    (let ((capabilities (omnivox-choice-acceptance--control process "capabilities")))
      (process-put process omnivox--control-capabilities-property capabilities)
      (unless (omnivox--choice-tuning-supported-p process) (error "Server lacks the complete choice bundle"))
      (when (getenv "EMACSVOX_RICH_TONE_TEST")
        (unless (omnivox--rich-tones-supported-p process) (error "Server lacks the richer-tone bundle"))
        (when (getenv "EMACSVOX_EXTENDED_TONE_TEST")
          (unless (omnivox--extended-tones-supported-p process) (error "Server lacks the extended-tone bundle")))
        ;; Inventory is requested synchronously below, before owned registration.
        (cl-letf (((symbol-function 'omnivox--request-inventory) #'ignore))
          (omnivox--handle-capabilities-response process capabilities))))
    (process-put process omnivox--control-inventory-property (omnivox-choice-acceptance--control process "inventory"))
    (process-put process tts--tracked-playback-completion-property t)
    (process-put process tts--marker-playback-events-property t)
    process))

(defun omnivox-choice-acceptance--tone (timeline &optional mode shape)
  "Verify a quiet tone in MODE with SHAPE, adding speech when TIMELINE is non-nil."
  (unless (memq (omnivox--choice-registration-version
                 (omnivox--choice-current-registration tts-speaker-process))
                (if (getenv "EMACSVOX_EXTENDED_TONE_TEST") '(7) '(6 7)))
    (error "Richer-tone registration did not select the required timeline version"))
  (let* ((action (emacsvox-aural--make-concrete-action
                  :kind 'tone :pitch 880 :duration 40 :audio-mode (or mode 'insert) :shape shape
                  :requested-volume 0.35 :volume-capability 'supported))
         (run (when timeline (omnivox-choice-timeline-test--run '(:preset bolden) nil)))
         result
         (tts--tracked-completion-function
          (lambda (_ status) (setq result status))))
    (when run (setf (emacsvox-aural-concrete-plan-before (car run)) (list action)))
    (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () "")))
      (emacsvox-aural-call-with-delivery-transaction
       tts-speaker-process
       (lambda ()
         (if run (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
           (emacsvox-aural-queue-concrete-action action))
         (if run (tts--protocol-dispatch)
           (tts--protocol-dispatch-tracked tts--tracked-completion-function)))))
    (omnivox-choice-acceptance--wait (lambda () result))
    (unless (eq result 'completed) (error "Tone dispatch ended %S" result))
    (princ (format "worker=%s tone=%s mode=%s shape=%S gain=0.35 completed\n"
                   (process-name tts-speaker-process) (if timeline (format "timeline%d" (omnivox--choice-registration-version (omnivox--choice-current-registration tts-speaker-process)))
                     (format "standalone%d" (process-get tts-speaker-process emacsvox-aural--presentation-tone-process-property)))
                   (or mode 'insert) shape))))
(let* ((tts-program "omnivox")
       (tts-speaker-process (omnivox-choice-acceptance--process "choice-live-main" 2001))
       (tts-notify-process (omnivox-choice-acceptance--process "choice-live-notify" 2002))
       (omnivox--logical-registry-generation 0)
       (omnivox--logical-registry-signature nil)
       (omnivox-average-pitch-contrast 1.0)
       (omnivox-logical-voice-preferences nil) (omnivox-logical-voice-languages nil)
       (omnivox-engine-priority-ids nil) (omnivox-fallback-engine-ids nil)
       (omnivox-disabled-engine-ids nil) (omnivox-global-default-selector nil)
       (omnivox-last-realized-routes (make-hash-table :test #'equal))
       (omnivox-realized-route-changed-hook nil) (tts-realized-voice-changed-hook nil)
       (omnivox-initial-routing-ready-hook nil) (tts-stopped-hook nil)
       (emacsvox-speak-messages nil) (omnivox-marker-last-error nil)
       (emacsvox-aural-presentation-history nil)
       (emacsvox-aural-presentation-history-limit 20)
       (emacsvox-aural-history-record-interface-presentations t)
       (emacsvox-aural-submission-controls-interruption nil)
       (emacsvox-aural-submission-delivery-policy 'ordered)
       (inventory (omnivox-choice-acceptance--control tts-speaker-process "inventory"))
       (engine (cl-find "espeak" (plist-get inventory :engines) :test #'equal :key (lambda (entry) (plist-get entry :id))))
       (physical (plist-get (car (plist-get engine :voices)) :id))
       (selector (list :kind 'exact :scope 'local :engine-id "espeak" :voice-id (plist-get physical :voice_id)))
       (choices (list (list :id "unavailable" :selector '(:kind exact :scope local :engine-id "absent-choice-test" :voice-id "absent") :adjustments nil)
                      (list :id "actual-fallback" :selector selector :adjustments '(:average-pitch nil :richness 0))
                      (list :id "same-physical-other-row" :selector selector :adjustments '(:richness 9))))
       (owned (list :mode 'owned :name 'bolden :palette 'isolated-acceptance :names '(bolden voice-bolden)
                    :definition '(:average-pitch 4 :richness 5 :rate-offset 2 :echo 2)
                    :choices choices :selectors (mapcar (lambda (row) (plist-get row :selector)) choices)
                    :choice-source 'local :language nil))
       (original tts-speaker-process))
  (unwind-protect
      (cl-letf (((symbol-function 'omnivox--logical-voice-ids) (lambda () '("bolden" "voice-bolden")))
                ((symbol-function 'emacsvox-aural-voice-runtime--owned) (lambda (&rest _) owned)))
        (unless physical (error "No eSpeak voice is available"))
        (dotimes (round 2)
          (let (applied)
            (omnivox-apply-voice-configuration (lambda (result) (setq applied result)))
            (omnivox-choice-acceptance--wait (lambda () applied))
            (unless (eq (plist-get applied :status) 'applied) (error "Configuration failed: %S" applied)))
          (omnivox-choice-acceptance--wait (lambda () (cl-every (lambda (process)
                                                  (eql omnivox--logical-registry-generation
                                                       (plist-get (process-get process omnivox--choice-registration-property) :registry-generation)))
                                                (list tts-speaker-process tts-notify-process))))
          (dolist (lane (list tts-speaker-process tts-notify-process))
            (let ((tts-speaker-process lane) result identifier)
              (setq identifier (omnivox-choice-playback-test--submit nil (lambda (_ status) (setq result status))))
              (omnivox-choice-acceptance--wait (lambda () result))
              (unless (eq result 'completed) (error "Real layered dispatch %s ended %S" identifier result))
              (let ((route (omnivox-last-realized-voice 'bolden)))
                (unless (and (eq (plist-get route :choice-status) 'verified)
                             (equal (plist-get route :choice-id) "actual-fallback")
                             (equal (plist-get route :engine-id) "espeak"))
                  (error "Unexpected real consumed route: %S; decoder: %S" route omnivox-marker-last-error))
                (princ (format "round=%d lane=%s dispatch=%d choice=%s registry=%d verified=t\n"
                               round (plist-get route :lane) identifier (plist-get route :choice-id) (plist-get route :registry-generation))))
              (unless (= 0 (process-get lane 'tts--dispatch-metadata-bytes)) (error "Retained metadata leaked"))
              (when (getenv "EMACSVOX_RICH_TONE_TEST")
                (dolist (mode '(insert overlay))
                  (dolist (shape (append '(nil (:waveform triangle)
                                          (:waveform square :envelope
                                           (:attack-ms 5 :decay-ms 10 :sustain-level 0.4 :release-ms 15)))
                                       (when (getenv "EMACSVOX_EXTENDED_TONE_TEST")
                                         '((:waveform pulse :pulse-width 0.05)
                                           (:waveform pulse :pulse-width 0.5)
                                           (:waveform pulse :pulse-width 0.95 :end-frequency-hz 1320
                                            :envelope-curve exponential :envelope
                                            (:attack-ms 5 :decay-ms 10 :sustain-level 0.4 :release-ms 15))
                                           (:waveform sawtooth :end-frequency-hz 220)))))
                    (omnivox-choice-acceptance--tone nil mode shape)
                    (omnivox-choice-acceptance--tone t mode shape))))))
          (let* ((record (car emacsvox-aural-presentation-history))
                 (operation (emacsvox-aural-replay--play record)))
            (omnivox-choice-acceptance--wait
             (lambda () (emacsvox-aural-replay--operation-finished operation)))
            (unless (eq (emacsvox-aural-replay--operation-finished operation) 'completed)
              (error "Historical notification voice replay failed"))
            (unless (eq record (car emacsvox-aural-presentation-history))
              (error "Replay recorded itself in history"))
            (princ (format "round=%d historical-notification-replay=completed\n" round)))
          (when (= round 0)
            (tts--retire-process tts-speaker-process)
            (setq tts-speaker-process (omnivox-choice-acceptance--process "choice-live-reconnected" 2003))
            (should-error (omnivox--choice-current-registration tts-speaker-process))))
        (when omnivox-marker-last-error (error "Marker codec rejected server output: %S" omnivox-marker-last-error)))
    (dolist (process (delete-dups (list original tts-speaker-process tts-notify-process)))
      (when (process-live-p process) (tts--retire-process process)))))
(princ "Muted real-server client acceptance passed.\n")

;;; verify-omnivox-choice-runtime.el ends here
