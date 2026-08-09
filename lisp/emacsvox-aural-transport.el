;;; emacsvox-aural-transport.el --- Concrete aural transport -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Queue backend-ready ordered actions through speech and sound transports,
;; and expose the immediate and compatibility presentation entry points.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-compiler)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-planner)
(require 'emacsvox-aural-source)
(require 'emacsvox-aural-schemes)

(declare-function emacsvox-sounds-play-concrete-cue
                  "emacsvox-sounds" (resource sample-id &optional balance))
(declare-function emacsvox-queue-resource
                  "emacsvox-sounds" (resource))
(declare-function tts--protocol-dispatch "tts-speak" ())
(declare-function tts--interrupt-process "tts-speak"
                  (process &optional notifications))
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-silence "tts-speak" (duration &optional force))
(declare-function tts--protocol-tone "tts-speak" (pitch duration &optional force))
(declare-function tts--prepare-structured-dispatch
                  "tts-speak"
                  (marker-callback completion-callback semantic-actions))
(declare-function tts-initialize "tts-speak" ())
(declare-function tts-voice-reset-code "tts-speak" ())

(defvar tts-speaker-process)
(defvar tts--marker-event-function)
(defvar tts--tracked-completion-function)

(defvar emacsvox-aural--queued-run-leading-pause nil
  "Leading pause retained while queueing one concrete formatting run.")

(cl-defstruct
    (emacsvox-aural--delivery-entry
     (:constructor emacsvox-aural--make-delivery-entry))
  "One server command captured inside a complete delivery transaction."
  process command kind)

(cl-defstruct
    (emacsvox-aural--pending-delivery
     (:constructor emacsvox-aural--make-pending-delivery))
  "One replaceable delivery waiting for an input-idle boundary."
  sequence owner replacement-key entries effects timer transaction-id)

(defcustom emacsvox-aural-replacement-idle-delay 0.025
  "Seconds of input idle before sending a replaceable presentation.

Each newer transaction with the same speaker and replacement key restarts this
delay.  Ordered and urgent transactions are never delayed."
  :type 'number
  :group 'emacsvox-aural)

(defvar emacsvox-aural--delivery-transaction-active-p nil
  "Non-nil while complete server commands are being collected.")

(defvar emacsvox-aural--delivery-transaction-entries nil
  "Reverse-ordered server commands in the current delivery transaction.")

(defvar emacsvox-aural--delivery-transaction-effects nil
  "Reverse-ordered effects committed after the current transaction is sent.")

(defvar emacsvox-aural--delivery-timeline-runs nil
  "Reverse-ordered concrete runs captured for structured delivery.")

(defvar emacsvox-aural--delivery-entry-kind nil
  "Dynamic origin tag applied to captured delivery entries.")

(defvar emacsvox-aural--structured-runs-recorded-p nil
  "Non-nil when the enclosing run queue already captured structured runs.")

(defvar emacsvox-aural--pending-deliveries
  (make-hash-table :test #'equal)
  "Replaceable server transactions indexed by owner and replacement key.")

(defvar emacsvox-aural--delivery-sequence 0
  "Sequence preserving order across independent replacement keys.")

(defvar emacsvox-aural-last-delivery-failure nil
  "Data-only description of the most recent asynchronous delivery failure.")

(defvar emacsvox-aural-delivery-failed-hook nil
  "Abnormal hook run after an asynchronous delivery failure.

Each function receives the failure plist stored in
`emacsvox-aural-last-delivery-failure'.")

(defconst emacsvox-aural--framed-delivery-process-property
  'emacsvox-aural-framed-delivery
  "Process property enabling complete replaceable transaction framing.")

(defconst emacsvox-aural--structured-timeline-process-property
  'emacsvox-aural-structured-timeline
  "Process property recording the negotiated structured timeline version.")

(defconst emacsvox-aural--relative-rate-process-property
  'emacsvox-aural-relative-rate
  "Process property enabling signed relative rate in timelines.")

(defconst emacsvox-aural--structured-timeline-version 2
  "Structured presentation timeline version emitted by Emacsvox.")

(defconst emacsvox-aural--timeline-replacement-key-max-bytes 128
  "Maximum UTF-8 size of one timeline replacement key.")

(defun emacsvox-aural-enable-framed-delivery (process)
  "Enable complete replaceable transaction framing for PROCESS."
  (process-put
   process emacsvox-aural--framed-delivery-process-property t)
  process)

(defun emacsvox-aural-enable-structured-timeline (process &optional version)
  "Record structured aural timeline VERSION support for PROCESS.

VERSION defaults to 2 for direct callers.  Version 1 is recorded only so an
installation mismatch can be reported before Aural semantics are lowered."
  (setq version (or version 2))
  (unless (memq version '(1 2))
    (error "Unsupported structured timeline version: %S" version))
  (process-put
   process emacsvox-aural--structured-timeline-process-property version)
  process)

(defun emacsvox-aural-enable-relative-rate (process)
  "Enable signed relative speech-rate fields for PROCESS."
  (process-put process emacsvox-aural--relative-rate-process-property t)
  process)

(defun emacsvox-aural-delivery-send (process command &optional kind)
  "Send COMMAND to PROCESS through the current delivery transaction.

KIND may be `stop'.  Stops are delivery control rather than presentation
payload, so they remain immediate and cannot accumulate behind idle delivery."
  (if
      (and
       emacsvox-aural--delivery-transaction-active-p
       (not (eq kind 'stop)))
      (push
       (emacsvox-aural--make-delivery-entry
        :process process :command command
        :kind (or kind emacsvox-aural--delivery-entry-kind))
       emacsvox-aural--delivery-transaction-entries)
    (process-send-string process command)))

(defun emacsvox-aural--framed-delivery-entries
    (owner generation entries)
  "Frame replaceable ENTRIES for OWNER at GENERATION when supported."
  (if
      (and
       generation
       (not
        (cl-some
         (lambda (entry)
           (eq 'structured
               (emacsvox-aural--delivery-entry-kind entry)))
         entries))
       (processp owner)
       (process-get
        owner emacsvox-aural--framed-delivery-process-property)
       (cl-every
        (lambda (entry)
          (eq owner (emacsvox-aural--delivery-entry-process entry)))
        entries))
      (let* ((payload
              (apply
               #'concat
               (mapcar
                #'emacsvox-aural--delivery-entry-command entries)))
             (encoded
              (base64-encode-string
               (encode-coding-string payload 'utf-8 t) t)))
        (list
         (emacsvox-aural--make-delivery-entry
          :process owner
          :command
          (format "emacsvox_tx %d {%s}\n" generation encoded))))
    entries))

(defun emacsvox-aural--delivery-process-name (process)
  "Return a diagnostic name for PROCESS without requiring a live process."
  (if (processp process)
      (process-name process)
    (format "%s" process)))

(defun emacsvox-aural--record-delivery-failure
    (reason process owner generation transaction-id &optional error-data)
  "Record one delivery failure for PROCESS and return nil.

REASON identifies the failure category.  OWNER, GENERATION and TRANSACTION-ID
identify the logical delivery.  ERROR-DATA is the caught Lisp condition, when
one was signalled."
  (let ((failure
         (list
          :time (current-time)
          :reason reason
          :process-name (emacsvox-aural--delivery-process-name process)
          :owner-name
          (and owner (emacsvox-aural--delivery-process-name owner))
          :process-generation
          (and
           (processp process)
           (process-get process 'tts--speech-process-generation))
          :generation generation
          :transaction-id transaction-id
          :condition (car-safe error-data)
          :error-message
          (and error-data (error-message-string error-data)))))
    (setq emacsvox-aural-last-delivery-failure failure)
    (condition-case hook-error
        (run-hook-with-args
         'emacsvox-aural-delivery-failed-hook failure)
      (error
       (message
        "Emacsvox delivery failure hook failed: %s"
        (error-message-string hook-error))))
    (message
     "Emacsvox discarded speech delivery to %s: %s"
     (plist-get failure :process-name)
     (or (plist-get failure :error-message) reason))
    nil))

(defun emacsvox-aural--send-delivery-entries
    (entries &optional owner generation transaction-id)
  "Send ordered delivery ENTRIES, combining adjacent writes per process.

Return non-nil when every entry was sent to a live process."
  (setq
   entries
   (emacsvox-aural--framed-delivery-entries
    owner generation entries))
  (let ((sent t)
        current-process commands)
    (cl-labels
        ((flush
          ()
          (when (and sent current-process)
            (if
                (and
                 (processp current-process)
                 (not (process-live-p current-process)))
                (progn
                  (setq sent nil)
                  (emacsvox-aural--record-delivery-failure
                   'process-not-live current-process owner generation
                   transaction-id))
              (condition-case error-data
                  (process-send-string
                   current-process (apply #'concat (nreverse commands)))
                (error
                 (setq sent nil)
                 (emacsvox-aural--record-delivery-failure
                  'process-send-error current-process owner generation
                  transaction-id error-data)))))
          (setq current-process nil commands nil)))
      (dolist (entry entries)
        (let ((process (emacsvox-aural--delivery-entry-process entry))
              (command (emacsvox-aural--delivery-entry-command entry)))
          (unless (eq process current-process)
            (flush)
            (setq current-process process))
          (push command commands)))
      (flush))
    sent))

(defun emacsvox-aural--commit-delivery-effects (effects)
  "Run forward-ordered delivery EFFECTS."
  (dolist (effect effects)
    (funcall effect)))

(defun emacsvox-aural--defer-delivery-effect (effect)
  "Commit EFFECT after the current packet is sent, or immediately outside one."
  (if emacsvox-aural--delivery-transaction-active-p
      (push effect emacsvox-aural--delivery-transaction-effects)
    (funcall effect)))

(defun emacsvox-aural--pending-delivery-table-key
    (owner replacement-key)
  "Return the scheduler table key for OWNER and REPLACEMENT-KEY."
  (list owner replacement-key))

(defun emacsvox-aural--deliver-pending (table-key)
  "Deliver and remove the pending transaction at TABLE-KEY."
  (when-let* ((pending
               (gethash table-key emacsvox-aural--pending-deliveries)))
    (remhash table-key emacsvox-aural--pending-deliveries)
    (setf (emacsvox-aural--pending-delivery-timer pending) nil)
    (when
        (emacsvox-aural--send-delivery-entries
         (emacsvox-aural--pending-delivery-entries pending)
         (emacsvox-aural--pending-delivery-owner pending)
         (emacsvox-aural--pending-delivery-sequence pending)
         (emacsvox-aural--pending-delivery-transaction-id pending))
      (emacsvox-aural--commit-delivery-effects
       (emacsvox-aural--pending-delivery-effects pending)))))

(defun emacsvox-aural--pending-delivery-keys
    (owner &optional replacement-key)
  "Return pending scheduler keys for OWNER and optional REPLACEMENT-KEY."
  (let (keys)
    (maphash
     (lambda (table-key pending)
       (when
           (and
            (eq
             owner
             (emacsvox-aural--pending-delivery-owner pending))
            (or
             (null replacement-key)
             (equal
              replacement-key
              (emacsvox-aural--pending-delivery-replacement-key
               pending))))
         (push table-key keys)))
     emacsvox-aural--pending-deliveries)
    (sort
     keys
     :key
     (lambda (table-key)
       (emacsvox-aural--pending-delivery-sequence
        (gethash table-key emacsvox-aural--pending-deliveries))))))

(defun emacsvox-aural-cancel-pending-deliveries
    (owner &optional replacement-key)
  "Discard pending deliveries for OWNER and optional REPLACEMENT-KEY."
  (dolist
      (table-key
       (emacsvox-aural--pending-delivery-keys owner replacement-key))
    (when-let* ((pending
                 (gethash table-key emacsvox-aural--pending-deliveries))
                (timer (emacsvox-aural--pending-delivery-timer pending)))
      (cancel-timer timer))
    (remhash table-key emacsvox-aural--pending-deliveries)))

(defun emacsvox-aural-flush-pending-deliveries
    (owner &optional replacement-key)
  "Send pending deliveries for OWNER and optional REPLACEMENT-KEY now."
  (dolist
      (table-key
       (emacsvox-aural--pending-delivery-keys owner replacement-key))
    (when-let* ((pending
                 (gethash table-key emacsvox-aural--pending-deliveries))
                (timer (emacsvox-aural--pending-delivery-timer pending)))
      (cancel-timer timer))
    (emacsvox-aural--deliver-pending table-key)))

(defun emacsvox-aural--schedule-replaceable-delivery
    (owner replacement-key entries effects generation)
  "Schedule ENTRIES and EFFECTS for OWNER, replacing older keyed work."
  (let* ((table-key
          (emacsvox-aural--pending-delivery-table-key
           owner replacement-key))
         (pending
          (emacsvox-aural--make-pending-delivery
           :sequence generation
           :owner owner
           :replacement-key replacement-key
           :entries entries
           :effects effects
           :transaction-id emacsvox-aural--history-transaction-id)))
    (puthash table-key pending emacsvox-aural--pending-deliveries)
    (setf
     (emacsvox-aural--pending-delivery-timer pending)
     (run-with-idle-timer
      emacsvox-aural-replacement-idle-delay nil
      #'emacsvox-aural--deliver-pending table-key))))

(defun emacsvox-aural--submit-delivery-entries
    (owner entries effects generation)
  "Submit protocol ENTRIES and commit EFFECTS under current source policy."
  (when entries
    (when-let* ((foreign
                 (cl-find-if
                  (lambda (entry)
                    (not
                     (eq
                      owner
                      (emacsvox-aural--delivery-entry-process entry))))
                  entries)))
      (error
       "Aural transaction for %s contains a command for %s"
       (emacsvox-aural--delivery-process-name owner)
       (emacsvox-aural--delivery-process-name
        (emacsvox-aural--delivery-entry-process foreign))))
    (pcase (or emacsvox-aural-submission-delivery-policy 'ordered)
      ('replaceable
       (emacsvox-aural-cancel-pending-deliveries
        owner emacsvox-aural-submission-replacement-key)
       (when emacsvox-aural-submission-controls-interruption
         (tts--interrupt-process owner t))
       (emacsvox-aural--schedule-replaceable-delivery
        owner emacsvox-aural-submission-replacement-key
        entries effects generation))
      ('urgent
       (emacsvox-aural-cancel-pending-deliveries owner)
       (when emacsvox-aural-submission-controls-interruption
         (tts--interrupt-process owner t))
       (when
           (emacsvox-aural--send-delivery-entries
            entries owner nil emacsvox-aural--history-transaction-id)
         (emacsvox-aural--commit-delivery-effects effects)))
      (_
       (emacsvox-aural-flush-pending-deliveries owner)
       (when
           (emacsvox-aural--send-delivery-entries
            entries owner nil emacsvox-aural--history-transaction-id)
         (emacsvox-aural--commit-delivery-effects effects))))))

(defun emacsvox-aural-call-with-delivery-transaction
    (owner function &rest arguments)
  "Call FUNCTION with ARGUMENTS and deliver its server writes for OWNER.

Nested calls join the enclosing transaction.  The outer source submission's
delivery policy determines whether the complete captured payload is sent now
or supersedes an older pending payload.  Every captured command must target
OWNER so a logical transaction cannot be partially delivered across streams."
  (if emacsvox-aural--delivery-transaction-active-p
      (apply function arguments)
    (let ((emacsvox-aural--delivery-transaction-active-p t)
          (emacsvox-aural--delivery-transaction-entries nil)
          (emacsvox-aural--delivery-transaction-effects nil)
          (emacsvox-aural--delivery-timeline-runs nil)
          result)
      (setq result (apply function arguments))
      (let* ((entries (nreverse emacsvox-aural--delivery-transaction-entries))
             (effects (nreverse emacsvox-aural--delivery-transaction-effects))
             (generation (cl-incf emacsvox-aural--delivery-sequence))
             (structured
              (emacsvox-aural--finalize-structured-delivery
               owner generation entries effects
               (nreverse emacsvox-aural--delivery-timeline-runs))))
        (setq entries (car structured)
              effects (cadr structured))
        (when (integerp (caddr structured))
          (setq result (caddr structured)))
        (when
            (and
             entries
             (functionp emacsvox-aural--delivery-history-registrar))
          (setq effects
                (cons
                 (funcall emacsvox-aural--delivery-history-registrar)
                 effects)))
        (emacsvox-aural--submit-delivery-entries
         owner entries effects generation))
      result)))

(defun emacsvox-aural--structured-capture-p ()
  "Return non-nil when the current transaction can carry a timeline."
  (and
   emacsvox-aural--delivery-transaction-active-p
   (emacsvox-aural-structured-timeline-available-p)))

(defun emacsvox-aural-structured-timeline-available-p ()
  "Return non-nil when the speaker accepts version 2 presentation timelines.

Signal a clear installation error when negotiation found only version 1."
  (when (processp tts-speaker-process)
    (let ((version
           (process-get
            tts-speaker-process
            emacsvox-aural--structured-timeline-process-property)))
      (cond
       ((eql version 2) t)
       ((eql version 1)
        (error
         "Omnivox timeline V2 is required; rebuild and restart the speech server"))
       (version
        (error "Unsupported negotiated Omnivox timeline version: %S" version))))))

(defun emacsvox-aural--capture-structured-run
    (plan text pause positioned-actions)
  "Capture PLAN, final TEXT, PAUSE, and POSITIONED-ACTIONS for the timeline."
  (push
   (list plan text pause positioned-actions)
   emacsvox-aural--delivery-timeline-runs))

(defun emacsvox-aural--structured-compatible-delivery-entry-p (entry)
  "Return non-nil when ENTRY can accompany a structured timeline."
  (let ((command (emacsvox-aural--delivery-entry-command entry)))
    (or
     (eq 'structured-fallback
         (emacsvox-aural--delivery-entry-kind entry))
     (string-prefix-p "tts_sync_state " command)
     (string-prefix-p "tts_set_capitalization_presentation " command))))

(defun emacsvox-aural-structured-delivery-pending-p ()
  "Return non-nil when the current transaction can replace its legacy queue."
  (and
   emacsvox-aural--delivery-timeline-runs
   (cl-every
    #'emacsvox-aural--timeline-run-has-speech-p
    emacsvox-aural--delivery-timeline-runs)
   (cl-every
    #'emacsvox-aural--structured-compatible-delivery-entry-p
    emacsvox-aural--delivery-transaction-entries)))

(defun emacsvox-aural--timeline-run-has-speech-p (run)
  "Return non-nil when concrete RUN contains a nonempty speech span."
  (pcase-let* ((`(,plan ,text ,_ . ,_) run)
               (content (emacsvox-aural-concrete-plan-content plan)))
    (or
     (and
      (emacsvox-aural-concrete-content-speak content)
      (stringp text) (not (string-empty-p text)))
     (cl-some
      (lambda (action)
        (and
         (eq 'speech (emacsvox-aural-concrete-action-kind action))
         (stringp (emacsvox-aural-concrete-action-text action))
         (not
          (string-empty-p
           (emacsvox-aural-concrete-action-text action)))))
      (append
       (emacsvox-aural-concrete-plan-before plan)
       (emacsvox-aural-concrete-plan-after plan))))))

(defun emacsvox-aural--timeline-normalize-value (value)
  "Normalize portable zero-to-nine VALUE for the timeline wire."
  (when (numberp value)
    (/ (float (max 0 (min 9 value))) 9.0)))

(defun emacsvox-aural--timeline-style-acss (style)
  "Return JSON ACSS fields carried by concrete voice STYLE."
  (let (result)
    (dolist
        (mapping
         '((:average-pitch . :average_pitch)
           (:pitch-range . :pitch_range)
           (:stress . :stress)
           (:richness . :richness)))
      (when-let* ((value
                   (emacsvox-aural--timeline-normalize-value
                    (plist-get style (car mapping)))))
        (setq result (plist-put result (cdr mapping) value))))
    (or result (make-hash-table :test #'equal))))

(defun emacsvox-aural--timeline-rate-offset (style)
  "Return STYLE's nonzero relative rate when the live process supports it."
  (let ((value (plist-get style :rate-offset)))
    (and
     (numberp value)
     (not (zerop value))
     (processp tts-speaker-process)
     (process-get
      tts-speaker-process emacsvox-aural--relative-rate-process-property)
     value)))

(defun emacsvox-aural--timeline-style-effects (style &optional balance)
  "Return JSON post-synthesis effects carried by STYLE and stereo BALANCE."
  (let (result)
    (dolist
        (mapping
         '((:gain . :gain)
           (:low-pass . :low_pass)
           (:high-pass . :high_pass)
           (:pan . :pan)
           (:reverb . :reverb)
           (:echo . :echo)))
      (when-let* ((value
                   (emacsvox-aural--timeline-normalize-value
                    (plist-get style (car mapping)))))
        (setq result (plist-put result (cdr mapping) value))))
    (when (numberp balance)
      (setq
       result
       (plist-put
        result :pan
        (/ (1+ (float (max -1.0 (min 1.0 balance)))) 2.0))))
    result))

(defun emacsvox-aural--timeline-action-pan (action)
  "Return ACTION's normalized concrete stereo position, defaulting to center."
  (let ((balance (emacsvox-aural-concrete-action-balance action)))
    (if (numberp balance)
        (/ (1+ (float (max -1.0 (min 1.0 balance)))) 2.0)
      0.5)))

(defun emacsvox-aural--timeline-logical-voice (command request)
  "Return the logical voice ID frozen in portable REQUEST or COMMAND.

A named portable request owns routing identity.  Generated legacy commands
may contain an ACSS implementation name such as `acss-a6'; use that only when
the concrete request has no named preset."
  (cond
   ((and request (symbolp request)) (symbol-name request))
   ((stringp request) request)
   ((and
     (listp request)
     (plist-get request :preset)
     (symbolp (plist-get request :preset)))
    (symbol-name (plist-get request :preset)))
   ((and (listp request) (stringp (plist-get request :preset)))
    (plist-get request :preset))
   ((and
     (stringp command)
     (string-match
      "\\[\\[logical_voice \\([A-Za-z0-9_.-]+\\)\\]\\]" command))
    (match-string 1 command))))

(defun emacsvox-aural--timeline-position (span-id affinity)
  "Return one span-boundary JSON position for SPAN-ID and AFFINITY."
  (list
   :position "span_boundary"
   :span_id span-id
   :affinity (symbol-name affinity)))

(defun emacsvox-aural--timeline-text-offset-position
    (span-id utf8-offset affinity)
  "Return an internal UTF-8 position in SPAN-ID at UTF8-OFFSET."
  (list
   :position "text_offset"
   :span_id span-id
   :utf8_offset utf8-offset
   :affinity (symbol-name affinity)))

(defun emacsvox-aural--timeline-lifecycle (action)
  "Return ACTION's valid lifecycle anchor as a JSON string."
  (symbol-name
   (or (emacsvox-aural-concrete-action-anchor action) 'object)))

(defun emacsvox-aural--timeline-delivery-fields ()
  "Return version 2 delivery fields for the current Aural submission."
  (let ((policy (or emacsvox-aural-submission-delivery-policy 'ordered)))
    (unless (memq policy '(ordered replaceable urgent))
      (error "Unsupported aural delivery policy: %S" policy))
    (append
     (list :delivery_policy (symbol-name policy))
     (when (eq policy 'replaceable)
       (unless emacsvox-aural-submission-replacement-key
         (error "Replaceable aural delivery requires a replacement key"))
       (let ((key
              (cond
               ((symbolp emacsvox-aural-submission-replacement-key)
                (symbol-name emacsvox-aural-submission-replacement-key))
               ((stringp emacsvox-aural-submission-replacement-key)
                emacsvox-aural-submission-replacement-key)
               (t
                (let ((print-circle t))
                  (prin1-to-string
                   emacsvox-aural-submission-replacement-key))))))
         (when
             (or
              (string-empty-p key)
              (>
               (string-bytes key)
               emacsvox-aural--timeline-replacement-key-max-bytes))
           (error
            "Aural replacement key must contain 1 to %d UTF-8 bytes"
            emacsvox-aural--timeline-replacement-key-max-bytes))
         (list :replacement_key key))))))

(defun emacsvox-aural--timeline-semantic-value (action)
  "Return the richer client value associated with concrete ACTION."
  (list
   :id (emacsvox-aural-concrete-action-id action)
   :kind (emacsvox-aural-concrete-action-kind action)
   :anchor (emacsvox-aural-concrete-action-anchor action)
   :source (emacsvox-aural-concrete-action-source action)
   :cue (emacsvox-aural-concrete-action-cue action)
   :tone (emacsvox-aural-concrete-action-tone action)
   :audio-mode (emacsvox-aural-concrete-action-audio-mode action)))

(defun emacsvox-aural--build-structured-timeline
    (generation dispatch-id runs)
  "Build a structured timeline for GENERATION, DISPATCH-ID, and RUNS.

Return a list of envelope and opaque semantic bindings, or nil when the
recorded plans contain no speech span and therefore require legacy lowering."
  (let ((span-sequence 0)
        (action-sequence 0)
        active-effects spans actions bindings unsupported)
    (cl-labels
        ((wire-id
          (prefix)
          (format "%s.%d" prefix (cl-incf action-sequence)))
         (effect-directive
          (style balance)
          (let ((effects
                 (emacsvox-aural--timeline-style-effects style balance)))
            (cond
             ((equal effects active-effects) '(:mode "retain"))
             (effects
              (setq active-effects (copy-tree effects))
              (list
               :mode "replace"
               :state_id (format "emacsvox.effects.%d" span-sequence)
               :style effects))
             (active-effects
              (setq active-effects nil)
              '(:mode "end"))
             (t '(:mode "retain")))))
         (add-wire-action
          (wire-id position lifecycle fields semantic-value)
          (push
           (append
            (list
             :id wire-id
             :position position
             :lifecycle_anchor lifecycle)
            fields)
           actions)
          (when semantic-value
            (push (cons wire-id (copy-tree semantic-value)) bindings)))
         (add-action
          (action span-id affinity context &optional explicit-position)
          (let* ((position
                  (or
                   explicit-position
                   (emacsvox-aural--timeline-position span-id affinity)))
                 (lifecycle
                  (emacsvox-aural--timeline-lifecycle action))
                 (semantic-value
                  (emacsvox-aural--timeline-semantic-value action))
                 (kind (emacsvox-aural-concrete-action-kind action))
                 (wire-action-id (wire-id "action"))
                 (modelled t))
            (pcase kind
              ('cue
               (if (emacsvox-aural-icons-enabled-p context)
                   (add-wire-action
                    wire-action-id position lifecycle
                    (list
                     :type "audio"
                     :path
                     (expand-file-name
                      (emacsvox-aural-concrete-action-resource action))
                     :mode "overlay" :volume 1.0
                     :pan (emacsvox-aural--timeline-action-pan action)
                     :effect_bus "dry")
                    semantic-value)
                 (setq modelled nil)))
              ('pause
               (add-wire-action
                wire-action-id position lifecycle
                (list
                 :type "silence"
                 :duration_ms
                 (emacsvox-aural-concrete-action-duration action))
                semantic-value))
              ('tone
               (add-wire-action
                wire-action-id position lifecycle
                (list
                 :type "tone"
                 :frequency_hz
                 (float (emacsvox-aural-concrete-action-pitch action))
                 :duration_ms
                 (emacsvox-aural-concrete-action-duration action)
                 :mode
                 (symbol-name
                  (or
                   (emacsvox-aural-concrete-action-audio-mode action)
                   'overlay))
                 :volume 1.0
                 :pan (emacsvox-aural--timeline-action-pan action)
                 :effect_bus "dry")
                semantic-value))
              (_ (setq modelled nil)))
            (when modelled
              (let ((semantic-id (wire-id "semantic")))
                (add-wire-action
                 semantic-id position lifecycle
                 '(:type "semantic_event") semantic-value)))))
         (add-silence
          (duration span-id affinity)
          (add-wire-action
           (wire-id "pause")
           (emacsvox-aural--timeline-position span-id affinity)
           "run"
           (list :type "silence" :duration_ms duration)
           nil))
         (add-span
          (text request style command balance lifecycle pending context)
          (let* ((span-id (cl-incf span-sequence))
                 (logical
                  (emacsvox-aural--timeline-logical-voice command request))
                 (rate-offset
                  (emacsvox-aural--timeline-rate-offset style)))
            (push
             (append
              (list
               :id span-id :text text
               :logical_voice_id (or logical :null)
               :acss (emacsvox-aural--timeline-style-acss style)
               :effects (effect-directive style balance))
              (when rate-offset (list :rate_offset rate-offset)))
             spans)
            (dolist (action pending)
              (if (numberp action)
                  (add-silence action span-id 'before)
                (add-action action span-id 'before context)))
            (when lifecycle
              (let ((semantic-id (wire-id "semantic")))
                (add-wire-action
                 semantic-id
                 (emacsvox-aural--timeline-position span-id 'before)
                 (emacsvox-aural--timeline-lifecycle lifecycle)
                 '(:type "semantic_event")
                 (emacsvox-aural--timeline-semantic-value lifecycle))))
            span-id))
         (speech-action-p
          (action)
          (and
           (eq 'speech (emacsvox-aural-concrete-action-kind action))
           (stringp (emacsvox-aural-concrete-action-text action))
           (not
            (string-empty-p
             (emacsvox-aural-concrete-action-text action))))))
      (dolist (run runs)
        (pcase-let* ((`(,plan ,text ,pause . ,extra) run)
                     (positioned-actions (car extra))
                     (content (emacsvox-aural-concrete-plan-content plan))
                     (context (emacsvox-aural-concrete-plan-context plan))
                     (pending (and pause (list pause)))
                     (last-span nil))
          (dolist (action (emacsvox-aural-concrete-plan-before plan))
            (if (speech-action-p action)
                (progn
                  (setq
                   last-span
                   (add-span
                    (emacsvox-aural-concrete-action-text action)
                    (emacsvox-aural-concrete-action-voice-request action)
                    (emacsvox-aural-concrete-action-voice-style action)
                    (emacsvox-aural-concrete-action-voice-command action)
                    (emacsvox-aural-concrete-action-balance action)
                    action pending context)
                   pending nil))
              (setq pending (append pending (list action)))))
          (when
              (and
               (emacsvox-aural-concrete-content-speak content)
               (stringp text) (not (string-empty-p text)))
            (setq
             last-span
             (add-span
              text
              (emacsvox-aural-concrete-content-voice-request content)
              (emacsvox-aural-concrete-content-voice-style content)
              (emacsvox-aural-concrete-content-voice-command content)
              (emacsvox-aural-concrete-content-balance content)
              nil pending context)
             pending nil))
          (dolist (positioned positioned-actions)
            (let ((offset (plist-get positioned :utf8-offset)))
              (unless
                  (and last-span (integerp offset)
                       (>= offset 0) (<= offset (string-bytes text)))
                (emacsvox-aural--transport-error
                 "Invalid positioned action offset %S for %S" offset text))
              (dolist
                  (entry (plist-get positioned :actions))
                (add-action
                 (emacsvox-aural-concrete-positioned-action-action entry)
                 last-span 'before
                 (emacsvox-aural-concrete-positioned-action-context entry)
                 (emacsvox-aural--timeline-text-offset-position
                  last-span offset 'before)))))
          (dolist (action (emacsvox-aural-concrete-plan-after plan))
            (if (speech-action-p action)
                (progn
                  (setq
                   last-span
                   (add-span
                    (emacsvox-aural-concrete-action-text action)
                    (emacsvox-aural-concrete-action-voice-request action)
                    (emacsvox-aural-concrete-action-voice-style action)
                    (emacsvox-aural-concrete-action-voice-command action)
                    (emacsvox-aural-concrete-action-balance action)
                    action pending context)
                   pending nil))
              (setq pending (append pending (list action)))))
          (if (not last-span)
              (setq unsupported t)
            (dolist (action pending)
              (if (numberp action)
                  (add-silence action last-span 'after)
                (add-action action last-span 'after context)))))))
    (unless unsupported
      (list
       (append
        (list
         :protocol_version emacsvox-aural--structured-timeline-version
         :generation generation
         :dispatch_id dispatch-id)
        (emacsvox-aural--timeline-delivery-fields)
        (list
         :spans (vconcat (nreverse spans))
         :actions (vconcat (nreverse actions))))
       (nreverse bindings)))))

(defun emacsvox-aural--encode-structured-timeline (envelope)
  "Encode structured timeline ENVELOPE as bounded Base64 JSON."
  (let* ((json (json-serialize envelope))
         (payload (encode-coding-string json 'utf-8 t)))
    (when (> (string-bytes payload) (* 256 1024))
      (error "Structured aural presentation exceeds 262144 bytes"))
    (base64-encode-string payload t)))

(defun emacsvox-aural--finalize-structured-delivery
    (owner generation entries effects runs)
  "Replace eligible legacy ENTRIES with one structured timeline for OWNER."
  (if
      (not
       (and
        runs
        (eq owner tts-speaker-process)
        (cl-every #'emacsvox-aural--timeline-run-has-speech-p runs)
        (cl-every
         #'emacsvox-aural--structured-compatible-delivery-entry-p
         entries)))
      (list entries effects)
    (let* ((built
            (emacsvox-aural--build-structured-timeline
             generation 1 runs)))
      (if (not built)
          (list entries effects)
        (let* ((envelope (car built))
               (bindings (cadr built))
               (registration
                (tts--prepare-structured-dispatch
                 tts--marker-event-function
                 tts--tracked-completion-function
                 bindings))
               (actual-id (car registration)))
          (unless (= actual-id 1)
            (setq
             envelope
             (car
              (emacsvox-aural--build-structured-timeline
               generation actual-id runs))))
          (list
           (append
            (cl-remove-if
             (lambda (entry)
               (eq 'structured-fallback
                   (emacsvox-aural--delivery-entry-kind entry)))
             entries)
            (list
             (emacsvox-aural--make-delivery-entry
              :process owner :kind 'structured
              :command
              (format
               "emacsvox_timeline {%s}\n"
               (emacsvox-aural--encode-structured-timeline envelope)))))
           (append effects (list (cdr registration)))
           actual-id))))))

(defun emacsvox-aural-queue-concrete-action (action &optional context)
  "Queue concrete ACTION under frozen CONTEXT without resolving again."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue
     (when (emacsvox-aural-icons-enabled-p context)
       (let ((resource
              (emacsvox-aural-concrete-action-resource action))
             (balance
              (emacsvox-aural-concrete-action-balance action)))
         (if
             (and
              (numberp balance)
              (not (zerop balance))
              (functionp emacsvox-aural-queued-cue-balance-function))
             (funcall
              emacsvox-aural-queued-cue-balance-function
              resource balance)
           (emacsvox-queue-resource resource)))))
    ('pause
     (tts--protocol-silence
      (emacsvox-aural-concrete-action-duration action)))
    ('tone
     ;; Retain the old standalone force request as concrete metadata, but
     ;; never dispatch in the middle of an ordered plan.  The containing
     ;; presentation owns the safe dispatch boundary.
     (tts--protocol-tone
      (emacsvox-aural-concrete-action-pitch action)
      (emacsvox-aural-concrete-action-duration action)))
    ('speech
     (let ((command
            (emacsvox-aural-concrete-action-voice-command action))
           (balance
            (emacsvox-aural-concrete-action-balance action)))
       (when
           (and
            (numberp balance)
            (not (zerop balance))
            (functionp emacsvox-aural-speech-balance-function))
         (funcall emacsvox-aural-speech-balance-function balance))
       (when (and command (not (string-empty-p command)))
         (tts--protocol-queue-code command))
       (tts--protocol-queue-text
        (emacsvox-aural-concrete-action-text action))
       (when command
         (tts--protocol-queue-code (tts-voice-reset-code)))
       (when
           (and
            (numberp balance)
            (not (zerop balance))
            (functionp emacsvox-aural-speech-balance-function))
         (funcall emacsvox-aural-speech-balance-function 0.0))))))

(defun emacsvox-aural--utf8-offset-position (text offset)
  "Return the character position at UTF-8 byte OFFSET in TEXT."
  (unless
      (and (integerp offset) (>= offset 0) (<= offset (string-bytes text)))
    (emacsvox-aural--transport-error
     "Invalid positioned action offset %S for %S" offset text))
  (let ((position 0)
        (bytes 0)
        (length (length text)))
    (while (and (< bytes offset) (< position length))
      (setq
       bytes
       (+ bytes (string-bytes (substring text position (1+ position)))))
      (cl-incf position))
    (unless (= bytes offset)
      (emacsvox-aural--transport-error
       "Positioned action offset %S splits a UTF-8 character in %S"
       offset text))
    position))

(defun emacsvox-aural--queue-positioned-content
    (payload positioned-actions)
  "Queue PAYLOAD with compiled POSITIONED-ACTIONS at internal offsets."
  (let ((cursor 0)
        (previous-offset 0))
    (dolist (positioned positioned-actions)
      (let* ((offset (plist-get positioned :utf8-offset))
             (position
              (emacsvox-aural--utf8-offset-position payload offset)))
        (when (< offset previous-offset)
          (emacsvox-aural--transport-error
           "Positioned action offsets are not ordered: %S" positioned-actions))
        (when (> position cursor)
          (tts--protocol-queue-text (substring payload cursor position)))
        (dolist (entry (plist-get positioned :actions))
          (emacsvox-aural-queue-concrete-action
           (emacsvox-aural-concrete-positioned-action-action entry)
           (emacsvox-aural-concrete-positioned-action-context entry)))
        (setq cursor position
              previous-offset offset)))
    (when (< cursor (length payload))
      (tts--protocol-queue-text (substring payload cursor)))))

(defun emacsvox-aural--queue-concrete-content
    (content payload &optional positioned-actions)
  "Queue concrete CONTENT using PAYLOAD and POSITIONED-ACTIONS."
  (when
      (and
       (emacsvox-aural-concrete-content-speak content)
       payload
       (not (string-empty-p payload)))
    (tts--protocol-queue-code (tts-voice-reset-code))
    (let ((balance
           (emacsvox-aural-concrete-content-balance content)))
      (when
          (and
           (numberp balance)
           (not (zerop balance))
           (functionp emacsvox-aural-speech-balance-function))
        (funcall emacsvox-aural-speech-balance-function balance))
      (when-let* ((command
                   (emacsvox-aural-concrete-content-voice-command content)))
        (unless (string-empty-p command)
          (tts--protocol-queue-code command)))
      (if positioned-actions
          (emacsvox-aural--queue-positioned-content
           payload positioned-actions)
        (tts--protocol-queue-text payload))
      (when (emacsvox-aural-concrete-content-voice-command content)
        (tts--protocol-queue-code (tts-voice-reset-code)))
      (when
          (and
           (numberp balance)
           (not (zerop balance))
           (functionp emacsvox-aural-speech-balance-function))
        (funcall emacsvox-aural-speech-balance-function 0.0)))))

(defun emacsvox-aural--finish-concrete-plan
    (plan text text-supplied-p &optional pause)
  "Record and finish concrete PLAN after queueing.

TEXT is the final payload when TEXT-SUPPLIED-P is non-nil.  PAUSE is the
run's leading transport pause."
  (let ((emacsvox-aural--history-respect-icon-policy t))
    (if text-supplied-p
        (emacsvox-aural-record-presentation plan text pause)
      (emacsvox-aural-record-presentation plan)))
  (when
      (or
       (null (emacsvox-aural-concrete-plan-object-id plan))
       (emacsvox-aural-concrete-plan-object-end-p plan))
    (emacsvox-aural--defer-delivery-effect
     (lambda ()
       (run-hook-with-args 'emacsvox-aural-plan-presented-hook plan))))
  plan)

(defun emacsvox-aural--concrete-content-transport-key (content)
  "Return the speech-transport settings that distinguish CONTENT."
  (list
   (emacsvox-aural-concrete-content-speak content)
   (emacsvox-aural-concrete-content-voice-command content)
   (emacsvox-aural-concrete-content-balance content)))

(defun emacsvox-aural--coalescible-concrete-runs-p (left right)
  "Return non-nil when adjacent concrete runs LEFT and RIGHT can be joined.

Each run contains PLAN, final text, an optional leading pause, and optional
positioned actions."
  (pcase-let
      ((`(,left-plan ,left-text ,_ . ,left-extra) left)
       (`(,right-plan ,right-text ,right-pause . ,right-extra) right))
    (let ((left-content
           (emacsvox-aural-concrete-plan-content left-plan))
          (right-content
           (emacsvox-aural-concrete-plan-content right-plan))
          (left-positioned (car left-extra))
          (right-positioned (car right-extra)))
      (and
       (not right-pause)
       (stringp left-text)
       (not (string-empty-p left-text))
       (stringp right-text)
       (not (string-empty-p right-text))
       (null left-positioned)
       (null right-positioned)
       (emacsvox-aural-concrete-content-speak left-content)
       (emacsvox-aural-concrete-content-speak right-content)
       (emacsvox-aural-concrete-plan-object-id left-plan)
       (equal
        (emacsvox-aural-concrete-plan-object-id left-plan)
        (emacsvox-aural-concrete-plan-object-id right-plan))
       (null (emacsvox-aural-concrete-plan-after left-plan))
       (null (emacsvox-aural-concrete-plan-before right-plan))
       (equal
        (emacsvox-aural--concrete-content-transport-key left-content)
        (emacsvox-aural--concrete-content-transport-key right-content))))))

(defun emacsvox-aural--queue-concrete-run-group (runs)
  "Queue forward-ordered, transport-equivalent concrete RUNS together."
  (let* ((first (car runs))
         (last (car (last runs)))
         (first-plan (car first))
         (last-plan (car last))
         (payload
          (mapconcat
           (lambda (run) (nth 1 run))
           runs
           "")))
    (when-let* ((pause (nth 2 first)))
      (tts--protocol-silence pause))
    (dolist (action (emacsvox-aural-concrete-plan-before first-plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context first-plan)))
    (emacsvox-aural--queue-concrete-content
     (emacsvox-aural-concrete-plan-content first-plan)
     payload)
    (dolist (action (emacsvox-aural-concrete-plan-after last-plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context last-plan)))
    (dolist (run runs)
      (emacsvox-aural--finish-concrete-plan
       (car run) (nth 1 run) t (nth 2 run)))
    last-plan))

(defun emacsvox-aural-queue-concrete-runs (runs)
  "Queue adjacent concrete RUNS without artificial speech boundaries.

Each entry in RUNS contains PLAN, final text, an optional leading pause, and
optional positioned actions.  Adjacent runs are coalesced only within one
aural object when their effective speech transport settings match and no
action or pause separates them."
  (let* ((structured (emacsvox-aural--structured-capture-p))
         (emacsvox-aural--delivery-entry-kind
          (if structured 'structured-fallback
            emacsvox-aural--delivery-entry-kind))
         (emacsvox-aural--structured-runs-recorded-p structured)
         group previous)
    (when structured
      (dolist (run runs)
        (emacsvox-aural--capture-structured-run
         (car run) (nth 1 run) (nth 2 run) (nth 3 run))))
    (cl-labels
        ((flush
          ()
          (when group
            (setq group (nreverse group))
            (if (cdr group)
                (emacsvox-aural--queue-concrete-run-group group)
              (pcase-let ((`(,plan ,text ,pause . ,extra) (car group)))
                (when pause
                  (tts--protocol-silence pause))
                (let ((emacsvox-aural--queued-run-leading-pause pause))
                  (if (car extra)
                      (emacsvox-aural-queue-concrete-plan
                       plan text (car extra))
                    (emacsvox-aural-queue-concrete-plan plan text)))))
            (setq group nil
                  previous nil))))
      (dolist (run runs)
        (unless
            (and
             previous
             (emacsvox-aural--coalescible-concrete-runs-p previous run))
          (flush))
        (push run group)
        (setq previous run))
      (flush))))

(cl-defun emacsvox-aural-queue-concrete-plan
    (plan &optional (text nil text-supplied-p) positioned-actions)
  "Queue concrete PLAN in strict before, content, and after order.

When TEXT is supplied it replaces the plan's source text after normal TTS
cleanup, without rerunning semantic or contextual resolution.
POSITIONED-ACTIONS occur at UTF-8 offsets inside that final text."
  (let* ((structured (emacsvox-aural--structured-capture-p))
         (emacsvox-aural--delivery-entry-kind
          (if structured 'structured-fallback
            emacsvox-aural--delivery-entry-kind))
         (content (emacsvox-aural-concrete-plan-content plan))
         (payload
          (if text-supplied-p
              text
            (emacsvox-aural-concrete-content-text content))))
    (when (and structured (not emacsvox-aural--structured-runs-recorded-p))
      (emacsvox-aural--capture-structured-run
       plan payload emacsvox-aural--queued-run-leading-pause
       positioned-actions))
    (let ((context (emacsvox-aural-concrete-plan-context plan)))
      (dolist (action (emacsvox-aural-concrete-plan-before plan))
        (emacsvox-aural-queue-concrete-action action context)))
    (emacsvox-aural--queue-concrete-content
     content payload positioned-actions)
    (dolist (action (emacsvox-aural-concrete-plan-after plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context plan)))
    (emacsvox-aural--finish-concrete-plan
     plan payload text-supplied-p
     emacsvox-aural--queued-run-leading-pause)))

(defun emacsvox-aural--standalone-cue (plan)
  "Return PLAN's one standalone cue action, or nil."
  (let* ((actions
          (append
           (emacsvox-aural-concrete-plan-before plan)
           (emacsvox-aural-concrete-plan-after plan)))
         (content (emacsvox-aural-concrete-plan-content plan)))
    (when
        (and
         (= (length actions) 1)
         (eq
          (emacsvox-aural-concrete-action-kind (car actions))
          'cue)
         (not (emacsvox-aural-concrete-content-text content)))
      (car actions))))

(defun emacsvox-aural--ensure-speaker ()
  "Ensure the TTS process needed for ordered plans is available."
  (unless
      (and
       (boundp 'tts-speaker-process)
       (process-live-p tts-speaker-process))
    (tts-initialize)))

(defun emacsvox-aural--concrete-action-output-p (action context)
  "Return non-nil when concrete ACTION produces output under CONTEXT."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue (emacsvox-aural-icons-enabled-p context))
    ((or 'pause 'speech 'tone) t)
    (_ nil)))

(defun emacsvox-aural--concrete-plan-output-p (plan)
  "Return non-nil when concrete PLAN has output under its frozen policy."
  (let* ((context (emacsvox-aural-concrete-plan-context plan))
         (content (emacsvox-aural-concrete-plan-content plan))
         (text (emacsvox-aural-concrete-content-text content)))
    (or
     (cl-some
      (lambda (action)
        (emacsvox-aural--concrete-action-output-p action context))
      (append
       (emacsvox-aural-concrete-plan-before plan)
       (emacsvox-aural-concrete-plan-after plan)))
     (and
      (emacsvox-aural-concrete-content-speak content)
      (stringp text)
      (not (string-empty-p text))))))

(defun emacsvox-aural-present-legacy-icon (icon &optional context)
  "Present legacy ICON through concrete transport.
Resolve it using CONTEXT or the dynamically captured submission context."
  (pcase-let*
      ((context
        (or
         context
         (emacsvox-aural-capture-context
          nil
          (or emacsvox-aural-submission-occasion 'notification))))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input
         icon emacsvox-aural-submission-facts context))
       (render
        (emacsvox-aural-resolve-legacy-icon icon context facts))
       (local-cue-p
        (let ((actions
               (append
                (emacsvox-aural-render-plan-before render)
                (emacsvox-aural-render-plan-after render))))
          (and
           (= (length actions) 1)
           (eq (emacsvox-aural-action-kind (car actions)) 'cue)
           (not (plist-get facts :content)))))
       (plan
        (emacsvox-aural-compile-plan
         render facts context
         (if local-cue-p 'local-cue 'queued-cue)))
       (cue (emacsvox-aural--standalone-cue plan))
       (icons-enabled
        (emacsvox-aural-icons-enabled-p
         (emacsvox-aural-concrete-plan-context plan))))
    (cond
     ((and cue icons-enabled)
      (let ((balance
             (emacsvox-aural-concrete-action-balance cue)))
        (if (and (numberp balance) (not (zerop balance)))
            (emacsvox-sounds-play-concrete-cue
             (emacsvox-aural-concrete-action-resource cue)
             (emacsvox-aural-concrete-action-sample-id cue)
             balance)
          (emacsvox-sounds-play-concrete-cue
           (emacsvox-aural-concrete-action-resource cue)
           (emacsvox-aural-concrete-action-sample-id cue))))
      (emacsvox-aural-record-presentation plan)
      (when emacsvox-aural-plan-presented-hook
        (emacsvox-aural--ensure-speaker)
        (run-hook-with-args
         'emacsvox-aural-plan-presented-hook plan)
        (tts--protocol-dispatch)))
     (cue nil)
     ((or
       (emacsvox-aural-concrete-plan-before plan)
       (emacsvox-aural-concrete-plan-after plan))
      (emacsvox-aural--ensure-speaker)
      (emacsvox-aural-queue-concrete-plan plan)
      (tts--protocol-dispatch)))
    plan))

(defun emacsvox-aural-queue-legacy-icon (icon &optional context)
  "Resolve and queue legacy ICON concretely without dispatching.
Use CONTEXT when supplied, otherwise capture the submission context."
  (pcase-let*
      ((context
        (or
         context
         emacsvox-aural-submission-context
         (emacsvox-aural-capture-context nil 'continuous)))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input
         icon emacsvox-aural-submission-facts context))
       (plan
        (emacsvox-aural-compile-plan
         (emacsvox-aural-resolve-legacy-icon icon context facts)
         facts context)))
    (emacsvox-aural-queue-concrete-plan plan)))

(defun emacsvox-aural-present (facts &optional context compatibility-actions)
  "Resolve, compile, queue, and dispatch semantic FACTS in CONTEXT.

COMPATIBILITY-ACTIONS are normalized source adapter records merged around the
semantic plan without resolving the semantic object more than once."
  (let* ((context
          (or
           context
           (emacsvox-aural-capture-context nil 'notification)))
         (plan
          (emacsvox-aural-compile-plan
           (emacsvox-aural--merge-object-compatibility
            (emacsvox-aural-resolve-active facts context)
            compatibility-actions facts context)
           facts context)))
    (when (emacsvox-aural--concrete-plan-output-p plan)
      (emacsvox-aural--ensure-speaker)
      (emacsvox-aural-call-with-delivery-transaction
       tts-speaker-process
       (lambda ()
         (emacsvox-aural-queue-concrete-plan plan)
         (tts--protocol-dispatch))))
    plan))

(provide 'emacsvox-aural-transport)
;;; emacsvox-aural-transport.el ends here
