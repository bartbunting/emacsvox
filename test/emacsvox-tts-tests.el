;;; emacsvox-tts-tests.el --- TTS runtime contract tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Pin the generic speech runtime behavior before the DTK-to-TTS namespace
;; migration.  These tests do not start a speech server or produce audio.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dectalk-voices)
(require 'tts-speak)
(require 'emacsvox-sounds)
(require 'espeak-voices)
(require 'mac-voices)
(require 'omnivox-voices)
(require 'outloud-voices)
(require 'plain-voices)
(require 'swiftmac-voices)
(require 'voice-setup)

(defconst emacsvox-test--legacy-protocol-functions
  '(dtk-interp-silence
    dtk-interp-tone
    dtk-interp-queue
    dtk-interp-queue-code
    dtk-interp-speak
    dtk-interp-say
    dtk-interp-stop
    dtk-interp-sync
    dtk-interp-letter
    dtk-interp-next-language
    dtk-interp-previous-language
    dtk-interp-language
    dtk-interp-preferred-language
    dtk-interp-say-version
    dtk-interp-set-rate
    dtk-interp-set-character-scale
    dtk-interp-toggle-split-caps
    dtk-interp-set-punctuations
    dtk-interp-reset-state)
  "Removed DECtalk-era names for the generic speech-server protocol.")

(defconst emacsvox-test--legacy-notification-functions
  '(dtk-notify-process
    dtk-notify-stop
    dtk-notify-apply
    dtk-notify
    dtk-notify-icon
    dtk-notify-initialize)
  "Removed DECtalk-era names for generic notification speech.")

(defconst emacsvox-test--legacy-audio-cue-functions
  '(dtk-tone-deletion
    dtk-tone-upcase
    dtk-tone-downcase
    dtk-silence
    dtk-tone
    tts-tone-deletion
    tts-tone-upcase
    tts-tone-downcase)
  "Removed legacy names for generic tones and silence.")

(defconst emacsvox-test--legacy-punctuation-functions
  '(dtk-set-punctuations
    dtk-set-punctuations-to-all
    dtk-set-punctuations-to-some
    dtk-toggle-punctuation-mode)
  "Removed DECtalk-era names for generic punctuation commands.")

(defconst emacsvox-test--legacy-rate-functions
  '(dtk-set-rate
    dtk-rate-adjust
    dtk-set-predefined-rate
    dtk-set-character-scale)
  "Removed DECtalk-era names for generic speech-rate commands.")

(defconst emacsvox-test--legacy-behavior-functions
  '(dtk-strip-octals
    dtk-handle-caps
    dtk-toggle-quiet
    dtk-toggle-split-caps
    dtk-toggle-strip-octals
    dtk-toggle-caps
    dtk-toggle-speak-nonprinting-chars)
  "Removed DECtalk-era names for generic speech behavior.")

(defconst emacsvox-test--legacy-style-functions
  '(dtk-get-style
    dtk-get-voice-for-face
    dtk-speak-using-voice
    dtk-next-single-property-change
    dtk-next-style-change
    dtk-previous-style-change
    dtk-plain-cons-p
    dtk-audio-format)
  "Removed DECtalk-era names for generic styled speech.")

(defconst emacsvox-test--legacy-text-preparation-functions
  '(dtk-add-cleanup-pattern
    dtk-handle-repeating-patterns
    dtk-replace-duplicates
    dtk-fix-brackets
    dtk-fix-control-chars
    dtk-fix-backslash
    dtk-quote
    dtk-complement-chunk-separator-syntax
    dtk-chunk-on-white-space-and-punctuations
    dtk-chunk-only-on-punctuations
    dtk-move-across-a-chunk
    dtk-toggle-splitting-on-white-space
    dtk-set-chunk-separator-syntax
    dtk-org-fold
    dtk--skip-invisible-forward
    dtk--skip-invisible-backward
    dtk--delete-invisible-text
    dtk--with-charset-priority)
  "Removed DECtalk-era names for generic text preparation.")

(defconst emacsvox-test--legacy-character-functions
  '(dtk-speak-setup-character-table
    dtk-char-to-speech
    dtk-letter
    dtk-unicode-charset-limits
    dtk-unicode-build-skip-regexp
    dtk-unicode-update-untouched-charsets
    dtk-unicode-char-in-charsets-p
    dtk-unicode-char-untouched-p
    dtk-unicode-name-for-char
    dtk-unicode-char-punctuation-p
    dtk-unicode-apply-name-transformation-rules
    dtk-unicode-uncustomize-char
    dtk-unicode-customize-char
    dtk-unicode-user-table-handler
    dtk-unicode-full-table-handler
    dtk-unicode-full-name-for-char
    dtk-unicode-short-name-for-char
    dtk-unicode-replace-chars)
  "Removed DECtalk-era names for generic character pronunciation.")

(defconst emacsvox-test--legacy-server-functions
  '(dtk-set-language
    dtk-set-next-language
    dtk-set-previous-language
    dtk-set-preferred-language
    dtk-dispatch
    dtk-reset-default-voice
    dtk-reset-state
    dtk-select-server
    dtk-cloud
    dtk-local-server
    dtk-make-process
    dtk-initialize)
  "Removed DECtalk-era names for generic server lifecycle operations.")

(ert-deftest emacsvox-tts-omnivox-discovers-physical-voice-identifiers ()
  "Omnivox discovery invokes the server safely and preserves backend IDs."
  (let (invocation)
    (cl-letf
        (((symbol-function 'omnivox--server-program)
          (lambda () "/tmp/server path/omnivox"))
         ((symbol-function 'process-file)
          (lambda (program input destination display &rest arguments)
            (setq invocation
                  (list program input destination display arguments))
            (insert
             "((\"winrt:HKEY\\\\Voice\" \"Microsoft David\" \"en-US\" \"Enhanced\"))")
            0)))
      (should
       (equal
        (omnivox-query-voices)
        '(("winrt:HKEY\\Voice" "Microsoft David" "en-US" "Enhanced"))))
      (should
       (equal
        invocation
        '("/tmp/server path/omnivox" nil t nil ("--list-voices-alist")))))))

(ert-deftest emacsvox-tts-omnivox-rejects-malformed-voice-discovery ()
  "Malformed discovery data cannot become selectable Omnivox voices."
  (should-error
   (omnivox--parse-voices "((\"id\" \"name\" \"language\"))")
   :type 'error)
  (should-error
   (omnivox--parse-voices "((\"id\" \"name\" \"language\" \"quality\")) trailing")
   :type 'error))

(ert-deftest emacsvox-tts-omnivox-selects-voice-on-both-streams ()
  "Physical voice selection updates speaker and notification processes."
  (let ((tts-speaker-process 'speaker)
        (tts-notify-process 'notifier)
        (omnivox-default-voice-id "")
        writes)
    (cl-letf
        (((symbol-function 'process-live-p) (lambda (_process) t))
         ((symbol-function 'process-send-string)
          (lambda (process command)
            (push (list process command) writes))))
      (should
       (equal
        (omnivox-set-voice "winrt:HKEY\\Voice")
        "winrt:HKEY\\Voice")))
    (should (equal omnivox-default-voice-id "winrt:HKEY\\Voice"))
    (should
     (equal
      (nreverse writes)
      '((speaker "tts_set_voice winrt:HKEY\\Voice\n")
        (notifier "tts_set_voice winrt:HKEY\\Voice\n"))))))

(defun emacsvox-test--omnivox-decode-command (command)
  "Decode one Omnivox control COMMAND emitted by the adapter."
  (unless
      (string-match
       "\\`omnivox_control {\\([^}\n]+\\)}\n\\'" command)
    (error "Invalid Omnivox control command"))
  (json-parse-string
   (decode-coding-string
    (base64-decode-string (match-string 1 command)) 'utf-8 t)
   :object-type 'plist :array-type 'list
   :null-object nil :false-object nil))

(defun emacsvox-test--omnivox-event (response)
  "Encode RESPONSE as one Omnivox control event."
  (format "%s%s\n"
          omnivox-control-event-prefix
          (omnivox--encode-control-request response)))

(defun emacsvox-test--omnivox-marker-event (event)
  "Encode EVENT as one Omnivox playback marker record."
  (format "%s%s\n"
          omnivox-marker-event-prefix
          (omnivox--encode-control-request event)))

(ert-deftest emacsvox-tts-omnivox-encodes-versioned-control-requests ()
  "Control requests are UTF-8 JSON in a newline-free Base64 field."
  (let* ((encoded
          (omnivox--encode-control-request
           '(:protocol_version 1 :request_id 42 :type "capabilities")))
         (decoded
          (json-parse-string
           (decode-coding-string (base64-decode-string encoded) 'utf-8 t)
           :object-type 'plist)))
    (should-not (string-match-p "\n" encoded))
    (should (= (plist-get decoded :protocol_version) 1))
    (should (= (plist-get decoded :request_id) 42))
    (should (equal (plist-get decoded :type) "capabilities"))))

(ert-deftest emacsvox-tts-omnivox-control-filter-handles-fragments ()
  "Control responses tolerate fragments and do not hide ordinary output."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-filter-test" :buffer nil :noquery t))
         (response
          '(:protocol_version 1 :request_id 7 :type "capabilities"
            :server_version "1.3.0" :supported_protocol_versions [1]
            :features ["control_v1"]))
         (event (emacsvox-test--omnivox-event response))
         received
         forwarded)
    (unwind-protect
        (progn
          (set-process-filter
           process
           (lambda (_process output) (push output forwarded)))
          (omnivox--install-control-filter process)
          (puthash
           7 (lambda (_process value) (setq received value))
           (omnivox--pending-requests process))
          (omnivox--control-process-filter
           process (concat "server notice\n" (substring event 0 25)))
          (should-not received)
          (omnivox--control-process-filter process (substring event 25))
          (should (equal (plist-get received :type) "capabilities"))
          (should (equal (nreverse forwarded) '("server notice\n")))
          (should-not (gethash 7 (omnivox--pending-requests process))))
      (delete-process process))))

(ert-deftest emacsvox-tts-default-preview-restores-voice-in-one-dispatch ()
  "Standalone previews queue native codes and restore default voice state."
  (let ((tts-voice-preview-code-function
         (lambda (selector)
           (format "voice:%s" (plist-get selector :voice-id))))
        operations
        result)
    (cl-letf
        (((symbol-function 'tts--resolve-voice-preview-selector)
          (lambda (selector &optional _inventory)
            (list :engine-id (plist-get selector :engine-id)
                  :voice-id (plist-get selector :voice-id))))
         ((symbol-function 'tts-stop)
          (lambda () (push '(stop) operations)))
         ((symbol-function 'tts--protocol-queue-code)
          (lambda (code) (push (list 'code code) operations)))
         ((symbol-function 'tts--protocol-queue-text)
          (lambda (text) (push (list 'text text) operations)))
         ((symbol-function 'tts-voice-reset-code)
          (lambda () "default-voice"))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (push '(dispatch) operations))))
      (tts-default-voice-preview-sequence
       '((:text "same text"
          :selector (:kind exact :engine-id "dectalk" :voice-id "paul")
          :acss (:stress 0.7) :effects (:reverb 0.5))
         (:text "same text"
          :selector (:kind exact :engine-id "dectalk" :voice-id "betty")))
       (lambda (value) (setq result value))))
    (should
     (equal
      (nreverse operations)
      '((stop)
        (code "voice:paul") (text "same text") (code "default-voice")
        (code "voice:betty") (text "same text") (code "default-voice")
        (dispatch))))
    (should (eq (plist-get result :status) 'queued))
    (should (eq (plist-get result :completion-guarantee) 'queued-only))
    (should
     (equal (plist-get (car (plist-get result :results)) :degraded-acss)
            '(:stress)))
    (should
     (equal (plist-get (car (plist-get result :results)) :degraded-effects)
            '(:reverb)))))

(ert-deftest emacsvox-tts-omnivox-preview-is-exact-and-non-mutating ()
  "Omnivox preview waits for its owned playback response without registration."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-preview-test" :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (omnivox--control-request-sequence 300)
         (omnivox--logical-registry-generation 17)
         writes
         result)
    (unwind-protect
        (progn
          (process-put
           process omnivox--control-capabilities-property
           '(:features ("exact_voice_preview")))
          (omnivox--install-control-filter process)
          (cl-letf
              (((symbol-function 'tts-stop) #'ignore)
               ((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
            (omnivox-preview-voice-sequence
             '((:text "same text"
                :selector
                (:kind exact :scope session
                 :engine-id "eloquence" :voice-id "eci:Reed")
                :language "en-AU"
                :acss (:average-pitch 0.6 :richness 0.8)
                :effects (:reverb 0.5)))
             (lambda (value) (setq result value)))
            (should-not result)
            (let* ((request
                    (emacsvox-test--omnivox-decode-command (car writes)))
                   (identifier (plist-get request :request_id)))
              (should (equal (plist-get request :type) "preview"))
              (should (equal (plist-get (plist-get request :selector)
                                        :engine_id)
                             "eloquence"))
              (should (equal (plist-get (plist-get request :selector)
                                        :voice_id)
                             "eci:Reed"))
              (should (= (plist-get (plist-get request :acss)
                                    :average_pitch)
                         0.6))
              (omnivox--control-process-filter
               process
               (emacsvox-test--omnivox-event
                (list
                 :protocol_version 1 :request_id identifier
                 :type "preview_completed" :status "completed"
                 :requested (plist-get request :selector)
                 :realized '(:engine_id "eloquence" :voice_id "eci:Reed")
                 :degraded_acss ["richness"] :message :null)))))
          (should (eq (plist-get result :status) 'completed))
          (let ((preview (car (plist-get result :results))))
            (should (eq (plist-get preview :status) 'completed))
            (should
             (equal (plist-get preview :realized)
                    '(:engine-id "eloquence" :voice-id "eci:Reed")))
            (should (equal (plist-get preview :degraded-acss) '(richness)))
            (should (equal (plist-get preview :degraded-effects) '(:reverb))))
          (should (= omnivox--logical-registry-generation 17))
          (should-not (gethash 301 (omnivox--pending-requests process))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest emacsvox-tts-omnivox-preview-transports-supported-effects ()
  "Omnivox sends supported post-synthesis effects and reports degradation."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-effect-preview-test"
           :buffer nil :noquery t))
         (tts-speaker-process process)
         (omnivox--control-request-sequence 350)
         result writes)
    (process-put
     process omnivox--control-capabilities-property
     '(:features ("exact_voice_preview" "post_synthesis_effects_v1")))
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-send-string)
              (lambda (_process command) (push command writes)))
             ((symbol-function 'tts-stop) #'ignore))
          (omnivox-preview-voice-sequence
           (list
            '(:text "effect preview"
              :selector
              (:kind exact :scope session
               :engine-id "dectalk" :voice-id "Paul")
              :acss nil
              :effects (:gain 0.5 :low-pass 0.75 :reverb 0.4)))
           (lambda (value) (setq result value)))
          (let* ((request
                  (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id))
                 (effects (plist-get request :effects)))
            (should (= (plist-get effects :gain) 0.5))
            (should (= (plist-get effects :low_pass) 0.75))
            (should (= (plist-get effects :reverb) 0.4))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier
               :type "preview_completed" :status "completed"
               :requested (plist-get request :selector)
               :realized '(:engine_id "dectalk" :voice_id "Paul")
               :degraded_acss [] :degraded_effects ["low_pass"]
               :message :null))))
          (let ((preview (car (plist-get result :results))))
            (should (equal (plist-get preview :degraded-effects)
                           '(low-pass)))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest emacsvox-tts-omnivox-negotiates-capabilities-and-inventory ()
  "Registration waits for inventory and uses the preferred engine."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-negotiation-test" :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (omnivox-control-capabilities nil)
         (omnivox-engine-inventory nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (omnivox--logical-registry-generation 0)
         (omnivox--logical-registry-signature nil)
         (omnivox-control-last-error nil)
         (omnivox--control-request-sequence 80)
         writes)
    (puthash "voice-bolden" '(:average_pitch 0.4)
             omnivox--logical-acss-table)
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-send-string)
              (lambda (_process command) (push command writes))))
          (omnivox--negotiate-process process)
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id)))
            (should (equal (plist-get request :type) "capabilities"))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier
               :type "capabilities" :server_version "1.3.0"
               :supported_protocol_versions [1]
               :features ["control_v1" "emacsvox_tx" "engine_inventory"
                          "logical_voice_registration"
                          "playback_marker_events_v1"
                          "preferred_engine"
                          "tracked_playback_completion"]))))
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id)))
            (should (equal (plist-get request :type) "inventory"))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier :type "inventory"
               :inventory_generation 3 :preferred_engine_id "winrt"
               :engines []))))
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id))
                 (definition (car (plist-get request :definitions)))
                 (selector (car (plist-get definition :preferences))))
            (should (equal (plist-get request :type)
                           "register_logical_voices"))
            (should (equal (plist-get selector :kind) "engine_default"))
            (should (equal (plist-get selector :engine_id) "winrt"))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier
               :type "logical_voices_registered"
               :inventory_generation 3
               :registration
               '(:registry_generation 1 :bindings [])))))
          (should (equal (plist-get omnivox-control-capabilities :type)
                         "capabilities"))
          (should
           (process-get
            process emacsvox-aural--framed-delivery-process-property))
          (should
           (process-get
            process tts--tracked-playback-completion-property))
          (should
           (process-get process tts--marker-playback-events-property))
          (should (= (plist-get omnivox-engine-inventory
                                :inventory_generation)
                     3))
          (should-not omnivox-control-last-error)
          (should (= (hash-table-count
                      (omnivox--pending-requests process))
                     0)))
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-aggregates-post-synthesis-capabilities ()
  "Adapter capabilities include effects advertised by any live engine."
  (let ((omnivox-engine-inventory
         '(:engines
           [(:id "eloquence"
             :capabilities
             (:acss (:rate t :average_pitch t)
              :post_synthesis_dimensions
              ["gain" "low_pass" "reverb"]))
            (:id "dectalk"
             :capabilities
             (:acss (:rate t :pitch_range t)
              :post_synthesis_dimensions
              ["echo" "gain" "high_pass"]))
            (:id "legacy" :capabilities (:acss (:volume t)))])))
    (let ((capabilities (omnivox-voice-capabilities)))
      (should
       (equal (plist-get capabilities :dimensions)
              '(average-pitch pitch-range rate volume)))
      (should
       (equal (plist-get capabilities :post-synthesis-dimensions)
              '(echo gain high-pass low-pass reverb))))))

(ert-deftest emacsvox-tts-omnivox-negotiates-independent-routing-policy ()
  "Modern Omnivox receives global policy before selector-only registration."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-routing-policy-test"
           :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (omnivox-control-capabilities nil)
         (omnivox-engine-inventory nil)
         (omnivox-routing-policy-registration nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-engine-priority-ids '("eloquence" "dectalk"))
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-disabled-engine-ids '("dectalk"))
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (omnivox--logical-registry-generation 0)
         (omnivox--logical-registry-signature nil)
         (omnivox--control-request-sequence 100)
         writes)
    (puthash "voice-bolden" '(:average_pitch 0.4)
             omnivox--logical-acss-table)
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-send-string)
              (lambda (_process command) (push command writes))))
          (omnivox--negotiate-process process)
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id)))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier
               :type "capabilities" :server_version "1.3.0"
               :supported_protocol_versions [1]
               :features
               ["control_v1" "engine_inventory" "engine_recovery_probe"
                "logical_voice_registration" "runtime_routing_policy"]))))
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id)))
            (should (equal (plist-get request :type) "inventory"))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier :type "inventory"
               :inventory_generation 3 :preferred_engine_id "winrt"
               :routing_policy
               '(:routing_policy_generation 0
                 :policy
                 (:preferred_engine_ids ["winrt"]
                  :fallback_engine_ids [] :disabled_engine_ids []))
               :engine_runtime [] :engines []))))
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (identifier (plist-get request :request_id)))
            (should (equal (plist-get request :type) "set_routing_policy"))
            (should (= (plist-get request :routing_policy_generation) 1))
            (should
             (equal (append (plist-get request :preferred_engine_ids) nil)
                    '("eloquence" "dectalk")))
            (should
             (equal (append (plist-get request :fallback_engine_ids) nil)
                    '("espeak")))
            (should
             (equal (append (plist-get request :disabled_engine_ids) nil)
                    '("dectalk")))
            (omnivox--control-process-filter
             process
             (emacsvox-test--omnivox-event
              (list
               :protocol_version 1 :request_id identifier
               :type "routing_policy_applied" :inventory_generation 4
               :routing_policy
               '(:routing_policy_generation 1
                 :policy
                 (:preferred_engine_ids ["eloquence" "dectalk"]
                  :fallback_engine_ids ["espeak"]
                  :disabled_engine_ids ["dectalk"]))
               :logical_voices
               '(:registry_generation 0 :bindings [])))))
          (let* ((request (emacsvox-test--omnivox-decode-command (car writes)))
                 (definition (car (plist-get request :definitions)))
                 (selector (car (plist-get definition :preferences)))
                 (fallback (plist-get request :fallback_policy)))
            (should (equal (plist-get request :type)
                           "register_logical_voices"))
            (should (equal (plist-get selector :kind) "properties"))
            (should-not (append (plist-get fallback :fallback_engines) nil)))
          (should
           (equal
            (plist-get
             (plist-get omnivox-routing-policy-registration :policy)
             :disabled_engine_ids)
            '("dectalk"))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest emacsvox-tts-omnivox-bounds-control-responses ()
  "The adapter rejects oversized responses before Base64 decoding."
  (should-error
   (omnivox--decode-control-response
    (make-string (1+ omnivox-control-max-encoded-bytes) ?A))
   :type 'error))

(ert-deftest emacsvox-tts-omnivox-bounds-marker-events ()
  "The adapter rejects oversized marker events before Base64 decoding."
  (should-error
   (omnivox--decode-marker-event
    (make-string (1+ omnivox-marker-max-encoded-bytes) ?A))
   :type 'error))

(ert-deftest emacsvox-tts-omnivox-gates-framing-on-capability ()
  "Legacy Omnivox processes are not sent framed presentations."
  (let ((process
         (make-pipe-process
          :name "emacsvox-omnivox-legacy-capability-test"
          :buffer nil :noquery t))
        (tts-speaker-process nil))
    (unwind-protect
        (progn
          (omnivox--handle-capabilities-response
           process
           '(:type "capabilities" :server_version "1.3.0"
             :supported_protocol_versions (1)
             :features ("legacy_commands")))
          (should-not
           (process-get
            process emacsvox-aural--framed-delivery-process-property))
          (should-not
           (process-get
            process tts--tracked-playback-completion-property)))
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-preserves-structured-voice-selectors ()
  "Logical preferences keep engine IDs separate from native voice IDs."
  (let* ((omnivox-logical-voice-preferences
          '((voice-annotate
             (exact "dectalk" "paul")
             (exact "eloquence" "eci:v1")
             (engine-default "winrt"))))
         (omnivox-logical-voice-languages '((voice-annotate . "en-US")))
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (definition
          (omnivox--logical-definition-json
           (omnivox--effective-logical-voice-id 'voice-annotate)))
         (selectors (plist-get definition :preferences)))
    (should (equal (plist-get definition :language) "en-US"))
    (should (equal (plist-get (aref selectors 0) :engine_id) "dectalk"))
    (should (equal (plist-get (aref selectors 0) :voice_id) "paul"))
    (should (equal (plist-get (aref selectors 1) :engine_id) "eloquence"))
    (should (equal (plist-get (aref selectors 1) :voice_id) "eci:v1"))
    (should (equal (plist-get (aref selectors 2) :kind) "engine_default"))))

(ert-deftest emacsvox-tts-omnivox-voices-emit-logical-routing-directives ()
  "Defined voices select their logical route before legacy style codes."
  (let ((omnivox-voice-table (make-hash-table))
        (omnivox--logical-acss-table (make-hash-table :test #'equal)))
    (cl-letf (((symbol-function 'omnivox--schedule-logical-registration)
               #'ignore))
      (omnivox-define-voice
       'voice-annotate "[[pitch 1.4]]" '(:average_pitch 0.7)))
    (should
     (equal (omnivox-get-voice-command 'voice-annotate)
            "[[logical_voice voice-annotate]] [[pitch 1.4]]"))
    (should
     (equal (gethash "voice-annotate" omnivox--logical-acss-table)
            '(:average_pitch 0.7)))
    (should-error
     (omnivox--logical-voice-directive "invalid voice") :type 'error)))

(ert-deftest emacsvox-tts-omnivox-canonicalizes-semantic-voice-settings ()
  "Portable settings follow the personality indirection used for speech."
  (let ((semantic-name 'emacsvox-test-semantic-voice)
        (omnivox-logical-voice-preferences
         '((emacsvox-test-semantic-voice
            (engine-default "espeak"))))
        (omnivox-logical-voice-languages
         '((emacsvox-test-semantic-voice . "en-US")))
        (omnivox--logical-acss-table (make-hash-table :test #'equal)))
    (set semantic-name 'acss-a4-s6)
    (unwind-protect
        (progn
          (puthash "acss-a4-s6" '(:average_pitch 0.4)
                   omnivox--logical-acss-table)
          (should (equal (omnivox--logical-voice-ids) '("acss-a4-s6")))
          (let* ((definition
                  (omnivox--logical-definition-json "acss-a4-s6"))
                 (selector (aref (plist-get definition :preferences) 0)))
            (should (equal (plist-get definition :language) "en-US"))
            (should (equal (plist-get selector :kind) "engine_default"))
            (should (equal (plist-get selector :engine_id) "espeak"))))
      (makunbound semantic-name))))

(ert-deftest emacsvox-tts-omnivox-logical-generations-are-content-based ()
  "Identical registry retries retain a generation and changes advance it."
  (let ((omnivox-logical-voice-preferences nil)
        (omnivox-logical-voice-languages nil)
        (omnivox-fallback-engine-ids '("espeak"))
        (omnivox-global-default-selector nil)
        (omnivox-allow-same-language-fallback t)
        (omnivox--logical-acss-table (make-hash-table :test #'equal))
        (omnivox--logical-registry-generation 0)
        (omnivox--logical-registry-signature nil))
    (puthash "voice-bolden" '(:average_pitch 0.4)
             omnivox--logical-acss-table)
    (let ((first (omnivox--logical-registry-snapshot))
          (retry (omnivox--logical-registry-snapshot)))
      (should (= (plist-get first :registry_generation) 1))
      (should (= (plist-get retry :registry_generation) 1)))
    (puthash "voice-annotate" '(:stress 0.0)
             omnivox--logical-acss-table)
    (should (= (plist-get (omnivox--logical-registry-snapshot)
                          :registry_generation)
               2))))

(ert-deftest emacsvox-tts-omnivox-normalizes-logical-acss ()
  "Emacs ACSS values become clamped zero-to-one logical voice styles."
  (let ((style (make-acss :average-pitch 9 :pitch-range -2
                          :stress 5 :richness nil)))
    (should
     (equal
      (omnivox--normalized-acss-json style)
      '(:average_pitch 1.0 :pitch_range 0.0
        :stress 0.5555555555555556)))))

(ert-deftest emacsvox-tts-static-voice-inventory-preserves-identities ()
  "Static adapter families become structured engine/voice inventory."
  (let* ((tts-voice-capabilities-function #'outloud-voice-capabilities)
         (tts-voice-inventory-function #'tts-default-voice-inventory)
         (inventory (tts-voice-inventory))
         (engine (car (plist-get inventory :engines)))
         (voice (car (plist-get engine :voices))))
    (should (equal (plist-get inventory :adapter) "outloud"))
    (should (equal (plist-get inventory :source) "static"))
    (should (equal (plist-get inventory :preview-support) "family"))
    (should (equal (plist-get inventory :routing-policy-support)
                   "unsupported"))
    (should (equal (plist-get engine :engine-id) "outloud"))
    (should (equal (plist-get voice :engine-id) "outloud"))
    (should (stringp (plist-get voice :voice-id)))
    (should (stringp (plist-get voice :display-name)))
    (setf (plist-get voice :display-name) "changed")
    (should-not
     (equal
      (plist-get
       (car
        (plist-get
         (car (plist-get (tts-voice-inventory) :engines)) :voices))
       :display-name)
      "changed"))))

(ert-deftest emacsvox-tts-omnivox-projects-live-inventory ()
  "Omnivox inventory keeps engine and native voice IDs separate."
  (let* ((omnivox-engine-inventory
          '(:type "inventory" :inventory_generation 7
            :preferred_engine_id "eloquence"
            :engines
            ((:id "eloquence" :display_name "Eloquence" :version "6.1"
              :availability (:status "available")
              :health (:status "healthy")
              :default_voice_id "v1"
              :capabilities
              (:acss (:rate t :average_pitch nil)
               :markers (:word t))
              :voices
              ((:id (:engine_id "eloquence" :voice_id "eci:v1")
                :display_name "Adult male" :language "en-US"
                :gender "male" :quality "standard"
                :availability (:status "available")))))))
         (omnivox-engine-inventory-time '(0 0 0 0))
         (inventory (omnivox-voice-inventory))
         (engine (car (plist-get inventory :engines)))
         (voice (car (plist-get engine :voices))))
    (should (= (plist-get inventory :generation) 7))
    (should (equal (plist-get inventory :source) "cached"))
    (should (plist-get inventory :stale))
    (should (equal (plist-get inventory :preferred-engine-id) "eloquence"))
    (should (equal (plist-get engine :health) "healthy"))
    (should (equal (plist-get voice :engine-id) "eloquence"))
    (should (equal (plist-get voice :voice-id) "eci:v1"))))

(ert-deftest emacsvox-tts-omnivox-projects-runtime-engine-status ()
  "Normalized inventory keeps dynamic circuit state separate from capability."
  (let* ((omnivox-control-capabilities
          '(:features ("runtime_routing_policy" "engine_recovery_probe")))
         (omnivox-engine-inventory
          '(:type "inventory" :inventory_generation 9
            :preferred_engine_id "eloquence"
            :routing_policy
            (:routing_policy_generation 2
             :policy
             (:preferred_engine_ids ("eloquence" "dectalk")
              :fallback_engine_ids ("espeak")
              :disabled_engine_ids ("dectalk")))
            :engine_runtime
            ((:engine_id "eloquence" :circuit "cooldown"
              :last_failure "helper exited" :cooldown_remaining_ms 900
              :disabled_by_policy nil))
            :engines
            ((:id "eloquence" :display_name "Eloquence"
              :availability (:status "available")
              :health (:status "degraded" :reason "recovering")
              :capabilities
              (:audio_output "buffered_pcm"
               :acss (:rate t) :markers (:word t :native_index t))
              :voices nil))))
         (omnivox-engine-inventory-time '(0 0 0 0))
         (inventory (omnivox-voice-inventory))
         (engine (car (plist-get inventory :engines))))
    (should (equal (plist-get inventory :preferred-engine-order)
                   '("eloquence" "dectalk")))
    (should (equal (plist-get inventory :disabled-engine-ids) '("dectalk")))
    (should (equal (plist-get engine :audio-output) "buffered_pcm"))
    (should (equal (plist-get engine :circuit) "cooldown"))
    (should (equal (plist-get engine :last-failure) "helper exited"))
    (should (= (plist-get engine :cooldown-remaining-ms) 900))
    (should (equal (plist-get engine :marker-support)
                   '(word native-index)))
    (should (equal (plist-get engine :anchor-support)
                   "exact/native-index"))))

(ert-deftest emacsvox-tts-omnivox-requests-explicit-recovery-probe ()
  "The adapter sends one bounded probe request and refreshes its inventory."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-recovery-probe-test"
           :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (omnivox--control-request-sequence 500)
         writes result)
    (unwind-protect
        (progn
          (process-put
           process omnivox--control-capabilities-property
           '(:features ("engine_recovery_probe" "engine_inventory")))
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
            (omnivox-request-engine-recovery-probe
             "eloquence" (lambda (value) (setq result value)))
            (let* ((request
                    (emacsvox-test--omnivox-decode-command (car writes)))
                   (identifier (plist-get request :request_id)))
              (should
               (equal (plist-get request :type)
                      "request_engine_recovery_probe"))
              (should (equal (plist-get request :engine_id) "eloquence"))
              (omnivox--control-process-filter
               process
               (emacsvox-test--omnivox-event
                (list
                 :protocol_version 1 :request_id identifier
                 :type "engine_recovery_probe_requested"
                 :inventory_generation 10 :engine_id "eloquence"))))
            (should
             (equal (plist-get result :type)
                    "engine_recovery_probe_requested"))
            (should
             (equal
              (plist-get
               (emacsvox-test--omnivox-decode-command (car writes)) :type)
              "inventory"))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest emacsvox-tts-omnivox-reports-process-inventory-agreement ()
  "Normalized inventory diagnoses main and notification process divergence."
  (let* ((speaker
          (make-pipe-process
           :name "emacsvox-omnivox-agreement-speaker"
           :buffer nil :noquery t))
         (notifier
          (make-pipe-process
           :name "emacsvox-omnivox-agreement-notifier"
           :buffer nil :noquery t))
         (tts-speaker-process speaker)
         (tts-notify-process notifier)
         (inventory
          '(:inventory_generation 4 :preferred_engine_id "eloquence")))
    (unwind-protect
        (progn
          (process-put speaker omnivox--control-inventory-property inventory)
          (process-put notifier omnivox--control-inventory-property
                       (copy-tree inventory))
          (should
           (equal (omnivox--inventory-process-agreement) "agree"))
          (process-put
           notifier omnivox--control-inventory-property
           '(:inventory_generation 4 :preferred_engine_id "dectalk"))
          (should
           (equal (omnivox--inventory-process-agreement) "differ"))
          (delete-process notifier)
          (should
           (equal (omnivox--inventory-process-agreement) "single-process")))
      (when (process-live-p speaker) (delete-process speaker))
      (when (process-live-p notifier) (delete-process notifier)))))

(ert-deftest emacsvox-tts-swiftmac-projects-enumerated-voice-cache ()
  "SwiftMac exposes installed native IDs without parsing them into engine IDs."
  (let* ((swiftmac-voice-inventory-cache
          '((:engine-id "swiftmac"
             :voice-id "com.apple.voice.compact.en-AU.Karen"
             :display-name "Karen" :language "en-AU"
             :gender "female" :quality "default"
             :availability "available")))
         (swiftmac-voice-inventory-time (current-time))
         (swiftmac-voice-inventory-error nil)
         (inventory (swiftmac-voice-inventory))
         (engine (car (plist-get inventory :engines)))
         (voice (car (plist-get engine :voices))))
    (should (equal (plist-get inventory :source) "live"))
    (should (equal (plist-get inventory :preview-support) "exact"))
    (should (equal (plist-get voice :engine-id) "swiftmac"))
    (should
     (equal (plist-get voice :voice-id)
            "com.apple.voice.compact.en-AU.Karen"))))

(ert-deftest emacsvox-tts-swiftmac-preview-preserves-native-voice-id ()
  "SwiftMac exact preview emits the selected installed native identifier."
  (let ((swiftmac-voice-inventory-cache
         '((:engine-id "swiftmac"
            :voice-id "com.apple.voice.compact.en-AU.Karen"
            :display-name "Karen" :language "en-AU"
            :availability "available")))
        (swiftmac-voice-inventory-time (current-time))
        (swiftmac-voice-inventory-error nil))
    (should
     (equal
      (swiftmac-voice-preview-code
       '(:kind exact :scope session :engine-id "swiftmac"
         :voice-id "com.apple.voice.compact.en-AU.Karen"))
      " [{voice com.apple.voice.compact.en-AU.Karen}] "))))

(ert-deftest emacsvox-tts-omnivox-registers-both-processes-atomically ()
  "Both servers share a generation but use their own preferred engine."
  (let* ((speaker
          (make-pipe-process
           :name "emacsvox-omnivox-registration-speaker"
           :buffer nil :noquery t))
         (notifier
          (make-pipe-process
           :name "emacsvox-omnivox-registration-notifier"
           :buffer nil :noquery t))
         (tts-speaker-process speaker)
         (tts-notify-process notifier)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (omnivox--logical-registry-generation 0)
         (omnivox--logical-registry-signature nil)
         (omnivox--control-request-sequence 200)
         writes)
    (puthash "voice-annotate" '(:stress 0.0)
             omnivox--logical-acss-table)
    (unwind-protect
        (progn
          (process-put
           speaker omnivox--control-capabilities-property
           '(:type "capabilities"
             :features ("engine_inventory" "logical_voice_registration")))
          (process-put
           speaker omnivox--control-inventory-property
           '(:type "inventory" :preferred_engine_id "winrt"))
          (process-put
           notifier omnivox--control-capabilities-property
           '(:type "capabilities"
             :features ("engine_inventory" "logical_voice_registration")))
          (process-put
           notifier omnivox--control-inventory-property
           '(:type "inventory" :preferred_engine_id "espeak"))
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (process command)
                  (push (cons process command) writes))))
            (should (= (omnivox-register-logical-voices) 2)))
          (should (= (length writes) 2))
          (dolist (entry writes)
            (let* ((request
                    (emacsvox-test--omnivox-decode-command (cdr entry)))
                   (definition (car (plist-get request :definitions)))
                   (selector (car (plist-get definition :preferences)))
                   (expected
                    (if (eq (car entry) speaker) "winrt" "espeak")))
              (should (equal (plist-get request :type)
                             "register_logical_voices"))
              (should (= (plist-get request :registry_generation) 1))
              (should (= (length (plist-get request :definitions)) 1))
              (should (equal (plist-get selector :engine_id) expected)))))
      (delete-process speaker)
      (delete-process notifier))))

(defun emacsvox-test--tts-capture-protocol (thunk)
  "Call THUNK and return chronological speech protocol writes."
  (let ((tts-speaker-process 'speaker)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (funcall thunk))
    (nreverse writes)))

(ert-deftest emacsvox-tts-protocol-queues-text-and-control-codes ()
  "Text and engine control codes retain their wire representation."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-queue-text "hello")
       (tts--protocol-queue-code "voice")
       (tts--protocol-queue-text "   ")))
    '((speaker "q {hello }\n")
      (speaker "c {voice }\n")))))

(ert-deftest emacsvox-tts-protocol-dispatches-speech-operations ()
  "Core speech operations retain their exact server commands."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-dispatch)
       (tts--protocol-say "hello")
       (tts--protocol-letter "x")
       (tts--protocol-stop)
       (tts--protocol-version)))
    '((speaker "d\n")
      (speaker "tts_say { hello}\n")
      (speaker "l {x}\n")
      (speaker "s\n")
      (speaker "version\n")))))

(ert-deftest emacsvox-tts-reentrant-speech-preserves-outer-text ()
  "Nested speech cannot erase the enclosing TTS preparation buffer."
  (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
    (kill-buffer scratch))
  (let ((tts-stop-immediately nil)
        (emacsvox-pronounce-table nil)
        (emacsvox-pronounce-personality nil)
        (voice-lock-mode nil)
        (emacsvox-use-icons nil)
        nested
        queued)
    (unwind-protect
        (cl-letf
            (((symbol-function 'emacsvox-aural-prepared-text-p)
              (lambda (_text) t))
             ((symbol-function 'tts--protocol-sync) #'ignore)
             ((symbol-function 'tts-move-across-a-chunk)
              (lambda (&rest _arguments)
                (goto-char (point-max))
                t))
             ((symbol-function 'tts-voice-reset-code)
              (lambda () "reset"))
             ((symbol-function 'tts--protocol-queue-code)
              (lambda (_code)
                (unless nested
                  (setq nested t)
                  (tts--speak-transaction "inner"))))
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text) (push text queued)))
             ((symbol-function 'tts--protocol-dispatch) #'ignore))
          (tts--speak-transaction "outer"))
      (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
        (kill-buffer scratch)))
    (should (equal (nreverse queued) '("inner" "outer")))
    (should-not (get-buffer " *tts-scratch-buffer* <2>"))))

(ert-deftest emacsvox-tts-protocol-dispatches-tracked-speech ()
  "Tracked speech uses the supported playback command and returns its token."
  (let ((tts--tracked-dispatch-sequence 40)
        (tts-program "windows-outloud")
        identifier
        writes)
    (unwind-protect
        (cl-letf
            (((symbol-function 'tts--ensure-tracked-process-filter)
              #'ignore))
          (setq
           writes
           (emacsvox-test--tts-capture-protocol
            (lambda ()
              (setq
               identifier
               (tts--protocol-dispatch-tracked #'ignore)))))
          (should (= identifier 41))
          (should
           (equal
            writes
            '((speaker
               "emacsvox_tracked_dispatch 41\n")))))
      (tts-cancel-tracked-dispatch identifier))))

(ert-deftest emacsvox-tts-protocol-dispatches-marker-aware-speech ()
  "Marker-aware speech uses its negotiated command and owns both callbacks."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-marker-dispatch-test" :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-program "/tmp/emacsvox/servers/omnivox")
         (tts--tracked-dispatch-sequence 40)
         (tts--tracked-dispatches (make-hash-table :test #'eql))
         (tts--marker-dispatches (make-hash-table :test #'eql))
         identifier
         writes)
    (unwind-protect
        (progn
          (process-put process tts--tracked-playback-completion-property t)
          (process-put process tts--marker-playback-events-property t)
          (cl-letf
              (((symbol-function 'tts--ensure-tracked-process-filter)
                #'ignore)
               ((symbol-function 'emacsvox-aural-delivery-send)
                (lambda (_process command &optional _kind)
                  (push command writes))))
            (setq
             identifier
             (tts--protocol-dispatch-marked #'ignore #'ignore)))
          (should (= identifier 41))
          (should (equal writes '("emacsvox_marker_dispatch 41\n")))
          (should (gethash identifier tts--tracked-dispatches))
          (should (gethash identifier tts--marker-dispatches)))
      (tts-cancel-tracked-dispatch identifier)
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-delivers-bounded-marker-events-in-order ()
  "The nested process filters decode markers and retire them before terminal status."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-marker-filter-test" :buffer nil :noquery t))
         (identifier 73)
         (tts--tracked-dispatches (make-hash-table :test #'eql))
         (tts--marker-dispatches (make-hash-table :test #'eql))
         marker-events
         terminal-events
         forwarded)
    (unwind-protect
        (progn
          (set-process-filter
           process
           (lambda (_process output) (push output forwarded)))
          (omnivox--install-control-filter process)
          (tts--ensure-tracked-process-filter process)
          (puthash
           identifier
           (cons
            process
            (lambda (value status)
              (push (list value status) terminal-events)))
           tts--tracked-dispatches)
          (puthash
           identifier
           (tts--marker-dispatch-create
            :process process
            :callback
            (lambda (value event)
              (push (list value (plist-get event :type)) marker-events)))
           tts--marker-dispatches)
          (let* ((record
                  (emacsvox-test--omnivox-marker-event
                   (list
                    :protocol_version 1 :dispatch_id identifier :sequence 1
                    :type "utterance_started" :utterance_id 1 :text "hello"
                    :engine_id "winrt" :actual_voice nil
                    :logical_voice_id nil :sample_rate 44100 :frame_count 5)))
                 (split (/ (length record) 2)))
            (tts--speaker-process-filter process (substring record 0 split))
            (should-not marker-events)
            (tts--speaker-process-filter process (substring record split)))
          (should
           (equal marker-events '((73 "utterance_started"))))
          (tts--speaker-process-filter
           process "__EMACSVOX_TRACKED__ 73 completed\n")
          (should (equal terminal-events '((73 completed))))
          (should-not (gethash identifier tts--tracked-dispatches))
          (should-not (gethash identifier tts--marker-dispatches))
          (should-not forwarded))
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-enriches-timeline-semantic-events ()
  "Version 2 semantic markers recover the richer client-side action value."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-timeline-marker-test" :buffer nil :noquery t))
         (identifier 74)
         (tts--marker-dispatches (make-hash-table :test #'eql))
         (semantic-value '(:id opening :kind cue :source scheme))
         (omnivox-timeline-last-event nil)
         observed hook-event)
    (unwind-protect
        (progn
          (puthash
           identifier
           (tts--marker-dispatch-create
            :process process
            :callback
            (lambda (_value event) (setq observed event))
            :semantic-actions
            (list (cons "semantic.1" semantic-value)))
           tts--marker-dispatches)
          (let ((omnivox-timeline-event-hook
                 (list (lambda (event) (setq hook-event event)))))
            (should
             (omnivox--handle-marker-line
              process
              (string-trim-right
               (emacsvox-test--omnivox-marker-event
                (list
                 :protocol_version 2 :dispatch_id identifier :sequence 1
                 :type "semantic_event_reached" :action_id "semantic.1"
                 :utterance_id 1 :engine_id "eloquence"))))))
          (should (equal (plist-get observed :semantic_value) semantic-value))
          (should (equal (plist-get hook-event :action_id) "semantic.1"))
          (should
           (equal
            (plist-get
             (plist-get omnivox-timeline-last-event :event) :type)
            "semantic_event_reached")))
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-records-actual-route-and-degradation ()
  "Ordinary playback records realized engine, voice, and omitted dimensions."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-realized-route-test" :buffer nil :noquery t))
         (omnivox-last-realized-routes (make-hash-table :test #'equal))
         (omnivox--utterance-logical-voices
          (make-hash-table :test #'equal))
         changes)
    (unwind-protect
        (let ((omnivox-realized-route-changed-hook
               (list (lambda (route) (push route changes)))))
          (omnivox--handle-marker-line
           process
           (string-trim-right
            (emacsvox-test--omnivox-marker-event
             '(:protocol_version 2 :dispatch_id 75 :sequence 1
               :type "utterance_started" :utterance_id 3 :text "hello"
               :engine_id "eloquence"
               :actual_voice (:engine_id "eloquence" :voice_id "v1")
               :logical_voice_id "voice-bolden"
               :sample_rate 44100 :frame_count 20))))
          (omnivox--handle-marker-line
           process
           (string-trim-right
            (emacsvox-test--omnivox-marker-event
             '(:protocol_version 2 :dispatch_id 75 :sequence 2
               :type "timeline_style_degraded" :utterance_id 3
               :degraded_acss ["richness"]
               :degraded_effects ["reverb"]))))
          (let ((route (omnivox-last-realized-voice 'voice-bolden)))
            (should (equal (plist-get route :engine-id) "eloquence"))
            (should (equal (plist-get route :voice-id) "v1"))
            (should (equal (plist-get route :degraded-acss) '("richness")))
            (should (equal (plist-get route :degraded-effects) '("reverb"))))
          (should (= (length changes) 2)))
      (delete-process process))))

(ert-deftest emacsvox-tts-omnivox-reports-partial-configuration-apply ()
  "Complete configuration apply returns one terminal result per speech stream."
  (let* ((speaker
          (make-pipe-process
           :name "emacsvox-config-speaker-test" :buffer nil :noquery t))
         (notification
          (make-pipe-process
           :name "emacsvox-config-notification-test" :buffer nil :noquery t))
         (tts-speaker-process speaker)
         (tts-notify-process notification)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-fallback-engine-ids nil)
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (omnivox--logical-registry-generation 0)
         (omnivox--logical-registry-signature nil)
         (omnivox-voice-configuration-last-result nil)
         writes terminal)
    (unwind-protect
        (progn
          (dolist (process (list speaker notification))
            (process-put
             process omnivox--control-capabilities-property
             '(:features ("logical_voice_registration"))))
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (process command)
                  (push (list process command) writes))))
            (should
             (= (omnivox-apply-voice-configuration
                 (lambda (result) (setq terminal result)))
                2)))
          (should (= (length writes) 2))
          (dolist (write writes)
            (let* ((process (car write))
                   (request
                    (emacsvox-test--omnivox-decode-command (cadr write)))
                   (identifier (plist-get request :request_id)))
              (should
               (equal (plist-get request :type) "register_logical_voices"))
              (omnivox--dispatch-control-response
               process
               (if (eq process speaker)
                   (list
                    :protocol_version 1 :request_id identifier
                    :type "logical_voices_registered"
                    :registration
                    '(:registry_generation 0 :bindings []))
                 (list
                  :protocol_version 1 :request_id identifier :type "error"
                  :code "engine_unavailable" :message "notification failed")))))
          (should (eq (plist-get terminal :status) 'partial))
          (should (= (length (plist-get terminal :processes)) 2))
          (should
           (= (cl-count 'applied (plist-get terminal :processes)
                        :key (lambda (result) (plist-get result :status)))
              1))
          (should (equal terminal omnivox-voice-configuration-last-result)))
      (delete-process speaker)
      (delete-process notification))))

(ert-deftest emacsvox-tts-omnivox-reports-unsupported-live-stream ()
  "A live older stream cannot be omitted from complete apply diagnostics."
  (let* ((speaker
          (make-pipe-process
           :name "emacsvox-config-supported-test" :buffer nil :noquery t))
         (notification
          (make-pipe-process
           :name "emacsvox-config-unsupported-test" :buffer nil :noquery t))
         (tts-speaker-process speaker)
         (tts-notify-process notification)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-fallback-engine-ids nil)
         (omnivox-global-default-selector nil)
         (omnivox--logical-acss-table (make-hash-table :test #'equal))
         (omnivox--logical-registry-generation 0)
         (omnivox--logical-registry-signature nil)
         writes terminal)
    (unwind-protect
        (progn
          (process-put
           speaker omnivox--control-capabilities-property
           '(:features ("logical_voice_registration")))
          (process-put
           notification omnivox--control-capabilities-property
           '(:features ()))
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (process command)
                  (push (list process command) writes))))
            (should
             (= (omnivox-apply-voice-configuration
                 (lambda (result) (setq terminal result)))
                2)))
          (should (= (length writes) 1))
          (let* ((request
                  (emacsvox-test--omnivox-decode-command
                   (cadar writes)))
                 (identifier (plist-get request :request_id)))
            (omnivox--dispatch-control-response
             speaker
             (list
              :protocol_version 1 :request_id identifier
              :type "logical_voices_registered"
              :registration '(:registry_generation 0 :bindings []))))
          (should (eq (plist-get terminal :status) 'partial))
          (let ((failure
                 (cl-find
                  'failed (plist-get terminal :processes)
                  :key (lambda (result) (plist-get result :status)))))
            (should (eq (plist-get failure :role) 'notification))
            (should (eq (plist-get failure :phase) 'negotiation))
            (should
             (eq (plist-get failure :code)
                 'logical-registration-unsupported))))
      (delete-process speaker)
      (delete-process notification))))

(ert-deftest emacsvox-tts-marker-speech-rejects-unsupported-server ()
  "Marker-aware speech fails before submitting text to an older server."
  (let ((tts-program "espeak") called)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (_text) (setq called t))))
      (should-error
       (tts-speak-marked "hello" #'ignore #'ignore)
       :type 'user-error)
      (should-not called))))

(ert-deftest emacsvox-tts-tracked-speech-rejects-unsupported-server ()
  "Tracked speech fails clearly when its server cannot report completion."
  (let ((tts-program "espeak") called)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (_text) (setq called t))))
      (should-error
       (tts-speak-tracked "hello" #'ignore)
       :type 'user-error)
      (should-not called))))

(ert-deftest emacsvox-tts-recognizes-tracked-server-by-basename ()
  "An absolute Windows Outloud path retains its completion capability."
  (should
   (tts-tracked-playback-completion-p
    "/tmp/emacsvox/servers/windows-outloud"))
  (should-not (tts-tracked-playback-completion-p "windows-dtk")))

(ert-deftest emacsvox-tts-recognizes-negotiated-omnivox-tracking ()
  "Omnivox tracking is enabled per process only after negotiation."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-omnivox-tracking-test" :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-program "/tmp/emacsvox/servers/omnivox"))
    (unwind-protect
        (progn
          (should-not (tts-tracked-playback-completion-p))
          (process-put
           process tts--tracked-playback-completion-property t)
          (should (tts-tracked-playback-completion-p))
          (should
           (tts-tracked-playback-completion-p
            "/tmp/emacsvox/servers/omnivox"))
          (should-not
           (tts-tracked-playback-completion-p "windows-dtk")))
      (delete-process process))))

(ert-deftest emacsvox-tts-tracked-filter-handles-fragments-and-forwards-output ()
  "Tracked process output tolerates fragments and preserves other output."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-tracked-filter-test" :buffer nil :noquery t))
         (identifier 73)
         statuses
         forwarded)
    (unwind-protect
        (progn
          (process-put
           process tts--tracked-filter-property
           (lambda (_process output)
             (push output forwarded)))
          (process-put process tts--tracked-fragment-property "")
          (puthash
           identifier
           (cons
            process
            (lambda (value status)
              (push (list value status) statuses)))
           tts--tracked-dispatches)
          (tts--speaker-process-filter
           process
           "server notice\n__EMACSVOX_TRACKED_")
          (should-not statuses)
          (tts--speaker-process-filter
           process "_ 73 completed\r\n")
          (should (equal statuses '((73 completed))))
          (should-not (gethash identifier tts--tracked-dispatches))
          (should (equal (nreverse forwarded) '("server notice\n"))))
      (remhash identifier tts--tracked-dispatches)
      (delete-process process))))

(ert-deftest emacsvox-tts-tracked-filter-reports-cancellation ()
  "Tracked cancellation retires its callback without claiming completion."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-tracked-cancel-test" :buffer nil :noquery t))
         status)
    (unwind-protect
        (progn
          (puthash
           74
           (cons
            process
            (lambda (identifier outcome)
              (setq status (list identifier outcome))))
           tts--tracked-dispatches)
          (tts--speaker-process-filter
           process "__EMACSVOX_TRACKED__ 74 cancelled\n")
          (should (equal status '(74 cancelled)))
          (should-not (gethash 74 tts--tracked-dispatches)))
      (remhash 74 tts--tracked-dispatches)
      (delete-process process))))

(ert-deftest emacsvox-tts-retiring-process-cleans-owned-runtime-state ()
  "Retiring a server cancels delivery, callbacks, clients, and the process."
  (let ((process
         (make-pipe-process
          :name "emacsvox-retire-process-test" :buffer nil :noquery t))
        (tts--tracked-dispatches (make-hash-table :test #'eql))
        events)
    (unwind-protect
        (progn
          (puthash 17 (cons process #'ignore) tts--tracked-dispatches)
          (let ((tts-stopped-hook
                 (list (lambda (stopped) (push (list 'hook stopped) events)))))
            (cl-letf
                (((symbol-function 'emacsvox-aural-cancel-pending-deliveries)
                  (lambda (owner) (push (list 'cancel owner) events)))
                 ((symbol-function 'emacsvox-aural-delivery-send)
                  (lambda (owner command kind)
                    (push (list 'send owner command kind) events)))
                 ((symbol-function 'delete-process)
                  (lambda (owner) (push (list 'delete owner) events))))
              (tts--retire-process process)))
          (should-not (gethash 17 tts--tracked-dispatches))
          (should
           (equal
            (nreverse events)
            `((cancel ,process)
              (send ,process "s\n" stop)
              (hook ,process)
              (delete ,process)))))
      (when (process-live-p process)
        (delete-process process)))))

(ert-deftest emacsvox-tts-interrupt-deduplicates-notification-owner ()
  "Interrupting notifications stops each distinct process exactly once."
  (let ((speaker
         (make-pipe-process
          :name "emacsvox-interrupt-speaker-test" :buffer nil :noquery t))
        (notifier
         (make-pipe-process
          :name "emacsvox-interrupt-notifier-test" :buffer nil :noquery t))
        (tts--tracked-dispatches (make-hash-table :test #'eql)))
    (unwind-protect
        (dolist (case `((,notifier ,notifier 1) (,speaker ,notifier 2)))
          (let ((owner (nth 0 case))
                (tts-notify-process (nth 1 case))
                (expected (nth 2 case))
                writes
                stopped)
            (let ((tts-stopped-hook
                   (list (lambda (process) (push process stopped)))))
              (cl-letf
                  (((symbol-function 'emacsvox-aural-delivery-send)
                    (lambda (process command kind)
                      (push (list process command kind) writes)))
                   ((symbol-function
                     'emacsvox-aural-cancel-pending-deliveries)
                    #'ignore))
                (tts--interrupt-process owner t)))
            (should (= (length writes) expected))
            (should (= (length stopped) expected))
            (should (= (cl-count owner stopped :test #'eq) 1))
            (should
             (=
              (cl-count owner writes :key #'car :test #'eq)
              1))))
      (delete-process speaker)
      (delete-process notifier))))

(ert-deftest emacsvox-tts-unexpected-process-exit-retires-owned-state ()
  "An unexpected server exit fails callbacks and clears its runtime state."
  (let* ((process
          (make-process
           :name "emacsvox-unexpected-exit-test"
           :command '("sh" "-c" "exit 7")
           :buffer nil :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (tts--tracked-dispatches (make-hash-table :test #'eql))
         (emacsvox-aural-last-delivery-failure nil)
         callbacks
         cancellations
         stopped)
    (process-put process tts--speech-process-generation-property 19)
    (process-put process tts--speech-process-role-property 'speaker)
    (puthash
     31
     (cons
      process
      (lambda (identifier status)
        (push (list identifier status) callbacks)))
     tts--tracked-dispatches)
    (let ((tts-stopped-hook
           (list (lambda (owner) (push owner stopped)))))
      (cl-letf
          (((symbol-function 'emacsvox-aural-cancel-pending-deliveries)
            (lambda (owner) (push owner cancellations)))
           ((symbol-function 'message) #'ignore))
        (set-process-sentinel process #'tts--speech-process-sentinel)
        (while (process-live-p process)
          (accept-process-output process 0.1))
        (accept-process-output process 0.01)))
    (should-not tts-speaker-process)
    (should (equal callbacks '((31 failed))))
    (should-not (gethash 31 tts--tracked-dispatches))
    (should (equal cancellations (list process)))
    (should (equal stopped (list process)))
    (should
     (eq
      (plist-get emacsvox-aural-last-delivery-failure :reason)
      'speech-process-exited))
    (should
     (=
      (plist-get emacsvox-aural-last-delivery-failure :process-generation)
      19))
    (should
     (=
      (plist-get emacsvox-aural-last-delivery-failure :exit-status)
      7))))

(ert-deftest emacsvox-tts-old-process-exit-cannot-clear-replacement ()
  "A terminal event from an old process leaves the replacement current."
  (let ((old
         (make-pipe-process
          :name "emacsvox-old-speaker-test" :buffer nil :noquery t))
        (replacement
         (make-pipe-process
          :name "emacsvox-new-speaker-test" :buffer nil :noquery t))
        (tts--tracked-dispatches (make-hash-table :test #'eql))
        (emacsvox-aural-last-delivery-failure nil))
    (unwind-protect
        (let ((tts-speaker-process replacement)
              (tts-notify-process nil))
          (delete-process old)
          (cl-letf
              (((symbol-function 'message) #'ignore)
               ((symbol-function
                 'emacsvox-aural-cancel-pending-deliveries)
                #'ignore))
            (tts--speech-process-sentinel old "exited\n"))
          (should (eq tts-speaker-process replacement)))
      (when (process-live-p old) (delete-process old))
      (when (process-live-p replacement) (delete-process replacement)))))

(ert-deftest emacsvox-tts-intentional-retirement-suppresses-exit-failure ()
  "The sentinel does not report an intentionally retired server as failed."
  (let ((process
         (make-pipe-process
          :name "emacsvox-intentional-retire-test" :buffer nil :noquery t))
        (tts--tracked-dispatches (make-hash-table :test #'eql))
        (emacsvox-aural-last-delivery-failure nil)
        failures)
    (let ((emacsvox-aural-delivery-failed-hook
           (list (lambda (failure) (push failure failures)))))
      (process-put process tts--speech-process-retiring-property t)
      (delete-process process)
      (tts--speech-process-sentinel process "killed\n"))
    (should-not failures)
    (should-not emacsvox-aural-last-delivery-failure)))

(ert-deftest emacsvox-tts-initialize-retires-old-process-after-new-starts ()
  "Successful initialization retires the old server before publishing new."
  (let ((tts-speaker-process 'old)
        (tts-program "test-server")
        events)
    (cl-letf
        (((symbol-function 'tts-make-process)
          (lambda (_name)
            (push 'started events)
            'new))
         ((symbol-function 'tts--retire-process)
          (lambda (process)
            (push (list 'retired process) events)))
         ((symbol-function 'processp)
          (lambda (process) (memq process '(old new))))
         ((symbol-function 'tts-multistream-p) (lambda (_) nil))
         ((symbol-function 'require) (lambda (&rest _) t))
         ((symbol-function 'voice-setup)
          (lambda () (push (list 'configured tts-speaker-process) events))))
      (tts-initialize))
    (should (eq tts-speaker-process 'new))
    (should
     (equal
      (nreverse events)
      '(started (retired old) (configured new))))))

(ert-deftest emacsvox-tts-initialize-retires-stale-notification-process ()
  "Switching to a single-stream server retires the previous notifier."
  (let ((tts-speaker-process 'old-speaker)
        (tts-notify-process 'old-notifier)
        (tts-program "single-stream-server")
        events)
    (cl-letf
        (((symbol-function 'tts-make-process)
          (lambda (_name)
            (push 'started events)
            'new-speaker))
         ((symbol-function 'tts--retire-process)
          (lambda (process)
            (push
             (list 'retired process
                   :speaker tts-speaker-process
                   :notifier tts-notify-process)
             events)))
         ((symbol-function 'processp)
          (lambda (process)
            (memq process '(old-speaker old-notifier new-speaker))))
         ((symbol-function 'tts-multistream-p) (lambda (_) nil))
         ((symbol-function 'require) (lambda (&rest _) t))
         ((symbol-function 'voice-setup)
          (lambda () (push (list 'configured tts-speaker-process) events))))
      (tts-initialize))
    (should (eq tts-speaker-process 'new-speaker))
    (should-not tts-notify-process)
    (should
     (equal
      (nreverse events)
      '(started
        (retired old-speaker
                 :speaker old-speaker :notifier old-notifier)
        (retired old-notifier
                 :speaker new-speaker :notifier nil)
        (configured new-speaker))))))

(ert-deftest emacsvox-tts-notify-initialize-publishes-before-retirement ()
  "Notifier replacement uses common retirement after publishing its successor."
  (let ((tts-notify-process 'old)
        (tts-program "test-server")
        (tts-notification-device "test-device")
        events)
    (cl-letf
        (((symbol-function 'tts-make-process)
          (lambda (_name)
            (push 'started events)
            'new))
         ((symbol-function 'process-live-p)
          (lambda (process)
            (push (list 'validated process) events)
            (eq process 'new)))
         ((symbol-function 'processp)
          (lambda (process) (memq process '(old new))))
         ((symbol-function 'tts--retire-process)
          (lambda (process)
            (push
             (list 'retired process :current tts-notify-process)
             events))))
      (should (eq (tts-notify-initialize) 'new)))
    (should (eq tts-notify-process 'new))
    (should
     (equal
      (nreverse events)
      '(started (validated new) (retired old :current new))))))

(ert-deftest emacsvox-tts-notify-initialize-preserves-old-on-start-failure ()
  "A notifier startup failure leaves the working old process current."
  (let ((tts-notify-process 'old)
        (tts-program "test-server")
        (tts-notification-device "test-device")
        retired)
    (cl-letf
        (((symbol-function 'tts-make-process)
          (lambda (_name) (error "simulated notifier startup failure")))
         ((symbol-function 'tts--retire-process)
          (lambda (process) (push process retired))))
      (should-error (tts-notify-initialize)))
    (should (eq tts-notify-process 'old))
    (should-not retired)))

(ert-deftest emacsvox-tts-notify-initialize-clears-disabled-stream ()
  "Disabling the separate notifier clears and retires its old owner."
  (let ((tts-notify-process 'old)
        (tts-program "test-server")
        (tts-notification-device "")
        observed)
    (cl-letf
        (((symbol-function 'processp) (lambda (process) (eq process 'old)))
         ((symbol-function 'tts--retire-process)
          (lambda (process)
            (setq observed (list process tts-notify-process)))))
      (should-not (tts-notify-initialize)))
    (should-not tts-notify-process)
    (should (equal observed '(old nil)))))

(ert-deftest emacsvox-tts-protocol-dispatches-tone-and-silence ()
  "Tone and silence commands preserve optional forced dispatch."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-tone 440 100)
       (tts--protocol-tone 880 50 t)
       (tts--protocol-silence 25)
       (tts--protocol-silence 30 t)))
    '((speaker "t 440 100\n")
      (speaker "t 880 50\nd\n")
      (speaker "sh 25\n")
      (speaker "sh 30\nd\n")))))

(ert-deftest emacsvox-tts-protocol-updates-engine-state ()
  "Rate, punctuation, character, capitalization, and reset stay stable."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-set-rate 175)
       (tts--protocol-set-character-scale 1.5)
       (tts--protocol-set-split-caps t)
       (tts--protocol-set-split-caps nil)
       (tts--protocol-set-punctuations 'some)
       (tts--protocol-reset)))
    '((speaker "tts_set_speech_rate 175\n")
      (speaker "tts_set_character_scale 1.5\n")
      (speaker "tts_split_caps 1\n")
      (speaker "tts_split_caps 0\n")
      (speaker "tts_set_punctuations some\nd\n")
      (speaker "tts_reset \n")))))

(ert-deftest emacsvox-tts-voice-capabilities-are-adapter-owned-and-copied ()
  "The generic interface returns an isolated adapter descriptor."
  (let* ((descriptor
          '(:adapter test
            :source static
            :family-selection enumerated
            :families ((test-voice :label "Test voice"))
            :dimensions (family)))
         (tts-voice-capabilities-function (lambda () descriptor))
         (first (tts-voice-capabilities))
         (second (tts-voice-capabilities)))
    (should (equal first descriptor))
    (setcar (plist-get first :dimensions) 'average-pitch)
    (should (equal (plist-get second :dimensions) '(family)))
    (should (equal (plist-get descriptor :dimensions) '(family)))))

(ert-deftest emacsvox-tts-outloud-describes-and-compiles-base-voices ()
  "Eloquence publishes all presets and compiles portable family names."
  (let* ((capabilities (outloud-voice-capabilities))
         command)
    (should (eq (plist-get capabilities :adapter) 'outloud))
    (should (eq (plist-get capabilities :family-selection) 'enumerated))
    (should (= (length (plist-get capabilities :families)) 8))
    (should
     (eq (tts-voice-family-id 'female capabilities) 'outloud-v2))
    (should (eq (tts-voice-family-id "V7" capabilities) 'outloud-v7))
    (cl-letf (((symbol-function 'outloud-define-voice)
               (lambda (_name value) (setq command value))))
      (outloud-define-voice-from-acss
       'test-outloud-family
       (make-acss :family 'female :average-pitch 5)))
    (should (string-match-p (regexp-quote "`v2") command))
    (should (string-match-p (regexp-quote "`vb65") command))))

(ert-deftest emacsvox-tts-dectalk-describes-and-compiles-base-voices ()
  "DECtalk publishes its built-ins and accepts non-Paul ACSS settings."
  (let* ((capabilities (dectalk-voice-capabilities))
         command)
    (should (eq (plist-get capabilities :adapter) 'dectalk))
    (should (eq (plist-get capabilities :family-selection) 'enumerated))
    (should (= (length (plist-get capabilities :families)) 9))
    (should (eq (tts-voice-family-id 'female capabilities) 'betty))
    (should (eq (tts-voice-family-id 'child capabilities) 'kit))
    (cl-letf (((symbol-function 'dectalk-define-voice)
               (lambda (_name value) (setq command value))))
      (dectalk-define-voice-from-acss
       'test-dectalk-family
       (make-acss :family 'betty :average-pitch 5)))
    (should (string-match-p (regexp-quote ":nb") command))
    (should (string-match-p (regexp-quote "ap 122") command))))

(ert-deftest emacsvox-tts-free-form-mac-families-compile-installed-names ()
  "The macOS adapters preserve free-form installed voice identifiers."
  (should
   (equal (mac-get-family-code "Samantha")
          " [{voice samantha}] "))
  (should
   (equal (swiftmac-get-family-code "en-US:Alex")
          " [{voice en-US:Alex}] ")))

(ert-deftest emacsvox-tts-protocol-synchronizes-buffer-state ()
  "The synchronization command snapshots the current speech state."
  (let ((tts-punctuation-mode 'none)
        (tts-split-caps t)
        (tts-caps nil)
        (tts-speech-rate 210))
    (should
     (equal
      (emacsvox-test--tts-capture-protocol #'tts--protocol-sync)
      '((speaker "tts_sync_state none 1 0 210\n"))))))

(ert-deftest emacsvox-tts-protocol-dispatches-language-operations ()
  "Language navigation and preference commands retain their protocol."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-next-language t)
       (tts--protocol-previous-language nil)
       (tts--protocol-set-language "en-gb" t)
       (tts--protocol-set-preferred-language "en" "en-gb")))
    '((speaker "set_next_lang t\n")
      (speaker "set_previous_lang nil\n")
      (speaker "set_lang en-gb t \n")
      (speaker "set_preferred_lang en en-gb \n")))))

(ert-deftest emacsvox-tts-process-routing-honors-dynamic-binding ()
  "Temporarily selecting another process redirects protocol writes."
  (let ((tts-speaker-process 'primary)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (tts--protocol-stop)
      (let ((tts-speaker-process 'notification))
        (tts--protocol-stop)))
    (should
     (equal
      (nreverse writes)
      '((primary "s\n")
        (notification "s\n"))))))

(ert-deftest emacsvox-tts-notification-apply-selects-notification-process ()
  "Notification calls dynamically use the live notification process."
  (let ((tts-speaker-process 'primary)
        (tts-notify-process 'notification)
        selected)
    (cl-letf (((symbol-function 'processp) (lambda (_) t))
              ((symbol-function 'process-status) (lambda (_) 'run)))
      (tts-notify-apply
       (lambda (_text) (setq selected tts-speaker-process))
       "notice"))
    (should (eq selected 'notification))))

(ert-deftest emacsvox-tts-notification-preserves-semantic-occasion ()
  "Notification transport does not replace an established semantic occasion."
  (let ((emacsvox-aural-submission-context
         '(:module agent-shell :occasion state-change))
        (emacsvox-aural-submission-occasion 'state-change)
        captured-context
        captured-occasion)
    (cl-letf (((symbol-function 'tts-notify-process) #'ignore)
              ((symbol-function 'tts-speak)
               (lambda (_text)
                 (setq
                  captured-context
                  (copy-tree emacsvox-aural-submission-context)
                  captured-occasion
                  emacsvox-aural-submission-occasion))))
      (tts-notify "Session mode changed" 'dont-log))
    (should (eq captured-occasion 'state-change))
    (should
     (eq (plist-get captured-context :occasion) 'state-change))))

(ert-deftest emacsvox-tts-org-fold-uses-current-hidden-spec ()
  "Org link visibility uses the current Emacs 31 folding spec."
  (let (events)
    (cl-progv
        '(org-fold-core-style org-link-descriptive)
        '(text-properties t)
      (cl-letf (((symbol-function 'outline-mode)
                 (lambda () (push '(outline) events)))
                ((symbol-function 'org-fold-initialize)
                 (lambda (ellipsis)
                   (push (list 'initialize ellipsis) events)))
                ((symbol-function 'org-fold-core-set-folding-spec-property)
                 (lambda (spec property value &optional force)
                   (push
                    (list 'spec spec property value force)
                    events))))
        (tts-org-fold)))
    (should
     (equal
      (nreverse events)
      '((outline)
        (initialize "...")
        (spec org-fold-hidden :visible nil nil))))))

(ert-deftest emacsvox-tts-canonical-protocol-preserves-wire-format ()
  "Canonical protocol entry points produce the established commands."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-queue-text "hello")
       (tts--protocol-set-rate 180)
       (tts--protocol-dispatch)))
    '((speaker "q {hello }\n")
      (speaker "tts_set_speech_rate 180\n")
      (speaker "d\n")))))

(ert-deftest emacsvox-tts-protocol-functions-support-native-advice ()
  "Canonical protocol functions remain directly adviceable."
  (let* ((calls 0)
         (advice (lambda (&rest _) (cl-incf calls))))
    (unwind-protect
        (progn
          (advice-add 'tts--protocol-stop :before advice)
          (emacsvox-test--tts-capture-protocol #'tts--protocol-stop)
          (should (= calls 1)))
      (advice-remove 'tts--protocol-stop advice))))

(ert-deftest emacsvox-tts-legacy-protocol-functions-are-removed ()
  "The generic protocol no longer exposes DECtalk-era function names."
  (dolist (function emacsvox-test--legacy-protocol-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-speech-function-is-removed ()
  "The generic speech entry point no longer exposes its DECtalk-era name."
  (should-not (fboundp 'dtk-speak)))

(ert-deftest emacsvox-tts-legacy-stop-function-is-removed ()
  "The speech stop entry point no longer exposes its DECtalk-era name."
  (should-not (fboundp 'dtk-stop)))

(ert-deftest emacsvox-tts-legacy-speak-list-function-is-removed ()
  "List speech no longer exposes its DECtalk-era function name."
  (should-not (fboundp 'dtk-speak-list)))

(ert-deftest emacsvox-tts-legacy-notification-api-is-removed ()
  "Notification speech no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-notification-functions)
    (should-not (fboundp function)))
  (should-not (boundp 'dtk-notify-process)))

(ert-deftest emacsvox-tts-legacy-audio-cue-functions-are-removed ()
  "Generic tones and silence no longer expose legacy helper names."
  (dolist (function emacsvox-test--legacy-audio-cue-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-punctuation-api-is-removed ()
  "Generic punctuation state and commands no longer expose DTK names."
  (dolist (function emacsvox-test--legacy-punctuation-functions)
    (should-not (fboundp function)))
  (should-not (boundp 'dtk-punctuation-mode))
  (should-not (boundp 'dtk-punctuation-mode-alist)))

(ert-deftest emacsvox-tts-legacy-rate-api-is-removed ()
  "Generic speech-rate state and commands no longer expose DTK names."
  (dolist (function emacsvox-test--legacy-rate-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-speech-rate
         dtk-speech-rate-base
         dtk-speech-rate-step
         dtk-character-scale))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-behavior-api-is-removed ()
  "Generic speech behavior no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-behavior-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-quiet
         dtk-split-caps
         dtk-caps
         dtk-strip-octals
         dtk-speak-nonprinting-chars
         dtk-octal-chars
         dtk-caps-regexp
         dtk-caps-prefix
         dtk-allcaps-prefix))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-style-api-is-removed ()
  "Generic styled speech no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-style-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-text-preparation-api-is-removed ()
  "Generic text preparation no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-text-preparation-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-cleanup-repeats
         dtk-bracket-regexp
         dtk-chunk-separator-syntax
         dtk-yank-excluded-properties))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-character-api-is-removed ()
  "Generic character pronunciation no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-character-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-handle-unicode
         dtk-character-to-speech-table
         dtk-unicode-character-replacement-alist
         dtk-unicode-name-transformation-rules-alist
         dtk-unicode-untouched-charsets
         dtk-unicode-handlers
         dtk-unicode-charset-filter-regexp
         dtk-unicode-cache))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-server-api-is-removed ()
  "Generic server lifecycle no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-server-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-program
         dtk-servers-alist
         dtk-cloud-server
         dtk-local-server-process
         dtk-speech-server-program
         dtk-local-server-port
         dtk-local-engine
         dtk-pamixer))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-program-uses-canonical-environment-variable ()
  "TTS_PROGRAM selects the server and the removed DTK variable is ignored."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "TTS_PROGRAM" "plain")
    (setenv "DTK_PROGRAM" "legacy")
    (should (equal (tts--default-program) "plain"))
    (setenv "TTS_PROGRAM" nil)
    (should-not (equal (tts--default-program) "legacy"))))

(defun emacsvox-test--tts-server-player (emacsvox-player emacspeak-player)
  "Return the Tcl TTS player selected from the supplied environment.

EMACSVOX-PLAYER and EMACSPEAK-PLAYER set their respective environment
variables; nil removes the variable."
  (let ((process-environment (copy-sequence process-environment))
        (library
         (expand-file-name "servers/tts-lib.tcl" emacsvox-directory)))
    (setenv "EMACSVOX_PLAY" emacsvox-player)
    (setenv "EMACSPEAK_PLAY" emacspeak-player)
    (with-temp-buffer
      (insert
       (format
        "source {%s}; tts_initialize; puts $tts(play)"
        library))
      (let ((status
             (call-process-region
              (point-min) (point-max) "tclsh" t t)))
        (unless (and (integerp status) (zerop status))
          (error "Could not exercise Tcl TTS initialization: %s"
                 (buffer-string)))
        (string-trim (buffer-string))))))

(ert-deftest emacsvox-tts-server-player-uses-emacsvox-environment ()
  "TTS servers honor EMACSVOX_PLAY and ignore the removed Emacspeak name."
  (skip-unless (executable-find "tclsh"))
  (should
   (equal
    (emacsvox-test--tts-server-player
     "/tmp/emacsvox-player" "/tmp/emacspeak-player")
    "/tmp/emacsvox-player"))
  (should
   (equal
    (emacsvox-test--tts-server-player nil "/tmp/emacspeak-player")
    "/usr/bin/paplay")))

(ert-deftest emacsvox-tts-state-remains-buffer-local ()
  "Changing speech state in one buffer does not alter another buffer."
  (let ((default-quiet (default-value 'tts-quiet))
        (default-rate (default-value 'tts-speech-rate)))
    (with-temp-buffer
      (setq tts-quiet (not default-quiet)
            tts-speech-rate (1+ default-rate))
      (should (eq tts-quiet (not default-quiet)))
      (should (= tts-speech-rate (1+ default-rate))))
    (with-temp-buffer
      (should (eq tts-quiet default-quiet))
      (should (= tts-speech-rate default-rate)))))

(ert-deftest emacsvox-tts-legacy-speaker-process-state-is-removed ()
  "The primary speech process no longer exposes its DECtalk-era state name."
  (should-not (boundp 'dtk-speaker-process)))

(ert-deftest emacsvox-tts-legacy-immediate-stop-state-is-removed ()
  "Immediate-stop state no longer exposes its DECtalk-era variable name."
  (should-not (boundp 'dtk-stop-immediately)))

(ert-deftest emacsvox-tts-auditory-icons-use-canonical-process ()
  "Queued resources and served icons use the canonical TTS process."
  (let ((tts-speaker-process 'canonical)
        (emacsvox-sounds-cache (make-hash-table))
        writes)
    (puthash 'served "/sounds/served.ogg" emacsvox-sounds-cache)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (emacsvox-queue-resource "/sounds/queued.ogg")
      (emacsvox-serve-icon 'served))
    (should
     (equal
      (nreverse writes)
      '((canonical "a \"/sounds/queued.ogg\"\n")
        (canonical "p \"/sounds/served.ogg\"\n"))))))

(ert-deftest emacsvox-tts-dectalk-soft-uses-canonical-runtime ()
  "The software DECtalk selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'dectalk-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events)))
              ((symbol-function 'tts-set-rate)
               (lambda (rate scope)
                 (push (list 'rate rate scope) events))))
      (dectalk-soft))
    (should
     (equal
      (nreverse events)
      `(configure
        (fastload "voice-defs")
        (select "dtk-soft")
        initialize
        (rate ,dectalk-default-speech-rate global))))))

(ert-deftest emacsvox-tts-dectalk-configures-canonical-state ()
  "The DECtalk adapter configures generic TTS state and dispatch."
  (let ((saved-state
         (mapcar
          (lambda (symbol)
            (list symbol
                  (boundp symbol)
                  (and (boundp symbol) (symbol-value symbol))))
          '(tts-default-voice tts-default-speech-rate
            tts-speech-rate-step tts-speech-rate-base
            tts-handle-unicode tts-voice-capabilities-function)))
        defaults
        character-scale
        untouched-charsets)
    (unwind-protect
        (cl-letf (((symbol-function 'set-default)
                   (lambda (symbol value)
                     (push (cons symbol value) defaults)))
                  ((symbol-function 'tts-set-character-scale)
                   (lambda (scale scope)
                     (setq character-scale (list scale scope))))
                  ((symbol-function 'tts-unicode-update-untouched-charsets)
                   (lambda (charsets)
                     (setq untouched-charsets charsets)))
                  ((symbol-function 'tts-voice-defined-p) #'ignore)
                  ((symbol-function 'tts-get-voice-command) #'ignore)
                  ((symbol-function 'tts-define-voice-from-acss) #'ignore))
          (dectalk-configure-tts)
          (should (eq (symbol-value 'tts-default-voice) 'paul))
          (should
           (= (symbol-value 'tts-default-speech-rate)
              dectalk-default-speech-rate))
          (should (= (symbol-value 'tts-speech-rate-step) 50))
          (should (= (symbol-value 'tts-speech-rate-base) 150))
          (should (symbol-value 'tts-handle-unicode))
          (should
           (eq (symbol-function 'tts-voice-defined-p)
               'dectalk-voice-defined-p))
          (should
           (eq (symbol-function 'tts-get-voice-command)
               'dectalk-get-voice-command))
          (should
           (eq (symbol-function 'tts-define-voice-from-acss)
               'dectalk-define-voice-from-acss))
          (should
           (eq tts-voice-capabilities-function
               #'dectalk-voice-capabilities)))
      (dolist (entry saved-state)
        (if (nth 1 entry)
            (set (car entry) (nth 2 entry))
          (makunbound (car entry)))))
    (should
     (equal
      (nreverse defaults)
      `((tts-default-speech-rate . ,dectalk-default-speech-rate)
        (tts-speech-rate-step . 50)
        (tts-speech-rate-base . 150))))
    (should (equal character-scale '(1.5 default)))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-outloud-uses-canonical-runtime ()
  "The Outloud selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'outloud-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (outloud))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "outloud")
        initialize)))))

(ert-deftest emacsvox-tts-outloud-configures-canonical-state ()
  "The Outloud adapter configures generic TTS state and dispatch."
  (let (defaults
        character-scale
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          tts-speech-rate-step tts-speech-rate-base
          tts-speech-rate tts-handle-unicode
          tts-voice-capabilities-function)
        '(nil 1 2 3 4 nil nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-set-character-scale)
                 (lambda (scale scope)
                   (setq character-scale (list scale scope))))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (outloud-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            outloud-default-speech-rate))
        (should (= (symbol-value 'tts-speech-rate-step) 10))
        (should (= (symbol-value 'tts-speech-rate-base) 50))
        (should
         (= (symbol-value 'tts-speech-rate)
            outloud-default-speech-rate))
        (should (symbol-value 'tts-handle-unicode))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'outloud-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'outloud-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'outloud-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'outloud-voice-capabilities))))
    (should
     (equal
      (nreverse defaults)
      `((tts-default-speech-rate . ,outloud-default-speech-rate)
        (tts-speech-rate-step . 10)
        (tts-speech-rate . ,outloud-default-speech-rate)
        (tts-speech-rate-base . 50))))
    (should (equal character-scale '(1.5 default)))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-espeak-uses-canonical-runtime ()
  "The eSpeak selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'espeak-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (espeak))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "espeak")
        initialize)))))

(ert-deftest emacsvox-tts-espeak-copies-canonical-character-table ()
  "The eSpeak table derives from canonical pronunciation state."
  (let ((espeak-character-to-speech-table nil)
        (source ["plain" "left [*] right"]))
    (cl-progv '(tts-character-to-speech-table) (list source)
      (espeak-setup-character-to-speech-table))
    (should
     (equal espeak-character-to-speech-table
            ["plain" "left   right"]))
    (should (equal source ["plain" "left [*] right"]))
    (should-not (eq espeak-character-to-speech-table source))))

(ert-deftest emacsvox-tts-espeak-configures-canonical-state ()
  "The eSpeak adapter configures generic TTS state and dispatch."
  (let (defaults
        character-table-setup
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          tts-voice-capabilities-function)
        '(unset 1 nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'espeak-setup-character-to-speech-table)
                 (lambda () (setq character-table-setup t)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (espeak-configure-tts)
        (should-not (symbol-value 'tts-default-voice))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            espeak-default-speech-rate))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'espeak-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'espeak-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'espeak-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'espeak-voice-capabilities))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,espeak-default-speech-rate))))
    (should character-table-setup)
    (should (equal untouched-charsets '(ascii latin-iso8859-1)))))

(ert-deftest emacsvox-tts-swiftmac-uses-canonical-runtime ()
  "The SwiftMac selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'swiftmac-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (swiftmac))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "swiftmac")
        initialize)))))

(ert-deftest emacsvox-tts-swiftmac-configures-canonical-state ()
  "The SwiftMac adapter configures generic TTS state and dispatch."
  (let (defaults
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          emacsvox-play-program tts-voice-capabilities-function)
        '(unset 1 local-player nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (swiftmac-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            swiftmac-default-speech-rate))
        (should-not (symbol-value 'emacsvox-play-program))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'swiftmac-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'swiftmac-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'swiftmac-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'swiftmac-voice-capabilities))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,swiftmac-default-speech-rate))))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-mac-uses-canonical-runtime ()
  "The macOS selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'mac-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (mac))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "mac")
        initialize)))))

(ert-deftest emacsvox-tts-mac-configures-canonical-state ()
  "The macOS adapter configures generic TTS state and dispatch."
  (let (defaults
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          emacsvox-play-program tts-voice-capabilities-function)
        '(unset 1 local-player nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (mac-configure-tts)
        (should
         (eq (symbol-value 'tts-default-voice) 'systemDefault))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            mac-default-speech-rate))
        (should-not (symbol-value 'emacsvox-play-program))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'mac-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'mac-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'mac-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'mac-voice-capabilities))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,mac-default-speech-rate))))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-plain-uses-canonical-runtime ()
  "The Plain selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'plain-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (plain))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "plain")
        initialize)))))

(ert-deftest emacsvox-tts-plain-configures-canonical-state ()
  "The Plain adapter configures generic TTS state and dispatch."
  (let (defaults)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          tts-voice-capabilities-function)
        '(unset 1 nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (plain-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            plain-default-speech-rate))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'plain-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'plain-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'plain-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'plain-voice-capabilities))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,plain-default-speech-rate))))))

(ert-deftest emacsvox-tts-canonical-state-aliases-remain-buffer-local ()
  "Canonical buffer-local state does not leak between buffers."
  (let ((default-quiet (default-value 'tts-quiet))
        (default-rate (default-value 'tts-speech-rate))
        (default-separators (default-value 'tts-chunk-separator-syntax)))
    (with-temp-buffer
      (setq tts-quiet (not default-quiet)
            tts-speech-rate (1+ default-rate)
            tts-chunk-separator-syntax "canonical")
      (should (eq tts-quiet (not default-quiet)))
      (should (= tts-speech-rate (1+ default-rate)))
      (should (equal tts-chunk-separator-syntax "canonical"))
      (should (local-variable-p 'tts-quiet))
      (should (local-variable-p 'tts-chunk-separator-syntax)))
    (with-temp-buffer
      (should (eq tts-quiet default-quiet))
      (should (= tts-speech-rate default-rate))
      (should (equal tts-chunk-separator-syntax default-separators)))))

(ert-deftest emacsvox-tts-voice-setup-selects-engine-adapter ()
  "Each speech-server name selects the corresponding voice adapter."
  (dolist
      (case
       '(("outloud" outloud-voices outloud)
         ("dtk-soft" dectalk-voices dectalk)
         ("swiftmac" swiftmac-voices swiftmac)
         ("mac" mac-voices mac)
         ("espeak" espeak-voices espeak)
         ("unknown" plain-voices plain)))
    (let ((tts-program (nth 0 case))
          required
          configured
          fastloaded)
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest _)
                   (push feature required)
                   feature))
                ((symbol-function 'outloud-configure-tts)
                 (lambda () (setq configured 'outloud)))
                ((symbol-function 'dectalk-configure-tts)
                 (lambda () (setq configured 'dectalk)))
                ((symbol-function 'swiftmac-configure-tts)
                 (lambda () (setq configured 'swiftmac)))
                ((symbol-function 'mac-configure-tts)
                 (lambda () (setq configured 'mac)))
                ((symbol-function 'espeak-configure-tts)
                 (lambda () (setq configured 'espeak)))
                ((symbol-function 'plain-configure-tts)
                 (lambda () (setq configured 'plain)))
                ((symbol-function 'ems--fastload)
                 (lambda (file) (setq fastloaded file))))
        (voice-setup))
      (should (memq (nth 1 case) required))
      (should (eq configured (nth 2 case)))
      (should
       (eq tts-voice-configuration-apply-function
           #'voice-setup-apply-voice-configuration))
      (should (equal fastloaded "voice-defs")))))

(provide 'emacsvox-tts-tests)
;;; emacsvox-tts-tests.el ends here
