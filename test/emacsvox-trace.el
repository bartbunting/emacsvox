;;; emacsvox-trace.el --- Semantic speech event traces -*- lexical-binding: t; -*-

;;; Commentary:

;; Record deterministic speech, auditory icon, tone, silence, rate, stop, and
;; message events without starting a speech server.  The scenario runner also
;; captures editor state for behavioural comparisons.

;;; Code:

(require 'cl-lib)

(defvar emacsvox-trace--events nil
  "Events accumulated by the active trace capture.")

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

(defun emacsvox-trace--speak (text)
  "Record a semantic speech event for TEXT."
  (when text
    (unless (stringp text)
      (setq text (format "%s" text)))
    (unless (string-empty-p text)
      (emacsvox-trace--record
       'speak (emacsvox-trace--speech-description text)))))

(defun emacsvox-trace--message (format-string &rest arguments)
  "Record FORMAT-STRING formatted with ARGUMENTS and return the message."
  (when format-string
    (let ((text (apply #'format-message format-string arguments)))
      (emacsvox-trace--record 'message (substring-no-properties text))
      text)))

(defun emacsvox-trace-capture (thunk)
  "Call THUNK while recording semantic output and return a result plist.

The result contains =:value= and chronological =:events=.  Low-level output
functions are replaced temporarily, so no speech server or sound player is
used."
  (let (emacsvox-trace--events value)
    (cl-letf (((symbol-function 'dtk-speak) #'emacsvox-trace--speak)
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (emacsvox-trace--record 'icon icon)))
              ((symbol-function 'emacspeak-icon)
               (lambda (icon) (emacsvox-trace--record 'icon icon)))
              ((symbol-function 'dtk-stop)
               (lambda (&optional all)
                 (emacsvox-trace--record 'stop all)))
              ((symbol-function 'dtk-tone)
               (lambda (pitch duration &optional force)
                 (emacsvox-trace--record
                  'tone pitch duration force)))
              ((symbol-function 'dtk-silence)
               (lambda (duration &optional force)
                 (emacsvox-trace--record 'silence duration force)))
              ((symbol-function 'dtk-set-rate)
               (lambda (rate &optional prefix)
                 (emacsvox-trace--record 'rate rate prefix)))
              ((symbol-function 'message) #'emacsvox-trace--message))
      (setq value (funcall thunk)))
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
            (let* ((this-command command)
                   (real-this-command command)
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
                :modified (buffer-modified-p))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(provide 'emacsvox-trace)
;;; emacsvox-trace.el ends here
