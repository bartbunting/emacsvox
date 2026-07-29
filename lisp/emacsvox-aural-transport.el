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
     (tts--protocol-tone
      (emacsvox-aural-concrete-action-pitch action)
      (emacsvox-aural-concrete-action-duration action)
      (emacsvox-aural-concrete-action-force action)))
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

(defun emacsvox-aural-present (facts &optional context)
  "Resolve, compile, queue, and dispatch semantic FACTS in CONTEXT."
  (let* ((context
          (or
           context
           (emacsvox-aural-capture-context nil 'notification)))
         (plan
          (emacsvox-aural-compile-plan
           (emacsvox-aural-resolve-active facts context)
           facts context)))
    (emacsvox-aural--ensure-speaker)
    (emacsvox-aural-queue-concrete-plan plan)
    (tts--protocol-dispatch)
    plan))

(provide 'emacsvox-aural-transport)
;;; emacsvox-aural-transport.el ends here
