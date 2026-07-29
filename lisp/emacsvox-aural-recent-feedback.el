;;; emacsvox-aural-recent-feedback.el --- Browse frozen feedback -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Spoken browsing, replay, inspection, and remapping of exact retained aural
;; presentations.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-explanation)
(require 'emacsvox-aural-description)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defun emacsvox-aural-recent-feedback--record (&optional id)
  "Return the retained feedback record for optional row ID."
  (let ((id
         (or id
             (tabulated-list-get-id)
             (user-error "Move to a recent feedback row first"))))
    (or
     (cl-find
      id emacsvox-aural-presentation-history
      :key #'emacsvox-aural-presentation-record-id
      :test #'eql)
     (user-error
      "Feedback record %s has expired; press g to refresh" id))))

(defun emacsvox-aural-recent-feedback--actions (record)
  "Return the ordered before and after actions from RECORD."
  (cl-mapcan
   (lambda (plan)
     (append
      (copy-sequence (emacsvox-aural-concrete-plan-before plan))
      (copy-sequence (emacsvox-aural-concrete-plan-after plan))))
   (emacsvox-aural-presentation-record-effective-plans record)))

(defun emacsvox-aural-recent-feedback--cues (record)
  "Return the concrete cue actions from RECORD."
  (cl-remove-if-not
   (lambda (action)
     (eq (emacsvox-aural-concrete-action-kind action) 'cue))
   (emacsvox-aural-recent-feedback--actions record)))

(defun emacsvox-aural-recent-feedback--tones (record)
  "Return the concrete tone actions from RECORD."
  (cl-remove-if-not
   (lambda (action)
     (eq (emacsvox-aural-concrete-action-kind action) 'tone))
   (emacsvox-aural-recent-feedback--actions record)))

(defun emacsvox-aural-recent-feedback--clean-text (text &optional width)
  "Return single-line TEXT, optionally truncated to WIDTH."
  (let ((text
         (string-trim
          (replace-regexp-in-string
           "[[:space:]\n\r]+" " " (or text "")))))
    (if (and width (> (string-width text) width))
        (truncate-string-to-width text width nil nil "...")
      text)))

(defun emacsvox-aural-recent-feedback--content (record)
  "Return a concise description of RECORD's exact content."
  (let* ((plans
          (emacsvox-aural-presentation-record-effective-plans record))
         (contents
          (mapcar #'emacsvox-aural-concrete-plan-content plans))
         (text
          (emacsvox-aural-recent-feedback--clean-text
           (mapconcat
            (lambda (content)
              (or (emacsvox-aural-concrete-content-text content) ""))
            contents
            "")
           72))
         (speech
          (cl-remove-if-not
           (lambda (action)
             (eq (emacsvox-aural-concrete-action-kind action) 'speech))
           (emacsvox-aural-recent-feedback--actions record))))
    (cond
     ((and
       (cl-some #'emacsvox-aural-concrete-content-speak contents)
       (not (string-empty-p text)))
      text)
     ((not (string-empty-p text))
      (format "Content suppressed: %s" text))
     (speech
      (format
       "Speech: %s"
       (mapconcat
        (lambda (action)
          (emacsvox-aural-recent-feedback--clean-text
           (emacsvox-aural-concrete-action-text action)))
        speech ", ")))
     ((emacsvox-aural-recent-feedback--cues record) "Earcon only")
     ((emacsvox-aural-recent-feedback--tones record)
      (format
       "Tone: %s"
       (mapconcat
        (lambda (action)
          (emacsvox-aural-humanize
           (emacsvox-aural-concrete-action-tone action)))
        (emacsvox-aural-recent-feedback--tones record)
        ", ")))
     ((cl-some
       (lambda (action)
         (eq (emacsvox-aural-concrete-action-kind action) 'pause))
       (emacsvox-aural-recent-feedback--actions record))
      "Pause only")
     (t "No audible output"))))

(defun emacsvox-aural-recent-feedback--voice (record)
  "Return a concise exact voice description for RECORD."
  (let* ((contents
          (mapcar
           #'emacsvox-aural-concrete-plan-content
           (emacsvox-aural-presentation-record-effective-plans record)))
         (content (car contents))
         (requests
          (delete-dups
           (mapcar
            #'emacsvox-aural-concrete-content-voice-request
            contents)))
         (request
          (emacsvox-aural-concrete-content-voice-request content)))
    (cond
     ((cdr requests)
      (format "%d voices" (length requests)))
     ((not
       (cl-some #'emacsvox-aural-concrete-content-speak contents))
      "suppressed")
     ((null request) "default")
     ((symbolp request) (emacsvox-aural-humanize request))
     ((emacsvox-aural-voice-style-p request)
      (cond
       ((plist-get request :preset)
        (format
         "%s preset"
         (emacsvox-aural-humanize
          (plist-get request :preset))))
       ((plist-get request :family)
        (format
         "%s base voice"
         (emacsvox-aural-humanize
          (plist-get request :family))))
       (t "custom voice")))
     (t (format "%s" request)))))

(defun emacsvox-aural-recent-feedback--cue-summary (record)
  "Return the ordered earcon names from RECORD."
  (if-let* ((cues (emacsvox-aural-recent-feedback--cues record)))
      (mapconcat
       (lambda (action)
         (emacsvox-aural-humanize
          (emacsvox-aural-concrete-action-cue action)))
       cues ", ")
    "none"))

(defun emacsvox-aural-recent-feedback--semantic-fallback-count (record)
  "Return the number of semantic fallback matches retained in RECORD."
  (cl-loop
   for plan in
   (emacsvox-aural-presentation-record-effective-plans record)
   sum
   (cl-loop
    for rule in (emacsvox-aural-concrete-plan-rule-provenance plan)
    sum
    (cl-count-if
     (lambda (detail)
       (let ((distance (plist-get detail :distance)))
         (and (numberp distance) (> distance 0))))
     (plist-get rule :semantic-matches)))))

(defun emacsvox-aural-recent-feedback--status (record)
  "Return fallback and degradation status for RECORD."
  (let* ((degradations
          (cl-loop
           for plan in
           (emacsvox-aural-presentation-record-effective-plans record)
           sum
           (length (emacsvox-aural-concrete-plan-degradations plan))))
         (fallbacks
          (emacsvox-aural-recent-feedback--semantic-fallback-count
           record))
         parts)
    (when (> degradations 0)
      (push
       (format
        "%d %s"
        degradations
        (if (= degradations 1) "degradation" "degradations"))
       parts))
    (when (> fallbacks 0)
      (push
       (format
        "%d semantic %s"
        fallbacks
        (if (= fallbacks 1) "fallback" "fallbacks"))
       parts))
    (if parts
        (string-join (nreverse parts) ", ")
      "ok")))

(defun emacsvox-aural-recent-feedback--entry (record)
  "Return a tabulated-list entry for RECORD."
  (let* ((plan (emacsvox-aural-presentation-record-plan record))
         (facts (emacsvox-aural-concrete-plan-facts plan))
         (context (emacsvox-aural-concrete-plan-context plan)))
    (list
     (emacsvox-aural-presentation-record-id record)
     (vector
      (emacsvox-aural-recent-feedback--content record)
      (emacsvox-aural-explanation-facts-description facts context)
      (emacsvox-aural-recent-feedback--clean-text
       (or
        (emacsvox-aural-presentation-record-source-buffer-name record)
        "unknown"))
      (emacsvox-aural-humanize
       (or (plist-get context :occasion) 'unknown))
      (emacsvox-aural-recent-feedback--voice record)
      (emacsvox-aural-recent-feedback--cue-summary record)
      (emacsvox-aural-recent-feedback--status record)
      (format-time-string
       "%H:%M:%S"
       (emacsvox-aural-presentation-record-queued-at record))))))

(defun emacsvox-aural-recent-feedback--entries ()
  "Return newest-first tabulated entries for retained feedback."
  (mapcar
   #'emacsvox-aural-recent-feedback--entry
   emacsvox-aural-presentation-history))

(defun emacsvox-aural-recent-feedback-refresh (&optional id)
  "Refresh recent feedback, preserving optional record ID."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq
      tabulated-list-entries
      (emacsvox-aural-recent-feedback--entries)))
   id
   (when-let* ((record (car emacsvox-aural-presentation-history)))
     (emacsvox-aural-presentation-record-id record))))

(defun emacsvox-aural-tools--speak-history-setting (text)
  "Speak history setting TEXT without recording that announcement."
  (let ((emacsvox-aural-submission-context
         (plist-put
          (emacsvox-aural-capture-context
           'aural-tools 'state-change)
          :history-recording-inhibited t)))
    (if (fboundp 'tts-speak)
        (tts-speak text)
      (message "%s" text)))
  text)

(defun emacsvox-aural-toggle-interface-history-recording ()
  "Toggle retention of presentations originating inside Aural interfaces."
  (interactive)
  (setq
   emacsvox-aural-history-record-interface-presentations
   (not emacsvox-aural-history-record-interface-presentations))
  (when (derived-mode-p 'emacsvox-aural-recent-feedback-mode)
    (emacsvox-aural-recent-feedback-refresh))
  (emacsvox-aural-ui-refresh-home-if-live)
  (emacsvox-aural-tools--speak-history-setting
   (format
    "Aural interface history recording %s"
    (if emacsvox-aural-history-record-interface-presentations
        "on"
      "off")))
  emacsvox-aural-history-record-interface-presentations)

(defun emacsvox-aural-set-history-limit (limit)
  "Set the retained presentation history LIMIT for this Emacs session.

LIMIT may be any natural number.  Zero disables history.  Lowering the limit
immediately discards the oldest excess records; increasing it affects future
recording.  Customize `emacsvox-aural-presentation-history-limit' to persist
the value across sessions."
  (interactive
   (list
    (read-number
     "Maximum retained aural presentations: "
     emacsvox-aural-presentation-history-limit)))
  (unless (natnump limit)
    (user-error "Aural history limit must be a natural number: %S" limit))
  (setq emacsvox-aural-presentation-history-limit limit)
  (cond
   ((zerop limit)
    (setq emacsvox-aural-presentation-history nil))
   ((> (length emacsvox-aural-presentation-history) limit)
    (setcdr
     (nthcdr (1- limit) emacsvox-aural-presentation-history)
     nil)))
  (when (derived-mode-p 'emacsvox-aural-recent-feedback-mode)
    (emacsvox-aural-recent-feedback-refresh))
  (emacsvox-aural-ui-refresh-home-if-live)
  (emacsvox-aural-tools--speak-history-setting
   (if (zerop limit)
       "Aural presentation history disabled"
     (format
      "Aural presentation history limit %d. Larger histories retain more spoken text in memory"
      limit)))
  limit)

(defun emacsvox-aural-recent-feedback-speak-current ()
  "Speak all useful fields for the feedback record at point."
  (interactive)
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to a recent feedback row first")))
         (summary
          (format
           (concat
            "%s. Object %s. Source %s. Occasion %s. Voice %s. "
            "Earcons %s. Status %s. Heard at %s.")
           (aref entry 0)
           (aref entry 1)
           (aref entry 2)
           (aref entry 3)
           (aref entry 4)
           (aref entry 5)
           (aref entry 6)
           (aref entry 7))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-recent-feedback-explain ()
  "Explain the exact frozen feedback record at point."
  (interactive)
  (emacsvox-aural-explanation-display
   (emacsvox-aural-explain-record
    (emacsvox-aural-recent-feedback--record))
   t))

(defun emacsvox-aural-recent-feedback-replay ()
  "Replay the complete frozen presentation at point."
  (interactive)
  (let* ((record (emacsvox-aural-recent-feedback--record))
         (id (emacsvox-aural-presentation-record-id record))
         (plans
          (emacsvox-aural-presentation-record-effective-plans record)))
    (if (cdr plans)
        (emacsvox-aural-preview-play-runs
         (emacsvox-aural-presentation-record-runs record)
         (emacsvox-aural-presentation-record-effective-transaction-id
          record))
      (emacsvox-aural-preview-play-plan (car plans)))
    (emacsvox-aural-recent-feedback-refresh id)
    (emacsvox-aural-preview-message
     "Replayed aural presentation %s" id)
    record))

(defun emacsvox-aural-recent-feedback-audition-cues ()
  "Audition only the exact earcons in the feedback record at point."
  (interactive)
  (let* ((record (emacsvox-aural-recent-feedback--record))
         (cues (emacsvox-aural-recent-feedback--cues record)))
    (unless cues
      (user-error "This feedback record contains no earcons"))
    (emacsvox-aural-preview-play-cues cues)
    (emacsvox-aural-preview-message
     "Auditioning %s"
     (emacsvox-aural-recent-feedback--cue-summary record))
    cues))

(defun emacsvox-aural-recent-feedback-remap-voice ()
  "Prepare a voice override from the frozen feedback record at point."
  (interactive)
  (emacsvox-aural-remap-voice-at-point
   (emacsvox-aural-recent-feedback--record)))

(defun emacsvox-aural-recent-feedback-remap-earcon ()
  "Prepare an earcon override from the frozen feedback record at point."
  (interactive)
  (emacsvox-aural-remap-earcon-at-point
   (emacsvox-aural-recent-feedback--record)))

(defun emacsvox-aural-recent-feedback-help ()
  "Display and speak recent aural feedback help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Recent Aural Feedback\n\n"
      "Each row is one exact frozen presentation that was actually queued.\n"
      "The browser never re-resolves it using the current configuration.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "SPC speak record     RET or e explain exact output\n"
      "P replay all         c audition only its earcons\n"
      "r prepare voice remap from this record\n"
      "R replace, suppress, or restore one exact earcon\n"
      "i include/exclude Aural UI feedback\n"
      "L set retained history limit\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-recent-feedback-mode
    emacsvox-aural-tabulated-mode
  "Aural-Feedback"
  "Spoken browser for exact recently queued aural presentations."
  (emacsvox-aural-ui-configure-tabulated
   "recent aural feedback"
   #'emacsvox-aural-recent-feedback-speak-current
   #'emacsvox-aural-recent-feedback-refresh)
  (setq
   tabulated-list-format
   [("Content" 34 nil)
    ("Object" 32 nil)
    ("Source" 22 nil)
    ("Occasion" 14 nil)
    ("Voice" 18 nil)
    ("Earcons" 24 nil)
    ("Status" 24 nil)
    ("Time" 8 nil)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-recent-feedback-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-recent-feedback-explain)
       ("e" . emacsvox-aural-recent-feedback-explain)
       ("P" . emacsvox-aural-recent-feedback-replay)
       ("c" . emacsvox-aural-recent-feedback-audition-cues)
       ("r" . emacsvox-aural-recent-feedback-remap-voice)
       ("R" . emacsvox-aural-recent-feedback-remap-earcon)
       ("i" . emacsvox-aural-toggle-interface-history-recording)
       ("L" . emacsvox-aural-set-history-limit)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-recent-feedback-help)))
  (define-key
   emacsvox-aural-recent-feedback-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-recent-feedback (&optional source-buffer)
  "Open the spoken browser for exact retained aural feedback.

SOURCE-BUFFER supplies the ordinary source to retain for navigation and
possible buffer-local remapping.  History itself contains only frozen data,
buffer names, and positions."
  (interactive)
  (unless emacsvox-aural-presentation-history
    (user-error
     "No recent aural feedback is retained; history limit is %s"
     emacsvox-aural-presentation-history-limit))
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer
           (or source-buffer (current-buffer))))
         (buffer (get-buffer-create "*Recent Aural Feedback*")))
    (with-current-buffer buffer
      (emacsvox-aural-recent-feedback-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-recent-feedback-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    buffer))

(provide 'emacsvox-aural-recent-feedback)
;;; emacsvox-aural-recent-feedback.el ends here
