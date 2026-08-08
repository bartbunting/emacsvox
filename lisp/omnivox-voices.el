;;; omnivox-voices.el --- Omnivox voice adapter  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Voice and rate support for the Omnivox speech server.  Omnivox accepts
;; generic Emacsvox protocol commands and uses [[pitch FLOAT]] inline codes.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'json)
(require 'subr-x)

(declare-function emacsvox-aural-enable-framed-delivery
                  "emacsvox-aural-transport" (process))
(declare-function emacsvox-aural-enable-relative-rate
                  "emacsvox-aural-transport" (process))
(declare-function emacsvox-aural-enable-structured-timeline
                  "emacsvox-aural-transport" (process))
(declare-function tts--dispatch-playback-marker-event
                  "tts-speak" (process event))
(declare-function tts-stop "tts-speak" (&optional all))

(defvar emacsvox-servers-directory)
(defvar emacsvox-play-program)
(defvar tts-default-speech-rate)
(defvar tts-default-voice)
(defvar tts-notify-process)
(defvar tts-speaker-process)
(defvar tts-speech-rate)
(defvar tts-speech-rate-base)
(defvar tts-speech-rate-step)
(defvar tts-voice-capabilities-function)
(defvar tts-voice-inventory-function)
(defvar tts-voice-inventory-refresh-function)
(defvar tts-voice-configuration-apply-function)
(defvar tts-last-realized-voice-function)
(defvar tts-realized-voice-changed-hook)
(defvar tts--capitalization-presentation-property)

(defgroup omnivox nil
  "Omnivox speech server."
  :group 'tts
  :prefix "omnivox-")

(defcustom omnivox-default-speech-rate 60
  "Default Omnivox speech rate on its zero-to-100 scale."
  :group 'omnivox
  :type 'integer)

(defcustom omnivox-default-voice-id ""
  "Default physical voice identifier for the current Omnivox engine.
An empty string leaves voice selection to the engine.  Use
`omnivox-select-voice' to choose from the voices reported by the server."
  :group 'omnivox
  :type 'string)

(defcustom omnivox-logical-voice-preferences nil
  "Ordered physical selectors for portable Emacs voice names.
Each alist key is a logical voice symbol or string.  Its value is an ordered
list of selectors with one of these forms:

  (exact ENGINE-ID VOICE-ID)
  (engine-default ENGINE-ID)
  (properties :engine ENGINE-ID :language LANGUAGE :gender GENDER)

Properties may omit any key.  A voice without an entry late-binds to the
preferred engine reported by each Omnivox process, or to any available engine
when an older server does not report a preference.  Exact selectors retain
separate engine and native voice IDs, so a native ID may safely contain colons
or backslashes."
  :group 'omnivox
  :type '(alist :key-type (choice symbol string) :value-type sexp))

(defcustom omnivox-logical-voice-languages nil
  "Language tags for logical Omnivox voices.
Each entry maps a logical voice symbol or string to a BCP 47 language string."
  :group 'omnivox
  :type '(alist :key-type (choice symbol string) :value-type string))

(defcustom omnivox-engine-priority-ids nil
  "Default ordered engine IDs for logical voices without stronger routes.

Per-logical-voice selectors remain first.  Distinct engines from this list are
then tried before the process's preferred engine and fallback policy.  A nil
value preserves the server-selected preferred-engine behavior."
  :group 'omnivox
  :type '(repeat string))

(defcustom omnivox-fallback-engine-ids '("espeak")
  "Ordered engine IDs used after a logical voice's explicit selectors fail."
  :group 'omnivox
  :type '(repeat string))

(defcustom omnivox-disabled-engine-ids nil
  "Engine IDs retained in routing order but administratively disabled."
  :group 'omnivox
  :type '(repeat string))

(defcustom omnivox-global-default-selector nil
  "Optional final default selector for every logical Omnivox voice.
The value is nil or one selector in the format documented by
`omnivox-logical-voice-preferences'."
  :group 'omnivox
  :type '(choice (const :tag "None" nil) sexp))

(defcustom omnivox-allow-same-language-fallback t
  "Whether Omnivox may try another same-language voice on an engine."
  :group 'omnivox
  :type 'boolean)

(defvar omnivox-available-voices nil
  "Physical voices most recently discovered from Omnivox.
Each entry has the form (ID NAME LANGUAGE QUALITY).")

(defconst omnivox-control-protocol-version 1
  "Control protocol version supported by this adapter.")

(defconst omnivox-control-event-prefix "__OMNIVOX_CONTROL__ "
  "Prefix of Base64-JSON control events emitted by Omnivox.")

(defconst omnivox-control-max-payload-bytes (* 256 1024)
  "Maximum decoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox-control-max-encoded-bytes 349532
  "Maximum encoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox-marker-event-protocol-versions '(1 2)
  "Marker event protocol versions supported by this adapter.")

(defconst omnivox-marker-event-prefix "__EMACSVOX_MARKER__ "
  "Prefix of Base64-JSON playback marker events emitted by Omnivox.")

(defconst omnivox-marker-max-payload-bytes (* 2 1024 1024)
  "Maximum decoded Omnivox marker event accepted by Emacsvox.")

(defconst omnivox-marker-max-encoded-bytes 2796208
  "Maximum encoded Omnivox marker event accepted by Emacsvox.")

(defconst omnivox--maximum-event-line-bytes
  (+ (length omnivox-marker-event-prefix)
     omnivox-marker-max-encoded-bytes)
  "Maximum incomplete machine-readable output line retained per process.")

(defconst omnivox--control-filter-installed-property
  'omnivox--control-filter-installed
  "Process property recording installation of the control filter.")

(defconst omnivox--control-original-filter-property
  'omnivox--control-original-filter
  "Process property retaining the filter wrapped by Omnivox.")

(defconst omnivox--control-fragment-property 'omnivox--control-fragment
  "Process property retaining an incomplete Omnivox output line.")

(defconst omnivox--control-pending-property 'omnivox--control-pending
  "Process property holding callbacks for outstanding control requests.")

(defconst omnivox--control-capabilities-property
  'omnivox--control-capabilities
  "Process property holding negotiated Omnivox capabilities.")

(defconst omnivox--control-inventory-property 'omnivox--control-inventory
  "Process property holding the latest Omnivox engine inventory.")

(defconst omnivox--control-registration-property
  'omnivox--control-registration
  "Process property holding the latest logical-voice registration result.")

(defconst omnivox--control-routing-policy-property
  'omnivox--control-routing-policy
  "Process property holding the latest applied routing policy.")

(defconst omnivox--control-negotiated-property 'omnivox--control-negotiated
  "Process property preventing duplicate capability negotiation.")

(defvar omnivox--control-request-sequence 0
  "Sequence used to identify Omnivox control requests.")

(defvar omnivox-control-capabilities nil
  "Capabilities most recently reported by the main Omnivox process.")

(defvar omnivox-engine-inventory nil
  "Engine inventory most recently reported by the main Omnivox process.")

(defvar omnivox-engine-inventory-time nil
  "Time at which the main Omnivox inventory was most recently received.")

(defvar omnivox-logical-voice-registration nil
  "Logical-voice result most recently reported by the main Omnivox process.")

(defvar omnivox-routing-policy-registration nil
  "Routing policy most recently reported by the main Omnivox process.")

(defvar omnivox-control-last-error nil
  "Most recent Omnivox control error or malformed event.")

(defvar omnivox-marker-last-error nil
  "Most recent malformed Omnivox playback marker event.")

(defvar omnivox-timeline-last-event nil
  "Most recent validated version 2 timeline event from Omnivox.")

(defvar omnivox-timeline-event-hook nil
  "Hook run with one validated version 2 timeline event argument.")

(defvar omnivox-last-realized-routes (make-hash-table :test #'equal)
  "Last playback-observed route indexed by logical voice ID.")

(defvar omnivox-realized-route-changed-hook nil
  "Hook run with one updated playback-observed logical route.")

(defvar omnivox--utterance-logical-voices (make-hash-table :test #'equal)
  "Bounded diagnostic map from playback utterances to logical voice IDs.")

(defvar omnivox-voice-configuration-last-result nil
  "Most recent terminal complete-configuration apply result.")

(defvar omnivox-voice-configuration-applied-hook nil
  "Hook run with a terminal complete-configuration apply result.")

(defcustom omnivox-voice-configuration-timeout 5
  "Seconds allowed for a complete multi-process configuration apply."
  :group 'omnivox
  :type 'number)

(defvar omnivox--logical-acss-table (make-hash-table :test #'equal)
  "Normalized ACSS styles indexed by logical voice ID.")

(defvar omnivox--logical-registry-generation 0
  "Generation of the current Emacsvox-owned logical voice registry.")

(defvar omnivox--logical-registry-signature nil
  "Last logical voice registry content assigned a generation.")

(defvar omnivox--logical-registration-timer nil
  "Timer coalescing logical voice definitions created in one operation.")

(defun omnivox--encode-control-request (request)
  "Encode control REQUEST as bounded, unwrapped Base64 JSON."
  (let* ((json (json-serialize request))
         (payload (encode-coding-string json 'utf-8 t)))
    (when (> (string-bytes payload) omnivox-control-max-payload-bytes)
      (error "Omnivox control request exceeds %d bytes"
             omnivox-control-max-payload-bytes))
    (base64-encode-string payload t)))

(defun omnivox--decode-control-response (payload)
  "Decode and validate one Base64-JSON control response PAYLOAD."
  (when (> (string-bytes payload) omnivox-control-max-encoded-bytes)
    (error "Encoded Omnivox control response exceeds its size limit"))
  (let ((decoded (base64-decode-string payload)))
    (when (> (string-bytes decoded) omnivox-control-max-payload-bytes)
      (error "Decoded Omnivox control response exceeds its size limit"))
    (json-parse-string
     (decode-coding-string decoded 'utf-8 t)
     :object-type 'plist :array-type 'list
     :null-object nil :false-object nil)))

(defun omnivox--decode-marker-event (payload)
  "Decode and validate one bounded Base64-JSON marker event PAYLOAD."
  (when (> (string-bytes payload) omnivox-marker-max-encoded-bytes)
    (error "Encoded Omnivox marker event exceeds its size limit"))
  (let ((decoded (base64-decode-string payload)))
    (when (> (string-bytes decoded) omnivox-marker-max-payload-bytes)
      (error "Decoded Omnivox marker event exceeds its size limit"))
    (json-parse-string
     (decode-coding-string decoded 'utf-8 t)
     :object-type 'plist :array-type 'list
     :null-object nil :false-object nil)))

(defun omnivox--pending-requests (process)
  "Return the pending control request table for PROCESS."
  (or (process-get process omnivox--control-pending-property)
      (let ((pending (make-hash-table :test #'eql)))
        (process-put process omnivox--control-pending-property pending)
        pending)))

(defun omnivox--send-control-request (process request callback)
  "Send REQUEST to Omnivox PROCESS and register CALLBACK.
CALLBACK receives PROCESS and the decoded response plist."
  (unless (process-live-p process)
    (error "Omnivox speech process is not live"))
  (let* ((identifier (cl-incf omnivox--control-request-sequence))
         (envelope
          (append
           (list :protocol_version omnivox-control-protocol-version
                 :request_id identifier)
           request))
         (pending (omnivox--pending-requests process)))
    (puthash identifier callback pending)
    (condition-case error-data
        (process-send-string
         process
         (format "omnivox_control {%s}\n"
                 (omnivox--encode-control-request envelope)))
      (error
       (remhash identifier pending)
       (signal (car error-data) (cdr error-data))))
    identifier))

(defun omnivox--record-control-error (process response)
  "Record control error RESPONSE from PROCESS without speaking it."
  (setq omnivox-control-last-error
        (list :process process :response response :time (current-time)))
  (message "Omnivox control error: %s"
           (or (plist-get response :message) "malformed response")))

(defun omnivox--dispatch-control-response (process response)
  "Match decoded control RESPONSE to its request on PROCESS."
  (unless (= (or (plist-get response :protocol_version) -1)
             omnivox-control-protocol-version)
    (error "Unsupported Omnivox control response version"))
  (let* ((identifier (plist-get response :request_id))
         (pending (omnivox--pending-requests process))
         (callback (and (integerp identifier) (gethash identifier pending))))
    (when (integerp identifier)
      (remhash identifier pending))
    (cond
     (callback (funcall callback process response))
     ((equal (plist-get response :type) "error")
      (omnivox--record-control-error process response)))))

(defun omnivox--handle-control-line (process line)
  "Handle an Omnivox control event LINE from PROCESS.
Return non-nil when LINE is a control event, including a malformed one."
  (when (string-prefix-p omnivox-control-event-prefix line)
    (condition-case error-data
        (omnivox--dispatch-control-response
         process
         (omnivox--decode-control-response
          (substring line (length omnivox-control-event-prefix))))
      (error
       (setq omnivox-control-last-error
             (list :process process :error error-data :time (current-time)))
       (message "Invalid Omnivox control event: %s"
                (error-message-string error-data))))
    t))

(defun omnivox--logical-voice-name (value)
  "Return VALUE as a stable logical voice string, or nil."
  (cond
   ((stringp value) value)
   ((symbolp value) (symbol-name value))))

(defun omnivox-last-realized-voice (logical-voice)
  "Return the last playback-observed route for LOGICAL-VOICE."
  (copy-tree
   (gethash
    (omnivox--logical-voice-name logical-voice)
    omnivox-last-realized-routes)))

(defun omnivox--utterance-key (process event)
  "Return a diagnostic playback key for PROCESS and marker EVENT."
  (list process
        (plist-get event :dispatch_id)
        (plist-get event :utterance_id)))

(defun omnivox--record-realized-route (process event)
  "Record route or degradation from playback marker EVENT on PROCESS."
  (pcase (plist-get event :type)
    ("utterance_started"
     (when-let* ((logical
                  (omnivox--logical-voice-name
                   (plist-get event :logical_voice_id)))
                 (engine (plist-get event :engine_id)))
       (when (> (hash-table-count omnivox--utterance-logical-voices) 1024)
         (clrhash omnivox--utterance-logical-voices))
       (puthash
        (omnivox--utterance-key process event) logical
        omnivox--utterance-logical-voices)
       (let* ((actual (plist-get event :actual_voice))
              (route
              (list
               :logical-voice logical
               :engine-id (or (and (listp actual)
                                   (plist-get actual :engine_id))
                              engine)
               :voice-id (if (listp actual)
                             (plist-get actual :voice_id)
                           actual)
               :dispatch-id (plist-get event :dispatch_id)
               :utterance-id (plist-get event :utterance_id)
               :process process :time (current-time)
               :degraded-acss nil :degraded-effects nil)))
         (puthash logical route omnivox-last-realized-routes)
         (run-hook-with-args 'omnivox-realized-route-changed-hook
                             (copy-tree route))
         (run-hook-with-args 'tts-realized-voice-changed-hook
                             (copy-tree route)))))
    ("timeline_style_degraded"
     (when-let* ((logical
                  (gethash
                   (omnivox--utterance-key process event)
                   omnivox--utterance-logical-voices))
                 (route (copy-tree
                         (gethash logical omnivox-last-realized-routes))))
       (setq route
             (plist-put route :degraded-acss
                        (copy-sequence
                         (plist-get event :degraded_acss))))
       (setq route
             (plist-put route :degraded-effects
                        (copy-sequence
                         (plist-get event :degraded_effects))))
       (puthash logical route omnivox-last-realized-routes)
       (run-hook-with-args 'omnivox-realized-route-changed-hook
                           (copy-tree route))
       (run-hook-with-args 'tts-realized-voice-changed-hook
                           (copy-tree route))))))

(defun omnivox--handle-marker-line (process line)
  "Handle an Omnivox playback marker LINE from PROCESS.
Return non-nil for every marker-prefixed line, including malformed records."
  (when (string-prefix-p omnivox-marker-event-prefix line)
    (condition-case error-data
        (let* ((event
                (omnivox--decode-marker-event
                 (substring line (length omnivox-marker-event-prefix))))
               (version (plist-get event :protocol_version))
               (identifier (plist-get event :dispatch_id))
               (sequence (plist-get event :sequence))
               (type (plist-get event :type)))
          (unless
              (and
               (memq version omnivox-marker-event-protocol-versions)
               (integerp identifier) (> identifier 0)
               (integerp sequence) (> sequence 0)
               (stringp type))
            (error "Invalid Omnivox marker event envelope"))
          (when (member type '("utterance_started"
                               "timeline_style_degraded"))
            (omnivox--record-realized-route process event))
          (when
              (member
               type
               '("semantic_event_reached"
                 "timeline_action_resolved"
                 "timeline_style_degraded"))
            (setq omnivox-timeline-last-event
                  (list :process process :event (copy-tree event)
                        :time (current-time)))
            (run-hook-with-args 'omnivox-timeline-event-hook event))
          (when
              (member
               type
               '("utterance_started" "marker_reached"
                 "semantic_event_reached"
                 "timeline_action_resolved"
                 "timeline_style_degraded"))
            (tts--dispatch-playback-marker-event process event)))
      (error
       (setq omnivox-marker-last-error
             (list :process process :error error-data :time (current-time)))
       (message "Invalid Omnivox marker event: %s"
                (error-message-string error-data))))
    t))

(defun omnivox--forward-process-output (process output)
  "Forward ordinary PROCESS OUTPUT to the filter wrapped by Omnivox."
  (when-let* ((filter
               (process-get
                process omnivox--control-original-filter-property)))
    (unless (eq filter #'omnivox--control-process-filter)
      (funcall filter process output))))

(defun omnivox--control-process-filter (process output)
  "Extract Omnivox control events from PROCESS OUTPUT."
  (let ((pending
         (concat
          (or (process-get process omnivox--control-fragment-property) "")
          output))
        line-end)
    (while (setq line-end (string-search "\n" pending))
      (let ((line (string-trim-right (substring pending 0 line-end) "\r")))
        (unless
            (or
             (omnivox--handle-control-line process line)
             (omnivox--handle-marker-line process line))
          (omnivox--forward-process-output process (concat line "\n"))))
      (setq pending (substring pending (1+ line-end))))
    (if (> (string-bytes pending) omnivox--maximum-event-line-bytes)
        (progn
          (setq omnivox-marker-last-error
                (list
                 :process process :error 'oversized-fragment
                 :time (current-time)))
          (process-put process omnivox--control-fragment-property "")
          (message "Discarded oversized Omnivox output fragment"))
      (process-put process omnivox--control-fragment-property pending))))

(defun omnivox--install-control-filter (process)
  "Install bounded control-event filtering on Omnivox PROCESS once."
  (unless (process-get process omnivox--control-filter-installed-property)
    (process-put process omnivox--control-filter-installed-property t)
    (process-put
     process omnivox--control-original-filter-property (process-filter process))
    (process-put process omnivox--control-fragment-property "")
    (set-process-filter process #'omnivox--control-process-filter)))

(defun omnivox--logical-voice-id (name)
  "Return the stable logical voice ID for symbol or string NAME."
  (cond
   ((symbolp name) (symbol-name name))
   ((stringp name) name)
   (t (error "Invalid logical Omnivox voice name: %S" name))))

(defun omnivox--effective-logical-voice-id (name)
  "Return the logical ID emitted when Emacs personality NAME is spoken.
Follow the same single symbol indirection as `tts-speak-using-voice'."
  (omnivox--logical-voice-id
   (if (and (symbolp name)
            (boundp name)
            (let ((value (symbol-value name)))
              (or (symbolp value) (stringp value))))
       (symbol-value name)
     name)))

(defun omnivox--logical-voice-directive (name)
  "Return the queued routing directive for logical voice NAME."
  (let ((id (omnivox--logical-voice-id name)))
    (unless (and (<= (string-bytes id) 128)
                 (string-match-p "\\`[A-Za-z0-9_.-]+\\'" id))
      (error "Invalid logical Omnivox voice ID: %S" id))
    (format "[[logical_voice %s]]" id)))

(defun omnivox--logical-setting (id settings)
  "Return logical voice ID's value from SETTINGS.
Symbol and string keys with the same printed name are equivalent."
  (cl-loop
   for (name . value) in settings
   when (equal id (omnivox--effective-logical-voice-id name))
   return value))

(defun omnivox--required-selector-id (value kind)
  "Validate and return selector ID VALUE described by KIND."
  (unless (and (stringp value) (not (string-empty-p value)))
    (error "Omnivox %s must be a nonempty string" kind))
  value)

(defun omnivox--selector-json (selector)
  "Convert one portable SELECTOR form to its JSON plist representation."
  (pcase selector
    (`(exact ,engine-id ,voice-id)
     (list
      :kind "exact"
      :engine_id (omnivox--required-selector-id engine-id "engine ID")
      :voice_id (omnivox--required-selector-id voice-id "voice ID")))
    (`(engine-default ,engine-id)
     (list
      :kind "engine_default"
      :engine_id (omnivox--required-selector-id engine-id "engine ID")))
    (`(properties . ,properties)
     (unless (proper-list-p properties)
       (error "Invalid Omnivox property selector: %S" selector))
     (let ((engine-id (plist-get properties :engine))
           (language (plist-get properties :language))
           (gender (plist-get properties :gender)))
       (when engine-id
         (omnivox--required-selector-id engine-id "engine ID"))
       (when (and language (not (stringp language)))
         (error "Omnivox selector language must be a string"))
       (when (and gender (not (or (symbolp gender) (stringp gender))))
         (error "Omnivox selector gender must be a symbol or string"))
       (list
        :kind "properties"
        :engine_id (or engine-id :null)
        :language (or language :null)
        :gender
        (if gender
            (downcase
             (if (symbolp gender) (symbol-name gender) gender))
          :null))))
    (_ (error "Invalid Omnivox voice selector: %S" selector))))

(defun omnivox--preview-selector-json (selector)
  "Convert normalized generic preview SELECTOR to Omnivox JSON data."
  (let ((kind (plist-get selector :kind)))
    (when (stringp kind) (setq kind (intern kind)))
    (pcase kind
      ('exact
       (omnivox--selector-json
        (list 'exact
              (plist-get selector :engine-id)
              (plist-get selector :voice-id))))
      ('engine-default
       (omnivox--selector-json
        (list 'engine-default (plist-get selector :engine-id))))
      ('properties
       (omnivox--selector-json
        (list 'properties
              :engine (plist-get selector :engine-id)
              :language (plist-get selector :language)
              :gender (plist-get selector :gender))))
      (_ (error "Invalid generic Omnivox preview selector: %S" selector)))))

(defun omnivox--preview-acss-json (acss)
  "Convert normalized generic ACSS plist to Omnivox JSON fields."
  (let (result)
    (dolist
        (mapping
         '((:rate . :rate)
           (:average-pitch . :average_pitch)
           (:pitch-range . :pitch_range)
           (:stress . :stress)
           (:richness . :richness)
           (:volume . :volume)))
      (when (plist-member acss (car mapping))
        (setq result
              (plist-put result (cdr mapping)
                         (plist-get acss (car mapping))))))
    (or result (make-hash-table :test #'equal))))

(defun omnivox--preview-effects-json (effects)
  "Convert normalized generic EFFECTS plist to Omnivox JSON fields."
  (let (result)
    (dolist
        (mapping
         '((:gain . :gain)
           (:low-pass . :low_pass)
           (:high-pass . :high_pass)
           (:pan . :pan)
           (:reverb . :reverb)
           (:echo . :echo)))
      (when (plist-member effects (car mapping))
        (setq result
              (plist-put result (cdr mapping)
                         (plist-get effects (car mapping))))))
    (or result (make-hash-table :test #'equal))))

(defun omnivox--preview-dimension-symbol (value)
  "Return generic dimension symbol for Omnivox wire VALUE."
  (intern (replace-regexp-in-string "_" "-" (format "%s" value))))

(defun omnivox--normalize-preview-response
    (entry response effects-supported rate-supported)
  "Normalize preview RESPONSE for ENTRY and EFFECTS-SUPPORTED status."
  (if (not (equal (plist-get response :type) "preview_completed"))
      (list
       :status 'failed :completion-guarantee 'playback
       :requested (copy-tree (plist-get entry :selector))
       :realized nil
       :degraded-acss
       (append
        (tts--voice-preview-dimensions (plist-get entry :acss))
        (and
         (numberp (plist-get entry :rate-offset))
         (not (zerop (plist-get entry :rate-offset)))
         '(rate-offset)))
       :degraded-effects
       (tts--voice-preview-dimensions (plist-get entry :effects))
       :message (or (plist-get response :message)
                    "Omnivox returned an invalid preview response"))
    (let ((realized (plist-get response :realized)))
      (list
       :status (intern (or (plist-get response :status) "failed"))
       :completion-guarantee 'playback
       :requested (copy-tree (plist-get entry :selector))
       :realized
       (and realized
            (list :engine-id (plist-get realized :engine_id)
                  :voice-id (plist-get realized :voice_id)))
       :degraded-acss
       (let ((degraded
              (mapcar #'omnivox--preview-dimension-symbol
                      (plist-get response :degraded_acss))))
         (when (and
                (numberp (plist-get entry :rate-offset))
                (not (zerop (plist-get entry :rate-offset))))
           (if rate-supported
               (when (memq 'rate degraded)
                 (setq degraded
                       (cons 'rate-offset (delq 'rate degraded))))
             (push 'rate-offset degraded)))
         degraded)
       :degraded-effects
       (if effects-supported
           (mapcar #'omnivox--preview-dimension-symbol
                   (plist-get response :degraded_effects))
         (tts--voice-preview-dimensions (plist-get entry :effects)))
       :message (plist-get response :message)))))

(defun omnivox--preview-one (entry callback)
  "Preview one normalized ENTRY and call CALLBACK after playback."
  (unless (and
           (process-live-p tts-speaker-process)
           (omnivox--process-supports-p
            tts-speaker-process "exact_voice_preview"))
    (error "The live Omnivox server does not support transactional preview"))
  (let ((effects-supported
         (omnivox--process-supports-p
          tts-speaker-process "post_synthesis_effects_v1"))
        (rate-supported
         (omnivox--process-supports-p
          tts-speaker-process "relative_rate_v1")))
    (tts-stop)
    (omnivox--send-control-request
     tts-speaker-process
     (append
      (list
       :type "preview"
       :text (plist-get entry :text)
       :selector
       (omnivox--preview-selector-json (plist-get entry :selector))
       :language (or (plist-get entry :language) :null)
       :acss (omnivox--preview-acss-json (plist-get entry :acss)))
      (when (and
             rate-supported
             (numberp (plist-get entry :rate-offset))
             (not (zerop (plist-get entry :rate-offset))))
        (list :rate_offset (plist-get entry :rate-offset)))
      (when effects-supported
        (list :effects
              (omnivox--preview-effects-json
               (plist-get entry :effects)))))
     (lambda (_process response)
       (funcall callback
                (omnivox--normalize-preview-response
                 entry response effects-supported rate-supported))))))

(defun omnivox-preview-voice-sequence (entries callback)
  "Preview Omnivox ENTRIES in order and call CALLBACK after playback."
  (let ((remaining (copy-tree entries))
        results)
    (cl-labels
        ((next
          ()
          (if (null remaining)
              (tts--voice-preview-callback
               callback
               (list :status 'completed :completion-guarantee 'playback
                     :results (nreverse results)))
            (let ((entry (pop remaining)))
              (omnivox--preview-one
               entry
               (lambda (result)
                 (push result results)
                 (if (eq (plist-get result :status) 'cancelled)
                     (tts--voice-preview-callback
                      callback
                      (list :status 'cancelled
                            :completion-guarantee 'playback
                            :results (nreverse results)))
                   (next))))))))
      (next))))

(defun omnivox--logical-voice-ids ()
  "Return every defined or explicitly configured logical voice ID."
  (let (ids)
    (maphash (lambda (id _style) (push id ids))
             omnivox--logical-acss-table)
    (dolist (entry omnivox-logical-voice-preferences)
      (push (omnivox--effective-logical-voice-id (car entry)) ids))
    (dolist (entry omnivox-logical-voice-languages)
      (push (omnivox--effective-logical-voice-id (car entry)) ids))
    (sort (delete-dups ids) #'string-lessp)))

(defun omnivox--selector-engine-id (selector)
  "Return the requested engine ID from Omnivox SELECTOR, or nil."
  (pcase selector
    (`(exact ,engine-id ,_) engine-id)
    (`(engine-default ,engine-id) engine-id)
    (`(properties . ,properties) (plist-get properties :engine))))

(defun omnivox--selectors-with-engine-priority (selectors)
  "Append distinct configured engine priorities to SELECTORS."
  (let ((result (copy-tree selectors))
        (used (delq nil (mapcar #'omnivox--selector-engine-id selectors))))
    (dolist (engine-id omnivox-engine-priority-ids)
      (omnivox--required-selector-id engine-id "priority engine ID")
      (unless (member engine-id used)
        (setq result (append result `((engine-default ,engine-id))))
        (push engine-id used)))
    result))

(defun omnivox--logical-definition-json
    (id &optional preferred-engine-id runtime-routing-policy)
  "Return the protocol definition for logical voice ID.
Use PREFERRED-ENGINE-ID for an otherwise unconfigured voice.
When RUNTIME-ROUTING-POLICY is non-nil, do not duplicate global engine order
inside this logical definition."
  (let* ((configured
          (omnivox--logical-setting id omnivox-logical-voice-preferences))
         (selectors
          (or
           (if runtime-routing-policy
               (copy-tree configured)
             (omnivox--selectors-with-engine-priority configured))
           (if preferred-engine-id
               `((engine-default ,preferred-engine-id))
             '((properties)))))
         (language
          (omnivox--logical-setting id omnivox-logical-voice-languages)))
    (when (and language (not (stringp language)))
      (error "Language for logical Omnivox voice %s must be a string" id))
    (list
     :id id
     :language (or language :null)
     :preferences (vconcat (mapcar #'omnivox--selector-json selectors))
     :acss (copy-tree (gethash id omnivox--logical-acss-table)))))

(defun omnivox--fallback-policy-json (&optional runtime-routing-policy)
  "Return the configured logical voice fallback policy as JSON data."
  (dolist (engine-id omnivox-fallback-engine-ids)
    (omnivox--required-selector-id engine-id "fallback engine ID"))
  (list
   :allow_same_language_on_requested_engine
   (if omnivox-allow-same-language-fallback t :false)
   :global_default
   (if omnivox-global-default-selector
       (omnivox--selector-json omnivox-global-default-selector)
     :null)
   :fallback_engines
   (if runtime-routing-policy [] (vconcat omnivox-fallback-engine-ids))))

(defun omnivox--logical-registry-content
    (&optional preferred-engine-id runtime-routing-policy)
  "Return complete logical registry content for PREFERRED-ENGINE-ID.
RUNTIME-ROUTING-POLICY keeps global order out of logical definitions."
  (let* ((definitions
          (vconcat
           (mapcar (lambda (id)
                     (omnivox--logical-definition-json
                      id preferred-engine-id runtime-routing-policy))
                   (omnivox--logical-voice-ids))))
         (fallback-policy
          (omnivox--fallback-policy-json runtime-routing-policy)))
    (list
     :definitions definitions
     :fallback_policy fallback-policy)))

(defun omnivox--update-logical-registry-generation (signature)
  "Advance the logical registry generation when SIGNATURE changed."
  (unless (equal signature omnivox--logical-registry-signature)
    (setq omnivox--logical-registry-signature (copy-tree signature))
    (cl-incf omnivox--logical-registry-generation)))

(defun omnivox--logical-registry-snapshot (&optional preferred-engine-id)
  "Return the current logical registry for PREFERRED-ENGINE-ID."
  (let ((content
         (omnivox--logical-registry-content preferred-engine-id)))
    (omnivox--update-logical-registry-generation (list content))
    (append
     (list :registry_generation omnivox--logical-registry-generation)
     content)))

(defun omnivox--process-supports-p (process feature)
  "Return non-nil when Omnivox PROCESS advertises FEATURE."
  (member
   feature
   (plist-get
    (process-get process omnivox--control-capabilities-property)
    :features)))

(defun omnivox--routing-engine-list (values description)
  "Validate and copy ordered engine VALUES described by DESCRIPTION."
  (unless (proper-list-p values)
    (error "Omnivox %s must be a list" description))
  (let (seen result)
    (dolist (engine-id values)
      (omnivox--required-selector-id engine-id description)
      (when (member engine-id seen)
        (error "Omnivox %s contains duplicate engine %s"
               description engine-id))
      (push engine-id seen)
      (push engine-id result))
    (nreverse result)))

(defun omnivox--routing-policy-content (process)
  "Return desired global routing policy for Omnivox PROCESS."
  (let* ((inventory
          (process-get process omnivox--control-inventory-property))
         (startup-preferred (plist-get inventory :preferred_engine_id))
         (preferred
          (or omnivox-engine-priority-ids
              (and (stringp startup-preferred)
                   (not (string-empty-p startup-preferred))
                   (list startup-preferred)))))
    (list
     :preferred_engine_ids
     (vconcat
      (omnivox--routing-engine-list preferred "preferred engine order"))
     :fallback_engine_ids
     (vconcat
      (omnivox--routing-engine-list
       omnivox-fallback-engine-ids "fallback engine order"))
     :disabled_engine_ids
     (vconcat
      (omnivox--routing-engine-list
       omnivox-disabled-engine-ids "disabled engine list")))))

(defun omnivox--routing-policy-lists (policy)
  "Return comparable ordered lists from wire POLICY."
  (list
   (append (plist-get policy :preferred_engine_ids) nil)
   (append (plist-get policy :fallback_engine_ids) nil)
   (append (plist-get policy :disabled_engine_ids) nil)))

(defun omnivox--routing-registration-policy (registration)
  "Return policy content nested in REGISTRATION, or nil."
  (and (listp registration) (plist-get registration :policy)))

(defun omnivox--process-routing-registration (process)
  "Return the newest routing registration known for PROCESS."
  (or
   (process-get process omnivox--control-routing-policy-property)
   (plist-get
    (process-get process omnivox--control-inventory-property)
    :routing_policy)))

(defun omnivox--process-routing-policy-current-p (process)
  "Return non-nil when PROCESS has the desired global routing policy."
  (let ((registered
         (omnivox--routing-registration-policy
          (omnivox--process-routing-registration process)))
        (desired (omnivox--routing-policy-content process)))
    (and registered
         (equal (omnivox--routing-policy-lists registered)
                (omnivox--routing-policy-lists desired)))))

(defun omnivox--routing-policy-generation (process)
  "Return the last routing-policy generation reported by PROCESS."
  (or
   (plist-get
    (omnivox--process-routing-registration process)
    :routing_policy_generation)
   0))

(defun omnivox--store-routing-policy-response (process response)
  "Store successful routing-policy RESPONSE for PROCESS."
  (let ((registration (plist-get response :routing_policy))
        (inventory
         (copy-tree
          (process-get process omnivox--control-inventory-property))))
    (process-put process omnivox--control-routing-policy-property registration)
    (when inventory
      (setq inventory
            (plist-put inventory :routing_policy (copy-tree registration)))
      (when (plist-member response :inventory_generation)
        (setq inventory
              (plist-put
               inventory :inventory_generation
               (plist-get response :inventory_generation))))
      (process-put process omnivox--control-inventory-property inventory))
    (when-let* ((logical (plist-get response :logical_voices)))
      (process-put process omnivox--control-registration-property logical)
      (when (eq process tts-speaker-process)
        (setq omnivox-logical-voice-registration (copy-tree logical))))
    (when (eq process tts-speaker-process)
      (setq omnivox-routing-policy-registration (copy-tree registration)
            omnivox-engine-inventory inventory
            omnivox-engine-inventory-time (current-time)))))

(defun omnivox--handle-routing-policy-response (process response)
  "Store routing policy RESPONSE and continue logical registration."
  (if (equal (plist-get response :type) "routing_policy_applied")
      (progn
        (omnivox--store-routing-policy-response process response)
        (if (omnivox--process-routing-policy-current-p process)
            (omnivox-register-logical-voices)
          (omnivox--set-process-routing-policy process)))
    (omnivox--record-control-error process response)
    (when (and
           (member (plist-get response :code)
                   '("stale_generation" "generation_conflict"))
           (omnivox--process-supports-p process "engine_inventory"))
      (omnivox--send-control-request
       process '(:type "inventory") #'omnivox--handle-inventory-response))))

(defun omnivox--set-process-routing-policy (process)
  "Apply desired routing policy to one negotiated Omnivox PROCESS."
  (let ((content (omnivox--routing-policy-content process)))
    (if (omnivox--process-routing-policy-current-p process)
        (progn
          (process-put
           process omnivox--control-routing-policy-property
           (omnivox--process-routing-registration process))
          nil)
      (omnivox--send-control-request
       process
       (append
        (list
         :type "set_routing_policy"
         :routing_policy_generation
         (1+ (omnivox--routing-policy-generation process)))
        content)
       #'omnivox--handle-routing-policy-response))))

(defun omnivox-set-routing-policy ()
  "Apply global engine order and disablement to live Omnivox processes.
Return the number of processes sent a generation-safe policy replacement."
  (interactive)
  (let ((processes
         (cl-remove-if-not
          (lambda (process)
            (and
             (process-live-p process)
             (omnivox--process-supports-p process "runtime_routing_policy")
             (process-get process omnivox--control-inventory-property)))
          (delete-dups (list tts-speaker-process tts-notify-process))))
        (sent 0))
    (dolist (process processes)
      (when (omnivox--set-process-routing-policy process)
        (cl-incf sent)))
    (when (called-interactively-p 'interactive)
      (if processes
          (message "Sent Omnivox routing policy to %d process%s"
                   sent (if (= sent 1) "" "es"))
        (user-error "No live Omnivox process supports runtime routing policy")))
    sent))

(defun omnivox--handle-registration-response (process response)
  "Store logical voice registration RESPONSE received from PROCESS."
  (if (equal (plist-get response :type) "logical_voices_registered")
      (progn
        (process-put process omnivox--control-registration-property response)
        (when (eq process tts-speaker-process)
          (setq omnivox-logical-voice-registration response)))
    (omnivox--record-control-error process response)))

(defun omnivox--registration-processes ()
  "Return live processes ready for logical voice registration."
  (cl-remove-if-not
   (lambda (process)
     (and (process-live-p process)
          (omnivox--process-supports-p
           process "logical_voice_registration")
          (or (not (omnivox--process-supports-p process "engine_inventory"))
              (process-get process omnivox--control-inventory-property))
          (or
           (not (omnivox--process-supports-p
                 process "runtime_routing_policy"))
           (omnivox--process-routing-policy-current-p process))))
   (delete-dups (list tts-speaker-process tts-notify-process))))

(defun omnivox--process-logical-registry-content (process)
  "Return logical registry content late-bound for Omnivox PROCESS."
  (let* ((inventory
          (process-get process omnivox--control-inventory-property))
         (runtime-routing-policy
          (omnivox--process-supports-p process "runtime_routing_policy"))
         (preferred-engine-id
          (plist-get inventory :preferred_engine_id)))
    (omnivox--logical-registry-content
     (and (not runtime-routing-policy)
          (stringp preferred-engine-id)
          (not (string-empty-p preferred-engine-id))
          preferred-engine-id)
     runtime-routing-policy)))

(defun omnivox-register-logical-voices ()
  "Register all Emacsvox logical voices with live Omnivox processes.
Return the number of processes sent the atomic registry replacement."
  (interactive)
  (let* ((processes (omnivox--registration-processes))
         (registrations
          (mapcar
           (lambda (process)
             (cons process
                   (omnivox--process-logical-registry-content process)))
           processes)))
    (omnivox--update-logical-registry-generation
     (mapcar #'cdr registrations))
    (dolist (registration registrations)
      (omnivox--send-control-request
       (car registration)
       (append
        (list :type "register_logical_voices"
              :registry_generation omnivox--logical-registry-generation)
        (cdr registration))
       #'omnivox--handle-registration-response))
    (when (and (called-interactively-p 'interactive) (null processes))
      (user-error "No live Omnivox process supports logical voice registration"))
    (when (called-interactively-p 'interactive)
      (message "Sent logical voice generation %d to %d Omnivox process%s"
               omnivox--logical-registry-generation
               (length processes) (if (= (length processes) 1) "" "es")))
    (length processes)))

(defun omnivox--voice-configuration-processes ()
  "Return every distinct live process targeted by voice configuration."
  (cl-remove-if-not
   (lambda (process)
     (process-live-p process))
   (delete-dups (list tts-speaker-process tts-notify-process))))

(defun omnivox--voice-configuration-process-role (process)
  "Return the speech-stream role owned by PROCESS."
  (cond
   ((and (eq process tts-speaker-process)
         (eq process tts-notify-process))
    'speaker-and-notification)
   ((eq process tts-speaker-process) 'speaker)
   ((eq process tts-notify-process) 'notification)
   (t 'speech)))

(defun omnivox--voice-configuration-result
    (process status &rest properties)
  "Return one terminal configuration STATUS for PROCESS and PROPERTIES."
  (append
   (list :process process
         :process-name (and (processp process) (process-name process))
         :role (omnivox--voice-configuration-process-role process)
         :status status)
   properties))

(defun omnivox--publish-voice-configuration-result (result callback)
  "Publish terminal configuration RESULT and safely call CALLBACK."
  (setq omnivox-voice-configuration-last-result (copy-tree result))
  (run-hook-with-args 'omnivox-voice-configuration-applied-hook
                      (copy-tree result))
  (when (functionp callback)
    (condition-case error-data
        (funcall callback (copy-tree result))
      (error
       (message "Omnivox configuration callback failed: %s"
                (error-message-string error-data)))))
  result)

(defun omnivox-apply-voice-configuration (&optional callback)
  "Apply routing policy and one logical registry generation to every stream.

CALLBACK receives one terminal aggregate with a result for each distinct live
speaker or notification process.  A process policy is acknowledged before its
logical registry is replaced, so partial failure is explicit and retryable."
  (let* ((processes (omnivox--voice-configuration-processes))
         (registrations
          (mapcar
           (lambda (process)
             (cons process
                   (omnivox--process-logical-registry-content process)))
           processes)))
    (omnivox--update-logical-registry-generation
     (mapcar #'cdr registrations))
    (if (null processes)
        (omnivox--publish-voice-configuration-result
         (list :status 'failed :adapter 'omnivox
               :registry-generation omnivox--logical-registry-generation
               :code 'no-supported-process :processes nil
               :time (current-time))
         callback)
      (let ((pending (make-hash-table :test #'eq))
            results timer done)
        (dolist (process processes) (puthash process t pending))
        (cl-labels
            ((complete
              ()
              (unless done
                (setq done t)
                (when (timerp timer) (cancel-timer timer))
                (let* ((ordered (nreverse results))
                       (applied
                        (cl-count 'applied ordered
                                  :key (lambda (result)
                                         (plist-get result :status))))
                       (status
                        (cond
                         ((= applied (length ordered)) 'applied)
                         ((zerop applied) 'failed)
                         (t 'partial))))
                  (omnivox--publish-voice-configuration-result
                   (list
                    :status status :adapter 'omnivox
                    :registry-generation omnivox--logical-registry-generation
                    :processes ordered :time (current-time))
                   callback))))
             (finish
              (process result)
              (when (gethash process pending)
                (remhash process pending)
                (push result results)
                (when (zerop (hash-table-count pending)) (complete))))
             (registration-response
              (process response)
              (if (equal (plist-get response :type)
                         "logical_voices_registered")
                  (progn
                    (omnivox--handle-registration-response process response)
                    (finish
                     process
                     (omnivox--voice-configuration-result
                      process 'applied
                      :routing-policy
                      (copy-tree
                       (omnivox--process-routing-registration process))
                      :registration
                      (copy-tree (plist-get response :registration)))))
                (omnivox--record-control-error process response)
                (finish
                 process
                 (omnivox--voice-configuration-result
                  process 'failed :phase 'logical-registration
                  :response (copy-tree response)))))
             (register
              (process)
              (omnivox--send-control-request
               process
               (append
                (list :type "register_logical_voices"
                      :registry_generation
                      omnivox--logical-registry-generation)
                (cdr (assq process registrations)))
               #'registration-response))
             (policy-response
              (process response)
              (if (equal (plist-get response :type)
                         "routing_policy_applied")
                  (progn
                    (omnivox--store-routing-policy-response process response)
                    (if (omnivox--process-routing-policy-current-p process)
                        (register process)
                      (finish
                       process
                       (omnivox--voice-configuration-result
                        process 'failed :phase 'routing-policy
                        :code 'policy-mismatch
                        :response (copy-tree response)))))
                (omnivox--record-control-error process response)
                (finish
                 process
                 (omnivox--voice-configuration-result
                  process 'failed :phase 'routing-policy
                  :response (copy-tree response)))))
             (start
              (process)
              (condition-case error-data
                  (cond
                   ((not
                     (omnivox--process-supports-p
                      process "logical_voice_registration"))
                    (finish
                     process
                     (omnivox--voice-configuration-result
                      process 'failed :phase 'negotiation
                      :code 'logical-registration-unsupported)))
                   ((and
                     (omnivox--process-supports-p process "engine_inventory")
                     (not
                      (process-get
                       process omnivox--control-inventory-property)))
                    (finish
                     process
                     (omnivox--voice-configuration-result
                      process 'failed :phase 'inventory
                      :code 'inventory-not-ready)))
                   ((and
                     (omnivox--process-supports-p
                      process "runtime_routing_policy")
                     (not
                      (omnivox--process-routing-policy-current-p process)))
                    (omnivox--send-control-request
                     process
                     (append
                      (list
                       :type "set_routing_policy"
                       :routing_policy_generation
                       (1+ (omnivox--routing-policy-generation process)))
                      (omnivox--routing-policy-content process))
                     #'policy-response))
                   (t (register process)))
                (error
                 (finish
                  process
                  (omnivox--voice-configuration-result
                   process 'failed :phase 'submission :condition error-data)))))
             (timeout
              ()
              (let (expired)
                (maphash (lambda (process _) (push process expired)) pending)
                (dolist (process expired)
                  (finish
                   process
                   (omnivox--voice-configuration-result
                    process 'failed :phase 'timeout :code 'timeout))))))
          (setq timer
                (run-at-time omnivox-voice-configuration-timeout nil #'timeout))
          (dolist (process processes) (start process)))
        (length processes)))))

(defun omnivox--run-scheduled-registration ()
  "Send a coalesced logical voice registry update."
  (setq omnivox--logical-registration-timer nil)
  (condition-case error-data
      (omnivox-register-logical-voices)
    (error
     (setq omnivox-control-last-error
           (list :error error-data :time (current-time)))
     (message "Could not register Omnivox logical voices: %s"
              (error-message-string error-data)))))

(defun omnivox--schedule-logical-registration ()
  "Coalesce logical voice changes into one registry replacement."
  (when (and (omnivox--registration-processes)
             (not (timerp omnivox--logical-registration-timer)))
    (setq omnivox--logical-registration-timer
          (run-at-time 0 nil #'omnivox--run-scheduled-registration))))

(defun omnivox--handle-inventory-response (process response)
  "Store an inventory RESPONSE received from PROCESS."
  (if (equal (plist-get response :type) "inventory")
      (progn
        (process-put process omnivox--control-inventory-property response)
        (when (eq process tts-speaker-process)
          (setq omnivox-engine-inventory response
                omnivox-engine-inventory-time (current-time)
                omnivox-routing-policy-registration
                (copy-tree (plist-get response :routing_policy))))
        (if (omnivox--process-supports-p process "runtime_routing_policy")
            (if (omnivox--set-process-routing-policy process)
                nil
              (omnivox-register-logical-voices))
          (when (omnivox--process-supports-p
                 process "logical_voice_registration")
            (omnivox-register-logical-voices))))
    (omnivox--record-control-error process response)))

(defun omnivox--handle-capabilities-response (process response)
  "Store capability RESPONSE from PROCESS and request its inventory."
  (if (not (equal (plist-get response :type) "capabilities"))
      (omnivox--record-control-error process response)
    (process-put process omnivox--control-capabilities-property response)
    (process-put
     process tts--tracked-playback-completion-property
     (and
      (member "tracked_playback_completion"
              (plist-get response :features))
      t))
    (process-put
     process tts--marker-playback-events-property
     (and
      (or
       (member "playback_marker_events_v1"
               (plist-get response :features))
       (member "playback_marker_events_v2"
               (plist-get response :features)))
      t))
    (process-put
     process tts--capitalization-presentation-property
     (and
      (member "capitalization_presentation_v1"
              (plist-get response :features))
      t))
    (when (member "emacsvox_tx" (plist-get response :features))
      (emacsvox-aural-enable-framed-delivery process))
    (when (member "presentation_timeline_v1" (plist-get response :features))
      (emacsvox-aural-enable-structured-timeline process))
    (when (member "relative_rate_v1" (plist-get response :features))
      (emacsvox-aural-enable-relative-rate process))
    (when (eq process tts-speaker-process)
      (setq omnivox-control-capabilities response))
    (if (member "engine_inventory" (plist-get response :features))
        (omnivox--send-control-request
         process '(:type "inventory") #'omnivox--handle-inventory-response)
      (when (member "logical_voice_registration"
                    (plist-get response :features))
        (omnivox-register-logical-voices)))))

(defun omnivox--negotiate-process (process)
  "Start capability negotiation for one live Omnivox PROCESS."
  (when (and (process-live-p process)
             (not (process-get process omnivox--control-negotiated-property)))
    (process-put process omnivox--control-negotiated-property t)
    (omnivox--install-control-filter process)
    (condition-case error-data
        (omnivox--send-control-request
         process '(:type "capabilities")
         #'omnivox--handle-capabilities-response)
      (error
       (setq omnivox-control-last-error
             (list :process process :error error-data :time (current-time)))
       (message "Could not negotiate Omnivox control protocol: %s"
                (error-message-string error-data))))))

(defun omnivox--negotiate-processes ()
  "Negotiate capabilities on all distinct live Omnivox processes."
  (dolist (process (delete-dups (list tts-speaker-process tts-notify-process)))
    (when (process-live-p process)
      (omnivox--negotiate-process process))))

(defun omnivox--server-program ()
  "Return the Omnivox server program used for discovery, or nil."
  (let ((server (expand-file-name "omnivox" emacsvox-servers-directory)))
    (cond
     ((file-executable-p server) server)
     ((executable-find "omnivox")))))

(defun omnivox--voice-entry-p (entry)
  "Return non-nil when ENTRY is a valid discovered voice record."
  (and (listp entry)
       (= (length entry) 4)
       (cl-every #'stringp entry)))

(defun omnivox--parse-voices (output)
  "Parse and validate Omnivox voice discovery OUTPUT."
  (condition-case error-data
      (let* ((parsed (read-from-string output))
             (voices (car parsed))
             (remainder (substring output (cdr parsed))))
        (unless (string-empty-p (string-trim remainder))
          (error "Unexpected data after voice list"))
        (unless (and (listp voices)
                     (cl-every #'omnivox--voice-entry-p voices))
          (error "Invalid Omnivox voice list"))
        voices)
    (error
     (error "Could not parse Omnivox voices: %s"
            (error-message-string error-data)))))

(defun omnivox-query-voices ()
  "Return physical voices reported by the Omnivox executable.
Signal an error if discovery cannot run or returns malformed data."
  (let ((program (omnivox--server-program)))
    (unless program
      (error "Could not find the Omnivox server executable"))
    (with-temp-buffer
      (let ((status
             (process-file program nil t nil "--list-voices-alist")))
        (unless (and (integerp status) (zerop status))
          (error "Omnivox voice discovery failed%s"
                 (if (string-empty-p (string-trim (buffer-string)))
                     ""
                   (format ": %s" (string-trim (buffer-string))))))
        (omnivox--parse-voices (buffer-string))))))

(defun omnivox-refresh-voices ()
  "Refresh and return the physical voices available from Omnivox."
  (interactive)
  (setq omnivox-available-voices (omnivox-query-voices))
  (when (called-interactively-p 'interactive)
    (message "Found %d Omnivox voices" (length omnivox-available-voices)))
  omnivox-available-voices)

(defun omnivox--send-state-command (command)
  "Send Omnivox state COMMAND to the live speaker processes.
Return the number of distinct processes that received the command."
  (let (sent)
    (dolist (process (list tts-speaker-process tts-notify-process))
      (when (and (process-live-p process) (not (memq process sent)))
        (process-send-string process (concat command "\n"))
        (push process sent)))
    (length sent)))

(defun omnivox-set-voice (voice-id)
  "Select physical Omnivox VOICE-ID for speaker and notification speech."
  (when (or (string-empty-p voice-id)
            (string-match-p "[\0\r\n]" voice-id))
    (user-error "Invalid Omnivox voice identifier"))
  (setq omnivox-default-voice-id voice-id)
  (unless (> (omnivox--send-state-command
              (format "tts_set_voice %s" voice-id))
             0)
    (user-error "No live Omnivox speech process"))
  voice-id)

(defun omnivox-select-voice ()
  "Select a discovered physical voice for the current Omnivox engine."
  (interactive)
  (unless omnivox-available-voices
    (omnivox-refresh-voices))
  (unless omnivox-available-voices
    (user-error "Omnivox reported no available voices"))
  (let* ((candidates
          (mapcar
           (lambda (voice)
             (pcase-let ((`(,id ,name ,language ,quality) voice))
               (cons
                (format "%s [%s, %s] — %s"
                        name language quality id)
                id)))
           omnivox-available-voices))
         (choice (completing-read "Omnivox voice: " candidates nil t))
         (voice-id (cdr (assoc-string choice candidates))))
    (omnivox-set-voice voice-id)
    (message "Omnivox voice set to %s" voice-id)))

(defun omnivox-list-voices ()
  "Display physical voices available from the current Omnivox engine."
  (interactive)
  (unless omnivox-available-voices
    (omnivox-refresh-voices))
  (with-help-window "*Omnivox Voices*"
    (princ (format "Omnivox reported %d voices.\n\n"
                   (length omnivox-available-voices)))
    (dolist (voice omnivox-available-voices)
      (pcase-let ((`(,id ,name ,language ,quality) voice))
        (princ (format "%s\n  ID: %s\n  Language: %s\n  Quality: %s\n\n"
                       name id language quality))))))

(defun omnivox--status-value (record fallback)
  "Return status string from RECORD, or FALLBACK."
  (let ((status (and (listp record) (plist-get record :status))))
    (if (stringp status) status fallback)))

(defun omnivox--status-reason (record)
  "Return the optional reason from availability or health RECORD."
  (and (listp record) (plist-get record :reason)))

(defun omnivox--control-feature-p (feature)
  "Return non-nil when the main Omnivox process advertised FEATURE."
  (and omnivox-control-capabilities
       (member feature (plist-get omnivox-control-capabilities :features))))

(defun omnivox--inventory-process-agreement ()
  "Describe agreement between distinct live Omnivox speech processes."
  (let ((processes
         (cl-remove-if-not
          #'process-live-p
          (delete-dups (list tts-speaker-process tts-notify-process)))))
    (cond
     ((< (length processes) 2) "single-process")
     ((cl-every
       (lambda (process)
         (process-get process omnivox--control-inventory-property))
       processes)
      (let ((signatures
             (mapcar
              (lambda (process)
                (let ((inventory
                       (process-get
                        process omnivox--control-inventory-property)))
                  (list
                   (plist-get inventory :inventory_generation)
                   (plist-get inventory :preferred_engine_id)
                   (plist-get inventory :routing_policy))))
              processes)))
        (if (cl-every (lambda (signature)
                        (equal signature (car signatures)))
                      (cdr signatures))
            "agree"
          "differ")))
     (t "pending"))))

(defun omnivox--inventory-voice (engine-id voice)
  "Normalize Omnivox VOICE belonging to ENGINE-ID."
  (let ((id (plist-get voice :id)))
    (list
     :engine-id (or (plist-get id :engine_id) engine-id)
     :voice-id (plist-get id :voice_id)
     :display-name (plist-get voice :display_name)
     :language (plist-get voice :language)
     :gender (plist-get voice :gender)
     :quality (plist-get voice :quality)
     :availability
     (omnivox--status-value (plist-get voice :availability) "unknown")
     :availability-reason
     (omnivox--status-reason (plist-get voice :availability)))))

(defun omnivox--inventory-runtime (engine-id)
  "Return live runtime status for ENGINE-ID from the main inventory."
  (cl-find-if
   (lambda (status)
     (equal engine-id (plist-get status :engine_id)))
   (append (plist-get omnivox-engine-inventory :engine_runtime) nil)))

(defun omnivox--inventory-engine
    (engine &optional inventory-kind runtime-status)
  "Normalize one engine descriptor and optional RUNTIME-STATUS."
  (let* ((engine-id (plist-get engine :id))
         (capabilities (plist-get engine :capabilities))
         (acss (plist-get capabilities :acss))
         (markers (plist-get capabilities :markers)))
    (list
     :engine-id engine-id
     :display-name (plist-get engine :display_name)
     :version (plist-get engine :version)
     :availability
     (omnivox--status-value (plist-get engine :availability) "unknown")
     :availability-reason
     (omnivox--status-reason (plist-get engine :availability))
     :health (omnivox--status-value (plist-get engine :health) "unknown")
     :health-reason (omnivox--status-reason (plist-get engine :health))
     :circuit (or (plist-get runtime-status :circuit) "unknown")
     :last-failure (plist-get runtime-status :last_failure)
     :cooldown-remaining-ms
     (plist-get runtime-status :cooldown_remaining_ms)
     :disabled-by-policy
     (and (plist-get runtime-status :disabled_by_policy) t)
     :default-voice-id (plist-get engine :default_voice_id)
     :inventory-kind (or inventory-kind "live")
     :audio-output (plist-get capabilities :audio_output)
     :marker-support
     (delq
      nil
      (mapcar
       (lambda (entry) (and (plist-get markers (car entry)) (cdr entry)))
       '((:word . word) (:sentence . sentence) (:phoneme . phoneme)
         (:native_index . native-index))))
     :anchor-support
     (cond
      ((plist-get markers :native_index) "exact/native-index")
      ((plist-get markers :word) "word-boundary")
      (t "none"))
     :acss-dimensions
     (delq
      nil
      (mapcar
       (lambda (entry) (and (plist-get acss (car entry)) (cdr entry)))
       '((:rate . rate) (:average_pitch . average-pitch)
         (:pitch_range . pitch-range) (:stress . stress)
         (:richness . richness) (:volume . volume))))
     :post-synthesis-dimensions
     (copy-sequence (plist-get capabilities :post_synthesis_dimensions))
     :preview-support
     (if (omnivox--control-feature-p "exact_voice_preview")
         "exact"
       "logical-route")
     :routing-policy-support
     (if (omnivox--control-feature-p "runtime_routing_policy")
         "runtime"
       "unsupported")
     :capabilities (copy-tree capabilities)
     :voices
     (mapcar
      (lambda (voice) (omnivox--inventory-voice engine-id voice))
      (append (plist-get engine :voices) nil)))))

(defun omnivox-voice-inventory ()
  "Return the normalized live Omnivox engine and voice inventory."
  (if (not omnivox-engine-inventory)
      (list
       :adapter "omnivox" :source "live" :status "pending"
       :generation nil :received-at nil :stale nil
       :preferred-engine-id nil
       :preferred-engine-order nil
       :fallback-engine-order nil
       :disabled-engine-ids nil
       :process-agreement (omnivox--inventory-process-agreement)
       :preview-support "pending"
       :routing-policy-support "pending"
       :engines nil)
    (let* ((live (process-live-p tts-speaker-process))
           (received omnivox-engine-inventory-time)
           (age (and received (float-time (time-subtract nil received))))
           (registration (plist-get omnivox-engine-inventory :routing_policy))
           (policy (plist-get registration :policy)))
      (list
       :adapter "omnivox"
       :source (if live "live" "cached")
       :status "available"
       :generation
       (plist-get omnivox-engine-inventory :inventory_generation)
       :received-at received
       :age-seconds age
       :stale (not live)
       :preferred-engine-id
       (plist-get omnivox-engine-inventory :preferred_engine_id)
       :routing-policy-generation
       (plist-get registration :routing_policy_generation)
       :preferred-engine-order
       (append (plist-get policy :preferred_engine_ids) nil)
       :fallback-engine-order
       (append (plist-get policy :fallback_engine_ids) nil)
       :disabled-engine-ids
       (append (plist-get policy :disabled_engine_ids) nil)
       :process-agreement (omnivox--inventory-process-agreement)
       :preview-support
       (if (omnivox--control-feature-p "exact_voice_preview")
           "exact"
         "logical-route")
       :routing-policy-support
       (if (omnivox--control-feature-p "runtime_routing_policy")
           "runtime"
         "unsupported")
       :engines
       (mapcar
        (lambda (engine)
          (omnivox--inventory-engine
           engine (if live "live" "cached")
           (omnivox--inventory-runtime (plist-get engine :id))))
        (append (plist-get omnivox-engine-inventory :engines) nil))))))

(defun omnivox-refresh-voice-inventory ()
  "Request fresh inventories from live Omnivox processes and return a snapshot."
  (dolist (process (delete-dups (list tts-speaker-process tts-notify-process)))
    (when (and (process-live-p process)
               (omnivox--process-supports-p process "engine_inventory"))
      (omnivox--send-control-request
       process '(:type "inventory") #'omnivox--handle-inventory-response)))
  (omnivox-voice-inventory))

(defun omnivox--handle-recovery-probe-response (callback process response)
  "Handle engine recovery probe RESPONSE and invoke CALLBACK."
  (if (equal (plist-get response :type) "engine_recovery_probe_requested")
      (progn
        (when (omnivox--process-supports-p process "engine_inventory")
          (omnivox--send-control-request
           process '(:type "inventory") #'omnivox--handle-inventory-response))
        (when (functionp callback)
          (funcall callback (copy-tree response))))
    (omnivox--record-control-error process response)
    (when (functionp callback)
      (funcall callback (copy-tree response)))))

(defun omnivox-request-engine-recovery-probe (engine-id &optional callback)
  "Arm failed ENGINE-ID for a recovery probe on the main Omnivox process."
  (unless
      (and
       (process-live-p tts-speaker-process)
       (omnivox--process-supports-p
        tts-speaker-process "engine_recovery_probe"))
    (user-error "The live Omnivox server does not support recovery probes"))
  (omnivox--required-selector-id engine-id "recovery probe engine ID")
  (omnivox--send-control-request
   tts-speaker-process
   (list :type "request_engine_recovery_probe" :engine_id engine-id)
   (lambda (process response)
     (omnivox--handle-recovery-probe-response callback process response))))

(defun omnivox--discovered-acss-dimensions ()
  "Return the union of normalized ACSS dimensions advertised by Omnivox."
  (let ((mapping
         '((:rate . rate)
           (:average_pitch . average-pitch)
           (:pitch_range . pitch-range)
           (:stress . stress)
           (:richness . richness)
           (:volume . volume)))
        dimensions)
    (dolist (engine (append (plist-get omnivox-engine-inventory :engines) nil))
      (let ((acss
             (plist-get (plist-get engine :capabilities) :acss)))
        (dolist (entry mapping)
          (when (plist-get acss (car entry))
            (push (cdr entry) dimensions)))))
    (sort (delete-dups dimensions)
          (lambda (left right)
            (string-lessp (symbol-name left) (symbol-name right))))))

(defun omnivox--discovered-post-synthesis-dimensions ()
  "Return normalized post-synthesis dimensions advertised by Omnivox."
  (let (dimensions)
    (dolist (engine (append (plist-get omnivox-engine-inventory :engines) nil))
      (dolist
          (dimension
           (append
            (plist-get (plist-get engine :capabilities)
                       :post_synthesis_dimensions)
            nil))
        (when dimension
          (push (omnivox--preview-dimension-symbol dimension) dimensions))))
    (sort (delete-dups dimensions)
          (lambda (left right)
            (string-lessp (symbol-name left) (symbol-name right))))))

(defun omnivox-voice-capabilities ()
  "Return discovered ACSS and routed-family capabilities for Omnivox."
  (let ((dimensions
         (remove 'rate (omnivox--discovered-acss-dimensions)))
        (effects (omnivox--discovered-post-synthesis-dimensions)))
    (when (and
           (omnivox--control-feature-p "relative_rate_v1")
           (memq 'rate (omnivox--discovered-acss-dimensions)))
      (push 'rate-offset dimensions))
    (list
     :adapter 'omnivox
     :source (if omnivox-engine-inventory 'discovered 'pending)
     :family-selection 'routed
     :families nil
     :generic-families '(male female child)
     :dimensions dimensions
     :post-synthesis-dimensions effects
     :parameters
     (mapcar
      (lambda (dimension)
        (if (eq dimension 'rate-offset)
            (list dimension :type 'integer :minimum -20 :maximum 20 :default 0)
          (list dimension :type 'integer :minimum 0 :maximum 9 :default 5)))
      dimensions)
     :inventory (omnivox-voice-inventory))))

;;;###autoload
(defun omnivox ()
  "Select the Omnivox speech server."
  (interactive)
  (tts-select-server "omnivox"))

(defvar omnivox-default-voice-string "[[pitch 1.0]]"
  "Omnivox inline code for the default voice.")

(defvar omnivox-voice-table (make-hash-table)
  "Map Emacsvox voice symbols to Omnivox inline codes.")

(defconst omnivox-average-pitch-table
  ["[[pitch 0.5]]"
   "[[pitch 0.6]]"
   "[[pitch 0.7]]"
   "[[pitch 0.8]]"
   "[[pitch 0.9]]"
   "[[pitch 1.0]]"
   "[[pitch 1.2]]"
   "[[pitch 1.4]]"
   "[[pitch 1.7]]"
   "[[pitch 2.0]]"]
  "Map normalized ACSS average pitch to Omnivox pitch multipliers.")

(defun omnivox-define-voice (name command &optional normalized-acss)
  "Define Omnivox voice NAME using inline COMMAND and NORMALIZED-ACSS."
  (puthash
   name (concat (omnivox--logical-voice-directive name) " " command)
   omnivox-voice-table)
  (puthash
   (omnivox--logical-voice-id name) normalized-acss
   omnivox--logical-acss-table)
  (omnivox--schedule-logical-registration))

(defun omnivox-get-voice-command (name)
  "Return the Omnivox inline command for voice NAME."
  (cond
   ((listp name)
    (mapconcat #'omnivox-get-voice-command name " "))
   (t
    (or (gethash name omnivox-voice-table)
        omnivox-default-voice-string))))

(defun omnivox-voice-defined-p (name)
  "Return non-nil when Omnivox voice NAME is defined."
  (gethash name omnivox-voice-table))

(omnivox-define-voice 'paul omnivox-default-voice-string)

(defun omnivox--normalize-acss-value (value)
  "Convert ACSS VALUE from zero-to-nine into the zero-to-one range."
  (when (numberp value)
    (/ (float (max 0 (min 9 value))) 9.0)))

(defun omnivox--normalized-acss-json (style)
  "Return the supported normalized ACSS dimensions from STYLE."
  (let (result)
    (dolist
        (entry
         `((:average_pitch ,(acss-average-pitch style))
           (:pitch_range ,(acss-pitch-range style))
           (:stress ,(acss-stress style))
           (:richness ,(acss-richness style))))
      (when (numberp (cadr entry))
        (setq result
              (plist-put
               result (car entry)
               (omnivox--normalize-acss-value (cadr entry))))))
    result))

(defun omnivox-define-voice-from-acss (name style)
  "Define Omnivox voice NAME from ACSS STYLE."
  (let ((pitch (acss-average-pitch style)))
    (omnivox-define-voice
     name
     (if pitch
         (aref omnivox-average-pitch-table pitch)
       omnivox-default-voice-string)
     (omnivox--normalized-acss-json style))))

;;;###autoload
(defun omnivox-configure-tts ()
  "Configure Emacsvox to use Omnivox."
  (setq tts-default-voice 'paul)
  (fset 'tts-voice-defined-p #'omnivox-voice-defined-p)
  (fset 'tts-get-voice-command #'omnivox-get-voice-command)
  (fset 'tts-define-voice-from-acss #'omnivox-define-voice-from-acss)
  (setq tts-voice-capabilities-function #'omnivox-voice-capabilities)
  (setq tts-voice-inventory-function #'omnivox-voice-inventory)
  (setq tts-voice-inventory-refresh-function
        #'omnivox-refresh-voice-inventory)
  (setq tts-voice-configuration-apply-function
        #'omnivox-apply-voice-configuration)
  (setq tts-last-realized-voice-function
        #'omnivox-last-realized-voice)
  (setq tts-engine-recovery-probe-function
        #'omnivox-request-engine-recovery-probe)
  (setq tts-voice-preview-function #'omnivox-preview-voice-sequence)
  (setq tts-voice-preview-code-function #'tts-default-voice-preview-code)
  (setq tts-default-speech-rate omnivox-default-speech-rate)
  (set-default 'tts-default-speech-rate omnivox-default-speech-rate)
  (setq tts-speech-rate omnivox-default-speech-rate)
  (setq-default tts-speech-rate omnivox-default-speech-rate)
  (setq tts-speech-rate-base 20
        tts-speech-rate-step 5
        emacsvox-play-program nil)
  (tts-unicode-update-untouched-charsets
   '(ascii latin-iso8859-1 latin-iso8859-15 latin-iso8859-9
           eight-bit-graphic))
  (omnivox--negotiate-processes)
  (unless (string-empty-p omnivox-default-voice-id)
    (omnivox--send-state-command
     (format "tts_set_voice %s" omnivox-default-voice-id))))

(provide 'omnivox-voices)
;;; omnivox-voices.el ends here
