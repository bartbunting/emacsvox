;;; emacsvox-trace.el --- Semantic speech event traces -*- lexical-binding: t; -*-

;;; Commentary:

;; Record deterministic speech, auditory icon, tone, silence, rate, stop, and
;; message events without starting a speech server.  The scenario runner also
;; captures editor state for behavioural comparisons.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar emacsvox-trace--events nil
  "Events accumulated by the active trace capture.")

(defvar emacsvox-trace--native-interruption-recorded-p nil
  "Non-nil after recording interruption for one native submission.")

(defvar tts-speaker-process)

(defun emacsvox-trace--record (kind &rest values)
  "Record an event of KIND containing VALUES."
  (push (cons kind values) emacsvox-trace--events))

(defun emacsvox-trace--personality-runs (text)
  "Return non-empty personality spans from TEXT."
  (let ((length (length text))
        (position 0)
        runs)
    (while (< position length)
      (let* ((personality (get-text-property position 'personality text))
             (next
              (or
               (next-single-property-change
                position 'personality text length)
               length)))
        (when personality
          (push (list position next personality) runs))
        (setq position next)))
    (nreverse runs)))

(defun emacsvox-trace--speech-description (text)
  "Return a stable semantic description of speech TEXT."
  (unless (stringp text)
    (setq text (format "%s" text)))
  (let ((description (list :text (substring-no-properties text)))
        (personalities (emacsvox-trace--personality-runs text)))
    (when personalities
      (setq description
            (append description (list :personalities personalities))))
    description))

(defun emacsvox-trace--concrete-action (action)
  "Record one first-class concrete aural ACTION."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue
     (emacsvox-trace--record
      'icon
      (or
       (emacsvox-aural-concrete-action-cue action)
       (emacsvox-aural-concrete-action-sample-id action))))
    ('pause
     (emacsvox-trace--record
      'silence (emacsvox-aural-concrete-action-duration action) nil))
    ('tone
     (emacsvox-trace--record
      'tone
      (emacsvox-aural-concrete-action-pitch action)
      (emacsvox-aural-concrete-action-duration action)
      (and (emacsvox-aural-concrete-action-force action) 'force)))
    ('speech
     (emacsvox-trace--record
      'speak
      (emacsvox-trace--speech-description
       (emacsvox-aural-concrete-action-text action))))))

(defun emacsvox-trace--native-interruption ()
  "Record native submission interruption once when it owns that policy."
  (when
      (and
       (boundp 'emacsvox-aural-submission-controls-interruption)
       emacsvox-aural-submission-controls-interruption
       (boundp 'emacsvox-aural-submission-delivery-policy)
       (memq
        emacsvox-aural-submission-delivery-policy
        '(replaceable urgent))
       (not emacsvox-trace--native-interruption-recorded-p))
    (setq emacsvox-trace--native-interruption-recorded-p t)
    (emacsvox-trace--record 'stop 'all)))

(defun emacsvox-trace--speak (text)
  "Record a semantic speech event for TEXT."
  (when text
    (unless (stringp text)
      (setq text (format "%s" text)))
    (unless (string-empty-p text)
      (let ((first-plan
             (and
              (boundp 'emacsvox-aural-concrete-plan-property)
              (get-text-property
               0 emacsvox-aural-concrete-plan-property text))))
        (if (not first-plan)
            (emacsvox-trace--record
             'speak (emacsvox-trace--speech-description text))
          (emacsvox-trace--native-interruption)
          (let ((position 0)
                pending-speech)
            (cl-labels
                ((flush-speech
                  ()
                  (when pending-speech
                    (emacsvox-trace--record
                     'speak
                     (emacsvox-trace--speech-description pending-speech))
                    (setq pending-speech nil))))
              (while (< position (length text))
                (let* ((plan
                        (get-text-property
                         position emacsvox-aural-concrete-plan-property text))
                       (next
                        (next-single-property-change
                         position emacsvox-aural-concrete-plan-property
                         text (length text)))
                       (before (emacsvox-aural-concrete-plan-before plan))
                       (after (emacsvox-aural-concrete-plan-after plan))
                       (speak
                        (emacsvox-aural-concrete-content-speak
                         (emacsvox-aural-concrete-plan-content plan))))
                  (when before (flush-speech))
                  (dolist (action before)
                    (emacsvox-trace--concrete-action action))
                  (if speak
                      (setq
                       pending-speech
                       (concat
                        pending-speech (substring text position next)))
                    (flush-speech))
                  (when after (flush-speech))
                  (dolist (action after)
                    (emacsvox-trace--concrete-action action))
                  (setq position next)))
              (flush-speech))))))))

(defun emacsvox-trace--message (original format-string &rest arguments)
  "Record a message, then call ORIGINAL with FORMAT-STRING and ARGUMENTS."
  (when format-string
    (let ((text (apply #'format-message format-string arguments)))
      (emacsvox-trace--record 'message (substring-no-properties text))))
  (apply original format-string arguments))

(defun emacsvox-trace--call-with-aural-output-capture
    (thunk original-process-live-p)
  "Call THUNK while capturing first-class aural output.

Use ORIGINAL-PROCESS-LIVE-P for processes other than the trace speaker.
Legacy implementations without concrete aural actions call THUNK directly."
  (if
      (not (fboundp 'emacsvox-aural-queue-concrete-action))
      (funcall thunk)
    (let ((queue-action
           (symbol-function 'emacsvox-aural-queue-concrete-action))
          (tts-speaker-process 'emacsvox-trace-speaker))
      (cl-letf
          (((symbol-function 'process-live-p)
            (lambda (process)
              (if (eq process 'emacsvox-trace-speaker)
                  t
                (funcall original-process-live-p process))))
           ((symbol-function 'tts--protocol-dispatch) #'ignore)
           ((symbol-function 'tts--interrupt-process)
            (lambda (_process &optional notifications)
              (emacsvox-trace--record
               'stop (and notifications 'all))))
           ((symbol-function 'emacsvox-aural-queue-concrete-action)
            (lambda (action &optional context)
              (pcase (emacsvox-aural-concrete-action-kind action)
                ((or 'cue 'pause 'tone 'speech)
                 (emacsvox-trace--native-interruption)
                 (emacsvox-trace--concrete-action action))
                (_ (funcall queue-action action context))))))
        (funcall thunk)))))

(defun emacsvox-trace-capture (thunk)
  "Call THUNK while recording semantic output and return a result plist.

The result contains =:value= and chronological =:events=.  Low-level output
functions are replaced temporarily, so no speech server or sound player is
used."
  (let ((original-message (symbol-function 'message))
        (original-process-live-p (symbol-function 'process-live-p))
        emacsvox-trace--events
        emacsvox-trace--native-interruption-recorded-p
        value)
    (cl-letf (((symbol-function 'tts-speak) #'emacsvox-trace--speak)
              ((symbol-function 'tts-letter)
               (lambda (letter)
                 (emacsvox-trace--record
                  'letter (substring-no-properties letter))))
              ((symbol-function 'tts-dispatch)
               (lambda (string)
                 (emacsvox-trace--record
                  'dispatch (substring-no-properties string))))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (emacsvox-trace--record 'icon icon)))
              ((symbol-function 'emacspeak-icon)
               (lambda (icon) (emacsvox-trace--record 'icon icon)))
              ((symbol-function 'tts-stop)
               (lambda (&optional all)
                 (emacsvox-trace--record 'stop all)))
              ((symbol-function 'tts-tone)
               (lambda (pitch duration &optional force)
                 (emacsvox-trace--record
                  'tone pitch duration force)))
              ((symbol-function 'tts-silence)
               (lambda (duration &optional force)
                 (emacsvox-trace--record 'silence duration force)))
              ((symbol-function 'tts-set-rate)
               (lambda (rate &optional prefix)
                 (emacsvox-trace--record 'rate rate prefix)))
              ((symbol-function 'tts-notify)
               (lambda (text &optional dont-log)
                 (emacsvox-trace--record
                  'notify
                  (emacsvox-trace--speech-description text)
                  dont-log)
                 text))
              ((symbol-function 'tts-notify-icon)
               (lambda (icon)
                 (emacsvox-trace--record 'notify-icon icon)))
              ((symbol-function 'tts-notify-stop)
               (lambda () (emacsvox-trace--record 'notify-stop)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (apply
                  #'emacsvox-trace--message
                  original-message format-string arguments))))
      (setq
       value
       (emacsvox-trace--call-with-aural-output-capture
        thunk original-process-live-p)))
    (list :value value :events (nreverse emacsvox-trace--events))))

(defun emacsvox-trace-normalize-value (value &optional scenario-buffer)
  "Make VALUE stable for a trace associated with SCENARIO-BUFFER."
  (cond
   ((bufferp value)
    (if (eq value scenario-buffer)
        'scenario-buffer
      (list 'buffer (buffer-name value))))
   ((markerp value) (marker-position value))
   ((windowp value) 'window)
   ((stringp value) (substring-no-properties value))
   ((consp value)
    (cons
     (emacsvox-trace-normalize-value (car value) scenario-buffer)
     (emacsvox-trace-normalize-value (cdr value) scenario-buffer)))
   ((vectorp value)
    (apply
     #'vector
     (mapcar
      (lambda (item)
        (emacsvox-trace-normalize-value item scenario-buffer))
      value)))
   ((hash-table-p value) 'hash-table)
   (t value)))

(cl-defun emacsvox-trace-run-scenario
    (&key name command arguments interactive (text "") (point 1) mark
          ((:mark-active initial-mark-active) nil)
          (mode 'fundamental-mode))
  "Run a deterministic editor scenario and return its semantic trace.

NAME labels the scenario.  COMMAND is called with ARGUMENTS, using
`funcall-interactively' when INTERACTIVE is non-nil.  TEXT, POINT, MARK,
MARK-ACTIVE, and MODE describe the initial buffer state."
  (unless command
    (error "A scenario command is required"))
  (let ((buffer (generate-new-buffer " *emacsvox-trace*")))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (funcall mode)
            (insert text)
            (goto-char point)
            (when mark (set-mark mark))
            (setq mark-active initial-mark-active)
            (set-buffer-modified-p nil)
            (let* ((this-command command)
                   (real-this-command command)
                   (kill-ring nil)
                   (kill-ring-yank-pointer nil)
                   (capture
                    (emacsvox-trace-capture
                     (lambda ()
                       (if interactive
                           (apply #'funcall-interactively command arguments)
                         (apply command arguments))))))
              (list
               :name name
               :events (plist-get capture :events)
               :value
               (emacsvox-trace-normalize-value
                (plist-get capture :value) buffer)
               :state
               (list
                :text (buffer-substring-no-properties (point-min) (point-max))
                :point (point)
                :mark (mark t)
                :mark-active mark-active
                :modified (buffer-modified-p)
                :kill-ring
                (emacsvox-trace-normalize-value kill-ring buffer))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(provide 'emacsvox-trace)
;;; emacsvox-trace.el ends here
