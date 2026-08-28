;;; emacsvox-agent-shell-tests.el --- Tests for agent-shell speech -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Deterministic speech tests for emacsvox-agent-shell.  The tests collect
;; ordered speech, interruption, auditory-icon, notification, and message
;; output without starting a live agent or speech server.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'map)
(require 'package)
(require 'seq)
(require 'subr-x)
(package-initialize)
(require 'emacsvox-agent-shell)

(defvar emacsvox-agent-shell--advice-list)
(defvar emacsvox-agent-shell--lifecycle-subscription)
(defvar emacsvox-agent-shell--permission-action-cache)
(defvar emacsvox-agent-shell--permission-response-subscription)
(defvar emacsvox-agent-shell--permission-subscription)
(defvar emacsvox-agent-shell--pending-bodies)
(defvar emacsvox-agent-shell--pending-section-markers)
(defvar emacsvox-agent-shell--pending-speech-qualified-ids)
(defvar emacsvox-agent-shell--pending-speech-timer)
(defvar emacsvox-agent-shell--response-turn-active-p)
(defvar emacsvox-agent-shell--last-completed-answer)
(defvar emacsvox-agent-shell--latest-turn-outcome)
(defvar emacsvox-agent-shell--out-of-turn-bodies)
(defvar emacsvox-agent-shell--out-of-turn-delivered-ids)
(defvar emacsvox-agent-shell--out-of-turn-delivered-order)
(defvar emacsvox-agent-shell--out-of-turn-pending-ids)
(defvar emacsvox-agent-shell--out-of-turn-section-markers)
(defvar emacsvox-agent-shell--out-of-turn-speech-timer)
(defvar emacsvox-agent-shell--tool-call-status-cache)
(defvar emacsvox-agent-shell--tool-call-subscription)
(defvar emacsvox-agent-shell--markdown-face-voice-map)
(defvar emacsvox-agent-shell--markdown-unvoiced-faces)
(defvar emacsvox-agent-shell--chat-face-voice-map)
(defvar emacsvox-agent-shell--ui-face-voice-map)
(defvar emacsvox-agent-shell--ui-unvoiced-faces)
(defvar emacsvox-agent-shell-background-speech-level)
(defvar emacsvox-agent-shell--block-navigation-type)
(defvar emacsvox-agent-shell--block-repeat-map)
(defvar emacsvox-agent-shell--vertical-navigation-active-p)
(defvar emacsvox-agent-shell--vertical-navigation-origin)
(defvar emacsvox-agent-shell--line-navigation-speech-p)
(defvar emacsvox-agent-shell-line-speech-max-characters)
(defvar emacsvox-agent-shell-block-navigation-max-characters)
(defvar emacsvox-agent-shell-foreground-speech-level)
(defvar emacsvox-agent-shell--table-navigation-active)
(defvar emacsvox-agent-shell--table-navigation-map)
(defvar emacsvox-agent-shell--table-navigation-table-start)
(defvar emacsvox-agent-shell--buffer-activation-active-p)
(defvar emacsvox-agent-shell--buffer-activation-values)
(defvar emacsvox-agent-shell--speech-control-active)
(defvar emacsvox-agent-shell--speech-control-map)
(defvar emacsvox-agent-shell-processing-end-icon)
(defvar emacsvox-agent-shell-processing-start-icon)
(defvar emacsvox-agent-shell-signal-processing)
(defvar emacsvox-agent-shell-speak-permissions)
(defvar emacsvox-agent-shell-speak-tool-calls)
(defvar emacsvox-agent-shell-table-data-position)
(defvar emacsvox-agent-shell-table-titles)
(defvar emacsvox-agent-shell-tool-output-verbosity)
(defvar emacsvox-agent-shell-speech-level)
(defvar emacsvox-agent-shell-status-speech-labels)
(defvar emacsvox-comint-autospeak)
(defvar emacsvox-aural-command-start-time)
(defvar tts-yank-excluded-properties)
(defvar ems--message-filter)
(defvar ems--speak-max-length)
(defvar agent-shell--state)
(defvar agent-shell-section-functions)
(defvar agent-shell-header-style)
(defvar agent-shell-mode-map)
(defvar agent-shell-show-context-usage-indicator)
(defvar agent-shell-show-session-id)
(defvar agent-shell-ui--fold-toggle-state)
(defvar agent-shell-viewport-dismiss-on-send)
(defvar agent-shell-viewport--position-cache)
(defvar agent-shell-viewport-edit-mode-map)
(defvar agent-shell-viewport-edit-mode-hook)
(defvar agent-shell-viewport-view-mode-hook)

(declare-function emacsvox-agent-shell--execute-delayed-speech
                  "emacsvox-agent-shell" (buffer qualified-ids))
(declare-function emacsvox-agent-shell--effective-speech-level
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--buffer-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--block-locations
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--block-location-at-point
                  "emacsvox-agent-shell" (&optional position))
(declare-function emacsvox-agent-shell--block-type-minibuffer-setup
                  "emacsvox-agent-shell" (accept-key))
(declare-function emacsvox-agent-shell--accept-block-type-default
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--agent-answer-from-response
                  "emacsvox-agent-shell" (response))
(declare-function emacsvox-agent-shell--latest-agent-answer-state
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--source-block-locations
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--source-block-summary
                  "emacsvox-agent-shell" (location))
(declare-function emacsvox-agent-shell-speak-last-response
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-speak-response-overview
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--jump-block-of-type
                  "emacsvox-agent-shell" (type direction &optional origin))
(declare-function emacsvox-agent-shell--buffer-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--handle-permission-request
                  "emacsvox-agent-shell" (event))
(declare-function emacsvox-agent-shell--handle-permission-response
                  "emacsvox-agent-shell" (event))
(declare-function emacsvox-agent-shell--handle-tool-call-update
                  "emacsvox-agent-shell" (event))
(declare-function emacsvox-agent-shell--handle-lifecycle-event
                  "emacsvox-agent-shell" (event))
(declare-function emacsvox-agent-shell--header-state
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--format-brief-header
                  "emacsvox-agent-shell" (state))
(declare-function emacsvox-agent-shell--format-full-header
                  "emacsvox-agent-shell" (state))
(declare-function emacsvox-agent-shell--lifecycle-event-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--lifecycle-event-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--markdown-table-region-at-point
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--permission-button-feedback
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--permission-event-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--permission-event-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--session-focused-p
                  "emacsvox-agent-shell" (&optional buffer))
(declare-function emacsvox-agent-shell--speak-focus-header-if-needed
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--prepare-speech-text
                  "emacsvox-agent-shell" (text))
(declare-function emacsvox-agent-shell--replace-status-icons-for-speech
                  "emacsvox-agent-shell" (text))
(declare-function emacsvox-agent-shell--remove-visual-chrome-for-speech
                  "emacsvox-agent-shell" (text))
(declare-function emacsvox-agent-shell--record-response-section
                  "emacsvox-agent-shell" (range))
(declare-function emacsvox-agent-shell--record-out-of-turn-snapshot
                  "emacsvox-agent-shell" (snapshot))
(declare-function emacsvox-agent-shell--deliver-out-of-turn-pending
                  "emacsvox-agent-shell" (buffer))
(declare-function emacsvox-agent-shell--section-marker-snapshot
                  "emacsvox-agent-shell" (qualified-id pair))
(declare-function emacsvox-agent-shell--response-overview
                  "emacsvox-agent-shell" (answer))
(declare-function emacsvox-agent-shell--out-of-turn-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--response-section-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--response-section-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--speech-copy-without-yank-handler
                  "emacsvox-agent-shell" (text))
(declare-function emacsvox-agent-shell--install-speech-control-bindings
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--filter-vertical-toggle-hint
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--semantic-item-feedback
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--restore-message-filter
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--vertical-toggle-hint-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--vertical-toggle-hint-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--vertical-navigation-pre-command
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--vertical-navigation-post-command
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--next-line-around
                  "emacsvox-agent-shell"
                  (original-function &rest arguments))
(declare-function emacsvox-agent-shell--previous-line-around
                  "emacsvox-agent-shell"
                  (original-function &rest arguments))
(declare-function emacsvox-agent-shell--beginning-of-visual-line-around
                  "emacsvox-agent-shell"
                  (original-function &rest arguments))
(declare-function emacsvox-agent-shell--end-of-visual-line-around
                  "emacsvox-agent-shell"
                  (original-function &rest arguments))
(declare-function emacsvox-agent-shell--speak-line-around
                  "emacsvox-agent-shell" (original-function &rest arguments))
(declare-function emacsvox-agent-shell--toggle-fragment-around
                  "emacsvox-agent-shell" (original-function &rest arguments))
(declare-function emacsvox-agent-shell--toggle-fragment-action-around
                  "emacsvox-agent-shell"
                  (original-function &rest arguments))
(declare-function emacsvox-agent-shell--toggle-all-fragments-around
                  "emacsvox-agent-shell" (original-function &rest arguments))
(declare-function emacsvox-agent-shell-next-block-of-type
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-next-block-at-point
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-previous-block-of-type
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-previous-block-at-point
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-cycle-speech-level
                  "emacsvox-agent-shell" (&optional reset))
(declare-function emacsvox-agent-shell-select-background-speech-level
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-select-speech-level
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--speak-content
                  "emacsvox-agent-shell" (content block-type))
(declare-function emacsvox-agent-shell--tool-call-block-handled-p
                  "emacsvox-agent-shell" (block-id))
(declare-function emacsvox-agent-shell--tool-call-event-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--tool-call-event-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-cell-feedback
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-navigation-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-navigation-post-command
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-navigation-pre-command
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-navigation-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--table-between
                  "emacsvox-agent-shell" (origin destination direction))
(declare-function emacsvox-agent-shell--viewport-submit-announcement
                  "emacsvox-agent-shell"
                  (disposition keep-composing dismiss))
(declare-function emacsvox-agent-shell--viewport-submit-disposition
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-disable "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-enable "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-speech-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-speak-header
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-speak-source-block
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-copy-source-block
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-select-speaking-method
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-copy-cell
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-copy-column
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-copy-row
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-exit-backward
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-exit-forward
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-next-column
                  "emacsvox-agent-shell" (&optional count))
(declare-function emacsvox-agent-shell-table-next-row
                  "emacsvox-agent-shell" (&optional count))
(declare-function emacsvox-agent-shell-table-previous-column
                  "emacsvox-agent-shell" (&optional count))
(declare-function emacsvox-agent-shell-table-previous-row
                  "emacsvox-agent-shell" (&optional count))
(declare-function emacsvox-agent-shell-table-speak-cell
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-speak-column
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-speak-context
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-speak-dimensions
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell-table-speak-row
                  "emacsvox-agent-shell" ())

(declare-function agent-shell--make-permission-button
                  "agent-shell" (&rest arguments))
(declare-function agent-shell--format-plan "agent-shell" (entries))
(declare-function agent-shell--save-tool-call
                  "agent-shell" (state tool-call-id tool-call))
(declare-function agent-shell-ui--toggle-fragment-at-point
                  "agent-shell-ui" ())
(declare-function agent-shell-markdown-replace-markup
                  "agent-shell-markdown" (&rest arguments))
(declare-function agent-shell-ui-make-fragment-model
                  "agent-shell-ui" (&rest arguments))
(declare-function agent-shell-ui-update-fragment
                  "agent-shell-ui" (model &rest arguments))

(defconst emacsvox-agent-shell-test--fixture-directory
  (file-name-as-directory
   (expand-file-name
    "fixtures/agent-shell"
    (file-name-directory (or load-file-name buffer-file-name))))
  "Directory containing deterministic Agent Shell traffic fixtures.")

(defmacro emacsvox-agent-shell-test--capture-events (&rest body)
  "Run BODY and return ordered speech, stop, icon, and message events."
  (declare (indent 0) (debug t))
  (let ((event-log (make-symbol "event-log")))
    `(let ((emacsvox-agent-shell-foreground-speech-level 'full)
           (emacsvox-agent-shell-background-speech-level 'full)
           (,event-log nil))
       (cl-letf (((symbol-function 'tts-speak)
                  (lambda (text)
                    (push (list 'speak text) ,event-log)))
                 ((symbol-function 'tts-notify)
                  (lambda (text &optional _dont-log)
                    (push (list 'notify text) ,event-log)))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (icon)
                    (push (list 'notify-icon icon) ,event-log)))
                 ((symbol-function 'tts-stop)
                  (lambda (&optional all)
                    (push (list 'stop all) ,event-log)))
                 ((symbol-function 'emacsvox-icon)
                  (lambda (icon)
                    (push (list 'icon icon) ,event-log)))
                 ((symbol-function 'emacsvox-aural-submit)
                  (lambda (text &rest arguments)
                    (let ((facts
                           (or
                            (plist-get arguments :facts)
                            emacsvox-aural-submission-facts)))
                      (dolist
                          (action
                           (plist-get arguments :compatibility-actions))
                        (when
                            (eq
                             (emacsvox-aural-compatibility-action-kind action)
                             'legacy-icon)
                          (push
                           (list
                            'icon
                            (emacsvox-aural-compatibility-action-value action))
                           ,event-log)))
                      (when (and
                             (eq (plist-get facts :role) 'agent-tool)
                             (plist-get facts :agent-tool-status))
                        (push
                         (list
                          'icon
                          (pcase (plist-get facts :agent-tool-status)
                            ('completed 'task-done)
                            ('failed 'warn-user)
                            ('in-progress 'progress)
                            (_ 'item)))
                         ,event-log)))
                    (push (list 'speak text) ,event-log)))
                 ((symbol-function 'emacsvox-aural-submit-actions)
                  (lambda (&rest arguments)
                    (let ((facts
                           (or
                            (plist-get arguments :facts)
                            emacsvox-aural-submission-facts)))
                      (dolist
                          (action
                           (plist-get arguments :compatibility-actions))
                        (when
                            (eq
                             (emacsvox-aural-compatibility-action-kind action)
                             'legacy-icon)
                          (push
                           (list
                            'icon
                            (emacsvox-aural-compatibility-action-value action))
                           ,event-log)))
                      (when (and
                             (eq (plist-get facts :role) 'agent-tool)
                             (plist-get facts :agent-tool-status))
                        (push
                         (list
                          'icon
                          (pcase (plist-get facts :agent-tool-status)
                            ('completed 'task-done)
                            ('failed 'warn-user)
                            ('in-progress 'progress)
                            (_ 'item)))
                         ,event-log)))))
                 ((symbol-function 'message)
                  (lambda (format-string &rest arguments)
                    (push (list 'message
                                (apply #'format-message
                                       format-string arguments))
                          ,event-log)))
                 ((symbol-function 'emacsvox-agent-shell--session-focused-p)
                  (lambda (&optional _buffer) t)))
         ,@body
         (nreverse ,event-log)))))

(defmacro emacsvox-agent-shell-test--capture-presentations (&rest body)
  "Run BODY and return aural facts observed by compatibility output."
  (declare (indent 0) (debug t))
  (let ((presentations (make-symbol "presentations")))
    `(let ((,presentations nil))
       (cl-labels
           ((capture
             (kind value)
             (push
              (list
               kind value
               (copy-tree emacsvox-aural-submission-facts)
               emacsvox-aural-submission-module
               emacsvox-aural-submission-occasion
               (copy-tree emacsvox-aural-submission-context))
              ,presentations))
            (capture-native
             (kind value arguments)
             (let* ((facts
                     (or
                      (plist-get arguments :facts)
                      emacsvox-aural-submission-facts))
                    (module
                     (or
                      emacsvox-aural-submission-module
                      (plist-get arguments :module)))
                    (occasion
                     (or
                      emacsvox-aural-submission-occasion
                      (plist-get arguments :occasion)))
                    (context
                     (or
                      emacsvox-aural-submission-context
                      (plist-get arguments :context)
                      (emacsvox-aural-capture-context module occasion))))
               (push
                (list
                 kind value (copy-tree facts) module occasion
                 (copy-tree context))
                ,presentations))))
         (cl-letf
             (((symbol-function 'emacsvox-icon)
               (lambda (icon) (capture 'icon icon)))
              ((symbol-function 'tts-notify-icon)
               (lambda (icon) (capture 'notify-icon icon)))
              ((symbol-function 'tts-speak)
               (lambda (text) (capture 'speak text)))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (text &rest arguments)
                 (capture-native 'submit text arguments)))
              ((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (capture-native 'submit-actions nil arguments)))
              ((symbol-function 'tts-notify)
               (lambda (text &optional _) (capture 'notify text)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (capture
                  'message
                  (apply #'format-message format-string arguments))))
              ((symbol-function
                'emacsvox-agent-shell--session-focused-p)
               (lambda (&optional _) t)))
           ,@body
           (nreverse ,presentations))))))

(defun emacsvox-agent-shell-test--insert-live-chat-input (draft)
  "Insert a labeled live prompt containing DRAFT and return its bounds."
  (setq major-mode 'agent-shell-mode)
  (set-syntax-table (copy-syntax-table (syntax-table)))
  (modify-syntax-entry ?\n ">" (syntax-table))
  (setq-local
   agent-shell--state
   '((:agent-config . ((:mode-line-name . "Codex"))))
   agent-shell-chat--labeled t)
  (insert "Earlier response\n\n")
  (let ((prompt-start (copy-marker (point) nil)))
    (insert
     (propertize
      "Codex> "
      'font-lock-face '(comint-highlight-prompt comint-highlight-prompt)
      'field 'output))
    (let ((input-start (copy-marker (point) nil)))
      (setq-local comint-last-prompt
                  (cons prompt-start (copy-marker input-start nil)))
      (insert draft)
      (let ((agent-shell-prompt-bar-mode nil))
        (agent-shell-chat--relabel))
      (cons (marker-position input-start) (point-max)))))

(defun emacsvox-agent-shell-test--face-at-text (string text)
  "Return STRING's face at the first occurrence of TEXT."
  (when-let* ((position (string-match (regexp-quote text) string)))
    (get-text-property position 'face string)))

(defun emacsvox-agent-shell-test--mapped-voices (string)
  "Return voices mapped from STRING's face runs, in order."
  (let ((position 0)
        (end (length string))
        voices)
    (while (< position end)
      (when-let* ((face (get-text-property position 'face string))
                  (voice (tts-get-voice-for-face face)))
        (push voice voices))
      (setq position
            (next-single-property-change position 'face string end)))
    (nreverse voices)))

(defun emacsvox-agent-shell-test--speak-pending (entries)
  "Speak pending ENTRIES and return captured events.
ENTRIES is an alist of qualified block IDs to body strings."
  (let ((buffer (generate-new-buffer " *emacsvox-agent-shell-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local emacsvox-comint-autospeak t)
          (setq-local emacsvox-agent-shell--pending-bodies
                      (make-hash-table :test #'equal))
          (dolist (entry entries)
            (puthash (car entry) (cdr entry)
                     emacsvox-agent-shell--pending-bodies))
          (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                      (mapcar #'car entries))
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell--execute-delayed-speech
             buffer
             emacsvox-agent-shell--pending-speech-qualified-ids)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun emacsvox-agent-shell-test--pending-marker-body (qualified-id)
  "Return QUALIFIED-ID's currently marked response body."
  (when-let* ((pair
               (and
                (hash-table-p
                 emacsvox-agent-shell--pending-section-markers)
                (gethash
                 qualified-id
                 emacsvox-agent-shell--pending-section-markers)))
              (body-start (marker-position (car pair)))
              (body-end (marker-position (cdr pair))))
    (buffer-substring body-start body-end)))

(defun emacsvox-agent-shell-test--fixture-path (filename)
  "Return the agent-shell traffic fixture path for FILENAME."
  (let ((path (expand-file-name
               filename
               emacsvox-agent-shell-test--fixture-directory)))
    (unless (file-readable-p path)
      (ert-fail (format "Unreadable agent-shell fixture: %s" path)))
    path))

(defmacro emacsvox-agent-shell-test--with-rendered-table (source &rest body)
  "Render Markdown table SOURCE in a temporary buffer, then run BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,source)
     (agent-shell-markdown-replace-markup)
     ,@body))

(defmacro emacsvox-agent-shell-test--with-rendered-source-blocks (&rest body)
  "Render two fenced source blocks in a temporary buffer, then run BODY."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert
      (concat "before\n"
              "```elisp\n(message \"hello\")\n(+ 1 2)\n```\n"
              "between\n"
              "```python\nprint(\"hello\")\n```\n"
              "after\n"))
     (agent-shell-markdown-replace-markup)
     ,@body))

(cl-defun emacsvox-agent-shell-test--render-response-section
    (&key namespace-id block-id body append create-new)
  "Render and publish one response section update for deterministic tests."
  (let ((range
         (agent-shell-ui-update-fragment
          (agent-shell-ui-make-fragment-model
           :namespace-id namespace-id :block-id block-id :body body)
          :append append :create-new create-new :navigation 'never)))
    (when-let* ((body-range (map-elt range :body)))
      (let ((inhibit-read-only t))
        (save-restriction
          (narrow-to-region (map-elt body-range :start)
                            (map-elt body-range :end))
          (agent-shell-markdown-replace-markup))))
    (run-hook-with-args 'agent-shell-section-functions range)
    range))

(defun emacsvox-agent-shell-test--rendered-interaction-response ()
  "Return a rendered response containing answer and non-answer fragments."
  (with-temp-buffer
    (setq-local agent-shell-section-functions nil)
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "1-agent_message_chunk"
     :body "**First answer**")
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "2-agent_thought_chunk"
     :body "Private reasoning" :create-new t)
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "tool-123"
     :body "Tool output" :create-new t)
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "reader-plan"
     :body "Private plan" :create-new t)
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "3-agent_message_chunk"
     :body "`Second answer`" :create-new t)
    (buffer-string)))

(defmacro emacsvox-agent-shell-test--with-semantic-blocks (&rest body)
  "Create representative agent-shell transcript blocks, then run BODY."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert "Transcript start\n")
     (insert
      (propertize "Codex> "
                  'font-lock-face 'agent-shell-prompt))
     (insert "first request\ncontinued request")
     (insert
      (propertize "<shell-maker-end-of-prompt>"
                  'shell-maker--marker t
                  'invisible t))
     (insert "\n")
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "1-agent_message_chunk"
       :body "First answer\nwith a second line")
      :navigation 'never :expanded t)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "2-agent_thought_chunk"
       :label-left "Thinking" :body "Reasoning"
       :group-id "activity-1"
       :group-label "Thought, read a file" :group-expanded nil)
      :expanded nil)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "tool-123"
       :label-left "completed" :label-right "Read file"
       :body "Tool output\nsecond line" :group-id "activity-1"
       :group-label "Thought, read a file" :group-expanded nil)
      :expanded nil)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "plan"
       :label-left "Plan" :body "One step")
      :expanded t)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "permission-tool-456"
       :body "Allow writing the file?")
      :navigation 'never :expanded t)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "failed-request-id:2"
       :body "Request failed")
      :expanded t)
     (agent-shell-ui-update-fragment
      (agent-shell-ui-make-fragment-model
       :namespace-id "1" :block-id "3-agent_message_chunk"
       :body "Second answer")
      :navigation 'never :expanded t)
     (setq major-mode 'agent-shell-mode)
     ,@body))

(defun emacsvox-agent-shell-test--table-entry (command mode direction)
  "Navigate with COMMAND in MODE across a real block containing a table.
Return speech events plus the target character.  DIRECTION is `forward' or
`backward'."
  (with-temp-buffer
    (let ((response-start (point))
          response-end next-start)
      (insert "thinking\nbefore\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n")
      (setq response-end (point))
      (insert "\n")
      (setq next-start (point))
      (insert "next item\n")
      (put-text-property
       response-start response-end 'agent-shell-ui-state
       '((:qualified-id . "response") (:navigatable . t)))
      (put-text-property
       next-start (point-max) 'agent-shell-ui-state
       '((:qualified-id . "next") (:navigatable . t))))
    (agent-shell-markdown-replace-markup)
    (goto-char (point-min))
    (let ((emacsvox-agent-shell-table-titles '(column))
          (emacsvox-agent-shell-table-data-position 'first))
      (setq major-mode mode)
      (if (eq direction 'forward)
          (goto-char (point-min))
        (goto-char (point-min))
        (search-forward "next item")
        (backward-char (length "next item")))
      (cl-letf (((symbol-function 'shell-maker-busy) (lambda () t))
                ((symbol-function 'comint-next-prompt) (lambda (&rest _) nil))
                ((symbol-function 'agent-shell-next-permission-button)
                 (lambda () nil))
                ((symbol-function 'agent-shell-previous-permission-button)
                 (lambda () nil))
                ((symbol-function 'agent-shell-viewport--prompt-start)
                 (lambda () nil))
                ((symbol-function 'agent-shell-viewport--response-start)
                 (lambda () nil)))
        (let ((events
               (emacsvox-agent-shell-test--capture-events
                 (call-interactively command))))
          (list events (char-after)))))))

(defun emacsvox-agent-shell-test--read-traffic (filename)
  "Read agent-shell traffic fixture FILENAME as Lisp data."
  (with-temp-buffer
    (insert-file-contents
     (emacsvox-agent-shell-test--fixture-path filename))
    (goto-char (point-min))
    (read (current-buffer))))

(defun emacsvox-agent-shell-test--permission-requests (filename)
  "Return incoming permission requests from traffic fixture FILENAME."
  (seq-filter
   (lambda (item)
     (and (eq (map-elt item :direction) 'incoming)
          (equal (map-nested-elt item '(:object method))
                 "session/request_permission")))
   (emacsvox-agent-shell-test--read-traffic filename)))

(defun emacsvox-agent-shell-test--session-updates (filename update-type)
  "Return UPDATE-TYPE notifications from traffic fixture FILENAME."
  (seq-filter
   (lambda (item)
     (and (eq (map-elt item :direction) 'incoming)
          (equal (map-nested-elt item '(:object method)) "session/update")
          (equal (map-nested-elt
                  item '(:object params update sessionUpdate))
                 update-type)))
   (emacsvox-agent-shell-test--read-traffic filename)))

(defun emacsvox-agent-shell-test--normalized-tool-call (raw-tool-call)
  "Normalize RAW-TOOL-CALL into the public event representation."
  (list (cons :title (map-elt raw-tool-call 'title))
        (cons :status (map-elt raw-tool-call 'status))
        (cons :kind (map-elt raw-tool-call 'kind))
        (cons :description
              (map-nested-elt raw-tool-call '(rawInput description)))
        (cons :command (map-nested-elt raw-tool-call '(rawInput command)))
        (cons :content (map-elt raw-tool-call 'content))))

(defun emacsvox-agent-shell-test--tool-call-events (filename)
  "Replay public tool-call events from upstream traffic FILENAME."
  (let ((state '((:tool-calls . nil)))
        events)
    (dolist (item (emacsvox-agent-shell-test--read-traffic filename))
      (let* ((object (map-elt item :object))
             (method (map-elt object 'method))
             (update (map-nested-elt object '(params update)))
             (update-kind (map-elt update 'sessionUpdate))
             (raw-tool-call
              (cond
               ((equal method "session/request_permission")
                (map-nested-elt object '(params toolCall)))
               ((and (equal method "session/update")
                     (member update-kind
                             '("tool_call" "tool_call_update")))
                update)))
             (tool-call-id (map-elt raw-tool-call 'toolCallId)))
        (when tool-call-id
          (agent-shell--save-tool-call
           state tool-call-id
           (emacsvox-agent-shell-test--normalized-tool-call raw-tool-call))
          (when (member update-kind '("tool_call" "tool_call_update"))
            (push
             (list
              (cons :event 'tool-call-update)
              (cons :data
                    (list
                     (cons :tool-call-id tool-call-id)
                     (cons :tool-call
                           (copy-tree
                            (map-nested-elt
                             state (list :tool-calls tool-call-id)))))))
             events)))))
    (nreverse events)))

(defun emacsvox-agent-shell-test--tool-call-event
    (tool-call-id status title &optional content kind output)
  "Make a tool event with TOOL-CALL-ID, STATUS, TITLE, CONTENT, KIND, and OUTPUT."
  (list
   (cons :event 'tool-call-update)
   (cons :data
         (list
          (cons :tool-call-id tool-call-id)
          (cons :tool-call
                (list (cons :status status)
                      (cons :title title)
                      (cons :content content)
                      (cons :kind kind)
                      (cons :output output)))))))

(defun emacsvox-agent-shell-test--permission-event (request)
  "Convert fixture permission REQUEST to a public agent-shell event."
  (let* ((object (map-elt request :object))
         (tool-call (map-nested-elt object '(params toolCall)))
         (tool-call-id (map-elt tool-call 'toolCallId))
         (title (map-elt tool-call 'title))
         (options (append (map-nested-elt object '(params options)) nil))
         (actions (agent-shell--make-permission-actions options)))
    (list
     (cons :event 'permission-request)
     (cons :data
           (list (cons :request-id (map-elt object 'id))
                 (cons :tool-call-id tool-call-id)
                 (cons :tool-call
                       (list (cons :title title)
                             (cons :permission-actions actions))))))))

(defun emacsvox-agent-shell-test--expected-permission-events (events)
  "Return the desired speech events for permission EVENTS."
  (apply #'append
         (mapcar
          (lambda (event)
            (let* ((tool-call (map-nested-elt event '(:data :tool-call)))
                   (title (map-elt tool-call :title))
                   (actions (map-elt tool-call :permission-actions))
                   (choices
                    (cl-loop
                     for action in actions
                     for index from 1
                     collect (format "Choice %d: %s."
                                     index (map-elt action :option)))))
              (list (list 'icon 'warn-user)
                    (list 'speak
                          (string-join
                           (append (list (format "Permission request. %s."
                                                      title))
                                   choices)
                           " ")))))
          events)))

(defun emacsvox-agent-shell-test--permission-response-event
    (request-event &optional kind cancelled)
  "Make a response for REQUEST-EVENT selecting KIND or CANCELLED."
  (let* ((data (map-elt request-event :data))
         (actions (map-nested-elt request-event
                                  '(:data :tool-call :permission-actions)))
         (action (and kind
                      (seq-find
                       (lambda (candidate)
                         (equal (map-elt candidate :kind) kind))
                       actions))))
    (list
     (cons :event 'permission-response)
     (cons :data
           (list (cons :request-id (map-elt data :request-id))
                 (cons :tool-call-id (map-elt data :tool-call-id))
                 (cons :option-id (map-elt action :option-id))
                 (cons :cancelled cancelled))))))

(defun emacsvox-agent-shell-test--insert-permission-buttons ()
  "Insert three navigatable permission buttons for focus tests."
  (insert
   (mapconcat
    #'identity
    (list
     (agent-shell--make-permission-button
      :text "Allow (y)" :help "Allow (y)" :action #'ignore
      :navigatable t :char "y" :option "Allow")
     (agent-shell--make-permission-button
      :text "Reject (n)" :help "Reject (n)" :action #'ignore
      :navigatable t :char "n" :option "Reject")
     (agent-shell--make-permission-button
      :text "Always Allow (!)" :help "Always Allow (!)" :action #'ignore
      :navigatable t :char "!" :option "Always Allow"))
    " ")))

(defun emacsvox-agent-shell-test--saved-advice-state ()
  "Return native advice state for each Agent Shell target."
  (mapcar (lambda (entry)
            (pcase-let ((`(,target ,where ,function) entry))
              (list target where function
                    (advice-member-p function target))))
          emacsvox-agent-shell--advice-list))

(defun emacsvox-agent-shell-test--restore-advice-state (states)
  "Restore native advice activation from STATES."
  (dolist (state states)
    (pcase-let ((`(,target ,where ,function ,active) state))
      (if active
          (unless (advice-member-p function target)
            (advice-add target where function
                        '((name . emacsvox-agent-shell))))
        (when (advice-member-p function target)
          (advice-remove target function))))))

(defun emacsvox-agent-shell-test--advice-target (&rest arguments)
  "Return ARGUMENTS for isolated advice coexistence tests."
  arguments)

(defun emacsvox-agent-shell-test--unrelated-advice
    (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS as unrelated Emacsvox advice."
  (apply original arguments))

(defun emacsvox-agent-shell-test--agent-advice
    (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS as test Agent Shell advice."
  (apply original arguments))

(ert-deftest emacsvox-agent-shell-advice-name-preserves-other-modules ()
  "Agent Shell advice should coexist with advice from another module."
  (let ((emacsvox-agent-shell--advice-list
         '((emacsvox-agent-shell-test--advice-target
            :around emacsvox-agent-shell-test--agent-advice))))
    (unwind-protect
        (progn
          (advice-add
           'emacsvox-agent-shell-test--advice-target
           :around
           #'emacsvox-agent-shell-test--unrelated-advice
           '((name . emacsvox)))
          (emacsvox-agent-shell--install-advice)
          (should
           (advice-member-p
            #'emacsvox-agent-shell-test--unrelated-advice
            'emacsvox-agent-shell-test--advice-target))
          (should
           (advice-member-p
            #'emacsvox-agent-shell-test--agent-advice
            'emacsvox-agent-shell-test--advice-target))
          (emacsvox-agent-shell--remove-advice)
          (should
           (advice-member-p
            #'emacsvox-agent-shell-test--unrelated-advice
            'emacsvox-agent-shell-test--advice-target)))
      (advice-remove
       'emacsvox-agent-shell-test--advice-target
       #'emacsvox-agent-shell-test--agent-advice)
      (advice-remove
       'emacsvox-agent-shell-test--advice-target
       #'emacsvox-agent-shell-test--unrelated-advice))))

(ert-deftest emacsvox-agent-shell-speak-content-orders-feedback ()
  "Speech and icon calls should be observable in their delivery order."
  (should
   (equal
    (emacsvox-agent-shell-test--capture-events
      (emacsvox-agent-shell--speak-content "hello" 'user-message)
      (emacsvox-agent-shell--speak-content "approve?" 'permission))
    '((icon item)
      (speak "User: hello")
      (icon warn-user)
      (speak "approve?")))))

(ert-deftest emacsvox-agent-shell-content-text-uses-atomic-submissions ()
  "Response, user, and plan text each use one native content transaction."
  (let ((emacsvox-agent-shell-speech-level 'full)
        captured
        direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (emacsvox-agent-shell--speak-content "Answer" 'agent-message)
      (emacsvox-agent-shell--speak-content "Prompt" 'user-message)
      (emacsvox-agent-shell--speak-content "One step" 'plan))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should (= (length captured) 3))
    (dolist
        (entry
         (cl-mapcar
          #'list
          captured
          '((agent-response "Answer" nil)
            (agent-user-prompt "User: Prompt" item)
            (agent-plan "Plan: One step" item))))
      (pcase-let* ((`(,submission (,role ,text ,icon)) entry)
                   (`(,content ,arguments ,facts ,module ,occasion)
                    submission)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content text))
        (should (eq (plist-get facts :role) role))
        (should (eq module 'agent-shell))
        (should (eq occasion 'continuous))
        (should
         (equal
          (mapcar #'emacsvox-aural-compatibility-action-value actions)
          (and icon (list icon))))))))

(ert-deftest emacsvox-agent-shell-thought-methods-use-native-submissions ()
  "Thought speech and cue modes should use one native transaction each."
  (let ((emacsvox-agent-shell-speech-level 'full)
        captured
        direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              'content content arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push
             (list
              'actions arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (let ((emacsvox-agent-shell-speak-thought-process 'speak))
        (emacsvox-agent-shell--speak-content "Reasoning" 'thought))
      (let ((emacsvox-agent-shell-speak-thought-process 'icon))
        (emacsvox-agent-shell--speak-content "Reasoning" 'thought))
      (let ((emacsvox-agent-shell-speak-thought-process nil))
        (emacsvox-agent-shell--speak-content "Reasoning" 'thought)))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should (= (length captured) 2))
    (pcase-let*
        ((`(content ,text ,_arguments ,facts ,module ,occasion)
          (car captured)))
      (should (equal text "Thinking: Reasoning"))
      (should (eq (plist-get facts :role) 'agent-thought))
      (should (eq module 'agent-shell))
      (should (eq occasion 'continuous)))
    (pcase-let*
        ((`(actions ,arguments ,facts ,module ,occasion) (cadr captured))
         (actions (plist-get arguments :compatibility-actions)))
      (should
       (equal
        (mapcar #'emacsvox-aural-compatibility-action-value actions)
        '(progress)))
      (should (eq (plist-get facts :role) 'agent-thought))
      (should (eq module 'agent-shell))
      (should (eq occasion 'continuous)))))

(ert-deftest emacsvox-agent-shell-rendered-tool-content-is-native ()
  "Rendered tool content modes should each use one native transaction."
  (let ((emacsvox-agent-shell-speech-level 'full)
        (emacsvox-agent-shell-speak-tool-calls t)
        captured
        direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              'content content arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push
             (list
              'actions arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (let ((emacsvox-agent-shell-tool-output-verbosity 'full))
        (emacsvox-agent-shell--speak-content "Complete output" 'tool-call))
      (let ((emacsvox-agent-shell-tool-output-verbosity 'summary))
        (emacsvox-agent-shell--speak-content
         "One\nTwo\nThree\nFour" 'tool-call))
      (let ((emacsvox-agent-shell-tool-output-verbosity 'status))
        (emacsvox-agent-shell--speak-content "Completed" 'tool-call)))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should (= (length captured) 3))
    (should (equal (mapcar #'car captured) '(content content actions)))
    (should (equal (mapcar #'cadr (seq-take captured 2))
                   '("Complete output" "One Two Three")))
    (dolist (entry captured)
      (let ((facts (if (eq (car entry) 'content)
                       (nth 3 entry)
                     (nth 2 entry)))
            (module (if (eq (car entry) 'content)
                        (nth 4 entry)
                      (nth 3 entry)))
            (occasion (if (eq (car entry) 'content)
                          (nth 5 entry)
                        (nth 4 entry))))
        (should (eq (plist-get facts :role) 'agent-tool))
        (should (eq module 'agent-shell))
        (should (eq occasion 'continuous))))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-compatibility-action-value
      (plist-get (cadr (nth 2 captured)) :compatibility-actions))
      '(task-done)))))

(ert-deftest emacsvox-agent-shell-fallback-content-is-native ()
  "Unknown and generic content should use native content transactions."
  (let (captured direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (let ((emacsvox-agent-shell-speech-level 'full))
        (emacsvox-agent-shell--speak-content "Unknown body" 'unknown))
      (let ((emacsvox-agent-shell-speech-level 'response))
        (emacsvox-agent-shell--speak-content "Hidden body" 'unknown)
        (emacsvox-agent-shell--speak-content "Generic body" 'other)))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should
     (equal
      (mapcar #'car captured)
      '("Unknown body"
        "Additional agent content available."
        "Generic body")))
    (dolist (entry captured)
      (should (eq (plist-get (nth 1 entry) :role) 'agent-block))
      (should (eq (plist-get (nth 1 entry) :agent-block-kind) 'other))
      (should (eq (nth 2 entry) 'agent-shell))
      (should (eq (nth 3 entry) 'continuous)))))

(ert-deftest emacsvox-agent-shell-response-inspection-is-native ()
  "Response inspection outcomes should use explicit native transactions."
  (let ((answer "Complete answer")
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--latest-agent-answer-state)
          (lambda () (list :answer answer :in-progress nil)))
         ((symbol-function 'emacsvox-agent-shell--response-overview)
          (lambda (_text) "Response overview"))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (cons content arguments) captured))))
      (emacsvox-agent-shell-speak-last-response)
      (emacsvox-agent-shell-speak-response-overview)
      (setq answer nil)
      (emacsvox-agent-shell-speak-last-response)
      (emacsvox-agent-shell-speak-response-overview))
    (setq captured (nreverse captured))
    (should
     (equal
      (mapcar #'car captured)
      '("Complete answer"
        "Response overview"
        "No agent response available."
        "No agent response available.")))
    (dolist (entry captured)
      (let* ((arguments (cdr entry))
             (facts (plist-get arguments :facts))
             (actions (plist-get arguments :compatibility-actions)))
        (should (eq (plist-get facts :role) 'agent-response))
        (should (eq (plist-get arguments :module) 'agent-shell))
        (should (eq (plist-get arguments :occasion) 'inspection))
        (should
         (equal
          (mapcar #'emacsvox-aural-compatibility-action-value actions)
          (if (member (car entry)
                      '("Complete answer" "Response overview"))
              '(item)
            '(warn-user))))))))

(ert-deftest emacsvox-agent-shell-response-inspection-keeps-completed-while-busy ()
  "Busy inspection should identify and retain the prior completed answer."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     emacsvox-agent-shell--last-completed-answer
     (propertize "Completed answer" 'face 'agent-shell-markdown-bold))
    (setq-local emacsvox-agent-shell--response-turn-active-p t
                emacsvox-agent-shell--latest-turn-outcome 'active)
    (let (events
          (status-calls 0)
          (rendered-calls 0))
      (cl-letf
          (((symbol-function 'emacsvox-agent-shell--session-buffer)
            (lambda (&optional _) (current-buffer)))
           ((symbol-function 'agent-shell-status)
            (lambda (&rest arguments)
              (should (eq (plist-get arguments :shell-buffer)
                          (current-buffer)))
              (cl-incf status-calls)
              'busy))
           ((symbol-function
             'emacsvox-agent-shell--rendered-latest-agent-answer)
            (lambda ()
              (cl-incf rendered-calls)
              "Partial current answer")))
        (setq events
              (emacsvox-agent-shell-test--capture-events
                (emacsvox-agent-shell-speak-last-response)
                (emacsvox-agent-shell-speak-response-overview))))
      (should (= status-calls 2))
      (should (= rendered-calls 0))
      (should
       (equal
        (mapcar
         (lambda (event)
           (if (stringp (cadr event))
               (list (car event) (substring-no-properties (cadr event)))
             event))
         events)
        '((stop nil)
          (icon item)
          (speak
           "Agent is still working. Last completed response: Completed answer")
          (stop nil)
          (icon item)
          (speak
           "Agent is still working. Last completed response: 1 line. Begins: Completed answer"))))
      (let ((spoken (cadr (nth 2 events))))
        (should
         (eq (emacsvox-agent-shell-test--face-at-text spoken "Completed answer")
             'agent-shell-markdown-bold))))))

(ert-deftest emacsvox-agent-shell-response-inspection-identifies-first-partial ()
  "Busy inspection should not call a first partial response completed."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local emacsvox-agent-shell--response-turn-active-p t
                emacsvox-agent-shell--latest-turn-outcome 'active)
    (let ((rendered-calls 0))
      (cl-letf
          (((symbol-function 'emacsvox-agent-shell--session-buffer)
            (lambda (&optional _) (current-buffer)))
           ((symbol-function 'agent-shell-status)
            (lambda (&rest _) 'busy))
           ((symbol-function
             'emacsvox-agent-shell--rendered-latest-agent-answer)
            (lambda ()
              (cl-incf rendered-calls)
              "Partial current answer")))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell-speak-last-response)
            (emacsvox-agent-shell-speak-response-overview))
          '((icon warn-user)
            (speak
             "Agent response in progress; no completed response available.")
            (icon warn-user)
            (speak
             "Agent response in progress; no completed response available.")))))
      (should (= rendered-calls 0)))))

(ert-deftest emacsvox-agent-shell-failed-turn-retains-completed-answer ()
  "A failed latest turn should not replace its prior completed answer."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local emacsvox-agent-shell--last-completed-answer "Safe answer"
                emacsvox-agent-shell--latest-turn-outcome 'failed)
    (let ((rendered-calls 0))
      (cl-letf
          (((symbol-function 'emacsvox-agent-shell--session-buffer)
            (lambda (&optional _) (current-buffer)))
           ((symbol-function 'agent-shell-status)
            (lambda (&rest _) 'ready))
           ((symbol-function
             'emacsvox-agent-shell--rendered-latest-agent-answer)
            (lambda ()
              (cl-incf rendered-calls)
              "Discarded partial")))
        (should
         (equal (emacsvox-agent-shell--latest-agent-answer-state)
                '(:answer "Safe answer" :in-progress nil))))
      (should (= rendered-calls 0)))))

(ert-deftest emacsvox-agent-shell-speech-setup-preserves-package-header ()
  "Speech setup should not replace agent-shell's semantic header."
  (with-temp-buffer
    (let ((header-line-format "Agent semantic header"))
      (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy) #'ignore)
                ((symbol-function
                  'emacsvox-pronounce-add-dictionary-entry)
                 #'ignore)
                ((symbol-function
                  'emacsvox-pronounce-refresh-pronunciations)
                 #'ignore))
        (emacsvox-agent-shell-speech-setup))
      (should (equal header-line-format "Agent semantic header")))))

(ert-deftest emacsvox-agent-shell-speech-setup-preserves-live-prompt-undo ()
  "Speech setup should leave Agent Shell's live prompt undoable."
  (with-temp-buffer
    (buffer-enable-undo)
    (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy) #'ignore)
              ((symbol-function
                'emacsvox-pronounce-add-dictionary-entry)
               #'ignore)
              ((symbol-function
                'emacsvox-pronounce-refresh-pronunciations)
               #'ignore))
      (emacsvox-agent-shell-speech-setup))
    (insert "draft α")
    (undo-boundary)
    (undo-only)
    (should (equal (buffer-string) ""))))

(ert-deftest emacsvox-agent-shell-speech-setup-preserves-disabled-undo ()
  "Speech setup should respect an explicitly disabled undo policy."
  (with-temp-buffer
    (buffer-disable-undo)
    (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy) #'ignore)
              ((symbol-function
                'emacsvox-pronounce-add-dictionary-entry)
               #'ignore)
              ((symbol-function
                'emacsvox-pronounce-refresh-pronunciations)
               #'ignore))
      (emacsvox-agent-shell-speech-setup))
    (should (eq buffer-undo-list t))))

(ert-deftest emacsvox-agent-shell-speech-setup-preserves-punctuation-override ()
  "Agent Shell setup should honor an explicit buffer punctuation mode."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let ((tts-speaker-process nil))
      (tts-set-punctuations 'some)
      (cl-letf
          (((symbol-function 'emacsvox-pronounce-add-dictionary-entry)
            #'ignore)
           ((symbol-function 'emacsvox-pronounce-refresh-pronunciations)
            #'ignore))
        (emacsvox-agent-shell-speech-setup))
      (should (eq tts-punctuation-mode 'some))
      (should (eq tts-punctuation-mode-override 'some)))))

(ert-deftest emacsvox-agent-shell-header-formatters-separate-detail-levels ()
  "Focus speech should be concise while explicit speech exposes full state."
  (let ((state
         '(:agent "Codex agent"
           :project "emacsvox-support"
           :busy t
           :model "GPT-5.6-Sol"
           :thought-level "xhigh"
           :mode "Agent (full access)"
           :context-percentage 73
           :session-id "session-123"))
        full)
    (should
     (equal (emacsvox-agent-shell--format-brief-header state)
            "Codex agent, emacsvox-support, busy."))
    (should-not
     (text-property-not-all
      0 (length (emacsvox-agent-shell--format-brief-header state))
      'face nil
      (emacsvox-agent-shell--format-brief-header state)))
    (setq full (emacsvox-agent-shell--format-full-header state))
    (should
     (equal
      full
      (concat
       "Codex agent. Project emacsvox-support. Busy. "
       "Model GPT-5.6-Sol. Thought level xhigh. "
       "Mode Agent (full access). Context 73 percent. "
       "Session ID session-123.")))
    (dolist (entry
             '(("Codex agent" . agent-shell-buffer-name)
               ("Project emacsvox-support" . agent-shell-session-directory)
               ("Busy" . agent-shell-warning)
               ("Model GPT-5.6-Sol" . agent-shell-model)
               ("Thought level xhigh" . agent-shell-thought-level)
               ("Mode Agent (full access)" . agent-shell-session-mode)
               ("Context 73 percent" . agent-shell-warning)
               ("Session ID session-123" . agent-shell-session-id)))
      (should
       (eq (emacsvox-agent-shell-test--face-at-text full (car entry))
           (cdr entry))))
    (should
     (equal
      (emacsvox-agent-shell-test--mapped-voices full)
      '(voice-animate voice-lighten-extra voice-brighten
        voice-brighten-extra voice-animate-extra voice-smoothen
        voice-brighten voice-lighten)))))

(ert-deftest emacsvox-agent-shell-context-header-voices-usage-severity ()
  "Context header speech should follow agent-shell's usage thresholds."
  (dolist (entry '((59 . agent-shell-success)
                   (60 . agent-shell-warning)
                   (84 . agent-shell-warning)
                   (85 . agent-shell-error)))
    (let ((speech
           (emacsvox-agent-shell--format-full-header
            (list :context-percentage (car entry)))))
      (should
       (eq (emacsvox-agent-shell-test--face-at-text speech "Context")
           (cdr entry))))))

(ert-deftest emacsvox-agent-shell-header-formatters-describe-viewport ()
  "Viewport focus speech should include position and interaction status."
  (let ((state
         '(:agent "Codex agent"
           :project "emacsvox-support"
           :busy t
           :viewport-position "2 of 5"
           :viewport-status "edit queue"
           :model "GPT-5.6-Sol")))
    (should
     (equal (emacsvox-agent-shell--format-brief-header state)
            (concat
             "Codex agent, emacsvox-support, viewport 2 of 5, "
             "edit queue.")))
    (should
     (equal (emacsvox-agent-shell--format-full-header state)
            (concat
             "Codex agent. Project emacsvox-support. Viewport 2 of 5. "
             "Edit queue. Model GPT-5.6-Sol.")))))

(ert-deftest emacsvox-agent-shell-header-state-uses-semantic-session-data ()
  "Header state should derive values from agent-shell state, not SVG text."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:buffer-name . "Codex")))
       (:heartbeat . ((:status . busy)))
       (:session . ((:id . "session-123")))
       (:usage . ((:context-used . 188000)
                  (:context-size . 258000)))))
    (let ((agent-shell-show-context-usage-indicator 'detailed)
          (agent-shell-show-session-id t))
      (cl-letf (((symbol-function 'shell-maker-busy) (lambda () t))
                ((symbol-function 'agent-shell--project-name)
                 (lambda () "emacsvox-support"))
                ((symbol-function 'agent-shell-get-model-name)
                 (lambda (_state) "GPT-5.6-Sol"))
                ((symbol-function 'agent-shell-get-thought-level-name)
                 (lambda (_state) "xhigh"))
                ((symbol-function 'agent-shell-get-mode-name)
                 (lambda (_state) "Agent (full access)")))
        (should
         (equal
          (emacsvox-agent-shell--header-state)
          '(:agent "Codex agent"
            :project "emacsvox-support"
            :busy t
            :viewport-position nil
            :viewport-status nil
            :model "GPT-5.6-Sol"
            :thought-level "xhigh"
            :mode "Agent (full access)"
            :context-percentage 73
            :session-id "session-123")))))))

(ert-deftest emacsvox-agent-shell-graphical-header-gets-brief-fallback ()
  "A visually rendered whitespace header should receive semantic speech."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode
          header-line-format "  ")
    (cl-letf (((symbol-function 'format-mode-line)
               (lambda (&rest _) "  "))
              ((symbol-function 'emacsvox-agent-shell--header-state)
               (lambda (&optional _buffer)
                 '(:agent "Codex agent"
                   :project "emacsvox-support"
                   :busy t))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--speak-focus-header-if-needed))
        '((icon item)
          (speak "Codex agent, emacsvox-support, busy.")))))))

(ert-deftest emacsvox-agent-shell-text-header-keeps-emacsvox-path ()
  "A textual agent header should not be replaced by semantic fallback speech."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode
          header-line-format "Codex text header")
    (cl-letf (((symbol-function 'format-mode-line)
               (lambda (&rest _) "Codex text header")))
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (emacsvox-agent-shell--speak-focus-header-if-needed))))))

(ert-deftest emacsvox-agent-shell-explicit-header-command-speaks-full-state ()
  "The explicit header command should stop chatter and read full state."
  (cl-letf (((symbol-function 'emacsvox-agent-shell--header-state)
             (lambda (&optional _buffer)
               '(:agent "Codex agent"
                 :project "emacsvox-support"
                 :model "GPT-5.6-Sol"))))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell-speak-header))
      '((stop nil)
        (icon item)
        (speak
         "Codex agent. Project emacsvox-support. Model GPT-5.6-Sol."))))))

(ert-deftest emacsvox-agent-shell-header-feedback-is-native ()
  "Brief and explicit headers should use native inspection transactions."
  (let (captured)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--unspoken-graphical-header-p)
          (lambda () t))
         ((symbol-function 'emacsvox-agent-shell--header-state)
          (lambda (&optional _buffer)
            '(:agent "Codex agent" :project "emacsvox")))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (cons content arguments) captured))))
      (emacsvox-agent-shell--speak-focus-header-if-needed)
      (emacsvox-agent-shell-speak-header))
    (setq captured (nreverse captured))
    (should
     (equal
      (mapcar #'car captured)
      '("Codex agent, emacsvox."
        "Codex agent. Project emacsvox.")))
    (dolist (entry captured)
      (let* ((arguments (cdr entry))
             (facts (plist-get arguments :facts))
             (actions (plist-get arguments :compatibility-actions)))
        (should (eq (plist-get facts :role) 'agent-session))
        (should
         (equal (plist-get facts :events) '(agent-content-inspected)))
        (should (eq (plist-get arguments :module) 'agent-shell))
        (should (eq (plist-get arguments :occasion) 'inspection))
        (should
         (equal
          (mapcar #'emacsvox-aural-compatibility-action-value actions)
          '(item)))))))

(ert-deftest emacsvox-agent-shell-speech-level-feedback-is-native ()
  "Session and background speech controls should submit selected levels."
  (let ((shell (generate-new-buffer "Codex Agent @ native-level"))
        (emacsvox-agent-shell-background-speech-level 'full)
        captured)
    (unwind-protect
        (progn
          (with-current-buffer shell
            (setq major-mode 'agent-shell-mode))
          (cl-letf
              (((symbol-function 'emacsvox-agent-shell--session-buffer)
                (lambda (&optional _buffer) shell))
               ((symbol-function 'emacsvox-agent-shell--read-speech-level)
                (lambda (&rest _) 'quiet))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push (cons content arguments) captured))))
            (emacsvox-agent-shell--set-session-speech-level shell 'response)
            (emacsvox-agent-shell-select-background-speech-level))
          (setq captured (nreverse captured))
          (should
           (equal
            (mapcar #'car captured)
            '("Agent speech response for Codex Agent @ native-level."
              "Background agent speech quiet.")))
          (dolist (entry captured)
            (let* ((arguments (cdr entry))
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
              (should (eq (plist-get facts :role) 'agent-session))
              (should
               (equal (plist-get facts :events) '(agent-setting-changed)))
              (should (memq (plist-get facts :agent-speech-level)
                            '(response quiet)))
              (should (eq (plist-get arguments :module) 'agent-shell))
              (should (eq (plist-get arguments :occasion) 'state-change))
              (should (= (length actions) 1)))))
      (when (buffer-live-p shell)
        (kill-buffer shell)))))

(ert-deftest emacsvox-agent-shell-mode-line-command-speaks-full-header ()
  "Interactive mode-line speech should read and voice semantic agent state."
  (let ((buffer (generate-new-buffer " *agent-mode-line-header-test*")))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode))
          (cl-letf (((symbol-function 'emacsvox-agent-shell--header-state)
                     (lambda (&optional _buffer)
                       '(:agent "Codex agent"
                         :project "emacsvox-support"
                         :model "GPT-5.6-Sol"))))
            (let* ((events
                    (emacsvox-agent-shell-test--capture-events
                      (call-interactively #'emacsvox-speak-mode-line)))
                   (speech (cadr (nth 2 events))))
              (should
               (equal
                events
                (list
                 '(stop nil)
                 '(icon item)
                 (list
                  'speak
                  (concat
                   "Codex agent. Project emacsvox-support. "
                   "Model GPT-5.6-Sol.")))))
              (should
               (equal
                (emacsvox-agent-shell-test--mapped-voices speech)
                '(voice-animate voice-lighten-extra
                  voice-brighten-extra))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-mode-line-prefix-retains-buffer-info ()
  "A prefix argument should preserve Emacsvox's buffer-information path."
  (let ((buffer (generate-new-buffer " *agent-mode-line-prefix-test*")))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode))
          (cl-letf (((symbol-function 'emacsvox-speak-buffer-info)
                     (lambda () (tts-speak "standard buffer information"))))
            (let ((current-prefix-arg '(4)))
              (should
               (equal
                (emacsvox-agent-shell-test--capture-events
                  (call-interactively #'emacsvox-speak-mode-line))
                '((stop nil)
                  (speak "standard buffer information")))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-automatic-mode-line-remains-concise ()
  "Noninteractive mode-line speech should retain concise focus feedback."
  (let ((buffer (generate-new-buffer " *agent-mode-line-focus-test*")))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode
                  header-line-format "  "))
          (cl-letf (((symbol-function 'format-mode-line)
                     (lambda (&rest _) "  "))
                    ((symbol-function
                      'emacsvox-agent-shell--header-state)
                     (lambda (&optional _buffer)
                       '(:agent "Codex agent"
                         :project "emacsvox-support"
                         :busy t))))
            (should
             (equal
              (emacsvox-agent-shell-test--capture-events
                (emacsvox-speak-mode-line))
              '((stop nil)
                (icon item)
                (speak "Codex agent, emacsvox-support, busy."))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-interactive-shell-commands-are-native ()
  "Interactive shell entry and interruption should use native transactions."
  (let (captured direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--header-state)
          (lambda (&optional _buffer)
            '(:agent "Codex agent" :project "emacsvox")))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (cons content arguments) captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'emacsvox-speak-mode-line)
          (lambda (&rest _) (push 'mode-line direct-output)))
         ((symbol-function 'message)
          (lambda (&rest _) (push 'message direct-output)))
         ((symbol-function 'tts-apply-punctuation-mode-policy) #'ignore)
         ((symbol-function 'tts-toggle-split-caps) #'ignore)
         ((symbol-function 'emacsvox-pronounce-refresh-pronunciations)
          #'ignore))
      (dolist
          (entry
           '((agent-shell
              . emacsvox-agent-shell--agent-shell-after)
             (agent-shell-start
              . emacsvox-agent-shell--agent-shell-start-after)
             (agent-shell-new-shell
              . emacsvox-agent-shell--agent-shell-new-shell-after)
             (agent-shell-toggle
              . emacsvox-agent-shell--agent-shell-toggle-after)
             (agent-shell-other-buffer
              . emacsvox-agent-shell--agent-shell-other-buffer-after)
             (agent-shell-interrupt
              . emacsvox-agent-shell--agent-shell-interrupt-after)))
        (let ((ems--interactive-fn-name (car entry)))
          (funcall (cdr entry)))))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should
     (equal
      (mapcar #'car captured)
      '("Codex agent, emacsvox."
        "Agent shell started"
        "New agent shell"
        "Codex agent, emacsvox."
        "Codex agent, emacsvox."
        "Agent interrupted")))
    (should
     (equal
      (mapcar
       (lambda (entry)
         (plist-get (plist-get (cdr entry) :facts) :events))
       captured)
      '((agent-session-opened)
        (agent-session-opened)
        (agent-session-opened)
        (agent-session-opened)
        (agent-session-opened)
        (agent-session-interrupted))))))

(ert-deftest emacsvox-agent-shell-delayed-agent-message-speaks-once ()
  "The legacy pending-body delivery helper should remain compatible."
  (should
   (equal
    (emacsvox-agent-shell-test--speak-pending
     '(("request-agent_message_chunk" . "Complete response")))
    '((speak "Complete response")))))

(ert-deftest emacsvox-agent-shell-rendered-response-waits-for-turn-complete ()
  "Rendered snapshots should stay silent through pauses and speak once."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local emacsvox-comint-autospeak t)
    (setq-local agent-shell-section-functions nil)
    (emacsvox-agent-shell--response-section-setup)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . input-submitted)))
        (emacsvox-agent-shell-test--render-response-section
         :namespace-id "request" :block-id "1-agent_message_chunk"
         :body "Partial **response**")
        ;; A pause longer than the legacy delay must not imply completion.
        (let ((emacsvox-agent-shell-speech-delay 0.001))
          (sit-for 0.01)))
      '((icon progress))))
    (should emacsvox-agent-shell--response-turn-active-p)
    (should-not emacsvox-agent-shell--pending-speech-timer)
    (should-not emacsvox-agent-shell--pending-bodies)
    (should
     (equal
      (substring-no-properties
       (emacsvox-agent-shell-test--pending-marker-body
        "request-1-agent_message_chunk"))
      "Partial response"))
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "request" :block-id "1-agent_message_chunk"
     :body "Complete **response**")
    (let* ((events
            (emacsvox-agent-shell-test--capture-events
              (emacsvox-agent-shell--handle-lifecycle-event
               '((:event . turn-complete)
                 (:data (:stop-reason . "end_turn"))))))
           (speech (cadr (car events))))
      (should
       (equal events
              '((speak "Complete response")
                (icon task-done))))
      (should
       (eq (emacsvox-agent-shell-test--face-at-text speech "response")
           'agent-shell-markdown-bold)))
    (should-not emacsvox-agent-shell--response-turn-active-p)
    (should (eq emacsvox-agent-shell--latest-turn-outcome 'completed))
    (should
     (equal (substring-no-properties
             emacsvox-agent-shell--last-completed-answer)
            "Complete response"))
    (should
     (eq
      (emacsvox-agent-shell-test--face-at-text
       emacsvox-agent-shell--last-completed-answer "response")
      'agent-shell-markdown-bold))
    (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
    (should-not emacsvox-agent-shell--pending-section-markers)
    (should-not emacsvox-agent-shell--pending-bodies)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . turn-complete)
           (:data (:stop-reason . "end_turn")))))
      '((icon task-done))))))

(ert-deftest emacsvox-agent-shell-streaming-defers-body-snapshot ()
  "Streaming should update stable markers and copy the final body only once."
  (let ((emacsvox-agent-shell-signal-processing nil)
        (expected (concat "Start" (make-string 250 ?x)))
        (snapshot-count 0)
        marker-pair
        (original-snapshot
         (symbol-function
          'emacsvox-agent-shell--section-marker-snapshot)))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'response)
      (setq-local agent-shell-section-functions nil)
      (emacsvox-agent-shell--response-section-setup)
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--section-marker-snapshot)
            (lambda (&rest arguments)
              (cl-incf snapshot-count)
              (apply original-snapshot arguments))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell--handle-lifecycle-event
             '((:event . input-submitted)))
            (emacsvox-agent-shell-test--render-response-section
             :namespace-id "stream"
             :block-id "answer-agent_message_chunk"
             :body "Start")
            (setq marker-pair
                  (gethash
                   "stream-answer-agent_message_chunk"
                   emacsvox-agent-shell--pending-section-markers))
            (let ((pair marker-pair))
              (dotimes (_ 250)
                (emacsvox-agent-shell-test--render-response-section
                 :namespace-id "stream"
                 :block-id "answer-agent_message_chunk"
                 :body "x" :append t)
                (should
                 (eq pair
                     (gethash
                      "stream-answer-agent_message_chunk"
                      emacsvox-agent-shell--pending-section-markers)))))
            (should (= snapshot-count 0))
            (should-not emacsvox-agent-shell--pending-bodies)
            (emacsvox-agent-shell--handle-lifecycle-event
             '((:event . turn-complete)
               (:data (:stop-reason . "end_turn")))))
          `((speak ,expected))))
        (should (= snapshot-count 1))
        (should-not emacsvox-agent-shell--pending-section-markers)
        (should-not (marker-buffer (car marker-pair)))
        (should-not (marker-buffer (cdr marker-pair)))))))

(ert-deftest emacsvox-agent-shell-turn-sections-use-real-id-and-order ()
  "Turn content should retain qualified IDs while response policy stays quiet."
  (let ((emacsvox-agent-shell-signal-processing nil))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'response)
      (setq-local agent-shell-section-functions
                  '(emacsvox-agent-shell--record-response-section))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . input-submitted)))
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "1-agent_message_chunk"
           :body "First answer")
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "agent_thought_chunk"
           :body "Reasoning available at full" :create-new t)
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "tool-1-plan"
           :body "Plan available at full" :create-new t)
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "2-agent_message_chunk"
           :body "Second answer" :create-new t)
          (should
           (equal emacsvox-agent-shell--pending-speech-qualified-ids
                  '("7-1-agent_message_chunk"
                    "7-agent_thought_chunk"
                    "7-tool-1-plan"
                    "7-2-agent_message_chunk")))
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . turn-complete)
             (:data (:stop-reason . "end_turn")))))
        '((speak "First answer")
          (speak "Second answer")))))))

(ert-deftest emacsvox-agent-shell-full-level-speaks-turn-thoughts-and-plans ()
  "Full speech should deliver thoughts and plans once at turn completion."
  (let ((emacsvox-agent-shell-signal-processing nil)
        (emacsvox-agent-shell-speak-thought-process 'speak))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'full)
      (setq-local agent-shell-section-functions
                  '(emacsvox-agent-shell--record-response-section))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . input-submitted)))
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "1-agent_thought_chunk"
           :body "Check constraints")
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "reader-plan"
           :body "Inspect then edit" :create-new t)
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "7" :block-id "answer-agent_message_chunk"
           :body "Final answer" :create-new t)
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . turn-complete)
             (:data (:stop-reason . "end_turn")))))
        '((speak "Thinking: Check constraints")
          (icon item)
          (speak "Plan: Inspect then edit")
          (speak "Final answer")))))))

(ert-deftest emacsvox-agent-shell-full-level-honors-thought-method ()
  "Full speech should retain icon and silent thought methods."
  (with-temp-buffer
    (setq-local emacsvox-agent-shell-speech-level 'full)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (let ((emacsvox-agent-shell-speak-thought-process 'icon))
          (emacsvox-agent-shell--speak-content "Reasoning" 'thought)))
      '((icon progress))))
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (let ((emacsvox-agent-shell-speak-thought-process nil))
         (emacsvox-agent-shell--speak-content "Reasoning" 'thought))))))

(ert-deftest emacsvox-agent-shell-out-of-turn-message-resumes-after-pause ()
  "A resumed out-of-turn message should announce each changed latest body."
  (let ((emacsvox-agent-shell-speech-delay 0.001)
        (snapshot-count 0)
        (qualified-id "out-of-turn-message-1-agent_message_chunk")
        (original-snapshot
         (symbol-function
          'emacsvox-agent-shell--section-marker-snapshot)))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'response)
      (setq-local agent-shell-section-functions
                  '(emacsvox-agent-shell--record-response-section))
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--section-marker-snapshot)
            (lambda (&rest arguments)
              (cl-incf snapshot-count)
              (apply original-snapshot arguments))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell-test--render-response-section
             :namespace-id "out-of-turn"
             :block-id "message-1-agent_message_chunk"
             :body "Partial ")
            (emacsvox-agent-shell-test--render-response-section
             :namespace-id "out-of-turn"
             :block-id "message-1-agent_message_chunk"
             :body "update" :append t)
            (should (= snapshot-count 0))
            (sit-for 0.01))
          '((icon item)
            (speak "Agent update: Partial update"))))
        (should (= snapshot-count 1))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell-test--render-response-section
             :namespace-id "out-of-turn"
             :block-id "message-1-agent_message_chunk"
             :body " completed" :append t)
            (sit-for 0.01))
          '((icon item)
            (speak "Agent update: Partial update completed"))))
        (should (= snapshot-count 2))
        (should-not
         (emacsvox-agent-shell-test--capture-events
           (emacsvox-agent-shell-test--render-response-section
            :namespace-id "out-of-turn"
            :block-id "message-1-agent_message_chunk"
            :body "Partial update completed")
           (sit-for 0.01)))
        (should (= snapshot-count 3)))
      (should-not emacsvox-agent-shell--out-of-turn-speech-timer)
      (should-not emacsvox-agent-shell--out-of-turn-pending-ids)
      (should
       (= 0
          (hash-table-count
           emacsvox-agent-shell--out-of-turn-section-markers)))
      (should
       (stringp
        (gethash qualified-id
                 emacsvox-agent-shell--out-of-turn-delivered-ids)))
      (should
       (equal emacsvox-agent-shell--out-of-turn-delivered-order
              (list qualified-id))))))

(ert-deftest emacsvox-agent-shell-out-of-turn-versions-handle-interleaving ()
  "Interleaved IDs should suppress unchanged bodies and retain changed ones."
  (let ((emacsvox-agent-shell-speech-delay 60))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'response)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--record-out-of-turn-snapshot
           '("message-a" . "First A"))
          (emacsvox-agent-shell--record-out-of-turn-snapshot
           '("message-b" . "First B"))
          (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer)
          (emacsvox-agent-shell--deliver-out-of-turn-pending
           (current-buffer))
          (emacsvox-agent-shell--record-out-of-turn-snapshot
           '("message-b" . "First B"))
          (emacsvox-agent-shell--record-out-of-turn-snapshot
           '("message-a" . "First A, resumed"))
          (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer)
          (emacsvox-agent-shell--deliver-out-of-turn-pending
           (current-buffer)))
        '((icon item)
          (speak "Agent update: First A")
          (icon item)
          (speak "Agent update: First B")
          (icon item)
          (speak "Agent update: First A, resumed"))))
      (should
       (equal emacsvox-agent-shell--out-of-turn-delivered-order
              '("message-a" "message-b"))))))

(ert-deftest emacsvox-agent-shell-out-of-turn-version-cache-is-bounded ()
  "Out-of-turn message digests should retain only the 64 most recent IDs."
  (let ((emacsvox-agent-shell-speech-delay 60))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (dotimes (index 65)
        (emacsvox-agent-shell--record-out-of-turn-snapshot
         (cons (format "message-%d" index)
               (format "Body %d" index))))
      (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer)
      (emacsvox-agent-shell--deliver-out-of-turn-pending (current-buffer))
      (should-not emacsvox-agent-shell--out-of-turn-speech-timer)
      (should
       (= (hash-table-count
           emacsvox-agent-shell--out-of-turn-delivered-ids)
          64))
      (should
       (= (length emacsvox-agent-shell--out-of-turn-delivered-order)
          64))
      (should-not
       (gethash "message-0"
                emacsvox-agent-shell--out-of-turn-delivered-ids))
      (should
       (gethash "message-64"
                emacsvox-agent-shell--out-of-turn-delivered-ids)))))

(ert-deftest emacsvox-agent-shell-out-of-turn-versions-are-session-local ()
  "Selecting a session should prevent prior message versions suppressing it."
  (let ((emacsvox-agent-shell-speech-delay 60)
        (snapshot '("shared-message" . "Same body")))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'response)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--record-out-of-turn-snapshot snapshot)
          (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer)
          (emacsvox-agent-shell--deliver-out-of-turn-pending
           (current-buffer))
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . session-selected)))
          (emacsvox-agent-shell--record-out-of-turn-snapshot snapshot)
          (cancel-timer emacsvox-agent-shell--out-of-turn-speech-timer)
          (emacsvox-agent-shell--deliver-out-of-turn-pending
           (current-buffer)))
        '((icon item)
          (speak "Agent update: Same body")
          (icon item)
          (speak "Agent update: Same body"))))
      (should
       (= (hash-table-count
           emacsvox-agent-shell--out-of-turn-delivered-ids)
          1))
      (should
       (equal emacsvox-agent-shell--out-of-turn-delivered-order
              '("shared-message"))))))

(ert-deftest emacsvox-agent-shell-focused-out-of-turn-is-one-submission ()
  "A focused out-of-turn cue and response use one native transaction."
  (let ((emacsvox-comint-autospeak t)
        (emacsvox-agent-shell-speech-level 'response)
        captured
        direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--session-focused-p)
          (lambda (&optional _) t))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (emacsvox-agent-shell--deliver-out-of-turn-body "Rendered update"))
    (should-not direct-output)
    (should (= (length captured) 1))
    (pcase-let* ((`(,content ,arguments ,facts ,module ,occasion)
                   (car captured))
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should (equal content "Agent update: Rendered update"))
      (should (eq (plist-get facts :role) 'agent-response))
      (should (eq module 'agent-shell))
      (should (eq occasion 'notification))
      (should
       (equal
        (mapcar #'emacsvox-aural-compatibility-action-value actions)
        '(item))))))

(ert-deftest emacsvox-agent-shell-out-of-turn-background-notifies-by-name ()
  "A background out-of-turn message should identify its session, not its body."
  (let ((buffer (generate-new-buffer "Codex Agent @ late-update"))
        (emacsvox-agent-shell-speech-delay 0.001))
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local emacsvox-comint-autospeak t)
          (setq-local emacsvox-agent-shell-speech-level 'notify)
          (setq-local agent-shell-section-functions
                      '(emacsvox-agent-shell--record-response-section))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (cl-letf
                  (((symbol-function
                     'emacsvox-agent-shell--session-focused-p)
                    (lambda (&optional _buffer) nil)))
                (emacsvox-agent-shell-test--render-response-section
                 :namespace-id "out-of-turn"
                 :block-id "message-2-agent_message_chunk"
                 :body "Private response body")
                (sit-for 0.01)))
            '((notify-icon item)
              (notify
               "Codex Agent @ late-update. Agent update available.")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-out-of-turn-respects-suppression-levels ()
  "Notify-only focused and quiet sessions should suppress agent updates."
  (dolist (case '((t notify) (t quiet) (nil quiet)))
    (let ((emacsvox-agent-shell-speech-delay 0.001))
      (with-temp-buffer
        (setq major-mode 'agent-shell-mode)
        (setq-local emacsvox-comint-autospeak t)
        (setq-local emacsvox-agent-shell-speech-level (cadr case))
        (setq-local agent-shell-section-functions
                    '(emacsvox-agent-shell--record-response-section))
        (should-not
         (emacsvox-agent-shell-test--capture-events
           (cl-letf
               (((symbol-function
                  'emacsvox-agent-shell--session-focused-p)
                 (lambda (&optional _buffer) (car case))))
             (emacsvox-agent-shell-test--render-response-section
              :namespace-id "out-of-turn"
              :block-id "message-3-agent_message_chunk"
              :body "Suppressed response")
             (sit-for 0.01))))))))

(ert-deftest emacsvox-agent-shell-restored-content-stays-automatically-silent ()
  "Inactive restored content should not be mistaken for an out-of-turn update."
  (let ((emacsvox-agent-shell-speech-delay 0.001))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell-speech-level 'full)
      (setq-local agent-shell-section-functions
                  '(emacsvox-agent-shell--record-response-section))
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (emacsvox-agent-shell-test--render-response-section
          :namespace-id "restored-turn"
          :block-id "message-agent_message_chunk"
          :body "Historical answer")
         (sit-for 0.01)))
      (should-not emacsvox-agent-shell--out-of-turn-speech-timer)
      (should-not emacsvox-agent-shell--out-of-turn-pending-ids)
      (should-not emacsvox-agent-shell--out-of-turn-bodies))))

(ert-deftest emacsvox-agent-shell-out-of-turn-cleanup-cancels-delivery ()
  "Response-section cleanup should cancel queued out-of-turn speech."
  (let ((emacsvox-agent-shell-speech-delay 60)
        marker-pair)
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local emacsvox-comint-autospeak t)
      (setq-local agent-shell-section-functions nil)
      (emacsvox-agent-shell--response-section-setup)
      (emacsvox-agent-shell-test--render-response-section
       :namespace-id "out-of-turn"
       :block-id "message-4-agent_message_chunk"
       :body "Queued response")
      (should (timerp emacsvox-agent-shell--out-of-turn-speech-timer))
      (should emacsvox-agent-shell--out-of-turn-pending-ids)
      (setq marker-pair
            (gethash
             "out-of-turn-message-4-agent_message_chunk"
             emacsvox-agent-shell--out-of-turn-section-markers))
      (emacsvox-agent-shell--response-section-cleanup)
      (should-not
       (memq #'emacsvox-agent-shell--record-response-section
             agent-shell-section-functions))
      (should-not emacsvox-agent-shell--out-of-turn-speech-timer)
      (should-not emacsvox-agent-shell--out-of-turn-pending-ids)
      (should-not emacsvox-agent-shell--out-of-turn-section-markers)
      (should-not emacsvox-agent-shell--out-of-turn-bodies)
      (should-not emacsvox-agent-shell--out-of-turn-delivered-ids)
      (should-not emacsvox-agent-shell--out-of-turn-delivered-order)
      (should-not (marker-buffer (car marker-pair)))
      (should-not (marker-buffer (cdr marker-pair))))))

(ert-deftest emacsvox-agent-shell-latest-answer-keeps-only-response-bodies ()
  "Latest-answer extraction should retain voiced answers and omit activity."
  (let* ((response
          (emacsvox-agent-shell-test--rendered-interaction-response))
         (answer
          (emacsvox-agent-shell--agent-answer-from-response response)))
    (should
     (equal (substring-no-properties answer)
            "First answer\nSecond answer"))
    (should-not (string-match-p "reasoning\\|Tool\\|plan"
                                (substring-no-properties answer)))
    (should
     (eq (emacsvox-agent-shell-test--face-at-text answer "First")
         'agent-shell-markdown-bold))
    (should
     (eq (emacsvox-agent-shell-test--face-at-text answer "Second")
         'agent-shell-markdown-inline-code))))

(ert-deftest emacsvox-agent-shell-latest-answer-has-plain-legacy-fallback ()
  "Unannotated legacy interaction responses should remain explicitly readable."
  (let* ((response
          (propertize "Legacy answer" 'face 'agent-shell-markdown-bold))
         (answer
          (emacsvox-agent-shell--agent-answer-from-response response)))
    (should (equal (substring-no-properties answer) "Legacy answer"))
    (should
     (eq (get-text-property 0 'face answer)
         'agent-shell-markdown-bold)))
  (let ((thought-only
         (propertize
          "Private reasoning"
          'agent-shell-ui-state
          '((:qualified-id . "turn-1-agent_thought_chunk"))
          'agent-shell-ui-section 'body)))
    (should-not
     (emacsvox-agent-shell--agent-answer-from-response thought-only))))

(ert-deftest emacsvox-agent-shell-response-overview-is-structural-and-bounded ()
  "Response overview should count structure and read only a bounded opening."
  (let ((answer
         (concat
          (propertize
           "Summary" 'face 'agent-shell-markdown-header-1)
          "\nImplemented the completion fix. More details follow.\n"
          (propertize
           "(message \"ok\")"
           'agent-shell-markdown-source-block-body t)
          "\n"
          (propertize
           "Name │ Value"
           'agent-shell-markdown-table-source "| Name | Value |"))))
    (should
     (equal
      (emacsvox-agent-shell--response-overview answer)
      (concat
       "Last completed response: 4 lines, 1 heading, 1 code block, 1 table. "
       "Begins: Summary Implemented the completion fix."))))
  (let ((overview
         (emacsvox-agent-shell--response-overview
          (make-string 200 ?x))))
    (should
     (string-prefix-p "Last completed response: 1 line. Begins: " overview))
    (should (string-suffix-p ", continued" overview))
    (should-not (string-match-p (make-string 121 ?x) overview)))
  (let ((answer
         (concat
          (propertize "One" 'face 'agent-shell-markdown-header-1)
          "\nIntro.\n"
          (propertize "Two" 'face 'agent-shell-markdown-header-2)
          "\n"
          (propertize "code one" 'agent-shell-markdown-source-block-body t)
          "\nplain\n"
          (propertize "code two" 'agent-shell-markdown-source-block-body t)
          "\n"
          (propertize "table one" 'agent-shell-markdown-table-source "one")
          "\nplain\n"
          (propertize "table two" 'agent-shell-markdown-table-source "two"))))
    (should
     (equal
      (emacsvox-agent-shell--response-overview answer)
      (concat
       "Last completed response: 9 lines, 2 headings, 2 code blocks, 2 tables. "
       "Begins: One Intro.")))))

(ert-deftest emacsvox-agent-shell-response-overview-counts-rendered-markdown ()
  "Overview counts should follow current agent-shell Markdown properties."
  (with-temp-buffer
    (setq-local agent-shell-section-functions nil)
    (emacsvox-agent-shell-test--render-response-section
     :namespace-id "turn-1" :block-id "answer-agent_message_chunk"
     :body
     (concat
      "# Result\n\nImplemented the fix.\n\n"
      "```elisp\n(+ 1 2)\n```\n\n"
      "| Name | Value |\n| --- | --- |\n| one | 1 |"))
    (should
     (equal
      (emacsvox-agent-shell--response-overview
       (emacsvox-agent-shell--agent-answer-from-response
        (buffer-string)))
      (concat
       "Last completed response: 13 lines, 1 heading, 1 code block, 1 table. "
       "Begins: Result Implemented the fix.")))))

(ert-deftest emacsvox-agent-shell-speak-response-overview-is-explicit ()
  "Overview speech should work at quiet level without reading the full answer."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local emacsvox-comint-autospeak nil)
    (setq-local emacsvox-agent-shell-speech-level 'quiet)
    (let ((position (point)))
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--latest-agent-answer-state)
            (lambda ()
              '(:answer "Implemented the fix. Unspoken detail follows."
                :in-progress nil))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell-speak-response-overview))
          '((stop nil)
            (icon item)
            (speak
             "Last completed response: 1 line. Begins: Implemented the fix.")))))
      (should (= (point) position)))))

(ert-deftest emacsvox-agent-shell-speak-last-response-works-in-session-views ()
  "Explicit last-response speech should work without moving shell or viewport."
  (let ((shell (generate-new-buffer " *agent-shell-last-response*"))
        (viewport (generate-new-buffer " *agent-shell-last-viewport*"))
        (response
         (emacsvox-agent-shell-test--rendered-interaction-response)))
    (unwind-protect
        (progn
          (with-current-buffer shell
            (insert "shell position")
            (goto-char 3)
            (setq major-mode 'agent-shell-mode)
            (setq-local emacsvox-comint-autospeak nil)
            (setq-local emacsvox-agent-shell-speech-level 'quiet))
          (with-current-buffer viewport
            (insert "viewport position")
            (goto-char 5)
            (setq major-mode 'agent-shell-viewport-view-mode)
            (setq-local emacsvox-comint-autospeak nil)
            (setq-local emacsvox-agent-shell-speech-level 'quiet))
          (cl-letf
              (((symbol-function 'emacsvox-agent-shell--session-buffer)
                (lambda (&optional _buffer) shell))
               ((symbol-function 'agent-shell-goto-last-interaction)
                (lambda ()
                  (should (eq (current-buffer) shell))
                  (goto-char (point-max))))
               ((symbol-function 'agent-shell-interaction-at-point)
                (lambda () `((:response . ,response)))))
            (dolist (buffer (list shell viewport))
              (with-current-buffer buffer
                (let ((point-before (point))
                      (shell-point-before
                       (with-current-buffer shell (point))))
                  (let* ((events
                          (emacsvox-agent-shell-test--capture-events
                            (emacsvox-agent-shell-speak-last-response)))
                         (spoken (cadr (nth 2 events))))
                    (should
                     (equal (mapcar #'car events) '(stop icon speak)))
                    (should
                     (equal (substring-no-properties spoken)
                            "First answer\nSecond answer"))
                    (should
                     (eq
                      (emacsvox-agent-shell-test--face-at-text
                       spoken "First")
                      'agent-shell-markdown-bold)))
                  (should (= (point) point-before))
                  (should
                   (= (with-current-buffer shell (point))
                      shell-point-before)))))))
      (when (buffer-live-p viewport)
        (kill-buffer viewport))
      (when (buffer-live-p shell)
        (kill-buffer shell)))))

(ert-deftest emacsvox-agent-shell-response-commands-report-empty-session ()
  "Explicit response commands should report when no answer is available."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let ((position (point)))
      (cl-letf (((symbol-function 'agent-shell-goto-last-interaction)
                 (lambda () nil))
                ((symbol-function 'agent-shell-interaction-at-point)
                 (lambda () nil)))
        (dolist (command '(emacsvox-agent-shell-speak-last-response
                           emacsvox-agent-shell-speak-response-overview))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (funcall command))
            '((icon warn-user)
              (speak "No agent response available."))))))
      (should (= (point) position)))))

(ert-deftest emacsvox-agent-shell-user-message-fixture-is-semantic ()
  "A restored user-message fixture should retain its speaker identity."
  (let* ((updates
          (emacsvox-agent-shell-test--session-updates
           "user-message-chunk.traffic" "user_message_chunk"))
         (text (map-nested-elt
                (car updates) '(:object params update content text))))
    (should (= 1 (length updates)))
    (should
     (equal
      (emacsvox-agent-shell-test--speak-pending
       (list (cons "fixture-user_message_chunk" text)))
      (list (list 'icon 'item)
            (list 'speak (concat "User: " text)))))))

(ert-deftest emacsvox-agent-shell-enable-activates-existing-shells-symmetrically ()
  "Enable should fully activate existing shells and disable should restore them."
  (let ((automatic (generate-new-buffer " *agent-shell-automatic-test*"))
        (override (generate-new-buffer " *agent-shell-override-test*"))
        (agent-shell-mode-hook nil)
        (agent-shell-viewport-edit-mode-hook nil)
        (agent-shell-viewport-view-mode-hook nil)
        automatic-pronunciations
        override-pronunciations)
    (unwind-protect
        (progn
          (with-current-buffer automatic
            (setq major-mode 'agent-shell-mode)
            (setq-local
             agent-shell--state
             (list (cons :buffer automatic)
                   (cons :event-subscriptions nil)))
            (setq-local emacsvox-aural-module 'comint)
            (setq-local emacsvox-aural-source-transform-function #'identity)
            (setq-local emacsvox-agent-shell-speech-level 'response)
            (kill-local-variable 'emacsvox-comint-autospeak)
            (kill-local-variable 'tts-punctuation-mode)
            (setq automatic-pronunciations
                  (make-hash-table :test #'equal))
            (puthash "custom" "pronunciation" automatic-pronunciations)
            (setq-local emacsvox-pronounce-table automatic-pronunciations))
          (with-current-buffer override
            (setq major-mode 'agent-shell-mode)
            (setq-local
             agent-shell--state
             (list (cons :buffer override)
                   (cons :event-subscriptions nil)))
            (setq-local emacsvox-agent-shell-speech-level 'response)
            (setq-local emacsvox-comint-autospeak nil))
          (cl-letf (((symbol-function
                      'emacsvox-agent-shell--upgrade-response-monitoring)
                     #'ignore)
                    ((symbol-function 'emacsvox-agent-shell--install-advice)
                     #'ignore)
                    ((symbol-function 'emacsvox-agent-shell--remove-advice)
                     #'ignore)
                    ((symbol-function 'buffer-list)
                     (lambda () (list automatic override))))
            (emacsvox-agent-shell-enable)
            (emacsvox-agent-shell-enable)
            (with-current-buffer automatic
              (should emacsvox-agent-shell--buffer-activation-active-p)
              (should (eq emacsvox-aural-module 'agent-shell))
              (should
               (eq emacsvox-aural-source-transform-function
                   #'emacsvox-agent-shell--prepare-speech-text))
              (should (local-variable-p 'emacsvox-comint-autospeak))
              (should emacsvox-comint-autospeak)
              (should (emacsvox-agent-shell--should-speak-p automatic))
              (should (local-variable-p 'tts-punctuation-mode))
              (should-not (eq emacsvox-pronounce-table
                              automatic-pronunciations))
              (should (= 4 (length (map-elt
                                    agent-shell--state
                                    :event-subscriptions)))))
            (with-current-buffer override
              (should (local-variable-p 'emacsvox-comint-autospeak))
              (should-not emacsvox-comint-autospeak)
              (should-not (emacsvox-agent-shell--should-speak-p override))
              (should (= 4 (length (map-elt
                                    agent-shell--state
                                    :event-subscriptions))))
              ;; Changes made after activation belong to the user.
              (setq-local emacsvox-aural-module 'custom-agent)
              (setq-local emacsvox-aural-source-transform-function #'ignore)
              (puthash "session" "override" emacsvox-pronounce-table)
              (setq override-pronunciations emacsvox-pronounce-table))
            ;; Cleaning one owner must not affect another live session.
            (with-current-buffer automatic
              (emacsvox-agent-shell--buffer-cleanup)
              (should-not emacsvox-agent-shell--buffer-activation-active-p)
              (should-not emacsvox-agent-shell--buffer-activation-values)
              (should (eq emacsvox-aural-module 'comint))
              (should (eq emacsvox-aural-source-transform-function #'identity))
              (should-not (local-variable-p 'emacsvox-comint-autospeak))
              (should-not (local-variable-p 'tts-punctuation-mode))
              (should (eq emacsvox-pronounce-table
                          automatic-pronunciations))
              (should-not (map-elt agent-shell--state
                                   :event-subscriptions)))
            (with-current-buffer override
              (should emacsvox-agent-shell--buffer-activation-active-p)
              (should (= 4 (length (map-elt
                                    agent-shell--state
                                    :event-subscriptions)))))
            (emacsvox-agent-shell-disable)
            (emacsvox-agent-shell-disable)
            (with-current-buffer override
              (should-not emacsvox-agent-shell--buffer-activation-active-p)
              (should (local-variable-p 'emacsvox-comint-autospeak))
              (should-not emacsvox-comint-autospeak)
              (should (eq emacsvox-aural-module 'custom-agent))
              (should (eq emacsvox-aural-source-transform-function #'ignore))
              (should (eq emacsvox-pronounce-table override-pronunciations))
              (should (equal (gethash "session" emacsvox-pronounce-table)
                             "override"))
              (should-not (map-elt agent-shell--state
                                   :event-subscriptions)))))
      (when (buffer-live-p automatic)
        (kill-buffer automatic))
      (when (buffer-live-p override)
        (kill-buffer override)))))

(ert-deftest emacsvox-agent-shell-enable-disable-manages-current-targets ()
  "Enable and disable should manage the hook and existing advice targets."
  (let ((saved-hook agent-shell-mode-hook)
        (saved-viewport-edit-hook agent-shell-viewport-edit-mode-hook)
        (saved-viewport-view-hook agent-shell-viewport-view-mode-hook)
        (saved-advice (emacsvox-agent-shell-test--saved-advice-state)))
    (unwind-protect
        (progn
          (emacsvox-agent-shell-enable)
          (should-not (memq #'emacsvox-agent-shell-speech-setup
                            agent-shell-mode-hook))
          (should (memq #'emacsvox-agent-shell--buffer-setup
                        agent-shell-mode-hook))
          (should
           (memq #'emacsvox-agent-shell--table-navigation-setup
                 agent-shell-viewport-edit-mode-hook))
          (should
           (memq #'emacsvox-agent-shell--table-navigation-setup
                 agent-shell-viewport-view-mode-hook))
          (should-not
           (memq #'emacsvox-agent-shell--permission-event-setup
                 agent-shell-mode-hook))
          (should-not
           (memq #'emacsvox-agent-shell--lifecycle-event-setup
                 agent-shell-mode-hook))
          (should-not
           (memq #'emacsvox-agent-shell--tool-call-event-setup
                 agent-shell-mode-hook))
          (dolist (entry emacsvox-agent-shell--advice-list)
            (pcase-let ((`(,target ,_where ,function) entry))
              (when (fboundp target)
                (should (advice-member-p function target)))))
          (emacsvox-agent-shell-disable)
          (should-not (memq #'emacsvox-agent-shell-speech-setup
                            agent-shell-mode-hook))
          (should-not (memq #'emacsvox-agent-shell--buffer-setup
                            agent-shell-mode-hook))
          (should-not
           (memq #'emacsvox-agent-shell--table-navigation-setup
                 agent-shell-viewport-edit-mode-hook))
          (should-not
           (memq #'emacsvox-agent-shell--table-navigation-setup
                 agent-shell-viewport-view-mode-hook))
          (should-not (memq #'emacsvox-agent-shell--permission-event-setup
                            agent-shell-mode-hook))
          (should-not (memq #'emacsvox-agent-shell--lifecycle-event-setup
                            agent-shell-mode-hook))
          (should-not (memq #'emacsvox-agent-shell--tool-call-event-setup
                            agent-shell-mode-hook))
          (dolist (entry emacsvox-agent-shell--advice-list)
            (pcase-let ((`(,target ,_where ,function) entry))
              (should-not (advice-member-p function target)))))
      (setq agent-shell-mode-hook saved-hook)
      (setq agent-shell-viewport-edit-mode-hook saved-viewport-edit-hook
            agent-shell-viewport-view-mode-hook saved-viewport-view-hook)
      (emacsvox-agent-shell-test--restore-advice-state saved-advice))))

(ert-deftest emacsvox-agent-shell-enable-disable-feedback-is-native ()
  "Interactive integration lifecycle feedback submits atomically."
  (let ((agent-shell-mode-hook nil)
        (agent-shell-viewport-edit-mode-hook nil)
        (agent-shell-viewport-view-mode-hook nil))
    (cl-letf (((symbol-function 'called-interactively-p)
               (lambda (&rest _) t))
              ((symbol-function
                'emacsvox-agent-shell--upgrade-response-monitoring)
               #'ignore)
              ((symbol-function 'emacsvox-agent-shell--install-advice)
               #'ignore)
              ((symbol-function 'emacsvox-agent-shell--remove-advice)
               #'ignore)
              ((symbol-function 'buffer-list) (lambda () nil)))
      (dolist
          (case
           '((emacsvox-agent-shell-enable
              "Enabled Emacsvox agent-shell support")
             (emacsvox-agent-shell-disable
              "Disabled Emacsvox agent-shell support")))
        (let* ((presentations
                (emacsvox-agent-shell-test--capture-presentations
                  (funcall (car case))))
               (presentation (car presentations)))
          (should (= 1 (length presentations)))
          (should (eq (car presentation) 'submit))
          (should (equal (nth 1 presentation) (cadr case)))
          (should
           (eq (plist-get (nth 2 presentation) :role) 'agent-session))
          (should (eq (nth 4 presentation) 'state-change)))))))

(ert-deftest emacsvox-agent-shell-vertical-motion-silences-toggle-hint ()
  "Arrowing should filter the toggle hint until cursor sensors have run."
  (dolist (command '(next-line previous-line))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local ems--message-filter "Decrypting")
      (let ((this-command command))
        (emacsvox-agent-shell--filter-vertical-toggle-hint))
      (should (string-match-p ems--message-filter "Decrypting"))
      (should (string-match-p ems--message-filter "Press RET to toggle"))
      (emacsvox-agent-shell--restore-message-filter)
      (should (equal ems--message-filter "Decrypting")))))

(ert-deftest emacsvox-agent-shell-toggle-hint-filter-is-narrow ()
  "Non-vertical commands should not alter the message filter."
  (dolist (command '(forward-char agent-shell-next-item ignore))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local ems--message-filter "original")
      (let ((this-command command))
        (emacsvox-agent-shell--filter-vertical-toggle-hint))
      (should (equal ems--message-filter "original")))))

(ert-deftest emacsvox-agent-shell-vertical-entry-adds-block-facts-once ()
  "Arrow movement should add facts only when it enters another block."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let* ((locations (emacsvox-agent-shell--block-locations))
           (response
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'agent-response))
             locations))
           (plan
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'plan))
             locations))
           entered-facts entered-module entered-occasion same-block-facts)
      (goto-char (plist-get response :position))
      (let ((this-command 'next-line))
        (emacsvox-agent-shell--vertical-navigation-pre-command))
      (goto-char (plist-get plan :position))
      (emacsvox-agent-shell--speak-line-around
       (lambda (&rest _)
         (setq
          entered-facts (copy-tree emacsvox-aural-submission-facts)
          entered-module emacsvox-aural-submission-module
          entered-occasion emacsvox-aural-submission-occasion)))
      (should (eq (plist-get entered-facts :role) 'agent-plan))
      (should (eq (plist-get entered-facts :agent-block-kind) 'plan))
      (should (eq (plist-get entered-facts :visibility) 'expanded))
      (should (equal (plist-get entered-facts :events) '(focus-entered)))
      (should (eq entered-module 'agent-shell))
      (should (eq entered-occasion 'navigation))
      (emacsvox-agent-shell--vertical-navigation-post-command)
      (goto-char (plist-get plan :position))
      (let ((this-command 'next-line))
        (emacsvox-agent-shell--vertical-navigation-pre-command))
      (search-forward "One step")
      (let ((emacsvox-aural-submission-facts nil))
        (emacsvox-agent-shell--speak-line-around
         (lambda (&rest _)
           (setq same-block-facts emacsvox-aural-submission-facts))))
      (should-not same-block-facts))))

(ert-deftest emacsvox-agent-shell-line-navigation-speech-is-bounded ()
  "Line navigation should bound only its speech copy."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let ((emacsvox-agent-shell-line-speech-max-characters 5)
          (emacsvox-agent-shell--line-navigation-speech-p t))
      (let* ((source (propertize "abcdefghij" 'face 'bold))
             (speech
              (emacsvox-agent-shell--prepare-speech-text source)))
        (should
         (equal
          (substring-no-properties speech)
          "abcde [line truncated; 5 characters omitted]"))
        (should (eq (get-text-property 0 'face speech) 'bold))))
    (let ((emacsvox-agent-shell-line-speech-max-characters 5)
          (emacsvox-agent-shell--line-navigation-speech-p nil))
      (should
       (equal
        (emacsvox-agent-shell--prepare-speech-text "abcdefghij")
        "abcdefghij")))))

(ert-deftest emacsvox-agent-shell-physical-line-bypasses-core-length-prompt ()
  "Bounded Agent Shell navigation should not invoke core long-line policy."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (insert "abcdefghij")
    (goto-char (point-min))
    (let ((emacsvox-agent-shell-line-speech-max-characters 5)
          (ems--speak-max-length 4)
          observed-limit
          spoken)
      (emacsvox-agent-shell--speak-line-around
       (lambda (&rest _)
         (setq
          observed-limit ems--speak-max-length
          spoken
          (emacsvox-agent-shell--prepare-speech-text
           (buffer-substring (point-min) (point-max))))))
      (should (= observed-limit most-positive-fixnum))
      (should
       (equal
        spoken "abcde [line truncated; 5 characters omitted]")))))

(ert-deftest emacsvox-agent-shell-visual-line-speech-is-bounded ()
  "Visual line navigation should apply the same compilation bound."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let ((emacsvox-agent-shell-line-speech-max-characters 5)
          spoken)
      (emacsvox-agent-shell--speak-visual-line-around
       (lambda (&rest _)
         (setq spoken
               (emacsvox-agent-shell--prepare-speech-text "abcdefghij"))))
      (should
       (equal spoken "abcde [line truncated; 5 characters omitted]")))))

(ert-deftest emacsvox-agent-shell-visual-line-kill-speaks-only-killed-input ()
  "A visual-line kill should omit the prompt and its visible chat label."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (insert
     (propertize
      "Codex> " 'font-lock-face
      '(comint-highlight-prompt comint-highlight-prompt))
     "this ")
    (goto-char (+ (point-min) (length "Codex> ")))
    (let ((emacsvox-agent-shell--chat-label-context
           '(:category agent-shell-chat-me :text "Me" :editable t))
          spoken)
      (cl-letf (;; Batch frames do not provide reliable visual-line geometry.
                ((symbol-function 'end-of-visual-line)
                 (lambda (&optional _)
                   (goto-char (line-end-position))))
                ((symbol-function 'emacsvox-icon)
                 (lambda (&rest _) nil))
                ((symbol-function 'tts-speak)
                 (lambda (text)
                   (push (substring-no-properties text) spoken))))
        (funcall-interactively #'kill-visual-line))
      (should (equal (nreverse spoken) '("this ")))
      (should (equal (buffer-string) "Codex> ")))))

(ert-deftest emacsvox-agent-shell-folded-visual-line-uses-visible-heading ()
  "Folded visual-line speech should not extract its invisible body."
  (with-temp-buffer
    (let ((start (point))
          spoken)
      (insert "Thought heading\n")
      (let ((body-start (point)))
        (insert (make-string 10000 ?x))
        (add-text-properties body-start (point) '(invisible t)))
      (add-text-properties
       start (point)
       '(agent-shell-ui-state ((:qualified-id . "1-agent_thought_chunk")
                               (:collapsed . t))))
      (add-text-properties
       start (+ start (length "Thought heading"))
       '(agent-shell-ui-section label-left))
      (setq major-mode 'agent-shell-mode
            buffer-invisibility-spec t)
      (goto-char start)
      (cl-letf
          (((symbol-function 'emacsvox-speak--present-physical-line)
            (lambda (&rest _)
              (ert-fail "Folded navigation used physical-line speech"))))
        (emacsvox-agent-shell--speak-visual-line-around
         (lambda (&rest _)
           (setq spoken
                 (buffer-substring-no-properties
                  (point-min) (point-max))))))
      (should (equal spoken "Thought heading")))))

(ert-deftest emacsvox-agent-shell-folded-wrapped-heading-speaks-current-row ()
  "Wrapped folded headings should not repeat their complete physical line."
  (with-temp-buffer
    (let* ((row-width 20)
           (command (concat "command " (make-string 80 ?x)))
           (range
            (agent-shell-ui-update-fragment
             (agent-shell-ui-make-fragment-model
              :namespace-id "1" :block-id "tool-1"
              :label-left "completed" :label-right command
              :body "hidden tool output")
             :expanded nil))
           (heading-start (map-nested-elt range '(:block :start)))
           spoken narrowed-end)
      (setq major-mode 'agent-shell-mode
            buffer-invisibility-spec t)
      (goto-char heading-start)
      (let ((heading-end (line-end-position)))
        ;; Model the second display row deterministically.  Batch frames do
        ;; not reliably expose terminal wrapping to `vertical-motion'.
        (goto-char (+ heading-start row-width))
        (should
         (eq (get-text-property (point) 'agent-shell-ui-section)
             'label-right))
        (cl-letf
            (((symbol-function 'beginning-of-visual-line)
              (lambda (&rest _)
                (goto-char
                 (+ heading-start
                    (* row-width
                       (/ (- (point) heading-start) row-width))))))
             ((symbol-function 'end-of-visual-line)
              (lambda (&rest _)
                (goto-char (min heading-end (+ (point) row-width)))))
             ((symbol-function 'emacsvox-speak--present-physical-line)
              (lambda (&rest _)
                (ert-fail "Wrapped heading used physical-line speech"))))
          (emacsvox-agent-shell--speak-visual-line-around
           (lambda (&rest _)
             (let ((bounds
                    (emacsvox-agent-shell--visual-line-source-bounds)))
               (setq
                narrowed-end (point-max)
                spoken
                (buffer-substring-no-properties
                 (car bounds) (cdr bounds)))))))
        (should (= narrowed-end heading-end))
        (should-not (string-match-p "completed" spoken))
        (should (string-match-p "x" spoken))
        (should (<= (length spoken) row-width))))))

(ert-deftest emacsvox-agent-shell-collapsed-body-keeps-visual-line-presenter ()
  "Collapsed fragment metadata on body text must not force physical lines."
  (with-temp-buffer
    (insert
     (propertize
      "wrapped body text"
      'agent-shell-ui-state
      '((:qualified-id . "1-agent_message_chunk") (:collapsed . t))
      'agent-shell-ui-section 'body))
    (goto-char (point-min))
    (let (presenter)
      (cl-letf
          (((symbol-function 'emacsvox-speak--present-physical-line)
            (lambda (&rest _) (setq presenter 'physical))))
        (emacsvox-agent-shell--speak-visual-line-around
         (lambda (&rest _) (setq presenter 'visual))))
      (should (eq presenter 'visual)))))

(ert-deftest emacsvox-agent-shell-visible-block-text-omits-hidden-content ()
  "Semantic visible text should exclude collapsed buffer intervals."
  (with-temp-buffer
    (insert "before ")
    (let ((hidden-start (point)))
      (insert (make-string 10000 ?x))
      (add-text-properties hidden-start (point) '(invisible t)))
    (insert " after")
    (setq buffer-invisibility-spec t)
    (should
     (equal
      (emacsvox-agent-shell--visible-block-text (point-min) (point-max))
      "before  after"))))

(ert-deftest emacsvox-agent-shell-visual-lines-leave-blank-policy-to-core ()
  "Agent Shell should not duplicate core visual-line blank presentation."
  (dolist (case '((agent-shell-mode "")
                  (agent-shell-mode "  ")
                  (agent-shell-viewport-view-mode "")
                  (agent-shell-viewport-edit-mode "\t")
                  (agent-shell-mode "content")))
    (let ((buffer (generate-new-buffer " *agent-shell-visual-line-test*"))
          events)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer buffer)
            (insert (nth 1 case))
            (goto-char (point-min))
            (setq major-mode (nth 0 case))
            (cl-letf
                (((symbol-function 'tts-stop)
                  (lambda (&rest _)
                    (ert-fail "Agent Shell stopped core visual speech")))
                 ((symbol-function 'emacsvox-speak--present-line-condition)
                  (lambda (&rest _)
                    (ert-fail "Agent Shell duplicated core blank feedback"))))
              (emacsvox-agent-shell--speak-visual-line-around
               (lambda (&rest _) (push 'original events))))
            (should (equal events '(original))))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-visual-line-keeps-nonblank-eol-speech ()
  "A prompt field boundary must not replace Agent Shell speech with a tone."
  (let ((buffer
         (generate-new-buffer " *agent-shell-visual-eol-test*"))
        events)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (insert
           (propertize
            "Codex> " 'field 'output 'rear-nonsticky '(field))
           "\n\n")
          (goto-char (point-min))
          (goto-char (line-end-position))
          (setq major-mode 'agent-shell-mode)
          (visual-line-mode 1)
          (cl-letf
              (((symbol-function 'beginning-of-visual-line)
                (lambda (&rest _) (goto-char (line-beginning-position))))
               ((symbol-function 'end-of-visual-line)
                (lambda (&rest _) (goto-char (line-end-position))))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest _)
                  (push (list 'speak content) events)))
               ((symbol-function 'emacsvox-aural-submit-actions)
                (lambda (&rest arguments)
                  (push (list 'actions arguments) events))))
            (emacsvox-speak-visual-line))
          (should (equal (nreverse events) '((speak "Codex> ")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-folded-header-is-not-a-blank-line ()
  "Invisible folded content must not turn its visible header into a blank."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (visual-line-mode 1)
    (let ((location
           (seq-find
            (lambda (item)
              (and
               (eq (plist-get item :visibility) 'folded)
               (get-char-property
                (plist-get item :position) 'invisible)))
            (emacsvox-agent-shell--block-locations))))
      (should location)
      (goto-char (plist-get location :position))
      (should-not (emacsvox-speak--visual-line-condition)))))

(ert-deftest emacsvox-agent-shell-toggle-filter-restores-after-sensors ()
  "Restore the original filter after agent-shell's cursor sensors run."
  (with-temp-buffer
    (cursor-sensor-mode 1)
    (emacsvox-agent-shell--vertical-toggle-hint-setup)
    (should
     (< (seq-position post-command-hook #'cursor-sensor--detect)
        (seq-position
         post-command-hook
         #'emacsvox-agent-shell--restore-message-filter)))
    (kill-local-variable 'ems--message-filter)
    (let ((this-command 'previous-line))
      (emacsvox-agent-shell--filter-vertical-toggle-hint))
    (should (local-variable-p 'ems--message-filter))
    (emacsvox-agent-shell--restore-message-filter)
    (should-not (local-variable-p 'ems--message-filter))
    (emacsvox-agent-shell--vertical-toggle-hint-cleanup)
    (should-not
     (memq #'emacsvox-agent-shell--filter-vertical-toggle-hint
           pre-command-hook))
    (should-not
     (memq #'emacsvox-agent-shell--vertical-navigation-pre-command
           pre-command-hook))
    (should-not
     (memq #'emacsvox-agent-shell--restore-message-filter
           post-command-hook))
    (should-not
     (memq #'emacsvox-agent-shell--vertical-navigation-post-command
           post-command-hook))))

(ert-deftest emacsvox-agent-shell-permission-fixture-is-urgent ()
  "A fixture permission should use native urgency and be spoken in full."
  (let* ((requests
          (emacsvox-agent-shell-test--permission-requests
           "gemini-permission.traffic"))
         (events (mapcar #'emacsvox-agent-shell-test--permission-event
                         requests)))
    (should (= 1 (length events)))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (dolist (event events)
          (emacsvox-agent-shell--handle-permission-request event)))
      (emacsvox-agent-shell-test--expected-permission-events events)))))

(ert-deftest emacsvox-agent-shell-permission-urgency-reaches-every-stream ()
  "Focused and background permission requests should both remain urgent."
  (let* ((request
          (car (emacsvox-agent-shell-test--permission-requests
                "gemini-permission.traffic")))
         (event (emacsvox-agent-shell-test--permission-event request)))
    (dolist
        (scenario
         '((t notification-stream nil)
           (nil notification-stream t)
           (nil primary-stream nil)))
      (pcase-let ((`(,focused ,notification-stream ,expected-stop) scenario))
        (let ((tts-speaker-process 'primary-stream)
              delivery-policies primary-stop)
          (cl-letf
              (((symbol-function 'emacsvox-agent-shell--session-focused-p)
                (lambda (&optional _) focused))
               ((symbol-function 'tts-notify-process)
                (lambda () notification-stream))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (&rest _)
                  (push emacsvox-aural-submission-delivery-policy
                        delivery-policies)))
               ((symbol-function 'tts-notify-icon) #'ignore)
               ((symbol-function 'tts-notify)
                (lambda (&rest _)
                  (push emacsvox-aural-submission-delivery-policy
                        delivery-policies)))
               ((symbol-function 'tts-stop)
                (lambda () (setq primary-stop t))))
            (emacsvox-agent-shell--handle-permission-request event))
          (should (equal delivery-policies '(urgent)))
          (should (eq primary-stop expected-stop)))))))

(ert-deftest emacsvox-agent-shell-multiple-permission-fixture-is-complete ()
  "Each permission in a fixture should get a complete announcement."
  (let* ((requests
          (emacsvox-agent-shell-test--permission-requests
           "gemini-multiple-permissions.traffic"))
         (events (mapcar #'emacsvox-agent-shell-test--permission-event
                         requests)))
    (should (= 2 (length events)))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (dolist (event events)
          (emacsvox-agent-shell--handle-permission-request event)))
      (emacsvox-agent-shell-test--expected-permission-events events)))))

(ert-deftest emacsvox-agent-shell-permission-subscription-is-idempotent ()
  "The public permission subscription should install once and clean up."
  (let ((buffer (generate-new-buffer " *agent-shell-permission-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local agent-shell--state
                      (list (cons :buffer buffer)
                            (cons :event-subscriptions nil)))
          (let* ((request
                  (car (emacsvox-agent-shell-test--permission-requests
                        "gemini-permission.traffic")))
                 (event
                  (emacsvox-agent-shell-test--permission-event request))
                 (data (map-elt event :data)))
            (emacsvox-agent-shell--permission-event-setup)
            (let ((token emacsvox-agent-shell--permission-subscription))
              (emacsvox-agent-shell--permission-event-setup)
              (should (equal token
                             emacsvox-agent-shell--permission-subscription))
              (should (= 2 (length (map-elt
                                    agent-shell--state
                                    :event-subscriptions)))))
            (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                        '("1-agent_message_chunk"))
            (setq-local emacsvox-agent-shell--pending-bodies
                        (make-hash-table :test #'equal))
            (puthash "1-agent_message_chunk" "Pending answer"
                     emacsvox-agent-shell--pending-bodies)
            (should
             (equal
              (emacsvox-agent-shell-test--capture-events
                (cl-letf (((symbol-function
                            'agent-shell--sync-system-sleep)
                           #'ignore))
                  (agent-shell--emit-event
                   :event 'permission-request :data data)))
              (emacsvox-agent-shell-test--expected-permission-events
               (list event))))
            (should
             (equal emacsvox-agent-shell--pending-speech-qualified-ids
                    '("1-agent_message_chunk")))
            (should (= 1 (hash-table-count
                          emacsvox-agent-shell--pending-bodies)))
            (should (= 1 (hash-table-count
                          emacsvox-agent-shell--permission-action-cache)))
            (emacsvox-agent-shell--permission-event-cleanup)
            (should-not emacsvox-agent-shell--permission-subscription)
            (should-not
             emacsvox-agent-shell--permission-response-subscription)
            (should-not emacsvox-agent-shell--permission-action-cache)
            (should-not (map-elt agent-shell--state
                                 :event-subscriptions))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-permission-announcement-can-be-disabled ()
  "Disabling permission speech should leave a pending response untouched."
  (let ((emacsvox-agent-shell-speak-permissions nil))
    (with-temp-buffer
      (setq-local emacsvox-agent-shell--pending-bodies
                  (make-hash-table :test #'equal))
      (puthash "1-agent_message_chunk" "Pending answer"
               emacsvox-agent-shell--pending-bodies)
      (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                  '("1-agent_message_chunk"))
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (emacsvox-agent-shell--handle-permission-request
          '((:event . permission-request)
            (:data (:tool-call-id . "tool-id")
                   (:tool-call (:title . "Run command")
                               (:permission-actions
                                ((:option . "Allow")))))))))
      (should
       (equal emacsvox-agent-shell--pending-speech-qualified-ids
              '("1-agent_message_chunk")))
      (should (= 1 (hash-table-count
                    emacsvox-agent-shell--pending-bodies))))))

(ert-deftest emacsvox-agent-shell-permission-responses-are-semantic ()
  "Allow, reject, and cancel responses should identify their outcomes."
  (with-temp-buffer
    (let* ((requests
            (emacsvox-agent-shell-test--permission-requests
             "gemini-multiple-permissions.traffic"))
           (events (mapcar #'emacsvox-agent-shell-test--permission-event
                           requests))
           (first (nth 0 events))
           (second (nth 1 events)))
      (ignore
       (emacsvox-agent-shell-test--capture-events
         (dolist (event events)
           (emacsvox-agent-shell--handle-permission-request event))))
      (should (= 2 (hash-table-count
                    emacsvox-agent-shell--permission-action-cache)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-permission-response
           (emacsvox-agent-shell-test--permission-response-event
            first "allow_always")))
        '((icon select-object)
          (speak "Permission granted: Always Allow git, head."))))
      (should (= 1 (hash-table-count
                    emacsvox-agent-shell--permission-action-cache)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-permission-response
           (emacsvox-agent-shell-test--permission-response-event
            second "reject_once")))
        '((icon close-object)
          (speak "Permission denied: Reject."))))
      (should (= 0 (hash-table-count
                    emacsvox-agent-shell--permission-action-cache)))
      (ignore
       (emacsvox-agent-shell-test--capture-events
         (emacsvox-agent-shell--handle-permission-request first)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-permission-response
           (emacsvox-agent-shell-test--permission-response-event
            first nil t)))
        '((icon close-object)
          (speak "Permission cancelled.")))))))

(ert-deftest emacsvox-agent-shell-lifecycle-transitions-are-semantic ()
  "Public lifecycle events should distinguish processing transitions."
  (let ((emacsvox-agent-shell-signal-processing t)
        (emacsvox-agent-shell-processing-start-icon 'progress)
        (emacsvox-agent-shell-processing-end-icon 'task-done))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (dolist (event '(((:event . init-started))
                         ((:event . init-finished))
                         ((:event . input-submitted))
                         ((:event . turn-complete)
                          (:data (:stop-reason . "end_turn")))))
          (emacsvox-agent-shell--handle-lifecycle-event event)))
      '((icon progress)
        (icon task-done)
        (icon progress)
        (icon task-done))))))

(ert-deftest emacsvox-agent-shell-focused-announcement-is-one-submission ()
  "Focused icon and speech feedback use one native aural transaction."
  (let (captured direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--session-focused-p)
          (lambda (&optional _) t))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              arguments
              (copy-tree (plist-get arguments :facts))
              (plist-get arguments :module)
              (plist-get arguments :occasion))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output)))
         ((symbol-function 'tts-speak)
          (lambda (&rest _) (push 'speech direct-output))))
      (emacsvox-agent-shell--deliver-announcement
       (emacsvox-agent-shell--presentation-facts
        'agent-error 'processing-failed)
       'notification 'warn-user
       "Agent error: Connection lost."))
    (should-not direct-output)
    (should (= (length captured) 1))
    (pcase-let* ((`(,content ,arguments ,facts ,module ,occasion)
                   (car captured))
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should (equal content "Agent error: Connection lost."))
      (should (eq (plist-get facts :role) 'agent-error))
      (should (equal (plist-get facts :events) '(processing-failed)))
      (should (eq module 'agent-shell))
      (should (eq occasion 'notification))
      (should
       (equal
        (mapcar #'emacsvox-aural-compatibility-action-value actions)
        '(warn-user))))))

(ert-deftest emacsvox-agent-shell-lifecycle-carries-aural-facts ()
  "Configured processing icons retain semantic lifecycle facts and context."
  (let ((emacsvox-agent-shell-signal-processing t)
        (emacsvox-agent-shell-processing-start-icon 'progress)
        (emacsvox-agent-shell-processing-end-icon 'task-done)
        captured
        direct-output)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--begin-response-turn)
          #'ignore)
         ((symbol-function 'emacsvox-agent-shell--finish-response-turn)
          #'ignore)
         ((symbol-function 'emacsvox-agent-shell--speech-level-at-least-p)
          (lambda (&rest _) t))
         ((symbol-function 'emacsvox-agent-shell--session-focused-p)
          (lambda (&rest _) t))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (let* ((actions
                    (plist-get arguments :compatibility-actions))
                   (icon
                    (emacsvox-aural-compatibility-action-value
                     (car actions))))
              (push
               (list
                icon
                (copy-tree (plist-get arguments :facts))
                (plist-get arguments :module)
                (plist-get arguments :occasion))
               captured))))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon direct-output))))
      (emacsvox-agent-shell--handle-lifecycle-event
       '((:event . input-submitted)))
      (emacsvox-agent-shell--handle-lifecycle-event
       '((:event . turn-complete)
         (:data (:stop-reason . "end_turn")))))
    (should-not direct-output)
    (setq captured (nreverse captured))
    (should (equal (mapcar #'car captured) '(progress task-done)))
    (should
     (equal
      (plist-get (cadr (car captured)) :events)
      '(processing-started)))
    (should
     (equal
      (plist-get (cadr (car captured)) :states)
      '(processing)))
    (should
     (equal
      (plist-get (cadr (cadr captured)) :events)
      '(processing-completed)))
    (dolist (entry captured)
      (should (eq (plist-get (cadr entry) :role) 'agent-session))
      (should (eq (caddr entry) 'agent-shell))
      (should (eq (cadddr entry) 'notification)))))

(ert-deftest emacsvox-agent-shell-focus-includes-associated-viewport ()
  "A selected shell or its viewport should be the focused session."
  (let ((shell (generate-new-buffer "Codex Agent @ focus-test"))
        (viewport (generate-new-buffer
                   "Codex Agent @ focus-test [viewport]"))
        (other (generate-new-buffer " *agent-shell-other*"))
        (emacsvox-agent-shell-foreground-speech-level 'response)
        (emacsvox-agent-shell-background-speech-level 'notify))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer shell
            (setq major-mode 'agent-shell-mode))
          (with-current-buffer viewport
            (setq major-mode 'agent-shell-viewport-view-mode))
          (switch-to-buffer shell)
          (should (emacsvox-agent-shell--session-focused-p shell))
          (should (eq (emacsvox-agent-shell--effective-speech-level shell)
                      'response))
          (switch-to-buffer other)
          (should-not (emacsvox-agent-shell--session-focused-p shell))
          (should (eq (emacsvox-agent-shell--effective-speech-level shell)
                      'notify))
          (switch-to-buffer viewport)
          (should (emacsvox-agent-shell--session-focused-p shell))
          (should (eq (emacsvox-agent-shell--effective-speech-level shell)
                      'response)))
      (dolist (buffer (list shell viewport other))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-speech-level-cycle-is-session-local ()
  "Cycling should reduce speech, cancel queued content, and reset to auto."
  (let ((buffer (generate-new-buffer "Codex Agent @ cycle-test"))
        timer)
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local emacsvox-agent-shell-speech-level 'auto)
          (setq-local emacsvox-agent-shell--pending-bodies
                      (make-hash-table :test #'equal))
          (puthash "1-agent_message_chunk" "Pending response"
                   emacsvox-agent-shell--pending-bodies)
          (setq timer (run-with-timer 3600 nil #'ignore))
          (setq-local emacsvox-agent-shell--pending-speech-timer timer
                      emacsvox-agent-shell--pending-speech-qualified-ids
                      '("1-agent_message_chunk"))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (let ((emacsvox-agent-shell-foreground-speech-level 'response)
                    (emacsvox-agent-shell-background-speech-level 'notify))
                (call-interactively
                 #'emacsvox-agent-shell-cycle-speech-level)))
            '((icon select-object)
              (speak
               "Agent speech notify for Codex Agent @ cycle-test."))))
          (should (eq emacsvox-agent-shell-speech-level 'notify))
          (should-not emacsvox-agent-shell--pending-speech-timer)
          (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
          (should (= 0 (hash-table-count
                        emacsvox-agent-shell--pending-bodies)))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (call-interactively
               #'emacsvox-agent-shell-cycle-speech-level))
            '((icon off)
              (speak "Agent speech quiet for Codex Agent @ cycle-test."))))
          (should (eq emacsvox-agent-shell-speech-level 'quiet))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (call-interactively
               #'emacsvox-agent-shell-cycle-speech-level))
            '((icon select-object)
              (speak "Agent speech full for Codex Agent @ cycle-test."))))
          (should (eq emacsvox-agent-shell-speech-level 'full))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (let ((emacsvox-agent-shell-foreground-speech-level 'response)
                    (emacsvox-agent-shell-background-speech-level 'notify))
                (emacsvox-agent-shell-cycle-speech-level t)))
            '((icon select-object)
              (speak "Agent speech automatic: response when focused, notify in background."))))
          (should (eq emacsvox-agent-shell-speech-level 'auto)))
      (when (timerp timer)
        (cancel-timer timer))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-speech-bindings-upgrade-live-map ()
  "Reloading support should install current speech and navigation controls."
  (let* ((map emacsvox-agent-shell--speech-control-map)
         (current-key (kbd "C-c C-q"))
         (background-key (kbd "C-c C-S-q"))
         (speak-source-key (kbd "C-c C-b"))
         (copy-source-key (kbd "C-c C-y"))
         (last-response-key (kbd "C-c r"))
         (response-overview-key (kbd "C-c R"))
         (next-block-key (kbd "C-c ]"))
         (previous-block-key (kbd "C-c ["))
         (context-next-key (kbd "]"))
         (context-previous-key (kbd "["))
         (saved-current (lookup-key map current-key))
         (saved-background (lookup-key map background-key))
         (saved-speak-source (lookup-key map speak-source-key))
         (saved-copy-source (lookup-key map copy-source-key))
         (saved-last-response (lookup-key map last-response-key))
         (saved-response-overview (lookup-key map response-overview-key))
         (saved-next-block (lookup-key map next-block-key))
         (saved-previous-block (lookup-key map previous-block-key))
         (saved-context-next (lookup-key map context-next-key))
         (saved-context-previous (lookup-key map context-previous-key)))
    (unwind-protect
        (progn
          (define-key map current-key
                      #'emacsvox-agent-shell-cycle-speech-level)
          (define-key map background-key nil)
          (define-key map speak-source-key nil)
          (define-key map copy-source-key nil)
          (define-key map last-response-key nil)
          (define-key map response-overview-key nil)
          (define-key map next-block-key nil)
          (define-key map previous-block-key nil)
          (define-key map context-next-key nil)
          (define-key map context-previous-key nil)
          (emacsvox-agent-shell--install-speech-control-bindings)
          (should
           (eq (lookup-key map current-key)
               #'emacsvox-agent-shell-select-speech-level))
          (should
           (eq (lookup-key map background-key)
               #'emacsvox-agent-shell-select-background-speech-level))
          (should
           (eq (lookup-key map speak-source-key)
               #'emacsvox-agent-shell-speak-source-block))
          (should
           (eq (lookup-key map copy-source-key)
               #'emacsvox-agent-shell-copy-source-block))
          (should
           (eq (lookup-key map last-response-key)
               #'emacsvox-agent-shell-speak-last-response))
          (should
           (eq (lookup-key map response-overview-key)
               #'emacsvox-agent-shell-speak-response-overview))
          (should
           (eq (lookup-key map next-block-key)
               #'emacsvox-agent-shell-next-block-of-type))
          (should
           (eq (lookup-key map previous-block-key)
               #'emacsvox-agent-shell-previous-block-of-type))
          (should
           (eq (lookup-key map context-next-key)
               #'emacsvox-agent-shell-next-block-at-point))
          (should
           (eq (lookup-key map context-previous-key)
               #'emacsvox-agent-shell-previous-block-at-point)))
      (define-key map current-key saved-current)
      (define-key map background-key saved-background)
      (define-key map speak-source-key saved-speak-source)
      (define-key map copy-source-key saved-copy-source)
      (define-key map last-response-key saved-last-response)
      (define-key map response-overview-key saved-response-overview)
      (define-key map next-block-key saved-next-block)
      (define-key map previous-block-key saved-previous-block)
      (define-key map context-next-key saved-context-next)
      (define-key map context-previous-key saved-context-previous))))

(ert-deftest emacsvox-agent-shell-speech-level-control-works-in-viewport ()
  "Viewport selectors should target the shell and remain active in tables."
  (let ((shell (generate-new-buffer "Codex Agent @ viewport-level"))
        (viewport
         (generate-new-buffer "Codex Agent @ viewport-level [viewport]")))
    (unwind-protect
        (progn
          (with-current-buffer shell
            (setq major-mode 'agent-shell-mode)
            (setq-local emacsvox-agent-shell-speech-level 'auto))
          (with-current-buffer viewport
            (setq major-mode 'agent-shell-viewport-view-mode)
            (emacsvox-agent-shell--table-navigation-setup)
            (should emacsvox-agent-shell--speech-control-active)
            (should
             (eq (key-binding (kbd "C-c C-q"))
                 #'emacsvox-agent-shell-select-speech-level))
            (should
             (eq (key-binding (kbd "C-c C-S-q"))
                 #'emacsvox-agent-shell-select-background-speech-level))
            (should
             (eq (key-binding (kbd "C-c C-b"))
                 #'emacsvox-agent-shell-speak-source-block))
            (should
             (eq (key-binding (kbd "C-c C-y"))
                 #'emacsvox-agent-shell-copy-source-block))
            (should
             (eq (key-binding (kbd "C-c ]"))
                 #'emacsvox-agent-shell-next-block-of-type))
            (should
             (eq (key-binding (kbd "C-c ["))
                 #'emacsvox-agent-shell-previous-block-of-type))
            (should
             (eq (key-binding (kbd "]"))
                 #'emacsvox-agent-shell-next-block-at-point))
            (should
             (eq (key-binding (kbd "["))
                 #'emacsvox-agent-shell-previous-block-at-point))
            (setq emacsvox-agent-shell--table-navigation-active t)
            (should
             (eq (key-binding (kbd "C-c C-q"))
                 #'emacsvox-agent-shell-select-speech-level))
            (should
             (eq (key-binding (kbd "C-c C-S-q"))
                 #'emacsvox-agent-shell-select-background-speech-level))
            (should
             (equal
              (emacsvox-agent-shell-test--capture-events
                (cl-letf (((symbol-function 'completing-read)
                           (lambda (&rest _) "notify")))
                  (call-interactively
                   #'emacsvox-agent-shell-select-speech-level)))
              '((icon select-object)
                (speak
                 "Agent speech notify for Codex Agent @ viewport-level."))))
            (emacsvox-agent-shell--table-navigation-cleanup)
            (should-not emacsvox-agent-shell--speech-control-active))
          (with-current-buffer shell
            (should (eq emacsvox-agent-shell-speech-level 'notify))))
      (dolist (buffer (list shell viewport))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-background-selector-cancels-auto-sessions ()
  "Selecting a quiet background default should cancel only affected queues."
  (let ((foreground (generate-new-buffer "Codex Agent @ selector-front"))
        (background (generate-new-buffer "Codex Agent @ selector-back"))
        (forced (generate-new-buffer "Codex Agent @ selector-forced"))
        background-timer forced-timer selected-level)
    (unwind-protect
        (progn
          (dolist (buffer (list foreground background forced))
            (with-current-buffer buffer
              (setq major-mode 'agent-shell-mode)
              (setq-local emacsvox-agent-shell--pending-bodies
                          (make-hash-table :test #'equal))
              (puthash "1-agent_message_chunk" "Pending"
                       emacsvox-agent-shell--pending-bodies)
              (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                          '("1-agent_message_chunk"))))
          (with-current-buffer background
            (setq-local emacsvox-agent-shell-speech-level 'auto)
            (setq background-timer (run-with-timer 3600 nil #'ignore))
            (setq-local emacsvox-agent-shell--pending-speech-timer
                        background-timer))
          (with-current-buffer forced
            (setq-local emacsvox-agent-shell-speech-level 'full)
            (setq forced-timer (run-with-timer 3600 nil #'ignore))
            (setq-local emacsvox-agent-shell--pending-speech-timer
                        forced-timer))
          (with-current-buffer foreground
            (should
             (equal
              (emacsvox-agent-shell-test--capture-events
                (cl-letf
                    (((symbol-function 'completing-read)
                      (lambda (&rest _) "quiet"))
                     ((symbol-function 'buffer-list)
                      (lambda (&optional _frame)
                        (list foreground background forced)))
                     ((symbol-function
                       'emacsvox-agent-shell--session-focused-p)
                      (lambda (&optional buffer)
                        (eq (or buffer (current-buffer)) foreground))))
                  (call-interactively
                   #'emacsvox-agent-shell-select-background-speech-level)
                  (setq selected-level
                        emacsvox-agent-shell-background-speech-level)))
              '((icon off)
                (speak "Background agent speech quiet.")))))
          (should (eq selected-level 'quiet))
          (with-current-buffer background
            (should-not emacsvox-agent-shell--pending-speech-timer)
            (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
            (should (= 0 (hash-table-count
                          emacsvox-agent-shell--pending-bodies))))
          (with-current-buffer forced
            (should (eq emacsvox-agent-shell--pending-speech-timer
                        forced-timer))
            (should emacsvox-agent-shell--pending-speech-qualified-ids)
            (should (= 1 (hash-table-count
                          emacsvox-agent-shell--pending-bodies)))))
      (dolist (timer (list background-timer forced-timer))
        (when (timerp timer)
          (cancel-timer timer)))
      (dolist (buffer (list foreground background forced))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-session-override-beats-focus-default ()
  "A concrete per-session level should apply in foreground or background."
  (with-temp-buffer
    (setq-local emacsvox-agent-shell-speech-level 'full)
    (let ((emacsvox-agent-shell-background-speech-level 'quiet))
      (cl-letf (((symbol-function
                  'emacsvox-agent-shell--session-focused-p)
                 (lambda (&optional _buffer) nil)))
        (should (eq (emacsvox-agent-shell--effective-speech-level) 'full))))))

(ert-deftest emacsvox-agent-shell-response-level-reduces-focused-chatter ()
  "The default focused level should retain responses and completion only."
  (let ((emacsvox-agent-shell-foreground-speech-level 'response)
        (emacsvox-agent-shell-signal-processing t)
        (emacsvox-agent-shell-speak-tool-calls t))
    (with-temp-buffer
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (let ((emacsvox-agent-shell-foreground-speech-level 'response))
            (emacsvox-agent-shell--speak-content
             "Useful response" 'agent-message)
            (emacsvox-agent-shell--speak-content "Reasoning" 'thought)
            (emacsvox-agent-shell--handle-tool-call-update
             (emacsvox-agent-shell-test--tool-call-event
              "reader" "in_progress" "Read README"))
            (emacsvox-agent-shell--handle-lifecycle-event
             '((:event . input-submitted)))
            (emacsvox-agent-shell--handle-lifecycle-event
             '((:event . turn-complete)
               (:data (:stop-reason . "end_turn"))))))
        '((speak "Useful response")
          (icon task-done)))))))

(ert-deftest emacsvox-agent-shell-background-notifies-without-content ()
  "Background sessions should drop pending content and identify completion."
  (let ((buffer (generate-new-buffer "Codex Agent @ background-test"))
        (emacsvox-agent-shell-background-speech-level 'notify)
        (emacsvox-agent-shell-signal-processing t)
        (emacsvox-agent-shell-speak-tool-calls t))
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local emacsvox-comint-autospeak t)
          (setq-local agent-shell-section-functions
                      '(emacsvox-agent-shell--record-response-section))
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . input-submitted)))
          (emacsvox-agent-shell-test--render-response-section
           :namespace-id "1" :block-id "1-agent_message_chunk"
           :body "Do not speak this response")
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (let ((emacsvox-agent-shell-background-speech-level 'notify))
                (cl-letf
                    (((symbol-function
                       'emacsvox-agent-shell--session-focused-p)
                      (lambda (&optional _buffer) nil)))
                  (emacsvox-agent-shell--handle-tool-call-update
                   (emacsvox-agent-shell-test--tool-call-event
                    "reader" "completed" "Read README"))
                  (emacsvox-agent-shell--handle-lifecycle-event
                   '((:event . turn-complete)
                     (:data (:stop-reason . "end_turn")))))))
            '((notify-icon task-done)
              (notify "Codex Agent @ background-test finished."))))
          (should-not emacsvox-agent-shell--pending-section-markers)
          (should-not emacsvox-agent-shell--pending-bodies)
          (should (= 0 (hash-table-count
                        emacsvox-agent-shell--tool-call-status-cache))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-quiet-retains-urgent-background-events ()
  "Quiet sessions should still identify errors and blocking permissions."
  (let ((buffer (generate-new-buffer "Codex Agent @ quiet-test"))
        (emacsvox-agent-shell-background-speech-level 'quiet)
        (emacsvox-agent-shell-signal-processing t)
        (emacsvox-agent-shell-speak-permissions t))
    (unwind-protect
        (with-current-buffer buffer
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (let ((emacsvox-agent-shell-background-speech-level 'quiet))
                (cl-letf
                    (((symbol-function
                       'emacsvox-agent-shell--session-focused-p)
                      (lambda (&optional _buffer) nil)))
                  (emacsvox-agent-shell--handle-lifecycle-event
                   '((:event . error)
                     (:data (:message . "Connection lost"))))
                  (emacsvox-agent-shell--handle-permission-request
                   '((:event . permission-request)
                     (:data (:tool-call-id . "tool-id")
                            (:tool-call
                             (:title . "Run command")
                             (:permission-actions
                              ((:option . "Allow"))))))))))
            '((notify-icon warn-user)
              (notify "Codex Agent @ quiet-test. Agent error: Connection lost")
              (notify-icon warn-user)
              (notify "Codex Agent @ quiet-test. Permission request. Run command. Choice 1: Allow.")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-exceptional-lifecycle-is-spoken ()
  "Exceptional turn completions and ACP errors should be unambiguous."
  (let ((emacsvox-agent-shell-signal-processing t))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (dolist (event '(((:event . turn-complete)
                          (:data (:stop-reason . "cancelled")))
                         ((:event . turn-complete)
                          (:data (:stop-reason . "max_tokens")))
                         ((:event . turn-complete)
                          (:data (:stop-reason . "max_turn_requests")))
                         ((:event . turn-complete)
                          (:data (:stop-reason . "refusal")))
                         ((:event . turn-complete)
                          (:data (:stop-reason . "agent_shutdown")))
                         ((:event . turn-complete))
                         ((:event . error)
                          (:data (:code . 500)
                                 (:message . "Connection lost.")))))
          (emacsvox-agent-shell--handle-lifecycle-event event)))
      '((icon close-object)
        (speak "Agent turn cancelled.")
        (icon warn-user)
        (speak "Agent stopped: maximum token limit reached.")
        (icon warn-user)
        (speak "Agent stopped: request limit reached.")
        (icon warn-user)
        (speak "Agent refused the request.")
        (icon warn-user)
        (speak "Agent stopped: agent shutdown.")
        (icon warn-user)
        (speak "Agent stopped for an unknown reason.")
        (icon warn-user)
        (speak "Agent error: Connection lost."))))))

(ert-deftest emacsvox-agent-shell-lifecycle-subscription-is-idempotent ()
  "Lifecycle events should subscribe once, dispatch, and clean up."
  (let ((buffer (generate-new-buffer " *agent-shell-lifecycle-test*"))
        (emacsvox-agent-shell-signal-processing t))
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local agent-shell--state
                      (list (cons :buffer buffer)
                            (cons :event-subscriptions nil)))
          (emacsvox-agent-shell--lifecycle-event-setup)
          (let ((token emacsvox-agent-shell--lifecycle-subscription))
            (emacsvox-agent-shell--lifecycle-event-setup)
            (should (equal token
                           emacsvox-agent-shell--lifecycle-subscription))
            (should (= 1 (length (map-elt
                                  agent-shell--state
                                  :event-subscriptions)))))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (cl-letf (((symbol-function 'agent-shell--sync-system-sleep)
                         #'ignore))
                (agent-shell--emit-event :event 'input-submitted)
                (agent-shell--emit-event
                 :event 'turn-complete
                 :data '((:stop-reason . "end_turn")))))
            '((icon progress)
              (icon task-done))))
          (emacsvox-agent-shell--lifecycle-event-cleanup)
          (should-not emacsvox-agent-shell--lifecycle-subscription)
          (should-not (map-elt agent-shell--state :event-subscriptions)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-session-restore-reseeds-completed-answer ()
  "Selecting and restoring a session should replace the prior answer cache."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local emacsvox-agent-shell--last-completed-answer "Old session"
                emacsvox-agent-shell--latest-turn-outcome 'completed)
    (let ((restored-answer "Restored session answer"))
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--rendered-latest-agent-answer)
            (lambda () restored-answer)))
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . session-selected)))
        (should-not emacsvox-agent-shell--last-completed-answer)
        (should-not emacsvox-agent-shell--latest-turn-outcome)
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . session-restored)))
        (should
         (equal emacsvox-agent-shell--last-completed-answer
                "Restored session answer"))
        (should (eq emacsvox-agent-shell--latest-turn-outcome 'completed))
        (setq restored-answer nil)
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . session-selected)))
        (emacsvox-agent-shell--handle-lifecycle-event
         '((:event . session-restored)))
        (should-not emacsvox-agent-shell--last-completed-answer)
        (should-not emacsvox-agent-shell--latest-turn-outcome)))))

(ert-deftest emacsvox-agent-shell-error-discards-partial-response ()
  "Public error feedback should not leave partial response speech pending."
  (let ((emacsvox-agent-shell-signal-processing t))
    (with-temp-buffer
      (setq-local emacsvox-agent-shell--response-turn-active-p t)
      (setq-local emacsvox-agent-shell--pending-bodies
                  (make-hash-table :test #'equal))
      (puthash "1-agent_message_chunk" "Partial response"
               emacsvox-agent-shell--pending-bodies)
      (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                  '("1-agent_message_chunk"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . error)
             (:data (:message . "Connection lost")))))
        '((icon warn-user)
          (speak "Agent error: Connection lost"))))
      (should-not emacsvox-agent-shell--response-turn-active-p)
      (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
      (should (= 0 (hash-table-count
                    emacsvox-agent-shell--pending-bodies))))))

(ert-deftest emacsvox-agent-shell-cancellation-discards-partial-response ()
  "A cancelled turn should announce its outcome without speaking its partial."
  (let ((emacsvox-agent-shell-signal-processing t))
    (with-temp-buffer
      (setq-local emacsvox-comint-autospeak t)
      (setq-local emacsvox-agent-shell--last-completed-answer
                  "Previous completed answer")
      (setq-local emacsvox-agent-shell--response-turn-active-p t)
      (setq-local emacsvox-agent-shell--pending-bodies
                  (make-hash-table :test #'equal))
      (puthash "1-agent_message_chunk" "Do not speak this partial"
               emacsvox-agent-shell--pending-bodies)
      (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                  '("1-agent_message_chunk"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-lifecycle-event
           '((:event . turn-complete)
             (:data (:stop-reason . "cancelled")))))
        '((icon close-object)
          (speak "Agent turn cancelled."))))
      (should-not emacsvox-agent-shell--response-turn-active-p)
      (should (eq emacsvox-agent-shell--latest-turn-outcome 'failed))
      (should
       (equal emacsvox-agent-shell--last-completed-answer
              "Previous completed answer"))
      (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
      (should (= 0 (hash-table-count
                    emacsvox-agent-shell--pending-bodies))))))

(ert-deftest emacsvox-agent-shell-lifecycle-feedback-can-be-disabled ()
  "The lifecycle option should suppress all lifecycle feedback."
  (let ((emacsvox-agent-shell-signal-processing nil))
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (emacsvox-agent-shell--handle-lifecycle-event
        '((:event . input-submitted)))
       (emacsvox-agent-shell--handle-lifecycle-event
        '((:event . error)
          (:data (:message . "Connection lost"))))))))

(ert-deftest emacsvox-agent-shell-tool-fixture-announces-transitions ()
  "Fixture tool transitions should be concise, ordered, and deduplicated."
  (let ((events
         (emacsvox-agent-shell-test--tool-call-events
          "gemini-wrong-output-grouping.traffic"))
        (emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'summary))
    (should (= 6 (length events)))
    (with-temp-buffer
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (dolist (event events)
            (emacsvox-agent-shell--handle-tool-call-update event)))
        '((icon progress)
          (speak "Tool started: search.")
          (icon task-done)
          (speak "Tool completed: search.")
          (icon progress)
          (speak "Tool started: README.org.")
          (icon task-done)
          (speak "Tool completed: README.org.")
          (icon progress)
          (speak "Tool started: acp.el.")
          (icon task-done)
          (speak "Tool completed: acp.el.")))))))

(ert-deftest emacsvox-agent-shell-tool-status-policy-uses-semantic-cues ()
  "Tool lifecycle states resolve their default cues through aural policy."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (dolist
        (entry '((pending . item)
                 (in-progress . progress)
                 (completed . task-done)
                 (failed . warn-user)))
      (let* ((status (car entry))
             (plan
              (emacsvox-aural-resolve-active
               (emacsvox-agent-shell--presentation-facts
                'agent-tool 'agent-tool-status-changed nil
                (list :agent-tool-status status))
               '(:module agent-shell :mode agent-shell-mode
                 :occasion notification)))
             (cue
              (seq-find
               (lambda (action)
                 (eq (emacsvox-aural-action-kind action) 'cue))
               (emacsvox-aural-render-plan-before plan))))
        (should cue)
        (should
         (eq (emacsvox-aural-action-cue cue) (cdr entry)))))))

(ert-deftest emacsvox-agent-shell-tool-status-verbosity-is-icon-only ()
  "Status verbosity should cue each real status without speaking titles."
  (let ((emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'status))
    (with-temp-buffer
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (dolist (entry '(("pending" "one")
                           ("in_progress" "two")
                           ("completed" "three")
                           ("failed" "four")))
            (emacsvox-agent-shell--handle-tool-call-update
             (emacsvox-agent-shell-test--tool-call-event
              (cadr entry) (car entry) (cadr entry))))
          (emacsvox-agent-shell--handle-tool-call-update
           (emacsvox-agent-shell-test--tool-call-event
            "future" "waiting_for_agent" "Future status")))
        '((icon item)
          (icon progress)
          (icon task-done)
          (icon warn-user)))))))

(ert-deftest emacsvox-agent-shell-tool-full-verbosity-speaks-output ()
  "Full verbosity should speak terminal text after its status summary."
  (let ((emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'full))
    (with-temp-buffer
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (dolist
              (event
               (list
                (emacsvox-agent-shell-test--tool-call-event
                 "calculator" "in_progress" "Calculate total")
                (emacsvox-agent-shell-test--tool-call-event
                 "calculator" "completed" "Calculate total"
                 '[((type . "content")
                    (content (type . "text") (text . "Total: 42")))])
                (emacsvox-agent-shell-test--tool-call-event
                 "compiler" "failed" "Compile project"
                 '[((type . "content")
                    (content (type . "text")
                             (text . "Undefined function")))])
                (emacsvox-agent-shell-test--tool-call-event
                 "shell" "completed" "Run command"
                 nil nil "stdout\nstderr\n")))
            (emacsvox-agent-shell--handle-tool-call-update event)))
        '((icon progress)
          (speak "Tool started: Calculate total.")
          (icon task-done)
          (speak "Tool completed: Calculate total. Output: Total: 42")
          (icon warn-user)
          (speak
           "Tool failed: Compile project. Output: Undefined function")
          (icon task-done)
          (speak
           "Tool completed: Run command. Output: stdout\nstderr")))))))

(ert-deftest emacsvox-agent-shell-tool-updates-speak-once-per-status ()
  "Repeated streaming updates should not repeat an unchanged tool status."
  (let ((event
         (emacsvox-agent-shell-test--tool-call-event
          "reader" "in_progress" "Read README"))
        (emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'summary))
    (with-temp-buffer
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--handle-tool-call-update event)
          (emacsvox-agent-shell--handle-tool-call-update event))
        '((icon progress)
          (speak "Tool started: Read README."))))
      (should (= 1 (hash-table-count
                    emacsvox-agent-shell--tool-call-status-cache))))))

(ert-deftest emacsvox-agent-shell-tool-subscription-cleans-state ()
  "Tool subscriptions and status state should install and clean up once."
  (let ((buffer (generate-new-buffer " *agent-shell-tool-test*"))
        (emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'summary))
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local agent-shell--state
                      (list (cons :buffer buffer)
                            (cons :event-subscriptions nil)))
          (emacsvox-agent-shell--tool-call-event-setup)
          (let ((token emacsvox-agent-shell--tool-call-subscription))
            (emacsvox-agent-shell--tool-call-event-setup)
            (should (equal token
                           emacsvox-agent-shell--tool-call-subscription))
            (should (= 1 (length (map-elt
                                  agent-shell--state
                                  :event-subscriptions)))))
          (should
           (equal
            (emacsvox-agent-shell-test--capture-events
              (cl-letf (((symbol-function 'agent-shell--sync-system-sleep)
                         #'ignore))
                (agent-shell--emit-event
                 :event 'tool-call-update
                 :data
                 (map-elt
                  (emacsvox-agent-shell-test--tool-call-event
                   "reader" "completed" "Read README")
                  :data))))
            '((icon task-done)
              (speak "Tool completed: Read README."))))
          (should (= 1 (hash-table-count
                        emacsvox-agent-shell--tool-call-status-cache)))
          (let ((emacsvox-agent-shell-signal-processing nil))
            (emacsvox-agent-shell--handle-lifecycle-event
             '((:event . turn-complete)
               (:data (:stop-reason . "end_turn")))))
          (should (= 0 (hash-table-count
                        emacsvox-agent-shell--tool-call-status-cache)))
          (emacsvox-agent-shell--tool-call-event-cleanup)
          (should-not emacsvox-agent-shell--tool-call-subscription)
          (should-not emacsvox-agent-shell--tool-call-status-cache)
          (should-not (map-elt agent-shell--state :event-subscriptions)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-tool-feedback-can-be-disabled ()
  "Disabling tool speech should retain status state without feedback."
  (let ((emacsvox-agent-shell-speak-tool-calls nil))
    (with-temp-buffer
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (emacsvox-agent-shell--handle-tool-call-update
          (emacsvox-agent-shell-test--tool-call-event
           "reader" "in_progress" "Read README"))))
      (should (= 1 (hash-table-count
                    emacsvox-agent-shell--tool-call-status-cache))))))

(ert-deftest emacsvox-agent-shell-permission-button-feedback-is-semantic ()
  "Focused permission feedback should include choice position and key."
  (with-temp-buffer
    (emacsvox-agent-shell-test--insert-permission-buttons)
    (goto-char (point-min))
    (should (agent-shell-next-permission-button))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--permission-button-feedback))
      '((icon item)
        (speak "Allow, choice 1 of 3. Press Return or y."))))
    (should (agent-shell-next-permission-button))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--permission-button-feedback))
      '((icon item)
        (speak "Reject, choice 2 of 3. Press Return or n."))))))

(ert-deftest emacsvox-agent-shell-permission-and-item-feedback-is-native ()
  "Permission choices and ordinary item moves use native submissions."
  (with-temp-buffer
    (emacsvox-agent-shell-test--insert-permission-buttons)
    (goto-char (point-min))
    (should (agent-shell-next-permission-button))
    (let ((presentations
           (emacsvox-agent-shell-test--capture-presentations
             (emacsvox-agent-shell--permission-button-feedback))))
      (should (= 1 (length presentations)))
      (should (eq (caar presentations) 'submit))
      (should
       (eq (plist-get (nth 2 (car presentations)) :role)
           'permission-request))
      (should (eq (nth 3 (car presentations)) 'agent-shell))
      (should (eq (nth 4 (car presentations)) 'navigation))))
  (with-temp-buffer
    (insert "first item\nsecond item\n")
    (goto-char (point-min))
    (let ((presentations
           (emacsvox-agent-shell-test--capture-presentations
             (cl-letf (((symbol-function 'ems-interactive-p)
                        (lambda (function)
                          (eq function 'agent-shell-next-item))))
               (emacsvox-agent-shell--next-item-around
                (lambda (&rest _) (forward-line 1)))))))
      (should (= 1 (length presentations)))
      (should (eq (caar presentations) 'submit))
      (should (equal (nth 1 (car presentations)) "second item"))
      (should (eq (nth 3 (car presentations)) 'agent-shell))
      (should (eq (nth 4 (car presentations)) 'navigation)))))

(ert-deftest emacsvox-agent-shell-actionable-items-are-semantic ()
  "Links, images, and source controls should announce labels, not chrome."
  (with-temp-buffer
    (insert "[docs](https://example.com)")
    (agent-shell-markdown-replace-markup)
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--semantic-item-feedback))
      '((icon item)
        (speak "docs, link. Press Return to open in browser."))))
    (should (string-match-p ems--message-filter
                            "Press RET to open in browser"))
    (emacsvox-agent-shell--restore-message-filter))
  (with-temp-buffer
    (insert "![diagram](https://example.com/diagram.png)")
    (agent-shell-markdown-replace-markup :complete t)
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--semantic-item-feedback))
      '((icon item)
        (speak "diagram, image. Press Return to open image in browser."))))
    (emacsvox-agent-shell--restore-message-filter))
  (with-temp-buffer
    (insert "architecture diagram")
    (add-text-properties
     (point-min) (point-max)
     '(display (image :type png) help-echo "Open image"))
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--semantic-item-feedback))
      '((icon item)
        (speak
         "architecture diagram, image. Press Return to open image; plus, minus, or zero to resize."))))
    (should (string-match-p ems--message-filter
                            "Press RET to open image, +/-/0 to resize"))
    (emacsvox-agent-shell--restore-message-filter))
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (goto-char (point-min))
    (search-forward "⧉")
    (backward-char)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--semantic-item-feedback))
      '((icon item)
        (speak
         "elisp source block, 2 lines. Press Return to copy."))))
    (should (string-match-p ems--message-filter "Press RET to copy"))
    (emacsvox-agent-shell--restore-message-filter)))

(ert-deftest emacsvox-agent-shell-actionable-items-speak-in-both-views ()
  "Shell and viewport item movement should share semantic link feedback."
  (dolist
      (case
       '((emacsvox-agent-shell--next-item-around
          agent-shell-next-item agent-shell-mode forward)
         (emacsvox-agent-shell--previous-item-around
          agent-shell-previous-item agent-shell-mode backward)
         (emacsvox-agent-shell--viewport-next-item-around
          agent-shell-viewport-next-item
          agent-shell-viewport-view-mode forward)
         (emacsvox-agent-shell--viewport-previous-item-around
          agent-shell-viewport-previous-item
          agent-shell-viewport-view-mode backward)))
    (with-temp-buffer
      (insert "before\n[docs](https://example.com)\nafter\n")
      (agent-shell-markdown-replace-markup)
      (let ((destination
             (save-excursion
               (goto-char (point-min))
               (search-forward "docs")
               (match-beginning 0))))
        (setq major-mode (nth 2 case))
        (goto-char
         (if (eq (nth 3 case) 'forward) (point-min) (point-max)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (cl-letf (((symbol-function 'ems-interactive-p)
                       (lambda (function) (eq function (nth 1 case)))))
              (funcall (nth 0 case)
                       (lambda (&rest _) (goto-char destination)))))
          '((icon item)
            (speak "docs, link. Press Return to open in browser."))))))))

(ert-deftest emacsvox-agent-shell-permission-button-advice-observes-boundary ()
  "Interactive choice navigation should speak moves but not failed moves."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (emacsvox-agent-shell-test--insert-permission-buttons)
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'agent-shell-next-permission-button))
      '((icon item)
        (speak "Allow, choice 1 of 3. Press Return or y."))))
    (ignore
     (emacsvox-agent-shell-test--capture-events
       (call-interactively #'agent-shell-next-permission-button)
       (call-interactively #'agent-shell-next-permission-button)))
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (call-interactively #'agent-shell-next-permission-button)))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'agent-shell-previous-permission-button))
      '((icon item)
        (speak "Reject, choice 2 of 3. Press Return or n."))))))

(ert-deftest emacsvox-agent-shell-item-navigation-skips-empty-lines ()
  "Item navigation should not submit an empty terminal line."
  (with-temp-buffer
    (insert "last item\n")
    (goto-char (point-min))
    (should-not
     (emacsvox-agent-shell-test--capture-presentations
       (cl-letf (((symbol-function 'ems-interactive-p)
                  (lambda (function)
                    (eq function 'agent-shell-next-item))))
         (emacsvox-agent-shell--next-item-around
          (lambda (&rest _) (goto-char (point-max)))))))))

(ert-deftest emacsvox-agent-shell-session-controls-submit-current-state ()
  "Model and mode controls atomically announce their resulting state."
  (cl-letf (((symbol-function 'ems-interactive-p)
             (lambda (&rest _) t))
            ((symbol-function 'emacsvox-agent-shell--header-state)
             (lambda (&optional _) '(:model "o4" :mode "Plan"))))
    (dolist
        (case
         '((emacsvox-agent-shell--set-session-model-after "Model o4.")
           (emacsvox-agent-shell--set-session-mode-after
            "Session mode Plan.")
           (emacsvox-agent-shell--cycle-session-mode-after
            "Session mode Plan.")))
      (let ((presentations
             (emacsvox-agent-shell-test--capture-presentations
               (funcall (car case)))))
        (should (= 1 (length presentations)))
        (should (eq (caar presentations) 'submit))
        (should (equal (nth 1 (car presentations)) (cadr case)))
        (should
         (eq (plist-get (nth 2 (car presentations)) :role)
             'agent-session))
        (should (eq (nth 3 (car presentations)) 'agent-shell))
        (should (eq (nth 4 (car presentations)) 'state-change))))))

(ert-deftest emacsvox-agent-shell-block-locations-are-semantic ()
  "Transcript locations should expose semantic types in buffer order."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (should
     (equal
      (mapcar
       (lambda (location) (plist-get location :type))
       (emacsvox-agent-shell--block-locations))
      '(user-prompt agent-response activity-group thought tool-call plan
                    permission error agent-response)))))

(ert-deftest emacsvox-agent-shell-block-jumps-use-native-submissions ()
  "Successful and failed non-table jumps should submit native feedback."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (insert "target")
    (let ((target
          '(:position 1 :end 7 :type thought :label "Thinking"
             :body "Inspect constraints"))
          captured
          direct-output)
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--block-location-in-direction)
            (lambda (&rest _) target))
           ((symbol-function 'emacsvox-agent-shell--expand-block-parent)
            #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) captured)))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _) (push 'icon direct-output)))
           ((symbol-function 'tts-speak)
            (lambda (&rest _) (push 'speech direct-output))))
        (emacsvox-agent-shell--jump-block-of-type 'thought 'forward)
        (setq target nil)
        (emacsvox-agent-shell--jump-block-of-type 'thought 'backward))
      (should-not direct-output)
      (setq captured (nreverse captured))
      (should
       (equal
        (mapcar #'car captured)
        '("Thinking. Inspect constraints"
          "No earlier thought or reasoning block.")))
      (dolist (entry captured)
        (let ((arguments (cdr entry)))
          (should (eq (plist-get arguments :module) 'agent-shell))
          (should (eq (plist-get arguments :occasion) 'navigation))
          (should
           (= (length
               (plist-get arguments :compatibility-actions))
              1)))))))

(ert-deftest emacsvox-agent-shell-block-jumps-bound-body-previews ()
  "Semantic navigation should bound large bodies at the configured limit."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (insert "target")
    (let ((emacsvox-agent-shell-block-navigation-max-characters 32)
          (target
           (list :position 1 :end 7 :type 'agent-response
                 :body (make-string 50000 ?x)))
          spoken)
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--block-location-in-direction)
            (lambda (&rest _) target))
           ((symbol-function 'emacsvox-agent-shell--expand-block-parent)
            #'ignore)
           ((symbol-function 'emacsvox-agent-shell--submit-text-feedback)
            (lambda (content &rest _) (setq spoken content)))
           ((symbol-function 'tts-stop) #'ignore))
        (emacsvox-agent-shell--jump-block-of-type
         'agent-response 'forward))
      (should
       (equal spoken
              (concat
               (make-string 32 ?x)
               " [block truncated; 49968 characters omitted]"))))))

(ert-deftest emacsvox-agent-shell-block-body-limit-uses-word-boundary ()
  "Bounded block navigation should avoid cutting an ordinary word."
  (let ((emacsvox-agent-shell-block-navigation-max-characters 18))
    (should
     (equal
      (emacsvox-agent-shell--block-navigation-body-text
       "alpha beta gamma delta")
      "alpha beta gamma [block truncated; 6 characters omitted]"))))

(ert-deftest emacsvox-agent-shell-block-body-limit-can-be-disabled ()
  "A nil navigation limit should retain the complete normalized body."
  (let ((emacsvox-agent-shell-block-navigation-max-characters nil))
    (should
     (equal
      (emacsvox-agent-shell--block-navigation-body-text
       " first line\nsecond line ")
      "first line second line"))))

(ert-deftest emacsvox-agent-shell-expansion-speech-excludes-body ()
  "Expansion feedback should report state without copying body content."
  (should
   (equal
    (emacsvox-agent-shell--expanded-block-speech
     (list :type 'thought :label "Thinking"
           :body (make-string 50000 ?x)))
    "Thinking, expanded.")))

(ert-deftest emacsvox-agent-shell-foldable-locations-expose-visibility ()
  "Foldable transcript locations should expose canonical visibility facts."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let* ((locations (emacsvox-agent-shell--block-locations))
           (activity
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'activity-group))
             locations))
           (plan
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'plan))
             locations))
           (activity-facts
            (emacsvox-agent-shell--block-location-facts
             activity 'focus-entered))
           (plan-facts
            (emacsvox-agent-shell--block-location-facts
             plan 'focus-entered)))
      (should (eq (plist-get activity :visibility) 'folded))
      (should (eq (plist-get plan :visibility) 'expanded))
      (should (eq (plist-get activity-facts :visibility) 'folded))
      (should (eq (plist-get plan-facts :visibility) 'expanded)))))

(ert-deftest emacsvox-agent-shell-feature-fragments-are-optional-built-ins ()
  "Agent Shell feature fragments are read-only and remain opt-in."
  (dolist
      (fragment
       '(agent-shell-block-type-labels
         agent-shell-block-type-cues
         agent-shell-block-visibility-cues
         agent-shell-block-visibility-labels))
    (let ((entry (emacsvox-aural-feature-fragment-entry fragment)))
      (should entry)
      (should (emacsvox-aural-feature-fragment-entry-built-in entry))
      (should
       (eq
        (emacsvox-aural-feature-fragment-entry-collection entry)
        'agent-shell))
      (should
       (equal
        (emacsvox-aural-feature-fragment-entry-source entry)
        "emacsvox-aural-provider-workflows"))
      (should-not
       (emacsvox-aural-feature-fragment-enabled-p fragment)))))

(ert-deftest emacsvox-agent-shell-feature-fragments-compose-on-navigation ()
  "Agent Shell labels, cues, and trailing visibility compose in order."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(agent-shell-block-type-labels
           agent-shell-block-type-cues
           agent-shell-block-visibility-cues
           agent-shell-block-visibility-labels))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (facts
         '(:role agent-thought :events (focus-entered)
           :agent-block-kind thought :visibility folded))
        (context
         '(:module agent-shell :mode agent-shell-mode
           :occasion navigation)))
    (let* ((plan (emacsvox-aural-resolve-active facts context))
           (concrete (emacsvox-aural-compile-plan plan facts context)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-id
         (emacsvox-aural-concrete-plan-before concrete))
        '(agent-shell-block-type-label-action
          agent-shell-thought-cue-action
          agent-shell-navigated-folded-cue-action)))
      (should
       (equal
        (emacsvox-aural-concrete-action-text
         (car (emacsvox-aural-concrete-plan-before concrete)))
        "thought"))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-cue
         (cdr (emacsvox-aural-concrete-plan-before concrete)))
        '(progress close-object)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-text
         (emacsvox-aural-concrete-plan-after concrete))
        '("collapsed"))))))

(ert-deftest emacsvox-agent-shell-visibility-labels-follow-navigation-content ()
  "The optional visibility words should follow only navigated block content."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(agent-shell-block-visibility-labels))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (context
         '(:module agent-shell :mode agent-shell-mode
           :occasion navigation)))
    (dolist (case '((folded "collapsed") (expanded "expanded")))
      (let* ((visibility (car case))
             (expected (cadr case))
             (facts
              (list :role 'agent-block :events '(focus-entered)
                    :agent-block-kind 'thought :visibility visibility))
             (plan (emacsvox-aural-resolve-active facts context))
             (concrete
              (emacsvox-aural-compile-plan plan facts context)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-text
           (emacsvox-aural-concrete-plan-after concrete))
          (list expected)))))
    (let* ((state-context
            '(:module agent-shell :mode agent-shell-mode
              :occasion state-change))
           (state-facts
            '(:role agent-block :events (visibility-changed)
              :agent-block-kind thought :visibility folded))
           (plan
            (emacsvox-aural-resolve-active state-facts state-context))
           (concrete
            (emacsvox-aural-compile-plan
             plan state-facts state-context)))
      (should-not (emacsvox-aural-concrete-plan-after concrete)))))

(ert-deftest emacsvox-agent-shell-visibility-fragment-replaces-toggle-cue ()
  "The visibility fragment should replace, not duplicate, the fallback cue."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(agent-shell-block-visibility-cues))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (facts
         '(:role agent-block :events (visibility-changed)
           :agent-block-kind activity-group :visibility expanded))
        (context
         '(:module agent-shell :mode agent-shell-mode
           :occasion state-change)))
    (let ((plan
           (emacsvox-aural-resolve-legacy-icon
            'open-object context facts)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-id
         (emacsvox-aural-render-plan-before plan))
        '(agent-shell-toggled-expanded-cue-action)))
      (should
       (eq
        (emacsvox-aural-action-cue
         (car (emacsvox-aural-render-plan-before plan)))
        'open-object)))))

(ert-deftest emacsvox-agent-shell-fold-toggle-emits-state-change-facts ()
  "An interactive fragment toggle should announce its new visibility."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let* ((activity
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'activity-group))
             (emacsvox-agent-shell--block-locations))))
      (goto-char (plist-get activity :position))
      (let* ((presentations
              (emacsvox-agent-shell-test--capture-presentations
                (call-interactively
                 #'agent-shell-ui-toggle-fragment))))
        (should (= (length presentations) 1))
        (dolist (presentation presentations)
          (let ((facts (nth 2 presentation)))
            (should (eq (plist-get facts :role) 'agent-block))
            (should
             (equal (plist-get facts :events) '(visibility-changed)))
            (should
             (eq (plist-get facts :agent-block-kind) 'activity-group))
            (should (eq (plist-get facts :visibility) 'expanded))
            (should (eq (nth 3 presentation) 'agent-shell))
            (should (eq (nth 4 presentation) 'state-change))))
        (should
         (eq (caar presentations) 'submit))
        (should
         (equal
          (cadar presentations)
          "Activity group, Thought, read a file, expanded."))
        (should
         (eq
          (plist-get
           (emacsvox-agent-shell--fragment-location-at-position
            (point))
           :visibility)
          'expanded))))))

(ert-deftest emacsvox-agent-shell-fold-action-ret-announces-state-concisely ()
  "Inline RET should announce visibility without reading complete bodies."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let* ((activity
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'activity-group))
             (emacsvox-agent-shell--block-locations))))
      (goto-char (plist-get activity :position))
      (let ((action (key-binding (kbd "RET"))))
        (should (functionp action))
        (should (eq action 'agent-shell-ui-toggle-fragment))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively action)
            (call-interactively (key-binding (kbd "RET"))))
          '((icon open-object)
            (speak
             "Activity group, Thought, read a file, expanded.")
            (icon close-object)))))
      (should
       (eq
        (plist-get
         (emacsvox-agent-shell--fragment-location-at-position (point))
         :visibility)
        'folded)))))

(ert-deftest emacsvox-agent-shell-thought-toggle-announces-state-concisely ()
  "A Thought toggle should announce expansion and stay silent on collapse."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let ((activity
           (seq-find
            (lambda (location)
              (eq (plist-get location :type) 'activity-group))
            (emacsvox-agent-shell--block-locations))))
      (goto-char (plist-get activity :position))
      (agent-shell-ui--toggle-fragment-at-point))
    (let ((thought
           (seq-find
            (lambda (location)
              (eq (plist-get location :type) 'thought))
            (emacsvox-agent-shell--block-locations))))
      (should (eq (plist-get thought :visibility) 'folded))
      (goto-char (plist-get thought :position))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'agent-shell-ui-toggle-fragment)
          (call-interactively #'agent-shell-ui-toggle-fragment))
        '((icon open-object)
          (speak "Thinking, expanded.")
          (icon close-object)))))))

(ert-deftest emacsvox-agent-shell-decorated-thought-toggle-is-semantic ()
  "A rendered thought icon should not enter expansion speech."
  (with-temp-buffer
    (agent-shell-ui-update-fragment
     (agent-shell-ui-make-fragment-model
      :namespace-id "1" :block-id "1-agent_thought_chunk"
      :label-left
      (concat
       "✶ "
       (propertize
        "Thinking" 'font-lock-face 'agent-shell-section-heading))
      :body "Reasoning")
     :expanded nil)
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (search-forward "Thinking")
    (goto-char (match-beginning 0))
    (let ((location
           (emacsvox-agent-shell--fragment-location-at-position (point))))
      (should (equal (plist-get location :label) "Thinking"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'agent-shell-ui-toggle-fragment))
        '((icon open-object)
          (speak "Thinking, expanded.")))))))

(ert-deftest emacsvox-agent-shell-internal-fold-toggle-remains-silent ()
  "Programmatic use of the internal fold primitive should remain silent."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (let* ((activity
            (seq-find
             (lambda (location)
               (eq (plist-get location :type) 'activity-group))
             (emacsvox-agent-shell--block-locations))))
      (goto-char (plist-get activity :position))
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (agent-shell-ui--toggle-fragment-at-point)))
      (should
       (eq
        (plist-get
         (emacsvox-agent-shell--fragment-location-at-position (point))
         :visibility)
        'expanded)))))

(ert-deftest emacsvox-agent-shell-toggle-all-emits-one-aggregate-change ()
  "Toggling all fragments should announce one aggregate visibility result."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let* ((ems--interactive-fn-name
            'agent-shell-ui-toggle-all-fragments)
           (presentations
           (emacsvox-agent-shell-test--capture-presentations
              (emacsvox-agent-shell--toggle-all-fragments-around
               (lambda ()
                 (setq agent-shell-ui--fold-toggle-state 'collapsed)
                 'toggled)))))
      (should (= (length presentations) 1))
      (dolist (presentation presentations)
        (let ((facts (nth 2 presentation)))
          (should (eq (plist-get facts :role) 'agent-session))
          (should (equal (plist-get facts :events) '(visibility-changed)))
          (should (eq (plist-get facts :visibility) 'folded))
          (should (eq (nth 4 presentation) 'state-change))))
      (should
       (equal
        (mapcar (lambda (presentation) (car presentation))
                presentations)
        '(submit)))
      (should
       (equal (cadar presentations)
              "All Agent Shell blocks collapsed")))))

(ert-deftest emacsvox-agent-shell-block-navigation-expands-activity-members ()
  "Selecting a hidden thought or tool should expand its activity group."
  (dolist (case '((thought "Thinking, collapsed.")
                  (tool-call
                   "completed Read file, collapsed.")))
    (emacsvox-agent-shell-test--with-semantic-blocks
      (let* ((type (car case))
             (location
              (seq-find
               (lambda (candidate)
                 (eq (plist-get candidate :type) type))
               (emacsvox-agent-shell--block-locations))))
        (should (invisible-p (plist-get location :position)))
        (goto-char (point-min))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell--jump-block-of-type type 'forward))
          `((stop nil)
            (icon large-movement)
            (speak ,(cadr case)))))
        (should (= (point) (plist-get location :position)))
        (should-not (invisible-p (point)))))))

(ert-deftest emacsvox-agent-shell-block-navigation-reads-activity-group ()
  "Manual navigation should identify a descriptive activity-group header."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--jump-block-of-type
         'user-prompt 'forward))
      '((stop nil)
        (icon large-movement)
        (speak "Codex> first request continued request"))))
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--jump-block-of-type
         'activity-group 'forward))
      '((stop nil)
        (icon large-movement)
        (speak
         "Activity group, Thought, read a file, collapsed."))))))

(ert-deftest emacsvox-agent-shell-legacy-tool-group-remains-navigable ()
  "Old tool-call group IDs and the former type name should remain usable."
  (with-temp-buffer
    (insert "before\n")
    (agent-shell-ui-update-fragment
     (agent-shell-ui-make-fragment-model
      :namespace-id "1" :block-id "tool-123"
      :label-left "completed" :label-right "Read file"
      :group-id "tool-calls-1" :group-label "Tool calls"
      :group-expanded nil)
     :expanded nil)
    (setq major-mode 'agent-shell-mode)
    (let ((group
           (seq-find
            (lambda (location)
              (eq (plist-get location :type) 'activity-group))
            (emacsvox-agent-shell--block-locations))))
      (should group)
      (should
       (equal (map-elt (plist-get group :state) :qualified-id)
              "1-tool-calls-1"))
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type
           'tool-group 'forward))
        '((stop nil)
          (icon large-movement)
          (speak "Activity group, Tool calls, collapsed.")))))))

(ert-deftest emacsvox-agent-shell-block-navigation-does-not-wrap ()
  "Typed navigation should read bodies and stop at transcript boundaries."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--jump-block-of-type
         'agent-response 'forward)
        (emacsvox-agent-shell--jump-block-of-type
         'agent-response 'forward))
      '((stop nil)
        (icon large-movement)
        (speak "First answer with a second line")
        (stop nil)
        (icon large-movement)
        (speak "Second answer"))))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--jump-block-of-type
         'agent-response 'forward))
      '((icon warn-user)
        (speak "No later agent response block."))))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--jump-block-of-type
         'agent-response 'backward))
      '((stop nil)
        (icon large-movement)
        (speak "First answer with a second line"))))))

(ert-deftest emacsvox-agent-shell-block-navigation-is-directional ()
  "Navigation should not rebuild all semantic locations for each move."
  (emacsvox-agent-shell-test--with-semantic-blocks
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (cl-letf
            (((symbol-function 'emacsvox-agent-shell--block-locations)
              (lambda ()
                (ert-fail "Navigation enumerated the whole transcript")))
             ((symbol-function 'emacsvox-agent-shell--fragment-locations)
              (lambda ()
                (ert-fail "Navigation enumerated every fragment"))))
          (emacsvox-agent-shell--jump-block-of-type
           'agent-response 'forward)
          (emacsvox-agent-shell--jump-block-of-type
           'agent-response 'forward)))
      '((stop nil)
        (icon large-movement)
        (speak "First answer with a second line")
        (stop nil)
        (icon large-movement)
        (speak "Second answer"))))
    (goto-char (point-min))
    (search-forward "second line")
    (backward-char 3)
    (cl-letf
        (((symbol-function 'emacsvox-agent-shell--block-locations)
          (lambda ()
            (ert-fail "Context lookup enumerated the whole transcript"))))
      (should
       (eq
        (plist-get (emacsvox-agent-shell--block-location-at-point) :type)
        'agent-response)))))

(ert-deftest emacsvox-agent-shell-local-block-lookup-skips-prompt-scan ()
  "Fragment metadata should prevent a transcript-wide legacy prompt scan."
  (with-temp-buffer
    (insert
     (propertize
      "Current response"
      'agent-shell-ui-state
      '((:qualified-id . "1-agent_message_chunk"))
      'agent-shell-ui-section 'body))
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (cl-letf
        (((symbol-function
           'emacsvox-agent-shell--prompt-location-at-position)
          (lambda (&rest _)
            (ert-fail "Local lookup searched legacy prompt properties"))))
      (should
       (eq
        (plist-get
         (emacsvox-agent-shell--block-location-at-point)
         :type)
        'agent-response)))))

(ert-deftest emacsvox-agent-shell-live-prompt-lookup-uses-local-fields ()
  "Live Comint prompts and multiline input should not scan the transcript."
  (with-temp-buffer
    (insert
     (propertize
      (concat (make-string 100000 ?x) "\n")
      'field 'output
      'rear-nonsticky '(field)))
    (let ((prompt-start (point)))
      (insert
       (propertize
        "Codex> "
        'font-lock-face
        '(comint-highlight-prompt comint-highlight-prompt)
        'face '(comint-highlight-prompt comint-highlight-prompt)
        'field 'output
        'rear-nonsticky '(field font-lock-face face)))
      (let ((input-start (point)))
        (insert
         (propertize
          "first line\n\nsecond line"
          'font-lock-face 'comint-highlight-input
          'face 'comint-highlight-input))
        (let ((marker-start (point))
              positions)
          (insert
           (propertize
            "<shell-maker-end-of-prompt>"
            'shell-maker--marker t
            'field 'output
            'invisible t))
          (setq major-mode 'agent-shell-mode)
          (setq positions
                (list
                 prompt-start
                 input-start
                 (save-excursion
                   (goto-char input-start)
                   (forward-line 2)
                   (point))
                 (1- marker-start)))
          (should-not (get-text-property input-start 'field))
          (cl-letf
              (((symbol-function
                 'emacsvox-agent-shell--prompt-location-at-position)
                (lambda (&rest _)
                  (ert-fail "Local prompt lookup scanned the transcript"))))
            (dolist (position positions)
              (let ((location
                     (emacsvox-agent-shell--block-location-at-point
                      position)))
                (should (eq (plist-get location :type) 'user-prompt))
                (should (= (plist-get location :position) prompt-start))
                (should (= (plist-get location :end) marker-start))))))))))

(ert-deftest emacsvox-agent-shell-output-blank-skips-prompt-scan ()
  "An unclassified Shell Maker output blank should be locally conclusive."
  (with-temp-buffer
    (insert
     (propertize
      (concat (make-string 100000 ?x) "\n\n")
      'field 'output))
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (forward-line 1)
    (should (= (line-beginning-position) (line-end-position)))
    (cl-letf
        (((symbol-function
           'emacsvox-agent-shell--prompt-location-at-position)
          (lambda (&rest _)
            (ert-fail "Output blank searched legacy prompt properties"))))
      (should-not (emacsvox-agent-shell--block-location-at-point))
      (should-not
       (emacsvox-agent-shell--block-location-at-point (point-max))))))

(ert-deftest emacsvox-agent-shell-unclassified-input-keeps-prompt-fallback ()
  "Plain nil-field text should retain legacy prompt containment lookup."
  (with-temp-buffer
    (insert "legacy input")
    (setq major-mode 'agent-shell-mode)
    (let (called)
      (cl-letf
          (((symbol-function
             'emacsvox-agent-shell--prompt-location-at-position)
            (lambda (&rest _)
              (setq called t)
              nil)))
        (should-not (emacsvox-agent-shell--block-location-at-point)))
      (should called))))

(ert-deftest emacsvox-agent-shell-prompt-search-recognizes-comint-face ()
  "Legacy directional lookup should recognize Shell Maker's live face."
  (with-temp-buffer
    (let ((prompt-start (point)))
      (insert
       (propertize
        "Codex> "
        'font-lock-face
        '(comint-highlight-prompt comint-highlight-prompt)))
      (insert "request")
      (let ((marker-start (point)))
        (insert
         (propertize
          "<shell-maker-end-of-prompt>"
          'shell-maker--marker t
          'invisible t))
        (setq major-mode 'agent-shell-mode)
        (let ((location
               (emacsvox-agent-shell--prompt-location-at-position
                prompt-start)))
          (should (eq (plist-get location :type) 'user-prompt))
          (should (= (plist-get location :position) prompt-start))
          (should (= (plist-get location :end) marker-start)))))))

(ert-deftest emacsvox-agent-shell-block-navigation-keeps-adjacent-fragments ()
  "Directional search should not skip adjacent matching property runs."
  (with-temp-buffer
    (let ((first-start (point)))
      (insert "first")
      (add-text-properties
       first-start (point)
       '(agent-shell-ui-state
         ((:qualified-id . "1-agent_message_chunk"))
         agent-shell-ui-section body)))
    (let ((second-start (point)))
      (insert "second")
      (add-text-properties
       second-start (point)
       '(agent-shell-ui-state
         ((:qualified-id . "2-agent_message_chunk"))
         agent-shell-ui-section body))
      (setq major-mode 'agent-shell-mode)
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type
           'agent-response 'forward))
        '((stop nil)
          (icon large-movement)
          (speak "second"))))
      (should (= (point) second-start)))))

(ert-deftest emacsvox-agent-shell-block-navigation-selects-and-repeats ()
  "Interactive navigation should remember completion and enable repeat keys."
  (let ((emacsvox-agent-shell--block-navigation-type 'agent-response)
        activated-map)
    (emacsvox-agent-shell-test--with-semantic-blocks
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _)
                       (should completion-ignore-case)
                       "plan"))
                    ((symbol-function 'set-transient-map)
                     (lambda (map &rest _)
                       (setq activated-map map))))
            (call-interactively
             #'emacsvox-agent-shell-next-block-of-type)))
        '((stop nil)
          (icon large-movement)
          (speak "Plan. One step"))))
      (should (eq emacsvox-agent-shell--block-navigation-type 'plan))
      (should (eq activated-map emacsvox-agent-shell--block-repeat-map))
      (should
       (eq (lookup-key activated-map (kbd "]"))
           #'emacsvox-agent-shell-repeat-next-block))
      (should
       (eq (lookup-key activated-map (kbd "["))
           #'emacsvox-agent-shell-repeat-previous-block)))))

(ert-deftest emacsvox-agent-shell-block-selector-bracket-accepts-default ()
  "The invoking bracket should accept only an empty selector minibuffer."
  (let ((base-map (make-sparse-keymap)))
    (with-temp-buffer
      (use-local-map base-map)
      (emacsvox-agent-shell--block-type-minibuffer-setup "]")
      (should-not (eq (current-local-map) base-map))
      (should
       (eq (lookup-key (current-local-map) (kbd "]"))
           #'emacsvox-agent-shell--accept-block-type-default))
      (should-not (lookup-key base-map (kbd "]")))))
  (let (action)
    (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
               (lambda () ""))
              ((symbol-function 'exit-minibuffer)
               (lambda () (setq action 'accept)))
              ((symbol-function 'self-insert-command)
               (lambda (&optional _count) (setq action 'insert))))
      (emacsvox-agent-shell--accept-block-type-default))
    (should (eq action 'accept)))
  (let ((last-command-event ?\]) action)
    (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
               (lambda () "p"))
              ((symbol-function 'exit-minibuffer)
               (lambda () (setq action 'accept)))
              ((symbol-function 'self-insert-command)
               (lambda (&optional count)
                 (setq action (list 'insert count last-command-event)))))
      (emacsvox-agent-shell--accept-block-type-default))
    (should (equal action `(insert 1 ,?\])))))

(ert-deftest emacsvox-agent-shell-context-navigation-infers-current-type ()
  "Bare brackets should infer and skip the semantic block containing point."
  (let ((emacsvox-agent-shell--block-navigation-type 'plan)
        activated-map)
    (emacsvox-agent-shell-test--with-semantic-blocks
      (setq major-mode 'agent-shell-viewport-view-mode)
      (goto-char (point-min))
      (search-forward "second line")
      (backward-char 3)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'set-transient-map)
                     (lambda (map &rest _)
                       (setq activated-map map))))
            (emacsvox-agent-shell-next-block-at-point)))
        '((stop nil)
          (icon large-movement)
          (speak "Second answer"))))
      (should (eq emacsvox-agent-shell--block-navigation-type
                  'agent-response))
      (should (eq activated-map emacsvox-agent-shell--block-repeat-map))
      (forward-char 3)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'set-transient-map) #'ignore))
            (emacsvox-agent-shell-previous-block-at-point)))
        '((stop nil)
          (icon large-movement)
          (speak "First answer with a second line"))))
      (forward-char 3)
      (let ((origin (point)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell-previous-block-at-point))
          '((icon warn-user)
            (speak "No earlier agent response block."))))
        (should (= (point) origin))))))

(ert-deftest emacsvox-agent-shell-context-navigation-prefers-nested-table ()
  "A rendered table should win over its enclosing response at point."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        (concat "before\n"
                "| A | B |\n|---|---|\n| 1 | 2 |\n"
                "between\n"
                "| C | D |\n|---|---|\n| 3 | 4 |\n"
                "after\n")
      (put-text-property
       (point-min) (point-max) 'agent-shell-ui-state
       '((:qualified-id . "1-agent_message_chunk")))
      (setq major-mode 'agent-shell-viewport-view-mode)
      (goto-char (point-min))
      (search-forward "1")
      (backward-char 1)
      (should
       (eq (plist-get (emacsvox-agent-shell--block-location-at-point) :type)
           'table))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'set-transient-map) #'ignore))
            (emacsvox-agent-shell-next-block-at-point)))
        '((stop nil)
          (icon open-object)
          (speak "Table, 1 data row, 2 columns. C."))))
      (should (eq emacsvox-agent-shell--block-navigation-type 'table)))))

(ert-deftest emacsvox-agent-shell-source-block-locations-are-semantic ()
  "Rendered fenced blocks should expose body, language, and panel bounds."
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (setq major-mode 'agent-shell-mode)
    (let ((locations (emacsvox-agent-shell--source-block-locations)))
      (should (= 2 (length locations)))
      (should (equal (mapcar (lambda (item) (plist-get item :language))
                             locations)
                     '("elisp" "python")))
      (should (equal (mapcar (lambda (item) (plist-get item :line-count))
                             locations)
                     '(2 1)))
      (should
       (equal (mapcar (lambda (item) (plist-get item :body)) locations)
              '("(message \"hello\")\n(+ 1 2)"
                "print(\"hello\")")))
      (dolist (location locations)
        (should (< (plist-get location :start)
                   (plist-get location :position)))
        (should (> (plist-get location :end)
                   (plist-get location :position)))
        (should
         (get-text-property
          (plist-get location :position)
          'agent-shell-markdown-source-block-body)))
      (put-text-property
       (point-min) (point-max) 'agent-shell-ui-state
       '((:qualified-id . "1-agent_message_chunk")))
      (put-text-property
       (point-min) (point-max) 'agent-shell-ui-section 'body)
      (goto-char (point-min))
      (search-forward "elisp")
      (should
       (eq (plist-get (emacsvox-agent-shell--block-location-at-point) :type)
           'source-block)))
    (should
     (equal
      (emacsvox-agent-shell--source-block-summary
       '(:language nil :line-count 1))
      "Source block, 1 line."))))

(ert-deftest emacsvox-agent-shell-source-block-navigation-is-concise ()
  "Source selection and inferred repeat should speak summaries and boundaries."
  (let ((emacsvox-agent-shell--block-navigation-type 'agent-response)
        activated-map)
    (emacsvox-agent-shell-test--with-rendered-source-blocks
      (setq major-mode 'agent-shell-viewport-view-mode)
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "Source block"))
                    ((symbol-function 'set-transient-map)
                     (lambda (map &rest _)
                       (setq activated-map map))))
            (call-interactively
             #'emacsvox-agent-shell-next-block-of-type)))
        '((stop nil)
          (icon open-object)
          (speak "elisp source block, 2 lines."))))
      (should (eq emacsvox-agent-shell--block-navigation-type 'source-block))
      (should (eq activated-map emacsvox-agent-shell--block-repeat-map))
      (goto-char (point-min))
      (search-forward "elisp")
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf (((symbol-function 'set-transient-map) #'ignore))
            (emacsvox-agent-shell-next-block-at-point)))
        '((stop nil)
          (icon open-object)
          (speak "python source block, 1 line."))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type
           'source-block 'forward))
        '((icon warn-user)
          (speak "No later source block."))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type
           'source-block 'backward))
        '((stop nil)
          (icon open-object)
          (speak "elisp source block, 2 lines.")))))))

(ert-deftest emacsvox-agent-shell-source-block-read-and-copy-use-public-body ()
  "Explicit source commands should read voiced code and copy its plain body."
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (search-forward "(message")
    (backward-char (length "(message"))
    (let* ((events
            (emacsvox-agent-shell-test--capture-events
              (call-interactively
               #'emacsvox-agent-shell-speak-source-block)))
           (speech (cadr (nth 2 events))))
      (should
       (equal events
              '((stop nil)
                (icon item)
                (speak
                 "elisp source block, 2 lines. (message \"hello\")\n(+ 1 2)"))))
      (should
       (eq (emacsvox-agent-shell-test--face-at-text
            speech "elisp source block")
           'agent-shell-markdown-source-block-language))
      (should
       (eq (emacsvox-agent-shell-test--face-at-text speech "(message")
           'agent-shell-markdown-source-block)))
    (let ((kill-ring nil)
          (kill-ring-yank-pointer nil))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively
           #'emacsvox-agent-shell-copy-source-block))
        '((message "Copied code block")
          (icon yank-object)
          (speak "Copied source block"))))
      (should (equal (current-kill 0) "(message \"hello\")\n(+ 1 2)")))))

(ert-deftest emacsvox-agent-shell-source-navigation-expands-parent ()
  "A hidden source target should expand its collapsed enclosing group."
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (setq major-mode 'agent-shell-mode)
    (let* ((source (car (emacsvox-agent-shell--source-block-locations)))
           (position (plist-get source :position))
           toggled)
      (put-text-property
       position (plist-get source :end) 'agent-shell-ui-state
       '((:qualified-id . "tool-source") (:group-id . "group-1")))
      (put-text-property position (plist-get source :end) 'invisible 'hidden)
      (add-to-invisibility-spec 'hidden)
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (cl-letf
              (((symbol-function
                 'emacsvox-agent-shell--fragment-location-by-id)
                (lambda (&rest _)
                  (list :position (point-min)
                        :state
                        '((:qualified-id . "group-1")
                          (:collapsed . t)))))
               ((symbol-function 'agent-shell-ui-toggle-fragment)
                (lambda ()
                  (setq toggled t)
                  (remove-text-properties
                   (point-min) (point-max) '(invisible nil)))))
            (emacsvox-agent-shell--jump-block-of-type
             'source-block 'forward)))
        '((stop nil)
          (icon open-object)
          (speak "elisp source block, 2 lines."))))
      (should toggled)
      (should (= (point) position))
      (should-not (invisible-p position)))))

(ert-deftest emacsvox-agent-shell-context-navigation-preserves-input ()
  "Contextual bracket keys should self-insert in both prompt editors."
  (dolist (case `((agent-shell-mode ,agent-shell-mode-map "]")
                  (agent-shell-viewport-edit-mode
                   ,agent-shell-viewport-edit-mode-map "[")))
    (let ((buffer (generate-new-buffer " *agent-shell-bracket-input-test*")))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer buffer)
            (setq major-mode (nth 0 case))
            (use-local-map (nth 1 case))
            (setq emacsvox-agent-shell--speech-control-active t)
            (cl-letf (((symbol-function 'shell-maker-busy) (lambda () nil))
                      ((symbol-function 'shell-maker-point-at-last-prompt-p)
                       (lambda () t)))
              (execute-kbd-macro (kbd (nth 2 case))))
            (should (equal (buffer-string) (nth 2 case))))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-context-navigation-selects-at-plain-text ()
  "Contextual navigation should select a type at unclassified transcript text."
  (let ((emacsvox-agent-shell--block-navigation-type 'plan)
        (minibuffer-setup-hook nil)
        activated-map accept-command default-value)
    (emacsvox-agent-shell-test--with-semantic-blocks
      (setq major-mode 'agent-shell-viewport-view-mode)
      (goto-char (point-min))
      (should-not (emacsvox-agent-shell--block-location-at-point))
      (let ((last-command-event ?\]))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (cl-letf
                (((symbol-function 'completing-read)
                  (lambda (&rest arguments)
                    (should completion-ignore-case)
                    (setq default-value (nth 6 arguments))
                    (with-temp-buffer
                      (use-local-map (make-sparse-keymap))
                      (funcall (car minibuffer-setup-hook))
                      (setq accept-command
                            (lookup-key (current-local-map) (kbd "]"))))
                    "plan"))
                 ((symbol-function 'set-transient-map)
                  (lambda (map &rest _)
                    (setq activated-map map))))
              (emacsvox-agent-shell-next-block-at-point)))
          '((stop nil)
            (icon large-movement)
            (speak "Plan. One step")))))
      (should (equal default-value "Plan"))
      (should
       (eq accept-command
           #'emacsvox-agent-shell--accept-block-type-default))
      (should (eq emacsvox-agent-shell--block-navigation-type 'plan))
      (should
       (eq activated-map emacsvox-agent-shell--block-repeat-map)))))

(ert-deftest emacsvox-agent-shell-block-navigation-has-viewport-fallback ()
  "Plain viewport responses should remain typed navigation targets."
  (with-temp-buffer
    (insert
     (propertize "Question\n\n" 'agent-shell-viewport-prompt t))
    (let ((response-position (point)))
      (insert "Plain answer")
      (setq major-mode 'agent-shell-viewport-view-mode)
      (goto-char (point-min))
      (should
       (equal
        (mapcar
         (lambda (location) (plist-get location :type))
         (emacsvox-agent-shell--block-locations))
        '(user-prompt agent-response)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type
           'agent-response 'forward))
        '((stop nil)
          (icon large-movement)
          (speak "Plain answer"))))
      (should (= (point) response-position)))))

(ert-deftest emacsvox-agent-shell-block-navigation-selects-rendered-tables ()
  "Rendered tables should be selectable without reading every cell."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        (concat "before\n"
                "| A | B |\n|---|---|\n| 1 | 2 |\n"
                "between\n"
                "| C | D |\n|---|---|\n| 3 | 4 |\n"
                "after\n")
      (setq major-mode 'agent-shell-mode)
      (should
       (= 2
          (length
           (seq-filter
            (lambda (location)
              (eq (plist-get location :type) 'table))
            (emacsvox-agent-shell--block-locations)))))
      (goto-char (point-min))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type 'table 'forward)
          (emacsvox-agent-shell--jump-block-of-type 'table 'forward))
        '((stop nil)
          (icon open-object)
          (speak "Table, 1 data row, 2 columns. A.")
          (stop nil)
          (icon open-object)
          (speak "Table, 1 data row, 2 columns. C."))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--jump-block-of-type 'table 'backward))
        '((stop nil)
          (icon open-object)
          (speak "Table, 1 data row, 2 columns. 2, B.")))))))

(ert-deftest emacsvox-agent-shell-table-cell-feedback-is-customizable ()
  "Table feedback should support every title set and both orderings."
  (emacsvox-agent-shell-test--with-rendered-table
      "| Name | Role |\n|---|---|\n| Alice | Engineer |\n"
    (goto-char (point-min))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (dolist (case '(((column) first "Engineer, Role.")
                    ((row) first "Engineer, Alice.")
                    ((column row) first "Engineer, Alice, Role.")
                    (nil first "Engineer.")
                    ((column row) last "Alice, Role, Engineer.")))
      (let ((emacsvox-agent-shell-table-titles (nth 0 case))
            (emacsvox-agent-shell-table-data-position (nth 1 case)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell--table-cell-feedback))
          `((icon item) (speak ,(nth 2 case)))))))))

(ert-deftest emacsvox-agent-shell-table-speaking-method-is-interactive ()
  "The table selector should toggle each setting and announce full state."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first)
        (keys '(?c ?r ?o ?c)))
    (cl-letf (((symbol-function 'read-char-choice)
               (lambda (prompt choices)
                 (should (string-prefix-p "Toggle table speech" prompt))
                 (should (equal choices '(?c ?r ?o)))
                 (pop keys))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively
           #'emacsvox-agent-shell-table-select-speaking-method))
        '((icon button)
          (speak
           "Table speech: data first; column titles off; row titles off."))))
      (should-not emacsvox-agent-shell-table-titles)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively
           #'emacsvox-agent-shell-table-select-speaking-method))
        '((icon button)
          (speak
           "Table speech: data first; column titles off; row titles on."))))
      (should (equal emacsvox-agent-shell-table-titles '(row)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively
           #'emacsvox-agent-shell-table-select-speaking-method))
        '((icon button)
          (speak
           "Table speech: titles first; column titles off; row titles on."))))
      (should (eq emacsvox-agent-shell-table-data-position 'last))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively
           #'emacsvox-agent-shell-table-select-speaking-method))
        '((icon button)
          (speak
           "Table speech: titles first; column titles on; row titles on."))))
      (should (equal emacsvox-agent-shell-table-titles '(column row)))
      (should-not keys))))

(ert-deftest emacsvox-agent-shell-table-context-describes-header-and-data ()
  "Manual table context should distinguish headers from one-based data rows."
  (emacsvox-agent-shell-test--with-rendered-table
      (concat "| Name | Role | Notes |\n"
              "|---|---|---|\n"
              "| Alice | Engineer | Builds |\n"
              "| Bob | Reviewer | Checks |\n")
    (goto-char (point-min))
    (search-forward "Role")
    (backward-char (length "Role"))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'emacsvox-agent-shell-table-speak-context))
      '((icon item)
        (speak
         "Header row, column 2 of 3; table has 2 data rows."))))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'emacsvox-agent-shell-table-speak-context))
      '((icon item)
        (speak "Data row 1 of 2, column 2 of 3."))))))

(ert-deftest emacsvox-agent-shell-table-context-handles-headerless-and-outside ()
  "Manual context should count headerless rows and reject non-table text."
  (emacsvox-agent-shell-test--with-rendered-table
      "| hello | world |\n| goodbye | moon |\n"
    (goto-char (point-min))
    (search-forward "world")
    (backward-char (length "world"))
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'emacsvox-agent-shell-table-speak-context))
      '((icon item) (speak "Row 1 of 2, column 2 of 2."))))
    (goto-char (point-max))
    (insert "\noutside")
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (should-error
        (call-interactively #'emacsvox-agent-shell-table-speak-context)
        :type 'user-error)))))

(ert-deftest emacsvox-agent-shell-table-entry-is-directional-in-both-views ()
  "Real item navigation should find embedded tables in both directions."
  (dolist (case
           `((agent-shell-next-item
              agent-shell-mode forward
              ((icon open-object)
               (speak "Table, 1 data row, 2 columns. A."))
              ,?A)
             (agent-shell-previous-item
              agent-shell-mode backward
              ((icon open-object)
               (speak "Table, 1 data row, 2 columns. 2, B."))
              ,?2)
             (agent-shell-viewport-next-item
              agent-shell-viewport-view-mode forward
              ((icon open-object)
               (speak "Table, 1 data row, 2 columns. A."))
              ,?A)
             (agent-shell-viewport-previous-item
              agent-shell-viewport-view-mode backward
              ((icon open-object)
               (speak "Table, 1 data row, 2 columns. 2, B."))
              ,?2)))
    (should
     (equal
      (emacsvox-agent-shell-test--table-entry
       (nth 0 case) (nth 1 case) (nth 2 case))
      (list (nth 3 case) (nth 4 case))))))

(ert-deftest emacsvox-agent-shell-prompt-letters-do-not-discover-tables ()
  "Typing n or p at the live prompt should insert without moving focus."
  (dolist (key '("n" "p"))
    (let ((buffer (generate-new-buffer " *agent-shell-prompt-table-test*")))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer buffer)
            (insert "before\n| A |\n|---|\n| 1 |\nafter\n\nCodex> ")
            (agent-shell-markdown-replace-markup)
            (setq major-mode 'agent-shell-mode)
            (use-local-map agent-shell-mode-map)
            (goto-char (point-max))
            (let ((origin (point))
                  events)
              (cl-letf
                  (((symbol-function 'shell-maker-busy) (lambda () nil))
                   ((symbol-function 'shell-maker-point-at-last-prompt-p)
                    (lambda () t)))
                (setq events
                      (emacsvox-agent-shell-test--capture-events
                        (execute-kbd-macro (kbd key)))))
              (should (= (point) (point-max) (1+ origin)))
              (should (string-suffix-p (concat "Codex> " key)
                                       (buffer-string)))
              (should-not
               (get-text-property
                (point) 'agent-shell-markdown-table-source))
              (should-not
               (seq-some
                (lambda (event)
                  (and (eq (car event) 'speak)
                       (string-match-p
                        "Table"
                        (substring-no-properties (cadr event)))))
                events))))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-agent-shell-table-discovery-selects-nearest-visible ()
  "Discovery should visit multiple tables in order and ignore hidden tables."
  (emacsvox-agent-shell-test--with-rendered-table
      (concat "before\n| A |\n|---|\n| 1 |\nbetween\n"
              "| B |\n|---|\n| 2 |\nafter\n")
    (let* ((first
            (next-single-property-change
             (point-min) 'agent-shell-markdown-table-source nil (point-max)))
           (first-region
            (progn
              (goto-char first)
              (emacsvox-agent-shell--markdown-table-region-at-point)))
           (second
            (next-single-property-change
             (cdr first-region)
             'agent-shell-markdown-table-source nil (point-max))))
      (should
       (= first
          (emacsvox-agent-shell--table-between
           (point-min) (point-max) 'forward)))
      (should
       (equal
        (get-text-property
         (emacsvox-agent-shell--table-between
          (point-max) (point-min) 'backward)
         'agent-shell-markdown-table-source)
        "| B |\n|---|\n| 2 |"))
      (put-text-property (car first-region) (cdr first-region) 'invisible t)
      (should
       (= second
          (emacsvox-agent-shell--table-between
           (point-min) (point-max) 'forward))))))

(ert-deftest emacsvox-agent-shell-table-sequential-boundaries-exit ()
  "Sequential table commands should leave at either edge in both views."
  (dolist (case
           '((agent-shell-next-item agent-shell-mode "2"
              ((icon close-object) (speak "After table. after")) "after")
             (agent-shell-previous-item agent-shell-mode "A"
              ((icon close-object) (speak "Before table. before")) "before")
             (agent-shell-viewport-next-item
              agent-shell-viewport-view-mode "2"
              ((icon close-object) (speak "After table. after")) "after")
             (agent-shell-viewport-previous-item
              agent-shell-viewport-view-mode "A"
              ((icon close-object) (speak "Before table. before")) "before")))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
      (goto-char (point-min))
      (search-forward (nth 2 case))
      (backward-char (length (nth 2 case)))
      (setq major-mode (nth 1 case))
      (cl-letf (((symbol-function 'shell-maker-busy) (lambda () t)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively (nth 0 case)))
          (nth 3 case))))
      (should (looking-at (nth 4 case)))
      (should-not
       (get-text-property (point) 'agent-shell-markdown-table-source)))))

(ert-deftest emacsvox-agent-shell-table-row-speech-respects-title-settings ()
  "Logical row speech should announce a row title once and format each cell."
  (emacsvox-agent-shell-test--with-rendered-table
      (concat "| Name | Role | Notes |\n"
              "|---|---|---|\n"
              "| Alice | Engineer | Builds |\n"
              "| Bob | Reviewer | Checks |\n")
    (goto-char (point-min))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (dolist (case
             '(((column row) first
                "Alice. Engineer, Role. Builds, Notes.")
               ((column row) last
                "Alice. Role, Engineer. Notes, Builds.")
               ((column) first
                "Alice, Name. Engineer, Role. Builds, Notes.")
               (nil first "Alice. Engineer. Builds.")))
      (let ((emacsvox-agent-shell-table-titles (nth 0 case))
            (emacsvox-agent-shell-table-data-position (nth 1 case)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'emacsvox-agent-shell-table-speak-row))
          `((icon item) (speak ,(nth 2 case)))))))))

(ert-deftest emacsvox-agent-shell-table-column-speech-respects-title-settings ()
  "Logical column speech should announce its title once and format each row."
  (emacsvox-agent-shell-test--with-rendered-table
      (concat "| Name | Role | Notes |\n"
              "|---|---|---|\n"
              "| Alice | Engineer | Builds |\n"
              "| Bob | Reviewer | Checks |\n")
    (goto-char (point-min))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (dolist (case
             '(((column row) first
                "Role. Engineer, Alice. Reviewer, Bob.")
               ((column row) last
                "Role. Alice, Engineer. Bob, Reviewer.")
               ((column) first "Role. Engineer. Reviewer.")
               ((row) first "Engineer, Alice. Reviewer, Bob.")
               (nil first "Engineer. Reviewer.")))
      (let ((emacsvox-agent-shell-table-titles (nth 0 case))
            (emacsvox-agent-shell-table-data-position (nth 1 case)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'emacsvox-agent-shell-table-speak-column))
          `((icon item) (speak ,(nth 2 case)))))))))

(ert-deftest emacsvox-agent-shell-table-row-column-handle-table-kinds ()
  "Row and column speech should handle header rows and headerless tables."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "| Name | Role | Notes |\n|---|---|---|\n| Alice | Engineer | Builds |\n"
      (goto-char (point-min))
      (search-forward "Role")
      (backward-char (length "Role"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-speak-row))
        '((icon item) (speak "Header row. Name. Role. Notes.")))))
    (emacsvox-agent-shell-test--with-rendered-table
        "| hello | world |\n| goodbye | moon |\n"
      (goto-char (point-min))
      (search-forward "world")
      (backward-char (length "world"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-speak-row))
        '((icon item) (speak "hello. world."))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-speak-column))
        '((icon item)
          (speak "world, hello. moon, goodbye.")))))))

(ert-deftest emacsvox-agent-shell-table-row-column-reject-outside-table ()
  "Manual row and column commands should remain silent outside tables."
  (with-temp-buffer
    (insert "outside")
    (dolist (command '(emacsvox-agent-shell-table-speak-row
                       emacsvox-agent-shell-table-speak-column))
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (should-error (call-interactively command) :type 'user-error))))))

(ert-deftest emacsvox-agent-shell-table-copy-cell-copies-logical-value ()
  "Cell copying should omit visual structure and text properties."
  (let ((kill-ring nil)
        (kill-ring-yank-pointer nil))
    (emacsvox-agent-shell-test--with-rendered-table
        "| Name | Value |\n|---|---|\n| Alice | `a|b` |\n"
      (goto-char (point-min))
      (search-forward "Alice")
      (agent-shell-markdown-table-next-cell)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-copy-cell))
        '((icon save-object) (speak "Copied table cell."))))
      (should (equal (car kill-ring) "a|b"))
      (should-not (text-properties-at 0 (car kill-ring))))))

(ert-deftest emacsvox-agent-shell-table-copy-cell-handles-blank-and-outside ()
  "Cell copying should preserve blanks and remain silent outside tables."
  (let ((kill-ring '("existing"))
        (kill-ring-yank-pointer nil))
    (emacsvox-agent-shell-test--with-rendered-table
        "| Name | Value |\n|---|---|\n| Alice |  |\n"
      (goto-char (point-min))
      (search-forward "Alice")
      (agent-shell-markdown-table-next-cell)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-copy-cell))
        '((icon save-object) (speak "Copied table cell."))))
      (should (equal (car kill-ring) "")))
    (with-temp-buffer
      (insert "outside")
      (should-not
       (emacsvox-agent-shell-test--capture-events
         (should-error
          (call-interactively #'emacsvox-agent-shell-table-copy-cell)
          :type 'user-error)))
      (should (equal (car kill-ring) "")))))

(ert-deftest emacsvox-agent-shell-table-copy-row-and-column-are-plain ()
  "Row and column copying should use tabular plain-text separators."
  (let ((kill-ring nil)
        (kill-ring-yank-pointer nil))
    (emacsvox-agent-shell-test--with-rendered-table
        "| Name | Value |\n|---|---|\n| Alice | `a|b` |\n| Bob | two |\n"
      (goto-char (point-min))
      (search-forward "a|b")
      (backward-char (length "a|b"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-copy-row))
        '((icon save-object) (speak "Copied table row."))))
      (should (equal (car kill-ring) "Alice\ta|b"))
      (should-not (text-properties-at 0 (car kill-ring)))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-copy-column))
        '((icon save-object) (speak "Copied table column."))))
      (should (equal (car kill-ring) "Value\na|b\ntwo"))
      (should-not (text-properties-at 0 (car kill-ring))))
    (with-temp-buffer
      (insert "outside")
      (dolist (command '(emacsvox-agent-shell-table-copy-row
                         emacsvox-agent-shell-table-copy-column))
        (should-error (call-interactively command) :type 'user-error))
      (should (equal (car kill-ring) "Value\na|b\ntwo")))))

(ert-deftest emacsvox-agent-shell-table-grid-navigation-is-logical ()
  "Grid movement should retain row/column identity across visual wrapping."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first)
        (agent-shell-markdown-table-max-width-fraction 1.0))
    (cl-letf (((symbol-function 'agent-shell-markdown--display-width)
               (lambda (&optional _window) 38)))
      (emacsvox-agent-shell-test--with-rendered-table
          (concat "| Name | Role | Notes |\n"
                  "|---|---|---|\n"
                  "| Alice | Engineer | owns a long wrapped description |\n"
                  "| Bob | Reviewer | Checks |\n")
        (goto-char (point-min))
        (search-forward "Engineer")
        (backward-char (length "Engineer"))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively
             #'emacsvox-agent-shell-table-next-column))
          '((icon item)
            (speak
             "owns a long wrapped description, Alice, Notes."))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'emacsvox-agent-shell-table-next-row))
          '((icon item) (speak "Checks, Bob, Notes."))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively
             #'emacsvox-agent-shell-table-previous-column))
          '((icon item) (speak "Reviewer, Bob, Role."))))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'emacsvox-agent-shell-table-previous-row))
          '((icon item) (speak "Engineer, Alice, Role."))))))))

(ert-deftest emacsvox-agent-shell-table-grid-navigation-accepts-leading-border ()
  "Grid movement should accept ordinary line entry on the leading border."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
      (goto-char (point-min))
      (goto-char
       (next-single-property-change
        (point) 'agent-shell-markdown-table-source nil (point-max)))
      (should
       (get-text-property (point) 'agent-shell-markdown-table-source))
      (should-not
       (get-text-property (point) 'agent-shell-markdown-table-cell-start))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-next-row))
        '((icon item) (speak "1, A.")))))))

(ert-deftest emacsvox-agent-shell-table-grid-navigation-accepts-bottom-entry ()
  "Grid movement should accept upward entry on the final row's border."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
      (goto-char (point-min))
      (goto-char
       (next-single-property-change
        (point) 'agent-shell-markdown-table-source nil (point-max)))
      (let ((region (emacsvox-agent-shell--markdown-table-region-at-point)))
        (goto-char (1- (cdr region)))
        (beginning-of-line))
      (should
       (get-text-property (point) 'agent-shell-markdown-table-source))
      (should-not
       (get-text-property (point) 'agent-shell-markdown-table-cell-start))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-previous-row))
        '((icon item) (speak "A.")))))))

(ert-deftest emacsvox-agent-shell-table-grid-navigation-handles-edges ()
  "Horizontal edges should warn; vertical edges should leave the table."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
      (goto-char (point-min))
      (search-forward "A")
      (backward-char)
      (let ((position (point)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively
             #'emacsvox-agent-shell-table-previous-column))
          '((icon warn-user) (speak "Left edge of table."))))
        (should (= position (point))))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-previous-row))
        '((icon close-object) (speak "Before table. before"))))
      (should (looking-at "before"))
      (search-forward "2")
      (backward-char)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'emacsvox-agent-shell-table-next-row))
        '((icon close-object) (speak "After table. after"))))
      (should (looking-at "after")))))

(ert-deftest emacsvox-agent-shell-table-explicit-exit-moves-past-table ()
  "Meta arrow commands should leave directly in either direction."
  (emacsvox-agent-shell-test--with-rendered-table
      "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
    (goto-char (point-min))
    (search-forward "1")
    (backward-char)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'emacsvox-agent-shell-table-exit-forward))
      '((icon close-object) (speak "After table. after"))))
    (search-backward "B")
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (call-interactively #'emacsvox-agent-shell-table-exit-backward))
      '((icon close-object) (speak "Before table. before"))))))

(ert-deftest emacsvox-agent-shell-table-navigation-is-contextual ()
  "Ordinary cursor entry should announce and activate table-only keys."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| Name | Role |\n|---|---|\n| Alice | Engineer |\nafter\n"
      (goto-char (point-min))
      (setq-local emacsvox-aural-module 'viewport)
      (emacsvox-agent-shell--table-navigation-setup)
      (should (eq emacsvox-aural-module 'agent-shell))
      (should-not emacsvox-agent-shell--table-navigation-active)
      (emacsvox-agent-shell--table-navigation-pre-command)
      (search-forward "Engineer")
      (backward-char (length "Engineer"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--table-navigation-post-command))
        '((stop nil)
          (icon open-object)
          (speak
           "Table, 1 data row, 2 columns. Engineer, Alice, Role."))))
      (should emacsvox-agent-shell--table-navigation-active)
      (should
       (eq (key-binding (kbd "<right>"))
           #'emacsvox-agent-shell-table-next-column))
      (dolist
          (binding
           `(("r" . ,#'emacsvox-agent-shell-table-speak-row)
             ("c" . ,#'emacsvox-agent-shell-table-speak-column)
             ("SPC" . ,#'emacsvox-agent-shell-table-speak-cell)
             ("." . ,#'emacsvox-agent-shell-table-speak-context)
             ("=" . ,#'emacsvox-agent-shell-table-speak-dimensions)
             ("w" . ,#'emacsvox-agent-shell-table-copy-cell)
             ("k k" . ,#'emacsvox-agent-shell-table-copy-cell)
             ("k r" . ,#'emacsvox-agent-shell-table-copy-row)
             ("k c" . ,#'emacsvox-agent-shell-table-copy-column)
             ("a" . ,#'emacsvox-agent-shell-table-select-speaking-method)
             ("M-<up>" . ,#'emacsvox-agent-shell-table-exit-backward)
             ("M-<down>" . ,#'emacsvox-agent-shell-table-exit-forward)))
        (should
         (eq (lookup-key emacsvox-agent-shell--table-navigation-map
                         (kbd (car binding)))
             (cdr binding))))
      (goto-char (point-max))
      (emacsvox-agent-shell--table-navigation-post-command)
      (should-not emacsvox-agent-shell--table-navigation-active)
      (emacsvox-agent-shell--table-navigation-cleanup)
      (should (eq emacsvox-aural-module 'viewport))
      (should-not
       (memq #'emacsvox-agent-shell--table-navigation-post-command
             post-command-hook)))))

(ert-deftest emacsvox-agent-shell-table-feedback-handles-title-cells-and-blanks ()
  "Table feedback should avoid duplicate titles and name blank data."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "| Name | Role |\n|---|---|\n| Alice |  |\n"
      (goto-char (point-min))
      (search-forward "Role")
      (backward-char (length "Role"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--table-cell-feedback))
        '((icon item) (speak "Role."))))
      (search-forward "Alice")
      (backward-char (length "Alice"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--table-cell-feedback))
        '((icon item) (speak "Alice, Name."))))
      (agent-shell-markdown-table-next-cell)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--table-cell-feedback))
        '((icon item) (speak "blank, Alice, Role.")))))))

(ert-deftest emacsvox-agent-shell-table-feedback-preserves-logical-cells ()
  "Table feedback should speak wrapped cells and protected pipes in full."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first)
        (agent-shell-markdown-table-max-width-fraction 1.0))
    (cl-letf (((symbol-function 'agent-shell-markdown--display-width)
               (lambda (&optional _window) 35)))
      (emacsvox-agent-shell-test--with-rendered-table
          (concat "| Code | Notes |\n"
                  "|---|---|\n"
                  "| `a|b` | owns a long wrapped description |\n")
        (goto-char (point-min))
        (search-forward "owns a long")
        (backward-char (length "owns a long"))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (emacsvox-agent-shell--table-cell-feedback))
          '((icon item)
            (speak
             "owns a long wrapped description, a|b, Notes."))))))))

(ert-deftest emacsvox-agent-shell-table-feedback-respects-headerless-tables ()
  "A table without a separator should not invent column titles."
  (let ((emacsvox-agent-shell-table-titles '(column row))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "| hello | world |\n| goodbye | moon |\n"
      (goto-char (point-min))
      (search-forward "world")
      (backward-char (length "world"))
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (emacsvox-agent-shell--table-cell-feedback))
        '((icon item) (speak "world, hello.")))))))

(ert-deftest emacsvox-agent-shell-table-navigation-speaks-in-both-views ()
  "Shell and viewport table traversal should share semantic feedback."
  (let ((emacsvox-agent-shell-table-titles '(column))
        (emacsvox-agent-shell-table-data-position 'first))
    (emacsvox-agent-shell-test--with-rendered-table
        "before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n"
      (goto-char (point-min))
      (goto-char
       (next-single-property-change
        (point) 'agent-shell-markdown-table-source nil (point-max)))
      (search-forward "B")
      (backward-char)
      (setq major-mode 'agent-shell-mode)
      (cl-letf (((symbol-function 'shell-maker-busy) (lambda () t)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'agent-shell-next-item))
          '((icon item) (speak "1, A.")))))
      (search-forward "2")
      (backward-char)
      (setq major-mode 'agent-shell-viewport-view-mode)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'agent-shell-viewport-previous-item))
        '((icon item) (speak "1, A."))))
      (search-forward "2")
      (backward-char)
      (should
       (equal
        (emacsvox-agent-shell-test--capture-events
          (call-interactively #'agent-shell-viewport-next-item))
        '((icon close-object) (speak "After table. after")))))))

(ert-deftest emacsvox-agent-shell-unknown-block-uses-fallback ()
  "Unknown non-empty content should reach the fallback speaker."
  (should
   (equal
    (emacsvox-agent-shell-test--speak-pending
     '(("request-mystery" . "Unrecognized but useful content")))
    '((speak "Unrecognized but useful content")))))

(ert-deftest emacsvox-agent-shell-unknown-block-respects-speech-level ()
  "Unknown content should be discoverable without adding background chatter."
  (with-temp-buffer
    (setq-local emacsvox-agent-shell-speech-level 'response)
    (should
     (equal
      (emacsvox-agent-shell-test--capture-events
        (emacsvox-agent-shell--speak-content "Useful content" 'unknown))
      '((speak "Additional agent content available."))))
    (setq-local emacsvox-agent-shell-speech-level 'notify)
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (emacsvox-agent-shell--speak-content "Useful content" 'unknown)))
    (setq-local emacsvox-agent-shell-speech-level 'quiet)
    (should-not
     (emacsvox-agent-shell-test--capture-events
       (emacsvox-agent-shell--speak-content "Useful content" 'unknown)))))

(ert-deftest emacsvox-agent-shell-advice-targets-exist ()
  "Every configured advice and public integration target should exist."
  (should-not
   (seq-remove (lambda (entry) (fboundp (car entry)))
               emacsvox-agent-shell--advice-list))
  (dolist (function '(agent-shell-goto-last-interaction
                      agent-shell-interaction-at-point))
    (should (fboundp function)))
  (should-not (assq 'agent-shell--update-fragment
                    emacsvox-agent-shell--advice-list)))

(ert-deftest emacsvox-agent-shell-viewport-submit-uses-public-status ()
  "Pre-send public status should determine queued and submitted feedback."
  (let (status)
    (cl-letf (((symbol-function 'emacsvox-agent-shell--session-buffer)
               (lambda (&optional _) (current-buffer)))
              ((symbol-function 'agent-shell-status)
               (lambda (&rest arguments)
                 (should (eq (plist-get arguments :shell-buffer)
                             (current-buffer)))
                 status)))
      (dolist (case '((ready submitted)
                      (busy queued)
                      (blocked queued)
                      (unknown nil)))
        (setq status (car case))
        (should
         (eq (emacsvox-agent-shell--viewport-submit-disposition)
             (cadr case))))))
  (cl-letf (((symbol-function 'emacsvox-agent-shell--session-buffer)
             (lambda (&optional _) (user-error "No session"))))
    (should-not (emacsvox-agent-shell--viewport-submit-disposition)))
  (should
   (equal
    (emacsvox-agent-shell--viewport-submit-announcement nil t nil)
    "Prompt sent. Continue composing.")))

(ert-deftest emacsvox-agent-shell-viewport-submit-announces-success ()
  "A ready session should report immediate viewport submission."
  (let ((agent-shell-prefer-viewport-interaction t)
        (agent-shell-session-strategy 'new-deferred)
        sent)
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf (((symbol-function
                  'agent-shell-viewport-compose-send-and-wait-for-response)
                 (lambda () (setq sent t)))
                ((symbol-function
                  'emacsvox-agent-shell--viewport-submit-disposition)
                 (lambda () 'submitted)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'agent-shell-viewport-compose-send))
          '((icon close-object)
            (speak "Prompt submitted."))))
        (should sent)))))

(ert-deftest emacsvox-agent-shell-viewport-submit-announces-queueing ()
  "A busy session should report that its viewport prompt was queued."
  (let ((agent-shell-prefer-viewport-interaction t)
        (agent-shell-session-strategy 'new-deferred)
        sent)
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf (((symbol-function
                  'agent-shell-viewport-compose-send-and-wait-for-response)
                 (lambda () (setq sent t)))
                ((symbol-function
                  'emacsvox-agent-shell--viewport-submit-disposition)
                 (lambda () 'queued)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'agent-shell-viewport-compose-send))
          '((icon close-object)
            (speak "Prompt queued."))))
        (should sent)))))

(ert-deftest emacsvox-agent-shell-viewport-submit-announces-continued-compose ()
  "A prefix submission should say that composition remains available."
  (let ((agent-shell-session-strategy 'new-deferred)
        (agent-shell-viewport-dismiss-on-send t)
        queued)
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf (((symbol-function 'agent-shell-viewport--compose-queue)
                 (lambda () (setq queued t)))
                ((symbol-function
                  'emacsvox-agent-shell--viewport-submit-disposition)
                 (lambda () 'queued)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (let ((current-prefix-arg '(4)))
              (call-interactively #'agent-shell-viewport-compose-send)))
          '((icon task-done)
            (speak "Prompt queued. Continue composing."))))
        (should queued)
        (should (eq major-mode 'agent-shell-viewport-edit-mode))))))

(ert-deftest emacsvox-agent-shell-viewport-submit-announces-dismissal ()
  "A fire-and-forget submission should report compose-window dismissal."
  (let ((agent-shell-session-strategy 'new-deferred)
        (agent-shell-viewport-dismiss-on-send t)
        dismissed)
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf (((symbol-function
                  'agent-shell-viewport-compose-send-and-dismiss)
                 (lambda () (setq dismissed t)))
                ((symbol-function
                  'emacsvox-agent-shell--viewport-submit-disposition)
                 (lambda () 'submitted)))
        (should
         (equal
          (emacsvox-agent-shell-test--capture-events
            (call-interactively #'agent-shell-viewport-compose-send))
          '((icon close-object)
            (speak
             "Prompt submitted. Compose window dismissed."))))
        (should dismissed)))))

(ert-deftest emacsvox-agent-shell-viewport-submit-does-not-confirm-error ()
  "A failed viewport submission should not produce a success cue."
  (let ((agent-shell-prefer-viewport-interaction t)
        (agent-shell-session-strategy 'new-deferred))
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf (((symbol-function
                  'agent-shell-viewport-compose-send-and-wait-for-response)
                 (lambda () (user-error "Nothing to send")))
                ((symbol-function
                  'emacsvox-agent-shell--viewport-submit-disposition)
                 (lambda () 'submitted)))
        (should-not
         (emacsvox-agent-shell-test--capture-events
           (should-error
            (call-interactively #'agent-shell-viewport-compose-send)
            :type 'user-error)))))))

(ert-deftest emacsvox-agent-shell-viewport-cancel-announces-accepted-only ()
  "Viewport cancellation should distinguish acceptance from declining it."
  (let ((shell-buffer (generate-new-buffer " *agent-shell-shell-test*"))
        (agent-shell-prefer-viewport-interaction t))
    (unwind-protect
        (with-temp-buffer
          (insert "draft prompt")
          (setq major-mode 'agent-shell-viewport-edit-mode)
          (cl-letf (((symbol-function 'agent-shell-viewport--ensure-buffer)
                     #'ignore)
                    ((symbol-function 'agent-shell-viewport--shell-buffer)
                     (lambda () shell-buffer))
                    ((symbol-function 'shell-maker-history-position)
                     (lambda () t))
                    ((symbol-function 'agent-shell-viewport-view-last)
                     (lambda ()
                       (setq major-mode 'agent-shell-viewport-view-mode)))
                    ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
            (should
             (equal
              (emacsvox-agent-shell-test--capture-events
                (call-interactively #'agent-shell-viewport-compose-cancel))
              '((icon close-object)
                (speak "Prompt composition cancelled."))))
            (should (eq major-mode 'agent-shell-viewport-view-mode)))
          (setq major-mode 'agent-shell-viewport-edit-mode)
          (cl-letf (((symbol-function 'agent-shell-viewport--ensure-buffer)
                     #'ignore)
                    ((symbol-function 'agent-shell-viewport--shell-buffer)
                     (lambda () shell-buffer))
                    ((symbol-function 'shell-maker-history-position)
                     (lambda () t))
                    ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
            (should-not
             (emacsvox-agent-shell-test--capture-events
               (call-interactively #'agent-shell-viewport-compose-cancel)))
            (should (eq major-mode 'agent-shell-viewport-edit-mode))))
      (when (buffer-live-p shell-buffer)
        (kill-buffer shell-buffer)))))

(ert-deftest emacsvox-agent-shell-ui-face-inventory-is-current ()
  "Every current non-Markdown agent-shell face should be classified."
  (let ((configured
         (sort
          (append (mapcar #'car emacsvox-agent-shell--ui-face-voice-map)
                  (seq-filter
                   #'facep
                   (mapcar #'car emacsvox-agent-shell--chat-face-voice-map))
                  emacsvox-agent-shell--ui-unvoiced-faces
                  nil)
          (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
        (current
         (sort
          (seq-filter
           (lambda (face)
             (let ((name (symbol-name face)))
               (and (string-prefix-p "agent-shell-" name)
                    (not (string-prefix-p "agent-shell-markdown-" name)))))
           (face-list))
          (lambda (a b) (string< (symbol-name a) (symbol-name b))))))
    (should (equal configured current))
    (dolist (face configured)
      (should (facep face)))
    (should-not (memq 'agent-shell-mode-line configured))))

(ert-deftest emacsvox-agent-shell-chat-labels-are-voiced-and-spoken ()
  "Optional chat overlays should contribute their visible labels to speech."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (dolist (entry emacsvox-agent-shell--chat-face-voice-map)
    (should (facep (car entry)))
    (should
     (eq (voice-setup-get-voice-for-face (car entry)) (cadr entry))))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Claude"))))
     agent-shell-chat--labeled t)
    (insert
     (propertize
      "Claude> " 'font-lock-face
      '(comint-highlight-prompt comint-highlight-prompt))
     "hello\n"
     (propertize "<shell-maker-end-of-prompt>" 'invisible t)
     "hi there\n")
    (agent-shell-chat--relabel)
    (goto-char (point-min))
    (search-forward "hello")
    (let (spoken)
      (emacsvox-agent-shell--speak-line-around
       (lambda (&rest _)
         (setq spoken
               (emacsvox-agent-shell--prepare-speech-text
                (buffer-substring
                 (line-beginning-position) (line-end-position))))))
      (should (equal (substring-no-properties spoken) "Me. hello"))
      (should (eq (get-text-property 0 'face spoken)
                  'agent-shell-chat-me-label)))
    (search-forward "<shell-maker-end-of-prompt>")
    (backward-char (length "<shell-maker-end-of-prompt>"))
    (let (spoken)
      (emacsvox-agent-shell--speak-line-around
       (lambda (&rest _)
         (setq spoken
               (emacsvox-agent-shell--prepare-speech-text
                (buffer-substring
                 (line-beginning-position) (line-end-position))))))
      (should (equal (substring-no-properties spoken) "Claude. hi there"))
      (should (eq (get-text-property 0 'face spoken)
                  'agent-shell-chat-agent-label)))))

(ert-deftest emacsvox-agent-shell-chat-labels-follow-separate-content-lines ()
  "Chat labels should describe content after whitespace-swallowing overlays."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Claude"))))
     agent-shell-chat--labeled t)
    ;; Match the live layout: chat label overlays consume the whitespace
    ;; before each content line and therefore end at that line's beginning.
    (insert
     (propertize
      "Claude> " 'font-lock-face
      '(comint-highlight-prompt comint-highlight-prompt))
     "\n\nhello\n"
     (propertize "<shell-maker-end-of-prompt>" 'invisible t)
     "\nhi there\n\n"
     (propertize
      "Claude> " 'font-lock-face
      '(comint-highlight-prompt comint-highlight-prompt)))
    (agent-shell-chat--relabel)
    (cl-labels
        ((speak-line-at
          (text)
          (goto-char (point-min))
          (search-forward text)
          (goto-char (match-beginning 0))
          (let (spoken)
            (emacsvox-agent-shell--speak-line-around
             (lambda (&rest _)
               (setq spoken
                     (emacsvox-agent-shell--prepare-speech-text
                      (buffer-substring
                       (line-beginning-position) (line-end-position))))))
            spoken)))
      (let ((spoken (speak-line-at "hello")))
        (should (equal (substring-no-properties spoken) "Me. hello"))
        (should (eq (get-text-property 0 'face spoken)
                    'agent-shell-chat-me-label)))
      (let ((spoken (speak-line-at "hi there")))
        (should (equal (substring-no-properties spoken) "Claude. hi there"))
        (should (eq (get-text-property 0 'face spoken)
                    'agent-shell-chat-agent-label))))))

(ert-deftest emacsvox-agent-shell-live-chat-prompt-announces-editability ()
  "The live chat prompt should speak its role without decorative glyphs."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (dolist (case '(("" "Me. Ready for input.")
                  ("draft" "Me. draft")))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      ;; Agent Shell gives newline comment-end syntax; preserve that detail so
      ;; label parsing cannot accidentally depend on the default syntax table.
      (set-syntax-table (copy-syntax-table (syntax-table)))
      (modify-syntax-entry ?\n ">" (syntax-table))
      (setq-local
       agent-shell--state
       '((:agent-config . ((:mode-line-name . "Codex"))))
       agent-shell-chat--labeled t)
      ;; Leave a completed content line and blank separator so current Agent
      ;; Shell carries the visible label on the newline before the prompt.
      (insert "Earlier response\n\n")
      (let ((prompt-start (point)))
        (insert
         (propertize
          "Codex> " 'font-lock-face
          '(comint-highlight-prompt comint-highlight-prompt))
         (car case))
        (let ((agent-shell-prompt-bar-mode nil))
          (agent-shell-chat--relabel))
        (should
         (seq-find
          (lambda (overlay)
            (eq (overlay-get overlay 'category)
                'agent-shell-chat-me-label))
          (overlays-in (1- prompt-start) prompt-start)))
        (let* ((emacsvox-agent-shell--chat-label-context
                (emacsvox-agent-shell--chat-label-context-between
                 prompt-start (point-max)))
               (spoken
                (emacsvox-agent-shell--prepare-speech-text
                 (buffer-substring prompt-start (point-max)))))
          (should
           (equal
            (plist-get emacsvox-agent-shell--chat-label-context :text)
            "Me"))
          (should
           (plist-get emacsvox-agent-shell--chat-label-context :editable))
          (should (equal (substring-no-properties spoken) (cadr case)))
          (should-not (string-match-p "❯" spoken))
          (should (eq (get-text-property 0 'face spoken)
                      'agent-shell-chat-me-label)))))))

(ert-deftest emacsvox-agent-shell-live-input-horizontal-boundaries-are-semantic ()
  "Character motion should stop at live input edges without core artifacts."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (dolist (draft '("" "draft"))
    (with-temp-buffer
      (pcase-let* ((`(,start . ,end)
                    (emacsvox-agent-shell-test--insert-live-chat-input draft))
                   (forward-origin (if (< start end) (1- end) end)))
        (should (equal (emacsvox-agent-shell--live-input-bounds)
                       (cons start end)))
        (dolist
            (case
             `((left-char
                emacsvox-agent-shell--backward-char-around
                ,start ,start "Beginning of input")
               (backward-char
                emacsvox-agent-shell--backward-char-around
                ,start ,start "Beginning of input")
               (right-char
                emacsvox-agent-shell--forward-char-around
                ,forward-origin ,end "End of input")
               (forward-char
                emacsvox-agent-shell--forward-char-around
                ,forward-origin ,end "End of input")))
          (pcase-let ((`(,target ,wrapper ,origin ,destination ,message)
                       case))
            (goto-char origin)
            (let ((ems--interactive-fn-name target)
                  original-called submission artifacts)
              (cl-letf
                  (((symbol-function
                     'emacsvox-agent-shell--submit-text-feedback)
                    (lambda (&rest arguments)
                      (setq submission arguments)))
                   ((symbol-function 'emacsvox-icon)
                    (lambda (&rest arguments)
                      (push (cons 'icon arguments) artifacts)))
                   ((symbol-function 'tts-speak)
                    (lambda (&rest arguments)
                      (push (cons 'speak arguments) artifacts)))
                   ((symbol-function 'message)
                    (lambda (&rest arguments)
                      (push (cons 'message arguments) artifacts))))
                (funcall wrapper
                         (lambda (&rest _)
                           (setq original-called t))))
              (should-not original-called)
              (should (= (point) destination))
              (should-not ems--interactive-fn-name)
              (should-not artifacts)
              (should (= (length submission) 3))
              (should (equal (car submission) message))
              (should
               (equal
                (cadr submission)
                (list :role 'agent-user-prompt
                      :events (list 'boundary-entered))))
              (should (eq (nth 2 submission) 'navigation)))))))))

(ert-deftest emacsvox-agent-shell-live-input-visual-boundaries-read-only-input ()
  "Visual-line boundary motion should omit the prompt and point highlight."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (pcase-let* ((`(,start . ,end)
                  (emacsvox-agent-shell-test--insert-live-chat-input
                   "when editing"))
                 (visual-start (- start (length "Codex> "))))
      (dolist
          (case
           `((beginning-of-visual-line
              emacsvox-agent-shell--beginning-of-visual-line-around
              ,end ,start)
             (end-of-visual-line
              emacsvox-agent-shell--end-of-visual-line-around
              ,start ,end)))
        (pcase-let ((`(,target ,wrapper ,origin ,destination) case))
          (goto-char origin)
          (let ((ems--interactive-fn-name target)
                (emacsvox-show-point t)
                original-called
                submissions)
            (cl-letf
                (((symbol-function
                   'emacsvox-agent-shell--visual-line-source-bounds)
                  (lambda () (cons visual-start end)))
                 ((symbol-function 'tts-speak)
                  (lambda (text)
                    (push
                     (list (substring-no-properties text)
                           emacsvox-show-point
                           emacsvox-agent-shell--chat-label-context)
                     submissions))))
              (should
               (eq
                (funcall
                 wrapper
                 (lambda (&rest _)
                   (setq original-called t)
                   (goto-char destination)
                   'moved)
                 1)
                'moved)))
            (should original-called)
            (should (= (point) destination))
            (should-not ems--interactive-fn-name)
            (should
             (equal submissions '(("when editing" nil nil))))))))))

(ert-deftest emacsvox-agent-shell-visual-input-boundaries-keep-normal-scope ()
  "Visual-line boundary adapters should leave other buffers to core speech."
  (with-temp-buffer
    (insert "ordinary text")
    (dolist
        (case
         '((beginning-of-visual-line
            emacsvox-agent-shell--beginning-of-visual-line-around)
           (end-of-visual-line
            emacsvox-agent-shell--end-of-visual-line-around)))
      (pcase-let ((`(,target ,wrapper) case))
        (let ((ems--interactive-fn-name target)
              original-called
              manually-spoken)
          (cl-letf (((symbol-function 'tts-speak)
                     (lambda (&rest _)
                       (setq manually-spoken t))))
            (should
             (eq
              (funcall wrapper
                       (lambda (&rest _)
                         (setq original-called t)
                         'moved)
                       1)
              'moved)))
          (should original-called)
          (should-not manually-spoken)
          (should (eq ems--interactive-fn-name target)))))))

(ert-deftest emacsvox-agent-shell-historical-input-skips-hidden-prompt-source ()
  "Character motion should cross a displayed Me prompt without artifacts."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Codex"))))
     agent-shell-chat--labeled t)
    (insert "Earlier response\n\n")
    (let ((prompt-start (point)))
      (insert
       (propertize
        "Codex> " 'font-lock-face
        '(comint-highlight-prompt comint-highlight-prompt)))
      (let ((input-start (point)))
        (insert "yes\n")
        (insert
         (propertize
          "<shell-maker-end-of-prompt>"
          'invisible t 'shell-maker--marker t)
         "\nAgent response")
        (agent-shell-chat--relabel)
        (let ((prompt-overlay
               (seq-find
                (lambda (overlay)
                  (eq (overlay-get overlay 'category)
                      'agent-shell-chat-me))
                (overlays-at prompt-start))))
          (should prompt-overlay)
          (should (equal (overlay-get prompt-overlay 'display) ""))
          (should (= (overlay-end prompt-overlay) input-start)))
        (cl-labels
            ((move
              (wrapper command origin destination)
              (goto-char origin)
              (let ((ems--interactive-fn-name command)
                    (tts-stop-immediately t)
                    original-called events)
                (cl-letf
                    (((symbol-function 'tts-stop)
                      (lambda (&rest _) (push '(stop) events)))
                     ((symbol-function 'tts-letter)
                      (lambda (&rest arguments)
                        (push (cons 'letter arguments) events)))
                     ((symbol-function 'tts-speak)
                      (lambda (&rest arguments)
                        (push (cons 'speak arguments) events)))
                     ((symbol-function 'tts-dispatch)
                      (lambda (&rest arguments)
                        (push (cons 'dispatch arguments) events)))
                     ((symbol-function 'emacsvox-icon)
                      (lambda (&rest arguments)
                        (push (cons 'icon arguments) events))))
                  (funcall
                   wrapper
                   (lambda (&rest _)
                     (setq original-called t))))
                (should-not original-called)
                (should (= (point) destination))
                (should-not ems--interactive-fn-name)
                (should-not (assq 'icon events))
                (should-not (member '(speak "") events))
                (nreverse events))))
          ;; Going back from `y' skips the hidden "Codex> " source and lands
          ;; on its preceding newline.  Reversing direction reaches and speaks
          ;; `y' in one step rather than emitting an ellipses earcon.
          (dolist
              (case
               `((emacsvox-agent-shell--backward-char-around
                  left-char ,input-start ,(1- prompt-start))
                 (emacsvox-agent-shell--backward-char-around
                  backward-char ,input-start ,(1- prompt-start))))
            (pcase-let ((`(,wrapper ,command ,origin ,destination) case))
              (should
               (assq 'dispatch
                     (move wrapper command origin destination)))))
          (dolist
              (case
               `((emacsvox-agent-shell--forward-char-around
                  right-char ,(1- prompt-start) ,input-start)
                 (emacsvox-agent-shell--forward-char-around
                  forward-char ,(1- prompt-start) ,input-start)))
            (pcase-let ((`(,wrapper ,command ,origin ,destination) case))
              (should
               (member '(letter "y")
                       (move wrapper command origin destination))))))))))

(ert-deftest emacsvox-agent-shell-horizontal-motion-keeps-normal-scope ()
  "The live-input guard should leave ordinary horizontal motion untouched."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (pcase-let* ((`(,start . ,end)
                  (emacsvox-agent-shell-test--insert-live-chat-input "draft")))
      (dolist
          (case
           `((left-char emacsvox-agent-shell--backward-char-around ,(1+ start))
             (backward-char
              emacsvox-agent-shell--backward-char-around ,(1+ start))
             (right-char emacsvox-agent-shell--forward-char-around ,start)
             (forward-char emacsvox-agent-shell--forward-char-around ,start)))
        (pcase-let ((`(,target ,wrapper ,origin) case))
          (goto-char origin)
          (let ((ems--interactive-fn-name target)
                original-called submission)
            (cl-letf
                (((symbol-function
                   'emacsvox-agent-shell--submit-text-feedback)
                  (lambda (&rest arguments)
                    (setq submission arguments))))
              (should
               (eq
                (funcall wrapper
                         (lambda (&rest _)
                           (setq original-called t)
                           'moved))
                'moved)))
            (should original-called)
            (should-not submission)
            ;; Leave the marker for core character speech to consume.
            (should (eq ems--interactive-fn-name target)))))
      ;; A point in the historical transcript is outside the live input.
      (goto-char (point-min))
      (let ((ems--interactive-fn-name 'left-char)
            original-called)
        (emacsvox-agent-shell--backward-char-around
         (lambda (&rest _) (setq original-called t)))
        (should original-called)
        (should (eq ems--interactive-fn-name 'left-char)))
      (should (< start end))))
  ;; The same advice is globally installed, so mode scoping is essential.
  (with-temp-buffer
    (insert "ordinary")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'right-char)
          original-called)
      (emacsvox-agent-shell--forward-char-around
       (lambda (&rest _) (setq original-called t)))
      (should original-called)
      (should (eq ems--interactive-fn-name 'right-char)))))

(ert-deftest emacsvox-agent-shell-chat-navigation-is-directionally-symmetric ()
  "Synthetic chat rows should not duplicate or mislabel upward speech."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Codex"))))
     agent-shell-chat--labeled t)
    (let (prompt-start question-start question-end
          marker-start thought-start thought-end)
      (setq prompt-start (point))
      (insert
       (propertize
        "Codex> " 'font-lock-face
        '(comint-highlight-prompt comint-highlight-prompt)))
      (setq question-start (point))
      (insert "where were we?")
      (setq question-end (point))
      (insert "\n")
      (setq marker-start (point))
      (insert
       (propertize
        "<shell-maker-end-of-prompt>"
        'invisible t 'shell-maker--marker t)
       "\n\n")
      (setq thought-start (point))
      (insert "▶ Thought")
      (setq thought-end (point))
      (agent-shell-chat--relabel)
      (cl-labels
          ((speech-for
            (start end)
            (let ((emacsvox-agent-shell--chat-label-context
                   (emacsvox-agent-shell--chat-label-context-between
                    start end))
                  (emacsvox-agent-shell--vertical-navigation-active-p t))
              (unless
                  (emacsvox-agent-shell--synthetic-agent-row-p start end)
                (substring-no-properties
                 (emacsvox-agent-shell--prepare-speech-text
                  (buffer-substring start end)))))))
        ;; Downward motion lands directly on each content row.
        (should
         (equal
          (mapcar
           (lambda (bounds) (speech-for (car bounds) (cdr bounds)))
           (list
            (cons question-start question-end)
            (cons thought-start thought-end)))
          '("Me. where were we?" "Codex. ▶ Thought")))
        ;; Upward motion also visits the hidden marker span that backs the
        ;; agent label.  It must not repeat Thought.
        (should
         (equal
          (delq
           nil
           (mapcar
            (lambda (bounds) (speech-for (car bounds) (cdr bounds)))
            (list
             (cons thought-start thought-end)
             (cons marker-start thought-end)
             (cons prompt-start question-end))))
          '("Codex. ▶ Thought" "Me. where were we?"))))
      (let ((emacsvox-agent-shell--vertical-navigation-active-p t)
            called)
        (goto-char marker-start)
        (cl-letf
            (((symbol-function 'beginning-of-visual-line)
              (lambda (&rest _) (goto-char marker-start)))
             ((symbol-function 'end-of-visual-line)
              (lambda (&rest _) (goto-char thought-end))))
          (emacsvox-agent-shell--speak-visual-line-around
           (lambda (&rest _) (setq called t))))
        (should-not called)))))

(ert-deftest emacsvox-agent-shell-chat-navigation-skips-hidden-marker-row ()
  "One vertical command should cross the hidden prompt marker and speak."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Codex"))))
     agent-shell-chat--labeled t)
    (let (prompt-start question-start question-end marker-start thought-start)
      (setq prompt-start (point))
      (insert
       (propertize
        "Codex> "
        'font-lock-face '(comint-highlight-prompt comint-highlight-prompt)
        'field 'output
        'inhibit-line-move-field-capture t))
      (setq question-start (point))
      (insert "where were we?")
      (setq question-end (point))
      (insert (propertize "\n" 'field 'boundary))
      (setq marker-start (point))
      (insert
       (propertize
        "<shell-maker-end-of-prompt>"
        'field 'output
        'inhibit-line-move-field-capture t
        'invisible t
        'shell-maker--marker t)
       (propertize
        "\n"
        'field 'output
        'inhibit-line-move-field-capture t))
      (setq thought-start (point))
      (insert (propertize "▶ Thought" 'field 'output))
      (agent-shell-chat--relabel)
      (let ((visual-line-mode nil)
            (line-move-visual nil))
        (cl-labels
            ((move-through-marker
              (wrapper direction origin)
              (goto-char origin)
              (let ((ems--interactive-fn-name
                     (if (eq direction 'backward)
                         'previous-line
                       'next-line))
                    result spoken)
                (cl-letf
                    (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _)
                        (setq spoken
                              (emacsvox-agent-shell--prepare-speech-text
                               text)))))
                  (setq result
                        (funcall
                         wrapper
                         (lambda (&rest _)
                           (goto-char marker-start)
                           'moved)
                         1)))
                (list result (point) spoken))))
          (pcase-let ((`(,result ,destination ,spoken)
                       (move-through-marker
                        #'emacsvox-agent-shell--previous-line-around
                        'backward thought-start)))
            (should (eq result 'moved))
            (should (<= prompt-start destination question-end))
            (should
             (equal
              (substring-no-properties spoken)
              "Me. where were we?")))
          (pcase-let ((`(,result ,destination ,spoken)
                       (move-through-marker
                        #'emacsvox-agent-shell--next-line-around
                        'forward question-start)))
            (should (eq result 'moved))
            (should (= destination thought-start))
            (should
             (equal
              (substring-no-properties spoken)
              "Codex. ▶ Thought"))))))))

(ert-deftest emacsvox-agent-shell-chat-navigation-preserves-prompt-rows ()
  "Skip a repeated Me alias without skipping wrapped or explicit rows."
  (skip-unless (require 'agent-shell-chat-mode nil t))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     agent-shell--state
     '((:agent-config . ((:mode-line-name . "Codex"))))
     agent-shell-chat--labeled t)
    (insert "Earlier response\n\n")
    (let (prompt-start question-start first-row-end continuation-start
          question-end second-line-start second-line-end alias-point
          marker-start marker-end thought-start thought-end)
      (setq prompt-start (point))
      (insert
       (propertize
        "Codex> " 'font-lock-face
        '(comint-highlight-prompt comint-highlight-prompt)))
      (setq question-start (point))
      (insert "first visual row")
      (setq first-row-end (point))
      (insert " ")
      (setq continuation-start (point))
      (insert "wrapped continuation")
      (setq question-end (point)
            alias-point (+ question-start 5))
      (insert "\n")
      (setq second-line-start (point))
      (insert "explicit second line")
      (setq second-line-end (point))
      (insert "\n")
      (setq marker-start (point))
      (insert
       (propertize
        "<shell-maker-end-of-prompt>"
        'invisible t 'shell-maker--marker t))
      (setq marker-end (point))
      (insert "\n")
      (setq thought-start (point))
      (insert "▶ Thought")
      (setq thought-end (point))
      (agent-shell-chat--relabel)
      (should
       (seq-find
        (lambda (overlay)
          (eq (overlay-get overlay 'category)
              'agent-shell-chat-me-label))
        (overlays-in (1- prompt-start) prompt-start)))
      ;; Model the live geometry: the display alias and first content row share
      ;; source bounds, followed by a distinct short continuation and another
      ;; explicit input line before the hidden prompt marker.
      (let ((visual-line-mode t)
            (line-move-visual t))
        (cl-labels
            ((visual-bounds
              (position)
              (cond
               ((<= position first-row-end)
                (cons prompt-start first-row-end))
               ((<= position question-end)
                (cons continuation-start question-end))
               ((<= position second-line-end)
                (cons second-line-start second-line-end))
               ((< position thought-start)
                (cons marker-start marker-end))
               (t
                (cons thought-start thought-end))))
             (move-and-speak
              (wrapper command origin destination)
              (goto-char origin)
              (let ((ems--interactive-fn-name command)
                    spoken)
                (cl-letf
                    (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _)
                        (setq spoken
                              (substring-no-properties
                               (emacsvox-agent-shell--prepare-speech-text
                                text))))))
                  (should
                   (eq
                    (funcall
                     wrapper
                     (lambda (&rest _)
                       (goto-char destination)
                       'moved)
                     1)
                    'moved)))
                (list (point) spoken))))
          (cl-letf
              (((symbol-function 'beginning-of-visual-line)
                (lambda (&rest _)
                  (goto-char (car (visual-bounds (point))))))
               ((symbol-function 'end-of-visual-line)
                (lambda (&rest _)
                  (goto-char (cdr (visual-bounds (point)))))))
            ;; Down visits the wrapped continuation, explicit line, then agent.
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--next-line-around
               'next-line prompt-start alias-point)
              (list continuation-start "wrapped continuation")))
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--next-line-around
               'next-line continuation-start second-line-start)
              (list second-line-start "explicit second line")))
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--next-line-around
               'next-line second-line-start marker-start)
              (list thought-start "Codex. ▶ Thought")))
            ;; Up returns through the same rows in reverse order.
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--previous-line-around
               'previous-line thought-start marker-start)
              (list second-line-end "explicit second line")))
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--previous-line-around
               'previous-line second-line-start question-end)
              (list question-end "wrapped continuation")))
            (should
             (equal
              (move-and-speak
               #'emacsvox-agent-shell--previous-line-around
               'previous-line continuation-start alias-point)
              (list alias-point "Me. first visual row")))))))))

(ert-deftest emacsvox-agent-shell-chat-label-lookup-scales-by-property-run ()
  "Chat label discovery should not inspect every character on long lines."
  (with-temp-buffer
    (insert (make-string 10000 ?x))
    (let ((original-get-text-property
           (symbol-function 'get-text-property))
          (property-reads 0))
      (cl-letf
          (((symbol-function 'get-text-property)
            (lambda (&rest arguments)
              (cl-incf property-reads)
              (apply original-get-text-property arguments))))
        (should-not (emacsvox-agent-shell--chat-label-context-at-point)))
      (should (= property-reads 0)))
    (add-text-properties
     (1- (point-max)) (point-max) '(face agent-shell-prompt))
    (let ((me-overlay (make-overlay (point-min) (point-max)))
          (agent-overlay (make-overlay (point-min) (point-max)))
          (original-get-text-property
           (symbol-function 'get-text-property))
          (property-reads 0))
      (overlay-put me-overlay 'category 'agent-shell-chat-me)
      (overlay-put me-overlay 'display "Me> ")
      (overlay-put agent-overlay 'category 'agent-shell-chat-agent)
      (overlay-put agent-overlay 'before-string "Claude> ")
      (cl-letf
          (((symbol-function 'get-text-property)
            (lambda (&rest arguments)
              (cl-incf property-reads)
              (apply original-get-text-property arguments))))
        (should
         (equal (emacsvox-agent-shell--chat-label-context-at-point)
                '(:category agent-shell-chat-me :text "Me>"))))
      (should (<= property-reads 4)))))

(ert-deftest emacsvox-agent-shell-ui-face-voices-are-explicit ()
  "Configured faces should resolve to their declared voice personalities."
  (dolist (entry emacsvox-agent-shell--ui-face-voice-map)
    (should
     (eq (voice-setup-get-voice-for-face (car entry)) (cadr entry))))
  (dolist (face emacsvox-agent-shell--ui-unvoiced-faces)
    (should-not (voice-setup-get-voice-for-face face))))

(ert-deftest emacsvox-agent-shell-status-faces-have-semantic-contrast ()
  "Rendered status faces should distinguish success, busy, failure and wait."
  (dolist (entry
           '((agent-shell-success . voice-brighten-extra)
             (agent-shell-warning . voice-brighten)
             (agent-shell-error . voice-bolden-and-animate)
             (agent-shell-pending . voice-monotone-extra)))
    (with-temp-buffer
      (insert (propertize "status" 'face (car entry)))
      (goto-char (point-min))
      (should (eq (tts-get-style) (cdr entry))))))

(ert-deftest emacsvox-agent-shell-rendered-plan-speaks-semantic-statuses ()
  "Rendered plan icons should become voiced status words in speech copies."
  (let ((agent-shell-status-kind-label-function
         #'agent-shell--inverse-icon-status-kind-label))
    (with-temp-buffer
      (setq major-mode 'agent-shell-mode)
      (let* ((rendered
              (agent-shell--format-plan
               '(((status . "pending") (content . "Wait step"))
                 ((status . "in_progress") (content . "Busy step"))
                 ((status . "completed") (content . "Done step"))
                 ((status . "failed") (content . "Failed step")))))
             (spoken
              (emacsvox-agent-shell--prepare-speech-text rendered)))
        (should
         (equal
          (substring-no-properties rendered)
          "[◔] Wait step\n[◔] Busy step\n[✓] Done step\n[✗] Failed step"))
        (should
         (equal
          (substring-no-properties spoken)
          (concat
           "[ pending ] Wait step\n[ in progress ] Busy step\n"
           "[ completed ] Done step\n[ failed ] Failed step")))
        (should (string-match-p "◔" rendered))
        (should-not (string-match-p "[◔…✓✗]" spoken))
        (let ((position (string-match "pending" spoken)))
          (should position)
          (should
           (text-property-not-all
            position (+ position (length "pending"))
            'font-lock-face nil spoken)))))))

(ert-deftest emacsvox-agent-shell-status-speech-is-scoped-and-customizable ()
  "Only faced status icons should use the customizable semantic label."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let* ((emacsvox-agent-shell-status-speech-labels
            '((pending . "waiting")))
           (rendered
            (concat
             (propertize "…" 'font-lock-face 'agent-shell-pending)
             " ordinary …"))
           (spoken
            (emacsvox-agent-shell--prepare-speech-text rendered)))
      (should (equal (substring-no-properties spoken)
                     " waiting  ordinary …"))
      (should (equal (substring-no-properties rendered)
                     "… ordinary …")))))

(ert-deftest emacsvox-agent-shell-speech-omits-fragment-visual-chrome ()
  "Line speech should omit fold and thought icons without changing source."
  (with-temp-buffer
    (let ((label
           (concat
            "✶ "
            (propertize
             "Thinking" 'font-lock-face 'agent-shell-section-heading))))
      (agent-shell-ui-update-fragment
       (agent-shell-ui-make-fragment-model
        :namespace-id "1" :block-id "1-agent_thought_chunk"
       :label-left label :body "Reasoning")
       :expanded nil)
      (setq major-mode 'agent-shell-mode)
      (goto-char (point-min))
      (search-forward "Thinking")
      (goto-char (match-beginning 0))
      (let* ((source
              (buffer-substring
               (line-beginning-position) (line-end-position)))
             (spoken (emacsvox-agent-shell--prepare-speech-text source)))
        (should (equal (substring-no-properties source) "▶ ✶ Thinking"))
        (should (equal (substring-no-properties spoken) "Thinking"))
        (should
         (eq
          (get-text-property 0 'font-lock-face spoken)
          'agent-shell-section-heading))
        (should (string-match-p "[▶✶]" source))
        (should-not (string-match-p "[▶✶]" spoken))))))

(ert-deftest emacsvox-agent-shell-speech-omits-source-copy-chrome ()
  "Continuous line speech should not send the source copy glyph to TTS."
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (search-forward "⧉")
    (let* ((source
            (buffer-substring
             (line-beginning-position) (line-end-position)))
           (spoken (emacsvox-agent-shell--prepare-speech-text source)))
      (should (string-match-p "⧉" source))
      (should-not (string-match-p "⧉" spoken))
      (should (equal (string-trim (substring-no-properties spoken))
                     "elisp")))))

(ert-deftest emacsvox-agent-shell-visual-chrome-filter-is-property-scoped ()
  "Ordinary matching Unicode characters should remain available to speech."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (let ((text "▶ ✶ Thinking"))
      (should (eq (emacsvox-agent-shell--prepare-speech-text text) text)))))

(ert-deftest emacsvox-agent-shell-transforms-before-native-preparation ()
  "Native Agent Shell text is transformed once before plans are frozen."
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (setq-local
     emacsvox-aural-source-transform-function
     #'emacsvox-agent-shell--prepare-speech-text)
    (let* ((emacsvox-agent-shell--chat-label-context
            '(:category agent-shell-chat-me :text "Me"))
           (context
            '(:module agent-shell
              :mode agent-shell-mode
              :mode-lineage (agent-shell-mode comint-mode)
              :occasion navigation
              :face-presentation-enabled t
              :voice-lock-enabled nil
              :icons-enabled nil))
           spoken
           submission)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (setq spoken text))))
        (setq
         submission
         (emacsvox-aural-submit
          "hello" :facts '(:role agent-response) :context context)))
      (should
       (equal
        (substring-no-properties
         (emacsvox-aural-submission-content submission))
        "Me. hello"))
      (should (emacsvox-aural-prepared-text-p spoken))
      (should (equal (substring-no-properties spoken) "Me. hello"))
      (let (adapted)
        (emacsvox-agent-shell--tts-speak-around
         (lambda (text) (setq adapted text)) spoken)
        (should (eq adapted spoken))
        (should (emacsvox-aural-prepared-text-p adapted))
        (should
         (equal (substring-no-properties adapted) "Me. hello"))))))

(ert-deftest emacsvox-agent-shell-markdown-face-inventory-is-current ()
  "Every current agent-shell Markdown face should be classified."
  (let ((configured
         (sort
          (append
           (mapcar #'car emacsvox-agent-shell--markdown-face-voice-map)
           emacsvox-agent-shell--markdown-unvoiced-faces
           nil)
          (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
        (current
         (sort
          (seq-filter
           (lambda (face)
             (string-prefix-p "agent-shell-markdown-" (symbol-name face)))
           (face-list))
          (lambda (a b) (string< (symbol-name a) (symbol-name b))))))
    (should (equal configured current))
    (should (= 19 (length configured)))
    (dolist (face configured)
      (should (facep face)))))

(ert-deftest emacsvox-agent-shell-markdown-face-voices-are-explicit ()
  "Markdown faces should resolve to declared or intentionally plain voices."
  (dolist (entry emacsvox-agent-shell--markdown-face-voice-map)
    (should
     (eq (voice-setup-get-voice-for-face (car entry)) (cadr entry))))
  (dolist (face emacsvox-agent-shell--markdown-unvoiced-faces)
    (should-not (voice-setup-get-voice-for-face face))))

(ert-deftest emacsvox-agent-shell-rendered-markdown-has-semantic-voices ()
  "Actual agent-shell Markdown output should retain the configured voices."
  (with-temp-buffer
    (insert
     (concat
      "# Heading one\n## Heading two\n### Heading three\n"
      "#### Heading four\n##### Heading five\n###### Heading six\n\n"
      "**bold** *italic* ~~obsolete~~ `inline` "
      "[link](https://example.test)\n\n> quotation\n\n"
      "```elisp\n(message hello)\n```\n\n"
      "| Name | Value |\n| --- | --- |\n| One | 1 |\n| Two | 2 |\n"))
    (agent-shell-markdown-replace-markup)
    (let ((case-fold-search nil))
      (dolist
          (entry
           '(("Heading one" . voice-brighten)
             ("Heading two" . voice-animate)
             ("Heading three" . voice-lighten)
             ("Heading four" . voice-smoothen)
             ("Heading five" . voice-monotone)
             ("Heading six" . voice-monotone-extra)
             ("bold" . voice-bolden)
             ("italic" . voice-animate)
             ("obsolete" . voice-annotate)
             ("inline" . voice-monotone-extra)
             ("link" . voice-bolden)
             ("quotation" . voice-lighten)
             ("elisp" . voice-smoothen)
             ("message" . voice-monotone-extra)
             ("Name" . voice-bolden)
             ("│" . inaudible)
             ("Two" . nil)))
        (goto-char (point-min))
        (should (search-forward (car entry) nil t))
        (goto-char (match-beginning 0))
        (should (eq (tts-get-style) (cdr entry)))
        (should (equal (get-text-property (point) 'face)
                       (get-text-property (point) 'font-lock-face)))))))

(ert-deftest emacsvox-agent-shell-speech-copy-bypasses-plain-yank-handler ()
  "Speech copies should retain rendered faces without changing normal paste."
  (with-temp-buffer
    (insert "# Heading\n\n| Name | Value |\n| --- | --- |\n| One | 1 |\n")
    (agent-shell-markdown-replace-markup)
    (let ((rendered (buffer-string)))
      (should (eq (emacsvox-agent-shell--prepare-speech-text rendered)
                  rendered))
      (setq major-mode 'agent-shell-mode)
      (let ((spoken
             (emacsvox-agent-shell--prepare-speech-text rendered)))
        (should
         (text-property-not-all
          0 (length rendered) 'yank-handler nil rendered))
        (should-not
         (text-property-not-all
          0 (length spoken) 'yank-handler nil spoken))
        (should
         (eq (emacsvox-agent-shell-test--face-at-text spoken "Heading")
             'agent-shell-markdown-header-1))
        (should
         (eq (emacsvox-agent-shell-test--face-at-text spoken "│")
             'agent-shell-markdown-table-border))
        ;; Preparing speech must not change agent-shell's clipboard contract.
        (should
         (text-property-not-all
          0 (length (buffer-string)) 'yank-handler nil (buffer-string)))
        ;; Exercise the same copy primitive used by `tts-speak'.
        (with-temp-buffer
          (let ((yank-excluded-properties tts-yank-excluded-properties))
            (insert-for-yank spoken))
          (goto-char (point-min))
          (should (eq (tts-get-style) 'voice-brighten)))))))

(ert-deftest emacsvox-agent-shell-disable-cleans-existing-buffer-state ()
  "Disabling support should cancel pending work in existing shell buffers."
  (let ((buffer (generate-new-buffer " *agent-shell-cleanup-test*"))
        (saved-hook agent-shell-mode-hook)
        (saved-advice (emacsvox-agent-shell-test--saved-advice-state))
        state timer fired)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode)
            (setq state
                  (list (cons :buffer buffer)
                        (cons :event-subscriptions nil)))
            (setq-local agent-shell--state state)
            (setq-local emacsvox-agent-shell--pending-bodies
                        (make-hash-table :test #'equal))
            (puthash "request-agent_message_chunk" "pending"
                     emacsvox-agent-shell--pending-bodies)
            (setq-local emacsvox-agent-shell--pending-speech-qualified-ids
                        '("request-agent_message_chunk"))
            (setq-local emacsvox-agent-shell--permission-action-cache
                        (make-hash-table :test #'equal))
            (puthash "permission" '((:option . "Allow"))
                     emacsvox-agent-shell--permission-action-cache)
            (setq-local emacsvox-agent-shell--tool-call-status-cache
                        (make-hash-table :test #'equal))
            (puthash "tool" "in_progress"
                     emacsvox-agent-shell--tool-call-status-cache)
            (setq timer (run-with-timer 0.1 nil
                                        (lambda () (setq fired t))))
            (setq-local emacsvox-agent-shell--pending-speech-timer timer))
          (emacsvox-agent-shell-enable)
          (with-current-buffer buffer
            (should (= 4 (length (map-elt
                                  agent-shell--state
                                  :event-subscriptions))))
            (should
             (eq emacsvox-aural-source-transform-function
                 #'emacsvox-agent-shell--prepare-speech-text))
            (should (memq #'emacsvox-agent-shell--buffer-cleanup
                          kill-buffer-hook))
            (should (memq #'emacsvox-agent-shell--buffer-cleanup
                          change-major-mode-hook))
            (should
             (memq #'emacsvox-agent-shell--record-response-section
                   agent-shell-section-functions))
            (should
             (memq #'emacsvox-agent-shell--table-navigation-post-command
                   post-command-hook)))
          (emacsvox-agent-shell-disable)
          (emacsvox-agent-shell-disable)
          (sit-for 0.15)
          (should-not fired)
          (with-current-buffer buffer
            (should-not
             (local-variable-p
              'emacsvox-aural-source-transform-function))
            (should-not emacsvox-agent-shell--pending-speech-timer)
            (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
            (should-not emacsvox-agent-shell--pending-bodies)
            (should-not emacsvox-agent-shell--response-turn-active-p)
            (should-not emacsvox-agent-shell--permission-subscription)
            (should-not
             emacsvox-agent-shell--permission-response-subscription)
            (should-not emacsvox-agent-shell--permission-action-cache)
            (should-not emacsvox-agent-shell--lifecycle-subscription)
            (should-not emacsvox-agent-shell--tool-call-subscription)
            (should-not emacsvox-agent-shell--tool-call-status-cache)
            (should-not (map-elt agent-shell--state
                                 :event-subscriptions))
            (should-not (memq #'emacsvox-agent-shell--buffer-cleanup
                              kill-buffer-hook))
            (should-not (memq #'emacsvox-agent-shell--buffer-cleanup
                              change-major-mode-hook))
            (should-not
             (memq #'emacsvox-agent-shell--record-response-section
                   agent-shell-section-functions))
            (should-not
             (memq #'emacsvox-agent-shell--table-navigation-post-command
                   post-command-hook))))
      (when (timerp timer)
        (cancel-timer timer))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (setq agent-shell-mode-hook saved-hook)
      (emacsvox-agent-shell-test--restore-advice-state saved-advice))))

(ert-deftest emacsvox-agent-shell-mode-change-cleans-buffer-state ()
  "Changing major mode should cancel timers and remove subscriptions."
  (let ((buffer (generate-new-buffer " *agent-shell-mode-cleanup-test*"))
        state timer fired)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode)
            (setq state
                  (list (cons :buffer buffer)
                        (cons :event-subscriptions nil)))
            (setq-local agent-shell--state state)
            (emacsvox-agent-shell--buffer-setup)
            (setq timer (run-with-timer 0.1 nil
                                        (lambda () (setq fired t))))
            (setq-local emacsvox-agent-shell--pending-speech-timer timer
                        emacsvox-agent-shell--pending-speech-qualified-ids
                        '("pending"))
            (setq-local emacsvox-agent-shell--pending-bodies
                        (make-hash-table :test #'equal))
            (puthash "pending" "text"
                     emacsvox-agent-shell--pending-bodies)
            (should
             (eq emacsvox-aural-source-transform-function
                 #'emacsvox-agent-shell--prepare-speech-text))
            (should
             (memq #'emacsvox-agent-shell--record-response-section
                   agent-shell-section-functions))
            (fundamental-mode))
          (sit-for 0.15)
          (should-not fired)
          (should-not (map-elt state :event-subscriptions))
          (with-current-buffer buffer
            (should-not
             (local-variable-p
              'emacsvox-aural-source-transform-function))
            (should-not emacsvox-agent-shell--pending-speech-timer)
            (should-not emacsvox-agent-shell--pending-speech-qualified-ids)
            (should-not emacsvox-agent-shell--pending-bodies)
            (should-not emacsvox-agent-shell--response-turn-active-p)
            (should-not
             (memq #'emacsvox-agent-shell--record-response-section
                   agent-shell-section-functions))))
      (when (timerp timer)
        (cancel-timer timer))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-buffer-death-cleans-buffer-state ()
  "Killing a shell buffer should cancel speech and unsubscribe its events."
  (let ((buffer (generate-new-buffer " *agent-shell-kill-cleanup-test*"))
        state timer fired)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq major-mode 'agent-shell-mode)
            (setq state
                  (list (cons :buffer buffer)
                        (cons :event-subscriptions nil)))
            (setq-local agent-shell--state state)
            (emacsvox-agent-shell--buffer-setup)
            (setq timer (run-with-timer 0.1 nil
                                        (lambda () (setq fired t))))
            (setq-local emacsvox-agent-shell--pending-speech-timer timer))
          (kill-buffer buffer)
          (sit-for 0.15)
          (should-not fired)
          (should-not (map-elt state :event-subscriptions)))
      (when (timerp timer)
        (cancel-timer timer))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-agent-shell-end-to-end-vocabulary-is-registered ()
  "Every Agent Shell presentation category has registered intent."
  (dolist
      (id
       '(agent-user-prompt agent-plan agent-block agent-source-block
         agent-table agent-table-cell agent-viewport agent-prompt-editor
         agent-error agent-block-kind agent-tool-status agent-table-row
         agent-table-column agent-source-language agent-speech-level
         agent-viewport-mode agent-prompt-disposition
         agent-permission-result agent-session-opened
         agent-session-interrupted agent-setting-changed
         agent-content-inspected agent-content-copied agent-table-entered
         agent-table-exited agent-viewport-opened agent-viewport-refreshed
         agent-prompt-opened agent-prompt-submitted agent-prompt-cancelled
         agent-tool-status-changed agent-permission-requested
         agent-permission-resolved))
    (should (emacsvox-aural-semantic id))))

(ert-deftest emacsvox-agent-shell-content-categories-carry-specific-intent ()
  "Turn content must expose its role before compatibility output."
  (dolist
      (entry
       '((agent-message . agent-response)
         (user-message . agent-user-prompt)
         (thought . agent-thought)
         (tool-call . agent-tool)
         (permission . permission-request)
         (plan . agent-plan)
         (error . agent-error)
         (unknown . agent-block)))
    (should
     (eq
      (plist-get
       (emacsvox-agent-shell-content-facts (car entry))
       :role)
      (cdr entry))))
  (let* ((presentations
          (emacsvox-agent-shell-test--capture-presentations
            (let ((emacsvox-agent-shell-speech-level 'full))
              (emacsvox-agent-shell--speak-content "One step" 'plan))))
         (presentation (car presentations)))
    (should (eq (car presentation) 'submit))
    (should (eq (plist-get (nth 2 presentation) :role) 'agent-plan))
    (should (eq (nth 3 presentation) 'agent-shell))
    (should (eq (nth 4 presentation) 'continuous))
    (should (eq (plist-get (nth 5 presentation) :module) 'agent-shell))))

(ert-deftest emacsvox-agent-shell-source-block-presentation-is-complete ()
  "Source-block inspection carries role, language, module, and occasion."
  (emacsvox-agent-shell-test--with-rendered-source-blocks
    (setq major-mode 'agent-shell-mode)
    (goto-char (point-min))
    (search-forward "(message")
    (backward-char (length "(message"))
    (let* ((presentations
            (emacsvox-agent-shell-test--capture-presentations
              (emacsvox-agent-shell-speak-source-block)))
           (presentation (car presentations))
           (facts (nth 2 presentation)))
      (should (eq (plist-get facts :role) 'agent-source-block))
      (should
       (equal (plist-get facts :events) '(agent-content-inspected)))
      (should (equal (plist-get facts :agent-source-language) "elisp"))
      (should (eq (nth 3 presentation) 'agent-shell))
      (should (eq (nth 4 presentation) 'inspection)))))

(ert-deftest emacsvox-agent-shell-table-presentation-is-complete ()
  "Table-cell navigation carries logical coordinates and source context."
  (emacsvox-agent-shell-test--with-rendered-table
      "| Name | Role |\n|---|---|\n| Alice | Engineer |\n"
    (goto-char (point-min))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (let* ((presentations
            (emacsvox-agent-shell-test--capture-presentations
              (emacsvox-agent-shell--table-cell-feedback)))
           (presentation (car presentations))
           (facts (nth 2 presentation)))
      (should (= (length presentations) 1))
      (should (eq (car presentation) 'submit))
      (should (eq (plist-get facts :role) 'agent-table-cell))
      (should (equal (plist-get facts :events) '(focus-entered)))
      (should (= (plist-get facts :agent-table-row) 1))
      (should (= (plist-get facts :agent-table-column) 1))
      (should (eq (nth 4 presentation) 'navigation)))))

(ert-deftest emacsvox-agent-shell-table-commands-use-native-submissions ()
  "Explicit table inspection, copy, and settings should submit natively."
  (emacsvox-agent-shell-test--with-rendered-table
      "| Name | Role |\n|---|---|\n| Alice | Engineer |\n"
    (goto-char (point-min))
    (search-forward "Engineer")
    (backward-char (length "Engineer"))
    (let ((emacsvox-agent-shell-table-data-position 'first)
          (emacsvox-agent-shell-table-titles '(column row))
          (kill-ring nil)
          (kill-ring-yank-pointer nil))
      (let ((presentations
             (emacsvox-agent-shell-test--capture-presentations
               (emacsvox-agent-shell-table-speak-context)
               (emacsvox-agent-shell-table-speak-dimensions)
               (emacsvox-agent-shell-table-speak-row)
               (emacsvox-agent-shell-table-speak-column)
               (emacsvox-agent-shell-table-copy-cell)
               (cl-letf (((symbol-function 'read-char-choice)
                          (lambda (&rest _) ?c)))
                 (emacsvox-agent-shell-table-select-speaking-method)))))
        (should (= (length presentations) 6))
        (should
         (equal (mapcar #'car presentations)
                '(submit submit submit submit submit submit)))
        (dolist (presentation presentations)
          (should (eq (nth 3 presentation) 'agent-shell))
          (should (memq (nth 4 presentation)
                        '(inspection state-change))))))))

(ert-deftest emacsvox-agent-shell-tool-presentation-is-complete ()
  "Tool transitions expose status intent before their compatibility cue."
  (let ((emacsvox-agent-shell-speak-tool-calls t)
        (emacsvox-agent-shell-tool-output-verbosity 'status)
        (emacsvox-agent-shell-foreground-speech-level 'full))
    (with-temp-buffer
      (let* ((presentations
              (emacsvox-agent-shell-test--capture-presentations
                (emacsvox-agent-shell--handle-tool-call-update
                 (emacsvox-agent-shell-test--tool-call-event
                  "reader" "in_progress" "Read README"))))
             (presentation (car presentations))
             (facts (nth 2 presentation)))
        (should (eq (plist-get facts :role) 'agent-tool))
        (should
         (equal
          (plist-get facts :events) '(agent-tool-status-changed)))
        (should (eq (plist-get facts :agent-tool-status) 'in-progress))
        (should (eq (nth 4 presentation) 'notification))))))

(ert-deftest emacsvox-agent-shell-viewport-submit-presentation-is-complete ()
  "Viewport submission exposes prompt disposition in one native transaction."
  (let ((agent-shell-prefer-viewport-interaction t)
        (agent-shell-session-strategy 'new-deferred))
    (with-temp-buffer
      (setq major-mode 'agent-shell-viewport-edit-mode)
      (cl-letf
          (((symbol-function
             'agent-shell-viewport-compose-send-and-wait-for-response)
            #'ignore)
           ((symbol-function
             'emacsvox-agent-shell--viewport-submit-disposition)
            (lambda () 'submitted)))
        (let* ((presentations
                (emacsvox-agent-shell-test--capture-presentations
                  (call-interactively
                   #'agent-shell-viewport-compose-send)))
               (presentation (car presentations))
               (facts (nth 2 presentation)))
          (should (= 1 (length presentations)))
          (should (eq (car presentation) 'submit))
          (should (eq (plist-get facts :role) 'agent-prompt-editor))
          (should
           (equal
            (plist-get facts :events) '(agent-prompt-submitted)))
          (should
           (eq (plist-get facts :agent-prompt-disposition) 'submitted))
          (should (eq (nth 4 presentation) 'state-change)))))))

(ert-deftest emacsvox-agent-shell-viewport-controls-are-native ()
  "Viewport display, editing, refresh, and mode feedback submit atomically."
  (cl-letf (((symbol-function 'ems-interactive-p)
             (lambda (&rest _) t))
            ((symbol-function 'emacsvox-agent-shell--brief-session-speech)
             (lambda (&optional _) "Codex agent, viewport 2 of 3, view.")))
    (dolist
        (case
         '((emacsvox-agent-shell--viewport-show-buffer-after
            "Codex agent, viewport 2 of 3, view." navigation)
           (emacsvox-agent-shell--prompt-compose-after
            "Compose prompt" edit)
           (emacsvox-agent-shell--viewport-refresh-after
            "Viewport refreshed" state-change)
           (emacsvox-agent-shell--viewport-view-mode-after
            "Codex agent, viewport 2 of 3, view." state-change)
           (emacsvox-agent-shell--viewport-edit-mode-after
            "Codex agent, viewport 2 of 3, view." state-change)))
      (let* ((presentations
              (emacsvox-agent-shell-test--capture-presentations
                (funcall (car case))))
             (presentation (car presentations)))
        (should (= 1 (length presentations)))
        (should (eq (car presentation) 'submit))
        (should (equal (nth 1 presentation) (cadr case)))
        (should (eq (nth 3 presentation) 'agent-shell))
        (should (eq (nth 4 presentation) (nth 2 case)))))))

(provide 'emacsvox-agent-shell-tests)
;;; emacsvox-agent-shell-tests.el ends here
