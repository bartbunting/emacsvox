;;; emacsvox-aural-transport.el --- Concrete aural transport -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Queue backend-ready ordered actions through speech and sound transports,
;; and expose the immediate and compatibility presentation entry points.

;;; Code:

(require 'cl-lib)
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
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-silence "tts-speak" (duration &optional force))
(declare-function tts--protocol-tone "tts-speak" (pitch duration &optional force))
(declare-function tts-initialize "tts-speak" ())
(declare-function tts-voice-reset-code "tts-speak" ())

(defvar tts-speaker-process)

(defvar emacsvox-aural--queued-run-leading-pause nil
  "Leading pause retained while queueing one concrete formatting run.")

(cl-defstruct
    (emacsvox-aural--delivery-entry
     (:constructor emacsvox-aural--make-delivery-entry))
  "One server command captured inside a complete delivery transaction."
  process command)

(cl-defstruct
    (emacsvox-aural--pending-delivery
     (:constructor emacsvox-aural--make-pending-delivery))
  "One replaceable delivery waiting for an input-idle boundary."
  sequence owner replacement-key entries timer)

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

(defvar emacsvox-aural--pending-deliveries
  (make-hash-table :test #'equal)
  "Replaceable server transactions indexed by owner and replacement key.")

(defvar emacsvox-aural--delivery-sequence 0
  "Sequence preserving order across independent replacement keys.")

(defconst emacsvox-aural--framed-delivery-process-property
  'emacsvox-aural-framed-delivery
  "Process property enabling complete replaceable transaction framing.")

(defun emacsvox-aural-enable-framed-delivery (process)
  "Enable complete replaceable transaction framing for PROCESS."
  (process-put
   process emacsvox-aural--framed-delivery-process-property t)
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
        :process process :command command)
       emacsvox-aural--delivery-transaction-entries)
    (process-send-string process command)))

(defun emacsvox-aural--framed-delivery-entries
    (owner generation entries)
  "Frame replaceable ENTRIES for OWNER at GENERATION when supported."
  (if
      (and
       generation
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

(defun emacsvox-aural--send-delivery-entries
    (entries &optional owner generation)
  "Send ordered delivery ENTRIES, combining adjacent writes per process."
  (setq
   entries
   (emacsvox-aural--framed-delivery-entries
    owner generation entries))
  (let (current-process commands)
    (cl-labels
        ((flush
          ()
          (when current-process
            (unless
                (and
                 (processp current-process)
                 (not (process-live-p current-process)))
              (process-send-string
               current-process (apply #'concat (nreverse commands)))))
          (setq current-process nil commands nil)))
      (dolist (entry entries)
        (let ((process (emacsvox-aural--delivery-entry-process entry))
              (command (emacsvox-aural--delivery-entry-command entry)))
          (unless (eq process current-process)
            (flush)
            (setq current-process process))
          (push command commands)))
      (flush))))

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
    (emacsvox-aural--send-delivery-entries
     (emacsvox-aural--pending-delivery-entries pending)
     (emacsvox-aural--pending-delivery-owner pending)
     (emacsvox-aural--pending-delivery-sequence pending))))

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
    (owner replacement-key entries)
  "Schedule ENTRIES for OWNER under REPLACEMENT-KEY, replacing older work."
  (let* ((table-key
          (emacsvox-aural--pending-delivery-table-key
           owner replacement-key))
         (pending
          (emacsvox-aural--make-pending-delivery
           :sequence (cl-incf emacsvox-aural--delivery-sequence)
           :owner owner
           :replacement-key replacement-key
           :entries entries)))
    (emacsvox-aural-cancel-pending-deliveries owner replacement-key)
    (puthash table-key pending emacsvox-aural--pending-deliveries)
    (setf
     (emacsvox-aural--pending-delivery-timer pending)
     (run-with-idle-timer
      emacsvox-aural-replacement-idle-delay nil
      #'emacsvox-aural--deliver-pending table-key))))

(defun emacsvox-aural--submit-delivery-entries (owner entries)
  "Submit complete protocol ENTRIES for OWNER under current source policy."
  (when entries
    (pcase (or emacsvox-aural-submission-delivery-policy 'ordered)
      ('replaceable
       (emacsvox-aural--schedule-replaceable-delivery
        owner emacsvox-aural-submission-replacement-key entries))
      ('urgent
       (emacsvox-aural-cancel-pending-deliveries owner)
       (emacsvox-aural--send-delivery-entries entries))
      (_
       (emacsvox-aural-flush-pending-deliveries owner)
       (emacsvox-aural--send-delivery-entries entries)))))

(defun emacsvox-aural-call-with-delivery-transaction
    (owner function &rest arguments)
  "Call FUNCTION with ARGUMENTS and deliver its server writes for OWNER.

Nested calls join the enclosing transaction.  The outer source submission's
delivery policy determines whether the complete captured payload is sent now
or supersedes an older pending payload."
  (if emacsvox-aural--delivery-transaction-active-p
      (apply function arguments)
    (let ((emacsvox-aural--delivery-transaction-active-p t)
          (emacsvox-aural--delivery-transaction-entries nil)
          result)
      (when (eq emacsvox-aural-submission-delivery-policy 'replaceable)
        (emacsvox-aural-cancel-pending-deliveries
         owner emacsvox-aural-submission-replacement-key))
      (when (eq emacsvox-aural-submission-delivery-policy 'urgent)
        (emacsvox-aural-cancel-pending-deliveries owner))
      (setq result (apply function arguments))
      (emacsvox-aural--submit-delivery-entries
       owner (nreverse emacsvox-aural--delivery-transaction-entries))
      result)))

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

(defun emacsvox-aural--queue-concrete-content (content payload)
  "Queue concrete CONTENT using final text PAYLOAD."
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
      (tts--protocol-queue-text payload)
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
    (run-hook-with-args 'emacsvox-aural-plan-presented-hook plan))
  plan)

(defun emacsvox-aural--concrete-content-transport-key (content)
  "Return the speech-transport settings that distinguish CONTENT."
  (list
   (emacsvox-aural-concrete-content-speak content)
   (emacsvox-aural-concrete-content-voice-command content)
   (emacsvox-aural-concrete-content-balance content)))

(defun emacsvox-aural--coalescible-concrete-runs-p (left right)
  "Return non-nil when adjacent concrete runs LEFT and RIGHT can be joined.

Each run is a list of PLAN, final text, and an optional leading pause."
  (pcase-let
      ((`(,left-plan ,left-text ,_) left)
       (`(,right-plan ,right-text ,right-pause) right))
    (let ((left-content
           (emacsvox-aural-concrete-plan-content left-plan))
          (right-content
           (emacsvox-aural-concrete-plan-content right-plan)))
      (and
       (not right-pause)
       (stringp left-text)
       (not (string-empty-p left-text))
       (stringp right-text)
       (not (string-empty-p right-text))
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

Each entry in RUNS is a list of PLAN, final text, and an optional leading
pause.  Adjacent runs are coalesced only within one aural object when their
effective speech transport settings match and no action or pause separates
them."
  (let (group previous)
    (cl-labels
        ((flush
          ()
          (when group
            (setq group (nreverse group))
            (if (cdr group)
                (emacsvox-aural--queue-concrete-run-group group)
              (pcase-let ((`(,plan ,text ,pause) (car group)))
                (when pause
                  (tts--protocol-silence pause))
                (let ((emacsvox-aural--queued-run-leading-pause pause))
                  (emacsvox-aural-queue-concrete-plan plan text))))
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
    (plan &optional (text nil text-supplied-p))
  "Queue concrete PLAN in strict before, content, and after order.

When TEXT is supplied it replaces the plan's source text after normal TTS
cleanup, without rerunning semantic or contextual resolution."
  (let ((context (emacsvox-aural-concrete-plan-context plan)))
    (dolist (action (emacsvox-aural-concrete-plan-before plan))
      (emacsvox-aural-queue-concrete-action action context)))
  (let* ((content (emacsvox-aural-concrete-plan-content plan))
         (payload
         (if text-supplied-p
              text
            (emacsvox-aural-concrete-content-text content))))
    (emacsvox-aural--queue-concrete-content content payload)
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
